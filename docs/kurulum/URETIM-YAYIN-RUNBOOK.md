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
