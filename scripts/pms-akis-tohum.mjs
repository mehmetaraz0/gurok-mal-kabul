// ===========================================================================
// PMS AKIS TESTI — YAPAY TOHUM (uretime BAGLANMAZ, gercek misafir verisi YOK)
// ===========================================================================
// Tum adlar uydurma, tum kimlikler sabit test UUID'leridir. Bu dosya yalnizca
// izole Docker veritabanina yazilir; uretim semasina veya uretim verisine
// dokunmaz. Modul/rol/yetki satirlari TEST VERISIDIR — urunun yetki modeli
// degistirilmemistir, yalnizca RLS'in gercekten calisabilmesi icin izole
// veritabaninda karsiligi kurulur.
//
// Mevcut bar tohumunun (scripts/bar-test-tohum.sql) USTUNE eklenir:
//   - oda tipi 44444444-...-810 (STD) ve otel 810 oradan gelir
//   - 101/102 dolu, 103 bos odalar oradan gelir; bu dosya 201/202'yi ekler
// ===========================================================================

export const PMS = {
  OTEL: '810',
  TIP: '44444444-0000-0000-0000-000000000810',
  ODA201: '66666666-0000-0000-0000-000000000201',
  ODA202: '66666666-0000-0000-0000-000000000202',
  ODA203: '66666666-0000-0000-0000-000000000203',
  MIS201: '77777777-0000-0000-0000-000000000201',
  MIS202: '77777777-0000-0000-0000-000000000202',
  // Onaylanmis, bugun girisli; oda ATAMASI VAR (oda 201).
  REZ_ATANMIS: '88888888-0000-0000-0000-000000000201',
  // Onaylanmis, bugun girisli; oda atamasi YOK.
  REZ_ATAMASIZ: '88888888-0000-0000-0000-000000000202',
  RESEPSIYON: { rol: 'authenticated', sub: '11111111-0000-0000-0000-0000000000e1' },
};

// Ekran harness'ina verilecek yetki haritasi (sunucudaki yetki_matrisi ile ayni).
export const RESEPSIYON_YETKI = {
  pms_oda_tipi: 'kayit', pms_oda: 'kayit', pms_misafir: 'kayit', pms_rezervasyon: 'kayit',
  pms_folio: 'kayit', pms_housekeeping: 'tam', pms_misafir_kimlik: 'kayit',
};

// Dogrudan SQL, uretimdeki denetim tetikleyicisince (phase0_islem_audit)
// reddedilir; tohum replica rolunde yazilir. Test edilen RPC'ler normal rolde
// calisir — kapilar gevsetilmez.
export const PMS_TOHUM = `
set session_replication_role = replica;

insert into public.moduller (id, kod, ad, kategori, sira, aktif) values
  ('00000000-0000-0000-0000-00000000a010', 'pms_oda_tipi',    'PMS Oda Tipi',    'pms', 61, true),
  ('00000000-0000-0000-0000-00000000a011', 'pms_oda',         'PMS Oda',         'pms', 62, true),
  ('00000000-0000-0000-0000-00000000a012', 'pms_misafir',     'PMS Misafir',     'pms', 63, true),
  ('00000000-0000-0000-0000-00000000a013', 'pms_rezervasyon', 'PMS Rezervasyon', 'pms', 64, true),
  ('00000000-0000-0000-0000-00000000a014', 'pms_housekeeping', 'PMS Kat Hizmetleri', 'pms', 65, true),
  ('00000000-0000-0000-0000-00000000a015', 'pms_misafir_kimlik', 'PMS Misafir Kimlik', 'pms', 66, true);

insert into public.roller (id, ad, seviye, kod, sira) values
  ('00000000-0000-0000-0000-00000000b021', 'Resepsiyon', 'otel', 'resepsiyon', 32);

insert into public.yetki_matrisi (rol_id, modul_id, yetki) values
  ('00000000-0000-0000-0000-00000000b021', '00000000-0000-0000-0000-00000000a010', 'kayit'),
  ('00000000-0000-0000-0000-00000000b021', '00000000-0000-0000-0000-00000000a011', 'kayit'),
  ('00000000-0000-0000-0000-00000000b021', '00000000-0000-0000-0000-00000000a012', 'kayit'),
  ('00000000-0000-0000-0000-00000000b021', '00000000-0000-0000-0000-00000000a013', 'kayit'),
  -- Resepsiyon tahsilat alir ve folyo kapatir (pms_folio modulu EK_TOHUM'dan gelir),
  -- kat hizmetleri dongusunu uctan uca testte yurutebilmek icin de yetkilidir.
  -- Bu TEST VERISIDIR; urunun rol/yetki tanimlari degistirilmemistir.
  ('00000000-0000-0000-0000-00000000b021', '00000000-0000-0000-0000-00000000a003', 'kayit'),
  ('00000000-0000-0000-0000-00000000b021', '00000000-0000-0000-0000-00000000a014', 'tam'),
  ('00000000-0000-0000-0000-00000000b021', '00000000-0000-0000-0000-00000000a015', 'kayit');

insert into auth.users (id, email) values
  ('11111111-0000-0000-0000-0000000000e1', 'resepsiyon810@test.local');

insert into public.kullanicilar (id, auth_user_id, ad, rol, otel_id, aktif, rol_id) values
  ('33333333-0000-0000-0000-0000000000e1', '11111111-0000-0000-0000-0000000000e1',
   'Resepsiyon 810', 'muhasebe_calisani', '810', true, '00000000-0000-0000-0000-00000000b021');

-- Check-in alabilecek iki bos + temiz oda.
insert into public.pms_odalar (id, otel_id, oda_tipi_id, oda_no, kullanim_durumu, temizlik_durumu) values
  ('66666666-0000-0000-0000-000000000201', '810', '44444444-0000-0000-0000-000000000810', '201', 'bos', 'temiz'),
  ('66666666-0000-0000-0000-000000000202', '810', '44444444-0000-0000-0000-000000000810', '202', 'bos', 'temiz'),
  ('66666666-0000-0000-0000-000000000203', '810', '44444444-0000-0000-0000-000000000810', '203', 'bos', 'temiz');

insert into public.pms_misafirler (id, otel_id, ad, soyad) values
  ('77777777-0000-0000-0000-000000000201', '810', 'Deneme', 'Atanmis'),
  ('77777777-0000-0000-0000-000000000202', '810', 'Deneme', 'Atamasiz');

insert into public.pms_rezervasyonlar
  (id, otel_id, rezervasyon_no, misafir_id, oda_tipi_id, giris_tarihi, cikis_tarihi, durum) values
  ('88888888-0000-0000-0000-000000000201', '810', 'T-201', '77777777-0000-0000-0000-000000000201',
   '44444444-0000-0000-0000-000000000810', current_date, current_date + 2, 'onaylandi'),
  ('88888888-0000-0000-0000-000000000202', '810', 'T-202', '77777777-0000-0000-0000-000000000202',
   '44444444-0000-0000-0000-000000000810', current_date, current_date + 2, 'onaylandi');

-- YALNIZ 201: rezervasyon oda 201'e ATANMIS ama henuz giris yapilmamis.
-- Bu, "once ata, sonra giris yap" akisinin gercek halidir.
insert into public.pms_oda_atamalari (otel_id, rezervasyon_id, oda_id, baslangic, bitis, aktif) values
  ('810', '88888888-0000-0000-0000-000000000201', '66666666-0000-0000-0000-000000000201',
   current_date, current_date + 2, true);

set session_replication_role = origin;
`;
