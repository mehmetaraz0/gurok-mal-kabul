# Ürün Tanımlama + Cost Fiyat Otomasyonu — Tasarım

## Problem / Hedef

İki eksik: (1) Sistemde **ürün kodu açma ekranı yok** — `urun-yonetimi.html` yalnızca birim dönüşümü yapıyor, ürün oluşturmuyor. (2) İç Talep onay zincirinin **cost aşaması** toplam tutarı **elle** yazmayı istiyor (`satin-alma-talepler.html` `talep-cost-tutar` input); oysa sistemde ürün fiyatı zaten var (son fatura). Hedef: ürün açarken/ürün yönetiminde bir **sistem fiyatı** tanımlamak ve cost aşamasında tutarı bu fiyatlardan **otomatik** hesaplamak.

## Kullanıcı kararları (bu oturumda alındı)

- **Fiyat kaynağı = Seçenek 1:** Cost, önce ürünün **sistem_fiyat**'ını, yoksa **son fatura fiyatı**nı (`urun_guncel_fiyat`) kullanır; ikisi de yoksa elle giriş. Fatura fiyatı zaten mal kabulde otomatik güncelleniyor.
- **Yeni ürün** açılırken başlangıç (sistem) fiyatı girilir; sonra satın alma günceller.
- **Cost tutarı** otomatik dolar ama **elle düzeltilebilir** (kilitli değil).
- Ürün açma ekranı **`urunler` tablosuyla** çalışır (statik URUN_DB'yi genişletmiyoruz).

## Kapsam

- Yeni ekran **`urun-tanimlama.html`**: `urunler` tablosundan ürün ara/listele; yeni ürün oluştur (kod+ad+birim+grup+sistem_fiyat); mevcut ürünün sistem_fiyat'ını düzenle. Satın Alma hub'ına (`satin-alma.html`) kart.
- `urunler` tablosuna **fiyat kolonları** eklenir (kullanıcı SQL çalıştırır).
- **`satin-alma-talepler.html`** cost aşaması UI: elle tutar yerine kalem×fiyat otomatik hesap + kırılım + düzeltilebilir toplam.

## Kapsam dışı

- **16 sayfalık URUN_DB→urunler tablosu birleştirmesi** — ayrı, sonraki bir tech-debt işi. Yeni açılan ürün `urunler` tablosuna yazılır → tabloyu okuyan 7 modern sayfada (satin-alma-talepler, stok-takip, mal-kabul-liste, mal-kabul-skt, gunluk-tuketim, trend-raporlama, bar-menu-yonetimi) görünür; statik-URUN_DB sayfaları (depo-siparis, satin-alma-iade/-firmalar/-siparisolustur, urun-yonetimi) bu kapsamda değil.
- Ürün silme/pasifleştirme, çoklu tedarikçi fiyatı (Teklif Toplama zaten ayrı), fiyat geçmişi/versiyon.

## Veri Modeli

`urunler` tablosuna (mevcut: kod PK, ad, birim, grup, sicaklik_kriteri, olusturma_tarihi) eklenecek kolonlar:

```sql
alter table public.urunler add column if not exists sistem_fiyat numeric;
alter table public.urunler add column if not exists sistem_fiyat_tarihi timestamptz;
alter table public.urunler add column if not exists sistem_fiyat_giren text;
```
`sistem_fiyat` nullable — tanımlı değilse cost fatura fiyatına düşer.

## Mimari

**1. `urun-tanimlama.html` (yeni, `urunler` tablosuyla).** Head/stil/header deseni mevcut bir kardeş sayfadan (ör. `mal-kabul-liste.html` — urunler tablosunu okuyan modern sayfa). Yetki: `YETKI_HARITASI['urun_yonetimi']` ∈ {kayit,tam} yazma için.
- `loadUrunler()` — `GET urunler?select=kod,ad,birim,grup,sistem_fiyat&order=ad`.
- Arama + liste (kod/ad); her satırda sistem_fiyat + "Fiyat Düzenle".
- `urunEkle()` — kod çakışma kontrolü (`GET urunler?kod=eq.X`), yoksa `POST urunler {kod,ad,birim,grup,sistem_fiyat, sistem_fiyat_tarihi:now, sistem_fiyat_giren:CU.ad}`.
- `fiyatGuncelle(kod, fiyat)` — `PATCH urunler?kod=eq.X {sistem_fiyat, sistem_fiyat_tarihi, sistem_fiyat_giren}`.

**2. `satin-alma.html` hub** — yeni "Ürün Tanımlama" kartı → `urun-tanimlama.html`.

**3. `satin-alma-talepler.html` cost otomatik fiyat.** `openTalepDetay` cost bloğunda (`t.asama==='cost'&&yetkili`, ~satır 761): elle input yerine, talebin kalemleri için fiyatları çöz ve tutarı hesapla.
- Fiyat çözümleme (kalem başına): `sistem_fiyat` (urunler) varsa o → yoksa `urun_guncel_fiyat.birim_fiyat` → yoksa null.
- Fiyatları toplu çek: talebin kalem kodları için `GET urunler?kod=in.(...)&select=kod,sistem_fiyat` + `GET urun_guncel_fiyat?urun_kodu=in.(...)&select=urun_kodu,birim_fiyat`.
- Kırılım tablosu: her kalem `ad — miktar × fiyat = satır tutarı` (fiyatı yoksa "fiyat yok", satır 0). Toplam = Σ satır.
- `talep-cost-tutar` input'u bu toplamla **önceden doldurulur** ama düzenlenebilir kalır. `talepKararVer` mevcut haliyle input değerini okur (değişmez).

## Akış

1. Satın alma **Ürün Tanımlama**'da ürün açar (fiyatlı) veya mevcut ürünün fiyatını günceller.
2. O ürünlü bir İç Talep depo onayından geçer → cost aşamasına düşer.
3. Cost açılınca kalem×fiyat kırılımı + otomatik toplam görünür (sistem_fiyat / fatura fiyatı sırasıyla).
4. Onaylayan gerekiyorsa toplamı düzeltir, **Onayla** → mevcut `talepAsamaIlerlet` akışı (tutar PATCH'lenir, sonraki katman tutara göre).

## Hata / kenar durumlar

- **Fiyatı olmayan kalem:** "fiyat yok" göster, satır 0, toplam eksik — bloklama yok, kullanıcı elle girebilir.
- **Kod çakışması** (ürün ekleme): mevcut kod varsa reddet, uyarı ver.
- **Yetkisiz:** urun-tanimlama yazma işlemleri `urun_yonetimi` yetkisiyle gate'li; yoksa salt-görüntüleme.
- Fiyat çekme sorgusu boş dönerse cost yine elle giriş olarak çalışır (geriye uyumlu).

## Test / doğrulama planı

Statik: yeni ekranın urunler POST/PATCH alan adlarının şemayla eşleştiği, cost fiyat çözümleme sırasının (sistem_fiyat→urun_guncel_fiyat→null) doğru olduğu, `talep-cost-tutar` prefill'inin `talepKararVer` okumasını bozmadığı kod okumasıyla doğrulanır. Kullanıcı uçtan uca (SQL sonrası): ürün aç (fiyatlı) → o üründen talep → depo onayla → cost'ta otomatik tutar geliyor mu → onayla → sonraki aşamaya tutarla geçiyor mu.
