-- ============================================================================
-- PMS FONKSİYON ACL TEMİZLİĞİ
-- Tarih: 2026-09-08
--
-- ############################################################################
-- # BU MIGRATION ÜRETİMDE ZATEN UYGULANMIŞTIR.                               #
-- #                                                                          #
-- # 2026-09-08'de kullanıcı, aşağıdaki revoke döngüsünü doğrudan Supabase    #
-- # SQL Editor'de çalıştırdı. Bu dosya o değişikliği SONRADAN kayda geçirir: #
-- # repo ile üretimin ayrışmaması için. Yeni kurulumlarda ve staging'de      #
-- # normal bir migration gibi çalıştırılır.                                  #
-- #                                                                          #
-- # Dosya idempotenttir: ikinci kez çalıştırmak hiçbir şeyi değiştirmez.     #
-- ############################################################################
--
-- NEDEN GEREKTİ
--   `2026-09-07-varsayilan-acl-uyari-kontrolu.sql` üretimde çalıştırıldığında
--   D3 = 18 ölçüldü: `public` şemasında `anon`'un EXECUTE hakkı olan 18
--   fonksiyon. Hepsi bizim PMS fonksiyonlarımızdı.
--
--   Sınıflandırma (repodan doğrulandı, tahmin değil):
--     17 adet  `returns trigger`  — doğrudan çağrılamaz, PostgREST yayınlamaz
--      1 adet  `pms_bugun(otel_id)` — `language sql stable`, tabloya
--               dokunmuyor, `select (now() at time zone 'Europe/Istanbul')::date`
--
--   Yani FİİLİ SIZINTI YOKTU. Sorun şuydu: 22 PMS fonksiyonundan yalnız 4'ü
--   (`pms_check_in`, `pms_check_out`, `pms_folio_oda_ucreti_isle`,
--   `pms_folio_kapat`) açık `revoke` almıştı; kalan 18'i için ACL kararı hiç
--   verilmemişti. Bugün zararsız olmaları, gövdelerinin yarın
--   değişmeyeceğini garanti etmez.
--
--   Açık revoke alan her fonksiyonun kapalı, almayan her fonksiyonun açık
--   çıkması, standardın kuralının üretimde bire bir çalıştığının kanıtıdır.
--
-- KAPSAM
--   Yalnız EXECUTE ayrıcalığı geri alınır. Hiçbir fonksiyon gövdesi, hiçbir
--   tablo, hiçbir politika, hiçbir veri değişmez.
--
-- TETİKLEYİCİLER NEDEN BOZULMAZ
--   PostgreSQL, tetikleyici fonksiyonu üzerindeki EXECUTE hakkını
--   `CREATE TRIGGER` anında kontrol eder; tetikleyici ateşlenirken YENİDEN
--   KONTROL ETMEZ. 17 tetikleyici fonksiyonu çalışmaya devam eder.
--
-- `authenticated` NEDEN ETKİLENMEZ
--   `public`/`postgres` varsayılan ACL'i yeni fonksiyona `authenticated` için
--   KENDİ EXECUTE hakkını verir — PUBLIC üzerinden değil. `from public, anon`
--   revoke'u ona dokunmaz. Üretimde ölçülerek doğrulandı (aşağıdaki
--   doğrulama bloğu aynı kontrolü yapar).
--
-- Standart: docs/kurulum/MIGRATION-GUVENLIK-STANDARDI.md
-- ============================================================================


-- ============================================================================
-- 0) ÖN KOŞULLAR
-- ============================================================================
do $$
begin
  if to_regclass('public.moduller') is null then
    raise exception 'ONKOSUL: moduller tablosu yok. Once Phase 0 uygulanmali.';
  end if;
end;
$$;


begin;


-- ============================================================================
-- 1) TEMİZLİK — `public` şemasındaki tüm `pms_*` fonksiyonlarından
--    PUBLIC ve anon için EXECUTE geri alınır.
--
--    `like 'pms\_%'` içindeki ters bölü zorunludur: `_` LIKE kalıbında tek
--    karakter jokeridir; kaçırılmazsa `pmsX...` gibi adlar da eşleşirdi.
-- ============================================================================
do $$
declare
  v record;
  n int := 0;
begin
  for v in select p.oid::regprocedure as f
             from pg_proc p
             join pg_namespace ns on ns.oid = p.pronamespace
            where ns.nspname = 'public'
              and p.proname like 'pms\_%'
  loop
    execute format('revoke all on function %s from public, anon', v.f);
    n := n + 1;
  end loop;
  raise notice 'PMS fonksiyon ACL temizligi: % fonksiyon islendi.', n;
end;
$$;


-- ============================================================================
-- 2) DOĞRULAMA — COMMIT'TEN ÖNCE
--
--    "Çalıştı" yeterli değil. İki yönlü sayılır: anon'un hiçbir şeye
--    erişemediği VE authenticated'ın çağrılabilir RPC'leri hâlâ
--    çağırabildiği. İkincisi olmadan bu blok bir regresyonu yakalayamazdı.
-- ============================================================================
do $$
declare
  v_anon    int;
  v_toplam  int;
  v_auth    int;
  v_cagrilabilir constant text[] :=
    array['pms_check_in','pms_check_out','pms_folio_oda_ucreti_isle',
          'pms_folio_kapat','pms_bugun'];
begin
  select count(*) into v_toplam
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname like 'pms\_%';

  -- Boş kurulumda (PMS henüz uygulanmamış) yapacak iş yok.
  if v_toplam = 0 then
    raise notice 'PMS fonksiyonu yok; dogrulama atlandi.';
    return;
  end if;

  -- (a) anon hiçbir pms_* fonksiyonunu çağıramamalı.
  select count(*) into v_anon
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname like 'pms\_%'
     and has_function_privilege('anon', p.oid, 'EXECUTE');
  if v_anon <> 0 then
    raise exception 'DOGRULAMA: anon hala % pms fonksiyonunu cagirabiliyor', v_anon;
  end if;

  -- (b) authenticated, çağrılabilir RPC'leri çağırabilmeli.
  --     Bu kontrol olmadan migration, uygulamayı kırarak "başarılı" olurdu.
  select count(*) into v_auth
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public'
     and p.proname = any (v_cagrilabilir)
     and not has_function_privilege('authenticated', p.oid, 'EXECUTE');
  if v_auth <> 0 then
    raise exception
      'DOGRULAMA: authenticated % cagrilabilir RPC icin EXECUTE kaybetti - PMS KIRILIRDI', v_auth;
  end if;

  raise notice 'DOGRULAMA gecti: % pms fonksiyonu, anon erisimi 0, authenticated korundu.', v_toplam;
end;
$$;


commit;


-- ============================================================================
-- 3) ÜRETİM ÖLÇÜMÜ — 2026-09-08
-- ----------------------------------------------------------------------------
-- Uygulama SONRASI, salt-okuma doğrulamayla ölçüldü:
--
--   | fonksiyon                       | authenticated | anon  |
--   |---------------------------------|---------------|-------|
--   | pms_bugun(otel_id)              | true          | false |
--   | pms_check_in(uuid,uuid)         | true          | false |
--   | pms_check_out(uuid)             | true          | false |
--   | pms_folio_oda_ucreti_isle(uuid) | true          | false |
--   | pms_folio_kapat(uuid)           | true          | false |
--
--   d3_anon = 0 · pms_toplam = 22
--
-- Yani: 22 PMS fonksiyonunun tamamı anon'a kapalı, beş çağrılabilir RPC'nin
-- tamamı authenticated'a açık. Uygulama akışı etkilenmedi.
-- ============================================================================


-- ============================================================================
-- 4) GERİ ALMA
-- ----------------------------------------------------------------------------
-- GEREKMEZ ve ÖNERİLMEZ. Bu migration yalnız fazla verilmiş ayrıcalığı geri
-- alır; geri almak, kapatılan yüzeyi yeniden açmak olur.
--
-- Yine de bir regresyon kanıtlanırsa, yalnız İLGİLİ fonksiyona, yalnız
-- ihtiyaç duyulan role, tek tek verilir — toplu `grant ... to public` ASLA:
--
--   grant execute on function public.<ad>(<imza>) to authenticated;
--
-- `anon`'a geri verilmesi gereken hiçbir PMS fonksiyonu yoktur: PMS'in
-- tamamı oturum açmış personel içindir.
-- ============================================================================
