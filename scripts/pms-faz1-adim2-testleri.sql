-- ============================================================================
-- PMS FAZ 1 / ADIM 2 — SÖZLEŞME TESTLERİ
-- ============================================================================
-- scripts/pms-faz1-adim2-testleri.mjs tarafından çalıştırılır.
-- Sıra: iskele -> ÜRETİM DÖKÜMÜ -> Adım 1 migration -> Adım 2 migration -> bu dosya.
-- Üretim veritabanına BAĞLANMAZ.
-- ============================================================================

create schema if not exists pms2_test;

create or replace function pms2_test.dogru(p_deger boolean, p_etiket text)
returns void language plpgsql as $$
begin
  if p_deger is not true then raise exception 'BASARISIZ: %', p_etiket; end if;
end;
$$;

-- Kabul edilen reddetme bicimleri: yetki, kisit, veri, exclusion ve
-- tetikleyicinin acik reddi. Hangisiyle reddettigi degil, GECEMEDIGI onemli.
create or replace function pms2_test.reddedilmeli(p_sql text, p_etiket text)
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

grant usage on schema pms2_test to authenticated, anon;

-- ---------------------------------------------------------------------------
-- Tezgah: roller, kullanicilar, oda tipleri, odalar
-- ---------------------------------------------------------------------------
insert into auth.users (id, email)
select ('a0000000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
       'pms2-' || n || '@ornek.gecersiz'
from generate_series(1, 4) n
on conflict (id) do nothing;

-- Rol 1: misafir + rezervasyon TAM, kimlik YOK  (tipik resepsiyon disi personel)
insert into public.roller (id, ad, seviye, kod, aktif) values
  ('b0000000-0000-0000-0000-000000000001','PMS2 Kimliksiz','otel','pms2_kimliksiz',true),
  ('b0000000-0000-0000-0000-000000000002','PMS2 Tam',      'otel','pms2_tam',      true)
on conflict (id) do nothing;

insert into public.yetki_matrisi (rol_id, modul_id, yetki)
select 'b0000000-0000-0000-0000-000000000001', id, 'tam'::public.yetki_seviye
from public.moduller where kod in ('pms_misafir','pms_rezervasyon','pms_oda_tipi','pms_oda')
on conflict (rol_id, modul_id) do nothing;

-- Rol 2: kimlik dahil her sey
insert into public.yetki_matrisi (rol_id, modul_id, yetki)
select 'b0000000-0000-0000-0000-000000000002', id, 'tam'::public.yetki_seviye
from public.moduller
where kod in ('pms_misafir','pms_misafir_kimlik','pms_rezervasyon','pms_oda_tipi','pms_oda')
on conflict (rol_id, modul_id) do nothing;

insert into public.kullanicilar (id, auth_user_id, rol, rol_id, otel_id, aktif, tum_oteller, ad) values
  ('c0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','yonetici',
   'b0000000-0000-0000-0000-000000000001','810', true, false, 'PMS2 810 kimliksiz'),
  ('c0000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000002','yonetici',
   'b0000000-0000-0000-0000-000000000002','810', true, false, 'PMS2 810 tam'),
  ('c0000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000003','yonetici',
   'b0000000-0000-0000-0000-000000000002','811', true, false, 'PMS2 811 tam')
on conflict (id) do nothing;

-- Oda tipleri: OVS'de TEK oda var -> asiri satis testinin zemini.
insert into public.pms_oda_tipleri (id, otel_id, kod, ad, azami_kisi, azami_yetiskin, azami_cocuk) values
  ('d0000000-0000-0000-0000-000000000810','810','OVS','Tek Odali Tip',2,2,1),
  ('d0000000-0000-0000-0000-000000000811','811','OVS','Tek Odali Tip',2,2,1),
  ('d0000000-0000-0000-0000-00000000ff10','810','GNS','Genis Tip',4,3,2)
on conflict (id) do nothing;

insert into public.pms_odalar (id, otel_id, oda_tipi_id, oda_no) values
  ('e0000000-0000-0000-0000-000000000810','810','d0000000-0000-0000-0000-000000000810','OVS-1'),
  ('e0000000-0000-0000-0000-000000000811','811','d0000000-0000-0000-0000-000000000811','OVS-1'),
  ('e0000000-0000-0000-0000-00000000ff10','810','d0000000-0000-0000-0000-00000000ff10','GNS-1'),
  ('e0000000-0000-0000-0000-00000000ff11','810','d0000000-0000-0000-0000-00000000ff10','GNS-2')
on conflict (id) do nothing;

insert into public.pms_misafirler (id, otel_id, ad, soyad, uyruk) values
  ('f0000000-0000-0000-0000-000000000810','810','Ayse','Yilmaz','TR'),
  ('f0000000-0000-0000-0000-000000000811','811','Mehmet','Demir','TR')
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- MISAFIR: bicim kisitlari
-- ---------------------------------------------------------------------------
select pms2_test.reddedilmeli($q$
  insert into public.pms_misafirler (otel_id, ad, soyad) values ('810',' Ayse','Yilmaz')
$q$, 'misafir adi kirpilmamis olamaz');

select pms2_test.reddedilmeli($q$
  insert into public.pms_misafirler (otel_id, ad, soyad, eposta)
  values ('810','Ali','Veli','gecersiz-eposta')
$q$, 'eposta @ icermeli');

select pms2_test.reddedilmeli($q$
  insert into public.pms_misafirler (otel_id, ad, soyad, dogum_tarihi)
  values ('810','Ali','Veli', current_date + 1)
$q$, 'dogum tarihi gelecekte olamaz');

-- ---------------------------------------------------------------------------
-- KIMLIK: bicim, benzersizlik, capraz otel
-- ---------------------------------------------------------------------------
insert into public.pms_misafir_kimlik (otel_id, misafir_id, belge_tipi, belge_no)
values ('810','f0000000-0000-0000-0000-000000000810','tc_kimlik','12345678901');

select pms2_test.reddedilmeli($q$
  insert into public.pms_misafir_kimlik (otel_id, misafir_id, belge_tipi, belge_no)
  values ('810','f0000000-0000-0000-0000-000000000810','tc_kimlik','123')
$q$, 'TC kimlik 11 hane olmali');

select pms2_test.reddedilmeli($q$
  insert into public.pms_misafir_kimlik (otel_id, misafir_id, belge_tipi, belge_no)
  values ('810','f0000000-0000-0000-0000-000000000810','tc_kimlik','02345678901')
$q$, 'TC kimlik 0 ile baslayamaz');

select pms2_test.reddedilmeli($q$
  insert into public.pms_misafir_kimlik (otel_id, misafir_id, belge_tipi, belge_no)
  values ('810','f0000000-0000-0000-0000-000000000810','tc_kimlik','12345678901')
$q$, 'ayni belge iki kez kaydedilemez');

-- CAPRAZ OTEL: 811 kimlik kaydi 810 misafirine baglanamaz.
select pms2_test.reddedilmeli($q$
  insert into public.pms_misafir_kimlik (otel_id, misafir_id, belge_tipi, belge_no)
  values ('811','f0000000-0000-0000-0000-000000000810','pasaport','X123456')
$q$, 'CAPRAZ OTEL: kimlik baska otelin misafirine baglanamaz');

-- ---------------------------------------------------------------------------
-- REZERVASYON: tarih, kapasite, capraz otel
-- ---------------------------------------------------------------------------
select pms2_test.reddedilmeli($q$
  insert into public.pms_rezervasyonlar (otel_id, misafir_id, oda_tipi_id, giris_tarihi, cikis_tarihi)
  values ('810','f0000000-0000-0000-0000-000000000810','d0000000-0000-0000-0000-000000000810',
          '2026-10-05','2026-10-05')
$q$, 'sifir gecelik rezervasyon olamaz');

select pms2_test.reddedilmeli($q$
  insert into public.pms_rezervasyonlar (otel_id, misafir_id, oda_tipi_id, giris_tarihi, cikis_tarihi)
  values ('810','f0000000-0000-0000-0000-000000000810','d0000000-0000-0000-0000-000000000810',
          '2026-10-05','2026-10-03')
$q$, 'cikis girisden once olamaz');

-- CAPRAZ OTEL: 810 rezervasyonu 811 oda tipine baglanamaz.
select pms2_test.reddedilmeli($q$
  insert into public.pms_rezervasyonlar (otel_id, misafir_id, oda_tipi_id, giris_tarihi, cikis_tarihi)
  values ('810','f0000000-0000-0000-0000-000000000810','d0000000-0000-0000-0000-000000000811',
          '2026-10-01','2026-10-03')
$q$, 'CAPRAZ OTEL: rezervasyon baska otelin oda tipine baglanamaz');

-- CAPRAZ OTEL: 810 rezervasyonu 811 misafirine baglanamaz.
select pms2_test.reddedilmeli($q$
  insert into public.pms_rezervasyonlar (otel_id, misafir_id, oda_tipi_id, giris_tarihi, cikis_tarihi)
  values ('810','f0000000-0000-0000-0000-000000000811','d0000000-0000-0000-0000-000000000810',
          '2026-10-01','2026-10-03')
$q$, 'CAPRAZ OTEL: rezervasyon baska otelin misafirine baglanamaz');

-- KAPASITE: OVS tipi 2 kisilik, 3 kisi kabul edilmemeli.
select pms2_test.reddedilmeli($q$
  insert into public.pms_rezervasyonlar
    (otel_id, misafir_id, oda_tipi_id, giris_tarihi, cikis_tarihi, yetiskin_sayisi, cocuk_sayisi, durum)
  values ('810','f0000000-0000-0000-0000-000000000810','d0000000-0000-0000-0000-000000000810',
          '2026-10-01','2026-10-03', 2, 1, 'onaylandi')
$q$, 'kisi sayisi oda tipi kapasitesini asamaz');

select pms2_test.reddedilmeli($q$
  insert into public.pms_rezervasyonlar
    (otel_id, misafir_id, oda_tipi_id, giris_tarihi, cikis_tarihi, yetiskin_sayisi, durum)
  values ('810','f0000000-0000-0000-0000-00000000ff10','d0000000-0000-0000-0000-00000000ff10',
          '2026-10-01','2026-10-03', 4, 'onaylandi')
$q$, 'yetiskin sayisi tip sinirini asamaz');

-- ---------------------------------------------------------------------------
-- ASIRI SATIS: OVS tipinde TEK oda var
-- ---------------------------------------------------------------------------
insert into public.pms_rezervasyonlar
  (id, otel_id, misafir_id, oda_tipi_id, giris_tarihi, cikis_tarihi, durum)
values ('11110000-0000-0000-0000-000000000001','810','f0000000-0000-0000-0000-000000000810',
        'd0000000-0000-0000-0000-000000000810','2026-10-01','2026-10-05','onaylandi');

select pms2_test.dogru(
  (select rezervasyon_no like 'R-2026-%' from public.pms_rezervasyonlar
    where id = '11110000-0000-0000-0000-000000000001'),
  'rezervasyon numarasi otomatik uretildi');

-- Cakisan ikinci rezervasyon: tek oda var, REDDEDILMELI.
select pms2_test.reddedilmeli($q$
  insert into public.pms_rezervasyonlar
    (otel_id, misafir_id, oda_tipi_id, giris_tarihi, cikis_tarihi, durum)
  values ('810','f0000000-0000-0000-0000-000000000810','d0000000-0000-0000-0000-000000000810',
          '2026-10-03','2026-10-07','onaylandi')
$q$, 'ASIRI SATIS: tek odali tipte cakisan ikinci rezervasyon');

-- BITISIK tarih: 05-09, ilkiyle cakismaz -> KABUL.
insert into public.pms_rezervasyonlar
  (id, otel_id, misafir_id, oda_tipi_id, giris_tarihi, cikis_tarihi, durum)
values ('11110000-0000-0000-0000-000000000002','810','f0000000-0000-0000-0000-000000000810',
        'd0000000-0000-0000-0000-000000000810','2026-10-05','2026-10-09','onaylandi');
select pms2_test.dogru(
  (select count(*) = 2 from public.pms_rezervasyonlar
    where oda_tipi_id = 'd0000000-0000-0000-0000-000000000810'),
  'bitisik tarihli rezervasyon kabul edilir (cikis gunu yeni girise acik)');

-- 'taslak' envanter TUTMAZ: cakisan taslak kabul edilmeli.
insert into public.pms_rezervasyonlar
  (id, otel_id, misafir_id, oda_tipi_id, giris_tarihi, cikis_tarihi, durum)
values ('11110000-0000-0000-0000-000000000003','810','f0000000-0000-0000-0000-000000000810',
        'd0000000-0000-0000-0000-000000000810','2026-10-02','2026-10-04','taslak');
select pms2_test.dogru(
  (select durum = 'taslak' from public.pms_rezervasyonlar
    where id = '11110000-0000-0000-0000-000000000003'),
  'taslak rezervasyon envanter tutmaz');

-- Taslagi ONAYLAMAK ise reddedilmeli: artik envanter istiyor.
select pms2_test.reddedilmeli($q$
  update public.pms_rezervasyonlar set durum = 'onaylandi'
   where id = '11110000-0000-0000-0000-000000000003'
$q$, 'ASIRI SATIS: taslak onaylanirken de kontrol edilir');

-- IPTAL envanteri SERBEST BIRAKIR.
update public.pms_rezervasyonlar set durum = 'iptal'
 where id = '11110000-0000-0000-0000-000000000001';
insert into public.pms_rezervasyonlar
  (id, otel_id, misafir_id, oda_tipi_id, giris_tarihi, cikis_tarihi, durum)
values ('11110000-0000-0000-0000-000000000004','810','f0000000-0000-0000-0000-000000000810',
        'd0000000-0000-0000-0000-000000000810','2026-10-01','2026-10-05','onaylandi');
select pms2_test.dogru(
  (select count(*) = 1 from public.pms_rezervasyonlar
    where id = '11110000-0000-0000-0000-000000000004'),
  'iptal envanteri serbest birakir');

-- ---------------------------------------------------------------------------
-- ODA ATAMASI: cakisma exclusion kisitiyla imkansiz
-- ---------------------------------------------------------------------------
insert into public.pms_oda_atamalari (otel_id, rezervasyon_id, oda_id, baslangic, bitis)
values ('810','11110000-0000-0000-0000-000000000004','e0000000-0000-0000-0000-000000000810',
        '2026-10-01','2026-10-05');

-- Ayni odaya cakisan ikinci AKTIF atama -> exclusion reddi.
select pms2_test.reddedilmeli($q$
  insert into public.pms_oda_atamalari (otel_id, rezervasyon_id, oda_id, baslangic, bitis)
  values ('810','11110000-0000-0000-0000-000000000002','e0000000-0000-0000-0000-000000000810',
          '2026-10-04','2026-10-08')
$q$, 'CAKISMA: ayni odaya cakisan ikinci atama');

-- Bitisik atama (05-09) kabul edilmeli.
insert into public.pms_oda_atamalari (otel_id, rezervasyon_id, oda_id, baslangic, bitis)
values ('810','11110000-0000-0000-0000-000000000002','e0000000-0000-0000-0000-000000000810',
        '2026-10-05','2026-10-09');
select pms2_test.dogru(
  (select count(*) = 2 from public.pms_oda_atamalari
    where oda_id = 'e0000000-0000-0000-0000-000000000810'),
  'bitisik atama kabul edilir');

-- Atama rezervasyon tarihlerinin DISINA tasamaz.
select pms2_test.reddedilmeli($q$
  insert into public.pms_oda_atamalari (otel_id, rezervasyon_id, oda_id, baslangic, bitis)
  values ('810','11110000-0000-0000-0000-000000000004','e0000000-0000-0000-0000-00000000ff10',
          '2026-09-30','2026-10-05')
$q$, 'atama rezervasyon tarihlerinin disina tasamaz');

-- CAPRAZ OTEL: 810 atamasi 811 odasina yapilamaz.
select pms2_test.reddedilmeli($q$
  insert into public.pms_oda_atamalari (otel_id, rezervasyon_id, oda_id, baslangic, bitis)
  values ('810','11110000-0000-0000-0000-000000000004','e0000000-0000-0000-0000-000000000811',
          '2026-10-01','2026-10-03')
$q$, 'CAPRAZ OTEL: atama baska otelin odasina yapilamaz');

-- Iptal edilmis rezervasyona oda atanamaz.
select pms2_test.reddedilmeli($q$
  insert into public.pms_oda_atamalari (otel_id, rezervasyon_id, oda_id, baslangic, bitis)
  values ('810','11110000-0000-0000-0000-000000000001','e0000000-0000-0000-0000-00000000ff10',
          '2026-10-01','2026-10-03')
$q$, 'iptal edilmis rezervasyona oda atanamaz');

-- Pasif atama cakismayi ENGELLEMEZ: oda serbest kalir.
update public.pms_oda_atamalari set aktif = false
 where oda_id = 'e0000000-0000-0000-0000-000000000810' and baslangic = '2026-10-01';
insert into public.pms_oda_atamalari (otel_id, rezervasyon_id, oda_id, baslangic, bitis)
values ('810','11110000-0000-0000-0000-000000000004','e0000000-0000-0000-0000-000000000810',
        '2026-10-01','2026-10-05');
select pms2_test.dogru(
  (select count(*) = 1 from public.pms_oda_atamalari
    where oda_id = 'e0000000-0000-0000-0000-000000000810'
      and baslangic = '2026-10-01' and aktif),
  'pasif atama odayi serbest birakir');

-- ---------------------------------------------------------------------------
-- IPTAL ODAYI SERBEST BIRAKIR
-- ---------------------------------------------------------------------------
-- Bu olmadan iptal edilen rezervasyonun atamasi aktif kalir, exclusion kisiti
-- odayi dolu sayar ve oda o tarihler icin OLU kalir. Oz-incelemede olculdu.
insert into public.pms_oda_tipleri (id, otel_id, kod, ad, azami_kisi, azami_yetiskin)
values ('30000000-0000-0000-0000-000000000001','810','IPT','Iptal Testi',2,2)
on conflict (id) do nothing;
insert into public.pms_odalar (id, otel_id, oda_tipi_id, oda_no)
values ('31000000-0000-0000-0000-000000000001','810','30000000-0000-0000-0000-000000000001','IPT-1')
on conflict (id) do nothing;
insert into public.pms_rezervasyonlar
  (id, otel_id, misafir_id, oda_tipi_id, giris_tarihi, cikis_tarihi, durum)
values ('32000000-0000-0000-0000-000000000001','810','f0000000-0000-0000-0000-000000000810',
        '30000000-0000-0000-0000-000000000001','2026-12-01','2026-12-05','onaylandi');
insert into public.pms_oda_atamalari (id, otel_id, rezervasyon_id, oda_id, baslangic, bitis)
values ('33000000-0000-0000-0000-000000000001','810','32000000-0000-0000-0000-000000000001',
        '31000000-0000-0000-0000-000000000001','2026-12-01','2026-12-05');

update public.pms_rezervasyonlar set durum = 'iptal'
 where id = '32000000-0000-0000-0000-000000000001';

select pms2_test.dogru(
  (select not aktif from public.pms_oda_atamalari
    where id = '33000000-0000-0000-0000-000000000001'),
  'IPTAL: atama otomatik pasife alinir');

-- Oda artik yeniden satilabilmeli.
insert into public.pms_rezervasyonlar
  (id, otel_id, misafir_id, oda_tipi_id, giris_tarihi, cikis_tarihi, durum)
values ('32000000-0000-0000-0000-000000000002','810','f0000000-0000-0000-0000-000000000810',
        '30000000-0000-0000-0000-000000000001','2026-12-01','2026-12-05','onaylandi');
insert into public.pms_oda_atamalari (otel_id, rezervasyon_id, oda_id, baslangic, bitis)
values ('810','32000000-0000-0000-0000-000000000002',
        '31000000-0000-0000-0000-000000000001','2026-12-01','2026-12-05');
select pms2_test.dogru(
  (select count(*) = 1 from public.pms_oda_atamalari
    where oda_id = '31000000-0000-0000-0000-000000000001' and aktif),
  'IPTAL: oda ayni tarihlere yeniden atanabilir');

-- 'gelmedi' de ayni sekilde serbest birakmali.
update public.pms_rezervasyonlar set durum = 'gelmedi'
 where id = '32000000-0000-0000-0000-000000000002';
select pms2_test.dogru(
  (select count(*) = 0 from public.pms_oda_atamalari
    where oda_id = '31000000-0000-0000-0000-000000000001' and aktif),
  'GELMEDI: atama otomatik pasife alinir');

-- ---------------------------------------------------------------------------
-- ENVANTER SATILANIN ALTINA DUSEMEZ
-- ---------------------------------------------------------------------------
insert into public.pms_oda_tipleri (id, otel_id, kod, ad, azami_kisi, azami_yetiskin)
values ('30000000-0000-0000-0000-000000000002','810','ENV','Envanter Testi',2,2)
on conflict (id) do nothing;
insert into public.pms_odalar (id, otel_id, oda_tipi_id, oda_no) values
  ('31000000-0000-0000-0000-000000000002','810','30000000-0000-0000-0000-000000000002','ENV-1'),
  ('31000000-0000-0000-0000-000000000003','810','30000000-0000-0000-0000-000000000002','ENV-2')
on conflict (id) do nothing;

-- Gelecege uzanan TEK rezervasyon: 2 odadan 1'i satili.
insert into public.pms_rezervasyonlar
  (id, otel_id, misafir_id, oda_tipi_id, giris_tarihi, cikis_tarihi, durum)
values ('32000000-0000-0000-0000-000000000003','810','f0000000-0000-0000-0000-000000000810',
        '30000000-0000-0000-0000-000000000002',
        current_date + 30, current_date + 34, 'onaylandi');

-- Bir odayi kapatmak SORUN DEGIL: 1 oda kalir, 1 rezervasyon var.
update public.pms_odalar set aktif = false where id = '31000000-0000-0000-0000-000000000003';
select pms2_test.dogru(
  (select not aktif from public.pms_odalar where id = '31000000-0000-0000-0000-000000000003'),
  'ENVANTER: yeterli oda kaldiginda pasiflestirme serbest');

-- Ikinci odayi da kapatmak REDDEDILMELI: 0 oda kalir, 1 rezervasyon var.
select pms2_test.reddedilmeli($q$
  update public.pms_odalar set aktif = false where id = '31000000-0000-0000-0000-000000000002'
$q$, 'ENVANTER: satilanin altina dusuren pasiflestirme reddedilir');

-- Silmek de ayni sekilde reddedilmeli.
select pms2_test.reddedilmeli($q$
  delete from public.pms_odalar where id = '31000000-0000-0000-0000-000000000002'
$q$, 'ENVANTER: satilanin altina dusuren silme reddedilir');

-- Odayi baska tipe tasimak da envanteri kisar.
select pms2_test.reddedilmeli($q$
  update public.pms_odalar set oda_tipi_id = '30000000-0000-0000-0000-000000000001'
   where id = '31000000-0000-0000-0000-000000000002'
$q$, 'ENVANTER: odayi baska tipe tasimak da envanteri kisar');

-- Rezervasyon iptal edilince kisitlama kalkar.
update public.pms_rezervasyonlar set durum = 'iptal'
 where id = '32000000-0000-0000-0000-000000000003';
update public.pms_odalar set aktif = false where id = '31000000-0000-0000-0000-000000000002';
select pms2_test.dogru(
  (select not aktif from public.pms_odalar where id = '31000000-0000-0000-0000-000000000002'),
  'ENVANTER: rezervasyon iptal olunca pasiflestirme serbest kalir');

-- ---------------------------------------------------------------------------
-- PASIF ODAYA ATAMA YAPILAMAZ
-- ---------------------------------------------------------------------------
insert into public.pms_odalar (id, otel_id, oda_tipi_id, oda_no, aktif)
values ('31000000-0000-0000-0000-00000000000f','810','30000000-0000-0000-0000-000000000001',
        'PASIF-1', false)
on conflict (id) do nothing;
insert into public.pms_rezervasyonlar
  (id, otel_id, misafir_id, oda_tipi_id, giris_tarihi, cikis_tarihi, durum)
values ('32000000-0000-0000-0000-000000000004','810','f0000000-0000-0000-0000-000000000810',
        '30000000-0000-0000-0000-000000000001','2027-01-01','2027-01-05','onaylandi');

select pms2_test.reddedilmeli($q$
  insert into public.pms_oda_atamalari (otel_id, rezervasyon_id, oda_id, baslangic, bitis)
  values ('810','32000000-0000-0000-0000-000000000004',
          '31000000-0000-0000-0000-00000000000f','2027-01-01','2027-01-05')
$q$, 'pasif odaya misafir atanamaz');

-- ---------------------------------------------------------------------------
-- PASIF ATAMA DA TARIH DENETIMINDEN GECER
-- ---------------------------------------------------------------------------
-- Onceki surumde `if not new.aktif then return new` erken cikisi yuzunden
-- rezervasyon tarihlerinin tamamen disinda pasif satirlar eklenebiliyordu.
select pms2_test.reddedilmeli($q$
  insert into public.pms_oda_atamalari (otel_id, rezervasyon_id, oda_id, baslangic, bitis, aktif)
  values ('810','32000000-0000-0000-0000-000000000004',
          '31000000-0000-0000-0000-000000000001','2020-01-01','2020-01-05', false)
$q$, 'pasif atama da rezervasyon tarihleri disina tasamaz');

-- ---------------------------------------------------------------------------
-- YETKI: kimlik verisi AYRI yetkiye bagli
-- ---------------------------------------------------------------------------
set role authenticated;
select set_config('request.jwt.claim.role','authenticated',false);

-- Kimlik yetkisi OLMAYAN kullanici: misafiri gorur, kimligi GORMEZ.
select set_config('request.jwt.claim.sub','a0000000-0000-0000-0000-000000000001',false);
select pms2_test.dogru((select count(*) > 0 from public.pms_misafirler),
  'kimliksiz kullanici misafirleri gorur');
select pms2_test.dogru((select count(*) = 0 from public.pms_misafir_kimlik),
  'KVKK: kimliksiz kullanici kimlik verisini GOREMEZ');
select pms2_test.reddedilmeli($q$
  insert into public.pms_misafir_kimlik (otel_id, misafir_id, belge_tipi, belge_no)
  values ('810','f0000000-0000-0000-0000-000000000810','pasaport','P999999')
$q$, 'KVKK: kimliksiz kullanici kimlik YAZAMAZ');

-- Kimlik yetkisi OLAN kullanici gorur.
select set_config('request.jwt.claim.sub','a0000000-0000-0000-0000-000000000002',false);
select pms2_test.dogru((select count(*) > 0 from public.pms_misafir_kimlik),
  'yetkili kullanici kimlik verisini gorur');

-- Otel izolasyonu: 810 kullanicisi 811 misafirini/rezervasyonunu goremez.
select pms2_test.dogru((select count(*) = 0 from public.pms_misafirler where otel_id::text = '811'),
  'OTEL: 810 kullanicisi 811 misafirlerini goremez');
select pms2_test.dogru((select count(*) = 0 from public.pms_rezervasyonlar where otel_id::text = '811'),
  'OTEL: 810 kullanicisi 811 rezervasyonlarini goremez');
select pms2_test.dogru((select count(*) = 0 from public.pms_oda_atamalari where otel_id::text = '811'),
  'OTEL: 810 kullanicisi 811 atamalarini goremez');

-- Istemci otel_id degistirerek kapsam asamaz.
select pms2_test.reddedilmeli($q$
  insert into public.pms_misafirler (otel_id, ad, soyad) values ('811','Sizinti','Denemesi')
$q$, 'OTEL: istemci otel_id ile 811 e yazamaz');
reset role;

-- ---------------------------------------------------------------------------
-- ANONIM: hicbir seye erisemez
-- ---------------------------------------------------------------------------
set role anon;
select set_config('request.jwt.claim.role','anon',false);
select set_config('request.jwt.claim.sub','',false);
select pms2_test.reddedilmeli($q$select count(*) from public.pms_misafirler$q$,      'anon misafir okuyamaz');
select pms2_test.reddedilmeli($q$select count(*) from public.pms_misafir_kimlik$q$,  'anon kimlik okuyamaz');
select pms2_test.reddedilmeli($q$select count(*) from public.pms_rezervasyonlar$q$,  'anon rezervasyon okuyamaz');
select pms2_test.reddedilmeli($q$select count(*) from public.pms_oda_atamalari$q$,   'anon atama okuyamaz');
reset role;

select 'TUM PMS ADIM 2 TESTLERI GECTI' as sonuc;
