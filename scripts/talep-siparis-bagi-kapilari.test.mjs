// talep_siparis_baglari: tablo + RLS + INV kapilari (K1-K7) — izole kanit.
import { readFileSync } from 'node:fs';
import { barOrtami } from './bar-test-ortam.mjs';
import { kurFikstur, bagYaz } from './talep-siparis-fikstur.mjs';

const KOK = new URL('..', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const M1 = 'docs/kurulum/2026-10-11-siparis-no-sayac.sql';
const M2 = 'docs/kurulum/2026-10-11-talep-siparis-baglari.sql';
const M4 = 'docs/kurulum/2026-10-11-talep-siparis-inv-kapilari.sql';
const O = barOrtami({ ad: 'bag-kapi', ag: 'bag-kapi-net' });

let ok = 0, fail = 0;
const sonuc = (g, ad, ek) => { console.log((g ? 'OK   ' : 'FAIL ') + ad + (ek ? ' — ' + ek : '')); if (g) ok++; else fail++; };
const es = (ad, bek, olc) => sonuc(Number(bek) === Number(olc), ad, Number(bek) === Number(olc) ? String(olc) : `beklenen=${bek} olculen=${olc}`);
const tek = (q) => O.sql(q).out.trim();
const hata = (r) => (String(r.err).split('\n').filter(l => /ERROR|HATA/.test(l))[0] || '(mesaj yok)').slice(0, 110);
let f;

try {
  await O.kur();
  for (const m of [M1, M2]) {
    const r = O.uygulaTekIslem(m);
    sonuc(r.ok, 'F ' + m.split('/').pop(), r.ok ? '' : hata(r));
  }
  f = kurFikstur(O);
  sonuc(true, 'F2 fikstur kuruldu');

  // Y1: tablo var ve RLS acik
  es('Y1 RLS acik', 1, tek(`select count(*) from pg_class
    where relname='talep_siparis_baglari' and relrowsecurity;`));

  // Y2: authenticated DOGRUDAN yazamaz (politika yok + ayricalik yok)
  const y2 = O.kimlikle(f.kimlik, `insert into public.talep_siparis_baglari
    (otel_id, talep_id, talep_kalem_id, siparis_no, miktar, hedef_birim,
     kaynak_miktar, kaynak_birim)
    values ('810','${f.talepId}'::uuid,'${f.kalemId}'::uuid,'${f.siparisNo}',
            1,'KOL',1,'KOL');`);
  sonuc(!y2.ok, 'Y2 authenticated dogrudan YAZAMIYOR', hata(y2));

  // Y3: authenticated kendi otelinin bagini OKUYABILIR
  bagYaz(O, f, { kalemId: f.kalemId, siparisNo: f.siparisNo, miktar: 1 });
  es('Y3 authenticated okuyabiliyor', 1,
    O.kimlikle(f.kimlik, 'select count(*) from public.talep_siparis_baglari;').out.trim());

  // Y4: BASKA otelin bagini okuyamaz
  O.sql(`update public.talep_siparis_baglari set otel_id='811';`);
  es('Y4 baska otelin bagi gorunmuyor', 0,
    O.kimlikle(f.kimlik, 'select count(*) from public.talep_siparis_baglari;').out.trim());
  O.sql(`update public.talep_siparis_baglari set otel_id='810';`);

  // Y5: ayni kalem + ayni siparis iki kez baglanamaz
  const y5 = bagYaz(O, f, { kalemId: f.kalemId, siparisNo: f.siparisNo, miktar: 1 });
  sonuc(!y5.ok && /talep_siparis_baglari_tekil|duplicate key/.test(y5.err),
    'Y5 (kalem, siparis) cifti tekrarlanamaz', hata(y5));

  // --- Task 3: idempotency kolonlari ---
  const m3 = O.uygulaTekIslem('docs/kurulum/2026-10-11-siparisler-islem-anahtari.sql');
  sonuc(m3.ok, 'F3 islem_anahtari migration', m3.ok ? '' : hata(m3));

  // `siparisler` uzerinde phase0_islem_audit AFTER UPDATE tetikleyicisi var ve
  // kimliksiz yazmayi "Aktif ERP personeli gerekli" ile reddediyor (olculdu).
  // Burada sinanan sey CHECK ve KISMI UNIQUE INDEKS; ikisi de KISIT, tetikleyici
  // degil, bu yuzden `session_replication_role=replica` altinda AKTIF kalirlar.
  // Bu sarmalayici olmadan testler kisiti degil denetim tetikleyicisini olcer.
  const anahtarYaz = (no, anahtar) => O.sql(
    `set session_replication_role = replica;
     update public.siparisler set islem_anahtari = ${anahtar === null ? 'null' : `'${anahtar}'`}
      where siparis_no = '${no}';
     set session_replication_role = origin;`);

  // Ret SEBEBI de dogrulanir: yalniz `!ok` bakmak yanlis-yesil uretiyordu
  // (denetim tetikleyicisi de reddediyordu ve test onu kisit sanıyordu).
  const kisitRetti = (r, desen) => !r.ok && desen.test(r.err);

  // A-S1 (Review Focus 5): 7 karakter CHECK altinda
  sonuc(kisitRetti(anahtarYaz(f.siparisNo, '1234567'), /siparisler_islem_anahtari_bicim/),
    'A-S1 7 karakterli anahtar CHECK ile reddedildi');
  // A-S2: 101 karakter CHECK ustunde
  sonuc(kisitRetti(anahtarYaz(f.siparisNo, 'x'.repeat(101)), /siparisler_islem_anahtari_bicim/),
    'A-S2 101 karakterli anahtar CHECK ile reddedildi');
  // A-S3: bos metin reddedildi
  sonuc(kisitRetti(anahtarYaz(f.siparisNo, ''), /siparisler_islem_anahtari_bicim/),
    'A-S3 bos anahtar CHECK ile reddedildi');
  // A1: gecerli anahtar kabul
  sonuc(anahtarYaz(f.siparisNo, 'anahtar-0001').ok, 'A1 gecerli anahtar kabul');
  // A2: ayni anahtar ikinci siparise YAZILAMAZ (kismi unique)
  sonuc(kisitRetti(anahtarYaz(f.siparisNo2, 'anahtar-0001'), /siparisler_islem_anahtari_key/),
    'A2 ayni anahtar kismi UNIQUE ile reddedildi');
  // A3: null anahtar birden fazla siparise yazilabilir (kismi indeks)
  anahtarYaz(f.siparisNo, null); anahtarYaz(f.siparisNo2, null);
  es('A3 null anahtar kisitlanmiyor', 0,
    tek("select count(*) from public.siparisler where islem_anahtari is not null;"));

  // --- Task 4: INV kapilari ---
  const m4 = O.uygulaTekIslem(M4);
  sonuc(m4.ok, 'F4 INV kapilari migration', m4.ok ? '' : hata(m4));
  O.sql('delete from public.talep_siparis_baglari;');

  // K1: kalem 10 KOL. 6 KOL baglanir, sonra 5 KOL daha -> ASIM
  sonuc(bagYaz(O, f, { kalemId: f.kalemId, siparisNo: f.siparisNo, miktar: 6 }).ok,
    'K1a 6 KOL baglandi');
  const k1 = bagYaz(O, f, { kalemId: f.kalemId, siparisNo: f.siparisNo2, miktar: 5 });
  sonuc(!k1.ok && /miktar_asimi/.test(k1.err), 'K1b 5 KOL daha ASIM ile reddedildi', hata(k1));
  es('K1c asimda satir kalmadi', 1, tek('select count(*) from public.talep_siparis_baglari;'));

  // K2: UPDATE'te eski satir iki kez sayilmamali -> 6 KOL'u 9 KOL'a cikarmak GECERLI
  const k2 = O.sql(`update public.talep_siparis_baglari set miktar = 9
                     where talep_kalem_id = '${f.kalemId}'::uuid;`);
  sonuc(k2.ok, 'K2a 6 -> 9 guncellemesi kabul (old.id iki kez sayilmadi)', hata(k2));
  const k2b = O.sql(`update public.talep_siparis_baglari set miktar = 11
                      where talep_kalem_id = '${f.kalemId}'::uuid;`);
  sonuc(!k2b.ok && /miktar_asimi/.test(k2b.err), 'K2b 11 KOL guncellemesi reddedildi', hata(k2b));
  es('K2c miktar 9 olarak kaldi', 9,
    tek(`select miktar from public.talep_siparis_baglari where talep_kalem_id='${f.kalemId}'::uuid;`));

  // `siparisler` / `siparis_kalemleri` / talep kalemleri uzerindeki denetim
  // tetikleyicisi kimliksiz yazmayi reddeder. INV tetikleyicileri ENABLE ALWAYS
  // oldugu icin replica kipinde de calisir: denetim susar, INV calisir.
  const rep = (q) => O.sql(`set session_replication_role = replica;\n${q}\nset session_replication_role = origin;`);

  // K3 KRITIK SENARYO: A iptal -> serbest miktar B'ye baglanir -> A geri acilamaz
  O.sql('delete from public.talep_siparis_baglari;');
  sonuc(bagYaz(O, f, { kalemId: f.kalemId, siparisNo: f.siparisNo, miktar: 10 }).ok,
    'K3-haz A siparisine 10 KOL (tamami) baglandi');
  rep(`update public.siparisler set durum='iptal' where siparis_no='${f.siparisNo}';`);
  sonuc(bagYaz(O, f, { kalemId: f.kalemId, siparisNo: f.siparisNo2, miktar: 10 }).ok,
    'K3a iptal sonrasi serbest miktar B siparisine baglandi');
  const k3 = rep(`update public.siparisler set durum='bekleyen'
                   where siparis_no='${f.siparisNo}';`);
  sonuc(!k3.ok && /miktar_asimi/.test(k3.err),
    'K3b A siparisini iptalden GERI ALMA reddedildi', hata(k3));
  es('K3c A siparisinin bagi yerinde kaldi', 1,
    tek(`select count(*) from public.talep_siparis_baglari where siparis_no='${f.siparisNo}';`));

  // K7: bagi olan siparis silinemez; bagsiz silinebilir
  const k7 = rep(`delete from public.siparisler where siparis_no='${f.siparisNo}';`);
  sonuc(!k7.ok && /bagli_siparis_silinemez|violates foreign key/.test(k7.err),
    'K7a bagli siparis SILINEMIYOR', hata(k7));
  rep(`insert into public.siparisler (siparis_no, firma_ad, otel_id, tarih, durum)
         values ('C00000003','Bagsiz','810',current_date,'bekleyen')
         on conflict (siparis_no) do nothing;`);
  sonuc(rep("delete from public.siparisler where siparis_no='C00000003';").ok,
    'K7b bagsiz siparis silinebiliyor');

  // K5: talep kalemi miktarini bag toplaminin altina dusurme reddedilir
  const k5 = rep(`update public.satin_alma_talep_kalemleri set miktar = 5
                   where id = '${f.kalemId}'::uuid;`);
  sonuc(!k5.ok && /bagli_miktar_altina_dusurulemez/.test(k5.err),
    'K5a talep miktarini dusurme reddedildi', hata(k5));
  sonuc(rep(`update public.satin_alma_talep_kalemleri set miktar = 20
              where id = '${f.kalemId}'::uuid;`).ok,
    'K5b talep miktarini ARTIRMA serbest');
  rep(`update public.satin_alma_talep_kalemleri set miktar = 10
        where id = '${f.kalemId}'::uuid;`);

  // K6: bagli kalemin birim/urun kodu degistirilemez
  const k6 = rep(`update public.satin_alma_talep_kalemleri set birim = 'KG'
                   where id = '${f.kalemId}'::uuid;`);
  sonuc(!k6.ok && /bagli_kalem_degistirilemez/.test(k6.err),
    'K6a bagli kalemin birimi degistirilemez', hata(k6));
  const k6b = rep(`update public.satin_alma_talep_kalemleri set urun_kodu = 'BASKA'
                    where id = '${f.kalemId}'::uuid;`);
  sonuc(!k6b.ok && /bagli_kalem_degistirilemez/.test(k6b.err),
    'K6b bagli kalemin urun kodu degistirilemez', hata(k6b));

  // K4: siparis kalemi miktarini bag kaynak toplaminin altina dusurme
  rep(`insert into public.siparis_kalemleri (siparis_no, urun_kodu, urun_adi, birim,
        miktar, gelen_miktar, kalan_miktar)
        values ('${f.siparisNo2}','${f.urunKodu}','Bag Test Urunu','KOL',10,0,10);`);
  const k4 = rep(`update public.siparis_kalemleri set miktar = 4
                   where siparis_no='${f.siparisNo2}' and urun_kodu='${f.urunKodu}';`);
  sonuc(!k4.ok && /bagli_miktar_altina_dusurulemez/.test(k4.err),
    'K4a siparis kalemi miktarini dusurme reddedildi', hata(k4));
  sonuc(rep(`update public.siparis_kalemleri set miktar = 15
              where siparis_no='${f.siparisNo2}' and urun_kodu='${f.urunKodu}';`).ok,
    'K4b siparis kalemi miktarini ARTIRMA serbest');

  // --- ESZAMANLILIK ---
  // DETERMINISTIK kurgu: A kalemi `for update` ile kilitler, 2 sn bekler, sonra
  // bag yazar ve commit eder. B 0.4 sn sonra baslar; INV tetikleyicisi ayni
  // kalemi kilitlemeye calisip A'nin commit'ini BEKLER, sonra guncel toplami
  // gorur -> asim. (Task 1'de olculdu: yalnizca N paralel surec baslatmak
  // cakisma GARANTI ETMEZ; kilidi tutan oturum sart.)
  // DURUM SIZMASI TEMIZLIGI: K3 blogu C00000001'i 'iptal' birakti. Iptal
  // siparisin bagi INV'de SAYILMAZ; temizlenmezse eszamanlilik ve mutant
  // testleri iptalli bir siparisle olcer ve yanlis sonuc verir (olculdu:
  // E1 toplami 12 cikti ama INV ihlali yoktu, cunku 6'si iptalliydi).
  // Baglar once silinir ki K3 kapisi iptalden geri almaya izin versin.
  O.sql('delete from public.talep_siparis_baglari;');
  const sifirla = rep(`update public.siparisler set durum='bekleyen'
                        where siparis_no in ('${f.siparisNo}','${f.siparisNo2}');`);
  sonuc(sifirla.ok, 'E0 fikstur siparisleri iptal-disi duruma donduruldu', hata(sifirla));
  es('E0b iki siparis de iptal degil', 0,
    tek(`select count(*) from public.siparisler
          where siparis_no in ('${f.siparisNo}','${f.siparisNo2}') and durum='iptal';`));

  const bagSql = (siparisNo, miktar) => `insert into public.talep_siparis_baglari
      (otel_id, talep_id, talep_kalem_id, siparis_no, urun_kodu, miktar, hedef_birim,
       kaynak_miktar, kaynak_birim, olusturan_ad)
    values ('810','${f.talepId}'::uuid,'${f.kalemId}'::uuid,'${siparisNo}','${f.urunKodu}',
            ${miktar},'KOL',${miktar},'KOL','es');`;
  const esKosum = async () => {
    const A = O.paralel({ rol: 'postgres' },
      `select miktar from public.satin_alma_talep_kalemleri
        where id='${f.kalemId}'::uuid for update;
       select pg_sleep(2);
       ${bagSql(f.siparisNo, 6)}`);
    await new Promise(r => setTimeout(r, 400));
    const B = O.paralel({ rol: 'postgres' }, bagSql(f.siparisNo2, 6));
    return Promise.all([A, B]);
  };
  const [r1, r2] = await esKosum();
  sonuc(r1.ok && !r2.ok, 'E1a birinci gecti, ikinci reddedildi',
    'birinci=' + r1.ok + ' ikinci=' + r2.ok);
  sonuc(/miktar_asimi/.test(r2.err), 'E1b ikincinin reddi miktar_asimi');
  // INV ile AYNI hesap: yalniz iptal olmayan siparislerin baglari.
  es('E1c INV toplami kalem miktarini asmadi', 6,
    tek(`select coalesce(sum(b.miktar),0) from public.talep_siparis_baglari b
           join public.siparisler s on s.siparis_no = b.siparis_no
          where b.talep_kalem_id='${f.kalemId}'::uuid and s.durum <> 'iptal';`));

  // E2 DEADLOCK YOK: iki oturum TERS sirada iki kaleme baglanir
  O.sql('delete from public.talep_siparis_baglari;');
  const kalem2Sql = (siparisNo) => `insert into public.talep_siparis_baglari
      (otel_id, talep_id, talep_kalem_id, siparis_no, urun_kodu, miktar, hedef_birim,
       kaynak_miktar, kaynak_birim, olusturan_ad)
    values ('810','${f.talepId}'::uuid,'${f.kalemId2}'::uuid,'${siparisNo}','${f.urunKodu}',
            1,'KG',1,'KG','es');`;
  const [i1, i2] = await Promise.all([
    O.paralel({ rol: 'postgres' },
      bagSql(f.siparisNo, 1) + `\nselect pg_sleep(1);\n` + kalem2Sql(f.siparisNo)),
    O.paralel({ rol: 'postgres' },
      kalem2Sql(f.siparisNo2) + `\nselect pg_sleep(1);\n` + bagSql(f.siparisNo2, 1)),
  ]);
  // E2 — GERCEK garanti: ters sirada kilit alan iki HAM insert PostgreSQL
  // tarafindan kilitlenme olarak saptanir; bir oturum dusurulur, digeri
  // tamamlanir ve INV HICBIR durumda bozulmaz.
  //
  // Olculdu: planin "deadlock yok" iddiasi HAM insert'ler icin YANLIS. Sabit
  // kilit sirasi (`order by id`) RPC'nin ICINDEDIR; dogrudan insert yapan bir
  // cagirici kilit sirasini kendi belirler. Garanti "deadlock olmaz" degil,
  // "deadlock saptanir ve veri bozulmaz"dir. RPC'nin sirali kilitlemesi
  // Task 5'te sinanir.
  const kilitlenmeVar = /deadlock/i.test(i1.err + i2.err);
  sonuc(i1.ok || i2.ok,
    'E2a ters sirada kosumda en az bir oturum TAMAMLANDI',
    'i1=' + i1.ok + ' i2=' + i2.ok + (kilitlenmeVar ? ' (kilitlenme saptandi)' : ''));
  sonuc(Number(tek(`select coalesce(sum(b.miktar),0) from public.talep_siparis_baglari b
           join public.siparisler s on s.siparis_no = b.siparis_no
          where b.talep_kalem_id='${f.kalemId}'::uuid and s.durum <> 'iptal';`)) <= 10,
    'E2b INV bozulmadi — kalem1 (10 KOL) asilmadi');
  sonuc(Number(tek(`select coalesce(sum(b.miktar),0) from public.talep_siparis_baglari b
           join public.siparisler s on s.siparis_no = b.siparis_no
          where b.talep_kalem_id='${f.kalemId2}'::uuid and s.durum <> 'iptal';`)) <= 100,
    'E2c INV bozulmadi — kalem2 (100 KG) asilmadi');

  // M1 MUTANT: kalem kilidi kalkarsa eszamanli asim GECIYOR
  O.sql('delete from public.talep_siparis_baglari;');
  const asil4 = readFileSync(KOK + M4, 'utf8');
  const mutant4 = asil4.split('\n   for update;').join(';');
  if (mutant4 === asil4) throw new Error('M1 capasi tutmadi');
  O.uygulaTekIslem(mutant4, { metin: true });
  const [mr1, mr2] = await esKosum();
  const mToplam = Number(tek(`select coalesce(sum(b.miktar),0) from public.talep_siparis_baglari b
           join public.siparisler s on s.siparis_no = b.siparis_no
          where b.talep_kalem_id='${f.kalemId}'::uuid and s.durum <> 'iptal';`));
  sonuc(mr1.ok && mr2.ok && mToplam > 10,
    'M1 MUTANT: kilit kalkinca asim geciyor (INV bozuldu)', 'toplam=' + mToplam);
  O.uygulaTekIslem(M4);

  // M2 MUTANT: UPDATE'te old.id cikarilmazsa GECERLI guncelleme yanlis reddedilir
  O.sql('delete from public.talep_siparis_baglari;');
  bagYaz(O, f, { kalemId: f.kalemId, siparisNo: f.siparisNo, miktar: 6 });
  const mutant4b = asil4.replace(
    'perform public.talep_bag_inv_kontrol(new.talep_kalem_id, new.miktar, old.id);',
    'perform public.talep_bag_inv_kontrol(new.talep_kalem_id, new.miktar, null);');
  if (mutant4b === asil4) throw new Error('M2 capasi tutmadi');
  O.uygulaTekIslem(mutant4b, { metin: true });
  const m2r = O.sql(`update public.talep_siparis_baglari set miktar = 7
                      where talep_kalem_id='${f.kalemId}'::uuid;`);
  sonuc(!m2r.ok && /miktar_asimi/.test(m2r.err),
    'M2 MUTANT: old.id cikarilmazsa gecerli guncelleme reddediliyor', hata(m2r));
  O.uygulaTekIslem(M4);
  sonuc(O.sql(`update public.talep_siparis_baglari set miktar = 7
                where talep_kalem_id='${f.kalemId}'::uuid;`).ok,
    'M2b orijinalde ayni guncelleme KABUL');

  console.log(`\nSONUC: ${ok} gecti, ${fail} kaldi`);
} catch (e) { console.error('DUR: ' + (e && e.message)); fail++; }
finally { try { O.temizle(); } catch { /* yoksay */ } }
process.exit(fail === 0 ? 0 : 1);
