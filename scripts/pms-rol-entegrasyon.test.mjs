// ===========================================================================
// MY-4 — ON BURO ROLLERIYLE REZERVASYON / CHECK-IN / CHECK-OUT
// ===========================================================================
// Kapsam belgesi: docs/inceleme/PMS-MY4-ROL-ENTEGRASYON-KAPSAMI.md
// Inceleme sartlari: 2026-10-06-4ca95db-PMS-regresyon-ve-MY4-inceleme.md
//   MY4-T2: kilit hedefi NEW'den gelir (INSERT ve oda tipi degisen UPDATE)
//   MY4-T3: dogrudan cagri ya guvenle reddedilir ya tam gecisi ATOMIK tamamlar
//
// Bu dosya ONCE duzeltmesiz tabanda KIRMIZI olcer (gercek personel/vardiya
// rolleriyle zincirin kirildigini gosterir), SONRA duzeltme migration'ini
// uygular ve ayni zinciri YESIL olcer. Olumsuz kontroller her iki rol icin
// AYRI tutulur: onayli matris vardiyaya pms_oda=kayit, personele goruntule
// verir; bu paket bunlari DEGISTIRMEZ.
//
// Izole Docker + sentetik veri. Canli yetki degisikligi YOK.
// Kullanim: node scripts/pms-rol-entegrasyon.test.mjs
// ===========================================================================
import fs from 'node:fs';
import { barOrtami } from './bar-test-ortam.mjs';
import { EK_TOHUM } from './bar-a1-tohum.mjs';
import { PMS, PMS_TOHUM } from './pms-akis-tohum.mjs';

const KOK = new URL('..', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const MALI = KOK + 'docs/kurulum/2026-10-06-pms-folio-mali-yetki-ayrimi.sql';
const DUZELTME = KOK + 'docs/kurulum/2026-10-06-pms-rol-entegrasyon-kilit.sql';
const O = barOrtami({ ad: 'pms-rol', ag: 'pms-rol-net' });

let ok = 0, fail = 0;
const sonuc = (g, ad, ek) => {
  console.log((g ? 'OK   ' : 'FAIL ') + ad + (ek ? ' — ' + ek : ''));
  if (g) ok++; else fail++;
};
const es = (ad, bek, olc) => sonuc(String(bek) === String(olc), ad,
  String(bek) === String(olc) ? String(olc) : `beklenen=${bek} olculen=${olc}`);
const tek = (q) => O.sql(q).out.trim();

const U = {
  sef:      '11111111-0000-0000-0000-0000000000f1',
  vardiya:  '11111111-0000-0000-0000-0000000000f2',
  personel: '11111111-0000-0000-0000-0000000000f3',
  digerOtel:'11111111-0000-0000-0000-0000000000f4',
  yetkisiz: '11111111-0000-0000-0000-0000000000f5',
};
const olarak = (kim, q) => O.kimlikle({ rol: 'authenticated', sub: U[kim] }, q);

// Onayli 15 satirlik matris + yetkisiz bir rol (olumsuz kontrol icin).
const TOHUM = `
set session_replication_role = replica;
insert into public.moduller (kod, ad, kategori, sira, aktif) values
  ('pms_oda_tipi','On Buro — Oda Tipleri','onburo',43,true),
  ('pms_oda','On Buro — Odalar','onburo',44,true),
  ('pms_misafir','On Buro — Misafirler','onburo',45,true),
  ('pms_rezervasyon','On Buro — Rezervasyonlar','onburo',47,true),
  ('pms_folio','On Buro — Folio','onburo',48,true)
on conflict (kod) do nothing;
insert into public.roller (id, ad, seviye, kod, sira) values
  ('00000000-0000-0000-0000-0000000000f1','On Buro Sefi','otel','onburo_sef',20),
  ('00000000-0000-0000-0000-0000000000f2','On Buro Vardiya','otel','onburo_vardiya',21),
  ('00000000-0000-0000-0000-0000000000f3','On Buro Personel','otel','onburo_personel',22),
  ('00000000-0000-0000-0000-0000000000f5','Yetkisiz','otel','yetkisiz_rol',96)
on conflict do nothing;
insert into public.yetki_matrisi (rol_id, modul_id, yetki)
select r.id, m.id, v.y::public.yetki_seviye from (values
  ('onburo_sef','pms_oda_tipi','tam'),          ('onburo_sef','pms_oda','tam'),
  ('onburo_sef','pms_misafir','tam'),           ('onburo_sef','pms_rezervasyon','tam'),
  ('onburo_sef','pms_folio','tam'),
  ('onburo_vardiya','pms_oda_tipi','goruntule'),('onburo_vardiya','pms_oda','kayit'),
  ('onburo_vardiya','pms_misafir','kayit'),     ('onburo_vardiya','pms_rezervasyon','kayit'),
  ('onburo_vardiya','pms_folio','kayit'),
  ('onburo_personel','pms_oda_tipi','goruntule'),('onburo_personel','pms_oda','goruntule'),
  ('onburo_personel','pms_misafir','kayit'),    ('onburo_personel','pms_rezervasyon','kayit'),
  ('onburo_personel','pms_folio','kayit')
) v(r,m,y) join public.roller r on r.kod=v.r join public.moduller m on m.kod=v.m
on conflict (rol_id, modul_id) do nothing;
insert into auth.users (id, email) values
  ('${U.sef}','sef@t.local'), ('${U.vardiya}','vardiya@t.local'),
  ('${U.personel}','personel@t.local'), ('${U.digerOtel}','diger@t.local'),
  ('${U.yetkisiz}','yetkisiz@t.local')
on conflict do nothing;
insert into public.kullanicilar (id, auth_user_id, ad, rol, otel_id, aktif, rol_id) values
  (gen_random_uuid(),'${U.sef}','Sef','muhasebe_calisani','810',true,'00000000-0000-0000-0000-0000000000f1'),
  (gen_random_uuid(),'${U.vardiya}','Vardiya','muhasebe_calisani','810',true,'00000000-0000-0000-0000-0000000000f2'),
  (gen_random_uuid(),'${U.personel}','Personel','muhasebe_calisani','810',true,'00000000-0000-0000-0000-0000000000f3'),
  (gen_random_uuid(),'${U.digerOtel}','Diger 811','muhasebe_calisani','811',true,'00000000-0000-0000-0000-0000000000f3'),
  (gen_random_uuid(),'${U.yetkisiz}','Yetkisiz','muhasebe_calisani','810',true,'00000000-0000-0000-0000-0000000000f5')
on conflict do nothing;
set session_replication_role = origin;
`;

// Her senaryoda taze rezervasyon: ayni fikstur hem kirmizi hem yesil fazda.
let sayac = 0;
function rezervasyonKur() {
  sayac += 1;
  const id = `99999999-0000-0000-0000-0000000${String(900 + sayac).padStart(5, '0')}`;
  // Her senaryodan ONCE onceki sentetik rezervasyonlar iptal edilir: aksi
  // halde ayni oda tipi/tarihte envanter tukenir ve testler ASIRI SATIS
  // kontrolune takilir (olculdu). Kontrol GEVSETILMEZ, fikstur temizlenir.
  O.sql(`set session_replication_role = replica;
    update public.pms_rezervasyonlar set durum='iptal'
     where (rezervasyon_no like 'R-9%' or rezervasyon_no like 'RY-%'
            or rezervasyon_no like 'KAP-%')
       and durum in ('onaylandi','giris_yapildi');
    set session_replication_role = origin;`);
  O.sql(`set session_replication_role = replica;
    insert into public.pms_rezervasyonlar
      (id, otel_id, rezervasyon_no, misafir_id, oda_tipi_id, giris_tarihi,
       cikis_tarihi, durum, gecelik_fiyat)
    values ('${id}','810','R-${900 + sayac}','${PMS.MIS201}','${PMS.TIP}',
            current_date, current_date + 2, 'onaylandi', 1200)
    on conflict (id) do nothing;
    set session_replication_role = origin;`);
  return id;
}
// Senaryo oncesi ortami bilinen hale getirir: bekleyen sentetik rezervasyonlar
// iptal, test odalari bos/temiz. Hicbir URUN kontrolu gevsetilmez; yalnizca
// fikstur durumu temizlenir (envanter tukenmesi ve kirli oda yan etkileri).
const ortamSifirla = () => O.sql(`set session_replication_role = replica;
  -- Ayni oda tipindeki TUM bekleyen rezervasyonlar iptal edilir: tohumdaki
  -- T-xxx kayitlari da envanter tuttugu icin yalniz kendi kayitlarimizi
  -- iptal etmek yetmiyordu (olculdu: "secilen tarihlerde N rezervasyon dolu").
  update public.pms_rezervasyonlar set durum='iptal'
   where oda_tipi_id = '${PMS.TIP}'
     and durum in ('onaylandi','giris_yapildi');
  update public.pms_oda_atamalari set aktif=false
   where oda_id in ('${PMS.ODA201}','${PMS.ODA202}','${PMS.ODA203}');
  -- Faz 2 tutarlilik kurali: oda temizlik durumu gorev motorunun izdusumudur.
  -- Kural GEVSETILMEZ; fikstur bekleyen gorevleri temizler ki oda durumu
  -- gorevle tutarli olsun (olculdu: "guncel gorev bekliyor").
  delete from public.pms_housekeeping_gorevleri
   where oda_id in ('${PMS.ODA201}','${PMS.ODA202}','${PMS.ODA203}');
  update public.pms_odalar set kullanim_durumu='bos', temizlik_durumu='temiz',
         temizlik_gorevi_id = null
   where id in ('${PMS.ODA201}','${PMS.ODA202}','${PMS.ODA203}');
  set session_replication_role = origin;`);

const odaDurum = (odaId) => tek(`select kullanim_durumu||'/'||temizlik_durumu
  from public.pms_odalar where id='${odaId}';`);
const rezDurum = (rezId) => tek(`select durum from public.pms_rezervasyonlar where id='${rezId}';`);
const atamaSayisi = (rezId) => tek(`select count(*) from public.pms_oda_atamalari
  where rezervasyon_id='${rezId}' and aktif;`);

// --- Zincir: rezervasyon yaz -> check-in -> check-out --------------------
const rezYaz = (kim) => olarak(kim, `insert into public.pms_rezervasyonlar
  (otel_id, rezervasyon_no, misafir_id, oda_tipi_id, giris_tarihi, cikis_tarihi,
   durum, gecelik_fiyat, yetiskin_sayisi)
  values ('810','RY-${kim}-${Date.now() % 100000}','${PMS.MIS201}','${PMS.TIP}',
          current_date, current_date + 1, 'onaylandi', 900, 1);`);
const girisYap = (kim, rezId, odaId) => olarak(kim,
  `select public.pms_check_in('${rezId}'${odaId ? `,'${odaId}'` : ''});`);
const cikisYap = (kim, rezId) => olarak(kim, `select public.pms_check_out('${rezId}');`);

try {
  console.log('izole veritabani kuruluyor (Docker)...');
  await O.kur();
  for (const [ad, s] of [['A1', EK_TOHUM], ['PMS', PMS_TOHUM], ['rol', TOHUM]]) {
    const r = O.sql(s); if (!r.ok) throw new Error(ad + ' tohum: ' + r.err.slice(-300));
  }
  const maliR = O.sql(fs.readFileSync(MALI, 'utf8'));
  sonuc(maliR.ok, 'R0 izole ortam + mali kural + onayli 15 satirlik matris',
    maliR.ok ? '' : maliR.err.slice(-200));

  // ======================================================================
  // KIRMIZI FAZ — duzeltme UYGULANMADAN, gercek rollerle zincir KIRIK
  // ======================================================================
  console.log('\n--- KIRMIZI FAZ: duzeltme yokken gercek personel/vardiya ---');
  const kirmizi = {};
  for (const kim of ['personel', 'vardiya']) {
    ortamSifirla();
    const r1 = rezYaz(kim);
    kirmizi[kim + '-rez'] = r1.ok;
    sonuc(!r1.ok && /Oda tipi bulunamadi/.test(r1.err),
      `K1 ${kim}: rezervasyon yazamiyor (oda tipi KILITLENEMIYOR)`,
      r1.ok ? 'YAZDI' : (r1.err.match(/Oda tipi bulunamadi[^\n]*/) || ['?'])[0].slice(0, 46));

    const rez = rezervasyonKur();
    const g = girisYap(kim, rez, PMS.ODA202);
    kirmizi[kim + '-giris'] = g.ok;
    sonuc(!g.ok, `K2 ${kim}: check-in YAPAMIYOR`,
      g.ok ? 'YAPTI' : (g.err.match(/(Oda tipi|Oda) bulunamadi[^\n]*/) || ['ret'])[0].slice(0, 46));
    es(`K2b ${kim}: basarisiz check-in sonrasi oda DEGISMEDI`, 'bos/temiz', odaDurum(PMS.ODA202));
    es(`K2c ${kim}: rezervasyon durumu DEGISMEDI`, 'onaylandi', rezDurum(rez));
  }
  // Sef ayni islemleri YAPABILIYOR (olumlu karsilastirma).
  ortamSifirla();
  const sefRez = rezervasyonKur();
  const sefG = girisYap('sef', sefRez, PMS.ODA203);
  sonuc(sefG.ok, 'K3 sef AYNI islemi yapabiliyor (engel yetkiye bagli)',
    sefG.ok ? '' : sefG.err.slice(-110));
  const sefC = cikisYap('sef', sefRez);
  sonuc(sefC.ok, 'K3b sef check-out yapabiliyor', sefC.ok ? '' : sefC.err.slice(-110));

  // ======================================================================
  // DUZELTME
  // ======================================================================
  console.log('\n--- DUZELTME uygulaniyor ---');
  const dR = O.sql(fs.readFileSync(DUZELTME, 'utf8'));
  sonuc(dR.ok, 'D0 rol entegrasyon migration kostu',
    dR.ok ? ((dR.err.match(/ENVANTER[^\n]*/) || [''])[0]).slice(0, 70) : dR.err.slice(-250));
  if (!dR.ok) throw new Error('duzeltme uygulanamadi');

  // ======================================================================
  // YESIL FAZ — ayni zincir, ayni roller
  // ======================================================================
  console.log('\n--- YESIL FAZ: zincir calisiyor ---');
  for (const kim of ['personel', 'vardiya']) {
    ortamSifirla();
    const r1 = rezYaz(kim);
    sonuc(r1.ok, `Y1 ${kim}: rezervasyon YAZABILIYOR`, r1.ok ? '' : r1.err.slice(-110));

    const rez = rezervasyonKur();
    const oda = kim === 'personel' ? PMS.ODA202 : PMS.ODA203;
    const g = girisYap(kim, rez, oda);
    sonuc(g.ok, `Y2 ${kim}: check-in YAPABILIYOR`, g.ok ? '' : g.err.slice(-130));
    es(`Y2b ${kim}: oda dolu/temiz`, 'dolu/temiz', odaDurum(oda));
    es(`Y2c ${kim}: rezervasyon giris_yapildi`, 'giris_yapildi', rezDurum(rez));
    es(`Y2d ${kim}: aktif atama olustu`, 1, atamaSayisi(rez));

    const c = cikisYap(kim, rez);
    sonuc(c.ok, `Y3 ${kim}: check-out YAPABILIYOR`, c.ok ? '' : c.err.slice(-130));
    es(`Y3b ${kim}: oda bos/kirli`, 'bos/kirli', odaDurum(oda));
    es(`Y3c ${kim}: rezervasyon cikis_yapildi`, 'cikis_yapildi', rezDurum(rez));
    // Oda tekrar satisa hazir olsun diye temizle (urun yolu disinda, kurulum).
    O.sql(`set session_replication_role=replica;
           update public.pms_odalar set temizlik_durumu='temiz' where id='${oda}';
           set session_replication_role=origin;`);
  }

  // ======================================================================
  // KORUNAN DAVRANISLAR (inceleme sarti 1-5)
  // ======================================================================
  console.log('\n--- Korunan davranislar ---');
  // 1) Atanmamis rezervasyon icin pms_check_in(rez, oda) yolu KORUNUR
  ortamSifirla();
  const rezA = rezervasyonKur();
  es('P1-oncesi aktif atama yok', 0, atamaSayisi(rezA));
  const gA = girisYap('personel', rezA, PMS.ODA202);
  sonuc(gA.ok && atamaSayisi(rezA) === '1',
    'P1 atanmamis rezervasyonda oda SECME yolu korunuyor (atama olusturuldu)',
    gA.ok ? 'atama=' + atamaSayisi(rezA) : gA.err.slice(-100));
  cikisYap('personel', rezA);
  O.sql(`set session_replication_role=replica;
         update public.pms_odalar set temizlik_durumu='kontrol_edildi' where id='${PMS.ODA202}';
         set session_replication_role=origin;`);
  // 2) Temizlik kabulu: temiz VEYA kontrol_edildi
  ortamSifirla();
  O.sql(`set session_replication_role=replica;
    update public.pms_odalar set temizlik_durumu='kontrol_edildi' where id='${PMS.ODA202}';
    set session_replication_role=origin;`);
  const rezB = rezervasyonKur();
  const gB = girisYap('personel', rezB, PMS.ODA202);
  sonuc(gB.ok, 'P2 temizlik kabulu kontrol_edildi icin de GECERLI (daraltilmadi)',
    gB.ok ? '' : gB.err.slice(-110));
  cikisYap('personel', rezB);
  O.sql(`set session_replication_role=replica;
         update public.pms_odalar set temizlik_durumu='kirli' where id='${PMS.ODA202}';
         set session_replication_role=origin;`);
  ortamSifirla();
  O.sql(`set session_replication_role=replica;
    update public.pms_odalar set temizlik_durumu='kirli' where id='${PMS.ODA202}';
    set session_replication_role=origin;`);
  const rezC = rezervasyonKur();
  const gC = girisYap('personel', rezC, PMS.ODA202);
  sonuc(!gC.ok, 'P2b KIRLI oda hala REDDEDILIYOR (kontrol gevsetilmedi)',
    gC.ok ? 'KABUL (kusur)' : 'ret');
  O.sql(`set session_replication_role=replica;
         update public.pms_odalar set temizlik_durumu='temiz' where id='${PMS.ODA202}';
         set session_replication_role=origin;`);
  // 3) Kapasite / asiri satis kontrolu KORUNUR (MY4-T2: NEW hedefi)
  const kap = olarak('personel', `insert into public.pms_rezervasyonlar
    (otel_id, rezervasyon_no, misafir_id, oda_tipi_id, giris_tarihi, cikis_tarihi,
     durum, gecelik_fiyat, yetiskin_sayisi, cocuk_sayisi)
    values ('810','KAP-${Date.now() % 100000}','${PMS.MIS201}','${PMS.TIP}',
            current_date, current_date + 1, 'onaylandi', 900, 90, 90);`);
  sonuc(!kap.ok && /kapasite|azami/i.test(kap.err),
    'P3 kapasite kontrolu KORUNDU (NEW hedefinden dogrulaniyor)',
    kap.ok ? 'KABUL (kusur)' : (kap.err.match(/Kisi sayisi[^\n]*/) || ['ret'])[0].slice(0, 50));
  // 4) Oda tipi DEGISEN update: YENI hedef dogrulanir (MY4-T2)
  // MY4-R1 duzeltmesi: onceki surumde gecersiz bir UUID kullaniliyordu ve
  // ::text::uuid donusumu, oda tipi kontrolune ULASMADAN hata veriyordu;
  // test yalniz !ok aradigi icin kontrol bozulsa bile yesil kalabilirdi.
  // Artik UC karsilastirma GERCEK hedeflerle yapilir ve her birinde
  // veritabanindaki oda tipi DEGERI ayrica olculur. Beklenmeyen hata
  // (uuid sozdizimi, yetki, altyapi) BASARI SAYILMAZ.
  const TIP_TEK = `44444444-0000-0000-0000-0000000008aa`;   // azami_kisi=1
  const TIP_YOK = `44444444-0000-0000-0000-0000000008ff`;   // gecerli UUID, YOK
  O.sql(`set session_replication_role = replica;
    insert into public.pms_oda_tipleri
      (id, otel_id, kod, ad, azami_kisi, azami_yetiskin, azami_cocuk, aktif)
    values ('${TIP_TEK}','810','TEK','Tek Kisilik',1,1,0,true)
    on conflict (id) do nothing;
    -- Bu tipten BIR oda da gerekir: aksi halde urunun ASIRI SATIS kontrolu
    -- "secilen tarihlerde 0 rezervasyon dolu" ile HAKLI olarak reddeder
    -- (olculdu). Kontrol GEVSETILMEZ; eksik olan fikstur tamamlanir.
    insert into public.pms_odalar
      (id, otel_id, oda_tipi_id, oda_no, kullanim_durumu, temizlik_durumu)
    values ('66666666-0000-0000-0000-0000000008aa','810','${TIP_TEK}','T01','bos','temiz')
    on conflict (id) do nothing;
    set session_replication_role = origin;`);
  es(`P4-hazirlik tek kisilik oda tipi + o tipten 1 oda var`, '1|810|1',
    tek(`select t.azami_kisi::text||'|'||t.otel_id::text||'|'||
              (select count(*) from public.pms_odalar o where o.oda_tipi_id=t.id)::text
         from public.pms_oda_tipleri t where t.id='${TIP_TEK}';`));

  // (a) GECERLI UUID fakat OLMAYAN yeni oda tipi -> "Oda tipi bulunamadi"
  const rezD = rezervasyonKur();
  const tipOnce = tek(`select oda_tipi_id::text from public.pms_rezervasyonlar
    where id='${rezD}';`);
  const updYok = olarak('personel', `update public.pms_rezervasyonlar
    set oda_tipi_id='${TIP_YOK}' where id='${rezD}';`);
  sonuc(!updYok.ok && /Oda tipi bulunamadi/.test(updYok.err),
    'P4a OLMAYAN yeni oda tipine UPDATE: beklenen ret sinifi',
    updYok.ok ? 'KABUL (kusur)'
      : (updYok.err.match(/Oda tipi bulunamadi[^\n]*/) || ['BEKLENMEYEN: ' + String(updYok.err).replace(/\s+/g, ' ').slice(0, 60)])[0].slice(0, 52));
  es(`P4a2 rezervasyonun oda tipi DEGISMEDI`, tipOnce,
    tek(`select oda_tipi_id::text from public.pms_rezervasyonlar where id='${rezD}';`));

  // (b) VAR OLAN yeni oda tipi (azami_kisi=1), 2 yetiskin -> KAPASITE reddi
  O.sql(`set session_replication_role = replica;
    update public.pms_rezervasyonlar set yetiskin_sayisi=2, cocuk_sayisi=0
     where id='${rezD}';
    set session_replication_role = origin;`);
  const updKap = olarak('personel', `update public.pms_rezervasyonlar
    set oda_tipi_id='${TIP_TEK}' where id='${rezD}';`);
  sonuc(!updKap.ok && /Kisi sayisi oda tipi kapasitesini asiyor/.test(updKap.err),
    'P4b YENI oda tipinin KAPASITESI asilinca ret (NEW hedefi dogrulandi)',
    updKap.ok ? 'KABUL (kusur)'
      : (updKap.err.match(/Kisi sayisi[^\n]*/) || ['BEKLENMEYEN: ' + String(updKap.err).replace(/\s+/g, ' ').slice(0, 60)])[0].slice(0, 52));
  es(`P4b2 kapasite reddinde oda tipi DEGISMEDI`, tipOnce,
    tek(`select oda_tipi_id::text from public.pms_rezervasyonlar where id='${rezD}';`));

  // (c) AYNI yeni oda tipi, 1 yetiskin -> OLUMLU kontrol; DB dogrulanir
  O.sql(`set session_replication_role = replica;
    update public.pms_rezervasyonlar set yetiskin_sayisi=1, cocuk_sayisi=0
     where id='${rezD}';
    set session_replication_role = origin;`);
  const updOk = olarak('personel', `update public.pms_rezervasyonlar
    set oda_tipi_id='${TIP_TEK}' where id='${rezD}';`);
  sonuc(updOk.ok, 'P4c OLUMLU: kapasiteye uyan YENI oda tipine UPDATE KABUL',
    updOk.ok ? '' : String(updOk.err).replace(/\s+/g, ' ').slice(-110));
  es(`P4c2 veritabanindaki oda tipi YENI hedefe dondu`, TIP_TEK,
    tek(`select oda_tipi_id::text from public.pms_rezervasyonlar where id='${rezD}';`));

  // ======================================================================
  // OLUMSUZ KONTROLLER
  // ======================================================================
  console.log('\n--- Olumsuz kontroller ---');
  // Baska otel
  ortamSifirla();
  const rezE = rezervasyonKur();
  const dg = girisYap('digerOtel', rezE, PMS.ODA202);
  sonuc(!dg.ok, 'N1 BASKA otelin personeli check-in YAPAMIYOR',
    dg.ok ? 'YAPTI (kusur)' : (dg.err.match(/erisim|bulunamadi|yetki/i) || ['ret'])[0]);
  es('N1b oda degismedi', 'bos/temiz', odaDurum(PMS.ODA202));
  // Yetkisiz rol
  const yz = girisYap('yetkisiz', rezE, PMS.ODA202);
  sonuc(!yz.ok && /yetki/i.test(yz.err), 'N2 pms_rezervasyon yetkisi olmayan rol REDDEDILDI',
    yz.ok ? 'YAPTI (kusur)' : (yz.err.match(/[^\n]*yetki[^\n]*/i) || ['ret'])[0].slice(0, 50));
  const cy = cikisYap('yetkisiz', rezE);
  sonuc(!cy.ok, 'N2b yetkisiz rol check-out da YAPAMIYOR', cy.ok ? 'YAPTI' : 'ret');
  // ROL BAZINDA AYRI: dogrudan oda guncellemesi
  // ROL FARKI: personelde RLS satiri SUZER (0 satir, sessiz), vardiyada
  // SUZMEZ (ya yazar ya da IS KURALI reddeder). Ikisi AYNI sey degildir;
  // olcum bu farki ayirir. Temizlik durumu Faz 2'de gorev motorunun
  // izdusumudur; dogrudan yazimi IS KURALI reddedebilir — bu yetki kaybi
  // DEGILDIR ve bu paket o kurali gevsetmez.
  ortamSifirla();
  const dene = (kim) => olarak(kim, `update public.pms_odalar
    set temizlik_durumu='kontrol_edildi' where id='${PMS.ODA203}' returning 1;`);
  const persOda = dene('personel');
  const persDeger = tek(`select temizlik_durumu from public.pms_odalar
    where id='${PMS.ODA203}';`);
  sonuc(persOda.ok && persOda.out.trim() === '' && persDeger !== 'kontrol_edildi',
    'N3 personel: RLS satiri SUZDU (0 satir), deger DEGISMEDI',
    'cikti=[' + persOda.out.trim() + '] deger=' + persDeger);
  // MY4-R2 duzeltmesi: onceki surumde "herhangi bir hata" yetkinin korundugu
  // KANITI sayiliyordu; permission denied, SQL sozdizimi veya altyapi hatasi
  // da yesil veriyordu. Artik iki ayri olcum var:
  //   N4  : IS KURALI engeline TAKILMAYAN bir alanda GERCEKTEN BASARILI
  //         UPDATE (RETURNING satiri + veritabani degeri).
  //   N4b : temizlik alanindaki ret YALNIZ beklenen kat hizmetleri is kurali
  //         hatasiysa kabul; ilgisiz yetki/SQL/altyapi hatasi testi KIRAR.
  const odaNoOnce = tek(`select oda_no from public.pms_odalar
    where id='${PMS.ODA203}';`);
  const yeniOdaNo = `CX731`;
  const vardYaz = olarak('vardiya', `update public.pms_odalar
    set oda_no='${yeniOdaNo}' where id='${PMS.ODA203}' returning oda_no;`);
  const vardOdaNo = tek(`select oda_no from public.pms_odalar
    where id='${PMS.ODA203}';`);
  sonuc(vardYaz.ok && vardYaz.out.trim() === yeniOdaNo && vardOdaNo === yeniOdaNo,
    'N4 vardiya GERCEKTEN basarili oda UPDATE yapti (kayit hakki korundu)',
    vardYaz.ok ? 'returning=' + vardYaz.out.trim() + ' db=' + vardOdaNo
               : 'BEKLENMEYEN HATA: ' + String(vardYaz.err).replace(/\s+/g, ' ').slice(-90));
  // Fikstur geri alinir (urun kurali degil, test verisi).
  O.sql(`set session_replication_role = replica;
    update public.pms_odalar set oda_no='${odaNoOnce}' where id='${PMS.ODA203}';
    set session_replication_role = origin;`);

  const vardOda = dene('vardiya');
  const vardDeger = tek(`select temizlik_durumu from public.pms_odalar
    where id='${PMS.ODA203}';`);
  // Kat hizmetleri is kurali: oda temizlik durumu gorev motorunun izdusumu.
  const IS_KURALI = /pms_housekeeping_oda_koruma|pms_housekeeping_tutarlilik_oda|H[0-9]+:/;
  if (vardOda.ok) {
    sonuc(vardOda.out.trim() !== '',
      'N4b vardiya temizlik alanini da yazabildi (RLS suzmedi)',
      'satir=' + vardOda.out.trim() + ' deger=' + vardDeger);
  } else {
    sonuc(IS_KURALI.test(String(vardOda.err)),
      'N4b temizlik reddi YALNIZ beklenen IS KURALI hatasi',
      IS_KURALI.test(String(vardOda.err))
        ? String(vardOda.err).replace(/\s+/g, ' ').match(IS_KURALI)[0]
        : 'BEKLENMEYEN HATA (basari sayilmaz): ' + String(vardOda.err).replace(/\s+/g, ' ').slice(-90));
  }
  // Oda tipi tanimi: her iki rolde de ret
  for (const kim of ['personel', 'vardiya']) {
    const ot = olarak(kim, `update public.pms_oda_tipleri set azami_kisi=99
      where id='${PMS.TIP}';`);
    const degisti = tek(`select azami_kisi::text from public.pms_oda_tipleri where id='${PMS.TIP}';`);
    sonuc(degisti !== '99', `N5 ${kim}: oda TIPI tanimini degistiremiyor`,
      ot.ok ? 'istek gecti, satir degismedi' : 'ret');
  }
  // Yardimcilarin DOGRUDAN cagrilmasi (MY4-T3)
  const dogrudan = olarak('personel',
    `select public.pms_oda_tipi_kilitle('${PMS.TIP}','811');`);
  sonuc(!dogrudan.ok, 'N6 kilit yardimcisi BASKA otel icin dogrudan cagrilamiyor',
    dogrudan.ok ? 'CAGRILDI (kusur)' : 'ret');
  const dogrudan2 = olarak('yetkisiz',
    `select public.pms_oda_tipi_kilitle('${PMS.TIP}','810');`);
  sonuc(!dogrudan2.ok, 'N6b yetkisiz rol kilit yardimcisini cagiramiyor',
    dogrudan2.ok ? 'CAGRILDI (kusur)' : 'ret');
  // Yardimci SATIRI DEGISTIRMIYOR
  const once = tek(`select azami_kisi::text from public.pms_oda_tipleri where id='${PMS.TIP}';`);
  olarak('personel', `select public.pms_oda_tipi_kilitle('${PMS.TIP}','810');`);
  es('N7 kilit yardimcisi oda tipi satirini DEGISTIRMIYOR', once,
    tek(`select azami_kisi::text from public.pms_oda_tipleri where id='${PMS.TIP}';`));

  // Mali ayrim hala yururlukte (kapanmis is bozulmadi)
  const folio = tek(`select id::text from public.pms_folyolar where durum='acik' limit 1;`);
  if (folio) {
    const neg = olarak('personel', `insert into public.pms_folio_odemeler
      (otel_id, folio_id, yontem, tutar, aciklama)
      values ('810','${folio}','nakit',-5,'Deneme');`);
    sonuc(!neg.ok, 'N8 MALI AYRIM hala yururlukte (personel negatif odeme yazamiyor)',
      neg.ok ? 'YAZDI (kusur)' : (neg.err.match(/MALI_[A-Z_]+|row-level/i) || ['ret'])[0]);
  } else {
    console.log('SINANMADI N8 — acik folyo yok; GECTI SAYILMAZ');
  }

  console.log('\n======================================================================');
  console.log(`SONUC: ${ok} gecti, ${fail} kaldi`);
  console.log('Yerel kanit; CANLI KABUL ve canli yetki degisikligi YERINE GECMEZ.');
  console.log('======================================================================');
} catch (e) {
  console.error('\nDUR: ' + (e && e.message));
  fail++;
} finally {
  try { O.temizle(); } catch {}
}
process.exit(fail === 0 ? 0 : 1);
