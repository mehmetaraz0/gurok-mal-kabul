# FEFO Koli Kontrolü — Tasarım

## Problem / Hedef

SKT (son kullanma tarihi) verisi mal kabulde parti (koli) bazında tutuluyor
(`koli_etiketleri.skt_tarihi`), ama stok çıkışı sırasında (manuel çıkış,
depo teslim) hangi kolinin önce çıkması gerektiği sistemce yönlendirilmiyor
— kullanıcı istediği koliyi okutabiliyor, en eski SKT'li koli depoda
unutulup süresi geçebiliyor. Bu, depo modülü kıyaslama raporunda
tespit edilen Kritik #3 eksiği.

## Kapsam

- Koli QR okutma noktalarının HER İKİSİNDE de (`stok-takip.html`'in
  manuel çıkışı, `depo-siparis.html`'in teslim akışı) — okutulan koliyle
  aynı üründen, aynı depoda, daha eski SKT tarihli başka bir koli
  (`durum='depoda'`) varsa uyarı gösterilir.
- Uyarı yumuşak bir kapı (`confirm()`) — sert engelleme değil, kullanıcı
  isterse yine de devam edebilir (eski koli fiziksel olarak
  bulunamıyor/hasarlı olabilir gibi meşru istisnalar için).

## Kapsam dışı

- Reçete bazlı tüketim (`gunluk-tuketim.html`) — bu akış koli okutmuyor,
  reçete satışında ürünü otomatik miktar olarak stoktan düşüyor. Hangi
  partiden otomatik düşüleceğini seçmek yapısal olarak farklı bir problem
  (koli seçimi kullanıcı etkileşimi olmadan otomatik yapılmalı), ayrı bir
  iş olarak bırakılıyor.
- SKT tarihi girilmemiş partiler/koliler — FEFO kontrolü SKT'siz kolilerde
  hiç çalıştırılmaz, sessizce atlanır.
- Yeni bir veri modeli/şema değişikliği — `koli_etiketleri` tablosu zaten
  her kolinin kendi `skt_tarihi`+`depo_kodu`+`durum`'unu tutuyor, hiçbir
  yeni kolon/tablo gerekmiyor.

## Mimari

Yeni bir `fefoKontrolEt(koli)` fonksiyonu — hem `stok-takip.html` hem
`depo-siparis.html`'e eklenir (bu kod tabanının mevcut deseniyle tutarlı:
küçük yardımcı fonksiyonlar paylaşılan bir modül yerine dosya başına
tekrarlanıyor, bkz. `giris`/`cikis`'in her iki dosyada da ayrı ayrı
tanımlı olması). Fonksiyon, okutulan koliyle aynı `urun_kodu`+`depo_kodu`
kombinasyonunda, hâlâ `durum='depoda'` olan ve okutulandan daha eski
`skt_tarihi`'ne sahip başka bir koli olup olmadığını **tek bir Supabase
sorgusuyla** (`skt_tarihi.asc` sıralı, `limit=1`) kontrol eder — bulunan
en eski kayıt döner, yoksa `null`.

## Akış

`qrOkundu()` (stok-takip.html) ve `depoQrOkundu()` (depo-siparis.html) —
koli bulunup geçerliliği (mevcut `durum` kontrolleri) doğrulandıktan hemen
sonra `fefoKontrolEt(koli)` çağrılır:

- Koli'nin `skt_tarihi` alanı boşsa fonksiyon hiç çalışmaz, akış değişmez.
- Daha eski SKT'li bir koli BULUNAMAZSA akış mevcut haliyle devam eder
  (görünür bir değişiklik yok).
- Daha eski SKT'li bir koli bulunursa: `confirm('⚠️ FEFO Uyarısı: Bu
  üründen daha eski SKT'li bir koli var (Koli No: <X>, SKT: <Y>). Önce o
  çıkarılmalı. Yine de bu koliyle devam etmek istiyor musunuz?')`.
  - Kullanıcı "Hayır" derse: koli okutma işlemi iptal edilir (form
    doldurulmaz / `_onayKolileri`'ye eklenmez), kullanıcı doğru koliyi
    arayıp okutabilir.
  - Kullanıcı "Evet" derse: mevcut akış (form doldurma / koli listeye
    ekleme) aynen devam eder — istisna bilinçli bir kullanıcı kararı
    olarak kabul edilir, ayrıca loglanmaz (bu görevin kapsamında audit
    log'a yazma yok, sadece anlık uyarı).

## Test/doğrulama planı

Statik: `fefoKontrolEt`'in sorgu filtrelerinin (`urun_kodu`, `depo_kodu`,
`durum=eq.depoda`, `skt_tarihi=not.is.null`, kendi id'sini hariç tutma)
doğru kurulduğunu, her iki dosyadaki çağrı noktasının koli doğrulandıktan
sonra ama form/liste güncellemesinden ÖNCE tetiklendiğini kod okuyarak
doğrulamak. Gerçek uçtan uca test (iki farklı SKT tarihli koli oluştur,
yeni tarihli olanı okut, uyarı çıktığını gör) kullanıcı tarafından
yapılacak.
