# Ürün Kalem Kodu Sınıflandırma Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `urun-yonetimi.html`'e, mevcut 1264 ürünün her birini (kodu değiştirmeden) bir Ana Grup + Alt Grup ikilisine atayabilen bir sınıflandırma sistemi eklemek — küçük kategori kataloğu form üzerinden, 1264 ürünlük toplu atama Excel üzerinden.

**Architecture:** 3 yeni Supabase tablosu (`urun_ana_gruplari`, `urun_alt_gruplari`, `urun_siniflandirma`) — `urun_birim_donusum` ile birebir aynı desen (ürün kodu sabit kalır, ayrı eşleme tablosu ekler). `urun-yonetimi.html` iki sekmeye bölünür: "Ürünler" (mevcut arama + birim dönüşümü + artık tekli alt-grup ataması) ve "Kategori Kataloğu" (yeni, ana/alt grup adlandırma). Toplu atama `ortak-excel.js`'in kanıtlanmış `excelSablonIndir/excelDosyaOku/excelSatirlariSiniflandir/excelOnizlemeGoster/excelTopluYaz/excelImportGecmisiYaz` altılısıyla, `stok-takip.html`'in `stokMinimumExcel*` üçlüsüyle birebir aynı iskelette.

**Tech Stack:** Vanilla HTML/JS/CSS, Supabase PostgREST, `ortak.js`/`ortak-excel.js`/`theme.css` (mevcut paylaşılan dosyalar), SheetJS (xlsx-js-style, `loadXlsxLib()` ile CDN'den yüklenir).

## Global Constraints

- Ürün kodunun kendisi (`kod` alanı, `gurok_veritabani.js` + Supabase `public.urunler.kod`) **hiçbir task'ta değiştirilmez**.
- Tüm yeni tablolarda soft-delete deseni: gerçek `DELETE` yok, `silindi boolean not null default false`.
- RLS modül kodu: `urun_yonetimi` (zaten `yetki_matrisi`'nde kayıtlı — bkz. `docs/superpowers/specs/2026-07-20-birim-donusum-design.md`). SELECT için `auth_yetki_var('urun_yonetimi','goruntule')`, yazma için `auth_yetki_var('urun_yonetimi','kayit')`.
- Ana/alt grup adları **hiçbir task'ta otomatik tahmin edilmez/uydurulmaz** — boş bırakılır, kullanıcı Kategori Kataloğu ekranından elle doldurur.
- Her task sonunda `git commit` (bu depoda feature branch kullanılmıyor, doğrudan `main`'e commit ediliyor — mevcut proje konvansiyonu).
- SQL migration dosyaları kullanıcı tarafından Supabase SQL Editor'de elle çalıştırılır — AI/implementer bunu otomatik çalıştıramaz, sadece dosyayı yazar.

---

### Task 1: Supabase şema migrasyonu

**Files:**
- Create: `docs/kurulum/2026-07-26-urun-siniflandirma-sema.sql`

**Interfaces:**
- Produces: `public.urun_ana_gruplari(ana_grup_kod, ana_grup_adi, sira, silindi)`, `public.urun_alt_gruplari(ana_grup_kod, alt_grup_kod, alt_grup_adi, sira, silindi)`, `public.urun_siniflandirma(urun_kodu, alt_grup_kod, silindi)` — sonraki tüm task'lar bu üç tabloyu ve sütun adlarını kullanır.

- [ ] **Step 1: SQL dosyasını yaz**

```sql
-- 2026-07-26: Ürün kalem kodu sınıflandırma (Ana Grup + Alt Grup)
-- Supabase SQL Editor'de tek seferlik çalıştırılır. Ürün kodunun kendisini
-- (public.urunler.kod) DEĞİŞTİRMEZ — sadece ek bir eşleme/katalog ekler,
-- urun_birim_donusum ile aynı desen.

begin;

create table public.urun_ana_gruplari (
  id uuid primary key default gen_random_uuid(),
  ana_grup_kod text not null unique,      -- mevcut public.urunler.grup değerleriyle eşleşir, örn. 'YIY01'
  ana_grup_adi text not null default '',  -- kullanıcı elle doldurur, boş başlar
  sira int not null default 0,
  silindi boolean not null default false,
  guncelleme_tarihi timestamptz not null default now()
);

create table public.urun_alt_gruplari (
  id uuid primary key default gen_random_uuid(),
  ana_grup_kod text not null references public.urun_ana_gruplari(ana_grup_kod),
  alt_grup_kod text not null unique,      -- örn. 'YIY0401'
  alt_grup_adi text not null,             -- örn. 'Kartonlu'
  sira int not null default 0,
  silindi boolean not null default false,
  guncelleme_tarihi timestamptz not null default now()
);

create table public.urun_siniflandirma (
  id uuid primary key default gen_random_uuid(),
  urun_kodu text not null unique references public.urunler(kod),
  alt_grup_kod text not null references public.urun_alt_gruplari(alt_grup_kod),
  silindi boolean not null default false,
  guncelleme_tarihi timestamptz not null default now()
);

alter table public.urun_ana_gruplari enable row level security;
alter table public.urun_alt_gruplari enable row level security;
alter table public.urun_siniflandirma enable row level security;

create policy urun_ana_gruplari_select on public.urun_ana_gruplari
  for select using (public.auth_yetki_var('urun_yonetimi','goruntule') and silindi = false);
create policy urun_ana_gruplari_yaz on public.urun_ana_gruplari
  for all using (public.auth_yetki_var('urun_yonetimi','kayit'))
  with check (public.auth_yetki_var('urun_yonetimi','kayit'));

create policy urun_alt_gruplari_select on public.urun_alt_gruplari
  for select using (public.auth_yetki_var('urun_yonetimi','goruntule') and silindi = false);
create policy urun_alt_gruplari_yaz on public.urun_alt_gruplari
  for all using (public.auth_yetki_var('urun_yonetimi','kayit'))
  with check (public.auth_yetki_var('urun_yonetimi','kayit'));

create policy urun_siniflandirma_select on public.urun_siniflandirma
  for select using (public.auth_yetki_var('urun_yonetimi','goruntule') and silindi = false);
create policy urun_siniflandirma_yaz on public.urun_siniflandirma
  for all using (public.auth_yetki_var('urun_yonetimi','kayit'))
  with check (public.auth_yetki_var('urun_yonetimi','kayit'));

commit;
```

- [ ] **Step 2: Kullanıcıya bildir**

Dosyayı yazdıktan sonra kullanıcıya şu mesajı ilet: "`docs/kurulum/2026-07-26-urun-siniflandirma-sema.sql` dosyasını Supabase SQL Editor'de çalıştırman gerekiyor — sonraki task'lar bu 3 tabloya yazıyor, migrasyon çalışmadan test edilemezler."

- [ ] **Step 3: Commit**

```bash
git add docs/kurulum/2026-07-26-urun-siniflandirma-sema.sql
git commit -m "feat: ürün sınıflandırma şeması (urun_ana_gruplari/urun_alt_gruplari/urun_siniflandirma)"
```

---

### Task 2: Kategori Kataloğu sekmesi — `urun-yonetimi.html`

**Files:**
- Modify: `urun-yonetimi.html` (mevcut dosya, 140 satır — bkz. bu dosyanın tamamı zaten planlayıcı tarafından okundu, tam içerik biliniyor)

**Interfaces:**
- Consumes: Task 1'in ürettiği `urun_ana_gruplari`/`urun_alt_gruplari` tabloları.
- Produces: global `ANA_GRUPLAR` (dizi, her eleman `{id,ana_grup_kod,ana_grup_adi,sira}`), `ALT_GRUPLAR` (dizi, her eleman `{id,ana_grup_kod,alt_grup_kod,alt_grup_adi,sira}`) — Task 3 ve Task 4 bu iki globali okuyacak.

- [ ] **Step 1: CSS ekle — sekme çubuğu + kart/form stilleri**

`urun-yonetimi.html`'in `<style>` bloğuna, mevcut `.uyari{...}` kuralından hemen sonra ekle (bu dosyada henüz `.tab-bar`/`.tabbtn`/`.card`/`.field`/`.btn` yok — `muhasebe-butce.html`'den birebir kopyalanan, kanıtlanmış kurallar):

```css
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
.btn{padding:11px 18px;border:none;border-radius:var(--radius-sm);font-size:14px;font-weight:600;cursor:pointer;display:inline-flex;align-items:center;justify-content:center;gap:6px;min-height:44px}
.btn:active{transform:scale(.97)}
.btn-primary{background:var(--primary);color:white}
.btn-block{width:100%}
.ag-satir{display:flex;align-items:center;gap:8px;padding:8px 0;border-bottom:1px solid var(--gray-100)}
.ag-kod{font-size:11px;color:var(--gray-500);font-family:monospace;min-width:60px}
.ag-satir input{flex:1;padding:7px 9px;border:1.5px solid var(--gray-300);border-radius:6px;font-size:13px;outline:none}
.ag-satir button{padding:7px 12px;border:none;border-radius:6px;font-size:12px;font-weight:600;cursor:pointer;background:var(--primary);color:white;min-height:32px}
```

- [ ] **Step 2: `<body>` içindeki `#app` yapısını sekme yapısına çevir**

Mevcut:
```html
<div id="app" style="display:none">
  <div class="header">
    <button class="header-btn" onclick="location.href='stok-takip.html'"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" style="width:16px;height:16px;flex-shrink:0"><path d="M19 12H5M12 19l-7-7 7-7"/></svg></button>
    <div style="flex:1"><h1>Ürün Birim Yönetimi</h1><span class="sub" id="hsub"></span></div>
  </div>
  <div class="uyari">Sadece koli/kg gibi büyük-küçük birim ilişkisi olan ürünler için "Büyük Birim" ve "Çarpan" gir (örn. 1 KOLİ = 10 KG için Büyük Birim: KOLİ, Çarpan: 10). Bu, sadece raporlarda kg'yi koli'ye çevirmek için kullanılır — mal kabulde gerçek ağırlık girişini değiştirmez.</div>
  <div class="search-bar"><input type="text" id="arama" placeholder="Ürün kodu veya adı ara (en az 2 karakter)..." oninput="aramaYap()"></div>
  <div class="scroll-content" id="urun-liste">
    <div class="es"><div class="ei">🔍</div><div class="et">Aramaya başlamak için en az 2 karakter yaz</div></div>
  </div>
</div>
```

Yeni (başlık "Ürün Yönetimi" olarak güncellendi çünkü artık sadece birim yönetimi değil; boş-durum ikonu SVG'ye çevrildi, repo genelindeki emoji temizliğiyle tutarlı):
```html
<div id="app" style="display:none">
  <div class="header">
    <button class="header-btn" onclick="location.href='stok-takip.html'"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" style="width:16px;height:16px;flex-shrink:0"><path d="M19 12H5M12 19l-7-7 7-7"/></svg></button>
    <div style="flex:1"><h1>Ürün Yönetimi</h1><span class="sub" id="hsub"></span></div>
  </div>
  <div class="tab-bar">
    <button class="tabbtn active" id="tb-urunler" onclick="sekmeDegistir('urunler')">Ürünler</button>
    <button class="tabbtn" id="tb-kategoriler" onclick="sekmeDegistir('kategoriler')">Kategori Kataloğu</button>
  </div>

  <div class="sc" id="tab-urunler" style="display:block">
    <div class="uyari">Sadece koli/kg gibi büyük-küçük birim ilişkisi olan ürünler için "Büyük Birim" ve "Çarpan" gir (örn. 1 KOLİ = 10 KG için Büyük Birim: KOLİ, Çarpan: 10). Bu, sadece raporlarda kg'yi koli'ye çevirmek için kullanılır — mal kabulde gerçek ağırlık girişini değiştirmez. Alt Grup ataması için önce Kategori Kataloğu sekmesinden en az bir alt grup tanımlanmış olmalı.</div>
    <div class="search-bar"><input type="text" id="arama" placeholder="Ürün kodu veya adı ara (en az 2 karakter)..." oninput="aramaYap()"></div>
    <div id="urun-liste">
      <div class="es"><div class="ei"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" style="width:44px;height:44px"><circle cx="10.5" cy="10.5" r="6.5"/><path d="m20 20-4.35-4.35"/></svg></div><div class="et">Aramaya başlamak için en az 2 karakter yaz</div></div>
    </div>
  </div>

  <div class="sc" id="tab-kategoriler">
    <div class="card">
      <div class="card-title">Ana Gruplar</div>
      <div id="ana-grup-liste"></div>
    </div>
    <div class="card">
      <div class="card-title">Yeni Alt Grup Ekle</div>
      <div class="field"><label>Ana Grup</label><select id="yeni-ag-parent"></select></div>
      <div class="field"><label>Alt Grup Kodu</label><input type="text" id="yeni-ag-kod" placeholder="örn. YIY0401"></div>
      <div class="field"><label>Alt Grup Adı</label><input type="text" id="yeni-ag-adi" placeholder="örn. Kartonlu"></div>
      <button class="btn btn-primary btn-block" onclick="altGrupEkle()">Ekle</button>
    </div>
    <div class="card">
      <div class="card-title">Alt Gruplar</div>
      <div id="alt-grup-liste"></div>
    </div>
  </div>
</div>
```

Not: `.scroll-content` sınıfı artık kullanılmıyor (`.sc` ile değiştirildi) — CSS'teki eski `.scroll-content{...}` kuralı kaldırılabilir ama zararsız olduğu için bırakılabilir (ölü CSS, riski yok).

- [ ] **Step 3: `sekmeDegistir` fonksiyonu ekle**

`<script>` bloğunun başına, `let CU=null;` satırından hemen sonra:

```js
function sekmeDegistir(hangisi){
  document.getElementById('tab-urunler').style.display = hangisi==='urunler' ? 'block' : 'none';
  document.getElementById('tab-kategoriler').style.display = hangisi==='kategoriler' ? 'block' : 'none';
  document.getElementById('tb-urunler').classList.toggle('active', hangisi==='urunler');
  document.getElementById('tb-kategoriler').classList.toggle('active', hangisi==='kategoriler');
  if(hangisi==='kategoriler') renderKategoriler();
}
```

- [ ] **Step 4: Kategori veri yükleme + render fonksiyonları ekle**

`mevcutDonusumleriYukle()` fonksiyonundan hemen sonra ekle:

```js
let ANA_GRUPLAR=[], ALT_GRUPLAR=[];

async function kategorileriYukle(){
  try{
    const [agR, altR] = await Promise.all([
      fetch(SB_URL+'/rest/v1/urun_ana_gruplari?select=*&silindi=eq.false&order=sira', {headers:SB_HEADERS}),
      fetch(SB_URL+'/rest/v1/urun_alt_gruplari?select=*&silindi=eq.false&order=sira', {headers:SB_HEADERS})
    ]);
    ANA_GRUPLAR = agR.ok ? await agR.json() : [];
    ALT_GRUPLAR = altR.ok ? await altR.json() : [];
  }catch(e){ ANA_GRUPLAR=[]; ALT_GRUPLAR=[]; }
}

function renderKategoriler(){
  const kayitliMi=['kayit','tam'].includes(YETKI_HARITASI['urun_yonetimi']);

  const agEl=document.getElementById('ana-grup-liste');
  if(!ANA_GRUPLAR.length){
    agEl.innerHTML='<div class="et" style="color:var(--gray-400)">Henüz ana grup kaydı yok — bu, gurok_veritabani.js\'teki mevcut ürün gruplarından (YIY01 vb.) otomatik türetilmez, her ana grubu tek tek eklemen gerekir.</div>';
  } else {
    agEl.innerHTML=ANA_GRUPLAR.map(ag=>`<div class="ag-satir">
      <span class="ag-kod">${escapeHtml(ag.ana_grup_kod)}</span>
      <input type="text" id="agad-${escapeHtml(ag.ana_grup_kod)}" value="${escapeHtml(ag.ana_grup_adi)}" placeholder="Ana grup adı" ${kayitliMi?'':'disabled'}>
      <button onclick="anaGrupAdiKaydet('${escapeHtml(ag.ana_grup_kod).replace(/'/g,"\\'")}')" ${kayitliMi?'':'disabled'}>Kaydet</button>
    </div>`).join('');
  }

  const sel=document.getElementById('yeni-ag-parent');
  sel.innerHTML = ANA_GRUPLAR.length
    ? ANA_GRUPLAR.map(ag=>`<option value="${escapeHtml(ag.ana_grup_kod)}">${escapeHtml(ag.ana_grup_kod)}${ag.ana_grup_adi?' — '+escapeHtml(ag.ana_grup_adi):''}</option>`).join('')
    : '<option value="">Önce bir ana grup ekle</option>';

  const altEl=document.getElementById('alt-grup-liste');
  altEl.innerHTML = ALT_GRUPLAR.length
    ? ALT_GRUPLAR.map(alt=>{
        const ana=ANA_GRUPLAR.find(a=>a.ana_grup_kod===alt.ana_grup_kod);
        return `<div class="ag-satir"><span class="ag-kod">${escapeHtml(alt.alt_grup_kod)}</span><span style="flex:1">${escapeHtml(alt.alt_grup_adi)} <span style="color:var(--gray-500);font-size:11px">(${escapeHtml(ana?ana.ana_grup_kod:alt.ana_grup_kod)})</span></span></div>`;
      }).join('')
    : '<div class="et" style="color:var(--gray-400)">Henüz alt grup yok.</div>';
}

async function anaGrupAdiKaydet(kod){
  const ad=document.getElementById('agad-'+kod).value.trim();
  if(!ad){toast('❌ Ana grup adı boş olamaz');return;}
  sLD();
  try{
    const r=await fetch(SB_URL+'/rest/v1/urun_ana_gruplari?ana_grup_kod=eq.'+encodeURIComponent(kod),{
      method:'PATCH', headers:SB_HEADERS,
      body:JSON.stringify({ana_grup_adi:ad, guncelleme_tarihi:new Date().toISOString()})
    });
    if(!r.ok)throw new Error(await r.text());
    const ag=ANA_GRUPLAR.find(a=>a.ana_grup_kod===kod); if(ag)ag.ana_grup_adi=ad;
    toast('✅ Kaydedildi');
  }catch(e){toast('❌ Kaydedilemedi: '+e.message);}
  hLD();
}

async function altGrupEkle(){
  const anaGrup=document.getElementById('yeni-ag-parent').value;
  const kod=document.getElementById('yeni-ag-kod').value.trim().toLocaleUpperCase('tr-TR');
  const ad=document.getElementById('yeni-ag-adi').value.trim();
  if(!anaGrup){toast('❌ Önce bir ana grup ekle');return;}
  if(!kod||!ad){toast('❌ Alt grup kodu ve adı zorunlu');return;}
  if(ALT_GRUPLAR.some(a=>a.alt_grup_kod===kod)){toast('❌ Bu alt grup kodu zaten var');return;}
  sLD();
  try{
    const r=await fetch(SB_URL+'/rest/v1/urun_alt_gruplari',{
      method:'POST', headers:{...SB_HEADERS,'Prefer':'return=representation'},
      body:JSON.stringify({ana_grup_kod:anaGrup, alt_grup_kod:kod, alt_grup_adi:ad})
    });
    if(!r.ok)throw new Error(await r.text());
    const yeni=(await r.json())[0];
    ALT_GRUPLAR.push(yeni);
    document.getElementById('yeni-ag-kod').value='';
    document.getElementById('yeni-ag-adi').value='';
    renderKategoriler();
    toast('✅ Alt grup eklendi');
  }catch(e){toast('❌ Eklenemedi: '+e.message);}
  hLD();
}
```

- [ ] **Step 5: Init IIFE'sine `kategorileriYukle()` çağrısını ekle**

Mevcut:
```js
(async function(){
  CU=requireLogin();
  if(!CU)return;
  if(!requireRole(CU,['yonetici','depo','cost_control']))return;
  document.getElementById('hsub').textContent=(CU.rol||'')+' '+(CU.ad||'');
  YETKI_HARITASI=await kullaniciYetkileriGetir();
  await mevcutDonusumleriYukle();
  document.getElementById('app').style.display='flex';
})();
```

Yeni (`kategorileriYukle()` `Promise.all` ile paralel çekiliyor, ekstra bekleme süresi eklemiyor):
```js
(async function(){
  CU=requireLogin();
  if(!CU)return;
  if(!requireRole(CU,['yonetici','depo','cost_control']))return;
  document.getElementById('hsub').textContent=(CU.rol||'')+' '+(CU.ad||'');
  YETKI_HARITASI=await kullaniciYetkileriGetir();
  await Promise.all([mevcutDonusumleriYukle(), kategorileriYukle()]);
  document.getElementById('app').style.display='flex';
})();
```

- [ ] **Step 6: Tarayıcıda doğrula**

Ön koşul: Task 1'in SQL migrasyonu Supabase'de çalıştırılmış olmalı. `preview_start` ile statik sunucuyu aç, `sessionStorage`'a fabrik bir `gurok_portal_session` (`rol:'yonetici'`) yaz, `/urun-yonetimi.html`'e git. Kontrol listesi:
- "Kategori Kataloğu" sekmesine tıklayınca "Henüz ana grup kaydı yok" mesajı görünüyor (migrasyon yeni çalıştırıldıysa tablo boş olacak — bu beklenen).
- Konsolda JS hatası yok.
- "Ürünler" sekmesi eskisi gibi çalışıyor (regresyon yok).

Not: Ana grup kataloğunu doldurmak (12 satır ekleyip adlandırmak) bu task'ın kapsamında değil — bu, migrasyon sonrası kullanıcının kendisinin, gerçek iş bilgisiyle yapacağı bir veri girişi adımı. Task'ın kendisi sadece UI'nin doğru çalıştığını doğrular; gerçek 12 satırı eklemek/adlandırmak kullanıcıya kalan bir sonraki adımdır.

- [ ] **Step 7: Commit**

```bash
git add urun-yonetimi.html
git commit -m "feat: urun-yonetimi.html'e Kategori Kataloğu sekmesi (ana/alt grup adlandırma)"
```

---

### Task 3: Ürün listesine tekli Alt Grup ataması

**Files:**
- Modify: `urun-yonetimi.html`

**Interfaces:**
- Consumes: Task 2'nin `ALT_GRUPLAR` globali, Task 1'in `urun_siniflandirma` tablosu.
- Produces: global `URUN_ALT_GRUP_ATANMIS` (harita: `{urun_kodu: alt_grup_kod}`) — Task 4'ün Excel dışa-aktarma fonksiyonu bu haritayı okuyacak.

- [ ] **Step 1: Sınıflandırma haritasını yükleyen fonksiyonu ekle**

`mevcutDonusumleriYukle()`'den sonra:

```js
let URUN_ALT_GRUP_ATANMIS={};

async function siniflandirmalariYukle(){
  try{
    const r=await fetch(SB_URL+'/rest/v1/urun_siniflandirma?select=urun_kodu,alt_grup_kod&silindi=eq.false',{headers:SB_HEADERS});
    if(r.ok){
      URUN_ALT_GRUP_ATANMIS={};
      (await r.json()).forEach(row=>{URUN_ALT_GRUP_ATANMIS[row.urun_kodu]=row.alt_grup_kod;});
    }
  }catch(e){}
}
```

- [ ] **Step 2: `aramaYap()`'ın render ettiği satıra Alt Grup seçici ekle**

Mevcut `aramaYap()` içindeki satır şablonu (`urow-fields` div'i):
```js
    return`<div class="urow" id="urow-${escapeHtml(u.kod)}">
      <div>
        <div class="urow-ad">${escapeHtml(u.ad)}</div>
        <div class="urow-kod">${escapeHtml(u.kod)} · <span class="urow-birim">${escapeHtml(u.birim)}</span></div>
      </div>
      <div class="urow-fields">
        <input type="text" id="bb-${escapeHtml(u.kod)}" placeholder="Büyük Birim" value="${escapeHtml(mevcut.buyuk_birim||'')}" ${kayitliMi?'':'disabled'}>
        <input type="number" min="0.01" step="0.01" id="cp-${escapeHtml(u.kod)}" placeholder="Çarpan" value="${mevcut.carpan||''}" ${kayitliMi?'':'disabled'}>
        <button onclick="donusumKaydet('${escapeHtml(u.kod).replace(/'/g,"\\'")}')" ${kayitliMi?'':'disabled'}>Kaydet</button>
      </div>
    </div>`;
```

Yeni (Alt Grup `<select>` eklendi — ürünün kendi `u.grup` koduna uyan alt gruplarla filtrelenir; hiç alt grup yoksa boş/disabled select gösterir):

```js
    const uyanAltGruplar=ALT_GRUPLAR.filter(a=>a.ana_grup_kod===u.grup);
    const atanmisAltGrup=URUN_ALT_GRUP_ATANMIS[u.kod]||'';
    const altGrupSecici = uyanAltGruplar.length
      ? `<select id="ag-${escapeHtml(u.kod)}" ${kayitliMi?'':'disabled'}>
           <option value="">— Alt grup seç —</option>
           ${uyanAltGruplar.map(a=>`<option value="${escapeHtml(a.alt_grup_kod)}" ${a.alt_grup_kod===atanmisAltGrup?'selected':''}>${escapeHtml(a.alt_grup_adi)}</option>`).join('')}
         </select>`
      : `<select disabled><option>Bu grup için alt grup yok</option></select>`;
    return`<div class="urow" id="urow-${escapeHtml(u.kod)}">
      <div>
        <div class="urow-ad">${escapeHtml(u.ad)}</div>
        <div class="urow-kod">${escapeHtml(u.kod)} · <span class="urow-birim">${escapeHtml(u.birim)}</span></div>
      </div>
      <div class="urow-fields">
        <input type="text" id="bb-${escapeHtml(u.kod)}" placeholder="Büyük Birim" value="${escapeHtml(mevcut.buyuk_birim||'')}" ${kayitliMi?'':'disabled'}>
        <input type="number" min="0.01" step="0.01" id="cp-${escapeHtml(u.kod)}" placeholder="Çarpan" value="${mevcut.carpan||''}" ${kayitliMi?'':'disabled'}>
        <button onclick="donusumKaydet('${escapeHtml(u.kod).replace(/'/g,"\\'")}')" ${kayitliMi?'':'disabled'}>Kaydet</button>
        ${altGrupSecici}
        <button onclick="altGrupAta('${escapeHtml(u.kod).replace(/'/g,"\\'")}')" ${kayitliMi&&uyanAltGruplar.length?'':'disabled'}>Ata</button>
      </div>
    </div>`;
```

- [ ] **Step 3: `altGrupAta` fonksiyonunu ekle**

`donusumKaydet` fonksiyonundan sonra:

```js
async function altGrupAta(kod){
  const altGrupKod=document.getElementById('ag-'+kod).value;
  if(!altGrupKod){toast('❌ Bir alt grup seç');return;}
  sLD();
  try{
    const r=await fetch(SB_URL+'/rest/v1/urun_siniflandirma?on_conflict=urun_kodu',{
      method:'POST',
      headers:{...SB_HEADERS,'Prefer':'resolution=merge-duplicates'},
      body:JSON.stringify({urun_kodu:kod, alt_grup_kod:altGrupKod, silindi:false})
    });
    if(!r.ok)throw new Error(await r.text());
    URUN_ALT_GRUP_ATANMIS[kod]=altGrupKod;
    toast('✅ Alt grup atandı');
  }catch(e){toast('❌ Atanamadı: '+e.message);}
  hLD();
}
```

- [ ] **Step 4: Init IIFE'sine `siniflandirmalariYukle()` ekle**

`Promise.all([mevcutDonusumleriYukle(), kategorileriYukle()])` satırını şuna genişlet:
```js
  await Promise.all([mevcutDonusumleriYukle(), kategorileriYukle(), siniflandirmalariYukle()]);
```

- [ ] **Step 5: Tarayıcıda doğrula**

Ön koşul: Task 2'nin Step 6'sındaki manuel adımda en az 1 ana grup + 1 alt grup eklenmiş olmalı (test için `YIY01` gibi mevcut bir gruba karşılık gelen kod kullan). Bir ürün ara (o ana gruba ait), Alt Grup dropdown'ının dolu geldiğini, bir seçim yapıp "Ata"ya basınca toast ile onaylandığını, sayfa yenilenince seçimin kalıcı olduğunu doğrula.

- [ ] **Step 6: Commit**

```bash
git add urun-yonetimi.html
git commit -m "feat: urun-yonetimi.html'e ürün bazlı tekli alt-grup ataması"
```

---

### Task 4: Excel toplu alt-grup ataması (1264 ürün)

**Files:**
- Modify: `urun-yonetimi.html`
- Modify: `urun-yonetimi.html`'in `<head>`'i — `ortak-excel.js` script tag'i eklenir (şu an yüklenmiyor)

**Interfaces:**
- Consumes: `ortak-excel.js`'in `excelSablonIndir`, `excelDosyaOku`, `excelSatirlariSiniflandir`, `excelOnizlemeGoster`, `excelTopluYaz`, `excelImportGecmisiYaz` fonksiyonları (imzaları `stok-takip.html`'deki `stokMinimumExcel*` üçlüsünden birebir alınmıştır — bkz. Step 2/3/4).
- Consumes: `URUN_DB` (`gurok_veritabani.js`), `ALT_GRUPLAR`, `URUN_ALT_GRUP_ATANMIS` (Task 2/3'ün globalleri).

- [ ] **Step 1: `<head>`'e `ortak-excel.js` ekle**

`urun-yonetimi.html`'in mevcut head'inde:
```html
<script src="ortak.js"></script>
<script src="gurok_veritabani.js"></script>
```

Bunu şuna çevir (ortak-excel.js, ortak.js'den sonra, gurok_veritabani.js'den önce — diğer entegrasyonlarla (stok-takip.html) aynı sıra):
```html
<script src="ortak.js"></script>
<script src="ortak-excel.js"></script>
<script src="gurok_veritabani.js"></script>
```

- [ ] **Step 2: Excel spec + dışa aktarma fonksiyonunu ekle**

`siniflandirmalariYukle()`'den sonra:

```js
const urunSiniflandirmaExcelSpec = [
  {alan:'urun_kodu', baslik:'Ürün Kodu', tip:'text', zorunlu:true, genislik:16},
  {alan:'urun_adi', baslik:'Ürün Adı', tip:'text', genislik:30},
  {alan:'ana_grup', baslik:'Ana Grup', tip:'text', genislik:12},
  {alan:'alt_grup_kod', baslik:'Alt Grup Kodu', tip:'text', zorunlu:true, genislik:14},
  {alan:'alt_grup_adi', baslik:'Alt Grup Adı (bilgi amaçlı)', tip:'text', genislik:22}
];

async function urunSiniflandirmaExcelAktar(){
  const altGrupHarita={};
  ALT_GRUPLAR.forEach(a=>{altGrupHarita[a.alt_grup_kod]=a.alt_grup_adi;});
  const veriler=URUN_DB.map(u=>({
    urun_kodu:u.kod,
    urun_adi:u.ad,
    ana_grup:u.grup||'',
    alt_grup_kod:URUN_ALT_GRUP_ATANMIS[u.kod]||'',
    alt_grup_adi:altGrupHarita[URUN_ALT_GRUP_ATANMIS[u.kod]]||''
  }));
  await excelSablonIndir(urunSiniflandirmaExcelSpec, veriler, 'urun-siniflandirma-'+new Date().toISOString().split('T')[0]+'.xlsx');
}
```

- [ ] **Step 3: Excel yükleme + önizleme fonksiyonunu ekle**

Yukarıdaki fonksiyondan hemen sonra. `fkSet`, Excel'deki `alt_grup_kod` değerinin **kataloğa kayıtlı** olup olmadığını doğrular (yazım hatasıyla kataloğu kirletmeyi önlemek için — spec'te belirtilen kritik gereksinim):

```js
async function urunSiniflandirmaExcelYukle(event){
  const file=event.target.files[0]; if(!file)return; event.target.value='';
  sLD();
  try{
    const satirlar=await excelDosyaOku(file);
    hLD();
    const urunKoduSet=new Set(URUN_DB.map(u=>u.kod));
    const altGrupKodSet=new Set(ALT_GRUPLAR.map(a=>a.alt_grup_kod));
    const mevcutKayitlar=Object.entries(URUN_ALT_GRUP_ATANMIS).map(([kod,altGrupKod])=>({urun_kodu:kod, alt_grup_kod:altGrupKod}));
    // excelSatirlariSiniflandir bir NESNE değil, doğrudan bir DİZİ döner
    // (her eleman {satirNo, alanlar, sinif, hatalar[], eskiDeger, yeniDeger,
    // kayitId} şeklinde — bkz. ortak-excel.js:130-131 imza yorumu).
    const siniflandirma=excelSatirlariSiniflandir(urunSiniflandirmaExcelSpec, satirlar, mevcutKayitlar, {
      dogalAnahtarlar:['urun_kodu'],
      fkAlan:'urun_kodu', fkSet:urunKoduSet
    });
    // Ürün kodu FK'sinden ayrı olarak, alt_grup_kod'un kataloğa kayıtlı olup
    // olmadığını da işaretle — excelSatirlariSiniflandir opts başına tek bir
    // fkAlan/fkSet çifti kabul ediyor (burada urun_kodu için kullanıldı),
    // ikinci bir doğrulamayı burada elle ekliyoruz. `hatalar` bir DİZİ,
    // tekil bir `hataMesaji` alanı yok — push ile eklenir.
    siniflandirma.forEach(s=>{
      if(s.sinif==='hata'||s.sinif==='bulunamadi'||s.sinif==='mukerrer')return;
      const altGrupKod=(s.alanlar.alt_grup_kod||'').trim().toLocaleUpperCase('tr-TR');
      if(!altGrupKodSet.has(altGrupKod)){
        s.sinif='hata';
        s.hatalar.push('Alt grup kodu kataloğa kayıtlı değil: "'+(s.alanlar.alt_grup_kod||'')+'" — önce Kategori Kataloğu sekmesinden ekle');
      } else {
        s.alanlar.alt_grup_kod=altGrupKod;
      }
    });
    excelOnizlemeGoster(siniflandirma,{
      spec:urunSiniflandirmaExcelSpec,
      dosyaAdiOnek:'urun-siniflandirma',
      onUygula:(mod,satirlarYaz)=>urunSiniflandirmaExcelUygula(mod,satirlarYaz)
    });
  }catch(err){
    hLD();
    toast('❌ Dosya okunamadı: '+err.message);
  }
}

async function urunSiniflandirmaExcelUygula(mod,yazilacaklar){
  if(!yazilacaklar.length){toast('ℹ️ Yazılacak satır yok');return;}
  const satirlar=yazilacaklar.map(s=>({urun_kodu:s.alanlar.urun_kodu, alt_grup_kod:s.alanlar.alt_grup_kod, silindi:false}));
  sLD();
  const sonuc=await excelTopluYaz('urun_siniflandirma', satirlar, {onConflict:'urun_kodu'});
  yazilacaklar.forEach(s=>{ if(s.alanlar.urun_kodu) URUN_ALT_GRUP_ATANMIS[s.alanlar.urun_kodu]=s.alanlar.alt_grup_kod; });
  await excelImportGecmisiYaz({
    tabloAdi:'urun_siniflandirma', ilgiliId:null, dosyaAdi:'urun-siniflandirma.xlsx',
    kullaniciAd:CU?.ad||'', mod, toplamSatir:yazilacaklar.length,
    yeniSayisi:yazilacaklar.filter(s=>s.sinif==='yeni').length,
    guncellemeSayisi:yazilacaklar.filter(s=>s.sinif==='guncelleme').length,
    hataSayisi:0, atlananSayisi:0
  }, yazilacaklar);
  hLD();
  toast(sonuc.hataliGrup?'⚠️ Bazı satırlar yazılamadı':'✅ Sınıflandırma güncellendi ('+sonuc.toplamYazilan+' satır)');
  const arama=document.getElementById('arama');
  if(arama.value.trim().length>=2) aramaYap();
}
```

- [ ] **Step 4: "Ürünler" sekmesine Excel dışa/içe aktarma butonlarını ekle**

`tab-urunler` içindeki `.uyari` div'inden hemen sonra, `.search-bar`'dan önce:

```html
    <div style="display:flex;gap:8px;margin-bottom:8px">
      <button class="btn btn-gray btn-sm" style="flex:1" onclick="urunSiniflandirmaExcelAktar()">Sınıflandırma — Excel'e Aktar</button>
      <button class="btn btn-gray btn-sm" style="flex:1" onclick="document.getElementById('siniflandirma-excel-input').click()">Sınıflandırma — Excel'den Yükle</button>
    </div>
    <input type="file" id="siniflandirma-excel-input" accept=".xlsx,.xls" style="display:none" onchange="urunSiniflandirmaExcelYukle(event)">
```

(`.btn-gray` sınıfı bu dosyanın CSS'inde henüz yok — Task 2 Step 1'de eklenen `.btn`/`.btn-primary` kurallarının yanına ekle: `.btn-gray{background:var(--gray-200);color:var(--gray-700)}`.)

- [ ] **Step 5: Tarayıcıda doğrula**

Ön koşul: Task 2/3'ün manuel adımlarında en az 2-3 alt grup tanımlanmış olmalı. "Sınıflandırma — Excel'e Aktar"a tıkla, indirilen dosyada 1264 satır + doğru kolon başlıklarını doğrula. Dosyada birkaç satırın `Alt Grup Kodu` sütununu (kataloğa kayıtlı gerçek bir kodla) doldur, bir satıra da **kataloğa kayıtlı olmayan** bir kod yaz (örn. "XXXX99"). "Excel'den Yükle" ile geri yükle, önizleme modalında: geçerli satırların "yeni"/"güncelleme" olarak, geçersiz kodlu satırın "hata" olarak (yukarıdaki özel mesajla) göründüğünü doğrula. Uygula'ya bas, "Ürünler" sekmesinde ilgili ürünlerin Alt Grup seçiminin güncellendiğini doğrula.

- [ ] **Step 6: Commit**

```bash
git add urun-yonetimi.html
git commit -m "feat: urun-yonetimi.html'e 1264 ürün için Excel toplu alt-grup ataması"
```

---

### Task 5: Uçtan uca regresyon + Obsidian vault güncellemesi

**Files:**
- Modify: `D:\ERP-Bilgi-Haritasi\02-Moduller\Stok-Depo.md` (urun-yonetimi.html zaten burada listeleniyor — yeni sınıflandırma özelliği not edilir)
- Modify: `D:\ERP-Bilgi-Haritasi\01-Mimari\Gelisim-Gecmisi.md` (yeni tarihli satır eklenir)

**Interfaces:**
- Consumes: yok (bu task sadece doğrulama + dokümantasyon, kod değişikliği yok).

- [ ] **Step 1: Tam uçtan uca manuel test**

1. `urun-yonetimi.html`'i aç, "Kategori Kataloğu" sekmesinde en az 2 ana gruba ad ver, her birinin altına en az 1 alt grup ekle.
2. "Ürünler" sekmesinde bu gruplara ait birkaç ürüne tekli alt-grup ata.
3. Excel'e aktar, tüm ürünlerin göründüğünü, atanmışların doğru alt-grup kodunu taşıdığını doğrula.
4. Excel'de 10-15 satır doldur (bazıları yeni atama, bazıları mevcut atamayı değiştiren, biri geçersiz kod), yükle, önizlemede sınıf dağılımının (yeni/güncelleme/hata) doğru olduğunu doğrula, uygula.
5. Sayfayı yenile, tüm atamaların kalıcı olduğunu doğrula.
6. Konsolda hiçbir JS hatası olmadığını doğrula (`read_console_messages`, `onlyErrors:true`).
7. `stok-takip.html`, `mal-kabul-liste.html` gibi `URUN_DB`/birim-dönüşümü kullanan diğer sayfalarda hiçbir regresyon olmadığını doğrula (bu plan onlara dokunmadı, ama `urun-yonetimi.html`'in kendi birim-dönüşüm akışının bozulmadığını doğrulamak için Task 2/3/4 sonrası "Büyük Birim/Çarpan/Kaydet" akışını da tekrar test et).

- [ ] **Step 2: Obsidian vault güncelle**

`D:\ERP-Bilgi-Haritasi\02-Moduller\Stok-Depo.md`'ye şu satırı ekle (mevcut "Dikkat çeken noktalar" listesinin sonuna):
```
- Ürün kalem kodu sınıflandırma (2026-07-26): `urun-yonetimi.html`'e Ana Grup/Alt Grup kataloğu (`urun_ana_gruplari`/`urun_alt_gruplari`) + ürün başına atama (`urun_siniflandirma`) eklendi — `urun_birim_donusum` ile aynı desen (kod sabit kalır, ayrı eşleme tablosu). 1264 ürünün toplu ataması Excel round-trip ile (`stokMinimumExcel*` deseninin tekrarı). Detay: `docs/superpowers/specs/2026-07-26-urun-siniflandirma-design.md`.
```

`D:\ERP-Bilgi-Haritasi\01-Mimari\Gelisim-Gecmisi.md`'ye, en son tarihli maddeden sonra yeni bir madde ekle:
```
- **07-26** — Ürün kalem kodu sınıflandırma: `urun_ana_gruplari`/`urun_alt_gruplari`/`urun_siniflandirma` tabloları + `urun-yonetimi.html`'e Kategori Kataloğu sekmesi + tekli/Excel-toplu alt-grup ataması eklendi. Mevcut ürün kodları (`YIY01000002` vb.) değişmedi — sınıflandırma tamamen ayrı bir eşleme katmanında.
```

Başlıktaki tarih aralığını `(2026-06-22 → 2026-07-24)`'ten `(2026-06-22 → 2026-07-26)`'ya güncelle.

- [ ] **Step 3: Commit**

```bash
cd D:\ERP-Bilgi-Haritasi
git add 02-Moduller/Stok-Depo.md 01-Mimari/Gelisim-Gecmisi.md
git commit -m "docs: ürün sınıflandırma özelliğini belgeledi"
cd D:\erp
```

(Not: `D:\ERP-Bilgi-Haritasi` ve `D:\erp` ayrı git repoları — iki ayrı commit gerekir.)
