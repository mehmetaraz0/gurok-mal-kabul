# e-Defter (Yevmiye + Kebir XML) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Yeni bir `muhasebe-edefter.html` modülü ile, mevcut Yevmiye/Kebir verisinden GİB'in gerçek XBRL-GL yapısına uygun **imzasız** e-Defter XML dosyaları üretmek.

**Architecture:** Tek dosyalık yeni modül (`muhasebe-edefter.html`), mevcut `muhasebe-yevmiye.html` ile aynı Supabase tablolarını (`yevmiye_fisler`, `yevmiye_kalemleri`, `hesap_plani`) okur, artı iki yeni tablo (`edefter_kurum_bilgileri`, `edefter_sube_bilgileri`) ile firma/şube bilgilerini tutar. XML, string template literal'larla elle inşa edilir (dış kütüphane gerekmez); tarayıcı `Blob`/`URL.createObjectURL` ile indirilir.

**Tech Stack:** Vanilla HTML/JS, Supabase REST (fetch) — build aracı/test çerçevesi/XML kütüphanesi yok.

## Global Constraints

- Üretilen XML **imzasız** olmalı — `<ds:Signature>` bloğu hiç üretilmez, dosya adında ve arayüzde "imzasız/İMZASIZ" ibaresi bulunur (spec).
- `accountSub` (alt hesap) elemanı hiç üretilmez — mevcut sistemde kullanılmıyor (spec).
- Sadece `onaylandi=true` yevmiye fişleri XML'e dahil edilir; taslak fişler sayıca kullanıcıya bildirilir ama dahil edilmez (spec).
- Mali dönem kapalı değilse üretim durdurulmaz, sadece onay istenir (spec).
- Kurum Bilgileri zorunlu alanları eksikse XML üretimi durur (spec).
- Dosya adları: `yevmiye-<VKN>-<YYYYAA>-imzasiz.xml` / `kebir-<VKN>-<YYYYAA>-imzasiz.xml` (spec).

---

### Task 1: Supabase şema değişikliği (kullanıcı tarafından çalıştırılır)

**Files:**
- Modify: Supabase SQL Editor (kod tabanında dosya yok)

**Interfaces:**
- Produces: `edefter_kurum_bilgileri` tablosu (tek satır), `edefter_sube_bilgileri` tablosu (otel başına bir satır) — Task 2/3'ün CRUD fonksiyonları bu tablolara yazar/okur.

- [ ] **Step 1: Kullanıcıya SQL'i ver, Supabase SQL Editor'de çalıştırmasını iste**

```sql
CREATE TABLE IF NOT EXISTS edefter_kurum_bilgileri (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vkn text,
  unvan text,
  adres_bina_no text,
  adres_sokak text,
  adres_sehir text,
  adres_posta_kodu text,
  adres_ulke text DEFAULT 'Türkiye',
  telefon text,
  eposta text,
  website text,
  is_tanimi text,
  mali_yil_baslangic date,
  mali_yil_bitis date,
  muhasebeci_ad text,
  muhasebeci_unvan text
);

CREATE TABLE IF NOT EXISTS edefter_sube_bilgileri (
  otel_id text PRIMARY KEY,
  sube_no text,
  sube_adi text
);
```

- [ ] **Step 2: Kullanıcı çalıştırdıktan sonra doğrula**

```bash
curl -s "https://xwytofysmgqtqjzkplfi.supabase.co/rest/v1/edefter_kurum_bilgileri?select=id&limit=1" -H "apikey: <SB_KEY>" -H "Authorization: Bearer <SB_KEY>"
curl -s "https://xwytofysmgqtqjzkplfi.supabase.co/rest/v1/edefter_sube_bilgileri?select=otel_id&limit=1" -H "apikey: <SB_KEY>" -H "Authorization: Bearer <SB_KEY>"
```
Expected: İkisi de `200` ve `[]` döner.

---

### Task 2: `muhasebe-edefter.html` iskeleti + Kurum Bilgileri paneli

**Files:**
- Create: `muhasebe-edefter.html`

**Interfaces:**
- Consumes: `auth-guard.js` (`requireLogin`, `requireRole`), Supabase REST.
- Produces: Global state `kurumBilgi` (camelCase kurum nesnesi veya `null`), `subeBilgileri` (obje, `otelId` anahtarlı), `yevmiyeler`, `hesapPlani` (Task 3/4/5'in kullanacağı); `kurumBilgileriYukle()`, `kurumBilgileriKaydet(k)`, `subeBilgileriYukle(otelId)`, `subeBilgileriKaydet(otelId,subeNo,subeAdi)` fonksiyonları.

- [ ] **Step 1: Dosyanın iskeletini oluştur**

```html
<!DOCTYPE html>
<html lang="tr">
<head>
<meta charset="UTF-8">
<script src="auth-guard.js"></script>
<script>
let OTURUM_KULLANICI = requireLogin();
if (OTURUM_KULLANICI) requireRole(OTURUM_KULLANICI, ['yonetici','satinalma']);
</script>
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
<title>Gürok — e-Defter</title>
<meta name="theme-color" content="#1a2744">
<style>
:root{--primary:#1a2744;--primary-light:#2d4080;--success:#27ae60;--warning:#f39c12;--danger:#e74c3c;--info:#0284c7;--gray-100:#f1f3f5;--gray-200:#e9ecef;--gray-300:#dee2e6;--gray-400:#ced4da;--gray-500:#adb5bd;--gray-600:#6c757d;--gray-700:#495057;--radius:12px;--radius-sm:8px;--shadow:0 2px 12px rgba(0,0,0,0.1)}
*{box-sizing:border-box;margin:0;padding:0;-webkit-tap-highlight-color:transparent}
html,body{height:100%;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;background:var(--gray-100)}
#app{height:100vh;display:flex;flex-direction:column;overflow:hidden}
.header{background:var(--primary);color:white;padding:12px 16px;display:flex;align-items:center;gap:8px;flex-shrink:0;min-height:56px;box-shadow:var(--shadow)}
.header h1{font-size:15px;font-weight:700;flex:1}
.hbtn{background:rgba(255,255,255,.15);border:none;color:white;width:34px;height:34px;border-radius:50%;font-size:16px;cursor:pointer;display:flex;align-items:center;justify-content:center;flex-shrink:0}
.hbtn:active{background:rgba(255,255,255,.3)}
.tab-bar{background:white;display:flex;border-bottom:2px solid var(--gray-200);flex-shrink:0;overflow-x:auto}
.tab-bar::-webkit-scrollbar{display:none}
.tabbtn{padding:12px 16px;border:none;background:none;font-size:12px;font-weight:600;color:var(--gray-500);cursor:pointer;white-space:nowrap;border-bottom:2px solid transparent;margin-bottom:-2px;flex-shrink:0}
.tabbtn.active{color:var(--primary);border-bottom-color:var(--primary)}
.sc{flex:1;overflow-y:auto;-webkit-overflow-scrolling:touch;padding:12px;display:none}
.sc::-webkit-scrollbar{display:none}
.card{background:white;border-radius:var(--radius);padding:14px;margin-bottom:10px;box-shadow:var(--shadow)}
.card-title{font-size:13px;font-weight:700;color:var(--primary);margin-bottom:10px;display:flex;align-items:center;gap:6px}
.field{margin-bottom:12px}
.field label{display:block;font-size:12px;font-weight:600;color:var(--gray-600);margin-bottom:5px;text-transform:uppercase}
.field input,.field select{width:100%;padding:10px 12px;border:1.5px solid var(--gray-300);border-radius:var(--radius-sm);font-size:14px;background:white;outline:none;-webkit-appearance:none}
.field input:focus,.field select:focus{border-color:var(--primary)}
.rfields{display:grid;grid-template-columns:1fr 1fr;gap:8px}.rfields .field{margin-bottom:0}
.btn{padding:11px 18px;border:none;border-radius:var(--radius-sm);font-size:14px;font-weight:600;cursor:pointer;display:inline-flex;align-items:center;justify-content:center;gap:6px;min-height:44px}
.btn:active{transform:scale(.97)}.btn-primary{background:var(--primary);color:white}.btn-success{background:var(--success);color:white}.btn-gray{background:var(--gray-200);color:var(--gray-700)}.btn-block{width:100%}.btn-sm{padding:7px 12px;font-size:12px;min-height:34px}
.uyari-serit{background:#fff7ed;border:1px solid #fed7aa;border-radius:8px;padding:8px 10px;margin-bottom:10px;font-size:11px;color:#92400e;font-weight:600}
#toast{position:fixed;bottom:24px;left:50%;transform:translateX(-50%) translateY(20px);background:var(--primary);color:white;padding:10px 20px;border-radius:20px;font-size:13px;z-index:9999;opacity:0;transition:all .3s;pointer-events:none;white-space:nowrap;max-width:90vw;text-align:center}
#toast.show{opacity:1;transform:translateX(-50%) translateY(0)}
#ld{display:none;position:fixed;inset:0;background:rgba(26,39,68,.85);z-index:9998;align-items:center;justify-content:center;flex-direction:column;gap:12px;color:white}
#ld.show{display:flex}
.sp{width:36px;height:36px;border:3px solid rgba(255,255,255,.3);border-top-color:white;border-radius:50%;animation:spin .8s linear infinite}
@keyframes spin{to{transform:rotate(360deg)}}
</style>
</head>
<body>
<div id="app">
  <div class="header">
    <button class="hbtn" onclick="location.href='muhasebe.html'">←</button>
    <div style="flex:1"><h1>e-Defter</h1><span style="font-size:11px;opacity:.7;display:block;margin-top:1px">Yevmiye / Kebir XML (imzasız taslak)</span></div>
  </div>
  <div class="tab-bar">
    <button class="tabbtn active" onclick="gTab('kurum',this)">🏢 Kurum Bilgileri</button>
    <button class="tabbtn" onclick="gTab('yevxml',this)">📒 Yevmiye XML</button>
    <button class="tabbtn" onclick="gTab('kebxml',this)">📗 Kebir XML</button>
  </div>

  <!-- KURUM BİLGİLERİ -->
  <div class="sc" id="tab-kurum" style="display:block">
    <div class="card">
      <div class="card-title">🏢 Firma Bilgileri</div>
      <div class="field"><label>VKN (10 haneli)</label><input type="text" id="kb-vkn" maxlength="10"></div>
      <div class="field"><label>Unvan</label><input type="text" id="kb-unvan"></div>
      <div class="rfields">
        <div class="field"><label>Bina No</label><input type="text" id="kb-bina"></div>
        <div class="field"><label>Sokak</label><input type="text" id="kb-sokak"></div>
      </div>
      <div class="rfields">
        <div class="field"><label>Şehir</label><input type="text" id="kb-sehir"></div>
        <div class="field"><label>Posta Kodu</label><input type="text" id="kb-posta"></div>
      </div>
      <div class="field"><label>Ülke</label><input type="text" id="kb-ulke" value="Türkiye"></div>
      <div class="rfields">
        <div class="field"><label>Telefon</label><input type="text" id="kb-telefon"></div>
        <div class="field"><label>E-posta</label><input type="text" id="kb-eposta"></div>
      </div>
      <div class="field"><label>Website</label><input type="text" id="kb-website"></div>
      <div class="field"><label>İş Tanımı</label><input type="text" id="kb-istanimi" placeholder="Örn: Turizm ve otelcilik"></div>
      <div class="rfields">
        <div class="field"><label>Mali Yıl Başlangıç</label><input type="date" id="kb-myb"></div>
        <div class="field"><label>Mali Yıl Bitiş</label><input type="date" id="kb-mye"></div>
      </div>
      <div class="rfields">
        <div class="field"><label>Muhasebeci Adı</label><input type="text" id="kb-muhad"></div>
        <div class="field"><label>Muhasebeci Unvanı</label><input type="text" id="kb-muhunvan" placeholder="Örn: Serbest Muhasebeci Mali Müşavir"></div>
      </div>
      <button class="btn btn-primary btn-block" onclick="kurumBilgileriFormKaydet()">💾 Kaydet</button>
    </div>
    <div id="sube-alani"></div>
  </div>

  <!-- YEVMİYE XML -->
  <div class="sc" id="tab-yevxml">
    <div id="yevxml-alani"></div>
  </div>

  <!-- KEBİR XML -->
  <div class="sc" id="tab-kebxml">
    <div id="kebxml-alani"></div>
  </div>
</div>
<div id="toast"></div>
<div id="ld"><div class="sp"></div><div>Yükleniyor...</div></div>
<script>
const SB_URL='https://xwytofysmgqtqjzkplfi.supabase.co';
const SB_KEY='eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inh3eXRvZnlzbWdxdHFqemtwbGZpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMyMjg5ODMsImV4cCI6MjA5ODgwNDk4M30.E7cRcOAvCmUFXWs45t4HE-igpmqWmSN2J66dOuvCHjA';
const SB_HEADERS={'apikey':SB_KEY,'Authorization':'Bearer '+SB_KEY,'Content-Type':'application/json'};
const OTEL_ISIMLERI={'810':'Ali Bey Club Manavgat','811':'Ali Bey Resort Sorgun'};

let kurumBilgi=null,subeBilgileri={},yevmiyeler={},hesapPlani={};

function toast(msg,d=2500){const t=document.getElementById('toast');t.textContent=msg;t.classList.add('show');setTimeout(()=>t.classList.remove('show'),d);}
function sLD(){document.getElementById('ld').classList.add('show');}
function hLD(){document.getElementById('ld').classList.remove('show');}
function escapeHtml(s){return String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));}
function fmt(n){return(parseFloat(n)||0).toLocaleString('tr-TR',{minimumFractionDigits:2,maximumFractionDigits:2});}
function round2(n){return Math.round(((parseFloat(n)||0)+Number.EPSILON)*100)/100;}
function gTab(tab,el){
  document.querySelectorAll('.sc').forEach(s=>s.style.display='none');
  document.querySelectorAll('.tabbtn').forEach(t=>t.classList.remove('active'));
  document.getElementById('tab-'+tab).style.display='block';
  el.classList.add('active');
  if(tab==='kurum')renderSubeAlani();
  if(tab==='yevxml')renderYevXmlAlani();
  if(tab==='kebxml')renderKebXmlAlani();
}
</script>
</body>
</html>
```

- [ ] **Step 2: Kurum Bilgileri CRUD fonksiyonlarını ekle**

Ana `<script>` bloğunun içine, `gTab` fonksiyonunun hemen ardına ekle:

```js
async function kurumBilgileriYukle(){
  try{
    const r=await fetch(SB_URL+'/rest/v1/edefter_kurum_bilgileri?select=*&limit=1',{headers:SB_HEADERS});
    if(!r.ok)return null;
    const d=await r.json();
    if(!d.length)return null;
    const k=d[0];
    return{
      id:k.id,vkn:k.vkn||'',unvan:k.unvan||'',
      adresBinaNo:k.adres_bina_no||'',adresSokak:k.adres_sokak||'',adresSehir:k.adres_sehir||'',
      adresPostaKodu:k.adres_posta_kodu||'',adresUlke:k.adres_ulke||'Türkiye',
      telefon:k.telefon||'',eposta:k.eposta||'',website:k.website||'',
      isTanimi:k.is_tanimi||'',maliYilBaslangic:k.mali_yil_baslangic||'',maliYilBitis:k.mali_yil_bitis||'',
      muhasebeciAd:k.muhasebeci_ad||'',muhasebeciUnvan:k.muhasebeci_unvan||''
    };
  }catch(e){return null;}
}

async function kurumBilgileriKaydet(k){
  const satir={
    vkn:k.vkn||null,unvan:k.unvan||null,adres_bina_no:k.adresBinaNo||null,adres_sokak:k.adresSokak||null,
    adres_sehir:k.adresSehir||null,adres_posta_kodu:k.adresPostaKodu||null,adres_ulke:k.adresUlke||null,
    telefon:k.telefon||null,eposta:k.eposta||null,website:k.website||null,is_tanimi:k.isTanimi||null,
    mali_yil_baslangic:k.maliYilBaslangic||null,mali_yil_bitis:k.maliYilBitis||null,
    muhasebeci_ad:k.muhasebeciAd||null,muhasebeci_unvan:k.muhasebeciUnvan||null
  };
  if(k.id){
    await fetch(SB_URL+'/rest/v1/edefter_kurum_bilgileri?id=eq.'+k.id,{method:'PATCH',headers:SB_HEADERS,body:JSON.stringify(satir)});
  }else{
    await fetch(SB_URL+'/rest/v1/edefter_kurum_bilgileri',{method:'POST',headers:SB_HEADERS,body:JSON.stringify(satir)});
  }
}

async function subeBilgileriYukle(otelId){
  try{
    const r=await fetch(SB_URL+'/rest/v1/edefter_sube_bilgileri?otel_id=eq.'+otelId+'&select=*',{headers:SB_HEADERS});
    if(!r.ok)return null;
    const d=await r.json();
    if(!d.length)return null;
    return{subeNo:d[0].sube_no||'',subeAdi:d[0].sube_adi||''};
  }catch(e){return null;}
}

async function subeBilgileriKaydet(otelId,subeNo,subeAdi){
  const mevcutR=await fetch(SB_URL+'/rest/v1/edefter_sube_bilgileri?otel_id=eq.'+otelId+'&select=otel_id',{headers:SB_HEADERS});
  const varMi=mevcutR.ok&&(await mevcutR.json()).length>0;
  const satir={sube_no:subeNo||null,sube_adi:subeAdi||null};
  if(varMi){
    await fetch(SB_URL+'/rest/v1/edefter_sube_bilgileri?otel_id=eq.'+otelId,{method:'PATCH',headers:SB_HEADERS,body:JSON.stringify(satir)});
  }else{
    await fetch(SB_URL+'/rest/v1/edefter_sube_bilgileri',{method:'POST',headers:SB_HEADERS,body:JSON.stringify({otel_id:otelId,...satir})});
  }
}

async function kurumBilgileriFormaDoldur(){
  kurumBilgi=await kurumBilgileriYukle();
  if(!kurumBilgi)return;
  document.getElementById('kb-vkn').value=kurumBilgi.vkn;
  document.getElementById('kb-unvan').value=kurumBilgi.unvan;
  document.getElementById('kb-bina').value=kurumBilgi.adresBinaNo;
  document.getElementById('kb-sokak').value=kurumBilgi.adresSokak;
  document.getElementById('kb-sehir').value=kurumBilgi.adresSehir;
  document.getElementById('kb-posta').value=kurumBilgi.adresPostaKodu;
  document.getElementById('kb-ulke').value=kurumBilgi.adresUlke;
  document.getElementById('kb-telefon').value=kurumBilgi.telefon;
  document.getElementById('kb-eposta').value=kurumBilgi.eposta;
  document.getElementById('kb-website').value=kurumBilgi.website;
  document.getElementById('kb-istanimi').value=kurumBilgi.isTanimi;
  document.getElementById('kb-myb').value=kurumBilgi.maliYilBaslangic;
  document.getElementById('kb-mye').value=kurumBilgi.maliYilBitis;
  document.getElementById('kb-muhad').value=kurumBilgi.muhasebeciAd;
  document.getElementById('kb-muhunvan').value=kurumBilgi.muhasebeciUnvan;
}

async function kurumBilgileriFormKaydet(){
  const k={
    id:kurumBilgi?.id,
    vkn:document.getElementById('kb-vkn').value.trim(),
    unvan:document.getElementById('kb-unvan').value.trim(),
    adresBinaNo:document.getElementById('kb-bina').value.trim(),
    adresSokak:document.getElementById('kb-sokak').value.trim(),
    adresSehir:document.getElementById('kb-sehir').value.trim(),
    adresPostaKodu:document.getElementById('kb-posta').value.trim(),
    adresUlke:document.getElementById('kb-ulke').value.trim(),
    telefon:document.getElementById('kb-telefon').value.trim(),
    eposta:document.getElementById('kb-eposta').value.trim(),
    website:document.getElementById('kb-website').value.trim(),
    isTanimi:document.getElementById('kb-istanimi').value.trim(),
    maliYilBaslangic:document.getElementById('kb-myb').value,
    maliYilBitis:document.getElementById('kb-mye').value,
    muhasebeciAd:document.getElementById('kb-muhad').value.trim(),
    muhasebeciUnvan:document.getElementById('kb-muhunvan').value.trim()
  };
  await kurumBilgileriKaydet(k);
  kurumBilgi=await kurumBilgileriYukle();
  toast('✅ Kurum bilgileri kaydedildi');
}
</script>
```

- [ ] **Step 3: Doğrula**

```bash
grep -n "function kurumBilgileriYukle\|function kurumBilgileriKaydet\|function subeBilgileriYukle\|function subeBilgileriKaydet\|function kurumBilgileriFormKaydet" muhasebe-edefter.html
```
Expected: 5 fonksiyon tanımı görünmeli.

- [ ] **Step 4: Commit**

```bash
git add muhasebe-edefter.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: add muhasebe-edefter.html skeleton with Kurum Bilgileri panel"
```

---

### Task 3: Şube Bilgileri alt-paneli + ortak XML yardımcı fonksiyonları

**Files:**
- Modify: `muhasebe-edefter.html`

**Interfaces:**
- Consumes: `OTEL_ISIMLERI`, `subeBilgileriYukle`, `subeBilgileriKaydet` (Task 2)
- Produces: `renderSubeAlani()`, `escapeXml(s)`, `buildDocumentInfoXml(tur,kurum,ayBaslangic,ayBitis)`, `buildEntityInfoXml(kurum,sube)`, `buildEDefterXml(tur,kurum,sube,ayBaslangic,ayBitis,entryHeadersXml)`, `indirXml(xmlIcerik,dosyaAdi)`, `kurumBilgileriDogrula(kurum)` — Task 4/5 bunları kullanacak.

- [ ] **Step 1: `renderSubeAlani()` fonksiyonunu ekle**

`kurumBilgileriFormKaydet` fonksiyonunun hemen ardına ekle:

```js
function renderSubeAlani(){
  const c=document.getElementById('sube-alani');
  c.innerHTML=Object.keys(OTEL_ISIMLERI).map(otelId=>`
    <div class="card">
      <div class="card-title">🏨 ${OTEL_ISIMLERI[otelId]} — Şube Bilgisi</div>
      <div class="rfields">
        <div class="field"><label>Şube No</label><input type="text" id="sube-no-${otelId}"></div>
        <div class="field"><label>Şube Adı</label><input type="text" id="sube-adi-${otelId}"></div>
      </div>
      <button class="btn btn-gray btn-block" onclick="subeFormKaydet('${otelId}')">💾 Kaydet</button>
    </div>
  `).join('');
  Object.keys(OTEL_ISIMLERI).forEach(async otelId=>{
    const s=await subeBilgileriYukle(otelId);
    if(s){
      document.getElementById('sube-no-'+otelId).value=s.subeNo;
      document.getElementById('sube-adi-'+otelId).value=s.subeAdi;
    }
  });
}

async function subeFormKaydet(otelId){
  const subeNo=document.getElementById('sube-no-'+otelId).value.trim();
  const subeAdi=document.getElementById('sube-adi-'+otelId).value.trim();
  await subeBilgileriKaydet(otelId,subeNo,subeAdi);
  toast('✅ '+OTEL_ISIMLERI[otelId]+' şube bilgisi kaydedildi');
}
```

- [ ] **Step 2: `kurumBilgileriFormaDoldur()` ve `renderSubeAlani()`'yı sayfa açılışında çağır**

Dosyanın en altındaki kapanış `</script>` etiketinden hemen önce ekle (Kurum Bilgileri sekmesi varsayılan olarak açık geldiği için, şube alanının da sayfa yüklenirken doldurulması gerekir — sadece sekme tıklanınca değil):

```js
(async function(){
  await kurumBilgileriFormaDoldur();
  renderSubeAlani();
})();
```

- [ ] **Step 3: XML yardımcı fonksiyonlarını ekle**

`subeFormKaydet` fonksiyonunun hemen ardına ekle:

```js
function escapeXml(s){return String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&apos;'}[c]));}

function kurumBilgileriDogrula(kurum){
  const hatalar=[];
  if(!kurum){hatalar.push('Kurum Bilgileri hiç girilmemiş — önce "Kurum Bilgileri" sekmesini doldurun.');return hatalar;}
  if(!kurum.vkn||kurum.vkn.length!==10)hatalar.push('VKN 10 haneli olmalı');
  if(!kurum.unvan)hatalar.push('Unvan zorunlu');
  if(!kurum.adresSehir)hatalar.push('Adres (şehir) zorunlu');
  if(!kurum.maliYilBaslangic||!kurum.maliYilBitis)hatalar.push('Mali yıl başlangıç/bitiş zorunlu');
  if(!kurum.muhasebeciAd)hatalar.push('Muhasebeci adı zorunlu');
  return hatalar;
}

function buildDocumentInfoXml(tur,kurum,ayBaslangic,ayBitis){
  const simdi=new Date().toISOString();
  const uniqueId=(tur==='yevmiye'?'YEV':'KEB')+kurum.vkn;
  return `<gl-cor:documentInfo>
<gl-cor:entriesType>${tur==='yevmiye'?'journal':'ledger'}</gl-cor:entriesType>
<gl-cor:uniqueID>${escapeXml(uniqueId)}</gl-cor:uniqueID>
<gl-cor:creationDate>${simdi}</gl-cor:creationDate>
<gl-cor:periodCoveredStart>${ayBaslangic}</gl-cor:periodCoveredStart>
<gl-cor:periodCoveredEnd>${ayBitis}</gl-cor:periodCoveredEnd>
<gl-bus:sourceApplication>Gurok ERP</gl-bus:sourceApplication>
</gl-cor:documentInfo>`;
}

function buildEntityInfoXml(kurum,sube){
  return `<gl-cor:entityInformation>
<gl-bus:entityPhoneNumber><gl-bus:phoneNumber>${escapeXml(kurum.telefon)}</gl-bus:phoneNumber></gl-bus:entityPhoneNumber>
<gl-bus:entityEmailAddressStructure><gl-bus:entityEmailAddress>${escapeXml(kurum.eposta)}</gl-bus:entityEmailAddress></gl-bus:entityEmailAddressStructure>
<gl-bus:organizationIdentifiers>
<gl-bus:organizationDescription>Kurum Unvanı</gl-bus:organizationDescription>
<gl-bus:organizationIdentifier>${escapeXml(kurum.unvan)}</gl-bus:organizationIdentifier>
</gl-bus:organizationIdentifiers>
<gl-bus:organizationIdentifiers>
<gl-bus:organizationDescription>Şube No</gl-bus:organizationDescription>
<gl-bus:organizationIdentifier>${escapeXml(sube.subeNo)}</gl-bus:organizationIdentifier>
</gl-bus:organizationIdentifiers>
<gl-bus:organizationIdentifiers>
<gl-bus:organizationDescription>Şube Adı</gl-bus:organizationDescription>
<gl-bus:organizationIdentifier>${escapeXml(sube.subeAdi)}</gl-bus:organizationIdentifier>
</gl-bus:organizationIdentifiers>
<gl-bus:organizationAddress>
<gl-bus:organizationBuildingNumber>${escapeXml(kurum.adresBinaNo)}</gl-bus:organizationBuildingNumber>
<gl-bus:organizationAddressStreet>${escapeXml(kurum.adresSokak)}</gl-bus:organizationAddressStreet>
<gl-bus:organizationAddressCity>${escapeXml(kurum.adresSehir)}</gl-bus:organizationAddressCity>
<gl-bus:organizationAddressZipOrPostalCode>${escapeXml(kurum.adresPostaKodu)}</gl-bus:organizationAddressZipOrPostalCode>
<gl-bus:organizationAddressCountry>${escapeXml(kurum.adresUlke)}</gl-bus:organizationAddressCountry>
</gl-bus:organizationAddress>
<gl-bus:entityWebSite><gl-bus:webSiteURL>${escapeXml(kurum.website)}</gl-bus:webSiteURL></gl-bus:entityWebSite>
<gl-bus:businessDescription>${escapeXml(kurum.isTanimi)}</gl-bus:businessDescription>
<gl-bus:fiscalYearStart>${kurum.maliYilBaslangic}</gl-bus:fiscalYearStart>
<gl-bus:fiscalYearEnd>${kurum.maliYilBitis}</gl-bus:fiscalYearEnd>
<gl-bus:accountantInformation>
<gl-bus:accountantName>${escapeXml(kurum.muhasebeciAd)}</gl-bus:accountantName>
<gl-bus:accountantEngagementTypeDescription>${escapeXml(kurum.muhasebeciUnvan)}</gl-bus:accountantEngagementTypeDescription>
</gl-bus:accountantInformation>
</gl-cor:entityInformation>`;
}

function buildEDefterXml(tur,kurum,sube,ayBaslangic,ayBitis,entryHeadersXml){
  return `<?xml version="1.0" encoding="UTF-8"?>
<edefter:defter xmlns:edefter="http://www.edefter.gov.tr" xmlns:xbrli="http://www.xbrl.org/2003/instance" xmlns:gl-cor="http://www.xbrl.org/int/gl/cor/2006-10-25" xmlns:gl-bus="http://www.xbrl.org/int/gl/bus/2006-10-25">
<xbrli:xbrl>
<xbrli:context id="c1">
<xbrli:entity>
<xbrli:identifier scheme="http://www.gib.gov.tr">${escapeXml(kurum.vkn)}</xbrli:identifier>
</xbrli:entity>
<xbrli:period><xbrli:startDate>${ayBaslangic}</xbrli:startDate><xbrli:endDate>${ayBitis}</xbrli:endDate></xbrli:period>
</xbrli:context>
<xbrli:unit id="TRY"><xbrli:measure>iso4217:TRY</xbrli:measure></xbrli:unit>
<gl-cor:accountingEntries>
${buildDocumentInfoXml(tur,kurum,ayBaslangic,ayBitis)}
${buildEntityInfoXml(kurum,sube)}
${entryHeadersXml}
</gl-cor:accountingEntries>
</xbrli:xbrl>
</edefter:defter>`;
}

function indirXml(xmlIcerik,dosyaAdi){
  const blob=new Blob([xmlIcerik],{type:'application/xml'});
  const url=URL.createObjectURL(blob);
  const a=document.createElement('a');
  a.href=url;a.download=dosyaAdi;
  document.body.appendChild(a);a.click();document.body.removeChild(a);
  URL.revokeObjectURL(url);
}

// ay: "YYYY-MM" formatında. Döner: {ayBaslangic:"YYYY-MM-DD", ayBitis:"YYYY-MM-DD", ayBasMs, ayBitMs}
function ayAraligiHesapla(ay){
  const [yil,ayNo]=ay.split('-');
  const ayBaslangic=`${yil}-${ayNo}-01`;
  const sonGun=new Date(parseInt(yil),parseInt(ayNo),0).getDate();
  const ayBitis=`${yil}-${ayNo}-${String(sonGun).padStart(2,'0')}`;
  return{
    yil,ayNo,ayBaslangic,ayBitis,
    ayBasMs:new Date(ayBaslangic).getTime(),
    ayBitMs:new Date(ayBitis+'T23:59:59').getTime()
  };
}
```

- [ ] **Step 4: Doğrula**

```bash
grep -n "function renderSubeAlani\|function buildDocumentInfoXml\|function buildEntityInfoXml\|function buildEDefterXml\|function indirXml\|function ayAraligiHesapla\|function kurumBilgileriDogrula" muhasebe-edefter.html
```
Expected: 7 fonksiyon tanımı görünmeli.

- [ ] **Step 5: Commit**

```bash
git add muhasebe-edefter.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: add Sube Bilgileri panel and shared XBRL-GL XML builder helpers"
```

---

### Task 4: Yevmiye XML üretimi

**Files:**
- Modify: `muhasebe-edefter.html`

**Interfaces:**
- Consumes: `buildEDefterXml`, `buildDocumentInfoXml`, `buildEntityInfoXml`, `escapeXml`, `indirXml`, `ayAraligiHesapla`, `kurumBilgileriDogrula`, `kurumBilgi`, `subeBilgileriYukle`, `OTEL_ISIMLERI`, `round2`, `toast`, `sLD`/`hLD` (Task 1-3)
- Produces: `loadDB()` (yevmiye_fisler + hesap_plani yükler, `yevmiyeler`/`hesapPlani` global state'ini doldurur), `renderYevXmlAlani()`, `yevmiyeXmlOlustur()`, `yevmiyeDogrula(fisler)`, `buildYevmiyeEntryHeader`, `buildEntryDetail` — Task 5 `buildEntryDetail`'ı kullanacak.

- [ ] **Step 1: `loadDB()` fonksiyonunu ekle (yevmiye_fisler + hesap_plani)**

`ayAraligiHesapla` fonksiyonunun hemen ardına ekle:

```js
function yevSbdenCamele(r){
  return{
    id:r.id,no:r.no,tarih:r.tarih?new Date(r.tarih).getTime():Date.now(),
    tarihStr:r.tarih,tip:r.tip,belge:r.belge_no||'',aciklama:r.aciklama||'',
    otelId:r.otel_id,toplamBorc:parseFloat(r.toplam_borc)||0,toplamAlacak:parseFloat(r.toplam_alacak)||0,
    onaylandi:!!r.onaylandi,otomatik:!!r.otomatik,
    kalemler:(r.yevmiye_kalemleri||[]).map(k=>({
      hesapKod:k.hesap_kodu,aciklama:k.aciklama||'',borc:parseFloat(k.borc)||0,alacak:parseFloat(k.alacak)||0
    }))
  };
}

async function loadDB(){
  sLD();
  try{
    const [yR,hR]=await Promise.all([
      fetch(SB_URL+'/rest/v1/yevmiye_fisler?select=*,yevmiye_kalemleri(*)',{headers:SB_HEADERS}),
      fetch(SB_URL+'/rest/v1/hesap_plani?select=kod,ad',{headers:SB_HEADERS}),
    ]);
    yevmiyeler={};hesapPlani={};
    if(yR.ok){(await yR.json()).forEach(r=>{yevmiyeler[r.id]=yevSbdenCamele(r);});}
    if(hR.ok){(await hR.json()).forEach(r=>{hesapPlani[r.kod.replace(/\./g,'_')]={kod:r.kod,ad:r.ad};});}
  }catch(e){console.warn(e);}
  hLD();
}
```

- [ ] **Step 2: Yevmiye doğrulama ve XML satır üretim fonksiyonlarını ekle**

`loadDB` fonksiyonunun hemen ardına ekle:

```js
function yevmiyeDogrula(fisler){
  const hatalar=[];
  fisler.forEach(f=>{
    const borc=round2(f.kalemler.reduce((t,k)=>t+(k.borc||0),0));
    const alacak=round2(f.kalemler.reduce((t,k)=>t+(k.alacak||0),0));
    if(borc!==alacak)hatalar.push(`${f.no}: Borç (${borc}) ≠ Alacak (${alacak})`);
    if(f.kalemler.length<2)hatalar.push(`${f.no}: En az 2 kalem olmalı (${f.kalemler.length} bulundu)`);
    f.kalemler.forEach(k=>{
      if(!k.hesapKod||k.hesapKod.length<3||k.hesapKod.length>4)hatalar.push(`${f.no}: Geçersiz hesap kodu "${k.hesapKod}" (3-4 karakter olmalı)`);
    });
  });
  return hatalar;
}

function buildEntryDetail(kalem,lineNo,entryCounter,fisNo,tarihStr){
  const hesapAd=hesapPlani[kalem.hesapKod.replace(/\./g,'_')]?.ad||'';
  const tutar=kalem.borc>0?kalem.borc:kalem.alacak;
  const yon=kalem.borc>0?'D':'C';
  return `<gl-cor:entryDetail>
<gl-cor:lineNumber>${lineNo}</gl-cor:lineNumber>
<gl-cor:lineNumberCounter>${entryCounter}</gl-cor:lineNumberCounter>
<gl-cor:account>
<gl-cor:accountMainID>${escapeXml(kalem.hesapKod)}</gl-cor:accountMainID>
<gl-cor:accountMainDescription>${escapeXml(hesapAd)}</gl-cor:accountMainDescription>
</gl-cor:account>
<gl-cor:amount decimals="INF">${tutar.toFixed(2)}</gl-cor:amount>
<gl-cor:debitCreditCode>${yon}</gl-cor:debitCreditCode>
<gl-cor:postingDate>${tarihStr}</gl-cor:postingDate>
<gl-cor:documentType>other</gl-cor:documentType>
<gl-cor:documentTypeDescription>Muhasebe Fişi</gl-cor:documentTypeDescription>
<gl-cor:documentNumber>${escapeXml(fisNo)}</gl-cor:documentNumber>
<gl-cor:documentDate>${tarihStr}</gl-cor:documentDate>
<gl-cor:documentReference>${escapeXml(fisNo)}</gl-cor:documentReference>
</gl-cor:entryDetail>`;
}

function buildYevmiyeEntryHeader(fis,counter){
  const kalemlerXml=fis.kalemler.map((k,i)=>buildEntryDetail(k,i+1,counter,fis.no,fis.tarihStr)).join('\n');
  return `<gl-cor:entryHeader>
<gl-cor:entryNumber>${escapeXml(fis.no)}</gl-cor:entryNumber>
<gl-cor:entryNumberCounter>${counter}</gl-cor:entryNumberCounter>
<gl-cor:enteredBy>${escapeXml(OTURUM_KULLANICI?.ad||'Sistem')}</gl-cor:enteredBy>
<gl-cor:enteredDate>${fis.tarihStr}</gl-cor:enteredDate>
<gl-bus:totalDebit>${fis.toplamBorc.toFixed(2)}</gl-bus:totalDebit>
<gl-bus:totalCredit>${fis.toplamAlacak.toFixed(2)}</gl-bus:totalCredit>
${kalemlerXml}
</gl-cor:entryHeader>`;
}
```

- [ ] **Step 3: `donemAcikMi` fonksiyonunu ekle**

`buildYevmiyeEntryHeader` fonksiyonunun hemen ardına ekle (`muhasebe-yevmiye.html`'deki ile birebir aynı):

```js
async function donemAcikMi(tarihMs){
  try{
    const r=await fetch(SB_URL+'/rest/v1/mali_donemler?select=*',{headers:SB_HEADERS});
    if(!r.ok)return{acik:true};
    const donemler=await r.json();
    if(!donemler||!donemler.length)return{acik:true};
    for(const don of donemler){
      const bas=new Date(don.baslangic).getTime();
      const bit=new Date(don.bitis+'T23:59:59').getTime();
      if(tarihMs>=bas&&tarihMs<=bit)return{acik:don.durum!=='kapali',donem:don};
    }
    return{acik:true};
  }catch(e){return{acik:true};}
}
```

- [ ] **Step 4: Yevmiye XML sekmesinin UI'ını ve üretim fonksiyonunu ekle**

`donemAcikMi` fonksiyonunun hemen ardına ekle:

```js
function renderYevXmlAlani(){
  const c=document.getElementById('yevxml-alani');
  c.innerHTML=`
    <div class="uyari-serit">⚠️ İMZASIZ TASLAK — GİB'e yüklemeden önce mali mühür ile imzalanmalı</div>
    <div class="card">
      <div class="card-title">📒 Yevmiye Defteri XML</div>
      <div class="field"><label>Ay</label><input type="month" id="yxml-ay"></div>
      <div class="field"><label>Otel</label><select id="yxml-otel">${Object.keys(OTEL_ISIMLERI).map(id=>`<option value="${id}">${OTEL_ISIMLERI[id]}</option>`).join('')}</select></div>
      <button class="btn btn-primary btn-block" onclick="yevmiyeXmlOlustur()">📥 XML Oluştur ve İndir</button>
    </div>`;
}

async function yevmiyeXmlOlustur(){
  const ay=document.getElementById('yxml-ay').value;
  const otelId=document.getElementById('yxml-otel').value;
  if(!ay){toast('⚠️ Ay seçin');return;}

  await loadDB();
  kurumBilgi=await kurumBilgileriYukle();
  const kHatalar=kurumBilgileriDogrula(kurumBilgi);
  if(kHatalar.length){toast('❌ '+kHatalar[0]);return;}

  const sube=await subeBilgileriYukle(otelId);
  if(!sube||!sube.subeNo){toast('❌ Bu otel için Şube Bilgisi girilmemiş (Kurum Bilgileri sekmesi)');return;}

  const{yil,ayNo,ayBaslangic,ayBitis,ayBasMs,ayBitMs}=ayAraligiHesapla(ay);

  let fisler=Object.values(yevmiyeler).filter(f=>f.otelId===otelId&&f.tarih>=ayBasMs&&f.tarih<=ayBitMs);
  const taslakSayisi=fisler.filter(f=>!f.onaylandi).length;
  fisler=fisler.filter(f=>f.onaylandi).sort((a,b)=>a.tarih-b.tarih);

  if(!fisler.length){toast('⚠️ Seçilen ayda onaylı fiş bulunamadı');return;}

  const hatalar=yevmiyeDogrula(fisler);
  if(hatalar.length){
    alert('XML üretilemedi, düzeltilmesi gereken sorunlar:\n\n'+hatalar.join('\n'));
    return;
  }

  const donemDurum=await donemAcikMi(ayBasMs);
  if(donemDurum.acik){
    if(!confirm(`⚠️ ${ay} dönemi henüz kapatılmamış. Yine de devam edilsin mi?`))return;
  }

  const entryHeadersXml=fisler.map((f,i)=>buildYevmiyeEntryHeader(f,i+1)).join('\n');
  const xml=buildEDefterXml('yevmiye',kurumBilgi,sube,ayBaslangic,ayBitis,entryHeadersXml);

  indirXml(xml,`yevmiye-${kurumBilgi.vkn}-${yil}${ayNo}-imzasiz.xml`);
  toast(taslakSayisi?`✅ XML oluşturuldu (${taslakSayisi} taslak fiş dahil edilmedi)`:'✅ XML oluşturuldu');
}
```

- [ ] **Step 5: `(async function(){...})()` başlangıç bloğunu güncelle**

Mevcut:
```js
(async function(){
  await kurumBilgileriFormaDoldur();
  renderSubeAlani();
})();
```
şuna çevir:
```js
(async function(){
  await loadDB();
  await kurumBilgileriFormaDoldur();
  renderSubeAlani();
})();
```

- [ ] **Step 6: Doğrula**

```bash
grep -n "function loadDB\|function yevmiyeDogrula\|function buildYevmiyeEntryHeader\|function buildEntryDetail\|function donemAcikMi\|function renderYevXmlAlani\|function yevmiyeXmlOlustur" muhasebe-edefter.html
```
Expected: 7 fonksiyon tanımı görünmeli.

- [ ] **Step 7: Kod okuyarak izleme**

`buildEntryDetail`'in ürettiği alan adlarının (`accountMainID`, `debitCreditCode`, `documentReference` vb.) Task 3'teki `buildEntityInfoXml`/`buildDocumentInfoXml` ile aynı namespace önekini (`gl-cor:`/`gl-bus:`) kullandığını, ve `yevmiyeDogrula`'nın spec'teki "Doğrulama" bölümünde listelenen kontrollerin (borç=alacak, min 2 kalem, hesap kodu 3-4 karakter) hepsini kapsadığını satır satır doğrula.

- [ ] **Step 8: Commit**

```bash
git add muhasebe-edefter.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: add Yevmiye XBRL-GL XML generation"
```

---

### Task 5: Kebir XML üretimi

**Files:**
- Modify: `muhasebe-edefter.html`

**Interfaces:**
- Consumes: `buildEDefterXml`, `buildEntryDetail`, `escapeXml`, `indirXml`, `ayAraligiHesapla`, `kurumBilgileriDogrula`, `donemAcikMi`, `round2`, `yevmiyeler`, `hesapPlani`, `kurumBilgi`, `subeBilgileriYukle`, `loadDB` (Task 1-4)
- Produces: `renderKebXmlAlani()`, `kebirXmlOlustur()`, `kebirGrupla(fisler)`, `buildKebirEntryHeader(hesapKod,hareketler,counter)`

- [ ] **Step 1: Kebir gruplama ve XML üretim fonksiyonlarını ekle**

`yevmiyeXmlOlustur` fonksiyonunun hemen ardına ekle:

```js
// fisler: onaylı yevmiye fişleri dizisi. Döner: {hesapKod: [{borc,alacak,fisNo,tarihStr}, ...]}
function kebirGrupla(fisler){
  const gruplar={};
  fisler.forEach(f=>{
    f.kalemler.forEach(k=>{
      if(!gruplar[k.hesapKod])gruplar[k.hesapKod]=[];
      gruplar[k.hesapKod].push({hesapKod:k.hesapKod,borc:k.borc,alacak:k.alacak,fisNo:f.no,tarihStr:f.tarihStr});
    });
  });
  return gruplar;
}

function buildKebirEntryHeader(hesapKod,hareketler,counter){
  const toplamBorc=round2(hareketler.reduce((t,h)=>t+(h.borc||0),0));
  const toplamAlacak=round2(hareketler.reduce((t,h)=>t+(h.alacak||0),0));
  const detaylarXml=hareketler.map((h,i)=>buildEntryDetail(h,i+1,counter,h.fisNo,h.tarihStr)).join('\n');
  return `<gl-cor:entryHeader>
<gl-cor:entryNumber>${escapeXml(hesapKod)}</gl-cor:entryNumber>
<gl-cor:entryNumberCounter>${counter}</gl-cor:entryNumberCounter>
<gl-cor:enteredBy>${escapeXml(OTURUM_KULLANICI?.ad||'Sistem')}</gl-cor:enteredBy>
<gl-cor:enteredDate>${hareketler[0].tarihStr}</gl-cor:enteredDate>
<gl-bus:totalDebit>${toplamBorc.toFixed(2)}</gl-bus:totalDebit>
<gl-bus:totalCredit>${toplamAlacak.toFixed(2)}</gl-bus:totalCredit>
${detaylarXml}
</gl-cor:entryHeader>`;
}
```

**Not:** Yevmiye'nin "en az 2 entryDetail" kuralı (Schematron kod 11610) sadece Yevmiye şeması için doğrulanabildi; Kebir'in tam Schematron içeriği bu ortamda incelenemedi, bu yüzden Kebir'de aynı kural zorunlu tutulmuyor (bir hesabın ayda tek hareketi olması mümkün).

- [ ] **Step 2: Kebir XML sekmesinin UI'ını ve üretim fonksiyonunu ekle**

`buildKebirEntryHeader` fonksiyonunun hemen ardına ekle:

```js
function renderKebXmlAlani(){
  const c=document.getElementById('kebxml-alani');
  c.innerHTML=`
    <div class="uyari-serit">⚠️ İMZASIZ TASLAK — GİB'e yüklemeden önce mali mühür ile imzalanmalı</div>
    <div class="card">
      <div class="card-title">📗 Defteri Kebir XML</div>
      <div class="field"><label>Ay</label><input type="month" id="kxml-ay"></div>
      <div class="field"><label>Otel</label><select id="kxml-otel">${Object.keys(OTEL_ISIMLERI).map(id=>`<option value="${id}">${OTEL_ISIMLERI[id]}</option>`).join('')}</select></div>
      <button class="btn btn-primary btn-block" onclick="kebirXmlOlustur()">📥 XML Oluştur ve İndir</button>
    </div>`;
}

async function kebirXmlOlustur(){
  const ay=document.getElementById('kxml-ay').value;
  const otelId=document.getElementById('kxml-otel').value;
  if(!ay){toast('⚠️ Ay seçin');return;}

  await loadDB();
  kurumBilgi=await kurumBilgileriYukle();
  const kHatalar=kurumBilgileriDogrula(kurumBilgi);
  if(kHatalar.length){toast('❌ '+kHatalar[0]);return;}

  const sube=await subeBilgileriYukle(otelId);
  if(!sube||!sube.subeNo){toast('❌ Bu otel için Şube Bilgisi girilmemiş (Kurum Bilgileri sekmesi)');return;}

  const{yil,ayNo,ayBaslangic,ayBitis,ayBasMs,ayBitMs}=ayAraligiHesapla(ay);

  let fisler=Object.values(yevmiyeler).filter(f=>f.otelId===otelId&&f.tarih>=ayBasMs&&f.tarih<=ayBitMs);
  const taslakSayisi=fisler.filter(f=>!f.onaylandi).length;
  fisler=fisler.filter(f=>f.onaylandi).sort((a,b)=>a.tarih-b.tarih);

  if(!fisler.length){toast('⚠️ Seçilen ayda onaylı fiş bulunamadı');return;}

  const donemDurum=await donemAcikMi(ayBasMs);
  if(donemDurum.acik){
    if(!confirm(`⚠️ ${ay} dönemi henüz kapatılmamış. Yine de devam edilsin mi?`))return;
  }

  const gruplar=kebirGrupla(fisler);
  const hesapKodlari=Object.keys(gruplar).sort();
  const entryHeadersXml=hesapKodlari.map((kod,i)=>buildKebirEntryHeader(kod,gruplar[kod],i+1)).join('\n');
  const xml=buildEDefterXml('kebir',kurumBilgi,sube,ayBaslangic,ayBitis,entryHeadersXml);

  indirXml(xml,`kebir-${kurumBilgi.vkn}-${yil}${ayNo}-imzasiz.xml`);
  toast(taslakSayisi?`✅ XML oluşturuldu (${taslakSayisi} taslak fiş dahil edilmedi)`:'✅ XML oluşturuldu');
}
```

- [ ] **Step 3: Doğrula**

```bash
grep -n "function kebirGrupla\|function buildKebirEntryHeader\|function renderKebXmlAlani\|function kebirXmlOlustur" muhasebe-edefter.html
```
Expected: 4 fonksiyon tanımı görünmeli.

- [ ] **Step 4: Kod okuyarak izleme**

`kebirXmlOlustur`'un `kebirGrupla` ile ürettiği grupları hesap koduna göre sıralı işlediğini (`hesapKodlari.sort()`), ve her `entryHeader`'ın `entryNumberCounter`'ının 1'den başlayan ardışık bir sayı olduğunu (Yevmiye'deki aynı kuralın Kebir'e de uygulandığını) doğrula.

- [ ] **Step 5: Commit**

```bash
git add muhasebe-edefter.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: add Kebir XBRL-GL XML generation"
```

---

### Task 6: muhasebe.html menü kartı + uçtan uca doğrulama

**Files:**
- Modify: `muhasebe.html:74-79` (modül kartları arasına)

**Interfaces:**
- Consumes: mevcut `.modul-kart` HTML deseni (değişmez)

- [ ] **Step 1: Menü kartını ekle**

Mevcut (satır 74-79 civarı, `muhasebe-yevmiye.html` kartından hemen sonra):
```html
    <a class="modul-kart" href="muhasebe-yevmiye.html">
      <div class="modul-ikon" style="background:#ede9fe">📒</div>
      <div class="modul-ad">Yevmiye</div>
      <div class="modul-desc">Günlük kayıtlar, mizan</div>
    </a>
    <a class="modul-kart" href="muhasebe-banka.html">
```
şuna çevir:
```html
    <a class="modul-kart" href="muhasebe-yevmiye.html">
      <div class="modul-ikon" style="background:#ede9fe">📒</div>
      <div class="modul-ad">Yevmiye</div>
      <div class="modul-desc">Günlük kayıtlar, mizan</div>
    </a>
    <a class="modul-kart" href="muhasebe-edefter.html">
      <div class="modul-ikon" style="background:#dbeafe">📑</div>
      <div class="modul-ad">e-Defter</div>
      <div class="modul-desc">Yevmiye/Kebir XML (imzasız)</div>
    </a>
    <a class="modul-kart" href="muhasebe-banka.html">
```

- [ ] **Step 2: Doğrula**

```bash
grep -n "muhasebe-edefter.html" muhasebe.html
```
Expected: 1 satır (yeni kart).

- [ ] **Step 3: Uçtan uca alan adı tutarlılığı kontrolü**

```bash
grep -n "gl-cor:\|gl-bus:" muhasebe-edefter.html | grep -oE "gl-(cor|bus):[a-zA-Z]+" | sort -u
```
Expected: Çıktıdaki her elemanın (`gl-cor:accountMainID`, `gl-bus:totalDebit`, vb.) tasarım belgesindeki (`docs/superpowers/specs/2026-07-13-edefter-yevmiye-kebir-design.md`) şema ağacında karşılığı olduğunu gözle karşılaştır — fazladan/eksik bir eleman adı varsa düzelt.

- [ ] **Step 4: Kullanıcıya manuel test adımlarını bildir**

Kullanıcının tarayıcıda doğrulaması gereken akış (Node/Python bu ortamda yok, gerçek GİB Schematron/XSD validasyonu da yapılamıyor):
1. Task 1'deki SQL'i Supabase SQL Editor'de çalıştır.
2. `muhasebe-edefter.html` → Kurum Bilgileri sekmesi → firma bilgilerini ve her iki otelin şube bilgisini doldur, kaydet.
3. Yevmiye XML sekmesi → onaylı fişi olan bir ay seç → "XML Oluştur ve İndir" → dosyanın indiğini, adının `-imzasiz.xml` ile bittiğini doğrula.
4. İndirilen XML'i bir metin editöründe aç, `<edefter:defter>` kök elemanının, `xbrli:context/xbrli:entity/xbrli:identifier`'ın VKN içerdiğini, `entryHeader`/`entryDetail` sayılarının seçilen aydaki fiş/kalem sayısıyla eştiğini gözle kontrol et.
5. Kebir XML sekmesi → aynı ay/otel → "XML Oluştur ve İndir" → dosyanın indiğini, hesap bazında gruplandığını doğrula.
6. **Mutlaka bir mali müşavir veya lisanslı e-Defter yazılımıyla son doğrulama/imzalama yaptır** — bu XML'ler imzasız taslaktır, doğrudan GİB'e yüklenemez.

- [ ] **Step 5: Kullanıcıdan onay al, sonra push**

```bash
git fetch
git log --oneline main..origin/main
```
Expected: paralel oturumdan gelen değişiklik var mı kontrol et, varsa kullanıcıya bildir. Yoksa kullanıcı onayıyla `git push`.
