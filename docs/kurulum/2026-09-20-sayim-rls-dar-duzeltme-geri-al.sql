-- ===========================================================================
-- SAYIM ERISIM DUZELTMESI — GERI ALMA   ** ONAY BEKLIYOR, UYGULANMADI **
-- ===========================================================================
-- 2026-09-20-sayim-rls-dar-duzeltme.sql dosyasini geri alir: 4 politika
-- dusurulur ve tablolar duzeltme ONCESI duruma doner (sayim ekrani yeniden
-- CALISMAZ hale gelir — duzeltme oncesi durum budur).
--
-- NOT: sayim_detaylari'na SELECT grant'i BURADA DA geri verilmez; o grant'i
-- A1 bilerek kaldirdi ve bu dosyanin kapsami disindadir.
-- NOT: TRUNCATE/DELETE haklari geri verilmez. Bunlar duzeltmenin getirdigi bir
-- kisit degil, ayri bir guvenlik duzeltmesidir; geri verilmesi gerekirse ayri
-- ve bilincli bir karar olmalidir.
-- ===========================================================================
begin;

drop policy if exists sayim_oturum_select on public.sayim_oturumlari;
drop policy if exists sayim_oturum_insert on public.sayim_oturumlari;
drop policy if exists sayim_oturum_reddet on public.sayim_oturumlari;
drop policy if exists sayim_detay_insert  on public.sayim_detaylari;

do $$
declare v_n integer;
begin
  select count(*) into v_n from pg_policies
   where schemaname = 'public'
     and policyname in ('sayim_oturum_select','sayim_oturum_insert','sayim_oturum_reddet','sayim_detay_insert');
  if v_n <> 0 then raise exception 'SON KOSUL: politikalar dusurulemedi (%)', v_n; end if;
end $$;

commit;
