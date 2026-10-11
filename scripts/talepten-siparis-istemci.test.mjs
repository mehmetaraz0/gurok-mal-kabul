// ===========================================================================
// TALEPTEN SIPARIS — ISTEMCI UCTAN UCA (izole, uretime BAGLANMAZ)
// ===========================================================================
// GERCEK `satin-alma-siparisolustur.html` betigi, GERCEK PostgREST ve GERCEK
// Postgres uzerinde kosar. Olculen sorular:
//   1. Talep kaynakli siparis TEK RPC ile mi yaziliyor (baslik + kalem + bag
//      ayni transaction'da)?
//   2. Bag miktari talep kaleminin DONDURULMUS biriminde mi? Referans ornek
//      (spec §1.1): kalem 10 KOL · satir 72 KG · 12 KG/KOL -> bag 6 KOL,
//      kalan 4 KOL.
//   3. RPC reddederse ekranda HICBIR satir kaliyor mu, kullanici anlasilir
//      mesaj goruyor mu?
//   4. Ayni sayfadan iki kez gonderim mukerrer siparis yaziyor mu?
//   5. Talepsiz yol bozulmadi mi (eski REST yolu + sunucu numarasi)?
// ===========================================================================
import { readFileSync } from 'node:fs';
import { barOrtami, yerelJwt } from './bar-test-ortam.mjs';
import { ekranKur } from './stok-ekran-harness.mjs';
import { kurFikstur, U_TEST } from './talep-siparis-fikstur.mjs';

const KOK = new URL('..', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const MIG = [
  'docs/kurulum/2026-08-04-stok-tablo-viewlar.sql',
  'docs/kurulum/2026-10-11-stok-acik-talep-durum-filtresi.sql',
  'docs/kurulum/2026-10-11-siparis-no-sayac.sql',
  'docs/kurulum/2026-10-11-talep-siparis-baglari.sql',
  'docs/kurulum/2026-10-11-siparisler-islem-anahtari.sql',
  'docs/kurulum/2026-10-11-talep-siparis-inv-kapilari.sql',
  'docs/kurulum/2026-10-11-siparis-olustur-talepten.sql',
  'docs/kurulum/2026-10-11-stok-acik-talep-kalan.sql',
];
const O = barOrtami({ ad: 'talep-istemci', ag: 'talep-istemci-net' });

let ok = 0, fail = 0;
const sonuc = (g, ad, ek) => { console.log((g ? 'OK   ' : 'FAIL ') + ad + (ek ? ' — ' + ek : '')); if (g) ok++; else fail++; };
const es = (ad, bek, olc) => sonuc(Number(bek) === Number(olc), ad, Number(bek) === Number(olc) ? String(olc) : `beklenen=${bek} olculen=${olc}`);
const tek = (q) => O.sql(q).out.trim();
const hat = (r) => (String(r.err).split('\n').filter(l => /ERROR/.test(l))[0] || '(mesaj yok)').slice(0, 130);
let f, restUrl;
// Fikstur iki siparis kaydi tasiyor (C00000001/C00000002). Sayimlar YALNIZ
// ekranin yazdigi siparisleri gormeli; yoksa her iddia ikiye kayar.
const ekranSip = (kolon) => tek(`select ${kolon} from public.siparisler
  where siparis_no not in ('${'C00000001'}','${'C00000002'}');`);

// Ekrani kurar: devir verisi sessionStorage'a betik KOSMADAN ONCE konur,
// cunku sayfanin init'i acilista okuyup temizliyor.
function ekran({ satirlar, talepId = null }) {
  const e = ekranKur({
    restUrl,
    jwt: yerelJwt('authenticated', U_TEST),
    dosya: 'satin-alma-siparisolustur.html',
    yardimcilar: ['otel-config.js', 'ortak.js', 'araz_veritabani.js'],
    yetkiler: { siparis_olustur: 'kayit' },
    oturumVerisi: `sessionStorage.setItem('sp_devir_satirlar', ${JSON.stringify(JSON.stringify(satirlar))});`
      + (talepId ? `sessionStorage.setItem('sp_devir_talep', ${JSON.stringify(talepId)});` : ''),
    baslangic: `var __toast=[]; toast=function(m){__toast.push(String(m));};
                sLD=function(){}; hLD=function(){};`,
  });
  return e;
}

// "let" ile tanimli kuresel degiskenler baglam NESNESINDE gorunmez (kuresel
// sozcuksel kapsamda yasarlar); betigin icinden degerlendirilmeleri gerekir.
const oku = (e, ifade) => e.calistir(ifade);
async function hazirBekle(e, sureMs = 20000) {
  const bitis = Date.now() + sureMs;
  while (Date.now() < bitis) {
    if (Number(oku(e, '(typeof SP_SATIRLAR!=="undefined" && SP_SATIRLAR) ? SP_SATIRLAR.length : -1')) > 0) return true;
    await new Promise(r => setTimeout(r, 50));
  }
  return false;
}
const toastlar = (e) => { try { return JSON.parse(e.calistir('JSON.stringify(__toast)')) || []; } catch { return []; } };
const toastVar = (e, p) => toastlar(e).some(t => t.includes(p));

async function gonder(e, { tarih = null, termin = '' } = {}) {
  e.el('sp-tarih').value = tarih || new Date().toISOString().slice(0, 10);
  e.el('sp-termin').value = termin;
  e.el('sp-otel').value = '810';
  await e.calistir('spGrupla()');
}

try {
  await O.kur();
  for (const m of MIG) {
    const r = O.uygulaTekIslem(m);
    sonuc(r.ok, 'F ' + m.split('/').pop(), r.ok ? '' : hat(r));
  }
  f = kurFikstur(O);
  restUrl = await O.restBaslat({ port: 3096 });
  sonuc(!!restUrl, 'F PostgREST ayakta', restUrl);

  const temizle = () => O.sql(`set session_replication_role = replica;
    delete from public.talep_siparis_baglari;
    delete from public.siparis_kalemleri;
    delete from public.siparisler where siparis_no not in ('${f.siparisNo}','${f.siparisNo2}');
    update public.satin_alma_talepleri set durum='onaylandi' where id='${f.talepId}'::uuid;
    set session_replication_role = origin;`);

  // ---- T1 MUTLU YOL: 72 KG satir -> 6 KOL bag, TEK RPC ------------------
  {
    temizle();
    const e = ekran({ talepId: f.talepId,
      satirlar: [{ ad: 'Bag Test Urunu', kod: f.urunKodu, miktar: '72', birim: 'KG',
                   not: '', talepKalemId: f.kalemId }] });
    sonuc(await hazirBekle(e), 'T1a ekran devir satirini yukledi',
      'SP_SATIRLAR=' + String(oku(e, 'JSON.stringify(SP_SATIRLAR)')).slice(0, 130));
    es('T1b talep kalem kimligi tasindi', 1,
      Number(oku(e, `SP_SATIRLAR.filter(r=>r.talepKalemId===${JSON.stringify(f.kalemId)}).length`)));
    await gonder(e);
    es('T1c bir siparis yazildi', 1, ekranSip('count(*)'));
    es('T1d bir siparis kalemi yazildi', 1, tek('select count(*) from public.siparis_kalemleri;'));
    es('T1e bir bag yazildi', 1, tek('select count(*) from public.talep_siparis_baglari;'));
    es('T1f bag miktari 6 (KOL)', 6, tek('select miktar from public.talep_siparis_baglari;'));
    sonuc(tek('select hedef_birim from public.talep_siparis_baglari;') === 'KOL',
      'T1g hedef_birim KOL olarak donduruldu');
    es('T1h kaynak miktar 72 KG korundu', 72, tek('select kaynak_miktar from public.talep_siparis_baglari;'));
    sonuc(ekranSip("max(kaynak)") === 'talep',
      'T1i siparis kaynagi talep');
    // Istemcinin URETTIGI numara DEGIL, sunucunun verdigi numara yazilmali.
    sonuc(/^C[0-9]{8}$/.test(ekranSip('max(siparis_no)')),
      'T1j numara sunucu bicimi', ekranSip('max(siparis_no)'));
    // Eski iki asamali REST yolu KULLANILMAMALI: yer tutucu POST yok.
    const istek = e.istekler.filter(u => /\/siparisler($|\?)/.test(u));
    sonuc(istek.length === 0, 'T1k talep yolunda `siparisler` REST POST yok',
      'olculen istek sayisi=' + istek.length);
    sonuc(e.istekler.some(u => u.includes('rpc/siparis_olustur_talepten')),
      'T1l tek RPC cagrildi');
  }

  // ---- T2 KALAN: gorunum 4 KOL (bag dondurulmus birimde) ----------------
  es('T2 kalan 4 KOL', 4, (O.kimlikle(f.kimlikTalep,
    `select coalesce(sum(talep_miktar),0)::text from public.stok_acik_talep
      where urun_kodu='${f.urunKodu}' and birim='KOL';`).out || '').trim().split('\n').pop());

  // ---- T3 RET: asim -> HICBIR satir yazilmaz, anlasilir mesaj -----------
  {
    temizle();
    const e = ekran({ talepId: f.talepId,
      satirlar: [{ ad: 'Bag Test Urunu', kod: f.urunKodu, miktar: '600', birim: 'KG',
                   not: '', talepKalemId: f.kalemId }] });
    await hazirBekle(e);
    await gonder(e);
    es('T3a siparis yazilmadi', 0, ekranSip('count(*)'));
    es('T3b kalem yazilmadi', 0, tek('select count(*) from public.siparis_kalemleri;'));
    es('T3c bag yazilmadi', 0, tek('select count(*) from public.talep_siparis_baglari;'));
    sonuc(toastVar(e, 'Talep miktarı aşılıyor'),
      'T3d kullaniciya anlasilir ret mesaji', JSON.stringify(toastlar(e).slice(-1)[0] || '—'));
  }

  // ---- T4 ISLEM ANAHTARI YASAM DONGUSU ----------------------------------
  // Sozlesme (spec §6.1): idempotency BASARISIZ DENEMENIN TEKRARINI korur;
  // BASARIDAN SONRA yeni siparis YENI anahtar ister. Yani "iki kez bas ->
  // tek siparis" DOGRU beklenti DEGIL — ikinci bas yeni bir siparis denemesi
  // olur ve burada INV onu zaten reddeder. Olculen:
  //   (a) basarisiz denemede anahtar KORUNUR (tekrar ayni anahtarla gider),
  //   (b) basariyla birlikte anahtar YENILENIR,
  //   (c) basaridan sonraki ikinci gonderim SESSIZ MUKERRER degil, INV retti.
  {
    temizle();
    const e = ekran({ talepId: f.talepId,
      satirlar: [{ ad: 'Bag Test Urunu', kod: f.urunKodu, miktar: '72', birim: 'KG',
                   not: '', talepKalemId: f.kalemId }] });
    await hazirBekle(e);

    // Sunucu reddi: termin tarihten once.
    await gonder(e, { termin: '2000-01-01' });
    es('T4a ret sonrasi siparis yazilmadi', 0, ekranSip('count(*)'));
    const a1 = String(oku(e, "JSON.stringify(SP_ANAHTARLAR)"));
    sonuc(/"_bos"\s*:\s*"[^"]{8,}"/.test(a1), 'T4b ret sonrasi anahtar olusmus', a1.slice(0, 80));

    // Ayni ret tekrar: anahtar DEGISMEMELI (tekrar gonderim ayni anahtarla).
    await gonder(e, { termin: '2000-01-01' });
    const a2 = String(oku(e, "JSON.stringify(SP_ANAHTARLAR)"));
    sonuc(a1 === a2, 'T4c basarisiz tekrar denemede anahtar KORUNDU',
      a1 === a2 ? 'ayni' : a1.slice(0, 40) + ' != ' + a2.slice(0, 40));

    // Duzeltip gonder: basarili, anahtar YENILENIR.
    await gonder(e, { termin: '' });
    es('T4d duzeltmeden sonra bir siparis yazildi', 1, ekranSip('count(*)'));
    es('T4e bir bag yazildi', 1, tek('select count(*) from public.talep_siparis_baglari;'));
    const a3 = String(oku(e, "JSON.stringify(SP_ANAHTARLAR)"));
    sonuc(a3 !== a2, 'T4f basaridan sonra anahtar YENILENDI',
      a3 === a2 ? 'DEGISMEDI — ayni anahtarla ikinci siparis denenirdi' : 'degisti');

    // Ikinci bas: yeni anahtar + ayni 72 KG -> kalan 4 KOL, INV reddeder.
    await gonder(e, { termin: '' });
    es('T4g ikinci bas mukerrer siparis YAZMADI', 1, ekranSip('count(*)'));
    es('T4h ikinci bas mukerrer bag YAZMADI', 1, tek('select count(*) from public.talep_siparis_baglari;'));
    sonuc(toastVar(e, 'Talep miktarı aşılıyor'),
      'T4i ikinci bas INV ile reddedildi (sessiz degil)',
      JSON.stringify(toastlar(e).slice(-1)[0] || '—'));
  }

  // ---- T5 TALEPSIZ YOL bozulmadi: eski REST yolu + sunucu numarasi ------
  {
    temizle();
    const e = ekran({ talepId: null,
      satirlar: [{ ad: 'Serbest Urun', kod: '', miktar: '3', birim: 'KG', not: '' }] });
    await hazirBekle(e);
    await gonder(e);
    es('T5a talepsiz siparis yazildi', 1, ekranSip('count(*)'));
    es('T5b bag YAZILMADI (talep yok)', 0, tek('select count(*) from public.talep_siparis_baglari;'));
    sonuc(/^C[0-9]{8}$/.test(ekranSip('max(siparis_no)')),
      'T5c numara sunucudan', ekranSip('max(siparis_no)'));
    sonuc(e.istekler.some(u => u.includes('rpc/siparis_no_uret')),
      'T5d talepsiz yol numara RPC\'sini kullandi');
    sonuc(!e.istekler.some(u => u.includes('rpc/siparis_olustur_talepten')),
      'T5e talepsiz yol talep RPC\'sini CAGIRMADI');
  }

  // ---- T6 TALEPSIZ YOL fail-closed: numara alinamazsa yazma YOK --------
  {
    temizle();
    O.sql(`revoke execute on function public.siparis_no_uret(text) from authenticated;
           notify pgrst, 'reload schema';`);
    const e = ekran({ talepId: null,
      satirlar: [{ ad: 'Serbest Urun', kod: '', miktar: '3', birim: 'KG', not: '' }] });
    await hazirBekle(e);
    await gonder(e);
    es('T6a numara alinamayinca siparis yazilmadi', 0, ekranSip('count(*)'));
    sonuc(toastVar(e, 'numarası alınamadı'), 'T6b kullaniciya bildirildi',
      JSON.stringify(toastlar(e).slice(-1)[0] || '—'));
    O.sql(`grant execute on function public.siparis_no_uret(text) to authenticated;
           notify pgrst, 'reload schema';`);
  }

  // ---- T7 ERKEN DURUM DAMGASI KALKTI ------------------------------------
  // Eskiden talepler ekraninda `talep_siparise_donustur` cagriliyor ve
  // SIPARIS OLUSMASA BILE talep 'siparis' oluyordu.
  sonuc(!/talepSiparisRpc\s*\(/.test(readFileSync(KOK + 'satin-alma-talepler.html', 'utf8')),
    'T7 talepler ekraninda erken durum damgasi YOK');

  console.log(`\nSONUC: ${ok} gecti, ${fail} kaldi`);
} catch (e) { console.error('DUR: ' + (e && e.stack || e)); fail++; }
finally { try { O.temizle(); } catch { /* yoksay */ } }
process.exit(fail === 0 ? 0 : 1);
