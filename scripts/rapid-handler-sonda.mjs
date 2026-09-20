// rapid-handler DAVRANIS SONDASI — SALT OKUMA
// ---------------------------------------------------------------------------
// NEDEN: canli `rapid-handler` repodaki surum degil (canli ping v=bolge1, repo
// v=anon3). Kaynagi indirmek Dashboard/erisim belirteci gerektiriyor. Bu betik,
// kaynak elde olmadan da korunmasi gereken DAVRANIS SOZLESMESINI olcer ve
// parmak izi olarak kaydeder. Birlesik surum izole ortamda ayni sondadan
// gecirilir; fark cikarsa birlestirme davranisi bozmus demektir.
//
// GUVENLIK: yalnizca YAZMAYAN yollar denenir — ping, gecersiz/eksik JWT, bozuk
// JSON, yanlis metot, OPTIONS. 'ekle' ve 'durum' eylemleri (yazan yollar) JWT
// gerektirir ve BILEREK denenmez. Sirlar bu dosyada yoktur; anon anahtar
// bar-config.js'ten okunur (public-by-design).
//
// KULLANIM:
//   node scripts/rapid-handler-sonda.mjs                 # canli musteri projesi
//   node scripts/rapid-handler-sonda.mjs <taban-url>     # izole ortam
// Cikti: JSON parmak izi (stdout). Karsilastirma icin dosyaya yonlendirin.
import { readFileSync } from 'node:fs';

const taban = process.argv[2] || null;
let url, anon;
if (taban) {
  url = taban.replace(/\/$/, '');
  anon = process.env.SONDA_ANON || 'yerel-test';
} else {
  const cfg = readFileSync(new URL('../bar-config.js', import.meta.url), 'utf8');
  url = /const CUSTOMER_SB_URL = '([^']+)'/.exec(cfg)[1];
  anon = /const CUSTOMER_ANON_KEY = '([^']+)'/.exec(cfg)[1];
}
const uc = url + '/functions/v1/rapid-handler';

const bas = { apikey: anon, Authorization: 'Bearer ' + anon, 'Content-Type': 'application/json' };

// Her sonda: [ad, fetch secenekleri]. Hicbiri yazmaz.
const sondalar = [
  ['ping',            { method: 'POST', headers: bas, body: '{"action":"ping"}' }],
  ['ping_anonlu',     { method: 'POST', headers: bas, body: '{"action":"ping","anon":"xxxxx"}' }],
  ['jwt_yok',         { method: 'POST', headers: bas, body: '{"action":"liste"}' }],
  ['jwt_gecersiz',    { method: 'POST', headers: bas, body: '{"action":"liste","jwt":"gecersiz.jwt.dizisi"}' }],
  ['eylem_yok',       { method: 'POST', headers: bas, body: '{}' }],
  ['bilinmeyen_eylem',{ method: 'POST', headers: bas, body: '{"action":"yok-boyle-bir-eylem","jwt":"gecersiz.jwt.dizisi"}' }],
  ['bozuk_json',      { method: 'POST', headers: bas, body: 'bozuk-json' }],
  ['get_metodu',      { method: 'GET',  headers: bas }],
  ['options',         { method: 'OPTIONS', headers: { ...bas, 'Access-Control-Request-Method': 'POST' } }],
];

const sonuc = { uc, zaman: new Date().toISOString(), sondalar: {} };
for (const [ad, sec] of sondalar) {
  try {
    const r = await fetch(uc, { ...sec, signal: AbortSignal.timeout(25000) });
    const metin = (await r.text()).slice(0, 400);
    sonuc.sondalar[ad] = {
      http: r.status,
      cors: r.headers.get('access-control-allow-origin') || null,
      govde: metin,
    };
  } catch (e) {
    sonuc.sondalar[ad] = { hata: String(e && e.message || e) };
  }
}
console.log(JSON.stringify(sonuc, null, 2));
