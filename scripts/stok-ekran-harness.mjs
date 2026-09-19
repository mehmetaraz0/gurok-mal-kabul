// ===========================================================================
// STOK EKRANI KOSUM ORTAMI (harness)
// ===========================================================================
// stok-takip.html icindeki GERCEK betigi Node'da calistirir. Amac, ekran
// mantigini kopyalamadan sinamak: testte kosan kod, tarayicida kosan kodun
// AYNISIDIR. Kopyalanan bir mantik, degisince testle birlikte yalan soyler.
//
// DOM tarafi kasten asgari ve hosgorulu: testler DOM'u degil, VERI davranisini
// olcer (hangi istek atildi, hangi yanit listeye yazildi, islem engellendi mi).
// ===========================================================================
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

export const kok = new URL('..', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');

function sahteEleman(id) {
  const el = {
    id, value: '', innerHTML: '', textContent: '', checked: false,
    style: {}, dataset: {}, options: [], selectedIndex: -1, files: [],
    scrollHeight: 0, scrollTop: 0, clientHeight: 0,
    classList: { add() {}, remove() {}, contains() { return false; }, toggle() {} },
    addEventListener() {}, removeEventListener() {},
    appendChild() {}, removeChild() {}, remove() {},
    setAttribute() {}, getAttribute() { return null; }, removeAttribute() {},
    focus() {}, blur() {}, click() {}, scrollIntoView() {},
    closest() { return null; },
    querySelector() { return null; }, querySelectorAll() { return []; },
    insertAdjacentHTML() {},
  };
  return el;
}

// kaynakKok: ekran dosyalarinin okunacagi kok (varsayilan: bu calisma kopyasi). Yayin gecis
// provasi eski surumu (origin/main) ayri bir dizinden calistirir.
export function ekranKur({ restUrl, jwt, depo = 'D1', otel = '810', rol = 'cost_control', kaynakKok = kok }) {
  const elemanlar = new Map();
  const el = (id) => {
    if (!elemanlar.has(id)) elemanlar.set(id, sahteEleman(id));
    return elemanlar.get(id);
  };

  const istekGunlugu = [];
  let fetchAraci = null;          // testler istegi yavaslatmak/bozmak icin kullanir

  const gercekFetch = globalThis.fetch;
  // Supabase ag gecidi REST'i /rest/v1 altinda sunar; ciplak PostgREST kokte
  // sunar. Ekranin URL'lerine DOKUNMAYIP yalniz test cagrisinda onek dusurulur.
  const yoluCevir = (u) => String(u).replace('/rest/v1/', '/');
  const ortamFetch = async (url, secenek) => {
    const hedef = yoluCevir(url);
    istekGunlugu.push(String(url));
    if (fetchAraci) return fetchAraci(String(url), secenek, () => gercekFetch(hedef, secenek));
    return gercekFetch(hedef, secenek);
  };

  const belge = {
    getElementById: (id) => el(id),
    querySelector: () => null,
    querySelectorAll: () => [],
    createElement: () => sahteEleman('yeni'),
    addEventListener() {},
    removeEventListener() {},
    body: sahteEleman('body'),
    documentElement: sahteEleman('html'),
    cookie: '',
    readyState: 'complete',
  };

  const depolar = {};
  const baglam = {
    console,
    setTimeout, clearTimeout, setInterval, clearInterval,
    Promise, Date, Math, JSON, Map, Set, Object, Array, String, Number, Boolean,
    Error, TypeError, RangeError, RegExp, Intl, URL, URLSearchParams,
    encodeURIComponent, decodeURIComponent, parseFloat, parseInt, isNaN, isFinite,
    Buffer, TextEncoder, TextDecoder, Headers, Request, Response, AbortController,
    document: belge,
    navigator: { userAgent: 'node-test' },
    location: { href: 'http://localhost/stok-takip.html', search: '', hash: '', pathname: '/stok-takip.html', reload() {} },
    localStorage: (() => { const m = new Map(); return {
      getItem: (k) => (m.has(k) ? m.get(k) : null), setItem: (k, v) => m.set(k, String(v)),
      removeItem: (k) => m.delete(k), clear: () => m.clear() }; })(),
    sessionStorage: (() => { const m = new Map(); return {
      getItem: (k) => (m.has(k) ? m.get(k) : null), setItem: (k, v) => m.set(k, String(v)),
      removeItem: (k) => m.delete(k), clear: () => m.clear() }; })(),
    fetch: ortamFetch,
    alert: (m) => { baglam.__uyarilar.push(String(m)); },
    confirm: () => true,
    prompt: () => null,
    XLSX: {                        // Excel kitapligi yerine sayac: kac satir yazildi?
      utils: {
        json_to_sheet: (satirlar) => ({ satirlar }),
        book_new: () => ({ sheets: [] }),
        book_append_sheet: (wb, ws) => { wb.sheets.push(ws); },
      },
      writeFile: (wb, ad) => { baglam.__excel = { ad, satirlar: wb.sheets[0].satirlar }; },
    },
    addEventListener() {}, removeEventListener() {},   // window dinleyicileri
    scrollTo() {},
    __uyarilar: [],
    __excel: null,
    __istekler: istekGunlugu,
  };
  baglam.window = baglam;
  baglam.globalThis = baglam;
  baglam.self = baglam;
  vm.createContext(baglam);

  // Supabase yapilandirmasi: uretim dosyasi degil, TEST sunucusu.
  vm.runInContext(
    `var SB_URL=${JSON.stringify(restUrl)};
     var SB_ANON_KEY='test';
     var SB_HEADERS={apikey:'test',Authorization:'Bearer ' + ${JSON.stringify(jwt)},
       'Content-Type':'application/json',Prefer:'return=minimal'};
     var AKTIF_OTEL=${JSON.stringify(otel)};
     var __testKullanici={id:'test-kullanici',ad:'Test Kullanici',rol:${JSON.stringify(rol)},otel_id:${JSON.stringify(otel)}};
     // auth-guard.js yerine: oturum kontrolu testin konusu degil.
     var requireLogin=function(){return __testKullanici;};
     var requireRole=function(){return true;};
     var kullaniciYetkileriGetir=async function(){return {};};
     var oturumAccessTokenGetir=function(){return 'test';};`, baglam, { filename: 'test-config.js' });

  for (const dosya of ['otel-config.js', 'ortak.js', 'filtre.js', 'stok-veri.js', 'hata-kodlari.js']) {
    // Eski surumde olmayan yardimci dosya (or. hata-kodlari.js) atlanir.
    let icerik; try { icerik = readFileSync(kaynakKok + dosya, 'utf8'); } catch { continue; }
    vm.runInContext(icerik, baglam, { filename: dosya });
  }

  const html = readFileSync(kaynakKok + 'stok-takip.html', 'utf8');
  const m = html.match(/<script(?![^>]*src=)[^>]*>([\s\S]*?)<\/script>/);
  if (!m) throw new Error('stok-takip.html icinde satir ici betik bulunamadi');
  vm.runInContext(m[1], baglam, { filename: 'stok-takip.html' });

  // Ekranin baslangic durumu: depo secili, katalog bos (bilerek — artik
  // acilista indirilmiyor).
  vm.runInContext(`aktifDepoId=${JSON.stringify(depo)};
     currentUser={id:'test-kullanici',ad:'Test Kullanici',rol:${JSON.stringify(rol)},otel_id:${JSON.stringify(otel)}};`, baglam, { filename: 'test-durum.js' });

  // init() ekran yuklenirken kendiliginden baslar ve async'tir. Testler onun
  // BITMESINI bekler; yarim yuklu durumda olcum yapmak yanlis sonuc uretir.
  async function hazir(sureMs = 15000) {
    const bitis = Date.now() + sureMs;
    while (Date.now() < bitis) {
      if (baglam.db && baglam.db.abcSiniflari && baglam.db.urunler) return true;
      await new Promise(r => setTimeout(r, 50));
    }
    return false;
  }

  return {
    baglam,
    el,
    hazir,
    istekler: istekGunlugu,
    calistir: (kod) => vm.runInContext(kod, baglam, { filename: 'test.js' }),
    fetchAraciAyarla: (f) => { fetchAraci = f; },
    depolar,
  };
}
