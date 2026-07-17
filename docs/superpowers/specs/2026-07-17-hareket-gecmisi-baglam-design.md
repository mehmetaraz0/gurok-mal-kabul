# Hareket Geçmişi Bağlam Kaybı — Tasarım

## Problem / Hedef

`stok-takip.html`'in "Hareketler" sekmesi (`renderHareketler()`, ~satır
1133), giriş/çıkış/transfer kayıtlarını listelerken ürün adı, giriş
kaynağı, çıkış nedeni ve transfer kaynak/hedef depo bilgisini göstermek
üzere yazılmış — ama bu bilgiler hiçbir zaman veritabanına kaydedilmiyor.
`giris()`/`cikis()`/`transfer()` fonksiyonlarının döndürdüğü nesne bu
alanları (`urunAd`, `kaynak`, `neden`, `kaynakDepoId`, `hedefDepoId`,
`kaynakDepoAd`, `hedefDepoAd`) taşıyor, ama `saveHareket()` sadece
`urun_kodu`, `depo_kodu`, `otel_id`, `tip`, `miktar`, `belge_no`,
`aciklama` alanlarını `stok_hareketleri` tablosuna yazıyor — geri kalanı
sessizce düşüyor. Sayfa yenilendiğinde (`loadDB()` tabloyu tekrar
okuduğunda) bu bağlam kalıcı olarak kaybolmuş oluyor; kullanıcı ekranda
"Giriş — —", "Çıkış — —" ve transferlerde nereden/nereye gittiği
gösterilemeyen kayıtlar görüyor.

Kanıt: `stok_hareketleri` tablosu doğrudan sorgulandığında (curl),
gerçek satırların `aciklama` alanı giriş/çıkış için `null`, tek bulunan
transfer örneğinde ise (`depo-siparis.html`'in "İç Talep" akışından)
`aciklama` zaten okunabilir bir metin taşıyor: *"İç Talep: 🏭 100 — Club
Isletme Depo → 🍳 CMM201 — Anamutfak — İç Talep #6"*.

## Kapsam

`stok-takip.html`'in giriş/çıkış/transfer hareket akışları — bundan
sonra oluşturulan kayıtlar için `aciklama` alanı, kod tabanında zaten var
olan desenle (mal-kabul-v2.html, depo-siparis.html) tutarlı, okunabilir
bir metinle doldurulacak. `renderHareketler()` bu metni öncelikli
gösterecek şekilde güncellenecek. Ürün adı, mevcut `db.urunler`
kataloğundan kod eşleştirilerek render sırasında çözülecek — ekstra
kayıt/kolon gerekmez.

## Kapsam dışı

- `stok_hareketleri` tablosuna yeni kolon eklenmesi (Approach B,
  reddedildi — mevcut kod tabanı zaten `aciklama` metin desenini
  kullanıyor, yapılandırılmış kolonlar aşırı mühendislik olur).
- `mal-kabul-v2.html`, `gunluk-tuketim.html`, `depo-siparis.html`'deki
  hareket kayıtları — bunlar zaten `aciklama`'ya anlamlı metin yazıyor,
  dokunulmuyor.
- Geçmiş (mevcut) hareket kayıtlarının geriye dönük doldurulması —
  onlarda `aciklama` zaten boş kalacak, backfill yapılmayacak.

## Mimari

Şema değişikliği yok. `giris()`/`cikis()`/`transfer()` fonksiyonları
(stok-takip.html, ~822-865), döndürdükleri hareket nesnesine zaten sahip
oldukları bilgilerden bir `aciklama` metni ekler:

- `giris(depoId,lnKod,urunAd,miktar,birim,kaynak,kaynakId)`:
  `aciklama: kaynak||''`
- `cikis(depoId,lnKod,urunAd,miktar,birim,neden,not)`:
  `aciklama: neden + (not?(' — '+not):'')`
- `transfer(kaynakDepoId,hedefDepoId,lnKod,urunAd,miktar,birim,not)`:
  `aciklama: kaynakDepoAd+' → '+hedefDepoAd + (not?(' — '+not):'')`
  (kaynakDepoAd/hedefDepoAd zaten fonksiyon içinde `depoAdi()` ile
  hesaplanıyor)

`saveHareket()` (~808) zaten `aciklama:h.aciklama||null` yazıyor —
değişiklik gerekmez; hareket nesnesi artık dolu geldiği için otomatik
kalıcı olur.

`renderHareketler()` (~1133) güncellenir:
- Ürün adı: `db.urunler`'den `kod→{ad,birim}` bir `Map` render başında
  bir kez kurulur (O(1) lookup), `h.urunAd || urunMap.get(h.lnKod)?.ad
  || h.lnKod` önceliğiyle gösterilir.
- Etiket: `h.aciklama` doluysa doğrudan gösterilir (DB'den gelen kalıcı
  veri); boşsa mevcut oturum-içi alanlara (`kaynakDepoAd` vb.) geriye
  dönük fallback yapılır (aynı oturumda henüz `saveHareket()` dönmemiş
  anlık gösterim için, mevcut davranışı bozmaz).

## Veri akışı

Kullanıcı işlemi → `giris()`/`cikis()`/`transfer()` dolu `aciklama` ile
hareket nesnesi üretir → `saveStok()` RPC ile stok deltasını kalıcı
kılar → `saveHareket()` hareket satırını (artık anlamlı `aciklama` ile)
kalıcı kılar → `loadDB()` satırları geri okurken `aciklama`'yı zaten
map'liyor (~706, değişmiyor) → `renderHareketler()` hem aynı oturumda
hem sayfa yenilendikten sonra aynı anlamlı metni gösterir.

## Hata yönetimi

Yeni bir hata yolu yok — bu, var olan yazma/okuma noktalarına saf veri
zenginleştirme. Mevcut hata gösterimi (`saveStok`/`saveHareket`
başarısızlık uyarıları) dokunulmadan kalır.

## Test / doğrulama planı

Statik: Her üç fonksiyonun (`giris`/`cikis`/`transfer`) döndürdüğü
nesnede `aciklama` alanının dolu olduğunu, `renderHareketler()`'in
artık `h.aciklama`'yı öncelikli kullandığını kod okuyarak doğrulamak.

Gerçek uçtan uca (kullanıcı tarafından tarayıcıda): yeni bir giriş, çıkış
ve transfer yapıp Hareketler sekmesinde ürün adı + anlamlı detay (kaynak/
neden/kaynak→hedef) göründüğünü doğrulamak; ardından **sayfayı
yenileyip** aynı detayın hâlâ göründüğünü doğrulamak — bu, bug'ın asıl
kanıtı olduğu için kalıcılık testi zorunlu.
