# Otomatik Yeniden Sipariş Tetikleme Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `satin-alma.html` açıldığında minimum stok altına düşen ürünleri tarayıp, kullanıcı onayıyla otel bazlı gruplu İç Talepler oluşturan bir öneri akışı eklemek.

**Architecture:** Mevcut manuel İç Talep kaydetme mantığı (`ytKaydet()`) parametreli bir yardımcıya (`talepKaydet()`) çıkarılır; hem mevcut manuel form hem yeni otomatik öneri akışı bu ortak fonksiyonu kullanır. Yeni bir `stokMinimumKontrolEt()` fonksiyonu sayfa açılışında `stok`+`stok_minimumlar` tablolarını okuyup eksikleri hesaplar, bir uyarı şeridi + onay listesi modalı gösterir.

**Tech Stack:** Vanilla HTML/JS, Supabase REST (fetch) — build aracı/test çerçevesi yok.

## Global Constraints

- Hiçbir talep kullanıcı onayı olmadan otomatik oluşturulmaz — sadece öneri gösterilir (spec).
- Gruplama otel bazlı (`departman:'DEPO'`, `otel_id`), depo bazlı değil (spec).
- Minimum değerleri ürün bazlı global kalır (mevcut `stok_minimumlar` modeli değişmez) (spec).
- Kontrol sadece `satin-alma.html` açıldığında çalışır — gerçek zamanlı/arka plan tetikleme yok (spec).

---

### Task 1: `talepKaydet()` yardımcı fonksiyonunu çıkar (refactor)

**Files:**
- Modify: `satin-alma.html:675-699` (`ytKaydet`)

**Interfaces:**
- Produces: `talepKaydet(departman,aciliyet,notAlani,satirlar,otelId)` → `Promise<string|null>` (yeni talep id'si veya hata durumunda `null`) — Task 4 bunu kullanacak.

- [ ] **Step 1: `talepKaydet()` fonksiyonunu ekle**

`ytKaydet` fonksiyonunun hemen ÖNÜNE ekle:

```js
// departman: string, aciliyet: 'acil'|'normal'|'rutin', notAlani: string|null,
// satirlar: [{ad,kod,miktar,birim}], otelId: string
// Döner: yeni talep id'si (string) veya hata durumunda null.
async function talepKaydet(departman,aciliyet,notAlani,satirlar,otelId){
  const doluSatirlar=satirlar.filter(u=>u.ad&&u.miktar&&parseFloat(u.miktar)>0);
  if(!doluSatirlar.length)return null;
  const satir={departman,aciliyet,not_alani:notAlani||null,durum:'bekleyen',talep_eden:CU.ad,otel_id:otelId||'810'};
  try{
    const r=await fetch(SB_URL+'/rest/v1/satin_alma_talepleri',{method:'POST',headers:{...SB_HEADERS,'Prefer':'return=representation'},body:JSON.stringify(satir)});
    if(!r.ok)return null;
    const d=await r.json();
    const talepId=d[0].id;
    const kalemSatirlar=doluSatirlar.map(u=>({talep_id:talepId,urun_adi:u.ad,urun_kodu:u.kod||null,miktar:u.miktar,birim:u.birim}));
    await fetch(SB_URL+'/rest/v1/satin_alma_talep_kalemleri',{method:'POST',headers:SB_HEADERS,body:JSON.stringify(kalemSatirlar)});
    DB.talepler[talepId]={id:talepId,tarih:new Date().toISOString().split('T')[0],olusturmaTarih:Date.now(),departman,personel:CU.ad,satirlar:doluSatirlar,aciliyet,not:notAlani||'',durum:'bekleyen'};
    return talepId;
  }catch(e){console.warn(e);return null;}
}
```

- [ ] **Step 2: `ytKaydet()`'i `talepKaydet()`'i kullanacak şekilde sadeleştir**

Mevcut (satır 675-699):
```js
async function ytKaydet(){
  const doluSatirlar=YT_SATIRLAR.filter(u=>u.ad&&u.miktar&&parseFloat(u.miktar)>0);
  if(!doluSatirlar.length){toast('⚠️ En az bir ürün ekleyin');return;}

  const dept=document.getElementById('yt-dept').value;
  const aciliyet=document.getElementById('yt-aciliyet').value;
  const not=document.getElementById('yt-not').value;

  const satir={departman:dept,aciliyet,not_alani:not||null,durum:'bekleyen',talep_eden:CU.ad,otel_id:CU.otelId||'810'};
  sLD();
  try{
    const r=await fetch(SB_URL+'/rest/v1/satin_alma_talepleri',{method:'POST',headers:{...SB_HEADERS,'Prefer':'return=representation'},body:JSON.stringify(satir)});
    const d=await r.json();
    const talepId=d[0].id;
    const kalemSatirlar=doluSatirlar.map(u=>({talep_id:talepId,urun_adi:u.ad,urun_kodu:u.kod||null,miktar:u.miktar,birim:u.birim}));
    await fetch(SB_URL+'/rest/v1/satin_alma_talep_kalemleri',{method:'POST',headers:SB_HEADERS,body:JSON.stringify(kalemSatirlar)});
    DB.talepler[talepId]={id:talepId,tarih:new Date().toISOString().split('T')[0],olusturmaTarih:Date.now(),departman:dept,personel:CU.ad,satirlar:doluSatirlar,aciliyet,not,durum:'bekleyen'};
  }catch(e){console.warn(e);toast('⚠️ Talep kaydedilemedi');}
  hLD();
  kModal('mYeniTalep');
  YT_SATIRLAR=[];
  document.getElementById('yt-not').value='';
  toast('✅ Talep gönderildi — '+doluSatirlar.length+' kalem');
  renderTalepler();
}
```
şuna çevir:
```js
async function ytKaydet(){
  const doluSatirlar=YT_SATIRLAR.filter(u=>u.ad&&u.miktar&&parseFloat(u.miktar)>0);
  if(!doluSatirlar.length){toast('⚠️ En az bir ürün ekleyin');return;}

  const dept=document.getElementById('yt-dept').value;
  const aciliyet=document.getElementById('yt-aciliyet').value;
  const not=document.getElementById('yt-not').value;

  sLD();
  const talepId=await talepKaydet(dept,aciliyet,not,YT_SATIRLAR,CU.otelId||'810');
  hLD();
  if(!talepId){toast('⚠️ Talep kaydedilemedi');return;}
  kModal('mYeniTalep');
  YT_SATIRLAR=[];
  document.getElementById('yt-not').value='';
  toast('✅ Talep gönderildi — '+doluSatirlar.length+' kalem');
  renderTalepler();
}
```

- [ ] **Step 3: Doğrula**

```bash
grep -n "function talepKaydet\|function ytKaydet" satin-alma.html
```
Expected: 2 fonksiyon tanımı, bu sırayla (`talepKaydet` önce).

- [ ] **Step 4: Kod okuyarak izleme**

`ytKaydet`'in yeni haliyle eski haliyle AYNI kullanıcı deneyimini ürettiğini doğrula: başarı durumunda aynı toast mesajı, aynı modal kapatma, aynı `YT_SATIRLAR`/not alanı temizleme sırası; hata durumunda aynı uyarı mesajı (`'⚠️ Talep kaydedilemedi'`). Davranış değişikliği YOK, sadece kod tekrarı kaldırıldı.

- [ ] **Step 5: Commit**

```bash
git add satin-alma.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "refactor: extract talepKaydet helper from ytKaydet for reuse"
```

---

### Task 2: `stokMinimumKontrolEt()` — eksik ürün taraması

**Files:**
- Modify: `satin-alma.html` — yeni fonksiyon ve global state, `talepKaydet` fonksiyonunun hemen ardına eklenir.

**Interfaces:**
- Consumes: `SB_URL`/`SB_HEADERS`, `DB.urunler` (mevcut, `loadFirmalar()`'da `URUN_DB`'den dolduruluyor — `{kod,ad,birim,grup,sicaklikKriter}`), `round2()` (mevcut)
- Produces: Global `YENIDEN_SIPARIS_ONERI` (dizi, `{otelId,depoKodu,urunKodu,urunAdi,birim,mevcutMiktar,minMiktar,onerilenMiktar}`), `stokMinimumKontrolEt()`, `renderYenidenSiparisUyarisi()` (Task 3'ün dolduracağı `#yeniden-siparis-uyari` elemanını günceller — Task 3'ten önce çağrılırsa elemanın henüz DOM'da olmamasına karşı `getElementById` null kontrolü içerir).

- [ ] **Step 1: Global state ve `stokMinimumKontrolEt()` fonksiyonunu ekle**

`talepKaydet` fonksiyonunun hemen ardına ekle:

```js
let YENIDEN_SIPARIS_ONERI=[]; // [{otelId,depoKodu,urunKodu,urunAdi,birim,mevcutMiktar,minMiktar,onerilenMiktar}]

async function stokMinimumKontrolEt(){
  try{
    const [stokR,minR]=await Promise.all([
      fetch(SB_URL+'/rest/v1/stok?select=urun_kodu,depo_kodu,otel_id,miktar',{headers:SB_HEADERS}),
      fetch(SB_URL+'/rest/v1/stok_minimumlar?select=urun_kodu,min_miktar',{headers:SB_HEADERS})
    ]);
    if(!stokR.ok||!minR.ok)return;
    const stokListe=await stokR.json();
    const minListe=await minR.json();
    const minMap={};
    minListe.forEach(m=>{
      const mevcut=minMap[m.urun_kodu]||0;
      minMap[m.urun_kodu]=Math.max(mevcut,parseFloat(m.min_miktar)||0);
    });
    const urunMap={};
    (DB.urunler||[]).forEach(u=>{urunMap[u.kod]=u;});
    const oneri=[];
    stokListe.forEach(s=>{
      const min=minMap[s.urun_kodu];
      if(!min||min<=0)return;
      const miktar=parseFloat(s.miktar)||0;
      if(miktar>min)return;
      const urun=urunMap[s.urun_kodu]||{};
      oneri.push({
        otelId:s.otel_id||(s.depo_kodu||'').split('_')[0]||'810',
        depoKodu:s.depo_kodu,urunKodu:s.urun_kodu,
        urunAdi:urun.ad||s.urun_kodu,birim:urun.birim||'',
        mevcutMiktar:miktar,minMiktar:min,onerilenMiktar:round2(min-miktar)
      });
    });
    YENIDEN_SIPARIS_ONERI=oneri;
  }catch(e){console.warn(e);}
  renderYenidenSiparisUyarisi();
}

function renderYenidenSiparisUyarisi(){
  const el=document.getElementById('yeniden-siparis-uyari');
  if(!el)return;
  if(YENIDEN_SIPARIS_ONERI.length){
    el.style.display='block';
    document.getElementById('yeniden-siparis-uyari-metin').textContent=`⚠️ ${YENIDEN_SIPARIS_ONERI.length} ürün minimum altında — Öneri listesini gör`;
  }else{
    el.style.display='none';
  }
}
```

- [ ] **Step 2: Doğrula**

```bash
grep -n "function stokMinimumKontrolEt\|function renderYenidenSiparisUyarisi\|let YENIDEN_SIPARIS_ONERI" satin-alma.html
```
Expected: 3 satır görünmeli.

- [ ] **Step 3: Commit**

```bash
git add satin-alma.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: add stokMinimumKontrolEt to scan for products below minimum stock"
```

---

### Task 3: Uyarı şeridi + öneri listesi modalı (UI)

**Files:**
- Modify: `satin-alma.html:95-96` (İç Talepler sekmesi başı, uyarı şeridi eklenir)
- Modify: `satin-alma.html` — yeni modal HTML, mevcut `mYeniTalep` modalının hemen ardına eklenir.
- Modify: `satin-alma.html` — `openYenidenSiparisOneri()` fonksiyonu, `renderYenidenSiparisUyarisi` fonksiyonunun hemen ardına eklenir.

**Interfaces:**
- Consumes: `YENIDEN_SIPARIS_ONERI` (Task 2), `escapeHtml()`, `aModal()`/`kModal()` (mevcut)
- Produces: `#yeniden-siparis-uyari` (div), `#mYenidenSiparis` (modal), `openYenidenSiparisOneri()` — Task 4'ün `yenidenSiparisOlustur()` fonksiyonu bu modalın içeriğini okuyacak.

- [ ] **Step 1: Uyarı şeridini ekle**

Mevcut (satır 95-97):
```html
  <!-- İÇ TALEPLER -->
  <div class="sc" id="tab-talepler" style="display:block">
    <div class="ftabs" id="talep-ftabs">
```
şuna çevir:
```html
  <!-- İÇ TALEPLER -->
  <div class="sc" id="tab-talepler" style="display:block">
    <div id="yeniden-siparis-uyari" style="display:none;background:#fff3cd;border:1px solid #ffc107;border-radius:8px;padding:10px 14px;margin-bottom:10px;cursor:pointer" onclick="openYenidenSiparisOneri()">
      <span style="font-weight:700;font-size:13px;color:#856404" id="yeniden-siparis-uyari-metin"></span>
    </div>
    <div class="ftabs" id="talep-ftabs">
```

- [ ] **Step 2: Öneri listesi modalını ekle**

`mYeniTalep` modalının kapanış `</div>` etiketlerinin (satır ~376-377 civarı, `mYeniTalep`'in tüm modal `.mo` div'i biter) hemen ardına ekle:

```html
<!-- MODAL: Yeniden Sipariş Önerileri -->
<div class="mo" id="mYenidenSiparis">
  <div class="mbox" style="max-height:95vh">
    <div class="mtitle">⚠️ Yeniden Sipariş Önerileri <button class="mclose" onclick="kModal('mYenidenSiparis')">✕</button></div>
    <div id="yeniden-siparis-liste" style="max-height:65vh;overflow-y:auto"></div>
    <div class="brow" style="margin-top:10px">
      <button class="btn btn-gray" onclick="kModal('mYenidenSiparis')">Kapat</button>
      <button class="btn btn-primary" onclick="yenidenSiparisOlustur()">📤 Seçilenlerden Talep Oluştur</button>
    </div>
  </div>
</div>
```

- [ ] **Step 3: `openYenidenSiparisOneri()` fonksiyonunu ekle**

`renderYenidenSiparisUyarisi` fonksiyonunun hemen ardına ekle:

```js
function openYenidenSiparisOneri(){
  const gruplar={};
  YENIDEN_SIPARIS_ONERI.forEach((o,i)=>{
    if(!gruplar[o.otelId])gruplar[o.otelId]=[];
    gruplar[o.otelId].push({...o,_idx:i});
  });
  const otelAdlari={'810':'Ali Bey Club Manavgat','811':'Ali Bey Resort Sorgun'};
  const c=document.getElementById('yeniden-siparis-liste');
  c.innerHTML=Object.keys(gruplar).sort().map(otelId=>`
    <div style="font-weight:700;font-size:13px;margin:10px 0 6px;color:var(--primary)">🏨 ${escapeHtml(otelAdlari[otelId]||otelId)}</div>
    ${gruplar[otelId].map(o=>`
      <label style="display:flex;align-items:center;gap:8px;padding:6px 4px;border-bottom:1px solid var(--gray-100);font-size:12px">
        <input type="checkbox" class="yeniden-siparis-check" data-idx="${o._idx}" checked>
        <span style="flex:1">${escapeHtml(o.urunAdi)}<br><span style="color:var(--gray-500);font-size:10px">${escapeHtml(o.depoKodu)} • Mevcut: ${o.mevcutMiktar} / Min: ${o.minMiktar} ${escapeHtml(o.birim)}</span></span>
        <span style="font-weight:700">+${o.onerilenMiktar}</span>
      </label>
    `).join('')}
  `).join('');
  aModal('mYenidenSiparis');
}
```

- [ ] **Step 4: Doğrula**

```bash
grep -n "id=\"yeniden-siparis-uyari\"\|id=\"mYenidenSiparis\"\|function openYenidenSiparisOneri" satin-alma.html
```
Expected: 3 satır görünmeli.

- [ ] **Step 5: Commit**

```bash
git add satin-alma.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: add reorder suggestion banner and modal UI"
```

---

### Task 4: `yenidenSiparisOlustur()` — seçilenlerden talep oluşturma

**Files:**
- Modify: `satin-alma.html` — yeni fonksiyon, `openYenidenSiparisOneri` fonksiyonunun hemen ardına eklenir.

**Interfaces:**
- Consumes: `talepKaydet(departman,aciliyet,notAlani,satirlar,otelId)` (Task 1), `YENIDEN_SIPARIS_ONERI` (Task 2), `renderYenidenSiparisUyarisi()` (Task 2), `renderTalepler()` (mevcut), `toast()`/`sLD()`/`hLD()`/`kModal()` (mevcut)
- Produces: `yenidenSiparisOlustur()` — modaldaki butonun `onclick`'i bunu çağırır.

- [ ] **Step 1: Çift-gönderim guard'ı ve `yenidenSiparisOlustur` fonksiyonunu ekle**

`openYenidenSiparisOneri` fonksiyonunun hemen ardına ekle:

```js
let _yenidenSiparisOlusturuluyor=false;

async function yenidenSiparisOlustur(){
  if(_yenidenSiparisOlusturuluyor)return;
  const secilenIdx=[...document.querySelectorAll('.yeniden-siparis-check:checked')].map(el=>parseInt(el.dataset.idx));
  if(!secilenIdx.length){toast('⚠️ En az bir ürün seçin');return;}
  _yenidenSiparisOlusturuluyor=true;
  sLD();
  try{
    const secilenler=secilenIdx.map(i=>YENIDEN_SIPARIS_ONERI[i]);
    const otelGruplari={};
    secilenler.forEach(o=>{
      if(!otelGruplari[o.otelId])otelGruplari[o.otelId]=[];
      otelGruplari[o.otelId].push(o);
    });
    let toplamTalep=0;
    for(const otelId of Object.keys(otelGruplari)){
      const grup=otelGruplari[otelId];
      const kritikVarMi=grup.some(o=>o.mevcutMiktar<=0||o.mevcutMiktar<=o.minMiktar*0.5);
      const satirlar=grup.map(o=>({ad:o.urunAdi,kod:o.urunKodu,miktar:o.onerilenMiktar,birim:o.birim}));
      const talepId=await talepKaydet('DEPO',kritikVarMi?'acil':'normal','Otomatik stok kontrolü önerisi',satirlar,otelId);
      if(talepId)toplamTalep++;
    }
    if(toplamTalep){
      toast(`✅ ${toplamTalep} talep oluşturuldu`);
      kModal('mYenidenSiparis');
      YENIDEN_SIPARIS_ONERI=YENIDEN_SIPARIS_ONERI.filter((o,i)=>!secilenIdx.includes(i));
      renderYenidenSiparisUyarisi();
      renderTalepler();
    }else{
      toast('❌ Talep oluşturulamadı, tekrar deneyin');
    }
  }catch(e){
    console.warn(e);
    toast('❌ Talep oluşturulamadı, tekrar deneyin');
  }
  _yenidenSiparisOlusturuluyor=false;
  hLD();
}
```

- [ ] **Step 2: Doğrula**

```bash
grep -n "function yenidenSiparisOlustur\|onclick=\"yenidenSiparisOlustur" satin-alma.html
```
Expected: fonksiyon tanımı + modaldaki buton çağrısı.

- [ ] **Step 3: Kod okuyarak izleme**

`yenidenSiparisOlustur`'ın her otel grubu için `talepKaydet('DEPO',...)`'u DOĞRU parametre sırasıyla çağırdığını (Task 1'de tanımlanan `talepKaydet(departman,aciliyet,notAlani,satirlar,otelId)` imzasıyla) ve `satirlar` dizisinin `{ad,kod,miktar,birim}` şeklinde olduğunu (mevcut `YT_SATIRLAR` öğe şekliyle aynı, `talepKaydet`'in beklediği) doğrula. Başarılı işlem sonrası `YENIDEN_SIPARIS_ONERI`'den SADECE seçilen (işaretli) satırların çıkarıldığını, işaretlenmemiş satırların listede kaldığını doğrula.

- [ ] **Step 4: Commit**

```bash
git add satin-alma.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: add yenidenSiparisOlustur to create grouped talepler from selected suggestions"
```

---

### Task 5: Sayfa açılışında tetikleme + uçtan uca doğrulama

**Files:**
- Modify: `satin-alma.html:2547-2553` (init IIFE)

**Interfaces:**
- Consumes: `stokMinimumKontrolEt()` (Task 2)

- [ ] **Step 1: Init akışına `stokMinimumKontrolEt()` çağrısını ekle**

Mevcut (satır 2547-2553):
```js
(async function(){
  CU = requireLogin();
  if(!CU) return;
  if(!requireRole(CU, ['yonetici','satinalma','depo'])) return;
  await loadDB();
  basla();
})();
```
şuna çevir:
```js
(async function(){
  CU = requireLogin();
  if(!CU) return;
  if(!requireRole(CU, ['yonetici','satinalma','depo'])) return;
  await loadDB();
  basla();
  stokMinimumKontrolEt();
})();
```

**Not:** `stokMinimumKontrolEt()` bilerek `await`'lenmiyor — sayfanın ana yüklemesini (mevcut `loadDB()`+`basla()`) bu ek, sayfanın normal işleviyle doğrudan ilgili olmayan taramanın bitmesini beklemeye zorlamamak için arka planda çalışır, bitince kendi `renderYenidenSiparisUyarisi()` çağrısıyla şeridi günceller.

- [ ] **Step 2: Doğrula**

```bash
grep -n "stokMinimumKontrolEt()" satin-alma.html
```
Expected: 2 satır (fonksiyon tanımı + init'teki çağrı).

- [ ] **Step 3: Kullanıcıya manuel test adımlarını bildir**

Kullanıcının tarayıcıda doğrulaması gereken akış (Node/Python bu ortamda yok, otomatik test yazılamıyor):
1. `stok-takip.html`'de bir ürünün minimum değerini yüksek bir sayıya ayarla (o üründe gerçek stok min altında kalsın).
2. `satin-alma.html`'i aç (`satinalma` veya `yonetici` rolüyle) → İç Talepler sekmesinde sarı uyarı şeridinin göründüğünü doğrula.
3. Şeride tıkla → otel bazlı gruplu öneri listesini gör, ürün adı/mevcut/minimum/önerilen miktarların doğru göründüğünü doğrula.
4. Bir kaç ürünün işaretini kaldır, "Seçilenlerden Talep Oluştur"a bas → başarı toast'ını gör.
5. İç Talepler listesinde yeni oluşan talebi bul, notunda "Otomatik stok kontrolü önerisi" yazdığını, departmanının "Depo" olduğunu doğrula.
6. Manuel "➕ İç Satın Alma Talebi" formunun (mevcut, Task 1'de refactor edilen `ytKaydet`) hâlâ eskisi gibi çalıştığını doğrula (regresyon kontrolü).

- [ ] **Step 4: Kullanıcıdan onay al, sonra push**

```bash
git fetch
git log --oneline main..origin/main
```
Expected: paralel oturumdan gelen değişiklik var mı kontrol et, varsa kullanıcıya bildir. Yoksa kullanıcı onayıyla `git push`.
