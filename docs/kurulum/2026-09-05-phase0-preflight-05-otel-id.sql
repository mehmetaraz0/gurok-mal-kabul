-- ============================================================================
-- PHASE 0 PREFLIGHT 5/5 — OTEL_ID ENUM UYUMU
-- ============================================================================
-- SALT-OKUMA. Hicbir mutation icermez. Supabase SQL Editor'de calistirilabilir:
-- dosya TEK sonuc kumesi uretir (editor yalniz son sorgunun sonucunu gosterir).
--
-- otel_id tasiyan HER tabloda, enum disi veya bos deger sayilir.
-- Bu onemlidir: yeni auth_otel_erisim, enum disi bir degeri FALSE sayar.
-- Enum disi satir varsa, sertlestirme sonrasi o satirlar gorunmez olur.
--
-- kullanicilar tablosundaki bos otel_id icin 4/5 numarali dosyaya bakin:
-- merkez kullanicilarinda bos olmasi mesrudur.
--
-- Ciktiyi ozel tutun: fonksiyon tanimlari ve politika ifadeleri is mantigi icerir.
-- Satir verisi, PIN, hash, JWT veya kimlik bilgisi SECILMEZ.
-- ============================================================================

select t.tablo,
       t.toplam,
       t.bos_otel_id,
       t.enum_disi,
       case when t.enum_disi > 0 then 'ENGEL — sertlestirme sonrasi gorunmez olur'
            when t.bos_otel_id > 0 then 'INCELE — merkez istisnasi olabilir'
            else 'temiz' end as durum
from (
  select c.relname::text as tablo,
         (select count(*) from pg_class x where x.oid = c.oid) * 0
           + (xpath('/row/c/text()', query_to_xml(
               format('select count(*) as c from public.%I', c.relname),
               false, true, '')))[1]::text::bigint as toplam,
         (xpath('/row/c/text()', query_to_xml(
             format('select count(*) as c from public.%I where otel_id is null', c.relname),
             false, true, '')))[1]::text::bigint as bos_otel_id,
         (xpath('/row/c/text()', query_to_xml(
             format('select count(*) as c from public.%I where otel_id is not null
                     and not (otel_id::text = any(enum_range(null::public.otel_id)::text[]))',
                    c.relname), false, true, '')))[1]::text::bigint as enum_disi
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  join pg_attribute a on a.attrelid = c.oid and a.attname = 'otel_id' and not a.attisdropped
  where n.nspname = 'public' and c.relkind in ('r','p')
) t
order by t.enum_disi desc, t.bos_otel_id desc, t.tablo;
