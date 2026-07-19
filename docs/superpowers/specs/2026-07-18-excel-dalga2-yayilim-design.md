# Excel Toplu Veri Yönetimi — Dalga 2 Yayılım — Tasarım

## Problem / Hedef

Dalga 1 (`stok_minimumlar`, `hesap_plani`, `doviz_kurlari`, `butce_kayitlari`)
tamamlandı. Dalga 2, `ortak-excel.js` motorunu 4 yeni hedefe yayıyor:
`cariler`, `demirbaslar`, `cek_senetler` (greenfield) ve RFQ
`tedarikci_teklif_kalemleri` (mevcut bespoke Excel akışının yükseltmesi).

## Kapsam

- **`muhasebe-cariler.html` → `cariler`**: doğal anahtar `kod`. Faz B3
  yetki desenine uyumlu (Yükle butonu `YETKI_HARITASI['cari_hesaplar']`
  kayit/tam olmadan disabled).
- **`muhasebe-demirbas.html` → `demirbaslar`**: doğal anahtar `kod`.
  `hesap_kodu`/`amortisman_hesap_kodu`/`oran_yillik` spec'te yok —
  `demirbasKaydet()` ile birebir aynı şekilde seçilen `kategori`'ye göre
  `KATEGORILER` map'inden otomatik türetiliyor.
- **`muhasebe-cek-senet.html` → `cek_senetler`**: bileşik doğal anahtar
  `no+banka+yon`. `cariId` spec'te yok — `kayitKaydet()` deseniyle
  birebir aynı: `cariAd`'a göre case-insensitive eşleştirme, yoksa
  otomatik yeni cari oluşturma (`kod:CARI_<timestamp>_<satır>`).
- **RFQ `tedarikci_teklif_kalemleri`** (satin-alma.html): mevcut
  `teklifleriExcelAktar`/`teklifExcelYukle`/`teklifExcelUygula` (bespoke,
  önizleme yok, denetim kaydı yok) `ortak-excel.js` tabanlı versiyonla
  değiştirildi. Bileşik doğal anahtar `firmaAd+urunKodu`, RFQ'ya özel
  (dosyada "Teklif Talep ID" sütunu yok, closure'da taşınıyor —
  kalemExcel pilot deseniyle aynı). 2 seviyeli çözümleme sayfa
  seviyesinde korundu: `firmaAd`→`tedarikci_teklif_id` (auto-create),
  `urunKodu`→`teklif_talep_kalem_id` (FK, RFQ'nun kendi kalemlerine
  karşı). Boş "Birim Fiyat" satırları sınıflandırmaya girmeden filtrelenip
  atlanıyor (eski "henüz teklif verilmemiş" davranışı korundu).

## Kapsam dışı

- Soft-delete edilmiş bir `cariler.kod`'un Excel'de tespiti (bilinen
  sınırlama, Dalga 1 planında da not edildi).
- Undo UI'ı, kolon-eşleştirme modalı, 10.000+ satır ilerleme çubuğu.
- Manuel "Tedarikçi Teklif Gir" modalı — değişmedi, Excel ile paralel
  yol olarak kalmaya devam ediyor.

## Beklenmeyen bulgu — gerçek RLS aktivasyonu

Kod yazımı sırasında paralel bir oturumun "Faz B0 — RLS Bağlantı
Katmanı" işini yaptığı görüldü (`auth_yetki_var()` fonksiyonu, henüz
hiçbir tabloya bağlanmadığı dokümante edilmiş). Ancak canlı testte
`cariler`/`demirbaslar`/`cek_senetler` tablolarına anon-key INSERT
denemesi gerçek bir RLS reddiyle karşılaştı (`42501`). Kullanıcı
Supabase Dashboard'dan doğruladı: bu 3 tabloda gerçek `yetki_insert`/
`yetki_select`/`yetki_update` politikaları `auth_yetki_var(<modül>,
<seviye>)`'e bağlı olarak aktif (örn. `cariler`→`cari_hesaplar`
modülü, `kayit` seviyesi). Yani B0 dokümantasyonu geride kalmış —
paralel oturum bu 3 tabloda gerçek RLS uygulamasını (Faz B1+) zaten
devreye almış.

**Sonuç**: bu 3 tabloya artık sadece gerçek giriş yapmış ve ilgili
modülde `kayit`/`tam` yetkisi olan bir kullanıcının `access_token`'ı
ile yazılabiliyor — anon-key ile (bu oturumun sahte test session'ı
dahil) yazma mümkün değil, bu güvenlik açısından doğru/beklenen
davranış. `stok_minimumlar`/`hesap_plani` (Dalga 1) ve
`tedarikci_teklif_kalemleri` (RFQ) bu kısıtlamaya tabi değil, anon-key
ile de test edilebildi.

## Doğrulama

`cariler`/`demirbaslar`/`cek_senetler`: sınıflandırma motoru (yeni/
güncelleme/hata tespiti, doğal anahtar eşleştirme) sahte oturumla
uçtan uca test edildi ve doğru çalıştığı doğrulandı — ama gerçek
canlı YAZMA testi RLS nedeniyle yapılamadı, kod `saveCari()`/
`demirbasKaydet()`/`kayitKaydet()` ile birebir aynı alan haritasını
kullanıyor olması üzerinden doğrulandı. Nihai canlı-yazma kabulü,
gerçek yetkili bir kullanıcının girişiyle yapılmalı.

RFQ: tam uçtan uca canlı test yapıldı (gerçek Supabase test verisiyle):
yeni satır yazma, aynı satırı farklı fiyatla upsert güncelleme, FK
hatası tespiti (RFQ'da olmayan ürün kodu), boş fiyat satırının
sessizce atlanması — hepsi doğrulandı, test verisi temizlendi.
