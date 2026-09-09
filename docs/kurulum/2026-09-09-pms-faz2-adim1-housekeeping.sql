-- ============================================================================
-- PMS FAZ 2 / ADIM 1 — KAT HİZMETLERİ (HOUSEKEEPING)
-- Tarih: 2026-09-09
--
-- ############################################################################
-- # ÜRETİME UYGULANMADI. `CANLIYA UYGULA` onayı olmadan çalıştırılmaz.       #
-- # Bu dosya ADAY migration'dır; yalnız yerel/atılabilir staging'de           #
-- # doğrulanmıştır.                                                          #
-- ############################################################################
--
-- YETKİLİ ŞARTNAME: docs/PMS-FAZ2-HOUSEKEEPING-ARCHITECTURE.md
--   Bu dosya o belgenin uygulamasıdır. Belge ile bu dosya çelişirse BELGE
--   kazanır ve bu dosya düzeltilir — tersi değil.
--
-- STANDART: docs/kurulum/MIGRATION-GUVENLIK-STANDARDI.md
-- ŞABLON  : docs/kurulum/SABLON-yeni-migration.sql
--
-- KAPSAM (Adım 1, veritabanı-önce):
--   Bu dosya görev tablosunu, bütünlük sözleşmesini, RLS/ACL'i ve modül
--   kaydını kurar. Durum makinesi RPC'leri, çıkış üreticisi, yaşam döngüsü
--   geçersizleştiricisi ve denetim izi genişletmesi AYNI migration'ın
--   sonraki bölümleridir; hiçbiri ayrı bir dosyaya taşınmaz.
--
-- FAZ 1'E DOKUNULMAZ: dört Faz 1 migration'ı ve hash manifesti değişmez.
-- ============================================================================


-- ============================================================================
-- 0) ÖN KOŞULLAR (prerequisites)
-- ----------------------------------------------------------------------------
-- Mimari §17.1: eksik denetim izi ya da değişmezlik altyapısı SERT HATADIR,
-- "yoksa atla" değil. Şablonun `raise notice ... return` kalıbı burada
-- BİLEREK kullanılmaz.
-- ============================================================================
do $$
begin
  -- Yetki motoru
  if to_regclass('public.moduller') is null
     or to_regclass('public.yetki_matrisi') is null
     or to_regclass('public.kullanicilar') is null then
    raise exception 'ONKOSUL: yetki motoru tablolari eksik';
  end if;

  -- Phase 0 fail-closed yardimcilari
  if to_regprocedure('public.auth_yetki_var(text, text)') is null
     or to_regprocedure('public.auth_otel_erisim(text)') is null
     or to_regprocedure('public.auth_erp_kullanicisi()') is null
     or to_regprocedure('public.auth_tum_oteller()') is null then
    raise exception 'ONKOSUL: auth_* yardimcilari eksik';
  end if;

  -- Denetim izi altyapisi — SERT HATA
  if to_regnamespace('phase0_private') is null then
    raise exception 'ONKOSUL: phase0_private semasi yok';
  end if;
  if to_regclass('public.erp_islem_audit') is null then
    raise exception 'ONKOSUL: erp_islem_audit tablosu yok';
  end if;
  if to_regprocedure('phase0_private.islem_audit()') is null then
    raise exception 'ONKOSUL: phase0_private.islem_audit() yok';
  end if;
  if to_regprocedure('phase0_private.otel_degismez()') is null then
    raise exception 'ONKOSUL: phase0_private.otel_degismez() yok';
  end if;

  -- PMS Faz 1 nesneleri
  if to_regclass('public.pms_odalar') is null
     or to_regclass('public.pms_oda_atamalari') is null
     or to_regclass('public.pms_rezervasyonlar') is null then
    raise exception 'ONKOSUL: PMS Faz 1 tablolari eksik';
  end if;

  -- Oda FK hedefi: (id, otel_id) benzersiz olmali
  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.pms_odalar'::regclass
       and contype = 'u'
       and conkey = array[
             (select attnum from pg_attribute where attrelid='public.pms_odalar'::regclass and attname='id'),
             (select attnum from pg_attribute where attrelid='public.pms_odalar'::regclass and attname='otel_id')
           ]::smallint[]) then
    raise exception 'ONKOSUL: pms_odalar(id, otel_id) benzersiz anahtari yok';
  end if;

  -- Faz 1 tutarlilik kisitlari duruyor mu (cikis akisi bunlara dayanir)
  if not exists (select 1 from pg_constraint where conname = 'pms_tutarlilik_oda')
     or not exists (select 1 from pg_constraint where conname = 'pms_tutarlilik_rezervasyon')
     or not exists (select 1 from pg_constraint where conname = 'pms_tutarlilik_atama') then
    raise exception 'ONKOSUL: Faz 1 tutarlilik kisitlari eksik';
  end if;

  -- Mimari §7.4: eski `temizleniyor` oda SIFIR olmali. Faz 2 aktive
  -- edildiginde H4 "calisan gorev olmadan oda temizleniyor olamaz" der;
  -- gecmis satirlar icin sahte baslama zamani/atama UYDURULMAZ.
  if exists (select 1 from public.pms_odalar where temizlik_durumu = 'temizleniyor') then
    raise exception
      'ONKOSUL: % oda `temizleniyor` durumunda. Faz 2 oncesi bu isler '
      'operasyonel olarak tamamlanmali ya da durdurulmali; migration '
      'gecmis uydurmaz.',
      (select count(*) from public.pms_odalar where temizlik_durumu = 'temizleniyor');
  end if;

  -- Bu migration daha once uygulanmis mi?
  if to_regclass('public.pms_housekeeping_gorevleri') is not null then
    raise notice 'pms_housekeeping_gorevleri zaten var; adimlar idempotent.';
  end if;
end;
$$;


begin;


-- ============================================================================
-- 1) MODÜL KAYDI  (mimari §16.1)
-- ----------------------------------------------------------------------------
-- Beş sütunun beşi de yazılır. `kategori` NOT NULL ve varsayılansızdır.
-- `sira = 49`: `onburo` kategorisinde en yüksek değer 48 (`pms_folio`);
-- 49 globalde de boştur (sonraki kullanılan 60). Repo verisinden ölçüldü.
-- `aktif = false`: modül KAPALI doğar. `auth_yetki_var()` `m.aktif is true`
-- şart koştuğu için bu tek başına her okuma ve komutu kapatır.
-- ============================================================================
insert into public.moduller (kod, ad, kategori, sira, aktif) values
  ('pms_housekeeping', 'Kat Hizmetleri', 'onburo', 49, false)
on conflict (kod) do nothing;


-- ============================================================================
-- 2) ATAMA HEDEF ANAHTARI  (mimari §4.2)
-- ----------------------------------------------------------------------------
-- Görevin kaynak ataması bileşik FK ile bağlanır: (kaynak_atama_id, oda_id,
-- otel_id). Bunun hedefi `pms_oda_atamalari(id, oda_id, otel_id)` benzersiz
-- anahtarıdır ve Faz 1'de YOKTUR — Faz 2 ekler.
--
-- Neden bileşik: kaynak atamanın oda ve otelinin görevinkiyle aynı olduğunu
-- YAPISAL olarak kanıtlar. Tek kolonlu FK bunu kanıtlayamaz.
-- ============================================================================
do $$
begin
  if not exists (select 1 from pg_constraint
                  where conname = 'pms_oda_atamalari_id_oda_otel_key') then
    alter table public.pms_oda_atamalari
      add constraint pms_oda_atamalari_id_oda_otel_key unique (id, oda_id, otel_id);
  end if;
end;
$$;


-- ============================================================================
-- 3) GÖREV TABLOSU  (mimari §4.1)
-- ============================================================================
create table if not exists public.pms_housekeeping_gorevleri (
  id                  uuid primary key default gen_random_uuid(),
  otel_id             public.otel_id not null,
  oda_id              uuid not null,

  gorev_tipi          text not null,
  durum               text not null default 'bekliyor',

  kaynak_atama_id     uuid,
  onceki_gorev_id     uuid,
  atanan_kullanici_id uuid,

  oncelik             smallint not null default 2,
  notlar              text,
  hedef_zamani        timestamptz,

  baslama_zamani      timestamptz,
  bitis_zamani        timestamptz,
  kontrol_zamani      timestamptz,
  kontrol_eden        uuid,
  iptal_zamani        timestamptz,
  iptal_nedeni        text,

  -- Oluşturma kaynağı ve aktörü (mimari §4.1.1).
  -- `olusturan` NULLABLE'dır: sistem/yaşam döngüsü üreticilerinin
  -- kimliklendirilmiş bir ERP aktörü olmayabilir. Sentinel kullanıcı
  -- YARATILMAZ; aktör otoritesi denetim izi satırındadır.
  olusturma_kaynagi   text not null default 'kullanici',
  olusturan           uuid,

  olusturma_tarihi    timestamptz not null default now(),
  guncelleme_tarihi   timestamptz not null default now(),
  surum               bigint not null default 1,

  -- Oluşturma alındısı: kalıcı tekilleştirme.
  istek_anahtari      uuid not null,
  istek_ozeti         text not null,
  -- Son etkin komut alındısı: sınırlı tekrar garantisi (§12.2, §12.4).
  son_islem_anahtari  uuid not null,
  son_islem_ozeti     text not null,

  -- Bileşik hedef anahtar: oda göstergesi ve öncül FK'si buna bağlanır.
  constraint pms_housekeeping_gorevleri_id_oda_otel_key unique (id, oda_id, otel_id)
);


-- ============================================================================
-- 4) ODA GÖSTERGESİ  (mimari §4.2)
-- ----------------------------------------------------------------------------
-- Odanın GÜNCEL temizlik döngüsünü hangi görevin desteklediğini söyler.
-- İkinci bir durum alanı DEĞİLDİR. Bileşik FK, göstergenin aynı oda ve otele
-- ait bir görevi işaret etmesini yapısal olarak zorunlu kılar; böylece eski
-- bir görev daha yeni bir döngüyü sertifikalayamaz.
-- ============================================================================
alter table public.pms_odalar
  add column if not exists temizlik_gorevi_id uuid;


-- ============================================================================
-- 5) YABANCI ANAHTARLAR  (mimari §4.2)
-- ----------------------------------------------------------------------------
-- Hepsi ON UPDATE RESTRICT / ON DELETE RESTRICT: geçmiş görevler kaskatla
-- silinmez. Kaynak atama, kendisine dayanan bir kat hizmeti geçmişi varken
-- taşınamaz/silinemez — bu KASITLI olarak Faz 1'den daha katı bir kısıttır.
--
-- NULL yapılabilir bileşik referanslar MATCH SIMPLE semantiğindedir: kaynak
-- ya da öncül NULL ise ilişki yok sayılır. Dolu ise oda ve otel EŞLEŞMEK
-- ZORUNDADIR.
-- ============================================================================
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'pms_housekeeping_oda_fk') then
    alter table public.pms_housekeeping_gorevleri
      add constraint pms_housekeeping_oda_fk
      foreign key (oda_id, otel_id) references public.pms_odalar (id, otel_id)
      on update restrict on delete restrict;
  end if;

  if not exists (select 1 from pg_constraint where conname = 'pms_housekeeping_kaynak_atama_fk') then
    alter table public.pms_housekeeping_gorevleri
      add constraint pms_housekeeping_kaynak_atama_fk
      foreign key (kaynak_atama_id, oda_id, otel_id)
      references public.pms_oda_atamalari (id, oda_id, otel_id)
      on update restrict on delete restrict;
  end if;

  if not exists (select 1 from pg_constraint where conname = 'pms_housekeeping_onceki_gorev_fk') then
    alter table public.pms_housekeeping_gorevleri
      add constraint pms_housekeeping_onceki_gorev_fk
      foreign key (onceki_gorev_id, oda_id, otel_id)
      references public.pms_housekeeping_gorevleri (id, oda_id, otel_id)
      on update restrict on delete restrict;
  end if;

  if not exists (select 1 from pg_constraint where conname = 'pms_housekeeping_atanan_fk') then
    alter table public.pms_housekeeping_gorevleri
      add constraint pms_housekeeping_atanan_fk
      foreign key (atanan_kullanici_id) references public.kullanicilar (id)
      on update restrict on delete restrict;
  end if;

  if not exists (select 1 from pg_constraint where conname = 'pms_housekeeping_olusturan_fk') then
    alter table public.pms_housekeeping_gorevleri
      add constraint pms_housekeeping_olusturan_fk
      foreign key (olusturan) references public.kullanicilar (id)
      on update restrict on delete restrict;
  end if;

  if not exists (select 1 from pg_constraint where conname = 'pms_housekeeping_kontrol_eden_fk') then
    alter table public.pms_housekeeping_gorevleri
      add constraint pms_housekeeping_kontrol_eden_fk
      foreign key (kontrol_eden) references public.kullanicilar (id)
      on update restrict on delete restrict;
  end if;

  -- Oda göstergesi -> görev. Dairesel FK'dir ve sorun DEĞİLDİR: görev satırı
  -- her zaman önce eklenir, gösterge sonra yazılır.
  if not exists (select 1 from pg_constraint where conname = 'pms_odalar_temizlik_gorevi_fk') then
    alter table public.pms_odalar
      add constraint pms_odalar_temizlik_gorevi_fk
      foreign key (temizlik_gorevi_id, id, otel_id)
      references public.pms_housekeeping_gorevleri (id, oda_id, otel_id)
      on update restrict on delete restrict;
  end if;
end;
$$;


-- ============================================================================
-- 6) CHECK KISITLARI  (mimari §4.3 ve §4.1.1)
-- ----------------------------------------------------------------------------
-- Çapraz tablo gerçekleri BURADA DEĞİL, FK'lerde ve kısıt tetikleyicilerinde
-- yaşar. CHECK ifadeleri başka tabloyu sorgulamaz.
-- Her `add constraint` ayrı ve idempotenttir.
-- ============================================================================
do $$
declare
  v_ad text;
  v_sql text;
  v_liste text[][] := array[
    ['pms_hk_durum_chk',
     'durum in (''bekliyor'',''temizleniyor'',''tamamlandi'',''kontrol_edildi'',''iptal'')'],
    ['pms_hk_tip_chk',
     'gorev_tipi in (''cikis_temizligi'',''konaklama_temizligi'',''ekstra_temizlik'')'],
    ['pms_hk_oncelik_chk', 'oncelik between 1 and 3'],
    ['pms_hk_surum_chk',   'surum > 0'],
    ['pms_hk_notlar_chk',
     'notlar is null or (notlar = btrim(notlar) and notlar <> '''' and length(notlar) <= 1000)'],
    ['pms_hk_istek_ozeti_chk',     'istek_ozeti ~ ''^[0-9a-f]{64}$'''],
    ['pms_hk_son_islem_ozeti_chk', 'son_islem_ozeti ~ ''^[0-9a-f]{64}$'''],
    ['pms_hk_zaman_sonlu_chk',
     'isfinite(olusturma_tarihi) and isfinite(guncelleme_tarihi)
      and (hedef_zamani   is null or isfinite(hedef_zamani))
      and (baslama_zamani is null or isfinite(baslama_zamani))
      and (bitis_zamani   is null or isfinite(bitis_zamani))
      and (kontrol_zamani is null or isfinite(kontrol_zamani))
      and (iptal_zamani   is null or isfinite(iptal_zamani))'],
    ['pms_hk_zaman_sira_chk',
     '(baslama_zamani is null or baslama_zamani >= olusturma_tarihi)
      and (bitis_zamani   is null or (baslama_zamani is not null and bitis_zamani >= baslama_zamani))
      and (kontrol_zamani is null or (bitis_zamani   is not null and kontrol_zamani >= bitis_zamani))
      and (iptal_zamani   is null or (iptal_zamani >= olusturma_tarihi
                                      and (baslama_zamani is null or iptal_zamani >= baslama_zamani)))'],
    ['pms_hk_onceki_kendisi_chk', 'onceki_gorev_id is null or onceki_gorev_id <> id'],
    ['pms_hk_kontrol_ikili_chk',  '(kontrol_eden is null) = (kontrol_zamani is null)'],
    ['pms_hk_kontrol_farkli_chk',
     'kontrol_eden is null or atanan_kullanici_id is null or kontrol_eden <> atanan_kullanici_id'],
    ['pms_hk_kaynak_gerekli_chk',
     'gorev_tipi not in (''cikis_temizligi'',''konaklama_temizligi'') or kaynak_atama_id is not null'],
    ['pms_hk_iptal_neden_chk',
     'iptal_nedeni is null or iptal_nedeni in
       (''operasyonel'',''devir'',''yeniden_temizlik'',''cikis_ile_yenilendi'',
        ''oda_bloke'',''oda_ariza'',''oda_pasif'')'],
    ['pms_hk_durum_matris_chk',
     'case durum
        when ''bekliyor'' then
          baslama_zamani is null and bitis_zamani is null
          and kontrol_zamani is null and iptal_zamani is null and iptal_nedeni is null
        when ''temizleniyor'' then
          atanan_kullanici_id is not null and baslama_zamani is not null
          and bitis_zamani is null and kontrol_zamani is null
          and iptal_zamani is null and iptal_nedeni is null
        when ''tamamlandi'' then
          atanan_kullanici_id is not null and baslama_zamani is not null
          and bitis_zamani is not null and kontrol_zamani is null
          and iptal_zamani is null and iptal_nedeni is null
        when ''kontrol_edildi'' then
          atanan_kullanici_id is not null and baslama_zamani is not null
          and bitis_zamani is not null and kontrol_zamani is not null
          and iptal_zamani is null and iptal_nedeni is null
        when ''iptal'' then
          iptal_zamani is not null and iptal_nedeni is not null
          and bitis_zamani is null and kontrol_zamani is null
          and (baslama_zamani is null or atanan_kullanici_id is not null)
        else false
      end'],
    ['pms_hk_kaynak_kodu_chk',     'olusturma_kaynagi in (''kullanici'',''checkout'',''sistem'')'],
    ['pms_hk_kullanici_aktor_chk', 'olusturma_kaynagi <> ''kullanici'' or olusturan is not null'],
    ['pms_hk_checkout_tip_chk',    '(olusturma_kaynagi = ''checkout'') = (gorev_tipi = ''cikis_temizligi'')'],
    ['pms_hk_sistem_tip_chk',      'olusturma_kaynagi <> ''sistem'' or gorev_tipi = ''ekstra_temizlik''']
  ];
  i int;
begin
  for i in 1 .. array_length(v_liste, 1) loop
    v_ad  := v_liste[i][1];
    v_sql := v_liste[i][2];
    if not exists (select 1 from pg_constraint where conname = v_ad) then
      execute format('alter table public.pms_housekeeping_gorevleri add constraint %I check (%s)',
                     v_ad, v_sql);
    end if;
  end loop;
end;
$$;


-- ============================================================================
-- 7) İNDEKSLER  (mimari §21.1)
-- ----------------------------------------------------------------------------
-- Boş tabloya kurulduğu için `concurrently` gerekmez ve transaction içinde
-- kalınır. Kısmi benzersiz indeksler yapısal koruma katmanıdır: RPC ön
-- kontrolü kaçarsa bunlar tutar.
-- ============================================================================

-- ODA BAŞINA TEK BİTMEMİŞ GÖREV. Adım 1'in en önemli yapısal kısıtı.
create unique index if not exists pms_housekeeping_aktif_oda_uniq
  on public.pms_housekeeping_gorevleri (otel_id, oda_id)
  where durum in ('bekliyor', 'temizleniyor');

-- Kalıcı oluşturma alındısı: TÜM geçmişi kapsar, tamamlanmış/iptal dahil.
create unique index if not exists pms_housekeeping_istek_uniq
  on public.pms_housekeeping_gorevleri (otel_id, istek_anahtari);

-- Gerçek bir çıkış başına TEK çıkış temizliği. İptal/tamamlanmış geçmiş de
-- kapsamdadır: iptal, çıkış tekilleştirme kanıtını SİLMEZ.
create unique index if not exists pms_housekeeping_cikis_kaynak_uniq
  on public.pms_housekeeping_gorevleri (otel_id, kaynak_atama_id)
  where gorev_tipi = 'cikis_temizligi';

-- Öncül başına TEK ardıl: aynı işi iki kez yeniden açma engellenir.
create unique index if not exists pms_housekeeping_onceki_uniq
  on public.pms_housekeeping_gorevleri (otel_id, onceki_gorev_id)
  where onceki_gorev_id is not null;

-- Sorgu indeksleri.
create index if not exists pms_housekeeping_otel_tarih_idx
  on public.pms_housekeeping_gorevleri (otel_id, olusturma_tarihi desc, id desc);

create index if not exists pms_housekeeping_oda_tarih_idx
  on public.pms_housekeeping_gorevleri (otel_id, oda_id, olusturma_tarihi desc, id desc);

create index if not exists pms_housekeeping_calisan_aktif_idx
  on public.pms_housekeeping_gorevleri (otel_id, atanan_kullanici_id, olusturma_tarihi, id)
  where durum in ('bekliyor', 'temizleniyor');

-- Kaynak FK bakımı: referans eden kolon sırasıyla.
create index if not exists pms_housekeeping_kaynak_atama_idx
  on public.pms_housekeeping_gorevleri (kaynak_atama_id, oda_id, otel_id)
  where kaynak_atama_id is not null;

-- Oda göstergesi FK bakımı.
create index if not exists pms_odalar_temizlik_gorevi_idx
  on public.pms_odalar (temizlik_gorevi_id)
  where temizlik_gorevi_id is not null;


-- ============================================================================
-- 8) PAYLAŞILAN OTEL DEĞİŞMEZLİĞİ  (mimari §4.4.1)
-- ----------------------------------------------------------------------------
-- Güncellenebilir her PMS tablosu bunu taşır. Muaf iki tablo
-- (`pms_folio_hareketleri`, `pms_folio_odemeler`) append-only'dir; UPDATE
-- yapısal olarak imkânsız olduğu için tetikleyiciye gerek duymazlar. Görev
-- tablosu BİLEREK güncellenebilirdir, dolayısıyla muafiyet geçerli değildir.
--
-- İkinci bir özel otel-değişmezlik mekanizması YAZILMAZ; geçiş bekçisi kendi
-- değişmez-alan sözleşmesini ayrıca uygular ve bu tetikleyici onun üstüne
-- binen derinlemesine savunmadır.
-- ============================================================================
drop trigger if exists phase0_otel_degismez on public.pms_housekeeping_gorevleri;
create trigger phase0_otel_degismez before update of otel_id
  on public.pms_housekeeping_gorevleri
  for each row execute function phase0_private.otel_degismez();


-- ============================================================================
-- 9) RLS  (mimari §15)
-- ----------------------------------------------------------------------------
-- İşleme özgü politika: yalnız GERÇEKTEN açılan işlem için politika yazılır.
-- Görev DML'i uygulama rollerine VERİLMEDİĞİ için INSERT/UPDATE/DELETE
-- politikası yoktur — simetri uğruna dört politika eklenmez.
-- ============================================================================
alter table public.pms_housekeeping_gorevleri enable row level security;

-- ÖNCE HEPSİNİ AL. `authenticated` listede olmak ZORUNDA: varsayılan
-- ayrıcalıklar tabloya ALL vermiş olabilir ve yalnız public/anon geri almak
-- "yazma yok" sözleşmesini SESSİZCE etkisiz bırakır (6 Eylül dersi).
revoke all on table public.pms_housekeeping_gorevleri from public, anon, authenticated;

-- Servis rolünün miras ayrıcalıkları da nötrlenir. Adım 1'de service_role
-- görev API'si YOKTUR; sonradan gerekirse ayrı bir karar olarak verilir.
revoke all on table public.pms_housekeeping_gorevleri from service_role;

-- Yalnız okuma. Tüm mutasyonlar amaca özel RPC'lerden geçer.
grant select on public.pms_housekeeping_gorevleri to authenticated;

drop policy if exists pms_housekeeping_gorevleri_select on public.pms_housekeeping_gorevleri;
create policy pms_housekeeping_gorevleri_select
  on public.pms_housekeeping_gorevleri
  for select to authenticated
  using (public.auth_erp_kullanicisi() is true
         and public.auth_yetki_var('pms_housekeeping','goruntule') is true
         and public.auth_otel_erisim(otel_id::text) is true);

-- Kısıtlayıcı otel sınırı: izin verici politikaların HEPSİNİN üstüne AND'lenir.
-- Biri gevşetilse bile otel sınırı bunu tutar.
drop policy if exists phase0_otel_kisit on public.pms_housekeeping_gorevleri;
create policy phase0_otel_kisit
  on public.pms_housekeeping_gorevleri
  as restrictive for all to authenticated
  using (public.auth_erp_kullanicisi() is true
         and public.auth_otel_erisim(otel_id::text) is true)
  with check (public.auth_erp_kullanicisi() is true
              and public.auth_otel_erisim(otel_id::text) is true);


-- ============================================================================
-- 10) DOĞRULAMA — COMMIT'TEN ÖNCE
-- ----------------------------------------------------------------------------
-- "Çalıştı" yeterli değil. Her kontrol GERÇEKTEN ölçülebilir bir şeyi ölçer;
-- sıfır dönen bir sorgu "sorun yok" değil, "hiçbir şey ölçmedim" de olabilir.
-- ============================================================================
do $$
declare n int;
begin
  -- Tablo ve RLS
  if to_regclass('public.pms_housekeeping_gorevleri') is null then
    raise exception 'DOGRULAMA: gorev tablosu yok';
  end if;
  if not (select relrowsecurity from pg_class where oid = 'public.pms_housekeeping_gorevleri'::regclass) then
    raise exception 'DOGRULAMA: RLS acik degil';
  end if;

  -- Politikalar: tam olarak biri izin verici SELECT, biri kısıtlayıcı ALL.
  select count(*) into n from pg_policy
   where polrelid = 'public.pms_housekeeping_gorevleri'::regclass;
  if n <> 2 then raise exception 'DOGRULAMA: politika sayisi % (2 bekleniyor)', n; end if;

  select count(*) into n from pg_policy
   where polrelid = 'public.pms_housekeeping_gorevleri'::regclass and not polpermissive;
  if n <> 1 then raise exception 'DOGRULAMA: kisitlayici politika % (1 bekleniyor)', n; end if;

  -- ACL: authenticated yalnız SELECT; yazma ayricaligi OLMAMALI.
  if not has_table_privilege('authenticated', 'public.pms_housekeeping_gorevleri', 'SELECT') then
    raise exception 'DOGRULAMA: authenticated SELECT alamamis';
  end if;
  if has_table_privilege('authenticated', 'public.pms_housekeeping_gorevleri', 'INSERT')
     or has_table_privilege('authenticated', 'public.pms_housekeeping_gorevleri', 'UPDATE')
     or has_table_privilege('authenticated', 'public.pms_housekeeping_gorevleri', 'DELETE') then
    raise exception 'DOGRULAMA: authenticated gorev tablosunda YAZMA ayricaligi tasiyor';
  end if;
  if has_table_privilege('anon', 'public.pms_housekeeping_gorevleri', 'SELECT') then
    raise exception 'DOGRULAMA: anon gorev tablosunu okuyabiliyor';
  end if;

  -- Kısmi benzersiz indeksler: ADI degil, TANIMI dogrulanir.
  select count(*) into n from pg_index i join pg_class c on c.oid = i.indexrelid
   where c.relname = 'pms_housekeeping_aktif_oda_uniq' and i.indisunique
     and pg_get_expr(i.indpred, i.indrelid) is not null;
  if n <> 1 then raise exception 'DOGRULAMA: aktif_oda_uniq kismi benzersiz degil'; end if;

  select count(*) into n from pg_index i join pg_class c on c.oid = i.indexrelid
   where c.relname in ('pms_housekeeping_istek_uniq',
                       'pms_housekeeping_cikis_kaynak_uniq',
                       'pms_housekeeping_onceki_uniq')
     and i.indisunique;
  if n <> 3 then raise exception 'DOGRULAMA: benzersiz indekslerden % tanesi eksik/unique degil', 3 - n; end if;

  -- Bileşik FK'ler gerçekten üç kolonlu mu?
  select count(*) into n from pg_constraint
   where conname in ('pms_housekeeping_kaynak_atama_fk',
                     'pms_housekeeping_onceki_gorev_fk',
                     'pms_odalar_temizlik_gorevi_fk')
     and contype = 'f' and array_length(conkey, 1) = 3;
  if n <> 3 then raise exception 'DOGRULAMA: bilesik FK sayisi % (3 bekleniyor)', n; end if;

  -- Oda FK'si iki kolonlu.
  if not exists (select 1 from pg_constraint
                  where conname = 'pms_housekeeping_oda_fk'
                    and contype = 'f' and array_length(conkey, 1) = 2) then
    raise exception 'DOGRULAMA: oda FK bilesik degil';
  end if;

  -- Paylasilan otel degismezligi bagli mi?
  if not exists (select 1 from pg_trigger
                  where tgrelid = 'public.pms_housekeeping_gorevleri'::regclass
                    and tgname = 'phase0_otel_degismez' and not tgisinternal) then
    raise exception 'DOGRULAMA: phase0_otel_degismez gorev tablosuna baglanmamis';
  end if;

  -- Modul kaydi: bes alan da dolu ve KAPALI.
  if not exists (select 1 from public.moduller
                  where kod = 'pms_housekeeping' and ad = 'Kat Hizmetleri'
                    and kategori = 'onburo' and sira = 49 and aktif = false) then
    raise exception 'DOGRULAMA: pms_housekeeping modul kaydi beklenen degerlerde degil';
  end if;

  -- Atama hedef anahtari.
  if not exists (select 1 from pg_constraint
                  where conname = 'pms_oda_atamalari_id_oda_otel_key' and contype = 'u') then
    raise exception 'DOGRULAMA: atama hedef anahtari yok';
  end if;

  raise notice 'DOGRULAMA (yapisal): tum kontroller gecti.';
end;
$$;




-- ============================================================================
-- 11) GÖREV GEÇİŞ BEKÇİSİ  (mimari §13.3)
-- ----------------------------------------------------------------------------
-- SECURITY INVOKER: ek yetkiye ihtiyacı yok, yalnız OLD/NEW inceler. Görev
-- tablosunda hiçbir uygulama rolünün DML ayrıcalığı olmadığı için bu bekçi
-- HERKESE uygulanır — özel motor da dâhil. Motor yalnız yasal geçiş yapar.
--
-- Artım 1'in satır-şekli CHECK'leri yerinde kalır; bu bekçi onların üstüne
-- GEÇİŞ yasalarını koyar. İkisi çelişmez: CHECK "bu satır tutarlı mı",
-- bekçi "bu satırdan şu satıra geçilebilir mi" sorusunu yanıtlar.
-- ============================================================================
create or replace function public.pms_housekeeping_gorev_koruma()
returns trigger language plpgsql
set search_path = pg_catalog, public, pg_temp as $fn$
declare
  v_gecis text;
begin
  -- ---- SİLME: operasyonel silme HER ZAMAN reddedilir ----
  if tg_op = 'DELETE' then
    raise exception
      'Kat hizmeti gorevi silinemez (%). Gecmis kayittir; iptal edin.', old.id
      using errcode = '42501';
  end if;

  -- ---- EKLEME: yalnız geçerli başlangıç durumu ----
  if tg_op = 'INSERT' then
    if new.durum <> 'bekliyor' then
      raise exception 'Yeni gorev yalniz `bekliyor` durumunda acilir (verilen: %)',
        new.durum using errcode = '42501';
    end if;
    if new.baslama_zamani is not null or new.bitis_zamani is not null
       or new.kontrol_zamani is not null or new.iptal_zamani is not null
       or new.kontrol_eden is not null or new.iptal_nedeni is not null then
      raise exception 'Yeni gorevde olay damgasi olamaz' using errcode = '42501';
    end if;
    if new.surum <> 1 then
      raise exception 'Yeni gorev surum 1 ile acilir (verilen: %)', new.surum
        using errcode = '42501';
    end if;
    return new;
  end if;

  -- ================= GÜNCELLEME =================

  -- ---- DEĞİŞMEZ KOLONLAR ----
  if new.id                is distinct from old.id
     or new.otel_id        is distinct from old.otel_id
     or new.oda_id         is distinct from old.oda_id
     or new.gorev_tipi     is distinct from old.gorev_tipi
     or new.olusturma_kaynagi is distinct from old.olusturma_kaynagi
     or new.kaynak_atama_id is distinct from old.kaynak_atama_id
     or new.onceki_gorev_id is distinct from old.onceki_gorev_id
     or new.olusturan      is distinct from old.olusturan
     or new.olusturma_tarihi is distinct from old.olusturma_tarihi
     or new.istek_anahtari is distinct from old.istek_anahtari
     or new.istek_ozeti    is distinct from old.istek_ozeti then
    raise exception 'Gorevin degismez alanlari guncellenemez' using errcode = '42501';
  end if;

  -- ---- TERMİNAL DURUM DONDURULMUŞ ----
  if old.durum in ('iptal', 'kontrol_edildi') then
    raise exception 'Terminal gorev (%) degistirilemez', old.durum
      using errcode = '42501';
  end if;

  -- ---- TEK İZİNLİ İNCELTME: tamamlandi -> kontrol_edildi ----
  if old.durum = 'tamamlandi' then
    if new.durum <> 'kontrol_edildi' then
      raise exception
        'Tamamlanmis gorevin tek gecisi kontrol_edildi''dir (istenen: %). '
        'Yeniden is icin ardil gorev acin.', new.durum using errcode = '42501';
    end if;
    -- Yalnız denetim alanları + sistem alanları değişebilir.
    if new.atanan_kullanici_id is distinct from old.atanan_kullanici_id
       or new.baslama_zamani is distinct from old.baslama_zamani
       or new.bitis_zamani   is distinct from old.bitis_zamani
       or new.oncelik        is distinct from old.oncelik
       or new.hedef_zamani   is distinct from old.hedef_zamani
       or new.notlar         is distinct from old.notlar then
      raise exception 'Kontrol adiminda yalniz denetim alanlari yazilir'
        using errcode = '42501';
    end if;
  end if;

  -- ---- YAZ-BİR-KEZ DAMGALAR ----
  if old.baslama_zamani is not null and new.baslama_zamani is distinct from old.baslama_zamani then
    raise exception 'baslama_zamani yaz-bir-kez' using errcode = '42501';
  end if;
  if old.bitis_zamani is not null and new.bitis_zamani is distinct from old.bitis_zamani then
    raise exception 'bitis_zamani yaz-bir-kez' using errcode = '42501';
  end if;
  if old.kontrol_zamani is not null and new.kontrol_zamani is distinct from old.kontrol_zamani then
    raise exception 'kontrol_zamani yaz-bir-kez' using errcode = '42501';
  end if;
  if old.iptal_zamani is not null and new.iptal_zamani is distinct from old.iptal_zamani then
    raise exception 'iptal_zamani yaz-bir-kez' using errcode = '42501';
  end if;
  if old.kontrol_eden is not null and new.kontrol_eden is distinct from old.kontrol_eden then
    raise exception 'kontrol_eden yaz-bir-kez' using errcode = '42501';
  end if;

  -- ---- BAŞLADIKTAN SONRA ATANAN DONDURULUR ----
  if old.baslama_zamani is not null
     and new.atanan_kullanici_id is distinct from old.atanan_kullanici_id then
    raise exception
      'Is basladiktan sonra atanan degistirilemez; devir icin iptal + ardil'
      using errcode = '42501';
  end if;

  -- ---- GEÇİŞ MATRİSİ ----
  v_gecis := old.durum || '->' || new.durum;
  if v_gecis not in (
       'bekliyor->bekliyor',        -- atama/planlama/not degisiklikleri
       'bekliyor->temizleniyor',
       'bekliyor->iptal',
       'temizleniyor->temizleniyor',-- not degisikligi
       'temizleniyor->tamamlandi',
       'temizleniyor->iptal',
       'tamamlandi->kontrol_edildi'
     ) then
    raise exception 'Gecersiz gorev gecisi: %', v_gecis using errcode = '42501';
  end if;

  -- ---- SÜRÜM İLERLEYİŞİ ----
  -- Her GERÇEK degisiklik surumu TAM BIR artirir. Degisiklik yoksa surum de
  -- degismemelidir; motor no-op'ta zaten UPDATE atmaz.
  if new.surum <> old.surum + 1 then
    raise exception 'Surum tam bir artmali (% -> %)', old.surum, new.surum
      using errcode = '42501';
  end if;

  -- ---- İSTEMCİ DAMGASI GERİYE ALINAMAZ ----
  if new.guncelleme_tarihi < old.guncelleme_tarihi then
    raise exception 'guncelleme_tarihi geriye alinamaz' using errcode = '42501';
  end if;

  return new;
end;
$fn$;

drop trigger if exists pms_housekeeping_gorev_koruma on public.pms_housekeeping_gorevleri;
create trigger pms_housekeeping_gorev_koruma
  before insert or update or delete on public.pms_housekeeping_gorevleri
  for each row execute function public.pms_housekeeping_gorev_koruma();


-- ============================================================================
-- 12) ODA BEKÇİSİ  (mimari §13.3.1, §13.4)
-- ----------------------------------------------------------------------------
-- SECURITY INVOKER OLMASI ZORUNLU: `current_user` ile uygulama rolü
-- yazmasını güvenilir iç yazmadan ayırt eder. DEFINER olsaydı her çağrı
-- sahibin kimliğiyle görünür ve ayrım imkânsızlaşırdı.
--
-- Güvenilir yazar, kat hizmeti nesnelerinin SAHİBİDİR. Uygulama rollerinin
-- o role üyeliği yoktur; GUC, başlık ya da `pg_trigger_depth()` gibi
-- taklit edilebilir hiçbir şey yetki kanıtı sayılmaz.
--
-- TETİKLEYİCİ SIRASI: adı `pms_housekeeping_oda_koruma`; alfabetik olarak
-- `phase0_otel_degismez`ten sonra, `pms_oda_*` bekçilerinden ÖNCE ateşlenir.
-- Böylece istemcinin GÖNDERDİĞİ ham NEW'i, Faz 1 kontrolleri onu kabul
-- etmeden önce yargılar.
-- ============================================================================
create or replace function public.pms_housekeeping_oda_koruma()
returns trigger language plpgsql
set search_path = pg_catalog, public, pg_temp as $fn$
declare
  v_sahip text;
begin
  v_sahip := pg_catalog.pg_get_userbyid(
               (select relowner from pg_catalog.pg_class
                 where oid = 'public.pms_housekeeping_gorevleri'::regclass));

  -- Güvenilir iç yazar: kısıtlar, FK'ler ve ertelenmiş tutarlılık yine
  -- geçerlidir. Ayrıcalıklı bağlam tutarsız veri yazma ruhsatı değildir.
  if current_user = v_sahip then
    return new;
  end if;

  -- ================= UYGULAMA ROLÜ YOLU =================

  if tg_op = 'INSERT' then
    -- Yeni oda temiz/denetlenmis DOGAMAZ ve gostergeyle acilmaz.
    if new.temizlik_gorevi_id is not null then
      raise exception 'Oda, temizlik gorevi gostergesiyle olusturulamaz'
        using errcode = '42501';
    end if;
    if new.temizlik_durumu <> 'kirli' then
      raise exception
        'Yeni oda `kirli` dogar; temizlik yalniz kat hizmeti akisiyla kazanilir (verilen: %)',
        new.temizlik_durumu using errcode = '42501';
    end if;
    return new;
  end if;

  -- ---- GÖSTERGE uygulama rolünce DEĞİŞTİRİLEMEZ ----
  if new.temizlik_gorevi_id is distinct from old.temizlik_gorevi_id then
    raise exception 'Oda temizlik gorevi gostergesi dogrudan degistirilemez'
      using errcode = '42501';
  end if;

  -- ---- CHECK-IN: bos -> dolu ----
  if old.kullanim_durumu = 'bos' and new.kullanim_durumu = 'dolu' then
    -- KİLİTLİ ESKİ değer denetlenir. Faz 1 `pms_oda_gecis` NEW'e bakar ve
    -- istemci NEW'i uydurabilir; asil koruma budur.
    if old.temizlik_durumu not in ('temiz', 'kontrol_edildi') then
      raise exception
        'Check-in yalniz temiz/kontrol_edildi odaya yapilir (odanin gercek durumu: %)',
        old.temizlik_durumu using errcode = '42501';
    end if;
    if new.temizlik_durumu is distinct from old.temizlik_durumu then
      raise exception 'Check-in temizlik durumunu degistiremez' using errcode = '42501';
    end if;
    -- Güncel döngü göstergesi EMEKLİ EDİLİR: yeni misafir girdikten sonra
    -- eski tamamlanmis gorev artik denetlenemez.
    new.temizlik_gorevi_id := null;
    return new;
  end if;

  -- ---- ÇIKIŞ: dolu -> bos, kirli olmak zorunda (Faz 1 davranisi korunur) ----
  if old.kullanim_durumu = 'dolu' and new.kullanim_durumu = 'bos' then
    if new.temizlik_durumu <> 'kirli' then
      raise exception 'Cikan oda kirli isaretlenmeli' using errcode = '42501';
    end if;
    return new;
  end if;

  -- ---- DİĞER HER YAZMA: temizlik durumu DEĞİŞEMEZ ----
  if new.temizlik_durumu is distinct from old.temizlik_durumu then
    raise exception
      'Oda temizlik durumu dogrudan degistirilemez; kat hizmeti komutlarini kullanin'
      using errcode = '42501';
  end if;

  return new;
end;
$fn$;

drop trigger if exists pms_housekeeping_oda_koruma on public.pms_odalar;
create trigger pms_housekeeping_oda_koruma
  before insert or update on public.pms_odalar
  for each row execute function public.pms_housekeeping_oda_koruma();


-- ============================================================================
-- 13) TETİKLEYİCİ SIRASI KATALOG DOĞRULAMASI  (mimari §13.3.1)
-- ----------------------------------------------------------------------------
-- Alfabetik sıranın "denk gelmesine" GÜVENİLMEZ; ölçülür.
-- ============================================================================
do $$
declare
  v_sira text[];
  v_beklenen text[] := array[
    'phase0_otel_degismez',
    'pms_housekeeping_oda_koruma',
    'pms_oda_envanter_kontrol',
    'pms_oda_gecis',
    'pms_odalar_guncelleme'
  ];
begin
  select array_agg(tgname order by tgname) into v_sira
    from pg_trigger
   where tgrelid = 'public.pms_odalar'::regclass
     and not tgisinternal
     and (tgtype & 2) <> 0;   -- BEFORE

  if v_sira is distinct from v_beklenen then
    raise exception 'TETIKLEYICI SIRASI beklenenden farkli. beklenen=% bulunan=%',
      v_beklenen, v_sira;
  end if;

  if v_sira[2] <> 'pms_housekeeping_oda_koruma' then
    raise exception 'Oda bekcisi 2. sirada degil';
  end if;

  raise notice 'TETIKLEYICI SIRASI dogrulandi: %', v_sira;
end;
$$;


-- ============================================================================
-- 14) H1-H10 ERTELENMİŞ TUTARLILIK KISITLARI  (mimari §7.2)
-- ----------------------------------------------------------------------------
-- DEFERRABLE INITIALLY DEFERRED olmak ZORUNDA: Faz 1 çıkışı odayı
-- rezervasyondan ÖNCE kirletir ve `pms_check_out` yalnız kendi üç kısıtını
-- adıyla erteler. Yeni kısıtlar o listeye kendiliğinden katılmaz; bu yüzden
-- BAŞTAN ertelenmiş doğarlar.
--
-- SECURITY DEFINER: değişmezi kuran satırlar çağıranın RLS'i altında GİZLİ
-- olabilir ve gizli satır "yok" sanılırsa kontrol sessizce geçer.
--
-- NEW anlık görüntüsüne GÜVENİLMEZ: kuyruğa alınmış olay sırasında satır
-- değişmiş olabilir. Her ikisi de anahtarla YENİDEN OKUNUR.
-- ============================================================================
create or replace function public.pms_housekeeping_tutarlilik_gorev()
returns trigger language plpgsql security definer
set search_path = pg_catalog, public, pg_temp as $fn$
declare
  g record;
  o record;
begin
  select * into g from public.pms_housekeeping_gorevleri
   where id = coalesce(new.id, old.id);
  if not found then return null; end if;          -- satir yok: kontrol edilecek sey yok

  select * into o from public.pms_odalar where id = g.oda_id and otel_id = g.otel_id;
  if not found then
    raise exception 'H8: gorevin odasi bulunamadi (gorev %)', g.id;
  end if;

  -- H2: bitmemis her gorev, odasinin GUNCEL gorevi olmali.
  if g.durum in ('bekliyor', 'temizleniyor')
     and o.temizlik_gorevi_id is distinct from g.id then
    raise exception 'H2: bitmemis gorev (%) odanin guncel gorevi degil', g.id;
  end if;

  -- H9: calisan is yalniz GUNCEL gorevde olabilir.
  if g.durum = 'temizleniyor' and o.temizlik_gorevi_id is distinct from g.id then
    raise exception 'H9: guncel olmayan gorev calisir durumda (%)', g.id;
  end if;

  -- Guncel gorev degilse odanin hazirligini etkileyemez; baska kontrol yok.
  if o.temizlik_gorevi_id is distinct from g.id then
    return null;
  end if;

  -- ---- GUNCEL GOREV: durum <-> oda temizligi ----
  if g.durum = 'bekliyor'       and o.temizlik_durumu <> 'kirli' then
    raise exception 'H3: bekleyen guncel gorev, oda `%` (kirli olmali)', o.temizlik_durumu;
  end if;
  if g.durum = 'temizleniyor'   and o.temizlik_durumu <> 'temizleniyor' then
    raise exception 'H4: calisan guncel gorev, oda `%` (temizleniyor olmali)', o.temizlik_durumu;
  end if;
  if g.durum = 'tamamlandi'     and o.temizlik_durumu <> 'temiz' then
    raise exception 'H5: tamamlanan guncel gorev, oda `%` (temiz olmali)', o.temizlik_durumu;
  end if;
  if g.durum = 'kontrol_edildi' and o.temizlik_durumu <> 'kontrol_edildi' then
    raise exception 'H6: denetlenen guncel gorev, oda `%` (kontrol_edildi olmali)', o.temizlik_durumu;
  end if;
  if g.durum = 'iptal'          and o.temizlik_durumu <> 'kirli' then
    raise exception 'H7: iptal guncel gorev, oda `%` (kirli olmali)', o.temizlik_durumu;
  end if;

  -- H10: kullanilamaz odada calisan is COMMIT edilemez.
  if g.durum = 'temizleniyor'
     and (not o.aktif or o.kullanim_durumu in ('bloke', 'ariza')) then
    raise exception 'H10: kullanilamaz odada calisan is (oda %, aktif=%, kullanim=%)',
      o.oda_no, o.aktif, o.kullanim_durumu;
  end if;

  return null;
end;
$fn$;

create or replace function public.pms_housekeeping_tutarlilik_oda()
returns trigger language plpgsql security definer
set search_path = pg_catalog, public, pg_temp as $fn$
declare
  o record;
  g record;
begin
  select * into o from public.pms_odalar where id = coalesce(new.id, old.id);
  if not found then return null; end if;

  -- H4 tersi: oda `temizleniyor` ise CALISAN guncel gorev SART.
  if o.temizlik_durumu = 'temizleniyor' then
    if o.temizlik_gorevi_id is null then
      raise exception 'H4: oda % temizleniyor ama guncel gorev yok', o.oda_no;
    end if;
    select * into g from public.pms_housekeeping_gorevleri where id = o.temizlik_gorevi_id;
    if not found or g.durum <> 'temizleniyor' then
      raise exception 'H4: oda % temizleniyor ama guncel gorev calismyor', o.oda_no;
    end if;
  end if;

  if o.temizlik_gorevi_id is null then
    return null;                                   -- gostergesiz oda: mesru
  end if;

  select * into g from public.pms_housekeeping_gorevleri where id = o.temizlik_gorevi_id;
  if not found then
    raise exception 'H8: oda % olmayan gorevi gosteriyor', o.oda_no;
  end if;

  -- H8: gosterge ayni oda ve otelde olmali (FK zaten garanti eder; ikinci kat).
  if g.oda_id <> o.id or g.otel_id <> o.otel_id then
    raise exception 'H8: gosterge baska oda/otel gorevini isaret ediyor';
  end if;

  -- Oda tarafindan da ayni eslesme (task tarafiyla simetrik).
  if g.durum = 'bekliyor'       and o.temizlik_durumu <> 'kirli' then
    raise exception 'H3: oda % (%), guncel gorev bekliyor', o.oda_no, o.temizlik_durumu;
  end if;
  if g.durum = 'tamamlandi'     and o.temizlik_durumu <> 'temiz' then
    raise exception 'H5: oda % (%), guncel gorev tamamlandi', o.oda_no, o.temizlik_durumu;
  end if;
  if g.durum = 'kontrol_edildi' and o.temizlik_durumu <> 'kontrol_edildi' then
    raise exception 'H6: oda % (%), guncel gorev kontrol_edildi', o.oda_no, o.temizlik_durumu;
  end if;
  if g.durum = 'iptal'          and o.temizlik_durumu <> 'kirli' then
    raise exception 'H7: oda % (%), guncel gorev iptal', o.oda_no, o.temizlik_durumu;
  end if;

  return null;
end;
$fn$;

drop trigger if exists pms_housekeeping_tutarlilik_gorev on public.pms_housekeeping_gorevleri;
create constraint trigger pms_housekeeping_tutarlilik_gorev
  after insert or update on public.pms_housekeeping_gorevleri
  deferrable initially deferred
  for each row execute function public.pms_housekeeping_tutarlilik_gorev();

drop trigger if exists pms_housekeeping_tutarlilik_oda on public.pms_odalar;
create constraint trigger pms_housekeeping_tutarlilik_oda
  after insert or update on public.pms_odalar
  deferrable initially deferred
  for each row execute function public.pms_housekeeping_tutarlilik_oda();



-- ============================================================================
-- 15) ÖZEL YARDIMCILAR  (mimari §13.2, §14.2)
-- ----------------------------------------------------------------------------
-- `phase0_private` şemasında yaşarlar: PostgREST yalnız `public` şemasını
-- yayınladığı için bu fonksiyonlar REST'ten ÇAĞRILAMAZ. Ayrıca hiçbir
-- uygulama rolüne EXECUTE verilmez.
--
-- Hiçbiri tablo/fonksiyon adı gibi serbest tanımlayıcı almaz; yalnız
-- numaralandırılmış iç eylem kodları kabul edilir.
-- ============================================================================

-- --- 15.1 Çağıran aktör: fail-closed ---------------------------------------
create or replace function phase0_private.hk_aktor()
returns public.kullanicilar
language plpgsql stable security definer
set search_path = pg_catalog, public, pg_temp as $fn$
declare k public.kullanicilar;
begin
  if auth.uid() is null then
    raise exception 'Kimlik dogrulanamadi' using errcode = '42501';
  end if;
  select * into k from public.kullanicilar
   where auth_user_id = auth.uid() and aktif is true;
  if not found then
    raise exception 'Aktif ERP personeli gerekli' using errcode = '42501';
  end if;
  return k;
end;
$fn$;

-- --- 15.2 Hedef çalışan uygunluğu ------------------------------------------
-- Mevcut yetki motorunun üstüne DAR bir adaptör. İkinci bir yetki deposu
-- yaratmaz, hedefin kimliğine BÜRÜNMEZ; `auth_*` yardımcıları çağıranı
-- değerlendirir, bu fonksiyon HEDEFİ değerlendirir.
create or replace function phase0_private.hk_calisan_uygun(
  p_kullanici_id uuid, p_otel public.otel_id)
returns boolean
language sql stable security definer
set search_path = pg_catalog, public, pg_temp as $fn$
  select exists (
    select 1
      from public.kullanicilar k
      join public.yetki_matrisi ym on ym.rol_id = k.rol_id
      join public.moduller m       on m.id = ym.modul_id
     where k.id = p_kullanici_id
       and k.aktif is true
       and k.auth_user_id is not null
       and (k.tum_oteller is true or k.otel_id = p_otel)
       and m.kod = 'pms_housekeeping'
       and m.aktif is true
       and ym.yetki::text in ('kayit', 'tam')
  );
$fn$;

-- --- 15.3 Kanonik parmak izi ------------------------------------------------
-- Sunucu hesaplar; çağıranın verdiği hash ASLA kabul edilmez.
create or replace function phase0_private.hk_ozet(p_zarf jsonb)
returns text
language sql immutable
set search_path = pg_catalog, pg_temp as $fn$
  select encode(sha256(convert_to(jsonb_pretty(p_zarf), 'UTF8')), 'hex');
$fn$;

-- --- 15.4 Modül durumu: paylaşımlı kilit + aktiflik -------------------------
-- Kilit PAYLAŞIMLIDIR: eş zamanlı oda işlemleri birbirinin arkasında
-- sıraya girmez. Devre dışı bırakma işlemi yazma kilidi ister ve uçuştaki
-- komutların bitmesini bekler — tahliye bariyeri budur.
create or replace function phase0_private.hk_modul_acik()
returns boolean
language plpgsql security definer
set search_path = pg_catalog, public, pg_temp as $fn$
declare v boolean;
begin
  select aktif into v from public.moduller where kod = 'pms_housekeeping' for share;
  return coalesce(v, false);
end;
$fn$;

-- --- 15.5 Durum -> oda temizliği izdüşümü -----------------------------------
create or replace function phase0_private.hk_oda_durumu(p_durum text)
returns public.pms_temizlik_durumu
language sql immutable
set search_path = pg_catalog, public, pg_temp as $fn$
  select case p_durum
           when 'bekliyor'       then 'kirli'
           when 'temizleniyor'   then 'temizleniyor'
           when 'tamamlandi'     then 'temiz'
           when 'kontrol_edildi' then 'kontrol_edildi'
           when 'iptal'          then 'kirli'
         end::public.pms_temizlik_durumu;
$fn$;


-- ============================================================================
-- 16) ÖZEL GEÇİŞ/İZDÜŞÜM MOTORU  (mimari §13.2)
-- ----------------------------------------------------------------------------
-- TEK uygulama. Her RPC bunu çağırır; hiçbir RPC kendi durum makinesini
-- yazmaz. Kilit sırası, sürüm/idempotency ve oda izdüşümü burada merkezîdir.
--
-- KİLİT SIRASI (mimari §11.1): calisan -> oda -> gorev -> modul.
-- Rezervasyon/atama kilidi ODA'DAN SONRA ASLA alınmaz; görev komutlarında
-- zaten alınmaz.
--
-- p_eylem yalnız numaralandırılmış iç kodlardan biridir. Serbest SQL,
-- tablo adı ya da durum değeri kabul etmez — genel amaçlı "durumu şu yap"
-- ilkeli YOKTUR.
-- ============================================================================
create or replace function phase0_private.hk_komut(
  p_gorev_id        uuid,
  p_eylem           text,
  p_beklenen_surum  bigint,
  p_islem_anahtari  uuid,
  p_yuk             jsonb default '{}'::jsonb)
returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public, pg_temp as $fn$
declare
  a       public.kullanicilar;
  g       public.pms_housekeeping_gorevleri;
  o       public.pms_odalar;
  v_oda   uuid;
  v_otel  public.otel_id;
  v_hedef uuid;
  v_ozet  text;
  v_simdi timestamptz;
  v_yeni_durum text;
  v_yeni_atanan uuid;
  v_kontrol_eden uuid;
  v_kontrol_zamani timestamptz;
  v_baslama timestamptz;
  v_bitis   timestamptz;
  v_iptal_z timestamptz;
  v_iptal_n text;
  v_notlar  text;
  v_oncelik smallint;
  v_hedef_z timestamptz;
  v_degisti boolean := false;
begin
  if p_eylem not in ('sahiplen','birak','ata','baslat','tamamla',
                     'kontrol_et','iptal','duzenle') then
    raise exception 'Bilinmeyen ic eylem' using errcode = '42501';
  end if;

  a := phase0_private.hk_aktor();

  -- Yönlendirme için KİLİTSİZ okuma; yetkilendirme burada YAPILMAZ.
  select oda_id, otel_id into v_oda, v_otel
    from public.pms_housekeeping_gorevleri where id = p_gorev_id;
  if v_oda is null then
    raise exception 'Gorev bulunamadi veya erisim yok' using errcode = 'P0002';
  end if;

  -- Otel kapsamı: satırın KENDİ oteline göre; istemciden gelen değere değil.
  if public.auth_otel_erisim(v_otel::text) is not true then
    raise exception 'Gorev bulunamadi veya erisim yok' using errcode = 'P0002';
  end if;

  -- ---- KİLİT 1: ilgili çalışan satırları (FOR SHARE) ----
  -- Kapsam/aktiflik alanları komut sırasında değişmesin.
  v_hedef := nullif(p_yuk->>'hedef_kullanici', '')::uuid;
  perform 1 from public.kullanicilar
   where id in (a.id, coalesce(v_hedef, a.id))
   order by id for share;

  -- ---- KİLİT 2: oda ----
  select * into o from public.pms_odalar
   where id = v_oda and otel_id = v_otel for update;
  if not found then
    raise exception 'Gorevin odasi bulunamadi' using errcode = 'P0002';
  end if;

  -- ---- KİLİT 3: görev (kilit altında YENİDEN oku) ----
  select * into g from public.pms_housekeeping_gorevleri
   where id = p_gorev_id for update;

  -- ---- KİLİT 4: modül ----
  if phase0_private.hk_modul_acik() is not true then
    raise exception 'Kat hizmetleri modulu kapali' using errcode = '42501';
  end if;

  -- ---- IDEMPOTENCY: tam aynı komutun tekrarı ----
  v_ozet := phase0_private.hk_ozet(jsonb_build_object(
    'eylem', p_eylem, 'aktor', a.id, 'otel', v_otel::text, 'gorev', p_gorev_id,
    'beklenen_surum', p_beklenen_surum, 'yuk', p_yuk));

  if g.son_islem_anahtari = p_islem_anahtari then
    if g.son_islem_ozeti = v_ozet then
      return jsonb_build_object('gorev_id', g.id, 'oda_id', o.id, 'otel_id', v_otel,
        'surum', g.surum, 'durum', g.durum, 'atanan', g.atanan_kullanici_id,
        'oda_temizlik', o.temizlik_durumu, 'oda_kullanim', o.kullanim_durumu,
        'oda_gorev_id', o.temizlik_gorevi_id, 'tekrar', true);
    end if;
    raise exception 'HK_ISTEK_CAKISMASI: ayni anahtar farkli icerikle gonderildi'
      using errcode = '23505';
  end if;

  -- ---- SÜRÜM ----
  if g.surum <> p_beklenen_surum then
    raise exception 'HK_SURUM_CAKISMASI: beklenen %, guncel %', p_beklenen_surum, g.surum
      using errcode = '40001';
  end if;

  v_simdi := clock_timestamp();

  -- Başlangıç: mevcut değerler
  v_yeni_durum := g.durum;  v_yeni_atanan := g.atanan_kullanici_id;
  v_baslama := g.baslama_zamani; v_bitis := g.bitis_zamani;
  v_kontrol_eden := g.kontrol_eden; v_kontrol_zamani := g.kontrol_zamani;
  v_iptal_z := g.iptal_zamani; v_iptal_n := g.iptal_nedeni;
  v_notlar := g.notlar; v_oncelik := g.oncelik; v_hedef_z := g.hedef_zamani;

  -- ================= EYLEMLER =================
  if p_eylem = 'sahiplen' then
    if public.auth_yetki_var('pms_housekeeping','kayit') is not true then
      raise exception 'Yetki yok' using errcode = '42501'; end if;
    if g.durum <> 'bekliyor' then
      raise exception 'HK_DURUM_CAKISMASI: yalniz bekleyen gorev sahiplenilir' using errcode = '42501'; end if;
    if g.atanan_kullanici_id is not null then
      raise exception 'HK_DURUM_CAKISMASI: gorev zaten atanmis' using errcode = '42501'; end if;
    if phase0_private.hk_calisan_uygun(a.id, v_otel) is not true then
      raise exception 'Bu otelde kat hizmeti gorevi alamazsiniz' using errcode = '42501'; end if;
    if not o.aktif or o.kullanim_durumu in ('bloke','ariza') then
      raise exception 'HK_ODA_KULLANILAMAZ: oda su an calisilamaz (%)' , o.kullanim_durumu
        using errcode = '42501'; end if;
    v_yeni_atanan := a.id; v_degisti := true;

  elsif p_eylem = 'birak' then
    if public.auth_yetki_var('pms_housekeeping','kayit') is not true then
      raise exception 'Yetki yok' using errcode = '42501'; end if;
    if g.durum <> 'bekliyor' or g.atanan_kullanici_id is distinct from a.id then
      raise exception 'HK_DURUM_CAKISMASI: yalniz kendi bekleyen gorevinizi birakabilirsiniz'
        using errcode = '42501'; end if;
    v_yeni_atanan := null; v_degisti := true;

  elsif p_eylem = 'ata' then
    if public.auth_yetki_var('pms_housekeeping','tam') is not true then
      raise exception 'Yetki yok' using errcode = '42501'; end if;
    if g.durum <> 'bekliyor' then
      raise exception 'HK_DURUM_CAKISMASI: yalniz bekleyen gorev atanir' using errcode = '42501'; end if;
    if v_hedef is not null
       and phase0_private.hk_calisan_uygun(v_hedef, v_otel) is not true then
      raise exception 'Hedef calisan bu otelde kat hizmetine uygun degil' using errcode = '42501'; end if;
    v_yeni_atanan := v_hedef;
    v_degisti := v_yeni_atanan is distinct from g.atanan_kullanici_id;

  elsif p_eylem = 'baslat' then
    if public.auth_yetki_var('pms_housekeeping','kayit') is not true then
      raise exception 'Yetki yok' using errcode = '42501'; end if;
    if g.durum <> 'bekliyor' then
      raise exception 'HK_DURUM_CAKISMASI: yalniz bekleyen gorev baslatilir' using errcode = '42501'; end if;
    if g.atanan_kullanici_id is distinct from a.id then
      raise exception 'Yalniz kendi atandiginiz gorevi baslatabilirsiniz' using errcode = '42501'; end if;
    if phase0_private.hk_calisan_uygun(a.id, v_otel) is not true then
      raise exception 'Kat hizmeti yetkiniz artik gecerli degil' using errcode = '42501'; end if;
    if o.temizlik_gorevi_id is distinct from g.id then
      raise exception 'HK_DURUM_CAKISMASI: gorev odanin guncel dongusu degil' using errcode = '42501'; end if;
    if not o.aktif or o.kullanim_durumu in ('bloke','ariza') then
      raise exception 'HK_ODA_KULLANILAMAZ: oda su an calisilamaz (%)', o.kullanim_durumu
        using errcode = '42501'; end if;
    v_yeni_durum := 'temizleniyor'; v_baslama := v_simdi; v_degisti := true;

  elsif p_eylem = 'tamamla' then
    if public.auth_yetki_var('pms_housekeeping','kayit') is not true then
      raise exception 'Yetki yok' using errcode = '42501'; end if;
    if g.durum <> 'temizleniyor' then
      raise exception 'HK_DURUM_CAKISMASI: yalniz calisan gorev tamamlanir' using errcode = '42501'; end if;
    if g.atanan_kullanici_id is distinct from a.id then
      raise exception 'Yalniz isi yapan calisan tamamlayabilir' using errcode = '42501'; end if;
    if o.temizlik_gorevi_id is distinct from g.id then
      raise exception 'HK_DURUM_CAKISMASI: gorev odanin guncel dongusu degil' using errcode = '42501'; end if;
    v_yeni_durum := 'tamamlandi'; v_bitis := v_simdi; v_degisti := true;

  elsif p_eylem = 'kontrol_et' then
    if public.auth_yetki_var('pms_housekeeping','tam') is not true then
      raise exception 'Yetki yok' using errcode = '42501'; end if;
    if g.durum <> 'tamamlandi' then
      raise exception 'HK_DURUM_CAKISMASI: yalniz tamamlanmis gorev denetlenir' using errcode = '42501'; end if;
    if g.atanan_kullanici_id = a.id then
      raise exception 'Kendi isinizi bagimsiz denetleyemezsiniz' using errcode = '42501'; end if;
    if o.temizlik_gorevi_id is distinct from g.id then
      raise exception 'HK_DURUM_CAKISMASI: gorev odanin guncel dongusu degil (bayat denetim)'
        using errcode = '42501'; end if;
    if o.kullanim_durumu <> 'bos' or not o.aktif then
      raise exception 'HK_ODA_KULLANILAMAZ: denetim yalniz aktif bos odada' using errcode = '42501'; end if;
    v_yeni_durum := 'kontrol_edildi'; v_kontrol_eden := a.id;
    v_kontrol_zamani := v_simdi; v_degisti := true;

  elsif p_eylem = 'iptal' then
    if public.auth_yetki_var('pms_housekeeping','tam') is not true then
      raise exception 'Yetki yok' using errcode = '42501'; end if;
    if g.durum not in ('bekliyor','temizleniyor') then
      raise exception 'HK_DURUM_CAKISMASI: yalniz bitmemis gorev iptal edilir' using errcode = '42501'; end if;
    v_notlar := nullif(btrim(coalesce(p_yuk->>'aciklama','')), '');
    if v_notlar is null then
      raise exception 'Iptal icin operasyonel aciklama zorunlu' using errcode = '22023'; end if;
    v_yeni_durum := 'iptal'; v_iptal_z := v_simdi; v_iptal_n := 'operasyonel';
    v_degisti := true;

  elsif p_eylem = 'duzenle' then
    if g.durum not in ('bekliyor','temizleniyor') then
      raise exception 'HK_DURUM_CAKISMASI: yalniz bitmemis gorev duzenlenir' using errcode = '42501'; end if;
    -- Not: kendi bitmemis gorevi icin `kayit`, baskasininki/planlama icin `tam`.
    if p_yuk ? 'notlar' then
      if public.auth_yetki_var('pms_housekeeping','tam') is not true
         and not (public.auth_yetki_var('pms_housekeeping','kayit') is true
                  and g.atanan_kullanici_id is not distinct from a.id) then
        raise exception 'Yetki yok' using errcode = '42501'; end if;
      v_notlar := nullif(btrim(coalesce(p_yuk->>'notlar','')), '');
    end if;
    if p_yuk ? 'oncelik' or p_yuk ? 'hedef_zamani' then
      if public.auth_yetki_var('pms_housekeeping','tam') is not true then
        raise exception 'Yetki yok' using errcode = '42501'; end if;
      if g.durum <> 'bekliyor' then
        raise exception 'HK_DURUM_CAKISMASI: planlama alanlari yalniz beklerken degisir'
          using errcode = '42501'; end if;
      if p_yuk ? 'oncelik'      then v_oncelik := (p_yuk->>'oncelik')::smallint; end if;
      if p_yuk ? 'hedef_zamani' then v_hedef_z := nullif(p_yuk->>'hedef_zamani','')::timestamptz; end if;
    end if;
    v_degisti := v_notlar is distinct from g.notlar
              or v_oncelik is distinct from g.oncelik
              or v_hedef_z is distinct from g.hedef_zamani;
  end if;

  -- ---- DEĞİŞİKLİK YOKSA: alındıyı kirletmeden dön ----
  if not v_degisti then
    return jsonb_build_object('gorev_id', g.id, 'oda_id', o.id, 'otel_id', v_otel,
      'surum', g.surum, 'durum', g.durum, 'atanan', g.atanan_kullanici_id,
      'oda_temizlik', o.temizlik_durumu, 'oda_kullanim', o.kullanim_durumu,
      'oda_gorev_id', o.temizlik_gorevi_id, 'degisiklik_yok', true);
  end if;

  -- ---- GÖREV YAZMASI ----
  update public.pms_housekeeping_gorevleri
     set durum = v_yeni_durum,
         atanan_kullanici_id = v_yeni_atanan,
         baslama_zamani = v_baslama, bitis_zamani = v_bitis,
         kontrol_eden = v_kontrol_eden, kontrol_zamani = v_kontrol_zamani,
         iptal_zamani = v_iptal_z, iptal_nedeni = v_iptal_n,
         notlar = v_notlar, oncelik = v_oncelik, hedef_zamani = v_hedef_z,
         surum = g.surum + 1,
         guncelleme_tarihi = v_simdi,
         son_islem_anahtari = p_islem_anahtari,
         son_islem_ozeti = v_ozet
   where id = g.id
   returning * into g;

  -- ---- ODA İZDÜŞÜMÜ (yalnız güncel döngü) ----
  if o.temizlik_gorevi_id = g.id then
    update public.pms_odalar
       set temizlik_durumu = phase0_private.hk_oda_durumu(g.durum)
     where id = o.id
     returning * into o;
  end if;

  return jsonb_build_object('gorev_id', g.id, 'oda_id', o.id, 'otel_id', v_otel,
    'surum', g.surum, 'durum', g.durum, 'atanan', g.atanan_kullanici_id,
    'oda_temizlik', o.temizlik_durumu, 'oda_kullanim', o.kullanim_durumu,
    'oda_gorev_id', o.temizlik_gorevi_id, 'tekrar', false);
end;
$fn$;


-- ============================================================================
-- 17) OLUŞTURMA MOTORU  (mimari §5, §12.1)
-- ============================================================================
create or replace function phase0_private.hk_olustur(
  p_oda_id          uuid,
  p_tip             text,
  p_beklenen_kullanim text,
  p_istek_anahtari  uuid,
  p_yuk             jsonb default '{}'::jsonb,
  p_oncul           uuid default null)
returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public, pg_temp as $fn$
declare
  a public.kullanicilar;
  o public.pms_odalar;
  v_otel public.otel_id;
  v_kaynak uuid;
  v_rez uuid;
  v_ozet text;
  v_simdi timestamptz;
  v_yeni public.pms_housekeeping_gorevleri;
  v_mevcut public.pms_housekeeping_gorevleri;
  v_notlar text;
  v_oncelik smallint;
  v_hedef_z timestamptz;
begin
  if p_tip not in ('konaklama_temizligi','ekstra_temizlik') then
    raise exception 'Bu RPC ile yalniz konaklama/ekstra temizlik acilir' using errcode = '42501';
  end if;

  a := phase0_private.hk_aktor();
  if public.auth_yetki_var('pms_housekeeping','tam') is not true then
    raise exception 'Yetki yok' using errcode = '42501';
  end if;

  select otel_id into v_otel from public.pms_odalar where id = p_oda_id;
  if v_otel is null or public.auth_otel_erisim(v_otel::text) is not true then
    raise exception 'Oda bulunamadi veya erisim yok' using errcode = 'P0002';
  end if;

  -- ---- OLUŞTURMA ALINDISI: oda yaşam döngüsü ön koşullarından ÖNCE ----
  -- Meşru bir tekrar, görev bu arada tamamlanmış olsa bile aynı satırı döner.
  select * into v_mevcut from public.pms_housekeeping_gorevleri
   where otel_id = v_otel and istek_anahtari = p_istek_anahtari;
  if found then
    v_ozet := phase0_private.hk_ozet(jsonb_build_object(
      'eylem','olustur','aktor',a.id,'otel',v_otel::text,'oda',p_oda_id,
      'tip',p_tip,'beklenen_kullanim',p_beklenen_kullanim,'oncul',p_oncul,'yuk',p_yuk));
    if v_mevcut.istek_ozeti <> v_ozet then
      raise exception 'HK_ISTEK_CAKISMASI: ayni olusturma anahtari farkli icerikle'
        using errcode = '23505';
    end if;
    return jsonb_build_object('gorev_id', v_mevcut.id, 'oda_id', v_mevcut.oda_id,
      'otel_id', v_otel, 'surum', v_mevcut.surum, 'durum', v_mevcut.durum, 'tekrar', true);
  end if;

  -- ---- KAYNAK ÖNEKİ: rezervasyon -> atama (ODA'DAN ÖNCE) ----
  if p_beklenen_kullanim = 'dolu' then
    select a2.id, a2.rezervasyon_id into v_kaynak, v_rez
      from public.pms_oda_atamalari a2
      join public.pms_rezervasyonlar r
        on r.id = a2.rezervasyon_id and r.otel_id = a2.otel_id
     where a2.oda_id = p_oda_id and a2.otel_id = v_otel and a2.aktif
       and r.durum = 'giris_yapildi'
     limit 1;
    if v_kaynak is null then
      raise exception 'HK_ODA_KULLANILAMAZ: odada devam eden konaklama yok' using errcode = '42501';
    end if;
    perform 1 from public.pms_rezervasyonlar where id = v_rez for update;
    perform 1 from public.pms_oda_atamalari  where id = v_kaynak for update;
  elsif p_tip = 'konaklama_temizligi' then
    raise exception 'konaklama_temizligi yalniz dolu odada acilir' using errcode = '42501';
  end if;

  -- ---- ODA KİLİDİ ----
  select * into o from public.pms_odalar where id = p_oda_id and otel_id = v_otel for update;
  if not o.aktif then
    raise exception 'HK_ODA_KULLANILAMAZ: oda pasif' using errcode = '42501';
  end if;
  if o.kullanim_durumu::text is distinct from p_beklenen_kullanim then
    raise exception 'HK_DURUM_CAKISMASI: oda kullanim durumu degismis (beklenen %, guncel %)',
      p_beklenen_kullanim, o.kullanim_durumu using errcode = '42501';
  end if;

  if phase0_private.hk_modul_acik() is not true then
    raise exception 'Kat hizmetleri modulu kapali' using errcode = '42501';
  end if;

  -- Kilit altinda kaynak hala GUNCEL mi?
  if v_kaynak is not null and not exists (
       select 1 from public.pms_oda_atamalari a2
        join public.pms_rezervasyonlar r on r.id = a2.rezervasyon_id
       where a2.id = v_kaynak and a2.aktif and r.durum = 'giris_yapildi') then
    raise exception 'HK_DURUM_CAKISMASI: kaynak konaklama degismis' using errcode = '42501';
  end if;

  v_simdi := clock_timestamp();
  v_ozet := phase0_private.hk_ozet(jsonb_build_object(
    'eylem','olustur','aktor',a.id,'otel',v_otel::text,'oda',p_oda_id,
    'tip',p_tip,'beklenen_kullanim',p_beklenen_kullanim,'oncul',p_oncul,'yuk',p_yuk));

  v_notlar  := nullif(btrim(coalesce(p_yuk->>'notlar','')), '');
  v_oncelik := coalesce((p_yuk->>'oncelik')::smallint, 2);
  v_hedef_z := nullif(p_yuk->>'hedef_zamani','')::timestamptz;

  insert into public.pms_housekeeping_gorevleri
    (otel_id, oda_id, gorev_tipi, durum, kaynak_atama_id, onceki_gorev_id,
     oncelik, notlar, hedef_zamani, olusturma_kaynagi, olusturan,
     olusturma_tarihi, guncelleme_tarihi, surum,
     istek_anahtari, istek_ozeti, son_islem_anahtari, son_islem_ozeti)
  values (v_otel, p_oda_id, p_tip, 'bekliyor', v_kaynak, p_oncul,
          v_oncelik, v_notlar, v_hedef_z, 'kullanici', a.id,
          v_simdi, v_simdi, 1,
          p_istek_anahtari, v_ozet, p_istek_anahtari, v_ozet)
  returning * into v_yeni;

  -- Gorev acmak "temizlik SIMDI gerekli" demektir: hazirlik ANINDA gecersizlesir.
  update public.pms_odalar
     set temizlik_durumu = 'kirli', temizlik_gorevi_id = v_yeni.id
   where id = o.id;

  return jsonb_build_object('gorev_id', v_yeni.id, 'oda_id', o.id, 'otel_id', v_otel,
    'surum', 1, 'durum', 'bekliyor', 'tekrar', false);
end;
$fn$;


-- ============================================================================
-- 18) GENEL KOMUT RPC'LERİ  (mimari §13.2)
-- ----------------------------------------------------------------------------
-- Hepsi İNCE sarmalayıcıdır: kimlik/kapsam/izin motorda merkezîdir.
-- Genel amaçlı durum yazıcı YOKTUR.
-- ============================================================================
create or replace function public.pms_housekeeping_gorev_olustur(
  p_oda_id uuid, p_tip text, p_beklenen_kullanim text,
  p_istek_anahtari uuid, p_yuk jsonb default '{}'::jsonb)
returns jsonb language sql security definer
set search_path = pg_catalog, public, pg_temp as $$
  select phase0_private.hk_olustur(p_oda_id, p_tip, p_beklenen_kullanim,
                                   p_istek_anahtari, p_yuk, null);
$$;

create or replace function public.pms_housekeeping_sahiplen(
  p_gorev_id uuid, p_beklenen_surum bigint, p_islem_anahtari uuid)
returns jsonb language sql security definer
set search_path = pg_catalog, public, pg_temp as $$
  select phase0_private.hk_komut(p_gorev_id,'sahiplen',p_beklenen_surum,p_islem_anahtari);
$$;

create or replace function public.pms_housekeeping_birak(
  p_gorev_id uuid, p_beklenen_surum bigint, p_islem_anahtari uuid)
returns jsonb language sql security definer
set search_path = pg_catalog, public, pg_temp as $$
  select phase0_private.hk_komut(p_gorev_id,'birak',p_beklenen_surum,p_islem_anahtari);
$$;

create or replace function public.pms_housekeeping_ata(
  p_gorev_id uuid, p_hedef_kullanici uuid, p_beklenen_surum bigint, p_islem_anahtari uuid)
returns jsonb language sql security definer
set search_path = pg_catalog, public, pg_temp as $$
  select phase0_private.hk_komut(p_gorev_id,'ata',p_beklenen_surum,p_islem_anahtari,
           jsonb_build_object('hedef_kullanici', p_hedef_kullanici));
$$;

create or replace function public.pms_housekeeping_baslat(
  p_gorev_id uuid, p_beklenen_surum bigint, p_islem_anahtari uuid)
returns jsonb language sql security definer
set search_path = pg_catalog, public, pg_temp as $$
  select phase0_private.hk_komut(p_gorev_id,'baslat',p_beklenen_surum,p_islem_anahtari);
$$;

create or replace function public.pms_housekeeping_tamamla(
  p_gorev_id uuid, p_beklenen_surum bigint, p_islem_anahtari uuid)
returns jsonb language sql security definer
set search_path = pg_catalog, public, pg_temp as $$
  select phase0_private.hk_komut(p_gorev_id,'tamamla',p_beklenen_surum,p_islem_anahtari);
$$;

create or replace function public.pms_housekeeping_kontrol_et(
  p_gorev_id uuid, p_beklenen_surum bigint, p_islem_anahtari uuid)
returns jsonb language sql security definer
set search_path = pg_catalog, public, pg_temp as $$
  select phase0_private.hk_komut(p_gorev_id,'kontrol_et',p_beklenen_surum,p_islem_anahtari);
$$;

create or replace function public.pms_housekeeping_iptal(
  p_gorev_id uuid, p_aciklama text, p_beklenen_surum bigint, p_islem_anahtari uuid)
returns jsonb language sql security definer
set search_path = pg_catalog, public, pg_temp as $$
  select phase0_private.hk_komut(p_gorev_id,'iptal',p_beklenen_surum,p_islem_anahtari,
           jsonb_build_object('aciklama', p_aciklama));
$$;

create or replace function public.pms_housekeeping_duzenle(
  p_gorev_id uuid, p_yuk jsonb, p_beklenen_surum bigint, p_islem_anahtari uuid)
returns jsonb language sql security definer
set search_path = pg_catalog, public, pg_temp as $$
  select phase0_private.hk_komut(p_gorev_id,'duzenle',p_beklenen_surum,p_islem_anahtari,p_yuk);
$$;

-- --- Yeniden açma: geçmişi geri sarmaz, ARDIL yaratır ----------------------
create or replace function public.pms_housekeeping_yeniden_ac(
  p_gorev_id uuid, p_aciklama text, p_beklenen_surum bigint, p_istek_anahtari uuid)
returns jsonb language plpgsql security definer
set search_path = pg_catalog, public, pg_temp as $fn$
declare
  a public.kullanicilar; g public.pms_housekeeping_gorevleri; o public.pms_odalar;
  v_sonuc jsonb;
begin
  a := phase0_private.hk_aktor();
  if public.auth_yetki_var('pms_housekeeping','tam') is not true then
    raise exception 'Yetki yok' using errcode = '42501'; end if;

  select * into g from public.pms_housekeeping_gorevleri where id = p_gorev_id;
  if not found or public.auth_otel_erisim(g.otel_id::text) is not true then
    raise exception 'Gorev bulunamadi veya erisim yok' using errcode = 'P0002'; end if;

  select * into o from public.pms_odalar where id = g.oda_id and otel_id = g.otel_id for update;
  select * into g from public.pms_housekeeping_gorevleri where id = p_gorev_id for update;

  if g.durum not in ('tamamlandi','kontrol_edildi') then
    raise exception 'HK_DURUM_CAKISMASI: yalniz tamamlanmis/denetlenmis is yeniden acilir'
      using errcode = '42501'; end if;
  if g.surum <> p_beklenen_surum then
    raise exception 'HK_SURUM_CAKISMASI: beklenen % guncel %', p_beklenen_surum, g.surum
      using errcode = '40001'; end if;
  if o.temizlik_gorevi_id is distinct from g.id then
    raise exception 'HK_DURUM_CAKISMASI: gorev odanin guncel dongusu degil' using errcode = '42501'; end if;
  if o.kullanim_durumu <> 'bos' then
    raise exception 'HK_ODA_KULLANILAMAZ: yeniden acma yalniz bos odada' using errcode = '42501'; end if;

  -- Öncül DEĞİŞMEDEN kalır; ardıl açılır ve oda kirlenir.
  v_sonuc := phase0_private.hk_olustur(o.id, 'ekstra_temizlik', 'bos',
               p_istek_anahtari,
               jsonb_build_object('notlar', p_aciklama), g.id);
  return v_sonuc || jsonb_build_object('oncul_id', g.id);
end;
$fn$;

-- --- Devir: çalışan işi iptal + atamasız ardıl, TEK transaction ------------
create or replace function public.pms_housekeeping_devret(
  p_gorev_id uuid, p_aciklama text, p_beklenen_surum bigint, p_istek_anahtari uuid)
returns jsonb language plpgsql security definer
set search_path = pg_catalog, public, pg_temp as $fn$
declare
  a public.kullanicilar; g public.pms_housekeeping_gorevleri;
  v_sonuc jsonb; v_iptal jsonb;
begin
  a := phase0_private.hk_aktor();
  if public.auth_yetki_var('pms_housekeeping','tam') is not true then
    raise exception 'Yetki yok' using errcode = '42501'; end if;

  select * into g from public.pms_housekeeping_gorevleri where id = p_gorev_id;
  if not found or public.auth_otel_erisim(g.otel_id::text) is not true then
    raise exception 'Gorev bulunamadi veya erisim yok' using errcode = 'P0002'; end if;
  if g.durum <> 'temizleniyor' then
    raise exception 'HK_DURUM_CAKISMASI: devir yalniz calisan iste yapilir' using errcode = '42501'; end if;

  -- Iptal ve ardil AYNI transaction'da; ardil basarisiz olursa iptal de geri doner.
  v_iptal := phase0_private.hk_komut(p_gorev_id, 'iptal', p_beklenen_surum,
               gen_random_uuid(), jsonb_build_object('aciklama', p_aciklama));

  v_sonuc := phase0_private.hk_olustur(g.oda_id, 'ekstra_temizlik',
               (select kullanim_durumu::text from public.pms_odalar where id = g.oda_id),
               p_istek_anahtari, jsonb_build_object('notlar', p_aciklama), g.id);

  return v_sonuc || jsonb_build_object('oncul_id', g.id, 'oncul_iptal', v_iptal->'durum');
end;
$fn$;


-- ============================================================================
-- 19) OKUMA RPC'LERİ  (mimari §15)
-- ----------------------------------------------------------------------------
-- Dar izdüşüm. `select *` yok, misafir/folyo verisi yok, kullanıcı yönetimi
-- açılmaz. Sayfa boyutu sınırlıdır.
-- ============================================================================
create or replace function public.pms_housekeeping_listele(
  p_otel text, p_kuyruk text default 'tumu', p_limit int default 50)
returns table (
  gorev_id uuid, oda_id uuid, oda_no text, kat text,
  gorev_tipi text, durum text, oncelik smallint,
  atanan_kullanici_id uuid, hedef_zamani timestamptz,
  olusturma_tarihi timestamptz, surum bigint,
  oda_kullanim public.pms_kullanim_durumu, oda_temizlik public.pms_temizlik_durumu,
  guncel_dongu boolean, sunucu_zamani timestamptz)
language plpgsql stable security definer
set search_path = pg_catalog, public, pg_temp as $fn$
declare v_otel public.otel_id;
begin
  perform phase0_private.hk_aktor();
  if public.auth_yetki_var('pms_housekeeping','goruntule') is not true
     or public.auth_otel_erisim(p_otel) is not true then
    raise exception 'Yetki yok' using errcode = '42501';
  end if;
  v_otel := p_otel::public.otel_id;

  return query
    select g.id, g.oda_id, o.oda_no, o.kat,
           g.gorev_tipi, g.durum, g.oncelik,
           g.atanan_kullanici_id, g.hedef_zamani,
           g.olusturma_tarihi, g.surum,
           o.kullanim_durumu, o.temizlik_durumu,
           (o.temizlik_gorevi_id = g.id),
           clock_timestamp()
      from public.pms_housekeeping_gorevleri g
      join public.pms_odalar o on o.id = g.oda_id and o.otel_id = g.otel_id
     where g.otel_id = v_otel
       and case p_kuyruk
             when 'bitmemis' then g.durum in ('bekliyor','temizleniyor')
             when 'kontrol'  then g.durum = 'tamamlandi' and o.temizlik_gorevi_id = g.id
             else true
           end
     order by g.oncelik, g.hedef_zamani nulls last, g.olusturma_tarihi, g.id
     limit least(greatest(coalesce(p_limit, 50), 1), 100);
end;
$fn$;

create or replace function public.pms_housekeeping_calisanlar(p_otel text)
returns table (kullanici_id uuid, ad text)
language plpgsql stable security definer
set search_path = pg_catalog, public, pg_temp as $fn$
declare v_otel public.otel_id;
begin
  perform phase0_private.hk_aktor();
  if public.auth_yetki_var('pms_housekeeping','goruntule') is not true
     or public.auth_otel_erisim(p_otel) is not true then
    raise exception 'Yetki yok' using errcode = '42501';
  end if;
  v_otel := p_otel::public.otel_id;
  -- YALNIZ kimlik ve gorunen ad. Tam kullanicilar satiri ASLA donmez.
  return query
    select k.id, k.ad from public.kullanicilar k
     where phase0_private.hk_calisan_uygun(k.id, v_otel)
     order by k.ad;
end;
$fn$;

create or replace function public.pms_housekeeping_oda_ozet(
  p_otel text, p_oda_idler uuid[])
returns table (
  oda_id uuid, oda_kullanim public.pms_kullanim_durumu,
  oda_temizlik public.pms_temizlik_durumu,
  gorev_id uuid, gorev_durum text, gorev_tipi text,
  atanan_kullanici_id uuid, oncelik smallint, hedef_zamani timestamptz)
language plpgsql stable security definer
set search_path = pg_catalog, public, pg_temp as $fn$
declare v_otel public.otel_id;
begin
  perform phase0_private.hk_aktor();
  if public.auth_yetki_var('pms_housekeeping','goruntule') is not true
     or public.auth_otel_erisim(p_otel) is not true then
    raise exception 'Yetki yok' using errcode = '42501';
  end if;
  if array_length(p_oda_idler, 1) > 500 then
    raise exception 'En cok 500 oda sorgulanir' using errcode = '22023';
  end if;
  v_otel := p_otel::public.otel_id;

  return query
    select o.id, o.kullanim_durumu, o.temizlik_durumu,
           g.id, g.durum, g.gorev_tipi, g.atanan_kullanici_id, g.oncelik, g.hedef_zamani
      from public.pms_odalar o
      left join public.pms_housekeeping_gorevleri g on g.id = o.temizlik_gorevi_id
     where o.otel_id = v_otel and o.id = any(p_oda_idler);
end;
$fn$;


-- ============================================================================
-- 20) FONKSİYON ACL'LERİ  (mimari §17.2)
-- ----------------------------------------------------------------------------
-- Özel yardımcılar: hiçbir uygulama rolüne EXECUTE verilmez. `phase0_private`
-- şeması zaten PostgREST'e kapalıdır; bu ikinci kattır.
-- ============================================================================
-- --- 20a) AÇIK KARAR — her çağrılabilir fonksiyon, imzasıyla -------------
-- Standart: süpürge açık kararın YERİNE GEÇMEZ, ÜSTÜNE BİNER. Hangi rolün
-- neyi çağırabileceği dosyada GÖRÜNÜR olmalıdır; aşağıdaki liste o karardır.
revoke all on function public.pms_housekeeping_gorev_olustur(uuid, text, text, uuid, jsonb) from public, anon;
revoke all on function public.pms_housekeeping_sahiplen(uuid, bigint, uuid)                 from public, anon;
revoke all on function public.pms_housekeeping_birak(uuid, bigint, uuid)                    from public, anon;
revoke all on function public.pms_housekeeping_ata(uuid, uuid, bigint, uuid)                from public, anon;
revoke all on function public.pms_housekeeping_baslat(uuid, bigint, uuid)                   from public, anon;
revoke all on function public.pms_housekeeping_tamamla(uuid, bigint, uuid)                  from public, anon;
revoke all on function public.pms_housekeeping_kontrol_et(uuid, bigint, uuid)               from public, anon;
revoke all on function public.pms_housekeeping_iptal(uuid, text, bigint, uuid)              from public, anon;
revoke all on function public.pms_housekeeping_duzenle(uuid, jsonb, bigint, uuid)           from public, anon;
revoke all on function public.pms_housekeeping_yeniden_ac(uuid, text, bigint, uuid)         from public, anon;
revoke all on function public.pms_housekeeping_devret(uuid, text, bigint, uuid)             from public, anon;
revoke all on function public.pms_housekeeping_listele(text, text, int)                     from public, anon;
revoke all on function public.pms_housekeeping_calisanlar(text)                             from public, anon;
revoke all on function public.pms_housekeeping_oda_ozet(text, uuid[])                       from public, anon;

grant execute on function public.pms_housekeeping_gorev_olustur(uuid, text, text, uuid, jsonb) to authenticated;
grant execute on function public.pms_housekeeping_sahiplen(uuid, bigint, uuid)                 to authenticated;
grant execute on function public.pms_housekeeping_birak(uuid, bigint, uuid)                    to authenticated;
grant execute on function public.pms_housekeeping_ata(uuid, uuid, bigint, uuid)                to authenticated;
grant execute on function public.pms_housekeeping_baslat(uuid, bigint, uuid)                   to authenticated;
grant execute on function public.pms_housekeeping_tamamla(uuid, bigint, uuid)                  to authenticated;
grant execute on function public.pms_housekeeping_kontrol_et(uuid, bigint, uuid)               to authenticated;
grant execute on function public.pms_housekeeping_iptal(uuid, text, bigint, uuid)              to authenticated;
grant execute on function public.pms_housekeeping_duzenle(uuid, jsonb, bigint, uuid)           to authenticated;
grant execute on function public.pms_housekeeping_yeniden_ac(uuid, text, bigint, uuid)         to authenticated;
grant execute on function public.pms_housekeeping_devret(uuid, text, bigint, uuid)             to authenticated;
grant execute on function public.pms_housekeeping_listele(text, text, int)                     to authenticated;
grant execute on function public.pms_housekeeping_calisanlar(text)                             to authenticated;
grant execute on function public.pms_housekeeping_oda_ozet(text, uuid[])                       to authenticated;

-- --- 20b) SÜPÜRGE — açık kararın üstüne -----------------------------------
-- Tetikleyici fonksiyonlarını ve unutulanı toplar; miras alınmış
-- authenticated/service_role EXECUTE haklarını da nötrler.
do $$
declare v record;
begin
  -- Ozel yardimcilar: TUM uygulama rollerinden geri al.
  for v in select p.oid::regprocedure as f
             from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
            where ns.nspname = 'phase0_private' and p.proname like 'hk\_%'
  loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', v.f);
  end loop;

  -- Genel RPC'ler: PUBLIC/anon kapali, yalniz authenticated.
  for v in select p.oid::regprocedure as f
             from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
            where ns.nspname = 'public' and p.proname like 'pms\_housekeeping\_%'
              and p.prorettype <> 'trigger'::regtype
  loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', v.f);
    execute format('grant execute on function %s to authenticated', v.f);
  end loop;

  -- Tetikleyici fonksiyonlari: cagrilamaz, ACL karari gerekmez; yine de
  -- PUBLIC/anon acikca kapatilir (supurge).
  for v in select p.oid::regprocedure as f
             from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
            where ns.nspname = 'public' and p.proname like 'pms\_housekeeping\_%'
              and p.prorettype = 'trigger'::regtype
  loop
    execute format('revoke all on function %s from public, anon', v.f);
  end loop;
end;
$$;




-- ============================================================================
-- 21) ARTIM 2 DOGRULAMASI — COMMIT'TEN ONCE
-- ============================================================================
do $$
declare n int;
begin
  -- Bekciler bagli mi?
  if not exists (select 1 from pg_trigger where tgrelid='public.pms_housekeeping_gorevleri'::regclass
                  and tgname='pms_housekeeping_gorev_koruma' and not tgisinternal) then
    raise exception 'DOGRULAMA: gecis bekcisi bagli degil'; end if;
  if not exists (select 1 from pg_trigger where tgrelid='public.pms_odalar'::regclass
                  and tgname='pms_housekeeping_oda_koruma' and not tgisinternal) then
    raise exception 'DOGRULAMA: oda bekcisi bagli degil'; end if;

  -- Oda bekcisi INVOKER olmali (current_user ayrimi icin ZORUNLU)
  if (select prosecdef from pg_proc where oid='public.pms_housekeeping_oda_koruma()'::regprocedure) then
    raise exception 'DOGRULAMA: oda bekcisi DEFINER; current_user ayrimi imkansiz olur'; end if;

  -- Ertelenmis kisit tetikleyicileri: DEFERRABLE INITIALLY DEFERRED
  select count(*) into n from pg_constraint
   where conname in ('pms_housekeeping_tutarlilik_gorev','pms_housekeeping_tutarlilik_oda')
     and contype='t' and condeferrable and condeferred;
  if n <> 2 then
    raise exception 'DOGRULAMA: tutarlilik kisitlari INITIALLY DEFERRED degil (%)', n; end if;

  -- Ozel yardimcilar uygulama rollerine KAPALI
  select count(*) into n from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
   where ns.nspname='phase0_private' and p.proname like 'hk_%'
     and (has_function_privilege('authenticated', p.oid, 'EXECUTE')
          or has_function_privilege('anon', p.oid, 'EXECUTE'));
  if n <> 0 then raise exception 'DOGRULAMA: % ozel yardimci uygulama rolune acik', n; end if;

  -- Genel RPC'ler: anon KAPALI, authenticated ACIK
  select count(*) into n from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
   where ns.nspname='public' and p.proname like 'pms_housekeeping_%'
     and p.prorettype <> 'trigger'::regtype
     and has_function_privilege('anon', p.oid, 'EXECUTE');
  if n <> 0 then raise exception 'DOGRULAMA: % RPC anon a acik', n; end if;

  select count(*) into n from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
   where ns.nspname='public' and p.proname like 'pms_housekeeping_%'
     and p.prorettype <> 'trigger'::regtype
     and not has_function_privilege('authenticated', p.oid, 'EXECUTE');
  if n <> 0 then raise exception 'DOGRULAMA: % RPC authenticated a kapali', n; end if;

  -- Pinsiz SECURITY DEFINER olmamali
  select count(*) into n from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
   where ns.nspname in ('public','phase0_private')
     and (p.proname like 'pms_housekeeping_%' or p.proname like 'hk_%')
     and p.prosecdef
     and (p.proconfig is null or not exists (select 1 from unnest(p.proconfig) k where k like 'search_path=%'));
  if n <> 0 then raise exception 'DOGRULAMA: % pinsiz SECURITY DEFINER', n; end if;

  raise notice 'DOGRULAMA (artim 2): tum kontroller gecti.';
end;
$$;


commit;


-- ============================================================================
-- GERİ ALMA / ÖZELLİĞİ KAPATMA
-- ----------------------------------------------------------------------------
-- TERCİH SIRASI (mimari §24):
--
-- 1) MODÜLÜ KAPAT — en güvenli, veri kaybı yok:
--      update public.moduller set aktif = false where kod = 'pms_housekeeping';
--    `auth_yetki_var()` modül aktifliğini şart koştuğu için tüm okuma ve
--    komutlar anında kapanır. Bu migration modülü ZATEN kapalı kurar.
--
-- 2) NESNELERİ DÜŞÜR — yalnız görev tablosu BOŞSA:
--      alter table public.pms_odalar drop constraint if exists pms_odalar_temizlik_gorevi_fk;
--      alter table public.pms_odalar drop column if exists temizlik_gorevi_id;
--      drop table if exists public.pms_housekeeping_gorevleri;
--      alter table public.pms_oda_atamalari
--        drop constraint if exists pms_oda_atamalari_id_oda_otel_key;
--      delete from public.moduller where kod = 'pms_housekeeping';
--
--    SINIR: görev tablosunda satır varsa bu blok ÇALIŞTIRILMAZ. Kat hizmeti
--    geçmişi operasyonel kanıttır; özellik kapatma tercih edilir.
--
-- 3) YEDEKTEN DÖNÜŞ: yalnız 1 ve 2 uygulanamıyorsa.
-- ============================================================================
