-- ============================================================================
-- PMS FAZ 1 / ADIM 3 — ODA PLANI, CHECK-IN / CHECK-OUT
-- ============================================================================
-- DURUM: ADAY. Üretime UYGULANMADI.
-- Üretim yazma dondurması yürürlükte — bkz. docs/kurulum/URETIM-YAYIN-RUNBOOK.md
--
-- ÖNKOŞUL: Adım 1 (oda tipleri/odalar) ve Adım 2 (misafir/rezervasyon/atama)
-- uygulanmış olmalı.
--
-- KAPSAM: check-in / check-out durum makinesi, oda durumu tutarlılığı,
-- oda planı ekranının veri katmanı. Folio, ödeme, fiyat/sezon motoru YOK.
--
-- TEK TRANSACTION · TEKRAR ÇALIŞTIRILABİLİR · VERİ SİLMEZ
--
-- ---------------------------------------------------------------------------
-- KARAR 1 — STATE MAKİNESİ SUNUCUDA, TÜM YAZMA YOLLARINA UYGULAR
-- ---------------------------------------------------------------------------
-- Check-in / check-out yalnızca RPC ile yapılır, AMA istemci doğrudan
-- REST/DML ile makineyi bypass edememeli. Yöntem: SECURITY INVOKER RPC +
-- BEFORE geçiş tetikleyicileri (geçiş matrisi, donmuş kolonlar) + AFTER
-- constraint tetikleyicileri (tablolar arası tutarlılık değişmezleri).
--
-- Geçiş matrisi (HER yazara uygulanır, RPC dahil):
--   taslak        -> onaylandi | iptal
--   onaylandi     -> giris_yapildi | iptal | gelmedi
--   giris_yapildi -> cikis_yapildi
--   cikis_yapildi / iptal / gelmedi -> terminal, değiştirilemez
--
-- Donmuş veri: giris/cikis zaman ve yapan kolonları bir kez yazılır, sonra
-- değiştirilemez. Konaklama sürerken (giris_yapildi/cikis_yapildi) misafir,
-- oda tipi ve tarihler değiştirilemez.
--
-- Tablolar arası değişmezler (constraint trigger, DEFERRABLE INITIALLY
-- IMMEDIATE — RPC ara hâllerde yazabilmek için kendi transaction'ında
-- DEFERRED'e çeker; doğrudan REST tek istek = tek transaction olduğundan
-- ara hâli commit edemez ve IMMEDIATE denetimine takılır):
-- GÜNCEL KONAKLAMA TANIMI (tüm değişmezlerde ortak):
--     atama.aktif = true  VE  rezervasyon.durum = 'giris_yapildi'
-- Tarih KULLANILMAZ. Planlanan çıkışın geçmiş olması konaklamayı bitirmez;
-- misafir çıkış yapana kadar oda fiziksel olarak doludur. Normal çıkıştan
-- sonra atama aktif kalır ama rezervasyon 'cikis_yapildi' olduğu için artık
-- güncel doluluk sayılmaz.
-- (Tarih kısıtları veri bütünlüğü için yerinde durur: aralık geçerliliği,
--  rezervasyon aralığına uyum, exclusion. Yalnız "şu anda konaklama sürüyor
--  mu" sorusunda tarih kullanılmaz.)
--
--   O1: oda 'dolu'  -> içeride konaklayan (giris_yapildi) bir rezervasyon OLMALI
--   O2: oda doludan çıkarken -> misafir içerideyse reddedilir; çıkış RPC ile
--   R1: rez 'giris_yapildi' -> damgalar dolu + aktif ataması DOLU odayı
--       göstermeli
--   R2: rez giristen cikisa dönerken -> aktif atamalarının hiçbiri DOLU
--       odayı göstermemeli
--   A1: aktif atama -> rezervasyon onaylandi/giris/cikis olmalı
--   A2: aktif atama + misafir içeride (giris_yapildi) -> oda DOLU olmalı
--   A3: misafir odadayken (giris_yapildi) atama pasifleştirilemez
--
-- Neden INVOKER yeterli: bypass için istemcinin "oda dolu + atama aktif +
-- rez giris_yapildi" üçlüsünü tutarlı kurması gerekir. PostgREST'te her istek
-- ayrı transaction'dır; üç yazma tek istekte yapılamaz. Ara hâllerde IMMEDIATE
-- constraint tetikleyicisi reddeder. RPC dışından yalnızca GEÇERLİ ara
-- durumlara yazılabilir; geçersiz state yapısal olarak imkânsızdır.
-- (Doğrudan psql/SQL erişimi threat model dışıdır; süperuser her şeyi
-- aşabilir, bu PostgreSQL'in doğasıdır.)
--
-- ---------------------------------------------------------------------------
-- KARAR 2 — NORMAL CHECK-OUT ATAMAYI PASİFLEŞTİRMEZ
-- ---------------------------------------------------------------------------
-- pms_oda_atamalari geçmiş konaklama ilişkisidir. Normal çıkışta atama
-- AKTİF/geçerli geçmiş kaydı olarak kalır: [giris, cikis) aralığı yarı açık
-- olduğundan çıkış günü başlayan yeni atamayla zaten çakışmaz (exclusion
-- kisiti bunu garanti eder).
-- Yalnız iptal / gelmedi (konaklama gerçekleşmedi) atamaları pasifleşir —
-- bu Adım 2'nin pms_iptal_atama_serbest tetikleyicisidir, burada değişmedi.
-- Erken check-out: atama SİLMEK yerine ileride effective bitiş tarihi
-- kapatılabilecek şekilde mimari korunmuştur; şu an erken çıkışta kalan
-- geceler için oda yeniden satılamaz (bilinçli sınırlama, aşağıda).
--
-- ---------------------------------------------------------------------------
-- KARAR 3 — KİLİT SIRASI (deterministik, deadlock'suz)
-- ---------------------------------------------------------------------------
-- Her iki RPC de aynı sırayla kilitler:
--   rezervasyon FOR UPDATE -> (atama FOR UPDATE) -> oda FOR UPDATE
--   -> kilitli hâlde şartları YENİDEN doğrula -> yaz.
-- Oda kilidi altında kullanim/temizlik durumları TEKRAR okunur; ilk kontrol
-- ile yazma arasında durum değişmişse reddedilir.
--
-- ---------------------------------------------------------------------------
-- KARAR 4 — HOUSEKEEPING: KİRLİ ODAYA CHECK-İN YOK
-- ---------------------------------------------------------------------------
-- Check-in yalnız temizlik_durumu in ('temiz','kontrol_edildi') odalara
-- yapılır; 'kirli' ve 'temizleniyor' reddedilir. Kural BEFORE oda geçiş
-- tetikleyicisinde TÜM yazma yollarına uygulanır (RPC tek başına yeterli
-- değildir). Override iş akışı bilinçli olarak YOK — istenirse ayrı, yüksek
-- yetkili bir adımla gelir.
--
-- ---------------------------------------------------------------------------
-- KARAR 5 — SAAT DİLİMİ
-- ---------------------------------------------------------------------------
-- Projede otel bazlı saat dilimi alanı YOK. "Bugün" Europe/Istanbul
-- varsayımıyla hesaplanır ve tek noktadan (pms_bugun) verilir; ileride otel
-- saat dilimi alanı geldiğinde yalnız bu fonksiyon değişir. Türkiye tek saat
-- dilimi kullandığı için tüm mevcut işletmeler için doğru varsayımdır.
--
-- ---------------------------------------------------------------------------
-- BİLİNÇLİ SINIRLAMALAR
-- ---------------------------------------------------------------------------
-- * Erken check-out: çıkış yapılır ama atama aktif kalır; kalan gecelerde
--   oda exclusion nedeniyle yeniden satılamaz. Effective bitiş kapatma
--   özelliği ileride eklenecek (mimari hazır).
-- * Gecikmiş check-out DESTEKLENİR: resepsiyon planlanan çıkış gününü
--   kaçırsa bile (bugün > cikis_tarihi) giris_yapildi rezervasyonun aktif
--   ataması hâlâ güncel konaklama kaydıdır ve check-out kabul edilir.
--   - cikis_zamani/cikis_yapan GERÇEK işlem anını ve aktörünü taşır
--     (planlanan tarih değil),
--   - planlanan stay aralığı (giris_tarihi/cikis_tarihi) sessizce
--     DEĞİŞTİRİLMEZ,
--   - atama geçmiş konaklama kaydı olarak aktif kalır.
--   Atama seçimi "bugünü kapsıyor mu" ile değil "bu rezervasyonun güncel
--   aktif ataması mı" ile yapılır; 0 veya >1 aktif atama açık tutarsızlık
--   hatasıdır (sessizce ilki seçilmez).
-- * 'bloke'/'ariza' odalara check-in yok; 'dolu' oda bloke/ariza yapılamaz.
-- ============================================================================

begin;

-- ============================================================================
-- 0) ÖN KOŞULLAR
-- ============================================================================
do $$
begin
  if to_regclass('public.pms_rezervasyonlar') is null
     or to_regclass('public.pms_oda_atamalari') is null
     or to_regclass('public.pms_odalar') is null then
    raise exception 'PMS Adim 1/2 uygulanmamis: pms tablolari yok';
  end if;
  if to_regprocedure('public.auth_yetki_var(text,text)') is null
     or to_regprocedure('public.auth_otel_erisim(text)') is null then
    raise exception 'Phase 0 yardimcilari yok';
  end if;
end;
$$;

-- ============================================================================
-- 1) REZERVASYONA CHECK-IN/OUT DAMGALARI
-- ============================================================================
alter table public.pms_rezervasyonlar
  add column if not exists giris_zamani timestamptz,
  add column if not exists cikis_zamani timestamptz,
  add column if not exists giris_yapan  uuid,
  add column if not exists cikis_yapan  uuid;

-- ============================================================================
-- 2) SAAT DİLİMİ — tek noktadan "bugün"
-- ============================================================================
-- p_otel şimdilik kullanılmıyor: otel saat dilimi alanı geldiğinde
--   (now() at time zone coalesce(otel_saati, 'Europe/Istanbul'))
-- hâline dönüşecek; çağıran kod değişmeyecek.
create or replace function public.pms_bugun(p_otel public.otel_id default null)
returns date
language sql stable
set search_path = pg_catalog
as $$
  select (now() at time zone 'Europe/Istanbul')::date;
$$;

-- ============================================================================
-- 3) REZERVASYON GEÇİŞ MAKİNESİ — BEFORE, tüm yazarlara
-- ============================================================================
create or replace function public.pms_rezervasyon_gecis()
returns trigger language plpgsql
set search_path = pg_catalog, public, pg_temp as $$
begin
  -- 3a0) INSERT: rezervasyon giris/cikis durumunda AÇILAMAZ; giriş yalnız
  --      onaylanmış rezervasyonun RPC üzerinden yapılır.
  if tg_op = 'INSERT' then
    if new.durum in ('giris_yapildi','cikis_yapildi') then
      raise exception 'Yeni rezervasyon % durumunda acilamaz', new.durum;
    end if;
    return new;
  end if;

  -- 3a) Geçiş matrisi
  if old.durum is distinct from new.durum then
    if old.durum = 'taslak' then
      if new.durum not in ('onaylandi','iptal') then
        raise exception 'Gecis yok: taslak -> %', new.durum;
      end if;
    elsif old.durum = 'onaylandi' then
      if new.durum not in ('giris_yapildi','iptal','gelmedi') then
        raise exception 'Gecis yok: onaylandi -> %', new.durum;
      end if;
    elsif old.durum = 'giris_yapildi' then
      if new.durum <> 'cikis_yapildi' then
        raise exception 'Gecis yok: giris_yapildi -> % (yalniz cikis_yapildi)',
          new.durum;
      end if;
    else
      raise exception 'Terminal durum (% ) degistirilemez', old.durum;
    end if;
  end if;

  -- 3b) Damgalar donmuş: bir kez yazılır, sonra hiç değişmez.
  if old.giris_zamani is not null
     and new.giris_zamani is distinct from old.giris_zamani then
    raise exception 'giris_zamani sonradan degistirilemez';
  end if;
  if old.giris_yapan is not null
     and new.giris_yapan is distinct from old.giris_yapan then
    raise exception 'giris_yapan sonradan degistirilemez';
  end if;
  if old.cikis_zamani is not null
     and new.cikis_zamani is distinct from old.cikis_zamani then
    raise exception 'cikis_zamani sonradan degistirilemez';
  end if;
  if old.cikis_yapan is not null
     and new.cikis_yapan is distinct from old.cikis_yapan then
    raise exception 'cikis_yapan sonradan degistirilemez';
  end if;

  -- 3c) Konaklama sürerken (veya bittiğinde) çekirdek alanlar donmuş.
  if new.durum in ('giris_yapildi','cikis_yapildi') then
    if new.misafir_id    is distinct from old.misafir_id
       or new.oda_tipi_id is distinct from old.oda_tipi_id
       or new.giris_tarihi is distinct from old.giris_tarihi
       or new.cikis_tarihi is distinct from old.cikis_tarihi then
      raise exception 'Konaklama surerken misafir/tip/tarihler degistirilemez';
    end if;
  end if;

  -- 3d) Check-in/out geçişleri damgasız olamaz (RPC bunları birlikte yazar;
  --     doğrudan REST damgasız geçiş yapamaz).
  if old.durum is distinct from new.durum then
    if new.durum = 'giris_yapildi'
       and (new.giris_zamani is null or new.giris_yapan is null) then
      raise exception 'giris_yapildi gecisi damgasiz olamaz (giris_zamani/giris_yapan gerekli)';
    end if;
    if new.durum = 'cikis_yapildi'
       and (new.cikis_zamani is null or new.cikis_yapan is null) then
      raise exception 'cikis_yapildi gecisi damgasiz olamaz (cikis_zamani/cikis_yapan gerekli)';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists pms_rezervasyon_gecis on public.pms_rezervasyonlar;
create trigger pms_rezervasyon_gecis before insert or update on public.pms_rezervasyonlar
  for each row execute function public.pms_rezervasyon_gecis();

-- ============================================================================
-- 4) ODA GEÇİŞ MAKİNESİ — BEFORE, tüm yazarlara
-- ============================================================================
create or replace function public.pms_oda_gecis()
returns trigger language plpgsql
set search_path = pg_catalog, public, pg_temp as $$
begin
  if tg_op = 'INSERT' and new.kullanim_durumu = 'dolu' then
    -- INSERT'te doğrudan dolu oda kurulamaz; doluluk yalnız check-in RPC ile.
    raise exception 'Oda % dolu isaretlenerek acilamaz; doluluk check-in ile olur',
      new.oda_no;
  end if;
  if tg_op = 'UPDATE'
     and old.kullanim_durumu is distinct from new.kullanim_durumu then
    -- Dolu odaya misafir dışı geçiş olamaz.
    if new.kullanim_durumu = 'dolu' then
      if old.kullanim_durumu <> 'bos' then
        raise exception 'Dolu''ya gecis yalniz bos odadan olur (% -> %)',
          old.kullanim_durumu, new.kullanim_durumu;
      end if;
      -- Housekeeping kuralı: check-in yalnız temiz odaya.
      if new.temizlik_durumu not in ('temiz','kontrol_edildi') then
        raise exception 'Kirli/temizleniyor oda dolu isaretlenemez (temizlik: %)',
          new.temizlik_durumu;
      end if;
    end if;
    -- Misafir odadayken oda operasyonel dışına çekilemez.
    if old.kullanim_durumu = 'dolu'
       and new.kullanim_durumu in ('bloke','ariza') then
      raise exception 'Misafir odada iken oda % yapilamaz; once cikis',
        new.kullanim_durumu;
    end if;
    -- Çıkan oda kirli doğar (kat hizmeti akışı bunu temizler).
    if old.kullanim_durumu = 'dolu' and new.kullanim_durumu = 'bos'
       and new.temizlik_durumu <> 'kirli' then
      raise exception 'Cikan oda kirli isaretlenmeli (temizlik: %)',
        new.temizlik_durumu;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists pms_oda_gecis on public.pms_odalar;
create trigger pms_oda_gecis before insert or update on public.pms_odalar
  for each row execute function public.pms_oda_gecis();

-- ============================================================================
-- 5) ATAMA DEĞİŞİM KISITI — BEFORE UPDATE
-- ============================================================================
-- Konaklama sürerken (giris_yapildi) atamanın odası ve tarihleri donmuştur.
-- (Pasifleştirme ayrıca aşağıdaki A3 değişmeziyle denetlenir; iptal/no-show
-- akışı rezervasyonu önce iptal ettiği için buraya takılmaz.)
create or replace function public.pms_atama_degisim_kontrol()
returns trigger language plpgsql
set search_path = pg_catalog, public, pg_temp as $$
declare v_durum public.pms_rezervasyon_durum;
begin
  select r.durum into v_durum
    from public.pms_rezervasyonlar r
   where r.id = new.rezervasyon_id and r.otel_id = new.otel_id;
  if v_durum = 'giris_yapildi'
     and (new.oda_id    is distinct from old.oda_id
          or new.baslangic is distinct from old.baslangic
          or new.bitis     is distinct from old.bitis) then
    raise exception 'Konaklama surerken atamanin odasi/tarihleri degistirilemez';
  end if;
  return new;
end;
$$;

drop trigger if exists pms_atama_degisim_kontrol on public.pms_oda_atamalari;
create trigger pms_atama_degisim_kontrol before update on public.pms_oda_atamalari
  for each row execute function public.pms_atama_degisim_kontrol();

-- ============================================================================
-- 6) TABLOLAR ARASI TUTARLILIK — constraint tetikleyicileri
-- ============================================================================
-- DEFERRABLE INITIALLY IMMEDIATE: doğrudan REST yazması tek istekli
-- transaction olduğu için hemen reddedilir (net hata); RPC ara hâlleri
-- yazabilmek için transaction başında DEFERRED'e çeker.

-- 6a) Oda değişmezleri (O1, O2)
create or replace function public.pms_tutarlilik_oda()
returns trigger language plpgsql
set search_path = pg_catalog, public, pg_temp as $$
begin
  -- GÜNCEL KONAKLAMA TANIMI (O1, O2 ortak):
  --   atama.aktif = true  VE  rezervasyon.durum = 'giris_yapildi'
  --
  -- Planlanan bitiş tarihinin geçmiş olması konaklamayı BİTİRMEZ: misafir
  -- çıkış yapana kadar oda fiziksel olarak doludur. Önceki sürüm
  -- `a.bitis >= pms_bugun()` kullanıyordu ve gecikmiş konaklamada oda satırını
  -- tamamen donduruyordu — kat hizmetleri temizlik durumunu güncelleyemiyordu.
  -- B1 bu varsayımı pms_check_out'tan kaldırmıştı; değişmez katmanında kalmıştı.
  --
  -- Sadece "şu anda konaklama sürüyor mu" sorusunda tarih kullanılmaz.
  -- Tarih kısıtları (aralık geçerliliği, çakışma) veri bütünlüğü için durur.

  -- O1: dolu oda -> içeride konaklayan bir rezervasyon olmalı.
  if new.kullanim_durumu = 'dolu' then
    if not exists (
      select 1
        from public.pms_oda_atamalari a
        join public.pms_rezervasyonlar r
          on r.id = a.rezervasyon_id and r.otel_id = a.otel_id
       where a.oda_id = new.id and a.otel_id = new.otel_id and a.aktif
         and r.durum = 'giris_yapildi') then
      raise exception 'Oda % dolu ama icerde konaklayan rezervasyon yok',
        new.oda_no;
    end if;
  end if;
  -- O2: doludan çıkarken misafir hâlâ içerideyse reddet (yalnız UPDATE'te
  -- anlamlı; INSERT'te old yok). Tarih filtresi YOK: gecikmiş konaklamada da
  -- doğrudan `dolu -> bos` yazarak check-out state makinesi atlanamaz.
  if tg_op = 'UPDATE' and old.kullanim_durumu = 'dolu'
     and new.kullanim_durumu <> 'dolu' then
    if exists (
      select 1
        from public.pms_oda_atamalari a
        join public.pms_rezervasyonlar r
          on r.id = a.rezervasyon_id and r.otel_id = a.otel_id
       where a.oda_id = new.id and a.otel_id = new.otel_id and a.aktif
         and r.durum = 'giris_yapildi') then
      raise exception 'Oda % misafir odada iken bosalamaz; once pms_check_out',
        new.oda_no;
    end if;
  end if;
  return null;
end;
$$;

drop trigger if exists pms_tutarlilik_oda on public.pms_odalar;
create constraint trigger pms_tutarlilik_oda
  after insert or update on public.pms_odalar
  deferrable initially immediate
  for each row execute function public.pms_tutarlilik_oda();

-- 6b) Rezervasyon değişmezleri (R1, R2)
create or replace function public.pms_tutarlilik_rezervasyon()
returns trigger language plpgsql
set search_path = pg_catalog, public, pg_temp as $$
begin
  -- GÜNCEL ATAMA TANIMI (R1, R2 ortak): atama.aktif = true VE aynı rezervasyon.
  -- Tarih filtresi YOK — planlanan çıkış geçmiş olsa da bağ kopmaz. Önceki
  -- sürümde gecikmiş konaklamada rezervasyonun NOT alanı bile güncellenemiyordu.
  --
  -- Konaklama boyunca donmuş çekirdek alanlar (giris/cikis tarihi, oda tipi,
  -- misafir) bu değişiklikten ETKİLENMEZ: onları BEFORE geçiş tetikleyicisi
  -- (pms_rezervasyon_gecis) koruyor, bu değişmez değil.

  -- R1: misafir içeride -> güncel aktif ataması DOLU odayı göstermeli.
  if new.durum = 'giris_yapildi' then
    if not exists (
      select 1
        from public.pms_oda_atamalari a
        join public.pms_odalar o
          on o.id = a.oda_id and o.otel_id = a.otel_id
       where a.rezervasyon_id = new.id and a.otel_id = new.otel_id and a.aktif
         and o.kullanim_durumu = 'dolu') then
      raise exception 'Rezervasyon giris_yapildi ama dolu odada aktif atamasi yok';
    end if;
  end if;
  -- R2: çıkışta hiçbir aktif atama dolu odayı göstermemeli.
  if tg_op = 'UPDATE' and old.durum = 'giris_yapildi'
     and new.durum = 'cikis_yapildi' then
    -- (yalnız UPDATE; INSERT'te bu geçiş BEFORE tetikleyicide zaten yasak)
    if exists (
      select 1
        from public.pms_oda_atamalari a
        join public.pms_odalar o
          on o.id = a.oda_id and o.otel_id = a.otel_id
       where a.rezervasyon_id = new.id and a.otel_id = new.otel_id and a.aktif
         and o.kullanim_durumu = 'dolu') then
      raise exception 'Cikis yapildi ama oda hala dolu; once oda bosalmali (pms_check_out)';
    end if;
  end if;
  return null;
end;
$$;

drop trigger if exists pms_tutarlilik_rezervasyon on public.pms_rezervasyonlar;
create constraint trigger pms_tutarlilik_rezervasyon
  after insert or update on public.pms_rezervasyonlar
  deferrable initially immediate
  for each row execute function public.pms_tutarlilik_rezervasyon();

-- 6c) Atama değişmezleri (A1, A2, A3)
create or replace function public.pms_tutarlilik_atama()
returns trigger language plpgsql
set search_path = pg_catalog, public, pg_temp as $$
-- v_bugun kaldirildi: A2 artik tarih kullanmiyor, guncel konaklama
-- rezervasyon durumundan turetiliyor.
declare v_durum public.pms_rezervasyon_durum;
begin
  select r.durum into v_durum
    from public.pms_rezervasyonlar r
   where r.id = new.rezervasyon_id and r.otel_id = new.otel_id;

  -- A1: aktif atama yalnız konaklama izni olan durumlarda.
  if new.aktif and coalesce(v_durum,'iptal') not in
     ('onaylandi','giris_yapildi','cikis_yapildi') then
    raise exception 'Aktif atama yalniz onaylandi/giris/cikis rezervasyonunda olabilir (durum: %)',
      coalesce(v_durum::text,'(yok)');
  end if;

  -- A2: GÜNCEL konaklama ataması = aktif VE rezervasyon giris_yapildi.
  -- Tarih kapısı YOK: planlanan bitiş geçmiş olsa da misafir hâlâ içeride.
  -- Normal çıkıştan SONRA rezervasyon 'cikis_yapildi' olur; atama aktif kalsa
  -- bile bu koşul artık sağlanmaz, yani geçmiş kayıt güncel doluluk sayılmaz.
  if new.aktif and v_durum = 'giris_yapildi' then
    if not exists (
      select 1 from public.pms_odalar o
       where o.id = new.oda_id and o.otel_id = new.otel_id
         and o.kullanim_durumu = 'dolu') then
      raise exception 'Misafir odada ama atamasi dolu olmayan odayi gosteriyor';
    end if;
  end if;

  -- A3: misafir odadayken atama pasifleştirilemez.
  if tg_op = 'UPDATE' and old.aktif and not new.aktif
     and v_durum = 'giris_yapildi' then
    raise exception 'Misafir odada iken atama pasiflestirilemez; once cikis';
  end if;

  return null;
end;
$$;

drop trigger if exists pms_tutarlilik_atama on public.pms_oda_atamalari;
create constraint trigger pms_tutarlilik_atama
  after insert or update on public.pms_oda_atamalari
  deferrable initially immediate
  for each row execute function public.pms_tutarlilik_atama();

-- ============================================================================
-- 7) CHECK-IN / CHECK-OUT RPC — SECURITY INVOKER
-- ============================================================================
-- INVOKER: RLS devrede kalır; otel kapsamı ve modul yetkisi otomatik uygulanır.
-- RPC içindeki auth_yetki_var kontrolü yalnızca NET hata içindir; asıl
-- güvence RLS'tir.

-- 7a) CHECK-IN
create or replace function public.pms_check_in(
  p_rezervasyon_id uuid,
  p_oda_id         uuid default null
)
returns uuid
language plpgsql
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_rez     public.pms_rezervasyonlar%rowtype;
  v_oda     public.pms_odalar%rowtype;
  v_atama   public.pms_oda_atamalari%rowtype;
  v_bugun   date;
  v_kirpik  uuid;
begin
  if public.auth_yetki_var('pms_rezervasyon','kayit') is not true then
    raise exception 'Check-in icin rezervasyon kayit yetkisi gerekli';
  end if;

  -- Kilit sırası 1: rezervasyon. RLS bulunamayan satırı zaten gizler.
  select * into v_rez
    from public.pms_rezervasyonlar
   where id = p_rezervasyon_id
   for update;
  if not found then
    raise exception 'Rezervasyon bulunamadi veya erisim yok';
  end if;

  v_bugun := public.pms_bugun(v_rez.otel_id);

  if v_rez.durum <> 'onaylandi' then
    raise exception 'Check-in yalniz onaylandi rezervasyonuna yapilir (durum: %)', v_rez.durum;
  end if;
  if v_bugun < v_rez.giris_tarihi then
    raise exception 'Rezervasyon giris tarihi bugunden ileride (%)', v_rez.giris_tarihi;
  end if;
  if v_bugun >= v_rez.cikis_tarihi then
    raise exception 'Rezervasyon cikis tarihi gecti (%)', v_rez.cikis_tarihi;
  end if;

  -- Ara hâlleri yazabilmek için tutarlılık denetimlerini commit'e bırak.
  set constraints pms_tutarlilik_oda, pms_tutarlilik_rezervasyon,
                  pms_tutarlilik_atama deferred;

  -- Kilit sırası 2: mevcut güncel atama varsa onu kilitle ve odayı ondan al.
  select * into v_atama
    from public.pms_oda_atamalari a
   where a.rezervasyon_id = v_rez.id and a.otel_id = v_rez.otel_id and a.aktif
     and a.bitis >= v_bugun
   order by a.id
   for update;
  if found then
    v_kirpik := v_atama.oda_id;
    if p_oda_id is not null and p_oda_id <> v_kirpik then
      raise exception 'Rezervasyona bagli baska oda atamasi var; oda secilemez';
    end if;
  else
    if p_oda_id is null then
      raise exception 'Oda secilmedi: rezervasyona bagli guncel oda atamasi yok';
    end if;
    v_kirpik := p_oda_id;
  end if;

  -- Kilit sırası 3: oda. Kilit altında şartları YENİDEN doğrula.
  select * into v_oda
    from public.pms_odalar
   where id = v_kirpik and otel_id = v_rez.otel_id
   for update;
  if not found then
    raise exception 'Oda bulunamadi veya baska otele ait';
  end if;
  if not v_oda.aktif then
    raise exception 'Pasif odaya check-in yapilamaz (oda %)', v_oda.oda_no;
  end if;
  if v_oda.kullanim_durumu <> 'bos' then
    raise exception 'Oda % bos degil (durum: %), check-in reddedildi',
      v_oda.oda_no, v_oda.kullanim_durumu;
  end if;
  if v_oda.temizlik_durumu not in ('temiz','kontrol_edildi') then
    raise exception 'Oda % kirli/temizleniyor, check-in reddedildi (temizlik: %)',
      v_oda.oda_no, v_oda.temizlik_durumu;
  end if;

  -- Güncel atama yoksa tam konaklama aralığına atama aç; çakışma exclusion
  -- kisitiyla veritabanınca reddedilir.
  if v_atama.id is null then
    insert into public.pms_oda_atamalari (otel_id, rezervasyon_id, oda_id,
                                          baslangic, bitis)
    values (v_rez.otel_id, v_rez.id, v_oda.id, v_rez.giris_tarihi, v_rez.cikis_tarihi);
  end if;

  update public.pms_odalar
     set kullanim_durumu = 'dolu'
   where id = v_oda.id;

  update public.pms_rezervasyonlar
     set durum = 'giris_yapildi',
         giris_zamani = now(),
         giris_yapan  = auth.uid()
   where id = v_rez.id;

  return v_oda.id;
end;
$$;

-- 7b) CHECK-OUT
create or replace function public.pms_check_out(p_rezervasyon_id uuid)
returns uuid
language plpgsql
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_rez    public.pms_rezervasyonlar%rowtype;
  v_oda    public.pms_odalar%rowtype;
  v_oda_id uuid;
  v_sayi   int := 0;
begin
  if public.auth_yetki_var('pms_rezervasyon','kayit') is not true then
    raise exception 'Check-out icin rezervasyon kayit yetkisi gerekli';
  end if;

  -- Kilit sırası 1: rezervasyon.
  select * into v_rez
    from public.pms_rezervasyonlar
   where id = p_rezervasyon_id
   for update;
  if not found then
    raise exception 'Rezervasyon bulunamadi veya erisim yok';
  end if;

  if v_rez.durum <> 'giris_yapildi' then
    raise exception 'Check-out yalniz giris_yapildi rezervasyonuna yapilir (durum: %)',
      v_rez.durum;
  end if;

  set constraints pms_tutarlilik_oda, pms_tutarlilik_rezervasyon,
                  pms_tutarlilik_atama deferred;

  -- Kilit sırası 2: rezervasyonun AKTİF konaklama ataması.
  -- "Bugünü kapsıyor mu" ŞARTI YOK: planlanan çıkış tarihi geçmiş olsa bile
  -- (resepsiyon çıkışı unuttu) atama bu rezervasyonun güncel konaklama
  -- kaydıdır ve çıkış yapılabilir. cikis_zamani gerçek işlem anını taşır;
  -- planlanan stay aralığı SESSİZCE DEĞİŞTİRİLMEZ; atama geçmiş kayıt
  -- olarak aktif kalır.
  select a.oda_id into v_oda_id
    from public.pms_oda_atamalari a
   where a.rezervasyon_id = v_rez.id and a.otel_id = v_rez.otel_id and a.aktif
   order by a.oda_id
   limit 1
   for update;
  if not found then
    raise exception 'Aktif oda atamasi yok; tutarsiz durum, cikis reddedildi';
  end if;

  -- Kilit altında yeniden doğrula: checked-in rezervasyonun TAM BİR aktif
  -- ataması olmalı. 0 ve >1, veri bozulmasıdır; sessizce ilki SEÇİLMEZ.
  -- (Kilit, bu sayım ile ilk kontrol arasına giren değişiklikleri de yakalar.)
  select count(*) into v_sayi
    from public.pms_oda_atamalari a
   where a.rezervasyon_id = v_rez.id and a.otel_id = v_rez.otel_id and a.aktif;
  if v_sayi <> 1 then
    raise exception 'Check-in rezervasyonun % aktif oda atamasi var; tutarsiz durum (1 bekleniyordu)',
      v_sayi;
  end if;

  -- Kilit sırası 3: oda; kilit altında durumu yeniden doğrula.
  select * into v_oda
    from public.pms_odalar
   where id = v_oda_id and otel_id = v_rez.otel_id
   for update;
  if not found then
    raise exception 'Atamadaki oda bulunamadi (oda_id: %)', v_oda_id;
  end if;
  if v_oda.kullanim_durumu <> 'dolu' then
    raise exception 'Oda % dolu degil (durum: %), tutarsiz durum',
      v_oda.oda_no, v_oda.kullanim_durumu;
  end if;
  update public.pms_odalar
     set kullanim_durumu = 'bos',
         temizlik_durumu = 'kirli'
   where id = v_oda.id;

  update public.pms_rezervasyonlar
     set durum = 'cikis_yapildi',
         cikis_zamani = now(),
         cikis_yapan  = auth.uid()
   where id = v_rez.id;

  return v_rez.id;
end;
$$;

-- RPC'ler yalnız authenticated'a açık. anon/PUBLIC kapalı.
revoke execute on function public.pms_check_in(uuid, uuid) from public, anon;
revoke execute on function public.pms_check_out(uuid)        from public, anon;
grant  execute on function public.pms_check_in(uuid, uuid) to authenticated, service_role;
grant  execute on function public.pms_check_out(uuid)        to authenticated, service_role;

-- ============================================================================
-- 8) DENETİM İZİ — Phase 0 generic tetikleyicisi, MİNİMUM kapsam
-- ============================================================================
-- Karar (F3): PMS'de her CRUD değil, İŞ GEÇİŞLERİ denetlenir:
--   - rezervasyon yaratma + durum geçişleri (check-in/check-out dahil:
--     damgalar rezervasyon satırında taşındığından UPDATE olayı izi verir)
--   - oda ataması yaratma / pasifleştirme / değişiklik
-- Oda listesindeki sıradan açıklama/temizlik değişiklikleri denetlenmez.
--
-- Yeni paralel audit sistemi KURULMADI: Phase 0'ın generic
-- phase0_private.islem_audit() tetikleyicisi aynen bağlanır. Fonksiyon
-- SECURITY DEFINER + aynı transaction'da yazar; hotel_id (satırdaki
-- otel_id), actor (auth.uid()), actor_role, event_type (TG_OP),
-- entity_type (tablo adı), entity_id (satır id) ve transaction_id
-- (pg_current_xact_id) taşır. Satır İÇERİĞİNİ kopyalamaz — misafir kişisel
-- verisi denetim izine sızamaz. Kişisel veri taşıyan pms_misafirler ve
-- pms_misafir_kimlik bilinçli olarak kapsam DIŞIDIR.
--
-- pms_misafirler ve pms_misafir_kimlik'e DELETE tetikleyicisi bağlanmaz:
-- PMS'de silme ekranları pasife alma (aktif=false) kullanır; kalıcı silme
-- yönetici işlemidir ve kapsamı büyütmeden dışarıda bırakıldı.
do $$
begin
  if to_regprocedure('phase0_private.islem_audit()') is null then
    raise exception 'phase0_private.islem_audit() yok: Phase 0 denetim izi uygulanmamis';
  end if;
end;
$$;

drop trigger if exists phase0_islem_audit on public.pms_rezervasyonlar;
create trigger phase0_islem_audit after insert or update on public.pms_rezervasyonlar
  for each row execute function phase0_private.islem_audit();

drop trigger if exists phase0_islem_audit on public.pms_oda_atamalari;
create trigger phase0_islem_audit after insert or update on public.pms_oda_atamalari
  for each row execute function phase0_private.islem_audit();

-- ============================================================================
-- 9) DOĞRULAMA — migration kendi iddialarını sınar
-- ============================================================================
do $$
declare v text;
begin
  -- Kolonlar
  foreach v in array array['giris_zamani','cikis_zamani','giris_yapan','cikis_yapan'] loop
    if not exists (select 1 from information_schema.columns
                   where table_schema='public' and table_name='pms_rezervasyonlar'
                     and column_name=v) then
      raise exception 'Kolon yok: pms_rezervasyonlar.%', v;
    end if;
  end loop;

  -- Constraint tetikleyicileri gerçekten CONSTRAINT + DEFERRABLE mı?
  foreach v in array array['pms_tutarlilik_oda','pms_tutarlilik_rezervasyon',
                           'pms_tutarlilik_atama','pms_rezervasyon_gecis',
                           'pms_oda_gecis','pms_atama_degisim_kontrol'] loop
    if not exists (select 1 from pg_trigger where tgname = v and not tgisinternal) then
      raise exception 'Tetikleyici yok: %', v;
    end if;
  end loop;
  if (select count(*) from pg_trigger
      where tgname in ('pms_tutarlilik_oda','pms_tutarlilik_rezervasyon',
                       'pms_tutarlilik_atama')
        and not tgisinternal and tgdeferrable) <> 3 then
    raise exception 'Tutarlilik tetikleyicileri deferrable degil';
  end if;

  -- RPC execute anon'a kapalı mı?
  if has_function_privilege('anon', 'public.pms_check_in(uuid,uuid)', 'execute')
     or has_function_privilege('anon', 'public.pms_check_out(uuid)', 'execute') then
    raise exception 'anon RPC calistirabiliyor';
  end if;

  -- pms_bugun tek nokta mı (STABLE)?
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                 where n.nspname='public' and p.proname='pms_bugun'
                   and p.provolatile='s') then
    raise exception 'pms_bugun yok veya stable degil';
  end if;

  -- Denetim izi: minimum kapsam tetikleyicileri yerinde mi ve Phase 0
  -- fonksiyonuna mı bağlı?
  foreach v in array array['pms_rezervasyonlar','pms_oda_atamalari'] loop
    if not exists (
      select 1 from pg_trigger t
       where t.tgrelid = ('public.' || v)::regclass
         and t.tgname = 'phase0_islem_audit' and not t.tgisinternal
         and t.tgfoid::regprocedure::text like '%islem_audit%' and t.tgenabled <> 'D') then
      raise exception 'Denetim izi tetikleyicisi yok: %', v;
    end if;
  end loop;
  -- Kişisel veri tabloları bilinçli kapsam dışı: yanlışlıkla bağlanmışsa kaldır.
  foreach v in array array['pms_misafirler','pms_misafir_kimlik'] loop
    if exists (select 1 from pg_trigger t
               where t.tgrelid = ('public.' || v)::regclass
                 and t.tgname = 'phase0_islem_audit') then
      raise exception 'Kisisel veri tablosu denetim kapsaminda olmamali: %', v;
    end if;
  end loop;
end;
$$;

commit;

notify pgrst, 'reload schema';

-- ============================================================================
-- GERİ ALMA
-- ============================================================================
-- Tek transaction: uygulama sirasindaki hata kendini geri alir.
-- Commit sonrasi geri alma (VERI SİLMEZ, yalnız yapıyı kaldırır):
--
-- begin;
--   drop function if exists public.pms_check_in(uuid, uuid);
--   drop function if exists public.pms_check_out(uuid);
--   drop function if exists public.pms_bugun(public.otel_id);
--   drop trigger if exists pms_tutarlilik_oda on public.pms_odalar;
--   drop trigger if exists pms_tutarlilik_rezervasyon on public.pms_rezervasyonlar;
--   drop trigger if exists pms_tutarlilik_atama on public.pms_oda_atamalari;
--   drop trigger if exists pms_rezervasyon_gecis on public.pms_rezervasyonlar;
--   drop trigger if exists pms_oda_gecis on public.pms_odalar;
--   drop trigger if exists pms_atama_degisim_kontrol on public.pms_oda_atamalari;
--   drop function if exists public.pms_tutarlilik_oda();
--   drop function if exists public.pms_tutarlilik_rezervasyon();
--   drop function if exists public.pms_tutarlilik_atama();
--   drop function if exists public.pms_rezervasyon_gecis();
--   drop function if exists public.pms_oda_gecis();
--   drop function if exists public.pms_atama_degisim_kontrol();
--   alter table public.pms_rezervasyonlar
--     drop column if exists giris_zamani,
--     drop column if exists cikis_zamani,
--     drop column if exists giris_yapan,
--     drop column if exists cikis_yapan;
-- commit;
--
-- Veri KAYBETMEDEN geri çekme (tercih edilen): check-in/out RPC'lerini ve
-- ekranı yetkilerle kapatmak — moduller tablosunda pms_* kapatma, Adım 1–2
-- geri çekme notundaki yöntemin aynısı.
