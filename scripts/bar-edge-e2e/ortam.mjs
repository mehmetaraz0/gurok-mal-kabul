// ===========================================================================
// BAR EDGE FUNCTION UCTAN UCA ORTAMI — uretime BAGLANMAZ (tasarim 5, E2)
// ===========================================================================
//   ANA proje     : postgres (uretim dokumu + uretim-sonrasi migration'lar [+ A1])
//                   + PostgREST + GoTrue (ayri 'gotrue' veritabani)
//   MUSTERI proje : postgres (musteri-projesi/01 + 03 sema) + PostgREST
//   Edge Runtime  : uc fonksiyon, CANLI adlariyla (hyper-api / rapid-handler /
//                   smooth-service); kaynak docs/kurulum/musteri-projesi/*
//   Yonlendiriciler (Node, bu makinede): Supabase ag gecidinin yol eslemesi
//                   ANA  : /auth/v1 -> GoTrue, /rest/v1 -> PostgREST
//                   MUST.: /rest/v1 -> PostgREST, /functions/v1 -> Edge Runtime
// Imajlar OZETLE sabit; supabase-js 2.116.0'a sabit (import_map.json). Bunlar
// TEST ortaminin surumleridir — uretimle surum esitligi IDDIA EDILMEZ.
// Tum anahtarlar yerel JWT'dir; uretim sirri kullanilmaz.
// ===========================================================================
import { spawnSync } from 'node:child_process';
import http from 'node:http';
import { readFileSync } from 'node:fs';
import { setTimeout as bekle } from 'node:timers/promises';
import { barOrtami, yerelJwt, YEREL_JWT_SIRRI, PG_IMAJ, PGRST_IMAJ, kok } from '../bar-test-ortam.mjs';
import { EK_TOHUM } from '../bar-a1-tohum.mjs';

export const GOTRUE_IMAJ = 'supabase/gotrue@sha256:1736a63078f5922b198c4cbe50f80ab9a2d3b54fe8b7b6cfb2e9dc5dbbc12c6b';        // v2.197.0
export const EDGE_IMAJ = 'supabase/edge-runtime@sha256:edd22bef4477b900d5c300e287ce9b18bff9b81a0291bee14ee0b7c7b71a2899';    // v1.76.2
export const SUPABASE_JS = '2.116.0';

const P = { anaRest: 3201, gotrue: 3202, musRest: 3203, edge: 3204, anaGecit: 3211, musGecit: 3212 };
const A1 = 'docs/kurulum/2026-09-18-bar-a1-guvenlik.sql';
const d = (a, girdi) => spawnSync('docker', a, { input: girdi, encoding: 'utf8', timeout: 600000, maxBuffer: 64 * 1024 * 1024 });
const zorunlu = (r, adim) => { if (r.status !== 0) throw new Error(adim + ': ' + (r.stderr || '').slice(-600)); return r; };

async function hazirBekle(url, adim, secenek = {}) {
  for (let i = 0; i < 120; i++) {
    try { const r = await fetch(url, secenek); if (r.status < 500) return; } catch { /* henuz */ }
    await bekle(500);
  }
  throw new Error(adim + ' hazir olmadi: ' + url);
}

function gecit(port, yollar) {
  const sunucu = http.createServer((istek, yanit) => {
    const hedef = yollar.find(([onek]) => istek.url.startsWith(onek));
    if (!hedef) { yanit.writeHead(404); yanit.end('yol yok'); return; }
    const [onek, hedefPort] = hedef;
    const ileri = http.request({ host: '127.0.0.1', port: hedefPort, method: istek.method,
      path: istek.url.slice(onek.length) || '/', headers: { ...istek.headers, host: '127.0.0.1:' + hedefPort } }, (h) => {
      yanit.writeHead(h.statusCode, h.headers); h.pipe(yanit);
    });
    ileri.on('error', (e) => { yanit.writeHead(502); yanit.end('gecit: ' + e.message); });
    istek.pipe(ileri);
  });
  return new Promise((coz) => sunucu.listen(port, '0.0.0.0', () => coz(sunucu)));
}

export function e2eOrtami({ ad = 'bar-e2e', a1 = true, negatifDizin = null, ekDizin = negatifDizin } = {}) {
  const AG = ad + '-net';
  const ana = barOrtami({ ad: ad + '-ana', ag: AG });
  const MUS = ad + '-mus-db', MUS_REST = ad + '-mus-rest', GOT = ad + '-gotrue', EDGE = ad + '-edge';
  const sunucular = [];
  const anon = yerelJwt('anon'), servis = yerelJwt('service_role');
  const musSql = (q) => d(['exec', '-i', MUS, 'psql', '-X', '-U', 'postgres', '-d', 'bar', '-q', '-At', '-v', 'ON_ERROR_STOP=1'], q);

  function temizle() {
    for (const s of sunucular) s.close();
    spawnSync('docker', ['rm', '-f', EDGE, GOT, MUS_REST, MUS]);
    ana.temizle();   // agi da siler
  }

  async function kur() {
    temizle();
    // --- ANA ---
    await ana.kur();
    if (a1) { const u = ana.uygulaTekIslem(A1); if (!u.ok) throw new Error('A1: ' + u.err.slice(-400)); }
    const t = ana.sql(EK_TOHUM); if (!t.ok) throw new Error('ek tohum: ' + t.err.slice(-300));
    await ana.restBaslat({ port: P.anaRest });

    // GoTrue: ayri veritabani (ana veritabanindaki test auth katmanina dokunmaz).
    zorunlu(d(['exec', ana.konteyner, 'createdb', '-U', 'postgres', 'gotrue']), 'gotrue db');
    zorunlu(d(['exec', '-i', ana.konteyner, 'psql', '-X', '-U', 'postgres', '-d', 'gotrue', '-q'],
      `do $$ begin if not exists (select 1 from pg_roles where rolname='supabase_auth_admin') then
         create role supabase_auth_admin; end if; end $$;
       alter role supabase_auth_admin login superuser password 'yerel-test';
       create schema if not exists auth authorization supabase_auth_admin;`), 'gotrue rol');
    zorunlu(d(['run', '--detach', '--name', GOT, '--network', AG, '-p', P.gotrue + ':9999',
      '-e', 'GOTRUE_DB_DRIVER=postgres',
      '-e', `DATABASE_URL=postgres://supabase_auth_admin:yerel-test@${ana.konteyner}:5432/gotrue?sslmode=disable&search_path=auth`,
      '-e', 'GOTRUE_API_HOST=0.0.0.0', '-e', 'PORT=9999', '-e', 'API_EXTERNAL_URL=http://localhost',
      '-e', 'GOTRUE_SITE_URL=http://localhost', '-e', 'GOTRUE_JWT_SECRET=' + YEREL_JWT_SIRRI,
      '-e', 'GOTRUE_JWT_EXP=3600', '-e', 'GOTRUE_JWT_AUD=authenticated', '-e', 'GOTRUE_JWT_DEFAULT_GROUP_NAME=authenticated',
      '-e', 'GOTRUE_JWT_ADMIN_ROLES=service_role', '-e', 'GOTRUE_EXTERNAL_EMAIL_ENABLED=true',
      '-e', 'GOTRUE_MAILER_AUTOCONFIRM=true', '-e', 'GOTRUE_DISABLE_SIGNUP=true', GOTRUE_IMAJ]), 'gotrue');
    try { await hazirBekle(`http://127.0.0.1:${P.gotrue}/health`, 'gotrue'); }
    catch (e) { throw new Error(e.message + '\n' + d(['logs', '--tail', '30', GOT]).stderr.slice(-2500)); }

    // --- MUSTERI ---
    zorunlu(d(['run', '--detach', '--rm', '--name', MUS, '--network', AG, '--tmpfs', '/var/lib/postgresql/data',
      '-e', 'POSTGRES_HOST_AUTH_METHOD=trust', PG_IMAJ]), 'musteri db');
    for (let i = 0; i < 60; i++) { if (spawnSync('docker', ['exec', MUS, 'pg_isready', '-U', 'postgres']).status === 0) break; await bekle(1000); }
    await bekle(1500);
    zorunlu(d(['exec', MUS, 'createdb', '-U', 'postgres', 'bar']), 'musteri createdb');
    zorunlu(musSql(`create role anon nologin; create role authenticated nologin; create role service_role nologin bypassrls;
      create role authenticator login noinherit password 'yerel-test'; grant anon, authenticated, service_role to authenticator;
      grant usage on schema public to anon, authenticated, service_role;
      alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
      alter default privileges in schema public grant all on functions to anon, authenticated, service_role;`), 'musteri roller');
    for (const f of ['01-musteri-sema.sql', '03-menu-yayin.sql']) {
      zorunlu(musSql(readFileSync(kok + 'docs/kurulum/musteri-projesi/' + f, 'utf8')), f);
    }
    // 'bolge' sutunu masa-yonetim kodunda kullaniliyor ama depodaki musteri sema
    // dosyalarinda yok (canli musteri projesinde elle eklenmis olmali). Testte eklenir.
    zorunlu(musSql(`alter table public.masa_tokenlari add column if not exists bolge text;
      insert into public.masa_tokenlari (token, otel_id, depo_id, masa_adi, bolge, aktif) values
        ('tok-810-a', '810', '810_CSM302', 'Havuz 1', 'Havuz', true),
        ('tok-811-a', '811', '811_CSM302', 'Lobi 1', 'Lobi', true),
        ('tok-810-pasif', '810', '810_CSM302', 'Kapali', 'Havuz', false);`), 'musteri tohum');
    zorunlu(d(['run', '--detach', '--rm', '--name', MUS_REST, '--network', AG, '-p', P.musRest + ':3000',
      '-e', `PGRST_DB_URI=postgres://authenticator:yerel-test@${MUS}:5432/bar`, '-e', 'PGRST_DB_SCHEMAS=public',
      '-e', 'PGRST_DB_ANON_ROLE=anon', '-e', 'PGRST_JWT_SECRET=' + YEREL_JWT_SIRRI, PGRST_IMAJ]), 'musteri rest');
    await hazirBekle(`http://127.0.0.1:${P.musRest}/`, 'musteri rest', { headers: { Authorization: 'Bearer ' + servis } });

    // --- Gecitler ---
    sunucular.push(await gecit(P.anaGecit, [['/auth/v1', P.gotrue], ['/rest/v1', P.anaRest]]));
    sunucular.push(await gecit(P.musGecit, [['/rest/v1', P.musRest], ['/functions/v1', P.edge]]));

    // --- Edge Runtime ---
    const fn = kok + 'scripts/bar-edge-e2e/functions/main';
    const src = kok + 'docs/kurulum/musteri-projesi';
    zorunlu(d(['run', '--detach', '--rm', '--name', EDGE, '--network', AG, '-p', P.edge + ':9000',
      '--add-host', 'host.docker.internal:host-gateway',
      '-v', fn + ':/home/deno/functions/main:ro', '-v', src + ':/home/deno/functions/src:ro',
      ...(ekDizin ? ['-v', ekDizin + ':/home/deno/functions/neg:ro'] : []),
      '-e', `MAIN_SB_URL=http://host.docker.internal:${P.anaGecit}`, '-e', 'MAIN_SERVICE_KEY=' + servis,
      '-e', 'MAIN_ANON_KEY=' + anon,
      '-e', `CUSTOMER_SB_URL=http://host.docker.internal:${P.musGecit}`, '-e', 'CUSTOMER_SERVICE_KEY=' + servis,
      EDGE_IMAJ, 'start', '--main-service', '/home/deno/functions/main', '-p', '9000']), 'edge runtime');
    await hazirBekle(`http://127.0.0.1:${P.edge}/rapid-handler`, 'edge runtime',
      { method: 'POST', body: JSON.stringify({ action: 'ping' }), headers: { 'Content-Type': 'application/json' } });
  }

  // GoTrue kullanicisi: kimligi tohumdaki auth_user_id ile AYNI olur.
  async function kullaniciOlustur(id, email, parola = 'Yerel-Test-1234') {
    const r = await fetch(`http://127.0.0.1:${P.anaGecit}/auth/v1/admin/users`, { method: 'POST',
      headers: { Authorization: 'Bearer ' + servis, apikey: anon, 'Content-Type': 'application/json' },
      body: JSON.stringify({ id, email, password: parola, email_confirm: true }) });
    const g = await r.json();
    if (!r.ok || g.id !== id) throw new Error('gotrue kullanici: ' + r.status + ' ' + JSON.stringify(g).slice(0, 300));
    return g;
  }
  async function girisYap(email, parola = 'Yerel-Test-1234') {
    const r = await fetch(`http://127.0.0.1:${P.anaGecit}/auth/v1/token?grant_type=password`, { method: 'POST',
      headers: { apikey: anon, 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password: parola }) });
    const g = await r.json();
    if (!r.ok || !g.access_token) throw new Error('giris: ' + r.status + ' ' + JSON.stringify(g).slice(0, 300));
    return g.access_token;
  }
  // Musteri projesindeki fonksiyon cagrisi: platform kapisi icin musteri anon anahtari.
  async function fonksiyon(adi, govde, ekBaslik = {}) {
    const r = await fetch(`http://127.0.0.1:${P.musGecit}/functions/v1/${adi}`, { method: 'POST',
      headers: { apikey: anon, Authorization: 'Bearer ' + anon, 'Content-Type': 'application/json', ...ekBaslik },
      body: JSON.stringify(govde) });
    const metin = await r.text();
    let json = null; try { json = JSON.parse(metin); } catch { /* duz metin */ }
    return { durum: r.status, json, metin };
  }
  const edgeGunlugu = () => d(['logs', '--tail', '80', EDGE]).stdout + d(['logs', '--tail', '80', EDGE]).stderr;

  return { ana, musSql: (q) => { const r = musSql(q); return { ok: r.status === 0, out: (r.stdout || '').trim(), err: r.stderr }; },
    kur, temizle, kullaniciOlustur, girisYap, fonksiyon, edgeGunlugu, anon, servis, P };
}
