// ortak.js — Araz ERP paylaşılan UI yardımcıları (sLD/hLD/toast/escapeHtml/
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

// GÜVENLİK (pentest 2026-08-09, bulgu [6]): inline olay işleyicisi içindeki
// TEK TIRNAKLI JS string'i İKİ katmanlı bir bağlamdır:
//   onclick="fn('BURASI')"  →  önce HTML attribute çözülür, SONRA JS parse edilir.
// Bu yüzden escapeHtml() TEK BAŞINA YETMEZ (&#39; HTML çözülünce ' olur ve
// string'den çıkılır); ".replace(/'/g,"\\'")" de yetmez (ters bölü enjeksiyonu).
// Doğru sıra: ÖNCE JS-kaçışı (\ ve '), SONRA HTML-kaçışı.
// Kullanım:  onclick="sil('${jsAttrStr(u.kod)}')"
function jsAttrStr(v){
  return escapeHtml(String(v ?? '').replace(/\\/g, '\\\\').replace(/'/g, "\\'"));
}
function round2(n){return Math.round(((parseFloat(n)||0)+Number.EPSILON)*100)/100;}

// ============================================================
// SUNUCUYA YAZMA — SESSİZ HATA BIRAKMAZ
// ============================================================
// SORUN: kod tabanında 60+ yerde `await fetch(..., {method:'POST'})` sonucu HİÇ
// kontrol edilmiyordu. RLS reddi / ağ hatası / 4xx durumunda kayıt gitmiyor ama
// akış devam edip "✅ kaydedildi" diyordu → SESSİZ VERİ KAYBI.
//
// sbYaz() aynı imzayla fetch'in yerine geçer (url, opts) ve yanıtı döndürür —
// akışı DEĞİŞTİRMEZ (throw etmez, mevcut mantık bozulmaz). Başarısızlıkta
// konsola yazar + KALICI kırmızı şerit gösterir. Şerit kalıcıdır çünkü toast
// tek elemanlıdır ve arkadan gelen "✅ kaydedildi" mesajı onu EZER.
async function sbYaz(url, opts, aciklama){
  let r;
  try{
    r = await fetch(url, opts);
  }catch(e){
    console.error('YAZMA HATASI (ağ):', url, e);
    yazmaHatasiGoster(aciklama || 'Kayıt', 'Sunucuya ulaşılamadı: ' + (e && e.message || e));
    throw e;   // ağ hatası zaten mevcut try/catch'lere düşüyordu — davranış korunur
  }
  if(!r.ok){
    const govde = await r.clone().text().catch(()=>'');
    console.error('YAZMA HATASI:', url, r.status, govde);
    yazmaHatasiGoster(aciklama || 'Kayıt', 'HTTP ' + r.status + (govde ? ' — ' + govde.slice(0,200) : ''));
  }
  return r;
}

// Kalıcı hata şeridi — kullanıcı kapatana kadar durur (toast gibi kaybolmaz).
function yazmaHatasiGoster(baslik, detay){
  let el = document.getElementById('yazma-hata-serit');
  if(!el){
    el = document.createElement('div');
    el.id = 'yazma-hata-serit';
    el.style.cssText = 'position:fixed;left:0;right:0;top:0;z-index:10000;background:#9b1c1c;color:#fff;'+
      'padding:10px 44px 10px 14px;font-size:13px;line-height:1.45;box-shadow:0 2px 10px rgba(0,0,0,.3);'+
      'font-family:-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif';
    const kapat = document.createElement('button');
    kapat.textContent = '✕';
    kapat.setAttribute('aria-label','Kapat');
    kapat.style.cssText = 'position:absolute;right:8px;top:6px;background:none;border:none;color:#fff;'+
      'font-size:18px;cursor:pointer;line-height:1';
    kapat.onclick = () => el.remove();
    el.appendChild(kapat);
    const ic = document.createElement('div');
    ic.id = 'yazma-hata-icerik';
    el.appendChild(ic);
    document.body.appendChild(el);
  }
  const ic = document.getElementById('yazma-hata-icerik');
  const satir = document.createElement('div');
  // textContent → XSS yok (sunucu hata gövdesi buraya basılıyor)
  satir.textContent = '⚠️ ' + baslik + ' KAYDEDİLEMEDİ — ' + detay;
  ic.appendChild(satir);
}

// TARİH — YEREL GÜN (Türkiye UTC+3).
// HATA: new Date().toISOString().split('T')[0] UTC gününü verir; saat 00:00–03:00
// arasında girilen kayıt BİR ÖNCEKİ güne yazılıyordu (gece vardiyası/bar kapanışı).
// bugunYerelStr() yerel takvim gününü döndürür. Tarih girişi/varsayılanı, "bugün"
// karşılaştırmaları ve gün damgaları için BUNU kullan.
function bugunYerelStr(){
  const d=new Date();
  return d.getFullYear()+'-'+String(d.getMonth()+1).padStart(2,'0')+'-'+String(d.getDate()).padStart(2,'0');
}
// Belirli bir Date/parse-edilebilir değeri yerel YYYY-MM-DD'ye çevirir.
function yerelTarihStr(t){
  const d=(t instanceof Date)?t:new Date(t);
  if(isNaN(d)) return '';
  return d.getFullYear()+'-'+String(d.getMonth()+1).padStart(2,'0')+'-'+String(d.getDate()).padStart(2,'0');
}
function kModal(id){document.getElementById(id).classList.remove('open');}
function aModal(id){document.getElementById(id).classList.add('open');}

// 13 yerde tekrarlanan "XLSX yüklü değilse CDN'den yükle" bloğunun ortak hali.
async function loadXlsxLib(){
  if(typeof XLSX!=='undefined')return;
  await new Promise(r=>{
    const s=document.createElement('script');
    s.src='https://cdn.jsdelivr.net/npm/xlsx-js-style@1.2.0/dist/xlsx.bundle.js';
    s.integrity='sha384-OUW9euuUyxyHcAhTqbhI+Iyb8LMssXt/cpz0yXhs9UWG2/R/uaWdakx/4cfww7Vb';
    s.crossOrigin='anonymous';
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
