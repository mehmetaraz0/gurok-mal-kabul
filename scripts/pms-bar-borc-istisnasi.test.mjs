// ===========================================================================
// BAR BORC ISTISNASI x MALI YETKI AYRIMI — KALICI REGRESYON
// ===========================================================================
// Referans: 2026-10-06-4ca95db-bar-mali-uyum-sondasi.mjs (Codex incelemesi).
// O sonda gecici idi; bu dosya ayni senaryoyu KALICI teste baglar.
//
// Neden AYRI dosya: pms-folio-mali-yetki.test.mjs kendi check-in akislarini
// yurutuyor ve oda 101 icin ACIK folyo birakiyor; istisna sarti orada
// olusmuyordu (olculdu, SINANMADI olarak raporlanmisti). Burada fikstur
// temiz: hicbir URUN KURALI veya YETKI gevsetilmez.
//
// MIGRATION SIRASI (referans sondayla ayni):
//   izole taban -> 2026-09-18-bar-a1-guvenlik.sql
//               -> 2026-10-06-pms-folio-mali-yetki-ayrimi.sql
//               -> A1 tohumu
//
// Olculenler:
//   B1 iki hassas kapi tetikleyicisi A1 ustunde de ETKIN
//   B2 normal teslim: acik folyoya TAM BIR pozitif 250,00 borc
//   B3 mukerrer teslim: borc MUKERRER YAZILMAZ
//   B4 KAPALI folyoda teslim: borc istisnasi dogar, kapali folyoya YAZILMAZ
//   B5 cozen kimlik pms_folio=kayit, tam=false (yetki GENISLETILMEDI)
//   B6 GERCEK bar_borc_istisnasi_coz: AYNI konaklamanin ACIK folyosuna
//      TAM BIR pozitif 250,00 hareket; siparis ve istisna durumlari tamam
//   B7 ikinci cagri MUKERRER borc olusturmaz
//   B8 mali yetki korumasi SURUYOR: RLS atlayan baglamda taklit negatif bar
//      hareketi MALI_TAM_YETKI_GEREKLI ile reddedilir
//
// Izole Docker + sentetik veri. Uretim/push/deploy ve canli islem YOK.
// Kullanim: node scripts/pms-bar-borc-istisnasi.test.mjs
// ===========================================================================
import { barOrtami } from './bar-test-ortam.mjs';
import { K, EK_TOHUM, FOLYO101, a1Yardimcilari } from './bar-a1-tohum.mjs';

const O = barOrtami({ ad: 'pms-borc', ag: 'pms-borc-net' });
const { q, siparis, VISKI1, tek, hazirla, folyoKapat, sifirla } = a1Yardimcilari(O);

let ok = 0, fail = 0;
const sonuc = (g, ad, ek) => {
  console.log((g ? 'OK   ' : 'FAIL ') + ad + (ek ? ' — ' + ek : ''));
  if (g) ok++; else fail++;
};
const es = (ad, bek, olc) => sonuc(String(bek) === String(olc), ad,
  String(bek) === String(olc) ? String(olc) : `beklenen=${bek} olculen=${olc}`);
const zorunlu = (r, ad) => { if (!r.ok) throw new Error(ad + ': ' + String(r.err).slice(-300)); return r.out; };

// Ayni konaklamanin IKINCI acik folyosu. Rezervasyon EK_TOHUM'dan gelir
// (oda 101 konaklamasi); folyo ACIK olarak eklenir ki cozum hedefi olsun.
const REZ101 = '88888888-0000-0000-0000-000000000101';
const FOLYO101B = '55555555-0000-0000-0000-0000000001aa';

try {
  console.log('izole veritabani kuruluyor (Docker)...');
  await O.kur();
  // SIRA onemli: A1 guvenlik -> mali kural -> tohum.
  zorunlu(O.uygulaTekIslem('docs/kurulum/2026-09-18-bar-a1-guvenlik.sql'), 'A1 guvenlik');
  zorunlu(O.uygula('docs/kurulum/2026-10-06-pms-folio-mali-yetki-ayrimi.sql'), 'mali kural');
  zorunlu(O.sql(EK_TOHUM), 'A1 tohum');
  es('B1 iki hassas kapi tetikleyicisi A1 ustunde ETKIN', 2,
    tek("select count(*) from pg_trigger where tgname='pms_folio_hassas_kapi' and tgenabled='O';"));

  // ======================================================================
  // B2/B3 — NORMAL teslim: acik folyoya tam bir pozitif borc
  // ======================================================================
  console.log('\n--- B2/B3: normal teslim ---');
  sifirla();
  const sip1 = zorunlu(siparis(K.BAR810, VISKI1, '101'), 'siparis 1').trim();
  zorunlu(q(K.BAR810, `select public.bar_siparis_oda_dogrula('${sip1}',true);`), 'oda dogrula 1');
  zorunlu(hazirla(sip1), 'hazirla 1');
  zorunlu(q(K.BAR810, `select public.bar_siparis_teslim_et('${sip1}');`), 'teslim 1');
  es('B2 GERCEK teslim acik folyoya TAM BIR +250,00 borc yazdi', '1|250.00',
    tek(`select count(*)||'|'||sum(tutar)::text from public.pms_folio_hareketleri
         where kaynak_id='${sip1}' and kaynak_tip='bar';`));
  es('B2b borc hedefi oda 101 konaklamasinin ACIK folyosu', FOLYO101,
    tek(`select folio_id::text from public.pms_folio_hareketleri where kaynak_id='${sip1}';`));
  zorunlu(q(K.BAR810, `select public.bar_siparis_teslim_et('${sip1}');`), 'teslim 1 tekrar');
  es('B3 MUKERRER teslim borcu COGALTMADI', 1,
    tek(`select count(*) from public.pms_folio_hareketleri where kaynak_id='${sip1}';`));

  // ======================================================================
  // B4 — KAPALI folyo: borc istisnasi dogar, kapali folyoya yazilmaz
  // ======================================================================
  console.log('\n--- B4: kapali folyo -> borc istisnasi ---');
  sifirla();
  const sip2 = zorunlu(siparis(K.BAR810, VISKI1, '101'), 'siparis 2').trim();
  zorunlu(q(K.BAR810, `select public.bar_siparis_oda_dogrula('${sip2}',true);`), 'oda dogrula 2');
  zorunlu(hazirla(sip2), 'hazirla 2');
  zorunlu(folyoKapat(), 'folyo kapat');
  zorunlu(q(K.SEF810, `select public.bar_siparis_teslim_et('${sip2}',true);`), 'istisnali teslim');
  es('B4 KAPALI folyoda teslim +250,00 BORC ISTISNASI uretti', 'acik|250.00',
    tek(`select durum||'|'||tutar::text from public.bar_borc_istisnalari
         where siparis_id='${sip2}';`));
  es('B4b kapali folyoya hareket YAZILMADI', 0,
    tek(`select count(*) from public.pms_folio_hareketleri where kaynak_id='${sip2}';`));

  // ======================================================================
  // B5/B6/B7 — AYNI konaklamanin ACIK folyosuna cozum
  // ======================================================================
  console.log('\n--- B5/B6/B7: istisna cozumu ---');
  const istisna = tek(`select id::text from public.bar_borc_istisnalari where siparis_id='${sip2}';`);
  sonuc(!!istisna, 'B5-hazirlik istisna kaydi bulundu', String(istisna).slice(0, 12));
  // Ayni konaklamanin (REZ101) ikinci ACIK folyosu: cozum hedefi.
  zorunlu(O.sql(`set session_replication_role=replica;
    insert into public.pms_folyolar (id, otel_id, rezervasyon_id, folio_no, durum)
    values ('${FOLYO101B}','810','${REZ101}','TEST-F-101B','acik')
    on conflict (id) do update set durum='acik';
    set session_replication_role=origin;`), 'ikinci folyo');
  es('B5b hedef folyo AYNI konaklamaya ait ve ACIK', REZ101 + '|acik',
    tek(`select rezervasyon_id::text||'|'||durum from public.pms_folyolar
         where id='${FOLYO101B}';`));
  // Cozen kimligin yetkisi: kayit VAR, tam YOK (yetki GENISLETILMEDI).
  es('B5 cozen kimlik pms_folio=kayit, tam=false', 't|f',
    zorunlu(q(K.ONBURO810,
      "select public.auth_yetki_var('pms_folio','kayit'), public.auth_yetki_var('pms_folio','tam');"),
      'yetki olcumu').trim());

  zorunlu(q(K.ONBURO810, `select public.bar_borc_istisnasi_coz(
    '${istisna}','folyoya_yaz','${FOLYO101B}',true,'Kalici regresyon');`), 'istisna cozumu');
  es('B6 GERCEK cozum RPC ayni konaklamanin ACIK folyosuna TAM BIR +250,00 yazdi', '1|250.00',
    tek(`select count(*)||'|'||sum(tutar)::text from public.pms_folio_hareketleri
         where kaynak_id='${sip2}' and folio_id='${FOLYO101B}';`));
  es('B6b siparis ve istisna durumlari tamamlandi', 'teslim_edildi|folyoya_yazildi',
    tek(`select s.durum||'|'||i.durum from public.bar_siparisleri s
         join public.bar_borc_istisnalari i on i.siparis_id=s.id where s.id='${sip2}';`));
  es('B6c cozum NEGATIF satir uretmedi', 0,
    tek(`select count(*) from public.pms_folio_hareketleri
         where kaynak_id='${sip2}' and tutar<0;`));

  zorunlu(q(K.ONBURO810, `select public.bar_borc_istisnasi_coz(
    '${istisna}','folyoya_yaz','${FOLYO101B}',true,'Ikinci cagri');`), 'ikinci cozum');
  es('B7 IKINCI cagri MUKERRER borc olusturmadi', 1,
    tek(`select count(*) from public.pms_folio_hareketleri where kaynak_id='${sip2}';`));
  es('B7b toplam tutar degismedi', '250.00',
    tek(`select sum(tutar)::text from public.pms_folio_hareketleri where kaynak_id='${sip2}';`));

  // ======================================================================
  // B8 — MALI YETKI KORUMASI suruyor
  // ======================================================================
  console.log('\n--- B8: mali yetki korumasi ---');
  const taklit = q({ ...K.ONBURO810, rol: 'service_role' },
    `insert into public.pms_folio_hareketleri (otel_id, folio_id, tip, aciklama, tutar, kaynak_tip)
     values ('810','${FOLYO101B}','bar','Taklit negatif',-17,'bar');`);
  sonuc(!taklit.ok && /MALI_TAM_YETKI_GEREKLI/.test(taklit.err),
    'B8 RLS ATLAYAN baglamda taklit negatif bar hareketi REDDEDILDI',
    taklit.ok ? 'KABUL EDILDI (kusur)' : 'MALI_TAM_YETKI_GEREKLI');
  const taklit2 = q(K.ONBURO810,
    `insert into public.pms_folio_hareketleri (otel_id, folio_id, tip, aciklama, tutar, kaynak_tip)
     values ('810','${FOLYO101B}','bar','Taklit negatif 2',-17,'bar');`);
  sonuc(!taklit2.ok, 'B8b normal baglamda da REDDEDILDI',
    taklit2.ok ? 'KABUL EDILDI (kusur)' : 'ret');
  es('B8c folyoda NEGATIF satir yok', 0,
    tek(`select count(*) from public.pms_folio_hareketleri
         where folio_id='${FOLYO101B}' and tutar<0;`));

  console.log('\n======================================================================');
  console.log(`SONUC: ${ok} gecti, ${fail} kaldi`);
  console.log('Yerel kanit; CANLI KABUL ve canli yetki degisikligi YERINE GECMEZ.');
  console.log('======================================================================');
} catch (e) {
  console.error('\nDUR: ' + (e && e.message));
  fail++;
} finally {
  try { O.temizle(); } catch {}
}
process.exit(fail === 0 ? 0 : 1);
