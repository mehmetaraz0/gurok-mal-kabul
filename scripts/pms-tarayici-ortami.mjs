// ===========================================================================
// PMS TARAYICI DOGRULAMA ORTAMI (uretime BAGLANMAZ)
// ===========================================================================
// Gercek ekranlari GERCEK bir tarayicida acabilmek icin:
//   1) izole Docker veritabani + PostgREST (bar-test-ortam ile ayni yol)
//   2) yapay PMS tohumu
//   3) ayni kokenden servis eden kucuk bir HTTP sunucusu:
//        /rest/v1/*  -> PostgREST'e vekillik (CORS sorunu olmasin diye)
//        diger yollar -> depo kokundeki GERCEK dosyalar
//      YALNIZ iki ortam dosyasi test surumuyle degistirilir:
//        auth-guard.js     (oturum/yetki yerine sabit test kullanicisi)
//        supabase-config.js(adres + test JWT'si)
//      Ekran betikleri, HTML ve CSS depodaki dosyalarin AYNISIDIR.
//
// Uretim adresleri ve anahtarlari YUKLENMEZ. Gercek misafir verisi YOKTUR.
// Kullanim: node scripts/pms-tarayici-ortami.mjs   (Ctrl-C ile kapanir)
// ===========================================================================
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { barOrtami, yerelJwt } from './bar-test-ortam.mjs';
import { EK_TOHUM } from './bar-a1-tohum.mjs';
import { PMS, PMS_TOHUM, RESEPSIYON_YETKI } from './pms-akis-tohum.mjs';

const KOK = new URL('..', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const PORT = Number(process.env.PMS_TARAYICI_PORT || 4180);
const O = barOrtami({ ad: 'pms-tarayici', ag: 'pms-tarayici-net' });

const TURLER = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml', '.png': 'image/png', '.ico': 'image/x-icon',
};

const JWT = yerelJwt('authenticated', PMS.RESEPSIYON.sub);

// Test surumu ortam dosyalari — depodaki dosyalar DEGISTIRILMEZ, yalnizca
// bu sunucu onlarin yerine asagidakileri servis eder.
const TEST_DOSYALARI = {
  'supabase-config.js':
    `// TEST SURUMU — izole ortam. Uretim adresi/anahtari YOK.\n` +
    `const SB_URL = '';\n` +
    `const SB_KEY = 'test-anon';\n` +
    `const SB_HEADERS = { apikey: 'test-anon', Authorization: 'Bearer ${JWT}' };\n`,
  'auth-guard.js':
    `// TEST SURUMU — oturum/PIN akisi yerine sabit test kullanicisi.\n` +
    `const __CU = ${JSON.stringify({
      id: PMS.RESEPSIYON.sub, ad: 'Resepsiyon 810', rol: 'muhasebe_calisani',
      otel_id: '810', otelId: '810',
    })};\n` +
    `function requireLogin() { return __CU; }\n` +
    `function requireRole() { return true; }\n` +
    `function oturumAccessTokenGetir() { return ${JSON.stringify(JWT)}; }\n` +
    `async function kullaniciYetkileriGetir() { return ${JSON.stringify(RESEPSIYON_YETKI)}; }\n`,
};

let REST;

function govdeOku(istek) {
  return new Promise((coz) => {
    const p = [];
    istek.on('data', (d) => p.push(d));
    istek.on('end', () => coz(Buffer.concat(p)));
  });
}

async function vekil(istek, yanit) {
  const hedef = REST + istek.url.replace('/rest/v1/', '/');
  const govde = ['GET', 'HEAD'].includes(istek.method) ? undefined : await govdeOku(istek);
  const basliklar = {};
  for (const [k, v] of Object.entries(istek.headers)) {
    if (['host', 'connection', 'content-length', 'origin', 'referer'].includes(k)) continue;
    basliklar[k] = v;
  }
  try {
    const r = await fetch(hedef, { method: istek.method, headers: basliklar, body: govde });
    const metin = await r.text();
    const cikis = {};
    for (const [k, v] of r.headers) if (!['content-encoding', 'transfer-encoding'].includes(k)) cikis[k] = v;
    yanit.writeHead(r.status, cikis);
    yanit.end(metin);
  } catch (e) {
    yanit.writeHead(502, { 'content-type': 'text/plain' });
    yanit.end('vekil hatasi: ' + (e && e.message));
  }
}

function statik(istek, yanit) {
  let yol = decodeURIComponent(istek.url.split('?')[0]);
  if (yol === '/') yol = '/index.html';
  const ad = yol.replace(/^\//, '');

  if (Object.prototype.hasOwnProperty.call(TEST_DOSYALARI, ad)) {
    yanit.writeHead(200, { 'content-type': TURLER['.js'], 'cache-control': 'no-store' });
    yanit.end(TEST_DOSYALARI[ad]);
    return;
  }
  // Depo kokunun DISINA cikilmaz.
  const tam = path.resolve(KOK, ad);
  if (!tam.startsWith(path.resolve(KOK))) { yanit.writeHead(403); yanit.end('disari cikis yok'); return; }
  if (!fs.existsSync(tam) || fs.statSync(tam).isDirectory()) { yanit.writeHead(404); yanit.end('yok: ' + ad); return; }
  yanit.writeHead(200, { 'content-type': TURLER[path.extname(tam)] || 'application/octet-stream', 'cache-control': 'no-store' });
  yanit.end(fs.readFileSync(tam));
}

try {
  console.log('izole veritabani kuruluyor (Docker)...');
  await O.kur();
  const t1 = O.sql(EK_TOHUM); if (!t1.ok) throw new Error('A1 tohum: ' + t1.err.slice(-300));
  const t2 = O.sql(PMS_TOHUM); if (!t2.ok) throw new Error('PMS tohum: ' + t2.err.slice(-400));
  REST = await O.restBaslat({ port: 3095 });

  const sunucu = http.createServer((istek, yanit) => {
    if (istek.url.startsWith('/rest/v1/')) return void vekil(istek, yanit);
    statik(istek, yanit);
  });
  await new Promise((c) => sunucu.listen(PORT, '127.0.0.1', c));

  const durum = (s) => O.sql(s).out.trim();
  console.log('\n=== TARAYICI ORTAMI HAZIR ===');
  console.log('  adres      : http://127.0.0.1:' + PORT + '/pms-oda-plani.html');
  console.log('  PostgREST  : ' + REST + ' (vekil arkasinda)');
  console.log('  oda 201    : ' + durum(`select kullanim_durumu||'/'||temizlik_durumu from public.pms_odalar where id='${PMS.ODA201}';`)
    + '  — ATANMIS rezervasyon var (T-201)');
  console.log('  oda 202/203: bos/temiz — atamasiz rezervasyon T-202 bekliyor');
  console.log('\n  Ctrl-C ile kapanir; konteynerler silinir.\n');

  const kapat = () => { try { O.temizle(); } catch {} process.exit(0); };
  process.on('SIGINT', kapat); process.on('SIGTERM', kapat);
  await new Promise(() => {});
} catch (e) {
  console.log('KURULUM HATASI: ' + (e && e.message || e));
  O.temizle();
  process.exit(1);
}
