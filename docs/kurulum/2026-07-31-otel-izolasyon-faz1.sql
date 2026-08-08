-- 2026-07-31 — Madde D / FAZ 1: altyapı (RİSKSİZ — hiçbir politika değişmez)
--
-- Bu script yalnızca HAZIRLIK yapar: tum_oteller kolonu + 3 SECURITY DEFINER
-- yardımcı fonksiyon + merkez kullanıcıları işaretleme. HİÇBİR RLS politikasına
-- dokunmaz → uygulama davranışı BİREBİR aynı kalır. Otel izolasyonu ancak Faz 2'de
-- (politikalara auth_otel_erisim eklendiğinde) devreye girer.
--
-- otel_id tipleri karışık (17 tablo enum public.otel_id, 7 tablo text) — bu yüzden
-- yardımcılar TEXT tabanlı; Faz 2 politikalarında `auth_otel_erisim(otel_id::text)`.
--
-- Merkez roller: yonetici + muhasebe_muduru (kullanici_rol enum'unda "depo yöneticisi"
-- yok; gerekirse belirli kişi tek tek tum_oteller=true yapılır).
--
-- Çalıştırma: SQL Editor → tamamını yapıştır → Run. Sonra TEST bölümü.
-- Rollback: en altta.

begin;

-- 1) Kolon (idempotent)
alter table public.kullanicilar
  add column if not exists tum_oteller boolean not null default false;

-- 2) Yardımcı fonksiyonlar (SECURITY DEFINER — auth_yetki_var deseniyle aynı, text tabanlı)
create or replace function public.auth_otel_id()
returns text language sql security definer stable
set search_path = public as $$
  select otel_id::text from public.kullanicilar
  where auth_user_id = auth.uid() limit 1;
$$;

create or replace function public.auth_tum_oteller()
returns boolean language sql security definer stable
set search_path = public as $$
  select coalesce((select tum_oteller from public.kullanicilar
    where auth_user_id = auth.uid() limit 1), false);
$$;

create or replace function public.auth_otel_erisim(p_otel text)
returns boolean language sql security definer stable
set search_path = public as $$
  select public.auth_tum_oteller() or p_otel = public.auth_otel_id();
$$;

grant execute on function public.auth_otel_id() to anon, authenticated;
grant execute on function public.auth_tum_oteller() to anon, authenticated;
grant execute on function public.auth_otel_erisim(text) to anon, authenticated;

-- 3) Merkez kullanıcıları işaretle (rol bazında — kesin merkez roller)
update public.kullanicilar
set tum_oteller = true
where rol in ('yonetici','muhasebe_muduru');

commit;

-- ============================================================
-- TEST (çalıştırdıktan sonra):
-- a) Kolon eklendi + merkez işaretlendi mi? (yonetici/muhasebe_muduru satırları true olmalı)
-- select rol, tum_oteller, count(*) from public.kullanicilar group by rol, tum_oteller order by rol;
-- b) Fonksiyonlar oluştu mu? (3 satır dönmeli)
-- select proname from pg_proc where proname in ('auth_otel_id','auth_tum_oteller','auth_otel_erisim');
-- NOT: SQL Editor'de auth.uid() null olduğu için auth_otel_id() null döner — bu normal;
-- gerçek per-kullanıcı testi Faz 2'de (giriş yapmış kullanıcıyla) yapılacak.
-- ============================================================
-- ROLLBACK (gerekirse):
-- begin;
-- drop function if exists public.auth_otel_erisim(text);
-- drop function if exists public.auth_tum_oteller();
-- drop function if exists public.auth_otel_id();
-- alter table public.kullanicilar drop column if exists tum_oteller;
-- commit;
