# Ön Büro menüsü ve PMS modülleri — birinci paket

**Durum: dosyalar hazır ve izole ortamda doğrulandı; GERÇEK ROL ERİŞİMİ
UYGULANMADI.** Üretimde, staging'de veya herhangi bir gerçek projede hiçbir SQL
koşulmadı. Rol erişimi onaylanmadan tohumlama uygulanmayacak.

Revizyon: 2026-10-05 (önceki sürümler 09-29 ve 10-05 karar tablosu).
Dal `pms/akis-tamamlama`. Üretim / push / deploy / VM değişikliği yok.
Mevcut yetkiler ve açık bakiye iş kuralı değiştirilmiyor.

Etiketler: **Z** ölçüm · **Ö** tasarım önerim (onay bekliyor) · **K** karar bekliyor.

---

## 1. KESİN KAPSAM — birinci paket

**İçinde:** beş Ön Büro modülü × üç Ön Büro rolü = **15 yetki satırı**.

| | |
|---|---|
| Modüller | `pms_oda_tipi`, `pms_oda`, `pms_misafir`, `pms_rezervasyon`, `pms_folio` |
| Roller | `onburo_sef`, `onburo_vardiya`, `onburo_personel` |

**Dışında — bu paket bunlara dokunmaz:**

| Dışarıda | Neden |
|---|---|
| `pms_housekeeping` | Modül `aktif=false` doğuyor ve temiz kurulumun şema dökümünde `pms_housekeeping_gorevleri` tablosu **yok** (Z); satır yazılsa da ekran çalışmaz |
| `kat_sef`, `kat_vardiya`, `kat_personel` | Yalnız housekeeping modülüne ihtiyaç duyuyorlar; onunla birlikte ikinci pakete kalır |
| `pms_misafir_kimlik` | KVKK; **ayrı karar**, bu pakette yetki verilmez |
| `gm` / `mali_isler_mdr` / üst roller | Karar K2 |

## 2. Temiz kurulumda bugünkü durum (Z)

Rehbere göre temiz kurulum şema dökümü (`2026-09-07-post-pms-faz1-sema-dokumu.sql`)
+ referans veri (`02-referans-veri.sql`) koşuyor; PMS migration'ları koşulmuyor.
Döküm yalnız şema taşır (`moduller` verisi 0 satır), referans veride de PMS kodu
yok →

> **Temiz kurulumda beş PMS modül satırı hiç yoktur; Ön Büro menüsü
> `sistem_admin` dahil HİÇBİR rolde görünmez.**

Menü kapısı: `index.html:468` ve `nav-drawer.js:77` (ikisi
`izinliSeviyeler.includes(yetkiHaritasi[kod])` ile en az bir kod arar);
`auth-guard.js:48` haritayı kurarken `moduller.aktif` olmayan satırı hiç koymaz.

## 3. Seviye → işlem haritası (Z, tek biçim)

| Seviye | Tablo işlemi | Ek koşul |
|---|---|---|
| `goruntule` | SELECT | `auth_otel_erisim(otel_id)` + kısıtlayıcı `phase0_otel_kisit` |
| `kayit` | INSERT **ve** UPDATE | aynı |
| `tam` | DELETE | aynı |

RPC kapıları: `pms_rezervasyon:kayit` → **check-in ve check-out**;
`pms_folio:kayit` → folyo kapatma + oda ücreti işleme.

## 4. KARAR TABLOSU — birinci paket (Ö)

| Rol | oda_tipi | oda | misafir | rezervasyon | folio | Bu satırlarla yapabileceği |
|---|---|---|---|---|---|---|
| `onburo_sef` | tam | tam | tam | tam | tam | Oda tipi/oda tanımı, misafir kaydı, rezervasyon, **check-in/out**, folyo + tahsilat, kayıt silme |
| `onburo_vardiya` | goruntule | kayit | kayit | kayit | kayit | Oda durumu, misafir, rezervasyon, **check-in/out**, tahsilat; oda **tipi** tanımını değiştiremez, silme yok |
| `onburo_personel` | goruntule | goruntule | kayit | kayit | **K1** | Misafir kaydı, rezervasyon, **check-in/out**; oda ve oda tipi salt-okuma; **folyo/tahsilat K1'e bağlı** |
| Diğer 34 rol | — | — | — | — | — | Değişiklik yok; Ön Büro menüsü **görünmez** |

**15 satır** (K1 iki seçenekte de 15; fark yalnız `onburo_personel/pms_folio`
seviyesinde). Kat rolleri bu tabloda **yok** — ikinci paket.

**Menü sonucu:** bu üç rolde Ön Büro menüsü **görünür**, diğerlerinde görünmez.
Otel kapsamı aynen korunur (modül yetkisi **ek** koşuldur); mevcut yetki satırları
değiştirilmez, yalnız yeni satır eklenir.

### K1 — KARAR VERİLDİ: seçenek A (2026-10-06)

Onay kaydı: `2026-10-06-PMS-mali-islem-yetkileri-onayli-tasarim.md`.
**A / `onburo_personel` için `pms_folio = kayit`.** Canlı yetki henüz verilmedi.

**YAYIN BAĞIMLILIĞI (kurulum dosyasında zorlanıyor):** A seçeneği, mali işlem
ayrımı kuralının **önce** kurulmuş olmasını gerektirir
(`2026-10-06-pms-folio-mali-yetki-ayrimi.sql`). Kural yoksa tohumlama dosyası
`MALI_AYRIM_KURALI_YOK` ile durur ve hiçbir satır yazmaz — çünkü kural olmadan
`kayit` yetkisi iade, indirim ve düzeltme yazmaya da yeter. `yok` seçeneği bu
bağımlılığı doğurmaz. Ölçüldü: T0a/T0b/T0c/T0d.

**Geri dönüş sırası:** önce tohumlama geri alması (yetkiyi kaldır), sonra kural
geri alması. Ters sıra, kural geri alma dosyasında **hard gate** ile engellenir.

### K1 seçenekleri (kayıt amaçlı)

`onburo_personel` folyo/tahsilat kaydı girebilsin mi? **İki seçenek de hazır ve
test edildi**; kurulum dosyası seçim yapılmadan **hiçbir şey yazmadan durur.**

| Seçenek | Satır | Sonuç |
|---|---|---|
| **A** `set local app.pms_k1 = 'kayit';` | `onburo_personel/pms_folio = kayit` | Personel folyo hareketi ve tahsilat girebilir |
| **B** `set local app.pms_k1 = 'yok';` | `onburo_personel/pms_folio = yok` (açık satır) | Personel folyoya erişmez; tahsilat yalnız vardiya + şefte |

Kararı siz vereceksiniz; belge bir seçeneği "karar" olarak kaydetmiyor.

### Ayrıca karar bekleyen (K2)

`gm` / `mali_isler_mdr` gibi üst roller bu beş modülde `goruntule` almalı mı?
Mevcut örüntüde `gm` birçok modülde `goruntule` taşıyor; uygulanırsa **+5 satır**.
Bu paket bu rollere dokunmuyor.

## 5. Kurulum dosyası

`docs/kurulum/2026-10-05-pms-onburo-modul-tohumlama.sql` — tek dosya, düz
`insert … on conflict do nothing`. `02-referans-veri.sql`'e dokunulmuyor (o bir
`pg_dump` çıktısı, `COPY … FROM stdin` içeriyor, SQL Editor'e yapıştırılamıyor).

Dosyanın kendi kapıları:

| Kapı | Davranış |
|---|---|
| K1 seçilmemiş | **Hata**, hiçbir satır yazılmaz |
| Eksik rol veya modül | **Hata** ve eksik liste; hiçbir satır yazılmaz |
| Hedef çiftte **çelişen mevcut yetki** | **Hata** ve çelişki listesi; hiçbir satır yazılmaz, mevcut yetki değiştirilmez |
| Zaten doğru olan satır | `on conflict do nothing` — dokunulmaz |

Modül satırları migration'larla **aynı** kod/ad/kategori (`onburo`) ve sıra
(43–48) ile yazılır, böylece yükseltilmiş kurulumlarla çakışmaz.

## 6. Geri alma — sabit çift listesi YOK

Önceki taslak sabit bir `(rol, modül)` listesini siliyordu. Bu **yanlıştı**:
kurulum `on conflict do nothing` ile çalıştığı için önceden var olan satırlar
eklenmemiş olabilir ve sabit listeyi silmek başkasının yetkisini kaldırırdı.

Yeni yaklaşım: kurulum eklediği her satırı `guncelleyen` alanına imzalar —

```
tohum:pms-onburo:<uygulama_id>@<uygulama_zamani>#<yazilan_yetki>
```

`docs/kurulum/2026-10-05-pms-onburo-modul-tohumlama-geri-al.sql` **yalnız bu
damgayı taşıyan** satırlara bakar ve bir satırı ancak iki koşul da sağlanırsa
siler: `guncelleme_tarihi` damgadaki zamanla aynı **ve** `yetki` damgadaki
seviyeyle aynı.

| Durum | Davranış |
|---|---|
| Damga yok (önceden var olan satır) | Hiç dokunulmaz |
| Damga var, zaman **farklı** | **Sonradan değiştirilmiş** → korunur, raporlanır |
| Damga var, zaman aynı, seviye **farklı** | **Çelişki** → hiçbir satır silinmez, işlem durur, raporlanır |
| Damga var, ikisi de aynı | Silinir |
| Uygulama kimliği verilmemiş | Hata, hiçbir satıra dokunulmaz |
| Bilinmeyen kimlik | Hiçbir şey silinmez, bildirilir |

**Dayanağı ölçüm (Z):** `yetki-yonetimi.html:137` düzenlemesi `yetki` ve
`guncelleme_tarihi`'ni yazıyor, `guncelleyen`'i **yazmıyor** ve `yetki_matrisi`
üzerinde bu alanları bakan tetikleyici yok. Bu yüzden damga kalır ama zaman/seviye
değişir — ayırt etme buna dayanıyor.

**Modül satırları kaldırılmaz.** Aynı satırlar PMS migration'larından da gelir ve
başka kurulumlarda zaten bulunabilir; silmek yabancı anahtar ve başka rollerin
yetki kaybı riski taşır. İstenirse ayrı ve açık kararla kaldırılır.

## 6b. İnceleme bulguları (PMS-S1…S4) — bağımsız doğrulandı ve düzeltildi

Dördü de düzeltmeden **önce** kırmızı üretildi, sonra yeşile döndü.

| # | Bulgu | Düzeltme |
|---|---|---|
| **S1** (P2) | Belgelenen `set local` satırı `begin;`ten **önceydi**; dosya dış işlem olmadan koşulunca seçim kayboluyordu (`SET LOCAL can only be used in transaction blocks`) ve testler bunu `set` ile atlıyordu | Seçim/kimlik satırları `begin;` **içine** alındı; testler artık dosyanın **kendi** belgelenen satırını yorumdan çıkarıp koşuyor |
| **S2** (P1) | Kimlik UUID doğrulanmıyordu ve LIKE desenine giriyordu; `%` joker olup 15 satırı siliyordu | Kimlik `::uuid` ile doğrulanıyor; eşleştirme `split_part(guncelleyen,@,1) = <imza>` ile **tam eşitlik** — kullanıcı girdisi desene hiç girmiyor |
| **S3** (P1) | Fotoğraf kilitsiz alınıyor, DELETE yalnız `id` denetliyordu; eş zamanlı düzenleme eski fotoğrafla siliniyordu | Fotoğraf `for update of ym` ile **kilitli** alınıyor; DELETE güncel satırın damga/seviye/zaman alanlarını **tekrar** denetliyor |
| **S4** (P2) | Mevcut modül `aktif=false` ise `on conflict do nothing` onu aktifleştirmiyor; kurulum "başarılı" görünürken modül menüye/yetki haritasına girmiyordu | Pasif hedef modül **açık engel**: durur, raporlar, hiçbir satır yazmaz ve **otomatik aktifleştirmez** (başkasının pasife alma kararı korunur) |

## 7. İzole doğrulama — kanıt

`scripts/pms-modul-tohum.test.mjs`, izole Docker veritabanında **yapay** referans
veriyle (üç Ön Büro rolü + ilgisiz bir rol + önceden var olan bir yetki satırı).
Sonuç: **63 geçti / 0 kaldı** (özgün 32 + 27 S-regresyonu + 4 yayın bağımlılığı). Gerçek rol erişimi uygulanmadı.

| Test | Ölçülen |
|---|---|
| T1 | K1 kararsızken **durur**; ne yetki ne modül satırı yazılır |
| T2 | Temiz kurulum: 5 modül + **15** yetki satırı, seviyeler karar tablosuyla **birebir** |
| T3 | Önceden var olan ilgisiz yetki satırı **değişmedi** |
| T4 | İkinci koşum **0 satır** ekledi; tüm `yetki_matrisi` md5'i **birebir aynı** |
| T5 | Geri alma koştu; yalnız bu uygulamanın eklediği satırlar kalktı; modül satırları **kalmaya devam etti** |
| T6 | Sonradan değiştirilmiş yetki geri almada **korundu** ve raporlandı |
| T7 | Çelişkide (zaman aynı, seviye farklı) geri alma **durdu**, hiçbir satır silinmedi |
| T8 | Eksik rol sessizce geçilmedi: hata + eksik adı, hiçbir satır yazılmadı |
| T9 | Çelişen mevcut yetki sessizce geçilmedi: hata + çelişki listesi; başkasının kararı **değişmedi** |
| T10 | K1'in **iki seçeneği de** çalıştı; satır sayısı 15 kaldı |
| T11/T12 | Kimliksiz geri alma durur; bilinmeyen kimlikte hiçbir şey silinmez |
| **S1** | Dosyanın **kendi belgelenen satırı** dış işlem olmadan çalışıyor (kurulum ve geri alma); `SET LOCAL` uyarısı yok |
| **S2** | `%`, `_`, bozuk UUID ve enjeksiyon denemesi geri almayı **durduruyor**, imzalı satır sayısı değişmiyor; iki uygulama fikstüründe biri geri alınınca **diğeri korunuyor** |
| **S3** | Eş zamanlı oturum bir satırı değiştirip kilidi tutuyor; geri alma o satırı **koruyor**, rapor gerçek sayıyı veriyor (`imzali=15 silinen=14 korunan=1`) |
| **S4** | Pasif hedef modülde kurulum **duruyor**, 0 satır yazıyor, `aktif=false` **değişmiyor**; aktif modülde pozitif kontrol geçiyor |

## 8. Uygulama onayından sonra ölçülmesi gerekenler

1. Temiz Supabase projesinde kurulum + bu dosya → üç rolde Ön Büro menüsünün
   **gerçekten** görünmesi, diğer 34 rolde görünmemesi (izole db bunu ölçmez).
2. `goruntule` verilen rolün yazma denemesinin RLS tarafından reddedilmesi.
3. `scripts/kurulum-onkontrol.test.mjs` **K-6** bu boşluğu ön yüz
   referanslarından sabitliyor; tohum değişince **kırılması beklenir**.
   Beklentisi kararla birlikte açıkça güncellenmeli, sessizce değiştirilmemeli.

## 9. İkinci pakete kalanlar

Housekeeping modülü (`aktif=false` + eksik tablo), üç kat rolü,
`pms_misafir_kimlik` (ayrı karar), üst roller (K2).

## 10. İlgili

`docs/inceleme/KURULUM-HAZIRLIK-KONTROLU.md` §3.2 ·
`docs/inceleme/PMS-AKIS-PAKETI.md` §2 D2 · `scripts/kurulum-onkontrol.test.mjs` K-6
