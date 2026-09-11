-- ============================================================================
-- YEREL STAGING — KAT HİZMETLERİ QA KATMANI
-- ============================================================================
-- scripts/yerel-staging.mjs tarafından, şu sıradan SONRA uygulanır:
--   shim -> üretim şema dökümü -> PMS Adım 1..4 -> Faz 2 kat hizmetleri
--   migration'ı -> yerel-staging-overlay.sql -> BU DOSYA
--
-- ÜRETİMDE ASLA ÇALIŞTIRILMAZ. Amacı yalnızca tarayıcı QA'sı için DÖRT
-- YETKİ SEVİYESİNİ ve otel izolasyonunu aynı anda test edilebilir kılmak.
--
-- ÜRETİMDE MODÜL KAPALIDIR. Burada AÇILIR çünkü QA'nın konusu tam olarak
-- açık modülün davranışıdır.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1) Modül açılır (YALNIZ yerel QA)
-- ---------------------------------------------------------------------------
update public.moduller set aktif = true where kod = 'pms_housekeeping';

-- ---------------------------------------------------------------------------
-- 2) Yetki seviyeleri
--    b..a1  QA Tam Yetki          -> pms_housekeeping = tam   (PIN 111111 / 333333)
--    b..a2  QA Sadece Görüntüleme -> pms_housekeeping = goruntule (PIN 222222)
--    b..a4  QA Kat Görevlisi      -> pms_housekeeping = kayit (PIN 444444)
--    b..a5  QA Yetkisiz           -> kat hizmetleri YETKİSİ YOK (PIN 555555)
-- ---------------------------------------------------------------------------
insert into public.roller (id, ad, seviye, kod, aktif) values
  ('b0000000-0000-0000-0000-0000000000a4','QA Kat Görevlisi','otel','qa_hk_kayit',true),
  ('b0000000-0000-0000-0000-0000000000a5','QA Yetkisiz','otel','qa_hk_yok',true)
on conflict (id) do nothing;

insert into public.yetki_matrisi (rol_id, modul_id, yetki)
select 'b0000000-0000-0000-0000-0000000000a1', id, 'tam'
  from public.moduller where kod = 'pms_housekeeping'
on conflict do nothing;

insert into public.yetki_matrisi (rol_id, modul_id, yetki)
select 'b0000000-0000-0000-0000-0000000000a2', id, 'goruntule'
  from public.moduller where kod = 'pms_housekeeping'
on conflict do nothing;

insert into public.yetki_matrisi (rol_id, modul_id, yetki)
select 'b0000000-0000-0000-0000-0000000000a4', id, 'kayit'
  from public.moduller where kod = 'pms_housekeeping'
on conflict do nothing;

-- Kat görevlisi oda planını da görebilsin (salt okuma testleri için).
insert into public.yetki_matrisi (rol_id, modul_id, yetki)
select 'b0000000-0000-0000-0000-0000000000a4', id, 'goruntule'
  from public.moduller where kod in ('pms_oda','pms_oda_tipi')
on conflict do nothing;

-- QA Yetkisiz rolü: kat hizmetleri YOK, ama oda planı VAR — böylece
-- "sayfa kapalı" davranışı, oturumun tümden yetkisiz olmasıyla karışmaz.
insert into public.yetki_matrisi (rol_id, modul_id, yetki)
select 'b0000000-0000-0000-0000-0000000000a5', id, 'goruntule'
  from public.moduller where kod in ('pms_oda','pms_oda_tipi')
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- 3) QA kullanıcıları
-- ---------------------------------------------------------------------------
insert into auth.users (id, email) values
  ('a0000000-0000-0000-0000-0000000000a4','qa-hk-kayit@ornek.gecersiz'),
  ('a0000000-0000-0000-0000-0000000000a5','qa-hk-yok@ornek.gecersiz')
on conflict (id) do nothing;

insert into public.kullanicilar (id, auth_user_id, rol, rol_id, otel_id, aktif, tum_oteller, ad) values
  ('c0000000-0000-0000-0000-0000000000a4','a0000000-0000-0000-0000-0000000000a4',
   'depo','b0000000-0000-0000-0000-0000000000a4','810', true, false, 'QA Kat Görevlisi'),
  ('c0000000-0000-0000-0000-0000000000a5','a0000000-0000-0000-0000-0000000000a5',
   'depo','b0000000-0000-0000-0000-0000000000a5','810', true, false, 'QA Yetkisiz')
on conflict (id) do nothing;

-- İkinci bir kat görevlisi: devir/yeniden atama senaryoları iki çalışan ister.
insert into auth.users (id, email) values
  ('a0000000-0000-0000-0000-0000000000a6','qa-hk-kayit2@ornek.gecersiz')
on conflict (id) do nothing;
insert into public.kullanicilar (id, auth_user_id, rol, rol_id, otel_id, aktif, tum_oteller, ad) values
  ('c0000000-0000-0000-0000-0000000000a6','a0000000-0000-0000-0000-0000000000a6',
   'depo','b0000000-0000-0000-0000-0000000000a4','810', true, false, 'QA Kat Görevlisi 2')
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- 4) DEMO GÖREVLER
--    Onaylı RPC yüzeyinden açılır; doğrudan tablo yazımı YAPILMAZ. Böylece
--    QA verisi de üretimdeki yolun aynısından geçer.
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.role','authenticated',false);
select set_config('request.jwt.claim.sub','a0000000-0000-0000-0000-0000000000a1',false);

do $$
declare v_g uuid;
begin
  -- Oda 103 zaten `kirli`: bekleyen ekstra temizlik.
  perform public.pms_housekeeping_gorev_olustur(
    'e0000000-0000-0000-0000-0000000000a3'::uuid, 'ekstra_temizlik', 'bos', gen_random_uuid());

  -- Oda 102: görev açılır, sahiplenilir ve BAŞLATILIR -> `temizleniyor`.
  v_g := (public.pms_housekeeping_gorev_olustur(
    'e0000000-0000-0000-0000-0000000000a2'::uuid, 'ekstra_temizlik', 'bos',
    gen_random_uuid())->>'gorev_id')::uuid;
  perform set_config('request.jwt.claim.sub','a0000000-0000-0000-0000-0000000000a4',false);
  perform public.pms_housekeeping_sahiplen(v_g,
    (select surum from public.pms_housekeeping_gorevleri where id=v_g), gen_random_uuid());
  perform public.pms_housekeeping_baslat(v_g,
    (select surum from public.pms_housekeeping_gorevleri where id=v_g), gen_random_uuid());

  -- Oda 201: tamamlanmış görev -> `Kontrol` sekmesi dolu gelsin.
  perform set_config('request.jwt.claim.sub','a0000000-0000-0000-0000-0000000000a1',false);
  v_g := (public.pms_housekeeping_gorev_olustur(
    'e0000000-0000-0000-0000-0000000000a4'::uuid, 'ekstra_temizlik', 'bos',
    gen_random_uuid())->>'gorev_id')::uuid;
  perform set_config('request.jwt.claim.sub','a0000000-0000-0000-0000-0000000000a4',false);
  perform public.pms_housekeeping_sahiplen(v_g,
    (select surum from public.pms_housekeeping_gorevleri where id=v_g), gen_random_uuid());
  perform public.pms_housekeeping_baslat(v_g,
    (select surum from public.pms_housekeeping_gorevleri where id=v_g), gen_random_uuid());
  perform public.pms_housekeeping_tamamla(v_g,
    (select surum from public.pms_housekeeping_gorevleri where id=v_g), gen_random_uuid());

  -- OTEL 811'de bir görev: otel izolasyonu testi için.
  perform set_config('request.jwt.claim.sub','a0000000-0000-0000-0000-0000000000a3',false);
  perform public.pms_housekeeping_gorev_olustur(
    'e0000000-0000-0000-0000-0000000000a5'::uuid, 'ekstra_temizlik', 'bos', gen_random_uuid());
end $$;

select set_config('request.jwt.claim.sub','',false);
select set_config('request.jwt.claim.role','',false);

-- ---------------------------------------------------------------------------
-- 5) YALNIZ KAT HIZMETLERI yetkisi olan sef (PIN 777777)
--    Oda secici testinin konusu: pms_oda modul yetkisi YOK, buna karsin
--    kat hizmetleri tam. Gorev acabilmeli ve oda secebilmelidir.
-- ---------------------------------------------------------------------------
insert into public.roller (id, ad, seviye, kod, aktif) values
  ('b0000000-0000-0000-0000-0000000000a7','QA Kat Sefi (yalniz HK)','otel','qa_hk_only',true)
on conflict (id) do nothing;

insert into public.yetki_matrisi (rol_id, modul_id, yetki)
select 'b0000000-0000-0000-0000-0000000000a7', id, 'tam'
  from public.moduller where kod = 'pms_housekeeping'
on conflict do nothing;

insert into auth.users (id, email) values
  ('a0000000-0000-0000-0000-0000000000a7','qa-hk-only@ornek.gecersiz')
on conflict (id) do nothing;

insert into public.kullanicilar (id, auth_user_id, rol, rol_id, otel_id, aktif, tum_oteller, ad) values
  ('c0000000-0000-0000-0000-0000000000a7','a0000000-0000-0000-0000-0000000000a7',
   'yonetici','b0000000-0000-0000-0000-0000000000a7','810', true, false, 'QA Kat Sefi')
on conflict (id) do nothing;
