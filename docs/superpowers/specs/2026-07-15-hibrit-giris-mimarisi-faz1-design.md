# Hibrit Giriş Mimarisi — Faz 1 (Altyapı) — Tasarım

## Problem / Hedef

Sahada çalışan personel (mutfak/bar/depo) PIN ile girmeye devam etsin, ama
beyaz yaka/yönetim/muhasebe rolleri ileride Microsoft 365 (Azure AD) ile
tek tıkla giriş yapabilsin (SSO). Bu faz sadece hazırlık — Azure/OAuth
bağlantısı KURULMUYOR, sadece ileride entegrasyonun tek iş kalacağı
altyapı hazırlanıyor.

## Kapsam düzeltmesi (önemli)

Görev talebi, session/PIN mimarisinin şu an 4 ayrı dosyada 4 ayrı
sessionStorage anahtarıyla dağınık olduğunu varsayıyordu. Kod tabanı
kontrol edildi — bu, bu projede **daha önce tamamlanmış** bir işin
(auth-guard.js merkezi login/session modülü, `gurok_portal_session` tek
anahtarı, `requireLogin()`/`requireRole()`) ESKİ/güncel olmayan bir
tasviri. Doğrulanan gerçek durum:

- `auth-guard.js` zaten tek bir `SESSION_KEY='gurok_portal_session'`
  tanımlıyor, `requireLogin()`/`requireRole()` sağlıyor.
- **Sadece `index.html`'in gerçek bir PIN giriş ekranı var**
  (`pinInput()`, `checkPin()`, `loadUsers()`). `mal-kabul-v2.html`,
  `depo-siparis.html`, `gunluk-tuketim.html` (ve auth-guard.js kullanan
  diğer tüm dosyalar) kendi PIN ekranlarına/session anahtarlarına sahip
  değil — hepsi `requireLogin()` üzerinden `index.html`'in oturumunu
  kontrol ediyor.
- `gurok_session`/`gurok_siparis_session`/`gurok_tuketim_session`
  anahtarları hiçbir aktif dosyada yok (sadece eski/legacy
  `gurok_mal_kabul.html`'de ve geçmiş planlama dokümanlarında).

Kullanıcı onayıyla: session anahtarı **`gurok_portal_session` olarak
kalacak** (yeniden adlandırma yok — fonksiyonel fayda yok, gereksiz risk).
Bu yüzden orijinal görevin "session anahtarlarını birleştir" maddesi
**kapsam dışı bırakıldı** (zaten tamamlanmış durumda).

## Kapsam

1. **SQL:** `kullanicilar` tablosuna nullable, unique `eposta` kolonu
   eklenir.
2. **"Microsoft ile Giriş" butonu:** SADECE `index.html`'in PIN giriş
   ekranına eklenir (tek gerçek login ekranı budur). Pasif/placeholder —
   tıklanınca `showToast('🔷 Microsoft girişi yakında aktif olacak')`
   gösterir, gerçek OAuth yok.
3. **`findUserByEmail(email)` yardımcı fonksiyonu:** `index.html`'e
   eklenir (mevcut `loadUsers()`'ın doldurduğu `users` dizisini kullanır).
   Henüz hiçbir yerden çağrılmıyor — sadece Azure entegrasyonu geldiğinde
   hazır olması için.

## Kapsam dışı

- Session anahtarlarının yeniden adlandırılması — zaten birleşik,
  kullanıcı onayıyla dokunulmuyor.
- Azure/Entra ID uygulama kaydı, Client ID/Secret, Supabase Auth
  Provider kurulumu, gerçek OAuth redirect akışı — hiçbiri bu fazda yok.
- `pin` alanının kaldırılması veya zorunlu e-posta girişine geçiş — PIN
  kalıcı olarak duracak.
- `mal-kabul-v2.html`/`depo-siparis.html`/`gunluk-tuketim.html`'e
  herhangi bir değişiklik — bunların kendi login ekranı olmadığı için
  bu görevin hiçbir maddesi bu dosyaları etkilemiyor.

## Mimari

**SQL (kullanıcı tarafından Supabase SQL editöründe çalıştırılacak):**

```sql
alter table kullanicilar add column if not exists eposta text unique;
```

**`index.html` — buton:** `.pin-pad` div'inin hemen altına, `.login-box`
içinde, `.pin-btn` ile aynı `var(--primary)` renk paletini kullanan yeni
bir buton eklenir:

```html
<button class="btn-ms" onclick="showToast('🔷 Microsoft girişi yakında aktif olacak')">
  🔷 Microsoft ile Giriş
</button>
```

```css
.btn-ms{width:100%;margin-top:14px;padding:12px;border:1.5px solid var(--primary);border-radius:12px;background:white;color:var(--primary);font-size:14px;font-weight:600;cursor:pointer}
.btn-ms:active{background:var(--gray-100)}
```

**`index.html` — `findUserByEmail`:** `loadUsers()` fonksiyonunun hemen
altına eklenir (aynı dosyadaki `users` modül-seviyesi diziyi okur):

```js
function findUserByEmail(email) {
  return users.find(u => u.eposta && u.eposta.toLowerCase() === String(email).toLowerCase()) || null;
}
```

## Test/doğrulama planı

Statik: `findUserByEmail`'in `users` dizisini doğru okuduğunu, hiçbir
yerden henüz çağrılmadığını (dead code olarak kalması bekleniyor,
hata değil) kod okuyarak doğrulamak. Buton stilinin PIN pad ile tutarlı
olduğunu görsel olarak doğrulamak.

Gerçek uçtan uca test: SQL'i kullanıcı Supabase'de çalıştırıp `eposta`
kolonunun oluştuğunu doğrulayacak; PIN ile giriş hâlâ eskisi gibi
çalıştığını (regresyon yok) ve "Microsoft ile Giriş" butonuna
tıklayınca toast'ın hatasız göründüğünü tarayıcıda test edecek.
