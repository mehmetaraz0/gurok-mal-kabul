// ===========================================================================
// SAYIM ERISIMI (A1 bolum 15c) — IZOLE TEST (uretime BAGLANMAZ)
// ===========================================================================
// 15c iki AYRI kapi tanimlar:
//   (1) OLUSTURMA + LISTELEME -> stok_takip:kayit + otel
//   (2) ONAY + RET            -> auth_sayim_onaycisi() = aktif cost_control
//                                kullanicisi + stok_takip:kayit
// Bu test ozellikle su soruyu olcer (kullanici karari 2026-09-20):
//   "stok_takip:kayit sahibi ama COST CONTROL OLMAYAN kullanici ne yapabilir?"
//   Beklenen: sayim OLUSTURUR ve LISTELER; ONAYLAYAMAZ, REDDEDEMEZ.
//
// Kullanicilar:
//   DEPO810  rol='depo', stok_takip kayit, otel 810  -> (1) evet, (2) HAYIR
//   CC810    rol='cost_control', stok_takip kayit    -> (1) evet, (2) evet
//   GORUNTU  stok_takip yok                          -> hicbiri
//   BAR811   stok_takip kayit ama otel 811           -> 810'a erisemez
//   PASIF    pasif                                   -> hicbiri
// ===========================================================================
import { barOrtami } from './bar-test-ortam.mjs';
import { K } from './bar-a1-tohum.mjs';

const A1 = 'docs/kurulum/2026-09-18-bar-a1-guvenlik.sql';
const GERI_AL = 'docs/kurulum/2026-09-18-bar-a1-guvenlik-geri-al.sql';

const GORUNTU810 = { rol: 'authenticated', sub: '11111111-0000-0000-0000-0000000000bb' };
const CC810 = { rol: 'authenticated', sub: '11111111-0000-0000-0000-0000000000c1' };
// PASIF cost_control: rol dogru, yetki dogru, ama kullanicilar.aktif = false.
// auth_sayim_onaycisi() 'aktif is true' arar; ise alinmamis/ayrilmis personelin
// onay yetkisini surdurmemesi bu satira bagli.
const CCPASIF810 = { rol: 'authenticated', sub: '11111111-0000-0000-0000-0000000000c2' };
const OTURUM = '99999999-0000-0000-0000-0000000000a1';
const DEPO = '810_CSM302';

const O = barOrtami({ ad: 'sayim-rls' });
let ok = 0, fail = 0;
const sonuc = (g, ad, ek) => { console.log((g ? 'OK   ' : 'FAIL ') + ad + (ek ? ' — ' + ek : '')); if (g) ok++; else fail++; };

const q = (kimlik, sql) => O.kimlikle(kimlik, sql);
const tek = (sql) => O.sql(sql).out;
const tohum = (sql) => tek(`set session_replication_role = replica;\n${sql}\nset session_replication_role = origin;`);
const yeniId = () => tek(`select gen_random_uuid();`);
const durum = (id) => tek(`select durum from public.sayim_oturumlari where id='${id}';`);

const oturumEkle = (kimlik, id, otel = '810') => q(kimlik,
  `insert into public.sayim_oturumlari (id, depo_kodu, otel_id, olusturan_ad, durum, toplam_urun_sayisi, farkli_urun_sayisi)
   values ('${id}', '${otel === '810' ? DEPO : '811_BAR'}', '${otel}', 'Test', 'onay_bekliyor', 1, 1);`);
const detayEkle = (kimlik, oturumId) => q(kimlik,
  `insert into public.sayim_detaylari (oturum_id, urun_kodu, urun_adi, birim, sistem_miktar, sayilan_miktar, fark, fark_yuzde)
   values ('${oturumId}', 'BIRA', 'Bira', 'KTU', 10, 8, -2, 20);`);
const oturumSayisi = (kimlik) => q(kimlik, `select count(*) from public.sayim_oturumlari;`).out;
const reddet = (kimlik, id) => q(kimlik,
  `update public.sayim_oturumlari set durum='reddedildi', onaylayan_ad='Test', onay_tarihi=now(), red_nedeni='test'
    where id='${id}';`);
const onayla = (kimlik, id) => q(kimlik, `select public.stok_sayim_onayla('${id}');`);
const hataKodu = (r) => { const m = /ERROR:\s+([A-Z_]+):/.exec(r.err || ''); return m ? m[1] : (r.ok ? '(hatasiz)' : (r.err || '').split('\n').pop()); };

try {
  await O.kur();

  // cost_control kullanicisi: rol='cost_control', stok_takip kayit veren rol (b003)
  tohum(`insert into auth.users (id, email) values ('${CC810.sub}', 'cc810@test.local');
         insert into public.kullanicilar (id, auth_user_id, ad, rol, otel_id, aktif, rol_id) values
           ('33333333-0000-0000-0000-0000000000c1', '${CC810.sub}', 'Cost 810', 'cost_control', '810', true,
            '00000000-0000-0000-0000-00000000b003');
         insert into auth.users (id, email) values ('${CCPASIF810.sub}', 'ccpasif810@test.local');
         insert into public.kullanicilar (id, auth_user_id, ad, rol, otel_id, aktif, rol_id) values
           ('33333333-0000-0000-0000-0000000000c2', '${CCPASIF810.sub}', 'Cost Pasif 810', 'cost_control', '810', false,
            '00000000-0000-0000-0000-00000000b003');`);

  const a = O.uygulaTekIslem(A1);
  sonuc(a.ok, 'Taban: A1 (15c dahil) tek islemde uygulandi — son kosullari kendi dogruluyor',
    a.ok ? '' : a.err.split('\n').slice(-4).join(' | '));
  if (!a.ok) throw new Error('A1 uygulanamadi');

  // ---------------- (1) OLUSTURMA + LISTELEME ----------------
  const o1 = oturumEkle(K.DEPO810, OTURUM);
  const d1 = o1.ok ? detayEkle(K.DEPO810, OTURUM) : { ok: false };
  sonuc(o1.ok && d1.ok, 'Y1 stok_takip:kayit (rol=depo) sayim OLUSTURUYOR (oturum + detay)',
    o1.ok ? '' : (o1.err || '').split('\n').pop());
  sonuc(oturumSayisi(K.DEPO810) === '1', 'Y2 ayni kullanici kendi otelinin sayimlarini LISTELIYOR');
  sonuc(oturumSayisi(CC810) === '1', 'Y3 cost_control da listeliyor');

  // ---------------- (2) ONAY + RET — AYRI KAPI ----------------
  const rDepo = reddet(K.DEPO810, OTURUM);
  sonuc(durum(OTURUM) === 'onay_bekliyor',
    'Y4 stok_takip:kayit ama COST CONTROL DEGIL -> REDDEDEMIYOR (sessiz 0 satir)',
    rDepo.ok ? 'yazma politika ile engellendi' : hataKodu(rDepo));

  const oDepo = onayla(K.DEPO810, OTURUM);
  sonuc(!oDepo.ok && hataKodu(oDepo) === 'YETKI_YOK' && durum(OTURUM) === 'onay_bekliyor',
    'Y5 ayni kullanici API yolundan da ONAYLAYAMIYOR (RPC onayci kapisi)', hataKodu(oDepo));

  const oCc = onayla(CC810, OTURUM);
  sonuc(oCc.ok && durum(OTURUM) === 'onaylandi', 'Y6 cost_control ONAYLIYOR', oCc.ok ? '' : hataKodu(oCc));

  const ikinci = yeniId();
  tohum(`insert into public.sayim_oturumlari (id, depo_kodu, otel_id, olusturan_ad, durum, toplam_urun_sayisi, farkli_urun_sayisi)
           values ('${ikinci}', '${DEPO}', '810', 'Tohum', 'onay_bekliyor', 1, 1);
         insert into public.sayim_detaylari (oturum_id, urun_kodu, urun_adi, birim, sistem_miktar, sayilan_miktar, fark, fark_yuzde)
           values ('${ikinci}', 'BIRA', 'Bira', 'KTU', 10, 9, -1, 10);`);
  const rCc = reddet(CC810, ikinci);
  sonuc(rCc.ok && durum(ikinci) === 'reddedildi', 'Y7 cost_control REDDEDIYOR');

  // ---------------- Negatif kontroller ----------------
  const ucuncu = yeniId();
  tohum(`insert into public.sayim_oturumlari (id, depo_kodu, otel_id, olusturan_ad, durum, toplam_urun_sayisi, farkli_urun_sayisi)
         values ('${ucuncu}', '${DEPO}', '810', 'Tohum', 'onay_bekliyor', 1, 1);`);
  const dogrudan = q(CC810, `update public.sayim_oturumlari set durum='onaylandi' where id='${ucuncu}';`);
  sonuc(durum(ucuncu) === 'onay_bekliyor',
    'N1 cost_control bile DOGRUDAN "onaylandi" yazamiyor (onay yalniz RPC ile)',
    dogrudan.ok ? 'engellendi' : hataKodu(dogrudan));

  const gor = oturumEkle(GORUNTU810, yeniId());
  sonuc(!gor.ok && /row-level security/i.test(gor.err), 'N2 stok_takip yetkisi olmayan sayim olusturamaz');
  sonuc(oturumSayisi(GORUNTU810) === '0', 'N3 stok_takip yetkisi olmayan sayim gormuyor');
  sonuc(oturumSayisi(K.BAR811) === '0', 'N4 baska otel kullanicisi 810 sayimlarini gormuyor');
  const bas = oturumEkle(K.BAR811, yeniId(), '810');
  sonuc(!bas.ok && /row-level security/i.test(bas.err), 'N5 baska otel adina sayim olusturulamaz');
  const pasif = oturumEkle(K.PASIF, yeniId());
  sonuc(!pasif.ok && /row-level security/i.test(pasif.err), 'N6 pasif kullanici sayim olusturamaz');

  // PASIF COST CONTROL: rol ve yetki dogru, yalniz aktif=false. Uc kapinin
  // ucu de kapali olmali; yoksa ayrilan personel onay yetkisini surdururdu.
  const pasifOturum = yeniId();
  tohum(`insert into public.sayim_oturumlari (id, depo_kodu, otel_id, olusturan_ad, durum, toplam_urun_sayisi, farkli_urun_sayisi)
           values ('${pasifOturum}', '${DEPO}', '810', 'Tohum', 'onay_bekliyor', 1, 1);
         insert into public.sayim_detaylari (oturum_id, urun_kodu, urun_adi, birim, sistem_miktar, sayilan_miktar, fark, fark_yuzde)
           values ('${pasifOturum}', 'BIRA', 'Bira', 'KTU', 10, 9, -1, 10);`);
  const pOnay = onayla(CCPASIF810, pasifOturum);
  sonuc(!pOnay.ok && hataKodu(pOnay) === 'YETKI_YOK' && durum(pasifOturum) === 'onay_bekliyor',
    'N6b PASIF cost_control ONAYLAYAMIYOR (aktif=false); oturum degismedi', hataKodu(pOnay));
  const pRed = reddet(CCPASIF810, pasifOturum);
  sonuc(durum(pasifOturum) === 'onay_bekliyor',
    'N6c PASIF cost_control REDDEDEMIYOR; oturum hala onay_bekliyor',
    pRed.ok ? 'yazma politika ile engellendi' : hataKodu(pRed));
  sonuc(oturumSayisi(CCPASIF810) === '0', 'N6d PASIF cost_control sayim LISTELEYEMIYOR');

  const detaySel = q(K.DEPO810, `select count(*) from public.sayim_detaylari;`);
  sonuc(!detaySel.ok && /permission denied/i.test(detaySel.err),
    'N7 sayim_detaylari dogrudan okunamiyor (A1 katmani korundu)');
  const rpc = q(K.DEPO810, `select count(*) from public.stok_sayim_detaylari('${OTURUM}');`);
  sonuc(rpc.ok && rpc.out === '1', 'N8 detaylar yalniz stok_sayim_detaylari RPC ile okunuyor');

  const trunc = q(K.DEPO810, `truncate table public.sayim_detaylari;`);
  sonuc(!trunc.ok && /permission denied|must be owner/i.test(trunc.err),
    'N9 TRUNCATE reddediliyor (A1 oncesi mumkundu)', (trunc.err || '').split('\n').pop());
  const del = q(K.DEPO810, `delete from public.sayim_oturumlari where id='${OTURUM}';`);
  sonuc(!del.ok && /permission denied/i.test(del.err), 'N10 DELETE reddediliyor');

  // Kismen uygulanmis oturum reddedilemez
  const dorduncu = yeniId();
  tohum(`insert into public.sayim_oturumlari (id, depo_kodu, otel_id, olusturan_ad, durum, toplam_urun_sayisi, farkli_urun_sayisi, kismi_uygulandi)
         values ('${dorduncu}', '${DEPO}', '810', 'Tohum', 'onay_bekliyor', 1, 1, true);`);
  reddet(CC810, dorduncu);
  sonuc(durum(dorduncu) === 'onay_bekliyor',
    'N11 kismen uygulanmis oturum cost_control tarafindan da reddedilemez');

  // ---------------- Geri alma ----------------
  const g = O.uygulaTekIslem(GERI_AL);
  sonuc(g.ok, 'G1 A1 geri alma calisti', g.ok ? '' : (g.err || '').split('\n').slice(-3).join(' | '));
  if (g.ok) {
    sonuc(oturumSayisi(K.DEPO810) === '0' && tek(`select to_regprocedure('public.auth_sayim_onaycisi()') is null;`) === 't',
      'G2 geri almada 15c politikalari ve onayci kapisi kalkiyor (A1 oncesi durum)');
    sonuc(tek(`select has_table_privilege('authenticated','public.sayim_oturumlari','truncate');`) === 'f',
      'G3 TRUNCATE hakki geri VERILMIYOR (ayri guvenlik duzeltmesi)');
  }
} catch (e) {
  sonuc(false, 'beklenmeyen hata', String(e && e.message || e));
} finally {
  O.temizle();
}
console.log(`\nSAYIM ERISIMI (15c): ${ok} OK / ${fail} FAIL`);
process.exit(fail ? 1 : 0);
