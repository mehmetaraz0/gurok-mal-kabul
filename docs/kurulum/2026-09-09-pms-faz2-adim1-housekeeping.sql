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
