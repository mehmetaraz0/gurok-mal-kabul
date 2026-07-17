# Supabase Auth Köprüsü — Faz A (Altyapı) — Tasarım

## Problem / Hedef

Güvenlik denetim raporunun asıl P0 endişesi ("gerçek yetkilendirme yok")
tam çözülmedi — RLS Faz 1 sadece DELETE'i engelledi, SELECT/UPDATE/INSERT
hâlâ herkese açık (`using(true)`). Bunu gerçek anlamda çözmek (role/otel
bazlı erişim kısıtlaması) Postgres RLS politikalarının `auth.uid()`'ye
erişebilmesini gerektirir — bu da PostgREST'e giden her isteğin gerçek
bir Supabase Auth JWT'siyle imzalanmasını şart koşar. Şu an sistem tek
bir sabit anon key kullanıyor, hiçbir isteğin "kim" gönderdiği DB
seviyesinde bilinmiyor.

Kullanıcı, 2026-07-15'te ("Hibrit Giriş Mimarisi Faz 1") PIN'in saha
personeli için **kalıcı olarak kalacağına** karar vermişti (ileride
ofis/yönetim rolleri için Microsoft SSO eklenecek). Bu tasarım o kararı
korur: PIN ekranı ve akışı hiç değişmiyor, arkada görünmez bir Supabase
Auth hesabı bağlanıyor.

Bu, büyük migrasyonun sadece **ilk, en düşük riskli parçası** (Faz A) —
gerçek erişim kısıtlaması (Faz B) ayrı, sonraki bir proje.

## Önemli bulgu (investigation sırasında tespit edildi)

`kullanicilar` tablosunda zaten `auth_user_id` ve `pin_hash` kolonları
var — paralel oturum tarafından eklenmiş, hiçbir kodda kullanılmıyor,
tüm satırlarda boş (curl ile doğrulandı). Kullanıcı onayıyla:
`auth_user_id` bu tasarımda kullanılıyor (amaçlanan kullanımıyla
birebir örtüşüyor); `pin_hash` bu fazın kapsamı dışında bırakıldı.

## Kapsam

1. **Supabase Dashboard ayarı** (kullanıcı tarafından zaten yapıldı):
   Authentication → Sign In/Providers → "Confirm email" kapatıldı, Email
   sağlayıcısı aktif — sahte `@gurok.internal` e-postalarının anında
   (doğrulama beklemeden) aktif hesap açabilmesi için gerekli.
2. **`index.html` — `checkPin()` fonksiyonu:** PIN doğrulandıktan hemen
   sonra, kullanıcının `auth_user_id`'sine göre iki yoldan biri izlenir:
   - `auth_user_id` boşsa: `POST /auth/v1/signup` ile yeni bir Supabase
     Auth hesabı açılır (e-posta: `{kullanici.id}@gurok.internal`,
     şifre: kullanıcının PIN'i), dönen Auth kullanıcı ID'si
     `kullanicilar.auth_user_id`'ye `PATCH` ile yazılır.
   - `auth_user_id` doluysa: `POST /auth/v1/token?grant_type=password`
     ile doğrudan giriş yapılır.
   - Her iki yoldan da dönen `access_token`, mevcut oturum nesnesine
     eklenir.
3. **`auth-guard.js` — oturum nesnesi:** `oturumKaydet(user)` artık
   ikinci bir parametre (`accessToken`) alır, session nesnesine
   `accessToken` alanı olarak ekler. `oturumGetir()` bunu aynen geri
   döndürür (kullanılmasa bile mevcut olması, Faz A2'nin ön koşulu).

## Kapsam dışı

- `pin_hash` kolonunun kullanılması / PIN'in hash'lenerek saklanması —
  ayrı, bu tasarımın konusu değil.
- `access_token`'ın herhangi bir gerçek veri isteğinde (`fetch`)
  kullanılması — tüm dosyalar hâlâ sabit `SB_KEY` (anon key) ile
  çalışmaya devam ediyor. Bu, Faz A2 (ayrı, sonraki bir proje).
- RLS politikalarının `auth.uid()` bazlı kısıtlanması — Faz B, ayrı ve
  çok daha büyük bir proje.
- Microsoft SSO'nun aktifleştirilmesi (buton zaten placeholder olarak
  duruyor, dokunulmuyor).
- `mal-kabul-v2.html`, `depo-siparis.html`, `gunluk-tuketim.html` ve
  diğer tüm modül dosyaları — hiçbiri bu fazda değişmiyor (kendi login
  ekranları yok, `requireLogin()` üzerinden `index.html`'in oturumunu
  okuyorlar, o oturum nesnesinin şekli aynı kalıyor, sadece içine bir
  alan daha ekleniyor).

## Mimari

`index.html`'in `checkPin()`'i şu anki haliyle PIN'i `kullanicilar.pin`
ile karşılaştırıp eşleşen kullanıcıyı buluyor. Eşleşme başarılı olduğunda,
yeni bir yardımcı fonksiyon çağrılır:

```js
async function supabaseAuthKoprusu(user) {
  const email = user.id + '@gurok.internal';
  const password = user.pin;
  try {
    if (!user.auth_user_id) {
      const r = await fetch(SB_URL + '/auth/v1/signup', {
        method: 'POST', headers: { apikey: SB_KEY, 'Content-Type': 'application/json' },
        body: JSON.stringify({ email, password })
      });
      if (!r.ok) { console.error('Supabase Auth signup hatası:', await r.text()); return null; }
      const data = await r.json();
      const authUserId = data.user?.id;
      const accessToken = data.access_token;
      if (authUserId) {
        await fetch(SB_URL + '/rest/v1/kullanicilar?id=eq.' + user.id, {
          method: 'PATCH', headers: SB_HEADERS,
          body: JSON.stringify({ auth_user_id: authUserId })
        });
      }
      return accessToken || null;
    } else {
      const r = await fetch(SB_URL + '/auth/v1/token?grant_type=password', {
        method: 'POST', headers: { apikey: SB_KEY, 'Content-Type': 'application/json' },
        body: JSON.stringify({ email, password })
      });
      if (!r.ok) { console.error('Supabase Auth signin hatası:', await r.text()); return null; }
      const data = await r.json();
      return data.access_token || null;
    }
  } catch (e) { console.error('supabaseAuthKoprusu hatası:', e); return null; }
}
```

`checkPin()`, PIN eşleşmesinden sonra `const accessToken = await
supabaseAuthKoprusu(user);` çağırır ve `oturumKaydet(user, accessToken)`
ile kaydeder. **`accessToken` null dönerse bile PIN girişi engellenmez**
— kullanıcı normal şekilde içeri girer, sadece token boş kalır (bu fazda
hiçbir yerde kullanılmadığı için işlevsel bir kayıp yok; sonraki fazda bu
davranış gözden geçirilecek).

`auth-guard.js`'deki `oturumKaydet`:

```js
function oturumKaydet(user, accessToken) {
  sessionStorage.setItem(SESSION_KEY, JSON.stringify({ user, accessToken: accessToken || null, expiry: Date.now() + SESSION_SURESI_MS }));
}
```

`oturumGetir()` değişmiyor (zaten tüm nesneyi okuyup `user`'ı döndürüyor;
`accessToken`'ı ayrıca okuyan bir çağıran yok bu fazda — ileride Faz
A2'nin ekleyeceği bir okuma noktası).

## Veri akışı

Kullanıcı PIN girer → `checkPin()` eşleşen kullanıcıyı bulur → PIN doğru
→ `supabaseAuthKoprusu(user)` çağrılır → (ilk giriş) Supabase Auth hesabı
açılır + `auth_user_id` DB'ye yazılır + token alınır, VEYA (sonraki
girişler) doğrudan token alınır → `oturumKaydet(user, accessToken)` →
kullanıcı portala girer (mevcut akışla birebir aynı görünür, ekstra bir
gecikme dışında fark edilmez).

## Hata yönetimi

Supabase Auth çağrılarından herhangi biri başarısız olursa (`!r.ok` veya
network hatası), `supabaseAuthKoprusu` `null` döner ve konsola hata
yazar — ama **PIN girişi engellenmez**, kullanıcı normal şekilde içeri
alınır. Bu bilinçli bir tasarım kararı: bu fazda `accessToken`
kullanılmadığı için, Auth köprüsünün başarısız olması gerçek işlevi
etkilemez; günlük operasyonu bir Auth-bağlantı sorunu yüzünden
kilitlemek YAGNI'ye aykırı olur ve gereksiz risk yaratır.

## Test / doğrulama planı

Statik: `supabaseAuthKoprusu`'nun doğru endpoint'leri
(`/auth/v1/signup`, `/auth/v1/token?grant_type=password`) doğru gövdeyle
çağırdığını, `auth_user_id` PATCH'inin doğru koşulda (sadece ilk girişte)
tetiklendiğini, PIN başarısının Auth sonucuna bağlı olmadığını kod
okuyarak doğrulamak.

Gerçek uçtan uca (kullanıcı tarafından tarayıcıda): `auth_user_id`'si
boş bir kullanıcıyla PIN girişi yapmak → Supabase'de o kullanıcının
`auth_user_id`'sinin dolduğunu doğrulamak → aynı kullanıcıyla ikinci kez
giriş yapmak → bu sefer signup değil signin çağrıldığını (network
sekmesinden veya konsol logundan) doğrulamak → her iki durumda da PIN
girişinin eskisi gibi (gecikme dışında fark edilmeden) çalıştığını
teyit etmek.
