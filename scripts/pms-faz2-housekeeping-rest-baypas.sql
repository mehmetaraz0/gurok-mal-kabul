-- ============================================================================
-- PMS FAZ 2 — REST / PostgREST BAYPAS TESTLERİ (KATMAN ATFIYLA)
-- ----------------------------------------------------------------------------
-- YALNIZ ATILABILIR YEREL/STAGING VERİTABANINDA ÇALIŞTIRILIR.
--   psql -X -U postgres -d hkdb -f scripts/pms-faz2-housekeeping-rest-baypas.sql
--
-- ---------------------------------------------------------------------------
-- NEDEN KATMAN ATFI
-- ---------------------------------------------------------------------------
-- "Reddedildi" yeterli DEĞİLDİR. RLS bir yazmayı SIFIR SATIR ile susturur ve
-- test yeşil görünür — oysa hedeflenen bekçi hiç ateşlenmemiştir. Yanlış
-- sebeple yeşil bir test hiçbir şey kanıtlamaz.
--
-- Bu yüzden her deneme için SQLSTATE + mesaj + satır sayısı okunur ve reddin
-- GERÇEKTEN hangi katmandan geldiği raporlanır:
--
--   ACL      : 42501 + "permission denied" (ayrıcalık yok)
--   RLS      : hata yok, 0 satır (politika satırı gizledi)
--   BEKCI    : 42501 + bizim Türkçe mesajımız (trigger)
--   KISIT    : 23xxx (check/unique/fk)
--   RPC      : P0002 / 42501 + RPC gövdesinden gelen mesaj
--
-- Beklenen katman ile gözlenen katman EŞLEŞMEZSE test BAŞARISIZDIR.
-- ============================================================================

\set ON_ERROR_STOP on

begin;

update public.moduller set aktif = true where kod = 'pms_housekeeping';

do $$
declare
  v_ok int := 0; v_fail int := 0;
  v_rol uuid; v_auth uuid := gen_random_uuid(); v_kul uuid;
  v_rol811 uuid; v_auth811 uuid := gen_random_uuid(); v_kul811 uuid;
  v_pauth uuid := gen_random_uuid(); v_pkul uuid;
  v_tip uuid; v_tip811 uuid; v_oda uuid; v_oda811 uuid;
  v_g uuid; v_g811 uuid; v_r jsonb; v_n int;
  v_state text; v_msg text; v_katman text; v_h text := encode(sha256('rest'::bytea),'hex');

begin
  -- ================= FİKSTÜR =================
  insert into public.moduller (kod, ad, kategori, sira, aktif) values
    ('pms_oda','On Buro - Odalar','onburo',44,true)
  on conflict (kod) do update set aktif = true;

  insert into public.roller (ad, seviye) values ('RB 810','otel') returning id into v_rol;
  insert into public.roller (ad, seviye) values ('RB 811','otel') returning id into v_rol811;
  insert into public.yetki_matrisi (rol_id, modul_id, yetki)
  select v_rol, id, 'tam' from public.moduller where kod in ('pms_housekeeping','pms_oda');
  insert into public.yetki_matrisi (rol_id, modul_id, yetki)
  select v_rol811, id, 'tam' from public.moduller where kod in ('pms_housekeeping','pms_oda');

  insert into auth.users (id) values (v_auth), (v_auth811), (v_pauth);
  insert into public.kullanicilar (ad, rol, rol_id, otel_id, aktif, auth_user_id)
  values ('RB 810','yonetici', v_rol, '810', true, v_auth) returning id into v_kul;
  insert into public.kullanicilar (ad, rol, rol_id, otel_id, aktif, auth_user_id)
  values ('RB 811','yonetici', v_rol811, '811', true, v_auth811) returning id into v_kul811;
  insert into public.kullanicilar (ad, rol, rol_id, otel_id, aktif, auth_user_id)
  values ('RB Pasif','depo', v_rol, '810', false, v_pauth) returning id into v_pkul;

  insert into public.pms_oda_tipleri (otel_id,kod,ad,azami_kisi,azami_yetiskin,azami_cocuk)
  values ('810','rb','RB',2,2,1) returning id into v_tip;
  insert into public.pms_oda_tipleri (otel_id,kod,ad,azami_kisi,azami_yetiskin,azami_cocuk)
  values ('811','rb','RB',2,2,1) returning id into v_tip811;
  insert into public.pms_odalar (otel_id,oda_tipi_id,oda_no) values ('810',v_tip,'RB01') returning id into v_oda;
  insert into public.pms_odalar (otel_id,oda_tipi_id,oda_no) values ('811',v_tip811,'RB01') returning id into v_oda811;

  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config('request.jwt.claim.sub', v_auth::text, true);
  v_r := public.pms_housekeeping_gorev_olustur(v_oda,'ekstra_temizlik','bos',gen_random_uuid());
  v_g := (v_r->>'gorev_id')::uuid;

  perform set_config('request.jwt.claim.sub', v_auth811::text, true);
  v_r := public.pms_housekeeping_gorev_olustur(v_oda811,'ekstra_temizlik','bos',gen_random_uuid());
  v_g811 := (v_r->>'gorev_id')::uuid;
  perform set_config('request.jwt.claim.sub', v_auth::text, true);

  -- ==================================================================
  -- ANON: hicbir sey
  -- ==================================================================
  perform set_config('request.jwt.claim.role','anon',true);
  perform set_config('request.jwt.claim.sub','',true);

  begin
    execute 'set local role anon';
    execute 'select count(*) from public.pms_housekeeping_gorevleri' into v_n;
    execute 'reset role';
    raise notice 'X1  FAIL  anon gorev okudu (% satir)', v_n; v_fail:=v_fail+1;
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    execute 'reset role';
    v_katman := case when v_state='42501' and v_msg like '%permission denied%' then 'ACL' else 'DIGER:'||v_state end;
    if v_katman='ACL' then raise notice 'X1  OK    anon gorev okuyamaz  [katman: ACL]'; v_ok:=v_ok+1;
    else raise notice 'X1  FAIL  beklenen ACL, gozlenen %', v_katman; v_fail:=v_fail+1; end if;
  end;

  begin
    execute 'set local role anon';
    execute format('select public.pms_housekeeping_sahiplen(%L::uuid, 1, gen_random_uuid())', v_g);
    execute 'reset role';
    raise notice 'X2  FAIL  anon RPC calistirdi'; v_fail:=v_fail+1;
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    execute 'reset role';
    v_katman := case when v_state='42501' and v_msg like '%permission denied%' then 'ACL' else 'DIGER:'||v_state end;
    if v_katman='ACL' then raise notice 'X2  OK    anon RPC calistiramaz  [katman: ACL]'; v_ok:=v_ok+1;
    else raise notice 'X2  FAIL  beklenen ACL, gozlenen % (%)', v_katman, left(v_msg,40); v_fail:=v_fail+1; end if;
  end;

  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config('request.jwt.claim.sub', v_auth::text, true);

  -- ==================================================================
  -- AUTHENTICATED: gorev tablosuna dogrudan DML — hepsi ACL katmani
  -- ==================================================================
  begin
    execute 'set local role authenticated';
    execute format('insert into public.pms_housekeeping_gorevleri
      (otel_id,oda_id,gorev_tipi,olusturma_kaynagi,istek_anahtari,istek_ozeti,son_islem_anahtari,son_islem_ozeti)
      values (%L,%L::uuid,%L,%L,gen_random_uuid(),%L,gen_random_uuid(),%L)',
      '810', v_oda, 'ekstra_temizlik','sistem', v_h, v_h);
    execute 'reset role';
    raise notice 'X3  FAIL  dogrudan INSERT gecti'; v_fail:=v_fail+1;
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    execute 'reset role';
    v_katman := case when v_state='42501' and v_msg like '%permission denied%' then 'ACL' else 'DIGER:'||v_state end;
    if v_katman='ACL' then raise notice 'X3  OK    dogrudan INSERT yok  [katman: ACL]'; v_ok:=v_ok+1;
    else raise notice 'X3  FAIL  beklenen ACL, gozlenen %', v_katman; v_fail:=v_fail+1; end if;
  end;

  begin
    execute 'set local role authenticated';
    execute format('update public.pms_housekeeping_gorevleri set durum=%L where id=%L::uuid','tamamlandi',v_g);
    execute 'reset role';
    raise notice 'X4  FAIL  dogrudan UPDATE gecti'; v_fail:=v_fail+1;
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    execute 'reset role';
    v_katman := case when v_state='42501' and v_msg like '%permission denied%' then 'ACL' else 'DIGER:'||v_state end;
    if v_katman='ACL' then raise notice 'X4  OK    durum sahteciligi yok  [katman: ACL]'; v_ok:=v_ok+1;
    else raise notice 'X4  FAIL  beklenen ACL, gozlenen %', v_katman; v_fail:=v_fail+1; end if;
  end;

  begin
    execute 'set local role authenticated';
    execute format('delete from public.pms_housekeeping_gorevleri where id=%L::uuid', v_g);
    execute 'reset role';
    raise notice 'X5  FAIL  dogrudan DELETE gecti'; v_fail:=v_fail+1;
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    execute 'reset role';
    v_katman := case when v_state='42501' and v_msg like '%permission denied%' then 'ACL' else 'DIGER:'||v_state end;
    if v_katman='ACL' then raise notice 'X5  OK    dogrudan DELETE yok  [katman: ACL]'; v_ok:=v_ok+1;
    else raise notice 'X5  FAIL  beklenen ACL, gozlenen %', v_katman; v_fail:=v_fail+1; end if;
  end;

  -- ==================================================================
  -- AUTHENTICATED: oda sahteciligi — BEKCI katmani (RLS DEGIL)
  -- ==================================================================
  begin
    execute 'set local role authenticated';
    execute format('update public.pms_odalar set temizlik_durumu=%L where id=%L::uuid','temiz',v_oda);
    get diagnostics v_n = row_count;
    execute 'reset role';
    raise notice 'X6  FAIL  temizlik sahteciligi gecti (% satir)', v_n; v_fail:=v_fail+1;
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    execute 'reset role';
    v_katman := case
      when v_state='42501' and v_msg like '%permission denied%' then 'ACL'
      when v_state='42501' then 'BEKCI' else 'DIGER:'||v_state end;
    if v_katman='BEKCI' then
      raise notice 'X6  OK    temizlik sahteciligi yok  [katman: BEKCI] %', left(v_msg,45); v_ok:=v_ok+1;
    else raise notice 'X6  FAIL  beklenen BEKCI, gozlenen % (%)', v_katman, left(v_msg,40); v_fail:=v_fail+1; end if;
  end;

  begin
    execute 'set local role authenticated';
    execute format('update public.pms_odalar set temizlik_gorevi_id=null where id=%L::uuid', v_oda);
    get diagnostics v_n = row_count;
    execute 'reset role';
    raise notice 'X7  FAIL  gosterge sahteciligi gecti (% satir)', v_n; v_fail:=v_fail+1;
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    execute 'reset role';
    v_katman := case
      when v_state='42501' and v_msg like '%permission denied%' then 'ACL'
      when v_state='42501' then 'BEKCI' else 'DIGER:'||v_state end;
    if v_katman='BEKCI' then
      raise notice 'X7  OK    gosterge sahteciligi yok  [katman: BEKCI]'; v_ok:=v_ok+1;
    else raise notice 'X7  FAIL  beklenen BEKCI, gozlenen % (%)', v_katman, left(v_msg,40); v_fail:=v_fail+1; end if;
  end;

  -- ==================================================================
  -- ÇAPRAZ OTEL: RPC yetkilendirmesi (RLS gizlemesi DEGIL)
  -- ==================================================================
  begin
    perform public.pms_housekeeping_sahiplen(v_g811, 1, gen_random_uuid());
    raise notice 'X8  FAIL  capraz otel gorev komutu gecti'; v_fail:=v_fail+1;
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    v_katman := case when v_state='P0002' then 'RPC' when v_state='42501' then 'RPC' else 'DIGER:'||v_state end;
    if v_katman='RPC' then
      raise notice 'X8  OK    capraz otel komutu reddedildi  [katman: RPC] %', left(v_msg,40); v_ok:=v_ok+1;
    else raise notice 'X8  FAIL  beklenen RPC, gozlenen %', v_katman; v_fail:=v_fail+1; end if;
  end;

  -- X9: capraz otel gorev RLS ile de GORUNMEZ (SELECT 0 satir - dogru katman)
  begin
    execute 'set local role authenticated';
    execute format('select count(*) from public.pms_housekeeping_gorevleri where id=%L::uuid', v_g811) into v_n;
    execute 'reset role';
    if v_n = 0 then
      raise notice 'X9  OK    capraz otel gorev gorunmuyor  [katman: RLS, 0 satir]'; v_ok:=v_ok+1;
    else raise notice 'X9  FAIL  capraz otel gorev okundu (% satir)', v_n; v_fail:=v_fail+1; end if;
  exception when others then
    execute 'reset role';
    get stacked diagnostics v_state = returned_sqlstate;
    raise notice 'X9  FAIL  beklenmeyen hata %', v_state; v_fail:=v_fail+1;
  end;

  -- ==================================================================
  -- KİMLİK: pasif ERP kullanicisi / ERP karsiligi olmayan Auth
  -- ==================================================================
  perform set_config('request.jwt.claim.sub', v_pauth::text, true);
  begin
    perform public.pms_housekeeping_listele('810');
    raise notice 'X10 FAIL  pasif kullanici gecti'; v_fail:=v_fail+1;
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate;
    if v_state='42501' then raise notice 'X10 OK    pasif ERP kullanicisi reddedildi  [katman: RPC]'; v_ok:=v_ok+1;
    else raise notice 'X10 FAIL  gozlenen %', v_state; v_fail:=v_fail+1; end if;
  end;

  perform set_config('request.jwt.claim.sub', gen_random_uuid()::text, true);
  begin
    perform public.pms_housekeeping_listele('810');
    raise notice 'X11 FAIL  ERP karsiligi olmayan kimlik gecti'; v_fail:=v_fail+1;
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate;
    if v_state='42501' then raise notice 'X11 OK    ERP karsiligi olmayan kimlik reddedildi  [katman: RPC]'; v_ok:=v_ok+1;
    else raise notice 'X11 FAIL  gozlenen %', v_state; v_fail:=v_fail+1; end if;
  end;

  -- ==================================================================
  -- service_role: gorev DML'i YOK (Adim 1'de kat hizmeti API'si yok)
  -- ==================================================================
  perform set_config('request.jwt.claim.role','service_role',true);
  perform set_config('request.jwt.claim.sub','',true);
  begin
    execute 'set local role service_role';
    execute format('update public.pms_housekeeping_gorevleri set durum=%L where id=%L::uuid','tamamlandi',v_g);
    execute 'reset role';
    raise notice 'X12 FAIL  service_role gorev yazdi'; v_fail:=v_fail+1;
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    execute 'reset role';
    v_katman := case when v_state='42501' and v_msg like '%permission denied%' then 'ACL' else 'DIGER:'||v_state end;
    if v_katman='ACL' then raise notice 'X12 OK    service_role gorev yazamaz  [katman: ACL]'; v_ok:=v_ok+1;
    else raise notice 'X12 FAIL  beklenen ACL, gozlenen %', v_katman; v_fail:=v_fail+1; end if;
  end;

  -- ==================================================================
  -- ÖZEL YARDIMCILAR REST'ten cagrilamaz
  -- ==================================================================
  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config('request.jwt.claim.sub', v_auth::text, true);
  begin
    execute 'set local role authenticated';
    execute format('select phase0_private.hk_iptal_sistem(%L::uuid, %L)', v_g, 'oda_bloke');
    execute 'reset role';
    raise notice 'X13 FAIL  ozel yardimci cagrilabildi'; v_fail:=v_fail+1;
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    execute 'reset role';
    v_katman := case when v_state in ('42501','42883') then 'ACL/SEMA' else 'DIGER:'||v_state end;
    if v_katman='ACL/SEMA' then
      raise notice 'X13 OK    ozel yardimci REST ten kapali  [katman: %]', v_katman; v_ok:=v_ok+1;
    else raise notice 'X13 FAIL  gozlenen %', v_katman; v_fail:=v_fail+1; end if;
  end;

  raise notice '--------------------------------------------------';
  raise notice 'REST BAYPAS SONUC: % OK / % FAIL', v_ok, v_fail;
  if v_fail > 0 then
    raise exception 'REST BAYPAS TESTLERI BASARISIZ: % test', v_fail;
  end if;
end;
$$;

rollback;
