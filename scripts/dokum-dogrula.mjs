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
//   node scripts/dokum-dogrula.mjs docs/kurulum/2026-09-06-sema-dokumu.sql
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

// ---------------------------------------------------------------------------
// BAYT SAGLIGI — yuklemeden ONCE
// ---------------------------------------------------------------------------
// pg_dump Linux konteynerinde calisir ve UTF-8 + LF yazar. Dosya baska bir
// sekilde geldiyse arada bir kabuk METIN MODUNDA yazmis demektir ve govdeler
// sessizce degismistir: fonksiyon govdelerinin satir sonlari (LF / CRLF /
// karisik) prosrc icinde AYNEN saklanir. Boyle bir dosya yuklenir, hicbir
// hata vermez ve md5 karsilastirmasinda "govde farkli" olarak gorunur --
// yani gercek bir sapma gibi. Bu yuzden burada durup acikca soyluyoruz.
{
  const ham = readFileSync(dokumYolu);
  const bom = ham.length >= 2 && ((ham[0] === 0xff && ham[1] === 0xfe)
    || (ham[0] === 0xfe && ham[1] === 0xff)) ? 'UTF-16'
    : (ham.length >= 3 && ham[0] === 0xef && ham[1] === 0xbb && ham[2] === 0xbf) ? 'UTF-8 BOM'
    : null;
  const metin = ham.toString('latin1');
  const crlf = (metin.match(/\r\n/g) || []).length;
  const lf = (metin.match(/\n/g) || []).length;

  // KARISIK satir sonu NORMALDIR ve beklenir: uretimdeki fonksiyon govdelerinin
  // bir kismi CRLF tasiyor (Windows'tan SQL Editor'e yapistirilmis) ve pg_dump
  // onlari AYNEN yazar. Bozulmanin isareti karisiklik degil, TEKDUZELIK'tir:
  // her satir sonunun CRLF olmasi, arada metin modunda yazan bir kabuk oldugunu
  // gosterir -- o kabuk govdelerdeki karisimi da ezmistir.
  const hepsiCRLF = lf > 0 && crlf === lf;

  if (bom || hepsiCRLF) {
    console.error('DOSYA BOZUK: dokum kabuk tarafindan yeniden yazilmis.\n');
    if (bom) console.error('  * Kodlama  : ' + bom + ' (pg_dump UTF-8 yazar)');
    if (hepsiCRLF) console.error('  * Satir sonu: ' + crlf + ' satirin ' + lf + "'i CRLF."
      + ' Tekduze CRLF, kabugun metin modunda yazdigi anlamina gelir;'
      + '\n                fonksiyon govdelerindeki LF/CRLF karisimi ezilmistir.');
    console.error('\nSebep: PowerShell yonlendirmesi ( > ) ciktiyi metin olarak yazar;'
      + '\nkodlamayi ve satir sonlarini degistirir. Fonksiyon govdelerindeki'
      + '\nsatir sonu karisimi geri donusu olmayan sekilde ezilir.'
      + '\n\nCozum: dokumu kabuk yonlendirmesi OLMADAN, pg_dump -f ile al.'
      + '\nParola URI ye degil PGPASSWORD e verilir (percent-encode gerekmez);'
      + '\nPowerShell de TEK tirnak kullan, cift tirnakta $ degisken sayilir.'
      + '\nphase0_private semasini da al: tetikleyiciler oradaki fonksiyonlari'
      + '\ncagirir, yoksa hicbiri yuklenmez.'
      + '\n\n  docker run --rm -e PGPASSWORD=\'PAROLA\' \\'
      + '\n    -v "' + kok.replace(/\//g, '\\') + 'docs\\kurulum:/out" postgres:17 \\'
      + '\n    pg_dump -h <pooler-host> -p 5432 -U postgres.<proje-ref> -d postgres \\'
      + '\n    --schema-only --schema=public --schema=phase0_private --no-owner \\'
      + '\n    -f /out/<tarih>-sema-dokumu.sql'
      + '\n\nAyrinti: docs/kurulum/2026-09-06-staging-branch-kurulum.md, bolum 3.2');
    process.exit(1);
  }
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
// "schema public already exists" ZARARSIZDIR: public semasi her PostgreSQL
// veritabaninda hazir gelir, dokum ise onu olusturmayi dener. Beyaz listeye
// aliyoruz ki gercek bir hata cikarsa goze carpsin.
const zararsiz = [/schema "public" already exists/];
const hatalar = r.err.split('\n')
  .filter((l) => l.startsWith('ERROR:'))
  .filter((l) => !zararsiz.some((z) => z.test(l)));
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
