// ===========================================================================
// SIRA TESTI: tarih duzeltmesi -> bar A1  ·  izole, uretime BAGLANMAZ
// ===========================================================================
// Soru: iki is ayni iki fonksiyonu (stok_ekle / stok_transfer) yeniden
// tanimliyor. Uretimdeki sirayla uygulandiginda IKISI BIRDEN calisiyor mu?
//   1. docs/kurulum/2026-09-17-stok-guncelleme-tarihi.sql  (guncelleme_tarihi)
//   2. bar A1 govdeleri                                    (rezervasyon korumasi)
//
// Ne kanitlar:
//   0. A1 govdeleri plandan OKUNUR (kopya tutulmaz); tarih satirini iceriyor
//   1. Tarih duzeltmesi tek basina calisir
//   2. A1'den SONRA da tarih guncelleniyor (duzeltme ezilmedi)
//   3. A1'den sonra rezervasyon korumasi calisiyor (cikis ve transfer)
//   4. Rezervasyon yoksa davranis degismiyor
//   5. NEGATIF KONTROL: A1 govdelerinden tarih satiri cikarilirsa test DUSER
//      (yani 2. maddedeki olcum gercekten bir sey olcuyor)
//
// A1 govdeleri plan dosyasindan gelir; plan baska bir dalda olabilir
// (pms-hk-otel-secici), bu yuzden once calisma agacina, sonra git'e bakilir.
// ===========================================================================
import { spawnSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { setTimeout as bekle } from 'node:timers/promises';
import { URETIM_RPC_SEMA, OTEL_ID_TIPI } from './stok-rpc-govde.mjs';

const kok = new URL('..', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const PLAN = 'docs/superpowers/plans/2026-09-17-bar-guvenlik-ikmal-kabul.md';
const DALLAR = ['pms-hk-otel-secici', 'main', 'HEAD'];
const PG = 'stok-sira-test-db';
const ESKI = '2026-07-09 07:23:10+00';

let ok = 0, fail = 0;
function sonuc(gecti, ad, ek) {
  console.log((gecti ? 'OK   ' : 'FAIL ') + ad + (ek ? ' — ' + ek : ''));
  if (gecti) ok++; else fail++;
}

const d = (a, girdi) => spawnSync('docker', a, { input: girdi, encoding: 'utf8', timeout: 600000, maxBuffer: 64 * 1024 * 1024 });
const psql = (db, sql) => d(['exec', '-i', PG, 'psql', '-X', '-U', 'postgres', '-d', db, '-v', 'ON_ERROR_STOP=1', '-q'], sql);
const tek = (db, sql) => {
  const r = d(['exec', '-i', PG, 'psql', '-X', '-U', 'postgres', '-d', db, '-At', '-v', 'ON_ERROR_STOP=1'], sql);
  if (r.status !== 0) throw new Error(r.stderr);
  return r.stdout.trim();
};
const temizle = () => spawnSync('docker', ['rm', '-f', PG]);

// --- A1 govdeleri: plandan oku, kopyalama --------------------------------
function planMetni() {
  if (existsSync(kok + PLAN)) return readFileSync(kok + PLAN, 'utf8');
  for (const dal of DALLAR) {
    const r = spawnSync('git', ['-C', kok, 'show', dal + ':' + PLAN], { encoding: 'utf8', maxBuffer: 32 * 1024 * 1024 });
    if (r.status === 0 && r.stdout) return r.stdout;
  }
  throw new Error('Plan dosyasi bulunamadi (calisma agaci ve ' + DALLAR.join('/') + '): ' + PLAN);
}
function a1Govdeleri() {
  const metin = planMetni();
  const bas = metin.indexOf('create or replace function public._stok_kilitle');
  const sonAnahtar = 'create or replace function public.stok_transfer';
  const trBas = metin.indexOf(sonAnahtar, bas);
  const bit = metin.indexOf('$$;', metin.indexOf('end;', trBas)) + 3;
  if (bas < 0 || trBas < 0 || bit < 3) throw new Error('A1 govdeleri planda bulunamadi');
  return metin.slice(bas, bit);
}

// A1 govdelerinin dayandigi, bu testin konusu OLMAYAN nesneler.
const A1_BAGIMLILIKLARI = `
  create schema if not exists auth;
  create or replace function auth.uid() returns uuid language sql stable as $$ select null::uuid $$;
  create or replace function public.auth_otel_erisim(p_otel text) returns boolean
    language sql stable as $$ select true $$;
  create table public.stok_rezervasyonlari (
    id uuid primary key default gen_random_uuid(),
    depo_id text not null, stok_kodu text not null,
    miktar numeric(12,3) not null, durum text not null default 'aktif');
`;

const TEMEL = `
  do $r$ begin
    if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
    if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role nologin; end if;
  end $r$;
  create schema if not exists extensions;
  ${OTEL_ID_TIPI}
  create table public.stok (
    id uuid primary key default gen_random_uuid(),
    urun_kodu text not null, depo_kodu text not null, otel_id public.otel_id not null,
    miktar numeric(12,3) not null default 0,
    guncelleme_tarihi timestamptz not null default now(),
    unique (urun_kodu, depo_kodu));
${URETIM_RPC_SEMA()}
  grant select, insert, update on public.stok to authenticated, service_role;
`;

const TOHUM = `
  truncate public.stok, public.stok_rezervasyonlari;
  insert into public.stok (urun_kodu, depo_kodu, otel_id, miktar, guncelleme_tarihi) values
    ('BIRA', '810_CSM302', '810', 10, '${ESKI}'),
    ('BIRA', '810_100',    '810',  0, '${ESKI}');
`;

const tarih = (db, depo) => tek(db, `select case when guncelleme_tarihi > '2026-07-10'::timestamptz
  then 'YENI' else 'ESKI' end from public.stok where urun_kodu='BIRA' and depo_kodu='${depo}'`);
const miktar = (db, depo) => tek(db, `select miktar::text from public.stok
  where urun_kodu='BIRA' and depo_kodu='${depo}'`);
const rolle = (db, sql) => psql(db, 'set role authenticated;\n' + sql);

async function main() {
  temizle();
  d(['run', '--detach', '--rm', '--name', PG, '--network', 'none', '--tmpfs', '/var/lib/postgresql/data',
    '-e', 'POSTGRES_HOST_AUTH_METHOD=trust', 'postgres:17']);
  for (let i = 0; i < 60; i++) {
    if (spawnSync('docker', ['exec', PG, 'pg_isready', '-U', 'postgres']).status === 0) break;
    await bekle(1000);
  }
  await bekle(1500);

  try {
    const a1 = a1Govdeleri();
    const tarihSatiri = (a1.match(/guncelleme_tarihi = now\(\)/g) || []).length;
    sonuc(tarihSatiri === 3, '0. A1 govdeleri plandan okundu ve tarih satirini iceriyor',
      tarihSatiri + ' yerde guncelleme_tarihi = now() (bekl. 3)');

    // ---------------- 1) tarih duzeltmesi tek basina ----------------
    d(['exec', PG, 'createdb', '-U', 'postgres', 'sira']);
    const kurR = psql('sira', TEMEL + A1_BAGIMLILIKLARI);
    if (kurR.status !== 0) throw new Error('Taban kurulamadi: ' + kurR.stderr);

    const m1 = psql('sira', readFileSync(kok + 'docs/kurulum/2026-09-17-stok-guncelleme-tarihi.sql', 'utf8'));
    sonuc(m1.status === 0, '1a. tarih duzeltmesi uygulandi', m1.status === 0 ? '' : m1.stderr.slice(-300));
    psql('sira', TOHUM);
    rolle('sira', `select public.stok_ekle('BIRA','810_CSM302','810',-1);`);
    sonuc(tarih('sira', '810_CSM302') === 'YENI' && miktar('sira', '810_CSM302') === '9.000',
      '1b. tarih duzeltmesi tek basina calisiyor');

    // ---------------- 2-4) uzerine bar A1 ----------------
    const m2 = psql('sira', a1);
    sonuc(m2.status === 0, '2a. bar A1 govdeleri tarih duzeltmesinin UZERINE uygulandi',
      m2.status === 0 ? '' : m2.stderr.slice(-300));

    psql('sira', TOHUM);
    rolle('sira', `select public.stok_ekle('BIRA','810_CSM302','810',-1);`);
    sonuc(tarih('sira', '810_CSM302') === 'YENI' && miktar('sira', '810_CSM302') === '9.000',
      '2b. A1 SONRASI da tarih guncelleniyor (duzeltme ezilmedi)');

    psql('sira', TOHUM);
    rolle('sira', `select public.stok_transfer('BIRA','810_CSM302','810_100','810',4);`);
    sonuc(tarih('sira', '810_CSM302') === 'YENI' && tarih('sira', '810_100') === 'YENI'
      && miktar('sira', '810_CSM302') === '6.000' && miktar('sira', '810_100') === '4.000',
      '2c. A1 SONRASI transferin iki bacaginda da tarih guncelleniyor');

    // rezervasyon korumasi: 10 stokta 8 rezerve -> 5 birim cikis REDDEDILMELI
    psql('sira', TOHUM + `insert into public.stok_rezervasyonlari (depo_id, stok_kodu, miktar, durum)
      values ('810_CSM302','BIRA',8,'aktif');`);
    const red = rolle('sira', `select public.stok_ekle('BIRA','810_CSM302','810',-5);`);
    sonuc(red.status !== 0 && /REZERVE_STOK/.test(red.stderr) && miktar('sira', '810_CSM302') === '10.000'
      && tarih('sira', '810_CSM302') === 'ESKI',
      '3a. rezervasyon korumasi calisiyor: cikis reddedildi, satir hic degismedi');

    const redT = rolle('sira', `select public.stok_transfer('BIRA','810_CSM302','810_100','810',5);`);
    sonuc(redT.status !== 0 && /REZERVE_STOK/.test(redT.stderr) && miktar('sira', '810_CSM302') === '10.000',
      '3b. rezervasyon korumasi transferde de calisiyor');

    const gecer = rolle('sira', `select public.stok_ekle('BIRA','810_CSM302','810',-2);`);
    sonuc(gecer.status === 0 && miktar('sira', '810_CSM302') === '8.000' && tarih('sira', '810_CSM302') === 'YENI',
      '3c. rezerve siniri icindeki cikis geciyor ve tarihi guncelliyor');

    psql('sira', TOHUM);   // rezervasyon yok
    const serbest = rolle('sira', `select public.stok_ekle('BIRA','810_CSM302','810',-5);`);
    sonuc(serbest.status === 0 && miktar('sira', '810_CSM302') === '5.000' && tarih('sira', '810_CSM302') === 'YENI',
      '4. rezervasyon yokken davranis degismiyor (tarih dahil)');

    // ---------------- 5) negatif kontrol ----------------
    // Tarih satiri A1 govdelerinden cikarilirsa 2b DUSMELI; dusmuyorsa
    // yukaridaki olcum bir sey olcmuyor demektir.
    d(['exec', PG, 'createdb', '-U', 'postgres', 'negatif']);
    psql('negatif', TEMEL + A1_BAGIMLILIKLARI);
    psql('negatif', readFileSync(kok + 'docs/kurulum/2026-09-17-stok-guncelleme-tarihi.sql', 'utf8'));
    psql('negatif', a1.replace(/,\s*\n\s*guncelleme_tarihi = now\(\)/g, '')
                      .replace(/,\s*\n\s*guncelleme_tarihi = now\(\);/g, ';'));
    psql('negatif', TOHUM);
    rolle('negatif', `select public.stok_ekle('BIRA','810_CSM302','810',-1);`);
    sonuc(tarih('negatif', '810_CSM302') === 'ESKI' && miktar('negatif', '810_CSM302') === '9.000',
      '5. NEGATIF KONTROL: tarih satiri cikarilinca olcum DUSUYOR (test bos degil)');
  } finally {
    temizle();
  }

  console.log(`\nSIRA TESTI SONUC: ${ok} OK / ${fail} FAIL`);
  process.exitCode = fail ? 1 : 0;
}

main().catch((e) => { console.error(e); temizle(); process.exitCode = 1; });
