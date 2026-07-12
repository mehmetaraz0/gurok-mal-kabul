# Stok Listesi Excel'e Aktar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `stok-takip.html`'in Stok Takip sekmesine, o an seçili depo + ekrandaki filtreye göre görünen listeyi indiren, salt görüntüleme amaçlı (geri yükleme YOK) bir "📤 Excel'e Aktar" butonu eklemek.

**Architecture:** Var olan `xlsx-js-style` lazy-load deseni (bu dosyada zaten LN import'ta kullanılıyor) tekrar kullanılır. Tek bir yeni fonksiyon eklenir; filtreleme mantığı `renderStok()`'takiyle birebir aynı olacak şekilde kopyalanır.

**Tech Stack:** Vanilla HTML/JS, xlsx-js-style (CDN, mevcut) — build aracı/test çerçevesi yok.

## Global Constraints

- Sadece dışa aktarma — geri yükleme/import YOK, stok verisine hiçbir yazma işlemi yapılmaz (spec).
- Sadece o an seçili depo (`aktifDepoId`) ve o an ekrandaki filtre (arama + kategori + durum) kapsanır (spec).

---

### Task 1: "Excel'e Aktar" butonu + dışa aktarma fonksiyonu

**Files:**
- Modify: `stok-takip.html:158-159` (buton HTML — `.filter-tabs` ile `#kat-tabs` arasına)
- Modify: `stok-takip.html` — `renderStok()` fonksiyonunun hemen ardına yeni fonksiyon eklenir.

**Interfaces:**
- Consumes: `db.stok[aktifDepoId]` (global), `db.minimumlar` (global), `getStokDurum(lnKod,miktar)` (mevcut fonksiyon), `depoAdi(depoId)` (mevcut fonksiyon), `document.getElementById('stok-search')`/`katFilter`/`stokFilter` (mevcut, renderStok'ta kullanılan aynı globaller).
- Produces: `stokExcelAktar()` — butonun `onclick`'i bunu çağırır.

- [ ] **Step 1: Butonu ekle**

Mevcut:
```html
    <div class="filter-tabs">
      <button class="filter-tab active" onclick="filterStok('tumu',this)">Tümü</button>
      <button class="filter-tab" onclick="filterStok('kritik',this)">🔴 Kritik</button>
      <button class="filter-tab" onclick="filterStok('uyari',this)">🟡 Uyarı</button>
      <button class="filter-tab" onclick="filterStok('normal',this)">✅ Normal</button>
    </div>
    <div class="filter-tabs" id="kat-tabs"></div>
    <div id="stok-liste"></div>
```
şuna çevir:
```html
    <div class="filter-tabs">
      <button class="filter-tab active" onclick="filterStok('tumu',this)">Tümü</button>
      <button class="filter-tab" onclick="filterStok('kritik',this)">🔴 Kritik</button>
      <button class="filter-tab" onclick="filterStok('uyari',this)">🟡 Uyarı</button>
      <button class="filter-tab" onclick="filterStok('normal',this)">✅ Normal</button>
    </div>
    <div class="filter-tabs" id="kat-tabs"></div>
    <button class="btn btn-gray btn-block" style="margin-bottom:8px" onclick="stokExcelAktar()">📤 Excel'e Aktar</button>
    <div id="stok-liste"></div>
```

- [ ] **Step 2: Dışa aktarma fonksiyonunu `renderStok()`'un hemen ardına ekle**

`renderStok()` fonksiyonunun kapanış `}` süslü parantezinin hemen ardına (dosyada `function renderStok(){...}` bloğunun bittiği yere) şu fonksiyonu ekle:

```js
async function stokExcelAktar(){
  const depoStok=db.stok[aktifDepoId]||{};
  const items=Object.values(depoStok);
  const search=(document.getElementById('stok-search')?.value||'').toLowerCase();
  const filtered=items.filter(s=>{
    if(search&&!s.urunAd?.toLowerCase().includes(search)&&!s.lnKod?.toLowerCase().includes(search))return false;
    if(katFilter!=='tumu'&&!s.lnKod?.startsWith(katFilter))return false;
    const d=getStokDurum(s.lnKod,s.miktar);
    if(stokFilter==='kritik'&&d!=='kritik')return false;
    if(stokFilter==='uyari'&&d!=='uyari')return false;
    if(stokFilter==='normal'&&d!=='normal')return false;
    return true;
  });
  if(!filtered.length){showToast('⚠️ Aktarılacak stok yok');return;}
  const durumEtiket={kritik:'Kritik',uyari:'Uyarı',normal:'Normal'};
  const satirlar=filtered.map(s=>({
    'Ürün Kodu':s.lnKod||'','Ürün Adı':s.urunAd||'','Miktar':s.miktar,'Birim':s.birim||'',
    'Minimum':db.minimumlar[s.lnKod]||0,'Durum':durumEtiket[getStokDurum(s.lnKod,s.miktar)]||''
  }));
  if(typeof XLSX==='undefined'){
    showLoading();
    await new Promise(r=>{const s=document.createElement('script');s.src='https://cdn.jsdelivr.net/npm/xlsx-js-style@1.2.0/dist/xlsx.bundle.js';s.onload=r;document.head.appendChild(s);});
    hideLoading();
  }
  const ws=XLSX.utils.json_to_sheet(satirlar);
  const wb=XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(wb,ws,'Stok');
  XLSX.writeFile(wb,'stok-'+depoAdi(aktifDepoId).replace(/[^a-zA-Z0-9]+/g,'-')+'-'+new Date().toISOString().split('T')[0]+'.xlsx');
  showToast(`✅ ${satirlar.length} ürün Excel'e aktarıldı`);
}
```

- [ ] **Step 3: Doğrula**

```bash
grep -n "function stokExcelAktar\|onclick=\"stokExcelAktar" stok-takip.html
```
Expected: 2 satır (fonksiyon tanımı + buton çağrısı).

- [ ] **Step 4: Kod okuyarak izleme**

`stokExcelAktar()`'daki filtreleme bloğunun `renderStok()`'taki filtreleme
bloğuyla (arama + katFilter + stokFilter sırası ve koşulları) birebir aynı
olduğunu satır satır karşılaştırarak doğrula — aynı olmalı, aksi halde
kullanıcının ekranda gördüğü liste ile indirdiği Excel farklı olur.

- [ ] **Step 5: Commit**

```bash
git add stok-takip.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "stok-takip.html: add view-only Excel export for current stock list"
```
