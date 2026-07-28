-- urunler yazma RLS düzeltmesi.
-- urunler'de sadece SELECT politikası vardı (urn_select), INSERT/UPDATE yoktu →
-- RLS açık olduğu için ürün ekleme/fiyat güncelleme sessizce 0 satır etkiliyordu
-- (PATCH 200 döner ama hiçbir şey yazılmaz). Bu, ürün yönetimi yetkisi olanlar için
-- yazmayı açar (mal_kabul_urunleri mku_update deseniyle aynı: auth_yetki_var gate).
-- Supabase SQL Editor'e yapıştır → Run.

grant insert, update on public.urunler to authenticated;

drop policy if exists urn_insert on public.urunler;
create policy urn_insert on public.urunler for insert
  with check (public.auth_yetki_var('urun_yonetimi','kayit'));

drop policy if exists urn_update on public.urunler;
create policy urn_update on public.urunler for update
  using (public.auth_yetki_var('urun_yonetimi','kayit'))
  with check (public.auth_yetki_var('urun_yonetimi','kayit'));

notify pgrst, 'reload schema';
