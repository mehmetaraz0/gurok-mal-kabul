// ===========================================================================
// PMS UCTAN UCA AKIS TESTI (uretime BAGLANMAZ, gercek misafir verisi YOK)
// ===========================================================================
// Olculen zincir — kullanicinin tarif ettigi akisin tamami:
//   oda musaitligi -> rezervasyon -> misafir kaydi -> CHECK-IN ->
//   harcamanin folyoya islenmesi -> odeme/duzeltme -> CHECK-OUT ->
//   odanin yeniden satisa hazir olmasi
//
// Her adim MUMKUN OLDUGUNCA urunun kendi yolundan yurutulur: ekran betigi
// (pms-oda-plani.html / pms-folio.html) veya urunun RPC'si. Adim urunde yoksa
// test onu "EKSIK" diye raporlar — yerine gecici bir cozum YAZILMAZ.
//
// Bu dosya yerel kanittir; CANLI KABUL YERINE GECMEZ.
// Kullanim: node scripts/pms-uctan-uca.test.mjs
// ===========================================================================
import { barOrtami, yerelJwt } from './bar-test-ortam.mjs';
import { EK_TOHUM } from './bar-a1-tohum.mjs';
import { barEkranKur } from './bar-ekran-harness.mjs';
import { PMS, PMS_TOHUM, RESEPSIYON_YETKI } from './pms-akis-tohum.mjs';

const O = barOrtami({ ad: 'pms-e2e', ag: 'pms-e2e-net' });
let ok = 0, fail = 0;
const adimlar = [];
const sonuc = (g, ad, ek) => {
  console.log((g ? 'OK   ' : 'FAIL ') + ad + (ek ? ' — ' + ek : ''));
  adimlar.push({ ad, g });
  if (g) ok++; else fail++;
};
const bekle = (ms) => new Promise((r) => setTimeout(r, ms));
const reddetmeler = [];
process.on('unhandledRejection', (e) => { reddetmeler.push(String(e && e.message || e)); });

const tek = (s) => O.sql(s).out.trim();
const jwt = () => yerelJwt('authenticated', PMS.RESEPSIYON.sub);
let REST;

// Urunun kendi yazma yolu: PostgREST uzerinden, RLS ve tetikleyiciler acik.
async function rest(yol, secenek = {}) {
  // PostgREST tablolari kokte sunar; ekranin kullandigi '/rest/v1/' oneki
  // harness'ta cevrildigi gibi burada da cevrilir (ayni sunucu, ayni yol).
  const r = await fetch(REST + yol.replace('/rest/v1/', '/'), {
    ...secenek,
    headers: {
      apikey: 'test-anon', Authorization: 'Bearer ' + jwt(),
      'Content-Type': 'application/json', Prefer: 'return=representation',
      ...(secenek.headers || {}),
    },
  });
  const govde = await r.text();
  return { ok: r.ok, durum: r.status, govde };
}
function ekran(html) {
  return barEkranKur({
    html, restUrl: REST, jwt: jwt(),
    kullanici: { id: PMS.RESEPSIYON.sub, ad: 'Resepsiyon 810', rol: 'muhasebe_calisani', otel_id: '810', otelId: '810' },
    yetkiler: RESEPSIYON_YETKI,
  });
}
async function hazirOl(e, ifade) {
  for (let i = 0; i < 120 && !e.calistir(ifade); i++) await bekle(50);
}

const MISAFIR = '77777777-0000-0000-0000-000000000203';
const REZ = '88888888-0000-0000-0000-000000000203';
let FOLIO = null;

try {
  await O.kur();
  const t1 = O.sql(EK_TOHUM); if (!t1.ok) throw new Error('A1 tohum: ' + t1.err.slice(-300));
  const t2 = O.sql(PMS_TOHUM); if (!t2.ok) throw new Error('PMS tohum: ' + t2.err.slice(-400));
  REST = await O.restBaslat({ port: 3098 });
  console.log('ortam hazir — ' + REST + ' (izole veritabani, uretim YOK)\n');
  console.log('--- 1) MISAFIR KAYDI ---');

  const m = await rest('/rest/v1/pms_misafirler', {
    method: 'POST',
    body: JSON.stringify({ id: MISAFIR, otel_id: '810', ad: 'Deneme', soyad: 'Uctanuca' }),
  });
  sonuc(m.ok, 'E1 misafir urunun kendi yolundan kaydedildi (RLS acik)', m.ok ? '' : m.durum + ' ' + m.govde.slice(0, 160));

  console.log('\n--- 2) REZERVASYON + ODA MUSAITLIGI ---');
  const r1 = await rest('/rest/v1/pms_rezervasyonlar', {
    method: 'POST',
    body: JSON.stringify({
      id: REZ, otel_id: '810', rezervasyon_no: 'E2E-203', misafir_id: MISAFIR,
      oda_tipi_id: PMS.TIP, giris_tarihi: tek('select current_date::text;'),
      cikis_tarihi: tek("select (current_date + 2)::text;"), durum: 'taslak',
      gecelik_fiyat: 1500,
    }),
  });
  sonuc(r1.ok, 'E2 rezervasyon taslak olarak olusturuldu', r1.ok ? '' : r1.durum + ' ' + r1.govde.slice(0, 160));

  const r2 = await rest('/rest/v1/pms_rezervasyonlar?id=eq.' + REZ, {
    method: 'PATCH', body: JSON.stringify({ durum: 'onaylandi' }),
  });
  sonuc(r2.ok, 'E3 rezervasyon onaylandi', r2.ok ? '' : r2.durum + ' ' + r2.govde.slice(0, 160));

  FOLIO = tek(`select id::text from public.pms_folyolar where rezervasyon_id='${REZ}';`);
  sonuc(!!FOLIO && tek(`select durum from public.pms_folyolar where rezervasyon_id='${REZ}';`) === 'acik',
    'E4 onay folyoyu OTOMATIK acti (tetikleyici)', FOLIO ? 'folio=' + FOLIO.slice(0, 8) : 'folyo YOK');

  console.log('\n--- 3) CHECK-IN (oda plani ekrani) ---');
  let e = ekran('pms-oda-plani.html');
  await hazirOl(e, 'ODALAR.length');
  const sunulan202 = e.calistir(
    `JSON.stringify(uygunRezervasyonlar(ODALAR.find(o=>o.id==='${PMS.ODA202}')).map(r=>r.id))`);
  sonuc(JSON.parse(sunulan202).includes(REZ),
    'E5 bos+temiz oda, onaylanmis rezervasyonu check-in listesinde gosteriyor (musaitlik)', sunulan202);

  e.calistir(`girisAc('${PMS.ODA202}')`);
  const tiklanabilir = [...e.el('girisListe').innerHTML.matchAll(/checkInYap\('([0-9a-f-]+)'\)/g)].map((x) => x[1]);
  if (tiklanabilir.includes(REZ)) {
    await e.calistir(`checkInYap('${REZ}')`);
    await bekle(400);
  }
  sonuc(tek(`select durum from public.pms_rezervasyonlar where id='${REZ}';`) === 'giris_yapildi',
    'E6 ekrandan check-in yapildi', e.sonToast());
  sonuc(tek(`select kullanim_durumu from public.pms_odalar where id='${PMS.ODA202}';`) === 'dolu',
    'E7 oda dolu isaretlendi');

  console.log('\n--- 4) HARCAMANIN FOLYOYA ISLENMESI ---');
  const oda = await rest('/rest/v1/rpc/pms_folio_oda_ucreti_isle', {
    method: 'POST', body: JSON.stringify({ p_rezervasyon_id: REZ }),
  });
  const hareket = Number(tek(`select count(*)::text from public.pms_folio_hareketleri where folio_id='${FOLIO}';`));
  sonuc(oda.ok && hareket > 0, 'E8 oda ucreti folyoya islendi',
    oda.ok ? 'hareket=' + hareket + ' donen=' + oda.govde.slice(0, 40) : oda.durum + ' ' + oda.govde.slice(0, 160));

  const bakiye = () => tek(`select (coalesce((select sum(tutar) from public.pms_folio_hareketleri where folio_id='${FOLIO}'),0)
                                  - coalesce((select sum(tutar) from public.pms_folio_odemeler    where folio_id='${FOLIO}'),0))::text;`);
  const b1 = bakiye();
  sonuc(b1 !== '' && Number(b1) > 0, 'E9 folyo bakiyesi olustu', 'bakiye=' + (b1 === '' ? '(OLCULEMEDI)' : b1));

  console.log('\n--- 5) ODEME / DUZELTME ---');
  const kapatDeneme = await rest('/rest/v1/rpc/pms_folio_kapat', {
    method: 'POST', body: JSON.stringify({ p_folio_id: FOLIO }),
  });
  sonuc(!kapatDeneme.ok && /bakiyesi sifir degil/i.test(kapatDeneme.govde),
    'E10 BAKIYE TUTARSIZLIGI: bakiye sifir degilken folyo kapatilamiyor',
    kapatDeneme.ok ? 'KAPANDI (beklenmeyen)' : kapatDeneme.govde.slice(0, 120));

  const anahtar = '99999999-0000-0000-0000-000000000203';
  const o1 = await rest('/rest/v1/pms_folio_odemeler', {
    method: 'POST',
    body: JSON.stringify({ otel_id: '810', folio_id: FOLIO, yontem: 'nakit', tutar: Number(b1), islem_anahtari: anahtar }),
  });
  sonuc(o1.ok, 'E11 tahsilat alindi', o1.ok ? 'tutar=' + b1 : o1.durum + ' ' + o1.govde.slice(0, 160));

  const o2 = await rest('/rest/v1/pms_folio_odemeler', {
    method: 'POST',
    body: JSON.stringify({ otel_id: '810', folio_id: FOLIO, yontem: 'nakit', tutar: Number(b1), islem_anahtari: anahtar }),
  });
  const odemeSayisi = Number(tek(`select count(*)::text from public.pms_folio_odemeler where folio_id='${FOLIO}';`));
  sonuc(odemeSayisi === 1, 'E12 MUKERRER ISLEM: ayni islem anahtariyla ikinci tahsilat COGALMADI',
    'odeme satiri=' + odemeSayisi + ' ikinci istek=' + (o2.ok ? 'kabul' : 'red ' + o2.durum));

  const b2 = bakiye();
  sonuc(b2 !== '' && Number(b2) === 0, 'E13 bakiye sifirlandi', 'bakiye=' + (b2 === '' ? '(OLCULEMEDI)' : b2));

  const kapat2 = await rest('/rest/v1/rpc/pms_folio_kapat', { method: 'POST', body: JSON.stringify({ p_folio_id: FOLIO }) });
  sonuc(kapat2.ok && tek(`select durum from public.pms_folyolar where id='${FOLIO}';`) === 'kapali',
    'E14 bakiye sifirken folyo kapandi', kapat2.ok ? '' : kapat2.govde.slice(0, 120));

  console.log('\n--- 6) CHECK-OUT ---');
  e = ekran('pms-oda-plani.html');
  await hazirOl(e, 'ODALAR.length');
  e.confirmVer(true);
  await e.calistir(`cikisAc('${PMS.ODA202}')`);
  await bekle(400);
  sonuc(tek(`select durum from public.pms_rezervasyonlar where id='${REZ}';`) === 'cikis_yapildi',
    'E15 ekrandan check-out yapildi', e.sonToast());
  const odaDurum = tek(`select kullanim_durumu||'/'||temizlik_durumu from public.pms_odalar where id='${PMS.ODA202}';`);
  sonuc(odaDurum === 'bos/kirli', 'E16 oda bosaldi ve KIRLI isaretlendi', odaDurum);

  console.log('\n--- 7) ODANIN YENIDEN SATISA HAZIR OLMASI ---');
  // Kirli oda satilamaz: ekran check-in yolu ACMAMALI.
  e = ekran('pms-oda-plani.html');
  await hazirOl(e, 'ODALAR.length');
  e.calistir(`girisAc('${PMS.ODA202}')`);
  sonuc(/check-in alamaz/i.test(e.sonToast()), 'E17 KIRLI oda check-in kabul etmiyor', e.sonToast());

  // Kat hizmetleri dongusu: gorev -> sahiplen -> baslat -> tamamla -> kontrol.
  // Gorev check-out'ta OTOMATIK acilir (Faz 2 yasam dongusu); disaridan
  // acmaya calismak yaniltici olurdu.
  const gId = tek(`select id::text from public.pms_housekeeping_gorevleri
                   where oda_id='${PMS.ODA202}' order by olusturma_tarihi desc limit 1;`);
  sonuc(!!gId, 'E18 cikis sonrasi temizlik gorevi OTOMATIK acildi',
    gId ? 'gorev=' + String(gId).slice(0, 8) : 'gorev YOK');

  if (gId) {
    const surum = () => tek(`select surum::text from public.pms_housekeeping_gorevleri where id='${gId}';`);
    const cagir = (ad, ek = {}) => rest('/rest/v1/rpc/' + ad, {
      method: 'POST',
      body: JSON.stringify({ p_gorev_id: gId, p_beklenen_surum: Number(surum()),
        p_islem_anahtari: crypto.randomUUID(), ...ek }),
    });
    const s1 = await cagir('pms_housekeeping_sahiplen');
    const s2 = await cagir('pms_housekeeping_baslat');
    const s3 = await cagir('pms_housekeeping_tamamla');
    const son = tek(`select kullanim_durumu||'/'||temizlik_durumu from public.pms_odalar where id='${PMS.ODA202}';`);
    sonuc(s1.ok && s2.ok && s3.ok, 'E19 temizlik dongusu yurutuldu (sahiplen/baslat/tamamla)',
      [s1, s2, s3].map((x) => x.ok ? 'ok' : x.durum).join('/'));
    sonuc(/^bos\/(temiz|kontrol_edildi)$/.test(son), 'E20 oda yeniden satilabilir durumda', son);
  } else {
    sonuc(false, 'E19-E20 OLCULEMEDI: temizlik gorevi olusmadigi icin donguye girilemedi');
  }

  // Zincirin kapanisi: temiz oda yeni bir rezervasyona check-in verebiliyor mu?
  const yeniRez = '88888888-0000-0000-0000-000000000204';
  O.sql(`set session_replication_role = replica;
    insert into public.pms_misafirler (id, otel_id, ad, soyad)
      values ('77777777-0000-0000-0000-000000000204','810','Deneme','Sonraki');
    insert into public.pms_rezervasyonlar (id, otel_id, rezervasyon_no, misafir_id, oda_tipi_id, giris_tarihi, cikis_tarihi, durum)
      values ('${yeniRez}','810','E2E-204','77777777-0000-0000-0000-000000000204','${PMS.TIP}',
              current_date, current_date + 1, 'onaylandi');
    set session_replication_role = origin;`);
  e = ekran('pms-oda-plani.html');
  await hazirOl(e, 'ODALAR.length');
  const tekrar = e.calistir(`JSON.stringify(uygunRezervasyonlar(ODALAR.find(o=>o.id==='${PMS.ODA202}')).map(r=>r.id))`);
  sonuc(JSON.parse(tekrar).includes(yeniRez), 'E21 ayni oda yeni rezervasyona satilabiliyor (zincir kapandi)', tekrar);

} catch (e) {
  console.log('\nKURULUM/KOSUM HATASI: ' + (e && e.message || e));
  fail++;
} finally {
  O.temizle();
}

if (reddetmeler.length) console.log('\nyakalanmamis reddetme: ' + reddetmeler.join(' | '));
console.log('\n======================================================================');
console.log(`SONUC: ${ok} gecti, ${fail} kaldi`);
if (fail) console.log('KALAN: ' + adimlar.filter((a) => !a.g).map((a) => a.ad.split(' ')[0]).join(', '));
console.log('======================================================================');
process.exit(fail ? 1 : 0);
