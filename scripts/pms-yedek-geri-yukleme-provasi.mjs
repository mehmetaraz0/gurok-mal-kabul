// ============================================================================
// YEDEK GERI YUKLEME PROVASI — izole, uretime baglanmaz
// ============================================================================
// NEDEN VAR: Proje Free planda ve Supabase PROJE YEDEGI ALMIYOR (2026-09-12'de
// panelden olculdu). Tek yedek, elle alinan dokumdur. "Dosya olustu" bir yedek
// KANITI DEGILDIR: yayin plani E-5 ancak bu prova gectiginde kapanir.
//
// KULLANIM:
//   node scripts/pms-yedek-geri-yukleme-provasi.mjs <veri-yedegi> [sayaclar.json] [secenekler]
//
//   <veri-yedegi>     .sql  -> psql ile yuklenir
//                     .dump -> pg_restore ile yuklenir (pg_dump -Fc)
//   [sayaclar.json]   docs/kurulum/2026-09-13-yedek-dogrulama-sayaclari.sql ciktisi
//   --sema <dosya>    Yedek VERI-ONLY ise once yuklenecek sema dokumu
//                     (ya da PMS_SEMA ortam degiskeni)
//   --mekanik         Yalniz mekanizma denemesi: gercek veri yedegi yoksa
//                     uygulama erisimi kontrolu ATLANIR ve cikis kodu bundan
//                     etkilenmez. Kabul kanitinda KULLANILMAZ.
//
// DOGRULANANLAR (sureleri AYRI olculur ve ayri raporlanir):
//   1) Geri yukleme            — dosya yuklenir, hata sayisi 0 olmali
//   2) Satir sayilari          — uretim sayaclariyla BIREBIR karsilastirma
//                                (kapsam: public + phase0_private semalari)
//   3) Veri tutarliligi        — uc kontrol, hepsi 0 olmali
//   4) Temel uygulama erisimi  — gercek bir ERP kullanicisinin kimligiyle
//                                authenticated rolunde okuma; anon'a kapali
// ============================================================================
import { spawnSync } from 'node:child_process';
import { readFileSync, existsSync, statSync } from 'node:fs';
import { setTimeout as bekle } from 'node:timers/promises';

const kok = new URL('..', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const argv = process.argv.slice(2);
const bayrak = (ad) => argv.includes(ad);
const deger = (ad) => { const i = argv.indexOf(ad); return i >= 0 ? argv[i + 1] : undefined; };
const konum = argv.filter((a, i) => !a.startsWith('--') && argv[i - 1] !== '--sema');

const yedek = konum[0];
const sayacDosyasi = konum[1];
const semaDosyasi = deger('--sema') || process.env.PMS_SEMA;
const mekanik = bayrak('--mekanik');

if (!yedek || !existsSync(yedek)) {
  console.error('Kullanim: node scripts/pms-yedek-geri-yukleme-provasi.mjs <veri-yedegi> [sayaclar.json] [--sema <sema.sql>] [--mekanik]');
  process.exit(2);
}
if (semaDosyasi && !existsSync(semaDosyasi)) { console.error('Sema dosyasi yok: ' + semaDosyasi); process.exit(2); }

const K = 'pms-yedek-prova';
const d = (a, g) => {
  const r = spawnSync('docker', a, { input: g, encoding: 'utf8', timeout: 1800000, maxBuffer: 256 * 1024 * 1024 });
  return { ok: !r.error && r.status === 0, out: r.stdout || '', err: r.error?.message || r.stderr || '' };
};
const psql = (ek = []) => ['exec', '-i', K, 'psql', '-X', '-U', 'postgres', '-d', 'geri', ...ek];
const tek = (q) => d(psql(['-At', '-v', 'ON_ERROR_STOP=1']), q).out.trim();
const yukHatalari = (s) => s.split('\n')
  .filter((l) => l.includes('ERROR:'))
  .filter((l) => !/schema "public" already exists/.test(l));
const sn = (t) => ((Date.now() - t) / 1000).toFixed(1);

// Kapsam, yedegin kapsamiyla AYNI: public + phase0_private (dokum-al.ps1).
const SAYAC_SORGUSU = `
select jsonb_build_object(
  'rol', current_user,
  'bypassrls', (select rolbypassrls from pg_roles where rolname = current_user),
  'force_rls_tablo', (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace
                       where n.nspname in ('public','phase0_private') and c.relkind='r' and c.relforcerowsecurity),
  'tablo_sayisi', (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace
                    where n.nspname in ('public','phase0_private') and c.relkind='r'),
  'satir_sayilari', (
    select coalesce(jsonb_object_agg(t.tablo, t.adet order by t.tablo), '{}'::jsonb) from (
      select n.nspname || '.' || c.relname as tablo,
             (xpath('/row/c/text()', query_to_xml(format('select count(*) as c from %I.%I', n.nspname, c.relname),
                                                  false, true, '')))[1]::text::bigint as adet
        from pg_class c join pg_namespace n on n.oid=c.relnamespace
       where n.nspname in ('public','phase0_private') and c.relkind='r') t),
  'denetim_izi_satir', (select count(*) from public.erp_islem_audit),
  'denetim_izi_son_kayit', (select max(server_timestamp) from public.erp_islem_audit),
  'pms_ozet', jsonb_build_object(
    'oda', (select count(*) from public.pms_odalar),
    'dolu_oda', (select count(*) from public.pms_odalar where kullanim_durumu='dolu'),
    'devam_eden_konaklama', (select count(*) from public.pms_rezervasyonlar where durum='giris_yapildi'),
    'aktif_atama', (select count(*) from public.pms_oda_atamalari where aktif),
    'acik_folyo', (select count(*) from public.pms_folyolar where durum='acik'))
)::text;`;

spawnSync('docker', ['rm', '-f', K]);
let r = d(['run', '--detach', '--rm', '--network', 'none', '--name', K, '--tmpfs', '/var/lib/postgresql/data',
  '-e', 'POSTGRES_HOST_AUTH_METHOD=trust', 'postgres:17']);
if (!r.ok) { console.error('Konteyner baslatilamadi: ' + r.err.slice(0, 200)); process.exit(1); }
for (let i = 0; i < 60; i++) {
  if (spawnSync('docker', ['exec', K, 'pg_isready', '-U', 'postgres']).status === 0) break;
  await bekle(1000);
}
await bekle(2000);
d(['exec', K, 'createdb', '-U', 'postgres', 'geri']);

const tHazirlik = Date.now();
r = d(psql(['-v', 'ON_ERROR_STOP=1']), readFileSync(kok + 'scripts/supabase-shim.sql', 'utf8'));
console.log('1) Supabase iskelesi : ' + (r.ok ? 'kuruldu' : 'HATA ' + r.err.slice(0, 200)));
let semaHatalari = [];
if (semaDosyasi) {
  r = d(psql(), readFileSync(semaDosyasi, 'utf8'));
  semaHatalari = yukHatalari(r.err);
  console.log('   sema dokumu       : ' + semaDosyasi + ' (' + semaHatalari.length + ' hata)');
}
const hazirlikSn = sn(tHazirlik);

const ist = statSync(yedek);
console.log('2) Yedek dosyasi     : ' + yedek);
console.log('   boyut             : ' + ist.size.toLocaleString('tr-TR') + ' bayt · dosya tarihi ' + ist.mtime.toISOString());

// --- 1) GERI YUKLEME -------------------------------------------------------
const tYukleme = Date.now();
let yuklemeHatalari = [];
if (/\.dump$/i.test(yedek)) {
  const kopya = d(['cp', yedek, K + ':/tmp/yedek.dump']);
  if (!kopya.ok) { console.error('Konteynere kopyalanamadi: ' + kopya.err.slice(0, 200)); spawnSync('docker', ['rm', '-f', K]); process.exit(1); }
  r = d(['exec', K, 'pg_restore', '-U', 'postgres', '-d', 'geri', '--no-owner', '--no-privileges', '/tmp/yedek.dump']);
  yuklemeHatalari = r.err.split('\n').filter((l) => /error:/i.test(l));
} else {
  r = d(psql(), readFileSync(yedek, 'utf8'));
  yuklemeHatalari = yukHatalari(r.err);
}
const yuklemeSn = sn(tYukleme);
console.log('3) GERI YUKLEME      : ' + yuklemeSn + ' sn · ' + yuklemeHatalari.length + ' hata');
for (const h of yuklemeHatalari.slice(0, 5)) console.log('   ' + h.slice(0, 180));

// --- 2) SATIR SAYILARI -----------------------------------------------------
const tSayac = Date.now();
let olculen = null;
try { olculen = JSON.parse(tek(SAYAC_SORGUSU)); } catch { /* asagida */ }
if (!olculen) {
  console.error('Geri yuklenen kopyadan sayaclar okunamadi; yukleme basarisiz olmus olabilir.');
  spawnSync('docker', ['rm', '-f', K]);
  process.exit(1);
}
let fark = 0;
let karsilastirilan = 0;
if (sayacDosyasi && existsSync(sayacDosyasi)) {
  const beklenen = JSON.parse(readFileSync(sayacDosyasi, 'utf8'));
  const b = beklenen.satir_sayilari || {};
  const o = olculen.satir_sayilari || {};
  const tablolar = [...new Set([...Object.keys(b), ...Object.keys(o)])].sort();
  karsilastirilan = tablolar.length;
  for (const t of tablolar) {
    const bs = b[t] === undefined ? null : Number(b[t]);
    const os = o[t] === undefined ? null : Number(o[t]);
    if (bs !== os) { console.log('   FARK  ' + t.padEnd(40) + ' uretim=' + bs + '  kopya=' + os); fark++; }
  }
  if (beklenen.tablo_sayisi !== undefined && Number(beklenen.tablo_sayisi) !== Number(olculen.tablo_sayisi)) {
    console.log('   FARK  tablo sayisi: uretim=' + beklenen.tablo_sayisi + ' kopya=' + olculen.tablo_sayisi);
    fark++;
  }
  if (beklenen.rol && beklenen.rol !== olculen.rol) {
    console.log('   NOT   sayim rolleri farkli: uretim=' + beklenen.rol + ' kopya=' + olculen.rol);
  }
  if (Number(beklenen.force_rls_tablo || 0) > 0) {
    console.log('   NOT   uretimde FORCE RLS tablo var (' + beklenen.force_rls_tablo + '); sayim gorunurlugu sinirli olabilir.');
  }
} else {
  console.log('   URETIM SAYACLARI VERILMEDI — karsilastirma yapilamadi.');
  fark = -1;
}
const sayacSn = sn(tSayac);
console.log('4) SATIR SAYILARI    : ' + sayacSn + ' sn · karsilastirilan tablo ' + karsilastirilan + ' · fark ' + (fark < 0 ? '(olculemedi)' : fark));

// --- 3) VERI TUTARLILIGI ---------------------------------------------------
const tTutarlilik = Date.now();
const kontroller = [
  ['dolu oda, devam eden konaklamasi yok',
    `select count(*) from public.pms_odalar o where o.kullanim_durumu='dolu'
       and not exists (select 1 from public.pms_oda_atamalari a
                        join public.pms_rezervasyonlar rz on rz.id=a.rezervasyon_id and rz.otel_id=a.otel_id
                       where a.oda_id=o.id and a.otel_id=o.otel_id and a.aktif and rz.durum='giris_yapildi')`],
  ['giris_yapildi konaklama, aktif atamasi 1 degil',
    `select count(*) from (select rz.id from public.pms_rezervasyonlar rz
       left join public.pms_oda_atamalari a on a.rezervasyon_id=rz.id and a.otel_id=rz.otel_id and a.aktif
      where rz.durum='giris_yapildi' group by rz.id having count(a.id)<>1) x`],
  ['aktif kullanicilarda tekrarlanan auth_user_id',
    `select count(*) from (select auth_user_id from public.kullanicilar
      where aktif is true and auth_user_id is not null group by auth_user_id having count(*)>1) x`],
];
let tutarsiz = 0;
for (const [ad, sorgu] of kontroller) {
  const sayi = Number(tek(sorgu + ';'));
  if (Number.isNaN(sayi)) { console.log('   ?    ' + ad + ' -> okunamadi'); tutarsiz++; continue; }
  console.log((sayi === 0 ? '   OK   ' : '   FAIL ') + ad + ' = ' + sayi);
  if (sayi !== 0) tutarsiz++;
}
const tutarlilikSn = sn(tTutarlilik);
console.log('5) VERI TUTARLILIGI  : ' + tutarlilikSn + ' sn · sorunlu kontrol ' + tutarsiz);

// --- 4) TEMEL UYGULAMA ERISIMI ---------------------------------------------
const tErisim = Date.now();
let erisimSorun = 0;
let erisimAtlandi = false;
const aktorSatiri = tek(`select k.auth_user_id::text || '|' || coalesce(k.otel_id::text,'-') || '|' || k.tum_oteller::text
  from public.kullanicilar k where k.aktif is true and k.auth_user_id is not null
  order by k.tum_oteller desc, k.olusturma_tarihi limit 1;`);
if (!aktorSatiri || !aktorSatiri.includes('|')) {
  erisimAtlandi = true;
  console.log('6) UYGULAMA ERISIMI  : ATLANDI — geri yuklenen kopyada aktif ERP kullanicisi yok'
    + (mekanik ? ' (mekanik deneme)' : ' — KABUL ICIN YETERSIZ'));
  if (!mekanik) erisimSorun++;
} else {
  const [uid, otel, tumOteller] = aktorSatiri.split('|');
  const kimlik = `select set_config('request.jwt.claim.sub', '${uid}', false), `
    + `set_config('request.jwt.claim.role', 'authenticated', false);`;
  const olarak = (sql) => d(psql(['-At', '-v', 'ON_ERROR_STOP=1']), `${kimlik} set role authenticated;\n${sql}`);
  const kontrol = (ad, sql, kabul) => {
    const x = olarak(sql);
    const cikti = (x.out || '').trim().split('\n').pop();
    const gecti = x.ok && kabul(cikti);
    console.log((gecti ? '   OK   ' : '   FAIL ') + ad + ' -> ' + (x.ok ? cikti : 'HATA'));
    if (!gecti) erisimSorun++;
  };
  console.log('6) UYGULAMA ERISIMI  : aktor ' + uid.slice(0, 8) + '… (otel ' + otel + ', tum_oteller=' + tumOteller + ')');
  kontrol('auth_erp_kullanicisi()', 'select public.auth_erp_kullanicisi()::text;', (c) => c === 't');
  kontrol('modul listesi okunuyor', 'select count(*)::text from public.moduller;', (c) => Number(c) > 0);
  kontrol('oda listesi okunuyor (RLS altinda)', 'select count(*)::text from public.pms_odalar;', (c) => !Number.isNaN(Number(c)));
  kontrol('yetki motoru cevap veriyor', "select public.auth_yetki_var('pms_oda','goruntule')::text;", (c) => c === 't' || c === 'f');
  const anon = d(psql(['-At', '-v', 'ON_ERROR_STOP=1']),
    'reset role; select set_config(\'request.jwt.claim.sub\', \'\', false), set_config(\'request.jwt.claim.role\', \'anon\', false);\n'
    + 'set role anon;\nselect count(*)::text from public.kullanicilar;');
  const anonCikti = (anon.out || '').trim().split('\n').pop();
  const anonKapali = !anon.ok || anonCikti === '0';
  console.log((anonKapali ? '   OK   ' : '   FAIL ') + 'anon kullanicilar tablosunu goremiyor -> '
    + (anon.ok ? anonCikti + ' satir' : 'RED'));
  if (!anonKapali) erisimSorun++;
}
const erisimSn = sn(tErisim);

// --- SONUC -----------------------------------------------------------------
const gecti = yuklemeHatalari.length === 0 && semaHatalari.length === 0 && fark === 0
  && tutarsiz === 0 && erisimSorun === 0;
console.log('\n' + '='.repeat(72));
console.log('SURELER (ayri olculdu)');
console.log('  hazirlik (iskele' + (semaDosyasi ? ' + sema' : '') + ') : ' + hazirlikSn + ' sn');
console.log('  geri yukleme                  : ' + yuklemeSn + ' sn');
console.log('  satir sayilari                : ' + sayacSn + ' sn');
console.log('  veri tutarliligi              : ' + tutarlilikSn + ' sn');
console.log('  uygulama erisimi              : ' + erisimSn + ' sn' + (erisimAtlandi ? ' (atlandi)' : ''));
console.log('-'.repeat(72));
if (mekanik) {
  console.log('SONUC: ' + (gecti
    ? 'MEKANIK DENEME GECTI — betik calisiyor. Bu bir KABUL KANITI DEGILDIR;'
      + ' gercek veri yedegi ve uretim sayaclariyla tekrarlanmalidir.'
    : 'MEKANIK DENEME GECMEDI — betikte ya da girdide sorun var.'));
} else {
  console.log('SONUC: ' + (gecti
    ? 'GERI YUKLEME PROVASI GECTI — yedek kanit sayilir.'
    : 'GERI YUKLEME PROVASI GECMEDI — yedek KANIT SAYILMAZ.'));
}
console.log('='.repeat(72));
spawnSync('docker', ['rm', '-f', K]);
process.exit(gecti ? 0 : 1);
