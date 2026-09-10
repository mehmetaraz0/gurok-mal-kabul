-- ============================================================================
-- PMS FAZ 2 / ARTIM 3 — YAŞAM DÖNGÜSÜ, ÇIKIŞ ÜRETİCİSİ, DENETİM İZİ
-- ----------------------------------------------------------------------------
-- YALNIZ ATILABILIR YEREL/STAGING VERİTABANINDA ÇALIŞTIRILIR.
--   psql -X -U postgres -d hkdb -f scripts/pms-faz2-housekeeping-artim3-testleri.sql
--
-- Tüm test tek transaction'dadır ve ROLLBACK edilir.
-- ============================================================================

\set ON_ERROR_STOP on

begin;

update public.moduller set aktif = true where kod = 'pms_housekeeping';

do $$
declare
  v_ok int := 0; v_fail int := 0;
  v_rol uuid; v_rolw uuid; v_auth uuid := gen_random_uuid(); v_wauth uuid := gen_random_uuid();
  v_kul uuid; v_w uuid;
  v_tip uuid; v_oda uuid; v_odaB uuid; v_odaC uuid; v_odaD uuid;
  v_mis uuid; v_rez uuid; v_atama uuid;
  v_g uuid; v_g2 uuid; v_s bigint; v_r jsonb;
  v_durum text; v_temiz text; v_kullanim text; v_n int; v_d jsonb; v_neden text;
  v_kaynak uuid; v_oncul uuid; v_kaynagi text; v_olusturan uuid;

begin
  -- ================= FİKSTÜR =================
  insert into public.moduller (kod, ad, kategori, sira, aktif) values
    ('pms_oda','On Buro - Odalar','onburo',44,true),
    ('pms_oda_tipi','On Buro - Oda Tipleri','onburo',43,true),
    ('pms_misafir','On Buro - Misafirler','onburo',45,true),
    ('pms_rezervasyon','On Buro - Rezervasyonlar','onburo',47,true)
  on conflict (kod) do update set aktif = true;

  insert into public.roller (ad, seviye) values ('A3 Yonetici','otel') returning id into v_rol;
  insert into public.roller (ad, seviye) values ('A3 Calisan','otel')  returning id into v_rolw;

  insert into public.yetki_matrisi (rol_id, modul_id, yetki)
  select v_rol, id, 'tam' from public.moduller
   where kod in ('pms_oda','pms_oda_tipi','pms_misafir','pms_rezervasyon','pms_housekeeping');
  insert into public.yetki_matrisi (rol_id, modul_id, yetki)
  select v_rolw, id, 'kayit' from public.moduller where kod = 'pms_housekeeping';

  insert into auth.users (id) values (v_auth), (v_wauth);
  insert into public.kullanicilar (ad, rol, rol_id, otel_id, aktif, auth_user_id)
  values ('A3 Yonetici','yonetici', v_rol, '810', true, v_auth) returning id into v_kul;
  insert into public.kullanicilar (ad, rol, rol_id, otel_id, aktif, auth_user_id)
  values ('A3 Calisan','depo', v_rolw, '810', true, v_wauth) returning id into v_w;

  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config('request.jwt.claim.sub', v_auth::text, true);

  insert into public.pms_oda_tipleri (otel_id,kod,ad,azami_kisi,azami_yetiskin,azami_cocuk)
  values ('810','a3','A3 Tip',4,4,2) returning id into v_tip;
  insert into public.pms_odalar (otel_id,oda_tipi_id,oda_no) values ('810',v_tip,'L101') returning id into v_oda;
  insert into public.pms_odalar (otel_id,oda_tipi_id,oda_no) values ('810',v_tip,'L102') returning id into v_odaB;
  insert into public.pms_odalar (otel_id,oda_tipi_id,oda_no) values ('810',v_tip,'L103') returning id into v_odaC;
  insert into public.pms_odalar (otel_id,oda_tipi_id,oda_no) values ('810',v_tip,'L104') returning id into v_odaD;
  insert into public.pms_misafirler (otel_id, ad, soyad) values ('810','A3','Misafir') returning id into v_mis;

  -- ==================================================================
  -- L1  ÇIKIŞ ÜRETİCİSİ: check-in -> check-out -> oda bos+kirli + 1 gorev
  -- ==================================================================
  update public.pms_odalar set temizlik_durumu='temiz' where id=v_oda;
  insert into public.pms_rezervasyonlar
    (otel_id,misafir_id,oda_tipi_id,giris_tarihi,cikis_tarihi,yetiskin_sayisi,durum,gecelik_fiyat)
  values ('810',v_mis,v_tip,public.pms_bugun(),public.pms_bugun()+1,1,'onaylandi',1000)
  returning id into v_rez;

  begin
    execute 'set local role authenticated';
    perform public.pms_check_in(v_rez, v_oda);
    perform public.pms_check_out(v_rez);
    execute 'reset role';

    select kullanim_durumu::text, temizlik_durumu::text, temizlik_gorevi_id
      into v_kullanim, v_temiz, v_g from public.pms_odalar where id=v_oda;
    select count(*) into v_n from public.pms_housekeeping_gorevleri
     where oda_id=v_oda and gorev_tipi='cikis_temizligi';
    select kaynak_atama_id, olusturma_kaynagi, olusturan
      into v_kaynak, v_kaynagi, v_olusturan
      from public.pms_housekeeping_gorevleri where id=v_g;
    select id into v_atama from public.pms_oda_atamalari where rezervasyon_id=v_rez;

    if v_kullanim='bos' and v_temiz='kirli' and v_n=1 and v_g is not null
       and v_kaynak = v_atama and v_kaynagi='checkout' and v_olusturan=v_kul then
      raise notice 'L1  OK    cikis: oda bos+kirli, 1 cikis_temizligi, kaynak+aktor dogru'; v_ok:=v_ok+1;
    else
      raise notice 'L1  FAIL  kullanim=% temizlik=% gorev=% kaynak_esit=% kaynagi=% aktor=%',
        v_kullanim, v_temiz, v_n, (v_kaynak=v_atama), v_kaynagi, (v_olusturan=v_kul); v_fail:=v_fail+1;
    end if;
  exception when others then
    execute 'reset role'; raise notice 'L1  FAIL  %', sqlerrm; v_fail:=v_fail+1;
  end;

  -- ==================================================================
  -- L2  TEKRAR ÇIKIŞ: Faz 1 semantigi korunur (reddedilir)
  -- ==================================================================
  begin
    execute 'set local role authenticated';
    perform public.pms_check_out(v_rez);
    execute 'reset role';
    raise notice 'L2  FAIL  tekrar cikis kabul edildi'; v_fail:=v_fail+1;
  exception when others then
    execute 'reset role';
    raise notice 'L2  OK    tekrar cikis Faz 1 tarafindan reddedildi'; v_ok:=v_ok+1;
  end;

  -- ==================================================================
  -- L3  DENETİM İZİ: gorev olayinda semantik ayrinti var, not govdesi YOK
  -- ==================================================================
  select islem_detayi into v_d from public.erp_islem_audit
   where entity_type='pms_housekeeping_gorevleri' and entity_id=v_g::text
   order by id limit 1;
  if v_d is not null and v_d ? 'olusturma_kaynagi'
     and (v_d->>'olusturma_kaynagi')='checkout'
     and not (v_d ? 'notlar') and not (v_d ? 'ad') then
    raise notice 'L3  OK    denetim ayrintisi izin listesinden (not govdesi yok)'; v_ok:=v_ok+1;
  else
    raise notice 'L3  FAIL  %', v_d; v_fail:=v_fail+1;
  end if;

  -- ==================================================================
  -- L4  ESKİ ÇAĞIRAN GERİLEMESİ: rezervasyon denetimi NULL ayrinti verir
  -- ==================================================================
  select count(*) into v_n from public.erp_islem_audit
   where entity_type='pms_rezervasyonlar' and islem_detayi is not null;
  if v_n = 0 then
    raise notice 'L4  OK    eski denetim cagiranlari NULL ayrinti uretiyor'; v_ok:=v_ok+1;
  else raise notice 'L4  FAIL  % eski satirda ayrinti var', v_n; v_fail:=v_fail+1; end if;

  -- ==================================================================
  -- L5  YAŞAM DÖNGÜSÜ: calisan is varken oda BLOKE -> iptal + kirli
  -- ==================================================================
  perform set_config('request.jwt.claim.sub', v_wauth::text, true);
  v_s := (select surum from public.pms_housekeeping_gorevleri where id=v_g);
  v_r := public.pms_housekeeping_sahiplen(v_g, v_s, gen_random_uuid());
  v_r := public.pms_housekeeping_baslat(v_g, (v_r->>'surum')::bigint, gen_random_uuid());
  perform set_config('request.jwt.claim.sub', v_auth::text, true);

  begin
    update public.pms_odalar set kullanim_durumu='bloke' where id=v_oda;
    select durum, iptal_nedeni into v_durum, v_neden
      from public.pms_housekeeping_gorevleri where id=v_g;
    select temizlik_durumu::text into v_temiz from public.pms_odalar where id=v_oda;
    if v_durum='iptal' and v_neden='oda_bloke' and v_temiz='kirli' then
      raise notice 'L5  OK    bloke: calisan is iptal (oda_bloke), oda kirli'; v_ok:=v_ok+1;
    else raise notice 'L5  FAIL  durum=% neden=% temizlik=%', v_durum, v_neden, v_temiz; v_fail:=v_fail+1; end if;
  exception when others then raise notice 'L5  FAIL  %', sqlerrm; v_fail:=v_fail+1; end;

  -- ==================================================================
  -- L6  SERBEST BIRAKMA ÜRETİCİSİ: bloke -> bos, kirli -> TEK ekstra gorev
  -- ==================================================================
  begin
    update public.pms_odalar set kullanim_durumu='bos' where id=v_oda;
    select count(*) into v_n from public.pms_housekeeping_gorevleri
     where oda_id=v_oda and durum='bekliyor';
    select temizlik_gorevi_id into v_g2 from public.pms_odalar where id=v_oda;
    select olusturma_kaynagi, olusturan into v_kaynagi, v_olusturan
      from public.pms_housekeeping_gorevleri where id=v_g2;
    if v_n=1 and v_kaynagi='sistem' and v_olusturan is null then
      raise notice 'L6  OK    serbest birakma: 1 sistem gorevi, aktor NULL (sentinel yok)'; v_ok:=v_ok+1;
    else raise notice 'L6  FAIL  n=% kaynagi=% aktor=%', v_n, v_kaynagi, v_olusturan; v_fail:=v_fail+1; end if;
  exception when others then raise notice 'L6  FAIL  %', sqlerrm; v_fail:=v_fail+1; end;

  -- ==================================================================
  -- L7  MUKERRER URETIM YOK: bekleyen is varken tekrar bloke->bos
  -- ==================================================================
  begin
    update public.pms_odalar set kullanim_durumu='bloke' where id=v_oda;
    update public.pms_odalar set kullanim_durumu='bos'   where id=v_oda;
    select count(*) into v_n from public.pms_housekeeping_gorevleri
     where oda_id=v_oda and durum in ('bekliyor','temizleniyor');
    if v_n=1 then
      raise notice 'L7  OK    mevcut bekleyen is yeniden kullanildi, mukerrer yok'; v_ok:=v_ok+1;
    else raise notice 'L7  FAIL  bitmemis gorev sayisi %', v_n; v_fail:=v_fail+1; end if;
  exception when others then raise notice 'L7  FAIL  %', sqlerrm; v_fail:=v_fail+1; end;

  -- ==================================================================
  -- L8  SIRADAN BLOKE (calisan is yok, oda TEMIZ) -> temizlik KORUNUR
  -- ==================================================================
  update public.pms_odalar set temizlik_durumu='temiz' where id=v_odaB;
  begin
    update public.pms_odalar set kullanim_durumu='bloke' where id=v_odaB;
    select temizlik_durumu::text into v_temiz from public.pms_odalar where id=v_odaB;
    if v_temiz='temiz' then
      raise notice 'L8  OK    siradan bloke temizligi bozmuyor'; v_ok:=v_ok+1;
    else raise notice 'L8  FAIL  temizlik=%', v_temiz; v_fail:=v_fail+1; end if;
  exception when others then raise notice 'L8  FAIL  %', sqlerrm; v_fail:=v_fail+1; end;

  -- ==================================================================
  -- L9  ARIZA hazirligi GECERSIZLESTIRIR
  -- ==================================================================
  update public.pms_odalar set kullanim_durumu='bos', temizlik_durumu='temiz' where id=v_odaC;
  begin
    update public.pms_odalar set kullanim_durumu='ariza' where id=v_odaC;
    select temizlik_durumu::text into v_temiz from public.pms_odalar where id=v_odaC;
    if v_temiz='kirli' then
      raise notice 'L9  OK    ariza hazirligi gecersizlestirdi (kirli)'; v_ok:=v_ok+1;
    else raise notice 'L9  FAIL  temizlik=%', v_temiz; v_fail:=v_fail+1; end if;
  exception when others then raise notice 'L9  FAIL  %', sqlerrm; v_fail:=v_fail+1; end;

  -- ==================================================================
  -- L10 MODUL KAPALI: cikis calisir, oda bos+kirli, GOREV URETILMEZ
  -- ==================================================================
  update public.moduller set aktif=false where kod='pms_housekeeping';
  update public.pms_odalar set temizlik_durumu='temiz', kullanim_durumu='bos' where id=v_odaD;
  insert into public.pms_rezervasyonlar
    (otel_id,misafir_id,oda_tipi_id,giris_tarihi,cikis_tarihi,yetiskin_sayisi,durum,gecelik_fiyat)
  values ('810',v_mis,v_tip,public.pms_bugun(),public.pms_bugun()+1,1,'onaylandi',1000)
  returning id into v_rez;

  begin
    execute 'set local role authenticated';
    perform public.pms_check_in(v_rez, v_odaD);
    perform public.pms_check_out(v_rez);
    execute 'reset role';
    select kullanim_durumu::text, temizlik_durumu::text, temizlik_gorevi_id
      into v_kullanim, v_temiz, v_g2 from public.pms_odalar where id=v_odaD;
    select count(*) into v_n from public.pms_housekeeping_gorevleri where oda_id=v_odaD;
    if v_kullanim='bos' and v_temiz='kirli' and v_n=0 and v_g2 is null then
      raise notice 'L10 OK    modul kapali: cikis calisti, gorev uretilmedi'; v_ok:=v_ok+1;
    else raise notice 'L10 FAIL  kullanim=% temizlik=% gorev=% gosterge=%',
      v_kullanim, v_temiz, v_n, v_g2; v_fail:=v_fail+1; end if;
  exception when others then
    execute 'reset role'; raise notice 'L10 FAIL  %', sqlerrm; v_fail:=v_fail+1;
  end;

  -- ==================================================================
  -- L11 MODUL KAPALI: genel RPC'ler kapali
  -- ==================================================================
  begin
    perform public.pms_housekeeping_listele('810');
    raise notice 'L11 FAIL  modul kapaliyken okuma gecti'; v_fail:=v_fail+1;
  exception when others then
    raise notice 'L11 OK    modul kapaliyken okuma reddedildi'; v_ok:=v_ok+1;
  end;

  -- ==================================================================
  -- L12 MODUL KAPALI: dogrudan temizlik PATCH'i YINE kapali
  -- ==================================================================
  begin
    execute 'set local role authenticated';
    update public.pms_odalar set temizlik_durumu='temiz' where id=v_odaD;
    execute 'reset role';
    raise notice 'L12 FAIL  modul kapaliyken eski PATCH yolu acildi'; v_fail:=v_fail+1;
  exception when others then
    execute 'reset role';
    raise notice 'L12 OK    modul kapaliyken de dogrudan PATCH kapali'; v_ok:=v_ok+1;
  end;

  -- ==================================================================
  -- L13 MODUL KAPALI: yasam dongusu YINE calisir (tutarlilik korunur)
  -- ==================================================================
  update public.moduller set aktif=true where kod='pms_housekeeping';
  perform set_config('request.jwt.claim.sub', v_wauth::text, true);
  select temizlik_gorevi_id into v_g2 from public.pms_odalar where id=v_oda;
  v_s := (select surum from public.pms_housekeeping_gorevleri where id=v_g2);
  v_r := public.pms_housekeeping_sahiplen(v_g2, v_s, gen_random_uuid());
  v_r := public.pms_housekeeping_baslat(v_g2, (v_r->>'surum')::bigint, gen_random_uuid());
  perform set_config('request.jwt.claim.sub', v_auth::text, true);
  update public.moduller set aktif=false where kod='pms_housekeeping';

  begin
    update public.pms_odalar set aktif=false where id=v_oda;
    select durum, iptal_nedeni into v_durum, v_neden
      from public.pms_housekeeping_gorevleri where id=v_g2;
    if v_durum='iptal' and v_neden='oda_pasif' then
      raise notice 'L13 OK    modul kapali olsa da yasam dongusu calisti'; v_ok:=v_ok+1;
    else raise notice 'L13 FAIL  durum=% neden=%', v_durum, v_neden; v_fail:=v_fail+1; end if;
  exception when others then raise notice 'L13 FAIL  %', sqlerrm; v_fail:=v_fail+1; end;
  update public.moduller set aktif=true where kod='pms_housekeeping';
  update public.pms_odalar set aktif=true where id=v_oda;

  -- ==================================================================
  -- L14 DENETİM ARIZASI IS ISLEMINI GERI ALIR
  -- Denetim tablosuna gecici bir CHECK konur; komut BASARISIZ olmali ve
  -- gorev DEGISMEMELI.
  -- ==================================================================
  -- Once hedef gorev hazirlanir; KISIT ancak ondan sonra konur, yoksa
  -- hazirligin kendi oda yazmasi kurulumu dusurur.
  select temizlik_gorevi_id into v_g2 from public.pms_odalar where id=v_odaC;
  if v_g2 is null then
    update public.pms_odalar set kullanim_durumu='bos' where id=v_odaC;
    select temizlik_gorevi_id into v_g2 from public.pms_odalar where id=v_odaC;
  end if;
  v_s := (select surum from public.pms_housekeeping_gorevleri where id=v_g2);

  begin
    alter table public.erp_islem_audit
      add constraint a3_denetim_sabotaj check (event_type <> 'UPDATE') not valid;

    begin
      perform set_config('request.jwt.claim.sub', v_wauth::text, true);
      perform public.pms_housekeeping_sahiplen(v_g2, v_s, gen_random_uuid());
      perform set_config('request.jwt.claim.sub', v_auth::text, true);
      raise notice 'L14 FAIL  denetim arizasina ragmen komut gecti'; v_fail:=v_fail+1;
    exception when others then
      perform set_config('request.jwt.claim.sub', v_auth::text, true);
      if (select surum from public.pms_housekeeping_gorevleri where id=v_g2) = v_s then
        raise notice 'L14 OK    denetim arizasi is islemini geri aldi (surum degismedi)'; v_ok:=v_ok+1;
      else
        raise notice 'L14 FAIL  gorev degismis kaldi'; v_fail:=v_fail+1;
      end if;
    end;
    alter table public.erp_islem_audit drop constraint a3_denetim_sabotaj;
  exception when others then
    raise notice 'L14 FAIL  kurulum: %', sqlerrm; v_fail:=v_fail+1;
  end;

  raise notice '--------------------------------------------------';
  raise notice 'ARTIM 3 SONUC: % OK / % FAIL', v_ok, v_fail;
  if v_fail > 0 then
    raise exception 'ARTIM 3 TESTLERI BASARISIZ: % test', v_fail;
  end if;
end;
$$;

rollback;
