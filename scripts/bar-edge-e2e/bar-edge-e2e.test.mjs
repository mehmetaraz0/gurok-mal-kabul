// ===========================================================================
// BAR A1 — EDGE FUNCTION UCTAN UCA TESTI (tasarim 5 / plan G7) — uretime BAGLANMAZ
// ===========================================================================
// Gercek GoTrue kullanicisi -> musteri projesi ag gecidi -> Edge Runtime
// (hyper-api / rapid-handler / smooth-service, depodaki GERCEK kaynak) -> ana
// proje PostgREST (A1 uygulanmis uretim semasi) + musteri projesi PostgREST.
//
// Evre A: A1 uygulanmis ana veritabani (hedef durum).
// Evre B: A1 UYGULANMAMIS ana veritabani (bugunku durum) — yayin sirasini
//         belirleyen olcumler (yeni istemci eski RPC ile; yeni rapid-handler eski
//         veritabaniyla).
// Surumler: ortam.mjs basligi. Uretimle surum esitligi IDDIA EDILMEZ.
// ===========================================================================
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { e2eOrtami, SUPABASE_JS } from './ortam.mjs';
import { yerelJwt, kok } from '../bar-test-ortam.mjs';
import { K, M } from '../bar-a1-tohum.mjs';

let ok = 0, fail = 0;
const sonuc = (g, ad, ek) => { console.log((g ? 'OK   ' : 'FAIL ') + ad + (ek ? ' — ' + ek : '')); if (g) ok++; else fail++; };
const kisa = (r) => r.durum + ' ' + (r.json ? JSON.stringify(r.json) : r.metin).slice(0, 160);

const KULLANICILAR = [
  [K.BAR810.sub, 'bar810@test.local'], [K.BAR811.sub, 'bar811@test.local'],
  [K.PASIF.sub, 'pasif@test.local'], [K.DEPO810.sub, 'depo810@test.local'],
];
async function kullanicilar(E) {
  const t = {};
  for (const [id, email] of KULLANICILAR) { await E.kullaniciOlustur(id, email); t[email.split('@')[0]] = await E.girisYap(email); }
  return t;
}

// Negatif kontrol kaynagi: rapid-handler 'liste' dalindan otel filtresi kaldirilir.
function negatifKaynak() {
  const dizin = mkdtempSync(path.join(tmpdir(), 'bar-e2e-neg-'));
  mkdirSync(path.join(dizin, 'masa-yonetim'));
  const asil = readFileSync(kok + 'docs/kurulum/musteri-projesi/masa-yonetim/index.ts', 'utf8');
  const filtre = '.in("otel_id", oteller).order("bolge")';
  if (!asil.includes(filtre)) throw new Error('negatif kontrol kurulamadi: liste filtresi bulunamadi');
  writeFileSync(path.join(dizin, 'masa-yonetim', 'index.ts'), asil.replace(filtre, '.order("bolge")'));
  return dizin.replace(/\\/g, '/');
}

// ======================= EVRE A: A1 uygulanmis =======================
const negDizin = negatifKaynak();
const E = e2eOrtami({ ad: 'bar-e2e-a', a1: true, negatifDizin: negDizin });
try {
  await E.kur();
  console.log(`evre A hazir — supabase-js ${SUPABASE_JS} (sabit), A1 uygulanmis ana veritabani\n`);
  const J = await kullanicilar(E);
  const anaTek = (q) => E.ana.sql(q).out;
  const musTek = (q) => E.musSql(q).out;
  const hyper = (g) => E.fonksiyon('hyper-api', g);

  // ---------------- hyper-api (kod degismez, davranis degisir) ----------------
  let r = await hyper({ token: 'yok-boyle-token', kalemler: [{ menu_urun_id: M.BIRA, adet: 1 }] });
  sonuc(r.durum === 400 && /Geçersiz masa/.test(r.json?.mesaj), 'H1 gecersiz token: 400 Gecersiz masa', kisa(r));
  r = await hyper({ token: 'tok-810-pasif', kalemler: [{ menu_urun_id: M.BIRA, adet: 1 }] });
  sonuc(r.durum === 400 && /Geçersiz masa/.test(r.json?.mesaj), 'H2 pasif masa tokeni: 400', kisa(r));
  const k21 = Array.from({ length: 21 }, () => ({ menu_urun_id: M.BIRA, adet: 1 }));
  const r21 = await hyper({ token: 'tok-810-a', kalemler: k21 });
  const r31 = await hyper({ token: 'tok-810-a', kalemler: [{ menu_urun_id: M.BIRA, adet: 31 }] });
  sonuc(r21.durum === 400 && r31.durum === 400 && anaTek(`select count(*) from public.bar_siparisleri;`) === '0',
    'H3 20 kalem / 30 adet siniri: 400, ana projede siparis yok', kisa(r21) + ' | ' + kisa(r31));

  r = await hyper({ token: 'tok-810-a', kalemler: [{ menu_urun_id: M.VISKI, adet: 1, gosterilen_fiyat: 250 }] });
  sonuc(r.durum === 200 && r.json?.ok === false && /^ODA_NO_GEREKLI/.test(r.json?.mesaj)
     && musTek(`select sonuc||'|'||hata_mesaji from public.siparis_arsiv order by olusturma_zamani desc limit 1;`).startsWith('hata|ODA_NO_GEREKLI'),
    'H4 ucretli, odasiz: ODA_NO_GEREKLI musteriye doner ve arsivlenir', kisa(r));
  r = await hyper({ token: 'tok-810-a', oda_no: '103', kalemler: [{ menu_urun_id: M.VISKI, adet: 1, gosterilen_fiyat: 250 }] });
  sonuc(r.json?.ok === false && /^KONAKLAMA_YOK/.test(r.json?.mesaj), 'H5 bos oda: KONAKLAMA_YOK musteriye doner', kisa(r));

  // ESKI menu istemcisi: gosterilen_fiyat GONDERMEZ.
  r = await hyper({ token: 'tok-810-a', oda_no: '101', kalemler: [{ menu_urun_id: M.VISKI, adet: 1 }] });
  sonuc(r.json?.ok === false && /^FIYAT_DEGISTI: .* guncel fiyat 250(\.00)? \[urun [0-9a-f-]{36}\]/.test(r.json?.mesaj)
     && anaTek(`select count(*) from public.bar_siparisleri;`) === '0',
    'H6 ESKI menu istemcisi (fiyatsiz) ucretli sipariste FIYAT_DEGISTI alir; siparis yazilmaz', kisa(r));
  const eskiUcretsiz = await hyper({ token: 'tok-810-a', kalemler: [{ menu_urun_id: M.BIRA, adet: 1 }] });
  sonuc(eskiUcretsiz.json?.ok === true
     && anaTek(`select kanal||'|'||oda_dogrulama_durumu from public.bar_siparisleri where id='${eskiUcretsiz.json?.siparis_id}';`) === 'qr|gerekmiyor',
    'H7 ESKI istemci ucretsiz sipariste calismaya devam eder (qr, dogrulama gerekmiyor)', kisa(eskiUcretsiz));

  r = await hyper({ token: 'tok-810-a', oda_no: '101', kalemler: [{ menu_urun_id: M.VISKI, adet: 1, gosterilen_fiyat: 250 }] });
  const sid = r.json?.siparis_id;
  sonuc(r.json?.ok === true
     && anaTek(`select kanal||'|'||oda_dogrulama_durumu||'|'||durum from public.bar_siparisleri where id='${sid}';`) === 'qr|bekliyor|yeni'
     && musTek(`select sonuc from public.siparis_arsiv where ana_siparis_id='${sid}';`) === 'basarili',
    'H8 YENI istemci dogru fiyat + dolu oda: siparis yazildi, dogrulama BEKLIYOR, arsiv basarili', kisa(r));
  const hazirlik = E.ana.kimlikle(K.BAR810, `select public.bar_siparis_durum_guncelle('${sid}','hazirlaniyor');`);
  sonuc(!hazirlik.ok && /ODA_DOGRULAMASI_BEKLIYOR/.test(hazirlik.err),
    'H9 QR ucretli siparis personel dogrulamadan hazirlanamaz');

  // ---------------- rapid-handler (kod degisti) ----------------
  const rh = (g) => E.fonksiyon('rapid-handler', { anon: E.anon, ...g });
  const yabanciJwt = yerelJwt('authenticated', K.BAR810.sub, 'baska-bir-sir-baska-bir-sir-baska-bir-sir-32');
  const r1 = await rh({ action: 'liste' });
  const r2 = await rh({ action: 'liste', jwt: 'bozuk' });
  const r3 = await rh({ action: 'liste', jwt: E.anon });
  const r4 = await rh({ action: 'liste', jwt: yabanciJwt });
  // CANLI SOZLESME (2026-09-20 sonda olcumu): JWT hic yoksa 401; JWT VAR ama gecersizse
  // canli surum HTTP 200 + { ok:false } donuyor ve birlesik surum bunu koruyor. Guvenlik
  // kriteri HTTP kodu degil: hicbirinde veri (masalar) donmemeli.
  const veriYok = (x) => x.json && x.json.ok === false && x.json.masalar === undefined;
  sonuc(r1.durum === 401 && veriYok(r1)
     && [r2, r3, r4].every((x) => x.durum === 200 && veriYok(x)),
    'R1 oturumsuz 401; bozuk / anon anahtari / baska sirla imzali JWT 200 + ok:false, hicbirinde veri yok',
    [r1, r2, r3, r4].map((x) => x.durum).join(','));
  r = await rh({ action: 'liste', jwt: J.pasif });
  const rDepo = await rh({ action: 'liste', jwt: J.depo810 });
  sonuc(r.durum === 403 && rDepo.durum === 403, 'R2 PASIF kullanici ve bar yetkisiz kullanici: 403 (GoTrue oturumu gecerli olsa da)',
    kisa(r) + ' | ' + kisa(rDepo));
  const l810 = await rh({ action: 'liste', jwt: J.bar810 });
  const l811 = await rh({ action: 'liste', jwt: J.bar811 });
  const oteller = (x) => [...new Set((x.json?.masalar || []).map((m) => m.otel_id))].join(',');
  sonuc(l810.durum === 200 && oteller(l810) === '810' && l811.durum === 200 && oteller(l811) === '811',
    'R3 liste otel kapsamli: 810 personeli yalniz 810, 811 personeli yalniz 811 masalarini gorur', oteller(l810) + ' / ' + oteller(l811));
  const neg = await E.fonksiyon('rapid-handler-negatif', { anon: E.anon, action: 'liste', jwt: J.bar810 });
  sonuc(neg.durum === 200 && oteller(neg).split(',').sort().join(',') === '810,811',
    'R3n NEGATIF KONTROL: liste filtresi kaldirilinca 811 masalari 810 personeline gorunuyor ve test bunu goruyor', oteller(neg));

  const e811 = await rh({ action: 'ekle', jwt: J.bar810, otel_id: '811', depo_id: '811_CSM302', masa_adi: 'Sizma' });
  const eOnek = await rh({ action: 'ekle', jwt: J.bar810, otel_id: '810', depo_id: '811_CSM302', masa_adi: 'Onek' });
  sonuc(e811.durum === 403 && eOnek.durum === 400
     && musTek(`select count(*) from public.masa_tokenlari where masa_adi in ('Sizma','Onek');`) === '0',
    'R4 baska otele masa eklenemez (403); depo oneki otelle uyusmazsa eklenmez (400)', kisa(e811) + ' | ' + kisa(eOnek));
  const eOk = await rh({ action: 'ekle', jwt: J.bar810, otel_id: '810', depo_id: '810_CSM302', masa_adi: 'Havuz 2', bolge: 'Havuz' });
  sonuc(eOk.durum === 200 && musTek(`select otel_id||'|'||depo_id||'|'||aktif from public.masa_tokenlari where masa_adi='Havuz 2';`) === '810|810_CSM302|true',
    'R5 kendi oteline masa eklenir; musteri projesine yazildi', kisa(eOk));
  const d811 = await rh({ action: 'durum', jwt: J.bar810, token: 'tok-811-a', aktif: false });
  sonuc(d811.durum === 404 && musTek(`select aktif from public.masa_tokenlari where token='tok-811-a';`) === 't',
    'R6 baska otelin masasi kapatilamaz (404, varligi sizdirilmaz); masa degismedi', kisa(d811));
  const dOk = await rh({ action: 'durum', jwt: J.bar810, token: 'tok-810-a', aktif: false });
  sonuc(dOk.durum === 200 && musTek(`select aktif from public.masa_tokenlari where token='tok-810-a';`) === 'f',
    'R7 kendi masasi kapatilir', kisa(dOk));
  const dGecersiz = await rh({ action: 'durum', jwt: J.bar810, token: 'tok-810-a', aktif: 'evet' });
  const bilinmeyen = await rh({ action: 'sil', jwt: J.bar810 });
  sonuc(dGecersiz.durum === 400 && bilinmeyen.durum === 400, 'R8 gecersiz girdi ve bilinmeyen aksiyon: 400');
  E.musSql(`update public.masa_tokenlari set aktif = true where token='tok-810-a';`);

  // ---------------- smooth-service (regresyon) ----------------
  const ss = (baslik) => E.fonksiyon('smooth-service', {}, baslik);
  const s1 = await ss({});
  const s2 = await ss({ 'x-staff-token': E.anon });
  const s3 = await ss({ 'x-staff-token': J.depo810 });
  const s4 = await ss({ 'x-staff-token': J.pasif });
  sonuc(s1.durum === 401 && s2.durum === 401 && s3.durum === 403 && s4.durum === 403,
    'S1 personel oturumu yok / anon: 401; bar yetkisiz ve pasif: 403', [s1, s2, s3, s4].map(kisa).join(' | '));
  const beklenen = anaTek(`select count(*) from public.menu_urunler where aktif and not silindi;`);
  const s5 = await ss({ 'x-staff-token': J.bar810 });
  sonuc(s5.durum === 200 && s5.json?.ok === true && String(s5.json?.sayi) === beklenen
     && musTek(`select count(*) from public.menu_urunler;`) === beklenen
     && musTek(`select fiyat::text from public.menu_urunler where id='${M.VISKI}';`) === '250.00',
    'S2 yetkili yayin: menu_yenile musteri projesine ana menuyu aynen yazdi', kisa(s5));
} catch (e) {
  sonuc(false, 'beklenmeyen hata (evre A)', e.stack || e.message);
  console.log(E.edgeGunlugu().slice(-2000));
} finally { E.temizle(); rmSync(negDizin, { recursive: true, force: true }); }

// ======================= EVRE B: A1 UYGULANMAMIS (bugunku uretim) =======================
const B = e2eOrtami({ ad: 'bar-e2e-b', a1: false });
try {
  await B.kur();
  console.log('\nevre B hazir — A1 UYGULANMAMIS ana veritabani (yayin sirasi olcumu)\n');
  await B.kullaniciOlustur(K.BAR810.sub, 'bar810@test.local');
  const jwt = await B.girisYap('bar810@test.local');
  const r = await B.fonksiyon('hyper-api', { token: 'tok-810-a', oda_no: '101',
    kalemler: [{ menu_urun_id: M.VISKI, adet: 1, gosterilen_fiyat: 250 }] });
  sonuc(r.json?.ok === true, 'Y1 YENI menu istemcisi (gosterilen_fiyat) BUGUNKU veritabaniyla calisir: fazladan alan yok sayilir', kisa(r));
  const rh = await B.fonksiyon('rapid-handler', { anon: B.anon, action: 'liste', jwt });
  sonuc(rh.durum === 403,
    'Y2 YENI rapid-handler BUGUNKU veritabaniyla calismaz (bar_masa_yetki_kapsami yok -> 403): once migration, sonra deploy', kisa(rh));
} catch (e) {
  sonuc(false, 'beklenmeyen hata (evre B)', e.stack || e.message);
  console.log(B.edgeGunlugu().slice(-2000));
} finally { B.temizle(); }

console.log(`\nBAR A1 EDGE UCTAN UCA: ${ok} OK / ${fail} FAIL`);
process.exit(fail ? 1 : 0);
