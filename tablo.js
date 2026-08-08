// tablo.js — Excel-benzeri tablo görünümü + sütun-altı operatör filtresi.
// filtre.js üzerine kurulu, ekrandan bağımsız. window.Tablo altında API sunar.
//
// Desen (stok-takip / sipariş-takip / giriş-kayıtları ekranlarında kanıtlandı):
//   üstte tek başlık satırı → hemen altında her sütun için [operatör ▾][değer]
//   filtre satırı → altta veri satırları. Yazarken anında süzer; yalnız tbody
//   yenilendiği için input odağı KAYBOLMAZ. Sıralama okları YOK (istenmedi).
//
// Kullanım:
//   const t = Tablo.olustur({
//     container: 'liste-div-id',
//     kolonlar: [{key,label,type,get}],       // type: text | number | date
//     veri: () => diziDondurenFonksiyon(),    // süzülmemiş ham satırlar
//     satirTikla: (row) => {...},             // opsiyonel
//     bosMesaj: 'Kayıt bulunamadı',           // opsiyonel
//     etiketKapsayici: 'etiket-div-id',       // opsiyonel (aktif filtre rozetleri)
//     onDegisim: (sayi, toplam) => {...}      // opsiyonel (sayaç güncelleme)
//   });
//   t.ciz();            // tam çizim (başlık + filtre satırı + gövde)
//   t.filtreler         // aktif filtre dizisi (dışarıdan okunabilir)
//   t.filtreliVeri()    // süzülmüş satırlar (Excel export vb. için)
(function(){
'use strict';

// filtre.js OPS anahtarlarına eşlenen, kolay seçilir semboller
const SUTUN_OPS = {
  text:   [['contains','içerir'],['equals','='],['not_equals','≠'],['starts','başlar']],
  number: [['eq','='],['ne','≠'],['gt','>'],['gte','≥'],['lt','<'],['lte','≤']],
  date:   [['on','='],['before','<'],['after','>']],
};

function esc(s){
  return (typeof escapeHtml === 'function')
    ? escapeHtml(String(s ?? ''))
    : String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
}

function hucreBicim(type, v){
  if(v==null || v==='') return '—';
  if(type==='date'){ const d=new Date(v); return isNaN(d) ? '—' : d.toLocaleDateString('tr-TR'); }
  if(type==='number'){ return (Math.round((parseFloat(v)||0)*100)/100).toLocaleString('tr-TR'); }
  return String(v);
}

let _sayac = 0;

function olustur(cfg){
  const id = 'tblo' + (++_sayac);
  const kolonlar = cfg.kolonlar || [];
  const alanlar = kolonlar.map(k => ({ field:k.key, label:k.label, type:k.type, getValue:k.get }));
  const bosMesaj = cfg.bosMesaj || 'Kayıt bulunamadı';

  const t = {
    id,
    filtreler: [],
    kolonlar,
    alanlar,
    ciz, tbodyYenile, filtreliVeri, filtreleriTemizle,
  };
  // onchange/oninput global erişebilsin diye kayıt
  (window.__TABLO_KAYIT = window.__TABLO_KAYIT || {})[id] = t;

  function kap(){ return document.getElementById(cfg.container); }

  function filtreliVeri(){
    const rows = (typeof cfg.veri === 'function' ? cfg.veri() : cfg.veri) || [];
    return (typeof Filtre !== 'undefined')
      ? Filtre.filtreleUygula(rows, t.filtreler, alanlar)
      : rows;
  }

  function basHTML(){
    return kolonlar.map(k =>
      `<th style="position:sticky;top:0;background:var(--primary);color:#fff;padding:6px 8px;font-size:11px;white-space:nowrap;z-index:2">${esc(k.label)}</th>`
    ).join('');
  }

  function filtreSatiriHTML(){
    return kolonlar.map(k => {
      const ops = SUTUN_OPS[k.type] || SUTUN_OPS.text;
      const mevcut = t.filtreler.find(f => f.field === k.key);
      const opsHtml = ops.map(([op,sim]) =>
        `<option value="${op}"${mevcut && mevcut.operator===op ? ' selected' : ''}>${sim}</option>`).join('');
      const inputType = k.type==='number' ? 'number' : (k.type==='date' ? 'date' : 'text');
      const val = mevcut ? esc(String(mevcut.value ?? '')) : '';
      const cagri = `Tablo._degis('${id}','${k.key}','${k.type}')`;
      return `<th data-fcol="${k.key}" style="background:#eef2ff;padding:4px 6px">
        <div style="display:flex;gap:3px;align-items:center">
          <select onchange="${cagri}" style="border:1px solid #c7d2fe;border-radius:5px;padding:2px 3px;font-size:12px;font-weight:800;background:#fff;cursor:pointer">${opsHtml}</select>
          <input type="${inputType}" value="${val}" oninput="${cagri}" placeholder="filtre" style="width:100%;min-width:44px;border:1px solid #c7d2fe;border-radius:5px;padding:2px 4px;font-size:11px">
        </div></th>`;
    }).join('');
  }

  function bosSatir(){
    return `<tr><td colspan="${kolonlar.length}" style="padding:24px;text-align:center;color:var(--gray-400)">${esc(bosMesaj)}</td></tr>`;
  }

  function govdeHTML(rows){
    return rows.map((row,i) => {
      const tik = cfg.satirTikla ? ` onclick="Tablo._tik('${id}',${i})" style="cursor:pointer"` : '';
      return `<tr${tik}>` + kolonlar.map(k =>
        `<td style="padding:6px 8px;border-top:1px solid var(--gray-200);font-size:11.5px;white-space:nowrap">${esc(hucreBicim(k.type, k.get(row)))}</td>`
      ).join('') + `</tr>`;
    }).join('');
  }

  function etiketleriCiz(){
    if(!cfg.etiketKapsayici || typeof Filtre === 'undefined') return;
    const el = document.getElementById(cfg.etiketKapsayici); if(!el) return;
    Filtre.etiketleriCiz(el, t.filtreler, alanlar, (i) => {
      if(i === -1) t.filtreler = []; else t.filtreler.splice(i,1);
      ciz();
    });
  }

  function ciz(){
    const c = kap(); if(!c) return;
    const rows = filtreliVeri();
    t._sonRows = rows;
    c.innerHTML = `<div style="overflow-x:auto"><table style="width:100%;border-collapse:collapse">`+
      `<thead><tr>${basHTML()}</tr><tr>${filtreSatiriHTML()}</tr></thead>`+
      `<tbody>${rows.length ? govdeHTML(rows) : bosSatir()}</tbody></table></div>`;
    etiketleriCiz();
    if(cfg.onDegisim) cfg.onDegisim(rows.length, ((typeof cfg.veri==='function'?cfg.veri():cfg.veri)||[]).length);
  }

  // Filtre değişince yalnız tbody yenilenir → input odağı korunur
  function tbodyYenile(){
    const c = kap(); if(!c) return;
    const tb = c.querySelector('tbody'); if(!tb){ ciz(); return; }
    const rows = filtreliVeri();
    t._sonRows = rows;
    tb.innerHTML = rows.length ? govdeHTML(rows) : bosSatir();
    etiketleriCiz();
    if(cfg.onDegisim) cfg.onDegisim(rows.length, ((typeof cfg.veri==='function'?cfg.veri():cfg.veri)||[]).length);
  }

  function filtreleriTemizle(){ t.filtreler = []; ciz(); }

  t._cfg = cfg;
  return t;
}

// Inline handler köprüleri
function _degis(id, field, ftype){
  const t = (window.__TABLO_KAYIT||{})[id]; if(!t) return;
  const c = document.getElementById(t._cfg.container); if(!c) return;
  const cell = c.querySelector('[data-fcol="'+field+'"]'); if(!cell) return;
  const op = cell.querySelector('select').value;
  const inp = cell.querySelector('input');
  const raw = inp ? inp.value : '';
  t.filtreler = t.filtreler.filter(f => f.field !== field);
  if(raw !== '' && raw != null) t.filtreler.push({ field, type:ftype, operator:op, value:raw });
  t.tbodyYenile();
}

function _tik(id, i){
  const t = (window.__TABLO_KAYIT||{})[id]; if(!t) return;
  const row = (t._sonRows||[])[i];
  if(row && t._cfg.satirTikla) t._cfg.satirTikla(row);
}

window.Tablo = { olustur, SUTUN_OPS, hucreBicim, _degis, _tik };
})();
