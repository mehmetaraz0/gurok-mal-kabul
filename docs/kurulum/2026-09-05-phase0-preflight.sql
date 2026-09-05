-- READ ONLY, main ERP database. Run as postgres before reviewing/deploying
-- phase0-hardening.sql. Save the metadata privately for recovery. No row data,
-- PINs, hashes, JWTs or credentials are selected. Review DDL literals before sharing.
begin transaction read only;
select current_database() as database_name, current_user as database_role,
       current_setting('server_version') as postgres_version;

-- Actual overloads/bodies/owners/ACLs, not chronology inferred from filenames.
select p.oid::regprocedure as signature, pg_get_userbyid(p.proowner) as owner,
       p.prosecdef as security_definer, p.proconfig, p.proacl,
       md5(pg_get_functiondef(p.oid)) as definition_fingerprint,
       has_function_privilege('anon',p.oid,'EXECUTE') as anon_execute,
       has_function_privilege('authenticated',p.oid,'EXECUTE') as staff_execute,
       has_function_privilege('service_role',p.oid,'EXECUTE') as backend_execute,
       pg_get_functiondef(p.oid) as definition
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname in ('public','phase0_private') and p.prokind='f'
  and (p.prosecdef or p.proname like 'auth_%' or p.proname in ('stok_ekle','stok_transfer'))
order by p.oid::regprocedure::text;

select c.relname, pg_get_userbyid(c.relowner) as owner,
       c.relrowsecurity, c.relforcerowsecurity, c.relacl
from pg_class c join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and c.relkind in ('r','p','v') order by c.relname;
select * from pg_policies where schemaname='public' order by tablename,policyname;
select table_name,column_name,data_type,udt_name,is_nullable
from information_schema.columns where table_schema='public' order by table_name,ordinal_position;
select c.conrelid::regclass as source_table,c.confrelid::regclass as referenced_table,
       c.conname,c.convalidated,pg_get_constraintdef(c.oid) as definition
from pg_constraint c join pg_namespace n on n.oid=c.connamespace
where n.nspname='public' and c.contype in ('f','p','u') order by c.conrelid::regclass::text,c.conname;
select table_name,grantee,privilege_type from information_schema.table_privileges
where table_schema='public' and grantee in ('PUBLIC','anon','authenticated','service_role')
order by table_name,grantee,privilege_type;
select table_name,column_name,grantee,privilege_type from information_schema.column_privileges
where table_schema='public' and grantee in ('PUBLIC','anon','authenticated','service_role')
order by table_name,column_name,grantee;
select pg_get_userbyid(roleid) as granted_role, pg_get_userbyid(member) as member_role
from pg_auth_members order by 1,2;
select n.nspname,d.defaclrole::regrole,d.defaclobjtype,d.defaclacl
from pg_default_acl d left join pg_namespace n on n.oid=d.defaclnamespace;
select c.relname,t.tgname,pg_get_triggerdef(t.oid) as definition
from pg_trigger t join pg_class c on c.oid=t.tgrelid
join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and not t.tgisinternal order by c.relname,t.tgname;
select viewname,definition from pg_views
where schemaname='public' order by viewname;

-- Counts only. Never repair assignment data automatically.
select count(*) filter(where aktif and otel_id is null and not tum_oteller) as unassigned_staff,
       count(*) filter(where aktif and rol_id is null) as staff_without_role,
       count(*) filter(where not aktif and auth_user_id is not null) as inactive_linked_users
from public.kullanicilar;
select count(*) as duplicate_identity_groups from (
  select auth_user_id from public.kullanicilar where auth_user_id is not null
  group by auth_user_id having count(*)>1
) duplicates;
do $$ declare t record; invalid_count bigint; begin
  for t in select c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
    join pg_attribute a on a.attrelid=c.oid and a.attname='otel_id' and not a.attisdropped
    where n.nspname='public' and c.relkind in ('r','p') loop
    execute format('select count(*) from public.%I where otel_id is null or
      not (otel_id::text=any(enum_range(null::public.otel_id)::text[]))',t.relname) into invalid_count;
    raise notice 'Table %, missing/invalid hotel count: % (review intentional exceptions)',t.relname,invalid_count;
  end loop;
end $$;

-- Stock is the existing DB-side depot reference, NOT a complete depot master.
-- Any nonzero count needs an explicit data/reference decision before deployment.
select count(*) as ambiguous_depot_codes from (
  select depo_kodu from public.stok group by depo_kodu
  having count(distinct otel_id)>1
) ambiguous;
select count(*) as bar_orders_without_registered_hotel_depot
from public.bar_siparisleri b where not exists (
  select 1 from public.stok s where s.depo_kodu=b.depo_id and s.otel_id=b.otel_id
);
select count(*) as cross_hotel_bar_items
from public.bar_siparis_kalemleri k
join public.bar_siparisleri b on b.id=k.siparis_id
join public.menu_urunler m on m.id=k.menu_urun_id
where b.otel_id is distinct from m.otel_id;
select count(*) as cross_hotel_invoice_orders
from public.faturalar f join public.siparisler s on s.siparis_no=f.siparis_no
where f.otel_id::text is distinct from s.otel_id::text;
rollback;
