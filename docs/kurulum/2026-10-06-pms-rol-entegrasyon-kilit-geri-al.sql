-- ===========================================================================
-- MY-4 GERI ALMA — rol entegrasyon kilidi (2026-10-06) kaldirilir
-- ===========================================================================
-- Ileri yonlu dosya: 2026-10-06-pms-rol-entegrasyon-kilit.sql
--
-- NE YAPAR: uc fonksiyonu (pms_rezervasyon_kontrol, pms_check_in,
-- pms_check_out) 2026-09-06 Faz 1 migration dosyalarindaki BIREBIR
-- govdelerine dondurur ve dar kilit yardimcisini (pms_oda_tipi_kilitle)
-- dusurur. Govdeler bu dosyaya ELLE YAZILMADI; Faz 1 dosyalarindan satir
-- araligiyla cikarildi (adim2: 357-414, adim3: 494-597 ve 600-684) ve
-- cikarma sirasinda "security definer icermiyor" diye olculdu.
--
-- NE YAPMAZ: hicbir role yetki vermez/almaz, tabloya, politikaya veya
-- tetikleyiciye dokunmaz, veri silmez. Mali yetki ayrimi ve modul
-- tohumlamasi ETKILENMEZ; bu dosya onlardan BAGIMSIZDIR.
--
-- BEDELI (olculdu, kabul edilmesi gerekir): kilit kalkinca MY-4 belirtisi
-- geri doner. pms_oda / pms_oda_tipi icin yalniz goruntule hakki olan
-- roller rezervasyon, check-in ve check-out yapamaz, cunku RLS icinde
-- FOR UPDATE satirin UPDATE politikasini da ister. Yani bu geri alma On
-- Buro akisini KAPATIR; sessiz bir iyilestirme degildir.
-- Olay aninda tercih sirasi: (1) modul aktif=false ile ozellik kapatma,
-- (2) bu dosya, (3) yedekten donus.
--
-- CALISTIRMA: dosyanin tamamini oldugu gibi verin (psql -f, psql < dosya
-- veya SQL Editor). Kendi islemini acar; disaridan sarmaya gerek yoktur.
-- ===========================================================================

begin;

do $guard$
begin
  if to_regprocedure('public.pms_check_in(uuid, uuid)') is null
     or to_regprocedure('public.pms_check_out(uuid)') is null
     or to_regproc('public.pms_rezervasyon_kontrol') is null then
    raise exception 'PMS Faz 1 fonksiyonlari yok: geri alinacak bir sey yok';
  end if;
end $guard$;

-- ---------------------------------------------------------------------------
-- 1) Rezervasyon kontrol tetikleyici fonksiyonu — Faz 1 Adim 2 govdesi
-- ---------------------------------------------------------------------------
create or replace function public.pms_rezervasyon_kontrol()
returns trigger language plpgsql
set search_path = pg_catalog, public, pg_temp as $$
declare
  v_tip      record;
  v_oda      bigint;
  v_dolu     bigint;
begin
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

-- ---------------------------------------------------------------------------
-- 2) CHECK-IN — Faz 1 Adim 3 govdesi
-- ---------------------------------------------------------------------------
create or replace function public.pms_check_in(
  p_rezervasyon_id uuid,
  p_oda_id         uuid default null
)
returns uuid
language plpgsql
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

-- ---------------------------------------------------------------------------
-- 3) CHECK-OUT — Faz 1 Adim 3 govdesi
-- ---------------------------------------------------------------------------
create or replace function public.pms_check_out(p_rezervasyon_id uuid)
returns uuid
language plpgsql
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

-- Faz 1 ACL si acikca yeniden kurulur ki geri alma sonrasi durum
-- tereddutsuz olsun (govde degisimi ACL yi dusurmez).
revoke execute on function public.pms_check_in(uuid, uuid) from public, anon;
revoke execute on function public.pms_check_out(uuid)        from public, anon;
grant  execute on function public.pms_check_in(uuid, uuid) to authenticated, service_role;
grant  execute on function public.pms_check_out(uuid)        to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4) Dar kilit yardimcisi dusurulur
-- ---------------------------------------------------------------------------
drop function if exists public.pms_oda_tipi_kilitle(uuid, public.otel_id);

-- ---------------------------------------------------------------------------
-- 5) DOGRULAMA — commit oncesi; tek sapmada islem geri alinir
-- ---------------------------------------------------------------------------
do $dogrula$
declare
  v_definer text;
  v_pinsiz  text;
begin
  select string_agg(p.proname, ', ' order by p.proname) into v_definer
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname in ('pms_rezervasyon_kontrol','pms_check_in','pms_check_out')
     and p.prosecdef;
  if v_definer is not null then
    raise exception 'G1: hala SECURITY DEFINER: %', v_definer;
  end if;

  if to_regprocedure('public.pms_oda_tipi_kilitle(uuid, public.otel_id)') is not null then
    raise exception 'G2: dar kilit yardimcisi hala var';
  end if;

  -- Faz 1 govdeleri search_path pinlidir; pinsiz kalmadigi olculur.
  select string_agg(p.proname, ', ' order by p.proname) into v_pinsiz
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname in ('pms_rezervasyon_kontrol','pms_check_in','pms_check_out')
     and not exists (select 1 from unnest(coalesce(p.proconfig, '{}'::text[])) c
                      where c like 'search\_path=%');
  if v_pinsiz is not null then
    raise exception 'G3: search_path pinsiz: %', v_pinsiz;
  end if;

  if not exists (select 1 from pg_trigger t join pg_class c on c.oid = t.tgrelid
                  where c.relname = 'pms_rezervasyonlar'
                    and t.tgname  = 'pms_rezervasyon_kontrol' and not t.tgisinternal) then
    raise exception 'G4: pms_rezervasyon_kontrol tetikleyicisi yok';
  end if;

  raise notice 'GERI ALMA: G1-G4 gecti. Uc fonksiyon invoker, kilit yardimcisi dusuruldu, tetikleyici yerinde.';
end $dogrula$;

commit;
