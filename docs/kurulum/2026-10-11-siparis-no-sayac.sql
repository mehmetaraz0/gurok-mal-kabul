-- ============================================================================
-- ORTAK SIPARIS NUMARASI URETECI
-- Standart : docs/kurulum/MIGRATION-GUVENLIK-STANDARDI.md
-- Tasarim  : docs/superpowers/specs/2026-10-11-talep-siparis-bagi-design.md §4
--
-- NEDEN: siparis numarasi bugun UC ayri istemci kopyasinda `max+1` ile
-- uretiliyor (satin-alma-siparisolustur / satin-alma-iade / stok-takip).
-- Iki kullanici ayni anda ayni maksimumu okuyabiliyor; `siparis_no` PK oldugu
-- icin sonuc sessiz mukerrer degil, gorunur hata — ama siparis yazilmiyor.
-- Bu dosya tek SERI kaynak kurar; dort yol da bunu kullanacak.
--
-- BU DOSYA YAZILDI, URETIME UYGULANMADI.
-- ============================================================================

-- 0) ONKOSULLAR
do $$
begin
  if to_regclass('public.siparisler') is null then
    raise exception 'ONKOSUL: siparisler tablosu yok.';
  end if;
  if to_regprocedure('public.auth_yetki_var(text, text)') is null then
    raise exception 'ONKOSUL: auth_yetki_var yok (Phase 0 gerekli).';
  end if;
end;
$$;

begin;

-- 1) SAYAC TABLOSU
create table if not exists public.siparis_no_sayac (
  prefix     text        primary key,
  son_no     bigint      not null,
  guncelleme timestamptz not null default now(),
  constraint siparis_no_sayac_onek    check (prefix in ('C','R')),
  constraint siparis_no_sayac_pozitif check (son_no >= 0)
);

-- 2) RLS: politika YOK — tabloya kimse dogrudan erisemez, yalniz
--    `siparis_no_uret` (security definer) yazar. Bos RLS = fail-closed.
--    Erisim YOKLUGU kasitlidir; standart yonergesiyle beyan ediliyor:
-- @erisim-yok: siparis_no_sayac
alter table public.siparis_no_sayac enable row level security;
revoke all on table public.siparis_no_sayac from public, anon, authenticated, service_role;

-- 3) TOHUMLAMA: mevcut maksimumdan basla (yoksa taban 91110)
insert into public.siparis_no_sayac (prefix, son_no) values
  ('C', coalesce((select max(substring(siparis_no from 2)::bigint)
                    from public.siparisler where siparis_no ~ '^C[0-9]{8}$'), 91110)),
  ('R', coalesce((select max(substring(siparis_no from 2)::bigint)
                    from public.siparisler where siparis_no ~ '^R[0-9]{8}$'), 91110))
on conflict (prefix) do nothing;

-- 4) URETEC
create or replace function public.siparis_no_uret(p_prefix text)
returns text
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $fn$
declare
  v_son  bigint;
  v_max  bigint;
  v_yeni bigint;
begin
  if p_prefix is null or p_prefix not in ('C','R') then
    raise exception 'onek_gecersiz: % (C veya R olmali)', coalesce(p_prefix,'<null>')
      using errcode = '22023';
  end if;

  -- SECURITY DEFINER RLS'i atlar; atlanan yetki kontrolu BURADA yeniden uygulanir.
  if public.auth_yetki_var('siparis_olustur','kayit') is not true then
    raise exception 'yetkisiz: siparis_olustur kayit yetkisi gerekir'
      using errcode = '42501';
  end if;

  -- Satir kilidi: eszamanli cagrilar SIRAYA girer, ayni numarayi almazlar.
  select son_no into v_son from public.siparis_no_sayac
   where prefix = p_prefix for update;
  if not found then
    raise exception 'sayac_yok: % oneki icin sayac satiri yok', p_prefix
      using errcode = '23503';
  end if;

  -- Sayac geride kalirsa (elle yazilmis kayit, eski veri) kendini toparlar.
  select coalesce(max(substring(siparis_no from 2)::bigint), 0) into v_max
    from public.siparisler
   where siparis_no ~ ('^' || p_prefix || '[0-9]{8}$');

  v_yeni := greatest(v_son, v_max) + 1;

  update public.siparis_no_sayac
     set son_no = v_yeni, guncelleme = now()
   where prefix = p_prefix;

  return p_prefix || lpad(v_yeni::text, 8, '0');
end;
$fn$;

-- 5) FONKSIYON ACL (standart R9 + R11)
revoke all on function public.siparis_no_uret(text) from public, anon;
revoke all on function public.siparis_no_uret(text) from service_role;
grant execute on function public.siparis_no_uret(text) to authenticated;

commit;

notify pgrst, 'reload schema';

-- ============================================================================
-- GERI ALMA
--   begin;
--   drop function if exists public.siparis_no_uret(text);
--   drop table if exists public.siparis_no_sayac;
--   commit;
-- Istemciler bu fonksiyona gectikten SONRA geri alinirsa siparis olusturma
-- kirilir; geri alma ancak istemci degisikligi de geri alinirsa anlamlidir.
-- ============================================================================
