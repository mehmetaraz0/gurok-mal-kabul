// ===========================================================================
// BAR A1 — VERITABANI TESTLERI (uretime BAGLANMAZ)
// ===========================================================================
// Taban: uretim dokumu + uretim-sonrasi migration'lar (bar-test-ortam.mjs) +
// A1 migration'i TEK ISLEMDE (uretim kanaliyla ayni kip).
// Kapsam: tasarim bolum 10 Asama 1 senaryolari + kararlar T23-T25 + G1'deki
// dokuz kusurun TERS yonu. Kritik korumalarin negatif kontrolleri
// scripts/bar-a1-negatif.test.mjs dosyasindadir.
// ===========================================================================
import { barOrtami, hataKodu } from './bar-test-ortam.mjs';
import { K, M, BAR, FOLYO101, EK_TOHUM, a1Yardimcilari } from './bar-a1-tohum.mjs';

const MIG = 'docs/kurulum/2026-09-18-bar-a1-guvenlik.sql';
const O = barOrtami({ ad: 'bar-a1-db' });
let ok = 0, fail = 0;
const sonuc = (g, ad, ek) => { console.log((g ? 'OK   ' : 'FAIL ') + ad + (ek ? ' — ' + ek : '')); if (g) ok++; else fail++; };

const { q, kalemler, siparis, VISKI1, tek, stok, kod, hazirla, folyoKapat, sifirla } = a1Yardimcilari(O);

try {
  await O.kur();
  const u = O.uygulaTekIslem(MIG);
  sonuc(u.ok, 'A1 migration tek islemde uygulandi', u.ok ? '' : u.err.split('\n').slice(-6).join(' | '));
  if (!u.ok) throw new Error('migration uygulanamadi');
  const t = O.sql(EK_TOHUM);
  if (!t.ok) throw new Error('ek tohum: ' + t.err.slice(-300));

  // ---------------- A) Siparis ve dogrulama (T23) ----------------
  sifirla();
  sonuc(kod(siparis(K.QR, VISKI1, null)) === 'ODA_NO_GEREKLI', 'A1 ucretli QR siparisi odasiz REDDEDILIR (ONCE-1 tersi)');
  sonuc(kod(siparis(K.QR, VISKI1, '103')) === 'KONAKLAMA_YOK', 'A2 bos odaya ucretli siparis: KONAKLAMA_YOK');
  sonuc(kod(siparis(K.QR, [{ menu_urun_id: M.VISKI, adet: 1, gosterilen_fiyat: 200 }], '101')) === 'FIYAT_DEGISTI'
     && kod(siparis(K.QR, [{ menu_urun_id: M.VISKI, adet: 1 }], '101')) === 'FIYAT_DEGISTI',
    'A3 gosterilen fiyat farkli ya da eksik: FIYAT_DEGISTI');
  const qr = siparis(K.QR, VISKI1, '101');
  const qrSat = tek(`select s.kanal||'|'||s.oda_dogrulama_durumu||'|'||k.birim_fiyat::text||'|'||k.ucretli
                       from public.bar_siparisleri s join public.bar_siparis_kalemleri k on k.siparis_id=s.id where s.id='${qr.out}';`);
  sonuc(qr.ok && qrSat === 'qr|bekliyor|250.00|true', 'A4 dogru QR siparisi: kanal qr, dogrulama bekliyor, fiyat anlik goruntusu 250', qrSat);

  const g = siparis(K.BAR810, VISKI1, '101');
  sonuc(g.ok && tek(`select kanal||'|'||oda_dogrulama_durumu from public.bar_siparisleri where id='${g.out}';`) === 'personel|bekliyor',
    'A5 GARSONUN siparisi girmesi dogrulama SAYILMAZ: personel kanali da bekliyor baslar (T18/T23)');
  sonuc(kod(q(K.BAR810, `select public.bar_siparis_durum_guncelle('${g.out}','hazirlaniyor');`)) === 'ODA_DOGRULAMASI_BEKLIYOR',
    'A6 dogrulama beklerken hazirlik REDDEDILIR (ONCE-2 tersi)');
  sonuc(kod(q(K.BAR810, `select public.bar_siparis_oda_dogrula('${g.out}', false);`)) === 'DOGRULAMA_BEYANI_GEREKLI',
    'A7a beyansiz dogrulama REDDEDILIR');
  sonuc(kod(q(K.QR, `select public.bar_siparis_oda_dogrula('${g.out}', true);`)) === 'KIMLIK_GEREKLI',
    'A7b servis rolu (kimliksiz) dogrulayamaz: dogrulayan kaydedilmek zorunda');
  const d = q(K.BAR810, `select public.bar_siparis_oda_dogrula('${g.out}', true);`);
  const dSat = tek(`select oda_dogrulama_durumu||'|'||dogrulayan::text||'|'||folio_id::text||'|'||(dogrulama_zamani is not null)||'|'||dogrulama_beyani
                      from public.bar_siparisleri where id='${g.out}';`);
  sonuc(d.ok && dSat === `dogrulandi|${K.BAR810.sub}|${FOLYO101}|true|Misafirin oda kartini/kimligini kontrol ettim`,
    'A7c beyanli dogrulama: folyo baglandi, DOGRULAYAN / zaman / beyan kaydedildi', dSat);
  sonuc(/zaten_dogrulandi/.test(q(K.BAR810, `select public.bar_siparis_oda_dogrula('${g.out}', true);`).out),
    'A7d tekrar dogrulama: zaten_dogrulandi');
  const ucretsiz = siparis(K.BAR810, [{ menu_urun_id: M.BIRA, adet: 1 }]);
  sonuc(ucretsiz.ok && tek(`select oda_dogrulama_durumu from public.bar_siparisleri where id='${ucretsiz.out}';`) === 'gerekmiyor'
     && hazirla(ucretsiz.out).ok, 'A8 ucretsiz siparis dogrulama gerektirmez ve hazirlanir (bugunku akis)');
  sonuc(kod(siparis(K.BAR810, [{ menu_urun_id: M.LIMONATA, adet: 1 }], null, '811_CSM302')) === 'DEPO_OTEL_UYUSMAZ',
    'A9 depo-otel uyusmazligi REDDEDILIR (ONCE-5 tersi)');
  sonuc(kod(siparis(K.BAR811, [{ menu_urun_id: M.BIRA, adet: 1 }])) === 'OTEL_ERISIMI_YOK'
     && kod(siparis(K.PASIF, [{ menu_urun_id: M.BIRA, adet: 1 }])) === 'YETKI_YOK',
    'A10 baska otelin personeli ve pasif kullanici siparis olusturamaz');
  const rd = q(K.BAR810, `update public.bar_siparisleri set oda_dogrulama_durumu='dogrulandi' where id='${qr.out}';`);
  const rd2 = q(K.BAR810, `update public.bar_siparisleri set durum='teslim_edildi' where id='${ucretsiz.out}';`);
  const rd3 = q(K.BAR810, `update public.bar_siparis_kalemleri set birim_fiyat=1 where siparis_id='${g.out}';`);
  sonuc(!rd.ok && !rd2.ok && !rd3.ok && /permission denied/.test(rd.err + rd2.err + rd3.err),
    'A11 RPC atlanarak DOGRUDAN yazma kapali: dogrulama, durum ve kalem fiyati degistirilemez');

  // ---------------- B) Teslim (T3, T24) ----------------
  sifirla();
  const b1 = siparis(K.BAR810, VISKI1, '101');
  q(K.BAR810, `select public.bar_siparis_oda_dogrula('${b1.out}', true);`);
  hazirla(b1.out);
  O.sql(`update public.menu_urunler set fiyat = 300 where id = '${M.VISKI}';`);
  const t1 = q(K.BAR810, `select public.bar_siparis_teslim_et('${b1.out}');`);
  const borc1 = tek(`select string_agg(tutar::text, ',') from public.pms_folio_hareketleri where kaynak_id='${b1.out}';`);
  sonuc(t1.ok && borc1 === '250.00', 'B1 borc SIPARIS anindaki fiyattan (250), teslimdeki 300den degil (ONCE-9 tersi)', 'borc ' + borc1);
  const t1b = q(K.BAR810, `select public.bar_siparis_teslim_et('${b1.out}');`);
  sonuc(/zaten_teslim/.test(t1b.out) && tek(`select count(*) from public.pms_folio_hareketleri where kaynak_id='${b1.out}';`) === '1'
     && tek(`select count(*) from public.bar_stok_tuketimleri where siparis_id='${b1.out}';`) === '1' && stok('VISKI') === '1.000',
    'B2 ikinci teslim: zaten_teslim; tek tuketim, tek borc, tek stok dusumu');
  sonuc(!/2026-07-09/.test(tek(`select guncelleme_tarihi::text from public.stok where urun_kodu='VISKI' and depo_kodu='${BAR}';`)),
    'B2b teslimde stok satirinin guncelleme_tarihi yazildi (tasarim 3.5.1)');

  sifirla();
  const b3 = siparis(K.BAR810, [{ menu_urun_id: M.BIRA, adet: 2 }]);
  hazirla(b3.out);
  const p1 = O.paralel(K.BAR810, `select public.bar_siparis_teslim_et('${b3.out}'); select pg_sleep(2);`);
  await new Promise((r) => setTimeout(r, 700));
  const p2 = O.paralel(K.BAR810, `select public.bar_siparis_teslim_et('${b3.out}');`);
  const [pr1, pr2] = await Promise.all([p1, p2]);
  sonuc(pr1.ok && pr2.ok && /zaten_teslim/.test(pr2.out) && stok('BIRA') === '8.000',
    'B3 ESZAMANLI iki teslim: stok TEK kez duser (ONCE-4 tersi)', 'stok 10 -> ' + stok('BIRA') + ' | ikinci: ' + pr2.out);

  sifirla();
  const b4 = siparis(K.BAR810, [{ menu_urun_id: M.BIRA, adet: 3 }]);
  hazirla(b4.out);
  O.sql(`update public.stok set miktar = 1 where urun_kodu='BIRA' and depo_kodu='${BAR}';`);
  const t4 = q(K.BAR810, `select public.bar_siparis_teslim_et('${b4.out}');`);
  sonuc(kod(t4) === 'STOK_TUTARSIZ' && stok('BIRA') === '1.000'
     && tek(`select durum from public.bar_siparisleri where id='${b4.out}';`) === 'hazir',
    'B4 kayitli stok yetersizse STOK_TUTARSIZ; sessiz 0a kirpma YOK, hicbir sey yazilmadi (ONCE-6 tersi)');

  // Kapali folyo + istisna (T24)
  sifirla();
  const b5 = siparis(K.BAR810, VISKI1, '101');
  q(K.BAR810, `select public.bar_siparis_oda_dogrula('${b5.out}', true);`);
  hazirla(b5.out);
  folyoKapat();
  sonuc(kod(q(K.BAR810, `select public.bar_siparis_teslim_et('${b5.out}');`)) === 'FOLYO_KAPALI' && stok('VISKI') === '2.000',
    'B5a folyo kapali + beyansiz teslim: FOLYO_KAPALI, hicbir sey yazilmadi');
  sonuc(kod(q(K.BAR810, `select public.bar_siparis_teslim_et('${b5.out}', true);`)) === 'YETKI_YOK' && stok('VISKI') === '2.000',
    'B5b istisnayi YETKISIZ personel (bar kayit) acamaz');
  const ist = q(K.SEF810, `select public.bar_siparis_teslim_et('${b5.out}', true);`);
  const istSat = tek(`select s.durum||'|'||i.durum||'|'||i.tutar::text||'|'||i.beyan_veren::text
                        from public.bar_siparisleri s join public.bar_borc_istisnalari i on i.siparis_id=s.id where s.id='${b5.out}';`);
  sonuc(/istisna_acildi/.test(ist.out) && istSat === `istisna_bekliyor|acik|250.00|${K.SEF810.sub}` && stok('VISKI') === '1.000'
     && tek(`select count(*) from public.pms_folio_hareketleri where kaynak_id='${b5.out}';`) === '0',
    'B5c yetkili istisna: stok bir kez dustu, borc YOK, siparis istisna_bekliyor (tamamlanmadi)', istSat);
  const ist2 = q(K.SEF810, `select public.bar_siparis_teslim_et('${b5.out}', true);`);
  sonuc(/zaten_istisnali/.test(ist2.out) && stok('VISKI') === '1.000'
     && tek(`select count(*) from public.bar_stok_tuketimleri where siparis_id='${b5.out}';`) === '1',
    'B5d ayni siparis icin ikinci istisna/teslim: ikinci stok dusumu YOK');
  sonuc(!q(K.BAR810, `select public.bar_siparis_durum_guncelle('${b5.out}','hazir');`).ok
     && !q(K.BAR810, `select public.bar_siparis_iptal('${b5.out}','deneme');`).ok,
    'B5e istisna bekleyen siparis hazira donemez, iptal edilemez');

  // Istisna cozumu
  sonuc(kod(q(K.BAR810, `select public.bar_borc_istisnasi_coz((select id from public.bar_borc_istisnalari where siparis_id='${b5.out}'),'tahsil_edilemedi',null,false,'x');`)) === 'YETKI_YOK',
    'B6a istisnayi bar personeli COZEMEZ (pms_folio yetkisi gerekir)');
  const istId = tek(`select id from public.bar_borc_istisnalari where siparis_id='${b5.out}';`);
  sonuc(kod(q(K.ONBURO810, `select public.bar_borc_istisnasi_coz('${istId}','folyoya_yaz','${FOLYO101}',false);`)) === 'DOGRULAMA_BEYANI_GEREKLI',
    'B6b folyoya yazma misafir yeniden dogrulanmadan REDDEDILIR');
  sonuc(kod(q(K.ONBURO810, `select public.bar_borc_istisnasi_coz('${istId}','folyoya_yaz','${FOLYO101}',true);`)) === 'FOLYO_KAPALI',
    'B6c kapali folyoya yazma REDDEDILIR');
  O.sql(`set session_replication_role = replica;
         insert into public.pms_folyolar (id, otel_id, rezervasyon_id, folio_no, durum)
         values ('55555555-0000-0000-0000-0000000001aa','810','88888888-0000-0000-0000-000000000101','F-101B','acik');
         set session_replication_role = origin;`);
  const coz = q(K.ONBURO810, `select public.bar_borc_istisnasi_coz('${istId}','folyoya_yaz','55555555-0000-0000-0000-0000000001aa',true,'misafir ikinci folyo');`);
  const cozSat = tek(`select s.durum||'|'||i.durum||'|'||(select count(*) from public.pms_folio_hareketleri h where h.kaynak_id=s.id)
                        from public.bar_siparisleri s join public.bar_borc_istisnalari i on i.siparis_id=s.id where s.id='${b5.out}';`);
  sonuc(coz.ok && cozSat === 'teslim_edildi|folyoya_yazildi|1', 'B6d cozum: secilen acik folyoya TEK borc, siparis ancak simdi tamamlandi', cozSat);
  const coz2 = q(K.ONBURO810, `select public.bar_borc_istisnasi_coz('${istId}','folyoya_yaz','55555555-0000-0000-0000-0000000001aa',true);`);
  sonuc(/zaten_cozuldu/.test(coz2.out) && tek(`select count(*) from public.pms_folio_hareketleri where kaynak_id='${b5.out}';`) === '1',
    'B6e ikinci cozum: zaten_cozuldu, ikinci borc YOK');

  sifirla();
  const b7 = siparis(K.BAR810, VISKI1, '101');
  q(K.BAR810, `select public.bar_siparis_oda_dogrula('${b7.out}', true);`);
  hazirla(b7.out);
  folyoKapat();
  q(K.SEF810, `select public.bar_siparis_teslim_et('${b7.out}', true);`);
  const i7 = tek(`select id from public.bar_borc_istisnalari where siparis_id='${b7.out}';`);
  sonuc(kod(q(K.ONBURO810, `select public.bar_borc_istisnasi_coz('${i7}','tahsil_edilemedi',null,false,'misafir ayrildi');`)) === 'YETKI_YOK'
     && tek(`select durum from public.bar_borc_istisnalari where id='${i7}';`) === 'acik',
    'B7a K2: tahsil edilemedi karari pms_folio KAYIT yetkisiyle REDDEDILIR (tam gerekir)');
  sonuc(kod(q(K.ONBUROMUD810, `select public.bar_borc_istisnasi_coz('${i7}','tahsil_edilemedi');`)) === 'COZUM_NOTU_GEREKLI',
    'B7b tahsil edilemedi kararinda gerekce zorunlu (tam yetkili icin de)');
  const c7 = q(K.ONBUROMUD810, `select public.bar_borc_istisnasi_coz('${i7}','tahsil_edilemedi',null,false,'misafir ayrildi');`);
  sonuc(c7.ok && tek(`select durum from public.bar_siparisleri where id='${b7.out}';`) === 'teslim_edildi'
     && tek(`select count(*) from public.pms_folio_hareketleri where kaynak_id='${b7.out}';`) === '0'
     && tek(`select cozen::text||'|'||cozum_notu||'|'||(cozum_zamani is not null) from public.bar_borc_istisnalari where id='${i7}';`)
        === `${K.ONBUROMUD810.sub}|misafir ayrildi|true`,
    'B7c tahsil edilemedi (tam): borc yazilmadi, siparis tamamlandi; AKTOR, gerekce ve zaman kaydedildi');

  // K3: borc yalniz dogrulanmis konaklamanin acik folyosuna
  sifirla();
  const b8 = siparis(K.BAR810, VISKI1, '101');
  q(K.BAR810, `select public.bar_siparis_oda_dogrula('${b8.out}', true);`);
  hazirla(b8.out);
  folyoKapat();
  q(K.SEF810, `select public.bar_siparis_teslim_et('${b8.out}', true);`);
  const i8 = tek(`select id from public.bar_borc_istisnalari where siparis_id='${b8.out}';`);
  O.sql(`set session_replication_role = replica;
         insert into public.pms_folyolar (id, otel_id, rezervasyon_id, folio_no, durum) values
           ('55555555-0000-0000-0000-0000000001bb','810','88888888-0000-0000-0000-000000000999','F-BASKA','acik'),
           ('55555555-0000-0000-0000-0000000001aa','810','88888888-0000-0000-0000-000000000101','F-101B','acik');
         set session_replication_role = origin;`);
  sonuc(kod(q(K.ONBURO810, `select public.bar_borc_istisnasi_coz('${i8}','folyoya_yaz','55555555-0000-0000-0000-0000000001bb',true);`)) === 'FOLYO_BASKA_KONAKLAMA'
     && tek(`select count(*) from public.pms_folio_hareketleri where kaynak_id='${b8.out}';`) === '0',
    'B8 K3: BASKA konaklamanin acik folyosuna yazma sunucuda REDDEDILIR (oda numarasi degil konaklama bagi esas)');
  const liste = (kim) => q(kim, `select public.bar_istisna_listesi()::text;`);
  const l1 = liste(K.ONBURO810);
  let lj = null; try { lj = JSON.parse(l1.out.split('\n').pop()); } catch { /* asagida FAIL */ }
  const hedefler = lj ? lj.istisnalar.flatMap((x) => x.hedef_folyolar.map((f) => f.folio_no)).join(',') : '';
  const lm = (() => { try { return JSON.parse(liste(K.ONBUROMUD810).out.split('\n').pop()); } catch { return null; } })();
  sonuc(lj && lj.istisnalar.length === 1 && hedefler === 'F-101B' && lj.folyoya_yazabilir === true
     && lj.tahsil_edilemedi_diyebilir === false && lm && lm.tahsil_edilemedi_diyebilir === true
     && /Viski ×1/.test(lj.istisnalar[0].kalemler) && lj.istisnalar[0].beyan_veren === 'Sef 810'
     && kod(liste(K.BAR810)) === 'YETKI_YOK',
    'B9 on buro listesi: yalniz acik istisna; hedef aday YALNIZ ayni konaklamanin folyosu (F-BASKA yok); yetki bayraklari kayit/tam; bar personeli goremez',
    hedefler + ' | ' + (lj ? lj.istisnalar[0].kalemler : l1.err.slice(0, 120)));
  O.sql(`set session_replication_role = replica; update public.bar_borc_istisnalari set eski_rezervasyon_id = null where id='${i8}';
         set session_replication_role = origin;`);
  sonuc(kod(q(K.ONBURO810, `select public.bar_borc_istisnasi_coz('${i8}','folyoya_yaz','55555555-0000-0000-0000-0000000001aa',true);`)) === 'KONAKLAMA_BAGI_YOK',
    'B10 dogrulanmis konaklama bagi olmayan istisna hicbir folyoya yazilamaz');

  // ---------------- C) Iptal (T24, O11) ----------------
  sifirla();
  const c1 = siparis(K.BAR810, [{ menu_urun_id: M.BIRA, adet: 2 }]);
  sonuc(kod(q(K.BAR810, `select public.bar_siparis_iptal('${c1.out}', '');`)) === 'IPTAL_NEDENI_GEREKLI', 'C1a iptal nedeni zorunlu');
  sonuc(q(K.BAR810, `select public.bar_siparis_iptal('${c1.out}', 'misafir vazgecti');`).ok
     && tek(`select string_agg(durum::text, ',') from public.stok_rezervasyonlari;`) === 'serbest' && stok('BIRA') === '10.000',
    'C1b yeni siparis iptali: rezervasyon serbest, stok degismedi');

  sifirla();
  const c2 = siparis(K.BAR810, [{ menu_urun_id: M.BIRA, adet: 2 }]);
  q(K.BAR810, `select public.bar_siparis_durum_guncelle('${c2.out}','hazirlaniyor');`);
  const rez2 = tek(`select id from public.stok_rezervasyonlari where durum='aktif';`);
  sonuc(kod(q(K.BAR810, `select public.bar_siparis_iptal('${c2.out}', 'x');`)) === 'KULLANILAN_MIKTAR_GEREKLI',
    'C2a hazirlanan siparis: kullanilan miktar girilmeden iptal REDDEDILIR (varsayilan yok)');
  const kul = (m, n, a) => kalemler([{ rezervasyon_id: rez2, kullanilan_miktar: m, kullanim_nedeni: n, aciklama: a }]);
  sonuc(kod(q(K.BAR810, `select public.bar_siparis_iptal('${c2.out}', 'x', ${kul(3, 'dokuldu_kirildi')});`)) === 'KULLANILAN_MIKTAR_GECERSIZ'
     && kod(q(K.BAR810, `select public.bar_siparis_iptal('${c2.out}', 'x', ${kul(1, null)});`)) === 'KULLANIM_NEDENI_GEREKLI'
     && kod(q(K.BAR810, `select public.bar_siparis_iptal('${c2.out}', 'x', ${kul(1, 'diger')});`)) === 'KULLANIM_NEDENI_GEREKLI',
    'C2b kullanilan > rezerve, nedensiz kullanim ve aciklamasiz "diger" REDDEDILIR');
  const c2i = q(K.BAR810, `select public.bar_siparis_iptal('${c2.out}', 'masa degisti', ${kul(1, 'dokuldu_kirildi')});`);
  const c2t = tek(`select tur||'|'||kullanim_nedeni||'|'||miktar::text from public.bar_stok_tuketimleri where siparis_id='${c2.out}';`);
  const c2r = tek(`select string_agg(durum::text||':'||miktar::text, ',' order by durum) from public.stok_rezervasyonlari;`);
  sonuc(c2i.ok && c2t === 'iptal_kullanimi|dokuldu_kirildi|1.000' && c2r === 'serbest:1.000,kullanildi:1.000' && stok('BIRA') === '9.000'
     && tek(`select count(*) from public.bar_stok_tuketimleri where tur='zayi';`) === '0',
    'C2c kismi kullanim: 1 birim "iptal_kullanimi" (ZAYI DEGIL) + nedeni; rezervasyon bolundu, 1 serbest (ONCE-8 tersi)',
    c2t + ' | ' + c2r);

  sifirla();
  const c3 = siparis(K.BAR810, [{ menu_urun_id: M.BIRA, adet: 2 }]);
  hazirla(c3.out);
  const rez3 = tek(`select id from public.stok_rezervasyonlari where durum='aktif';`);
  sonuc(kod(q(K.BAR810, `select public.bar_siparis_iptal('${c3.out}', 'x');`)) === 'KULLANILAN_MIKTAR_GEREKLI'
     && q(K.BAR810, `select public.bar_siparis_iptal('${c3.out}', 'x', ${kalemler([{ rezervasyon_id: rez3, kullanilan_miktar: 0 }])});`).ok
     && stok('BIRA') === '10.000',
    'C3 HAZIR siparis iptali de giris ister; 0 acikca girilince tamami serbest, stok degismez');

  // ---------------- D) Stok cikis korumasi ----------------
  sifirla();
  siparis(K.BAR810, [{ menu_urun_id: M.BIRA, adet: 8 }]);
  sonuc(kod(q(K.DEPO810, `select public.stok_ekle('BIRA','${BAR}','810',-5,1);`)) === 'REZERVE_STOK' && stok('BIRA') === '10.000',
    'D1a bar yetkisi olmayan depo kullanicisi rezerve stogu TUKETEMEZ (ONCE-3 tersi)');
  sonuc(q(K.DEPO810, `select public.stok_ekle('BIRA','${BAR}','810',-2,1);`).ok && stok('BIRA') === '8.000',
    'D1b rezerve disi miktar (2) cikabilir');
  sonuc(kod(q(K.DEPO810, `select public.stok_transfer('BIRA','${BAR}','810_100','810',1);`)) === 'REZERVE_STOK',
    'D2 rezerve stoktan transfer REDDEDILIR');
  const d3 = q(K.DEPO810, `select public.stok_ekle('LIMON','${BAR}','810',-5,1);`);
  sonuc(d3.ok && stok('LIMON') === '45.000'
     && !/2026-07-09/.test(tek(`select guncelleme_tarihi::text from public.stok where urun_kodu='LIMON' and depo_kodu='${BAR}';`)),
    'D3 rezervasyonsuz kalemde davranis ayni; tarih yazildi');
  sifirla();
  O.sql(`update public.stok set miktar = 3 where urun_kodu='BIRA' and depo_kodu='${BAR}';`);
  const y1 = O.paralel(K.BAR810, `select public.bar_siparis_olustur('810','${BAR}','M1',null,${kalemler([{ menu_urun_id: M.BIRA, adet: 2 }])}); select pg_sleep(2);`);
  await new Promise((r) => setTimeout(r, 700));
  const y2 = O.paralel(K.BAR810, `select public.bar_siparis_olustur('810','${BAR}','M2',null,${kalemler([{ menu_urun_id: M.BIRA, adet: 2 }])});`);
  const [yr1, yr2] = await Promise.all([y1, y2]);
  sonuc(yr1.ok && !yr2.ok && hataKodu(yr2) === 'YETERSIZ_STOK'
     && tek(`select sum(miktar)::text from public.stok_rezervasyonlari where durum='aktif';`) === '2.000',
    'D4 ayni son birimler icin eszamanli iki siparis: yalniz biri gecer');

  // ---------------- E) Sayim (T25, O14, O15) ----------------
  sifirla();
  siparis(K.BAR810, [{ menu_urun_id: M.BIRA, adet: 8 }]);            // BIRA: stok 10, rezerve 8
  O.sql(`insert into public.sayim_oturumlari (id, depo_kodu, otel_id, olusturan_ad, durum)
           values ('99999999-0000-0000-0000-000000000001','${BAR}','810','Test','onay_bekliyor');
         insert into public.sayim_detaylari (id, oturum_id, urun_kodu, urun_adi, sistem_miktar, sayilan_miktar, fark) values
           ('99999999-0000-0000-0000-0000000000b1','99999999-0000-0000-0000-000000000001','BIRA','Bira',10,5,-5),
           ('99999999-0000-0000-0000-0000000000b2','99999999-0000-0000-0000-000000000001','VISKI','Viski',2,3,1),
           ('99999999-0000-0000-0000-0000000000b3','99999999-0000-0000-0000-000000000001','LIMON','Limon',50,50,0);`);
  const e1 = q(K.COST810, `select public.stok_sayim_onayla('99999999-0000-0000-0000-000000000001');`);
  const e1d = tek(`select string_agg(urun_kodu||':'||uygulama_durumu, ',' order by urun_kodu) from public.sayim_detaylari;`);
  const e1o = tek(`select durum||'|'||kismi_uygulandi from public.sayim_oturumlari;`);
  const e1b = tek(`select fark::text||'|'||onay_anindaki_stok::text||'|'||onay_anindaki_rezerve::text from public.stok_sayim_bekleyenleri;`);
  sonuc(e1.ok && e1d === 'BIRA:bekliyor,LIMON:fark_yok,VISKI:uygulandi' && e1o === 'onaylandi|true'
     && stok('BIRA') === '10.000' && stok('VISKI') === '3.000' && e1b === '-5.000|10.000|8.000'
     && /"bekleyen": 1/.test(e1.out) && /"kismi": true/.test(e1.out),
    'E1 sayim: celisen kalem BEKLER (gozlem saklandi), digerleri uygulandi; KISMI uygulama isaretli ve kalem bazinda donduruldu',
    e1d + ' | ' + e1o);
  sonuc(tek(`select count(*) from public.stok_hareketleri where aciklama like 'sayim%';`) === '1',
    'E1b yalniz uygulanan kalem icin sayim hareketi yazildi');
  const bekId = tek(`select id from public.stok_sayim_bekleyenleri;`);
  sonuc(kod(q(K.DEPO810, `select public.stok_sayim_bekleyen_uygula('${bekId}');`)) === 'YETKI_YOK',
    'E2 bekleyeni uygulamak icin stok_takip TAM gerekir');
  sonuc(kod(q(K.DEPOSEF810, `select public.stok_sayim_bekleyen_uygula('${bekId}');`)) === 'REZERVE_STOK',
    'E3 celiski surerken uygulama REDDEDILIR');
  // Aradaki hareket: +20 giris (mal kabul gibi). Rezervasyon hala 8.
  q(K.DEPO810, `select public.stok_ekle('BIRA','${BAR}','810',20,1);`);           // stok 30
  const e4 = q(K.DEPOSEF810, `select public.stok_sayim_bekleyen_uygula('${bekId}');`);
  sonuc(e4.ok && stok('BIRA') === '25.000' && /"onceki_stok": 30/.test(e4.out)
     && tek(`select kismi_uygulandi::text from public.sayim_oturumlari;`) === 'false'
     && tek(`select uygulama_durumu from public.sayim_detaylari where urun_kodu='BIRA';`) === 'sonradan_uygulandi',
    'E4 bekleyen DELTA olarak uygulandi: 30 + (-5) = 25 — aradaki +20 korundu, sayilan 5 USTUNE YAZILMADI', 'stok ' + stok('BIRA'));
  sonuc(!/2026-07-09/.test(tek(`select guncelleme_tarihi::text from public.stok where urun_kodu='BIRA' and depo_kodu='${BAR}';`)),
    'E5 sayim uygulamasi stok tarihini yazdi (3.5.1)');
  // Eksik kaydedilmis oturum: 3 urun bildirildi, 1 detay var -> tek satir yazmadan durur.
  O.sql(`insert into public.sayim_oturumlari (id, depo_kodu, otel_id, olusturan_ad, durum, toplam_urun_sayisi)
           values ('99999999-0000-0000-0000-000000000002','${BAR}','810','Test','onay_bekliyor',3);
         insert into public.sayim_detaylari (id, oturum_id, urun_kodu, urun_adi, sistem_miktar, sayilan_miktar, fark) values
           ('99999999-0000-0000-0000-0000000000c1','99999999-0000-0000-0000-000000000002','VISKI','Viski',3,9,6);`);
  const e6 = q(K.COST810, `select public.stok_sayim_onayla('99999999-0000-0000-0000-000000000002');`);
  sonuc(kod(e6) === 'SAYIM_EKSIK' && stok('VISKI') === '3.000'
     && tek(`select durum from public.sayim_oturumlari where id='99999999-0000-0000-0000-000000000002';`) === 'onay_bekliyor',
    'E6 eksik kaydedilmis sayim onaylanmaz (SAYIM_EKSIK); stok ve oturum degismedi', e6.out);
  O.sql(`insert into public.sayim_oturumlari (id, depo_kodu, otel_id, olusturan_ad, durum)
           values ('99999999-0000-0000-0000-000000000003','${BAR}','810','Test','onay_bekliyor');`);
  sonuc(kod(q(K.COST810, `select public.stok_sayim_onayla('99999999-0000-0000-0000-000000000003');`)) === 'SAYIM_EKSIK',
    'E6b detay satiri olmayan oturum onaylanmaz (SAYIM_EKSIK)');

  // ---- Kullanici senaryosu (karar 3): sayim aninda 100, fiziksel 90, arada cikis 20 -> 70 ----
  const oturumKur = (id, sistem, sayilan) => O.sql(`
    insert into public.sayim_oturumlari (id, depo_kodu, otel_id, olusturan_ad, durum, toplam_urun_sayisi)
      values ('${id}','${BAR}','810','Test','onay_bekliyor',1);
    insert into public.sayim_detaylari (oturum_id, urun_kodu, urun_adi, sistem_miktar, sayilan_miktar, fark)
      values ('${id}','BIRA','Bira',${sistem},${sayilan},${sayilan - sistem});`);
  const sayimHareketi = () => tek(`select count(*) from public.stok_hareketleri where aciklama like 'sayim%';`);
  const onayla = (id, kim = K.COST810) => q(kim, `select public.stok_sayim_onayla('${id}');`);
  const OT = (n) => '99999999-0000-0000-0000-' + String(n).padStart(12, '0');

  sifirla();
  O.sql(`update public.stok set miktar = 100 where urun_kodu='BIRA' and depo_kodu='${BAR}';`);
  oturumKur(OT('e7'), 100, 90);                                           // sayim aninda sistem 100, fiziksel 90
  q(K.DEPO810, `select public.stok_ekle('BIRA','${BAR}','810',-20,1);`);   // sayimdan sonra cikis 20 -> 80
  const e7 = onayla(OT('e7'));
  sonuc(e7.ok && stok('BIRA') === '70.000' && sayimHareketi() === '1'
     && tek(`select uygulama_durumu from public.sayim_detaylari where oturum_id='${OT('e7')}';`) === 'uygulandi',
    'E7 100 -> fiziksel 90 -> arada cikis 20 -> onay sonrasi 70: fark SAYIM ANINDAKI stoga gore (-10), cikis korundu', 'stok ' + stok('BIRA'));
  const e8 = onayla(OT('e7'));
  sonuc(/zaten_onaylandi/.test(e8.out) && stok('BIRA') === '70.000' && sayimHareketi() === '1',
    'E8 ayni sayim ikinci kez onaylanamaz: zaten_onaylandi, stok 70, tek sayim hareketi');
  oturumKur(OT('e9'), 70, 65);
  const [e9a, e9b] = await Promise.all([
    O.paralel(K.COST810, `select public.stok_sayim_onayla('${OT('e9')}'); select pg_sleep(2);`),
    new Promise((r) => setTimeout(r, 700)).then(() => O.paralel(K.COST810, `select public.stok_sayim_onayla('${OT('e9')}');`)),
  ]);
  sonuc(e9a.ok && e9b.ok && /zaten_onaylandi/.test(e9b.out) && stok('BIRA') === '65.000' && sayimHareketi() === '2',
    'E9 ayni sayimin ESZAMANLI iki onayi: fark bir kez uygulandi (70 -> 65)', 'stok ' + stok('BIRA'));

  // Ayni senaryo, rezervasyonla celisen yol: duzeltme bekler, sonra delta uygulanir.
  sifirla();
  O.sql(`update public.stok set miktar = 100 where urun_kodu='BIRA' and depo_kodu='${BAR}';`);
  oturumKur(OT('e10'), 100, 90);
  const rezSip = siparis(K.BAR810, [{ menu_urun_id: M.BIRA, adet: 75 }]).out;           // 75 rezerve
  q(K.DEPO810, `select public.stok_ekle('BIRA','${BAR}','810',-20,1);`);                  // 100 -> 80 (rezerve disi 25)
  const e10 = onayla(OT('e10'));
  sonuc(e10.ok && /"bekleyen": 1/.test(e10.out) && stok('BIRA') === '80.000'
     && tek(`select fark::text||'|'||onay_anindaki_stok::text from public.stok_sayim_bekleyenleri;`) === '-10.000|80.000',
    'E10 rezervasyonla celisen duzeltme BEKLER: 80 - 10 = 70 < 75 rezerve; stok 80, bekleyen fark -10',
    'stok ' + stok('BIRA') + ' rez ' + tek(`select coalesce(sum(miktar),0)::text from public.stok_rezervasyonlari where durum='aktif';`) + ' | ' + (e10.out || e10.err).slice(0, 200));
  q(K.BAR810, `select public.bar_siparis_iptal('${rezSip}', 'Test: rezervasyon kalkti');`);
  const bek = tek(`select id from public.stok_sayim_bekleyenleri;`);
  const [u1, u2] = await Promise.all([
    O.paralel(K.DEPOSEF810, `select public.stok_sayim_bekleyen_uygula('${bek}'); select pg_sleep(2);`),
    new Promise((r) => setTimeout(r, 700)).then(() => O.paralel(K.DEPOSEF810, `select public.stok_sayim_bekleyen_uygula('${bek}');`)),
  ]);
  const u3 = q(K.DEPOSEF810, `select public.stok_sayim_bekleyen_uygula('${bek}');`);
  sonuc(u1.ok && u2.ok && /zaten_uygulandi/.test(u2.out) && /zaten_uygulandi/.test(u3.out)
     && stok('BIRA') === '70.000' && sayimHareketi() === '1',
    'E11 bekleyen duzeltme 80 -> 70 uygulandi; eszamanli ikinci ve sonraki ucuncu deneme uygulanmadi', 'stok ' + stok('BIRA'));

  // ---- Eski sayim istemcisi sunucuda durdurulur (15b) ----
  const GORUNTU = { rol: 'authenticated', sub: '11111111-0000-0000-0000-0000000000bb' };   // bar goruntule, stok yetkisi YOK
  const e12 = q(K.DEPO810, `select count(*) from public.sayim_detaylari;`);
  sonuc(!e12.ok && /permission denied/.test(e12.err),
    'E12 sayim_detaylari DOGRUDAN okunamaz (eski istemci detay okuyamaz, yazmadan durur)', e12.err.split('\n')[0]);
  oturumKur(OT('e13'), 70, 60);
  O.sql(`insert into public.sayim_oturumlari (id, depo_kodu, otel_id, olusturan_ad, durum, toplam_urun_sayisi)
           values ('${OT('e14')}','811_CSM302','811','Test','onay_bekliyor',0);`);
  const e13 = q(K.DEPO810, `select count(*) from public.stok_sayim_detaylari('${OT('e13')}');`);
  sonuc(e13.ok && e13.out.split('\n').pop() === '1'
     && kod(q(GORUNTU, `select * from public.stok_sayim_detaylari('${OT('e13')}');`)) === 'YETKI_YOK'
     && kod(q(K.DEPO810, `select * from public.stok_sayim_detaylari('${OT('e14')}');`)) === 'OTEL_ERISIMI_YOK'
     && kod(q(K.ANON, `select * from public.stok_sayim_detaylari('${OT('e13')}');`)) !== 'OK',
    'E13 detaylar RPC ile okunur: stok kayit yetkili kendi otelinde okur; stok yetkisiz, baska otel ve anon REDDEDILIR',
    [e13.out || e13.err, kod(q(GORUNTU, `select * from public.stok_sayim_detaylari('${OT('e13')}');`)), kod(q(K.DEPO810, `select * from public.stok_sayim_detaylari('${OT('e14')}');`)), kod(q(K.ANON, `select * from public.stok_sayim_detaylari('${OT('e13')}');`))].join(' | '));
  const e14a = O.sql(`update public.sayim_oturumlari set durum = 'onaylandi' where id = '${OT('e13')}';`);
  const e14b = O.sql(`update public.sayim_oturumlari set kismi_uygulandi = true where id = '${OT('e13')}';`);
  const e14c = O.sql(`insert into public.sayim_oturumlari (depo_kodu, otel_id, olusturan_ad, durum) values ('${BAR}','810','x','onaylandi');`);
  sonuc(kod(e14a) === 'SAYIM_ONAYI_SUNUCUDA' && kod(e14b) === 'SAYIM_ONAYI_SUNUCUDA' && kod(e14c) === 'SAYIM_ONAYI_SUNUCUDA'
     && tek(`select durum from public.sayim_oturumlari where id='${OT('e13')}';`) === 'onay_bekliyor',
    'E14 sayim onay durumu / kismi bayrak sunucu fonksiyonu disinda (sahip rolde bile) degistirilemez');
  const e15 = onayla(OT('e13'));
  sonuc(e15.ok && tek(`select durum from public.sayim_oturumlari where id='${OT('e13')}';`) === 'onaylandi'
     && O.sql(`update public.sayim_oturumlari set olusturan_ad = 'duzeltme' where id = '${OT('e13')}';`).ok,
    'E15 sunucu onayi calisir; onayla ilgisiz alan guncellemesi engellenmez');

  // ---- Yazma yolunda istemci ayrimi (2026-09-19; gecis provasi G12) ----
  const once16 = stok('BIRA');
  const e16a = q(K.DEPO810, `select public.stok_ekle('BIRA','${BAR}','810',10);`);
  const e16b = q(K.DEPO810, `select public.stok_ekle('BIRA','${BAR}','810',10,0);`);
  sonuc(kod(e16a) === 'ESKI_ISTEMCI' && kod(e16b) === 'ESKI_ISTEMCI' && stok('BIRA') === once16,
    'E16 A1 sonrasi 4 parametreli (eski istemci) ve nesli gecersiz stok_ekle HICBIR SEY YAZMAZ: ESKI_ISTEMCI', 'stok ' + stok('BIRA'));
  const e16c = q(K.DEPO810, `select public.stok_ekle('BIRA','${BAR}','810',10,1);`);
  sonuc(e16c.ok && Number(stok('BIRA')) === Number(once16) + 10, 'E16b yeni istemci (nesil 1) yazar');
  const hareket = (acik) => q(K.DEPO810, `insert into public.stok_hareketleri (urun_kodu, depo_kodu, otel_id, tip, miktar, aciklama)
                                           values ('BIRA','${BAR}','810','giris',1,${acik === null ? 'null' : `'${acik}'`});`);
  const e17a = hareket('sayim');
  const e17b = hareket('sayim — Fiziksel sayım düzeltmesi');
  const e17c = hareket('Mal kabul');
  sonuc(kod(e17a) === 'SAYIM_ONAYI_SUNUCUDA' && kod(e17b) === 'SAYIM_ONAYI_SUNUCUDA' && e17c.ok,
    'E17 sunucu disindan "sayim" aciklamali hareket REDDEDILIR; diger dogrudan hareketler etkilenmez',
    [kod(e17a), kod(e17b), kod(e17c)].join(' | '));

  // E18: 5. parametre UYUMLULUK ayrimidir, YETKI KAPISI DEGIL. Yeni imza mevcut
  // kullanici / otel / stok kontrollerini bagimsiz uygular (SECURITY INVOKER + RLS
  // + rezervasyon korumasi). Nesil 1 vermek hicbir kontrolu atlatmaz.
  const e18Once = stok('BIRA');
  const e18anon = q(K.ANON, `select public.stok_ekle('BIRA','${BAR}','810',5,1);`);
  const e18yetkisiz = q(GORUNTU, `select public.stok_ekle('BIRA','${BAR}','810',5,1);`);   // stok yetkisi YOK
  const e18pasif = q(K.PASIF, `select public.stok_ekle('BIRA','${BAR}','810',5,1);`);
  const e18baskaOtel = q(K.DEPO810, `select public.stok_ekle('BIRA','811_CSM302','811',5,1);`);  // otel 811
  const e18tanim = tek(`select string_agg(p.oid::regprocedure::text || '=' || p.prosecdef::text, ',' order by 1)
                          from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'stok_ekle';`);
  sonuc(!e18anon.ok && !e18yetkisiz.ok && !e18pasif.ok && !e18baskaOtel.ok
     && stok('BIRA') === e18Once
     && tek(`select coalesce(miktar::text,'yok') from public.stok where urun_kodu='BIRA' and depo_kodu='811_CSM302';`) !== '5.000'
     && e18tanim === 'stok_ekle(text,text,text,numeric)=false,stok_ekle(text,text,text,numeric,integer)=false',
    'E18 nesil 1 ile bile: anon, stok yetkisiz, pasif ve BASKA OTEL yazamaz; iki imza da SECURITY DEFINER degil (kontroller bagimsiz)',
    [kod(e18anon), kod(e18yetkisiz), kod(e18pasif), kod(e18baskaOtel)].join(' | '));
  // Rezervasyon korumasi da 5 parametreli yolda aynen isler (D1/D2 ile ayni kural).
  sifirla();
  siparis(K.BAR810, [{ menu_urun_id: M.BIRA, adet: 8 }]);
  sonuc(kod(q(K.DEPO810, `select public.stok_ekle('BIRA','${BAR}','810',-5,1);`)) === 'REZERVE_STOK' && stok('BIRA') === '10.000',
    'E18b yeni imza rezervasyon korumasini da uygular (nesil parametresi kontrolu atlatmaz)');

  // ---------------- F) Guvenlik yuzeyi ----------------
  const anonAcik = tek(`select count(*) from pg_proc p where p.pronamespace='public'::regnamespace
    and (p.proname like 'bar\\_%' or p.proname like 'stok\\_sayim\\_%' or p.proname in ('stok_ekle','stok_transfer','stok_cikis_korumasi'))
    and has_function_privilege('anon', p.oid, 'EXECUTE');`);
  const icAcik = tek(`select count(*) from pg_proc p where p.pronamespace='public'::regnamespace
    and (p.proname like '\\_bar\\_%' or p.proname like '\\_stok\\_%')
    and (has_function_privilege('authenticated', p.oid, 'EXECUTE') or has_function_privilege('service_role', p.oid, 'EXECUTE'));`);
  sonuc(anonAcik === '0' && icAcik === '0', 'F1 anon hicbir A1 RPCsini, authenticated/service_role hicbir ic yardimciyi cagiramaz',
    `anon ${anonAcik}, ic ${icAcik}`);
  const kap = (kim) => q(kim, `select public.bar_masa_yetki_kapsami()::text;`).out;
  sonuc(/"yetkili": true/.test(kap(K.BAR810)) && /\["810"\]/.test(kap(K.BAR810))
     && /"yetkili": false/.test(kap(K.PASIF)) && /"yetkili": false/.test(kap(K.DEPO810)) && /"oteller": \[\]/.test(kap(K.PASIF)),
    'F2 masa yetki kapsami: bar personeli yalniz kendi oteli; pasif ve bar yetkisizler yetkisiz');
  sifirla();
  const f3 = siparis(K.BAR810, [{ menu_urun_id: M.BIRA, adet: 1 }]);
  hazirla(f3.out);
  q(K.BAR810, `select public.bar_siparis_teslim_et('${f3.out}');`);
  sonuc(kod(O.sql(`update public.bar_stok_tuketimleri set miktar = 99;`)) === 'DEGISMEZ_KAYIT'
     && kod(O.sql(`delete from public.bar_stok_tuketimleri;`)) === 'DEGISMEZ_KAYIT',
    'F3 tuketim kaydi degistirilemez/silinemez (sahip rolde bile)');
} catch (e) {
  sonuc(false, 'beklenmeyen hata', e.stack || e.message);
} finally {
  O.temizle();
}
console.log(`\nBAR A1 VERITABANI: ${ok} OK / ${fail} FAIL`);
process.exitCode = fail ? 1 : 0;
