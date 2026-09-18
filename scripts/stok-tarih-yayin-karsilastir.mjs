#!/usr/bin/env node
// ===========================================================================
// STOK TARIH YAYINI — T0..T2 KARSILASTIRICI  ·  uretime BAGLANMAZ
// ===========================================================================
// Girdi: 2026-09-18-stok-tarih-yayin-anlik.sql ciktilari (H bolumu, "@"
// satirlari) ve duman plani (JSON). Dosyalar PowerShell Tee-Object ile
// kaydedilmis olabilir (UTF-16LE + CRLF); ikisi de okunur.
//
// Her ardisik aralikta (onceki -> sonraki goruntu) degisen her stok satiri,
// o araliktaki stok_hareketleri ile eslestirilir:
//   * DUMAN      : plandaki islemle eslesen hareket
//   * BASKA ISLEM: plan disi hareket (baska kullanici / baska ekran)
//
// KARAR KURALLARI
//   migration araligi (T0->T1):
//     - hareketle aciklanan degisiklik  -> BASKA ISLEM (migration hatasi DEGIL)
//     - aciklanamayan degisiklik        -> INCELE (migration yalniz fonksiyon
//                                          tanimi degistirir, satir degistiremez)
//     - T1'de iki fonksiyon da tarih duzeltmesini tasimali, bar A1 izi olmamali
//   duman araligi:
//     - her plan islemi TAM BIR harekete eslesmeli
//     - duman satirina yabanci yazma girdiyse -> DUMAN GECERSIZ (tekrarla)
//     - duman satirinin miktari beklenen, tarihi aralik icinde ve islemin
//       zamanina yakin olmali; degilse -> BASARISIZ
//     - dokunulmayan satirin tarihi degistiyse -> BASARISIZ
//
// Kullanim:
//   node scripts/stok-tarih-yayin-karsilastir.mjs --plan <plan.json> T0.txt T1.txt T2a.txt ...
// Dosya sayisi plandaki adim sayisina esit olmali. Cikis kodu: 0 = GECTI,
// 1 = BASARISIZ, 2 = INCELE / DUMAN GECERSIZ (insan karari gerekir).
// ===========================================================================
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

// Hareketin yazildigi an ile stok satirinin now() degeri arasindaki en buyuk
// fark. Istemci once RPC'yi, hemen ardindan hareket kaydini yazar.
export const ESIK_SN = 120;

export function metniCoz(tampon) {
  if (typeof tampon === 'string') return tampon.replace(/\r\n?/g, '\n');
  if (tampon[0] === 0xff && tampon[1] === 0xfe) return tampon.slice(2).toString('utf16le').replace(/\r\n?/g, '\n');
  if (tampon[0] === 0xef && tampon[1] === 0xbb && tampon[2] === 0xbf) return tampon.slice(3).toString('utf8').replace(/\r\n?/g, '\n');
  return tampon.toString('utf8').replace(/\r\n?/g, '\n');
}

export function goruntuOku(metin, ad = '?') {
  const g = { ad, zaman: null, fonk: {}, satir: new Map(), hareket: [], tam: false };
  for (const ham of metin.split('\n')) {
    const s = ham.trim();
    if (!s.startsWith('@')) continue;
    const p = s.split('|');
    if (p[0] === '@ZAMAN') g.zaman = p[1];
    else if (p[0] === '@FONK') g.fonk[p[1]] = { tarih: p[2] === 'true', barA1: p[3] === 'true' };
    else if (p[0] === '@SATIR') g.satir.set(p[1] + '@' + p[2], { urun: p[1], depo: p[2], miktar: Number(p[3]), tarih: p[4] });
    else if (p[0] === '@HAREKET') g.hareket.push({ id: p[1], tarih: p[2], tip: p[3], urun: p[4], depo: p[5], kaynak: p[6] || null, miktar: Number(p[7]), belge: p[8] || '' });
    else if (p[0] === '@SON') g.tam = true;
  }
  if (!g.zaman || !g.tam) throw new Error(ad + ': makine okunur bolum eksik (@ZAMAN / @SON yok) — dosya kesik mi?');
  return g;
}

const ms = (iso) => Date.parse(iso);
const yuvarla = (x) => Math.round(x * 1000) / 1000;
export const kartMetni = (iso) => new Date(iso).toLocaleString('tr-TR', { timeZone: 'Europe/Istanbul' });

// Bir hareketin dokundugu satirlar ve miktar etkisi.
function etkiler(h) {
  if (h.tip === 'transfer') return [[h.urun + '@' + h.kaynak, -h.miktar], [h.urun + '@' + h.depo, +h.miktar]];
  if (h.tip === 'giris') return [[h.urun + '@' + h.depo, +h.miktar]];
  if (h.tip === 'cikis') return [[h.urun + '@' + h.depo, -h.miktar]];
  return [[h.urun + '@' + h.depo, NaN]];     // bilinmeyen tip: satir etkilendi, miktar bilinmez
}

function eslesir(islem, h) {
  if (islem.tip !== h.tip || islem.urun !== h.urun || yuvarla(islem.miktar) !== yuvarla(h.miktar)) return false;
  if (islem.belge && islem.belge !== h.belge) return false;
  if (islem.tip === 'transfer') return islem.kaynak === h.kaynak && islem.hedef === h.depo;
  return islem.depo === h.depo;
}

export function araligiDegerlendir(onceki, sonraki, adim) {
  const bulgular = [];
  const ekle = (seviye, mesaj) => bulgular.push({ seviye, mesaj });
  const z0 = ms(onceki.zaman), z1 = ms(sonraki.zaman);
  const aralikta = sonraki.hareket.filter((h) => ms(h.tarih) > z0 && ms(h.tarih) <= z1);

  // 1) Hareketleri siniflandir.
  const islemler = adim.islemler || [];
  const kullanilan = new Set();
  const dumanHareket = [];
  for (const islem of islemler) {
    const adaylar = aralikta.filter((h) => !kullanilan.has(h.id) && eslesir(islem, h));
    if (adaylar.length !== 1) {
      ekle('BASARISIZ', `plan islemi ${JSON.stringify(islem)} icin ${adaylar.length} hareket bulundu (tam 1 bekleniyordu)`);
      continue;
    }
    kullanilan.add(adaylar[0].id);
    dumanHareket.push(adaylar[0]);
  }
  const yabanci = aralikta.filter((h) => !kullanilan.has(h.id));

  const D = new Map();     // duman satiri -> { delta, sonHareket }
  for (const h of dumanHareket) {
    for (const [k, delta] of etkiler(h)) {
      const e = D.get(k) || { delta: 0, sonHareket: null };
      e.delta += delta;
      if (!e.sonHareket || ms(h.tarih) > ms(e.sonHareket)) e.sonHareket = h.tarih;
      D.set(k, e);
    }
  }
  const Y = new Set(yabanci.flatMap((h) => etkiler(h).map(([k]) => k)));
  for (const h of yabanci) {
    ekle('BILGI', `BASKA ISLEM (plan disi hareket): ${h.tip} ${h.urun} ${h.kaynak ? h.kaynak + ' -> ' : ''}${h.depo} ${h.miktar} @ ${h.tarih}`);
  }

  // 2) Satir karsilastirmasi.
  const anahtarlar = new Set([...onceki.satir.keys(), ...sonraki.satir.keys()]);
  const kartlar = [];
  for (const k of [...anahtarlar].sort()) {
    const a = onceki.satir.get(k), b = sonraki.satir.get(k);
    const degisti = !a || !b || yuvarla(a.miktar) !== yuvarla(b.miktar) || a.tarih !== b.tarih;

    if (D.has(k)) {
      const e = D.get(k);
      if (Y.has(k)) { ekle('DUMAN_GECERSIZ', `${k}: duman satirina ayni aralikta YABANCI yazma girdi — sonuc olculemez, adimi tekrarla`); continue; }
      if (!b) { ekle('BASARISIZ', `${k}: duman satiri sonraki goruntude YOK`); continue; }
      const beklenen = yuvarla(Math.max(0, (a ? a.miktar : 0) + e.delta));
      if (Number.isNaN(beklenen) || yuvarla(b.miktar) !== beklenen) {
        ekle('BASARISIZ', `${k}: miktar ${a ? a.miktar : '(yok)'} -> ${b.miktar}, beklenen ${beklenen}`);
      }
      const t = ms(b.tarih);
      if (!(t > z0 && t <= z1)) {
        ekle('BASARISIZ', `${k}: guncelleme_tarihi SUNUCUDA GUNCELLENMEDI (${a ? a.tarih : '-'} -> ${b.tarih}; aralik ${onceki.zaman} .. ${sonraki.zaman})`);
      } else if (Math.abs(t - ms(e.sonHareket)) > ESIK_SN * 1000) {
        ekle('BASARISIZ', `${k}: tarih ${b.tarih} duman hareketinden (${e.sonHareket}) ${ESIK_SN} sn'den uzak`);
      } else {
        ekle('GECTI', `${k}: miktar ${a ? a.miktar : 0} -> ${b.miktar}, tarih sunucuda ${b.tarih}`);
        kartlar.push({ satir: k, tarih: b.tarih, kart: kartMetni(b.tarih) });
      }
      continue;
    }
    if (!degisti) continue;
    if (Y.has(k)) { ekle('BILGI', `${k}: BASKA ISLEM tarafindan degisti (migration/duman hatasi DEGIL)`); continue; }
    const tarihDegisti = a && b && a.tarih !== b.tarih;
    if (adim.tur === 'migration') {
      ekle('INCELE', `${k}: hareket kaydi olmadan degisti (${a ? a.miktar + ' ' + a.tarih : 'yok'} -> ${b ? b.miktar + ' ' + b.tarih : 'yok'}). Migration satir degistiremez; kaynagi bul.`);
    } else if (tarihDegisti) {
      ekle('BASARISIZ', `${k}: DOKUNULMAYAN satirin tarihi degisti (${a.tarih} -> ${b.tarih}), aciklayan hareket yok`);
    } else {
      ekle('INCELE', `${k}: hareket kaydi olmadan miktar degisti (${a ? a.miktar : 'yok'} -> ${b ? b.miktar : 'yok'})`);
    }
  }

  // 3) Fonksiyon durumu.
  if (adim.tur === 'migration') {
    for (const f of ['stok_ekle', 'stok_transfer']) {
      const d = sonraki.fonk[f];
      if (!d || !d.tarih) ekle('BASARISIZ', `${sonraki.ad}: ${f} tarih duzeltmesini TASIMIYOR`);
      else if (d.barA1) ekle('BASARISIZ', `${sonraki.ad}: ${f} bar A1 izi tasiyor — bu yayin A1 icermemeli`);
      else ekle('GECTI', `${sonraki.ad}: ${f} tarih duzeltmesini tasiyor, bar A1 izi yok`);
    }
  }
  return { bulgular, kartlar };
}

const SIRA = ['GECTI', 'BILGI', 'DUMAN_GECERSIZ', 'INCELE', 'BASARISIZ'];
export function karar(bulgular) {
  return bulgular.reduce((en, b) => (SIRA.indexOf(b.seviye) > SIRA.indexOf(en) ? b.seviye : en), 'GECTI');
}

export function karsilastir(goruntuler, plan) {
  if (goruntuler.length !== plan.adimlar.length) {
    throw new Error(`plan ${plan.adimlar.length} adim, ${goruntuler.length} goruntu verildi`);
  }
  const ilk = goruntuler[0];
  const sonuc = [];
  const ilkBulgu = [];
  for (const f of ['stok_ekle', 'stok_transfer']) {
    const d = ilk.fonk[f];
    if (!d) ilkBulgu.push({ seviye: 'BASARISIZ', mesaj: `${ilk.ad}: ${f} bulunamadi` });
    else if (d.barA1) ilkBulgu.push({ seviye: 'BASARISIZ', mesaj: `${ilk.ad}: ${f} bar A1 izi tasiyor` });
    else ilkBulgu.push({ seviye: 'BILGI', mesaj: `${ilk.ad}: ${f} tarih_duzeltmesi=${d.tarih}` });
  }
  sonuc.push({ aralik: ilk.ad, bulgular: ilkBulgu, kartlar: [] });
  for (let i = 1; i < goruntuler.length; i++) {
    const r = araligiDegerlendir(goruntuler[i - 1], goruntuler[i], plan.adimlar[i]);
    sonuc.push({ aralik: goruntuler[i - 1].ad + ' -> ' + goruntuler[i].ad, ...r });
  }
  return { sonuc, genel: karar(sonuc.flatMap((s) => s.bulgular)) };
}

function planDogrula(plan) {
  const metin = JSON.stringify(plan);
  if (/<[A-Z_]+>/.test(metin)) throw new Error('planda doldurulmamis yer tutucu var: ' + metin.match(/<[A-Z_]+>/)[0]);
  return plan;
}

// --- CLI ---------------------------------------------------------------------
if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const arg = process.argv.slice(2);
  const pi = arg.indexOf('--plan');
  if (pi < 0) { console.error('Kullanim: --plan <plan.json> T0.txt T1.txt ...'); process.exit(1); }
  const plan = planDogrula(JSON.parse(metniCoz(readFileSync(arg[pi + 1]))));
  const dosyalar = arg.filter((_, i) => i !== pi && i !== pi + 1);
  const goruntuler = dosyalar.map((d, i) => goruntuOku(metniCoz(readFileSync(d)), plan.adimlar[i]?.ad || d));
  const { sonuc, genel } = karsilastir(goruntuler, plan);
  for (const s of sonuc) {
    console.log(`\n=== ${s.aralik}  [${karar(s.bulgular)}]`);
    for (const b of s.bulgular) console.log(`  ${b.seviye.padEnd(15)} ${b.mesaj}`);
    for (const k of s.kartlar) console.log(`  KART (sayfa yenilenince beklenen): ${k.satir} -> "Son güncelleme: ${k.kart}"`);
  }
  console.log(`\nGENEL KARAR: ${genel}`);
  process.exit(genel === 'GECTI' || genel === 'BILGI' ? 0 : genel === 'BASARISIZ' ? 1 : 2);
}
