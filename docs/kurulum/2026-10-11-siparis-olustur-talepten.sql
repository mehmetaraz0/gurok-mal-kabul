-- ============================================================================
-- TALEPTEN SIPARIS OLUSTURMA — TEK TRANSACTION
-- Tasarim: docs/superpowers/specs/2026-10-11-talep-siparis-bagi-design.md §6
--
-- Siparis basligi + kalemleri + talep baglari AYNI transaction'da yazilir.
-- Yetki, otel, birim veya miktar kontrolu basarisizsa TAMAMI geri alinir:
-- bu yuzden her ret `raise exception` ile verilir. `return` ile ret VERILMEZ —
-- `return` transaction'i geri almaz ve o ana kadar yazilanlari birakir.
--
-- BU DOSYA YAZILDI, URETIME UYGULANMADI.
-- ============================================================================

do $$
begin
  if to_regprocedure('public.siparis_no_uret(text)') is null then
    raise exception 'ONKOSUL: siparis_no_uret yok.';
  end if;
  if to_regclass('public.talep_siparis_baglari') is null then
    raise exception 'ONKOSUL: talep_siparis_baglari yok.';
  end if;
  if not exists (select 1 from information_schema.columns
                  where table_schema='public' and table_name='siparisler'
                    and column_name='islem_anahtari') then
    raise exception 'ONKOSUL: siparisler.islem_anahtari yok.';
  end if;
end;
$$;

begin;

-- ---------------------------------------------------------------------------
-- Birim katsayisi: HEDEF daima talep kaleminin birimi. Cevrilemiyorsa NULL.
-- `1 buyuk_birim = carpan × urunler.birim` (urun basina TEK cift).
-- ---------------------------------------------------------------------------
create or replace function public.talep_bag_birim_kat(
  p_urun_kodu text, p_hedef_birim text, p_kaynak_birim text)
returns numeric
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $fn$
declare v_katalog text; v_buyuk text; v_carpan numeric;
begin
  if p_kaynak_birim is null or btrim(p_kaynak_birim) = '' then
    return null;
  end if;
  if p_kaynak_birim = p_hedef_birim then
    return 1;
  end if;
  if p_urun_kodu is null then
    return null;                        -- katalog yok -> yalniz ayni birim
  end if;

  select u.birim into v_katalog from public.urunler u where u.kod = p_urun_kodu;
  select d.buyuk_birim, d.carpan into v_buyuk, v_carpan
    from public.urun_birim_donusum d
   where d.urun_kodu = p_urun_kodu and d.silindi = false
   limit 1;
  if v_carpan is null or v_carpan <= 0 then
    return null;
  end if;

  if p_kaynak_birim = v_buyuk and p_hedef_birim = v_katalog then
    return v_carpan;                    -- KOL -> KG
  end if;
  if p_kaynak_birim = v_katalog and p_hedef_birim = v_buyuk then
    return 1 / v_carpan;                -- KG -> KOL
  end if;
  return null;
end;
$fn$;

revoke all on function public.talep_bag_birim_kat(text, text, text) from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- RPC
-- ---------------------------------------------------------------------------
create or replace function public.siparis_olustur_talepten(
  p_islem_anahtari text,
  p_talep_id       uuid,
  p_otel_id        text,
  p_firma_ad       text,
  p_cari_id        uuid,
  p_tarih          date,
  p_termin         date,
  p_satirlar       jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $fn$
declare
  v_talep      record;
  v_kalem      record;
  v_satir      jsonb;
  v_parmak     text;
  v_mevcut     record;
  v_siparis_no text;
  v_onek       text;
  v_kat        numeric;
  v_hedef      numeric;
  v_sayi       int := 0;
  v_tam        boolean;
  v_kalan      numeric;
  v_kimlik     text := coalesce(current_setting('request.jwt.claims', true)::jsonb->>'sub', 'rpc');
  v_ad         text;
  v_hazir      jsonb := '[]'::jsonb;
begin
  -- 1) YETKI — SECURITY DEFINER RLS'i atlar, kontrol burada yeniden uygulanir.
  if public.auth_yetki_var('siparis_olustur','kayit') is not true then
    raise exception 'yetkisiz: siparis_olustur kayit yetkisi gerekir' using errcode='42501';
  end if;

  -- 2) OTEL KAPSAMI
  if public.auth_otel_erisim(p_otel_id) is not true then
    raise exception 'otel_kapsami_disi: %', p_otel_id using errcode='42501';
  end if;

  -- `olusturan_ad` INSAN ADIDIR: siparis takip ekrani bu kolonu gosteriyor ve
  -- diger uc siparis yolu oraya `CU.ad` yaziyor. Eskiden buraya JWT `sub`
  -- UUID'si yaziliyordu; ekranda `3f2a...b901` gorunuyordu. Kimlik ise
  -- parmak izinin PARCASIDIR (bkz. 4. adim) — kullanici tarafindan
  -- guncellenebilen bir goruntuleme kolonunda tutulmaz.
  select k.ad into v_ad
    from public.kullanicilar k
   where k.auth_user_id = auth.uid() and k.aktif is true
   limit 1;
  v_ad := coalesce(nullif(btrim(coalesce(v_ad,'')), ''), 'rpc');

  -- 3) GIRDI DOGRULAMA (Review Focus 1, 4, 5)
  -- Anahtar dogrulamasi CHECK KISITIYLA BIREBIR ayni olmali. Eski hal alt
  -- siniri `btrim` uzerinden, ust siniri ham uzunluk uzerinden olcuyor ve
  -- `= btrim(...)` esitligini HIC kontrol etmiyordu: `' anahtar1 '` RPC'den
  -- geciyor, bir siparis numarasi TUKETILIYOR, sonra insert
  -- `siparisler_islem_anahtari_bicim` CHECK ihlaliyle dusuyordu (OLCULDU).
  if p_islem_anahtari is null
     or p_islem_anahtari <> btrim(p_islem_anahtari)
     or length(p_islem_anahtari) not between 8 and 100 then
    raise exception 'anahtar_gecersiz: islem anahtari bastan/sondan bosluksuz 8-100 karakter olmali'
      using errcode='22023';
  end if;
  if p_tarih is null then
    raise exception 'tarih_gecersiz: siparis tarihi zorunlu' using errcode='23514';
  end if;
  if p_termin is not null and p_termin < p_tarih then
    raise exception 'termin_gecersiz: termin (%) siparis tarihinden (%) once olamaz',
      p_termin, p_tarih using errcode='23514';
  end if;
  if p_satirlar is null or jsonb_typeof(p_satirlar) <> 'array'
     or jsonb_array_length(p_satirlar) = 0 then
    raise exception 'satir_yok: en az bir satir gerekir' using errcode='23514';
  end if;
  if exists (select 1 from jsonb_array_elements(p_satirlar) e
              where e->>'talep_kalem_id' is null
                 or (e->>'talep_kalem_id') !~ '^[0-9a-fA-F-]{36}$') then
    raise exception 'kalem_kimligi_gecersiz: her satirda gecerli talep_kalem_id olmali'
      using errcode='22023';
  end if;
  if exists (select 1 from jsonb_array_elements(p_satirlar) e
              where (e->>'miktar') is null
                 or (e->>'miktar') !~ '^[0-9]+(\.[0-9]+)?$') then
    raise exception 'miktar_gecersiz: miktar pozitif sayi olmali' using errcode='22023';
  end if;
  -- HASSASIYET (spec §6 kontrol 5): hedef kolonlar `numeric(12,3)`. Olculdu:
  -- kapi olmadan `10.0004` sessizce `10.000` yaziliyordu — kullanicinin
  -- girdigi sayi ne siparis kaleminde ne denetim izinde kaliyor. Sessiz
  -- yuvarlama yerine RET.
  if exists (select 1 from jsonb_array_elements(p_satirlar) e
              where (e->>'miktar') ~ '\.[0-9]{4,}$') then
    raise exception 'hassasiyet_asimi: miktar en fazla 3 ondalik hane olabilir'
      using errcode='22023';
  end if;
  if (select count(*) from (select distinct e->>'talep_kalem_id' k
                              from jsonb_array_elements(p_satirlar) e) d)
     <> jsonb_array_length(p_satirlar) then
    raise exception 'tekrarli_kalem: ayni talep kalemi birden fazla satirda'
      using errcode='23514';
  end if;

  -- 4) ICERIK PARMAK IZI (tekrar gonderme sozlesmesi)
  -- KIMLIK parmak izinin PARCASI: ayni anahtari baska bir kullanici ayni
  -- icerikle gonderirse parmak izi tutmaz ve `anahtar_celiskili` alir.
  -- Boylece "anahtar baskasina ait" kontrolu, kullanicinin
  -- degistirebilecegi `olusturan_ad` kolonuna bagimli olmaktan cikar.
  select md5(
    coalesce(v_kimlik,'') || '|' ||
    coalesce(p_talep_id::text,'') || '|' || coalesce(p_otel_id,'') || '|' ||
    coalesce(p_firma_ad,'') || '|' || coalesce(p_cari_id::text,'') || '|' ||
    coalesce(p_tarih::text,'') || '|' || coalesce(p_termin::text,'') || '|' ||
    coalesce(string_agg(x.k || ':' || x.m || ':' || x.b || ':' || x.f, ','
                        order by x.k), ''))
    into v_parmak
  from (select e->>'talep_kalem_id' k, (e->>'miktar')::numeric m,
               coalesce(e->>'birim','') b, coalesce(e->>'tahmini_fiyat','') f
          from jsonb_array_elements(p_satirlar) e) x;

  -- 5) MUKERRER GONDERIM
  select s.siparis_no, s.otel_id::text as otel_id, s.islem_parmak_izi, s.olusturan_ad
    into v_mevcut
    from public.siparisler s
   where s.islem_anahtari = p_islem_anahtari;
  if found then
    if v_mevcut.islem_parmak_izi is distinct from v_parmak then
      raise exception 'anahtar_celiskili: ayni anahtar farkli icerikle kullanilamaz'
        using errcode='23505';
    end if;
    if public.auth_otel_erisim(v_mevcut.otel_id) is not true then
      raise exception 'anahtar_celiskili: anahtar kapsam disinda' using errcode='23505';
    end if;
    -- "Baska kullaniciya ait" kontrolu artik parmak izinin icinde (4. adim):
    -- kimlik parmak izine giriyor, farkli kullanici farkli izdir ve yukaridaki
    -- celiski kapisi devreye girer. `olusturan_ad` kolonuna bakmak yanlisti —
    -- o kolon insan adi tasir ve sonradan degistirilebilir.
    return jsonb_build_object('ok', true, 'mukerrer', true,
                              'siparis_no', v_mevcut.siparis_no);
  end if;

  -- 6) TALEP — kilitle
  select t.id, t.otel_id::text as otel_id, t.durum::text as durum
    into v_talep
    from public.satin_alma_talepleri t
   where t.id = p_talep_id
   for update;
  if not found then
    raise exception 'talep_yok: %', p_talep_id using errcode='23503';
  end if;
  if v_talep.otel_id <> p_otel_id then
    raise exception 'otel_uyusmaz: talep oteli %, istek oteli %',
      v_talep.otel_id, p_otel_id using errcode='23514';
  end if;
  if v_talep.durum not in ('onaylandi','siparis') then
    raise exception 'onaylanmamis: talep durumu %', v_talep.durum using errcode='23514';
  end if;

  -- 7) DOGRULAMA + KILIT TURU — HENUZ HICBIR SEY YAZILMAZ.
  --
  -- SIRA BILINCLI (spec §6 kontrol 9): numara ureteci `siparis_no_sayac`
  -- satir kilidini transaction SONUNA kadar tutar. Numara ONCE uretilirse bu
  -- RPC bir talep kalemi kilidinde beklerken SISTEMDEKI TUM siparis numarasi
  -- uretimi (dort yolun hepsi) o sure boyunca bloke olur. Bu yuzden butun
  -- kalem kilitleri ve dogrulamalar once alinir, numara en sonda uretilir.
  --
  -- Kilit sirasi UUID sirasina gore SABIT. Metin siralamasi yeterli DEGIL:
  -- `talep_kalem_id` buyuk/kucuk harf karisik gelebilir ve metinde
  -- 'C' (0x43) < 'a' (0x61) oldugu icin iki oturum ayni iki kalemi TERS
  -- sirada kilitleyip deadlock uretebilir.
  for v_satir in select e from jsonb_array_elements(p_satirlar) e
                  order by (e->>'talep_kalem_id')::uuid loop
    select tk.id, tk.miktar, tk.birim, tk.urun_kodu, tk.urun_adi
      into v_kalem
      from public.satin_alma_talep_kalemleri tk
     where tk.id = (v_satir->>'talep_kalem_id')::uuid
       and tk.talep_id = p_talep_id
     for update;
    if not found then
      raise exception 'kalem_yok: % bu talebe ait degil', v_satir->>'talep_kalem_id'
        using errcode='23503';
    end if;

    -- BIRIM: hedef daima talep kaleminin birimi (dondurulur).
    v_kat := public.talep_bag_birim_kat(v_kalem.urun_kodu, v_kalem.birim,
                                        coalesce(v_satir->>'birim', v_kalem.birim));
    if v_kat is null then
      raise exception 'birim_cevrilemez: kalem % (%), siparis birimi %',
        v_kalem.id, v_kalem.birim, coalesce(v_satir->>'birim','<bos>')
        using errcode='23514';
    end if;

    v_hedef := round((v_satir->>'miktar')::numeric * v_kat, 3);
    if v_hedef <= 0 then
      raise exception 'miktar_gecersiz: yuvarlama sonrasi miktar sifir (kalem %)',
        v_kalem.id using errcode='23514';
    end if;

    -- INV (kullaniciya anlasilir mesaj; tetikleyici de ayrica korur)
    select v_kalem.miktar - coalesce(sum(b.miktar), 0) into v_kalan
      from public.talep_siparis_baglari b
      join public.siparisler s on s.siparis_no = b.siparis_no
     where b.talep_kalem_id = v_kalem.id and s.durum <> 'iptal'
       and b.hedef_birim = v_kalem.birim;
    if v_hedef > v_kalan then
      raise exception 'miktar_asimi: kalem %, kalan % %, istenen % %',
        v_kalem.id, v_kalan, v_kalem.birim, v_hedef, v_kalem.birim
        using errcode='23514';
    end if;

    v_hazir := v_hazir || jsonb_build_object(
      'kalem_id',     v_kalem.id,
      'urun_kodu',    v_kalem.urun_kodu,
      'urun_adi',     v_kalem.urun_adi,
      'hedef',        v_hedef,
      'hedef_birim',  v_kalem.birim,
      'kaynak',       (v_satir->>'miktar')::numeric,
      'kaynak_birim', coalesce(v_satir->>'birim', v_kalem.birim),
      'carpan',       nullif(v_kat, 1),
      'fiyat',        nullif(v_satir->>'tahmini_fiyat',''));
    v_sayi := v_sayi + 1;
  end loop;

  -- 8) NUMARA — otel onekinden (Club/Resort). Tum kalem kilitleri ALINDIKTAN
  -- sonra: kuresel sayac kilidi mumkun olan en kisa sure tutulur.
  v_onek := case when p_otel_id = '810' then 'C' else 'R' end;
  v_siparis_no := public.siparis_no_uret(v_onek);

  -- 9) BASLIK — eszamanli ayni anahtar sozlesmesi (spec §6.1 son satir).
  -- Iki istek ayni anahtarla paralel gelirse ikisi de 5. adimda anahtari
  -- bulamaz; kaybeden `unique_violation` alir. Sozlesme ham "duplicate key"
  -- hatasi DEGIL `{ok:true, mukerrer:true}` gerektirir — idempotency'nin
  -- varlik sebebi tam olarak bu durumdur. YALNIZ
  -- `siparisler_islem_anahtari_key` ihlali mukerrer sayilir; PK veya baska
  -- kisit ihlali oldugu gibi yukselir.
  begin
    insert into public.siparisler
      (siparis_no, cari_id, firma_ad, otel_id, tarih, termin_tarihi, durum, tip,
       kaynak, olusturan_ad, islem_anahtari, islem_parmak_izi)
    values (v_siparis_no, p_cari_id, coalesce(p_firma_ad,''), p_otel_id::public.otel_id,
            p_tarih, p_termin, 'bekleyen', 'normal', 'talep',
            v_ad, p_islem_anahtari, v_parmak);
  exception when unique_violation then
    if sqlerrm not like '%siparisler_islem_anahtari_key%' then
      raise;
    end if;
    select s.siparis_no, s.otel_id::text as otel_id, s.islem_parmak_izi
      into v_mevcut
      from public.siparisler s
     where s.islem_anahtari = p_islem_anahtari;
    if not found then
      raise;                      -- ihlal bizim anahtarimizdan degil: yukselt
    end if;
    if v_mevcut.islem_parmak_izi is distinct from v_parmak
       or public.auth_otel_erisim(v_mevcut.otel_id) is not true then
      raise exception 'anahtar_celiskili: ayni anahtar farkli icerikle kullanilamaz'
        using errcode='23505';
    end if;
    return jsonb_build_object('ok', true, 'mukerrer', true,
                              'siparis_no', v_mevcut.siparis_no);
  end;

  -- 10) KALEMLER + BAGLAR — dogrulanmis satirlar, dogrulama turundaki sirada.
  for v_satir in select e from jsonb_array_elements(v_hazir) e loop
    insert into public.siparis_kalemleri
      (siparis_no, urun_kodu, urun_adi, birim, miktar, gelen_miktar, kalan_miktar,
       tahmini_fiyat)
    values (v_siparis_no, v_satir->>'urun_kodu', v_satir->>'urun_adi',
            v_satir->>'kaynak_birim',
            (v_satir->>'kaynak')::numeric, 0, (v_satir->>'kaynak')::numeric,
            (v_satir->>'fiyat')::numeric);

    insert into public.talep_siparis_baglari
      (otel_id, talep_id, talep_kalem_id, siparis_no, urun_kodu, miktar, hedef_birim,
       kaynak_miktar, kaynak_birim, carpan, olusturan_ad)
    values (p_otel_id::public.otel_id, p_talep_id, (v_satir->>'kalem_id')::uuid,
            v_siparis_no, v_satir->>'urun_kodu',
            (v_satir->>'hedef')::numeric, v_satir->>'hedef_birim',
            (v_satir->>'kaynak')::numeric, v_satir->>'kaynak_birim',
            (v_satir->>'carpan')::numeric, v_ad);
  end loop;

  -- 11) TAM KARSILAMA -> talep durumu
  select not exists (
    select 1 from public.satin_alma_talep_kalemleri tk
     where tk.talep_id = p_talep_id
       and tk.miktar > coalesce((select sum(b.miktar) from public.talep_siparis_baglari b
                                   join public.siparisler s on s.siparis_no = b.siparis_no
                                  where b.talep_kalem_id = tk.id and s.durum <> 'iptal'
                                    and b.hedef_birim = tk.birim), 0))
    into v_tam;
  if v_tam then
    update public.satin_alma_talepleri set durum = 'siparis' where id = p_talep_id;
  end if;

  return jsonb_build_object('ok', true, 'mukerrer', false,
    'siparis_no', v_siparis_no, 'yazilan_kalem', v_sayi,
    'baglanan_kalem', v_sayi, 'tam_karsilandi', v_tam);
end;
$fn$;

revoke all on function public.siparis_olustur_talepten(text, uuid, text, text, uuid, date, date, jsonb) from public, anon;
revoke all on function public.siparis_olustur_talepten(text, uuid, text, text, uuid, date, date, jsonb) from service_role;
grant execute on function public.siparis_olustur_talepten(text, uuid, text, text, uuid, date, date, jsonb) to authenticated;

commit;

notify pgrst, 'reload schema';

-- ============================================================================
-- GERI ALMA
--   begin;
--   drop function if exists public.siparis_olustur_talepten(text, uuid, text, text, uuid, date, date, jsonb);
--   drop function if exists public.talep_bag_birim_kat(text, text, text);
--   commit;
-- Istemci bu RPC'ye gectikten sonra geri alinirsa talepten siparis olusturma
-- kirilir; istemci degisikligi de geri alinmalidir.
-- ============================================================================
