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

select 'TUM PMS ADIM 4 TESTLERI GECTI' as sonuc;
