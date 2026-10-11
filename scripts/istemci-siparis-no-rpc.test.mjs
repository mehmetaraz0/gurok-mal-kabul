// ===========================================================================
// ISTEMCI SIPARIS NUMARASI — RPC'ye gecis DAVRANIS testi (izole, uretime
// BAGLANMAZ, ag yok). Tasarim: specs/2026-10-11-talep-siparis-bagi-design.md §4
// ===========================================================================
// HTML icindeki GERCEK `yeniSiparisNoUret` govdesi dosyadan cikarilir ve
// taklit (`stub`) bir fetch ile CALISTIRILIR. Boylece metin benzerligi degil
// gercek donus degeri olculur.
//
// Kanitlanan sorular:
//   1. Numara sunucudan mi geliyor (rpc/siparis_no_uret), istemcide max+1 ile
//      mi uretiliyor?
//   2. Sunucu hata verirse / ag koparsa numara UYDURULUYOR mu?
//      (Eski kod `catch` icinde rastgele numara donduruyordu: iki kullanici
//       ayni numarayi alabilir, siparis_no PRIMARY KEY oldugu icin biri
//       sessizce kaybolur.)
//   3. Cagiran yer numara alinamazsa DURUYOR mu, yoksa null numarayla
//      siparis yazmaya devam mi ediyor? (Yukleme ortusu de kapanmali.)
// ===========================================================================
import { readFileSync } from 'node:fs';

const KOK = new URL('..', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
// UC KOPYA: ucuncusu (siparis olustur) suite disinda kalirsa o dosyaya
// hata dalindaki rastgele numara uretimi geri gelse testler yesil kalir
// (olculdu: ikinci bagimsiz inceleme I-10).
const DOSYALAR = ['satin-alma-iade.html', 'stok-takip.html', 'satin-alma-siparisolustur.html'];

let ok = 0, fail = 0;
const sonuc = (g, ad, ek) => {
  console.log((g ? 'OK   ' : 'FAIL ') + ad + (ek ? ' — ' + ek : ''));
  if (g) ok++; else fail++;
};
const es = (ad, bek, olc) => sonuc(bek === olc, ad, bek === olc ? String(olc) : `beklenen=${bek} olculen=${olc}`);

// --- govde cikarma: suslu parantez sayarak fonksiyonun tamamini al ---------
function govdeCikar(kaynak, ad) {
  const i = kaynak.indexOf('async function ' + ad + '(');
  if (i < 0) throw new Error(ad + ' bulunamadi');
  const bas = kaynak.indexOf('{', i);
  let d = 0;
  for (let j = bas; j < kaynak.length; j++) {
    if (kaynak[j] === '{') d++;
    else if (kaynak[j] === '}') { d--; if (d === 0) return kaynak.slice(i, j + 1); }
  }
  throw new Error(ad + ' govdesi kapanmiyor');
}

// --- taklit ortam: fetch cagrilarini kaydeder ------------------------------
function uretecKur(govde, fetchTaklit) {
  const cagrilar = [];
  const fetch = async (url, opt) => { cagrilar.push({ url: String(url), opt: opt || {} }); return fetchTaklit(String(url), opt || {}); };
  const fn = new Function('fetch', 'SB_URL', 'SB_HEADERS', 'console',
    govde + '\n return yeniSiparisNoUret;')(
    fetch, 'https://ornek.test', { apikey: 'x' },
    { error() {}, warn() {}, log() {} });
  return { fn, cagrilar };
}
const yanit = (status, body) => ({
  ok: status >= 200 && status < 300, status,
  json: async () => body,
  text: async () => JSON.stringify(body),
});

for (const dosya of DOSYALAR) {
  console.log('\n--- ' + dosya + ' ---');
  const kaynak = readFileSync(KOK + dosya, 'utf8');
  let govde;
  try { govde = govdeCikar(kaynak, 'yeniSiparisNoUret'); }
  catch (e) { sonuc(false, dosya + ' govde cikarildi', e.message); continue; }

  // S1 — SUNUCUDAN URETIM: istek rpc/siparis_no_uret'e POST gider.
  {
    const { fn, cagrilar } = uretecKur(govde, async () => yanit(200, 'C00091115'));
    const no = await fn('C');
    es('S1a sunucunun verdigi numara donuyor', 'C00091115', no);
    const c = cagrilar[0] || {};
    sonuc(/\/rest\/v1\/rpc\/siparis_no_uret$/.test(c.url || ''),
      'S1b istek rpc/siparis_no_uret adresine gidiyor', c.url || '(istek yok)');
    es('S1c yontem POST', 'POST', (c.opt && c.opt.method) || '(yok)');
    sonuc(cagrilar.length === 1, 'S1d tek istek (listeleyip max+1 yapmiyor)', 'istek sayisi=' + cagrilar.length);
    let govdeJson = {};
    try { govdeJson = JSON.parse((c.opt && c.opt.body) || '{}'); } catch { /* yoksay */ }
    es('S1e onek govdede p_prefix olarak gidiyor', 'C', govdeJson.p_prefix);
  }

  // S2 — R oneki tasiniyor
  {
    const { fn, cagrilar } = uretecKur(govde, async () => yanit(200, 'R00091200'));
    const no = await fn('R');
    let g = {};
    try { g = JSON.parse((cagrilar[0] && cagrilar[0].opt.body) || '{}'); } catch { /* yoksay */ }
    es('S2a R oneki sunucuya gecirildi', 'R', g.p_prefix);
    es('S2b R numarasi donuyor', 'R00091200', no);
  }

  // S3 — SUNUCU HATASI: numara UYDURULMAZ, null doner
  {
    const { fn } = uretecKur(govde, async () => yanit(500, { message: 'bum' }));
    const no = await fn('C');
    sonuc(no === null, 'S3 sunucu 500 verince null doner (numara uydurulmaz)', 'donen=' + JSON.stringify(no));
  }

  // S4 — AG KOPTU: istisna halinde de null
  {
    const { fn } = uretecKur(govde, async () => { throw new Error('ag yok'); });
    const no = await fn('C');
    sonuc(no === null, 'S4 ag hatasinda null doner (rastgele numara YOK)', 'donen=' + JSON.stringify(no));
  }

  // S5 — BICIM DOGRULAMA: sunucu sacma deger donerse kabul edilmez
  {
    const { fn } = uretecKur(govde, async () => yanit(200, 'bozuk-deger'));
    const no = await fn('C');
    sonuc(no === null, 'S5 gecersiz bicimde yanit reddedilir', 'donen=' + JSON.stringify(no));
  }
  {
    const { fn } = uretecKur(govde, async () => yanit(200, null));
    const no = await fn('C');
    sonuc(no === null, 'S5b null yanit reddedilir', 'donen=' + JSON.stringify(no));
  }

  // S6 — CAGIRAN YER FAIL-CLOSED: numara yoksa akis durur ve ortu kapanir.
  {
    const satirlar = kaynak.split(/\r?\n/);
    // Iki cagiran bicimi: `const siparisNo = await ...` (iade, stok-takip) ve
    // `g.siparisNo = await ...` (siparis olustur, firma grubu dongusu).
    const i = satirlar.findIndex(l => /(?:const\s+siparisNo|g\.siparisNo)\s*=\s*await\s+yeniSiparisNoUret\(/.test(l));
    sonuc(i >= 0, 'S6a cagiran satir bulundu', i >= 0 ? 'satir ' + (i + 1) : 'yok');
    const blok = satirlar.slice(i + 1, i + 5).join('\n');
    sonuc(/!(?:g\.)?siparisNo/.test(blok) && /\breturn\b/.test(blok),
      'S6b numara yoksa cagiran DURUYOR', JSON.stringify(blok.trim().slice(0, 90)));
    sonuc(/hLD\(\)|hideLoading\(\)/.test(blok),
      'S6c erken cikista yukleme ortusu kapaniyor', JSON.stringify(blok.trim().slice(0, 90)));
  }

  // S7 — ESKI UYDURMA KOD GOVDEDEN KALKTI
  sonuc(!/maxNo/.test(govde), 'S7a govdede maxNo (istemci max+1) yok',
    /maxNo/.test(govde) ? 'hala var' : 'temiz');
  sonuc(!/Math\.random/.test(govde), 'S7b govdede Math.random (rastgele numara) yok',
    /Math\.random/.test(govde) ? 'hala var' : 'temiz');
  sonuc(!/padStart/.test(govde), 'S7c govde numarayi kendisi KURMUYOR (padStart yok)',
    /padStart/.test(govde) ? 'hala var' : 'temiz');
}

console.log(`\nSONUC: ${ok} gecti, ${fail} kaldi`);
process.exit(fail === 0 ? 0 : 1);
