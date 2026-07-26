-- Ürün sistem fiyatı — urunler tablosuna fiyat kolonları.
-- Supabase SQL Editor'e yapıştır → Run. Geri alınabilir (kolon ekler, veri silmez).
alter table public.urunler add column if not exists sistem_fiyat numeric;
alter table public.urunler add column if not exists sistem_fiyat_tarihi timestamptz;
alter table public.urunler add column if not exists sistem_fiyat_giren text;
notify pgrst, 'reload schema';
