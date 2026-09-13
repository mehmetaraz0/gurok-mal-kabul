// ============================================================================
// PMS FAZ 2 — NEGATIF YETKI TESTLERI (GERCEK URETIM ROL ADLARIYLA)
// ============================================================================
// YALNIZ ATILABILIR YEREL KONTEYNERDE CALISIR. Uretime BAGLANMAZ.
//
// KULLANIM:
//   PMS_DOKUM=<sema-dokumu.sql> PMS_REFERANS=<referans-veri.sql> \
//     node scripts/pms-faz2-yetki-negatif.mjs
//   veya
//   node scripts/pms-faz2-yetki-negatif.mjs <sema-dokumu.sql> <referans-veri.sql>
//
// Dokumler REPO DISINDA tutulur (docs/kurulum/dokum-al.ps1 -Hedef); bu yuzden
// yol disaridan verilir ve varsayilani yoktur.
//
// NE OLCER: yayin planindaki (docs/kurulum/2026-09-11-pms-faz2-yayin-plani.md §4)
// yetki matrisi gercek uretim rol adlariyla kurulur ve her seviyenin SINIRI
// davranissal olarak sinanir. Beklenen RED gerceklesmezse FAIL.
//
//   goruntule  : okur, komut veremez
//   kayit      : sahiplenir/baslatir/tamamlar; acamaz, atayamaz, iptal edemez,
//                kendi isini denetleyemez
//   tam        : acar/atar/denetler; atanmis gorevi sahiplenemez; KENDI
//                tamamladigi isi denetleyemez (bagimsiz denetim)
//   matriste yok / pasif kullanici / baska otel : hicbir sey
//
// TEST KURGUSU NOTU: hedef kullanici kimligi SAHIP rolunde cozulur. Uygulama
// rolunde alt sorgu ile cozmek RLS altinda sessizce NULL doner ve `ata`
// komutunu "atamayi kaldir"a cevirir; bu, testi yaniltir.
// ============================================================================
import { spawnSync } from 'node:child_process';
import { readFileSync, existsSync } from 'node:fs';
import { setTimeout as bekle } from 'node:timers/promises';

const kok = new URL('..', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const dokum = process.env.PMS_DOKUM || process.argv[2];
const referans = process.env.PMS_REFERANS || process.argv[3];
if (!dokum || !referans) {
  console.error('Kullanim: node scripts/pms-faz2-yetki-negatif.mjs <sema-dokumu.sql> <referans-veri.sql>');
  console.error('(veya PMS_DOKUM / PMS_REFERANS ortam degiskenleri)');
  process.exit(2);
}
for (const y of [dokum, referans]) {
  if (!existsSync(y)) { console.error('Dosya bulunamadi: ' + y); process.exit(2); }
}

const K = 'pms-faz2-yetki';
const d = (a, g) => {
  const r = spawnSync('docker', a, { input: g, encoding: 'utf8', timeout: 600000, maxBuffer: 64 * 1024 * 1024 });
  return { ok: !r.error && r.status === 0, out: r.stdout || '', err: r.error?.message || r.stderr || '' };
};
const psql = (ek = []) => ['exec', '-i', K, 'psql', '-X', '-U', 'postgres', '-d', 'hkdb', ...ek];
const repoDosyasi = (p) => readFileSync(kok + p, 'utf8');
const disDosya = (p) => readFileSync(p, 'utf8');
const tek = (q) => d(psql(['-At', '-v', 'ON_ERROR_STOP=1']), q).out.trim();
const ilkHata = (s) => (s.split('\n').find((l) => l.includes('ERROR:')) || '')
  .replace(/^.*ERROR:\s*/, '').split('\n')[0].slice(0, 90);

const U = {
  sef: 'aaaaaaa1-0000-0000-0000-000000000001',
  vardiya: 'aaaaaaa1-0000-0000-0000-000000000002',
  personel: 'aaaaaaa1-0000-0000-0000-000000000003',
  personel2: 'aaaaaaa1-0000-0000-0000-000000000004',
  onburo: 'aaaaaaa1-0000-0000-0000-000000000005',
  bar: 'aaaaaaa1-0000-0000-0000-000000000006',
  pasif: 'aaaaaaa1-0000-0000-0000-000000000007',
  otel811: 'aaaaaaa1-0000-0000-0000-000000000008',
};
// Kimlik ve rol OTURUM duzeyinde ayarlanir: psql her ifadeyi ayri transaction'da
// calistirdigi icin `set local` bir sonraki ifadeye ULASMAZ.
const kimlik = (uid) => `select set_config('request.jwt.claim.sub', '${uid}', false), `
  + `set_config('request.jwt.claim.role', 'authenticated', false);`;
function calistir(uid, sql) {
  const r = d(psql(['-At', '-v', 'ON_ERROR_STOP=1']), `${kimlik(uid)} set role authenticated;\n${sql}`);
  return { ok: r.ok, hata: ilkHata(r.err) };
}

let ok = 0;
let fail = 0;
function bekleRed(etiket, uid, sql, ipucu) {
  const r = calistir(uid, sql);
  if (r.ok) { console.log('FAIL ' + etiket + ' -> GECTI (reddedilmeliydi)'); fail++; return; }
  if (ipucu && !r.hata.toLowerCase().includes(ipucu.toLowerCase())) {
    console.log('FAIL ' + etiket + ' -> yanlis sebeple red: ' + r.hata); fail++; return;
  }
  console.log('OK   ' + etiket + ' -> RED (' + r.hata + ')'); ok++;
}
function bekleGec(etiket, uid, sql) {
  const r = calistir(uid, sql);
  if (r.ok) { console.log('OK   ' + etiket + ' -> GECTI'); ok++; return true; }
  console.log('FAIL ' + etiket + ' -> RED (' + r.hata + ')'); fail++; return false;
}

spawnSync('docker', ['rm', '-f', K]);
d(['run', '--detach', '--rm', '--network', 'none', '--name', K, '--tmpfs', '/var/lib/postgresql/data',
  '-e', 'POSTGRES_HOST_AUTH_METHOD=trust', 'postgres:17']);
for (let i = 0; i < 60; i++) {
  if (spawnSync('docker', ['exec', K, 'pg_isready', '-U', 'postgres']).status === 0) break;
  await bekle(1000);
}
await bekle(2000);
d(['exec', K, 'createdb', '-U', 'postgres', 'hkdb']);
d(psql(['-v', 'ON_ERROR_STOP=1']), repoDosyasi('scripts/supabase-shim.sql'));
d(psql(), disDosya(dokum));
d(psql(), disDosya(referans));
d(psql(['-v', 'ON_ERROR_STOP=1']), repoDosyasi('docs/kurulum/2026-09-08-pms-fonksiyon-acl-temizligi.sql'));
for (const m of ['docs/kurulum/2026-09-09-pms-faz2-adim1-housekeeping.sql',
  'docs/kurulum/2026-09-10-pms-faz2-adim2-housekeeping-ui-destek.sql']) {
  // SQL Editor esdegeri: tum dosya TEK sorgu metni olarak gider.
  const r = d(['exec', '-i', K, 'sh', '-c',
    'psql -X -U postgres -d hkdb -v ON_ERROR_STOP=1 -c "$(cat)"'], repoDosyasi(m));
  if (!r.ok) { console.log('migration hatasi ' + m + ': ' + ilkHata(r.err)); spawnSync('docker', ['rm', '-f', K]); process.exit(1); }
}
console.log('dokum : ' + dokum);
console.log('taban + iki Faz 2 migration kuruldu\n');

const kurulum = `
do $$
declare v_tip uuid; v_tip811 uuid;
begin
  insert into public.yetki_matrisi (rol_id, modul_id, yetki)
  select r.id, m.id,
         case r.ad
           when 'Kat Hizmetleri Şefi' then 'tam'
           when 'Kat Hizmetleri Vardiya Sorumlusu' then 'tam'
           when 'Kat Hizmetleri Personeli' then 'kayit'
           when 'Genel Müdür (GM)' then 'goruntule'
           when 'Ön Büro Şefi' then 'goruntule'
           when 'Ön Büro Vardiya Sorumlusu' then 'goruntule'
           when 'Ön Büro Personeli' then 'goruntule'
           when 'IT / Sistem Yöneticisi' then 'tam'
           when 'Sistem Yöneticisi' then 'tam'
         end::public.yetki_seviye
    from public.roller r cross join public.moduller m
   where m.kod = 'pms_housekeeping'
     and r.ad in ('Kat Hizmetleri Şefi','Kat Hizmetleri Vardiya Sorumlusu','Kat Hizmetleri Personeli',
                  'Genel Müdür (GM)','Ön Büro Şefi','Ön Büro Vardiya Sorumlusu','Ön Büro Personeli',
                  'IT / Sistem Yöneticisi','Sistem Yöneticisi')
  on conflict (rol_id, modul_id) do update set yetki = excluded.yetki;

  update public.moduller set aktif = true where kod = 'pms_housekeeping';

  insert into auth.users (id) values
    ('${U.sef}'::uuid), ('${U.vardiya}'::uuid), ('${U.personel}'::uuid), ('${U.personel2}'::uuid),
    ('${U.onburo}'::uuid), ('${U.bar}'::uuid), ('${U.pasif}'::uuid), ('${U.otel811}'::uuid)
  on conflict (id) do nothing;

  insert into public.kullanicilar (auth_user_id, ad, rol, rol_id, otel_id, aktif, tum_oteller)
  select x.uid::uuid, x.ad, 'yonetici', r.id, x.otel::public.otel_id, x.aktif, false
    from (values
      ('${U.sef}',      'test sef',       'Kat Hizmetleri Şefi',              '810', true),
      ('${U.vardiya}',  'test vardiya',   'Kat Hizmetleri Vardiya Sorumlusu', '810', true),
      ('${U.personel}', 'test personel',  'Kat Hizmetleri Personeli',         '810', true),
      ('${U.personel2}','test personel2', 'Kat Hizmetleri Personeli',         '810', true),
      ('${U.onburo}',   'test onburo',    'Ön Büro Personeli',                '810', true),
      ('${U.bar}',      'test bar',       'Bar Personeli',                    '810', true),
      ('${U.pasif}',    'test pasif',     'Kat Hizmetleri Personeli',         '810', false),
      ('${U.otel811}',  'test 811',       'Kat Hizmetleri Şefi',              '811', true)
    ) as x(uid, ad, rol_ad, otel, aktif)
    join public.roller r on r.ad = x.rol_ad;

  insert into public.pms_oda_tipleri (otel_id, kod, ad, azami_kisi, azami_yetiskin, azami_cocuk)
  values ('810','YT','Yetki testi',2,2,0) returning id into v_tip;
  insert into public.pms_odalar (otel_id, oda_tipi_id, oda_no) values ('810', v_tip, 'Y01'), ('810', v_tip, 'Y02');
  insert into public.pms_oda_tipleri (otel_id, kod, ad, azami_kisi, azami_yetiskin, azami_cocuk)
  values ('811','YT','Yetki testi',2,2,0) returning id into v_tip811;
  insert into public.pms_odalar (otel_id, oda_tipi_id, oda_no) values ('811', v_tip811, 'Y81');
end $$;`;
let r = d(psql(['-v', 'ON_ERROR_STOP=1']), kurulum);
if (!r.ok) { console.log('kurulum hatasi: ' + ilkHata(r.err)); spawnSync('docker', ['rm', '-f', K]); process.exit(1); }

const oda1 = tek("select id::text from public.pms_odalar where oda_no='Y01'");
const oda2 = tek("select id::text from public.pms_odalar where oda_no='Y02'");
const personelId = tek(`select id::text from public.kullanicilar where auth_user_id='${U.personel}'::uuid`);
const personel2Id = tek(`select id::text from public.kullanicilar where auth_user_id='${U.personel2}'::uuid`);
console.log('matris: ' + tek("select string_agg(r.ad || '=' || ym.yetki::text, '; ' order by r.ad) "
  + 'from public.yetki_matrisi ym join public.roller r on r.id=ym.rol_id '
  + "join public.moduller m on m.id=ym.modul_id where m.kod='pms_housekeeping'") + '\n');

const olustur = (oda) => `select public.pms_housekeeping_gorev_olustur('${oda}'::uuid, 'ekstra_temizlik', 'bos', gen_random_uuid());`;
const listele = "select count(*)::text from public.pms_housekeeping_listele('810','tumu',50);";

console.log('--- GORUNTULE (On Buro Personeli) ---');
bekleGec('G1 goruntule kuyrugu okur', U.onburo, listele);
bekleRed('G2 goruntule gorev ACAMAZ', U.onburo, olustur(oda1), 'Yetki yok');

console.log('--- MATRISTE SATIRI OLMAYAN ROL (Bar Personeli) ---');
bekleRed('Y1 yetkisiz kuyrugu okuyamaz', U.bar, listele, 'Yetki yok');
bekleRed('Y2 yetkisiz gorev acamaz', U.bar, olustur(oda1), 'Yetki yok');

console.log('--- PASIF KULLANICI ---');
bekleRed('P1 pasif kuyrugu okuyamaz', U.pasif, listele, 'Aktif ERP personeli');
bekleRed('P2 pasif gorev acamaz', U.pasif, olustur(oda1), 'Aktif ERP personeli');

console.log('--- KAYIT (Kat Hizmetleri Personeli) ---');
bekleRed('K1 kayit gorev ACAMAZ', U.personel, olustur(oda1), 'Yetki yok');
bekleGec('K0 sef hazirlik gorevi acar', U.sef, olustur(oda1));
const gid = tek(`select id::text from public.pms_housekeeping_gorevleri where oda_id='${oda1}'::uuid order by olusturma_tarihi desc limit 1`);
const surum = () => tek(`select surum::text from public.pms_housekeeping_gorevleri where id='${gid}'::uuid`);
bekleGec('K2 kayit sahiplenir', U.personel, `select public.pms_housekeeping_sahiplen('${gid}'::uuid, ${surum()}, gen_random_uuid());`);
bekleRed('K3 kayit BASKASINI atayamaz', U.personel, `select public.pms_housekeeping_ata('${gid}'::uuid, '${personel2Id}'::uuid, ${surum()}, gen_random_uuid());`, 'Yetki yok');
bekleGec('K4 kayit baslatir', U.personel, `select public.pms_housekeeping_baslat('${gid}'::uuid, ${surum()}, gen_random_uuid());`);
bekleGec('K5 kayit tamamlar', U.personel, `select public.pms_housekeeping_tamamla('${gid}'::uuid, ${surum()}, gen_random_uuid());`);
bekleRed('K6 kayit KENDI isini denetleyemez', U.personel, `select public.pms_housekeeping_kontrol_et('${gid}'::uuid, ${surum()}, gen_random_uuid());`, 'Yetki yok');
bekleRed('K7 kayit iptal edemez', U.personel2, `select public.pms_housekeeping_iptal('${gid}'::uuid, 'deneme', ${surum()}, gen_random_uuid());`, 'Yetki yok');

console.log('--- TAM (Sef / Vardiya Sorumlusu) ---');
bekleGec('T1 tam baskasinin isini denetler', U.sef, `select public.pms_housekeeping_kontrol_et('${gid}'::uuid, ${surum()}, gen_random_uuid());`);
bekleGec('T2 tam ikinci gorev acar', U.vardiya, olustur(oda2));
const gid2 = tek(`select id::text from public.pms_housekeeping_gorevleri where oda_id='${oda2}'::uuid order by olusturma_tarihi desc limit 1`);
const surum2 = () => tek(`select surum::text from public.pms_housekeeping_gorevleri where id='${gid2}'::uuid`);
bekleGec('T3 tam gorevi personele atar', U.vardiya, `select public.pms_housekeeping_ata('${gid2}'::uuid, '${personelId}'::uuid, ${surum2()}, gen_random_uuid());`);
const atanan = tek(`select coalesce(atanan_kullanici_id::text,'(bos)') from public.pms_housekeeping_gorevleri where id='${gid2}'::uuid`);
if (atanan === personelId) { console.log('OK   T3b atama KALICI'); ok++; } else { console.log('FAIL T3b atama yazilmadi: ' + atanan); fail++; }
bekleRed('T4 tam atanmis gorevi sahiplenemez', U.sef, `select public.pms_housekeeping_sahiplen('${gid2}'::uuid, ${surum2()}, gen_random_uuid());`, 'zaten atanmis');
bekleGec('T5 sef ucuncu gorev acar', U.sef, olustur(oda1));
const gid3 = tek(`select id::text from public.pms_housekeeping_gorevleri where oda_id='${oda1}'::uuid order by olusturma_tarihi desc limit 1`);
const surum3 = () => tek(`select surum::text from public.pms_housekeeping_gorevleri where id='${gid3}'::uuid`);
bekleGec('T6 sef kendi sahiplenir', U.sef, `select public.pms_housekeeping_sahiplen('${gid3}'::uuid, ${surum3()}, gen_random_uuid());`);
bekleGec('T7 sef baslatir', U.sef, `select public.pms_housekeeping_baslat('${gid3}'::uuid, ${surum3()}, gen_random_uuid());`);
bekleGec('T8 sef tamamlar', U.sef, `select public.pms_housekeeping_tamamla('${gid3}'::uuid, ${surum3()}, gen_random_uuid());`);
bekleRed('T9 sef KENDI isini denetleyemez', U.sef, `select public.pms_housekeeping_kontrol_et('${gid3}'::uuid, ${surum3()}, gen_random_uuid());`, 'Kendi isinizi');
bekleGec('T10 ikinci tam kullanici denetler', U.vardiya, `select public.pms_housekeeping_kontrol_et('${gid3}'::uuid, ${surum3()}, gen_random_uuid());`);

console.log('--- OTEL IZOLASYONU ---');
bekleRed('O1 811 sefi 810 kuyrugunu okuyamaz', U.otel811, listele, 'Yetki yok');
bekleRed('O2 811 sefi 810 odasinda gorev acamaz', U.otel811, olustur(oda1), 'erisim yok');
bekleRed('O3 811 sefi 810 gorevini denetleyemez', U.otel811, `select public.pms_housekeeping_kontrol_et('${gid2}'::uuid, ${surum2()}, gen_random_uuid());`, 'bulunamadi');

console.log('--- ODA SECICI (dar izdusum) ---');
bekleGec('S1 tam oda seciciyi okur', U.sef, "select count(*)::text from public.pms_housekeeping_odalar('810', 200);");
bekleRed('S2 kayit oda seciciyi okuyamaz', U.personel, "select count(*)::text from public.pms_housekeeping_odalar('810', 200);", 'Yetki yok');
bekleRed('S3 goruntule oda seciciyi okuyamaz', U.onburo, "select count(*)::text from public.pms_housekeeping_odalar('810', 200);", 'Yetki yok');
bekleRed('S4 811 sefi 810 oda secicisini okuyamaz', U.otel811, "select count(*)::text from public.pms_housekeeping_odalar('810', 200);", 'Yetki yok');

console.log('\nNEGATIF YETKI SONUC: ' + ok + ' OK / ' + fail + ' FAIL');
spawnSync('docker', ['rm', '-f', K]);
process.exit(fail ? 1 : 0);
