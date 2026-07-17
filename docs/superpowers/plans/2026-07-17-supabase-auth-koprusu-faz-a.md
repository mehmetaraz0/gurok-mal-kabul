# Supabase Auth Köprüsü Faz A Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** PIN girişi sırasında, arka planda görünmez bir Supabase Auth hesabı açıp/bağlayıp bir `access_token` almak — PIN ekranı/akışı hiç değişmeden, hiçbir gerçek veri isteğinin davranışı etkilenmeden.

**Architecture:** `index.html`'in `checkPin()`'i, PIN eşleşmesinden sonra yeni bir `supabaseAuthKoprusu(user)` yardımcı fonksiyonunu çağırır — bu, kullanıcının `auth_user_id`'si boşsa Supabase Auth'ta `{id}@gurok.internal` e-postasıyla yeni hesap açar (`/auth/v1/signup`) ve dönen Auth ID'sini `kullanicilar.auth_user_id`'ye yazar; doluysa doğrudan giriş yapar (`/auth/v1/token?grant_type=password`). Dönen `access_token`, `auth-guard.js`'nin `oturumKaydet()`'ine ikinci parametre olarak eklenir ve session nesnesine kaydedilir — ama bu fazda HİÇBİR YERDE kullanılmaz.

**Tech Stack:** Vanilla JS, raw `fetch()` (supabase-js kütüphanesi eklenmiyor — kod tabanının mevcut deseni). Build aracı/test çerçevesi yok — doğrulama grep + manuel kod okuma + kullanıcının tarayıcıda uçtan uca testi.

## Global Constraints

- PIN karşılaştırma mantığı (`String(u.pin) === String(pinValue)`) DEĞİŞMEZ — PIN hâlâ tek başına giriş yeterliliğini belirler.
- `supabaseAuthKoprusu()` başarısız olursa (network hatası, `!r.ok`) PIN girişi ENGELLENMEZ — kullanıcı normal şekilde içeri alınır, sadece `accessToken` `null` kalır.
- PIN'ler her zaman 6 haneli (`pinInput()`'taki `pinValue.length === 6` kontrolüyle doğrulandı) — Supabase Auth'un varsayılan 6 karakter minimum şifre kuralını karşılıyor, ekstra dolgu/dönüşüm gerekmez.
- `SB_URL`/`SB_KEY`/`SB_HEADERS` zaten `supabase-config.js`'den global olarak geliyor (`index.html:6`) — yeniden tanımlanmaz.
- Bu fazda `access_token`'ın herhangi bir gerçek veri isteğinde (`fetch`) kullanılması YOK — tüm `fetch()` çağrıları hâlâ `SB_HEADERS` (sabit anon key) ile çalışır.
- `mal-kabul-v2.html`, `depo-siparis.html`, `gunluk-tuketim.html` ve diğer modül dosyalarına DOKUNULMAZ.

---

### Task 1: `auth-guard.js` — `oturumKaydet` accessToken parametresi

**Files:**
- Modify: `auth-guard.js:20-22`

**Interfaces:**
- Consumes: (yok)
- Produces: `oturumKaydet(user, accessToken)` — Task 2'nin `checkPin()`'i bu güncellenmiş imzayla çağıracak.

- [ ] **Step 1: `oturumKaydet`'i güncelle**

`auth-guard.js:20-22`'deki mevcut kod:

```js
function oturumKaydet(user) {
  sessionStorage.setItem(SESSION_KEY, JSON.stringify({ user, expiry: Date.now() + SESSION_SURESI_MS }));
}
```

Şununla değiştir:

```js
function oturumKaydet(user, accessToken) {
  sessionStorage.setItem(SESSION_KEY, JSON.stringify({ user, accessToken: accessToken || null, expiry: Date.now() + SESSION_SURESI_MS }));
}
```

(Tek değişiklik: ikinci parametre `accessToken` eklendi, session nesnesine `accessToken: accessToken || null` alanı eklendi. `oturumGetir()`'e DOKUNULMUYOR — zaten tüm nesneyi `JSON.parse` ile okuyup `{user, expiry}`'yi destructure ediyor, yeni `accessToken` alanı orada sessizce mevcut olacak, kullanan olmadığı için hata vermez.)

- [ ] **Step 2: Grep ile doğrula**

```bash
grep -n "function oturumKaydet" auth-guard.js
```

Expected: `function oturumKaydet(user, accessToken) {` satırı görünmeli.

- [ ] **Step 3: Commit**

```bash
cd "C:\Users\USER\Projects\gurok-mal-kabul"
git add auth-guard.js
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: oturumKaydet artık opsiyonel accessToken parametresi alıyor"
```

---

### Task 2: `index.html` — `supabaseAuthKoprusu()` + `checkPin()` entegrasyonu

**Files:**
- Modify: `index.html:525-550`

**Interfaces:**
- Consumes: Task 1'in güncellediği `oturumKaydet(user, accessToken)` imzası. Global `SB_URL`/`SB_KEY`/`SB_HEADERS` (supabase-config.js). `user.id`, `user.auth_user_id`, `user.pin` (mevcut `kullanicilar` satırından `users` dizisine `...u` spread ile geliyor, `index.html:471-476`).
- Produces: (yok — bu, en son tüketici; Faz A2 ileride `accessToken`'ı okuyacak ama bu plan onu kapsamıyor)

**Önemli bulgu (bu görevin gerekçesi):** `checkPin()` şu an senkron bir fonksiyon — `supabaseAuthKoprusu()` `async` olduğu için `checkPin()`'in de `async` olması ve `await` ile çağırması gerekiyor. `checkPin()`'in çağrıldığı yerler (`pinInput()`'taki `setTimeout(checkPin, 200)` ve PIN pad butonlarının `onclick="checkPin()"` — bu ikinci çağrı noktası HTML'de, bu görevde değişmiyor çünkü `async` bir fonksiyonu senkronmuş gibi çağırmak JavaScript'te hata vermez, sadece dönen Promise'i görmezden gelir) hiçbir değişiklik gerektirmiyor — `async` fonksiyonu `await`siz çağırmak geçerlidir.

- [ ] **Step 1: `supabaseAuthKoprusu()` yardımcı fonksiyonunu ekle**

`index.html:525`'teki (`function checkPin() {` satırının hemen ÜSTÜNE), şu yeni fonksiyonu ekle:

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

- [ ] **Step 2: `checkPin()`'i async yap ve köprüyü çağır**

`index.html:525-550`'deki mevcut kod:

```js
function checkPin() {
  // Firebase'den yüklenen + DEFAULT_USERS her ikisine bak
  const tumKullanicilar = users.length > 0 ? users : DEFAULT_USERS;
  const user = tumKullanicilar.find(u => String(u.pin) === String(pinValue));
  if (!user) {
    pinBasarisizKaydet();
    const kalanSn=pinKilitliMi();
    const errEl = document.getElementById('pin-error');
    errEl.textContent = kalanSn>0?`🔒 Çok fazla hatalı deneme — ${kalanSn} sn kilitlendi`:'❌ Hatalı PIN';
    setTimeout(() => errEl.textContent = '', kalanSn>0?4000:2000);
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

Şununla değiştir:

```js
async function checkPin() {
  // Firebase'den yüklenen + DEFAULT_USERS her ikisine bak
  const tumKullanicilar = users.length > 0 ? users : DEFAULT_USERS;
  const user = tumKullanicilar.find(u => String(u.pin) === String(pinValue));
  if (!user) {
    pinBasarisizKaydet();
    const kalanSn=pinKilitliMi();
    const errEl = document.getElementById('pin-error');
    errEl.textContent = kalanSn>0?`🔒 Çok fazla hatalı deneme — ${kalanSn} sn kilitlendi`:'❌ Hatalı PIN';
    setTimeout(() => errEl.textContent = '', kalanSn>0?4000:2000);
    pinValue = '';
    updateDots();
    document.getElementById('pin-user-show').textContent = '';
    return;
  }
  pinBasariliTemizle();
  currentUser = user;
  const accessToken = await supabaseAuthKoprusu(user);
  oturumKaydet(user, accessToken);
  const params = new URLSearchParams(location.search);
  const returnTo = params.get('returnTo');
  if (returnTo && /^[a-z0-9_-]+\.html(\?[^#]*)?(#.*)?$/i.test(returnTo)) {
    location.replace(returnTo);
    return;
  }
  showPortal();
}
```

(İki değişiklik: fonksiyon `async` oldu; `oturumKaydet(user)` → `const accessToken = await supabaseAuthKoprusu(user); oturumKaydet(user, accessToken);`. Hata/kilitleme bloğu — `if (!user) {...}` — AYNEN korundu, dokunulmadı.)

- [ ] **Step 3: Grep ile doğrula**

```bash
grep -n "async function checkPin\|async function supabaseAuthKoprusu\|await supabaseAuthKoprusu" index.html
```

Expected: her üç satır da bulunmalı.

- [ ] **Step 4: Commit**

```bash
cd "C:\Users\USER\Projects\gurok-mal-kabul"
git add index.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: PIN girişi artık arka planda Supabase Auth hesabı açıp bağlıyor"
```

---

### Task 3: Uçtan uca doğrulama

**Files:** (yok — sadece doğrulama)

- [ ] **Step 1: Statik doğrulama**

Task 1 ve Task 2'nin grep adımlarının temiz geçtiğini teyit et. `checkPin()`'in `if (!user) {...}` (hatalı PIN) bloğunun DEĞİŞMEDİĞİNİ `git diff` ile doğrula — bu görev SADECE başarılı PIN yolunu etkilemeli.

- [ ] **Step 2: Controller'ın kendi curl doğrulaması**

Gerçek bir test kullanıcısıyla (örn. `auth_user_id` boş, gerçek bir PIN'i olan bir satır) `/auth/v1/signup` isteğini doğrudan curl ile tekrarla, dönen `access_token`'ın geçerli olduğunu ve `kullanicilar.auth_user_id`'nin gerçekten yazıldığını doğrula. Sonra AYNI kullanıcıyla `/auth/v1/token?grant_type=password` isteğini tekrarla, başarılı `200` döndüğünü doğrula (bu, signup sonrası signin yolunun da çalıştığını kanıtlar).

- [ ] **Step 3: Kullanıcıya manuel test adımlarını bildir**

Kullanıcının tarayıcıda doğrulaması gereken akış:
1. `index.html`'de normal PIN ile giriş yap → eskisi gibi (fark edilir bir gecikme olmadan) portala girmeli.
2. Supabase'de o kullanıcının `auth_user_id`'sinin dolduğunu kontrol et.
3. Çıkış yapıp AYNI kullanıcıyla tekrar PIN gir → yine eskisi gibi girmeli (bu sefer signup değil signin çağrılıyor, davranışta fark olmamalı).
4. Yanlış PIN dene → eskisi gibi "❌ Hatalı PIN" hatası almalı (bu görev bu yolu değiştirmedi, regresyon kontrolü).
5. Herhangi bir gecikme/hata/kırılma görülürse bildir.

- [ ] **Step 4: Kullanıcıdan onay al**

"Test ettim, çalışıyor" onayını bekle, ardından push kararını sor.
