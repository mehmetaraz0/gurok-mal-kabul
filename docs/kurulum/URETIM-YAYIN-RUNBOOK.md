# Üretim Yayın Runbook'u

**Yürürlük:** 6 Eylül 2026
**Release owner:** ana geliştirme ajanı (bu oturum)

---

## 0. ÜRETİM YAZMA DONDURMASI

Kullanıcı **açıkça `CANLIYA UYGULA`** demedikçe üretimde hiçbir:

- SQL migration
- `CREATE` / `ALTER` / `DROP`
- `INSERT` / `UPDATE` / `DELETE`
- `GRANT` / `REVOKE`
- deploy / push-to-production
- Supabase şema değişikliği

yapılmaz.

Salt-okuma sorgular, yerel çalışma, konteyner testleri ve staging bu kuralın
dışındadır.

**Neden var:** 6 Eylül 2026'da Phase 0 sertleştirmesi üretime uygulandı ve
kimin uyguladığı tespit edilemedi. Uygulanan sürüm o gün 00:44 civarında
düzeltilmiş olan sürümdü; birkaç saat erken uygulansaydı `giris_kayitlari`
ekranı canlıda tamamen kararacaktı (46 satırın 46'sında `otel_id` NULL).
Sonuç şansa kalmıştı. Bu runbook o şansı ortadan kaldırmak için var.

Başka ajanların üretime yazmaması gerekir. Yazarsa bu dondurmanın anlamı
kalmaz.

---

## 1. Her üretim yayını için zorunlu kayıt

Aşağıdaki tablo **her** üretim dağıtımı için doldurulur ve bu dosyanın
sonundaki geçmişe eklenir. Eksik alan varsa yayın yapılmaz.

| Alan | Açıklama |
|---|---|
| Tarih / saat | ISO 8601, saat dilimiyle (`2026-09-06T14:30:00+03:00`) |
| Release owner | Yayını yürüten ajan/kişi |
| Kullanıcı onayı | `CANLIYA UYGULA` ifadesinin geçtiği mesaj — tarih/saat |
| Git commit hash | Tam hash. Çalışma ağacı **temiz** olmalı |
| Migration dosyası | Repo içindeki tam yol |
| Preflight sonucu | Hangi salt-okuma dosyaları koştu, çıktı özeti |
| Yedek / geri alma | Yedeğin nerede olduğu ve geri alma yolu |
| Uygulama sonucu | Başarılı / hata; hata varsa tam mesaj |
| Smoke test | Hangi ekranlar denendi, sonuç |
| Yayın sonrası parmak izi | `2026-09-06-staging-esitlik-dogrulama.sql` çıktısı |
| Geri alma gerekti mi | Evet/Hayır; evetse ne yapıldı |

---

## 2. Sıra

### 2.1 Onay
Kullanıcının **`CANLIYA UYGULA`** demesi. Başka hiçbir ifade bunun yerine
geçmez ("tamam", "devam", "uygula" yeterli değildir).

### 2.2 Kod donduruldu mu
```bash
git status --short        # boş olmalı
git rev-parse HEAD        # kayda geçecek hash
```
Çalışma ağacı kirliyse yayın yapılmaz: uygulanan şeyin hangi commit olduğu
belirsizleşir. Bu tam olarak 6 Eylül'de yaşanan belirsizliktir.

### 2.2b Statik migration denetimi (2026-09-08'den itibaren zorunlu)
```bash
node scripts/migration-guvenlik-kontrol.mjs
node --test scripts/migration-guvenlik-kontrol.test.mjs
```
İkisi de yeşil olmadan yayın başlamaz. Denetleyici veritabanına bağlanmaz;
yalnız yeni migration dosyalarının ACL/grant standardına uyduğunu ölçer.
Standart: `docs/kurulum/MIGRATION-GUVENLIK-STANDARDI.md`.

Tarihî dosyalar (PMS Adım 1–4 dâhil) varsayılan kapsamda **değildir** ve
CI'ı kırmazlar; bilinen sapmaları standardın 5. bölümünde listelidir.

### 2.3 Yayın öncesi parmak izi (salt-okuma)

Üretimde çalıştırılır, çıktı **kaydedilir** — geri alma gerekirse "öncesi"
fotoğrafı budur. Güncel taban POST-PMS-FAZ1'dir; eski dosyalar yanlış alarm
verir (bkz. "Yeni taban (POST-PMS-FAZ1)" bölümü).

| Ne ölçer | Dosya |
|---|---|
| Şema / politika / fonksiyon parmak izi | `2026-09-07-post-pms-faz1-uretim-parmakizi.sql` |
| Şema eşitliği | `2026-09-07-post-pms-faz1-esitlik-dogrulama.sql` |
| **Varsayılan ACL + fiili anon hakkı** | `2026-09-07-varsayilan-acl-uyari-kontrolu.sql` |

**ACL uyarı kontrolünün karar kriteri D1/D2'dir** (`public` şemasında anon
tablo/sekans hakkı = 0). `B1`/`C1` bilinen platform riskini izler:
büyürlerse yayın durmaz, ama açıklanmadan geçilmez. Ayrıntı:
`2026-09-07-varsayilan-acl-bulgusu.md`.

### 2.4 Yedek
Supabase Dashboard → Database → Backups. Yedeğin tarihi ve saati kayda
geçer. Ücretsiz planda otomatik yedek günlüktür; son yedekten bu yana geçen
süre kayıt altına alınır.

### 2.5 Yerel prova
Migration önce üretimin doğrulanmış kopyasında koşturulur:
```bash
node scripts/dokum-dogrula.mjs \
  docs/kurulum/2026-09-07-post-pms-faz1-sema-dokumu.sql \
  docs/kurulum/2026-09-07-post-pms-faz1-esitlik-dogrulama.sql
```
Ardından migration o kopyaya uygulanıp fark raporu alınır. Beklenmeyen tek
bir fark bile yayını durdurur.

### 2.6 Uygulama
Tek transaction. Hata alırsa tamamı geri döner. Çıktı kaydedilir.

### 2.7 Smoke test

**Ekranın açılması smoke test DEĞİLDİR.** Her yazma maddesi gerçek bir kayıt
gerektirir; "çalışıyor gibi görünüyor" sonuç olarak kabul edilmez. Bu ayrım
6 Eylül 2026'da atlandı (bkz. bölüm 4).

Gerçek kullanıcıyla, gerçek kayıtla:

| Adım | Kanıt |
|---|---|
| Giriş (PIN) ve otel seçimi | oturum açılıyor, doğru otel görünüyor |
| Satın alma talep onay/ret | `talep_onay_gecmisi` yeni satır |
| Mal kabul kaydı | `erp_islem_audit` yeni satır |
| Fatura kaydı | `erp_islem_audit` yeni satır |
| Stok hareketi | `erp_islem_audit` yeni satır |
| Bar sipariş akışı ve QR | `erp_islem_audit` yeni satır |
| Giriş kayıtları | merkez kullanıcıda dolu, otel kullanıcısında boş |

Yazma yollarını topluca doğrula — sayı yayın öncesine göre **artmalı**:

```sql
select count(*) as audit_satiri, max(server_timestamp) as son_kayit
from public.erp_islem_audit;
```

Artmıyorsa ya kayıt gerçekten yazılmadı ya da denetim izi kopmuş. İkisi de
yayının tamamlanmadığı anlamına gelir.

### 2.8 Yayın sonrası parmak izi
2.3'teki dosya tekrar çalıştırılır. Beklenen dışında `SAPMA` varsa geri alma
değerlendirilir.

### 2.9 Kayıt
Aşağıdaki geçmişe satır eklenir ve commit edilir.

---

## 3. Geri alma

Migration tek transaction olduğu için **uygulama sırasındaki** hata kendini
geri alır; kısmi durum oluşmaz.

**Commit sonrası** geri alma farklıdır ve kendiliğinden güvenli değildir:

- Etkilenen yazmaları durdur.
- Korunan denetim kayıtlarını (`erp_islem_audit`) **silme**.
- Yalnızca 2.3'te kaydedilen "öncesi" parmak izinden, gözden geçirilmiş
  tanımları geri yükle.
- Ekranları çalıştırmak uğruna bilinen açık izinleri geri açma.
- Güvenli bir geri yükleme yolu yoksa yazmaları kapalı tut ve ileri doğru
  düzelt.

---

## 4. Yayın geçmişi

| Tarih/saat | Owner | Onay | Commit | Migration | Sonuç |
|---|---|---|---|---|---|
| 2026-09-06, ~00:44–08:32 arası (kesin değil) | **UNKNOWN** | **YOK** | 8a080d3 veya sonrası ile uyumlu | `2026-09-05-phase0-hardening.sql` | Uygulandı; **smoke test EKSİK** — aşağıya bakınız |
| 2026-09-07T20:30–21:05+03:00 | Claude (ajan) + kullanıcı (SQL Editor) | **VAR** — `CANLIYA UYGULA`, 2026-09-07 | `5f0945d` (DB) → `4b131ae` (ön yüz) | PMS Faz 1 Adım 1–4 (4 dosya) | **Başarılı.** Hata yok, geri alma gerekmedi — aşağıya bakınız |
| 2026-09-08 | Kullanıcı (SQL Editor) | **YOK** — ajan öneri olarak sunmuştu, kullanıcı doğrudan çalıştırdı | Sonradan `2026-09-08-pms-fonksiyon-acl-temizligi.sql` ile kayda geçirildi | PMS fonksiyon ACL temizliği (yalnız REVOKE) | **Başarılı.** Uygulama sonrası ölçüldü; hiçbir akış kırılmadı — aşağıya bakınız |

> Bu satır bir uyarı olarak duruyor. Onaysız, sahipsiz ve kayıtsız bir üretim
> değişikliğinin nasıl göründüğünü gösteriyor. Sonraki her satır eksiksiz
> doldurulacak.

### 6 Eylül yayınının smoke test durumu

Bu satır önce "smoke test sonradan yapıldı, sorun çıkmadı" diyordu. **Fazla
iddialıydı; düzeltildi.**

Yapılan: satın alma onay/ret ekranı, giriş kayıtları merkez/otel ayrımı, otel
seçimi ve çapraz otel görünürlüğü, denetim kapsamındaki 7 tablonun ekranları
açıldı ve çalıştığı görüldü. Sorun bildirilmedi.

Yapılmayan: **o 7 tabloya gerçek bir kayıt yazılmadı.** Kanıt —
`select count(*) from public.erp_islem_audit` **0** dönüyor; gerçek bir
INSERT/UPDATE olsaydı tetikleyici satır üretirdi. Ekranın açılması ile kaydın
kaydedilmesi farklı şeylerdir ve bu ayrım sorulmadan "smoke test yapıldı"
yazılmıştı.

Yapısal durum sağlam: 7 tabloda `AFTER INSERT OR UPDATE` tetikleyicisi
`phase0_private.islem_audit()` çağırıyor, devre dışı bırakılmış yok. Ayrıca
sessiz bozulma mümkün değil — audit iş işlemiyle **aynı transaction'da**
olduğu için bozuk olsaydı yazmayı sessizce atlamaz, yazmayı komple düşürürdü.
Yani kalan risk "bozuk olabilir" değil, **"hiç denenmedi"**.

**Kapanma ölçütü:** günlük işte ilk gerçek kayıt açıldıktan sonra
`erp_islem_audit` en az bir satır içermeli. İçermiyorsa gerçek bir sorun var.

**Ders — sonraki yayınlar için:** 2.7'deki smoke test listesi "ekran açıldı"
ile karşılanmaz. Her madde bir **yazma** gerektirir ve yazmanın gerçekleştiği
`erp_islem_audit` üzerinden doğrulanır. "Çalışıyor gibi görünüyor" bir smoke
test sonucu değildir.

---

## 5. PMS Faz 1 yayını — 2026-09-07 (tam kayıt)

Bölüm 1'deki zorunlu alanların tamamı doldurulmuştur.

| Alan | Değer |
|---|---|
| **Tarih / saat** | Veritabanı: `2026-09-07T20:30+03:00` – `2026-09-07T20:50+03:00` (damgalardan ölçüldü: check-in `17:41:14+00`, check-out `17:46:36+00`, folyo kapanışı `17:49:03+00`). Ön yüz push: aynı gün, veritabanı doğrulaması tamamlandıktan sonra. |
| **Release owner** | Claude (ajan) yürüttü ve doğruladı; SQL Editor komutlarını ve ekran işlemlerini kullanıcı çalıştırdı. Ajanın üretim kimlik bilgisi **yoktur**; hiçbir migration ajan tarafından uygulanmadı. |
| **Kullanıcı onayı** | `CANLIYA UYGULA` — kullanıcı mesajı, 2026-09-07. Ön yüz push'u için **ayrı** onay alındı (`PMS FRONTEND RELEASE — COMMIT + PUSH ONAYLI`). |
| **Git commit hash** | Veritabanı yayını: `5f0945da10bb0c2877862674b015422bc2bb684c`. Ön yüz yayını: `4b131ae8bff524c44c11572aa3a7a742da48a0f9`. Her ikisinde de çalışma ağacı **temiz**. |
| **Migration dosyası** | `docs/kurulum/2026-09-06-pms-faz1-oda-tipleri-odalar.sql` (`9c30126139a4…975047`)<br>`docs/kurulum/2026-09-06-pms-faz1-adim2-misafir-rezervasyon.sql` (`ba4f9ad026f7…5df2cd`)<br>`docs/kurulum/2026-09-06-pms-faz1-adim3-checkin-checkout.sql` (`3954dcd1f94d…31e74f`)<br>`docs/kurulum/2026-09-06-pms-faz1-adim4-folio.sql` (`bc9b320359bf…c71ea`)<br>Her dosya uygulanmadan önce SHA256 ile doğrulandı. |
| **Preflight sonucu** | `2026-09-07-pms-yayin-oncesi-preflight.sql` (salt-okuma) → **19/19 geçti, sıfır drift**. PMS nesneleri yok (7/7 sıfır), Adım 1 önkoşulları tam (4/4/1/1/2/3), taban sapmamış (66 tablo / 193 politika / 31 kısıtlayıcı), RLS kapalı tablo 0, `search_path` pinsiz SECURITY DEFINER 0, anon tablo hakkı 0.<br>`2026-09-06-staging-esitlik-dogrulama.sql` → yayın öncesi **SAPMA yok** (26/26 fonksiyon gövdesi eşleşti). |
| **Yedek / geri alma** | **Otomatik günlük yedek, 2026-09-07** (Supabase Pro). Geri alma yolu, tercih sırasıyla: (1) modül `aktif=false` — `auth_yetki_var()` modül aktifliğini şart koştuğu için tüm PMS politikaları anında kapanır; (2) her migration dosyasının sonundaki yorumlu geri alma bloğu, **ters sırada** (Adım 4→3→2→1); (3) yedekten dönüş. **Uyarı:** modül kapatmak bar köprüsünü durdurmaz (SECURITY DEFINER); `pms_bar_folio_koprusu` tetikleyicisi ayrıca düşürülmelidir. **Sınır:** `pms_folio_odemeler` boş değilse Adım 4 geri alınmaz, özellik kapatma tercih edilir. |
| **Uygulama sonucu** | **Başarılı.** Dört migration da tek transaction içinde (`begin`…`commit`) uygulandı, hiçbirinde `ERROR` alınmadı. Her adımın kendi doğrulama bloğu commit öncesi çalıştı ve geçti. Post-check sonuçları: Adım 1 → 5/5, Adım 2 → 6/6, Adım 3 → 5/5, Adım 4 → **10/10**. |
| **Smoke test** | Ekranların açılması smoke test sayılmadı; **gerçek kayıt yazıldı ve geri okundu.** Ayrıntı aşağıda. |
| **Yayın sonrası parmak izi** | **75 tablo · 234 politika · 40 kısıtlayıcı** · RLS kapalı tablo **0** · anon tablo hakkı **0** · `search_path` pinsiz SECURITY DEFINER **0**.<br>Delta doğrulaması: +9 tablo (2+4+3), +41 politika, +9 kısıtlayıcı. **+41'in +45 olmaması append-only'nin kanıtıdır:** `pms_folio_hareketleri` ve `pms_folio_odemeler` yalnız `select`+`insert` alır, `update`/`delete` politikası hiç oluşturulmaz.<br>**Not:** `2026-09-06-staging-esitlik-dogrulama.sql` bundan sonra SAPMA raporlayacaktır — tabanı PMS öncesidir. Yeni taban çıkarılmalı (manifest P3 #7). |
| **Geri alma gerekti mi** | **Hayır.** Hiçbir adımda STOP kriteri tetiklenmedi. |

### Yeni taban (POST-PMS-FAZ1) — 2026-09-07

Bu yayından sonra taban değişti. Sonraki yayınlarda **eski dosyalar
kullanılırsa yanlış alarm** verir; aşağıdaki eşleştirmeye uyun.

| Amaç | Kullanılacak dosya |
|---|---|
| Yayın öncesi üretim parmak izi | `2026-09-07-post-pms-faz1-uretim-parmakizi.sql` |
| Şema eşitlik doğrulaması | `2026-09-07-post-pms-faz1-esitlik-dogrulama.sql` |
| Taban şema dökümü | `2026-09-07-post-pms-faz1-sema-dokumu.sql` |
| Yeni döküm alma | `dokum-al.ps1 -Etiket <tarih-etiket>` |

Yeni taban: **75 tablo · 234 politika · 40 kısıtlayıcı · 28 kapsam fonksiyonu**
· RLS kapalı 0 · `search_path` pinsiz SECURITY DEFINER 0 · anon tablo hakkı 0.

Eski dosyalar (66/193/31/26) **tarihsel kanıt** olarak korunur; PMS öncesi
durumu temsil ederler ve silinmemelidir.

### Smoke test ayrıntısı — üretimde gerçek kayıtlar

| Halka | Kanıt |
|---|---|
| Oda tipi + oda | `std` oda tipi ve oda `101` ekrandan kaydedildi, listede görüldü |
| Misafir | `araz, mehmet` kaydedildi |
| Rezervasyon + otomatik folyo | `R-2026-000001` onaylandı → **`F-2026-000001` kendiliğinden açıldı** |
| Check-in | Oda Planı ekranından; oda `dolu`, giriş damgası `17:41:14+00`, atama oluştu |
| **Oda ücreti idempotency** | Düğmeye **iki kez** basıldı → **tek** `oda_ucreti` satırı, yalnız `2026-09-07` gecesi. Denetim izi de yalnız 1 arttı (bağımsız ikinci kanıt). |
| Ödeme idempotency anahtarı | Tahsilat kaydında `islem_anahtari` UUID yazıldı |
| **Bakiyeli check-out** | 5.000,00 ₺ açıkken çıkış çalıştı; folyo açık kaldı, borç korundu (bilinçli Faz 1 kararı) |
| Atama korundu | Çıkıştan sonra `aktif = true` kaldı — geçmiş konaklama kaydı |
| Folyo kapanışı | Bakiye sıfırlanınca kapandı (`17:49:03+00`); kapalı folyoda formlar gizlendi |
| İkinci konaklama | `F-2026-000002`: oda ücreti 10.000 + indirim −1.000, tahsilat 9.000, bakiye 0, kapatıldı |
| **Denetim izi** | `erp_islem_audit` **0 → 12**. Üretimde ilk kez kayıt üretti. Manifest P3 #5 kapandı. |
| Ön yüz (canlı) | 7 PMS ekranı `demo.otel.dornevi.com` üzerinde HTTP 200; canlı `pms-rezervasyonlar.html` SHA256'sı commit'tekiyle **birebir aynı**; oturumsuz erişim giriş ekranına yönlendiriyor (fail-closed); 404 ve konsol hatası yok |

> **Ön yüz için giriş sonrası akışlar ajan tarafından doğrulanmadı** — üretim
> PIN'i ajanda yoktur ve olmamalıdır. Giriş sonrası canlı doğrulama kullanıcıya
> aittir.

### Yayın sırasında öğrenilenler

1. **Ön yüz, Adım 1–4'ün tamamına bağlıdır.** Rezervasyon ekranı `gecelik_fiyat`
   gönderir; o kolon Adım 4 ile gelir. Ön yüzü dört adım tamamlanmadan
   yayınlamak rezervasyon kaydını kırardı. Push'un sona bırakılması bu sayede
   doğrulandı. (Manifest P3 #9)
2. **Manifestteki Adım 1–2 smoke kriteri yanlıştı** — "audit sayacı artmalı"
   diyordu, oysa o adımlar denetim tetikleyicisi bağlamaz. `4b131ae` ile
   düzeltildi; Adım 3–4 kriterleri korundu.
3. **Rezervasyon formu, veritabanının reddedeceği durumları sunuyordu**
   (`giris_yapildi`/`cikis_yapildi`). Durum listesi geçiş matrisine bağlandı
   (`4b131ae`); check-in/out yetkili akışı Oda Planı + RPC olarak **korundu**.

### Üretimde kalıcı test verisi

Smoke test gerçek kayıtlar ürettiği ve finansal satırlar **append-only** olduğu
için şu zincir üretimde kalıcıdır ve silinemez: misafir `araz, mehmet`,
`R-2026-000001` / `F-2026-000001` (6.000 borç / 6.000 tahsilat, kapalı) ve
`R-2026-000002` / `F-2026-000002` (9.000 / 9.000, kapalı). Her ikisi de net
sıfır ve kapalı; muhasebe açısından etkisizdir. Misafir adı istenirse
değiştirilebilir (misafir tablosu append-only değildir).

---

## 6. PMS fonksiyon ACL temizliği — 2026-09-08

| Alan | Değer |
|---|---|
| **Ne yapıldı** | `public` şemasındaki tüm `pms_*` fonksiyonlarından `PUBLIC` ve `anon` için EXECUTE geri alındı. Yalnız `REVOKE`; hiçbir gövde, tablo, politika ya da veri değişmedi. |
| **Kim çalıştırdı** | Kullanıcı, Supabase SQL Editor. |
| **Onay** | **`CANLIYA UYGULA` alınmadı.** Ajan bunu bir öneri olarak sunmuş, kullanıcı doğrudan çalıştırmıştır. Prosedür ihlali olarak kayda geçer; sonucu zararsız çıkmıştır ama kayıt düzeltilmemelidir. |
| **Neden gerekti** | `2026-09-07-varsayilan-acl-uyari-kontrolu.sql` ilk çalıştırmasında **D3 = 18** ölçüldü: `public` şemasında `anon`'un EXECUTE hakkı olan 18 fonksiyon, hepsi PMS. 22 PMS fonksiyonundan yalnız 4'ü açık `revoke` almıştı. |
| **Fiili risk (uygulama öncesi)** | **Yok.** 18'in 17'si `returns trigger` — doğrudan çağrılamaz, PostgREST RPC olarak yayınlamaz. Kalan biri `pms_bugun(otel_id)`: `language sql stable`, hiçbir tabloya dokunmuyor, saat dilimine göre tarih döndürüyor. |
| **Doğrulama (uygulama sonrası, salt-okuma)** | `d3_anon = 0` · `pms_toplam = 22`. Beş çağrılabilir RPC'de (`pms_check_in`, `pms_check_out`, `pms_folio_oda_ucreti_isle`, `pms_folio_kapat`, `pms_bugun`) `authenticated = true`, `anon = false`. |
| **Etki** | Yok. Tetikleyiciler etkilenmez: PostgreSQL tetikleyici fonksiyonu üzerindeki EXECUTE hakkını `CREATE TRIGGER` anında kontrol eder, ateşlenirken yeniden kontrol etmez. `authenticated` da etkilenmez: varsayılan ACL ona PUBLIC üzerinden değil, kendi EXECUTE hakkını verir. |
| **Repo kaydı** | `docs/kurulum/2026-09-08-pms-fonksiyon-acl-temizligi.sql` — idempotent, doğrulama bloklu, yeni kurulumlarda da çalışır. |
| **Geri alma gerekti mi** | Hayır. Geri alma ayrıca **önerilmez**: bu migration yalnız fazla verilmiş ayrıcalığı geri alır. |

### Alınan ders

Değişiklik zararsız çıktı, ama **önce üretimde uygulanıp sonra kayda geçirildi.**
Bu, 6 Eylül'deki sahipsiz Phase 0 uygulamasının küçük ölçekli tekrarıdır: bir
süre boyunca üretimde, repoda karşılığı olmayan bir durum vardı ve sonraki bir
eşitlik doğrulaması bunu açıklanamayan bir sapma olarak raporlayacaktı.

Sıra her zaman şudur: **migration dosyası → statik denetim → onay → uygulama
→ doğrulama → kayıt.** Doğrudan SQL Editor'de çalıştırılan bir DDL, ne kadar
küçük olursa olsun, aynı gün dosyaya dönüştürülmelidir.

> `Success. No rows returned` bir DO bloğunun her zaman verdiği çıktıdır ve
> **hiçbir şey kanıtlamaz** — kaç revoke çalıştığını söylemez. Bu yüzden
> uygulama sonrası ölçüm ayrıca yapıldı.

---

## 7. DÜZELTME — yedek gerçeği (2026-09-12)

Bölüm 5'teki PMS Faz 1 kaydında **"Otomatik günlük yedek, 2026-09-07 (Supabase Pro)"** yazıyor.
2026-09-12'de Supabase panelinden ölçüldü:

- Proje **Free plan**da: *"Free Plan does not include project backups. Upgrade to the Pro Plan for up to 7 days of scheduled backups."*
- **Proje yedeği yok.** Zamanlanmış yedek listesi boş; point-in-time kurtarma da yok.
- Veritabanı parolası oluşturulduktan sonra **görüntülenemiyor**; yalnız sıfırlanabiliyor ("Resetting it will break any existing connections").

Sonuçlar:

1. **2.4'teki "Yedek" adımı otomatik yedeğe dayanamaz.** Yayın öncesi yedek, kullanıcının elle aldığı
   dökümdür: şema + referans veri için `docs/kurulum/dokum-al.ps1`, veri için ayrıca
   `pg_dump --data-only`. Yedeğin alındığı saat ve dosya yolu kayda geçer.
2. **Geri alma tablolarındaki "yedekten dönüş" satırı, elde elle alınmış bir yedek yoksa mevcut
   değildir.** Faz 2 yayın planının geri dönüş bölümü bu gerçeğe göre okunmalıdır.
3. 2026-09-07 kaydındaki ifade tarihsel kayıt olarak **silinmedi**; bu not onun üstüne eklendi.
   O tarihte planın Pro olup olmadığı ayrıca doğrulanmadı; bugünkü ölçüm Free'dir.

---

## 8. PMS Faz 2 — Kat Hizmetleri yayını — 2026-09-13 (tam kayıt)

### Zorunlu kayıt (§1)

| Alan | Değer |
|---|---|
| Tarih / saat | 2026-09-13T16:08–16:53+03:00 (kesinti); duman testleri 18:01–18:16+03:00 |
| Release owner | Claude (ajan) — komutları kullanıcı çalıştırdı (parola yalnız kullanıcıda) |
| Kullanıcı onayı | **VAR** — `CANLIYA UYGULA`, 2026-09-13; ortam demo, aktif operasyon yok |
| Git commit hash | `45b162ed57143d83f4902cfd9bd179315d4425b9` (çalışma ağacı temiz; `origin/main` `d0bd734` → `45b162e`) |
| Migration dosyası | `docs/kurulum/2026-09-09-pms-faz2-adim1-housekeeping.sql` (SHA-256 `e5a560cd…11e8f`), `docs/kurulum/2026-09-10-pms-faz2-adim2-housekeeping-ui-destek.sql` (SHA-256 `7d987dd9…88380`) |
| Preflight sonucu | `2026-09-11-pms-faz2-yayin-oncesi-preflight.sql` — **50 GEÇTİ / 0 SAPMA / 10 BİLGİ**, E1 = 0, taban `erp_islem_audit` 22 satır. Uygulama sonrası aynı dosya: **19 SAPMA** (beklenen liste ile birebir) |
| Yedek / geri alma | `C:\Users\USER\ERP-Yedek\2026-09-13-pre-faz2-veri-yedegi.sql` (757.033 bayt, SHA-256 `7D3AFF78…56DA`), sayaçlar `2026-09-13-pre-faz2-sayaclar.json`, yedeğin okuduğu an 2026-09-13T07:40:53Z. Geri yükleme provası geçti (E-5). **Auth kapsam dışı** |
| Uygulama sonucu | **Başarılı.** Adım 1: 36,7 sn; Adım 2: 6,8 sn; her ikisinin kendi doğrulama blokları "tüm kontroller geçti" dedi. Hata yok, geri alma gerekmedi |
| Smoke test | D1 denetim döngüsü ✅, D2 çıkış üreticisi ✅, D3 Faz 2 dışı denetim regresyonu ✅, D4 ⏳ (aşağıda) |
| Yayın sonrası parmak izi | Preflight 19 SAPMA listesi; `erp_islem_audit` 22 → 36 satır (12'si `islem_detayi` taşıyor) |
| Geri alma gerekti mi | **Hayır** |

### Sıra ve saatler

| Adım | Saat (+03:00) | Sonuç |
|---|---|---|
| 6.1.1 Kod dondurma | 15:5x | LF yayın baytları §0.1 ile birebir; hazırlık kilidi 11/11 aynı |
| 6.1.2 Yayın başlangıcı preflight'ı | 16:0x | 50 GEÇTİ / 0 SAPMA / E1 = 0 |
| 6.1.3 Adım 1 | **16:08 (T0)** | Uygulandı (36,7 sn); tetikleyici sırası doğrulandı |
| 6.1.4 Adım 2 | 16:1x | Uygulandı (6,8 sn); `odalar=t`, `definer_pinli=2`, `anon_veya_service=0` |
| 6.1.5 Uygulama sonrası doğrulama | 16:4x | 19 SAPMA (beklenen) |
| 6.1.6 Yetkiler | 16:4x | 9 rol satırı (4 `tam`, 1 `kayit`, 4 `goruntule`); modül kapalı kaldı |
| 6.1.7 Arayüz yayını | 16:50:57 push · 16:51:33 canlıda | Altı dosyanın canlı SHA-256'sı yayın commit'iyle aynı; HTTP 200 |
| 6.1.8 Modülü açma | **16:53** | `aktif = t` · **kesinti 45 dakika** |

### Duman testleri (üretimde gerçek kayıtlar)

- **D1 — denetim döngüsü.** Oda 102 çıkış temizliği görevi: Sistem Test başlattı (15:14:23Z) ve tamamladı (15:14:52Z); **MEHMET ARAZ denetledi** (15:16:14Z). `durum = kontrol_edildi`, `surum = 5`. Yapan ile denetleyen **farklı kullanıcı** — denetim bağımsızlığı üretimde kanıtlandı.
- **D2 — çıkış üreticisi.** Oda 102'nin gerçek check-out'u yapıldı; oda `boş + kirli` oldu ve `cikis_temizligi` görevi `bekliyor` durumunda, `olusturma_kaynagi = 'checkout'` ile **kendiliğinden** doğdu. Oda planında rozet ve "Kat Hizmetlerinde Aç" bağlantısı da çalıştı.
- **D3 — Faz 2 dışı denetim regresyonu.** Taban sonrası 14 denetim satırı: `pms_housekeeping_gorevleri` (6) ve `pms_odalar` (6) satırlarının **hepsi** `islem_detayi` taşıyor; `pms_rezervasyonlar` (2) satırının **hiçbiri** taşımıyor. Değiştirilen ortak denetim fonksiyonu diğer tetikleyiciler için eski davranışını koruyor.
- **D4 — yetki sınırı.** `goruntule` seviyesinde tek aday kullanıcı var (WWWWWW / Genel Müdür). Yayın penceresinde **yapılmadı**; izole kopyadaki 32 negatif yetki testi bu sınırı davranışsal olarak kanıtlıyor (yayın planı 1.6).

### Yayın sırasında öğrenilenler

1. **Arayüz, veritabanından daha katı: kat hizmetleri ekranı `kullanicilar.otel_id` ister.**
   Ekran otel kapsamını `CU.otelId`'den alır; otel seçici yoktur. `tum_oteller = true`
   ama `otel_id` boş olan kullanıcı ekranı **hiç kullanamaz** ("Otel seçili değil").
   DB tarafındaki `hk_calisan_uygun` "tüm oteller"i kabul ettiği için bu bir arayüz
   kısıtıdır. Test kullanıcılarına (`MEHMET ARAZ`, `Sistem Test`) `otel_id = '810'`
   verildi; `tum_oteller` yetkileri değişmedi. Kapsam geçici verilmişti, **kullanıcı
   kararıyla kalıcı bırakıldı** (tek otelli demo; ekranın bu kullanıcılarda çalışır
   kalması istendi). **Açık madde:** ya ekrana otel seçici eklenmeli ya da kat hizmetleri
   kullanıcılarının `otel_id`'si dolu olmalıdır.
   **Çözüldü (2026-09-13, yayın bekliyor):** ekrana otel seçici eklendi; çapraz otel
   hakkı `auth_tum_oteller()` ile sunucudan **fail-closed** okunuyor, şema değişmedi.
   Tasarım `docs/superpowers/specs/2026-09-13-kat-hizmetleri-otel-secici-design.md`,
   plan `docs/superpowers/plans/2026-09-13-kat-hizmetleri-otel-secici.md`. Otel atamalı
   kullanıcının davranışı aynı kaldı. Yerel izole ortamda sekiz kontrolle doğrulandı;
   üretime yayın ayrı bir `CANLIYA UYGULA` onayına bağlıdır.
2. **Tarayıcı otomasyonu yayın kanalı olarak güvenilmezdir.** SQL Editor'e yapıştırma
   yöntemi pencere ortasında çöktü (JS çalışıyor, tıklama/tuş ulaşmıyor). Aynı baytlar
   psql ile `--single-transaction` altında uygulandı; dosya özeti uygulamadan önce
   karşılaştırıldı. Bundan sonraki yayınlarda **birincil kanal psql olmalı**; SQL Editor
   yedek kanaldır.
3. **Parola girişi kesintiyi uzatabilir.** İki başarısız parola denemesi kesintiye
   yaklaşık 6 dakika ekledi. Pencere başında `-YalnizBaglanti` ile parola bir kez
   sınanmalıdır.
4. **Kesinti 45 dakika oldu** — plandaki müdahale eşiğine denk. Migration'ların kendisi
   toplam 44 saniye sürdü; kalan süre kanal değişikliği, parola denemeleri ve adımlar
   arası doğrulamalardır.

### Üretimde kalan kalıcı iz

- Oda 102: `cikis_temizligi` görevi `kontrol_edildi` (terminal), oda `boş + kontrol_edildi`.
- Oda 101: `ekstra_temizlik` görevi `bekliyor` (atanmamış), oda `boş + kirli`.
  **Bu oda temizlik akışı tamamlanana kadar satılabilir değildir.**
- `erp_islem_audit`: 22 → 36 satır.
- `kullanicilar.otel_id`: `MEHMET ARAZ` ve `Sistem Test` için `810` (kalıcı, kullanıcı kararı).
- Oda 101'in bekleyen görevini kullanıcı kapatacağını bildirdi; kapanana kadar oda satılabilir değildir.

---

## 9. Kat hizmetleri otel seçici — 2026-09-13 (arayüz yayını)

### Zorunlu kayıt (§1)

| Alan | Değer |
|---|---|
| Tarih / saat | 2026-09-13T19:13:25+03:00 push · 19:14:14 canlıda |
| Release owner | Claude (ajan) |
| Kullanıcı onayı | **VAR** — `CANLIYA UYGULA`, 2026-09-13 |
| Git commit hash | `e0b986e` (`origin/main` `77e98ef` → `e0b986e`, hızlı ileri alma; çalışma ağacı temiz) |
| Migration dosyası | **Yok.** Şema, yetki ve veri değişmedi |
| Preflight sonucu | Gerekmedi (veritabanına dokunulmuyor). `check.mjs` yeşil; hazırlık kilidi 11/11 aynı |
| Yedek / geri alma | Geri alma `git revert e0b986e` + push; veritabanında iz yok |
| Uygulama sonucu | **Başarılı.** İki dosyanın canlı SHA-256'sı yayın baytıyla aynı: `pms-housekeeping.html` `acd53b89…4d15c`, `pms-oda-plani.html` `35b15b72…61ee7`; ikisi de HTTP 200 |
| Smoke test | Yayın öncesi yerel izole ortamda sekiz kontrol (aşağıda); yayın sonrası canlı dosya içeriği doğrulandı |
| Yayın sonrası parmak izi | Canlı `pms-housekeeping.html` içinde `auth_tum_oteller` / `AKTIF_OTEL` geçişleri mevcut |
| Geri alma gerekti mi | **Hayır** |

### Ne değişti

Kat hizmetleri ekranı otel kapsamını artık yalnız `kullanicilar.otel_id`'den almıyor. Otel ataması olmayan kullanıcının çapraz otel hakkı `public.auth_tum_oteller()` ile **sunucudan** okunuyor (hata durumunda `false`, yani ekran eski uyarısına düşüyor) ve hakkı olan kullanıcı oteli başlıktaki listeden seçiyor. Seçim yalnız tarayıcıda (`hk-otel:<kullanici_id>`) duruyor. Oda planındaki "Kat Hizmetlerinde Aç" bağlantısı artık `#otel=<id>&oda=<no>` taşıyor.

**Otel atamalı kullanıcının davranışı değişmedi:** seçici görünmez, kendi oteline kilitlidir ve bağlantıdaki `#otel=` yok sayılır.

### Yayın öncesi doğrulama (yerel izole ortam)

| # | Kontrol | Sonuç |
|---|---|---|
| 1 | Otel atamalı kullanıcı | Seçici yok, ekran eskisi gibi |
| 2 | Çapraz otel kullanıcısı | Seçici var, ilk otel seçili, komut düğmeleri var |
| 3 | Otel değiştirme | Kuyruk yeni otelin verisiyle geldi, eskisinden satır kalmadı |
| 4 | Oda seçici | Yalnız seçili otelin odaları |
| 5 | Sayfa yenileme | Son seçim hatırlandı |
| 6 | `#otel=` derin bağlantı | Hatırlanan seçimi geçersiz kıldı |
| 7 | Aynı bağlantı, otel atamalı kullanıcıda | Yok sayıldı |
| 8 | Kat hizmetleri yetkisi olmayan kullanıcı | Kapalı ekran, seçici yok |

Ayrıca RPC adı bilerek bozularak **fail-closed** davranış ölçüldü: seçici çıkmadı, ekran eski uyarıya düştü; geçici değişiklik commit'e girmedi.

### Kayda geçen not

Yayın öncesi QA'da kullanılan çapraz otel rolünde `pms_oda` yetkisi yoktur; o kullanıcı oda planını boş görür. Kat hizmetlerini etkilemez (oda seçici ayrı RPC kullanır). Üretimde çapraz otelli bir kullanıcının oda planını da görmesi isteniyorsa ilgili role `pms_oda` yetkisi ayrıca verilmelidir.

§8'deki "otel seçici" açık maddesi bu yayınla kapanmıştır. Faz 2 yayınında iki test kullanıcısına verilen `otel_id = '810'` **kalıcı bırakılmıştı**; seçici geldikten sonra da **kalması kullanıcı kararıdır** (2026-09-13). Yani o iki kullanıcı 810'a kilitli kalır ve otel seçici onlarda görünmez; çapraz otel seçebilmeleri istenirse `otel_id` boşaltılmalıdır.
