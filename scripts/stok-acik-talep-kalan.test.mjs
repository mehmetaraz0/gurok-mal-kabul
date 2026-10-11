// stok_acik_talep: kalan miktar + BIRIM DONDURMA kaniti.
// Kritik iddia: carpan / katalog birimi / donusum degisirse ESKI KALAN DEGISMEZ.
//
// REFERANS ORNEK (spec §1.1): kalem 10 KOL · siparis satiri 72 KG · yazma
// aninda 12 KG/KOL -> bag 6 KOL -> kalan 4 KOL.
import { readFileSync } from 'node:fs';
import { barOrtami } from './bar-test-ortam.mjs';
import { kurFikstur, bagYaz } from './talep-siparis-fikstur.mjs';

const KOK = new URL('..', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const M6 = 'docs/kurulum/2026-10-11-stok-acik-talep-kalan.sql';
// Taban dokum (2026-09-13) stok gorunumlerinden ONCE alindi; o ucu uretime
// 2026-10-10'da uygulandi, durum filtresi duzeltmesi de 2026-10-11'de.
// Test tabani URETIMIN BUGUNKU HALINE esitlenir ve M6 bunun UZERINE uygulanir:
// boylece yukseltme yolunun kendisi de sinanir.
const MIG = [
  'docs/kurulum/2026-08-04-stok-tablo-viewlar.sql',
  'docs/kurulum/2026-10-11-stok-acik-talep-durum-filtresi.sql',
  'docs/kurulum/2026-10-11-siparis-no-sayac.sql',
  'docs/kurulum/2026-10-11-talep-siparis-baglari.sql',
  'docs/kurulum/2026-10-11-talep-siparis-inv-kapilari.sql',
  M6,
];
const O = barOrtami({ ad: 'acik-talep', ag: 'acik-talep-net' });

let ok = 0, fail = 0;
const sonuc = (g, ad, ek) => { console.log((g ? 'OK   ' : 'FAIL ') + ad + (ek ? ' — ' + ek : '')); if (g) ok++; else fail++; };
const es = (ad, bek, olc) => sonuc(Number(bek) === Number(olc), ad, Number(bek) === Number(olc) ? String(olc) : `beklenen=${bek} olculen=${olc}`);
const tek = (q) => O.sql(q).out.trim();
const hata = (r) => (String(r.err).split('\n').filter(l => /ERROR/.test(l))[0] || '(mesaj yok)').slice(0, 110);
let f;
// GORUNUM KIMLIKLE OKUNUR. Sebep olculdu: superuser RLS'i atlar ve bag
// toplaminin cagiran yetkisine bagli oldugu durumu GOREMEZ (bagimsiz
// inceleme bulgusu C2). Okuyan kimlik `ic_talep` + `stok_takip` yetkili,
// SIPARIS modulunde yetkisiz — gorunumun gercek tuketici profili.
const gorunum = (q) => ((O.kimlikle(f.kimlikTalep, q).out || '').trim().split('\n').pop() || '').trim();
const kalan = (birim) => gorunum(`select coalesce(sum(talep_miktar),0)::text from public.stok_acik_talep
  where urun_kodu='${f.urunKodu}' and birim='${birim}';`);
const rep = (q) => O.sql(`set session_replication_role = replica;\n${q}\nset session_replication_role = origin;`);

try {
  await O.kur();
  for (const m of MIG) {
    const r = O.uygulaTekIslem(m);
    sonuc(r.ok, 'F ' + m.split('/').pop(), r.ok ? '' : hata(r));
  }
  f = kurFikstur(O);
  // REFERANS ORNEK: kalem 10 KOL, siparis satiri 72 KG, carpan 12 -> bag 6 KOL.
  // Kalem2: 100 KG (ayri birim satiri).
  bagYaz(O, f, { kalemId: f.kalemId, siparisNo: f.siparisNo, miktar: 6,
                 hedefBirim: 'KOL', kaynakMiktar: 72, kaynakBirim: 'KG', carpan: 12 });

  // B1 TABAN — 10 KOL - 6 KOL = 4 KOL
  es('B1a KOL kalan 4 KOL', 4, kalan('KOL'));
  es('B1b KG kalan 100 (ayri satir)', 100, kalan('KG'));
  es('B1c birim bazinda IKI satir var', 2,
    gorunum(`select count(*)::text from public.stok_acik_talep where urun_kodu='${f.urunKodu}';`));

  // B2 CARPAN DEGISTI 12 -> 24: eski kalan DEGISMEZ
  O.sql(`update public.urun_birim_donusum set carpan = 24 where urun_kodu='${f.urunKodu}';`);
  es('B2 carpan 24 olunca KOL kalan hala 4 KOL', 4, kalan('KOL'));

  // B3 KATALOG BIRIMI DEGISTI KG -> LT
  O.sql(`update public.urunler set birim='LT' where kod='${f.urunKodu}';`);
  es('B3 katalog birimi LT olunca KOL kalan hala 4 KOL', 4, kalan('KOL'));
  O.sql(`update public.urunler set birim='KG' where kod='${f.urunKodu}';`);

  // B4 DONUSUM PASIFLESTI
  O.sql(`update public.urun_birim_donusum set silindi = true where urun_kodu='${f.urunKodu}';`);
  es('B4 donusum pasif olunca KOL kalan hala 4 KOL', 4, kalan('KOL'));

  // B5 DONUSUM SATIRI SILINDI
  O.sql(`delete from public.urun_birim_donusum where urun_kodu='${f.urunKodu}';`);
  es('B5 donusum silinince KOL kalan hala 4 KOL', 4, kalan('KOL'));

  // B6 MUTANT: gorunum GUNCEL carpanla hesaplarsa eski kalan BOZULUR.
  // Beklenen mutant degeri: 10 × 24 − 6 = 234 (dogrusu 4 KOL).
  O.sql(`insert into public.urun_birim_donusum (urun_kodu, buyuk_birim, carpan, silindi)
          values ('${f.urunKodu}','KOL',24,false);`);
  // Mutant da ayni kolon sirasini kullanmak ZORUNDA (`birim` sonda); aksi
  // halde `create or replace view` reddedilir ve test ESKI gorunumu olcer —
  // olculdu: o durumda B6 yanlis sebeple yesil cikiyor (110 = 10 + 100).
  const mv = O.sql(`create or replace view public.stok_acik_talep with (security_invoker=true) as
    select t.otel_id, tk.urun_kodu,
           sum(tk.miktar * coalesce(d.carpan,1) - coalesce(b.bagli,0)) as talep_miktar,
           u.birim as birim
      from public.satin_alma_talep_kalemleri tk
      join public.satin_alma_talepleri t on t.id = tk.talep_id
      left join public.urunler u on u.kod = tk.urun_kodu
      left join public.urun_birim_donusum d on d.urun_kodu = tk.urun_kodu and d.silindi = false
      left join (select talep_kalem_id, sum(bagli) bagli
                   from public.talep_bag_toplam() group by talep_kalem_id) b
             on b.talep_kalem_id = tk.id
     where t.durum not in ('iptal','reddedildi')
     group by t.otel_id, tk.urun_kodu, u.birim;`);
  sonuc(mv.ok, 'B6-haz mutant gorunum kuruldu (kolon sirasi uyumlu)',
    mv.ok ? '' : hata(mv));
  const mutantKalan = Number(gorunum(`select coalesce(sum(talep_miktar),0)::text
    from public.stok_acik_talep where urun_kodu='${f.urunKodu}';`));
  sonuc(mutantKalan !== 4, 'B6 MUTANT: guncel carpanla hesap eski kalani BOZUYOR',
    'mutant kalan=' + mutantKalan + ' (dogru deger 4)');
  O.uygulaTekIslem(M6);
  es('B6b orijinal gorunum geri geldi, kalan 4 KOL', 4, kalan('KOL'));

  // IP1: siparis iptal edilince kalan GERI DONER, bag satiri KALIR
  rep(`update public.siparisler set durum='iptal' where siparis_no='${f.siparisNo}';`);
  es('IP1a iptal sonrasi KOL kalan 10', 10, kalan('KOL'));
  es('IP1b bag satiri korundu', 1,
    tek(`select count(*) from public.talep_siparis_baglari where siparis_no='${f.siparisNo}';`));
  rep(`update public.siparisler set durum='bekleyen' where siparis_no='${f.siparisNo}';`);
  es('IP1c iptal geri alinca kalan yine 4', 4, kalan('KOL'));

  // IP2: talep iptal/reddedildi ise gorunumde yok
  rep(`update public.satin_alma_talepleri set durum='iptal' where id='${f.talepId}'::uuid;`);
  es('IP2 iptal talep gorunumde yok', 0,
    gorunum(`select count(*)::text from public.stok_acik_talep where urun_kodu='${f.urunKodu}';`));
  rep(`update public.satin_alma_talepleri set durum='onaylandi' where id='${f.talepId}'::uuid;`);

  // K1: KOLON SOZLESMESI. Istemci `select=otel_id,urun_kodu,birim,talep_miktar`
  // istiyor; gorunum bu adlardan BIRINI bile kaybederse PostgREST 400 doner,
  // istemcide `if(rt.ok)` saglanmaz ve Talep sutunu BUTUN urunlerde sessizce
  // bos kalir (ikinci bagimsiz inceleme I-7/I-11). Kolonlar burada ADLARIYLA
  // iddia edilir; yoksa bu sessiz kirilmayi hicbir kapi yakalamaz.
  {
    const kolonlar = tek(`select string_agg(column_name, ',' order by column_name)
      from information_schema.columns
     where table_schema='public' and table_name='stok_acik_talep';`);
    sonuc(kolonlar === 'birim,otel_id,talep_miktar,urun_kodu',
      'K1 gorunum TAM OLARAK dort kolonu bu adlarla donduruyor', kolonlar);
  }

  // D1: denetim sorgusu temiz tabanda 0 satir
  es('D1 hedef_birim ayrismasi yok', 0, tek(`select count(*) from public.talep_siparis_baglari b
    join public.satin_alma_talep_kalemleri tk on tk.id = b.talep_kalem_id
   where b.hedef_birim <> tk.birim;`));

  // S1: kalan sifirsa satir yok
  bagYaz(O, f, { kalemId: f.kalemId, siparisNo: f.siparisNo2, miktar: 4, hedefBirim: 'KOL' });
  es('S1 kalan sifir olunca KOL satiri yok', 0,
    gorunum(`select count(*)::text from public.stok_acik_talep
          where urun_kodu='${f.urunKodu}' and birim='KOL';`));

  console.log(`\nSONUC: ${ok} gecti, ${fail} kaldi`);
} catch (e) { console.error('DUR: ' + (e && e.message)); fail++; }
finally { try { O.temizle(); } catch { /* yoksay */ } }
process.exit(fail === 0 ? 0 : 1);
