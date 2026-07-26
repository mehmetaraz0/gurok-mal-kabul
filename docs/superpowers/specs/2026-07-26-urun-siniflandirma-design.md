# Ürün Kalem Kodu Sınıflandırma / Alt Sınıflandırma — Tasarım

## Context

`gurok_veritabani.js`'teki 1264 ürünün her biri zaten bir `grup` koduna sahip (`YIY01`..`YIY12`, 12 grup — bkz. ürün kodu deseni `<grup><6 haneli sıra>`, örn. `YIY01000002`). Bu kodların hiçbirinin okunabilir bir adı yok ve altında hiç alt kategori yok. Kullanıcı, mevcut ana grupların altına bir alt-grup seviyesi eklemek istiyor — örnek: `YIY04` (Dondurma) altında `YIY0401` (Kartonlu), `YIY0402` (Çubuk Dondurmalar). Kullanıcının netleştirdiği kapsam kararları:

- **Derinlik**: 2 seviye yeterli (Ana Grup → Alt Grup), 3. seviyeye gerek yok.
- **Mevcut ürün kodları değişmez** — `YIY01000002` gibi kodlar hem `gurok_veritabani.js`'te hem Supabase'deki gerçek `public.urunler` tablosunda (bkz. `urun_birim_donusum` tablosunun `urun_kodu → urunler(kod)` FK'si) sabit kalıyor; binlerce stok hareketi/mal kabul/sipariş kaydı bu koda referans veriyor, değiştirmek geriye dönük veriyi kırar.
- **Sınıflandırma verisi ayrı bir Supabase tablosunda** tutulacak (statik `gurok_veritabani.js` dosyasına dokunulmayacak) — `urun_birim_donusum` ile birebir aynı mimari desen: ürün kodu sabit kalır, ek bir eşleme tablosu ürünü etiketler.
- **1264 mevcut ürünün alt gruba atanması**: Excel toplu içe aktarma ile (bu kod tabanında zaten kurulu, kanıtlanmış bir desen — `ortak-excel.js` + `stok-takip.html`'in `stok_minimumlar` entegrasyonu, bkz. Mimari bölümü).
- **Yönetim ekranı**: mevcut `urun-yonetimi.html` (zaten ürün bazlı metadata — birim dönüşümü — yönetiyor, aynı arama/liste akışına eklenir).
- **Yeni ürün kodları**: kullanıcı "şu anki kod sistemi duracak, yeni ürün kodları için de bu alanı geliştireceğiz" dedi — yani gelecekte eklenecek ürünler de AYNI `urun_siniflandirma` eşleme tablosu üzerinden sınıflandırılacak (kodun kendisi büyümeyecek, ayrı bir "yeni ürün ekleme" akışı bu planın kapsamında değil çünkü böyle bir akış bugün hiç yok — ürünler hâlâ `gurok_veritabani.js`'e elle ekleniyor).

## Kapsam

### 1) Kategori Kataloğu (küçük, form tabanlı — 12 ana grup + tahmini 30-50 alt grup)

Yeni iki tablo:
- `urun_ana_gruplari` (`ana_grup_kod` — mevcut `YIY01`..`YIY12` değerleriyle eşleşir, `ana_grup_adi`, `sira`, `silindi`)
- `urun_alt_gruplari` (`alt_grup_kod` — örn. `YIY0401`, `ana_grup_kod` FK, `alt_grup_adi`, `sira`, `silindi`)

`urun-yonetimi.html`'e yeni bir "Kategori Kataloğu" bölümü: ana grupları listele (12 satır, ilk kurulumda `ana_grup_adi` boş — kullanıcı elle doldurur, kod bunu tahmin ETMEZ), her ana grubun altına alt grup ekle/listele/adlandır formu. Bu, 1264 satırlık büyük veri değil — Excel gerekmez, doğrudan form.

### 2) Ürün → Alt Grup ataması (büyük, 1264 satır — Excel toplu)

Yeni tablo: `urun_siniflandirma` (`urun_kodu` FK → `public.urunler(kod)`, `alt_grup_kod` FK → `urun_alt_gruplari(alt_grup_kod)`, `guncelleme_tarihi`).

`urun-yonetimi.html`'in mevcut arama sonuçlarına (her ürün satırına) bir "Alt Grup" seçici (o ürünün `grup` koduna uyan alt gruplarla filtrelenmiş `<select>`) + "Kaydet" eklenir — tekli/nokta düzeltmeler için (`donusumKaydet` ile birebir aynı desen).

Toplu atama için: **Excel'e Aktar** (1264 ürün + mevcut alt-grup ataması varsa) / **Excel'den Yükle** — `stok-takip.html`'deki `stokMinimumExcelAktar/Yukle/Uygula` üçlüsüyle birebir aynı iskelet (`excelSablonIndir`/`excelDosyaOku`/`excelSatirlariSiniflandir`/`excelOnizlemeGoster`/`excelTopluYaz`/`excelImportGecmisiYaz`). Fark: doğal anahtar yine `urun_kodu`, ama yazılacak değer `alt_grup_kod` (serbest metin değil — Excel'deki değer önce mevcut `urun_alt_gruplari` kataloğuna karşı doğrulanır, kataloğa yoksa satır hata olarak işaretlenir; bu, yazım hatalarıyla kataloğu kirletmeyi önler).

## Mimari kararı: neden ayrı eşleme tablosu (gömülü kod değil)

Kullanıcının orijinal örneği (`YIY0401` gibi kodun kendisinin büyümesi) yerine ayrı tablo seçildi çünkü:
- Ürün kodu `stok_hareketleri`, `mal_kabul_urunleri`, `siparis_kalemleri` gibi düzinelerce tabloda serbest metin/FK olarak duruyor — kodun formatını değiştirmek geriye dönük tüm veriyi etkiler.
- `urun_birim_donusum` zaten AYNI problemi (ürüne ek metadata ekleme, kodu değiştirmeden) bu desenle çözmüş durumda — tutarlılık için aynı desen tekrar kullanılıyor.

## Test/doğrulama planı

Statik: yeni 3 tablonun her fonksiyonda tutarlı isimle kullanıldığını, Excel export/import kolon adlarının birebir eşleştiğini kod okuyarak doğrulamak; `excelSatirlariSiniflandir`'a geçilen `fkSet`'in hem `urunler.kod` (ürün var mı) hem `urun_alt_gruplari.alt_grup_kod` (alt grup kataloğa kayıtlı mı) için ayrı ayrı doğrulama yaptığını kontrol etmek.

Gerçek uçtan uca test (kullanıcı, SQL migration'dan sonra): Kategori Kataloğu'ndan birkaç ana gruba ad ver + birkaç alt grup ekle (örn. YIY04 → Dondurma, YIY0401 → Kartonlu, YIY0402 → Çubuk Dondurmalar) → ürün listesinden bir ürüne tekli alt-grup ata, kaydedildiğini doğrula → Excel'e aktar, birkaç satırı doldur, geri yükle, önizlemede yeni/güncelleme sayılarının doğru göründüğünü ve kataloğa olmayan bir alt-grup kodu girilince satırın hata olarak işaretlendiğini doğrula.

## Kapsam dışı

- Yeni ürün oluşturma akışı (bugün hiç yok, bu planın parçası değil).
- 3. seviye alt-alt-kategori (kullanıcı "1 ana 1 alt yeterli" dedi).
- Ana/alt grup adlarının otomatik tahmin edilmesi — kullanıcı elle dolduracak, kod uydurmayacak.
