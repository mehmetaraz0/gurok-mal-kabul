-- 2026-08-02 — [3] FAZ 4: düz-metin `pin` sütununu kaldır (geri dönüşsüz)
--
-- Güvenlik zaten [3] ile kapandı (login pin_hash/bcrypt üzerinden). Bu faz, artık gereksiz
-- olan düz-metin `pin` sütununu siler. PIN yönetimi write-only olur: pin_ayarla RPC ile
-- düz PIN sunucuda hash'lenip pin_hash'e yazılır, sütunda saklanmaz.
--
-- SIRA ÖNEMLİ — giriş HİÇ bozulmasın:
--   ADIM A (risksiz, ŞİMDİ): pin_ayarla RPC. Sütun hâlâ dururken login etkilenmez.
--   >>> kullanici-yonetimi.html write-only sürümü DEPLOY + TEST edilir (kullanıcı ekle/düzenle
--       + PIN ata + o PIN'le giriş). Ancak bundan SONRA ADIM B.
--   ADIM B (geri dönüşsüz): trigger + pin sütunu drop.

-- ============================================================
-- ADIM A — pin_ayarla RPC (ŞİMDİ çalıştır, risksiz)
-- ============================================================
create or replace function public.pin_ayarla(p_kullanici_id uuid, p_pin text)
returns void
language plpgsql
security definer
set search_path = public, extensions   -- pgcrypto (crypt/gen_salt) extensions şemasında
as $$
begin
  if not public.auth_yetki_var('kullanici_yonetimi','kayit') then
    raise exception 'Yetkisiz: PIN ayarlama yetkiniz yok';
  end if;
  if p_pin is null or p_pin !~ '^\d{6}$' then
    raise exception 'PIN 6 haneli sayısal olmalı';
  end if;
  update public.kullanicilar
    set pin_hash = crypt(p_pin, gen_salt('bf'))
    where id = p_kullanici_id;
  if not found then
    raise exception 'Kullanıcı bulunamadı';
  end if;
end;
$$;

revoke all on function public.pin_ayarla(uuid, text) from public, anon;
grant execute on function public.pin_ayarla(uuid, text) to authenticated;
notify pgrst, 'reload schema';

-- TEST A (SQL Editor'de auth yok → yetki hatası beklenir, NORMAL):
-- select public.pin_ayarla('00000000-0000-0000-0000-000000000000', '123456');
--   -> "Yetkisiz..." hatası = RPC var ve yetki kapısı çalışıyor. Gerçek test UYGULAMADA.


-- ============================================================
-- ADIM B — pin sütununu düşür (client TEST EDİLDİKTEN SONRA, geri dönüşsüz)
-- ============================================================
-- >>> Bu bloğu, kullanici-yonetimi.html write-only sürümü canlıda TEST EDİLENE KADAR
--     ÇALIŞTIRMA. Test tamamsa aşağıyı çalıştır:
--
-- begin;
--   -- 1) pin'e yazınca pin_hash senkronlayan trigger artık gereksiz (pin gidiyor)
--   drop trigger if exists tg_pin_hash_senkronize on public.kullanicilar;
--   drop function if exists public.pin_hash_senkronize_tetikleyici();
--   -- 2) eski düz-metin PIN arama fonksiyonu (cutover'da client'tan zaten kaldırılmıştı)
--   drop function if exists public.pin_ile_kullanici_ara(text);
--   -- 3) düz-metin sütunu düşür (geri dönüşsüz)
--   alter table public.kullanicilar drop column if exists pin;
-- commit;
-- notify pgrst, 'reload schema';
--
-- TEST B (uygulamada): (a) mevcut kullanıcı PIN'iyle giriş → çalışmalı (pin_hash),
--   (b) Kullanıcı Yönetimi'nden bir kullanıcının PIN'ini değiştir → yeni PIN'le giriş,
--   (c) yeni kullanıcı oluştur + PIN ata → o PIN'le giriş.
