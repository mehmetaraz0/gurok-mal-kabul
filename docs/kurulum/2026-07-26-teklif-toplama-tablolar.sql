-- Teklif Toplama (RFQ) — eski 4 tablolu RFQ'yu düşür, 3 yeni tabloyu kur.
-- Supabase SQL Editor'e tamamını yapıştır → Run. Geri alınamaz (eski RFQ verisi silinir).
begin;

-- 1) Eski RFQ tablolarını düşür (FK sırasına göre: önce çocuklar)
drop table if exists public.tedarikci_teklif_kalemleri cascade;
drop table if exists public.tedarikci_teklifler cascade;
drop table if exists public.teklif_talep_kalemleri cascade;
drop table if exists public.teklif_talepleri cascade;

-- 2) Yeni tablolar
create table public.teklif_talepleri (
  id uuid primary key default gen_random_uuid(),
  olusturma_tarihi timestamptz not null default now(),
  olusturan text not null,
  otel_id text,
  durum text not null default 'acik',   -- acik | tamamlandi
  not_alani text
);

create table public.teklif_kalemleri (
  id uuid primary key default gen_random_uuid(),
  teklif_talebi_id uuid not null references public.teklif_talepleri(id) on delete cascade,
  urun_kodu text,
  urun_adi text not null,
  miktar numeric not null,
  birim text not null,
  kaynak_ic_talep_kalemi_id uuid,  -- satin_alma_talep_kalemleri.id (FK değil), nullable
  secilen_teklif_id uuid           -- teklif_fiyatlari.id (kullanıcı seçimi), nullable
);

create table public.teklif_fiyatlari (
  id uuid primary key default gen_random_uuid(),
  teklif_kalemi_id uuid not null references public.teklif_kalemleri(id) on delete cascade,
  firma_id integer,                -- FIRMA_DB[].id (FK değil)
  firma_ad text not null,
  birim_fiyat numeric not null,
  giris_tarihi timestamptz not null default now(),
  giren_kullanici text not null,
  not_alani text
);

-- 3) RLS — projenin geri kalanıyla aynı desen: RLS açık, authenticated'a tam izin
alter table public.teklif_talepleri enable row level security;
alter table public.teklif_kalemleri enable row level security;
alter table public.teklif_fiyatlari enable row level security;
create policy tt_hepsi on public.teklif_talepleri for all using(true) with check(true);
create policy tk_hepsi on public.teklif_kalemleri for all using(true) with check(true);
create policy tf_hepsi on public.teklif_fiyatlari for all using(true) with check(true);
grant all on public.teklif_talepleri, public.teklif_kalemleri, public.teklif_fiyatlari to anon, authenticated;

commit;
notify pgrst, 'reload schema';
