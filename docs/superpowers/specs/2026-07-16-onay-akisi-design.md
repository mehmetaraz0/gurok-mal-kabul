# Satın Alma Talepleri — Çok Aşamalı Onay Akışı — Tasarım

## Problem / Hedef

`satin-alma.html`'deki "Bekleyen Talepler" onayı tek aşamalı ve tek tıkla biter
(`talepOnayla`/`talepReddet`, satır ~1043-1056): canlı durum kontrolü yok,
onaylayan adı/tarihi hiçbir zaman Supabase'e yazılmıyor, red nedeni hiç
saklanmıyor. Gerçek iş süreci ise çok aşamalı: talep önce Depo'dan, sonra Cost
Control'den geçiyor, ardından tutarına göre doğru yetki katmanına
yönlendiriliyor. Bu tasarım, gerçek süreci modelleyen ve mevcut kayıt
eksikliklerini gideren bir onay motoru kurar.

## Kapsam

- Sadece `satin-alma.html` → Bekleyen Talepler (`satin_alma_talepleri`).
- Aşama sırası: **Depo → Cost Control → (tutara göre) Satınalma Müdürü /
  Grup Satınalma Direktörü / GM / Grup Direktörü**. Depo ve Cost limitsiz —
  ürün kontrolü + bütçe kontrolü yaparlar, onay yetkisi değil "geçiş" yetkisi.
- Tutara göre yönlendirme **tek katmana düşer**, sıralı çoklu imza değildir:

  | Katman | Rol kodu | Üst limit |
  |---|---|---|
  | Satınalma Müdürü | `satinalma_mdr` | 200.000 ₺ |
  | Grup Satınalma Direktörü | `grup_satinalma` | 500.000 ₺ |
  | GM | `gm` | 750.000 ₺ |
  | Grup Direktörü | `grup_direktor` | limitsiz |

  Örn. 300.000 ₺'lik talep `satinalma_mdr` kuyruğuna hiç düşmez, doğrudan
  `grup_satinalma`'ya gider.
- Tutar, talep oluşturulduğunda bilinmiyor (kalemlerde fiyat alanı yok) —
  **Cost Control aşamasında girilir**, yönlendirme kararı bu noktada verilir.
- Her aşama geçişi denetim izine (`talep_onay_gecmisi`) yazılır: kim, hangi
  aşamada, ne karar verdi, ne zaman, hangi not ile.
- Red, herhangi bir aşamada mümkün — süreç orada biter (`durum='reddedildi'`).

## Kapsam dışı

- RLS / sunucu taraflı yetkilendirme — ayrı bir hatta yürüyor.
- Diğer modüllere (İç Talepler, Mal Kabul) yayılım.
- Yapılandırılabilir onay kuralları tablosu/arayüzü — limitler v1'de
  `onay-motoru.js` içinde sabit kod (`ONAY_KATMANLARI`); ileride bir tabloya
  taşınabilir şekilde yazılır ama editör arayüzü bu iterasyonda yok.
- Vekalet/eskalasyon/zaman aşımı bildirimleri.
- Bütçe modülüyle (`muhasebe-butce.html`) otomatik entegrasyon — Cost, tutarı
  manuel girer.
- Kalem bazlı fiyat girişi — Cost aşamasında tek bir toplam tutar alanı
  yeterli, satır satır fiyatlandırma kapsam dışı.

## Mimari

**Yeni kolonlar — `satin_alma_talepleri`:**
`asama` (`depo`|`cost`|`mdr`|`direktor`|`gm`|`ust_yonetim`, DEFAULT `'depo'`),
`tutar` (numeric, null'lanabilir — Cost aşamasında dolar),
`onaylayan_ad` (text), `onay_tarihi` (timestamptz) — sonuncu ikisi mevcut bug'ı
da düzeltir, şu an bu tabloda hiç yazılmıyor.

**Yeni tablo `talep_onay_gecmisi`:** her aşama geçişinin tam denetim izi —
`id, talep_id (FK), asama, rol_kodu, kullanici_ad, karar ('onay'|'red'), not,
created_at`.

**Yeni paylaşılan dosya `onay-motoru.js`** (repo kökü, `auth-guard.js` gibi
`<head>`'den senkron yüklenir — projede onay/kaydet mantığı hiç paylaşılmıyor,
her modül `auditLogYaz`'ı bile kendi kopyalıyor; bu, çok katmanlı yönlendirme
mantığının ilk paylaşılan iş-mantığı dosyası olacak):

- `ONAY_KATMANLARI` — sıralı aşama tanımları: `{asama, roller:[...], tip:
  'kontrol'|'tutar_gir'|'onay', limit}`.
- `sonrakiAsamaBelirle(mevcutAsama, tutar)` — saf fonksiyon: `depo`→`cost`;
  `cost`→tutara göre `mdr`/`direktor`/`gm`/`ust_yonetim`; katmanlardan biri
  onaylarsa → `null` (süreç biter, `durum='onaylandi'`).
- `talepAsamaIlerlet(talepId, kullanici, karar, {tutar, not})` —
  `stok-takip.html`'deki `sayimOnayla` ile aynı güvenlik deseni: işlemden
  hemen önce talebin güncel `asama`/`durum`'unu canlı GET ile tazeler
  (stale-state guard — "başka biri az önce bu aşamayı zaten ilerletti"),
  kullanıcının rolünün o anki asamaya yetkili olup olmadığını kontrol eder,
  `talep_onay_gecmisi`'ne satır yazar, `sonrakiAsamaBelirle` ile bir sonraki
  durumu hesaplayıp `satin_alma_talepleri`'ni PATCH'ler. Son katman
  onaylarsa `durum:'onaylandi', onaylayan_ad, onay_tarihi` de yazılır. Red
  kararında `durum:'reddedildi'` yazılır, `asama` olduğu yerde kalır (tarihsel
  kayıt için).

**`satin-alma.html` değişiklikleri:**
- `<head>`'e `<script src="onay-motoru.js"></script>`.
- `talepOnayla`/`talepReddet` kaldırılır, yerine `talepAsamaIlerlet` çağıran
  tek akış.
- "Bekleyen Talepler" listesi kullanıcının rolüne uyan `asama`'daki talepleri
  filtreler — yönlendirme zaten doğru katmana düşürdüğü için ekstra tutar
  filtresine gerek yok.
- Cost aşamasında onaylarken tutar girişi modalı açılır.
- Talep detay modalına aşama geçmişi (`talep_onay_gecmisi`) zaman çizelgesi
  eklenir.

## Akış

1. Talep oluşturulur → `asama='depo'`, `durum='bekleyen'` (mevcut
   `talepKaydet` değişmez, sadece `asama` alanı DB'nin DEFAULT'undan gelir).
2. `depo` rolü talebi görür, ürün kontrolü yapar, onaylar veya reddeder.
   Onaylarsa → `talepAsamaIlerlet(..., karar:'onay')` → `asama='cost'`.
3. `cost_control` rolü talebi görür, bütçe kontrolü yapar, **tutarı girer**,
   onaylar veya reddeder. Onaylarsa → `sonrakiAsamaBelirle('cost', tutar)`
   tutara göre `mdr`/`direktor`/`gm`/`ust_yonetim`'den birini döner, `tutar`
   kalıcı olarak yazılır.
4. İlgili katman (yalnızca o katmanın rolü) talebi görür, onaylar veya
   reddeder. Onaylarsa süreç biter: `durum='onaylandi'`, `onaylayan_ad`,
   `onay_tarihi` yazılır. Reddederse `durum='reddedildi'`.
5. Her adımda `talep_onay_gecmisi`'ne bir satır eklenir — talep detayında tam
   zaman çizelgesi görüntülenebilir.

## Doğrulama / Bayat Veri

`sayimOnayla`/`sayimReddet`'teki desen birebir taşınır: `talepAsamaIlerlet`,
PATCH'ten hemen önce talebin `asama`/`durum` alanlarını canlı GET ile tazeler;
beklenenden farklıysa işlemi durdurur ve kullanıcıyı bilgilendirir — iki
kişinin aynı talebi aynı anda farklı kararlarla ilerletmesi engellenir. Çift
gönderim guard'ı (`_talepAsamaIsleniyor` modül değişkeni) eklenir.

## Test/doğrulama planı

Statik: `sonrakiAsamaBelirle`'nin her tutar aralığı için doğru katmanı
döndüğünü (200k/500k/750k sınır değerleri dahil), rol kontrolünün her
aşamada doğru role kilitlendiğini, stale-state guard'ın PATCH'ten önce
gerçekten canlı GET yaptığını kod okuyarak doğrulamak. Gerçek akışın uçtan
uca testi (depo→cost→katman→onay, red senaryosu, iki sekme çakışması)
kullanıcı tarafından tarayıcıda yapılacak.
