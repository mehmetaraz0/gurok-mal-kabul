-- 2026-08-02 — AI Analiz Merkezi v1 / FAZ 2: yetki modülü + 6 niyet RPC'si
--
-- Tasarım: docs/superpowers/specs/2026-08-01-ai-analiz-merkezi-design.md
-- Faz 1 (7 view) CANLI+doğrulandı. Bu dosya:
--   (1) ai_analiz_merkezi yetki modülünü seed'ler (EF auth_yetki_var buna bakacak),
--   (2) 6 niyet için SECURITY INVOKER RPC yazar — filtreleme SQL'de, RLS+otel izolasyonu
--       OTOMATİK (Faz 1 ai_* view'larını + base tabloları kullanıcı JWT'siyle okur).
--
-- GÜVENLİK: RPC'ler SECURITY INVOKER → kullanıcının JWT'siyle çalışınca Madde D otel-RLS'i
-- (auth_otel_erisim) otomatik uygulanır. service_role YOK. Dönüş = küçük agregat (PII yok,
-- otel-scoped, LIMIT'li). EF bunları auth_yetki_var('ai_analiz_merkezi','goruntule') geçen
-- kullanıcı için çağırır.
--
-- Çalıştırma: SQL Editor → Run. Geri alma: en altta.

begin;

-- ============================================================
-- 1) Yetki modülü: ai_analiz_merkezi
-- ============================================================
insert into public.moduller (kod, ad, sira, kategori, aktif)
select 'ai_analiz_merkezi', 'Akıllı Veri Analiz Merkezi', 60, 'analiz', true
where not exists (select 1 from public.moduller where kod = 'ai_analiz_merkezi');

-- Yetki dağılımı: yönetim + ilgili müdürler (yalnızca 'goruntule' — salt-okunur analiz).
-- yetki enum değerini tip adını bilmeden mevcut bir 'goruntule' satırından alıyoruz.
-- İstenirse sonradan yetki-yonetimi ekranından değiştirilebilir.
insert into public.yetki_matrisi (rol_id, modul_id, yetki)
select r.id,
       (select id from public.moduller where kod = 'ai_analiz_merkezi'),
       (select yetki from public.yetki_matrisi where yetki::text = 'goruntule' limit 1)
from public.roller r
where r.kod in (
  'grup_direktor', 'grup_finans', 'grup_satinalma', 'grup_kalite', 'sistem_admin',
  'gm', 'mali_isler_mdr', 'muhasebe_mdr', 'cost_control_mdr', 'cost_control',
  'fb_mdr', 'satinalma_mdr', 'depo_sef'
)
and not exists (
  select 1 from public.yetki_matrisi ym
  where ym.rol_id = r.id
    and ym.modul_id = (select id from public.moduller where kod = 'ai_analiz_merkezi')
);

-- ============================================================
-- 2) Niyet RPC'leri (SECURITY INVOKER — RLS/otel-scope otomatik)
--    Her biri küçük jsonb agregat döner. p_otel null = kullanıcının görebildiği tüm oteller.
-- ============================================================

-- 2a) gunluk_ozet — otel bazlı bekleyen mal kabul + kritik SKT + min-altı
create or replace function public.ai_q_gunluk_ozet(p_otel text default null)
returns jsonb language sql stable security invoker set search_path = public as $$
  select coalesce(jsonb_agg(t), '[]'::jsonb) from (
    select otel_id, bekleyen_mal_kabul, kritik_skt_14gun, min_alti_urun
    from public.ai_gunluk_ozet
    where (p_otel is null or otel_id::text = p_otel)
    order by otel_id
  ) t;
$$;

-- 2b) skt_yaklasan — p_gun içinde SKT'si dolacak aktif kayıtlar
create or replace function public.ai_q_skt_yaklasan(p_otel text default null, p_gun int default 14)
returns jsonb language sql stable security invoker set search_path = public as $$
  select coalesce(jsonb_agg(t), '[]'::jsonb) from (
    select otel_id, depo_kodu, urun_kodu, urun_adi, miktar, skt_tarihi, kalan_gun
    from public.ai_skt_risk
    where (p_otel is null or otel_id::text = p_otel)
      and kalan_gun <= greatest(p_gun, 0)
    order by kalan_gun asc
    limit 50
  ) t;
$$;

-- 2c) stok_anomali — |miktar - ort_30| > esik * sapma_30 (istatistiksel sapma)
create or replace function public.ai_q_stok_anomali(p_otel text default null, p_esik numeric default 2)
returns jsonb language sql stable security invoker set search_path = public as $$
  select coalesce(jsonb_agg(t), '[]'::jsonb) from (
    select otel_id, depo_kodu, urun_kodu, urun_adi, tip, tarih, miktar, ort_30, sapma_30
    from public.ai_stok_anomali
    where (p_otel is null or otel_id::text = p_otel)
      and sapma_30 is not null and sapma_30 > 0
      and abs(miktar - ort_30) > greatest(p_esik, 0) * sapma_30
    order by abs(miktar - ort_30) / nullif(sapma_30, 0) desc
    limit 50
  ) t;
$$;

-- 2d) min_alti_stok — minimum altındaki ürünler + minimum-tanımlı bayrağı
--     (stok_minimumlar boşsa EF 'henüz minimum tanımlı değil' göstermeli)
create or replace function public.ai_q_min_alti(p_otel text default null)
returns jsonb language sql stable security invoker set search_path = public as $$
  select jsonb_build_object(
    'minimum_tanimli', exists (select 1 from public.stok_minimumlar),
    'satirlar', coalesce((
      select jsonb_agg(t) from (
        select otel_id, depo_kodu, urun_kodu, urun_adi, miktar, min_miktar, eksik_miktar
        from public.ai_min_alti_stok
        where (p_otel is null or otel_id::text = p_otel)
        order by eksik_miktar desc
        limit 50
      ) t
    ), '[]'::jsonb)
  );
$$;

-- 2e) tuketim_artan — son p_gun vs önceki p_gun tüketim karşılaştırması (artanlar)
create or replace function public.ai_q_tuketim_artan(p_otel text default null, p_gun int default 30)
returns jsonb language sql stable security invoker set search_path = public as $$
  select coalesce(jsonb_agg(t), '[]'::jsonb) from (
    select h.otel_id, h.urun_kodu, u.ad as urun_adi,
           coalesce(sum(h.miktar) filter (where h.tarih >= current_date - p_gun), 0) as son_donem,
           coalesce(sum(h.miktar) filter (where h.tarih >= current_date - 2 * p_gun
                                            and h.tarih <  current_date - p_gun), 0) as onceki_donem
    from public.stok_hareketleri h
    left join public.urunler u on u.kod = h.urun_kodu
    where h.tip = 'cikis' and h.aciklama ilike '%tuketim%'
      and h.tarih >= current_date - 2 * p_gun
      and (p_otel is null or h.otel_id::text = p_otel)
    group by h.otel_id, h.urun_kodu, u.ad
    having coalesce(sum(h.miktar) filter (where h.tarih >= current_date - p_gun), 0)
         > coalesce(sum(h.miktar) filter (where h.tarih >= current_date - 2 * p_gun
                                           and h.tarih < current_date - p_gun), 0)
    order by (coalesce(sum(h.miktar) filter (where h.tarih >= current_date - p_gun), 0)
            - coalesce(sum(h.miktar) filter (where h.tarih >= current_date - 2 * p_gun
                                             and h.tarih < current_date - p_gun), 0)) desc
    limit 30
  ) t;
$$;

-- 2f) yavas_donen — stoklu ama son p_gun günde HİÇ çıkışı olmayan ürünler
create or replace function public.ai_q_yavas_donen(p_otel text default null, p_gun int default 30)
returns jsonb language sql stable security invoker set search_path = public as $$
  select coalesce(jsonb_agg(t), '[]'::jsonb) from (
    select st.otel_id, st.depo_kodu, st.urun_kodu, u.ad as urun_adi, st.miktar
    from public.stok st
    left join public.urunler u on u.kod = st.urun_kodu
    where st.miktar > 0
      and (p_otel is null or st.otel_id::text = p_otel)
      and not exists (
        select 1 from public.stok_hareketleri h
        where h.urun_kodu = st.urun_kodu and h.depo_kodu = st.depo_kodu
          and h.tip = 'cikis' and h.tarih >= current_date - p_gun
      )
    order by st.miktar desc
    limit 50
  ) t;
$$;

-- ============================================================
-- 3) Yetkiler: public/anon çağıramasın, yalnızca authenticated
-- ============================================================
do $$
declare fn text;
begin
  foreach fn in array array[
    'ai_q_gunluk_ozet(text)', 'ai_q_skt_yaklasan(text,int)', 'ai_q_stok_anomali(text,numeric)',
    'ai_q_min_alti(text)', 'ai_q_tuketim_artan(text,int)', 'ai_q_yavas_donen(text,int)'
  ] loop
    execute format('revoke all on function public.%s from public, anon;', fn);
    execute format('grant execute on function public.%s to authenticated;', fn);
  end loop;
end $$;

commit;
notify pgrst, 'reload schema';

-- ============================================================
-- TEST (SQL Editor'de — auth.uid null olduğu için RLS'siz = tüm veri; gerçek otel-scope
-- testi UYGULAMADA tek-otel login ile Faz 4'te):
-- select public.ai_q_gunluk_ozet();
-- select public.ai_q_skt_yaklasan(null, 14);
-- select public.ai_q_stok_anomali(null, 2);
-- select public.ai_q_min_alti();          -> {"minimum_tanimli": false, "satirlar": []}
-- select public.ai_q_tuketim_artan(null, 30);
-- select public.ai_q_yavas_donen(null, 30);
-- select public.auth_yetki_var('ai_analiz_merkezi','goruntule');  -- SQL'de auth yok → muhtemelen false; gerçek test EF/uygulamada
-- ============================================================
-- ROLLBACK:
-- begin;
-- drop function if exists public.ai_q_gunluk_ozet(text);
-- drop function if exists public.ai_q_skt_yaklasan(text,int);
-- drop function if exists public.ai_q_stok_anomali(text,numeric);
-- drop function if exists public.ai_q_min_alti(text);
-- drop function if exists public.ai_q_tuketim_artan(text,int);
-- drop function if exists public.ai_q_yavas_donen(text,int);
-- delete from public.yetki_matrisi where modul_id = (select id from public.moduller where kod='ai_analiz_merkezi');
-- delete from public.moduller where kod = 'ai_analiz_merkezi';
-- commit;
-- notify pgrst, 'reload schema';
