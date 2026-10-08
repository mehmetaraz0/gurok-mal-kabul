// ===========================================================================
// YAYIN KABUL KURALLARI — karsi ornek testleri (Docker gerekmez)
// ===========================================================================
// 2026-10-08 incelemesinin gosterdigi iki yanlis-yesil yolu KALICI olarak
// kapatir. Her olumlu kontrolun yaninda, kuralin gevsetilmesi halinde yesil
// verecek OLUMSUZ kontrol de durur.
//
// Kullanim: node --test scripts/yayin-kabul-kurallari.test.mjs
// ===========================================================================
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parmakIziDogrula, degismezlikKarari, PARMAK_IZI_ALANLARI }
  from './yayin-kabul-kurallari.mjs';

// Canli olculen taban (runbook §14) — olumlu kontrolun referansi.
const TAM = {
  tablo: 79, politika: 240, kisitlayici: 41,
  rls_kapali: 0, pinsiz_definer: 0, anon_tablo_hakki: 0,
};
const OLCULEN = { ...TAM };

test('Y8-P1 alti alan tam ve uyumlu -> GECTI', () => {
  const s = parmakIziDogrula(TAM, OLCULEN);
  assert.equal(s.durum, 'gecti');
  assert.equal(s.sapma, 0);
  assert.equal(s.karsilastirilan, 6);
});

test('Y8-N1 SO-1b karsi ornegi: yalniz {tablo:79} -> BASARISIZ', () => {
  const s = parmakIziDogrula({ tablo: 79 }, OLCULEN);
  assert.equal(s.durum, 'basarisiz', 'tek alanli dosya kabul EDILMEMELI');
  assert.equal(s.karsilastirilan, 1);
  assert.equal(s.sapma, 5, 'kalan bes zorunlu alan eksik sayilmali');
});

test('Y8-N2 her zorunlu alanin TEK TEK eksikligi BASARISIZ', () => {
  for (const alan of PARMAK_IZI_ALANLARI) {
    const eksik = { ...TAM };
    delete eksik[alan];
    const s = parmakIziDogrula(eksik, OLCULEN);
    assert.equal(s.durum, 'basarisiz', alan + ' eksikken gecmemeli');
    assert.match(s.satirlar.join('\n'), new RegExp('SAPMA\\s+' + alan + '\\s+ZORUNLU alan eksik'));
  }
});

test('Y8-N3 null deger BASARISIZ', () => {
  for (const alan of PARMAK_IZI_ALANLARI) {
    const s = parmakIziDogrula({ ...TAM, [alan]: null }, OLCULEN);
    assert.equal(s.durum, 'basarisiz', alan + ' null iken gecmemeli');
  }
});

test('Y8-N4 yanlis tur ve negatif deger BASARISIZ', () => {
  for (const kotu of ['79', 79.5, NaN, Infinity, -1, true, [], {}]) {
    const s = parmakIziDogrula({ ...TAM, tablo: kotu }, OLCULEN);
    assert.equal(s.durum, 'basarisiz', JSON.stringify(kotu) + ' kabul edilmemeli');
  }
});

test('Y8-N5 bos nesne ve nesne OLMAYAN girdi BASARISIZ', () => {
  for (const kotu of [{}, null, [], 'tablo=79', 79]) {
    assert.equal(parmakIziDogrula(kotu, OLCULEN).durum, 'basarisiz');
  }
});

test('Y8-N6 TANINMAYAN alan (yazim hatasi) BASARISIZ', () => {
  // "tablolar" yazilip "tablo" eksik kalirsa sessizce gecmemeli.
  const { tablo, ...kalan } = TAM;
  const s = parmakIziDogrula({ ...kalan, tablolar: 79 }, OLCULEN);
  assert.equal(s.durum, 'basarisiz');
  assert.match(s.satirlar.join('\n'), /TANINMAYAN alan/);
});

test('Y8-N7 olculemeyen alan BASARISIZ', () => {
  const s = parmakIziDogrula(TAM, { ...OLCULEN, politika: null });
  assert.equal(s.durum, 'basarisiz');
  assert.match(s.satirlar.join('\n'), /politika\s+OLCULEMEDI/);
});

test('Y8-N8 tek alanda sayisal sapma BASARISIZ', () => {
  const s = parmakIziDogrula(TAM, { ...OLCULEN, kisitlayici: 40 });
  assert.equal(s.durum, 'basarisiz');
  assert.equal(s.karsilastirilan, 6, 'alti alan yine karsilastirilmali');
  assert.equal(s.sapma, 1);
});

// --- Mali degismezlik ------------------------------------------------------

const ICERIK = 'id=abc|tutar=1000.00';

test('DEG-P1 iki deneme de RET ve satir korundu -> GECTI', () => {
  const s = degismezlikKarari({
    updateOk: false, deleteOk: false, oncekiIcerik: ICERIK, sonrakiIcerik: ICERIK,
  });
  assert.equal(s.gecti, true);
  assert.match(s.ozet, /update RET \/ delete RET \/ satir KORUNDU/);
});

test('DEG-N1 SO-2t karsi ornegi: UPDATE KABUL + DELETE ret -> KIRAR', () => {
  const s = degismezlikKarari({
    updateOk: true, deleteOk: false, oncekiIcerik: ICERIK, sonrakiIcerik: ICERIK,
  });
  assert.equal(s.gecti, false, 'tek tarafin kabulu testi KIRMALI');
  assert.match(s.neden, /UPDATE KABUL EDILDI/);
});

test('DEG-N2 SO-2t karsi ornegi: UPDATE ret + DELETE KABUL -> KIRAR', () => {
  const s = degismezlikKarari({
    updateOk: false, deleteOk: true, oncekiIcerik: ICERIK, sonrakiIcerik: ICERIK,
  });
  assert.equal(s.gecti, false);
  assert.match(s.neden, /DELETE KABUL EDILDI/);
});

test('DEG-N3 ikisi de RET ama satir icerigi DEGISTI -> KIRAR', () => {
  const s = degismezlikKarari({
    updateOk: false, deleteOk: false, oncekiIcerik: ICERIK, sonrakiIcerik: 'id=abc|tutar=9.00',
  });
  assert.equal(s.gecti, false);
  assert.match(s.neden, /satir icerigi DEGISTI/);
});

test('DEG-N4 satir KAYBOLDU (sonraki icerik yok) -> KIRAR', () => {
  for (const sonra of [undefined, null, '']) {
    const s = degismezlikKarari({
      updateOk: false, deleteOk: false, oncekiIcerik: ICERIK, sonrakiIcerik: sonra,
    });
    assert.equal(s.gecti, false, 'sonraki=' + JSON.stringify(sonra));
  }
});

test('DEG-N5 onceki icerik olculmemisse GECMEZ (olcumsuz yesil yok)', () => {
  const s = degismezlikKarari({
    updateOk: false, deleteOk: false, oncekiIcerik: undefined, sonrakiIcerik: undefined,
  });
  assert.equal(s.gecti, false);
});
