# Merkezi Giriş (Centralized Login) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** PIN girişini tek noktaya (`index.html`) toplamak; diğer tüm modül sayfaları kendi PIN ekranlarını kaldırıp paylaşılan `auth-guard.js` üzerinden oturum/rol kontrolü yapsın, oturumsuz doğrudan erişimde `index.html`'e yönlenip giriş sonrası orijinal sayfaya geri dönsün.

**Architecture:** Yeni `auth-guard.js` dosyası oturum okuma/yazma, PIN deneme kilitleme ve rol kontrolü fonksiyonlarını tek yerde toplar. `index.html` tek PIN ekranı olarak kalır ve `?returnTo=` parametresiyle geri yönlendirme yapar. Diğer 20 sayfa bu dosyayı yükleyip `requireLogin()`/`requireRole()` çağırır.

**Tech Stack:** Vanilla HTML/CSS/JS, build aracı yok, test çerçevesi yok (statik dosyalar, doğrudan tarayıcıda çalışır). Doğrulama bu ortamda tarayıcıda tıklayarak yapılamıyor — her görev statik/mantıksal doğrulama adımlarıyla kapanıyor (grep ile kalıntı kontrolü, kod okuyarak izleme).

## Global Constraints

- Tek oturum anahtarı: `gurok_portal_session` (spec).
- Oturum süresi: 30 dakika, tüm modüllerde aynı (spec).
- `returnTo` sadece `^[a-z0-9_-]+\.html(\?[^#]*)?(#.*)?$` kalıbına uyan göreli dosya adlarını kabul eder — tam URL veya `//` ile başlayan hiçbir değer kabul edilmez (spec, open-redirect önleme).
- Rol tablosu `index.html`'deki mevcut `MODULLER` dizisiyle birebir aynı olmalı (spec'teki tablo).
- Yanlış rolle (ama geçerli oturumla) erişimde YÖNLENDİRME YOK — sadece "erişim reddedildi" mesajı (sonsuz döngüyü önlemek için, spec).
- `bar.html`, `migrate-to-supabase.html`, `gurok_mal_kabul.html` bu planın kapsamı dışında (spec).

---

### Task 1: `auth-guard.js` paylaşılan modülünü oluştur

**Files:**
- Create: `auth-guard.js` (repo kökü, diğer tüm `.html` dosyalarıyla aynı dizin)

**Interfaces:**
- Produces: `SESSION_KEY` (string), `oturumGetir()` → `user|null`, `oturumKaydet(user)` → `void`, `requireLogin()` → `user|null` (oturum yoksa `index.html?returnTo=...`'a yönlendirir ve `null` döner), `requireRole(user, izinliRoller:string[])` → `boolean` (false ise body'yi "erişim reddedildi" ile değiştirir), `pinKilitliMi()` → `number` (kalan saniye, 0=kilitli değil), `pinBasarisizKaydet()` → `void`, `pinBasariliTemizle()` → `void`.
- Consumes: hiçbir şey (bağımsız, sadece `sessionStorage`/`localStorage`/`location`/`document` kullanır).

- [ ] **Step 1: Dosyayı oluştur**

```js
// auth-guard.js — Gürok ERP paylaşılan oturum/erişim kontrolü.
// index.html DIŞINDAKİ her modül sayfası bunu <head> içinde en üstte,
// senkron olarak yükler (<script src="auth-guard.js"></script> — defer/async YOK,
// sayfa gövdesi render edilmeden önce çalışmalı).

const SESSION_KEY = 'gurok_portal_session';
const SESSION_SURESI_MS = 30 * 60 * 1000;
const PIN_KILIT_ANAHTAR = 'gurok_pin_kilit';

function oturumGetir() {
  try {
    const s = sessionStorage.getItem(SESSION_KEY);
    if (!s) return null;
    const { user, expiry } = JSON.parse(s);
    if (!user || Date.now() >= expiry) return null;
    return user;
  } catch (e) { return null; }
}

function oturumKaydet(user) {
  sessionStorage.setItem(SESSION_KEY, JSON.stringify({ user, expiry: Date.now() + SESSION_SURESI_MS }));
}

// index.html DIŞINDAKİ sayfalar bunu çağırır. Oturum geçerliyse kullanıcıyı döner.
// Değilse index.html'e (geri dönüş adresiyle) yönlendirir ve null döner — çağıran
// kod null aldığında HİÇBİR ŞEY YAPMADAN durmalı (yönlendirme zaten gerçekleşti).
function requireLogin() {
  const user = oturumGetir();
  if (user) return user;
  const donusUrl = location.pathname.split('/').pop() + location.search + location.hash;
  location.replace('index.html?returnTo=' + encodeURIComponent(donusUrl));
  return null;
}

// Geçerli oturumu olan ama rolü yetersiz kullanıcı için — YÖNLENDİRME YAPMAZ
// (zaten giriş yapmış, index.html'e göndermek sonsuz döngü yaratır). Sadece
// erişimi reddeder ve body'yi bir "kapalı" mesajıyla değiştirir.
function requireRole(user, izinliRoller) {
  if (izinliRoller.includes(user.rol)) return true;
  document.body.innerHTML = `
    <div style="min-height:100vh;display:flex;align-items:center;justify-content:center;background:#f1f3f5;font-family:-apple-system,'Segoe UI',sans-serif;padding:20px">
      <div style="background:white;border-radius:16px;padding:32px 28px;max-width:340px;text-align:center;box-shadow:0 8px 40px rgba(0,0,0,.15)">
        <div style="font-size:40px;margin-bottom:12px">🔒</div>
        <div style="font-weight:700;color:#1a2744;margin-bottom:8px">Bu modül sana kapalı</div>
        <div style="font-size:13px;color:#6c757d;margin-bottom:20px">Hesabının rolü (${user.rol}) bu sayfayı açmaya yetmiyor.</div>
        <a href="index.html" style="display:inline-block;background:#1a2744;color:white;padding:10px 20px;border-radius:8px;text-decoration:none;font-size:13px;font-weight:600">Portala Dön</a>
      </div>
    </div>`;
  return false;
}

// PIN deneme sınırlaması — 5 hatalı denemeden sonra artan sürelerle (30sn, 60sn,
// ... en fazla 5dk) kilitlenir. Sadece index.html'in PIN ekranı kullanır.
function pinKilitliMi() {
  try {
    const s = JSON.parse(localStorage.getItem(PIN_KILIT_ANAHTAR) || '{}');
    if (s.kilitSonu && Date.now() < s.kilitSonu) return Math.ceil((s.kilitSonu - Date.now()) / 1000);
  } catch (e) {}
  return 0;
}
function pinBasarisizKaydet() {
  let s = {};
  try { s = JSON.parse(localStorage.getItem(PIN_KILIT_ANAHTAR) || '{}'); } catch (e) {}
  s.deneme = (s.deneme || 0) + 1;
  if (s.deneme >= 5) s.kilitSonu = Date.now() + Math.min(300000, 30000 * Math.pow(2, s.deneme - 5));
  localStorage.setItem(PIN_KILIT_ANAHTAR, JSON.stringify(s));
}
function pinBasariliTemizle() { localStorage.removeItem(PIN_KILIT_ANAHTAR); }
```

- [ ] **Step 2: Sözdizimini doğrula**

Run: `node --check auth-guard.js` (bu ortamda Node kurulu değilse, tarayıcı konsolunda `fetch('auth-guard.js').then(r=>r.text()).then(eval)` ile hatasız yüklendiğini kontrol et — build/test aracı yok, bu dosyanın tek başına geçerli JS olduğunu doğrulamanın elimizdeki tek yolu bu.)
Expected: hata yok.

- [ ] **Step 3: Commit**

```bash
git add auth-guard.js
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "Add shared auth-guard.js (session, PIN lockout, role gate)"
```

---

### Task 2: `index.html` — returnTo yönlendirmesi ve paylaşılan PIN kilitlemesine geçiş

**Files:**
- Modify: `index.html:3-5` (head'e script ekle), `index.html:334-340` (SESSION_KEY tanımı ve PIN kilit fonksiyonları — Task'ta "Kritik #10" ve "PIN #31" ile eklenmişti, şimdi auth-guard.js'e taşınıyor), `index.html:504-522` (checkPin), `index.html:596-613` (init IIFE)

**Interfaces:**
- Consumes: Task 1'in `oturumKaydet`, `pinKilitliMi`, `pinBasarisizKaydet`, `pinBasariliTemizle`, `oturumGetir`, `SESSION_KEY`.
- Produces: hiçbir şey (bu, zincirin sonu — başka hiçbir dosya index.html'i "kullanmaz").

- [ ] **Step 1: `<head>`'e auth-guard.js ekle**

`<meta charset="UTF-8">` satırından hemen sonra ekle:

```html
<script src="auth-guard.js"></script>
```

- [ ] **Step 2: index.html'in kendi `PIN_KILIT_ANAHTAR`/`pinKilitliMi`/`pinBasarisizKaydet`/`pinBasariliTemizle` tanımlarını sil**

Bu dört fonksiyon (bugün eklenmişti) `auth-guard.js` içinde zaten var — index.html'deki kopyalarını tamamen sil. `SESSION_KEY` sabiti de aynı isimle `auth-guard.js`'de tanımlı olduğu için index.html'deki `const SESSION_KEY = 'gurok_portal_session';` satırını da sil (çift tanım JS hatası verir).

- [ ] **Step 3: `checkPin()`'i returnTo yönlendirmesi ekleyecek şekilde güncelle**

Mevcut fonksiyonun sonunu (başarılı giriş dalı) şuna çevir:

```js
function checkPin() {
  const tumKullanicilar = users.length > 0 ? users : DEFAULT_USERS;
  const user = tumKullanicilar.find(u => String(u.pin) === String(pinValue));
  if (!user) {
    pinBasarisizKaydet();
    const kalanSn = pinKilitliMi();
    const errEl = document.getElementById('pin-error');
    errEl.textContent = kalanSn > 0 ? `🔒 Çok fazla hatalı deneme — ${kalanSn} sn kilitlendi` : '❌ Hatalı PIN';
    setTimeout(() => errEl.textContent = '', kalanSn > 0 ? 4000 : 2000);
    pinValue = '';
    updateDots();
    document.getElementById('pin-user-show').textContent = '';
    return;
  }
  pinBasariliTemizle();
  currentUser = user;
  oturumKaydet(user);
  const params = new URLSearchParams(location.search);
  const returnTo = params.get('returnTo');
  if (returnTo && /^[a-z0-9_-]+\.html(\?[^#]*)?(#.*)?$/i.test(returnTo)) {
    location.replace(returnTo);
    return;
  }
  showPortal();
}
```

- [ ] **Step 4: Sayfa açılışındaki oturum-geri-yükleme IIFE'sini `oturumGetir()` kullanacak şekilde sadeleştir**

Mevcut `(async function init() {...})();` bloğunun oturum kontrolü kısmını şuna çevir:

```js
(async function init() {
  document.getElementById('loading').classList.add('show');
  await loadUsers();
  document.getElementById('loading').classList.remove('show');
  const user = oturumGetir();
  if (user) {
    currentUser = user;
    showPortal();
  }
})();
```

- [ ] **Step 5: Doğrula**

```bash
grep -n "PIN_KILIT_ANAHTAR\|const SESSION_KEY" index.html
```

Expected: **hiçbir satır dönmemeli** (ikisi de artık sadece `auth-guard.js`'de).

```bash
grep -n "auth-guard.js\|oturumKaydet\|oturumGetir" index.html
```

Expected: 3 satır (script tag, checkPin içindeki oturumKaydet çağrısı, init IIFE içindeki oturumGetir çağrısı).

- [ ] **Step 6: Commit**

```bash
git add index.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "index.html: use shared auth-guard.js, add returnTo redirect after login"
```

---

### Task 3: `stok-takip.html` — kendi PIN ekranını kaldır, auth-guard'a geç

**Files:**
- Modify: `stok-takip.html:139-169` (login div — sil), `stok-takip.html:680-724` (pinInput/pinDelete/updatePinDots/checkPin/PIN kilit fonksiyonları — sil), `stok-takip.html:725-` (`checkSession()` — sil), `stok-takip.html:1629-1652` (init IIFE — değiştir)

**Interfaces:**
- Consumes: Task 1'in `requireLogin()`, `requireRole()`.
- Produces: `currentUser` global değişkeni (dosyanın geri kalanı zaten bu ismi kullanıyor — DEĞİŞMİYOR, sadece nasıl doldurulduğu değişiyor).

- [ ] **Step 1: `<head>`'e auth-guard.js ekle** (dosyanın en üstündeki `<meta charset="UTF-8">`'den sonra)

```html
<script src="auth-guard.js"></script>
```

- [ ] **Step 2: `<div id="screen-login">...</div>` bloğunu tamamen sil**

139. satırdaki `<div id="screen-login">` ile eşleşen kapanış `</div>`'ine kadar (170. satırdan önceki `<!-- APP -->` yorumuna kadar) olan tüm bloğu sil. `.pin-dot`, `.pin-pad`, `.pin-btn`, `.login-box` CSS kurallarını da (yalnızca bu ekran için kullanılıyorlarsa) `<style>` bloğundan sil — silmeden önce `grep -n "pin-dot\|pin-pad\|pin-btn\|login-box" stok-takip.html` ile başka yerde kullanılmadıklarını doğrula.

- [ ] **Step 3: PIN JS fonksiyonlarını sil**

`pinValue`, `pinInput()`, `pinDelete()`, `updatePinDots()`, `checkPin()`, `PIN_KILIT_ANAHTAR`, `pinKilitliMi()`, `pinBasarisizKaydet()`, `pinBasariliTemizle()` tanımlarının tamamını sil (bunlar `auth-guard.js`'e taşındı).

- [ ] **Step 4: `checkSession()` fonksiyonunu sil**

Bu fonksiyon artık `requireLogin()` ile değiştiriliyor, kullanılmıyor.

- [ ] **Step 5: init IIFE'sini auth-guard kullanacak şekilde değiştir**

```js
(async function init(){
  currentUser = requireLogin();
  if(!currentUser) return;
  if(!requireRole(currentUser, ['yonetici','depo'])) return;

  aktifDepoId=tamDepoId(aktifOtelId,depolarForOtel(aktifOtelId)[0].id);
  buildDepoSelectors(aktifOtelId);
  document.getElementById('otel-selector').value=aktifOtelId;
  document.getElementById('depo-selector').value=aktifDepoId;
  onIadeOtelChange(document.getElementById('iade-otel').value);
  renderIadeKalemler();
  await loadDB();
  buildIadeFirmaSelector();

  document.getElementById('header-depo-label').textContent=depoAdi(aktifDepoId);
  renderStok();

  await malKabulOnayKontrolEt();
  setInterval(malKabulOnayKontrolEt,30000);
})();
```

(Not: eski koddaki `screen-login` görünürlük toggle satırları kaldırıldı — login ekranı artık dosyada hiç yok, `#app` doğrudan gösteriliyor.)

- [ ] **Step 6: Doğrula**

```bash
grep -n "screen-login\|pinInput\|checkSession\b" stok-takip.html
```

Expected: **hiçbir satır dönmemeli.**

```bash
grep -n "requireLogin\|requireRole" stok-takip.html
```

Expected: init IIFE içinde 2 satır.

- [ ] **Step 7: Commit**

```bash
git add stok-takip.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "stok-takip.html: remove own login screen, use shared auth-guard.js"
```

---

### Task 4: `depo-siparis.html` — kendi PIN ekranını kaldır, auth-guard'a geç

**Files:**
- Modify: `depo-siparis.html:75-` (`<div id="login">` — sil), `depo-siparis.html:400-` (pi/pd/dots/checkPin/PIN kilit fonksiyonları — sil), `depo-siparis.html:448-` (`getSession()` — sil), `depo-siparis.html:1271-1284` (init IIFE — değiştir)

**Interfaces:**
- Consumes: Task 1'in `requireLogin()`, `requireRole()`.
- Produces: `CU` global değişkeni (dosyanın geri kalanı bu ismi kullanıyor — değişmiyor).

- [ ] **Step 1: `<head>`'e auth-guard.js ekle**

- [ ] **Step 2: `<div id="login">...</div>` bloğunu ve ilişkili PIN CSS'ini sil**

(Task 3, Step 2'deki aynı yöntem — kapsayan `</div>`'i bul, bloğu sil, CSS'in başka yerde kullanılmadığını doğrulayıp sil.)

- [ ] **Step 3: PIN JS fonksiyonlarını sil**

`pv`, `pi()`, `pd()`, `dots()`, `checkPin()`, `PIN_KILIT_ANAHTAR`, `pinKilitliMi()`, `pinBasarisizKaydet()`, `pinBasariliTemizle()`.

- [ ] **Step 4: `getSession()` fonksiyonunu sil**

- [ ] **Step 5: init IIFE'sini değiştir**

```js
(async function(){
  CU = requireLogin();
  if(!CU) return;
  if(!requireRole(CU, ['yonetici','depo','mutfak','bar'])) return;

  document.getElementById('otel-selector').value=aktifOtelId;
  buildDeptSelector();
  await loadDB();
  basla();
})();
```

- [ ] **Step 6: Doğrula**

```bash
grep -n 'id="login"\|function pi(\|function checkPin\|function getSession' depo-siparis.html
```

Expected: hiçbir satır dönmemeli.

- [ ] **Step 7: Commit**

```bash
git add depo-siparis.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "depo-siparis.html: remove own login screen, use shared auth-guard.js"
```

---

### Task 5: `satin-alma.html` — kendi PIN ekranını kaldır, auth-guard'a geç

**Files:**
- Modify: `satin-alma.html:85-` (`<div id="login">` — sil), `satin-alma.html:465-` (pi/pd/dots/checkPin/PIN kilit fonksiyonları — sil), `satin-alma.html:510-` (`getSession()` — sil), `satin-alma.html:2511-2516` (init IIFE — değiştir)

**Interfaces:**
- Consumes: Task 1'in `requireLogin()`, `requireRole()`.
- Produces: `CU` global değişkeni (değişmiyor).

- [ ] **Step 1: `<head>`'e auth-guard.js ekle**

- [ ] **Step 2: `<div id="login">...</div>` bloğunu ve ilişkili PIN CSS'ini sil**

- [ ] **Step 3: PIN JS fonksiyonlarını sil** (`pv`, `pi()`, `pd()`, `dots()`, `checkPin()`, `PIN_KILIT_ANAHTAR`, `pinKilitliMi()`, `pinBasarisizKaydet()`, `pinBasariliTemizle()`)

- [ ] **Step 4: `getSession()` fonksiyonunu sil**

- [ ] **Step 5: init IIFE'sini değiştir**

```js
(async function(){
  CU = requireLogin();
  if(!CU) return;
  if(!requireRole(CU, ['yonetici','satinalma','depo'])) return;
  await loadDB();
  basla();
})();
```

- [ ] **Step 6: Doğrula**

```bash
grep -n 'id="login"\|function pi(\|function checkPin\|function getSession' satin-alma.html
```

Expected: hiçbir satır dönmemeli.

- [ ] **Step 7: Commit**

```bash
git add satin-alma.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "satin-alma.html: remove own login screen, use shared auth-guard.js"
```

---

### Task 6: `gunluk-tuketim.html` — kendi PIN ekranını kaldır, auth-guard'a geç

**Files:**
- Modify: `gunluk-tuketim.html:66-` (`<div id="login">` — sil), `gunluk-tuketim.html:210-` (pi/pd/dots/checkPin/PIN kilit fonksiyonları — sil), `gunluk-tuketim.html:257-` (`getSession()` — sil), `gunluk-tuketim.html:877-888` (init IIFE — değiştir)

**Interfaces:**
- Consumes: Task 1'in `requireLogin()`, `requireRole()`.
- Produces: `CU` global değişkeni (değişmiyor).

- [ ] **Step 1: `<head>`'e auth-guard.js ekle**

- [ ] **Step 2: `<div id="login">...</div>` bloğunu ve ilişkili PIN CSS'ini sil**

- [ ] **Step 3: PIN JS fonksiyonlarını sil** (`pv`, `pi()`, `pd()`, `dots()`, `checkPin()`, `PIN_KILIT_ANAHTAR`, `pinKilitliMi()`, `pinBasarisizKaydet()`, `pinBasariliTemizle()`)

Not: eski `checkPin()` burada PIN doğru ama rol mutfak/bar/yonetici değilse ayrı bir hata veriyordu — bu davranış artık `requireRole()`'a taşınıyor, Step 5'e bak.

- [ ] **Step 4: `getSession()` fonksiyonunu sil**

- [ ] **Step 5: init IIFE'sini değiştir**

```js
(async function(){
  CU = requireLogin();
  if(!CU) return;
  if(!requireRole(CU, ['mutfak','bar','yonetici'])) return;
  await loadKullanicilar();
  await loadUrunAdlari();
  basla();
})();
```

- [ ] **Step 6: Doğrula**

```bash
grep -n 'id="login"\|function pi(\|function checkPin\|function getSession' gunluk-tuketim.html
```

Expected: hiçbir satır dönmemeli.

- [ ] **Step 7: Commit**

```bash
git add gunluk-tuketim.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "gunluk-tuketim.html: remove own login screen, use shared auth-guard.js"
```

---

### Task 7: `mal-kabul-v2.html` — kendi PIN ekranını kaldır, auth-guard'a geç

**Files:**
- Modify: `mal-kabul-v2.html:92-` (`<div id="loginScreen">` — sil), `mal-kabul-v2.html:399-420` (pinInput/pinClear/pinBack/updateDots/girisYap — sil), `mal-kabul-v2.html:422-430` (`loadKullanicilar()` — sil, artık gereksiz), `mal-kabul-v2.html:2429-2432` (init IIFE — değiştir)

**Interfaces:**
- Consumes: Task 1'in `requireLogin()`, `requireRole()`.
- Produces: `currentUser` global değişkeni (dosyanın geri kalanı — `formOtelId=currentUser.otelId||'810'` dahil — bu ismi kullanıyor, değişmiyor).

Not: Bu dosyanın diğer 4'ten farkı — şu an sessionStorage'a hiç yazmıyor, her sayfa
yenilemesinde PIN yeniden isteniyordu. auth-guard.js'e geçince bu eksiklik de
kendiliğinden düzeliyor (artık diğer modüllerle aynı 30 dakikalık paylaşılan oturumu
kullanacak).

- [ ] **Step 1: `<head>`'e auth-guard.js ekle**

- [ ] **Step 2: `<div id="loginScreen">...</div>` bloğunu ve ilişkili PIN CSS'ini sil**

- [ ] **Step 3: PIN JS fonksiyonlarını sil**

`pinValue`, `updateDots()`, `pinInput()`, `pinClear()`, `pinBack()`, `girisYap()`.

- [ ] **Step 4: `loadKullanicilar()` fonksiyonunu ve tek çağrı noktasını sil**

Bu fonksiyon sadece PIN eşleştirmesi için `kullanicilar` dizisini dolduruyordu — artık kullanılmıyor. `let currentUser=null, kullanicilar=[];` satırındaki `kullanicilar=[]` kısmını da kaldırıp `let currentUser=null;` yap (dosyanın başka hiçbir yerinde `kullanicilar` kullanılmadığını `grep -n "kullanicilar" mal-kabul-v2.html` ile doğrula — Task hazırlığı sırasında sadece login'de kullanıldığı zaten teyit edildi).

- [ ] **Step 5: init IIFE'sini değiştir**

```js
(function(){
  currentUser = requireLogin();
  if(!currentUser) return;
  if(!requireRole(currentUser, ['yonetici','depo','satinalma','kalite'])) return;
  document.getElementById('hdrUser').textContent='👤 '+currentUser.ad;
  document.getElementById('hdrOtel').textContent=currentUser.otelId?('🏨 '+OTEL_KISA[currentUser.otelId]):'';
  initApp();
})();
```

- [ ] **Step 6: Doğrula**

```bash
grep -n 'loginScreen\|function pinInput\|function girisYap\|loadKullanicilar' mal-kabul-v2.html
```

Expected: hiçbir satır dönmemeli.

- [ ] **Step 7: Commit**

```bash
git add mal-kabul-v2.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "mal-kabul-v2.html: remove own login screen, use shared auth-guard.js"
```

---

### Task 8: 16 dosyadaki gömülü gate kopyalarını `auth-guard.js`'e taşı

**Context:** Bu 16 dosya (`muhasebe.html`, `muhasebe-cariler.html`, `muhasebe-faturalar.html`,
`muhasebe-hesap-plani.html`, `muhasebe-yevmiye.html`, `muhasebe-banka.html`,
`muhasebe-kur.html`, `muhasebe-cek-senet.html`, `muhasebe-demirbas.html`,
`muhasebe-butce.html`, `muhasebe-sene-sonu.html`, `muhasebe-raporlar.html`,
`muhasebe-denetim.html`, `muhasebe-asistan.html`, `yetki-yonetimi.html`) — ve ayrı
bir varyantla `kullanici-yonetimi.html` — bugün daha önce eklenen kendi PIN ekranı
YOK, sadece "oturum var mı" kontrol eden gömülü bir IIFE var. Bu görevde bu gömülü
kopyalar silinip `auth-guard.js` kullanımına geçiliyor. Davranış aynı kalıyor,
sadece kod tekrarı ortadan kalkıyor.

**Files:**
- Modify (14 dosya, hepsi aynı desen): `muhasebe.html:5-27`, `muhasebe-cariler.html`,
  `muhasebe-faturalar.html`, `muhasebe-hesap-plani.html`, `muhasebe-yevmiye.html`,
  `muhasebe-banka.html`, `muhasebe-kur.html`, `muhasebe-cek-senet.html`,
  `muhasebe-demirbas.html`, `muhasebe-butce.html`, `muhasebe-sene-sonu.html`,
  `muhasebe-raporlar.html`, `muhasebe-denetim.html`, `muhasebe-asistan.html`
  (`<script>` bloğu, `<meta charset="UTF-8">`'den hemen sonra — bugün eklendiği için
  hepsinde satır 5-27 aralığında)
- Modify: `yetki-yonetimi.html` (kendi `erisimVarMi()` deseni)
- Modify: `kullanici-yonetimi.html` (kendi `oturumAcanKullanici()`/`OTURUM_KULLANICI` deseni)

**Interfaces:**
- Consumes: Task 1'in `requireLogin()`, `requireRole()`.
- Produces: Bu 16 dosyanın hiçbiri başka bir dosyanın bağımlı olduğu bir arayüz üretmiyor (yaprak düğümler).

- [ ] **Step 1: 14 muhasebe dosyasındaki gömülü bloğu sil ve auth-guard.js + guard çağrısıyla değiştir**

Her dosyada şuna benzeyen bloğu (satır 5-27 civarı, `<meta charset="UTF-8">`'den hemen sonra):

```html
<script>
// Erişim kontrolü — Muhasebe modülü, PIN girişi gerektirmeden doğrudan URL ile
// açılabiliyordu (denetimde bulundu). ...
let OTURUM_KULLANICI=null;
(function(){
  function oturumuBul(){ ... }
  OTURUM_KULLANICI=oturumuBul();
  if(!OTURUM_KULLANICI)location.replace('index.html');
})();
</script>
```

şununla değiştir:

```html
<script src="auth-guard.js"></script>
<script>
let OTURUM_KULLANICI = requireLogin();
if (OTURUM_KULLANICI) requireRole(OTURUM_KULLANICI, ['yonetici','satinalma']);
</script>
```

(`OTURUM_KULLANICI` ismi korunuyor çünkü bu 14 dosyanın hepsinde `auditLogYaz()`
içinde `OTURUM_KULLANICI?.ad` olarak zaten kullanılıyor — değişken adını değiştirmek
gereksiz risk. `requireLogin()` zaten null ise yönlendirmeyi kendi içinde yapıyor,
bu yüzden burada ekstra "if null return" gerekmiyor — `if(OTURUM_KULLANICI)` sarmalı
sadece `requireRole`'ün null'a çağrılmasını önlüyor.)

Bunu 14 dosyanın her birinde tek tek uygula (isimler yukarıdaki listede). Rol listesi
hepsinde aynı: `['yonetici','satinalma']`.

- [ ] **Step 2: `yetki-yonetimi.html`'i güncelle**

Mevcut `erisimVarMi()` fonksiyonunu ve onu çağıran `if(!erisimVarMi()){...}else{yukle();}`
bloğunu sil, şununla değiştir:

```js
const OTURUM_KULLANICI = requireLogin();
if (OTURUM_KULLANICI && requireRole(OTURUM_KULLANICI, ['yonetici'])) {
  yukle();
}
```

`<head>`'e `<script src="auth-guard.js"></script>` eklemeyi unutma.

- [ ] **Step 3: `kullanici-yonetimi.html`'i güncelle**

Bu dosyanın deseni biraz farklı (`oturumAcanKullanici()` fonksiyonu + `OTURUM_KULLANICI`
global + `render()`'dan önce çalışan IIFE). Mevcut `oturumAcanKullanici()` fonksiyonunu
ve onu çağıran IIFE'yi sil, şununla değiştir:

```js
(async function(){
  OTURUM_KULLANICI = requireLogin();
  if(!OTURUM_KULLANICI) return;
  if(!requireRole(OTURUM_KULLANICI, ['yonetici'])) return;
  await loadDB();
  render();
})();
```

`let OTURUM_KULLANICI=null;` tanımı kalsın (dosyanın geri kalanı, örn. `auditLogYaz()`,
bunu kullanıyor). `<head>`'e `<script src="auth-guard.js"></script>` eklemeyi unutma.

- [ ] **Step 4: Doğrula — hiçbir dosyada eski gate kalıntısı kalmadığını kontrol et**

```bash
grep -rln "function oturumuBul\|function erisimVarMi\|function oturumAcanKullanici" *.html
```

Expected: **hiçbir dosya dönmemeli** (hepsi `auth-guard.js`'deki paylaşılan
fonksiyonları kullanıyor artık).

```bash
grep -rlL "auth-guard.js" muhasebe.html muhasebe-cariler.html muhasebe-faturalar.html muhasebe-hesap-plani.html muhasebe-yevmiye.html muhasebe-banka.html muhasebe-kur.html muhasebe-cek-senet.html muhasebe-demirbas.html muhasebe-butce.html muhasebe-sene-sonu.html muhasebe-raporlar.html muhasebe-denetim.html muhasebe-asistan.html yetki-yonetimi.html kullanici-yonetimi.html
```

Expected: **hiçbir dosya dönmemeli** (`-L` = eşleşmeyenleri listele; boş çıktı =
hepsinde `auth-guard.js` referansı var).

- [ ] **Step 5: Commit**

```bash
git add muhasebe.html muhasebe-cariler.html muhasebe-faturalar.html muhasebe-hesap-plani.html muhasebe-yevmiye.html muhasebe-banka.html muhasebe-kur.html muhasebe-cek-senet.html muhasebe-demirbas.html muhasebe-butce.html muhasebe-sene-sonu.html muhasebe-raporlar.html muhasebe-denetim.html muhasebe-asistan.html yetki-yonetimi.html kullanici-yonetimi.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "Switch 16 already-gated pages from inline gate copies to shared auth-guard.js"
```

---

### Task 9: Uçtan uca elle doğrulama (test çerçevesi yok)

**Files:** Yok (sadece doğrulama — kod değişikliği içermez)

**Context:** Bu proje bir build/test aracına sahip değil ve bu ortamdan gerçek bir
tarayıcıda tıklayarak test yapılamıyor. Bu görev, kullanıcının (ya da bu planı
yürüten ajanın, kendi tarayıcı erişimi varsa) uygulamayı gerçek bir tarayıcıda açıp
takip etmesi gereken somut bir kontrol listesidir.

- [ ] **Step 1: Temiz oturumla doğrudan modül erişimi**

Tarayıcı konsolunda `sessionStorage.clear()` çalıştır, sonra `stok-takip.html`'i
doğrudan aç. Beklenen: anında `index.html?returnTo=stok-takip.html`'e yönlenmeli,
PIN ekranı görünmeli.

- [ ] **Step 2: Giriş sonrası geri dönüş**

Adım 1'in devamında geçerli bir PIN gir (örn. depo rolü). Beklenen: giriş sonrası
otomatik olarak `stok-takip.html`'e dönmeli, portal ızgarası GÖRÜNMEMELİ.

- [ ] **Step 3: Yanlış rolle erişim**

Mutfak rolündeki bir PIN ile giriş yap, sonra tarayıcı adres çubuğuna elle
`muhasebe.html` yaz. Beklenen: "Bu modül sana kapalı" mesajı, yönlendirme
döngüsü YOK.

- [ ] **Step 4: Doğru rolle her modülü tek tek aç**

Yönetici rolüyle giriş yaptıktan sonra sırayla: `stok-takip.html`,
`depo-siparis.html`, `satin-alma.html`, `gunluk-tuketim.html`, `mal-kabul-v2.html`,
`muhasebe.html`, `kullanici-yonetimi.html`, `yetki-yonetimi.html` — hepsi
PIN istemeden doğrudan açılmalı.

- [ ] **Step 5: PIN kilitleme hâlâ çalışıyor mu**

`index.html`'de 5 kez yanlış PIN dene. Beklenen: 5. denemeden sonra "🔒 Çok fazla
hatalı deneme — 30 sn kilitlendi" mesajı, PIN pad'e her basışta aynı mesaj
tekrar gösterilmeli (kilit süresi dolana kadar).

- [ ] **Step 6: Oturum süresi doldu senaryosu**

Tarayıcı konsolunda `sessionStorage.setItem('gurok_portal_session', JSON.stringify({user:{...mevcut kullanıcı...}, expiry: Date.now()-1000}))` ile süresi dolmuş bir oturum simüle et, herhangi bir modülü aç. Beklenen: geçerli oturum yokmuş gibi `index.html`'e yönlenmeli.

- [ ] **Step 7: `returnTo` beyaz liste kontrolü**

`index.html?returnTo=//evil.com` ve `index.html?returnTo=https://evil.com/x.html`
adreslerini elle aç, geçerli bir PIN gir. Beklenen: HER İKİSİNDE de `returnTo`
yok sayılmalı, normal portal ızgarası gösterilmeli (evil.com'a ASLA yönlenmemeli).

- [ ] **Step 8: Sonuçları kaydet**

Yukarıdaki 7 adımdan herhangi biri beklenenden farklı davranırsa, ilgili Task'a
dönüp kodu düzelt, bu Task'ı tekrar çalıştır. Hepsi geçtiğinde bu planı tamamlanmış
say.
