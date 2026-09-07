// ============================================================================
// YEREL STAGING — MANUEL TARAYICI QA İÇİN
// ============================================================================
// Uygulamayı ÜRETİME HİÇ DOKUNMADAN gerçek bir tarayıcıda çalıştırır.
//
//   Docker: postgres:17  + postgrest/postgrest
//   Node  : yerel geçit  (statik dosya + /functions/v1/pin-girisi stub'ı
//                         + /rest/v1 -> PostgREST proxy'si)
//
// ÜRETİM BAĞLANTISI YOKTUR:
//   * supabase-config.js DEĞİŞTİRİLMEZ; geçit onu SERVIS EDERKEN bellekte
//     yeniden yazar (SB_URL -> yerel geçit). Repo dosyaları temiz kalır.
//   * PIN doğrulaması gerçek Edge Function'a gitmez; yerel stub PIN'i
//     kullanıcıya eşler ve JWT'yi PostgREST ile paylaşılan sır ile imzalar.
//     Bu yüzden ÜRETİM PIN'İ GEREKMEZ ve üretime giriş kaydı YAZILMAZ.
//
// Kullanım:
//   node scripts/yerel-staging.mjs           # kurar ve http://127.0.0.1:8791
//   node scripts/yerel-staging.mjs --durdur  # konteynerleri kaldırır
//
// QA adımları: docs/kurulum/2026-09-07-tarayici-qa-kontrol-listesi.md
// ============================================================================
import { spawnSync } from 'node:child_process';
import { readFileSync, existsSync } from 'node:fs';
import { createHmac } from 'node:crypto';
import { extname, join, resolve, sep } from 'node:path';
import http from 'node:http';
import { setTimeout as bekle } from 'node:timers/promises';

const kok = resolve(new URL('..', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'));
const AG = 'pms-staging-net';
const PG = 'pms-staging-db';
const PR = 'pms-staging-rest';
const PORT = 8791;
const REST_PORT = 3001;
// Yalniz yerel; uretimdeki hicbir sirla ilgisi yok.
const JWT_SIR = 'yerel-staging-sadece-qa-icin-en-az-32-karakter-uzunlugunda';

const DOSYA = {
  shim:  join(kok, 'scripts/supabase-shim.sql'),
  dokum: join(kok, 'docs/kurulum/2026-09-06-sema-dokumu.sql'),
  adim1: join(kok, 'docs/kurulum/2026-09-06-pms-faz1-oda-tipleri-odalar.sql'),
  adim2: join(kok, 'docs/kurulum/2026-09-06-pms-faz1-adim2-misafir-rezervasyon.sql'),
  adim3: join(kok, 'docs/kurulum/2026-09-06-pms-faz1-adim3-checkin-checkout.sql'),
  adim4: join(kok, 'docs/kurulum/2026-09-06-pms-faz1-adim4-folio.sql'),
  overlay: join(kok, 'scripts/yerel-staging-overlay.sql'),
};

// PIN -> demo kullanici. Gercek PIN dogrulamasi DEGILDIR; yerel stub.
const PINLER = {
  '111111': 'a0000000-0000-0000-0000-0000000000a1',  // QA Tam Yetki (otel 810)
  '222222': 'a0000000-0000-0000-0000-0000000000a2',  // QA Kisitli (folyo yetkisi YOK)
  '333333': 'a0000000-0000-0000-0000-0000000000a3',  // QA 811 Otel
};

function calistir(komut, args, girdi) {
  const r = spawnSync(komut, args, {
    input: girdi, encoding: 'utf8', timeout: 300000, maxBuffer: 64 * 1024 * 1024,
  });
  return { ok: !r.error && r.status === 0, out: r.stdout || '', err: r.error?.message || r.stderr || '' };
}
const docker = (args, girdi) => calistir('docker', args, girdi);
const psql = (girdi, kati = true) => docker(
  ['exec', '-i', PG, 'psql', '-X', '-U', 'postgres', '-d', 'pmsqa', ...(kati ? ['-v', 'ON_ERROR_STOP=1'] : [])],
  girdi);

function temizle() {
  docker(['rm', '-f', PR]);
  docker(['rm', '-f', PG]);
  docker(['network', 'rm', AG]);
}

if (process.argv.includes('--durdur')) {
  temizle();
  console.log('Yerel staging kaldirildi.');
  process.exit(0);
}

for (const [ad, yol] of Object.entries(DOSYA)) {
  if (!existsSync(yol)) { console.error('Dosya yok (' + ad + '): ' + yol); process.exit(1); }
}

// ---------------------------------------------------------------------------
// 1) Konteynerler
// ---------------------------------------------------------------------------
console.log('Yerel staging kuruluyor (uretime baglanmaz)...\n');
temizle();
docker(['network', 'create', AG]);

let r = docker(['run', '--detach', '--name', PG, '--network', AG,
  '--tmpfs', '/var/lib/postgresql/data',
  '-e', 'POSTGRES_HOST_AUTH_METHOD=trust', 'postgres:17']);
if (!r.ok) { console.error('postgres baslatilamadi: ' + r.err.slice(0, 300)); process.exit(1); }

for (let i = 0; i < 60; i++) {
  if (spawnSync('docker', ['exec', PG, 'pg_isready', '-U', 'postgres']).status === 0) break;
  await bekle(1000);
}
docker(['exec', PG, 'createdb', '-U', 'postgres', 'pmsqa']);
console.log('  [1/6] postgres hazir');

r = psql(readFileSync(DOSYA.shim, 'utf8'));
if (!r.ok) { console.error('iskele: ' + r.err.slice(-800)); temizle(); process.exit(1); }
console.log('  [2/6] supabase iskelesi');

// Dokum `create schema public` iceriyor; YALNIZ o hata elenir.
r = psql(readFileSync(DOSYA.dokum, 'utf8'), false);
const dh = r.err.split('\n').filter((l) => l.startsWith('ERROR:'))
  .filter((l) => !/schema "public" already exists/.test(l));
if (dh.length) { console.error('dokum:\n' + dh.slice(0, 5).join('\n')); temizle(); process.exit(1); }
console.log('  [3/6] uretim sema kopyasi');

for (const ad of ['adim1', 'adim2', 'adim3', 'adim4']) {
  r = psql(readFileSync(DOSYA[ad], 'utf8'));
  if (!r.ok) {
    console.error(ad + ':\n' + r.err.split('\n').filter((l) => l.startsWith('ERROR:')).slice(0, 4).join('\n'));
    temizle(); process.exit(1);
  }
}
console.log('  [4/6] PMS Adim 1-4 migration');

r = psql(readFileSync(DOSYA.overlay, 'utf8'));
if (!r.ok) { console.error('overlay: ' + r.err.slice(-800)); temizle(); process.exit(1); }
console.log('  [5/6] staging katmani + demo veri');

r = docker(['run', '--detach', '--name', PR, '--network', AG,
  '-e', 'PGRST_DB_URI=postgres://authenticator:staging@' + PG + ':5432/pmsqa',
  '-e', 'PGRST_DB_SCHEMAS=public',
  '-e', 'PGRST_DB_ANON_ROLE=anon',
  '-e', 'PGRST_JWT_SECRET=' + JWT_SIR,
  '-p', REST_PORT + ':3000',
  'postgrest/postgrest']);
if (!r.ok) { console.error('postgrest baslatilamadi: ' + r.err.slice(0, 300)); temizle(); process.exit(1); }

let restHazir = false;
for (let i = 0; i < 40; i++) {
  try {
    const y = await fetch('http://127.0.0.1:' + REST_PORT + '/', { signal: AbortSignal.timeout(2000) });
    if (y.status < 500) { restHazir = true; break; }
  } catch { /* henuz ayakta degil */ }
  await bekle(500);
}
if (!restHazir) {
  // Kaydi TEMIZLEMEDEN once al: aksi halde tani icin hicbir sey kalmiyor.
  const kayit = docker(['logs', '--tail', '30', PR]);
  console.error(['PostgREST ayaga kalkmadi. Konteyner kaydi:',
    kayit.out || '', kayit.err || ''].join('\n'));
  temizle(); process.exit(1);
}
console.log('  [6/6] PostgREST hazir\n');

// ---------------------------------------------------------------------------
// 2) JWT
// ---------------------------------------------------------------------------
const b64 = (o) => Buffer.from(typeof o === 'string' ? o : JSON.stringify(o))
  .toString('base64url');

function jwtUret(sub, rol) {
  const simdi = Math.floor(Date.now() / 1000);
  const govde = b64({ alg: 'HS256', typ: 'JWT' }) + '.'
    + b64({ sub, role: rol, iss: 'yerel-staging', iat: simdi, exp: simdi + 8 * 3600 });
  return govde + '.' + createHmac('sha256', JWT_SIR).update(govde).digest('base64url');
}
const ANON_JWT = jwtUret('00000000-0000-0000-0000-000000000000', 'anon');

// ---------------------------------------------------------------------------
// 3) Geçit
// ---------------------------------------------------------------------------
const TIP = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml', '.png': 'image/png', '.ico': 'image/x-icon',
  '.webmanifest': 'application/manifest+json',
};

function govdeOku(istek) {
  return new Promise((coz) => {
    let v = ''; istek.on('data', (p) => { v += p; }); istek.on('end', () => coz(v));
  });
}

http.createServer(async (istek, yanit) => {
  const url = new URL(istek.url, 'http://127.0.0.1:' + PORT);
  const yol = decodeURIComponent(url.pathname);

  // --- PIN girisi stub'i: gercek Edge Function'in yerine gecer ---
  if (yol === '/functions/v1/pin-girisi' && istek.method === 'POST') {
    const { pin } = JSON.parse((await govdeOku(istek)) || '{}');
    const uid = PINLER[String(pin || '')];
    yanit.setHeader('Content-Type', 'application/json; charset=utf-8');
    if (!uid) { yanit.writeHead(200); yanit.end(JSON.stringify({ ok: false, mesaj: 'Hatali PIN (yerel staging)' })); return; }
    const token = jwtUret(uid, 'authenticated');
    // service_role: BYPASSRLS. Kullanicinin kendi token'i ile aramak
    // yumurta-tavuk olurdu (kullanicilar SELECT politikasi ayri bir modul
    // yetkisi ister). Gercek pin-girisi Edge Function'i da service role kosar.
    const k = await fetch('http://127.0.0.1:' + REST_PORT
      + '/kullanicilar?select=*&auth_user_id=eq.' + uid,
      { headers: { Authorization: 'Bearer ' + jwtUret(uid, 'service_role') } });
    const satirlar = k.ok ? await k.json() : [];
    if (!satirlar.length) {
      yanit.writeHead(200);
      yanit.end(JSON.stringify({ ok: false, mesaj: 'Kullanici bulunamadi (staging verisi eksik)' }));
      return;
    }
    // ÜRETİM SADAKATİ: gerçek pin-girisi Edge Function'i satira camelCase
    // takma adlar da ekliyor ve uygulama BUNLARI okuyor (CU.otelId).
    // Ham satiri dondurmek, otel kapsamini "Tum oteller" gosterip QA'nin
    // YANLIS davranisi test etmesine yol acar.
    const k0 = satirlar[0];
    yanit.writeHead(200);
    yanit.end(JSON.stringify({
      ok: true,
      kullanici: { ...k0, otelId: k0.otel_id ?? null, depoId: k0.depo_id ?? null },
      access_token: token,
    }));
    return;
  }

  // --- /rest/v1 -> PostgREST ---
  if (yol.startsWith('/rest/v1/')) {
    const hedef = 'http://127.0.0.1:' + REST_PORT + yol.slice('/rest/v1'.length) + url.search;
    const bas = {};
    for (const [a, d] of Object.entries(istek.headers)) {
      if (['host', 'connection', 'content-length', 'apikey'].includes(a)) continue;
      bas[a] = d;
    }
    // Uygulama oturum yokken anon key gonderiyor; PostgREST onu cozemez.
    // Yerel anon JWT'ye cevir ki "yetkisiz" davranisi GERCEKCI olsun.
    const yetki = istek.headers.authorization || '';
    if (!yetki.startsWith('Bearer ey') || yetki.includes(String.fromCharCode(46) + 'E7cR')) {
      bas.authorization = 'Bearer ' + ANON_JWT;
    }
    try {
      const c = await fetch(hedef, {
        method: istek.method,
        headers: bas,
        body: ['GET', 'HEAD'].includes(istek.method) ? undefined : await govdeOku(istek),
      });
      const metin = await c.text();
      yanit.writeHead(c.status, {
        'Content-Type': c.headers.get('content-type') || 'application/json',
        ...(c.headers.get('content-range') ? { 'Content-Range': c.headers.get('content-range') } : {}),
      });
      yanit.end(metin);
    } catch (e) {
      yanit.writeHead(502); yanit.end(JSON.stringify({ message: 'gecit hatasi: ' + e.message }));
    }
    return;
  }

  // --- /functions/v1/* digerleri: sessizce bos ---
  if (yol.startsWith('/functions/v1/')) {
    yanit.writeHead(200, { 'Content-Type': 'application/json' });
    yanit.end(JSON.stringify({ ok: false, mesaj: 'yerel staging: bu Edge Function yok' }));
    return;
  }

  // --- Statik dosyalar ---
  let dosyaYolu = yol === '/' ? '/index.html' : yol;
  const tam = resolve(join(kok, dosyaYolu));
  if (tam !== kok && !tam.startsWith(kok + sep)) { yanit.writeHead(403); yanit.end('yasak'); return; }
  try {
    let veri = readFileSync(tam);
    // supabase-config.js BELLEKTE yeniden yazilir; repo dosyasi degismez.
    if (tam.endsWith('supabase-config.js')) {
      veri = Buffer.from(veri.toString('utf8')
        .replace(/const SB_URL='[^']*'/, "const SB_URL='http://127.0.0.1:" + PORT + "'"));
    }
    yanit.writeHead(200, { 'Content-Type': TIP[extname(tam)] || 'application/octet-stream' });
    yanit.end(veri);
  } catch {
    yanit.writeHead(404); yanit.end('yok');
  }
}).on('error', (e) => {
  // Gecit bu surecin ICINDE calisiyor; --durdur onu durduramaz (o ayri bir
  // surectir, yalniz konteynerleri kaldirir). Bu yuzden acik mesaj sart.
  if (e.code === 'EADDRINUSE') {
    console.error('Port ' + PORT + ' dolu — baska bir yerel staging zaten calisiyor.');
    console.error('Once o pencerede Ctrl+C yapin, sonra: node scripts/yerel-staging.mjs --durdur');
    process.exit(1);
  }
  throw e;
}).listen(PORT, '127.0.0.1', () => {
  console.log('='.repeat(66));
  console.log('YEREL STAGING HAZIR  ->  http://127.0.0.1:' + PORT);
  console.log('='.repeat(66));
  console.log('Demo PIN kodlari (yalniz yerel; uretim PIN\'i DEGIL):');
  console.log('  111111  QA Tam Yetki      otel 810 — tum PMS + bar');
  console.log('  222222  QA Kisitli        otel 810 — yalniz goruntule, FOLYO YOK');
  console.log('  333333  QA 811 Otel       otel 811 — capraz otel izolasyonu icin');
  console.log('');
  console.log('QA listesi: docs/kurulum/2026-09-07-tarayici-qa-kontrol-listesi.md');
  console.log('Durdurmak icin: Ctrl+C, ardindan');
  console.log('  node scripts/yerel-staging.mjs --durdur');
  console.log('='.repeat(66));
});

process.on('SIGINT', () => {
  console.log('\nKonteynerler kaldiriliyor...');
  temizle();
  process.exit(0);
});
