# Supabase Auth Köprüsü — Faz A2 (Token'ı Gerçek İsteklerde Kullanma) — Tasarım

## Problem / Hedef

Faz A (2026-07-17, commit `5534863`) PIN girişi sırasında arka planda bir
Supabase Auth `access_token` alıyor ama hiçbir gerçek veri isteğinde
kullanmıyor — tüm `fetch()` çağrıları hâlâ sabit anon key (`SB_KEY`) ile
çalışıyor. Bu yüzden Postgres RLS politikalarında `auth.uid()` hiçbir zaman
dolu gelmiyor; gerçek role/otel bazlı erişim kısıtlaması (Faz B) için bu
gerekli ön koşul eksik.

Bu tasarım, alınan `access_token`'ı gerçek isteklerde kullanmaya başlıyor —
ama RLS politikaları hâlâ herkese açık (`using(true)`, hem `anon` hem
`authenticated` rolüne) olduğu için, bu fazın kendisi HİÇBİR erişim
davranışını değiştirmiyor. Sadece Faz B'nin üzerine inşa edileceği zemini
hazırlıyor.

## Önemli bulgu (investigation sırasında tespit edildi)

`auth-guard.js` ve `supabase-config.js`'i yükleyen **28 dosyanın hepsi**
doğru sırada yüklüyor (`auth-guard.js` önce, `supabase-config.js` sonra —
`supabase-config.js`'nin kendi yorum satırı bunu zaten belirtiyor). Bu,
`SB_HEADERS`'ı tek bir merkezi dosyada (supabase-config.js) dinamik hale
getirerek, 28 sayfanın hiçbirine tek tek dokunmadan hepsini kapsayabileceğim
anlamına geliyor. Sadece `gurok_mal_kabul.html` (zaten devre dışı, eski
sayfa) bu düzenin dışında.

curl ile doğrudan doğrulandı: `authenticated` rolündeki bir JWT ile hem
RLS'siz bir tabloda (`stok`, SELECT → 200) hem RLS'li bir tabloda
(`cariler`, SELECT → 200) hem de bir INSERT'te (`stok_hareketleri` → 201)
anon key ile birebir aynı sonuç alınıyor — beklenmedik bir izin farkı yok.

## Kapsam

1. **`auth-guard.js`:** `oturumGetir()`'in yanına, aynı deseni kullanan
   yeni bir `oturumAccessTokenGetir()` fonksiyonu eklenir — oturumdaki
   `accessToken`'ı (varsa ve oturum süresi geçmemişse) döner, yoksa `null`.
2. **`supabase-config.js`:** `SB_HEADERS`, artık sabit bir nesne değil,
   sayfa yüklenirken hesaplanan bir değer olur — `oturumAccessTokenGetir()`
   geçerli bir token dönerse `Authorization: Bearer <token>`, dönmezse
   (token yok / Auth Faz A'da başarısız olmuş / oturum süresi geçmiş)
   eskisi gibi `Authorization: Bearer <SB_KEY>`. `apikey` header'ı her
   durumda `SB_KEY` olarak kalır.

## Kapsam dışı

- RLS politikalarının gerçekten kısıtlanması (Faz B, ayrı ve çok daha
  büyük bir proje — bu fazın TEK hedefi zemin hazırlamak, erişim
  değiştirmek değil).
- Token yenileme (refresh) mekanizması — gerekmiyor: Supabase access_token
  1 saat yaşıyor, mevcut PIN oturumu (`SESSION_SURESI_MS`) 30 dakikada
  zaten sona erip yeniden girişe zorluyor, yani token oturumdan önce hiç
  süresi dolmadan doğal olarak yenileniyor (yeni giriş = yeni token). Her
  sayfa yüklemesi zaten taze bir `SB_HEADERS` hesaplıyor.
- `gurok_mal_kabul.html` — zaten devre dışı, kendi lokal `SB_URL`/`SB_KEY`
  sabitleri var, bu dosyaları yüklemiyor.
- 28 sayfanın herhangi birinin kendi kodunun değiştirilmesi — hepsi
  merkezi `SB_HEADERS`'ı olduğu gibi kullanmaya devam ediyor.

## Mimari

`auth-guard.js`'e eklenen yeni fonksiyon, `oturumGetir()`'in aynı hata
toleransı deseniyle:

```js
function oturumAccessTokenGetir() {
  try {
    const s = sessionStorage.getItem(SESSION_KEY);
    if (!s) return null;
    const { accessToken, expiry } = JSON.parse(s);
    if (!accessToken || Date.now() >= expiry) return null;
    return accessToken;
  } catch (e) { return null; }
}
```

`supabase-config.js`'deki `SB_HEADERS` tanımı:

```js
const SB_URL='https://xwytofysmgqtqjzkplfi.supabase.co';
const SB_KEY='...';
const SB_HEADERS = (function(){
  const token = (typeof oturumAccessTokenGetir === 'function') ? oturumAccessTokenGetir() : null;
  return {'apikey':SB_KEY,'Authorization':'Bearer '+(token||SB_KEY),'Content-Type':'application/json'};
})();
```

`typeof oturumAccessTokenGetir === 'function'` kontrolü bilinçli bir
savunma katmanı — eğer bir sayfa (yanlışlıkla veya ileride) `auth-guard.js`
olmadan `supabase-config.js`'i yüklerse, `ReferenceError` fırlatıp tüm
sayfayı kilitlemek yerine sessizce anon key'e düşer.

## Veri akışı

Sayfa yüklenir → `auth-guard.js` çalışır (fonksiyonları tanımlar) →
`supabase-config.js` çalışır → `oturumAccessTokenGetir()` çağrılır →
mevcut oturumda geçerli bir token varsa `SB_HEADERS.Authorization` o
token'ı taşır, yoksa anon key'i taşır → sayfanın geri kalanındaki TÜM
`fetch()` çağrıları bu tek `SB_HEADERS` nesnesini kullanır (kod tabanının
zaten mevcut deseni — değişmiyor).

## Hata yönetimi

`oturumAccessTokenGetir()` her hata durumunda (`sessionStorage` erişim
hatası, bozuk JSON, eksik alan, süresi geçmiş oturum) `null` döner —
hiçbir zaman exception fırlatmaz. `SB_HEADERS`'ın kendisi de `token||SB_KEY`
ile HER ZAMAN geçerli bir Authorization değeri üretir; asla `undefined`
veya boş bir header üretemez. Bu, "token eksik olan kullanıcı tüm
uygulamadan kilitlenir" riskini yapısal olarak imkânsız kılıyor.

## Test / doğrulama planı

Statik: `oturumAccessTokenGetir`'in `oturumGetir` ile aynı hata-toleranslı
deseni kullandığını, `SB_HEADERS`'ın her koşulda (token var/yok/süresi
geçmiş) geçerli bir `Authorization` değeri ürettiğini kod okuyarak
doğrulamak.

Gerçek (controller tarafından curl ile, kodu deploy etmeden önce):
`authenticated` rollü gerçek bir token ile RLS'li/RLS'siz tablolarda
anon key ile birebir aynı sonucun alındığını doğrulamak — BU FAZLA
İLGİLİ DEĞİL, tasarım aşamasında zaten yapıldı, sonuç yukarıda.

Gerçek uçtan uca (kullanıcı tarafından tarayıcıda): PIN ile giriş yapıp
birkaç farklı sayfada (stok-takip, muhasebe, satın-alma) normal işlem
yapmak — hiçbir davranış farkı hissedilmemeli. Tarayıcı DevTools → Network
sekmesinden bir Supabase isteğinin `Authorization` header'ının artık sabit
anon key değil, kullanıcının kendi token'ı olduğunu görsel olarak
doğrulamak (opsiyonel ama önerilir — Faz A2'nin gerçekten devrede
olduğunun kanıtı).
