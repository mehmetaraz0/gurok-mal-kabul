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

  console.log(`\nSONUC: ${ok} gecti, ${fail} kaldi`);
} catch (e) { console.error('DUR: ' + (e && e.message)); fail++; }
finally { try { O.temizle(); } catch { /* yoksay */ } }
process.exit(fail === 0 ? 0 : 1);
