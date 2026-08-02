-- 2026-08-01 — AI Analiz Merkezi v1 / FAZ 1: salt-okunur analiz view'ları
--
-- Tasarım: docs/superpowers/specs/2026-08-01-ai-analiz-merkezi-design.md
-- Kolonlar canlı information_schema'dan DOĞRULANDI (2026-08-01).
--
-- GÜVENLİK: Operasyonel tablolara (stok/stok_hareketleri/skt_kayitlari/stok_minimumlar/
-- mal_kabuller/uygunsuzluklar) dokunan view'lar `security_invoker=true` → kullanıcının
-- JWT'siyle çalışınca Madde D otel-RLS'i (auth_otel_erisim) OTOMATİK uygulanır: tek-otel
-- kullanıcı yalnızca kendi otelini, merkez hepsini görür. Elle WHERE otel_id YOK.
-- Paylaşımlı referans tablolar (urunler, urun_*_gruplari — otel_id yok) join'lerde serbest.
--
-- Salt-okunur; hiçbir tabloyu değiştirmez. Çalıştırma: SQL Editor → Run.
-- Geri alma: en altta (drop view'lar).

begin;

-- ============================================================
-- 1) ai_otel_ref — otel_id → okunur isim (otel-config.js'in SQL yansıması, statik)
-- ============================================================
create or replace view public.ai_otel_ref as
  select '810'::text as otel_id, 'Ali Bey Club Manavgat' as otel_ad
  union all
  select '811'::text, 'Ali Bey Resort Sorgun';

-- ============================================================
-- 2) ai_urun_grup — ürün → grup hiyerarşisi
--    ⚠️ v1 DIŞI / ERTELENDİ (v1.1): canlıda urun_siniflandirma BOŞ (0 satır) → bu view 0
--    satır döner. urunler.grup yalnızca okunmaz KOD (YIY01..YIY12), okunur isim eşlemesi yok.
--    6 v1 niyetinin hiçbiri grup-ismine göre filtrelemiyor → v1 yeteneği düşmez. View zararsız
--    kalır. Grup-filtreli serbest soru için ön koşul: KOD→isim eşleme tablosu (v1.1).
-- ============================================================
create or replace view public.ai_urun_grup as
  select s.urun_kodu,
         ag.ana_grup_kod, ag.ana_grup_adi,
         alt.alt_grup_kod, alt.alt_grup_adi
  from public.urun_siniflandirma s
  join public.urun_alt_gruplari alt
       on alt.alt_grup_kod = s.alt_grup_kod and coalesce(alt.silindi, false) = false
  join public.urun_ana_gruplari ag
       on ag.ana_grup_kod = alt.ana_grup_kod and coalesce(ag.silindi, false) = false
  where coalesce(s.silindi, false) = false;

-- ============================================================
-- 3) ai_tuketim_trend — haftalık çıkış (tüketim), otel/depo/ürün bazlı (security_invoker)
--    cikis_toplam = tüm çıkış; tuketim_miktar = aciklama'da 'tuketim' geçen (günlük/reçete)
--    NOT: "tüketim" tanımı aciklama ILIKE'a bağlı (temiz kategori yok) — tek yerde burada.
-- ============================================================
create or replace view public.ai_tuketim_trend with (security_invoker = true) as
  select h.otel_id,
         h.depo_kodu,
         h.urun_kodu,
         u.ad as urun_adi,
         (date_trunc('week', h.tarih))::date as hafta,
         sum(h.miktar) as cikis_toplam,
         sum(h.miktar) filter (where h.aciklama ilike '%tuketim%') as tuketim_miktar
  from public.stok_hareketleri h
  left join public.urunler u on u.kod = h.urun_kodu
  where h.tip = 'cikis'
  group by h.otel_id, h.depo_kodu, h.urun_kodu, u.ad, date_trunc('week', h.tarih);

-- ============================================================
-- 4) ai_stok_anomali — istatistiksel sapma adayları (son 30 hareket ort/stddev, security_invoker)
--    |miktar - ort| > k*sapma olan satırlar aday; k eşiği tüketen RPC/EF parametresi.
-- ============================================================
create or replace view public.ai_stok_anomali with (security_invoker = true) as
  select h.otel_id, h.depo_kodu, h.urun_kodu, u.ad as urun_adi,
         h.tip, h.tarih, h.miktar, h.aciklama,
         avg(h.miktar) over w as ort_30,
         stddev_pop(h.miktar) over w as sapma_30
  from public.stok_hareketleri h
  left join public.urunler u on u.kod = h.urun_kodu
  window w as (partition by h.urun_kodu, h.depo_kodu, h.tip
               order by h.tarih rows between 30 preceding and 1 preceding);

-- ============================================================
-- 5) ai_skt_risk — aktif SKT kayıtları + kalan gün (security_invoker)
-- ============================================================
create or replace view public.ai_skt_risk with (security_invoker = true) as
  select s.otel_id, s.depo_kodu, s.urun_kodu, u.ad as urun_adi,
         s.miktar, s.skt_tarihi,
         (s.skt_tarihi - current_date) as kalan_gun
  from public.skt_kayitlari s
  left join public.urunler u on u.kod = s.urun_kodu
  where s.durum = 'aktif';

-- ============================================================
-- 6) ai_min_alti_stok — minimum seviyenin altındaki stoklar (security_invoker)
-- ============================================================
create or replace view public.ai_min_alti_stok with (security_invoker = true) as
  select st.otel_id, st.depo_kodu, st.urun_kodu, u.ad as urun_adi,
         st.miktar, m.min_miktar,
         (m.min_miktar - st.miktar) as eksik_miktar
  from public.stok st
  join public.stok_minimumlar m
       on m.urun_kodu = st.urun_kodu and m.depo_kodu = st.depo_kodu
  left join public.urunler u on u.kod = st.urun_kodu
  where st.miktar < m.min_miktar;

-- ============================================================
-- 7) ai_gunluk_ozet — otel bazlı günlük özet (security_invoker)
--    bekleyen mal kabul + 14 günde kritik SKT + min-altı stok sayısı
-- ============================================================
create or replace view public.ai_gunluk_ozet with (security_invoker = true) as
  select o.otel_id,
         (select count(*) from public.mal_kabuller mk
            where mk.durum = 'bekleyen' and mk.otel_id::text = o.otel_id) as bekleyen_mal_kabul,
         (select count(*) from public.skt_kayitlari s
            where s.durum = 'aktif' and s.otel_id::text = o.otel_id
              and s.skt_tarihi between current_date and current_date + 14) as kritik_skt_14gun,
         (select count(*) from public.ai_min_alti_stok ma
            where ma.otel_id::text = o.otel_id) as min_alti_urun
  from public.ai_otel_ref o;

commit;

-- ============================================================
-- TEST (SQL Editor'de + uygulama üzerinde):
-- a) select * from ai_gunluk_ozet;  → 810/811 satırları (SQL Editor'de auth.uid null
--    olduğu için security_invoker view'lar RLS'siz çalışır = tüm veri; GERÇEK otel-scope
--    testi UYGULAMADA tek-otel login ile yapılır).
-- b) select * from ai_skt_risk order by kalan_gun limit 10;
-- c) select * from ai_tuketim_trend order by hafta desc, cikis_toplam desc limit 10;
-- d) select * from ai_stok_anomali where sapma_30 is not null
--      and abs(miktar - ort_30) > 2*sapma_30 limit 10;
-- e) UYGULAMA: tek-otel (810) kullanıcıyla giriş → bu view'ları çeken ekran SADECE 810
--    verisini göstermeli (security_invoker + Madde D RLS). Merkez → ikisi de.
-- f) urun_siniflandirma dolu mu: select count(*) from ai_urun_grup;  (boşsa grup-filtreli
--    sorular şimdilik urunler.grup'a düşürülür — EF/intent tarafında ele alınır)
-- ============================================================
-- ROLLBACK:
-- begin;
-- drop view if exists public.ai_gunluk_ozet;
-- drop view if exists public.ai_min_alti_stok;
-- drop view if exists public.ai_skt_risk;
-- drop view if exists public.ai_stok_anomali;
-- drop view if exists public.ai_tuketim_trend;
-- drop view if exists public.ai_urun_grup;
-- drop view if exists public.ai_otel_ref;
-- commit;
