-- ============================================================================
-- PMS FAZ 1 / ADIM 4 — FOLIO SÖZLEŞME TESTLERİ
-- ============================================================================
-- scripts/pms-faz1-adim4-testleri.mjs tarafından çalıştırılır.
-- Sıra: iskele -> ÜRETİM DÖKÜMÜ -> Adım 1 -> 2 -> 3 -> 4 (2 kez) -> bu dosya.
-- Üretim veritabanına BAĞLANMAZ.
-- ============================================================================

create schema if not exists pms4_test;

create or replace function pms4_test.dogru(p_deger boolean, p_etiket text)
returns void language plpgsql as $$
begin
  if p_deger is not true then raise exception 'BASARISIZ: %', p_etiket; end if;
end;
$$;

create or replace function pms4_test.reddedilmeli(p_sql text, p_etiket text)
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

grant usage on schema pms4_test to authenticated, anon;

-- Denetim izi tetikleyicileri "aktif ERP personeli" sarti ariyor; claim'ler
-- BASTAN ayarlanir (Adim 3'te ogrenilen ders).
select set_config('request.jwt.claim.role','authenticated',false);
select set_config('request.jwt.claim.sub','a0000000-0000-0000-0000-000000000001',false);

-- ---------------------------------------------------------------------------
-- Tezgah
-- ---------------------------------------------------------------------------
insert into auth.users (id, email)
values ('a0000000-0000-0000-0000-000000000001','pms4-1@ornek.gecersiz'),
       ('a0000000-0000-0000-0000-000000000004','pms4-4@ornek.gecersiz')
on conflict (id) do nothing;

insert into public.roller (id, ad, seviye, kod, aktif) values
  ('b0000000-0000-0000-0000-000000040001','PMS4 Tam',     'otel','pms4_tam',     true),
  ('b0000000-0000-0000-0000-000000040002','PMS4 Foliosuz','otel','pms4_foliosuz',true)
on conflict (id) do nothing;

insert into public.yetki_matrisi (rol_id, modul_id, yetki)
select 'b0000000-0000-0000-0000-000000040001', id, 'tam'::public.yetki_seviye
from public.moduller
where kod in ('pms_misafir','pms_rezervasyon','pms_oda_tipi','pms_oda','pms_folio',
              'bar_siparis_yonetimi')
on conflict (rol_id, modul_id) do nothing;

-- Folyo yetkisi OLMAYAN rol (bar personeli gibi)
insert into public.yetki_matrisi (rol_id, modul_id, yetki)
select 'b0000000-0000-0000-0000-000000040002', id, 'tam'::public.yetki_seviye
from public.moduller where kod in ('pms_rezervasyon','pms_oda','bar_siparis_yonetimi')
on conflict (rol_id, modul_id) do nothing;

insert into public.kullanicilar (id, auth_user_id, rol, rol_id, otel_id, aktif, tum_oteller, ad) values
  ('c0000000-0000-0000-0000-000000040001','a0000000-0000-0000-0000-000000000001','yonetici',
   'b0000000-0000-0000-0000-000000040001','810', true, false, 'PMS4 810 tam'),
  ('c0000000-0000-0000-0000-000000040004','a0000000-0000-0000-0000-000000000004','yonetici',
   'b0000000-0000-0000-0000-000000040002','810', true, false, 'PMS4 folyosuz')
on conflict (id) do nothing;

insert into public.pms_oda_tipleri (id, otel_id, kod, ad, azami_kisi, azami_yetiskin) values
  ('d0000000-0000-0000-0000-000000040010','810','T4A','Adim4 Tip',2,2)
on conflict (id) do nothing;

insert into public.pms_odalar (id, otel_id, oda_tipi_id, oda_no, temizlik_durumu) values
  ('e0000000-0000-0000-0000-000000040101','810','d0000000-0000-0000-0000-000000040010','401','temiz'),
  ('e0000000-0000-0000-0000-000000040102','810','d0000000-0000-0000-0000-000000040010','402','temiz'),
  ('e0000000-0000-0000-0000-000000040103','810','d0000000-0000-0000-0000-000000040010','403','temiz')
on conflict (id) do nothing;

insert into public.pms_misafirler (id, otel_id, ad, soyad) values
  ('f0000000-0000-0000-0000-000000040001','810','Zeynep','Kaya')
on conflict (id) do nothing;

-- Bar menusu: biri ucretli, biri ikram
insert into public.menu_urunler (id, otel_id, ad, fiyat, ucretli, aktif) values
  ('c1000000-0000-0000-0000-000000040001','810','Bira',      120.00, true,  true),
  ('c1000000-0000-0000-0000-000000040002','810','Ikram Cay',   0.00, false, true)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- T1 — FOLYO OTOMATİK AÇILIR
-- ---------------------------------------------------------------------------
insert into public.pms_rezervasyonlar
  (id, otel_id, misafir_id, oda_tipi_id, giris_tarihi, cikis_tarihi, durum, gecelik_fiyat)
values ('11000000-0000-0000-0000-000000040001','810','f0000000-0000-0000-0000-000000040001',
        'd0000000-0000-0000-0000-000000040010', current_date - 2, current_date + 1,
        'onaylandi', 1000.00);

select pms4_test.dogru(
  (select count(*) = 1 from public.pms_folyolar
    where rezervasyon_id = '11000000-0000-0000-0000-000000040001' and durum = 'acik'),
  'T1: rezervasyon onaylaninca folyo otomatik acildi');
select pms4_test.dogru(
  (select folio_no like 'F-%' from public.pms_folyolar
    where rezervasyon_id = '11000000-0000-0000-0000-000000040001'),
  'T1: folyo numarasi uretildi');

-- ---------------------------------------------------------------------------
-- T2 — ODA ÜCRETİ İŞLEME
-- ---------------------------------------------------------------------------
set role authenticated;
select set_config('request.jwt.claim.role','authenticated',false);
select set_config('request.jwt.claim.sub','a0000000-0000-0000-0000-000000000001',false);

-- Giris yapilmadan islenemez.
select pms4_test.reddedilmeli($q$
  select public.pms_folio_oda_ucreti_isle('11000000-0000-0000-0000-000000040001')
$q$, 'T2: giris yapilmadan oda ucreti islenemez');

select public.pms_check_in('11000000-0000-0000-0000-000000040001',
                           'e0000000-0000-0000-0000-000000040101');

-- Konaklama: current_date-2 .. current_date+1 -> geceler -2, -1, 0 (bugun dahil),
-- +1 gecesi henuz gelmedi (cikis gunu zaten gece degil).
select pms4_test.dogru(
  (select public.pms_folio_oda_ucreti_isle('11000000-0000-0000-0000-000000040001') = 3),
  'T2: gecmis 3 gece islendi');

-- IDEMPOTENCY: ikinci cagri HICBIR SEY eklememeli.
select pms4_test.dogru(
  (select public.pms_folio_oda_ucreti_isle('11000000-0000-0000-0000-000000040001') = 0),
  'T2: ikinci cagri ayni geceyi tekrar islemedi (idempotent)');
select pms4_test.dogru(
  (select count(*) = 3 from public.pms_folio_hareketleri h
     join public.pms_folyolar f on f.id = h.folio_id
    where f.rezervasyon_id = '11000000-0000-0000-0000-000000040001'
      and h.tip = 'oda_ucreti'),
  'T2: toplam 3 oda ucreti hareketi (mukerrer yok)');

select pms4_test.dogru(
  (select bakiye = 3000.00 from public.pms_folio_ozet
    where rezervasyon_id = '11000000-0000-0000-0000-000000040001'),
  'T2: bakiye 3 x 1000 = 3000');

-- Ayni geceyi elle ikinci kez yazmak da imkansiz olmali.
select pms4_test.reddedilmeli($q$
  insert into public.pms_folio_hareketleri
    (otel_id, folio_id, tip, aciklama, tutar, konaklama_gecesi)
  select '810', id, 'oda_ucreti', 'Mukerrer gece', 1000.00, current_date - 1
    from public.pms_folyolar where rezervasyon_id = '11000000-0000-0000-0000-000000040001'
$q$, 'T2: ayni gece elle de iki kez yazilamaz');

-- Fiyatsiz rezervasyon islenemez.
reset role;
insert into public.pms_rezervasyonlar
  (id, otel_id, misafir_id, oda_tipi_id, giris_tarihi, cikis_tarihi, durum)
values ('11000000-0000-0000-0000-000000040002','810','f0000000-0000-0000-0000-000000040001',
        'd0000000-0000-0000-0000-000000040010', current_date, current_date + 2, 'onaylandi');
set role authenticated;
select set_config('request.jwt.claim.role','authenticated',false);
select set_config('request.jwt.claim.sub','a0000000-0000-0000-0000-000000000001',false);
select public.pms_check_in('11000000-0000-0000-0000-000000040002',
                           'e0000000-0000-0000-0000-000000040102');
select pms4_test.reddedilmeli($q$
  select public.pms_folio_oda_ucreti_isle('11000000-0000-0000-0000-000000040002')
$q$, 'T2: gecelik fiyat yoksa islenemez');
reset role;

-- ---------------------------------------------------------------------------
-- T3 — BAR / ODA DEVRİ KÖPRÜSÜ
-- ---------------------------------------------------------------------------
-- Ucretli siparis, odada konaklayan var -> folyoya duser.
insert into public.bar_siparisleri (id, otel_id, depo_id, oda_no, durum)
values ('c2000000-0000-0000-0000-000000040001','810','BAR1','401','hazir')
on conflict (id) do nothing;
insert into public.bar_siparis_kalemleri (siparis_id, menu_urun_id, adet)
values ('c2000000-0000-0000-0000-000000040001','c1000000-0000-0000-0000-000000040001', 2);

update public.bar_siparisleri set durum = 'teslim_edildi'
 where id = 'c2000000-0000-0000-0000-000000040001';

select pms4_test.dogru(
  (select count(*) = 1 from public.pms_folio_hareketleri
    where kaynak_tip = 'bar' and kaynak_id = 'c2000000-0000-0000-0000-000000040001'
      and not ters_kayit and tutar = 240.00),
  'T3: ucretli bar siparisi folyoya 2 x 120 = 240 dustu');
select pms4_test.dogru(
  (select bakiye = 3240.00 from public.pms_folio_ozet
    where rezervasyon_id = '11000000-0000-0000-0000-000000040001'),
  'T3: bakiye 3000 + 240 = 3240');

-- IKRAM (ucretsiz) siparis: folyoyu ilgilendirmez, teslim REDDEDILMEZ.
insert into public.bar_siparisleri (id, otel_id, depo_id, oda_no, durum)
values ('c2000000-0000-0000-0000-000000040002','810','BAR1','403','hazir')
on conflict (id) do nothing;
insert into public.bar_siparis_kalemleri (siparis_id, menu_urun_id, adet)
values ('c2000000-0000-0000-0000-000000040002','c1000000-0000-0000-0000-000000040002', 3);
update public.bar_siparisleri set durum = 'teslim_edildi'
 where id = 'c2000000-0000-0000-0000-000000040002';
select pms4_test.dogru(
  (select durum = 'teslim_edildi' from public.bar_siparisleri
    where id = 'c2000000-0000-0000-0000-000000040002')
  and (select count(*) = 0 from public.pms_folio_hareketleri
        where kaynak_id = 'c2000000-0000-0000-0000-000000040002'),
  'T3: ikram siparisi bos odaya bile teslim edilir, folyoya dusmez');

-- UCRETLI siparis, odada KIMSE YOK -> teslim REDDEDILIR.
insert into public.bar_siparisleri (id, otel_id, depo_id, oda_no, durum)
values ('c2000000-0000-0000-0000-000000040003','810','BAR1','403','hazir')
on conflict (id) do nothing;
insert into public.bar_siparis_kalemleri (siparis_id, menu_urun_id, adet)
values ('c2000000-0000-0000-0000-000000040003','c1000000-0000-0000-0000-000000040001', 1);
select pms4_test.reddedilmeli($q$
  update public.bar_siparisleri set durum = 'teslim_edildi'
   where id = 'c2000000-0000-0000-0000-000000040003'
$q$, 'T3: bos odaya ucretli oda devri reddedilir');

-- ODA NO YOK: masa siparisi, folyoyu ilgilendirmez.
insert into public.bar_siparisleri (id, otel_id, depo_id, durum)
values ('c2000000-0000-0000-0000-000000040004','810','BAR1','hazir')
on conflict (id) do nothing;
insert into public.bar_siparis_kalemleri (siparis_id, menu_urun_id, adet)
values ('c2000000-0000-0000-0000-000000040004','c1000000-0000-0000-0000-000000040001', 1);
update public.bar_siparisleri set durum = 'teslim_edildi'
 where id = 'c2000000-0000-0000-0000-000000040004';
select pms4_test.dogru(
  (select count(*) = 0 from public.pms_folio_hareketleri
    where kaynak_id = 'c2000000-0000-0000-0000-000000040004'),
  'T3: oda numarasi olmayan siparis folyoya dusmez');

-- IPTAL: borc silinmez, TERS KAYIT yazilir.
update public.bar_siparisleri set durum = 'iptal'
 where id = 'c2000000-0000-0000-0000-000000040001';
select pms4_test.dogru(
  (select count(*) = 1 from public.pms_folio_hareketleri
    where kaynak_id = 'c2000000-0000-0000-0000-000000040001'
      and ters_kayit and tutar = -240.00),
  'T3: iptal ters kayit uretti (-240)');
select pms4_test.dogru(
  (select count(*) = 1 from public.pms_folio_hareketleri
    where kaynak_id = 'c2000000-0000-0000-0000-000000040001' and not ters_kayit),
  'T3: orijinal borc SILINMEDI (mali iz korundu)');
select pms4_test.dogru(
  (select bakiye = 3000.00 from public.pms_folio_ozet
    where rezervasyon_id = '11000000-0000-0000-0000-000000040001'),
  'T3: ters kayit sonrasi bakiye 3000 e dondu');

-- ---------------------------------------------------------------------------
-- T4 — ÖDEME VE BAKİYE
-- ---------------------------------------------------------------------------
set role authenticated;
select set_config('request.jwt.claim.role','authenticated',false);
select set_config('request.jwt.claim.sub','a0000000-0000-0000-0000-000000000001',false);

insert into public.pms_folio_odemeler (otel_id, folio_id, yontem, tutar)
select '810', id, 'nakit', 1000.00 from public.pms_folyolar
 where rezervasyon_id = '11000000-0000-0000-0000-000000040001';
select pms4_test.dogru(
  (select bakiye = 2000.00 from public.pms_folio_ozet
    where rezervasyon_id = '11000000-0000-0000-0000-000000040001'),
  'T4: 1000 tahsilat sonrasi bakiye 2000');

-- Sifir tutarli odeme anlamsizdir.
select pms4_test.reddedilmeli($q$
  insert into public.pms_folio_odemeler (otel_id, folio_id, yontem, tutar)
  select '810', id, 'nakit', 0 from public.pms_folyolar
   where rezervasyon_id = '11000000-0000-0000-0000-000000040001'
$q$, 'T4: sifir tutarli odeme reddedilir');

-- ---------------------------------------------------------------------------
-- T5 — FOLYO KAPATMA
-- ---------------------------------------------------------------------------
select pms4_test.reddedilmeli($q$
  select public.pms_folio_kapat(
    (select id from public.pms_folyolar
      where rezervasyon_id = '11000000-0000-0000-0000-000000040001'))
$q$, 'T5: bakiyeli folyo kapatilamaz');

insert into public.pms_folio_odemeler (otel_id, folio_id, yontem, tutar)
select '810', id, 'kredi_karti', 2000.00 from public.pms_folyolar
 where rezervasyon_id = '11000000-0000-0000-0000-000000040001';
select public.pms_folio_kapat(
  (select id from public.pms_folyolar
    where rezervasyon_id = '11000000-0000-0000-0000-000000040001'));
select pms4_test.dogru(
  (select durum = 'kapali' and kapanis_zamani is not null from public.pms_folyolar
    where rezervasyon_id = '11000000-0000-0000-0000-000000040001'),
  'T5: bakiye sifirlaninca folyo kapandi');

-- Kapali folyoya yazma yasak.
select pms4_test.reddedilmeli($q$
  insert into public.pms_folio_hareketleri (otel_id, folio_id, tip, aciklama, tutar)
  select '810', id, 'ekstra', 'Kapali folyoya yazma', 50 from public.pms_folyolar
   where rezervasyon_id = '11000000-0000-0000-0000-000000040001'
$q$, 'T5: kapali folyoya borc yazilamaz');
select pms4_test.reddedilmeli($q$
  insert into public.pms_folio_odemeler (otel_id, folio_id, yontem, tutar)
  select '810', id, 'nakit', 50 from public.pms_folyolar
   where rezervasyon_id = '11000000-0000-0000-0000-000000040001'
$q$, 'T5: kapali folyoya odeme yazilamaz');
reset role;

-- ---------------------------------------------------------------------------
-- T6 — YETKİ VE İZOLASYON
-- ---------------------------------------------------------------------------
set role authenticated;
select set_config('request.jwt.claim.role','authenticated',false);

-- Folyo yetkisi OLMAYAN kullanici folyoyu goremez.
select set_config('request.jwt.claim.sub','a0000000-0000-0000-0000-000000000004',false);
select pms4_test.dogru(
  (select count(*) = 0 from public.pms_folyolar),
  'T6: folyo yetkisi olmayan kullanici folyo goremez');
select pms4_test.dogru(
  (select count(*) = 0 from public.pms_folio_ozet),
  'T6: ozet gorunumu de RLS e tabi (security_invoker)');
select pms4_test.reddedilmeli($q$
  select public.pms_folio_oda_ucreti_isle('11000000-0000-0000-0000-000000040002')
$q$, 'T6: folyo yetkisi olmayan oda ucreti isleyemez');

-- Yetkili kullanici gorur.
select set_config('request.jwt.claim.sub','a0000000-0000-0000-0000-000000000001',false);
select pms4_test.dogru(
  (select count(*) > 0 from public.pms_folyolar),
  'T6: yetkili kullanici folyolari gorur');
reset role;

set role anon;
select set_config('request.jwt.claim.role','anon',false);
select set_config('request.jwt.claim.sub','',false);
select pms4_test.reddedilmeli($q$select count(*) from public.pms_folyolar$q$,
  'T6: anon folyo okuyamaz');
select pms4_test.reddedilmeli($q$select count(*) from public.pms_folio_hareketleri$q$,
  'T6: anon hareket okuyamaz');
select pms4_test.reddedilmeli($q$select count(*) from public.pms_folio_odemeler$q$,
  'T6: anon odeme okuyamaz');
select pms4_test.reddedilmeli($q$select count(*) from public.pms_folio_ozet$q$,
  'T6: anon ozet okuyamaz');
select pms4_test.reddedilmeli($q$
  select public.pms_folio_kapat('11000000-0000-0000-0000-000000040001')
$q$, 'T6: anon folyo RPC calistiramaz');
reset role;

-- ---------------------------------------------------------------------------
-- T7 — DENETİM İZİ
-- ---------------------------------------------------------------------------
select pms4_test.dogru(
  (select count(*) > 0 from public.erp_islem_audit
    where entity_type in ('pms_folyolar','pms_folio_hareketleri','pms_folio_odemeler')),
  'T7: folyo yazmalari denetim izi uretti');
select pms4_test.dogru(
  (select bool_and(actor_user_id is not null) from public.erp_islem_audit
    where entity_type = 'pms_folio_odemeler'),
  'T7: aktor sunucudan geldi');


-- ---------------------------------------------------------------------------
-- T8 — ÇAPRAZ OTEL (İKİ OTELLİ GERÇEK TEZGAH)
-- ---------------------------------------------------------------------------
-- Bilesik FK + RLS var diye ATLANMAZ: garanti olculur.
-- 811'in odasi BILEREK 810 ile ayni numarayi tasir ('401'). Kopru ya da
-- politikalar otel kapsamini kaybederse bu testler kirmiziya duser.
reset role;
select set_config('request.jwt.claim.role','authenticated',false);
select set_config('request.jwt.claim.sub','a0000000-0000-0000-0000-000000000001',false);

insert into auth.users (id, email)
values ('a0000000-0000-0000-0000-000000000811','pms4-811@ornek.gecersiz')
on conflict (id) do nothing;

insert into public.roller (id, ad, seviye, kod, aktif) values
  ('b0000000-0000-0000-0000-000000040811','PMS4 811 Tam','otel','pms4_811',true)
on conflict (id) do nothing;

insert into public.yetki_matrisi (rol_id, modul_id, yetki)
select 'b0000000-0000-0000-0000-000000040811', id, 'tam'::public.yetki_seviye
from public.moduller
where kod in ('pms_misafir','pms_rezervasyon','pms_oda_tipi','pms_oda','pms_folio',
              'bar_siparis_yonetimi')
on conflict (rol_id, modul_id) do nothing;

insert into public.kullanicilar (id, auth_user_id, rol, rol_id, otel_id, aktif, tum_oteller, ad) values
  ('c0000000-0000-0000-0000-000000040811','a0000000-0000-0000-0000-000000000811','yonetici',
   'b0000000-0000-0000-0000-000000040811','811', true, false, 'PMS4 811 tam')
on conflict (id) do nothing;

insert into public.pms_oda_tipleri (id, otel_id, kod, ad, azami_kisi, azami_yetiskin) values
  ('d0000000-0000-0000-0000-000000040811','811','T4B','Adim4 Tip 811',2,2)
on conflict (id) do nothing;

-- DIKKAT: 810'daki 401 ile AYNI oda numarasi, farkli otel.
insert into public.pms_odalar (id, otel_id, oda_tipi_id, oda_no, temizlik_durumu) values
  ('e0000000-0000-0000-0000-000000040811','811','d0000000-0000-0000-0000-000000040811','401','temiz'),
  ('e0000000-0000-0000-0000-000000040812','811','d0000000-0000-0000-0000-000000040811','402','temiz')
on conflict (id) do nothing;

insert into public.pms_misafirler (id, otel_id, ad, soyad) values
  ('f0000000-0000-0000-0000-000000040811','811','Merve','Demir')
on conflict (id) do nothing;

insert into public.menu_urunler (id, otel_id, ad, fiyat, ucretli, aktif) values
  ('c1000000-0000-0000-0000-000000040811','811','Bira 811', 150.00, true, true)
on conflict (id) do nothing;

-- 811 rezervasyonu -> folyosu otomatik acilir. Giris 402'ye yapilir;
-- 811'in 401 odasi BOS BIRAKILIR (bar sizinti testi icin).
insert into public.pms_rezervasyonlar
  (id, otel_id, misafir_id, oda_tipi_id, giris_tarihi, cikis_tarihi, durum, gecelik_fiyat)
values ('11000000-0000-0000-0000-000000040811','811','f0000000-0000-0000-0000-000000040811',
        'd0000000-0000-0000-0000-000000040811', current_date - 1, current_date + 1,
        'onaylandi', 500.00);

set role authenticated;
select set_config('request.jwt.claim.role','authenticated',false);
select set_config('request.jwt.claim.sub','a0000000-0000-0000-0000-000000000811',false);
select public.pms_check_in('11000000-0000-0000-0000-000000040811',
                           'e0000000-0000-0000-0000-000000040811');
select public.pms_folio_oda_ucreti_isle('11000000-0000-0000-0000-000000040811');
reset role;

-- 811 folyosunun kimligini OTURUM DEGISKENINE al.
-- TUZAK: asagidaki testler folyoyu alt sorguyla bulsaydi, 810 kullanicisi o
-- satiri RLS yuzunden GOREMEZ; alt sorgu 0 satir doner, INSERT 0 satir ekler
-- ve HATA VERMEZ. "Reddedildi" ile "hicbir sey olmadi" birbirine karisirdi.
-- Degisken rolden bagimsizdir; boylece reddi gercekten YETKI katmani verir.
select set_config('pms4.folio811',
  (select id::text from public.pms_folyolar
    where rezervasyon_id = '11000000-0000-0000-0000-000000040811'), false);

-- --- T8a: 810 folyosu 811 rezervasyonuna BAGLANAMAZ (bilesik FK) ---
select pms4_test.reddedilmeli($q$
  insert into public.pms_folyolar (otel_id, rezervasyon_id, folio_no)
  values ('810','11000000-0000-0000-0000-000000040811','F-CAPRAZ-1')
$q$, 'T8a: 810 folyosu 811 rezervasyonuna baglanamaz');

-- --- T8b: 810 kullanicisi 811 folyosunu GOREMEZ ---
set role authenticated;
select set_config('request.jwt.claim.role','authenticated',false);
select set_config('request.jwt.claim.sub','a0000000-0000-0000-0000-000000000001',false);
select pms4_test.dogru(
  (select count(*) = 0 from public.pms_folyolar where otel_id = '811'),
  'T8b: 810 kullanicisi 811 folyosunu goremez');
select pms4_test.dogru(
  (select count(*) = 0 from public.pms_folio_hareketleri where otel_id = '811'),
  'T8b: 810 kullanicisi 811 hareketlerini goremez');
select pms4_test.dogru(
  (select count(*) = 0 from public.pms_folio_odemeler where otel_id = '811'),
  'T8b: 810 kullanicisi 811 odemelerini goremez');

-- --- T8c: ozet gorunumu capraz otel SIZINTI URETMEZ ---
select pms4_test.dogru(
  (select count(*) = 0 from public.pms_folio_ozet where otel_id = '811'),
  'T8c: ozet gorunumu 811 satiri sizdirmiyor');
-- Sifir satir "her sey gizli" demek DEGIL; gorunum 810 tarafinda calismali.
select pms4_test.dogru(
  (select count(*) > 0 from public.pms_folio_ozet where otel_id = '810'),
  'T8c: ayni gorunum 810 satirlarini donduruyor (test anlamli)');

-- --- T8d: 810 kullanicisi 811 folyosuna HAREKET ekleyemez ---
select pms4_test.reddedilmeli($q$
  insert into public.pms_folio_hareketleri (otel_id, folio_id, tip, aciklama, tutar)
  values ('811', current_setting('pms4.folio811')::uuid, 'ekstra',
          'Capraz otel denemesi', 100.00)
$q$, 'T8d: 810 kullanicisi 811 otel_id ile hareket ekleyemez');

-- --- T8e: 810 kullanicisi 811 folyosuna ODEME ekleyemez ---
select pms4_test.reddedilmeli($q$
  insert into public.pms_folio_odemeler (otel_id, folio_id, yontem, tutar)
  values ('811', current_setting('pms4.folio811')::uuid, 'nakit', 100.00)
$q$, 'T8e: 810 kullanicisi 811 folyosuna odeme ekleyemez');
reset role;

-- --- T8f: kendi otelini yazip BASKA otelin folyosuna baglamak da imkansiz ---
-- RLS'i atlayan sahip yetkisiyle bile: bilesik FK yapisal olarak engeller.
select pms4_test.reddedilmeli($q$
  insert into public.pms_folio_hareketleri (otel_id, folio_id, tip, aciklama, tutar)
  values ('810', current_setting('pms4.folio811')::uuid, 'ekstra',
          'Capraz otel FK denemesi', 100.00)
$q$, 'T8f: 810 otel_id ile 811 folyosuna hareket baglanamaz (bilesik FK)');
select pms4_test.reddedilmeli($q$
  insert into public.pms_folio_odemeler (otel_id, folio_id, yontem, tutar)
  values ('810', current_setting('pms4.folio811')::uuid, 'nakit', 100.00)
$q$, 'T8f: 810 otel_id ile 811 folyosuna odeme baglanamaz (bilesik FK)');

-- --- T8g: BAR DEVRI CAPRAZ OTEL YAPILAMAZ ---
-- 811'in 402 odasi BOS; 810'un 402 odasi DOLU ve folyosu ACIK.
-- Kopru otel kapsamini kaybederse 810'un ACIK folyosunu bulup KABUL eder.
insert into public.bar_siparisleri (id, otel_id, depo_id, oda_no, durum)
values ('c2000000-0000-0000-0000-000000040811','811','BAR2','402','hazir')
on conflict (id) do nothing;
insert into public.bar_siparis_kalemleri (siparis_id, menu_urun_id, adet)
values ('c2000000-0000-0000-0000-000000040811','c1000000-0000-0000-0000-000000040811', 1);
select pms4_test.reddedilmeli($q$
  update public.bar_siparisleri set durum = 'teslim_edildi'
   where id = 'c2000000-0000-0000-0000-000000040811'
$q$, 'T8g: 811 siparisi 810 odasinin folyosuna devredilemez');
select pms4_test.dogru(
  (select count(*) = 0 from public.pms_folio_hareketleri
    where kaynak_id = 'c2000000-0000-0000-0000-000000040811'),
  'T8g: capraz otel devrinden hicbir hareket kalmadi');
-- 811'in KENDI dolu odasina devir CALISIR (test anlamli, kopru bozuk degil).
insert into public.bar_siparisleri (id, otel_id, depo_id, oda_no, durum)
values ('c2000000-0000-0000-0000-000000040812','811','BAR2','401','hazir')
on conflict (id) do nothing;
insert into public.bar_siparis_kalemleri (siparis_id, menu_urun_id, adet)
values ('c2000000-0000-0000-0000-000000040812','c1000000-0000-0000-0000-000000040811', 1);
update public.bar_siparisleri set durum = 'teslim_edildi'
 where id = 'c2000000-0000-0000-0000-000000040812';
select pms4_test.dogru(
  (select count(*) = 1 from public.pms_folio_hareketleri
    where kaynak_id = 'c2000000-0000-0000-0000-000000040812' and otel_id = '811'),
  'T8g: 811 kendi dolu odasina devri yapabiliyor');

-- --- T8i: AYNI KAYNAK IKI KEZ BORCLANDIRILAMAZ (bar retry) ---
-- Tetikleyici yalniz durum GECISINDE calistigi icin ayni siparisin ikinci
-- borcu dogrudan denenir: koruma index'tedir, tetikleyicinin sansinda degil.
set role authenticated;
select set_config('request.jwt.claim.role','authenticated',false);
select set_config('request.jwt.claim.sub','a0000000-0000-0000-0000-000000000811',false);
select pms4_test.reddedilmeli($q$
  insert into public.pms_folio_hareketleri
    (otel_id, folio_id, tip, aciklama, tutar, kaynak_tip, kaynak_id)
  values ('811', current_setting('pms4.folio811')::uuid, 'bar',
          'Ayni bar siparisi ikinci kez', 150.00,
          'bar', 'c2000000-0000-0000-0000-000000040812')
$q$, 'T8i: ayni bar siparisi ikinci kez borclandirilamaz');
select pms4_test.dogru(
  (select count(*) = 1 from public.pms_folio_hareketleri
    where kaynak_id = 'c2000000-0000-0000-0000-000000040812' and not ters_kayit),
  'T8i: kaynak basina tek borc satiri');
reset role;

-- --- T8h: capraz otel denemelerinden GERIYE HICBIR SATIR kalmadi ---
-- "Hata firlatildi" yetmez; 0 satir eklendigi ayrica olculur.
select pms4_test.dogru(
  (select count(*) = 0 from public.pms_folio_hareketleri
    where aciklama like 'Capraz otel%'),
  'T8h: capraz otel hareket denemelerinden satir kalmadi');
select pms4_test.dogru(
  (select count(*) = 0 from public.pms_folio_odemeler
    where folio_id = current_setting('pms4.folio811')::uuid),
  'T8h: reddedilen odeme denemelerinden 811 folyosuna satir gecmedi');

-- ---------------------------------------------------------------------------
-- T9 — FİNANSAL APPEND-ONLY + SİLME DENETİMİ
-- ---------------------------------------------------------------------------
set role authenticated;
select set_config('request.jwt.claim.role','authenticated',false);
select set_config('request.jwt.claim.sub','a0000000-0000-0000-0000-000000000001',false);

select pms4_test.reddedilmeli($q$
  delete from public.pms_folio_hareketleri
   where id = (select id from public.pms_folio_hareketleri
                where otel_id = '810' and tip = 'oda_ucreti' limit 1)
$q$, 'T9: finansal hareket silinemez');
select pms4_test.reddedilmeli($q$
  update public.pms_folio_hareketleri set tutar = 1
   where id = (select id from public.pms_folio_hareketleri
                where otel_id = '810' and tip = 'oda_ucreti' limit 1)
$q$, 'T9: finansal hareket tutari degistirilemez');
reset role;

-- SAHIP YETKISIYLE DE (RLS atlanir) silinemez: koruma tetikleyicidedir.
select pms4_test.reddedilmeli($q$
  delete from public.pms_folio_hareketleri
   where id = (select id from public.pms_folio_hareketleri
                where otel_id = '810' and tip = 'oda_ucreti' limit 1)
$q$, 'T9: RLS i atlayan yetkiyle de hareket silinemez');

-- Silme sonrasi mali iz YERINDE: sayim degismedi.
select pms4_test.dogru(
  (select count(*) = 3 from public.pms_folio_hareketleri h
     join public.pms_folyolar f on f.id = h.folio_id
    where f.rezervasyon_id = '11000000-0000-0000-0000-000000040001'
      and h.tip = 'oda_ucreti'),
  'T9: silme denemeleri sonrasi 3 oda ucreti hareketi duruyor');

-- Hareketi olan folyo basligi da silinemez (FK restrict).
select pms4_test.reddedilmeli($q$
  delete from public.pms_folyolar
   where rezervasyon_id = '11000000-0000-0000-0000-000000040001'
$q$, 'T9: hareketi olan folyo basligi silinemez');

-- Bos folyo basligi silinebilir AMA DENETIM IZI BIRAKIR.
insert into public.pms_rezervasyonlar
  (id, otel_id, misafir_id, oda_tipi_id, giris_tarihi, cikis_tarihi, durum, gecelik_fiyat)
values ('11000000-0000-0000-0000-000000040090','810','f0000000-0000-0000-0000-000000040001',
        'd0000000-0000-0000-0000-000000040010', current_date + 20, current_date + 22,
        'onaylandi', 100.00);

create temporary table pms4_silme_sayaci as
select count(*) as adet from public.erp_islem_audit
 where event_type = 'DELETE' and entity_type = 'pms_folyolar';

delete from public.pms_folyolar
 where rezervasyon_id = '11000000-0000-0000-0000-000000040090';

select pms4_test.dogru(
  (select count(*) = 0 from public.pms_folyolar
    where rezervasyon_id = '11000000-0000-0000-0000-000000040090'),
  'T9: bos folyo basligi silinebildi (test anlamli)');
select pms4_test.dogru(
  (select count(*) from public.erp_islem_audit
    where event_type = 'DELETE' and entity_type = 'pms_folyolar')
  = (select adet + 1 from pms4_silme_sayaci),
  'T9: folyo basligi silme DENETIM IZI uretti');

-- ---------------------------------------------------------------------------
-- T10 — ÖDEME BÜTÜNLÜĞÜ
-- ---------------------------------------------------------------------------
set role authenticated;
select set_config('request.jwt.claim.role','authenticated',false);
select set_config('request.jwt.claim.sub','a0000000-0000-0000-0000-000000000001',false);

-- NOT: 040001 folyosu T5 te KAPATILDI; bu bolum ACIK olan 040002 folyosunu
-- kullanir. Kapali folyo davranisi zaten T5 te sinaniyor.
-- Sifir odeme reddedilir.
select pms4_test.reddedilmeli($q$
  insert into public.pms_folio_odemeler (otel_id, folio_id, yontem, tutar)
  select '810', id, 'nakit', 0
    from public.pms_folyolar where rezervasyon_id = '11000000-0000-0000-0000-000000040002'
$q$, 'T10: sifir tutarli odeme reddedilir');

-- Parasal tip numeric(12,2): kurus ASLA kayan noktaya birakilmaz.
select pms4_test.dogru(
  (select bool_and(a.atttypid = 'numeric'::regtype
                   and a.atttypmod = ((12 << 16) | 2) + 4)
     from pg_attribute a
    where a.attrelid in ('public.pms_folio_odemeler'::regclass,
                         'public.pms_folio_hareketleri'::regclass)
      and a.attname = 'tutar'),
  'T10: tutar kolonlari numeric(12,2)');

-- IDEMPOTENCY ANAHTARI: ayni anahtar iki kez yazilamaz.
insert into public.pms_folio_odemeler (otel_id, folio_id, yontem, tutar, islem_anahtari)
select '810', id, 'nakit', 500.00, 'test-odeme-anahtari-0001'
  from public.pms_folyolar where rezervasyon_id = '11000000-0000-0000-0000-000000040002';
select pms4_test.reddedilmeli($q$
  insert into public.pms_folio_odemeler (otel_id, folio_id, yontem, tutar, islem_anahtari)
  select '810', id, 'nakit', 500.00, 'test-odeme-anahtari-0001'
    from public.pms_folyolar where rezervasyon_id = '11000000-0000-0000-0000-000000040002'
$q$, 'T10: ayni islem anahtari ikinci kez yazilamaz (retry guvenli)');
select pms4_test.dogru(
  (select count(*) = 1 from public.pms_folio_odemeler
    where islem_anahtari = 'test-odeme-anahtari-0001'),
  'T10: mukerrer tahsilat olusmadi');

-- Farkli anahtar kabul edilir: koruma her odemeyi bloklamiyor.
insert into public.pms_folio_odemeler (otel_id, folio_id, yontem, tutar, islem_anahtari)
select '810', id, 'nakit', 250.00, 'test-odeme-anahtari-0002'
  from public.pms_folyolar where rezervasyon_id = '11000000-0000-0000-0000-000000040002';
select pms4_test.dogru(
  (select count(*) = 1 from public.pms_folio_odemeler
    where islem_anahtari = 'test-odeme-anahtari-0002'),
  'T10: farkli anahtarli ikinci tahsilat kabul edildi');

-- NEGATIF odeme BILEREK kabul edilir = iade.
insert into public.pms_folio_odemeler (otel_id, folio_id, yontem, tutar, aciklama)
select '810', id, 'nakit', -100.00, 'Iade'
  from public.pms_folyolar where rezervasyon_id = '11000000-0000-0000-0000-000000040002';
select pms4_test.dogru(
  (select count(*) = 1 from public.pms_folio_odemeler
    where tutar = -100.00 and aciklama = 'Iade'),
  'T10: negatif odeme (iade) BILEREK kabul edilir');

-- Odeme de append-only: tahsilat silinemez, duzeltme negatif kayitla yapilir.
select pms4_test.reddedilmeli($q$
  delete from public.pms_folio_odemeler where islem_anahtari = 'test-odeme-anahtari-0002'
$q$, 'T10: tahsilat silinemez (append-only)');

-- Anahtar OTEL KAPSAMLI: 811 ayni metni kullanabilir.
select set_config('request.jwt.claim.sub','a0000000-0000-0000-0000-000000000811',false);
insert into public.pms_folio_odemeler (otel_id, folio_id, yontem, tutar, islem_anahtari)
select '811', id, 'nakit', 10.00, 'test-odeme-anahtari-0001'
  from public.pms_folyolar where rezervasyon_id = '11000000-0000-0000-0000-000000040811';
reset role;
select pms4_test.dogru(
  (select count(*) = 2 from public.pms_folio_odemeler
    where islem_anahtari = 'test-odeme-anahtari-0001'),
  'T10: idempotency anahtari otel kapsamli (811 ayni metni kullanabildi)');

-- ---------------------------------------------------------------------------
-- T11 — ÇIKIŞ YAPMIŞ ESKİ ATAMA GÜNCEL DOLULUK SAYILMAZ
-- ---------------------------------------------------------------------------
-- Adim 3: check-out atamayi pasiflestirmez. Kopru tarihe degil DURUMA baktigi
-- icin cikis yapmis konaklamaya bar devri yapilamamali.
set role authenticated;
select set_config('request.jwt.claim.role','authenticated',false);
select set_config('request.jwt.claim.sub','a0000000-0000-0000-0000-000000000001',false);
select public.pms_check_out('11000000-0000-0000-0000-000000040002');
reset role;

select pms4_test.dogru(
  (select count(*) = 1 from public.pms_oda_atamalari a
     join public.pms_rezervasyonlar r on r.id = a.rezervasyon_id
    where r.id = '11000000-0000-0000-0000-000000040002'
      and a.aktif and r.durum = 'cikis_yapildi'),
  'T11: cikis sonrasi atama aktif KALDI (test anlamli)');

insert into public.bar_siparisleri (id, otel_id, depo_id, oda_no, durum)
values ('c2000000-0000-0000-0000-000000040092','810','BAR1','402','hazir')
on conflict (id) do nothing;
insert into public.bar_siparis_kalemleri (siparis_id, menu_urun_id, adet)
values ('c2000000-0000-0000-0000-000000040092','c1000000-0000-0000-0000-000000040001', 1);
select pms4_test.reddedilmeli($q$
  update public.bar_siparisleri set durum = 'teslim_edildi'
   where id = 'c2000000-0000-0000-0000-000000040092'
$q$, 'T11: cikis yapmis eski atama guncel doluluk sayilmaz');

select 'TUM PMS ADIM 4 TESTLERI GECTI' as sonuc;
