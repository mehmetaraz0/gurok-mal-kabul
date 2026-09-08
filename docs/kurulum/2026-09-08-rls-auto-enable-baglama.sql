-- ============================================================================
-- rls_auto_enable() EVENT TRIGGER'A BAĞLANMASI
-- Tarih: 2026-09-08
--
-- ÖNCE SONDAYI ÇALIŞTIR: `2026-09-08-event-trigger-yetki-sondasi.sql`
-- Sonda "PLATFORM SINIRI" derse bu dosyayı çalıştırma — reddedilecektir.
--
-- ÜRETİME UYGULAMA: `CANLIYA UYGULA` onayı olmadan çalıştırılmaz.
--
-- ---------------------------------------------------------------------------
-- SORUN
--   `public.rls_auto_enable()` üretimde MEVCUT (post-PMS şema dökümü, satır
--   2238) ama onu bir DDL olayına bağlayan `CREATE EVENT TRIGGER` hiç
--   çalıştırılmamış. Güvenlik ağı kurulmuş, fişe takılmamış.
--
--   İlk kez 2026-07-22 RLS denetiminde kök neden olarak işaretlendi. Bu süre
--   içinde eklenen tablolarda aynı sınıf hata tekrar üretildi
--   (`urun_birim_donusum`, `gelen_efaturalar`).
--
--   2026-09-08 varsayılan ACL bulgusu bunun önemini artırdı: `supabase_admin`
--   `public` şemasında bir tablo yaratırsa o tablo `anon` hakkıyla DOĞAR ve
--   RLS'i biz açmayız. Event trigger, o senaryoda kalan tek otomatik savunma.
--
-- NE YAPAR, NE YAPMAZ
--   YAPAR : `public` şemasında yaratılan her yeni tabloda RLS'i açar.
--   YAPMAZ: politika EKLEMEZ.
--
--   Yani yeni tablo "RLS açık + 0 politika" = herkese kapalı doğar. Bu
--   GÜVENLİ başarısızlık yönüdür (veri sızmaz) ama SESSİZDİR: ekran hata
--   vermez, boş gelir. "RLS açmayı unutma" hatasını kapatır, "politika
--   yazmayı unutma" hatasını KAPATMAZ.
--
-- ETKİ UYARISI
--   Bağlandıktan sonra `public` şemasında tablo yaratan HER yol etkilenir —
--   `create table as` ve `select into` dâhil. Bir kod yolu `public` içinde
--   geçici bir tablo yaratıp hemen `authenticated` olarak okuyorsa, o okuma
--   BOŞ dönmeye başlar. Bilinen böyle bir yol yok (uygulama kodu tablo
--   yaratmaz, migration'lar politikayı kendisi ekler), ama bir regresyon
--   görülürse ilk bakılacak yer burasıdır.
--
-- NEDEN `EXCEPTION` İLE SARILMADI
--   Bilerek. Phase 0'ın `supabase_admin` revoke'u `exception when
--   insufficient_privilege` dalına alınmıştı, sessizce başarısız oldu ve
--   üç gün sonra ölçümle ortaya çıktı. Bu dosya yetki yoksa GÜRÜLTÜYLE
--   patlar ve transaction geri döner. Yarım uygulanmış bir durum kalmaz.
--
-- Standart: docs/kurulum/MIGRATION-GUVENLIK-STANDARDI.md
-- Öncül   : docs/kurulum/2026-09-01-rls-auto-enable-baglama.sql (analiz)
-- ============================================================================


-- ============================================================================
-- 0) ÖN KOŞULLAR
-- ============================================================================
do $$
declare v_oid oid;
begin
  select p.oid into v_oid
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'rls_auto_enable';

  if v_oid is null then
    raise exception 'ONKOSUL: public.rls_auto_enable() yok.';
  end if;

  if (select prorettype from pg_proc where oid = v_oid) <> 'event_trigger'::regtype then
    raise exception 'ONKOSUL: rls_auto_enable() event_trigger dondurmuyor.';
  end if;

  -- SECURITY DEFINER + pinli search_path olmadan bu fonksiyon her CREATE TABLE
  -- olayinda calisan bir saldiri yuzeyi olurdu.
  if not (select prosecdef from pg_proc where oid = v_oid) then
    raise exception 'ONKOSUL: rls_auto_enable() SECURITY DEFINER degil.';
  end if;

  if not exists (select 1 from pg_proc p, unnest(p.proconfig) k
                  where p.oid = v_oid and k like 'search_path=%') then
    raise exception 'ONKOSUL: rls_auto_enable() search_path pinli degil.';
  end if;
end;
$$;


begin;


-- ============================================================================
-- 1) BAĞLAMA
--
--    `create event trigger`in `if not exists` biçimi YOKTUR; varlık kontrolü
--    elle yapılır. Yetki yoksa buradaki `execute` "permission denied to
--    create event trigger" ile PATLAR ve transaction geri döner — istenen
--    davranış budur.
-- ============================================================================
do $$
begin
  if exists (select 1 from pg_event_trigger where evtname = 'rls_auto_enable_trg') then
    raise notice 'rls_auto_enable_trg zaten var; atlandi.';
    return;
  end if;

  execute $ddl$
    create event trigger rls_auto_enable_trg
      on ddl_command_end
      when tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      execute function public.rls_auto_enable()
  $ddl$;

  raise notice 'rls_auto_enable_trg olusturuldu.';
end;
$$;


-- ============================================================================
-- 2) DOĞRULAMA — COMMIT'TEN ÖNCE
--
--    "Oluştu" yetmez: bağlı VE AÇIK olmalı. Devre dışı bir event trigger
--    (`evtenabled = 'D'`) katalogda görünür ama hiçbir şey yapmaz — tam
--    olarak bu dosyanın kapatmaya çalıştığı "kurulmuş ama çalışmıyor"
--    durumunun bir başka biçimi.
-- ============================================================================
do $$
declare v record;
begin
  select e.evtname, e.evtenabled, e.evtevent, e.evtfoid::regprocedure::text as fn
    into v
    from pg_event_trigger e
   where e.evtname = 'rls_auto_enable_trg';

  if v is null then
    raise exception 'DOGRULAMA: rls_auto_enable_trg olusmadi';
  end if;

  if v.evtenabled <> 'O' then
    raise exception 'DOGRULAMA: rls_auto_enable_trg devre disi (evtenabled=%)', v.evtenabled;
  end if;

  if v.fn <> 'public.rls_auto_enable()' then
    raise exception 'DOGRULAMA: yanlis fonksiyona bagli: %', v.fn;
  end if;

  if v.evtevent <> 'ddl_command_end' then
    raise exception 'DOGRULAMA: yanlis olay: %', v.evtevent;
  end if;

  raise notice 'DOGRULAMA gecti: % / % / %', v.evtname, v.evtevent, v.fn;
end;
$$;


commit;


-- ============================================================================
-- 3) CANLI TEST — commit'ten SONRA, ayrı çalıştırılır
-- ----------------------------------------------------------------------------
-- Katalogda görünmesi ağın ÇALIŞTIĞINI kanıtlamaz. Tek kanıt, gerçekten bir
-- tablo yaratıp RLS'in kendiliğinden açıldığını görmektir.
--
-- Bu bir ÜRETİM YAZMASIDIR (create + drop). Ayrı onay ister. Tercihen önce
-- yerel staging'de çalıştırılır.
--
--   create table public.zzz_rls_agi_testi (id int);
--
--   select relname, relrowsecurity as rls_acik
--     from pg_class where relname = 'zzz_rls_agi_testi';
--   --> rls_acik TRUE donmeli. FALSE donerse ag KURULU AMA CALISMIYOR.
--
--   drop table public.zzz_rls_agi_testi;
--
-- Temizliği unutma: `zzz_` önekli bir tablo üretimde kalmamalı.
-- ============================================================================


-- ============================================================================
-- 4) GERİ ALMA
-- ----------------------------------------------------------------------------
--   drop event trigger if exists rls_auto_enable_trg;
--
-- Geri alma güvenlidir ve anlıktır: yalnız ağı söker, hiçbir tablonun mevcut
-- RLS durumunu değiştirmez. Ağın açtığı RLS'ler açık kalır.
--
-- Bir regresyonda (bir kod yolunun yarattığı tablo boş dönüyor) önce
-- `evtenabled` ile devre dışı bırakmak da yeterlidir:
--   alter event trigger rls_auto_enable_trg disable;
-- ============================================================================


-- ============================================================================
-- 5) KAPSAM SINIRI — bu ağın YAKALAMADIĞI
-- ----------------------------------------------------------------------------
-- 1. Yalnız `public` şeması. `phase0_private` kapsam dışı (o şemadaki
--    nesneler zaten kasıtlı ve dar; oraya erişim rol düzeyinde kapalı).
-- 2. GEÇMİŞ tablolar. Ağ yalnız yeni `CREATE TABLE` olaylarında çalışır;
--    hâlihazırda RLS'i kapalı bir tablo varsa onu AÇMAZ. Sonda sorgu 5 bu
--    sayıyı ölçer; 0 olmalıdır.
-- 3. Politika eksikliği. Yukarıda anlatıldı.
-- ============================================================================
