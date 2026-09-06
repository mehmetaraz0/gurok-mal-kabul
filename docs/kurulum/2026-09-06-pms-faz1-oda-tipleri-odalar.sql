-- ============================================================================
-- PMS FAZ 1 / ADIM 1 — ODA TİPLERİ VE ODALAR
-- ============================================================================
-- DURUM: ADAY. Üretime UYGULANMADI.
-- Üretim yazma dondurması yürürlükte — bkz. docs/kurulum/URETIM-YAYIN-RUNBOOK.md
--
-- KAPSAM: yalnızca oda tipi ve oda ana verisi. Misafir, rezervasyon,
-- müsaitlik, oda planı, check-in/out, folio ve ödeme BU DOSYADA YOK.
--
-- TEK TRANSACTION: hata hâlinde tamamı geri döner, kısmi durum oluşmaz.
-- TEKRAR ÇALIŞTIRILABİLİR: mevcut nesneleri düşürmez, veriyi silmez.
--
-- ---------------------------------------------------------------------------
-- İSİMLENDİRME KARARI
-- ---------------------------------------------------------------------------
-- Görev tanımı `pms_room_types` / `pms_rooms` öneriyordu ama "mevcut repository
-- naming convention farklıysa ona uy" diyordu. Bu depo baştan sona Türkçe
-- (kullanicilar, mal_kabuller, stok_hareketleri; kolonlar aktif,
-- olusturma_tarihi). Bu yüzden Türkçe adlar + PMS gruplaması için `pms_` öneki:
--   pms_oda_tipleri, pms_odalar
--
-- ---------------------------------------------------------------------------
-- DURUM MODELİ KARARI
-- ---------------------------------------------------------------------------
-- İKİ enum kuruldu, üçüncüsü BİLEREK kurulmadı:
--   kullanim_durumu : bos | dolu | bloke | ariza
--   temizlik_durumu : temiz | kirli | temizleniyor | kontrol_edildi
--
-- Görev tanımı üçüncü bir bakim_durumu enum'unu "gerekiyorsa" diye niteleyip
-- "gereksiz enum çoğaltma" uyarısı yapıyordu. AVAILABLE/MAINTENANCE/
-- OUT_OF_SERVICE değerlerinin ikisi kullanim_durumu ile örtüşüyor:
-- OUT_OF_SERVICE = 'ariza', MAINTENANCE = 'bloke'. Üçüncü enum, aynı gerçeği
-- iki yerde tutup tutarsızlık üretirdi. Ayrı bir bakım iş akışı (iş emri,
-- teknisyen, tarih aralığı) gerektiğinde o kendi tablosuyla gelmeli.
--
-- REZERVE durumu oda üstünde TUTULMAZ: rezervasyon/atama verisinden
-- hesaplanacak. 'bloke' operasyonel blokedir (grup tutma, tadilat), rezervasyon
-- değildir.
--
-- ---------------------------------------------------------------------------
-- ÇAPRAZ OTEL ENGELİ — asıl tasarım kararı
-- ---------------------------------------------------------------------------
-- 810 oda tipi + 811 oda bağlantısı VERİTABANI tarafından reddedilir.
-- Yöntem: bileşik yabancı anahtar.
--   pms_oda_tipleri  (id, otel_id) benzersiz
--   pms_odalar       (oda_tipi_id, otel_id) -> pms_oda_tipleri (id, otel_id)
-- Böylece odanın otel_id'si tipin otel_id'siyle AYNI olmak zorunda; trigger,
-- uygulama kontrolü veya RLS'e gerek kalmadan yapısal olarak imkânsız.
-- ============================================================================

begin;

-- ============================================================================
-- 0) ÖN KOŞULLAR — beklenmeyen bir şema üzerinde çalışmayı reddet
-- ============================================================================
do $$
begin
  if to_regtype('public.otel_id') is null then
    raise exception 'public.otel_id enum bulunamadi: yanlis veritabani';
  end if;
  if to_regclass('public.moduller') is null or to_regclass('public.roller') is null
     or to_regclass('public.yetki_matrisi') is null then
    raise exception 'Yetki motoru tablolari yok: yanlis veritabani';
  end if;
  if to_regprocedure('public.auth_otel_erisim(text)') is null
     or to_regprocedure('public.auth_yetki_var(text,text)') is null then
    raise exception 'Phase 0 yardimcilari yok: once sertlestirme uygulanmali';
  end if;
end;
$$;

-- ============================================================================
-- 1) ENUM'LAR
-- ============================================================================
do $$
begin
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace
                 where n.nspname = 'public' and t.typname = 'pms_kullanim_durumu') then
    create type public.pms_kullanim_durumu as enum ('bos','dolu','bloke','ariza');
  end if;
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace
                 where n.nspname = 'public' and t.typname = 'pms_temizlik_durumu') then
    create type public.pms_temizlik_durumu as enum ('temiz','kirli','temizleniyor','kontrol_edildi');
  end if;
end;
$$;

-- ============================================================================
-- 2) ODA TİPLERİ
-- ============================================================================
create table if not exists public.pms_oda_tipleri (
  id                 uuid primary key default gen_random_uuid(),
  otel_id            public.otel_id not null,
  kod                text    not null,
  ad                 text    not null,
  aciklama           text,
  azami_kisi         smallint not null,
  azami_yetiskin     smallint not null,
  azami_cocuk        smallint not null default 0,
  aktif              boolean not null default true,
  olusturma_tarihi   timestamptz not null default now(),
  guncelleme_tarihi  timestamptz not null default now()
);

do $$
begin
  -- Bilesik FK'nin hedefi. Capraz otel engelinin dayanagi budur.
  if not exists (select 1 from pg_constraint where conname = 'pms_oda_tipleri_id_otel_key') then
    alter table public.pms_oda_tipleri
      add constraint pms_oda_tipleri_id_otel_key unique (id, otel_id);
  end if;
  -- Kod ve ad NORMALLESTIRILMIS olmali. `btrim(kod) <> ''` yalnizca BOS olmayi
  -- engeller, KIRPILMIS olmayi degil: ' STD' gecerdi ve otelde iki ayri "STD"
  -- oda tipi olusurdu. Ekran .trim() yapiyor ama API'ye dogrudan giden bir
  -- istemci yapmaz; kural veritabaninda olmali.
  if not exists (select 1 from pg_constraint where conname = 'pms_oda_tipleri_kod_bicim') then
    alter table public.pms_oda_tipleri add constraint pms_oda_tipleri_kod_bicim
      check (kod = btrim(kod) and kod <> '' and length(kod) <= 20);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'pms_oda_tipleri_ad_bicim') then
    alter table public.pms_oda_tipleri add constraint pms_oda_tipleri_ad_bicim
      check (ad = btrim(ad) and ad <> '');
  end if;

  -- Eski (harf duyarli) benzersizlik varsa birakilir; yerine buyuk/kucuk harf
  -- duyarsiz benzersiz index gelir. 'STD' ve 'std' AYNI oda tipidir.
  if exists (select 1 from pg_constraint where conname = 'pms_oda_tipleri_otel_kod_key') then
    alter table public.pms_oda_tipleri drop constraint pms_oda_tipleri_otel_kod_key;
  end if;
  if exists (select 1 from pg_constraint where conname = 'pms_oda_tipleri_kod_bos_degil') then
    alter table public.pms_oda_tipleri drop constraint pms_oda_tipleri_kod_bos_degil;
  end if;
  if exists (select 1 from pg_constraint where conname = 'pms_oda_tipleri_ad_bos_degil') then
    alter table public.pms_oda_tipleri drop constraint pms_oda_tipleri_ad_bos_degil;
  end if;
  -- Kapasite tutarliligi: yetiskin ve cocuk ayri ayri toplam kapasiteyi asamaz.
  -- (Toplamlari asabilir: 2 yetiskin + 2 cocuk kapasiteli 3 kisilik oda mesrudur.)
  if not exists (select 1 from pg_constraint where conname = 'pms_oda_tipleri_kapasite') then
    alter table public.pms_oda_tipleri add constraint pms_oda_tipleri_kapasite check (
      azami_kisi between 1 and 20
      and azami_yetiskin between 1 and azami_kisi
      and azami_cocuk between 0 and azami_kisi
    );
  end if;
end;
$$;

create unique index if not exists pms_oda_tipleri_otel_kod_uniq
  on public.pms_oda_tipleri (otel_id, upper(kod));

create index if not exists pms_oda_tipleri_otel_aktif_idx
  on public.pms_oda_tipleri (otel_id, aktif);

-- ============================================================================
-- 3) ODALAR
-- ============================================================================
create table if not exists public.pms_odalar (
  id                 uuid primary key default gen_random_uuid(),
  otel_id            public.otel_id not null,
  oda_tipi_id        uuid    not null,
  oda_no             text    not null,
  kat                text,
  blok               text,
  kullanim_durumu    public.pms_kullanim_durumu not null default 'bos',
  temizlik_durumu    public.pms_temizlik_durumu not null default 'kirli',
  aciklama           text,
  aktif              boolean not null default true,
  olusturma_tarihi   timestamptz not null default now(),
  guncelleme_tarihi  timestamptz not null default now()
);

do $$
begin
  -- CAPRAZ OTEL ENGELI: odanin oteli, tipin oteliyle ayni olmak ZORUNDA.
  -- on delete restrict: kullanimdaki bir oda tipi silinemez.
  if not exists (select 1 from pg_constraint where conname = 'pms_odalar_tip_ayni_otel_fk') then
    alter table public.pms_odalar
      add constraint pms_odalar_tip_ayni_otel_fk
      foreign key (oda_tipi_id, otel_id)
      references public.pms_oda_tipleri (id, otel_id)
      on update cascade on delete restrict;
  end if;
  -- Oda numarasi otel icinde benzersiz; FARKLI otellerde ayni numara mesrudur.
  -- Benzersizlik asagida buyuk/kucuk harf duyarsiz INDEX ile kurulur: "12A" ve
  -- "12a" ayni odadir. Eski harf duyarli kisit varsa birakilir.
  if exists (select 1 from pg_constraint where conname = 'pms_odalar_otel_oda_no_key') then
    alter table public.pms_odalar drop constraint pms_odalar_otel_oda_no_key;
  end if;
  if exists (select 1 from pg_constraint where conname = 'pms_odalar_oda_no_bos_degil') then
    alter table public.pms_odalar drop constraint pms_odalar_oda_no_bos_degil;
  end if;
  -- Ileride rezervasyon/atama tablolari icin bilesik FK hedefi.
  if not exists (select 1 from pg_constraint where conname = 'pms_odalar_id_otel_key') then
    alter table public.pms_odalar
      add constraint pms_odalar_id_otel_key unique (id, otel_id);
  end if;
  -- Kirpilmis olma zorunlulugu: ' 101' ile '101' ayri oda sayilmasin.
  if not exists (select 1 from pg_constraint where conname = 'pms_odalar_oda_no_bicim') then
    alter table public.pms_odalar add constraint pms_odalar_oda_no_bicim
      check (oda_no = btrim(oda_no) and oda_no <> '' and length(oda_no) <= 20);
  end if;
  -- Kat ve blok da kirpilmis olmali; ' 1' ile '1' ayri kat filtresi uretirdi.
  if not exists (select 1 from pg_constraint where conname = 'pms_odalar_kat_blok_bicim') then
    alter table public.pms_odalar add constraint pms_odalar_kat_blok_bicim check (
      (kat  is null or (kat  = btrim(kat)  and kat  <> '' and length(kat)  <= 10))
      and (blok is null or (blok = btrim(blok) and blok <> '' and length(blok) <= 30))
    );
  end if;
end;
$$;

create unique index if not exists pms_odalar_otel_oda_no_uniq
  on public.pms_odalar (otel_id, upper(oda_no));

create index if not exists pms_odalar_otel_aktif_idx    on public.pms_odalar (otel_id, aktif);
create index if not exists pms_odalar_tip_idx           on public.pms_odalar (oda_tipi_id);
create index if not exists pms_odalar_otel_durum_idx    on public.pms_odalar (otel_id, kullanim_durumu, temizlik_durumu);

-- ============================================================================
-- 4) GÜNCELLEME DAMGASI
-- ============================================================================
-- SECURITY INVOKER: ayricalik yukseltmez, yalnizca kolonu doldurur.
create or replace function public.pms_guncelleme_damgala()
returns trigger language plpgsql
set search_path = pg_catalog, public, pg_temp as $$
begin
  new.guncelleme_tarihi := now();
  return new;
end;
$$;

drop trigger if exists pms_oda_tipleri_guncelleme on public.pms_oda_tipleri;
create trigger pms_oda_tipleri_guncelleme before update on public.pms_oda_tipleri
  for each row execute function public.pms_guncelleme_damgala();

drop trigger if exists pms_odalar_guncelleme on public.pms_odalar;
create trigger pms_odalar_guncelleme before update on public.pms_odalar
  for each row execute function public.pms_guncelleme_damgala();

-- Phase 0'in otel degismezligi yeni tablolara da uygulanir: bir kaydin oteli
-- sonradan degistirilemez. Fonksiyon Phase 0'dan AYNEN kullanilir, kopyalanmaz.
do $$
begin
  if to_regprocedure('phase0_private.otel_degismez()') is not null then
    execute 'drop trigger if exists phase0_otel_degismez on public.pms_oda_tipleri';
    execute 'create trigger phase0_otel_degismez before update of otel_id
             on public.pms_oda_tipleri for each row
             execute function phase0_private.otel_degismez()';
    execute 'drop trigger if exists phase0_otel_degismez on public.pms_odalar';
    execute 'create trigger phase0_otel_degismez before update of otel_id
             on public.pms_odalar for each row
             execute function phase0_private.otel_degismez()';
  else
    raise notice 'phase0_private.otel_degismez() yok - otel degismezlik tetikleyicisi ATLANDI';
  end if;
end;
$$;

-- ============================================================================
-- 5) YETKİ MODÜLLERİ — paralel ikinci yetki sistemi KURULMAZ
-- ============================================================================
-- Mevcut moduller + yetki_matrisi + auth_yetki_var motoru kullanilir.
insert into public.moduller (kod, ad, kategori, sira, aktif) values
  ('pms_oda_tipi', 'Ön Büro — Oda Tipleri', 'onburo', 43, true),
  ('pms_oda',      'Ön Büro — Odalar',      'onburo', 44, true)
on conflict (kod) do nothing;

-- Yeni modul VARSAYILAN OLARAK KAPALI dogar (yetki_matrisi'nde satir yoksa
-- auth_yetki_var false doner). Yalnizca yetki yonetimine zaten 'tam' erisimi
-- olan rollere 'tam' verilir; digerleri yetki-yonetimi.html uzerinden acilir.
-- Bu bilincli bir fail-closed varsayilandir.
insert into public.yetki_matrisi (rol_id, modul_id, yetki)
select ym.rol_id, m.id, 'tam'::public.yetki_seviye
from public.yetki_matrisi ym
join public.moduller yy on yy.id = ym.modul_id and yy.kod = 'yetki_yonetimi'
cross join public.moduller m
where ym.yetki = 'tam' and m.kod in ('pms_oda_tipi','pms_oda')
on conflict (rol_id, modul_id) do nothing;

-- ============================================================================
-- 6) RLS — Phase 0 yaklasimi: set-tabanli, tek STABLE fonksiyon cagrisi
-- ============================================================================
-- Satir basina dinamik SQL veya jsonb serilestirme YOK; maliyet sinifi mevcut
-- 2026-08-10 politikalariyla ayni.
alter table public.pms_oda_tipleri enable row level security;
alter table public.pms_odalar      enable row level security;

-- anon hicbir sekilde erisemez. PUBLIC'ten de alinir: tablo bazli revoke tek
-- basina yetmez, PUBLIC uzerinden miras kalabilir.
revoke all on public.pms_oda_tipleri from public, anon;
revoke all on public.pms_odalar      from public, anon;
grant select, insert, update, delete on public.pms_oda_tipleri to authenticated;
grant select, insert, update, delete on public.pms_odalar      to authenticated;
grant all on public.pms_oda_tipleri to service_role;
grant all on public.pms_odalar      to service_role;

do $$
declare v record;
begin
  for v in select * from (values
      ('pms_oda_tipleri', 'pms_oda_tipi'),
      ('pms_odalar',      'pms_oda')
    ) s(tablo, modul) loop

    -- KALICI (permissive) politikalar: yetki VE otel kapsami.
    -- `is true` zorunlu: NULL sonuc REDDEDILIR (fail-closed).
    execute format('drop policy if exists %I on public.%I', v.tablo || '_select', v.tablo);
    execute format($f$create policy %I on public.%I for select to authenticated
      using (public.auth_yetki_var(%L,'goruntule') is true
             and public.auth_otel_erisim(otel_id::text) is true)$f$,
      v.tablo || '_select', v.tablo, v.modul);

    execute format('drop policy if exists %I on public.%I', v.tablo || '_insert', v.tablo);
    execute format($f$create policy %I on public.%I for insert to authenticated
      with check (public.auth_yetki_var(%L,'kayit') is true
                  and public.auth_otel_erisim(otel_id::text) is true)$f$,
      v.tablo || '_insert', v.tablo, v.modul);

    execute format('drop policy if exists %I on public.%I', v.tablo || '_update', v.tablo);
    execute format($f$create policy %I on public.%I for update to authenticated
      using (public.auth_yetki_var(%L,'kayit') is true
             and public.auth_otel_erisim(otel_id::text) is true)
      with check (public.auth_yetki_var(%L,'kayit') is true
                  and public.auth_otel_erisim(otel_id::text) is true)$f$,
      v.tablo || '_update', v.tablo, v.modul, v.modul);

    -- DELETE en yuksek seviyeyi ister. Ekranlar pasife alma (aktif=false)
    -- kullanir; kalici silme yonetici islemidir.
    execute format('drop policy if exists %I on public.%I', v.tablo || '_delete', v.tablo);
    execute format($f$create policy %I on public.%I for delete to authenticated
      using (public.auth_yetki_var(%L,'tam') is true
             and public.auth_otel_erisim(otel_id::text) is true)$f$,
      v.tablo || '_delete', v.tablo, v.modul);

    -- KISITLAYICI taban: Phase 0'in kalibi. Kalici politikalar OR ile
    -- birlesir; ileride eklenecek tek bir kalici politika otel kapsamini
    -- sessizce atlayabilir. Kisitlayici politika AND ile baglanir ve
    -- hicbiri onu gecemez.
    execute format('drop policy if exists phase0_otel_kisit on public.%I', v.tablo);
    execute format($f$create policy phase0_otel_kisit on public.%I
      as restrictive for all to authenticated
      using ((case when otel_id is null then public.auth_tum_oteller()
                   else public.auth_otel_erisim(otel_id::text) end) is true)
      with check ((case when otel_id is null then public.auth_tum_oteller()
                        else public.auth_otel_erisim(otel_id::text) end) is true)$f$,
      v.tablo);
  end loop;
end;
$$;

-- ============================================================================
-- 7) DOĞRULAMA — migration kendi iddialarini sinar
-- ============================================================================
do $$
declare v_tablo text; v_rel regclass;
begin
  foreach v_tablo in array array['pms_oda_tipleri','pms_odalar'] loop
    v_rel := to_regclass('public.' || v_tablo);

    if has_table_privilege('anon', v_rel, 'SELECT,INSERT,UPDATE,DELETE')
       or has_any_column_privilege('anon', v_rel, 'SELECT,INSERT,UPDATE') then
      raise exception 'anon erisebiliyor: %', v_tablo;
    end if;

    if not (select relrowsecurity from pg_class where oid = v_rel) then
      raise exception 'RLS kapali: %', v_tablo;
    end if;

    if not exists (select 1 from pg_policy p
                   where p.polrelid = v_rel and p.polname = 'phase0_otel_kisit'
                     and not p.polpermissive) then
      raise exception 'Kisitlayici otel tabani yok: %', v_tablo;
    end if;

    if (select count(*) from pg_policy where polrelid = v_rel and polpermissive) <> 4 then
      raise exception 'Beklenen 4 kalici politika yok: %', v_tablo;
    end if;
  end loop;

  -- Capraz otel engeli GERCEKTEN bilesik FK ile mi kurulu?
  if not exists (
    select 1 from pg_constraint
    where conname = 'pms_odalar_tip_ayni_otel_fk' and contype = 'f'
      and array_length(conkey, 1) = 2) then
    raise exception 'Capraz otel engeli bilesik FK degil - tek kolonlu FK yetersiz';
  end if;

  if (select count(*) from public.moduller
      where kod in ('pms_oda_tipi','pms_oda')) <> 2 then
    raise exception 'PMS modulleri kaydedilmedi (2 satir bekleniyordu)';
  end if;

  -- Benzersizlik buyuk/kucuk harf DUYARSIZ olmali. Duyarli bir kisit geri
  -- gelirse 'STD' ile 'std' iki ayri oda tipi olur ve fark edilmez.
  foreach v_tablo in array array['pms_oda_tipleri_otel_kod_uniq',
                                 'pms_odalar_otel_oda_no_uniq'] loop
    if not exists (select 1 from pg_class where relname = v_tablo and relkind = 'i') then
      raise exception 'Harf duyarsiz benzersiz index yok: %', v_tablo;
    end if;
  end loop;

  -- Kirpma kurallari yerinde mi?
  foreach v_tablo in array array['pms_oda_tipleri_kod_bicim','pms_oda_tipleri_ad_bicim',
                                 'pms_odalar_oda_no_bicim','pms_odalar_kat_blok_bicim'] loop
    if not exists (select 1 from pg_constraint where conname = v_tablo) then
      raise exception 'Bicim kisiti yok: %', v_tablo;
    end if;
  end loop;
end;
$$;

commit;

notify pgrst, 'reload schema';

-- ============================================================================
-- TEST (uygulamadan sonra, SALT-OKUMA)
-- ============================================================================
-- select tablo, politika, kalici, komut from (
--   select c.relname as tablo, p.polname as politika, p.polpermissive as kalici,
--          p.polcmd::text as komut
--   from pg_policy p join pg_class c on c.oid=p.polrelid
--   join pg_namespace n on n.oid=c.relnamespace
--   where n.nspname='public' and c.relname like 'pms\_%') x order by tablo, politika;
--
-- Otomatik sozlesme testleri: node scripts/pms-faz1-testleri.mjs
--
-- ============================================================================
-- GERİ ALMA
-- ============================================================================
-- Migration tek transaction: uygulama sirasindaki hata kendini geri alir.
-- Commit sonrasi geri alma (VERI SILER - once yedek alin):
--
-- begin;
--   drop table if exists public.pms_odalar;
--   drop table if exists public.pms_oda_tipleri;
--   drop function if exists public.pms_guncelleme_damgala();
--   drop type if exists public.pms_kullanim_durumu;
--   drop type if exists public.pms_temizlik_durumu;
--   delete from public.yetki_matrisi where modul_id in
--     (select id from public.moduller where kod in ('pms_oda_tipi','pms_oda'));
--   delete from public.moduller where kod in ('pms_oda_tipi','pms_oda');
-- commit;
--
-- Veri KAYBETMEDEN geri cekmek icin tercih edilen yol: modulleri kapatmak.
--   update public.moduller set aktif=false where kod in ('pms_oda_tipi','pms_oda');
-- Bu, auth_yetki_var uzerinden hem UI'yi hem RLS'i kapatir; tablolar durur.
