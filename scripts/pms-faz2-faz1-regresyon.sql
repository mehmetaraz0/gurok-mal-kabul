-- ============================================================================
-- PMS FAZ 2 / ARTIM 2 — FAZ 1 REGRESYON TESTİ
-- ----------------------------------------------------------------------------
-- YALNIZ ATILABILIR YEREL/STAGING VERİTABANINDA ÇALIŞTIRILIR.
--
--   psql -X -U postgres -d hkdb -f scripts/pms-faz2-faz1-regresyon.sql
--
-- NEDEN: Artım 2 `pms_odalar` üzerine YENİ bir BEFORE bekçisi ekliyor ve o
-- bekçi uygulama rolünün temizlik/gösterge yazmalarını reddediyor. Faz 1
-- check-in/check-out ve oda yönetimi INVOKER'dır, yani `authenticated`
-- olarak çalışır ve bu bekçiden GEÇMEK ZORUNDADIR.
--
-- Bekçi meşru Faz 1 davranışını kırarsa BU DOSYA KIRMIZI OLUR. Çözüm
-- bekçiyi körlemesine gevşetmek değil, doğru yeri düzeltmektir.
--
-- Tüm test tek transaction'dadır ve ROLLBACK edilir.
-- ============================================================================

\set ON_ERROR_STOP on

begin;

do $$
declare
  v_ok int := 0; v_fail int := 0;
  v_rol uuid; v_auth uuid := gen_random_uuid(); v_kul uuid;
  v_tip uuid; v_oda uuid; v_oda2 uuid;
  v_misafir uuid; v_rez uuid; v_rez2 uuid;
  v_n int; v_durum text; v_kullanim text;
begin
  -- ---- FİKSTÜR: tam yetkili resepsiyon kullanicisi -------------------
  insert into public.roller (ad, seviye) values ('R1 Resepsiyon','otel') returning id into v_rol;

  insert into public.moduller (kod, ad, kategori, sira, aktif) values
    ('pms_oda','On Buro - Odalar','onburo',44,true),
    ('pms_oda_tipi','On Buro - Oda Tipleri','onburo',43,true),
    ('pms_misafir','On Buro - Misafirler','onburo',45,true),
    ('pms_rezervasyon','On Buro - Rezervasyonlar','onburo',47,true)
  on conflict (kod) do update set aktif = true;

  insert into public.yetki_matrisi (rol_id, modul_id, yetki)
  select v_rol, id, 'tam' from public.moduller
   where kod in ('pms_oda','pms_oda_tipi','pms_misafir','pms_rezervasyon');

  insert into auth.users (id) values (v_auth);
  insert into public.kullanicilar (ad, rol, rol_id, otel_id, aktif, auth_user_id)
  values ('R1 Resepsiyon','yonetici', v_rol, '810', true, v_auth) returning id into v_kul;

  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config('request.jwt.claim.sub', v_auth::text, true);

  insert into public.pms_oda_tipleri (otel_id,kod,ad,azami_kisi,azami_yetiskin,azami_cocuk)
  values ('810','r1','R1 Tip',2,2,1) returning id into v_tip;

  -- ==================================================================
  -- R1  Oda OLUSTURMA (uygulama rolu) hala calisiyor
  -- ==================================================================
  begin
    execute 'set local role authenticated';
    insert into public.pms_odalar (otel_id, oda_tipi_id, oda_no)
    values ('810', v_tip, 'R101') returning id into v_oda;
    execute 'reset role';
    if v_oda is not null then
      raise notice 'R1  OK    oda olusturma calisiyor'; v_ok:=v_ok+1;
    else raise notice 'R1  FAIL  oda olusmadi'; v_fail:=v_fail+1; end if;
  exception when others then
    execute 'reset role';
    raise notice 'R1  FAIL  %', sqlerrm; v_fail:=v_fail+1;
  end;

  -- ==================================================================
  -- R2  Oda DUZENLEME (temizlik disi alanlar) hala calisiyor
  -- ==================================================================
  begin
    execute 'set local role authenticated';
    update public.pms_odalar set aciklama='regresyon', kat='1' where id=v_oda;
    get diagnostics v_n = row_count;
    execute 'reset role';
    if v_n = 1 then raise notice 'R2  OK    oda duzenleme calisiyor'; v_ok:=v_ok+1;
    else raise notice 'R2  FAIL  % satir', v_n; v_fail:=v_fail+1; end if;
  exception when others then
    execute 'reset role';
    raise notice 'R2  FAIL  %', sqlerrm; v_fail:=v_fail+1;
  end;

  -- ==================================================================
  -- R3  KIRLI odaya check-in REDDEDILIR (Faz 1 davranisi korunuyor)
  -- ==================================================================
  insert into public.pms_misafirler (otel_id, ad, soyad)
  values ('810','Reg','Test') returning id into v_misafir;

  insert into public.pms_rezervasyonlar
    (otel_id, misafir_id, oda_tipi_id, giris_tarihi, cikis_tarihi, yetiskin_sayisi, durum, gecelik_fiyat)
  values ('810', v_misafir, v_tip, public.pms_bugun(), public.pms_bugun()+1, 1, 'onaylandi', 1000)
  returning id into v_rez;

  begin
    execute 'set local role authenticated';
    perform public.pms_check_in(v_rez, v_oda);      -- oda `kirli` dogdu
    execute 'reset role';
    raise notice 'R3  FAIL  kirli odaya check-in gecti'; v_fail:=v_fail+1;
  exception when others then
    execute 'reset role';
    raise notice 'R3  OK    kirli odaya check-in reddedildi'; v_ok:=v_ok+1;
  end;

  -- ==================================================================
  -- R4  TEMIZ odaya check-in CALISIYOR
  -- Odayi mesru yoldan temizleriz: guvenilir yazar (kat hizmeti motorunun
  -- yapacagi izdusumun ayni), sonra uygulama rolu check-in yapar.
  -- ==================================================================
  update public.pms_odalar set temizlik_durumu='temiz' where id=v_oda;
  begin
    execute 'set local role authenticated';
    perform public.pms_check_in(v_rez, v_oda);
    execute 'reset role';
    select kullanim_durumu::text, temizlik_durumu::text into v_kullanim, v_durum
      from public.pms_odalar where id=v_oda;
    if v_kullanim='dolu' and v_durum='temiz' then
      raise notice 'R4  OK    temiz odaya check-in calisiyor (oda dolu/temiz)'; v_ok:=v_ok+1;
    else raise notice 'R4  FAIL  kullanim=% temizlik=%', v_kullanim, v_durum; v_fail:=v_fail+1; end if;
  exception when others then
    execute 'reset role';
    raise notice 'R4  FAIL  %', sqlerrm; v_fail:=v_fail+1;
  end;

  -- ==================================================================
  -- R5  CHECK-OUT calisiyor: oda bos + kirli
  -- ==================================================================
  begin
    execute 'set local role authenticated';
    perform public.pms_check_out(v_rez);
    execute 'reset role';
    select kullanim_durumu::text, temizlik_durumu::text into v_kullanim, v_durum
      from public.pms_odalar where id=v_oda;
    if v_kullanim='bos' and v_durum='kirli' then
      raise notice 'R5  OK    check-out calisiyor (oda bos/kirli)'; v_ok:=v_ok+1;
    else raise notice 'R5  FAIL  kullanim=% temizlik=%', v_kullanim, v_durum; v_fail:=v_fail+1; end if;
  exception when others then
    execute 'reset role';
    raise notice 'R5  FAIL  %', sqlerrm; v_fail:=v_fail+1;
  end;

  -- ==================================================================
  -- R6  GECIKMIS konaklama: planlanan cikis gecmis olsa da check-out calisir
  -- ==================================================================
  insert into public.pms_odalar (otel_id, oda_tipi_id, oda_no)
  values ('810', v_tip, 'R102') returning id into v_oda2;
  update public.pms_odalar set temizlik_durumu='kontrol_edildi' where id=v_oda2;

  -- GECİKMİŞ KONAKLAMA. Faz 1 check-in'i çıkış tarihi geçmiş rezervasyonu
  -- reddeder ve süren konaklamada atama tarihleri değiştirilemez — ikisi de
  -- doğru Faz 1 davranışıdır. Bu yüzden gecikmiş durum, güvenilir yazar
  -- olarak DOĞRUDAN kurulur; ölçülen şey `pms_check_out`'un planlanan çıkış
  -- tarihine BAKMADIĞIDIR.
  set constraints all deferred;

  insert into public.pms_rezervasyonlar
    (otel_id, misafir_id, oda_tipi_id, giris_tarihi, cikis_tarihi, yetiskin_sayisi, durum, gecelik_fiyat)
  values ('810', v_misafir, v_tip, public.pms_bugun()-5, public.pms_bugun()-2, 1, 'onaylandi', 1000)
  returning id into v_rez2;

  insert into public.pms_oda_atamalari (otel_id, rezervasyon_id, oda_id, baslangic, bitis, aktif)
  values ('810', v_rez2, v_oda2, public.pms_bugun()-5, public.pms_bugun()-2, true);

  update public.pms_odalar set kullanim_durumu='dolu' where id=v_oda2;
  update public.pms_rezervasyonlar set durum='giris_yapildi', giris_zamani=now(), giris_yapan=v_auth
   where id=v_rez2;

  begin
    execute 'set local role authenticated';
    perform public.pms_check_out(v_rez2);           -- planlanan cikis GECMIS
    execute 'reset role';
    select kullanim_durumu::text into v_kullanim from public.pms_odalar where id=v_oda2;
    if v_kullanim='bos' then
      raise notice 'R6  OK    gecikmis konaklama check-in/out calisiyor'; v_ok:=v_ok+1;
    else raise notice 'R6  FAIL  kullanim=%', v_kullanim; v_fail:=v_fail+1; end if;
  exception when others then
    execute 'reset role';
    raise notice 'R6  FAIL  %', sqlerrm; v_fail:=v_fail+1;
  end;

  raise notice '--------------------------------------------------';
  raise notice 'FAZ 1 REGRESYON: % OK / % FAIL', v_ok, v_fail;
  if v_fail > 0 then
    raise exception 'FAZ 1 REGRESYON BASARISIZ: % test', v_fail;
  end if;
end;
$$;

rollback;
