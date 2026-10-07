// ===========================================================================
// PMS ON BURO AKIS TESTLERI — EKRAN + SUNUCU (uretime BAGLANMAZ)
// ===========================================================================
// pms-oda-plani.html icindeki GERCEK betik, gercek PostgREST uzerinden izole
// bir veritabanina konusur. Olculen: resepsiyonistin ekrandan yapabildigi is.
//
// Kapsanan akis parcasi:
//   oda musaitligi -> (rezervasyon + atama zaten var) -> CHECK-IN -> oda dolu
//
// KAPSAM DISI (bu dosya iddia ETMEZ): uretim davranisi, tarayici render'i,
// gercek misafir verisi. Yerel gecis canli kabul yerine GECMEZ.
//
// Kullanim: node scripts/pms-akis-ekran.test.mjs
// ===========================================================================
import fs from 'node:fs';
import { barOrtami, kok, yerelJwt } from './bar-test-ortam.mjs';
import { EK_TOHUM } from './bar-a1-tohum.mjs';
import { barEkranKur } from './bar-ekran-harness.mjs';
import { PMS, PMS_TOHUM, RESEPSIYON_YETKI } from './pms-akis-tohum.mjs';

const O = barOrtami({ ad: 'pms-akis', ag: 'pms-akis-net' });
let ok = 0, fail = 0;
const sonuc = (g, ad, ek) => {
  console.log((g ? 'OK   ' : 'FAIL ') + ad + (ek ? ' — ' + ek : ''));
  if (g) ok++; else fail++;
};
const bekle = (ms) => new Promise((r) => setTimeout(r, ms));
const reddetmeler = [];
process.on('unhandledRejection', (e) => { reddetmeler.push(String(e && e.message || e)); });

const tek = (s) => O.sql(s).out.trim();
let REST;

function ekran(kimlik = PMS.RESEPSIYON, yetkiler = RESEPSIYON_YETKI) {
  return barEkranKur({
    html: 'pms-oda-plani.html',
    restUrl: REST,
    jwt: yerelJwt('authenticated', kimlik.sub),
    kullanici: { id: kimlik.sub, ad: 'Resepsiyon 810', rol: 'muhasebe_calisani', otel_id: '810', otelId: '810' },
    yetkiler,
  });
}
async function hazirOl(e) {
  for (let i = 0; i < 100 && !e.calistir('ODALAR.length'); i++) await bekle(50);
}

try {
  await O.kur();
  const t1 = O.sql(EK_TOHUM);
  if (!t1.ok) throw new Error('A1 ek tohum: ' + t1.err.slice(-300));
  const t2 = O.sql(PMS_TOHUM);
  if (!t2.ok) throw new Error('PMS tohum: ' + t2.err.slice(-400));
  REST = await O.restBaslat({ port: 3099 });
  console.log('ortam hazir — ' + REST + ' (izole veritabani, uretim YOK)\n');

  // -----------------------------------------------------------------------
  // TOHUM DOGRULAMASI — testin dayandigi durum gercekten kuruldu mu?
  // -----------------------------------------------------------------------
  sonuc(tek(`select kullanim_durumu||'/'||temizlik_durumu from public.pms_odalar where id='${PMS.ODA201}';`) === 'bos/temiz',
    'T0 oda 201 bos ve temiz (check-in alabilir)');
  sonuc(tek(`select count(*)::text from public.pms_oda_atamalari where rezervasyon_id='${PMS.REZ_ATANMIS}' and aktif;`) === '1',
    'T1 atanmis rezervasyonun AKTIF oda atamasi var');
  sonuc(tek(`select count(*)::text from public.pms_oda_atamalari where rezervasyon_id='${PMS.REZ_ATAMASIZ}' and aktif;`) === '0',
    'T2 atamasiz rezervasyonun atamasi yok');

  // -----------------------------------------------------------------------
  // A — EKRANDAN CHECK-IN
  // -----------------------------------------------------------------------
  let e = ekran();
  await hazirOl(e);
  sonuc(e.calistir(`REZ.length >= 2 && ATAMALAR.length >= 1`),
    'A0 ekran rezervasyonlari ve atamalari sunucudan okudu',
    'REZ=' + e.calistir('REZ.length') + ' ATAMA=' + e.calistir('ATAMALAR.length'));

  // A1 — ATAMASIZ rezervasyon: bugunku davranis, korunmali (regresyon kalkani)
  const oda202 = e.calistir(`JSON.stringify(uygunRezervasyonlar(ODALAR.find(o=>o.id==='${PMS.ODA202}')).map(r=>r.id))`);
  sonuc(JSON.parse(oda202).includes(PMS.REZ_ATAMASIZ),
    'A1 atamasiz rezervasyon bos odanin check-in listesinde', oda202);

  // A2 — ATANMIS rezervasyon: ATANDIGI odanin listesinde GORUNMELI.
  // Sunucu (pms_check_in) atamayi zaten kabul ediyor: atama varsa odayi ondan
  // alir, ayni oda verilirse sorun cikarmaz. Ekran bunu gizlerse "once ata,
  // sonra giris yap" yolu CIKMAZ olur (09-25 bulgusu).
  const oda201 = e.calistir(`JSON.stringify(uygunRezervasyonlar(ODALAR.find(o=>o.id==='${PMS.ODA201}')).map(r=>r.id))`);
  sonuc(JSON.parse(oda201).includes(PMS.REZ_ATANMIS),
    'A2 ATANMIS rezervasyon, atandigi odanin check-in listesinde', oda201);

  // A3 — Yanlis oda eslesmesi: atanmis rezervasyon BASKA odanin listesinde OLMAMALI.
  sonuc(!JSON.parse(oda202).includes(PMS.REZ_ATANMIS),
    'A3 atanmis rezervasyon BASKA odanin listesinde YOK (yanlis oda korumasi)', oda202);

  // A4 — Ekrandan gercek check-in. Tiklama YALNIZ modalin SUNDUGU kimlikle
  // yapilir; kullanicinin ekranda goremedigi bir rezervasyona giris yapmasi
  // mumkun olmadigi icin test de kestirme YAPMAZ (aksi halde ekran kusuru
  // sunucunun hosgorusuyle yesile boyanir).
  e.calistir(`girisAc('${PMS.ODA201}')`);
  const sunulan = [...e.el('girisListe').innerHTML.matchAll(/checkInYap\('([0-9a-f-]+)'\)/g)].map((m) => m[1]);
  sonuc(sunulan.includes(PMS.REZ_ATANMIS),
    'A4 oda 201 check-in modali ATANMIS rezervasyonu sunuyor',
    'sunulan=' + JSON.stringify(sunulan) + (sunulan.length ? '' : ' toast=' + e.sonToast()));

  if (sunulan.includes(PMS.REZ_ATANMIS)) {
    await e.calistir(`checkInYap('${PMS.REZ_ATANMIS}')`);
    await bekle(400);
    sonuc(tek(`select durum from public.pms_rezervasyonlar where id='${PMS.REZ_ATANMIS}';`) === 'giris_yapildi',
      'A5 ekrandan check-in sonrasi rezervasyon giris_yapildi', e.sonToast());
    sonuc(tek(`select kullanim_durumu from public.pms_odalar where id='${PMS.ODA201}';`) === 'dolu',
      'A6 check-in sonrasi oda 201 dolu');
    sonuc(tek(`select count(*)::text from public.pms_oda_atamalari where rezervasyon_id='${PMS.REZ_ATANMIS}' and aktif;`) === '1',
      'A7 atama COGALMADI (mukerrer atama yok)');

    // A8 — MUKERRER ISLEM: ayni rezervasyona ikinci check-in sunucuda reddedilir.
    const ikinci = O.kimlikle(PMS.RESEPSIYON,
      `select public.pms_check_in('${PMS.REZ_ATANMIS}','${PMS.ODA201}');`);
    sonuc(!ikinci.ok && /giris_yapildi|yalniz onaylandi/i.test(ikinci.err),
      'A8 ikinci check-in reddedildi (mukerrer islem korumasi)',
      ikinci.ok ? 'KABUL EDILDI' : (ikinci.err.split('\n').find((x) => /ERROR/.test(x)) || ''));
  } else {
    sonuc(false, 'A5-A8 OLCULEMEDI: ekran check-in yolunu sunmadigi icin akis yurutulemedi');
  }
  // --------------------------------------------------------------------
  // A9 — EKRANIN KENDI ACIKLAMASI KURALLA AYNI SEYI SOYLEMELI.
  // Bu kusur gercek tarayicida goruldu: kural degistikten sonra modaldaki
  // yardim metni hala "odasi atanmamis" diyordu, yani ekran kullaniciya
  // artik uygulamadigi bir kurali anlatiyordu.
  const sayfa = fs.readFileSync(kok + 'pms-oda-plani.html', 'utf8');
  const yardim = (sayfa.match(/Liste: aynı otelde[\s\S]{0,400}?<\/div>/) || [''])[0];
  sonuc(yardim.length > 0 && !/odası atanmamış ve/.test(yardim)
    && /bu odaya atanmış/.test(yardim),
    'A9 check-in modalindaki aciklama YENI kurali anlatiyor (eski metin kalmadi)',
    yardim ? yardim.replace(/\s+/g, ' ').slice(0, 110) : 'yardim metni bulunamadi');
} catch (e) {
  console.log('\nKURULUM/KOSUM HATASI: ' + (e && e.message || e));
  fail++;
} finally {
  O.temizle();
}

if (reddetmeler.length) console.log('\nyakalanmamis reddetme: ' + reddetmeler.join(' | '));
console.log('\n======================================================================');
console.log(`SONUC: ${ok} gecti, ${fail} kaldi`);
console.log('======================================================================');
process.exit(fail ? 1 : 0);
