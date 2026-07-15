# Hibrit Giriş Mimarisi Faz 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** İleride Azure AD/Microsoft 365 SSO entegrasyonuna hazırlık olarak `kullanicilar` tablosuna `eposta` kolonu eklemek, `index.html`'in PIN giriş ekranına pasif bir "Microsoft ile Giriş" butonu koymak, ve henüz çağrılmayan bir `findUserByEmail()` yardımcı fonksiyonu eklemek.

**Architecture:** Tek dosya değişikliği (`index.html`) + bir Supabase SQL adımı. Session/login mimarisi zaten merkezi (`auth-guard.js`, `gurok_portal_session`) — bu plan ona dokunmuyor, sadece `index.html`'in mevcut PIN ekranına ek yapıyor.

**Tech Stack:** Vanilla JS, Supabase Postgres (SQL migration, kullanıcı tarafından Supabase SQL editöründe çalıştırılır). Build aracı yok, test çerçevesi yok (Node/Python bu ortamda mevcut değil) — doğrulama grep + manuel kod okuma + kullanıcının tarayıcıda elle test etmesiyle yapılır.

## Global Constraints

- `eposta` kolonu nullable ve unique — zorunlu değil, bir kullanıcının hem `pin` hem `eposta` dolu olabilir.
- "Microsoft ile Giriş" butonu SADECE `index.html`'e eklenir (tek gerçek PIN giriş ekranı burası — `mal-kabul-v2.html`/`depo-siparis.html`/`gunluk-tuketim.html`'in kendi login ekranı yok, hiçbiri bu planda değişmiyor).
- Buton pasif/placeholder: tıklanınca `showToast('🔷 Microsoft girişi yakında aktif olacak')` gösterir, gerçek OAuth/Azure bağlantısı YOK.
- `findUserByEmail(email)` eklenir ama hiçbir yerden çağrılmaz (Azure entegrasyonu geldiğinde kullanılacak, şimdilik dead code olması beklenen/kabul edilen bir durum).
- Session anahtarı (`gurok_portal_session`) veya `requireLogin()`/`requireRole()` mekanizmasına DOKUNULMAZ.
- PIN girişi mevcut haliyle çalışmaya devam etmeli — regresyon yok.

---

### Task 1: Supabase şema değişikliği

**Files:** (yok — sadece SQL, kullanıcı tarafından Supabase SQL editöründe çalıştırılır)

- [ ] **Step 1: Kullanıcıya SQL'i ver**

Kullanıcıya şu SQL'i Supabase SQL editöründe çalıştırması için ver:

```sql
alter table kullanicilar add column if not exists eposta text unique;
```

- [ ] **Step 2: Kullanıcıdan onay al**

Kullanıcının "Çalıştı" (veya benzeri) onayını bekle. Onay gelmeden Task 2'ye geçme.

---

### Task 2: "Microsoft ile Giriş" butonu + `findUserByEmail()`

**Files:**
- Modify: `index.html:82` civarı (CSS — `.btn-ms` eklenir), `index.html:283-287` civarı (HTML — buton eklenir), `index.html:478` civarı (JS — `loadUsers()`'ın hemen altına `findUserByEmail` eklenir)

**Interfaces:**
- Consumes: mevcut `showToast(msg, dur=2500)` (satır 607), mevcut modül-seviyesi `users` dizisi (satır 460: `let users = [...DEFAULT_USERS];`, `loadUsers()` tarafından doldurulur).
- Produces: `function findUserByEmail(email)` — başka hiçbir task/dosya bu fonksiyonu şu an tüketmiyor (kasıtlı olarak dead code, Azure entegrasyonu geldiğinde kullanılacak).

- [ ] **Step 1: `.btn-ms` CSS kuralını ekle**

`index.html`'de satır 82'deki şu satırı:

```css
.pin-btn.del { font-size: 18px; }
```

şununla değiştir (mevcut satırı koru, hemen altına ekle):

```css
.pin-btn.del { font-size: 18px; }
.btn-ms{width:100%;margin-top:14px;padding:12px;border:1.5px solid var(--primary);border-radius:12px;background:white;color:var(--primary);font-size:14px;font-weight:600;cursor:pointer}
.btn-ms:active{background:var(--gray-100)}
```

- [ ] **Step 2: Butonu PIN pad'in altına ekle**

`index.html`'de şu bloğu (PIN pad'in kapanışı):

```html
      <button class="pin-btn" onclick="pinInput('0')">0</button>
      <button class="pin-btn del" onclick="pinDelete()">⌫</button>
    </div>
  </div>
</div>
```

şununla değiştir:

```html
      <button class="pin-btn" onclick="pinInput('0')">0</button>
      <button class="pin-btn del" onclick="pinDelete()">⌫</button>
    </div>
    <button class="btn-ms" onclick="showToast('🔷 Microsoft girişi yakında aktif olacak')">🔷 Microsoft ile Giriş</button>
  </div>
</div>
```

- [ ] **Step 3: `findUserByEmail` fonksiyonunu ekle**

`index.html`'de satır 478'deki `loadUsers()` fonksiyonunun kapanışından (`}`) hemen sonra, `// ============================================================\n// PIN` yorumundan ÖNCE şunu ekle:

```js
function findUserByEmail(email) {
  return users.find(u => u.eposta && u.eposta.toLowerCase() === String(email).toLowerCase()) || null;
}
```

- [ ] **Step 4: Doğrulama**

Bu dosyada test çerçevesi yok. Doğrulama için:

```bash
grep -n "class=\"btn-ms\"\|function findUserByEmail\|Microsoft girişi yakında" index.html
```

Expected: 3 eşleşme (CSS sınıf tanımı değil — HTML'deki `class="btn-ms"` kullanımı, `findUserByEmail` fonksiyon tanımı, toast mesajı — not: `.btn-ms{` CSS satırı bu pattern'e uymayabilir, sadece HTML/JS kullanım noktalarını sayıyoruz).

- [ ] **Step 5: Commit**

```bash
git add index.html
git commit -m "feat: add Microsoft SSO placeholder button and findUserByEmail helper (hibrit giriş faz 1)"
```

---

### Task 3: Uçtan uca doğrulama

**Files:** (yok — sadece doğrulama)

- [ ] **Step 1: Tutarlılık kontrolü**

```bash
grep -n "class=\"btn-ms\"\|\.btn-ms{\|function findUserByEmail" index.html
```
Expected: 3 eşleşme (HTML kullanımı, CSS tanımı, JS fonksiyon tanımı) — hepsi `index.html` içinde.

- [ ] **Step 2: Kullanıcıya manuel test adımlarını bildir**

Kullanıcının tarayıcıda doğrulaması gereken akış (Node/Python bu ortamda yok, otomatik test yazılamıyor):
1. `index.html`'i aç → PIN pad'in altında "🔷 Microsoft ile Giriş" butonunun göründüğünü doğrula.
2. Butona tıkla → "🔷 Microsoft girişi yakında aktif olacak" toast'ının çıktığını, hata vermediğini doğrula.
3. Normal PIN ile giriş yap → hâlâ eskisi gibi çalıştığını (regresyon yok) doğrula.
4. Supabase'de `kullanicilar` tablosunda `eposta` kolonunun göründüğünü doğrula.

- [ ] **Step 3: Kullanıcıdan onay al, sonra push**

```bash
git fetch
git log --oneline main..origin/main
```
Expected: paralel oturumdan gelen değişiklik var mı kontrol et, varsa kullanıcıya bildir. Yoksa kullanıcı onayıyla `git push`.
