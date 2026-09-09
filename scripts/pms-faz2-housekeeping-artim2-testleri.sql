-- ============================================================================
-- PMS FAZ 2 / ARTIM 2 — DURUM MAKİNESİ, KOMUT YÜZEYİ VE ODA BÜTÜNLÜĞÜ TESTLERİ
-- ----------------------------------------------------------------------------
-- YALNIZ ATILABILIR YEREL/STAGING VERİTABANINDA ÇALIŞTIRILIR.
--
--   psql -X -U postgres -d hkdb -f scripts/pms-faz2-housekeeping-artim2-testleri.sql
--
-- Gerçek `authenticated` oturumu, shim'in okuduğu `request.jwt.claim.*`
-- GUC'lariyla taklit edilir; böylece `auth.uid()` ve tüm `auth_*`
-- yardımcıları üretimdeki gibi çalışır.
--
-- ---------------------------------------------------------------------------
-- İKİ ÖLÇÜM TUZAĞI — bu dosya ikisinden de kaçınır
-- ---------------------------------------------------------------------------
-- 1) RLS ENGELİ HATA DEĞİL, SIFIR SATIRDIR. Bir yazma "reddedildi" görünürken
--    aslında politika satırı gizlemiş olabilir ve BEKÇİ HİÇ ATEŞLENMEZ.
--    Bu yüzden bekçi testlerinde denek kullanıcıya GERÇEK `pms_oda` yetkisi
--    verilir; RLS geçer, tek durdurucu bekçi kalır. Ayrıca satır sayısı
--    ölçülür: 0 satır "belirsiz" sayılır ve BAŞARISIZ raporlanır.
--
-- 2) ERTELENMİŞ KISIT ALT-TRANSACTION'DA ATEŞLENMEZ. PL/pgSQL'de her
--    `begin ... exception` bir alt-transaction açar; dıştaki blokta kuyruğa
--    girmiş olaylar içerideki `set constraints ... immediate` ile ATEŞLENMEZ.
--    İhlal ve `set constraints` AYNI blokta olmalıdır.
--
-- Tüm test tek transaction'dadır ve sonunda ROLLBACK edilir.
-- ============================================================================

\set ON_ERROR_STOP on

begin;

-- Modül testler için açılır; ROLLBACK ile geri alınır.
update public.moduller set aktif = true where kod = 'pms_housekeeping';

do $$
declare
  v_ok int := 0; v_fail int := 0;
  v_rol_tam uuid; v_rol_kayit uuid; v_modul uuid; v_modul_oda uuid;
  v_sup uuid; v_sup_auth uuid := gen_random_uuid();
  v_w1 uuid;  v_w1_auth  uuid := gen_random_uuid();
  v_w2 uuid;  v_w2_auth  uuid := gen_random_uuid();
  v_yab uuid; v_yab_auth uuid := gen_random_uuid();
  v_pasif uuid; v_pasif_auth uuid := gen_random_uuid();
  v_tipi810 uuid; v_tipi811 uuid;
  v_oda uuid; v_oda811 uuid; v_odaD uuid; v_odaE uuid; v_odaF uuid; v_odaG uuid;
  v_g uuid; v_g2 uuid; v_gE uuid; v_s bigint; v_r jsonb; v_r2 jsonb;
  v_oda_durum text; v_key uuid; v_n int; v_sira text[];
begin
  -- ==================================================================
  -- FİKSTÜR
  -- ==================================================================
  select id into v_modul from public.moduller where kod = 'pms_housekeeping';

  -- Sema-only dokumde `moduller` BOSTUR; migration yalniz kendi satirini
  -- ekler. Oda modulu fikstur olarak yaratilir: D bolumunun RLS'i gecmesi
  -- icin gereklidir (bkz. yukaridaki 1. olcum tuzagi).
  insert into public.moduller (kod, ad, kategori, sira, aktif)
  values ('pms_oda', 'On Buro - Odalar', 'onburo', 44, true)
  on conflict (kod) do update set aktif = true
  returning id into v_modul_oda;

  insert into public.roller (ad, seviye) values ('T2 Supervisor','otel') returning id into v_rol_tam;
  insert into public.roller (ad, seviye) values ('T2 Worker','otel')     returning id into v_rol_kayit;

  -- Supervisor'a kat hizmeti `tam` VE oda `tam`: oda yetkisi RLS'i gecmek
  -- icindir, boylece bekci testleri gercekten bekciyi olcer.
  insert into public.yetki_matrisi (rol_id, modul_id, yetki) values
    (v_rol_tam,   v_modul,     'tam'),
    (v_rol_tam,   v_modul_oda, 'tam'),
    (v_rol_kayit, v_modul,     'kayit');

  insert into auth.users (id) values
    (v_sup_auth), (v_w1_auth), (v_w2_auth), (v_yab_auth), (v_pasif_auth);

  insert into public.kullanicilar (ad, rol, rol_id, otel_id, aktif, auth_user_id)
  values ('T2 Sup', 'yonetici', v_rol_tam,  '810', true, v_sup_auth)  returning id into v_sup;
  insert into public.kullanicilar (ad, rol, rol_id, otel_id, aktif, auth_user_id)
  values ('T2 W1',  'depo',     v_rol_kayit,'810', true, v_w1_auth)   returning id into v_w1;
  insert into public.kullanicilar (ad, rol, rol_id, otel_id, aktif, auth_user_id)
  values ('T2 W2',  'depo',     v_rol_kayit,'810', true, v_w2_auth)   returning id into v_w2;
  insert into public.kullanicilar (ad, rol, rol_id, otel_id, aktif, auth_user_id)
  values ('T2 Yab', 'depo',     v_rol_kayit,'811', true, v_yab_auth)  returning id into v_yab;
  insert into public.kullanicilar (ad, rol, rol_id, otel_id, aktif, auth_user_id)
  values ('T2 Pasif','depo',    v_rol_kayit,'810', false, v_pasif_auth) returning id into v_pasif;

  insert into public.pms_oda_tipleri (otel_id, kod, ad, azami_kisi, azami_yetiskin, azami_cocuk)
  values ('810','a2','A2 Tip',2,2,1) returning id into v_tipi810;
  insert into public.pms_oda_tipleri (otel_id, kod, ad, azami_kisi, azami_yetiskin, azami_cocuk)
  values ('811','a2','A2 Tip',2,2,1) returning id into v_tipi811;

  -- Her bolum KENDI odasini kullanir: durum tasmasi testleri bozmasin.
  insert into public.pms_odalar (otel_id,oda_tipi_id,oda_no) values ('810',v_tipi810,'A201') returning id into v_oda;
  insert into public.pms_odalar (otel_id,oda_tipi_id,oda_no) values ('811',v_tipi811,'A201') returning id into v_oda811;
  insert into public.pms_odalar (otel_id,oda_tipi_id,oda_no) values ('810',v_tipi810,'D201') returning id into v_odaD;
  insert into public.pms_odalar (otel_id,oda_tipi_id,oda_no) values ('810',v_tipi810,'E201') returning id into v_odaE;
  insert into public.pms_odalar (otel_id,oda_tipi_id,oda_no) values ('810',v_tipi810,'F201') returning id into v_odaF;
  insert into public.pms_odalar (otel_id,oda_tipi_id,oda_no) values ('810',v_tipi810,'G201') returning id into v_odaG;

  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config('request.jwt.claim.sub', v_sup_auth::text, true);

  -- ==================================================================
  -- A. DURUM MAKİNESİ
  -- ==================================================================
  begin
    v_r := public.pms_housekeeping_gorev_olustur(v_oda,'ekstra_temizlik','bos',gen_random_uuid());
    v_g := (v_r->>'gorev_id')::uuid;
    select temizlik_durumu::text into v_oda_durum from public.pms_odalar where id=v_oda;
    if v_oda_durum='kirli' and (select temizlik_gorevi_id from public.pms_odalar where id=v_oda)=v_g then
      raise notice 'A1  OK    gorev acildi, oda kirli + gosterge kuruldu'; v_ok:=v_ok+1;
    else raise notice 'A1  FAIL  oda=%', v_oda_durum; v_fail:=v_fail+1; end if;
  exception when others then raise notice 'A1  FAIL  %', sqlerrm; v_fail:=v_fail+1; end;

  begin
    v_s := (select surum from public.pms_housekeeping_gorevleri where id=v_g);
    perform public.pms_housekeeping_tamamla(v_g, v_s, gen_random_uuid());
    raise notice 'A2  FAIL  bekliyor -> tamamla kabul edildi'; v_fail:=v_fail+1;
  exception when others then raise notice 'A2  OK    bekliyor -> tamamla reddedildi'; v_ok:=v_ok+1; end;

  perform set_config('request.jwt.claim.sub', v_w1_auth::text, true);
  begin
    v_s := (select surum from public.pms_housekeeping_gorevleri where id=v_g);
    v_r := public.pms_housekeeping_sahiplen(v_g, v_s, gen_random_uuid());
    v_r := public.pms_housekeeping_baslat(v_g, (v_r->>'surum')::bigint, gen_random_uuid());
    if v_r->>'durum'='temizleniyor' and v_r->>'oda_temizlik'='temizleniyor' then
      raise notice 'A3  OK    sahiplen+baslat, oda temizleniyor'; v_ok:=v_ok+1;
    else raise notice 'A3  FAIL  %', v_r; v_fail:=v_fail+1; end if;
  exception when others then raise notice 'A3  FAIL  %', sqlerrm; v_fail:=v_fail+1; end;

  perform set_config('request.jwt.claim.sub', v_w2_auth::text, true);
  begin
    v_s := (select surum from public.pms_housekeeping_gorevleri where id=v_g);
    perform public.pms_housekeeping_tamamla(v_g, v_s, gen_random_uuid());
    raise notice 'A4  FAIL  baska calisan tamamladi'; v_fail:=v_fail+1;
  exception when others then raise notice 'A4  OK    yalniz isi yapan tamamlayabilir'; v_ok:=v_ok+1; end;

  perform set_config('request.jwt.claim.sub', v_w1_auth::text, true);
  begin
    v_s := (select surum from public.pms_housekeeping_gorevleri where id=v_g);
    v_r := public.pms_housekeeping_tamamla(v_g, v_s, gen_random_uuid());
    if v_r->>'durum'='tamamlandi' and v_r->>'oda_temizlik'='temiz' then
      raise notice 'A5  OK    tamamlandi, oda temiz'; v_ok:=v_ok+1;
    else raise notice 'A5  FAIL  %', v_r; v_fail:=v_fail+1; end if;
  exception when others then raise notice 'A5  FAIL  %', sqlerrm; v_fail:=v_fail+1; end;

  begin
    v_s := (select surum from public.pms_housekeeping_gorevleri where id=v_g);
    perform public.pms_housekeeping_baslat(v_g, v_s, gen_random_uuid());
    raise notice 'A6  FAIL  tamamlanmis is yeniden baslatildi'; v_fail:=v_fail+1;
  exception when others then raise notice 'A6  OK    tamamlanmis is geri sarilamaz'; v_ok:=v_ok+1; end;

  begin
    v_s := (select surum from public.pms_housekeeping_gorevleri where id=v_g);
    perform public.pms_housekeeping_kontrol_et(v_g, v_s, gen_random_uuid());
    raise notice 'A7  FAIL  temizlikci kendi isini denetledi'; v_fail:=v_fail+1;
  exception when others then raise notice 'A7  OK    kendi isini denetleyemez'; v_ok:=v_ok+1; end;

  perform set_config('request.jwt.claim.sub', v_sup_auth::text, true);
  begin
    v_s := (select surum from public.pms_housekeeping_gorevleri where id=v_g);
    v_r := public.pms_housekeeping_kontrol_et(v_g, v_s, gen_random_uuid());
    if v_r->>'durum'='kontrol_edildi' and v_r->>'oda_temizlik'='kontrol_edildi' then
      raise notice 'A8  OK    denetlendi, oda kontrol_edildi'; v_ok:=v_ok+1;
    else raise notice 'A8  FAIL  %', v_r; v_fail:=v_fail+1; end if;
  exception when others then raise notice 'A8  FAIL  %', sqlerrm; v_fail:=v_fail+1; end;

  begin
    v_s := (select surum from public.pms_housekeeping_gorevleri where id=v_g);
    perform public.pms_housekeeping_iptal(v_g,'olmaz', v_s, gen_random_uuid());
    raise notice 'A9  FAIL  terminal gorev iptal edildi'; v_fail:=v_fail+1;
  exception when others then raise notice 'A9  OK    terminal gorev degistirilemez'; v_ok:=v_ok+1; end;

  -- ==================================================================
  -- B. SAHİPLİK / YETKİ
  -- ==================================================================
  v_r := public.pms_housekeeping_gorev_olustur(v_odaG,'ekstra_temizlik','bos',gen_random_uuid());
  v_g2 := (v_r->>'gorev_id')::uuid;

  perform set_config('request.jwt.claim.sub', v_w1_auth::text, true);
  perform public.pms_housekeeping_sahiplen(v_g2,(select surum from public.pms_housekeeping_gorevleri where id=v_g2),gen_random_uuid());

  perform set_config('request.jwt.claim.sub', v_w2_auth::text, true);
  begin
    v_s := (select surum from public.pms_housekeeping_gorevleri where id=v_g2);
    perform public.pms_housekeeping_sahiplen(v_g2, v_s, gen_random_uuid());
    raise notice 'B1  FAIL  ikinci calisan gorevi caldi'; v_fail:=v_fail+1;
  exception when others then raise notice 'B1  OK    atanmis gorev calinamaz'; v_ok:=v_ok+1; end;

  begin
    v_s := (select surum from public.pms_housekeeping_gorevleri where id=v_g2);
    perform public.pms_housekeeping_baslat(v_g2, v_s, gen_random_uuid());
    raise notice 'B2  FAIL  baskasinin gorevi baslatildi'; v_fail:=v_fail+1;
  exception when others then raise notice 'B2  OK    yalniz atanan baslatir'; v_ok:=v_ok+1; end;

  begin
    perform public.pms_housekeeping_gorev_olustur(v_odaD,'ekstra_temizlik','bos',gen_random_uuid());
    raise notice 'B3  FAIL  kayit yetkisi gorev acti'; v_fail:=v_fail+1;
  exception when others then raise notice 'B3  OK    gorev acmak `tam` istiyor'; v_ok:=v_ok+1; end;

  perform set_config('request.jwt.claim.sub', v_pasif_auth::text, true);
  begin
    perform public.pms_housekeeping_listele('810');
    raise notice 'B4  FAIL  pasif kullanici okudu'; v_fail:=v_fail+1;
  exception when others then raise notice 'B4  OK    pasif ERP kullanicisi reddedildi'; v_ok:=v_ok+1; end;

  perform set_config('request.jwt.claim.sub', gen_random_uuid()::text, true);
  begin
    perform public.pms_housekeeping_listele('810');
    raise notice 'B5  FAIL  ERP karsiligi olmayan kimlik okudu'; v_fail:=v_fail+1;
  exception when others then raise notice 'B5  OK    ERP karsiligi olmayan kimlik reddedildi'; v_ok:=v_ok+1; end;

  perform set_config('request.jwt.claim.sub','',true);
  begin
    perform public.pms_housekeeping_listele('810');
    raise notice 'B6  FAIL  kimliksiz cagri gecti'; v_fail:=v_fail+1;
  exception when others then raise notice 'B6  OK    kimliksiz cagri reddedildi'; v_ok:=v_ok+1; end;

  -- ==================================================================
  -- C. ÇOK OTEL
  -- ==================================================================
  perform set_config('request.jwt.claim.sub', v_sup_auth::text, true);
  begin
    perform public.pms_housekeeping_gorev_olustur(v_oda811,'ekstra_temizlik','bos',gen_random_uuid());
    raise notice 'C1  FAIL  capraz otel gorev acildi'; v_fail:=v_fail+1;
  exception when others then raise notice 'C1  OK    capraz otel oda reddedildi'; v_ok:=v_ok+1; end;

  begin
    v_s := (select surum from public.pms_housekeeping_gorevleri where id=v_g2);
    perform public.pms_housekeeping_ata(v_g2, v_yab, v_s, gen_random_uuid());
    raise notice 'C2  FAIL  yabanci otel calisani atandi'; v_fail:=v_fail+1;
  exception when others then raise notice 'C2  OK    yabanci otel calisani reddedildi'; v_ok:=v_ok+1; end;

  update public.kullanicilar set tum_oteller = true where id = v_yab;
  begin
    v_s := (select surum from public.pms_housekeeping_gorevleri where id=v_g2);
    perform public.pms_housekeeping_ata(v_g2, v_yab, v_s, gen_random_uuid());
    raise notice 'C3  OK    tum_oteller calisani atanabildi'; v_ok:=v_ok+1;
  exception when others then raise notice 'C3  FAIL  %', sqlerrm; v_fail:=v_fail+1; end;

  -- ==================================================================
  -- D. DOĞRUDAN YAZMA / SAHTECİLİK
  -- RLS'in gizlemediğinden EMİN olmak için supervisor `pms_oda` tam
  -- yetkisiyle çağırır; tek durdurucu bekçidir. Satır sayısı ölçülür.
  -- ==================================================================
  perform set_config('request.jwt.claim.sub', v_sup_auth::text, true);

  -- D0: RLS gercekten geciyor mu? (mesru bir yazma calismali)
  begin
    execute 'set local role authenticated';
    update public.pms_odalar set aciklama = 'rls kontrol' where id = v_odaD;
    get diagnostics v_n = row_count;
    execute 'reset role';
    if v_n = 1 then raise notice 'D0  OK    RLS gecirgen (bekci testleri anlamli)'; v_ok:=v_ok+1;
    else raise notice 'D0  FAIL  RLS engelliyor; D testleri olcum yapamaz'; v_fail:=v_fail+1; end if;
  exception when others then
    execute 'reset role';
    raise notice 'D0  FAIL  %', sqlerrm; v_fail:=v_fail+1;
  end;

  -- D1: temizlik durumu dogrudan degistirilemez
  begin
    execute 'set local role authenticated';
    update public.pms_odalar set temizlik_durumu='temiz' where id=v_odaD;
    get diagnostics v_n = row_count;
    execute 'reset role';
    raise notice 'D1  FAIL  dogrudan temizlik yazmasi gecti (% satir)', v_n; v_fail:=v_fail+1;
  exception when others then
    execute 'reset role';
    raise notice 'D1  OK    dogrudan temizlik yazmasi reddedildi'; v_ok:=v_ok+1;
  end;

  -- D2: gosterge dogrudan degistirilemez
  begin
    execute 'set local role authenticated';
    update public.pms_odalar set temizlik_gorevi_id=null where id=v_oda;
    get diagnostics v_n = row_count;
    execute 'reset role';
    raise notice 'D2  FAIL  dogrudan gosterge yazmasi gecti (% satir)', v_n; v_fail:=v_fail+1;
  exception when others then
    execute 'reset role';
    raise notice 'D2  OK    dogrudan gosterge yazmasi reddedildi'; v_ok:=v_ok+1;
  end;

  -- D3: gorev tablosuna dogrudan INSERT
  begin
    execute 'set local role authenticated';
    insert into public.pms_housekeeping_gorevleri
      (otel_id, oda_id, gorev_tipi, olusturma_kaynagi, istek_anahtari, istek_ozeti,
       son_islem_anahtari, son_islem_ozeti)
    values ('810', v_odaD, 'ekstra_temizlik','sistem', gen_random_uuid(),
            encode(sha256('x'::bytea),'hex'), gen_random_uuid(), encode(sha256('x'::bytea),'hex'));
    execute 'reset role';
    raise notice 'D3  FAIL  dogrudan gorev INSERT gecti'; v_fail:=v_fail+1;
  exception when others then
    execute 'reset role';
    raise notice 'D3  OK    dogrudan gorev INSERT reddedildi'; v_ok:=v_ok+1;
  end;

  -- ==================================================================
  -- E. H1-H10 (ihlal ve `set constraints` AYNI blokta)
  -- ==================================================================
  -- E1: bekleyen guncel gorev varken oda `temiz` -> H3
  begin
    insert into public.pms_housekeeping_gorevleri
      (otel_id,oda_id,gorev_tipi,olusturma_kaynagi,istek_anahtari,istek_ozeti,
       son_islem_anahtari,son_islem_ozeti)
    values ('810',v_odaE,'ekstra_temizlik','sistem',gen_random_uuid(),
            encode(sha256('e'::bytea),'hex'),gen_random_uuid(),encode(sha256('e'::bytea),'hex'))
    returning id into v_gE;
    update public.pms_odalar set temizlik_gorevi_id=v_gE, temizlik_durumu='kirli' where id=v_odaE;
    update public.pms_odalar set temizlik_durumu='temiz' where id=v_odaE;
    set constraints all immediate;
    raise notice 'E1  FAIL  H3 ihlali kabul edildi'; v_fail:=v_fail+1;
  exception when others then
    raise notice 'E1  OK    H3 ihlali ertelenmis kisitla yakalandi (%)', left(sqlerrm,40); v_ok:=v_ok+1;
  end;
  set constraints all deferred;

  -- E2: bitmemis gorev odanin guncel gorevi DEGILSE -> H2
  begin
    insert into public.pms_housekeeping_gorevleri
      (otel_id,oda_id,gorev_tipi,olusturma_kaynagi,istek_anahtari,istek_ozeti,
       son_islem_anahtari,son_islem_ozeti)
    values ('810',v_odaF,'ekstra_temizlik','sistem',gen_random_uuid(),
            encode(sha256('f'::bytea),'hex'),gen_random_uuid(),encode(sha256('f'::bytea),'hex'));
    -- gosterge KURULMADI: H2 ihlali
    set constraints all immediate;
    raise notice 'E2  FAIL  gostergesiz bitmemis gorev kabul edildi'; v_fail:=v_fail+1;
  exception when others then
    raise notice 'E2  OK    H2 ihlali yakalandi (%)', left(sqlerrm,40); v_ok:=v_ok+1;
  end;
  set constraints all deferred;

  -- ==================================================================
  -- F. IDEMPOTENCY  (temiz oda: F201'de kalinti yok)
  -- ==================================================================
  perform set_config('request.jwt.claim.sub', v_sup_auth::text, true);
  v_key := gen_random_uuid();
  begin
    v_r  := public.pms_housekeeping_gorev_olustur(v_odaF,'ekstra_temizlik','bos',v_key);
    v_r2 := public.pms_housekeeping_gorev_olustur(v_odaF,'ekstra_temizlik','bos',v_key);
    if (v_r->>'gorev_id') = (v_r2->>'gorev_id') and (v_r2->>'tekrar')::boolean then
      raise notice 'F1  OK    olusturma tekrari ayni satiri dondu'; v_ok:=v_ok+1;
    else raise notice 'F1  FAIL  ilk=% ikinci=%', v_r, v_r2; v_fail:=v_fail+1; end if;
  exception when others then raise notice 'F1  FAIL  %', sqlerrm; v_fail:=v_fail+1; end;

  begin
    perform public.pms_housekeeping_gorev_olustur(v_odaF,'konaklama_temizligi','dolu',v_key);
    raise notice 'F2  FAIL  ayni anahtar farkli icerikle gecti'; v_fail:=v_fail+1;
  exception when others then raise notice 'F2  OK    ayni anahtar farkli icerik reddedildi'; v_ok:=v_ok+1; end;

  v_g2 := (v_r->>'gorev_id')::uuid;
  perform set_config('request.jwt.claim.sub', v_w1_auth::text, true);
  begin
    v_key := gen_random_uuid();
    v_s := (select surum from public.pms_housekeeping_gorevleri where id=v_g2);
    v_r  := public.pms_housekeeping_sahiplen(v_g2, v_s, v_key);
    v_r2 := public.pms_housekeeping_sahiplen(v_g2, v_s, v_key);
    if (v_r2->>'tekrar')::boolean and (v_r->>'surum') = (v_r2->>'surum') then
      raise notice 'F3  OK    komut tekrari yan etkisiz (surum %)', v_r2->>'surum'; v_ok:=v_ok+1;
    else raise notice 'F3  FAIL  ilk=% ikinci=%', v_r, v_r2; v_fail:=v_fail+1; end if;
  exception when others then raise notice 'F3  FAIL  %', sqlerrm; v_fail:=v_fail+1; end;

  begin
    v_s := (select surum from public.pms_housekeeping_gorevleri where id=v_g2);
    perform public.pms_housekeeping_baslat(v_g2, v_s, gen_random_uuid());
    perform public.pms_housekeeping_birak(v_g2, v_s, gen_random_uuid());
    raise notice 'F4  FAIL  bayat surum kabul edildi'; v_fail:=v_fail+1;
  exception when others then raise notice 'F4  OK    bayat surum catismasi verdi'; v_ok:=v_ok+1; end;

  -- ==================================================================
  -- G. YENİDEN AÇMA / DEVİR
  -- ==================================================================
  perform set_config('request.jwt.claim.sub', v_sup_auth::text, true);
  -- G1: denetlenmis is yeniden acilinca ARDIL olusur, oncul DEGISMEZ
  begin
    v_s := (select surum from public.pms_housekeeping_gorevleri where id=v_g);
    v_r := public.pms_housekeeping_yeniden_ac(v_g, 'yeniden temizlik', v_s, gen_random_uuid());
    select durum into v_oda_durum from public.pms_housekeeping_gorevleri where id=v_g;
    if (v_r->>'gorev_id')::uuid <> v_g and v_oda_durum = 'kontrol_edildi'
       and (select onceki_gorev_id from public.pms_housekeeping_gorevleri
             where id=(v_r->>'gorev_id')::uuid) = v_g
       and (select temizlik_durumu::text from public.pms_odalar where id=v_oda) = 'kirli' then
      raise notice 'G1  OK    ardil olustu, oncul degismedi, oda kirlendi'; v_ok:=v_ok+1;
    else raise notice 'G1  FAIL  %', v_r; v_fail:=v_fail+1; end if;
  exception when others then raise notice 'G1  FAIL  %', sqlerrm; v_fail:=v_fail+1; end;

  -- G2: ayni oncul iki kez yeniden acilamaz
  begin
    v_s := (select surum from public.pms_housekeeping_gorevleri where id=v_g);
    perform public.pms_housekeeping_yeniden_ac(v_g, 'ikinci', v_s, gen_random_uuid());
    raise notice 'G2  FAIL  ayni oncul iki ardil uretti'; v_fail:=v_fail+1;
  exception when others then raise notice 'G2  OK    oncul basina tek ardil'; v_ok:=v_ok+1; end;

  -- ==================================================================
  -- H. TETİKLEYİCİ SIRASI
  -- ==================================================================
  select array_agg(tgname order by tgname) into v_sira
    from pg_trigger where tgrelid='public.pms_odalar'::regclass
      and not tgisinternal and (tgtype & 2) <> 0;
  if v_sira = array['phase0_otel_degismez','pms_housekeeping_oda_koruma',
                    'pms_oda_envanter_kontrol','pms_oda_gecis','pms_odalar_guncelleme'] then
    raise notice 'H1  OK    BEFORE tetikleyici sirasi beklenen'; v_ok:=v_ok+1;
  else raise notice 'H1  FAIL  %', v_sira; v_fail:=v_fail+1; end if;

  raise notice '--------------------------------------------------';
  raise notice 'ARTIM 2 SONUC: % OK / % FAIL', v_ok, v_fail;
  if v_fail > 0 then
    raise exception 'ARTIM 2 TESTLERI BASARISIZ: % test', v_fail;
  end if;
end;
$$;

rollback;
