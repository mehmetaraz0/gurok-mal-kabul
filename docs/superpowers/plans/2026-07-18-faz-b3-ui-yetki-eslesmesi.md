# Faz B3 UI Yetki Eşlemesi Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Portal menüsünü ve bir pilot sayfanın (`muhasebe-cariler.html`) butonlarını, Faz B0-B2'de kurulan gerçek `yetki_matrisi` verisiyle eşleştirmek — eski, ayrı `rol` metin tabanlı filtreyi kaldırıp yerine `rol_id` → `yetki_matrisi` zincirini koymak.

**Architecture:** `auth-guard.js`'e paylaşılan bir `kullaniciYetkileriGetir()` fonksiyonu eklenir — giriş yapmış kullanıcının TÜM modül yetkilerini tek sorguda `{modul_kod: seviye}` haritası olarak döner. `index.html`'in portal menüsü bu haritayı kullanacak şekilde güncellenir (`MODULLER` dizisine `moduller:[...]` alanı eklenir, eski `roller:[...]` kaldırılır). `muhasebe-cariler.html` aynı haritayı kullanarak Kaydet/Sil butonlarını gösterir/gizler.

**Tech Stack:** Vanilla JS, raw `fetch()`. Build aracı/test çerçevesi yok — doğrulama grep + manuel kod okuma + kullanıcının tarayıcıda uçtan uca testi.

## Global Constraints

- `kullaniciYetkileriGetir()` her hata durumunda (`fetch` başarısız, `rol_id` yok, ağ hatası) boş nesne `{}` döner — asla exception fırlatmaz, asla "her şeyi göster" yönünde hataya düşmez (en güvenli varsayım: gösterme).
- Portal kutucuğu görünürlük kuralı: `m.moduller` listesindeki kod'lardan HERHANGİ birinde `goruntule`/`kayit`/`tam` varsa göster.
- `muhasebe-cariler.html`'de buton aktiflik kuralı: `cari_hesaplar` seviyesi `kayit` veya `tam` ise aktif, `goruntule`/`yok`/eksik ise pasif/gizli.
- Eski `roller:[...]` alanı ve `rol` bazlı filtre `index.html`'den TAMAMEN kaldırılır (kısmi geçiş yok — spec'te kullanıcı onayıyla netleşti).
- Bu plan SADECE `auth-guard.js`, `index.html`, `muhasebe-cariler.html` dosyalarını değiştirir. Şema değişikliği yok.

---

### Task 1: `auth-guard.js` — `kullaniciYetkileriGetir()` fonksiyonu

**Files:**
- Modify: `auth-guard.js:34-36` (`oturumAccessTokenGetir`'in hemen altına ekleme)

**Interfaces:**
- Consumes: `oturumGetir()` (aynı dosyada, mevcut), global `SB_URL`/`SB_HEADERS` (supabase-config.js'den, bu dosyadan SONRA yüklenir — fonksiyon TANIMLANIRKEN değil ÇAĞRILIRKEN bu değerlere ihtiyaç duyar, bu yüzden sorun yok).
- Produces: `kullaniciYetkileriGetir()` — `async`, `{modul_kod: yetki_seviye}` şeklinde bir nesne döner. Task 2 ve Task 3 bunu çağıracak.

- [ ] **Step 1: Yeni fonksiyonu ekle**

`auth-guard.js:26-36`'daki mevcut kod:

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

// index.html DIŞINDAKİ sayfalar bunu çağırır. Oturum geçerliyse kullanıcıyı döner.
```

Şununla değiştir:

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

// Sayfa yüklenirken bir kez çağrılır. Giriş yapmış kullanıcının rol_id'sine
// ait TÜM yetki_matrisi satırlarını tek sorguda çekip {modul_kod: yetki_seviye}
// haritası döner. Hata/eksik veri durumunda boş nesne döner (en güvenli
// varsayım — hiçbir modülde yetki yokmuş gibi davran).
async function kullaniciYetkileriGetir() {
  const user = oturumGetir();
  if (!user || !user.rol_id) return {};
  try {
    const r = await fetch(SB_URL + '/rest/v1/yetki_matrisi?select=yetki,moduller(kod)&rol_id=eq.' + user.rol_id, { headers: SB_HEADERS });
    if (!r.ok) return {};
    const rows = await r.json();
    const harita = {};
    rows.forEach(row => { if (row.moduller) harita[row.moduller.kod] = row.yetki; });
    return harita;
  } catch (e) { return {}; }
}

// index.html DIŞINDAKİ sayfalar bunu çağırır. Oturum geçerliyse kullanıcıyı döner.
```

(Tek değişiklik: `oturumAccessTokenGetir` ile bir sonraki yorumun arasına yeni fonksiyon eklendi.)

- [ ] **Step 2: Grep ile doğrula**

```bash
grep -n "function kullaniciYetkileriGetir" auth-guard.js
```

Expected: `async function kullaniciYetkileriGetir() {` satırı görünmeli.

- [ ] **Step 3: Commit**

```bash
cd "C:\Users\USER\Projects\gurok-mal-kabul"
git add auth-guard.js
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: auth-guard.js'e kullaniciYetkileriGetir() ekle"
```

---

### Task 2: `index.html` — Portal menüsünü gerçek yetkiye bağla

**Files:**
- Modify: `index.html:343-444` (`MODULLER` dizisi)
- Modify: `index.html:588-628` (`showPortal`, `renderModuller`)
- Modify: `index.html:656-667` (init IIFE)
- Modify: `checkPin()` içindeki `showPortal();` çağrısı (satır numarası Task ile birlikte aşağıda verilecek — dosyada `showPortal();` metnini ara)

**Interfaces:**
- Consumes: Task 1'in `kullaniciYetkileriGetir()` fonksiyonu.
- Produces: (yok — bu, en son tüketici bu dosyada)

- [ ] **Step 1: `MODULLER` dizisini güncelle**

`index.html:343-444`'teki mevcut kod:

```js
const MODULLER = [
  {
    id: 'malkabul',
    ad: 'Mal Kabul',
    desc: 'Teslimat girişi, onay, SKT takip',
    ikon: '📋',
    renk: 'icon-blue',
    url: 'mal-kabul-v2.html',
    roller: ['yonetici','depo'],
    durum: 'aktif'
  },
  {
    id: 'stok',
    ad: 'Stok Takip',
    desc: 'Anlık stok, giriş/çıkış',
    ikon: '📦',
    renk: 'icon-green',
    url: 'stok-takip.html',
    roller: ['yonetici','depo'],
    durum: 'aktif'
  },
  {
    id: 'depo-siparis',
    ad: 'Depo Siparişleri',
    desc: 'Mutfak & departman talepleri',
    ikon: '📤',
    renk: 'icon-orange',
    url: 'depo-siparis.html',
    roller: ['yonetici','depo','mutfak','bar'],
    durum: 'aktif'
  },
  {
    id: 'satinalma',
    ad: 'Satın Alma',
    desc: 'Sipariş takip, LN Infor',
    ikon: '🛒',
    renk: 'icon-purple',
    url: 'satin-alma.html',
    roller: ['yonetici','satinalma','depo','cost_control'],
    durum: 'aktif'
  },
  {
    id: 'raporlar',
    ad: 'Raporlar',
    desc: 'Analiz, izleme, uygunsuzluk',
    ikon: '📊',
    renk: 'icon-yellow',
    url: 'mal-kabul-v2.html#izleme',
    roller: ['yonetici','satinalma','kalite'],
    durum: 'aktif'
  },
  {
    id: 'yonetim',
    ad: 'Yönetim',
    desc: 'Kullanıcılar, ayarlar, yedek',
    ikon: '⚙️',
    renk: 'icon-gray',
    url: 'kullanici-yonetimi.html',
    roller: ['yonetici'],
    durum: 'aktif'
  },
  {
    id: 'muhasebe',
    ad: 'Muhasebe',
    desc: 'Cari, fatura, hesap planı',
    ikon: '💰',
    renk: 'icon-green',
    url: 'muhasebe.html',
    roller: ['yonetici','satinalma','muhasebe_muduru','muhasebe_calisani','cost_control'],
    durum: 'aktif'
  },
  {
    id: 'bar',
    ad: 'F&B Bar',
    desc: 'Müşteri kart, sipariş takip',
    ikon: '🍹',
    renk: 'icon-red',
    url: 'bar.html',
    roller: ['yonetici'],
    durum: 'yapiyor'
  },
  {
    id: 'gunlukTuketim',
    ad: 'Günlük Tüketim',
    desc: 'Bar/Mutfak günlük malzeme tüketimi',
    ikon: '📉',
    renk: 'icon-orange',
    url: 'gunluk-tuketim.html',
    roller: ['mutfak', 'bar', 'yonetici'],
    durum: 'aktif'
  },
  {
    id: 'trendler',
    ad: 'Trendler',
    desc: 'Stok, tüketim ve food-cost eğilimleri',
    ikon: '📈',
    renk: 'icon-teal',
    url: 'trend-raporlama.html',
    roller: ['yonetici', 'depo', 'cost_control'],
    durum: 'aktif'
  }
];
```

Şununla değiştir:

```js
const MODULLER = [
  {
    id: 'malkabul',
    ad: 'Mal Kabul',
    desc: 'Teslimat girişi, onay, SKT takip',
    ikon: '📋',
    renk: 'icon-blue',
    url: 'mal-kabul-v2.html',
    moduller: ['mal_kabul_form','mal_kabul_kalite'],
    durum: 'aktif'
  },
  {
    id: 'stok',
    ad: 'Stok Takip',
    desc: 'Anlık stok, giriş/çıkış',
    ikon: '📦',
    renk: 'icon-green',
    url: 'stok-takip.html',
    moduller: ['stok_takip'],
    durum: 'aktif'
  },
  {
    id: 'depo-siparis',
    ad: 'Depo Siparişleri',
    desc: 'Mutfak & departman talepleri',
    ikon: '📤',
    renk: 'icon-orange',
    url: 'depo-siparis.html',
    moduller: ['depo_siparis'],
    durum: 'aktif'
  },
  {
    id: 'satinalma',
    ad: 'Satın Alma',
    desc: 'Sipariş takip, LN Infor',
    ikon: '🛒',
    renk: 'icon-purple',
    url: 'satin-alma.html',
    moduller: ['ic_talep','siparis_olustur','siparis_takip','fiyat_kontrol','tedarikci_skorkart','firma_yonetimi'],
    durum: 'aktif'
  },
  {
    id: 'raporlar',
    ad: 'Raporlar',
    desc: 'Analiz, izleme, uygunsuzluk',
    ikon: '📊',
    renk: 'icon-yellow',
    url: 'mal-kabul-v2.html#izleme',
    moduller: ['mal_kabul_kalite'],
    durum: 'aktif'
  },
  {
    id: 'yonetim',
    ad: 'Yönetim',
    desc: 'Kullanıcılar, ayarlar, yedek',
    ikon: '⚙️',
    renk: 'icon-gray',
    url: 'kullanici-yonetimi.html',
    moduller: ['kullanici_yonetimi'],
    durum: 'aktif'
  },
  {
    id: 'muhasebe',
    ad: 'Muhasebe',
    desc: 'Cari, fatura, hesap planı',
    ikon: '💰',
    renk: 'icon-green',
    url: 'muhasebe.html',
    moduller: ['hesap_plani','cari_hesaplar','fatura_giris','fatura_onay','odeme_yapma','uc_yollu_eslestirme','yevmiye_fis_giris','yevmiye_fis_onay','banka_kasa','doviz_manuel','mizan_raporlar','denetim_izi','donem_kilitleme','demirbas_yonetimi','cek_senet_yonetimi','butce_yonetimi','sene_sonu_kapama','e_fatura','e_defter','muhasebe_asistan'],
    durum: 'aktif'
  },
  {
    id: 'bar',
    ad: 'F&B Bar',
    desc: 'Müşteri kart, sipariş takip',
    ikon: '🍹',
    renk: 'icon-red',
    url: 'bar.html',
    moduller: ['bar_qr_siparis'],
    durum: 'yapiyor'
  },
  {
    id: 'gunlukTuketim',
    ad: 'Günlük Tüketim',
    desc: 'Bar/Mutfak günlük malzeme tüketimi',
    ikon: '📉',
    renk: 'icon-orange',
    url: 'gunluk-tuketim.html',
    moduller: ['gunluk_tuketim'],
    durum: 'aktif'
  },
  {
    id: 'trendler',
    ad: 'Trendler',
    desc: 'Stok, tüketim ve food-cost eğilimleri',
    ikon: '📈',
    renk: 'icon-teal',
    url: 'trend-raporlama.html',
    moduller: ['trend_raporlama'],
    durum: 'aktif'
  }
];
```

(Tek değişiklik türü: her girdide `roller: [...]` → `moduller: [...]` — değerler `moduller` tablosundaki gerçek `kod`'lardan alındı.)

- [ ] **Step 2: `renderModuller` ve `showPortal`'ı güncelle**

`index.html:588-628`'deki mevcut kod:

```js
function showPortal() {
  const u = currentUser;
  document.getElementById('screen-login').classList.add('hidden');
  document.getElementById('screen-portal').classList.add('active');

  // Header
  document.getElementById('header-user-name').textContent = u.ad;
  document.getElementById('header-user-rol').textContent = (ROL_IKON[u.rol]||'👤') + ' ' + (ROL_AD[u.rol]||u.rol);

  // Hoşgeldin
  document.getElementById('welcome-text').textContent = 'Hoş geldin, ' + u.ad.split(' ')[0];
  document.getElementById('welcome-sub').textContent = ROL_AD[u.rol] + ' • ' + (u.departman||'');

  // Tarih
  const now = new Date();
  document.getElementById('welcome-date').textContent =
    now.toLocaleDateString('tr-TR', { weekday:'long', day:'numeric', month:'long', year:'numeric' });

  // Modülleri render et
  renderModuller(u.rol);
}

function renderModuller(rol) {
  const grid = document.getElementById('modules-grid');
  const gorunur = MODULLER.filter(m => m.roller.includes(rol));

  grid.innerHTML = gorunur.map(m => {
    const aktif = m.durum === 'aktif';
    return `
      <div class="module-card ${aktif ? 'available' : 'coming-soon'}"
        onclick="${aktif ? `gotoModule('${m.url}')` : 'void(0)'}">
        <div class="module-icon ${m.renk}">${m.ikon}</div>
        <div>
          <div class="module-name">${m.ad}</div>
          <div class="module-desc">${m.desc}</div>
        </div>
        ${!aktif ? '<span class="module-soon-tag">Yakında</span>' : ''}
      </div>
    `;
  }).join('');
}
```

Şununla değiştir:

```js
async function showPortal() {
  const u = currentUser;
  document.getElementById('screen-login').classList.add('hidden');
  document.getElementById('screen-portal').classList.add('active');

  // Header
  document.getElementById('header-user-name').textContent = u.ad;
  document.getElementById('header-user-rol').textContent = (ROL_IKON[u.rol]||'👤') + ' ' + (ROL_AD[u.rol]||u.rol);

  // Hoşgeldin
  document.getElementById('welcome-text').textContent = 'Hoş geldin, ' + u.ad.split(' ')[0];
  document.getElementById('welcome-sub').textContent = ROL_AD[u.rol] + ' • ' + (u.departman||'');

  // Tarih
  const now = new Date();
  document.getElementById('welcome-date').textContent =
    now.toLocaleDateString('tr-TR', { weekday:'long', day:'numeric', month:'long', year:'numeric' });

  // Modülleri render et — artık gerçek yetki_matrisi'ne göre
  const yetkiHaritasi = await kullaniciYetkileriGetir();
  renderModuller(yetkiHaritasi);
}

function renderModuller(yetkiHaritasi) {
  const grid = document.getElementById('modules-grid');
  const izinliSeviyeler = ['goruntule','kayit','tam'];
  const gorunur = MODULLER.filter(m => m.moduller.some(kod => izinliSeviyeler.includes(yetkiHaritasi[kod])));

  grid.innerHTML = gorunur.map(m => {
    const aktif = m.durum === 'aktif';
    return `
      <div class="module-card ${aktif ? 'available' : 'coming-soon'}"
        onclick="${aktif ? `gotoModule('${m.url}')` : 'void(0)'}">
        <div class="module-icon ${m.renk}">${m.ikon}</div>
        <div>
          <div class="module-name">${m.ad}</div>
          <div class="module-desc">${m.desc}</div>
        </div>
        ${!aktif ? '<span class="module-soon-tag">Yakında</span>' : ''}
      </div>
    `;
  }).join('');
}
```

(Değişiklikler: `showPortal` artık `async`, `renderModuller(u.rol)` → `await kullaniciYetkileriGetir()` sonra `renderModuller(yetkiHaritasi)`; `renderModuller` artık `rol` yerine `yetkiHaritasi` parametresi alıyor, filtre `m.roller.includes(rol)` yerine `m.moduller.some(...)` kullanıyor.)

- [ ] **Step 3: `checkPin()`'in sonundaki `showPortal();` çağrısını `await` ile güncelle**

`index.html`'de (Faz A2'den beri `checkPin()` zaten `async`) şu satırı bul:

```js
  showPortal();
}
```

(Bu, `checkPin()` fonksiyonunun en sonunda, `returnTo` kontrolünün hemen altında.) Şununla değiştir:

```js
  await showPortal();
}
```

- [ ] **Step 4: `init()`'teki `showPortal();` çağrısını `await` ile güncelle**

`index.html:656-667`'deki mevcut kod:

```js
(async function init() {
  document.getElementById('loading').classList.add('show');
  await loadUsers();
  document.getElementById('loading').classList.remove('show');

  // Session kontrolü — paylaşılan auth-guard.js üzerinden
  const user = oturumGetir();
  if (user) {
    currentUser = user;
    showPortal();
  }
})();
```

Şununla değiştir:

```js
(async function init() {
  document.getElementById('loading').classList.add('show');
  await loadUsers();
  document.getElementById('loading').classList.remove('show');

  // Session kontrolü — paylaşılan auth-guard.js üzerinden
  const user = oturumGetir();
  if (user) {
    currentUser = user;
    await showPortal();
  }
})();
```

- [ ] **Step 5: Grep ile doğrula**

```bash
grep -n "roller: \[" index.html
grep -n "moduller: \[" index.html
grep -n "async function showPortal\|await showPortal\|function renderModuller(yetkiHaritasi)" index.html
```

Expected: birinci komut HİÇBİR SONUÇ döndürmemeli (eski `roller:` tamamen kalktı); ikinci komut 10 satır döndürmeli; üçüncü komut `async function showPortal`, en az 2 yerde `await showPortal`, ve `function renderModuller(yetkiHaritasi)` satırlarını döndürmeli.

- [ ] **Step 6: Commit**

```bash
cd "C:\Users\USER\Projects\gurok-mal-kabul"
git add index.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: portal menüsü artık gerçek yetki_matrisi'ne göre çalışıyor"
```

---

### Task 3: `muhasebe-cariler.html` — Buton seviyesi pilot

**Files:**
- Modify: `muhasebe-cariler.html:227-228` (Kaydet/Sil butonlarına id ekleme)
- Modify: `muhasebe-cariler.html:276` (ikinci Kaydet butonuna id ekleme)
- Modify: `muhasebe-cariler.html:286-289` (state değişkenleri — yeni `YETKI_HARITASI` eklenir)
- Modify: `muhasebe-cariler.html:557` (`openDuzenleCari` içindeki Sil butonu gösterme satırı)
- Modify: `muhasebe-cariler.html:956-965` (init IIFE)

**Interfaces:**
- Consumes: Task 1'in `kullaniciYetkileriGetir()` fonksiyonu.
- Produces: (yok — bu pilotun son tüketicisi)

- [ ] **Step 1: Kaydet butonlarına id ekle**

`muhasebe-cariler.html:225-229`'daki mevcut kod:

```html
    <div class="brow">
      <button class="btn btn-gray" onclick="kModal('mCari')">İptal</button>
      <button class="btn btn-danger btn-sm" id="c-sil-btn" onclick="cariSil()" style="display:none">🗑️</button>
      <button class="btn btn-primary" onclick="cariKaydet()">💾 Kaydet</button>
    </div>
```

Şununla değiştir:

```html
    <div class="brow">
      <button class="btn btn-gray" onclick="kModal('mCari')">İptal</button>
      <button class="btn btn-danger btn-sm" id="c-sil-btn" onclick="cariSil()" style="display:none">🗑️</button>
      <button class="btn btn-primary" id="c-kaydet-btn" onclick="cariKaydet()">💾 Kaydet</button>
    </div>
```

`muhasebe-cariler.html:274-277`'deki mevcut kod:

```html
    <div class="brow">
      <button class="btn btn-gray" onclick="kModal('mHareket')">İptal</button>
      <button class="btn btn-primary" onclick="hareketKaydet()">💾 Kaydet</button>
    </div>
```

Şununla değiştir:

```html
    <div class="brow">
      <button class="btn btn-gray" onclick="kModal('mHareket')">İptal</button>
      <button class="btn btn-primary" id="h-kaydet-btn" onclick="hareketKaydet()">💾 Kaydet</button>
    </div>
```

- [ ] **Step 2: Yetki haritası için state değişkeni ekle**

`muhasebe-cariler.html:286-289`'daki mevcut kod:

```js
let cariler = {};
let hareketler = {};
let faturalar = {};
let cariFilter = 'tumu';
```

Şununla değiştir:

```js
let cariler = {};
let hareketler = {};
let faturalar = {};
let cariFilter = 'tumu';
let YETKI_HARITASI = {};
```

- [ ] **Step 3: `openDuzenleCari` içindeki Sil butonu satırını yetkiye bağla**

`muhasebe-cariler.html:557`'deki mevcut satır:

```js
  document.getElementById('c-sil-btn').style.display='flex';
```

Şununla değiştir:

```js
  document.getElementById('c-sil-btn').style.display=['kayit','tam'].includes(YETKI_HARITASI['cari_hesaplar'])?'flex':'none';
```

(Not: `openYeniCari`'deki `c-sil-btn` gizleme satırı — `style.display='none'` — DEĞİŞMİYOR, yeni cari için Sil zaten her koşulda gizli kalmalı.)

- [ ] **Step 4: Init'te Kaydet butonlarını yetkiye göre pasif yap**

`muhasebe-cariler.html:956-965`'teki mevcut kod:

```js
(async function(){
  await loadDB();
  const today=new Date().toISOString().split('T')[0];
  const ayBasi=new Date();ayBasi.setDate(1);
  document.getElementById('har-bas').value=ayBasi.toISOString().split('T')[0];
  document.getElementById('har-bit').value=today;
  document.getElementById('mut-bas').value=ayBasi.toISOString().split('T')[0];
  document.getElementById('mut-bit').value=today;
  renderCariler();
})();
```

Şununla değiştir:

```js
(async function(){
  await loadDB();
  const today=new Date().toISOString().split('T')[0];
  const ayBasi=new Date();ayBasi.setDate(1);
  document.getElementById('har-bas').value=ayBasi.toISOString().split('T')[0];
  document.getElementById('har-bit').value=today;
  document.getElementById('mut-bas').value=ayBasi.toISOString().split('T')[0];
  document.getElementById('mut-bit').value=today;
  renderCariler();
  YETKI_HARITASI = await kullaniciYetkileriGetir();
  const yaziYetkisiVar = ['kayit','tam'].includes(YETKI_HARITASI['cari_hesaplar']);
  document.getElementById('c-kaydet-btn').disabled = !yaziYetkisiVar;
  document.getElementById('h-kaydet-btn').disabled = !yaziYetkisiVar;
})();
```

- [ ] **Step 5: Grep ile doğrula**

```bash
grep -n "id=\"c-kaydet-btn\"\|id=\"h-kaydet-btn\"\|YETKI_HARITASI" muhasebe-cariler.html
```

Expected: her iki id de bulunmalı, `YETKI_HARITASI` en az 4 yerde geçmeli (tanım + 3 kullanım).

- [ ] **Step 6: Commit**

```bash
cd "C:\Users\USER\Projects\gurok-mal-kabul"
git add muhasebe-cariler.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: muhasebe-cariler.html buton görünürlüğü gerçek yetkiye bağlandı (Faz B3 pilotu)"
```

---

### Task 4: Uçtan uca doğrulama

**Files:** (yok — sadece doğrulama)

- [ ] **Step 1: Statik doğrulama**

Task 1-3'ün grep adımlarının temiz geçtiğini teyit et. `index.html`'de eski `roller:` deseninin gerçekten hiç kalmadığını, `muhasebe-cariler.html`'deki `openYeniCari`'nin `c-sil-btn` gizleme satırının DEĞİŞMEDİĞİNİ `git diff` ile doğrula.

- [ ] **Step 2: Controller'ın kendi curl doğrulaması**

Gerçek bir kullanıcının (Şeyma, grup_finans, `cari_hesaplar=tam`) `rol_id`'siyle `yetki_matrisi?select=yetki,moduller(kod)&rol_id=eq...` sorgusunu tekrar çalıştırıp doğru haritayı döndürdüğünü teyit et — bu, tasarım aşamasında zaten curl ile doğrulandı, burada sadece deploy sonrası bir sağlık kontrolü.

- [ ] **Step 3: Kullanıcıya manuel test adımlarını bildir**

Kullanıcının tarayıcıda doğrulaması gereken akış:
1. Şeyma (veya `cari_hesaplar` yetkisi `tam`/`kayit` olan biri) ile giriş yap → portalda "Muhasebe" kutucuğu görünmeli → `muhasebe-cariler.html`'e git → Kaydet ve (bir cariyi düzenlerken) Sil butonları aktif/görünür olmalı.
2. `cari_hesaplar` yetkisi sadece `goruntule` olan biriyle (örn. grup_direktor) aynı sayfaya git → Kaydet butonu pasif (tıklanamaz) olmalı, Sil butonu düzenleme modunda bile görünmemeli.
3. Herhangi bir modülde hiç yetkisi olmayan biriyle giriş yap → portalda o modülün kutucuğu HİÇ görünmemeli.
4. Herhangi bir hata/kırılma/beklenmedik davranış olursa bildir.

- [ ] **Step 4: Kullanıcıdan onay al**

"Test ettim, çalışıyor" onayını bekle, ardından push kararını sor.
