-- ============================================================================
-- PMS FAZ 1 / ADIM 1 — SÖZLEŞME TESTLERİ
-- ============================================================================
-- scripts/pms-faz1-testleri.mjs tarafından çalıştırılır.
-- Sıra: Supabase iskelesi -> ÜRETİM DÖKÜMÜ -> PMS migration -> bu dosya.
--
-- Yani testler sentetik bir şema üzerinde değil, üretimin bayt-birebir
-- doğrulanmış kopyası üzerinde koşar: Phase 0 politikaları, auth_* yardımcıları
-- ve yetki motoru gerçek hâlleriyle devrededir.
--
-- Üretim veritabanına BAĞLANMAZ.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Test tezgahı: gerçek kullanıcılar, gerçek roller, gerçek yetki matrisi
-- ---------------------------------------------------------------------------
create schema if not exists pms_test;

create or replace function pms_test.dogru(p_deger boolean, p_etiket text)
returns void language plpgsql as $$
begin
  if p_deger is not true then raise exception 'BASARISIZ: %', p_etiket; end if;
end;
$$;

-- Kabul edilen reddetme bicimleri:
--   42501 insufficient_privilege        -> RLS / GRANT reddi
--   23xxx integrity_constraint_violation -> FK, unique, check, not-null
--   22xxx data_exception                 -> gecersiz enum degeri gibi
--   P0001 raise_exception                -> trigger'in acikca reddetmesi
--                                           (Phase 0 otel degismezligi)
-- Hepsi "veritabani reddetti" demektir; HANGI mekanizmayla reddettigi testin
-- konusu degil. Konu, istemcinin gecememesi.
create or replace function pms_test.reddedilmeli(p_sql text, p_etiket text)
returns void language plpgsql as $$
begin
  begin
    execute p_sql;
  exception
    when insufficient_privilege then return;
    when integrity_constraint_violation then return;
    when data_exception then return;
    when raise_exception then return;
    when others then
      raise exception 'BASARISIZ (beklenmeyen hata) %: % / %', p_etiket, sqlstate, sqlerrm;
  end;
  raise exception 'BASARISIZ: % - reddedilmesi gerekirken KABUL EDILDI', p_etiket;
end;
$$;

grant usage on schema pms_test to authenticated, anon;

-- Rol: yetki matrisinde PMS modullerine 'tam' verilmis bir rol olustur.
insert into public.roller (id, ad, seviye, kod, aktif)
values ('50000000-0000-0000-0000-000000000001', 'PMS Test Rolu', 'otel', 'pms_test_rol', true)
on conflict (id) do nothing;

insert into public.yetki_matrisi (rol_id, modul_id, yetki)
select '50000000-0000-0000-0000-000000000001', id, 'tam'::public.yetki_seviye
from public.moduller where kod in ('pms_oda_tipi','pms_oda')
on conflict (rol_id, modul_id) do nothing;

-- Yetkisiz rol: PMS modullerinde satiri YOK -> auth_yetki_var false doner.
insert into public.roller (id, ad, seviye, kod, aktif)
values ('50000000-0000-0000-0000-000000000002', 'PMS Yetkisiz Rol', 'otel', 'pms_yetkisiz', true)
on conflict (id) do nothing;

-- Kullanicilar
-- kullanicilar.auth_user_id -> auth.users(id) yabanci anahtari uretimde VAR.
-- Kimlikler once orada olmali; bu, gercek semanin bir kisiti.
insert into auth.users (id, email)
select ('70000000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
       'pms-test-' || n || '@ornek.gecersiz'
from generate_series(1, 5) n
on conflict (id) do nothing;

-- NOT: kullanicilar.rol (eski kullanici_rol enum'u) uretimde NOT NULL. Gercek
-- yetki karari rol_id -> yetki_matrisi uzerinden verilir; bu kolon eski kabuk
-- kontrolu icin durur. Testte de doldurulmali, aksi halde tezgah kurulamaz.
insert into public.kullanicilar (id, auth_user_id, rol, rol_id, otel_id, aktif, tum_oteller, ad)
values
  ('60000000-0000-0000-0000-000000000001','70000000-0000-0000-0000-000000000001','yonetici',
   '50000000-0000-0000-0000-000000000001','810', true,  false, 'PMS 810 personeli'),
  ('60000000-0000-0000-0000-000000000002','70000000-0000-0000-0000-000000000002','yonetici',
   '50000000-0000-0000-0000-000000000001','811', true,  false, 'PMS 811 personeli'),
  ('60000000-0000-0000-0000-000000000003','70000000-0000-0000-0000-000000000003','yonetici',
   '50000000-0000-0000-0000-000000000001','810', false, false, 'PMS pasif personel'),
  ('60000000-0000-0000-0000-000000000004','70000000-0000-0000-0000-000000000004','yonetici',
   '50000000-0000-0000-0000-000000000002','810', true,  false, 'PMS yetkisiz personel'),
  ('60000000-0000-0000-0000-000000000005','70000000-0000-0000-0000-000000000005','yonetici',
   '50000000-0000-0000-0000-000000000001', null, true,  true,  'PMS merkez personeli')
on conflict (id) do nothing;

-- Tohum veri: her otelde bir oda tipi ve bir oda. Sahip (postgres) olarak
-- eklenir; RLS'i test etmek icin degil, test zemini kurmak icin.
insert into public.pms_oda_tipleri (id, otel_id, kod, ad, azami_kisi, azami_yetiskin, azami_cocuk)
values
  ('80000000-0000-0000-0000-000000000810','810','STD','Standart Oda',3,2,2),
  ('80000000-0000-0000-0000-000000000811','811','STD','Standart Oda',3,2,2)
on conflict (id) do nothing;

insert into public.pms_odalar (id, otel_id, oda_tipi_id, oda_no, kat)
values
  ('90000000-0000-0000-0000-000000000810','810','80000000-0000-0000-0000-000000000810','101','1'),
  ('90000000-0000-0000-0000-000000000811','811','80000000-0000-0000-0000-000000000811','101','1')
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- E) AYNI ODA NO FARKLI OTELDE -> IZIN
-- ---------------------------------------------------------------------------
-- Yukaridaki iki '101' odasi farkli otellerde ve ikisi de eklendi.
select pms_test.dogru(
  (select count(*) = 2 from public.pms_odalar where oda_no = '101'),
  'E) ayni oda numarasi farkli otellerde kabul edilir');

-- ---------------------------------------------------------------------------
-- D) AYNI OTELDE MUKERRER ODA NO -> RED
-- ---------------------------------------------------------------------------
select pms_test.reddedilmeli($q$
  insert into public.pms_odalar (otel_id, oda_tipi_id, oda_no)
  values ('810','80000000-0000-0000-0000-000000000810','101')
$q$, 'D) ayni otelde mukerrer oda numarasi');

-- ---------------------------------------------------------------------------
-- C) ÇAPRAZ OTEL: 811 oda -> 810 oda tipi -> RED (veritabani seviyesinde)
-- ---------------------------------------------------------------------------
select pms_test.reddedilmeli($q$
  insert into public.pms_odalar (otel_id, oda_tipi_id, oda_no)
  values ('811','80000000-0000-0000-0000-000000000810','999')
$q$, 'C) 811 odasi 810 oda tipine baglanamaz');

-- Ters yon de reddedilmeli.
select pms_test.reddedilmeli($q$
  insert into public.pms_odalar (otel_id, oda_tipi_id, oda_no)
  values ('810','80000000-0000-0000-0000-000000000811','998')
$q$, 'C2) 810 odasi 811 oda tipine baglanamaz');

-- Mevcut bir odayi capraz otel tipine GUNCELLEMEK de reddedilmeli.
select pms_test.reddedilmeli($q$
  update public.pms_odalar set oda_tipi_id='80000000-0000-0000-0000-000000000811'
  where id='90000000-0000-0000-0000-000000000810'
$q$, 'C3) oda tipi capraz otele GUNCELLENEMEZ');

-- ---------------------------------------------------------------------------
-- Kapasite kisitlari
-- ---------------------------------------------------------------------------
select pms_test.reddedilmeli($q$
  insert into public.pms_oda_tipleri (otel_id, kod, ad, azami_kisi, azami_yetiskin, azami_cocuk)
  values ('810','X1','Gecersiz',2,5,0)
$q$, 'kapasite: azami_yetiskin azami_kisi yi asamaz');

select pms_test.reddedilmeli($q$
  insert into public.pms_oda_tipleri (otel_id, kod, ad, azami_kisi, azami_yetiskin, azami_cocuk)
  values ('810','X2','Gecersiz',0,1,0)
$q$, 'kapasite: azami_kisi en az 1 olmali');

select pms_test.reddedilmeli($q$
  insert into public.pms_oda_tipleri (otel_id, kod, ad, azami_kisi, azami_yetiskin, azami_cocuk)
  values ('810','   ','Bos kod',2,2,0)
$q$, 'kod bos olamaz');

-- Gecersiz durum degeri enum tarafindan reddedilir.
select pms_test.reddedilmeli($q$
  update public.pms_odalar set kullanim_durumu='REZERVE'
  where id='90000000-0000-0000-0000-000000000810'
$q$, 'gecersiz kullanim_durumu reddedilir');

-- otel_id NULL olamaz.
select pms_test.reddedilmeli($q$
  insert into public.pms_oda_tipleri (otel_id, kod, ad, azami_kisi, azami_yetiskin)
  values (null,'X3','Otelsiz',2,2)
$q$, 'otel_id NULL olamaz');

-- ---------------------------------------------------------------------------
-- A) 810 kullanicisi -> 810 kayitlari -> IZIN
-- ---------------------------------------------------------------------------
set role authenticated;
select set_config('request.jwt.claim.role','authenticated',false);
select set_config('request.jwt.claim.sub','70000000-0000-0000-0000-000000000001',false);

select pms_test.dogru((select count(*) = 1 from public.pms_oda_tipleri), 'A) 810 kullanicisi kendi oda tipini gorur');
select pms_test.dogru((select count(*) = 1 from public.pms_odalar),      'A) 810 kullanicisi kendi odasini gorur');
select pms_test.dogru(
  (select otel_id::text = '810' from public.pms_odalar limit 1),
  'A) gorunen kayit kendi otelinin');

insert into public.pms_odalar (otel_id, oda_tipi_id, oda_no, kat)
values ('810','80000000-0000-0000-0000-000000000810','102','1');
select pms_test.dogru((select count(*) = 2 from public.pms_odalar), 'A) 810 kullanicisi kendi otelinde oda ekleyebilir');

update public.pms_odalar set temizlik_durumu='temiz' where oda_no='102';
select pms_test.dogru(
  (select temizlik_durumu = 'temiz' from public.pms_odalar where oda_no='102'),
  'A) 810 kullanicisi kendi odasini guncelleyebilir');

-- ---------------------------------------------------------------------------
-- B) 810 kullanicisi -> 811 kayitlari -> RED
-- ---------------------------------------------------------------------------
select pms_test.dogru(
  (select count(*) = 0 from public.pms_odalar where otel_id::text = '811'),
  'B) 810 kullanicisi 811 odalarini GOREMEZ');
select pms_test.dogru(
  (select count(*) = 0 from public.pms_oda_tipleri where otel_id::text = '811'),
  'B) 810 kullanicisi 811 oda tiplerini GOREMEZ');

-- Istemci otel_id gondererek kapsam asamaz.
select pms_test.reddedilmeli($q$
  insert into public.pms_odalar (otel_id, oda_tipi_id, oda_no)
  values ('811','80000000-0000-0000-0000-000000000811','555')
$q$, 'B) istemci otel_id degistirerek 811 e yazamaz');

-- Gormedigi satiri guncelleyemez (0 satir etkilenir, sessiz basarisizlik degil:
-- gorunurlugun kendisi engel).
update public.pms_odalar set aciklama='ele gecirildi' where otel_id::text='811';
reset role;
select pms_test.dogru(
  (select count(*) = 0 from public.pms_odalar where aciklama='ele gecirildi'),
  'B) 810 kullanicisi 811 odasini DEGISTIREMEZ');

-- Phase 0 otel degismezligi: kendi kaydinin otelini bile tasiyamaz.
set role authenticated;
select set_config('request.jwt.claim.sub','70000000-0000-0000-0000-000000000001',false);
select pms_test.reddedilmeli($q$
  update public.pms_odalar set otel_id='811' where oda_no='102'
$q$, 'B) kaydin oteli sonradan DEGISTIRILEMEZ');

-- ---------------------------------------------------------------------------
-- F) PASİF KULLANICI -> RED
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub','70000000-0000-0000-0000-000000000003',false);
select pms_test.dogru((select count(*) = 0 from public.pms_odalar), 'F) pasif kullanici hicbir oda goremez');
select pms_test.reddedilmeli($q$
  insert into public.pms_odalar (otel_id, oda_tipi_id, oda_no)
  values ('810','80000000-0000-0000-0000-000000000810','777')
$q$, 'F) pasif kullanici yazamaz');

-- ---------------------------------------------------------------------------
-- Yetkisiz kullanici (aktif, oteli var, ama modul yetkisi yok) -> RED
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub','70000000-0000-0000-0000-000000000004',false);
select pms_test.dogru((select count(*) = 0 from public.pms_odalar), 'yetkisiz kullanici oda goremez');
select pms_test.reddedilmeli($q$
  insert into public.pms_odalar (otel_id, oda_tipi_id, oda_no)
  values ('810','80000000-0000-0000-0000-000000000810','778')
$q$, 'yetkisiz kullanici yazamaz');

-- ---------------------------------------------------------------------------
-- Kimliksiz oturum -> RED
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub','',false);
select pms_test.dogru((select count(*) = 0 from public.pms_odalar), 'kimliksiz oturum oda goremez');

-- ---------------------------------------------------------------------------
-- Merkez kullanicisi (tum_oteller) -> HER IKI OTEL
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub','70000000-0000-0000-0000-000000000005',false);
select pms_test.dogru(
  (select count(distinct otel_id) = 2 from public.pms_odalar),
  'merkez kullanicisi her iki otelin odalarini gorur');
reset role;

-- ---------------------------------------------------------------------------
-- G) ANONIM -> RED
-- ---------------------------------------------------------------------------
set role anon;
select set_config('request.jwt.claim.role','anon',false);
select set_config('request.jwt.claim.sub','',false);
select pms_test.reddedilmeli($q$select count(*) from public.pms_oda_tipleri$q$, 'G) anon oda tiplerini okuyamaz');
select pms_test.reddedilmeli($q$select count(*) from public.pms_odalar$q$,      'G) anon odalari okuyamaz');
select pms_test.reddedilmeli($q$
  insert into public.pms_odalar (otel_id, oda_tipi_id, oda_no)
  values ('810','80000000-0000-0000-0000-000000000810','666')
$q$, 'G) anon oda ekleyemez');
reset role;

-- ---------------------------------------------------------------------------
-- Kalici politika kisitlayici tabani ATLAYAMAZ (Phase 0 dersi)
-- ---------------------------------------------------------------------------
create policy pms_test_bypass on public.pms_odalar for all using (true) with check (true);
set role authenticated;
select set_config('request.jwt.claim.role','authenticated',false);
select set_config('request.jwt.claim.sub','70000000-0000-0000-0000-000000000001',false);
select pms_test.dogru(
  (select count(*) = 0 from public.pms_odalar where otel_id::text = '811'),
  'kalici OR politikasi otel kapsamini ATLAYAMAZ');
reset role;
drop policy pms_test_bypass on public.pms_odalar;

-- ---------------------------------------------------------------------------
-- Oda tipi silme: kullanimdaki tip silinemez
-- ---------------------------------------------------------------------------
select pms_test.reddedilmeli($q$
  delete from public.pms_oda_tipleri where id='80000000-0000-0000-0000-000000000810'
$q$, 'kullanimdaki oda tipi silinemez (on delete restrict)');

select 'TUM PMS FAZ 1 TESTLERI GECTI' as sonuc;
