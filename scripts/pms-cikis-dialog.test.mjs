// ===========================================================================
// PMS CHECK-OUT ONAY PENCERESI — GERCEK TARAYICIDA IKI YOL
// ===========================================================================
// Olculen: pms-oda-plani.html icindeki `cikisAc()` fonksiyonunun GERCEK
// window.confirm penceresi, GERCEK bir tarayicida (Chrome), GERCEK dialog
// olayiyla iki yonde de ele alinarak:
//
//   YOL 1 (Iptal) : dialog REDDEDILIR  -> hic cikis istegi gitmemeli;
//                   rezervasyon, oda ve temizlik gorevi DEGISMEMELI.
//   YOL 2 (Tamam) : dialog KABUL EDILIR -> TEK cikis istegi gitmeli;
//                   rezervasyon cikis_yapildi, oda bos/kirli ve cikis
//                   temizligi gorevi olusmali.
//
// window.confirm DEGISTIRILMEZ, sarilmaz, atlanmaz. Her adimda yerli oldugu
// (`[native code]`) ayrica olculur. Dialog, Chrome DevTools Protokolu'nun
// `Page.javascriptDialogOpening` olayi ile yakalanir ve
// `Page.handleJavaScriptDialog` ile kabul/ret edilir — yani tarayicinin
// kendi dialog olayi kullanilir.
//
// YENI BAGIMLILIK YOKTUR: Node 22+ yerlesik `WebSocket` sinifi ve sistemde
// kurulu Chrome yeterlidir. Playwright/Puppeteer KURULMAZ.
//
// Izole ortam: scripts/pms-tarayici-ortami.mjs alt surec olarak baslatilir
// (Docker veritabani + PostgREST + depodaki GERCEK ekran dosyalari). Uretime
// baglanmaz; yalniz yapay misafir verisi kullanilir.
//
// Bu dosya YEREL kanittir; CANLI KABUL YERINE GECMEZ.
// Kullanim: node scripts/pms-cikis-dialog.test.mjs
// ===========================================================================
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const PORT = Number(process.env.PMS_DIALOG_PORT || 4186);
const CDP_PORT = Number(process.env.PMS_DIALOG_CDP || 9333);
const ADRES = `http://127.0.0.1:${PORT}/pms-oda-plani.html`;
const KOK = new URL('..', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');

let ok = 0, fail = 0;
const sonuc = (g, ad, ek) => {
  console.log((g ? 'OK   ' : 'FAIL ') + ad + (ek ? ' — ' + ek : ''));
  if (g) ok++; else fail++;
};
const bekle = (ms) => new Promise((r) => setTimeout(r, ms));

const CHROME_ADAYLARI = [
  process.env.PMS_CHROME,
  'C:/Program Files/Google/Chrome/Application/chrome.exe',
  'C:/Program Files (x86)/Google/Chrome/Application/chrome.exe',
  'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
  'C:/Program Files/Microsoft/Edge/Application/msedge.exe',
  '/usr/bin/google-chrome', '/usr/bin/chromium', '/usr/bin/chromium-browser',
].filter(Boolean);

// --- CDP istemcisi (yerlesik WebSocket; harici paket yok) -----------------
function cdpIstemci(wsUrl) {
  const ws = new WebSocket(wsUrl);
  let sira = 0;
  const bekleyen = new Map();
  const dinleyiciler = new Map();
  const hazir = new Promise((coz, red) => { ws.onopen = () => coz(); ws.onerror = (e) => red(new Error('ws: ' + e.message)); });
  ws.onmessage = (ev) => {
    const m = JSON.parse(ev.data);
    if (m.id && bekleyen.has(m.id)) {
      const { coz, red } = bekleyen.get(m.id); bekleyen.delete(m.id);
      m.error ? red(new Error(m.method + ': ' + m.error.message)) : coz(m.result);
    } else if (m.method) {
      (dinleyiciler.get(m.method) || []).forEach((f) => f(m.params));
    }
  };
  const cagir = (method, params = {}) => new Promise((coz, red) => {
    const id = ++sira; bekleyen.set(id, { coz, red });
    ws.send(JSON.stringify({ id, method, params }));
  });
  const uzerine = (method, f) => {
    if (!dinleyiciler.has(method)) dinleyiciler.set(method, []);
    dinleyiciler.get(method).push(f);
  };
  return { hazir, cagir, uzerine, kapat: () => ws.close() };
}

let ortam, chrome, profil, istemci;
let CHROME_PID = null, ORTAM_PID = null;
// pms-tarayici-ortami.mjs -> barOrtami({ ad: 'pms-tarayici' }) konteynerleri.
const KONTEYNERLER = ['pms-tarayici-rest', 'pms-tarayici-db'];
const bitti = (c) => (c && c.exitCode === null && c.signalCode === null ? false : true);
// Kapanis: YALNIZ bu kosumun baslattigi sureclere dokunur. Kullanicinin acik
// tarayicilarina ASLA dokunulmaz (pid'ler bu kosumda spawn edilenlerdir).
const kapat = async () => {
  try { istemci && istemci.kapat(); } catch {}
  // Ortam alt sureci: SIGINT ile kendi Docker temizligini yapsin, sonra bekle.
  try { if (ortam && !bitti(ortam)) ortam.kill('SIGINT'); } catch {}
  try { if (chrome && !bitti(chrome)) chrome.kill(); } catch {}
  for (let i = 0; i < 40 && ((chrome && !bitti(chrome)) || (ortam && !bitti(ortam))); i++) {
    await new Promise((r) => setTimeout(r, 250));
  }
  try { if (ortam && !bitti(ortam)) ortam.kill('SIGKILL'); } catch {}
  try { if (chrome && !bitti(chrome)) chrome.kill('SIGKILL'); } catch {}
  for (let i = 0; i < 20 && ((chrome && !bitti(chrome)) || (ortam && !bitti(ortam))); i++) {
    await new Promise((r) => setTimeout(r, 250));
  }
  try { profil && fs.rmSync(profil, { recursive: true, force: true }); } catch {}
  // Windows'ta child.kill('SIGINT') alt surecin SIGINT isleyicisini
  // CALISTIRMAZ; dolayisiyla ortamin kendi Docker temizligi kosmayabilir.
  // "Islem bitti" = "kaynaklar temizlendi" VARSAYILMAZ: bu kosumun
  // olusturdugu konteynerler ADIYLA kaldirilir. Baska hicbir konteynere ve
  // kullanicinin acik tarayicilarina DOKUNULMAZ.
  try {
    const { execFileSync } = await import('node:child_process');
    for (const ad of KONTEYNERLER) {
      try { execFileSync('docker', ['rm', '-f', ad], { stdio: 'ignore' }); } catch {}
    }
  } catch {}
};
process.on('SIGINT', async () => { await kapat(); process.exit(130); });

try {
  // --- 1) Izole ortami baslat --------------------------------------------
  console.log('izole ortam baslatiliyor (Docker + PostgREST + gercek ekranlar)...');
  ortam = spawn(process.execPath, [path.join(KOK, 'scripts', 'pms-tarayici-ortami.mjs')], {
    cwd: KOK, env: { ...process.env, PMS_TARAYICI_PORT: String(PORT) },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  ORTAM_PID = ortam.pid;
  let ortamCikti = '';
  ortam.stdout.on('data', (d) => { ortamCikti += d; });
  ortam.stderr.on('data', (d) => { ortamCikti += d; });
  const hazirOl = async () => {
    for (let i = 0; i < 100; i++) {
      if (/TARAYICI ORTAMI HAZIR/.test(ortamCikti)) return true;
      if (ortam.exitCode !== null) throw new Error('ortam dustu:\n' + ortamCikti.slice(-800));
      await bekle(1000);
    }
    throw new Error('ortam 100 sn icinde hazir olmadi:\n' + ortamCikti.slice(-800));
  };
  await hazirOl();
  sonuc(true, 'D0 izole ortam hazir', ADRES);

  // --- 2) Gercek tarayiciyi baslat ---------------------------------------
  const ikili = CHROME_ADAYLARI.find((p) => fs.existsSync(p));
  if (!ikili) throw new Error('kurulu Chrome/Edge bulunamadi; PMS_CHROME ile yol verin');
  profil = fs.mkdtempSync(path.join(os.tmpdir(), 'pms-dialog-'));
  const chromeArgs = [
    '--headless=new', '--disable-gpu', '--no-first-run', '--no-default-browser-check',
    '--disable-extensions',
    // PD-1: tarayici SANDBOX'I ACIK. '--no-sandbox' KALDIRILDI; gercek
    // dialog olcumu icin guvenlik katmanini kapatmak gerekmiyor. Normal
    // sandbox ile baslatilamazsa sebep RAPORLANIR; otomatik olarak
    // kapatmaya veya baska bir gevsetmeye DONULMEZ.
    `--user-data-dir=${profil}`, `--remote-debugging-port=${CDP_PORT}`, ADRES,
  ];
  chrome = spawn(ikili, chromeArgs, { stdio: ['ignore', 'pipe', 'pipe'] });
  CHROME_PID = chrome.pid;
  let chromeCikti = '';
  chrome.stdout.on('data', (d) => { chromeCikti += d; });
  chrome.stderr.on('data', (d) => { chromeCikti += d; });
  let hedefWs = null;
  for (let i = 0; i < 60; i++) {
    try {
      const l = await (await fetch(`http://127.0.0.1:${CDP_PORT}/json/list`)).json();
      const s = l.find((t) => t.type === 'page' && t.webSocketDebuggerUrl);
      if (s) { hedefWs = s.webSocketDebuggerUrl; break; }
    } catch {}
    await bekle(500);
  }
  if (!hedefWs) {
    const cikti = (chromeCikti || '').slice(-600);
    throw new Error('CDP sayfa hedefi bulunamadi (sandbox ACIK baslatma).\n'
      + '  PD-1: guvenlik gevsetmesine DONULMEDI. Tarayici ciktisi:\n  ' + cikti
      + '\n  cikis kodu=' + chrome.exitCode);
  }
  sonuc(true, 'D1a tarayici SANDBOX ACIK basladi (--no-sandbox YOK)',
    chromeArgs.some((a) => a === '--no-sandbox') ? 'BAYRAK VAR!' : 'bayrak yok');
  istemci = cdpIstemci(hedefWs);
  await istemci.hazir;
  await istemci.cagir('Page.enable');
  await istemci.cagir('Runtime.enable');
  await istemci.cagir('Network.enable');
  sonuc(true, 'D1 gercek tarayici CDP ile bagli', path.basename(ikili) + ' (headless)');

  // --- 3) Dialog ve ag kayitlari ----------------------------------------
  const dialoglar = [];          // gercek dialog olaylari
  const cikisIstekleri = [];     // rpc/pms_check_out POST'lari
  let kabulEt = null;            // o anki yol icin karar (true/false)
  istemci.uzerine('Page.javascriptDialogOpening', async (p) => {
    dialoglar.push({ tur: p.type, metin: p.message, karar: kabulEt });
    await istemci.cagir('Page.handleJavaScriptDialog', { accept: kabulEt === true });
  });
  istemci.uzerine('Network.requestWillBeSent', (p) => {
    if (/\/rpc\/pms_check_out/.test(p.request.url)) {
      cikisIstekleri.push({ yontem: p.request.method, url: p.request.url, govde: p.request.postData || null });
    }
  });

  const degerlendir = async (ifade) => {
    const r = await istemci.cagir('Runtime.evaluate', {
      expression: `(async () => { ${ifade} })()`, awaitPromise: true, returnByValue: true,
    });
    if (r.exceptionDetails) throw new Error('sayfa hatasi: ' + JSON.stringify(r.exceptionDetails.exception || r.exceptionDetails));
    return r.result.value;
  };

  // Ekranin yuklenmesini bekle (urunun kendi veri yolundan). YALNIZ ODALAR
  // yetmez: cikis dugmesi, rezervasyonlar da yuklenip render bitmeden
  // olusmadigi icin DUGMENIN KENDISI beklenir.
  let hazirDurum = null;
  for (let i = 0; i < 80; i++) {
    hazirDurum = await degerlendir(`
      return {
        odalar: (typeof ODALAR !== 'undefined' && ODALAR.length) || 0,
        cikisDugmesi: !!document.querySelector('button[onclick^="cikisAc"]'),
      };
    `);
    if (hazirDurum.odalar > 0 && hazirDurum.cikisDugmesi) break;
    await bekle(500);
  }
  sonuc(!!(hazirDurum && hazirDurum.odalar > 0 && hazirDurum.cikisDugmesi),
    'D1b ekran yuklendi ve cikis dugmesi olustu',
    hazirDurum ? hazirDurum.odalar + ' oda, dugme=' + hazirDurum.cikisDugmesi : 'olculemedi');

  // confirm YERLI mi? (degistirilmedigi her adimda olculur)
  const yerliMi = () => degerlendir('return /\\[native code\\]/.test(String(window.confirm));');
  sonuc(await yerliMi(), 'D2 window.confirm YERLI (degistirilmedi/sarilmadi)');

  // Cikis dugmesi sunan GERCEK bir oda sec (urunun kendi dugmesi).
  const hedef = await degerlendir(`
    const b = document.querySelector('button[onclick^="cikisAc"]');
    if (!b) return null;
    const id = b.getAttribute('onclick').match(/cikisAc\\('([^']+)'\\)/)[1];
    const o = ODALAR.find(x => x.id === id);
    const d = doluRez(o);
    return { odaId: id, odaNo: o.oda_no, rezId: d && d.rez.id };
  `);
  if (!hedef || !hedef.rezId) throw new Error('cikis sunan oda bulunamadi (tohum beklenenden farkli)');
  sonuc(true, 'D3 cikis dugmesi sunan oda bulundu', 'oda ' + hedef.odaNo);

  // Durum fotografi — urunun kendi REST yolundan.
  const fotoIfade = `
    const al = async (y) => (await fetch(y, { headers: SB_HEADERS })).json();
    const rez = (await al('/rest/v1/pms_rezervasyonlar?id=eq.${hedef.rezId}&select=rezervasyon_no,durum'))[0];
    const oda = (await al('/rest/v1/pms_odalar?id=eq.${hedef.odaId}&select=oda_no,kullanim_durumu,temizlik_durumu'))[0];
    // PD-2: yalniz SAYI degil; kimlik ve ilgili alanlar, SIRALI.
    const gorevler = (await al('/rest/v1/pms_housekeeping_gorevleri?oda_id=eq.${hedef.odaId}'
      + '&select=id,oda_id,gorev_tipi,durum&order=id'))
      .map((g) => ({ id: g.id, oda_id: g.oda_id, gorev_tipi: g.gorev_tipi, durum: g.durum }))
      .sort((a, b) => a.id.localeCompare(b.id));
    return { rez, oda, gorevSayisi: gorevler.length, gorevler };
  `;
  const foto = () => degerlendir(fotoIfade);

  // ======================================================================
  // PD-2 DOGRULAYICILARI — sayi degil, KIMLIK ve ALANLAR
  // ======================================================================
  const anahtar = (g) => [g.id, g.oda_id, g.gorev_tipi, g.durum].join('|');
  const dizi = (l) => l.map(anahtar).sort().join('\n');
  // Iptal yolu: gorev kumesi KIMLIK ve ALANLARLA birebir ayni olmali.
  const gorevlerAyniMi = (a, b) => dizi(a) === dizi(b);
  // Kabul yolu: onceki kimlik kumesine gore TAM BIR yeni gorev; yeni gorev
  // hedef odaya ait 'cikis_temizligi' ve 'bekliyor'; ESKILER degismemis.
  const tekYeniGorev = (once, sonra, odaId) => {
    const onceId = new Set(once.map((g) => g.id));
    const yeniler = sonra.filter((g) => !onceId.has(g.id));
    const kalanlar = sonra.filter((g) => onceId.has(g.id));
    if (yeniler.length !== 1) return { tamam: false, sebep: 'yeni gorev sayisi=' + yeniler.length };
    if (!gorevlerAyniMi(once, kalanlar)) return { tamam: false, sebep: 'ESKI gorevler degismis' };
    const y = yeniler[0];
    if (y.oda_id !== odaId) return { tamam: false, sebep: 'yeni gorev baska odaya ait' };
    if (y.gorev_tipi !== 'cikis_temizligi') return { tamam: false, sebep: 'yeni gorev tipi=' + y.gorev_tipi };
    if (y.durum !== 'bekliyor') return { tamam: false, sebep: 'yeni gorev durumu=' + y.durum };
    return { tamam: true, sebep: y.gorev_tipi + '/' + y.durum + ' oda=' + y.oda_id.slice(-3) };
  };

  // Dogrulayicilarin KENDISI sinanir: yanlis tur ve ayni sayida DEGISTIRILMIS
  // gorev fiksturu bu kontrolu DUSURMELI; saglikli kontrol GECMELI.
  {
    const O = hedef.odaId;
    const g1 = { id: 'a', oda_id: O, gorev_tipi: 'gunluk_temizlik', durum: 'bekliyor' };
    const g2 = { id: 'b', oda_id: O, gorev_tipi: 'cikis_temizligi', durum: 'bekliyor' };
    // (a) saglikli: tam bir yeni cikis_temizligi gorevi
    sonuc(tekYeniGorev([g1], [g1, g2], O).tamam,
      'D2a POZITIF KONTROL: tam bir yeni cikis_temizligi gorevi KABUL edilir');
    // (b) yanlis TUR
    const yt = tekYeniGorev([g1], [g1, { ...g2, gorev_tipi: 'gunluk_temizlik' }], O);
    sonuc(!yt.tamam, 'D2b NEGATIF: yanlis TURDE yeni gorev REDDEDILIR', yt.sebep);
    // (c) yanlis DURUM
    const yd = tekYeniGorev([g1], [g1, { ...g2, durum: 'tamamlandi' }], O);
    sonuc(!yd.tamam, 'D2c NEGATIF: yanlis DURUMDA yeni gorev REDDEDILIR', yd.sebep);
    // (d) baska ODA
    const yo = tekYeniGorev([g1], [g1, { ...g2, oda_id: 'baska-oda' }], O);
    sonuc(!yo.tamam, 'D2d NEGATIF: BASKA odaya ait yeni gorev REDDEDILIR', yo.sebep);
    // (e) ESKI gorev degismis (sayi ayni kalsa da)
    const ed = tekYeniGorev([g1], [{ ...g1, durum: 'tamamlandi' }, g2], O);
    sonuc(!ed.tamam, 'D2e NEGATIF: ESKI gorev degismisse REDDEDILIR', ed.sebep);
    // (f) AYNI SAYIDA ama DEGISTIRILMIS gorev -> 'degismedi' DENEMEZ
    sonuc(!gorevlerAyniMi([g1], [{ ...g1, durum: 'tamamlandi' }]),
      'D2f NEGATIF: ayni sayida DEGISTIRILMIS gorev "degismedi" sayilmaz');
    sonuc(gorevlerAyniMi([g1, g2], [g2, g1]),
      'D2g POZITIF: sira farki "degismis" sayilmaz (sirali karsilastirma)');
  }

  // GERCEK fare tiklamasi: dialog acildiginda bloklanacagi icin tiklama
  // SONUCU BEKLENMEZ; dialog olayi gelince ele alinir, sonra beklenir.
  const gercekTikla = async () => {
    const k = await degerlendir(`
      const b = document.querySelector('button[onclick^="cikisAc"]');
      b.scrollIntoView({ block: 'center' });
      const r = b.getBoundingClientRect();
      return { x: Math.round(r.left + r.width / 2), y: Math.round(r.top + r.height / 2) };
    `);
    const ortak = { x: k.x, y: k.y, button: 'left', clickCount: 1 };
    const bas = istemci.cagir('Input.dispatchMouseEvent', { type: 'mousePressed', ...ortak });
    const birak = istemci.cagir('Input.dispatchMouseEvent', { type: 'mouseReleased', ...ortak });
    await bas.catch(() => {});
    await birak.catch(() => {});
  };

  // ======================================================================
  // YOL 1 — IPTAL: dialog REDDEDILIR
  // ======================================================================
  console.log('\n--- YOL 1: IPTAL (dialog reddedilir) ---');
  const once1 = await foto();
  dialoglar.length = 0; cikisIstekleri.length = 0;
  kabulEt = false;
  await gercekTikla();
  await bekle(1500);
  const sonra1 = await foto();

  sonuc(dialoglar.length === 1 && dialoglar[0].tur === 'confirm',
    'D4 GERCEK confirm dialogu acildi (iptal yolu)',
    dialoglar.length ? dialoglar[0].tur + ': ' + JSON.stringify(dialoglar[0].metin.slice(0, 60)) : 'dialog YOK');
  sonuc(await yerliMi(), 'D5 confirm iptal sonrasi hala YERLI');
  sonuc(cikisIstekleri.length === 0, 'D6 IPTAL: cikis istegi GONDERILMEDI',
    cikisIstekleri.length + ' istek');
  sonuc(sonra1.rez.durum === once1.rez.durum,
    'D7 IPTAL: rezervasyon durumu DEGISMEDI', once1.rez.durum + ' -> ' + sonra1.rez.durum);
  sonuc(sonra1.oda.kullanim_durumu === once1.oda.kullanim_durumu
     && sonra1.oda.temizlik_durumu === once1.oda.temizlik_durumu,
    'D8 IPTAL: oda durumu DEGISMEDI',
    `${once1.oda.kullanim_durumu}/${once1.oda.temizlik_durumu} -> ${sonra1.oda.kullanim_durumu}/${sonra1.oda.temizlik_durumu}`);
  sonuc(gorevlerAyniMi(once1.gorevler, sonra1.gorevler),
    'D9 IPTAL: temizlik gorevleri KIMLIK ve ALANLARLA birebir ayni',
    once1.gorevSayisi + ' gorev; ozet ' + (dizi(once1.gorevler) === dizi(sonra1.gorevler) ? 'esit' : 'FARKLI'));

  // ======================================================================
  // YOL 2 — TAMAM: dialog KABUL EDILIR
  // ======================================================================
  console.log('\n--- YOL 2: TAMAM (dialog kabul edilir) ---');
  dialoglar.length = 0; cikisIstekleri.length = 0;
  kabulEt = true;
  await gercekTikla();
  await bekle(3000);
  const sonra2 = await foto();

  sonuc(dialoglar.length === 1 && dialoglar[0].tur === 'confirm',
    'D10 GERCEK confirm dialogu acildi (tamam yolu)',
    dialoglar.length ? dialoglar[0].tur : 'dialog YOK');
  sonuc(await yerliMi(), 'D11 confirm kabul sonrasi hala YERLI');
  sonuc(cikisIstekleri.length === 1,
    'D12 TAMAM: TEK cikis istegi gonderildi', cikisIstekleri.length + ' istek');
  sonuc(cikisIstekleri.length === 1 && cikisIstekleri[0].yontem === 'POST'
     && String(cikisIstekleri[0].govde || '').includes(hedef.rezId),
    'D13 TAMAM: istek dogru rezervasyon icin POST edildi',
    cikisIstekleri[0] ? cikisIstekleri[0].yontem + ' ' + String(cikisIstekleri[0].govde).slice(0, 70) : 'istek YOK');
  sonuc(sonra2.rez.durum === 'cikis_yapildi',
    'D14 TAMAM: rezervasyon cikis_yapildi', once1.rez.durum + ' -> ' + sonra2.rez.durum);
  sonuc(sonra2.oda.kullanim_durumu === 'bos' && sonra2.oda.temizlik_durumu === 'kirli',
    'D15 TAMAM: oda bos/kirli',
    `${sonra1.oda.kullanim_durumu}/${sonra1.oda.temizlik_durumu} -> ${sonra2.oda.kullanim_durumu}/${sonra2.oda.temizlik_durumu}`);
  const yg = tekYeniGorev(sonra1.gorevler, sonra2.gorevler, hedef.odaId);
  sonuc(yg.tamam,
    'D16 TAMAM: hedef odaya ait TAM BIR yeni cikis_temizligi/bekliyor gorevi olustu; eskiler degismedi',
    sonra1.gorevSayisi + ' -> ' + sonra2.gorevSayisi + '; ' + yg.sebep);

  console.log('\nBu YEREL kanittir; canli kabul yerine GECMEZ.');
} catch (e) {
  console.error('\nDUR: ' + (e && e.message));
  fail++;
}

// ===========================================================================
// KOSUM SONRASI KAYNAK TEMIZLIGI — olculur, varsayilmaz
// ===========================================================================
await kapat();
console.log('\n--- kaynak temizligi (yalniz BU kosumun kaynaklari) ---');
const canli = (pid) => {
  if (!pid) return false;
  try { process.kill(pid, 0); return true; } catch { return false; }
};
sonuc(!canli(CHROME_PID), 'T1 bu kosumun Chrome sureci kapandi', 'pid=' + CHROME_PID);
sonuc(!canli(ORTAM_PID), 'T2 ortam alt sureci kapandi', 'pid=' + ORTAM_PID);
sonuc(!profil || !fs.existsSync(profil), 'T3 gecici tarayici profili silindi', String(profil));
try {
  const { execFileSync } = await import('node:child_process');
  const ad = execFileSync('docker', ['ps', '-a', '--format', '{{.Names}}'], { encoding: 'utf8' })
    .split(/\r?\n/).filter(Boolean);
  const kalan = ad.filter((n) => /^pms-tarayici(-|$)/.test(n));
  sonuc(kalan.length === 0, 'T4 test konteynerleri kalmadi (adla kaldirildi, sonra olculdu)',
    kalan.length ? 'KALAN: ' + kalan.join(',') : KONTEYNERLER.join(',') + ' yok');
  sonuc(ad.length > 0, 'T5 docker olcumu gercekten yapildi (baska konteynerlere dokunulmadi)',
    ad.length + ' konteyner goruldu, yalnizca ' + KONTEYNERLER.length + ' tanesi kaldirildi');
} catch (e) {
  sonuc(false, 'T4 konteyner olcumu yapilamadi', String(e && e.message));
}
console.log('\n======================================================================');
console.log(`KESIN SONUC: ${ok} gecti, ${fail} kaldi`);
console.log('======================================================================');
process.exit(fail === 0 ? 0 : 1);
