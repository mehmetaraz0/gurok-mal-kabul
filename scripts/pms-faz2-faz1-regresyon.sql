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
  v_misafir uuid; v_rez uuid; v_rez2 uuid; v_rez3 uuid;
  v_oda3 uuid; v_oda4 uuid; v_rez4 uuid; v_folio uuid; v_folio4 uuid; v_hareket uuid; v_menu uuid; v_siparis uuid;
  v_n int; v_n2 int; v_durum text; v_kullanim text;
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

  -- ==================================================================
  -- R7  REZERVASYON DURUM MAKINESI hala kapali
  -- Giris yapilmamis bir rezervasyon DOGRUDAN `cikis_yapildi` olamaz.
  -- ==================================================================
  insert into public.pms_rezervasyonlar
    (otel_id, misafir_id, oda_tipi_id, giris_tarihi, cikis_tarihi, yetiskin_sayisi, durum, gecelik_fiyat)
  values ('810', v_misafir, v_tip, public.pms_bugun()+10, public.pms_bugun()+20, 1, 'onaylandi', 900)
  returning id into v_rez3;

  begin
    update public.pms_rezervasyonlar set durum='cikis_yapildi' where id=v_rez3;
    raise notice 'R7  FAIL  onaylandi->cikis_yapildi gecti'; v_fail:=v_fail+1;
  exception when others then
    raise notice 'R7  OK    gecersiz rezervasyon gecisi reddedildi (%)', sqlstate; v_ok:=v_ok+1;
  end;

  -- ==================================================================
  -- R8  CIFT REZERVASYON: cakisan atama REDDEDILIR, BITISIK atama GECER
  -- `pms_oda_atamalari_cakisma` GiST dislama kisiti (aktif atamalarda).
  -- ==================================================================
  insert into public.pms_odalar (otel_id, oda_tipi_id, oda_no)
  values ('810', v_tip, 'R103') returning id into v_oda3;

  insert into public.pms_oda_atamalari (otel_id, rezervasyon_id, oda_id, baslangic, bitis, aktif)
  values ('810', v_rez3, v_oda3, public.pms_bugun()+10, public.pms_bugun()+12, true);

  begin
    -- [10,12) ile [11,13) CAKISIR
    insert into public.pms_oda_atamalari (otel_id, rezervasyon_id, oda_id, baslangic, bitis, aktif)
    values ('810', v_rez3, v_oda3, public.pms_bugun()+11, public.pms_bugun()+13, true);
    raise notice 'R8a FAIL  cakisan atama kabul edildi'; v_fail:=v_fail+1;
  exception when others then
    if sqlstate = '23P01' then
      raise notice 'R8a OK    cakisan atama dislama kisitiyla reddedildi'; v_ok:=v_ok+1;
    else
      raise notice 'R8a FAIL  beklenen 23P01, gelen % (%)', sqlstate, sqlerrm; v_fail:=v_fail+1;
    end if;
  end;

  begin
    -- [12,14) BITISIK: yarim acik aralik, cakisma YOK
    insert into public.pms_oda_atamalari (otel_id, rezervasyon_id, oda_id, baslangic, bitis, aktif)
    values ('810', v_rez3, v_oda3, public.pms_bugun()+12, public.pms_bugun()+14, true);
    raise notice 'R8b OK    bitisik atama kabul edildi (yarim acik aralik)'; v_ok:=v_ok+1;
  exception when others then
    raise notice 'R8b FAIL  bitisik atama reddedildi: %', sqlerrm; v_fail:=v_fail+1;
  end;

  -- ==================================================================
  -- R9  IPTAL/GELMEDI atamayi SERBEST birakir
  -- ==================================================================
  begin
    update public.pms_rezervasyonlar set durum='iptal' where id=v_rez3;
    select count(*) into v_n from public.pms_oda_atamalari
     where rezervasyon_id=v_rez3 and aktif;
    if v_n = 0 then
      raise notice 'R9  OK    iptal tum aktif atamalari serbest birakti'; v_ok:=v_ok+1;
    else raise notice 'R9  FAIL  % aktif atama kaldi', v_n; v_fail:=v_fail+1; end if;
  exception when others then
    raise notice 'R9  FAIL  %', sqlerrm; v_fail:=v_fail+1;
  end;

  -- ==================================================================
  -- R10 FOLYO otomatik aciliyor (onaylandi rezervasyonda)
  -- ==================================================================
  select id into v_folio from public.pms_folyolar where rezervasyon_id=v_rez limit 1;
  if v_folio is not null then
    raise notice 'R10 OK    folyo otomatik acildi'; v_ok:=v_ok+1;
  else
    raise notice 'R10 FAIL  rezervasyon icin folyo yok'; v_fail:=v_fail+1;
  end if;

  -- ==================================================================
  -- R11 MALI KAYIT EKLE-ONLY: folyo hareketi guncellenemez/silinemez
  -- ==================================================================
  insert into public.pms_folio_hareketleri
    (otel_id, folio_id, tarih, tip, aciklama, tutar)
  values ('810', v_folio, public.pms_bugun(), 'ekstra', 'regresyon kalemi', 50)
  returning id into v_hareket;

  begin
    update public.pms_folio_hareketleri set tutar = 999 where id=v_hareket;
    raise notice 'R11a FAIL  mali kayit guncellendi'; v_fail:=v_fail+1;
  exception when others then
    raise notice 'R11a OK    mali kayit guncellemesi reddedildi'; v_ok:=v_ok+1;
  end;

  begin
    delete from public.pms_folio_hareketleri where id=v_hareket;
    raise notice 'R11b FAIL  mali kayit silindi'; v_fail:=v_fail+1;
  exception when others then
    raise notice 'R11b OK    mali kayit silinmesi reddedildi'; v_ok:=v_ok+1;
  end;

  -- ==================================================================
  -- R12 BAR -> FOLYO KOPRUSU hala calisiyor (DAVRANISSAL)
  -- Katalog kontrolu degil: gercek bir siparis teslim edilir ve folyoda
  -- `bar` hareketi olusup olusmadigi olculur.
  -- ==================================================================
  -- Kopru SUREN konaklama ve ACIK folyo sart kosar (bu da Faz 1 korumasidir).
  -- Bu yuzden once temiz bir odaya gercek bir check-in yapilir.
  insert into public.pms_odalar (otel_id, oda_tipi_id, oda_no)
  values ('810', v_tip, 'R104') returning id into v_oda4;
  update public.pms_odalar set temizlik_durumu='temiz' where id=v_oda4;

  insert into public.pms_rezervasyonlar
    (otel_id, misafir_id, oda_tipi_id, giris_tarihi, cikis_tarihi, yetiskin_sayisi, durum, gecelik_fiyat)
  values ('810', v_misafir, v_tip, public.pms_bugun(), public.pms_bugun()+1, 1, 'onaylandi', 1000)
  returning id into v_rez4;

  execute 'set local role authenticated';
  perform public.pms_check_in(v_rez4, v_oda4);
  execute 'reset role';

  select id into v_folio4 from public.pms_folyolar where rezervasyon_id=v_rez4 limit 1;

  begin
    insert into public.menu_urunler (ad, kategori, otel_id, fiyat, aktif, ucretli, tip)
    values ('R12 Test Icecek','bar','810', 120, true, true, 'direkt')
    returning id into v_menu;

    insert into public.bar_siparisleri (otel_id, depo_id, oda_no, durum)
    values ('810', 'BAR', 'R104', 'yeni') returning id into v_siparis;

    insert into public.bar_siparis_kalemleri (siparis_id, menu_urun_id, adet)
    values (v_siparis, v_menu, 2);

    select count(*) into v_n from public.pms_folio_hareketleri
     where folio_id=v_folio4 and tip='bar';

    update public.bar_siparisleri set durum='teslim_edildi' where id=v_siparis;

    select count(*) into v_n2 from public.pms_folio_hareketleri
     where folio_id=v_folio4 and tip='bar';

    if v_n2 > v_n then
      raise notice 'R12 OK    bar->folyo koprusu calisiyor (% -> % hareket)', v_n, v_n2;
      v_ok:=v_ok+1;
    else
      raise notice 'R12 FAIL  teslimden sonra folyoya bar hareketi dusmedi (%)', v_n2;
      v_fail:=v_fail+1;
    end if;
  exception when others then
    raise notice 'R12 FAIL  %', sqlerrm; v_fail:=v_fail+1;
  end;

  raise notice '--------------------------------------------------';
  raise notice 'FAZ 1 REGRESYON: % OK / % FAIL', v_ok, v_fail;
  if v_fail > 0 then
    raise exception 'FAZ 1 REGRESYON BASARISIZ: % test', v_fail;
  end if;
end;
$$;

rollback;
