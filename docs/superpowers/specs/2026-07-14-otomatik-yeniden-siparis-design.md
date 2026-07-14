# Otomatik Yeniden Sipariş Tetikleme — Tasarım

## Problem / Hedef

Minimum stok altına düşen ürünler için hiçbir sistematik uyarı/talep akışı
yok — depo sorumlusunun fark edip manuel İç Talep açması gerekiyor, unutma
riski var. Bu, depo modülü kıyaslama raporunda (`depo-modul-kiyaslama-raporu.html`)
tespit edilen Kritik #2 eksiği.

## Kapsam

- `satin-alma.html` açıldığında, tüm depolardaki (810 + 811, her otelin tüm
  depoları) güncel stok, ürün bazlı global minimum değerleriyle (`db.minimumlar[lnKod]`)
  karşılaştırılır.
- Minimum altına düşen ürünler bulunursa bir uyarı şeridi + öneri listesi
  gösterilir — kullanıcı onaylamadan hiçbir kayıt oluşmaz.
- Kullanıcı seçtiği ürünlerden, mevcut İç Talep akışıyla (`satin_alma_talepleri`/
  `satin_alma_talep_kalemleri`, `ytKaydet()`'in aynısı) **otel bazında** gruplu
  talepler oluşturur.

## Kapsam dışı

- Gerçek zamanlı/arka plan tetikleme — bu uygulamanın sunucu/cron altyapısı
  yok, kontrol sadece ilgili sayfa (`satin-alma.html`) açıldığında çalışır.
- Depo bazlı gruplama — kullanıcı onayıyla otel bazlı gruplama seçildi
  (mevcut `satin_alma_talepleri.departman` alanı zaten sabit bir enum,
  "DEPO" değeri kullanılacak, depo ayrımı tutulmuyor).
- Minimum değerlerinin depo bazlı hale getirilmesi — mevcut global
  (ürün başına tek minimum, tüm depolarda aynı eşik) model korunuyor,
  bu ayrı bir iyileştirme konusu.
- Otomatik/tam onaysız talep oluşturma — kullanıcı onayıyla insan-döngüde
  (human-in-the-loop) tasarım seçildi, sessiz otomatik oluşturma yok.

## Mimari

`satin-alma.html` şu an `stok`/`stok_minimumlar` tablolarını hiç yüklemiyor.
Yeni bir `stokMinimumKontrolEt()` fonksiyonu eklenir — sayfanın `init()`
akışında, mevcut `loadDB()`'den sonra bir kez çağrılır, `stok` ve
`stok_minimumlar` tablolarını ayrı bir fetch ile çeker (mevcut `loadDB()`'e
karıştırılmaz — bu veri sadece bu özellik için gerekli, sayfanın normal
yükleme performansını etkilememesi için ayrı tutulur).

Karşılaştırma: her `stok` satırı (`depo_kodu`, `urun_kodu`, `miktar`) için
`stok_minimumlar`'daki karşılık gelen `min_miktar` bulunur (aynı
`stok-takip.html`'deki `getStokDurum()` mantığı — min yoksa/0 ise atlanır,
`miktar<=min` ise eksik sayılır). Eksik bulunan satırlar `otelFromDepoId(depo_kodu)`
ile otele göre gruplanır.

## Öneri Listesi UI

İç Talepler sekmesinin üstünde, eksik varsa bir uyarı şeridi:
**"⚠️ N ürün minimum altında — Öneri listesini gör"**. Tıklanınca modal açılır:
her otel başlığı altında ürün satırları (ürün adı, depo, mevcut/minimum
miktar, önerilen sipariş miktarı = `min_miktar - miktar`, varsayılan işaretli
onay kutusu). "Seçilenlerden Talep Oluştur" butonu.

## Talep Oluşturma

`ytKaydet()` şu an doğrudan DOM'dan okuyor (`document.getElementById('yt-dept').value`
ve global `YT_SATIRLAR`) — bu haliyle otomatik akıştan çağrılamaz. Bu yüzden
`ytKaydet()`'in Supabase'e yazan çekirdeği, parametre alan bir yardımcı
fonksiyona (`talepKaydet(departman,aciliyet,notAlani,satirlar,otelId)`)
çıkarılır; hem mevcut manuel form hem yeni otomatik akış bu ortak
fonksiyonu çağırır — DOM okuma mantığı sadece manuel formda kalır, kod
tekrarı olmaz. Seçilen satırlar otel bazında gruplanıp, her otel için bu
ortak fonksiyon çağrılır:
`departman:'DEPO'`, `aciliyet`: o oteldeki en kritik ürünün durumuna göre
(`miktar<=0` veya `miktar<=min*0.5` varsa `'acil'`, yoksa `'normal'`),
`not_alani:'Otomatik stok kontrolü önerisi'`, `talep_eden:CU.ad`,
`otel_id`: ilgili otel. Kalemler: seçilen ürünlerin `urun_adi`, `urun_kodu`,
önerilen miktar, birim.

## Test/doğrulama planı

Statik: `stokMinimumKontrolEt()`'in eksik hesaplama mantığının
`stok-takip.html`'deki `getStokDurum()` ile tutarlı olduğunu, oluşan
talebin `ytKaydet()` ile aynı Supabase yazma şeklini kullandığını kod
okuyarak doğrulamak. Gerçek uçtan uca test (minimum altı ürün oluştur →
öneri listesini gör → talep oluştur → İç Talepler'de görün) kullanıcı
tarafından yapılacak.
