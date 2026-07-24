-- Bar menü yayınlama — müşteri projesi şema eklemeleri. MÜŞTERİ projesinde çalıştırılır.
begin;

-- menü ürününe otel bilgisi
alter table public.menu_urunler add column if not exists otel_id text;

-- Masa→otel çözümü: yalnız BİLİNEN token için otel_id döner (token listesi sızdırmaz).
create or replace function public.masa_oteli_getir(p_token text)
returns text language sql stable security definer set search_path = public
as $$ select otel_id from public.masa_tokenlari where token = p_token and aktif = true $$;
grant execute on function public.masa_oteli_getir(text) to anon;

-- Atomik menü değiştirme (yalnız Edge Function service_role çağırır; anon'a AÇILMAZ)
create or replace function public.menu_yenile(p_menu jsonb)
returns integer language plpgsql security definer set search_path = public
as $$
declare v_sayi integer;
begin
  delete from public.menu_urunler;
  insert into public.menu_urunler (id, ad, kategori, fiyat, ucretli, aktif, otel_id)
  select (x->>'id')::uuid, x->>'ad', x->>'kategori', (x->>'fiyat')::numeric,
         (x->>'ucretli')::boolean, (x->>'aktif')::boolean, x->>'otel_id'
  from jsonb_array_elements(p_menu) x;
  get diagnostics v_sayi = row_count;
  return v_sayi;
end $$;
-- menu_yenile için anon GRANT YOK — varsayılan olarak public'e kapalı bırakılır.

commit;
