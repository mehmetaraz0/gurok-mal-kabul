# Supabase Auth Köprüsü Faz A2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Faz A'da alınan Supabase Auth `access_token`'ı, mevcut oturum varsa gerçek `fetch()` isteklerinde (`Authorization` header) kullanmaya başlamak — token yoksa/geçersizse otomatik olarak eskisi gibi anon key'e düşerek.

**Architecture:** `auth-guard.js`'e `oturumGetir()` ile aynı hata-toleranslı deseni kullanan yeni bir `oturumAccessTokenGetir()` fonksiyonu eklenir. `supabase-config.js`'deki `SB_HEADERS`, artık sabit bir nesne değil, sayfa yüklenirken bu fonksiyonu çağırıp hesaplanan bir IIFE (immediately-invoked function expression) olur. `auth-guard.js` her zaman `supabase-config.js`'den ÖNCE yüklendiği için (28 dosyada doğrulandı), bu iki dosyalık değişiklik tüm sayfaları otomatik kapsar.

**Tech Stack:** Vanilla JS, `sessionStorage`. Build aracı/test çerçevesi yok — doğrulama grep + manuel kod okuma + kullanıcının tarayıcıda uçtan uca testi.

## Global Constraints

- `SB_HEADERS`, HER KOŞULDA (token var/yok/süresi geçmiş/bozuk oturum verisi) geçerli bir `Authorization` header'ı üretmeli — asla `undefined`/boş üretemez, asla exception fırlatamaz.
- `oturumAccessTokenGetir()`, `oturumGetir()`'in AYNI hata-toleranslı deseninde olmalı (`try/catch`, `null` dönüş, exception fırlatmama).
- `apikey` header'ı her zaman `SB_KEY` (anon key) olarak kalır — sadece `Authorization`'ın değeri değişir.
- Bu görev, `stok_hareketleri`/`cariler` gibi hiçbir tabloya, hiçbir RLS politikasına dokunmuyor — SADECE hangi header'ın gönderildiğini değiştiriyor.
- 28 sayfanın hiçbirinin kendi kodu değiştirilmiyor — hepsi `supabase-config.js`'i olduğu gibi yüklemeye devam ediyor.

---

### Task 1: `auth-guard.js` — `oturumAccessTokenGetir()` fonksiyonu

**Files:**
- Modify: `auth-guard.js:18-23` (`oturumKaydet`'in hemen altına ekleme)

**Interfaces:**
- Consumes: (yok — sadece `SESSION_KEY` global sabitini okur, dosyanın kendi tepesinde zaten tanımlı)
- Produces: `oturumAccessTokenGetir()` — Task 2'nin `supabase-config.js`'i bu fonksiyonu çağıracak.

- [ ] **Step 1: Yeni fonksiyonu ekle**

`auth-guard.js:20-23`'teki mevcut kod:

```js
function oturumKaydet(user, accessToken) {
  sessionStorage.setItem(SESSION_KEY, JSON.stringify({ user, accessToken: accessToken || null, expiry: Date.now() + SESSION_SURESI_MS }));
}

// index.html DIŞINDAKİ sayfalar bunu çağırır. Oturum geçerliyse kullanıcıyı döner.
```

Şununla değiştir:

```js
function oturumKaydet(user, accessToken) {
  sessionStorage.setItem(SESSION_KEY, JSON.stringify({ user, accessToken: accessToken || null, expiry: Date.now() + SESSION_SURESI_MS }));
}

// supabase-config.js bunu çağırır (auth-guard.js ondan önce yüklenir).
// Geçerli bir Supabase Auth token varsa döner, yoksa null (anon key'e düşülür).
function oturumAccessTokenGetir() {
  try {
    const s = sessionStorage.getItem(SESSION_KEY);
    if (!s) return null;
    const { accessToken, expiry } = JSON.parse(s);
    if (!accessToken || Date.now() >= expiry) return null;
    return accessToken;
  } catch (e) { return null; }
}

// index.html DIŞINDAKİ sayfalar bunu çağırır. Oturum geçerliyse kullanıcıyı döner.
```

(Tek değişiklik: `oturumKaydet` ile `requireLogin` yorumunun arasına yeni `oturumAccessTokenGetir` fonksiyonu eklendi.)

- [ ] **Step 2: Grep ile doğrula**

```bash
grep -n "function oturumAccessTokenGetir" auth-guard.js
```

Expected: `function oturumAccessTokenGetir() {` satırı görünmeli.

- [ ] **Step 3: Commit**

```bash
cd "C:\Users\USER\Projects\gurok-mal-kabul"
git add auth-guard.js
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: auth-guard.js'e oturumAccessTokenGetir() ekle"
```

---

### Task 2: `supabase-config.js` — `SB_HEADERS`'ı dinamik hale getir

**Files:**
- Modify: `supabase-config.js:11`

**Interfaces:**
- Consumes: Task 1'in ürettiği `oturumAccessTokenGetir()` (global, `auth-guard.js`'den, her zaman bu dosyadan önce yüklü).
- Produces: (yok — `SB_HEADERS`, 28 sayfanın zaten tükettiği mevcut global; şekli/adı değişmiyor, sadece değeri artık dinamik hesaplanıyor)

- [ ] **Step 1: `SB_HEADERS` tanımını güncelle**

`supabase-config.js:9-11`'deki mevcut kod:

```js
const SB_URL='https://xwytofysmgqtqjzkplfi.supabase.co';
const SB_KEY='eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inh3eXRvZnlzbWdxdHFqemtwbGZpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMyMjg5ODMsImV4cCI6MjA5ODgwNDk4M30.E7cRcOAvCmUFXWs45t4HE-igpmqWmSN2J66dOuvCHjA';
const SB_HEADERS={'apikey':SB_KEY,'Authorization':'Bearer '+SB_KEY,'Content-Type':'application/json'};
```

Şununla değiştir:

```js
const SB_URL='https://xwytofysmgqtqjzkplfi.supabase.co';
const SB_KEY='eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inh3eXRvZnlzbWdxdHFqemtwbGZpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMyMjg5ODMsImV4cCI6MjA5ODgwNDk4M30.E7cRcOAvCmUFXWs45t4HE-igpmqWmSN2J66dOuvCHjA';
const SB_HEADERS = (function(){
  const token = (typeof oturumAccessTokenGetir === 'function') ? oturumAccessTokenGetir() : null;
  return {'apikey':SB_KEY,'Authorization':'Bearer '+(token||SB_KEY),'Content-Type':'application/json'};
})();
```

(Tek değişiklik: `SB_HEADERS`'ın sabit değeri, `oturumAccessTokenGetir()`'i çağırıp token varsa onu, yoksa `SB_KEY`'i kullanan bir IIFE ile değiştirildi. `typeof ... === 'function'` kontrolü, `auth-guard.js` yüklenmemiş bir sayfada `ReferenceError` fırlatmak yerine sessizce anon key'e düşülmesini sağlıyor.)

- [ ] **Step 2: Grep ile doğrula**

```bash
grep -n "oturumAccessTokenGetir" supabase-config.js
```

Expected: `const token = (typeof oturumAccessTokenGetir === 'function') ? oturumAccessTokenGetir() : null;` satırı görünmeli.

- [ ] **Step 3: Commit**

```bash
cd "C:\Users\USER\Projects\gurok-mal-kabul"
git add supabase-config.js
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: SB_HEADERS artık oturum varsa kullanıcının Supabase Auth token'ını kullanıyor"
```

---

### Task 3: Uçtan uca doğrulama

**Files:** (yok — sadece doğrulama)

- [ ] **Step 1: Statik doğrulama**

Task 1 ve Task 2'nin grep adımlarının temiz geçtiğini teyit et. `SB_HEADERS`'ın her üç durumda (token var / token yok / oturum yok) da geçerli bir `Authorization` string'i ürettiğini kod okuyarak doğrula — `token||SB_KEY` ifadesi bunu garanti ediyor, testi gerektirmiyor.

- [ ] **Step 2: Controller'ın kendi tarayıcı-benzeri doğrulaması**

Gerçek bir test kullanıcısının (Faz A'da zaten `auth_user_id` bağlanmış) PIN'iyle `/auth/v1/token?grant_type=password` çağırıp taze bir `access_token` al. Bu token'ı elle bir `sessionStorage` nesnesi olarak simüle ETMEK yerine — kod zaten Task 1/2'de doğru okunuyor olduğu doğrulandığından, doğrudan bu token'la `SB_URL/rest/v1/stok?select=id&limit=1` isteğini curl ile tekrar çağırıp `200` döndüğünü teyit et (bu, tasarım aşamasında zaten yapıldı — burada sadece deploy sonrası tekrar bir sağlık kontrolü).

- [ ] **Step 3: Kullanıcıya manuel test adımlarını bildir**

Kullanıcının tarayıcıda doğrulaması gereken akış:
1. `index.html`'de PIN ile giriş yap → eskisi gibi çalışmalı.
2. `stok-takip.html`, `muhasebe-yevmiye.html` gibi birkaç farklı sayfaya git, normal bir işlem yap (örn. stok görüntüle, bir kayıt aç) → hiçbir hata/davranış farkı olmamalı.
3. (Opsiyonel ama önerilir) Tarayıcı DevTools → Network sekmesini aç, bir Supabase isteğine tıkla, Request Headers'da `Authorization` değerinin artık sabit anon key değil, farklı (kullanıcıya özel) bir JWT olduğunu gör.
4. Herhangi bir hata/kırılma/veri görünmemesi durumu olursa hemen bildir.

- [ ] **Step 4: Kullanıcıdan onay al**

"Test ettim, çalışıyor" onayını bekle, ardından push kararını sor.
