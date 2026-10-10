// ===========================================================================
// MALI SUNUCU RETLERI SONDASI — IZOLE KANIT (uretime BAGLANMAZ)
// ===========================================================================
// Sonda: docs/kurulum/2026-10-09-pms-mali-sunucu-retleri-sondasi.sql
// Plan  : docs/kurulum/2026-10-09-pms-mali-sunucu-retleri-plani.md
//
// Sonda CANLIDA kosulmadan once guvenlik ozellikleri burada KANITLANIR:
//   G0  Hedef secimi DOLDURULMAMISSA sonda duruyor mu
//   G1  Gercek uygulama rolu ile ALTI deneme dogru siniflaniyor mu
//   G2  BEKLENMEDIK KABUL olsa bile ROLLBACK kalici satir birakmiyor mu
//   G3  KAPALI FOLYO asil yetki hatasini maskeliyorsa yakalaniyor mu
//   G4  `postgres` yetkisiyle alinan sonuc GECERSIZ sayiliyor mu
//   G5  Tek kalici iz dizi bosluklari mi, ciktida belirtiliyor mu
//   G6  Sentetik misafir YOKSA duruyor mu
//   G7  Sentetik misafir COKLU eslesiyorsa duruyor mu
//   G8  Misafir isareti sentetik gorunmuyorsa duruyor mu
//   G9  Personel TAM yetkiliyse (K1 anlamsiz) duruyor mu
//   G10 Mesaj dogru ama SQLSTATE yanlissa BEKLENEN RET sayilmiyor mu
//
// Izole Docker + sentetik veri. Canliya DOKUNULMAZ.
// Kullanim: node scripts/pms-mali-sunucu-sonda.test.mjs
// ===========================================================================
import { readFileSync } from 'node:fs';
import { barOrtami } from './bar-test-ortam.mjs';
import { EK_TOHUM } from './bar-a1-tohum.mjs';
import { PMS, PMS_TOHUM } from './pms-akis-tohum.mjs';

const KOK = new URL('..', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const MALI = 'docs/kurulum/2026-10-06-pms-folio-mali-yetki-ayrimi.sql';
const KILIT = 'docs/kurulum/2026-10-06-pms-rol-entegrasyon-kilit.sql';
const SONDA = KOK + 'docs/kurulum/2026-10-09-pms-mali-sunucu-retleri-sondasi.sql';
const O = barOrtami({ ad: 'pms-sonda', ag: 'pms-sonda-net' });

const U_PERS = '11111111-0000-0000-0000-00000000e001';
const U_YON = '11111111-0000-0000-0000-00000000e002';
const OTEL = '810';
const MISAFIR = 'QA-SONDA-IZOLE';

let ok = 0, fail = 0;
const sonuc = (g, ad, ek) => {
  console.log((g ? 'OK   ' : 'FAIL ') + ad + (ek ? ' — ' + ek : ''));
  if (g) ok++; else fail++;
};
const es = (ad, bek, olc) => sonuc(String(bek) === String(olc), ad,
  String(bek) === String(olc) ? String(olc) : `beklenen=${bek} olculen=${olc}`);
const tek = (q) => O.sql(q).out.trim();
const say = (q) => Number(tek(q) || '0');
const hata = (r) => (String(r.err).split('\n')
  .filter((l) => /ERROR|HATA/.test(l))[0] || '(mesaj yok)').slice(0, 98);

// Sonda ciktisindan kapi satirini ve siniflari cikarir.
// Kapi satiri da "BEKLENEN RET" metnini icerdigi icin SATIR SATIR ayiklanir;
// yoksa kapi metni fazladan bir deneme gibi sayilir (yanlis-yesil).
const SINIF_RE = /BEKLENEN RET[^|]*|KABUL \(KUSUR\)|MASKELENDI \(GECERSIZ\)|BEKLENMEYEN \(GECERSIZ\)|SQLSTATE YANLIS[^|]*|FARKLI KATMAN[^|]*|KIMLIK YANLIS[^|]*/g;
const kapi = (cikti) => (cikti.split('\n').find((l) => /UYGUN|GECERSIZ|INCELE/.test(l)) || '').trim();
const siniflar = (cikti) => cikti.split('\n')
  .filter((l) => !/^(UYGUN|INCELE|GECERSIZ)/.test(l.trim()))
  .flatMap((l) => l.match(SINIF_RE) || []).map((x) => x.trim());

// Sondanin HEDEF SECIMI satirlarini doldurur. Canlida bunu operator elle
// yapar; burada doldurmanin GERCEKTEN tuttugu da dogrulanir (capa yoksa atar).
const doldur = (deger = {}) => {
  const tam = {
    hedef_otel: OTEL, hedef_personel: U_PERS,
    hedef_yonetici: U_YON, hedef_misafir: MISAFIR, ...deger,
  };
  let s = readFileSync(SONDA, 'utf8');
  for (const [ad, v] of Object.entries(tam)) {
    const re = new RegExp(`set local sonda\\.${ad}\\s*=\\s*'DOLDUR';`);
    if (!re.test(s)) throw new Error('DOLDUR capasi yok: ' + ad);
    s = s.replace(re, `set local sonda.${ad} = '${v}';`);
  }
  if (/= 'DOLDUR';/.test(s)) throw new Error('DOLDUR kalintisi var');
  return s;
};

// Mali migration'dan YALNIZ hassas kapi fonksiyonunu ayiklar (G2e/G10 mutanti).
const hassasKapiBlogu = () => {
  const m = readFileSync(KOK + MALI, 'utf8')
    .match(/create or replace function public\.pms_folio_hassas_kapi\(\)[\s\S]*?\n\$\$;/);
  if (!m) throw new Error('hassas kapi blogu bulunamadi');
  return m[0];
};

try {
  await O.kur();
  if (!O.sql(EK_TOHUM).ok) throw new Error('A1 ek tohum kurulamadi');
  if (!O.sql(PMS_TOHUM).ok) throw new Error('PMS tohum kurulamadi');

  // Uretimde MY-4 kilidi de uygulanmis durumda; sonda AYNI tabanda kosmali.
  const kilit = O.sql(readFileSync(KOK + KILIT, 'utf8'));
  sonuc(kilit.ok, 'F1b MY-4 rol entegrasyon kilidi uygulandi',
    kilit.ok ? '' : hata(kilit));

  const mali = O.sql(readFileSync(KOK + MALI, 'utf8'));
  sonuc(mali.ok, 'F1 mali ayrim kurali uygulandi', mali.ok ? '' : hata(mali));

  // --- Gercek rol/otel fiksturu + SENTETIK misafir ------------------------
  const f = O.sql(`set session_replication_role = replica;
    insert into public.moduller (kod, ad, kategori, sira, aktif) values
      ('pms_oda_tipi','On Buro — Oda Tipleri','onburo',43,true),
      ('pms_oda','On Buro — Odalar','onburo',44,true),
      ('pms_misafir','On Buro — Misafirler','onburo',45,true),
      ('pms_rezervasyon','On Buro — Rezervasyonlar','onburo',47,true),
      ('pms_folio','On Buro — Folio','onburo',48,true) on conflict (kod) do nothing;
    insert into public.roller (id, ad, seviye, kod, sira) values
      ('00000000-0000-0000-0000-00000000e001','On Buro Personel','otel','onburo_personel',22),
      ('00000000-0000-0000-0000-00000000e002','IT Admin','grup','it_admin',2)
      on conflict do nothing;
    insert into public.yetki_matrisi (rol_id, modul_id, yetki)
    select r.id, m.id, v.y::public.yetki_seviye from (values
        ('onburo_personel','pms_oda_tipi','goruntule'),
        ('onburo_personel','pms_oda','goruntule'),
        ('onburo_personel','pms_misafir','kayit'),
        ('onburo_personel','pms_rezervasyon','kayit'),
        ('onburo_personel','pms_folio','kayit'),
        ('it_admin','pms_oda_tipi','tam'), ('it_admin','pms_oda','tam'),
        ('it_admin','pms_misafir','tam'), ('it_admin','pms_rezervasyon','tam'),
        ('it_admin','pms_folio','tam')) v(rk,mk,y)
      join public.roller r on r.kod = v.rk
      join public.moduller m on m.kod = v.mk
      on conflict (rol_id, modul_id) do nothing;
    insert into auth.users (id, email) values
      ('${U_PERS}','sonda-personel@test.local'), ('${U_YON}','sonda-yonetici@test.local')
      on conflict (id) do nothing;
    insert into public.kullanicilar (id, auth_user_id, ad, rol, otel_id, aktif, rol_id)
    select gen_random_uuid(), v.au, v.ad, 'muhasebe_calisani', '${OTEL}', true, r.id
      from (values ('${U_PERS}'::uuid,'Sonda Personel','onburo_personel'),
                   ('${U_YON}'::uuid,'Sonda Yonetici','it_admin')) v(au,ad,rk)
      join public.roller r on r.kod = v.rk;
    insert into public.pms_misafirler (otel_id, ad, soyad, aktif)
      values ('${OTEL}','QA','${MISAFIR}',true);
    set session_replication_role = origin;`);
  sonuc(f.ok, 'F2 gercek rol/otel + sentetik misafir fiksturu kuruldu',
    f.ok ? '' : hata(f));

  const harOnce = say('select count(*) from public.pms_folio_hareketleri;');
  const odeOnce = say('select count(*) from public.pms_folio_odemeler;');
  const rezOnce = say('select count(*) from public.pms_rezervasyonlar;');
  const folOnce = say('select count(*) from public.pms_folyolar;');
  const misOnce = say('select count(*) from public.pms_misafirler;');

  // =====================================================================
  // G0 — HEDEF SECIMI DOLDURULMAMISSA SONDA DURMALI
  // "Ilk bulunani al" mantigi yok: eksik secim, yanlis otelde olcum demektir.
  // =====================================================================
  const s0 = O.sql(readFileSync(SONDA, 'utf8'));
  sonuc(!s0.ok && /hedef secimi DOLDURULMAMIS/.test(s0.err + s0.out),
    'G0 doldurulmamis hedef secimiyle sonda DURDU', hata(s0));
  es('G0b doldurulmamis kosumda satir yazilmadi', rezOnce,
    say('select count(*) from public.pms_rezervasyonlar;'));

  // =====================================================================
  // G1 — SONDA GERCEK ROLLE DOGRU SINIFLANDIRIYOR MU (alti deneme)
  // =====================================================================
  const s1 = O.sql(doldur());
  sonuc(s1.ok, 'G1 sonda hatasiz kostu (islem rollback ile bitti)',
    s1.ok ? '' : hata(s1));
  const sin1 = siniflar(s1.out);
  es('G1b alti deneme de BEKLENEN RET (katman etiketi serbest)', 6,
    sin1.filter((x) => x.startsWith('BEKLENEN RET')).length);
  sonuc(/UYGUN: alti denemenin altisi da BEKLENEN RET/.test(s1.out),
    'G1c kimlik ve sonuc kapisi UYGUN dedi', kapi(s1.out).slice(0, 70));
  sonuc(!/postgres/.test(s1.out.split('\n').filter((l) => /BEKLENEN RET/.test(l)).join()),
    'G1d denemelerin rolu postgres DEGIL (authenticated)');
  sonuc(['K1 personel negatif odeme', 'K2 yonetici gerekcesiz iade',
    'K3a mevcut HAREKET satiri UPDATE', 'K3b mevcut HAREKET satiri DELETE',
    'K4a mevcut ODEME satiri UPDATE', 'K4b mevcut ODEME satiri DELETE']
    .every((k) => s1.out.includes(k)),
    'G1e ODEMELER tablosu da sinandi (K4a/K4b ciktida)');
  sonuc(s1.out.includes(MISAFIR) && s1.out.includes(U_PERS)
    && s1.out.includes(U_YON) && /otel\s*\|\s*810/.test(s1.out),
    'G1f secilen hedef ciktida raporlandi (otel/kimlikler/misafir)');

  // =====================================================================
  // G2 — KALICI DEGISIKLIK YOK (beklenmedik kabulde bile)
  // =====================================================================
  es('G2 hareket satiri sayisi degismedi', harOnce,
    say('select count(*) from public.pms_folio_hareketleri;'));
  es('G2b odeme satiri sayisi degismedi', odeOnce,
    say('select count(*) from public.pms_folio_odemeler;'));
  es('G2c rezervasyon sayisi degismedi (sonda fiksturu geri alindi)', rezOnce,
    say('select count(*) from public.pms_rezervasyonlar;'));
  es('G2d folyo sayisi degismedi', folOnce,
    say('select count(*) from public.pms_folyolar;'));
  es('G2d2 misafir sayisi degismedi', misOnce,
    say('select count(*) from public.pms_misafirler;'));

  // BEKLENMEDIK KABUL taklidi. Sunucu katmanlarini KIRMAK yerine, denemenin
  // kendisi KABUL EDILECEK bir yazmaya cevrilir: negatif tutar yerine pozitif.
  // (Olculdu: tetikleyici kapisi devre disi birakilsa negatif odemeyi RLS
  // reddediyor; yani kabul taklidi icin iki katman kirmak gerekirdi. Oysa
  // sinanmak istenen ozellik sondanin KABUL halindeki davranisidir.)
  const kabulTaklidi = doldur().split('-50.00').join('5.00');
  if (kabulTaklidi.includes('-50.00') || !kabulTaklidi.includes('5.00')) {
    throw new Error('G2e kabul taklidi capasi tutmadi');
  }
  const s2 = O.sql(kabulTaklidi);
  const sin2 = siniflar(s2.out);
  sonuc(sin2.some((x) => x === 'KABUL (KUSUR)'),
    'G2e kusur taklidinde sonda KABUL (KUSUR) raporladi',
    sin2.join(' | ').slice(0, 84));
  sonuc(/INCELE|GECERSIZ/.test(kapi(s2.out)),
    'G2f kapi bunu UYGUN saymadi', kapi(s2.out).slice(0, 70));
  es('G2g KUSURA RAGMEN hareket sayisi degismedi', harOnce,
    say('select count(*) from public.pms_folio_hareketleri;'));
  es('G2h KUSURA RAGMEN odeme sayisi degismedi', odeOnce,
    say('select count(*) from public.pms_folio_odemeler;'));

  // =====================================================================
  // G3 — KAPALI FOLYO MASKELEMESI YAKALANIYOR MU
  // Sonda hedef folyoyu ISLEM ICINDE acik kurar; kapali folyoya dusulurse
  // kendi kurulum kapisi DURDURUR. Otomatik folyoyu aninda kapatan gecici
  // bir tetikleyiciyle taklit ediyoruz.
  // =====================================================================
  O.sql(`create or replace function public.sonda_folyo_kapat() returns trigger
    language plpgsql as $$ begin
      update public.pms_folyolar set durum='kapali', kapanis_zamani=now()
        where id = new.id;
      return new; end $$;
    create trigger sonda_folyo_kapat after insert on public.pms_folyolar
      for each row execute function public.sonda_folyo_kapat();`);
  const s3 = O.sql(doldur());
  sonuc(!s3.ok && /hedef folyo ACIK degil|MASKELER/.test(s3.err + s3.out),
    'G3 kapali folyo hedefi DURDURDU (maskeleme engellendi)', hata(s3));
  es('G3b maskeleme denemesinde de satir kalmadi', harOnce,
    say('select count(*) from public.pms_folio_hareketleri;'));
  O.sql(`drop trigger if exists sonda_folyo_kapat on public.pms_folyolar;
    drop function if exists public.sonda_folyo_kapat();`);

  // =====================================================================
  // G4 — `postgres` ile kosulan sonuc GECERSIZ sayilmali
  // =====================================================================
  const postgresGibi = doldur()
    .split("execute 'set local role authenticated';")
    .join('-- rol degistirme DEVRE DISI (G4)');
  const s4 = O.sql(postgresGibi);
  sonuc(/GECERSIZ: en az bir deneme gercek uygulama rolu disinda kostu/.test(s4.out),
    'G4 postgres ile kosum GECERSIZ sayildi', kapi(s4.out).slice(0, 72));
  sonuc(!/UYGUN: alti denemenin altisi/.test(s4.out),
    'G4b postgres kosumu "UYGUN" DEMEDI');
  es('G4c postgres kosumunda da satir kalmadi', harOnce,
    say('select count(*) from public.pms_folio_hareketleri;'));

  // =====================================================================
  // G5 — TEK KALICI IZ: dizi bosluklari; ciktida ACIKCA yaziyor mu
  // =====================================================================
  const dizi = tek('select last_value::text from public.pms_folio_no_seq;');
  sonuc(Number(dizi) >= 1, 'G5 folyo dizisi ilerledi (bilinen tek kalici iz)',
    'last_value=' + dizi);
  sonuc(/GECICI YAZMA: 1 rezervasyon/.test(s1.out)
    && /KALICI IZ: pms_rezervasyon_no_seq ve pms_folio_no_seq/.test(s1.out),
    'G5b gecici yazma ve dizi etkisi ciktida acikca belirtildi');

  // =====================================================================
  // G6/G7/G8 — SENTETIK MISAFIR KAPISI: yok / coklu / sentetik degil
  // =====================================================================
  const s6 = O.sql(doldur({ hedef_misafir: 'QA-OLMAYAN-KAYIT' }));
  sonuc(!s6.ok && /sentetik misafir .*YOK/.test(s6.err + s6.out),
    'G6 misafir YOKSA sonda DURDU', hata(s6));

  O.sql(`set session_replication_role = replica;
    insert into public.pms_misafirler (otel_id, ad, soyad, aktif)
      values ('${OTEL}','QA Ikinci','${MISAFIR}',true);
    set session_replication_role = origin;`);
  const s7 = O.sql(doldur());
  sonuc(!s7.ok && /kez *eslesti|belirsiz/.test(s7.err + s7.out),
    'G7 COKLU misafir eslesmesinde sonda DURDU', hata(s7));
  O.sql(`delete from public.pms_misafirler
     where soyad='${MISAFIR}' and ad='QA Ikinci';`);

  const s8 = O.sql(doldur({ hedef_misafir: 'Yilmaz' }));
  sonuc(!s8.ok && /SENTETIK gorunmuyor/.test(s8.err + s8.out),
    'G8 sentetik olmayan isarette sonda DURDU', hata(s8));

  // =====================================================================
  // G9 — PERSONEL TAM YETKILIYSE K1 OLCUMU ANLAMSIZ: sonda durmali
  // =====================================================================
  O.sql(`set session_replication_role = replica;
    update public.yetki_matrisi y set yetki='tam'
      from public.roller r, public.moduller m
     where y.rol_id=r.id and y.modul_id=m.id
       and r.kod='onburo_personel' and m.kod='pms_folio';
    set session_replication_role = origin;`);
  const s9 = O.sql(doldur());
  sonuc(!s9.ok && /pms_folio yetkisi tam/.test(s9.err + s9.out),
    'G9 personel TAM yetkiliyken sonda DURDU', hata(s9));
  O.sql(`set session_replication_role = replica;
    update public.yetki_matrisi y set yetki='kayit'
      from public.roller r, public.moduller m
     where y.rol_id=r.id and y.modul_id=m.id
       and r.kod='onburo_personel' and m.kod='pms_folio';
    set session_replication_role = origin;`);

  // =====================================================================
  // G10 — MESAJ DOGRU, SQLSTATE YANLIS: BEKLENEN RET SAYILMAMALI
  // K1 kapisinin errcode'u bozulur; mesaj metni ayni kalir.
  // =====================================================================
  const kapiBlok = hassasKapiBlogu();
  const sqlstateMutant = kapiBlok.replace(
    "using errcode = '42501';", "using errcode = 'P0001';");
  if (sqlstateMutant === kapiBlok) throw new Error('G10 mutant capasi tutmadi');
  if (!O.sql(sqlstateMutant).ok) throw new Error('G10 mutanti uygulanamadi');
  const s10 = O.sql(doldur());
  const sin10 = siniflar(s10.out);
  sonuc(sin10.some((x) => x.startsWith('SQLSTATE YANLIS')),
    'G10 dogru mesaj + yanlis SQLSTATE "SQLSTATE YANLIS" sayildi',
    sin10.join(' | ').slice(0, 88));
  sonuc(/INCELE|GECERSIZ/.test(kapi(s10.out)),
    'G10b kapi bunu UYGUN saymadi', kapi(s10.out).slice(0, 70));
  es('G10c SQLSTATE mutantinda da satir kalmadi', odeOnce,
    say('select count(*) from public.pms_folio_odemeler;'));
  if (!O.sql(kapiBlok).ok) throw new Error('G10 mutanti geri alinamadi');

  console.log('\n======================================================================');
  console.log(`SONUC: ${ok} gecti, ${fail} kaldi`);
  console.log('Yerel kanit; CANLI KOSUM yerine GECMEZ.');
  console.log('======================================================================');
} catch (e) {
  console.error('\nDUR: ' + (e && e.message));
  fail++;
} finally {
  try { O.temizle(); } catch { /* yoksay */ }
}
process.exit(fail === 0 ? 0 : 1);
