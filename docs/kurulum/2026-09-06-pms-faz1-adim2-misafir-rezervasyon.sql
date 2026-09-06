-- ============================================================================
-- PMS FAZ 1 / ADIM 2 — MİSAFİRLER VE REZERVASYONLAR
-- ============================================================================
-- DURUM: ADAY. Üretime UYGULANMADI.
-- Üretim yazma dondurması yürürlükte — bkz. docs/kurulum/URETIM-YAYIN-RUNBOOK.md
--
-- ÖNKOŞUL: 2026-09-06-pms-faz1-oda-tipleri-odalar.sql uygulanmış olmalı.
--
-- KAPSAM: misafir kaydı, misafir kimlik belgesi, rezervasyon, oda ataması.
-- Folio, ödeme, fiyat/sezon motoru, oda planı ekranı ve KBS entegrasyonu YOK.
--
-- TEK TRANSACTION · TEKRAR ÇALIŞTIRILABİLİR · VERİ SİLMEZ
--
-- ---------------------------------------------------------------------------
-- KARAR 1 — REZERVASYON ODA TİPİNE YAPILIR, ODA SONRA ATANIR
-- ---------------------------------------------------------------------------
-- Misafir "Standart Oda" rezerve eder; oda numarası sonra atanır (genelde
-- check-in'de). Gerçek otel işletmesi böyle çalışır: oda 101 rezerveyken 102
-- boşsa satış durmaz.
--
-- Bu yüzden çift-rezervasyon engeli İKİ KATMANLIDIR:
--
--   Katman 1 — TİP SEVİYESİ (aşırı satış engeli)
--     Bir tarih aralığında o tipten satılan rezervasyon sayısı, o tipteki
--     aktif oda sayısını AŞAMAZ. Eşzamanlılık için oda tipi satırı
--     `for update` ile kilitlenir; iki eşzamanlı işlem aynı son odayı
--     satamaz. Bu, repodaki `bar_siparis_olustur` atomik hard-block deseninin
--     aynısıdır (2026-07-22-bar-02-rpc.sql).
--
--   Katman 2 — ODA SEVİYESİ (çakışan atama imkânsız)
--     `EXCLUDE USING gist (otel_id =, oda_id =, konaklama &&)`. Aynı odaya
--     çakışan iki aktif atama veritabanı tarafından reddedilir. Uygulama
--     kontrolü değil, yapısal imkânsızlık.
--
-- Konaklama aralığı `[)` yarı açıktır: 01–05 ile 05–09 ÇAKIŞMAZ (çıkış günü
-- yeni girişe açıktır), 01–05 ile 03–06 ÇAKIŞIR.
--
-- ---------------------------------------------------------------------------
-- KARAR 2 — KİMLİK VERİSİ AYRI TABLODA, AYRI YETKİYLE
-- ---------------------------------------------------------------------------
-- TC kimlik / pasaport numarası `pms_misafir_kimlik` tablosunda ve kendi
-- modül yetkisine (`pms_misafir_kimlik`) bağlı. Misafir listesini okumak,
-- kimlik numarasını okumak anlamına GELMEZ.
--
-- Neden: Türkiye'de konaklama tesisleri Kimlik Bildirim Sistemi için bu veriyi
-- tutmak zorunda, ama KVKK veri minimizasyonu da geçerli. Resepsiyon görür,
-- kat hizmetleri görmez. Bir sızıntıda etki alanı daralır.
--
-- ---------------------------------------------------------------------------
-- KAPSAM DIŞI (bilinçli, teknik borç olarak kayıtlı)
-- ---------------------------------------------------------------------------
-- * Tarih aralıklı oda bloğu (belirli tarihlerde arıza/tadilat) YOK. Oda
--   durumu BUGÜNÜN durumudur; gelecek tarihli müsaitlik envanteri `aktif`
--   bayrağına bakar. Tarihli blok kendi tablosuyla gelmeli.
-- * `taslak` rezervasyon envanter TUTMAZ. Opsiyonlu/tentatif tutma ayrı bir
--   karar; şimdilik yalnız onaylanmış ve sonrası envanteri işgal eder.
-- * Atanan odanın tipi rezervasyonun tipiyle AYNI OLMAK ZORUNDA DEĞİL —
--   upgrade meşrudur. Ama otel aynı olmak zorunda (bileşik FK).
-- ============================================================================

begin;

-- ============================================================================
-- 0) ÖN KOŞULLAR
-- ============================================================================
do $$
begin
  if to_regclass('public.pms_odalar') is null
     or to_regclass('public.pms_oda_tipleri') is null then
    raise exception 'PMS Adim 1 uygulanmamis: pms_odalar/pms_oda_tipleri yok';
  end if;
  if to_regprocedure('public.auth_otel_erisim(text)') is null
     or to_regprocedure('public.auth_yetki_var(text,text)') is null then
    raise exception 'Phase 0 yardimcilari yok';
  end if;
end;
$$;

-- GiST ile `=` karsilastirmasi (uuid, enum) icin gerekli. Supabase'de mevcut.
create extension if not exists btree_gist with schema extensions;

-- ============================================================================
-- 1) ENUM'LAR
-- ============================================================================
do $$
begin
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace
                 where n.nspname = 'public' and t.typname = 'pms_rezervasyon_durum') then
    create type public.pms_rezervasyon_durum as enum
      ('taslak','onaylandi','giris_yapildi','cikis_yapildi','iptal','gelmedi');
  end if;
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace
                 where n.nspname = 'public' and t.typname = 'pms_belge_tipi') then
    create type public.pms_belge_tipi as enum
      ('tc_kimlik','pasaport','surucu_belgesi','diger');
  end if;
end;
$$;

-- ============================================================================
-- 2) MİSAFİRLER — hassas olmayan kimlik dışı bilgi
-- ============================================================================
-- Otel kapsamlı: aynı kişi iki otelde konakladıysa iki kayıt olur. Bu bilinçli
-- bir tercih — otel izolasyonu güvenlik modelinin temeli ve her tesis kendi
-- misafir verisini tutar (KVKK açısından da savunulabilir).
create table if not exists public.pms_misafirler (
  id                 uuid primary key default gen_random_uuid(),
  otel_id            public.otel_id not null,
  ad                 text not null,
  soyad              text not null,
  dogum_tarihi       date,
  uyruk              text,
  telefon            text,
  eposta             text,
  notlar             text,
  aktif              boolean not null default true,
  olusturma_tarihi   timestamptz not null default now(),
  guncelleme_tarihi  timestamptz not null default now()
);

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'pms_misafirler_id_otel_key') then
    alter table public.pms_misafirler
      add constraint pms_misafirler_id_otel_key unique (id, otel_id);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'pms_misafirler_ad_bicim') then
    alter table public.pms_misafirler add constraint pms_misafirler_ad_bicim check (
      ad = btrim(ad) and ad <> '' and length(ad) <= 80
      and soyad = btrim(soyad) and soyad <> '' and length(soyad) <= 80
    );
  end if;
  -- Bos string yerine NULL: '' ile NULL ayni sey degil, filtreler bozulur.
  if not exists (select 1 from pg_constraint where conname = 'pms_misafirler_iletisim_bicim') then
    alter table public.pms_misafirler add constraint pms_misafirler_iletisim_bicim check (
      (telefon is null or (telefon = btrim(telefon) and telefon <> ''))
      and (eposta is null or (eposta = btrim(eposta) and eposta <> '' and position('@' in eposta) > 1))
      and (uyruk  is null or (uyruk  = btrim(uyruk)  and uyruk  <> ''))
    );
  end if;
  if not exists (select 1 from pg_constraint where conname = 'pms_misafirler_dogum_makul') then
    alter table public.pms_misafirler add constraint pms_misafirler_dogum_makul
      check (dogum_tarihi is null
             or (dogum_tarihi > date '1900-01-01' and dogum_tarihi <= current_date));
  end if;
end;
$$;

create index if not exists pms_misafirler_otel_aktif_idx on public.pms_misafirler (otel_id, aktif);
create index if not exists pms_misafirler_ad_idx on public.pms_misafirler (otel_id, upper(soyad), upper(ad));

-- ============================================================================
-- 3) MİSAFİR KİMLİK BELGESİ — ayrı tablo, ayrı yetki
-- ============================================================================
create table if not exists public.pms_misafir_kimlik (
  id                 uuid primary key default gen_random_uuid(),
  otel_id            public.otel_id not null,
  misafir_id         uuid not null,
  belge_tipi         public.pms_belge_tipi not null,
  belge_no           text not null,
  veren_ulke         text,
  gecerlilik_tarihi  date,
  olusturma_tarihi   timestamptz not null default now(),
  guncelleme_tarihi  timestamptz not null default now()
);

do $$
begin
  -- Bilesik FK: kimlik kaydi misafirle AYNI otelde olmak zorunda.
  if not exists (select 1 from pg_constraint where conname = 'pms_misafir_kimlik_misafir_fk') then
    alter table public.pms_misafir_kimlik
      add constraint pms_misafir_kimlik_misafir_fk
      foreign key (misafir_id, otel_id)
      references public.pms_misafirler (id, otel_id)
      on update cascade on delete cascade;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'pms_misafir_kimlik_no_bicim') then
    alter table public.pms_misafir_kimlik add constraint pms_misafir_kimlik_no_bicim
      check (belge_no = btrim(belge_no) and belge_no <> '' and length(belge_no) <= 40);
  end if;
  -- TC kimlik numarasi 11 hane rakamdir. Bicim kontrolu; algoritmik dogrulama
  -- degil (o uygulama katmaninda, cunku kural degisebilir).
  if not exists (select 1 from pg_constraint where conname = 'pms_misafir_kimlik_tc_bicim') then
    alter table public.pms_misafir_kimlik add constraint pms_misafir_kimlik_tc_bicim
      check (belge_tipi <> 'tc_kimlik' or belge_no ~ '^[1-9][0-9]{10}$');
  end if;
end;
$$;

-- Ayni belge iki misafire ait olamaz (otel icinde).
create unique index if not exists pms_misafir_kimlik_benzersiz
  on public.pms_misafir_kimlik (otel_id, belge_tipi, upper(belge_no));
create index if not exists pms_misafir_kimlik_misafir_idx
  on public.pms_misafir_kimlik (misafir_id);

-- ============================================================================
-- 4) REZERVASYONLAR — oda TİPİ seviyesinde
-- ============================================================================
create sequence if not exists public.pms_rezervasyon_no_seq;

create table if not exists public.pms_rezervasyonlar (
  id                 uuid primary key default gen_random_uuid(),
  otel_id            public.otel_id not null,
  rezervasyon_no     text not null,
  misafir_id         uuid not null,
  oda_tipi_id        uuid not null,
  giris_tarihi       date not null,
  cikis_tarihi       date not null,
  konaklama          daterange generated always as
                       (daterange(giris_tarihi, cikis_tarihi, '[)')) stored,
  yetiskin_sayisi    smallint not null default 1,
  cocuk_sayisi       smallint not null default 0,
  durum              public.pms_rezervasyon_durum not null default 'taslak',
  notlar             text,
  olusturma_tarihi   timestamptz not null default now(),
  guncelleme_tarihi  timestamptz not null default now()
);

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'pms_rezervasyonlar_id_otel_key') then
    alter table public.pms_rezervasyonlar
      add constraint pms_rezervasyonlar_id_otel_key unique (id, otel_id);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'pms_rezervasyonlar_misafir_fk') then
    alter table public.pms_rezervasyonlar
      add constraint pms_rezervasyonlar_misafir_fk
      foreign key (misafir_id, otel_id)
      references public.pms_misafirler (id, otel_id)
      on update cascade on delete restrict;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'pms_rezervasyonlar_tip_fk') then
    alter table public.pms_rezervasyonlar
      add constraint pms_rezervasyonlar_tip_fk
      foreign key (oda_tipi_id, otel_id)
      references public.pms_oda_tipleri (id, otel_id)
      on update cascade on delete restrict;
  end if;
  -- Cikis girisden SONRA olmali; sifir gecelik rezervasyon yoktur.
  if not exists (select 1 from pg_constraint where conname = 'pms_rezervasyonlar_tarih') then
    alter table public.pms_rezervasyonlar add constraint pms_rezervasyonlar_tarih check (
      isfinite(giris_tarihi) and isfinite(cikis_tarihi) and cikis_tarihi > giris_tarihi
    );
  end if;
  if not exists (select 1 from pg_constraint where conname = 'pms_rezervasyonlar_kisi') then
    alter table public.pms_rezervasyonlar add constraint pms_rezervasyonlar_kisi check (
      yetiskin_sayisi >= 1 and yetiskin_sayisi <= 20
      and cocuk_sayisi >= 0 and cocuk_sayisi <= 20
    );
  end if;
  if not exists (select 1 from pg_constraint where conname = 'pms_rezervasyonlar_no_bicim') then
    alter table public.pms_rezervasyonlar add constraint pms_rezervasyonlar_no_bicim
      check (rezervasyon_no = btrim(rezervasyon_no) and rezervasyon_no <> '');
  end if;
end;
$$;

create unique index if not exists pms_rezervasyonlar_no_uniq
  on public.pms_rezervasyonlar (otel_id, upper(rezervasyon_no));
create index if not exists pms_rezervasyonlar_tip_tarih_idx
  on public.pms_rezervasyonlar (otel_id, oda_tipi_id, durum) include (giris_tarihi, cikis_tarihi);
create index if not exists pms_rezervasyonlar_konaklama_idx
  on public.pms_rezervasyonlar using gist (konaklama);
create index if not exists pms_rezervasyonlar_misafir_idx
  on public.pms_rezervasyonlar (misafir_id);

-- ============================================================================
-- 5) ODA ATAMALARI — çakışma veritabanı tarafından imkânsız
-- ============================================================================
create table if not exists public.pms_oda_atamalari (
  id                 uuid primary key default gen_random_uuid(),
  otel_id            public.otel_id not null,
  rezervasyon_id     uuid not null,
  oda_id             uuid not null,
  baslangic          date not null,
  bitis              date not null,
  konaklama          daterange generated always as
                       (daterange(baslangic, bitis, '[)')) stored,
  aktif              boolean not null default true,
  olusturma_tarihi   timestamptz not null default now(),
  guncelleme_tarihi  timestamptz not null default now()
);

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'pms_oda_atamalari_rez_fk') then
    alter table public.pms_oda_atamalari
      add constraint pms_oda_atamalari_rez_fk
      foreign key (rezervasyon_id, otel_id)
      references public.pms_rezervasyonlar (id, otel_id)
      on update cascade on delete cascade;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'pms_oda_atamalari_oda_fk') then
    alter table public.pms_oda_atamalari
      add constraint pms_oda_atamalari_oda_fk
      foreign key (oda_id, otel_id)
      references public.pms_odalar (id, otel_id)
      on update cascade on delete restrict;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'pms_oda_atamalari_tarih') then
    alter table public.pms_oda_atamalari add constraint pms_oda_atamalari_tarih check (
      isfinite(baslangic) and isfinite(bitis) and bitis > baslangic
    );
  end if;
  -- ASIL KORUMA: ayni odaya cakisan iki AKTIF atama imkansiz.
  -- '[)' yari acik: 01-05 ile 05-09 cakismaz, 01-05 ile 03-06 cakisir.
  if not exists (select 1 from pg_constraint where conname = 'pms_oda_atamalari_cakisma') then
    alter table public.pms_oda_atamalari
      add constraint pms_oda_atamalari_cakisma
      exclude using gist (otel_id with =, oda_id with =, konaklama with &&)
      where (aktif);
  end if;
end;
$$;

create index if not exists pms_oda_atamalari_rez_idx on public.pms_oda_atamalari (rezervasyon_id);
create index if not exists pms_oda_atamalari_oda_idx on public.pms_oda_atamalari (otel_id, oda_id, aktif);

-- ============================================================================
-- 6) İŞ KURALLARI — sunucuda, tetikleyicilerle
-- ============================================================================

-- 6a) Rezervasyon numarası: boşsa üret. İstemcinin "en büyük numarayı bul,
--     bir artır" yapması yarış koşuludur; sequence tekildir.
create or replace function public.pms_rezervasyon_no_uret()
returns trigger language plpgsql
set search_path = pg_catalog, public, pg_temp as $$
begin
  if new.rezervasyon_no is null or btrim(new.rezervasyon_no) = '' then
    new.rezervasyon_no := 'R-' || to_char(coalesce(new.giris_tarihi, current_date), 'YYYY')
                       || '-' || lpad(nextval('public.pms_rezervasyon_no_seq')::text, 6, '0');
  end if;
  return new;
end;
$$;

drop trigger if exists pms_rezervasyon_no on public.pms_rezervasyonlar;
create trigger pms_rezervasyon_no before insert on public.pms_rezervasyonlar
  for each row execute function public.pms_rezervasyon_no_uret();

-- 6b) Kapasite ve AŞIRI SATIŞ engeli — atomik hard-block.
--
-- Eszamanlilik: iki islem ayni anda "9/10 satildi" gorup ikisi de eklerse 11
-- olur. Oda tipi satiri `for update` ile kilitlenerek bu engellenir; ikinci
-- islem birincisi bitene kadar bekler ve guncel sayiyi gorur. Repodaki
-- `bar_siparis_olustur` ayni deseni kullanir.
create or replace function public.pms_rezervasyon_kontrol()
returns trigger language plpgsql
set search_path = pg_catalog, public, pg_temp as $$
declare
  v_tip      record;
  v_oda      bigint;
  v_dolu     bigint;
begin
  -- Envanter tutan durumlar. 'taslak' TUTMAZ (bilincli karar).
  if new.durum not in ('onaylandi','giris_yapildi','cikis_yapildi') then
    return new;
  end if;

  -- Tip satirini KILITLE. Bu satir, bu tipin envanterinin serilestirme
  -- noktasidir; kilit transaction sonuna kadar durur.
  select * into v_tip from public.pms_oda_tipleri
   where id = new.oda_tipi_id and otel_id = new.otel_id
   for update;
  if not found then
    raise exception 'Oda tipi bulunamadi veya baska otele ait';
  end if;

  -- Kapasite: kisi sayisi tipin sinirini asamaz.
  if new.yetiskin_sayisi + new.cocuk_sayisi > v_tip.azami_kisi then
    raise exception 'Kisi sayisi oda tipi kapasitesini asiyor (% > %)',
      new.yetiskin_sayisi + new.cocuk_sayisi, v_tip.azami_kisi;
  end if;
  if new.yetiskin_sayisi > v_tip.azami_yetiskin then
    raise exception 'Yetiskin sayisi oda tipi sinirini asiyor (% > %)',
      new.yetiskin_sayisi, v_tip.azami_yetiskin;
  end if;
  if new.cocuk_sayisi > v_tip.azami_cocuk then
    raise exception 'Cocuk sayisi oda tipi sinirini asiyor (% > %)',
      new.cocuk_sayisi, v_tip.azami_cocuk;
  end if;

  -- Envanter: bu tipteki AKTIF oda sayisi.
  -- NOT: oda durumu (ariza/bloke) BUGUNUN durumudur; gelecek tarihli musaitlik
  -- icin tarih arali'kli oda blogu gerekir ve o ayri bir adimdir.
  select count(*) into v_oda from public.pms_odalar
   where otel_id = new.otel_id and oda_tipi_id = new.oda_tipi_id and aktif;

  -- Cakisan aktif rezervasyonlar (kendisi haric).
  select count(*) into v_dolu from public.pms_rezervasyonlar r
   where r.otel_id = new.otel_id
     and r.oda_tipi_id = new.oda_tipi_id
     and r.durum in ('onaylandi','giris_yapildi','cikis_yapildi')
     and r.id <> new.id
     and r.konaklama && daterange(new.giris_tarihi, new.cikis_tarihi, '[)');

  if v_dolu >= v_oda then
    raise exception 'Asiri satis: % tipinde % oda var, secilen tarihlerde % rezervasyon dolu',
      v_tip.kod, v_oda, v_dolu;
  end if;

  return new;
end;
$$;

drop trigger if exists pms_rezervasyon_kontrol on public.pms_rezervasyonlar;
create trigger pms_rezervasyon_kontrol before insert or update on public.pms_rezervasyonlar
  for each row execute function public.pms_rezervasyon_kontrol();

-- 6c) Atama kuralları.
--
-- Denetimin HANGI kismi ne zaman calisir:
--   HER ZAMAN (pasif satirlarda da) : rezervasyon var mi, tarihler rezervasyonun
--                                     araligi icinde mi.
--   YALNIZ AKTIFKEN                 : rezervasyon iptal degil, oda aktif.
--
-- Ayrim zorunlu: 6e iptal edilen bir rezervasyonun atamalarini PASIFE ALIR;
-- o guncelleme sirasinda "iptal rezervasyona atama yapilamaz" kurali calissaydi
-- kendi temizligimizi engellerdi. Ayni sekilde pasife alinan bir odanin mevcut
-- atamasi da kapatilabilmeli.
--
-- Tarih denetimi pasif satirlarda da calisir: onceki surumde `if not new.aktif
-- then return new` erken cikisi yuzunden rezervasyon tarihlerinin tamamen
-- disinda pasif satirlar eklenebiliyordu (oz-incelemede olculdu).
create or replace function public.pms_atama_kontrol()
returns trigger language plpgsql
set search_path = pg_catalog, public, pg_temp as $$
declare v_rez record; v_oda record;
begin
  select * into v_rez from public.pms_rezervasyonlar
   where id = new.rezervasyon_id and otel_id = new.otel_id;
  if not found then
    raise exception 'Rezervasyon bulunamadi veya baska otele ait';
  end if;

  if new.baslangic < v_rez.giris_tarihi or new.bitis > v_rez.cikis_tarihi then
    raise exception 'Atama rezervasyon tarihlerinin disina tasiyor (% - % / rezervasyon % - %)',
      new.baslangic, new.bitis, v_rez.giris_tarihi, v_rez.cikis_tarihi;
  end if;

  if new.aktif then
    if v_rez.durum in ('iptal','gelmedi') then
      raise exception 'Iptal edilmis rezervasyona oda atanamaz (durum: %)', v_rez.durum;
    end if;

    select * into v_oda from public.pms_odalar
     where id = new.oda_id and otel_id = new.otel_id;
    if not found then
      raise exception 'Oda bulunamadi veya baska otele ait';
    end if;
    if not v_oda.aktif then
      raise exception 'Pasif odaya misafir atanamaz (oda %)', v_oda.oda_no;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists pms_atama_kontrol on public.pms_oda_atamalari;
create trigger pms_atama_kontrol before insert or update on public.pms_oda_atamalari
  for each row execute function public.pms_atama_kontrol();

-- 6e) İPTAL, ODAYI SERBEST BIRAKIR
--
-- Bu olmadan: rezervasyon iptal edilir, atamasi `aktif=true` kalir, exclusion
-- kisiti odayi hala dolu sayar ve o tarihlere YENI atama REDDEDILIR. Oda,
-- iptal edilmis bir rezervasyon icin olu kalir; kimse hata gormez, sadece
-- satilamaz. Oz-incelemede olculdu.
create or replace function public.pms_iptal_atama_serbest()
returns trigger language plpgsql
set search_path = pg_catalog, public, pg_temp as $$
begin
  update public.pms_oda_atamalari
     set aktif = false
   where rezervasyon_id = new.id and otel_id = new.otel_id and aktif;
  return null;
end;
$$;

drop trigger if exists pms_iptal_atama_serbest on public.pms_rezervasyonlar;
create trigger pms_iptal_atama_serbest after update of durum on public.pms_rezervasyonlar
  for each row
  when (new.durum in ('iptal','gelmedi') and old.durum is distinct from new.durum)
  execute function public.pms_iptal_atama_serbest();

-- 6f) ENVANTER, SATILANIN ALTINA DÜŞEMEZ
--
-- Asiri satis kontrolu yalniz REZERVASYON tarafinda calisiyordu. ODA tarafindan
-- envanteri kisan bir islem (pasife alma, silme, baska tipe tasima) denetimsizdi:
-- tek odali bir tipte onayli rezervasyon varken oda pasife alinabiliyor ve
-- envanter 0'a duserken rezervasyon ayakta kaliyordu. Oz-incelemede olculdu.
--
-- Yontem: degisiklikten SONRAKI oda sayisini hesapla, sonra o tipte gelecege
-- uzanan aktif rezervasyonlarin HERHANGI BIR GUNDEKI en yuksek cakisma sayisini
-- bul. En yuksek cakisma yeni envanteri asiyorsa reddet.
-- (Azami cakisma daima bir rezervasyonun GIRIS gununde olusur; o yuzden aday
--  noktalar olarak giris tarihleri yeterlidir.)
create or replace function public.pms_oda_envanter_kontrol()
returns trigger language plpgsql
set search_path = pg_catalog, public, pg_temp as $$
declare
  v_eski   record;
  v_yeni_sayi bigint;
  v_azami  bigint;
begin
  v_eski := old;

  -- Envanteri KISMAYAN degisiklikler ilgilendirmiyor.
  if tg_op = 'UPDATE'
     and new.aktif and old.aktif
     and new.oda_tipi_id = old.oda_tipi_id
     and new.otel_id = old.otel_id then
    return new;
  end if;
  if tg_op = 'UPDATE' and not old.aktif then
    return new;   -- zaten sayilmiyordu
  end if;

  -- Degisiklikten sonra bu tipte kac aktif oda kalir?
  select count(*) into v_yeni_sayi
    from public.pms_odalar o
   where o.otel_id = v_eski.otel_id
     and o.oda_tipi_id = v_eski.oda_tipi_id
     and o.aktif
     and o.id <> v_eski.id;

  if tg_op = 'UPDATE' and new.aktif and new.oda_tipi_id = old.oda_tipi_id then
    v_yeni_sayi := v_yeni_sayi + 1;
  end if;

  -- Gelecege uzanan aktif rezervasyonlarda azami es zamanli cakisma.
  select coalesce(max(x.c), 0) into v_azami from (
    select count(*) as c
      from public.pms_rezervasyonlar a
      join public.pms_rezervasyonlar b
        on b.otel_id = a.otel_id
       and b.oda_tipi_id = a.oda_tipi_id
       and b.durum in ('onaylandi','giris_yapildi','cikis_yapildi')
       and b.konaklama @> a.giris_tarihi
     where a.otel_id = v_eski.otel_id
       and a.oda_tipi_id = v_eski.oda_tipi_id
       and a.durum in ('onaylandi','giris_yapildi','cikis_yapildi')
       and a.cikis_tarihi > current_date
     group by a.id
  ) x;

  if v_azami > v_yeni_sayi then
    raise exception
      'Envanter satilanin altina duser: bu tipte % oda kalir ama gelecekte en fazla % es zamanli rezervasyon var (oda %)',
      v_yeni_sayi, v_azami, v_eski.oda_no;
  end if;

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

drop trigger if exists pms_oda_envanter_kontrol on public.pms_odalar;
create trigger pms_oda_envanter_kontrol before update or delete on public.pms_odalar
  for each row execute function public.pms_oda_envanter_kontrol();

-- 6d) Güncelleme damgası + Phase 0 otel değişmezliği
do $$
declare v_tablo text;
begin
  foreach v_tablo in array array['pms_misafirler','pms_misafir_kimlik',
                                 'pms_rezervasyonlar','pms_oda_atamalari'] loop
    execute format('drop trigger if exists pms_guncelleme on public.%I', v_tablo);
    execute format('create trigger pms_guncelleme before update on public.%I
                    for each row execute function public.pms_guncelleme_damgala()', v_tablo);

    if to_regprocedure('phase0_private.otel_degismez()') is not null then
      execute format('drop trigger if exists phase0_otel_degismez on public.%I', v_tablo);
      execute format('create trigger phase0_otel_degismez before update of otel_id
                      on public.%I for each row
                      execute function phase0_private.otel_degismez()', v_tablo);
    end if;
  end loop;
end;
$$;

-- ============================================================================
-- 7) YETKİ MODÜLLERİ
-- ============================================================================
insert into public.moduller (kod, ad, kategori, sira, aktif) values
  ('pms_misafir',        'Ön Büro — Misafirler',          'onburo', 45, true),
  ('pms_misafir_kimlik', 'Ön Büro — Misafir Kimlik Bilgisi','onburo', 46, true),
  ('pms_rezervasyon',    'Ön Büro — Rezervasyonlar',      'onburo', 47, true)
on conflict (kod) do nothing;

-- Fail-closed varsayilan: yalniz yetki yonetimine 'tam' erisimi olan rollere
-- verilir. DIKKAT: pms_misafir_kimlik BILEREK DAGITILMAZ — kimlik verisi
-- erisimi acik bir karar olmali, otomatik miras degil.
insert into public.yetki_matrisi (rol_id, modul_id, yetki)
select ym.rol_id, m.id, 'tam'::public.yetki_seviye
from public.yetki_matrisi ym
join public.moduller yy on yy.id = ym.modul_id and yy.kod = 'yetki_yonetimi'
cross join public.moduller m
where ym.yetki = 'tam' and m.kod in ('pms_misafir','pms_rezervasyon')
on conflict (rol_id, modul_id) do nothing;

-- ============================================================================
-- 8) RLS — Phase 0 yaklaşımı: set-tabanlı, tek STABLE fonksiyon çağrısı
-- ============================================================================
do $$
declare v record;
begin
  for v in select * from (values
      ('pms_misafirler',      'pms_misafir'),
      ('pms_misafir_kimlik',  'pms_misafir_kimlik'),
      ('pms_rezervasyonlar',  'pms_rezervasyon'),
      ('pms_oda_atamalari',   'pms_rezervasyon')
    ) s(tablo, modul) loop

    execute format('alter table public.%I enable row level security', v.tablo);
    execute format('revoke all on public.%I from public, anon', v.tablo);
    execute format('grant select, insert, update, delete on public.%I to authenticated', v.tablo);
    execute format('grant all on public.%I to service_role', v.tablo);

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

    execute format('drop policy if exists %I on public.%I', v.tablo || '_delete', v.tablo);
    execute format($f$create policy %I on public.%I for delete to authenticated
      using (public.auth_yetki_var(%L,'tam') is true
             and public.auth_otel_erisim(otel_id::text) is true)$f$,
      v.tablo || '_delete', v.tablo, v.modul);

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
-- 9) DOĞRULAMA — migration kendi iddialarını sınar
-- ============================================================================
do $$
declare v_tablo text; v_rel regclass;
begin
  foreach v_tablo in array array['pms_misafirler','pms_misafir_kimlik',
                                 'pms_rezervasyonlar','pms_oda_atamalari'] loop
    v_rel := to_regclass('public.' || v_tablo);
    if v_rel is null then raise exception 'Tablo olusmadi: %', v_tablo; end if;

    if has_table_privilege('anon', v_rel, 'SELECT,INSERT,UPDATE,DELETE')
       or has_any_column_privilege('anon', v_rel, 'SELECT,INSERT,UPDATE') then
      raise exception 'anon erisebiliyor: %', v_tablo;
    end if;
    if not (select relrowsecurity from pg_class where oid = v_rel) then
      raise exception 'RLS kapali: %', v_tablo;
    end if;
    if not exists (select 1 from pg_policy p where p.polrelid = v_rel
                   and p.polname = 'phase0_otel_kisit' and not p.polpermissive) then
      raise exception 'Kisitlayici otel tabani yok: %', v_tablo;
    end if;
    if (select count(*) from pg_policy where polrelid = v_rel and polpermissive) <> 4 then
      raise exception 'Beklenen 4 kalici politika yok: %', v_tablo;
    end if;
  end loop;

  -- Cakisma engeli GERCEKTEN exclusion kisiti mi? Benzersiz index YETMEZ:
  -- cakisma esitlik degil, aralik ortusmesidir.
  if not exists (select 1 from pg_constraint
                 where conname = 'pms_oda_atamalari_cakisma' and contype = 'x') then
    raise exception 'Oda cakisma engeli exclusion kisiti degil';
  end if;

  -- Capraz otel engelleri bilesik FK olmali.
  foreach v_tablo in array array['pms_misafir_kimlik_misafir_fk','pms_rezervasyonlar_misafir_fk',
                                 'pms_rezervasyonlar_tip_fk','pms_oda_atamalari_rez_fk',
                                 'pms_oda_atamalari_oda_fk'] loop
    if not exists (select 1 from pg_constraint
                   where conname = v_tablo and contype = 'f' and array_length(conkey,1) = 2) then
      raise exception 'Capraz otel engeli bilesik FK degil: %', v_tablo;
    end if;
  end loop;

  if (select count(*) from public.moduller
      where kod in ('pms_misafir','pms_misafir_kimlik','pms_rezervasyon')) <> 3 then
    raise exception 'PMS Adim 2 modulleri kaydedilmedi';
  end if;

  -- Is kurali tetikleyicileri yerinde mi? Bunlar oz-incelemede bulunan
  -- bosluklarin karsiligi; biri dusserse sessizce veri bozulur.
  foreach v_tablo in array array['pms_rezervasyon_kontrol','pms_atama_kontrol',
                                 'pms_iptal_atama_serbest','pms_oda_envanter_kontrol'] loop
    if not exists (select 1 from pg_trigger where tgname = v_tablo and not tgisinternal) then
      raise exception 'Is kurali tetikleyicisi yok: %', v_tablo;
    end if;
  end loop;

  -- Kimlik yetkisi OTOMATIK dagitilmamis olmali: acik karar gerektirir.
  if exists (select 1 from public.yetki_matrisi ym
             join public.moduller m on m.id = ym.modul_id
             where m.kod = 'pms_misafir_kimlik' and ym.yetki <> 'yok') then
    raise exception 'pms_misafir_kimlik yetkisi otomatik dagitilmis - bu acik karar olmali';
  end if;
end;
$$;

commit;

notify pgrst, 'reload schema';

-- ============================================================================
-- GERİ ALMA
-- ============================================================================
-- Tek transaction: uygulama sirasindaki hata kendini geri alir.
-- Commit sonrasi (VERI SILER - once yedek):
--
-- begin;
--   drop table if exists public.pms_oda_atamalari;
--   drop table if exists public.pms_rezervasyonlar;
--   drop table if exists public.pms_misafir_kimlik;
--   drop table if exists public.pms_misafirler;
--   drop sequence if exists public.pms_rezervasyon_no_seq;
--   drop function if exists public.pms_rezervasyon_kontrol();
--   drop function if exists public.pms_atama_kontrol();
--   drop function if exists public.pms_rezervasyon_no_uret();
--   drop type if exists public.pms_rezervasyon_durum;
--   drop type if exists public.pms_belge_tipi;
--   delete from public.yetki_matrisi where modul_id in
--     (select id from public.moduller
--      where kod in ('pms_misafir','pms_misafir_kimlik','pms_rezervasyon'));
--   delete from public.moduller
--    where kod in ('pms_misafir','pms_misafir_kimlik','pms_rezervasyon');
-- commit;
--
-- Veri KAYBETMEDEN geri cekme (tercih edilen):
--   update public.moduller set aktif=false
--    where kod in ('pms_misafir','pms_misafir_kimlik','pms_rezervasyon');
