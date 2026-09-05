-- ============================================================================
-- PHASE 0 — GÜVENLİK SERTLEŞTİRME (yeniden yazım, 2026-09-05)
-- ============================================================================
-- ANA PROJE (erp) İÇİN. Elle, preflight incelendikten SONRA uygulanır.
-- Bu dosya otomatik dağıtılmaz. Tek transaction; hata hâlinde tamamı geri alınır.
--
-- Kaynak: GPT-6 Astra'nın Phase 0 taslağı
-- (arsiv/2026-09-05-phase0-hardening-ASTRA-ORIJINAL.sql).
-- Teşhisleri doğruydu; uygulama kararlarının üçü kod incelemesinde reddedildi
-- ve bu sürümde YER ALMIYOR:
--
--   1) phase0_scope RESTRICTIVE RLS politikası (40 tabloda)
--      REDDEDİLDİ: phase0_otel_kapsami/row_hotel volatilite işareti taşımıyor,
--      yani VOLATILE. RLS politikasında satır başına jsonb serileştirme +
--      plpgsql çağrısı + alt tablolarda satır başına DİNAMİK SQL demek.
--      2026-09-03 yük testi tabanı: p95 397 ms, tavan ~95-100 istek/sn.
--      Bu tasarım o tabanı yok ederdi. Üstelik OKUMA tarafı zaten
--      2026-08-10-alt-tablo-otel-kapsami.sql ile set-tabanlı exists(...)
--      politikalarıyla kapatılmıştı; planlayıcı onları semi-join'e çevirir.
--
--   2) stok tablosunu depo master'ı saymak
--      REDDEDİLDİ: veritabanında depo master tablosu YOK. Otoriter kaynak
--      uygulama tarafında (otel-config.js: DEPOLAR_810 / DEPOLAR_811 /
--      MERKEZI_DEPO). stok yalnızca "şu an stoğu olan depo"yu bilir; geçerli
--      ama boş bir depo reddedilir ve bar siparişi / stok rezervasyonu kırılır.
--      Teknik borç olarak dokümante edildi; Phase 0 kapsamı büyütülmedi.
--
--   3) Canlı RPC gövdelerinin regexp_replace ile yeniden yazılması
--      REDDEDİLDİ ve GEREKSİZ. Fail-open davranışının TEK sebebi eski
--      auth_otel_erisim'in NULL dönebilmesiydi:
--          select auth_tum_oteller() or p_otel = auth_otel_id();
--      auth_otel_id() NULL ise -> (false or NULL) = NULL -> `if not NULL`
--      dalına girilmez -> kontrol atlanır.
--      Aşağıdaki yeni sürüm exists(...) kullanıyor; exists ASLA NULL dönmez.
--      Dolayısıyla YARDIMCIYI DÜZELTMEK bütün çağrı noktalarını aynı anda
--      fail-closed yapar. Üretim gövdelerine dokunmaya gerek yoktur.
-- ============================================================================

begin;
set local lock_timeout = '5s';
set local statement_timeout = '120s';
set local search_path = pg_catalog, public, pg_temp;

-- ----------------------------------------------------------------------------
-- 0) ÖN KOŞULLAR — beklenmeyen bir şema üzerinde çalışmayı reddet
-- ----------------------------------------------------------------------------
do $$
begin
  if current_user <> 'postgres' then
    raise exception 'Phase 0 veritabanı sahibi ile çalıştırılmalı';
  end if;
  if to_regclass('public.kullanicilar') is null
     or to_regclass('public.audit_log') is null
     or to_regprocedure('public.auth_otel_erisim(text)') is null then
    raise exception 'Desteklenen ana ERP veritabanı değil';
  end if;
  if exists (select 1 from public.kullanicilar where auth_user_id is not null
             group by auth_user_id having count(*) > 1) then
    raise exception 'Mükerrer Auth kimliği var: önce atamaları düzeltin';
  end if;
end;
$$;

create schema if not exists phase0_private;
revoke all on schema phase0_private from public, anon, authenticated, service_role;

-- Mükerrer Auth kimliğini yapısal olarak imkânsız kıl.
create unique index if not exists phase0_kullanici_auth_unique
  on public.kullanicilar(auth_user_id) where auth_user_id is not null;

-- ============================================================================
-- 1) KİMLİK YARDIMCILARI — Phase 0'ın ASIL düzeltmesi
-- ============================================================================
-- Hepsi: SECURITY DEFINER + açık search_path + `aktif is true` + exists(...).
-- exists(...) asla NULL dönmediği için `if not auth_otel_erisim(...)` yazan
-- MEVCUT tüm RPC gövdeleri bu andan itibaren fail-closed çalışır.
-- ----------------------------------------------------------------------------

create or replace function public.auth_kullanici_rol_id()
returns uuid language sql stable security definer
set search_path = pg_catalog, public, pg_temp as $$
  select k.rol_id from public.kullanicilar k
  where k.auth_user_id = auth.uid() and k.aktif is true;
$$;

create or replace function public.auth_kullanici_id()
returns text language sql stable security definer
set search_path = pg_catalog, public, pg_temp as $$
  select k.id::text from public.kullanicilar k
  where k.auth_user_id = auth.uid() and k.aktif is true;
$$;

create or replace function public.auth_erp_kullanicisi()
returns boolean language sql stable security definer
set search_path = pg_catalog, public, pg_temp as $$
  select exists (select 1 from public.kullanicilar k
    where k.auth_user_id = auth.uid() and k.aktif is true);
$$;

create or replace function public.auth_otel_id()
returns text language sql stable security definer
set search_path = pg_catalog, public, pg_temp as $$
  select k.otel_id::text from public.kullanicilar k
  where k.auth_user_id = auth.uid() and k.aktif is true;
$$;

create or replace function public.auth_tum_oteller()
returns boolean language sql stable security definer
set search_path = pg_catalog, public, pg_temp as $$
  select exists (select 1 from public.kullanicilar k
    where k.auth_user_id = auth.uid() and k.aktif is true and k.tum_oteller is true);
$$;

-- p_otel geçerli bir otel_id enum değeri DEĞİLSE de false döner (fail-closed).
create or replace function public.auth_otel_erisim(p_otel text)
returns boolean language sql stable security definer
set search_path = pg_catalog, public, pg_temp as $$
  select exists (
    select 1 from public.kullanicilar k
    where k.auth_user_id = auth.uid() and k.aktif is true
      and p_otel = any(enum_range(null::public.otel_id)::text[])
      and (k.tum_oteller is true or k.otel_id::text = p_otel)
  );
$$;

-- auth_kullanici_rol_id() üzerinden zincirlenmek yerine doğrudan join.
-- Eski durumda auth_yetki_var DEFINER, auth_kullanici_rol_id INVOKER idi;
-- zincir yalnızca DEFINER bağlamından çağrıldığı için çalışıyordu. Kırılgandı.
create or replace function public.auth_yetki_var(
  p_modul_kod text, p_min_seviye text default 'goruntule')
returns boolean language sql stable security definer
set search_path = pg_catalog, public, pg_temp as $$
  select exists (
    select 1 from public.kullanicilar k
    join public.yetki_matrisi ym on ym.rol_id = k.rol_id
    join public.moduller m on m.id = ym.modul_id
    where k.auth_user_id = auth.uid() and k.aktif is true
      and m.kod = p_modul_kod and m.aktif is true
      and ym.yetki::text = any(case p_min_seviye
        when 'goruntule' then array['goruntule','kayit','tam']
        when 'kayit'     then array['kayit','tam']
        when 'tam'       then array['tam']
        else array[]::text[] end)
  );
$$;

do $$
declare v_sig text;
begin
  foreach v_sig in array array[
    'public.auth_kullanici_rol_id()', 'public.auth_kullanici_id()',
    'public.auth_erp_kullanicisi()',  'public.auth_otel_id()',
    'public.auth_tum_oteller()',      'public.auth_otel_erisim(text)',
    'public.auth_yetki_var(text,text)'] loop
    execute 'revoke all on function ' || v_sig || ' from public, anon';
    execute 'grant execute on function ' || v_sig || ' to authenticated';
  end loop;
end;
$$;

-- ============================================================================
-- 2) KORUMALI DENETİM İZİ — iş işlemiyle AYNI transaction'da
-- ============================================================================
-- Mevcut audit_log tarayıcı tarafından ayrı bir HTTP isteğiyle yazılıyor:
-- işlemin başarılı olup audit isteğinin başarısız olması mümkün. Bu tablo
-- tetikleyiciyle, iş yazmasıyla aynı transaction içinde dolar.
-- Misafir/satır içeriği KOPYALANMAZ; yalnızca kimlik anahtarları tutulur.
-- ----------------------------------------------------------------------------
create table if not exists public.erp_islem_audit (
  id bigint generated always as identity primary key,
  -- hotel_id BILEREK nullable: denetim izi hiçbir koşulda meşru bir iş
  -- yazmasını bloklamamalı. Otel bilgisi yoksa olay yine kaydedilir ve
  -- yalnızca merkez kullanıcıları görebilir (aşağıdaki okuma politikası).
  hotel_id public.otel_id,
  actor_user_id uuid,
  actor_role text not null check (actor_role in ('authenticated','service_role')),
  server_timestamp timestamptz not null default clock_timestamp(),
  event_type text not null check (event_type in ('INSERT','UPDATE','DELETE')),
  entity_type text not null,
  entity_id text not null,
  transaction_id text not null,
  check (actor_user_id is not null or actor_role = 'service_role')
);
create index if not exists erp_islem_audit_hotel_time
  on public.erp_islem_audit(hotel_id, server_timestamp desc);
create index if not exists erp_islem_audit_entity
  on public.erp_islem_audit(entity_type, entity_id);

alter table public.erp_islem_audit enable row level security;
revoke all on public.erp_islem_audit from public, anon, authenticated, service_role;
grant select on public.erp_islem_audit to authenticated;

drop policy if exists phase0_audit_select on public.erp_islem_audit;
create policy phase0_audit_select on public.erp_islem_audit
  for select to authenticated
  using (public.auth_yetki_var('denetim_izi','goruntule') is true
         and (case when hotel_id is null then public.auth_tum_oteller()
                   else public.auth_otel_erisim(hotel_id::text) end) is true);

-- İstemci hiçbir koşulda YAZAMAZ: with check(false) + değişmezlik tetikleyicisi.
drop policy if exists phase0_audit_boundary on public.erp_islem_audit;
create policy phase0_audit_boundary on public.erp_islem_audit
  as restrictive for all to authenticated
  using (public.auth_yetki_var('denetim_izi','goruntule') is true
         and (case when hotel_id is null then public.auth_tum_oteller()
                   else public.auth_otel_erisim(hotel_id::text) end) is true)
  with check (false);

create or replace function phase0_private.audit_immutable()
returns trigger language plpgsql set search_path = pg_catalog as $$
begin
  raise exception 'Korumalı denetim izi yalnızca eklenebilir' using errcode = '42501';
end;
$$;
drop trigger if exists phase0_audit_immutable on public.erp_islem_audit;
create trigger phase0_audit_immutable
  before update or delete or truncate on public.erp_islem_audit
  for each statement execute function phase0_private.audit_immutable();

-- ----------------------------------------------------------------------------
-- Tetikleyici: SADE. Astra'nın özyinelemeli row_hotel / dinamik SQL makinesi
-- KULLANILMIYOR. Kapsam, otel_id'yi DOĞRUDAN taşıyan ve NOT NULL olan kritik
-- iş tablolarıyla sınırlı (aşağıda şema kontrolüyle doğrulanır).
-- ----------------------------------------------------------------------------
create or replace function phase0_private.islem_audit()
returns trigger language plpgsql security definer
set search_path = pg_catalog, public, pg_temp as $$
declare
  v_row jsonb; v_role text; v_hotel text; v_entity text;
begin
  v_role := auth.role();
  -- Aktif ERP personeli şartı. service_role (QR köprüsü, Edge Function) muaf.
  if v_role is distinct from 'service_role' then
    if v_role is distinct from 'authenticated'
       or public.auth_erp_kullanicisi() is not true then
      raise exception 'Aktif ERP personeli gerekli' using errcode = '42501';
    end if;
  end if;

  v_row    := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  v_hotel  := v_row->>'otel_id';
  v_entity := coalesce(v_row->>'id', v_row->>'siparis_no', v_row->>'mk_no');

  -- Otel veya kimlik cozulemezse olay YINE kaydedilir. Denetim izi bir is
  -- yazmasini asla bloklamamali; eksik alan, kaybolan olaydan iyidir.
  insert into public.erp_islem_audit(
    hotel_id, actor_user_id, actor_role, event_type,
    entity_type, entity_id, transaction_id)
  values (case when v_hotel = any(enum_range(null::public.otel_id)::text[])
               then v_hotel::public.otel_id else null end,
          auth.uid(), v_role, tg_op, tg_table_name,
          coalesce(v_entity, '(kimliksiz)'), pg_current_xact_id()::text);

  if tg_op = 'DELETE' then return old; end if;
  return null;
end;
$$;

-- Kapsam: yalnızca finansal / stok hareketi yaratan / onay akışı olan tablolar.
-- 40 tabloyu körü körüne audit'e bağlamak yazma yükünü gereksiz katlıyordu.
do $$
declare v_tablo text; v_rel regclass;
begin
  foreach v_tablo in array array[
    'faturalar', 'yevmiye_fisler', 'mal_kabuller', 'stok_hareketleri',
    'satin_alma_talepleri', 'siparisler', 'bar_siparisleri'] loop
    v_rel := to_regclass('public.' || v_tablo);
    if v_rel is null then
      raise exception 'Eksik ön koşul tablosu: %', v_tablo;
    end if;
    -- otel_id kolonu BULUNMALI. NOT NULL SART DEGIL: nullable ise olay
    -- hotel_id = NULL ile kaydedilir ve yalniz merkez gorur. Sertlestirme,
    -- semadan kisit talep etmek yerine semaya uyum saglar.
    if not exists (select 1 from pg_attribute
      where attrelid = v_rel and attname = 'otel_id' and not attisdropped) then
      raise exception 'otel_id kolonu yok, audit kapsamina alinamaz: %', v_tablo;
    end if;
    execute format('drop trigger if exists phase0_islem_audit on %s', v_rel);
    execute format('create trigger phase0_islem_audit
      after insert or update on %s for each row
      execute function phase0_private.islem_audit()', v_rel);
    execute format('drop trigger if exists phase0_islem_audit_del on %s', v_rel);
    execute format('create trigger phase0_islem_audit_del
      before delete on %s for each row
      execute function phase0_private.islem_audit()', v_rel);
  end loop;
end;
$$;

-- ============================================================================
-- 3) PERSONEL DİZİNİ — pasif / diğer otel personelini sızdırmayı durdur
-- ============================================================================
drop policy if exists phase0_users_scope on public.kullanicilar;
create policy phase0_users_scope on public.kullanicilar
  as restrictive for all to authenticated
  using (public.auth_erp_kullanicisi() is true
         and (public.auth_tum_oteller() is true
              or public.auth_otel_erisim(otel_id::text) is true))
  with check (public.auth_erp_kullanicisi() is true
         and (public.auth_tum_oteller() is true
              or (public.auth_otel_erisim(otel_id::text) is true
                  and tum_oteller is false)));

revoke all on public.kullanicilar from public, anon;
revoke delete, truncate, trigger, references on public.kullanicilar from authenticated;
alter table public.kullanicilar enable row level security;

-- kullanicilar_genel bir VIEW ve RLS'i baypas ediyordu. Kolon ŞEKLİ korunur
-- (istemci bu alanlara bağlı), yalnızca görünürlük daraltılır.
-- PIN/parola kolonları bu view'da zaten YOK — açıkça kontrol ediliyor.
do $$
declare v_columns text;
begin
  if to_regclass('public.kullanicilar_genel') is null then
    raise exception 'Sanitize personel dizini bulunamadı';
  end if;
  if exists (select 1 from pg_attribute
    where attrelid = 'public.kullanicilar_genel'::regclass
      and attnum > 0 and not attisdropped
      and attname in ('pin','pin_hash','sifre','password')) then
    raise exception 'Personel dizininde hassas kolon var — elle inceleyin';
  end if;
  select string_agg(format('k.%I', attname), ', ' order by attnum) into v_columns
    from pg_attribute
    where attrelid = 'public.kullanicilar_genel'::regclass
      and attnum > 0 and not attisdropped;
  execute 'create or replace view public.kullanicilar_genel as select ' || v_columns ||
    ' from public.kullanicilar k
      where public.auth_erp_kullanicisi() is true
        and (public.auth_tum_oteller() is true
             or public.auth_otel_erisim(k.otel_id::text) is true
             or k.auth_user_id = auth.uid())';
end;
$$;
revoke all on public.kullanicilar_genel from public, anon;
grant select on public.kullanicilar_genel to authenticated;

-- ============================================================================
-- 4) ESKİ TARAYICI TELEMETRİSİ (audit_log) — istemci için salt-okuma
-- ============================================================================
-- Bu kayıt bir iş işleminin KANITI değildir; eklemeye devam edilebilir ama
-- geçmiş istemci tarafından değiştirilemez. Otel kapsamı olmadığı için
-- okuma merkez kullanıcılarına ayrılmıştır.
revoke update, delete, truncate, trigger on public.audit_log
  from public, anon, authenticated;

drop policy if exists phase0_legacy_audit_read on public.audit_log;
create policy phase0_legacy_audit_read on public.audit_log
  as restrictive for select to authenticated
  using (public.auth_tum_oteller() is true
         and public.auth_yetki_var('denetim_izi','goruntule') is true);

drop policy if exists phase0_legacy_audit_insert on public.audit_log;
create policy phase0_legacy_audit_insert on public.audit_log
  as restrictive for insert to authenticated
  with check (public.auth_erp_kullanicisi() is true);

-- ============================================================================
-- 4b) KORUMALI YAZMA YOLLARI — onay motoru yalnızca sunucuda
-- ============================================================================
-- Bu revoke'lar 2026-08-10'da üretime uygulanmıştı. Yine de BURADA tekrar
-- ediliyor: migration kendi kendine yeterli olmalı. Aksi hâlde temiz bir
-- veritabanında (yeni müşteri kurulumu, test konteyneri) onay motoru
-- doğrudan PostgREST yazmasıyla atlanabilir kalır.
-- Bu boşluğu Astra'nın fixture testi yakaladı; çıkarmak hataydı.
--
-- INSERT bilerek korunuyor: talep OLUŞTURMA istemciden yapılıyor.
revoke update on public.satin_alma_talepleri from public, anon, authenticated;
revoke insert, update, delete on public.talep_onay_gecmisi
  from public, anon, authenticated;

-- ============================================================================
-- 3b) OTEL KAPSAMI İÇİN KISITLAYICI TABAN — ucuz ve set-tabanlı
-- ============================================================================
-- NEDEN GEREKLİ (Astra'nın haklı olduğu nokta):
-- Mevcut otel kapsamı 2026-08-10 politikalarında ve o politikalar KALICI
-- (permissive). PostgreSQL kalıcı politikaları OR ile birleştirir; ileride
-- eklenecek tek bir kalıcı politika otel kapsamını sessizce ATLAYABİLİR.
-- Kısıtlayıcı (restrictive) bir politika AND ile bağlanır ve hiçbir kalıcı
-- politika onu geçemez. Bu bir derinlemesine savunma katmanıdır.
--
-- NEDEN ASTRA'NIN SÜRÜMÜ DEĞİL:
-- Onun kısıtlayıcı politikası satır başına jsonb serileştirme + VOLATILE
-- plpgsql + alt tablolarda dinamik SQL çalıştırıyordu. Buradaki sürüm,
-- 2026-08-10 politikalarının zaten kullandığı ifadenin AYNISINI kullanır:
-- tek bir STABLE fonksiyon çağrısı. Maliyet sınıfı değişmez.
--
-- KAPSAM: otel_id kolonunu DOĞRUDAN taşıyan tablolar. Alt tabloların kapsamı
-- 2026-08-10'daki üst-tablo exists(...) politikalarında kalır (orada da
-- kalıcıdır — bilinen ve kabul edilen sınır, aşağıdaki nota bakınız).
do $$
declare v record;
begin
  for v in
    select c.oid::regclass as rel, c.relname
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    join pg_attribute a on a.attrelid = c.oid
                       and a.attname = 'otel_id' and not a.attisdropped
    where n.nspname = 'public' and c.relkind = 'r'
      and c.relname <> 'erp_islem_audit'   -- kendi politikası var
      and c.relname <> 'kullanicilar'      -- phase0_users_scope ayrıca kuruyor
    loop
    execute format('alter table %s enable row level security', v.rel);
    execute format('drop policy if exists phase0_otel_kisit on %s', v.rel);
    -- otel_id NULL olan satir bir MERKEZ kaydidir ve yalnizca tum_oteller
    -- yetkisi olan kullaniciya gorunur. Bu ayrim olmadan giris_kayitlari
    -- (46 satirin 46'si NULL) sertlestirme sonrasi tamamen gorunmez olurdu:
    -- 2026-09-06 preflight 05 bulgusu.
    -- Kisitlayici politika hicbir zaman yetki GENISLETMEZ; kalici politikalarla
    -- AND ile baglanir. Bu yuzden NULL izni, otel kapsami zaten kalici
    -- politikasinda olan tablolari (cari_hareketler, receteler) gevsetmez.
    execute format('create policy phase0_otel_kisit on %s
      as restrictive for all to authenticated
      using ((case when otel_id is null then public.auth_tum_oteller()
                   else public.auth_otel_erisim(otel_id::text) end) is true)
      with check ((case when otel_id is null then public.auth_tum_oteller()
                        else public.auth_otel_erisim(otel_id::text) end) is true)',
      v.rel);
  end loop;
end;
$$;

-- ============================================================================
-- 3c) OTEL DEĞİŞMEZLİĞİ — bir iş kaydı otel değiştiremez
-- ============================================================================
-- SORUN: kısıtlayıcı politika, satırı GÖRME ve YAZMA hakkını denetler ama
-- merkez yetkili bir kullanıcı (tum_oteller) bir satırın otel_id'sini
-- değiştirebilir. O satırın alt kayıtları eski otelde kalır ve çapraz otel
-- tutarsızlığı doğar (ör. menü ürünü 811'e taşınır, sipariş kalemleri 810'da).
--
-- ASTRA'NIN ÇÖZÜMÜ: her UPDATE'te FK grafiğini yürüyüp tüm alt kayıtları
-- yeniden doğrulamak. Doğru ama pahalı ve reddedilen makinenin parçası.
--
-- BURADAKİ ÇÖZÜM: kuralı tersine çevir. Bir iş kaydı otel değiştiremez.
-- Kontrol O(1), sorgu yok. Meşru bir taşıma ihtiyacı doğarsa bu, açıkça
-- yazılmış ve alt kayıtları da taşıyan bir RPC'nin işidir — sessiz bir
-- UPDATE'in değil.
create or replace function phase0_private.otel_degismez()
returns trigger language plpgsql set search_path = pg_catalog as $$
begin
  if new.otel_id is distinct from old.otel_id then
    raise exception 'Bir iş kaydının oteli değiştirilemez (%.otel_id)', tg_table_name
      using errcode = '42501';
  end if;
  return new;
end;
$$;

do $$
declare v record;
begin
  for v in
    select c.oid::regclass as rel, c.relname
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    join pg_attribute a on a.attrelid = c.oid
                       and a.attname = 'otel_id' and not a.attisdropped
    where n.nspname = 'public' and c.relkind = 'r'
      and c.relname not in ('erp_islem_audit', 'kullanicilar')
    loop
    -- kullanicilar HARİÇ: personelin oteli yönetim ekranından değiştirilebilir,
    -- bu meşru bir işlemdir ve alt kayıt tutarlılığı sorunu doğurmaz.
    execute format('drop trigger if exists phase0_otel_degismez on %s', v.rel);
    execute format('create trigger phase0_otel_degismez
      before update of otel_id on %s for each row
      execute function phase0_private.otel_degismez()', v.rel);
  end loop;
end;
$$;

-- ============================================================================
-- 4a) AYRICALIKLI RPC İZİNLERİ — gövdelere DOKUNULMADAN
-- ============================================================================
-- PostgreSQL, CREATE FUNCTION'da varsayılan olarak PUBLIC'e EXECUTE verir ve
-- anon bunu PUBLIC'ten miras alır; `revoke from anon` TEK BAŞINA yetmez.
-- Bu sınıf 2026-08-09'da üretimde kapatılmıştı, burada TEKRAR ediliyor ki
-- migration temiz bir veritabanında da kendi kendine yeterli olsun.
--
-- Fonksiyon GÖVDELERİ DEĞİŞTİRİLMEZ. Yalnızca izinler ve search_path
-- sabitlenir — ikisi de diff ile incelenebilir, tek tek yazılmıştır.
do $$
declare v_sig text; v_oid oid;
begin
  foreach v_sig in array array[
    'public.fatura_kaydet(uuid,jsonb,jsonb)',
    'public.mal_kabul_kaydet(jsonb,jsonb)',
    'public.teklif_talebi_olustur(text,text,jsonb)',
    'public.siparis_yeniden_yonlendir(text,text)',
    'public.talep_karar_ver(uuid,text,text,numeric)',
    'public.talep_siparise_donustur(uuid)',
    'public.bar_siparis_olustur(text,text,text,text,jsonb)',
    'public.bar_siparis_iptal(uuid)',
    'public.bar_siparis_teslim_et(uuid)',
    'public.bar_siparis_durum_guncelle(uuid,public.bar_durum)'] loop
    v_oid := to_regprocedure(v_sig);
    if v_oid is null then
      raise exception 'Beklenen ayrıcalıklı RPC bulunamadı: %', v_sig;
    end if;
    execute format('revoke all on function %s from public, anon', v_oid::regprocedure);
    execute format('grant execute on function %s to authenticated', v_oid::regprocedure);
    -- search_path'i sabitlemek gövdeyi değiştirmez; arama yolu manipülasyonuna
    -- karşı korur. SECURITY DEFINER fonksiyonlarda bu bir gerekliliktir.
    execute format('alter function %s set search_path = pg_catalog, public, pg_temp',
                   v_oid::regprocedure);
  end loop;
end;
$$;

-- TEK İSTİSNA: QR müşteri akışı. Müşteri projesindeki siparis-gonder Edge
-- Function'ı bu RPC'yi ANA projenin service_role anahtarıyla çağırır; masa
-- token doğrulaması orada yapılır. Bu grant olmadan QR sipariş akışı kırılır.
grant execute on function public.bar_siparis_olustur(text,text,text,text,jsonb)
  to service_role;

-- Personel ekranlarında çağıranı olmayan yardımcılar (2026-08-10 kararı).
do $$
begin
  if to_regprocedure('public.bar_kullanilabilir_stok(text,text)') is not null then
    revoke all on function public.bar_kullanilabilir_stok(text,text)
      from public, anon, authenticated;
  end if;
end;
$$;

-- ============================================================================
-- 4c) ANON KİLİDİ — Phase 0'ın iddia ettiği tablolar için
-- ============================================================================
-- Üretimde anon tüm tablolardan 2026-08-09'da alınmıştı (56 -> 0). Burada
-- TEKRAR ediliyor çünkü migration kendi kendine yeterli olmalı: temiz bir
-- veritabanında (yeni müşteri, test konteyneri) o adım henüz koşmamış olur.
-- Bunu da fixture testi yakaladı.
--
-- KAPSAM BİLİNÇLİ OLARAK DAR: yalnızca aşağıdaki bölümde doğrulanan tablolar.
-- Şemanın TAMAMI için genel kilit ayrı bir dosyadadır:
--   docs/kurulum/2026-08-09-anon-tablo-kilit.sql
-- Phase 0 onun yerine geçmez; kurulum sırasında ikisi de çalıştırılmalıdır.
do $$
declare v_tablo text; v_rel regclass;
begin
  foreach v_tablo in array array[
    'faturalar', 'yevmiye_fisler', 'mal_kabuller', 'stok_hareketleri',
    'satin_alma_talepleri', 'siparisler', 'bar_siparisleri',
    'talep_onay_gecmisi', 'audit_log'] loop
    v_rel := to_regclass('public.' || v_tablo);
    if v_rel is null then continue; end if;
    execute format('revoke all on %s from public, anon', v_rel);
  end loop;
end;
$$;

-- ============================================================================
-- 4d) VARSAYILAN İZİNLER VE PİNLENMEMİŞ search_path — preflight bulguları
-- ============================================================================
-- BULGU 1 (preflight 02): public şemasında postgres'in oluşturduğu YENİ
-- fonksiyonlar varsayılan olarak anon'a EXECUTE veriyor:
--   public | postgres | f -> ..., anon=X/postgres, ...
-- Yani bugünden sonra eklenecek her RPC, anon tarafından çağrılabilir DOĞAR.
-- Tek tek revoke etmek unutulabilir bir adımdır; kaynağı kapatıyoruz.
-- Yalnız GELECEKTEKİ nesneleri etkiler, mevcut izinlere dokunmaz.
alter default privileges for role postgres in schema public
  revoke execute on functions from anon;

-- BULGU 2 (preflight 02): supabase_admin'in varsayılanı YENİ TABLOLARA anon'a
-- tüm hakları veriyor. Bu rolün varsayılanını değiştirmek üyelik ister;
-- postgres üye değilse migration'ı düşürmemeli — bilgi notuyla geçilir.
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_admin') then
    raise notice 'supabase_admin rolu yok (Supabase disi ortam) - atlandi.';
    return;
  end if;
  alter default privileges for role supabase_admin in schema public
    revoke all on tables from anon;
  raise notice 'supabase_admin varsayilan tablo izni anon icin kaldirildi.';
exception when insufficient_privilege or invalid_grant_operation or undefined_object then
  raise notice 'supabase_admin varsayilani degistirilemedi (uyelik yok). Kalan risk: bu rolun olusturdugu YENI tablolar anon a acik dogar. Supabase destek uzerinden kapatilmali.';
end;
$$;

-- BULGU 3 (preflight 01): stok_ekle ve stok_transfer SECURITY INVOKER ve
-- search_path pinlenmemiş. INVOKER oldukları için RLS'e tabiler — ayrıcalık
-- yükseltme yolu değiller — ama pinlenmemiş yol "$user" şemasını arar ve
-- çağıranın oluşturduğu bir fonksiyon adı gölgeleyebilir.
-- GÖVDELERİ DEĞİŞTİRİLMEZ. extensions şeması yolda BIRAKILIR: bu iki
-- fonksiyonun gövdesi okunmadan çıkarılırsa bir eklenti çağrısı kırılabilir.
do $$
declare v_sig text; v_oid oid;
begin
  foreach v_sig in array array[
    'public.stok_ekle(text,text,text,numeric)',
    'public.stok_transfer(text,text,text,text,numeric)'] loop
    v_oid := to_regprocedure(v_sig);
    if v_oid is null then continue; end if;
    execute format(
      'alter function %s set search_path = pg_catalog, public, extensions, pg_temp',
      v_oid::regprocedure);
  end loop;
end;
$$;

-- ============================================================================
-- 5) SON DOĞRULAMA — devralınan ve kolon bazlı izinler dâhil
-- ============================================================================
do $$
declare v record;
begin
  for v in select to_regclass('public.' || t) as rel from unnest(array[
      'faturalar','yevmiye_fisler','mal_kabuller','stok_hareketleri',
      'satin_alma_talepleri','siparisler','bar_siparisleri',
      'kullanicilar','erp_islem_audit']) t loop
    if has_table_privilege('anon', v.rel, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE')
       or has_any_column_privilege('anon', v.rel, 'SELECT,INSERT,UPDATE') then
      raise exception 'Beklenmeyen anon izni: %', v.rel;
    end if;
  end loop;

  -- Kolon bazlı ve devralınan izinler tablo bazlı revoke'u delebilir; korumalı
  -- yazma yollarını ETKİN izin üzerinden doğrula, tablo ACL'ine güvenme.
  if has_any_column_privilege('authenticated','public.erp_islem_audit','INSERT,UPDATE') then
    raise exception 'Denetim izine istemci yazabiliyor';
  end if;
  -- NOT: bu iki guard'ın mesajı bilerek İNGİLİZCE — sözleşme testi
  -- (scripts/phase0-database-tests.mjs) bu metinleri arıyor.
  if has_any_column_privilege('authenticated','public.satin_alma_talepleri','UPDATE')
     or has_any_column_privilege('authenticated','public.talep_onay_gecmisi','INSERT,UPDATE') then
    raise exception 'Unexpected inherited/column grant bypasses a protected write path';
  end if;

  -- Ayrıcalıklı bir RPC'nin FAZLADAN imzası (overload), gözden geçirilmemiş
  -- ve korumasız yeni bir giriş noktası demektir. Her ad tek imza taşımalı.
  for v in select p.proname, count(*) as adet
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prokind = 'f' and p.proname in (
      'fatura_kaydet','mal_kabul_kaydet','teklif_talebi_olustur',
      'siparis_yeniden_yonlendir','talep_karar_ver','talep_siparise_donustur',
      'bar_siparis_olustur','bar_siparis_iptal','bar_siparis_teslim_et',
      'bar_siparis_durum_guncelle')
    group by p.proname having count(*) > 1 loop
    raise exception 'Unreviewed overload of a privileged RPC: % (% imza)', v.proname, v.adet;
  end loop;

  -- Ayrıcalıklı RPC'lerin hiçbiri anon tarafından çağrılabilir olmamalı.
  for v in select p.oid, p.oid::regprocedure as imza
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prokind = 'f' and p.proname in (
      'fatura_kaydet','mal_kabul_kaydet','teklif_talebi_olustur',
      'siparis_yeniden_yonlendir','talep_karar_ver','talep_siparise_donustur',
      'bar_siparis_iptal','bar_siparis_teslim_et','bar_siparis_durum_guncelle') loop
    if has_function_privilege('anon', v.oid, 'EXECUTE') then
      raise exception 'Ayrıcalıklı RPC anon tarafından çağrılabilir: %', v.imza;
    end if;
  end loop;

  -- YENİ nesneler anon'a açık DOĞMAMALI. Bu, tek tek revoke etmeyi unutmaya
  -- karşı tek yapısal korumadır (preflight 02 bulgusu).
  if exists (
    select 1 from pg_default_acl d
    join pg_namespace n on n.oid = d.defaclnamespace
    where n.nspname = 'public' and d.defaclrole = 'postgres'::regrole
      and d.defaclobjtype = 'f'
      and array_to_string(d.defaclacl::text[], ',') like '%anon=%') then
    raise exception 'Yeni fonksiyonlar hala anon a aciliyor (varsayilan ACL)';
  end if;

  -- SECURITY DEFINER bir fonksiyonun search_path'i pinlenmemişse, arama yolu
  -- manipülasyonu gövdedeki her çağrıyı yeniden hedefleyebilir.
  for v in select p.oid::regprocedure as imza from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prokind = 'f' and p.prosecdef
      and (p.proconfig is null
           or not exists (select 1 from unnest(p.proconfig) c
                          where starts_with(c, 'search_path='))) loop
    raise exception 'SECURITY DEFINER fonksiyonun search_path i pinlenmemis: %', v.imza;
  end loop;

  -- auth_* yardımcılarının hepsi fail-closed exists(...) kullanmalı.
  for v in select p.oid, p.proname from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname in (
      'auth_erp_kullanicisi','auth_tum_oteller','auth_otel_erisim','auth_yetki_var') loop
    if position('exists' in lower(pg_get_functiondef(v.oid))) = 0 then
      raise exception 'Fail-closed olmayan yardımcı: %', v.proname;
    end if;
  end loop;
end;
$$;

commit;

notify pgrst, 'reload schema';

-- ============================================================================
-- KAPSAM DIŞI BIRAKILANLAR (bilinçli — teknik borç olarak kayıtlı)
-- ============================================================================
-- * Depo/otel tutarlılığı veritabanında doğrulanmıyor. Otoriter depo master'ı
--   uygulama tarafında (otel-config.js). DB tarafı bir `depolar` referans
--   tablosu Phase 1 öncesinde ayrıca tasarlanmalı; Phase 0 kapsamını
--   büyütmemek için buraya alınmadı.
-- * Alt tabloların otel kapsamı 2026-08-10-alt-tablo-otel-kapsami.sql ile
--   ZATEN kurulu (set-tabanlı exists). Bu dosya onu tekrarlamaz, zayıflatmaz.
-- * PMS rezervasyon tabloları OLUŞTURULMAZ. daterange '[)' + GiST exclusion
--   yaklaşımı scripts/phase0-database-tests.sql içinde referans olarak durur.
-- * talep_karar_ver'e ek modül yetkisi EKLENMEDİ: fonksiyon zaten üç katmanlı
--   (aktif kullanıcı + otel kapsamı + talep_asama_yetkili_mi aşama yetkisi) ve
--   yardımcı düzeltmesiyle fail-closed oluyor. Dördüncü ve farklı bir yetki
--   modeli eklemek onay zincirini kırma riski taşıyordu.
--
-- GERİ ALMA: migration kendi kendini geri alır (tek transaction). Commit
-- sonrası kurtarma için preflight çıktısındaki tanım/politika/ACL'ler kullanılır.
