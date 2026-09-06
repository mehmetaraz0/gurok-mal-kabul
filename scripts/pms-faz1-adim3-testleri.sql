-- ============================================================================
-- PMS FAZ 1 / ADIM 3 — SÖZLEŞME TESTLERİ
-- ============================================================================
-- scripts/pms-faz1-adim3-testleri.mjs tarafından çalıştırılır.
-- Sıra: iskele -> ÜRETİM DÖKÜMÜ -> Adım 1 -> Adım 2 -> Adım 3 (2 kez) -> bu.
-- Üretim veritabanına BAĞLANMAZ.
-- ============================================================================

create schema if not exists pms3_test;

create or replace function pms3_test.dogru(p_deger boolean, p_etiket text)
returns void language plpgsql as $$
begin
  if p_deger is not true then raise exception 'BASARISIZ: %', p_etiket; end if;
end;
$$;

create or replace function pms3_test.reddedilmeli(p_sql text, p_etiket text)
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

grant usage on schema pms3_test to authenticated, anon;

-- ---------------------------------------------------------------------------
-- OTURUM KİMLİĞİ (denetim izi için)
-- ---------------------------------------------------------------------------
-- Adım 3, pms_rezervasyonlar/pms_oda_atamalari üzerine Phase 0 denetim izi
-- tetikleyicisini bağlar; fonksiyon "aktif ERP personeli" şartı arar ve
-- aktörü auth.uid()'den okur. Tezgâh yazmaları süperuser oturumunda yapılır;
-- tetikleyicinin çalışabilmesi için claim'ler BAŞTAN ayarlanır. Gerçek aktör:
-- pms3 810 tam kullanıcısı (aşağıda kullanicilar'a yazılıyor).
select set_config('request.jwt.claim.role','authenticated',false);
select set_config('request.jwt.claim.sub','a0000000-0000-0000-0000-000000000001',false);

-- ---------------------------------------------------------------------------
-- Tezgah: roller, kullanicilar, tipler, odalar, misafirler
-- ---------------------------------------------------------------------------
insert into auth.users (id, email)
select ('a0000000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
       'pms3-' || n || '@ornek.gecersiz'
from generate_series(1, 3) n
on conflict (id) do nothing;

insert into public.roller (id, ad, seviye, kod, aktif) values
  ('b0000000-0000-0000-0000-000000030001','PMS3 Tam',      'otel','pms3_tam',      true),
  ('b0000000-0000-0000-0000-000000030002','PMS3 Yetkisiz', 'otel','pms3_yetkisiz', true)
on conflict (id) do nothing;

insert into public.yetki_matrisi (rol_id, modul_id, yetki)
select 'b0000000-0000-0000-0000-000000030001', id, 'tam'::public.yetki_seviye
from public.moduller
where kod in ('pms_misafir','pms_rezervasyon','pms_oda_tipi','pms_oda')
on conflict (rol_id, modul_id) do nothing;

insert into public.kullanicilar (id, auth_user_id, rol, rol_id, otel_id, aktif, tum_oteller, ad) values
  ('c0000000-0000-0000-0000-000000030001','a0000000-0000-0000-0000-000000000001','yonetici',
   'b0000000-0000-0000-0000-000000030001','810', true, false, 'PMS3 810 tam'),
  ('c0000000-0000-0000-0000-000000030002','a0000000-0000-0000-0000-000000000002','yonetici',
   'b0000000-0000-0000-0000-000000030001','811', true, false, 'PMS3 811 tam'),
  ('c0000000-0000-0000-0000-000000030003','a0000000-0000-0000-0000-000000000003','yonetici',
   'b0000000-0000-0000-0000-000000030002','810', true, false, 'PMS3 810 yetkisiz')
on conflict (id) do nothing;

insert into public.pms_oda_tipleri (id, otel_id, kod, ad, azami_kisi, azami_yetiskin) values
  ('d0000000-0000-0000-0000-000000030010','810','T3A','Adim3 Tip 810',2,2),
  ('d0000000-0000-0000-0000-000000030011','811','T3B','Adim3 Tip 811',2,2)
on conflict (id) do nothing;

insert into public.pms_odalar (id, otel_id, oda_tipi_id, oda_no, kullanim_durumu, temizlik_durumu, aktif) values
  ('e0000000-0000-0000-0000-000000030101','810','d0000000-0000-0000-0000-000000030010','301','bos','temiz',         true),
  ('e0000000-0000-0000-0000-000000030102','810','d0000000-0000-0000-0000-000000030010','302','bos','kirli',         true),
  ('e0000000-0000-0000-0000-000000030103','810','d0000000-0000-0000-0000-000000030010','303','bos','temizleniyor',  true),
  ('e0000000-0000-0000-0000-000000030104','810','d0000000-0000-0000-0000-000000030010','304','bos','kontrol_edildi',true),
  ('e0000000-0000-0000-0000-000000030105','810','d0000000-0000-0000-0000-000000030010','305','bloke','temiz',       true),
  ('e0000000-0000-0000-0000-000000030106','810','d0000000-0000-0000-0000-000000030010','306','ariza','temiz',       true),
  ('e0000000-0000-0000-0000-000000030107','810','d0000000-0000-0000-0000-000000030010','307','bos','temiz',         false),
  ('e0000000-0000-0000-0000-000000030108','810','d0000000-0000-0000-0000-000000030010','308','bos','temiz',         true),
  ('e0000000-0000-0000-0000-000000030109','810','d0000000-0000-0000-0000-000000030010','309','bos','temiz',         true),
  ('e0000000-0000-0000-0000-000000030110','810','d0000000-0000-0000-0000-000000030010','310','bos','temiz',         true),
  ('e0000000-0000-0000-0000-000000030112','810','d0000000-0000-0000-0000-000000030010','312','bos','temiz',         true),
  ('e0000000-0000-0000-0000-000000030113','810','d0000000-0000-0000-0000-000000030010','313','bos','temiz',         true),
  ('e0000000-0000-0000-0000-000000030114','810','d0000000-0000-0000-0000-000000030010','314','bos','temiz',         true),
  ('e0000000-0000-0000-0000-000000030115','810','d0000000-0000-0000-0000-000000030010','315','bos','temiz',         true),
  ('e0000000-0000-0000-0000-000000030116','810','d0000000-0000-0000-0000-000000030010','316','bos','temiz',         true),
  ('e0000000-0000-0000-0000-000000030117','810','d0000000-0000-0000-0000-000000030010','317','bos','temiz',         true),
  ('e0000000-0000-0000-0000-000000030111','811','d0000000-0000-0000-0000-000000030011','311','bos','temiz',         true)
on conflict (id) do nothing;

insert into public.pms_misafirler (id, otel_id, ad, soyad) values
  ('f0000000-0000-0000-0000-000000030001','810','Ayse','Yilmaz'),
  ('f0000000-0000-0000-0000-000000030002','811','Mehmet','Demir')
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- T0 — SAAT DİLİMİ: pms_bugun Europe/Istanbul'a bağlı, session TZ'ye değil
-- ---------------------------------------------------------------------------
select pms3_test.dogru(
  (select public.pms_bugun('810') = (now() at time zone 'Europe/Istanbul')::date),
  'pms_bugun Europe/Istanbul tarihini verir');

set timezone = 'Pacific/Auckland';  -- session TZ bozuk bile olsa
select pms3_test.dogru(
  (select public.pms_bugun('810') = (now() at time zone 'Europe/Istanbul')::date),
  'pms_bugun session timezone icinden etkilenmez');
reset timezone;

-- ---------------------------------------------------------------------------
-- T1 — CHECK-IN MUTLU YOLU
-- ---------------------------------------------------------------------------
insert into public.pms_rezervasyonlar
  (id, otel_id, misafir_id, oda_tipi_id, giris_tarihi, cikis_tarihi, durum)
values ('11000000-0000-0000-0000-000000030001','810','f0000000-0000-0000-0000-000000030001',
        'd0000000-0000-0000-0000-000000030010', current_date, current_date + 2,'onaylandi');

set role authenticated;
select set_config('request.jwt.claim.role','authenticated',false);
select set_config('request.jwt.claim.sub','a0000000-0000-0000-0000-000000000001',false);

select public.pms_check_in('11000000-0000-0000-0000-000000030001',
                           'e0000000-0000-0000-0000-000000030108');

select pms3_test.dogru(
  (select kullanim_durumu = 'dolu' from public.pms_odalar
    where id = 'e0000000-0000-0000-0000-000000030108'),
  'check-in: oda dolu oldu');
select pms3_test.dogru(
  (select durum = 'giris_yapildi' and giris_yapan = 'a0000000-0000-0000-0000-000000000001'
     and giris_zamani is not null
   from public.pms_rezervasyonlar where id = '11000000-0000-0000-0000-000000030001'),
  'check-in: rezervasyon giris_yapildi + damga aktorlu');
select pms3_test.dogru(
  (select count(*) = 1 from public.pms_oda_atamalari
    where rezervasyon_id = '11000000-0000-0000-0000-000000030001' and aktif),
  'check-in: aktif atama acildi');

-- ---------------------------------------------------------------------------
-- T1b — "DÜN GİRMİŞ, BUGÜN ÇIKIŞLI" DURUMUN SAHNELENMESİ
-- ---------------------------------------------------------------------------
-- Bugün check-in yapılabilen tek rezervasyon bugünden SONRA bitendir; oysa
-- normal çıkış senaryosu (çıkış günü oda devri) için dün girip BUGÜN çıkan
-- misafir gerekir. Testte "dünkü" check-in, geçerli ara durumların aynısıyla
-- tek transaction'da sahnelenir: atama acildi -> oda dolu -> rezervasyon
-- giris_yapildi. Bu sırada her ara adım tutarlılık değişmezlerini GEÇER —
-- yani sahneleme, RPC'nin üreteceği durumun birebir aynısıdır.
-- TEK TRANSACTION + ERTELENMİŞ DEĞİŞMEZLER — RPC'nin yaptığının aynısı.
-- Gerekçe: "oda dolu" ile "rezervasyon giris_yapildi" birbirini şart koşar
-- (O1 ve R1). Ayrı ifadelerde yazılırsa hangisi önce gelirse gelsin ara durum
-- değişmezi ihlal eder; pms_check_in de bu yüzden `set constraints deferred`
-- kullanıyor. Sahneleme aynı yolu izlemeli, aksi hâlde RPC'nin üretemeyeceği
-- bir sırayı test etmiş oluruz.
begin;
set constraints pms_tutarlilik_oda, pms_tutarlilik_rezervasyon,
                pms_tutarlilik_atama deferred;

insert into public.pms_rezervasyonlar
  (id, otel_id, misafir_id, oda_tipi_id, giris_tarihi, cikis_tarihi, durum)
values ('11000000-0000-0000-0000-000000030000','810','f0000000-0000-0000-0000-000000030001',
        'd0000000-0000-0000-0000-000000030010', current_date - 1, current_date,'onaylandi');

insert into public.pms_oda_atamalari (otel_id, rezervasyon_id, oda_id, baslangic, bitis)
values ('810','11000000-0000-0000-0000-000000030000','e0000000-0000-0000-0000-000000030109',
        current_date - 1, current_date);

update public.pms_odalar set kullanim_durumu = 'dolu'
 where id = 'e0000000-0000-0000-0000-000000030109';

update public.pms_rezervasyonlar
   set durum = 'giris_yapildi', giris_zamani = now() - interval '1 day',
       giris_yapan = 'a0000000-0000-0000-0000-000000000001'
 where id = '11000000-0000-0000-0000-000000030000';
commit;

select pms3_test.dogru(
  (select durum='giris_yapildi' from public.pms_rezervasyonlar
    where id='11000000-0000-0000-0000-000000030000'),
  'sahneleme: dün girmis misafir durumu kuruldu');

-- ---------------------------------------------------------------------------
-- T2/T3 — HOUSEKEEPING VE ODA DURUMU REDLERİ
-- ---------------------------------------------------------------------------
insert into public.pms_rezervasyonlar
  (id, otel_id, misafir_id, oda_tipi_id, giris_tarihi, cikis_tarihi, durum)
values ('11000000-0000-0000-0000-000000030002','810','f0000000-0000-0000-0000-000000030001',
        'd0000000-0000-0000-0000-000000030010', current_date, current_date + 2,'onaylandi'),
       ('11000000-0000-0000-0000-000000030003','810','f0000000-0000-0000-0000-000000030001',
        'd0000000-0000-0000-0000-000000030010', current_date, current_date + 1,'onaylandi')
on conflict (id) do nothing;

select pms3_test.reddedilmeli($q$
  select public.pms_check_in('11000000-0000-0000-0000-000000030002',
                             'e0000000-0000-0000-0000-000000030102')
$q$, 'kirli odaya check-in reddedilir');

select pms3_test.reddedilmeli($q$
  select public.pms_check_in('11000000-0000-0000-0000-000000030002',
                             'e0000000-0000-0000-0000-000000030103')
$q$, 'temizleniyor odaya check-in reddedilir');

select pms3_test.reddedilmeli($q$
  select public.pms_check_in('11000000-0000-0000-0000-000000030002',
                             'e0000000-0000-0000-0000-000000030105')
$q$, 'bloke odaya check-in reddedilir');

select pms3_test.reddedilmeli($q$
  select public.pms_check_in('11000000-0000-0000-0000-000000030002',
                             'e0000000-0000-0000-0000-000000030106')
$q$, 'ariza odaya check-in reddedilir');

select pms3_test.reddedilmeli($q$
  select public.pms_check_in('11000000-0000-0000-0000-000000030002',
                             'e0000000-0000-0000-0000-000000030107')
$q$, 'pasif odaya check-in reddedilir');

-- Temiz ve kontrol_edildi kabul edilir.
select public.pms_check_in('11000000-0000-0000-0000-000000030002',
                           'e0000000-0000-0000-0000-000000030101');
select public.pms_check_in('11000000-0000-0000-0000-000000030003',
                           'e0000000-0000-0000-0000-000000030104');
select pms3_test.dogru(
  (select count(*) = 2 from public.pms_odalar
    where kullanim_durumu = 'dolu'
      and otel_id = '810'
      and id in ('e0000000-0000-0000-0000-000000030101',
                 'e0000000-0000-0000-0000-000000030104')),
  'temiz ve kontrol_edildi odaya check-in kabul edilir');

-- ---------------------------------------------------------------------------
-- T5 — DOĞRUDAN REST/DML BYPASS: her biri reddedilmeli
-- ---------------------------------------------------------------------------
-- (a) Çıkışı RPC'siz yazmak: oda hâlâ dolu -> R2 reddi.
select pms3_test.reddedilmeli($q$
  update public.pms_rezervasyonlar
     set durum='cikis_yapildi', cikis_zamani=now(),
         cikis_yapan='a0000000-0000-0000-0000-000000000001'
   where id='11000000-0000-0000-0000-000000030001'
$q$, 'BYPASS: giris_yapildi -> cikis_yapildi dogrudan yazilamaz (oda dolu)');

-- (b) Misafir odadayken odayi bosalamak -> O2 reddi.
select pms3_test.reddedilmeli($q$
  update public.pms_odalar set kullanim_durumu='bos'
   where id='e0000000-0000-0000-0000-000000030101'
$q$, 'BYPASS: misafir odada iken oda bosalamaz');

-- (c) Atamasız odayı dolu yapmak -> O1 reddi. (310: sahipsiz temiz oda)
select pms3_test.reddedilmeli($q$
  update public.pms_odalar set kullanim_durumu='dolu'
   where id='e0000000-0000-0000-0000-000000030110'
$q$, 'BYPASS: atamasiz oda dolu isaretlenemez');

-- (d) Atamasız rezervasyonu giris_yapildi yapmak -> R1 reddi.
insert into public.pms_rezervasyonlar
  (id, otel_id, misafir_id, oda_tipi_id, giris_tarihi, cikis_tarihi, durum)
values ('11000000-0000-0000-0000-000000030006','810','f0000000-0000-0000-0000-000000030001',
        'd0000000-0000-0000-0000-000000030010', current_date, current_date + 2,'onaylandi')
on conflict (id) do nothing;
select pms3_test.reddedilmeli($q$
  update public.pms_rezervasyonlar
     set durum='giris_yapildi', giris_zamani=now(),
         giris_yapan='a0000000-0000-0000-0000-000000000001'
   where id='11000000-0000-0000-0000-000000030006'
$q$, 'BYPASS: atamasiz rezervasyon giris_yapildi yapilamaz');

-- (e) Atama var ama odası dolu değil -> R1 reddi. (302: bos ama kirli oda)
insert into public.pms_oda_atamalari (otel_id, rezervasyon_id, oda_id, baslangic, bitis)
values ('810','11000000-0000-0000-0000-000000030006','e0000000-0000-0000-0000-000000030102',
        current_date, current_date + 2);
select pms3_test.reddedilmeli($q$
  update public.pms_rezervasyonlar
     set durum='giris_yapildi', giris_zamani=now(),
         giris_yapan='a0000000-0000-0000-0000-000000000001'
   where id='11000000-0000-0000-0000-000000030006'
$q$, 'BYPASS: atamasi bos odada olan rezervasyon giris_yapildi yapilamaz');

-- Atama pasife alma onaylandi rezervasyonunda serbest.
update public.pms_oda_atamalari set aktif=false
 where rezervasyon_id='11000000-0000-0000-0000-000000030006';
select pms3_test.dogru(
  (select count(*) = 0 from public.pms_oda_atamalari
    where rezervasyon_id='11000000-0000-0000-0000-000000030006' and aktif),
  'onaylandi rezervasyonun atamasi pasiflestirilebilir');

-- (f) Misafir odadayken atamayı pasifleştirmek -> A3 reddi.
select pms3_test.reddedilmeli($q$
  update public.pms_oda_atamalari set aktif=false
   where rezervasyon_id='11000000-0000-0000-0000-000000030001'
$q$, 'BYPASS: misafir odada iken atama pasiflestirilemez');

-- (g) Misafir odadayken atamanın odasını/tarihini değiştirmek -> BEFORE donmuş.
select pms3_test.reddedilmeli($q$
  update public.pms_oda_atamalari set oda_id='e0000000-0000-0000-0000-000000030109'
   where rezervasyon_id='11000000-0000-0000-0000-000000030001' and aktif
$q$, 'BYPASS: konaklama surerken atamanin odasi degistirilemez');

select pms3_test.reddedilmeli($q$
  update public.pms_oda_atamalari set bitis = bitis + 3
   where rezervasyon_id='11000000-0000-0000-0000-000000030001' and aktif
$q$, 'BYPASS: konaklama surerken atamanin tarihleri degistirilemez');

-- (h) Geçiş matrisi.
select pms3_test.reddedilmeli($q$
  update public.pms_rezervasyonlar set durum='iptal'
   where id='11000000-0000-0000-0000-000000030001'
$q$, 'MATRIS: giris_yapildi -> iptal olamaz');

select pms3_test.reddedilmeli($q$
  update public.pms_rezervasyonlar set durum='onaylandi'
   where id='11000000-0000-0000-0000-000000030001'
$q$, 'MATRIS: giris_yapildi -> onaylandi geri donemez');

insert into public.pms_rezervasyonlar
  (id, otel_id, misafir_id, oda_tipi_id, giris_tarihi, cikis_tarihi, durum)
values ('11000000-0000-0000-0000-000000030007','810','f0000000-0000-0000-0000-000000030001',
        'd0000000-0000-0000-0000-000000030010', current_date, current_date + 2,'taslak')
on conflict (id) do nothing;
select pms3_test.reddedilmeli($q$
  update public.pms_rezervasyonlar
     set durum='giris_yapildi', giris_zamani=now(),
         giris_yapan='a0000000-0000-0000-0000-000000000001'
   where id='11000000-0000-0000-0000-000000030007'
$q$, 'MATRIS: taslak -> giris_yapildi dogrudan olamaz (once onaylandi)');

-- (i) Damgalar donmuş.
select pms3_test.reddedilmeli($q$
  update public.pms_rezervasyonlar set giris_zamani = now() + interval '1 hour'
   where id='11000000-0000-0000-0000-000000030001'
$q$, 'DONMUS: giris_zamani sonradan degistirilemez');

select pms3_test.reddedilmeli($q$
  update public.pms_rezervasyonlar set giris_yapan='a0000000-0000-0000-0000-000000000002'
   where id='11000000-0000-0000-0000-000000030001'
$q$, 'DONMUS: giris_yapan sonradan degistirilemez');

-- (j) Çekirdek alanlar konaklama sürerken donmuş.
select pms3_test.reddedilmeli($q$
  update public.pms_rezervasyonlar set cikis_tarihi = current_date + 5
   where id='11000000-0000-0000-0000-000000030001'
$q$, 'DONMUS: konaklama surerken cikis tarihi degistirilemez');

select pms3_test.reddedilmeli($q$
  update public.pms_rezervasyonlar set oda_tipi_id='d0000000-0000-0000-0000-000000030011'
   where id='11000000-0000-0000-0000-000000030001'
$q$, 'CAPRAZ OTEL + DONMUS: konaklama surerken tip degistirilemez');

-- (k) Oda geçiş matrisi.
select pms3_test.reddedilmeli($q$
  update public.pms_odalar set kullanim_durumu='bloke'
   where id='e0000000-0000-0000-0000-000000030101'
$q$, 'MATRIS: dolu oda bloke yapilamaz');

select pms3_test.reddedilmeli($q$
  update public.pms_odalar set kullanim_durumu='ariza'
   where id='e0000000-0000-0000-0000-000000030101'
$q$, 'MATRIS: dolu oda ariza yapilamaz');

select pms3_test.reddedilmeli($q$
  update public.pms_odalar set kullanim_durumu='bos', temizlik_durumu='temiz'
   where id='e0000000-0000-0000-0000-000000030101'
$q$, 'MATRIS: cikan oda kirli isaretlenmeden bosalamaz');

-- ---------------------------------------------------------------------------
-- T6 — CHECK-OUT MUTLU YOLU: atama AKTİF KALIR (geçmiş kayıt)
-- ---------------------------------------------------------------------------
select public.pms_check_out('11000000-0000-0000-0000-000000030000');

select pms3_test.dogru(
  (select durum='cikis_yapildi' and cikis_yapan='a0000000-0000-0000-0000-000000000001'
     and cikis_zamani is not null
   from public.pms_rezervasyonlar where id='11000000-0000-0000-0000-000000030000'),
  'check-out: rezervasyon cikis_yapildi + damga');

select pms3_test.dogru(
  (select kullanim_durumu='bos' and temizlik_durumu='kirli'
   from public.pms_odalar where id='e0000000-0000-0000-0000-000000030109'),
  'check-out: oda bos + kirli dogdu');

select pms3_test.dogru(
  (select count(*) = 1 from public.pms_oda_atamalari
    where rezervasyon_id='11000000-0000-0000-0000-000000030000' and aktif),
  'check-out: atama AKTIF KALDI (gecmis konaklama kaydi)');

select pms3_test.reddedilmeli($q$
  select public.pms_check_out('11000000-0000-0000-0000-000000030000')
$q$, 'check-out: ikinci cikis reddedilir');

-- ---------------------------------------------------------------------------
-- T7 — ÇIKIŞ GÜNÜ AYNI ODAYA YENİ GİRİŞ
-- ---------------------------------------------------------------------------
-- 309 bos+kirli; kat hizmeti temizler (RPC'siz, doğrudan PATCH - bos odada serbest).
update public.pms_odalar set temizlik_durumu='temiz'
 where id='e0000000-0000-0000-0000-000000030109';
select pms3_test.dogru(
  (select kullanim_durumu='bos' and temizlik_durumu='temiz'
   from public.pms_odalar where id='e0000000-0000-0000-0000-000000030109'),
  'bos odada temizlik guncellemesi serbest');

insert into public.pms_rezervasyonlar
  (id, otel_id, misafir_id, oda_tipi_id, giris_tarihi, cikis_tarihi, durum)
values ('11000000-0000-0000-0000-000000030008','810','f0000000-0000-0000-0000-000000030001',
        'd0000000-0000-0000-0000-000000030010', current_date, current_date + 3,'onaylandi')
on conflict (id) do nothing;

select public.pms_check_in('11000000-0000-0000-0000-000000030008',
                           'e0000000-0000-0000-0000-000000030109');
select pms3_test.dogru(
  (select kullanim_durumu='dolu' from public.pms_odalar
    where id='e0000000-0000-0000-0000-000000030109'),
  'CIKIS GUNU: ayni odaya yeni giris kabul edilir ([) yari acik aralik)');

-- ---------------------------------------------------------------------------
-- T7b — GECİKMİŞ CHECK-OUT (B1): planlanan çıkış günü geçse de çıkış yapılır
-- ---------------------------------------------------------------------------
-- "Takvim ilerledi" simülasyonu: geçerli konaklama state'i RPC ile kurulur;
-- sonra planlanan çıkış tarihi, tetikleyiciler devre dışı bırakılarak
-- (session_replication_role = replica — YALNIZ test, süperuser) geride
-- bırakılır. Gerçek işletmede bu durum takvimin kendi ilerlemesiyle oluşur;
-- replica hilesi yalnızca sahneleme içindir, RPC yollarına dokunmaz.

-- (B) Planlanan çıkıştan 1 GÜN sonra.
insert into public.pms_rezervasyonlar
  (id, otel_id, misafir_id, oda_tipi_id, giris_tarihi, cikis_tarihi, durum)
values ('11000000-0000-0000-0000-000000030030','810','f0000000-0000-0000-0000-000000030001',
        'd0000000-0000-0000-0000-000000030010', current_date - 3, current_date + 2,'onaylandi')
on conflict (id) do nothing;
select public.pms_check_in('11000000-0000-0000-0000-000000030030',
                           'e0000000-0000-0000-0000-000000030112');

reset role;
set session_replication_role = replica;
update public.pms_rezervasyonlar set cikis_tarihi = current_date - 1
 where id = '11000000-0000-0000-0000-000000030030';
update public.pms_oda_atamalari set bitis = current_date - 1
 where rezervasyon_id = '11000000-0000-0000-0000-000000030030' and aktif;
set session_replication_role = origin;
set role authenticated;
select set_config('request.jwt.claim.role','authenticated',false);
select set_config('request.jwt.claim.sub','a0000000-0000-0000-0000-000000000001',false);

select public.pms_check_out('11000000-0000-0000-0000-000000030030');
select pms3_test.dogru(
  (select durum='cikis_yapildi' and cikis_yapan='a0000000-0000-0000-0000-000000000001'
     and cikis_zamani is not null
   from public.pms_rezervasyonlar where id='11000000-0000-0000-0000-000000030030'),
  'GECIKMIS (1 gun): cikis kabul edildi + gercek damga');
select pms3_test.dogru(
  (select kullanim_durumu='bos' and temizlik_durumu='kirli'
   from public.pms_odalar where id='e0000000-0000-0000-0000-000000030112'),
  'GECIKMIS (1 gun): oda bos + kirli');
select pms3_test.dogru(
  (select count(*) = 1 from public.pms_oda_atamalari
    where rezervasyon_id='11000000-0000-0000-0000-000000030030' and aktif
      and bitis = current_date - 1),
  'GECIKMIS (1 gun): gecmis atama korunuyor, planlanan aralik degismedi');

-- (C) Planlanan çıkıştan BİRKAÇ gün sonra (3 gün). Giriş, sahnelemeden önce
--     çıkıştan önce olmalı: [d-6, d+2) kurulur, çıkış d-3'e geriletir.
insert into public.pms_rezervasyonlar
  (id, otel_id, misafir_id, oda_tipi_id, giris_tarihi, cikis_tarihi, durum)
values ('11000000-0000-0000-0000-000000030031','810','f0000000-0000-0000-0000-000000030001',
        'd0000000-0000-0000-0000-000000030010', current_date - 6, current_date + 2,'onaylandi')
on conflict (id) do nothing;
select public.pms_check_in('11000000-0000-0000-0000-000000030031',
                           'e0000000-0000-0000-0000-000000030113');

reset role;
set session_replication_role = replica;
update public.pms_rezervasyonlar set cikis_tarihi = current_date - 3
 where id = '11000000-0000-0000-0000-000000030031';
update public.pms_oda_atamalari set bitis = current_date - 3
 where rezervasyon_id = '11000000-0000-0000-0000-000000030031' and aktif;
set session_replication_role = origin;
set role authenticated;
select set_config('request.jwt.claim.role','authenticated',false);
select set_config('request.jwt.claim.sub','a0000000-0000-0000-0000-000000000001',false);

select public.pms_check_out('11000000-0000-0000-0000-000000030031');
select pms3_test.dogru(
  (select durum='cikis_yapildi' from public.pms_rezervasyonlar
    where id='11000000-0000-0000-0000-000000030031'),
  'GECIKMIS (4 gun): cikis kabul edildi');

-- (F) checked-in rezervasyonun 0 aktif ataması -> açık tutarsızlık hatası.
insert into public.pms_rezervasyonlar
  (id, otel_id, misafir_id, oda_tipi_id, giris_tarihi, cikis_tarihi, durum)
values ('11000000-0000-0000-0000-000000030032','810','f0000000-0000-0000-0000-000000030001',
        'd0000000-0000-0000-0000-000000030010', current_date, current_date + 2,'onaylandi')
on conflict (id) do nothing;
select public.pms_check_in('11000000-0000-0000-0000-000000030032',
                           'e0000000-0000-0000-0000-000000030114');

reset role;
set session_replication_role = replica;
update public.pms_oda_atamalari set aktif = false
 where rezervasyon_id = '11000000-0000-0000-0000-000000030032';
set session_replication_role = origin;
set role authenticated;
select set_config('request.jwt.claim.role','authenticated',false);
select set_config('request.jwt.claim.sub','a0000000-0000-0000-0000-000000000001',false);

select pms3_test.reddedilmeli($q$
  select public.pms_check_out('11000000-0000-0000-0000-000000030032')
$q$, 'TUTARSIZLIK: 0 aktif atamali check-in rezervasyonundan cikis reddedilir');

-- (G) checked-in rezervasyonun >1 aktif ataması -> açık tutarsızlık hatası;
--     sessizce ilki SEÇİLMEZ.
insert into public.pms_rezervasyonlar
  (id, otel_id, misafir_id, oda_tipi_id, giris_tarihi, cikis_tarihi, durum)
values ('11000000-0000-0000-0000-000000030033','810','f0000000-0000-0000-0000-000000030001',
        'd0000000-0000-0000-0000-000000030010', current_date, current_date + 2,'onaylandi')
on conflict (id) do nothing;
select public.pms_check_in('11000000-0000-0000-0000-000000030033',
                           'e0000000-0000-0000-0000-000000030115');

reset role;
set session_replication_role = replica;
insert into public.pms_oda_atamalari (otel_id, rezervasyon_id, oda_id, baslangic, bitis)
values ('810','11000000-0000-0000-0000-000000030033','e0000000-0000-0000-0000-000000030116',
        current_date, current_date + 2);
set session_replication_role = origin;
set role authenticated;
select set_config('request.jwt.claim.role','authenticated',false);
select set_config('request.jwt.claim.sub','a0000000-0000-0000-0000-000000000001',false);

select pms3_test.reddedilmeli($q$
  select public.pms_check_out('11000000-0000-0000-0000-000000030033')
$q$, 'TUTARSIZLIK: 2 aktif atamali check-in rezervasyonundan cikis reddedilir');

-- (J) ERKEN ÇIKIŞ: mevcut bilinçli davranış DEĞİŞMEDİ — atama aktif kalır,
--     kalan geceler exclusion nedeniyle yeniden satılamaz.
insert into public.pms_rezervasyonlar
  (id, otel_id, misafir_id, oda_tipi_id, giris_tarihi, cikis_tarihi, durum)
values ('11000000-0000-0000-0000-000000030035','810','f0000000-0000-0000-0000-000000030001',
        'd0000000-0000-0000-0000-000000030010', current_date, current_date + 3,'onaylandi'),
       ('11000000-0000-0000-0000-000000030036','810','f0000000-0000-0000-0000-000000030001',
        'd0000000-0000-0000-0000-000000030010', current_date + 1, current_date + 3,'onaylandi')
on conflict (id) do nothing;
select public.pms_check_in('11000000-0000-0000-0000-000000030035',
                           'e0000000-0000-0000-0000-000000030117');
select public.pms_check_out('11000000-0000-0000-0000-000000030035');
select pms3_test.dogru(
  (select count(*) = 1 from public.pms_oda_atamalari
    where rezervasyon_id='11000000-0000-0000-0000-000000030035' and aktif
      and bitis = current_date + 3),
  'ERKEN CIKIS: atama tam aralikta aktif kaldi');
select pms3_test.reddedilmeli($q$
  insert into public.pms_oda_atamalari (otel_id, rezervasyon_id, oda_id, baslangic, bitis)
  values ('810','11000000-0000-0000-0000-000000030036','e0000000-0000-0000-0000-000000030117',
          current_date + 1, current_date + 3)
$q$, 'ERKEN CIKIS: kalan geceler hala satilamaz (bilincli sinirlama)');

-- ---------------------------------------------------------------------------
-- ---------------------------------------------------------------------------
-- T7d — GECİKMİŞ KONAKLAMA SIRASINDA SATIRLAR DONMAMALI
-- ---------------------------------------------------------------------------
-- B1 "bugünü kapsayan atama" varsayımını pms_check_out'tan kaldırmıştı ama
-- değişmez katmanında (O1, R1, R2, A2) bırakmıştı. Sonuç: planlanan çıkış
-- geçtiği anda oda ve rezervasyon satırları TAMAMEN donuyordu — kat hizmetleri
-- temizlik durumunu güncelleyemiyor, resepsiyon nota bile dokunamıyordu.
--
-- GÜNCEL KONAKLAMA artık tarihten değil, DURUMDAN türetilir:
--     atama.aktif = true  VE  rezervasyon.durum = 'giris_yapildi'
--
-- Tarih kısıtları veri bütünlüğü için yerinde durur (aralık geçerliliği,
-- rezervasyon aralığına uyum, exclusion). Yalnız "şu anda konaklama sürüyor
-- mu" sorusunda tarih kullanılmaz.

insert into public.pms_odalar (id, otel_id, oda_tipi_id, oda_no, temizlik_durumu)
values ('e0000000-0000-0000-0000-000000030131','810','d0000000-0000-0000-0000-000000030010',
        '330','temiz')
on conflict (id) do nothing;

insert into public.pms_rezervasyonlar
  (id, otel_id, misafir_id, oda_tipi_id, giris_tarihi, cikis_tarihi, durum)
values ('11000000-0000-0000-0000-000000030050','810','f0000000-0000-0000-0000-000000030001',
        'd0000000-0000-0000-0000-000000030010', current_date - 3, current_date + 2,'onaylandi')
on conflict (id) do nothing;
select public.pms_check_in('11000000-0000-0000-0000-000000030050',
                           'e0000000-0000-0000-0000-000000030131');

-- Takvimi ilerlet: planlanan çıkış DÜN kaldı, misafir hâlâ içeride.
reset role;
set session_replication_role = replica;
update public.pms_rezervasyonlar set cikis_tarihi = current_date - 1
 where id = '11000000-0000-0000-0000-000000030050';
update public.pms_oda_atamalari set bitis = current_date - 1
 where rezervasyon_id = '11000000-0000-0000-0000-000000030050' and aktif;
set session_replication_role = origin;
set role authenticated;
select set_config('request.jwt.claim.role','authenticated',false);
select set_config('request.jwt.claim.sub','a0000000-0000-0000-0000-000000000001',false);

-- (A) OVERDUE HOUSEKEEPING — meşru operasyonel güncelleme GEÇMELİ.
update public.pms_odalar set temizlik_durumu = 'temizleniyor'
 where id = 'e0000000-0000-0000-0000-000000030131';
select pms3_test.dogru(
  (select temizlik_durumu = 'temizleniyor' from public.pms_odalar
    where id = 'e0000000-0000-0000-0000-000000030131'),
  'A) GECIKMIS: housekeeping durumu guncellenebilir');

-- (B) OVERDUE RESERVATION NOTE — çekirdek olmayan alan GEÇMELİ.
update public.pms_rezervasyonlar set notlar = 'Gec cikis: misafir odada'
 where id = '11000000-0000-0000-0000-000000030050';
select pms3_test.dogru(
  (select notlar = 'Gec cikis: misafir odada' from public.pms_rezervasyonlar
    where id = '11000000-0000-0000-0000-000000030050'),
  'B) GECIKMIS: rezervasyon notu guncellenebilir');

-- (C) OVERDUE CORE DATE CHANGE — çekirdek alan hâlâ DONUK olmalı.
-- B1 düzeltmesi bu korumayı gevşetmemeli.
select pms3_test.reddedilmeli($q$
  update public.pms_rezervasyonlar set cikis_tarihi = current_date + 5
   where id = '11000000-0000-0000-0000-000000030050'
$q$, 'C) GECIKMIS: cikis_tarihi konaklama surerken degistirilemez');
select pms3_test.reddedilmeli($q$
  update public.pms_rezervasyonlar set giris_tarihi = current_date - 10
   where id = '11000000-0000-0000-0000-000000030050'
$q$, 'C) GECIKMIS: giris_tarihi konaklama surerken degistirilemez');

-- (D) DIRECT VACANT BYPASS — check-out state makinesi atlanamaz.
select pms3_test.reddedilmeli($q$
  update public.pms_odalar set kullanim_durumu = 'bos', temizlik_durumu = 'kirli'
   where id = 'e0000000-0000-0000-0000-000000030131'
$q$, 'D) GECIKMIS: oda dogrudan bos yapilamaz (checkout bypass)');

-- (E) NORMAL CHECKOUT — gecikmiş konaklama RPC ile kapanmalı.
select public.pms_check_out('11000000-0000-0000-0000-000000030050');
select pms3_test.dogru(
  (select durum = 'cikis_yapildi' and cikis_zamani is not null
     from public.pms_rezervasyonlar where id = '11000000-0000-0000-0000-000000030050'),
  'E) GECIKMIS: check-out kabul edildi + gercek damga');
select pms3_test.dogru(
  (select kullanim_durumu = 'bos' and temizlik_durumu = 'kirli'
     from public.pms_odalar where id = 'e0000000-0000-0000-0000-000000030131'),
  'E) GECIKMIS: oda bos + kirli');
select pms3_test.dogru(
  (select count(*) = 1 from public.pms_oda_atamalari
    where rezervasyon_id = '11000000-0000-0000-0000-000000030050'
      and aktif and bitis = current_date - 1),
  'E) GECIKMIS: gecmis atama aktif kaldi, planlanan aralik degismedi');

-- (F) POST-CHECKOUT HISTORICAL ASSIGNMENT — atama aktif ama GÜNCEL DOLULUK DEĞİL.
select pms3_test.dogru(
  (select count(*) = 1 from public.pms_oda_atamalari
    where oda_id = 'e0000000-0000-0000-0000-000000030131' and aktif)
  and (select count(*) = 0
         from public.pms_oda_atamalari a
         join public.pms_rezervasyonlar r
           on r.id = a.rezervasyon_id and r.otel_id = a.otel_id
        where a.oda_id = 'e0000000-0000-0000-0000-000000030131' and a.aktif
          and r.durum = 'giris_yapildi'),
  'F) CIKIS SONRASI: atama aktif ama guncel doluluk sayilmiyor');

-- Aynı şeyin davranışsal kanıtı: oda artık operasyonel dışına alınabilir.
-- (Misafir içerideyken bu reddedilirdi.)
update public.pms_odalar set kullanim_durumu = 'bloke'
 where id = 'e0000000-0000-0000-0000-000000030131';
select pms3_test.dogru(
  (select kullanim_durumu = 'bloke' from public.pms_odalar
    where id = 'e0000000-0000-0000-0000-000000030131'),
  'F) CIKIS SONRASI: oda bloke edilebilir (misafir icerideyken reddedilirdi)');
update public.pms_odalar set kullanim_durumu = 'bos'
 where id = 'e0000000-0000-0000-0000-000000030131';

-- ---------------------------------------------------------------------------
-- T7c — DENETİM İZİ KANITI (Phase 0 tetikleyicisi PMS yazmalarında çalışıyor)
-- ---------------------------------------------------------------------------
-- DÖKÜM DERSİ: erp_islem_audit'in SELECT politikası 'denetim_izi' yetkisi
-- ister; pms3 rolünde o yetki YOK. RLS satırı GİZLER — sayım 0 döner,
-- satır olmadığı için değil. Sayım SAHİP ROLÜYLE yapılır.
reset role;

select pms3_test.dogru(
  (select count(*) >= 1 from public.erp_islem_audit
    where entity_type = 'pms_oda_atamalari' and event_type = 'INSERT'),
  'AUDIT: atama INSERT izi uretildi');
select pms3_test.dogru(
  (select count(*) >= 1 from public.erp_islem_audit
    where entity_type = 'pms_rezervasyonlar' and event_type = 'UPDATE'),
  'AUDIT: rezervasyon gecis (UPDATE) izi uretildi');
select pms3_test.dogru(
  (select count(*) >= 1 from public.erp_islem_audit
    where entity_type = 'pms_rezervasyonlar'
      and actor_user_id = 'a0000000-0000-0000-0000-000000000001'
      and hotel_id::text = '810' and transaction_id is not null),
  'AUDIT: aktor + hotel_id + transaction_id dolu');
select pms3_test.dogru(
  (select count(*) = 0 from public.erp_islem_audit
    where entity_type in ('pms_misafirler','pms_misafir_kimlik')),
  'AUDIT: kisisel veri tablolari kapsam disi');

-- ---------------------------------------------------------------------------
-- T8 — İPTAL / GELMEDİ ATAMAYI SERBEST BIRAKIR; YENİDEN AKTİFLEŞMEZ
-- ---------------------------------------------------------------------------
insert into public.pms_rezervasyonlar
  (id, otel_id, misafir_id, oda_tipi_id, giris_tarihi, cikis_tarihi, durum)
values ('11000000-0000-0000-0000-000000030009','810','f0000000-0000-0000-0000-000000030001',
        'd0000000-0000-0000-0000-000000030010', current_date, current_date + 2,'onaylandi'),
       ('11000000-0000-0000-0000-00000003000a','810','f0000000-0000-0000-0000-000000030001',
        'd0000000-0000-0000-0000-000000030010', current_date + 1, current_date + 3,'onaylandi')
on conflict (id) do nothing;

insert into public.pms_oda_atamalari (otel_id, rezervasyon_id, oda_id, baslangic, bitis) values
  ('810','11000000-0000-0000-0000-000000030009','e0000000-0000-0000-0000-000000030102',
   current_date, current_date + 2);

update public.pms_rezervasyonlar set durum='iptal'
 where id='11000000-0000-0000-0000-000000030009';
select pms3_test.dogru(
  (select count(*) = 0 from public.pms_oda_atamalari
    where rezervasyon_id='11000000-0000-0000-0000-000000030009' and aktif),
  'IPTAL: atama otomatik pasiflesti');

select pms3_test.reddedilmeli($q$
  update public.pms_oda_atamalari set aktif=true
   where rezervasyon_id='11000000-0000-0000-0000-000000030009'
$q$, 'IPTAL: iptal rezervasyonun atamasi yeniden aktiflesemez');

-- R102 simdi serbest: ikinci rezervasyonun atamasi oraya acilir.
insert into public.pms_oda_atamalari (otel_id, rezervasyon_id, oda_id, baslangic, bitis) values
  ('810','11000000-0000-0000-0000-00000003000a','e0000000-0000-0000-0000-000000030102',
   current_date + 1, current_date + 3);

update public.pms_rezervasyonlar set durum='gelmedi'
 where id='11000000-0000-0000-0000-00000003000a';
select pms3_test.dogru(
  (select count(*) = 0 from public.pms_oda_atamalari
    where rezervasyon_id='11000000-0000-0000-0000-00000003000a' and aktif),
  'GELMEDI: atama otomatik pasiflesti');

-- ---------------------------------------------------------------------------
-- T11 — TARİH DENETİMİ
-- ---------------------------------------------------------------------------
insert into public.pms_rezervasyonlar
  (id, otel_id, misafir_id, oda_tipi_id, giris_tarihi, cikis_tarihi, durum)
values ('11000000-0000-0000-0000-00000003000b','810','f0000000-0000-0000-0000-000000030001',
        'd0000000-0000-0000-0000-000000030010', current_date + 3, current_date + 5,'onaylandi'),
       ('11000000-0000-0000-0000-00000003000c','810','f0000000-0000-0000-0000-000000030001',
        'd0000000-0000-0000-0000-000000030010', current_date - 5, current_date - 2,'onaylandi')
on conflict (id) do nothing;

select pms3_test.reddedilmeli($q$
  select public.pms_check_in('11000000-0000-0000-0000-00000003000b',
                             'e0000000-0000-0000-0000-000000030109')
$q$, 'TARIH: giris tarihi bugunden ileride, check-in reddedilir');

select pms3_test.reddedilmeli($q$
  select public.pms_check_in('11000000-0000-0000-0000-00000003000c',
                             'e0000000-0000-0000-0000-000000030109')
$q$, 'TARIH: cikis tarihi gecmis, check-in reddedilir');

-- ---------------------------------------------------------------------------
-- T9 — YETKİ: RPC INVOKER, RLS + modul yetkisi devrede
-- ---------------------------------------------------------------------------
-- Yetkisiz kullanici (rolunde pms modul yetkisi yok).
select set_config('request.jwt.claim.sub','a0000000-0000-0000-0000-000000000003',false);
select pms3_test.reddedilmeli($q$
  select public.pms_check_in('11000000-0000-0000-0000-00000003000b',
                             'e0000000-0000-0000-0000-000000030109')
$q$, 'YETKI: yetkisiz kullanici check-in yapamaz');

-- Baska otelin kullanicisi 810 rezervasyonunu HIC GOREMEZ (RLS).
select set_config('request.jwt.claim.sub','a0000000-0000-0000-0000-000000000002',false);
select pms3_test.reddedilmeli($q$
  select public.pms_check_in('11000000-0000-0000-0000-00000003000b',
                             'e0000000-0000-0000-0000-000000030111')
$q$, 'OTEL: 811 kullanicisi 810 rezervasyonuna check-in yapamaz (RLS gizler)');

-- 811 kendi odasina kendi misafirini alabilir.
insert into public.pms_rezervasyonlar
  (id, otel_id, misafir_id, oda_tipi_id, giris_tarihi, cikis_tarihi, durum)
values ('11000000-0000-0000-0000-00000003000d','811','f0000000-0000-0000-0000-000000030002',
        'd0000000-0000-0000-0000-000000030011', current_date, current_date + 2,'onaylandi')
on conflict (id) do nothing;
select public.pms_check_in('11000000-0000-0000-0000-00000003000d',
                           'e0000000-0000-0000-0000-000000030111');
select pms3_test.dogru(
  (select kullanim_durumu='dolu' from public.pms_odalar
    where id='e0000000-0000-0000-0000-000000030111'),
  'OTEL: 811 kullanicisi 811 odasina check-in yapabilir');

reset role;

-- ---------------------------------------------------------------------------
-- T10 — ANON: RPC hicbir sekilde calistirilamaz
-- ---------------------------------------------------------------------------
set role anon;
select set_config('request.jwt.claim.role','anon',false);
select pms3_test.reddedilmeli($q$
  select public.pms_check_in('11000000-0000-0000-0000-00000003000b',
                             'e0000000-0000-0000-0000-000000030109')
$q$, 'ANON: check-in RPC calistirilamaz');
select pms3_test.reddedilmeli($q$
  select public.pms_check_out('11000000-0000-0000-0000-000000030001')
$q$, 'ANON: check-out RPC calistirilamaz');
reset role;

-- ---------------------------------------------------------------------------
-- NİHAİ SAYIM — satir sayisi OLCULUR (dunku ders: "istisna yok" kanit degil)
-- ---------------------------------------------------------------------------
select pms3_test.dogru(
  (select count(*) from public.pms_odalar where otel_id='810' and kullanim_durumu='dolu') = 6,
  'final: 810 otelinde 6 dolu oda (301, 304, 308, 309, 314, 315)');
select pms3_test.dogru(
  (select count(*) from public.pms_rezervasyonlar
    where otel_id='810' and durum='giris_yapildi') = 6
  and (select count(*) from public.pms_rezervasyonlar
       where otel_id='810' and durum='cikis_yapildi') = 5,
  'final: durum sayilari beklenen gibi (T7d gecikmis cikis dahil)');

select 'TUM PMS ADIM 3 TESTLERI GECTI' as sonuc;
