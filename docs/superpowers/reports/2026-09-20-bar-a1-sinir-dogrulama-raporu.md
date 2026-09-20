# Bar A1 — Sınır Doğrulamaları ve Yayın İşlem Kapısı

**Tarih:** 2026-09-20 · **Dal:** `bar-a1` (yerel) · **Üretim:** yazma yok. Push, deploy, canlı
migration ve Aşama 2 **yok**; yayın talimatı yok. Yeni özellik geliştirilmedi; istenen sınırlar
doğrulandı ve kanıtlandı.

| # | Sınır / madde | Durum |
|---|---|---|
| 1 | Geçiş testi kabul kanıtına eklendi | **YAPILDI** |
| 2 | 5. parametre uyumluluk ayrımı; yetki kapısı değil — kontroller bağımsız | **KANITLANDI** |
| 3 | Eski imzaya dönüş yalnız "fonksiyon bulunamadı" hatasında | **KANITLANDI** |
| 4 | "Sayım" açıklaması kontrolü dar kapsamlı sunuluyor | **DÜZELTİLDİ** |
| 5 | Geçiş `service_role` kullanımı yalnız işlem kapsamında; denetimde ayırt ediliyor | **KANITLANDI** |
| 6 | Yayın öncesi işlem kapısı; yarım kalan körlemesine yeniden çalıştırılmaz | **PLANA İŞLENDİ** |
| 7 | Sayım oluşturma / listeleme gerçek yetkiyle | **AÇIK** (sizde) |
| 8 | Canlı Edge kodu / müşteri şeması | **AÇIK** (sizde) |
| 9 | Koşullu tarayıcı testleri | **AÇIK** — tamamlanmış sayılmıyor |
| 10 | Yayın sırası | **KARAR GEREKİYOR** |

---

## 1. Geçiş testi artık kabul kanıtı

Tasarım bölüm 10'a (test stratejisi) eklendi: `gecis-provasi.test.mjs` **kabul kanıtıdır** ve asgari
senaryosu yazılıdır — eski ekran detayları migration'dan önce okur, yazması bekletilir, migration
uygulanır, yazma devam eder; **stok değişmez, sayım hareketi yazılmaz, oturum onay bekler** (G12) ve
aynı sayım yeni ekranla doğru sonucu verir (G13). Bu senaryo geçmeden ilgili madde kapatılamaz.
Dolu tablo geçiş testi de (`bar-a1-gecis-migration.test.mjs`) kabul kanıtına eklendi.

## 2. Beşinci parametre bir yetki kapısı değil

`p_istemci_nesli` yalnız **sürüm ayrımıdır**. Yeni imza da SECURITY INVOKER'dır; mevcut kontroller
(çağıranın kimliği, `stok_takip` yetkisi ve otel kapsamı için tablo RLS'i, rezervasyon koruması)
bağımsız işler. Nesil 1 göndermek hiçbir kontrolü atlatmaz:

| Deneme (hepsi `p_istemci_nesli = 1`) | Sonuç |
|---|---|
| `anon` | fonksiyon yetkisi reddedildi |
| Stok yetkisi olmayan personel | reddedildi, stok değişmedi |
| Pasif kullanıcı | reddedildi |
| Başka otelin deposuna yazma (810 kullanıcısı → 811) | reddedildi |
| Rezerve stoğa çıkış | `REZERVE_STOK` (E18b) |
| İki imzanın tanımı | ikisi de `SECURITY DEFINER` **değil** (ölçüldü) |

Kanıt: `bar-a1-guvenlik` E18 / E18b (72/72).

## 3. Eski imzaya dönüş yalnız "fonksiyon bulunamadı"

`stokEkleCagir` (ortak.js) gerçek fonksiyonu, taklit edilmiş `fetch` ile sınandı
(`scripts/stok-ekle-cagri.test.mjs`, 9/9, Docker gerekmez):

| Durum | Davranış |
|---|---|
| Başarılı | tek istek, gövdede `p_istemci_nesli` |
| 404 + `PGRST202` (A1 öncesi veritabanı) | eski imzaya **bir kez** dönülür, ikinci istekte nesil yok |
| `ESKI_ISTEMCI` (A1 sonrası 4 parametreli yol) | dönüş **yok** |
| Yetki reddi (403), oturum hatası (401), `REZERVE_STOK` (400), sunucu hatası (500) | dönüş **yok** |
| 404 ama `PGRST202` değil | dönüş **yok** |
| Ağ hatası | ikinci istek yok; hata çağırana gider |

## 4. "Sayım" açıklaması kontrolünün kapsamı

Bu kontrol **dar kapsamlıdır** ve migration yorumunda da böyle yazılıdır: yalnız eski sayım
akışının sahte `sayim` hareketini engeller. `stok_hareketleri`'ne doğrudan yazma **genel olarak
açıktır** (mevcut tasarım: mal kabul, günlük tüketim ve stok-takip doğrudan yazar); açıklamasını
değiştiren bir istemci bu kontrolü aşar. Stok miktarını koruyan asıl mekanizma yazma yolundaki
sürüm ayrımıdır (madde 2). Testte de böyle ölçülüyor: `sayim` açıklamalı hareket reddedilir,
diğer doğrudan hareketler etkilenmez (E17).

## 5. Geçiş kimliği: kapsam ve denetim izi

`scripts/bar-a1-gecis-migration.test.mjs` (6/6). Tabloda her durumdan sipariş varken:

| Ölçüm | Sonuç |
|---|---|
| Migration | dolu tabloda tek işlemde uygulandı (M1) |
| Kimlik kapsamı — işlem içi | migration dosyasının sonunda, **aynı işlemde**: rol ve claim boş (M1) |
| Kimlik kapsamı — sonraki oturum | boş (M2) |
| Geçiş değerleri | açık ücretli → `bekliyor`, kapanmış ücretli → `gecis`, ücretsiz → `gerekmiyor` (M3, M4) |
| Denetim izi | backfill satırları + `A1-GECIS-ISARETI` satırı **aynı `transaction_id`**; işaret satırında migration dosyası adı ve güncellenen satır sayısı; başka işlemden satır yok (M5) |
| Hata / geri alma | yapay hata sonrası: geçiş alanları yok, denetim satırı yok, kimlik ayarı kalmadı, siparişler duruyor (M6) |

Not: denetimde rol `service_role`, aktör boştur (migration'ın ERP kullanıcısı yoktur). Ayırt edici
olan, işaret satırı ve ortak `transaction_id`'dir.

## 6. Yayın öncesi işlem kapısı (sessiz saat tek başına yeterli değil)

Plana (G9) eklendi; sorgu: `docs/kurulum/2026-09-20-yayin-oncesi-islem-kontrol.sql` (salt okuma).

1. **Bitti mi:** son stok hareketi ≥ 15 dk önce; son 15 dk'da hareket yazan depo yok.
2. **Yeni işlem başlamıyor mu:** ilgili personele duyurulur ve ekranlar kapatılır; kapanış
   **sorguyla** teyit edilir (duyuru tek başına kanıt değil). Kontrol 5 dk arayla iki kez koşulur.
3. **Yarım kalan var mı:** `durum='onaylandi'` ve `stok_islendi=false` olan mal kabuller yayından
   önce kaydedilir (mevcutlar yayının eseri değildir).
4. Açık sayım oturumu yayın sırasında onaylanmaz; açık ücretli bar siparişleri migration sonrası
   yeni kuyrukta doğrulanır.

**Yayından sonra** aynı sorgu tekrar koşulur. Yeni yarım kalan çıkarsa **körlemesine yeniden onay
yoktur**: sorgunun 4. maddesi belge başına kalem sayısı ile yazılmış hareket sayısını karşılaştırır;
yalnız eksik satırlar tamamlanır ve işlem sahibine hangi satırların yazıldığı bildirilir. Günlük
tüketim ekranı zaten satır satır çalışır ve başarısız satırları listeler; yalnız o satırlar
yeniden denenir.

## 7–10. Açık kalanlar (değişmedi)

- **Sayım oluşturma / listeleme**: üretim şemasında sayım tabloları oturum açmış kullanıcıya kapalı
  görünüyor; testte yalnız test ortamına okuma politikası eklendi, oluşturma hiç sınanmadı. Canlı
  doğrulama sizde: `.\docs\kurulum\sql-uygula.ps1 -Dosya docs\kurulum\2026-09-19-sayim-rls-salt-okuma.sql -SaltOkuma`
- **Canlı Edge kodu / müşteri şeması**: uygulama içi tarayıcıda Supabase Dashboard oturumu gerekiyor.
- **Koşullu tarayıcı testleri**: kuyruktaki yerel `confirm/prompt` adımları ve sayımdaki iki düğme
  gerçek tıklamayla sınanmış sayılmıyor; PIN ekranı sınanmadı. Bunu kapatmanın tek yolu o ekranlarda
  da yerel pencereleri sayfa içi formlarla değiştirmek olur — **bu yeni geliştirmedir, açılmadı.**
- **Yayın sırası**: karar sizde.

## Test sonuçları (bu tur)

| Takım | Sonuç | Bu turda yeni |
|---|---|---|
| bar-a1-guvenlik | 72/72 | E18, E18b |
| bar-a1-gecis-migration (yeni dosya) | 6/6 | M1–M6 |
| stok-ekle-cagri (yeni dosya, Docker gerekmez) | 9/9 | C1–C6 |
| gecis-provasi | 16/16 | — |
| bar-a1-negatif | 12/12 | — |
| bar-a1-ekran | 37/37 | — |
| sira ve geri alma | 17/17 | — |
| bar-edge-e2e | 22/22 | — |
| stok-ekran · stok-veri-eksiksizlik · stok-guncelleme-tarihi | 21/21 · 33/33 · 14/14 | — |
| taban · önce ölçümü | 9/9 · 9/9 | — |
| migration denetleyicisi | 25 dosya 0 hata; birim 15/15; phase0 6/6 | yeni salt-okuma sorgusu dahil |
