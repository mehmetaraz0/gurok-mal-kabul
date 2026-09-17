// ===========================================================================
// IZOLE TEST ORTAMI — tek kullanimlik postgres + postgrest
// ===========================================================================
// Iki test dosyasi da (veri katmani ve ekran) ayni ortami kurar. Kurulum tek
// yerde durur ki "testte gecti ama sema baska" durumu olusmasin.
//
// URETIME HICBIR BAGLANTISI YOKTUR: konteynerler her kosuda yeniden yaratilir,
// veri tmpfs'te tutulur, sir yereldir.
//
// STOK RPC'LERI ELLE YAZILMAZ: govdeler scripts/stok-rpc-govde.mjs icinde
// uretimden birebir durur, uzerine docs/kurulum altindaki GERCEK migration'lar
// uygulanir ve kurulan govdenin md5'i uretim olcumuyle karsilastirilir.
// Gerekce: 2026-09-17'de buradaki elle yazilmis stok_ekle kopyasi
// guncelleme_tarihi'ni set ediyordu, uretimdeki etmiyordu — test yesil,
// ekran yanlis. Uretimde olmayan davranisi test ortaminda var saymak hatayi
// gizler.
// ===========================================================================
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { setTimeout as bekle } from 'node:timers/promises';
import { createRequire } from 'node:module';
import { URETIM_RPC_SEMA, OTEL_ID_TIPI, STOK_RPC_MIGRATIONLARI, MD5_SORGUSU, MD5_BEKLENEN }
  from './stok-rpc-govde.mjs';

const require = createRequire(import.meta.url);
export const kok = new URL('..', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');

// Asgari sema: testlerin konusu sayfalama ve eksiksizlik. RLS ayrica kurulur.
export const TEMEL_SEMA = `
  create role anon nologin;
  create role authenticated nologin;
  create role service_role nologin;
  grant usage on schema public to anon, authenticated, service_role;

  create table public.urunler (kod text primary key, ad text, birim text);
  ${OTEL_ID_TIPI}
  -- otel_id uretimde enum, text degil: RPC govdeleri ::otel_id cast'i tasir
  -- ve cast'siz atama 42804 verir (2026-07-17'de canlida yasandi).
  create table public.stok (
    id uuid primary key default gen_random_uuid(),
    urun_kodu text not null, depo_kodu text not null, otel_id public.otel_id not null,
    miktar numeric(12,3) not null default 0,
    guncelleme_tarihi timestamptz not null default now());
  create table public.stok_minimumlar (
    id uuid primary key default gen_random_uuid(),
    urun_kodu text not null, depo_kodu text not null, otel_id text not null,
    min_miktar numeric(12,3) not null default 0);
  create table public.stok_hareketleri (
    id uuid primary key default gen_random_uuid(),
    urun_kodu text, depo_kodu text, otel_id text, tip text, miktar numeric(12,3),
    tarih timestamptz default now(), belge_no text, aciklama text,
    kaynak_depo_kodu text);
  create table public.sayim_oturumlari (
    id uuid primary key default gen_random_uuid(),
    depo_kodu text not null, otel_id text, olusturan_ad text,
    durum text default 'onay_bekliyor',
    toplam_urun_sayisi integer default 0, farkli_urun_sayisi integer default 0,
    olusturma_tarihi timestamptz default now());
  create table public.sayim_detaylari (
    id uuid primary key default gen_random_uuid(),
    oturum_id uuid not null, urun_kodu text not null, urun_adi text,
    sistem_miktar numeric(12,3), sayilan_miktar numeric(12,3),
    fark numeric(12,3), fark_yuzde numeric(12,3), birim text, aciklama text);

  grant select on all tables in schema public to authenticated, service_role;
  grant insert, update on public.sayim_oturumlari, public.sayim_detaylari,
    public.stok, public.stok_hareketleri to authenticated, service_role;
`;

// Ekranin yazma yollari RPC kullanir. Govde uretimden gelir (stok-rpc-govde.mjs);
// burada yalniz uretimdeki tekil kisit yeniden kurulur — RPC'lerin
// "on conflict (urun_kodu, depo_kodu)" yolu buna dayanir.
export const RPC_SEMA = `
  create unique index if not exists stok_urun_depo_tekil
    on public.stok (urun_kodu, depo_kodu);
${URETIM_RPC_SEMA()}`;

export function ortamOlustur({ onek = 'stok-test', port = 3099, maxRows = 100 } = {}) {
  const AG = onek + '-net';
  const PG = onek + '-db';
  const PR = onek + '-rest';
  const SIR = 'stok-testi-icin-yerel-sir-en-az-32-karakter-olmali';
  const restUrl = 'http://127.0.0.1:' + port;

  const d = (a, girdi) => spawnSync('docker', a,
    { input: girdi, encoding: 'utf8', timeout: 600000, maxBuffer: 64 * 1024 * 1024 });
  const psql = (sql) => d(['exec', '-i', PG, 'psql', '-X', '-U', 'postgres', '-d', 'stoktest',
    '-v', 'ON_ERROR_STOP=1', '-q'], sql);
  const psqlTek = (sql) => d(['exec', '-i', PG, 'psql', '-X', '-U', 'postgres', '-d', 'stoktest',
    '-At', '-v', 'ON_ERROR_STOP=1'], sql).stdout.trim();

  function temizle() {
    for (const k of [PR, PG]) spawnSync('docker', ['rm', '-f', k]);
    spawnSync('docker', ['network', 'rm', AG]);
  }

  function jwt(rol, sub) {
    const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
    const bas = b64({ alg: 'HS256', typ: 'JWT' });
    const govde = b64({ role: rol, ...(sub ? { sub } : {}), exp: Math.floor(Date.now() / 1000) + 3600 });
    const imza = require('node:crypto').createHmac('sha256', SIR).update(bas + '.' + govde).digest('base64url');
    return bas + '.' + govde + '.' + imza;
  }

  async function kur({ ekSema = '', rpc = false } = {}) {
    temizle();
    spawnSync('docker', ['network', 'create', AG]);
    d(['run', '--detach', '--rm', '--name', PG, '--network', AG, '--tmpfs', '/var/lib/postgresql/data',
      '-e', 'POSTGRES_HOST_AUTH_METHOD=trust', 'postgres:17']);
    for (let i = 0; i < 60; i++) {
      if (spawnSync('docker', ['exec', PG, 'pg_isready', '-U', 'postgres']).status === 0) break;
      await bekle(1000);
    }
    await bekle(1500);
    d(['exec', PG, 'createdb', '-U', 'postgres', 'stoktest']);
    psql(TEMEL_SEMA);
    if (rpc) {
      psql(RPC_SEMA);
      // Kurulan govde uretimde OLCULEN govde mi? Tutmuyorsa testler artik
      // uretimi temsil etmiyor demektir — sessizce devam etmek, gizlenen
      // hatanin ta kendisidir.
      const md5 = psqlTek(MD5_SORGUSU);
      if (md5 !== MD5_BEKLENEN) {
        console.error('Stok RPC govdeleri uretim olcumuyle AYNI DEGIL:\n  kurulan : ' + md5 +
          '\n  beklenen: ' + MD5_BEKLENEN + '\n  (scripts/stok-rpc-govde.mjs)');
        temizle();
        process.exit(1);
      }
      // Uretim govdesinin uzerine, canliya gidecek GERCEK migration dosyalari.
      for (const yol of STOK_RPC_MIGRATIONLARI) {
        const r = psql(readFileSync(kok + yol, 'utf8'));
        if (r.status !== 0) {
          console.error('Stok RPC migration uygulanamadi (' + yol + '):\n' +
            (r.stderr || '').split('\n').slice(-6).join('\n'));
          temizle();
          process.exit(1);
        }
      }
    }
    if (ekSema) psql(ekSema);

    // Aday migration AYNEN uygulanir.
    const mig = readFileSync(kok + 'docs/kurulum/2026-09-14-stok-liste-ozet.sql', 'utf8');
    const r = psql(mig);
    if (r.status !== 0) {
      console.error('Migration uygulanamadi:\n' + (r.stderr || '').split('\n').slice(-6).join('\n'));
      temizle();
      process.exit(1);
    }

    d(['run', '--detach', '--rm', '--name', PR, '--network', AG, '-p', port + ':3000',
      '-e', 'PGRST_DB_URI=postgres://postgres@' + PG + ':5432/stoktest',
      '-e', 'PGRST_DB_SCHEMAS=public',
      '-e', 'PGRST_DB_ANON_ROLE=anon',
      '-e', 'PGRST_JWT_SECRET=' + SIR,
      '-e', 'PGRST_DB_MAX_ROWS=' + maxRows,
      'postgrest/postgrest:v12.2.3']);
    for (let i = 0; i < 60; i++) {
      try {
        const c = await fetch(restUrl + '/', { headers: { Authorization: 'Bearer ' + jwt('authenticated') } });
        if (c.status < 500) break;
      } catch (e) { /* henuz ayakta degil */ }
      await bekle(1000);
    }
  }

  return { kur, psql, psqlTek, temizle, jwt, restUrl, maxRows, port };
}
