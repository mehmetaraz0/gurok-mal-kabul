// ===========================================================================
// YAYIN KABUL KURALLARI — saf karar mantigi, yan etkisiz
// ===========================================================================
// NICIN AYRI DOSYA: 2026-10-08 incelemesi iki kabul kuralinin YANLIS YESIL
// verebildigini sentetik karsi orneklerle gosterdi:
//
//   SO-1b  Y8 sema parmak izi: eksik/null alanlar atlaniyordu, bu yuzden
//          `{"tablo":79}` gibi TEK alanli bir dosya "altı alan uyumlu" gibi
//          gecebiliyordu.
//   SO-2t  Mali degismezlik: `!updateOk || !deleteOk` kosulu, UPDATE kabul +
//          DELETE ret (ya da tersi) halinde de gecebiliyordu.
//
// Karar mantigi buraya tasindi ki Docker'a ve geri yuklemeye ihtiyac duymadan
// KARSI ORNEKLERLE sinanabilsin:
//   scripts/yayin-kabul-kurallari.test.mjs
// ===========================================================================

// Y8'in ZORUNLU alanlari. Hepsi bulunmak zorundadir; eksigi ret demektir.
export const PARMAK_IZI_ALANLARI = [
  'tablo',
  'politika',
  'kisitlayici',
  'rls_kapali',
  'pinsiz_definer',
  'anon_tablo_hakki',
];

function tamsayiMi(v) {
  return typeof v === 'number' && Number.isFinite(v) && Number.isInteger(v) && v >= 0;
}

// Beklenen parmak izini olculen degerlerle karsilastirir.
//   beklenen  : JSON nesnesi (ALTI alanin TAMAMI zorunlu)
//   olculenler: { alan: sayi } — olculemeyen alan icin null/undefined verilebilir
// Donus: { durum, sapma, karsilastirilan, satirlar[] }
//
// SOZLESME (SO-1b): alti alanin tamami bulunmali ve her biri sonlu, negatif
// olmayan TAMSAYI olmali. Eksik, null, yanlis tur veya negatif deger RET'tir.
// "Karsilastirilan sayisi sifir degilse gecer" mantigi KULLANILMAZ.
export function parmakIziDogrula(beklenen, olculenler) {
  const satirlar = [];
  let sapma = 0;
  let karsilastirilan = 0;

  if (beklenen === null || typeof beklenen !== 'object' || Array.isArray(beklenen)) {
    return {
      durum: 'basarisiz',
      sapma: 1,
      karsilastirilan: 0,
      satirlar: ['SAPMA  beklenen parmak izi bir JSON nesnesi degil'],
    };
  }

  // Fazla alan sessizce gecilmez: yazim hatasi (ornegin "tablolar") ALTI
  // alandan birini eksik birakip gozden kacabilir.
  const fazla = Object.keys(beklenen).filter((a) => !PARMAK_IZI_ALANLARI.includes(a));
  for (const a of fazla) {
    sapma++;
    satirlar.push('SAPMA  ' + a.padEnd(18) + ' TANINMAYAN alan (yazim hatasi mi?)');
  }

  for (const alan of PARMAK_IZI_ALANLARI) {
    const bek = beklenen[alan];
    if (bek === undefined || bek === null) {
      sapma++;
      satirlar.push('SAPMA  ' + alan.padEnd(18) + ' ZORUNLU alan eksik — kabul edilemez');
      continue;
    }
    if (!tamsayiMi(bek)) {
      sapma++;
      satirlar.push('SAPMA  ' + alan.padEnd(18) + ' beklenen deger sonlu, negatif olmayan '
        + 'tamsayi degil: ' + JSON.stringify(bek));
      continue;
    }
    const olc = olculenler ? olculenler[alan] : undefined;
    if (olc === undefined || olc === null || !Number.isFinite(Number(olc))) {
      sapma++;
      satirlar.push('SAPMA  ' + alan.padEnd(18) + ' OLCULEMEDI');
      continue;
    }
    karsilastirilan++;
    const uygun = Number(olc) === bek;
    if (!uygun) sapma++;
    satirlar.push((uygun ? 'UYGUN' : 'SAPMA') + '  ' + alan.padEnd(18)
      + ' beklenen=' + bek + ' olculen=' + Number(olc));
  }

  return {
    durum: sapma === 0 && karsilastirilan === PARMAK_IZI_ALANLARI.length ? 'gecti' : 'basarisiz',
    sapma,
    karsilastirilan,
    satirlar,
  };
}

// Mevcut bir mali satirin DEGISMEZLIGI.
//   updateOk / deleteOk : denemelerin KABUL edilip edilmedigi
//   oncekiIcerik / sonrakiIcerik : hedef satirin kimlik+icerik ozeti
// Donus: { gecti, ozet, neden }
//
// SOZLESME (SO-2t): IKI deneme de REDDEDILMELI (mantiksal VE) ve hedef satirin
// icerigi AYNEN kalmali. Tek tarafin kabul edilmesi testi KIRAR.
export function degismezlikKarari({ updateOk, deleteOk, oncekiIcerik, sonrakiIcerik }) {
  const korundu = oncekiIcerik !== undefined && oncekiIcerik !== null
    && String(oncekiIcerik) === String(sonrakiIcerik);
  const nedenler = [];
  if (updateOk) nedenler.push('UPDATE KABUL EDILDI (kusur)');
  if (deleteOk) nedenler.push('DELETE KABUL EDILDI (kusur)');
  if (!korundu) {
    nedenler.push('satir icerigi DEGISTI: ' + JSON.stringify(oncekiIcerik)
      + ' -> ' + JSON.stringify(sonrakiIcerik));
  }
  return {
    gecti: !updateOk && !deleteOk && korundu,
    ozet: 'update ' + (updateOk ? 'KABUL(kusur)' : 'RET')
      + ' / delete ' + (deleteOk ? 'KABUL(kusur)' : 'RET')
      + ' / satir ' + (korundu ? 'KORUNDU' : 'BOZULDU'),
    neden: nedenler.join(' · '),
  };
}
