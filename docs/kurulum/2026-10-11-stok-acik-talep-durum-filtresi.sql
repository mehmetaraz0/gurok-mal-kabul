-- ============================================================================
-- DUZELTME MIGRATION — stok_acik_talep: DURUM FILTRESI
-- ============================================================================
-- Standart : docs/kurulum/MIGRATION-GUVENLIK-STANDARDI.md
-- Denetim  : node scripts/migration-guvenlik-kontrol.mjs docs/kurulum/2026-10-11-stok-acik-talep-durum-filtresi.sql
--
-- NEDEN BU DOSYA VAR
-- ------------------------------------------------------------------------
-- `2026-08-04-stok-tablo-viewlar.sql` (2026-10-10'da uretime uygulandi)
-- `stok_acik_talep` gorunumunu su filtreyle kurdu:
--
--   where t.siparis_no is null
--     and t.durum::text not in ('reddedildi','iptal','tamamlandi')
--
-- OLCULEN IKI KUSUR:
--
--  1) `'tamamlandi'` `talep_durum` enum'unda YOK. Etiketler: bekliyor,
--     siparise_donustu, iptal, bekleyen, onaylandi, reddedildi, siparis.
--     `::text` cast'i yuzunden hata vermiyor; terim sessizce HIC ESLESMIYOR.
--     Yani filtre, yazarinin sandigindan bir durum AZ disliyor.
--
--  2) Siparise donusmeyi anlatan IKI etiket (`siparise_donustu`, `siparis`)
--     dislanmiyor. Normalde `siparis_no is null` kontrolu bunlari kapsar,
--     ama durum "siparise dondu" derken `siparis_no` bos kalmis TUTARSIZ bir
--     satir ACIK TALEP sayilir. Gorunumun adi "acik talep"tir; boyle bir
--     satiri saymak sayiyi SISIRIR.
--
-- UYGULAMANIN GERCEK YASAM DONGUSU (koddan olculdu, tahmin degil)
-- ------------------------------------------------------------------------
-- `satin-alma-talepler.html` enum'un yedi etiketinden yalniz UCUNU yaziyor:
--   `bekleyen` (10 yer) -> `onaylandi` (3 yer) -> `siparis` (3 yer)
-- Tablonun varsayilani ise `bekliyor` (dokumde
-- `DEFAULT 'bekliyor'::public.talep_durum`), yani durum verilmeden olusan
-- eski/otomatik satirlar `bekliyor` tasir.
--   ACIK  talep: bekliyor, bekleyen, onaylandi
--   KAPALI talep: iptal, reddedildi, siparise_donustu, siparis
--
-- DUZELTME
-- ------------------------------------------------------------------------
-- Filtre AYNI BICIMDE (dislama listesi) kalir ki uygulanmis surumle farki
-- tek satirda okunabilsin; iceriği gercek etiketlerle duzeltilir ve `::text`
-- cast'i KALDIRILIR:
--
--   where t.siparis_no is null
--     and t.durum not in ('reddedildi','iptal','siparise_donustu','siparis')
--
-- `::text` kaldirilinca liste ENUM olarak dogrulanir: gelecekte yanlis yazilan
-- bir etiket SESSIZCE etkisiz kalmak yerine HATA verir. Bu bilincli bir
-- fail-loud secimidir — bu dosyanin varlik sebebi tam olarak o sessizlikti.
--
-- NEDEN YENI DOSYA, NEDEN ESKISI DUZELTILMEDI
-- ------------------------------------------------------------------------
-- Standardin 5. bolumu: uretime uygulanmis migration geriye donuk yeniden
-- yazilmaz; gercek bir kusur bulunursa YENI bir duzeltme migration'i yazilir.
-- `2026-08-04-stok-tablo-viewlar.sql` 2026-10-10'da uygulandi ve ozeti
-- (SHA-256 2DF4575B...) o anda dogrulandi; dosyaya dokunulmaz.
--
-- DAVRANIS DEGISIKLIGI — ACIKCA
-- ------------------------------------------------------------------------
-- Stok tablo gorunumundeki **Talep** sutunu, yalnizca `siparis_no is null`
-- olup durumu `siparise_donustu`/`siparis` olan TUTARSIZ satirlar varsa
-- DUSER. Boyle satirin uretimde bulunup bulunmadigi OLCULMEDI (uretim
-- parolasi ajanda degil). Hic yoksa sutun degismez; varsa sutun duzelir.
-- Asagidaki 3. bolum, uygulamadan once bu sayiyi RAPORLAR.
--
-- KAPSAM
-- ------------------------------------------------------------------------
-- TEK gorunumun `where` kosulu. Sutun listesi, `security_invoker`, izinler,
-- diger iki gorunum (`stok_acik_siparis`, `stok_son_hareket`) ve hicbir tablo
-- DEGISMEZ. Veri yazilmaz.
--
-- UYGULAMA
-- ------------------------------------------------------------------------
-- Bu dosya YAZILDI. Uretime uygulamak ayri onaya baglidir ("CANLIYA UYGULA").
-- Idempotenttir: `create or replace view`, birden fazla kez calistirilabilir.
--   .\docs\kurulum\sql-uygula.ps1 -Dosya docs\kurulum\2026-10-11-stok-acik-talep-durum-filtresi.sql
-- ============================================================================


-- ============================================================================
-- 0) ONKOSULLAR
-- ============================================================================
do $$
begin
  if to_regclass('public.stok_acik_talep') is null then
    raise exception 'ONKOSUL: stok_acik_talep gorunumu yok. Once '
      '2026-08-04-stok-tablo-viewlar.sql uygulanmali.';
  end if;

  if to_regtype('public.talep_durum') is null then
    raise exception 'ONKOSUL: talep_durum enum tipi yok.';
  end if;

  -- Dislama listesindeki her etiket GERCEKTEN var mi? Yoksa dur: sessiz
  -- etkisiz terim bu dosyanin duzeltmeye calistigi kusurun ta kendisidir.
  if exists (
    select 1 from unnest(array['reddedildi','iptal','siparise_donustu','siparis']) v(e)
     where not exists (
       select 1 from pg_enum en
        where en.enumtypid = 'public.talep_durum'::regtype
          and en.enumlabel = v.e)) then
    raise exception 'ONKOSUL: dislama listesinde talep_durum enum''unda '
      'bulunmayan etiket var; filtre sessizce etkisiz kalirdi.';
  end if;
end;
$$;


-- ============================================================================
-- 1) TRANSACTION
-- ============================================================================
begin;


-- ============================================================================
-- 2) GORUNUM — yalniz `where` kosulu degisti
-- ----------------------------------------------------------------------------
-- `security_invoker=true` ACIKCA yeniden yazilir: RLS otel kapsami ana
-- tablolardan gelmeye devam etsin. `create or replace view` mevcut izinleri
-- (authenticated SELECT) KORUR.
-- ============================================================================
create or replace view public.stok_acik_talep with (security_invoker=true) as
  select t.otel_id, tk.urun_kodu, sum(tk.miktar) as talep_miktar
  from public.satin_alma_talep_kalemleri tk
  join public.satin_alma_talepleri t on t.id = tk.talep_id
  where t.siparis_no is null
    and t.durum not in ('reddedildi','iptal','siparise_donustu','siparis')
  group by t.otel_id, tk.urun_kodu;

-- ACL KARARI ACIKCA (standart R10): `create or replace view` mevcut izinleri
-- korur, ama standart her dosyanin kararini KENDI yazmasini ister — "korunur"
-- varsayimi sessizce yanlis cikabilir. Son durum: cagiran YALNIZ authenticated.
-- `service_role` BILINCLI olarak dokunulmaz: hakki Supabase'in varsayilan
-- izinlerinden gelir ve sunucu tarafi akislar icin kasitlidir.
revoke all on public.stok_acik_talep from public, anon;
grant select on public.stok_acik_talep to authenticated;


-- ============================================================================
-- 3) DOGRULAMA ve ETKI RAPORU  (transaction icinde)
-- ============================================================================
do $$
declare
  v_tutarsiz bigint;
  v_satir    bigint;
begin
  -- Gorunum hala sorgulanabilir mi ve izin yerinde mi?
  if not has_table_privilege('authenticated', 'public.stok_acik_talep', 'SELECT') then
    raise exception 'DOGRULAMA BASARISIZ: authenticated SELECT hakki kayboldu.';
  end if;

  execute 'select count(*) from public.stok_acik_talep' into v_satir;

  -- Davranis degisikliginin BUYUKLUGU: filtreden yeni dusen satir sayisi.
  select count(*) into v_tutarsiz
    from public.satin_alma_talepleri t
   where t.siparis_no is null
     and t.durum in ('siparise_donustu','siparis');

  raise notice 'stok_acik_talep yeniden kuruldu. Gorunum satiri: %. '
               'Filtreden yeni dusen TUTARSIZ talep sayisi: % '
               '(0 ise Talep sutunu degismez).', v_satir, v_tutarsiz;
end;
$$;

commit;

notify pgrst, 'reload schema';


-- ============================================================================
-- GERI ALMA
-- ----------------------------------------------------------------------------
-- Uygulanmis 2026-08-04 surumune donmek icin (sessiz etkisiz terim geri
-- gelir; bilerek yapilmadikca onerilmez):
--
--   begin;
--   create or replace view public.stok_acik_talep with (security_invoker=true) as
--     select t.otel_id, tk.urun_kodu, sum(tk.miktar) as talep_miktar
--     from public.satin_alma_talep_kalemleri tk
--     join public.satin_alma_talepleri t on t.id = tk.talep_id
--     where t.siparis_no is null
--       and t.durum::text not in ('reddedildi','iptal','tamamlandi')
--     group by t.otel_id, tk.urun_kodu;
--   commit;
--   notify pgrst, 'reload schema';
--
-- Veri degismedigi icin baska geri alma adimi yoktur.
-- ============================================================================
