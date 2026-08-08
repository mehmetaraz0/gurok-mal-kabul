-- 2026-08-04 — Kayıtlı filtreler (kullanıcıya özel + yönetici ortak şablon)
-- Gelişmiş filtreleme altyapısı Task 1. Tasarım: docs/superpowers/specs/2026-08-04-gelismis-filtreleme-design.md
-- auth_kullanici_id() = auth.uid() -> kullanicilar.id (auth_otel_id deseniyle). RLS: kendi + paylaşımlı.
-- Çalıştırma: SQL Editor → Run. Rollback: en altta.

begin;

create or replace function public.auth_kullanici_id()
returns text language sql stable security definer set search_path = public as $$
  select id from public.kullanicilar where auth_user_id = auth.uid() limit 1;
$$;
grant execute on function public.auth_kullanici_id() to authenticated;

create table if not exists public.kayitli_filtreler (
  id uuid primary key default gen_random_uuid(),
  kullanici_id text,
  ekran text not null,
  ad text not null,
  filtreler jsonb not null,
  paylasimli boolean not null default false,
  olusturma_tarihi timestamptz not null default now()
);
alter table public.kayitli_filtreler enable row level security;

drop policy if exists kf_select on public.kayitli_filtreler;
create policy kf_select on public.kayitli_filtreler for select to authenticated
  using (kullanici_id = public.auth_kullanici_id() or paylasimli = true);

drop policy if exists kf_insert on public.kayitli_filtreler;
create policy kf_insert on public.kayitli_filtreler for insert to authenticated
  with check (
    kullanici_id = public.auth_kullanici_id()
    and (paylasimli = false or public.auth_yetki_var('kullanici_yonetimi','kayit'))
  );

drop policy if exists kf_update on public.kayitli_filtreler;
create policy kf_update on public.kayitli_filtreler for update to authenticated
  using (kullanici_id = public.auth_kullanici_id())
  with check (kullanici_id = public.auth_kullanici_id());

drop policy if exists kf_delete on public.kayitli_filtreler;
create policy kf_delete on public.kayitli_filtreler for delete to authenticated
  using (kullanici_id = public.auth_kullanici_id());

commit;
notify pgrst, 'reload schema';

-- ROLLBACK:
-- begin;
-- drop table if exists public.kayitli_filtreler;
-- drop function if exists public.auth_kullanici_id();
-- commit;
-- notify pgrst, 'reload schema';
