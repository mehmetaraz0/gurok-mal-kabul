-- ============================================================================
-- STOK LISTESI VE OZETI — sunucu tarafi sayfalama ve toplamlar
-- Tarih: 2026-09-14
-- ============================================================================
-- ###########################################################################
-- # URETIME UYGULANMADI. `CANLIYA UYGULA` onayi olmadan calistirilmaz.      #
-- # Bu dosya ADAY migration'dir; yalniz yerel/atilabilir ortamda dogrulandi.#
-- ###########################################################################
--
-- NEDEN: stok-takip ekrani listeyi `stok?select=*` ile cekiyordu — filtresiz,
-- sayfalamasiz. PostgREST'in satir tavani asildiginda liste SESSIZCE kirpiliyor
-- ve toplamlar bellekteki (kirpilmis) listeden sayiliyordu. Sayfalama ancak
-- sunucu tarafinda filtrelenebilir bir kaynak ve sunucudan gelen toplam varsa
-- dogru olur.
--
-- NE YAPAR:
--   1. public.stok_liste  — stok + urun adi/birim + urun bazli minimum
--   2. public.stok_ozet(p_depo) — toplam / kritik / uyari / normal sayilari
--
-- RLS: gorunum `security_invoker = true`, fonksiyon SECURITY INVOKER. Ikisi de
-- CAGIRANIN haklariyla calisir; `stok` uzerindeki mevcut politikalar ve otel
-- izolasyonu aynen gecerlidir. Yeni nesneler `anon`'a KAPALIDIR.
--
-- ESIK SEMANTIGI: bugunku istemci mantigi BIREBIR korunur (stok-takip.html
-- getStokDurum): minimum yoksa/0 ise normal; miktar <= 0 ya da miktar <= min/2
-- ise kritik; miktar <= min ise uyari; degilse normal. Minimum, urun basina
-- DEPOLAR ARASI EN YUKSEK degerdir — bu da bugunku davranistir (Firebase
-- mirasi; stok_minimumlar depo kirilimli olsa da ekran max aliyor). Minimumun
-- depo bazinda ele alinmasi AYRI bir karardir, bu migration'in konusu degildir.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1) GORUNUM
-- ---------------------------------------------------------------------------
create or replace view public.stok_liste
with (security_invoker = true) as
  select
    s.otel_id,
    s.depo_kodu,
    s.urun_kodu,
    u.ad    as urun_adi,
    u.birim as birim,
    s.miktar,
    (select max(m.min_miktar)
       from public.stok_minimumlar m
      where m.urun_kodu = s.urun_kodu) as min_miktar,
    s.guncelleme_tarihi
  from public.stok s
  left join public.urunler u on u.kod = s.urun_kodu;

comment on view public.stok_liste is
  'Stok satirlari + urun adi/birim + urun bazli en yuksek minimum. security_invoker: RLS cagirana gore uygulanir.';

revoke all on public.stok_liste from public, anon;
grant select on public.stok_liste to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2) OZET FONKSIYONU
-- ---------------------------------------------------------------------------
-- Toplamlar SAYFADAN degil buradan gelir. SECURITY INVOKER: sayilar da
-- cagiranin gorebildigi satirlar uzerinden hesaplanir.
create or replace function public.stok_ozet(p_depo text default null)
returns table (toplam bigint, kritik bigint, uyari bigint, normal bigint)
language sql
stable
security invoker
set search_path = public
as $fn$
  with v as (
    select l.miktar, coalesce(l.min_miktar, 0) as min_miktar
      from public.stok_liste l
     where p_depo is null or l.depo_kodu = p_depo
  ), d as (
    select case
             when min_miktar <= 0 then 'normal'
             when miktar <= 0 or miktar <= min_miktar * 0.5 then 'kritik'
             when miktar <= min_miktar then 'uyari'
             else 'normal'
           end as durum
      from v
  )
  select count(*)::bigint,
         count(*) filter (where durum = 'kritik')::bigint,
         count(*) filter (where durum = 'uyari')::bigint,
         count(*) filter (where durum = 'normal')::bigint
    from d;
$fn$;

comment on function public.stok_ozet(text) is
  'Depo bazinda stok durumu sayilari. Esikler stok-takip getStokDurum ile birebir aynidir.';

revoke all on function public.stok_ozet(text) from public, anon;
grant execute on function public.stok_ozet(text) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3) KATEGORI LISTESI
-- ---------------------------------------------------------------------------
-- Ekrandaki kategori sekmeleri, urun kodunun ilk 5 karakterinden turuyor.
-- Sayfalamadan sonra bunu YUKLENMIS satirlardan uretmek sekmelerin eksik
-- cikmasina yol acardi; liste de sunucudan gelir.
create or replace function public.stok_kategoriler(p_depo text default null)
returns table (kategori text, adet bigint)
language sql
stable
security invoker
set search_path = public
as $fn$
  select left(l.urun_kodu, 5) as kategori, count(*)::bigint
    from public.stok_liste l
   where p_depo is null or l.depo_kodu = p_depo
   group by 1
   order by 1;
$fn$;

comment on function public.stok_kategoriler(text) is
  'Depo bazinda urun kodu onekleri (kategori sekmeleri). Sayfadan degil, tum kayitlardan.';

revoke all on function public.stok_kategoriler(text) from public, anon;
grant execute on function public.stok_kategoriler(text) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4) ABC GIRDILERI
-- ---------------------------------------------------------------------------
-- ABC siniflandirmasi urun basina (tum depolardaki stok) ve (son 7 gunun
-- tuketimi) ister. Ikisi de TUM kayitlar uzerinden hesaplanmalidir; ekran
-- sayfali yuklendigi icin istemci bunu kendi basina yapamaz.
create or replace function public.stok_abc_girdi(p_gun integer default 7)
returns table (urun_kodu text, stok_miktar numeric, tuketim_miktar numeric)
language sql
stable
security invoker
set search_path = public
as $fn$
  with s as (
    select l.urun_kodu, sum(l.miktar) as stok_miktar
      from public.stok_liste l
     group by 1
  ), t as (
    select h.urun_kodu, sum(h.miktar) as tuketim_miktar
      from public.stok_hareketleri h
     where h.tip = 'cikis'
       and h.tarih >= now() - make_interval(days => greatest(p_gun, 1))
       and (h.aciklama ilike '%gunluk_tuketim%' or h.aciklama ilike '%recete_tuketim%')
     group by 1
  )
  select coalesce(s.urun_kodu, t.urun_kodu),
         coalesce(s.stok_miktar, 0),
         coalesce(t.tuketim_miktar, 0)
    from s full outer join t on t.urun_kodu = s.urun_kodu;
$fn$;

comment on function public.stok_abc_girdi(integer) is
  'ABC siniflandirmasi girdileri: urun basina toplam stok ve son N gun tuketimi. Sayfadan degil, tum kayitlardan.';

revoke all on function public.stok_abc_girdi(integer) from public, anon;
grant execute on function public.stok_abc_girdi(integer) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 5) DOGRULAMA — sessiz basari yok
-- ---------------------------------------------------------------------------
do $dogrula$
declare
  v_invoker boolean;
  v_anon_view boolean;
  v_anon_fn boolean;
  v_auth_view boolean;
  v_auth_fn boolean;
  v_secdef boolean;
begin
  select coalesce((select (c.reloptions::text like '%security_invoker=true%')
                     from pg_class c join pg_namespace n on n.oid = c.relnamespace
                    where n.nspname = 'public' and c.relname = 'stok_liste'), false)
    into v_invoker;
  if not v_invoker then
    raise exception 'stok_liste security_invoker DEGIL — RLS atlanir, uygulanmaz';
  end if;

  select has_table_privilege('anon', 'public.stok_liste', 'select') into v_anon_view;
  select (has_function_privilege('anon', 'public.stok_ozet(text)', 'execute')
       or has_function_privilege('anon', 'public.stok_kategoriler(text)', 'execute')
       or has_function_privilege('anon', 'public.stok_abc_girdi(integer)', 'execute')) into v_anon_fn;
  if v_anon_view or v_anon_fn then
    raise exception 'anon erisimi acik kalmis (view=%, fn=%)', v_anon_view, v_anon_fn;
  end if;

  select has_table_privilege('authenticated', 'public.stok_liste', 'select') into v_auth_view;
  select has_function_privilege('authenticated', 'public.stok_ozet(text)', 'execute') into v_auth_fn;
  if not (v_auth_view and v_auth_fn) then
    raise exception 'authenticated erisimi eksik (view=%, fn=%)', v_auth_view, v_auth_fn;
  end if;

  select bool_or(p.prosecdef) into v_secdef
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname in ('stok_ozet', 'stok_kategoriler', 'stok_abc_girdi');
  if v_secdef then
    raise exception 'stok_ozet/stok_kategoriler SECURITY DEFINER olmus — cagiranin RLS''i atlanir';
  end if;

  raise notice 'DOGRULAMA (stok liste/ozet): tum kontroller gecti.';
end
$dogrula$;

commit;
