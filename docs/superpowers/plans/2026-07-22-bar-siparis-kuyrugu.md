# Bar Sipariş Kuyruk Ekranı Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bar/mutfak personelinin gelen bar siparişlerini görüp durumlarını yönettiği (`yeni → hazirlaniyor → hazir → teslim_edildi | iptal`) tek sayfalık bir kuyruk ekranı (`bar-siparis-kuyrugu.html`).

**Architecture:** Mevcut Depo Sipariş modülüyle birebir aynı desen — vanilla HTML/JS + Supabase REST, `auth-guard.js` + `bar_siparis_yonetimi` yetkisiyle korunur. Durum geçişleri Task 2'de kurulan RPC'leri (`bar_siparis_teslim_et`, `bar_siparis_iptal`, `bar_siparis_durum_guncelle`) çağırır. Canlı görünüm 8 saniyelik `setInterval` polling ile (Realtime yok).

**Tech Stack:** Vanilla HTML/JS, Supabase REST (`fetch`), mevcut `auth-guard.js`/`ortak.js`/`otel-config.js`/`nav-drawer.js`.

## Global Constraints

- Sayfa `bar_siparis_yonetimi` modülüne bağlı: `requireRole(CU, ['mutfak','bar','yonetici'])` sayfa geçidi + init'te `kullaniciYetkileriGetir()` ile `YETKI_HARITASI['bar_siparis_yonetimi']` kontrolü (aksiyon butonları `kayit`/`tam` yoksa disabled).
- Script yükleme sırası (diğer sayfalarla aynı): `auth-guard.js` → `supabase-config.js` → `nav-drawer.js` → `otel-config.js` → `ortak.js` → `theme.css`.
- Durum geçişleri DOĞRUDAN tablo PATCH ile DEĞİL, RPC ile yapılır: `hazirlaniyor`/`hazir` → `bar_siparis_durum_guncelle(id, durum)`; teslim → `bar_siparis_teslim_et(id)` (stok düşürür); iptal → `bar_siparis_iptal(id)` (rezervasyonu serbest bırakır).
- DB'den gelen tüm serbest metin (`oda_no`, `masa_token`, menü ürün adı) `escapeHtml()` ile kaçışlanır (XSS — bugünkü denetim kuralı).
- `bar_siparisleri` sorgusu `bar_siparis_kalemleri(*, menu_urunler(ad))` embed ile kalem+ürün adı çeker.
- Portal (`index.html`) kartı: mevcut `bar` kartı `durum:'yapiyor'` — bu kart `bar.html`'e gidiyor; kuyruk ekranı AYRI, index.html'e dokunulmuyor (kart entegrasyonu ayrı/opsiyonel iş).
- Bu proje paralel oturumla ortak: her task öncesi `git fetch origin` + gerekirse pull; commit `git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com"`.
- `SB_URL='https://xwytofysmgqtqjzkplfi.supabase.co'`, anon key oturumda mevcut.

---

## Task 1: `bar-siparis-kuyrugu.html` — İskelet + Sipariş Listesi + Polling

**Files:**
- Create: `bar-siparis-kuyrugu.html`

**Interfaces:**
- Consumes: `requireLogin()`, `requireRole()`, `kullaniciYetkileriGetir()` (auth-guard.js); `escapeHtml`, `toast`, `sLD`, `hLD` (ortak.js); Task 1-2'nin `bar_siparisleri`/`bar_siparis_kalemleri`/`menu_urunler` tabloları ve `bar_siparis_teslim_et`/`bar_siparis_iptal`/`bar_siparis_durum_guncelle` RPC'leri.

- [ ] **Step 1: Dosyayı oluştur**

```html
<!DOCTYPE html>
<html lang="tr">
<head>
<meta charset="UTF-8">
<script src="auth-guard.js"></script>
<script src="supabase-config.js"></script>
<script src="nav-drawer.js"></script>
<script src="otel-config.js"></script>
<script src="ortak.js"></script>
<link rel="stylesheet" href="theme.css">
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
<title>Gürok — Bar Sipariş Kuyruğu</title>
<meta name="theme-color" content="#1a2744">
<style>
*{box-sizing:border-box;margin:0;padding:0;-webkit-tap-highlight-color:transparent}
html,body{height:100%;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;background:var(--gray-100)}
#app{height:100vh;display:flex;flex-direction:column;overflow:hidden}
.header{background:var(--primary);color:white;padding:12px 16px;display:flex;align-items:center;gap:8px;flex-shrink:0;min-height:56px;box-shadow:var(--shadow)}
.header h1{font-size:15px;font-weight:700;flex:1}.header .sub{font-size:11px;opacity:.7;display:block;margin-top:1px}
.header-btn{background:rgba(255,255,255,.15);border:none;color:white;width:34px;height:34px;border-radius:50%;font-size:16px;cursor:pointer;display:flex;align-items:center;justify-content:center;flex-shrink:0}
.ftabs{display:flex;gap:6px;padding:10px 12px;background:white;border-bottom:1px solid var(--gray-200);overflow-x:auto;flex-shrink:0}
.ftab{padding:6px 14px;border:1.5px solid var(--gray-300);border-radius:20px;font-size:12px;font-weight:600;cursor:pointer;white-space:nowrap;background:white;color:var(--gray-600);flex-shrink:0}
.ftab.active{background:var(--primary);border-color:var(--primary);color:white}
.sc{flex:1;overflow-y:auto;-webkit-overflow-scrolling:touch;padding:12px}
.skart{background:white;border-radius:var(--radius-sm);padding:12px;margin-bottom:10px;box-shadow:0 1px 4px rgba(0,0,0,.08);border-left:4px solid var(--gray-300)}
.skart.yeni{border-left-color:var(--danger)}.skart.hazirlaniyor{border-left-color:var(--warning)}.skart.hazir{border-left-color:var(--info)}.skart.teslim_edildi{border-left-color:var(--success)}.skart.iptal{border-left-color:var(--gray-400);opacity:.6}
.skart-ust{display:flex;justify-content:space-between;align-items:center;margin-bottom:8px}
.skart-masa{font-size:14px;font-weight:700;color:var(--primary)}
.skart-zaman{font-size:11px;color:var(--gray-500)}
.chip{display:inline-flex;align-items:center;padding:3px 8px;border-radius:12px;font-size:11px;font-weight:600}
.chip-yeni{background:#fde8e8;color:#9b1c1c}.chip-hazirlaniyor{background:#fff3cd;color:#856404}.chip-hazir{background:#d1ecf1;color:#0c5460}.chip-teslim_edildi{background:#d4edda;color:#155724}.chip-iptal{background:var(--gray-200);color:var(--gray-600)}
.kalem{font-size:13px;color:var(--gray-700);padding:2px 0}
.oda{font-size:12px;color:var(--danger);font-weight:600;margin-top:4px}
.brow{display:flex;gap:8px;margin-top:10px}
.btn{padding:9px 14px;border:none;border-radius:var(--radius-sm);font-size:13px;font-weight:600;cursor:pointer;flex:1;min-height:40px}
.btn:disabled{background:var(--gray-200)!important;color:var(--gray-400)!important;cursor:not-allowed}
.btn-primary{background:var(--primary);color:white}.btn-success{background:var(--success);color:white}.btn-danger{background:var(--danger);color:white}.btn-info{background:var(--info);color:white}
.es{text-align:center;padding:40px 20px;color:var(--gray-400)}.ei{font-size:48px;margin-bottom:12px}.et{font-size:14px}
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
    <button class="header-btn" onclick="location.href='index.html'"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" style="width:16px;height:16px"><path d="M19 12H5M12 19l-7-7 7-7"/></svg></button>
    <div style="flex:1"><h1>Bar Sipariş Kuyruğu</h1><span class="sub" id="hsub"></span></div>
    <button class="header-btn" onclick="yukle()" title="Yenile"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" style="width:16px;height:16px"><path d="M23 4v6h-6M1 20v-6h6"/><path d="M3.51 9a9 9 0 0 1 14.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0 0 20.49 15"/></svg></button>
  </div>
  <div class="ftabs" id="ftabs">
    <button class="ftab active" onclick="filtrele('aktif',this)">⏳ Aktif</button>
    <button class="ftab" onclick="filtrele('yeni',this)">🔴 Yeni</button>
    <button class="ftab" onclick="filtrele('hazirlaniyor',this)">👨‍🍳 Hazırlanıyor</button>
    <button class="ftab" onclick="filtrele('hazir',this)">🔔 Hazır</button>
    <button class="ftab" onclick="filtrele('teslim_edildi',this)">✅ Teslim</button>
    <button class="ftab" onclick="filtrele('iptal',this)">✕ İptal</button>
  </div>
  <div class="sc" id="liste"></div>
</div>
<div id="toast"></div>
<div id="ld"><div class="sp"></div><div style="font-size:13px">Yükleniyor...</div></div>

<script>
// SB_URL/SB_KEY/SB_HEADERS -> supabase-config.js
// sLD/hLD/toast/escapeHtml -> ortak.js
let CU=null, YETKI_HARITASI={}, SIPARISLER=[], aktifFilter='aktif', _pollTimer=null;

function yazabilir(){ return ['kayit','tam'].includes(YETKI_HARITASI['bar_siparis_yonetimi']); }

function zamanKisa(iso){
  const d=new Date(iso); return d.toLocaleTimeString('tr-TR',{hour:'2-digit',minute:'2-digit'});
}

async function yukle(){
  try{
    const r=await fetch(SB_URL+'/rest/v1/bar_siparisleri?select=*,bar_siparis_kalemleri(adet,menu_urunler(ad))&order=olusturma_zamani.desc',{headers:SB_HEADERS});
    if(r.ok) SIPARISLER=await r.json();
  }catch(e){}
  render();
}

function filtrele(f,btn){
  aktifFilter=f;
  document.querySelectorAll('.ftab').forEach(b=>b.classList.remove('active'));
  if(btn)btn.classList.add('active');
  render();
}

function render(){
  const el=document.getElementById('liste');
  let liste=SIPARISLER;
  if(aktifFilter==='aktif') liste=SIPARISLER.filter(s=>['yeni','hazirlaniyor','hazir'].includes(s.durum));
  else liste=SIPARISLER.filter(s=>s.durum===aktifFilter);
  if(!liste.length){ el.innerHTML='<div class="es"><div class="ei">🍸</div><div class="et">Bu filtrede sipariş yok</div></div>'; return; }
  const yzb=yazabilir();
  el.innerHTML=liste.map(s=>{
    const kalemler=(s.bar_siparis_kalemleri||[]).map(k=>`<div class="kalem">• ${escapeHtml((k.menu_urunler&&k.menu_urunler.ad)||'—')} × ${k.adet}</div>`).join('');
    const odaSatiri=s.oda_no?`<div class="oda">🏨 Oda: ${escapeHtml(s.oda_no)} (ücretli)</div>`:'';
    return `<div class="skart ${s.durum}">
      <div class="skart-ust">
        <span class="skart-masa">${escapeHtml(s.masa_token||'—')}</span>
        <span class="chip chip-${s.durum}">${s.durum}</span>
      </div>
      <div class="skart-zaman">${zamanKisa(s.olusturma_zamani)}</div>
      ${kalemler}
      ${odaSatiri}
      ${aksiyonButonlari(s, yzb)}
    </div>`;
  }).join('');
}

function aksiyonButonlari(s, yzb){
  if(s.durum==='teslim_edildi'||s.durum==='iptal') return '';
  const dis = yzb?'':'disabled';
  let b='<div class="brow">';
  if(s.durum==='yeni') b+=`<button class="btn btn-primary" ${dis} onclick="durumGuncelle('${s.id}','hazirlaniyor')">Hazırlanıyor</button>`;
  if(s.durum==='hazirlaniyor') b+=`<button class="btn btn-info" ${dis} onclick="durumGuncelle('${s.id}','hazir')">Hazır</button>`;
  if(s.durum==='hazir') b+=`<button class="btn btn-success" ${dis} onclick="teslimEt('${s.id}')">Teslim Et</button>`;
  b+=`<button class="btn btn-danger" ${dis} onclick="iptalEt('${s.id}')">İptal</button>`;
  b+='</div>';
  return b;
}

(async function(){
  CU=requireLogin();
  if(!CU) return;
  if(!requireRole(CU, ['mutfak','bar','yonetici'])) return;
  document.getElementById('app').style.display='flex';
  document.getElementById('hsub').textContent=(CU.rol||'')+' '+(CU.ad||'');
  YETKI_HARITASI=await kullaniciYetkileriGetir();
  await yukle();
  _pollTimer=setInterval(yukle, 8000);
})();
</script>
</body>
</html>
```

- [ ] **Step 2: Statik doğrulama**

`grep -c "escapeHtml" bar-siparis-kuyrugu.html` ≥ 3 (masa/oda/ürün adı kaçışlı). Parantez/süslü parantez dengesi kontrol et. `durumGuncelle`/`teslimEt`/`iptalEt` fonksiyonları Task 2'de eklenecek — bu adımda tanımsızlar (onclick'ler henüz çalışmaz, normal).

- [ ] **Step 3: Commit**

```bash
git add bar-siparis-kuyrugu.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: bar-siparis-kuyrugu.html iskeleti — sipariş listesi + filtre + 8sn polling"
```

---

## Task 2: Durum Aksiyon Fonksiyonları (RPC Çağrıları)

**Files:**
- Modify: `bar-siparis-kuyrugu.html`

**Interfaces:**
- Consumes: Task 1'in sayfası + `bar_siparis_durum_guncelle`/`bar_siparis_teslim_et`/`bar_siparis_iptal` RPC'leri.

- [ ] **Step 1: Aksiyon fonksiyonlarını ekle**

`bar-siparis-kuyrugu.html` içinde, `aksiyonButonlari()` fonksiyonundan SONRA, init IIFE'sinden ÖNCE ekle:

```javascript
async function rpcCagir(fonksiyon, govde){
  sLD();
  try{
    const r=await fetch(SB_URL+'/rest/v1/rpc/'+fonksiyon,{
      method:'POST', headers:SB_HEADERS, body:JSON.stringify(govde)
    });
    if(!r.ok){ const t=await r.text(); toast('❌ '+(t.slice(0,120))); hLD(); return false; }
    hLD(); return true;
  }catch(e){ toast('❌ Bağlantı hatası'); hLD(); return false; }
}

async function durumGuncelle(id, durum){
  if(!yazabilir()){ toast('⚠️ Yetkiniz yok'); return; }
  if(await rpcCagir('bar_siparis_durum_guncelle', {p_siparis_id:id, p_durum:durum})){
    toast('✅ '+durum); await yukle();
  }
}

async function teslimEt(id){
  if(!yazabilir()){ toast('⚠️ Yetkiniz yok'); return; }
  if(await rpcCagir('bar_siparis_teslim_et', {p_siparis_id:id})){
    toast('✅ Teslim edildi — stok düşüldü'); await yukle();
  }
}

async function iptalEt(id){
  if(!yazabilir()){ toast('⚠️ Yetkiniz yok'); return; }
  if(!confirm('Bu siparişi iptal et? Rezerve edilen stok serbest bırakılacak.')) return;
  if(await rpcCagir('bar_siparis_iptal', {p_siparis_id:id})){
    toast('✅ İptal edildi'); await yukle();
  }
}
```

- [ ] **Step 2: Statik doğrulama**

`grep -c "durumGuncelle\|teslimEt\|iptalEt" bar-siparis-kuyrugu.html` — tanım + çağrılar (her isim ≥ 2). Tüm `rpc/` çağrıları Task 2'de kurulan gerçek fonksiyon adlarıyla eşleşmeli: `bar_siparis_durum_guncelle`, `bar_siparis_teslim_et`, `bar_siparis_iptal`.

- [ ] **Step 3: Commit**

```bash
git add bar-siparis-kuyrugu.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: bar kuyruk ekranı durum aksiyonları (teslim/iptal/durum RPC çağrıları)"
```

---

## Task 3: Uçtan Uca Doğrulama

**Files:**
- Modify: `.superpowers/sdd/progress.md`

**Interfaces:**
- Consumes: Task 1 + Task 2.

- [ ] **Step 1: Statik/grep kontrolleri**

```bash
cd "C:\Users\USER\Projects\gurok-mal-kabul"
grep -c "escapeHtml" bar-siparis-kuyrugu.html          # >=3
grep -c "bar_siparis_teslim_et\|bar_siparis_iptal\|bar_siparis_durum_guncelle" bar-siparis-kuyrugu.html  # >=3
grep -c "requireRole(CU, \['mutfak','bar','yonetici'\])" bar-siparis-kuyrugu.html  # ==1
grep -c "setInterval(yukle, 8000)" bar-siparis-kuyrugu.html  # ==1
```

- [ ] **Step 2: Kullanıcıdan tarayıcı testi iste**

Kullanıcıya: (a) `mutfak`/`bar`/`yonetici` bir kullanıcıyla `bar-siparis-kuyrugu.html`'i aç — boş kuyruk "sipariş yok" göstermeli, sayfa açılıp `requireRole` geçmeli. (b) Task 1 planındaki test sipariş verisini (BAR_TEST_BIRA + bir sipariş) geçici ekleyip ekranda göründüğünü, "Hazırlanıyor→Hazır→Teslim Et" akışının çalıştığını ve teslim sonrası stokun düştüğünü doğrula, sonra test verisini temizle. (c) Yetkisiz bir rolle (örn. sadece görüntüleme) butonların disabled olduğunu doğrula.

- [ ] **Step 3: İlerleme kaydı + push**

`.superpowers/sdd/progress.md`'ye tamamlanma satırı ekle; `git fetch origin` (drift kontrolü) + `git push origin main`.

---

## Self-Review Notu

- **Spec kapsaması:** Spec bölüm 4 (personel arayüzü — durum akışı, polling, yetki) tam karşılandı: Task 1 liste+polling+iskelet, Task 2 durum geçiş RPC'leri, Task 3 doğrulama.
- **Placeholder taraması:** Yok — tüm HTML/JS tam. Task 1 Step 2'deki "fonksiyonlar Task 2'de eklenecek" bir placeholder değil, task sıralamasının doğal sonucu (iskelet önce, aksiyonlar sonra) ve açıkça belirtildi.
- **Tip/isim tutarlılığı:** `durumGuncelle`/`teslimEt`/`iptalEt`/`rpcCagir`/`yazabilir`/`yukle`/`render`/`aksiyonButonlari` isimleri Task 1-2 arasında birebir tutarlı; RPC adları (`bar_siparis_durum_guncelle` vb.) ve parametre adları (`p_siparis_id`, `p_durum`) Task 2 (veri modeli planı)'nde kurulan imzalarla eşleşiyor.
- **YAGNI:** Realtime yerine polling, sipariş oluşturma bu ekranda yok (müşteri projesinden webhook ile gelir), oda no doğrulama yok — hepsi spec kararlarıyla uyumlu.
