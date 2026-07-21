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
