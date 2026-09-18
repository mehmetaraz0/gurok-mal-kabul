-- ===========================================================================
-- DUMAN TESTI BELGESI — DOGRUDAN KONTROL (SALT OKUMA)
-- ===========================================================================
-- T2a'da sayaclar degismedi. Bu, belgenin kaydedilmedigini KANITLAMAZ:
-- baska numara/otelle kaydedilmis ya da tetikleyicinin calismadigi bir yoldan
-- yazilmis olabilir. Belge burada numarasi, irsaliyesi ve firma adiyla AYRI
-- AYRI aranir. RLS'siz (postgres) calisir: otel gorunurlugunden bagimsizdir.
--
--   .\docs\kurulum\sql-uygula.ps1 -Dosya docs\kurulum\2026-09-18-stok-tarih-duman-belge-kontrol.sql -SaltOkuma
-- ===========================================================================
set default_transaction_read_only = on;
\pset pager off

\echo '=== A) sunucu saati ==='
select now() as sunucu_saati;

\echo '=== B) mal_kabuller: numara / irsaliye / firma / not ile (her biri ayri isaretli) ==='
select mk.id, mk.mk_no, mk.otel_id, mk.depo_kodu, mk.firma_ad, mk.irsaliye_no, mk.fatura_no,
       mk.ln_siparis_no, mk.durum, mk.stok_islendi, mk.tarih, mk.form_tarihi, mk.personel_ad,
       mk.mk_no = 'MK-2026-00031'                 as numara_eslesti,
       mk.irsaliye_no = 'DUMAN-2026-09-18'         as irsaliye_eslesti,
       mk.firma_ad ilike '%DUMAN%'                 as firma_eslesti,
       coalesce(mk.notlar, '') ilike '%DUMAN%'     as not_eslesti
  from public.mal_kabuller mk
 where mk.mk_no = 'MK-2026-00031'
    or mk.irsaliye_no ilike '%DUMAN%'
    or mk.firma_ad ilike '%DUMAN%'
    or coalesce(mk.notlar, '') ilike '%DUMAN%';

\echo '=== C) bu yilin son 5 belgesi (numara sirasi) + toplam ==='
select mk_no, otel_id, firma_ad, irsaliye_no, durum, stok_islendi, tarih
  from public.mal_kabuller
 where mk_no like 'MK-2026-%'
 order by mk_no desc
 limit 5;
select count(*) as bu_yil_belge from public.mal_kabuller where mk_no like 'MK-2026-%';

\echo '=== D) bulunan belgenin kalemleri ==='
select u.mk_id, u.urun_kodu, u.urun_adi, u.birim, u.miktar
  from public.mal_kabul_urunleri u
  join public.mal_kabuller mk on mk.id = u.mk_id
 where mk.mk_no = 'MK-2026-00031' or mk.irsaliye_no ilike '%DUMAN%' or mk.firma_ad ilike '%DUMAN%';

\echo '=== E) stok_hareketleri: belge no ya da aciklamada DUMAN / 00031 ==='
select id, tarih, tip, urun_kodu, depo_kodu, kaynak_depo_kodu, miktar, belge_no, aciklama
  from public.stok_hareketleri
 where belge_no = 'MK-2026-00031'
    or coalesce(aciklama, '') ilike '%DUMAN%'
    or coalesce(aciklama, '') ilike '%MK-2026-00031%'
 order by tarih;

\echo '=== F) YIY06000002 stok satirlari ve son hareketleri ==='
select depo_kodu, miktar, guncelleme_tarihi from public.stok where urun_kodu = 'YIY06000002' order by depo_kodu;
select tarih, tip, depo_kodu, kaynak_depo_kodu, miktar, belge_no
  from public.stok_hareketleri where urun_kodu = 'YIY06000002' order by tarih desc limit 5;

\echo '=== G) denetim izleri (satirin TAMAMINDA metin aramasi; sutun adindan bagimsiz) ==='
select 'erp_islem_audit' as tablo, count(*) as eslesen
  from public.erp_islem_audit a
 where to_jsonb(a)::text ilike '%DUMAN%' or to_jsonb(a)::text ilike '%MK-2026-00031%'
union all
select 'audit_log', count(*)
  from public.audit_log a
 where to_jsonb(a)::text ilike '%DUMAN%' or to_jsonb(a)::text ilike '%MK-2026-00031%';

select left(to_jsonb(a)::text, 400) as erp_islem_audit_satiri
  from public.erp_islem_audit a
 where to_jsonb(a)::text ilike '%DUMAN%' or to_jsonb(a)::text ilike '%MK-2026-00031%';
select left(to_jsonb(a)::text, 400) as audit_log_satiri
  from public.audit_log a
 where to_jsonb(a)::text ilike '%DUMAN%' or to_jsonb(a)::text ilike '%MK-2026-00031%';

\echo '=== G2) erp_islem_audit: bulunan belgenin id si ile (metinde numara gecmeyebilir) ==='
select a.server_timestamp, a.event_type, a.entity_type, a.entity_id
  from public.erp_islem_audit a
 where a.entity_id::text in (
         select mk.id::text from public.mal_kabuller mk
          where mk.mk_no = 'MK-2026-00031' or mk.irsaliye_no ilike '%DUMAN%' or mk.firma_ad ilike '%DUMAN%')
 order by a.server_timestamp;

\echo '=== H) son 1 saatte yazilan denetim satirlari (herhangi bir kaynak) ==='
select count(*) as erp_islem_audit_son_1_saat
  from public.erp_islem_audit where server_timestamp > now() - interval '1 hour';
