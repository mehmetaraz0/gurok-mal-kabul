# Grafik/Trend Raporlama — Tasarım

## Problem / Hedef

Tüm ekranlar (stok-takip.html'deki stat kartları, gunluk-tuketim.html'deki
Food Cost sekmesi vb.) sadece o anki anlık sayıyı gösteriyor —
stok/tüketim/food-cost'un zaman içindeki eğilimi hiçbir yerde
görülemiyor. Bu, depo modülü kıyaslama raporunda tespit edilen Önemli
#05 eksiği.

## Kapsam

- Yeni, bağımsız bir sayfa: `trend-raporlama.html`. Üç bölüm üst üste:
  **Stok Trendi**, **Tüketim Trendi**, **Food-Cost Trendi**.
- Ortak bir zaman aralığı seçici (Son 7 gün / Son 30 gün, varsayılan 30
  gün) sayfanın üstünde, üç grafiği de etkiler.
- Grafik kütüphanesi: Chart.js, CDN üzerinden yüklenir (build aracı
  gerektirmez, proje zaten XLSX gibi başka kütüphaneleri de CDN'den
  yüklüyor — bkz. `stok-takip.html`'in `stokExcelAktar()`'ı).
- `index.html`'deki mevcut "Raporlar" kartı bu yeni sayfaya
  yönlendirilir (şu an `mal-kabul-v2.html#izleme`'ye gidiyor — o sekme
  dokunulmadan, mal kabul odaklı haliyle kalır).
- Erişim: `stok-takip.html` ile aynı roller — `yonetici`, `depo`,
  `cost_control`.

## Kapsam dışı

- Otel/depo bazlı food-cost ayrımı — tüm oteller birlikte, tek bir
  ortalama çizgi (YAGNI, mevcut veri zaten çok sığ).
- Önceden hesaplanmış/kalıcı özet tablo — her şey sayfa açıldığında ham
  veriden anlık hesaplanır (Güvenlik Stoğu ve ABC Analizi özellikleriyle
  tutarlı desen).
- PDF/Excel dışa aktarma.
- Stok trendinde transfer hareketlerinin (`tip='transfer'`) dahil
  edilmesi — transfer kaydının hangi depo için giriş hangi depo için
  çıkış sayılacağı `stok_hareketleri` şemasında belirsiz (satır tek bir
  `depo_kodu` taşıyor, yön ayrımı yok); net hareket hesabı sadece
  `tip='giris'` ve `tip='cikis'` satırlarını sayar, `transfer` satırları
  hesaba katılmaz. İleride transfer yönü netleştirilirse ayrı bir iş.
- Mutlak stok seviyesi (ör. "1 Temmuz'da depoda tam olarak 340 kg
  vardı") — bkz. Mimari bölümü, bunun yerine pencere-içi kümülatif net
  hareket gösterilir.

## Mimari

**Sayfa iskeleti:** `stok-takip.html`'in üst bilgi çubuğu + auth-guard
deseni kopyalanır (`requireLogin()`, `requireRole(user,['yonetici','depo','cost_control'])`).
Otel/depo seçici `stok-takip.html`'deki ile aynı desende üstte durur;
seçim stok ve tüketim bölümlerini filtreler (food-cost bölümü tüm
otelleri birlikte gösterdiği için bu seçimden etkilenmez).

**Chart.js yükleme:** `stok-takip.html`'in Excel kütüphanesini yüklediği
desenle aynı — `<script src="https://cdnjs.cloudflare.com/ajax/libs/Chart.js/4.4.1/chart.umd.js"></script>`
sayfa `<head>`'inde statik olarak eklenir (lazy-load gerekmez, bu sayfanın
tek işi grafik çizmek).

### 1. Stok Trendi

Kullanıcı bir ürün (`urun_kodu`) + depo (`depo_kodu`) seçer (mevcut
ürün/depo seçici desenleri). Seçilen aralıktaki `stok_hareketleri`
satırları (`urun_kodu`, `depo_kodu` eşleşen, `tarih` aralık içinde,
`tip` `giris` veya `cikis`) çekilir, güne göre gruplanır:

```
gunlukNet[gun] = (o gündeki tüm 'giris' miktarları toplamı) - (o gündeki tüm 'cikis' miktarları toplamı)
```

Grafik, aralığın ilk gününde 0'dan başlayan bir çizgi olarak
`kumulatif[gun] = kumulatif[gun-1] + gunlukNet[gun]` çizer — "bu ürün
seçilen pencerede net ne kadar arttı/azaldı" gösterir, mutlak stok
seviyesini iddia etmez.

### 2. Tüketim Trendi

Kullanıcı bir ürün seçer. Seçilen aralıktaki `stok_hareketleri`
satırlarından `tip='cikis'` VE `aciklama` `gunluk_tuketim` veya
`recete_tuketim` içerenler (Güvenlik Stoğu/ABC Analizi özellikleriyle
aynı tüketim tanımı) güne göre toplanır, günlük toplam tüketim miktarı
çizgi grafikte gösterilir (kümülatif değil — her gün kendi değeriyle).

### 3. Food-Cost Trendi

`recete_tuketimleri` tablosunda gerçek, dolu `tarih` (date) ve
`food_cost_yuzde` (nullable) kolonları doğrulandı (canlı sorguyla
kontrol edildi — örnek satır: `{"tarih":"2026-07-09","food_cost_yuzde":null,...}`).
Seçilen aralıktaki satırlar `tarih`'e göre gruplanır, her gün için
`food_cost_yuzde` NULL olmayan satırların ortalaması alınır, günlük
ortalama food-cost yüzdesi çizgi grafikte gösterilir. Hiç verisi
olmayan günler grafikte boşluk/kesinti olarak kalır (interpolasyon
yapılmaz).

## Akış

1. Sayfa açılır, auth kontrolü geçilir, Chart.js yüklenir.
2. Varsayılan aralık (son 30 gün) ve varsayılan otel/depo/ürün seçimiyle
   üç grafik de hesaplanıp çizilir.
3. Kullanıcı aralığı (7/30 gün) veya ürün/depo seçimini değiştirirse
   ilgili grafik(ler) yeniden hesaplanıp çizilir.
4. Veri olmayan bir ürün/aralık seçilirse grafik boş durum mesajı
   gösterir ("Bu aralıkta veri yok"), hata fırlatmaz.

## Test/doğrulama planı

Statik: `stok_hareketleri`/`recete_tuketimleri` sorgu filtrelerinin
(tarih aralığı, `tip`/`aciklama` filtreleri) doğru kurulduğunu, kümülatif
net hareket hesabının pencere başında 0'dan başladığını, food-cost
ortalamasının NULL değerleri doğru dışladığını kod okuyarak doğrulamak.
Gerçek uçtan uca test (bir ürün için bilinen giriş/çıkış hareketleri
oluştur → stok trendi grafiğinin beklenen kümülatif değerle eşleştiğini
gör, tüketim ve food-cost grafiklerinin gerçek verilerle doğru
çizildiğini gör) kullanıcı tarafından yapılacak.
