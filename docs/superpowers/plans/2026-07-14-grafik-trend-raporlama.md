# Grafik/Trend Raporlama Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Yeni bir `trend-raporlama.html` sayfası ekleyerek stok/tüketim/food-cost verilerinin zaman içindeki eğilimini Chart.js grafikleriyle göstermek.

**Architecture:** Tek yeni dosya (`trend-raporlama.html`), mevcut sayfaların (`gunluk-tuketim.html`) iskelet desenini (header, auth-guard, SB sabitleri, toast/loading yardımcıları) kopyalar. Üç bağımsız render fonksiyonu (`renderStokTrend`, `renderTuketimTrend`, `renderFoodCostTrend`) ortak bir aralık seçiciyi (7/30 gün) okur, her biri kendi Supabase sorgusunu yapıp kendi `<canvas>`'ına Chart.js ile çizer. `index.html`'e mevcut "Raporlar" kartına dokunmadan yeni, ayrı bir "Trendler" modül kartı eklenir.

**Tech Stack:** Vanilla JS, doğrudan `fetch()` ile Supabase REST API. Chart.js 4.4.1 CDN üzerinden (`https://cdnjs.cloudflare.com/ajax/libs/Chart.js/4.4.1/chart.umd.js`). Build aracı yok, test çerçevesi yok (Node/Python bu ortamda mevcut değil) — doğrulama grep + manuel kod okuma + kullanıcının tarayıcıda elle test etmesiyle yapılır.

## Global Constraints

- Zaman aralığı: ortak seçici, "Son 7 gün" / "Son 30 gün", varsayılan 30 gün — üç grafiği de etkiler.
- Stok Trendi: sadece `tip='giris'` ve `tip='cikis'` sayılır (`transfer` hariç — yön belirsiz, bkz. spec Kapsam dışı). Pencere başında 0'dan başlayan kümülatif net hareket (`giriş toplamı - çıkış toplamı`, güne göre).
- Tüketim Trendi: `stok_hareketleri`'nde `tip='cikis'` VE `aciklama` `gunluk_tuketim` veya `recete_tuketim` içeren satırlar, güne göre toplam miktar (kümülatif DEĞİL, her gün kendi değeri).
- Food-Cost Trendi: `recete_tuketimleri` tablosunun gerçek `tarih` (date) ve `food_cost_yuzde` (nullable) kolonları kullanılır. Güne göre gruplanır, `food_cost_yuzde` NULL olmayan satırların günlük ortalaması alınır. Tüm oteller birlikte (otel filtresi yok).
- Erişim: `requireRole(user, ['yonetici','depo','cost_control'])` — `stok-takip.html` ile aynı roller.
- Mevcut `index.html`'deki "Raporlar" kartına (`url:'mal-kabul-v2.html#izleme'`, roller `['yonetici','satinalma','kalite']`) DOKUNULMAZ — bu farklı bir işlev (mal kabul izleme/uygunsuzluk) ve farklı rollere hizmet ediyor. Yeni sayfa için AYRI bir modül kartı eklenir.
- Veri olmayan ürün/aralık seçiminde grafik boş durum mesajı gösterir, hata fırlatmaz.

---

### Task 1: Sayfa iskeleti + auth + Chart.js yükleme

**Files:**
- Create: `trend-raporlama.html`

**Interfaces:**
- Consumes: `auth-guard.js`'in `requireLogin()` (döner: `{ad,rol,depoId,...}` veya `null`) ve `requireRole(user,izinliRoller)` fonksiyonları (mevcut, değişmeden kullanılır — bkz. `gunluk-tuketim.html:786-789`).
- Produces: Sayfa `#app` iskeleti (`#tab-stok-trend`, `#tab-tuketim-trend`, `#tab-foodcost-trend` bölümleri — hepsi tek sayfada üst üste, sekme YOK, hepsi aynı anda görünür), `#aralik-secici` (7/30 gün butonları), global `let aralikGun=30;`, `SB_URL`/`SB_KEY`/`SB_HEADERS` sabitleri, `toast(m)`/`sLD()`/`hLD()` yardımcıları, `escapeHtml(s)`. Task 2 ve 3 bu iskelet içine kendi bölümlerini render eder.

- [ ] **Step 1: Dosyayı oluştur**

`trend-raporlama.html` adında yeni bir dosya oluştur, aşağıdaki tam içerikle:

```html
<!DOCTYPE html>
<html lang="tr">
<head>
<meta charset="UTF-8">
<script src="auth-guard.js"></script>
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
<title>Gürok — Trend Raporlama</title>
<meta name="theme-color" content="#1a2744">
<script src="https://cdnjs.cloudflare.com/ajax/libs/Chart.js/4.4.1/chart.umd.js"></script>
<style>
:root{--primary:#1a2744;--primary-light:#2d4080;--success:#27ae60;--warning:#f39c12;--danger:#e74c3c;--info:#0284c7;--gray-100:#f1f3f5;--gray-200:#e9ecef;--gray-300:#dee2e6;--gray-400:#ced4da;--gray-500:#adb5bd;--gray-600:#6c757d;--gray-700:#495057;--radius:12px;--radius-sm:8px;--shadow:0 2px 12px rgba(0,0,0,0.1)}
*{box-sizing:border-box;margin:0;padding:0;-webkit-tap-highlight-color:transparent}
html,body{height:100%;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;background:var(--gray-100)}
#app{height:100vh;display:flex;flex-direction:column;overflow:hidden}
.header{background:var(--primary);color:white;padding:12px 16px;display:flex;align-items:center;gap:8px;flex-shrink:0;min-height:56px;box-shadow:var(--shadow)}
.header h1{font-size:15px;font-weight:700;flex:1}
.header .sub{font-size:11px;opacity:.7;display:block;margin-top:1px}
.hbtn{background:rgba(255,255,255,.15);border:none;color:white;width:34px;height:34px;border-radius:50%;font-size:16px;cursor:pointer;display:flex;align-items:center;justify-content:center;flex-shrink:0}
.hbtn:active{background:rgba(255,255,255,.3)}
.sc{flex:1;overflow-y:auto;-webkit-overflow-scrolling:touch;padding:12px}
.card{background:white;border-radius:var(--radius);padding:14px;margin-bottom:12px;box-shadow:var(--shadow)}
.card-title{font-size:13px;font-weight:700;color:var(--primary);margin-bottom:10px;display:flex;align-items:center;gap:6px}
.field select{width:100%;padding:10px 12px;border:1.5px solid var(--gray-300);border-radius:var(--radius-sm);font-size:14px;background:white;outline:none;-webkit-appearance:none;margin-bottom:10px}
.aralik-tabs{display:flex;gap:6px;margin-bottom:12px}
.aralik-tab{flex:1;padding:9px;border:1.5px solid var(--gray-300);border-radius:var(--radius-sm);background:white;font-size:13px;font-weight:600;color:var(--gray-600);cursor:pointer}
.aralik-tab.active{background:var(--primary);color:white;border-color:var(--primary)}
.es{text-align:center;padding:30px 20px;color:var(--gray-400)}.ei{font-size:36px;margin-bottom:8px}.et{font-size:13px}
#toast{position:fixed;bottom:24px;left:50%;transform:translateX(-50%) translateY(20px);background:var(--primary);color:white;padding:10px 20px;border-radius:20px;font-size:13px;z-index:9999;opacity:0;transition:all .3s;pointer-events:none;white-space:nowrap;max-width:90vw;text-align:center}
#toast.show{opacity:1;transform:translateX(-50%) translateY(0)}
#ld{display:none;position:fixed;inset:0;background:rgba(26,39,68,.85);z-index:9998;align-items:center;justify-content:center;flex-direction:column;gap:12px;color:white}
#ld.show{display:flex}
.sp{width:36px;height:36px;border:3px solid rgba(255,255,255,.3);border-top-color:white;border-radius:50%;animation:spin .8s linear infinite}
@keyframes spin{to{transform:rotate(360deg)}}
</style>
</head>
<body>

<div id="app" style="display:none">
  <div class="header">
    <button class="hbtn" onclick="location.href='index.html'">🏠</button>
    <div style="flex:1"><h1>Trend Raporlama</h1><span class="sub" id="hsub"></span></div>
  </div>

  <div class="sc">
    <div class="aralik-tabs">
      <button class="aralik-tab" id="ar-7" onclick="aralikSec(7)">Son 7 gün</button>
      <button class="aralik-tab active" id="ar-30" onclick="aralikSec(30)">Son 30 gün</button>
    </div>

    <div class="card" id="tab-stok-trend"></div>
    <div class="card" id="tab-tuketim-trend"></div>
    <div class="card" id="tab-foodcost-trend"></div>
  </div>
</div>

<div id="toast"></div>
<div id="ld"><div class="sp"></div><div style="font-size:13px">Yükleniyor...</div></div>

<script>
const SB_URL='https://xwytofysmgqtqjzkplfi.supabase.co';
const SB_KEY='eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inh3eXRvZnlzbWdxdHFqemtwbGZpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMyMjg5ODMsImV4cCI6MjA5ODgwNDk4M30.E7cRcOAvCmUFXWs45t4HE-igpmqWmSN2J66dOuvCHjA';
const SB_HEADERS={'apikey':SB_KEY,'Authorization':'Bearer '+SB_KEY,'Content-Type':'application/json'};

let CU=null;
let aralikGun=30;

function toast(m){const t=document.getElementById('toast');t.textContent=m;t.classList.add('show');clearTimeout(window._tt);window._tt=setTimeout(()=>t.classList.remove('show'),3000);}
function escapeHtml(s){return String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));}
function sLD(){document.getElementById('ld').classList.add('show');}
function hLD(){document.getElementById('ld').classList.remove('show');}

function aralikSec(gun){
  aralikGun=gun;
  document.getElementById('ar-7').classList.toggle('active',gun===7);
  document.getElementById('ar-30').classList.toggle('active',gun===30);
  renderTumTrendler();
}

function renderTumTrendler(){
  // Task 2 ve Task 3 burada kendi render fonksiyonlarını çağıracak
}

function basla(){
  document.getElementById('app').style.display='flex';
  document.getElementById('hsub').textContent=(CU.rol||'')+' '+(CU.ad||'');
  renderTumTrendler();
}

(async function(){
  CU = requireLogin();
  if(!CU) return;
  if(!requireRole(CU, ['yonetici','depo','cost_control'])) return;
  basla();
})();
</script>
</body>
</html>
```

- [ ] **Step 2: Doğrulama**

Bu dosyada test çerçevesi yok. Doğrulama için:

```bash
grep -n "requireRole(CU, \['yonetici','depo','cost_control'\])\|function aralikSec\|function renderTumTrendler\|Chart.js/4.4.1" trend-raporlama.html
```

Expected: 4 eşleşme (rol kontrolü, `aralikSec` tanımı, `renderTumTrendler` tanımı, Chart.js script src).

- [ ] **Step 3: Commit**

```bash
git add trend-raporlama.html
git commit -m "feat: add trend-raporlama.html page skeleton with auth and Chart.js"
```

---

### Task 2: Stok Trendi + Tüketim Trendi bölümleri

**Files:**
- Modify: `trend-raporlama.html` (Task 1'in oluşturduğu dosya)

**Interfaces:**
- Consumes: Task 1'in `SB_URL`/`SB_HEADERS`/`aralikGun`/`sLD()`/`hLD()`/`escapeHtml()`/`#tab-stok-trend`/`#tab-tuketim-trend` elemanları, `renderTumTrendler()` fonksiyonu (bu task içini doldurur).
- Produces: `async function renderStokTrend()`, `async function renderTuketimTrend()` — Task 3'ün `renderTumTrendler()` içinde bu iki fonksiyonu da çağırması gerekir (Task 3, Task 2'den sonra bu satırları ekleyecek).

- [ ] **Step 1: Ürün listesi yardımcı fonksiyonunu ekle**

`trend-raporlama.html`'de `function renderTumTrendler(){` fonksiyonunun HEMEN ÜSTÜNE (yani `// Task 2 ve Task 3...` yorumundan önce) şunu ekle:

```js
let _urunListesiCache=null;
async function urunListesiGetir(){
  if(_urunListesiCache)return _urunListesiCache;
  try{
    const r=await fetch(SB_URL+'/rest/v1/urunler?select=kod,ad&order=ad',{headers:SB_HEADERS});
    _urunListesiCache=r.ok?await r.json():[];
  }catch(e){_urunListesiCache=[];}
  return _urunListesiCache;
}
```

- [ ] **Step 2: `renderStokTrend()` fonksiyonunu ekle**

Aynı yere (`urunListesiGetir`'in hemen altına) şunu ekle:

```js
let _stokTrendUrun=null;
async function renderStokTrend(){
  const el=document.getElementById('tab-stok-trend');
  const urunler=await urunListesiGetir();
  if(!_stokTrendUrun&&urunler.length)_stokTrendUrun=urunler[0].kod;
  const secenekler=urunler.map(u=>`<option value="${u.kod}" ${u.kod===_stokTrendUrun?'selected':''}>${escapeHtml(u.ad)}</option>`).join('');
  el.innerHTML=`
    <div class="card-title">📦 Stok Trendi (pencere içi kümülatif net hareket)</div>
    <div class="field"><select id="stok-trend-urun" onchange="_stokTrendUrun=this.value;renderStokTrend()">${secenekler}</select></div>
    <div style="position:relative;height:220px"><canvas id="stok-trend-canvas"></canvas></div>`;
  if(!_stokTrendUrun){el.querySelector('div[style]').innerHTML='<div class="es"><div class="ei">📦</div><div class="et">Ürün bulunamadı</div></div>';return;}

  const baslangic=new Date(Date.now()-aralikGun*24*60*60*1000).toISOString();
  let hareketler=[];
  try{
    const r=await fetch(SB_URL+'/rest/v1/stok_hareketleri?urun_kodu=eq.'+encodeURIComponent(_stokTrendUrun)+'&tarih=gte.'+encodeURIComponent(baslangic)+'&or=(tip.eq.giris,tip.eq.cikis)&select=tip,miktar,tarih&order=tarih.asc',{headers:SB_HEADERS});
    if(r.ok)hareketler=await r.json();
  }catch(e){}

  const gunlukNet={};
  hareketler.forEach(h=>{
    const gun=String(h.tarih).slice(0,10);
    const isaret=h.tip==='giris'?1:-1;
    gunlukNet[gun]=(gunlukNet[gun]||0)+isaret*(parseFloat(h.miktar)||0);
  });

  const gunler=[];
  for(let i=aralikGun-1;i>=0;i--){
    gunler.push(new Date(Date.now()-i*24*60*60*1000).toISOString().slice(0,10));
  }
  let kumulatif=0;
  const veri=gunler.map(g=>{kumulatif+=(gunlukNet[g]||0);return kumulatif;});

  if(!hareketler.length){
    document.getElementById('stok-trend-canvas').parentElement.innerHTML='<div class="es"><div class="ei">📦</div><div class="et">Bu aralıkta hareket yok</div></div>';
    return;
  }

  new Chart(document.getElementById('stok-trend-canvas'),{
    type:'line',
    data:{labels:gunler,datasets:[{label:'Kümülatif net hareket',data:veri,borderColor:'#1a2744',backgroundColor:'rgba(26,39,68,.08)',fill:true,tension:.2}]},
    options:{responsive:true,maintainAspectRatio:false,plugins:{legend:{display:false}}}
  });
}
```

- [ ] **Step 3: `renderTuketimTrend()` fonksiyonunu ekle**

Aynı yere (`renderStokTrend`'in hemen altına) şunu ekle:

```js
let _tuketimTrendUrun=null;
async function renderTuketimTrend(){
  const el=document.getElementById('tab-tuketim-trend');
  const urunler=await urunListesiGetir();
  if(!_tuketimTrendUrun&&urunler.length)_tuketimTrendUrun=urunler[0].kod;
  const secenekler=urunler.map(u=>`<option value="${u.kod}" ${u.kod===_tuketimTrendUrun?'selected':''}>${escapeHtml(u.ad)}</option>`).join('');
  el.innerHTML=`
    <div class="card-title">📉 Tüketim Trendi</div>
    <div class="field"><select id="tuketim-trend-urun" onchange="_tuketimTrendUrun=this.value;renderTuketimTrend()">${secenekler}</select></div>
    <div style="position:relative;height:220px"><canvas id="tuketim-trend-canvas"></canvas></div>`;
  if(!_tuketimTrendUrun){el.querySelector('div[style]').innerHTML='<div class="es"><div class="ei">📉</div><div class="et">Ürün bulunamadı</div></div>';return;}

  const baslangic=new Date(Date.now()-aralikGun*24*60*60*1000).toISOString();
  let hareketler=[];
  try{
    const r=await fetch(SB_URL+'/rest/v1/stok_hareketleri?urun_kodu=eq.'+encodeURIComponent(_tuketimTrendUrun)+'&tip=eq.cikis&tarih=gte.'+encodeURIComponent(baslangic)+'&or=(aciklama.ilike.*gunluk_tuketim*,aciklama.ilike.*recete_tuketim*)&select=miktar,tarih&order=tarih.asc',{headers:SB_HEADERS});
    if(r.ok)hareketler=await r.json();
  }catch(e){}

  if(!hareketler.length){
    document.getElementById('tuketim-trend-canvas').parentElement.innerHTML='<div class="es"><div class="ei">📉</div><div class="et">Bu aralıkta tüketim yok</div></div>';
    return;
  }

  const gunlukToplam={};
  hareketler.forEach(h=>{
    const gun=String(h.tarih).slice(0,10);
    gunlukToplam[gun]=(gunlukToplam[gun]||0)+(parseFloat(h.miktar)||0);
  });

  const gunler=[];
  for(let i=aralikGun-1;i>=0;i--){
    gunler.push(new Date(Date.now()-i*24*60*60*1000).toISOString().slice(0,10));
  }
  const veri=gunler.map(g=>gunlukToplam[g]||0);

  new Chart(document.getElementById('tuketim-trend-canvas'),{
    type:'line',
    data:{labels:gunler,datasets:[{label:'Günlük tüketim',data:veri,borderColor:'#f39c12',backgroundColor:'rgba(243,156,18,.08)',fill:true,tension:.2}]},
    options:{responsive:true,maintainAspectRatio:false,plugins:{legend:{display:false}}}
  });
}
```

- [ ] **Step 4: Doğrulama**

```bash
grep -n "async function renderStokTrend\|async function renderTuketimTrend\|async function urunListesiGetir" trend-raporlama.html
```

Expected: 3 eşleşme.

- [ ] **Step 5: Commit**

```bash
git add trend-raporlama.html
git commit -m "feat: add stok and tüketim trend charts to trend-raporlama.html"
```

---

### Task 3: Food-Cost Trendi bölümü + `renderTumTrendler()` bağlama + `index.html` modül kartı

**Files:**
- Modify: `trend-raporlama.html` (Task 1/2'nin oluşturduğu dosya)
- Modify: `index.html` (`MODULLER` dizisi, satır ~422 civarı — `gunlukTuketim` girdisinin hemen sonrası)

**Interfaces:**
- Consumes: Task 2'nin `renderStokTrend()`, `renderTuketimTrend()` fonksiyonları; Task 1'in `renderTumTrendler()` gövdesi (bu task doldurur), `aralikGun`, `SB_URL`/`SB_HEADERS`, `escapeHtml()`.
- Produces: `async function renderFoodCostTrend()` — başka hiçbir task tüketmiyor.

- [ ] **Step 1: `renderFoodCostTrend()` fonksiyonunu ekle**

`trend-raporlama.html`'de Task 2'nin eklediği `renderTuketimTrend()` fonksiyonunun hemen altına şunu ekle:

```js
async function renderFoodCostTrend(){
  const el=document.getElementById('tab-foodcost-trend');
  el.innerHTML=`
    <div class="card-title">💰 Food-Cost Trendi (tüm oteller)</div>
    <div style="position:relative;height:220px"><canvas id="foodcost-trend-canvas"></canvas></div>`;

  const baslangicTarih=new Date(Date.now()-aralikGun*24*60*60*1000).toISOString().slice(0,10);
  let kayitlar=[];
  try{
    const r=await fetch(SB_URL+'/rest/v1/recete_tuketimleri?tarih=gte.'+encodeURIComponent(baslangicTarih)+'&select=tarih,food_cost_yuzde&order=tarih.asc',{headers:SB_HEADERS});
    if(r.ok)kayitlar=await r.json();
  }catch(e){}

  const gecerli=kayitlar.filter(k=>k.food_cost_yuzde!==null&&k.food_cost_yuzde!==undefined);
  if(!gecerli.length){
    document.getElementById('foodcost-trend-canvas').parentElement.innerHTML='<div class="es"><div class="ei">💰</div><div class="et">Bu aralıkta food-cost verisi yok</div></div>';
    return;
  }

  const gunlukToplam={},gunlukSayi={};
  gecerli.forEach(k=>{
    const gun=k.tarih;
    gunlukToplam[gun]=(gunlukToplam[gun]||0)+(parseFloat(k.food_cost_yuzde)||0);
    gunlukSayi[gun]=(gunlukSayi[gun]||0)+1;
  });

  const gunler=[];
  for(let i=aralikGun-1;i>=0;i--){
    gunler.push(new Date(Date.now()-i*24*60*60*1000).toISOString().slice(0,10));
  }
  const veri=gunler.map(g=>gunlukSayi[g]?Math.round((gunlukToplam[g]/gunlukSayi[g])*10)/10:null);

  new Chart(document.getElementById('foodcost-trend-canvas'),{
    type:'line',
    data:{labels:gunler,datasets:[{label:'Ortalama food-cost %',data:veri,borderColor:'#27ae60',backgroundColor:'rgba(39,174,96,.08)',fill:true,tension:.2,spanGaps:false}]},
    options:{responsive:true,maintainAspectRatio:false,plugins:{legend:{display:false}}}
  });
}
```

- [ ] **Step 2: `renderTumTrendler()`'ı üç fonksiyonu çağıracak şekilde doldur**

`trend-raporlama.html`'de şu bloğu:

```js
function renderTumTrendler(){
  // Task 2 ve Task 3 burada kendi render fonksiyonlarını çağıracak
}
```

şununla değiştir:

```js
function renderTumTrendler(){
  renderStokTrend();
  renderTuketimTrend();
  renderFoodCostTrend();
}
```

- [ ] **Step 3: `index.html`'e yeni modül kartını ekle**

`index.html`'de satır ~420-431 civarındaki `gunlukTuketim` girdisinin kapanışını (`durum: 'aktif'\n  }\n];`) bul:

```js
    url: 'gunluk-tuketim.html',
    roller: ['mutfak', 'bar', 'yonetici'],
    durum: 'aktif'
  }
];
```

şununla değiştir:

```js
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

- [ ] **Step 4: Doğrulama**

```bash
grep -n "async function renderFoodCostTrend\|renderStokTrend();\|renderTuketimTrend();\|renderFoodCostTrend();" trend-raporlama.html
grep -n "id: 'trendler'\|url: 'trend-raporlama.html'" index.html
```

Expected: ilk komut 4 eşleşme (fonksiyon tanımı + `renderTumTrendler()` içindeki 3 çağrı), ikinci komut 2 eşleşme.

- [ ] **Step 5: Commit**

```bash
git add trend-raporlama.html index.html
git commit -m "feat: add food-cost trend chart and wire up trend-raporlama.html navigation"
```

---

### Task 4: Uçtan uca doğrulama

**Files:** (yok — sadece doğrulama)

- [ ] **Step 1: Tutarlılık kontrolü**

```bash
grep -n "async function renderStokTrend\|async function renderTuketimTrend\|async function renderFoodCostTrend\|function aralikSec\|id: 'trendler'" trend-raporlama.html index.html
```
Expected: `trend-raporlama.html`'de 4 fonksiyon tanımı, `index.html`'de 1 modül girişi — hepsi tekrarsız.

- [ ] **Step 2: Kullanıcıya manuel test adımlarını bildir**

Kullanıcının tarayıcıda doğrulaması gereken akış (Node/Python bu ortamda yok, otomatik test yazılamıyor):
1. `index.html`'e giriş yap (yonetici/depo/cost_control rolüyle) → yeni "📈 Trendler" kartının göründüğünü doğrula, tıkla.
2. `trend-raporlama.html` açılınca üç grafiğin de (Stok Trendi, Tüketim Trendi, Food-Cost Trendi) hatasız çizildiğini doğrula.
3. Stok Trendi'nde ürün dropdown'ından bilinen giriş/çıkış hareketi olan bir ürün seç → grafiğin pencere başında 0'dan başladığını, bilinen hareketlerle tutarlı bir kümülatif çizgi çizdiğini doğrula.
4. "Son 7 gün" / "Son 30 gün" sekmelerini değiştir → üç grafiğin de yeniden çizildiğini doğrula.
5. Hiç hareketi olmayan bir ürün seç → grafik yerine "Bu aralıkta hareket yok" mesajının çıktığını doğrula.
6. `mutfak`/`bar` gibi yetkisiz bir rolle giriş yapıp `trend-raporlama.html`'e doğrudan URL ile gitmeyi dene → erişimin engellendiğini doğrula.

- [ ] **Step 3: Kullanıcıdan onay al, sonra push**

```bash
git fetch
git log --oneline main..origin/main
```
Expected: paralel oturumdan gelen değişiklik var mı kontrol et, varsa kullanıcıya bildir. Yoksa kullanıcı onayıyla `git push`.
