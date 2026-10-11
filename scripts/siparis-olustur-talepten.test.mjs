// siparis_olustur_talepten: tek transaction + idempotency + birim + INV.
import { readFileSync } from 'node:fs';
import { barOrtami } from './bar-test-ortam.mjs';
import { kurFikstur } from './talep-siparis-fikstur.mjs';

const KOK = new URL('..', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const MIG = [
  'docs/kurulum/2026-10-11-siparis-no-sayac.sql',
  'docs/kurulum/2026-10-11-talep-siparis-baglari.sql',
  'docs/kurulum/2026-10-11-siparisler-islem-anahtari.sql',
  'docs/kurulum/2026-10-11-talep-siparis-inv-kapilari.sql',
  'docs/kurulum/2026-10-11-siparis-olustur-talepten.sql',
];
const O = barOrtami({ ad: 'sip-talep', ag: 'sip-talep-net' });

let ok = 0, fail = 0;
const sonuc = (g, ad, ek) => { console.log((g ? 'OK   ' : 'FAIL ') + ad + (ek ? ' — ' + ek : '')); if (g) ok++; else fail++; };
const es = (ad, bek, olc) => sonuc(Number(bek) === Number(olc), ad, Number(bek) === Number(olc) ? String(olc) : `beklenen=${bek} olculen=${olc}`);
const tek = (q) => O.sql(q).out.trim();
const hata = (r) => (String(r.err).split('\n').filter(l => /ERROR|HATA/.test(l))[0] || '(mesaj yok)').slice(0, 120);
let f;

// RPC cagrisi — gercek uygulama kimligiyle.
const cagir = (ozel = {}) => {
  const p = {
    anahtar: 'anahtar-' + Math.random().toString(36).slice(2, 10),
    otel: '810', firma: 'Test Firma', cari: null,
    tarih: 'current_date', termin: 'null',
    satirlar: [{ talep_kalem_id: f.kalemId, miktar: 6, birim: 'KOL', tahmini_fiyat: 10 }],
    ...ozel,
  };
  return O.kimlikle(f.kimlik, `select public.siparis_olustur_talepten(
      '${p.anahtar}', '${f.talepId}'::uuid, '${p.otel}', '${p.firma}',
      ${p.cari ? `'${p.cari}'::uuid` : 'null'}, ${p.tarih}, ${p.termin},
      '${JSON.stringify(p.satirlar)}'::jsonb)::text;`);
};

const sayac = () => ({
  siparis: Number(tek('select count(*) from public.siparisler;')),
  kalem: Number(tek('select count(*) from public.siparis_kalemleri;')),
  bag: Number(tek('select count(*) from public.talep_siparis_baglari;')),
});
const esSayac = (ad, once) => {
  const s = sayac();
  sonuc(s.siparis === once.siparis && s.kalem === once.kalem && s.bag === once.bag,
    ad, JSON.stringify(s) + ' <- ' + JSON.stringify(once));
};

try {
  await O.kur();
  for (const m of MIG) {
    const r = O.uygulaTekIslem(m);
    sonuc(r.ok, 'F ' + m.split('/').pop(), r.ok ? '' : hata(r));
  }
  f = kurFikstur(O);

  // S1: MUTLU YOL — 6 KOL baglanir, kismi oldugu icin durum 'onaylandi' kalir
  const s1 = cagir();
  sonuc(s1.ok && /"ok"\s*:\s*true/.test(s1.out), 'S1a RPC basarili', hata(s1) || s1.out.slice(0, 90));
  es('S1b bir siparis yazildi', 1, tek("select count(*) from public.siparisler where islem_anahtari is not null;"));
  es('S1c bir bag yazildi', 1, tek('select count(*) from public.talep_siparis_baglari;'));
  es('S1d bag miktari 6 KOL', 6, tek('select miktar from public.talep_siparis_baglari;'));
  es('S1e hedef_birim KOL olarak donduruldu', 1,
    tek("select count(*) from public.talep_siparis_baglari where hedef_birim='KOL';"));
  sonuc(tek(`select durum from public.satin_alma_talepleri where id='${f.talepId}'::uuid;`) === 'onaylandi',
    'S1f kismi karsilamada talep durumu KORUNDU');
  es('S1g urun_kodu sunucuda turetildi', 1,
    tek(`select count(*) from public.talep_siparis_baglari where urun_kodu='${f.urunKodu}';`));

  // Denetim tetikleyicisi kimliksiz yazmayi reddeder; temizlik replica kipinde.
  // INV tetikleyicileri ENABLE ALWAYS oldugu icin replica'da da korur.
  const rep = (q) => O.sql(`set session_replication_role = replica;\n${q}\nset session_replication_role = origin;`);

  // S2: TEK TRANSACTION — her ret yolunda HIC satir kalmiyor
  const once = sayac();
  // BEKLENEN RET KODU DA DOGRULANIR. Sebebi olculdu: yalniz `!r.ok`
  // iddiasi, her cagriyi `yetkisiz` yapan bir bozulmada da yesil kalirdi —
  // yani dokuz testin hicbiri dis tasimaz. Spec §9 bu kodlarin kullaniciya
  // ulasmasini sart kosuyor.
  const retler = [
    ['R-J1 eksik talep_kalem_id', { satirlar: [{ miktar: 1, birim: 'KOL' }] }, 'kalem_kimligi_gecersiz'],
    ['R-J2 null talep_kalem_id', { satirlar: [{ talep_kalem_id: null, miktar: 1, birim: 'KOL' }] }, 'kalem_kimligi_gecersiz'],
    ['R-J3 metin miktar', { satirlar: [{ talep_kalem_id: f.kalemId, miktar: 'bir', birim: 'KOL' }] }, 'miktar_gecersiz'],
    ['R-T1 null tarih', { tarih: 'null' }, 'tarih_gecersiz'],
    ['R-T2 termin tarihten once', { tarih: 'current_date', termin: 'current_date - 1' }, 'termin_gecersiz'],
    ['R-D1 tekrarli kalem', { satirlar: [
      { talep_kalem_id: f.kalemId, miktar: 1, birim: 'KOL' },
      { talep_kalem_id: f.kalemId, miktar: 1, birim: 'KOL' }] }, 'tekrarli_kalem'],
    ['R-B1 cevrilemez birim', { satirlar: [{ talep_kalem_id: f.kalemId, miktar: 1, birim: 'LT' }] }, 'birim_cevrilemez'],
    ['R-M1 asim', { satirlar: [{ talep_kalem_id: f.kalemId, miktar: 99, birim: 'KOL' }] }, 'miktar_asimi'],
    ['R-A1 kisa anahtar', { anahtar: 'abc' }, 'anahtar_gecersiz'],
    // --- spec'in sart kostugu ama uygulanmamis kodlar (bagimsiz inceleme) ---
    ['R-H1 4 ondalikli miktar', { satirlar: [{ talep_kalem_id: f.kalemId2, miktar: '10.0004', birim: 'KG' }] }, 'hassasiyet_asimi'],
    ['R-A2 bosluklu anahtar (CHECK ile tutarsiz)', { anahtar: ' anahtar1 ' }, 'anahtar_gecersiz'],
    ['R-A3 101 karakter anahtar', { anahtar: 'a'.repeat(101) }, 'anahtar_gecersiz'],
    ['R-A4 bos anahtar', { anahtar: '' }, 'anahtar_gecersiz'],
  ];
  for (const [ad, ozel, kod] of retler) {
    const r = cagir(ozel);
    sonuc(!r.ok && new RegExp(kod).test(String(r.err)),
      ad + ' -> ' + kod, r.ok ? 'KABUL EDILDI' : hata(r));
  }
  esSayac('S2 tum retlerden sonra satir sayilari DEGISMEDI', once);

  // R-C1: spec §5 `carpan_gecersiz` ret kodu ISTIYOR; UYGULANMADI ve
  // uygulanmamasi DOGRU. Sebep olculdu: `urun_birim_donusum.carpan` kolonu
  // `numeric NOT NULL CHECK (carpan > 0)`. Yani gecersiz carpan VERI
  // KATMANINDA imkansiz; RPC'ye o dal eklenirse olu kod olur. Burada
  // dayanagin KENDISI sinanir: carpan 0 yazma denemesi REDDEDILMELI.
  const rc1 = O.sql(`update public.urun_birim_donusum set carpan = 0
                      where urun_kodu='${f.urunKodu}';`);
  sonuc(!rc1.ok && /urun_birim_donusum_carpan_check|violates check constraint/.test(String(rc1.err)),
    'R-C1 carpan<=0 veri katmaninda imkansiz (carpan_gecersiz olu kod olurdu)',
    rc1.ok ? 'KABUL EDILDI — spec §5 dali gerekli' : hata(rc1));
  es('R-C1b carpan 12 olarak kaldi', 12,
    tek(`select carpan from public.urun_birim_donusum where urun_kodu='${f.urunKodu}';`));

  // R-K1: kilit sirasi UUID sirasina gore olmali, metin sirasina gore DEGIL.
  // Buyuk/kucuk harf karisimi metin siralamasinda ters sira uretir ve iki
  // oturum kalemleri ters kilitleyip deadlock'a girer.
  sonuc(/order by \(e->>'talep_kalem_id'\)::uuid/.test(
    readFileSync(KOK + 'docs/kurulum/2026-10-11-siparis-olustur-talepten.sql', 'utf8')),
    'R-K1 kilit sirasi uuid cast ile sabitlendi');

  // R-N1: olusturan_ad INSAN ADI olmali; siparis takip ekrani bu kolonu
  // gosteriyor ve diger uc yol oraya `CU.ad` yaziyor.
  sonuc(tek("select olusturan_ad from public.siparisler where islem_anahtari is not null limit 1;") === 'Bag Test',
    'R-N1 olusturan_ad insan adi (JWT sub degil)',
    'olculen=' + tek("select olusturan_ad from public.siparisler where islem_anahtari is not null limit 1;"));

  // R-O1 (Review Focus 2): capraz otel — talep baska otelin
  rep(`update public.satin_alma_talepleri set otel_id='811' where id='${f.talepId}'::uuid;`);
  const ro1 = cagir();
  sonuc(!ro1.ok && /otel_uyusmaz|otel_kapsami_disi/.test(ro1.err),
    'R-O1 capraz otel reddedildi', hata(ro1));
  rep(`update public.satin_alma_talepleri set otel_id='810' where id='${f.talepId}'::uuid;`);

  // I1: ayni anahtar + ayni icerik -> tek siparis, mukerrer:true
  const anahtar = 'idem-anahtar-001';
  const satirlar = [{ talep_kalem_id: f.kalemId2, miktar: 10, birim: 'KG' }];
  const i1 = cagir({ anahtar, satirlar });
  sonuc(i1.ok, 'I1a ilk cagri basarili', hata(i1));
  const i2 = cagir({ anahtar, satirlar });
  sonuc(i2.ok && /"mukerrer"\s*:\s*true/.test(i2.out), 'I1b ikinci cagri mukerrer:true',
    hata(i2) || i2.out.slice(0, 80));
  es('I1c yalniz bir siparis yazildi', 1,
    tek(`select count(*) from public.siparisler where islem_anahtari='${anahtar}';`));

  // I2: ayni anahtar + FARKLI icerik -> anahtar_celiskili
  const i3 = cagir({ anahtar, satirlar: [{ talep_kalem_id: f.kalemId2, miktar: 5, birim: 'KG' }] });
  sonuc(!i3.ok && /anahtar_celiskili/.test(i3.err), 'I2 farkli icerik reddedildi', hata(i3));

  // I3: ESZAMANLI ayni anahtar -> tek siparis
  const anahtar2 = 'idem-anahtar-002';
  const govde = (a) => `select public.siparis_olustur_talepten(
      '${a}', '${f.talepId}'::uuid, '810', 'Es Firma', null, current_date, null,
      '${JSON.stringify([{ talep_kalem_id: f.kalemId, miktar: 1, birim: 'KOL' }])}'::jsonb)::text;`;
  const [e1, e2] = await Promise.all([
    O.paralel(f.kimlik, govde(anahtar2)),
    O.paralel(f.kimlik, govde(anahtar2)),
  ]);
  es('I3a eszamanli ayni anahtar -> tek siparis', 1,
    tek(`select count(*) from public.siparisler where islem_anahtari='${anahtar2}';`));
  // SOZLESME (spec §6.1 son satir): kaybeden ham `duplicate key` DEGIL
  // `{ok:true, mukerrer:true}` alir — idempotency'nin varlik sebebi tam bu
  // durumdur. "En az biri basarili" iddiasi DISSIZ: kisit adi degisip
  // `exception when unique_violation` dali bozulsa kaybeden ham hata alir,
  // istemci "Siparis olusturulamadi (400)" yazar ve bu suit YESIL kalirdi.
  sonuc(e1.ok && e2.ok, 'I3b IKISI DE basarili (kaybeden ham hata almaz)',
    'e1=' + e1.ok + ' e2=' + e2.ok + ' | ' + (hata(e1) || hata(e2) || ''));
  const cikti = String(e1.out || '') + String(e2.out || '');
  sonuc(/"mukerrer"\s*:\s*true/.test(cikti),
    'I3c kaybeden mukerrer:true aldi', cikti.replace(/\s+/g, ' ').slice(0, 130));

  // Ayni anahtar + ayni icerik + BASKA KULLANICI -> siparis numarasi SIZMAZ.
  // Kimlik parmak izinin parcasi oldugu icin iz tutmaz; ustelik o kimligin
  // siparis yetkisi de yok, yani iki katman birden kapatir.
  const i3d = O.kimlikle(f.kimlikTalep, `select public.siparis_olustur_talepten(
      '${anahtar2}'::text, '${f.talepId}'::uuid, '810'::text, 'Es Firma'::text, null::uuid,
      current_date, null::date,
      '${JSON.stringify([{ talep_kalem_id: f.kalemId, miktar: 1, birim: 'KOL' }])}'::jsonb)::text;`);
  sonuc(!i3d.ok && !/C[0-9]{8}/.test(String(i3d.out)),
    'I3d baska kullanici ayni anahtarla siparis numarasi SIZDIRAMIYOR',
    i3d.ok ? 'YANIT VERDI: ' + String(i3d.out).slice(0, 80) : hata(i3d));

  // I4: PK ihlali mukerrer SAYILMAZ — parmak izi bozulursa celiski yakalanir
  const i4 = cagir({ anahtar: 'mutant-anahtar-01',
                     satirlar: [{ talep_kalem_id: f.kalemId, miktar: 1, birim: 'KOL' }] });
  sonuc(i4.ok, 'I4a yeni anahtar kabul', hata(i4));
  rep(`update public.siparisler set islem_parmak_izi = 'bozuk'
        where islem_anahtari = 'mutant-anahtar-01';`);
  const i4b = cagir({ anahtar: 'mutant-anahtar-01',
                      satirlar: [{ talep_kalem_id: f.kalemId, miktar: 1, birim: 'KOL' }] });
  sonuc(!i4b.ok && /anahtar_celiskili/.test(i4b.err),
    'I4b parmak izi bozulunca celiski yakalandi', hata(i4b));

  // --- BIRIM ---
  rep('delete from public.talep_siparis_baglari;');
  rep('delete from public.siparis_kalemleri;');
  rep('delete from public.siparisler where islem_anahtari is not null;');

  // B1: 72 KG siparis satiri 10 KOL talebe 6 KOL olarak baglanir (carpan 12)
  const b1 = cagir({ satirlar: [{ talep_kalem_id: f.kalemId, miktar: 72, birim: 'KG' }] });
  sonuc(b1.ok, 'B1a 72 KG -> KOL cevrildi', hata(b1));
  es('B1b bag miktari 6 KOL', 6, tek('select miktar from public.talep_siparis_baglari;'));
  es('B1c hedef_birim KOL', 1,
    tek("select count(*) from public.talep_siparis_baglari where hedef_birim='KOL';"));
  es('B1d carpan kaydedildi', 1,
    tek('select count(*) from public.talep_siparis_baglari where carpan is not null;'));
  es('B1e kaynak 72 KG korundu', 1,
    tek("select count(*) from public.talep_siparis_baglari where kaynak_miktar=72 and kaynak_birim='KG';"));

  // B2: donusum pasiflestirilirse artik cevrilemez
  rep(`update public.urun_birim_donusum set silindi = true where urun_kodu='${f.urunKodu}';`);
  const b2 = cagir({ satirlar: [{ talep_kalem_id: f.kalemId, miktar: 12, birim: 'KG' }] });
  sonuc(!b2.ok && /birim_cevrilemez/.test(b2.err), 'B2 pasif donusum kullanilmiyor', hata(b2));
  rep(`update public.urun_birim_donusum set silindi = false where urun_kodu='${f.urunKodu}';`);

  // T1: TAM karsilamada talep durumu 'siparis' olur
  rep('delete from public.talep_siparis_baglari;');
  rep(`update public.satin_alma_talepleri set durum='onaylandi' where id='${f.talepId}'::uuid;`);
  rep(`delete from public.satin_alma_talep_kalemleri where id='${f.kalemId2}'::uuid;`);
  const t1 = cagir({ satirlar: [{ talep_kalem_id: f.kalemId, miktar: 10, birim: 'KOL' }] });
  sonuc(t1.ok && /"tam_karsilandi"\s*:\s*true/.test(t1.out), 'T1a tam karsilandi bildirildi',
    hata(t1) || t1.out.slice(0, 80));
  sonuc(tek(`select durum from public.satin_alma_talepleri where id='${f.talepId}'::uuid;`) === 'siparis',
    'T1b talep durumu siparis oldu');

  console.log(`\nSONUC: ${ok} gecti, ${fail} kaldi`);
} catch (e) { console.error('DUR: ' + (e && e.message)); fail++; }
finally { try { O.temizle(); } catch { /* yoksay */ } }
process.exit(fail === 0 ? 0 : 1);
