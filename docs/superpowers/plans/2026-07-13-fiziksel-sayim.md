# Fiziksel Sayım (Cycle Count) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `stok-takip.html`'e, sayım oluşturma → onay iki aşamalı bir fiziksel sayım (cycle count) akışı eklemek; stok düzeltmesi sadece `cost_control` rolünün onayından sonra uygulanır.

**Architecture:** Mevcut bottom-nav (`switchTab`) desenine yeni bir "Sayım" sekmesi eklenir. Sayım oluşturma mevcut `renderStok()`'un filtreleme mantığını (arama+kategori) yeniden kullanır. Onay sonrası stok güncellemesi, mevcut `giris()`/`cikis()`/`saveStok()`/`saveHareket()` fonksiyonları üzerinden yapılır — yeni bir stok-yazma yolu icat edilmez.

**Tech Stack:** Vanilla HTML/JS, Supabase REST (fetch) — build aracı/test çerçevesi yok.

## Global Constraints

- Stok miktarı SADECE onay sonrası değişir; sayım oluşturma aşamasında `stok` tablosuna hiçbir yazma yapılmaz (spec).
- Mutlak fark yüzdesi >%10 olan satırlarda açıklama zorunlu, altındakilerde isteğe bağlı (spec).
- Sayım oluşturma rolleri: `yonetici`, `depo`, `cost_control`. Onaylama: **sadece `cost_control`** — `yonetici` dahi onaylayamaz (spec).
- Onay anında her ürünün sistem miktarı Supabase'den YENİDEN okunur (bayat veri kontrolü); sayım oluşturma anındaki donmuş değer kullanılmaz (spec).
- Alt hesap/raf/lokasyon seviyesi kapsam dışı — depo bazlı sayım (spec).

---

### Task 1: Supabase şema değişikliği (kullanıcı tarafından çalıştırılır)

**Files:**
- Modify: Supabase SQL Editor (kod tabanında dosya yok)

**Interfaces:**
- Produces: `sayim_oturumlari` tablosu, `sayim_detaylari` tablosu — Task 4/5'in yazma/okuma işlemleri bu tablolara.

- [ ] **Step 1: Kullanıcıya SQL'i ver, Supabase SQL Editor'de çalıştırmasını iste**

```sql
CREATE TABLE IF NOT EXISTS sayim_oturumlari (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  depo_kodu text NOT NULL,
  otel_id text,
  olusturma_tarihi timestamptz DEFAULT now(),
  olusturan_ad text,
  durum text DEFAULT 'onay_bekliyor',
  onaylayan_ad text,
  onay_tarihi timestamptz,
  toplam_urun_sayisi integer DEFAULT 0,
  farkli_urun_sayisi integer DEFAULT 0,
  genel_not text,
  red_nedeni text
);

CREATE TABLE IF NOT EXISTS sayim_detaylari (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  oturum_id uuid REFERENCES sayim_oturumlari(id),
  urun_kodu text NOT NULL,
  urun_adi text,
  birim text,
  sistem_miktar numeric DEFAULT 0,
  sayilan_miktar numeric DEFAULT 0,
  fark numeric DEFAULT 0,
  fark_yuzde numeric DEFAULT 0,
  aciklama text
);
```

- [ ] **Step 2: Kullanıcı çalıştırdıktan sonra doğrula**

```bash
curl -s "https://xwytofysmgqtqjzkplfi.supabase.co/rest/v1/sayim_oturumlari?select=id&limit=1" -H "apikey: <SB_KEY>" -H "Authorization: Bearer <SB_KEY>"
curl -s "https://xwytofysmgqtqjzkplfi.supabase.co/rest/v1/sayim_detaylari?select=id&limit=1" -H "apikey: <SB_KEY>" -H "Authorization: Bearer <SB_KEY>"
```
Expected: İkisi de `200` ve `[]` döner.

---

### Task 2: "Sayım" sekmesi iskeleti + rol genişletme

**Files:**
- Modify: `stok-takip.html:135-144` (header alanı sonrası, yeni tab div eklenir)
- Modify: `stok-takip.html:247-260` (bottom-nav)
- Modify: `stok-takip.html:1540-1546` (`switchTab`)
- Modify: `stok-takip.html:1565` (`requireRole`)

**Interfaces:**
- Produces: `#tab-sayim` div, `#nav-sayim` buton, `switchTab('sayim')` desteği — Task 3/4/5 bu iskelet içine render eder.

- [ ] **Step 1: `requireRole` çağrısına `cost_control` ekle**

Mevcut (satır 1565):
```js
  if(!requireRole(currentUser, ['yonetici','depo'])) return;
```
şuna çevir:
```js
  if(!requireRole(currentUser, ['yonetici','depo','cost_control'])) return;
```

- [ ] **Step 2: Bottom-nav'a "Sayım" butonu ekle**

Mevcut (satır 258-260 civarı, `nav-iade` butonunun hemen ardına — dosyanın gerçek son nav-btn'i neyse ona bak, `İade Başlat` bu son eleman olmalı):
```html
    <button class="nav-btn" id="nav-iade" onclick="switchTab('iade')">
      <span class="nav-icon">↩️</span><span class="nav-label">İade Başlat</span>
    </button>
  </nav>
```
şuna çevir:
```html
    <button class="nav-btn" id="nav-iade" onclick="switchTab('iade')">
      <span class="nav-icon">↩️</span><span class="nav-label">İade Başlat</span>
    </button>
    <button class="nav-btn" id="nav-sayim" onclick="switchTab('sayim')">
      <span class="nav-icon">📊</span><span class="nav-label">Sayım</span>
      <span class="nav-badge" id="sayim-onay-badge" style="display:none;"></span>
    </button>
  </nav>
```

- [ ] **Step 3: `switchTab` dizisine `'sayim'` ekle**

Mevcut (satır 1540-1546):
```js
function switchTab(tab){
  ['stok','hareketler','ln','iade'].forEach(t=>{
    document.getElementById('tab-'+t).style.display=t===tab?'flex':'none';
    document.getElementById('nav-'+t).classList.toggle('active',t===tab);
  });
  if(tab==='hareketler')renderHareketler();
}
```
şuna çevir:
```js
function switchTab(tab){
  ['stok','hareketler','ln','iade','sayim'].forEach(t=>{
    document.getElementById('tab-'+t).style.display=t===tab?'flex':'none';
    document.getElementById('nav-'+t).classList.toggle('active',t===tab);
  });
  if(tab==='hareketler')renderHareketler();
  if(tab==='sayim')renderSayimTab();
}
```

- [ ] **Step 4: `#tab-sayim` div'ini ekle**

`#tab-iade` (satır 182'de açılıyor) tüm içeriğiyle birlikte biter ve hemen ardından `<nav class="bottom-nav">` (satır 247) başlar. Yeni `#tab-sayim` div'ini, `<nav class="bottom-nav">` satırının HEMEN ÖNÜNE ekle (yani `#tab-iade`'nin kapanış `</div>`'inden sonra, `<nav ...>`'dan önce):

```html
  <!-- SAYIM TAB -->
  <div class="scroll-content" id="tab-sayim" style="display:none;flex-direction:column;">
    <div class="filter-tabs" id="sayim-gorunum-tabs" style="display:none">
      <button class="filter-tab active" onclick="sayimGorunumDegistir('yeni',this)">📝 Yeni Sayım</button>
      <button class="filter-tab" onclick="sayimGorunumDegistir('onay',this)">✅ Onay Bekleyen</button>
    </div>
    <div id="sayim-yeni-alani">
      <div class="search-bar">
        <input type="text" id="sayim-search" placeholder="Ürün adı veya LN kodu ara..." oninput="renderSayimYeni()">
        <span class="search-icon">🔍</span>
      </div>
      <div class="filter-tabs" id="sayim-kat-tabs"></div>
      <div id="sayim-liste"></div>
      <button class="btn btn-primary btn-block" style="margin-top:10px" onclick="sayimTamamla()">✅ Sayımı Tamamla</button>
    </div>
    <div id="sayim-onay-alani" style="display:none">
      <div id="sayim-onay-liste"></div>
    </div>
  </div>
```

- [ ] **Step 5: Doğrula**

```bash
grep -n "id=\"tab-sayim\"\|id=\"nav-sayim\"\|switchTab('sayim')\|cost_control" stok-takip.html
```
Expected: `#tab-sayim`, `#nav-sayim`, en az bir `switchTab('sayim')` referansı ve `requireRole` satırında `cost_control` görünmeli.

- [ ] **Step 6: Commit**

```bash
git add stok-takip.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: add Sayim tab skeleton to stok-takip.html, widen role to cost_control"
```

---

### Task 3: Yeni Sayım listesi — filtre + canlı fark hesaplama

**Files:**
- Modify: `stok-takip.html` — yeni fonksiyonlar, `switchTab`'ın hemen sonrasına eklenir.

**Interfaces:**
- Consumes: `db.stok[aktifDepoId]` (`{lnKod,urunAd,miktar,birim}`), `escapeHtml()`, `aktifDepoId` (mevcut globaller)
- Produces: `round2(n)`, `sayimGorunumDegistir(g,el)`, `renderSayimTab()`, `filterSayimKat(k,el)`, `renderSayimYeni()`, `sayimFarkGuncelle(lnKod,val)`, `sayimAciklamaGuncelle(lnKod,val)` — Task 4/5 bunları kullanacak. Global state: `sayimSatirlari`, `sayimKatFilter`, `sayimGorunum`, `_sayimSistemMiktar`, `_sayimUrunAdi`, `_sayimBirim`, `SAYIM_ESIK_YUZDE`.

**Not:** Sayım ekranı sadece arama+kategori filtresini kullanır (mevcut Stok sekmesindeki kritik/uyarı/normal durum filtresi burada YOK) — sayım kapsamı "hangi ürünleri fiziksel olarak sayacağım" sorusuna cevap verir, stok durumu bu kararla ilgisiz, bilinçli bir kapsam daraltmasıdır.

- [ ] **Step 1: Global state ve `round2` yardımcı fonksiyonunu ekle**

`switchTab` fonksiyonunun hemen ardına ekle:

```js
const SAYIM_ESIK_YUZDE=10;
let sayimSatirlari={}; // {lnKod:{sayilan,fark,farkYuzde,aciklama}}
let sayimKatFilter='tumu';
let sayimGorunum='yeni'; // 'yeni' | 'onay'
let _sayimSistemMiktar={},_sayimUrunAdi={},_sayimBirim={};
function round2(n){return Math.round(((parseFloat(n)||0)+Number.EPSILON)*100)/100;}
```

- [ ] **Step 2: Görünüm değiştirme ve ana render fonksiyonlarını ekle**

Az önce eklenen bloğun hemen ardına ekle:

```js
function sayimGorunumDegistir(g,el){
  sayimGorunum=g;
  document.querySelectorAll('#sayim-gorunum-tabs .filter-tab').forEach(t=>t.classList.remove('active'));
  if(el)el.classList.add('active');
  document.getElementById('sayim-yeni-alani').style.display=g==='yeni'?'block':'none';
  document.getElementById('sayim-onay-alani').style.display=g==='onay'?'block':'none';
  if(g==='onay')sayimOnayBekleyenleriYukle();
}

function renderSayimTab(){
  const costControlMi=currentUser?.rol==='cost_control';
  document.getElementById('sayim-gorunum-tabs').style.display=costControlMi?'flex':'none';
  if(!costControlMi){sayimGorunumDegistir('yeni',null);}
  sayimSatirlari={};
  renderSayimYeni();
  if(costControlMi)sayimOnayBekleyenSayisiGuncelle();
}

function filterSayimKat(k,el){
  sayimKatFilter=k;
  document.querySelectorAll('#sayim-kat-tabs .filter-tab').forEach(t=>t.classList.remove('active'));
  el.classList.add('active');
  sayimSatirlari={};
  renderSayimYeni();
}
```

- [ ] **Step 3: Liste render fonksiyonunu ekle**

Az önce eklenen bloğun hemen ardına ekle:

```js
function renderSayimYeni(){
  const depoStok=db.stok[aktifDepoId]||{};
  const items=Object.values(depoStok);
  const search=(document.getElementById('sayim-search')?.value||'').toLowerCase();

  const katSet=new Set();
  items.forEach(s=>{if(s.lnKod)katSet.add(s.lnKod.slice(0,5));});
  document.getElementById('sayim-kat-tabs').innerHTML=
    `<button class="filter-tab ${sayimKatFilter==='tumu'?'active':''}" onclick="filterSayimKat('tumu',this)">Tümü</button>`+
    [...katSet].sort().map(k=>`<button class="filter-tab ${sayimKatFilter===k?'active':''}" onclick="filterSayimKat('${k}',this)">${k}</button>`).join('');

  const filtered=items.filter(s=>{
    if(search&&!s.urunAd?.toLowerCase().includes(search)&&!s.lnKod?.toLowerCase().includes(search))return false;
    if(sayimKatFilter!=='tumu'&&!s.lnKod?.startsWith(sayimKatFilter))return false;
    return true;
  });
  filtered.sort((a,b)=>(a.urunAd||'').localeCompare(b.urunAd||'','tr'));

  _sayimSistemMiktar={};_sayimUrunAdi={};_sayimBirim={};
  const c=document.getElementById('sayim-liste');
  if(!filtered.length){c.innerHTML='<div class="card" style="text-align:center;color:var(--gray-500)">Ürün bulunamadı</div>';return;}
  c.innerHTML=filtered.map(s=>{
    _sayimSistemMiktar[s.lnKod]=parseFloat(s.miktar)||0;
    _sayimUrunAdi[s.lnKod]=s.urunAd;
    _sayimBirim[s.lnKod]=s.birim;
    return `
    <div class="card" style="padding:10px 14px">
      <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:6px;gap:8px">
        <div><div style="font-weight:700;font-size:13px">${escapeHtml(s.urunAd)}</div><div style="font-size:10px;color:var(--gray-400)">${escapeHtml(s.lnKod)} • Sistem: ${s.miktar} ${escapeHtml(s.birim||'')}</div></div>
        <input type="number" step="any" placeholder="Sayılan" style="width:90px;padding:8px;border:1.5px solid var(--gray-300);border-radius:var(--radius-sm)" oninput="sayimFarkGuncelle('${s.lnKod}',this.value)">
      </div>
      <div id="sayim-fark-${s.lnKod}"></div>
      <div id="sayim-aciklama-alan-${s.lnKod}"></div>
    </div>`;
  }).join('');
}
```

- [ ] **Step 4: Canlı fark hesaplama fonksiyonlarını ekle**

Az önce eklenen bloğun hemen ardına ekle:

```js
function sayimFarkGuncelle(lnKod,val){
  const farkEl=document.getElementById('sayim-fark-'+lnKod);
  const aciklamaEl=document.getElementById('sayim-aciklama-alan-'+lnKod);
  if(val===''){
    delete sayimSatirlari[lnKod];
    if(farkEl)farkEl.innerHTML='';
    if(aciklamaEl)aciklamaEl.innerHTML='';
    return;
  }
  const sistemMiktar=_sayimSistemMiktar[lnKod]||0;
  const sayilan=parseFloat(val);
  if(isNaN(sayilan))return;
  const fark=round2(sayilan-sistemMiktar);
  const farkYuzde=sistemMiktar>0?round2(Math.abs(fark)/sistemMiktar*100):(fark!==0?100:0);
  const oncekiAciklama=sayimSatirlari[lnKod]?.aciklama||'';
  sayimSatirlari[lnKod]={sayilan,fark,farkYuzde,aciklama:oncekiAciklama};
  const buyukFark=farkYuzde>SAYIM_ESIK_YUZDE;
  const renk=fark===0?'var(--gray-500)':(buyukFark?'var(--danger)':'var(--warning)');
  if(farkEl)farkEl.innerHTML=fark===0
    ?`<span style="color:${renk};font-size:12px">Fark yok</span>`
    :`<span style="color:${renk};font-weight:700;font-size:12px">${fark>0?'+':''}${fark} (${fark>0?'+':''}${farkYuzde}%)</span>`;
  if(aciklamaEl)aciklamaEl.innerHTML=buyukFark
    ?`<input type="text" placeholder="⚠️ Açıklama (zorunlu)" style="width:100%;margin-top:6px;padding:8px;border:1.5px solid var(--danger);border-radius:var(--radius-sm)" oninput="sayimAciklamaGuncelle('${lnKod}',this.value)" value="${escapeHtml(oncekiAciklama)}">`
    :(fark!==0?`<input type="text" placeholder="Açıklama (isteğe bağlı)" style="width:100%;margin-top:6px;padding:8px;border:1.5px solid var(--gray-300);border-radius:var(--radius-sm)" oninput="sayimAciklamaGuncelle('${lnKod}',this.value)" value="${escapeHtml(oncekiAciklama)}">`:'');
}

function sayimAciklamaGuncelle(lnKod,val){
  if(sayimSatirlari[lnKod])sayimSatirlari[lnKod].aciklama=val;
}
```

- [ ] **Step 5: Doğrula**

```bash
grep -n "function renderSayimTab\|function renderSayimYeni\|function sayimFarkGuncelle\|function sayimAciklamaGuncelle\|function sayimGorunumDegistir\|function filterSayimKat\|function round2" stok-takip.html
```
Expected: 7 fonksiyon tanımı görünmeli.

- [ ] **Step 6: Commit**

```bash
git add stok-takip.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: add Sayim list rendering with live diff calculation"
```

---

### Task 4: "Sayımı Tamamla" — doğrulama + kayıt

**Files:**
- Modify: `stok-takip.html` — yeni fonksiyon, `sayimAciklamaGuncelle`'nin hemen ardına eklenir.

**Interfaces:**
- Consumes: `sayimSatirlari`, `_sayimSistemMiktar`, `_sayimUrunAdi`, `_sayimBirim`, `SAYIM_ESIK_YUZDE`, `aktifDepoId`, `otelFromDepoId()`, `showLoading()`/`hideLoading()`, `showToast()`, `SB_URL`/`SB_HEADERS`, `currentUser` (Task 1-3)
- Produces: `sayimTamamla()` — butonun `onclick`'i bunu çağırır.

- [ ] **Step 1: Çift-gönderim guard'ı ve `sayimTamamla` fonksiyonunu ekle**

`sayimAciklamaGuncelle` fonksiyonunun hemen ardına ekle:

```js
let _sayimKaydediliyor=false;

async function sayimTamamla(){
  if(_sayimKaydediliyor){showToast('⏳ İşleniyor, bekleyin...');return;}
  const satirlar=Object.entries(sayimSatirlari).filter(([,v])=>v.sayilan!==undefined&&!isNaN(v.sayilan));
  if(!satirlar.length){showToast('⚠️ En az bir ürün için sayılan miktar girin');return;}
  const eksikAciklama=satirlar.filter(([,v])=>v.farkYuzde>SAYIM_ESIK_YUZDE&&!v.aciklama.trim());
  if(eksikAciklama.length){
    alert('Sayım kaydedilemedi, açıklama eksik:\n\n'+eksikAciklama.map(([k])=>_sayimUrunAdi[k]||k).join('\n'));
    return;
  }
  _sayimKaydediliyor=true;
  showLoading();
  try{
    const farkliSayisi=satirlar.filter(([,v])=>v.fark!==0).length;
    const oturumR=await fetch(SB_URL+'/rest/v1/sayim_oturumlari',{method:'POST',headers:{...SB_HEADERS,'Prefer':'return=representation'},body:JSON.stringify({
      depo_kodu:aktifDepoId,otel_id:otelFromDepoId(aktifDepoId),olusturan_ad:currentUser?.ad||'—',
      durum:'onay_bekliyor',toplam_urun_sayisi:satirlar.length,farkli_urun_sayisi:farkliSayisi
    })});
    if(!oturumR.ok)throw new Error('Oturum oluşturulamadı');
    const oturumD=await oturumR.json();
    const oturumId=oturumD[0].id;
    const detaySatirlar=satirlar.map(([kod,v])=>({
      oturum_id:oturumId,urun_kodu:kod,urun_adi:_sayimUrunAdi[kod]||'',birim:_sayimBirim[kod]||'',
      sistem_miktar:_sayimSistemMiktar[kod]||0,sayilan_miktar:v.sayilan,fark:v.fark,fark_yuzde:v.farkYuzde,
      aciklama:v.aciklama||null
    }));
    const detayR=await fetch(SB_URL+'/rest/v1/sayim_detaylari',{method:'POST',headers:SB_HEADERS,body:JSON.stringify(detaySatirlar)});
    if(!detayR.ok)throw new Error('Detaylar kaydedilemedi');
    showToast(`✅ Sayım kaydedildi — ${satirlar.length} ürün, ${farkliSayisi} farklı, onay bekliyor`);
    sayimSatirlari={};
    renderSayimYeni();
  }catch(e){
    console.warn(e);
    showToast('❌ Sayım kaydedilemedi, tekrar deneyin');
  }
  _sayimKaydediliyor=false;
  hideLoading();
}
```

- [ ] **Step 2: Doğrula**

```bash
grep -n "function sayimTamamla\|onclick=\"sayimTamamla" stok-takip.html
```
Expected: fonksiyon tanımı + butonun `onclick` çağrısı.

- [ ] **Step 3: Kod okuyarak izleme**

`sayimTamamla`'nın `eksikAciklama` kontrolünün `SAYIM_ESIK_YUZDE` (Task 3) ile aynı eşiği kullandığını, ve `sayim_detaylari` POST body'sinin Task 1'in SQL'inde tanımlanan kolon adlarıyla (`oturum_id,urun_kodu,urun_adi,birim,sistem_miktar,sayilan_miktar,fark,fark_yuzde,aciklama`) birebir eştiğini doğrula.

- [ ] **Step 4: Commit**

```bash
git add stok-takip.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: add sayimTamamla - saves count session as onay_bekliyor"
```

---

### Task 5: Onay Bekleyen Sayımlar — cost_control onay/red akışı

**Files:**
- Modify: `stok-takip.html` — yeni fonksiyonlar + yeni modal HTML.

**Interfaces:**
- Consumes: `giris(depoId,lnKod,urunAd,miktar,birim,kaynak,kaynakId)`, `cikis(depoId,lnKod,urunAd,miktar,birim,neden,not)`, `saveStok(hedefler)`, `saveHareket(h)`, `depoAdi()`, `escapeHtml()`, `round2()`, `openModal()`/`closeModal()` (mevcut/Task 1-4)
- Produces: `sayimOnayBekleyenleriYukle()`, `renderSayimOnayListesi()`, `sayimOnayBekleyenSayisiGuncelle()`, `sayimDetayGoster(oturumId)`, `sayimOnayla(oturumId)`, `sayimReddet(oturumId)`

**Not:** `giris()` fonksiyonunun döndürdüğü hareket nesnesinde serbest metin bir açıklama alanı yok (mevcut kodun kendi kısıtı — bu görevin kapsamı dışında, dokunulmuyor). Bu yüzden pozitif farklarda (giriş) sayım açıklaması `stok_hareketleri` tablosuna değil, sadece `sayim_detaylari.aciklama`'ya kalıcı olarak yazılır — bu, denetlenebilirlik için yeterli, çünkü oturum kaydı hiç silinmiyor.

- [ ] **Step 1: Onay listesi state'i ve yükleme fonksiyonlarını ekle**

`sayimTamamla` fonksiyonunun hemen ardına ekle:

```js
let sayimOnayBekleyenler=[];

async function sayimOnayBekleyenleriYukle(){
  showLoading();
  try{
    const r=await fetch(SB_URL+'/rest/v1/sayim_oturumlari?durum=eq.onay_bekliyor&select=*&order=olusturma_tarihi.desc',{headers:SB_HEADERS});
    sayimOnayBekleyenler=r.ok?await r.json():[];
  }catch(e){console.warn(e);sayimOnayBekleyenler=[];}
  hideLoading();
  renderSayimOnayListesi();
  sayimOnayBekleyenSayisiGuncelle();
}

async function sayimOnayBekleyenSayisiGuncelle(){
  if(currentUser?.rol!=='cost_control')return;
  try{
    const r=await fetch(SB_URL+'/rest/v1/sayim_oturumlari?durum=eq.onay_bekliyor&select=id',{headers:SB_HEADERS});
    const n=r.ok?(await r.json()).length:0;
    const badge=document.getElementById('sayim-onay-badge');
    if(n>0){badge.textContent=n;badge.style.display='block';}else badge.style.display='none';
  }catch(e){console.warn(e);}
}

function renderSayimOnayListesi(){
  const c=document.getElementById('sayim-onay-liste');
  if(!sayimOnayBekleyenler.length){c.innerHTML='<div class="card" style="text-align:center;color:var(--gray-500)">Onay bekleyen sayım yok</div>';return;}
  c.innerHTML=sayimOnayBekleyenler.map(o=>`
    <div class="card">
      <div class="card-title">${escapeHtml(depoAdi(o.depo_kodu))} — ${new Date(o.olusturma_tarihi).toLocaleString('tr-TR')}</div>
      <div style="font-size:12px;color:var(--gray-600);margin-bottom:8px">Oluşturan: ${escapeHtml(o.olusturan_ad)} • ${o.toplam_urun_sayisi} ürün sayıldı, ${o.farkli_urun_sayisi} üründe fark var</div>
      <button class="btn btn-primary btn-sm btn-block" onclick="sayimDetayGoster('${o.id}')">🔍 İncele</button>
    </div>
  `).join('');
}
```

- [ ] **Step 2: Detay modalını ve HTML'ini ekle**

`stok-takip.html:333-338` civarındaki `modal-detay` div'inin hemen ardına ekle:

```html
<!-- MODAL: Sayım Detay/Onay -->
<div class="modal-overlay" id="modal-sayim-detay">
  <div class="modal-box">
    <div class="modal-title">📊 Sayım Detayı <button class="modal-close" onclick="closeModal('modal-sayim-detay')">✕</button></div>
    <div id="sayim-detay-icerik"></div>
    <div class="btn-row" style="margin-top:12px">
      <button class="btn btn-danger" onclick="sayimReddet(_sayimAktifOturumId)">❌ Reddet</button>
      <button class="btn btn-success" onclick="sayimOnayla(_sayimAktifOturumId)">✅ Onayla</button>
    </div>
  </div>
</div>
```

- [ ] **Step 3: `sayimDetayGoster` fonksiyonunu ekle**

`renderSayimOnayListesi` fonksiyonunun hemen ardına ekle:

```js
let _sayimAktifOturumId=null;

async function sayimDetayGoster(oturumId){
  _sayimAktifOturumId=oturumId;
  showLoading();
  try{
    const r=await fetch(SB_URL+'/rest/v1/sayim_detaylari?oturum_id=eq.'+oturumId+'&select=*',{headers:SB_HEADERS});
    const detaylar=r.ok?await r.json():[];
    const c=document.getElementById('sayim-detay-icerik');
    c.innerHTML=detaylar.map(d=>{
      const fark=parseFloat(d.fark)||0;
      const renk=fark===0?'var(--gray-500)':(parseFloat(d.fark_yuzde)>SAYIM_ESIK_YUZDE?'var(--danger)':'var(--warning)');
      return `<div style="padding:8px 0;border-bottom:1px solid var(--gray-100)">
        <div style="display:flex;justify-content:space-between"><b style="font-size:13px">${escapeHtml(d.urun_adi)}</b><span style="color:${renk};font-weight:700">${fark>0?'+':''}${fark}</span></div>
        <div style="font-size:11px;color:var(--gray-500)">Sistem: ${d.sistem_miktar} → Sayılan: ${d.sayilan_miktar} ${escapeHtml(d.birim||'')}</div>
        ${d.aciklama?`<div style="font-size:11px;color:var(--gray-600);margin-top:2px">📝 ${escapeHtml(d.aciklama)}</div>`:''}
      </div>`;
    }).join('');
  }catch(e){console.warn(e);}
  hideLoading();
  openModal('modal-sayim-detay');
}
```

- [ ] **Step 4: `sayimOnayla` ve `sayimReddet` fonksiyonlarını ekle**

`sayimDetayGoster` fonksiyonunun hemen ardına ekle:

```js
let _sayimOnayIsleniyor=false;

async function sayimOnayla(oturumId){
  if(currentUser?.rol!=='cost_control'){showToast('❌ Bu işlem için yetkiniz yok');return;}
  if(_sayimOnayIsleniyor)return;
  _sayimOnayIsleniyor=true;
  showLoading();
  try{
    const oturum=sayimOnayBekleyenler.find(o=>o.id===oturumId);
    if(!oturum)throw new Error('Oturum bulunamadı');
    const detR=await fetch(SB_URL+'/rest/v1/sayim_detaylari?oturum_id=eq.'+oturumId+'&select=*',{headers:SB_HEADERS});
    const detaylar=detR.ok?await detR.json():[];
    const hareketler=[];
    for(const d of detaylar){
      // Bayat veri kontrolü: onay anındaki GÜNCEL sistem miktarını yeniden oku, oturumdaki donmuş değeri değil
      const guncelR=await fetch(SB_URL+'/rest/v1/stok?depo_kodu=eq.'+encodeURIComponent(oturum.depo_kodu)+'&urun_kodu=eq.'+encodeURIComponent(d.urun_kodu)+'&select=miktar',{headers:SB_HEADERS});
      const guncelD=guncelR.ok?await guncelR.json():[];
      const guncelMiktar=guncelD.length?parseFloat(guncelD[0].miktar)||0:0;
      const guncelFark=round2(parseFloat(d.sayilan_miktar)-guncelMiktar);
      if(guncelFark===0)continue;
      const h=guncelFark>0
        ?giris(oturum.depo_kodu,d.urun_kodu,d.urun_adi,guncelFark,d.birim,'sayim',oturumId)
        :cikis(oturum.depo_kodu,d.urun_kodu,d.urun_adi,Math.abs(guncelFark),d.birim,'sayim',d.aciklama||'Fiziksel sayım düzeltmesi');
      hareketler.push(h);
    }
    if(hareketler.length){
      await saveStok(hareketler.map(h=>({depoId:h.depoId,kod:h.lnKod})));
      for(const h of hareketler)await saveHareket(h);
    }
    await fetch(SB_URL+'/rest/v1/sayim_oturumlari?id=eq.'+oturumId,{method:'PATCH',headers:SB_HEADERS,body:JSON.stringify({
      durum:'onaylandi',onaylayan_ad:currentUser?.ad||'—',onay_tarihi:new Date().toISOString()
    })});
    showToast(`✅ Sayım onaylandı — ${hareketler.length} üründe stok güncellendi`);
    closeModal('modal-sayim-detay');
    if(aktifDepoId)renderStok();
    await sayimOnayBekleyenleriYukle();
  }catch(e){
    console.warn(e);
    showToast('❌ Onaylama başarısız, tekrar deneyin');
  }
  _sayimOnayIsleniyor=false;
  hideLoading();
}

async function sayimReddet(oturumId){
  if(currentUser?.rol!=='cost_control'){showToast('❌ Bu işlem için yetkiniz yok');return;}
  if(_sayimOnayIsleniyor)return;
  const nedenGirdi=prompt('Red nedeni (opsiyonel):','');
  if(nedenGirdi===null)return; // kullanıcı iptal etti
  _sayimOnayIsleniyor=true;
  showLoading();
  try{
    await fetch(SB_URL+'/rest/v1/sayim_oturumlari?id=eq.'+oturumId,{method:'PATCH',headers:SB_HEADERS,body:JSON.stringify({
      durum:'reddedildi',onaylayan_ad:currentUser?.ad||'—',onay_tarihi:new Date().toISOString(),red_nedeni:nedenGirdi||null
    })});
    showToast('❌ Sayım reddedildi, stok değişmedi');
    closeModal('modal-sayim-detay');
    await sayimOnayBekleyenleriYukle();
  }catch(e){
    console.warn(e);
    showToast('❌ İşlem başarısız, tekrar deneyin');
  }
  _sayimOnayIsleniyor=false;
  hideLoading();
}
```

- [ ] **Step 5: Doğrula**

```bash
grep -n "function sayimOnayBekleyenleriYukle\|function renderSayimOnayListesi\|function sayimDetayGoster\|function sayimOnayla\|function sayimReddet\|id=\"modal-sayim-detay\"" stok-takip.html
```
Expected: 5 fonksiyon tanımı + modal div görünmeli.

- [ ] **Step 6: Kod okuyarak izleme**

`sayimOnayla`'nın her ürün için `stok` tablosundan GÜNCEL miktarı yeniden okuduğunu (oturum oluşturma anındaki `sistem_miktar` değerini DEĞİL) ve farkın bu güncel değere göre yeniden hesaplandığını doğrula — bu spec'in "bayat veri" kontrolü gereksinimi. Ayrıca `sayimOnayla`/`sayimReddet` içindeki `currentUser?.rol!=='cost_control'` kontrolünün, UI'da bu butonların zaten sadece `cost_control` kullanıcısına gösterilmesinden (Task 3, `renderSayimTab`) BAĞIMSIZ ikinci bir savunma katmanı olduğunu doğrula (UI gizlemesi tek başına yetki kontrolü değildir).

- [ ] **Step 7: Commit**

```bash
git add stok-takip.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: add sayim approval flow (cost_control only) with live stok re-check"
```

---

### Task 6: Uçtan uca doğrulama

**Files:** (yok — sadece doğrulama)

- [ ] **Step 1: Tüm yeni tanımların tutarlılığını kontrol et**

```bash
grep -n "sayim_oturumlari\|sayim_detaylari" stok-takip.html
```
Expected: Task 1'deki SQL'de tanımlanan tablo adlarının hepsi doğru yazımla geçmeli.

- [ ] **Step 2: Kullanıcıya manuel test adımlarını bildir**

Kullanıcının tarayıcıda doğrulaması gereken akış (Node/Python bu ortamda yok, otomatik test yazılamıyor):
1. Task 1'deki SQL'i Supabase SQL Editor'de çalıştır.
2. `depo` veya `yonetici` rolüyle giriş yap → `stok-takip.html` → "📊 Sayım" sekmesi → birkaç üründe sistemden farklı bir "Sayılan Miktar" gir → büyük farkta (>%10) açıklamanın zorunlu hale geldiğini doğrula.
3. "Sayımı Tamamla" → boş açıklamayla göndermeye çalış, engellendiğini doğrula → açıklamaları doldurup tekrar dene → başarı toast'ını gör.
4. `cost_control` rolüyle giriş yap (yoksa `kullanici-yonetimi.html`'de bir kullanıcıya bu rolü ata) → "📊 Sayım" sekmesinde "✅ Onay Bekleyen" alt-sekmesinin göründüğünü, diğer rollerde görünmediğini doğrula.
5. Onay Bekleyen listesinde az önceki sayımı bul → "🔍 İncele" → detayları gör → "✅ Onayla" → stok-takip.html'in Stok sekmesine dönüp miktarların güncellendiğini, Hareketler sekmesinde `sayim` kaynaklı giriş/çıkış kayıtlarının göründüğünü doğrula.
6. Farklı bir sayım oluşturup "❌ Reddet" ile reddet, stok miktarının DEĞİŞMEDİĞİNİ doğrula.
7. `yonetici` rolüyle onay/red butonlarına erişimin olmadığını (sekme görünmüyor) doğrula.

- [ ] **Step 3: Kullanıcıdan onay al, sonra push**

```bash
git fetch
git log --oneline main..origin/main
```
Expected: paralel oturumdan gelen değişiklik var mı kontrol et, varsa kullanıcıya bildir. Yoksa kullanıcı onayıyla `git push`.
