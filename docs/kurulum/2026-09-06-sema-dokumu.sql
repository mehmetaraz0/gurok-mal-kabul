--
-- PostgreSQL database dump
--

\restrict rxsePyxW4hPQdRiywqyGdxOFIk7sz6iafhvnN8SnFQ8gERuKQGuIjttjbTi1Z4k

-- Dumped from database version 17.6
-- Dumped by pg_dump version 17.11 (Debian 17.11-1.pgdg13+2)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: phase0_private; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA phase0_private;


--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA public;


--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- Name: bar_durum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.bar_durum AS ENUM (
    'yeni',
    'hazirlaniyor',
    'hazir',
    'teslim_edildi',
    'iptal'
);


--
-- Name: cari_tip; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.cari_tip AS ENUM (
    'tedarikci',
    'musteri',
    'her_ikisi'
);


--
-- Name: cek_senet_durum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.cek_senet_durum AS ENUM (
    'portfoyde',
    'tahsilde',
    'tamamlandi',
    'karsiliksiz'
);


--
-- Name: cek_senet_tur; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.cek_senet_tur AS ENUM (
    'cek',
    'senet'
);


--
-- Name: cek_senet_yon; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.cek_senet_yon AS ENUM (
    'alinan',
    'verilen'
);


--
-- Name: demirbas_durum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.demirbas_durum AS ENUM (
    'aktif',
    'elden_cikarildi'
);


--
-- Name: demirbas_kategori; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.demirbas_kategori AS ENUM (
    'demirbas',
    'bilgisayar',
    'tesis_makine',
    'tasit',
    'bina',
    'haklar'
);


--
-- Name: fatura_durum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.fatura_durum AS ENUM (
    'taslak',
    'bekliyor',
    'onaylandi',
    'odendi',
    'iptal',
    'kismi_odendi'
);


--
-- Name: fatura_tur; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.fatura_tur AS ENUM (
    'alis',
    'satis'
);


--
-- Name: hareket_tip; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.hareket_tip AS ENUM (
    'borc',
    'alacak',
    'iade',
    'mahsup',
    'acilis'
);


--
-- Name: hesap_tip; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.hesap_tip AS ENUM (
    'Bilanço',
    'Gelir Tablosu',
    'Maliyet',
    'Nazım'
);


--
-- Name: hesap_yon; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.hesap_yon AS ENUM (
    'Borç',
    'Alacak',
    'İkisi de'
);


--
-- Name: kullanici_rol; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.kullanici_rol AS ENUM (
    'depo',
    'satinalma',
    'kalite',
    'yonetici',
    'mutfak',
    'bar',
    'muhasebe_muduru',
    'muhasebe_calisani',
    'cost_control'
);


--
-- Name: mal_kabul_durum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.mal_kabul_durum AS ENUM (
    'bekleyen',
    'onaylandi',
    'iptal',
    'arsivlendi'
);


--
-- Name: otel_id; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.otel_id AS ENUM (
    '810',
    '811'
);


--
-- Name: rezervasyon_durum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.rezervasyon_durum AS ENUM (
    'aktif',
    'serbest',
    'kullanildi'
);


--
-- Name: rol_seviye; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.rol_seviye AS ENUM (
    'grup',
    'otel'
);


--
-- Name: talep_durum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.talep_durum AS ENUM (
    'bekliyor',
    'siparise_donustu',
    'iptal',
    'bekleyen',
    'onaylandi',
    'reddedildi',
    'siparis'
);


--
-- Name: uygunsuzluk_durum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.uygunsuzluk_durum AS ENUM (
    'acik',
    'kapatildi'
);


--
-- Name: yetki_seviye; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.yetki_seviye AS ENUM (
    'yok',
    'goruntule',
    'kayit',
    'tam'
);


--
-- Name: audit_immutable(); Type: FUNCTION; Schema: phase0_private; Owner: -
--

CREATE FUNCTION phase0_private.audit_immutable() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog'
    AS $$
begin
  raise exception 'Korumalı denetim izi yalnızca eklenebilir' using errcode = '42501';
end;
$$;


--
-- Name: islem_audit(); Type: FUNCTION; Schema: phase0_private; Owner: -
--

CREATE FUNCTION phase0_private.islem_audit() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
declare
  v_row jsonb; v_role text; v_hotel text; v_entity text;
begin
  v_role := auth.role();
  -- Aktif ERP personeli şartı. service_role (QR köprüsü, Edge Function) muaf.
  if v_role is distinct from 'service_role' then
    if v_role is distinct from 'authenticated'
       or public.auth_erp_kullanicisi() is not true then
      raise exception 'Aktif ERP personeli gerekli' using errcode = '42501';
    end if;
  end if;

  v_row    := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  v_hotel  := v_row->>'otel_id';
  v_entity := coalesce(v_row->>'id', v_row->>'siparis_no', v_row->>'mk_no');

  -- Otel veya kimlik cozulemezse olay YINE kaydedilir. Denetim izi bir is
  -- yazmasini asla bloklamamali; eksik alan, kaybolan olaydan iyidir.
  insert into public.erp_islem_audit(
    hotel_id, actor_user_id, actor_role, event_type,
    entity_type, entity_id, transaction_id)
  values (case when v_hotel = any(enum_range(null::public.otel_id)::text[])
               then v_hotel::public.otel_id else null end,
          auth.uid(), v_role, tg_op, tg_table_name,
          coalesce(v_entity, '(kimliksiz)'), pg_current_xact_id()::text);

  if tg_op = 'DELETE' then return old; end if;
  return null;
end;
$$;


--
-- Name: otel_degismez(); Type: FUNCTION; Schema: phase0_private; Owner: -
--

CREATE FUNCTION phase0_private.otel_degismez() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog'
    AS $$
begin
  if new.otel_id is distinct from old.otel_id then
    raise exception 'Bir iş kaydının oteli değiştirilemez (%.otel_id)', tg_table_name
      using errcode = '42501';
  end if;
  return new;
end;
$$;


--
-- Name: ai_q_gunluk_ozet(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ai_q_gunluk_ozet(p_otel text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE sql STABLE
    SET search_path TO 'public'
    AS $$
  select case
    when not public.auth_yetki_var('ai_analiz_merkezi','goruntule') then '[]'::jsonb
    else (
      select coalesce(jsonb_agg(t), '[]'::jsonb) from (
          select otel_id, bekleyen_mal_kabul, kritik_skt_14gun, min_alti_urun
          from public.ai_gunluk_ozet
          where (p_otel is null or otel_id::text = p_otel)
            and public.auth_otel_erisim(otel_id)
          order by otel_id
        ) t
    )
  end;
$$;


--
-- Name: ai_q_min_alti(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ai_q_min_alti(p_otel text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE sql STABLE
    SET search_path TO 'public'
    AS $$
  select case
    when not public.auth_yetki_var('ai_analiz_merkezi','goruntule') then '[]'::jsonb
    else (
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
        )
    )
  end;
$$;


--
-- Name: ai_q_skt_yaklasan(text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ai_q_skt_yaklasan(p_otel text DEFAULT NULL::text, p_gun integer DEFAULT 14) RETURNS jsonb
    LANGUAGE sql STABLE
    SET search_path TO 'public'
    AS $$
  select case
    when not public.auth_yetki_var('ai_analiz_merkezi','goruntule') then '[]'::jsonb
    else (
      select coalesce(jsonb_agg(t), '[]'::jsonb) from (
          select otel_id, depo_kodu, urun_kodu, urun_adi, miktar, skt_tarihi, kalan_gun
          from public.ai_skt_risk
          where (p_otel is null or otel_id::text = p_otel)
            and kalan_gun <= greatest(p_gun, 0)
          order by kalan_gun asc
          limit 50
        ) t
    )
  end;
$$;


--
-- Name: ai_q_stok_anomali(text, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ai_q_stok_anomali(p_otel text DEFAULT NULL::text, p_esik numeric DEFAULT 2) RETURNS jsonb
    LANGUAGE sql STABLE
    SET search_path TO 'public'
    AS $$
  select case
    when not public.auth_yetki_var('ai_analiz_merkezi','goruntule') then '[]'::jsonb
    else (
      select coalesce(jsonb_agg(t), '[]'::jsonb) from (
          select otel_id, depo_kodu, urun_kodu, urun_adi, tip, tarih, miktar, ort_30, sapma_30
          from public.ai_stok_anomali
          where (p_otel is null or otel_id::text = p_otel)
            and sapma_30 is not null and sapma_30 > 0
            and abs(miktar - ort_30) > greatest(p_esik, 0) * sapma_30
          order by abs(miktar - ort_30) / nullif(sapma_30, 0) desc
          limit 50
        ) t
    )
  end;
$$;


--
-- Name: ai_q_tuketim_artan(text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ai_q_tuketim_artan(p_otel text DEFAULT NULL::text, p_gun integer DEFAULT 30) RETURNS jsonb
    LANGUAGE sql STABLE
    SET search_path TO 'public'
    AS $$
  select case
    when not public.auth_yetki_var('ai_analiz_merkezi','goruntule') then '[]'::jsonb
    else (
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
        ) t
    )
  end;
$$;


--
-- Name: ai_q_yavas_donen(text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ai_q_yavas_donen(p_otel text DEFAULT NULL::text, p_gun integer DEFAULT 30) RETURNS jsonb
    LANGUAGE sql STABLE
    SET search_path TO 'public'
    AS $$
  select case
    when not public.auth_yetki_var('ai_analiz_merkezi','goruntule') then '[]'::jsonb
    else (
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
        ) t
    )
  end;
$$;


--
-- Name: audit_log_damgala(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.audit_log_damgala() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  new.auth_user_id := auth.uid();
  new.kullanici_ad := coalesce(
    (select ad from public.kullanicilar where auth_user_id = auth.uid() limit 1),
    new.kullanici_ad
  );
  return new;
end;
$$;


--
-- Name: auth_erp_kullanicisi(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.auth_erp_kullanicisi() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
  select exists (select 1 from public.kullanicilar k
    where k.auth_user_id = auth.uid() and k.aktif is true);
$$;


--
-- Name: auth_kullanici_id(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.auth_kullanici_id() RETURNS text
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
  select k.id::text from public.kullanicilar k
  where k.auth_user_id = auth.uid() and k.aktif is true;
$$;


--
-- Name: auth_kullanici_rol_id(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.auth_kullanici_rol_id() RETURNS uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
  select k.rol_id from public.kullanicilar k
  where k.auth_user_id = auth.uid() and k.aktif is true;
$$;


--
-- Name: auth_otel_erisim(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.auth_otel_erisim(p_otel text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
  select exists (
    select 1 from public.kullanicilar k
    where k.auth_user_id = auth.uid() and k.aktif is true
      and p_otel = any(enum_range(null::public.otel_id)::text[])
      and (k.tum_oteller is true or k.otel_id::text = p_otel)
  );
$$;


--
-- Name: auth_otel_id(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.auth_otel_id() RETURNS text
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
  select k.otel_id::text from public.kullanicilar k
  where k.auth_user_id = auth.uid() and k.aktif is true;
$$;


--
-- Name: auth_tum_oteller(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.auth_tum_oteller() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
  select exists (select 1 from public.kullanicilar k
    where k.auth_user_id = auth.uid() and k.aktif is true and k.tum_oteller is true);
$$;


--
-- Name: auth_yetki_var(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.auth_yetki_var(p_modul_kod text, p_min_seviye text DEFAULT 'goruntule'::text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
  select exists (
    select 1 from public.kullanicilar k
    join public.yetki_matrisi ym on ym.rol_id = k.rol_id
    join public.moduller m on m.id = ym.modul_id
    where k.auth_user_id = auth.uid() and k.aktif is true
      and m.kod = p_modul_kod and m.aktif is true
      and ym.yetki::text = any(case p_min_seviye
        when 'goruntule' then array['goruntule','kayit','tam']
        when 'kayit'     then array['kayit','tam']
        when 'tam'       then array['tam']
        else array[]::text[] end)
  );
$$;


--
-- Name: bar_kullanilabilir_stok(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.bar_kullanilabilir_stok(p_stok_kodu text, p_depo_kodu text) RETURNS numeric
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select coalesce((select miktar from stok where urun_kodu = p_stok_kodu and depo_kodu = p_depo_kodu), 0)
       - coalesce((select sum(miktar) from stok_rezervasyonlari
                   where stok_kodu = p_stok_kodu and depo_id = p_depo_kodu and durum = 'aktif'), 0);
$$;


--
-- Name: bar_siparis_durum_guncelle(uuid, public.bar_durum); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.bar_siparis_durum_guncelle(p_siparis_id uuid, p_durum public.bar_durum) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
declare v_otel text;
begin
  if not auth_yetki_var('bar_siparis_yonetimi','kayit') then
    raise exception 'Yetki yok: bar_siparis_yonetimi kayıt gerekli';
  end if;
  if p_durum not in ('hazirlaniyor','hazir') then
    raise exception 'Bu fonksiyon yalnız hazirlaniyor/hazir için — teslim/iptal ayrı RPC';
  end if;

  select otel_id::text into v_otel from bar_siparisleri where id = p_siparis_id;
  if v_otel is null then raise exception 'Sipariş bulunamadı'; end if;
  if not auth_otel_erisim(v_otel) then
    raise exception 'Bu sipariş sizin otelinize ait değil';
  end if;

  update bar_siparisleri set durum = p_durum where id = p_siparis_id;
end;
$$;


--
-- Name: bar_siparis_iptal(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.bar_siparis_iptal(p_siparis_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
declare v_otel text;
begin
  if not auth_yetki_var('bar_siparis_yonetimi','kayit') then
    raise exception 'Yetki yok: bar_siparis_yonetimi kayıt gerekli';
  end if;

  select otel_id::text into v_otel from bar_siparisleri where id = p_siparis_id;
  if v_otel is null then raise exception 'Sipariş bulunamadı'; end if;
  if not auth_otel_erisim(v_otel) then
    raise exception 'Bu sipariş sizin otelinize ait değil';
  end if;

  update stok_rezervasyonlari r set durum = 'serbest'
    from bar_siparis_kalemleri k
    where k.id = r.siparis_kalem_id and k.siparis_id = p_siparis_id and r.durum = 'aktif';
  update bar_siparisleri set durum = 'iptal' where id = p_siparis_id;
end;
$$;


--
-- Name: bar_siparis_olustur(text, text, text, text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.bar_siparis_olustur(p_otel_id text, p_depo_id text, p_masa_token text, p_oda_no text, p_kalemler jsonb) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
declare
  v_siparis_id uuid;
  v_kalem jsonb;
  v_menu menu_urunler%rowtype;
  v_kalem_id uuid;
  v_bilesen record;
  v_gerekli numeric;
  v_musait numeric;
begin
  -- GUARD: boş sepet reddedilir (sipariş satırı bile oluşmaz)
  if p_kalemler is null or jsonb_array_length(p_kalemler) = 0 then
    raise exception 'Boş sipariş: en az bir kalem gerekli';
  end if;

  -- GÜVENLİK (politika denetimi sorgu 6 — 2026-08-10): bu fonksiyon İKİ yoldan çağrılıyor.
  --   • MÜŞTERİ QR AKIŞI: müşteri projesindeki 'siparis-gonder' Edge Function'ı, ANA
  --     projenin service_role anahtarıyla çağırır → auth.uid() BOŞTUR. Otel/depo
  --     doğrulaması orada masa token'ıyla yapılır; burada tekrar edilemez (kullanıcı yok).
  --   • PERSONEL AKIŞI: bar-garson.html, personel JWT'siyle çağırır → auth.uid() DOLUDUR.
  --     Bu yolda p_otel_id/p_depo_id çağırandan geliyordu ve HİÇ DOĞRULANMIYORDU →
  --     bir otelin personeli diğer oteli yazıp orada sipariş oluşturabiliyor ve
  --     STOK REZERVE EDEBİLİYORDU.
  -- Bu yüzden kontrol koşullu: yalnız kimliği olan çağıran için uygulanır.
  if auth.uid() is not null then
    if not auth_yetki_var('bar_siparis_yonetimi','kayit') then
      raise exception 'Yetki yok: bar_siparis_yonetimi kayıt gerekli';
    end if;
    if not auth_otel_erisim(p_otel_id) then
      raise exception 'Bu otel için sipariş oluşturamazsınız';
    end if;
  end if;

  insert into bar_siparisleri (otel_id, depo_id, masa_token, oda_no, durum)
  values (p_otel_id::otel_id, p_depo_id, p_masa_token, p_oda_no, 'yeni')
  returning id into v_siparis_id;

  for v_kalem in select * from jsonb_array_elements(p_kalemler)
  loop
    -- GÜVENLİK (pentest-2 [1]): menü ürünü, masa token'ından çözümlenen OTELE ait
    -- OLMALI. Önceden yalnız id ile aranıyordu → 810'un masasından 811'in menüsü
    -- sipariş edilebiliyor ve stok 810 deposundan düşüyordu (çapraz-otel sızıntı).
    select * into v_menu from menu_urunler
      where id = (v_kalem->>'menu_urun_id')::uuid
        and aktif = true and silindi = false
        and otel_id = p_otel_id::otel_id;
    if not found then
      raise exception 'Menü ürünü bulunamadı/pasif: %', v_kalem->>'menu_urun_id';
    end if;

    insert into bar_siparis_kalemleri (siparis_id, menu_urun_id, adet, rezerve_edildi)
    values (v_siparis_id, v_menu.id, (v_kalem->>'adet')::numeric, v_menu.stok_kodu is not null)
    returning id into v_kalem_id;

    if v_menu.tip = 'direkt' then
      -- stok_kodu YOKSA stok takibi yok (dahil/ücretsiz ürün) → kontrolü ve rezervasyonu atla
      if v_menu.stok_kodu is not null then
        v_gerekli := (v_kalem->>'adet')::numeric * coalesce(v_menu.miktar_per_porsiyon, 1);
        v_musait := bar_kullanilabilir_stok(v_menu.stok_kodu, p_depo_id);
        if v_musait < v_gerekli then
          raise exception 'Yetersiz stok: % (gerekli %, müsait %)', v_menu.stok_kodu, v_gerekli, v_musait;
        end if;
        insert into stok_rezervasyonlari (stok_kodu, otel_id, depo_id, miktar, siparis_kalem_id, durum)
        values (v_menu.stok_kodu, p_otel_id::otel_id, p_depo_id, v_gerekli, v_kalem_id, 'aktif');
      end if;
    else
      for v_bilesen in select * from recete_bilesenleri where menu_urun_id = v_menu.id
      loop
        v_gerekli := (v_kalem->>'adet')::numeric * v_bilesen.miktar_per_porsiyon;
        v_musait := bar_kullanilabilir_stok(v_bilesen.stok_kodu, p_depo_id);
        if v_musait < v_gerekli then
          raise exception 'Yetersiz stok (reçete): % (gerekli %, müsait %)', v_bilesen.stok_kodu, v_gerekli, v_musait;
        end if;
        insert into stok_rezervasyonlari (stok_kodu, otel_id, depo_id, miktar, siparis_kalem_id, durum)
        values (v_bilesen.stok_kodu, p_otel_id::otel_id, p_depo_id, v_gerekli, v_kalem_id, 'aktif');
      end loop;
    end if;
  end loop;

  return v_siparis_id;
end;
$$;


--
-- Name: bar_siparis_teslim_et(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.bar_siparis_teslim_et(p_siparis_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
declare v_rez record; v_otel text;
begin
  if not auth_yetki_var('bar_siparis_yonetimi','kayit') then
    raise exception 'Yetki yok: bar_siparis_yonetimi kayıt gerekli';
  end if;

  -- Teslim STOK DÜŞÜRÜR — kapsam kontrolü burada özellikle kritik
  select otel_id::text into v_otel from bar_siparisleri where id = p_siparis_id;
  if v_otel is null then raise exception 'Sipariş bulunamadı'; end if;
  if not auth_otel_erisim(v_otel) then
    raise exception 'Bu sipariş sizin otelinize ait değil';
  end if;

  for v_rez in
    select r.* from stok_rezervasyonlari r
    join bar_siparis_kalemleri k on k.id = r.siparis_kalem_id
    where k.siparis_id = p_siparis_id and r.durum = 'aktif'
  loop
    perform stok_ekle(v_rez.stok_kodu, v_rez.depo_id, v_rez.otel_id::text, -v_rez.miktar);
    update stok_rezervasyonlari set durum = 'kullanildi' where id = v_rez.id;
  end loop;
  update bar_siparis_kalemleri set teslim_edildi = true where siparis_id = p_siparis_id;
  update bar_siparisleri set durum = 'teslim_edildi' where id = p_siparis_id;
end;
$$;


--
-- Name: fatura_kaydet(uuid, jsonb, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fatura_kaydet(p_fatura_id uuid, p_satir jsonb, p_kalemler jsonb) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
declare v_fatura_id uuid; v_eski_otel public.otel_id; v_kalem jsonb;
begin
  if not (public.auth_yetki_var('fatura_giris','kayit') or public.auth_yetki_var('fiyat_kontrol','kayit') or public.auth_yetki_var('siparis_olustur','kayit')) then
    raise exception 'Yetki yok: fatura kaydı için fatura_giris/fiyat_kontrol/siparis_olustur kayıt yetkisi gerekli';
  end if;
  if p_kalemler is null or jsonb_array_length(p_kalemler) = 0 then raise exception 'En az bir fatura kalemi gerekli'; end if;
  if not public.auth_otel_erisim(p_satir->>'otel_id') then raise exception 'Yetki yok: bu otel için fatura kaydedemezsiniz'; end if;
  if p_fatura_id is not null then
    select otel_id into v_eski_otel from faturalar where id = p_fatura_id;
    if not found then raise exception 'Fatura bulunamadı: %', p_fatura_id; end if;
    if not public.auth_otel_erisim(v_eski_otel::text) then raise exception 'Yetki yok: bu faturanın oteline erişiminiz yok'; end if;
    update faturalar set
      no=p_satir->>'no', tur=(p_satir->>'tur')::fatura_tur, tarih=(p_satir->>'tarih')::date,
      vade_tarihi=(p_satir->>'vade_tarihi')::date, cari_id=(p_satir->>'cari_id')::uuid, cari_ad=p_satir->>'cari_ad',
      siparis_no=p_satir->>'siparis_no', ara_toplam=coalesce((p_satir->>'ara_toplam')::numeric,0),
      kdv_toplam=coalesce((p_satir->>'kdv_toplam')::numeric,0), genel_toplam=coalesce((p_satir->>'genel_toplam')::numeric,0),
      komisyon_orani=coalesce((p_satir->>'komisyon_orani')::numeric,0), komisyon_tutari=coalesce((p_satir->>'komisyon_tutari')::numeric,0),
      iade=coalesce((p_satir->>'iade')::boolean,false), otel_id=(p_satir->>'otel_id')::otel_id, not_alani=p_satir->>'not_alani',
      durum=(p_satir->>'durum')::fatura_durum, odeme_tarihi=(p_satir->>'odeme_tarihi')::timestamptz,
      odeme_tutari=(p_satir->>'odeme_tutari')::numeric, odeme_yontemi=p_satir->>'odeme_yontemi', guncelleme_tarihi=now()
    where id=p_fatura_id returning id into v_fatura_id;
    delete from fatura_kalemleri where fatura_id=v_fatura_id;
  else
    insert into faturalar (no,tur,tarih,vade_tarihi,cari_id,cari_ad,siparis_no,ara_toplam,kdv_toplam,genel_toplam,komisyon_orani,komisyon_tutari,iade,otel_id,not_alani,durum,odeme_tarihi,odeme_tutari,odeme_yontemi)
    values (p_satir->>'no',(p_satir->>'tur')::fatura_tur,(p_satir->>'tarih')::date,(p_satir->>'vade_tarihi')::date,(p_satir->>'cari_id')::uuid,p_satir->>'cari_ad',p_satir->>'siparis_no',coalesce((p_satir->>'ara_toplam')::numeric,0),coalesce((p_satir->>'kdv_toplam')::numeric,0),coalesce((p_satir->>'genel_toplam')::numeric,0),coalesce((p_satir->>'komisyon_orani')::numeric,0),coalesce((p_satir->>'komisyon_tutari')::numeric,0),coalesce((p_satir->>'iade')::boolean,false),(p_satir->>'otel_id')::otel_id,p_satir->>'not_alani',coalesce((p_satir->>'durum')::fatura_durum,'taslak'),(p_satir->>'odeme_tarihi')::timestamptz,(p_satir->>'odeme_tutari')::numeric,p_satir->>'odeme_yontemi')
    returning id into v_fatura_id;
  end if;
  for v_kalem in select * from jsonb_array_elements(p_kalemler) loop
    insert into fatura_kalemleri (fatura_id,urun_kodu,urun_adi,miktar,birim,birim_fiyat,iskonto_yuzde,kdv_orani,toplam)
    values (v_fatura_id,v_kalem->>'urun_kodu',v_kalem->>'urun_adi',(v_kalem->>'miktar')::numeric,coalesce(v_kalem->>'birim','KG'),(v_kalem->>'birim_fiyat')::numeric,coalesce((v_kalem->>'iskonto_yuzde')::numeric,0),coalesce((v_kalem->>'kdv_orani')::numeric,20),(v_kalem->>'toplam')::numeric);
  end loop;
  return v_fatura_id;
end; $$;


--
-- Name: giris_kaydi_ekle(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.giris_kaydi_ekle(p_giris_tipi text DEFAULT 'pin'::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_id   uuid;
  v_ad   text;
  v_otel public.otel_id;
begin
  select k.id, k.ad, k.otel_id
    into v_id, v_ad, v_otel
  from public.kullanicilar k
  where k.auth_user_id = auth.uid()
  limit 1;

  if v_id is null then
    return;
  end if;

  insert into public.giris_kayitlari (kullanici_id, ad, otel_id, giris_tipi, ip_hash)
  values (v_id, v_ad, v_otel, coalesce(nullif(p_giris_tipi,''),'pin'), null);
end;
$$;


--
-- Name: mal_kabul_kaydet(jsonb, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.mal_kabul_kaydet(p_baslik jsonb, p_kalemler jsonb) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
declare
  v_mk_id uuid;
  v_kalem jsonb;
  v_koli jsonb;
  v_kalem_id uuid;
  v_siparis_nolar text[];
  v_sip_miktar numeric;
  v_sip_gelen  numeric;
  v_sip_birim  text;
  v_bu_sefer_max numeric;
  v_istenen numeric;
begin
  if not public.auth_yetki_var('mal_kabul_form', 'kayit') then
    raise exception 'Yetki yok: mal kabul kaydı için mal_kabul_form kayıt yetkisi gerekli';
  end if;

  if p_kalemler is null or jsonb_array_length(p_kalemler) = 0 then
    raise exception 'En az bir ürün kalemi gerekli';
  end if;

  if not public.auth_otel_erisim(p_baslik->>'otel_id') then
    raise exception 'Yetki yok: bu otel için mal kabul kaydedemezsiniz';
  end if;

  -- ------------------------------------------------------------
  -- TESLİMAT TOLERANSI (%120) — pentest tur 3 bulgu [4]
  -- ------------------------------------------------------------
  -- Bu kural şimdiye kadar YALNIZCA istemcideydi (mal-kabul-liste.html:837);
  -- doğrudan RPC/REST çağrısıyla atlanabiliyordu. Mantık istemcidekiyle
  -- BİREBİR aynı tutuldu:
  --   • sipariş edilenin en fazla %120'si kabul edilir,
  --   • kısmi teslimatlarda ZATEN GELEN miktar da hesaba katılır,
  --   • 0.001'lik kayan nokta payı bırakılır,
  --   • birden fazla sipariş no verilmişse İLK eşleşen sipariş esas alınır,
  --   • ürün hiçbir siparişte bulunamazsa kontrol UYGULANMAZ (siparişsiz
  --     mal kabul meşru bir akış).
  -- İstemciden FARKI: satır FOR UPDATE ile kilitlenir, böylece eşzamanlı iki
  -- teslimat aynı bayat 'gelen_miktar' üzerinden ikisi birden geçemez —
  -- istemci kodunun yorumunda endişe edilen yarış durumu burada kapanır.
  if coalesce(p_baslik->>'ln_siparis_no', '') <> '' then
    select array_agg(btrim(x)) into v_siparis_nolar
    from unnest(string_to_array(p_baslik->>'ln_siparis_no', ',')) as x
    where btrim(x) <> '';

    if v_siparis_nolar is not null and array_length(v_siparis_nolar, 1) > 0 then
      for v_kalem in select * from jsonb_array_elements(p_kalemler)
      loop
        if coalesce(v_kalem->>'urun_kodu', '') = '' then
          continue;
        end if;

        select sk.miktar, sk.gelen_miktar, sk.birim
          into v_sip_miktar, v_sip_gelen, v_sip_birim
        from siparis_kalemleri sk
        where sk.siparis_no = any(v_siparis_nolar)
          and sk.urun_kodu = v_kalem->>'urun_kodu'
        order by array_position(v_siparis_nolar, sk.siparis_no)
        limit 1
        for update;

        if found then
          v_bu_sefer_max := v_sip_miktar * 1.2 - coalesce(v_sip_gelen, 0);
          v_istenen := coalesce((v_kalem->>'miktar')::numeric, 0);
          if v_istenen > v_bu_sefer_max + 0.001 then
            raise exception
              'Tolerans aşıldı (%): sipariş % %, zaten gelen % — bu teslimatta en fazla % % girilebilir',
              coalesce(v_kalem->>'urun_adi', v_kalem->>'urun_kodu'),
              v_sip_miktar, coalesce(v_sip_birim,''), coalesce(v_sip_gelen,0),
              round(greatest(v_bu_sefer_max, 0), 2), coalesce(v_sip_birim,'');
          end if;
        end if;
      end loop;
    end if;
  end if;

  insert into mal_kabuller (
    mk_no, form_tarihi, firma_ad, fatura_no, irsaliye_no, ln_siparis_no,
    otel_id, depo_kodu, arac_hijyen, arac_sicaklik, notlar, personel_ad, durum
  ) values (
    p_baslik->>'mk_no', (p_baslik->>'form_tarihi')::date, p_baslik->>'firma_ad',
    p_baslik->>'fatura_no', p_baslik->>'irsaliye_no', p_baslik->>'ln_siparis_no',
    (p_baslik->>'otel_id')::otel_id, p_baslik->>'depo_kodu',
    p_baslik->>'arac_hijyen', p_baslik->>'arac_sicaklik', p_baslik->>'notlar',
    p_baslik->>'personel_ad', coalesce((p_baslik->>'durum')::mal_kabul_durum, 'bekleyen')
  )
  returning id into v_mk_id;

  for v_kalem in select * from jsonb_array_elements(p_kalemler)
  loop
    insert into mal_kabul_urunleri (mk_id, urun_kodu, urun_adi, birim, miktar, seri_no, marka, sicaklik)
    values (
      v_mk_id, v_kalem->>'urun_kodu', v_kalem->>'urun_adi', coalesce(v_kalem->>'birim', 'KG'),
      (v_kalem->>'miktar')::numeric, v_kalem->>'seri_no', v_kalem->>'marka', v_kalem->>'sicaklik'
    )
    returning id into v_kalem_id;

    if v_kalem ? 'koliler' and jsonb_array_length(v_kalem->'koliler') > 0 then
      for v_koli in select * from jsonb_array_elements(v_kalem->'koliler')
      loop
        insert into koli_etiketleri (
          mk_id, mk_urun_id, urun_kodu, urun_adi, birim, miktar, koli_no,
          seri_no, marka, skt_tarihi, otel_id, depo_kodu, durum, birim_fiyat, fiyat_kaynagi
        ) values (
          v_mk_id, v_kalem_id, v_kalem->>'urun_kodu', v_kalem->>'urun_adi', coalesce(v_kalem->>'birim', 'KG'),
          (v_koli->>'miktar')::numeric, (v_koli->>'koli_no')::integer,
          v_kalem->>'seri_no', v_kalem->>'marka', (v_koli->>'skt_tarihi')::date,
          p_baslik->>'otel_id', p_baslik->>'depo_kodu', 'depoda',
          (v_koli->>'birim_fiyat')::numeric, v_koli->>'fiyat_kaynagi'
        );
      end loop;
    end if;
  end loop;

  return v_mk_id;
end;
$$;


--
-- Name: pin_ayarla(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.pin_ayarla(p_kullanici_id uuid, p_pin text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions'
    AS $_$
begin
  if not public.auth_yetki_var('kullanici_yonetimi','kayit') then
    raise exception 'Yetkisiz: PIN ayarlama yetkiniz yok';
  end if;
  if p_pin is null or p_pin !~ '^\d{6}$' then
    raise exception 'PIN 6 haneli sayısal olmalı';
  end if;
  if public.pin_zayif_mi(p_pin) then
    raise exception 'Bu PIN çok zayıf (sıralı/tekrarlı/yaygın). Tahmin edilmesi zor 6 hane seçin.';
  end if;
  update public.kullanicilar
    set pin_hash = crypt(p_pin, gen_salt('bf'))
    where id = p_kullanici_id;
  if not found then
    raise exception 'Kullanıcı bulunamadı';
  end if;
end;
$_$;


--
-- Name: pin_dogrula(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.pin_dogrula(p_giris text, p_ip_hash text) RETURNS TABLE(id uuid, ad text, rol public.kullanici_rol, rol_id uuid, departman text, otel_id public.otel_id, depo_id text, eposta text, auth_user_id uuid)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions'
    AS $$
declare
  v_basarisiz_sayisi int;
  v_genel_basarisiz int;
  v_eslesme_sayisi int;
begin
  if p_ip_hash is null or length(p_ip_hash) = 0 then
    raise exception 'p_ip_hash zorunlu';
  end if;

  -- KATMAN 1 — IP bazlı
  select count(*) into v_basarisiz_sayisi
  from public.giris_denemeleri
  where ip_hash = p_ip_hash
    and basarili = false
    and created_at > now() - interval '15 minutes';

  if v_basarisiz_sayisi >= 10 then
    return;
  end if;

  -- KATMAN 2 — IP'den BAĞIMSIZ genel tavan (dağıtık denemeye karşı)
  select count(*) into v_genel_basarisiz
  from public.giris_denemeleri
  where basarili = false
    and created_at > now() - interval '15 minutes';

  if v_genel_basarisiz >= 50 then
    insert into public.giris_denemeleri (ip_hash, basarili) values (p_ip_hash, false);
    return;
  end if;

  -- Zayıf PIN hiçbir zaman oturum üretmez (pentest-1 [1])
  if public.pin_zayif_mi(p_giris) then
    insert into public.giris_denemeleri (ip_hash, basarili) values (p_ip_hash, false);
    return;
  end if;

  select count(*) into v_eslesme_sayisi
  from public.kullanicilar k
  where k.aktif = true
    and k.pin_hash is not null
    and char_length(p_giris) = 6
    and k.pin_hash = crypt(p_giris, k.pin_hash);

  insert into public.giris_denemeleri (ip_hash, basarili)
  values (p_ip_hash, v_eslesme_sayisi > 0);

  if v_eslesme_sayisi = 0 then
    return;
  end if;

  return query
  select k.id, k.ad, k.rol, k.rol_id, k.departman, k.otel_id, k.depo_id, k.eposta, k.auth_user_id
  from public.kullanicilar k
  where k.aktif = true
    and k.pin_hash is not null
    and char_length(p_giris) = 6
    and k.pin_hash = crypt(p_giris, k.pin_hash);
end;
$$;


--
-- Name: pin_zayif_mi(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.pin_zayif_mi(p_pin text) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE
    AS $_$
declare
  v_bilinen text[] := array[
    '000000','111111','222222','333333','444444','555555','666666','777777','888888','999999',
    '123456','654321','012345','543210','111222','121212','123123','112233','102030','123321',
    '159753','147258','258369','741852','963852','696969','420420','131313','777888','101010'
  ];
  i int;
  v_artan boolean := true;
  v_azalan boolean := true;
begin
  if p_pin is null or p_pin !~ '^\d{6}$' then
    return true;
  end if;
  if p_pin = any(v_bilinen) then return true; end if;
  if p_pin ~ '^(\d)\1{5}$' then return true; end if;
  if substring(p_pin,1,2) = substring(p_pin,3,2)
     and substring(p_pin,3,2) = substring(p_pin,5,2) then return true; end if;
  if substring(p_pin,1,3) = substring(p_pin,4,3) then return true; end if;
  for i in 1..5 loop
    if ascii(substring(p_pin,i+1,1)) <> ascii(substring(p_pin,i,1)) + 1 then v_artan := false; end if;
    if ascii(substring(p_pin,i+1,1)) <> ascii(substring(p_pin,i,1)) - 1 then v_azalan := false; end if;
  end loop;
  if v_artan or v_azalan then return true; end if;
  return false;
end;
$_$;


--
-- Name: rls_auto_enable(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rls_auto_enable() RETURNS event_trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog'
    AS $$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$$;


--
-- Name: siparis_yeniden_yonlendir(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.siparis_yeniden_yonlendir(p_siparis_no text, p_olusturan text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
declare
  v_otel public.otel_id;
  v_durum text;
  v_talep_id uuid;
  v_kalan_sayi int;
  v_kalem record;
begin
  if not public.auth_yetki_var('siparis_olustur','kayit') then
    raise exception 'Yetki yok: sipariş yeniden yönlendirme için siparis_olustur kayıt yetkisi gerekli';
  end if;

  select otel_id, durum into v_otel, v_durum
  from public.siparisler where siparis_no = p_siparis_no;
  if not found then
    raise exception 'Sipariş bulunamadı: %', p_siparis_no;
  end if;
  if not public.auth_otel_erisim(v_otel::text) then
    raise exception 'Yetki yok: bu siparişin oteline erişiminiz yok';
  end if;
  if v_durum in ('iptal','tamamlandi') then
    raise exception 'Bu sipariş yeniden yönlendirilemez (durum: %)', v_durum;
  end if;

  select count(*) into v_kalan_sayi
  from public.siparis_kalemleri
  where siparis_no = p_siparis_no and kalan_miktar > 0;
  if v_kalan_sayi = 0 then
    raise exception 'Gelmeyen (kalan) kalem yok — yeniden yönlendirmeye gerek yok';
  end if;

  update public.siparisler
    set durum = 'iptal',
        not_alani = coalesce(not_alani || ' | ', '') ||
          'Gecikme nedeniyle iptal + yeniden yönlendirildi (' || to_char(now(),'YYYY-MM-DD') || ')',
        son_guncelleme = now()
  where siparis_no = p_siparis_no;

  insert into public.teklif_talepleri (olusturan, otel_id, durum)
  values (p_olusturan, v_otel::text, 'acik')
  returning id into v_talep_id;

  for v_kalem in
    select urun_kodu, urun_adi, birim, kalan_miktar
    from public.siparis_kalemleri
    where siparis_no = p_siparis_no and kalan_miktar > 0
  loop
    insert into public.teklif_kalemleri (teklif_talebi_id, urun_kodu, urun_adi, miktar, birim)
    values (v_talep_id, v_kalem.urun_kodu, v_kalem.urun_adi, v_kalem.kalan_miktar, v_kalem.birim);
  end loop;

  return v_talep_id;
end;
$$;


--
-- Name: stok_ekle(text, text, text, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.stok_ekle(p_urun_kodu text, p_depo_kodu text, p_otel_id text, p_delta numeric) RETURNS numeric
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'public', 'extensions', 'pg_temp'
    AS $$
declare
  v_yeni numeric;
begin
  insert into stok (urun_kodu, depo_kodu, otel_id, miktar)
  values (p_urun_kodu, p_depo_kodu, p_otel_id::otel_id, greatest(0, p_delta))
  on conflict (urun_kodu, depo_kodu)
  do update set miktar = greatest(0, stok.miktar + p_delta)
  returning miktar into v_yeni;
  return v_yeni;
end;
$$;


--
-- Name: stok_transfer(text, text, text, text, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.stok_transfer(p_urun_kodu text, p_kaynak_depo text, p_hedef_depo text, p_hedef_otel text, p_miktar numeric) RETURNS void
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'public', 'extensions', 'pg_temp'
    AS $$
begin
  update stok set miktar = greatest(0, miktar - p_miktar)
    where urun_kodu = p_urun_kodu and depo_kodu = p_kaynak_depo;
  insert into stok (urun_kodu, depo_kodu, otel_id, miktar)
    values (p_urun_kodu, p_hedef_depo, p_hedef_otel::otel_id, p_miktar)
    on conflict (urun_kodu, depo_kodu)
    do update set miktar = greatest(0, stok.miktar + p_miktar);
end;
$$;


--
-- Name: talep_asama_yetkili_mi(text, text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.talep_asama_yetkili_mi(p_asama text, p_rol text, p_rol_id uuid) RETURNS boolean
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_rol_kod text;
begin
  if p_rol = 'yonetici' then return true; end if;

  if p_asama = 'depo' then return p_rol = 'depo'; end if;
  if p_asama = 'cost' then return p_rol = 'cost_control'; end if;

  select kod into v_rol_kod from public.roller where id = p_rol_id;
  if v_rol_kod is null then return false; end if;

  return case p_asama
    when 'mdr'         then v_rol_kod = 'satinalma_mdr'
    when 'direktor'    then v_rol_kod = 'grup_satinalma'
    when 'gm'          then v_rol_kod = 'gm'
    when 'ust_yonetim' then v_rol_kod = 'grup_direktor'
    else false
  end;
end;
$$;


--
-- Name: talep_karar_ver(uuid, text, text, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.talep_karar_ver(p_talep_id uuid, p_karar text, p_not text DEFAULT NULL::text, p_tutar numeric DEFAULT NULL::numeric) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
declare
  v_kul record; v_talep record; v_asama text; v_sonraki text;
begin
  if p_karar not in ('onay','red') then
    raise exception 'Geçersiz karar: %', p_karar;
  end if;

  select k.id, k.ad, k.rol::text as rol, k.rol_id into v_kul
  from public.kullanicilar k
  where k.auth_user_id = auth.uid() and k.aktif = true;
  if not found then
    return jsonb_build_object('ok', false, 'hata', 'oturum_yok');
  end if;

  select t.id, t.durum::text as durum, t.asama, t.otel_id::text as otel_id into v_talep
  from public.satin_alma_talepleri t
  where t.id = p_talep_id
  for update;
  if not found then
    return jsonb_build_object('ok', false, 'hata', 'talep_yok');
  end if;

  -- ★ OTEL KAPSAMI (pentest tur 4)
  if not public.auth_otel_erisim(v_talep.otel_id) then
    return jsonb_build_object('ok', false, 'hata', 'otel_kapsami_disi');
  end if;

  if v_talep.durum <> 'bekleyen' then
    return jsonb_build_object('ok', false, 'hata', 'zaten_karar_verilmis');
  end if;

  v_asama := v_talep.asama;

  if not public.talep_asama_yetkili_mi(v_asama, v_kul.rol, v_kul.rol_id) then
    return jsonb_build_object('ok', false, 'hata', 'yetkisiz');
  end if;

  if p_karar = 'red' then
    insert into public.talep_onay_gecmisi (talep_id, asama, rol_kodu, kullanici_ad, karar, not_metni)
    values (p_talep_id, v_asama, v_kul.rol, v_kul.ad, 'red', p_not);
    update public.satin_alma_talepleri
       set durum = 'reddedildi', onaylayan_ad = v_kul.ad, onay_tarihi = now()
     where id = p_talep_id;
    return jsonb_build_object('ok', true, 'sonuc', 'reddedildi');
  end if;

  if v_asama = 'cost' and (p_tutar is null or p_tutar < 0) then
    return jsonb_build_object('ok', false, 'hata', 'tutar_gerekli');
  end if;

  insert into public.talep_onay_gecmisi (talep_id, asama, rol_kodu, kullanici_ad, karar, not_metni)
  values (p_talep_id, v_asama, v_kul.rol, v_kul.ad, 'onay', p_not);

  v_sonraki := case
    when v_asama = 'depo' then 'cost'
    when v_asama = 'cost' then
      case
        when p_tutar <= 200000 then 'mdr'
        when p_tutar <= 500000 then 'direktor'
        when p_tutar <= 750000 then 'gm'
        else 'ust_yonetim'
      end
    else null
  end;

  if v_asama = 'cost' then
    update public.satin_alma_talepleri set tutar = p_tutar where id = p_talep_id;
  end if;

  if v_sonraki is not null then
    update public.satin_alma_talepleri set asama = v_sonraki where id = p_talep_id;
    return jsonb_build_object('ok', true, 'sonuc', v_sonraki);
  else
    update public.satin_alma_talepleri
       set durum = 'onaylandi', onaylayan_ad = v_kul.ad, onay_tarihi = now()
     where id = p_talep_id;
    return jsonb_build_object('ok', true, 'sonuc', 'onaylandi');
  end if;
end;
$$;


--
-- Name: talep_siparise_donustur(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.talep_siparise_donustur(p_talep_id uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
declare
  v_talep record;
begin
  if not public.auth_yetki_var('siparis_olustur','kayit') then
    return jsonb_build_object('ok', false, 'hata', 'yetkisiz');
  end if;

  select t.id, t.durum::text as durum, t.otel_id::text as otel_id into v_talep
  from public.satin_alma_talepleri t
  where t.id = p_talep_id
  for update;
  if not found then
    return jsonb_build_object('ok', false, 'hata', 'talep_yok');
  end if;

  -- ★ OTEL KAPSAMI (pentest tur 4)
  if not public.auth_otel_erisim(v_talep.otel_id) then
    return jsonb_build_object('ok', false, 'hata', 'otel_kapsami_disi');
  end if;

  if v_talep.durum <> 'onaylandi' then
    return jsonb_build_object('ok', false, 'hata', 'onaylanmamis', 'durum', v_talep.durum);
  end if;

  update public.satin_alma_talepleri set durum = 'siparis' where id = p_talep_id;
  return jsonb_build_object('ok', true, 'sonuc', 'siparis');
end;
$$;


--
-- Name: teklif_talebi_olustur(text, text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.teklif_talebi_olustur(p_olusturan text, p_otel_id text, p_kalemler jsonb) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
declare v_talep_id uuid; v_otel text; v_kalem jsonb;
begin
  if not public.auth_yetki_var('siparis_olustur','kayit') then raise exception 'Yetki yok: teklif talebi için siparis_olustur kayıt yetkisi gerekli'; end if;
  if p_kalemler is null or jsonb_array_length(p_kalemler) = 0 then raise exception 'En az bir kalem seçin'; end if;
  v_otel := coalesce(p_otel_id,'810');
  if not public.auth_otel_erisim(v_otel) then raise exception 'Yetki yok: bu otel için teklif talebi oluşturamazsınız'; end if;
  insert into teklif_talepleri (olusturan,otel_id,durum) values (p_olusturan,v_otel,'acik') returning id into v_talep_id;
  for v_kalem in select * from jsonb_array_elements(p_kalemler) loop
    insert into teklif_kalemleri (teklif_talebi_id,urun_kodu,urun_adi,miktar,birim,kaynak_ic_talep_kalemi_id)
    values (v_talep_id,v_kalem->>'urun_kodu',v_kalem->>'urun_adi',(v_kalem->>'miktar')::numeric,coalesce(v_kalem->>'birim','KG'),nullif(v_kalem->>'kaynak_ic_talep_kalemi_id','')::uuid);
  end loop;
  return v_talep_id;
end; $$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: stok; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.stok (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    urun_kodu text NOT NULL,
    depo_kodu text NOT NULL,
    otel_id public.otel_id NOT NULL,
    miktar numeric(12,3) DEFAULT 0 NOT NULL,
    guncelleme_tarihi timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: stok_minimumlar; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.stok_minimumlar (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    urun_kodu text NOT NULL,
    depo_kodu text NOT NULL,
    otel_id public.otel_id NOT NULL,
    min_miktar numeric(12,3) DEFAULT 0 NOT NULL
);


--
-- Name: urunler; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.urunler (
    kod text NOT NULL,
    ad text NOT NULL,
    birim text DEFAULT 'KG'::text NOT NULL,
    grup text,
    sicaklik_kriteri text,
    olusturma_tarihi timestamp with time zone DEFAULT now() NOT NULL,
    sicaklik_kriter text,
    sistem_fiyat numeric,
    sistem_fiyat_tarihi timestamp with time zone,
    sistem_fiyat_giren text
);


--
-- Name: ai_min_alti_stok; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.ai_min_alti_stok WITH (security_invoker='true') AS
 SELECT st.otel_id,
    st.depo_kodu,
    st.urun_kodu,
    u.ad AS urun_adi,
    st.miktar,
    m.min_miktar,
    (m.min_miktar - st.miktar) AS eksik_miktar
   FROM ((public.stok st
     JOIN public.stok_minimumlar m ON (((m.urun_kodu = st.urun_kodu) AND (m.depo_kodu = st.depo_kodu))))
     LEFT JOIN public.urunler u ON ((u.kod = st.urun_kodu)))
  WHERE (st.miktar < m.min_miktar);


--
-- Name: ai_otel_ref; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.ai_otel_ref AS
 SELECT '810'::text AS otel_id,
    'Ali Bey Club Manavgat'::text AS otel_ad
UNION ALL
 SELECT '811'::text AS otel_id,
    'Ali Bey Resort Sorgun'::text AS otel_ad;


--
-- Name: mal_kabuller; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mal_kabuller (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    mk_no text NOT NULL,
    form_tarihi date NOT NULL,
    firma_ad text NOT NULL,
    firma_id text,
    fatura_no text,
    irsaliye_no text,
    ln_siparis_no text,
    otel_id public.otel_id NOT NULL,
    depo_kodu text,
    arac_hijyen text,
    arac_sicaklik text,
    seri_no text,
    notlar text,
    personel_ad text,
    durum public.mal_kabul_durum DEFAULT 'bekleyen'::public.mal_kabul_durum NOT NULL,
    tarih timestamp with time zone DEFAULT now() NOT NULL,
    fiyat_kontrol_durum text,
    fiyat_kontrol_notu text,
    fiyat_kontrol_tarihi timestamp with time zone,
    muhasebe_fatura_id bigint,
    stok_islendi boolean DEFAULT false
);


--
-- Name: skt_kayitlari; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.skt_kayitlari (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    urun_kodu text NOT NULL,
    mk_id uuid,
    otel_id public.otel_id NOT NULL,
    depo_kodu text,
    miktar numeric(12,3) NOT NULL,
    skt_tarihi date NOT NULL,
    durum text DEFAULT 'aktif'::text NOT NULL,
    olusturma_tarihi timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: ai_gunluk_ozet; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.ai_gunluk_ozet WITH (security_invoker='true') AS
 SELECT otel_id,
    ( SELECT count(*) AS count
           FROM public.mal_kabuller mk
          WHERE ((mk.durum = 'bekleyen'::public.mal_kabul_durum) AND ((mk.otel_id)::text = o.otel_id))) AS bekleyen_mal_kabul,
    ( SELECT count(*) AS count
           FROM public.skt_kayitlari s
          WHERE ((s.durum = 'aktif'::text) AND ((s.otel_id)::text = o.otel_id) AND ((s.skt_tarihi >= CURRENT_DATE) AND (s.skt_tarihi <= (CURRENT_DATE + 14))))) AS kritik_skt_14gun,
    ( SELECT count(*) AS count
           FROM public.ai_min_alti_stok ma
          WHERE ((ma.otel_id)::text = o.otel_id)) AS min_alti_urun
   FROM public.ai_otel_ref o;


--
-- Name: ai_skt_risk; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.ai_skt_risk WITH (security_invoker='true') AS
 SELECT s.otel_id,
    s.depo_kodu,
    s.urun_kodu,
    u.ad AS urun_adi,
    s.miktar,
    s.skt_tarihi,
    (s.skt_tarihi - CURRENT_DATE) AS kalan_gun
   FROM (public.skt_kayitlari s
     LEFT JOIN public.urunler u ON ((u.kod = s.urun_kodu)))
  WHERE (s.durum = 'aktif'::text);


--
-- Name: stok_hareketleri; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.stok_hareketleri (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    urun_kodu text NOT NULL,
    depo_kodu text NOT NULL,
    otel_id public.otel_id NOT NULL,
    tip text NOT NULL,
    miktar numeric(12,3) NOT NULL,
    belge_no text,
    tarih timestamp with time zone DEFAULT now() NOT NULL,
    aciklama text,
    kaynak_depo_kodu text
);


--
-- Name: ai_stok_anomali; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.ai_stok_anomali WITH (security_invoker='true') AS
 SELECT h.otel_id,
    h.depo_kodu,
    h.urun_kodu,
    u.ad AS urun_adi,
    h.tip,
    h.tarih,
    h.miktar,
    h.aciklama,
    avg(h.miktar) OVER w AS ort_30,
    stddev_pop(h.miktar) OVER w AS sapma_30
   FROM (public.stok_hareketleri h
     LEFT JOIN public.urunler u ON ((u.kod = h.urun_kodu)))
  WINDOW w AS (PARTITION BY h.urun_kodu, h.depo_kodu, h.tip ORDER BY h.tarih ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING);


--
-- Name: ai_tuketim_trend; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.ai_tuketim_trend WITH (security_invoker='true') AS
 SELECT h.otel_id,
    h.depo_kodu,
    h.urun_kodu,
    u.ad AS urun_adi,
    (date_trunc('week'::text, h.tarih))::date AS hafta,
    sum(h.miktar) AS cikis_toplam,
    sum(h.miktar) FILTER (WHERE (h.aciklama ~~* '%tuketim%'::text)) AS tuketim_miktar
   FROM (public.stok_hareketleri h
     LEFT JOIN public.urunler u ON ((u.kod = h.urun_kodu)))
  WHERE (h.tip = 'cikis'::text)
  GROUP BY h.otel_id, h.depo_kodu, h.urun_kodu, u.ad, (date_trunc('week'::text, h.tarih));


--
-- Name: urun_alt_gruplari; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.urun_alt_gruplari (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    ana_grup_kod text NOT NULL,
    alt_grup_kod text NOT NULL,
    alt_grup_adi text NOT NULL,
    sira integer DEFAULT 0 NOT NULL,
    silindi boolean DEFAULT false NOT NULL,
    guncelleme_tarihi timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: urun_ana_gruplari; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.urun_ana_gruplari (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    ana_grup_kod text NOT NULL,
    ana_grup_adi text DEFAULT ''::text NOT NULL,
    sira integer DEFAULT 0 NOT NULL,
    silindi boolean DEFAULT false NOT NULL,
    guncelleme_tarihi timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: urun_siniflandirma; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.urun_siniflandirma (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    urun_kodu text NOT NULL,
    alt_grup_kod text NOT NULL,
    silindi boolean DEFAULT false NOT NULL,
    guncelleme_tarihi timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: ai_urun_grup; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.ai_urun_grup AS
 SELECT s.urun_kodu,
    ag.ana_grup_kod,
    ag.ana_grup_adi,
    alt.alt_grup_kod,
    alt.alt_grup_adi
   FROM ((public.urun_siniflandirma s
     JOIN public.urun_alt_gruplari alt ON (((alt.alt_grup_kod = s.alt_grup_kod) AND (COALESCE(alt.silindi, false) = false))))
     JOIN public.urun_ana_gruplari ag ON (((ag.ana_grup_kod = alt.ana_grup_kod) AND (COALESCE(ag.silindi, false) = false))))
  WHERE (COALESCE(s.silindi, false) = false);


--
-- Name: amortisman_kosustu; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.amortisman_kosustu (
    donem text NOT NULL,
    calistirma_tarihi timestamp with time zone DEFAULT now() NOT NULL,
    demirbas_sayisi integer NOT NULL,
    toplam_tutar numeric(14,2) NOT NULL,
    kullanan text
);


--
-- Name: audit_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_log (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    action text NOT NULL,
    entity_type text NOT NULL,
    entity_id text NOT NULL,
    detail text,
    kullanici_ad text,
    zaman timestamp with time zone DEFAULT now() NOT NULL,
    auth_user_id uuid
);


--
-- Name: banka_kasa_hareketleri; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.banka_kasa_hareketleri (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    hesap_id uuid NOT NULL,
    tarih date NOT NULL,
    tip text NOT NULL,
    tutar numeric(14,2) NOT NULL,
    belge_no text,
    otel_id public.otel_id,
    aciklama text,
    olusturma_tarihi timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT banka_kasa_hareketleri_tutar_check CHECK ((tutar >= (0)::numeric))
);


--
-- Name: banka_kasa_hesaplari; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.banka_kasa_hesaplari (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    ad text NOT NULL,
    tip text NOT NULL,
    iban text,
    otel_id public.otel_id NOT NULL,
    acilis_bakiye numeric(14,2) DEFAULT 0 NOT NULL,
    durum text DEFAULT 'aktif'::text NOT NULL,
    olusturma_tarihi timestamp with time zone DEFAULT now() NOT NULL,
    muhasebe_kod text,
    doviz text DEFAULT 'TRY'::text,
    banka_ad text,
    sube text,
    silindi boolean DEFAULT false
);


--
-- Name: bar_siparis_kalemleri; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bar_siparis_kalemleri (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    siparis_id uuid NOT NULL,
    menu_urun_id uuid NOT NULL,
    adet numeric(12,3) NOT NULL,
    rezerve_edildi boolean DEFAULT false NOT NULL,
    teslim_edildi boolean DEFAULT false NOT NULL,
    CONSTRAINT bar_siparis_kalemleri_adet_check CHECK ((adet > (0)::numeric))
);


--
-- Name: bar_siparisleri; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bar_siparisleri (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    otel_id public.otel_id NOT NULL,
    depo_id text NOT NULL,
    masa_token text,
    oda_no text,
    durum public.bar_durum DEFAULT 'yeni'::public.bar_durum NOT NULL,
    personel_id uuid,
    olusturma_zamani timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: butce_kayitlari; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.butce_kayitlari (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    yil integer NOT NULL,
    otel_id public.otel_id NOT NULL,
    hesap_kodu text NOT NULL,
    ocak numeric(14,2) DEFAULT 0,
    subat numeric(14,2) DEFAULT 0,
    mart numeric(14,2) DEFAULT 0,
    nisan numeric(14,2) DEFAULT 0,
    mayis numeric(14,2) DEFAULT 0,
    haziran numeric(14,2) DEFAULT 0,
    temmuz numeric(14,2) DEFAULT 0,
    agustos numeric(14,2) DEFAULT 0,
    eylul numeric(14,2) DEFAULT 0,
    ekim numeric(14,2) DEFAULT 0,
    kasim numeric(14,2) DEFAULT 0,
    aralik numeric(14,2) DEFAULT 0,
    olusturma_tarihi timestamp with time zone DEFAULT now() NOT NULL,
    guncelleme_tarihi timestamp with time zone DEFAULT now() NOT NULL,
    hesap_ad text,
    silindi boolean DEFAULT false
);


--
-- Name: cari_hareketler; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cari_hareketler (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    cari_id uuid NOT NULL,
    tip public.hareket_tip NOT NULL,
    tarih date NOT NULL,
    belge_no text,
    vade_tarihi date,
    tutar numeric(14,2) NOT NULL,
    kdv numeric(14,2) DEFAULT 0,
    otel_id public.otel_id,
    aciklama text,
    fatura_id uuid,
    olusturma_tarihi timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT cari_hareketler_tutar_check CHECK ((tutar >= (0)::numeric))
);


--
-- Name: cariler; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cariler (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    kod text NOT NULL,
    ad text NOT NULL,
    tip public.cari_tip NOT NULL,
    vkn text,
    vergi_dairesi text,
    telefon text,
    eposta text,
    adres text,
    hesap_kodu text,
    vade_gun integer DEFAULT 30 NOT NULL,
    risk_limiti numeric(14,2) DEFAULT 0,
    efatura_mukellefi boolean DEFAULT false NOT NULL,
    efatura_alias text,
    acente boolean DEFAULT false NOT NULL,
    komisyon_orani numeric(5,2) DEFAULT 0,
    not_alani text,
    olusturma_tarihi timestamp with time zone DEFAULT now() NOT NULL,
    guncelleme_tarihi timestamp with time zone DEFAULT now() NOT NULL,
    silindi boolean DEFAULT false
);


--
-- Name: cek_senetler; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cek_senetler (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tur public.cek_senet_tur NOT NULL,
    yon public.cek_senet_yon NOT NULL,
    cari_id uuid,
    cari_ad text NOT NULL,
    no text,
    banka text,
    duzenleme_tarihi date,
    vade_tarihi date NOT NULL,
    tutar numeric(14,2) NOT NULL,
    otel_id public.otel_id NOT NULL,
    durum public.cek_senet_durum DEFAULT 'portfoyde'::public.cek_senet_durum NOT NULL,
    not_alani text,
    olusturma_tarihi timestamp with time zone DEFAULT now() NOT NULL,
    guncelleme_tarihi timestamp with time zone DEFAULT now() NOT NULL,
    silindi boolean DEFAULT false
);


--
-- Name: demirbaslar; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.demirbaslar (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    kod text NOT NULL,
    ad text NOT NULL,
    kategori public.demirbas_kategori NOT NULL,
    hesap_kodu text NOT NULL,
    amortisman_hesap_kodu text NOT NULL,
    seri_no text,
    alim_tarihi date NOT NULL,
    alim_tutari numeric(14,2) NOT NULL,
    oran_yillik numeric(5,2) NOT NULL,
    birikmis_amortisman numeric(14,2) DEFAULT 0 NOT NULL,
    otel_id public.otel_id NOT NULL,
    zimmet text,
    durum public.demirbas_durum DEFAULT 'aktif'::public.demirbas_durum NOT NULL,
    elden_cikarma_tarihi timestamp with time zone,
    satis_bedeli numeric(14,2),
    not_alani text,
    olusturma_tarihi timestamp with time zone DEFAULT now() NOT NULL,
    guncelleme_tarihi timestamp with time zone DEFAULT now() NOT NULL,
    silindi boolean DEFAULT false
);


--
-- Name: doviz_kurlari; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.doviz_kurlari (
    tarih date NOT NULL,
    para_birimi text NOT NULL,
    doviz_alis numeric(10,4) NOT NULL,
    doviz_satis numeric(10,4),
    efektif_alis numeric(10,4),
    efektif_satis numeric(10,4),
    kaynak text DEFAULT 'TCMB'::text NOT NULL,
    guncelleme_tarihi timestamp with time zone DEFAULT now() NOT NULL,
    silindi boolean DEFAULT false
);


--
-- Name: edefter_kurum_bilgileri; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.edefter_kurum_bilgileri (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    vkn text,
    unvan text,
    adres_bina_no text,
    adres_sokak text,
    adres_sehir text,
    adres_posta_kodu text,
    adres_ulke text DEFAULT 'Türkiye'::text,
    telefon text,
    eposta text,
    website text,
    is_tanimi text,
    mali_yil_baslangic date,
    mali_yil_bitis date,
    muhasebeci_ad text,
    muhasebeci_unvan text
);


--
-- Name: edefter_sube_bilgileri; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.edefter_sube_bilgileri (
    otel_id text NOT NULL,
    sube_no text,
    sube_adi text
);


--
-- Name: erp_islem_audit; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.erp_islem_audit (
    id bigint NOT NULL,
    hotel_id public.otel_id,
    actor_user_id uuid,
    actor_role text NOT NULL,
    server_timestamp timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    event_type text NOT NULL,
    entity_type text NOT NULL,
    entity_id text NOT NULL,
    transaction_id text NOT NULL,
    CONSTRAINT erp_islem_audit_actor_role_check CHECK ((actor_role = ANY (ARRAY['authenticated'::text, 'service_role'::text]))),
    CONSTRAINT erp_islem_audit_check CHECK (((actor_user_id IS NOT NULL) OR (actor_role = 'service_role'::text))),
    CONSTRAINT erp_islem_audit_event_type_check CHECK ((event_type = ANY (ARRAY['INSERT'::text, 'UPDATE'::text, 'DELETE'::text])))
);


--
-- Name: erp_islem_audit_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.erp_islem_audit ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.erp_islem_audit_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: excel_import_gecmisi; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.excel_import_gecmisi (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tablo_adi text NOT NULL,
    ilgili_id uuid,
    dosya_adi text,
    kullanici_ad text,
    tarih timestamp with time zone DEFAULT now(),
    mod text,
    toplam_satir integer DEFAULT 0,
    yeni_sayisi integer DEFAULT 0,
    guncelleme_sayisi integer DEFAULT 0,
    hata_sayisi integer DEFAULT 0,
    atlanan_sayisi integer DEFAULT 0
);


--
-- Name: excel_import_satirlari; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.excel_import_satirlari (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    import_id uuid,
    satir_no integer,
    kayit_id uuid,
    durum text NOT NULL,
    eski_deger jsonb,
    yeni_deger jsonb,
    hata_mesaji text
);


--
-- Name: fatura_kalemleri; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.fatura_kalemleri (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    fatura_id uuid NOT NULL,
    urun_kodu text,
    urun_adi text NOT NULL,
    miktar numeric(12,3) NOT NULL,
    birim text DEFAULT 'KG'::text NOT NULL,
    birim_fiyat numeric(12,4) NOT NULL,
    iskonto_yuzde numeric(5,2) DEFAULT 0,
    kdv_orani numeric(5,2) DEFAULT 20 NOT NULL,
    toplam numeric(14,2) NOT NULL
);


--
-- Name: faturalar; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.faturalar (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    no text,
    tur public.fatura_tur NOT NULL,
    tarih date NOT NULL,
    vade_tarihi date,
    cari_id uuid,
    cari_ad text NOT NULL,
    siparis_no text,
    ara_toplam numeric(14,2) DEFAULT 0 NOT NULL,
    kdv_toplam numeric(14,2) DEFAULT 0 NOT NULL,
    genel_toplam numeric(14,2) DEFAULT 0 NOT NULL,
    komisyon_orani numeric(5,2) DEFAULT 0,
    komisyon_tutari numeric(14,2) DEFAULT 0,
    iade boolean DEFAULT false NOT NULL,
    otel_id public.otel_id NOT NULL,
    not_alani text,
    durum public.fatura_durum DEFAULT 'taslak'::public.fatura_durum NOT NULL,
    odeme_tarihi timestamp with time zone,
    odeme_tutari numeric(14,2),
    odeme_yontemi text,
    olusturma_tarihi timestamp with time zone DEFAULT now() NOT NULL,
    guncelleme_tarihi timestamp with time zone DEFAULT now() NOT NULL,
    efatura_durum text,
    efatura_tip text,
    ettn text,
    gib_fatura_no text,
    gib_pdf_url text,
    efatura_gonderim_tarihi timestamp with time zone,
    efatura_hata_mesaji text,
    silindi boolean DEFAULT false
);


--
-- Name: gelen_efaturalar; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.gelen_efaturalar (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    ettn text,
    gonderen_vkn text,
    gonderen_ad text,
    tarih date,
    kalemler jsonb,
    ara_toplam numeric,
    kdv_toplam numeric,
    genel_toplam numeric,
    durum text DEFAULT 'yeni'::text,
    alis_fatura_id uuid,
    olusturma_tarihi timestamp with time zone DEFAULT now()
);


--
-- Name: giris_denemeleri; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.giris_denemeleri (
    id bigint NOT NULL,
    ip_hash text NOT NULL,
    basarili boolean NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: giris_denemeleri_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.giris_denemeleri ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.giris_denemeleri_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: giris_kayitlari; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.giris_kayitlari (
    id bigint NOT NULL,
    kullanici_id uuid,
    ad text,
    otel_id public.otel_id,
    giris_tipi text DEFAULT 'pin'::text NOT NULL,
    ip_hash text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: giris_kayitlari_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.giris_kayitlari ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.giris_kayitlari_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: hesap_plani; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hesap_plani (
    kod text NOT NULL,
    ust_kod text,
    ad text NOT NULL,
    tip public.hesap_tip NOT NULL,
    ana_grup text,
    yon public.hesap_yon DEFAULT 'Borç'::public.hesap_yon NOT NULL,
    alt_seviye text,
    ozellik text,
    doviz text DEFAULT 'TRY'::text,
    durum text DEFAULT 'aktif'::text NOT NULL,
    aciklama text,
    olusturma_tarihi timestamp with time zone DEFAULT now() NOT NULL,
    guncelleme_tarihi timestamp with time zone DEFAULT now() NOT NULL,
    silindi boolean DEFAULT false
);


--
-- Name: ic_talep_kalemleri; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ic_talep_kalemleri (
    id bigint NOT NULL,
    talep_id bigint,
    urun_kodu text,
    urun_adi text,
    talep_miktar numeric,
    onaylanan_miktar numeric,
    birim text,
    not_alani text
);


--
-- Name: ic_talep_kalemleri_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.ic_talep_kalemleri ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.ic_talep_kalemleri_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: ic_talepler; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ic_talepler (
    id bigint NOT NULL,
    otel_id text,
    departman_id text,
    departman_ad text,
    personel_ad text,
    personel_rol text,
    not_alani text,
    durum text DEFAULT 'bekleyen'::text,
    tarih date,
    olusturma_tarihi timestamp with time zone DEFAULT now(),
    onaylayan_ad text,
    onay_tarihi timestamp with time zone,
    red_notu text
);


--
-- Name: ic_talepler_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.ic_talepler ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.ic_talepler_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: kayitli_filtreler; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.kayitli_filtreler (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    kullanici_id text,
    ekran text NOT NULL,
    ad text NOT NULL,
    filtreler jsonb NOT NULL,
    paylasimli boolean DEFAULT false NOT NULL,
    olusturma_tarihi timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: koli_etiketleri; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.koli_etiketleri (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    mk_id uuid,
    mk_urun_id uuid,
    urun_kodu text,
    urun_adi text NOT NULL,
    birim text DEFAULT 'KG'::text,
    miktar numeric NOT NULL,
    koli_no integer,
    seri_no text,
    marka text,
    skt_tarihi date,
    otel_id text,
    depo_kodu text,
    durum text DEFAULT 'depoda'::text,
    cikis_depo text,
    cikis_tarihi timestamp with time zone,
    olusturma_tarihi timestamp with time zone DEFAULT now(),
    birim_fiyat numeric,
    fiyat_kaynagi text
);


--
-- Name: kullanicilar; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.kullanicilar (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    auth_user_id uuid,
    ad text NOT NULL,
    pin_hash text,
    rol public.kullanici_rol NOT NULL,
    departman text,
    otel_id public.otel_id,
    aktif boolean DEFAULT true NOT NULL,
    olusturma_tarihi timestamp with time zone DEFAULT now() NOT NULL,
    rol_id uuid,
    gizli boolean DEFAULT false,
    depo_id text,
    eposta text,
    tum_oteller boolean DEFAULT false NOT NULL
);


--
-- Name: kullanicilar_genel; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.kullanicilar_genel AS
 SELECT id,
    auth_user_id,
    ad,
    rol,
    departman,
    otel_id,
    aktif,
    olusturma_tarihi,
    rol_id,
    gizli,
    depo_id,
    eposta
   FROM public.kullanicilar k
  WHERE ((public.auth_erp_kullanicisi() IS TRUE) AND ((public.auth_tum_oteller() IS TRUE) OR (public.auth_otel_erisim((otel_id)::text) IS TRUE) OR (auth_user_id = auth.uid())));


--
-- Name: ln_siparisler; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ln_siparisler (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    siparis_no text NOT NULL,
    firma text,
    tarih text,
    kalemler jsonb DEFAULT '[]'::jsonb,
    durum text DEFAULT 'bekleyen'::text,
    yuklenme_tarihi timestamp with time zone DEFAULT now()
);


--
-- Name: mal_kabul_urunleri; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mal_kabul_urunleri (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    mk_id uuid NOT NULL,
    urun_kodu text,
    urun_adi text NOT NULL,
    birim text DEFAULT 'KG'::text NOT NULL,
    miktar numeric(12,3) NOT NULL,
    birim_fiyat numeric(12,4),
    seri_no text,
    marka text,
    sicaklik text
);


--
-- Name: mali_donemler; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mali_donemler (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    ad text NOT NULL,
    baslangic date NOT NULL,
    bitis date NOT NULL,
    durum text DEFAULT 'acik'::text NOT NULL
);


--
-- Name: menu_urunler; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.menu_urunler (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    ad text NOT NULL,
    kategori text,
    otel_id public.otel_id NOT NULL,
    fiyat numeric(12,2) DEFAULT 0,
    aktif boolean DEFAULT true NOT NULL,
    ucretli boolean DEFAULT false NOT NULL,
    tip text DEFAULT 'direkt'::text NOT NULL,
    stok_kodu text,
    miktar_per_porsiyon numeric(12,3),
    silindi boolean DEFAULT false NOT NULL,
    guncelleme_tarihi timestamp with time zone DEFAULT now(),
    CONSTRAINT menu_urunler_tip_check CHECK ((tip = ANY (ARRAY['direkt'::text, 'receteli'::text])))
);


--
-- Name: moduller; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.moduller (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    kod text NOT NULL,
    ad text NOT NULL,
    kategori text NOT NULL,
    sira integer DEFAULT 0,
    aktif boolean DEFAULT true NOT NULL
);


--
-- Name: recete_bilesenleri; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.recete_bilesenleri (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    menu_urun_id uuid NOT NULL,
    stok_kodu text NOT NULL,
    miktar_per_porsiyon numeric(12,3) NOT NULL,
    birim text
);


--
-- Name: recete_kalemleri; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.recete_kalemleri (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    recete_id uuid NOT NULL,
    urun_kodu text NOT NULL,
    urun_adi text NOT NULL,
    miktar numeric NOT NULL,
    birim text NOT NULL
);


--
-- Name: recete_tuketimleri; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.recete_tuketimleri (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    recete_id uuid,
    recete_ad text NOT NULL,
    porsiyon_sayisi numeric NOT NULL,
    birim_maliyet numeric NOT NULL,
    toplam_maliyet numeric NOT NULL,
    satis_fiyati numeric,
    food_cost_yuzde numeric,
    depo_kodu text,
    otel_id text,
    tarih date DEFAULT CURRENT_DATE,
    olusturan_ad text,
    olusturma_tarihi timestamp with time zone DEFAULT now()
);


--
-- Name: receteler; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.receteler (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    ad text NOT NULL,
    kategori text DEFAULT 'yemek'::text,
    rol text NOT NULL,
    otel_id text,
    porsiyon_birim text DEFAULT 'porsiyon'::text,
    satis_fiyati numeric,
    aciklama text,
    aktif boolean DEFAULT true,
    olusturan_ad text,
    olusturma_tarihi timestamp with time zone DEFAULT now(),
    guncelleme_tarihi timestamp with time zone DEFAULT now()
);


--
-- Name: roller; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.roller (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    ad text NOT NULL,
    seviye public.rol_seviye NOT NULL,
    aciklama text,
    sira integer DEFAULT 0,
    aktif boolean DEFAULT true NOT NULL,
    olusturma_tarihi timestamp with time zone DEFAULT now() NOT NULL,
    kod text,
    gizli boolean DEFAULT false
);


--
-- Name: satin_alma_talep_kalemleri; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.satin_alma_talep_kalemleri (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    talep_id uuid NOT NULL,
    urun_adi text NOT NULL,
    urun_kodu text,
    miktar numeric(12,3) NOT NULL,
    birim text DEFAULT 'KG'::text NOT NULL
);


--
-- Name: satin_alma_talepleri; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.satin_alma_talepleri (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    talep_no text,
    departman text NOT NULL,
    aciliyet text DEFAULT 'normal'::text NOT NULL,
    otel_id public.otel_id NOT NULL,
    not_alani text,
    durum public.talep_durum DEFAULT 'bekliyor'::public.talep_durum NOT NULL,
    siparis_no text,
    talep_eden text,
    olusturma_tarihi timestamp with time zone DEFAULT now() NOT NULL,
    asama text DEFAULT 'depo'::text,
    tutar numeric,
    onaylayan_ad text,
    onay_tarihi timestamp with time zone
);


--
-- Name: sayim_detaylari; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sayim_detaylari (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    oturum_id uuid,
    urun_kodu text NOT NULL,
    urun_adi text,
    birim text,
    sistem_miktar numeric DEFAULT 0,
    sayilan_miktar numeric DEFAULT 0,
    fark numeric DEFAULT 0,
    fark_yuzde numeric DEFAULT 0,
    aciklama text
);


--
-- Name: sayim_oturumlari; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sayim_oturumlari (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    depo_kodu text NOT NULL,
    otel_id text,
    olusturma_tarihi timestamp with time zone DEFAULT now(),
    olusturan_ad text,
    durum text DEFAULT 'onay_bekliyor'::text,
    onaylayan_ad text,
    onay_tarihi timestamp with time zone,
    toplam_urun_sayisi integer DEFAULT 0,
    farkli_urun_sayisi integer DEFAULT 0,
    genel_not text,
    red_nedeni text,
    kismi_uygulandi boolean DEFAULT false
);


--
-- Name: sene_sonu_kapanislar; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sene_sonu_kapanislar (
    yil integer NOT NULL,
    kapanma_tarihi timestamp with time zone DEFAULT now() NOT NULL,
    brut_kar_zarar numeric(14,2) NOT NULL,
    vergi numeric(14,2) DEFAULT 0,
    net_sonuc numeric(14,2) NOT NULL,
    kullanan text,
    silindi boolean DEFAULT false
);


--
-- Name: siparis_kalemleri; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.siparis_kalemleri (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    siparis_no text NOT NULL,
    urun_kodu text,
    urun_adi text NOT NULL,
    birim text DEFAULT 'KG'::text NOT NULL,
    miktar numeric(12,3) NOT NULL,
    gelen_miktar numeric(12,3) DEFAULT 0 NOT NULL,
    kalan_miktar numeric(12,3) NOT NULL,
    birim_fiyat numeric(12,4),
    tahmini_fiyat numeric
);


--
-- Name: siparisler; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.siparisler (
    siparis_no text NOT NULL,
    cari_id uuid,
    firma_ad text NOT NULL,
    otel_id public.otel_id NOT NULL,
    tarih date NOT NULL,
    termin_tarihi date,
    durum text DEFAULT 'islemde'::text NOT NULL,
    tip text DEFAULT 'normal'::text NOT NULL,
    iade_nedeni text,
    olusturan_ad text,
    olusturma_tarihi timestamp with time zone DEFAULT now() NOT NULL,
    son_guncelleme timestamp with time zone DEFAULT now() NOT NULL,
    orijinal_fatura_no text,
    kaynak text DEFAULT 'satinalma'::text,
    not_alani text,
    gonderildi_muhasebe boolean DEFAULT false,
    muhasebe_fatura_id uuid,
    fiyatlandirildi boolean DEFAULT false,
    fiyatlandiran_ad text,
    fiyatlandirma_tarihi timestamp with time zone,
    gonderilme_tarihi timestamp with time zone,
    bagli_faturalar jsonb DEFAULT '[]'::jsonb,
    depo_kodu text
);


--
-- Name: stok_rezervasyonlari; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.stok_rezervasyonlari (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    stok_kodu text NOT NULL,
    otel_id public.otel_id NOT NULL,
    depo_id text NOT NULL,
    miktar numeric(12,3) NOT NULL,
    siparis_kalem_id uuid NOT NULL,
    durum public.rezervasyon_durum DEFAULT 'aktif'::public.rezervasyon_durum NOT NULL,
    olusturma_zamani timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT stok_rezervasyonlari_miktar_check CHECK ((miktar > (0)::numeric))
);


--
-- Name: talep_onay_gecmisi; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.talep_onay_gecmisi (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    talep_id uuid,
    asama text NOT NULL,
    rol_kodu text,
    kullanici_ad text,
    karar text NOT NULL,
    not_metni text,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: tedarikci_urun_eslesme; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tedarikci_urun_eslesme (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    firma_ad text NOT NULL,
    firma_kod text,
    cari_id uuid,
    urun_kodu text NOT NULL
);


--
-- Name: teklif_fiyatlari; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.teklif_fiyatlari (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    teklif_kalemi_id uuid NOT NULL,
    firma_id integer,
    firma_ad text NOT NULL,
    birim_fiyat numeric NOT NULL,
    giris_tarihi timestamp with time zone DEFAULT now() NOT NULL,
    giren_kullanici text NOT NULL,
    not_alani text
);


--
-- Name: teklif_kalemleri; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.teklif_kalemleri (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    teklif_talebi_id uuid NOT NULL,
    urun_kodu text,
    urun_adi text NOT NULL,
    miktar numeric NOT NULL,
    birim text NOT NULL,
    kaynak_ic_talep_kalemi_id uuid,
    secilen_teklif_id uuid
);


--
-- Name: teklif_talepleri; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.teklif_talepleri (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    olusturma_tarihi timestamp with time zone DEFAULT now() NOT NULL,
    olusturan text NOT NULL,
    otel_id text,
    durum text DEFAULT 'acik'::text NOT NULL,
    not_alani text
);


--
-- Name: urun_birim_donusum; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.urun_birim_donusum (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    urun_kodu text NOT NULL,
    buyuk_birim text NOT NULL,
    carpan numeric NOT NULL,
    silindi boolean DEFAULT false NOT NULL,
    guncelleme_tarihi timestamp with time zone DEFAULT now(),
    CONSTRAINT urun_birim_donusum_carpan_check CHECK ((carpan > (0)::numeric))
);


--
-- Name: urun_fifo_fiyat; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.urun_fifo_fiyat WITH (security_invoker='true') AS
 SELECT DISTINCT ON (urun_kodu) urun_kodu,
    birim_fiyat,
    birim,
    fiyat_kaynagi,
    olusturma_tarihi AS giris_tarihi
   FROM public.koli_etiketleri
  WHERE ((durum = 'depoda'::text) AND (birim_fiyat IS NOT NULL) AND (urun_kodu IS NOT NULL) AND (urun_kodu <> ''::text))
  ORDER BY urun_kodu, olusturma_tarihi;


--
-- Name: urun_guncel_fiyat; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.urun_guncel_fiyat WITH (security_invoker='true') AS
 SELECT DISTINCT ON (fk.urun_kodu) fk.urun_kodu,
    fk.urun_adi,
    fk.birim,
    fk.birim_fiyat,
    f.tarih AS fiyat_tarihi
   FROM (public.fatura_kalemleri fk
     JOIN public.faturalar f ON ((f.id = fk.fatura_id)))
  WHERE ((f.tur = 'alis'::public.fatura_tur) AND (f.durum <> 'iptal'::public.fatura_durum) AND (fk.urun_kodu IS NOT NULL) AND (fk.urun_kodu <> ''::text))
  ORDER BY fk.urun_kodu, f.tarih DESC, f.olusturma_tarihi DESC;


--
-- Name: uygunsuzluklar; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.uygunsuzluklar (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    mk_id uuid,
    urun_kodu text,
    otel_id public.otel_id NOT NULL,
    aciklama text NOT NULL,
    fotograf_url text,
    durum public.uygunsuzluk_durum DEFAULT 'acik'::public.uygunsuzluk_durum NOT NULL,
    bildiren_ad text,
    olusturma_tarihi timestamp with time zone DEFAULT now() NOT NULL,
    kapanma_tarihi timestamp with time zone,
    karar text,
    faaliyet_aciklama text,
    faaliyet_yapan text,
    faaliyet_tarih date
);


--
-- Name: virmanlar; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.virmanlar (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    kaynak_hesap_id uuid NOT NULL,
    hedef_hesap_id uuid NOT NULL,
    tutar numeric(14,2) NOT NULL,
    tarih date NOT NULL,
    aciklama text,
    olusturma_tarihi timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT chk_farkli_hesap CHECK ((kaynak_hesap_id <> hedef_hesap_id)),
    CONSTRAINT virmanlar_tutar_check CHECK ((tutar > (0)::numeric))
);


--
-- Name: yetki_matrisi; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.yetki_matrisi (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    rol_id uuid NOT NULL,
    modul_id uuid NOT NULL,
    yetki public.yetki_seviye DEFAULT 'yok'::public.yetki_seviye NOT NULL,
    guncelleyen text,
    guncelleme_tarihi timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: yevmiye_fisler; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.yevmiye_fisler (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    no text NOT NULL,
    tarih date NOT NULL,
    tip text NOT NULL,
    belge_no text,
    aciklama text,
    otel_id public.otel_id NOT NULL,
    toplam_borc numeric(14,2) NOT NULL,
    toplam_alacak numeric(14,2) NOT NULL,
    onaylandi boolean DEFAULT true NOT NULL,
    otomatik boolean DEFAULT false NOT NULL,
    olusturma_tarihi timestamp with time zone DEFAULT now() NOT NULL,
    guncelleme_tarihi timestamp with time zone DEFAULT now() NOT NULL,
    silindi boolean DEFAULT false,
    CONSTRAINT chk_denge CHECK ((toplam_borc = toplam_alacak))
);


--
-- Name: yevmiye_kalemleri; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.yevmiye_kalemleri (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    fis_id uuid NOT NULL,
    hesap_kodu text NOT NULL,
    masraf_merkezi text,
    aciklama text,
    borc numeric(14,2) DEFAULT 0 NOT NULL,
    alacak numeric(14,2) DEFAULT 0 NOT NULL,
    CONSTRAINT chk_tek_yon CHECK ((NOT ((borc > (0)::numeric) AND (alacak > (0)::numeric))))
);


--
-- Name: yevmiye_no_seq_2026; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.yevmiye_no_seq_2026
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: amortisman_kosustu amortisman_kosustu_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.amortisman_kosustu
    ADD CONSTRAINT amortisman_kosustu_pkey PRIMARY KEY (donem);


--
-- Name: audit_log audit_log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_log
    ADD CONSTRAINT audit_log_pkey PRIMARY KEY (id);


--
-- Name: banka_kasa_hareketleri banka_kasa_hareketleri_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.banka_kasa_hareketleri
    ADD CONSTRAINT banka_kasa_hareketleri_pkey PRIMARY KEY (id);


--
-- Name: banka_kasa_hesaplari banka_kasa_hesaplari_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.banka_kasa_hesaplari
    ADD CONSTRAINT banka_kasa_hesaplari_pkey PRIMARY KEY (id);


--
-- Name: bar_siparis_kalemleri bar_siparis_kalemleri_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bar_siparis_kalemleri
    ADD CONSTRAINT bar_siparis_kalemleri_pkey PRIMARY KEY (id);


--
-- Name: bar_siparisleri bar_siparisleri_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bar_siparisleri
    ADD CONSTRAINT bar_siparisleri_pkey PRIMARY KEY (id);


--
-- Name: butce_kayitlari butce_kayitlari_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.butce_kayitlari
    ADD CONSTRAINT butce_kayitlari_pkey PRIMARY KEY (id);


--
-- Name: butce_kayitlari butce_kayitlari_yil_otel_id_hesap_kodu_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.butce_kayitlari
    ADD CONSTRAINT butce_kayitlari_yil_otel_id_hesap_kodu_key UNIQUE (yil, otel_id, hesap_kodu);


--
-- Name: cari_hareketler cari_hareketler_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cari_hareketler
    ADD CONSTRAINT cari_hareketler_pkey PRIMARY KEY (id);


--
-- Name: cariler cariler_kod_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cariler
    ADD CONSTRAINT cariler_kod_key UNIQUE (kod);


--
-- Name: cariler cariler_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cariler
    ADD CONSTRAINT cariler_pkey PRIMARY KEY (id);


--
-- Name: cek_senetler cek_senetler_no_banka_yon_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cek_senetler
    ADD CONSTRAINT cek_senetler_no_banka_yon_key UNIQUE (no, banka, yon);


--
-- Name: cek_senetler cek_senetler_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cek_senetler
    ADD CONSTRAINT cek_senetler_pkey PRIMARY KEY (id);


--
-- Name: demirbaslar demirbaslar_kod_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.demirbaslar
    ADD CONSTRAINT demirbaslar_kod_key UNIQUE (kod);


--
-- Name: demirbaslar demirbaslar_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.demirbaslar
    ADD CONSTRAINT demirbaslar_pkey PRIMARY KEY (id);


--
-- Name: doviz_kurlari doviz_kurlari_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.doviz_kurlari
    ADD CONSTRAINT doviz_kurlari_pkey PRIMARY KEY (tarih, para_birimi);


--
-- Name: edefter_kurum_bilgileri edefter_kurum_bilgileri_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.edefter_kurum_bilgileri
    ADD CONSTRAINT edefter_kurum_bilgileri_pkey PRIMARY KEY (id);


--
-- Name: edefter_sube_bilgileri edefter_sube_bilgileri_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.edefter_sube_bilgileri
    ADD CONSTRAINT edefter_sube_bilgileri_pkey PRIMARY KEY (otel_id);


--
-- Name: erp_islem_audit erp_islem_audit_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.erp_islem_audit
    ADD CONSTRAINT erp_islem_audit_pkey PRIMARY KEY (id);


--
-- Name: excel_import_gecmisi excel_import_gecmisi_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.excel_import_gecmisi
    ADD CONSTRAINT excel_import_gecmisi_pkey PRIMARY KEY (id);


--
-- Name: excel_import_satirlari excel_import_satirlari_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.excel_import_satirlari
    ADD CONSTRAINT excel_import_satirlari_pkey PRIMARY KEY (id);


--
-- Name: fatura_kalemleri fatura_kalemleri_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fatura_kalemleri
    ADD CONSTRAINT fatura_kalemleri_pkey PRIMARY KEY (id);


--
-- Name: faturalar faturalar_no_tur_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.faturalar
    ADD CONSTRAINT faturalar_no_tur_key UNIQUE (no, tur);


--
-- Name: faturalar faturalar_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.faturalar
    ADD CONSTRAINT faturalar_pkey PRIMARY KEY (id);


--
-- Name: gelen_efaturalar gelen_efaturalar_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gelen_efaturalar
    ADD CONSTRAINT gelen_efaturalar_pkey PRIMARY KEY (id);


--
-- Name: giris_denemeleri giris_denemeleri_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.giris_denemeleri
    ADD CONSTRAINT giris_denemeleri_pkey PRIMARY KEY (id);


--
-- Name: giris_kayitlari giris_kayitlari_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.giris_kayitlari
    ADD CONSTRAINT giris_kayitlari_pkey PRIMARY KEY (id);


--
-- Name: hesap_plani hesap_plani_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hesap_plani
    ADD CONSTRAINT hesap_plani_pkey PRIMARY KEY (kod);


--
-- Name: ic_talep_kalemleri ic_talep_kalemleri_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ic_talep_kalemleri
    ADD CONSTRAINT ic_talep_kalemleri_pkey PRIMARY KEY (id);


--
-- Name: ic_talepler ic_talepler_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ic_talepler
    ADD CONSTRAINT ic_talepler_pkey PRIMARY KEY (id);


--
-- Name: kayitli_filtreler kayitli_filtreler_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.kayitli_filtreler
    ADD CONSTRAINT kayitli_filtreler_pkey PRIMARY KEY (id);


--
-- Name: koli_etiketleri koli_etiketleri_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.koli_etiketleri
    ADD CONSTRAINT koli_etiketleri_pkey PRIMARY KEY (id);


--
-- Name: kullanicilar kullanicilar_eposta_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.kullanicilar
    ADD CONSTRAINT kullanicilar_eposta_key UNIQUE (eposta);


--
-- Name: kullanicilar kullanicilar_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.kullanicilar
    ADD CONSTRAINT kullanicilar_pkey PRIMARY KEY (id);


--
-- Name: ln_siparisler ln_siparisler_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ln_siparisler
    ADD CONSTRAINT ln_siparisler_pkey PRIMARY KEY (id);


--
-- Name: ln_siparisler ln_siparisler_siparis_no_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ln_siparisler
    ADD CONSTRAINT ln_siparisler_siparis_no_key UNIQUE (siparis_no);


--
-- Name: mal_kabul_urunleri mal_kabul_urunleri_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mal_kabul_urunleri
    ADD CONSTRAINT mal_kabul_urunleri_pkey PRIMARY KEY (id);


--
-- Name: mal_kabuller mal_kabuller_mk_no_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mal_kabuller
    ADD CONSTRAINT mal_kabuller_mk_no_key UNIQUE (mk_no);


--
-- Name: mal_kabuller mal_kabuller_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mal_kabuller
    ADD CONSTRAINT mal_kabuller_pkey PRIMARY KEY (id);


--
-- Name: mali_donemler mali_donemler_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mali_donemler
    ADD CONSTRAINT mali_donemler_pkey PRIMARY KEY (id);


--
-- Name: menu_urunler menu_urunler_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.menu_urunler
    ADD CONSTRAINT menu_urunler_pkey PRIMARY KEY (id);


--
-- Name: moduller moduller_kod_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.moduller
    ADD CONSTRAINT moduller_kod_key UNIQUE (kod);


--
-- Name: moduller moduller_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.moduller
    ADD CONSTRAINT moduller_pkey PRIMARY KEY (id);


--
-- Name: recete_bilesenleri recete_bilesenleri_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recete_bilesenleri
    ADD CONSTRAINT recete_bilesenleri_pkey PRIMARY KEY (id);


--
-- Name: recete_kalemleri recete_kalemleri_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recete_kalemleri
    ADD CONSTRAINT recete_kalemleri_pkey PRIMARY KEY (id);


--
-- Name: recete_tuketimleri recete_tuketimleri_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recete_tuketimleri
    ADD CONSTRAINT recete_tuketimleri_pkey PRIMARY KEY (id);


--
-- Name: receteler receteler_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.receteler
    ADD CONSTRAINT receteler_pkey PRIMARY KEY (id);


--
-- Name: roller roller_ad_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roller
    ADD CONSTRAINT roller_ad_key UNIQUE (ad);


--
-- Name: roller roller_kod_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roller
    ADD CONSTRAINT roller_kod_key UNIQUE (kod);


--
-- Name: roller roller_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roller
    ADD CONSTRAINT roller_pkey PRIMARY KEY (id);


--
-- Name: satin_alma_talep_kalemleri satin_alma_talep_kalemleri_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.satin_alma_talep_kalemleri
    ADD CONSTRAINT satin_alma_talep_kalemleri_pkey PRIMARY KEY (id);


--
-- Name: satin_alma_talepleri satin_alma_talepleri_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.satin_alma_talepleri
    ADD CONSTRAINT satin_alma_talepleri_pkey PRIMARY KEY (id);


--
-- Name: satin_alma_talepleri satin_alma_talepleri_talep_no_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.satin_alma_talepleri
    ADD CONSTRAINT satin_alma_talepleri_talep_no_key UNIQUE (talep_no);


--
-- Name: sayim_detaylari sayim_detaylari_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sayim_detaylari
    ADD CONSTRAINT sayim_detaylari_pkey PRIMARY KEY (id);


--
-- Name: sayim_oturumlari sayim_oturumlari_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sayim_oturumlari
    ADD CONSTRAINT sayim_oturumlari_pkey PRIMARY KEY (id);


--
-- Name: sene_sonu_kapanislar sene_sonu_kapanislar_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sene_sonu_kapanislar
    ADD CONSTRAINT sene_sonu_kapanislar_pkey PRIMARY KEY (yil);


--
-- Name: siparis_kalemleri siparis_kalemleri_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.siparis_kalemleri
    ADD CONSTRAINT siparis_kalemleri_pkey PRIMARY KEY (id);


--
-- Name: siparisler siparisler_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.siparisler
    ADD CONSTRAINT siparisler_pkey PRIMARY KEY (siparis_no);


--
-- Name: skt_kayitlari skt_kayitlari_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.skt_kayitlari
    ADD CONSTRAINT skt_kayitlari_pkey PRIMARY KEY (id);


--
-- Name: stok_hareketleri stok_hareketleri_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stok_hareketleri
    ADD CONSTRAINT stok_hareketleri_pkey PRIMARY KEY (id);


--
-- Name: stok_minimumlar stok_minimumlar_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stok_minimumlar
    ADD CONSTRAINT stok_minimumlar_pkey PRIMARY KEY (id);


--
-- Name: stok_minimumlar stok_minimumlar_urun_kodu_depo_kodu_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stok_minimumlar
    ADD CONSTRAINT stok_minimumlar_urun_kodu_depo_kodu_key UNIQUE (urun_kodu, depo_kodu);


--
-- Name: stok stok_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stok
    ADD CONSTRAINT stok_pkey PRIMARY KEY (id);


--
-- Name: stok_rezervasyonlari stok_rezervasyonlari_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stok_rezervasyonlari
    ADD CONSTRAINT stok_rezervasyonlari_pkey PRIMARY KEY (id);


--
-- Name: stok stok_urun_kodu_depo_kodu_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stok
    ADD CONSTRAINT stok_urun_kodu_depo_kodu_key UNIQUE (urun_kodu, depo_kodu);


--
-- Name: talep_onay_gecmisi talep_onay_gecmisi_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.talep_onay_gecmisi
    ADD CONSTRAINT talep_onay_gecmisi_pkey PRIMARY KEY (id);


--
-- Name: tedarikci_urun_eslesme tedarikci_urun_eslesme_firma_ad_urun_kodu_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tedarikci_urun_eslesme
    ADD CONSTRAINT tedarikci_urun_eslesme_firma_ad_urun_kodu_key UNIQUE (firma_ad, urun_kodu);


--
-- Name: tedarikci_urun_eslesme tedarikci_urun_eslesme_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tedarikci_urun_eslesme
    ADD CONSTRAINT tedarikci_urun_eslesme_pkey PRIMARY KEY (id);


--
-- Name: teklif_fiyatlari teklif_fiyatlari_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.teklif_fiyatlari
    ADD CONSTRAINT teklif_fiyatlari_pkey PRIMARY KEY (id);


--
-- Name: teklif_kalemleri teklif_kalemleri_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.teklif_kalemleri
    ADD CONSTRAINT teklif_kalemleri_pkey PRIMARY KEY (id);


--
-- Name: teklif_talepleri teklif_talepleri_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.teklif_talepleri
    ADD CONSTRAINT teklif_talepleri_pkey PRIMARY KEY (id);


--
-- Name: urun_alt_gruplari urun_alt_gruplari_alt_grup_kod_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.urun_alt_gruplari
    ADD CONSTRAINT urun_alt_gruplari_alt_grup_kod_key UNIQUE (alt_grup_kod);


--
-- Name: urun_alt_gruplari urun_alt_gruplari_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.urun_alt_gruplari
    ADD CONSTRAINT urun_alt_gruplari_pkey PRIMARY KEY (id);


--
-- Name: urun_ana_gruplari urun_ana_gruplari_ana_grup_kod_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.urun_ana_gruplari
    ADD CONSTRAINT urun_ana_gruplari_ana_grup_kod_key UNIQUE (ana_grup_kod);


--
-- Name: urun_ana_gruplari urun_ana_gruplari_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.urun_ana_gruplari
    ADD CONSTRAINT urun_ana_gruplari_pkey PRIMARY KEY (id);


--
-- Name: urun_birim_donusum urun_birim_donusum_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.urun_birim_donusum
    ADD CONSTRAINT urun_birim_donusum_pkey PRIMARY KEY (id);


--
-- Name: urun_birim_donusum urun_birim_donusum_urun_kodu_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.urun_birim_donusum
    ADD CONSTRAINT urun_birim_donusum_urun_kodu_key UNIQUE (urun_kodu);


--
-- Name: urun_siniflandirma urun_siniflandirma_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.urun_siniflandirma
    ADD CONSTRAINT urun_siniflandirma_pkey PRIMARY KEY (id);


--
-- Name: urun_siniflandirma urun_siniflandirma_urun_kodu_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.urun_siniflandirma
    ADD CONSTRAINT urun_siniflandirma_urun_kodu_key UNIQUE (urun_kodu);


--
-- Name: urunler urunler_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.urunler
    ADD CONSTRAINT urunler_pkey PRIMARY KEY (kod);


--
-- Name: uygunsuzluklar uygunsuzluklar_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.uygunsuzluklar
    ADD CONSTRAINT uygunsuzluklar_pkey PRIMARY KEY (id);


--
-- Name: virmanlar virmanlar_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.virmanlar
    ADD CONSTRAINT virmanlar_pkey PRIMARY KEY (id);


--
-- Name: yetki_matrisi yetki_matrisi_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.yetki_matrisi
    ADD CONSTRAINT yetki_matrisi_pkey PRIMARY KEY (id);


--
-- Name: yetki_matrisi yetki_matrisi_rol_id_modul_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.yetki_matrisi
    ADD CONSTRAINT yetki_matrisi_rol_id_modul_id_key UNIQUE (rol_id, modul_id);


--
-- Name: yevmiye_fisler yevmiye_fisler_no_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.yevmiye_fisler
    ADD CONSTRAINT yevmiye_fisler_no_key UNIQUE (no);


--
-- Name: yevmiye_fisler yevmiye_fisler_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.yevmiye_fisler
    ADD CONSTRAINT yevmiye_fisler_pkey PRIMARY KEY (id);


--
-- Name: yevmiye_kalemleri yevmiye_kalemleri_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.yevmiye_kalemleri
    ADD CONSTRAINT yevmiye_kalemleri_pkey PRIMARY KEY (id);


--
-- Name: erp_islem_audit_entity; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX erp_islem_audit_entity ON public.erp_islem_audit USING btree (entity_type, entity_id);


--
-- Name: erp_islem_audit_hotel_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX erp_islem_audit_hotel_time ON public.erp_islem_audit USING btree (hotel_id, server_timestamp DESC);


--
-- Name: giris_denemeleri_ip_zaman_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX giris_denemeleri_ip_zaman_idx ON public.giris_denemeleri USING btree (ip_hash, created_at DESC);


--
-- Name: giris_denemeleri_zaman_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX giris_denemeleri_zaman_idx ON public.giris_denemeleri USING btree (created_at DESC) WHERE (basarili = false);


--
-- Name: giris_kayitlari_zaman_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX giris_kayitlari_zaman_idx ON public.giris_kayitlari USING btree (created_at DESC);


--
-- Name: idx_audit_log_entity; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_log_entity ON public.audit_log USING btree (entity_type, entity_id);


--
-- Name: idx_audit_log_zaman; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_log_zaman ON public.audit_log USING btree (zaman);


--
-- Name: idx_banka_hareket_hesap; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_banka_hareket_hesap ON public.banka_kasa_hareketleri USING btree (hesap_id);


--
-- Name: idx_banka_hareket_tarih; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_banka_hareket_tarih ON public.banka_kasa_hareketleri USING btree (tarih);


--
-- Name: idx_cari_hareketler_belge; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cari_hareketler_belge ON public.cari_hareketler USING btree (belge_no);


--
-- Name: idx_cari_hareketler_cari; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cari_hareketler_cari ON public.cari_hareketler USING btree (cari_id);


--
-- Name: idx_cari_hareketler_tarih; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cari_hareketler_tarih ON public.cari_hareketler USING btree (tarih);


--
-- Name: idx_cariler_ad; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cariler_ad ON public.cariler USING gin (to_tsvector('turkish'::regconfig, ad));


--
-- Name: idx_cariler_tip; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cariler_tip ON public.cariler USING btree (tip);


--
-- Name: idx_cek_senet_cari; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cek_senet_cari ON public.cek_senetler USING btree (cari_id);


--
-- Name: idx_cek_senet_durum; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cek_senet_durum ON public.cek_senetler USING btree (durum);


--
-- Name: idx_cek_senet_vade; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cek_senet_vade ON public.cek_senetler USING btree (vade_tarihi);


--
-- Name: idx_fatura_kalemleri_fatura; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_fatura_kalemleri_fatura ON public.fatura_kalemleri USING btree (fatura_id);


--
-- Name: idx_faturalar_cari; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_faturalar_cari ON public.faturalar USING btree (cari_id);


--
-- Name: idx_faturalar_durum; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_faturalar_durum ON public.faturalar USING btree (durum);


--
-- Name: idx_faturalar_tarih; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_faturalar_tarih ON public.faturalar USING btree (tarih);


--
-- Name: idx_hesap_plani_tip; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_hesap_plani_tip ON public.hesap_plani USING btree (tip);


--
-- Name: idx_hesap_plani_ust_kod; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_hesap_plani_ust_kod ON public.hesap_plani USING btree (ust_kod);


--
-- Name: idx_koli_durum; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_koli_durum ON public.koli_etiketleri USING btree (durum);


--
-- Name: idx_koli_fifo; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_koli_fifo ON public.koli_etiketleri USING btree (urun_kodu, durum, olusturma_tarihi);


--
-- Name: idx_koli_mk; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_koli_mk ON public.koli_etiketleri USING btree (mk_id);


--
-- Name: idx_mal_kabul_urunleri_mk; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_mal_kabul_urunleri_mk ON public.mal_kabul_urunleri USING btree (mk_id);


--
-- Name: idx_recete_kalemleri_recete; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_recete_kalemleri_recete ON public.recete_kalemleri USING btree (recete_id);


--
-- Name: idx_recete_tuketimleri_recete; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_recete_tuketimleri_recete ON public.recete_tuketimleri USING btree (recete_id);


--
-- Name: idx_recete_tuketimleri_tarih; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_recete_tuketimleri_tarih ON public.recete_tuketimleri USING btree (tarih);


--
-- Name: idx_siparis_kalemleri_siparis; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_siparis_kalemleri_siparis ON public.siparis_kalemleri USING btree (siparis_no);


--
-- Name: idx_skt_durum; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_skt_durum ON public.skt_kayitlari USING btree (durum);


--
-- Name: idx_skt_tarih; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_skt_tarih ON public.skt_kayitlari USING btree (skt_tarihi);


--
-- Name: idx_skt_urun; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_skt_urun ON public.skt_kayitlari USING btree (urun_kodu);


--
-- Name: idx_stok_depo; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_stok_depo ON public.stok USING btree (depo_kodu);


--
-- Name: idx_stok_hareket_tarih; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_stok_hareket_tarih ON public.stok_hareketleri USING btree (tarih);


--
-- Name: idx_stok_hareket_urun; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_stok_hareket_urun ON public.stok_hareketleri USING btree (urun_kodu);


--
-- Name: idx_stok_urun; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_stok_urun ON public.stok USING btree (urun_kodu);


--
-- Name: idx_talep_kalem_talep; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_talep_kalem_talep ON public.satin_alma_talep_kalemleri USING btree (talep_id);


--
-- Name: idx_tedarikci_urun_cari; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tedarikci_urun_cari ON public.tedarikci_urun_eslesme USING btree (cari_id) WHERE (cari_id IS NOT NULL);


--
-- Name: idx_tedarikci_urun_firma; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tedarikci_urun_firma ON public.tedarikci_urun_eslesme USING btree (firma_ad);


--
-- Name: idx_tedarikci_urun_urun; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tedarikci_urun_urun ON public.tedarikci_urun_eslesme USING btree (urun_kodu);


--
-- Name: idx_urunler_ad; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_urunler_ad ON public.urunler USING gin (to_tsvector('turkish'::regconfig, ad));


--
-- Name: idx_urunler_grup; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_urunler_grup ON public.urunler USING btree (grup);


--
-- Name: idx_uygunsuzluk_durum; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_uygunsuzluk_durum ON public.uygunsuzluklar USING btree (durum);


--
-- Name: idx_uygunsuzluk_mk; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_uygunsuzluk_mk ON public.uygunsuzluklar USING btree (mk_id);


--
-- Name: idx_yetki_modul; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_yetki_modul ON public.yetki_matrisi USING btree (modul_id);


--
-- Name: idx_yetki_rol; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_yetki_rol ON public.yetki_matrisi USING btree (rol_id);


--
-- Name: idx_yevmiye_kalemleri_fis; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_yevmiye_kalemleri_fis ON public.yevmiye_kalemleri USING btree (fis_id);


--
-- Name: idx_yevmiye_kalemleri_hesap; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_yevmiye_kalemleri_hesap ON public.yevmiye_kalemleri USING btree (hesap_kodu);


--
-- Name: idx_yevmiye_kalemleri_masraf; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_yevmiye_kalemleri_masraf ON public.yevmiye_kalemleri USING btree (masraf_merkezi) WHERE (masraf_merkezi IS NOT NULL);


--
-- Name: idx_yevmiye_otel; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_yevmiye_otel ON public.yevmiye_fisler USING btree (otel_id);


--
-- Name: idx_yevmiye_tarih; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_yevmiye_tarih ON public.yevmiye_fisler USING btree (tarih);


--
-- Name: idx_yevmiye_tip; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_yevmiye_tip ON public.yevmiye_fisler USING btree (tip);


--
-- Name: phase0_kullanici_auth_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX phase0_kullanici_auth_unique ON public.kullanicilar USING btree (auth_user_id) WHERE (auth_user_id IS NOT NULL);


--
-- Name: stok_minimumlar_urun_kodu_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX stok_minimumlar_urun_kodu_key ON public.stok_minimumlar USING btree (urun_kodu);


--
-- Name: stok_rezervasyonlari_aktif_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX stok_rezervasyonlari_aktif_idx ON public.stok_rezervasyonlari USING btree (stok_kodu, depo_id, durum) WHERE (durum = 'aktif'::public.rezervasyon_durum);


--
-- Name: erp_islem_audit phase0_audit_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER phase0_audit_immutable BEFORE DELETE OR UPDATE OR TRUNCATE ON public.erp_islem_audit FOR EACH STATEMENT EXECUTE FUNCTION phase0_private.audit_immutable();


--
-- Name: bar_siparisleri phase0_islem_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER phase0_islem_audit AFTER INSERT OR UPDATE ON public.bar_siparisleri FOR EACH ROW EXECUTE FUNCTION phase0_private.islem_audit();


--
-- Name: faturalar phase0_islem_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER phase0_islem_audit AFTER INSERT OR UPDATE ON public.faturalar FOR EACH ROW EXECUTE FUNCTION phase0_private.islem_audit();


--
-- Name: mal_kabuller phase0_islem_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER phase0_islem_audit AFTER INSERT OR UPDATE ON public.mal_kabuller FOR EACH ROW EXECUTE FUNCTION phase0_private.islem_audit();


--
-- Name: satin_alma_talepleri phase0_islem_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER phase0_islem_audit AFTER INSERT OR UPDATE ON public.satin_alma_talepleri FOR EACH ROW EXECUTE FUNCTION phase0_private.islem_audit();


--
-- Name: siparisler phase0_islem_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER phase0_islem_audit AFTER INSERT OR UPDATE ON public.siparisler FOR EACH ROW EXECUTE FUNCTION phase0_private.islem_audit();


--
-- Name: stok_hareketleri phase0_islem_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER phase0_islem_audit AFTER INSERT OR UPDATE ON public.stok_hareketleri FOR EACH ROW EXECUTE FUNCTION phase0_private.islem_audit();


--
-- Name: yevmiye_fisler phase0_islem_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER phase0_islem_audit AFTER INSERT OR UPDATE ON public.yevmiye_fisler FOR EACH ROW EXECUTE FUNCTION phase0_private.islem_audit();


--
-- Name: bar_siparisleri phase0_islem_audit_del; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER phase0_islem_audit_del BEFORE DELETE ON public.bar_siparisleri FOR EACH ROW EXECUTE FUNCTION phase0_private.islem_audit();


--
-- Name: faturalar phase0_islem_audit_del; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER phase0_islem_audit_del BEFORE DELETE ON public.faturalar FOR EACH ROW EXECUTE FUNCTION phase0_private.islem_audit();


--
-- Name: mal_kabuller phase0_islem_audit_del; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER phase0_islem_audit_del BEFORE DELETE ON public.mal_kabuller FOR EACH ROW EXECUTE FUNCTION phase0_private.islem_audit();


--
-- Name: satin_alma_talepleri phase0_islem_audit_del; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER phase0_islem_audit_del BEFORE DELETE ON public.satin_alma_talepleri FOR EACH ROW EXECUTE FUNCTION phase0_private.islem_audit();


--
-- Name: siparisler phase0_islem_audit_del; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER phase0_islem_audit_del BEFORE DELETE ON public.siparisler FOR EACH ROW EXECUTE FUNCTION phase0_private.islem_audit();


--
-- Name: stok_hareketleri phase0_islem_audit_del; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER phase0_islem_audit_del BEFORE DELETE ON public.stok_hareketleri FOR EACH ROW EXECUTE FUNCTION phase0_private.islem_audit();


--
-- Name: yevmiye_fisler phase0_islem_audit_del; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER phase0_islem_audit_del BEFORE DELETE ON public.yevmiye_fisler FOR EACH ROW EXECUTE FUNCTION phase0_private.islem_audit();


--
-- Name: banka_kasa_hareketleri phase0_otel_degismez; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER phase0_otel_degismez BEFORE UPDATE OF otel_id ON public.banka_kasa_hareketleri FOR EACH ROW EXECUTE FUNCTION phase0_private.otel_degismez();


--
-- Name: banka_kasa_hesaplari phase0_otel_degismez; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER phase0_otel_degismez BEFORE UPDATE OF otel_id ON public.banka_kasa_hesaplari FOR EACH ROW EXECUTE FUNCTION phase0_private.otel_degismez();


--
-- Name: bar_siparisleri phase0_otel_degismez; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER phase0_otel_degismez BEFORE UPDATE OF otel_id ON public.bar_siparisleri FOR EACH ROW EXECUTE FUNCTION phase0_private.otel_degismez();


--
-- Name: butce_kayitlari phase0_otel_degismez; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER phase0_otel_degismez BEFORE UPDATE OF otel_id ON public.butce_kayitlari FOR EACH ROW EXECUTE FUNCTION phase0_private.otel_degismez();


--
-- Name: cari_hareketler phase0_otel_degismez; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER phase0_otel_degismez BEFORE UPDATE OF otel_id ON public.cari_hareketler FOR EACH ROW EXECUTE FUNCTION phase0_private.otel_degismez();


--
-- Name: cek_senetler phase0_otel_degismez; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER phase0_otel_degismez BEFORE UPDATE OF otel_id ON public.cek_senetler FOR EACH ROW EXECUTE FUNCTION phase0_private.otel_degismez();


--
-- Name: demirbaslar phase0_otel_degismez; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER phase0_otel_degismez BEFORE UPDATE OF otel_id ON public.demirbaslar FOR EACH ROW EXECUTE FUNCTION phase0_private.otel_degismez();


--
-- Name: edefter_sube_bilgileri phase0_otel_degismez; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER phase0_otel_degismez BEFORE UPDATE OF otel_id ON public.edefter_sube_bilgileri FOR EACH ROW EXECUTE FUNCTION phase0_private.otel_degismez();


--
-- Name: faturalar phase0_otel_degismez; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER phase0_otel_degismez BEFORE UPDATE OF otel_id ON public.faturalar FOR EACH ROW EXECUTE FUNCTION phase0_private.otel_degismez();


--
-- Name: giris_kayitlari phase0_otel_degismez; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER phase0_otel_degismez BEFORE UPDATE OF otel_id ON public.giris_kayitlari FOR EACH ROW EXECUTE FUNCTION phase0_private.otel_degismez();


--
-- Name: ic_talepler phase0_otel_degismez; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER phase0_otel_degismez BEFORE UPDATE OF otel_id ON public.ic_talepler FOR EACH ROW EXECUTE FUNCTION phase0_private.otel_degismez();


--
-- Name: koli_etiketleri phase0_otel_degismez; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER phase0_otel_degismez BEFORE UPDATE OF otel_id ON public.koli_etiketleri FOR EACH ROW EXECUTE FUNCTION phase0_private.otel_degismez();


--
-- Name: mal_kabuller phase0_otel_degismez; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER phase0_otel_degismez BEFORE UPDATE OF otel_id ON public.mal_kabuller FOR EACH ROW EXECUTE FUNCTION phase0_private.otel_degismez();


--
-- Name: menu_urunler phase0_otel_degismez; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER phase0_otel_degismez BEFORE UPDATE OF otel_id ON public.menu_urunler FOR EACH ROW EXECUTE FUNCTION phase0_private.otel_degismez();


--
-- Name: recete_tuketimleri phase0_otel_degismez; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER phase0_otel_degismez BEFORE UPDATE OF otel_id ON public.recete_tuketimleri FOR EACH ROW EXECUTE FUNCTION phase0_private.otel_degismez();


--
-- Name: receteler phase0_otel_degismez; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER phase0_otel_degismez BEFORE UPDATE OF otel_id ON public.receteler FOR EACH ROW EXECUTE FUNCTION phase0_private.otel_degismez();


--
-- Name: satin_alma_talepleri phase0_otel_degismez; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER phase0_otel_degismez BEFORE UPDATE OF otel_id ON public.satin_alma_talepleri FOR EACH ROW EXECUTE FUNCTION phase0_private.otel_degismez();


--
-- Name: sayim_oturumlari phase0_otel_degismez; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER phase0_otel_degismez BEFORE UPDATE OF otel_id ON public.sayim_oturumlari FOR EACH ROW EXECUTE FUNCTION phase0_private.otel_degismez();


--
-- Name: siparisler phase0_otel_degismez; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER phase0_otel_degismez BEFORE UPDATE OF otel_id ON public.siparisler FOR EACH ROW EXECUTE FUNCTION phase0_private.otel_degismez();


--
-- Name: skt_kayitlari phase0_otel_degismez; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER phase0_otel_degismez BEFORE UPDATE OF otel_id ON public.skt_kayitlari FOR EACH ROW EXECUTE FUNCTION phase0_private.otel_degismez();


--
-- Name: stok phase0_otel_degismez; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER phase0_otel_degismez BEFORE UPDATE OF otel_id ON public.stok FOR EACH ROW EXECUTE FUNCTION phase0_private.otel_degismez();


--
-- Name: stok_hareketleri phase0_otel_degismez; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER phase0_otel_degismez BEFORE UPDATE OF otel_id ON public.stok_hareketleri FOR EACH ROW EXECUTE FUNCTION phase0_private.otel_degismez();


--
-- Name: stok_minimumlar phase0_otel_degismez; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER phase0_otel_degismez BEFORE UPDATE OF otel_id ON public.stok_minimumlar FOR EACH ROW EXECUTE FUNCTION phase0_private.otel_degismez();


--
-- Name: stok_rezervasyonlari phase0_otel_degismez; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER phase0_otel_degismez BEFORE UPDATE OF otel_id ON public.stok_rezervasyonlari FOR EACH ROW EXECUTE FUNCTION phase0_private.otel_degismez();


--
-- Name: teklif_talepleri phase0_otel_degismez; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER phase0_otel_degismez BEFORE UPDATE OF otel_id ON public.teklif_talepleri FOR EACH ROW EXECUTE FUNCTION phase0_private.otel_degismez();


--
-- Name: uygunsuzluklar phase0_otel_degismez; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER phase0_otel_degismez BEFORE UPDATE OF otel_id ON public.uygunsuzluklar FOR EACH ROW EXECUTE FUNCTION phase0_private.otel_degismez();


--
-- Name: yevmiye_fisler phase0_otel_degismez; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER phase0_otel_degismez BEFORE UPDATE OF otel_id ON public.yevmiye_fisler FOR EACH ROW EXECUTE FUNCTION phase0_private.otel_degismez();


--
-- Name: audit_log tg_audit_log_damgala; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER tg_audit_log_damgala BEFORE INSERT ON public.audit_log FOR EACH ROW EXECUTE FUNCTION public.audit_log_damgala();


--
-- Name: banka_kasa_hareketleri banka_kasa_hareketleri_hesap_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.banka_kasa_hareketleri
    ADD CONSTRAINT banka_kasa_hareketleri_hesap_id_fkey FOREIGN KEY (hesap_id) REFERENCES public.banka_kasa_hesaplari(id) ON DELETE RESTRICT;


--
-- Name: bar_siparis_kalemleri bar_siparis_kalemleri_menu_urun_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bar_siparis_kalemleri
    ADD CONSTRAINT bar_siparis_kalemleri_menu_urun_id_fkey FOREIGN KEY (menu_urun_id) REFERENCES public.menu_urunler(id);


--
-- Name: bar_siparis_kalemleri bar_siparis_kalemleri_siparis_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bar_siparis_kalemleri
    ADD CONSTRAINT bar_siparis_kalemleri_siparis_id_fkey FOREIGN KEY (siparis_id) REFERENCES public.bar_siparisleri(id);


--
-- Name: butce_kayitlari butce_kayitlari_hesap_kodu_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.butce_kayitlari
    ADD CONSTRAINT butce_kayitlari_hesap_kodu_fkey FOREIGN KEY (hesap_kodu) REFERENCES public.hesap_plani(kod);


--
-- Name: cari_hareketler cari_hareketler_cari_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cari_hareketler
    ADD CONSTRAINT cari_hareketler_cari_id_fkey FOREIGN KEY (cari_id) REFERENCES public.cariler(id) ON DELETE RESTRICT;


--
-- Name: cariler cariler_hesap_kodu_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cariler
    ADD CONSTRAINT cariler_hesap_kodu_fkey FOREIGN KEY (hesap_kodu) REFERENCES public.hesap_plani(kod);


--
-- Name: cek_senetler cek_senetler_cari_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cek_senetler
    ADD CONSTRAINT cek_senetler_cari_id_fkey FOREIGN KEY (cari_id) REFERENCES public.cariler(id);


--
-- Name: demirbaslar demirbaslar_amortisman_hesap_kodu_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.demirbaslar
    ADD CONSTRAINT demirbaslar_amortisman_hesap_kodu_fkey FOREIGN KEY (amortisman_hesap_kodu) REFERENCES public.hesap_plani(kod);


--
-- Name: demirbaslar demirbaslar_hesap_kodu_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.demirbaslar
    ADD CONSTRAINT demirbaslar_hesap_kodu_fkey FOREIGN KEY (hesap_kodu) REFERENCES public.hesap_plani(kod);


--
-- Name: excel_import_satirlari excel_import_satirlari_import_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.excel_import_satirlari
    ADD CONSTRAINT excel_import_satirlari_import_id_fkey FOREIGN KEY (import_id) REFERENCES public.excel_import_gecmisi(id);


--
-- Name: fatura_kalemleri fatura_kalemleri_fatura_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fatura_kalemleri
    ADD CONSTRAINT fatura_kalemleri_fatura_id_fkey FOREIGN KEY (fatura_id) REFERENCES public.faturalar(id) ON DELETE CASCADE;


--
-- Name: faturalar faturalar_cari_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.faturalar
    ADD CONSTRAINT faturalar_cari_id_fkey FOREIGN KEY (cari_id) REFERENCES public.cariler(id);


--
-- Name: cari_hareketler fk_cari_hareketler_fatura; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cari_hareketler
    ADD CONSTRAINT fk_cari_hareketler_fatura FOREIGN KEY (fatura_id) REFERENCES public.faturalar(id) ON DELETE SET NULL;


--
-- Name: hesap_plani hesap_plani_ust_kod_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hesap_plani
    ADD CONSTRAINT hesap_plani_ust_kod_fkey FOREIGN KEY (ust_kod) REFERENCES public.hesap_plani(kod);


--
-- Name: ic_talep_kalemleri ic_talep_kalemleri_talep_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ic_talep_kalemleri
    ADD CONSTRAINT ic_talep_kalemleri_talep_id_fkey FOREIGN KEY (talep_id) REFERENCES public.ic_talepler(id) ON DELETE CASCADE;


--
-- Name: koli_etiketleri koli_etiketleri_mk_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.koli_etiketleri
    ADD CONSTRAINT koli_etiketleri_mk_id_fkey FOREIGN KEY (mk_id) REFERENCES public.mal_kabuller(id) ON DELETE CASCADE;


--
-- Name: koli_etiketleri koli_etiketleri_mk_urun_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.koli_etiketleri
    ADD CONSTRAINT koli_etiketleri_mk_urun_id_fkey FOREIGN KEY (mk_urun_id) REFERENCES public.mal_kabul_urunleri(id) ON DELETE CASCADE;


--
-- Name: kullanicilar kullanicilar_auth_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.kullanicilar
    ADD CONSTRAINT kullanicilar_auth_user_id_fkey FOREIGN KEY (auth_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: kullanicilar kullanicilar_rol_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.kullanicilar
    ADD CONSTRAINT kullanicilar_rol_id_fkey FOREIGN KEY (rol_id) REFERENCES public.roller(id);


--
-- Name: mal_kabul_urunleri mal_kabul_urunleri_mk_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mal_kabul_urunleri
    ADD CONSTRAINT mal_kabul_urunleri_mk_id_fkey FOREIGN KEY (mk_id) REFERENCES public.mal_kabuller(id) ON DELETE CASCADE;


--
-- Name: recete_bilesenleri recete_bilesenleri_menu_urun_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recete_bilesenleri
    ADD CONSTRAINT recete_bilesenleri_menu_urun_id_fkey FOREIGN KEY (menu_urun_id) REFERENCES public.menu_urunler(id);


--
-- Name: recete_kalemleri recete_kalemleri_recete_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recete_kalemleri
    ADD CONSTRAINT recete_kalemleri_recete_id_fkey FOREIGN KEY (recete_id) REFERENCES public.receteler(id) ON DELETE CASCADE;


--
-- Name: recete_tuketimleri recete_tuketimleri_recete_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recete_tuketimleri
    ADD CONSTRAINT recete_tuketimleri_recete_id_fkey FOREIGN KEY (recete_id) REFERENCES public.receteler(id) ON DELETE SET NULL;


--
-- Name: satin_alma_talep_kalemleri satin_alma_talep_kalemleri_talep_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.satin_alma_talep_kalemleri
    ADD CONSTRAINT satin_alma_talep_kalemleri_talep_id_fkey FOREIGN KEY (talep_id) REFERENCES public.satin_alma_talepleri(id) ON DELETE CASCADE;


--
-- Name: satin_alma_talep_kalemleri satin_alma_talep_kalemleri_urun_kodu_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.satin_alma_talep_kalemleri
    ADD CONSTRAINT satin_alma_talep_kalemleri_urun_kodu_fkey FOREIGN KEY (urun_kodu) REFERENCES public.urunler(kod);


--
-- Name: satin_alma_talepleri satin_alma_talepleri_siparis_no_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.satin_alma_talepleri
    ADD CONSTRAINT satin_alma_talepleri_siparis_no_fkey FOREIGN KEY (siparis_no) REFERENCES public.siparisler(siparis_no);


--
-- Name: sayim_detaylari sayim_detaylari_oturum_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sayim_detaylari
    ADD CONSTRAINT sayim_detaylari_oturum_id_fkey FOREIGN KEY (oturum_id) REFERENCES public.sayim_oturumlari(id);


--
-- Name: siparis_kalemleri siparis_kalemleri_siparis_no_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.siparis_kalemleri
    ADD CONSTRAINT siparis_kalemleri_siparis_no_fkey FOREIGN KEY (siparis_no) REFERENCES public.siparisler(siparis_no) ON DELETE CASCADE;


--
-- Name: siparisler siparisler_cari_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.siparisler
    ADD CONSTRAINT siparisler_cari_id_fkey FOREIGN KEY (cari_id) REFERENCES public.cariler(id);


--
-- Name: skt_kayitlari skt_kayitlari_mk_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.skt_kayitlari
    ADD CONSTRAINT skt_kayitlari_mk_id_fkey FOREIGN KEY (mk_id) REFERENCES public.mal_kabuller(id) ON DELETE SET NULL;


--
-- Name: skt_kayitlari skt_kayitlari_urun_kodu_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.skt_kayitlari
    ADD CONSTRAINT skt_kayitlari_urun_kodu_fkey FOREIGN KEY (urun_kodu) REFERENCES public.urunler(kod);


--
-- Name: stok_hareketleri stok_hareketleri_urun_kodu_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stok_hareketleri
    ADD CONSTRAINT stok_hareketleri_urun_kodu_fkey FOREIGN KEY (urun_kodu) REFERENCES public.urunler(kod);


--
-- Name: stok_minimumlar stok_minimumlar_urun_kodu_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stok_minimumlar
    ADD CONSTRAINT stok_minimumlar_urun_kodu_fkey FOREIGN KEY (urun_kodu) REFERENCES public.urunler(kod);


--
-- Name: stok_rezervasyonlari stok_rezervasyonlari_siparis_kalem_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stok_rezervasyonlari
    ADD CONSTRAINT stok_rezervasyonlari_siparis_kalem_id_fkey FOREIGN KEY (siparis_kalem_id) REFERENCES public.bar_siparis_kalemleri(id);


--
-- Name: stok stok_urun_kodu_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stok
    ADD CONSTRAINT stok_urun_kodu_fkey FOREIGN KEY (urun_kodu) REFERENCES public.urunler(kod);


--
-- Name: talep_onay_gecmisi talep_onay_gecmisi_talep_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.talep_onay_gecmisi
    ADD CONSTRAINT talep_onay_gecmisi_talep_id_fkey FOREIGN KEY (talep_id) REFERENCES public.satin_alma_talepleri(id);


--
-- Name: tedarikci_urun_eslesme tedarikci_urun_eslesme_cari_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tedarikci_urun_eslesme
    ADD CONSTRAINT tedarikci_urun_eslesme_cari_id_fkey FOREIGN KEY (cari_id) REFERENCES public.cariler(id);


--
-- Name: tedarikci_urun_eslesme tedarikci_urun_eslesme_urun_kodu_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tedarikci_urun_eslesme
    ADD CONSTRAINT tedarikci_urun_eslesme_urun_kodu_fkey FOREIGN KEY (urun_kodu) REFERENCES public.urunler(kod);


--
-- Name: teklif_fiyatlari teklif_fiyatlari_teklif_kalemi_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.teklif_fiyatlari
    ADD CONSTRAINT teklif_fiyatlari_teklif_kalemi_id_fkey FOREIGN KEY (teklif_kalemi_id) REFERENCES public.teklif_kalemleri(id) ON DELETE CASCADE;


--
-- Name: teklif_kalemleri teklif_kalemleri_teklif_talebi_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.teklif_kalemleri
    ADD CONSTRAINT teklif_kalemleri_teklif_talebi_id_fkey FOREIGN KEY (teklif_talebi_id) REFERENCES public.teklif_talepleri(id) ON DELETE CASCADE;


--
-- Name: urun_alt_gruplari urun_alt_gruplari_ana_grup_kod_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.urun_alt_gruplari
    ADD CONSTRAINT urun_alt_gruplari_ana_grup_kod_fkey FOREIGN KEY (ana_grup_kod) REFERENCES public.urun_ana_gruplari(ana_grup_kod);


--
-- Name: urun_birim_donusum urun_birim_donusum_urun_kodu_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.urun_birim_donusum
    ADD CONSTRAINT urun_birim_donusum_urun_kodu_fkey FOREIGN KEY (urun_kodu) REFERENCES public.urunler(kod);


--
-- Name: urun_siniflandirma urun_siniflandirma_alt_grup_kod_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.urun_siniflandirma
    ADD CONSTRAINT urun_siniflandirma_alt_grup_kod_fkey FOREIGN KEY (alt_grup_kod) REFERENCES public.urun_alt_gruplari(alt_grup_kod);


--
-- Name: urun_siniflandirma urun_siniflandirma_urun_kodu_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.urun_siniflandirma
    ADD CONSTRAINT urun_siniflandirma_urun_kodu_fkey FOREIGN KEY (urun_kodu) REFERENCES public.urunler(kod);


--
-- Name: uygunsuzluklar uygunsuzluklar_mk_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.uygunsuzluklar
    ADD CONSTRAINT uygunsuzluklar_mk_id_fkey FOREIGN KEY (mk_id) REFERENCES public.mal_kabuller(id) ON DELETE SET NULL;


--
-- Name: uygunsuzluklar uygunsuzluklar_urun_kodu_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.uygunsuzluklar
    ADD CONSTRAINT uygunsuzluklar_urun_kodu_fkey FOREIGN KEY (urun_kodu) REFERENCES public.urunler(kod);


--
-- Name: virmanlar virmanlar_hedef_hesap_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.virmanlar
    ADD CONSTRAINT virmanlar_hedef_hesap_id_fkey FOREIGN KEY (hedef_hesap_id) REFERENCES public.banka_kasa_hesaplari(id);


--
-- Name: virmanlar virmanlar_kaynak_hesap_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.virmanlar
    ADD CONSTRAINT virmanlar_kaynak_hesap_id_fkey FOREIGN KEY (kaynak_hesap_id) REFERENCES public.banka_kasa_hesaplari(id);


--
-- Name: yetki_matrisi yetki_matrisi_modul_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.yetki_matrisi
    ADD CONSTRAINT yetki_matrisi_modul_id_fkey FOREIGN KEY (modul_id) REFERENCES public.moduller(id) ON DELETE CASCADE;


--
-- Name: yetki_matrisi yetki_matrisi_rol_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.yetki_matrisi
    ADD CONSTRAINT yetki_matrisi_rol_id_fkey FOREIGN KEY (rol_id) REFERENCES public.roller(id) ON DELETE CASCADE;


--
-- Name: yevmiye_kalemleri yevmiye_kalemleri_fis_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.yevmiye_kalemleri
    ADD CONSTRAINT yevmiye_kalemleri_fis_id_fkey FOREIGN KEY (fis_id) REFERENCES public.yevmiye_fisler(id) ON DELETE CASCADE;


--
-- Name: yevmiye_kalemleri yevmiye_kalemleri_hesap_kodu_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.yevmiye_kalemleri
    ADD CONSTRAINT yevmiye_kalemleri_hesap_kodu_fkey FOREIGN KEY (hesap_kodu) REFERENCES public.hesap_plani(kod);


--
-- Name: amortisman_kosustu ak_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ak_insert ON public.amortisman_kosustu FOR INSERT WITH CHECK (public.auth_yetki_var('demirbas_yonetimi'::text, 'kayit'::text));


--
-- Name: amortisman_kosustu ak_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ak_select ON public.amortisman_kosustu FOR SELECT USING (public.auth_yetki_var('demirbas_yonetimi'::text, 'goruntule'::text));


--
-- Name: amortisman_kosustu ak_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ak_update ON public.amortisman_kosustu FOR UPDATE USING (public.auth_yetki_var('demirbas_yonetimi'::text, 'kayit'::text)) WITH CHECK (public.auth_yetki_var('demirbas_yonetimi'::text, 'kayit'::text));


--
-- Name: audit_log al_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY al_insert ON public.audit_log FOR INSERT TO authenticated WITH CHECK (public.auth_erp_kullanicisi());


--
-- Name: audit_log al_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY al_select ON public.audit_log FOR SELECT USING (public.auth_yetki_var('denetim_izi'::text, 'goruntule'::text));


--
-- Name: amortisman_kosustu; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.amortisman_kosustu ENABLE ROW LEVEL SECURITY;

--
-- Name: audit_log; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;

--
-- Name: excel_import_gecmisi authenticated_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_insert ON public.excel_import_gecmisi FOR INSERT TO authenticated WITH CHECK (public.auth_erp_kullanicisi());


--
-- Name: excel_import_satirlari authenticated_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_insert ON public.excel_import_satirlari FOR INSERT TO authenticated WITH CHECK (public.auth_erp_kullanicisi());


--
-- Name: excel_import_gecmisi authenticated_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_select ON public.excel_import_gecmisi FOR SELECT TO authenticated USING (public.auth_erp_kullanicisi());


--
-- Name: excel_import_satirlari authenticated_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_select ON public.excel_import_satirlari FOR SELECT TO authenticated USING (public.auth_erp_kullanicisi());


--
-- Name: excel_import_gecmisi authenticated_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_update ON public.excel_import_gecmisi FOR UPDATE TO authenticated USING (public.auth_erp_kullanicisi()) WITH CHECK (public.auth_erp_kullanicisi());


--
-- Name: excel_import_satirlari authenticated_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_update ON public.excel_import_satirlari FOR UPDATE TO authenticated USING (public.auth_erp_kullanicisi()) WITH CHECK (public.auth_erp_kullanicisi());


--
-- Name: banka_kasa_hareketleri; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.banka_kasa_hareketleri ENABLE ROW LEVEL SECURITY;

--
-- Name: banka_kasa_hesaplari; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.banka_kasa_hesaplari ENABLE ROW LEVEL SECURITY;

--
-- Name: bar_siparis_kalemleri; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.bar_siparis_kalemleri ENABLE ROW LEVEL SECURITY;

--
-- Name: bar_siparisleri; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.bar_siparisleri ENABLE ROW LEVEL SECURITY;

--
-- Name: butce_kayitlari; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.butce_kayitlari ENABLE ROW LEVEL SECURITY;

--
-- Name: cari_hareketler; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.cari_hareketler ENABLE ROW LEVEL SECURITY;

--
-- Name: cariler; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.cariler ENABLE ROW LEVEL SECURITY;

--
-- Name: cek_senetler; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.cek_senetler ENABLE ROW LEVEL SECURITY;

--
-- Name: demirbaslar; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.demirbaslar ENABLE ROW LEVEL SECURITY;

--
-- Name: doviz_kurlari dk_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY dk_insert ON public.doviz_kurlari FOR INSERT WITH CHECK (public.auth_yetki_var('doviz_manuel'::text, 'kayit'::text));


--
-- Name: doviz_kurlari dk_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY dk_select ON public.doviz_kurlari FOR SELECT USING (public.auth_yetki_var('doviz_manuel'::text, 'goruntule'::text));


--
-- Name: doviz_kurlari dk_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY dk_update ON public.doviz_kurlari FOR UPDATE USING (public.auth_yetki_var('doviz_manuel'::text, 'kayit'::text)) WITH CHECK (public.auth_yetki_var('doviz_manuel'::text, 'kayit'::text));


--
-- Name: doviz_kurlari; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.doviz_kurlari ENABLE ROW LEVEL SECURITY;

--
-- Name: edefter_kurum_bilgileri; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.edefter_kurum_bilgileri ENABLE ROW LEVEL SECURITY;

--
-- Name: edefter_sube_bilgileri; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.edefter_sube_bilgileri ENABLE ROW LEVEL SECURITY;

--
-- Name: erp_islem_audit; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.erp_islem_audit ENABLE ROW LEVEL SECURITY;

--
-- Name: excel_import_gecmisi; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.excel_import_gecmisi ENABLE ROW LEVEL SECURITY;

--
-- Name: excel_import_satirlari; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.excel_import_satirlari ENABLE ROW LEVEL SECURITY;

--
-- Name: faturalar fat_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY fat_insert ON public.faturalar FOR INSERT WITH CHECK (((public.auth_yetki_var('fatura_giris'::text, 'kayit'::text) OR public.auth_yetki_var('fiyat_kontrol'::text, 'kayit'::text) OR public.auth_yetki_var('siparis_olustur'::text, 'kayit'::text)) AND public.auth_otel_erisim((otel_id)::text)));


--
-- Name: faturalar fat_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY fat_update ON public.faturalar FOR UPDATE USING (((public.auth_yetki_var('fatura_giris'::text, 'kayit'::text) OR public.auth_yetki_var('fiyat_kontrol'::text, 'kayit'::text) OR public.auth_yetki_var('siparis_olustur'::text, 'kayit'::text)) AND public.auth_otel_erisim((otel_id)::text))) WITH CHECK (((public.auth_yetki_var('fatura_giris'::text, 'kayit'::text) OR public.auth_yetki_var('fiyat_kontrol'::text, 'kayit'::text) OR public.auth_yetki_var('siparis_olustur'::text, 'kayit'::text)) AND public.auth_otel_erisim((otel_id)::text)));


--
-- Name: fatura_kalemleri; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.fatura_kalemleri ENABLE ROW LEVEL SECURITY;

--
-- Name: faturalar; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.faturalar ENABLE ROW LEVEL SECURITY;

--
-- Name: fatura_kalemleri fk_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY fk_delete ON public.fatura_kalemleri FOR DELETE TO authenticated USING (((public.auth_yetki_var('fatura_giris'::text, 'kayit'::text) OR public.auth_yetki_var('fiyat_kontrol'::text, 'kayit'::text) OR public.auth_yetki_var('siparis_olustur'::text, 'kayit'::text)) AND (EXISTS ( SELECT 1
   FROM public.faturalar f
  WHERE ((f.id = fatura_kalemleri.fatura_id) AND public.auth_otel_erisim((f.otel_id)::text))))));


--
-- Name: fatura_kalemleri fk_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY fk_insert ON public.fatura_kalemleri FOR INSERT TO authenticated WITH CHECK (((public.auth_yetki_var('fatura_giris'::text, 'kayit'::text) OR public.auth_yetki_var('fiyat_kontrol'::text, 'kayit'::text) OR public.auth_yetki_var('siparis_olustur'::text, 'kayit'::text)) AND (EXISTS ( SELECT 1
   FROM public.faturalar f
  WHERE ((f.id = fatura_kalemleri.fatura_id) AND public.auth_otel_erisim((f.otel_id)::text))))));


--
-- Name: fatura_kalemleri fk_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY fk_select ON public.fatura_kalemleri FOR SELECT TO authenticated USING ((public.auth_yetki_var('fatura_giris'::text, 'goruntule'::text) AND (EXISTS ( SELECT 1
   FROM public.faturalar f
  WHERE ((f.id = fatura_kalemleri.fatura_id) AND public.auth_otel_erisim((f.otel_id)::text))))));


--
-- Name: fatura_kalemleri fk_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY fk_update ON public.fatura_kalemleri FOR UPDATE TO authenticated USING (((public.auth_yetki_var('fatura_giris'::text, 'kayit'::text) OR public.auth_yetki_var('fiyat_kontrol'::text, 'kayit'::text) OR public.auth_yetki_var('siparis_olustur'::text, 'kayit'::text)) AND (EXISTS ( SELECT 1
   FROM public.faturalar f
  WHERE ((f.id = fatura_kalemleri.fatura_id) AND public.auth_otel_erisim((f.otel_id)::text)))))) WITH CHECK (((public.auth_yetki_var('fatura_giris'::text, 'kayit'::text) OR public.auth_yetki_var('fiyat_kontrol'::text, 'kayit'::text) OR public.auth_yetki_var('siparis_olustur'::text, 'kayit'::text)) AND (EXISTS ( SELECT 1
   FROM public.faturalar f
  WHERE ((f.id = fatura_kalemleri.fatura_id) AND public.auth_otel_erisim((f.otel_id)::text))))));


--
-- Name: gelen_efaturalar gef_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY gef_insert ON public.gelen_efaturalar FOR INSERT TO authenticated WITH CHECK (public.auth_yetki_var('fatura_giris'::text, 'kayit'::text));


--
-- Name: gelen_efaturalar gef_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY gef_select ON public.gelen_efaturalar FOR SELECT TO authenticated USING (public.auth_yetki_var('fatura_giris'::text, 'goruntule'::text));


--
-- Name: gelen_efaturalar gef_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY gef_update ON public.gelen_efaturalar FOR UPDATE TO authenticated USING (public.auth_yetki_var('fatura_giris'::text, 'kayit'::text)) WITH CHECK (public.auth_yetki_var('fatura_giris'::text, 'kayit'::text));


--
-- Name: gelen_efaturalar; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.gelen_efaturalar ENABLE ROW LEVEL SECURITY;

--
-- Name: giris_denemeleri; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.giris_denemeleri ENABLE ROW LEVEL SECURITY;

--
-- Name: giris_kayitlari; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.giris_kayitlari ENABLE ROW LEVEL SECURITY;

--
-- Name: giris_kayitlari gk_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY gk_select ON public.giris_kayitlari FOR SELECT TO authenticated USING (public.auth_yetki_var('kullanici_yonetimi'::text, 'goruntule'::text));


--
-- Name: hesap_plani; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.hesap_plani ENABLE ROW LEVEL SECURITY;

--
-- Name: hesap_plani hp_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY hp_insert ON public.hesap_plani FOR INSERT WITH CHECK ((public.auth_yetki_var('hesap_plani'::text, 'kayit'::text) OR public.auth_yetki_var('fiyat_kontrol'::text, 'kayit'::text)));


--
-- Name: hesap_plani hp_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY hp_select ON public.hesap_plani FOR SELECT USING (public.auth_yetki_var('hesap_plani'::text, 'goruntule'::text));


--
-- Name: hesap_plani hp_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY hp_update ON public.hesap_plani FOR UPDATE USING ((public.auth_yetki_var('hesap_plani'::text, 'kayit'::text) OR public.auth_yetki_var('fiyat_kontrol'::text, 'kayit'::text))) WITH CHECK ((public.auth_yetki_var('hesap_plani'::text, 'kayit'::text) OR public.auth_yetki_var('fiyat_kontrol'::text, 'kayit'::text)));


--
-- Name: ic_talep_kalemleri; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.ic_talep_kalemleri ENABLE ROW LEVEL SECURITY;

--
-- Name: ic_talepler; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.ic_talepler ENABLE ROW LEVEL SECURITY;

--
-- Name: ic_talepler it_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY it_insert ON public.ic_talepler FOR INSERT WITH CHECK ((public.auth_yetki_var('depo_siparis'::text, 'kayit'::text) AND public.auth_otel_erisim(otel_id)));


--
-- Name: ic_talepler it_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY it_select ON public.ic_talepler FOR SELECT USING ((public.auth_yetki_var('depo_siparis'::text, 'goruntule'::text) AND public.auth_otel_erisim(otel_id)));


--
-- Name: ic_talepler it_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY it_update ON public.ic_talepler FOR UPDATE USING ((public.auth_yetki_var('depo_siparis'::text, 'kayit'::text) AND public.auth_otel_erisim(otel_id))) WITH CHECK ((public.auth_yetki_var('depo_siparis'::text, 'kayit'::text) AND public.auth_otel_erisim(otel_id)));


--
-- Name: ic_talep_kalemleri itk_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY itk_insert ON public.ic_talep_kalemleri FOR INSERT TO authenticated WITH CHECK ((public.auth_yetki_var('depo_siparis'::text, 'kayit'::text) AND (EXISTS ( SELECT 1
   FROM public.ic_talepler t
  WHERE ((t.id = ic_talep_kalemleri.talep_id) AND public.auth_otel_erisim(t.otel_id))))));


--
-- Name: ic_talep_kalemleri itk_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY itk_select ON public.ic_talep_kalemleri FOR SELECT TO authenticated USING ((public.auth_yetki_var('depo_siparis'::text, 'goruntule'::text) AND (EXISTS ( SELECT 1
   FROM public.ic_talepler t
  WHERE ((t.id = ic_talep_kalemleri.talep_id) AND public.auth_otel_erisim(t.otel_id))))));


--
-- Name: ic_talep_kalemleri itk_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY itk_update ON public.ic_talep_kalemleri FOR UPDATE TO authenticated USING ((public.auth_yetki_var('depo_siparis'::text, 'kayit'::text) AND (EXISTS ( SELECT 1
   FROM public.ic_talepler t
  WHERE ((t.id = ic_talep_kalemleri.talep_id) AND public.auth_otel_erisim(t.otel_id)))))) WITH CHECK ((public.auth_yetki_var('depo_siparis'::text, 'kayit'::text) AND (EXISTS ( SELECT 1
   FROM public.ic_talepler t
  WHERE ((t.id = ic_talep_kalemleri.talep_id) AND public.auth_otel_erisim(t.otel_id))))));


--
-- Name: bar_siparis_kalemleri kalem_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY kalem_select ON public.bar_siparis_kalemleri FOR SELECT USING ((public.auth_yetki_var('bar_siparis_yonetimi'::text, 'goruntule'::text) AND (EXISTS ( SELECT 1
   FROM public.bar_siparisleri s
  WHERE ((s.id = bar_siparis_kalemleri.siparis_id) AND public.auth_otel_erisim((s.otel_id)::text))))));


--
-- Name: bar_siparis_kalemleri kalem_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY kalem_write ON public.bar_siparis_kalemleri USING ((public.auth_yetki_var('bar_siparis_yonetimi'::text, 'kayit'::text) AND (EXISTS ( SELECT 1
   FROM public.bar_siparisleri s
  WHERE ((s.id = bar_siparis_kalemleri.siparis_id) AND public.auth_otel_erisim((s.otel_id)::text)))))) WITH CHECK ((public.auth_yetki_var('bar_siparis_yonetimi'::text, 'kayit'::text) AND (EXISTS ( SELECT 1
   FROM public.bar_siparisleri s
  WHERE ((s.id = bar_siparis_kalemleri.siparis_id) AND public.auth_otel_erisim((s.otel_id)::text))))));


--
-- Name: kayitli_filtreler; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.kayitli_filtreler ENABLE ROW LEVEL SECURITY;

--
-- Name: koli_etiketleri ke_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ke_insert ON public.koli_etiketleri FOR INSERT TO authenticated WITH CHECK ((public.auth_yetki_var('mal_kabul_form'::text, 'kayit'::text) AND public.auth_otel_erisim(otel_id)));


--
-- Name: koli_etiketleri ke_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ke_select ON public.koli_etiketleri FOR SELECT USING ((public.auth_yetki_var('fiyat_kontrol'::text, 'goruntule'::text) AND public.auth_otel_erisim(otel_id)));


--
-- Name: koli_etiketleri ke_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ke_update ON public.koli_etiketleri FOR UPDATE USING ((public.auth_yetki_var('fiyat_kontrol'::text, 'kayit'::text) AND public.auth_otel_erisim(otel_id))) WITH CHECK ((public.auth_yetki_var('fiyat_kontrol'::text, 'kayit'::text) AND public.auth_otel_erisim(otel_id)));


--
-- Name: kayitli_filtreler kf_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY kf_delete ON public.kayitli_filtreler FOR DELETE TO authenticated USING ((kullanici_id = public.auth_kullanici_id()));


--
-- Name: kayitli_filtreler kf_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY kf_insert ON public.kayitli_filtreler FOR INSERT TO authenticated WITH CHECK (((kullanici_id = public.auth_kullanici_id()) AND ((paylasimli = false) OR public.auth_yetki_var('kullanici_yonetimi'::text, 'kayit'::text))));


--
-- Name: kayitli_filtreler kf_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY kf_select ON public.kayitli_filtreler FOR SELECT TO authenticated USING ((public.auth_erp_kullanicisi() AND ((kullanici_id = public.auth_kullanici_id()) OR (paylasimli = true))));


--
-- Name: kayitli_filtreler kf_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY kf_update ON public.kayitli_filtreler FOR UPDATE TO authenticated USING ((kullanici_id = public.auth_kullanici_id())) WITH CHECK ((kullanici_id = public.auth_kullanici_id()));


--
-- Name: koli_etiketleri; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.koli_etiketleri ENABLE ROW LEVEL SECURITY;

--
-- Name: kullanicilar; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.kullanicilar ENABLE ROW LEVEL SECURITY;

--
-- Name: ln_siparisler ln_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ln_insert ON public.ln_siparisler FOR INSERT WITH CHECK (public.auth_yetki_var('siparis_takip'::text, 'kayit'::text));


--
-- Name: ln_siparisler ln_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ln_select ON public.ln_siparisler FOR SELECT USING (public.auth_yetki_var('siparis_takip'::text, 'goruntule'::text));


--
-- Name: ln_siparisler; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.ln_siparisler ENABLE ROW LEVEL SECURITY;

--
-- Name: ln_siparisler ln_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ln_update ON public.ln_siparisler FOR UPDATE USING (public.auth_yetki_var('siparis_takip'::text, 'kayit'::text)) WITH CHECK (public.auth_yetki_var('siparis_takip'::text, 'kayit'::text));


--
-- Name: mal_kabul_urunleri; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.mal_kabul_urunleri ENABLE ROW LEVEL SECURITY;

--
-- Name: mal_kabuller; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.mal_kabuller ENABLE ROW LEVEL SECURITY;

--
-- Name: mali_donemler; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.mali_donemler ENABLE ROW LEVEL SECURITY;

--
-- Name: mali_donemler md_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY md_insert ON public.mali_donemler FOR INSERT WITH CHECK (public.auth_yetki_var('donem_kilitleme'::text, 'kayit'::text));


--
-- Name: mali_donemler md_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY md_select ON public.mali_donemler FOR SELECT USING (public.auth_yetki_var('donem_kilitleme'::text, 'goruntule'::text));


--
-- Name: mali_donemler md_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY md_update ON public.mali_donemler FOR UPDATE USING (public.auth_yetki_var('donem_kilitleme'::text, 'kayit'::text)) WITH CHECK (public.auth_yetki_var('donem_kilitleme'::text, 'kayit'::text));


--
-- Name: menu_urunler menu_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY menu_select ON public.menu_urunler FOR SELECT USING ((public.auth_yetki_var('bar_siparis_yonetimi'::text, 'goruntule'::text) AND (silindi = false) AND public.auth_otel_erisim((otel_id)::text)));


--
-- Name: menu_urunler; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.menu_urunler ENABLE ROW LEVEL SECURITY;

--
-- Name: menu_urunler menu_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY menu_write ON public.menu_urunler USING ((public.auth_yetki_var('bar_siparis_yonetimi'::text, 'kayit'::text) AND public.auth_otel_erisim((otel_id)::text))) WITH CHECK ((public.auth_yetki_var('bar_siparis_yonetimi'::text, 'kayit'::text) AND public.auth_otel_erisim((otel_id)::text)));


--
-- Name: mal_kabuller mk_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY mk_insert ON public.mal_kabuller FOR INSERT WITH CHECK ((public.auth_yetki_var('mal_kabul_form'::text, 'kayit'::text) AND public.auth_otel_erisim((otel_id)::text)));


--
-- Name: mal_kabuller mk_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY mk_select ON public.mal_kabuller FOR SELECT USING ((public.auth_yetki_var('fiyat_kontrol'::text, 'goruntule'::text) AND public.auth_otel_erisim((otel_id)::text)));


--
-- Name: mal_kabuller mk_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY mk_update ON public.mal_kabuller FOR UPDATE USING ((public.auth_yetki_var('fiyat_kontrol'::text, 'kayit'::text) AND public.auth_otel_erisim((otel_id)::text))) WITH CHECK ((public.auth_yetki_var('fiyat_kontrol'::text, 'kayit'::text) AND public.auth_otel_erisim((otel_id)::text)));


--
-- Name: mal_kabul_urunleri mku_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY mku_insert ON public.mal_kabul_urunleri FOR INSERT WITH CHECK ((public.auth_yetki_var('mal_kabul_form'::text, 'kayit'::text) AND (EXISTS ( SELECT 1
   FROM public.mal_kabuller m
  WHERE ((m.id = mal_kabul_urunleri.mk_id) AND public.auth_otel_erisim((m.otel_id)::text))))));


--
-- Name: mal_kabul_urunleri mku_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY mku_select ON public.mal_kabul_urunleri FOR SELECT USING ((public.auth_yetki_var('fiyat_kontrol'::text, 'goruntule'::text) AND (EXISTS ( SELECT 1
   FROM public.mal_kabuller m
  WHERE ((m.id = mal_kabul_urunleri.mk_id) AND public.auth_otel_erisim((m.otel_id)::text))))));


--
-- Name: mal_kabul_urunleri mku_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY mku_update ON public.mal_kabul_urunleri FOR UPDATE USING ((public.auth_yetki_var('fiyat_kontrol'::text, 'kayit'::text) AND (EXISTS ( SELECT 1
   FROM public.mal_kabuller m
  WHERE ((m.id = mal_kabul_urunleri.mk_id) AND public.auth_otel_erisim((m.otel_id)::text)))))) WITH CHECK ((public.auth_yetki_var('fiyat_kontrol'::text, 'kayit'::text) AND (EXISTS ( SELECT 1
   FROM public.mal_kabuller m
  WHERE ((m.id = mal_kabul_urunleri.mk_id) AND public.auth_otel_erisim((m.otel_id)::text))))));


--
-- Name: moduller mod_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY mod_select ON public.moduller FOR SELECT TO authenticated USING (public.auth_erp_kullanicisi());


--
-- Name: moduller mod_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY mod_write ON public.moduller USING ((public.auth_yetki_var('kullanici_yonetimi'::text, 'kayit'::text) OR public.auth_yetki_var('yetki_yonetimi'::text, 'kayit'::text))) WITH CHECK ((public.auth_yetki_var('kullanici_yonetimi'::text, 'kayit'::text) OR public.auth_yetki_var('yetki_yonetimi'::text, 'kayit'::text)));


--
-- Name: moduller; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.moduller ENABLE ROW LEVEL SECURITY;

--
-- Name: erp_islem_audit phase0_audit_boundary; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY phase0_audit_boundary ON public.erp_islem_audit AS RESTRICTIVE TO authenticated USING (((public.auth_yetki_var('denetim_izi'::text, 'goruntule'::text) IS TRUE) AND (
CASE
    WHEN (hotel_id IS NULL) THEN public.auth_tum_oteller()
    ELSE public.auth_otel_erisim((hotel_id)::text)
END IS TRUE))) WITH CHECK (false);


--
-- Name: erp_islem_audit phase0_audit_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY phase0_audit_select ON public.erp_islem_audit FOR SELECT TO authenticated USING (((public.auth_yetki_var('denetim_izi'::text, 'goruntule'::text) IS TRUE) AND (
CASE
    WHEN (hotel_id IS NULL) THEN public.auth_tum_oteller()
    ELSE public.auth_otel_erisim((hotel_id)::text)
END IS TRUE)));


--
-- Name: audit_log phase0_legacy_audit_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY phase0_legacy_audit_insert ON public.audit_log AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK ((public.auth_erp_kullanicisi() IS TRUE));


--
-- Name: audit_log phase0_legacy_audit_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY phase0_legacy_audit_read ON public.audit_log AS RESTRICTIVE FOR SELECT TO authenticated USING (((public.auth_tum_oteller() IS TRUE) AND (public.auth_yetki_var('denetim_izi'::text, 'goruntule'::text) IS TRUE)));


--
-- Name: banka_kasa_hareketleri phase0_otel_kisit; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY phase0_otel_kisit ON public.banka_kasa_hareketleri AS RESTRICTIVE TO authenticated USING ((
CASE
    WHEN (otel_id IS NULL) THEN public.auth_tum_oteller()
    ELSE public.auth_otel_erisim((otel_id)::text)
END IS TRUE)) WITH CHECK ((
CASE
    WHEN (otel_id IS NULL) THEN public.auth_tum_oteller()
    ELSE public.auth_otel_erisim((otel_id)::text)
END IS TRUE));


--
-- Name: banka_kasa_hesaplari phase0_otel_kisit; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY phase0_otel_kisit ON public.banka_kasa_hesaplari AS RESTRICTIVE TO authenticated USING ((
CASE
    WHEN (otel_id IS NULL) THEN public.auth_tum_oteller()
    ELSE public.auth_otel_erisim((otel_id)::text)
END IS TRUE)) WITH CHECK ((
CASE
    WHEN (otel_id IS NULL) THEN public.auth_tum_oteller()
    ELSE public.auth_otel_erisim((otel_id)::text)
END IS TRUE));


--
-- Name: bar_siparisleri phase0_otel_kisit; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY phase0_otel_kisit ON public.bar_siparisleri AS RESTRICTIVE TO authenticated USING ((
CASE
    WHEN (otel_id IS NULL) THEN public.auth_tum_oteller()
    ELSE public.auth_otel_erisim((otel_id)::text)
END IS TRUE)) WITH CHECK ((
CASE
    WHEN (otel_id IS NULL) THEN public.auth_tum_oteller()
    ELSE public.auth_otel_erisim((otel_id)::text)
END IS TRUE));


--
-- Name: butce_kayitlari phase0_otel_kisit; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY phase0_otel_kisit ON public.butce_kayitlari AS RESTRICTIVE TO authenticated USING ((
CASE
    WHEN (otel_id IS NULL) THEN public.auth_tum_oteller()
    ELSE public.auth_otel_erisim((otel_id)::text)
END IS TRUE)) WITH CHECK ((
CASE
    WHEN (otel_id IS NULL) THEN public.auth_tum_oteller()
    ELSE public.auth_otel_erisim((otel_id)::text)
END IS TRUE));


--
-- Name: cari_hareketler phase0_otel_kisit; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY phase0_otel_kisit ON public.cari_hareketler AS RESTRICTIVE TO authenticated USING ((
CASE
    WHEN (otel_id IS NULL) THEN public.auth_tum_oteller()
    ELSE public.auth_otel_erisim((otel_id)::text)
END IS TRUE)) WITH CHECK ((
CASE
    WHEN (otel_id IS NULL) THEN public.auth_tum_oteller()
    ELSE public.auth_otel_erisim((otel_id)::text)
END IS TRUE));


--
-- Name: cek_senetler phase0_otel_kisit; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY phase0_otel_kisit ON public.cek_senetler AS RESTRICTIVE TO authenticated USING ((
CASE
    WHEN (otel_id IS NULL) THEN public.auth_tum_oteller()
    ELSE public.auth_otel_erisim((otel_id)::text)
END IS TRUE)) WITH CHECK ((
CASE
    WHEN (otel_id IS NULL) THEN public.auth_tum_oteller()
    ELSE public.auth_otel_erisim((otel_id)::text)
END IS TRUE));


--
-- Name: demirbaslar phase0_otel_kisit; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY phase0_otel_kisit ON public.demirbaslar AS RESTRICTIVE TO authenticated USING ((
CASE
    WHEN (otel_id IS NULL) THEN public.auth_tum_oteller()
    ELSE public.auth_otel_erisim((otel_id)::text)
END IS TRUE)) WITH CHECK ((
CASE
    WHEN (otel_id IS NULL) THEN public.auth_tum_oteller()
    ELSE public.auth_otel_erisim((otel_id)::text)
END IS TRUE));


--
-- Name: edefter_sube_bilgileri phase0_otel_kisit; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY phase0_otel_kisit ON public.edefter_sube_bilgileri AS RESTRICTIVE TO authenticated USING ((
CASE
    WHEN (otel_id IS NULL) THEN public.auth_tum_oteller()
    ELSE public.auth_otel_erisim(otel_id)
END IS TRUE)) WITH CHECK ((
CASE
    WHEN (otel_id IS NULL) THEN public.auth_tum_oteller()
    ELSE public.auth_otel_erisim(otel_id)
END IS TRUE));


--
-- Name: faturalar phase0_otel_kisit; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY phase0_otel_kisit ON public.faturalar AS RESTRICTIVE TO authenticated USING ((
CASE
    WHEN (otel_id IS NULL) THEN public.auth_tum_oteller()
    ELSE public.auth_otel_erisim((otel_id)::text)
END IS TRUE)) WITH CHECK ((
CASE
    WHEN (otel_id IS NULL) THEN public.auth_tum_oteller()
    ELSE public.auth_otel_erisim((otel_id)::text)
END IS TRUE));


--
-- Name: giris_kayitlari phase0_otel_kisit; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY phase0_otel_kisit ON public.giris_kayitlari AS RESTRICTIVE TO authenticated USING ((
CASE
    WHEN (otel_id IS NULL) THEN public.auth_tum_oteller()
    ELSE public.auth_otel_erisim((otel_id)::text)
END IS TRUE)) WITH CHECK ((
CASE
    WHEN (otel_id IS NULL) THEN public.auth_tum_oteller()
    ELSE public.auth_otel_erisim((otel_id)::text)
END IS TRUE));


--
-- Name: ic_talepler phase0_otel_kisit; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY phase0_otel_kisit ON public.ic_talepler AS RESTRICTIVE TO authenticated USING ((
CASE
    WHEN (otel_id IS NULL) THEN public.auth_tum_oteller()
    ELSE public.auth_otel_erisim(otel_id)
END IS TRUE)) WITH CHECK ((
CASE
    WHEN (otel_id IS NULL) THEN public.auth_tum_oteller()
    ELSE public.auth_otel_erisim(otel_id)
END IS TRUE));


--
-- Name: koli_etiketleri phase0_otel_kisit; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY phase0_otel_kisit ON public.koli_etiketleri AS RESTRICTIVE TO authenticated USING ((
CASE
    WHEN (otel_id IS NULL) THEN public.auth_tum_oteller()
    ELSE public.auth_otel_erisim(otel_id)
END IS TRUE)) WITH CHECK ((
CASE
    WHEN (otel_id IS NULL) THEN public.auth_tum_oteller()
    ELSE public.auth_otel_erisim(otel_id)
END IS TRUE));


--
-- Name: mal_kabuller phase0_otel_kisit; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY phase0_otel_kisit ON public.mal_kabuller AS RESTRICTIVE TO authenticated USING ((
CASE
    WHEN (otel_id IS NULL) THEN public.auth_tum_oteller()
    ELSE public.auth_otel_erisim((otel_id)::text)
END IS TRUE)) WITH CHECK ((
CASE
    WHEN (otel_id IS NULL) THEN public.auth_tum_oteller()
    ELSE public.auth_otel_erisim((otel_id)::text)
END IS TRUE));


--
-- Name: menu_urunler phase0_otel_kisit; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY phase0_otel_kisit ON public.menu_urunler AS RESTRICTIVE TO authenticated USING ((
CASE
    WHEN (otel_id IS NULL) THEN public.auth_tum_oteller()
    ELSE public.auth_otel_erisim((otel_id)::text)
END IS TRUE)) WITH CHECK ((
CASE
    WHEN (otel_id IS NULL) THEN public.auth_tum_oteller()
    ELSE public.auth_otel_erisim((otel_id)::text)
END IS TRUE));


--
-- Name: recete_tuketimleri phase0_otel_kisit; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY phase0_otel_kisit ON public.recete_tuketimleri AS RESTRICTIVE TO authenticated USING ((
CASE
    WHEN (otel_id IS NULL) THEN public.auth_tum_oteller()
    ELSE public.auth_otel_erisim(otel_id)
END IS TRUE)) WITH CHECK ((
CASE
    WHEN (otel_id IS NULL) THEN public.auth_tum_oteller()
    ELSE public.auth_otel_erisim(otel_id)
END IS TRUE));


--
-- Name: receteler phase0_otel_kisit; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY phase0_otel_kisit ON public.receteler AS RESTRICTIVE TO authenticated USING ((
CASE
    WHEN (otel_id IS NULL) THEN public.auth_tum_oteller()
    ELSE public.auth_otel_erisim(otel_id)
END IS TRUE)) WITH CHECK ((
CASE
    WHEN (otel_id IS NULL) THEN public.auth_tum_oteller()
    ELSE public.auth_otel_erisim(otel_id)
END IS TRUE));


--
-- Name: satin_alma_talepleri phase0_otel_kisit; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY phase0_otel_kisit ON public.satin_alma_talepleri AS RESTRICTIVE TO authenticated USING ((
CASE
    WHEN (otel_id IS NULL) THEN public.auth_tum_oteller()
    ELSE public.auth_otel_erisim((otel_id)::text)
END IS TRUE)) WITH CHECK ((
CASE
    WHEN (otel_id IS NULL) THEN public.auth_tum_oteller()
    ELSE public.auth_otel_erisim((otel_id)::text)
END IS TRUE));


--
-- Name: sayim_oturumlari phase0_otel_kisit; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY phase0_otel_kisit ON public.sayim_oturumlari AS RESTRICTIVE TO authenticated USING ((
CASE
    WHEN (otel_id IS NULL) THEN public.auth_tum_oteller()
    ELSE public.auth_otel_erisim(otel_id)
END IS TRUE)) WITH CHECK ((
CASE
    WHEN (otel_id IS NULL) THEN public.auth_tum_oteller()
    ELSE public.auth_otel_erisim(otel_id)
END IS TRUE));


--
-- Name: siparisler phase0_otel_kisit; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY phase0_otel_kisit ON public.siparisler AS RESTRICTIVE TO authenticated USING ((
CASE
    WHEN (otel_id IS NULL) THEN public.auth_tum_oteller()
    ELSE public.auth_otel_erisim((otel_id)::text)
END IS TRUE)) WITH CHECK ((
CASE
    WHEN (otel_id IS NULL) THEN public.auth_tum_oteller()
    ELSE public.auth_otel_erisim((otel_id)::text)
END IS TRUE));


--
-- Name: skt_kayitlari phase0_otel_kisit; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY phase0_otel_kisit ON public.skt_kayitlari AS RESTRICTIVE TO authenticated USING ((
CASE
    WHEN (otel_id IS NULL) THEN public.auth_tum_oteller()
    ELSE public.auth_otel_erisim((otel_id)::text)
END IS TRUE)) WITH CHECK ((
CASE
    WHEN (otel_id IS NULL) THEN public.auth_tum_oteller()
    ELSE public.auth_otel_erisim((otel_id)::text)
END IS TRUE));


--
-- Name: stok phase0_otel_kisit; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY phase0_otel_kisit ON public.stok AS RESTRICTIVE TO authenticated USING ((
CASE
    WHEN (otel_id IS NULL) THEN public.auth_tum_oteller()
    ELSE public.auth_otel_erisim((otel_id)::text)
END IS TRUE)) WITH CHECK ((
CASE
    WHEN (otel_id IS NULL) THEN public.auth_tum_oteller()
    ELSE public.auth_otel_erisim((otel_id)::text)
END IS TRUE));


--
-- Name: stok_hareketleri phase0_otel_kisit; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY phase0_otel_kisit ON public.stok_hareketleri AS RESTRICTIVE TO authenticated USING ((
CASE
    WHEN (otel_id IS NULL) THEN public.auth_tum_oteller()
    ELSE public.auth_otel_erisim((otel_id)::text)
END IS TRUE)) WITH CHECK ((
CASE
    WHEN (otel_id IS NULL) THEN public.auth_tum_oteller()
    ELSE public.auth_otel_erisim((otel_id)::text)
END IS TRUE));


--
-- Name: stok_minimumlar phase0_otel_kisit; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY phase0_otel_kisit ON public.stok_minimumlar AS RESTRICTIVE TO authenticated USING ((
CASE
    WHEN (otel_id IS NULL) THEN public.auth_tum_oteller()
    ELSE public.auth_otel_erisim((otel_id)::text)
END IS TRUE)) WITH CHECK ((
CASE
    WHEN (otel_id IS NULL) THEN public.auth_tum_oteller()
    ELSE public.auth_otel_erisim((otel_id)::text)
END IS TRUE));


--
-- Name: stok_rezervasyonlari phase0_otel_kisit; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY phase0_otel_kisit ON public.stok_rezervasyonlari AS RESTRICTIVE TO authenticated USING ((
CASE
    WHEN (otel_id IS NULL) THEN public.auth_tum_oteller()
    ELSE public.auth_otel_erisim((otel_id)::text)
END IS TRUE)) WITH CHECK ((
CASE
    WHEN (otel_id IS NULL) THEN public.auth_tum_oteller()
    ELSE public.auth_otel_erisim((otel_id)::text)
END IS TRUE));


--
-- Name: teklif_talepleri phase0_otel_kisit; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY phase0_otel_kisit ON public.teklif_talepleri AS RESTRICTIVE TO authenticated USING ((
CASE
    WHEN (otel_id IS NULL) THEN public.auth_tum_oteller()
    ELSE public.auth_otel_erisim(otel_id)
END IS TRUE)) WITH CHECK ((
CASE
    WHEN (otel_id IS NULL) THEN public.auth_tum_oteller()
    ELSE public.auth_otel_erisim(otel_id)
END IS TRUE));


--
-- Name: uygunsuzluklar phase0_otel_kisit; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY phase0_otel_kisit ON public.uygunsuzluklar AS RESTRICTIVE TO authenticated USING ((
CASE
    WHEN (otel_id IS NULL) THEN public.auth_tum_oteller()
    ELSE public.auth_otel_erisim((otel_id)::text)
END IS TRUE)) WITH CHECK ((
CASE
    WHEN (otel_id IS NULL) THEN public.auth_tum_oteller()
    ELSE public.auth_otel_erisim((otel_id)::text)
END IS TRUE));


--
-- Name: yevmiye_fisler phase0_otel_kisit; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY phase0_otel_kisit ON public.yevmiye_fisler AS RESTRICTIVE TO authenticated USING ((
CASE
    WHEN (otel_id IS NULL) THEN public.auth_tum_oteller()
    ELSE public.auth_otel_erisim((otel_id)::text)
END IS TRUE)) WITH CHECK ((
CASE
    WHEN (otel_id IS NULL) THEN public.auth_tum_oteller()
    ELSE public.auth_otel_erisim((otel_id)::text)
END IS TRUE));


--
-- Name: kullanicilar phase0_users_scope; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY phase0_users_scope ON public.kullanicilar AS RESTRICTIVE TO authenticated USING (((public.auth_erp_kullanicisi() IS TRUE) AND ((public.auth_tum_oteller() IS TRUE) OR (public.auth_otel_erisim((otel_id)::text) IS TRUE)))) WITH CHECK (((public.auth_erp_kullanicisi() IS TRUE) AND ((public.auth_tum_oteller() IS TRUE) OR ((public.auth_otel_erisim((otel_id)::text) IS TRUE) AND (tum_oteller IS FALSE)))));


--
-- Name: receteler r_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY r_insert ON public.receteler FOR INSERT WITH CHECK ((public.auth_yetki_var('gunluk_tuketim'::text, 'kayit'::text) AND public.auth_otel_erisim(otel_id)));


--
-- Name: receteler r_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY r_select ON public.receteler FOR SELECT USING ((public.auth_yetki_var('gunluk_tuketim'::text, 'goruntule'::text) AND public.auth_otel_erisim(otel_id)));


--
-- Name: receteler r_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY r_update ON public.receteler FOR UPDATE USING ((public.auth_yetki_var('gunluk_tuketim'::text, 'kayit'::text) AND public.auth_otel_erisim(otel_id))) WITH CHECK ((public.auth_yetki_var('gunluk_tuketim'::text, 'kayit'::text) AND public.auth_otel_erisim(otel_id)));


--
-- Name: recete_bilesenleri; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.recete_bilesenleri ENABLE ROW LEVEL SECURITY;

--
-- Name: recete_kalemleri; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.recete_kalemleri ENABLE ROW LEVEL SECURITY;

--
-- Name: recete_bilesenleri recete_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY recete_select ON public.recete_bilesenleri FOR SELECT USING ((public.auth_yetki_var('bar_siparis_yonetimi'::text, 'goruntule'::text) AND (EXISTS ( SELECT 1
   FROM public.menu_urunler m
  WHERE ((m.id = recete_bilesenleri.menu_urun_id) AND public.auth_otel_erisim((m.otel_id)::text))))));


--
-- Name: recete_tuketimleri; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.recete_tuketimleri ENABLE ROW LEVEL SECURITY;

--
-- Name: recete_bilesenleri recete_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY recete_write ON public.recete_bilesenleri USING ((public.auth_yetki_var('bar_siparis_yonetimi'::text, 'kayit'::text) AND (EXISTS ( SELECT 1
   FROM public.menu_urunler m
  WHERE ((m.id = recete_bilesenleri.menu_urun_id) AND public.auth_otel_erisim((m.otel_id)::text)))))) WITH CHECK ((public.auth_yetki_var('bar_siparis_yonetimi'::text, 'kayit'::text) AND (EXISTS ( SELECT 1
   FROM public.menu_urunler m
  WHERE ((m.id = recete_bilesenleri.menu_urun_id) AND public.auth_otel_erisim((m.otel_id)::text))))));


--
-- Name: receteler; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.receteler ENABLE ROW LEVEL SECURITY;

--
-- Name: stok_rezervasyonlari rez_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rez_select ON public.stok_rezervasyonlari FOR SELECT TO authenticated USING ((public.auth_yetki_var('bar_siparis_yonetimi'::text, 'goruntule'::text) AND public.auth_otel_erisim((otel_id)::text)));


--
-- Name: stok_rezervasyonlari rez_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rez_write ON public.stok_rezervasyonlari TO authenticated USING ((public.auth_yetki_var('bar_siparis_yonetimi'::text, 'kayit'::text) AND public.auth_otel_erisim((otel_id)::text))) WITH CHECK ((public.auth_yetki_var('bar_siparis_yonetimi'::text, 'kayit'::text) AND public.auth_otel_erisim((otel_id)::text)));


--
-- Name: recete_kalemleri rk_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rk_delete ON public.recete_kalemleri FOR DELETE TO authenticated USING ((public.auth_yetki_var('gunluk_tuketim'::text, 'kayit'::text) AND (EXISTS ( SELECT 1
   FROM public.receteler r
  WHERE ((r.id = recete_kalemleri.recete_id) AND public.auth_otel_erisim(r.otel_id))))));


--
-- Name: recete_kalemleri rk_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rk_insert ON public.recete_kalemleri FOR INSERT TO authenticated WITH CHECK ((public.auth_yetki_var('gunluk_tuketim'::text, 'kayit'::text) AND (EXISTS ( SELECT 1
   FROM public.receteler r
  WHERE ((r.id = recete_kalemleri.recete_id) AND public.auth_otel_erisim(r.otel_id))))));


--
-- Name: recete_kalemleri rk_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rk_select ON public.recete_kalemleri FOR SELECT TO authenticated USING ((public.auth_yetki_var('gunluk_tuketim'::text, 'goruntule'::text) AND (EXISTS ( SELECT 1
   FROM public.receteler r
  WHERE ((r.id = recete_kalemleri.recete_id) AND public.auth_otel_erisim(r.otel_id))))));


--
-- Name: roller rol_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rol_select ON public.roller FOR SELECT TO authenticated USING (public.auth_erp_kullanicisi());


--
-- Name: roller rol_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rol_write ON public.roller USING ((public.auth_yetki_var('kullanici_yonetimi'::text, 'kayit'::text) OR public.auth_yetki_var('yetki_yonetimi'::text, 'kayit'::text))) WITH CHECK ((public.auth_yetki_var('kullanici_yonetimi'::text, 'kayit'::text) OR public.auth_yetki_var('yetki_yonetimi'::text, 'kayit'::text)));


--
-- Name: roller; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.roller ENABLE ROW LEVEL SECURITY;

--
-- Name: recete_tuketimleri rt_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rt_insert ON public.recete_tuketimleri FOR INSERT WITH CHECK ((public.auth_yetki_var('gunluk_tuketim'::text, 'kayit'::text) AND public.auth_otel_erisim(otel_id)));


--
-- Name: recete_tuketimleri rt_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rt_select ON public.recete_tuketimleri FOR SELECT USING ((public.auth_yetki_var('gunluk_tuketim'::text, 'goruntule'::text) AND public.auth_otel_erisim(otel_id)));


--
-- Name: satin_alma_talepleri sat_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sat_insert ON public.satin_alma_talepleri FOR INSERT WITH CHECK ((public.auth_yetki_var('ic_talep'::text, 'kayit'::text) AND public.auth_otel_erisim((otel_id)::text)));


--
-- Name: satin_alma_talepleri sat_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sat_select ON public.satin_alma_talepleri FOR SELECT USING ((public.auth_yetki_var('ic_talep'::text, 'goruntule'::text) AND public.auth_otel_erisim((otel_id)::text)));


--
-- Name: satin_alma_talepleri sat_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sat_update ON public.satin_alma_talepleri FOR UPDATE USING ((public.auth_yetki_var('ic_talep'::text, 'kayit'::text) AND public.auth_otel_erisim((otel_id)::text))) WITH CHECK ((public.auth_yetki_var('ic_talep'::text, 'kayit'::text) AND public.auth_otel_erisim((otel_id)::text)));


--
-- Name: satin_alma_talep_kalemleri; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.satin_alma_talep_kalemleri ENABLE ROW LEVEL SECURITY;

--
-- Name: satin_alma_talepleri; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.satin_alma_talepleri ENABLE ROW LEVEL SECURITY;

--
-- Name: satin_alma_talep_kalemleri satk_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY satk_insert ON public.satin_alma_talep_kalemleri FOR INSERT TO authenticated WITH CHECK ((public.auth_yetki_var('ic_talep'::text, 'kayit'::text) AND (EXISTS ( SELECT 1
   FROM public.satin_alma_talepleri t
  WHERE ((t.id = satin_alma_talep_kalemleri.talep_id) AND public.auth_otel_erisim((t.otel_id)::text))))));


--
-- Name: satin_alma_talep_kalemleri satk_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY satk_select ON public.satin_alma_talep_kalemleri FOR SELECT TO authenticated USING ((public.auth_yetki_var('ic_talep'::text, 'goruntule'::text) AND (EXISTS ( SELECT 1
   FROM public.satin_alma_talepleri t
  WHERE ((t.id = satin_alma_talep_kalemleri.talep_id) AND public.auth_otel_erisim((t.otel_id)::text))))));


--
-- Name: satin_alma_talep_kalemleri satk_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY satk_update ON public.satin_alma_talep_kalemleri FOR UPDATE TO authenticated USING ((public.auth_yetki_var('ic_talep'::text, 'kayit'::text) AND (EXISTS ( SELECT 1
   FROM public.satin_alma_talepleri t
  WHERE ((t.id = satin_alma_talep_kalemleri.talep_id) AND public.auth_otel_erisim((t.otel_id)::text)))))) WITH CHECK ((public.auth_yetki_var('ic_talep'::text, 'kayit'::text) AND (EXISTS ( SELECT 1
   FROM public.satin_alma_talepleri t
  WHERE ((t.id = satin_alma_talep_kalemleri.talep_id) AND public.auth_otel_erisim((t.otel_id)::text))))));


--
-- Name: sayim_detaylari; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.sayim_detaylari ENABLE ROW LEVEL SECURITY;

--
-- Name: sayim_oturumlari; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.sayim_oturumlari ENABLE ROW LEVEL SECURITY;

--
-- Name: sene_sonu_kapanislar; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.sene_sonu_kapanislar ENABLE ROW LEVEL SECURITY;

--
-- Name: siparisler sip_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sip_insert ON public.siparisler FOR INSERT WITH CHECK ((public.auth_yetki_var('siparis_olustur'::text, 'kayit'::text) AND public.auth_otel_erisim((otel_id)::text)));


--
-- Name: siparisler sip_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sip_select ON public.siparisler FOR SELECT USING (((public.auth_yetki_var('siparis_olustur'::text, 'goruntule'::text) OR public.auth_yetki_var('siparis_takip'::text, 'goruntule'::text)) AND public.auth_otel_erisim((otel_id)::text)));


--
-- Name: siparisler sip_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sip_update ON public.siparisler FOR UPDATE USING ((public.auth_yetki_var('siparis_olustur'::text, 'kayit'::text) AND public.auth_otel_erisim((otel_id)::text))) WITH CHECK ((public.auth_yetki_var('siparis_olustur'::text, 'kayit'::text) AND public.auth_otel_erisim((otel_id)::text)));


--
-- Name: siparis_kalemleri; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.siparis_kalemleri ENABLE ROW LEVEL SECURITY;

--
-- Name: bar_siparisleri siparis_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY siparis_select ON public.bar_siparisleri FOR SELECT USING ((public.auth_yetki_var('bar_siparis_yonetimi'::text, 'goruntule'::text) AND public.auth_otel_erisim((otel_id)::text)));


--
-- Name: bar_siparisleri siparis_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY siparis_write ON public.bar_siparisleri USING ((public.auth_yetki_var('bar_siparis_yonetimi'::text, 'kayit'::text) AND public.auth_otel_erisim((otel_id)::text))) WITH CHECK ((public.auth_yetki_var('bar_siparis_yonetimi'::text, 'kayit'::text) AND public.auth_otel_erisim((otel_id)::text)));


--
-- Name: siparisler; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.siparisler ENABLE ROW LEVEL SECURITY;

--
-- Name: siparis_kalemleri sipk_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sipk_insert ON public.siparis_kalemleri FOR INSERT TO authenticated WITH CHECK ((public.auth_yetki_var('siparis_olustur'::text, 'kayit'::text) AND (EXISTS ( SELECT 1
   FROM public.siparisler s
  WHERE ((s.siparis_no = siparis_kalemleri.siparis_no) AND public.auth_otel_erisim((s.otel_id)::text))))));


--
-- Name: siparis_kalemleri sipk_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sipk_select ON public.siparis_kalemleri FOR SELECT TO authenticated USING (((public.auth_yetki_var('siparis_olustur'::text, 'goruntule'::text) OR public.auth_yetki_var('siparis_takip'::text, 'goruntule'::text)) AND (EXISTS ( SELECT 1
   FROM public.siparisler s
  WHERE ((s.siparis_no = siparis_kalemleri.siparis_no) AND public.auth_otel_erisim((s.otel_id)::text))))));


--
-- Name: siparis_kalemleri sipk_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sipk_update ON public.siparis_kalemleri FOR UPDATE TO authenticated USING ((public.auth_yetki_var('siparis_olustur'::text, 'kayit'::text) AND (EXISTS ( SELECT 1
   FROM public.siparisler s
  WHERE ((s.siparis_no = siparis_kalemleri.siparis_no) AND public.auth_otel_erisim((s.otel_id)::text)))))) WITH CHECK ((public.auth_yetki_var('siparis_olustur'::text, 'kayit'::text) AND (EXISTS ( SELECT 1
   FROM public.siparisler s
  WHERE ((s.siparis_no = siparis_kalemleri.siparis_no) AND public.auth_otel_erisim((s.otel_id)::text))))));


--
-- Name: skt_kayitlari skt_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY skt_insert ON public.skt_kayitlari FOR INSERT WITH CHECK ((public.auth_yetki_var('mal_kabul_kalite'::text, 'kayit'::text) AND public.auth_otel_erisim((otel_id)::text)));


--
-- Name: skt_kayitlari; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.skt_kayitlari ENABLE ROW LEVEL SECURITY;

--
-- Name: skt_kayitlari skt_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY skt_select ON public.skt_kayitlari FOR SELECT USING ((public.auth_yetki_var('mal_kabul_kalite'::text, 'goruntule'::text) AND public.auth_otel_erisim((otel_id)::text)));


--
-- Name: skt_kayitlari skt_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY skt_update ON public.skt_kayitlari FOR UPDATE USING ((public.auth_yetki_var('mal_kabul_kalite'::text, 'kayit'::text) AND public.auth_otel_erisim((otel_id)::text))) WITH CHECK ((public.auth_yetki_var('mal_kabul_kalite'::text, 'kayit'::text) AND public.auth_otel_erisim((otel_id)::text)));


--
-- Name: stok_minimumlar sm_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sm_insert ON public.stok_minimumlar FOR INSERT WITH CHECK ((public.auth_yetki_var('stok_takip'::text, 'kayit'::text) AND public.auth_otel_erisim((otel_id)::text)));


--
-- Name: stok_minimumlar sm_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sm_select ON public.stok_minimumlar FOR SELECT USING ((public.auth_yetki_var('stok_takip'::text, 'goruntule'::text) AND public.auth_otel_erisim((otel_id)::text)));


--
-- Name: stok_minimumlar sm_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sm_update ON public.stok_minimumlar FOR UPDATE USING ((public.auth_yetki_var('stok_takip'::text, 'kayit'::text) AND public.auth_otel_erisim((otel_id)::text))) WITH CHECK ((public.auth_yetki_var('stok_takip'::text, 'kayit'::text) AND public.auth_otel_erisim((otel_id)::text)));


--
-- Name: sene_sonu_kapanislar ssk_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ssk_insert ON public.sene_sonu_kapanislar FOR INSERT WITH CHECK (public.auth_yetki_var('sene_sonu_kapama'::text, 'kayit'::text));


--
-- Name: sene_sonu_kapanislar ssk_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ssk_select ON public.sene_sonu_kapanislar FOR SELECT USING (public.auth_yetki_var('sene_sonu_kapama'::text, 'goruntule'::text));


--
-- Name: stok; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.stok ENABLE ROW LEVEL SECURITY;

--
-- Name: stok_hareketleri; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.stok_hareketleri ENABLE ROW LEVEL SECURITY;

--
-- Name: stok_minimumlar; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.stok_minimumlar ENABLE ROW LEVEL SECURITY;

--
-- Name: stok_rezervasyonlari; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.stok_rezervasyonlari ENABLE ROW LEVEL SECURITY;

--
-- Name: talep_onay_gecmisi; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.talep_onay_gecmisi ENABLE ROW LEVEL SECURITY;

--
-- Name: tedarikci_urun_eslesme; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.tedarikci_urun_eslesme ENABLE ROW LEVEL SECURITY;

--
-- Name: teklif_fiyatlari; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.teklif_fiyatlari ENABLE ROW LEVEL SECURITY;

--
-- Name: teklif_kalemleri; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.teklif_kalemleri ENABLE ROW LEVEL SECURITY;

--
-- Name: teklif_talepleri; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.teklif_talepleri ENABLE ROW LEVEL SECURITY;

--
-- Name: teklif_fiyatlari tf_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tf_insert ON public.teklif_fiyatlari FOR INSERT WITH CHECK ((public.auth_yetki_var('siparis_olustur'::text, 'kayit'::text) AND (EXISTS ( SELECT 1
   FROM (public.teklif_kalemleri k
     JOIN public.teklif_talepleri t ON ((t.id = k.teklif_talebi_id)))
  WHERE ((k.id = teklif_fiyatlari.teklif_kalemi_id) AND public.auth_otel_erisim(t.otel_id))))));


--
-- Name: teklif_fiyatlari tf_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tf_select ON public.teklif_fiyatlari FOR SELECT USING ((public.auth_yetki_var('siparis_olustur'::text, 'goruntule'::text) AND (EXISTS ( SELECT 1
   FROM (public.teklif_kalemleri k
     JOIN public.teklif_talepleri t ON ((t.id = k.teklif_talebi_id)))
  WHERE ((k.id = teklif_fiyatlari.teklif_kalemi_id) AND public.auth_otel_erisim(t.otel_id))))));


--
-- Name: teklif_fiyatlari tf_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tf_update ON public.teklif_fiyatlari FOR UPDATE USING ((public.auth_yetki_var('siparis_olustur'::text, 'kayit'::text) AND (EXISTS ( SELECT 1
   FROM (public.teklif_kalemleri k
     JOIN public.teklif_talepleri t ON ((t.id = k.teklif_talebi_id)))
  WHERE ((k.id = teklif_fiyatlari.teklif_kalemi_id) AND public.auth_otel_erisim(t.otel_id)))))) WITH CHECK ((public.auth_yetki_var('siparis_olustur'::text, 'kayit'::text) AND (EXISTS ( SELECT 1
   FROM (public.teklif_kalemleri k
     JOIN public.teklif_talepleri t ON ((t.id = k.teklif_talebi_id)))
  WHERE ((k.id = teklif_fiyatlari.teklif_kalemi_id) AND public.auth_otel_erisim(t.otel_id))))));


--
-- Name: teklif_kalemleri tk_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tk_insert ON public.teklif_kalemleri FOR INSERT WITH CHECK ((public.auth_yetki_var('siparis_olustur'::text, 'kayit'::text) AND (EXISTS ( SELECT 1
   FROM public.teklif_talepleri t
  WHERE ((t.id = teklif_kalemleri.teklif_talebi_id) AND public.auth_otel_erisim(t.otel_id))))));


--
-- Name: teklif_kalemleri tk_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tk_select ON public.teklif_kalemleri FOR SELECT USING ((public.auth_yetki_var('siparis_olustur'::text, 'goruntule'::text) AND (EXISTS ( SELECT 1
   FROM public.teklif_talepleri t
  WHERE ((t.id = teklif_kalemleri.teklif_talebi_id) AND public.auth_otel_erisim(t.otel_id))))));


--
-- Name: teklif_kalemleri tk_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tk_update ON public.teklif_kalemleri FOR UPDATE USING ((public.auth_yetki_var('siparis_olustur'::text, 'kayit'::text) AND (EXISTS ( SELECT 1
   FROM public.teklif_talepleri t
  WHERE ((t.id = teklif_kalemleri.teklif_talebi_id) AND public.auth_otel_erisim(t.otel_id)))))) WITH CHECK ((public.auth_yetki_var('siparis_olustur'::text, 'kayit'::text) AND (EXISTS ( SELECT 1
   FROM public.teklif_talepleri t
  WHERE ((t.id = teklif_kalemleri.teklif_talebi_id) AND public.auth_otel_erisim(t.otel_id))))));


--
-- Name: talep_onay_gecmisi toh_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY toh_insert ON public.talep_onay_gecmisi FOR INSERT WITH CHECK (public.auth_yetki_var('ic_talep'::text, 'kayit'::text));


--
-- Name: talep_onay_gecmisi toh_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY toh_select ON public.talep_onay_gecmisi FOR SELECT USING (public.auth_yetki_var('ic_talep'::text, 'goruntule'::text));


--
-- Name: teklif_talepleri tt_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tt_insert ON public.teklif_talepleri FOR INSERT WITH CHECK ((public.auth_yetki_var('siparis_olustur'::text, 'kayit'::text) AND public.auth_otel_erisim(otel_id)));


--
-- Name: teklif_talepleri tt_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tt_select ON public.teklif_talepleri FOR SELECT USING ((public.auth_yetki_var('siparis_olustur'::text, 'goruntule'::text) AND public.auth_otel_erisim(otel_id)));


--
-- Name: teklif_talepleri tt_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tt_update ON public.teklif_talepleri FOR UPDATE USING ((public.auth_yetki_var('siparis_olustur'::text, 'kayit'::text) AND public.auth_otel_erisim(otel_id))) WITH CHECK ((public.auth_yetki_var('siparis_olustur'::text, 'kayit'::text) AND public.auth_otel_erisim(otel_id)));


--
-- Name: tedarikci_urun_eslesme tue_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tue_select ON public.tedarikci_urun_eslesme FOR SELECT USING (public.auth_yetki_var('fiyat_kontrol'::text, 'goruntule'::text));


--
-- Name: urun_birim_donusum ubd_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ubd_insert ON public.urun_birim_donusum FOR INSERT TO authenticated WITH CHECK (public.auth_yetki_var('urun_yonetimi'::text, 'kayit'::text));


--
-- Name: urun_birim_donusum ubd_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ubd_select ON public.urun_birim_donusum FOR SELECT TO authenticated USING (public.auth_erp_kullanicisi());


--
-- Name: urun_birim_donusum ubd_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ubd_update ON public.urun_birim_donusum FOR UPDATE TO authenticated USING (public.auth_yetki_var('urun_yonetimi'::text, 'kayit'::text)) WITH CHECK (public.auth_yetki_var('urun_yonetimi'::text, 'kayit'::text));


--
-- Name: urunler urn_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY urn_insert ON public.urunler FOR INSERT WITH CHECK (public.auth_yetki_var('urun_yonetimi'::text, 'kayit'::text));


--
-- Name: urunler urn_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY urn_select ON public.urunler FOR SELECT TO authenticated USING (public.auth_erp_kullanicisi());


--
-- Name: urunler urn_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY urn_update ON public.urunler FOR UPDATE USING (public.auth_yetki_var('urun_yonetimi'::text, 'kayit'::text)) WITH CHECK (public.auth_yetki_var('urun_yonetimi'::text, 'kayit'::text));


--
-- Name: urun_alt_gruplari; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.urun_alt_gruplari ENABLE ROW LEVEL SECURITY;

--
-- Name: urun_alt_gruplari urun_alt_gruplari_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY urun_alt_gruplari_select ON public.urun_alt_gruplari FOR SELECT USING ((public.auth_yetki_var('urun_yonetimi'::text, 'goruntule'::text) AND (silindi = false)));


--
-- Name: urun_alt_gruplari urun_alt_gruplari_yaz; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY urun_alt_gruplari_yaz ON public.urun_alt_gruplari USING (public.auth_yetki_var('urun_yonetimi'::text, 'kayit'::text)) WITH CHECK (public.auth_yetki_var('urun_yonetimi'::text, 'kayit'::text));


--
-- Name: urun_ana_gruplari; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.urun_ana_gruplari ENABLE ROW LEVEL SECURITY;

--
-- Name: urun_ana_gruplari urun_ana_gruplari_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY urun_ana_gruplari_select ON public.urun_ana_gruplari FOR SELECT USING ((public.auth_yetki_var('urun_yonetimi'::text, 'goruntule'::text) AND (silindi = false)));


--
-- Name: urun_ana_gruplari urun_ana_gruplari_yaz; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY urun_ana_gruplari_yaz ON public.urun_ana_gruplari USING (public.auth_yetki_var('urun_yonetimi'::text, 'kayit'::text)) WITH CHECK (public.auth_yetki_var('urun_yonetimi'::text, 'kayit'::text));


--
-- Name: urun_birim_donusum; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.urun_birim_donusum ENABLE ROW LEVEL SECURITY;

--
-- Name: urun_siniflandirma; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.urun_siniflandirma ENABLE ROW LEVEL SECURITY;

--
-- Name: urun_siniflandirma urun_siniflandirma_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY urun_siniflandirma_select ON public.urun_siniflandirma FOR SELECT USING ((public.auth_yetki_var('urun_yonetimi'::text, 'goruntule'::text) AND (silindi = false)));


--
-- Name: urun_siniflandirma urun_siniflandirma_yaz; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY urun_siniflandirma_yaz ON public.urun_siniflandirma USING (public.auth_yetki_var('urun_yonetimi'::text, 'kayit'::text)) WITH CHECK (public.auth_yetki_var('urun_yonetimi'::text, 'kayit'::text));


--
-- Name: urunler; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.urunler ENABLE ROW LEVEL SECURITY;

--
-- Name: uygunsuzluklar uy_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY uy_select ON public.uygunsuzluklar FOR SELECT USING ((public.auth_yetki_var('fiyat_kontrol'::text, 'goruntule'::text) AND public.auth_otel_erisim((otel_id)::text)));


--
-- Name: uygunsuzluklar; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.uygunsuzluklar ENABLE ROW LEVEL SECURITY;

--
-- Name: virmanlar vir_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY vir_insert ON public.virmanlar FOR INSERT WITH CHECK (public.auth_yetki_var('banka_kasa'::text, 'kayit'::text));


--
-- Name: virmanlar vir_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY vir_select ON public.virmanlar FOR SELECT USING (public.auth_yetki_var('banka_kasa'::text, 'goruntule'::text));


--
-- Name: virmanlar; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.virmanlar ENABLE ROW LEVEL SECURITY;

--
-- Name: banka_kasa_hareketleri yetki_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yetki_insert ON public.banka_kasa_hareketleri FOR INSERT WITH CHECK ((public.auth_yetki_var('banka_kasa'::text, 'kayit'::text) AND public.auth_otel_erisim((otel_id)::text)));


--
-- Name: banka_kasa_hesaplari yetki_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yetki_insert ON public.banka_kasa_hesaplari FOR INSERT WITH CHECK ((public.auth_yetki_var('banka_kasa'::text, 'kayit'::text) AND public.auth_otel_erisim((otel_id)::text)));


--
-- Name: butce_kayitlari yetki_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yetki_insert ON public.butce_kayitlari FOR INSERT WITH CHECK ((public.auth_yetki_var('butce_yonetimi'::text, 'kayit'::text) AND public.auth_otel_erisim((otel_id)::text)));


--
-- Name: cari_hareketler yetki_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yetki_insert ON public.cari_hareketler FOR INSERT WITH CHECK ((public.auth_yetki_var('cari_hesaplar'::text, 'kayit'::text) AND public.auth_otel_erisim((otel_id)::text)));


--
-- Name: cariler yetki_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yetki_insert ON public.cariler FOR INSERT WITH CHECK (public.auth_yetki_var('cari_hesaplar'::text, 'kayit'::text));


--
-- Name: cek_senetler yetki_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yetki_insert ON public.cek_senetler FOR INSERT WITH CHECK ((public.auth_yetki_var('cek_senet_yonetimi'::text, 'kayit'::text) AND public.auth_otel_erisim((otel_id)::text)));


--
-- Name: demirbaslar yetki_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yetki_insert ON public.demirbaslar FOR INSERT WITH CHECK ((public.auth_yetki_var('demirbas_yonetimi'::text, 'kayit'::text) AND public.auth_otel_erisim((otel_id)::text)));


--
-- Name: kullanicilar yetki_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yetki_insert ON public.kullanicilar FOR INSERT WITH CHECK (public.auth_yetki_var('kullanici_yonetimi'::text, 'kayit'::text));


--
-- Name: stok yetki_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yetki_insert ON public.stok FOR INSERT WITH CHECK ((public.auth_yetki_var('stok_takip'::text, 'kayit'::text) AND public.auth_otel_erisim((otel_id)::text)));


--
-- Name: stok_hareketleri yetki_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yetki_insert ON public.stok_hareketleri FOR INSERT WITH CHECK ((public.auth_yetki_var('stok_takip'::text, 'kayit'::text) AND public.auth_otel_erisim((otel_id)::text)));


--
-- Name: yetki_matrisi; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.yetki_matrisi ENABLE ROW LEVEL SECURITY;

--
-- Name: banka_kasa_hareketleri yetki_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yetki_select ON public.banka_kasa_hareketleri FOR SELECT USING ((public.auth_yetki_var('banka_kasa'::text, 'goruntule'::text) AND public.auth_otel_erisim((otel_id)::text)));


--
-- Name: banka_kasa_hesaplari yetki_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yetki_select ON public.banka_kasa_hesaplari FOR SELECT USING ((public.auth_yetki_var('banka_kasa'::text, 'goruntule'::text) AND public.auth_otel_erisim((otel_id)::text)));


--
-- Name: butce_kayitlari yetki_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yetki_select ON public.butce_kayitlari FOR SELECT USING ((public.auth_yetki_var('butce_yonetimi'::text, 'goruntule'::text) AND public.auth_otel_erisim((otel_id)::text)));


--
-- Name: cari_hareketler yetki_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yetki_select ON public.cari_hareketler FOR SELECT USING ((public.auth_yetki_var('cari_hesaplar'::text, 'goruntule'::text) AND public.auth_otel_erisim((otel_id)::text)));


--
-- Name: cariler yetki_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yetki_select ON public.cariler FOR SELECT USING (public.auth_yetki_var('cari_hesaplar'::text, 'goruntule'::text));


--
-- Name: cek_senetler yetki_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yetki_select ON public.cek_senetler FOR SELECT USING ((public.auth_yetki_var('cek_senet_yonetimi'::text, 'goruntule'::text) AND public.auth_otel_erisim((otel_id)::text)));


--
-- Name: demirbaslar yetki_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yetki_select ON public.demirbaslar FOR SELECT USING ((public.auth_yetki_var('demirbas_yonetimi'::text, 'goruntule'::text) AND public.auth_otel_erisim((otel_id)::text)));


--
-- Name: faturalar yetki_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yetki_select ON public.faturalar FOR SELECT USING ((public.auth_yetki_var('fatura_giris'::text, 'goruntule'::text) AND public.auth_otel_erisim((otel_id)::text)));


--
-- Name: kullanicilar yetki_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yetki_select ON public.kullanicilar FOR SELECT USING (public.auth_yetki_var('kullanici_yonetimi'::text, 'goruntule'::text));


--
-- Name: stok yetki_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yetki_select ON public.stok FOR SELECT USING ((public.auth_yetki_var('stok_takip'::text, 'goruntule'::text) AND public.auth_otel_erisim((otel_id)::text)));


--
-- Name: stok_hareketleri yetki_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yetki_select ON public.stok_hareketleri FOR SELECT USING ((public.auth_yetki_var('stok_takip'::text, 'goruntule'::text) AND public.auth_otel_erisim((otel_id)::text)));


--
-- Name: banka_kasa_hareketleri yetki_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yetki_update ON public.banka_kasa_hareketleri FOR UPDATE USING ((public.auth_yetki_var('banka_kasa'::text, 'kayit'::text) AND public.auth_otel_erisim((otel_id)::text))) WITH CHECK ((public.auth_yetki_var('banka_kasa'::text, 'kayit'::text) AND public.auth_otel_erisim((otel_id)::text)));


--
-- Name: banka_kasa_hesaplari yetki_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yetki_update ON public.banka_kasa_hesaplari FOR UPDATE USING ((public.auth_yetki_var('banka_kasa'::text, 'kayit'::text) AND public.auth_otel_erisim((otel_id)::text))) WITH CHECK ((public.auth_yetki_var('banka_kasa'::text, 'kayit'::text) AND public.auth_otel_erisim((otel_id)::text)));


--
-- Name: butce_kayitlari yetki_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yetki_update ON public.butce_kayitlari FOR UPDATE USING ((public.auth_yetki_var('butce_yonetimi'::text, 'kayit'::text) AND public.auth_otel_erisim((otel_id)::text))) WITH CHECK ((public.auth_yetki_var('butce_yonetimi'::text, 'kayit'::text) AND public.auth_otel_erisim((otel_id)::text)));


--
-- Name: cari_hareketler yetki_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yetki_update ON public.cari_hareketler FOR UPDATE USING ((public.auth_yetki_var('cari_hesaplar'::text, 'kayit'::text) AND public.auth_otel_erisim((otel_id)::text))) WITH CHECK ((public.auth_yetki_var('cari_hesaplar'::text, 'kayit'::text) AND public.auth_otel_erisim((otel_id)::text)));


--
-- Name: cariler yetki_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yetki_update ON public.cariler FOR UPDATE USING (public.auth_yetki_var('cari_hesaplar'::text, 'kayit'::text)) WITH CHECK (public.auth_yetki_var('cari_hesaplar'::text, 'kayit'::text));


--
-- Name: cek_senetler yetki_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yetki_update ON public.cek_senetler FOR UPDATE USING ((public.auth_yetki_var('cek_senet_yonetimi'::text, 'kayit'::text) AND public.auth_otel_erisim((otel_id)::text))) WITH CHECK ((public.auth_yetki_var('cek_senet_yonetimi'::text, 'kayit'::text) AND public.auth_otel_erisim((otel_id)::text)));


--
-- Name: demirbaslar yetki_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yetki_update ON public.demirbaslar FOR UPDATE USING ((public.auth_yetki_var('demirbas_yonetimi'::text, 'kayit'::text) AND public.auth_otel_erisim((otel_id)::text))) WITH CHECK ((public.auth_yetki_var('demirbas_yonetimi'::text, 'kayit'::text) AND public.auth_otel_erisim((otel_id)::text)));


--
-- Name: kullanicilar yetki_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yetki_update ON public.kullanicilar FOR UPDATE USING (public.auth_yetki_var('kullanici_yonetimi'::text, 'kayit'::text)) WITH CHECK (public.auth_yetki_var('kullanici_yonetimi'::text, 'kayit'::text));


--
-- Name: stok yetki_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yetki_update ON public.stok FOR UPDATE USING ((public.auth_yetki_var('stok_takip'::text, 'kayit'::text) AND public.auth_otel_erisim((otel_id)::text))) WITH CHECK ((public.auth_yetki_var('stok_takip'::text, 'kayit'::text) AND public.auth_otel_erisim((otel_id)::text)));


--
-- Name: stok_hareketleri yetki_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yetki_update ON public.stok_hareketleri FOR UPDATE USING ((public.auth_yetki_var('stok_takip'::text, 'kayit'::text) AND public.auth_otel_erisim((otel_id)::text))) WITH CHECK ((public.auth_yetki_var('stok_takip'::text, 'kayit'::text) AND public.auth_otel_erisim((otel_id)::text)));


--
-- Name: yevmiye_fisler; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.yevmiye_fisler ENABLE ROW LEVEL SECURITY;

--
-- Name: yevmiye_kalemleri; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.yevmiye_kalemleri ENABLE ROW LEVEL SECURITY;

--
-- Name: yevmiye_fisler yf_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yf_insert ON public.yevmiye_fisler FOR INSERT WITH CHECK (((
CASE
    WHEN onaylandi THEN public.auth_yetki_var('yevmiye_fis_onay'::text, 'kayit'::text)
    ELSE public.auth_yetki_var('yevmiye_fis_giris'::text, 'kayit'::text)
END OR public.auth_yetki_var('fiyat_kontrol'::text, 'kayit'::text)) AND public.auth_otel_erisim((otel_id)::text)));


--
-- Name: yevmiye_fisler yf_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yf_select ON public.yevmiye_fisler FOR SELECT USING ((public.auth_yetki_var('yevmiye_fis_giris'::text, 'goruntule'::text) AND public.auth_otel_erisim((otel_id)::text)));


--
-- Name: yevmiye_fisler yf_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yf_update ON public.yevmiye_fisler FOR UPDATE USING (((public.auth_yetki_var('yevmiye_fis_giris'::text, 'kayit'::text) OR public.auth_yetki_var('yevmiye_fis_onay'::text, 'kayit'::text) OR public.auth_yetki_var('fiyat_kontrol'::text, 'kayit'::text)) AND public.auth_otel_erisim((otel_id)::text))) WITH CHECK (((
CASE
    WHEN onaylandi THEN public.auth_yetki_var('yevmiye_fis_onay'::text, 'kayit'::text)
    ELSE public.auth_yetki_var('yevmiye_fis_giris'::text, 'kayit'::text)
END OR public.auth_yetki_var('fiyat_kontrol'::text, 'kayit'::text)) AND public.auth_otel_erisim((otel_id)::text)));


--
-- Name: yevmiye_kalemleri yk_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yk_delete ON public.yevmiye_kalemleri FOR DELETE TO authenticated USING ((public.auth_yetki_var('yevmiye_fis_giris'::text, 'kayit'::text) AND (EXISTS ( SELECT 1
   FROM public.yevmiye_fisler y
  WHERE ((y.id = yevmiye_kalemleri.fis_id) AND public.auth_otel_erisim((y.otel_id)::text))))));


--
-- Name: yevmiye_kalemleri yk_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yk_insert ON public.yevmiye_kalemleri FOR INSERT TO authenticated WITH CHECK (((public.auth_yetki_var('yevmiye_fis_giris'::text, 'kayit'::text) OR public.auth_yetki_var('yevmiye_fis_onay'::text, 'kayit'::text) OR public.auth_yetki_var('fiyat_kontrol'::text, 'kayit'::text)) AND (EXISTS ( SELECT 1
   FROM public.yevmiye_fisler y
  WHERE ((y.id = yevmiye_kalemleri.fis_id) AND public.auth_otel_erisim((y.otel_id)::text))))));


--
-- Name: yevmiye_kalemleri yk_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yk_select ON public.yevmiye_kalemleri FOR SELECT TO authenticated USING ((public.auth_yetki_var('yevmiye_fis_giris'::text, 'goruntule'::text) AND (EXISTS ( SELECT 1
   FROM public.yevmiye_fisler y
  WHERE ((y.id = yevmiye_kalemleri.fis_id) AND public.auth_otel_erisim((y.otel_id)::text))))));


--
-- Name: yevmiye_kalemleri yk_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yk_update ON public.yevmiye_kalemleri FOR UPDATE TO authenticated USING (((public.auth_yetki_var('yevmiye_fis_giris'::text, 'kayit'::text) OR public.auth_yetki_var('yevmiye_fis_onay'::text, 'kayit'::text) OR public.auth_yetki_var('fiyat_kontrol'::text, 'kayit'::text)) AND (EXISTS ( SELECT 1
   FROM public.yevmiye_fisler y
  WHERE ((y.id = yevmiye_kalemleri.fis_id) AND public.auth_otel_erisim((y.otel_id)::text)))))) WITH CHECK (((public.auth_yetki_var('yevmiye_fis_giris'::text, 'kayit'::text) OR public.auth_yetki_var('yevmiye_fis_onay'::text, 'kayit'::text) OR public.auth_yetki_var('fiyat_kontrol'::text, 'kayit'::text)) AND (EXISTS ( SELECT 1
   FROM public.yevmiye_fisler y
  WHERE ((y.id = yevmiye_kalemleri.fis_id) AND public.auth_otel_erisim((y.otel_id)::text))))));


--
-- Name: yetki_matrisi ym_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ym_select ON public.yetki_matrisi FOR SELECT TO authenticated USING (public.auth_erp_kullanicisi());


--
-- Name: yetki_matrisi ym_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ym_write ON public.yetki_matrisi USING ((public.auth_yetki_var('kullanici_yonetimi'::text, 'kayit'::text) OR public.auth_yetki_var('yetki_yonetimi'::text, 'kayit'::text))) WITH CHECK ((public.auth_yetki_var('kullanici_yonetimi'::text, 'kayit'::text) OR public.auth_yetki_var('yetki_yonetimi'::text, 'kayit'::text)));


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: -
--

GRANT USAGE ON SCHEMA public TO postgres;
GRANT USAGE ON SCHEMA public TO anon;
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT USAGE ON SCHEMA public TO service_role;


--
-- Name: FUNCTION ai_q_gunluk_ozet(p_otel text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.ai_q_gunluk_ozet(p_otel text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.ai_q_gunluk_ozet(p_otel text) TO authenticated;
GRANT ALL ON FUNCTION public.ai_q_gunluk_ozet(p_otel text) TO service_role;


--
-- Name: FUNCTION ai_q_min_alti(p_otel text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.ai_q_min_alti(p_otel text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.ai_q_min_alti(p_otel text) TO authenticated;
GRANT ALL ON FUNCTION public.ai_q_min_alti(p_otel text) TO service_role;


--
-- Name: FUNCTION ai_q_skt_yaklasan(p_otel text, p_gun integer); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.ai_q_skt_yaklasan(p_otel text, p_gun integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.ai_q_skt_yaklasan(p_otel text, p_gun integer) TO authenticated;
GRANT ALL ON FUNCTION public.ai_q_skt_yaklasan(p_otel text, p_gun integer) TO service_role;


--
-- Name: FUNCTION ai_q_stok_anomali(p_otel text, p_esik numeric); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.ai_q_stok_anomali(p_otel text, p_esik numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION public.ai_q_stok_anomali(p_otel text, p_esik numeric) TO authenticated;
GRANT ALL ON FUNCTION public.ai_q_stok_anomali(p_otel text, p_esik numeric) TO service_role;


--
-- Name: FUNCTION ai_q_tuketim_artan(p_otel text, p_gun integer); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.ai_q_tuketim_artan(p_otel text, p_gun integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.ai_q_tuketim_artan(p_otel text, p_gun integer) TO authenticated;
GRANT ALL ON FUNCTION public.ai_q_tuketim_artan(p_otel text, p_gun integer) TO service_role;


--
-- Name: FUNCTION ai_q_yavas_donen(p_otel text, p_gun integer); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.ai_q_yavas_donen(p_otel text, p_gun integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.ai_q_yavas_donen(p_otel text, p_gun integer) TO authenticated;
GRANT ALL ON FUNCTION public.ai_q_yavas_donen(p_otel text, p_gun integer) TO service_role;


--
-- Name: FUNCTION audit_log_damgala(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.audit_log_damgala() FROM PUBLIC;
GRANT ALL ON FUNCTION public.audit_log_damgala() TO authenticated;
GRANT ALL ON FUNCTION public.audit_log_damgala() TO service_role;


--
-- Name: FUNCTION auth_erp_kullanicisi(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.auth_erp_kullanicisi() FROM PUBLIC;
GRANT ALL ON FUNCTION public.auth_erp_kullanicisi() TO authenticated;
GRANT ALL ON FUNCTION public.auth_erp_kullanicisi() TO service_role;


--
-- Name: FUNCTION auth_kullanici_id(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.auth_kullanici_id() FROM PUBLIC;
GRANT ALL ON FUNCTION public.auth_kullanici_id() TO authenticated;
GRANT ALL ON FUNCTION public.auth_kullanici_id() TO service_role;


--
-- Name: FUNCTION auth_kullanici_rol_id(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.auth_kullanici_rol_id() FROM PUBLIC;
GRANT ALL ON FUNCTION public.auth_kullanici_rol_id() TO authenticated;
GRANT ALL ON FUNCTION public.auth_kullanici_rol_id() TO service_role;


--
-- Name: FUNCTION auth_otel_erisim(p_otel text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.auth_otel_erisim(p_otel text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.auth_otel_erisim(p_otel text) TO authenticated;
GRANT ALL ON FUNCTION public.auth_otel_erisim(p_otel text) TO service_role;


--
-- Name: FUNCTION auth_otel_id(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.auth_otel_id() FROM PUBLIC;
GRANT ALL ON FUNCTION public.auth_otel_id() TO authenticated;
GRANT ALL ON FUNCTION public.auth_otel_id() TO service_role;


--
-- Name: FUNCTION auth_tum_oteller(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.auth_tum_oteller() FROM PUBLIC;
GRANT ALL ON FUNCTION public.auth_tum_oteller() TO authenticated;
GRANT ALL ON FUNCTION public.auth_tum_oteller() TO service_role;


--
-- Name: FUNCTION auth_yetki_var(p_modul_kod text, p_min_seviye text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.auth_yetki_var(p_modul_kod text, p_min_seviye text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.auth_yetki_var(p_modul_kod text, p_min_seviye text) TO authenticated;
GRANT ALL ON FUNCTION public.auth_yetki_var(p_modul_kod text, p_min_seviye text) TO service_role;


--
-- Name: FUNCTION bar_kullanilabilir_stok(p_stok_kodu text, p_depo_kodu text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.bar_kullanilabilir_stok(p_stok_kodu text, p_depo_kodu text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.bar_kullanilabilir_stok(p_stok_kodu text, p_depo_kodu text) TO service_role;


--
-- Name: FUNCTION bar_siparis_durum_guncelle(p_siparis_id uuid, p_durum public.bar_durum); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.bar_siparis_durum_guncelle(p_siparis_id uuid, p_durum public.bar_durum) FROM PUBLIC;
GRANT ALL ON FUNCTION public.bar_siparis_durum_guncelle(p_siparis_id uuid, p_durum public.bar_durum) TO authenticated;
GRANT ALL ON FUNCTION public.bar_siparis_durum_guncelle(p_siparis_id uuid, p_durum public.bar_durum) TO service_role;


--
-- Name: FUNCTION bar_siparis_iptal(p_siparis_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.bar_siparis_iptal(p_siparis_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.bar_siparis_iptal(p_siparis_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.bar_siparis_iptal(p_siparis_id uuid) TO service_role;


--
-- Name: FUNCTION bar_siparis_olustur(p_otel_id text, p_depo_id text, p_masa_token text, p_oda_no text, p_kalemler jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.bar_siparis_olustur(p_otel_id text, p_depo_id text, p_masa_token text, p_oda_no text, p_kalemler jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.bar_siparis_olustur(p_otel_id text, p_depo_id text, p_masa_token text, p_oda_no text, p_kalemler jsonb) TO authenticated;
GRANT ALL ON FUNCTION public.bar_siparis_olustur(p_otel_id text, p_depo_id text, p_masa_token text, p_oda_no text, p_kalemler jsonb) TO service_role;


--
-- Name: FUNCTION bar_siparis_teslim_et(p_siparis_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.bar_siparis_teslim_et(p_siparis_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.bar_siparis_teslim_et(p_siparis_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.bar_siparis_teslim_et(p_siparis_id uuid) TO service_role;


--
-- Name: FUNCTION fatura_kaydet(p_fatura_id uuid, p_satir jsonb, p_kalemler jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.fatura_kaydet(p_fatura_id uuid, p_satir jsonb, p_kalemler jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.fatura_kaydet(p_fatura_id uuid, p_satir jsonb, p_kalemler jsonb) TO authenticated;
GRANT ALL ON FUNCTION public.fatura_kaydet(p_fatura_id uuid, p_satir jsonb, p_kalemler jsonb) TO service_role;


--
-- Name: FUNCTION giris_kaydi_ekle(p_giris_tipi text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.giris_kaydi_ekle(p_giris_tipi text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.giris_kaydi_ekle(p_giris_tipi text) TO authenticated;
GRANT ALL ON FUNCTION public.giris_kaydi_ekle(p_giris_tipi text) TO service_role;


--
-- Name: FUNCTION mal_kabul_kaydet(p_baslik jsonb, p_kalemler jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.mal_kabul_kaydet(p_baslik jsonb, p_kalemler jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.mal_kabul_kaydet(p_baslik jsonb, p_kalemler jsonb) TO authenticated;
GRANT ALL ON FUNCTION public.mal_kabul_kaydet(p_baslik jsonb, p_kalemler jsonb) TO service_role;


--
-- Name: FUNCTION pin_ayarla(p_kullanici_id uuid, p_pin text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.pin_ayarla(p_kullanici_id uuid, p_pin text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.pin_ayarla(p_kullanici_id uuid, p_pin text) TO authenticated;
GRANT ALL ON FUNCTION public.pin_ayarla(p_kullanici_id uuid, p_pin text) TO service_role;


--
-- Name: FUNCTION pin_dogrula(p_giris text, p_ip_hash text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.pin_dogrula(p_giris text, p_ip_hash text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.pin_dogrula(p_giris text, p_ip_hash text) TO service_role;


--
-- Name: FUNCTION pin_zayif_mi(p_pin text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.pin_zayif_mi(p_pin text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.pin_zayif_mi(p_pin text) TO authenticated;
GRANT ALL ON FUNCTION public.pin_zayif_mi(p_pin text) TO service_role;


--
-- Name: FUNCTION rls_auto_enable(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.rls_auto_enable() FROM PUBLIC;
GRANT ALL ON FUNCTION public.rls_auto_enable() TO service_role;


--
-- Name: FUNCTION siparis_yeniden_yonlendir(p_siparis_no text, p_olusturan text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.siparis_yeniden_yonlendir(p_siparis_no text, p_olusturan text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.siparis_yeniden_yonlendir(p_siparis_no text, p_olusturan text) TO authenticated;
GRANT ALL ON FUNCTION public.siparis_yeniden_yonlendir(p_siparis_no text, p_olusturan text) TO service_role;


--
-- Name: FUNCTION stok_ekle(p_urun_kodu text, p_depo_kodu text, p_otel_id text, p_delta numeric); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.stok_ekle(p_urun_kodu text, p_depo_kodu text, p_otel_id text, p_delta numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION public.stok_ekle(p_urun_kodu text, p_depo_kodu text, p_otel_id text, p_delta numeric) TO authenticated;
GRANT ALL ON FUNCTION public.stok_ekle(p_urun_kodu text, p_depo_kodu text, p_otel_id text, p_delta numeric) TO service_role;


--
-- Name: FUNCTION stok_transfer(p_urun_kodu text, p_kaynak_depo text, p_hedef_depo text, p_hedef_otel text, p_miktar numeric); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.stok_transfer(p_urun_kodu text, p_kaynak_depo text, p_hedef_depo text, p_hedef_otel text, p_miktar numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION public.stok_transfer(p_urun_kodu text, p_kaynak_depo text, p_hedef_depo text, p_hedef_otel text, p_miktar numeric) TO authenticated;
GRANT ALL ON FUNCTION public.stok_transfer(p_urun_kodu text, p_kaynak_depo text, p_hedef_depo text, p_hedef_otel text, p_miktar numeric) TO service_role;


--
-- Name: FUNCTION talep_asama_yetkili_mi(p_asama text, p_rol text, p_rol_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.talep_asama_yetkili_mi(p_asama text, p_rol text, p_rol_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.talep_asama_yetkili_mi(p_asama text, p_rol text, p_rol_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.talep_asama_yetkili_mi(p_asama text, p_rol text, p_rol_id uuid) TO service_role;


--
-- Name: FUNCTION talep_karar_ver(p_talep_id uuid, p_karar text, p_not text, p_tutar numeric); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.talep_karar_ver(p_talep_id uuid, p_karar text, p_not text, p_tutar numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION public.talep_karar_ver(p_talep_id uuid, p_karar text, p_not text, p_tutar numeric) TO authenticated;
GRANT ALL ON FUNCTION public.talep_karar_ver(p_talep_id uuid, p_karar text, p_not text, p_tutar numeric) TO service_role;


--
-- Name: FUNCTION talep_siparise_donustur(p_talep_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.talep_siparise_donustur(p_talep_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.talep_siparise_donustur(p_talep_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.talep_siparise_donustur(p_talep_id uuid) TO service_role;


--
-- Name: FUNCTION teklif_talebi_olustur(p_olusturan text, p_otel_id text, p_kalemler jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.teklif_talebi_olustur(p_olusturan text, p_otel_id text, p_kalemler jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.teklif_talebi_olustur(p_olusturan text, p_otel_id text, p_kalemler jsonb) TO authenticated;
GRANT ALL ON FUNCTION public.teklif_talebi_olustur(p_olusturan text, p_otel_id text, p_kalemler jsonb) TO service_role;


--
-- Name: TABLE stok; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.stok TO authenticated;
GRANT ALL ON TABLE public.stok TO service_role;


--
-- Name: TABLE stok_minimumlar; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.stok_minimumlar TO authenticated;
GRANT ALL ON TABLE public.stok_minimumlar TO service_role;


--
-- Name: TABLE urunler; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.urunler TO authenticated;
GRANT ALL ON TABLE public.urunler TO service_role;


--
-- Name: TABLE ai_min_alti_stok; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.ai_min_alti_stok TO authenticated;
GRANT ALL ON TABLE public.ai_min_alti_stok TO service_role;


--
-- Name: TABLE ai_otel_ref; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.ai_otel_ref TO authenticated;
GRANT ALL ON TABLE public.ai_otel_ref TO service_role;


--
-- Name: TABLE mal_kabuller; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.mal_kabuller TO authenticated;
GRANT ALL ON TABLE public.mal_kabuller TO service_role;


--
-- Name: TABLE skt_kayitlari; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.skt_kayitlari TO authenticated;
GRANT ALL ON TABLE public.skt_kayitlari TO service_role;


--
-- Name: TABLE ai_gunluk_ozet; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.ai_gunluk_ozet TO authenticated;
GRANT ALL ON TABLE public.ai_gunluk_ozet TO service_role;


--
-- Name: TABLE ai_skt_risk; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.ai_skt_risk TO authenticated;
GRANT ALL ON TABLE public.ai_skt_risk TO service_role;


--
-- Name: TABLE stok_hareketleri; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.stok_hareketleri TO authenticated;
GRANT ALL ON TABLE public.stok_hareketleri TO service_role;


--
-- Name: TABLE ai_stok_anomali; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.ai_stok_anomali TO authenticated;
GRANT ALL ON TABLE public.ai_stok_anomali TO service_role;


--
-- Name: TABLE ai_tuketim_trend; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.ai_tuketim_trend TO authenticated;
GRANT ALL ON TABLE public.ai_tuketim_trend TO service_role;


--
-- Name: TABLE urun_alt_gruplari; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.urun_alt_gruplari TO authenticated;
GRANT ALL ON TABLE public.urun_alt_gruplari TO service_role;


--
-- Name: TABLE urun_ana_gruplari; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.urun_ana_gruplari TO authenticated;
GRANT ALL ON TABLE public.urun_ana_gruplari TO service_role;


--
-- Name: TABLE urun_siniflandirma; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.urun_siniflandirma TO authenticated;
GRANT ALL ON TABLE public.urun_siniflandirma TO service_role;


--
-- Name: TABLE ai_urun_grup; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.ai_urun_grup TO authenticated;
GRANT ALL ON TABLE public.ai_urun_grup TO service_role;


--
-- Name: TABLE amortisman_kosustu; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.amortisman_kosustu TO authenticated;
GRANT ALL ON TABLE public.amortisman_kosustu TO service_role;


--
-- Name: TABLE audit_log; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,REFERENCES,MAINTAIN ON TABLE public.audit_log TO authenticated;
GRANT ALL ON TABLE public.audit_log TO service_role;


--
-- Name: TABLE banka_kasa_hareketleri; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.banka_kasa_hareketleri TO authenticated;
GRANT ALL ON TABLE public.banka_kasa_hareketleri TO service_role;


--
-- Name: TABLE banka_kasa_hesaplari; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.banka_kasa_hesaplari TO authenticated;
GRANT ALL ON TABLE public.banka_kasa_hesaplari TO service_role;


--
-- Name: TABLE bar_siparis_kalemleri; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.bar_siparis_kalemleri TO authenticated;
GRANT ALL ON TABLE public.bar_siparis_kalemleri TO service_role;


--
-- Name: TABLE bar_siparisleri; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.bar_siparisleri TO authenticated;
GRANT ALL ON TABLE public.bar_siparisleri TO service_role;


--
-- Name: TABLE butce_kayitlari; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.butce_kayitlari TO authenticated;
GRANT ALL ON TABLE public.butce_kayitlari TO service_role;


--
-- Name: TABLE cari_hareketler; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.cari_hareketler TO authenticated;
GRANT ALL ON TABLE public.cari_hareketler TO service_role;


--
-- Name: TABLE cariler; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.cariler TO authenticated;
GRANT ALL ON TABLE public.cariler TO service_role;


--
-- Name: TABLE cek_senetler; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.cek_senetler TO authenticated;
GRANT ALL ON TABLE public.cek_senetler TO service_role;


--
-- Name: TABLE demirbaslar; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.demirbaslar TO authenticated;
GRANT ALL ON TABLE public.demirbaslar TO service_role;


--
-- Name: TABLE doviz_kurlari; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.doviz_kurlari TO authenticated;
GRANT ALL ON TABLE public.doviz_kurlari TO service_role;


--
-- Name: TABLE edefter_kurum_bilgileri; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.edefter_kurum_bilgileri TO authenticated;
GRANT ALL ON TABLE public.edefter_kurum_bilgileri TO service_role;


--
-- Name: TABLE edefter_sube_bilgileri; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.edefter_sube_bilgileri TO authenticated;
GRANT ALL ON TABLE public.edefter_sube_bilgileri TO service_role;


--
-- Name: TABLE erp_islem_audit; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.erp_islem_audit TO authenticated;


--
-- Name: SEQUENCE erp_islem_audit_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.erp_islem_audit_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.erp_islem_audit_id_seq TO service_role;


--
-- Name: TABLE excel_import_gecmisi; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.excel_import_gecmisi TO authenticated;
GRANT ALL ON TABLE public.excel_import_gecmisi TO service_role;


--
-- Name: TABLE excel_import_satirlari; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.excel_import_satirlari TO authenticated;
GRANT ALL ON TABLE public.excel_import_satirlari TO service_role;


--
-- Name: TABLE fatura_kalemleri; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.fatura_kalemleri TO authenticated;
GRANT ALL ON TABLE public.fatura_kalemleri TO service_role;


--
-- Name: TABLE faturalar; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.faturalar TO authenticated;
GRANT ALL ON TABLE public.faturalar TO service_role;


--
-- Name: TABLE gelen_efaturalar; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.gelen_efaturalar TO authenticated;
GRANT ALL ON TABLE public.gelen_efaturalar TO service_role;


--
-- Name: TABLE giris_denemeleri; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.giris_denemeleri TO authenticated;
GRANT ALL ON TABLE public.giris_denemeleri TO service_role;


--
-- Name: SEQUENCE giris_denemeleri_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.giris_denemeleri_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.giris_denemeleri_id_seq TO service_role;


--
-- Name: TABLE giris_kayitlari; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.giris_kayitlari TO authenticated;
GRANT ALL ON TABLE public.giris_kayitlari TO service_role;


--
-- Name: SEQUENCE giris_kayitlari_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.giris_kayitlari_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.giris_kayitlari_id_seq TO service_role;


--
-- Name: TABLE hesap_plani; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.hesap_plani TO authenticated;
GRANT ALL ON TABLE public.hesap_plani TO service_role;


--
-- Name: TABLE ic_talep_kalemleri; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.ic_talep_kalemleri TO authenticated;
GRANT ALL ON TABLE public.ic_talep_kalemleri TO service_role;


--
-- Name: SEQUENCE ic_talep_kalemleri_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.ic_talep_kalemleri_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.ic_talep_kalemleri_id_seq TO service_role;


--
-- Name: TABLE ic_talepler; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.ic_talepler TO authenticated;
GRANT ALL ON TABLE public.ic_talepler TO service_role;


--
-- Name: SEQUENCE ic_talepler_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.ic_talepler_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.ic_talepler_id_seq TO service_role;


--
-- Name: TABLE kayitli_filtreler; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.kayitli_filtreler TO authenticated;
GRANT ALL ON TABLE public.kayitli_filtreler TO service_role;


--
-- Name: TABLE koli_etiketleri; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.koli_etiketleri TO authenticated;
GRANT ALL ON TABLE public.koli_etiketleri TO service_role;


--
-- Name: TABLE kullanicilar; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,MAINTAIN,UPDATE ON TABLE public.kullanicilar TO authenticated;
GRANT ALL ON TABLE public.kullanicilar TO service_role;


--
-- Name: TABLE kullanicilar_genel; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.kullanicilar_genel TO authenticated;
GRANT ALL ON TABLE public.kullanicilar_genel TO service_role;


--
-- Name: TABLE ln_siparisler; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.ln_siparisler TO authenticated;
GRANT ALL ON TABLE public.ln_siparisler TO service_role;


--
-- Name: TABLE mal_kabul_urunleri; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.mal_kabul_urunleri TO authenticated;
GRANT ALL ON TABLE public.mal_kabul_urunleri TO service_role;


--
-- Name: TABLE mali_donemler; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.mali_donemler TO authenticated;
GRANT ALL ON TABLE public.mali_donemler TO service_role;


--
-- Name: TABLE menu_urunler; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.menu_urunler TO authenticated;
GRANT ALL ON TABLE public.menu_urunler TO service_role;


--
-- Name: TABLE moduller; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.moduller TO authenticated;
GRANT ALL ON TABLE public.moduller TO service_role;


--
-- Name: TABLE recete_bilesenleri; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.recete_bilesenleri TO authenticated;
GRANT ALL ON TABLE public.recete_bilesenleri TO service_role;


--
-- Name: TABLE recete_kalemleri; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.recete_kalemleri TO authenticated;
GRANT ALL ON TABLE public.recete_kalemleri TO service_role;


--
-- Name: TABLE recete_tuketimleri; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.recete_tuketimleri TO authenticated;
GRANT ALL ON TABLE public.recete_tuketimleri TO service_role;


--
-- Name: TABLE receteler; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.receteler TO authenticated;
GRANT ALL ON TABLE public.receteler TO service_role;


--
-- Name: TABLE roller; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.roller TO authenticated;
GRANT ALL ON TABLE public.roller TO service_role;


--
-- Name: TABLE satin_alma_talep_kalemleri; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.satin_alma_talep_kalemleri TO authenticated;
GRANT ALL ON TABLE public.satin_alma_talep_kalemleri TO service_role;


--
-- Name: TABLE satin_alma_talepleri; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN ON TABLE public.satin_alma_talepleri TO authenticated;
GRANT ALL ON TABLE public.satin_alma_talepleri TO service_role;


--
-- Name: TABLE sayim_detaylari; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.sayim_detaylari TO authenticated;
GRANT ALL ON TABLE public.sayim_detaylari TO service_role;


--
-- Name: TABLE sayim_oturumlari; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.sayim_oturumlari TO authenticated;
GRANT ALL ON TABLE public.sayim_oturumlari TO service_role;


--
-- Name: TABLE sene_sonu_kapanislar; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.sene_sonu_kapanislar TO authenticated;
GRANT ALL ON TABLE public.sene_sonu_kapanislar TO service_role;


--
-- Name: TABLE siparis_kalemleri; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.siparis_kalemleri TO authenticated;
GRANT ALL ON TABLE public.siparis_kalemleri TO service_role;


--
-- Name: TABLE siparisler; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.siparisler TO authenticated;
GRANT ALL ON TABLE public.siparisler TO service_role;


--
-- Name: TABLE stok_rezervasyonlari; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.stok_rezervasyonlari TO authenticated;
GRANT ALL ON TABLE public.stok_rezervasyonlari TO service_role;


--
-- Name: TABLE talep_onay_gecmisi; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE public.talep_onay_gecmisi TO authenticated;
GRANT ALL ON TABLE public.talep_onay_gecmisi TO service_role;


--
-- Name: TABLE tedarikci_urun_eslesme; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.tedarikci_urun_eslesme TO authenticated;
GRANT ALL ON TABLE public.tedarikci_urun_eslesme TO service_role;


--
-- Name: TABLE teklif_fiyatlari; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.teklif_fiyatlari TO authenticated;
GRANT ALL ON TABLE public.teklif_fiyatlari TO service_role;


--
-- Name: TABLE teklif_kalemleri; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.teklif_kalemleri TO authenticated;
GRANT ALL ON TABLE public.teklif_kalemleri TO service_role;


--
-- Name: TABLE teklif_talepleri; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.teklif_talepleri TO authenticated;
GRANT ALL ON TABLE public.teklif_talepleri TO service_role;


--
-- Name: TABLE urun_birim_donusum; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.urun_birim_donusum TO authenticated;
GRANT ALL ON TABLE public.urun_birim_donusum TO service_role;


--
-- Name: TABLE urun_fifo_fiyat; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.urun_fifo_fiyat TO authenticated;
GRANT ALL ON TABLE public.urun_fifo_fiyat TO service_role;


--
-- Name: TABLE urun_guncel_fiyat; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.urun_guncel_fiyat TO authenticated;
GRANT ALL ON TABLE public.urun_guncel_fiyat TO service_role;


--
-- Name: TABLE uygunsuzluklar; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.uygunsuzluklar TO authenticated;
GRANT ALL ON TABLE public.uygunsuzluklar TO service_role;


--
-- Name: TABLE virmanlar; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.virmanlar TO authenticated;
GRANT ALL ON TABLE public.virmanlar TO service_role;


--
-- Name: TABLE yetki_matrisi; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.yetki_matrisi TO authenticated;
GRANT ALL ON TABLE public.yetki_matrisi TO service_role;


--
-- Name: TABLE yevmiye_fisler; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.yevmiye_fisler TO authenticated;
GRANT ALL ON TABLE public.yevmiye_fisler TO service_role;


--
-- Name: TABLE yevmiye_kalemleri; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.yevmiye_kalemleri TO authenticated;
GRANT ALL ON TABLE public.yevmiye_kalemleri TO service_role;


--
-- Name: SEQUENCE yevmiye_no_seq_2026; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.yevmiye_no_seq_2026 TO authenticated;
GRANT ALL ON SEQUENCE public.yevmiye_no_seq_2026 TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO service_role;


--
-- PostgreSQL database dump complete
--

\unrestrict rxsePyxW4hPQdRiywqyGdxOFIk7sz6iafhvnN8SnFQ8gERuKQGuIjttjbTi1Z4k

