// otel-config.js — Araz ERP müşteriye özel kurulum sabitleri.
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

// Bar/Restoran depoları — kod → ad + tip + otel. Bar modülünde masa/garson bu isimleri gösterir.
// otel: hangi otele ait (810 Club Manavgat / 811 Resort Sorgun) — masa eklemede depo listesi otele göre filtrelenir.
const BAR_DEPOLARI = {
  // 810 — Ali Bey Club Manavgat
  'CSM201':{ad:'ALIBEY RESTAURANT',tip:'Restoran',otel:'810'}, 'CSM202':{ad:'PARK RESTAURANT',tip:'Restoran',otel:'810'},
  'CSM204':{ad:'SAHIL RESTAURANT',tip:'Restoran',otel:'810'}, 'CSM205':{ad:'AQUA RESTAURANT',tip:'Restoran',otel:'810'},
  'CSM206':{ad:'KIYI RESTAURANT',tip:'Restoran',otel:'810'},
  'CSM301':{ad:'TURK KAHVESI',tip:'Bar',otel:'810'}, 'CSM302':{ad:'CARDAK',tip:'Bar',otel:'810'}, 'CSM303':{ad:'TALVAR',tip:'Bar',otel:'810'},
  'CSM304':{ad:'POOL',tip:'Bar',otel:'810'}, 'CSM305':{ad:"ALI'S PUB",tip:'Bar',otel:'810'}, 'CSM306':{ad:'TENIS BAR',tip:'Bar',otel:'810'},
  'CSM307':{ad:'KONAK',tip:'Bar',otel:'810'}, 'CSM308':{ad:'KARAGOZ',tip:'Bar',otel:'810'}, 'CSM310':{ad:'ILICA BAR',tip:'Bar',otel:'810'},
  'CSM311':{ad:'HARLEK',tip:'Bar',otel:'810'}, 'CSM312':{ad:'HISAR',tip:'Bar',otel:'810'}, 'CSM313':{ad:'YONCALI',tip:'Bar',otel:'810'},
  'CSM314':{ad:'FRIG BEACH BAR',tip:'Bar',otel:'810'}, 'CSM315':{ad:'PAVILLION BAR',tip:'Bar',otel:'810'}, 'CSM316':{ad:'LOBBY BAR',tip:'Bar',otel:'810'},
  'CSM317':{ad:'PARK TURK KAHVESI',tip:'Bar',otel:'810'}, 'CSM318':{ad:'SARAP VE BIRA EVI',tip:'Bar',otel:'810'},
  // 811 — Ali Bey Resort Sorgun
  'RSM201':{ad:'ALA RESTAURANT',tip:'Restoran',otel:'811'}, 'RSM202':{ad:'RANA RESTAURANT',tip:'Restoran',otel:'811'},
  'RSM203':{ad:'MEHTABE RESTAURANT',tip:'Restoran',otel:'811'}, 'RSM204':{ad:'KEYFI SEFA RESTAURANT',tip:'Restoran',otel:'811'},
  'RSM205':{ad:'KAIGAN SUSHI CORNER',tip:'Restoran',otel:'811'}, 'RSM206':{ad:'KAIGAN TEPPANYAKI A LA CARTE',tip:'Restoran',otel:'811'},
  'RSM207':{ad:'MEHTABE GRILL',tip:'Restoran',otel:'811'}, 'RSM208':{ad:'MEHTABE FISH',tip:'Restoran',otel:'811'},
  'RSM301':{ad:'PEYMANE BAR',tip:'Bar',otel:'811'}, 'RSM302':{ad:'NAZENDE CAFE',tip:'Bar',otel:'811'},
  'RSM303':{ad:'RUMI BAR',tip:'Bar',otel:'811'}, 'RSM304':{ad:'FERASE ALIS PUB',tip:'Bar',otel:'811'},
  'RSM305':{ad:'ENDAME BAR',tip:'Bar',otel:'811'}, 'RSM306':{ad:'LOBBY BAR',tip:'Bar',otel:'811'},
  'RSM307':{ad:'TENIS BAR',tip:'Bar',otel:'811'}, 'RSM308':{ad:'ODA SERVISI',tip:'Bar',otel:'811'},
  'RSM309':{ad:'BEACH BAR',tip:'Bar',otel:'811'}
};
// Depo kodu ERP genelinde otel-önekli tutulur (ör. '810_CSM302'). depoAdi hem önekli
// hem ham ('CSM302') formu çözer: ilk '_' sonrasını bar kodu kabul edip BAR_DEPOLARI'ye bakar.
function depoAdi(kod){
  if(!kod) return '—';
  const i=String(kod).indexOf('_');
  const bar=i>=0 ? String(kod).slice(i+1) : kod;
  return (BAR_DEPOLARI[bar] && BAR_DEPOLARI[bar].ad) ? BAR_DEPOLARI[bar].ad : kod;
}
