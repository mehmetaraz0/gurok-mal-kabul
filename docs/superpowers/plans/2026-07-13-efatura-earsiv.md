# e-Fatura/e-Arşiv Entegrasyonu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `muhasebe-faturalar.html`'e, gerçek GİB entegratör API'si gelene kadar simülasyon modunda çalışan, satış faturalarını gönderen ve tedarikçilerden gelen e-faturaları otomatik alış-faturası taslağına çeviren bir e-Fatura/e-Arşiv katmanı eklemek.

**Architecture:** Tek bir paylaşılan adapter dosyası (`efatura-adapter.js`, `auth-guard.js` ile aynı `<script src=...>` deseni) iki fonksiyon sunar (`eFaturaGonder`, `eFaturaGelenleriCek`); `EFATURA_SIMULASYON=true` iken ikisi de sahte veri üretir. `muhasebe-faturalar.html` bu iki fonksiyonu çağırır, sonucu `faturalar`/`gelen_efaturalar` Supabase tablolarına yazar. Gerçek API geldiğinde sadece adapter dosyasının içi değişir.

**Tech Stack:** Vanilla HTML/JS, Supabase REST (fetch), mevcut `toast()`/`sLD()`/`hLD()`/`escapeHtml()`/`fmt()` yardımcıları — build aracı/test çerçevesi yok (Node/Python bu ortamda yok).

## Global Constraints

- Sadece satış faturaları entegratöre gönderilir; alış faturalarında gönder butonu YOK (spec).
- Yeni Supabase kolonları TEXT olacak, ENUM olmayacak — bu oturumda bir ENUM kısıtı yüzünden gerçek bir prod hatası yaşandı, tekrarlanmayacak (spec).
- `EFATURA_SIMULASYON=true` iken hiçbir gerçek ağ çağrısı GİB'e/entegratöre gitmez; ekranda her zaman "⚠️ SİMÜLASYON MODU" görünür (spec).
- Gelen e-faturalar mevcut "Alış Faturaları" sekmesindeki `durum==='taslak'` filtresiyle görüntülenir — yeni bir onay ekranı YOK (spec).
- `onaylandi` ve `iptal` efatura_durum değerleri bu iterasyonda UI'dan set edilmez, sadece şema/gelecek için yer tutar (spec).

---

### Task 1: `efatura-adapter.js` — simülasyon modunda adapter

**Files:**
- Create: `efatura-adapter.js` (repo kökü)

**Interfaces:**
- Produces: `eFaturaGonder(fatura, cari)` → `Promise<{basarili, ettn, gibFaturaNo, pdfUrl, hataMesaji, tip}>`
- Produces: `eFaturaGelenleriCek(sonCekimTarihi)` → `Promise<Array<{ettn, gibFaturaNo, gonderenVkn, gonderenAd, tarih, kalemler, araToplam, kdvToplam, genelToplam}>>`
- Produces: `const EFATURA_SIMULASYON` (global, `muhasebe-faturalar.html` bu bayrağı okuyarak "SİMÜLASYON MODU" şeridini gösterir)

- [ ] **Step 1: Dosyayı oluştur**

```js
// efatura-adapter.js
// GİB onaylı entegratör (Paraşüt/Logo/Foriba/İzibiz/Uyumsoft vb.) API'sine bağlanana
// kadar simülasyon modunda çalışır. Gerçek API geldiğinde EFATURA_SIMULASYON=false
// yapılıp iki fonksiyonun gövdesi gerçek fetch() çağrılarıyla değiştirilir — çağıran
// taraf (muhasebe-faturalar.html) değişmez, çünkü dönüş şekli sabit kalıyor.
const EFATURA_SIMULASYON = true;

function _efaturaGecikme(ms) {
  return new Promise(r => setTimeout(r, ms));
}

function _efaturaSahteNo(prefix) {
  const yil = new Date().getFullYear();
  const sira = String(Math.floor(Math.random() * 999999999999)).padStart(12, '0');
  return `${prefix}${yil}${sira}`;
}

// fatura: camelCase fatura nesnesi ({tur, no, kalemler, ...}), cari: camelCase cari nesnesi ({efatura, ...})
async function eFaturaGonder(fatura, cari) {
  if (EFATURA_SIMULASYON) {
    await _efaturaGecikme(1500);
    if (Math.random() < 0.1) {
      return { basarili: false, hataMesaji: 'Simüle hata: entegratör yanıt vermedi', ettn: null, gibFaturaNo: null, pdfUrl: null, tip: null };
    }
    const tip = cari?.efatura === 'evet' ? 'e-fatura' : 'e-arsiv';
    return {
      basarili: true,
      ettn: crypto.randomUUID(),
      gibFaturaNo: _efaturaSahteNo(fatura.tur === 'satis' ? 'SAT' : 'ALI'),
      pdfUrl: `https://simulasyon.local/efatura/${crypto.randomUUID()}.pdf`,
      hataMesaji: null,
      tip
    };
  }
  throw new Error('Gerçek entegratör API entegrasyonu henüz yapılmadı');
}

// sonCekimTarihi: ms epoch veya null — simülasyonda kullanılmıyor, gerçek API'de "bu tarihten sonrakileri getir" için kullanılacak
async function eFaturaGelenleriCek(sonCekimTarihi) {
  if (EFATURA_SIMULASYON) {
    await _efaturaGecikme(1500);
    const adet = Math.floor(Math.random() * 3); // 0, 1 veya 2 sahte fatura
    const sonuc = [];
    for (let i = 0; i < adet; i++) {
      const birimFiyat = Math.round((Math.random() * 900 + 100) * 100) / 100;
      const miktar = Math.floor(Math.random() * 10) + 1;
      const kdvOran = 20;
      const araToplam = Math.round(birimFiyat * miktar * 100) / 100;
      const kdvToplam = Math.round(araToplam * kdvOran / 100 * 100) / 100;
      sonuc.push({
        ettn: crypto.randomUUID(),
        gibFaturaNo: _efaturaSahteNo('SIM'),
        gonderenVkn: String(Math.floor(1000000000 + Math.random() * 8999999999)),
        gonderenAd: 'Simülasyon Tedarikçi ' + (i + 1),
        tarih: new Date().toISOString().split('T')[0],
        kalemler: [{
          kod: '', ad: 'Simüle Ürün ' + (i + 1), miktar, birim: 'Adet',
          birimFiyat, kdvOran, toplam: araToplam + kdvToplam
        }],
        araToplam, kdvToplam, genelToplam: araToplam + kdvToplam
      });
    }
    return sonuc;
  }
  throw new Error('Gerçek entegratör API entegrasyonu henüz yapılmadı');
}
```

- [ ] **Step 2: Doğrula**

```bash
grep -n "^const EFATURA_SIMULASYON\|^async function eFaturaGonder\|^async function eFaturaGelenleriCek" efatura-adapter.js
```
Expected: 3 satır — bayrak ve iki fonksiyon tanımı.

- [ ] **Step 3: Commit**

```bash
git add efatura-adapter.js
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: add efatura-adapter.js (simulation-mode e-Fatura/e-Arsiv adapter)"
```

---

### Task 2: Supabase şema değişikliği (kullanıcı tarafından çalıştırılır)

**Files:**
- Modify: Supabase SQL Editor (kod tabanında dosya yok, bu adım kullanıcının Supabase dashboard'unda çalıştırması için)

**Interfaces:**
- Produces: `faturalar` tablosunda 7 yeni TEXT/timestamptz kolon; yeni `gelen_efaturalar` tablosu — Task 3/4/5'in `faturaSbdenCamele`/`loadDB`/PATCH çağrıları bu kolonlara/tabloya yazar.

- [ ] **Step 1: Kullanıcıya SQL'i ver, Supabase SQL Editor'de çalıştırmasını iste**

```sql
ALTER TABLE faturalar
  ADD COLUMN IF NOT EXISTS efatura_durum text,
  ADD COLUMN IF NOT EXISTS efatura_tip text,
  ADD COLUMN IF NOT EXISTS ettn text,
  ADD COLUMN IF NOT EXISTS gib_fatura_no text,
  ADD COLUMN IF NOT EXISTS gib_pdf_url text,
  ADD COLUMN IF NOT EXISTS efatura_gonderim_tarihi timestamptz,
  ADD COLUMN IF NOT EXISTS efatura_hata_mesaji text;

CREATE TABLE IF NOT EXISTS gelen_efaturalar (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ettn text,
  gonderen_vkn text,
  gonderen_ad text,
  tarih date,
  kalemler jsonb,
  ara_toplam numeric,
  kdv_toplam numeric,
  genel_toplam numeric,
  durum text DEFAULT 'yeni',
  alis_fatura_id uuid,
  olusturma_tarihi timestamptz DEFAULT now()
);
```

- [ ] **Step 2: Kullanıcı çalıştırdıktan sonra, güvenli (salt okunur) bir REST sorgusuyla doğrula**

```bash
curl -s "https://xwytofysmgqtqjzkplfi.supabase.co/rest/v1/faturalar?select=efatura_durum,ettn&limit=1" -H "apikey: <SB_KEY>" -H "Authorization: Bearer <SB_KEY>"
curl -s "https://xwytofysmgqtqjzkplfi.supabase.co/rest/v1/gelen_efaturalar?select=id&limit=1" -H "apikey: <SB_KEY>" -H "Authorization: Bearer <SB_KEY>"
```
Expected: İkisi de `200` ve `[]` veya kayıt listesi döner (400/`column does not exist` DÖNMEMELİ — dönerse kullanıcıya SQL'i tekrar çalıştırması gerektiği söylenir).

---

### Task 3: `muhasebe-faturalar.html` — adapter'ı bağla, veri modelini genişlet

**Files:**
- Modify: `muhasebe-faturalar.html:5-9` (script include)
- Modify: `muhasebe-faturalar.html:261` (global state)
- Modify: `muhasebe-faturalar.html:371-389` (`faturaSbdenCamele`)
- Modify: `muhasebe-faturalar.html:400-416` (`loadDB`)
- Modify: `muhasebe-faturalar.html:390-398` sonrası (yeni `gelenEfaturaSbdenCamele` fonksiyonu)

**Interfaces:**
- Consumes: `eFaturaGonder`, `eFaturaGelenleriCek`, `EFATURA_SIMULASYON` (Task 1'den, `efatura-adapter.js`)
- Produces: `faturalar[id].efaturaDurum/efaturaTip/ettn/gibFaturaNo/gibPdfUrl/efaturaGonderimTarihi/efaturaHataMesaji` (Task 4 bunu okuyacak); `gelenEfaturalar` global obje ve `gelenEfaturaSbdenCamele(r)` (Task 5 bunu kullanacak)

- [ ] **Step 1: `efatura-adapter.js`'i script olarak ekle**

Mevcut (satır 5-9):
```html
<script src="auth-guard.js"></script>
<script>
let OTURUM_KULLANICI = requireLogin();
if (OTURUM_KULLANICI) requireRole(OTURUM_KULLANICI, ['yonetici','satinalma']);
</script>
```
şuna çevir:
```html
<script src="auth-guard.js"></script>
<script src="efatura-adapter.js"></script>
<script>
let OTURUM_KULLANICI = requireLogin();
if (OTURUM_KULLANICI) requireRole(OTURUM_KULLANICI, ['yonetici','satinalma']);
</script>
```

- [ ] **Step 2: Global state'e `gelenEfaturalar` ekle**

Mevcut (satır 261):
```js
let faturalar={},cariler={},malKabulFormlar={},satinAlmaSiparisler={};
```
şuna çevir:
```js
let faturalar={},cariler={},malKabulFormlar={},satinAlmaSiparisler={},gelenEfaturalar={};
```

- [ ] **Step 3: `faturaSbdenCamele`'e yeni alanları ekle**

Mevcut (satır 371-389):
```js
function faturaSbdenCamele(r){
  return{
    id:r.id,no:r.no,tur:r.tur,tarih:r.tarih,vade:r.vade_tarihi||'',
    cariId:r.cari_id,cariAd:r.cari_ad,siparisNo:r.siparis_no||'',
    araToplam:parseFloat(r.ara_toplam)||0,kdvToplam:parseFloat(r.kdv_toplam)||0,
    genelToplam:parseFloat(r.genel_toplam)||0,komisyonOrani:parseFloat(r.komisyon_orani)||0,
    komisyonTutari:parseFloat(r.komisyon_tutari)||0,iade:!!r.iade,otelId:r.otel_id,
    not:r.not_alani||'',durum:r.durum,
    odemeTarih:r.odeme_tarihi?new Date(r.odeme_tarihi).getTime():null,
    odemeTutar:r.odeme_tutari?parseFloat(r.odeme_tutari):null,odemeYontem:r.odeme_yontemi||'',
    kalemler:(r.fatura_kalemleri||[]).map(k=>({
      kod:k.urun_kodu||'',ad:k.urun_adi,miktar:parseFloat(k.miktar),birim:k.birim,
      birimFiyat:parseFloat(k.birim_fiyat),iskonto:parseFloat(k.iskonto_yuzde)||0,
      kdvOran:parseFloat(k.kdv_orani),toplam:parseFloat(k.toplam)
    })),
    olusturmaTarih:r.olusturma_tarihi?new Date(r.olusturma_tarihi).getTime():Date.now(),
    guncellemeTarih:r.guncelleme_tarihi?new Date(r.guncelleme_tarihi).getTime():Date.now()
  };
}
```
şuna çevir:
```js
function faturaSbdenCamele(r){
  return{
    id:r.id,no:r.no,tur:r.tur,tarih:r.tarih,vade:r.vade_tarihi||'',
    cariId:r.cari_id,cariAd:r.cari_ad,siparisNo:r.siparis_no||'',
    araToplam:parseFloat(r.ara_toplam)||0,kdvToplam:parseFloat(r.kdv_toplam)||0,
    genelToplam:parseFloat(r.genel_toplam)||0,komisyonOrani:parseFloat(r.komisyon_orani)||0,
    komisyonTutari:parseFloat(r.komisyon_tutari)||0,iade:!!r.iade,otelId:r.otel_id,
    not:r.not_alani||'',durum:r.durum,
    odemeTarih:r.odeme_tarihi?new Date(r.odeme_tarihi).getTime():null,
    odemeTutar:r.odeme_tutari?parseFloat(r.odeme_tutari):null,odemeYontem:r.odeme_yontemi||'',
    efaturaDurum:r.efatura_durum||null,efaturaTip:r.efatura_tip||null,
    ettn:r.ettn||null,gibFaturaNo:r.gib_fatura_no||null,gibPdfUrl:r.gib_pdf_url||null,
    efaturaGonderimTarihi:r.efatura_gonderim_tarihi?new Date(r.efatura_gonderim_tarihi).getTime():null,
    efaturaHataMesaji:r.efatura_hata_mesaji||null,
    kalemler:(r.fatura_kalemleri||[]).map(k=>({
      kod:k.urun_kodu||'',ad:k.urun_adi,miktar:parseFloat(k.miktar),birim:k.birim,
      birimFiyat:parseFloat(k.birim_fiyat),iskonto:parseFloat(k.iskonto_yuzde)||0,
      kdvOran:parseFloat(k.kdv_orani),toplam:parseFloat(k.toplam)
    })),
    olusturmaTarih:r.olusturma_tarihi?new Date(r.olusturma_tarihi).getTime():Date.now(),
    guncellemeTarih:r.guncelleme_tarihi?new Date(r.guncelleme_tarihi).getTime():Date.now()
  };
}
```

- [ ] **Step 4: `gelenEfaturaSbdenCamele` fonksiyonunu ekle**

`cariSbdenCamele` fonksiyonunun kapanış `}`'ının hemen ardına (satır 398 civarı) ekle:

```js
function gelenEfaturaSbdenCamele(r){
  return{
    id:r.id,ettn:r.ettn,gibFaturaNo:r.gib_fatura_no||'',gonderenVkn:r.gonderen_vkn||'',
    gonderenAd:r.gonderen_ad||'',tarih:r.tarih,kalemler:r.kalemler||[],
    araToplam:parseFloat(r.ara_toplam)||0,kdvToplam:parseFloat(r.kdv_toplam)||0,
    genelToplam:parseFloat(r.genel_toplam)||0,durum:r.durum,alisFaturaId:r.alis_fatura_id||null,
    olusturmaTarih:r.olusturma_tarihi?new Date(r.olusturma_tarihi).getTime():Date.now()
  };
}
```

- [ ] **Step 5: `loadDB`'ye `gelen_efaturalar` fetch'i ekle**

Mevcut (satır 400-416):
```js
async function loadDB(){
  sLD();
  try{
    const [fR,cR,mkR,spR]=await Promise.all([
      fetch(SB_URL+'/rest/v1/faturalar?select=*,fatura_kalemleri(*)',{headers:SB_HEADERS}),
      fetch(SB_URL+'/rest/v1/cariler?select=*',{headers:SB_HEADERS}),
      fetch(SB_URL+'/rest/v1/mal_kabuller?select=*,mal_kabul_urunleri(*)',{headers:SB_HEADERS}),
      fetch(SB_URL+'/rest/v1/siparisler?select=*,siparis_kalemleri(*)',{headers:SB_HEADERS}),
    ]);
    faturalar={};cariler={};malKabulFormlar={};satinAlmaSiparisler={};
    if(fR.ok){(await fR.json()).forEach(r=>{faturalar[r.id]=faturaSbdenCamele(r);});}
    if(cR.ok){(await cR.json()).forEach(r=>{cariler[r.id]=cariSbdenCamele(r);});}
    if(mkR.ok){(await mkR.json()).forEach(r=>{malKabulFormlar[r.id]=malKabulSbdenCamele(r);});}
    if(spR.ok){(await spR.json()).forEach(r=>{satinAlmaSiparisler[r.siparis_no]=siparisSbdenCamele(r);});}
  }catch(e){console.warn(e);}
  hLD();
}
```
şuna çevir:
```js
async function loadDB(){
  sLD();
  try{
    const [fR,cR,mkR,spR,geR]=await Promise.all([
      fetch(SB_URL+'/rest/v1/faturalar?select=*,fatura_kalemleri(*)',{headers:SB_HEADERS}),
      fetch(SB_URL+'/rest/v1/cariler?select=*',{headers:SB_HEADERS}),
      fetch(SB_URL+'/rest/v1/mal_kabuller?select=*,mal_kabul_urunleri(*)',{headers:SB_HEADERS}),
      fetch(SB_URL+'/rest/v1/siparisler?select=*,siparis_kalemleri(*)',{headers:SB_HEADERS}),
      fetch(SB_URL+'/rest/v1/gelen_efaturalar?select=*&order=olusturma_tarihi.desc',{headers:SB_HEADERS}),
    ]);
    faturalar={};cariler={};malKabulFormlar={};satinAlmaSiparisler={};gelenEfaturalar={};
    if(fR.ok){(await fR.json()).forEach(r=>{faturalar[r.id]=faturaSbdenCamele(r);});}
    if(cR.ok){(await cR.json()).forEach(r=>{cariler[r.id]=cariSbdenCamele(r);});}
    if(mkR.ok){(await mkR.json()).forEach(r=>{malKabulFormlar[r.id]=malKabulSbdenCamele(r);});}
    if(spR.ok){(await spR.json()).forEach(r=>{satinAlmaSiparisler[r.siparis_no]=siparisSbdenCamele(r);});}
    if(geR.ok){(await geR.json()).forEach(r=>{gelenEfaturalar[r.id]=gelenEfaturaSbdenCamele(r);});}
  }catch(e){console.warn(e);}
  hLD();
}
```

- [ ] **Step 6: Doğrula**

```bash
grep -n "efatura-adapter.js\|gelenEfaturalar\|gelenEfaturaSbdenCamele\|efaturaDurum" muhasebe-faturalar.html
```
Expected: script include satırı + global state satırı + `faturaSbdenCamele` içindeki yeni alanlar + `gelenEfaturaSbdenCamele` tanımı + `loadDB` içindeki `geR` fetch/parse satırları — hepsi görünmeli.

- [ ] **Step 7: Commit**

```bash
git add muhasebe-faturalar.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: wire efatura-adapter.js into muhasebe-faturalar.html data layer"
```

---

### Task 4: Satış akışı — giden e-Fatura/e-Arşiv gönderimi

**Files:**
- Modify: `muhasebe-faturalar.html:551-595` (`openFaturaDetay`)
- Modify: `muhasebe-faturalar.html` — `openFaturaDetay`'ın hemen ardına yeni fonksiyon eklenir

**Interfaces:**
- Consumes: `eFaturaGonder(fatura,cari)` (Task 1), `faturalar[id]`/`cariler[id]` (Task 3'ten genişletilmiş şekil), `toast()`, `escapeHtml()`, `fmt()`, `SB_URL`, `SB_HEADERS` (mevcut)
- Produces: `eFaturaGonderTikla(id)` — butonun `onclick`'i bunu çağırır

- [ ] **Step 1: `openFaturaDetay`'a e-Fatura bloğunu ekle**

Mevcut (satır 551-563):
```js
function openFaturaDetay(id){
  const f=faturalar[id];if(!f)return;
  document.getElementById('mFaturaDetayTitle').textContent=f.no;
  const durumChip={taslak:'<span class="chip chip-gray">📝 Taslak</span>',bekliyor:'<span class="chip chip-yellow">⏳ Bekliyor</span>',onaylandi:'<span class="chip chip-green">✅ Onaylı</span>',kismi_odendi:'<span class="chip chip-orange">💰 Kısmi Ödendi</span>',odendi:'<span class="chip chip-blue">💳 Ödendi</span>',iptal:'<span class="chip chip-red">❌ İptal</span>'};
  document.getElementById('mFaturaDetayIc').innerHTML=`
    <div style="display:flex;justify-content:space-between;margin-bottom:12px">
      <div>
        <div style="font-size:15px;font-weight:700">${escapeHtml(f.cariAd)||'—'}</div>
        <div style="font-size:12px;color:var(--gray-500)">${f.tarih} ${f.vade?'• Vade: '+f.vade:''}</div>
      </div>
      ${durumChip[f.durum]||''}
    </div>
    ${f.siparisNo||f.otelId?`<div style="margin-bottom:8px;display:flex;gap:6px;flex-wrap:wrap">${f.siparisNo?`<span class="chip chip-purple">📋 LN Sipariş: ${f.siparisNo}</span>`:''}${f.otelId?`<span class="chip ${f.otelId==='811'?'chip-blue':'chip-orange'}">🏨 ${OTEL_ISIMLERI[f.otelId]||f.otelId}</span>`:''}</div>`:''}
```
şuna çevir:
```js
function openFaturaDetay(id){
  const f=faturalar[id];if(!f)return;
  document.getElementById('mFaturaDetayTitle').textContent=f.no;
  const durumChip={taslak:'<span class="chip chip-gray">📝 Taslak</span>',bekliyor:'<span class="chip chip-yellow">⏳ Bekliyor</span>',onaylandi:'<span class="chip chip-green">✅ Onaylı</span>',kismi_odendi:'<span class="chip chip-orange">💰 Kısmi Ödendi</span>',odendi:'<span class="chip chip-blue">💳 Ödendi</span>',iptal:'<span class="chip chip-red">❌ İptal</span>'};
  const efDurumChip={taslak:'<span class="chip chip-gray">📝 Taslak</span>',gonderiliyor:'<span class="chip chip-yellow">⏳ Gönderiliyor</span>',gonderildi:'<span class="chip chip-blue">✅ Gönderildi</span>',onaylandi:'<span class="chip chip-green">✔️ Onaylandı</span>',reddedildi:'<span class="chip chip-red">❌ Reddedildi</span>',iptal:'<span class="chip chip-gray">🚫 İptal</span>'};
  document.getElementById('mFaturaDetayIc').innerHTML=`
    <div style="display:flex;justify-content:space-between;margin-bottom:12px">
      <div>
        <div style="font-size:15px;font-weight:700">${escapeHtml(f.cariAd)||'—'}</div>
        <div style="font-size:12px;color:var(--gray-500)">${f.tarih} ${f.vade?'• Vade: '+f.vade:''}</div>
      </div>
      ${durumChip[f.durum]||''}
    </div>
    ${f.siparisNo||f.otelId?`<div style="margin-bottom:8px;display:flex;gap:6px;flex-wrap:wrap">${f.siparisNo?`<span class="chip chip-purple">📋 LN Sipariş: ${f.siparisNo}</span>`:''}${f.otelId?`<span class="chip ${f.otelId==='811'?'chip-blue':'chip-orange'}">🏨 ${OTEL_ISIMLERI[f.otelId]||f.otelId}</span>`:''}</div>`:''}
    ${f.tur==='satis'?`
    <div style="background:#fff7ed;border:1px solid #fed7aa;border-radius:8px;padding:8px 10px;margin-bottom:10px;font-size:11px;color:#92400e;font-weight:600">⚠️ SİMÜLASYON MODU — gerçek GİB gönderimi yapılmıyor</div>
    <div style="display:flex;align-items:center;gap:8px;margin-bottom:10px;flex-wrap:wrap">
      ${efDurumChip[f.efaturaDurum]||'<span class="chip chip-gray">— Gönderilmedi</span>'}
      ${!f.efaturaDurum||f.efaturaDurum==='reddedildi'||(f.efaturaDurum==='gonderiliyor'&&Date.now()-(f.efaturaGonderimTarihi||0)>120000)?`<button class="btn btn-sm ${f.efaturaDurum==='reddedildi'?'btn-danger':'btn-primary'}" onclick="eFaturaGonderTikla('${id}')">📤 ${cariler[f.cariId]?.efatura==='evet'?'e-Fatura Gönder':'e-Arşiv Gönder'}</button>`:''}
      ${f.efaturaDurum==='gonderiliyor'&&Date.now()-(f.efaturaGonderimTarihi||0)<=120000?'<span style="font-size:11px;color:var(--gray-500)">Gönderiliyor, bekleyin...</span>':''}
    </div>
    ${f.ettn?`<div style="font-size:11px;color:var(--gray-600);margin-bottom:6px">ETTN: ${f.ettn}${f.gibFaturaNo?' • GİB No: '+f.gibFaturaNo:''}</div>`:''}
    ${f.efaturaHataMesaji?`<div style="font-size:11px;color:var(--danger);margin-bottom:6px">⚠️ ${escapeHtml(f.efaturaHataMesaji)}</div>`:''}
    `:''}
```

- [ ] **Step 2: `eFaturaGonderTikla` fonksiyonunu ekle**

`openFaturaDetay` fonksiyonunun kapanış `}`'ının hemen ardına (satır 595 civarı) ekle:

```js
async function eFaturaGonderTikla(id){
  const f=faturalar[id];if(!f||f.tur!=='satis')return;
  const cari=cariler[f.cariId]||null;
  f.efaturaDurum='gonderiliyor';f.efaturaGonderimTarihi=Date.now();
  await fetch(SB_URL+'/rest/v1/faturalar?id=eq.'+id,{method:'PATCH',headers:SB_HEADERS,body:JSON.stringify({
    efatura_durum:'gonderiliyor',efatura_gonderim_tarihi:new Date(f.efaturaGonderimTarihi).toISOString()
  })});
  openFaturaDetay(id);
  const sonuc=await eFaturaGonder(f,cari);
  if(sonuc.basarili){
    f.efaturaDurum='gonderildi';f.efaturaTip=sonuc.tip;f.ettn=sonuc.ettn;
    f.gibFaturaNo=sonuc.gibFaturaNo;f.gibPdfUrl=sonuc.pdfUrl;f.efaturaHataMesaji=null;
    await fetch(SB_URL+'/rest/v1/faturalar?id=eq.'+id,{method:'PATCH',headers:SB_HEADERS,body:JSON.stringify({
      efatura_durum:'gonderildi',efatura_tip:sonuc.tip,ettn:sonuc.ettn,
      gib_fatura_no:sonuc.gibFaturaNo,gib_pdf_url:sonuc.pdfUrl,efatura_hata_mesaji:null
    })});
    toast(`✅ ${sonuc.tip==='e-fatura'?'e-Fatura':'e-Arşiv'} gönderildi (simülasyon)`);
  }else{
    f.efaturaDurum='reddedildi';f.efaturaHataMesaji=sonuc.hataMesaji;
    await fetch(SB_URL+'/rest/v1/faturalar?id=eq.'+id,{method:'PATCH',headers:SB_HEADERS,body:JSON.stringify({
      efatura_durum:'reddedildi',efatura_hata_mesaji:sonuc.hataMesaji
    })});
    toast(`❌ Gönderim başarısız: ${sonuc.hataMesaji}`);
  }
  openFaturaDetay(id);
}
```

- [ ] **Step 3: Doğrula**

```bash
grep -n "function eFaturaGonderTikla\|onclick=\"eFaturaGonderTikla" muhasebe-faturalar.html
```
Expected: fonksiyon tanımı + `openFaturaDetay` içindeki buton `onclick` çağrısı görünmeli.

- [ ] **Step 4: Kod okuyarak izleme**

`eFaturaGonderTikla`'nın hem yerel `faturalar[id]` nesnesini hem Supabase satırını güncellediğini, ve her iki PATCH çağrısının aynı alan adlarını (`efatura_durum`, `ettn`, `gib_fatura_no`, `gib_pdf_url`, `efatura_hata_mesaji`) Task 2'deki SQL'de tanımlanan kolon adlarıyla birebir eşleştiğini satır satır karşılaştırarak doğrula.

- [ ] **Step 5: Commit**

```bash
git add muhasebe-faturalar.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: add outbound e-Fatura/e-Arsiv sending flow to satis invoices"
```

---

### Task 5: Alış akışı — gelen e-Fatura kutusu ve otomatik taslak oluşturma

**Files:**
- Modify: `muhasebe-faturalar.html:85-90` (tab-bar)
- Modify: `muhasebe-faturalar.html:141-144` (tab içerikleri — `tab-odeme`'den sonra yeni `tab-gelenkutu` eklenir)
- Modify: `muhasebe-faturalar.html:1107-1117` (`gTab`)
- Modify: `muhasebe-faturalar.html` — yeni `renderGelenKutusu()`, `eFaturaKontrolEt()`, `gelenEfaturaTaslakOlustur(g)` fonksiyonları eklenir

**Interfaces:**
- Consumes: `eFaturaGelenleriCek(sonCekimTarihi)` (Task 1), `gelenEfaturalar`/`cariler`/`saveFatura` şekli (Task 3, mevcut `saveFatura` fonksiyonu), `toast()`, `escapeHtml()`, `fmt()`, `sLD()`/`hLD()`
- Produces: `renderGelenKutusu()`, `eFaturaKontrolEt()` — butonun `onclick`'i bunu çağırır

- [ ] **Step 1: Tab butonunu ekle**

Mevcut (satır 85-90):
```html
  <div class="tab-bar">
    <button class="tabbtn active" onclick="gTab('alis',this)">📥 Alış</button>
    <button class="tabbtn" onclick="gTab('satis',this)">📤 Satış</button>
    <button class="tabbtn" onclick="gTab('eslestir',this)">🔗 3-Way Match</button>
    <button class="tabbtn" onclick="gTab('odeme',this)">💳 Ödeme Bekleyen</button>
  </div>
```
şuna çevir:
```html
  <div class="tab-bar">
    <button class="tabbtn active" onclick="gTab('alis',this)">📥 Alış</button>
    <button class="tabbtn" onclick="gTab('satis',this)">📤 Satış</button>
    <button class="tabbtn" onclick="gTab('eslestir',this)">🔗 3-Way Match</button>
    <button class="tabbtn" onclick="gTab('odeme',this)">💳 Ödeme Bekleyen</button>
    <button class="tabbtn" onclick="gTab('gelenkutu',this)">📬 Gelen e-Fatura</button>
  </div>
```

- [ ] **Step 2: Tab içeriğini ekle**

Mevcut (satır 140-144):
```html
  <!-- ÖDEME BEKLEYEN -->
  <div class="sc" id="tab-odeme">
    <div id="odeme-liste"></div>
  </div>
</div>
```
şuna çevir:
```html
  <!-- ÖDEME BEKLEYEN -->
  <div class="sc" id="tab-odeme">
    <div id="odeme-liste"></div>
  </div>

  <!-- GELEN E-FATURA KUTUSU -->
  <div class="sc" id="tab-gelenkutu">
    <div style="background:#fff7ed;border:1px solid #fed7aa;border-radius:8px;padding:8px 10px;margin-bottom:10px;font-size:11px;color:#92400e;font-weight:600">⚠️ SİMÜLASYON MODU — gerçek GİB'den fatura çekilmiyor</div>
    <button class="btn btn-primary btn-block" style="margin-bottom:10px" onclick="eFaturaKontrolEt()">🔄 Yeni e-Fatura Kontrol Et</button>
    <div id="gelenkutu-liste"></div>
  </div>
</div>
```

- [ ] **Step 3: `gTab`'a yeni sekme davranışını ekle**

Mevcut (satır 1107-1117):
```js
function gTab(tab,el){
  aktifTab=tab;
  document.querySelectorAll('.sc').forEach(s=>s.style.display='none');
  document.querySelectorAll('.tabbtn').forEach(t=>t.classList.remove('active'));
  document.getElementById('tab-'+tab).style.display='block';
  el.classList.add('active');
  if(tab==='alis')renderFaturalar('alis');
  if(tab==='satis')renderFaturalar('satis');
  if(tab==='odeme')renderOdemeBekleyen();
  if(tab==='eslestir')renderFaturalar('alis');
}
```
şuna çevir:
```js
function gTab(tab,el){
  aktifTab=tab;
  document.querySelectorAll('.sc').forEach(s=>s.style.display='none');
  document.querySelectorAll('.tabbtn').forEach(t=>t.classList.remove('active'));
  document.getElementById('tab-'+tab).style.display='block';
  el.classList.add('active');
  if(tab==='alis')renderFaturalar('alis');
  if(tab==='satis')renderFaturalar('satis');
  if(tab==='odeme')renderOdemeBekleyen();
  if(tab==='eslestir')renderFaturalar('alis');
  if(tab==='gelenkutu')renderGelenKutusu();
}
```

- [ ] **Step 4: `renderGelenKutusu`, `eFaturaKontrolEt`, `gelenEfaturaTaslakOlustur` fonksiyonlarını ekle**

`gTab` fonksiyonunun kapanış `}`'ının hemen ardına ekle:

```js
function renderGelenKutusu(){
  const liste=Object.values(gelenEfaturalar).sort((a,b)=>b.olusturmaTarih-a.olusturmaTarih);
  const c=document.getElementById('gelenkutu-liste');
  if(!liste.length){c.innerHTML='<div class="es"><div class="ei">📬</div><div class="et">Henüz gelen e-fatura yok</div></div>';return;}
  c.innerHTML=liste.map(g=>`
    <div class="card" style="margin-bottom:8px">
      <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:6px">
        <div style="font-weight:700;font-size:13px">${escapeHtml(g.gonderenAd)}</div>
        <span class="chip ${g.durum==='islendi'?'chip-blue':'chip-yellow'}">${g.durum==='islendi'?'✅ İşlendi':'🆕 Yeni'}</span>
      </div>
      <div style="font-size:11px;color:var(--gray-500);margin-bottom:4px">VKN: ${g.gonderenVkn} • ${g.tarih}</div>
      <div style="font-size:12px;font-weight:600">${fmt(g.genelToplam)} ₺</div>
      <div style="font-size:10px;color:var(--gray-400);margin-top:4px">ETTN: ${g.ettn}</div>
    </div>
  `).join('');
}

async function eFaturaKontrolEt(){
  sLD();
  try{
    const sonCekim=localStorage.getItem('efatura_son_cekim');
    const gelenler=await eFaturaGelenleriCek(sonCekim?parseInt(sonCekim):null);
    for(const g of gelenler){
      await gelenEfaturaTaslakOlustur(g);
    }
    localStorage.setItem('efatura_son_cekim',String(Date.now()));
    await loadDB();
    renderGelenKutusu();
    toast(gelenler.length?`✅ ${gelenler.length} yeni e-fatura alındı`:'ℹ️ Yeni e-fatura yok');
  }catch(e){
    console.warn(e);
    toast('❌ Gelen e-fatura kontrolü başarısız');
  }
  hLD();
}

// g: eFaturaGelenleriCek()'ten dönen tek bir gelen e-fatura kaydı
async function gelenEfaturaTaslakOlustur(g){
  const eslesenCari=Object.values(cariler).find(c=>c.vkn===g.gonderenVkn);
  const yeniFatura={
    tur:'alis',no:g.gibFaturaNo,tarih:g.tarih,
    cariId:eslesenCari?eslesenCari.id:null,
    cariAd:eslesenCari?eslesenCari.ad:g.gonderenAd,
    araToplam:g.araToplam,kdvToplam:g.kdvToplam,genelToplam:g.genelToplam,
    otelId:'810',durum:'taslak',
    not:eslesenCari?'':`⚠️ Cari eşleşmedi, VKN: ${g.gonderenVkn}`,
    kalemler:g.kalemler.map(k=>({
      kod:k.kod||'',ad:k.ad,miktar:k.miktar,birim:k.birim,
      birimFiyat:k.birimFiyat,iskonto:0,kdvOran:k.kdvOran,toplam:k.toplam
    }))
  };
  await saveFatura(yeniFatura);
  const satir={
    ettn:g.ettn,gonderen_vkn:g.gonderenVkn,gonderen_ad:g.gonderenAd,tarih:g.tarih,
    kalemler:g.kalemler,ara_toplam:g.araToplam,kdv_toplam:g.kdvToplam,genel_toplam:g.genelToplam,
    durum:'islendi',alis_fatura_id:yeniFatura.id
  };
  await fetch(SB_URL+'/rest/v1/gelen_efaturalar',{method:'POST',headers:SB_HEADERS,body:JSON.stringify(satir)});
}
```

- [ ] **Step 5: Doğrula**

```bash
grep -n "function renderGelenKutusu\|function eFaturaKontrolEt\|function gelenEfaturaTaslakOlustur\|tab-gelenkutu\|gTab('gelenkutu'" muhasebe-faturalar.html
```
Expected: 3 fonksiyon tanımı + tab div + 2 `gTab('gelenkutu'...)` çağrısı (buton + `gTab` içindeki dispatch) görünmeli.

- [ ] **Step 6: Kod okuyarak izleme**

`gelenEfaturaTaslakOlustur`'ın `saveFatura()`'yı çağırdıktan sonra `yeniFatura.id`'nin dolu olduğunu (mevcut `saveFatura` fonksiyonu `f.id`'yi POST sonrası yazıyor, satır ~446-455) ve bu id'nin `gelen_efaturalar.alis_fatura_id`'ye doğru şekilde yazıldığını doğrula. Ayrıca oluşan taslağın mevcut "Alış Faturaları" sekmesindeki "📝 Taslak" filtresinde (satır 101) göründüğünü kod okuyarak teyit et — `filterF('alis','taslak',...)`'in `f.durum==='taslak'` ile filtrelediğini, `gelenEfaturaTaslakOlustur`'ın da `durum:'taslak'` yazdığını karşılaştır.

- [ ] **Step 7: Commit**

```bash
git add muhasebe-faturalar.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: add inbound e-Fatura inbox with automatic alis-faturasi draft creation"
```

---

### Task 6: Uçtan uca doğrulama

**Files:** (yok — sadece doğrulama)

- [ ] **Step 1: Tüm yeni tanımların tutarlılığını kontrol et**

```bash
grep -n "efatura_durum\|efatura_tip\|gib_fatura_no\|gib_pdf_url\|efatura_gonderim_tarihi\|efatura_hata_mesaji" muhasebe-faturalar.html
```
Expected: Task 2'deki SQL'de tanımlanan 6 kolon adının hepsi (snake_case) `faturaSbdenCamele` (okuma) ve `eFaturaGonderTikla` (yazma) içinde birebir aynı yazımla geçmeli — yazım farkı varsa (örn. `efatura_durum` vs `efaturadurum`) Supabase sessizce yanlış/eksik güncelleme yapar.

- [ ] **Step 2: Kullanıcıya manuel test adımlarını bildir**

Kullanıcının tarayıcıda doğrulaması gereken akış (Node/Python bu ortamda yok, otomatik test yazılamıyor):
1. Task 2'deki SQL'i Supabase SQL Editor'de çalıştır.
2. `muhasebe-faturalar.html` → Satış sekmesi → bir faturaya tıkla → "⚠️ SİMÜLASYON MODU" şeridini ve "e-Fatura/e-Arşiv Gönder" butonunu gör.
3. Butona bas → "Gönderiliyor" → 1.5sn sonra "Gönderildi" durumuna geçtiğini, ETTN/GİB No'nun göründüğünü doğrula.
4. "📬 Gelen e-Fatura" sekmesine geç → "🔄 Yeni e-Fatura Kontrol Et" butonuna bas → 0-2 sahte fatura gelmesini bekle.
5. Alış sekmesi → "📝 Taslak" filtresine geç → yeni oluşan taslak alış faturasını gör, aç, kalemlerin doğru göründüğünü doğrula.

- [ ] **Step 3: Kullanıcıdan onay al, sonra push**

```bash
git fetch
git log --oneline main..origin/main
```
Expected: paralel oturumdan gelen değişiklik var mı kontrol et, varsa kullanıcıya bildir. Yoksa kullanıcı onayıyla `git push`.
