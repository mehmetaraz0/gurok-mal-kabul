-- ============================================================================
-- PHASE 0 PREFLIGHT 2/5 — TABLO VE KOLON IZINLERI
-- ============================================================================
-- SALT-OKUMA. Hicbir mutation icermez. Supabase SQL Editor'de calistirilabilir:
-- dosya TEK sonuc kumesi uretir (editor yalniz son sorgunun sonucunu gosterir).
--
-- Devralinan ve kolon bazli izinler dahil. anon satiri CIKMAMALI:
-- 2026-08-09 tarihinde anon tum tablolardan alinmisti (56 -> 0).
--
-- Ciktiyi ozel tutun: fonksiyon tanimlari ve politika ifadeleri is mantigi icerir.
-- Satir verisi, PIN, hash, JWT veya kimlik bilgisi SECILMEZ.
-- ============================================================================

select 'tablo'  as kapsam, table_name as nesne, null::text as kolon,
       grantee as rol, privilege_type as izin
from information_schema.table_privileges
where table_schema = 'public' and grantee in ('PUBLIC','anon','authenticated','service_role')
union all
select 'kolon', table_name, column_name, grantee, privilege_type
from information_schema.column_privileges
where table_schema = 'public' and grantee in ('PUBLIC','anon','authenticated','service_role')
union all
select 'rol_uyeligi', pg_get_userbyid(roleid)::text, null,
       pg_get_userbyid(member)::text, 'MEMBER'
from pg_auth_members
union all
select 'varsayilan_acl', coalesce(n.nspname,'(global)'), d.defaclobjtype::text,
       d.defaclrole::regrole::text, coalesce(array_to_string(d.defaclacl::text[], ', '), '(yok)')
from pg_default_acl d
left join pg_namespace n on n.oid = d.defaclnamespace
order by 1, 2, 3, 4, 5;
