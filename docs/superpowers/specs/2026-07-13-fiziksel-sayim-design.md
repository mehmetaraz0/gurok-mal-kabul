# Fiziksel Sayım (Cycle Count) — Tasarım

## Problem / Hedef

Depo modülünde sistematik bir fiziksel sayım (cycle count) mekanizması yok
— sistemdeki stok miktarı ile depodaki gerçek miktar zamanla sapıyor ve
düzeltmek için hiçbir sistematik akış bulunmuyor. Bu, önceki depo modülü
kıyaslama analizinde (`depo-modul-kiyaslama-raporu.html`) tespit edilen en
kritik eksik olarak işaretlendi.

## Kapsam

- `stok-takip.html`'e yeni bir **"📊 Sayım"** sekmesi eklenir (ayrı dosya
  değil — depo/ürün verisi ve mevcut filtreler zaten bu dosyada yüklü).
- Kısmi (kategori/arama filtreli) ve tam depo sayımı — aynı mekanizma,
  ikisi de mevcut filtre UI'ı üzerinden.
- İki aşamalı akış: sayım oluşturma → onay (stok değişikliği sadece onay
  sonrası uygulanır).
- Fark eşiği: mutlak %10 üstü sapmalarda açıklama zorunlu.
- Rol ayrımı: sayım oluşturma (`yonetici`,`depo`,`cost_control`) ile
  onaylama (**sadece `cost_control`**) ayrı yetkiler — `yonetici` dahi
  onaylayamaz, kasıtlı bir ayrım gücü (segregation of duties) kontrolü.

## Kapsam dışı

- Ürün/raf bazlı barkod ile sayım hızlandırma — mevcut sistemde sadece
  koli bazlı QR var, ürün bazlı barkod ayrı bir roadmap maddesi.
- Otomatik/periyodik sayım hatırlatması (örn. "her hafta X kategorisi
  sayılsın") — bu iterasyonda manuel başlatma yeterli.
- Raf/lokasyon (bin) seviyesinde sayım — depo bazlı sayımla sınırlı,
  mevcut stok veri modeli zaten raf seviyesini tutmuyor.

## Mimari

Mevcut `giris()`/`cikis()` fonksiyonları (`stok-takip.html`) zaten bir
`neden` parametresi alıyor (mal kabul, transfer gibi kaynaklar için) —
sayım düzeltmesi de aynı desenle, `neden='sayim'` olarak bu fonksiyonlar
üzerinden uygulanır; yeni bir stok-güncelleme yolu icat edilmez.

İki yeni Supabase tablosu:

**`sayim_oturumlari`** — bir sayım işleminin başlığı:
`id, depo_kodu, otel_id, olusturma_tarihi, olusturan_ad, durum
('onay_bekliyor'/'onaylandi'/'reddedildi'), onaylayan_ad, onay_tarihi,
toplam_urun_sayisi, farkli_urun_sayisi, genel_not, red_nedeni`

**`sayim_detaylari`** — oturuma bağlı satır bazlı kayıtlar:
`id, oturum_id (FK), urun_kodu, urun_adi, birim, sistem_miktar,
sayilan_miktar, fark, fark_yuzde, aciklama`

## Akış

1. Kullanıcı depo seçer, isteğe bağlı olarak mevcut arama/kategori/durum
   filtreleriyle daraltır (`renderStok()`'taki filtreleme mantığıyla
   birebir aynı — `stokExcelAktar()`'ın zaten kullandığı desen).
2. Filtrelenmiş her ürün satırında "Sayılan Miktar" giriş kutusu
   gösterilir (boş = sayıma dahil değil, kısmi doldurma serbest). Girilen
   her değer için sistem miktarıyla fark canlı hesaplanır (+/- birim, %).
3. Mutlak fark yüzdesi **>%10** olan satırlarda kırmızı uyarı + zorunlu
   açıklama kutusu belirir; altındaki farklarda açıklama isteğe bağlı.
4. "Sayımı Tamamla" → özet (N ürün sayıldı, M üründe fark, toplam +X/-Y
   birim) → büyük farkı olan ama açıklaması boş satır varsa gönderim
   engellenir; hangi ürün(ler)de açıklama eksik olduğu `alert()` ile
   listelenir (mevcut `yevmiyeDogrula`/`stokExcelAktar` hata gösterim
   deseniyle tutarlı). Sorun yoksa `sayim_oturumlari`
   (`durum='onay_bekliyor'`) ve `sayim_detaylari` satırları Supabase'e
   yazılır — **stok miktarı bu aşamada değişmez**.
5. Yeni "Onay Bekleyen Sayımlar" listesi — sadece `cost_control` rolüne
   görünür (buton/sekme diğer rollerde hiç render edilmez). Onaylayınca:
   farkı olan (`fark≠0`) her `sayim_detaylari` satırı için `giris()` (fark
   pozitifse) veya `cikis()` (fark negatifse) çağrılır — `neden='sayim'`,
   `not=aciklama||'Fiziksel sayım düzeltmesi'` — ardından `saveStok()` +
   `saveHareket()` ile kalıcılaştırılır, oturum `durum='onaylandi'` olur.
   Reddedilirse `cost_control` kullanıcısından kısa bir red nedeni istenir
   (`red_nedeni`), `durum='reddedildi'` yazılır, stok hiç değişmez.

## Doğrulama / Bayat Veri

Onay anında, oturumun oluşturulduğu zamandan bu yana sistemdeki stok
miktarı değişmiş olabilir (başka bir hareket/mal kabul araya girmiş
olabilir) — bu oturumda daha önce kurulan "bayat veri" canlı kontrol
deseniyle tutarlı olarak, onay anında her ürünün GÜNCEL sistem miktarı
yeniden okunur ve fark buna göre yeniden hesaplanır (oturum oluşturma
anındaki donmuş `sistem_miktar` değeri değil). Yeniden hesaplanan fark
sıfırsa o satır için hiçbir hareket oluşturulmaz.

## Test/doğrulama planı

Statik: sayım ekranının filtreleme mantığının `renderStok()`/
`stokExcelAktar()` ile birebir aynı olduğunu, fark yüzdesi hesaplamasının
ve %10 eşiğinin doğru uygulandığını, onay akışının `giris()`/`cikis()`'i
doğru yönde çağırdığını kod okuyarak doğrulamak. Rol kısıtının
(`cost_control` dışındaki hiçbir rolün onay butonunu görmediği/işlem
yapamadığı) doğru uygulandığını kontrol etmek. Gerçek sayım/onay
akışının uçtan uca testi kullanıcı tarafından yapılacak.
