-- 2026-07-27 — pin_ile_kullanici_ara() prefix "oracle" kapatma
--
-- Sorun: pin_ile_kullanici_ara(p_giris) fonksiyonu `pin like (p_giris || '%')`
-- ile PREFIX eşleşmesi yapıyordu ve anon role'e execute yetkisi verilmişti
-- (docs/kurulum/2026-07-22-pin-rls-duzeltme.sql). Anon key public olduğundan
-- (istemci bundle'ında açık), bir saldırgan tarayıcı UI'ını hiç kullanmadan
-- doğrudan REST üzerinden bu RPC'yi art arda çağırarak (3 haneli ~1000
-- kombinasyon, sonra devamla 6 haneye daraltma) sunucu tarafı hiçbir
-- rate-limit'e takılmadan bir kullanıcının tam PIN'ini brute-force
-- edebiliyordu. İstemcideki kilitleme (auth-guard.js: pinKilitliMi/
-- pinBasarisizKaydet) yalnızca localStorage'a yazıyor ve yalnızca
-- checkPin()'in "hatalı PIN" yolunda tetikleniyor -- bu RPC'nin doğrudan
-- çağrılmasını hiç engellemiyor. PIN, supabaseAuthKoprusu() içinde
-- doğrudan Supabase Auth şifresi olarak kullanıldığından, brute-force
-- edilen PIN gerçek bir Auth JWT'sine (tam hesap ele geçirme) dönüşüyordu.
--
-- Bu script: fonksiyonu TAM 6 haneli eşleşmeye çevirir (prefix kaldırılır).
-- Grant'lere dokunulmuyor (anon + authenticated execute yetkisi kalıyor --
-- giriş ekranı hâlâ oturumsuz çalışmalı, yalnızca prefix arama kapatılıyor).
--
-- Çalıştırma: Supabase Dashboard → SQL Editor → bu dosyanın tamamını
-- yapıştır → Run. Sonra aşağıdaki TEST sorgularını çalıştırıp doğrula.
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
    and char_length(p_giris) = 6
    and pin = p_giris;
$$;

commit;

-- ============================================================
-- TEST — Supabase SQL Editor'de tek tek çalıştırıp sonucu doğrula:
-- ============================================================
-- select * from pin_ile_kullanici_ara('123456'); -- gerçek bir kullanıcının TAM PIN'i → 1 satır dönmeli
-- select * from pin_ile_kullanici_ara('123');     -- kısmi giriş (3 hane)  → 0 satır dönmeli
-- select * from pin_ile_kullanici_ara('999999');  -- olmayan PIN           → 0 satır dönmeli

-- ============================================================
-- ROLLBACK — bir sorun çıkarsa bu bloğu ayrıca çalıştır:
-- ============================================================
-- begin;
-- create or replace function public.pin_ile_kullanici_ara(p_giris text)
-- returns table (
--   id uuid, ad text, rol public.kullanici_rol, rol_id uuid,
--   departman text, otel_id public.otel_id, depo_id text,
--   eposta text, auth_user_id uuid
-- )
-- language sql
-- security definer
-- set search_path = public
-- stable
-- as $$
--   select id, ad, rol, rol_id, departman, otel_id, depo_id, eposta, auth_user_id
--   from public.kullanicilar
--   where aktif = true
--     and pin is not null
--     and pin like (p_giris || '%');
-- $$;
-- commit;
