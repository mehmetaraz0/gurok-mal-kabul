# Merkezi Giriş (Centralized Login) — Tasarım

## Problem

Uygulamadaki her modül sayfası (`index.html`, `stok-takip.html`, `depo-siparis.html`,
`satin-alma.html`, `gunluk-tuketim.html`, `mal-kabul-v2.html`) kendi PIN ekranını,
kendi `checkPin()`/`pinInput()` mantığını ve kendi `DEFAULT_USERS`/`TUSERS` yedek
listesini taşıyor. `muhasebe-*.html`, `kullanici-yonetimi.html`, `yetki-yonetimi.html`
ise farklı bir modelde: kendi PIN ekranları yok, altı farklı `sessionStorage`
anahtarından (`gurok_portal_session`, `gurok_session`, `gurok_stok_session`,
`gurok_siparis_session`, `gurok_satinalma_session`, `gurok_tuketim_session`) herhangi
birini geçerli sayıyorlar.

Bu ikili model bugünkü denetimde iki kez gerçek hataya yol açtı: (1) muhasebe
sayfalarının hiçbirinde başlangıçta hiçbir oturum kontrolü yoktu, (2) PIN deneme
sınırlamasını eklemek için aynı kodu 5 ayrı dosyaya elle kopyalamak gerekti. Kod
tekrarı arttıkça "bu dosyaya kontrolü eklemeyi unuttum" tarzı hatalar da artıyor.

## Hedef

- Tek giriş noktası: PIN ekranı sadece `index.html`'de olsun.
- Diğer tüm modül sayfaları kendi PIN ekranını kaldırıp, sayfa açılışında oturum
  kontrolü yapsın; oturum yoksa/süresi dolmuşsa `index.html`'e, oradan da (giriş
  başarılıysa) orijinal olarak açılmak istenen sayfaya geri dönsün.
- Oturum kontrolü, PIN deneme sınırlaması ve rol kontrolü mantığı **tek bir paylaşılan
  dosyada** (`auth-guard.js`) yaşasın — her modül sadece o dosyayı yükleyip kendi
  izinli rol listesiyle çağırsın.
- Rol bazlı modül erişimi bugünküyle birebir aynı kalsın (aşağıdaki tablo).

## Kapsam dışı

- Sunucu taraflı (Supabase RLS) erişim kontrolü — bu ayrı bir konu, bu tasarım sadece
  istemci tarafı yönlendirme/oturum davranışını değiştiriyor.
- PIN'in kendisinin değiştirilmesi (uzunluk, format) — kapsam dışı.
- `bar.html` (henüz yapılmamış modül) — kapsam dışı.
- `migrate-to-supabase.html`, `gurok_mal_kabul.html` (retired) — bu ikisi zaten kendi
  özel erişim modeline sahip, bu tasarımın kapsamı dışında bırakılıyor.

## Mimari

### `auth-guard.js` (yeni, paylaşılan dosya)

Repo köküne eklenir, her modül sayfası `<head>` içinde en üste
`<script src="auth-guard.js"></script>` ile yükler. İçeriği:

- `SESSION_KEY = 'gurok_portal_session'` — tek oturum anahtarı.
- `SESSION_SURESI_MS = 30*60*1000` — 30 dakika, tüm modüllerde aynı.
- `oturumGetir()` — `sessionStorage`'dan `SESSION_KEY`'i okur, süresi dolmuşsa
  `null` döner, geçerliyse `{user, expiry}` döner.
- `requireLogin()` — `index.html` DIŞINDAKİ her modülün `<head>`'inde, sayfa
  parse edilirken senkron çağrılır:
  - Oturum yoksa/süresi dolmuşsa: `location.replace('index.html?returnTo=' +
    encodeURIComponent(location.pathname + location.search + location.hash))`
    ile yönlendirir ve `null` döner (çağıran kod devam etmemeli — bkz. "Sayfa
    içi kullanım" altında).
  - Oturum geçerliyse `user` nesnesini döner.
- `requireRole(user, izinliRoller)` — `user.rol` `izinliRoller` içinde değilse,
  sayfanın `<body>` içeriğini "Bu modül senin rolüne kapalı" mesajıyla değiştirir
  ve `false` döner (yönlendirme YAPMAZ — kullanıcı zaten giriş yapmış, sonsuz
  döngüye sokmamak için sadece erişimi reddeder).
- PIN deneme sınırlaması fonksiyonları (`pinKilitliMi`, `pinBasarisizKaydet`,
  `pinBasariliTemizle`) — bugün 5 dosyaya kopyalanan mantığın tek kopyası,
  `index.html`'in PIN ekranı tarafından kullanılır.

### `index.html` değişiklikleri

- Mevcut PIN ekranı ve `checkPin()` kalır (tek giriş noktası burası).
- `checkPin()` başarılı girişte: URL'de `?returnTo=` parametresi varsa VE bu
  parametre `/^[a-z0-9_-]+\.html(\?.*)?(#.*)?$/i` gibi bir kalıba uyan,
  aynı-origin, göreli bir dosya adıysa (açık yönlendirme/open-redirect'i önlemek
  için beyaz liste mantığı — sadece bilinen `.html` dosyalarına izin ver, tam bir
  URL veya `//` ile başlayan bir değer asla kabul edilmez) oraya
  `location.replace(returnTo)` ile yönlendirir; yoksa bugünkü gibi portal
  ızgarasını gösterir.
- `auth-guard.js`'deki PIN kilitleme fonksiyonlarını kullanacak şekilde
  güncellenir (kendi kopyası silinir).

### Diğer modül sayfaları (`stok-takip.html`, `depo-siparis.html`,
`satin-alma.html`, `gunluk-tuketim.html`, `mal-kabul-v2.html`)

- Kendi PIN ekranı HTML/CSS'i, `checkPin()`/`pinInput()`/`pinBasarisizKaydet()`
  vb. fonksiyonları, `DEFAULT_USERS`/`TUSERS` yedek listesi tamamen silinir.
- `<head>` içine `auth-guard.js` eklenir; sayfa init akışının en başında:
  ```js
  const CU = requireLogin(); if(!CU) { /* yönlendirme zaten oldu, dur */ }
  else if(!requireRole(CU, ['yonetici','depo'])) { /* erişim reddedildi mesajı zaten gösterildi, dur */ }
  else { /* mevcut init() çağrısı */ }
  ```
- Zaten aynı desende olan `muhasebe-*.html`, `kullanici-yonetimi.html`,
  `yetki-yonetimi.html` de bugünkü kendi-içine-gömülü gate kodunu bırakıp
  `auth-guard.js`'e geçer (davranış aynı kalır, sadece tek kopyaya iner).

### Rol tablosu (mevcut `index.html` MODULLER dizisinden birebir alınıyor)

| Dosya | İzinli roller |
|---|---|
| `stok-takip.html` | yonetici, depo |
| `depo-siparis.html` | yonetici, depo, mutfak, bar |
| `satin-alma.html` | yonetici, satinalma, depo |
| `gunluk-tuketim.html` | mutfak, bar, yonetici |
| `mal-kabul-v2.html` | yonetici, depo, satinalma, kalite *(malkabul ve raporlar modüllerinin rol birleşimi — aynı dosya iki farklı kart üzerinden açılıyor)* |
| `kullanici-yonetimi.html`, `yetki-yonetimi.html` | yonetici |
| `muhasebe-*.html` (14 dosya) | yonetici, satinalma |

## Hata durumları

- **Oturum süresi modül kullanılırken dolarsa**: mevcut davranışla aynı — bir
  sonraki yazma isteği 401/403 alır ya da kullanıcı fark etmeden bayat veriyle
  çalışmaya devam edebilir. Bu tasarımın kapsamı dışında (bugünküyle aynı risk,
  kötüleştirmiyoruz).
- **`returnTo` geçersiz/kötü niyetli bir değerse**: beyaz liste eşleşmezse
  yok sayılır, normal portal gösterilir.
- **Doğru PIN ama yanlış rol**: yönlendirme döngüsüne girmeden "Bu modül sana
  kapalı" mesajı + `index.html`'e dönüş linki.

## Test/doğrulama planı

Bu ortamda gerçek tarayıcıda tıklayarak test edilemiyor (önceki oturumlarda
belirtildiği gibi). Doğrulama, her migrate edilen dosya için:
1. `auth-guard.js`'in doğru yüklendiğini ve eski PIN kodunun tamamen kaldırıldığını
   statik olarak doğrulamak (grep ile eski fonksiyon adlarının kalmadığını kontrol).
2. Rol tablosundaki her satırın `requireRole()` çağrısında birebir yansıdığını
   kontrol etmek.
3. `returnTo` beyaz liste regex'ini birkaç örnek girdiyle (geçerli dosya adı,
   tam URL, `//evil.com`, script içeren değer) elle iz sürerek doğrulamak.
