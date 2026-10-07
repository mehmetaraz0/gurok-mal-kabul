-- ===========================================================================
-- PMS — Ön Büro modül ve yetki tohumlaması (BİRİNCİ PAKET)
-- ===========================================================================
-- Kapsam: BEŞ Ön Büro modülü × ÜÇ Ön Büro rolü = 15 yetki satırı.
--   Modüller : pms_oda_tipi, pms_oda, pms_misafir, pms_rezervasyon, pms_folio
--   Roller   : onburo_sef, onburo_vardiya, onburo_personel
--
-- KAPSAM DIŞI (bu dosya bunlara DOKUNMAZ):
--   pms_housekeeping  — modül aktif=false doğuyor ve temiz kurulumun şema
--                       dökümünde pms_housekeeping_gorevleri tablosu yok
--   kat_sef / kat_vardiya / kat_personel  — housekeeping ile birlikte ayrı paket
--   pms_misafir_kimlik — KVKK; AYRI KARAR, bu dosyada yetki verilmez
--
-- Mevcut yetkileri DEĞİŞTİRMEZ: tüm eklemeler `on conflict do nothing`.
-- Pasif bırakılmış bir modülü AKTİFLEŞTİRMEZ; durur ve raporlar (PMS-S4).
-- Açık bakiye iş kuralına, otel kapsamına ve RLS politikalarına dokunmaz.
--
-- Geri alma: 2026-10-05-pms-onburo-modul-tohumlama-geri-al.sql
--   Geri alma SABİT ÇİFT LİSTESİ KULLANMAZ. Bu dosya eklediği her satırı
--   `guncelleyen` damgasıyla imzalar; geri alma yalnız o damgayı taşıyan ve
--   sonradan DEĞİŞTİRİLMEMİŞ satırları kaldırır.
--
-- ÇALIŞTIRMA: dosyanın tamamını olduğu gibi verin (psql -f, psql < dosya veya
-- SQL Editor'e yapıştırma). Seçim satırı `begin;`ten SONRA olduğu için dışarıdan
-- bir işlemle sarmaya GEREK YOKTUR (PMS-S1).
-- ===========================================================================

begin;

-- --- K1 KARARI — kullanıcı seçimi gerekir ---------------------------------
-- `onburo_personel` folyo/tahsilat kaydı girebilsin mi?
-- `kayit`, tahsilatın yanında folyo hareketi, oda ücreti işleme ve folyo
-- kapatma yetkilerini de kapsar; `yok` bunlara erişim vermez.
--
-- Aşağıdaki İKİ satırdan BİRİNİ açın (başındaki `--` işaretini silin):

--   set local app.pms_k1 = 'kayit';   -- A) personel folyo kaydı/tahsilat GİREBİLİR
--   set local app.pms_k1 = 'yok';     -- B) personel folyoya ERİŞMEZ (açık 'yok' satırı)
--
-- ONAYLI KARAR (2026-10-06): secenek **A** (kayit). Karar kaydi:
--   2026-10-06-PMS-mali-islem-yetkileri-onayli-tasarim.md
-- Satır yine ELLE açılmalıdır; sessiz varsayılan yoktur.
--
-- YAYIN BAĞIMLILIĞI: bu paket `onburo_vardiya` ve `onburo_sef` için folyo
-- yazma yetkisini HER İKİ K1 seçeneğinde de açar; A seçeneğinde personel de
-- eklenir. Bu yüzden ön koşul K1'den bağımsızdır: mali işlem ayrımı kuralı
-- (2026-10-06-pms-folio-mali-yetki-ayrimi.sql) ÖNCE kurulmuş olmalıdır.
-- Kural yoksa dosya HER İKİ seçenekte de durur ve hiçbir satır yazmaz.

-- Seçim yapılmazsa bu dosya hiçbir şey yazmadan HATA verir.

do $$
declare
  v_k1       text := current_setting('app.pms_k1', true);
  v_zaman    timestamptz := clock_timestamp();
  v_id       uuid := gen_random_uuid();
  v_damga    text;
  v_eksik    text;
  v_pasif    text;
  v_catisma  text;
  v_eklenen  int;
begin
  -- --- K1 kapısı ----------------------------------------------------------
  if v_k1 is null or v_k1 not in ('kayit','yok') then
    raise exception
      'K1 KARARI VERILMEDI. Dosyadaki (begin sonrasi) iki satirdan BIRINI acin: '
      '"set local app.pms_k1 = ''kayit'';" (personel folyo girebilir) veya '
      '"set local app.pms_k1 = ''yok'';" (personel folyoya erismez). '
      'Hicbir satir yazilmadi.'
      using errcode = '22023';
  end if;

  -- Damga: geri alma bunu kullanir. Icinde uygulama kimligi, uygulama zamani
  -- ve yazilan seviye durur; boylece geri alma sabit bir cift listesine
  -- ihtiyac duymaz ve sonradan degistirilmis satiri ayirt eder.
  v_damga := 'tohum:pms-onburo:' || v_id::text || '@'
             || to_char(v_zaman, 'YYYY-MM-DD"T"HH24:MI:SS.USOF');

  -- --- 1) Modül satırları -------------------------------------------------
  -- Migration'larla AYNI kod/ad/kategori/sıra. Çakışırsa dokunulmaz.
  insert into public.moduller (kod, ad, kategori, sira, aktif) values
    ('pms_oda_tipi',    'Ön Büro — Oda Tipleri',            'onburo', 43, true),
    ('pms_oda',         'Ön Büro — Odalar',                 'onburo', 44, true),
    ('pms_misafir',     'Ön Büro — Misafirler',             'onburo', 45, true),
    ('pms_rezervasyon', 'Ön Büro — Rezervasyonlar',         'onburo', 47, true),
    ('pms_folio',       'Ön Büro — Misafir Hesabı (Folio)', 'onburo', 48, true)
  on conflict (kod) do nothing;

  -- --- 2) Hedef küme ------------------------------------------------------
  create temporary table pms_hedef (rol text, modul text, yetki text)
    on commit drop;
  insert into pms_hedef values
    ('onburo_sef',      'pms_oda_tipi',    'tam'),
    ('onburo_sef',      'pms_oda',         'tam'),
    ('onburo_sef',      'pms_misafir',     'tam'),
    ('onburo_sef',      'pms_rezervasyon', 'tam'),
    ('onburo_sef',      'pms_folio',       'tam'),
    ('onburo_vardiya',  'pms_oda_tipi',    'goruntule'),
    ('onburo_vardiya',  'pms_oda',         'kayit'),
    ('onburo_vardiya',  'pms_misafir',     'kayit'),
    ('onburo_vardiya',  'pms_rezervasyon', 'kayit'),
    ('onburo_vardiya',  'pms_folio',       'kayit'),
    ('onburo_personel', 'pms_oda_tipi',    'goruntule'),
    ('onburo_personel', 'pms_oda',         'goruntule'),
    ('onburo_personel', 'pms_misafir',     'kayit'),
    ('onburo_personel', 'pms_rezervasyon', 'kayit'),
    ('onburo_personel', 'pms_folio',       v_k1);     -- K1 kararı

  -- --- YAYIN BAĞIMLILIĞI — K1'e DEĞİL, açılacak YETKİLERE bağlı ----------
  -- MY-1: K1 yalnız personelin folyo hakkını seçer; `onburo_vardiya` HER İKİ
  -- seçenekte de `pms_folio=kayit` alır. Bu yüzden ön koşul K1 değişkenine
  -- değil, bu koşumda gerçekten yazma yetkisi verilen folyo satırlarına
  -- bağlanır: hedef kümede `pms_folio` için `kayit` veya `tam` varsa, mali
  -- ayrım kuralı kurulu olmalıdır.
  if exists (select 1 from pms_hedef
              where modul = 'pms_folio' and yetki in ('kayit','tam')) then
    if not exists (
      select 1 from pg_trigger t join pg_class c on c.oid = t.tgrelid
       where c.relname = 'pms_folio_hareketleri'
         and t.tgname = 'pms_folio_hassas_kapi' and not t.tgisinternal
    ) or not exists (
      select 1 from pg_trigger t join pg_class c on c.oid = t.tgrelid
       where c.relname = 'pms_folio_odemeler'
         and t.tgname = 'pms_folio_hassas_kapi' and not t.tgisinternal
    ) then
      raise exception
        'MALI_AYRIM_KURALI_YOK: bu paket folyoya YAZMA yetkisi aciyor (K1=%), bu da '
        'iade/indirim/duzeltme ayrimini zorunlu kilan sunucu kuralini ON KOSUL '
        'yapar. Once 2026-10-06-pms-folio-mali-yetki-ayrimi.sql uygulanmalidir. '
        'Hicbir satir yazilmadi.', v_k1
        using errcode = '23514';
    end if;
  end if;

  -- --- 3) Eksik rol/modül SESSİZCE GEÇİLMEZ -------------------------------
  select string_agg(distinct x, ', ' order by x) into v_eksik from (
    select 'rol yok: ' || h.rol as x from pms_hedef h
      left join public.roller r on r.kod = h.rol where r.id is null
    union all
    select 'modul yok: ' || h.modul from pms_hedef h
      left join public.moduller m on m.kod = h.modul where m.id is null
  ) s;
  if v_eksik is not null then
    raise exception 'EKSIK REFERANS, hicbir satir yazilmadi: %', v_eksik
      using errcode = '23503';
  end if;

  -- --- 4) PASİF hedef modül SESSİZCE GEÇİLMEZ (PMS-S4) --------------------
  -- `auth_yetki_var` `m.aktif is true` istiyor ve `auth-guard.js:48` pasif
  -- modülü yetki haritasına hiç koymuyor. Mevcut satır pasifse `on conflict
  -- do nothing` onu aktifleştirmez; kurulum "başarılı" görünürken modül
  -- kullanılamaz kalır. Pasife alma BAŞKASININ KARARI olabileceği için
  -- otomatik aktifleştirilmez: durulur ve raporlanır.
  select string_agg(distinct m.kod, ', ' order by m.kod) into v_pasif
  from pms_hedef h join public.moduller m on m.kod = h.modul
  where m.aktif is not true;
  if v_pasif is not null then
    raise exception
      'PASIF MODUL, hicbir satir yazilmadi. Bu modul(ler) aktif degil ve bu dosya '
      'baskasinin pasife alma kararini DEGISTIRMEZ; menu ve RLS kapali kalacagi '
      'icin durduruldu: %. Once aktiflestirme kararini verin.', v_pasif
      using errcode = '23514';
  end if;

  -- --- 5) Çelişen MEVCUT yetki SESSİZCE GEÇİLMEZ --------------------------
  select string_agg(h.rol || '/' || h.modul || ': mevcut=' || ym.yetki::text
                    || ' hedef=' || h.yetki, ', ' order by h.rol, h.modul)
    into v_catisma
  from pms_hedef h
  join public.roller   r  on r.kod = h.rol
  join public.moduller m  on m.kod = h.modul
  join public.yetki_matrisi ym on ym.rol_id = r.id and ym.modul_id = m.id
  where ym.yetki::text <> h.yetki;
  if v_catisma is not null then
    raise exception
      'CELISEN MEVCUT YETKI, hicbir satir yazilmadi. Mevcut yetkiler bu paketle '
      'DEGISTIRILMEZ; karar tablosuyla uyusmadigi icin durduruldu: %', v_catisma
      using errcode = '23505';
  end if;

  -- --- 6) Yetki satırları -------------------------------------------------
  with eklenen as (
    insert into public.yetki_matrisi (rol_id, modul_id, yetki, guncelleyen, guncelleme_tarihi)
    select r.id, m.id, (h.yetki)::public.yetki_seviye, v_damga || '#' || h.yetki, v_zaman
    from pms_hedef h
    join public.roller   r on r.kod = h.rol
    join public.moduller m on m.kod = h.modul
    on conflict (rol_id, modul_id) do nothing
    returning 1
  )
  select count(*) into v_eklenen from eklenen;

  raise notice 'PMS On Buro tohumlama: uygulama_id=% K1=% eklenen_yetki_satiri=%/15',
    v_id, v_k1, v_eklenen;
  raise notice 'GERI ALMA ICIN UYGULAMA KIMLIGI: %', v_id;
end $$;

commit;

-- --- Doğrulama sorgusu (koşum sonrası) ------------------------------------
-- select r.kod, m.kod, ym.yetki, ym.guncelleyen
--   from public.yetki_matrisi ym
--   join public.roller r   on r.id = ym.rol_id
--   join public.moduller m on m.id = ym.modul_id
--  where m.kod in ('pms_oda_tipi','pms_oda','pms_misafir','pms_rezervasyon','pms_folio')
--    and r.kod in ('onburo_sef','onburo_vardiya','onburo_personel')
--  order by r.kod, m.kod;
