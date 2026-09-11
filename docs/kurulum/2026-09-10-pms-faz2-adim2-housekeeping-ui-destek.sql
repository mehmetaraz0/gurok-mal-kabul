-- ============================================================================
-- PMS FAZ 2 / ADIM 2 — KAT HİZMETLERİ ARAYÜZ DESTEK SÖZLEŞMESİ
-- ----------------------------------------------------------------------------
-- İLERİ YÖNLÜ migration. 2026-09-09 tarihli onaylı kat hizmetleri
-- migration'ı DEĞİŞTİRİLMEZ; release geçmişi yeniden yazılmaz.
--
-- NEDEN (iki ÖLÇÜLMÜŞ boşluk, ikisi de arayüz incelemesinde kanıtlandı):
--
-- 1) "İŞLERİM" EKSİK LİSTELİYOR.
--    `pms_housekeeping_listele` sonucu 100 satırla sınırlıdır ve sıralama
--    `oncelik, hedef_zamani, olusturma_tarihi, id` üzerinedir. Otelde
--    100'den çok bitmemiş görev varsa, çalışanın KENDİ görevi ilk sayfanın
--    dışında kalabilir ve arayüzdeki istemci süzgeci onu HİÇ göremez.
--    ÖLÇÜM: 116 bitmemiş görev, düşük öncelikli atanmış görev -> İşlerim 0.
--    Bu bir gösterim kusuru değil, SÖZLEŞME boşluğudur: "bana atananlar"
--    sunucuda süzülmelidir.
--    ÇÖZÜM: `p_kuyruk = 'benim'`. Kullanıcı kimliği İSTEMCİDEN ALINMAZ;
--    `phase0_private.hk_aktor()` ile kimliği doğrulanmış çağırandan
--    TÜRETİLİR. Yeni genel fonksiyon eklenmez, imza değişmez.
--
-- 2) ODA SEÇİCİ ÇIKMAZI.
--    `pms_housekeeping = tam` yetkisi olan bir yönetici görev AÇABİLİR,
--    ama oda listesini okumak `pms_oda` modül yetkisi ister
--    (`pms_odalar_select` politikası). Kat hizmetleri yetkisi olan ama oda
--    yönetimi yetkisi olmayan yönetici için oda seçici BOŞ gelir.
--    ÖLÇÜM: görünen oda sayısı 0, buna karşın görev açma BAŞARILI.
--    ÇÖZÜM: dar, operasyonel, SINIRLI bir oda izdüşümü RPC'si.
--    Yetki eşiği görev açmanın eşiğiyle AYNIDIR (`tam`) — hiçbir yeni
--    erişim açılmaz. Misafir/rezervasyon verisi DÖNMEZ.
--
-- UYGULAMA NOTU: modül üretimde KAPALIDIR ve bu migration onu AÇMAZ.
-- ============================================================================

\set ON_ERROR_STOP on

-- ---------------------------------------------------------------------------
-- 0) ÖN KOŞULLAR
-- ---------------------------------------------------------------------------
do $$
begin
  if to_regclass('public.pms_housekeeping_gorevleri') is null then
    raise exception 'ON KOSUL: kat hizmetleri gorev tablosu yok. Once 2026-09-09 migration uygulanmali.';
  end if;
  if to_regprocedure('phase0_private.hk_aktor()') is null then
    raise exception 'ON KOSUL: phase0_private.hk_aktor() yok.';
  end if;
  if to_regprocedure('public.pms_housekeeping_listele(text,text,integer)') is null then
    raise exception 'ON KOSUL: pms_housekeeping_listele(text,text,int) yok.';
  end if;
end $$;

begin;

-- ---------------------------------------------------------------------------
-- 1) LİSTELEME: `benim` kuyruğu
-- ---------------------------------------------------------------------------
-- Kuyruk adı artık DENETLENİR. Önceki sürümde bilinmeyen bir kuyruk sessizce
-- `tumu` gibi davranıyordu; yazım hatası tüm oteli listeleyebilirdi. Artık
-- yalnız bilinen dört değer kabul edilir.
create or replace function public.pms_housekeeping_listele(
  p_otel text, p_kuyruk text default 'tumu', p_limit int default 50)
returns table (
  gorev_id uuid, oda_id uuid, oda_no text, kat text,
  gorev_tipi text, durum text, oncelik smallint,
  atanan_kullanici_id uuid, hedef_zamani timestamptz,
  olusturma_tarihi timestamptz, surum bigint,
  oda_kullanim public.pms_kullanim_durumu, oda_temizlik public.pms_temizlik_durumu,
  guncel_dongu boolean, sunucu_zamani timestamptz)
language plpgsql stable security definer
set search_path = pg_catalog, public, pg_temp as $fn$
declare
  v_otel public.otel_id;
  a public.kullanicilar;
begin
  -- Aktör: kimliği doğrulanmış ÇAĞIRAN. İstemciden kullanıcı kimliği
  -- ASLA alınmaz; "bana atananlar" bu satırdan türetilir.
  a := phase0_private.hk_aktor();

  if public.auth_yetki_var('pms_housekeeping','goruntule') is not true
     or public.auth_otel_erisim(p_otel) is not true then
    raise exception 'Yetki yok' using errcode = '42501';
  end if;
  if p_kuyruk is null or p_kuyruk not in ('tumu','bitmemis','kontrol','benim') then
    raise exception 'Bilinmeyen kuyruk: %', coalesce(p_kuyruk,'(null)') using errcode = '22023';
  end if;
  v_otel := p_otel::public.otel_id;

  return query
    select g.id, g.oda_id, o.oda_no, o.kat,
           g.gorev_tipi, g.durum, g.oncelik,
           g.atanan_kullanici_id, g.hedef_zamani,
           g.olusturma_tarihi, g.surum,
           o.kullanim_durumu, o.temizlik_durumu,
           (o.temizlik_gorevi_id = g.id),
           clock_timestamp()
      from public.pms_housekeeping_gorevleri g
      join public.pms_odalar o on o.id = g.oda_id and o.otel_id = g.otel_id
     where g.otel_id = v_otel
       and case p_kuyruk
             when 'bitmemis' then g.durum in ('bekliyor','temizleniyor')
             when 'kontrol'  then g.durum = 'tamamlandi' and o.temizlik_gorevi_id = g.id
             -- SUNUCU TARAFI "İşlerim": sayfalama penceresi artık çalışanın
             -- kendi işini gizleyemez.
             when 'benim'    then g.durum in ('bekliyor','temizleniyor')
                                  and g.atanan_kullanici_id = a.id
             else true
           end
     order by g.oncelik, g.hedef_zamani nulls last, g.olusturma_tarihi, g.id
     limit least(greatest(coalesce(p_limit, 50), 1), 100);
end;
$fn$;

-- ---------------------------------------------------------------------------
-- 2) ODA SEÇİCİ: dar operasyonel izdüşüm
-- ---------------------------------------------------------------------------
-- SINIRLIDIR (en çok 500 satır), OTEL KAPSAMLIDIR ve yalnız görev açmaya
-- yetkili çağıran okuyabilir. Misafir adı, telefon, rezervasyon, folyo ya da
-- fiyat DÖNMEZ — bu alanlar sorguya HİÇ girmez.
create or replace function public.pms_housekeeping_odalar(
  p_otel text, p_limit int default 200)
returns table (
  oda_id uuid, oda_no text, kat text, blok text,
  kullanim_durumu public.pms_kullanim_durumu,
  temizlik_durumu public.pms_temizlik_durumu,
  acik_gorev_id uuid)
language plpgsql stable security definer
set search_path = pg_catalog, public, pg_temp as $fn$
declare v_otel public.otel_id;
begin
  perform phase0_private.hk_aktor();
  -- Eşik görev AÇMA eşiğiyle AYNI: yeni bir erişim yüzeyi açılmaz.
  if public.auth_yetki_var('pms_housekeeping','tam') is not true
     or public.auth_otel_erisim(p_otel) is not true then
    raise exception 'Yetki yok' using errcode = '42501';
  end if;
  v_otel := p_otel::public.otel_id;

  return query
    select o.id, o.oda_no, o.kat, o.blok,
           o.kullanim_durumu, o.temizlik_durumu,
           g.id
      from public.pms_odalar o
      left join public.pms_housekeeping_gorevleri g
        on g.id = o.temizlik_gorevi_id
       and g.durum in ('bekliyor','temizleniyor')
     where o.otel_id = v_otel and o.aktif is true
     order by o.kat nulls last, o.oda_no
     limit least(greatest(coalesce(p_limit, 200), 1), 500);
end;
$fn$;

-- ---------------------------------------------------------------------------
-- 3) FONKSİYON ACL'LERİ — AÇIK KARAR
-- ---------------------------------------------------------------------------
-- Süpürge açık kararın yerine geçmez; her fonksiyon imzasıyla yazılır.
-- DÜZELTME (REST baypas X16 yakaladı): YENİ fonksiyon, veritabanının
-- varsayılan ACL'sinden `service_role` EXECUTE hakkını MİRAS alıyordu
-- (bilinen P3 platform riski). `CREATE OR REPLACE` mevcut ACL'yi koruduğu
-- için `listele` etkilenmedi; yalnız yeni `odalar` etkilendi. Kural Adım 1
-- ile AYNIDIR: public, anon, authenticated VE service_role'dan geri al,
-- yalnız authenticated'a ver. Kat hizmetleri API'si service_role'a açık
-- DEĞİLDİR.
revoke all on function public.pms_housekeeping_listele(text, text, integer) from public;
revoke all on function public.pms_housekeeping_listele(text, text, integer) from anon;
revoke all on function public.pms_housekeeping_listele(text, text, integer) from authenticated;
revoke all on function public.pms_housekeeping_listele(text, text, integer) from service_role;
grant execute on function public.pms_housekeeping_listele(text, text, integer) to authenticated;

revoke all on function public.pms_housekeeping_odalar(text, integer) from public;
revoke all on function public.pms_housekeeping_odalar(text, integer) from anon;
revoke all on function public.pms_housekeeping_odalar(text, integer) from authenticated;
revoke all on function public.pms_housekeeping_odalar(text, integer) from service_role;
grant execute on function public.pms_housekeeping_odalar(text, integer) to authenticated;

-- Süpürge: bu migration'ın dokunduğu yüzeyde anon/service_role'a hiçbir şey
-- kalmasın. Süpürge açık kararın YERİNE GEÇMEZ, üstüne biner.
do $$
declare r record;
begin
  for r in
    select p.oid::regprocedure::text as imza
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('pms_housekeeping_listele','pms_housekeeping_odalar')
  loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', r.imza);
    execute format('grant execute on function %s to authenticated', r.imza);
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- 4) DOĞRULAMA — COMMIT'TEN ÖNCE
-- ---------------------------------------------------------------------------
do $$
declare v_n int;
begin
  if to_regprocedure('public.pms_housekeeping_odalar(text,integer)') is null then
    raise exception 'DOGRULAMA: pms_housekeeping_odalar olusmadi';
  end if;

  -- Her iki fonksiyon da SECURITY DEFINER ve search_path PİNLİ olmalı.
  select count(*) into v_n from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('pms_housekeeping_listele','pms_housekeeping_odalar')
     and p.prosecdef
     and exists (select 1 from unnest(coalesce(p.proconfig,'{}')) c where c like 'search_path=%');
  if v_n <> 2 then
    raise exception 'DOGRULAMA: pinsiz/definer olmayan fonksiyon var (%/2)', v_n;
  end if;

  -- anon EXECUTE hakkı KALMAMALI.
  select count(*) into v_n from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('pms_housekeeping_listele','pms_housekeeping_odalar')
     and has_function_privilege('anon', p.oid, 'EXECUTE');
  if v_n <> 0 then raise exception 'DOGRULAMA: anon EXECUTE kaldi (%)', v_n; end if;

  -- service_role EXECUTE hakkı da KALMAMALI. Varsayılan ACL mirası yeni
  -- fonksiyona sessizce bu hakkı veriyordu; migration artık kendisi düşer.
  select count(*) into v_n from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('pms_housekeeping_listele','pms_housekeeping_odalar')
     and has_function_privilege('service_role', p.oid, 'EXECUTE');
  if v_n <> 0 then raise exception 'DOGRULAMA: service_role EXECUTE kaldi (%)', v_n; end if;

  -- Modül üretimde KAPALI kalmalı: bu migration onu açmaz.
  if exists (select 1 from public.moduller where kod = 'pms_housekeeping' and aktif) then
    raise warning 'NOT: pms_housekeeping bu veritabaninda ACIK (yerel QA icin normaldir).';
  end if;

  raise notice 'DOGRULAMA (adim 2 arayuz destegi): tum kontroller gecti.';
end $$;

commit;

-- ============================================================================
-- GERİ ALMA
-- ----------------------------------------------------------------------------
-- 1) `pms_housekeeping_odalar` düşürülebilir:
--      drop function if exists public.pms_housekeeping_odalar(text, integer);
-- 2) `pms_housekeeping_listele` 2026-09-09 sürümüne geri alınabilir; `benim`
--    kuyruğu kaybolur ve "İşlerim" yeniden eksik listeler.
-- Görev verisine DOKUNULMAZ; bu migration yalnız okuma sözleşmesidir.
-- ============================================================================
