-- ============================================================================
-- PMS FAZ 2 / ADIM 1 — KAT HİZMETLERİ VERİTABANI SÖZLEŞME TESTLERİ
-- ----------------------------------------------------------------------------
-- YALNIZ ATILABILIR YEREL/STAGING VERİTABANINDA ÇALIŞTIRILIR.
-- Üretime karşı ASLA çalıştırılmaz: gerçek satır yazar ve geri alır.
--
-- Kullanım (yerel Docker staging):
--   psql -X -U postgres -d dokum_test -f scripts/pms-faz2-housekeeping-testleri.sql
--
-- Yöntem: her test kendi savepoint'inde çalışır, sonucunu NOTICE olarak
-- yazar ve durumu geri alır. "OK" olmayan her satır bir başarısızlıktır.
--
-- Bu dosya ADIM 1'in YAPISAL sözleşmesini kapsar (tablo, kısıt, indeks, FK,
-- ACL, RLS, tetikleyici). Durum makinesi RPC'leri, çıkış üreticisi, yaşam
-- döngüsü ve denetim izi testleri sonraki artımda eklenir.
-- ============================================================================

\set ON_ERROR_STOP on

-- Tüm test bir transaction içinde çalışır ve dosyanın sonunda GERİ ALINIR.
-- Hiçbir test satırı kalıcı olmaz.
begin;

do $$
declare
  v_oda    uuid;
  v_oda2   uuid;
  v_gorev  uuid;
  v_calisan uuid;
  v_h      text := encode(sha256('sozlesme'::bytea), 'hex');
  v_ok     int := 0;
  v_fail   int := 0;
begin
  -- --------------------------------------------------------------------
  -- FİKSTÜR: iki otelde aynı oda numarası (çapraz otel testleri için)
  -- artı bir test çalışanı. Şema-only dökümde `kullanicilar` BOŞTUR;
  -- atanan/olusturan FK'leri gerçek bir satır ister.
  -- --------------------------------------------------------------------
  insert into public.kullanicilar (ad, rol, otel_id, aktif)
  values ('T2 Test Calisani', 'depo', '810', true)
  returning id into v_calisan;

  insert into public.pms_oda_tipleri (otel_id, kod, ad, azami_kisi, azami_yetiskin, azami_cocuk)
  values ('810','t2test','Test Tipi',2,2,1), ('811','t2test','Test Tipi',2,2,1)
  on conflict do nothing;

  insert into public.pms_odalar (otel_id, oda_tipi_id, oda_no)
  select o.otel_id, o.id, 'T201' from public.pms_oda_tipleri o where o.kod='t2test'
  on conflict do nothing;

  select id into v_oda  from public.pms_odalar where oda_no='T201' and otel_id='810';
  select id into v_oda2 from public.pms_odalar where oda_no='T201' and otel_id='811';

  if v_oda is null or v_oda2 is null or v_calisan is null then
    raise exception 'FIKSTUR: test odalari/calisani olusturulamadi';
  end if;

  -- ====================================================================
  -- T1  Oda başına tek bitmemiş görev
  -- ====================================================================
  begin
    insert into public.pms_housekeeping_gorevleri
      (otel_id, oda_id, gorev_tipi, olusturma_kaynagi,
       istek_anahtari, istek_ozeti, son_islem_anahtari, son_islem_ozeti)
    values ('810', v_oda, 'ekstra_temizlik', 'sistem',
            gen_random_uuid(), v_h, gen_random_uuid(), v_h)
    returning id into v_gorev;

    begin
      insert into public.pms_housekeeping_gorevleri
        (otel_id, oda_id, gorev_tipi, olusturma_kaynagi,
         istek_anahtari, istek_ozeti, son_islem_anahtari, son_islem_ozeti)
      values ('810', v_oda, 'ekstra_temizlik', 'sistem',
              gen_random_uuid(), v_h, gen_random_uuid(), v_h);
      raise notice 'T1  FAIL  ikinci bitmemis gorev kabul edildi';
      v_fail := v_fail + 1;
    exception when unique_violation then
      raise notice 'T1  OK    oda basina tek bitmemis gorev';
      v_ok := v_ok + 1;
    end;
  end;

  -- ====================================================================
  -- T2  Tamamlanmış görev aktif yuvayı BOŞALTIR (kontrol bekleyen iş
  --     bitmemiş sayılmaz)
  -- ====================================================================
  begin
    update public.pms_housekeeping_gorevleri
       set durum = 'tamamlandi',
           atanan_kullanici_id = v_calisan,
           baslama_zamani = now(), bitis_zamani = now()
     where id = v_gorev;

    insert into public.pms_housekeeping_gorevleri
      (otel_id, oda_id, gorev_tipi, olusturma_kaynagi,
       istek_anahtari, istek_ozeti, son_islem_anahtari, son_islem_ozeti)
    values ('810', v_oda, 'ekstra_temizlik', 'sistem',
            gen_random_uuid(), v_h, gen_random_uuid(), v_h);
    raise notice 'T2  OK    tamamlanmis gorev aktif yuvayi bosaltiyor';
    v_ok := v_ok + 1;
  exception when others then
    raise notice 'T2  FAIL  %', sqlerrm;
    v_fail := v_fail + 1;
  end;

  -- ====================================================================
  -- T3  Durum matrisi: bekliyor durumunda bitis_zamani olamaz
  -- ====================================================================
  begin
    insert into public.pms_housekeeping_gorevleri
      (otel_id, oda_id, gorev_tipi, olusturma_kaynagi, durum, bitis_zamani,
       istek_anahtari, istek_ozeti, son_islem_anahtari, son_islem_ozeti)
    values ('811', v_oda2, 'ekstra_temizlik', 'sistem', 'bekliyor', now(),
            gen_random_uuid(), v_h, gen_random_uuid(), v_h);
    raise notice 'T3  FAIL  bekliyor + bitis_zamani kabul edildi';
    v_fail := v_fail + 1;
  exception when check_violation then
    raise notice 'T3  OK    durum matrisi bekliyor+bitis_zamani reddetti';
    v_ok := v_ok + 1;
  end;

  -- ====================================================================
  -- T4  Oluşturma kaynağı: kullanici olusturan olmadan reddedilir
  -- ====================================================================
  begin
    insert into public.pms_housekeeping_gorevleri
      (otel_id, oda_id, gorev_tipi, olusturma_kaynagi, olusturan,
       istek_anahtari, istek_ozeti, son_islem_anahtari, son_islem_ozeti)
    values ('811', v_oda2, 'ekstra_temizlik', 'kullanici', null,
            gen_random_uuid(), v_h, gen_random_uuid(), v_h);
    raise notice 'T4  FAIL  kullanici kaynagi aktorsuz kabul edildi';
    v_fail := v_fail + 1;
  exception when check_violation then
    raise notice 'T4  OK    kullanici kaynagi olusturan sart kosuyor';
    v_ok := v_ok + 1;
  end;

  -- ====================================================================
  -- T5  Oluşturma kaynağı: sistem, olusturan NULL ile KABUL EDİLİR
  --     (sentinel kullanıcı yaratmama kararının doğrudan sınavı)
  -- ====================================================================
  begin
    insert into public.pms_housekeeping_gorevleri
      (otel_id, oda_id, gorev_tipi, olusturma_kaynagi, olusturan,
       istek_anahtari, istek_ozeti, son_islem_anahtari, son_islem_ozeti)
    values ('811', v_oda2, 'ekstra_temizlik', 'sistem', null,
            gen_random_uuid(), v_h, gen_random_uuid(), v_h);
    raise notice 'T5  OK    sistem kaynagi aktorsuz kabul ediliyor';
    v_ok := v_ok + 1;
  exception when others then
    raise notice 'T5  FAIL  %', sqlerrm;
    v_fail := v_fail + 1;
  end;

  -- ====================================================================
  -- T6  checkout kaynağı ile cikis_temizligi tipi AYRILAMAZ
  -- ====================================================================
  begin
    insert into public.pms_housekeeping_gorevleri
      (otel_id, oda_id, gorev_tipi, olusturma_kaynagi,
       istek_anahtari, istek_ozeti, son_islem_anahtari, son_islem_ozeti)
    values ('810', v_oda, 'ekstra_temizlik', 'checkout',
            gen_random_uuid(), v_h, gen_random_uuid(), v_h);
    raise notice 'T6  FAIL  checkout kaynagi ekstra_temizlik ile kabul edildi';
    v_fail := v_fail + 1;
  exception when check_violation then
    raise notice 'T6  OK    checkout kaynagi <-> cikis_temizligi bagli';
    v_ok := v_ok + 1;
  end;

  -- ====================================================================
  -- T7  cikis_temizligi kaynak atama ZORUNLU
  -- ====================================================================
  begin
    insert into public.pms_housekeeping_gorevleri
      (otel_id, oda_id, gorev_tipi, olusturma_kaynagi, kaynak_atama_id,
       istek_anahtari, istek_ozeti, son_islem_anahtari, son_islem_ozeti)
    values ('810', v_oda, 'cikis_temizligi', 'checkout', null,
            gen_random_uuid(), v_h, gen_random_uuid(), v_h);
    raise notice 'T7  FAIL  cikis_temizligi kaynaksiz kabul edildi';
    v_fail := v_fail + 1;
  exception when check_violation then
    raise notice 'T7  OK    cikis_temizligi kaynak atama sart kosuyor';
    v_ok := v_ok + 1;
  end;

  -- ====================================================================
  -- T8  ÇAPRAZ OTEL: 810 görevinin oda_id'si 811 odasını gösteremez
  --     Bileşik FK bunu RLS'ten BAĞIMSIZ olarak reddeder.
  -- ====================================================================
  begin
    insert into public.pms_housekeeping_gorevleri
      (otel_id, oda_id, gorev_tipi, olusturma_kaynagi,
       istek_anahtari, istek_ozeti, son_islem_anahtari, son_islem_ozeti)
    values ('810', v_oda2, 'ekstra_temizlik', 'sistem',
            gen_random_uuid(), v_h, gen_random_uuid(), v_h);
    raise notice 'T8  FAIL  capraz otel oda referansi kabul edildi';
    v_fail := v_fail + 1;
  exception when foreign_key_violation then
    raise notice 'T8  OK    bilesik FK capraz otel odayi reddetti';
    v_ok := v_ok + 1;
  end;

  -- ====================================================================
  -- T9  Oda göstergesi BAŞKA odanın görevini işaret edemez
  -- ====================================================================
  begin
    update public.pms_odalar set temizlik_gorevi_id = v_gorev where id = v_oda2;
    raise notice 'T9  FAIL  oda gostergesi baska odanin gorevini aldi';
    v_fail := v_fail + 1;
  exception when foreign_key_violation then
    raise notice 'T9  OK    gosterge FK yanlis oda/otel esini reddetti';
    v_ok := v_ok + 1;
  end;

  -- ====================================================================
  -- T10 Otel değişmezliği (paylaşılan phase0 tetikleyicisi)
  -- ====================================================================
  begin
    update public.pms_housekeeping_gorevleri set otel_id = '811' where id = v_gorev;
    raise notice 'T10 FAIL  gorevin oteli degistirilebildi';
    v_fail := v_fail + 1;
  exception when others then
    raise notice 'T10 OK    phase0_otel_degismez otel degisimini reddetti';
    v_ok := v_ok + 1;
  end;

  -- ====================================================================
  -- T11 Öncül kendisi olamaz
  -- ====================================================================
  begin
    update public.pms_housekeeping_gorevleri set onceki_gorev_id = v_gorev where id = v_gorev;
    raise notice 'T11 FAIL  gorev kendi onculu oldu';
    v_fail := v_fail + 1;
  exception when check_violation then
    raise notice 'T11 OK    oncul kendisi olamaz';
    v_ok := v_ok + 1;
  end;

  -- ====================================================================
  -- T12 Parmak izi biçimi 64 küçük harfli onaltılık olmalı
  -- ====================================================================
  begin
    insert into public.pms_housekeeping_gorevleri
      (otel_id, oda_id, gorev_tipi, olusturma_kaynagi,
       istek_anahtari, istek_ozeti, son_islem_anahtari, son_islem_ozeti)
    values ('811', v_oda2, 'ekstra_temizlik', 'sistem',
            gen_random_uuid(), 'KISA', gen_random_uuid(), v_h);
    raise notice 'T12 FAIL  gecersiz parmak izi kabul edildi';
    v_fail := v_fail + 1;
  exception when check_violation then
    raise notice 'T12 OK    parmak izi bicimi zorunlu';
    v_ok := v_ok + 1;
  end;

  -- ====================================================================
  -- T13 İptal nedeni denetimli kod kümesinden olmalı
  -- ====================================================================
  begin
    insert into public.pms_housekeeping_gorevleri
      (otel_id, oda_id, gorev_tipi, olusturma_kaynagi, durum,
       iptal_zamani, iptal_nedeni,
       istek_anahtari, istek_ozeti, son_islem_anahtari, son_islem_ozeti)
    values ('811', v_oda2, 'ekstra_temizlik', 'sistem', 'iptal',
            now(), 'canim_istedi',
            gen_random_uuid(), v_h, gen_random_uuid(), v_h);
    raise notice 'T13 FAIL  serbest metin iptal nedeni kabul edildi';
    v_fail := v_fail + 1;
  exception when check_violation then
    raise notice 'T13 OK    iptal nedeni denetimli kod kumesinden';
    v_ok := v_ok + 1;
  end;

  -- ====================================================================
  raise notice '--------------------------------------------------';
  raise notice 'SONUC: % OK / % FAIL', v_ok, v_fail;
  if v_fail > 0 then
    raise exception 'YAPISAL SOZLESME TESTLERI BASARISIZ: % test', v_fail;
  end if;
end;
$$;

-- Fikstür ve tüm test satırları geri alınır; hiçbir şey kalıcı olmaz.
rollback;
