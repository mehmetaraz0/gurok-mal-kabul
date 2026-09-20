// ===========================================================================
// stokEkleCagir() — ISTEMCI NESLI VE GERI DUSUS SINIRI (Docker gerekmez)
// ===========================================================================
// ortak.js'deki GERCEK fonksiyon calistirilir; fetch taklit edilir.
// Olculen (kullanici siniri 2026-09-20):
//   * Yeni cagri her zaman p_istemci_nesli tasir.
//   * Eski imzaya donus YALNIZ "fonksiyon bulunamadi" (PGRST202) halinde olur.
//   * Diger hicbir hata (ESKI_ISTEMCI, yetki, RLS, sunucu, ag) geri donus
//     tetiklemez — yani 5. parametre bir yetki kapisi degil, uyumluluk ayrimidir
//     ve istemci hata halinde eski yola "kacamaz".
// ===========================================================================
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import { kok } from './bar-test-ortam.mjs';

let ok = 0, fail = 0;
const sonuc = (g, ad, ek) => { console.log((g ? 'OK   ' : 'FAIL ') + ad + (ek ? ' — ' + ek : '')); if (g) ok++; else fail++; };

function ortamKur(yanitlar) {
  const cagrilar = [];
  const baglam = {
    console, JSON, Object, Promise, Error, String, Number, Boolean, Math, Date, RegExp,
    SB_URL: 'http://test/rest/v1'.replace('/rest/v1', ''),
    SB_HEADERS: { apikey: 'x', 'Content-Type': 'application/json' },
    document: { getElementById: () => null, createElement: () => ({ style: {}, appendChild() {} }), body: { appendChild() {} } },
    fetch: async (url, opts) => {
      const govde = JSON.parse(opts.body);
      cagrilar.push(govde);
      const y = yanitlar[cagrilar.length - 1];
      if (y instanceof Error) throw y;
      return { ok: y.durum >= 200 && y.durum < 300, status: y.durum,
        text: async () => y.metin || '', clone() { return this; }, json: async () => JSON.parse(y.metin || '{}') };
    },
  };
  baglam.window = baglam; baglam.globalThis = baglam;
  vm.createContext(baglam);
  vm.runInContext(readFileSync(kok + 'ortak.js', 'utf8'), baglam, { filename: 'ortak.js' });
  return { baglam, cagrilar };
}
const GOVDE = { p_urun_kodu: 'BIRA', p_depo_kodu: '810_CSM302', p_otel_id: '810', p_delta: 5 };
const cagir = async (yanitlar) => {
  const { baglam, cagrilar } = ortamKur(yanitlar);
  baglam.__govde = GOVDE;
  let hata = null, cevap = null;
  try { cevap = await vm.runInContext('stokEkleCagir(__govde)', baglam); } catch (e) { hata = e; }
  return { cagrilar, cevap, hata };
};
const YOK = JSON.stringify({ code: 'PGRST202', message: 'Could not find the function public.stok_ekle(p_delta, p_depo_kodu, p_istemci_nesli, p_otel_id, p_urun_kodu) in the schema cache' });

// 1) Basarili cagri: tek istek, istemci nesli var
let r = await cagir([{ durum: 200, metin: '15' }]);
sonuc(r.cagrilar.length === 1 && r.cagrilar[0].p_istemci_nesli === 1 && r.cevap && r.cevap.ok,
  'C1 yeni cagri p_istemci_nesli tasir ve tek istek atilir', JSON.stringify(r.cagrilar[0]));

// 2) A1 ONCESI veritabani: fonksiyon yok -> eski imzaya TEK kez donulur
r = await cagir([{ durum: 404, metin: YOK }, { durum: 200, metin: '15' }]);
sonuc(r.cagrilar.length === 2 && r.cagrilar[1].p_istemci_nesli === undefined && r.cevap.ok,
  'C2 yalniz PGRST202 (fonksiyon bulunamadi) halinde eski imzaya donulur; ikinci istekte nesil YOK');

// 3) ESKI_ISTEMCI (A1 sonrasi 4 parametreli yol) -> geri donus YOK
r = await cagir([{ durum: 400, metin: JSON.stringify({ code: 'P0001', message: 'ESKI_ISTEMCI: bu ekran guncelleme oncesi surum' }) }]);
sonuc(r.cagrilar.length === 1 && !r.cevap.ok, 'C3 ESKI_ISTEMCI hatasinda eski imzaya DONULMEZ (tek istek)');

// 4) Yetki / RLS / sunucu hatalari -> geri donus YOK
for (const [durum, metin, ad] of [
  [403, JSON.stringify({ code: '42501', message: 'permission denied for function stok_ekle' }), 'yetki reddi'],
  [401, JSON.stringify({ message: 'JWT expired' }), 'oturum hatasi'],
  [400, JSON.stringify({ code: 'P0001', message: 'REZERVE_STOK: ...' }), 'rezervasyon korumasi'],
  [500, 'sunucu', 'sunucu hatasi'],
  [404, JSON.stringify({ code: 'PGRST116', message: 'baska 404' }), '404 ama PGRST202 degil'],
]) {
  r = await cagir([{ durum, metin }]);
  sonuc(r.cagrilar.length === 1, `C5 ${ad} (${durum}) halinde eski imzaya DONULMEZ`);
}

// 5) Ag hatasi: istisna cagirana gider, ikinci istek atilmaz
r = await cagir([new Error('network')]);
sonuc(r.cagrilar.length === 1 && r.hata && /network/.test(r.hata.message),
  'C6 ag hatasinda ikinci istek atilmaz, hata cagirana gider');

console.log(`\nSTOK_EKLE CAGRI SINIRI: ${ok} OK / ${fail} FAIL`);
process.exit(fail ? 1 : 0);
