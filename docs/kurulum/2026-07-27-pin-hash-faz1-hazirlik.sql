-- 2026-07-27 — [3] Faz 1: pin_hash doldurma + giris_denemeleri + pin_dogrula RPC
--
-- KAPSAM: Bu script YALNIZCA HAZIRLIK yapar. Mevcut giris akisini (index.html,
-- pin_ile_kullanici_ara, supabaseAuthKoprusu) HIC DEGISTIRMEZ ve HIC BOZMAZ.
-- Calistiktan sonra uygulama tamamen eskisi gibi calismaya devam eder.
--
--   1) kullanicilar.pin_hash (zaten var, bos) mevcut pin'lerden pgcrypto/bcrypt
--      ile doldurulur. kullanicilar.pin sutununa DOKUNULMAZ, SILINMEZ.
--   2) giris_denemeleri tablosu eklenir (sunucu tarafi rate-limit icin, IP hash
--      bazli). RLS acik + politika yok -> yalnizca service_role erisebilir
--      (service_role Postgres'te RLS'i bypass eder).
--   3) pin_dogrula(p_giris, p_ip_hash) RPC'si eklenir: TAM 6 hane + bcrypt
--      karsilastirmasi + rate-limit kontrolu yapar. [2]'nin dersi geregi bu
--      RPC'ye anon/authenticated'e HICBIR execute yetkisi VERILMEZ -- yalnizca
--      Faz 3'te yazilacak Edge Function'in service_role client'i cagirabilecek.
--      Bu script calistiktan sonra bu RPC'yi hicbir istemci cagiramaz (henuz
--      cagiran bir Edge Function da yok) -- tamamen pasif, zararsiz durur.
--
-- ONEMLI (UYGULANDI): canli projede pgcrypto 'extensions' semasinda kurulu
-- oldugu dogrulandi (select extnamespace::regnamespace from pg_extension
-- where extname='pgcrypto' -> 'extensions' dondu). Bu yuzden asagidaki
-- pin_dogrula() fonksiyonunun search_path'i `public, extensions` olarak
-- guncellendi -- fonksiyon crypt()/gen_salt()'i bu sayede bulabilecek.
-- Baska bir ortamda calistirilacaksa pgcrypto semasini tekrar kontrol edin.
--
-- Guvenli test onerisi: asagidaki `commit;` satirini gecici olarak `rollback;`
-- yaparak once DRY-RUN calistirip hata olup olmadigini gorebilirsiniz, sonra
-- gercek `commit;` ile kalici hale getirin.
--
-- Calistirma: Supabase Dashboard -> SQL Editor -> bu dosyanin tamamini yapistir -> Run.
-- Sonra asagidaki TEST bolumundeki sorgularla dogrulayin.
-- Geri alma: en alttaki ROLLBACK blogunu ayrica calistirin (hicbir mevcut veriyi
-- bozmaz -- yalnizca bu script'in ekledigi yeni tablo/fonksiyonu kaldirir).

begin;

-- 1) pgcrypto (yoksa kur; Supabase'de genellikle zaten kurulu olur)
create extension if not exists pgcrypto;

-- 2) Mevcut pin'lerden pin_hash'i doldur (pin sutunu SILINMIYOR, dokunulmuyor)
update public.kullanicilar
set pin_hash = crypt(pin, gen_salt('bf'))
where pin is not null
  and pin_hash is null;

-- 3) Sunucu taraflı rate-limit tablosu (IP hash bazli, kullanici bilgisi tutmaz)
create table if not exists public.giris_denemeleri (
  id bigint generated always as identity primary key,
  ip_hash text not null,
  basarili boolean not null,
  created_at timestamptz not null default now()
);

create index if not exists giris_denemeleri_ip_zaman_idx
  on public.giris_denemeleri (ip_hash, created_at desc);

alter table public.giris_denemeleri enable row level security;
-- Kasitli olarak HICBIR policy eklenmiyor. RLS acik + policy yok = owner ve
-- service_role (RLS'i bypass eder) haric hicbir role bu tabloya erisemez.
-- anon/authenticated icin select/insert/update/delete YOK.

-- 4) pin_dogrula RPC'si — TAM 6 hane esleme + bcrypt + rate-limit.
-- Not: pin_ile_kullanici_ara() (docs/kurulum/2026-07-27-pin-tam-eslesme.sql) ile
-- AYNI donus seklini korur, boylece Faz 3'te Edge Function bu satirlari dogrudan
-- mevcut client-side kullanici nesnesi seklinde kullanabilir.
create or replace function public.pin_dogrula(p_giris text, p_ip_hash text)
returns table (
  id uuid, ad text, rol public.kullanici_rol, rol_id uuid,
  departman text, otel_id public.otel_id, depo_id text,
  eposta text, auth_user_id uuid
)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_basarisiz_sayisi int;
  v_eslesme_sayisi int;
begin
  if p_ip_hash is null or length(p_ip_hash) = 0 then
    raise exception 'p_ip_hash zorunlu';
  end if;

  -- Son 15 dakikada bu IP'den 10'dan fazla basarisiz deneme varsa: dogrudan
  -- reddet, deneme kaydi bile eklemeden (kilit suresini uzatmamak icin).
  select count(*) into v_basarisiz_sayisi
  from public.giris_denemeleri
  where ip_hash = p_ip_hash
    and basarili = false
    and created_at > now() - interval '15 minutes';

  if v_basarisiz_sayisi >= 10 then
    return;
  end if;

  select count(*) into v_eslesme_sayisi
  from public.kullanicilar k
  where k.aktif = true
    and k.pin_hash is not null
    and char_length(p_giris) = 6
    and k.pin_hash = crypt(p_giris, k.pin_hash);

  insert into public.giris_denemeleri (ip_hash, basarili)
  values (p_ip_hash, v_eslesme_sayisi > 0);

  if v_eslesme_sayisi = 0 then
    return;
  end if;

  return query
  select k.id, k.ad, k.rol, k.rol_id, k.departman, k.otel_id, k.depo_id, k.eposta, k.auth_user_id
  from public.kullanicilar k
  where k.aktif = true
    and k.pin_hash is not null
    and char_length(p_giris) = 6
    and k.pin_hash = crypt(p_giris, k.pin_hash);
end;
$$;

-- KRITIK: anon/authenticated/public HICBIR execute yetkisi ALMAZ. Yalnizca
-- service_role (Faz 3'teki Edge Function'in kullanacagi client) cagirabilir.
revoke all on function public.pin_dogrula(text, text) from public;
revoke all on function public.pin_dogrula(text, text) from anon;
revoke all on function public.pin_dogrula(text, text) from authenticated;
grant execute on function public.pin_dogrula(text, text) to service_role;

commit;

-- ============================================================
-- TEST — Supabase SQL Editor'de sirayla calistirip dogrulayin:
-- ============================================================

-- a) Backfill tamamlandi mi? (0 donmeli)
-- select count(*) from public.kullanicilar where pin is not null and pin_hash is null;

-- b) Bilinen bir kullanicinin gercek PIN'i ile hash eslesiyor mu? (true donmeli)
-- select (pin_hash = crypt(pin, pin_hash)) as eslesiyor_mu
-- from public.kullanicilar where id = '<test edilecek kullanicinin id'si>';

-- c) pin_dogrula dogru PIN ile 1 satir donuyor mu? (SQL Editor postgres/owner
--    olarak calistigi icin service_role grant'indan bagimsiz calisir, sadece
--    fonksiyon mantigini test eder)
-- select * from public.pin_dogrula('<test kullanicisinin GERCEK 6 haneli PIN''i>', 'test-ip-hash-1');

-- d) Yanlis PIN ile 0 satir donuyor mu?
-- select * from public.pin_dogrula('000000', 'test-ip-hash-1');

-- e) giris_denemeleri'ne kayit dustu mu? (yukaridaki c+d cagrilarindan sonra
--    en az 2 satir gormelisiniz: biri basarili=true, biri basarili=false)
-- select * from public.giris_denemeleri where ip_hash = 'test-ip-hash-1' order by created_at desc;

-- f) Rate-limit calisiyor mu? (asagidaki sorguyu 'test-ip-hash-2' ile 11 kez
--    yanlis PIN vererek cagirin; 11. cagride de bos donmeli -- rate-limit'e
--    takildigi icin, "yanlis PIN" ile ayni gorunen davranis)
-- select * from public.pin_dogrula('000000', 'test-ip-hash-2');  -- 10 kez calistirin
-- select * from public.pin_dogrula('000000', 'test-ip-hash-2');  -- 11. cagri -- bos donmeli (rate-limit)

-- g) anon/authenticated gercekten cagiramiyor mu? (PostgREST uzerinden, yani
--    tarayicidan/curl ile SB_KEY (anon) kullanarak asagidaki REST cagrisi
--    denendiginde 401/403 donmeli):
--    POST {SB_URL}/rest/v1/rpc/pin_dogrula   body: {"p_giris":"123456","p_ip_hash":"x"}
--    Beklenen: HTTP 401 veya "permission denied for function pin_dogrula"

-- ============================================================
-- ROLLBACK — bir sorun cikarsa bu bloğu ayrica calistirin. Mevcut
-- kullanicilar.pin / pin_hash verisine DOKUNMAZ, yalnizca bu script'in
-- ekledigi yeni tablo/fonksiyonu kaldirir:
-- ============================================================
-- begin;
-- drop function if exists public.pin_dogrula(text, text);
-- drop table if exists public.giris_denemeleri;
-- commit;
--
-- (pin_hash backfill'ini geri almak ISTERSENIZ -- normalde gerekmez, zararsizdir:)
-- -- begin;
-- -- update public.kullanicilar set pin_hash = null;
-- -- commit;
