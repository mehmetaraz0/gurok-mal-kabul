# Excel Toplu Veri Yönetimi Modülü — Pilot: İç Talepler Kalemleri — Tasarım

## Problem / Hedef

Kullanıcı, ERP genelinde kullanılabilecek, çift yönlü (dışa/içe aktarma)
bir Excel toplu veri yönetimi modülü istiyor: bir tablo Excel'e aktarılır,
Excel'de toplu düzenlenir, geri yüklenir; sistem yazmadan önce bir
**önizleme/karşılaştırma ekranı** göstermeli (satırları yeni/güncelle/
değişiklik yok/hata/bulunamadı/yinelenen olarak sınıflandırıp eski-yeni
değeri yan yana göstermeli), kullanıcı onaylayınca toplu yazmalı, her
aktarımı denetim kaydına işlemeli, hatalı satırlar indirilebilir bir
raporla dönmeli. Referans: Infor LN'nin "Satınalma Talepleri - Satırlar"
ekranındaki Excel'e Aktar/Excel'den Yükle akışı.

Kod tabanı taraması, repoda **hiçbir Excel özelliğinde önizleme/diff adımı
olmadığını** doğruladı — 6 gerçek implementasyon var, hepsi dosya okunur
okunmaz doğrudan Supabase'e yazıyor. En değerli iki mevcut desen: (1)
`talepExcelUygula`/`teklifExcelUygula`'daki (satin-alma.html) "canlı durum
tazele" — yazmadan hemen önce kaydın güncel durumunu Supabase'den tekrar
çekip karşılaştırma, ve (2) `saveLnSiparisler`
(satin-alma-siparisler.html:141-153) — repodaki **tek gerçek toplu-atomik
yazma**: tek dizi-body POST'u `TABLE?on_conflict=<doğal_anahtar>` +
`Prefer: resolution=merge-duplicates` ile atıyor; Postgres bunu tek bir
çoklu-satır INSERT ifadesi olarak çalıştırdığı için satırlar ya hep
birlikte yazılır ya hiç yazılmaz — bu mimaride mevcut olan TEK gerçek
"transaction" ilkesi bu (backend/stored-procedure yok, anon key üzerinden
BEGIN/COMMIT yok).

## Kapsam

**Yeni paylaşılan modül `ortak-excel.js`** — 5 fonksiyon grubu:

1. `excelSablonIndir(spec, veriler, dosyaAdi)` — şablon sürümlü dışa
   aktarma, `xlsx-js-style` ile hücre biçimlendirme (kilitli sütun gri,
   zorunlu sütun başlığı sarı, izin verilen değerler başlık notu olarak).
2. `excelDosyaOku(file)` — `FileReader`+`XLSX.read`+`sheet_to_json`.
3. `excelSatirlariSiniflandir(spec, satirlar, mevcutKayitlar, opts)` —
   her satırı `{yeni,guncelleme,degisiklik_yok,hata,bulunamadi,mukerrer}`
   sınıflarından birine ayırır.
4. Önizleme/diff modalı — `ensureExcelOnizlemeModal()` (runtime DOM
   enjeksiyonu) + `excelOnizlemeGoster(siniflandirma, opts)`.
5. `excelTopluYaz`/`excelImportGecmisiYaz`/`excelHataRaporuIndir` — 500'lük
   gruplar halinde toplu-atomik yazma, denetim kaydı, hata raporu.

**Yeni Supabase tabloları**: `excel_import_gecmisi` + `excel_import_satirlari`
(`talep_onay_gecmisi` ile aynı üst/alt FK deseni, `eski_deger`/`yeni_deger`
jsonb — ileride UPDATE-satırları için geri alma imkanı, v1'de undo UI'ı yok).

**Pilot — satin-alma.html İç Talepler kalemleri**: `openTalepDetay()`'e
`t.durum==='bekleyen'&&t.asama==='depo'` koşullu yeni buton. Mevcut
`talepleriExcelAktar`/`talepExcelUygula` (bekleyen taleplere toplu ONAY
KARARI Excel'i) ile KARIŞTIRILMAMALI — o karar için, bu pilot talebin ürün
SATIRLARINI toplu oluşturma/düzenleme için, ayrı bir yetenek.
`onay-motoru.js`'e dokunulmuyor; kalem düzenleme sadece talep henüz onay
zincirinde hiç ilerlememişken izinli (cost aşaması tutarı orijinal
kalemlere göre belirlediği için, sonrasında kalem değiştirmek onay
denetim izini bozar).

## Kapsam dışı

- Diğer tablolara yayılım (Faz 2).
- 10.000+ satır için ilerleme çubuğu/yeniden-deneme sertleştirmesi (pilot
  gerçekçi satır sayılarında — İç Talepler kalemleri genelde 5-100 satır).
- Undo UI'ı (şema hazır, akış yok).
- Kolon-eşleştirme modalı (`#mLNKolon` tarzı) — pilotun export şablonu
  sabit başlıklı, gerekmiyor.
- Gerçek Excel açılır-liste (native data validation) — `xlsx-js-style`
  desteklemiyor, yerine kilitli/renkli referans + başlık notu.
- Alan/sütun bazlı sunucu-taraflı yetkilendirme — repoda hiç emsali yok,
  anon key paylaşımlı olduğu için sunucuda zorlanamaz; sadece istemci
  tarafı (yumuşak) kısıt — bu uygulamanın genel güvenlik modeliyle tutarlı.
- Mevcut `talepleriExcelAktar`/`talepExcelUygula` (onay-kararı Excel'i) —
  dokunulmuyor.

## Mimari

`ortak-excel.js` repo kökünde, `<head>`'de `ortak.js`'den hemen sonra
yüklenir (senkron). `spec` nesnesi tablo-agnostik: `{alan, baslik, tip,
zorunlu, kilitli, gizli, genislik, izinliDegerler}` dizisi — hem export
hem sınıflandırma hem önizleme hem hata raporu bu tek spec'i kullanır.

Eşleştirme mantığı: kilitli ID sütunu doluysa gerçek `id` (UUID) ile
eşleştirilir (yoksa `bulunamadi`); boşsa doğal anahtar (`urun_kodu`, yoksa
`urun_adi`) ile — IDler her zaman sunucuda üretiliyor (`gen_random_uuid()`),
bu yüzden yeni satırlarda ID sütunu boş bırakılır. Dosya içinde aynı doğal
anahtarın tekrarı `mukerrer` sınıfına düşer.

5 aktarım modu somut karşılığı:

| Mod | Yazılan | Hata satırları |
|---|---|---|
| Sadece Güncelleme | `guncelleme` | atlanır |
| Sadece Yeni Kayıt | `yeni` | atlanır |
| Güncelleme + Yeni Kayıt | `guncelleme`+`yeni` | sessizce atlanır |
| Hatalıları Atla, Kalanını Uygula | `guncelleme`+`yeni` | atlanır, önizlemede "N satır atlanacak, devam?" onayı |
| Herhangi Bir Hatada Tümünü İptal Et | — | dosyada 1 `hata` satırı varsa Uygula pasif |

`mukerrer`/`bulunamadi` hiçbir modda yazılmaz.

**Önizleme modalı, bilinçli mimari sapma:** repodaki her modal statik
HTML (sayfaya gömülü); bu ilk kez runtime'da JS'den DOM'a enjekte edilen
modal olacak (`ensureExcelOnizlemeModal()`, idempotent). Gerekçe: modül
Faz 2'de tüm ERP'ye yayılacaksa, her sayfaya aynı modal HTML'ini
kopyalamak `#mLNKolon`'da zaten görülen tekrar sorununu büyütür.

**Operasyon-seviyesi canlı-durum kilidi (pilotta):** Uygula'ya basılınca,
herhangi bir satır yazılmadan önce tek bir canlı GET
(`satin_alma_talepleri?id=eq.<id>&select=durum,asama`) — `bekleyen`+`depo`
değilse TÜM aktarım iptal edilir (satır bazlı değil, işlem bazlı — kısmi
kalem güncellemesi onay denetim izini bozar).

## Doğrulama / Bayat Veri

Operasyon-seviyesi canlı-durum kilidi, iki kişinin aynı talebin
kalemlerini aynı anda Excel ile düzenlemesi veya biri Excel yüklerken
diğerinin talebi onaya ilerletmesi senaryosunu, kısmi/tutarsız yazmayı
engelleyerek kapatır.

## Test/doğrulama planı

Statik: `excelSatirlariSiniflandir`'ın 6 sınıfı da doğru ürettiğini, 5
modun tabloyla birebir eşleştiğini, `excelTopluYaz`'ın 500'lük gruplar
halinde `on_conflict` ile POST attığını kod okuyarak doğrulamak.

Gerçek uçtan uca test: `bekleyen`+`depo` bir talep aç → kalemleri Excel'e
aktar → bir satırın miktarını değiştir, yeni satır ekle, bir ürün kodunu
boz, bir satırı çoğalt → geri yükle → önizlemede sınıfların doğru
göründüğünü kontrol et → uygula → `satin_alma_talep_kalemleri`,
`excel_import_gecmisi`/`satirlari`, hata raporunu doğrula → talebi cost
aşamasına ilerlet → butonun kaybolduğunu, eski dosyayla yeniden
denemenin tüm işlemi iptal ettiğini doğrula.
