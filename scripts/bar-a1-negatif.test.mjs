// ===========================================================================
// BAR A1 — KRITIK KORUMALARIN NEGATIF KONTROLLERI (uretime BAGLANMAZ)
// ===========================================================================
// Her koruma A1 dosyasinin bir KOPYASINDA kaldirilir ve ilgili senaryo
// yeniden kosulur. Beklenen: koruma yokken kusur GERI GELIR. Gelmezse o
// korumayi olcen test (bar-a1-guvenlik.test.mjs) bos geciyor demektir.
//
//   K1a teslim FOR UPDATE kaldirilir     -> ikinci eszamanli teslim artik
//        'zaten_teslim' donmez; tuketim tekilligi (ikinci katman) cift
//        dusumu yine engeller (katmanlarin ayri ayri isi gorunur)
//   K1b FOR UPDATE + tuketim tekilligi   -> stok IKI KEZ duser
//   K2  stok cikis korumasi              -> rezerve stok baska cikisla tuketilir
//   K3  danisma kilidi                   -> son birimler icin iki siparis de gecer
//   K4  dogrudan yazma kapatmasi         -> personel durumu RPC'siz degistirir
// ===========================================================================
import { readFileSync } from 'node:fs';
import { barOrtami, hataKodu, kok } from './bar-test-ortam.mjs';

const A1 = readFileSync(kok + 'docs/kurulum/2026-09-18-bar-a1-guvenlik.sql', 'utf8');
const BAR = '810_CSM302';
const BAR810 = { rol: 'authenticated', sub: '11111111-0000-0000-0000-000000000810' };
const DEPO810 = { rol: 'authenticated', sub: '11111111-0000-0000-0000-0000000000cc' };
const BIRA = '22222222-0000-0000-0000-000000000001';

let ok = 0, fail = 0;
const sonuc = (g, ad, ek) => { console.log((g ? 'OK   ' : 'FAIL ') + ad + (ek ? ' — ' + ek : '')); if (g) ok++; else fail++; };

// Bolum ici degisim: yalniz [basIsaret, bitIsaret) araligindaki metin degisir.
function bolumde(metin, basIsaret, bitIsaret, eski, yeni) {
  const b = metin.indexOf(basIsaret), e = metin.indexOf(bitIsaret, b);
  if (b < 0 || e < 0) throw new Error('bolum yok: ' + basIsaret);
  const bolum = metin.slice(b, e);
  if (!bolum.includes(eski)) throw new Error('degisecek metin bolumde yok: ' + eski.slice(0, 50));
  return metin.slice(0, b) + bolum.split(eski).join(yeni) + metin.slice(e);
}
function degistir(metin, eski, yeni) {
  if (!metin.includes(eski)) throw new Error('degisecek metin yok: ' + eski.slice(0, 50));
  return metin.split(eski).join(yeni);
}

async function varyant(ad, metin, senaryo) {
  const O = barOrtami({ ad: 'bar-neg-' + ad });
  try {
    await O.kur();
    const u = O.uygulaTekIslem(metin, { metin: true });
    if (!u.ok) throw new Error('varyant uygulanamadi: ' + u.err.slice(-300));
    await senaryo(O);
  } catch (e) {
    sonuc(false, ad + ' beklenmeyen hata', e.message);
  } finally { O.temizle(); }
}

const siparis = (O, adet, masa = 'M1') => O.kimlikle(BAR810,
  `select public.bar_siparis_olustur('810','${BAR}','${masa}',null,'[{"menu_urun_id":"${BIRA}","adet":${adet}}]'::jsonb);`);
const stok = (O) => O.sql(`select miktar::text from public.stok where urun_kodu='BIRA' and depo_kodu='${BAR}';`).out;

async function eszamanliTeslim(O) {
  const s = siparis(O, 2).out;
  O.kimlikle(BAR810, `select public.bar_siparis_durum_guncelle('${s}','hazirlaniyor');
                      select public.bar_siparis_durum_guncelle('${s}','hazir');`);
  const p1 = O.paralel(BAR810, `select public.bar_siparis_teslim_et('${s}'); select pg_sleep(2);`);
  await new Promise((r) => setTimeout(r, 700));
  const p2 = O.paralel(BAR810, `select public.bar_siparis_teslim_et('${s}');`);
  const [r1, r2] = await Promise.all([p1, p2]);
  return { r1, r2, stok: stok(O) };
}

// K1a — yalniz teslimdeki FOR UPDATE kaldirilir
const K1a = bolumde(A1, '-- 11) TESLIM', '-- 12) IPTAL',
  'select * into v_s from public.bar_siparisleri where id = p_siparis_id for update;',
  'select * into v_s from public.bar_siparisleri where id = p_siparis_id;');
await varyant('K1a', K1a, async (O) => {
  const r = await eszamanliTeslim(O);
  sonuc(!(r.r2.ok && /zaten_teslim/.test(r.r2.out)) && r.stok === '8.000',
    'K1a FOR UPDATE yokken ikinci teslim artik tekil sonuc donmuyor; cift dusumu yalniz tuketim tekilligi durduruyor',
    'ikinci: ' + (r.r2.ok ? r.r2.out : hataKodu(r.r2) || r.r2.err.split('\n')[0].slice(0, 90)) + ' | stok ' + r.stok);
});

// K1b — FOR UPDATE + tuketim tekilligi birlikte kaldirilir
const K1b = degistir(K1a, 'rezervasyon_id   uuid not null unique references', 'rezervasyon_id   uuid not null references');
await varyant('K1b', K1b, async (O) => {
  const r = await eszamanliTeslim(O);
  sonuc(r.r1.ok && r.r2.ok && r.stok === '6.000',
    'K1b iki katman da yokken eszamanli teslim stogu IKI KEZ dusuruyor (B3 testi bunu yakalar)', 'stok 10 -> ' + r.stok);
});

// K2 — stok cikis korumasi etkisiz
const K2 = degistir(A1, '  if v_rezerve = 0 then\n    return;   -- rezervasyon yoksa davranis BUGUNKUYLE AYNI',
                        '  if true then\n    return;   -- NEGATIF KONTROL: koruma kaldirildi');
await varyant('K2', K2, async (O) => {
  siparis(O, 8);
  const c = O.kimlikle(DEPO810, `select public.stok_ekle('BIRA','${BAR}','810',-5);`);
  sonuc(c.ok && stok(O) === '5.000', 'K2 koruma yokken depo kullanicisi 8 rezerveli stogu 5e dusurebiliyor (D1a testi bunu yakalar)',
    'stok 10 -> ' + stok(O));
});

// K3 — danisma kilidi etkisiz
const K3 = degistir(A1, "  perform pg_advisory_xact_lock(hashtextextended('stok:' || p_depo_kodu || ':' || p_stok_kodu, 0));",
                        '  null;   -- NEGATIF KONTROL: kilit kaldirildi');
await varyant('K3', K3, async (O) => {
  O.sql(`update public.stok set miktar = 3 where urun_kodu='BIRA' and depo_kodu='${BAR}';`);
  const p1 = O.paralel(BAR810, `select public.bar_siparis_olustur('810','${BAR}','M1',null,'[{"menu_urun_id":"${BIRA}","adet":2}]'::jsonb); select pg_sleep(2);`);
  await new Promise((r) => setTimeout(r, 700));
  const p2 = O.paralel(BAR810, `select public.bar_siparis_olustur('810','${BAR}','M2',null,'[{"menu_urun_id":"${BIRA}","adet":2}]'::jsonb);`);
  const [r1, r2] = await Promise.all([p1, p2]);
  const rez = O.sql(`select sum(miktar)::text from public.stok_rezervasyonlari where durum='aktif';`).out;
  sonuc(r1.ok && r2.ok && rez === '4.000', 'K3 kilit yokken 3 birimlik stoga 2+2 rezervasyon ikisi de geciyor (D4 testi bunu yakalar)',
    'rezerve ' + rez + ' / stok 3');
});

// K4 — dogrudan yazma kapatmasi kaldirilir
let K4 = degistir(A1, `revoke insert, update, delete, truncate, references, trigger
  on table public.bar_siparisleri, public.bar_siparis_kalemleri, public.stok_rezervasyonlari
  from authenticated;
drop policy if exists siparis_write on public.bar_siparisleri;`, '-- NEGATIF KONTROL: dogrudan yazma kapatmasi kaldirildi');
K4 = degistir(K4, "    raise exception 'SON KOSUL: siparis tablolarina dogrudan yazma hala acik.';", '    null;');
await varyant('K4', K4, async (O) => {
  const s = siparis(O, 1).out;
  const w = O.kimlikle(BAR810, `update public.bar_siparisleri set durum='teslim_edildi' where id='${s}';`);
  const d = O.sql(`select durum::text from public.bar_siparisleri where id='${s}';`).out;
  sonuc(w.ok && d === 'teslim_edildi' && stok(O) === '10.000',
    'K4 kapatma yokken personel siparisi RPCsiz teslim_edildi yapabiliyor, stok dusmeden (A11 testi bunu yakalar)', 'durum ' + d);
});

console.log(`\nBAR A1 NEGATIF KONTROLLER: ${ok} OK / ${fail} FAIL`);
process.exitCode = fail ? 1 : 0;
