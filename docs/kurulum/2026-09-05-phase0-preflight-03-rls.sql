-- ============================================================================
-- PHASE 0 PREFLIGHT 3/5 — RLS DURUMU VE POLITIKALAR
-- ============================================================================
-- SALT-OKUMA. Hicbir mutation icermez. Supabase SQL Editor'de calistirilabilir:
-- dosya TEK sonuc kumesi uretir (editor yalniz son sorgunun sonucunu gosterir).
--
-- rls_acik=false olan tablo, politika ne yazarsa yazsin korumasizdir.
-- rls_zorunlu (FORCE), tablo sahibinin de politikaya tabi olmasini saglar.
-- kalici=true permissive (OR ile birlesir), false restrictive (AND ile).
--
-- Ciktiyi ozel tutun: fonksiyon tanimlari ve politika ifadeleri is mantigi icerir.
-- Satir verisi, PIN, hash, JWT veya kimlik bilgisi SECILMEZ.
-- ============================================================================

select c.relname                                      as tablo,
       c.relrowsecurity                                as rls_acik,
       c.relforcerowsecurity                           as rls_zorunlu,
       p.polname                                       as politika,
       p.polpermissive                                 as kalici,
       case p.polcmd when 'r' then 'SELECT' when 'a' then 'INSERT'
                     when 'w' then 'UPDATE' when 'd' then 'DELETE'
                     when '*' then 'ALL' end           as komut,
       coalesce(array_to_string(array(
         select pg_get_userbyid(x) from unnest(p.polroles) x), ', '), 'PUBLIC') as roller,
       pg_get_expr(p.polqual, p.polrelid)              as using_ifadesi,
       pg_get_expr(p.polwithcheck, p.polrelid)         as with_check_ifadesi
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
left join pg_policy p on p.polrelid = c.oid
where n.nspname = 'public' and c.relkind in ('r','p')
order by c.relrowsecurity, c.relname, p.polname nulls first;
