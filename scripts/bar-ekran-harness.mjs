// ===========================================================================
// BAR EKRANLARI KOSUM ORTAMI (harness) — uretime BAGLANMAZ
// ===========================================================================
// bar-*.html icindeki GERCEK betigi Node'da, gercek PostgREST'e (A1 uygulanmis
// izole veritabani) karsi calistirir. Tarayicida kosan kod ile testte kosan kod
// AYNIDIR; ekran mantigi kopyalanmaz.
//
// Yuklenen dosyalar HTML'deki <script src> sirasiyla okunur. Yalniz ortam
// dosyalari (auth-guard / supabase-config / nav-drawer / bar-config) test
// yapilandirmasiyla DEGISTIRILIR: uretim adresleri ve anahtarlari yuklenmez.
//
// confirm / prompt yanitlari testte kuyruga konur; toast ve alert metinleri
// kaydedilir. setInterval (8 sn'lik yoklama) kasten calistirilmaz.
// ===========================================================================
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

export const kok = new URL('..', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const ORTAM_DOSYALARI = new Set(['auth-guard.js', 'supabase-config.js', 'nav-drawer.js', 'bar-config.js']);

function sahteEleman(id) {
  return {
    id, value: '', innerHTML: '', textContent: '', checked: false, disabled: false,
    style: {}, dataset: {}, options: [],
    classList: { add() {}, remove() {}, contains() { return false; }, toggle() {} },
    addEventListener() {}, removeEventListener() {}, appendChild() {}, remove() {},
    setAttribute() {}, getAttribute() { return null; }, focus() {}, click() {},
    querySelector() { return null; }, querySelectorAll() { return []; },
  };
}

export function barEkranKur({ html, restUrl, jwt, kullanici, yetkiler = {}, musteriFetch = null, arama = '', kaynakKok = kok, musteriAnon = 'test-musteri-anon' }) {
  const elemanlar = new Map();
  const el = (id) => { if (!elemanlar.has(id)) elemanlar.set(id, sahteEleman(id)); return elemanlar.get(id); };
  const kayit = { toastlar: [], uyarilar: [], istekler: [], onaylar: [], sorular: [] };
  const confirmKuyrugu = [], promptKuyrugu = [];

  const MUSTERI = 'http://musteri.test';
  const gercekFetch = globalThis.fetch;
  const ortamFetch = async (url, secenek) => {
    const u = String(url);
    kayit.istekler.push({ url: u, govde: secenek && secenek.body });
    if (u.startsWith(MUSTERI)) {
      if (!musteriFetch) throw new Error('musteri projesi cagrisi beklenmiyordu: ' + u);
      return musteriFetch(u.slice(MUSTERI.length), secenek);
    }
    return gercekFetch(u.replace('/rest/v1/', '/'), secenek);
  };

  const baglam = {
    console, setTimeout, clearTimeout, setInterval: () => 0, clearInterval() {},
    Promise, Date, Math, JSON, Map, Set, Object, Array, String, Number, Boolean,
    Error, TypeError, RegExp, Intl, URL, URLSearchParams, encodeURIComponent, decodeURIComponent,
    parseFloat, parseInt, isNaN, isFinite, Headers, Request, Response,
    document: {
      getElementById: el, querySelector: () => null, querySelectorAll: () => [],
      createElement: () => sahteEleman('yeni'), addEventListener() {}, body: sahteEleman('body'),
    },
    navigator: { userAgent: 'node-test' },
    location: { href: 'http://localhost/' + html + arama, search: arama, hash: '', pathname: '/' + html, reload() {} },
    localStorage: { getItem: () => null, setItem() {}, removeItem() {} },
    sessionStorage: { getItem: () => null, setItem() {}, removeItem() {} },
    fetch: ortamFetch,
    alert: (m) => { kayit.uyarilar.push(String(m)); },
    confirm: (m) => { kayit.onaylar.push(String(m)); return confirmKuyrugu.length ? confirmKuyrugu.shift() : false; },
    prompt: (m) => { kayit.sorular.push(String(m)); return promptKuyrugu.length ? promptKuyrugu.shift() : null; },
    addEventListener() {}, removeEventListener() {},
  };
  baglam.window = baglam; baglam.globalThis = baglam; baglam.self = baglam;
  vm.createContext(baglam);

  vm.runInContext(
    `var SB_URL=${JSON.stringify(restUrl)};
     var SB_KEY='test-anon';
     var SB_HEADERS={apikey:'test-anon',Authorization:'Bearer ' + ${JSON.stringify(jwt)},'Content-Type':'application/json'};
     var CUSTOMER_SB_URL=${JSON.stringify(MUSTERI)};
     var CUSTOMER_ANON_KEY=${JSON.stringify(musteriAnon)};
     var __kullanici=${JSON.stringify(kullanici)};
     var requireLogin=function(){return __kullanici;};
     var requireRole=function(){return true;};
     var kullaniciYetkileriGetir=async function(){return ${JSON.stringify(yetkiler)};};
     var oturumAccessTokenGetir=function(){return ${JSON.stringify(jwt)};};`,
    baglam, { filename: 'test-config.js' });

  const metin = readFileSync(kaynakKok + html, 'utf8');
  for (const m of metin.matchAll(/<script src="([^"]+)"><\/script>/g)) {
    if (ORTAM_DOSYALARI.has(m[1])) continue;
    vm.runInContext(readFileSync(kaynakKok + m[1], 'utf8'), baglam, { filename: m[1] });
  }
  // toast/sLD ortak.js'ten gelir; kayit icin sarilir (davranis degismez).
  vm.runInContext(`var __toast=[];`, baglam);
  const icBetik = metin.match(/<script>([\s\S]*?)<\/script>/);
  if (!icBetik) throw new Error(html + ' icinde satir ici betik yok');
  vm.runInContext(icBetik[1], baglam, { filename: html });
  baglam.toast = (m) => { kayit.toastlar.push(String(m)); };
  baglam.sLD = () => {}; baglam.hLD = () => {};

  return {
    baglam, el, kayit,
    confirmVer: (...c) => confirmKuyrugu.push(...c),
    promptVer: (...p) => promptKuyrugu.push(...p),
    calistir: (kod) => vm.runInContext(kod, baglam, { filename: 'test.js' }),
    sonToast: () => kayit.toastlar[kayit.toastlar.length - 1] || '',
  };
}
