-- ============================================================================
-- PMS FAZ 1 / ADIM 4 — FOLIO (MİSAFİR HESABI)
-- ============================================================================
-- DURUM: ADAY. Üretime UYGULANMADI.
-- Üretim yazma dondurması yürürlükte — bkz. docs/kurulum/URETIM-YAYIN-RUNBOOK.md
--
-- ÖNKOŞUL: Adım 1, 2 ve 3 uygulanmış olmalı.
--
-- KAPSAM: misafir hesabı, gecelik oda ücreti işleme, bar/oda devri köprüsü,
-- ödeme kaydı, bakiye. Fiyat/sezon motoru ve muhasebe köprüsü YOK.
--
-- TEK TRANSACTION · TEKRAR ÇALIŞTIRILABİLİR · VERİ SİLMEZ
--
-- ---------------------------------------------------------------------------
-- KARAR 1 — ODA ÜCRETİ GECELİK İŞLENİR, FİYAT REZERVASYONDA
-- ---------------------------------------------------------------------------
-- Fiyat/sezon motoru henüz yok. Gecelik fiyat rezervasyona elle girilir
-- (`pms_rezervasyonlar.gecelik_fiyat`). `pms_folio_oda_ucreti_isle` RPC'si
-- konaklamanın GEÇMİŞ gecelerini folyoya tek tek işler.
--
-- Gerçek PMS'te bunu gece denetimi (night audit) otomatik yapar; burada
-- zamanlayıcı olmadığı için RPC talep üzerine çalışır ve AYNI GECEYİ İKİ KEZ
-- İŞLEMEZ — (folio, gece) benzersiz index'i bunu yapısal olarak imkânsız kılar.
-- Böylece ekrandan kaç kez tetiklenirse tetiklensin sonuç aynıdır.
--
-- Fiyat motoru geldiğinde yalnız fiyatın KAYNAĞI değişir; işleme mantığı durur.
--
-- ---------------------------------------------------------------------------
-- KARAR 2 — MUHASEBE KÖPRÜSÜ YOK (bilinçli)
-- ---------------------------------------------------------------------------
-- Ödemeler folio içinde tutulur; `banka_kasa_hareketleri` veya
-- `cari_hareketler`'e otomatik kayıt ATILMAZ. O tablolar tedarikçi muhasebesi
-- için tasarlandı; misafir tahsilatını oraya bağlamak hesap planı eşleşmesi,
-- iade/iptal akışı ve dönem kilidi etkileşimi çözülmeden mali kayıtları
-- kirletir. Köprü ayrı bir adımın konusudur.
--
-- ---------------------------------------------------------------------------
-- KARAR 3 — BAR/ODA DEVRİ KÖPRÜSÜ
-- ---------------------------------------------------------------------------
-- Ücretli bir bar siparişi `teslim_edildi` olduğunda ve `oda_no` doluysa,
-- tutar o odada KONAKLAYAN rezervasyonun folyosuna borç olarak düşer.
-- Güncel konaklama tanımı Adım 3'teki ile aynıdır:
--     atama.aktif = true VE rezervasyon.durum = 'giris_yapildi'
--
-- Oda numarası yazılmış ama odada kimse yoksa ve tutar > 0 ise teslim
-- REDDEDİLİR: tahsil edilemeyecek bir borç yazmak yerine yanlış oda numarası
-- anında görünür olmalı. Ücretsiz siparişlerde (tutar 0) doğrulama yapılmaz,
-- yani mevcut ikram akışı etkilenmez.
--
-- Teslim edilmiş sipariş sonradan iptal edilebiliyor (bar_siparis_iptal her
-- durumdan iptale izin veriyor); bu durumda borç SİLİNMEZ, TERS KAYIT yazılır.
-- Mali iz korunur.
--
-- ---------------------------------------------------------------------------
-- KAPSAM DIŞI (bilinçli, teknik borç olarak kayıtlı)
-- ---------------------------------------------------------------------------
-- * `pms_check_out` DEĞİŞTİRİLMEDİ. Faz 1 Core az önce onaylandı; folio onu
--   kırmamalı. Çıkışta oda ücretlerinin işlenmesi ekran akışının işidir
--   (folio ekranı "geceleri işle" düğmesi + çıkış öncesi çağrı).
-- * Çıkış BAKİYEYE BAKMAZ. Bakiyeli çıkışı bloklamak, yönetici geçişi
--   olmayan bir sistemde kilitlenme üretirdi (bu sınıf hata Adım 3'te iki kez
--   yaşandı). Bakiye açık kalır ve folio kapanmaz — borç görünür durur.
-- * GECİKMİŞ konaklamada planlanan aralığın DIŞINDAKİ geceler otomatik
--   işlenmez: `cikis_tarihi` ticari aralıktır ve konaklama sürerken donuktur.
--   Fazla geceler `ekstra` hareketiyle elle girilir. Otomatik uzatma, fiyat
--   motoruyla birlikte tasarlanmalı.
-- * Vergi/KDV ayrıştırması, döviz, indirim ve paket fiyatlandırma YOK.
-- ============================================================================

begin;

-- ============================================================================
-- 0) ÖN KOŞULLAR
-- ============================================================================
do $$
begin
  if to_regclass('public.pms_rezervasyonlar') is null
     or to_regclass('public.pms_oda_atamalari') is null then
    raise exception 'PMS Adim 2 uygulanmamis';
  end if;
  if to_regprocedure('public.pms_check_out(uuid)') is null then
    raise exception 'PMS Adim 3 uygulanmamis';
  end if;
  if to_regclass('public.bar_siparisleri') is null
     or to_regclass('public.menu_urunler') is null then
    raise exception 'Bar modulu yok: oda devri koprusu kurulamaz';
  end if;
end;
$$;

-- ============================================================================
-- 1) ENUM'LAR VE REZERVASYON FİYAT ALANI
-- ============================================================================
do $$
begin
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace
                 where n.nspname='public' and t.typname='pms_folio_durum') then
    create type public.pms_folio_durum as enum ('acik','kapali');
  end if;
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace
                 where n.nspname='public' and t.typname='pms_folio_hareket_tip') then
    create type public.pms_folio_hareket_tip as enum
      ('oda_ucreti','bar','ekstra','duzeltme');
  end if;
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace
                 where n.nspname='public' and t.typname='pms_odeme_yontem') then
    create type public.pms_odeme_yontem as enum
      ('nakit','kredi_karti','havale','diger');
  end if;
end;
$$;

alter table public.pms_rezervasyonlar
  add column if not exists gecelik_fiyat numeric(12,2);

do $$
begin
  if not exists (select 1 from pg_constraint where conname='pms_rezervasyonlar_fiyat') then
    alter table public.pms_rezervasyonlar add constraint pms_rezervasyonlar_fiyat
      check (gecelik_fiyat is null or gecelik_fiyat >= 0);
  end if;
end;
$$;

-- ============================================================================
-- 2) FOLYOLAR
-- ============================================================================
-- Rezervasyon başına BİRDEN FAZLA folyo olabilir (misafir + firma ayrımı,
-- ileride grup folyosu). Şimdilik otomatik bir tane açılır; şema bölünmüş
-- fatura için sonradan migration gerektirmesin diye baştan çoklu.
create table if not exists public.pms_folyolar (
  id                 uuid primary key default gen_random_uuid(),
  otel_id            public.otel_id not null,
  rezervasyon_id     uuid not null,
  folio_no           text not null,
  tip                text not null default 'misafir',
  durum              public.pms_folio_durum not null default 'acik',
  acilis_zamani      timestamptz not null default now(),
  kapanis_zamani     timestamptz,
  olusturma_tarihi   timestamptz not null default now(),
  guncelleme_tarihi  timestamptz not null default now()
);

create sequence if not exists public.pms_folio_no_seq;

do $$
begin
  if not exists (select 1 from pg_constraint where conname='pms_folyolar_id_otel_key') then
    alter table public.pms_folyolar add constraint pms_folyolar_id_otel_key
      unique (id, otel_id);
  end if;
  if not exists (select 1 from pg_constraint where conname='pms_folyolar_rez_fk') then
    alter table public.pms_folyolar add constraint pms_folyolar_rez_fk
      foreign key (rezervasyon_id, otel_id)
      references public.pms_rezervasyonlar (id, otel_id)
      on update cascade on delete restrict;
  end if;
  if not exists (select 1 from pg_constraint where conname='pms_folyolar_tip') then
    alter table public.pms_folyolar add constraint pms_folyolar_tip
      check (tip in ('misafir','firma'));
  end if;
  if not exists (select 1 from pg_constraint where conname='pms_folyolar_kapanis') then
    alter table public.pms_folyolar add constraint pms_folyolar_kapanis
      check ((durum = 'kapali') = (kapanis_zamani is not null));
  end if;
end;
$$;

create unique index if not exists pms_folyolar_no_uniq
  on public.pms_folyolar (otel_id, upper(folio_no));
create index if not exists pms_folyolar_rez_idx
  on public.pms_folyolar (rezervasyon_id, durum);

-- ============================================================================
-- 3) FOLYO HAREKETLERİ (borç)
-- ============================================================================
create table if not exists public.pms_folio_hareketleri (
  id                 uuid primary key default gen_random_uuid(),
  otel_id            public.otel_id not null,
  folio_id           uuid not null,
  tarih              date not null default current_date,
  tip                public.pms_folio_hareket_tip not null,
  aciklama           text not null,
  tutar              numeric(12,2) not null,
  kaynak_tip         text,
  kaynak_id          uuid,
  konaklama_gecesi   date,
  ters_kayit         boolean not null default false,
  olusturma_tarihi   timestamptz not null default now()
);

do $$
begin
  if not exists (select 1 from pg_constraint where conname='pms_folio_hareketleri_folio_fk') then
    alter table public.pms_folio_hareketleri add constraint pms_folio_hareketleri_folio_fk
      foreign key (folio_id, otel_id)
      references public.pms_folyolar (id, otel_id)
      on update cascade on delete restrict;
  end if;
  if not exists (select 1 from pg_constraint where conname='pms_folio_hareketleri_aciklama') then
    alter table public.pms_folio_hareketleri add constraint pms_folio_hareketleri_aciklama
      check (aciklama = btrim(aciklama) and aciklama <> '');
  end if;
  -- Oda ucreti hareketinin gecesi OLMALI; diger tiplerde olmamali.
  if not exists (select 1 from pg_constraint where conname='pms_folio_hareketleri_gece') then
    alter table public.pms_folio_hareketleri add constraint pms_folio_hareketleri_gece
      check ((tip = 'oda_ucreti') = (konaklama_gecesi is not null));
  end if;
  -- Ters kayit yalniz bir kaynaga bagli hareket icin anlamli.
  if not exists (select 1 from pg_constraint where conname='pms_folio_hareketleri_ters') then
    alter table public.pms_folio_hareketleri add constraint pms_folio_hareketleri_ters
      check (not ters_kayit or kaynak_id is not null);
  end if;
end;
$$;

-- AYNI GECE IKI KEZ ISLENEMEZ. RPC kac kez cagrilirsa cagrilsin sonuc ayni.
create unique index if not exists pms_folio_gece_uniq
  on public.pms_folio_hareketleri (folio_id, konaklama_gecesi)
  where tip = 'oda_ucreti';

-- AYNI KAYNAK (ornegin bar siparisi) BIR KEZ BORC, BIR KEZ TERS KAYIT.
create unique index if not exists pms_folio_kaynak_uniq
  on public.pms_folio_hareketleri (kaynak_tip, kaynak_id, ters_kayit)
  where kaynak_id is not null;

create index if not exists pms_folio_hareketleri_folio_idx
  on public.pms_folio_hareketleri (folio_id, tarih);

-- ============================================================================
-- 4) ÖDEMELER
-- ============================================================================
create table if not exists public.pms_folio_odemeler (
  id                 uuid primary key default gen_random_uuid(),
  otel_id            public.otel_id not null,
  folio_id           uuid not null,
  tarih              date not null default current_date,
  yontem             public.pms_odeme_yontem not null,
  tutar              numeric(12,2) not null,
  aciklama           text,
  olusturma_tarihi   timestamptz not null default now()
);

do $$
begin
  if not exists (select 1 from pg_constraint where conname='pms_folio_odemeler_folio_fk') then
    alter table public.pms_folio_odemeler add constraint pms_folio_odemeler_folio_fk
      foreign key (folio_id, otel_id)
      references public.pms_folyolar (id, otel_id)
      on update cascade on delete restrict;
  end if;
  -- Tutar sifir olamaz; iade NEGATIF odeme olarak girilir.
  if not exists (select 1 from pg_constraint where conname='pms_folio_odemeler_tutar') then
    alter table public.pms_folio_odemeler add constraint pms_folio_odemeler_tutar
      check (tutar <> 0);
  end if;
end;
$$;

create index if not exists pms_folio_odemeler_folio_idx
  on public.pms_folio_odemeler (folio_id, tarih);

-- ÖDEME IDEMPOTENCY ANAHTARI.
-- Hareketlerde kaynak (bar siparisi) mukerrer borcu engelliyor; odemenin ise
-- dogal bir is anahtari YOK. Cift tiklama ya da ag katmaninin ayni istegi
-- tekrar gondermesi ikinci bir tahsilat uretirdi ve bakiye sessizce bozulurdu.
-- Istemci odeme niyeti basina bir anahtar uretir; ayni anahtar ikinci kez
-- yazilamaz. Anahtarsiz odeme de kabul edilir (eski/entegrasyon disi yollar).
alter table public.pms_folio_odemeler
  add column if not exists islem_anahtari text;

do $$
begin
  if not exists (select 1 from pg_constraint where conname='pms_folio_odemeler_anahtar') then
    alter table public.pms_folio_odemeler add constraint pms_folio_odemeler_anahtar
      check (islem_anahtari is null
             or (islem_anahtari = btrim(islem_anahtari)
                 and length(islem_anahtari) between 8 and 100));
  end if;
end;
$$;

create unique index if not exists pms_folio_odeme_anahtar_uniq
  on public.pms_folio_odemeler (otel_id, islem_anahtari)
  where islem_anahtari is not null;

-- ============================================================================
-- 5) BAKİYE GÖRÜNÜMÜ
-- ============================================================================
-- security_invoker: görünüm çağıranın hakkıyla çalışır, RLS devrede kalır.
create or replace view public.pms_folio_ozet
with (security_invoker = true) as
select f.id                as folio_id,
       f.otel_id,
       f.rezervasyon_id,
       f.folio_no,
       f.durum,
       coalesce(h.borc, 0)   as borc,
       coalesce(o.odeme, 0)  as odeme,
       coalesce(h.borc, 0) - coalesce(o.odeme, 0) as bakiye
from public.pms_folyolar f
left join (select folio_id, sum(tutar) as borc
             from public.pms_folio_hareketleri group by folio_id) h on h.folio_id = f.id
left join (select folio_id, sum(tutar) as odeme
             from public.pms_folio_odemeler group by folio_id) o on o.folio_id = f.id;

-- ============================================================================
-- 6) FOLYO OTOMATİK AÇILIŞI
-- ============================================================================
-- Rezervasyon 'onaylandi' olduğunda folyo açılır. SECURITY DEFINER: kullanıcı
-- rezervasyon üzerinde yetkisini zaten kanıtladı; folyo o rezervasyonun iç
-- muhasebe kaydıdır ve ayrı bir yetki istemek akışı kilitlerdi.
create or replace function public.pms_folio_otomatik_ac()
returns trigger language plpgsql security definer
set search_path = pg_catalog, public, pg_temp as $$
begin
  if not exists (select 1 from public.pms_folyolar
                  where rezervasyon_id = new.id and otel_id = new.otel_id) then
    insert into public.pms_folyolar (otel_id, rezervasyon_id, folio_no)
    values (new.otel_id,
            new.id,
            'F-' || to_char(now(), 'YYYY') || '-'
              || lpad(nextval('public.pms_folio_no_seq')::text, 6, '0'));
  end if;
  return null;
end;
$$;

drop trigger if exists pms_folio_otomatik_ac on public.pms_rezervasyonlar;
create trigger pms_folio_otomatik_ac after insert or update of durum
  on public.pms_rezervasyonlar
  for each row when (new.durum = 'onaylandi')
  execute function public.pms_folio_otomatik_ac();

-- ============================================================================
-- 7) GECELİK ODA ÜCRETİ İŞLEME
-- ============================================================================
-- Konaklamanın BUGÜNE KADARKİ gecelerini işler. Gece n, [giris, cikis)
-- aralığındadır ve n <= bugün ise "gerçekleşmiş" sayılır.
-- Planlanan aralığın DIŞINA taşmaz (bkz. başlıktaki kapsam dışı notu).
create or replace function public.pms_folio_oda_ucreti_isle(p_rezervasyon_id uuid)
returns integer
language plpgsql
set search_path = pg_catalog, public, pg_temp as $$
declare
  v_rez    public.pms_rezervasyonlar%rowtype;
  v_folio  public.pms_folyolar%rowtype;
  v_bugun  date;
  v_eklendi integer := 0;
begin
  if public.auth_yetki_var('pms_folio','kayit') is not true then
    raise exception 'Folyo kayit yetkisi gerekli';
  end if;

  select * into v_rez from public.pms_rezervasyonlar
   where id = p_rezervasyon_id for update;
  if not found then
    raise exception 'Rezervasyon bulunamadi veya erisim yok';
  end if;
  if v_rez.gecelik_fiyat is null then
    raise exception 'Rezervasyonda gecelik fiyat yok; once fiyat girin';
  end if;
  if v_rez.durum not in ('giris_yapildi','cikis_yapildi') then
    raise exception 'Oda ucreti yalniz giris yapilmis konaklamaya islenir (durum: %)',
      v_rez.durum;
  end if;

  select * into v_folio from public.pms_folyolar
   where rezervasyon_id = v_rez.id and otel_id = v_rez.otel_id and durum = 'acik'
   order by acilis_zamani limit 1
   for update;
  if not found then
    raise exception 'Rezervasyonun acik folyosu yok';
  end if;

  v_bugun := public.pms_bugun(v_rez.otel_id);

  -- Ayni gece iki kez islenemez: benzersiz index + on conflict do nothing.
  -- RPC'nin kac kez cagrildigi sonucu DEGISTIRMEZ.
  with geceler as (
    select g::date as gece
      from generate_series(v_rez.giris_tarihi,
                           v_rez.cikis_tarihi - 1,
                           interval '1 day') g
     where g::date <= v_bugun
  ), eklenen as (
    insert into public.pms_folio_hareketleri
      (otel_id, folio_id, tarih, tip, aciklama, tutar, konaklama_gecesi)
    select v_rez.otel_id, v_folio.id, gece, 'oda_ucreti',
           'Oda ucreti ' || to_char(gece,'DD.MM.YYYY'), v_rez.gecelik_fiyat, gece
      from geceler
    on conflict do nothing
    returning 1
  )
  select count(*) into v_eklendi from eklenen;

  return v_eklendi;
end;
$$;

-- ============================================================================
-- 8) BAR / ODA DEVRİ KÖPRÜSÜ
-- ============================================================================
-- SECURITY DEFINER: bar personelinin folyo yetkisi olmayabilir; oda devri
-- barın kendi akışının parçasıdır.
create or replace function public.pms_bar_folio_koprusu()
returns trigger language plpgsql security definer
set search_path = pg_catalog, public, pg_temp as $$
declare
  v_tutar  numeric(12,2);
  v_folio  public.pms_folyolar%rowtype;
begin
  -- Yalniz ucretli kalemlerin toplami folyoya duser.
  select coalesce(sum(k.adet * m.fiyat), 0) into v_tutar
    from public.bar_siparis_kalemleri k
    join public.menu_urunler m on m.id = k.menu_urun_id
   where k.siparis_id = new.id and m.ucretli;

  -- ---- TESLIM: borc yaz ----
  if new.durum = 'teslim_edildi' and old.durum is distinct from 'teslim_edildi' then
    if new.oda_no is null or btrim(new.oda_no) = '' or v_tutar = 0 then
      return null;   -- oda devri yok ya da ikram: folyoyu ilgilendirmez
    end if;

    -- GUNCEL KONAKLAMA (Adim 3 tanimi): aktif atama + giris_yapildi.
    select f.* into v_folio
      from public.pms_odalar o
      join public.pms_oda_atamalari a
        on a.oda_id = o.id and a.otel_id = o.otel_id and a.aktif
      join public.pms_rezervasyonlar r
        on r.id = a.rezervasyon_id and r.otel_id = a.otel_id
       and r.durum = 'giris_yapildi'
      join public.pms_folyolar f
        on f.rezervasyon_id = r.id and f.otel_id = r.otel_id and f.durum = 'acik'
     where o.otel_id = new.otel_id and upper(o.oda_no) = upper(btrim(new.oda_no))
     order by f.acilis_zamani
     limit 1;

    if not found then
      -- Tahsil edilemeyecek borc yazmak yerine yanlis oda numarasi ANINDA
      -- gorunur olsun. Ucretsiz siparislerde buraya hic gelinmez.
      raise exception 'Oda % icin acik folyo yok (odada konaklayan yok veya folyo kapali); oda devri yapilamaz',
        new.oda_no;
    end if;

    insert into public.pms_folio_hareketleri
      (otel_id, folio_id, tip, aciklama, tutar, kaynak_tip, kaynak_id)
    values (v_folio.otel_id, v_folio.id, 'bar',
            'Bar/restoran siparisi (oda ' || new.oda_no || ')',
            v_tutar, 'bar', new.id)
    on conflict do nothing;   -- ayni siparis iki kez borclandirilamaz
    return null;
  end if;

  -- TESLIMDEN CIKIS DIYE BIR SEY YOK: 'teslim_edildi' TERMINAL durumdur
  -- (asagidaki pms_bar_durum_kilit). Teslimden sonra yapilan duzeltme folyoya
  -- elle 'duzeltme' satiri olarak girilir; bar siparisinin durumu geri alinmaz.
  -- Bu yuzden burada ters kayit dali YOKTUR: ulasilamayan, dolayisiyla
  -- sinanamayan bir finansal kod yolu birakmiyoruz.
  return null;
end;
$$;

drop trigger if exists pms_bar_folio_koprusu on public.bar_siparisleri;
create trigger pms_bar_folio_koprusu after update of durum on public.bar_siparisleri
  for each row execute function public.pms_bar_folio_koprusu();

-- ---------------------------------------------------------------------------
-- BAR DURUM MAKINESI: 'teslim_edildi' ve 'iptal' TERMINALDIR
-- ---------------------------------------------------------------------------
-- Bu kural yeni bir is kurali DEGIL; sistemde zaten fiilen gecerli olan
-- davranisin DB katmaninda eksik kalan yarisi:
--
--   * bar_siparis_teslim_et() stok rezervasyonlarini 'kullanildi' yapar ve
--     stogu duser. IKINCI teslim hicbir stok hareketi uretmez.
--   * bar_siparis_iptal() yalniz 'aktif' rezervasyonu serbest birakir; teslim
--     sonrasi iptal stogu GERI VERMEZ.
--   * bar_siparis_durum_guncelle() yalniz 'hazirlaniyor'/'hazir' hedefini
--     kabul eder, terminal durumlardan geri donus saglamaz.
--   * bar-siparis-kuyrugu.html teslim/iptal kartlarinda HIC buton gostermez.
--
-- Yani stok defteri ve ekran icin teslim/iptal zaten son duraktir; yalnizca
-- dogrudan REST/DML yolu aciktir. Acik kalirsa
-- teslim_edildi -> iptal -> teslim_edildi zinciri folyoda borc/ters kayit
-- karmasasi uretebilirdi. Kural burada kapatilir; teslim sonrasi duzeltme
-- folyoya 'duzeltme' satiri olarak girilir.
create or replace function public.pms_bar_durum_kilit()
returns trigger language plpgsql
set search_path = pg_catalog, public, pg_temp as $$
begin
  if new.durum is not distinct from old.durum then
    return new;   -- durum degismiyor: diger kolonlar serbest
  end if;
  if old.durum in ('teslim_edildi','iptal') then
    raise exception
      'Bar siparisi % durumundan cikarilamaz (son durum). Duzeltme folyoya duzeltme satiri olarak girilir',
      old.durum
      using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists pms_bar_durum_kilit on public.bar_siparisleri;
create trigger pms_bar_durum_kilit before update of durum on public.bar_siparisleri
  for each row execute function public.pms_bar_durum_kilit();

-- ============================================================================
-- 9) FOLYO KAPATMA
-- ============================================================================
create or replace function public.pms_folio_kapat(p_folio_id uuid)
returns uuid
language plpgsql
set search_path = pg_catalog, public, pg_temp as $$
declare v_folio public.pms_folyolar%rowtype; v_bakiye numeric(12,2);
begin
  if public.auth_yetki_var('pms_folio','kayit') is not true then
    raise exception 'Folyo kayit yetkisi gerekli';
  end if;

  select * into v_folio from public.pms_folyolar where id = p_folio_id for update;
  if not found then
    raise exception 'Folyo bulunamadi veya erisim yok';
  end if;
  if v_folio.durum = 'kapali' then
    raise exception 'Folyo zaten kapali';
  end if;

  select coalesce((select sum(tutar) from public.pms_folio_hareketleri where folio_id = v_folio.id), 0)
       - coalesce((select sum(tutar) from public.pms_folio_odemeler    where folio_id = v_folio.id), 0)
    into v_bakiye;

  if v_bakiye <> 0 then
    raise exception 'Folyo bakiyesi sifir degil (%); once tahsilat veya duzeltme', v_bakiye;
  end if;

  update public.pms_folyolar
     set durum = 'kapali', kapanis_zamani = now()
   where id = v_folio.id;
  return v_folio.id;
end;
$$;

-- Kapali folyoya yazma YASAK.
--
-- KILIT ZORUNLU (P0 dersi): kilitsiz `select ... where durum = 'kapali'`
-- READ COMMITTED altinda YARISI KAYBEDER. Kapatan islem folyoyu 'kapali'
-- yapip commit ederken, ayni anda baslamis bir odeme hala ESKI satiri
-- ('acik') gorur, kontrolden gecer ve KAPANMIS folyoya yazar; folyo sifir
-- bakiyeyle kapali gorunurken bakiyesi artik sifir DEGILDIR.
--
-- `for share` bunu deterministik yapar: kapatan islem satiri `for update` ile
-- tuttugu icin yazan islem BEKLER; kapanis commit olunca kilit istegi satirin
-- EN GUNCEL surumunu yeniden okur ve 'kapali' gorup reddeder. Ters sirada
-- (once yazan) kapanis bekler, sonra bakiyeyi yeniden hesaplar ve sifir
-- degilse reddeder. Iki yonde de tek bir dogru sonuc kalir.
create or replace function public.pms_folio_kapali_kontrol()
returns trigger language plpgsql
set search_path = pg_catalog, public, pg_temp as $$
declare v_durum public.pms_folio_durum;
begin
  select durum into v_durum from public.pms_folyolar
   where id = new.folio_id for share;
  if v_durum = 'kapali' then
    raise exception 'Kapali folyoya kayit eklenemez veya degistirilemez';
  end if;
  return new;
end;
$$;

drop trigger if exists pms_folio_kapali_kontrol on public.pms_folio_hareketleri;
create trigger pms_folio_kapali_kontrol before insert
  on public.pms_folio_hareketleri
  for each row execute function public.pms_folio_kapali_kontrol();

drop trigger if exists pms_folio_kapali_kontrol on public.pms_folio_odemeler;
create trigger pms_folio_kapali_kontrol before insert
  on public.pms_folio_odemeler
  for each row execute function public.pms_folio_kapali_kontrol();

-- ---------------------------------------------------------------------------
-- FINANSAL HAREKETLER APPEND-ONLY
-- ---------------------------------------------------------------------------
-- Muhasebesel gecmis DEGISTIRILEMEZ ve SILINEMEZ. Yanlis kayit yeni bir
-- kayitla duzeltilir: negatif tutarli 'duzeltme' hareketi, iade icin negatif
-- odeme, bar iptalinde ters kayit. Bunlarin hepsi zaten tasarimda var, yani
-- append-only kisitlamasi hicbir mevcut akisi kapatmiyor.
--
-- Koruma tetikleyicidedir, yalniz ayricalik/politika katmaninda degil: RLS'i
-- atlayan service_role da buna takilir. Migration'in kendi geri alisi tablolari
-- DROP eder (DDL), bu tetikleyici DDL'i engellemez.
create or replace function public.pms_folio_degismez()
returns trigger language plpgsql
set search_path = pg_catalog, public, pg_temp as $$
begin
  raise exception
    'Finansal kayit degistirilemez/silinemez (%.%). Duzeltme icin ters kayit girin',
    tg_table_name, lower(tg_op)
    using errcode = '42501';
end;
$$;

drop trigger if exists pms_folio_degismez on public.pms_folio_hareketleri;
create trigger pms_folio_degismez before update or delete
  on public.pms_folio_hareketleri
  for each row execute function public.pms_folio_degismez();

drop trigger if exists pms_folio_degismez on public.pms_folio_odemeler;
create trigger pms_folio_degismez before update or delete
  on public.pms_folio_odemeler
  for each row execute function public.pms_folio_degismez();

-- Guncelleme damgasi
drop trigger if exists pms_guncelleme on public.pms_folyolar;
create trigger pms_guncelleme before update on public.pms_folyolar
  for each row execute function public.pms_guncelleme_damgala();

do $$
begin
  if to_regprocedure('phase0_private.otel_degismez()') is not null then
    execute 'drop trigger if exists phase0_otel_degismez on public.pms_folyolar';
    execute 'create trigger phase0_otel_degismez before update of otel_id
             on public.pms_folyolar for each row
             execute function phase0_private.otel_degismez()';
  end if;
end;
$$;

-- ============================================================================
-- 10) YETKİ MODÜLÜ
-- ============================================================================
insert into public.moduller (kod, ad, kategori, sira, aktif) values
  ('pms_folio', 'Ön Büro — Misafir Hesabı (Folio)', 'onburo', 48, true)
on conflict (kod) do nothing;

insert into public.yetki_matrisi (rol_id, modul_id, yetki)
select ym.rol_id, m.id, 'tam'::public.yetki_seviye
from public.yetki_matrisi ym
join public.moduller yy on yy.id = ym.modul_id and yy.kod = 'yetki_yonetimi'
cross join public.moduller m
where ym.yetki = 'tam' and m.kod = 'pms_folio'
on conflict (rol_id, modul_id) do nothing;

-- ============================================================================
-- 11) RLS
-- ============================================================================
do $$
declare v_tablo text;
begin
  foreach v_tablo in array array['pms_folyolar','pms_folio_hareketleri',
                                 'pms_folio_odemeler'] loop
    execute format('alter table public.%I enable row level security', v_tablo);
    -- authenticated DAHIL sifirla: varsayilan ayricaliklar (F2 dersi) tabloya
    -- zaten ALL vermis olabilir; yalniz public/anon'u geri almak append-only
    -- kisitlamasini SESSIZCE etkisiz birakirdi.
    execute format('revoke all on public.%I from public, anon, authenticated', v_tablo);
    -- Finansal hareket tablolari APPEND-ONLY: update/delete AYRICALIGI dahi yok.
    -- Folyo BASLIGI degistirilebilir/silinebilir kalir; ama hareketi ya da
    -- odemesi olan folyo, FK'lerin `on delete restrict`i yuzunden zaten
    -- silinemez — yani baslik silme finansal gecmisi yok edemez.
    if v_tablo = 'pms_folyolar' then
      execute format('grant select, insert, update, delete on public.%I to authenticated', v_tablo);
    else
      execute format('grant select, insert on public.%I to authenticated', v_tablo);
    end if;
    execute format('grant all on public.%I to service_role', v_tablo);

    execute format('drop policy if exists %I on public.%I', v_tablo || '_select', v_tablo);
    execute format($f$create policy %I on public.%I for select to authenticated
      using (public.auth_yetki_var('pms_folio','goruntule') is true
             and public.auth_otel_erisim(otel_id::text) is true)$f$,
      v_tablo || '_select', v_tablo);

    execute format('drop policy if exists %I on public.%I', v_tablo || '_insert', v_tablo);
    execute format($f$create policy %I on public.%I for insert to authenticated
      with check (public.auth_yetki_var('pms_folio','kayit') is true
                  and public.auth_otel_erisim(otel_id::text) is true)$f$,
      v_tablo || '_insert', v_tablo);

    -- Append-only tablolarda update/delete POLITIKASI DA yok: politikasiz
    -- islem RLS altinda 0 satir eder, ayricalik da verilmedi, ustune
    -- tetikleyici var. Uc katman da ayni yone bakar.
    execute format('drop policy if exists %I on public.%I', v_tablo || '_update', v_tablo);
    execute format('drop policy if exists %I on public.%I', v_tablo || '_delete', v_tablo);

    if v_tablo = 'pms_folyolar' then
      execute format($f$create policy %I on public.%I for update to authenticated
        using (public.auth_yetki_var('pms_folio','kayit') is true
               and public.auth_otel_erisim(otel_id::text) is true)
        with check (public.auth_yetki_var('pms_folio','kayit') is true
                    and public.auth_otel_erisim(otel_id::text) is true)$f$,
        v_tablo || '_update', v_tablo);

      execute format($f$create policy %I on public.%I for delete to authenticated
        using (public.auth_yetki_var('pms_folio','tam') is true
               and public.auth_otel_erisim(otel_id::text) is true)$f$,
        v_tablo || '_delete', v_tablo);
    end if;

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

-- Sekans ACL: varsayilan ayricaliklar authenticated'a ALL acabiliyor (F2 dersi).
revoke all on sequence public.pms_folio_no_seq from public, anon, authenticated;
grant usage on sequence public.pms_folio_no_seq to authenticated;
grant all   on sequence public.pms_folio_no_seq to service_role;

revoke all on function public.pms_folio_oda_ucreti_isle(uuid) from public, anon;
revoke all on function public.pms_folio_kapat(uuid)           from public, anon;
grant execute on function public.pms_folio_oda_ucreti_isle(uuid) to authenticated, service_role;
grant execute on function public.pms_folio_kapat(uuid)           to authenticated, service_role;

-- Görünüm de aynı kapsamda.
revoke all on public.pms_folio_ozet from public, anon;
grant select on public.pms_folio_ozet to authenticated, service_role;

-- ============================================================================
-- 12) DENETİM İZİ — Phase 0 generic tetikleyicisi, MİNİMUM kapsam
-- ============================================================================
-- Para hareketleri denetlenir. Folyo başlığı (açılış/kapanış) da para akışının
-- sınırını belirlediği için kapsamda.
do $$
declare v_tablo text;
begin
  if to_regprocedure('phase0_private.islem_audit()') is null then
    raise notice 'phase0_private.islem_audit() yok - PMS folio denetim izi ATLANDI';
    return;
  end if;
  foreach v_tablo in array array['pms_folyolar','pms_folio_hareketleri',
                                 'pms_folio_odemeler'] loop
    -- DELETE DE DENETLENIR. Hareket/odeme zaten append-only tetikleyicisine
    -- takilir; ama "silme mumkun + iz yok" durumu hicbir tabloda kalmasin
    -- diye kapsam op bazinda degil, tablo bazinda tam tutuldu. Folyo basligi
    -- silinebilen tek satirdir ve artik izini birakir.
    -- islem_audit() satir icerigini KOPYALAMAZ: yalniz otel, aktor, op,
    -- tablo, kimlik ve txid yazar. Odeme yontemi, tutar, misafir bilgisi ya da
    -- kart benzeri hicbir veri denetim izine dusmez.
    execute format('drop trigger if exists phase0_islem_audit on public.%I', v_tablo);
    execute format('create trigger phase0_islem_audit after insert or update or delete
                    on public.%I for each row
                    execute function phase0_private.islem_audit()', v_tablo);
  end loop;
end;
$$;

-- ============================================================================
-- 13) DOĞRULAMA
-- ============================================================================
do $$
declare v_tablo text; v_rel regclass;
begin
  foreach v_tablo in array array['pms_folyolar','pms_folio_hareketleri',
                                 'pms_folio_odemeler'] loop
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
    if not exists (select 1 from pg_trigger where tgrelid = v_rel
                   and tgname = 'phase0_islem_audit' and not tgisinternal) then
      raise exception 'Denetim izi tetikleyicisi yok: %', v_tablo;
    end if;
  end loop;

  -- Sekans ACL (F2 dersi): anon/PUBLIC hicbir hak almamali.
  if has_sequence_privilege('anon','public.pms_folio_no_seq','USAGE,SELECT,UPDATE')
     or has_sequence_privilege('public','public.pms_folio_no_seq','USAGE,SELECT,UPDATE') then
    raise exception 'pms_folio_no_seq anon/PUBLIC e acik';
  end if;
  if has_sequence_privilege('authenticated','public.pms_folio_no_seq','SELECT')
     or has_sequence_privilege('authenticated','public.pms_folio_no_seq','UPDATE') then
    raise exception 'authenticated sekansta USAGE disinda hak almis';
  end if;

  -- Idempotency dayanaklari index'lerdir; varliklari sinanir.
  -- VARLIK YETMEZ: index BENZERSIZ olmali. Ayni adla benzersiz olmayan bir
  -- index idempotency'yi sessizce yok ederdi; sadece adi aramak bunu kacirir.
  foreach v_tablo in array array['pms_folio_gece_uniq','pms_folio_kaynak_uniq',
                                 'pms_folio_odeme_anahtar_uniq'] loop
    if not exists (select 1 from pg_class c where c.relname = v_tablo and c.relkind = 'i') then
      raise exception 'Idempotency index i yok: %', v_tablo;
    end if;
    if not exists (select 1 from pg_index i join pg_class c on c.oid = i.indexrelid
                    where c.relname = v_tablo and i.indisunique) then
      raise exception 'Idempotency index i BENZERSIZ DEGIL: %', v_tablo;
    end if;
  end loop;

  -- APPEND-ONLY: uc katman da kapali olmali.
  foreach v_tablo in array array['pms_folio_hareketleri','pms_folio_odemeler'] loop
    v_rel := to_regclass('public.' || v_tablo);
    if has_table_privilege('authenticated', v_rel, 'UPDATE')
       or has_table_privilege('authenticated', v_rel, 'DELETE') then
      raise exception 'Finansal tabloda update/delete ayricaligi kalmis: %', v_tablo;
    end if;
    if exists (select 1 from pg_policy p where p.polrelid = v_rel
                and p.polcmd in ('w','d')) then
      raise exception 'Finansal tabloda update/delete politikasi kalmis: %', v_tablo;
    end if;
    if not exists (select 1 from pg_trigger t where t.tgrelid = v_rel
                    and t.tgname = 'pms_folio_degismez' and not t.tgisinternal) then
      raise exception 'Append-only tetikleyicisi yok: %', v_tablo;
    end if;
  end loop;

  -- Bar durum kilidi olmadan teslim_edildi -> iptal -> teslim_edildi zinciri
  -- folyoda borc/ters kayit karmasasi uretir.
  if not exists (select 1 from pg_trigger t
                  where t.tgrelid = 'public.bar_siparisleri'::regclass
                    and t.tgname = 'pms_bar_durum_kilit' and not t.tgisinternal) then
    raise exception 'Bar durum kilidi tetikleyicisi yok';
  end if;

  -- "Silme mumkun + denetim izi yok" durumu HICBIR tabloda kalmamali.
  foreach v_tablo in array array['pms_folyolar','pms_folio_hareketleri',
                                 'pms_folio_odemeler'] loop
    v_rel := to_regclass('public.' || v_tablo);
    if to_regprocedure('phase0_private.islem_audit()') is not null
       and not exists (select 1 from pg_trigger t where t.tgrelid = v_rel
                        and t.tgname = 'phase0_islem_audit'
                        and not t.tgisinternal
                        and (t.tgtype & 8) = 8) then   -- 8 = DELETE
      raise exception 'Denetim izi DELETE i kapsamiyor: %', v_tablo;
    end if;
  end loop;

  if (select count(*) from public.moduller where kod = 'pms_folio') <> 1 then
    raise exception 'pms_folio modulu kaydedilmedi';
  end if;

  -- Gorunum cagiranin hakkiyla calismali; aksi halde RLS atlanir.
  if not exists (select 1 from pg_class c
                 join pg_namespace n on n.oid = c.relnamespace
                 where n.nspname='public' and c.relname='pms_folio_ozet'
                   and c.relkind='v'
                   and array_to_string(c.reloptions,',') like '%security_invoker=true%') then
    raise exception 'pms_folio_ozet security_invoker degil - RLS atlanabilir';
  end if;
end;
$$;

commit;

notify pgrst, 'reload schema';

-- ============================================================================
-- GERİ ALMA
-- ============================================================================
-- begin;
--   drop trigger if exists pms_bar_folio_koprusu on public.bar_siparisleri;
--   drop trigger if exists pms_folio_otomatik_ac on public.pms_rezervasyonlar;
--   drop view  if exists public.pms_folio_ozet;
--   drop table if exists public.pms_folio_odemeler;
--   drop table if exists public.pms_folio_hareketleri;
--   drop table if exists public.pms_folyolar;
--   drop sequence if exists public.pms_folio_no_seq;
--   drop function if exists public.pms_folio_oda_ucreti_isle(uuid);
--   drop function if exists public.pms_folio_kapat(uuid);
--   drop function if exists public.pms_folio_otomatik_ac();
--   drop function if exists public.pms_bar_folio_koprusu();
--   drop function if exists public.pms_folio_kapali_kontrol();
--   drop type if exists public.pms_folio_durum;
--   drop type if exists public.pms_folio_hareket_tip;
--   drop type if exists public.pms_odeme_yontem;
--   alter table public.pms_rezervasyonlar drop column if exists gecelik_fiyat;
--   delete from public.yetki_matrisi where modul_id in
--     (select id from public.moduller where kod = 'pms_folio');
--   delete from public.moduller where kod = 'pms_folio';
-- commit;
--
-- Veri kaybetmeden geri cekme: update public.moduller set aktif=false
--   where kod='pms_folio';  (bar koprusu tetikleyicisi ayrica dusurulmeli)
