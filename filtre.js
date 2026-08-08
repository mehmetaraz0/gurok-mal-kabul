// filtre.js — Merkezi gelişmiş filtre altyapısı (client-predicate, VE-only v1, Türkçe-duyarlı).
// Ekrandan bağımsız. window.Filtre altında API sunar.
// Tasarım: docs/superpowers/specs/2026-08-04-gelismis-filtreleme-design.md
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
  if(op==='on'){ const t=tarihParse(v); return !!t && gunBasi(t).getTime()===g.getTime(); }
  if(op==='before'){ const t=tarihParse(v); return !!t && g < gunBasi(t); }
  if(op==='after'){ const t=tarihParse(v); return !!t && g > gunBasi(t); }
  if(op==='between'){ const s=tarihParse(v&&v.start), e=tarihParse(v&&v.end); return !!(s&&e) && g>=gunBasi(s) && g<=gunBasi(e); }
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

function hucre(row, alan){ return alan && alan.getValue ? alan.getValue(row) : (row ? row[alan ? alan.field : undefined] : undefined); }

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

// ---- Oturum kullanıcı id (RLS insert için) — typeof-güvenli ----
function kullaniciId(){
  try{ if(typeof CU!=='undefined' && CU && CU.id) return CU.id; }catch(e){}
  try{ if(typeof OTURUM_KULLANICI!=='undefined' && OTURUM_KULLANICI && OTURUM_KULLANICI.id) return OTURUM_KULLANICI.id; }catch(e){}
  try{ if(typeof currentUser!=='undefined' && currentUser && currentUser.id) return currentUser.id; }catch(e){}
  return null;
}

// ---- Kayıtlı filtre CRUD (RLS'li) ----
async function kayitliGetir(ekran){
  try{
    const r=await fetch(SB_URL+'/rest/v1/kayitli_filtreler?ekran=eq.'+encodeURIComponent(ekran)+'&select=*&order=ad',{headers:SB_HEADERS});
    return r.ok ? await r.json() : [];
  }catch(e){ return []; }
}
async function kayitliKaydet(ekran, ad, filtreler, paylasimli){
  const r=await fetch(SB_URL+'/rest/v1/kayitli_filtreler',{method:'POST',headers:{...SB_HEADERS,'Prefer':'return=representation'},
    body:JSON.stringify({kullanici_id:kullaniciId(), ekran, ad, filtreler, paylasimli:!!paylasimli})});
  if(!r.ok) throw new Error(await r.text().catch(()=>'kaydedilemedi'));
  return (await r.json())[0];
}
async function kayitliSil(id){
  const r=await fetch(SB_URL+'/rest/v1/kayitli_filtreler?id=eq.'+id,{method:'DELETE',headers:SB_HEADERS});
  return r.ok;
}

// ---- UI yardımcıları ----
function opLabel(type, op){ const o=(OPS[type]||[]).find(x=>x.op===op); return o?o.label:op; }
function degerMetni(f){
  if(f.value==null) return '';
  if(f.type==='number' && (f.operator==='between'||f.operator==='not_between')) return `${f.value.min}–${f.value.max}`;
  if(f.type==='date' && f.operator==='between') return `${f.value.start}–${f.value.end}`;
  if(Array.isArray(f.value)) return f.value.join(', ');
  return String(f.value);
}
function esc(s){ return String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])); }

// ---- UI: aktif filtre etiketleri (onKaldir(i): i>=0 tek kaldır, -1 tümünü temizle) ----
function etiketleriCiz(container, aktif, alanlar, onKaldir){
  const map={}; (alanlar||[]).forEach(a=>map[a.field]=a);
  if(!aktif || !aktif.length){ container.innerHTML=''; return; }
  container.innerHTML = aktif.map((f,i)=>{
    const lbl=(map[f.field] && map[f.field].label) || f.field;
    const dv=degerMetni(f);
    return `<span style="display:inline-flex;align-items:center;gap:6px;background:#eef2ff;color:#3730a3;border-radius:14px;padding:4px 10px;font-size:11px;font-weight:600;margin:2px">
      ${esc(lbl)}: ${esc(opLabel(f.type,f.operator))}${dv?' '+esc(dv):''}
      <span data-i="${i}" class="filtre-etiket-x" style="cursor:pointer;font-weight:800">✕</span></span>`;
  }).join('') + `<button class="filtre-temizle" style="background:none;border:none;color:#9b1c1c;font-size:11px;font-weight:700;cursor:pointer;margin-left:6px">Tümünü temizle</button>`;
  container.querySelectorAll('.filtre-etiket-x').forEach(x=>x.onclick=()=>onKaldir(parseInt(x.dataset.i,10)));
  const t=container.querySelector('.filtre-temizle'); if(t) t.onclick=()=>onKaldir(-1);
}

// ---- UI: filtre paneli (alan→operatör→değer + Ekle) ----
function girisWidget(type, op, val){
  const meta=(OPS[type]||[]).find(o=>o.op===op);
  const n=meta?meta.n:1;
  if(n===0) return '';
  const inputType = type==='number'?'number' : type==='date'?'date':'text';
  if(n===2){
    const a=type==='number'?((val&&val.min)??''):((val&&val.start)??''); const b=type==='number'?((val&&val.max)??''):((val&&val.end)??'');
    return `<input class="f-v1" type="${inputType}" value="${esc(a)}" placeholder="Min" style="flex:1;min-width:0">
            <input class="f-v2" type="${inputType}" value="${esc(b)}" placeholder="Max" style="flex:1;min-width:0">`;
  }
  if(n==='list'){ return `<input class="f-v1" type="text" value="${esc(Array.isArray(val)?val.join(','):'')}" placeholder="virgülle ayır" style="flex:2;min-width:0">`; }
  return `<input class="f-v1" type="${inputType}" value="${esc(val??'')}" style="flex:2;min-width:0">`;
}
function satirDegerOku(satirEl, type, op){
  const meta=(OPS[type]||[]).find(o=>o.op===op); const n=meta?meta.n:1;
  if(n===0) return null;
  const v1=(satirEl.querySelector('.f-v1') && satirEl.querySelector('.f-v1').value) || '';
  if(n===2){ const v2=(satirEl.querySelector('.f-v2') && satirEl.querySelector('.f-v2').value) || ''; return type==='number'?{min:v1,max:v2}:{start:v1,end:v2}; }
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
  function alanTip(){ const a=alanlar.find(x=>x.field===alanSel.value); return a?a.type:'text'; }
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
