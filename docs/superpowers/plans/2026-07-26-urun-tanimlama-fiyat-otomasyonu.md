# Ürün Tanımlama + Cost Fiyat Otomasyonu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ürün açma/fiyat tanımlama ekranı + İç Talep cost aşamasında tutarın sistem/fatura fiyatından otomatik hesaplanması.

**Architecture:** Yeni `urun-tanimlama.html` sayfası `urunler` tablosuyla çalışır (ürün oluştur + sistem_fiyat düzenle). `urunler`'e fiyat kolonları eklenir. `satin-alma-talepler.html` cost UI'ı, kalem×fiyat otomatik hesaplayıp `talep-cost-tutar` input'unu doldurur (düzeltilebilir). Yeni sipariş/onay yolu icat edilmez; mevcut `talepAsamaIlerlet` akışı korunur.

**Tech Stack:** Statik HTML/JS (build/test aracı YOK), Supabase REST (`SB_HEADERS` = JWT/anon), GitHub Pages (main branch deploy).

## Global Constraints

- Tablo/kolon değişikliği anon key'le YAPILAMAZ → DDL ayrı `.sql` dosyası, kullanıcı Supabase SQL Editor'e yapıştırır (Task 1).
- Fiyat çözümleme sırası (cost): **`sistem_fiyat` (urunler) → `urun_guncel_fiyat.birim_fiyat` (son fatura) → null ("fiyat yok")**.
- Cost tutarı otomatik dolar ama **elle düzeltilebilir** (input yalnızca BOŞsa doldurulur, kullanıcı değerini ezme).
- Ürün yazma yetkisi: `YETKI_HARITASI['urun_yonetimi']` ∈ {`kayit`,`tam`} (modül canlıda mevcut: "Ürün Yönetimi (Birim Dönüşüm)").
- Tarih yazımı `bugunTarih()`/`new Date().toISOString()` — proje deseni; UTC kayması için mevcut desene uy.
- XSS: tüm kullanıcı/DB metni `escapeHtml`'den geçer.
- Sayfa iskeleti mevcut modern (urunler-tablosu okuyan) kardeş sayfa deseniyle: `auth-guard.js`+`supabase-config.js`+`nav-drawer.js`, `requireLogin`/`requireRole`, `SB_URL`/`SB_HEADERS`, `escapeHtml`/`toast`/`sLD`/`hLD`, `kullaniciYetkileriGetir`.

**Mevcut şema/kaynak (doğrulanmış):**
- `urunler`: kod(PK,text), ad(text), birim(text), grup(text), sicaklik_kriteri(text), olusturma_tarihi(timestamptz). Bu tabloyu okuyan modern sayfalar: satin-alma-talepler, stok-takip, mal-kabul-liste, mal-kabul-skt, gunluk-tuketim, trend-raporlama, bar-menu-yonetimi.
- `urun_guncel_fiyat` (view): urun_kodu, birim_fiyat, birim (son fatura fiyatı).
- `satin_alma_talepleri` kalemleri `satin-alma-talepler.html` içinde `DB.talepler[id].satirlar = [{id, ad, kod, miktar, birim}]`.
- Cost UI: `satin-alma-talepler.html` openTalepDetay cost bloğu (`t.asama==='cost'&&yetkili`, ~satır 761-762 `talep-cost-tutar` input); `aModal('mTalepDetay')` ~satır 779; `talepKararVer(id,karar)` ~782 cost'ta input değerini okur.

---

### Task 1: SQL — `urunler`'e fiyat kolonları ekle

**Files:**
- Create: `docs/kurulum/2026-07-26-urun-sistem-fiyat.sql`

**Interfaces:**
- Produces (canlı DB): `urunler.sistem_fiyat numeric`, `urunler.sistem_fiyat_tarihi timestamptz`, `urunler.sistem_fiyat_giren text`.

- [ ] **Step 1: SQL dosyasını yaz**

`docs/kurulum/2026-07-26-urun-sistem-fiyat.sql`:
```sql
-- Ürün sistem fiyatı — urunler tablosuna fiyat kolonları.
-- Supabase SQL Editor'e yapıştır → Run. Geri alınabilir (kolon ekler, veri silmez).
alter table public.urunler add column if not exists sistem_fiyat numeric;
alter table public.urunler add column if not exists sistem_fiyat_tarihi timestamptz;
alter table public.urunler add column if not exists sistem_fiyat_giren text;
notify pgrst, 'reload schema';
```

- [ ] **Step 2: Doğrula (kullanıcı çalıştırır)** — controller REST ile: `curl "$SBURL/rest/v1/urunler?select=kod,sistem_fiyat&limit=1"` → `sistem_fiyat` alanı dönmeli (200, kolon var).

- [ ] **Step 3: Commit**
```bash
git add docs/kurulum/2026-07-26-urun-sistem-fiyat.sql
git commit -m "feat(urun): urunler tablosuna sistem_fiyat kolonlari (SQL)"
```

---

### Task 2: `urun-tanimlama.html` yeni ekran + hub kartı

**Files:**
- Create: `urun-tanimlama.html`
- Modify: `satin-alma.html` (yeni "Ürün Tanımlama" kartı, modul-grid içine)

**Interfaces:**
- Consumes: `urunler` tablosu (Task 1 kolonlarıyla), `YETKI_HARITASI['urun_yonetimi']`.
- Produces: ürünler `urunler` tablosuna INSERT/PATCH edilir (kod, ad, birim, grup, sistem_fiyat, sistem_fiyat_tarihi, sistem_fiyat_giren).

- [ ] **Step 1: Sayfa iskeleti**

`urun-tanimlama.html` — head/stil/header'ı mevcut modern kardeş `mal-kabul-liste.html`'den (urunler tablosunu okuyan) uyarla: `<script src="auth-guard.js"></script>`+`supabase-config.js`+`nav-drawer.js`, `let CU=requireLogin(); if(CU)requireRole(CU,['yonetici','satinalma','depo','cost_control']);`, title "Ürün Tanımlama", header (geri → `satin-alma.html`), `SB_URL/SB_HEADERS/escapeHtml/toast/sLD/hLD` global. İçerik: arama input `<input id="urun-ara">`, `<div id="urun-liste"></div>`, "➕ Yeni Ürün" butonu.

- [ ] **Step 2: Veri + render**
```javascript
let URUNLER=[], YETKI_HARITASI={};
function yazabilir(){ return ['kayit','tam'].includes(YETKI_HARITASI['urun_yonetimi']); }
async function loadUrunler(){
  const r=await fetch(SB_URL+'/rest/v1/urunler?select=kod,ad,birim,grup,sistem_fiyat&order=ad',{headers:SB_HEADERS});
  URUNLER = r.ok ? await r.json() : [];
}
function renderUrunler(){
  const q=(document.getElementById('urun-ara').value||'').toLowerCase();
  const list=URUNLER.filter(u=>!q||(u.ad||'').toLowerCase().includes(q)||(u.kod||'').toLowerCase().includes(q)).slice(0,200);
  document.getElementById('urun-liste').innerHTML = list.map(u=>`
    <div style="background:#fff;border:1px solid #e4e7ec;border-radius:8px;padding:10px;margin-bottom:6px;display:flex;align-items:center;gap:8px">
      <div style="flex:1"><b>${escapeHtml(u.ad)}</b> <span style="color:#8992a3;font-size:11px">${escapeHtml(u.kod)} · ${escapeHtml(u.birim||'')}</span>
        <div style="font-size:12px">Sistem fiyatı: <b>${u.sistem_fiyat!=null?parseFloat(u.sistem_fiyat).toFixed(2)+' ₺':'—'}</b></div></div>
      ${yazabilir()?`<button onclick="fiyatDuzenle('${escapeHtml(u.kod)}')">Fiyat Düzenle</button>`:''}
    </div>`).join('') || '<div style="text-align:center;color:#8992a3;padding:16px">Ürün yok</div>';
}
```
`urun-ara` input'a `oninput="renderUrunler()"`.

- [ ] **Step 3: Yeni ürün ekle (kod çakışma kontrolü)**
```javascript
async function urunEkle(kod, ad, birim, grup, fiyat){
  if(!yazabilir()){toast('⚠️ Yetkiniz yok');return;}
  if(!kod||!ad){toast('⚠️ Kod ve ad zorunlu');return;}
  const c=await fetch(SB_URL+'/rest/v1/urunler?kod=eq.'+encodeURIComponent(kod)+'&select=kod',{headers:SB_HEADERS});
  if(c.ok && (await c.json()).length){toast('⚠️ Bu kod zaten var');return;}
  const body={kod, ad, birim:birim||'KG', grup:grup||null};
  if(fiyat!==''&&fiyat!=null&&!isNaN(parseFloat(fiyat))){ body.sistem_fiyat=parseFloat(fiyat); body.sistem_fiyat_tarihi=new Date().toISOString(); body.sistem_fiyat_giren=CU.ad; }
  const r=await fetch(SB_URL+'/rest/v1/urunler',{method:'POST',headers:SB_HEADERS,body:JSON.stringify(body)});
  if(!r.ok){toast('❌ Eklenemedi');return;}
  await loadUrunler(); renderUrunler(); toast('✅ Ürün eklendi');
}
```
"➕ Yeni Ürün" butonu → basit modal/form (kod, ad, birim seçici, grup, sistem fiyatı) → `urunEkle(...)`. Modal deseni mevcut sayfalardan.

- [ ] **Step 4: Fiyat düzenle**
```javascript
async function fiyatGuncelle(kod, fiyat){
  if(!yazabilir()){toast('⚠️ Yetkiniz yok');return;}
  if(fiyat===''||isNaN(parseFloat(fiyat))){toast('⚠️ Geçerli fiyat girin');return;}
  const r=await fetch(SB_URL+'/rest/v1/urunler?kod=eq.'+encodeURIComponent(kod),{method:'PATCH',headers:SB_HEADERS,
    body:JSON.stringify({sistem_fiyat:parseFloat(fiyat), sistem_fiyat_tarihi:new Date().toISOString(), sistem_fiyat_giren:CU.ad})});
  if(!r.ok){toast('❌ Güncellenemedi');return;}
  await loadUrunler(); renderUrunler(); toast('✅ Fiyat güncellendi');
}
```
`fiyatDuzenle(kod)` — ürünü bul, prompt/mini-modal ile yeni fiyat al → `fiyatGuncelle(kod, fiyat)`.

Init IIFE: `if(!CU)return; YETKI_HARITASI=await kullaniciYetkileriGetir(); sLD(); await loadUrunler(); hLD(); renderUrunler();`.

- [ ] **Step 5: Hub kartı — `satin-alma.html`**

`modul-grid` içine yeni kart (mevcut kart deseniyle): `<a class="modul-kart" href="urun-tanimlama.html">` ikon + `<div class="modul-ad">Ürün Tanımlama</div>` + `<div class="modul-desc">Ürün aç, sistem fiyatı</div>`.

- [ ] **Step 6: Doğrula (statik)**
```bash
grep -n "loadUrunler\|urunEkle\|fiyatGuncelle\|YETKI_HARITASI\['urun_yonetimi'\]" urun-tanimlama.html
grep -n "urun-tanimlama.html" satin-alma.html
node -e "const s=require('fs').readFileSync('urun-tanimlama.html','utf8');const m=[...s.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(x=>x[1]).join('\n;\n');new (require('vm').Script)(m);console.log('JS OK')"
```
Beklenen: fonksiyonlar mevcut; hub kartı linki var; JS syntax OK.

- [ ] **Step 7: Commit**
```bash
git add urun-tanimlama.html satin-alma.html
git commit -m "feat(urun): Urun Tanimlama ekrani (urunler tablosu, sistem fiyat) + hub karti"
```

---

### Task 3: Cost aşaması otomatik fiyat (`satin-alma-talepler.html`)

**Files:**
- Modify: `satin-alma-talepler.html` (openTalepDetay cost bloğu ~761, aModal ~779)

**Interfaces:**
- Consumes: `DB.talepler[id].satirlar` (`[{id,ad,kod,miktar,birim}]`), `urunler.sistem_fiyat`, `urun_guncel_fiyat.birim_fiyat`, mevcut `talep-cost-tutar` input + `talepKararVer`.
- Produces: `costFiyatDoldur(t)` async — kalem fiyatlarını çözer, kırılımı `#cost-fiyat-kirilim`'e yazar, toplamı `talep-cost-tutar`'a (boşsa) doldurur.

- [ ] **Step 1: Cost bloğuna kırılım alanı ekle**

openTalepDetay cost bloğunda (`t.asama==='cost'&&yetkili`) mevcut tutar input'unun ÜSTÜNE kırılım div ekle:
`<div id="cost-fiyat-kirilim" style="font-size:12px;margin-bottom:8px;color:var(--gray-600)">Fiyatlar yükleniyor…</div>`
Tutar input'u aynı kalır (`id="talep-cost-tutar"`), placeholder "Otomatik — gerekirse düzelt".

- [ ] **Step 2: costFiyatDoldur fonksiyonu**
```javascript
async function costFiyatDoldur(t){
  const kodlar=[...new Set((t.satirlar||[]).map(s=>s.kod).filter(Boolean))];
  const fiyat={};
  if(kodlar.length){
    const inList='('+kodlar.map(k=>encodeURIComponent(k)).join(',')+')';
    try{
      const [uR,fR]=await Promise.all([
        fetch(SB_URL+'/rest/v1/urunler?select=kod,sistem_fiyat&kod=in.'+inList,{headers:SB_HEADERS}),
        fetch(SB_URL+'/rest/v1/urun_guncel_fiyat?select=urun_kodu,birim_fiyat&urun_kodu=in.'+inList,{headers:SB_HEADERS})
      ]);
      const sis={}, fat={};
      if(uR.ok)(await uR.json()).forEach(r=>{ if(r.sistem_fiyat!=null)sis[r.kod]=parseFloat(r.sistem_fiyat); });
      if(fR.ok)(await fR.json()).forEach(r=>{ fat[r.urun_kodu]=parseFloat(r.birim_fiyat); });
      kodlar.forEach(k=>{ fiyat[k]= (sis[k]!=null?sis[k]:(fat[k]!=null?fat[k]:null)); });
    }catch(e){ console.warn(e); }
  }
  let toplam=0, html='';
  (t.satirlar||[]).forEach(s=>{
    const f=s.kod?fiyat[s.kod]:null;
    const satir=(f!=null)?(parseFloat(s.miktar)||0)*f:null;
    if(satir!=null) toplam+=satir;
    html+=`<div style="display:flex;justify-content:space-between;padding:2px 0">
      <span>${escapeHtml(s.ad)} — ${s.miktar} ${escapeHtml(s.birim||'')} × ${f!=null?parseFloat(f).toFixed(2)+'₺':'<b style="color:var(--danger)">fiyat yok</b>'}</span>
      <span>${satir!=null?parseFloat(satir).toFixed(2)+'₺':''}</span></div>`;
  });
  const kir=document.getElementById('cost-fiyat-kirilim');
  if(kir) kir.innerHTML=html+`<div style="display:flex;justify-content:space-between;font-weight:700;border-top:1px solid var(--gray-200);margin-top:4px;padding-top:4px"><span>Toplam</span><span>${toplam.toFixed(2)}₺</span></div>`;
  const inp=document.getElementById('talep-cost-tutar');
  if(inp && !inp.value) inp.value=toplam.toFixed(2);
}
```

- [ ] **Step 3: aModal sonrası tetikle**

openTalepDetay içinde `aModal('mTalepDetay');` satırından SONRA:
`if(t.asama==='cost'&&yetkili) costFiyatDoldur(t);`
(costFiyatDoldur async; fire-and-forget — modal hemen açılır, fiyatlar bir an sonra dolar.)

- [ ] **Step 4: Doğrula (statik)**
```bash
grep -n "function costFiyatDoldur\|cost-fiyat-kirilim\|costFiyatDoldur(t)" satin-alma-talepler.html
grep -n "talep-cost-tutar" satin-alma-talepler.html   # input hala var, talepKararVer okumasi bozulmadi
node -e "const s=require('fs').readFileSync('satin-alma-talepler.html','utf8');const m=[...s.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(x=>x[1]).join('\n;\n');new (require('vm').Script)(m);console.log('JS OK')"
```
Beklenen: costFiyatDoldur + kırılım + tetik mevcut; `talep-cost-tutar` input hâlâ var (talepKararVer değişmedi); JS OK.

- [ ] **Step 5: Commit**
```bash
git add satin-alma-talepler.html
git commit -m "feat(talep): cost asamasi otomatik fiyat (sistem_fiyat->fatura fiyati) + kalem kirilim, duzeltilebilir"
```

---

### Task 4: Uçtan uca doğrulama

- [ ] **Step 1: Push + deploy**
```bash
git push origin main
```
GitHub Pages ~1 dk. Canlı doğrula: `curl -s "https://mehmetaraz0.github.io/gurok-mal-kabul/urun-tanimlama.html" | grep -c "urunEkle"` ≥1.

- [ ] **Step 2: Kullanıcı E2E (Task 1 SQL sonrası)**

1. Task 1 SQL çalıştırıldı mı (`urunler.sistem_fiyat` kolonu var mı) doğrula.
2. Satın Alma → **Ürün Tanımlama** → yeni ürün (kod+ad+birim+fiyat) ekle VEYA mevcut bir ürünün fiyatını gir.
3. O ürünlü bir İç Talep oluştur → depo onayla → cost'a düşür.
4. Cost detayını aç → **kalem×fiyat kırılımı + otomatik toplam** görünüyor mu; tutar input'u otomatik dolu mu; düzeltilebiliyor mu.
5. Onayla → sonraki aşamaya tutarla geçiyor mu.
6. Fiyatı olmayan ürünle → "fiyat yok" görünüyor, bloklamıyor mu.

- [ ] **Step 3: Hafıza güncelle** — `gurok-cost-fiyat-otomasyonu.md`'yi "YAPILDI + canlı" olarak güncelle.

---

## Self-Review

**1. Spec coverage:** urunler fiyat kolonu→Task 1. Ürün açma ekranı+fiyat→Task 2. Hub kartı→Task 2. Cost otomatik fiyat (sistem→fatura→yok, düzeltilebilir, kırılım)→Task 3. E2E→Task 4. 16-sayfa birleştirme kapsam dışı (spec ile tutarlı). Kapsandı.

**2. Placeholder taraması:** SQL tam; fonksiyon gövdeleri gerçek kod; UI iskeleti mevcut kardeş sayfa referansıyla; doğrulama statik grep+node syntax + kullanıcı E2E (projede test çerçevesi yok — yerleşik desen).

**3. Tip tutarlılığı:** Fiyat çözümleme sırası (sistem_fiyat→urun_guncel_fiyat→null) Task 3'te; `sistem_fiyat`/`sistem_fiyat_tarihi`/`sistem_fiyat_giren` alan adları Task 1↔2 aynı; `talep-cost-tutar` input id'si Task 3'te korunuyor (talepKararVer okuması değişmiyor); `urun_yonetimi` yetki kodu Task 2'de canlı modülle eşleşiyor.
