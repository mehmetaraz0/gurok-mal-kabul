-- ============================================================================
-- YAYIN PENCERESI — STOK YAZMALARINI SUNUCUDA DURAKLAT (2026-09-20)
-- ============================================================================
-- NEDEN: Hareketsizlik sorgusu yalnizca YARDIMCI kanittir; "ekranlar kapali"
-- demez. Migration sirasinda hicbir istemcinin stok yazmadigini garanti eden
-- tek sey, sunucunun yazmayi reddetmesidir. Bu dosya yazma yolunu KAPATIR.
--
-- NE YAPAR: authenticated rolunden stok yazma haklari geri alinir.
--   * rpc/stok_ekle (iki imza), rpc/stok_transfer  -> EXECUTE yok
--   * stok_hareketleri  -> INSERT yok
--   * stok             -> INSERT/UPDATE yok (dogrudan yazan eski yollar)
-- Okuma (SELECT) DOKUNULMAZ: ekranlar gormeye devam eder.
--
-- NE YAPMAZ (KALAN RISK — acikca yaziyoruz):
--   * Bu duraklatma, o an SURMEKTE olan cok satirli bir islemi TAMAMLAMAZ.
--     Tersine, sonraki satirinda o islemi keser. Sunucu "hangi istemci islemin
--     ortasinda" bilemez (satirlar ayri HTTP istekleridir, islem kimligi yoktur).
--     Bu yuzden duraklatma ONCESINDE hareketsizlik beklenir ve duraklatmadan
--     sonra REDDEDILEN denemeler personelden sorulur/izlenir.
--   * Bar siparis akisi (SECURITY DEFINER fonksiyonlar) bu duraklatmadan
--     ETKILENMEZ: teslim/iptal stogu sunucu fonksiyonu icinden yazar. Bar
--     operasyonu durmaz; istenirse bar ekranlari ayrica kapatilir.
--
-- SIRA: (1) hareketsizlik kontrolu -> (2) BU DOSYA -> (3) 5 dk bekle, reddedilen
-- deneme var mi diye personele sor -> (4) yedek -> (5) migration -> (6) surdur
-- dosyasi (2026-09-20-yayin-yazma-surdur.sql). Migration basarisiz olsa bile
-- (6) MUTLAKA calistirilir; yoksa stok yazmalari kapali kalir.
--
--   .\docs\kurulum\sql-uygula.ps1 -Dosya docs\kurulum\2026-09-20-yayin-yazma-duraklat.sql
-- ============================================================================
begin;

revoke execute on function public.stok_ekle(text, text, text, numeric) from authenticated;
do $$
begin
  if to_regprocedure('public.stok_ekle(text,text,text,numeric,integer)') is not null then
    execute 'revoke execute on function public.stok_ekle(text, text, text, numeric, integer) from authenticated';
  end if;
end;
$$;
revoke execute on function public.stok_transfer(text, text, text, text, numeric) from authenticated;
revoke insert on table public.stok_hareketleri from authenticated;
revoke insert, update on table public.stok from authenticated;

-- Duraklatma kaydi: denetim izinde yayin penceresi gorunur olsun.
insert into public.erp_islem_audit (hotel_id, actor_user_id, actor_role, event_type,
                                    entity_type, entity_id, transaction_id, islem_detayi)
values (null, null, 'service_role', 'UPDATE', 'stok', 'A1-YAYIN-DURAKLATMA', pg_current_xact_id()::text,
        jsonb_build_object('islem', 'yazma_duraklatildi', 'dosya', '2026-09-20-yayin-yazma-duraklat.sql'));

-- Son kosul: gercekten kapandi mi?
do $$
begin
  if has_function_privilege('authenticated', 'public.stok_ekle(text,text,text,numeric)', 'EXECUTE')
     or has_table_privilege('authenticated', 'public.stok_hareketleri', 'INSERT')
     or has_table_privilege('authenticated', 'public.stok', 'UPDATE') then
    raise exception 'SON KOSUL: stok yazma yolu hala acik; duraklatma tutmadi.';
  end if;
end;
$$;

commit;

\echo '== DURAKLATILDI. Ekranlar okumaya devam eder, YAZAMAZ.'
\echo '== Bar siparis akisi (SECURITY DEFINER) etkilenmez.'
\echo '== Yayin bitince 2026-09-20-yayin-yazma-surdur.sql MUTLAKA calistirilir.'
