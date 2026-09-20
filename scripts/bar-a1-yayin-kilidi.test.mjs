// ===========================================================================
// YAYIN PENCERESI — SUNUCU TARAFI YAZMA DURAKLATMASI (izole; uretime BAGLANMAZ)
// ===========================================================================
// Olculen (kullanici talebi 2026-09-20): hareketsizlik sorgusu yardimci kanittir;
// yazmanin durdugunu SUNUCU garanti etmelidir.
//   D1  Duraklatmadan ONCE: istemci stok yazabiliyor (taban).
//   D2  Duraklatma: rpc/stok_ekle, rpc/stok_transfer, stok_hareketleri INSERT ve
//       dogrudan stok INSERT/UPDATE authenticated icin KAPALI; okuma acik.
//   D3  Duraklatma SIRASINDA bar siparis akisi (SECURITY DEFINER) calisir —
//       yani duraklatma bar operasyonunu durdurmaz (kapsam siniri).
//   D4  KALAN RISK olcumu: duraklatma, o an surmekte olan cok satirli islemin
//       ORTASINDA gelirse islemi KESER (yarim kalir). Bu testte gosterilir.
//   D5  Migration duraklatma altinda uygulanir (yazma kapaliyken).
//   D6  Surdur dosyasi: yetkiler geri acilir; YENI istemci yazabilir, ESKI
//       istemci (4 parametre) A1 nedeniyle yine yazamaz.
// ===========================================================================
import { barOrtami } from './bar-test-ortam.mjs';
import { K, BAR, M, EK_TOHUM, a1Yardimcilari } from './bar-a1-tohum.mjs';

const A1 = 'docs/kurulum/2026-09-18-bar-a1-guvenlik.sql';
const DURAKLAT = 'docs/kurulum/2026-09-20-yayin-yazma-duraklat.sql';
const SURDUR = 'docs/kurulum/2026-09-20-yayin-yazma-surdur.sql';
const O = barOrtami({ ad: 'bar-a1-kilit' });
const { q, siparis, hazirla, tek, stok } = a1Yardimcilari(O);
let ok = 0, fail = 0;
const sonuc = (g, ad, ek) => { console.log((g ? 'OK   ' : 'FAIL ') + ad + (ek ? ' — ' + ek : '')); if (g) ok++; else fail++; };
const hata = (r) => (r.err || '').split('\n')[0].slice(0, 90);

try {
  await O.kur();
  const t = O.sql(EK_TOHUM); if (!t.ok) throw new Error('ek tohum: ' + t.err.slice(-200));

  // D1 — taban: A1 ONCESI istemci yazabiliyor
  const d1 = q(K.DEPO810, `select public.stok_ekle('LIMON','${BAR}','810',1);`);
  sonuc(d1.ok && stok('LIMON') === '51.000', 'D1 duraklatmadan once istemci stok yazabiliyor (taban)', 'stok ' + stok('LIMON'));

  // D2 — duraklatma
  const dur = O.uygulaTekIslem(DURAKLAT);
  const d2ekle = q(K.DEPO810, `select public.stok_ekle('LIMON','${BAR}','810',1);`);
  const d2tr = q(K.DEPO810, `select public.stok_transfer('LIMON','${BAR}','810_100','810',1);`);
  const d2har = q(K.DEPO810, `insert into public.stok_hareketleri (urun_kodu, depo_kodu, otel_id, tip, miktar, aciklama)
                               values ('LIMON','${BAR}','810','giris',1,'Mal kabul');`);
  const d2stok = q(K.DEPO810, `update public.stok set miktar = miktar + 1 where urun_kodu='LIMON' and depo_kodu='${BAR}';`);
  const d2oku = q(K.DEPO810, `select count(*) from public.stok where depo_kodu='${BAR}';`);
  sonuc(dur.ok && !d2ekle.ok && !d2tr.ok && !d2har.ok && !d2stok.ok && d2oku.ok && stok('LIMON') === '51.000',
    'D2 duraklatma: stok_ekle / stok_transfer / hareket INSERT / dogrudan stok yazma KAPALI, okuma ACIK, stok degismedi',
    dur.ok ? hata(d2ekle) : dur.err.slice(-160));

  // D3 — bar siparis akisi (SECURITY DEFINER) duraklatmadan etkilenmez
  const s3 = siparis(K.BAR810, [{ menu_urun_id: M.BIRA, adet: 1 }]);
  const h3 = hazirla(s3.out);
  const t3 = q(K.BAR810, `select public.bar_siparis_teslim_et('${s3.out}');`);
  sonuc(s3.ok && h3.ok && t3.ok && stok('BIRA') === '9.000',
    'D3 duraklatma sirasinda bar siparisi ve teslimi CALISIR (sunucu fonksiyonu yazar) — kapsam siniri', 'stok ' + stok('BIRA'));

  // D4 — KALAN RISK: surmekte olan cok satirli islem kesilir
  // Istemci iki satirli bir islemin ilk satirini duraklatmadan ONCE yazmis olsun:
  // (duraklatma oncesi D1 bunu temsil eder). Ikinci satir duraklatmadan sonra gelir:
  sonuc(!q(K.DEPO810, `select public.stok_ekle('VISKI','${BAR}','810',1);`).ok,
    'D4 KALAN RISK: duraklatma, suren cok satirli islemin sonraki satirini KESER (yarim kalir) — sunucu islemi tamamlayamaz');

  // D5 — migration duraklatma altinda uygulanir
  const mig = O.uygulaTekIslem(A1);
  sonuc(mig.ok, 'D5 A1 migration yazma duraklatilmisken uygulandi', mig.ok ? '' : mig.err.slice(-200));

  // D6 — surdur
  const sur = O.uygulaTekIslem(SURDUR);
  const yeni = q(K.DEPO810, `select public.stok_ekle('LIMON','${BAR}','810',1,1);`);
  const eski = q(K.DEPO810, `select public.stok_ekle('LIMON','${BAR}','810',1);`);
  const har = q(K.DEPO810, `insert into public.stok_hareketleri (urun_kodu, depo_kodu, otel_id, tip, miktar, aciklama)
                             values ('LIMON','${BAR}','810','giris',1,'Mal kabul');`);
  sonuc(sur.ok && yeni.ok && stok('LIMON') === '52.000' && !eski.ok && /ESKI_ISTEMCI/.test(eski.err) && har.ok,
    'D6 surdur: YENI istemci yazar, hareket yazilir; ESKI istemci (4 parametre) A1 nedeniyle yine yazamaz',
    sur.ok ? 'stok ' + stok('LIMON') + ' | eski: ' + hata(eski) : sur.err.slice(-160));

  const iz = tek(`select string_agg(entity_id, ',' order by entity_id) from public.erp_islem_audit
                   where entity_id like 'A1-YAYIN-%';`);
  sonuc(iz === 'A1-YAYIN-DURAKLATMA,A1-YAYIN-SURDURME',
    'D7 duraklatma ve surdurme denetim izine islendi (yayin penceresi gorunur)', iz);
} catch (e) {
  sonuc(false, 'beklenmeyen hata', e.stack || e.message);
} finally { O.temizle(); }

console.log(`\nYAYIN YAZMA DURAKLATMA: ${ok} OK / ${fail} FAIL`);
process.exit(fail ? 1 : 0);
