// ===========================================================================
// BAR A1 — EKRAN TESTLERI (uretime BAGLANMAZ)
// ===========================================================================
// Ekranlarin GERCEK betigi (bar-ekran-harness.mjs / stok-ekran-harness.mjs),
// gercek PostgREST uzerinden A1 uygulanmis izole veritabanina konusur.
// Olculen: kullanici kararlarinin (1) dogrulama, (2) iptal/istisna,
// (3) sayim ekranda dogru RPC'ye, dogru girdiyle gittigi ve sonucun
// veritabaninda beklenen oldugu. Edge Function'lar bu dosyanin konusu degil
// (G7 uctan uca testi).
// ===========================================================================
import { barOrtami, yerelJwt } from './bar-test-ortam.mjs';
import { K, M, BAR, FOLYO101, EK_TOHUM, a1Yardimcilari } from './bar-a1-tohum.mjs';
import { barEkranKur } from './bar-ekran-harness.mjs';
import { ekranKur } from './stok-ekran-harness.mjs';

const MIG = 'docs/kurulum/2026-09-18-bar-a1-guvenlik.sql';
const O = barOrtami({ ad: 'bar-a1-ekran', ag: 'bar-a1-ekran-net' });
const { q, siparis, VISKI1, tek, stok, hazirla, folyoKapat, sifirla } = a1Yardimcilari(O);
let ok = 0, fail = 0;
const sonuc = (g, ad, ek) => { console.log((g ? 'OK   ' : 'FAIL ') + ad + (ek ? ' — ' + ek : '')); if (g) ok++; else fail++; };
const bekle = (ms) => new Promise((r) => setTimeout(r, ms));
// Ekran init'i async'tir; yakalanmayan reddetme testi dusurmesin, gorunsun.
const reddetmeler = [];
process.on('unhandledRejection', (e) => { reddetmeler.push(String(e && e.message || e)); });

const kisi = (k, ad, rol) => ({ id: k.sub, ad, rol, otel_id: '810' });
function kuyruk(k, yetki, ad = 'Bar 810') {
  return barEkranKur({ html: 'bar-siparis-kuyrugu.html', restUrl: REST, jwt: yerelJwt('authenticated', k.sub),
    kullanici: kisi(k, ad, 'bar'), yetkiler: { bar_siparis_yonetimi: yetki } });
}
async function hazirOl(e) { for (let i = 0; i < 100 && !e.calistir(`SIPARISLER.length`); i++) await bekle(50); }
const sat = (id, alan) => tek(`select ${alan} from public.bar_siparisleri where id='${id}';`);
let REST;

try {
  await O.kur();
  const u = O.uygulaTekIslem(MIG);
  if (!u.ok) throw new Error('A1 uygulanamadi: ' + u.err.slice(-300));
  const t = O.sql(EK_TOHUM);
  if (!t.ok) throw new Error('ek tohum: ' + t.err.slice(-300));
  REST = await O.restBaslat({ port: 3097 });
  console.log('ortam hazir — ' + REST + ' (A1 uygulanmis izole veritabani)\n');

  // ---------------- Kuyruk: dogrulama (karar 1) ----------------
  sifirla();
  const s1 = siparis(K.BAR810, VISKI1, '101').out;
  let e = kuyruk(K.BAR810, 'kayit');
  await hazirOl(e);
  const liste = e.el('liste').innerHTML;
  const kart = liste.slice(liste.indexOf('Oda: 101'));
  sonuc(/Oda doğrulaması bekliyor/.test(kart) && /odaDogrula\('/.test(kart) && /odaReddet\('/.test(kart)
     && !/'hazirlaniyor'\)">Hazırlanıyor/.test(kart),
    'K1 dogrulama bekleyen ucretli sipariste Hazirlaniyor YOK; Dogrula ve Reddet var');
  e.confirmVer(false);
  await e.calistir(`odaDogrula('${s1}')`);
  sonuc(sat(s1, 'oda_dogrulama_durumu') === 'bekliyor' && e.kayit.onaylar.length === 1,
    'K2 beyan onaylanmazsa (confirm hayir) sunucuya gidilmez, sipariş bekler');
  e.confirmVer(true);
  await e.calistir(`odaDogrula('${s1}')`);
  sonuc(sat(s1, `oda_dogrulama_durumu||'|'||dogrulayan::text`) === 'dogrulandi|' + K.BAR810.sub
     && /Oda doğrulandı/.test(e.sonToast()),
    'K3 beyanli dogrulama ekrandan: dogrulandi, DOGRULAYAN ekrani kullanan personel', e.sonToast());

  const s2 = siparis(K.BAR810, VISKI1, '101').out;
  e.promptVer('   ');
  await e.calistir(`odaReddet('${s2}')`);
  sonuc(sat(s2, 'oda_dogrulama_durumu') === 'bekliyor' && /zorunlu/.test(e.sonToast()),
    'K4 bos ret nedeni sunucuya gitmez');
  e.promptVer('Misafir odada degil');
  await e.calistir(`odaReddet('${s2}')`);
  sonuc(sat(s2, `oda_dogrulama_durumu||'|'||durum`) === 'reddedildi|iptal',
    'K5 nedenli ret ekrandan: siparis reddedildi', sat(s2, `oda_dogrulama_durumu||'|'||durum`));

  // ---------------- Kuyruk: kapali folyo istisnasi (karar 2) ----------------
  sifirla();
  const s3 = siparis(K.BAR810, VISKI1, '101').out;
  q(K.BAR810, `select public.bar_siparis_oda_dogrula('${s3}', true);`);
  hazirla(s3);
  folyoKapat();
  e = kuyruk(K.BAR810, 'kayit');
  await hazirOl(e);
  e.confirmVer(false);
  await e.calistir(`teslimEt('${s3}')`);
  sonuc(sat(s3, 'durum') === 'hazir' && /FOLYO/.test(e.kayit.onaylar.join('|').toUpperCase()) && stok('VISKI') === '2.000',
    'K6 FOLYO_KAPALI: ekran servis sorusunu sorar; hayir denirse hicbir sey yazilmaz');
  e.confirmVer(true);
  await e.calistir(`teslimEt('${s3}')`);
  sonuc(sat(s3, 'durum') === 'hazir' && /yetkiniz yok/i.test(e.sonToast()) && stok('VISKI') === '2.000',
    'K7 kayit yetkili personel "servis edildi" deyince REDDEDILIR (istisnayi yalniz yetkili acar)', e.sonToast());
  const sef = kuyruk(K.SEF810, 'tam', 'Sef 810');
  await hazirOl(sef);
  sef.confirmVer(true);
  await sef.calistir(`teslimEt('${s3}')`);
  sonuc(sat(s3, 'durum') === 'istisna_bekliyor' && stok('VISKI') === '1.000'
     && tek(`select count(*) from public.pms_folio_hareketleri where kaynak_id='${s3}';`) === '0'
     && tek(`select durum from public.bar_borc_istisnalari where siparis_id='${s3}';`) === 'acik',
    'K8 yetkili "servis edildi": stok bir kez dustu, borc YOK, istisna acik, siparis tamamlanmis SAYILMAZ');
  await sef.calistir(`yukle()`);
  const iListe = sef.el('liste').innerHTML;
  sonuc(/ön büro çözümü bekliyor/.test(iListe) && !new RegExp(`teslimEt\\('${s3}'\\)`).test(iListe),
    'K9 istisna bekleyen siparis aktif listede gorunur, uzerinde aksiyon dugmesi yok');
  sef.confirmVer(true);
  await sef.calistir(`teslimEt('${s3}')`);
  sonuc(stok('VISKI') === '1.000' && tek(`select count(*) from public.bar_stok_tuketimleri where siparis_id='${s3}';`) === '1',
    'K10 ayni siparise ikinci teslim denemesi: ikinci stok dusumu yok');

  // ---------------- Kuyruk: iptal (karar 2) ----------------
  sifirla();
  const s4 = siparis(K.BAR810, [{ menu_urun_id: M.BIRA, adet: 2 }]).out;
  e = kuyruk(K.BAR810, 'kayit');
  await hazirOl(e);
  e.promptVer('Musteri vazgecti');
  await e.calistir(`iptalEt('${s4}')`);
  sonuc(sat(s4, 'durum') === 'iptal' && stok('BIRA') === '10.000'
     && tek(`select count(*) from public.stok_rezervasyonlari where durum='aktif';`) === '0',
    'K11 yeni siparis iptali: yalniz neden istenir, rezervasyon serbest, stok degismez');

  const s5 = siparis(K.BAR810, [{ menu_urun_id: M.BIRA, adet: 2 }]).out;
  hazirla(s5);
  await e.calistir(`yukle()`);
  await e.calistir(`iptalEt('${s5}')`);
  const rezSayisi = e.calistir(`_iptalRezler.length`);
  sonuc(e.el('iptalForm').style.display === 'flex' && rezSayisi === 1 && /kul-0/.test(e.el('iptalBilesenler').innerHTML),
    'K12 hazirlanmis siparis iptali: bilesen bazli form acilir', 'bilesen ' + rezSayisi);
  e.el('iptalNeden').value = 'Masa kapandi';
  e.el('kul-0').value = '';
  const istekOnce = e.kayit.istekler.length;
  await e.calistir(`iptalFormGonder()`);
  sonuc(e.kayit.istekler.length === istekOnce && sat(s5, 'durum') === 'hazir',
    'K13 kullanilan miktar bos birakilirsa istek GITMEZ (varsayilan yok)');
  e.el('kul-0').value = '1';
  e.el('ned-0').value = 'dokuldu_kirildi';
  e.el('ack-0').value = 'Tepsi devrildi';
  await e.calistir(`iptalFormGonder()`);
  const tuk = tek(`select tur||'|'||kullanim_nedeni||'|'||aciklama||'|'||miktar::text from public.bar_stok_tuketimleri where siparis_id='${s5}';`);
  sonuc(sat(s5, 'durum') === 'iptal' && tuk === 'iptal_kullanimi|dokuldu_kirildi|Tepsi devrildi|1.000' && stok('BIRA') === '9.000'
     && tek(`select count(*) from public.stok_hareketleri where aciklama ilike '%zayi%';`) === '0',
    'K14 kullanilan 1 birim "iptal_kullanimi" + neden + aciklama kaydedildi; zayi YAZILMADI; stok 10 -> 9', tuk);

  // Sunucu hatasi Turkce ve kodla gosterilir
  const s6 = siparis(K.BAR810, [{ menu_urun_id: M.BIRA, adet: 1 }]).out;
  hazirla(s6);
  await e.calistir(`yukle()`);
  await e.calistir(`iptalEt('${s6}')`);
  e.el('iptalNeden').value = 'Test';
  e.el('kul-0').value = '1';
  e.el('ned-0').value = '';
  await e.calistir(`iptalFormGonder()`);
  sonuc(/neden seçin/.test(e.sonToast()) && sat(s6, 'durum') === 'hazir',
    'K15 nedensiz kullanim: sunucu KULLANIM_NEDENI_GEREKLI, ekran Turkce metni gosterir', e.sonToast());

  // ---------------- Garson: fiyat ve dogrulama ----------------
  sifirla();
  const g = barEkranKur({ html: 'bar-garson.html', restUrl: REST, jwt: yerelJwt('authenticated', K.BAR810.sub),
    kullanici: kisi(K.BAR810, 'Bar 810', 'bar'), yetkiler: { bar_siparis_yonetimi: 'kayit' },
    musteriFetch: async () => new Response(JSON.stringify({ ok: true, masalar: [] }), { status: 200 }) });
  await bekle(300);
  g.calistir(`MASALAR=[{token:'T1',masa_adi:'M1',otel_id:'810',depo_id:'${BAR}',aktif:true}];`);
  g.el('masaSec').value = 'T1';
  await g.calistir(`masaDegisti()`);
  const menuFiyat = g.calistir(`(MENU.find(x=>x.id==='${M.VISKI}')||{}).fiyat`);
  O.sql(`update public.menu_urunler set fiyat = 300 where id = '${M.VISKI}';`);   // ekranin menusu artik bayat
  g.calistir(`SEPET={'${M.VISKI}':{adet:1,ucretli:true}};`);
  g.el('odaNo').value = '101';
  await g.calistir(`gonder()`);
  const yeniFiyat = g.calistir(`(MENU.find(x=>x.id==='${M.VISKI}')||{}).fiyat`);
  sonuc(String(menuFiyat) === '250' && /Fiyat değişti/.test(g.sonToast()) && String(yeniFiyat) === '300'
     && tek(`select count(*) from public.bar_siparisleri;`) === '0',
    'G1 bayat fiyatla gonderim REDDEDILIR; ekran menuyu yeniler (250 -> 300), siparis yazilmaz', g.sonToast());
  g.calistir(`SEPET={'${M.VISKI}':{adet:1,ucretli:true}};`);
  g.el('odaNo').value = '101';
  await g.calistir(`gonder()`);
  const gSip = tek(`select id from public.bar_siparisleri;`);
  sonuc(!!gSip && g.el('dogrulamaPanel').style.display === '' && sat(gSip, 'oda_dogrulama_durumu') === 'bekliyor',
    'G2 guncel fiyatla siparis yazildi; dogrulama paneli ACILDI ama siparis dogrulanmis SAYILMADI');
  g.el('dogrulamaBeyan').checked = false;
  await g.calistir(`odaDogrula()`);
  sonuc(sat(gSip, 'oda_dogrulama_durumu') === 'bekliyor' && /onaylayın/.test(g.sonToast()),
    'G3 beyan kutusu isaretlenmeden dogrulama REDDEDILIR', g.sonToast());
  g.el('dogrulamaBeyan').checked = true;
  await g.calistir(`odaDogrula()`);
  sonuc(sat(gSip, `oda_dogrulama_durumu||'|'||dogrulayan::text||'|'||folio_id::text`) === `dogrulandi|${K.BAR810.sub}|${FOLYO101}`,
    'G4 beyanli dogrulama garson ekranindan: dogrulayan ve folyo kaydedildi');

  // ---------------- Musteri menusu: FIYAT_DEGISTI mesaji (sunucunun GERCEK metni) ----------------
  O.sql(`update public.menu_urunler set fiyat = 300 where id = '${M.VISKI}';`);
  const hata = q(K.QR, `select public.bar_siparis_olustur('810','${BAR}','M1','101',
    '[{"menu_urun_id":"${M.VISKI}","adet":1,"gosterilen_fiyat":250}]'::jsonb);`);
  const sunucuMesaji = (hata.err.match(/FIYAT_DEGISTI:[^\n]*/) || [''])[0];
  const menu = barEkranKur({ html: 'bar-menu.html', restUrl: REST, jwt: 'yok', kullanici: {}, arama: '?t=T1',
    musteriFetch: async (yol, sec) => {
      if (yol.includes('masa_oteli_getir')) return new Response('"810"', { status: 200 });
      if (yol.includes('menu_urunler')) return new Response(JSON.stringify([
        { id: M.VISKI, ad: 'Viski', kategori: 'Icki', ucretli: true, fiyat: 250, aktif: true }]), { status: 200 });
      if (yol.includes('hyper-api')) return new Response(JSON.stringify({ ok: false, mesaj: sunucuMesaji }), { status: 200 });
      throw new Error('beklenmeyen ' + yol);
    } });
  for (let i = 0; i < 100 && !menu.calistir(`MENU.length`); i++) await bekle(50);   // acilista menuYukle()
  menu.calistir(`SEPET={'${M.VISKI}':{adet:1,ucretli:true}};`);
  menu.el('odaNo').value = '101';
  await menu.calistir(`gonder()`);
  const gonderilen = JSON.parse(menu.kayit.istekler.find((r) => r.url.includes('hyper-api')).govde);
  sonuc(!!sunucuMesaji && gonderilen.kalemler[0].gosterilen_fiyat === 250
     && /250 ₺ → 300 ₺/.test(menu.el('mesaj').textContent)
     && String(menu.calistir(`MENU[0].fiyat`)) === '300',
    'M1 musteri menusu gosterilen fiyati gonderir; sunucunun GERCEK FIYAT_DEGISTI metninden yeni fiyati okuyup gosterir',
    menu.el('mesaj').textContent);

  // ---------------- Stok takip: sayim (karar 3) ----------------
  sifirla();
  siparis(K.BAR810, [{ menu_urun_id: M.BIRA, adet: 8 }]);             // BIRA stok 10, rezerve 8
  O.sql(`insert into public.sayim_oturumlari (id, depo_kodu, otel_id, olusturan_ad, durum, toplam_urun_sayisi)
           values ('99999999-0000-0000-0000-000000000001','${BAR}','810','Test','onay_bekliyor',2);
         insert into public.sayim_detaylari (id, oturum_id, urun_kodu, urun_adi, sistem_miktar, sayilan_miktar, fark) values
           ('99999999-0000-0000-0000-0000000000b1','99999999-0000-0000-0000-000000000001','BIRA','Bira',10,5,-5),
           ('99999999-0000-0000-0000-0000000000b2','99999999-0000-0000-0000-000000000001','VISKI','Viski',2,3,1);`);
  // S0 — URETIM BULGUSU (A1'den bagimsiz): 2026-09-13 dokumunde sayim_oturumlari
  // yalniz RESTRICTIVE politika, sayim_detaylari HIC politika tasir (ikisinde de
  // RLS acik). Oturum acmis kullanici bu satirlari GOREMEZ. Olculur, duzeltilmez.
  const okunan = (tablo) => q(K.DEPO810, `select count(*) from public.${tablo};`).out.split('\n').pop();
  sonuc(okunan('sayim_oturumlari') === '0' && okunan('sayim_detaylari') === '0'
     && tek(`select count(*) from public.sayim_oturumlari;`) === '1',
    'S0 OLCUM (uretim semasi): stok yetkili kullanici sayim oturumu/detayi OKUYAMIYOR — permissive politika yok (A1 disi bulgu)');
  // Ekran mantigini sinamak icin YALNIZ bu test ortaminda okuma politikasi. Uretimde YOK.
  O.sql(`create policy test_yalniz_okuma on public.sayim_oturumlari for select to authenticated using (true);
         create policy test_yalniz_okuma on public.sayim_detaylari for select to authenticated using (true);`);
  const st = ekranKur({ restUrl: REST, jwt: yerelJwt('authenticated', K.DEPO810.sub), depo: BAR, rol: 'cost_control' });
  await bekle(1500);
  await st.calistir(`sayimOnayBekleyenleriYukle()`);
  await st.calistir(`sayimOnayla('99999999-0000-0000-0000-000000000001')`);
  const uyari = st.baglam.__uyarilar.join('\n');
  const stokYazmasi = st.istekler.filter((u) => /\/rest\/v1\/stok(\?|$)/.test(u) && !/select=/.test(u));
  sonuc(/SAYIM KISMEN UYGULANDI/.test(uyari) && /BIRA/.test(uyari) && stok('BIRA') === '10.000' && stok('VISKI') === '3.000'
     && stokYazmasi.length === 0,
    'S1 sayim onayi tek RPC: celisen kalem bekler, digeri uygulanir, KISMI uygulama ekranda ACIK uyariyla gosterilir; istemci stoga yazmaz');
  await bekle(300);   // liste yuklemesi onay listesinden sonra beklenmeden baslar
  const bListe = st.el('sayim-bekleyen-liste').innerHTML;
  sonuc(/BIRA/.test(bListe) && /Uygulama\/iptal için stok tam yetkisi gerekir/.test(bListe),
    'S2 bekleyen duzeltme listelenir; stok tam yetkisi olmayan kullaniciya uygula dugmesi gosterilmez', bListe.slice(0, 160));
  q(K.DEPO810, `select public.stok_ekle('BIRA','${BAR}','810',20);`);                // aradaki hareket: 10 -> 30
  const st2 = ekranKur({ restUrl: REST, jwt: yerelJwt('authenticated', K.DEPOSEF810.sub), depo: BAR, rol: 'cost_control' });
  await bekle(1500);
  st2.calistir(`YETKI_HARITASI={stok_takip:'tam'};`);
  await st2.calistir(`sayimBekleyenDuzeltmeleriYukle()`);
  const bekId = tek(`select id from public.stok_sayim_bekleyenleri;`);
  sonuc(new RegExp(`sayimBekleyenUygula\\('${bekId}'\\)`).test(st2.el('sayim-bekleyen-liste').innerHTML),
    'S3 stok tam yetkili kullaniciya Uygula/Iptal gorunur');
  await st2.calistir(`sayimBekleyenUygula('${bekId}')`);
  sonuc(stok('BIRA') === '25.000' && tek(`select durum from public.stok_sayim_bekleyenleri;`) === 'uygulandi',
    'S4 ekrandan bekleyen uygulama: 30 + (-5) = 25 — aradaki +20 korundu, sayilan 5 ustune yazilmadi', 'stok ' + stok('BIRA'));

  sonuc(reddetmeler.length === 0, 'Z1 ekranlarda yakalanmayan hata yok', reddetmeler.slice(0, 3).join(' | '));
} catch (e) {
  sonuc(false, 'beklenmeyen hata', e.stack || e.message);
} finally { O.temizle(); }

console.log(`\nBAR A1 EKRAN: ${ok} OK / ${fail} FAIL`);
// stok-takip ekrani kendi yoklama zamanlayicilarini kurar; surec acik kalmasin.
process.exit(fail ? 1 : 0);
