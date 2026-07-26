-- 2026-07-26: Ürün kalem kodu sınıflandırma (Ana Grup + Alt Grup)
-- Supabase SQL Editor'de tek seferlik çalıştırılır. Ürün kodunun kendisini
-- (public.urunler.kod) DEĞİŞTİRMEZ — sadece ek bir eşleme/katalog ekler,
-- urun_birim_donusum ile aynı desen.

begin;

create table public.urun_ana_gruplari (
  id uuid primary key default gen_random_uuid(),
  ana_grup_kod text not null unique,      -- mevcut public.urunler.grup değerleriyle eşleşir, örn. 'YIY01'
  ana_grup_adi text not null default '',  -- kullanıcı elle doldurur, boş başlar
  sira int not null default 0,
  silindi boolean not null default false,
  guncelleme_tarihi timestamptz not null default now()
);

create table public.urun_alt_gruplari (
  id uuid primary key default gen_random_uuid(),
  ana_grup_kod text not null references public.urun_ana_gruplari(ana_grup_kod),
  alt_grup_kod text not null unique,      -- örn. 'YIY0401'
  alt_grup_adi text not null,             -- örn. 'Kartonlu'
  sira int not null default 0,
  silindi boolean not null default false,
  guncelleme_tarihi timestamptz not null default now()
);

create table public.urun_siniflandirma (
  id uuid primary key default gen_random_uuid(),
  urun_kodu text not null unique references public.urunler(kod),
  alt_grup_kod text not null references public.urun_alt_gruplari(alt_grup_kod),
  silindi boolean not null default false,
  guncelleme_tarihi timestamptz not null default now()
);

alter table public.urun_ana_gruplari enable row level security;
alter table public.urun_alt_gruplari enable row level security;
alter table public.urun_siniflandirma enable row level security;

create policy urun_ana_gruplari_select on public.urun_ana_gruplari
  for select using (public.auth_yetki_var('urun_yonetimi','goruntule') and silindi = false);
create policy urun_ana_gruplari_yaz on public.urun_ana_gruplari
  for all using (public.auth_yetki_var('urun_yonetimi','kayit'))
  with check (public.auth_yetki_var('urun_yonetimi','kayit'));

create policy urun_alt_gruplari_select on public.urun_alt_gruplari
  for select using (public.auth_yetki_var('urun_yonetimi','goruntule') and silindi = false);
create policy urun_alt_gruplari_yaz on public.urun_alt_gruplari
  for all using (public.auth_yetki_var('urun_yonetimi','kayit'))
  with check (public.auth_yetki_var('urun_yonetimi','kayit'));

create policy urun_siniflandirma_select on public.urun_siniflandirma
  for select using (public.auth_yetki_var('urun_yonetimi','goruntule') and silindi = false);
create policy urun_siniflandirma_yaz on public.urun_siniflandirma
  for all using (public.auth_yetki_var('urun_yonetimi','kayit'))
  with check (public.auth_yetki_var('urun_yonetimi','kayit'));

commit;
