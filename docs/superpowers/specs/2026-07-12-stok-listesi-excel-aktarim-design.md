# Stok Listesi — Excel'e Aktar (salt görüntüleme) — Tasarım

## Problem / Hedef

`stok-takip.html`'deki Stok Takip sekmesinde, o an seçili depo + ekrandaki
filtreye (arama, kategori, kritik/uyarı/normal) göre görünen ürün listesini
tek tuşla Excel'e indirmek. **Geri yükleme/import yok** — bu tamamen tek
yönlü, salt görüntüleme/raporlama amaçlı bir özellik. Stok verisine hiçbir
şekilde yazma işlemi yapılmaz.

## Kapsam dışı

- Excel'den geri yükleme / stok güncelleme — kullanıcı bunu açıkça istemedi.
- Diğer depoların/otelin toplu dışa aktarımı — sadece o an seçili depo.
- Hareketler (giriş/çıkış/transfer) sekmesinin dışa aktarımı — kapsam dışı,
  ayrı bir iş olabilir.

## Tasarım

Stok Takip sekmesinin filtre satırının altına, listenin üstüne bir
**"📤 Excel'e Aktar"** butonu eklenir (`stok-takip.html:158-159` civarı,
`.filter-tabs` ile `#kat-tabs` arasına ya da `#kat-tabs`'ın hemen altına).

Tıklanınca `renderStok()`'ta zaten hesaplanan `filtered` diziyle AYNI
filtreleme mantığı tekrar uygulanır (arama + kategori + durum filtresi) —
kullanıcı o an ekranda ne görüyorsa Excel'e o çıkar. Kolonlar:
`Ürün Kodu | Ürün Adı | Miktar | Birim | Minimum | Durum` (Durum: Kritik/
Uyarı/Normal — `getStokDurum()` fonksiyonuyla zaten hesaplanıyor, aynısı
kullanılır). `xlsx-js-style` kütüphanesi (bu dosyada zaten LN import'ta
kullanılıyor, aynı lazy-load deseni) ile `.xlsx` olarak indirilir. Dosya adı:
`stok-<depoAdi>-<tarih>.xlsx`.

Liste boşsa dışa aktarmadan `showToast('⚠️ Aktarılacak stok yok')`.

## Test/doğrulama planı

Statik: kolon adlarının/sırasının tasarımla eştiğini ve filtreleme mantığının
`renderStok()`'takiyle birebir aynı olduğunu kod okuyarak doğrulamak. Gerçek
indirme testi kullanıcı tarafından yapılacak.
