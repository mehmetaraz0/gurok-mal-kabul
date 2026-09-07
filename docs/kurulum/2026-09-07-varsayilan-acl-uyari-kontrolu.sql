-- ============================================================================
-- VARSAYILAN ACL — SALT OKUMA UYARI KONTROLÜ
-- Tarih: 2026-09-07 · Yeniden çalıştırılabilir · Her yayından ÖNCE
--
-- BU DOSYA HİÇBİR ŞEY DEĞİŞTİRMEZ. Yalnız `select` içerir.
-- Supabase SQL Editor'e yapıştırılır (.ps1 değil — bu bir .sql dosyasıdır).
--
-- NEDEN AYRI BİR DOSYA:
--   `2026-09-07-post-pms-faz1-uretim-parmakizi.sql` PMS Faz 1 kapanışının
--   TARİHSEL kanıtıdır ve 28/28 sonucu belgelenmiştir. İçine yeni kontrol
--   eklemek o kaydı geçersiz kılardı. Bu dosya onun yerine geçmez; yanında
--   çalışır ve yalnız ACL katmanına bakar.
--
-- ARKA PLAN:
--   `pg_default_acl`, YENİ oluşturulacak nesnelerin doğuştan hangi haklarla
--   geleceğini söyler ve kayıtlar NESNEYİ OLUŞTURAN ROLE göre tutulur.
--   Aynı şemada `postgres` bir varsayılan, `supabase_admin` başka bir
--   varsayılan taşıyabilir — ve taşıyor. Bir rolün varsayılanını yalnız o rol
--   (veya üyesi olan biri) değiştirebilir; SQL Editor `postgres` olarak
--   çalıştığı için `supabase_admin` varsayılanına dokunamaz.
--
--   Bu, Phase 0'da sessizce başarısız oldu: migration `supabase_admin`
--   varsayılanını geri almayı denedi, üyelik olmadığı için `exception when
--   insufficient_privilege` dalına düştü ve yalnız `notice` yazdı.
--
-- YORUMLAMA:
--   tur = 'esit'  -> bulunan <> beklenen ise SAPMA. Yayını durdur.
--   tur = 'uyari' -> bulunan > beklenen ise KNOWN PLATFORM RISK büyümüş
--                    demektir; blocker değil, ama açıklanmadan geçilmez.
--   tur = 'bilgi' -> karar kriteri değil, kayıttır.
--
-- Ayrıntı ve destek metni: docs/kurulum/2026-09-07-varsayilan-acl-bulgusu.md
-- ============================================================================

with

-- ---------------------------------------------------------------------------
-- A) BİZİM migration rolümüz: `postgres`, şema `public`
--    Migration'larımız SQL Editor üzerinden `postgres` olarak çalışır.
--    Bu satırların anon içermemesi, ürettiğimiz her yeni nesnenin kapalı
--    doğduğu anlamına gelir.
-- ---------------------------------------------------------------------------
postgres_public as (
  select d.defaclobjtype::text as tur,
         coalesce(array_to_string(d.defaclacl::text[], ', '), '(yok)') as acl
    from pg_default_acl d
    join pg_namespace n on n.oid = d.defaclnamespace
   where d.defaclrole = 'postgres'::regrole
     and n.nspname = 'public'
),
a1_postgres_anon as (
  select count(*) n from postgres_public where acl like '%anon=%'
),

-- ---------------------------------------------------------------------------
-- B) PLATFORM rolü: `supabase_admin`, şema `public`
--    Bunlar bizim değiştiremediğimiz kayıtlardır. Beklenen değer 3'tür
--    (tablo `r`, sekans `S`, fonksiyon `f`) ve bu BİLİNEN RİSKTİR.
--    3'ten BÜYÜKSE yeni bir nesne türü de açılmış demektir.
-- ---------------------------------------------------------------------------
b1_supabase_admin_anon as (
  select count(*) n
    from pg_default_acl d
    join pg_namespace n on n.oid = d.defaclnamespace
   where d.defaclrole = 'supabase_admin'::regrole
     and n.nspname = 'public'
     and exists (select 1 from unnest(d.defaclacl) a where a::text like 'anon=%')
),

-- ---------------------------------------------------------------------------
-- C) TOPLAM sayaçlar — 2026-09-07 ölçümüyle karşılaştırılır.
--    Bu iki sayı parmak izindeki F1 / F2 ile AYNI tanımdır; kasten aynı
--    tutuldu ki iki dosya birbirini doğrulayabilsin.
-- ---------------------------------------------------------------------------
c1_anon_ureten_toplam as (
  select count(*) n from pg_default_acl d
   where exists (select 1 from unnest(d.defaclacl) a where a::text like 'anon=%')
),
c2_kayit_toplam as (select count(*) n from pg_default_acl),

-- ---------------------------------------------------------------------------
-- D) ETKİ ÖLÇÜMÜ — varsayılan ACL bir NİYET beyanıdır; asıl soru
--    üretimde GERÇEKTEN anon'a açık nesne olup olmadığıdır.
--    Bu üç sayı `public` şemasındaki fiili durumu ölçer ve HEPSİ 0 olmalıdır.
--    D3 ilk ölçümde (2026-09-07) 18'di; 2026-09-08 temizliğiyle 0'a indi.
--    Varsayılan ACL riski gerçekleşirse önce burası kırmızıya döner.
-- ---------------------------------------------------------------------------
d1_anon_tablo as (
  select count(*) n from information_schema.role_table_grants
   where table_schema = 'public' and grantee = 'anon'
),
d2_anon_sekans as (
  select count(*) n from information_schema.role_usage_grants
   where object_schema = 'public' and grantee = 'anon' and object_type = 'SEQUENCE'
),
d3_anon_fonksiyon as (
  select count(*) n from pg_proc p
    join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public'
     and (has_function_privilege('anon', p.oid, 'EXECUTE'))
),

-- ---------------------------------------------------------------------------
-- E) DÖKÜM — hangi kaydın kime ait olduğunu satır satır gösterir.
--    Sayı sapınca "hangisi?" sorusunu cevaplayan tek şey budur.
-- ---------------------------------------------------------------------------
e1_dokum as (
  select coalesce(n.nspname, '(global)') as sema,
         d.defaclrole::regrole::text     as olusturan_rol,
         d.defaclobjtype::text           as nesne_turu,
         coalesce(array_to_string(d.defaclacl::text[], ', '), '(yok)') as acl,
         (exists (select 1 from unnest(d.defaclacl) a where a::text like 'anon=%')) as anon_var
    from pg_default_acl d
    left join pg_namespace n on n.oid = d.defaclnamespace
)

-- ============================================================================
-- SONUÇ 1 — KARAR TABLOSU
-- ============================================================================
select 1 as blok, kontrol, bulunan, beklenen, tur,
       case when tur = 'bilgi' then 'KAYIT'
            when tur = 'uyari' and bulunan > beklenen then 'RISK BUYUDU'
            when tur = 'uyari' then 'BILINEN RISK'
            when bulunan = beklenen then 'ESIT'
            else 'SAPMA' end as durum
from (values
  -- Bizim rolümüz: anon üretmemeli. Bu SAPARSA yeni nesnelerimiz açık doğar.
  ('A1 postgres/public varsayilan ACL anon uretiyor',
                                    (select n from a1_postgres_anon),      0,  'esit'),

  -- Platform rolü: bilinen ve kabul edilen risk. 3 = tablo + sekans + fonksiyon.
  ('B1 supabase_admin/public anon ureten kayit',
                                    (select n from b1_supabase_admin_anon), 3, 'uyari'),

  -- Toplamlar: 2026-09-07 ölçümü F1=12, F2=24.
  ('C1 anon ureten varsayilan ACL (tum semalar)',
                                    (select n from c1_anon_ureten_toplam), 12, 'uyari'),
  ('C2 varsayilan ACL kaydi (toplam)',
                                    (select n from c2_kayit_toplam),       24, 'esit'),

  -- Fiili etki: hepsi 0 olmalı. Risk gerçekleşirse ilk burası kırmızıya döner.
  ('D1 anon tablo hakki (public)',  (select n from d1_anon_tablo),          0, 'esit'),
  ('D2 anon sekans USAGE (public)', (select n from d2_anon_sekans),         0, 'esit'),
  ('D3 anon EXECUTE fonksiyon (public)',
                                    (select n from d3_anon_fonksiyon),      0, 'esit')
) as t(kontrol, bulunan, beklenen, tur)

union all

-- ============================================================================
-- SONUÇ 2 — DÖKÜM (bilgi)
-- ============================================================================
select 2, sema || ' / ' || olusturan_rol || ' / ' || nesne_turu,
       case when anon_var then 1 else 0 end, -1, 'bilgi', acl
from e1_dokum

order by 1, 2;

-- ============================================================================
-- STOP KRİTERLERİ
-- ----------------------------------------------------------------------------
-- A1 <> 0        -> DUR. Bizim migration rolümüzün varsayılanı anon'a hak
--                   üretiyor. Phase 0'ın `alter default privileges for role
--                   postgres in schema public revoke execute on functions
--                   from anon` satırı geri alınmış olabilir. Yayını durdur.
--
-- D3 <> 0        -> DUR. `public` semasinda anon'a EXECUTE acik fonksiyon var.
--                   2026-09-08'de 18'den 0'a indirildi
--                   (`2026-09-08-pms-fonksiyon-acl-temizligi.sql`); yeniden
--                   yukselmesi, ACL karari verilmemis yeni bir fonksiyon
--                   eklendigi anlamina gelir.
--
-- D1/D2 <> 0     -> DUR. Varsayılan ACL riski ARTIK TEORİK DEĞİL: üretimde
--                   anon'a açık nesne var. Hangi nesne olduğunu bulmadan
--                   ilerleme.
--
-- B1 > 3         -> DURMA, AÇIKLA. Platform yeni bir nesne türünü de anon'a
--                   açmış. Bulgu dosyasını güncelle, destek kaydını yenile.
--
-- C1 > 12        -> DURMA, AÇIKLA. Yeni bir şemada anon üreten varsayılan
--                   belirmiş. Döküm bloğundan hangisi olduğuna bak.
-- ============================================================================
