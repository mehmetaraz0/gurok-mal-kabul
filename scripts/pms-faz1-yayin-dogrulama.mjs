// ============================================================================
// PMS FAZ 1 — YAYIN ADAYI (RELEASE CANDIDATE) DOĞRULAMASI
// ============================================================================
// Tek kullanımlık PostgreSQL konteynerinde, ÜRETİME BAĞLANMADAN:
//
//   A) ZİNCİR SIRASI  — her migration önkoşulunu gerçekten uyguluyor mu?
//      Yanlış sırada çalıştırma REDDEDİLMELİ (Adım 2 önce, Adım 3 önce, ...).
//   B) SIRALI UYGULAMA — Adım 1 → 2 → 3 → 4, her biri iki kez (idempotency),
//      doğrulama blokları dahil.
//   C) UÇTAN UCA      — oda tipi → oda → misafir → rezervasyon → atama →
//      check-in → rack → folyo → oda ücreti → bar devri → tahsilat →
//      bakiye → folyo kapat → check-out → oda boş+kirli.
//
// Kullanım: node scripts/pms-faz1-yayin-dogrulama.mjs
import { spawnSync } from 'node:child_process';
import { readFileSync, existsSync } from 'node:fs';
import { setTimeout as bekle } from 'node:timers/promises';

const kok = new URL('..', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const DOSYALAR = {
  shim:  kok + 'scripts/supabase-shim.sql',
  dokum: kok + 'docs/kurulum/2026-09-06-sema-dokumu.sql',
  adim1: kok + 'docs/kurulum/2026-09-06-pms-faz1-oda-tipleri-odalar.sql',
  adim2: kok + 'docs/kurulum/2026-09-06-pms-faz1-adim2-misafir-rezervasyon.sql',
  adim3: kok + 'docs/kurulum/2026-09-06-pms-faz1-adim3-checkin-checkout.sql',
  adim4: kok + 'docs/kurulum/2026-09-06-pms-faz1-adim4-folio.sql',
};
for (const [ad, yol] of Object.entries(DOSYALAR)) {
  if (!existsSync(yol)) { console.error('Dosya yok (' + ad + '): ' + yol); process.exit(1); }
}
const oku = (ad) => readFileSync(DOSYALAR[ad], 'utf8');

const konteyner = 'pms-yayin-dogrulama';
const psqlArgs = ['exec', '-i', konteyner, 'psql', '-X', '-U', 'postgres', '-d', 'pmsrc'];
// ON_ERROR_STOP olmadan psql ifade hatasindan sonra devam eder ve 0 ile cikar;
// o hâlde "cikis kodu 0" hicbir sey kanitlamaz.
const psqlKati = [...psqlArgs, '-v', 'ON_ERROR_STOP=1'];

function docker(a, girdi) {
  const r = spawnSync('docker', a, {
    input: girdi, encoding: 'utf8', timeout: 300000, maxBuffer: 64 * 1024 * 1024,
  });
  return { ok: !r.error && r.status === 0, out: r.stdout || '', err: r.error?.message || r.stderr || '' };
}
function temizle() { spawnSync('docker', ['rm', '-f', konteyner], { encoding: 'utf8' }); }
function bitir(kod) { temizle(); process.exit(kod); }
function sorgu(sql) {
  return (spawnSync('docker', [...psqlArgs, '-At', '-c', sql], { encoding: 'utf8' }).stdout || '').trim();
}

let sonuc = 0;
const kontroller = [];
function ol(gecti, etiket, detay) {
  kontroller.push({ gecti, etiket, detay });
  if (!gecti) sonuc = 1;
}

// ---------------------------------------------------------------------------
// Ortam
// ---------------------------------------------------------------------------
temizle();
let r = docker(['run', '--detach', '--rm', '--network', 'none', '--name', konteyner,
  '--tmpfs', '/var/lib/postgresql/data', '-e', 'POSTGRES_HOST_AUTH_METHOD=trust', 'postgres:17']);
if (!r.ok) { console.error('Konteyner baslatilamadi: ' + r.err.slice(0, 300)); process.exit(1); }
for (let i = 0; i < 60; i++) {
  if (spawnSync('docker', ['exec', konteyner, 'pg_isready', '-U', 'postgres']).status === 0) break;
  await bekle(1000);
}
docker(['exec', konteyner, 'createdb', '-U', 'postgres', 'pmsrc']);

r = docker(psqlKati, oku('shim'));
if (!r.ok) { console.error('Supabase iskelesi BASARISIZ\n' + r.err.slice(-1500)); bitir(1); }
console.log('1) Supabase iskelesi   : kuruldu');

// Dokum `create schema public` iceriyor; iskele onu zaten olusturdu. Bu TEK
// hata elenir, digerleri elenmez -- yoksa bozuk bir dokum sessizce gecerdi.
r = docker(psqlArgs, oku('dokum'));
const dokumHatalari = r.err.split('\n').filter((l) => l.startsWith('ERROR:'))
  .filter((l) => !/schema "public" already exists/.test(l));
if (dokumHatalari.length) {
  console.error('Uretim kopyasi BASARISIZ\n' + dokumHatalari.slice(0, 5).join('\n'));
  bitir(1);
}
console.log('2) Uretim kopyasi      : hatasiz (dogrulanmis sema dokumu)');

// ---------------------------------------------------------------------------
// A) ZİNCİR SIRASI — yanlış sıra reddedilmeli
// ---------------------------------------------------------------------------
// Bu, "migration'lari elle yanlis sirada calistirma" riskini olcen tek testtir.
// Onkosul kontrolu YOKSA yanlis sirali kurulum sessizce yarim sema uretir.
console.log('\n3) Zincir sirasi (yanlis sira REDDEDILMELI):');
for (const [ad, beklenen] of [
  ['adim2', /Adim 1 uygulanmamis/i],
  ['adim3', /Adim 1\/2 uygulanmamis/i],
  ['adim4', /Adim 2 uygulanmamis|Adim 3 uygulanmamis/i],
]) {
  const q = docker(psqlKati, oku(ad));
  const reddedildi = !q.ok && beklenen.test(q.err);
  ol(reddedildi, ad + ' Adim 1 olmadan reddedildi',
    reddedildi ? '' : (q.ok ? 'KABUL EDILDI' : 'yanlis hata: ' + (q.err.split('\n').find((l) => l.startsWith('ERROR:')) || '').slice(0, 90)));
  console.log((reddedildi ? '   OK   ' : '   HATA ') + ad + ' onkosulsuz reddedildi'
    + (reddedildi ? '' : '  <-- ' + kontroller[kontroller.length - 1].detay));
}

// ---------------------------------------------------------------------------
// B) SIRALI UYGULAMA + IDEMPOTENCY
// ---------------------------------------------------------------------------
console.log('\n4) Sirali uygulama (her biri iki kez):');
for (const ad of ['adim1', 'adim2', 'adim3', 'adim4']) {
  const ilk = docker(psqlKati, oku(ad));
  if (!ilk.ok) {
    console.log('   HATA ' + ad + ' ilk uygulama BASARISIZ');
    console.error(ilk.err.split('\n').filter((l) => l.startsWith('ERROR:')).slice(0, 5).join('\n'));
    ol(false, ad + ' ilk uygulama', 'basarisiz');
    bitir(1);
  }
  const tekrar = docker(psqlKati, oku(ad));
  ol(tekrar.ok, ad + ' tekrar uygulama (idempotent)',
    tekrar.ok ? '' : (tekrar.err.split('\n').find((l) => l.startsWith('ERROR:')) || '').slice(0, 110));
  console.log('   ' + (tekrar.ok ? 'OK  ' : 'HATA') + ' ' + ad + ' : uygulandi + tekrar uygulandi'
    + (tekrar.ok ? '' : '  <-- ' + kontroller[kontroller.length - 1].detay));
}

// ---------------------------------------------------------------------------
// C) UÇTAN UCA SENARYO
// ---------------------------------------------------------------------------
// Tek bir gercek konaklama zinciri. Her adim ONCEKININ ciktisini kullanir;
// boylece modullerin ayri ayri degil BIRLIKTE calistigi olculur.
const tezgah = `
select set_config('request.jwt.claim.role','authenticated',false);
select set_config('request.jwt.claim.sub','a0000000-0000-0000-0000-0000000000e2',false);
insert into auth.users (id, email) values
  ('a0000000-0000-0000-0000-0000000000e2','e2e@ornek.gecersiz') on conflict do nothing;
insert into public.roller (id, ad, seviye, kod, aktif) values
  ('b0000000-0000-0000-0000-0000000000e2','E2E Tam','otel','e2e_tam',true) on conflict do nothing;
insert into public.moduller (kod, ad, kategori, sira, aktif) values
  ('bar_siparis_yonetimi','Bar Siparis Yonetimi','bar', 90, true)
on conflict (kod) do nothing;
insert into public.yetki_matrisi (rol_id, modul_id, yetki)
select 'b0000000-0000-0000-0000-0000000000e2', id, 'tam'::public.yetki_seviye
from public.moduller
where kod in ('pms_oda_tipi','pms_oda','pms_misafir','pms_rezervasyon','pms_folio',
              'bar_siparis_yonetimi')
on conflict do nothing;
insert into public.kullanicilar (id, auth_user_id, rol, rol_id, otel_id, aktif, tum_oteller, ad)
values ('c0000000-0000-0000-0000-0000000000e2','a0000000-0000-0000-0000-0000000000e2',
        'yonetici','b0000000-0000-0000-0000-0000000000e2','810', true, false, 'E2E')
on conflict do nothing;
insert into public.menu_urunler (id, otel_id, ad, fiyat, ucretli, aktif) values
  ('c1000000-0000-0000-0000-0000000000e2','810','Sise Su', 60.00, true, true)
on conflict do nothing;`;
r = docker(psqlKati, tezgah);
if (!r.ok) { console.error('E2E tezgahi BASARISIZ\n' + r.err.slice(-1200)); bitir(1); }

// Zincir TEK oturumda, authenticated rolüyle: RLS ve yetki devrede.
const zincir = `
set role authenticated;
select set_config('request.jwt.claim.role','authenticated',false);
select set_config('request.jwt.claim.sub','a0000000-0000-0000-0000-0000000000e2',false);

-- 1) oda tipi -> 2) oda
insert into public.pms_oda_tipleri (id, otel_id, kod, ad, azami_kisi, azami_yetiskin)
values ('d0000000-0000-0000-0000-0000000000e2','810','E2E','E2E Tip',2,2);
insert into public.pms_odalar (id, otel_id, oda_tipi_id, oda_no, temizlik_durumu)
values ('e0000000-0000-0000-0000-0000000000e2','810',
        'd0000000-0000-0000-0000-0000000000e2','E2E-1','temiz');

-- 3) misafir -> 4) rezervasyon (onaylandi -> folyo OTOMATIK acilir)
insert into public.pms_misafirler (id, otel_id, ad, soyad)
values ('f0000000-0000-0000-0000-0000000000e2','810','Ayse','Yilmaz');
insert into public.pms_rezervasyonlar
  (id, otel_id, misafir_id, oda_tipi_id, giris_tarihi, cikis_tarihi, durum, gecelik_fiyat)
values ('11000000-0000-0000-0000-0000000000e2','810','f0000000-0000-0000-0000-0000000000e2',
        'd0000000-0000-0000-0000-0000000000e2', current_date - 1, current_date + 1,
        'onaylandi', 800.00);

-- 5) oda ata + 6) check-in (state makinesi RPC uzerinden)
select public.pms_check_in('11000000-0000-0000-0000-0000000000e2',
                           'e0000000-0000-0000-0000-0000000000e2');

-- 8) oda ucreti isle (gecmis 1 gece: current_date-1)
select public.pms_folio_oda_ucreti_isle('11000000-0000-0000-0000-0000000000e2');
`;
r = docker(psqlKati, zincir);
if (!r.ok) {
  console.error('\nE2E zinciri BASARISIZ\n'
    + r.err.split('\n').filter((l) => l.startsWith('ERROR:')).slice(0, 4).join('\n'));
  bitir(1);
}

// 7) room rack: oda DOLU ve icerde konaklayan var
ol(sorgu(`select kullanim_durumu from public.pms_odalar where id='e0000000-0000-0000-0000-0000000000e2';`) === 'dolu',
   'check-in sonrasi oda dolu (room rack)');
ol(sorgu(`select durum from public.pms_rezervasyonlar where id='11000000-0000-0000-0000-0000000000e2';`) === 'giris_yapildi',
   'rezervasyon giris_yapildi');
ol(sorgu(`select count(*) from public.pms_folyolar where rezervasyon_id='11000000-0000-0000-0000-0000000000e2' and durum='acik';`) === '1',
   'folyo otomatik acildi');
ol(Number(sorgu(`select bakiye from public.pms_folio_ozet where rezervasyon_id='11000000-0000-0000-0000-0000000000e2';`)) === 1600,
   'oda ucreti islendi (2 gece x 800 = 1600)');

// 9) bar devri
const folio = sorgu(`select id from public.pms_folyolar where rezervasyon_id='11000000-0000-0000-0000-0000000000e2';`);
r = docker(psqlKati, `
set role authenticated;
select set_config('request.jwt.claim.role','authenticated',false);
select set_config('request.jwt.claim.sub','a0000000-0000-0000-0000-0000000000e2',false);
insert into public.bar_siparisleri (id, otel_id, depo_id, oda_no, durum)
values ('c2000000-0000-0000-0000-0000000000e2','810','BARE2E','E2E-1','hazir');
insert into public.bar_siparis_kalemleri (siparis_id, menu_urun_id, adet)
values ('c2000000-0000-0000-0000-0000000000e2','c1000000-0000-0000-0000-0000000000e2', 2);
update public.bar_siparisleri set durum='teslim_edildi'
 where id='c2000000-0000-0000-0000-0000000000e2';`);
ol(r.ok, 'bar siparisi odaya devredildi',
   r.ok ? '' : (r.err.split('\n').find((l) => l.startsWith('ERROR:')) || '').slice(0, 100));
ol(Number(sorgu(`select bakiye from public.pms_folio_ozet where folio_id='${folio}';`)) === 1720,
   'bar devri sonrasi bakiye 1600 + 120 = 1720');

// 10) tahsilat -> 11) bakiye -> 12) folyo kapat
r = docker(psqlKati, `
set role authenticated;
select set_config('request.jwt.claim.role','authenticated',false);
select set_config('request.jwt.claim.sub','a0000000-0000-0000-0000-0000000000e2',false);
insert into public.pms_folio_odemeler (otel_id, folio_id, yontem, tutar, islem_anahtari)
values ('810','${folio}','kredi_karti', 1720.00, 'e2e-odeme-anahtari-1');
select public.pms_folio_kapat('${folio}');`);
ol(r.ok, 'tahsilat + folyo kapatma',
   r.ok ? '' : (r.err.split('\n').find((l) => l.startsWith('ERROR:')) || '').slice(0, 100));
ol(Number(sorgu(`select bakiye from public.pms_folio_ozet where folio_id='${folio}';`)) === 0,
   'kapanista bakiye sifir');
ol(sorgu(`select durum from public.pms_folyolar where id='${folio}';`) === 'kapali',
   'folyo kapandi');

// 13) check-out -> 14) oda bos + kirli
r = docker(psqlKati, `
set role authenticated;
select set_config('request.jwt.claim.role','authenticated',false);
select set_config('request.jwt.claim.sub','a0000000-0000-0000-0000-0000000000e2',false);
select public.pms_check_out('11000000-0000-0000-0000-0000000000e2');`);
ol(r.ok, 'check-out yapildi',
   r.ok ? '' : (r.err.split('\n').find((l) => l.startsWith('ERROR:')) || '').slice(0, 100));
ol(sorgu(`select kullanim_durumu || '/' || temizlik_durumu from public.pms_odalar where id='e0000000-0000-0000-0000-0000000000e2';`) === 'bos/kirli',
   'cikis sonrasi oda bos + kirli');
ol(sorgu(`select durum from public.pms_rezervasyonlar where id='11000000-0000-0000-0000-0000000000e2';`) === 'cikis_yapildi',
   'rezervasyon cikis_yapildi');

// Kapali folyo check-out'tan SONRA da kapali; bakiye bozulmadi.
ol(Number(sorgu(`select bakiye from public.pms_folio_ozet where folio_id='${folio}';`)) === 0,
   'check-out folyo bakiyesini bozmadi');

console.log('\n5) Uctan uca PMS zinciri:');
for (const k of kontroller.slice(3)) {
  console.log((k.gecti ? '   OK   ' : '   HATA ') + k.etiket + (k.gecti ? '' : '  <-- ' + (k.detay || 'beklenen deger cikmadi')));
}

console.log('\n' + '='.repeat(70));
console.log(sonuc === 0
  ? 'SONUC: PMS FAZ 1 YAYIN ADAYI DOGRULAMASI GECTI\n'
    + '       zincir sirasi + idempotency + uctan uca konaklama'
  : 'SONUC: PMS FAZ 1 YAYIN ADAYI DOGRULAMASI BASARISIZ');
console.log('='.repeat(70));
bitir(sonuc);
