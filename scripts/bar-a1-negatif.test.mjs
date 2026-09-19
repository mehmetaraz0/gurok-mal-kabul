// ===========================================================================
// BAR A1 — KRITIK KORUMALARIN NEGATIF KONTROLLERI (uretime BAGLANMAZ)
// ===========================================================================
// Her koruma A1 dosyasinin bir KOPYASINDA kaldirilir ve ilgili senaryo
// yeniden kosulur. Beklenen: koruma yokken kusur GERI GELIR. Gelmezse o
// korumayi olcen test (bar-a1-guvenlik.test.mjs) bos geciyor demektir.
//
//   K1a teslim FOR UPDATE kaldirilir     -> ikinci eszamanli teslim artik
//        'zaten_teslim' donmez; tuketim tekilligi (ikinci katman) cift
//        dusumu yine engeller (katmanlarin ayri ayri isi gorunur)
//   K1b FOR UPDATE + tuketim tekilligi   -> stok IKI KEZ duser
//   K2  stok cikis korumasi              -> rezerve stok baska cikisla tuketilir
//   K3  danisma kilidi                   -> son birimler icin iki siparis de gecer
//   K4  dogrudan yazma kapatmasi         -> personel durumu RPC'siz degistirir
// ===========================================================================
import { readFileSync } from 'node:fs';
import { barOrtami, hataKodu, kok } from './bar-test-ortam.mjs';

// Git calisma kopyasini CRLF cikarabilir (core.autocrlf); arama metinleri LF'tir.
// psql satir sonunu normalize ettigi icin uygulanan SQL'in anlami degismez.
const A1 = readFileSync(kok + 'docs/kurulum/2026-09-18-bar-a1-guvenlik.sql', 'utf8').replace(/\r\n/g, '\n');
const BAR = '810_CSM302';
const BAR810 = { rol: 'authenticated', sub: '11111111-0000-0000-0000-000000000810' };
const DEPO810 = { rol: 'authenticated', sub: '11111111-0000-0000-0000-0000000000cc' };
const BIRA = '22222222-0000-0000-0000-000000000001';

let ok = 0, fail = 0;
const sonuc = (g, ad, ek) => { console.log((g ? 'OK   ' : 'FAIL ') + ad + (ek ? ' — ' + ek : '')); if (g) ok++; else fail++; };

// Bolum ici degisim: yalniz [basIsaret, bitIsaret) araligindaki metin degisir.
function bolumde(metin, basIsaret, bitIsaret, eski, yeni) {
  const b = metin.indexOf(basIsaret), e = metin.indexOf(bitIsaret, b);
  if (b < 0 || e < 0) throw new Error('bolum yok: ' + basIsaret);
  const bolum = metin.slice(b, e);
  if (!bolum.includes(eski)) throw new Error('degisecek metin bolumde yok: ' + eski.slice(0, 50));
  return metin.slice(0, b) + bolum.split(eski).join(yeni) + metin.slice(e);
}
function degistir(metin, eski, yeni) {
  if (!metin.includes(eski)) throw new Error('degisecek metin yok: ' + eski.slice(0, 50));
  return metin.split(eski).join(yeni);
}

async function varyant(ad, metin, senaryo) {
  const O = barOrtami({ ad: 'bar-neg-' + ad });
  try {
    await O.kur();
    const u = O.uygulaTekIslem(metin, { metin: true });
    if (!u.ok) throw new Error('varyant uygulanamadi: ' + u.err.slice(-300));
    await senaryo(O);
  } catch (e) {
    sonuc(false, ad + ' beklenmeyen hata', e.message);
  } finally { O.temizle(); }
}

const siparis = (O, adet, masa = 'M1') => O.kimlikle(BAR810,
  `select public.bar_siparis_olustur('810','${BAR}','${masa}',null,'[{"menu_urun_id":"${BIRA}","adet":${adet}}]'::jsonb);`);
const stok = (O) => O.sql(`select miktar::text from public.stok where urun_kodu='BIRA' and depo_kodu='${BAR}';`).out;

async function eszamanliTeslim(O) {
  const s = siparis(O, 2).out;
  O.kimlikle(BAR810, `select public.bar_siparis_durum_guncelle('${s}','hazirlaniyor');
                      select public.bar_siparis_durum_guncelle('${s}','hazir');`);
  const p1 = O.paralel(BAR810, `select public.bar_siparis_teslim_et('${s}'); select pg_sleep(2);`);
  await new Promise((r) => setTimeout(r, 700));
  const p2 = O.paralel(BAR810, `select public.bar_siparis_teslim_et('${s}');`);
  const [r1, r2] = await Promise.all([p1, p2]);
  return { r1, r2, stok: stok(O) };
}

// K1a — yalniz teslimdeki FOR UPDATE kaldirilir
const K1a = bolumde(A1, '-- 11) TESLIM', '-- 12) IPTAL',
  'select * into v_s from public.bar_siparisleri where id = p_siparis_id for update;',
  'select * into v_s from public.bar_siparisleri where id = p_siparis_id;');
await varyant('K1a', K1a, async (O) => {
  const r = await eszamanliTeslim(O);
  sonuc(!(r.r2.ok && /zaten_teslim/.test(r.r2.out)) && r.stok === '8.000',
    'K1a FOR UPDATE yokken ikinci teslim artik tekil sonuc donmuyor; cift dusumu yalniz tuketim tekilligi durduruyor',
    'ikinci: ' + (r.r2.ok ? r.r2.out : hataKodu(r.r2) || r.r2.err.split('\n')[0].slice(0, 90)) + ' | stok ' + r.stok);
});

// K1b — FOR UPDATE + tuketim tekilligi birlikte kaldirilir
const K1b = degistir(K1a, 'rezervasyon_id   uuid not null unique references', 'rezervasyon_id   uuid not null references');
await varyant('K1b', K1b, async (O) => {
  const r = await eszamanliTeslim(O);
  sonuc(r.r1.ok && r.r2.ok && r.stok === '6.000',
    'K1b iki katman da yokken eszamanli teslim stogu IKI KEZ dusuruyor (B3 testi bunu yakalar)', 'stok 10 -> ' + r.stok);
});

// K2 — stok cikis korumasi etkisiz
const K2 = degistir(A1, '  if v_rezerve = 0 then\n    return;   -- rezervasyon yoksa davranis BUGUNKUYLE AYNI',
                        '  if true then\n    return;   -- NEGATIF KONTROL: koruma kaldirildi');
await varyant('K2', K2, async (O) => {
  siparis(O, 8);
  const c = O.kimlikle(DEPO810, `select public.stok_ekle('BIRA','${BAR}','810',-5,1);`);
  sonuc(c.ok && stok(O) === '5.000', 'K2 koruma yokken depo kullanicisi 8 rezerveli stogu 5e dusurebiliyor (D1a testi bunu yakalar)',
    'stok 10 -> ' + stok(O));
});

// K3 — danisma kilidi etkisiz
const K3 = degistir(A1, "  perform pg_advisory_xact_lock(hashtextextended('stok:' || p_depo_kodu || ':' || p_stok_kodu, 0));",
                        '  null;   -- NEGATIF KONTROL: kilit kaldirildi');
await varyant('K3', K3, async (O) => {
  O.sql(`update public.stok set miktar = 3 where urun_kodu='BIRA' and depo_kodu='${BAR}';`);
  const p1 = O.paralel(BAR810, `select public.bar_siparis_olustur('810','${BAR}','M1',null,'[{"menu_urun_id":"${BIRA}","adet":2}]'::jsonb); select pg_sleep(2);`);
  await new Promise((r) => setTimeout(r, 700));
  const p2 = O.paralel(BAR810, `select public.bar_siparis_olustur('810','${BAR}','M2',null,'[{"menu_urun_id":"${BIRA}","adet":2}]'::jsonb);`);
  const [r1, r2] = await Promise.all([p1, p2]);
  const rez = O.sql(`select sum(miktar)::text from public.stok_rezervasyonlari where durum='aktif';`).out;
  sonuc(r1.ok && r2.ok && rez === '4.000', 'K3 kilit yokken 3 birimlik stoga 2+2 rezervasyon ikisi de geciyor (D4 testi bunu yakalar)',
    'rezerve ' + rez + ' / stok 3');
});

// K4 — dogrudan yazma kapatmasi kaldirilir
let K4 = degistir(A1, `revoke insert, update, delete, truncate, references, trigger
  on table public.bar_siparisleri, public.bar_siparis_kalemleri, public.stok_rezervasyonlari
  from authenticated;
drop policy if exists siparis_write on public.bar_siparisleri;`, '-- NEGATIF KONTROL: dogrudan yazma kapatmasi kaldirildi');
K4 = degistir(K4, "    raise exception 'SON KOSUL: siparis tablolarina dogrudan yazma hala acik.';", '    null;');
await varyant('K4', K4, async (O) => {
  const s = siparis(O, 1).out;
  const w = O.kimlikle(BAR810, `update public.bar_siparisleri set durum='teslim_edildi' where id='${s}';`);
  const d = O.sql(`select durum::text from public.bar_siparisleri where id='${s}';`).out;
  sonuc(w.ok && d === 'teslim_edildi' && stok(O) === '10.000',
    'K4 kapatma yokken personel siparisi RPCsiz teslim_edildi yapabiliyor, stok dusmeden (A11 testi bunu yakalar)', 'durum ' + d);
});

// K5 — sayim farki ONAY ANINDAKI stoga gore hesaplanir (2026-09-18 ilk surumun hatasi)
const K5 = degistir(A1, 'v_fark := round(v_d.sayilan_miktar - v_d.sistem_miktar, 3);',
  'v_fark := round(v_d.sayilan_miktar - v_mevcut, 3);   -- NEGATIF KONTROL');
await varyant('K5', K5, async (O) => {
  O.sql(`update public.stok set miktar = 100 where urun_kodu='BIRA' and depo_kodu='${BAR}';
    insert into public.sayim_oturumlari (id, depo_kodu, otel_id, olusturan_ad, durum, toplam_urun_sayisi)
      values ('99999999-0000-0000-0000-0000000000f5','${BAR}','810','Test','onay_bekliyor',1);
    insert into public.sayim_detaylari (oturum_id, urun_kodu, urun_adi, sistem_miktar, sayilan_miktar, fark)
      values ('99999999-0000-0000-0000-0000000000f5','BIRA','Bira',100,90,-10);`);
  O.kimlikle(DEPO810, `select public.stok_ekle('BIRA','${BAR}','810',-20,1);`);
  O.kimlikle(DEPO810, `select public.stok_sayim_onayla('99999999-0000-0000-0000-0000000000f5');`);
  sonuc(stok(O) === '90.000',
    'K5 fark onay anindaki stoga gore hesaplaninca 100 -> say 90 -> cikis 20 senaryosu 90 veriyor, 70 degil (E7 testi bunu yakalar)',
    'stok ' + stok(O));
});

// K6 — sayim_detaylari SELECT kapatmasi kaldirilir (15b)
let K6 = degistir(A1, 'revoke select on table public.sayim_detaylari from authenticated;', '-- NEGATIF KONTROL: select kapatmasi kaldirildi');
K6 = degistir(K6, "    raise exception 'SON KOSUL: sayim_detaylari dogrudan okunabiliyor — eski sayim istemcisi durdurulmadi.';", '    null;');
await varyant('K6', K6, async (O) => {
  const r = O.kimlikle(DEPO810, `select count(*) from public.sayim_detaylari;`);
  sonuc(r.ok, 'K6 kapatma yokken sayim_detaylari dogrudan okunabiliyor -> eski istemci okuyup YAZABILIR (E12 testi bunu yakalar)',
    r.ok ? 'okuma basarili' : r.err.split('\n')[0]);
});

// K7 — onay koruma tetikleyicisi kaldirilir (15b ikinci katman)
let K7 = degistir(A1, `create trigger stok_sayim_oturum_koruma
  before insert or update on public.sayim_oturumlari
  for each row execute function public._stok_sayim_oturum_koruma();`, '-- NEGATIF KONTROL: tetikleyici kaldirildi');
K7 = degistir(K7, "    raise exception 'SON KOSUL: sayim onay koruma tetikleyicisi yok.';", '    null;');
await varyant('K7', K7, async (O) => {
  O.sql(`insert into public.sayim_oturumlari (id, depo_kodu, otel_id, olusturan_ad, durum)
           values ('99999999-0000-0000-0000-0000000000f7','${BAR}','810','x','onay_bekliyor');`);
  const r = O.sql(`update public.sayim_oturumlari set durum='onaylandi', kismi_uygulandi=true where id='99999999-0000-0000-0000-0000000000f7';`);
  sonuc(r.ok, 'K7 tetikleyici yokken sayim sunucu disinda onaylanmis isaretlenebiliyor (E14 testi bunu yakalar)');
});

// K8/K9 — istisna cozum kurallari (kullanici kararlari K3/K2, 2026-09-19)
const { EK_TOHUM } = await import('./bar-a1-tohum.mjs');
const ONBURO810 = { rol: 'authenticated', sub: '11111111-0000-0000-0000-0000000000d2' };   // pms_folio KAYIT
function istisnaKur(O) {
  const t = O.sql(EK_TOHUM); if (!t.ok) throw new Error('ek tohum: ' + t.err.slice(-200));
  const s = siparis(O, 1).out;
  O.sql(`set session_replication_role = replica;
    update public.bar_siparisleri set durum = 'istisna_bekliyor' where id = '${s}';
    insert into public.bar_borc_istisnalari (id, otel_id, siparis_id, oda_no, tutar, eski_folio_id, eski_rezervasyon_id, beyan_veren, beyan_metni)
      values ('99999999-0000-0000-0000-0000000000e8', '810', '${s}', '101', 250, '55555555-0000-0000-0000-000000000101',
              '88888888-0000-0000-0000-000000000101', '11111111-0000-0000-0000-0000000000d1', 'test');
    insert into public.pms_folyolar (id, otel_id, rezervasyon_id, folio_no, durum)
      values ('55555555-0000-0000-0000-0000000001bb', '810', '88888888-0000-0000-0000-000000000999', 'F-BASKA', 'acik');
    set session_replication_role = origin;`);
  return s;
}
const K8 = degistir(A1, `    if v_folio.rezervasyon_id is distinct from v_i.eski_rezervasyon_id then
      raise exception 'FOLYO_BASKA_KONAKLAMA: secilen folyo siparisi dogrulanan konaklamaya ait degil';
    end if;`, '    -- NEGATIF KONTROL: konaklama esitligi kaldirildi');
await varyant('K8', K8, async (O) => {
  const s = istisnaKur(O);
  const r = O.kimlikle(ONBURO810, `select public.bar_borc_istisnasi_coz('99999999-0000-0000-0000-0000000000e8','folyoya_yaz','55555555-0000-0000-0000-0000000001bb',true);`);
  const borc = O.sql(`select count(*) from public.pms_folio_hareketleri where kaynak_id = '${s}' and folio_id = '55555555-0000-0000-0000-0000000001bb';`).out;
  sonuc(r.ok && borc === '1', 'K8 konaklama kontrolu yokken borc BASKA misafirin folyosuna yaziliyor (B8 testi bunu yakalar)', 'borc ' + borc);
});
const K9 = degistir(A1, `    if not (public.auth_yetki_var('pms_folio', 'tam') is true) then
      raise exception 'YETKI_YOK: tahsil edilemedi karari pms_folio tam yetkisi gerektirir';
    end if;`, '    -- NEGATIF KONTROL: tam yetki kontrolu kaldirildi');
await varyant('K9', K9, async (O) => {
  istisnaKur(O);
  const r = O.kimlikle(ONBURO810, `select public.bar_borc_istisnasi_coz('99999999-0000-0000-0000-0000000000e8','tahsil_edilemedi',null,false,'deneme');`);
  sonuc(r.ok, 'K9 tam yetki kontrolu yokken kayit yetkilisi tahsil edilemedi diyebiliyor (B7a testi bunu yakalar)');
});

// K10 — 4 parametreli stok_ekle ret govdesi yerine eski yazan govde (istemci ayrimi yok)
const K10 = degistir(A1, `begin
  raise exception 'ESKI_ISTEMCI: bu ekran guncelleme oncesi surum; sayfayi yenileyip islemi tekrar yapin'
    using errcode = 'P0001';
end;`, `begin
  -- NEGATIF KONTROL: eski istemci yazabiliyor
  insert into stok (urun_kodu, depo_kodu, otel_id, miktar) values (p_urun_kodu, p_depo_kodu, p_otel_id::otel_id, greatest(0, p_delta))
  on conflict (urun_kodu, depo_kodu) do update set miktar = greatest(0, stok.miktar + p_delta), guncelleme_tarihi = now();
  return null;
end;`);
const K10b = degistir(K10, "    raise exception 'SON KOSUL: 4 parametreli stok_ekle hala yaziyor ya da ESKI_ISTEMCI dondurmuyor.';", '    null;');
await varyant('K10', K10b, async (O) => {
  const once = stok(O);
  O.kimlikle(DEPO810, `select public.stok_ekle('BIRA','${BAR}','810',10);`);
  sonuc(Number(stok(O)) === Number(once) + 10, 'K10 istemci ayrimi yokken ESKI istemci (4 parametre) A1 sonrasi stok yaziyor (E16 ve G12 bunu yakalar)',
    once + ' -> ' + stok(O));
});

// K11 — sayim hareketi tetikleyicisi kaldirilir
const K11 = degistir(A1, `create trigger stok_sayim_hareket_koruma
  before insert on public.stok_hareketleri
  for each row execute function public._stok_sayim_hareket_koruma();`, '-- NEGATIF KONTROL: hareket tetikleyicisi kaldirildi');
await varyant('K11', K11, async (O) => {
  const r = O.kimlikle(DEPO810, `insert into public.stok_hareketleri (urun_kodu, depo_kodu, otel_id, tip, miktar, aciklama)
                                 values ('BIRA','${BAR}','810','giris',10,'sayim');`);
  sonuc(r.ok, 'K11 tetikleyici yokken eski istemci stok degismeden "sayim" hareketi yazabiliyor (E17 bunu yakalar)');
});

console.log(`\nBAR A1 NEGATIF KONTROLLER: ${ok} OK / ${fail} FAIL`);
process.exitCode = fail ? 1 : 0;
