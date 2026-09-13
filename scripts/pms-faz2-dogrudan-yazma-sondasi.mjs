// ============================================================================
// PMS FAZ 2 — DOGRUDAN ODA TEMIZLIGI YAZMA SONDASI
// ============================================================================
// YALNIZ ATILABILIR YEREL KONTEYNERDE CALISIR. Uretime BAGLANMAZ.
//
// KULLANIM:
//   PMS_DOKUM=<sema-dokumu.sql> PMS_REFERANS=<referans-veri.sql> \
//     node scripts/pms-faz2-dogrudan-yazma-sondasi.mjs
//
// SORU: Faz 2 migration'lari uygulandiktan sonra, veritabani icinden bir odanin
// temizligi DOGRUDAN duzeltilebilir mi? Yayin planinin "kesinti suresi asilirsa
// ne yapacagiz" adimi bu olcume dayanir (plan §1.5, §5.5).
//
// Olculen dort yol:
//   S1 sahip rolu (postgres), kimlik ayari YOK  -> SQL Editor'un gercek durumu
//   S2 authenticated rolu, kimlik ayari YOK
//   S3 authenticated rolu + GERCEK ERP kullanicisinin kimligi
//   S4 sahip rolu + GERCEK ERP kullanicisinin kimligi (kontrollu acil mudahale)
//
// BEKLENEN: S1, S2, S3 YAZAMAZ; yalniz S4 yazar. Beklenti bozulursa FAIL.
// Ayrica kat hizmetleri komutunun modul KAPALI iken reddedildigi, ACIK iken
// calistigi dogrulanir.
// ============================================================================
import { spawnSync } from 'node:child_process';
import { readFileSync, existsSync } from 'node:fs';
import { setTimeout as bekle } from 'node:timers/promises';

const kok = new URL('..', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const dokum = process.env.PMS_DOKUM || process.argv[2];
const referans = process.env.PMS_REFERANS || process.argv[3];
if (!dokum || !referans) {
  console.error('Kullanim: node scripts/pms-faz2-dogrudan-yazma-sondasi.mjs <sema-dokumu.sql> <referans-veri.sql>');
  process.exit(2);
}
for (const y of [dokum, referans]) {
  if (!existsSync(y)) { console.error('Dosya bulunamadi: ' + y); process.exit(2); }
}

const K = 'pms-faz2-yazma-sondasi';
const AUTH = '11111111-1111-1111-1111-111111111111';
const KIMLIK = `select set_config('request.jwt.claim.sub', '${AUTH}', false), `
  + `set_config('request.jwt.claim.role', 'authenticated', false);`;
const d = (a, g) => {
  const r = spawnSync('docker', a, { input: g, encoding: 'utf8', timeout: 600000, maxBuffer: 64 * 1024 * 1024 });
  return { ok: !r.error && r.status === 0, out: r.stdout || '', err: r.error?.message || r.stderr || '' };
};
const psql = (ek = []) => ['exec', '-i', K, 'psql', '-X', '-U', 'postgres', '-d', 'hkdb', ...ek];
const repoDosyasi = (p) => readFileSync(kok + p, 'utf8');
const tek = (q) => d(psql(['-At', '-v', 'ON_ERROR_STOP=1']), q).out.trim();
const ilkHata = (s) => (s.split('\n').find((l) => l.includes('ERROR:')) || '')
  .replace(/^.*ERROR:\s*/, '').split('\n')[0].slice(0, 120);

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
d(psql(), readFileSync(dokum, 'utf8'));
d(psql(), readFileSync(referans, 'utf8'));
d(psql(['-v', 'ON_ERROR_STOP=1']), repoDosyasi('docs/kurulum/2026-09-08-pms-fonksiyon-acl-temizligi.sql'));
for (const m of ['docs/kurulum/2026-09-09-pms-faz2-adim1-housekeeping.sql',
  'docs/kurulum/2026-09-10-pms-faz2-adim2-housekeeping-ui-destek.sql']) {
  const r = d(['exec', '-i', K, 'sh', '-c',
    'psql -X -U postgres -d hkdb -v ON_ERROR_STOP=1 -c "$(cat)"'], repoDosyasi(m));
  if (!r.ok) { console.log('migration hatasi ' + m + ': ' + ilkHata(r.err)); spawnSync('docker', ['rm', '-f', K]); process.exit(1); }
}
console.log('taban + iki Faz 2 migration kuruldu');

let r = d(psql(['-v', 'ON_ERROR_STOP=1']), `
do $$
declare v_tip uuid; v_rol uuid;
begin
  insert into public.pms_oda_tipleri (otel_id, kod, ad, azami_kisi, azami_yetiskin, azami_cocuk)
  values ('810', 'SND', 'Sonda', 2, 2, 0) returning id into v_tip;
  insert into public.pms_odalar (otel_id, oda_tipi_id, oda_no) values ('810', v_tip, 'S01');

  insert into auth.users (id) values ('${AUTH}'::uuid) on conflict (id) do nothing;
  select id into v_rol from public.roller where ad = 'Kat Hizmetleri Şefi';
  insert into public.kullanicilar (auth_user_id, ad, rol, rol_id, otel_id, aktif, tum_oteller)
  values ('${AUTH}'::uuid, 'sonda kullanici', 'yonetici', v_rol, '810', true, false);
  insert into public.yetki_matrisi (rol_id, modul_id, yetki)
  select v_rol, m.id, 'tam'::public.yetki_seviye from public.moduller m where m.kod = 'pms_housekeeping'
  on conflict (rol_id, modul_id) do update set yetki = 'tam';
end $$;`);
if (!r.ok) { console.log('fikstur hatasi: ' + ilkHata(r.err)); spawnSync('docker', ['rm', '-f', K]); process.exit(1); }

const odaId = tek("select id::text from public.pms_odalar where oda_no = 'S01'");
console.log('sonda odasi: ' + odaId + ' | durum: '
  + tek("select kullanim_durumu::text || '/' || temizlik_durumu::text from public.pms_odalar where oda_no = 'S01'"));

let ok = 0;
let fail = 0;
function deneme(etiket, sql, yazmaliMi) {
  const oncesi = tek("select temizlik_durumu::text from public.pms_odalar where oda_no = 'S01'");
  const x = d(psql(['-v', 'ON_ERROR_STOP=1']), sql);
  const sonrasi = tek("select temizlik_durumu::text from public.pms_odalar where oda_no = 'S01'");
  const yazdi = oncesi !== sonrasi;
  const gecti = yazdi === yazmaliMi;
  console.log((gecti ? 'OK   ' : 'FAIL ') + etiket.padEnd(46)
    + (yazdi ? 'YAZDI   ' : 'YAZAMADI') + ' | ' + oncesi + ' -> ' + sonrasi
    + (x.ok ? '' : ' | ' + ilkHata(x.err)));
  if (gecti) ok++; else fail++;
  if (yazdi) d(psql(['-v', 'ON_ERROR_STOP=1']), `${KIMLIK} update public.pms_odalar set temizlik_durumu = 'kirli' where oda_no = 'S01';`);
}

console.log('\n== ODA TEMIZLIGINI DOGRUDAN YAZMA (kirli -> temiz)');
deneme('S1 sahip rolu, kimlik yok', "update public.pms_odalar set temizlik_durumu='temiz' where oda_no='S01';", false);
deneme('S2 authenticated, kimlik yok', "set role authenticated; update public.pms_odalar set temizlik_durumu='temiz' where oda_no='S01';", false);
deneme('S3 authenticated + gercek kimlik', `${KIMLIK} set role authenticated; update public.pms_odalar set temizlik_durumu='temiz' where oda_no='S01';`, false);
deneme('S4 sahip rolu + gercek kimlik', `${KIMLIK} update public.pms_odalar set temizlik_durumu='temiz' where oda_no='S01';`, true);

const komut = `${KIMLIK} set role authenticated;
  select public.pms_housekeeping_gorev_olustur('${odaId}'::uuid, 'ekstra_temizlik', 'bos', gen_random_uuid());`;
console.log('\n== KAT HIZMETLERI KOMUTU (gercek kimlik, uygulama rolu)');
r = d(psql(['-v', 'ON_ERROR_STOP=1']), komut);
if (!r.ok) { console.log('OK   modul KAPALI -> RED (' + ilkHata(r.err) + ')'); ok++; } else { console.log('FAIL modul KAPALI -> GECTI'); fail++; }
d(psql(['-v', 'ON_ERROR_STOP=1']), "update public.moduller set aktif = true where kod = 'pms_housekeeping';");
r = d(psql(['-v', 'ON_ERROR_STOP=1']), komut);
if (r.ok) { console.log('OK   modul ACIK   -> GECTI (gorev olustu)'); ok++; } else { console.log('FAIL modul ACIK -> RED (' + ilkHata(r.err) + ')'); fail++; }

console.log('\nDOGRUDAN YAZMA SONDASI SONUC: ' + ok + ' OK / ' + fail + ' FAIL');
spawnSync('docker', ['rm', '-f', K]);
process.exit(fail ? 1 : 0);
