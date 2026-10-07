// ===========================================================================
// PMS HATA DURUMLARI — yapay verilerle (uretime BAGLANMAZ)
// ===========================================================================
// Kullanicinin saydigi dort hata sinifi, urunun kendi yollarindan denenir:
//   1) cifte rezervasyon (ayni odaya cakisan konaklama)
//   2) mukerrer islem (ayni isin iki kez yazilmasi)
//   3) yanlis oda / yanlis misafir eslesmesi
//   4) bakiye tutarsizligi (kapali folyo, sifir tutar, eksik odeme)
//
// Her olcum bir REDDIN gerceklestigini gosterir. Bir kural sunucuda degil de
// yalnizca ekranda duruyorsa, bu testte GORUNUR: dogrudan REST cagrisi ekrani
// atlar. Yerel gecis CANLI KABUL YERINE GECMEZ.
//
// Kullanim: node scripts/pms-hata-durumlari.test.mjs
// ===========================================================================
import { barOrtami, yerelJwt } from './bar-test-ortam.mjs';
import { EK_TOHUM } from './bar-a1-tohum.mjs';
import { barEkranKur } from './bar-ekran-harness.mjs';
import { PMS, PMS_TOHUM, RESEPSIYON_YETKI } from './pms-akis-tohum.mjs';

const O = barOrtami({ ad: 'pms-hata', ag: 'pms-hata-net' });
let ok = 0, fail = 0;
const sonuc = (g, ad, ek) => {
  console.log((g ? 'OK   ' : 'FAIL ') + ad + (ek ? ' — ' + ek : ''));
  if (g) ok++; else fail++;
};
const bekle = (ms) => new Promise((r) => setTimeout(r, ms));
const tek = (s) => O.sql(s).out.trim();
const jwt = () => yerelJwt('authenticated', PMS.RESEPSIYON.sub);
let REST;

async function rest(yol, secenek = {}) {
  const r = await fetch(REST + yol.replace('/rest/v1/', '/'), {
    ...secenek,
    headers: {
      apikey: 'test-anon', Authorization: 'Bearer ' + jwt(),
      'Content-Type': 'application/json', Prefer: 'return=representation',
      ...(secenek.headers || {}),
    },
  });
  return { ok: r.ok, durum: r.status, govde: await r.text() };
}
function ekran() {
  return barEkranKur({
    html: 'pms-oda-plani.html', restUrl: REST, jwt: jwt(),
    kullanici: { id: PMS.RESEPSIYON.sub, ad: 'Resepsiyon 810', rol: 'muhasebe_calisani', otel_id: '810', otelId: '810' },
    yetkiler: RESEPSIYON_YETKI,
  });
}
const kisa = (t) => { try { return JSON.parse(t).message || t.slice(0, 120); } catch { return t.slice(0, 120); } };

try {
  await O.kur();
  const t1 = O.sql(EK_TOHUM); if (!t1.ok) throw new Error('A1 tohum: ' + t1.err.slice(-300));
  const t2 = O.sql(PMS_TOHUM); if (!t2.ok) throw new Error('PMS tohum: ' + t2.err.slice(-400));
  REST = await O.restBaslat({ port: 3096 });
  console.log('ortam hazir — ' + REST + ' (izole veritabani, uretim YOK)\n');

  console.log('--- 1) CIFTE REZERVASYON ---');
  // Oda 201'in bugunu kapsayan AKTIF atamasi var (tohum). Ayni odaya, cakisan
  // tarihlerle ikinci bir atama acilmaya calisiliyor.
  const cakisan = await rest('/rest/v1/pms_oda_atamalari', {
    method: 'POST',
    body: JSON.stringify({
      otel_id: '810', rezervasyon_id: PMS.REZ_ATAMASIZ, oda_id: PMS.ODA201,
      baslangic: tek('select current_date::text;'),
      bitis: tek('select (current_date + 1)::text;'), aktif: true,
    }),
  });
  sonuc(!cakisan.ok, 'H1 ayni odaya CAKISAN ikinci atama reddedildi (cifte rezervasyon)',
    cakisan.ok ? 'KABUL EDILDI' : cakisan.durum + ' ' + kisa(cakisan.govde));

  console.log('\n--- 2) MUKERRER ISLEM ---');
  // Once oda 201'e check-in (atanmis rezervasyon).
  const g1 = await rest('/rest/v1/rpc/pms_check_in', {
    method: 'POST', body: JSON.stringify({ p_rezervasyon_id: PMS.REZ_ATANMIS, p_oda_id: PMS.ODA201 }),
  });
  sonuc(g1.ok, 'H3 atanmis rezervasyon check-in oldu (sonraki olcumlerin on kosulu)',
    g1.ok ? '' : kisa(g1.govde));

  const g2 = await rest('/rest/v1/rpc/pms_check_in', {
    method: 'POST', body: JSON.stringify({ p_rezervasyon_id: PMS.REZ_ATANMIS, p_oda_id: PMS.ODA201 }),
  });
  sonuc(!g2.ok && /yalniz onaylandi/i.test(g2.govde),
    'H4 ayni rezervasyona IKINCI check-in reddedildi (mukerrer islem)',
    g2.ok ? 'KABUL EDILDI' : kisa(g2.govde));

  console.log('\n--- 3) YANLIS ODA / MISAFIR ESLESMESI ---');
  // Dolu odaya baska bir rezervasyonun check-in'i. REZ_ATAMASIZ'in bu anda
  // atamasi YOKTUR; reddin sebebi ODANIN DOLU olmasidir.
  const doluya = await rest('/rest/v1/rpc/pms_check_in', {
    method: 'POST', body: JSON.stringify({ p_rezervasyon_id: PMS.REZ_ATAMASIZ, p_oda_id: PMS.ODA201 }),
  });
  sonuc(!doluya.ok && /bos degil/i.test(doluya.govde),
    'H5 DOLU odaya ikinci misafirin check-in\'i reddedildi', doluya.ok ? 'KABUL EDILDI' : kisa(doluya.govde));

  // Baska bir odaya, kendi rezervasyon tarihleri icinde atama KABUL edilmeli:
  // cakisma kurali fazla genis olmamali.
  const baskaOda = await rest('/rest/v1/pms_oda_atamalari', {
    method: 'POST',
    body: JSON.stringify({
      otel_id: '810', rezervasyon_id: PMS.REZ_ATAMASIZ, oda_id: PMS.ODA202,
      baslangic: tek('select current_date::text;'),
      bitis: tek('select (current_date + 2)::text;'), aktif: true,
    }),
  });
  sonuc(baskaOda.ok, 'H2 baska odaya, kendi tarihlerinde atama KABUL edildi',
    baskaOda.ok ? '' : baskaOda.durum + ' ' + kisa(baskaOda.govde));

  // Atamasi oda 202'de olan rezervasyon, BOS ve TEMIZ oda 203'e check-in
  // edilemez: oda secimini atama belirler.
  const yanlisOda = await rest('/rest/v1/rpc/pms_check_in', {
    method: 'POST', body: JSON.stringify({ p_rezervasyon_id: PMS.REZ_ATAMASIZ, p_oda_id: PMS.ODA203 }),
  });
  sonuc(!yanlisOda.ok && /baska oda atamasi/i.test(yanlisOda.govde),
    'H6 atamasi baska odada olan rezervasyon, BOS baska odaya check-in edemiyor',
    yanlisOda.ok ? 'KABUL EDILDI' : kisa(yanlisOda.govde));

  // Capraz otel: 811 otelinin rezervasyonu, 810 otelinin odasina.
  const capraz = await rest('/rest/v1/rpc/pms_check_in', {
    method: 'POST',
    body: JSON.stringify({ p_rezervasyon_id: '88888888-0000-0000-0000-000000000811', p_oda_id: PMS.ODA203 }),
  });
  sonuc(!capraz.ok, 'H7 BASKA OTELIN rezervasyonu bu otelin odasina check-in edemiyor',
    capraz.ok ? 'KABUL EDILDI' : kisa(capraz.govde));

  // Ekran da ayni kurali gosteriyor mu: dolu oda check-in yolu acmamali.
  const e = ekran();
  for (let i = 0; i < 120 && !e.calistir('ODALAR.length'); i++) await bekle(50);
  e.calistir(`girisAc('${PMS.ODA201}')`);
  sonuc(/check-in alamaz/i.test(e.sonToast()), 'H8 ekran DOLU odaya check-in yolu acmiyor', e.sonToast());
  console.log('\n--- 4) BAKIYE TUTARSIZLIGI ---');
  // Tohum satirlari replica rolunde yazildigi icin folyo tetikleyicisi o anda
  // calismaz. Folyo, urunun kendi yolundan acilir: rezervasyon durumu
  // 'onaylandi' olarak yazildiginda pms_folio_otomatik_ac tetikleyicisi acar.
  await rest('/rest/v1/pms_rezervasyonlar?id=eq.' + PMS.REZ_ATAMASIZ, {
    method: 'PATCH', body: JSON.stringify({ durum: 'onaylandi' }),
  });
  const folio = tek(`select id::text from public.pms_folyolar where rezervasyon_id='${PMS.REZ_ATAMASIZ}';`);
  const folyoSayisi = tek(`select count(*)::text from public.pms_folyolar where rezervasyon_id='${PMS.REZ_ATAMASIZ}';`);
  sonuc(!!folio && folyoSayisi === '1', 'H9 onaylanan rezervasyona TEK folyo acildi',
    folio ? 'folio=' + folio.slice(0, 8) + ' adet=' + folyoSayisi : 'YOK');

  if (folio) {
    // Sifir tutarli tahsilat: veritabani CHECK kurali.
    const sifir = await rest('/rest/v1/pms_folio_odemeler', {
      method: 'POST',
      body: JSON.stringify({ otel_id: '810', folio_id: folio, yontem: 'nakit', tutar: 0,
        islem_anahtari: '99999999-0000-0000-0000-0000000003a1' }),
    });
    sonuc(!sifir.ok, 'H10 SIFIR tutarli tahsilat reddedildi', sifir.ok ? 'KABUL EDILDI' : kisa(sifir.govde));

    // Kapali folyoya yazma: once bakiye sifirken kapat, sonra yazmayi dene.
    const kapat = await rest('/rest/v1/rpc/pms_folio_kapat', { method: 'POST', body: JSON.stringify({ p_folio_id: folio }) });
    sonuc(kapat.ok, 'H11 bakiyesi sifir olan folyo kapandi (on kosul)', kapat.ok ? '' : kisa(kapat.govde));

    const kapaliya = await rest('/rest/v1/pms_folio_odemeler', {
      method: 'POST',
      body: JSON.stringify({ otel_id: '810', folio_id: folio, yontem: 'nakit', tutar: 100,
        islem_anahtari: '99999999-0000-0000-0000-0000000003a2' }),
    });
    sonuc(!kapaliya.ok && /kapali/i.test(kapaliya.govde),
      'H12 KAPALI folyoya tahsilat eklenemiyor', kapaliya.ok ? 'KABUL EDILDI' : kisa(kapaliya.govde));

    const tekrarKapat = await rest('/rest/v1/rpc/pms_folio_kapat', { method: 'POST', body: JSON.stringify({ p_folio_id: folio }) });
    sonuc(!tekrarKapat.ok && /zaten kapali/i.test(tekrarKapat.govde),
      'H13 kapali folyo IKINCI kez kapatilamiyor (mukerrer islem)',
      tekrarKapat.ok ? 'KABUL EDILDI' : kisa(tekrarKapat.govde));
  } else {
    sonuc(false, 'H10-H13 OLCULEMEDI: folyo bulunamadigi icin bakiye kurallari denenemedi');
  }

} catch (e) {
  console.log('\nKURULUM/KOSUM HATASI: ' + (e && e.message || e));
  fail++;
} finally {
  O.temizle();
}

console.log('\n======================================================================');
console.log(`SONUC: ${ok} gecti, ${fail} kaldi`);
console.log('======================================================================');
process.exit(fail ? 1 : 0);
