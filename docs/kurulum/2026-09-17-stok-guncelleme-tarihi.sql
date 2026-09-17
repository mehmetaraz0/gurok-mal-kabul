-- ============================================================================
-- STOK GUNCELLEME TARIHI — stok_ekle / stok_transfer guncelleme_tarihi = now()
--
-- Bulgu (2026-09-15 duman testi, 2026-09-17 salt-okuma teshisi):
--   public.stok.guncelleme_tarihi yalniz INSERT varsayilani (default now())
--   ile doluyor. Stok'a yazan iki fonksiyonun hicbiri UPDATE yolunda sutunu
--   set etmiyor; tabloda sutunu guncelleyen tetikleyici de yok.
--   Uretim olcumu: 24 satirin en yenisi 2026-07-31, son 30 gunde 0 satir;
--   son hareketi sutundan sonra gelen satirlar: cikis 3/3, giris 10/16,
--   transfer 3/5.
--
-- Degisiklik: YALNIZ iki UPDATE yoluna `guncelleme_tarihi = now()`.
--   - stok_ekle     : on conflict do update set ... , guncelleme_tarihi = now()
--   - stok_transfer : kaynak bacak UPDATE + hedef bacak on conflict do update
--   Fonksiyonlar SECURITY INVOKER oldugu icin onkosul, cagiran rollerin
--   sutun uzerinde UPDATE yetkisini de dogrular.
--   Miktar hesabi, imza, donus tipi, dil, search_path, SECURITY INVOKER ve
--   EXECUTE ACL'si DEGISMEZ. INSERT yollari zaten default now() alir.
--
-- Denetim  : node scripts/migration-guvenlik-kontrol.mjs docs/kurulum/2026-09-17-stok-guncelleme-tarihi.sql
-- Izole test: node scripts/stok-guncelleme-tarihi.test.mjs
-- ============================================================================


-- ============================================================================
-- 0) ONKOSULLAR — uretimde olculen hal ile birebir ayni mi?
-- ----------------------------------------------------------------------------
-- Govde md5'leri 2026-09-17 teshisinde (2026-09-17-stok-guncelleme-tarihi-
-- teshis.sql, bolum 1) olculdu. Arada biri fonksiyonu degistirdiyse (or.
-- bar-guvenlik plani stok_cikis_korumasi ekledi) bu migration o degisikligi
-- EZMEMELI: dur, yeniden olc, yeniden yaz.
-- EXECUTE ACL'si de beklenen halde olmali; boylece asagidaki acik
-- revoke/grant cifti uretimde fiilen bir sey degistirmez.
-- ============================================================================
do $$
declare
  v_ekle     oid := to_regprocedure('public.stok_ekle(text,text,text,numeric)');
  v_transfer oid := to_regprocedure('public.stok_transfer(text,text,text,text,numeric)');
  v_f oid;
begin
  if to_regclass('public.stok') is null then
    raise exception 'ONKOSUL: public.stok yok.';
  end if;
  if v_ekle is null or v_transfer is null then
    raise exception 'ONKOSUL: stok_ekle / stok_transfer imzasi bulunamadi.';
  end if;

  if (select md5(prosrc) from pg_proc where oid = v_ekle) = '24d255cc03df86bb4c9f6c978cadce81'
     and (select md5(prosrc) from pg_proc where oid = v_transfer) = '4c6fe1217463841653bec7637f3bf259' then
    null;  -- olculen hal: uygula
  elsif (select prosrc ~* 'guncelleme_tarihi' from pg_proc where oid = v_ekle)
     and (select prosrc ~* 'guncelleme_tarihi' from pg_proc where oid = v_transfer) then
    raise notice 'Govdeler zaten guncelleme_tarihi iceriyor; yeniden yazim idempotent.';
  else
    raise exception 'ONKOSUL: stok_ekle/stok_transfer govdesi 2026-09-17 olcumunden farkli. Ezmemek icin durduruldu; teshisi yeniden calistirin.';
  end if;

  -- Fonksiyonlar SECURITY INVOKER: yeni SET, cagiranin sutun yetkisiyle
  -- calisir. UPDATE yetkisi sutun bazinda kisitliysa her stok yazmasi
  -- 42501 ile kirilirdi — uygulamadan once dur.
  if not has_column_privilege('authenticated', 'public.stok', 'guncelleme_tarihi', 'UPDATE')
     or not has_column_privilege('service_role', 'public.stok', 'guncelleme_tarihi', 'UPDATE') then
    raise exception 'ONKOSUL: authenticated/service_role public.stok.guncelleme_tarihi uzerinde UPDATE yetkisine sahip degil; bu degisiklik stok yazmalarini kirardi.';
  end if;

  foreach v_f in array array[v_ekle, v_transfer] loop
    if (select prosecdef from pg_proc where oid = v_f) then
      raise exception 'ONKOSUL: % beklenmedik sekilde SECURITY DEFINER.', v_f::regprocedure;
    end if;
    if has_function_privilege('anon', v_f, 'EXECUTE')
       or (select proacl is null or exists (select 1 from aclexplode(proacl) a
                                             where a.grantee = 0 and a.privilege_type = 'EXECUTE')
             from pg_proc where oid = v_f)
       or not has_function_privilege('authenticated', v_f, 'EXECUTE')
       or not has_function_privilege('service_role', v_f, 'EXECUTE') then
      raise exception 'ONKOSUL: % EXECUTE ACL beklenen halde degil (public/anon kapali, authenticated+service_role acik olmali).', v_f::regprocedure;
    end if;
  end loop;
end;
$$;


-- ============================================================================
-- 1) FONKSIYONLAR — uretim govdesi + guncelleme_tarihi = now()
-- ============================================================================
create or replace function public.stok_ekle(p_urun_kodu text, p_depo_kodu text, p_otel_id text, p_delta numeric)
returns numeric
language plpgsql
set search_path to 'pg_catalog', 'public', 'extensions', 'pg_temp'
as $function$
declare
  v_yeni numeric;
begin
  insert into stok (urun_kodu, depo_kodu, otel_id, miktar)
  values (p_urun_kodu, p_depo_kodu, p_otel_id::otel_id, greatest(0, p_delta))
  on conflict (urun_kodu, depo_kodu)
  do update set miktar = greatest(0, stok.miktar + p_delta),
                guncelleme_tarihi = now()
  returning miktar into v_yeni;
  return v_yeni;
end;
$function$;

create or replace function public.stok_transfer(p_urun_kodu text, p_kaynak_depo text, p_hedef_depo text, p_hedef_otel text, p_miktar numeric)
returns void
language plpgsql
set search_path to 'pg_catalog', 'public', 'extensions', 'pg_temp'
as $function$
begin
  update stok set miktar = greatest(0, miktar - p_miktar),
                  guncelleme_tarihi = now()
    where urun_kodu = p_urun_kodu and depo_kodu = p_kaynak_depo;
  insert into stok (urun_kodu, depo_kodu, otel_id, miktar)
    values (p_urun_kodu, p_hedef_depo, p_hedef_otel::otel_id, p_miktar)
    on conflict (urun_kodu, depo_kodu)
    do update set miktar = greatest(0, stok.miktar + p_miktar),
                  guncelleme_tarihi = now();
end;
$function$;


-- ============================================================================
-- 2) ACL — standartin acik karari. Onkosul mevcut halin bu oldugunu
--    kanitladi; create or replace ACL'yi zaten korur. Uretimde no-op.
-- ============================================================================
revoke all on function public.stok_ekle(text, text, text, numeric) from public, anon;
grant execute on function public.stok_ekle(text, text, text, numeric) to authenticated, service_role;
revoke all on function public.stok_transfer(text, text, text, text, numeric) from public, anon;
grant execute on function public.stok_transfer(text, text, text, text, numeric) to authenticated, service_role;


-- ============================================================================
-- 3) SON KOSULLAR
-- ============================================================================
do $$
declare v_f oid;
begin
  foreach v_f in array array[
      to_regprocedure('public.stok_ekle(text,text,text,numeric)'),
      to_regprocedure('public.stok_transfer(text,text,text,text,numeric)')] loop
    if not (select prosrc ~* 'guncelleme_tarihi\s*=\s*now\(\)' from pg_proc where oid = v_f) then
      raise exception 'SON KOSUL: % govdesinde guncelleme_tarihi = now() yok.', v_f::regprocedure;
    end if;
    if (select prosecdef from pg_proc where oid = v_f)
       or (select proconfig from pg_proc where oid = v_f)
          is distinct from array['search_path=pg_catalog, public, extensions, pg_temp'] then
      raise exception 'SON KOSUL: % guvenlik/ayar degisti.', v_f::regprocedure;
    end if;
    if has_function_privilege('anon', v_f, 'EXECUTE')
       or not has_function_privilege('authenticated', v_f, 'EXECUTE') then
      raise exception 'SON KOSUL: % EXECUTE ACL degisti.', v_f::regprocedure;
    end if;
  end loop;
end;
$$;
