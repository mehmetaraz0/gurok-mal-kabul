-- ============================================================================
-- PMS FAZ 2 — KAT HİZMETLERİ NİHAİ KABUL TESTLERİ
-- ----------------------------------------------------------------------------
-- YALNIZ ATILABILIR YEREL/STAGING VERİTABANINDA ÇALIŞTIRILIR.
--   psql -X -U postgres -d hkdb -f scripts/pms-faz2-housekeeping-son-kabul.sql
--
-- Üç sözleşmeyi DAVRANIŞSAL olarak kanıtlar:
--   M1-M8  Modül kapatma sözleşmesi
--   D1-D4  Denetim izi başarısızlığında ATOMİKLİK
--   C1-C4  Check-out ATOMİKLİĞİ ve tekrar korumaları
--
-- Sabotaj tespiti tek başına atomiklik kanıtı DEĞİLDİR; burada iş
-- mutasyonunun, oda izdüşümünün ve denetim satırının GERİ ALINDIĞI
-- ayrı ayrı ölçülür.
--
-- Tüm dosya tek transaction'dadır ve ROLLBACK edilir.
-- ============================================================================

\set ON_ERROR_STOP on

begin;

do $$
declare
  v_ok int := 0; v_fail int := 0;
  v_rol uuid; v_a uuid := gen_random_uuid(); v_k uuid;
  v_a2 uuid := gen_random_uuid(); v_k2 uuid;
  v_tip uuid; v_mis uuid;
  v_oda uuid; v_odaB uuid; v_odaC uuid; v_odaD uuid; v_odaE uuid;
  v_rez uuid; v_rezB uuid; v_rezC uuid;
  v_g uuid; v_g2 uuid; v_g3 uuid;
  v_n int; v_n2 int; v_txt text; v_txt2 text;
  v_surum bigint; v_durum text;
  v_ek text := substr(md5(random()::text || clock_timestamp()::text), 1, 6);
begin
  -- =====================================================================
  -- FİKSTÜR
  -- =====================================================================
  update public.moduller set aktif = true where kod = 'pms_housekeeping';
  insert into public.moduller (kod, ad, kategori, sira, aktif) values
    ('pms_oda','On Buro - Odalar','onburo',44,true),
    ('pms_oda_tipi','On Buro - Oda Tipleri','onburo',43,true),
    ('pms_misafir','On Buro - Misafirler','onburo',45,true),
    ('pms_rezervasyon','On Buro - Rezervasyonlar','onburo',47,true)
  on conflict (kod) do update set aktif = true;

  insert into public.roller (ad, seviye) values ('SK Rol '||v_ek,'otel') returning id into v_rol;
  insert into public.yetki_matrisi (rol_id, modul_id, yetki)
  select v_rol, id, 'tam' from public.moduller
   where kod in ('pms_housekeeping','pms_oda','pms_oda_tipi','pms_misafir','pms_rezervasyon');

  insert into auth.users (id) values (v_a);
  insert into public.kullanicilar (ad, rol, rol_id, otel_id, aktif, auth_user_id)
  values ('SK Kullanici','yonetici', v_rol, '810', true, v_a) returning id into v_k;
  insert into auth.users (id) values (v_a2);
  insert into public.kullanicilar (ad, rol, rol_id, otel_id, aktif, auth_user_id)
  values ('SK Denetci','yonetici', v_rol, '810', true, v_a2) returning id into v_k2;

  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config('request.jwt.claim.sub', v_a::text, true);

  insert into public.pms_oda_tipleri (otel_id,kod,ad,azami_kisi,azami_yetiskin,azami_cocuk)
  values ('810','sk'||v_ek,'SK '||v_ek,2,2,1) returning id into v_tip;
  insert into public.pms_misafirler (otel_id, ad, soyad)
  values ('810','SK','Misafir') returning id into v_mis;

  insert into public.pms_odalar (otel_id,oda_tipi_id,oda_no)
  values ('810',v_tip,'SKA-'||v_ek) returning id into v_oda;
  insert into public.pms_odalar (otel_id,oda_tipi_id,oda_no)
  values ('810',v_tip,'SKB-'||v_ek) returning id into v_odaB;
  insert into public.pms_odalar (otel_id,oda_tipi_id,oda_no)
  values ('810',v_tip,'SKC-'||v_ek) returning id into v_odaC;
  insert into public.pms_odalar (otel_id,oda_tipi_id,oda_no)
  values ('810',v_tip,'SKD-'||v_ek) returning id into v_odaD;
  insert into public.pms_odalar (otel_id,oda_tipi_id,oda_no)
  values ('810',v_tip,'SKE-'||v_ek) returning id into v_odaE;

  -- =====================================================================
  -- C1  BAŞARILI CHECK-OUT — tam sözleşme
  -- =====================================================================
  update public.pms_odalar set temizlik_durumu='temiz' where id=v_oda;
  insert into public.pms_rezervasyonlar
    (otel_id, misafir_id, oda_tipi_id, giris_tarihi, cikis_tarihi,
     yetiskin_sayisi, durum, gecelik_fiyat)
  values ('810', v_mis, v_tip, public.pms_bugun(), public.pms_bugun()+1, 1, 'onaylandi', 100)
  returning id into v_rez;

  -- Faz 1'in ertelenmis `pms_tutarlilik_oda` olayi, check-in ve check-out
  -- AYNI transaction'da yapilirsa bayat kalir. Uretimde bunlar ayri
  -- transaction'lardir; burada her adimdan sonra kuyruk bosaltilarak ayni
  -- kosul saglanir. Bu bir gevsetme degil, dogru sinir kosulunun kurulmasidir.
  execute 'set local role authenticated';
  perform public.pms_check_in(v_rez, v_oda);
  execute 'reset role';
  set constraints all immediate;   -- kuyrugu bosalt
  set constraints all deferred;    -- ERTELENMIS moda geri don (varsayilan)

  execute 'set local role authenticated';
  perform public.pms_check_out(v_rez);
  execute 'reset role';
  set constraints all immediate;   -- kuyrugu bosalt
  set constraints all deferred;    -- ERTELENMIS moda geri don (varsayilan)

  select durum::text into v_durum from public.pms_rezervasyonlar where id=v_rez;
  select kullanim_durumu::text||'|'||temizlik_durumu::text into v_txt
    from public.pms_odalar where id=v_oda;
  select count(*) into v_n from public.pms_oda_atamalari
   where rezervasyon_id=v_rez;                       -- gecmis KORUNUR
  select count(*) into v_n2 from public.pms_housekeeping_gorevleri
   where oda_id=v_oda and gorev_tipi='cikis_temizligi' and olusturma_kaynagi='checkout';

  if v_durum='cikis_yapildi' and v_txt='bos|kirli' and v_n=1 and v_n2=1 then
    raise notice 'C1  OK    check-out sozlesmesi: rez=% oda=% atama gecmisi=% cikis gorevi=%',
      v_durum, v_txt, v_n, v_n2;
    v_ok:=v_ok+1;
  else
    raise notice 'C1  FAIL  rez=% oda=% atama=% gorev=%', v_durum, v_txt, v_n, v_n2;
    v_fail:=v_fail+1;
  end if;

  -- =====================================================================
  -- C2  TEKRARLANAN CHECK-OUT mükerrer çıkış görevi ÜRETEMEZ
  -- =====================================================================
  begin
    execute 'set local role authenticated';
    perform public.pms_check_out(v_rez);
    execute 'reset role';
    raise notice 'C2  FAIL  ikinci check-out gecti'; v_fail:=v_fail+1;
  exception when others then
    execute 'reset role';
    select count(*) into v_n from public.pms_housekeeping_gorevleri
     where oda_id=v_oda and gorev_tipi='cikis_temizligi';
    if v_n = 1 then
      raise notice 'C2  OK    ikinci check-out reddedildi, cikis gorevi hala tek (%)', v_n;
      v_ok:=v_ok+1;
    else
      raise notice 'C2  FAIL  cikis gorevi sayisi %', v_n; v_fail:=v_fail+1;
    end if;
  end;

  -- =====================================================================
  -- C3  ÜRETİCİ HATASI TÜM CHECK-OUT'U GERİ ALIR
  -- Yalnız kat hizmetleri üreticisini patlatan bir kısıt konur.
  -- =====================================================================
  update public.pms_odalar set temizlik_durumu='temiz' where id=v_odaB;
  insert into public.pms_rezervasyonlar
    (otel_id, misafir_id, oda_tipi_id, giris_tarihi, cikis_tarihi,
     yetiskin_sayisi, durum, gecelik_fiyat)
  values ('810', v_mis, v_tip, public.pms_bugun(), public.pms_bugun()+1, 1, 'onaylandi', 100)
  returning id into v_rezB;

  execute 'set local role authenticated';
  perform public.pms_check_in(v_rezB, v_odaB);
  execute 'reset role';
  set constraints all immediate;   -- kuyrugu bosalt
  set constraints all deferred;    -- ERTELENMIS moda geri don (varsayilan)

  -- Ertelenmis kisit olaylari kuyrukta dururken ALTER TABLE yapilamaz.
  -- Kuyrugu bosaltmak ayrica onceki adimlarin TUTARLI bittigini de kanitlar.
  set constraints all immediate;   -- kuyrugu bosalt
  set constraints all deferred;    -- ERTELENMIS moda geri don (varsayilan)
  alter table public.pms_housekeeping_gorevleri
    add constraint sk_uretici_patlat check (olusturma_kaynagi <> 'checkout') not valid;

  begin
    execute 'set local role authenticated';
    perform public.pms_check_out(v_rezB);
    execute 'reset role';
    raise notice 'C3  FAIL  uretici patlamasina ragmen check-out gecti'; v_fail:=v_fail+1;
  exception when others then
    execute 'reset role';
    select durum::text into v_durum from public.pms_rezervasyonlar where id=v_rezB;
    select kullanim_durumu::text||'|'||temizlik_durumu::text into v_txt
      from public.pms_odalar where id=v_odaB;
    select count(*) into v_n from public.pms_housekeeping_gorevleri where oda_id=v_odaB;
    if v_durum='giris_yapildi' and v_txt='dolu|temiz' and v_n=0 then
      raise notice 'C3  OK    TUM check-out geri alindi: rez=% oda=% gorev=%',
        v_durum, v_txt, v_n;
      v_ok:=v_ok+1;
    else
      raise notice 'C3  FAIL  YARIM DURUM: rez=% oda=% gorev=%', v_durum, v_txt, v_n;
      v_fail:=v_fail+1;
    end if;
  end;

  set constraints all immediate;   -- kuyrugu bosalt
  set constraints all deferred;    -- ERTELENMIS moda geri don (varsayilan)
  alter table public.pms_housekeeping_gorevleri drop constraint sk_uretici_patlat;

  -- C4: kisit kalkinca ayni check-out normal calisir (yan etki kalmadi)
  begin
    execute 'set local role authenticated';
    perform public.pms_check_out(v_rezB);
    execute 'reset role';
    select count(*) into v_n from public.pms_housekeeping_gorevleri
     where oda_id=v_odaB and gorev_tipi='cikis_temizligi';
    if v_n = 1 then
      raise notice 'C4  OK    kisit kalkinca check-out temiz calisti (gorev=%)', v_n;
      v_ok:=v_ok+1;
    else raise notice 'C4  FAIL  gorev=%', v_n; v_fail:=v_fail+1; end if;
  exception when others then
    execute 'reset role';
    raise notice 'C4  FAIL  %', sqlerrm; v_fail:=v_fail+1;
  end;

  -- =====================================================================
  -- D1  DENETİM KATMANI PATLARSA KOMUT TÜMÜYLE GERİ ALINIR
  -- Yalnız denetim INSERT'i reddedilir; is mantigina DOKUNULMAZ.
  -- =====================================================================
  v_g := (public.pms_housekeeping_gorev_olustur(v_odaC,'ekstra_temizlik','bos',
            gen_random_uuid())->>'gorev_id')::uuid;
  select surum into v_surum from public.pms_housekeeping_gorevleri where id=v_g;
  select kullanim_durumu::text||'|'||temizlik_durumu::text into v_txt
    from public.pms_odalar where id=v_odaC;
  select count(*) into v_n from public.erp_islem_audit where entity_id=v_g::text;

  set constraints all immediate;   -- kuyrugu bosalt
  set constraints all deferred;    -- ERTELENMIS moda geri don (varsayilan)
  alter table public.erp_islem_audit
    add constraint sk_denetim_patlat
    check (entity_type <> 'pms_housekeeping_gorevleri') not valid;

  begin
    perform public.pms_housekeeping_sahiplen(v_g, v_surum, gen_random_uuid());
    raise notice 'D1  FAIL  denetim patlamasina ragmen komut gecti'; v_fail:=v_fail+1;
  exception when others then
    select durum into v_durum
      from public.pms_housekeeping_gorevleri where id=v_g;
    select kullanim_durumu::text||'|'||temizlik_durumu::text into v_txt2
      from public.pms_odalar where id=v_odaC;
    select count(*) into v_n2 from public.erp_islem_audit where entity_id=v_g::text;
    if v_durum='bekliyor' and v_txt2=v_txt and v_n2=v_n then
      raise notice 'D1  OK    komut geri alindi: gorev=% oda=% denetim satiri=%(degismedi)',
        v_durum, v_txt2, v_n2;
      v_ok:=v_ok+1;
    else
      raise notice 'D1  FAIL  YARIM DURUM: gorev=% oda=%/% denetim=%/%',
        v_durum, v_txt2, v_txt, v_n2, v_n;
      v_fail:=v_fail+1;
    end if;
  end;

  -- D2: gorev satiri gercekten DEGISMEDI (surum ilerlememeli)
  select surum into v_surum from public.pms_housekeeping_gorevleri where id=v_g;
  if v_surum = 1 then
    raise notice 'D2  OK    surum ilerlemedi (%)', v_surum; v_ok:=v_ok+1;
  else raise notice 'D2  FAIL  surum %', v_surum; v_fail:=v_fail+1; end if;

  -- D3: ESKI (kat hizmetleri disi) denetim cagiranlari DAVRANISINI KORUR
  --     islem_detayi NULL kalmali ve yazma BASARILI olmali.
  begin
    insert into public.pms_rezervasyonlar
      (otel_id, misafir_id, oda_tipi_id, giris_tarihi, cikis_tarihi,
       yetiskin_sayisi, durum, gecelik_fiyat)
    values ('810', v_mis, v_tip, public.pms_bugun()+30, public.pms_bugun()+31, 1, 'onaylandi', 100)
    returning id into v_rezC;
    select count(*) into v_n from public.erp_islem_audit
     where entity_id=v_rezC::text and islem_detayi is null;
    if v_n >= 1 then
      raise notice 'D3  OK    eski denetim cagirani degismedi (islem_detayi NULL, % satir)', v_n;
      v_ok:=v_ok+1;
    else
      raise notice 'D3  FAIL  eski cagiran icin NULL detayli denetim satiri yok'; v_fail:=v_fail+1;
    end if;
  exception when others then
    raise notice 'D3  FAIL  %', sqlerrm; v_fail:=v_fail+1;
  end;

  set constraints all immediate;   -- kuyrugu bosalt
  set constraints all deferred;    -- ERTELENMIS moda geri don (varsayilan)
  alter table public.erp_islem_audit drop constraint sk_denetim_patlat;

  -- D4: kisit kalkinca ayni komut normal calisir ve denetim satiri OLUSUR
  begin
    select surum into v_surum from public.pms_housekeeping_gorevleri where id=v_g;
    perform public.pms_housekeeping_sahiplen(v_g, v_surum, gen_random_uuid());
    select count(*) into v_n2 from public.erp_islem_audit
     where entity_id=v_g::text and islem_detayi is not null;
    if v_n2 >= 1 then
      raise notice 'D4  OK    kisit kalkinca komut+denetim birlikte gecti (% detayli satir)', v_n2;
      v_ok:=v_ok+1;
    else raise notice 'D4  FAIL  detayli denetim satiri yok'; v_fail:=v_fail+1; end if;
  exception when others then
    raise notice 'D4  FAIL  %', sqlerrm; v_fail:=v_fail+1;
  end;

  -- =====================================================================
  -- MODÜL KAPATMA SÖZLEŞMESİ
  -- =====================================================================
  -- Kapatmadan ONCE: odaD icin bekleyen gorev ve suren bir konaklama
  update public.pms_odalar set temizlik_durumu='temiz' where id=v_odaD;
  insert into public.pms_rezervasyonlar
    (otel_id, misafir_id, oda_tipi_id, giris_tarihi, cikis_tarihi,
     yetiskin_sayisi, durum, gecelik_fiyat)
  values ('810', v_mis, v_tip, public.pms_bugun(), public.pms_bugun()+1, 1, 'onaylandi', 100)
  returning id into v_rezC;
  execute 'set local role authenticated';
  perform public.pms_check_in(v_rezC, v_odaD);
  execute 'reset role';
  set constraints all immediate;   -- kuyrugu bosalt
  set constraints all deferred;    -- ERTELENMIS moda geri don (varsayilan)

  v_g2 := (public.pms_housekeeping_gorev_olustur(v_odaD,'ekstra_temizlik','dolu',
             gen_random_uuid())->>'gorev_id')::uuid;

  -- M5 icin AYRI bir oda: check-out yoluna hic girmeyecek.
  -- Mimari §10: `ariza` gecisinde BEKLEYEN is KORUNUR, yalniz CALISAN is
  -- `oda_ariza` ile iptal edilir. Bu yuzden gorev CALISIR hale getirilir;
  -- aksi halde test gecersizlestiriciyi hic sinamamis olurdu.
  v_g3 := (public.pms_housekeeping_gorev_olustur(v_odaE,'ekstra_temizlik','bos',
             gen_random_uuid())->>'gorev_id')::uuid;
  perform public.pms_housekeeping_sahiplen(v_g3,
    (select surum from public.pms_housekeeping_gorevleri where id=v_g3), gen_random_uuid());
  perform public.pms_housekeeping_baslat(v_g3,
    (select surum from public.pms_housekeeping_gorevleri where id=v_g3), gen_random_uuid());

  select count(*) into v_n from public.pms_housekeeping_gorevleri;

  -- Faz 1'in `pms_tutarlilik_oda` fonksiyonu kuyruga giren olayi BAYAT NEW
  -- anlik goruntusuyle degerlendiriyor (kat hizmetleri kontrolleri aksine
  -- anahtardan YENIDEN OKUR). Uretimde her islem ayri transaction oldugu
  -- icin bu ortaya cikmaz; burada kurulum bitince kuyruk bosaltilarak ayni
  -- kosul saglanir. Faz 1 davranisi DEGISTIRILMEMISTIR.
  set constraints all immediate;
  set constraints all deferred;

  -- ---- MODÜL KAPATILIYOR ----
  update public.moduller set aktif=false where kod='pms_housekeeping';

  -- M1: genel kat hizmetleri RPC'si REDDEDILIR
  begin
    perform public.pms_housekeeping_gorev_olustur(v_odaC,'ekstra_temizlik','bos',
              gen_random_uuid());
    raise notice 'M1  FAIL  modul kapaliyken RPC gecti'; v_fail:=v_fail+1;
  exception when others then
    raise notice 'M1  OK    modul kapaliyken RPC reddedildi (%)', sqlstate; v_ok:=v_ok+1;
  end;

  -- M2/M3/M4: CHECK-OUT calisir, oda kirli kalir, YENI gorev URETILMEZ
  begin
    execute 'set local role authenticated';
    perform public.pms_check_out(v_rezC);
    execute 'reset role';
    set constraints all immediate;   -- kuyrugu bosalt
    set constraints all deferred;
    select kullanim_durumu::text||'|'||temizlik_durumu::text into v_txt
      from public.pms_odalar where id=v_odaD;
    select count(*) into v_n2 from public.pms_housekeeping_gorevleri
     where oda_id=v_odaD and gorev_tipi='cikis_temizligi';
    if v_txt='bos|kirli' then
      raise notice 'M2  OK    modul kapaliyken check-out calisti'; v_ok:=v_ok+1;
      raise notice 'M3  OK    oda kirli birakildi (%)', v_txt; v_ok:=v_ok+1;
    else
      raise notice 'M2/M3 FAIL  oda=%', v_txt; v_fail:=v_fail+2;
    end if;
    if v_n2 = 0 then
      raise notice 'M4  OK    modul kapaliyken YENI cikis gorevi uretilmedi'; v_ok:=v_ok+1;
    else
      raise notice 'M4  FAIL  % cikis gorevi uretildi', v_n2; v_fail:=v_fail+1;
    end if;
  exception when others then
    execute 'reset role';
    raise notice 'M2/M3/M4 FAIL  check-out patladi: %', sqlerrm; v_fail:=v_fail+3;
  end;

  -- M5: yasam dongusu gecersizlestiricisi CALISMAYA DEVAM EDER
  begin
    execute 'set local role authenticated';
    update public.pms_odalar set kullanim_durumu='ariza' where id=v_odaE;
    execute 'reset role';
    select durum||coalesce('/'||iptal_nedeni,'') into v_txt
      from public.pms_housekeeping_gorevleri where id=v_g3;
    select temizlik_durumu::text into v_txt2 from public.pms_odalar where id=v_odaE;
    if v_txt='iptal/oda_ariza' and v_txt2='kirli' then
      raise notice 'M5  OK    modul kapaliyken gecersizlestirici calisti (gorev=%, oda=%)',
        v_txt, v_txt2;
      v_ok:=v_ok+1;
    else
      raise notice 'M5  FAIL  gorev=% oda=%', v_txt, v_txt2; v_fail:=v_fail+1;
    end if;
  exception when others then
    execute 'reset role';
    raise notice 'M5  FAIL  %', sqlerrm; v_fail:=v_fail+1;
  end;

  -- M6: mevcut gorev/gecmis BOZULMAZ (satir sayisi azalmadi)
  select count(*) into v_n2 from public.pms_housekeeping_gorevleri;
  if v_n2 >= v_n then
    raise notice 'M6  OK    gorev gecmisi korundu (% -> %)', v_n, v_n2; v_ok:=v_ok+1;
  else
    raise notice 'M6  FAIL  gorev sayisi dustu (% -> %)', v_n, v_n2; v_fail:=v_fail+1;
  end if;

  -- M7: modul kapaliyken ESKI/DOGRUDAN temizlik yamasi ACILMAZ
  begin
    execute 'set local role authenticated';
    update public.pms_odalar set temizlik_durumu='temiz' where id=v_odaC;
    execute 'reset role';
    raise notice 'M7  FAIL  dogrudan temizlik yamasi gecti'; v_fail:=v_fail+1;
  exception when others then
    execute 'reset role';
    raise notice 'M7  OK    dogrudan temizlik yamasi hala reddediliyor (%)', sqlstate;
    v_ok:=v_ok+1;
  end;

  -- M8: ucustaki komut vs kapatma -> TAHLIYE BARIYERI
  -- Bu tek oturumda kanitlanamaz (iki transaction gerekir); gercek iki
  -- oturumlu kaniti eszamanlilik dosyasindaki EZ-E'dir. Burada yalnizca
  -- bariyerin DAYANDIGI kilit yapisi dogrulanir.
  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
     where n.nspname='phase0_private' and p.proname='hk_modul_acik'
       and pg_get_functiondef(p.oid) ilike '%for share%'
  ) then
    raise notice 'M8  OK    tahliye bariyeri: hk_modul_acik modul satirini FOR SHARE tutuyor (davranissal kanit: EZ-E)';
    v_ok:=v_ok+1;
  else
    raise notice 'M8  FAIL  hk_modul_acik paylasimli kilit almiyor'; v_fail:=v_fail+1;
  end if;

  update public.moduller set aktif=true where kod='pms_housekeeping';

  -- =====================================================================
  -- H9  BAYAT (GUNCEL OLMAYAN) GOREV YENI DONGUYU SERTIFIKA EDEMEZ
  -- ---------------------------------------------------------------------
  -- SOZLESME: eski/gecmis bir gorev, odanin GUNCEL temizlik durumunu ya da
  -- gosterge sahipligini YENI dongu adina degistiremez.
  --
  -- Sonda BILEREK dar secildi: A gorevi `tamamlandi` durumunda birakilir,
  -- denetleyen atanandan FARKLI bir kullanicidir ve `tamamlandi ->
  -- kontrol_edildi` DURUM MAKINESINE GORE GECERLI bir gecistir. Yani bu
  -- islemi durduracak TEK sey gosterge sahipligi kontroludur; H1/H2/H4
  -- gibi baska bir koruma ON-KESEMEZ.
  --
  -- Tetikleyiciler ACIK, gercek RPC'ler kullanilir (guvenilir yazar YOK).
  -- =====================================================================
  declare
    v_odaF uuid; v_gA uuid; v_gB uuid; v_rr jsonb;
    v_oncePtr uuid; v_onceTemiz text;
  begin
    insert into public.pms_odalar (otel_id,oda_tipi_id,oda_no)
    values ('810',v_tip,'SKF-'||v_ek) returning id into v_odaF;

    -- ---- ESKI DONGU: gorev A olusur, calisir ve TAMAMLANIR --------------
    perform set_config('request.jwt.claim.sub', v_a::text, true);
    v_gA := (public.pms_housekeeping_gorev_olustur(v_odaF,'ekstra_temizlik','bos',
               gen_random_uuid())->>'gorev_id')::uuid;
    perform public.pms_housekeeping_sahiplen(v_gA,
      (select surum from public.pms_housekeeping_gorevleri where id=v_gA), gen_random_uuid());
    perform public.pms_housekeeping_baslat(v_gA,
      (select surum from public.pms_housekeeping_gorevleri where id=v_gA), gen_random_uuid());
    perform public.pms_housekeeping_tamamla(v_gA,
      (select surum from public.pms_housekeeping_gorevleri where id=v_gA), gen_random_uuid());

    -- ---- YENI DONGU: A yeniden acilir, ARDIL B olusur -------------------
    perform set_config('request.jwt.claim.sub', v_a2::text, true);
    v_rr := public.pms_housekeeping_yeniden_ac(v_gA, 'yeniden temizlik gerekti',
              (select surum from public.pms_housekeeping_gorevleri where id=v_gA),
              gen_random_uuid());
    v_gB := (v_rr->>'gorev_id')::uuid;

    select temizlik_gorevi_id, temizlik_durumu::text
      into v_oncePtr, v_onceTemiz from public.pms_odalar where id=v_odaF;

    -- ON KOSUL: A GECMISTE kaldi, gosterge YENI dongudedir.
    if not (v_oncePtr = v_gB and v_onceTemiz = 'kirli'
            and (select durum from public.pms_housekeeping_gorevleri where id=v_gA) = 'tamamlandi'
            and (select durum from public.pms_housekeeping_gorevleri where id=v_gB) = 'bekliyor') then
      raise notice 'H9  KURULUM HATASI  gosterge=% temizlik=% A=% B=%',
        v_oncePtr = v_gB, v_onceTemiz,
        (select durum from public.pms_housekeeping_gorevleri where id=v_gA),
        (select durum from public.pms_housekeeping_gorevleri where id=v_gB);
      v_fail:=v_fail+1;
    else
      -- ---- H9b NEGATIF: BAYAT A denetlenemez ---------------------------
      begin
        perform public.pms_housekeeping_kontrol_et(v_gA,
          (select surum from public.pms_housekeeping_gorevleri where id=v_gA),
          gen_random_uuid());
        raise notice 'H9b FAIL  BAYAT gorev A denetlendi (yeni donguyu sertifika etti)';
        v_fail:=v_fail+1;
      exception when others then
        if sqlerrm like '%guncel dongusu degil%' then
          -- Oda durumu ve gosterge YENI dongunun elinde KALDI mi?
          select temizlik_gorevi_id, temizlik_durumu::text
            into v_oncePtr, v_onceTemiz from public.pms_odalar where id=v_odaF;
          if v_oncePtr = v_gB and v_onceTemiz = 'kirli'
             and (select durum from public.pms_housekeeping_gorevleri where id=v_gA) = 'tamamlandi'
             and (select durum from public.pms_housekeeping_gorevleri where id=v_gB) = 'bekliyor' then
            raise notice 'H9b OK    bayat denetim reddedildi (%); oda=% gosterge=B, A=tamamlandi, B=bekliyor',
              sqlstate, v_onceTemiz;
            v_ok:=v_ok+1;
          else
            raise notice 'H9b FAIL  reddedildi ama durum kaydi: gosterge=B? % temizlik=%',
              v_oncePtr = v_gB, v_onceTemiz;
            v_fail:=v_fail+1;
          end if;
        else
          raise notice 'H9b FAIL  BASKA bir koruma on-kesti: % / %', sqlstate, left(sqlerrm,60);
          v_fail:=v_fail+1;
        end if;
      end;

      -- ---- H9a POZITIF: YENI dongunun KENDI gorevi sertifika EDEBILIR ---
      begin
        perform set_config('request.jwt.claim.sub', v_a::text, true);
        perform public.pms_housekeeping_sahiplen(v_gB,
          (select surum from public.pms_housekeeping_gorevleri where id=v_gB), gen_random_uuid());
        perform public.pms_housekeeping_baslat(v_gB,
          (select surum from public.pms_housekeeping_gorevleri where id=v_gB), gen_random_uuid());
        perform public.pms_housekeeping_tamamla(v_gB,
          (select surum from public.pms_housekeeping_gorevleri where id=v_gB), gen_random_uuid());
        perform set_config('request.jwt.claim.sub', v_a2::text, true);
        perform public.pms_housekeeping_kontrol_et(v_gB,
          (select surum from public.pms_housekeeping_gorevleri where id=v_gB), gen_random_uuid());

        select temizlik_gorevi_id, temizlik_durumu::text
          into v_oncePtr, v_onceTemiz from public.pms_odalar where id=v_odaF;
        if v_oncePtr = v_gB and v_onceTemiz = 'kontrol_edildi'
           and (select durum from public.pms_housekeeping_gorevleri where id=v_gA) = 'tamamlandi' then
          raise notice 'H9a OK    YENI dongu kendi gorevi ile odayi sertifika etti (oda=%, gosterge=B); A gecmiste kaldi',
            v_onceTemiz;
          v_ok:=v_ok+1;
        else
          raise notice 'H9a FAIL  gosterge=B? % temizlik=% A=%',
            v_oncePtr = v_gB, v_onceTemiz,
            (select durum from public.pms_housekeeping_gorevleri where id=v_gA);
          v_fail:=v_fail+1;
        end if;
      exception when others then
        raise notice 'H9a FAIL  mesru yeni dongu isi reddedildi: %', left(sqlerrm,70);
        v_fail:=v_fail+1;
      end;
    end if;
    perform set_config('request.jwt.claim.sub', v_a::text, true);
  end;

  -- =====================================================================
  -- H4, H6, H7, H8, H10 — EKSIK NEGATIF SONDALAR
  -- ---------------------------------------------------------------------
  -- H1/H2/H3/H5 icin negatif kanit BASKA dosyalarda mevcut (artim 2
  -- testleri ve sabotaj S1/S7). Burada YALNIZ eksik olanlar kapatilir.
  --
  -- KATMAN IZOLASYONU: yasak durumu KURABILMEK icin satir bekcileri bu
  -- blok boyunca kapatilir; olculen sey COMMIT ANI ertelenmis H kontrolu.
  -- Blok sonunda geri acilir.
  -- =====================================================================
  set constraints all immediate;   -- kuyrugu bosalt (ALTER icin sart)
  set constraints all deferred;
  alter table public.pms_housekeeping_gorevleri disable trigger pms_housekeeping_gorev_koruma;
  alter table public.pms_odalar disable trigger pms_housekeeping_oda_koruma;
  alter table public.pms_odalar disable trigger pms_housekeeping_oda_yasam_dongusu;

  -- H4: oda `temizleniyor` ama guncel gorev CALISMIYOR
  declare v_h uuid; begin
    insert into public.pms_odalar (otel_id,oda_tipi_id,oda_no)
    values ('810',v_tip,'H4-'||v_ek) returning id into v_h;
    update public.pms_odalar set temizlik_durumu='temizleniyor' where id=v_h;
    set constraints all immediate;
    raise notice 'H4  FAIL  ihlal kabul edildi'; v_fail:=v_fail+1;
    set constraints all deferred;
  exception when others then
    set constraints all deferred;
    if sqlerrm like 'H4:%' then
      raise notice 'H4  OK    %', left(sqlerrm,60); v_ok:=v_ok+1;
    else raise notice 'H4  FAIL  beklenen H4, gelen: %', left(sqlerrm,60); v_fail:=v_fail+1; end if;
  end;

  -- H6: denetlenen guncel gorev ama oda `kontrol_edildi` DEGIL
  declare v_h uuid; v_hg uuid; begin
    insert into public.pms_odalar (otel_id,oda_tipi_id,oda_no)
    values ('810',v_tip,'H6-'||v_ek) returning id into v_h;
    insert into public.pms_housekeeping_gorevleri
      (otel_id, oda_id, gorev_tipi, durum, olusturma_kaynagi, olusturan,
       atanan_kullanici_id, baslama_zamani, bitis_zamani, kontrol_eden, kontrol_zamani,
       istek_anahtari, istek_ozeti, son_islem_anahtari, son_islem_ozeti)
    values ('810', v_h, 'ekstra_temizlik', 'kontrol_edildi', 'kullanici', v_k, v_k,
            now(), now(), v_k2, now(),
            gen_random_uuid(), encode(sha256('h6'::bytea),'hex'),
            gen_random_uuid(), encode(sha256('h6'::bytea),'hex'))
    returning id into v_hg;
    update public.pms_odalar set temizlik_gorevi_id=v_hg, temizlik_durumu='kirli' where id=v_h;
    set constraints all immediate;
    raise notice 'H6  FAIL  ihlal kabul edildi'; v_fail:=v_fail+1;
    set constraints all deferred;
  exception when others then
    set constraints all deferred;
    if sqlerrm like 'H6:%' then
      raise notice 'H6  OK    %', left(sqlerrm,60); v_ok:=v_ok+1;
    else raise notice 'H6  FAIL  beklenen H6, gelen: %', left(sqlerrm,60); v_fail:=v_fail+1; end if;
  end;

  -- H7: iptal guncel gorev ama oda `kirli` DEGIL
  declare v_h uuid; v_hg uuid; begin
    insert into public.pms_odalar (otel_id,oda_tipi_id,oda_no)
    values ('810',v_tip,'H7-'||v_ek) returning id into v_h;
    insert into public.pms_housekeeping_gorevleri
      (otel_id, oda_id, gorev_tipi, durum, olusturma_kaynagi, olusturan,
       iptal_zamani, iptal_nedeni,
       istek_anahtari, istek_ozeti, son_islem_anahtari, son_islem_ozeti)
    values ('810', v_h, 'ekstra_temizlik', 'iptal', 'kullanici', v_k,
            now(), 'oda_bloke',
            gen_random_uuid(), encode(sha256('h7'::bytea),'hex'),
            gen_random_uuid(), encode(sha256('h7'::bytea),'hex'))
    returning id into v_hg;
    update public.pms_odalar set temizlik_gorevi_id=v_hg, temizlik_durumu='temiz' where id=v_h;
    set constraints all immediate;
    raise notice 'H7  FAIL  ihlal kabul edildi'; v_fail:=v_fail+1;
    set constraints all deferred;
  exception when others then
    set constraints all deferred;
    if sqlerrm like 'H7:%' then
      raise notice 'H7  OK    %', left(sqlerrm,60); v_ok:=v_ok+1;
    else raise notice 'H7  FAIL  beklenen H7, gelen: %', left(sqlerrm,60); v_fail:=v_fail+1; end if;
  end;

  -- H8: gosterge BASKA odanin gorevini isaret ediyor
  -- Bileşik FK bunu YAPISAL olarak da engeller; hangisi once konusursa
  -- konussun ikisi de gecerli savunmadir, ama ayirt edilerek raporlanir.
  declare v_h uuid; begin
    insert into public.pms_odalar (otel_id,oda_tipi_id,oda_no)
    values ('810',v_tip,'H8-'||v_ek) returning id into v_h;
    update public.pms_odalar set temizlik_gorevi_id=v_g where id=v_h;  -- v_g BASKA odada
    set constraints all immediate;
    raise notice 'H8  FAIL  yabanci gorev gostergesi kabul edildi'; v_fail:=v_fail+1;
    set constraints all deferred;
  exception when others then
    set constraints all deferred;
    if sqlerrm like 'H8:%' then
      raise notice 'H8  OK    ertelenmis kontrol: %', left(sqlerrm,50); v_ok:=v_ok+1;
    elsif sqlstate = '23503' then
      raise notice 'H8  OK    bilesik FK yapisal olarak reddetti (23503)'; v_ok:=v_ok+1;
    else raise notice 'H8  FAIL  beklenmeyen: % %', sqlstate, left(sqlerrm,50); v_fail:=v_fail+1; end if;
  end;

  -- H9: bu blokta DEGIL. H9 davranissal olarak YUKARIDA H9a/H9b ile
  -- kanitlanir. Guvenilir yazarla kurulan "guncel olmayan calisan gorev"
  -- sondasi H4 tarafindan ON-KESILIYORDU, yani H9 iddiasini hic sinamiyordu;
  -- yanlis sebeple yesil olan o sonda KALDIRILDI.

  -- H10: ARIZALI odada CALISAN is commit edilemez
  declare v_h uuid; v_hg uuid; begin
    insert into public.pms_odalar (otel_id,oda_tipi_id,oda_no)
    values ('810',v_tip,'HA-'||v_ek) returning id into v_h;
    insert into public.pms_housekeeping_gorevleri
      (otel_id, oda_id, gorev_tipi, durum, olusturma_kaynagi, olusturan,
       atanan_kullanici_id, baslama_zamani,
       istek_anahtari, istek_ozeti, son_islem_anahtari, son_islem_ozeti)
    values ('810', v_h, 'ekstra_temizlik', 'temizleniyor', 'kullanici', v_k,
            v_k, now(),
            gen_random_uuid(), encode(sha256('h10'::bytea),'hex'),
            gen_random_uuid(), encode(sha256('h10'::bytea),'hex'))
    returning id into v_hg;
    update public.pms_odalar
       set temizlik_gorevi_id=v_hg, temizlik_durumu='temizleniyor',
           kullanim_durumu='ariza'
     where id=v_h;
    set constraints all immediate;
    raise notice 'H10 FAIL  arizali odada calisan is commit edildi'; v_fail:=v_fail+1;
    set constraints all deferred;
  exception when others then
    set constraints all deferred;
    if sqlerrm like 'H10:%' then
      raise notice 'H10 OK    %', left(sqlerrm,60); v_ok:=v_ok+1;
    else raise notice 'H10 FAIL  beklenen H10, gelen: %', left(sqlerrm,60); v_fail:=v_fail+1; end if;
  end;

  set constraints all immediate;
  set constraints all deferred;
  alter table public.pms_housekeeping_gorevleri enable trigger pms_housekeeping_gorev_koruma;
  alter table public.pms_odalar enable trigger pms_housekeeping_oda_koruma;
  alter table public.pms_odalar enable trigger pms_housekeeping_oda_yasam_dongusu;

  -- Izolasyon SIZMADI mi? Bekci geri acildiysa dogrudan yazma REDDEDILMELI.
  begin
    update public.pms_housekeeping_gorevleri set durum='tamamlandi' where id=v_g;
    raise notice 'HZ  FAIL  bekci geri acilmadi (izolasyon sizdi)'; v_fail:=v_fail+1;
  exception when others then
    raise notice 'HZ  OK    bekci geri acildi (izolasyon sizmadi)'; v_ok:=v_ok+1;
  end;

  raise notice '--------------------------------------------------';
  raise notice 'SON KABUL SONUC: % OK / % FAIL', v_ok, v_fail;
  if v_fail > 0 then
    raise exception 'SON KABUL BASARISIZ: % test', v_fail;
  end if;
end;
$$;

rollback;
