// ===========================================================================
// PMS ON BURO MODUL/YETKI TOHUMLAMASI — IZOLE DOGRULAMA
// ===========================================================================
// Olculenler (hepsi izole Docker veritabaninda, YAPAY veriyle):
//   T1 K1 kararsiz kosum: hicbir satir yazilmadan DURUR
//   T2 temiz kurulum: 5 modul + 15 yetki satiri olusur, dogru seviyelerle
//   T3 MEVCUT yetkiler korunur (onceden var olan satir degismez)
//   T4 ikinci kosum: 0 satir eklenir, hicbir satir degismez (idempotent)
//   T5 geri alma: yalniz bu uygulamanin ekledigi satirlar kalkar
//   T6 SONRADAN DEGISTIRILMIS yetki geri almada KORUNUR
//   T7 CELISKI (zaman ayni, seviye farkli): hicbir satir silinmez, hata verir
//   T8 EKSIK rol/modul sessizce gecilmez: hata, hicbir satir yazilmaz
//   T9 CELISEN MEVCUT yetki sessizce gecilmez: hata, hicbir satir yazilmaz
//   T10 K1 iki secenegi de calisir (kayit / yok), satir sayisi 15 kalir
//
// Uretime BAGLANMAZ, gercek veri yok, rol erisimi UYGULANMAZ (yalniz izole db).
// Kullanim: node scripts/pms-modul-tohum.test.mjs
// ===========================================================================
import fs from 'node:fs';
import { spawn } from 'node:child_process';
import { barOrtami } from './bar-test-ortam.mjs';

const KOK = new URL('..', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const KUR = KOK + 'docs/kurulum/2026-10-05-pms-onburo-modul-tohumlama.sql';
const GERI = KOK + 'docs/kurulum/2026-10-05-pms-onburo-modul-tohumlama-geri-al.sql';
const O = barOrtami({ ad: 'pms-tohum', ag: 'pms-tohum-net' });

let ok = 0, fail = 0;
const sonuc = (g, ad, ek) => {
  console.log((g ? 'OK   ' : 'FAIL ') + ad + (ek ? ' — ' + ek : ''));
  if (g) ok++; else fail++;
};
const es = (ad, bek, olc) => sonuc(String(bek) === String(olc), ad,
  String(bek) === String(olc) ? String(olc) : `beklenen=${bek} olculen=${olc}`);

const MODULLER = ['pms_oda_tipi', 'pms_oda', 'pms_misafir', 'pms_rezervasyon', 'pms_folio'];
const ROLLER = ['onburo_sef', 'onburo_vardiya', 'onburo_personel'];

const tek = (q) => O.sql(q).out.trim();
const kosDosya = (yol, onsoz = '') => O.sql(onsoz + '\n' + fs.readFileSync(yol, 'utf8'));
// K1/uygulama kimligi "set local" ile verilir; dosyanin kendi begin'i icinde
// gecerli olmasi icin ayni oturumda ONCE set edilir (psql tek oturum calistirir).
const kurKos = (k1) => kosDosya(KUR, k1 ? `set app.pms_k1 = '${k1}';` : '');
const geriKos = (id) => kosDosya(GERI, id ? `set app.pms_uygulama_id = '${id}';` : '');

const pmsSayim = () => tek(`select count(*) from public.yetki_matrisi ym
  join public.roller r on r.id=ym.rol_id join public.moduller m on m.id=ym.modul_id
  where m.kod = any(array['${MODULLER.join("','")}'])
    and r.kod = any(array['${ROLLER.join("','")}']);`);
const imzaliSayim = () => tek(`select count(*) from public.yetki_matrisi
  where guncelleyen like 'tohum:pms-onburo:%';`);
const uygulamaId = (cikti) => (cikti.match(/UYGULAMA KIMLIGI: ([0-9a-f-]{36})/) || [])[1];
const haritala = () => tek(`select string_agg(r.kod||'/'||m.kod||'='||ym.yetki::text, ' ' order by r.kod, m.kod)
  from public.yetki_matrisi ym
  join public.roller r on r.id=ym.rol_id join public.moduller m on m.id=ym.modul_id
  where m.kod = any(array['${MODULLER.join("','")}'])
    and r.kod = any(array['${ROLLER.join("','")}']);`);

// Yapay referans veri: uc On Buro rolu + ILGISIZ bir rol + onceden var olan
// bir yetki satiri (korunmasi olculecek).
// --- Inceleme bulgulari icin ek yardimcilar (PMS-S1..S4) ------------------
// Ham psql oturumu: paralel() rol sarmaladigi icin es zamanlilik testinde
// dogrudan docker exec kullanilir (ortam yardimcisi DEGISTIRILMEDI).
const hamPsql = (govde) => new Promise((coz) => {
  const p = spawn('docker', ['exec', '-i', O.konteyner, 'psql', '-X', '-U', 'postgres',
    '-d', 'bar', '-q', '-At', '-F', '|', '-v', 'ON_ERROR_STOP=1']);
  let out = '', err = '';
  p.stdout.on('data', (x) => { out += x; });
  p.stderr.on('data', (x) => { err += x; });
  p.on('close', (c) => coz({ ok: c === 0, out: out.trim(), err: err.trim() }));
  p.stdin.end(govde);
});
// PMS-S1: dosyanin KENDI belgelenen satirini yorumdan cikarip oldugu gibi kosar.
// Oturum duzeyinde "set" ile sessizce farkli bir yol KURMAZ.
const belgelenenKur = (k1) => {
  const metin = fs.readFileSync(KUR, 'utf8')
    .replace(new RegExp("^--(\\s*set local app\\.pms_k1 = '" + k1 + "';)", 'm'), '$1');
  if (!new RegExp("^\\s*set local app\\.pms_k1 = '" + k1 + "';", 'm').test(metin)) {
    throw new Error('belgelenen K1 satiri bulunamadi: ' + k1);
  }
  return O.sql(metin);
};
const belgelenenGeri = (id) => {
  const metin = fs.readFileSync(GERI, 'utf8')
    .replace(/^--(\s*set local app\.pms_uygulama_id = ')[^']*(';)/m, '$1' + id + '$2');
  if (!/^\s*set local app\.pms_uygulama_id = '[0-9a-f-]{36}';/m.test(metin)) {
    throw new Error('belgelenen kimlik satiri bulunamadi');
  }
  return O.sql(metin);
};
// Kapsamdaki yetki satirlarini bilinen bos duruma getirir (yalniz test icin).
const sifirla = () => O.sql(`delete from public.yetki_matrisi ym
  using public.roller r, public.moduller m
  where ym.rol_id=r.id and ym.modul_id=m.id
    and r.kod = any(array['${ROLLER.join("','")}'])
    and m.kod = any(array['${MODULLER.join("','")}']);
  delete from public.yetki_matrisi where guncelleyen like 'tohum:pms-onburo:%';`);

const YAPAY = `
set session_replication_role = replica;
insert into public.roller (id, ad, seviye, kod, sira) values
  ('00000000-0000-0000-0000-0000000000f1', 'On Buro Sefi',     'otel', 'onburo_sef', 20),
  ('00000000-0000-0000-0000-0000000000f2', 'On Buro Vardiya',  'otel', 'onburo_vardiya', 21),
  ('00000000-0000-0000-0000-0000000000f3', 'On Buro Personel', 'otel', 'onburo_personel', 22),
  ('00000000-0000-0000-0000-0000000000f9', 'Ilgisiz Rol',      'otel', 'ilgisiz_rol', 97)
on conflict do nothing;
-- ONCEDEN VAR OLAN yetki: ilgisiz rol, mevcut bir modulde. Tohumlama bunu
-- degistirmemeli (T3).
insert into public.yetki_matrisi (rol_id, modul_id, yetki, guncelleyen)
select '00000000-0000-0000-0000-0000000000f9', m.id, 'goruntule', 'onceden-var-olan'
from public.moduller m where m.kod = 'stok_takip'
on conflict do nothing;
set session_replication_role = origin;
`;

try {
  console.log('izole veritabani kuruluyor (Docker)...');
  await O.kur();
  const y = O.sql(YAPAY);
  if (!y.ok) throw new Error('yapay referans veri: ' + y.err.slice(-300));
  sonuc(true, 'T0 izole ortam + yapay referans veri hazir',
    tek('select count(*) from public.roller;') + ' rol');

  // --- YAYIN BAGIMLILIGI (2026-10-06 onayli tasarim) ----------------------
  // K1='kayit', mali ayrim kuralini ON KOSUL sayar. Once kuralin YOKLUGUNDA
  // reddedildigini olc, sonra kurali kur: boylece kalan testler gercek yayin
  // sirasiyla kosar.
  let rb = kurKos('kayit');
  sonuc(!rb.ok && /MALI_AYRIM_KURALI_YOK/.test(rb.err),
    'T0a mali ayrim kurali YOKKEN K1=kayit REDDEDILIYOR',
    rb.ok ? 'KOSTU (kusur)' : (rb.err.match(/MALI_AYRIM_KURALI_YOK[^\n]*/) || ['?'])[0].slice(0, 60));
  es('T0b bagimlilik reddinde hicbir yetki satiri yazilmadi', 0, pmsSayim());
  // MY-1: K1 YALNIZ personelin folyo hakkini seciyor; onburo_vardiya HER IKI
  // secenekte de pms_folio=kayit aliyor. Bu yuzden B secenegi de mali ayrim
  // kuralini gerektirir. Eski beklenti ("B kosmali") YANLISTI ve duzeltildi.
  rb = kurKos('yok');
  sonuc(!rb.ok && /MALI_AYRIM_KURALI_YOK/.test(rb.err),
    "T0c K1='yok' da kural YOKKEN REDDEDILIYOR (vardiya yine kayit aliyor)",
    rb.ok ? 'KOSTU (kusur)' : (rb.err.match(/MALI_AYRIM_KURALI_YOK[^\n]*/) || ['?'])[0].slice(0, 56));
  es('T0c2 B seceneginin reddinde de hicbir yetki satiri yazilmadi', 0, pmsSayim());
  O.sql(`delete from public.yetki_matrisi where guncelleyen like 'tohum:pms-onburo:%';`);
  const maliR = O.sql(fs.readFileSync(
    KOK + 'docs/kurulum/2026-10-06-pms-folio-mali-yetki-ayrimi.sql', 'utf8'));
  sonuc(maliR.ok, 'T0d mali ayrim kurali kuruldu (yayin sirasi)',
    maliR.ok ? '' : maliR.err.slice(-200));
  // Kural kurulduktan sonra HER IKI secenek de kosmali (olumlu kontroller).
  for (const secim of ['kayit', 'yok']) {
    O.sql(`delete from public.yetki_matrisi where guncelleyen like 'tohum:pms-onburo:%';`);
    const rr = kurKos(secim);
    sonuc(rr.ok, `T0e kural kuruluyken K1='${secim}' KOSUYOR (olumlu kontrol)`,
      rr.ok ? '' : rr.err.slice(-120));
    es(`T0e2 K1='${secim}' 15 satir yazdi`, 15, pmsSayim());
  }
  O.sql(`delete from public.yetki_matrisi where guncelleyen like 'tohum:pms-onburo:%';`);

  const oncekiIlgisiz = tek(`select yetki::text||'|'||guncelleyen from public.yetki_matrisi
    where guncelleyen = 'onceden-var-olan';`);

  // --- T1: K1 kararsiz -> DURUR -----------------------------------------
  // NOT: T0c (K1=yok) bagimlilik testi modul satirlarini zaten olusturdu.
  // Bu yuzden olcut MUTLAK sayi degil FARK: kararsiz kosum hicbir modul
  // satiri EKLEMEMELI.
  const modulSay = () => tek(`select count(*) from public.moduller
    where kod = any(array['${MODULLER.join("','")}']);`);
  const modulOnce = modulSay();
  let r = kurKos(null);
  sonuc(!r.ok && /K1 KARARI VERILMEDI/.test(r.err), 'T1 K1 kararsizken DURUYOR',
    (r.err.match(/K1 KARARI VERILMEDI[^\n]*/) || ['hata metni yok'])[0].slice(0, 60));
  es('T1b K1 kararsizken hicbir yetki satiri yazilmadi', 0, pmsSayim());
  es('T1c K1 kararsizken modul satiri EKLENMEDI (fark=0)', modulOnce, modulSay());

  // --- T8: EKSIK rol -> hata, hicbir satir yazilmaz ----------------------
  O.sql(`set session_replication_role=replica;
         delete from public.roller where kod='onburo_personel';
         set session_replication_role=origin;`);
  r = kurKos('kayit');
  sonuc(!r.ok && /EKSIK REFERANS/.test(r.err) && /onburo_personel/.test(r.err),
    'T8 EKSIK rol sessizce gecilmiyor',
    (r.err.match(/EKSIK REFERANS[^\n]*/) || ['hata metni yok'])[0].slice(0, 70));
  es('T8b eksik referansta hicbir yetki satiri yazilmadi', 0, pmsSayim());
  O.sql(`set session_replication_role=replica;
         insert into public.roller (id,ad,seviye,kod,sira) values
          ('00000000-0000-0000-0000-0000000000f3','On Buro Personel','otel','onburo_personel',22);
         set session_replication_role=origin;`);

  // --- T2: temiz kurulum -------------------------------------------------
  r = kurKos('kayit');
  sonuc(r.ok, 'T2 temiz kurulum kostu', r.ok ? '' : r.err.slice(-200));
  const id1 = uygulamaId(r.out + r.err);
  es('T2b bes modul satiri olustu', 5,
    tek(`select count(*) from public.moduller where kod = any(array['${MODULLER.join("','")}']);`));
  es('T2c onbes yetki satiri olustu', 15, pmsSayim());
  sonuc(!!id1, 'T2d uygulama kimligi raporlandi', String(id1));
  const beklenenHarita = [
    'onburo_personel/pms_folio=kayit', 'onburo_personel/pms_misafir=kayit',
    'onburo_personel/pms_oda=goruntule', 'onburo_personel/pms_oda_tipi=goruntule',
    'onburo_personel/pms_rezervasyon=kayit',
    'onburo_sef/pms_folio=tam', 'onburo_sef/pms_misafir=tam', 'onburo_sef/pms_oda=tam',
    'onburo_sef/pms_oda_tipi=tam', 'onburo_sef/pms_rezervasyon=tam',
    'onburo_vardiya/pms_folio=kayit', 'onburo_vardiya/pms_misafir=kayit',
    'onburo_vardiya/pms_oda=kayit', 'onburo_vardiya/pms_oda_tipi=goruntule',
    'onburo_vardiya/pms_rezervasyon=kayit',
  ].join(' ');
  es('T2e seviyeler karar tablosuyla birebir', beklenenHarita, haritala());

  // --- T3: MEVCUT yetkiler korunur ---------------------------------------
  es('T3 onceden var olan yetki satiri DEGISMEDI', oncekiIlgisiz,
    tek(`select yetki::text||'|'||guncelleyen from public.yetki_matrisi
         where guncelleyen = 'onceden-var-olan';`));

  // --- T4: ikinci kosum -> 0 ekleme, degisiklik yok ----------------------
  const oncekiTam = tek(`select md5(string_agg(id::text||yetki::text||coalesce(guncelleyen,'')||guncelleme_tarihi::text, ',' order by id))
    from public.yetki_matrisi;`);
  r = kurKos('kayit');
  sonuc(r.ok && /eklenen_yetki_satiri=0\/15/.test(r.out + r.err),
    'T4 ikinci kosum 0 satir ekledi',
    ((r.out + r.err).match(/eklenen_yetki_satiri=\d+\/15/) || ['?'])[0]);
  es('T4b ikinci kosum sonrasi toplam yetki tablosu BIREBIR ayni', oncekiTam,
    tek(`select md5(string_agg(id::text||yetki::text||coalesce(guncelleyen,'')||guncelleme_tarihi::text, ',' order by id))
         from public.yetki_matrisi;`));
  es('T4c yetki satiri sayisi 15 kaldi', 15, pmsSayim());

  // --- T6: sonradan degistirilmis yetki geri almada KORUNUR -------------
  // UI'nin yaptigi gibi: yetki ve guncelleme_tarihi degisir, guncelleyen AYNI kalir.
  O.sql(`update public.yetki_matrisi ym set yetki='goruntule', guncelleme_tarihi=now()
         from public.roller r, public.moduller m
         where ym.rol_id=r.id and ym.modul_id=m.id
           and r.kod='onburo_vardiya' and m.kod='pms_folio';`);
  r = geriKos(id1);
  sonuc(r.ok, 'T5 geri alma kostu', r.ok ? '' : r.err.slice(-200));
  sonuc(/SONRADAN DEGISTIRILMIS, KORUNDU/.test(r.out + r.err) && /pms_folio/.test(r.out + r.err),
    'T6 sonradan degistirilmis yetki KORUNDU ve raporlandi',
    ((r.out + r.err).match(/SONRADAN DEGISTIRILMIS[^\n]*/) || ['?'])[0].slice(0, 80));
  es('T5b geri alma sonrasi yalniz korunan satir kaldi', 1, pmsSayim());
  es('T5c korunan satirin seviyesi elle verilen deger', 'goruntule',
    tek(`select ym.yetki::text from public.yetki_matrisi ym
         join public.roller r on r.id=ym.rol_id join public.moduller m on m.id=ym.modul_id
         where r.kod='onburo_vardiya' and m.kod='pms_folio';`));
  es('T5d onceden var olan ILGISIZ yetki hala yerinde', oncekiIlgisiz,
    tek(`select yetki::text||'|'||guncelleyen from public.yetki_matrisi
         where guncelleyen = 'onceden-var-olan';`));
  es('T5e modul satirlari KALDIRILMADI', 5,
    tek(`select count(*) from public.moduller where kod = any(array['${MODULLER.join("','")}']);`));

  // Korunan satiri temizleyip T9/T7 icin zemini hazirla.
  O.sql(`delete from public.yetki_matrisi ym using public.roller r, public.moduller m
         where ym.rol_id=r.id and ym.modul_id=m.id
           and r.kod='onburo_vardiya' and m.kod='pms_folio';`);

  // --- T9: CELISEN MEVCUT yetki sessizce gecilmez -----------------------
  O.sql(`insert into public.yetki_matrisi (rol_id, modul_id, yetki, guncelleyen)
         select r.id, m.id, 'goruntule', 'baskasinin-karari'
         from public.roller r, public.moduller m
         where r.kod='onburo_sef' and m.kod='pms_oda';`);
  r = kurKos('kayit');
  sonuc(!r.ok && /CELISEN MEVCUT YETKI/.test(r.err) && /onburo_sef\/pms_oda/.test(r.err),
    'T9 celisen MEVCUT yetki sessizce gecilmiyor',
    (r.err.match(/onburo_sef\/pms_oda[^,]*/) || ['hata metni yok'])[0].slice(0, 60));
  es('T9b celiskide hicbir yeni satir yazilmadi (yalniz catisan satir var)', 1, pmsSayim());
  es('T9c baskasinin karari DEGISMEDI', 'goruntule|baskasinin-karari',
    tek(`select ym.yetki::text||'|'||ym.guncelleyen from public.yetki_matrisi ym
         join public.roller r on r.id=ym.rol_id join public.moduller m on m.id=ym.modul_id
         where r.kod='onburo_sef' and m.kod='pms_oda';`));
  O.sql(`delete from public.yetki_matrisi where guncelleyen='baskasinin-karari';`);

  // --- T10: K1='yok' secenegi -------------------------------------------
  r = kurKos('yok');
  const id2 = uygulamaId(r.out + r.err);
  sonuc(r.ok, 'T10 K1=yok secenegi kostu', r.ok ? '' : r.err.slice(-200));
  es('T10b satir sayisi yine 15', 15, pmsSayim());
  es('T10c personel folyo seviyesi yok', 'yok',
    tek(`select ym.yetki::text from public.yetki_matrisi ym
         join public.roller r on r.id=ym.rol_id join public.moduller m on m.id=ym.modul_id
         where r.kod='onburo_personel' and m.kod='pms_folio';`));

  // --- T7: CELISKI (zaman ayni, seviye farkli) -> hicbir sey silinmez ----
  // Damgayi bozmadan YALNIZ seviyeyi degistir (guncelleme_tarihi AYNI kalsin).
  O.sql(`update public.yetki_matrisi ym set yetki='tam'
         from public.roller r, public.moduller m
         where ym.rol_id=r.id and ym.modul_id=m.id
           and r.kod='onburo_personel' and m.kod='pms_oda';`);
  const oncekiSayim = pmsSayim();
  r = geriKos(id2);
  sonuc(!r.ok && /CELISKI/.test(r.err) && /onburo_personel\/pms_oda/.test(r.err),
    'T7 celiskide geri alma DURUYOR',
    (r.err.match(/onburo_personel\/pms_oda[^,]*/) || ['hata metni yok'])[0].slice(0, 60));
  es('T7b celiskide HICBIR satir silinmedi', oncekiSayim, pmsSayim());

  // --- Geri alma: bilinmeyen kimlik ve kimliksiz kosum -------------------
  r = geriKos(null);
  sonuc(!r.ok && /UYGULAMA KIMLIGI VERILMEDI/.test(r.err),
    'T11 kimliksiz geri alma DURUYOR');
  r = geriKos('11111111-1111-1111-1111-111111111111');
  sonuc(r.ok && /imzali satir YOK/.test(r.out + r.err),
    'T12 bilinmeyen kimlikte hicbir sey silinmiyor');
  es('T12b satir sayisi degismedi', oncekiSayim, pmsSayim());

  // ======================================================================
  // INCELEME BULGULARI — kalici regresyon (PMS-S1..S4)
  // ======================================================================
  console.log('\n--- PMS-S1..S4 karsi ornekleri ---');

  // --- PMS-S1: dosyanin BELGELENEN satiri, dis islem olmadan calismali ----
  sifirla();
  let r1 = belgelenenKur('kayit');
  sonuc(r1.ok && !/SET LOCAL can only be used in transaction blocks/.test(r1.err),
    'S1 belgelenen K1 satiri dis islem OLMADAN calisiyor',
    /SET LOCAL can only be used/.test(r1.err) ? 'SET LOCAL uyarisi VAR' : (r1.ok ? '' : r1.err.slice(-120)));
  es('S1b belgelenen yolla 15 satir yazildi', 15, pmsSayim());
  const s1id = uygulamaId(r1.out + r1.err);
  sonuc(!!s1id, 'S1c belgelenen yolda uygulama kimligi raporlandi', String(s1id));
  let rg = s1id ? belgelenenGeri(s1id) : { ok: false, out: '', err: 'kimlik yok' };
  sonuc(rg.ok && !/SET LOCAL can only be used in transaction blocks/.test(rg.err),
    'S1d belgelenen kimlik satiri dis islem OLMADAN calisiyor',
    /SET LOCAL can only be used/.test(rg.err) ? 'SET LOCAL uyarisi VAR' : (rg.ok ? '' : rg.err.slice(-120)));
  es('S1e belgelenen yolla geri alma 15 satiri kaldirdi', 0, pmsSayim());

  // --- PMS-S2: gecersiz/joker kimlik silme kapsamini GENISLETMEMELI -------
  sifirla();
  r1 = belgelenenKur('kayit');
  const s2id = uygulamaId(r1.out + r1.err);
  // Ikinci uygulama fiksturu: kapsam DISI bir cifte baska bir uygulama damgasi.
  const s2digerId = '22222222-2222-2222-2222-222222222222';
  O.sql(`insert into public.yetki_matrisi (rol_id, modul_id, yetki, guncelleyen, guncelleme_tarihi)
    select r.id, m.id, 'goruntule',
      'tohum:pms-onburo:${s2digerId}@' || to_char(now(),'YYYY-MM-DD"T"HH24:MI:SS.USOF') || '#goruntule',
      now()
    from public.roller r, public.moduller m
    where r.kod='ilgisiz_rol' and m.kod='stok_takip'
    on conflict (rol_id, modul_id) do update set guncelleyen = excluded.guncelleyen,
      yetki = excluded.yetki, guncelleme_tarihi = excluded.guncelleme_tarihi;`);
  const imzaliOnce = imzaliSayim();
  for (const kotu of ['%', '_', 'bozuk-uuid', "' or 1=1 --"]) {
    const rr = geriKos(kotu);
    sonuc(!rr.ok, 'S2 gecersiz kimlik "' + kotu + '" geri almayi DURDURUYOR',
      rr.ok ? 'KOSTU (kusur)' : (rr.err.match(/(gecersiz|invalid|UYGULAMA KIMLIGI)[^\n]*/i) || ['hata'])[0].slice(0, 55));
    es('S2b "' + kotu + '" sonrasi imzali satir sayisi degismedi', imzaliOnce, imzaliSayim());
  }
  // Iki uygulama: birini geri almak digerini KORUMALI.
  rg = geriKos(s2id);
  sonuc(rg.ok, 'S2c birinci uygulama geri alindi', rg.ok ? '' : rg.err.slice(-120));
  es('S2d IKINCI uygulamanin satiri KORUNDU', 1,
    tek(`select count(*) from public.yetki_matrisi
         where guncelleyen like 'tohum:pms-onburo:${s2digerId}@%';`));
  O.sql(`delete from public.yetki_matrisi where guncelleyen like 'tohum:pms-onburo:${s2digerId}@%';`);

  // --- PMS-S3: ES ZAMANLI duzenleme geri almada SILINMEMELI --------------
  sifirla();
  r1 = belgelenenKur('kayit');
  const s3id = uygulamaId(r1.out + r1.err);
  es('S3-hazirlik 15 satir', 15, pmsSayim());
  // Arka plan oturumu: bir satiri degistirip kilidi 4 sn tutar, sonra commit.
  const arkaPlan = hamPsql(`begin;
    update public.yetki_matrisi ym set yetki='goruntule', guncelleme_tarihi=now()
      from public.roller r, public.moduller m
     where ym.rol_id=r.id and ym.modul_id=m.id
       and r.kod='onburo_sef' and m.kod='pms_misafir';
    select pg_sleep(4);
    commit;`);
  await new Promise((c) => setTimeout(c, 1200));   // guncelleme yapildi, kilit duruyor
  rg = geriKos(s3id);
  const ap = await arkaPlan;
  sonuc(ap.ok, 'S3-arkaplan oturumu commit etti', ap.ok ? '' : ap.err.slice(-120));
  sonuc(rg.ok, 'S3 geri alma kostu', rg.ok ? '' : rg.err.slice(-150));
  es('S3b ES ZAMANLI degistirilen satir KORUNDU', 1,
    tek(`select count(*) from public.yetki_matrisi ym
         join public.roller r on r.id=ym.rol_id join public.moduller m on m.id=ym.modul_id
         where r.kod='onburo_sef' and m.kod='pms_misafir';`));
  es('S3c korunan satirin seviyesi es zamanli verilen deger', 'goruntule',
    tek(`select ym.yetki::text from public.yetki_matrisi ym
         join public.roller r on r.id=ym.rol_id join public.moduller m on m.id=ym.modul_id
         where r.kod='onburo_sef' and m.kod='pms_misafir';`));
  sonuc(/silinen=14/.test(rg.out + rg.err) && /korunan=1/.test(rg.out + rg.err),
    'S3d rapor GERCEK silinen/korunan sayilarini gosteriyor',
    ((rg.out + rg.err).match(/GERI ALMA: [^\n]*/) || ['rapor yok'])[0].slice(0, 70));
  es('S3e kapsamda yalniz korunan satir kaldi', 1, pmsSayim());

  // --- PMS-S4: PASIF mevcut modulle kurulum BASARILI DEMEMELI -----------
  sifirla();
  O.sql(`delete from public.yetki_matrisi where guncelleyen like 'tohum:pms-onburo:%';
         update public.moduller set aktif=false where kod='pms_oda';`);
  r1 = belgelenenKur('kayit');
  sonuc(!r1.ok && /PASIF MODUL|pasif/i.test(r1.err),
    'S4 pasif hedef modulde kurulum DURUYOR',
    r1.ok ? 'KOSTU (kusur)' : (r1.err.match(/(PASIF MODUL|pasif)[^\n]*/i) || ['hata metni yok'])[0].slice(0, 70));
  es('S4b pasif modulde hicbir yetki satiri yazilmadi', 0, pmsSayim());
  es('S4c baskasinin PASIFE ALMA karari KORUNDU', 'false',
    tek("select aktif::text from public.moduller where kod='pms_oda';"));
  O.sql("update public.moduller set aktif=true where kod='pms_oda';");
  r1 = belgelenenKur('kayit');
  sonuc(r1.ok, 'S4d POZITIF kontrol: modul aktifken kurulum kosuyor', r1.ok ? '' : r1.err.slice(-120));
  es('S4e aktif modulde 15 satir yazildi', 15, pmsSayim());

  console.log('\n======================================================================');
  console.log(`SONUC: ${ok} gecti, ${fail} kaldi`);
  console.log('Izole kanit; rol erisimi UYGULANMADI, canli kabul yerine GECMEZ.');
  console.log('======================================================================');
} catch (e) {
  console.error('\nDUR: ' + (e && e.message));
  fail++;
} finally {
  try { O.temizle(); } catch {}
}
process.exit(fail === 0 ? 0 : 1);
