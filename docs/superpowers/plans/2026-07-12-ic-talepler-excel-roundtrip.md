# İç Talepler Excel Al/Ver Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `satin-alma.html`'in İç Talepler sekmesine, o an ekrandaki filtreye göre kalem bazlı Excel dışa aktarma ve Karar/Miktar kolonlu geri yükleme özelliği eklemek.

**Architecture:** Var olan `xlsx-js-style` lazy-load deseni (dosyada zaten `parseLNExcel()` içinde kullanılıyor) tekrar kullanılır. Yeni iki fonksiyon (`talepleriExcelAktar`, `talepExcelYukle`+`talepExcelUygula`) eklenir; geri yüklemede her talebin canlı durumu yazmadan hemen önce tekrar kontrol edilir.

**Tech Stack:** Vanilla HTML/JS, xlsx-js-style (CDN, mevcut), Supabase REST — build aracı/test çerçevesi yok.

## Global Constraints

- Dışa aktarım sadece o an ekrandaki `talepFilter`'a göre görünen listeyi kapsar (spec).
- `Kalem ID` kolonu export'ta bulunmalı ve import'ta eşleştirme için kullanılmalı (spec) — sadece ürün adına güvenilmez.
- Import'ta bir talebi güncellemeden HEMEN ÖNCE canlı durumu tekrar sorgulanır; `'bekleyen'` değilse o talep tamamen atlanır (spec).
- Aynı talebin satırlarında çelişkili `Karar` değeri varsa o talep tamamen atlanır (spec).
- Tek bir satırın/talebin hatası tüm içe aktarmayı durdurmaz — kalan satırlarla devam edilir (spec).

---

### Task 1: `loadDB()` — kalem `id`'sini `DB.talepler[...].satirlar`'a ekle

**Files:**
- Modify: `satin-alma.html:480` (loadDB içindeki satirlar mapping)

**Interfaces:**
- Consumes: yok.
- Produces: `DB.talepler[id].satirlar[i].id` — Task 3/4'ün kalem eşleştirmesi için gerekli.

- [ ] **Step 1: Mapping'e `id` ekle**

Mevcut satırı:
```js
satirlar:(r.satin_alma_talep_kalemleri||[]).map(k=>({ad:k.urun_adi,kod:k.urun_kodu||'',miktar:k.miktar,birim:k.birim}))
```
şuna çevir:
```js
satirlar:(r.satin_alma_talep_kalemleri||[]).map(k=>({id:k.id,ad:k.urun_adi,kod:k.urun_kodu||'',miktar:k.miktar,birim:k.birim}))
```

- [ ] **Step 2: Doğrula**

```bash
grep -n "satirlar:(r.satin_alma_talep_kalemleri" satin-alma.html
```
Expected: satırda `id:k.id,ad:k.urun_adi` görünmeli.

- [ ] **Step 3: Commit**

```bash
git add satin-alma.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "satin-alma.html: include kalem id in DB.talepler mapping"
```

---

### Task 2: İç Talepler sekmesine "Excel'e Aktar" / "Excel'den Yükle" butonlarını ekle

**Files:**
- Modify: `satin-alma.html:96-104` (İç Talepler tab HTML)

**Interfaces:**
- Consumes: yok (Task 3/4'te tanımlanacak `talepleriExcelAktar()`/`talepExcelYukle()` fonksiyonlarını çağıracak `onclick`/`onchange` — henüz tanımlı değiller, Task 3/4 sonrası çalışır hale gelir).
- Produces: `#talep-excel-input` (file input id) — Task 4'ün `talepExcelYukle(event)`'i bunun `onchange`'inden tetiklenir.

- [ ] **Step 1: Buton satırını ve gizli dosya input'unu ekle**

Mevcut:
```html
  <!-- İÇ TALEPLER -->
  <div class="sc" id="tab-talepler" style="display:block">
    <div class="ftabs" id="talep-ftabs">
      <button class="ftab active" onclick="filterTalep('tumu',this)">Tümü</button>
      <button class="ftab" onclick="filterTalep('bekleyen',this)">⏳ Bekleyen</button>
      <button class="ftab" onclick="filterTalep('onaylandi',this)">✅ Onaylanan</button>
      <button class="ftab" onclick="filterTalep('siparis',this)">📦 Siparişe Dönüştü</button>
    </div>
    <div id="talepler-liste"></div>
  </div>
```
şuna çevir:
```html
  <!-- İÇ TALEPLER -->
  <div class="sc" id="tab-talepler" style="display:block">
    <div class="ftabs" id="talep-ftabs">
      <button class="ftab active" onclick="filterTalep('tumu',this)">Tümü</button>
      <button class="ftab" onclick="filterTalep('bekleyen',this)">⏳ Bekleyen</button>
      <button class="ftab" onclick="filterTalep('onaylandi',this)">✅ Onaylanan</button>
      <button class="ftab" onclick="filterTalep('siparis',this)">📦 Siparişe Dönüştü</button>
    </div>
    <div class="brow" style="margin-bottom:10px">
      <button class="btn btn-sm btn-gray" onclick="talepleriExcelAktar()">📤 Excel'e Aktar</button>
      <button class="btn btn-sm btn-gray" onclick="document.getElementById('talep-excel-input').click()">📥 Excel'den Yükle</button>
      <input type="file" id="talep-excel-input" accept=".xlsx,.xls" style="display:none" onchange="talepExcelYukle(event)">
    </div>
    <div id="talepler-liste"></div>
  </div>
```

- [ ] **Step 2: Doğrula**

```bash
grep -n "talepleriExcelAktar\|talep-excel-input" satin-alma.html
```
Expected: en az 2 satır (buton onclick + input tanımı).

- [ ] **Step 3: Commit**

```bash
git add satin-alma.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "satin-alma.html: add Excel export/import buttons to İç Talepler tab"
```

---

### Task 3: Dışa aktarma fonksiyonu — `talepleriExcelAktar()`

**Files:**
- Modify: `satin-alma.html` — `parseLNExcel` fonksiyonunun hemen öncesine/sonrasına yeni fonksiyon ekle (dosyanın script bölümünde uygun bir yer, örn. `renderTalepler()`'den hemen sonra).

**Interfaces:**
- Consumes: `DB.talepler` (global, Task 1'de `id` eklenmiş `satirlar` içeriyor), `talepFilter` (global, mevcut).
- Produces: `talepleriExcelAktar()` — Task 2'nin butonu bunu çağırır.

- [ ] **Step 1: Fonksiyonu ekle**

```js
async function talepleriExcelAktar(){
  let liste=Object.values(DB.talepler||{}).filter(Boolean);
  if(talepFilter!=='tumu')liste=liste.filter(t=>t.durum===talepFilter);
  const satirlar=[];
  liste.forEach(t=>{
    (t.satirlar||[]).forEach(k=>{
      satirlar.push({
        'Talep ID':t.id,'Kalem ID':k.id||'','Departman':t.departman||'','Tarih':t.tarih||'',
        'Personel':t.personel||'','Aciliyet':t.aciliyet||'','Talep Notu':t.not||'',
        'Ürün Adı':k.ad||'','Miktar':k.miktar,'Birim':k.birim||'',
        'Mevcut Durum':t.durum||'','Karar':''
      });
    });
  });
  if(!satirlar.length){toast('⚠️ Aktarılacak talep yok');return;}
  if(typeof XLSX==='undefined'){
    sLD();
    await new Promise(r=>{const s=document.createElement('script');s.src='https://cdn.jsdelivr.net/npm/xlsx-js-style@1.2.0/dist/xlsx.bundle.js';s.onload=r;document.head.appendChild(s);});
    hLD();
  }
  const ws=XLSX.utils.json_to_sheet(satirlar);
  const wb=XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(wb,ws,'IcTalepler');
  XLSX.writeFile(wb,'ic-talepler-'+new Date().toISOString().split('T')[0]+'.xlsx');
  toast(`✅ ${satirlar.length} satır Excel'e aktarıldı`);
}
```

- [ ] **Step 2: Doğrula**

```bash
grep -n "async function talepleriExcelAktar" satin-alma.html
```
Expected: 1 satır.

- [ ] **Step 3: Commit**

```bash
git add satin-alma.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "satin-alma.html: implement İç Talepler Excel export"
```

---

### Task 4: Geri yükleme fonksiyonları — `talepExcelYukle()` + `talepExcelUygula()`

**Files:**
- Modify: `satin-alma.html` — Task 3'te eklenen `talepleriExcelAktar()`'ın hemen ardına.

**Interfaces:**
- Consumes: `DB.talepler` (global), `SB_URL`/`SB_HEADERS` (global, mevcut), `sLD()`/`hLD()`/`toast()` (global, mevcut), `loadDB()`/`renderTalepler()` (global, mevcut).
- Produces: `talepExcelYukle(event)` — Task 2'nin `#talep-excel-input` onchange'i bunu çağırır.

- [ ] **Step 1: Fonksiyonları ekle**

```js
async function talepExcelYukle(event){
  const file=event.target.files[0];if(!file)return;event.target.value='';
  if(typeof XLSX==='undefined'){
    sLD();
    await new Promise(r=>{const s=document.createElement('script');s.src='https://cdn.jsdelivr.net/npm/xlsx-js-style@1.2.0/dist/xlsx.bundle.js';s.onload=r;document.head.appendChild(s);});
    hLD();
  }
  sLD();
  const reader=new FileReader();
  reader.onload=async e=>{
    try{
      const wb=XLSX.read(e.target.result,{type:'array',raw:false});
      const ws=wb.Sheets[wb.SheetNames[0]];
      const rows=XLSX.utils.sheet_to_json(ws,{raw:false});
      await talepExcelUygula(rows);
    }catch(err){hLD();toast('❌ Dosya okunamadı: '+err.message);}
  };
  reader.readAsArrayBuffer(file);
}

async function talepExcelUygula(rows){
  const gruplar={};
  rows.forEach(r=>{
    const talepId=String(r['Talep ID']||'').trim();
    if(!talepId)return;
    if(!gruplar[talepId])gruplar[talepId]=[];
    gruplar[talepId].push(r);
  });

  let onaylanan=0,reddedilen=0,miktarGuncellenen=0;
  const atlananlar=[];

  for(const talepId of Object.keys(gruplar)){
    const satirlar=gruplar[talepId];
    const talep=DB.talepler[talepId];
    if(!talep){atlananlar.push({talepId,sebep:'talep bulunamadı'});continue;}

    // Canlı durumu tazele — önbellekteki DB.talepler bayat olabilir.
    let canliDurum=talep.durum;
    try{
      const r=await fetch(SB_URL+'/rest/v1/satin_alma_talepleri?id=eq.'+talepId+'&select=durum',{headers:SB_HEADERS});
      if(r.ok){const d=await r.json();if(d[0])canliDurum=d[0].durum;}
    }catch(e){}
    if(canliDurum!=='bekleyen'){atlananlar.push({talepId,sebep:'zaten karara bağlanmış ('+canliDurum+')'});continue;}

    // Karar çelişkisi kontrolü — aynı talebin satırlarında farklı Karar varsa atla.
    const kararlar=[...new Set(satirlar.map(s=>String(s['Karar']||'').trim()).filter(Boolean))];
    if(kararlar.length>1){atlananlar.push({talepId,sebep:'çelişkili karar: '+kararlar.join(', ')});continue;}
    const karar=kararlar[0]||'';

    // Miktar güncellemeleri — Kalem ID ile eşleştir.
    for(const satir of satirlar){
      const kalemId=String(satir['Kalem ID']||'').trim();
      if(!kalemId)continue;
      const kalem=(talep.satirlar||[]).find(k=>String(k.id)===kalemId);
      if(!kalem)continue;
      const yeniMiktar=parseFloat(satir['Miktar']);
      if(!isNaN(yeniMiktar)&&yeniMiktar!==parseFloat(kalem.miktar)){
        try{
          await fetch(SB_URL+'/rest/v1/satin_alma_talep_kalemleri?id=eq.'+kalemId,{method:'PATCH',headers:SB_HEADERS,body:JSON.stringify({miktar:yeniMiktar})});
          miktarGuncellenen++;
        }catch(e){}
      }
    }

    // Karar uygula — talepOnayla()/talepReddet() ile AYNI PATCH.
    if(karar==='Onayla'){
      try{await fetch(SB_URL+'/rest/v1/satin_alma_talepleri?id=eq.'+talepId,{method:'PATCH',headers:SB_HEADERS,body:JSON.stringify({durum:'onaylandi'})});onaylanan++;}catch(e){}
    }else if(karar==='Reddet'){
      try{await fetch(SB_URL+'/rest/v1/satin_alma_talepleri?id=eq.'+talepId,{method:'PATCH',headers:SB_HEADERS,body:JSON.stringify({durum:'reddedildi'})});reddedilen++;}catch(e){}
    }
  }

  hLD();
  await loadDB();
  renderTalepler();
  let mesaj=`✅ ${onaylanan} onaylandı, ${reddedilen} reddedildi, ${miktarGuncellenen} kalem miktarı güncellendi.`;
  if(atlananlar.length){
    mesaj+=` ⚠️ ${atlananlar.length} satır atlandı.`;
    console.warn('Excel içe aktarma — atlanan talepler:',atlananlar);
  }
  toast(mesaj,4000);
}
```

- [ ] **Step 2: Doğrula**

```bash
grep -n "async function talepExcelYukle\|async function talepExcelUygula" satin-alma.html
```
Expected: 2 satır.

- [ ] **Step 3: Commit**

```bash
git add satin-alma.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "satin-alma.html: implement İç Talepler Excel import with live re-check and conflict detection"
```

---

### Task 5: Statik doğrulama + kullanıcı testi için özet

**Files:** Yok (sadece doğrulama)

- [ ] **Step 1: Sözdizimi/tutarlılık kontrolü**

```bash
grep -c "talepleriExcelAktar\|talepExcelYukle\|talepExcelUygula" satin-alma.html
```
Expected: en az 5 (2 tanım/çağrı talepleriExcelAktar için, 2 talepExcelYukle için [tanım+onchange], 2 talepExcelUygula için [tanım+çağrı] — tam sayı önemli değil, sıfır olmaması önemli).

- [ ] **Step 2: Kod okuyarak izleme (manuel)**

`talepExcelUygula` fonksiyonunu baştan sona oku ve şunu doğrula: "Karar çelişkisi kontrolü" bloğu `for(const talepId of Object.keys(gruplar))` döngüsünün içinde, "Miktar güncellemeleri" bloğundan ÖNCE gelir ve çelişki varsa `continue` ile bir sonraki talebe geçer — yani çelişkili kararda miktar güncellemesi de dahil o talebin TÜM işlemleri atlanır (spec'in istediği budur). Kod bu sırayla yazıldıysa (Task 4 Step 1'deki kod bloğunda öyle) ek bir düzeltme gerekmez.

- [ ] **Step 3: Kullanıcı testi (bu oturumun dışında)**

Kullanıcı gerçek bir tarayıcıda: birkaç bekleyen talebi Excel'e aktarsın, birine "Onayla" birine "Reddet" yazsın, birinin miktarını değiştirsin, geri yüklesin, sonuçları (durum değişimi + miktar güncellemesi + özet mesajı) doğrulasın.
