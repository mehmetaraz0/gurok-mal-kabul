// ===========================================================================
// BAG GERI YAZMA — izole test (uretime BAGLANMAZ)
// ===========================================================================
// Geri yazma dosyasi URETIM VERISINE dokunacak; bu yuzden once izole ortamda
// uretimin OLCULEN sekli taklit edilir ve dosyanin:
//   1. 12 bagi dogru kalem/siparis/miktar ile yazdigi,
//   2. kapsam disi birakilanlara DOKUNMADIGI,
//   3. yanlis girdide SESSIZCE gecmedigi — her kontrolun dis tasidigi
// olculur. Mutantlar: ikinci kosum, bozuk miktar, iptal siparis, eksik kalem.
//
// Fikstur sayilari uretim sondasindan alindi (2026-10-11):
//   9a109899: 2 kalem · 1f80e26a: 10 kalem · 72f378c0: 1 kalem
//   49a7bab2 + c06e4939: CARTE DOR cifti (ayni siparis) · dept 100: 2 kalem
// ===========================================================================
import { barOrtami } from './bar-test-ortam.mjs';

const MIG = [
  'docs/kurulum/2026-08-04-stok-tablo-viewlar.sql',
  'docs/kurulum/2026-10-11-stok-acik-talep-durum-filtresi.sql',
  'docs/kurulum/2026-10-11-siparis-no-sayac.sql',
  'docs/kurulum/2026-10-11-talep-siparis-baglari.sql',
  'docs/kurulum/2026-10-11-siparisler-islem-anahtari.sql',
  'docs/kurulum/2026-10-11-talep-siparis-inv-kapilari.sql',
  'docs/kurulum/2026-10-11-stok-acik-talep-kalan.sql',
];
const GERI = 'docs/kurulum/2026-10-11-talep-siparis-bag-geri-yazma.sql';
const O = barOrtami({ ad: 'geri-yazma', ag: 'geri-yazma-net' });

let ok = 0, fail = 0;
const sonuc = (g, ad, ek) => { console.log((g ? 'OK   ' : 'FAIL ') + ad + (ek ? ' — ' + ek : '')); if (g) ok++; else fail++; };
const es = (ad, bek, olc) => sonuc(Number(bek) === Number(olc), ad, Number(bek) === Number(olc) ? String(olc) : `beklenen=${bek} olculen=${olc}`);
const tek = (q) => O.sql(q).out.trim();
const hat = (r) => (String(r.err).split('\n').filter(l => /ERROR/.test(l))[0] || '(mesaj yok)').slice(0, 160);
const retti = (r, desen) => !r.ok && new RegExp(desen).test(String(r.err));

// Uretimin olculen sekli: 7 bagsiz talep, kalemleri ve aday siparisleri.
const T1 = '9a109899-75ad-4a5c-a06d-4bf839447baf';
const T2 = '1f80e26a-1eb8-449e-885a-1807f8ada01d';
const T3 = '49a7bab2-0621-408d-a033-9101e0432751';
const T4 = 'c06e4939-f2ad-48eb-a683-ea47fcee01ff';
const T5 = '72f378c0-9269-4f71-85bf-cfc605ea2a37';
const T6 = '0f3febe3-03b7-40cc-8d0a-0c9369ea1c01';
const T7 = '86c05d06-3705-4861-8d1d-c5183c6d9f60';

// (urun, birim) · (talep, urun, miktar) · (siparis, urun, miktar, durum)
const URUNLER = [
  ['YIY01000002', 'KG'], ['YIY06000001', 'KG'], ['YIY03000001', 'TNK'],
  ['YIY03000002', 'KG'], ['YIY03000004', 'KG'], ['YIY03000005', 'KG'],
  ['YIY03000006', 'KG'], ['YIY03000007', 'KG'], ['YIY03000008', 'KG'],
  ['YIY03000009', 'KG'], ['YIY03000010', 'KG'], ['YIY11000005', 'KG'],
  ['YIY06000010', 'KG'], ['YIY04000020', 'KTU'], ['YIY09000001', 'KG'],
];
const KALEMLER = [
  [T1, 'YIY01000002', 69, 'KG'], [T1, 'YIY06000001', 1500, 'KG'],
  [T2, 'YIY03000001', 7, 'TNK'], [T2, 'YIY03000002', 180, 'KG'],
  [T2, 'YIY03000004', 20, 'KG'], [T2, 'YIY03000005', 50, 'KG'],
  [T2, 'YIY03000006', 100, 'KG'], [T2, 'YIY03000007', 38, 'KG'],
  [T2, 'YIY03000008', 20, 'KG'], [T2, 'YIY03000009', 18, 'KG'],
  [T2, 'YIY03000010', 10, 'KG'], [T2, 'YIY11000005', 120, 'KG'],
  [T3, 'YIY04000020', 11, 'KTU'], [T4, 'YIY04000020', 10, 'KTU'],
  [T5, 'YIY06000010', 11, 'KG'],
  [T6, 'YIY09000001', 5, 'KG'], [T7, 'YIY09000001', 3, 'KG'],
];
const SIPARISLER = [
  ['C00091128', 'YIY01000002', 55, 'KG', 'tamamlandi'],
  ['C00091129', 'YIY01000002', 69, 'KG', 'kismi'],
  ['C00091130', 'YIY06000001', 1500, 'KG', 'tamamlandi'],
  ['C00091135', 'YIY03000009', 18, 'KG', 'tamamlandi'],
  ['C00091136', 'YIY03000001', 7, 'TNK', 'tamamlandi'],
  ['C00091137', 'YIY11000005', 120, 'KG', 'bekleyen'],
  ['C00091138', 'YIY03000010', 10, 'KG', 'iptal'],
  ['C00091140', 'YIY03000006', 100, 'KG', 'tamamlandi'],
  ['C00091144', 'YIY04000020', 10, 'KTU', 'bekleyen'],
  ['C00091145', 'YIY06000010', 11, 'KG', 'tamamlandi'],
];
// C00091139 BES kalem tasir (ayni firma grubu) — tekil kisit (kalem, siparis)
// ciftinde oldugu icin bu dogru ve test edilmesi gereken sekildir.
const S139 = [['YIY03000002', 180], ['YIY03000004', 20], ['YIY03000005', 50],
              ['YIY03000007', 38], ['YIY03000008', 20]];

function fikstur() {
  const q = [`set session_replication_role = replica;`,
    `insert into public.urunler (kod, ad, birim) values ` +
      URUNLER.map(([k, b]) => `('${k}','Urun ${k}','${b}')`).join(',') +
      ` on conflict (kod) do nothing;`,
    `insert into public.satin_alma_talepleri (id, departman, otel_id, durum) values ` +
      [[T1, 'DEPO'], [T2, 'DEPO'], [T3, 'DEPO'], [T4, 'DEPO'],
       [T5, 'ANA_MUTFAK'], [T6, '100'], [T7, '100']]
        .map(([id, d]) => `('${id}'::uuid,'${d}','810','siparis')`).join(',') +
      ` on conflict (id) do nothing;`,
    `insert into public.satin_alma_talep_kalemleri (talep_id, urun_adi, urun_kodu, miktar, birim) values ` +
      KALEMLER.map(([t, u, m, b]) => `('${t}'::uuid,'Urun ${u}','${u}',${m},'${b}')`).join(',') + `;`,
    `insert into public.siparisler (siparis_no, firma_ad, otel_id, tarih, durum) values ` +
      SIPARISLER.map(([s, , , , d]) => `('${s}','Firma','810', current_date, '${d}')`).join(',') +
      `,('C00091139','Firma','810', current_date, 'kismi')` +
      ` on conflict (siparis_no) do nothing;`,
    `insert into public.siparis_kalemleri (siparis_no, urun_kodu, urun_adi, miktar, birim, gelen_miktar, kalan_miktar) values ` +
      SIPARISLER.map(([s, u, m, b]) => `('${s}','${u}','Urun ${u}',${m},'${b}',0,${m})`).join(',') + `,` +
      S139.map(([u, m]) => `('C00091139','${u}','Urun ${u}',${m},'KG',0,${m})`).join(',') + `;`,
    `set session_replication_role = origin;`].join('\n');
  const r = O.sql(q);
  if (!r.ok) throw new Error('fikstur kurulamadi:\n' + hat(r));
}
const bagSay = () => tek(`select count(*) from public.talep_siparis_baglari;`);
const acik = (talep, urun) => tek(`select coalesce(sum(tk.miktar - coalesce(b.bagli,0)),0)::text
  from public.satin_alma_talep_kalemleri tk
  left join (select talep_kalem_id, sum(miktar) bagli from public.talep_siparis_baglari
              group by talep_kalem_id) b on b.talep_kalem_id = tk.id
 where tk.talep_id='${talep}'::uuid and tk.urun_kodu='${urun}';`);

try {
  await O.kur();
  for (const m of MIG) {
    const r = O.uygulaTekIslem(m);
    sonuc(r.ok, 'F ' + m.split('/').pop(), r.ok ? '' : hat(r));
  }
  fikstur();
  es('H1 17 talep kalemi kuruldu', 17,
    tek(`select count(*) from public.satin_alma_talep_kalemleri;`));
  es('H2 bag tablosu bos', 0, bagSay());

  // ---- G1 MUTLU YOL ------------------------------------------------------
  {
    const r = O.uygulaTekIslem(GERI);
    sonuc(r.ok, 'G1a geri yazma uygulandi', r.ok ? '' : hat(r));
    es('G1b 12 bag yazildi', 12, bagSay());
    es('G1c hepsi geri-yazma damgali', 12,
      tek(`select count(*) from public.talep_siparis_baglari
            where olusturan_ad='geri-yazma-2026-10-11';`));
    es('G1d donusum yok (carpan null)', 12,
      tek(`select count(*) from public.talep_siparis_baglari where carpan is null;`));
    es('G1e hedef_birim kalem birimiyle ayni', 0,
      tek(`select count(*) from public.talep_siparis_baglari b
            join public.satin_alma_talep_kalemleri tk on tk.id=b.talep_kalem_id
           where b.hedef_birim <> tk.birim;`));
    es('G1f C00091139 bes bag tasiyor (firma grubu izi)', 5,
      tek(`select count(*) from public.talep_siparis_baglari where siparis_no='C00091139';`));
  }

  // ---- G2 KARSILANAN kalemlerin KALANI sifir -----------------------------
  es('G2a T1 DANA kalan 0', 0, acik(T1, 'YIY01000002'));
  es('G2b T1 PATATES kalan 0', 0, acik(T1, 'YIY06000001'));
  es('G2c T2 TEREYAG kalan 0', 0, acik(T2, 'YIY11000005'));
  es('G2d T5 BRUKSEL kalan 0', 0, acik(T5, 'YIY06000010'));

  // ---- G3 KAPSAM DISI BIRAKILANLARA DOKUNULMADI --------------------------
  // Bu dort satir bilincli olarak ACIK kalir; "ekran temizlendi" diye
  // sessizce baglanmalari, kararin kendisini bozmak olurdu.
  es('G3a PARMESAN (iptal siparis) hala acik 10', 10, acik(T2, 'YIY03000010'));
  es('G3b CARTE DOR T3 hala acik 11', 11, acik(T3, 'YIY04000020'));
  es('G3c CARTE DOR T4 hala acik 10', 10, acik(T4, 'YIY04000020'));
  es('G3d dept 100 T6 hala acik 5', 5, acik(T6, 'YIY09000001'));
  es('G3e dept 100 T7 hala acik 3', 3, acik(T7, 'YIY09000001'));
  es('G3f iptal siparise bag YAZILMADI', 0,
    tek(`select count(*) from public.talep_siparis_baglari where siparis_no='C00091138';`));
  es('G3g CARTE DOR siparisine bag YAZILMADI', 0,
    tek(`select count(*) from public.talep_siparis_baglari where siparis_no='C00091144';`));

  // ---- M1 MUTANT: IKINCI KOSUM reddedilmeli -----------------------------
  {
    const r = O.uygulaTekIslem(GERI);
    sonuc(retti(r, 'ZATEN BAG VAR'), 'M1 ikinci kosum REDDEDILDI (mukerrer kalkani)',
      r.ok ? 'IKINCI KEZ UYGULANDI' : hat(r));
    es('M1b bag sayisi degismedi', 12, bagSay());
  }

  // ---- M2 MUTANT: kalem miktari degisirse SESSIZCE gecmemeli ------------
  {
    O.sql(`delete from public.talep_siparis_baglari;
           set session_replication_role = replica;
           update public.satin_alma_talep_kalemleri set miktar = 68
            where talep_id='${T1}'::uuid and urun_kodu='YIY01000002';
           set session_replication_role = origin;`);
    const r = O.uygulaTekIslem(GERI);
    sonuc(retti(r, 'MIKTAR/BIRIM UYUSMAZ'), 'M2 miktar uyusmazligi REDDEDILDI',
      r.ok ? 'YAZDI' : hat(r));
    es('M2b hicbir bag yazilmadi (tam geri alma)', 0, bagSay());
    O.sql(`set session_replication_role = replica;
           update public.satin_alma_talep_kalemleri set miktar = 69
            where talep_id='${T1}'::uuid and urun_kodu='YIY01000002';
           set session_replication_role = origin;`);
  }

  // ---- M3 MUTANT: siparis IPTAL olursa reddedilmeli ---------------------
  {
    O.sql(`set session_replication_role = replica;
           update public.siparisler set durum='iptal' where siparis_no='C00091139';
           set session_replication_role = origin;`);
    const r = O.uygulaTekIslem(GERI);
    sonuc(retti(r, 'SIPARIS YOK veya IPTAL'), 'M3 iptal siparis REDDEDILDI',
      r.ok ? 'YAZDI' : hat(r));
    es('M3b hicbir bag yazilmadi', 0, bagSay());
    O.sql(`set session_replication_role = replica;
           update public.siparisler set durum='kismi' where siparis_no='C00091139';
           set session_replication_role = origin;`);
  }

  // ---- M4 MUTANT: kalem yoksa (veya ikiye cikarsa) reddedilmeli ---------
  {
    O.sql(`set session_replication_role = replica;
           insert into public.satin_alma_talep_kalemleri (talep_id, urun_adi, urun_kodu, miktar, birim)
             values ('${T5}'::uuid,'Urun YIY06000010','YIY06000010',11,'KG');
           set session_replication_role = origin;`);
    const r = O.uygulaTekIslem(GERI);
    sonuc(retti(r, 'KALEM COZULMEDI'), 'M4 mukerrer kalem REDDEDILDI (1 beklenir)',
      r.ok ? 'YAZDI' : hat(r));
    es('M4b hicbir bag yazilmadi', 0, bagSay());
  }

  // ---- G4 TEMIZ TABANDA tekrar uygulanabilir ----------------------------
  {
    O.sql(`set session_replication_role = replica;
           delete from public.satin_alma_talep_kalemleri
            where ctid in (select max(ctid) from public.satin_alma_talep_kalemleri
                            where talep_id='${T5}'::uuid and urun_kodu='YIY06000010');
           set session_replication_role = origin;`);
    const r = O.uygulaTekIslem(GERI);
    sonuc(r.ok, 'G4 duzeltmeden sonra yeniden uygulandi', r.ok ? '' : hat(r));
    es('G4b yine 12 bag', 12, bagSay());
  }

  console.log(`\nSONUC: ${ok} gecti, ${fail} kaldi`);
} catch (e) { console.error('DUR: ' + (e && e.message)); fail++; }
finally { try { O.temizle(); } catch { /* yoksay */ } }
process.exit(fail === 0 ? 0 : 1);
