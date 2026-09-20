// ===========================================================================
// KESINTI UZLASTIRMA PROVASI — IZOLE (uretime BAGLANMAZ)
// ===========================================================================
// Yayin penceresinde yazma duraklatmasi cok adimli bir islemi YARIDA kesebilir.
// Bu prova, kesilmis islemleri izole ortamda BILEREK uretir ve
// docs/kurulum/2026-09-20-kesinti-uzlastirma.sql prosedurunun her birini
// yakalayip 'BELIRSIZ' olarak isaretledigini, temiz durumda ise
// 'YENIDEN ACMA: EVET' dedigini olcer.
//
// Kesinti desenleri (ekranlarin gercek yazma sirasina gore):
//   P1 stok yazildi, hareket yazilmadi        (mal kabul / transfer / elle)
//   P2 mal kabul onaylandi, kalem islenmedi   (stok da degismemis)
//   P3 siparis kapandi, rezervasyon aktif kaldi
//   P4 rezervasyon kullanildi, tuketim kaydi yok
//   P5 aktif rezervasyon stoktan fazla
//   P6 sayim oturumu var, detay yok
//   P7 negatif stok
// ===========================================================================
import { barOrtami } from './bar-test-ortam.mjs';

const A1 = 'docs/kurulum/2026-09-18-bar-a1-guvenlik.sql';
const UZL = 'docs/kurulum/2026-09-20-kesinti-uzlastirma.sql';
const DEPO = '810_CSM302';

const O = barOrtami({ ad: 'kesinti-uzl' });
let ok = 0, fail = 0;
const sonuc = (g, ad, ek) => { console.log((g ? 'OK   ' : 'FAIL ') + ad + (ek ? ' — ' + ek : '')); if (g) ok++; else fail++; };

const sql = (q) => { const r = O.sql(q); if (!r.ok) throw new Error(r.err.slice(-400)); return r.out; };
// Tetikleyici/denetim katmani tohumlamayi engellemesin: replica rolunde yazilir.
const tohum = (q) => sql(`set session_replication_role = replica;\n${q}\nset session_replication_role = origin;`);

function uzlastir() {
  const r = O.uygulaTekIslem(UZL);
  if (!r.ok) throw new Error('uzlastirma calismadi: ' + r.err.slice(-400));
  return r.out;
}
const belirsizSayisi = (cikti) => {
  const m = /YENIDEN ACMA: (EVET|HAYIR)[^\n|]*\|\s*(\d+)/.exec(cikti.replace(/\s*\|\s*/g, ' | '));
  return m ? { karar: m[1], n: Number(m[2]) } : { karar: '?', n: -1 };
};
const icerir = (cikti, parca) => cikti.includes(parca);

try {
  await O.kur();
  const a = O.uygulaTekIslem(A1);
  sonuc(a.ok, 'Taban: A1 migration uygulandi', a.ok ? '' : a.err.split('\n').slice(-4).join(' | '));
  if (!a.ok) throw new Error('A1 uygulanamadi');

  // ---------------- T0: temiz durum ----------------
  // Tohum verisi test ANINDA yazildigi icin tum stok satirlari kesinti
  // penceresinin (son 2 saat) icinde gorunur ve hareketleri yoktur. Bu, olcmek
  // istedigimiz kesinti degil kurulum gurultusudur: taban satirlari geriye
  // alinir, boylece pencerede yalnizca provanin urettigi kesintiler kalir.
  tohum(`update public.stok set guncelleme_tarihi = now() - interval '1 day';`);
  let c = uzlastir();
  let k = belirsizSayisi(c);
  sonuc(k.karar === 'EVET' && k.n === 0, 'K0 TEMIZ durum: "YENIDEN ACMA: EVET"', JSON.stringify(k));

  // ---------------- P1: stok yazildi, hareket yazilmadi ----------------
  tohum(`update public.stok set miktar = miktar + 5, guncelleme_tarihi = now()
          where depo_kodu = '${DEPO}' and urun_kodu = 'BIRA';`);
  c = uzlastir(); k = belirsizSayisi(c);
  sonuc(k.karar === 'HAYIR' && icerir(c, 'U2 stok/hareket'),
    'K1 P1 yakalandi: stok pencerede degismis, eslesen hareket yok', JSON.stringify(k));

  // Hareket de yazilirsa satir KESIN olmali (yanlis alarm kontrolu)
  tohum(`insert into public.stok_hareketleri (urun_kodu, depo_kodu, otel_id, tip, miktar, tarih, aciklama, belge_no)
         values ('BIRA', '${DEPO}', '810', 'giris', 5, now(), 'prova', 'PROVA-1');`);
  c = uzlastir(); k = belirsizSayisi(c);
  sonuc(k.karar === 'EVET' && k.n === 0, 'K2 P1 cozumlendi: hareket yazilinca satir KESIN oluyor', JSON.stringify(k));

  // ---------------- P3: kapanmis siparisin rezervasyonu aktif ----------------
  const sip = sql(`select gen_random_uuid();`);
  const kalem = sql(`select gen_random_uuid();`);
  tohum(`insert into public.bar_siparisleri (id, otel_id, depo_id, masa_token, kanal, durum, oda_dogrulama_durumu)
           values ('${sip}', '810', '${DEPO}', 'PROVA', 'personel', 'iptal', 'gerekmiyor');
         insert into public.bar_siparis_kalemleri (id, siparis_id, menu_urun_id, adet, rezerve_edildi, birim_fiyat, ucretli)
           values ('${kalem}', '${sip}', '22222222-0000-0000-0000-000000000001', 1, true, 0, false);
         insert into public.stok_rezervasyonlari (stok_kodu, otel_id, depo_id, miktar, siparis_kalem_id, durum)
           values ('BIRA', '810', '${DEPO}', 1, '${kalem}', 'aktif');`);
  c = uzlastir(); k = belirsizSayisi(c);
  sonuc(k.karar === 'HAYIR' && icerir(c, 'U3a rezervasyon'),
    'K3 P3 yakalandi: kapanmis siparisin rezervasyonu serbest birakilmamis', JSON.stringify(k));
  tohum(`update public.stok_rezervasyonlari set durum = 'serbest' where siparis_kalem_id = '${kalem}';`);

  // ---------------- P4: rezervasyon kullanildi, tuketim yok ----------------
  tohum(`update public.stok_rezervasyonlari set durum = 'kullanildi' where siparis_kalem_id = '${kalem}';`);
  c = uzlastir(); k = belirsizSayisi(c);
  sonuc(k.karar === 'HAYIR' && icerir(c, 'U3b rezervasyon'),
    'K4 P4 yakalandi: kullanilmis rezervasyonun tuketim kaydi yok', JSON.stringify(k));

  // ---------------- P4b: teslim edilmis kalemin tuketimi yok ----------------
  tohum(`update public.bar_siparisleri set durum = 'teslim_edildi' where id = '${sip}';`);
  c = uzlastir();
  sonuc(icerir(c, 'U3c siparis'), 'K5 teslim edilmis kalemin tuketimi yok — yakalandi');
  tohum(`delete from public.stok_rezervasyonlari where siparis_kalem_id = '${kalem}';
         delete from public.bar_siparis_kalemleri where id = '${kalem}';
         delete from public.bar_siparisleri where id = '${sip}';`);

  // ---------------- P5: aktif rezervasyon stoktan fazla ----------------
  const sip2 = sql(`select gen_random_uuid();`);
  const kalem2 = sql(`select gen_random_uuid();`);
  tohum(`insert into public.bar_siparisleri (id, otel_id, depo_id, masa_token, kanal, durum, oda_dogrulama_durumu)
           values ('${sip2}', '810', '${DEPO}', 'PROVA2', 'personel', 'yeni', 'gerekmiyor');
         insert into public.bar_siparis_kalemleri (id, siparis_id, menu_urun_id, adet, rezerve_edildi, birim_fiyat, ucretli)
           values ('${kalem2}', '${sip2}', '22222222-0000-0000-0000-000000000001', 1, true, 0, false);
         insert into public.stok_rezervasyonlari (stok_kodu, otel_id, depo_id, miktar, siparis_kalem_id, durum)
           values ('BIRA', '810', '${DEPO}', 9999, '${kalem2}', 'aktif');`);
  c = uzlastir(); k = belirsizSayisi(c);
  sonuc(k.karar === 'HAYIR' && icerir(c, 'U4 rezerve/stok'),
    'K6 P5 yakalandi: aktif rezervasyon stoktan fazla', JSON.stringify(k));
  tohum(`delete from public.stok_rezervasyonlari where siparis_kalem_id = '${kalem2}';
         delete from public.bar_siparis_kalemleri where id = '${kalem2}';
         delete from public.bar_siparisleri where id = '${sip2}';`);

  // ---------------- P6: sayim oturumu var, detay yok ----------------
  const ot = sql(`select gen_random_uuid();`);
  tohum(`insert into public.sayim_oturumlari (id, depo_kodu, otel_id, olusturan_ad, durum, toplam_urun_sayisi, farkli_urun_sayisi)
         values ('${ot}', '${DEPO}', '810', 'Prova', 'onay_bekliyor', 3, 1);`);
  c = uzlastir(); k = belirsizSayisi(c);
  sonuc(k.karar === 'HAYIR' && icerir(c, 'U5a sayim'),
    'K7 P6 yakalandi: sayim oturumu var, detay satiri yok', JSON.stringify(k));
  tohum(`delete from public.sayim_oturumlari where id = '${ot}';`);

  // ---------------- P7: negatif stok ----------------
  tohum(`update public.stok set miktar = -3 where depo_kodu = '${DEPO}' and urun_kodu = 'LIMON';`);
  c = uzlastir(); k = belirsizSayisi(c);
  sonuc(k.karar === 'HAYIR' && icerir(c, 'U6 negatif stok'), 'K8 P7 yakalandi: negatif stok', JSON.stringify(k));

  // ---------------- Kapanis: hepsi cozumlenince yeniden acilabilir ----------------
  tohum(`update public.stok set miktar = 50 where depo_kodu = '${DEPO}' and urun_kodu = 'LIMON';
         insert into public.stok_hareketleri (urun_kodu, depo_kodu, otel_id, tip, miktar, tarih, aciklama, belge_no)
           values ('LIMON', '${DEPO}', '810', 'giris', 53, now(), 'prova duzeltme', 'PROVA-2');`);
  c = uzlastir(); k = belirsizSayisi(c);
  sonuc(k.karar === 'EVET' && k.n === 0,
    'K9 Tum belirsizlikler cozumlenince "YENIDEN ACMA: EVET"', JSON.stringify(k));

  // ---------------- Prosedur salt okuma mi? ----------------
  const once = sql(`select count(*) from public.stok_hareketleri;`);
  uzlastir();
  sonuc(sql(`select count(*) from public.stok_hareketleri;`) === once,
    'K10 Prosedur hicbir sey yazmiyor (salt okuma)');
} catch (e) {
  sonuc(false, 'beklenmeyen hata', String(e && e.message || e));
} finally {
  O.temizle();
}
console.log(`\nKESINTI UZLASTIRMA PROVASI: ${ok} OK / ${fail} FAIL`);
process.exit(fail ? 1 : 0);
