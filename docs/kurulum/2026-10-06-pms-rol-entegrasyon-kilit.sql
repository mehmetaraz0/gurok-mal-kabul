-- ===========================================================================
-- MY-4 — On Buro rolleriyle rezervasyon / check-in / check-out (ileri yonlu)
-- ===========================================================================
-- Kapsam: docs/inceleme/PMS-MY4-ROL-ENTEGRASYON-KAPSAMI.md
-- Inceleme sartlari: 2026-10-06-4ca95db-PMS-regresyon-ve-MY4-inceleme.md
--
-- SORUN (olculdu): RLS'te `FOR UPDATE` satirin UPDATE politikasini da ister.
-- Onayli matris personele oda/oda tipi icin yalniz `goruntule` verdigi icin
-- rezervasyon kontrol tetikleyicisi, check-in ve check-out ayni hedefte
-- SELECT 1 satir / FOR UPDATE 0 satir ile kiriliyordu.
--
-- COZUM: rollere GENEL oda/oda tipi duzenleme hakki VERILMEZ. Bunun yerine
-- is isleminin TAMAMI (tetikleyici ve iki RPC) tanimlayici haklariyla kosar;
-- atlanan RLS kontrolleri fonksiyonlarin ICINDE acikca yeniden uygulanir.
--
--   MY4-T2: kilit hedefi NEW'den gelir; INSERT'te satir henuz tabloda olmadigi
--           ve oda tipi degisen UPDATE'te yeni hedef gerektigi icin yeniden
--           SELECT yapilmaz. Oda tipi-otel eslesmesi ve kapasite AYNEN korunur.
--   MY4-T3: oda durumunu TEK BASINA yazan dis yardimci YOKTUR. Yazma, tam
--           gecisi tek islemde yapan `pms_check_in`/`pms_check_out` icinde
--           kalir; boylece yarim durum uretilemez ve mevcut tutarlilik
--           tetikleyicileri gevsetilmez.
--
-- YETKI GENISLEMESI YOK: hicbir role yeni satir/ayricalik eklenmez. Vardiyanin
-- mevcut `pms_oda=kayit` hakki korunur; personelin `goruntule` hakki artmaz.
-- Fonksiyon govdeleri 2026-09-06 migration'larindan BIREBIR alinmistir; tek
-- fark SECURITY DEFINER ve yukaridaki acik kapilardir.
-- ===========================================================================

begin;

do $guard$
begin
  if to_regprocedure('public.auth_otel_erisim(text)') is null
     or to_regprocedure('public.auth_yetki_var(text, text)') is null then
    raise exception 'auth yardimcilari yok: yetki katmani kurulmamis';
  end if;
end $guard$;

-- ---------------------------------------------------------------------------
-- Dar kilit yardimcisi: YALNIZ kilit alir, hicbir satiri DEGISTIRMEZ.
-- MY4-T2: hedef cagirandan (INSERT/UPDATE'in NEW degerlerinden) gelir; yardimci
-- yetkiyi ve oda tipi-otel eslesmesini KENDI ICINDE dogrular.
-- MY4-T3: satir yazmadigi icin yarim durum uretemez; dogrudan cagrilsa bile
-- en fazla bir kilit alir ve islem sonunda birakilir.
-- ---------------------------------------------------------------------------
create or replace function public.pms_oda_tipi_kilitle(
  p_oda_tipi_id uuid, p_otel_id public.otel_id)
returns public.pms_oda_tipleri
language plpgsql security definer
set search_path = pg_catalog, public, pg_temp as $fn$
declare v_tip public.pms_oda_tipleri;
begin
  if public.auth_yetki_var('pms_rezervasyon','kayit') is not true then
    raise exception 'Oda tipi kilidi icin rezervasyon kayit yetkisi gerekli'
      using errcode = '42501';
  end if;
  if public.auth_otel_erisim(p_otel_id::text) is not true then
    raise exception 'Oda tipi baska otele ait (otel: %)', p_otel_id
      using errcode = '42501';
  end if;
  select * into v_tip from public.pms_oda_tipleri
   where id = p_oda_tipi_id and otel_id = p_otel_id
   for update;
  if not found then
    raise exception 'Oda tipi bulunamadi veya baska otele ait';
  end if;
  return v_tip;
end;
$fn$;

revoke all on function public.pms_oda_tipi_kilitle(uuid, public.otel_id) from public, anon;
grant execute on function public.pms_oda_tipi_kilitle(uuid, public.otel_id) to authenticated;

create or replace function public.pms_rezervasyon_kontrol()
returns trigger language plpgsql
-- MY-4: tanimlayici haklariyla kosar. Gerekcesi: kilit ve dar guncelleme
-- icin RLS UPDATE politikasini gecmek gerekiyor; alternatifi rollere genel
-- oda/oda tipi duzenleme hakki vermekti. Atlanan RLS kontrolleri ASAGIDA
-- ACIKCA yeniden uygulanir.
security definer
set search_path = pg_catalog, public, pg_temp
set search_path = pg_catalog, public, pg_temp as $$
declare
  v_tip      record;
  v_oda      bigint;
  v_dolu     bigint;
begin
  -- MY-4 ACIK KAPI (RLS yerine): hedef NEW satirindan gelir.
  if public.auth_yetki_var('pms_rezervasyon','kayit') is not true then
    raise exception 'Rezervasyon icin kayit yetkisi gerekli'
      using errcode = '42501';
  end if;
  if public.auth_otel_erisim(new.otel_id::text) is not true then
    raise exception 'Rezervasyon baska otele ait (otel: %)', new.otel_id
      using errcode = '42501';
  end if;
  -- Envanter tutan durumlar. 'taslak' TUTMAZ (bilincli karar).
  if new.durum not in ('onaylandi','giris_yapildi','cikis_yapildi') then
    return new;
  end if;

  -- Tip satirini KILITLE. Bu satir, bu tipin envanterinin serilestirme
  -- noktasidir; kilit transaction sonuna kadar durur.
  select * into v_tip from public.pms_oda_tipleri
   where id = new.oda_tipi_id and otel_id = new.otel_id
   for update;
  if not found then
    raise exception 'Oda tipi bulunamadi veya baska otele ait';
  end if;

  -- Kapasite: kisi sayisi tipin sinirini asamaz.
  if new.yetiskin_sayisi + new.cocuk_sayisi > v_tip.azami_kisi then
    raise exception 'Kisi sayisi oda tipi kapasitesini asiyor (% > %)',
      new.yetiskin_sayisi + new.cocuk_sayisi, v_tip.azami_kisi;
  end if;
  if new.yetiskin_sayisi > v_tip.azami_yetiskin then
    raise exception 'Yetiskin sayisi oda tipi sinirini asiyor (% > %)',
      new.yetiskin_sayisi, v_tip.azami_yetiskin;
  end if;
  if new.cocuk_sayisi > v_tip.azami_cocuk then
    raise exception 'Cocuk sayisi oda tipi sinirini asiyor (% > %)',
      new.cocuk_sayisi, v_tip.azami_cocuk;
  end if;

  -- Envanter: bu tipteki AKTIF oda sayisi.
  -- NOT: oda durumu (ariza/bloke) BUGUNUN durumudur; gelecek tarihli musaitlik
  -- icin tarih arali'kli oda blogu gerekir ve o ayri bir adimdir.
  select count(*) into v_oda from public.pms_odalar
   where otel_id = new.otel_id and oda_tipi_id = new.oda_tipi_id and aktif;

  -- Cakisan aktif rezervasyonlar (kendisi haric).
  select count(*) into v_dolu from public.pms_rezervasyonlar r
   where r.otel_id = new.otel_id
     and r.oda_tipi_id = new.oda_tipi_id
     and r.durum in ('onaylandi','giris_yapildi','cikis_yapildi')
     and r.id <> new.id
     and r.konaklama && daterange(new.giris_tarihi, new.cikis_tarihi, '[)');

  if v_dolu >= v_oda then
    raise exception 'Asiri satis: % tipinde % oda var, secilen tarihlerde % rezervasyon dolu',
      v_tip.kod, v_oda, v_dolu;
  end if;

  return new;
end;
$$;

create or replace function public.pms_check_in(
  p_rezervasyon_id uuid,
  p_oda_id         uuid default null
)
returns uuid
language plpgsql
-- MY-4: tanimlayici haklariyla kosar. Gerekcesi: kilit ve dar guncelleme
-- icin RLS UPDATE politikasini gecmek gerekiyor; alternatifi rollere genel
-- oda/oda tipi duzenleme hakki vermekti. Atlanan RLS kontrolleri ASAGIDA
-- ACIKCA yeniden uygulanir.
security definer
set search_path = pg_catalog, public, pg_temp
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_rez     public.pms_rezervasyonlar%rowtype;
  v_oda     public.pms_odalar%rowtype;
  v_atama   public.pms_oda_atamalari%rowtype;
  v_bugun   date;
  v_kirpik  uuid;
begin
  if public.auth_yetki_var('pms_rezervasyon','kayit') is not true then
    raise exception 'Check-in icin rezervasyon kayit yetkisi gerekli';
  end if;

  -- Kilit sırası 1: rezervasyon. RLS bulunamayan satırı zaten gizler.
  select * into v_rez
    from public.pms_rezervasyonlar
   where id = p_rezervasyon_id
   for update;
  if not found then
    raise exception 'Rezervasyon bulunamadi veya erisim yok';
  end if;
  -- MY-4 ACIK KAPI (RLS yerine): otel kapsami burada yeniden dogrulanir.
  if public.auth_otel_erisim(v_rez.otel_id::text) is not true then
    raise exception 'Rezervasyon baska otele ait (otel: %)', v_rez.otel_id
      using errcode = '42501';
  end if;

  v_bugun := public.pms_bugun(v_rez.otel_id);

  if v_rez.durum <> 'onaylandi' then
    raise exception 'Check-in yalniz onaylandi rezervasyonuna yapilir (durum: %)', v_rez.durum;
  end if;
  if v_bugun < v_rez.giris_tarihi then
    raise exception 'Rezervasyon giris tarihi bugunden ileride (%)', v_rez.giris_tarihi;
  end if;
  if v_bugun >= v_rez.cikis_tarihi then
    raise exception 'Rezervasyon cikis tarihi gecti (%)', v_rez.cikis_tarihi;
  end if;

  -- Ara hâlleri yazabilmek için tutarlılık denetimlerini commit'e bırak.
  set constraints pms_tutarlilik_oda, pms_tutarlilik_rezervasyon,
                  pms_tutarlilik_atama deferred;

  -- Kilit sırası 2: mevcut güncel atama varsa onu kilitle ve odayı ondan al.
  select * into v_atama
    from public.pms_oda_atamalari a
   where a.rezervasyon_id = v_rez.id and a.otel_id = v_rez.otel_id and a.aktif
     and a.bitis >= v_bugun
   order by a.id
   for update;
  if found then
    v_kirpik := v_atama.oda_id;
    if p_oda_id is not null and p_oda_id <> v_kirpik then
      raise exception 'Rezervasyona bagli baska oda atamasi var; oda secilemez';
    end if;
  else
    if p_oda_id is null then
      raise exception 'Oda secilmedi: rezervasyona bagli guncel oda atamasi yok';
    end if;
    v_kirpik := p_oda_id;
  end if;

  -- Kilit sırası 3: oda. Kilit altında şartları YENİDEN doğrula.
  select * into v_oda
    from public.pms_odalar
   where id = v_kirpik and otel_id = v_rez.otel_id
   for update;
  if not found then
    raise exception 'Oda bulunamadi veya baska otele ait';
  end if;
  if not v_oda.aktif then
    raise exception 'Pasif odaya check-in yapilamaz (oda %)', v_oda.oda_no;
  end if;
  if v_oda.kullanim_durumu <> 'bos' then
    raise exception 'Oda % bos degil (durum: %), check-in reddedildi',
      v_oda.oda_no, v_oda.kullanim_durumu;
  end if;
  if v_oda.temizlik_durumu not in ('temiz','kontrol_edildi') then
    raise exception 'Oda % kirli/temizleniyor, check-in reddedildi (temizlik: %)',
      v_oda.oda_no, v_oda.temizlik_durumu;
  end if;

  -- Güncel atama yoksa tam konaklama aralığına atama aç; çakışma exclusion
  -- kisitiyla veritabanınca reddedilir.
  if v_atama.id is null then
    insert into public.pms_oda_atamalari (otel_id, rezervasyon_id, oda_id,
                                          baslangic, bitis)
    values (v_rez.otel_id, v_rez.id, v_oda.id, v_rez.giris_tarihi, v_rez.cikis_tarihi);
  end if;

  update public.pms_odalar
     set kullanim_durumu = 'dolu'
   where id = v_oda.id;

  update public.pms_rezervasyonlar
     set durum = 'giris_yapildi',
         giris_zamani = now(),
         giris_yapan  = auth.uid()
   where id = v_rez.id;

  return v_oda.id;
end;
$$;

create or replace function public.pms_check_out(p_rezervasyon_id uuid)
returns uuid
language plpgsql
-- MY-4: tanimlayici haklariyla kosar. Gerekcesi: kilit ve dar guncelleme
-- icin RLS UPDATE politikasini gecmek gerekiyor; alternatifi rollere genel
-- oda/oda tipi duzenleme hakki vermekti. Atlanan RLS kontrolleri ASAGIDA
-- ACIKCA yeniden uygulanir.
security definer
set search_path = pg_catalog, public, pg_temp
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_rez    public.pms_rezervasyonlar%rowtype;
  v_oda    public.pms_odalar%rowtype;
  v_oda_id uuid;
  v_sayi   int := 0;
begin
  if public.auth_yetki_var('pms_rezervasyon','kayit') is not true then
    raise exception 'Check-out icin rezervasyon kayit yetkisi gerekli';
  end if;

  -- Kilit sırası 1: rezervasyon.
  select * into v_rez
    from public.pms_rezervasyonlar
   where id = p_rezervasyon_id
   for update;
  if not found then
    raise exception 'Rezervasyon bulunamadi veya erisim yok';
  end if;
  -- MY-4 ACIK KAPI (RLS yerine): otel kapsami burada yeniden dogrulanir.
  if public.auth_otel_erisim(v_rez.otel_id::text) is not true then
    raise exception 'Rezervasyon baska otele ait (otel: %)', v_rez.otel_id
      using errcode = '42501';
  end if;

  if v_rez.durum <> 'giris_yapildi' then
    raise exception 'Check-out yalniz giris_yapildi rezervasyonuna yapilir (durum: %)',
      v_rez.durum;
  end if;

  set constraints pms_tutarlilik_oda, pms_tutarlilik_rezervasyon,
                  pms_tutarlilik_atama deferred;

  -- Kilit sırası 2: rezervasyonun AKTİF konaklama ataması.
  -- "Bugünü kapsıyor mu" ŞARTI YOK: planlanan çıkış tarihi geçmiş olsa bile
  -- (resepsiyon çıkışı unuttu) atama bu rezervasyonun güncel konaklama
  -- kaydıdır ve çıkış yapılabilir. cikis_zamani gerçek işlem anını taşır;
  -- planlanan stay aralığı SESSİZCE DEĞİŞTİRİLMEZ; atama geçmiş kayıt
  -- olarak aktif kalır.
  select a.oda_id into v_oda_id
    from public.pms_oda_atamalari a
   where a.rezervasyon_id = v_rez.id and a.otel_id = v_rez.otel_id and a.aktif
   order by a.oda_id
   limit 1
   for update;
  if not found then
    raise exception 'Aktif oda atamasi yok; tutarsiz durum, cikis reddedildi';
  end if;

  -- Kilit altında yeniden doğrula: checked-in rezervasyonun TAM BİR aktif
  -- ataması olmalı. 0 ve >1, veri bozulmasıdır; sessizce ilki SEÇİLMEZ.
  -- (Kilit, bu sayım ile ilk kontrol arasına giren değişiklikleri de yakalar.)
  select count(*) into v_sayi
    from public.pms_oda_atamalari a
   where a.rezervasyon_id = v_rez.id and a.otel_id = v_rez.otel_id and a.aktif;
  if v_sayi <> 1 then
    raise exception 'Check-in rezervasyonun % aktif oda atamasi var; tutarsiz durum (1 bekleniyordu)',
      v_sayi;
  end if;

  -- Kilit sırası 3: oda; kilit altında durumu yeniden doğrula.
  select * into v_oda
    from public.pms_odalar
   where id = v_oda_id and otel_id = v_rez.otel_id
   for update;
  if not found then
    raise exception 'Atamadaki oda bulunamadi (oda_id: %)', v_oda_id;
  end if;
  if v_oda.kullanim_durumu <> 'dolu' then
    raise exception 'Oda % dolu degil (durum: %), tutarsiz durum',
      v_oda.oda_no, v_oda.kullanim_durumu;
  end if;
  update public.pms_odalar
     set kullanim_durumu = 'bos',
         temizlik_durumu = 'kirli'
   where id = v_oda.id;

  update public.pms_rezervasyonlar
     set durum = 'cikis_yapildi',
         cikis_zamani = now(),
         cikis_yapan  = auth.uid()
   where id = v_rez.id;

  return v_rez.id;
end;
$$;

-- --- Olcum: yetki genislemesi OLMADIGI ve kapilarin yerinde oldugu ---------
do $olcum$
declare v_hata text := ''; v_liste text;
begin
  foreach v_liste in array array['pms_rezervasyon_kontrol','pms_check_in',
                                 'pms_check_out','pms_oda_tipi_kilitle'] loop
    if not exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                    where n.nspname='public' and p.proname=v_liste and p.prosecdef) then
      v_hata := v_hata || v_liste || ': SECURITY DEFINER degil; ';
    end if;
  end loop;
  -- Oda durumunu tek basina yazan dis yardimci OLMAMALI (MY4-T3).
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
              where n.nspname='public' and p.proname = 'pms_oda_konaklama_isaretle') then
    v_hata := v_hata || 'pms_oda_konaklama_isaretle VAR (MY4-T3 ihlali); ';
  end if;
  if v_hata <> '' then
    raise exception 'MY-4 OLCUMU BASARISIZ: %', v_hata using errcode = '23514';
  end if;

  select string_agg(r.kod || '=' || ym.yetki::text, ', ' order by r.kod) into v_liste
  from public.yetki_matrisi ym
  join public.roller r on r.id = ym.rol_id
  join public.moduller m on m.id = ym.modul_id
  where m.kod in ('pms_oda','pms_oda_tipi')
    and r.kod in ('onburo_personel','onburo_vardiya','onburo_sef');
  raise notice 'ENVANTER — oda/oda tipi yetkileri DEGISMEDI: %', coalesce(v_liste,'(hic)');
  raise notice 'MY-4 kuruldu: genel yetki genislemesi YOK; yazma yalniz tam gecis icinde.';
end $olcum$;

commit;
