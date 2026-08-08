# Gelişmiş Filtreleme Altyapısı — Uygulama Planı

> **Ajan işçiler için:** GEREKLİ ALT-SKILL: superpowers:executing-plans (bu oturumda) ile görev-görev uygula. Adımlar checkbox (`- [ ]`).

**Hedef:** Merkezi, tekrar kullanılabilir bir `filtre.js` + `kayitli_filtreler` DB tablosu ile, her sütunun veri tipine uygun operatörlerle (VE) filtrelenebildiği gelişmiş filtreleme; stok-takip pilotu.

**Mimari:** `filtre.js` saf yardımcı (operatör tanımları + client predicate + panel UI + etiketler + kayıtlı-filtre CRUD). Filtre modeli yürütmeden ayrı. Stok-takip pilotu client-predicate ile mevcut listeye biner. Kayıtlı filtreler RLS'li DB tablosunda.

**Teknoloji:** Statik HTML/JS + Supabase. Test çerçevesi YOK → SQL Editor + uygulamada elle doğrulama.

## Global Constraints
- SQL dosya olarak verilir, kullanıcı SQL Editor'de çalıştırır.
- Client değişikliği `main`'e push → GitHub Pages.
- VE-only v1 (VEYA/grup kapsam dışı). Türkçe metin: `toLocaleLowerCase('tr-TR')`, diakritik korunur.
- Mevcut arama kutusu + kritik/ABC/kategori sekmeleri + stok işlemleri BOZULMAZ.
- RLS korunur; değerler asla SQL'e gömülmez (client predicate).
- Commit yazarı: `git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com"`.

---

### Task 1: SQL — `kayitli_filtreler` tablosu + `auth_kullanici_id()` + RLS

**Files:**
- Create: `docs/kurulum/2026-08-04-kayitli-filtreler.sql`

**Interfaces:**
- Produces: tablo `public.kayitli_filtreler(id,kullanici_id,ekran,ad,filtreler jsonb,paylasimli,olusturma_tarihi)`;
  fonksiyon `auth_kullanici_id() returns text` (auth.uid()→kullanicilar.id).

- [ ] **Adım 1: SQL dosyasını yaz**

```sql
-- 2026-08-04 — Kayıtlı filtreler (kullanıcıya özel + yönetici ortak şablon)
begin;

-- auth.uid() -> kullanicilar.id (auth_otel_id deseniyle)
create or replace function public.auth_kullanici_id()
returns text language sql stable security definer set search_path = public as $$
  select id from public.kullanicilar where auth_user_id = auth.uid() limit 1;
$$;
grant execute on function public.auth_kullanici_id() to authenticated;

create table if not exists public.kayitli_filtreler (
  id uuid primary key default gen_random_uuid(),
  kullanici_id text,
  ekran text not null,
  ad text not null,
  filtreler jsonb not null,
  paylasimli boolean not null default false,
  olusturma_tarihi timestamptz not null default now()
);
alter table public.kayitli_filtreler enable row level security;

-- SELECT: kendi filtrelerin + paylaşımlı şablonlar
drop policy if exists kf_select on public.kayitli_filtreler;
create policy kf_select on public.kayitli_filtreler for select to authenticated
  using (kullanici_id = public.auth_kullanici_id() or paylasimli = true);

-- INSERT: yalnız kendi adına (paylaşımlı şablon için yönetici yetkisi)
drop policy if exists kf_insert on public.kayitli_filtreler;
create policy kf_insert on public.kayitli_filtreler for insert to authenticated
  with check (
    kullanici_id = public.auth_kullanici_id()
    and (paylasimli = false or public.auth_yetki_var('kullanici_yonetimi','kayit'))
  );

-- UPDATE/DELETE: yalnız kendi kayıtların
drop policy if exists kf_update on public.kayitli_filtreler;
create policy kf_update on public.kayitli_filtreler for update to authenticated
  using (kullanici_id = public.auth_kullanici_id())
  with check (kullanici_id = public.auth_kullanici_id());
drop policy if exists kf_delete on public.kayitli_filtreler;
create policy kf_delete on public.kayitli_filtreler for delete to authenticated
  using (kullanici_id = public.auth_kullanici_id());

commit;
notify pgrst, 'reload schema';
```

- [ ] **Adım 2: Kullanıcı çalıştırır + doğrular**
```sql
select proname from pg_proc where proname='auth_kullanici_id';
select tablename from pg_tables where tablename='kayitli_filtreler';
```
İkisi de 1 satır dönmeli.

- [ ] **Adım 3: Commit**
```bash
git add docs/kurulum/2026-08-04-kayitli-filtreler.sql
git commit -m "feat(filtre): kayitli_filtreler tablosu + auth_kullanici_id + RLS"
```

---

### Task 2: `filtre.js` — merkezi filtre modülü

**Files:**
- Create: `filtre.js`

**Interfaces:**
- Produces (global `window.Filtre`):
  - `Filtre.filtreleUygula(rows, filtreler, alanlar)` → filtrelenmiş dizi
  - `Filtre.panelOlustur(container, alanlar, aktif, onDegisim)` → panel render
  - `Filtre.etiketleriCiz(container, aktif, alanlar, onKaldir)` → aktif filtre etiketleri
  - `Filtre.kayitliGetir(ekran)`, `Filtre.kayitliKaydet(ekran,ad,filtreler,paylasimli)`, `Filtre.kayitliSil(id)`
  - Alan config: `{field,label,type,options?,getValue?}` (type: text|number|date|multi_select|boolean).
    `getValue(row)` verilirse hesaplanan alanlar için kullanılır (yoksa `row[field]`).
  - Filtre modeli: `{field,type,operator,value}`.
- Consumes: `SB_URL`, `SB_HEADERS`, `oturumAccessTokenGetir` (global). Türkçe normalize kendi içinde.

- [ ] **Adım 1: filtre.js dosyasını yaz** (tam kod)

```javascript
// filtre.js — Merkezi gelişmiş filtre altyapısı (client-predicate, VE-only v1, Türkçe-duyarlı).
// Ekrandan bağımsız. window.Filtre altında API sunar.
(function(){
'use strict';

const norm = s => String(s ?? '').toLocaleLowerCase('tr-TR'); // i/İ/ı/I doğru; ş/ç korunur

const OPS = {
  text:[
    {op:'equals',label:'Eşittir',n:1},{op:'not_equals',label:'Eşit değildir',n:1},
    {op:'contains',label:'İçerir',n:1},{op:'not_contains',label:'İçermez',n:1},
    {op:'starts',label:'İle başlar',n:1},{op:'not_starts',label:'İle başlamaz',n:1},
    {op:'ends',label:'İle biter',n:1},{op:'not_ends',label:'İle bitmez',n:1},
    {op:'empty',label:'Boştur',n:0},{op:'not_empty',label:'Boş değildir',n:0},
  ],
  number:[
    {op:'eq',label:'Eşittir',n:1},{op:'ne',label:'Eşit değildir',n:1},
    {op:'gt',label:'Büyüktür',n:1},{op:'gte',label:'Büyük veya eşit',n:1},
    {op:'lt',label:'Küçüktür',n:1},{op:'lte',label:'Küçük veya eşit',n:1},
    {op:'between',label:'Arasında',n:2},{op:'not_between',label:'Arasında değil',n:2},
    {op:'zero',label:'Sıfırdır',n:0},{op:'not_zero',label:'Sıfır değildir',n:0},
    {op:'empty',label:'Boştur',n:0},{op:'not_empty',label:'Boş değildir',n:0},
  ],
  date:[
    {op:'on',label:'Tarihine eşit',n:1},{op:'before',label:'Öncesi',n:1},{op:'after',label:'Sonrası',n:1},
    {op:'between',label:'Arasında',n:2},
    {op:'today',label:'Bugün',n:0},{op:'yesterday',label:'Dün',n:0},
    {op:'this_week',label:'Bu hafta',n:0},{op:'last_week',label:'Geçen hafta',n:0},
    {op:'this_month',label:'Bu ay',n:0},{op:'last_month',label:'Geçen ay',n:0},
    {op:'this_year',label:'Bu yıl',n:0},{op:'last7',label:'Son 7 gün',n:0},{op:'last30',label:'Son 30 gün',n:0},
    {op:'overdue',label:'Süresi geçmiş',n:0},{op:'due_today',label:'Bugün doluyor',n:0},{op:'due7',label:'7 günde dolacak',n:0},
    {op:'empty',label:'Boştur',n:0},{op:'not_empty',label:'Boş değildir',n:0},
  ],
  multi_select:[
    {op:'in',label:'Seçilenlerden biri',n:'list'},{op:'not_in',label:'Seçilenlerden biri değil',n:'list'},
    {op:'equals',label:'Eşittir',n:1},{op:'not_equals',label:'Eşit değildir',n:1},
    {op:'empty',label:'Boştur',n:0},{op:'not_empty',label:'Boş değildir',n:0},
  ],
  boolean:[{op:'true',label:'Evet',n:0},{op:'false',label:'Hayır',n:0}],
};

// ---- Tarih yardımcıları ----
function gunBasi(d){ const x=new Date(d); x.setHours(0,0,0,0); return x; }
function bugun(){ return gunBasi(new Date()); }
function gunEkle(d,n){ const x=new Date(d); x.setDate(x.getDate()+n); return x; }
function haftaBasi(d){ const x=gunBasi(d); const g=(x.getDay()+6)%7; return gunEkle(x,-g); } // Pazartesi
function ayBasi(d){ const x=gunBasi(d); x.setDate(1); return x; }
function tarihPreset(op){
  const b=bugun();
  switch(op){
    case 'today': return [b, gunEkle(b,1)];
    case 'yesterday': return [gunEkle(b,-1), b];
    case 'this_week': { const s=haftaBasi(b); return [s, gunEkle(s,7)]; }
    case 'last_week': { const s=gunEkle(haftaBasi(b),-7); return [s, gunEkle(s,7)]; }
    case 'this_month': { const s=ayBasi(b); const e=new Date(s); e.setMonth(e.getMonth()+1); return [s,e]; }
    case 'last_month': { const e=ayBasi(b); const s=new Date(e); s.setMonth(s.getMonth()-1); return [s,e]; }
    case 'this_year': { const s=new Date(b.getFullYear(),0,1); const e=new Date(b.getFullYear()+1,0,1); return [s,e]; }
    case 'last7': return [gunEkle(b,-7), gunEkle(b,1)];
    case 'last30': return [gunEkle(b,-30), gunEkle(b,1)];
    default: return null;
  }
}
function tarihParse(v){ if(!v) return null; const d=new Date(v); return isNaN(d)?null:d; }

// ---- Tip bazlı geçer-mi ----
function textGec(h, op, v){
  const H=norm(h), V=norm(v);
  switch(op){
    case 'equals': return H===V;
    case 'not_equals': return H!==V;
    case 'contains': return H.includes(V);
    case 'not_contains': return !H.includes(V);
    case 'starts': return H.startsWith(V);
    case 'not_starts': return !H.startsWith(V);
    case 'ends': return H.endsWith(V);
    case 'not_ends': return !H.endsWith(V);
    case 'empty': return H==='';
    case 'not_empty': return H!=='';
    case 'in': return (Array.isArray(v)?v:[v]).map(norm).includes(H);
    case 'not_in': return !(Array.isArray(v)?v:[v]).map(norm).includes(H);
    default: return true;
  }
}
function numGec(h, op, v){
  const bos = (h===null||h===undefined||h==='');
  if(op==='empty') return bos;
  if(op==='not_empty') return !bos;
  const n=parseFloat(h);
  if(op==='zero') return n===0;
  if(op==='not_zero') return n!==0;
  if(isNaN(n)) return false;
  if(op==='between'){ const {min,max}=v||{}; return n>=parseFloat(min) && n<=parseFloat(max); }
  if(op==='not_between'){ const {min,max}=v||{}; return !(n>=parseFloat(min) && n<=parseFloat(max)); }
  const x=parseFloat(v);
  switch(op){ case 'eq':return n===x; case 'ne':return n!==x; case 'gt':return n>x;
    case 'gte':return n>=x; case 'lt':return n<x; case 'lte':return n<=x; default:return true; }
}
function dateGec(h, op, v){
  const d=tarihParse(h); const bos=!d;
  if(op==='empty') return bos;
  if(op==='not_empty') return !bos;
  if(bos) return false;
  const g=gunBasi(d), b=bugun();
  if(op==='on'){ const t=tarihParse(v); return t && gunBasi(t).getTime()===g.getTime(); }
  if(op==='before'){ const t=tarihParse(v); return t && g < gunBasi(t); }
  if(op==='after'){ const t=tarihParse(v); return t && g > gunBasi(t); }
  if(op==='between'){ const s=tarihParse(v&&v.start), e=tarihParse(v&&v.end); return s&&e && g>=gunBasi(s) && g<=gunBasi(e); }
  if(op==='overdue') return g < b;
  if(op==='due_today') return g.getTime()===b.getTime();
  if(op==='due7') return g>=b && g<=gunEkle(b,7);
  const pr=tarihPreset(op); if(pr) return d>=pr[0] && d<pr[1];
  return true;
}
function multiGec(h, op, v){
  const arr=Array.isArray(v)?v:(v==null?[]:[v]);
  const H=norm(h);
  switch(op){
    case 'in': return arr.map(norm).includes(H);
    case 'not_in': return !arr.map(norm).includes(H);
    case 'equals': return H===norm(arr[0]);
    case 'not_equals': return H!==norm(arr[0]);
    case 'empty': return H==='';
    case 'not_empty': return H!=='';
    default: return true;
  }
}
function boolGec(h, op){ const b=(h===true||h==='true'||h===1); return op==='true'?b:!b; }

function hucre(row, alan){ return alan && alan.getValue ? alan.getValue(row) : (row ? row[alan?alan.field:undefined] : undefined); }

function filtreGecer(row, f, alan){
  const h=hucre(row, alan||{field:f.field});
  switch(f.type){
    case 'text': return textGec(h, f.operator, f.value);
    case 'number': return numGec(h, f.operator, f.value);
    case 'date': return dateGec(h, f.operator, f.value);
    case 'multi_select': return multiGec(h, f.operator, f.value);
    case 'boolean': return boolGec(h, f.operator);
    default: return true;
  }
}

function filtreleUygula(rows, filtreler, alanlar){
  if(!filtreler || !filtreler.length) return rows;
  const map={}; (alanlar||[]).forEach(a=>map[a.field]=a);
  return rows.filter(row => filtreler.every(f => filtreGecer(row, f, map[f.field])));
}

// ---- Kayıtlı filtre CRUD (RLS'li) ----
async function kayitliGetir(ekran){
  try{
    const r=await fetch(SB_URL+'/rest/v1/kayitli_filtreler?ekran=eq.'+encodeURIComponent(ekran)+'&select=*&order=ad',{headers:SB_HEADERS});
    return r.ok ? await r.json() : [];
  }catch(e){ return []; }
}
async function kayitliKaydet(ekran, ad, filtreler, paylasimli){
  const kid = (window.CU&&CU.id) || (window.OTURUM_KULLANICI&&OTURUM_KULLANICI.id) || null;
  const r=await fetch(SB_URL+'/rest/v1/kayitli_filtreler',{method:'POST',headers:{...SB_HEADERS,'Prefer':'return=representation'},
    body:JSON.stringify({kullanici_id:kid, ekran, ad, filtreler, paylasimli:!!paylasimli})});
  if(!r.ok) throw new Error(await r.text().catch(()=>'kaydedilemedi'));
  return (await r.json())[0];
}
async function kayitliSil(id){
  const r=await fetch(SB_URL+'/rest/v1/kayitli_filtreler?id=eq.'+id,{method:'DELETE',headers:SB_HEADERS});
  return r.ok;
}

// ---- UI: aktif filtre etiketleri ----
function opLabel(type, op){ return (OPS[type]||[]).find(o=>o.op===op)?.label || op; }
function degerMetni(f){
  if(f.value==null) return '';
  if(f.type==='number' && (f.operator==='between'||f.operator==='not_between')) return `${f.value.min}–${f.value.max}`;
  if(f.type==='date' && f.operator==='between') return `${f.value.start}–${f.value.end}`;
  if(Array.isArray(f.value)) return f.value.join(', ');
  return String(f.value);
}
function esc(s){ return String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])); }

function etiketleriCiz(container, aktif, alanlar, onKaldir){
  const map={}; (alanlar||[]).forEach(a=>map[a.field]=a);
  if(!aktif.length){ container.innerHTML=''; return; }
  container.innerHTML = aktif.map((f,i)=>{
    const lbl=(map[f.field]?.label)||f.field;
    const dv=degerMetni(f);
    return `<span style="display:inline-flex;align-items:center;gap:6px;background:#eef2ff;color:#3730a3;border-radius:14px;padding:4px 10px;font-size:11px;font-weight:600;margin:2px">
      ${esc(lbl)}: ${esc(opLabel(f.type,f.operator))}${dv?' '+esc(dv):''}
      <span onclick="(${''})" data-i="${i}" class="filtre-etiket-x" style="cursor:pointer;font-weight:800">✕</span></span>`;
  }).join('') + `<button class="filtre-temizle" style="background:none;border:none;color:#9b1c1c;font-size:11px;font-weight:700;cursor:pointer;margin-left:6px">Tümünü temizle</button>`;
  container.querySelectorAll('.filtre-etiket-x').forEach(x=>x.onclick=()=>onKaldir(parseInt(x.dataset.i,10)));
  container.querySelector('.filtre-temizle').onclick=()=>onKaldir(-1); // -1 = tümünü temizle
}

// ---- UI: filtre paneli (alan→operatör→değer + ekle/uygula) ----
function girisWidget(type, op, val){
  const meta=(OPS[type]||[]).find(o=>o.op===op);
  const n=meta?meta.n:1;
  if(n===0) return '';
  const inputType = type==='number'?'number' : type==='date'?'date':'text';
  if(n===2){
    const a=type==='number'?(val?.min??''):(val?.start??''); const b=type==='number'?(val?.max??''):(val?.end??'');
    return `<input class="f-v1" type="${inputType}" value="${esc(a)}" placeholder="Min" style="flex:1;min-width:0">
            <input class="f-v2" type="${inputType}" value="${esc(b)}" placeholder="Max" style="flex:1;min-width:0">`;
  }
  if(n==='list'){ return `<input class="f-v1" type="text" value="${esc(Array.isArray(val)?val.join(','):'')}" placeholder="virgülle ayır" style="flex:2;min-width:0">`; }
  return `<input class="f-v1" type="${inputType}" value="${esc(val??'')}" style="flex:2;min-width:0">`;
}
function satirDegerOku(satirEl, type, op){
  const meta=(OPS[type]||[]).find(o=>o.op===op); const n=meta?meta.n:1;
  if(n===0) return null;
  const v1=satirEl.querySelector('.f-v1')?.value ?? '';
  if(n===2){ const v2=satirEl.querySelector('.f-v2')?.value ?? ''; return type==='number'?{min:v1,max:v2}:{start:v1,end:v2}; }
  if(n==='list') return v1.split(',').map(s=>s.trim()).filter(Boolean);
  return v1;
}

function panelOlustur(container, alanlar, aktif, onDegisim){
  const alanOpt = alanlar.map(a=>`<option value="${a.field}">${esc(a.label)}</option>`).join('');
  container.innerHTML = `
    <div class="f-satir" style="display:flex;gap:6px;align-items:center;flex-wrap:wrap;margin-bottom:8px">
      <select class="f-alan" style="flex:1;min-width:120px">${alanOpt}</select>
      <select class="f-op" style="flex:1;min-width:120px"></select>
      <span class="f-deg" style="display:flex;gap:6px;flex:2;min-width:120px"></span>
      <button class="f-ekle" style="background:var(--primary);color:#fff;border:none;border-radius:6px;padding:8px 12px;font-weight:700;cursor:pointer">+ Ekle</button>
    </div>`;
  const alanSel=container.querySelector('.f-alan'), opSel=container.querySelector('.f-op'), degEl=container.querySelector('.f-deg');
  function alanTip(){ return alanlar.find(a=>a.field===alanSel.value)?.type || 'text'; }
  function opDoldur(){ const t=alanTip(); opSel.innerHTML=(OPS[t]||[]).map(o=>`<option value="${o.op}">${esc(o.label)}</option>`).join(''); }
  function degDoldur(){ degEl.innerHTML=girisWidget(alanTip(), opSel.value, null); }
  alanSel.onchange=()=>{ opDoldur(); degDoldur(); };
  opSel.onchange=degDoldur;
  opDoldur(); degDoldur();
  container.querySelector('.f-ekle').onclick=()=>{
    const alan=alanlar.find(a=>a.field===alanSel.value); const type=alan.type, op=opSel.value;
    const value=satirDegerOku(container.querySelector('.f-satir'), type, op);
    aktif.push({field:alan.field, type, operator:op, value});
    degDoldur();
    onDegisim(aktif);
  };
}

window.Filtre = { OPS, filtreleUygula, panelOlustur, etiketleriCiz, kayitliGetir, kayitliKaydet, kayitliSil };
})();
```

- [ ] **Adım 2: Söz-dizimi kontrolü**
Tarayıcı konsolunda dosya yüklendikten sonra `typeof Filtre.filtreleUygula === 'function'` → true. (Bu Task 3 entegrasyonunda görülür; burada sadece dosya yazılır.)

- [ ] **Adım 3: Commit**
```bash
git add filtre.js
git commit -m "feat(filtre): merkezi filtre.js (operatorler + client predicate + panel + etiket + kayitli CRUD)"
```

---

### Task 3: Stok-takip pilot entegrasyonu

**Files:**
- Modify: `stok-takip.html` (`<head>` script; stok görünümü üstüne buton+panel; `renderStok` içine filtre; kaydet/yükle)

**Interfaces:**
- Consumes: `Filtre.*` (Task 2); `db.stok[aktifDepoId]`, `db.abcSiniflari`, `getStokDurum` (mevcut).
- Produces: `STOK_FILTRE_ALANLARI`, `aktifStokFiltreleri`, `stokFiltrePaneliAcKapa()`, `stokFiltreUygula()`.

- [ ] **Adım 1: filtre.js'i yükle** — `stok-takip.html` `<head>` içinde diğer script'lerin yanına:
```html
<script src="filtre.js"></script>
```

- [ ] **Adım 2: Alan config + state** — stok script'inde (renderStok'tan önce) ekle:
```javascript
const STOK_FILTRE_ALANLARI = [
  { field:'urunAd', label:'Ürün Adı', type:'text' },
  { field:'lnKod', label:'Kalem Kodu (LN)', type:'text' },
  { field:'miktar', label:'Miktar', type:'number' },
  { field:'kategori', label:'Kategori', type:'multi_select',
    getValue:s=> (s.lnKod||'').slice(0,5) },
  { field:'abc', label:'ABC Sınıfı', type:'multi_select',
    getValue:s=> db.abcSiniflari[s.lnKod]||'C' },
  { field:'durum', label:'Stok Durumu', type:'multi_select',
    getValue:s=> getStokDurum(s.lnKod, s.miktar) },
];
let aktifStokFiltreleri = [];
```

- [ ] **Adım 3: Buton + panel + etiket kutuları** — `#stok-search` input'unun hemen ALTINA (satır ~153 civarı) ekle:
```html
      <button onclick="stokFiltrePaneliAcKapa()" style="margin-top:6px;background:#eef2ff;color:#3730a3;border:1.5px solid #c7d2fe;border-radius:8px;padding:8px 12px;font-size:12px;font-weight:700;cursor:pointer">🔎 Gelişmiş Filtre</button>
      <div id="stok-filtre-panel" style="display:none;background:#fff;border:1px solid var(--gray-200);border-radius:8px;padding:10px;margin-top:8px"></div>
      <div id="stok-filtre-etiket" style="margin-top:6px"></div>
```

- [ ] **Adım 4: Panel aç/kapa + uygula fonksiyonları** — script'e ekle:
```javascript
function stokFiltreYenidenCiz(){
  Filtre.etiketleriCiz(document.getElementById('stok-filtre-etiket'), aktifStokFiltreleri, STOK_FILTRE_ALANLARI, (i)=>{
    if(i===-1) aktifStokFiltreleri=[]; else aktifStokFiltreleri.splice(i,1);
    stokFiltreYenidenCiz(); renderStok();
  });
}
function stokFiltrePaneliAcKapa(){
  const p=document.getElementById('stok-filtre-panel');
  if(p.style.display==='none'){
    p.style.display='block';
    Filtre.panelOlustur(p, STOK_FILTRE_ALANLARI, aktifStokFiltreleri, ()=>{ stokFiltreYenidenCiz(); renderStok(); });
  } else { p.style.display='none'; }
}
```

- [ ] **Adım 5: renderStok'a filtreyi bağla** — `renderStok` içinde mevcut `let filtered=items.filter(...)` bloğundan HEMEN SONRA, `filtered.sort(...)`'tan ÖNCE:
```javascript
  filtered = Filtre.filtreleUygula(filtered, aktifStokFiltreleri, STOK_FILTRE_ALANLARI);
```
Ve `renderStok` sonuna (return'lerden önce güvenli bir yerde, örn. stats sonrası) `stokFiltreYenidenCiz();` çağrısı yoksa init'te bir kez çağır.

- [ ] **Adım 6: Kaydet/Yükle butonları** — panel HTML'inin altına iki buton + basit prompt akışı:
```javascript
// panelOlustur sonrası panele eklenecek — Adım 4'teki stokFiltrePaneliAcKapa içine, panelOlustur'dan sonra:
p.insertAdjacentHTML('beforeend', `<div style="display:flex;gap:6px;margin-top:8px">
  <button onclick="stokFiltreKaydet()" style="flex:1;background:#fff;border:1.5px solid var(--primary);color:var(--primary);border-radius:6px;padding:8px;font-weight:700;cursor:pointer">💾 Kaydet</button>
  <button onclick="stokFiltreYukle()" style="flex:1;background:#fff;border:1.5px solid var(--gray-300);border-radius:6px;padding:8px;font-weight:700;cursor:pointer">📂 Yükle</button>
</div>`);
```
```javascript
async function stokFiltreKaydet(){
  if(!aktifStokFiltreleri.length){toast('Önce filtre ekle');return;}
  const ad=prompt('Filtre adı:'); if(!ad)return;
  try{ await Filtre.kayitliKaydet('stok-takip', ad, aktifStokFiltreleri, false); toast('✅ Kaydedildi'); }
  catch(e){ toast('❌ Kaydedilemedi'); }
}
async function stokFiltreYukle(){
  const liste=await Filtre.kayitliGetir('stok-takip');
  if(!liste.length){toast('Kayıtlı filtre yok');return;}
  const sec=prompt('Yüklenecek filtre:\n'+liste.map((f,i)=>`${i+1}) ${f.ad}${f.paylasimli?' (ortak)':''}`).join('\n')+'\n\nNumara:');
  const idx=parseInt(sec,10)-1; if(isNaN(idx)||!liste[idx])return;
  aktifStokFiltreleri = liste[idx].filtreler || [];
  stokFiltreYenidenCiz(); renderStok(); toast('✅ Yüklendi');
}
```
(`toast` bu dosyada `showToast` olabilir — Adım öncesi `grep toast stok-takip.html` ile doğrula; yoksa `showToast` kullan.)

- [ ] **Adım 7: Uygulamada elle test** (Ctrl+Shift+R sonrası)
- "🔎 Gelişmiş Filtre" → panel açılır.
- "Ürün Adı / içerir / SU" ekle → liste süzülür, etiket görünür, ✕ ile kalkar.
- "Miktar / büyüktür / 10" + "Ürün Adı içerir SU" → ikisi birlikte (VE).
- "ABC / listede biri / A" (çoklu) çalışır.
- Mevcut arama kutusu + Kritik/Uyarı/kategori sekmeleri hâlâ çalışır (gelişmiş filtre üstüne biner).
- Kaydet → Yükle → aynı filtre geri gelir.

- [ ] **Adım 8: Commit + push**
```bash
git add stok-takip.html
git commit -m "feat(filtre): stok-takip gelismis filtre pilotu (panel + filtreleUygula + kaydet/yukle)"
git push origin main
```

---

### Task 4: Uçtan uca doğrulama

- [ ] **Adım 1: Türkçe metin** — "şeker" içerir "SEK" → eşleşir; "şeker" ≠ "seker" (ş korunur); "İ/ı" doğru.
- [ ] **Adım 2: Sayı between** — Miktar 10–50 arası; sıfır filtresi.
- [ ] **Adım 3: Çoklu VE** — üç filtre birlikte doğru süzer.
- [ ] **Adım 4: Kayıtlı filtre RLS** — kaydet/yükle çalışır; (mümkünse) başka kullanıcının filtresi görünmez.
- [ ] **Adım 5: Regresyon** — mevcut arama/sekmeler/stok giriş-çıkış BOZULMAZ.
- [ ] **Adım 6: Memory'ye işle** (özellik + pilot kanıtı).

---

## Self-Review
- Spec kapsamı: operatörler (Task 2 OPS), client predicate (filtreleUygula), panel/etiket (Task 2 UI), kayıtlı filtre+RLS (Task 1+2), stok pilot (Task 3), Türkçe (norm), güvenlik (client predicate + RLS) — hepsi karşılanıyor. Sütun-header ikonları + VEYA/grup + server-side bilerek kapsam dışı (spec ile uyumlu).
- Placeholder yok: SQL + filtre.js + entegrasyon somut. DİKKAT (execution'da doğrula): `toast` vs `showToast` ad; `CU.id`/oturum kullanıcı id alanı; renderStok içindeki tam ekleme noktası (mevcut `filtered` değişken adı).
- Tip tutarlılığı: filtre modeli `{field,type,operator,value}` her yerde aynı; `filtreleUygula(rows,filtreler,alanlar)` imzası Task 2↔3 tutarlı; alan config `{field,label,type,getValue?}` tutarlı.
