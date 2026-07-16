# Satın Alma — RFQ / Teklif Yönetimi — Tasarım

## Problem / Hedef

Sistemde tedarikçilerden fiyat teklifi isteme, birden fazla teklifi
karşılaştırma ve en iyisini siparişe dönüştürme akışı yok — ürün denetim
raporunda en yüksek öncelikli (85/100) P1 eksik olarak işaretlendi. Bugün
teklif süreci tamamen sistem dışında (telefon/e-posta) yürüyor: `Sipariş
Oluştur`'daki `tahminiFiyat` alanı tek satırlık, tek tedarikçiye bağlı bir
tahmin; yazdırılan sipariş formundaki "Teklif Fiyatı..." sütunu boş
bırakılıp elle doldurulmak üzere basılıyor. Hiçbir teklif hiç sisteme
girmiyor, karşılaştırma yapılamıyor.

## Kapsam

- Onaylanmış bir talebin detayında yeni **"📨 Teklif İste"** butonu — talebin
  kalemlerinden bir RFQ (teklif talebi) oluşturur.
- Yeni **"📨 Teklifler"** sekmesi: RFQ listesi (açık/kapandı).
- RFQ detayında tedarikçi ekleme (ürünlere göre otomatik öneri + manuel
  arama), her tedarikçi için elle fiyat girişi VE Excel toplu
  yükleme/indirme.
- Karşılaştırma tablosu: ürün × tedarikçi, en düşük fiyat vurgulu, satır
  bazında kazanan seçilebilir.
- Seçilenleri siparişe dönüştürme (firma bazlı gruplama).

## Kapsam dışı

- Bağımsız/sepetten RFQ başlatma — sadece onaylanmış talepten başlar.
- Tedarikçi portalı / otomatik e-posta ile yanıt toplama — Excel elle
  gönderilip elle geri yükleniyor.
- Teslim süresi/MOQ gibi ek teklif kriterleri — sadece birim fiyat.
- `firmalar` Supabase tablosu oluşturmak — statik `FIRMA_DB` + serbest metin
  `firma_ad` deseni korunur (kod tabanının geri kalanıyla tutarlı:
  `siparisler`/`mal_kabuller`/`faturalar` hepsi `firma_ad`'ı serbest metin
  tutuyor, `firmaId` Supabase round-trip'inde zaten atılıyor).
- Kısmi teklif girişi/versiyon takibi — bir tedarikçinin teklifi tek seferde
  girilir.

## Mimari

Dört yeni tablo:

**`teklif_talepleri`** — RFQ başlığı: `id, talep_id (FK), otel_id,
olusturan_ad, olusturma_tarihi, durum ('acik'/'kapandi'), not_alani`.

**`teklif_talep_kalemleri`** — RFQ'ya konu ürünler: `id, teklif_talep_id
(FK), urun_kodu, urun_adi, miktar, birim`.

**`tedarikci_teklifler`** — RFQ'ya eklenen her tedarikçi: `id,
teklif_talep_id (FK), firma_ad, firma_kodu, durum
('bekleniyor'/'geldi'/'reddetti'), teklif_tarihi, not_alani`.

**`tedarikci_teklif_kalemleri`** — tedarikçinin ürün başına verdiği fiyat:
`id, tedarikci_teklif_id (FK), teklif_talep_kalem_id (FK), birim_fiyat,
not_alani`.

Mevcut desenlerin doğrudan uyarlaması:
- `teklifIste(talepId)` — `talepSipariseDonustur`'daki POST deseni.
- `renderTeklifler()`/`openTeklifDetay()` — `renderTalepler`/
  `openTalepDetay` ile birebir aynı liste+detay-modal iskeleti.
- `teklifTedarikciEkle` — `autoFirma`'nın çoklu-eşleşme versiyonu (mevcut
  `autoFirma` sadece ilk eşleşen firmayı alıyor, burada RFQ kalemlerindeki
  her ürün için TÜM eşleşen firmalar toplanıp tekilleştirilir).
- Elle fiyat girişi — `fkDetayAc`'taki (Fiyat Kontrolü) ürün×fiyat giriş
  tablosu deseni.
- Excel export/import — `talepleriExcelAktar`/`talepExcelUygula` (İç
  Talepler) ile birebir aynı desen; export kolonları `Ürün Kodu, Ürün Adı,
  Miktar, Birim, Firma, Birim Fiyat` (Firma sütunu önceden eklenmiş her
  tedarikçi için tekrarlanan satırlar üretir).
- Siparişe dönüştürme — `spGrupla()`'daki firma bazlı gruplama +
  `siparisler`/`siparis_kalemleri` insert deseni, `tahmini_fiyat` = seçilen
  `birim_fiyat`.

## Akış

1. Talep, çok aşamalı onay akışının son katmanından geçip
   `durum='onaylandi'` olur.
2. Satınalma, talep detayında "📨 Teklif İste"e basar → `teklif_talepleri` +
   `teklif_talep_kalemleri` oluşur, Teklifler sekmesine yönlendirilir.
3. RFQ detayında tedarikçi eklenir (öneri listesinden veya manuel arama) →
   her biri için `tedarikci_teklifler` satırı (`durum:'bekleniyor'`).
4. Fiyat geldikçe: tek tedarikçi için elle giriş modalı, veya "Excel'e
   Aktar" ile tüm RFQ+tedarikçi satırlarını indirip toplu doldurup "Excel'den
   Yükle" ile geri yükleme. Her iki yol da `tedarikci_teklif_kalemleri`
   doldurur ve ilgili `tedarikci_teklifler.durum='geldi'` yapar.
5. Karşılaştırma tablosunda her ürün satırı için en düşük fiyatlı tedarikçi
   varsayılan seçili gelir (yeşil vurgu); satınalma isterse başka
   tedarikçiyi seçer.
6. "Seçilenleri Siparişe Dönüştür" → seçimler `firma_ad`'a göre gruplanır,
   her grup için `siparisler`+`siparis_kalemleri` oluşur (mevcut Sipariş
   Takip akışına aynen girer), `teklif_talepleri.durum='kapandi'` yazılır.

## Doğrulama / Bayat Veri

Excel içe aktarma, İç Talepler'deki `talepExcelUygula` ile aynı desen: her
satır uygulanmadan hemen önce RFQ'nun güncel `durum`'u canlı GET ile
tazelenir — `kapandi` ise o RFQ'ya ait satırlar atlanır ve "zaten kapanmış"
olarak raporlanır. Bu, iki kişinin aynı RFQ'yu aynı anda kapatıp Excel
yüklemesi çakışmasını önler.

## Test/doğrulama planı

Statik: dört tablonun her fonksiyonda tutarlı isimle kullanıldığını, Excel
export/import kolon adlarının birebir eşleştiğini, karşılaştırma
tablosundaki min-fiyat hesabının doğru çalıştığını kod okuyarak doğrulamak.

Gerçek uçtan uca test (kullanıcı, SQL migration'dan sonra): onaylanmış bir
talepten RFQ oluştur → 3 tedarikçi ekle → birini elle, ikisini Excel ile
fiyatla → karşılaştırma tablosunda en düşük vurgulanıyor mu kontrol et →
karışık seçim yap → siparişe dönüştür → oluşan siparişlerin doğru
firma(lar)a bölündüğünü ve fiyatların doğru taşındığını doğrula.
