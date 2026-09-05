-- Phase 0, main ERP project ONLY. Manual deployment after preflight review.
-- This is an overlay, NOT a replay of the historical schema dump.
-- Unknown RPC shapes/policies abort the whole transaction. Capture pre-change
-- definitions/ACLs with phase0-preflight.sql before applying; see the runbook.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';
set local search_path = pg_catalog, public, pg_temp;

do $$
begin
  if current_user <> 'postgres' then
    raise exception 'Phase 0 requires the database owner and a reviewed preflight';
  end if;
  if to_regclass('public.kullanicilar') is null
     or to_regclass('public.audit_log') is null
     or to_regprocedure('public.auth_otel_erisim(text)') is null then
    raise exception 'Not a supported main ERP database';
  end if;
  if exists (select 1 from public.kullanicilar where auth_user_id is not null
             group by auth_user_id having count(*) > 1) then
    raise exception 'Duplicate Auth identities: resolve assignments before migration';
  end if;
end;
$$;

create schema if not exists phase0_private;
revoke all on schema phase0_private from public, anon, authenticated, service_role;
revoke create on schema public from public, anon, authenticated;
create unique index if not exists phase0_kullanici_auth_unique
  on public.kullanicilar(auth_user_id) where auth_user_id is not null;

-- Canonical identity helpers. They never authorize from client profile fields.
create or replace function public.auth_kullanici_rol_id()
returns uuid language sql stable security definer set search_path = pg_catalog, public, pg_temp as $$
  select k.rol_id from public.kullanicilar k
  where k.auth_user_id = auth.uid() and k.aktif is true;
$$;
create or replace function public.auth_kullanici_id()
returns text language sql stable security definer set search_path = pg_catalog, public, pg_temp as $$
  select k.id::text from public.kullanicilar k
  where k.auth_user_id = auth.uid() and k.aktif is true;
$$;
create or replace function public.auth_erp_kullanicisi()
returns boolean language sql stable security definer set search_path = pg_catalog, public, pg_temp as $$
  select exists (select 1 from public.kullanicilar k
    where k.auth_user_id = auth.uid() and k.aktif is true);
$$;
create or replace function public.auth_otel_id()
returns text language sql stable security definer set search_path = pg_catalog, public, pg_temp as $$
  select k.otel_id::text from public.kullanicilar k
  where k.auth_user_id = auth.uid() and k.aktif is true;
$$;
create or replace function public.auth_tum_oteller()
returns boolean language sql stable security definer set search_path = pg_catalog, public, pg_temp as $$
  select exists (select 1 from public.kullanicilar k
    where k.auth_user_id = auth.uid() and k.aktif is true and k.tum_oteller is true);
$$;
create or replace function public.auth_otel_erisim(p_otel text)
returns boolean language sql stable security definer set search_path = pg_catalog, public, pg_temp as $$
  select exists (
    select 1 from public.kullanicilar k
    where k.auth_user_id = auth.uid() and k.aktif is true
      and p_otel = any(enum_range(null::public.otel_id)::text[])
      and (k.tum_oteller is true or k.otel_id::text = p_otel)
  );
$$;
create or replace function public.auth_yetki_var(p_modul_kod text, p_min_seviye text default 'goruntule')
returns boolean language sql stable security definer set search_path = pg_catalog, public, pg_temp as $$
  select exists (
    select 1 from public.kullanicilar k
    join public.yetki_matrisi ym on ym.rol_id = k.rol_id
    join public.moduller m on m.id = ym.modul_id
    where k.auth_user_id = auth.uid() and k.aktif is true
      and m.kod = p_modul_kod and m.aktif is true
      and ym.yetki::text = any(case p_min_seviye
        when 'goruntule' then array['goruntule','kayit','tam']
        when 'kayit' then array['kayit','tam']
        when 'tam' then array['tam'] else array[]::text[] end)
  );
$$;

-- Explicit, previously identified scope. Shared master data is not hotelized.
create or replace function phase0_private.scope_tables()
returns table(tablo text, parent_table text, parent_key text)
language sql immutable set search_path = pg_catalog as $$
  values
    ('stok',null,null), ('stok_hareketleri',null,null), ('stok_minimumlar',null,null),
    ('faturalar',null,null), ('mal_kabuller',null,null), ('koli_etiketleri',null,null),
    ('ic_talepler',null,null), ('satin_alma_talepleri',null,null),
    ('siparisler',null,null), ('teklif_talepleri',null,null),
    ('menu_urunler',null,null), ('bar_siparisleri',null,null), ('stok_rezervasyonlari',null,null),
    ('banka_kasa_hesaplari',null,null), ('banka_kasa_hareketleri',null,null),
    ('cari_hareketler',null,null), ('cek_senetler',null,null), ('demirbaslar',null,null),
    ('butce_kayitlari',null,null), ('yevmiye_fisler',null,null),
    ('receteler',null,null), ('recete_tuketimleri',null,null),
    ('skt_kayitlari',null,null), ('uygunsuzluklar',null,null),
    ('sayim_oturumlari',null,null), ('edefter_sube_bilgileri',null,null),
    ('fatura_kalemleri','faturalar','fatura_id'),
    ('mal_kabul_urunleri','mal_kabuller','mk_id'),
    ('teklif_kalemleri','teklif_talepleri','teklif_talebi_id'),
    ('teklif_fiyatlari','teklif_kalemleri','teklif_kalemi_id'),
    ('siparis_kalemleri','siparisler','siparis_no'),
    ('satin_alma_talep_kalemleri','satin_alma_talepleri','talep_id'),
    ('ic_talep_kalemleri','ic_talepler','talep_id'),
    ('bar_siparis_kalemleri','bar_siparisleri','siparis_id'),
    ('recete_bilesenleri','menu_urunler','menu_urun_id'),
    ('recete_kalemleri','receteler','recete_id'),
    ('yevmiye_kalemleri','yevmiye_fisler','fis_id'),
    ('sayim_detaylari','sayim_oturumlari','oturum_id'),
    ('talep_onay_gecmisi','satin_alma_talepleri','talep_id');
$$;

-- Private resolver: RLS calls the nonlocking wrapper below. Writes validate
-- and lock referenced rows, including references reached inside DEFINER RPCs.
create or replace function phase0_private.row_hotel(
  p_table text, p_row jsonb, p_lock boolean, p_seen text[] default array[]::text[]
) returns text language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare
  v_scope record; v_ref record; v_parent jsonb; v_hotel text; v_other text;
  v_key text; v_type text; v_where text; v_keys jsonb;
begin
  if p_table = any(p_seen) then raise exception 'Unsupported hotel-reference cycle'; end if;
  select * into v_scope from phase0_private.scope_tables() where tablo = p_table;
  if not found then raise exception 'Unreviewed scope table: %', p_table; end if;
  if v_scope.parent_table is null then
    v_hotel := p_row->>'otel_id';
  else
    v_key := case when v_scope.parent_table = 'siparisler' then 'siparis_no' else 'id' end;
    select format_type(a.atttypid,a.atttypmod) into v_type from pg_attribute a
      where a.attrelid = to_regclass('public.' || v_scope.parent_table) and a.attname = v_key;
    execute format('select to_jsonb(t) from public.%I t where %I = $1::%s%s',
      v_scope.parent_table, v_key, v_type, case when p_lock then ' for share' else '' end)
      into v_parent using p_row->>v_scope.parent_key;
    if v_parent is null and p_lock then
      -- A cascading DELETE can no longer see its deleted parent. Only a
      -- protected, same-transaction BEFORE DELETE event can supply that scope.
      select a.hotel_id::text into v_hotel from public.erp_islem_audit a
        where a.transaction_id=pg_current_xact_id()::text and a.event_type='DELETE'
          and a.entity_type=v_scope.parent_table and a.entity_key->>v_key=p_row->>v_scope.parent_key
        order by a.id desc limit 1;
    elsif v_parent is not null then
      v_hotel := phase0_private.row_hotel(v_scope.parent_table,v_parent,p_lock,p_seen || p_table);
    end if;
  end if;
  if v_hotel is null or not (v_hotel = any(enum_range(null::public.otel_id)::text[])) then return null; end if;
  if auth.role() is distinct from 'service_role' and public.auth_otel_erisim(v_hotel) is not true then
    return null;
  end if;
  if not p_lock then return v_hotel; end if;

  -- All existing FKs to scoped tables, including composite FKs. Shared master
  -- references (e.g. cariler) remain shared. FK constraints enforce existence.
  for v_ref in
    select c.*, cl.relname as parent_name
    from pg_constraint c join pg_class cl on cl.oid = c.confrelid
    join pg_namespace ns on ns.oid = cl.relnamespace
    join phase0_private.scope_tables() s on s.tablo = cl.relname
    where c.conrelid = to_regclass('public.' || p_table) and c.contype = 'f'
      and ns.nspname = 'public'
  loop
    if exists (select 1 from unnest(v_ref.conkey) k
      join pg_attribute a on a.attrelid = v_ref.conrelid and a.attnum = k
      where p_row->>a.attname is null) then continue; end if;
    select string_agg(format('t.%I = ($1->>%L)::%s',b.attname,a.attname,
      format_type(b.atttypid,b.atttypmod)), ' and ' order by keys.n)
    into v_where
    from unnest(v_ref.conkey,v_ref.confkey) with ordinality keys(ak,bk,n)
    join pg_attribute a on a.attrelid=v_ref.conrelid and a.attnum=keys.ak
    join pg_attribute b on b.attrelid=v_ref.confrelid and b.attnum=keys.bk;
    execute format('select to_jsonb(t) from public.%I t where %s for share',v_ref.parent_name,v_where)
      into v_parent using p_row;
    if v_parent is null then
      select jsonb_object_agg(b.attname,p_row->a.attname) into v_keys
      from unnest(v_ref.conkey,v_ref.confkey) keys(ak,bk)
      join pg_attribute a on a.attrelid=v_ref.conrelid and a.attnum=keys.ak
      join pg_attribute b on b.attrelid=v_ref.confrelid and b.attnum=keys.bk;
      select a.hotel_id::text into v_other from public.erp_islem_audit a
        where a.transaction_id=pg_current_xact_id()::text and a.event_type='DELETE'
          and a.entity_type=v_ref.parent_name and a.entity_key @> v_keys
        order by a.id desc limit 1;
    else
      v_other := phase0_private.row_hotel(v_ref.parent_name,v_parent,true,p_seen || p_table);
    end if;
    if v_other is distinct from v_hotel then return null; end if;
    if v_parent is not null and p_table = 'koli_etiketleri' and v_ref.parent_name = 'mal_kabul_urunleri'
       and p_row->>'mk_id' is distinct from v_parent->>'mk_id' then return null; end if;
  end loop;

  -- These client-supplied links are not consistently backed by historical FKs.
  if p_table = 'teklif_kalemleri' and p_row->>'kaynak_ic_talep_kalemi_id' is not null then
    select to_jsonb(t) into v_parent from public.ic_talep_kalemleri t
      where t.id = (p_row->>'kaynak_ic_talep_kalemi_id')::uuid for share;
    if v_parent is null or phase0_private.row_hotel('ic_talep_kalemleri',v_parent,true,p_seen || p_table)
       is distinct from v_hotel then return null; end if;
  end if;
  if p_table = 'faturalar' and nullif(p_row->>'siparis_no','') is not null then
    select to_jsonb(t) into v_parent from public.siparisler t
      where t.siparis_no = p_row->>'siparis_no' for share;
    if v_parent is null or phase0_private.row_hotel('siparisler',v_parent,true,p_seen || p_table)
       is distinct from v_hotel then return null; end if;
  end if;
  if p_table in ('bar_siparisleri','stok_rezervasyonlari') then
    -- Stock is the available server-side depot reference. Unregistered/ambiguous
    -- depots are rejected; preflight must identify them before deployment.
    perform 1 from public.stok s where s.depo_kodu = p_row->>'depo_id'
      and s.otel_id::text = v_hotel
      and (p_table = 'bar_siparisleri' or s.urun_kodu = p_row->>'stok_kodu') for share;
    if not found then return null; end if;
    if exists (select 1 from public.stok s where s.depo_kodu = p_row->>'depo_id'
      and s.otel_id::text is distinct from v_hotel) then return null; end if;
  end if;
  return v_hotel;
end;
$$;

create or replace function public.phase0_otel_kapsami(p_tablo text,p_satir jsonb)
returns boolean language sql security definer set search_path = pg_catalog, public, pg_temp as $$
  select public.auth_erp_kullanicisi() is true
    and phase0_private.row_hotel(p_tablo,p_satir,false) is not null;
$$;

-- Separate from untrusted browser telemetry; no guest/row payload is retained.
create table if not exists public.erp_islem_audit (
  id bigint generated always as identity primary key,
  hotel_id public.otel_id not null,
  actor_user_id uuid,
  actor_role text not null check (actor_role in ('authenticated','service_role')),
  server_timestamp timestamptz not null default clock_timestamp(),
  event_type text not null check (event_type in ('INSERT','UPDATE','DELETE')),
  entity_type text not null,
  entity_id text not null,
  entity_key jsonb not null,
  transaction_id text not null,
  check (actor_user_id is not null or actor_role = 'service_role')
);
create index if not exists erp_islem_audit_hotel_time on public.erp_islem_audit(hotel_id,server_timestamp desc);
alter table public.erp_islem_audit enable row level security;
revoke all on public.erp_islem_audit from public,anon,authenticated,service_role;
revoke all on sequence public.erp_islem_audit_id_seq from public,anon,authenticated,service_role;
grant select on public.erp_islem_audit to authenticated;
drop policy if exists phase0_audit_select on public.erp_islem_audit;
create policy phase0_audit_select on public.erp_islem_audit for select to authenticated
  using (public.auth_yetki_var('denetim_izi','goruntule') is true
         and public.auth_otel_erisim(hotel_id::text) is true);
drop policy if exists phase0_audit_boundary on public.erp_islem_audit;
create policy phase0_audit_boundary on public.erp_islem_audit as restrictive for all to authenticated
  using (public.auth_yetki_var('denetim_izi','goruntule') is true
         and public.auth_otel_erisim(hotel_id::text) is true) with check(false);

create or replace function phase0_private.audit_immutable()
returns trigger language plpgsql set search_path = pg_catalog as $$
begin raise exception 'Protected audit history is append-only' using errcode='42501'; end;
$$;
drop trigger if exists phase0_audit_immutable on public.erp_islem_audit;
create trigger phase0_audit_immutable before update or delete or truncate on public.erp_islem_audit
  for each statement execute function phase0_private.audit_immutable();

create or replace function phase0_private.guard_and_audit()
returns trigger language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare v_row jsonb; v_old_hotel text; v_hotel text; v_role text;
  v_keys jsonb; v_entity text; v_ref record; v_child jsonb; v_where text;
begin
  v_role := auth.role();
  if v_role is distinct from 'service_role' then
    if v_role is distinct from 'authenticated' or public.auth_erp_kullanicisi() is not true then
      raise exception 'Active ERP staff required' using errcode='42501';
    end if;
  end if;
  if tg_op <> 'INSERT' then
    v_old_hotel := phase0_private.row_hotel(tg_table_name,to_jsonb(old),true);
    if v_old_hotel is null then raise exception 'Existing hotel scope/link denied' using errcode='42501'; end if;
  end if;
  if tg_op <> 'DELETE' then
    v_row := to_jsonb(new);
    v_hotel := phase0_private.row_hotel(tg_table_name,v_row,true);
    if v_hotel is null then raise exception 'New hotel scope/link denied' using errcode='42501'; end if;
  else v_row := to_jsonb(old); v_hotel := v_old_hotel;
  end if;
  -- A parent hotel change must not invalidate already-linked records either.
  if tg_op='UPDATE' and v_old_hotel is distinct from v_hotel then
    for v_ref in select c.*,cl.relname as child_name from pg_constraint c
      join pg_class cl on cl.oid=c.conrelid join pg_namespace ns on ns.oid=cl.relnamespace
      join phase0_private.scope_tables() s on s.tablo=cl.relname
      where c.confrelid=tg_relid and c.contype='f' and ns.nspname='public' loop
      select string_agg(format('t.%I = ($1->>%L)::%s',a.attname,b.attname,
        format_type(a.atttypid,a.atttypmod)),' and ') into v_where
      from unnest(v_ref.conkey,v_ref.confkey) keys(ak,bk)
      join pg_attribute a on a.attrelid=v_ref.conrelid and a.attnum=keys.ak
      join pg_attribute b on b.attrelid=v_ref.confrelid and b.attnum=keys.bk;
      for v_child in execute format('select to_jsonb(t) from public.%I t where %s for share',
        v_ref.child_name,v_where) using v_row loop
        if phase0_private.row_hotel(v_ref.child_name,v_child,true) is null then
          raise exception 'Parent hotel change would break related scope' using errcode='42501';
        end if;
      end loop;
    end loop;
  end if;
  select jsonb_object_agg(a.attname,v_row->a.attname) into v_keys
    from pg_index i join lateral unnest(i.indkey) k(attnum) on true
    join pg_attribute a on a.attrelid=i.indrelid and a.attnum=k.attnum
    where i.indrelid=tg_relid and i.indisprimary;
  v_keys := coalesce(v_keys,'{}'::jsonb) || jsonb_strip_nulls(jsonb_build_object(
    'id',v_row->'id','siparis_no',v_row->'siparis_no'));
  if v_keys='{}'::jsonb then raise exception 'Audit requires a reviewed entity key'; end if;
  v_entity := coalesce(v_row->>'id',v_row->>'siparis_no',v_keys::text);
  insert into public.erp_islem_audit(hotel_id,actor_user_id,actor_role,event_type,entity_type,entity_id,entity_key,transaction_id)
  values (v_hotel::public.otel_id,auth.uid(),v_role,tg_op,tg_table_name,
    v_entity,v_keys,pg_current_xact_id()::text);
  -- Preserve a source-hotel event too when an authorized centre user moves a row.
  if tg_op='UPDATE' and v_old_hotel is distinct from v_hotel then
    insert into public.erp_islem_audit(hotel_id,actor_user_id,actor_role,event_type,entity_type,entity_id,entity_key,transaction_id)
    values(v_old_hotel::public.otel_id,auth.uid(),v_role,tg_op,tg_table_name,
      v_entity,v_keys,pg_current_xact_id()::text);
  end if;
  if tg_op='DELETE' then return old; end if;
  return null;
end;
$$;

-- Known permissive leftovers only. Unknown policies are a review gate, not
-- candidates for a broad DROP/rebuild which could change module permissions.
do $$
declare v record; v_rel regclass; v_bad text;
begin
  for v in select * from phase0_private.scope_tables() loop
    v_rel := to_regclass('public.' || v.tablo);
    if v_rel is null then raise exception 'Missing prerequisite table: %',v.tablo; end if;
    if not exists (select 1 from pg_attribute where attrelid=v_rel
      and attname=coalesce(v.parent_key,'otel_id') and not attisdropped) then
      raise exception 'Unreviewed table shape: %',v.tablo;
    end if;
    if not exists (select 1 from pg_index where indrelid=v_rel and indisprimary) then
      raise exception 'A reviewed primary key is required for audit: %',v.tablo;
    end if;
    -- Dropping a sole legacy policy must not silently disable an ERP screen.
    if exists (select 1 from pg_policy where polrelid=v_rel
      and polname in ('mk_hepsi','mku_hepsi','tt_hepsi','tk_hepsi','tf_hepsi','fk_write','yk_write'))
      and not exists (select 1 from pg_policy where polrelid=v_rel and polpermissive
        and polname not in ('mk_hepsi','mku_hepsi','tt_hepsi','tk_hepsi','tf_hepsi','fk_write','yk_write')) then
      raise exception 'Install reviewed replacement policies first: %',v.tablo;
    end if;
    for v_bad in select polname from pg_policy where polrelid=v_rel
      and polname in ('mk_hepsi','mku_hepsi','tt_hepsi','tk_hepsi','tf_hepsi','fk_write','yk_write') loop
      execute format('drop policy %I on %s',v_bad,v_rel);
    end loop;
    if exists (select 1 from pg_policy where polrelid=v_rel and polpermissive
      and coalesce(pg_get_expr(polqual,polrelid),'') || ' ' ||
          coalesce(pg_get_expr(polwithcheck,polrelid),'') not like '%auth_yetki_var%') then
      raise exception 'Unreviewed permissive policy on %; inspect preflight',v.tablo;
    end if;
    execute format('alter table %s enable row level security',v_rel);
    execute format('revoke all on %s from public,anon',v_rel);
    execute format('revoke truncate,trigger,references on %s from authenticated',v_rel);
    execute format('drop policy if exists phase0_scope on %s',v_rel);
    execute format('create policy phase0_scope on %s as restrictive for all to authenticated
      using (public.phase0_otel_kapsami(%L,to_jsonb(%I)) is true)
      with check (public.phase0_otel_kapsami(%L,to_jsonb(%I)) is true)',v_rel,v.tablo,v.tablo,v.tablo,v.tablo);
    execute format('drop trigger if exists phase0_guard_audit on %s',v_rel);
    execute format('create trigger phase0_guard_audit after insert or update on %s
      for each row execute function phase0_private.guard_and_audit()',v_rel);
    execute format('drop trigger if exists phase0_guard_delete on %s',v_rel);
    execute format('create trigger phase0_guard_delete before delete on %s
      for each row execute function phase0_private.guard_and_audit()',v_rel);
  end loop;
end;
$$;

-- User administration remains permission-gated; only explicit centre users can
-- administer unassigned/group accounts. No own-row write exception is introduced.
drop policy if exists allow_select on public.kullanicilar;
drop policy if exists yetki_select on public.kullanicilar;
create policy yetki_select on public.kullanicilar for select to authenticated
  using (public.auth_yetki_var('kullanici_yonetimi','goruntule') is true);
do $$ begin
  if exists (select 1 from pg_policy where polrelid='public.kullanicilar'::regclass and polpermissive
    and coalesce(pg_get_expr(polqual,polrelid),'') || ' ' ||
        coalesce(pg_get_expr(polwithcheck,polrelid),'') not like '%auth_yetki_var%') then
    raise exception 'Unreviewed permissive staff administration policy';
  end if;
end $$;
drop policy if exists phase0_users_scope on public.kullanicilar;
create policy phase0_users_scope on public.kullanicilar as restrictive for all to authenticated
  using (public.auth_erp_kullanicisi() is true and
    (public.auth_tum_oteller() is true or public.auth_otel_erisim(otel_id::text) is true))
  with check (public.auth_erp_kullanicisi() is true and
    (public.auth_tum_oteller() is true or
      (public.auth_otel_erisim(otel_id::text) is true and tum_oteller is false)));
revoke all on public.kullanicilar from public,anon;
revoke delete,truncate,trigger,references on public.kullanicilar from authenticated;
alter table public.kullanicilar enable row level security;

-- Keep the existing sanitized directory shape, but stop owner-view bypass for
-- inactive staff and other hotels. Never expose PIN/password columns.
do $$
declare v_columns text;
begin
  if to_regclass('public.kullanicilar_genel') is null then
    raise exception 'Missing sanitized staff directory';
  end if;
  if exists (select 1 from pg_attribute where attrelid='public.kullanicilar_genel'::regclass
    and attnum>0 and not attisdropped and attname not in
      ('id','auth_user_id','ad','rol','departman','otel_id','aktif','olusturma_tarihi','rol_id','gizli','depo_id','eposta')) then
    raise exception 'Unreviewed staff directory columns';
  end if;
  select string_agg(format('k.%I',attname),',' order by attnum) into v_columns
    from pg_attribute where attrelid='public.kullanicilar_genel'::regclass and attnum>0 and not attisdropped;
  execute 'create or replace view public.kullanicilar_genel as select ' || v_columns ||
    ' from public.kullanicilar k where public.auth_erp_kullanicisi() is true and
      (public.auth_tum_oteller() is true or public.auth_otel_erisim(k.otel_id::text) is true or k.auth_user_id=auth.uid())';
end;
$$;
revoke all on public.kullanicilar_genel from public,anon;
grant select on public.kullanicilar_genel to authenticated;

-- Existing browser telemetry is NOT proof of a business operation. Preserve
-- inserts, but make history read-only for clients; unscoped history is centre-only.
revoke update,delete,truncate,trigger on public.audit_log from public,anon,authenticated;
drop policy if exists phase0_legacy_audit_read on public.audit_log;
create policy phase0_legacy_audit_read on public.audit_log as restrictive for select to authenticated
  using (public.auth_tum_oteller() is true and public.auth_yetki_var('denetim_izi','goruntule') is true);
drop policy if exists phase0_legacy_audit_insert on public.audit_log;
create policy phase0_legacy_audit_insert on public.audit_log as restrictive for insert to authenticated
  with check (public.auth_erp_kullanicisi() is true);

create or replace function phase0_private.rpc_yetki(p_rpc text)
returns void language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare v_allowed boolean := false;
begin
  -- Only this existing QR bridge has a legitimate non-personnel entry point.
  if p_rpc='bar_siparis_olustur' and auth.role()='service_role' then return; end if;
  if auth.role() is distinct from 'authenticated' or public.auth_erp_kullanicisi() is not true then
    raise exception 'Active ERP staff required' using errcode='42501';
  end if;
  v_allowed := case
    when p_rpc='fatura_kaydet' then public.auth_yetki_var('fatura_giris','kayit')
      or public.auth_yetki_var('fiyat_kontrol','kayit') or public.auth_yetki_var('siparis_olustur','kayit')
    when p_rpc='mal_kabul_kaydet' then public.auth_yetki_var('mal_kabul_form','kayit')
    when p_rpc in ('teklif_talebi_olustur','siparis_yeniden_yonlendir','talep_siparise_donustur')
      then public.auth_yetki_var('siparis_olustur','kayit')
    -- The existing stage-specific decision check remains inside this RPC.
    when p_rpc='talep_karar_ver' then public.auth_yetki_var('ic_talep','goruntule')
    when p_rpc in ('bar_siparis_olustur','bar_siparis_iptal','bar_siparis_teslim_et','bar_siparis_durum_guncelle')
      then public.auth_yetki_var('bar_siparis_yonetimi','kayit') else false end;
  if v_allowed is not true then raise exception 'Module permission denied' using errcode='42501'; end if;
end;
$$;

-- Preserve effective business bodies, including later fixes/counters. Only
-- structurally matched PL/pgSQL entry/NULL guards are changed, never old bodies.
do $$
declare v_sig text; v_oid oid; v record; v_src text; v_def text; v_match text[];
  v_start integer; v_prefix text; v_block text; v_guard text;
begin
  foreach v_sig in array array[
    'public.fatura_kaydet(uuid,jsonb,jsonb)','public.mal_kabul_kaydet(jsonb,jsonb)',
    'public.teklif_talebi_olustur(text,text,jsonb)','public.siparis_yeniden_yonlendir(text,text)',
    'public.talep_karar_ver(uuid,text,text,numeric)','public.talep_siparise_donustur(uuid)',
    'public.bar_siparis_olustur(text,text,text,text,jsonb)','public.bar_siparis_iptal(uuid)',
    'public.bar_siparis_teslim_et(uuid)','public.bar_siparis_durum_guncelle(uuid,public.bar_durum)'
  ] loop
    v_oid := to_regprocedure(v_sig);
    if v_oid is null then raise exception 'Missing reviewed RPC: %',v_sig; end if;
    select p.*,l.lanname into v from pg_proc p join pg_language l on l.oid=p.prolang where p.oid=v_oid;
    if v.lanname<>'plpgsql' or not v.prosecdef or position('auth_otel_erisim' in v.prosrc)=0 then
      raise exception 'Unsupported RPC definition: %',v_sig;
    end if;
    if not exists(select 1 from unnest(v.proconfig) setting
      where setting in ('search_path=public','search_path=pg_catalog, public, pg_temp')) then
      raise exception 'RPC search_path requires explicit dependency review: %',v_sig;
    end if;
    v_src := regexp_replace(v.prosrc,
      '(if[[:space:]]+)not[[:space:]]+((public\.)?auth_otel_erisim\([^;]*?\))[[:space:]]+then',
      '\1(\2) is not true then','gi');
    v_match := regexp_match(v_src,E'(^|\n)([ \t]*begin[ \t]*\r?\n)','i');
    if v_match is null then raise exception 'Unrecognized RPC entry: %',v_sig; end if;
    v_block := v_match[1] || v_match[2];
    v_start := strpos(v_src,v_block);
    v_prefix := left(v_src,v_start-1);
    if position('/*' in v_prefix)>0 or position('''' in v_prefix)>0 or position('$' in v_prefix)>0 then
      raise exception 'RPC declaration requires explicit review: %',v_sig;
    end if;
    v_guard := format(E'  perform phase0_private.rpc_yetki(%L);\n',v.proname);
    if substring(v_src from v_start+length(v_block) for length(v_guard)) <> v_guard then
      v_src := overlay(v_src placing v_block || v_guard
        from v_start for length(v_block));
    end if;
    v_def := pg_get_functiondef(v_oid);
    execute replace(v_def,v.prosrc,v_src);
    execute format('alter function %s set search_path=pg_catalog,public,pg_temp',v_oid::regprocedure);
    execute format('revoke all on function %s from public,anon',v_oid::regprocedure);
    execute format('grant execute on function %s to authenticated',v_oid::regprocedure);
  end loop;
end;
$$;
grant execute on function public.bar_siparis_olustur(text,text,text,text,jsonb) to service_role;
revoke all on function public.bar_kullanilabilir_stok(text,text) from public,anon,authenticated;
revoke execute on function public.stok_ekle(text,text,text,numeric) from public,anon;
revoke execute on function public.stok_transfer(text,text,text,text,numeric) from public,anon;
-- Preserve the existing server-only approval paths.
revoke update on public.satin_alma_talepleri from public,anon,authenticated;
revoke insert,update,delete on public.talep_onay_gecmisi from public,anon,authenticated;

do $$
declare v_sig text;
begin
  foreach v_sig in array array['public.auth_kullanici_rol_id()','public.auth_kullanici_id()',
    'public.auth_erp_kullanicisi()','public.auth_otel_id()','public.auth_tum_oteller()',
    'public.auth_otel_erisim(text)','public.auth_yetki_var(text,text)','public.phase0_otel_kapsami(text,jsonb)'] loop
    execute 'revoke all on function ' || v_sig || ' from public,anon';
    execute 'grant execute on function ' || v_sig || ' to authenticated';
  end loop;
end;
$$;
revoke all on all functions in schema phase0_private from public,anon,authenticated,service_role;
alter default privileges in schema phase0_private revoke execute on functions from public;
-- Check effective privileges, including inherited and column-level grants.
-- Do not silently rewrite role memberships or unreviewed column ACLs.
do $$
declare v record;
begin
  for v in select to_regclass('public.'||tablo) as rel from phase0_private.scope_tables()
    union all select 'public.kullanicilar'::regclass
    union all select 'public.erp_islem_audit'::regclass loop
    if has_table_privilege('anon',v.rel,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE')
       or has_any_column_privilege('anon',v.rel,'SELECT,INSERT,UPDATE') then
      raise exception 'Unexpected inherited/column anon grant on %',v.rel;
    end if;
  end loop;
  if has_any_column_privilege('authenticated','public.satin_alma_talepleri','UPDATE')
     or has_any_column_privilege('authenticated','public.talep_onay_gecmisi','INSERT,UPDATE')
     or has_any_column_privilege('authenticated','public.erp_islem_audit','INSERT,UPDATE') then
    raise exception 'Unexpected inherited/column grant bypasses a protected write path';
  end if;
  for v in select p.oid,p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname in ('fatura_kaydet','mal_kabul_kaydet','teklif_talebi_olustur',
      'siparis_yeniden_yonlendir','talep_karar_ver','talep_siparise_donustur','bar_siparis_olustur',
      'bar_siparis_iptal','bar_siparis_teslim_et','bar_siparis_durum_guncelle') loop
    if has_function_privilege('anon',v.oid,'EXECUTE') or not exists (
      select 1 from pg_proc where oid=v.oid and position('phase0_private.rpc_yetki' in prosrc)>0) then
      raise exception 'Unreviewed overload or inherited RPC privilege: %',v.oid::regprocedure;
    end if;
  end loop;
end;
$$;
commit;
notify pgrst,'reload schema';

-- ROLLBACK: a failed migration rolls itself back. For post-commit recovery,
-- stop writes and restore captured definitions/policies/ACLs after review.
-- Retain erp_islem_audit data. Never restore blanket PUBLIC/anon grants or
-- USING(true) policies on an online system. This file does NOT auto-deploy.
