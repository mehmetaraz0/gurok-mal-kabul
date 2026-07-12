# Talep Ver — Excel'den Toplu Ürün Girişi — Tasarım

## Problem / Hedef

`depo-siparis.html`'de mutfak/bar rolündeki kullanıcılar "Talep Ver"
sekmesinde yeni bir malzeme talebi oluştururken ürünleri tek tek "+ Ekle"
butonuyla, satır satır otomatik-tamamlama ile giriyor. Talep 20-30 kalemi
bulduğunda bu çok yavaş. Kullanıcı, Excel'de tek satırlık bir şablonu
çoğaltıp (Ürün Kodu / Ürün Adı / Miktar / Birim doldurarak) toplu olarak
içe aktarabilmek istiyor.

## Kapsam

- Sadece "Talep Ver" sekmesi (yeni talep oluşturma), mutfak/bar tarafı
  (`#tVer` içeriği, `#usatirlar` — `depo-siparis.html:519` civarı).
- "Gelen Talepler" (onay/red) tarafı kapsam dışı — bu ayrı bir akış,
  dokunulmuyor.
- Depo tarafının "Yeni Sipariş" modalındaki ikinci `#usatirlar` (satır
  ~1011) bu tasarımın kapsamı dışında — sadece mutfak/bar'ın Talep Ver
  formuna ekleniyor.

## Tasarım

Ürünler kartındaki "+ Ekle" butonunun yanına iki yeni buton eklenir:

- **"📄 Şablon İndir"** — kolon başlıkları (`Ürün Kodu`, `Ürün Adı`,
  `Miktar`, `Birim`, `Not`) ve 1 örnek satır içeren boş bir `.xlsx` indirir.
  Kullanıcı bu dosyayı açıp örnek satırı çoğaltıp doldurur.
- **"📥 Excel'den Yükle"** — dosya seçtirir, satırları okuyup mevcut ürün
  listesine ekler.

**İçe aktarma davranışı:**
1. Dosya `xlsx-js-style` ile okunur (aynı lazy-load deseni, bu dosyada
   zaten LN kataloğu importunda kullanılıyor).
2. Her satır `{kod, ad, miktar, birim, not}` şeklinde bir `US` satırına
   çevrilir. `Ürün Adı` boşsa o satır atlanır (boş satır).
3. İçe aktarmadan önce, `US` içindeki hâlihazırda tamamen boş satırlar
   (ad VE miktar ikisi de boş — formun ilk açılışında `addUS()` ile
   eklenen varsayılan boş satır gibi) temizlenir. Kullanıcının elle
   doldurduğu dolu satırlara dokunulmaz, yüklenenler bunların ARDINA
   eklenir (üzerine yazma yok).
4. `rUS()` çağrılarak liste yeniden çizilir — kullanıcı "Talep Gönder"e
   basmadan önce tüm satırları ekranda görüp kontrol edebilir/düzenleye­bilir/silebilir.
5. Ürün kodu katalogla (`URUN_DB`) eşleşmese bile satır kabul edilir
   (serbest metin) — mevcut elle-giriş davranışıyla birebir aynı: kullanıcı
   otomatik-tamamlamadan bir öneri seçmeden de ürün adı yazabiliyor, kod
   boş kalabiliyor.
6. İçe aktarma sonunda `showToast('✅ N ürün yüklendi')`.
7. Dosya boşsa/geçerli satır yoksa `showToast('⚠️ Yüklenecek satır bulunamadı')`
   ve `US` değiştirilmez.

**Otomatik gönderim YOK** — içe aktarma sadece formu doldurur, "Talep
Gönder" butonuna basmak kullanıcının elindedir.

## Kapsam dışı

- Gelen Talepler (onay/red) Excel round-trip — ayrı, önceden tasarlanmış
  bir konuydu, bu işin parçası değil.
- Depo'nun "Yeni Sipariş" modalına aynı özelliğin eklenmesi — istenirse
  ayrı bir iş olarak ele alınabilir.
- Ürün kodu/adı katalog doğrulaması veya otomatik düzeltme — serbest metin
  olarak kabul ediliyor, mevcut davranışla tutarlı.

## Test/doğrulama planı

Statik: şablon kolonlarının içe aktarma kodunun okuduğu kolonlarla birebir
eştiğini, boş satır temizleme mantığının doğru çalıştığını kod okuyarak
doğrulamak. Gerçek Excel indirme/yükleme testi kullanıcı tarafından
yapılacak (Node/Python bu ortamda yok).
