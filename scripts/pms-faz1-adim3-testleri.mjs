// ============================================================================
// PMS FAZ 1 / ADIM 3 — SÖZLEŞME TESTİ KOŞUCUSU
// ============================================================================
// Tek kullanımlık PostgreSQL konteynerinde:
//   1) Supabase iskelesi
//   2) ÜRETİM ŞEMA DÖKÜMÜ (bayt-birebir doğrulanmış kopya)
//   3) Adım 1 → Adım 2 → Adım 3 migration (Adım 3 iki kez — idempotency)
//   4) Sözleşme testleri (state makinesi, bypass, housekeeping, yetki)
//   5) EŞZAMANLILIK — check-out kilit tutarken check-in odaya giremez;
//      kilit bırakıldığında YENİDEN doğrulama ile reddedilir.
//
// ÜRETİM VERİTABANINA BAĞLANMAZ. Yalnızca yerel dosya + Docker.
// Kullanım: node scripts/pms-faz1-adim3-testleri.mjs [--mig <sql-yolu>]
// --mig: sabotaj testi için migration'ı geçici değiştirilmiş kopyayla koşturur.
import { spawn, spawnSync } from 'node:child_process';
import { readFileSync, existsSync } from 'node:fs';
import { setTimeout as bekle } from 'node:timers/promises';

const kok = new URL('..', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const args = process.argv.slice(2);
const migArg = args.includes('--mig') ? args[args.indexOf('--mig') + 1] : null;

const DOSYALAR = {
  shim:   kok + 'scripts/supabase-shim.sql',
  dokum:  kok + 'docs/kurulum/2026-09-06-sema-dokumu.sql',
  adim1:  kok + 'docs/kurulum/2026-09-06-pms-faz1-oda-tipleri-odalar.sql',
  adim2:  kok + 'docs/kurulum/2026-09-06-pms-faz1-adim2-misafir-rezervasyon.sql',
  adim3:  migArg || kok + 'docs/kurulum/2026-09-06-pms-faz1-adim3-checkin-checkout.sql',
  test:   kok + 'scripts/pms-faz1-adim3-testleri.sql',
};
for (const [ad, yol] of Object.entries(DOSYALAR)) {
  if (!existsSync(yol)) { console.error('Dosya yok (' + ad + '): ' + yol); process.exit(1); }
}

const konteyner = 'pms-adim3-test';
const psqlArgs = ['exec', '-i', konteyner, 'psql', '-X', '-U', 'postgres', '-d', 'pms3'];

function docker(args_, girdi) {
  const r = spawnSync('docker', args_, {
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
docker(['exec', konteyner, 'createdb', '-U', 'postgres', 'pms3']);

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

r = docker([...psqlArgs, '-v', 'ON_ERROR_STOP=1'], oku('adim2'));
if (!r.ok) { console.error('4) Adim 2 migration    : BASARISIZ\n'
  + r.err.split('\n').filter((l) => l.trim()).slice(-14).join('\n')); bitir(1); }
console.log('4) Adim 2 migration    : uygulandi');

const adim3 = oku('adim3');
r = docker([...psqlArgs, '-v', 'ON_ERROR_STOP=1'], adim3);
if (!r.ok) { console.error('5) Adim 3 migration    : BASARISIZ\n'
  + r.err.split('\n').filter((l) => l.trim()).slice(-14).join('\n')); bitir(1); }
console.log('5) Adim 3 migration    : uygulandi');

r = docker([...psqlArgs, '-v', 'ON_ERROR_STOP=1'], adim3);
if (!r.ok) { console.error('6) Tekrar uygulama     : BASARISIZ (idempotent degil)\n'
  + r.err.split('\n').filter((l) => l.trim()).slice(-14).join('\n')); bitir(1); }
console.log('6) Tekrar uygulama     : gecti (idempotent)');

r = docker([...psqlArgs, '-v', 'ON_ERROR_STOP=1'], oku('test'));
if (!r.ok) {
  const satirlar = r.err.split('\n').filter((l) => l.trim());
  console.error('\n7) Sozlesme testleri   : BASARISIZ\n'
    + (satirlar.filter((l) => /BASARISIZ|ERROR|DETAIL/.test(l)).slice(0, 10).join('\n')
       || satirlar.slice(-12).join('\n')));
  bitir(1);
}
console.log('7) Sozlesme testleri   : gecti');

// ---------------------------------------------------------------------------
// 8) EŞZAMANLILIK — kilit sırası + kilit altında yeniden doğrulama
// ---------------------------------------------------------------------------
// A, 309'da konaklayan V20'nin check-out'unu yapar ve transaction'ı AÇIK
// tutar (oda kilidi onda). B, aynı odaya V21'i check-in etmeye çalışır:
//   - B, A'nın oda kilidini BEKLEMELİ (deterministik kilit sırası kanıtı)
//   - A commit edince oda bos+KIRLI olur; B kilidi alınca şartları YENİDEN
//     doğrular ve housekeeping kuralıyla REDDEDİLMELİ.
// Kilit/yeniden doğrulama olmasaydı B "bos görünen" odaya girer ve A'nın
// çıkışı odayı B'yi içeride bırakarak bos/kirli sayardı — tam istenen yarış.
function sorgu(sql) {
  return spawnSync('docker', [...psqlArgs, '-At', '-c', sql], { encoding: 'utf8' }).stdout || '';
}
const psqlKatiArgs = [...psqlArgs, '-v', 'ON_ERROR_STOP=1'];

// Zemin: V20 konaklıyor (310, dün girdi, bugün çıkışlı — sahnelenmiş), V21 bugün girecek.
r = docker(psqlKatiArgs, `
insert into public.pms_rezervasyonlar
  (id, otel_id, misafir_id, oda_tipi_id, giris_tarihi, cikis_tarihi, durum)
values ('11000000-0000-0000-0000-000000030020','810','f0000000-0000-0000-0000-000000030001',
        'd0000000-0000-0000-0000-000000030010', current_date - 1, current_date,'onaylandi'),
       ('11000000-0000-0000-0000-000000030021','810','f0000000-0000-0000-0000-000000030001',
        'd0000000-0000-0000-0000-000000030010', current_date, current_date + 2,'onaylandi')
on conflict (id) do nothing;
insert into public.pms_oda_atamalari (otel_id, rezervasyon_id, oda_id, baslangic, bitis)
values ('810','11000000-0000-0000-0000-000000030020','e0000000-0000-0000-0000-000000030110',
        current_date - 1, current_date);
update public.pms_odalar set kullanim_durumu='dolu'
 where id='e0000000-0000-0000-0000-000000030110';
update public.pms_rezervasyonlar
   set durum='giris_yapildi', giris_zamani=now() - interval '1 day',
       giris_yapan='a0000000-0000-0000-0000-000000000001'
 where id='11000000-0000-0000-0000-000000030020';`);
if (!r.ok) {
  console.error('8) Eszamanlilik zemini : BASARISIZ\n'
    + r.err.split('\n').filter((l) => l.trim()).slice(-10).join('\n'));
  bitir(1);
}

let sonuc = 0;
const a = spawn('docker', psqlKatiArgs, { stdio: ['pipe', 'pipe', 'pipe'] });
let aCikti = '', aHata = '';
a.stdout.on('data', (d) => { aCikti += d; });
a.stderr.on('data', (d) => { aHata += d; });
const aKapandi = new Promise((c) => a.on('close', c));

const kilitTutuldu = new Promise((coz, red) => {
  const zaman = setTimeout(() => red(new Error('eszamanlilik bariyeri zaman asimi')), 20000);
  a.stdout.on('data', () => {
    if (aCikti.includes('PMS3_KILIT')) { clearTimeout(zaman); coz(); }
  });
  a.on('close', () => { clearTimeout(zaman); red(new Error(aHata || 'A bariyerden once durdu')); });
});

try {
  // A: check-out'u yap ama COMMIT ETME — oda kilidi A'da kalır.
  a.stdin.write(`begin;\n`
    + `set role authenticated;\n`
    + `select set_config('request.jwt.claim.role','authenticated',false);\n`
    + `select set_config('request.jwt.claim.sub','a0000000-0000-0000-0000-000000000001',false);\n`
    + `select public.pms_check_out('11000000-0000-0000-0000-000000030020');\n`
    + `reset role;\n\\echo PMS3_KILIT\n`);
  await kilitTutuldu;

  // B: aynı odaya check-in — A'nın kilidini beklemeli, sonra KIRLI nedeniyle reddedilmeli.
  const b = spawn('docker', psqlKatiArgs, { stdio: ['pipe', 'pipe', 'pipe'] });
  let bHata = '';
  b.stdout.resume();
  b.stderr.on('data', (d) => { bHata += d; });
  const bKapandi = new Promise((c) => b.on('close', c));
  b.stdin.end(`set application_name='pms3-ikinci';\n`
    + `set role authenticated;\n`
    + `select set_config('request.jwt.claim.role','authenticated',false);\n`
    + `select set_config('request.jwt.claim.sub','a0000000-0000-0000-0000-000000000001',false);\n`
    + `select public.pms_check_in('11000000-0000-0000-0000-000000030021',\n`
    + `                           'e0000000-0000-0000-0000-000000030110');\n`);

  let bekliyor = false;
  let sonBekleme = '';
  for (let i = 0; i < 80; i++) {
    sonBekleme = sorgu("select coalesce(string_agg(application_name || ':' || wait_event_type || '/' || coalesce(wait_event,'-'), ' | '), '(yok)') from pg_stat_activity where application_name='pms3-ikinci';").trim();
    if (sonBekleme.includes('Lock')) { bekliyor = true; break; }
    await bekle(100);
  }
  if (!bekliyor) console.log('   DEBUG bekleme gozlenmedi: ' + sonBekleme + ' | bHata: ' + bHata.slice(0, 300));
  a.stdin.end('commit;\n');
  const aKod = await aKapandi;
  const bKod = await bKapandi;

  const odaDurum = sorgu("select kullanim_durumu || '/' || temizlik_durumu from public.pms_odalar where id='e0000000-0000-0000-0000-000000030110';").trim();
  const v20 = sorgu("select durum from public.pms_rezervasyonlar where id='11000000-0000-0000-0000-000000030020';").trim();
  const v21 = sorgu("select durum from public.pms_rezervasyonlar where id='11000000-0000-0000-0000-000000030021';").trim();

  const kontroller = [
    [aKod === 0, 'A (check-out) commit etmeliydi', 'A commit etti'],
    [bekliyor, 'B, A nin oda kilidini BEKLEMELIYDI', 'B kilidi bekledi (sirali kilit)'],
    [bKod !== 0, 'B REDDEDILMELIYDI', 'B reddedildi'],
    [/kirli|temizleniyor|bos degil/i.test(bHata), 'B housekeeping hatasiyla reddedilmeliydi', 'red sebebi: kirli oda'],
    [odaDurum === 'bos/kirli', 'oda bos/kirli kalmaliydi, durum: ' + odaDurum, 'oda bos/kirli (check-out bozulmadi)'],
    [v20 === 'cikis_yapildi', 'V20 cikis_yapildi olmaliydi, durum: ' + v20, 'V20 cikis_yapildi'],
    [v21 === 'onaylandi', "V21 onaylandi kalmaliydi (giris YAPILMAMALI), durum: " + v21, 'V21 giris yapamadi'],
  ];
  console.log('\n8) Eszamanlilik testi (check-out vs check-in):');
  for (const [gecti, hataMsg, okMsg] of kontroller) {
    console.log((gecti ? '   OK   ' : '   HATA ') + (gecti ? okMsg : hataMsg));
    if (!gecti) sonuc = 1;
  }
} catch (e) {
  console.error('\n8) Eszamanlilik testi  : ' + e.message);
  sonuc = 1;
}

console.log('\n' + '='.repeat(70));
console.log(sonuc === 0
  ? 'SONUC: PMS FAZ 1 / ADIM 3 TESTLERI GECTI\n'
    + '       check-in/out + state makinesi + bypass korumalari\n'
    + '       housekeeping kurallari + yetki + eszamanlilik'
  : 'SONUC: PMS FAZ 1 / ADIM 3 TESTLERI BASARISIZ');
console.log('='.repeat(70));
bitir(sonuc);
