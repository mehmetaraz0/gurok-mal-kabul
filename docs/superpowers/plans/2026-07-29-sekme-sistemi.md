# Uygulama İçi Sekme Sistemi Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `index.html`'e, tarayıcı sekmelerine benzeyen ama uygulamanın kendi çizdiği bir sekme çubuğu eklemek — Ana Sayfa sabit/kapatılamaz sekme, seçilen her modül `<iframe>` içinde yeni bir sekme olarak açılır, sekmeler arası geçişte hiçbiri sıfırlanmaz.

**Architecture:** `index.html` kabuğa dönüşür: mevcut hub içeriği (`.main-content`) "Ana Sayfa" sekmesinin sabit paneli olur, yeni açılan her modül `.tab-app-content` içine eklenen bir `<iframe>` paneli olur — sadece aktif panel görünür, diğerleri DOM'da kalır (`display:none`). `nav-drawer.js`, bir iframe içinde çalıştığını tespit edince kendi hamburger'ini enjekte etmez (kabuğun sekme çubuğu + "+" düğmesi aynı işi görür).

**Tech Stack:** Vanilla HTML/JS/CSS, mevcut `theme.css` renk tokenleri, ek kütüphane yok.

## Global Constraints

- 60 modül dosyasının hiçbiri değişmiyor (sadece `index.html` ve `nav-drawer.js`).
- Sekme durumu `sessionStorage`'a **yazılmıyor** — sayfa yenilenince sekmeler sıfırlanır, sadece Ana Sayfa ile başlanır (kullanıcı kararı).
- Aynı modül birden fazla kez açılabilir — her tıklama her zaman **yeni** bir sekme oluşturur, mevcut sekmeye atlanmaz.
- Ana Sayfa sekmesi kapatılamaz; diğer tüm sekmeler "×" ile kapatılabilir.
- En az bir kapatılabilir sekme açıkken sayfa yenileme/kapatma girişiminde tarayıcının kendi `beforeunload` onay diyaloğu tetiklenir (metin özelleştirilemez, sadece davranış).
- Bilinen sınırlama (v1 kapsamı, düzeltilmeyecek): bir modül sekmesinin kendi "eve dön" butonuna basılması sekmeyi kapatmaz, o sekmenin içeriğini değiştirir.
- Her task sonunda `git commit` (doğrudan `main`'e, bu depoda feature branch kullanılmıyor).

---

### Task 1: `index.html` — sekme çubuğu (CSS + HTML + JS)

**Files:**
- Modify: `index.html`

**Interfaces:**
- Produces: `SEKMELER` (dizi, `{id, ad, url, kapatilabilir}`), `AKTIF_SEKME` (string), `sekmeAc({ad,url})`, `sekmeSec(id)`, `sekmeKapat(id,evt)`, `GORUNUR_MODULLER` (dizi) — bu isim/imzalar Task 2 ve Task 3'ün doğrulama adımlarında referans alınır.

- [ ] **Step 1: CSS ekle**

`index.html`'in `<style>` bloğunda, `.main-content` kuralından hemen sonra (mevcut `@media (max-width: 899px) { .main-content { padding: 16px 16px 32px; } }` satırından sonra) ekle:

```css
.tab-bar-app { display: flex; align-items: center; background: var(--primary); border-bottom: 1px solid rgba(255,255,255,.1); flex: none; }
.tab-bar-scroll { display: flex; align-items: center; flex: 1; min-width: 0; overflow-x: auto; scrollbar-width: none; }
.tab-bar-scroll::-webkit-scrollbar { display: none; }
.tab-app-btn { display: flex; align-items: center; gap: 6px; padding: 0 14px; height: 38px; min-width: 120px; max-width: 200px; background: transparent; border: none; border-bottom: 2px solid transparent; color: rgba(255,255,255,.6); font-size: 12.5px; font-weight: 600; cursor: pointer; white-space: nowrap; flex: none; font-family: inherit; }
.tab-app-btn.active { color: #fff; border-bottom-color: var(--accent); background: rgba(255,255,255,.05); }
.tab-app-btn .tab-label { overflow: hidden; text-overflow: ellipsis; }
.tab-app-btn .tab-close { flex: none; opacity: .6; border-radius: 4px; padding: 3px; display: flex; }
.tab-app-btn .tab-close:hover { opacity: 1; background: rgba(255,255,255,.15); }
.tab-app-add { flex: none; width: 38px; height: 38px; display: flex; align-items: center; justify-content: center; background: transparent; border: none; color: rgba(255,255,255,.6); cursor: pointer; }
.tab-app-add:hover { color: #fff; background: rgba(255,255,255,.08); }
.tab-app-content { flex: 1; position: relative; overflow: hidden; }
.tab-app-frame { position: absolute; inset: 0; width: 100%; height: 100%; border: none; display: none; background: #fff; }
.tab-app-frame.active { display: block; }
```

- [ ] **Step 2: HTML yapısını değiştir**

Mevcut:
```html
  <div class="main">
    <div class="topbar">
      <div class="topbar-brand"><div class="brand-mark small"><img src="icon-mark.png" alt="Araz" style="width:75%;height:75%;object-fit:contain"></div><span>ARAZ</span></div>
      <div class="crumb">Uygulamalar <b>/ Ana Sayfa</b></div>
      <div class="topbar-user">
        <div class="user-info">
          <div class="user-name" id="header-user-name">—</div>
          <div class="user-rol" id="header-user-rol">—</div>
        </div>
        <div class="avatar" id="header-avatar">—</div>
        <button class="logout-btn" onclick="logout()" title="Çıkış"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" style="width:16px;height:16px"><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><path d="M16 17l5-5-5-5"/><path d="M21 12H9"/></svg></button>
      </div>
    </div>

    <div class="main-content">
      <div class="welcome-row">
        <div>
          <h2 id="welcome-text">Hoş geldiniz</h2>
          <p id="welcome-sub">Araz Turizm Grubu — Depo Operasyonları</p>
        </div>
        <div class="welcome-date" id="welcome-date"></div>
      </div>

      <div class="kpi-strip">
        <div class="kpi-card"><div class="kpi-label">Açık Talepler</div><div class="kpi-num" id="kpi-talep">—</div></div>
        <div class="kpi-card"><div class="kpi-label">Bekleyen Onay</div><div class="kpi-num" id="kpi-onay">—</div></div>
        <div class="kpi-card"><div class="kpi-label">SKT Uyarısı</div><div class="kpi-num warn" id="kpi-skt">—</div></div>
        <div class="kpi-card"><div class="kpi-label">Aktif Kullanıcı</div><div class="kpi-num" id="kpi-kullanici">—</div></div>
      </div>

      <div class="modules-title">Uygulamalar</div>
      <div class="modules-grid" id="modules-grid"><!-- JS ile doldurulur --></div>
    </div>
  </div>
```

Yeni (tab-bar-app + tab-app-content sarmalayıcısı eklendi, main-content artık `id="tab-panel-home"` ve `tab-app-frame active` sınıflarını da taşıyor, içeriği hiç değişmedi):
```html
  <div class="main">
    <div class="topbar">
      <div class="topbar-brand"><div class="brand-mark small"><img src="icon-mark.png" alt="Araz" style="width:75%;height:75%;object-fit:contain"></div><span>ARAZ</span></div>
      <div class="crumb">Uygulamalar <b>/ Ana Sayfa</b></div>
      <div class="topbar-user">
        <div class="user-info">
          <div class="user-name" id="header-user-name">—</div>
          <div class="user-rol" id="header-user-rol">—</div>
        </div>
        <div class="avatar" id="header-avatar">—</div>
        <button class="logout-btn" onclick="logout()" title="Çıkış"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" style="width:16px;height:16px"><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><path d="M16 17l5-5-5-5"/><path d="M21 12H9"/></svg></button>
      </div>
    </div>

    <div class="tab-bar-app">
      <div class="tab-bar-scroll" id="tab-bar-list"><!-- JS ile doldurulur: sadece sekme butonları --></div>
      <button class="tab-app-add" id="tab-app-add-btn" onclick="sekmeEklePaneliAc()" title="Yeni sekme"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" style="width:16px;height:16px"><path d="M12 5v14M5 12h14"/></svg></button>
    </div>

    <div class="tab-app-content" id="tab-app-content">
      <div class="main-content tab-app-frame active" id="tab-panel-home">
        <div class="welcome-row">
          <div>
            <h2 id="welcome-text">Hoş geldiniz</h2>
            <p id="welcome-sub">Araz Turizm Grubu — Depo Operasyonları</p>
          </div>
          <div class="welcome-date" id="welcome-date"></div>
        </div>

        <div class="kpi-strip">
          <div class="kpi-card"><div class="kpi-label">Açık Talepler</div><div class="kpi-num" id="kpi-talep">—</div></div>
          <div class="kpi-card"><div class="kpi-label">Bekleyen Onay</div><div class="kpi-num" id="kpi-onay">—</div></div>
          <div class="kpi-card"><div class="kpi-label">SKT Uyarısı</div><div class="kpi-num warn" id="kpi-skt">—</div></div>
          <div class="kpi-card"><div class="kpi-label">Aktif Kullanıcı</div><div class="kpi-num" id="kpi-kullanici">—</div></div>
        </div>

        <div class="modules-title">Uygulamalar</div>
        <div class="modules-grid" id="modules-grid"><!-- JS ile doldurulur --></div>
      </div>
    </div>
  </div>
```

- [ ] **Step 3: `showPortal()`'a `GORUNUR_MODULLER` ata**

Mevcut (`showPortal()` fonksiyonu içinde):
```js
  // Modülleri render et — gerçek yetki_matrisi'ne göre
  const yetkiHaritasi = await kullaniciYetkileriGetir();
  const izinliSeviyeler = ['goruntule','kayit','tam'];
  const gorunur = MODULLER.filter(m => m.moduller.some(kod => izinliSeviyeler.includes(yetkiHaritasi[kod])));
  renderSidebar(gorunur);
  renderModuleGrid(gorunur);

  loadKpiler();
```

Yeni:
```js
  // Modülleri render et — gerçek yetki_matrisi'ne göre
  const yetkiHaritasi = await kullaniciYetkileriGetir();
  const izinliSeviyeler = ['goruntule','kayit','tam'];
  const gorunur = MODULLER.filter(m => m.moduller.some(kod => izinliSeviyeler.includes(yetkiHaritasi[kod])));
  GORUNUR_MODULLER = gorunur;
  renderSidebar(gorunur);
  renderModuleGrid(gorunur);
  sekmeCubuguRenderEt();

  loadKpiler();
```

`GORUNUR_MODULLER` global değişkenini, dosyanın en üstündeki `let users = [...DEFAULT_USERS];` satırından hemen önce ekle:
```js
let GORUNUR_MODULLER = [];
let users = [...DEFAULT_USERS];
```

- [ ] **Step 4: `renderModuleGrid`/`renderSidebar`'ı sekme-açan hale getir**

Mevcut:
```js
function renderSidebar(list) {
  const nav = document.getElementById('sidebar-nav');
  nav.innerHTML = `<a class="sidebar-item active" href="index.html">${iconSvg('<path d="M3 11l9-7 9 7v9a1 1 0 01-1 1h-5v-6H9v6H4a1 1 0 01-1-1z"/>')}Ana Sayfa</a>` +
    list.map(m => {
      const aktif = m.durum === 'aktif';
      return aktif
        ? `<a class="sidebar-item" href="${m.url}">${iconSvg(m.svg)}${m.ad}</a>`
        : `<span class="sidebar-item disabled">${iconSvg(m.svg)}${m.ad}</span>`;
    }).join('');
}

function renderModuleGrid(list) {
  const grid = document.getElementById('modules-grid');
  grid.innerHTML = list.map(m => {
    const aktif = m.durum === 'aktif';
    const tag = aktif ? 'a' : 'div';
    const hrefAttr = aktif ? ` href="${m.url}"` : '';
    return `
      <${tag} class="module-card ${aktif ? 'available' : 'coming-soon'}"${hrefAttr}>
        <div class="module-icon">${iconSvg(m.svg)}</div>
        <div>
          <div class="module-name">${m.ad}</div>
          <div class="module-desc">${m.desc}</div>
          ${!aktif ? '<span class="module-soon-tag">Yakında</span>' : ''}
        </div>
      </${tag}>
    `;
  }).join('');
}
```

Yeni (`href` yerine `sekmeAc()`/`sekmeSec('home')` çağıran `onclick`; modül verisi statik/geliştirici-kontrollü olduğu için tırnak kaçışı gerekmiyor — `MODULLER` dizisindeki hiçbir `ad` değeri apostrof içermiyor):
```js
function renderSidebar(list) {
  const nav = document.getElementById('sidebar-nav');
  nav.innerHTML = `<a class="sidebar-item active" href="javascript:void(0)" onclick="sekmeSec('home')">${iconSvg('<path d="M3 11l9-7 9 7v9a1 1 0 01-1 1h-5v-6H9v6H4a1 1 0 01-1-1z"/>')}Ana Sayfa</a>` +
    list.map(m => {
      const aktif = m.durum === 'aktif';
      return aktif
        ? `<a class="sidebar-item" href="javascript:void(0)" onclick="sekmeAc({ad:'${m.ad}',url:'${m.url}'})">${iconSvg(m.svg)}${m.ad}</a>`
        : `<span class="sidebar-item disabled">${iconSvg(m.svg)}${m.ad}</span>`;
    }).join('');
}

function renderModuleGrid(list) {
  const grid = document.getElementById('modules-grid');
  grid.innerHTML = list.map(m => {
    const aktif = m.durum === 'aktif';
    const tag = aktif ? 'a' : 'div';
    const attrs = aktif ? ` href="javascript:void(0)" onclick="sekmeAc({ad:'${m.ad}',url:'${m.url}'})"` : '';
    return `
      <${tag} class="module-card ${aktif ? 'available' : 'coming-soon'}"${attrs}>
        <div class="module-icon">${iconSvg(m.svg)}</div>
        <div>
          <div class="module-name">${m.ad}</div>
          <div class="module-desc">${m.desc}</div>
          ${!aktif ? '<span class="module-soon-tag">Yakında</span>' : ''}
        </div>
      </${tag}>
    `;
  }).join('');
}
```

- [ ] **Step 5: Sekme yönetimi fonksiyonlarını ekle**

`renderModuleGrid` fonksiyonundan hemen sonra ekle:

```js
// ============================================================
// SEKME SİSTEMİ (uygulama içi, iframe tabanlı) — bkz.
// docs/superpowers/specs/2026-07-29-sekme-sistemi-design.md
// ============================================================
let SEKMELER = [{ id: 'home', ad: 'Ana Sayfa', url: null, kapatilabilir: false }];
let AKTIF_SEKME = 'home';

function sekmeAc(modul) {
  const id = 'tab-' + Date.now() + '-' + Math.floor(Math.random() * 1000);
  SEKMELER.push({ id, ad: modul.ad, url: modul.url, kapatilabilir: true });
  const frame = document.createElement('iframe');
  frame.className = 'tab-app-frame';
  frame.src = modul.url;
  frame.dataset.tabId = id;
  document.getElementById('tab-app-content').appendChild(frame);
  sekmeSec(id);
}

function sekmeSec(id) {
  AKTIF_SEKME = id;
  document.getElementById('tab-panel-home').classList.toggle('active', id === 'home');
  document.querySelectorAll('.tab-app-frame[data-tab-id]').forEach(el => {
    el.classList.toggle('active', el.dataset.tabId === id);
  });
  sekmeCubuguRenderEt();
}

function sekmeKapat(id, evt) {
  if (evt) evt.stopPropagation();
  const idx = SEKMELER.findIndex(s => s.id === id);
  if (idx < 0 || !SEKMELER[idx].kapatilabilir) return;
  SEKMELER.splice(idx, 1);
  const frame = document.querySelector('.tab-app-frame[data-tab-id="' + id + '"]');
  if (frame) frame.remove();
  if (AKTIF_SEKME === id) {
    sekmeSec(SEKMELER[Math.max(0, idx - 1)].id);
  } else {
    sekmeCubuguRenderEt();
  }
}

function sekmeCubuguRenderEt() {
  // Sadece kaydırılabilir sekme listesini yazar — "+" düğmesi statik HTML'de,
  // kaydırma alanının dışında sabit kalır (tasarım gereği).
  const el = document.getElementById('tab-bar-list');
  el.innerHTML = SEKMELER.map(s => `
    <button class="tab-app-btn${s.id === AKTIF_SEKME ? ' active' : ''}" onclick="sekmeSec('${s.id}')">
      <span class="tab-label">${escapeHtmlSekme(s.ad)}</span>
      ${s.kapatilabilir ? `<span class="tab-close" onclick="sekmeKapat('${s.id}',event)"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" style="width:12px;height:12px"><path d="M18 6 6 18M6 6l12 12"/></svg></span>` : ''}
    </button>
  `).join('');
}

function escapeHtmlSekme(s) {
  return String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

function sekmeEklePaneliAc() {
  const eski = document.getElementById('sekme-ekle-panel');
  if (eski) { eski.remove(); return; }
  const panel = document.createElement('div');
  panel.id = 'sekme-ekle-panel';
  panel.style.cssText = 'position:fixed;top:96px;right:20px;background:#fff;border-radius:10px;box-shadow:0 8px 30px rgba(0,0,0,.25);padding:8px;z-index:500;min-width:220px;max-height:70vh;overflow-y:auto';
  const aktifModuller = GORUNUR_MODULLER.filter(m => m.durum === 'aktif');
  panel.innerHTML = aktifModuller.length
    ? aktifModuller.map(m => `
        <div onclick="sekmeAc({ad:'${m.ad}',url:'${m.url}'});document.getElementById('sekme-ekle-panel').remove();"
             style="display:flex;align-items:center;gap:10px;padding:9px 10px;border-radius:6px;cursor:pointer;font-size:13px;color:var(--primary)"
             onmouseover="this.style.background='var(--gray-100)'" onmouseout="this.style.background='transparent'">
          ${iconSvg(m.svg)}${m.ad}
        </div>`).join('')
    : '<div style="padding:12px;font-size:12.5px;color:var(--gray-500)">Açılabilecek modül yok</div>';
  document.body.appendChild(panel);
  setTimeout(() => document.addEventListener('click', function disKapat(e) {
    if (!panel.contains(e.target) && !e.target.closest('#tab-app-add-btn')) {
      panel.remove();
      document.removeEventListener('click', disKapat);
    }
  }), 0);
}

window.addEventListener('beforeunload', e => {
  if (SEKMELER.some(s => s.kapatilabilir)) { e.preventDefault(); e.returnValue = ''; }
});
```

- [ ] **Step 6: Tarayıcıda doğrula**

`preview_start` ile statik sunucuyu aç, `sessionStorage`'a fabrik bir `araz_portal_session` (`rol:'yonetici'`) yaz, `/index.html`'e git (veya `document.getElementById('screen-login').classList.add('hidden'); document.getElementById('screen-portal').classList.add('active');` ile doğrudan portalı göster). Kontrol listesi:
- Sekme çubuğunda tek "Ana Sayfa" sekmesi + sağda "+" düğmesi görünüyor, Ana Sayfa'da "×" yok.
- Bir modül kartına (örn. Stok Takip) tıkla — yeni bir sekme açılıyor, o modülün içeriği iframe içinde yükleniyor, konsolda hata yok.
- Aynı modüle tekrar tıkla — ikinci bir sekme daha açılıyor (aynı isimli iki sekme).
- Sekmeler arasında tıklayarak geçiş yap — her ikisi de doğru içeriği gösteriyor.
- Bir modül sekmesini "×" ile kapat — sekme kayboluyor, iframe DOM'dan siliniyor (bir sonraki task'ta bunun bellek/durum sızdırmadığını doğrulamaya gerek yok, basit kaldırma yeterli).
- "+" düğmesine tıkla, panel açılıyor; panel dışına tıklayınca kapanıyor.
- En az bir modül sekmesi açıkken sayfayı yenilemeye çalış (F5) — tarayıcının onay diyaloğu çıkıyor (iptal et, testi bozma). Sadece Ana Sayfa açıkken F5'in sorunsuz çalıştığını da doğrula.

- [ ] **Step 7: Commit**

```bash
git add index.html
git commit -m "feat: index.html'e uygulama içi iframe tabanlı sekme sistemi eklendi"
```

---

### Task 2: `nav-drawer.js` — iframe tespiti

**Files:**
- Modify: `nav-drawer.js`

**Interfaces:**
- Consumes: yok (bağımsız bir kontrol satırı).

- [ ] **Step 1: `ndKur()`'un başına iframe kontrolü ekle**

Mevcut:
```js
async function ndKur() {
  if (document.getElementById('nd-drawer')) return; // zaten kurulu
  const header = document.querySelector('.header');
  if (!header) return;
```

Yeni:
```js
async function ndKur() {
  if (document.getElementById('nd-drawer')) return; // zaten kurulu
  if (window.self !== window.top) return; // bir sekme (iframe) içinde çalışıyor — kabuğun kendi sekme çubuğu bu işi görüyor
  const header = document.querySelector('.header');
  if (!header) return;
```

- [ ] **Step 2: Tarayıcıda doğrula**

Task 1'in Step 6'sındaki gibi bir sekme aç (örn. Stok Takip). Açılan iframe içindeki sayfada hamburger düğmesinin **görünmediğini** doğrula — çünkü `stok-takip.html` artık `window.top !== window.self` durumunda. Ardından `stok-takip.html`'i **doğrudan** (kabuk olmadan, örn. `/stok-takip.html` adresine gidip) aç — bu sefer hamburger'in **eskisi gibi göründüğünü** doğrula (regresyon kontrolü — bağımsız açılan sayfalarda davranış değişmemeli).

- [ ] **Step 3: Commit**

```bash
git add nav-drawer.js
git commit -m "feat: nav-drawer.js iframe (sekme) içinde çalışırken kendi hamburger'ini enjekte etmiyor"
```

---

### Task 3: Uçtan uca doğrulama + Obsidian güncelleme

**Files:**
- Modify: `D:\ERP-Bilgi-Haritasi\01-Mimari\Genel-Bakis.md`
- Modify: `D:\ERP-Bilgi-Haritasi\01-Mimari\Gelisim-Gecmisi.md`

**Interfaces:**
- Consumes: yok (sadece doğrulama + dokümantasyon).

- [ ] **Step 1: Tam uçtan uca manuel test**

1. `index.html`'i aç (fabrik oturumla), 3 farklı modülü sekme olarak aç (örn. Stok Takip, Muhasebe, Depo Siparişleri).
2. Stok Takip sekmesinde arama kutusuna bir şey yaz, Muhasebe sekmesine geç, Stok Takip'e geri dön — yazdığının hâlâ durduğunu doğrula.
3. Sidebar'daki "Ana Sayfa" linkine tıkla — Ana Sayfa sekmesine geçtiğini, diğer açık sekmelerin kapanmadığını doğrula.
4. Bir sekmeyi kapat, kalan sekmelerin doğru sırada göründüğünü doğrula.
5. Konsolda hiçbir JS hatası olmadığını doğrula (`read_console_messages`, `onlyErrors:true`).
6. `stok-takip.html`'i bağımsız (kabuksuz) açıp hamburger menüsünün hâlâ çalıştığını doğrula (Task 2'nin regresyon kontrolü).

- [ ] **Step 2: Obsidian vault güncelle**

`D:\ERP-Bilgi-Haritasi\01-Mimari\Genel-Bakis.md`'ye, "İlk paylaşılan UI-chrome bileşeni: nav-drawer.js" bölümünden sonra yeni bir bölüm ekle:
```
## Uygulama içi sekme sistemi (2026-07-29)
`index.html` artık bir "kabuk": mevcut hub içeriği sabit/kapatılamaz "Ana Sayfa"
sekmesi oluyor, seçilen her modül `<iframe>` içinde yeni bir sekme olarak açılıyor
(tarayıcı sekmelerine benzer, ama uygulamanın kendi çizdiği bir UI). `nav-drawer.js`
bir iframe içinde çalıştığını (`window.self !== window.top`) tespit edince kendi
hamburger'ini enjekte etmiyor — kabuğun sekme çubuğu + "+" düğmesi aynı işi görüyor.
60 modül dosyasının hiçbiri değişmedi. Sekme durumu `sessionStorage`'a yazılmıyor
(sayfa yenilenince sıfırlanır) — en az bir modül sekmesi açıkken sayfa yenileme/kapatma
girişiminde tarayıcının kendi `beforeunload` onay diyaloğu tetiklenir. Detay:
`docs/superpowers/specs/2026-07-29-sekme-sistemi-design.md`.
```

`D:\ERP-Bilgi-Haritasi\01-Mimari\Gelisim-Gecmisi.md`'ye yeni bir madde ekle (başlıktaki tarih aralığını da `2026-07-29`'a güncelle):
```
- **07-29** — Uygulama içi sekme sistemi: `index.html` iframe tabanlı bir sekme
  kabuğuna dönüştürüldü (Ana Sayfa sabit sekme, modüller `<iframe>` sekmesi olarak
  açılıyor), `nav-drawer.js` iframe içinde kendi hamburger'ini artık enjekte etmiyor.
```

- [ ] **Step 3: Commit**

```bash
cd D:\ERP-Bilgi-Haritasi
git add 01-Mimari/Genel-Bakis.md 01-Mimari/Gelisim-Gecmisi.md
git commit -m "docs: uygulama içi sekme sistemini belgeledi"
cd D:\erp
```

(Not: `D:\ERP-Bilgi-Haritasi` ve `D:\erp` ayrı git repoları — iki ayrı commit gerekir, `D:\erp` tarafında bu task için ek bir commit yok çünkü Task 1/2 zaten kod değişikliklerini commit'ledi.)
