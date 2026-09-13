// ============================================================================
// YEDEK GERI YUKLEME PROVASI — izole, uretime baglanmaz
// ============================================================================
// NEDEN VAR: Proje Free planda ve Supabase PROJE YEDEGI ALMIYOR (2026-09-12'de
// panelden olculdu). Tek yedek, elle alinan dokumdur. "Dosya olustu" bir yedek
// KANITI DEGILDIR: yayin plani E-5, ancak bu prova gectiginde kapanir.
//
// KULLANIM:
//   node scripts/pms-yedek-geri-yukleme-provasi.mjs <veri-yedegi> [sayaclar.json]
//
//   <veri-yedegi>  : .sql  -> psql ile yuklenir
//                    .dump -> pg_restore ile yuklenir (pg_dump -Fc ciktisi)
//   [sayaclar.json]: docs/kurulum/2026-09-13-yedek-dogrulama-sayaclari.sql
//                    ciktisinin kaydedilmis hali (uretimden, yedekle AYNI anda)
//
// Dosyalar REPO DISINDA tutulur (varsayilan C:\Users\USER\ERP-Yedek).
//
// OLCTUKLERI
//   1) Geri yukleme SURESI (duvar saati) — yayin raporunda kullanilir
//   2) Yukleme hatalari (0 olmali)
//   3) Tablo satir sayilari — sayaclar.json ile BIREBIR karsilastirma
//   4) Veri tutarliligi: dolu oda <-> devam eden konaklama, aktif atama,
//      folyo/denetim izi ozetleri
//   5) RPO: yedegin alindigi an ile simdi arasindaki fark (olasi veri kaybi)
// ============================================================================
import { spawnSync } from 'node:child_process';
import { readFileSync, existsSync, statSync } from 'node:fs';
import { setTimeout as bekle } from 'node:timers/promises';

const kok = new URL('..', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const yedek = process.argv[2];
const sayacDosyasi = process.argv[3];
if (!yedek || !existsSync(yedek)) {
  console.error('Kullanim: node scripts/pms-yedek-geri-yukleme-provasi.mjs <veri-yedegi> [sayaclar.json]');
  process.exit(2);
}

const K = 'pms-yedek-prova';
const d = (a, g) => {
  const r = spawnSync('docker', a, { input: g, encoding: 'utf8', timeout: 1800000, maxBuffer: 256 * 1024 * 1024 });
  return { ok: !r.error && r.status === 0, out: r.stdout || '', err: r.error?.message || r.stderr || '' };
};
const psql = (ek = []) => ['exec', '-i', K, 'psql', '-X', '-U', 'postgres', '-d', 'geri', ...ek];
const tek = (q) => d(psql(['-At', '-v', 'ON_ERROR_STOP=1']), q).out.trim();
const hatalar = (s) => s.split('\n')
  .filter((l) => l.includes('ERROR:'))
  .filter((l) => !/schema "public" already exists/.test(l));

const SAYAC_SORGUSU = `
select jsonb_build_object(
  'tablo_sayisi', (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace
                    where n.nspname='public' and c.relkind='r'),
  'satir_sayilari', (
    select jsonb_object_agg(t.tablo, t.adet order by t.tablo) from (
      select c.relname as tablo,
             (xpath('/row/c/text()', query_to_xml(format('select count(*) as c from public.%I', c.relname),
                                                  false, true, '')))[1]::text::bigint as adet
        from pg_class c join pg_namespace n on n.oid=c.relnamespace
       where n.nspname='public' and c.relkind='r') t),
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
r = d(psql(['-v', 'ON_ERROR_STOP=1']), readFileSync(kok + 'scripts/supabase-shim.sql', 'utf8'));
console.log('1) Supabase iskelesi : ' + (r.ok ? 'kuruldu' : 'HATA ' + r.err.slice(0, 200)));

const istatistik = statSync(yedek);
console.log('2) Yedek dosyasi     : ' + yedek);
console.log('   boyut             : ' + istatistik.size.toLocaleString('tr-TR') + ' bayt');
console.log('   dosya tarihi      : ' + istatistik.mtime.toISOString());

const baslangic = Date.now();
let yuklemeHatalari = [];
if (/\.dump$/i.test(yedek)) {
  const kopya = d(['cp', yedek, K + ':/tmp/yedek.dump']);
  if (!kopya.ok) { console.error('Dosya konteynere kopyalanamadi: ' + kopya.err.slice(0, 200)); spawnSync('docker', ['rm', '-f', K]); process.exit(1); }
  r = d(['exec', K, 'pg_restore', '-U', 'postgres', '-d', 'geri', '--no-owner', '--no-privileges', '/tmp/yedek.dump']);
  yuklemeHatalari = r.err.split('\n').filter((l) => /error|ERROR/.test(l));
} else {
  r = d(psql(), readFileSync(yedek, 'utf8'));
  yuklemeHatalari = hatalar(r.err);
}
const sureSn = (Date.now() - baslangic) / 1000;
console.log('3) Geri yukleme      : ' + sureSn.toFixed(1) + ' saniye, ' + yuklemeHatalari.length + ' hata');
for (const h of yuklemeHatalari.slice(0, 5)) console.log('   ' + h.slice(0, 180));

const ham = tek(SAYAC_SORGUSU);
let olculen = null;
try { olculen = JSON.parse(ham); } catch { /* asagida ele alinir */ }
if (!olculen) {
  console.error('Geri yuklenen kopyadan sayaclar okunamadi. Yukleme basarisiz olabilir.');
  spawnSync('docker', ['rm', '-f', K]);
  process.exit(1);
}

console.log('\n4) GERI YUKLENEN KOPYA');
console.log('   tablo sayisi      : ' + olculen.tablo_sayisi);
console.log('   toplam satir      : ' + Object.values(olculen.satir_sayilari || {}).reduce((a, b) => a + Number(b), 0));
console.log('   denetim izi son   : ' + (olculen.denetim_izi_son_kayit || '-'));
console.log('   pms ozet          : ' + JSON.stringify(olculen.pms_ozet));

let fark = 0;
if (sayacDosyasi && existsSync(sayacDosyasi)) {
  const beklenen = JSON.parse(readFileSync(sayacDosyasi, 'utf8'));
  console.log('\n5) URETIM SAYACLARIYLA KARSILASTIRMA (' + sayacDosyasi + ')');
  console.log('   yedek alinma zamani: ' + (beklenen.alinma_zamani || '(kayitli degil)'));
  const b = beklenen.satir_sayilari || {};
  const o = olculen.satir_sayilari || {};
  const tumTablolar = [...new Set([...Object.keys(b), ...Object.keys(o)])].sort();
  for (const t of tumTablolar) {
    const bs = b[t] === undefined ? null : Number(b[t]);
    const os = o[t] === undefined ? null : Number(o[t]);
    if (bs !== os) { console.log('   FARK  ' + t.padEnd(34) + ' uretim=' + bs + '  kopya=' + os); fark++; }
  }
  if (beklenen.tablo_sayisi !== undefined && Number(beklenen.tablo_sayisi) !== Number(olculen.tablo_sayisi)) {
    console.log('   FARK  tablo sayisi: uretim=' + beklenen.tablo_sayisi + ' kopya=' + olculen.tablo_sayisi);
    fark++;
  }
  console.log('   karsilastirilan tablo: ' + tumTablolar.length + ' | fark: ' + fark);
  if (beklenen.alinma_zamani) {
    const yas = (Date.now() - new Date(beklenen.alinma_zamani).getTime()) / 60000;
    console.log('   RPO (yedek yasi)  : ' + yas.toFixed(1) + ' dakika — bu sureye ait yazmalar geri donuste KAYBOLUR');
  }
} else {
  console.log('\n5) URETIM SAYACLARI VERILMEDI — karsilastirma yapilamadi.');
  console.log('   docs/kurulum/2026-09-13-yedek-dogrulama-sayaclari.sql ciktisini kaydedip ikinci argumanla verin.');
  fark = -1;
}

console.log('\n6) VERI TUTARLILIGI (geri yuklenen kopyada)');
const tutarlilik = [
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
for (const [ad, sorgu] of tutarlilik) {
  const deger = tek(sorgu + ';');
  const sayi = Number(deger);
  if (Number.isNaN(sayi)) { console.log('   ? ' + ad + ' -> okunamadi'); tutarsiz++; continue; }
  console.log((sayi === 0 ? '   OK   ' : '   FAIL ') + ad + ' = ' + sayi);
  if (sayi !== 0) tutarsiz++;
}

const gecti = yuklemeHatalari.length === 0 && fark === 0 && tutarsiz === 0;
console.log('\n' + '='.repeat(70));
console.log('SONUC: ' + (gecti
  ? 'GERI YUKLEME PROVASI GECTI — yedek kullanilabilir.'
  : 'GERI YUKLEME PROVASI GECMEDI — yedek KANIT SAYILMAZ.'));
console.log('Geri yukleme suresi: ' + sureSn.toFixed(1) + ' saniye (bu boyut ve bu makine icin).');
console.log('='.repeat(70));
spawnSync('docker', ['rm', '-f', K]);
process.exit(gecti ? 0 : 1);
