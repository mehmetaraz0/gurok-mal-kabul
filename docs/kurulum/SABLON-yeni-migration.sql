-- ============================================================================
-- SABLON — YENI MIGRATION (PMS Faz 2 ve sonrasi)
--
-- Bu dosya CALISTIRILMAK icin degil, KOPYALANMAK icindir.
-- Kopyala:  docs/kurulum/<YYYY-AA-GG>-<konu>.sql
-- Ornek adlari (ornek_*) kendi nesne adlarinla degistir.
--
-- Standart : docs/kurulum/MIGRATION-GUVENLIK-STANDARDI.md
-- Denetim  : node scripts/migration-guvenlik-kontrol.mjs docs/kurulum/<dosya>.sql
--
-- Sablonun kendisi denetleyiciden TEMIZ gecer. Once onu calistir, sonra
-- degistir; kirmizi verdigi anda neyi bozdugunu bilirsin.
-- ============================================================================


-- ============================================================================
-- 0) ONKOSULLAR  (prerequisites)
-- ----------------------------------------------------------------------------
-- Bagimli oldugun her sey GERCEKTEN var mi? Yoksa transaction'i burada,
-- hicbir sey yaratmadan durdur. "Yarim uygulanmis migration" en pahali
-- durumdur; onkosul kontrolu onu bastan imkansiz kilar.
-- ============================================================================
do $$
begin
  -- Yetki motoru
  if to_regclass('public.yetki_matrisi') is null then
    raise exception 'ONKOSUL: yetki_matrisi yok. Once Phase 0 uygulanmali.';
  end if;

  -- Phase 0 fail-closed yardimcilari (RLS politikalari bunlara dayanir)
  if to_regprocedure('public.auth_yetki_var(text, text)') is null
     or to_regprocedure('public.auth_otel_erisim(text)') is null then
    raise exception 'ONKOSUL: auth_yetki_var / auth_otel_erisim yok.';
  end if;

  -- Denetim izi altyapisi
  if to_regnamespace('phase0_private') is null then
    raise exception 'ONKOSUL: phase0_private semasi yok.';
  end if;

  -- Bu migration daha once uygulanmis mi? (idempotency guvenligi)
  if to_regclass('public.ornek_baslik') is not null then
    raise notice 'Bu migration zaten uygulanmis gorunuyor; adimlar idempotent.';
  end if;
end;
$$;


-- ============================================================================
-- 1) TRANSACTION
-- ----------------------------------------------------------------------------
-- HER SEY tek transaction icinde. Supabase SQL Editor'de dosyanin tamami
-- tek seferde yapistirilir; parca parca calistirma.
--
-- NOT: "create index concurrently" transaction icinde CALISMAZ. Gerekiyorsa
-- ayri bir dosyaya al ve commit'ten SONRA calistir.
-- ============================================================================
begin;


-- ============================================================================
-- 2) NESNE OLUSTURMA  (object creation)
-- ============================================================================

-- --- 2a) Sekans ---------------------------------------------------------
create sequence if not exists public.ornek_no_seq;

-- --- 2b) Normal CRUD tablosu -------------------------------------------
create table if not exists public.ornek_baslik (
  id            uuid primary key default gen_random_uuid(),
  otel_id       public.otel_id not null,
  no            text not null,
  durum         text not null default 'acik',
  aciklama      text,
  olusturuldu   timestamptz not null default now(),
  guncellendi   timestamptz not null default now(),

  -- Bilesik benzersizlik: (id, otel_id) — cocuk tablolarin bilesik FK'si
  -- buna baglanir; capraz-otel baglanti YAPISAL olarak imkansiz olur.
  unique (id, otel_id)
);

-- --- 2c) Append-only finansal tablo ------------------------------------
-- @append-only: ornek_hareket
create table if not exists public.ornek_hareket (
  id            uuid primary key default gen_random_uuid(),
  otel_id       public.otel_id not null,
  baslik_id     uuid not null,
  tutar         numeric(12,2) not null,
  aciklama      text,
  olusturuldu   timestamptz not null default now(),

  -- Bilesik FK: cocuk yalniz AYNI otelin basligina baglanabilir.
  constraint ornek_hareket_baslik_fk
    foreign key (baslik_id, otel_id)
    references public.ornek_baslik (id, otel_id)
    on delete restrict
);


-- ============================================================================
-- 3) KISITLAR  (constraints)
-- ----------------------------------------------------------------------------
-- Is kurali veritabaninda da gecerli olmali. Istemci dogrulamasi bir
-- kolaylik; kisit bir garantidir.
-- ============================================================================
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'ornek_baslik_durum_chk') then
    alter table public.ornek_baslik
      add constraint ornek_baslik_durum_chk check (durum in ('acik','kapali','iptal'));
  end if;

  if not exists (select 1 from pg_constraint where conname = 'ornek_hareket_tutar_chk') then
    alter table public.ornek_hareket
      add constraint ornek_hareket_tutar_chk check (tutar <> 0);
  end if;
end;
$$;


-- ============================================================================
-- 4) INDEKSLER  (indexes)
-- ----------------------------------------------------------------------------
-- RLS politikalari otel_id uzerinden filtreler: otel_id ONDE olan bilesik
-- indeks olmadan her sorgu seq scan olur.
--
-- Kismi UNIQUE indeks = idempotency anahtari. Ayni islemin iki kez
-- gonderilmesi (cift tiklama, yeniden deneme) ikinci kaydi URETEMEZ.
-- ============================================================================
create index if not exists ornek_baslik_otel_idx
  on public.ornek_baslik (otel_id, durum);

create index if not exists ornek_hareket_baslik_idx
  on public.ornek_hareket (baslik_id, olusturuldu);

create unique index if not exists ornek_baslik_no_uniq
  on public.ornek_baslik (otel_id, no);


-- ============================================================================
-- 5) FONKSIYONLAR
-- ----------------------------------------------------------------------------
-- SECURITY DEFINER kullaniyorsan search_path'i PINLEMEK ZORUNDASIN.
-- Pinlenmemis arama yolu, govdedeki her cagriyi saldirganin semasina
-- yonlendirebilir — fonksiyon sahibinin yetkisiyle.
-- ============================================================================

-- Append-only bekci: ayricalik ve politika yetmez, service_role RLS'i
-- baypas eder. Ucuncu katman tetikleyicidir.
create or replace function public.ornek_degismez()
returns trigger language plpgsql
set search_path = pg_catalog, public, pg_temp as $$
begin
  raise exception
    'Finansal kayit degistirilemez/silinemez (%.%). Duzeltme icin ters kayit girin',
    tg_table_name, lower(tg_op)
    using errcode = '42501';
end;
$$;

drop trigger if exists ornek_degismez on public.ornek_hareket;
create trigger ornek_degismez before update or delete
  on public.ornek_hareket
  for each row execute function public.ornek_degismez();

-- Cagrilabilir RPC. SECURITY DEFINER ise: yetkiyi GOVDEDE kendin dogrula.
-- Definer, RLS'i cagiranin ustunden alir; kontrolu geri koymak SENIN isin.
create or replace function public.ornek_kapat(p_baslik_id uuid)
returns void language plpgsql security definer
set search_path = pg_catalog, public, pg_temp as $$
declare v_otel public.otel_id;
begin
  -- Sadece TRUE gecer. exists(...) asla NULL donmez; "is true" fail-closed.
  if not (public.auth_yetki_var('ornek','kayit') is true) then
    raise exception 'Yetki yok' using errcode = '42501';
  end if;

  -- Kilitle: kilitsiz okuma READ COMMITTED altinda yarisi kaybeder.
  select otel_id into v_otel
    from public.ornek_baslik
   where id = p_baslik_id
     for update;

  if v_otel is null then
    raise exception 'Kayit bulunamadi' using errcode = 'P0002';
  end if;

  -- Istemciden gelen otel_id'ye GUVENME; satirin kendi otel_id'sini dogrula.
  if not (public.auth_otel_erisim(v_otel::text) is true) then
    raise exception 'Yetki yok' using errcode = '42501';
  end if;

  update public.ornek_baslik set durum = 'kapali', guncellendi = now()
   where id = p_baslik_id;
end;
$$;


-- ============================================================================
-- 6) GORUNUM  (view)
-- ----------------------------------------------------------------------------
-- security_invoker = true OLMADAN gorunum, SAHIBININ haklariyla calisir ve
-- RLS'i tamamen atlatir. Varsayilan yanlis taraftadir; acikca yaz.
-- ============================================================================
create or replace view public.ornek_ozet
with (security_invoker = true) as
select b.id, b.otel_id, b.no, b.durum,
       coalesce(sum(h.tutar), 0) as bakiye
  from public.ornek_baslik b
  left join public.ornek_hareket h on h.baslik_id = b.id
 group by b.id, b.otel_id, b.no, b.durum;


-- ============================================================================
-- 7) RLS
-- ----------------------------------------------------------------------------
-- Izin (GRANT) ile politika (POLICY) AYRI katmanlardir. Ikisi de gerekir.
-- Kisitlayici (restrictive) politika hicbir zaman erisimi GENISLETMEZ;
-- otel kapsamini onunla kilitleriz.
-- ============================================================================
alter table public.ornek_baslik  enable row level security;
alter table public.ornek_hareket enable row level security;

drop policy if exists ornek_baslik_select on public.ornek_baslik;
create policy ornek_baslik_select on public.ornek_baslik for select to authenticated
  using (public.auth_yetki_var('ornek','goruntule') is true
         and public.auth_otel_erisim(otel_id::text) is true);

drop policy if exists ornek_baslik_insert on public.ornek_baslik;
create policy ornek_baslik_insert on public.ornek_baslik for insert to authenticated
  with check (public.auth_yetki_var('ornek','kayit') is true
              and public.auth_otel_erisim(otel_id::text) is true);

drop policy if exists ornek_baslik_update on public.ornek_baslik;
create policy ornek_baslik_update on public.ornek_baslik for update to authenticated
  using (public.auth_yetki_var('ornek','kayit') is true
         and public.auth_otel_erisim(otel_id::text) is true)
  with check (public.auth_yetki_var('ornek','kayit') is true
              and public.auth_otel_erisim(otel_id::text) is true);

drop policy if exists ornek_baslik_delete on public.ornek_baslik;
create policy ornek_baslik_delete on public.ornek_baslik for delete to authenticated
  using (public.auth_yetki_var('ornek','tam') is true
         and public.auth_otel_erisim(otel_id::text) is true);

-- Append-only tabloda UPDATE/DELETE POLITIKASI DA yoktur. Politikasiz islem
-- RLS altinda 0 satir eder; ayricalik zaten verilmedi; ustune tetikleyici var.
drop policy if exists ornek_hareket_select on public.ornek_hareket;
create policy ornek_hareket_select on public.ornek_hareket for select to authenticated
  using (public.auth_yetki_var('ornek','goruntule') is true
         and public.auth_otel_erisim(otel_id::text) is true);

drop policy if exists ornek_hareket_insert on public.ornek_hareket;
create policy ornek_hareket_insert on public.ornek_hareket for insert to authenticated
  with check (public.auth_yetki_var('ornek','kayit') is true
              and public.auth_otel_erisim(otel_id::text) is true);

-- Kisitlayici otel kapsami: yukaridaki izin verici politikalarin HEPSININ
-- ustune AND'lenir. Biri unutulsa bile otel sinirini bu tutar.
do $$
declare v_tablo text;
begin
  foreach v_tablo in array array['ornek_baslik','ornek_hareket'] loop
    execute format('drop policy if exists phase0_otel_kisit on public.%I', v_tablo);
    execute format($f$create policy phase0_otel_kisit on public.%I
      as restrictive for all to authenticated
      using ((case when otel_id is null then public.auth_tum_oteller()
                   else public.auth_otel_erisim(otel_id::text) end) is true)
      with check ((case when otel_id is null then public.auth_tum_oteller()
                        else public.auth_otel_erisim(otel_id::text) end) is true)$f$,
      v_tablo);
  end loop;
end;
$$;


-- ============================================================================
-- 8) TABLO IZINLERI  (grants / revokes)
-- ----------------------------------------------------------------------------
-- ONCE HEPSINI AL, SONRA ASGARIYI VER.
--
-- "authenticated" mutlaka revoke listesinde olmali. Varsayilan ayricaliklar
-- (ALTER DEFAULT PRIVILEGES) yeni tabloya authenticated icin ALL vermis
-- olabilir; yalniz public/anon'u geri almak, append-only kisitini SESSIZCE
-- etkisiz birakir. Bu ders 6 Eylul 2026'da odendi.
-- ============================================================================
revoke all on table public.ornek_baslik  from public, anon, authenticated;
revoke all on table public.ornek_hareket from public, anon, authenticated;

-- Normal CRUD tablo: DELETE yalnizca gercekten gerekiyorsa.
grant select, insert, update, delete on public.ornek_baslik to authenticated;

-- Append-only finansal tablo: UPDATE/DELETE AYRICALIGI DAHI YOK.
grant select, insert on public.ornek_hareket to authenticated;

grant all on public.ornek_baslik  to service_role;
grant all on public.ornek_hareket to service_role;


-- ============================================================================
-- 9) SEKANS IZINLERI  (sequence ACL)
-- ----------------------------------------------------------------------------
-- authenticated'a ALL degil, USAGE. ALL, sekansi setval ile geri sarmaya
-- izin verir; belge numaralari cakisir.
-- ============================================================================
revoke all on sequence public.ornek_no_seq from public, anon, authenticated;
grant usage on sequence public.ornek_no_seq to authenticated;
grant all   on sequence public.ornek_no_seq to service_role;


-- ============================================================================
-- 10) FONKSIYON VE GORUNUM IZINLERI  (function ACL)
-- ----------------------------------------------------------------------------
-- PostgreSQL yeni fonksiyona PUBLIC icin EXECUTE verir. Her cagrilabilir
-- fonksiyon icin bu acikca geri alinir.
--
-- Tetikleyici fonksiyonlari (returns trigger) dogrudan cagrilamaz; onlar
-- icin ACL karari gerekmez.
-- ============================================================================
revoke all on function public.ornek_kapat(uuid) from public, anon;
grant execute on function public.ornek_kapat(uuid) to authenticated, service_role;

revoke all on public.ornek_ozet from public, anon;
grant select on public.ornek_ozet to authenticated, service_role;


-- ============================================================================
-- 11) DENETIM IZI  (audit)
-- ----------------------------------------------------------------------------
-- Denetim, is islemiyle AYNI transaction icinde yazilir. Istemciden ayri
-- HTTP istegiyle gonderilen denetim, is islemi geri alindiginda kalir ya da
-- hic gonderilmez — ikisi de yalan soyler.
--
-- Kapsam: para hareketi ve durum degistiren tablolar. Her tabloya takma;
-- gurultu denetim izini kullanilmaz hale getirir.
-- ============================================================================
do $$
declare v_tablo text;
begin
  if to_regprocedure('phase0_private.islem_audit()') is null then
    raise notice 'phase0_private.islem_audit yok; denetim tetikleyicisi atlandi.';
    return;
  end if;
  foreach v_tablo in array array['ornek_baslik','ornek_hareket'] loop
    execute format('drop trigger if exists phase0_islem_audit on public.%I', v_tablo);
    execute format('create trigger phase0_islem_audit
                    after insert or update or delete on public.%I
                    for each row execute function phase0_private.islem_audit()', v_tablo);
  end loop;
end;
$$;


-- ============================================================================
-- 12) MODUL VE YETKI KAYDI
-- ============================================================================
insert into public.moduller (kod, ad, aktif)
values ('ornek', 'Ornek Modul', true)
on conflict (kod) do nothing;


-- ============================================================================
-- 13) DOGRULAMA  (validation) — COMMIT'TEN ONCE
-- ----------------------------------------------------------------------------
-- "Calisti" yeterli degil; SAYARAK dogrula. Bu blok patlarsa transaction
-- geri alinir ve veritabani migration'a hic girmemis gibi kalir.
--
-- Her kontrol, gercekten OLCEBILECEGIN bir seyi olcmeli. Sifir donduren bir
-- sorgu "sorun yok" degil, "hicbir sey olcmedim" de olabilir.
-- ============================================================================
do $$
declare n int;
begin
  -- RLS her iki tabloda acik mi?
  select count(*) into n from pg_class c
    join pg_namespace ns on ns.oid = c.relnamespace
   where ns.nspname = 'public'
     and c.relname in ('ornek_baslik','ornek_hareket')
     and c.relrowsecurity;
  if n <> 2 then raise exception 'DOGRULAMA: RLS acik tablo % (2 bekleniyor)', n; end if;

  -- Append-only tabloda authenticated'in UPDATE/DELETE ayricaligi OLMAMALI.
  if has_table_privilege('authenticated', 'public.ornek_hareket', 'UPDATE')
     or has_table_privilege('authenticated', 'public.ornek_hareket', 'DELETE') then
    raise exception 'DOGRULAMA: append-only tabloda yazma ayricaligi kalmis';
  end if;

  -- anon hicbir seye erisememeli.
  if has_table_privilege('anon', 'public.ornek_baslik', 'SELECT')
     or has_table_privilege('anon', 'public.ornek_hareket', 'SELECT') then
    raise exception 'DOGRULAMA: anon tablo hakki kalmis';
  end if;

  -- anon RPC cagiramamali.
  if has_function_privilege('anon', 'public.ornek_kapat(uuid)', 'EXECUTE') then
    raise exception 'DOGRULAMA: anon RPC cagirabiliyor';
  end if;

  -- Idempotency indeksi GERCEKTEN unique mi? (adi dogru, tanimi yanlis olabilir)
  select count(*) into n from pg_index i
    join pg_class c on c.oid = i.indexrelid
   where c.relname = 'ornek_baslik_no_uniq' and i.indisunique;
  if n <> 1 then raise exception 'DOGRULAMA: idempotency indeksi unique degil'; end if;

  -- SECURITY DEFINER fonksiyonlarin search_path pini
  select count(*) into n from pg_proc p
    join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname like 'ornek%'
     and p.prosecdef and (p.proconfig is null
       or not exists (select 1 from unnest(p.proconfig) k where k like 'search_path=%'));
  if n <> 0 then raise exception 'DOGRULAMA: pinsiz SECURITY DEFINER %', n; end if;

  raise notice 'DOGRULAMA: tum kontroller gecti.';
end;
$$;


commit;


-- ============================================================================
-- 14) GERI ALMA / OZELLIGI KAPATMA  (rollback / disable notes)
-- ----------------------------------------------------------------------------
-- TERCIH SIRASI:
--
-- 1) OZELLIGI KAPAT (en guvenli, veri kaybi yok):
--       update public.moduller set aktif = false where kod = 'ornek';
--    auth_yetki_var() modul aktifligini sart kostugu icin tum politikalar
--    aninda kapanir.
--    UYARI: SECURITY DEFINER tetikleyiciler modul kapali olsa da calisir.
--    Varsa ayrica dusurulmelidir.
--
-- 2) NESNELERI DUSUR (yalniz tablo BOSSA):
--       drop trigger if exists phase0_islem_audit on public.ornek_hareket;
--       drop trigger if exists ornek_degismez     on public.ornek_hareket;
--       drop view  if exists public.ornek_ozet;
--       drop table if exists public.ornek_hareket;
--       drop table if exists public.ornek_baslik;
--       drop sequence if exists public.ornek_no_seq;
--       drop function if exists public.ornek_kapat(uuid);
--       drop function if exists public.ornek_degismez();
--       delete from public.moduller where kod = 'ornek';
--
--    SINIR: ornek_hareket bos DEGILSE bu blok CALISTIRILMAZ. Append-only
--    finansal veri drop ile yok edilmez; ozellik kapatma tercih edilir.
--
-- 3) YEDEKTEN DONUS: yalniz 1 ve 2 uygulanamiyorsa. Yayin oncesi yedegin
--    alindigi runbook'a yazilmis olmali.
-- ============================================================================
