// ===========================================================================
// PMS REZERVASYON + MISAFIR EKRANLARI (uretime BAGLANMAZ)
// ===========================================================================
// pms-misafirler.html ve pms-rezervasyonlar.html icindeki GERCEK betikler,
// gercek PostgREST uzerinden izole veritabanina konusur. Olculen: resepsiyonun
// bu iki ekrandan yapabildigi is ve ekranin sunucu redlerini dogru gostermesi.
//
// Yapay veri; gercek misafir verisi YOKTUR. KVKK ayrimi (kimlik belgesinin
// AYRI tabloda tutulmasi) da yapay belge numarasiyla olculur.
//
// Kullanim: node scripts/pms-rezervasyon-misafir.test.mjs
// ===========================================================================
import { barOrtami, yerelJwt } from './bar-test-ortam.mjs';
import { EK_TOHUM } from './bar-a1-tohum.mjs';
import { barEkranKur } from './bar-ekran-harness.mjs';
import { PMS, PMS_TOHUM, RESEPSIYON_YETKI } from './pms-akis-tohum.mjs';

const O = barOrtami({ ad: 'pms-rez-mis', ag: 'pms-rez-mis-net' });
let ok = 0, fail = 0;
const sonuc = (g, ad, ek) => {
  console.log((g ? 'OK   ' : 'FAIL ') + ad + (ek ? ' — ' + ek : ''));
  if (g) ok++; else fail++;
};
const bekle = (ms) => new Promise((r) => setTimeout(r, ms));
const tek = (s) => O.sql(s).out.trim();
let REST;

function ekran(html) {
  return barEkranKur({
    html, restUrl: REST, jwt: yerelJwt('authenticated', PMS.RESEPSIYON.sub),
    kullanici: { id: PMS.RESEPSIYON.sub, ad: 'Resepsiyon 810', rol: 'muhasebe_calisani', otel_id: '810', otelId: '810' },
    yetkiler: RESEPSIYON_YETKI,
  });
}
async function hazirOl(e, ifade) {
  for (let i = 0; i < 120 && !e.calistir(ifade); i++) await bekle(50);
}
// Ekran alanlarini doldurmak: harness'in sahte elemanlarina deger yazar.
const yaz = (e, alan, deger) => { e.el(alan).value = deger; };

try {
  await O.kur();
  const t1 = O.sql(EK_TOHUM); if (!t1.ok) throw new Error('A1 tohum: ' + t1.err.slice(-300));
  const t2 = O.sql(PMS_TOHUM); if (!t2.ok) throw new Error('PMS tohum: ' + t2.err.slice(-400));
  REST = await O.restBaslat({ port: 3094 });
  console.log('ortam hazir — ' + REST + ' (izole veritabani, uretim YOK)\n');

  // =====================================================================
  console.log('--- MISAFIR EKRANI ---');
  let e = ekran('pms-misafirler.html');
  await hazirOl(e, 'MISAFIRLER.length');
  sonuc(e.calistir('MISAFIRLER.length') >= 3, 'M1 misafir listesi sunucudan okundu',
    'misafir=' + e.calistir('MISAFIRLER.length'));

  // M2 — zorunlu alan dogrulamasi: ad/soyad bos ise SUNUCUYA GIDILMEZ.
  e.calistir('yeniAc()');
  yaz(e, 'fAd', ''); yaz(e, 'fSoyad', ''); yaz(e, 'fOtel', '810');
  const oncekiIstek = e.kayit.istekler.length;
  await e.calistir('kaydet()');
  sonuc(e.kayit.istekler.length === oncekiIstek && /ad ve soyad zorunlu/i.test(e.sonToast()),
    'M2 ad/soyad bos: ekran sunucuya GITMEDI ve uyardi', e.sonToast());

  // M3 — gecersiz e-posta da erken yakalanir.
  yaz(e, 'fAd', 'Deneme'); yaz(e, 'fSoyad', 'Misafir'); yaz(e, 'fEposta', 'gecersiz');
  const oncekiIstek2 = e.kayit.istekler.length;
  await e.calistir('kaydet()');
  sonuc(e.kayit.istekler.length === oncekiIstek2 && /e-posta/i.test(e.sonToast()),
    'M3 gecersiz e-posta: ekran sunucuya GITMEDI ve uyardi', e.sonToast());

  // M4 — gecerli kayit gercekten yazilir.
  yaz(e, 'fEposta', ''); yaz(e, 'fTelefon', '5550000000'); yaz(e, 'fUyruk', 'TR');
  await e.calistir('kaydet()');
  await bekle(400);
  const yeniId = tek(`select id::text from public.pms_misafirler
                      where ad='Deneme' and soyad='Misafir' and otel_id='810';`);
  sonuc(!!yeniId, 'M4 ekrandan yeni misafir kaydedildi', yeniId ? yeniId.slice(0, 8) : e.sonToast());

  // M5 — KVKK: kimlik belgesi AYRI tabloya yazilir, misafir satirina degil.
  if (yeniId) {
    await e.calistir('yukle()');
    await bekle(300);
    e.calistir(`duzenleAc('${yeniId}')`);
    yaz(e, 'kTip', 'tc_kimlik'); yaz(e, 'kNo', '12345678901');
    const onceKimlik = e.kayit.istekler.length;
    await e.calistir('kimlikEkle()');
    await bekle(400);
    const kimlikSayisi = tek(`select count(*)::text from public.pms_misafir_kimlik where misafir_id='${yeniId}';`);
    sonuc(kimlikSayisi === '1', 'M5 kimlik belgesi AYRI tabloya yazildi (KVKK ayrimi)',
      'kimlik=' + kimlikSayisi + ' toast=' + e.sonToast());

    // M6 — gecersiz TC ekranda yakalanir, sunucuya gidilmez.
    yaz(e, 'kNo', '01234567890');
    const onceIstek3 = e.kayit.istekler.length;
    await e.calistir('kimlikEkle()');
    sonuc(e.kayit.istekler.length === onceIstek3 && /TC kimlik/i.test(e.sonToast()),
      'M6 gecersiz TC kimlik: ekran sunucuya GITMEDI', e.sonToast());
    void onceKimlik;
  } else {
    sonuc(false, 'M5-M6 OLCULEMEDI: misafir kaydedilemedigi icin kimlik denenemedi');
  }

  // =====================================================================
  console.log('\n--- REZERVASYON EKRANI ---');
  let r = ekran('pms-rezervasyonlar.html');
  await hazirOl(r, 'REZ.length');
  sonuc(r.calistir('REZ.length') >= 2 && r.calistir('TIPLER.length') >= 1,
    'R1 rezervasyon ekrani rezervasyon ve oda tiplerini okudu',
    'REZ=' + r.calistir('REZ.length') + ' TIP=' + r.calistir('TIPLER.length'));

  const bugun = tek('select current_date::text;');
  const yarin = tek('select (current_date + 1)::text;');
  const misafirId = yeniId || PMS.MIS202;

  // R2 — ekrandan TASLAK rezervasyon; gecelik fiyat da yazilmali.
  r.calistir('yeniAc()');
  yaz(r, 'fOtel', '810'); yaz(r, 'mMisafir', misafirId); yaz(r, 'mTip', PMS.TIP);
  yaz(r, 'mGiris', bugun); yaz(r, 'mCikis', yarin); yaz(r, 'mDurum', 'taslak');
  yaz(r, 'mYetiskin', '2'); yaz(r, 'mCocuk', '0'); yaz(r, 'mFiyat', '1750');
  await r.calistir('kaydet()');
  await bekle(500);
  const rezId = tek(`select id::text from public.pms_rezervasyonlar
                     where misafir_id='${misafirId}' and giris_tarihi=current_date
                       and cikis_tarihi=current_date+1 order by olusturma_tarihi desc limit 1;`);
  const fiyat = rezId ? tek(`select gecelik_fiyat::text from public.pms_rezervasyonlar where id='${rezId}';`) : '';
  sonuc(!!rezId && fiyat === '1750.00', 'R2 ekrandan taslak rezervasyon olusturuldu (gecelik fiyat dahil)',
    rezId ? 'fiyat=' + fiyat : 'toast=' + r.sonToast());

  if (rezId) {
    // R3 — onaya cekince folyo OTOMATIK acilmali (urun yolu; tetikleyici).
    await r.calistir('yukle()');
    await bekle(300);
    r.calistir(`duzenleAc('${rezId}')`);
    yaz(r, 'mDurum', 'onaylandi');
    await r.calistir('kaydet()');
    await bekle(500);
    const folyo = tek(`select count(*)::text from public.pms_folyolar where rezervasyon_id='${rezId}';`);
    sonuc(tek(`select durum from public.pms_rezervasyonlar where id='${rezId}';`) === 'onaylandi' && folyo === '1',
      'R3 ekrandan onaylandi + folyo OTOMATIK acildi', 'folyo=' + folyo);

    // R4 — ekrandan oda atamasi.
    await r.calistir('yukle()');
    await bekle(300);
    r.calistir(`duzenleAc('${rezId}')`);
    yaz(r, 'aOda', PMS.ODA203);
    await r.calistir('atamaEkle()');
    await bekle(500);
    const atama = tek(`select count(*)::text from public.pms_oda_atamalari
                       where rezervasyon_id='${rezId}' and oda_id='${PMS.ODA203}' and aktif;`);
    sonuc(atama === '1', 'R4 ekrandan oda atandi', 'atama=' + atama + ' toast=' + r.sonToast());

    // R5 — CAKISMA: ayni odaya, cakisan tarihlerle ikinci rezervasyon atanamaz.
    //      Sunucu reddini EKRAN gostermeli (sessizce yutmamali).
    r.calistir('yeniAc()');
    yaz(r, 'fOtel', '810'); yaz(r, 'mMisafir', PMS.MIS201); yaz(r, 'mTip', PMS.TIP);
    yaz(r, 'mGiris', bugun); yaz(r, 'mCikis', yarin); yaz(r, 'mDurum', 'onaylandi');
    yaz(r, 'mYetiskin', '1'); yaz(r, 'mCocuk', '0'); yaz(r, 'mFiyat', '900');
    await r.calistir('kaydet()');
    await bekle(500);
    const ikinciId = tek(`select id::text from public.pms_rezervasyonlar
                          where misafir_id='${PMS.MIS201}' and gecelik_fiyat=900 order by olusturma_tarihi desc limit 1;`);
    if (ikinciId) {
      await r.calistir('yukle()');
      await bekle(300);
      r.calistir(`duzenleAc('${ikinciId}')`);
      yaz(r, 'aOda', PMS.ODA203);
      const onceHata = r.yazmaHatalari().length;
      await r.calistir('atamaEkle()');
      await bekle(500);
      const cakisan = tek(`select count(*)::text from public.pms_oda_atamalari
                           where rezervasyon_id='${ikinciId}' and oda_id='${PMS.ODA203}' and aktif;`);
      // Kullanicinin GORDUGU hata: ortak.js'in kirmizi yazma hatasi seridi.
      const seritler = r.yazmaHatalari();
      const gosterildi = seritler.length > onceHata && /KAYDEDİLEMEDİ/.test(seritler.join(' '));
      sonuc(cakisan === '0' && gosterildi,
        'R5 CAKISAN oda atamasi reddedildi ve ekran bunu KULLANICIYA gosterdi',
        'atama=' + cakisan + ' serit=' + (seritler.slice(-1)[0] || '(yok)').slice(0, 90));
    } else {
      sonuc(false, 'R5 OLCULEMEDI: ikinci rezervasyon olusturulamadi');
    }

    // R6 — atama kaldirma ekrandan.
    await r.calistir('yukle()');
    await bekle(300);
    r.calistir(`duzenleAc('${rezId}')`);
    const atamaId = tek(`select id::text from public.pms_oda_atamalari
                         where rezervasyon_id='${rezId}' and aktif limit 1;`);
    if (atamaId) {
      r.confirmVer(true);
      await r.calistir(`atamaKaldir('${atamaId}')`);
      await bekle(500);
      const kalan = tek(`select count(*)::text from public.pms_oda_atamalari
                         where rezervasyon_id='${rezId}' and aktif;`);
      sonuc(kalan === '0', 'R6 ekrandan oda atamasi kaldirildi', 'kalan aktif atama=' + kalan);
    } else {
      sonuc(false, 'R6 OLCULEMEDI: kaldirilacak atama bulunamadi');
    }
  } else {
    sonuc(false, 'R3-R6 OLCULEMEDI: rezervasyon olusturulamadi');
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
