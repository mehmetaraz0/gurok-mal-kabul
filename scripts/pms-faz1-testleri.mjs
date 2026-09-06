// ============================================================================
// PMS FAZ 1 / ADIM 1 — SÖZLEŞME TESTİ KOŞUCUSU
// ============================================================================
// Tek kullanımlık PostgreSQL konteynerinde şu sırayla çalışır:
//   1) Supabase iskelesi (roller, auth.uid(), extensions)
//   2) ÜRETİM ŞEMA DÖKÜMÜ — bayt-birebir doğrulanmış kopya
//   3) PMS Faz 1 migration ADAYI
//   4) Sözleşme testleri
//
// Neden üretim dökümü: testler sentetik bir taklit üzerinde değil, Phase 0
// politikaları ve gerçek yetki motoru devredeyken koşar. Sentetik fixture
// üzerinde geçip üretimde kırılan bir test, test değildir.
//
// ÜRETİM VERİTABANINA BAĞLANMAZ. Yalnızca yerel dosya + Docker.
// Kullanım: node scripts/pms-faz1-testleri.mjs
import { spawnSync } from 'node:child_process';
import { readFileSync, existsSync } from 'node:fs';
import { setTimeout as bekle } from 'node:timers/promises';

const kok = new URL('..', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const DOKUM = kok + 'docs/kurulum/2026-09-06-sema-dokumu.sql';
const MIGRATION = kok + 'docs/kurulum/2026-09-06-pms-faz1-oda-tipleri-odalar.sql';
const TESTLER = kok + 'scripts/pms-faz1-testleri.sql';

for (const f of [DOKUM, MIGRATION, TESTLER]) {
  if (!existsSync(f)) { console.error('Dosya yok: ' + f); process.exit(1); }
}

const konteyner = 'pms-faz1-test';
const psql = ['exec', '-i', konteyner, 'psql', '-X', '-U', 'postgres', '-d', 'pms_test'];

function docker(args, girdi) {
  const r = spawnSync('docker', args, {
    input: girdi, encoding: 'utf8', timeout: 300000, maxBuffer: 64 * 1024 * 1024,
  });
  return { ok: !r.error && r.status === 0, out: r.stdout || '', err: r.error?.message || r.stderr || '' };
}
function temizle() { spawnSync('docker', ['rm', '-f', konteyner], { encoding: 'utf8' }); }
function hatalari(s) {
  return s.split('\n').filter((l) => l.startsWith('ERROR:'))
    .filter((l) => !/schema "public" already exists/.test(l));
}
function bitir(kod) { temizle(); process.exit(kod); }

temizle();
let r = docker(['run', '--detach', '--rm', '--network', 'none', '--name', konteyner,
  '--tmpfs', '/var/lib/postgresql/data', '-e', 'POSTGRES_HOST_AUTH_METHOD=trust', 'postgres:17']);
if (!r.ok) { console.error('Konteyner baslatilamadi: ' + r.err.slice(0, 300)); process.exit(1); }

for (let i = 0; i < 60; i++) {
  if (spawnSync('docker', ['exec', konteyner, 'pg_isready', '-U', 'postgres']).status === 0) break;
  await bekle(1000);
}
docker(['exec', konteyner, 'createdb', '-U', 'postgres', 'pms_test']);

r = docker([...psql, '-v', 'ON_ERROR_STOP=1'], readFileSync(kok + 'scripts/supabase-shim.sql', 'utf8'));
if (!r.ok) { console.error('Supabase iskelesi kurulamadi:\n' + r.err.slice(0, 400)); bitir(1); }
console.log('1) Supabase iskelesi   : kuruldu');

r = docker(psql, readFileSync(DOKUM, 'utf8'));
let h = hatalari(r.err);
console.log('2) Uretim kopyasi      : ' + (h.length ? h.length + ' HATA' : 'hatasiz'));
if (h.length) { console.error(h.slice(0, 5).join('\n')); bitir(1); }

// Migration IKI KEZ uygulanir: ikinci kosum tekrar calistirilabilirligi kanitlar.
const migSql = readFileSync(MIGRATION, 'utf8');
r = docker([...psql, '-v', 'ON_ERROR_STOP=1'], migSql);
if (!r.ok) {
  console.error('3) PMS migration       : BASARISIZ\n'
    + r.err.split('\n').filter((l) => l.trim()).slice(-12).join('\n'));
  bitir(1);
}
console.log('3) PMS migration       : uygulandi');

r = docker([...psql, '-v', 'ON_ERROR_STOP=1'], migSql);
if (!r.ok) {
  console.error('4) Tekrar uygulama     : BASARISIZ (migration idempotent degil)\n'
    + r.err.split('\n').filter((l) => l.trim()).slice(-12).join('\n'));
  bitir(1);
}
console.log('4) Tekrar uygulama     : gecti (idempotent)');

r = docker([...psql, '-v', 'ON_ERROR_STOP=1'], readFileSync(TESTLER, 'utf8'));
console.log('\n5) Sozlesme testleri:\n');
if (!r.ok) {
  const satirlar = r.err.split('\n').filter((l) => l.trim());
  console.error(satirlar.filter((l) => /BASARISIZ|ERROR|DETAIL/.test(l)).slice(0, 8).join('\n')
    || satirlar.slice(-10).join('\n'));
  console.log('\n' + '='.repeat(66));
  console.log('SONUC: PMS FAZ 1 TESTLERI BASARISIZ');
  console.log('='.repeat(66));
  bitir(1);
}
console.log(r.out.trimEnd().split('\n').filter((l) => l.trim()).slice(-4).join('\n'));
console.log('\n' + '='.repeat(66));
console.log('SONUC: PMS FAZ 1 / ADIM 1 SOZLESME TESTLERI GECTI');
console.log('       A-G + capraz otel + kapasite + idempotency');
console.log('='.repeat(66));
bitir(0);
