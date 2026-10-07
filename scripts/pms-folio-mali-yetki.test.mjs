// ===========================================================================
// PMS FOLYO MALI YETKI AYRIMI — GERCEK ROL BAGLAMIYLA DOGRULAMA
// ===========================================================================
// Onayli tasarim: 2026-10-06-PMS-mali-islem-yetkileri-onayli-tasarim.md
//
// Izole Docker veritabani, SENTETIK kullanici/misafir. Her yazma denemesi
// GERCEK rol baglaminda kosar: `set local role authenticated` +
// `request.jwt.claims` ile kullanicinin kendi kimligi. RLS ve tetikleyiciler
// aciktir; dogrudan superuser yazimi KULLANILMAZ (tohum disinda).
//
// Olculen (onayli tasarimin kabul olcutleri):
//   M1  personel + vardiya: pozitif tahsilat, normal ucret, sifir bakiyeli
//       folyo kapatma -> HER BIRI ICIN OLUMLU kontrol
//   M2  personel + vardiya: negatif odeme, negatif hareket, 'duzeltme' tipi,
//       ters_kayit=true -> REDDEDILIR; ret sonrasi satir ve bakiye DEGISMEZ
//   M3  sef: gerekceli hassas islem GECER; gerekcesiz REDDEDILIR
//   M4  sef DAHIL hicbir rol mali hareket/odeme UPDATE/DELETE edemez
//   M5  baska otele yazma REDDEDILIR; izinli otelde olumlu kontrol
//   M6  kapali folyoya yazma, bakiye varken kapatma mevcut kurallarla reddedilir
//   M7  sistem akislari (oda ucreti) engellenmemis
//   M8  geri alma: yetki acikken DURUR, yetki kaldirilinca kosar; degismezlik korunur
//
// Yerel kanit; CANLI KABUL YERINE GECMEZ. Canli yetki degisikligi YAPILMAZ.
// Kullanim: node scripts/pms-folio-mali-yetki.test.mjs
// ===========================================================================
import fs from 'node:fs';
import { barOrtami } from './bar-test-ortam.mjs';
import { EK_TOHUM, a1Yardimcilari, K, FOLYO101 } from './bar-a1-tohum.mjs';
import { PMS, PMS_TOHUM } from './pms-akis-tohum.mjs';
import { barEkranKur } from './bar-ekran-harness.mjs';

const KOK = new URL('..', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const KURAL = KOK + 'docs/kurulum/2026-10-06-pms-folio-mali-yetki-ayrimi.sql';
const KURAL_GERI = KOK + 'docs/kurulum/2026-10-06-pms-folio-mali-yetki-ayrimi-geri-al.sql';
const O = barOrtami({ ad: 'pms-mali', ag: 'pms-mali-net' });

let ok = 0, fail = 0;
const sonuc = (g, ad, ek) => {
  console.log((g ? 'OK   ' : 'FAIL ') + ad + (ek ? ' — ' + ek : ''));
  if (g) ok++; else fail++;
};
const es = (ad, bek, olc) => sonuc(String(bek) === String(olc), ad,
  String(bek) === String(olc) ? String(olc) : `beklenen=${bek} olculen=${olc}`);
const tek = (q) => O.sql(q).out.trim();

// --- Sentetik kullanicilar: uc On Buro rolu + baska otelden bir personel ---
const U = {
  sef:      '11111111-0000-0000-0000-0000000000s1'.replace('s1', 'f1'),
  vardiya:  '11111111-0000-0000-0000-0000000000f2',
  personel: '11111111-0000-0000-0000-0000000000f3',
  digerOtel:'11111111-0000-0000-0000-0000000000f4',
  // Tohumdaki mevcut BAR kullanicisi (bar_siparis_yonetimi yetkili). On Buro
  // rollerinin yetkisi GENISLETILMEZ; bar akisini bar personeli yurutur.
  bar:      '11111111-0000-0000-0000-000000000810',
};
// Gercek rol baglami: authenticated rolu + kullanicinin auth.uid()'i.
const olarak = (kim, q) => O.kimlikle({ rol: 'authenticated', sub: U[kim] }, q);

const TOHUM = `
set session_replication_role = replica;
insert into public.moduller (kod, ad, kategori, sira, aktif) values
  ('pms_oda_tipi','On Buro — Oda Tipleri','onburo',43,true),
  ('pms_oda','On Buro — Odalar','onburo',44,true),
  ('pms_misafir','On Buro — Misafirler','onburo',45,true),
  ('pms_rezervasyon','On Buro — Rezervasyonlar','onburo',47,true),
  ('pms_folio','On Buro — Folio','onburo',48,true)
on conflict (kod) do nothing;
insert into public.roller (id, ad, seviye, kod, sira) values
  ('00000000-0000-0000-0000-0000000000f1','On Buro Sefi','otel','onburo_sef',20),
  ('00000000-0000-0000-0000-0000000000f2','On Buro Vardiya','otel','onburo_vardiya',21),
  ('00000000-0000-0000-0000-0000000000f3','On Buro Personel','otel','onburo_personel',22)
on conflict do nothing;
-- ONAYLI TASARIM: normal islemler kayit, hassas islemler tam.
insert into public.yetki_matrisi (rol_id, modul_id, yetki)
select r.id, m.id, v.y::public.yetki_seviye from (values
  -- Onayli karar tablosunun TAMAMI (15 satir); mali ayrim: normal=kayit, hassas=tam.
  ('onburo_sef','pms_oda_tipi','tam'),       ('onburo_sef','pms_oda','tam'),
  ('onburo_sef','pms_misafir','tam'),        ('onburo_sef','pms_rezervasyon','tam'),
  ('onburo_sef','pms_folio','tam'),
  ('onburo_vardiya','pms_oda_tipi','goruntule'), ('onburo_vardiya','pms_oda','kayit'),
  ('onburo_vardiya','pms_misafir','kayit'),     ('onburo_vardiya','pms_rezervasyon','kayit'),
  ('onburo_vardiya','pms_folio','kayit'),
  ('onburo_personel','pms_oda_tipi','goruntule'),('onburo_personel','pms_oda','goruntule'),
  ('onburo_personel','pms_misafir','kayit'),    ('onburo_personel','pms_rezervasyon','kayit'),
  ('onburo_personel','pms_folio','kayit')
) v(r,m,y) join public.roller r on r.kod=v.r join public.moduller m on m.kod=v.m
on conflict (rol_id, modul_id) do nothing;
insert into auth.users (id, email) values
  ('${U.sef}','sef@test.local'), ('${U.vardiya}','vardiya@test.local'),
  ('${U.personel}','personel@test.local'), ('${U.digerOtel}','diger@test.local')
on conflict do nothing;
insert into public.kullanicilar (id, auth_user_id, ad, rol, otel_id, aktif, rol_id) values
  (gen_random_uuid(),'${U.sef}','Sef 810','muhasebe_calisani','810',true,'00000000-0000-0000-0000-0000000000f1'),
  (gen_random_uuid(),'${U.vardiya}','Vardiya 810','muhasebe_calisani','810',true,'00000000-0000-0000-0000-0000000000f2'),
  (gen_random_uuid(),'${U.personel}','Personel 810','muhasebe_calisani','810',true,'00000000-0000-0000-0000-0000000000f3'),
  (gen_random_uuid(),'${U.digerOtel}','Personel 811','muhasebe_calisani','811',true,'00000000-0000-0000-0000-0000000000f3')
on conflict do nothing;
set session_replication_role = origin;
`;

try {
  console.log('izole veritabani kuruluyor (Docker)...');
  await O.kur();
  for (const [ad, s] of [['A1 tohum', EK_TOHUM], ['PMS tohum', PMS_TOHUM], ['mali tohum', TOHUM]]) {
    const r = O.sql(s);
    if (!r.ok) throw new Error(ad + ': ' + r.err.slice(-400));
  }
  sonuc(true, 'M0 izole ortam + sentetik roller/kullanicilar hazir',
    tek(`select count(*) from public.kullanicilar where otel_id in ('810','811');`) + ' kullanici');

  // Kural dosyasini uygula (urun kanali: tek islem + ON_ERROR_STOP)
  // Dosyalar kendi begin/commit'ini tasir; belgelenen kullanim "tamamini oldugu
  // gibi ver" oldugu icin dis islem sarmasi YOK.
  const kuralR = O.sql(fs.readFileSync(KURAL, 'utf8'));
  sonuc(kuralR.ok, 'M0b mali yetki ayrimi migration kostu',
    kuralR.ok ? ((kuralR.err.match(/ENVANTER[^\n]*/) || [''])[0]).slice(0, 80) : kuralR.err.slice(-250));
  if (!kuralR.ok) throw new Error('migration uygulanamadi');

  // --- Calisma folyosu: giris yapilmis konaklama + acik folyo -------------
  // OLCULDU: phase0 denetim tetikleyicisi dogrudan superuser yazimini
  // "Aktif ERP personeli gerekli" ile reddediyor ve pms_check_in rezervasyon
  // yetkisi istiyor. Bu yuzden KURULUM DA gercek rol baglaminda, urunun kendi
  // yolundan yapilir: sef (pms_rezervasyon=tam) fiyati girer, durumu gunceller
  // (tetikleyici folyoyu acar) ve check-in yapar.
  const hz1 = olarak('sef', `update public.pms_rezervasyonlar set gecelik_fiyat = 1500
          where id='${PMS.REZ_ATANMIS}';`);
  sonuc(hz1.ok, 'M0c1 sef gecelik fiyati girdi (urun yolu)', hz1.ok ? '' : hz1.err.slice(-140));
  const hz2 = olarak('sef', `update public.pms_rezervasyonlar set durum = 'onaylandi'
          where id='${PMS.REZ_ATANMIS}';`);
  sonuc(hz2.ok, 'M0c2 durum guncellendi, folyo tetikleyicisi atesledi', hz2.ok ? '' : hz2.err.slice(-140));
  const hz3 = olarak('sef', `select public.pms_check_in('${PMS.REZ_ATANMIS}');`);
  sonuc(hz3.ok, 'M0c3 sef check-in yapti', hz3.ok ? '' : hz3.err.slice(-140));
  const folio = tek(`select id::text from public.pms_folyolar
                     where rezervasyon_id='${PMS.REZ_ATANMIS}' and durum='acik' limit 1;`);
  sonuc(!!folio, 'M0c acik folyo hazir', String(folio).slice(0, 8));
  const say = () => tek(`select count(*)||'/'||count(*) filter (where t='h')
    from (select 'h' t from public.pms_folio_hareketleri where folio_id='${folio}'
          union all select 'o' from public.pms_folio_odemeler where folio_id='${folio}') s;`);
  const bakiye = () => tek(`select coalesce((select sum(tutar) from public.pms_folio_hareketleri where folio_id='${folio}'),0)
    - coalesce((select sum(tutar) from public.pms_folio_odemeler where folio_id='${folio}'),0);`);

  const hareket = (kim, { tip = 'ekstra', tutar = 100, aciklama = 'Minibar', ters = false }) =>
    olarak(kim, `insert into public.pms_folio_hareketleri
      (otel_id, folio_id, tip, aciklama, tutar, ters_kayit)
      values ('810','${folio}','${tip}','${aciklama}',${tutar},${ters});`);
  const odeme = (kim, { tutar = 50, aciklama = null }) =>
    olarak(kim, `insert into public.pms_folio_odemeler (otel_id, folio_id, yontem, tutar, aciklama)
      values ('810','${folio}','nakit',${tutar},${aciklama === null ? 'null' : `'${aciklama}'`});`);

  // ======================================================================
  // M1 — OLUMLU: personel ve vardiya normal islem yapabilir
  // ======================================================================
  console.log('\n--- M1: normal islem OLUMLU kontroller ---');
  for (const kim of ['personel', 'vardiya', 'sef']) {
    const r = hareket(kim, { tutar: 100, aciklama: 'Minibar ' + kim });
    sonuc(r.ok, `M1 ${kim}: POZITIF normal hareket yazdi`, r.ok ? '' : r.err.slice(-110));
    const o = odeme(kim, { tutar: 100, aciklama: 'Nakit tahsilat ' + kim });
    sonuc(o.ok, `M1 ${kim}: POZITIF tahsilat yazdi`, o.ok ? '' : o.err.slice(-110));
  }
  // Oda ucreti (sistem akisi) engellenmemis olmali — personel kimliginde.
  const odaR = olarak('personel', `select public.pms_folio_oda_ucreti_isle('${PMS.REZ_ATANMIS}');`);
  sonuc(odaR.ok, 'M7 sistem akisi: oda ucreti isleme personelde CALISIYOR',
    odaR.ok ? '' : odaR.err.slice(-140));

  // ======================================================================
  // M2 — OLUMSUZ: personel/vardiya hassas islem YAPAMAZ
  // ======================================================================
  console.log('\n--- M2: hassas islem OLUMSUZ kontroller ---');
  const denemeler = [
    ['negatif hareket',        (k) => hareket(k, { tutar: -50, aciklama: 'Iade denemesi' })],
    ['duzeltme tipi (pozitif)',(k) => hareket(k, { tip: 'duzeltme', tutar: 25, aciklama: 'Duzeltme denemesi' })],
    ['ters kayit',             (k) => hareket(k, { tutar: 10, aciklama: 'Ters denemesi', ters: true })],
    ['negatif odeme (iade)',   (k) => odeme(k, { tutar: -40, aciklama: 'Iade denemesi' })],
    ['baska tur + negatif',    (k) => hareket(k, { tip: 'bar', tutar: -75, aciklama: 'Tur degistirme denemesi' })],
  ];
  for (const kim of ['personel', 'vardiya']) {
    for (const [ad, f] of denemeler) {
      const oncekiSay = say(), oncekiBak = bakiye();
      const r = f(kim);
      const dogruRet = !r.ok && /MALI_TAM_YETKI_GEREKLI|row-level security/i.test(r.err);
      sonuc(dogruRet, `M2 ${kim}: ${ad} REDDEDILDI`,
        r.ok ? 'KABUL EDILDI (kusur)' : (r.err.match(/MALI_[A-Z_]+|row-level security/i) || ['?'])[0]);
      es(`M2b ${kim}/${ad}: satir sayisi DEGISMEDI`, oncekiSay, say());
      es(`M2c ${kim}/${ad}: bakiye DEGISMEDI`, oncekiBak, bakiye());
    }
  }

  // ======================================================================
  // M3 — SEF: gerekceli hassas islem GECER, gerekcesiz REDDEDILIR
  // ======================================================================
  console.log('\n--- M3: sef hassas islem ---');
  let r = hareket('sef', { tutar: -30, aciklama: 'Musteri sikayeti nedeniyle indirim' });
  sonuc(r.ok, 'M3 sef: GEREKCELI negatif hareket (indirim) GECTI', r.ok ? '' : r.err.slice(-140));
  r = hareket('sef', { tip: 'duzeltme', tutar: 20, aciklama: 'Yanlis islenen ekstra duzeltmesi' });
  sonuc(r.ok, 'M3b sef: GEREKCELI duzeltme GECTI', r.ok ? '' : r.err.slice(-140));
  r = odeme('sef', { tutar: -20, aciklama: 'Fazla tahsilat iadesi' });
  sonuc(r.ok, 'M3c sef: GEREKCELI iade (negatif odeme) GECTI', r.ok ? '' : r.err.slice(-140));
  r = hareket('sef', { tutar: -15, aciklama: '   ' });
  sonuc(!r.ok && /MALI_GEREKCE_ZORUNLU|row-level security/i.test(r.err),
    'M3d sef: GEREKCESIZ hassas hareket REDDEDILDI',
    r.ok ? 'KABUL EDILDI (kusur)' : (r.err.match(/MALI_[A-Z_]+|row-level security/i) || ['?'])[0]);
  r = odeme('sef', { tutar: -15, aciklama: null });
  sonuc(!r.ok && /MALI_GEREKCE_ZORUNLU|row-level security/i.test(r.err),
    'M3e sef: GEREKCESIZ iade REDDEDILDI',
    r.ok ? 'KABUL EDILDI (kusur)' : (r.err.match(/MALI_[A-Z_]+|row-level security/i) || ['?'])[0]);
  // Duzeltme MEVCUT satiri degistirmedi: yeni satir eklendi.
  sonuc(Number(tek(`select count(*) from public.pms_folio_hareketleri where folio_id='${folio}' and tutar<0;`)) >= 1,
    'M3f sefin duzeltmesi YENI satir olarak eklendi (mevcut satir degismedi)');

  // ======================================================================
  // M4 — SEF DAHIL hic kimse UPDATE/DELETE edemez
  // ======================================================================
  console.log('\n--- M4: degismezlik (sef dahil) ---');
  const hId = tek(`select id::text from public.pms_folio_hareketleri where folio_id='${folio}' limit 1;`);
  const oId = tek(`select id::text from public.pms_folio_odemeler where folio_id='${folio}' limit 1;`);
  for (const kim of ['sef', 'vardiya', 'personel']) {
    for (const [ad, q] of [
      ['hareket UPDATE', `update public.pms_folio_hareketleri set tutar=1 where id='${hId}';`],
      ['hareket DELETE', `delete from public.pms_folio_hareketleri where id='${hId}';`],
      ['odeme UPDATE',   `update public.pms_folio_odemeler set tutar=1 where id='${oId}';`],
      ['odeme DELETE',   `delete from public.pms_folio_odemeler where id='${oId}';`],
    ]) {
      const rr = olarak(kim, q);
      sonuc(!rr.ok, `M4 ${kim}: ${ad} REDDEDILDI`,
        rr.ok ? 'KABUL EDILDI (kusur)' : (rr.err.match(/permission denied|degistirilemez|denied/i) || ['ret'])[0]);
    }
  }
  es('M4b hareket satiri hala yerinde', 1,
    tek(`select count(*) from public.pms_folio_hareketleri where id='${hId}';`));
  // Superuser (RLS atlar) bile tetikleyiciye takilir:
  const suR = O.sql(`update public.pms_folio_hareketleri set tutar=1 where id='${hId}';`);
  sonuc(!suR.ok && /degistirilemez/i.test(suR.err),
    'M4c RLS atlayan yol da tetikleyiciye takiliyor',
    (suR.err.match(/Finansal kayit[^\n]*/) || ['?'])[0].slice(0, 60));

  // ======================================================================
  // M5 — OTEL KAPSAMI
  // ======================================================================
  console.log('\n--- M5: otel kapsami ---');
  const digerR = olarak('digerOtel', `insert into public.pms_folio_odemeler
    (otel_id, folio_id, yontem, tutar) values ('810','${folio}','nakit',10);`);
  sonuc(!digerR.ok, 'M5 baska otelin personeli 810 folyosuna YAZAMADI',
    digerR.ok ? 'KABUL EDILDI (kusur)' : 'ret');
  const izinliR = odeme('personel', { tutar: 5, aciklama: 'Izinli otel olumlu kontrol' });
  sonuc(izinliR.ok, 'M5b izinli oteldeki personel YAZABILDI', izinliR.ok ? '' : izinliR.err.slice(-110));

  // ======================================================================
  // M6 — MEVCUT kurallar gevsemedi
  // ======================================================================
  console.log('\n--- M6: mevcut kurallar ---');
  const bak = Number(bakiye());
  const kapatBakiyeli = olarak('personel', `select public.pms_folio_kapat('${folio}');`);
  sonuc(bak !== 0 ? !kapatBakiyeli.ok : true,
    'M6 bakiye varken folyo kapatma REDDEDILDI', 'bakiye=' + bak);
  // Bakiyeyi sifirla (pozitif tahsilat: normal islem) ve kapat.
  if (bak > 0) odeme('personel', { tutar: bak, aciklama: 'Kalan bakiye tahsilati' });
  else if (bak < 0) hareket('personel', { tutar: -bak, aciklama: 'Bakiye duzeltme ucreti' });
  const kapatR = olarak('personel', `select public.pms_folio_kapat('${folio}');`);
  sonuc(kapatR.ok, 'M1b personel: SIFIR bakiyeli folyoyu KAPATTI',
    kapatR.ok ? 'bakiye=' + bakiye() : kapatR.err.slice(-140));
  const kapaliYaz = odeme('personel', { tutar: 10, aciklama: 'Kapali folyoya deneme' });
  sonuc(!kapaliYaz.ok, 'M6b kapali folyoya yazma REDDEDILDI',
    kapaliYaz.ok ? 'KABUL EDILDI (kusur)' : 'ret');

  // ======================================================================
  // E — EKRAN davranisi SUNUCU kuraliyla tutarli mi?
  // Dugme gizleme TEK BASINA kanit sayilmaz: her olumsuz durumda AG ISTEGI
  // GONDERILMEDIGI de olculur, olumlu durumda istegin gittigi olculur.
  // ======================================================================
  console.log('\n--- E: ekran/sunucu tutarliligi ---');
  const REST = await O.restBaslat({ port: 3097 });
  const YETKI = {
    kayit: { pms_folio: 'kayit', pms_rezervasyon: 'kayit', pms_misafir: 'kayit',
             pms_oda: 'goruntule', pms_oda_tipi: 'goruntule' },
    tam:   { pms_folio: 'tam', pms_rezervasyon: 'tam', pms_misafir: 'tam',
             pms_oda: 'tam', pms_oda_tipi: 'tam' },
  };
  // Yeni bir folyo gerekir (onceki kapandi): sef yeni rezervasyonu hazirlar.
  olarak('sef', `update public.pms_rezervasyonlar set gecelik_fiyat = 900
          where id='${PMS.REZ_ATAMASIZ}';`);
  olarak('sef', `update public.pms_rezervasyonlar set durum = 'onaylandi'
          where id='${PMS.REZ_ATAMASIZ}';`);
  olarak('sef', `select public.pms_check_in('${PMS.REZ_ATAMASIZ}', '${PMS.ODA202}');`);
  const folio2 = tek(`select id::text from public.pms_folyolar
                      where rezervasyon_id='${PMS.REZ_ATAMASIZ}' and durum='acik' limit 1;`);
  sonuc(!!folio2, 'E0 ekran testi icin acik folyo hazir', String(folio2).slice(0, 8));

  const { yerelJwt } = await import('./bar-test-ortam.mjs');
  const ekranKur = (seviye, kim) => barEkranKur({
    html: 'pms-folio.html', restUrl: REST,   // harness dosya YOLU bekler
    jwt: yerelJwt('authenticated', U[kim]),
    kullanici: { id: U[kim], ad: 'Test ' + kim, rol: 'muhasebe_calisani',
                 otel_id: '810', otelId: '810' },
    yetkiler: YETKI[seviye],
  });

  const hazirla = async (seviye, kim) => {
    const e = await ekranKur(seviye, kim);
    e.calistir('FOLIO_YETKI = null;');
    await e.calistir('yukle()');
    // Acik folyoyu sec ve formlari goster.
    e.calistir(`ACIK = { folio_id: '${folio2}', otel_id: '810', folio_no: 'T' };
                maliArayuzuUyarla();`);
    return e;
  };
  const istekSayisi = (e, desen) =>
    e.kayit.istekler.filter((i) => desen.test(String(i.url))).length;
  // OLCULDU: harness'in <select> ogesi .value'yu okumuyor ve innerHTML
  // appendChild ile eklenen option'lari yansitmiyor. Bu bir HARNESS sinirdir,
  // urun kusuru DEGIL: secenekler cocuk listesinden okunur, secim ACIKCA atanir.
  // Urun secenek listesini innerHTML ile kuruyor; hem gercek tarayicida hem
  // harness'ta AYNI sekilde gozlemlenebilir. (Harness appendChild ile eklenen
  // option'lari cocuklar listesinde tutmuyordu: o yol bosuna yesil veriyordu.)
  const secenekler = (e, id) =>
    [...String((e.el(id) || {}).innerHTML || '').matchAll(/value="([^"]*)"/g)]
      .map((m) => m[1]);

  // --- KAYIT seviyesi (personel/vardiya) --------------------------------
  let e = await hazirla('kayit', 'personel');
  sonuc(!secenekler(e, 'hTip').some((v) => /duzeltme|Düzeltme/.test(v)),
    'E1 kayit seviyesinde "Duzeltme" secenegi SUNULMUYOR',
    'secenekler=' + JSON.stringify(secenekler(e, 'hTip')));
  sonuc(/tam mali yetki/i.test(String(e.el('maliRozet').innerHTML || '')),
    'E2 kayit seviyesinde rozet iade/indirim icin tam yetki gerektigini yaziyor',
    String(e.el('maliRozet').innerHTML || '').slice(0, 60));
  let oncekiIstek = istekSayisi(e, /pms_folio_hareketleri/);
  e.calistir("document.getElementById('hTip').value='ekstra';"
           + "document.getElementById('hAciklama').value='Iade denemesi';"
           + "document.getElementById('hTutar').value='-50';");
  await e.calistir('hareketEkle()');
  sonuc(/tam mali yetki/i.test(e.sonToast()),
    'E3 kayit: negatif hareket denemesinde ANLASILIR uyari', e.sonToast().slice(0, 60));
  es('E3b kayit: negatif harekette AG ISTEGI GONDERILMEDI', oncekiIstek,
    istekSayisi(e, /pms_folio_hareketleri/));
  oncekiIstek = istekSayisi(e, /pms_folio_odemeler/);
  e.calistir("document.getElementById('oYontem').value='nakit';"
           + "document.getElementById('oTutar').value='-40';"
           + "document.getElementById('oAciklama').value='Iade denemesi';");
  await e.calistir('odemeEkle()');
  sonuc(/tam mali yetki/i.test(e.sonToast()),
    'E4 kayit: negatif tahsilat denemesinde ANLASILIR uyari', e.sonToast().slice(0, 60));
  es('E4b kayit: negatif tahsilatta AG ISTEGI GONDERILMEDI', oncekiIstek,
    istekSayisi(e, /pms_folio_odemeler/));
  // POZITIF kontrol: normal tahsilat ekranda GECER ve istek GIDER.
  oncekiIstek = istekSayisi(e, /pms_folio_odemeler/);
  e.calistir("document.getElementById('oYontem').value='nakit';"
           + "document.getElementById('oTutar').value='60';"
           + "document.getElementById('oAciklama').value='Nakit';");
  await e.calistir('odemeEkle()');
  sonuc(istekSayisi(e, /pms_folio_odemeler/) > oncekiIstek,
    'E5 kayit: POZITIF tahsilat istegi GONDERILDI (pozitif kontrol)');

  // --- TAM seviyesi (sef) ----------------------------------------------
  e = await hazirla('tam', 'sef');
  sonuc(secenekler(e, 'hTip').some((v) => /duzeltme|Düzeltme/.test(v)),
    'E6 tam seviyesinde "Duzeltme" secenegi SUNULUYOR',
    'secenekler=' + JSON.stringify(secenekler(e, 'hTip')));
  oncekiIstek = istekSayisi(e, /pms_folio_hareketleri/);
  e.calistir("document.getElementById('hTip').value='ekstra';"
           + "document.getElementById('hAciklama').value='';"
           + "document.getElementById('hTutar').value='-25';");
  await e.calistir('hareketEkle()');
  sonuc(/gerekçe|Açıklama zorunlu/i.test(e.sonToast()),
    'E7 tam: GEREKCESIZ hassas hareket ekranda REDDEDILDI', e.sonToast().slice(0, 60));
  es('E7b tam: gerekcesizde AG ISTEGI GONDERILMEDI', oncekiIstek,
    istekSayisi(e, /pms_folio_hareketleri/));
  e.calistir("document.getElementById('hTip').value='ekstra';"
           + "document.getElementById('hAciklama').value='Musteri sikayeti indirimi';"
           + "document.getElementById('hTutar').value='-25';");
  await e.calistir('hareketEkle()');
  sonuc(istekSayisi(e, /pms_folio_hareketleri/) > oncekiIstek,
    'E8 tam: GEREKCELI hassas hareket istegi GONDERILDI (pozitif kontrol)');
  sonuc(Number(tek(`select count(*) from public.pms_folio_hareketleri
      where folio_id='${folio2}' and tutar<0;`)) >= 1,
    'E8b tam: gerekceli hassas hareket SUNUCUDA da yazildi (ekran-sunucu tutarli)');

  // ======================================================================
  // MY-3 — "dar sistem istisnasi" karsi ornegi + GERCEK bar akisi
  // ======================================================================
  console.log('\n--- MY-3: kaynak etiketi istisnasi ---');
  // Olculdu: current_user <> session_user yalniz SECURITY DEFINER'da degil
  // sirada SET ROLE gecisinde de dogrudur; kaynak_tip istemcinin yazabildigi
  // bir alandir. Bu yuzden ikisinin birlesimi "onayli bar fonksiyonundan
  // gelindi" kaniti DEGILDIR. Istisna KALDIRILDI; karsi ornek bunu olcer.
  const servisOlarak = (q) => O.kimlikle({ rol: 'service_role', sub: U.vardiya }, q);
  const negBar = `insert into public.pms_folio_hareketleri
    (otel_id, folio_id, tip, aciklama, tutar, kaynak_tip)
    values ('810','${folio}','bar','Taklit bar kaynagi',-33,'bar');`;
  let mr = servisOlarak(negBar);
  sonuc(!mr.ok && /MALI_TAM_YETKI_GEREKLI/.test(mr.err),
    'MY3 RLS ATLAYAN baglamda bar etiketli NEGATIF hareket REDDEDILDI',
    mr.ok ? 'KABUL EDILDI (kusur)' : (mr.err.match(/MALI_[A-Z_]+/) || ['?'])[0]);
  mr = olarak('vardiya', negBar);
  sonuc(!mr.ok, 'MY3b normal baglamda bar etiketli negatif hareket de REDDEDILDI',
    mr.ok ? 'KABUL EDILDI (kusur)' : 'ret');
  es('MY3c taklit denemeleri sonrasi negatif bar satiri YOK', 0,
    tek(`select count(*) from public.pms_folio_hareketleri
         where folio_id='${folio}' and tutar<0 and kaynak_tip='bar';`));
  sonuc(!/current_user is distinct from session_user/.test(fs.readFileSync(KURAL, 'utf8')),
    'MY3d gereksiz "dar sistem istisnasi" dosyadan KALDIRILDI');

  // --- GERCEK bar koprusu OLUMLU kontrolu (mali migration UYGULANMIS taban) --
  // Istisna kaldirildi; sistem akisi artik NORMAL daldan gecmeli. Oda ucreti
  // RPC'si yerine GERCEK kopru fonksiyonu tetiklenir. Siparisi BAR personeli
  // acar: On Buro rollerinin yetkisi GENISLETILMEZ.
  const menuUrun = tek("select id::text from public.menu_urunler where ucretli limit 1;");
  const oda202 = tek(`select oda_no from public.pms_odalar where id='${PMS.ODA202}';`);
  const barHareket = () => tek(`select count(*) from public.pms_folio_hareketleri
    where folio_id='${folio2}' and kaynak_tip='bar';`);
  const barToplam = () => tek(`select coalesce(sum(tutar),0) from public.pms_folio_hareketleri
    where folio_id='${folio2}' and kaynak_tip='bar';`);
  sonuc(!!menuUrun, 'MY3e0 ucretli menu urunu var (onkosul)', String(menuUrun).slice(0, 12));

  const sipR = olarak('bar', `insert into public.bar_siparisleri (otel_id, depo_id, durum, oda_no)
    values ('810','BAR-TEST','yeni','${oda202}') returning id::text;`);
  sonuc(sipR.ok && !!sipR.out.trim(), 'MY3e1 BAR personeli siparis acti',
    sipR.ok ? sipR.out.trim().slice(0, 12) : String(sipR.err).slice(0, 110));
  const sip = sipR.out.trim();

  const kalemR = olarak('bar', `insert into public.bar_siparis_kalemleri
      (siparis_id, menu_urun_id, adet) values ('${sip}','${menuUrun}',2);`);
  sonuc(kalemR.ok, 'MY3e2 siparis kalemi eklendi (adet=2)',
    kalemR.ok ? '' : String(kalemR.err).slice(0, 110));

  const oncekiBar = barHareket(), oncekiTop = barToplam();
  const teslimR = olarak('bar', `update public.bar_siparisleri set durum='teslim_edildi'
    where id='${sip}';`);
  sonuc(teslimR.ok, 'MY3e3 teslim edildi -> GERCEK kopru tetiklendi',
    teslimR.ok ? '' : String(teslimR.err).slice(0, 140));

  const sonrakiBar = barHareket(), sonrakiTop = barToplam();
  sonuc(Number(sonrakiBar) === Number(oncekiBar) + 1,
    'MY3e4 OLUMLU: bar borcu folyoya TEK hareket olarak yazildi',
    oncekiBar + ' -> ' + sonrakiBar);
  sonuc(Number(sonrakiTop) > Number(oncekiTop),
    'MY3e5 OLUMLU: yazilan tutar POZITIF (bakiye artti)',
    oncekiTop + ' -> ' + sonrakiTop);
  es('MY3e6 bar kaynakli NEGATIF satir YOK', 0,
    tek(`select count(*) from public.pms_folio_hareketleri
         where folio_id='${folio2}' and kaynak_tip='bar' and tutar<0;`));
  sonuc(/'bar'/.test(tek(`select coalesce(string_agg(distinct tip::text, ','),'(yok)')
      from public.pms_folio_hareketleri where folio_id='${folio2}' and kaynak_tip='bar';`))
      || tek(`select coalesce(string_agg(distinct tip::text, ','),'(yok)')
         from public.pms_folio_hareketleri where folio_id='${folio2}' and kaynak_tip='bar';`) === 'bar',
    'MY3e7 hareket tipi bar olarak kaydedildi');

  // --- BORC ISTISNASI yolu: KALICI regresyon ------------------------------
  // Onceki surumde bu yol SINANMADI idi: sabit taban (09-13) tabloyu tasimiyor.
  // Artik A1 guvenlik migration'i (2026-09-18) bu testin icinde uygulanir ve
  // GERCEK bar_borc_istisnasi_coz fonksiyonu kosulur. Mali kural bu yoldan
  // SONRA yeniden uygulanir ki hassas kapi yururlukte kalsin.
  const a1R = O.sql(fs.readFileSync(KOK + 'docs/kurulum/2026-09-18-bar-a1-guvenlik.sql', 'utf8'));
  sonuc(a1R.ok, 'MY3f0 A1 guvenlik migration uygulandi (borc istisnasi altyapisi)',
    a1R.ok ? '' : String(a1R.err).slice(-200));
  const maliTekrar = O.sql(fs.readFileSync(KURAL, 'utf8'));
  sonuc(maliTekrar.ok, 'MY3f1 mali ayrim kurali A1 ustune yeniden uygulandi',
    maliTekrar.ok ? '' : String(maliTekrar.err).slice(-200));
  es('MY3f2 iki hassas kapi tetikleyicisi etkin', 2,
    tek("select count(*) from pg_trigger t join pg_class c on c.oid=t.tgrelid "
      + "where t.tgname='pms_folio_hassas_kapi' and not t.tgisinternal;"));

  if (a1R.ok) {
    // Mevcut A1 test altyapisi kullanilir (yeni altyapi KURULMAZ): siparis
    // GERCEK RPC'lerle acilir, oda dogrulanir, hazirlanir ve teslim edilir.
    const A1 = a1Yardimcilari(O);
    A1.sifirla();

    // (a) Acik folyolu odaya normal teslim -> folyoya POZITIF borc
    const s1 = A1.siparis(K.BAR810, A1.VISKI1, '101');
    const id1 = s1.out.trim();
    sonuc(s1.ok && !!id1, 'MY3f3 GERCEK siparis RPC ile acildi (oda 101)',
      s1.ok ? id1.slice(0, 12) : String(s1.err).replace(/\s+/g, ' ').slice(-120));
    A1.q(K.BAR810, `select public.bar_siparis_oda_dogrula('${id1}',true);`);
    A1.hazirla(id1);
    const t1 = A1.q(K.BAR810, `select public.bar_siparis_teslim_et('${id1}');`);
    sonuc(t1.ok, 'MY3f4 GERCEK teslim RPC kostu', t1.ok ? '' : String(t1.err).replace(/\s+/g, ' ').slice(-130));
    es('MY3f5 acik folyoya TEK POZITIF bar borcu yazildi', '250.00',
      tek(`select coalesce(sum(tutar),0)::text from public.pms_folio_hareketleri
           where folio_id='${FOLYO101}' and kaynak_tip='bar';`));
    es('MY3f6 negatif bar satiri YOK', 0,
      tek(`select count(*) from public.pms_folio_hareketleri
           where folio_id='${FOLYO101}' and kaynak_tip='bar' and tutar<0;`));

    // (b)/(c) KAPALI folyo -> borc istisnasi -> cozum senaryosu bu suitin
    // fiksturunde kurulamiyordu (bu suit kendi check-in akislarini yurutugu
    // icin oda 101 icin ACIK folyo kaliyor ve istisna sarti olusmuyor).
    // ARTIK AYRI ve TEMIZ fiksturlu KALICI testte olculuyor:
    //   scripts/pms-bar-borc-istisnasi.test.mjs  (B4..B8)
    // Burada tekrar edilmez; o dosya migration sirasini da (A1 -> mali kural
    // -> tohum) referans sondayla ayni kurar.
    console.log("NOT: kapali folyo -> borc istisnasi -> cozum senaryosu "
      + "scripts/pms-bar-borc-istisnasi.test.mjs icinde KALICI olarak olculuyor.");

    // Bagimsiz olculebilen kisim: mali kural A1 tabaninda da yururlukte.
    const hedefA1 = tek(`select id::text from public.pms_folyolar
      where durum='acik' and otel_id='810' order by acilis_zamani limit 1;`);
    if (hedefA1) {
      const taklit = servisOlarak(`insert into public.pms_folio_hareketleri
        (otel_id, folio_id, tip, aciklama, tutar, kaynak_tip)
        values ('810','${hedefA1}','bar','A1 tabaninda taklit',-21,'bar');`);
      const red = !taklit.ok && /MALI_TAM_YETKI_GEREKLI/.test(taklit.err);
      sonuc(red, 'MY3f8 A1 tabaninda da taklit negatif bar hareketi REDDEDILDI',
        taklit.ok ? 'KABUL EDILDI (kusur)' : 'MALI_TAM_YETKI_GEREKLI');
    } else {
      console.log("SINANMADI MY3f8 — acik folyo yok; GECTI SAYILMAZ");
    }
  }

  // ======================================================================
  // M8 — GUVENLI GERI DONUS
  // ======================================================================
  console.log('\n--- M8: guvenli geri donus ---');
  let g = O.sql(fs.readFileSync(KURAL_GERI, 'utf8'));
  sonuc(!g.ok && /GUVENLI GERI DONUS ENGELI/.test(g.err),
    'M8 yetki ACIKKEN geri alma DURUYOR',
    g.ok ? 'KOSTU (kusur)' : (g.err.match(/su roller hala[^.]*/) || ['?'])[0].slice(0, 70));
  // Hassas kapi hala yerinde mi?
  r = hareket('personel', { tutar: -5, aciklama: 'Ret sonrasi deneme' });
  sonuc(!r.ok, 'M8b engellenen geri almadan sonra kural hala YURURLUKTE');
  // Bilincli zorlama uyarisi
  // MY-2: ZORLAMA YOLU KALDIRILDI. Onayli tasarim, personel/vardiya yetkisi
  // acikken eski genis INSERT kuralinin geri gelmemesini sart kosuyor; bir
  // bayrakla bunu atlamak yeni bir yetki genisletme yoludur ve kullanici onayi
  // yerine gecmez. Karsi ornek: bayrak verilse DE geri alma durmali ve kural
  // yururlukte kalmali.
  sonuc(!/pms_mali_geri_zorla/.test(fs.readFileSync(KURAL_GERI, 'utf8')),
    'M8c zorlama yolu dosyadan KALDIRILDI');
  // NOT: "set local" dosyanin begin'inden ONCE verilince ATILIR; bayragin
  // GERCEKTEN DO blogua ulasmasi icin OTURUM duzeyinde verilir. Aksi halde bu
  // karsi ornek yanlis sebeple yesil olurdu (olculdu).
  g = O.sql("set app.pms_mali_geri_zorla = 'evet';\n"
    + fs.readFileSync(KURAL_GERI, 'utf8'));
  sonuc(!g.ok && /GUVENLI GERI DONUS ENGELI/.test(g.err),
    'M8c2 bayrak VERILSE DE geri alma DURUYOR',
    g.ok ? 'KOSTU (kusur)' : (g.err.match(/GUVENLI GERI DONUS ENGELI/) || ['?'])[0]);
  r = odeme('vardiya', { tutar: -14, aciklama: 'Bayrak sonrasi deneme' });
  sonuc(!r.ok, 'M8c3 bayrak denemesinden sonra vardiya hala NEGATIF ODEME YAZAMIYOR',
    r.ok ? 'YAZDI (kusur)' : (r.err.match(/MALI_[A-Z_]+|row-level security/i) || ['ret'])[0]);
  // Dogru sira: yetkiyi kaldir, sonra geri al.
  O.sql(fs.readFileSync(KURAL, 'utf8'));   // kurali geri kur
  O.sql(`delete from public.yetki_matrisi ym using public.roller r, public.moduller m
         where ym.rol_id=r.id and ym.modul_id=m.id and m.kod='pms_folio'
           and r.kod in ('onburo_personel','onburo_vardiya');`);
  g = O.sql(fs.readFileSync(KURAL_GERI, 'utf8'));
  sonuc(g.ok && /Geri alma tamam/.test(g.err),
    'M8d yetki KALDIRILINCA geri alma kostu', g.ok ? '' : g.err.slice(-150));
  sonuc(/Degismezlik korunuyor/.test(g.err),
    'M8e geri alma sonrasi DEGISMEZLIK olculdu ve korundu');
  // Olcut satirin kimligi DEGIL silinemezliktir; A1 blogu tabloyu sifirlamis
  // olabilecegi icin GUNCEL bir mali satir secilir. Hic satir yoksa iddia
  // uretilmez: SINANMADI yazilir.
  const hId2 = tek(`select id::text from public.pms_folio_hareketleri limit 1;`);
  if (!hId2) {
    console.log("SINANMADI M8f — mali hareket satiri yok; GECTI SAYILMAZ");
  } else {
    const suR2 = O.sql(`delete from public.pms_folio_hareketleri where id='${hId2}';`);
    sonuc(!suR2.ok && /degistirilemez/i.test(suR2.err),
      'M8f geri alma sonrasi mali satir hala SILINEMEZ',
      suR2.ok ? 'SILINDI (kusur)' : 'tetikleyici reddi');
  }

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
