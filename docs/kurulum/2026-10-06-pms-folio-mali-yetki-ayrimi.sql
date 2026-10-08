-- ===========================================================================
-- PMS folyo — NORMAL TAHSİLAT / HASSAS MALİ İŞLEM ayrımı (ileri yönlü)
-- ===========================================================================
-- Onaylı tasarım: 2026-10-06-PMS-mali-islem-yetkileri-onayli-tasarim.md
-- Yayımlanmış tarihsel migration'lar (2026-09-06-...-adim4-folio.sql) ÜZERİNE
-- YAZILMAZ; bu dosya yalnız INSERT kapısını daraltır.
--
-- KURAL
--   NORMAL  (pms_folio:kayit yeter)
--     hareket : tutar > 0 ve tip <> 'duzeltme' ve ters_kayit = false
--     ödeme   : tutar > 0
--   HASSAS  (pms_folio:tam + GEREKÇE zorunlu)
--     hareket : tutar < 0  VEYA tip = 'duzeltme'  VEYA ters_kayit = true
--     ödeme   : tutar < 0
--     gerekçe : btrim(aciklama) <> ''  (asgari uzunluk UYDURULMADI)
--   (tutar = 0 zaten `pms_folio_hareketleri_tutar_check` ile yasak.)
--
-- DEĞİŞMEZLİK KORUNUR: bu dosya append-only kurgusuna DOKUNMAZ. Mali
-- hareket/ödeme satırları ŞEF DAHİL kimse tarafından UPDATE/DELETE edilemez;
-- üç katman (ayrıcalık yok + politika yok + `pms_folio_degismez` tetikleyicisi)
-- olduğu gibi kalır. Dosyanın sonunda bu üç katman ÖLÇÜLÜR.
--
-- İKİ KATMAN
--   1) RLS INSERT politikası — kullanıcının doğrudan yazma yolu.
--   2) `before insert` tetikleyici — RLS'i atlayan yollar da dahil her yol,
--      ayrıca kullanıcıya ANLAŞILIR hata mesajı.
--
-- SİSTEM İSTİSNASI YOKTUR (MY-3)
--   Önceki sürümde `current_user <> session_user` + `kaynak_tip='bar'` ile dar
--   bir istisna vardı. ÖLÇÜLDÜ: bu birleşim güvenilir bir "onaylı bar
--   fonksiyonundan gelindi" kanıtı değildir — rol farkı sıradan SET ROLE ile de
--   oluşur ve `kaynak_tip` istemcinin yazabildiği bir alandır.
--   İstisnaya GEREK DE YOKTUR: `bar_siparis_kalemleri.adet > 0` ve
--   `menu_urun.birim_fiyat >= 0` kısıtları yüzünden bar köprüsünün tutarı
--   negatif olamaz (sıfırda erken döner) ve `bar_borc_istisnalari.tutar > 0`
--   kısıtı vardır. Bu yüzden istisna KALDIRILDI; sistem akışları normal daldan
--   geçer ve gerçek fonksiyonlarıyla olumlu kontrolde ölçülür.
--
-- Geri alma: 2026-10-06-pms-folio-mali-yetki-ayrimi-geri-al.sql
--   YAYIN BAĞIMLILIĞI: bu kural doğrulanmadan personel/vardiyaya `kayit`
--   açılmaz; geri alırken de personelin `kayit` yetkisi AÇIK kalırken eski
--   geniş INSERT kuralı geri getirilmez. Geri alma dosyası bunu ZORLAR.
-- ===========================================================================

begin;

do $$
begin
  if to_regclass('public.pms_folio_hareketleri') is null
     or to_regclass('public.pms_folio_odemeler') is null then
    raise exception 'PMS folyo adimi uygulanmamis: pms_folio_* tablolari yok';
  end if;
  if to_regprocedure('public.auth_yetki_var(text, text)') is null then
    raise exception 'auth_yetki_var yok: yetki katmani kurulmamis';
  end if;
end $$;

-- --- 1) Hassas kapı: tek kaynak, iki tabloda da aynı ----------------------
create or replace function public.pms_folio_hassas_mi(
  p_tablo text, p_tutar numeric, p_tip text, p_ters boolean)
returns boolean language sql immutable
set search_path = pg_catalog, public, pg_temp as $$
  select case
    when p_tablo = 'pms_folio_hareketleri'
      then p_tutar < 0 or p_tip = 'duzeltme' or p_ters is true
    else p_tutar < 0
  end;
$$;

comment on function public.pms_folio_hassas_mi(text, numeric, text, boolean) is
  'Folyo satiri hassas mi (iade/indirim/duzeltme)? tam + gerekce ister.';

-- --- 1b) Fonksiyon ACL kararI -------------------------------------------
-- OLCULDU (izole taban + bu migration): fonksiyon olusturulduktan sonra
--   proacl = =X/postgres,postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres
-- yani `=X/postgres` PUBLIC hakkidir ve `anon` EXECUTE yetkisini PUBLIC
-- uzerinden DEVRALIR (has_function_privilege(anon,...)=true). Statik
-- denetleyici bunu R9-FONKSIYON-ACL-KARARI-YOK uyarisiyla gosteriyordu.
-- Karar artik acikca yazilidir; kullanici talimati (2026-10-08).
REVOKE ALL ON FUNCTION public.pms_folio_hassas_mi(text,numeric,text,boolean)
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.pms_folio_hassas_mi(text,numeric,text,boolean)
TO authenticated, service_role;

-- --- 2) Tetikleyici: her yol + anlasilir mesaj ----------------------------
create or replace function public.pms_folio_hassas_kapi()
returns trigger language plpgsql
set search_path = pg_catalog, public, pg_temp as $$
declare
  -- Iki tabloda da ayni islev kosar; `pms_folio_odemeler` tablosunda `tip`,
  -- `ters_kayit` ve `kaynak_tip` SUTUNLARI YOKTUR. Dogrudan `new.tip` yazmak
  -- PL/pgSQL'de degisken ilklendirmede hata verir (olculdu), bu yuzden satir
  -- jsonb'ye cevrilip alanlar VARSA okunur.
  v_satir    jsonb   := to_jsonb(new);
  v_tutar    numeric := (v_satir->>'tutar')::numeric;
  v_aciklama text    := v_satir->>'aciklama';
  v_tip      text    := v_satir->>'tip';
  v_ters     boolean := coalesce((v_satir->>'ters_kayit')::boolean, false);
begin
  if not public.pms_folio_hassas_mi(tg_table_name, v_tutar, v_tip, v_ters) then
    return new;                                  -- normal islem: kapi yok
  end if;

  if public.auth_yetki_var('pms_folio','tam') is not true then
    raise exception
      'MALI_TAM_YETKI_GEREKLI: iade, indirim ve duzeltme icin folyo TAM yetkisi '
      'gerekir. Normal (pozitif) tahsilat ve ucret kaydi icin KAYIT yetkisi '
      'yeterlidir. Tablo: %', tg_table_name
      using errcode = '42501';
  end if;

  if btrim(coalesce(v_aciklama, '')) = '' then
    raise exception
      'MALI_GEREKCE_ZORUNLU: hassas mali islem (iade/indirim/duzeltme) icin '
      'aciklama alanina gerekce yazilmasi zorunludur. Tablo: %', tg_table_name
      using errcode = '23514';
  end if;

  return new;
end;
$$;

drop trigger if exists pms_folio_hassas_kapi on public.pms_folio_hareketleri;
create trigger pms_folio_hassas_kapi before insert
  on public.pms_folio_hareketleri
  for each row execute function public.pms_folio_hassas_kapi();

drop trigger if exists pms_folio_hassas_kapi on public.pms_folio_odemeler;
create trigger pms_folio_hassas_kapi before insert
  on public.pms_folio_odemeler
  for each row execute function public.pms_folio_hassas_kapi();

-- --- 3) RLS INSERT politikalarini DARALT ---------------------------------
-- Eski politika: auth_yetki_var('pms_folio','kayit') — normal ile hassas
-- islemi ayirmiyordu. Yenisi iki dala ayirir. Otel kapsami AYNEN korunur.
drop policy if exists pms_folio_hareketleri_insert on public.pms_folio_hareketleri;
create policy pms_folio_hareketleri_insert on public.pms_folio_hareketleri
  for insert to authenticated
  with check (
    public.auth_otel_erisim(otel_id::text) is true
    and (
      ( not public.pms_folio_hassas_mi('pms_folio_hareketleri', tutar, tip::text, ters_kayit)
        and public.auth_yetki_var('pms_folio','kayit') is true )
      or
      ( public.pms_folio_hassas_mi('pms_folio_hareketleri', tutar, tip::text, ters_kayit)
        and public.auth_yetki_var('pms_folio','tam') is true
        and btrim(coalesce(aciklama, '')) <> '' )
    )
  );

drop policy if exists pms_folio_odemeler_insert on public.pms_folio_odemeler;
create policy pms_folio_odemeler_insert on public.pms_folio_odemeler
  for insert to authenticated
  with check (
    public.auth_otel_erisim(otel_id::text) is true
    and (
      ( not public.pms_folio_hassas_mi('pms_folio_odemeler', tutar, null, false)
        and public.auth_yetki_var('pms_folio','kayit') is true )
      or
      ( public.pms_folio_hassas_mi('pms_folio_odemeler', tutar, null, false)
        and public.auth_yetki_var('pms_folio','tam') is true
        and btrim(coalesce(aciklama, '')) <> '' )
    )
  );

-- --- 4) DEĞİŞMEZLİK ve KAPSAM ölçümü (gevşetilmediği kanıtı) -------------
do $$
declare v_t text; v_n int; v_hata text := '';
begin
  foreach v_t in array array['pms_folio_hareketleri','pms_folio_odemeler'] loop
    -- (a) update/delete AYRICALIGI olmamali
    if has_table_privilege('authenticated', 'public.' || v_t, 'UPDATE')
       or has_table_privilege('authenticated', 'public.' || v_t, 'DELETE') then
      v_hata := v_hata || v_t || ': authenticated UPDATE/DELETE ayricaligi VAR; ';
    end if;
    -- (b) update/delete POLITIKASI olmamali
    select count(*) into v_n from pg_policies
     where schemaname='public' and tablename=v_t and cmd in ('UPDATE','DELETE');
    if v_n > 0 then
      v_hata := v_hata || v_t || ': update/delete politikasi VAR (' || v_n || '); ';
    end if;
    -- (c) degismezlik tetikleyicisi yerinde olmali
    if not exists (select 1 from pg_trigger t join pg_class c on c.oid=t.tgrelid
                    where c.relname=v_t and t.tgname='pms_folio_degismez'
                      and not t.tgisinternal) then
      v_hata := v_hata || v_t || ': pms_folio_degismez tetikleyicisi YOK; ';
    end if;
    -- (d) yeni hassas kapi yerinde olmali
    if not exists (select 1 from pg_trigger t join pg_class c on c.oid=t.tgrelid
                    where c.relname=v_t and t.tgname='pms_folio_hassas_kapi'
                      and not t.tgisinternal) then
      v_hata := v_hata || v_t || ': pms_folio_hassas_kapi tetikleyicisi YOK; ';
    end if;
    -- (e) RLS acik olmali
    if not exists (select 1 from pg_class where relname=v_t and relrowsecurity) then
      v_hata := v_hata || v_t || ': RLS KAPALI; ';
    end if;
  end loop;
  if v_hata <> '' then
    raise exception 'DEGISMEZLIK/KAPSAM OLCUMU BASARISIZ: %', v_hata
      using errcode = '23514';
  end if;
  raise notice 'Mali yetki ayrimi kuruldu. Degismezlik 3 katman yerinde; '
               'update/delete ayricaligi ve politikasi YOK (sef dahil).';
end $$;

-- --- 5) Yönetim hesaplari envanteri (bilgi; bu dosya DEGISTIRMEZ) --------
do $$
declare v_liste text;
begin
  select string_agg(r.kod || '=' || ym.yetki::text, ', ' order by r.kod)
    into v_liste
  from public.yetki_matrisi ym
  join public.roller   r on r.id = ym.rol_id
  join public.moduller m on m.id = ym.modul_id
  where m.kod = 'pms_folio' and ym.yetki::text = 'tam';
  raise notice 'ENVANTER — pms_folio TAM yetkisi olan roller: %',
    coalesce(v_liste, '(hic)');
  raise notice 'Bu dosya hicbir rolun yetkisini EKLEMEZ/KALDIRMAZ.';
end $$;

commit;
