// ===========================================================================
// SAYIM ONAY/RET DUGMESI — EKRAN KAPISI SUNUCU KAPISIYLA AYNI MI?
// ===========================================================================
// Sunucu kapisi (A1 bolum 15c, auth_sayim_onaycisi):
//     kullanicilar.rol = 'cost_control'  VE  stok_takip yetkisi kayit|tam
//
// 2026-09-25 canli duman testinde ekranin bundan DAR oldugu olculdu: dugmeler
// yalnizca stok_takip='tam' ise aciliyordu. Uretimde 810'un tek uygun onaycisi
// 'kayit' yetkili oldugu icin sunucu kabul ediyor, ekran etmiyordu — yani
// sayim hic onaylanamiyordu. Bu dosya o kapiyi olcer.
//
// Docker gerekmez: ekran acilista yalnizca liste okur; bos yanit veren yerel
// bir saplama sunucu yeter. Olculen sey veri degil, DUGME DURUMU.
//
//   node scripts/sayim-onay-dugmesi.test.mjs
// ===========================================================================
import http from 'node:http';
import { ekranKur } from './stok-ekran-harness.mjs';

let gecen = 0, kalan = 0;
const sonuc = (ok, ad, ek = '') => {
  if (ok) { gecen++; console.log('  PASS  ' + ad); }
  else { kalan++; console.log('  FAIL  ' + ad + (ek ? '  [' + ek + ']' : '')); }
};

// Her yola bos dizi donen saplama: ekranin acilis okumalari icin yeterli.
const sunucu = http.createServer((istek, yanit) => {
  yanit.writeHead(200, { 'Content-Type': 'application/json', 'Content-Range': '0-0/0' });
  // stok_ozet tek satir bekler; diger yollar icin bos liste yeterli.
  yanit.end(String(istek.url).includes('stok_ozet')
    ? JSON.stringify([{ toplam: 0, kritik: 0, uyari: 0, normal: 0 }])
    : '[]');
});
await new Promise((r) => sunucu.listen(0, '127.0.0.1', r));
const REST = 'http://127.0.0.1:' + sunucu.address().port;

async function dugmeDurumu({ rol, stokTakip }) {
  const yetkiler = stokTakip === null ? {} : { stok_takip: stokTakip };
  const ek = ekranKur({ restUrl: REST, jwt: 'test', depo: '810_CSM302', rol, yetkiler });
  await ek.hazir(8000);
  // init() dugme durumlarini en sonda yazar; yetki cagrisindan sonrasini bekle.
  await new Promise((r) => setTimeout(r, 300));
  return {
    onayla: ek.el('sayim-onayla-btn').disabled,
    reddet: ek.el('sayim-reddet-btn').disabled,
    tamamla: ek.el('sayim-tamamla-btn').disabled,
  };
}

console.log('SAYIM ONAY/RET DUGMESI — EKRAN KAPISI');

// 1) Uretimdeki gercek durum: cost_control + kayit. Sunucu KABUL ediyor.
const d1 = await dugmeDurumu({ rol: 'cost_control', stokTakip: 'kayit' });
sonuc(d1.onayla === false && d1.reddet === false,
  'O1 cost_control + stok_takip:kayit -> Onayla ve Reddet ACIK (sunucu kapisiyla ayni)',
  'onayla.disabled=' + d1.onayla + ' reddet.disabled=' + d1.reddet);

// 2) cost_control + tam da onaycidir.
const d2 = await dugmeDurumu({ rol: 'cost_control', stokTakip: 'tam' });
sonuc(d2.onayla === false && d2.reddet === false,
  'O2 cost_control + stok_takip:tam -> Onayla ve Reddet ACIK',
  'onayla.disabled=' + d2.onayla);

// 3) Kapsam GENISLEMEMELI: en yuksek yetki bile cost_control degilse onaylayamaz.
const d3 = await dugmeDurumu({ rol: 'yonetici', stokTakip: 'tam' });
sonuc(d3.onayla === true && d3.reddet === true,
  'O3 yonetici + stok_takip:tam -> Onayla ve Reddet KAPALI (rol cost_control degil)',
  'onayla.disabled=' + d3.onayla + ' reddet.disabled=' + d3.reddet);

// 4) cost_control olsa bile yazma yetkisi yoksa onaylayamaz.
const d4 = await dugmeDurumu({ rol: 'cost_control', stokTakip: 'goruntule' });
sonuc(d4.onayla === true && d4.reddet === true,
  'O4 cost_control + stok_takip:goruntule -> Onayla ve Reddet KAPALI',
  'onayla.disabled=' + d4.onayla);

// 5) Komsu kapiya dokunulmadi: sayim OLUSTURMA kayit|tam ile acik kalmali.
const d5 = await dugmeDurumu({ rol: 'depo', stokTakip: 'kayit' });
sonuc(d5.tamamla === false,
  'O5 depo + stok_takip:kayit -> "Sayimi Tamamla" ACIK (olusturma kapisi degismedi)',
  'tamamla.disabled=' + d5.tamamla);

sunucu.close();
console.log('\nGECEN ' + gecen + ' / KALAN ' + kalan);
process.exit(kalan ? 1 : 0);
