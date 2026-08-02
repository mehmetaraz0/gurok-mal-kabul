-- 2026-07-22 — kullanicilar tablosu PIN sızıntısı düzeltmesi
--
-- Sorun: `allow_select ON kullanicilar FOR SELECT USING (true)` politikası,
-- anon key ile (giriş yapmadan) kullanicilar.pin (düz metin) dahil TÜM
-- sütunların herkes tarafından okunmasına izin veriyordu. supabaseAuthKoprusu()
-- bu PIN'i Supabase Auth şifresi olarak kullandığından, sızan PIN ile
-- auth.uid() bazlı RLS kontrollerini de aşan gerçek bir Auth JWT'si alınabiliyordu.
--
-- Bu script:
--   1) PIN'i asla dışarı vermeyen bir SECURITY DEFINER arama fonksiyonu ekler
--      (giriş ekranının hem 3+ hane isim önizlemesi hem 6 hane tam eşleşme
--      ihtiyacını karşılar).
--   2) pin/pin_hash HARİÇ tüm sütunları veren bir view ekler (diğer modüllerin
--      "aktif kullanıcı listesi" ihtiyacı için — hiçbiri zaten pin kullanmıyor).
--   3) Ham tablonun SELECT politikasını, tablonun kendi INSERT/UPDATE
--      politikalarıyla (yetki_insert/yetki_update) AYNI desene taşır:
--      sadece kullanici_yonetimi modülüne yetkisi olanlar (yönetim rolü)
--      ham tabloyu (dolayısıyla pin sütununu) okuyabilir.
--
-- Çalıştırma: Supabase Dashboard → SQL Editor → bu dosyanın tamamını yapıştır → Run.
-- Geri alma: dosyanın en altındaki ROLLBACK bloğunu ayrıca çalıştır.

begin;

create or replace function public.pin_ile_kullanici_ara(p_giris text)
returns table (
  id uuid, ad text, rol public.kullanici_rol, rol_id uuid,
  departman text, otel_id public.otel_id, depo_id text,
  eposta text, auth_user_id uuid
)
language sql
security definer
set search_path = public
stable
as $$
  select id, ad, rol, rol_id, departman, otel_id, depo_id, eposta, auth_user_id
  from public.kullanicilar
  where aktif = true
    and pin is not null
    and pin like (p_giris || '%');
$$;

revoke all on function public.pin_ile_kullanici_ara(text) from public;
grant execute on function public.pin_ile_kullanici_ara(text) to anon, authenticated;

create or replace view public.kullanicilar_genel as
select id, auth_user_id, ad, rol, departman, otel_id, aktif,
       olusturma_tarihi, rol_id, gizli, depo_id, eposta
from public.kullanicilar;

grant select on public.kullanicilar_genel to anon, authenticated;

drop policy if exists allow_select on public.kullanicilar;
create policy yetki_select on public.kullanicilar
  for select using (public.auth_yetki_var('kullanici_yonetimi', 'goruntule'));

commit;

-- ============================================================
-- ROLLBACK — bir sorun çıkarsa bu bloğu ayrıca çalıştır:
-- ============================================================
-- begin;
-- drop policy if exists yetki_select on public.kullanicilar;
-- create policy allow_select on public.kullanicilar for select using (true);
-- drop view if exists public.kullanicilar_genel;
-- drop function if exists public.pin_ile_kullanici_ara(text);
-- commit;
