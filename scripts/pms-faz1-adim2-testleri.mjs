// ============================================================================
// PMS FAZ 1 / ADIM 2 — SÖZLEŞME TESTİ KOŞUCUSU
// ============================================================================
// Tek kullanımlık PostgreSQL konteynerinde:
//   1) Supabase iskelesi
//   2) ÜRETİM ŞEMA DÖKÜMÜ (bayt-birebir doğrulanmış kopya)
//   3) PMS Adım 1 migration
//   4) PMS Adım 2 migration  (iki kez — idempotency)
//   5) Sözleşme testleri
//   6) EŞZAMANLILIK testi — iki bağımsız transaction aynı son odayı satmaya
//      çalışır; yalnız biri commit etmelidir.
//
// (6) ayrı bir koşum gerektirir: tek psql oturumunda eşzamanlılık simüle
// edilemez. Aşırı satış engelinin ASIL sınavı budur — tek oturumlu testler
// yarış koşulunu göremez.
//
// ÜRETİM VERİTABANINA BAĞLANMAZ. Yalnızca yerel dosya + Docker.
import { spawn, spawnSync } from 'node:child_process';
import { readFileSync, existsSync } from 'node:fs';
import { setTimeout as bekle } from 'node:timers/promises';

const kok = new URL('..', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const DOSYALAR = {
  shim:   kok + 'scripts/supabase-shim.sql',
  dokum:  kok + 'docs/kurulum/2026-09-06-sema-dokumu.sql',
  adim1:  kok + 'docs/kurulum/2026-09-06-pms-faz1-oda-tipleri-odalar.sql',
  adim2:  kok + 'docs/kurulum/2026-09-06-pms-faz1-adim2-misafir-rezervasyon.sql',
  test:   kok + 'scripts/pms-faz1-adim2-testleri.sql',
};
for (const [ad, yol] of Object.entries(DOSYALAR)) {
  if (!existsSync(yol)) { console.error('Dosya yok (' + ad + '): ' + yol); process.exit(1); }
}

const konteyner = 'pms-adim2-test';
const psqlArgs = ['exec', '-i', konteyner, 'psql', '-X', '-U', 'postgres', '-d', 'pms2'];

function docker(args, girdi) {
  const r = spawnSync('docker', args, {
    input: girdi, encoding: 'utf8', timeout: 300000, maxBuffer: 64 * 1024 * 1024,
  });
  return { ok: !r.error && r.status === 0, out: r.stdout || '', err: r.error?.message || r.stderr || '' };
}
function temizle() { spawnSync('docker', ['rm', '-f', konteyner], { encoding: 'utf8' }); }
function bitir(kod) { temizle(); process.exit(kod); }
function hatalari(s) {
  return s.split('\n').filter((l) => l.startsWith('ERROR:'))
    .filter((l) => !/schema "public" already exists/.test(l));
}
const oku = (ad) => readFileSync(DOSYALAR[ad], 'utf8');

temizle();
let r = docker(['run', '--detach', '--rm', '--network', 'none', '--name', konteyner,
  '--tmpfs', '/var/lib/postgresql/data', '-e', 'POSTGRES_HOST_AUTH_METHOD=trust', 'postgres:17']);
if (!r.ok) { console.error('Konteyner baslatilamadi: ' + r.err.slice(0, 300)); process.exit(1); }
for (let i = 0; i < 60; i++) {
  if (spawnSync('docker', ['exec', konteyner, 'pg_isready', '-U', 'postgres']).status === 0) break;
  await bekle(1000);
}
docker(['exec', konteyner, 'createdb', '-U', 'postgres', 'pms2']);

r = docker([...psqlArgs, '-v', 'ON_ERROR_STOP=1'], oku('shim'));
if (!r.ok) { console.error('Iskele kurulamadi:\n' + r.err.slice(0, 400)); bitir(1); }
console.log('1) Supabase iskelesi   : kuruldu');

r = docker(psqlArgs, oku('dokum'));
let h = hatalari(r.err);
console.log('2) Uretim kopyasi      : ' + (h.length ? h.length + ' HATA' : 'hatasiz'));
if (h.length) { console.error(h.slice(0, 5).join('\n')); bitir(1); }

r = docker([...psqlArgs, '-v', 'ON_ERROR_STOP=1'], oku('adim1'));
if (!r.ok) { console.error('3) Adim 1 migration    : BASARISIZ\n'
  + r.err.split('\n').filter((l) => l.trim()).slice(-10).join('\n')); bitir(1); }
console.log('3) Adim 1 migration    : uygulandi');

const adim2 = oku('adim2');
r = docker([...psqlArgs, '-v', 'ON_ERROR_STOP=1'], adim2);
if (!r.ok) { console.error('4) Adim 2 migration    : BASARISIZ\n'
  + r.err.split('\n').filter((l) => l.trim()).slice(-14).join('\n')); bitir(1); }
console.log('4) Adim 2 migration    : uygulandi');

r = docker([...psqlArgs, '-v', 'ON_ERROR_STOP=1'], adim2);
if (!r.ok) { console.error('5) Tekrar uygulama     : BASARISIZ (idempotent degil)\n'
  + r.err.split('\n').filter((l) => l.trim()).slice(-14).join('\n')); bitir(1); }
console.log('5) Tekrar uygulama     : gecti (idempotent)');

r = docker([...psqlArgs, '-v', 'ON_ERROR_STOP=1'], oku('test'));
if (!r.ok) {
  const satirlar = r.err.split('\n').filter((l) => l.trim());
  console.error('\n6) Sozlesme testleri   : BASARISIZ\n'
    + (satirlar.filter((l) => /BASARISIZ|ERROR|DETAIL/.test(l)).slice(0, 8).join('\n')
       || satirlar.slice(-10).join('\n')));
  bitir(1);
}
console.log('6) Sozlesme testleri   : gecti');

// ---------------------------------------------------------------------------
// 7) ESZAMANLILIK — asiri satis engelinin ASIL sinavi
// ---------------------------------------------------------------------------
// Tek odali bir tipte, iki bagimsiz transaction ayni tarihler icin ayni anda
// rezervasyon acmaya calisir. Tip satiri `for update` ile kilitlendigi icin
// ikincisi birincisi bitene kadar BEKLEMELI, sonra guncel sayiyi gorup
// REDDEDILMELIDIR. Kilit olmasaydi ikisi de "0/1 dolu" gorup ikisi de gecerdi.
function sorgu(sql) {
  return spawnSync('docker', [...psqlArgs, '-At', '-c', sql], { encoding: 'utf8' }).stdout || '';
}

// Temiz zemin: yeni tip, TEK oda, hic rezervasyon yok.
docker([...psqlArgs, '-v', 'ON_ERROR_STOP=1'], `
insert into public.pms_oda_tipleri (id, otel_id, kod, ad, azami_kisi, azami_yetiskin)
values ('d0000000-0000-0000-0000-0000000ccc10','810','CNC','Eszamanlilik',2,2)
on conflict (id) do nothing;
insert into public.pms_odalar (id, otel_id, oda_tipi_id, oda_no)
values ('e0000000-0000-0000-0000-0000000ccc10','810','d0000000-0000-0000-0000-0000000ccc10','CNC-1')
on conflict (id) do nothing;`);

const ekle = `insert into public.pms_rezervasyonlar
  (otel_id, misafir_id, oda_tipi_id, giris_tarihi, cikis_tarihi, durum)
  values ('810','f0000000-0000-0000-0000-000000000810','d0000000-0000-0000-0000-0000000ccc10',
          '2026-11-01','2026-11-05','onaylandi');`;

// ON_ERROR_STOP ZORUNLU: psql varsayilan olarak ifade hatasindan sonra devam
// eder ve 0 ile cikar. O hâlde "cikis kodu 0" hiçbir sey kanitlamaz — B
// reddedilmis olsa bile basarili gorunur. Bayragi vererek cikis kodunu
// anlamli hale getiriyoruz.
const psqlKatiArgs = [...psqlArgs, '-v', 'ON_ERROR_STOP=1'];

const a = spawn('docker', psqlKatiArgs, { stdio: ['pipe', 'pipe', 'pipe'] });
let aCikti = '', aHata = '';
a.stdout.on('data', (d) => { aCikti += d; });
a.stderr.on('data', (d) => { aHata += d; });
const aKapandi = new Promise((c) => a.on('close', c));

const kilitTutuldu = new Promise((coz, red) => {
  const zaman = setTimeout(() => red(new Error('eszamanlilik bariyeri zaman asimi')), 20000);
  a.stdout.on('data', () => {
    if (aCikti.includes('PMS2_KILIT')) { clearTimeout(zaman); coz(); }
  });
  a.on('close', () => { clearTimeout(zaman); red(new Error(aHata || 'A bariyerden once durdu')); });
});
a.stdin.write(`begin;\n${ekle}\n\\echo PMS2_KILIT\n`);

let sonuc = 0;
try {
  await kilitTutuldu;

  const b = spawn('docker', psqlKatiArgs, { stdio: ['pipe', 'pipe', 'pipe'] });
  let bHata = '';
  b.stdout.resume();
  b.stderr.on('data', (d) => { bHata += d; });
  const bKapandi = new Promise((c) => b.on('close', c));
  b.stdin.end(`set application_name='pms2-ikinci';\n${ekle}\n`);

  let bekliyor = false;
  for (let i = 0; i < 60; i++) {
    if (sorgu("select count(*) from pg_stat_activity where application_name='pms2-ikinci' and wait_event_type='Lock';").trim() === '1') {
      bekliyor = true; break;
    }
    await bekle(100);
  }
  a.stdin.end('commit;\n');
  const aKod = await aKapandi;
  const bKod = await bKapandi;
  const kalan = sorgu("select count(*) from public.pms_rezervasyonlar where oda_tipi_id='d0000000-0000-0000-0000-0000000ccc10';").trim();

  const kontroller = [
    [aKod === 0, 'A commit etmeliydi', 'A commit etti'],
    [bekliyor, 'B, A nin kilidini BEKLEMELIYDI (kilit yok -> yaris kosulu)', 'B kilidi bekledi'],
    [bKod !== 0, 'B REDDEDILMELIYDI (ikisi de gecti -> asiri satis)', 'B reddedildi'],
    [/[Aa]siri satis/.test(bHata), 'B, asiri satis hatasiyla reddedilmeliydi', 'red sebebi asiri satis'],
    [kalan === '1', 'tam 1 rezervasyon kalmaliydi, kalan: ' + kalan, 'tam 1 rezervasyon commit oldu'],
  ];
  console.log('\n7) Eszamanlilik testi:');
  for (const [gecti, hataMsg, okMsg] of kontroller) {
    console.log((gecti ? '   OK   ' : '   HATA ') + (gecti ? okMsg : hataMsg));
    if (!gecti) sonuc = 1;
  }
} catch (e) {
  console.error('\n7) Eszamanlilik testi  : ' + e.message);
  sonuc = 1;
}

console.log('\n' + '='.repeat(70));
console.log(sonuc === 0
  ? 'SONUC: PMS FAZ 1 / ADIM 2 TESTLERI GECTI\n'
    + '       misafir + kimlik (KVKK ayrimi) + rezervasyon + oda atamasi\n'
    + '       capraz otel, kapasite, asiri satis, cakisma, eszamanlilik'
  : 'SONUC: PMS FAZ 1 / ADIM 2 TESTLERI BASARISIZ');
console.log('='.repeat(70));
bitir(sonuc);
