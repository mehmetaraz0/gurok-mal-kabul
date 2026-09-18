// ===========================================================================
// BAR A1 — ortak test tohumu ve yardimcilari (veritabani + ekran testleri)
// ===========================================================================
// bar-test-tohum.sql'e dokunmadan A1'e ozel kimlikler/roller. Yardimcilar bir
// barOrtami() ornegine baglanir. Uretime BAGLANMAZ.
// ===========================================================================
import { hataKodu } from './bar-test-ortam.mjs';

export const K = {
  BAR810: { rol: 'authenticated', sub: '11111111-0000-0000-0000-000000000810' },   // bar kayit
  BAR811: { rol: 'authenticated', sub: '11111111-0000-0000-0000-000000000811' },
  PASIF: { rol: 'authenticated', sub: '11111111-0000-0000-0000-0000000000aa' },
  DEPO810: { rol: 'authenticated', sub: '11111111-0000-0000-0000-0000000000cc' },   // stok kayit, bar yok
  SEF810: { rol: 'authenticated', sub: '11111111-0000-0000-0000-0000000000d1' },    // bar TAM
  ONBURO810: { rol: 'authenticated', sub: '11111111-0000-0000-0000-0000000000d2' }, // pms_folio kayit
  DEPOSEF810: { rol: 'authenticated', sub: '11111111-0000-0000-0000-0000000000d3' },// stok TAM
  QR: { rol: 'service_role' },
  ANON: { rol: 'anon' },
};
export const M = { BIRA: '22222222-0000-0000-0000-000000000001', VISKI: '22222222-0000-0000-0000-000000000002',
  LIMONATA: '22222222-0000-0000-0000-000000000003' };
export const BAR = '810_CSM302';
export const FOLYO101 = '55555555-0000-0000-0000-000000000101';

// A1 testine ozel ek kimlikler (bar-test-tohum.sql'e dokunmadan).
export const EK_TOHUM = `
  insert into public.moduller (id, kod, ad, kategori, sira, aktif) values
    ('00000000-0000-0000-0000-00000000a003', 'pms_folio', 'PMS Folyo', 'pms', 60, true);
  insert into public.roller (id, ad, seviye, kod, sira) values
    ('00000000-0000-0000-0000-00000000b011', 'Bar Sefi Tam', 'otel', 'bar_tam', 17),
    ('00000000-0000-0000-0000-00000000b012', 'On Buro', 'otel', 'onburo', 30),
    ('00000000-0000-0000-0000-00000000b013', 'Depo Sorumlusu', 'otel', 'depo_sef', 13);
  insert into public.yetki_matrisi (rol_id, modul_id, yetki) values
    ('00000000-0000-0000-0000-00000000b011', '00000000-0000-0000-0000-00000000a001', 'tam'),
    ('00000000-0000-0000-0000-00000000b012', '00000000-0000-0000-0000-00000000a003', 'kayit'),
    ('00000000-0000-0000-0000-00000000b013', '00000000-0000-0000-0000-00000000a002', 'tam');
  insert into auth.users (id, email) values
    ('11111111-0000-0000-0000-0000000000d1', 'sef810@test.local'),
    ('11111111-0000-0000-0000-0000000000d2', 'onburo810@test.local'),
    ('11111111-0000-0000-0000-0000000000d3', 'deposef810@test.local');
  insert into public.kullanicilar (id, auth_user_id, ad, rol, otel_id, aktif, rol_id) values
    ('33333333-0000-0000-0000-0000000000d1', '11111111-0000-0000-0000-0000000000d1', 'Sef 810', 'bar', '810', true, '00000000-0000-0000-0000-00000000b011'),
    ('33333333-0000-0000-0000-0000000000d2', '11111111-0000-0000-0000-0000000000d2', 'Onburo 810', 'muhasebe_calisani', '810', true, '00000000-0000-0000-0000-00000000b012'),
    ('33333333-0000-0000-0000-0000000000d3', '11111111-0000-0000-0000-0000000000d3', 'DepoSef 810', 'depo', '810', true, '00000000-0000-0000-0000-00000000b013');`;

export function a1Yardimcilari(O) {
  const q = (kim, s) => O.kimlikle(kim, s);
  const kalemler = (arr) => `'${JSON.stringify(arr)}'::jsonb`;
  const siparis = (kim, arr, oda = null, depo = BAR, otel = '810') =>
    q(kim, `select public.bar_siparis_olustur('${otel}','${depo}','M1',${oda ? `'${oda}'` : 'null'},${kalemler(arr)});`);
  const VISKI1 = [{ menu_urun_id: M.VISKI, adet: 1, gosterilen_fiyat: 250 }];
  const tek = (s) => O.sql(s).out;
  const stok = (kod, depo = BAR) => tek(`select miktar::text from public.stok where urun_kodu='${kod}' and depo_kodu='${depo}';`);
  const kod = (r) => hataKodu(r) || (r.ok ? 'OK' : r.err.split('\n').slice(-1)[0].slice(0, 120));
  const hazirla = (id, kim = K.BAR810) => q(kim, `select public.bar_siparis_durum_guncelle('${id}','hazirlaniyor');
                                                   select public.bar_siparis_durum_guncelle('${id}','hazir');`);
  // Test verisi hazirligi: uretimdeki denetim tetikleyicisi (phase0_islem_audit)
  // dogrudan SQL'i 'aktif ERP personeli' istemedigi icin reddeder; tohum gibi
  // replica rolunde yapilir. Test edilen RPC'ler normal rolde calisir.
  const folyoKapat = () => O.sql(`set session_replication_role = replica;
    update public.pms_folyolar set durum='kapali', kapanis_zamani=now() where id='${FOLYO101}';
    set session_replication_role = origin;`);
  const sifirla = () => O.sql(`
    set session_replication_role = replica;
    delete from public.stok_sayim_bekleyenleri; delete from public.sayim_detaylari; delete from public.sayim_oturumlari;
    delete from public.pms_folio_hareketleri; delete from public.bar_borc_istisnalari; delete from public.bar_stok_tuketimleri;
    delete from public.stok_rezervasyonlari; delete from public.bar_siparis_kalemleri; delete from public.bar_siparisleri;
    delete from public.stok_hareketleri; delete from public.pms_folyolar where id = '55555555-0000-0000-0000-0000000001aa';
    update public.stok set miktar = case urun_kodu when 'BIRA' then 10 when 'VISKI' then 2 when 'LIMON' then 50 end,
                           guncelleme_tarihi = '2026-07-09 07:23:10+00' where depo_kodu = '${BAR}';
    update public.menu_urunler set fiyat = 250 where id = '${M.VISKI}';
    update public.pms_folyolar set durum = 'acik', kapanis_zamani = null where id = '${FOLYO101}';
    set session_replication_role = origin;`);
  return { q, kalemler, siparis, VISKI1, tek, stok, kod, hazirla, folyoKapat, sifirla };
}
