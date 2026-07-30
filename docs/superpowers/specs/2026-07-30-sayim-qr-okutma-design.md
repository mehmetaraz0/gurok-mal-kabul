# Sayım — Koli QR ile Otomatik Sayım — Tasarım

## Context

`stok-takip.html`'deki "📊 Sayım" (fiziksel/cycle count) sekmesi şu an tamamen
elle giriş: kullanıcı filtrelenmiş ürün listesindeki her satıra "Sayılan
Miktar" yazıyor. Depoda hem koli/QR etiketli ürünler hem de etiketsiz
(dökme/açık) ürünler var — kullanıcı, Mal Kabul'de zaten basılan koli
QR'larını (`KOLI:<uuid>` → `koli_etiketleri` tablosu) sayım sırasında okutup
sistemin otomatik toplama yapmasını istiyor.

Bu mekanizma yeni değil — aynı `KOLI:<uuid>` QR + `koli_etiketleri` lookup +
`Html5Qrcode` kamera entegrasyonu iki yerde zaten kanıtlanmış durumda:

- `stok-takip.html` → Manuel Çıkış modalı (`qrOkundu()`, satır ~1412): okutulan
  koli çıkış formunu otomatik dolduruyor, FEFO uyarısı veriyor (bu, stoktan
  bir şey ÇIKARILDIĞI için anlamlı).
- `depo-siparis.html` → Depo transfer onayı (`depoQrOkundu()`, satır ~804):
  aynı lookup + **1.5 saniyelik debounce** (kamera saniyede ~10 kare okuduğu
  için aynı karenin tekrar tetiklenmesini önler) + **oturum bazlı çift-okutma
  engeli** (`_onayKolileri.some(k=>k.id===koliId)` → "Bu koli bu talepte
  zaten okutuldu").

Sayım bu iki koruma desenini (debounce + çift-okutma engeli) birebir
kullanacak. FEFO kontrolü ise Sayım'a **taşınmayacak** — sayım stoktan bir
şey çıkarmıyor/taşımıyor, sadece mevcut durumu kayıt altına alıyor, bu yüzden
"hangi koli önce çıkmalı" sorusu burada anlamsız.

## Kapsam

1. Sayım sekmesine **"📷 Koli QR ile Say"** düğmesi eklenir (arama kutusunun
   altına, mevcut Manuel Çıkış/Depo transfer düğmeleriyle aynı görsel
   stilde).
2. Bir koli QR'ı okutulunca:
   - Debounce (1.5sn) + oturum bazlı çift-okutma engeli (aynı koli id
     ikinci kez okutulursa reddedilir).
   - `koli_etiketleri`'den koli çekilir; bulunamazsa reddedilir.
   - `koli.durum!=='depoda'` ise reddedilir (zaten çıkmış bir koli
     sayılamaz).
   - `koli.depo_kodu!==aktifDepoId` ise reddedilir (farklı depoya ait koli
     bu sayıma dahil edilemez).
   - Geçtiyse: `koli.urun_kodu`'na karşılık gelen ürünün Sayım listesindeki
     "Sayılan Miktar" değerine `koli.miktar` **eklenir** — kullanıcının o an
     hangi kategori/arama filtresine baktığından bağımsız olarak doğru ürün
     bulunur.
   - Anlık toast geri bildirimi: `✅ <ürün> +<miktar> <birim> (toplam: X,
     N koli)`.
3. **Elle giriş aynen kalır** — etiketsiz ürünler için zorunlu, etiketli bir
   üründe de QR ile gelen toplamın üzerine elle düzeltme (örn. hasarlı
   ürün) yapılabilir; input normal bir `<input type=number>` olarak kalır,
   QR sadece onu hızlıca dolduran bir kısayoldur.
4. **Yeni Supabase tablosu/kolonu yok.** `koli_etiketleri` zaten gereken her
   şeyi taşıyor (`urun_kodu, urun_adi, miktar, birim, depo_kodu, durum`);
   `sayim_oturumlari`/`sayim_detaylari`'ya yazım anı ve şekli
   (`sayimTamamla()`) hiç değişmiyor — QR sadece o yazımdan önceki veri
   girişini hızlandırıyor.

## Tasarım kararı: QR toplamları filtre değişikliğinde silinmez

Mevcut `filterSayimKat()` her kategori değişiminde `sayimSatirlari={}`
yaparak elle girilen tüm değerleri sıfırlıyor (bu, "kısmi/filtreli sayım"
modelinin zaten var olan, kasıtlı bir davranışı — bu tasarımın kapsamı
dışında, dokunulmuyor). Ancak QR ile depoda dolaşarak okutma yapan bir
kullanıcı, yanlışlıkla bir filtre sekmesine dokunursa tüm QR ilerlemesinin
silinmesi kabul edilemez — bu yüzden QR ile biriken toplamlar
(`_sayimQrToplam`) **ayrı, filtre değişiminden etkilenmeyen bir state'te**
tutulur ve her `renderSayimYeni()` çağrısında görünür satırlara yeniden
uygulanır. Sadece yeni bir sayım oturumuna girildiğinde (`renderSayimTab()`)
sıfırlanır.

## Kapsam dışı

- FEFO uyarısı — sayım stok hareketi değil, anlamsız (yukarıda açıklandı).
- Etiketsiz ürünler için barkod/QR üretimi — ayrı bir iş, bu tasarım sadece
  zaten var olan koli QR'larını okutuyor.
- `sayim_oturumlari`/`sayim_detaylari` şemasında değişiklik.
- Sayım onay akışının (cost_control onay/red) değiştirilmesi.
- Kısmi koli sayımı (bir kolinin içinden bir kısmının sayılması) — bir koli
  ya tam okutulur ya hiç, kısmi miktar için elle düzeltme kullanılır.

## Mimari

Yeni global state'ler (`stok-takip.html`, mevcut sayım globalleriyle
birlikte):

```js
let _sayimQrToplam={}; // {lnKod:{miktar,koliSayisi}}
let _sayimOkutulanKoliler=[]; // bu oturumda okutulan koli id'leri
let _sayimQrScanner=null;
let _sayimSonOkumaZamani=0;
```

`renderSayimTab()` içine `_sayimQrToplam={};_sayimOkutulanKoliler=[];`
eklenir (yeni oturum = temiz başlangıç). `filterSayimKat()`'a
**dokunulmaz**.

`renderSayimYeni()`'in ürün satırı oluşturma döngüsüne, her satır için
`_sayimQrToplam[s.lnKod]` varsa input'un başlangıç değeri olarak
uygulanması eklenir; input'a `id="sayim-inp-<lnKod>"` verilir (şu an hiç
id'si yok — QR okutmanın görünür bir satırı doğrudan güncelleyebilmesi
için gerekli).

Yeni fonksiyonlar — `depoQrOkundu()`'nun (`depo-siparis.html`) birebir
aynı deseni, hedef farklı:

- `sayimQrOkutmaBaslat()` / `sayimQrOkutmaDurdur()` — `Html5Qrcode`
  kamera aç/kapa (mevcut `qrOkutmaBaslat()` ile aynı CDN yükleme deseni).
- `sayimQrOkundu(text)` — debounce, çift-okutma engeli, `koli_etiketleri`
  lookup, `durum`/`depo_kodu` kontrolü, `_sayimQrToplam` güncelleme,
  görünürse DOM input + `sayimFarkGuncelle()` tetikleme, toast.

## Test/Doğrulama Planı

Tarayıcıda: fabrike edilmiş `koli_etiketleri` satırlarıyla (gerçek kamera
gerekmeden `sayimQrOkundu('KOLI:<test-id>')` doğrudan çağrılarak) —

- Geçerli koli okutulunca doğru üründe toplamın arttığını,
- Aynı koli ikinci kez okutulunca reddedildiğini,
- `durum='cikti'` bir koli okutulunca reddedildiğini,
- Farklı depoya ait bir koli okutulunca reddedildiğini,
- Kategori filtresi değiştirilince QR toplamlarının kaybolmadığını (yeni
  filtrede satır görününce doğru değeri gösterdiğini),
- Elle girilen bir değerin üzerine QR okutulunca (veya tam tersi) doğru
  şekilde toplandığını,
- `sayimTamamla()`'nın QR ile oluşan satırları da elle girilenler gibi
  normal şekilde işlediğini (kod değişmedi ama uçtan uca doğrulanmalı)

doğrulamak gerekiyor.

## İlgili

`stok-takip.html` (Manuel Çıkış `qrOkundu()`, Sayım sekmesi),
`depo-siparis.html` (`depoQrOkundu()` — çift-okutma engeli deseni),
`mal-kabul-liste.html` (`koliEtiketYazdir()` — QR'ların nereden geldiği).
