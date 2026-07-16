# Teknik Borç — Ortak Kod Çıkarma (Pilot) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `sLD`/`hLD`/`toast`/`escapeHtml`/`round2`/`kModal`/`aModal` gibi
~20 dosyada birebir kopyalanmış yardımcı fonksiyonları ve XLSX yükleme
boilerplate'ini tek bir `ortak.js` dosyasında, ortak CSS paletini de
`theme.css`'te toplamak; 3 pilot dosyada (satin-alma.html,
depo-siparis.html, muhasebe-cariler.html) devreye alıp doğrulamak.

**Architecture:** `ortak.js`/`theme.css`, `auth-guard.js` gibi repo
kökünde, her pilot dosyanın `<head>`'inden senkron yüklenir. Sadece
byte-byte doğrulanmış identik kod taşınır — hiçbir davranış değişikliği
olmaz.

**Tech Stack:** Vanilla HTML/JS/CSS — build aracı yok.

---

## Global Constraints

- Sadece byte-byte doğrulanmış identik fonksiyonlar taşınır (spec) —
  `fmt()`, farklı-imzalı `toast()` varyantları, `auditLogYaz` bu işin
  dışında.
- `theme.css` sadece paylaşılan değişkenleri taşır; dosyaya özel ekstra
  değişkenler (`--accent` gibi) page-local `:root`'ta kalır (spec).
- `gurok_mal_kabul.html`/`index.html.html`'e dokunulmaz (spec).

---

### Task 1: `ortak.js` + `theme.css` oluştur

**Files:**
- Create: `ortak.js`
- Create: `theme.css`

- [ ] **Step 1: `ortak.js`**

```js
// ortak.js — Gürok ERP paylaşılan UI yardımcıları (sLD/hLD/toast/escapeHtml/
// round2/kModal/aModal) ve XLSX kütüphane yükleyici. Sayfalar bunu <head>
// içinde auth-guard.js'den SONRA, senkron olarak yükler.

function sLD(){document.getElementById('ld').classList.add('show');}
function hLD(){document.getElementById('ld').classList.remove('show');}
function toast(msg,d=2500){const t=document.getElementById('toast');t.textContent=msg;t.classList.add('show');setTimeout(()=>t.classList.remove('show'),d);}
function escapeHtml(s){return String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));}
function round2(n){return Math.round(((parseFloat(n)||0)+Number.EPSILON)*100)/100;}
function kModal(id){document.getElementById(id).classList.remove('open');}
function aModal(id){document.getElementById(id).classList.add('open');}

// 13 yerde tekrarlanan "XLSX yüklü değilse CDN'den yükle" bloğunun ortak hali.
async function loadXlsxLib(){
  if(typeof XLSX!=='undefined')return;
  await new Promise(r=>{
    const s=document.createElement('script');
    s.src='https://cdn.jsdelivr.net/npm/xlsx-js-style@1.2.0/dist/xlsx.bundle.js';
    s.onload=r;
    document.head.appendChild(s);
  });
}
```

- [ ] **Step 2: `theme.css`**

```css
:root{
  --primary:#1a2744;--primary-light:#2d4080;
  --success:#27ae60;--warning:#f39c12;--danger:#e74c3c;--info:#0284c7;
  --gray-100:#f1f3f5;--gray-200:#e9ecef;--gray-300:#dee2e6;--gray-400:#ced4da;
  --gray-500:#adb5bd;--gray-600:#6c757d;--gray-700:#495057;
  --radius:12px;--radius-sm:8px;--shadow:0 2px 12px rgba(0,0,0,0.1)
}
```

- [ ] **Step 3: Doğrula**

```bash
grep -n "function sLD\|function hLD\|function toast\|function escapeHtml\|function round2\|function kModal\|function aModal\|function loadXlsxLib" ortak.js
grep -n ":root" theme.css
```

- [ ] **Step 4: Commit**

```bash
git add ortak.js theme.css
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: add shared ortak.js/theme.css for duplicated UI helpers"
```

---

### Task 2: Pilot — `satin-alma.html`

**Files:**
- Modify: `satin-alma.html` — `<head>` (script/link ekle), `:root` bloğu
  (ortak değişkenleri sil, `--accent` kalsın), `function sLD/hLD/toast/
  escapeHtml/round2/kModal/aModal` tanımlarını sil, 5 yerdeki XLSX
  yükleme bloğunu `await loadXlsxLib()` ile değiştir.

- [ ] **Step 1: `<head>`'e ekle**

`<script src="auth-guard.js"></script>` satırının hemen altına:
```html
<script src="ortak.js"></script>
<link rel="stylesheet" href="theme.css">
```

- [ ] **Step 2: `:root` bloğundan ortak değişkenleri çıkar, `--accent` kalsın**

- [ ] **Step 3: 7 fonksiyon tanımını sil** (`ortak.js`'e taşındı)

- [ ] **Step 4: XLSX yükleme bloklarını `loadXlsxLib()` çağrısıyla değiştir**

- [ ] **Step 5: Doğrula**

```bash
grep -c "function sLD\|function hLD\|function toast\|function escapeHtml\|function round2\|function kModal\|function aModal" satin-alma.html
```
Expected: `0`.

- [ ] **Step 6: Tarayıcıda test et**

Gerçek kullanıcı ile login, İç Talepler + Teklifler sekmelerine geç, bir
toast tetikle, bir modal aç/kapa, Excel'e Aktar dene — konsolda hata
olmamalı.

- [ ] **Step 7: Commit**

```bash
git add satin-alma.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "refactor: satin-alma.html adopts shared ortak.js/theme.css"
```

---

### Task 3: Pilot — `depo-siparis.html`

Task 2 ile aynı adımlar (`escapeHtml`/`round2` bu dosyada hiç
kullanılmadığı için silinecek bir tanımları yok, sadece `sLD/hLD/toast/
kModal/aModal` silinir).

- [ ] **Step 1-6:** Task 2'nin aynısı, `depo-siparis.html` için.
- [ ] **Step 7: Commit**

```bash
git add depo-siparis.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "refactor: depo-siparis.html adopts shared ortak.js/theme.css"
```

---

### Task 4: Pilot — `muhasebe-cariler.html`

Task 2 ile aynı adımlar.

- [ ] **Step 1-6:** Task 2'nin aynısı, `muhasebe-cariler.html` için.
- [ ] **Step 7: Commit**

```bash
git add muhasebe-cariler.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "refactor: muhasebe-cariler.html adopts shared ortak.js/theme.css"
```

---

### Task 5: Rapor

**Files:** (yok — sadece doğrulama + rapor)

- [ ] **Step 1:** Kullanıcıya bulguları ve kalan ~26 dosya için rollout
  önerisini raporla; şüpheli ölü dosyaları (`gurok_mal_kabul.html`,
  `index.html.html`) tekrar hatırlat.
- [ ] **Step 2: Kullanıcıdan onay al, sonra push**

```bash
git fetch
git log --oneline main..origin/main
```
