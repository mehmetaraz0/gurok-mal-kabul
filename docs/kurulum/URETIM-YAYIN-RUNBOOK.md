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

### 2.3 Yayın öncesi parmak izi (salt-okuma)
```
docs/kurulum/2026-09-06-staging-esitlik-dogrulama.sql
```
Üretimde çalıştırılır. Çıktı **kaydedilir** — geri alma gerekirse
"öncesi" fotoğrafı budur.

### 2.4 Yedek
Supabase Dashboard → Database → Backups. Yedeğin tarihi ve saati kayda
geçer. Ücretsiz planda otomatik yedek günlüktür; son yedekten bu yana geçen
süre kayıt altına alınır.

### 2.5 Yerel prova
Migration önce üretimin doğrulanmış kopyasında koşturulur:
```bash
node scripts/dokum-dogrula.mjs docs/kurulum/<tarih>-sema-dokumu.sql
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
