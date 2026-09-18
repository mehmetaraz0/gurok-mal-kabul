// ===========================================================================
// BAR A1 — ONCE OLCUMU (uretime BAGLANMAZ)
// ===========================================================================
// A1'in duzeltecegi her kusur, BUGUNKU uretim koduna (dokum + uretim-sonrasi
// migration'lar) karsi olculur. Kusur VARSA test GECER: bu dosya "neyi
// duzelttigimizi" kanitlar. A1 uygulanmis tabanda ayni senaryolar
// scripts/bar-a1-guvenlik.test.mjs icinde TERS yonde olculur.
//
// Kimlikler (bar-test-tohum.sql): BAR810 bar sefi 810 · DEPO810 depo elemani
// 810 (bar yetkisi yok) · QR = service_role (auth.uid bos; musteri QR akisi).
// ===========================================================================
import { barOrtami, hataKodu } from './bar-test-ortam.mjs';

const O = barOrtami({ ad: 'bar-a1-once' });
let ok = 0, fail = 0;
const sonuc = (g, ad, ek) => { console.log((g ? 'OK   ' : 'FAIL ') + ad + (ek ? ' — ' + ek : '')); if (g) ok++; else fail++; };

const BAR810 = { rol: 'authenticated', sub: '11111111-0000-0000-0000-000000000810' };
const DEPO810 = { rol: 'authenticated', sub: '11111111-0000-0000-0000-0000000000cc' };
const QR = { rol: 'service_role' };
const M = { BIRA: '22222222-0000-0000-0000-000000000001', VISKI: '22222222-0000-0000-0000-000000000002',
  LIMONATA: '22222222-0000-0000-0000-000000000003' };
const BAR = '810_CSM302';

const kalem = (menu, adet) => `'[{"menu_urun_id":"${menu}","adet":${adet}}]'::jsonb`;
const siparis = (kim, menu, adet, oda = null, depo = BAR) =>
  O.kimlikle(kim, `select public.bar_siparis_olustur('810','${depo}','M1',${oda ? `'${oda}'` : 'null'},${kalem(menu, adet)});`);
const stok = (kod) => O.sql(`select miktar::text from public.stok where urun_kodu='${kod}' and depo_kodu='${BAR}';`).out;
const sifirla = () => O.sql(`
  set session_replication_role = replica;
  delete from public.pms_folio_hareketleri; delete from public.stok_rezervasyonlari;
  delete from public.bar_siparis_kalemleri; delete from public.bar_siparisleri;
  update public.stok set miktar = case urun_kodu when 'BIRA' then 10 when 'VISKI' then 2 else miktar end
   where depo_kodu = '${BAR}';
  update public.menu_urunler set fiyat = 250 where id = '${M.VISKI}';
  set session_replication_role = origin;`);

try {
  await O.kur();

  // 1) Oda numarasiz ucretli QR siparisi
  sifirla();
  const s1 = siparis(QR, M.VISKI, 1, null);
  sonuc(s1.ok, 'ONCE-1 ucretli QR siparisi oda numarasi OLMADAN olusuyor', s1.ok ? 'siparis olustu' : s1.err.slice(-120));

  // 2) Garson ucretli siparisi dogrulama olmadan hazirlaniyor
  sifirla();
  const s2 = siparis(BAR810, M.VISKI, 1, '101');
  const h2 = s2.ok && O.kimlikle(BAR810, `select public.bar_siparis_durum_guncelle('${s2.out}','hazirlaniyor');`);
  sonuc(s2.ok && h2.ok, 'ONCE-2 garson ucretli siparisi personel dogrulamasi OLMADAN hazirlanabiliyor');

  // 3) Rezerve stok baska cikisla tuketiliyor (sayim da bu yoldan yazar)
  sifirla();
  siparis(BAR810, M.BIRA, 8);
  const c3 = O.kimlikle(DEPO810, `select public.stok_ekle('BIRA','${BAR}','810',-5);`);
  sonuc(c3.ok && stok('BIRA') === '5.000', 'ONCE-3 depo cikisi 8 rezerveli stogu 5e dusurebiliyor (rezervasyon korunmuyor)',
    'stok 10 -> ' + stok('BIRA'));

  // 4) Eszamanli cift teslim cift stok dusuyor
  sifirla();
  const s4 = siparis(BAR810, M.BIRA, 2);
  O.kimlikle(BAR810, `select public.bar_siparis_durum_guncelle('${s4.out}','hazirlaniyor');
                      select public.bar_siparis_durum_guncelle('${s4.out}','hazir');`);
  const t1 = O.paralel(BAR810, `select public.bar_siparis_teslim_et('${s4.out}'); select pg_sleep(2);`);
  await new Promise((r) => setTimeout(r, 700));
  const t2 = O.paralel(BAR810, `select public.bar_siparis_teslim_et('${s4.out}');`);
  const [r1, r2] = await Promise.all([t1, t2]);
  sonuc(r1.ok && r2.ok && stok('BIRA') === '6.000', 'ONCE-4 eszamanli iki teslim stogu IKI KEZ dusuyor (2 birimlik siparis)',
    'stok 10 -> ' + stok('BIRA'));

  // 5) Depo-otel uyusmazligi
  sifirla();
  const s5 = siparis(BAR810, M.LIMONATA, 1, null, '811_CSM302');
  sonuc(s5.ok, 'ONCE-5 810 personeli 811 deposuna siparis yazabiliyor (depo oneki dogrulanmiyor)');

  // 6) Sessiz 0'a kirpma
  sifirla();
  const s6 = siparis(BAR810, M.BIRA, 3);
  O.sql(`update public.stok set miktar = 1 where urun_kodu='BIRA' and depo_kodu='${BAR}';`);
  O.kimlikle(BAR810, `select public.bar_siparis_durum_guncelle('${s6.out}','hazirlaniyor');
                      select public.bar_siparis_durum_guncelle('${s6.out}','hazir');`);
  const t6 = O.kimlikle(BAR810, `select public.bar_siparis_teslim_et('${s6.out}');`);
  sonuc(t6.ok && stok('BIRA') === '0.000', 'ONCE-6 stok 1 iken 3 birim teslim SESSIZCE 0a kirpiliyor (hata yok)',
    'stok 1 -> ' + stok('BIRA'));

  // 7) Kapali folyoda servis edilmis urun kaybolur
  sifirla();
  const s7 = siparis(BAR810, M.VISKI, 1, '102');   // 102: folyo kapali
  O.kimlikle(BAR810, `select public.bar_siparis_durum_guncelle('${s7.out}','hazirlaniyor');
                      select public.bar_siparis_durum_guncelle('${s7.out}','hazir');`);
  const t7 = O.kimlikle(BAR810, `select public.bar_siparis_teslim_et('${s7.out}');`);
  sonuc(!t7.ok && stok('VISKI') === '2.000', 'ONCE-7 kapali folyoda teslim TUMDEN reddediliyor: servis edilen urunun stok/istisna kaydi yok',
    'teslim ' + (t7.ok ? 'gecti' : 'reddedildi') + ', VISKI stok ' + stok('VISKI'));

  // 8) Hazirlaniyor iptalinde kullanim kaybolur
  sifirla();
  const s8 = siparis(BAR810, M.BIRA, 2);
  O.kimlikle(BAR810, `select public.bar_siparis_durum_guncelle('${s8.out}','hazirlaniyor');`);
  const i8 = O.kimlikle(BAR810, `select public.bar_siparis_iptal('${s8.out}');`);
  const serbest = O.sql(`select count(*) from public.stok_rezervasyonlari where durum='serbest';`).out;
  sonuc(i8.ok && serbest === '1' && stok('BIRA') === '10.000',
    'ONCE-8 hazirlaniyor iptali tum rezervasyonu serbest birakiyor: kullanilan miktar ve nedeni kaydedilemiyor');

  // 9) Borc siparis fiyatindan degil teslim anindaki fiyattan
  sifirla();
  const s9 = siparis(BAR810, M.VISKI, 1, '101');
  O.sql(`update public.menu_urunler set fiyat = 300 where id = '${M.VISKI}';`);
  O.kimlikle(BAR810, `select public.bar_siparis_durum_guncelle('${s9.out}','hazirlaniyor');
                      select public.bar_siparis_durum_guncelle('${s9.out}','hazir');
                      select public.bar_siparis_teslim_et('${s9.out}');`);
  const borc = O.sql(`select tutar::text from public.pms_folio_hareketleri where kaynak_id = '${s9.out}';`).out;
  sonuc(borc === '300.00', 'ONCE-9 folyo borcu siparis anindaki 250 degil teslim anindaki fiyat (300)', 'borc ' + borc);
} catch (e) {
  sonuc(false, 'beklenmeyen hata', e.stack || e.message);
} finally {
  O.temizle();
}
console.log(`\nBAR A1 ONCE OLCUMU: ${ok} OK / ${fail} FAIL`);
process.exitCode = fail ? 1 : 0;
