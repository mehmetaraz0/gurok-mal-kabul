// ortak.js — Gürok ERP paylaşılan UI yardımcıları (sLD/hLD/toast/escapeHtml/
// round2/kModal/aModal) ve XLSX kütüphane yükleyici. Sayfalar bunu <head>
// içinde auth-guard.js'den SONRA, senkron olarak yükler.
//
// Sadece birden fazla dosyada byte-byte doğrulanmış identik fonksiyonlar
// buraya taşınır — fmt() (dosyalar arası ondalık basamak farklı) ve farklı
// imzalı toast()/auditLogYaz varyantları kasıtlı olarak burada DEĞİL.

function sLD(){document.getElementById('ld').classList.add('show');}
function hLD(){document.getElementById('ld').classList.remove('show');}
// Mesaj bir emoji ile başlıyorsa emoji metinden çıkarılır, yerine renkli
// sol kenarlık kullanılır (durum hâlâ tek bakışta ayırt edilebiliyor,
// ama emoji karakteri görünmüyor). Bilinmeyen emoji nötr griyle gösterilir.
const TOAST_RENK={
  '✅':'var(--success)','❌':'var(--danger)','⚠':'var(--warning)','⏳':'var(--gray-500)',
  '🗑':'var(--danger)','📦':'var(--success)','📤':'var(--success)','📥':'var(--success)',
  '🔄':'var(--primary-light)','✏':'var(--primary-light)','👁':'var(--gray-500)','⚡':'var(--warning)'
};
function toast(msg,d=2500){
  const t=document.getElementById('toast');
  const m=String(msg).match(/^([\u{1F300}-\u{1FAFF}☀-➿])️?\s*(.*)$/su);
  t.textContent=m?m[2]:msg;
  t.style.borderLeft=m?('4px solid '+(TOAST_RENK[m[1]]||'var(--gray-400)')):'';
  t.style.paddingLeft=m?'16px':'20px';
  t.classList.add('show');
  setTimeout(()=>t.classList.remove('show'),d);
}
function escapeHtml(s){return String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));}
function round2(n){return Math.round(((parseFloat(n)||0)+Number.EPSILON)*100)/100;}
function kModal(id){document.getElementById(id).classList.remove('open');}
function aModal(id){document.getElementById(id).classList.add('open');}

// 13 yerde tekrarlanan "XLSX yüklü değilse CDN'den yükle" bloğunun ortak hali.
async function loadXlsxLib(){
  if(typeof XLSX!=='undefined')return;
  await new Promise(r=>{
    const s=document.createElement('script');
    s.src='https://cdn.jsdelivr.net/npm/xlsx-js-style@1.2.0/dist/xlsx.bundle.js';
    s.onload=r;
    document.head.appendChild(s);
  });
}

// Birim dönüşüm sistemi — ürün başına opsiyonel büyük birim/çarpan gösterimi.
// Sadece raporlama/gösterim amaçlı; mal kabul/stok giriş akışlarını etkilemez.
// Harita boşsa veya ürünün kaydı yoksa '' döner (sessiz, katmanlı özellik).
let BIRIM_DONUSUM_HARITASI={};
async function birimDonusumHaritasiYukle(){
  try{
    const r=await fetch(SB_URL+'/rest/v1/urun_birim_donusum?select=urun_kodu,buyuk_birim,carpan&silindi=eq.false',{headers:SB_HEADERS});
    if(!r.ok)return;
    (await r.json()).forEach(row=>{BIRIM_DONUSUM_HARITASI[row.urun_kodu]={buyuk_birim:row.buyuk_birim,carpan:parseFloat(row.carpan)};});
  }catch(e){}
}
function birimDonusumEtiketi(urunKodu,miktar){
  const d=BIRIM_DONUSUM_HARITASI[urunKodu];
  if(!d||!d.carpan)return'';
  const m=parseFloat(miktar)||0;
  return`≈${(m/d.carpan).toFixed(2)} ${d.buyuk_birim}`;
}

// UTC tuzağı: new Date().toISOString().split('T')[0] Türkiye saatinde 00:00-03:00
// arasında DÜNÜN tarihini döndürür (ISO string UTC'dir). DB'ye yazılan işlem
// tarihleri için her zaman bu YEREL tarih yardımcısını kullan.
function bugunTarih(){
  const d=new Date();
  return d.getFullYear()+'-'+String(d.getMonth()+1).padStart(2,'0')+'-'+String(d.getDate()).padStart(2,'0');
}
