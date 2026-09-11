-- ============================================================================
-- PMS FAZ 2 / ADIM 2 — ARAYÜZ DESTEK SÖZLEŞMESİ TESTLERİ
-- ----------------------------------------------------------------------------
-- YALNIZ ATILABILIR YEREL/STAGING VERİTABANINDA ÇALIŞTIRILIR.
--   psql -X -U postgres -d <vt> -f scripts/pms-faz2-housekeeping-ui-destek-testleri.sql
--
-- İki ÖLÇÜLMÜŞ boşluğun kapandığını ve kapatırken yeni bir açık
-- yaratılmadığını kanıtlar:
--   U1-U3  "İşlerim" sunucu tarafında süzülüyor (100 satır penceresi artık
--          çalışanın kendi işini gizleyemiyor)
--   U4-U6  Oda seçici: kat hizmetleri yetkisi yeter, oda modülü yetkisi
--          GEREKMEZ; ama yetki eşiği görev açmanın eşiğinden DÜŞÜK DEĞİL
--   U7-U9  Otel izolasyonu, sınır (bounded) davranışı, kuyruk denetimi
--   U10    anon hiçbirini çağıramaz
--
-- Tüm dosya tek transaction'dadır ve ROLLBACK edilir.
-- ============================================================================

\set ON_ERROR_STOP on

begin;

do $$
declare
  v_ok int := 0; v_fail int := 0;
  v_ek text := substr(md5(random()::text || clock_timestamp()::text), 1, 6);
  v_rol_tam uuid; v_rol_kayit uuid; v_rol_oda uuid;
  v_a_sup uuid := gen_random_uuid(); v_a_isci uuid := gen_random_uuid();
  v_a_811 uuid := gen_random_uuid();
  v_sup uuid; v_isci uuid; v_s811 uuid;
  v_tip uuid; v_tip811 uuid; v_oda uuid; v_odaA uuid; v_oda811 uuid;
  v_g uuid; v_hedef uuid;
  i int; v_n int; v_n2 int; v_txt text;
begin
  update public.moduller set aktif = true where kod = 'pms_housekeeping';
  insert into public.moduller (kod, ad, kategori, sira, aktif) values
    ('pms_oda','On Buro - Odalar','onburo',44,true),
    ('pms_oda_tipi','On Buro - Oda Tipleri','onburo',43,true)
  on conflict (kod) do update set aktif = true;

  -- Rol A: YALNIZ kat hizmetleri `tam`  (oda modülü yetkisi YOK)
  insert into public.roller (ad, seviye) values ('UI Tam '||v_ek,'otel') returning id into v_rol_tam;
  insert into public.yetki_matrisi (rol_id, modul_id, yetki)
  select v_rol_tam, id, 'tam' from public.moduller where kod = 'pms_housekeeping';

  -- Rol B: kat hizmetleri `kayit` (çalışan)
  insert into public.roller (ad, seviye) values ('UI Kayit '||v_ek,'otel') returning id into v_rol_kayit;
  insert into public.yetki_matrisi (rol_id, modul_id, yetki)
  select v_rol_kayit, id, 'kayit' from public.moduller where kod = 'pms_housekeeping';

  insert into auth.users (id) values (v_a_sup), (v_a_isci), (v_a_811);
  insert into public.kullanicilar (ad, rol, rol_id, otel_id, aktif, auth_user_id)
  values ('UI Sup','yonetici', v_rol_tam,'810', true, v_a_sup) returning id into v_sup;
  insert into public.kullanicilar (ad, rol, rol_id, otel_id, aktif, auth_user_id)
  values ('UI Isci','depo', v_rol_kayit,'810', true, v_a_isci) returning id into v_isci;
  insert into public.kullanicilar (ad, rol, rol_id, otel_id, aktif, auth_user_id)
  values ('UI S811','yonetici', v_rol_tam,'811', true, v_a_811) returning id into v_s811;

  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config('request.jwt.claim.sub', v_a_sup::text, true);

  insert into public.pms_oda_tipleri (otel_id,kod,ad,azami_kisi,azami_yetiskin,azami_cocuk)
  values ('810','ui'||v_ek,'UI',2,2,1) returning id into v_tip;

  -- =====================================================================
  -- 110 oda + bekleyen görev. Hedef görev DÜŞÜK öncelikli (sıralamada
  -- en sona düşer) ve çalışana atanır: 100'lük pencerenin DIŞINDA kalır.
  -- =====================================================================
  for i in 1..110 loop
    insert into public.pms_odalar (otel_id,oda_tipi_id,oda_no)
    values ('810',v_tip,'UI'||lpad(i::text,3,'0')||'-'||v_ek) returning id into v_oda;
    v_g := (public.pms_housekeeping_gorev_olustur(v_oda,'ekstra_temizlik','bos',
              gen_random_uuid(), jsonb_build_object('oncelik',1))->>'gorev_id')::uuid;
    if i = 110 then v_hedef := v_g; end if;
  end loop;

  perform public.pms_housekeeping_duzenle(v_hedef, jsonb_build_object('oncelik',3),
    (select surum from public.pms_housekeeping_gorevleri where id=v_hedef), gen_random_uuid());
  perform public.pms_housekeeping_ata(v_hedef, v_isci,
    (select surum from public.pms_housekeeping_gorevleri where id=v_hedef), gen_random_uuid());

  -- ---- U1: eski yol GERÇEKTEN kaybediyor (regresyon bekçisi) ----------
  perform set_config('request.jwt.claim.sub', v_a_isci::text, true);
  select count(*) into v_n from public.pms_housekeeping_listele('810','bitmemis',100) t
   where t.atanan_kullanici_id = v_isci;
  if v_n = 0 then
    raise notice 'U1  OK    istemci suzgeci 100 penceresinde gorevi KACIRIYOR (boslugun kaniti)';
    v_ok:=v_ok+1;
  else
    raise notice 'U1  FAIL  bosluk yeniden uretilemedi (% satir) — test artik anlamli degil', v_n;
    v_fail:=v_fail+1;
  end if;

  -- ---- U2: `benim` kuyrugu gorevi BULUYOR ----------------------------
  select count(*) into v_n from public.pms_housekeeping_listele('810','benim',100);
  select count(*) into v_n2 from public.pms_housekeeping_listele('810','benim',100) t
   where t.gorev_id = v_hedef;
  if v_n2 = 1 then
    raise notice 'U2  OK    `benim` kuyrugu gorevi buldu (toplam % satir)', v_n;
    v_ok:=v_ok+1;
  else
    raise notice 'U2  FAIL  `benim` kuyrugunda gorev yok (% satir)', v_n; v_fail:=v_fail+1;
  end if;

  -- ---- U3: `benim` YALNIZ cagirana ait olani doner --------------------
  select count(*) into v_n from public.pms_housekeeping_listele('810','benim',100) t
   where t.atanan_kullanici_id is distinct from v_isci;
  if v_n = 0 then
    raise notice 'U3  OK    `benim` baskasinin gorevini sizdirmiyor'; v_ok:=v_ok+1;
  else
    raise notice 'U3  FAIL  % yabanci satir', v_n; v_fail:=v_fail+1;
  end if;

  -- ---- U3b: kimlik ISTEMCIDEN alinmiyor -------------------------------
  -- Supervisor ayni kuyrugu cagirinca KENDI (bos) listesini gorur;
  -- iscinin gorevini goremez. Yani sonuc cagirandan turetiliyor.
  perform set_config('request.jwt.claim.sub', v_a_sup::text, true);
  select count(*) into v_n from public.pms_housekeeping_listele('810','benim',100) t
   where t.gorev_id = v_hedef;
  if v_n = 0 then
    raise notice 'U3b OK    kuyruk cagiranin kimliginden turetiliyor'; v_ok:=v_ok+1;
  else
    raise notice 'U3b FAIL  baska kullanicinin gorevi dondu'; v_fail:=v_fail+1;
  end if;

  -- =====================================================================
  -- ODA SEÇİCİ
  -- =====================================================================
  insert into public.pms_odalar (otel_id,oda_tipi_id,oda_no)
  values ('810',v_tip,'UIA-'||v_ek) returning id into v_odaA;   -- GÖREVİ YOK

  -- ---- U4: oda modulu yetkisi OLMADAN oda okunamiyordu (bosluk kaniti)
  begin
    execute 'set local role authenticated';
    select count(*) into v_n from public.pms_odalar where id = v_odaA;
    execute 'reset role';
    if v_n = 0 then
      raise notice 'U4  OK    dogrudan pms_odalar okumasi 0 satir (bosluk kaniti)'; v_ok:=v_ok+1;
    else
      raise notice 'U4  FAIL  oda modulu yetkisi olmadan % satir okundu', v_n; v_fail:=v_fail+1;
    end if;
  exception when others then
    execute 'reset role';
    raise notice 'U4  OK    dogrudan okuma reddedildi (%)', sqlstate; v_ok:=v_ok+1;
  end;

  -- ---- U5: yeni RPC gorevi olmayan odayi DA doner ---------------------
  select count(*) into v_n from public.pms_housekeeping_odalar('810', 500) t
   where t.oda_id = v_odaA;
  if v_n = 1 then
    raise notice 'U5  OK    oda secici gorevi olmayan odayi donduruyor'; v_ok:=v_ok+1;
  else
    raise notice 'U5  FAIL  oda secici odayi dondurmedi'; v_fail:=v_fail+1;
  end if;

  -- ---- U6: seçici MİSAFİR/REZERVASYON verisi dondurmez ----------------
  select count(*) into v_n
    from information_schema.columns c
   where c.table_schema = 'public'
     and c.table_name is not null
     and false;   -- (fonksiyon donus tipi asagida dogrudan kontrol edilir)
  select count(*) into v_n
    from unnest(string_to_array(
      pg_get_function_result(to_regprocedure('public.pms_housekeeping_odalar(text,integer)')), ',')) x
   where x ~* 'misafir|rezervasyon|telefon|folio|folyo|fiyat|tutar|ad |soyad';
  if v_n = 0 then
    raise notice 'U6  OK    oda secici sozlesmesinde misafir/rezervasyon alani yok'; v_ok:=v_ok+1;
  else
    raise notice 'U6  FAIL  sozlesmede % supheli alan', v_n; v_fail:=v_fail+1;
  end if;

  -- ---- U7: `kayit` yetkisi seciciyi ACAMAZ (esik gorev acmayla ayni) --
  perform set_config('request.jwt.claim.sub', v_a_isci::text, true);
  begin
    perform public.pms_housekeeping_odalar('810', 10);
    raise notice 'U7  FAIL  kayit yetkisi oda secicisini acti'; v_fail:=v_fail+1;
  exception when others then
    if sqlstate = '42501' then
      raise notice 'U7  OK    kayit yetkisi seciciyi acamiyor (esik = tam)'; v_ok:=v_ok+1;
    else
      raise notice 'U7  FAIL  beklenen 42501, gelen %', sqlstate; v_fail:=v_fail+1;
    end if;
  end;

  -- ---- U8: OTEL IZOLASYONU (iki yonlu) -------------------------------
  insert into public.pms_oda_tipleri (otel_id,kod,ad,azami_kisi,azami_yetiskin,azami_cocuk)
  values ('811','ui811'||v_ek,'UI811',2,2,1) returning id into v_tip811;
  insert into public.pms_odalar (otel_id,oda_tipi_id,oda_no)
  values ('811',v_tip811,'U811-'||v_ek) returning id into v_oda811;

  perform set_config('request.jwt.claim.sub', v_a_sup::text, true);
  begin
    perform public.pms_housekeeping_odalar('811', 10);
    raise notice 'U8a FAIL  810 kullanicisi 811 odalarini okudu'; v_fail:=v_fail+1;
  exception when others then
    raise notice 'U8a OK    capraz otel oda secici reddedildi (%)', sqlstate; v_ok:=v_ok+1;
  end;
  select count(*) into v_n from public.pms_housekeeping_odalar('810', 500) t
   where t.oda_id = v_oda811;
  if v_n = 0 then
    raise notice 'U8b OK    kendi otel kapsaminda yabanci oda yok'; v_ok:=v_ok+1;
  else
    raise notice 'U8b FAIL  yabanci oda sizdi'; v_fail:=v_fail+1;
  end if;

  -- ---- U9: SINIR (bounded) davranisi ---------------------------------
  select count(*) into v_n from public.pms_housekeeping_odalar('810', 5);
  select count(*) into v_n2 from public.pms_housekeeping_odalar('810', 99999);
  if v_n = 5 and v_n2 <= 500 then
    raise notice 'U9  OK    sinir uygulaniyor (istek 5 -> %, istek 99999 -> % <= 500)', v_n, v_n2;
    v_ok:=v_ok+1;
  else
    raise notice 'U9  FAIL  sinir hatali (% / %)', v_n, v_n2; v_fail:=v_fail+1;
  end if;

  -- ---- U9b: bilinmeyen kuyruk REDDEDILIR -----------------------------
  begin
    perform public.pms_housekeeping_listele('810','uydurma',10);
    raise notice 'U9b FAIL  bilinmeyen kuyruk kabul edildi'; v_fail:=v_fail+1;
  exception when others then
    if sqlstate = '22023' then
      raise notice 'U9b OK    bilinmeyen kuyruk reddedildi'; v_ok:=v_ok+1;
    else
      raise notice 'U9b FAIL  beklenen 22023, gelen %', sqlstate; v_fail:=v_fail+1;
    end if;
  end;

  -- ---- U10: anon HICBIRINI cagiramaz ---------------------------------
  select count(*) into v_n from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public'
     and p.proname in ('pms_housekeeping_listele','pms_housekeeping_odalar')
     and has_function_privilege('anon', p.oid, 'EXECUTE');
  if v_n = 0 then
    raise notice 'U10 OK    anon EXECUTE yok'; v_ok:=v_ok+1;
  else
    raise notice 'U10 FAIL  anon % fonksiyonu cagirabiliyor', v_n; v_fail:=v_fail+1;
  end if;

  -- ---- U11: service_role da cagiramaz (varsayilan ACL mirasi) ---------
  -- Ilk yazimda yeni fonksiyon veritabaninin varsayilan ACL'sinden
  -- service_role EXECUTE hakkini miras aliyordu; statik denetleyici bunu
  -- yakalamadi, REST baypas X16 yakaladi. Bu satir o regresyonu kilitler.
  select count(*) into v_n from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public'
     and p.proname in ('pms_housekeeping_listele','pms_housekeeping_odalar')
     and has_function_privilege('service_role', p.oid, 'EXECUTE');
  if v_n = 0 then
    raise notice 'U11 OK    service_role EXECUTE yok (varsayilan ACL mirasi notrlendi)'; v_ok:=v_ok+1;
  else
    raise notice 'U11 FAIL  service_role % fonksiyonu cagirabiliyor', v_n; v_fail:=v_fail+1;
  end if;

  raise notice '--------------------------------------------------';
  raise notice 'UI DESTEK SONUC: % OK / % FAIL', v_ok, v_fail;
  if v_fail > 0 then
    raise exception 'UI DESTEK TESTLERI BASARISIZ: % test', v_fail;
  end if;
end;
$$;

rollback;
