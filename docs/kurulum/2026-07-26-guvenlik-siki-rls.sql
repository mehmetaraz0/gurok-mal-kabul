-- 2026-07-26 — KRİTİK GÜVENLİK SIKILAŞTIRMASI
-- Kapatılan açıklar:
--   1) fatura_kalemleri, yevmiye_kalemleri: RLS KAPALIYDI → herhangi bir giriş yapmış
--      kullanıcı finansal satırları yetkisiz okuyup/yazabiliyordu (parent faturalar/
--      yevmiye_fisleri yetki-kilitli; çocuk tablolar açıktı).
--   2) yetki_matrisi, roller, moduller: RLS KAPALIYDI → kullanıcı kendine yetki
--      verebilir / rol-modül tanımını değiştirebilirdi (yetki yükseltme).
--   3) teklif_talepleri/kalemleri/fiyatlari: anon'a 'grant all' → giriş YAPMAMIŞ biri
--      RFQ verisi yazabiliyordu. anon yazma yetkisi geri alınır (authenticated kalır).
-- Not: auth_yetki_var() SECURITY DEFINER olduğundan izin hesabı bu RLS'lerden etkilenmez.
--      Direkt REST okumaları için SELECT politikaları geniş bırakıldı (app kırılmaz).
-- Çalıştırma: Supabase SQL Editor → tamamını yapıştır → Run. Sonra HEMEN test et
--   (aşağıdaki TEST notu). Sorun olursa en alttaki ROLLBACK bloğunu çalıştır.

begin;

-- ============ 1) FATURA KALEMLERİ (parent faturalar deseniyle) ============
alter table public.fatura_kalemleri enable row level security;
drop policy if exists fk_select on public.fatura_kalemleri;
create policy fk_select on public.fatura_kalemleri for select
  using (public.auth_yetki_var('fatura_giris','goruntule'));
drop policy if exists fk_insert on public.fatura_kalemleri;
create policy fk_insert on public.fatura_kalemleri for insert
  with check (public.auth_yetki_var('fatura_giris','kayit') or public.auth_yetki_var('fiyat_kontrol','kayit') or public.auth_yetki_var('siparis_olustur','kayit'));
drop policy if exists fk_update on public.fatura_kalemleri;
create policy fk_update on public.fatura_kalemleri for update
  using (public.auth_yetki_var('fatura_giris','kayit') or public.auth_yetki_var('fiyat_kontrol','kayit') or public.auth_yetki_var('siparis_olustur','kayit'))
  with check (public.auth_yetki_var('fatura_giris','kayit') or public.auth_yetki_var('fiyat_kontrol','kayit') or public.auth_yetki_var('siparis_olustur','kayit'));
drop policy if exists fk_delete on public.fatura_kalemleri;
create policy fk_delete on public.fatura_kalemleri for delete
  using (public.auth_yetki_var('fatura_giris','kayit') or public.auth_yetki_var('fiyat_kontrol','kayit') or public.auth_yetki_var('siparis_olustur','kayit'));

-- ============ 2) YEVMİYE KALEMLERİ ============
alter table public.yevmiye_kalemleri enable row level security;
drop policy if exists yk_select on public.yevmiye_kalemleri;
create policy yk_select on public.yevmiye_kalemleri for select
  using (public.auth_yetki_var('yevmiye_fis_giris','goruntule'));
drop policy if exists yk_insert on public.yevmiye_kalemleri;
create policy yk_insert on public.yevmiye_kalemleri for insert
  with check (public.auth_yetki_var('yevmiye_fis_giris','kayit'));
drop policy if exists yk_update on public.yevmiye_kalemleri;
create policy yk_update on public.yevmiye_kalemleri for update
  using (public.auth_yetki_var('yevmiye_fis_giris','kayit'))
  with check (public.auth_yetki_var('yevmiye_fis_giris','kayit'));
drop policy if exists yk_delete on public.yevmiye_kalemleri;
create policy yk_delete on public.yevmiye_kalemleri for delete
  using (public.auth_yetki_var('yevmiye_fis_giris','kayit'));

-- ============ 3) YETKİ/ROL/MODÜL — SELECT herkese (izin hesabı için), YAZMA admin ============
alter table public.yetki_matrisi enable row level security;
drop policy if exists ym_select on public.yetki_matrisi;
create policy ym_select on public.yetki_matrisi for select using (auth.uid() is not null);
drop policy if exists ym_write on public.yetki_matrisi;
create policy ym_write on public.yetki_matrisi for all
  using (public.auth_yetki_var('kullanici_yonetimi','kayit') or public.auth_yetki_var('yetki_yonetimi','kayit'))
  with check (public.auth_yetki_var('kullanici_yonetimi','kayit') or public.auth_yetki_var('yetki_yonetimi','kayit'));

alter table public.roller enable row level security;
drop policy if exists rol_select on public.roller;
create policy rol_select on public.roller for select using (auth.uid() is not null);
drop policy if exists rol_write on public.roller;
create policy rol_write on public.roller for all
  using (public.auth_yetki_var('kullanici_yonetimi','kayit') or public.auth_yetki_var('yetki_yonetimi','kayit'))
  with check (public.auth_yetki_var('kullanici_yonetimi','kayit') or public.auth_yetki_var('yetki_yonetimi','kayit'));

alter table public.moduller enable row level security;
drop policy if exists mod_select on public.moduller;
create policy mod_select on public.moduller for select using (auth.uid() is not null);
drop policy if exists mod_write on public.moduller;
create policy mod_write on public.moduller for all
  using (public.auth_yetki_var('kullanici_yonetimi','kayit') or public.auth_yetki_var('yetki_yonetimi','kayit'))
  with check (public.auth_yetki_var('kullanici_yonetimi','kayit') or public.auth_yetki_var('yetki_yonetimi','kayit'));

-- ============ 4) TEKLİF tablolarında anon yazma yetkisini geri al ============
revoke all on public.teklif_talepleri from anon;
revoke all on public.teklif_kalemleri from anon;
revoke all on public.teklif_fiyatlari from anon;

commit;
notify pgrst, 'reload schema';

-- ============================================================
-- TEST (çalıştırdıktan HEMEN sonra):
--   1) Çıkış yap / gir → login çalışıyor mu?
--   2) Bir modül aç → yetkilerin yükleniyor mu (boş/kapalı görünmüyor)?
--   3) Muhasebe → Faturalar → bir fatura gör/düzenle → kalemler geliyor/kaydoluyor mu?
--   4) Yevmiye fişi gör/gir → satırlar çalışıyor mu?
--   5) Yönetim → Yetki Yönetimi → bir yetki değiştir/kaydet → çalışıyor mu?
-- Kırılan olursa → ROLLBACK'i çalıştır ve haber ver.
-- ============================================================
-- ROLLBACK (sorun çıkarsa bu bloğu ayrıca çalıştır):
-- begin;
-- alter table public.fatura_kalemleri disable row level security;
-- alter table public.yevmiye_kalemleri disable row level security;
-- alter table public.yetki_matrisi disable row level security;
-- alter table public.roller disable row level security;
-- alter table public.moduller disable row level security;
-- grant all on public.teklif_talepleri, public.teklif_kalemleri, public.teklif_fiyatlari to anon;
-- commit; notify pgrst, 'reload schema';
