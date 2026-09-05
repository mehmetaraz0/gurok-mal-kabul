// ============================================================================
// ŞEMA DÖKÜMÜ DOĞRULAMA
// ============================================================================
// Bir şema dökümünü tek kullanımlık PostgreSQL konteynerine yükler ve
// docs/kurulum/2026-09-06-staging-esitlik-dogrulama.sql ile üretime karşı
// karşılaştırır.
//
// NEDEN: Supabase preview branch'leri şemayı supabase/migrations dosyalarından
// kurar. O dosyalar üretimi birebir üretmiyorsa branch de üretmez ve orada
// alınan "Phase 0 geçti" sonucu YANILTICIDIR. Bu betik, branch açmadan ve
// para harcamadan, dökümün gerçekten yeterli olup olmadığını yerelde kanıtlar.
//
// KULLANIM:
//   node scripts/dokum-dogrula.mjs docs/kurulum/01-sema-dokumu.sql
//
// ÇIKIŞ KODU: 0 = döküm üretimi temsil ediyor, 1 = sapma var (veya hata).
//
// Üretim veritabanına BAĞLANMAZ. Yalnızca yerel dosya + Docker.
// ============================================================================
import { spawnSync } from 'node:child_process';
import { readFileSync, existsSync } from 'node:fs';
import { setTimeout as bekle } from 'node:timers/promises';

const kok = new URL('..', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const dokumYolu = process.argv[2];

if (!dokumYolu) {
  console.error('Kullanim: node scripts/dokum-dogrula.mjs <dokum.sql>');
  process.exit(1);
}
if (!existsSync(dokumYolu)) {
  console.error('Dosya bulunamadi: ' + dokumYolu);
  process.exit(1);
}

const konteyner = 'dokum-dogrula';
const psql = ['exec', '-i', konteyner, 'psql', '-X', '-U', 'postgres', '-d', 'dokum_test'];

function docker(args, girdi) {
  const r = spawnSync('docker', args, {
    input: girdi, encoding: 'utf8', timeout: 300000, maxBuffer: 64 * 1024 * 1024,
  });
  return { ok: !r.error && r.status === 0, out: r.stdout || '', err: r.error?.message || r.stderr || '' };
}

function temizle() { spawnSync('docker', ['rm', '-f', konteyner], { encoding: 'utf8' }); }

temizle();
let r = docker(['run', '--detach', '--rm', '--network', 'none', '--name', konteyner,
  '--tmpfs', '/var/lib/postgresql/data', '-e', 'POSTGRES_HOST_AUTH_METHOD=trust', 'postgres:17']);
if (!r.ok) { console.error('Konteyner baslatilamadi: ' + r.err.slice(0, 300)); process.exit(1); }

for (let i = 0; i < 60; i++) {
  if (spawnSync('docker', ['exec', konteyner, 'pg_isready', '-U', 'postgres']).status === 0) break;
  await bekle(1000);
}
docker(['exec', konteyner, 'createdb', '-U', 'postgres', 'dokum_test']);

// 1) Supabase iskelesi. Bu asamada hata olursa dokumun sucu yok.
r = docker([...psql, '-v', 'ON_ERROR_STOP=1'], readFileSync(kok + 'scripts/supabase-shim.sql', 'utf8'));
if (!r.ok) {
  console.error('Supabase shim yuklenemedi:\n' + r.err.split('\n').filter((l) => l.includes('ERROR')).slice(0, 3).join('\n'));
  temizle(); process.exit(1);
}
console.log('1) Supabase iskelesi   : kuruldu');

// 2) Dokum. ON_ERROR_STOP KULLANILMAZ: amac dokumun ne kadarinin yuklendigini
//    gormek; ilk hatada durursak eksikligin boyutunu olcemeyiz.
r = docker(psql, readFileSync(dokumYolu, 'utf8'));
const hatalar = r.err.split('\n').filter((l) => l.startsWith('ERROR:'));
console.log('2) Dokum yuklendi      : ' + (hatalar.length === 0
  ? 'hatasiz'
  : hatalar.length + ' HATA (ilk 5 asagida)'));
for (const h of hatalar.slice(0, 5)) console.log('   ' + h.slice(0, 160));

// 3) Uretime karsi esitlik.
r = docker([...psql, '-v', 'ON_ERROR_STOP=1'],
  readFileSync(kok + 'docs/kurulum/2026-09-06-staging-esitlik-dogrulama.sql', 'utf8'));
if (!r.ok) {
  console.error('Esitlik sorgusu calismadi:\n' + r.err.slice(0, 400));
  temizle(); process.exit(1);
}
console.log('\n3) Uretime karsi esitlik:\n');
console.log(r.out.trimEnd());

const sapmaVar = /SAPMA/.test(r.out);
console.log('\n' + '='.repeat(70));
console.log(sapmaVar
  ? 'SONUC: DOKUM YETERSIZ. Bu dokumden kurulan bir staging uretimi temsil\n'
    + '       etmez; Phase 0 orada test edilmemelidir.'
  : 'SONUC: Dokum uretimi temsil ediyor. Staging tabani olarak kullanilabilir.');
console.log('='.repeat(70));

temizle();
process.exit(sapmaVar || hatalar.length > 0 ? 1 : 0);
