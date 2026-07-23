-- F&B Bar modülü — ana proje şeması (2026-07-22)
-- Çalıştırma: Supabase Dashboard → SQL Editor → tamamını yapıştır → Run.
begin;

-- Enum'lar
create type public.bar_durum as enum ('yeni','hazirlaniyor','hazir','teslim_edildi','iptal');
create type public.rezervasyon_durum as enum ('aktif','serbest','kullanildi');

-- Menü ürünleri (personel yönetir, müşteri projesine tek yönlü kopyalanır)
create table public.menu_urunler (
  id uuid primary key default gen_random_uuid(),
  ad text not null,
  kategori text,
  otel_id public.otel_id not null,
  fiyat numeric(12,2) default 0,
  aktif boolean not null default true,
  ucretli boolean not null default false,
  tip text not null default 'direkt' check (tip in ('direkt','receteli')),
  stok_kodu text,               -- yalnız tip='direkt'
  miktar_per_porsiyon numeric(12,3),  -- yalnız tip='direkt'
  silindi boolean not null default false,
  guncelleme_tarihi timestamptz default now()
);

-- Reçete bileşenleri (tip='receteli' ürünler için)
create table public.recete_bilesenleri (
  id uuid primary key default gen_random_uuid(),
  menu_urun_id uuid not null references public.menu_urunler(id),
  stok_kodu text not null,
  miktar_per_porsiyon numeric(12,3) not null,
  birim text
);

-- Bar siparişleri (webhook ile müşteri projesinden beslenir)
create table public.bar_siparisleri (
  id uuid primary key default gen_random_uuid(),
  otel_id public.otel_id not null,
  depo_id text not null,
  masa_token text,
  oda_no text,                  -- nullable, yalnız ücretli kalem varsa dolu
  durum public.bar_durum not null default 'yeni',
  personel_id uuid,             -- kim hazırladı/teslim etti
  olusturma_zamani timestamptz not null default now()
);

-- Sipariş kalemleri
create table public.bar_siparis_kalemleri (
  id uuid primary key default gen_random_uuid(),
  siparis_id uuid not null references public.bar_siparisleri(id),
  menu_urun_id uuid not null references public.menu_urunler(id),
  adet numeric(12,3) not null check (adet > 0),
  rezerve_edildi boolean not null default false,
  teslim_edildi boolean not null default false
);

-- Stok rezervasyonları (aktif rezervasyonlar kullanılabilir stoktan düşülür)
create table public.stok_rezervasyonlari (
  id uuid primary key default gen_random_uuid(),
  stok_kodu text not null,
  otel_id public.otel_id not null,
  depo_id text not null,
  miktar numeric(12,3) not null check (miktar > 0),
  siparis_kalem_id uuid not null references public.bar_siparis_kalemleri(id),
  durum public.rezervasyon_durum not null default 'aktif',
  olusturma_zamani timestamptz not null default now()
);

-- Müsaitlik sorgusunun hızlı olması için: aktif rezervasyonlar üzerinde indeks
create index stok_rezervasyonlari_aktif_idx
  on public.stok_rezervasyonlari (stok_kodu, depo_id, durum)
  where durum = 'aktif';

-- ============ RLS ============
alter table public.menu_urunler enable row level security;
alter table public.recete_bilesenleri enable row level security;
alter table public.bar_siparisleri enable row level security;
alter table public.bar_siparis_kalemleri enable row level security;
alter table public.stok_rezervasyonlari enable row level security;

create policy menu_select on public.menu_urunler for select
  using (public.auth_yetki_var('bar_siparis_yonetimi','goruntule') and silindi = false);
create policy menu_write on public.menu_urunler for all
  using (public.auth_yetki_var('bar_siparis_yonetimi','kayit'))
  with check (public.auth_yetki_var('bar_siparis_yonetimi','kayit'));

create policy recete_select on public.recete_bilesenleri for select
  using (public.auth_yetki_var('bar_siparis_yonetimi','goruntule'));
create policy recete_write on public.recete_bilesenleri for all
  using (public.auth_yetki_var('bar_siparis_yonetimi','kayit'))
  with check (public.auth_yetki_var('bar_siparis_yonetimi','kayit'));

create policy siparis_select on public.bar_siparisleri for select
  using (public.auth_yetki_var('bar_siparis_yonetimi','goruntule'));
create policy siparis_write on public.bar_siparisleri for all
  using (public.auth_yetki_var('bar_siparis_yonetimi','kayit'))
  with check (public.auth_yetki_var('bar_siparis_yonetimi','kayit'));

create policy kalem_select on public.bar_siparis_kalemleri for select
  using (public.auth_yetki_var('bar_siparis_yonetimi','goruntule'));
create policy kalem_write on public.bar_siparis_kalemleri for all
  using (public.auth_yetki_var('bar_siparis_yonetimi','kayit'))
  with check (public.auth_yetki_var('bar_siparis_yonetimi','kayit'));

create policy rez_select on public.stok_rezervasyonlari for select
  using (public.auth_yetki_var('bar_siparis_yonetimi','goruntule'));
create policy rez_write on public.stok_rezervasyonlari for all
  using (public.auth_yetki_var('bar_siparis_yonetimi','kayit'))
  with check (public.auth_yetki_var('bar_siparis_yonetimi','kayit'));

-- ============ Modül kaydı ============
insert into public.moduller (kod, ad, sira, kategori, aktif)
values ('bar_siparis_yonetimi', 'Bar / Restoran Sipariş Yönetimi', 43, 'fb', true);

-- Yetki dağılımı: gunluk_tuketim modülüyle aynı roller/seviyeler
insert into public.yetki_matrisi (rol_id, modul_id, yetki)
select rol_id, (select id from public.moduller where kod='bar_siparis_yonetimi'), yetki
from public.yetki_matrisi
where modul_id = (select id from public.moduller where kod='gunluk_tuketim');

commit;
