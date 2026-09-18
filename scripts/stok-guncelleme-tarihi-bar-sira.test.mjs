// ===========================================================================
// SIRA ve GERI ALMA TESTI: tarih duzeltmesi -> bar A1 -> geri alma
// izole, uretime BAGLANMAZ
// ===========================================================================
// Soru: 2026-09-18'de uretime alinan stok tarih duzeltmesi, bar A1 migration'i
// ve onun geri alma dosyasi uygulandiginda KORUNUYOR MU? (tasarim 3.5.1)
//
// Tarihsel planin metnine DAYANMAZ: GERCEK dosyalari uretim kanaliyla ayni kipte
// (tek islem) calistirir:
//   docs/kurulum/2026-09-18-bar-a1-guvenlik.sql
//   docs/kurulum/2026-09-18-bar-a1-guvenlik-geri-al.sql (uretilmis)
// Dosya yoksa test DUSER (sessizce atlamaz).
//
// Taban: uretim dokumu + uretim-sonrasi migration'lar (tarih duzeltmesi dahil,
// md5 uretim olcumuyle ayni) — bar-test-ortam.mjs.
//
// Kanit:
//   1  A1 uygulandi; stok_ekle ve transferin IKI bacagi tarihi yazar
//   2  rezervasyon korumasi cikisi ve transferi reddeder, satir (tarih dahil) degismez
//   3  rezervasyonsuz davranis ayni
//   4  geri alma: tarih duzeltmesi govdelerde ve davranista DURUYOR; A1
//      fonksiyonlari kalkti; A1 doneminin tuketim kayitlari KORUNDU
//   N1 A1'in tarih satirlari silinince (1) DUSER
//   N2 tarih duzeltmesi OLMAYAN tabanda A1 migration'i DURUR
//   N3 geri alma stok govdelerini eski dokumden (duzeltmesiz) alirsa (4) DUSER
// ===========================================================================
import { existsSync, readFileSync } from 'node:fs';
import { barOrtami, hataKodu, kok } from './bar-test-ortam.mjs';
import { dokumFonksiyonu } from './bar-a1-geri-al-uret.mjs';

const A1 = 'docs/kurulum/2026-09-18-bar-a1-guvenlik.sql';
const GERI = 'docs/kurulum/2026-09-18-bar-a1-guvenlik-geri-al.sql';
const BAR = '810_CSM302';
const ESKI = '2026-07-09 07:23:10+00';
const BAR810 = { rol: 'authenticated', sub: '11111111-0000-0000-0000-000000000810' };
const DEPO810 = { rol: 'authenticated', sub: '11111111-0000-0000-0000-0000000000cc' };

let ok = 0, fail = 0;
const sonuc = (g, ad, ek) => { console.log((g ? 'OK   ' : 'FAIL ') + ad + (ek ? ' — ' + ek : '')); if (g) ok++; else fail++; };

function tarihOlc(O, cagri) {
  O.sql(`update public.stok set guncelleme_tarihi = '${ESKI}' where depo_kodu in ('${BAR}','810_100');`);
  const r = O.kimlikle(DEPO810, cagri);
  const t = (d, u = 'BIRA') => O.sql(`select (guncelleme_tarihi > '2026-07-10')::text from public.stok
                                        where urun_kodu='${u}' and depo_kodu='${d}';`).out;
  return { ok: r.ok, err: r.err, bar: t(BAR), merkez: t('810_100') };
}
const tarihSeti = (O) => ({
  ekle: tarihOlc(O, `select public.stok_ekle('BIRA','${BAR}','810',1);`),
  transfer: tarihOlc(O, `select public.stok_transfer('BIRA','810_100','${BAR}','810',1);`),
});

async function main() {
  for (const f of [A1, GERI]) {
    if (!existsSync(kok + f)) { sonuc(false, 'dosya var: ' + f, 'A1 henuz uretilmemis'); return; }
  }
  const a1Metin = readFileSync(kok + A1, 'utf8');

  // ---------------- ana akis ----------------
  const O = barOrtami({ ad: 'bar-sira' });
  try {
    await O.kur();
    const u = O.uygulaTekIslem(A1);
    sonuc(u.ok, '1a A1 migration tarih duzeltmeli tabana tek islemde uygulandi', u.ok ? '' : u.err.slice(-300));
    const t = tarihSeti(O);
    sonuc(t.ekle.ok && t.ekle.bar === 'true', '1b A1 sonrasi stok_ekle tarihi yaziyor');
    sonuc(t.transfer.ok && t.transfer.bar === 'true' && t.transfer.merkez === 'true',
      '1c A1 sonrasi transferin IKI bacagi da tarihi yaziyor');

    O.sql(`update public.stok set miktar = 10 where urun_kodu='BIRA' and depo_kodu='${BAR}';`);
    O.kimlikle(BAR810, `select public.bar_siparis_olustur('810','${BAR}','M1',null,
      '[{"menu_urun_id":"22222222-0000-0000-0000-000000000001","adet":8}]'::jsonb);`);
    O.sql(`update public.stok set guncelleme_tarihi = '${ESKI}' where urun_kodu='BIRA' and depo_kodu='${BAR}';`);
    const c = O.kimlikle(DEPO810, `select public.stok_ekle('BIRA','${BAR}','810',-5);`);
    const tr = O.kimlikle(DEPO810, `select public.stok_transfer('BIRA','${BAR}','810_100','810',5);`);
    const satir = O.sql(`select miktar::text||'|'||(guncelleme_tarihi > '2026-07-10')::text from public.stok
                          where urun_kodu='BIRA' and depo_kodu='${BAR}';`).out;
    sonuc(hataKodu(c) === 'REZERVE_STOK' && hataKodu(tr) === 'REZERVE_STOK' && satir === '10.000|false',
      '2 rezervasyon korumasi cikis ve transferi reddetti; satir (miktar ve TARIH) degismedi', satir);
    const l = O.kimlikle(DEPO810, `select public.stok_ekle('LIMON','${BAR}','810',-1);`);
    sonuc(l.ok && O.sql(`select (guncelleme_tarihi > '2026-07-10')::text from public.stok where urun_kodu='LIMON' and depo_kodu='${BAR}';`).out === 'true',
      '3 rezervasyonsuz kalemde davranis ayni, tarih yazildi');

    // A1 doneminde bir tuketim kaydi olustur, sonra geri al.
    const s = O.kimlikle(BAR810, `select public.bar_siparis_olustur('810','${BAR}','M2',null,
      '[{"menu_urun_id":"22222222-0000-0000-0000-000000000003","adet":1},{"menu_urun_id":"22222222-0000-0000-0000-000000000001","adet":1}]'::jsonb);`).out;
    O.kimlikle(BAR810, `select public.bar_siparis_durum_guncelle('${s}','hazirlaniyor');
                        select public.bar_siparis_durum_guncelle('${s}','hazir');
                        select public.bar_siparis_teslim_et('${s}');`);
    const tuketimOnce = O.sql(`select count(*) from public.bar_stok_tuketimleri;`).out;

    const g = O.uygulaTekIslem(GERI);
    sonuc(g.ok, '4a geri alma dosyasi tek islemde uygulandi', g.ok ? '' : g.err.slice(-400));
    const govde = O.sql(`select bool_and(prosrc ~* 'guncelleme_tarihi\\s*=\\s*now\\(\\)')::text from pg_proc
                          where pronamespace='public'::regnamespace and proname in ('stok_ekle','stok_transfer');`).out;
    const md5 = O.sql(`select string_agg(md5(prosrc), ',' order by proname) from pg_proc
                        where pronamespace='public'::regnamespace and proname in ('stok_ekle','stok_transfer');`).out;
    sonuc(govde === 'true' && md5 === '43ec3cfcd28b9a8cb9e5d8b3ed03b47d,8dd27c19ac2da9629a53dae9861766ba',
      '4b geri alma sonrasi stok govdeleri A1-ONCESI uretim haliyle BIREBIR ayni (md5) ve tarih duzeltmesini tasiyor', md5);
    const t2 = tarihSeti(O);
    sonuc(t2.ekle.ok && t2.ekle.bar === 'true' && t2.transfer.bar === 'true' && t2.transfer.merkez === 'true',
      '4c geri alma sonrasi tarih duzeltmesi DAVRANIS olarak calisiyor (ekle + transferin iki bacagi)');
    const kalan = O.sql(`select count(*) from pg_proc where pronamespace='public'::regnamespace and proname in
      ('stok_cikis_korumasi','_stok_kilitle','bar_siparis_oda_dogrula','stok_sayim_onayla','bar_masa_yetki_kapsami');`).out;
    const eski = O.sql(`select (to_regprocedure('public.bar_siparis_teslim_et(uuid)') is not null
                           and to_regprocedure('public.bar_siparis_iptal(uuid)') is not null)::text;`).out;
    sonuc(kalan === '0' && eski === 'true', '4d A1 fonksiyonlari kalkti, eski teslim/iptal imzalari geri geldi');
    sonuc(O.sql(`select count(*) from public.bar_stok_tuketimleri;`).out === tuketimOnce && tuketimOnce !== '0',
      '4e A1 doneminde yazilan tuketim kayitlari KORUNDU', 'kayit ' + tuketimOnce);
    const eskiSip = O.kimlikle(BAR810, `select public.bar_siparis_olustur('810','${BAR}','M3',null,
      '[{"menu_urun_id":"22222222-0000-0000-0000-000000000001","adet":1}]'::jsonb);`);
    sonuc(eskiSip.ok, '4f eski bar_siparis_olustur geri alma sonrasi calisiyor', eskiSip.ok ? '' : eskiSip.err.slice(-200));
  } catch (e) {
    sonuc(false, 'beklenmeyen hata (ana)', e.stack || e.message);
  } finally { O.temizle(); }

  // ---------------- N1: tarih satirlari silinmis A1 ----------------
  const N1 = barOrtami({ ad: 'bar-sira-n1' });
  try {
    await N1.kur();
    const bozuk = a1Metin
      .replace(/do update set miktar = greatest\(0, stok\.miktar \+ p_delta\),\s*\r?\n\s*guncelleme_tarihi = now\(\)/,
               'do update set miktar = greatest(0, stok.miktar + p_delta)')
      .replace(/update stok set miktar = greatest\(0, miktar - p_miktar\),\s*\r?\n\s*guncelleme_tarihi = now\(\)/,
               'update stok set miktar = greatest(0, miktar - p_miktar)')
      .replace(/do update set miktar = greatest\(0, stok\.miktar \+ p_miktar\),\s*\r?\n\s*guncelleme_tarihi = now\(\);/,
               'do update set miktar = greatest(0, stok.miktar + p_miktar);')
      // Son kosul da tarihi arar; negatif kontrolde onun yerine DAVRANIS olculur.
      .replace("raise exception 'SON KOSUL: stok yazan fonksiyonlardan biri guncelleme_tarihi yazmiyor.';", 'null;');
    const u = N1.uygulaTekIslem(bozuk, { metin: true });
    const t = tarihSeti(N1);
    sonuc(u.ok && t.ekle.bar === 'false' && t.transfer.bar === 'false',
      'N1 NEGATIF KONTROL: A1 tarih satirlari silininca tarih yazilmiyor ve test bunu goruyor', u.ok ? '' : u.err.slice(-200));
  } catch (e) { sonuc(false, 'beklenmeyen hata (N1)', e.stack || e.message); } finally { N1.temizle(); }

  // ---------------- N2: tarih duzeltmesi olmayan taban ----------------
  const N2 = barOrtami({ ad: 'bar-sira-n2' });
  try {
    await N2.kur({ uretimSonrasi: false, onceki: ['docs/kurulum/2026-09-14-stok-liste-ozet.sql'] });
    const u = N2.uygulaTekIslem(A1);
    const yok = N2.sql(`select count(*) from pg_proc where proname = 'stok_cikis_korumasi';`).out;
    sonuc(!u.ok && /ONKOSUL/.test(u.err) && yok === '0',
      'N2 NEGATIF KONTROL: tarih duzeltmesi olmayan tabanda A1 onkosulda DURDU, hicbir sey kalmadi',
      (u.err.match(/ONKOSUL:[^\n]*/) || [''])[0].slice(0, 110));
  } catch (e) { sonuc(false, 'beklenmeyen hata (N2)', e.stack || e.message); } finally { N2.temizle(); }

  // ---------------- N3: geri alma stok govdelerini eski dokumden alirsa ----------------
  const N3 = barOrtami({ ad: 'bar-sira-n3' });
  try {
    await N3.kur();
    N3.uygulaTekIslem(A1);
    const geri = readFileSync(kok + GERI, 'utf8');
    const dokumGovdeleri = dokumFonksiyonu('stok_ekle') + '\n\n' + dokumFonksiyonu('stok_transfer');
    // Isaretler arasi, konumla (regex kacisi yok) dokumdeki DUZELTMESIZ govdelerle degistirilir.
    const bas = geri.indexOf('-- <<STOK_GOVDELERI>>');
    const bitIsaret = '-- <</STOK_GOVDELERI>>';
    const bit = geri.indexOf(bitIsaret);
    const bozuk = (bas < 0 || bit < 0 ? geri
      : geri.slice(0, bas) + '-- <<STOK_GOVDELERI>>\n' + dokumGovdeleri + '\n' + geri.slice(bit))
      .replace("raise exception 'SON KOSUL: geri alma tarih duzeltmesini kaybettirdi.';", 'null;');
    // Degisim GERCEKTEN yapilmali; yapilmazsa negatif kontrol bos gecerdi.
    if (bozuk === geri || !bozuk.includes(dokumGovdeleri.slice(0, 60))) throw new Error('N3 bozma kurulamadi');
    const g = N3.uygulaTekIslem(bozuk, { metin: true });
    const t = tarihSeti(N3);
    sonuc(g.ok && t.ekle.bar === 'false',
      'N3 NEGATIF KONTROL: geri alma duzeltmesiz govdeleri yazinca tarih kayboluyor ve test bunu goruyor', g.ok ? '' : g.err.slice(-200));
  } catch (e) { sonuc(false, 'beklenmeyen hata (N3)', e.stack || e.message); } finally { N3.temizle(); }
}

await main();
console.log(`\nSIRA VE GERI ALMA: ${ok} OK / ${fail} FAIL`);
process.exitCode = fail ? 1 : 0;
