-- ============================================================================
-- YEREL STAGING KATMANI — YALNIZ TARAYICI QA İÇİN
-- ============================================================================
-- scripts/yerel-staging.mjs tarafından, şu sıradan SONRA uygulanır:
--   supabase-shim.sql -> üretim şema dökümü -> PMS Adım 1..4
--
-- ÜRETİMDE ASLA ÇALIŞTIRILMAZ. İçeriği bilerek "gerçek dışı"dır:
--   * PostgREST'in ihtiyaç duyduğu authenticator rolü
--   * PostgREST'in JWT claim'lerini yazdığı GUC biçimine uyum
--   * ekranların boş görünmemesi için demo veri
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1) PostgREST rolleri
-- ---------------------------------------------------------------------------
-- DIKKAT: rol iskele tarafindan NOLOGIN olarak zaten olusturulmus olabilir.
-- Yalniz "yoksa olustur" demek yetmez — o durumda PostgREST
-- `role "authenticator" is not permitted to log in` ile duser.
-- Bu yuzden LOGIN ve parola KOSULSUZ uygulanir.
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'authenticator') then
    create role authenticator;
  end if;
end;
$$;
alter role authenticator login noinherit password 'staging';
grant anon, authenticated, service_role to authenticator;

-- ---------------------------------------------------------------------------
-- 2) auth.uid() / auth.role() — İKİ GUC BİÇİMİNİ DE OKU
-- ---------------------------------------------------------------------------
-- Test iskelesi eski biçimi (`request.jwt.claim.sub`) set_config ile yazıyor.
-- PostgREST 10+ ise claim'lerin TAMAMINI tek JSON GUC'unda yazıyor
-- (`request.jwt.claims`). Yalnız birini okumak, ekranların sessizce BOŞ
-- gelmesine yol açar: RLS auth.uid() null görür, hicbir satir eslesmez ve
-- hata da olusmaz. Ikisini de oku.
create or replace function auth.uid() returns uuid language sql stable as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'
  )::uuid;
$$;

create or replace function auth.role() returns text language sql stable as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'
  );
$$;

create or replace function auth.email() returns text language sql stable as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.email', true), ''),
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'email'
  );
$$;

-- ---------------------------------------------------------------------------
-- 3) DEMO VERİ
-- ---------------------------------------------------------------------------
-- Şema dökümü SEMA-ONLY: moduller/roller/kullanicilar tabloları boş gelir.
-- PMS modüllerini migration'lar ekler; diğerlerini burada ekliyoruz ki
-- portal ve menü gerçekçi görünsün.
insert into public.moduller (kod, ad, kategori, sira, aktif) values
  ('bar_siparis_yonetimi','Bar Sipariş Yönetimi','bar', 90, true),
  ('yetki_yonetimi',      'Yetki Yönetimi',      'yonetim', 99, true),
  ('stok_takip',          'Stok Takip',          'depo', 10, true),
  ('denetim_izi',         'Denetim İzi',         'yonetim', 98, true),
  ('kullanici_yonetimi',  'Kullanıcı Yönetimi',  'yonetim', 97, true)
on conflict (kod) do nothing;

insert into auth.users (id, email) values
  ('a0000000-0000-0000-0000-0000000000a1','qa-tam@ornek.gecersiz'),
  ('a0000000-0000-0000-0000-0000000000a2','qa-kisitli@ornek.gecersiz'),
  ('a0000000-0000-0000-0000-0000000000a3','qa-811@ornek.gecersiz')
on conflict (id) do nothing;

insert into public.roller (id, ad, seviye, kod, aktif) values
  ('b0000000-0000-0000-0000-0000000000a1','QA Tam Yetki','otel','qa_tam',true),
  ('b0000000-0000-0000-0000-0000000000a2','QA Sadece Görüntüleme','otel','qa_goruntule',true)
on conflict (id) do nothing;

-- Tam yetkili rol: tüm PMS + bar
insert into public.yetki_matrisi (rol_id, modul_id, yetki)
select 'b0000000-0000-0000-0000-0000000000a1', id, 'tam'::public.yetki_seviye
from public.moduller
where kod in ('pms_oda_tipi','pms_oda','pms_misafir','pms_rezervasyon','pms_folio',
              'bar_siparis_yonetimi','stok_takip','kullanici_yonetimi')
on conflict (rol_id, modul_id) do nothing;

-- Kısıtlı rol: yalnız görüntüleme; FOLYO YETKİSİ YOK (yetki testi için).
insert into public.yetki_matrisi (rol_id, modul_id, yetki)
select 'b0000000-0000-0000-0000-0000000000a2', id, 'goruntule'::public.yetki_seviye
from public.moduller
where kod in ('pms_oda_tipi','pms_oda','pms_misafir','pms_rezervasyon')
on conflict (rol_id, modul_id) do nothing;

insert into public.kullanicilar (id, auth_user_id, rol, rol_id, otel_id, aktif, tum_oteller, ad) values
  ('c0000000-0000-0000-0000-0000000000a1','a0000000-0000-0000-0000-0000000000a1',
   'yonetici','b0000000-0000-0000-0000-0000000000a1','810', true, false, 'QA Tam Yetki'),
  ('c0000000-0000-0000-0000-0000000000a2','a0000000-0000-0000-0000-0000000000a2',
   'depo','b0000000-0000-0000-0000-0000000000a2','810', true, false, 'QA Kisitli'),
  ('c0000000-0000-0000-0000-0000000000a3','a0000000-0000-0000-0000-0000000000a3',
   'yonetici','b0000000-0000-0000-0000-0000000000a1','811', true, false, 'QA 811 Otel')
on conflict (id) do nothing;

-- Bundan SONRAKI tohumlama, denetim izi tetikleyicisinin "aktif ERP
-- personeli" sartini karsilamak icin QA kullanicisi kimligiyle kosar.
-- (Adim 3/4 audit kapsami: rezervasyon, atama, folyo tablolari.)
select set_config('request.jwt.claim.role','authenticated',false);
select set_config('request.jwt.claim.sub','a0000000-0000-0000-0000-0000000000a1',false);

-- Oda tipleri / odalar — iki otel (çapraz otel izolasyonunu ekranda görmek için)
insert into public.pms_oda_tipleri (id, otel_id, kod, ad, azami_kisi, azami_yetiskin) values
  ('d0000000-0000-0000-0000-0000000000a1','810','STD','Standart Oda',2,2),
  ('d0000000-0000-0000-0000-0000000000a2','810','SUIT','Suit',4,3),
  ('d0000000-0000-0000-0000-0000000000a3','811','STD','Standart Oda (811)',2,2)
on conflict (id) do nothing;

insert into public.pms_odalar (id, otel_id, oda_tipi_id, oda_no, kat, temizlik_durumu) values
  ('e0000000-0000-0000-0000-0000000000a1','810','d0000000-0000-0000-0000-0000000000a1','101','1','temiz'),
  ('e0000000-0000-0000-0000-0000000000a2','810','d0000000-0000-0000-0000-0000000000a1','102','1','temiz'),
  ('e0000000-0000-0000-0000-0000000000a3','810','d0000000-0000-0000-0000-0000000000a1','103','1','kirli'),
  ('e0000000-0000-0000-0000-0000000000a4','810','d0000000-0000-0000-0000-0000000000a2','201','2','temiz'),
  ('e0000000-0000-0000-0000-0000000000a5','811','d0000000-0000-0000-0000-0000000000a3','101','1','temiz')
on conflict (id) do nothing;

insert into public.pms_misafirler (id, otel_id, ad, soyad, telefon) values
  ('f0000000-0000-0000-0000-0000000000a1','810','Ahmet','Yilmaz','5550000001'),
  ('f0000000-0000-0000-0000-0000000000a2','810','Elif','Kaya','5550000002'),
  ('f0000000-0000-0000-0000-0000000000a3','811','Mehmet','Demir','5550000003')
on conflict (id) do nothing;

-- Bar menüsü: biri ücretli, biri ikram (oda devri QA'si için)
insert into public.menu_urunler (id, otel_id, ad, fiyat, ucretli, aktif) values
  ('c1000000-0000-0000-0000-0000000000a1','810','Bira',       150.00, true,  true),
  ('c1000000-0000-0000-0000-0000000000a2','810','Ikram Cay',    0.00, false, true)
on conflict (id) do nothing;

-- Rezervasyonlar: biri onaylandi (folyosu otomatik açılır), biri taslak.
insert into public.pms_rezervasyonlar
  (id, otel_id, misafir_id, oda_tipi_id, giris_tarihi, cikis_tarihi, durum, gecelik_fiyat)
values
  ('11000000-0000-0000-0000-0000000000a1','810','f0000000-0000-0000-0000-0000000000a1',
   'd0000000-0000-0000-0000-0000000000a1', current_date - 1, current_date + 2, 'onaylandi', 1200.00),
  ('11000000-0000-0000-0000-0000000000a2','810','f0000000-0000-0000-0000-0000000000a2',
   'd0000000-0000-0000-0000-0000000000a2', current_date + 3, current_date + 5, 'taslak', null)
on conflict (id) do nothing;

-- Fiyatsız bir rezervasyon daha: "gecelik fiyat yok" hata mesajını görmek için.
insert into public.pms_rezervasyonlar
  (id, otel_id, misafir_id, oda_tipi_id, giris_tarihi, cikis_tarihi, durum, gecelik_fiyat)
values
  ('11000000-0000-0000-0000-0000000000a3','810','f0000000-0000-0000-0000-0000000000a2',
   'd0000000-0000-0000-0000-0000000000a1', current_date - 1, current_date + 1, 'onaylandi', null)
on conflict (id) do nothing;
