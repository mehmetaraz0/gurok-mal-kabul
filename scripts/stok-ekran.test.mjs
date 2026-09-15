// ===========================================================================
// STOK EKRANI DAVRANIS TESTLERI — izole, uretime BAGLANMAZ
// ===========================================================================
// Bu testler stok-takip.html icindeki GERCEK betigi calistirir (harness).
// Kanitlanan sorular:
//   1. Depo/arama degistiginde UCUSTAKI eski istegin yaniti yeni listeye
//      karisiyor mu?  (Benzersiz siralama bunu engellemez; sorun siralamada
//      degil YANIT SIRASINDA.)
//   2. Cikis / transfer / iade / sayim / Excel, artik acilista indirilmeyen
//      bellek verisine (db.stok) bagimli mi?
//   3. Okuma basarisiz olursa bu akislar DURUYOR mu, yoksa "0 mevcut" gibi
//      uydurulmus veriyle mi ilerliyor?
//
// Sunucu satir tavani 100: 300 urunlu bir depo tek sayfaya SIGMAZ.
// ===========================================================================
import { ortamOlustur } from './stok-test-ortam.mjs';
import { ekranKur } from './stok-ekran-harness.mjs';

const ortam = ortamOlustur({ onek: 'stok-ekran', port: 3098, maxRows: 100 });

let ok = 0, fail = 0;
function sonuc(gecti, ad, ek) {
  console.log((gecti ? 'OK   ' : 'FAIL ') + ad + (ek ? ' — ' + ek : ''));
  if (gecti) ok++; else fail++;
}

// Ekranin acilista okudugu yan tablolar (bos) — testin konusu degil, gurultu
// olmasin diye var.
const EK_SEMA = `
  create table public.urun_birim_donusum (urun_kodu text, buyuk_birim text, carpan numeric, silindi boolean default false);
  create table public.cariler (id uuid primary key default gen_random_uuid(), ad text, tip text, aktif boolean default true, silindi boolean default false);
  create table public.kullanicilar_genel (id uuid primary key default gen_random_uuid(), ad text, rol text);
  create table public.siparisler (
    id uuid primary key default gen_random_uuid(), siparis_no text, firma_ad text, otel_id text,
    tarih date, durum text, tip text, iade_nedeni text, orijinal_fatura_no text,
    not_alani text, kaynak text, depo_kodu text, olusturan_ad text);
  create table public.siparis_kalemleri (
    id uuid primary key default gen_random_uuid(), siparis_id uuid, urun_kodu text, urun_adi text,
    miktar numeric, birim text);
  grant select, insert, update on public.urun_birim_donusum, public.cariler,
    public.kullanicilar_genel, public.siparisler, public.siparis_kalemleri to authenticated;
`;

function seedDepolar() {
  ortam.psql(`
    truncate public.stok, public.urunler, public.stok_minimumlar, public.stok_hareketleri;
    insert into public.urunler (kod, ad, birim)
      select 'AAA' || lpad(g::text, 3, '0'), 'A urunu ' || g, 'KG' from generate_series(1, 300) g;
    insert into public.urunler (kod, ad, birim)
      select 'BBB' || lpad(g::text, 3, '0'), 'B urunu ' || g, 'KG' from generate_series(1, 5) g;
    insert into public.stok (urun_kodu, depo_kodu, otel_id, miktar)
      select kod, 'D1', '810', 50 from public.urunler where kod like 'AAA%';
    insert into public.stok (urun_kodu, depo_kodu, otel_id, miktar)
      select kod, 'D2', '810', 7 from public.urunler where kod like 'BBB%';
  `);
}

const miktarOku = (kod, depo) =>
  Number(ortam.psqlTek(`select coalesce(max(miktar),-1)::text from public.stok
                         where urun_kodu='${kod}' and depo_kodu='${depo}'`));

await ortam.kur({ ekSema: EK_SEMA, rpc: true });
console.log('ortam hazir — postgrest satir tavani: ' + ortam.maxRows + '\n');
seedDepolar();

async function ekran(depo = 'D1') {
  const e = ekranKur({ restUrl: ortam.restUrl, jwt: ortam.jwt('authenticated'), depo });
  // Toast'lari yakala: akisin ENGELLENDIGINI bu mesajlar soyler.
  e.calistir(`var __toast=[]; showToast=function(m){__toast.push(String(m));};
              showLoading=function(){}; hideLoading=function(){};
              openModal=function(){}; closeModal=function(){};`);
  await e.hazir();          // init() bitsin: yarim yuklu ekranda olcum yapilmaz
  return e;
}
const toastlar = (e) => e.baglam.__toast || [];
const toastVar = (e, parca) => toastlar(e).some(t => t.includes(parca));

// --- 1) BAYAT YANIT: depo degisimi ------------------------------------------
{
  const e = await ekran('D1');
  let ozetGecikti = false;
  e.fetchAraciAyarla(async (url, sec, calistir) => {
    // D1'in liste istegi ve ILK ozet istegi (yine D1'in) gec donsun: yanitlari
    // kullanici D2'ye gectikten SONRA gelir.
    if (url.includes('depo_kodu=eq.D1')) await new Promise(r => setTimeout(r, 400));
    else if (!ozetGecikti && url.includes('/rpc/stok_ozet')) {
      ozetGecikti = true;
      await new Promise(r => setTimeout(r, 400));
    }
    return calistir();
  });

  e.calistir('stokListesiSifirla()');                   // D1 icin temiz durum
  const ilk = e.calistir('Promise.all([stokOzetYukle(),stokSayfaYukle()])');  // D1, yavas
  e.calistir('aktifDepoId="D2"');
  await e.calistir('stokListesiYenile()');              // D2, hizli
  await ilk;                                            // gec gelen D1 yanitlari
  await new Promise(r => setTimeout(r, 300));

  const d2 = e.calistir('Object.keys(db.stok.D2||{})');
  const kirli = d2.filter(k => !k.startsWith('BBB'));
  const toplam = e.calistir('_stokSayfa.toplam');
  const ozet = e.calistir('_stokOzet && _stokOzet.toplam');
  sonuc(d2.length === 5 && kirli.length === 0,
    'depo degisti: eski deponun satirlari yeni listeye KARISMIYOR',
    'D2 listesi ' + d2.length + ' satir, yabanci ' + kirli.length);
  sonuc(toplam === 5 && ozet === 5,
    'depo degisti: sayac ve ozet de yeni depoya ait',
    'sayfa toplam=' + toplam + ', ozet=' + ozet + ' (bekl. 5/5)');
}

// --- 2) BAYAT YANIT: arama degisimi -----------------------------------------
{
  const e = await ekran('D1');
  await e.calistir('stokListesiYenile()');
  let geciktirildi = false;
  e.fetchAraciAyarla(async (url, sec, calistir) => {
    if (!geciktirildi && url.includes('AAA1')) {        // ilk aramanin yaniti gec gelsin
      geciktirildi = true;
      await new Promise(r => setTimeout(r, 400));
    }
    return calistir();
  });
  e.el('stok-search').value = 'AAA1';
  const ilk = e.calistir('stokListesiSifirla(); _stokSayfa.arama="AAA1"; stokSayfaYukle()');
  e.el('stok-search').value = 'AAA299';
  await e.calistir('stokListesiSifirla(); _stokSayfa.arama="AAA299"; stokSayfaYukle()');
  await ilk;
  await new Promise(r => setTimeout(r, 200));

  const kodlar = e.calistir('Object.keys(db.stok.D1||{})');
  sonuc(kodlar.length === 1 && kodlar[0] === 'AAA299',
    'arama degisti: eski aramanin sonucu listeye KARISMIYOR',
    kodlar.length + ' satir: ' + kodlar.slice(0, 3).join(','));
}

// --- 2b) Kartin alan takimi: "Son guncelleme" bos kalmamali -----------------
// Eski toplu okuma stok?select=* ile geliyordu; sayfali okumada alan listesi
// dar yazilinca her kart "—" gosterdi (uretimde 2026-09-15'te goruldu).
{
  seedDepolar();
  const e = await ekran('D1');
  await e.calistir('stokListesiYenile()');
  const s = e.calistir('Object.values(db.stok.D1||{})[0]');
  const alanlar = ['lnKod', 'urunAd', 'miktar', 'birim', 'sonGuncelleme'];
  const eksik = alanlar.filter(a => s[a] === undefined || s[a] === null);
  sonuc(eksik.length === 0, 'liste satiri kartin ihtiyaci olan ALANLARIN hepsini tasiyor',
    eksik.length ? 'eksik: ' + eksik.join(',') : 'sonGuncelleme=' + String(s.sonGuncelleme).slice(0, 19));
}

// --- 3) CIKIS: yuklenmemis urun icin de calisir ------------------------------
{
  seedDepolar();
  const e = await ekran('D1');
  await e.calistir('stokListesiYenile()');               // yalniz ilk 100 satir
  const yuklu = e.calistir('Object.keys(db.stok.D1||{}).length');
  const bellekteVar = e.calistir('!!(db.stok.D1||{})["AAA300"]');

  e.el('cikis-depo').value = 'D1';
  e.el('cikis-urun-kod').value = 'AAA300';
  e.el('cikis-urun-inp').value = 'A urunu 300';
  e.el('cikis-miktar').value = '10';
  e.el('cikis-birim').value = 'KG';
  e.el('cikis-neden').value = 'fire';
  e.el('cikis-not').value = '';
  await e.calistir('saveCikis()');

  const kalan = miktarOku('AAA300', 'D1');
  sonuc(!bellekteVar && yuklu === 100 && kalan === 40 && !toastVar(e, 'yetersiz'),
    'cikis: sayfada olmayan urun icin de yapilabiliyor (miktar SUNUCUDAN)',
    'bellekte ' + yuklu + ' satir, AAA300 bellekte=' + bellekteVar + ', stok 50 -> ' + kalan);
}

// --- 4) TRANSFER: yuklenmemis urun icin de calisir ---------------------------
{
  seedDepolar();
  const e = await ekran('D1');
  await e.calistir('stokListesiYenile()');
  e.el('tr-kaynak').value = 'D1';
  e.el('tr-hedef').value = 'D2';
  e.el('tr-urun-kod').value = 'AAA300';
  e.el('tr-urun-inp').value = 'A urunu 300';
  e.el('tr-miktar').value = '5';
  e.el('tr-birim').value = 'KG';
  e.el('tr-not').value = '';
  await e.calistir('saveTransfer()');
  const kaynak = miktarOku('AAA300', 'D1');
  const hedef = miktarOku('AAA300', 'D2');
  sonuc(kaynak === 45 && hedef === 5 && !toastVar(e, 'yetersiz'),
    'transfer: sayfada olmayan urun icin de yapilabiliyor',
    'D1 50 -> ' + kaynak + ', D2 0 -> ' + hedef);
}

// --- 5) CIKIS: miktar okunamazsa ISLEM DURUR --------------------------------
{
  seedDepolar();
  const e = await ekran('D1');
  await e.calistir('stokListesiYenile()');
  e.fetchAraciAyarla(async (url, sec, calistir) => {
    if (url.includes('/stok?select=urun_kodu,miktar')) return new Response('bozuk', { status: 503 });
    return calistir();
  });
  e.el('cikis-depo').value = 'D1';
  e.el('cikis-urun-kod').value = 'AAA001';
  e.el('cikis-urun-inp').value = 'A urunu 1';
  e.el('cikis-miktar').value = '10';
  e.el('cikis-birim').value = 'KG';
  e.el('cikis-neden').value = 'fire';
  await e.calistir('saveCikis()');
  const kalan = miktarOku('AAA001', 'D1');
  sonuc(kalan === 50 && toastVar(e, 'okunamadı'),
    'cikis: mevcut miktar okunamazsa islem ENGELLENDI, stok degismedi',
    'stok 50 -> ' + kalan + ' | mesaj: ' + (toastlar(e).slice(-1)[0] || '—').slice(0, 60));
}

// --- 6) IADE: stok kontrolu sunucudan, okunamazsa siparis OLUSMUYOR ----------
{
  seedDepolar();
  ortam.psql(`truncate public.siparisler, public.siparis_kalemleri;`);
  const e = await ekran('D1');
  await e.calistir('stokListesiYenile()');
  const firma = e.el('iade-firma');
  firma.value = '00000000-0000-0000-0000-000000000001';
  firma.selectedIndex = 0;
  firma.options = [{ dataset: { ad: 'Test Firma' } }];
  e.el('iade-otel').value = '810';
  e.el('iade-depo').value = 'D1';
  e.el('iade-neden').value = 'bozuk';
  e.el('iade-fatura-no').value = '';
  e.el('iade-not').value = '';
  // Sayfada OLMAYAN urun: bellege bakan eski kontrol "mevcut 0" derdi.
  e.calistir(`IADE_KALEMLER=[{id:'t1',kod:'AAA300',ad:'A urunu 300',birim:'KG',miktar:'5'}];`);
  await e.calistir('iadeSiparisiOlustur()');
  const siparisAdet = Number(ortam.psqlTek("select count(*)::text from public.siparisler"));
  sonuc(siparisAdet === 1 && !toastVar(e, 'stok yetersiz'),
    'iade: sayfada olmayan urun icin stok kontrolu SUNUCUDAN gecti',
    siparisAdet + ' iade siparisi olustu');

  // Simdi okuma bozuk: iade hic baslamamali.
  ortam.psql(`truncate public.siparisler, public.siparis_kalemleri;`);
  const e2 = await ekran('D1');
  await e2.calistir('stokListesiYenile()');
  e2.fetchAraciAyarla(async (url, sec, calistir) => {
    if (url.includes('/stok?select=urun_kodu,miktar')) return new Response('bozuk', { status: 503 });
    return calistir();
  });
  const f2 = e2.el('iade-firma');
  f2.value = '00000000-0000-0000-0000-000000000001';
  f2.selectedIndex = 0;
  f2.options = [{ dataset: { ad: 'Test Firma' } }];
  e2.el('iade-otel').value = '810';
  e2.el('iade-depo').value = 'D1';
  e2.calistir(`IADE_KALEMLER=[{id:'t1',kod:'AAA001',ad:'A urunu 1',birim:'KG',miktar:'5'}];`);
  await e2.calistir('iadeSiparisiOlustur()');
  const adet2 = Number(ortam.psqlTek("select count(*)::text from public.siparisler"));
  sonuc(adet2 === 0 && toastVar(e2, 'okunamadı'),
    'iade: stok okunamazsa siparis HIC olusmuyor',
    adet2 + ' siparis | mesaj: ' + (toastlar(e2).slice(-1)[0] || '—').slice(0, 60));
}

// --- 7) SAYIM: ekran TUM depoyu kapsiyor ------------------------------------
{
  seedDepolar();
  const e = await ekran('D1');
  await e.calistir('stokListesiYenile()');               // liste yalniz 100 satir
  await e.calistir('renderSayimYeni()');
  const sayimAdet = e.calistir('(_sayimStok||[]).length');
  const sistemAdet = e.calistir('Object.keys(_sayimSistemMiktar||{}).length');
  sonuc(sayimAdet === 300 && sistemAdet === 300,
    'sayim ekrani deponun TAMAMINI kapsiyor (yuklenmis sayfayi degil)',
    'sayim listesi ' + sayimAdet + ' urun, sistem miktari ' + sistemAdet + ' urun (bekl. 300)');
}

// --- 8) SAYIM: depo stogu okunamazsa sayim KAYDEDILMIYOR ---------------------
{
  seedDepolar();
  ortam.psql(`truncate public.sayim_oturumlari, public.sayim_detaylari;`);
  const e = await ekran('D1');
  e.fetchAraciAyarla(async (url, sec, calistir) => {
    if (url.includes('stok_liste')) return new Response('bozuk', { status: 503 });
    return calistir();
  });
  await e.calistir('renderSayimYeni()');
  const hata = e.calistir('_sayimStokHata');
  e.calistir(`sayimSatirlari={AAA001:{sayilan:10,fark:-40,farkYuzde:80,aciklama:'x',urunAd:'A',birim:'KG',sistemMiktar:50}};`);
  await e.calistir('sayimTamamla()');
  const oturumAdet = Number(ortam.psqlTek("select count(*)::text from public.sayim_oturumlari"));
  sonuc(!!hata && oturumAdet === 0,
    'sayim: depo stogu eksiksiz okunamazsa oturum ACILMIYOR',
    'hata="' + String(hata).slice(0, 40) + '", oturum ' + oturumAdet);
}

// --- 9) EXCEL: yuklenmis sayfayi degil, deponun tamamini aktariyor -----------
{
  seedDepolar();
  const e = await ekran('D1');
  await e.calistir('stokListesiYenile()');
  const yuklu = e.calistir('Object.keys(db.stok.D1||{}).length');
  await e.calistir('stokExcelAktar()');
  const satir = e.calistir('__excel && __excel.satirlar.length');
  sonuc(yuklu === 100 && satir === 300,
    'Excel: ekranda 100 satir yuklu olsa da deponun TAMAMI aktariliyor',
    'yuklu ' + yuklu + ', Excel ' + satir + ' satir (bekl. 300)');
}

// --- 10) EXCEL: okuma basarisizsa dosya URETILMIYOR --------------------------
{
  const e = await ekran('D1');
  await e.calistir('stokListesiYenile()');
  e.fetchAraciAyarla(async (url, sec, calistir) => {
    if (url.includes('stok_liste')) return new Response('bozuk', { status: 503 });
    return calistir();
  });
  await e.calistir('stokExcelAktar()');
  const excel = e.calistir('__excel');
  sonuc(excel === null && toastVar(e, 'okunamadı'),
    'Excel: stok eksiksiz okunamazsa dosya URETILMIYOR',
    'excel=' + (excel === null ? 'yok' : 'URETILDI') + ' | mesaj: ' + (toastlar(e).slice(-1)[0] || '—').slice(0, 50));
}

console.log('\nSTOK EKRANI SONUC: ' + ok + ' OK / ' + fail + ' FAIL');
ortam.temizle();
process.exit(fail ? 1 : 0);
