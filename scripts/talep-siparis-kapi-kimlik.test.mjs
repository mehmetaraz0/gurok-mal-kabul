// ===========================================================================
// INV KAPILARI — GERCEK KIMLIK ALTINDA (RLS acikken). Izole, uretime BAGLANMAZ.
// ===========================================================================
// NEDEN BU DOSYA VAR: talep-siparis-bagi-kapilari.test.mjs kapilarin TAMAMINI
// `postgres` superuser olarak olcuyor. Superuser RLS'i atlar. Bagimsiz
// inceleme bu kor noktada UC kritik delik buldu; her biri burada KIMLIKLE
// olculur:
//
//   C1  K5/K6 tetikleyicisi `security invoker`: `talep_siparis_baglari`
//       sorgusu cagiranin RLS'i altinda 0 satir doner -> kapi SESSIZCE
//       atlanir. `ic_talep:kayit` yetkili (siparis modulunde yetkisiz) bir
//       kullanici bagli kalemin miktarini 1'e dusurebilir / birimini
//       degistirebilir.
//   C3  K3 tetikleyicisi `security invoker` olup EXECUTE'u her rolden alinmis
//       bir `security definer` fonksiyonu cagiriyor -> mesru "iptalden geri
//       alma" kalici `permission denied` ile duser.
//   C2  `stok_acik_talep` gorunumu `security_invoker=true`; bag alt sorgusu
//       `siparisler`e katildigi icin siparis modulu yetkisi olmayan
//       kullaniciya `bagli=0` doner -> KALAN degil TOPLAM talep gorunur.
//
// REFERANS ORNEK (spec §1.1): kalem 10 KOL · bag 6 KOL · kalan 4 KOL.
// ===========================================================================
import { barOrtami } from './bar-test-ortam.mjs';
import { kurFikstur, bagYaz } from './talep-siparis-fikstur.mjs';

const MIG = [
  'docs/kurulum/2026-08-04-stok-tablo-viewlar.sql',
  'docs/kurulum/2026-10-11-stok-acik-talep-durum-filtresi.sql',
  'docs/kurulum/2026-10-11-siparis-no-sayac.sql',
  'docs/kurulum/2026-10-11-talep-siparis-baglari.sql',
  'docs/kurulum/2026-10-11-talep-siparis-inv-kapilari.sql',
  'docs/kurulum/2026-10-11-stok-acik-talep-kalan.sql',
];
const O = barOrtami({ ad: 'kapi-kimlik', ag: 'kapi-kimlik-net' });

let ok = 0, fail = 0;
const sonuc = (g, ad, ek) => { console.log((g ? 'OK   ' : 'FAIL ') + ad + (ek ? ' — ' + ek : '')); if (g) ok++; else fail++; };
const es = (ad, bek, olc) => sonuc(Number(bek) === Number(olc), ad, Number(bek) === Number(olc) ? String(olc) : `beklenen=${bek} olculen=${olc}`);
const tek = (q) => O.sql(q).out.trim();
const hat = (r) => (String(r.err).split('\n').filter(l => /ERROR/.test(l))[0] || '(mesaj yok)').slice(0, 150);
// Belirli bir ret kodu bekleniyor: "reddedildi" yetmez, DOGRU sebeple
// reddedilmis olmali. Yetki hatasi (permission denied) kapi sayilmaz.
const retti = (r, desen) => !r.ok && new RegExp(desen).test(String(r.err));
let f;

try {
  await O.kur();
  for (const m of MIG) {
    const r = O.uygulaTekIslem(m);
    sonuc(r.ok, 'F ' + m.split('/').pop(), r.ok ? '' : hat(r));
  }
  f = kurFikstur(O);
  bagYaz(O, f, { kalemId: f.kalemId, siparisNo: f.siparisNo, miktar: 6,
                 hedefBirim: 'KOL', kaynakMiktar: 72, kaynakBirim: 'KG', carpan: 12 });

  // Kimliklerin gercekten farkli yetkide oldugunu ONCE dogrula; aksi halde
  // asagidaki iddialar yanlis sebeple yesil cikabilir.
  const yetkiOku = (q) => (O.kimlikle(f.kimlikTalep, q).out || '').trim().split('\n').pop();
  es('H1 talep kimligi ic_talep kayit yetkisine SAHIP', 1,
    yetkiOku(`select (public.auth_yetki_var('ic_talep','kayit'))::int;`));
  es('H2 talep kimliginin siparis modulunde yetkisi YOK', 0,
    yetkiOku(`select (coalesce(public.auth_yetki_var('siparis_olustur','goruntule'),false)
                   or coalesce(public.auth_yetki_var('siparis_takip','goruntule'),false))::int;`));

  // ---- C1 / K5: bagli kalemin miktari dusurulemez ------------------------
  {
    const r = O.kimlikle(f.kimlikTalep,
      `update public.satin_alma_talep_kalemleri set miktar = 1 where id = '${f.kalemId}'::uuid;`);
    sonuc(retti(r, 'bagli_miktar_altina_dusurulemez'),
      'C1a K5 kapisi KIMLIKLE de reddediyor (miktar 10 -> 1)',
      r.ok ? 'KABUL EDILDI (kapi atlandi)' : hat(r));
    es('C1b kalem miktari degismedi', 10,
      tek(`select miktar::text from public.satin_alma_talep_kalemleri where id='${f.kalemId}'::uuid;`));
  }

  // ---- C1 / K6: bagli kalemin birimi degistirilemez ----------------------
  {
    const r = O.kimlikle(f.kimlikTalep,
      `update public.satin_alma_talep_kalemleri set birim = 'KG' where id = '${f.kalemId}'::uuid;`);
    sonuc(retti(r, 'bagli_kalem_degistirilemez'),
      'C1c K6 kapisi KIMLIKLE de reddediyor (birim KOL -> KG)',
      r.ok ? 'KABUL EDILDI (kapi atlandi)' : hat(r));
    sonuc(tek(`select birim from public.satin_alma_talep_kalemleri where id='${f.kalemId}'::uuid;`) === 'KOL',
      'C1d kalem birimi KOL kaldi');
  }

  // ---- C2: gorunum, siparis yetkisi OLMAYAN kullaniciya KALANI gosterir ---
  {
    const g = O.kimlikle(f.kimlikTalep,
      `select coalesce(sum(talep_miktar),0)::text from public.stok_acik_talep
        where urun_kodu='${f.urunKodu}' and birim='KOL';`);
    const deger = (g.out || '').trim().split('\n').pop();
    sonuc(g.ok && Number(deger) === 4,
      'C2 gorunum siparis yetkisiz kullaniciya KALANI (4 KOL) gosteriyor',
      g.ok ? 'olculen=' + deger + ' (10 ise bag toplami RLS ile suzuldu)' : hat(g));
  }

  // ---- C3 / K3: mesru iptalden geri alma, yetki hatasiyla DUSMEMELI -------
  {
    // Iptal: K3 yalniz 'iptal' -> degil gecisinde calisir, iptale girerken degil.
    const i = O.kimlikle(f.kimlik,
      `update public.siparisler set durum='iptal' where siparis_no='${f.siparisNo}';`);
    sonuc(i.ok, 'C3a siparis iptal edilebildi', i.ok ? '' : hat(i));
    const g = O.kimlikle(f.kimlik,
      `update public.siparisler set durum='bekleyen' where siparis_no='${f.siparisNo}';`);
    sonuc(g.ok, 'C3b iptalden geri alma KIMLIKLE basarili (miktar sigiyor)',
      g.ok ? '' : hat(g));
    sonuc(!/permission denied/i.test(String(g.err)),
      'C3c geri almada "permission denied" YOK', /permission denied/i.test(String(g.err)) ? hat(g) : 'temiz');
    sonuc(tek(`select durum from public.siparisler where siparis_no='${f.siparisNo}';`) === 'bekleyen',
      'C3d siparis durumu bekleyen');
  }

  // ---- C3 / K3 NEGATIF: bosalan miktar yeniden tahsis edildiyse RET ------
  // Spec §12.7'nin zorunlu senaryosu: A iptal -> bosalan 6 KOL B'ye baglanir
  // -> A geri alinamaz.
  {
    O.kimlikle(f.kimlik, `update public.siparisler set durum='iptal' where siparis_no='${f.siparisNo}';`);
    const b = bagYaz(O, f, { kalemId: f.kalemId, siparisNo: f.siparisNo2, miktar: 6,
                             hedefBirim: 'KOL', kaynakMiktar: 72, kaynakBirim: 'KG', carpan: 12 });
    sonuc(b.ok, 'C3e bosalan 6 KOL ikinci siparise baglandi', b.ok ? '' : hat(b));
    const g = O.kimlikle(f.kimlik,
      `update public.siparisler set durum='bekleyen' where siparis_no='${f.siparisNo}';`);
    sonuc(retti(g, 'miktar_asimi|talep_miktari_asildi|asildi'),
      'C3f yeniden tahsisten sonra geri alma REDDEDILDI (dogru sebeple)',
      g.ok ? 'KABUL EDILDI (INV bozuldu)' : hat(g));
    sonuc(tek(`select durum from public.siparisler where siparis_no='${f.siparisNo}';`) === 'iptal',
      'C3g siparis iptal kaldi');
  }

  console.log(`\nSONUC: ${ok} gecti, ${fail} kaldi`);
} catch (e) { console.error('DUR: ' + (e && e.message)); fail++; }
finally { try { O.temizle(); } catch { /* yoksay */ } }
process.exit(fail === 0 ? 0 : 1);
