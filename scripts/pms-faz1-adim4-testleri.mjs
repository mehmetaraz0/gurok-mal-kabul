// ============================================================================
// PMS FAZ 1 / ADIM 4 — FOLIO SÖZLEŞME TESTİ KOŞUCUSU
// ============================================================================
// Tek kullanımlık PostgreSQL konteynerinde:
//   1) Supabase iskelesi
//   2) ÜRETİM ŞEMA DÖKÜMÜ (bayt-birebir doğrulanmış kopya)
//   3) Adım 1 → 2 → 3 → 4 migration (Adım 4 iki kez — idempotency)
//   4) Sözleşme testleri (gecelik işleme, bar köprüsü, ödeme, kapatma, yetki)
//   5) EŞZAMANLILIK — iki oturum aynı geceleri aynı anda işlemeye çalışır;
//      mükerrer borç oluşmamalı.
//
// ÜRETİM VERİTABANINA BAĞLANMAZ. Yalnızca yerel dosya + Docker.
// Kullanım: node scripts/pms-faz1-adim4-testleri.mjs [--mig <sql-yolu>]
// --mig: sabotaj testi için migration'ı geçici değiştirilmiş kopyayla koşturur.
import { spawn, spawnSync } from 'node:child_process';
import { readFileSync, existsSync } from 'node:fs';
import { setTimeout as bekle } from 'node:timers/promises';

const kok = new URL('..', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const args = process.argv.slice(2);
const migArg = args.includes('--mig') ? args[args.indexOf('--mig') + 1] : null;

const DOSYALAR = {
  shim:  kok + 'scripts/supabase-shim.sql',
  dokum: kok + 'docs/kurulum/2026-09-06-sema-dokumu.sql',
  adim1: kok + 'docs/kurulum/2026-09-06-pms-faz1-oda-tipleri-odalar.sql',
  adim2: kok + 'docs/kurulum/2026-09-06-pms-faz1-adim2-misafir-rezervasyon.sql',
  adim3: kok + 'docs/kurulum/2026-09-06-pms-faz1-adim3-checkin-checkout.sql',
  adim4: migArg || kok + 'docs/kurulum/2026-09-06-pms-faz1-adim4-folio.sql',
  test:  kok + 'scripts/pms-faz1-adim4-testleri.sql',
};
for (const [ad, yol] of Object.entries(DOSYALAR)) {
  if (!existsSync(yol)) { console.error('Dosya yok (' + ad + '): ' + yol); process.exit(1); }
}

const konteyner = 'pms-adim4-test';
const psqlArgs = ['exec', '-i', konteyner, 'psql', '-X', '-U', 'postgres', '-d', 'pms4'];
// ON_ERROR_STOP zorunlu: psql varsayilan olarak ifade hatasindan sonra devam
// eder ve 0 ile cikar; o hâlde "cikis kodu 0" hicbir sey kanitlamaz.
const psqlKatiArgs = [...psqlArgs, '-v', 'ON_ERROR_STOP=1'];

function docker(a, girdi) {
  const r = spawnSync('docker', a, {
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
function sorgu(sql) {
  return spawnSync('docker', [...psqlArgs, '-At', '-c', sql], { encoding: 'utf8' }).stdout || '';
}

temizle();
let r = docker(['run', '--detach', '--rm', '--network', 'none', '--name', konteyner,
  '--tmpfs', '/var/lib/postgresql/data', '-e', 'POSTGRES_HOST_AUTH_METHOD=trust', 'postgres:17']);
if (!r.ok) { console.error('Konteyner baslatilamadi: ' + r.err.slice(0, 300)); process.exit(1); }
for (let i = 0; i < 60; i++) {
  if (spawnSync('docker', ['exec', konteyner, 'pg_isready', '-U', 'postgres']).status === 0) break;
  await bekle(1000);
}
docker(['exec', konteyner, 'createdb', '-U', 'postgres', 'pms4']);

r = docker(psqlKatiArgs, oku('shim'));
if (!r.ok) { console.error('Iskele kurulamadi:\n' + r.err.slice(0, 400)); bitir(1); }
console.log('1) Supabase iskelesi   : kuruldu');

r = docker(psqlArgs, oku('dokum'));
let h = hatalari(r.err);
console.log('2) Uretim kopyasi      : ' + (h.length ? h.length + ' HATA' : 'hatasiz'));
if (h.length) { console.error(h.slice(0, 5).join('\n')); bitir(1); }

for (const [no, ad] of [[3, 'adim1'], [4, 'adim2'], [5, 'adim3']]) {
  r = docker(psqlKatiArgs, oku(ad));
  if (!r.ok) {
    console.error(no + ') ' + ad + ' migration : BASARISIZ\n'
      + r.err.split('\n').filter((l) => l.trim()).slice(-12).join('\n'));
    bitir(1);
  }
  console.log(no + ') ' + ad.padEnd(6) + ' migration : uygulandi');
}

const adim4 = oku('adim4');
r = docker(psqlKatiArgs, adim4);
if (!r.ok) {
  console.error('6) Adim 4 migration    : BASARISIZ\n'
    + r.err.split('\n').filter((l) => l.trim()).slice(-14).join('\n'));
  bitir(1);
}
console.log('6) Adim 4 migration    : uygulandi');

r = docker(psqlKatiArgs, adim4);
if (!r.ok) {
  console.error('7) Tekrar uygulama     : BASARISIZ (idempotent degil)\n'
    + r.err.split('\n').filter((l) => l.trim()).slice(-14).join('\n'));
  bitir(1);
}
console.log('7) Tekrar uygulama     : gecti (idempotent)');

r = docker(psqlKatiArgs, oku('test'));
if (!r.ok) {
  const satirlar = r.err.split('\n').filter((l) => l.trim());
  console.error('\n8) Sozlesme testleri   : BASARISIZ\n'
    + (satirlar.filter((l) => /BASARISIZ|ERROR|DETAIL/.test(l)).slice(0, 8).join('\n')
       || satirlar.slice(-10).join('\n')));
  bitir(1);
}
console.log('8) Sozlesme testleri   : gecti');

// ---------------------------------------------------------------------------
// 9) ESZAMANLILIK — ayni geceleri iki oturum ayni anda islemeye calisir
// ---------------------------------------------------------------------------
// Gecelik isleme idempotency'si (folio, gece) benzersiz index'ine dayanir.
// Tek oturumlu test bunu kanitlamaz: yaris kosulunda iki oturum ayni geceyi
// gorup ikisi de yazmaya calisabilir. Beklenen: biri yazar, digeri ya bekler
// ve 0 ekler ya da benzersizlik ihlaliyle duser -- HER IKI HALDE de mukerrer
// borc olusmaz.
const zemin = `
select set_config('request.jwt.claim.role','authenticated',false);
select set_config('request.jwt.claim.sub','a0000000-0000-0000-0000-000000000001',false);
insert into public.pms_rezervasyonlar
  (id, otel_id, misafir_id, oda_tipi_id, giris_tarihi, cikis_tarihi, durum, gecelik_fiyat)
values ('11000000-0000-0000-0000-0000000400c1','810','f0000000-0000-0000-0000-000000040001',
        'd0000000-0000-0000-0000-000000040010', current_date - 2, current_date + 1,
        'onaylandi', 500.00)
on conflict (id) do nothing;`;
r = docker(psqlKatiArgs, zemin);
if (!r.ok) {
  console.error('9) Eszamanlilik zemini : BASARISIZ\n'
    + r.err.split('\n').filter((l) => l.trim()).slice(-8).join('\n'));
  bitir(1);
}
// Check-in ayri oturumda (RPC yolu).
r = docker(psqlKatiArgs, `
set role authenticated;
select set_config('request.jwt.claim.role','authenticated',false);
select set_config('request.jwt.claim.sub','a0000000-0000-0000-0000-000000000001',false);
select public.pms_check_in('11000000-0000-0000-0000-0000000400c1',
                           'e0000000-0000-0000-0000-000000040103');`);
if (!r.ok) {
  console.error('9) Eszamanlilik check-in: BASARISIZ\n'
    + r.err.split('\n').filter((l) => l.trim()).slice(-8).join('\n'));
  bitir(1);
}

const isle = `set role authenticated;
select set_config('request.jwt.claim.role','authenticated',false);
select set_config('request.jwt.claim.sub','a0000000-0000-0000-0000-000000000001',false);
select public.pms_folio_oda_ucreti_isle('11000000-0000-0000-0000-0000000400c1');`;

const a = spawn('docker', psqlKatiArgs, { stdio: ['pipe', 'pipe', 'pipe'] });
let aCikti = '', aHata = '';
a.stdout.on('data', (d) => { aCikti += d; });
a.stderr.on('data', (d) => { aHata += d; });
const aKapandi = new Promise((c) => a.on('close', c));
const kilitTutuldu = new Promise((coz, red) => {
  const z = setTimeout(() => red(new Error('bariyer zaman asimi')), 20000);
  a.stdout.on('data', () => { if (aCikti.includes('PMS4_KILIT')) { clearTimeout(z); coz(); } });
  a.on('close', () => { clearTimeout(z); red(new Error(aHata || 'A bariyerden once durdu')); });
});
a.stdin.write(`begin;\n${isle}\n\\echo PMS4_KILIT\n`);

let sonuc = 0;
try {
  await kilitTutuldu;
  const b = spawn('docker', psqlKatiArgs, { stdio: ['pipe', 'pipe', 'pipe'] });
  let bHata = '';
  b.stdout.resume();
  b.stderr.on('data', (d) => { bHata += d; });
  const bKapandi = new Promise((c) => b.on('close', c));
  b.stdin.end(`set application_name='pms4-ikinci';\n${isle}\n`);

  let bekliyor = false;
  for (let i = 0; i < 60; i++) {
    if (sorgu("select count(*) from pg_stat_activity where application_name='pms4-ikinci' and wait_event_type='Lock';").trim() === '1') {
      bekliyor = true; break;
    }
    await bekle(100);
  }
  a.stdin.end('commit;\n');
  const aKod = await aKapandi;
  await bKapandi;

  const gece = sorgu(`select count(*) from public.pms_folio_hareketleri h
     join public.pms_folyolar f on f.id = h.folio_id
    where f.rezervasyon_id='11000000-0000-0000-0000-0000000400c1'
      and h.tip='oda_ucreti';`).trim();
  const tutar = sorgu(`select coalesce(sum(h.tutar),0)::text from public.pms_folio_hareketleri h
     join public.pms_folyolar f on f.id = h.folio_id
    where f.rezervasyon_id='11000000-0000-0000-0000-0000000400c1';`).trim();

  const kontroller = [
    [aKod === 0, 'A commit etmeliydi', 'A commit etti'],
    [bekliyor, 'B, A nin kilidini BEKLEMELIYDI (kilit yok -> yaris kosulu)', 'B kilidi bekledi'],
    [gece === '3', 'tam 3 gece olmaliydi, bulunan: ' + gece, 'tam 3 gece islendi'],
    [tutar === '1500.00', 'toplam 1500.00 olmaliydi, bulunan: ' + tutar, 'toplam 1500.00 (mukerrer borc yok)'],
  ];
  console.log('\n9) Eszamanlilik testi (ayni geceler, iki oturum):');
  for (const [gecti, hataMsg, okMsg] of kontroller) {
    console.log((gecti ? '   OK   ' : '   HATA ') + (gecti ? okMsg : hataMsg));
    if (!gecti) sonuc = 1;
  }
} catch (e) {
  console.error('\n9) Eszamanlilik testi  : ' + e.message);
  sonuc = 1;
}

// ---------------------------------------------------------------------------
// 10) KAPANIŞ / ÖDEME YARIŞI — iki oturum, iki yön
// ---------------------------------------------------------------------------
// P0 dersi: kapalı folyo kontrolü KİLİTSİZ yapılırsa READ COMMITTED altında
// yarışı kaybeder. Kapatan işlem folyoyu 'kapali' yapıp commit ederken aynı
// anda başlamış ödeme hâlâ ESKİ satırı ('acik') görür, kontrolden geçer ve
// KAPANMIŞ folyoya yazar; folyo sıfır bakiyeyle kapalı görünürken bakiyesi
// artık sıfır DEĞİLDİR. Aşağıdaki iki test bunun olmadığını ölçer.
function zeminKur(rezId) {
  const q = docker(psqlKatiArgs, `
select set_config('request.jwt.claim.role','authenticated',false);
select set_config('request.jwt.claim.sub','a0000000-0000-0000-0000-000000000001',false);
insert into public.pms_rezervasyonlar
  (id, otel_id, misafir_id, oda_tipi_id, giris_tarihi, cikis_tarihi, durum, gecelik_fiyat)
values ('${rezId}','810','f0000000-0000-0000-0000-000000040001',
        'd0000000-0000-0000-0000-000000040010', current_date + 40, current_date + 42,
        'onaylandi', 100.00)
on conflict (id) do nothing;`);
  if (!q.ok) {
    console.error('10) Yaris zemini       : BASARISIZ\n'
      + q.err.split('\n').filter((l) => l.trim()).slice(-8).join('\n'));
    bitir(1);
  }
  return sorgu(`select id from public.pms_folyolar where rezervasyon_id='${rezId}';`).trim();
}

const rolBasi = `set role authenticated;
select set_config('request.jwt.claim.role','authenticated',false);
select set_config('request.jwt.claim.sub','a0000000-0000-0000-0000-000000000001',false);`;

// B'nin gerçekten KİLİT beklediğini doğrular; beklemiyorsa koruma kilitsizdir.
async function kilitteMi(ad) {
  for (let i = 0; i < 60; i++) {
    if (sorgu(`select count(*) from pg_stat_activity where application_name='${ad}' and wait_event_type='Lock';`).trim() === '1') return true;
    await bekle(100);
  }
  return false;
}

// --- 10a: ÖNCE KAPANIŞ, sonra ödeme -> ödeme REDDEDİLMELİ ---
const folioA = zeminKur('11000000-0000-0000-0000-0000000400c2');
const yarisKontrolleri = [];
try {
  const a2 = spawn('docker', psqlKatiArgs, { stdio: ['pipe', 'pipe', 'pipe'] });
  let a2Cikti = '', a2Hata = '';
  a2.stdout.on('data', (d) => { a2Cikti += d; });
  a2.stderr.on('data', (d) => { a2Hata += d; });
  const a2Kapandi = new Promise((c) => a2.on('close', c));
  const a2Bariyer = new Promise((coz, red) => {
    const z = setTimeout(() => red(new Error('10a bariyer zaman asimi')), 20000);
    a2.stdout.on('data', () => { if (a2Cikti.includes('PMS4_KAPANDI')) { clearTimeout(z); coz(); } });
    a2.on('close', () => { clearTimeout(z); red(new Error(a2Hata || '10a: A bariyerden once durdu')); });
  });
  a2.stdin.write(`begin;\n${rolBasi}\nselect public.pms_folio_kapat('${folioA}');\n\\echo PMS4_KAPANDI\n`);
  await a2Bariyer;

  const b2 = spawn('docker', psqlKatiArgs, { stdio: ['pipe', 'pipe', 'pipe'] });
  let b2Hata = '';
  b2.stdout.resume();
  b2.stderr.on('data', (d) => { b2Hata += d; });
  const b2Kapandi = new Promise((c) => b2.on('close', c));
  b2.stdin.end(`set application_name='pms4-odeme';\n${rolBasi}
insert into public.pms_folio_odemeler (otel_id, folio_id, yontem, tutar)
values ('810','${folioA}','nakit', 250.00);\n`);

  const b2Bekledi = await kilitteMi('pms4-odeme');
  a2.stdin.end('commit;\n');
  const a2Kod = await a2Kapandi;
  const b2Kod = await b2Kapandi;

  const durum = sorgu(`select durum from public.pms_folyolar where id='${folioA}';`).trim();
  const odemeSay = sorgu(`select count(*) from public.pms_folio_odemeler where folio_id='${folioA}';`).trim();
  const bakiye = sorgu(`select bakiye::text from public.pms_folio_ozet where folio_id='${folioA}';`).trim();

  yarisKontrolleri.push(
    [a2Kod === 0, '10a: kapanis commit etmeliydi', '10a kapanis commit etti'],
    [b2Bekledi, '10a: odeme KILIT BEKLEMELIYDI (kilitsiz kontrol -> yaris kosulu)', '10a odeme kilidi bekledi'],
    [b2Kod !== 0 && /Kapali folyoya/.test(b2Hata), '10a: odeme reddedilmeliydi, cikis=' + b2Kod, '10a kapanmis folyoya odeme REDDEDILDI'],
    [durum === 'kapali', '10a: folyo kapali kalmaliydi, bulunan: ' + durum, '10a folyo kapali'],
    [odemeSay === '0', '10a: folyoya odeme SIZDI (' + odemeSay + ' satir)', '10a kapali folyoda odeme yok'],
    [Number(bakiye) === 0, '10a: bakiye 0 olmaliydi, bulunan: ' + bakiye, '10a bakiye 0 (kapanis tutarli)'],
  );
} catch (e) {
  yarisKontrolleri.push([false, '10a: ' + e.message, '']);
}

// --- 10b: ÖNCE ödeme, sonra kapanış -> kapanış REDDEDİLMELİ ---
const folioB = zeminKur('11000000-0000-0000-0000-0000000400c3');
try {
  const a3 = spawn('docker', psqlKatiArgs, { stdio: ['pipe', 'pipe', 'pipe'] });
  let a3Cikti = '', a3Hata = '';
  a3.stdout.on('data', (d) => { a3Cikti += d; });
  a3.stderr.on('data', (d) => { a3Hata += d; });
  const a3Kapandi = new Promise((c) => a3.on('close', c));
  const a3Bariyer = new Promise((coz, red) => {
    const z = setTimeout(() => red(new Error('10b bariyer zaman asimi')), 20000);
    a3.stdout.on('data', () => { if (a3Cikti.includes('PMS4_ODENDI')) { clearTimeout(z); coz(); } });
    a3.on('close', () => { clearTimeout(z); red(new Error(a3Hata || '10b: odeme bariyerden once durdu')); });
  });
  a3.stdin.write(`begin;\n${rolBasi}
insert into public.pms_folio_odemeler (otel_id, folio_id, yontem, tutar)
values ('810','${folioB}','nakit', 300.00);\n\\echo PMS4_ODENDI\n`);
  await a3Bariyer;

  const b3 = spawn('docker', psqlKatiArgs, { stdio: ['pipe', 'pipe', 'pipe'] });
  let b3Hata = '';
  b3.stdout.resume();
  b3.stderr.on('data', (d) => { b3Hata += d; });
  const b3Kapandi = new Promise((c) => b3.on('close', c));
  b3.stdin.end(`set application_name='pms4-kapat';\n${rolBasi}\nselect public.pms_folio_kapat('${folioB}');\n`);

  const b3Bekledi = await kilitteMi('pms4-kapat');
  a3.stdin.end('commit;\n');
  const a3Kod = await a3Kapandi;
  const b3Kod = await b3Kapandi;

  const durumB = sorgu(`select durum from public.pms_folyolar where id='${folioB}';`).trim();
  const bakiyeB = sorgu(`select bakiye::text from public.pms_folio_ozet where folio_id='${folioB}';`).trim();

  yarisKontrolleri.push(
    [a3Kod === 0, '10b: odeme commit etmeliydi', '10b odeme commit etti'],
    [b3Bekledi, '10b: kapanis KILIT BEKLEMELIYDI', '10b kapanis kilidi bekledi'],
    [b3Kod !== 0 && /bakiyesi sifir degil/.test(b3Hata), '10b: kapanis reddedilmeliydi, cikis=' + b3Kod, '10b bakiyeli folyo kapanmadi'],
    [durumB === 'acik', '10b: folyo acik kalmaliydi, bulunan: ' + durumB, '10b folyo acik kaldi'],
    [Number(bakiyeB) === -300, '10b: bakiye -300 olmaliydi, bulunan: ' + bakiyeB, '10b bakiye -300 (odeme korundu)'],
  );
} catch (e) {
  yarisKontrolleri.push([false, '10b: ' + e.message, '']);
}

console.log('\n10) Kapanis / odeme yarisi (iki oturum, iki yon):');
for (const [gecti, hataMsg, okMsg] of yarisKontrolleri) {
  console.log((gecti ? '   OK   ' : '   HATA ') + (gecti ? okMsg : hataMsg));
  if (!gecti) sonuc = 1;
}

console.log('\n' + '='.repeat(70));
console.log(sonuc === 0
  ? 'SONUC: PMS FAZ 1 / ADIM 4 TESTLERI GECTI\n'
    + '       folio + gecelik oda ucreti (idempotent) + bar/oda devri\n'
    + '       ters kayit + odeme/bakiye + kapatma + yetki + eszamanlilik\n'
    + '       + capraz otel (iki otel) + append-only + kapanis/odeme yarisi'
  : 'SONUC: PMS FAZ 1 / ADIM 4 TESTLERI BASARISIZ');
console.log('='.repeat(70));
bitir(sonuc);
