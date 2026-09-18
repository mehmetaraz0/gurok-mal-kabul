// ===========================================================================
// stok-tarih-yayin-karsilastir.mjs TESTLERI — her karar kurali, sentetik
// goruntulerle. Calistir: node --test scripts/stok-tarih-yayin-karsilastir.test.mjs
// ===========================================================================
import test from 'node:test';
import assert from 'node:assert/strict';
import { goruntuOku, metniCoz, karsilastir, kartMetni } from './stok-tarih-yayin-karsilastir.mjs';

const ESKI = '2026-07-09T07:23:10.000000Z';
const FONK = (tarih) => [`@FONK|stok_ekle|${tarih}|false`, `@FONK|stok_transfer|${tarih}|false`];

// Goruntu metni: satirlar {k: [miktar, tarih]}, hareketler dizi.
function goruntu(zaman, tarihDuzeltmesi, satirlar, hareketler = []) {
  return ['bas satirlari psql tablosu',
    `@ZAMAN|${zaman}`, ...FONK(tarihDuzeltmesi),
    ...Object.entries(satirlar).map(([k, [m, t]]) => { const [u, d] = k.split('@'); return `@SATIR|${u}|${d}|${m}|${t}`; }),
    ...hareketler.map((h) => `@HAREKET|${h.id}|${h.tarih}|${h.tip}|${h.urun}|${h.depo}|${h.kaynak || ''}|${h.miktar}|${h.belge || ''}`),
    '@SON'].join('\n');
}

const PLAN = {
  adimlar: [
    { ad: 'T0' },
    { ad: 'T1', tur: 'migration' },
    { ad: 'T2a', tur: 'duman', islemler: [{ tip: 'giris', urun: 'X', depo: '810_100', miktar: 1, belge: 'MK-TEST' }] },
    { ad: 'T2b', tur: 'duman', islemler: [{ tip: 'transfer', urun: 'X', kaynak: '810_100', hedef: '810_CMM201', miktar: 1 }] },
    { ad: 'T2c', tur: 'duman', islemler: [{ tip: 'cikis', urun: 'X', depo: '810_CMM201', miktar: 1 }] },
  ],
};

const Z = { t0: '2026-09-18T10:00:00.000000Z', t1: '2026-09-18T10:05:00.000000Z',
  a: '2026-09-18T10:10:00.000000Z', b: '2026-09-18T10:15:00.000000Z', c: '2026-09-18T10:20:00.000000Z' };
const H = {
  giris: { id: 'h1', tarih: '2026-09-18T10:07:01.000000Z', tip: 'giris', urun: 'X', depo: '810_100', miktar: 1, belge: 'MK-TEST' },
  transfer: { id: 'h2', tarih: '2026-09-18T10:12:01.000000Z', tip: 'transfer', urun: 'X', depo: '810_CMM201', kaynak: '810_100', miktar: 1 },
  cikis: { id: 'h3', tarih: '2026-09-18T10:17:01.000000Z', tip: 'cikis', urun: 'X', depo: '810_CMM201', miktar: 1 },
};
const RPC = { giris: '2026-09-18T10:07:00.500000Z', transfer: '2026-09-18T10:12:00.500000Z', cikis: '2026-09-18T10:17:00.500000Z' };

// Temiz, dogru calisan yayin.
function temizSenaryo() {
  const baz = { 'X@810_100': [5, ESKI], 'X@810_CMM201': [2, ESKI], 'Y@810_100': [9, ESKI] };
  return [
    goruntu(Z.t0, false, baz),
    goruntu(Z.t1, true, baz),
    goruntu(Z.a, true, { ...baz, 'X@810_100': [6, RPC.giris] }, [H.giris]),
    goruntu(Z.b, true, { ...baz, 'X@810_100': [5, RPC.transfer], 'X@810_CMM201': [3, RPC.transfer] }, [H.giris, H.transfer]),
    goruntu(Z.c, true, { ...baz, 'X@810_100': [5, RPC.transfer], 'X@810_CMM201': [2, RPC.cikis] }, [H.giris, H.transfer, H.cikis]),
  ];
}
const oku = (metinler) => metinler.map((m, i) => goruntuOku(metniCoz(m), PLAN.adimlar[i].ad));
const seviyeler = (r, aralik) => r.sonuc.find((s) => s.aralik.endsWith(aralik)).bulgular.map((b) => b.seviye);

test('temiz yayin: GECTI; kart metinleri sunucu tarihinden', () => {
  const r = karsilastir(oku(temizSenaryo()), PLAN);
  assert.ok(['GECTI', 'BILGI'].includes(r.genel), r.genel);
  assert.ok(!r.sonuc.flatMap((s) => s.bulgular).some((b) => ['BASARISIZ', 'INCELE', 'DUMAN_GECERSIZ'].includes(b.seviye)),
    JSON.stringify(r.sonuc, null, 1));
  const kartlar = r.sonuc.flatMap((s) => s.kartlar);
  assert.deepEqual(kartlar.map((k) => k.satir), ['X@810_100', 'X@810_100', 'X@810_CMM201', 'X@810_CMM201']);
  assert.equal(kartlar[0].kart, kartMetni(RPC.giris));
});

test('Tee-Object dosyasi (UTF-16LE + BOM + CRLF) okunur', () => {
  const m = temizSenaryo()[0].replace(/\n/g, '\r\n');
  const tampon = Buffer.concat([Buffer.from([0xff, 0xfe]), Buffer.from(m, 'utf16le')]);
  const g = goruntuOku(metniCoz(tampon), 'T0');
  assert.equal(g.satir.size, 3);
  assert.equal(g.zaman, Z.t0);
});

test('kesik dosya reddedilir (@SON yok)', () => {
  assert.throws(() => goruntuOku(temizSenaryo()[0].replace('@SON', ''), 'T0'), /eksik/);
});

test('migration araliginda BASKA ISLEM: migration hatasi SAYILMAZ', () => {
  const g = temizSenaryo();
  const yabanci = { id: 'y1', tarih: '2026-09-18T10:02:00.000000Z', tip: 'cikis', urun: 'Y', depo: '810_100', miktar: 1 };
  // Migration oncesi RPC tarihi yazmaz: miktar degisir, tarih eski kalir.
  g[1] = goruntu(Z.t1, true, { 'X@810_100': [5, ESKI], 'X@810_CMM201': [2, ESKI], 'Y@810_100': [8, ESKI] }, [yabanci]);
  for (let i = 2; i < 5; i++) g[i] = g[i].replace('@SATIR|Y|810_100|9|', '@SATIR|Y|810_100|8|').replace('@SON', `@HAREKET|y1|${yabanci.tarih}|cikis|Y|810_100||1|\n@SON`);
  const r = karsilastir(oku(g), PLAN);
  const s = seviyeler(r, 'T1');
  assert.ok(s.includes('BILGI') && !s.includes('INCELE') && !s.includes('BASARISIZ'), JSON.stringify(r.sonuc[1]));
});

test('migration araliginda hareketsiz degisiklik: INCELE (BASARISIZ degil)', () => {
  const g = temizSenaryo();
  g[1] = g[1].replace('@SATIR|Y|810_100|9|', '@SATIR|Y|810_100|7|');
  for (let i = 2; i < 5; i++) g[i] = g[i].replace('@SATIR|Y|810_100|9|', '@SATIR|Y|810_100|7|');
  const r = karsilastir(oku(g), PLAN);
  assert.deepEqual([...new Set(seviyeler(r, 'T1'))].sort(), ['GECTI', 'INCELE']);
});

test('T1 de tarih duzeltmesi yoksa BASARISIZ', () => {
  const g = temizSenaryo();
  g[1] = g[1].replace('@FONK|stok_ekle|true', '@FONK|stok_ekle|false');
  assert.ok(seviyeler(karsilastir(oku(g), PLAN), 'T1').includes('BASARISIZ'));
});

test('duman satirina yabanci yazma: DUMAN_GECERSIZ (tekrarla), migration suclanmaz', () => {
  const g = temizSenaryo();
  const yabanci = { id: 'y2', tarih: '2026-09-18T10:08:00.000000Z', tip: 'cikis', urun: 'X', depo: '810_100', miktar: 2 };
  g[2] = goruntu(Z.a, true, { 'X@810_100': [4, '2026-09-18T10:07:59.000000Z'], 'X@810_CMM201': [2, ESKI], 'Y@810_100': [9, ESKI] }, [H.giris, yabanci]);
  const r = karsilastir(oku(g.slice(0, 3)), { adimlar: PLAN.adimlar.slice(0, 3) });
  assert.ok(seviyeler(r, 'T2a').includes('DUMAN_GECERSIZ'));
  assert.ok(!seviyeler(r, 'T2a').includes('BASARISIZ'));
});

test('duman satirinin tarihi sunucuda guncellenmediyse BASARISIZ (duzeltme olmadan)', () => {
  const g = temizSenaryo();
  g[2] = g[2].replace(`@SATIR|X|810_100|6|${RPC.giris}`, `@SATIR|X|810_100|6|${ESKI}`);
  assert.ok(seviyeler(karsilastir(oku(g.slice(0, 3)), { adimlar: PLAN.adimlar.slice(0, 3) }), 'T2a').includes('BASARISIZ'));
});

test('transferde HEDEF tarafin tarihi guncellenmediyse BASARISIZ', () => {
  const g = temizSenaryo();
  g[3] = g[3].replace(`@SATIR|X|810_CMM201|3|${RPC.transfer}`, `@SATIR|X|810_CMM201|3|${ESKI}`);
  assert.ok(seviyeler(karsilastir(oku(g.slice(0, 4)), { adimlar: PLAN.adimlar.slice(0, 4) }), 'T2b').includes('BASARISIZ'));
});

test('dokunulmayan satirin tarihi degistiyse BASARISIZ', () => {
  const g = temizSenaryo();
  g[4] = g[4].replace(`@SATIR|Y|810_100|9|${ESKI}`, '@SATIR|Y|810_100|9|2026-09-18T10:18:00.000000Z');
  assert.ok(seviyeler(karsilastir(oku(g), PLAN), 'T2c').includes('BASARISIZ'));
});

test('plan islemine ait hareket yoksa BASARISIZ', () => {
  const g = temizSenaryo();
  g[2] = g[2].replace(/@HAREKET\|h1\|[^\n]*\n/, '');
  assert.ok(seviyeler(karsilastir(oku(g.slice(0, 3)), { adimlar: PLAN.adimlar.slice(0, 3) }), 'T2a').includes('BASARISIZ'));
});

test('beklenmeyen miktar BASARISIZ', () => {
  const g = temizSenaryo();
  g[2] = g[2].replace(`@SATIR|X|810_100|6|`, `@SATIR|X|810_100|7|`);
  assert.ok(seviyeler(karsilastir(oku(g.slice(0, 3)), { adimlar: PLAN.adimlar.slice(0, 3) }), 'T2a').includes('BASARISIZ'));
});
