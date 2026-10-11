// ===========================================================================
// stok_acik_talep DURUM FILTRESI — IZOLE REGRESYON (uretime BAGLANMAZ)
// ===========================================================================
// Duzeltme: docs/kurulum/2026-10-11-stok-acik-talep-durum-filtresi.sql
// Onkosul : docs/kurulum/2026-08-04-stok-tablo-viewlar.sql (uretimde 2026-10-10)
//
// Bu testin varlik sebebi: duzeltilen kusur SESSIZDI. Filtre, `talep_durum`
// enum'unda bulunmayan 'tamamlandi' etiketini dislamaya calisiyordu; `::text`
// cast'i yuzunden hata vermiyor, terim hic eslesmiyordu. Boyle bir kusur
// ancak kendisini kiran bir testle kapali tutulur.
//
//   A1  Duzeltme hatasiz uygulaniyor mu
//   A2  Gorunum tanimi GERCEK etiketleri tasiyor, 'tamamlandi' TASIMIYOR
//   A3  authenticated SELECT hakki korundu mu
//   A4  Idempotent mi (ikinci kez uygulanabiliyor mu)
//   S1  TUTARSIZ satir (siparis_no bos + durum 'siparis') artik SAYILMIYOR;
//       uygulanmis eski surumde SAYILIYORDU  -> davranis degisikligi kanitli
//   M1  MUTANT: dislama listesine var olmayan etiket konursa migration DURUR
//       (::text kaldirilmasinin fail-loud kazanimi)
//   M2  Onkosul kapisi: gorunum yoksa migration DURUR
//
// Kullanim: node scripts/stok-acik-talep-filtresi.test.mjs
// ===========================================================================
import { readFileSync } from 'node:fs';
import { barOrtami } from './bar-test-ortam.mjs';

const KOK = new URL('..', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const VIEWLAR = KOK + 'docs/kurulum/2026-08-04-stok-tablo-viewlar.sql';
const DUZELTME = KOK + 'docs/kurulum/2026-10-11-stok-acik-talep-durum-filtresi.sql';
const O = barOrtami({ ad: 'stok-talep', ag: 'stok-talep-net' });

let ok = 0, fail = 0;
const sonuc = (g, ad, ek) => {
  console.log((g ? 'OK   ' : 'FAIL ') + ad + (ek ? ' — ' + ek : ''));
  if (g) ok++; else fail++;
};
const es = (ad, bek, olc) => sonuc(String(bek) === String(olc), ad,
  String(bek) === String(olc) ? String(olc) : `beklenen=${bek} olculen=${olc}`);
// numeric(12,3) "7.000" dondurur; miktar karsilastirmalari SAYISAL yapilir,
// yoksa dogru olcum yanlis-kirmizi verir (olculdu).
const esSayi = (ad, bek, olc) => sonuc(Number(bek) === Number(olc), ad,
  Number(bek) === Number(olc) ? String(olc) : `beklenen=${bek} olculen=${olc}`);
const tek = (q) => O.sql(q).out.trim();
const hata = (r) => (String(r.err).split('\n')
  .filter((l) => /ERROR|HATA/.test(l))[0] || '(mesaj yok)').slice(0, 110);

try {
  await O.kur();

  // --- Onkosul: uretimde 2026-10-10'da uygulanan gorunumler ---------------
  const v = O.sql(readFileSync(VIEWLAR, 'utf8'));
  sonuc(v.ok, 'F1 onkosul gorunumleri kuruldu (2026-08-04 dosyasi)',
    v.ok ? '' : hata(v));

  // --- M2: gorunum YOKSA duzeltme durmali --------------------------------
  O.sql('drop view if exists public.stok_acik_talep;');
  const m2 = O.sql(readFileSync(DUZELTME, 'utf8'));
  sonuc(!m2.ok && /ONKOSUL: stok_acik_talep gorunumu yok/.test(m2.err + m2.out),
    'M2 gorunum yokken duzeltme DURDU (onkosul kapisi)', hata(m2));
  O.sql(readFileSync(VIEWLAR, 'utf8'));   // geri kur

  // --- S1 hazirlik: TUTARSIZ satir (siparis_no bos + durum 'siparis') -----
  // Phase 0 denetim tetikleyicileri kimliksiz yazmayi reddeder; fikstur
  // bilincli olarak tetikleyiciler kapaliyken kurulur.
  const TALEP_ID = 'aaaaaaaa-0000-0000-0000-00000000a001';
  const f = O.sql(`set session_replication_role = replica;
    insert into public.satin_alma_talepleri
      (id, departman, otel_id, durum, siparis_no)
    values ('${TALEP_ID}'::uuid, 'TEST-DEPARTMAN', '810', 'siparis', null)
      on conflict (id) do nothing;
    insert into public.satin_alma_talep_kalemleri
      (talep_id, urun_adi, urun_kodu, miktar)
    values ('${TALEP_ID}'::uuid, 'Tutarsiz test kalemi', 'TEST-TUTARSIZ', 7);
    set session_replication_role = origin;`);
  sonuc(f.ok, 'F2 tutarsiz talep fiksturu kuruldu (siparis_no bos, durum=siparis)',
    f.ok ? '' : hata(f));

  const sayOncesi = tek(
    "select coalesce(sum(talep_miktar),0)::text from public.stok_acik_talep " +
    "where urun_kodu = 'TEST-TUTARSIZ';");
  esSayi('S1a ESKI surumde tutarsiz satir SAYILIYORDU', 7, sayOncesi);

  // --- A1..A4: duzeltmeyi uygula -----------------------------------------
  const d = O.sql(readFileSync(DUZELTME, 'utf8'));
  sonuc(d.ok, 'A1 duzeltme hatasiz uygulandi', d.ok ? '' : hata(d));
  sonuc(/stok_acik_talep yeniden kuruldu/.test(String(d.out) + String(d.err)),
    'A1b kendi dogrulama/etki raporu kostu');

  const tanim = tek("select pg_get_viewdef('public.stok_acik_talep', true);");
  sonuc(['reddedildi', 'iptal', 'siparise_donustu', 'siparis']
    .every((e) => tanim.includes(e)),
    'A2 gorunum tanimi dort GERCEK etiketi tasiyor');
  sonuc(!/tamamlandi/.test(tanim),
    "A2b gorunum tanimi artik 'tamamlandi' TASIMIYOR");

  sonuc(tek("select has_table_privilege('authenticated','public.stok_acik_talep','SELECT')::text;") === 'true',
    'A3 authenticated SELECT hakki korundu');

  const saySonrasi = tek(
    "select coalesce(sum(talep_miktar),0)::text from public.stok_acik_talep " +
    "where urun_kodu = 'TEST-TUTARSIZ';");
  esSayi('S1b YENI surumde tutarsiz satir SAYILMIYOR', 0, saySonrasi);

  const d2 = O.sql(readFileSync(DUZELTME, 'utf8'));
  sonuc(d2.ok && tek("select coalesce(sum(talep_miktar),0)::text from public.stok_acik_talep where urun_kodu = 'TEST-TUTARSIZ';") === '0',
    'A4 idempotent: ikinci kez uygulandi, sonuc ayni', d2.ok ? '' : hata(d2));

  // --- M1 MUTANT: var olmayan etiket artik SESSIZ KALMAMALI --------------
  // `::text` kaldirildigi icin liste enum olarak dogrulanir. Hem onkosul
  // kapisi hem de PostgreSQL'in kendi enum donusumu bunu yakalamali.
  const mutant = readFileSync(DUZELTME, 'utf8')
    .split("'siparise_donustu','siparis'").join("'siparise_donustu','tamamlandi'");
  if (mutant === readFileSync(DUZELTME, 'utf8')) throw new Error('M1 capasi tutmadi');
  const m1 = O.sql(mutant);
  sonuc(!m1.ok, 'M1 var olmayan etiketli mutant DURDU (sessiz etkisiz terim yok)',
    hata(m1));
  sonuc(!/tamamlandi/.test(tek("select pg_get_viewdef('public.stok_acik_talep', true);")),
    'M1b mutant gorunumu DEGISTIRMEDI');

  console.log(`\nSONUC: ${ok} gecti, ${fail} kaldi`);
  console.log('Yerel kanit; CANLI UYGULAMA yerine GECMEZ.');
} catch (e) {
  console.error('\nDUR: ' + (e && e.message));
  fail++;
} finally {
  try { O.temizle(); } catch { /* yoksay */ }
}
process.exit(fail === 0 ? 0 : 1);
