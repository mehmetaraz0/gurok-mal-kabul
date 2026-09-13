-- ============================================================================
-- YEDEK DOĞRULAMA SAYAÇLARI — SALT OKUMA
-- Tarih: 2026-09-13
-- ============================================================================
-- Nerede çalışır : Supabase SQL Editor, ÜRETİM. Tek SELECT; hiçbir şey yazmaz.
-- Ne işe yarar   : Elle alınan yedeğin izole kopyaya geri yüklenmesinden sonra
--                  satır sayılarının tuttuğunu kanıtlamak için "beklenen"
--                  değerleri üretir. Dosyanın var olması yedek KANITI DEĞİLDİR
--                  (yayın planı E-5).
--
-- ---------------------------------------------------------------------------
-- SAYAÇ ile YEDEK AYNI DURUMU GÖRMELİDİR
-- ---------------------------------------------------------------------------
-- "Aynı dakikada çalıştır" yeterli bir koşul değildir: iki işlem arasında bir
-- yazma olursa sayaçlar yedeği temsil etmez. Kabul edilen iki yol:
--
--   A) AYNI SNAPSHOT (tercih edilen)
--      Yedek ve sayaçlar aynı anlık görüntüden okunur:
--        1. psql ile üretime bağlanın ve tek oturumda:
--             begin isolation level repeatable read;
--             select pg_export_snapshot();          -- snapshot kimliği
--           Oturumu AÇIK bırakın.
--        2. Başka bir kabukta, aynı snapshot ile veri yedeği alın:
--             pg_dump ... --snapshot=<kimlik> --data-only ...
--        3. Açık oturumda bu dosyayı çalıştırıp çıktıyı kaydedin, sonra
--             commit;   (ya da rollback; — ikisi de salt okumadır)
--      Not: `--snapshot` yalnız aynı sunucuya doğrudan bağlantıda geçerlidir;
--      pooler üzerinden çalışmayabilir. Çalışmıyorsa (B)'ye geçin.
--
--   B) DOĞRULANMIŞ YAZMA DURAKLATMASI
--      Yazmalar durdurulur ve durduğu ÖLÇÜLÜR:
--        1. Uygulama yazmalarını durdurun (personel işlemi bitirir, ekranlar
--           kapatılır) — yalnız sözle değil, aşağıdaki kanıtla.
--        2. Bu dosyayı çalıştırın; `denetim_izi_son_kayit` ve
--           `denetim_izi_satir` değerlerini not edin.
--        3. Yedeği alın.
--        4. Bu dosyayı TEKRAR çalıştırın. `denetim_izi_satir` ve tüm satır
--           sayıları DEĞİŞMEMİŞ olmalı. Değiştiyse yazma sürüyor demektir:
--           yedek ve sayaçlar farklı durumları gösterir, baştan alınır.
--      Duraklatma penceresi bu iki ölçüm arasındaki süredir ve kayda geçer.
--
-- ---------------------------------------------------------------------------
-- KAPSAM VE GÖRÜNÜRLÜK — YEDEKLE EŞİTLENMİŞTİR
-- ---------------------------------------------------------------------------
-- `dokum-al.ps1` yedeği `--schema=public --schema=phase0_private` ile alır.
-- Bu sorgu da tam olarak o iki şemadaki tabloları sayar (bugün phase0_private'de
-- tablo yoktur; ileride eklenirse kapsama kendiliğinden girer).
-- Görünürlük: SQL Editor `postgres` rolüyle çalışır ve tabloların sahibidir;
-- pg_dump da aynı rolle bağlanır. Çıktıya `rol`, `bypassrls` ve `force_rls_tablo`
-- alanları eklenir ki karşılaştırma aynı görünürlükte yapıldığı görülebilsin.
--
-- NASIL KULLANILIR
--   1) Yukarıdaki (A) ya da (B) yolunu izleyin.
--   2) Tek satırlık JSON çıktısını REPO DIŞINDAKİ yedek klasörüne
--      `<etiket>-sayaclar.json` olarak kaydedin (varsayılan C:/Users/USER/ERP-Yedek).
--   3) Geri yükleme provası:
--      node scripts/pms-yedek-geri-yukleme-provasi.mjs <veri-yedegi> <sayaclar.json>
-- ============================================================================

select jsonb_pretty(jsonb_build_object(
  'alinma_zamani', now(),
  'sunucu_surumu', current_setting('server_version'),
  'rol', current_user,
  'bypassrls', (select rolbypassrls from pg_roles where rolname = current_user),
  'kapsam_semalari', jsonb_build_array('public', 'phase0_private'),
  'force_rls_tablo', (select count(*) from pg_class c
                       join pg_namespace n on n.oid = c.relnamespace
                      where n.nspname in ('public','phase0_private')
                        and c.relkind = 'r' and c.relforcerowsecurity),
  'tablo_sayisi', (select count(*) from pg_class c
                    join pg_namespace n on n.oid = c.relnamespace
                   where n.nspname in ('public','phase0_private') and c.relkind = 'r'),
  'satir_sayilari', (
    select coalesce(jsonb_object_agg(t.tablo, t.adet order by t.tablo), '{}'::jsonb)
      from (
        select n.nspname || '.' || c.relname as tablo,
               (xpath('/row/c/text()',
                      query_to_xml(format('select count(*) as c from %I.%I', n.nspname, c.relname),
                                   false, true, '')))[1]::text::bigint as adet
          from pg_class c
          join pg_namespace n on n.oid = c.relnamespace
         where n.nspname in ('public','phase0_private') and c.relkind = 'r'
      ) t
  ),
  'denetim_izi_satir', (select count(*) from public.erp_islem_audit),
  'denetim_izi_son_kayit', (select max(server_timestamp) from public.erp_islem_audit),
  'pms_ozet', jsonb_build_object(
    'oda', (select count(*) from public.pms_odalar),
    'dolu_oda', (select count(*) from public.pms_odalar where kullanim_durumu = 'dolu'),
    'devam_eden_konaklama', (select count(*) from public.pms_rezervasyonlar where durum = 'giris_yapildi'),
    'aktif_atama', (select count(*) from public.pms_oda_atamalari where aktif),
    'acik_folyo', (select count(*) from public.pms_folyolar where durum = 'acik')
  )
)) as sayaclar;

-- ============================================================================
-- YORUMLAMA
-- ============================================================================
-- * Bu çıktı, yedeğin OKUDUĞU durumu temsil etmelidir. (A) yolunda bu garanti
--   snapshot'tan gelir; (B) yolunda iki ölçümün eşitliğinden.
-- * Geri yükleme provasında satır sayıları BİREBİR karşılaştırılır; tutmayan
--   her tablo raporlanır ve yedek kabul edilmez.
-- * `rol` ve `bypassrls` alanları, sayımın yedekle aynı görünürlükte yapıldığını
--   gösterir. `force_rls_tablo` > 0 ise sahibin bile göremediği satırlar olabilir;
--   o durumda karşılaştırma bu notla birlikte okunur.
-- ============================================================================
