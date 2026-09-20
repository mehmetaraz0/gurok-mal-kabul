// ===========================================================================
// SAYIM ERISIM DUZELTMESI — IZOLE TEST (uretime BAGLANMAZ)
// ===========================================================================
// Taban: uretim dokumu + A1 migration'i. Once BUGUNKU durum olculur (sayim
// olusturma/listeleme/reddetme calismiyor), sonra aday duzeltme uygulanir ve
// ayni olcumler tekrarlanir. Negatif kontroller duzeltmenin fazla yetki
// ACMADIGINI gosterir.
//
// Kullanicilar (scripts/bar-test-tohum.sql):
//   DEPO810     stok_takip kayit, otel 810   -> sayim yapabilmeli
//   BAR810      stok_takip kayit, otel 810   -> yapabilmeli (ayni kapi)
//   GORUNTU810  stok_takip YOK               -> yapamamali
//   BAR811      stok_takip kayit, otel 811   -> 810'un sayimini GOREMEMELI
//   PASIF       pasif kullanici              -> yapamamali
// ===========================================================================
import { barOrtami } from './bar-test-ortam.mjs';
import { K } from './bar-a1-tohum.mjs';

const A1 = 'docs/kurulum/2026-09-18-bar-a1-guvenlik.sql';
const DUZELTME = 'docs/kurulum/2026-09-20-sayim-rls-dar-duzeltme.sql';
const GERI_AL = 'docs/kurulum/2026-09-20-sayim-rls-dar-duzeltme-geri-al.sql';

const GORUNTU810 = { rol: 'authenticated', sub: '11111111-0000-0000-0000-0000000000bb' };
const OTURUM = '99999999-0000-0000-0000-0000000000a1';
const DEPO = '810_CSM302';

const O = barOrtami({ ad: 'sayim-rls' });
let ok = 0, fail = 0;
const sonuc = (g, ad, ek) => { console.log((g ? 'OK   ' : 'FAIL ') + ad + (ek ? ' — ' + ek : '')); if (g) ok++; else fail++; };

const q = (kimlik, sql) => O.kimlikle(kimlik, sql);
const tek = (sql) => O.sql(sql).out;
const yeniId = () => tek(`select gen_random_uuid();`);

// Ekranin yaptigi cagrilarin BIREBIR SQL esi (PostgREST ayni haklarla calisir).
const oturumEkle = (kimlik, id, otel = '810') => q(kimlik,
  `insert into public.sayim_oturumlari (id, depo_kodu, otel_id, olusturan_ad, durum, toplam_urun_sayisi, farkli_urun_sayisi)
   values ('${id}', '${otel === '810' ? DEPO : '811_BAR'}', '${otel}', 'Test', 'onay_bekliyor', 1, 1);`);
const detayEkle = (kimlik, oturumId) => q(kimlik,
  `insert into public.sayim_detaylari (oturum_id, urun_kodu, urun_adi, birim, sistem_miktar, sayilan_miktar, fark, fark_yuzde)
   values ('${oturumId}', 'BIRA', 'Bira', 'KTU', 10, 8, -2, 20);`);
const oturumSayisi = (kimlik) => q(kimlik, `select count(*) from public.sayim_oturumlari;`).out;
const reddet = (kimlik, id) => q(kimlik,
  `update public.sayim_oturumlari set durum='reddedildi', onaylayan_ad='Test', onay_tarihi=now(), red_nedeni='test'
    where id='${id}';`);

try {
  await O.kur();
  const a = O.uygulaTekIslem(A1);
  sonuc(a.ok, 'Taban: A1 migration uygulandi', a.ok ? '' : a.err.split('\n').slice(-4).join(' | '));
  if (!a.ok) throw new Error('A1 uygulanamadi');

  // ---------------- ONCE: bugunku durum ----------------
  const o1 = oturumEkle(K.DEPO810, OTURUM);
  sonuc(!o1.ok && /row-level security/i.test(o1.err),
    'S1 ONCE: sayim olusturma RLS ile REDDEDILIYOR (ozellik bugun calismiyor)', (o1.err || '').split('\n').pop());

  // Tohum: oturum + detay dogrudan (superuser) — listeleme/reddetme olcumu icin
  tek(`set session_replication_role = replica;
       insert into public.sayim_oturumlari (id, depo_kodu, otel_id, olusturan_ad, durum, toplam_urun_sayisi, farkli_urun_sayisi)
         values ('${OTURUM}', '${DEPO}', '810', 'Tohum', 'onay_bekliyor', 1, 1);
       insert into public.sayim_detaylari (oturum_id, urun_kodu, urun_adi, birim, sistem_miktar, sayilan_miktar, fark, fark_yuzde)
         values ('${OTURUM}', 'BIRA', 'Bira', 'KTU', 10, 8, -2, 20);
       set session_replication_role = origin;`);

  sonuc(oturumSayisi(K.DEPO810) === '0', 'S2 ONCE: listeleme 0 satir (izin veren politika yok)');
  const r1 = reddet(K.DEPO810, OTURUM);
  sonuc(r1.ok && tek(`select durum from public.sayim_oturumlari where id='${OTURUM}';`) === 'onay_bekliyor',
    'S3 ONCE: reddetme sessizce yazmiyor (0 satir)');
  sonuc(O.sql(`select has_table_privilege('authenticated','public.sayim_oturumlari','truncate');`).out === 't',
    'S4 ONCE: authenticated TRUNCATE hakkina sahip (RLS dinlemez)');

  // ---------------- DUZELTME ----------------
  const d = O.uygulaTekIslem(DUZELTME);
  sonuc(d.ok, 'S5 Duzeltme tek islemde uygulandi (son kosullari kendi dogruluyor)',
    d.ok ? '' : d.err.split('\n').slice(-4).join(' | '));
  if (!d.ok) throw new Error('duzeltme uygulanamadi');

  // ---------------- SONRA: akis calisiyor ----------------
  sonuc(oturumSayisi(K.DEPO810) === '1', 'S6 SONRA: yetkili kullanici kendi otelinin sayimini LISTELIYOR');

  const yeni = yeniId();
  const o2 = oturumEkle(K.DEPO810, yeni);
  const d2 = o2.ok ? detayEkle(K.DEPO810, yeni) : { ok: false };
  sonuc(o2.ok && d2.ok
     && tek(`select count(*) from public.sayim_detaylari where oturum_id='${yeni}';`) === '1',
    'S7 SONRA: sayim OLUSTURMA (oturum + detay) calisiyor', o2.ok ? '' : (o2.err || '').split('\n').pop());

  const r2 = reddet(K.DEPO810, yeni);
  sonuc(r2.ok && tek(`select durum from public.sayim_oturumlari where id='${yeni}';`) === 'reddedildi',
    'S8 SONRA: REDDETME calisiyor');

  // ---------------- Negatif kontroller ----------------
  const onayla = q(K.DEPO810, `update public.sayim_oturumlari set durum='onaylandi' where id='${OTURUM}';`);
  sonuc(tek(`select durum from public.sayim_oturumlari where id='${OTURUM}';`) === 'onay_bekliyor',
    'N1 dogrudan "onaylandi" YAZILAMAZ (onay yalniz RPC ile)', onayla.ok ? 'yazma engellendi' : (onayla.err || '').split('\n').pop());

  const gor = oturumEkle(GORUNTU810, yeniId());
  sonuc(!gor.ok && /row-level security/i.test(gor.err),
    'N2 stok_takip yetkisi OLMAYAN kullanici sayim olusturamaz');
  sonuc(oturumSayisi(GORUNTU810) === '0', 'N3 stok_takip yetkisi olmayan kullanici sayim GORMUYOR');

  sonuc(oturumSayisi(K.BAR811) === '0', 'N4 BASKA OTEL kullanicisi 810 sayimlarini gormuyor');
  const bas = oturumEkle(K.BAR811, yeniId(), '810');
  sonuc(!bas.ok && /row-level security/i.test(bas.err),
    'N5 BASKA OTEL adina sayim olusturulamaz');

  const pasif = oturumEkle(K.PASIF, yeniId());
  sonuc(!pasif.ok && /row-level security/i.test(pasif.err), 'N6 PASIF kullanici sayim olusturamaz');

  const detaySel = q(K.DEPO810, `select count(*) from public.sayim_detaylari;`);
  sonuc(!detaySel.ok && /permission denied/i.test(detaySel.err),
    'N7 sayim_detaylari DOGRUDAN okunamiyor (A1 katmani korundu)');
  const rpc = q(K.DEPO810, `select count(*) from public.stok_sayim_detaylari('${OTURUM}');`);
  sonuc(rpc.ok && rpc.out === '1', 'N8 detaylar yalniz stok_sayim_detaylari RPC ile okunuyor');

  const trunc = q(K.DEPO810, `truncate table public.sayim_detaylari;`);
  sonuc(!trunc.ok && /permission denied|must be owner/i.test(trunc.err),
    'N9 TRUNCATE artik REDDEDILIYOR (duzeltme oncesi mumkundu)', (trunc.err || '').split('\n').pop());
  const del = q(K.DEPO810, `delete from public.sayim_oturumlari where id='${OTURUM}';`);
  sonuc(!del.ok && /permission denied/i.test(del.err), 'N10 DELETE reddediliyor');

  // Kismen uygulanmis oturum reddedilemez (ekranin fail-closed kontrolunun sunucu esi)
  // A1'in oturum koruma tetikleyicisi bu alani sunucu disindan yazmaya kapatiyor:
  // tohumlama replica rolunde yapilir (tetikleyiciler devre disi).
  tek(`set session_replication_role = replica;
       update public.sayim_oturumlari set kismi_uygulandi = true where id='${OTURUM}';
       set session_replication_role = origin;`);
  const r3 = reddet(K.DEPO810, OTURUM);
  sonuc(r3.ok && tek(`select durum from public.sayim_oturumlari where id='${OTURUM}';`) === 'onay_bekliyor',
    'N11 KISMEN uygulanmis oturum reddedilemez (stok zaten degismis olabilir)');

  // ---------------- Geri alma ----------------
  const g = O.uygulaTekIslem(GERI_AL);
  sonuc(g.ok && oturumSayisi(K.DEPO810) === '0',
    'S9 Geri alma: politikalar dusuyor, akis yine kapaniyor', g.ok ? '' : (g.err || '').split('\n').pop());
} catch (e) {
  sonuc(false, 'beklenmeyen hata', String(e && e.message || e));
} finally {
  O.temizle();
}
console.log(`\nSAYIM RLS DAR DUZELTME: ${ok} OK / ${fail} FAIL`);
process.exit(fail ? 1 : 0);
