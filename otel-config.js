// otel-config.js — Gürok ERP müşteriye özel kurulum sabitleri.
// Yeni bir müşteri kurulumunda SADECE bu dosya düzenlenir, başka hiçbir
// dosyaya dokunulmaz. auth-guard.js -> supabase-config.js -> otel-config.js
// -> ortak.js sırasında, senkron olarak yüklenir.

const OTEL_ISIMLERI = {'810':'Ali Bey Club Manavgat','811':'Ali Bey Resort Sorgun'};
const OTEL_KISA = {'810':'Club','811':'Resort'};
const OTEL_TICARI_UNVAN = {'810':'GUROK TUR MAD.A.S. (CLUB MANAVGAT)','811':'GUROK TUR MAD.A.S. (RESORT SORGUN)'};
const GRUP_ADI = 'Gürok Turizm Grubu';
const DAHILI_EMAIL_DOMAIN = 'gurok.internal';
const MERKEZI_DEPO = {'810':'100','811':'300'};

function merkeziDepoKodu(otelId){ return MERKEZI_DEPO[otelId] || '100'; }
function otelFromDepoId(depoId){ const i=(depoId||'').indexOf('_'); return i>=0 ? depoId.slice(0,i) : '810'; }

// Bar/Restoran depoları — kod → ad + tip. Bar modülünde masa/garson bu isimleri gösterir.
const BAR_DEPOLARI = {
  'CSM201':{ad:'ALIBEY RESTAURANT',tip:'Restoran'}, 'CSM202':{ad:'PARK RESTAURANT',tip:'Restoran'},
  'CSM204':{ad:'SAHIL RESTAURANT',tip:'Restoran'}, 'CSM205':{ad:'AQUA RESTAURANT',tip:'Restoran'},
  'CSM206':{ad:'KIYI RESTAURANT',tip:'Restoran'},
  'CSM301':{ad:'TURK KAHVESI',tip:'Bar'}, 'CSM302':{ad:'CARDAK',tip:'Bar'}, 'CSM303':{ad:'TALVAR',tip:'Bar'},
  'CSM304':{ad:'POOL',tip:'Bar'}, 'CSM305':{ad:"ALI'S PUB",tip:'Bar'}, 'CSM306':{ad:'TENIS BAR',tip:'Bar'},
  'CSM307':{ad:'KONAK',tip:'Bar'}, 'CSM308':{ad:'KARAGOZ',tip:'Bar'}, 'CSM310':{ad:'ILICA BAR',tip:'Bar'},
  'CSM311':{ad:'HARLEK',tip:'Bar'}, 'CSM312':{ad:'HISAR',tip:'Bar'}, 'CSM313':{ad:'YONCALI',tip:'Bar'},
  'CSM314':{ad:'FRIG BEACH BAR',tip:'Bar'}, 'CSM315':{ad:'PAVILLION BAR',tip:'Bar'}, 'CSM316':{ad:'LOBBY BAR',tip:'Bar'},
  'CSM317':{ad:'PARK TURK KAHVESI',tip:'Bar'}, 'CSM318':{ad:'SARAP VE BIRA EVI',tip:'Bar'}
};
// Depo kodu ERP genelinde otel-önekli tutulur (ör. '810_CSM302'). depoAdi hem önekli
// hem ham ('CSM302') formu çözer: ilk '_' sonrasını bar kodu kabul edip BAR_DEPOLARI'ye bakar.
function depoAdi(kod){
  if(!kod) return '—';
  const i=String(kod).indexOf('_');
  const bar=i>=0 ? String(kod).slice(i+1) : kod;
  return (BAR_DEPOLARI[bar] && BAR_DEPOLARI[bar].ad) ? BAR_DEPOLARI[bar].ad : kod;
}
