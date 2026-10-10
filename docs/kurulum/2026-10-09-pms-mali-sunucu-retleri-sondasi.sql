-- ===========================================================================
-- MALI SUNUCU RETLERI — SALT SONDA (K1 / K2 / K3 / K4)
-- ===========================================================================
-- Plan: docs/kurulum/2026-10-09-pms-mali-sunucu-retleri-plani.md
--
-- NE OLCER: canli mali duman testinde ARAYUZ tarafindan engellendigi icin
-- sunucuya hic ulasmamis kontrolleri. ALTI deneme:
--   K1  personelin NEGATIF odemesi            -> MALI_TAM_YETKI_GEREKLI  42501
--   K2  yoneticinin GEREKCESIZ iadesi         -> MALI_GEREKCE_ZORUNLU    23514
--   K3a mevcut HAREKET satirinin UPDATE'i     -> Finansal kayit degis... 42501
--   K3b mevcut HAREKET satirinin DELETE'i     -> Finansal kayit degis... 42501
--   K4a mevcut ODEME satirinin UPDATE'i       -> Finansal kayit degis... 42501
--   K4b mevcut ODEME satirinin DELETE'i       -> Finansal kayit degis... 42501
-- `pms_folio_degismez` tetikleyicisi IKI tabloda da kuruludur
-- (docs/kurulum/2026-09-06-pms-faz1-adim4-folio.sql); bu yuzden odemeler
-- tablosu da ayrica sinanir.
--
-- ---------------------------------------------------------------------------
-- BU SONDA GECICI OLARAK YAZAR — ACIKCA BELIRTILIR
-- ---------------------------------------------------------------------------
-- Dosya calistiginda hedef otelde SU SATIRLAR YAZILIR:
--   1 rezervasyon (`SONDA-<zaman damgasi>`) + 1 folyo (tetikleyici otomatik
--   acar) + 1 oda ucreti hareketi (+100,00) + 1 pozitif nakit odeme (+10,00).
-- Hepsi dosyanin sonundaki `rollback` ile GERI ALINIR; beklenmedik bir KABUL
-- cikarsa o satir da geri alinir.
--
-- KALICI IZ — DIZILER GERI ALINMAZ. Her kosum sunlari KALICI olarak ilerletir:
--   `pms_rezervasyon_no_seq`  +1   (rezervasyon numarasinda bosluk)
--   `pms_folio_no_seq`        +1   (folyo numarasinda bosluk)
-- `pms_folio_odemeler` ve `pms_folio_hareketleri` tablolarinin dizisi YOKTUR
-- (kimlikleri `gen_random_uuid()`), dolayisiyla baska dizi izi kalmaz.
-- Yani kosumdan sonra uretimde bir rezervasyon ve bir folyo NUMARASI
-- atlanmis gorunur. Bu bilinerek kabul edilir; baska kalici etki yoktur.
--
-- ---------------------------------------------------------------------------
-- TASARIM KURALLARI (hepsi bilincli)
-- ---------------------------------------------------------------------------
--  1) HEDEF ACIK SECIMLE SABITLENIR. Otel, personel, yonetici ve sentetik
--     misafir asagidaki `set local sonda.*` satirlarinda ELLE yazilir.
--     Doldurulmamis (`DOLDUR`) birakilan her alan sondayi DURDURUR. "Ilk
--     bulunani al" mantigi YOKTUR: yanlis otelde veya yanlis kimlikle
--     olculen bir ret, olculmek istenen ret DEGILDIR.
--
--  2) GERCEK UYGULAMA ROLU. Her deneme `set local role authenticated` +
--     `request.jwt.claims` ile, secilen gercek ERP kullanicisinin kimligiyle
--     yapilir. Her denemenin yaninda `current_user`, `rolsuper` ve
--     `rolbypassrls` KAYDEDILIR. `postgres` ile alinan sonuc GECERSIZ sayilir.
--
--  3) FIKSTUR DE KIMLIKLE KURULUR. `phase0_islem_audit` tetikleyicisi
--     kimliksiz (dogrudan superuser) yazmayi "Aktif ERP personeli gerekli"
--     ile REDDEDER — izole ortamda olculdu. Bu yuzden hedef rezervasyon,
--     hareket ve odeme satirlari da personel kimligiyle yazilir.
--
--  4) YALNIZ SENTETIK MISAFIR. Hedef misafir, soyadi acik secimle verilen
--     SENTETIK QA kaydidir; isarette 'QA' gecmek ZORUNDADIR. Eslesme yoksa
--     veya BIRDEN FAZLAYSA sonda DURUR. Gercek bir misafirin uzerine
--     sentetik rezervasyon yazilmaz.
--
--  5) KALICI DEGISIKLIK YOK. Dosyanin tamami tek islemdedir ve `rollback` ile
--     biter. Her deneme kendi istisna blogunda kosar; bir hata islemi abort
--     etmez.
--
--  6) `SET TRANSACTION READ ONLY` KULLANILMAZ. Kullanilsaydi her yazma
--     "read-only transaction" ile reddedilir ve ASIL YETKI HATASINI
--     MASKELERDI.
--
--  7) KAPALI FOLYO MASKELEMESI ENGELLENIR. Hedef folyo ISLEM ICINDE olusur ve
--     ACIK olmak zorundadir; degilse sonda KURULUM ASAMASINDA DURUR. Ayrica
--     "Kapali folyoya kayit eklenemez" hatasi BEKLENEN RET SAYILMAZ.
--
--  8) MESAJ **VE** SQLSTATE BIRLIKTE DOGRULANIR. Beklenen metin tuttugu halde
--     SQLSTATE farkliysa sonuc `SQLSTATE YANLIS (GECERSIZ)` olur ve kabul
--     kapisindan GECMEZ. Dogru mesaji yanlis kodla uretmek bir regresyondur.
--
--  9) BEKLENMEYEN HATA BASARI SAYILMAZ; ayri sinif alir.
--
-- CALISTIRMA: salt sonda kipinde, TEK oturumda, dosyanin tamami verilerek.
--   .\docs\kurulum\sql-uygula.ps1 -Dosya docs\kurulum\2026-10-09-pms-mali-sunucu-retleri-sondasi.sql -SaltOkuma
-- `-SaltOkuma` tek islem sarmalayicisi EKLEMEZ; islem sinirini bu dosya kurar.
-- ===========================================================================

begin;

-- ---------------------------------------------------------------------------
-- HEDEF SECIMI — OPERATOR BU DORT SATIRI DOLDURUR (kural 1)
-- ---------------------------------------------------------------------------
-- hedef_otel     : otel kodu, ornegin '810'
-- hedef_personel : `auth.users.id` (kullanicilar.auth_user_id) — pms_folio
--                  yetkisi KAYIT olan on buro personeli
-- hedef_yonetici : `auth.users.id` — pms_folio yetkisi TAM olan kullanici
-- hedef_misafir  : SENTETIK QA misafirinin SOYADI (icinde 'QA' gecmeli),
--                  ornegin 'QA-DORNEVI-20261008'
set local sonda.hedef_otel     = 'DOLDUR';
set local sonda.hedef_personel = 'DOLDUR';
set local sonda.hedef_yonetici = 'DOLDUR';
set local sonda.hedef_misafir  = 'DOLDUR';

create temporary table sonda_sonuc(
  sira      int,
  kontrol   text,
  kimlik    text,
  rol       text,
  super     boolean,
  bypassrls boolean,
  sinif     text,
  sqlstate  text,
  mesaj     text
) on commit drop;

create temporary table sonda_hedef(
  alan  text,
  deger text
) on commit drop;

do $sonda$
declare
  v_otel_t   text := current_setting('sonda.hedef_otel',     true);
  v_pers_t   text := current_setting('sonda.hedef_personel', true);
  v_yon_t    text := current_setting('sonda.hedef_yonetici', true);
  v_mis_t    text := current_setting('sonda.hedef_misafir',  true);
  v_otel     public.otel_id;
  v_personel uuid;
  v_yonetici uuid;
  v_misafir  uuid;
  v_odatipi  uuid;
  v_odatipi_ad text;
  v_rez      uuid;
  v_folio    uuid;
  v_hareket  uuid;
  v_odeme    uuid;
  v_durum    text;
  v_n        int;
  v_yetki    text;
  -- deneme tanimlari (alti deneme, tek siniflandirma yolu)
  v_ad       text[];
  v_kim      uuid[];
  v_dml      text[];
  v_bek_msg  text[];
  v_bek_sts  text[];
  v_degismez boolean[];
  i          int;
  v_cu       text;
  v_super    boolean;
  v_bypass   boolean;
  v_state    text;
  v_msg      text;
  v_sinif    text;
begin
  -- =====================================================================
  -- 0) HEDEF SECIMININ DOGRULANMASI — eksik/coklu eslesmede DUR (kural 1, 4)
  -- =====================================================================
  if v_otel_t is null or v_otel_t = 'DOLDUR'
     or v_pers_t is null or v_pers_t = 'DOLDUR'
     or v_yon_t  is null or v_yon_t  = 'DOLDUR'
     or v_mis_t  is null or v_mis_t  = 'DOLDUR' then
    raise exception 'SONDA KURULAMADI: hedef secimi DOLDURULMAMIS — '
      'dosyanin basindaki sonda.hedef_* satirlarini doldurun '
      '(otel=%, personel=%, yonetici=%, misafir=%)',
      coalesce(v_otel_t,'<yok>'), coalesce(v_pers_t,'<yok>'),
      coalesce(v_yon_t,'<yok>'),  coalesce(v_mis_t,'<yok>');
  end if;

  v_otel     := v_otel_t::public.otel_id;   -- gecersiz kod burada patlar
  v_personel := v_pers_t::uuid;
  v_yonetici := v_yon_t::uuid;

  if position('QA' in upper(v_mis_t)) = 0 then
    raise exception 'SONDA KURULAMADI: misafir isareti SENTETIK gorunmuyor (%) — '
      'icinde QA gecmeyen bir soyadla kosulmaz', v_mis_t;
  end if;

  -- Otel: hedef otelde aktif kullanici olmali (otel kodu gercekten kullanimda)
  select count(*) into v_n from public.kullanicilar
   where otel_id = v_otel and aktif;
  if v_n = 0 then
    raise exception 'SONDA KURULAMADI: otel % icin aktif kullanici yok', v_otel;
  end if;

  -- Personel: TAM OLARAK BIR aktif kullanici, hedef otelde
  select count(*) into v_n from public.kullanicilar
   where auth_user_id = v_personel and aktif and otel_id = v_otel;
  if v_n <> 1 then
    raise exception 'SONDA KURULAMADI: personel kimligi % icin otel %-de '
      'eslesen aktif kullanici sayisi % (beklenen 1)', v_personel, v_otel, v_n;
  end if;

  -- Personelin pms_folio yetkisi KAYIT olmali; TAM ise K1 olcumu anlamsizdir
  select y.yetki::text into v_yetki
    from public.kullanicilar k
    join public.yetki_matrisi y on y.rol_id = k.rol_id
    join public.moduller m on m.id = y.modul_id
   where k.auth_user_id = v_personel and k.aktif and k.otel_id = v_otel
     and m.kod = 'pms_folio';
  if v_yetki is distinct from 'kayit' then
    raise exception 'SONDA KURULAMADI: personelin pms_folio yetkisi % '
      '(beklenen kayit) — TAM yetkili kimlikle K1 olculemez',
      coalesce(v_yetki, '<yok>');
  end if;

  -- Yonetici: TAM OLARAK BIR aktif kullanici, hedef otelde, pms_folio=tam
  select count(*) into v_n from public.kullanicilar
   where auth_user_id = v_yonetici and aktif and otel_id = v_otel;
  if v_n <> 1 then
    raise exception 'SONDA KURULAMADI: yonetici kimligi % icin otel %-de '
      'eslesen aktif kullanici sayisi % (beklenen 1)', v_yonetici, v_otel, v_n;
  end if;

  select y.yetki::text into v_yetki
    from public.kullanicilar k
    join public.yetki_matrisi y on y.rol_id = k.rol_id
    join public.moduller m on m.id = y.modul_id
   where k.auth_user_id = v_yonetici and k.aktif and k.otel_id = v_otel
     and m.kod = 'pms_folio';
  if v_yetki is distinct from 'tam' then
    raise exception 'SONDA KURULAMADI: yoneticinin pms_folio yetkisi % '
      '(beklenen tam) — K2 gerekce kontrolu olculemez',
      coalesce(v_yetki, '<yok>');
  end if;

  if v_personel = v_yonetici then
    raise exception 'SONDA KURULAMADI: personel ve yonetici ayni kimlik (%)',
      v_personel;
  end if;

  -- Misafir: YALNIZ sentetik, TAM OLARAK BIR eslesme (kural 4)
  select count(*) into v_n from public.pms_misafirler
   where otel_id = v_otel and aktif and soyad = v_mis_t;
  if v_n = 0 then
    raise exception 'SONDA KURULAMADI: sentetik misafir "%" otel %-de YOK',
      v_mis_t, v_otel;
  end if;
  if v_n > 1 then
    raise exception 'SONDA KURULAMADI: sentetik misafir "%" otel %-de % kez '
      'eslesti — hangisi oldugu belirsiz, kosulmaz', v_mis_t, v_otel, v_n;
  end if;
  select id into v_misafir from public.pms_misafirler
   where otel_id = v_otel and aktif and soyad = v_mis_t;

  -- Oda tipi: hedefin kendisi degil, rezervasyonun zorunlu alani.
  -- Secim DETERMINISTIK (en kucuk kod) ve ciktida RAPORLANIR.
  select id, kod into v_odatipi, v_odatipi_ad from public.pms_oda_tipleri
   where otel_id = v_otel and aktif order by kod limit 1;
  if v_odatipi is null then
    raise exception 'SONDA KURULAMADI: otel %-de aktif oda tipi yok', v_otel;
  end if;

  insert into sonda_hedef values
    ('otel',           v_otel::text),
    ('personel (kayit)', v_personel::text),
    ('yonetici (tam)',   v_yonetici::text),
    ('sentetik misafir', v_mis_t || ' / ' || v_misafir::text),
    ('oda tipi (deterministik)', v_odatipi_ad || ' / ' || v_odatipi::text);

  -- =====================================================================
  -- 1) HEDEF FIKSTUR — PERSONEL KIMLIGIYLE (kural 3), GECICI (bkz. baslik)
  -- =====================================================================
  execute 'set local role authenticated';
  execute format('set local request.jwt.claims = %L',
    json_build_object('sub', v_personel, 'role', 'authenticated')::text);

  insert into public.pms_rezervasyonlar
    (otel_id, rezervasyon_no, misafir_id, oda_tipi_id,
     giris_tarihi, cikis_tarihi, durum, yetiskin_sayisi, cocuk_sayisi)
  values (v_otel, 'SONDA-' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISS'),
          v_misafir, v_odatipi, current_date, current_date + 1, 'onaylandi', 1, 0)
  returning id into v_rez;

  select id, durum::text into v_folio, v_durum
    from public.pms_folyolar where rezervasyon_id = v_rez;
  if v_folio is null then
    raise exception 'SONDA KURULAMADI: otomatik folyo acilmadi';
  end if;
  if v_durum <> 'acik' then
    raise exception 'SONDA KURULAMADI: hedef folyo ACIK degil (%) — '
      'kapali folyo asil yetki hatasini MASKELER', v_durum;
  end if;

  -- K3'un hedefi: POZITIF oda ucreti (hassas DEGIL; `kayit` ile yazilir).
  insert into public.pms_folio_hareketleri
    (otel_id, folio_id, tip, aciklama, tutar, konaklama_gecesi)
  values (v_otel, v_folio, 'oda_ucreti', 'SONDA hedef hareketi', 100.00, current_date)
  returning id into v_hareket;

  -- K4'un hedefi: POZITIF tahsilat (hassas DEGIL). Borctan KUCUK tutulur ki
  -- bakiye sifirlanmasin ve folyo ACIK kalsin (kural 7).
  insert into public.pms_folio_odemeler
    (otel_id, folio_id, yontem, tutar, aciklama)
  values (v_otel, v_folio, 'nakit', 10.00, 'SONDA hedef odemesi')
  returning id into v_odeme;

  execute 'reset role';

  if v_hareket is null or v_odeme is null then
    raise exception 'SONDA KURULAMADI: hedef mali satirlar yazilamadi';
  end if;

  -- =====================================================================
  -- 2) ALTI DENEME — tek siniflandirma yolu (kural 8: mesaj VE sqlstate)
  -- =====================================================================
  v_ad := array[
    'K1 personel negatif odeme',
    'K2 yonetici gerekcesiz iade',
    'K3a mevcut HAREKET satiri UPDATE',
    'K3b mevcut HAREKET satiri DELETE',
    'K4a mevcut ODEME satiri UPDATE',
    'K4b mevcut ODEME satiri DELETE'];
  v_kim := array[v_personel, v_yonetici, v_yonetici, v_yonetici,
                 v_yonetici, v_yonetici];
  v_dml := array[
    format('insert into public.pms_folio_odemeler '
           '(otel_id, folio_id, yontem, tutar, aciklama) '
           'values (%L, %L, %L, -50.00, %L)',
           v_otel, v_folio, 'nakit', 'SONDA K1'),
    -- K2: aciklama BILEREK verilmez -> gerekce zorunlulugu sinanir
    format('insert into public.pms_folio_odemeler '
           '(otel_id, folio_id, yontem, tutar) values (%L, %L, %L, -50.00)',
           v_otel, v_folio, 'nakit'),
    format('update public.pms_folio_hareketleri set tutar = 1 where id = %L',
           v_hareket),
    format('delete from public.pms_folio_hareketleri where id = %L', v_hareket),
    format('update public.pms_folio_odemeler set tutar = 1 where id = %L',
           v_odeme),
    format('delete from public.pms_folio_odemeler where id = %L', v_odeme)];
  v_bek_msg := array[
    'MALI_TAM_YETKI_GEREKLI%', 'MALI_GEREKCE_ZORUNLU%',
    'Finansal kayit degistirilemez%', 'Finansal kayit degistirilemez%',
    'Finansal kayit degistirilemez%', 'Finansal kayit degistirilemez%'];
  v_bek_sts := array['42501', '23514', '42501', '42501', '42501', '42501'];
  -- degismezlik denemelerinde ayricalik/RLS katmani da MESRU RET sayilir
  v_degismez := array[false, false, true, true, true, true];

  for i in 1 .. 6 loop
    execute 'set local role authenticated';
    execute format('set local request.jwt.claims = %L',
      json_build_object('sub', v_kim[i], 'role', 'authenticated')::text);
    v_cu := current_user;
    select rolsuper, rolbypassrls into v_super, v_bypass
      from pg_roles where rolname = v_cu;

    begin
      execute v_dml[i];
      v_sinif := 'KABUL (KUSUR)'; v_state := null;
      v_msg := 'Islem KABUL EDILDI; rollback ile geri alinacak';
    exception when others then
      get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
      v_sinif := case
        -- Beklenen metin VE beklenen SQLSTATE birlikte tutuyor
        when v_msg like v_bek_msg[i] and v_state = v_bek_sts[i]
          then 'BEKLENEN RET' ||
               case when v_degismez[i] then ' (tetikleyici)' else '' end
        -- Metin tutuyor ama kod yanlis: REGRESYON, kabul EDILMEZ (kural 8)
        when v_msg like v_bek_msg[i]
          then 'SQLSTATE YANLIS (GECERSIZ): bek=' || v_bek_sts[i]
               || ' olc=' || coalesce(v_state, '<yok>')
        -- Maskeleme: ret var ama yanlis sebepten (kural 6, 7)
        when v_msg like 'Kapali folyoya%'         then 'MASKELENDI (GECERSIZ)'
        when v_msg like '%read-only transaction%' then 'MASKELENDI (GECERSIZ)'
        -- Degismezlikte UC katman: ayricalik YOK + politika YOK + tetikleyici.
        -- Hangisi once vurursa vursun RET mesrudur; katman adi raporlanir.
        when v_degismez[i] and v_state = '42501'
             and v_msg like 'permission denied for table pms_folio%'
          then 'BEKLENEN RET (ayricalik)'
        when v_degismez[i] and v_state = '42501'
             and v_msg like '%row-level security%'
          then 'BEKLENEN RET (RLS)'
        -- Kimlik/katman karisikliklari ayri isaretlenir
        when v_msg like 'MALI_TAM_YETKI_GEREKLI%'
          then 'KIMLIK YANLIS (tam yetki yok)'
        when v_msg like 'MALI_GEREKCE_ZORUNLU%'
          then 'FARKLI KATMAN (gerekce once)'
        when v_msg like '%row-level security%' then 'FARKLI KATMAN (RLS)'
        when v_state = '42501'                 then 'FARKLI KATMAN (yetki)'
        else 'BEKLENMEYEN (GECERSIZ)' end;
    end;

    -- Sonuc tablosu oturum kullanicisinindir; `authenticated` iken yazilamaz.
    execute 'reset role';
    insert into sonda_sonuc values (i, v_ad[i], v_kim[i]::text, v_cu,
      v_super, v_bypass, v_sinif, v_state, left(v_msg, 180));
  end loop;
end $sonda$;

-- ---------------------------------------------------------------------------
-- SONUC
-- ---------------------------------------------------------------------------
select alan, deger from sonda_hedef;

select sira, kontrol, rol, super, bypassrls, sinif, sqlstate, mesaj
  from sonda_sonuc order by sira;

-- KIMLIK KAPISI: tek bir deneme bile gercek uygulama rolu disinda kostuysa
-- kosum GECERSIZDIR ve ret olarak okunamaz.
select case
    when count(*) filter (where rol <> 'authenticated' or super or bypassrls) > 0
      then 'GECERSIZ: en az bir deneme gercek uygulama rolu disinda kostu'
    when count(*) <> 6
      then 'GECERSIZ: beklenen 6 deneme, olculen ' || count(*)
    when count(*) filter (where sinif not like 'BEKLENEN RET%') > 0
      then 'INCELE: ' || coalesce(string_agg(sira || '=' || sinif, ', ')
             filter (where sinif not like 'BEKLENEN RET%'), '')
    else 'UYGUN: alti denemenin altisi da BEKLENEN RET'
  end as kimlik_ve_sonuc_kapisi
  from sonda_sonuc;

-- GECICI YAZMA ve DIZI ETKISI — acikca raporlanir
select 'GECICI YAZMA: 1 rezervasyon + 1 folyo (otomatik) + 1 hareket + '
       '1 odeme yazildi; hepsi ROLLBACK ile geri alinir. '
       'KALICI IZ: pms_rezervasyon_no_seq ve pms_folio_no_seq birer artar '
       '(numara bosluklari geri alinmaz).' as yazma_ve_dizi_etkisi,
       pg_sequence_last_value('public.pms_rezervasyon_no_seq') as rez_no_son,
       pg_sequence_last_value('public.pms_folio_no_seq')       as folio_no_son;

-- Islem icinde yazilan her sey geri alinir. Beklenmedik KABUL olsa bile
-- kalici satir kalmaz. (Dizi numaralarinda bosluk kalir; bilinen tek iz.)
rollback;
