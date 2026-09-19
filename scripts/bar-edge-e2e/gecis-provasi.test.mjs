// ===========================================================================
// BAR A1 — YAYIN GECIS PROVASI (izole; uretime BAGLANMAZ)
// ===========================================================================
// Soru: onerilen yayin sirasinin her araliginda ESKI ve YENI parcalar birlikte
// nasil davraniyor? Eski parcalar origin/main'den alinir (ekranlar + eski
// rapid-handler kodu); yeni parcalar bu daldan. Ekranlar gercek betikleriyle
// (harness), gercek Edge Runtime / GoTrue / PostgREST uzerinden kosar.
//
//   Adim 1  menu push (yeni bar-menu)           — veritabani ESKI
//   Adim 2  A1 migration                        — eski garson/kuyruk/stok-takip, eski rapid-handler
//   Adim 3  kalan ekranlar push                 — eski rapid-handler hala canli
//   Adim 4  rapid-handler deploy                — (bar-edge-e2e.test.mjs Evre A)
//
// Her satir bir OLCUMDUR: beklenen, o aralikta gorulmesi gereken davranistir;
// kusurlu davranis da olcum olarak kaydedilir (raporda risk olarak yazilir).
// ===========================================================================
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { execSync } from 'node:child_process';
import { e2eOrtami } from './ortam.mjs';
import { kok } from '../bar-test-ortam.mjs';
import { K, M, BAR } from '../bar-a1-tohum.mjs';
import { barEkranKur } from '../bar-ekran-harness.mjs';
import { ekranKur } from '../stok-ekran-harness.mjs';

let ok = 0, fail = 0;
const sonuc = (g, ad, ek) => { console.log((g ? 'OK   ' : 'FAIL ') + ad + (ek ? ' — ' + ek : '')); if (g) ok++; else fail++; };
const bekle = (ms) => new Promise((r) => setTimeout(r, ms));
process.on('unhandledRejection', () => {});   // eski ekranlarin init hatalari olcumu dusurmesin

// --- Eski surum: origin/main ---------------------------------------------
const ESKI = mkdtempSync(path.join(tmpdir(), 'bar-gecis-eski-')).replace(/\\/g, '/') + '/';
execSync(`git -C "${kok}" archive origin/main -- "*.html" "*.js" | tar -x -C "${ESKI}"`, { shell: 'bash' });
const EK = mkdtempSync(path.join(tmpdir(), 'bar-gecis-ek-')).replace(/\\/g, '/');
mkdirSync(path.join(EK, 'masa-yonetim-eski'));
writeFileSync(path.join(EK, 'masa-yonetim-eski', 'index.ts'),
  execSync(`git -C "${kok}" show origin/main:docs/kurulum/musteri-projesi/masa-yonetim/index.ts`, { encoding: 'utf8' }));
const eskiRev = execSync(`git -C "${kok}" rev-parse --short origin/main`, { encoding: 'utf8' }).trim();

// Eski rapid-handler kullaniciyi e-posta onekinden (kullanicilar.id) bulur;
// uretimdeki e-posta bicimi bu. GoTrue kimligi tohumdaki auth_user_id ile ayni.
const KISI = {
  bar810: { id: K.BAR810.sub, email: '33333333-0000-0000-0000-000000000810@test.local' },
  pasif: { id: K.PASIF.sub, email: '33333333-0000-0000-0000-0000000000aa@test.local' },
  depo810: { id: K.DEPO810.sub, email: '33333333-0000-0000-0000-0000000000cc@test.local' },
};
async function girisler(E) {
  const t = {};
  for (const [ad, k] of Object.entries(KISI)) { await E.kullaniciOlustur(k.id, k.email); t[ad] = await E.girisYap(k.email); }
  return t;
}
const musteri = (E, { eskiRapid = false } = {}) => (yol, sec) =>
  fetch(`http://127.0.0.1:${E.P.musGecit}` + (eskiRapid ? yol.replace('/functions/v1/rapid-handler', '/functions/v1/rapid-handler-eski') : yol), sec);
const REST = (E) => `http://127.0.0.1:${E.P.anaRest}`;
async function menuYayinla(E, jwt) {
  const r = await E.fonksiyon('smooth-service', {}, { 'x-staff-token': jwt });
  if (!r.json?.ok) throw new Error('menu yayini: ' + r.metin);
}
function menuEkrani(E, { eski }) {
  return barEkranKur({ html: 'bar-menu.html', restUrl: REST(E), jwt: 'yok', kullanici: {}, arama: '?t=tok-810-a',
    kaynakKok: eski ? ESKI : kok, musteriAnon: E.anon, musteriFetch: musteri(E) });
}
async function menuSiparis(ekran, kalemler, oda) {
  for (let i = 0; i < 100 && !ekran.calistir('MENU.length'); i++) await bekle(50);
  ekran.calistir(`SEPET=${JSON.stringify(Object.fromEntries(kalemler.map(([id, adet, ucretli]) => [id, { adet, ucretli }])))};`);
  ekran.el('odaNo').value = oda || '';
  await ekran.calistir('gonder()');
  return ekran.el('mesaj').textContent;
}

// ======================= Adim 1: yeni menu, ESKI veritabani =======================
const A = e2eOrtami({ ad: 'bar-gecis-1', a1: false, ekDizin: EK });
try {
  await A.kur();
  console.log(`adim 1 — veritabani A1 OLMADAN; eski surum ${eskiRev}\n`);
  const J = await girisler(A);
  await menuYayinla(A, J.bar810);
  const yeni = menuEkrani(A, { eski: false });
  const m1 = await menuSiparis(yeni, [[M.VISKI, 1, true]], '101');
  const gonderilen = JSON.parse(yeni.kayit.istekler.find((r) => r.url.includes('hyper-api')).govde);
  sonuc(/Siparişiniz alındı/.test(m1) && gonderilen.kalemler[0].gosterilen_fiyat === 250
     && A.ana.sql(`select count(*) from public.bar_siparisleri;`).out === '1',
    'G1 YENI menu ekrani ESKI veritabaniyla ucretli siparis verebiliyor (fiyat alani yok sayiliyor)', m1);

  // --- Alternatif sira: TUM yeni ekranlar migration'dan ONCE yayinlanirsa ---
  const tekA = (q) => A.ana.sql(q).out;
  const yk = barEkranKur({ html: 'bar-siparis-kuyrugu.html', restUrl: REST(A), jwt: J.bar810,
    kullanici: { id: K.BAR810.sub, ad: 'Bar 810', rol: 'bar', otel_id: '810' }, yetkiler: { bar_siparis_yonetimi: 'kayit' },
    musteriAnon: A.anon, musteriFetch: musteri(A) });
  const sipA = A.ana.kimlikle(K.BAR810, `select public.bar_siparis_olustur('810','${BAR}','M5',null,'[{"menu_urun_id":"${M.BIRA}","adet":1}]'::jsonb);`).out;
  for (let i = 0; i < 100 && !yk.calistir('SIPARISLER.length'); i++) await bekle(50);
  yk.promptVer('Musteri vazgecti');
  await yk.calistir(`iptalEt('${sipA}')`);
  sonuc(tekA(`select durum::text from public.bar_siparisleri where id='${sipA}';`) === 'yeni',
    'G1b YENI kuyruk + ESKI veritabani: iptal CALISMAZ (yeni RPC imzasi yok); siparis acik kalir',
    (yk.kayit.toastlar.slice(-1)[0] || '').slice(0, 90));
  await yk.calistir(`durumGuncelle('${sipA}','hazirlaniyor')`);
  await yk.calistir(`durumGuncelle('${sipA}','hazir')`);
  await yk.calistir(`teslimEt('${sipA}')`);
  sonuc(tekA(`select durum::text from public.bar_siparisleri where id='${sipA}';`) === 'teslim_edildi',
    'G1c YENI kuyruk + ESKI veritabani: hazirlik ve teslim calisir');
  A.ana.sql(`create policy test_yalniz_okuma on public.sayim_oturumlari for select to authenticated using (true);
    create policy test_yalniz_okuma on public.sayim_detaylari for select to authenticated using (true);
    update public.stok set miktar = 100 where urun_kodu='LIMON' and depo_kodu='${BAR}';
    insert into public.sayim_oturumlari (id, depo_kodu, otel_id, olusturan_ad, durum, toplam_urun_sayisi)
      values ('99999999-0000-0000-0000-00000000aa02','${BAR}','810','Test','onay_bekliyor',1);
    insert into public.sayim_detaylari (oturum_id, urun_kodu, urun_adi, sistem_miktar, sayilan_miktar, fark)
      values ('99999999-0000-0000-0000-00000000aa02','LIMON','Limon',100,90,-10);`);
  const stA = ekranKur({ restUrl: REST(A), jwt: J.depo810, depo: BAR, rol: 'cost_control' });
  await bekle(1500);
  await stA.calistir('sayimOnayBekleyenleriYukle()');
  await stA.calistir(`sayimOnayla('99999999-0000-0000-0000-00000000aa02')`);
  sonuc(tekA(`select miktar::text from public.stok where urun_kodu='LIMON' and depo_kodu='${BAR}';`) === '100.000'
     && tekA(`select durum from public.sayim_oturumlari where id='99999999-0000-0000-0000-00000000aa02';`) === 'onay_bekliyor',
    'G1d YENI stok-takip + ESKI veritabani: sayim onayi GUVENLI basarisiz olur (RPC yok) — stok ve oturum degismez');
} catch (e) { sonuc(false, 'beklenmeyen hata (adim 1)', e.stack || e.message); console.log(A.edgeGunlugu().slice(-1500)); }
finally { A.temizle(); }

// ======================= Adim 2-3: A1 uygulanmis =======================
const B = e2eOrtami({ ad: 'bar-gecis-2', a1: true, ekDizin: EK });
try {
  await B.kur();
  console.log('\nadim 2-3 — A1 uygulanmis veritabani\n');
  const J = await girisler(B);
  await menuYayinla(B, J.bar810);
  const tek = (q) => B.ana.sql(q).out;
  const stok = (kod) => tek(`select miktar::text from public.stok where urun_kodu='${kod}' and depo_kodu='${BAR}';`);

  // --- menu push'u migration'dan SONRAYA kalirsa (eski menu) ---
  const eskiMenu = menuEkrani(B, { eski: true });
  const m2 = await menuSiparis(eskiMenu, [[M.VISKI, 1, true]], '101');
  const eskiMenu2 = menuEkrani(B, { eski: true });
  const m3 = await menuSiparis(eskiMenu2, [[M.BIRA, 1, false]], '');
  sonuc(/FIYAT_DEGISTI/.test(m2) && /Siparişiniz alındı/.test(m3),
    'G2 ESKI menu + A1: ucretli sipariste ham FIYAT_DEGISTI metni gorunur, siparis alinmaz; ucretsiz calisir', m2.slice(0, 90));

  // --- eski garson ---
  const garson = (eski, eskiRapid) => barEkranKur({ html: 'bar-garson.html', restUrl: REST(B), jwt: J.bar810,
    kullanici: { id: K.BAR810.sub, ad: 'Bar 810', rol: 'bar', otel_id: '810' }, yetkiler: { bar_siparis_yonetimi: 'kayit' },
    kaynakKok: eski ? ESKI : kok, musteriAnon: B.anon, musteriFetch: musteri(B, { eskiRapid }) });
  const g = garson(true, true);
  for (let i = 0; i < 100 && !g.calistir('MASALAR.length'); i++) await bekle(50);
  g.el('otelSec').value = '810'; g.calistir('otelDegisti()');
  g.el('barSec').value = BAR; g.calistir('barDegisti()');
  g.el('masaSec').value = 'tok-810-a'; await g.calistir('masaDegisti()');
  g.calistir(`SEPET={'${M.VISKI}':{adet:1,ucretli:true}};`); g.el('odaNo').value = '101';
  await g.calistir('gonder()');
  const gt1 = g.kayit.toastlar.slice(-1)[0] || '';
  g.calistir(`SEPET={'${M.BIRA}':{adet:1,ucretli:false}};`);
  await g.calistir('gonder()');
  const gt2 = g.kayit.toastlar.slice(-1)[0] || '';
  sonuc(/FIYAT_DEGISTI/.test(gt1) && /gönderildi/.test(gt2),
    'G3 ESKI garson + A1: ucretli siparis FIYAT_DEGISTI ile reddedilir (fiyat gondermiyor); ucretsiz calisir', gt1.slice(0, 90));

  // --- eski kuyruk ---
  const yeniMenu = menuEkrani(B, { eski: false });
  await menuSiparis(yeniMenu, [[M.VISKI, 1, true]], '101');
  const bekleyen = tek(`select id from public.bar_siparisleri where oda_dogrulama_durumu='bekliyor' order by olusturma_zamani desc limit 1;`);
  const kuyruk = (eski, k = K.BAR810, jwt = J.bar810) => barEkranKur({ html: 'bar-siparis-kuyrugu.html', restUrl: REST(B), jwt,
    kullanici: { id: k.sub, ad: 'Bar 810', rol: 'bar', otel_id: '810' }, yetkiler: { bar_siparis_yonetimi: 'kayit' },
    kaynakKok: eski ? ESKI : kok, musteriAnon: B.anon, musteriFetch: musteri(B) });
  const ek = kuyruk(true);
  for (let i = 0; i < 100 && !ek.calistir('SIPARISLER.length'); i++) await bekle(50);
  const eskiListe = ek.el('liste').innerHTML;
  const dogrulaVar = /odaDogrula|Doğrula/.test(eskiListe);
  await ek.calistir(`durumGuncelle('${bekleyen}','hazirlaniyor')`);
  sonuc(!dogrulaVar && /ODA_DOGRULAMASI_BEKLIYOR/.test(ek.kayit.toastlar.join('|'))
     && tek(`select durum::text from public.bar_siparisleri where id='${bekleyen}';`) === 'yeni',
    'G4 ESKI kuyruk + A1: dogrulama bekleyen ucretli sipariste Dogrula dugmesi YOK; Hazirlaniyor reddedilir -> siparis TAKILI kalir');

  const bira = tek(`select id from public.bar_siparisleri where oda_dogrulama_durumu='gerekmiyor' order by olusturma_zamani desc limit 1;`);
  await ek.calistir(`durumGuncelle('${bira}','hazirlaniyor')`);
  await ek.calistir(`durumGuncelle('${bira}','hazir')`);
  const once = stok('BIRA');
  await ek.calistir(`teslimEt('${bira}')`);
  sonuc(tek(`select durum::text from public.bar_siparisleri where id='${bira}';`) === 'teslim_edildi'
     && Number(stok('BIRA')) === Number(once) - 1,
    'G5 ESKI kuyruk + A1: ucretsiz siparisin hazirlanmasi ve teslimi calisir (stok bir kez duser)', once + ' -> ' + stok('BIRA'));

  const iptalId2 = B.ana.kimlikle(K.BAR810, `select public.bar_siparis_olustur('810','${BAR}','M9',null,'[{"menu_urun_id":"${M.BIRA}","adet":1}]'::jsonb);`).out;
  ek.confirmVer(true);
  await ek.calistir(`iptalEt('${iptalId2}')`);
  sonuc(tek(`select durum::text from public.bar_siparisleri where id='${iptalId2}';`) === 'yeni',
    'G6 ESKI kuyruk + A1: iptal CALISMAZ (yeni imza neden ister); siparis ve rezervasyonu acik kalir',
    (ek.kayit.toastlar.slice(-1)[0] || '').slice(0, 100));

  // --- eski rapid-handler + A1 ---
  const rh = (jwt) => B.fonksiyon('rapid-handler-eski', { anon: B.anon, action: 'liste', jwt });
  const r810 = await rh(J.bar810);
  const rPasif = await rh(J.pasif);
  const oteller = (x) => [...new Set((x.json?.masalar || []).map((m) => m.otel_id))].sort().join(',');
  sonuc(r810.json?.ok === true && oteller(r810) === '810,811' && rPasif.json?.ok === true,
    'G7 ESKI rapid-handler + A1: calisir, ANCAK eski acik surer — 810 personeli 811 masalarini, PASIF kullanici listeyi gorur',
    `810 -> ${oteller(r810)} | pasif -> ${rPasif.json?.ok}`);

  // --- adim 3: yeni ekranlar + eski rapid-handler ---
  const yg = garson(false, true);
  for (let i = 0; i < 100 && !yg.calistir('MASALAR.length'); i++) await bekle(50);
  sonuc(yg.calistir('MASALAR.length') >= 2, 'G8 YENI garson + ESKI rapid-handler: masa listesi gelir (sozlesme ayni)',
    'masa ' + yg.calistir('MASALAR.length'));
  const yk = kuyruk(false);
  for (let i = 0; i < 100 && !yk.calistir('SIPARISLER.length'); i++) await bekle(50);
  yk.confirmVer(true);
  await yk.calistir(`odaDogrula('${bekleyen}')`);
  await yk.calistir(`durumGuncelle('${bekleyen}','hazirlaniyor')`);
  sonuc(tek(`select oda_dogrulama_durumu||'|'||durum from public.bar_siparisleri where id='${bekleyen}';`) === 'dogrulandi|hazirlaniyor',
    'G9 YENI kuyruk yayinlaninca G4te takilan siparis dogrulanip hazirlanabilir');

  // --- eski stok-takip sayim + A1 (okuma politikasi YALNIZ testte; uretimde sayim tablolari kapali) ---
  B.ana.sql(`create policy test_yalniz_okuma on public.sayim_oturumlari for select to authenticated using (true);
    create policy test_yalniz_okuma on public.sayim_detaylari for select to authenticated using (true);
    update public.stok set miktar = 100 where urun_kodu='LIMON' and depo_kodu='${BAR}';
    insert into public.sayim_oturumlari (id, depo_kodu, otel_id, olusturan_ad, durum, toplam_urun_sayisi)
      values ('99999999-0000-0000-0000-00000000aa01','${BAR}','810','Test','onay_bekliyor',1);
    insert into public.sayim_detaylari (oturum_id, urun_kodu, urun_adi, sistem_miktar, sayilan_miktar, fark)
      values ('99999999-0000-0000-0000-00000000aa01','LIMON','Limon',100,90,-10);`);
  B.ana.kimlikle(K.DEPO810, `select public.stok_ekle('LIMON','${BAR}','810',-20);`);   // 100 -> 80
  const st = ekranKur({ restUrl: REST(B), jwt: J.depo810, depo: BAR, rol: 'cost_control', kaynakKok: ESKI });
  await bekle(1500);
  await st.calistir('sayimOnayBekleyenleriYukle()');
  await st.calistir(`sayimOnayla('99999999-0000-0000-0000-00000000aa01')`);
  await bekle(500);
  const eskiSonuc = stok('LIMON');
  sonuc(eskiSonuc === '90.000',
    'G10 ESKI stok-takip + A1: eski istemci sayimi onay anindaki stoga gore yazar -> 70 yerine 90 (aradaki cikis kaybolur)',
    '100 -> say 90 -> cikis 20 -> eski ekran sonucu ' + eskiSonuc);
} catch (e) { sonuc(false, 'beklenmeyen hata (adim 2-3)', e.stack || e.message); console.log(B.edgeGunlugu().slice(-1500)); }
finally { B.temizle(); rmSync(ESKI, { recursive: true, force: true }); rmSync(EK, { recursive: true, force: true }); }

console.log(`\nBAR A1 YAYIN GECIS PROVASI: ${ok} OK / ${fail} FAIL`);
process.exit(fail ? 1 : 0);
