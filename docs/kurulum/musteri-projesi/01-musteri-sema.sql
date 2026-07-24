-- Bar müşteri projesi (İZOLE) — şema + RLS. Ana ERP projesinden AYRI bir Supabase
-- projesinde çalıştırılır. Bu projede SADECE bu 3 tablo vardır.
begin;

-- Menü önizleme (ana projeden manuel/yayınla ile doldurulur, müşteri okur)
create table public.menu_urunler (
  id uuid primary key,          -- ana projedeki menu_urunler.id ile AYNI (eşleştirme)
  ad text not null,
  kategori text,
  fiyat numeric(12,2) default 0,
  ucretli boolean not null default false,
  aktif boolean not null default true
);

-- Masa token haritası — anon ERİŞEMEZ, yalnız Edge Function (service_role) okur
create table public.masa_tokenlari (
  token text primary key,       -- opak, tahmin edilemez (örn. gen_random_uuid()::text)
  otel_id text not null,        -- '810' | '811'
  depo_id text not null,        -- bar/restoran depo kodu
  masa_adi text not null,
  aktif boolean not null default true
);

-- Sipariş arşivi — yalnız Edge Function yazar (izlenebilirlik/yeniden deneme için)
create table public.siparis_arsiv (
  id uuid primary key default gen_random_uuid(),
  token text,
  oda_no text,
  kalemler jsonb not null,
  ana_siparis_id uuid,          -- ana projeden dönen id (başarılıysa)
  sonuc text,                   -- 'basarili' | 'hata'
  hata_mesaji text,
  olusturma_zamani timestamptz default now()
);

alter table public.menu_urunler enable row level security;
alter table public.masa_tokenlari enable row level security;
alter table public.siparis_arsiv enable row level security;

-- menu_urunler: anon yalnız aktif ürünleri OKUR
create policy menu_anon_select on public.menu_urunler for select
  to anon using (aktif = true);

-- masa_tokenlari: anon'a HİÇBİR policy yok → varsayılan deny (Edge Function service_role
-- RLS'i bypass eder, o okur). Bilinçli olarak boş bırakıldı.

-- siparis_arsiv: anon'a policy yok → deny. Edge Function service_role yazar.

commit;

-- ============ ÖRNEK VERİ (v1 manuel) — controller gerçek menüyle günceller ============
-- insert into public.masa_tokenlari (token, otel_id, depo_id, masa_adi)
-- values ('demo-token-abc123', '810', '100', 'Havuz Bar Masa 1');
-- insert into public.menu_urunler (id, ad, kategori, fiyat, ucretli, aktif)
-- values ('<ana-projedeki-menu_urun-id>', 'Örnek Kokteyl', 'icecek', 120, true, true);
