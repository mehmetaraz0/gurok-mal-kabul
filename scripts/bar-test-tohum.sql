-- scripts/bar-test-tohum.sql — IZOLE TEST VERISI, uretime uygulanmaz.
-- PMS tetikleyicileri tohumlama sirasinda devre disi: konaklama durumunu
-- dogrudan kurmak icin (check-in akisinin kendisi burada sinanmiyor).
set session_replication_role = replica;

insert into public.moduller (id, kod, ad, kategori, sira, aktif) values
  ('00000000-0000-0000-0000-00000000a001', 'bar_siparis_yonetimi', 'Bar / Restoran Siparis', 'fb', 43, true),
  ('00000000-0000-0000-0000-00000000a002', 'stok_takip', 'Stok Takip', 'depo', 10, true);

insert into public.roller (id, ad, seviye, kod, sira) values
  ('00000000-0000-0000-0000-00000000b001', 'Bar Sefi', 'otel', 'bar', 18),
  ('00000000-0000-0000-0000-00000000b002', 'Bar Goruntuleyici', 'otel', 'bar_goruntu', 98),
  ('00000000-0000-0000-0000-00000000b003', 'Depo Elemani', 'otel', 'depo', 14);

insert into public.yetki_matrisi (rol_id, modul_id, yetki) values
  ('00000000-0000-0000-0000-00000000b001', '00000000-0000-0000-0000-00000000a001', 'kayit'),
  ('00000000-0000-0000-0000-00000000b001', '00000000-0000-0000-0000-00000000a002', 'kayit'),
  ('00000000-0000-0000-0000-00000000b002', '00000000-0000-0000-0000-00000000a001', 'goruntule'),
  ('00000000-0000-0000-0000-00000000b003', '00000000-0000-0000-0000-00000000a002', 'kayit');

insert into auth.users (id, email) values
  ('11111111-0000-0000-0000-000000000810', 'bar810@test.local'),
  ('11111111-0000-0000-0000-000000000811', 'bar811@test.local'),
  ('11111111-0000-0000-0000-0000000000aa', 'pasif@test.local'),
  ('11111111-0000-0000-0000-0000000000bb', 'goruntu@test.local'),
  ('11111111-0000-0000-0000-0000000000cc', 'depo810@test.local');

insert into public.kullanicilar (id, auth_user_id, ad, rol, otel_id, aktif, rol_id) values
  ('33333333-0000-0000-0000-000000000810', '11111111-0000-0000-0000-000000000810', 'Bar 810', 'bar', '810', true,  '00000000-0000-0000-0000-00000000b001'),
  ('33333333-0000-0000-0000-000000000811', '11111111-0000-0000-0000-000000000811', 'Bar 811', 'bar', '811', true,  '00000000-0000-0000-0000-00000000b001'),
  ('33333333-0000-0000-0000-0000000000aa', '11111111-0000-0000-0000-0000000000aa', 'Pasif',   'bar', '810', false, '00000000-0000-0000-0000-00000000b001'),
  ('33333333-0000-0000-0000-0000000000bb', '11111111-0000-0000-0000-0000000000bb', 'Goruntu', 'bar', '810', true,  '00000000-0000-0000-0000-00000000b002'),
  ('33333333-0000-0000-0000-0000000000cc', '11111111-0000-0000-0000-0000000000cc', 'Depo 810','depo','810', true,  '00000000-0000-0000-0000-00000000b003');

-- PMS: 810 odalari 101 (acik folyo), 102 (kapali folyo), 103 (bos); 811 odasi 101
insert into public.pms_oda_tipleri (id, otel_id, kod, ad, azami_kisi, azami_yetiskin) values
  ('44444444-0000-0000-0000-000000000810', '810', 'STD', 'Standart', 3, 2),
  ('44444444-0000-0000-0000-000000000811', '811', 'STD', 'Standart', 3, 2);
insert into public.pms_odalar (id, otel_id, oda_tipi_id, oda_no, kullanim_durumu) values
  ('66666666-0000-0000-0000-000000000101', '810', '44444444-0000-0000-0000-000000000810', '101', 'dolu'),
  ('66666666-0000-0000-0000-000000000102', '810', '44444444-0000-0000-0000-000000000810', '102', 'dolu'),
  ('66666666-0000-0000-0000-000000000103', '810', '44444444-0000-0000-0000-000000000810', '103', 'bos'),
  ('66666666-0000-0000-0000-000000000811', '811', '44444444-0000-0000-0000-000000000811', '101', 'dolu');
insert into public.pms_misafirler (id, otel_id, ad, soyad) values
  ('77777777-0000-0000-0000-000000000101', '810', 'Test', 'Birinci'),
  ('77777777-0000-0000-0000-000000000102', '810', 'Test', 'Ikinci'),
  ('77777777-0000-0000-0000-000000000811', '811', 'Test', 'Resort');
insert into public.pms_rezervasyonlar (id, otel_id, rezervasyon_no, misafir_id, oda_tipi_id, giris_tarihi, cikis_tarihi, durum, giris_zamani) values
  ('88888888-0000-0000-0000-000000000101', '810', 'T-101', '77777777-0000-0000-0000-000000000101', '44444444-0000-0000-0000-000000000810', current_date - 1, current_date + 3, 'giris_yapildi', now()),
  ('88888888-0000-0000-0000-000000000102', '810', 'T-102', '77777777-0000-0000-0000-000000000102', '44444444-0000-0000-0000-000000000810', current_date - 1, current_date + 3, 'giris_yapildi', now()),
  ('88888888-0000-0000-0000-000000000811', '811', 'T-811', '77777777-0000-0000-0000-000000000811', '44444444-0000-0000-0000-000000000811', current_date - 1, current_date + 3, 'giris_yapildi', now());
insert into public.pms_oda_atamalari (otel_id, rezervasyon_id, oda_id, baslangic, bitis, aktif) values
  ('810', '88888888-0000-0000-0000-000000000101', '66666666-0000-0000-0000-000000000101', current_date - 1, current_date + 3, true),
  ('810', '88888888-0000-0000-0000-000000000102', '66666666-0000-0000-0000-000000000102', current_date - 1, current_date + 3, true),
  ('811', '88888888-0000-0000-0000-000000000811', '66666666-0000-0000-0000-000000000811', current_date - 1, current_date + 3, true);
insert into public.pms_folyolar (id, otel_id, rezervasyon_id, folio_no, durum, kapanis_zamani) values
  ('55555555-0000-0000-0000-000000000101', '810', '88888888-0000-0000-0000-000000000101', 'F-101', 'acik', null),
  ('55555555-0000-0000-0000-000000000102', '810', '88888888-0000-0000-0000-000000000102', 'F-102', 'kapali', now()),
  ('55555555-0000-0000-0000-000000000811', '811', '88888888-0000-0000-0000-000000000811', 'F-811', 'acik', null);

insert into public.urunler (kod, ad, birim) values
  ('BIRA', 'Bira', 'KTU'), ('VISKI', 'Viski', 'CL'), ('LIMON', 'Limon', 'ADET');
insert into public.stok (urun_kodu, depo_kodu, otel_id, miktar) values
  ('BIRA', '810_CSM302', '810', 10), ('VISKI', '810_CSM302', '810', 2),
  ('LIMON', '810_CSM302', '810', 50), ('BIRA', '810_100', '810', 100);
insert into public.menu_urunler (id, ad, kategori, otel_id, fiyat, aktif, ucretli, tip, stok_kodu, miktar_per_porsiyon) values
  ('22222222-0000-0000-0000-000000000001', 'Bira',     'icecek', '810', 0,   true, false, 'direkt', 'BIRA',  1),
  ('22222222-0000-0000-0000-000000000002', 'Viski',    'icecek', '810', 250, true, true,  'direkt', 'VISKI', 1),
  ('22222222-0000-0000-0000-000000000003', 'Limonata', 'icecek', '810', 0,   true, false, 'direkt', null,    null),
  ('22222222-0000-0000-0000-000000000811', 'Bira',     'icecek', '811', 0,   true, false, 'direkt', 'BIRA',  1);

set session_replication_role = origin;
