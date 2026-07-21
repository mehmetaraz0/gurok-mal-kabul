--
-- PostgreSQL database dump
--

\restrict Qpbcxu28RPBkE2ymVmBZZUhCTD8xcH89jKlykwNFqZ8Rc0ZItpwBtGrV0zjG32F

-- Dumped from database version 17.6
-- Dumped by pg_dump version 17.10

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
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA public;


--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS 'standard public schema';


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
-- Name: auth_kullanici_rol_id(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.auth_kullanici_rol_id() RETURNS uuid
    LANGUAGE sql STABLE
    AS $$
  select rol_id from kullanicilar where auth_user_id = auth.uid() limit 1;
$$;


--
-- Name: auth_yetki_var(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.auth_yetki_var(p_modul_kod text, p_min_seviye text DEFAULT 'goruntule'::text) RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
  select exists (
    select 1 from yetki_matrisi ym
    join moduller m on m.id = ym.modul_id
    where ym.rol_id = auth_kullanici_rol_id()
      and m.kod = p_modul_kod
      and m.aktif = true
      and ym.yetki::text = any(
        case p_min_seviye
          when 'goruntule' then array['goruntule','kayit','tam']
          when 'kayit' then array['kayit','tam']
          when 'tam' then array['tam']
          else array[]::text[]
        end
      )
  );
$$;


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
-- Name: stok_ekle(text, text, text, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.stok_ekle(p_urun_kodu text, p_depo_kodu text, p_otel_id text, p_delta numeric) RETURNS numeric
    LANGUAGE plpgsql
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


SET default_tablespace = '';

SET default_table_access_method = heap;

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
    zaman timestamp with time zone DEFAULT now() NOT NULL
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
    pin text,
    rol_id uuid,
    gizli boolean DEFAULT false,
    depo_id text,
    eposta text
);


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
-- Name: tedarikci_teklif_kalemleri; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tedarikci_teklif_kalemleri (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tedarikci_teklif_id uuid,
    teklif_talep_kalem_id uuid,
    birim_fiyat numeric,
    not_alani text
);


--
-- Name: tedarikci_teklifler; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tedarikci_teklifler (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    teklif_talep_id uuid,
    firma_ad text NOT NULL,
    firma_kodu text,
    durum text DEFAULT 'bekleniyor'::text,
    teklif_tarihi timestamp with time zone,
    not_alani text
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
-- Name: teklif_talep_kalemleri; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.teklif_talep_kalemleri (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    teklif_talep_id uuid,
    urun_kodu text,
    urun_adi text,
    miktar numeric,
    birim text
);


--
-- Name: teklif_talepleri; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.teklif_talepleri (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    talep_id uuid,
    otel_id text,
    olusturan_ad text,
    olusturma_tarihi timestamp with time zone DEFAULT now(),
    durum text DEFAULT 'acik'::text,
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
-- Name: urunler; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.urunler (
    kod text NOT NULL,
    ad text NOT NULL,
    birim text DEFAULT 'KG'::text NOT NULL,
    grup text,
    sicaklik_kriteri text,
    olusturma_tarihi timestamp with time zone DEFAULT now() NOT NULL,
    sicaklik_kriter text
);


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
-- Name: tedarikci_teklif_kalemleri tedarikci_teklif_kalemleri_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tedarikci_teklif_kalemleri
    ADD CONSTRAINT tedarikci_teklif_kalemleri_pkey PRIMARY KEY (id);


--
-- Name: tedarikci_teklif_kalemleri tedarikci_teklif_kalemleri_tedarikci_teklif_id_teklif_talep_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tedarikci_teklif_kalemleri
    ADD CONSTRAINT tedarikci_teklif_kalemleri_tedarikci_teklif_id_teklif_talep_key UNIQUE (tedarikci_teklif_id, teklif_talep_kalem_id);


--
-- Name: tedarikci_teklifler tedarikci_teklifler_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tedarikci_teklifler
    ADD CONSTRAINT tedarikci_teklifler_pkey PRIMARY KEY (id);


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
-- Name: teklif_talep_kalemleri teklif_talep_kalemleri_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.teklif_talep_kalemleri
    ADD CONSTRAINT teklif_talep_kalemleri_pkey PRIMARY KEY (id);


--
-- Name: teklif_talepleri teklif_talepleri_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.teklif_talepleri
    ADD CONSTRAINT teklif_talepleri_pkey PRIMARY KEY (id);


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
-- Name: stok_minimumlar_urun_kodu_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX stok_minimumlar_urun_kodu_key ON public.stok_minimumlar USING btree (urun_kodu);


--
-- Name: banka_kasa_hareketleri banka_kasa_hareketleri_hesap_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.banka_kasa_hareketleri
    ADD CONSTRAINT banka_kasa_hareketleri_hesap_id_fkey FOREIGN KEY (hesap_id) REFERENCES public.banka_kasa_hesaplari(id) ON DELETE RESTRICT;


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
-- Name: tedarikci_teklif_kalemleri tedarikci_teklif_kalemleri_tedarikci_teklif_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tedarikci_teklif_kalemleri
    ADD CONSTRAINT tedarikci_teklif_kalemleri_tedarikci_teklif_id_fkey FOREIGN KEY (tedarikci_teklif_id) REFERENCES public.tedarikci_teklifler(id);


--
-- Name: tedarikci_teklif_kalemleri tedarikci_teklif_kalemleri_teklif_talep_kalem_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tedarikci_teklif_kalemleri
    ADD CONSTRAINT tedarikci_teklif_kalemleri_teklif_talep_kalem_id_fkey FOREIGN KEY (teklif_talep_kalem_id) REFERENCES public.teklif_talep_kalemleri(id);


--
-- Name: tedarikci_teklifler tedarikci_teklifler_teklif_talep_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tedarikci_teklifler
    ADD CONSTRAINT tedarikci_teklifler_teklif_talep_id_fkey FOREIGN KEY (teklif_talep_id) REFERENCES public.teklif_talepleri(id);


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
-- Name: teklif_talep_kalemleri teklif_talep_kalemleri_teklif_talep_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.teklif_talep_kalemleri
    ADD CONSTRAINT teklif_talep_kalemleri_teklif_talep_id_fkey FOREIGN KEY (teklif_talep_id) REFERENCES public.teklif_talepleri(id);


--
-- Name: teklif_talepleri teklif_talepleri_talep_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.teklif_talepleri
    ADD CONSTRAINT teklif_talepleri_talep_id_fkey FOREIGN KEY (talep_id) REFERENCES public.satin_alma_talepleri(id);


--
-- Name: urun_birim_donusum urun_birim_donusum_urun_kodu_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.urun_birim_donusum
    ADD CONSTRAINT urun_birim_donusum_urun_kodu_fkey FOREIGN KEY (urun_kodu) REFERENCES public.urunler(kod);


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

CREATE POLICY al_insert ON public.audit_log FOR INSERT WITH CHECK ((auth.uid() IS NOT NULL));


--
-- Name: audit_log al_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY al_select ON public.audit_log FOR SELECT USING (public.auth_yetki_var('denetim_izi'::text, 'goruntule'::text));


--
-- Name: excel_import_gecmisi allow_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY allow_insert ON public.excel_import_gecmisi FOR INSERT WITH CHECK (true);


--
-- Name: excel_import_satirlari allow_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY allow_insert ON public.excel_import_satirlari FOR INSERT WITH CHECK (true);


--
-- Name: excel_import_gecmisi allow_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY allow_select ON public.excel_import_gecmisi FOR SELECT USING (true);


--
-- Name: excel_import_satirlari allow_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY allow_select ON public.excel_import_satirlari FOR SELECT USING (true);


--
-- Name: kullanicilar allow_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY allow_select ON public.kullanicilar FOR SELECT USING (true);


--
-- Name: excel_import_gecmisi allow_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY allow_update ON public.excel_import_gecmisi FOR UPDATE USING (true) WITH CHECK (true);


--
-- Name: excel_import_satirlari allow_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY allow_update ON public.excel_import_satirlari FOR UPDATE USING (true) WITH CHECK (true);


--
-- Name: amortisman_kosustu; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.amortisman_kosustu ENABLE ROW LEVEL SECURITY;

--
-- Name: ln_siparisler anon_all_ln_siparisler; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY anon_all_ln_siparisler ON public.ln_siparisler USING (true) WITH CHECK (true);


--
-- Name: audit_log; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;

--
-- Name: banka_kasa_hareketleri; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.banka_kasa_hareketleri ENABLE ROW LEVEL SECURITY;

--
-- Name: banka_kasa_hesaplari; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.banka_kasa_hesaplari ENABLE ROW LEVEL SECURITY;

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

CREATE POLICY fat_insert ON public.faturalar FOR INSERT WITH CHECK ((public.auth_yetki_var('fatura_giris'::text, 'kayit'::text) OR public.auth_yetki_var('fiyat_kontrol'::text, 'kayit'::text) OR public.auth_yetki_var('siparis_olustur'::text, 'kayit'::text)));


--
-- Name: faturalar fat_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY fat_update ON public.faturalar FOR UPDATE USING ((public.auth_yetki_var('fatura_giris'::text, 'kayit'::text) OR public.auth_yetki_var('fiyat_kontrol'::text, 'kayit'::text) OR public.auth_yetki_var('siparis_olustur'::text, 'kayit'::text))) WITH CHECK ((public.auth_yetki_var('fatura_giris'::text, 'kayit'::text) OR public.auth_yetki_var('fiyat_kontrol'::text, 'kayit'::text) OR public.auth_yetki_var('siparis_olustur'::text, 'kayit'::text)));


--
-- Name: faturalar; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.faturalar ENABLE ROW LEVEL SECURITY;

--
-- Name: gelen_efaturalar; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.gelen_efaturalar ENABLE ROW LEVEL SECURITY;

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

CREATE POLICY it_insert ON public.ic_talepler FOR INSERT WITH CHECK (public.auth_yetki_var('depo_siparis'::text, 'kayit'::text));


--
-- Name: ic_talepler it_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY it_select ON public.ic_talepler FOR SELECT USING (public.auth_yetki_var('depo_siparis'::text, 'goruntule'::text));


--
-- Name: ic_talepler it_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY it_update ON public.ic_talepler FOR UPDATE USING (public.auth_yetki_var('depo_siparis'::text, 'kayit'::text)) WITH CHECK (public.auth_yetki_var('depo_siparis'::text, 'kayit'::text));


--
-- Name: ic_talep_kalemleri itk_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY itk_insert ON public.ic_talep_kalemleri FOR INSERT WITH CHECK (public.auth_yetki_var('depo_siparis'::text, 'kayit'::text));


--
-- Name: ic_talep_kalemleri itk_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY itk_select ON public.ic_talep_kalemleri FOR SELECT USING (public.auth_yetki_var('depo_siparis'::text, 'goruntule'::text));


--
-- Name: ic_talep_kalemleri itk_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY itk_update ON public.ic_talep_kalemleri FOR UPDATE USING (public.auth_yetki_var('depo_siparis'::text, 'kayit'::text)) WITH CHECK (public.auth_yetki_var('depo_siparis'::text, 'kayit'::text));


--
-- Name: koli_etiketleri ke_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ke_select ON public.koli_etiketleri FOR SELECT USING (public.auth_yetki_var('fiyat_kontrol'::text, 'goruntule'::text));


--
-- Name: koli_etiketleri ke_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ke_update ON public.koli_etiketleri FOR UPDATE USING (public.auth_yetki_var('fiyat_kontrol'::text, 'kayit'::text)) WITH CHECK (public.auth_yetki_var('fiyat_kontrol'::text, 'kayit'::text));


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
-- Name: mal_kabuller mk_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY mk_select ON public.mal_kabuller FOR SELECT USING (public.auth_yetki_var('fiyat_kontrol'::text, 'goruntule'::text));


--
-- Name: mal_kabuller mk_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY mk_update ON public.mal_kabuller FOR UPDATE USING (public.auth_yetki_var('fiyat_kontrol'::text, 'kayit'::text)) WITH CHECK (public.auth_yetki_var('fiyat_kontrol'::text, 'kayit'::text));


--
-- Name: mal_kabul_urunleri mku_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY mku_select ON public.mal_kabul_urunleri FOR SELECT USING (public.auth_yetki_var('fiyat_kontrol'::text, 'goruntule'::text));


--
-- Name: mal_kabul_urunleri mku_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY mku_update ON public.mal_kabul_urunleri FOR UPDATE USING (public.auth_yetki_var('fiyat_kontrol'::text, 'kayit'::text)) WITH CHECK (public.auth_yetki_var('fiyat_kontrol'::text, 'kayit'::text));


--
-- Name: receteler r_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY r_insert ON public.receteler FOR INSERT WITH CHECK (public.auth_yetki_var('gunluk_tuketim'::text, 'kayit'::text));


--
-- Name: receteler r_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY r_select ON public.receteler FOR SELECT USING (public.auth_yetki_var('gunluk_tuketim'::text, 'goruntule'::text));


--
-- Name: receteler r_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY r_update ON public.receteler FOR UPDATE USING (public.auth_yetki_var('gunluk_tuketim'::text, 'kayit'::text)) WITH CHECK (public.auth_yetki_var('gunluk_tuketim'::text, 'kayit'::text));


--
-- Name: recete_kalemleri; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.recete_kalemleri ENABLE ROW LEVEL SECURITY;

--
-- Name: recete_tuketimleri; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.recete_tuketimleri ENABLE ROW LEVEL SECURITY;

--
-- Name: receteler; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.receteler ENABLE ROW LEVEL SECURITY;

--
-- Name: recete_kalemleri rk_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rk_delete ON public.recete_kalemleri FOR DELETE USING (public.auth_yetki_var('gunluk_tuketim'::text, 'kayit'::text));


--
-- Name: recete_kalemleri rk_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rk_insert ON public.recete_kalemleri FOR INSERT WITH CHECK (public.auth_yetki_var('gunluk_tuketim'::text, 'kayit'::text));


--
-- Name: recete_kalemleri rk_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rk_select ON public.recete_kalemleri FOR SELECT USING (public.auth_yetki_var('gunluk_tuketim'::text, 'goruntule'::text));


--
-- Name: recete_tuketimleri rt_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rt_insert ON public.recete_tuketimleri FOR INSERT WITH CHECK (public.auth_yetki_var('gunluk_tuketim'::text, 'kayit'::text));


--
-- Name: recete_tuketimleri rt_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rt_select ON public.recete_tuketimleri FOR SELECT USING (public.auth_yetki_var('gunluk_tuketim'::text, 'goruntule'::text));


--
-- Name: satin_alma_talepleri sat_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sat_insert ON public.satin_alma_talepleri FOR INSERT WITH CHECK (public.auth_yetki_var('ic_talep'::text, 'kayit'::text));


--
-- Name: satin_alma_talepleri sat_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sat_select ON public.satin_alma_talepleri FOR SELECT USING (public.auth_yetki_var('ic_talep'::text, 'goruntule'::text));


--
-- Name: satin_alma_talepleri sat_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sat_update ON public.satin_alma_talepleri FOR UPDATE USING (public.auth_yetki_var('ic_talep'::text, 'kayit'::text)) WITH CHECK (public.auth_yetki_var('ic_talep'::text, 'kayit'::text));


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

CREATE POLICY satk_insert ON public.satin_alma_talep_kalemleri FOR INSERT WITH CHECK (public.auth_yetki_var('ic_talep'::text, 'kayit'::text));


--
-- Name: satin_alma_talep_kalemleri satk_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY satk_select ON public.satin_alma_talep_kalemleri FOR SELECT USING (public.auth_yetki_var('ic_talep'::text, 'goruntule'::text));


--
-- Name: satin_alma_talep_kalemleri satk_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY satk_update ON public.satin_alma_talep_kalemleri FOR UPDATE USING (public.auth_yetki_var('ic_talep'::text, 'kayit'::text)) WITH CHECK (public.auth_yetki_var('ic_talep'::text, 'kayit'::text));


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

CREATE POLICY sip_insert ON public.siparisler FOR INSERT WITH CHECK (public.auth_yetki_var('siparis_olustur'::text, 'kayit'::text));


--
-- Name: siparisler sip_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sip_select ON public.siparisler FOR SELECT USING ((public.auth_yetki_var('siparis_olustur'::text, 'goruntule'::text) OR public.auth_yetki_var('siparis_takip'::text, 'goruntule'::text)));


--
-- Name: siparisler sip_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sip_update ON public.siparisler FOR UPDATE USING (public.auth_yetki_var('siparis_olustur'::text, 'kayit'::text)) WITH CHECK (public.auth_yetki_var('siparis_olustur'::text, 'kayit'::text));


--
-- Name: siparis_kalemleri; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.siparis_kalemleri ENABLE ROW LEVEL SECURITY;

--
-- Name: siparisler; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.siparisler ENABLE ROW LEVEL SECURITY;

--
-- Name: siparis_kalemleri sipk_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sipk_insert ON public.siparis_kalemleri FOR INSERT WITH CHECK (public.auth_yetki_var('siparis_olustur'::text, 'kayit'::text));


--
-- Name: siparis_kalemleri sipk_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sipk_select ON public.siparis_kalemleri FOR SELECT USING ((public.auth_yetki_var('siparis_olustur'::text, 'goruntule'::text) OR public.auth_yetki_var('siparis_takip'::text, 'goruntule'::text)));


--
-- Name: siparis_kalemleri sipk_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sipk_update ON public.siparis_kalemleri FOR UPDATE USING (public.auth_yetki_var('siparis_olustur'::text, 'kayit'::text)) WITH CHECK (public.auth_yetki_var('siparis_olustur'::text, 'kayit'::text));


--
-- Name: skt_kayitlari skt_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY skt_insert ON public.skt_kayitlari FOR INSERT WITH CHECK (public.auth_yetki_var('mal_kabul_kalite'::text, 'kayit'::text));


--
-- Name: skt_kayitlari; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.skt_kayitlari ENABLE ROW LEVEL SECURITY;

--
-- Name: skt_kayitlari skt_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY skt_select ON public.skt_kayitlari FOR SELECT USING (public.auth_yetki_var('mal_kabul_kalite'::text, 'goruntule'::text));


--
-- Name: skt_kayitlari skt_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY skt_update ON public.skt_kayitlari FOR UPDATE USING (public.auth_yetki_var('mal_kabul_kalite'::text, 'kayit'::text)) WITH CHECK (public.auth_yetki_var('mal_kabul_kalite'::text, 'kayit'::text));


--
-- Name: stok_minimumlar sm_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sm_insert ON public.stok_minimumlar FOR INSERT WITH CHECK (public.auth_yetki_var('stok_takip'::text, 'kayit'::text));


--
-- Name: stok_minimumlar sm_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sm_select ON public.stok_minimumlar FOR SELECT USING (public.auth_yetki_var('stok_takip'::text, 'goruntule'::text));


--
-- Name: stok_minimumlar sm_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sm_update ON public.stok_minimumlar FOR UPDATE USING (public.auth_yetki_var('stok_takip'::text, 'kayit'::text)) WITH CHECK (public.auth_yetki_var('stok_takip'::text, 'kayit'::text));


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
-- Name: talep_onay_gecmisi; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.talep_onay_gecmisi ENABLE ROW LEVEL SECURITY;

--
-- Name: tedarikci_teklif_kalemleri; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.tedarikci_teklif_kalemleri ENABLE ROW LEVEL SECURITY;

--
-- Name: tedarikci_teklifler; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.tedarikci_teklifler ENABLE ROW LEVEL SECURITY;

--
-- Name: tedarikci_urun_eslesme; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.tedarikci_urun_eslesme ENABLE ROW LEVEL SECURITY;

--
-- Name: tedarikci_teklifler tedt_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tedt_insert ON public.tedarikci_teklifler FOR INSERT WITH CHECK (public.auth_yetki_var('siparis_olustur'::text, 'kayit'::text));


--
-- Name: tedarikci_teklifler tedt_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tedt_select ON public.tedarikci_teklifler FOR SELECT USING (public.auth_yetki_var('siparis_olustur'::text, 'goruntule'::text));


--
-- Name: tedarikci_teklifler tedt_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tedt_update ON public.tedarikci_teklifler FOR UPDATE USING (public.auth_yetki_var('siparis_olustur'::text, 'kayit'::text)) WITH CHECK (public.auth_yetki_var('siparis_olustur'::text, 'kayit'::text));


--
-- Name: tedarikci_teklif_kalemleri tedtk_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tedtk_insert ON public.tedarikci_teklif_kalemleri FOR INSERT WITH CHECK (public.auth_yetki_var('siparis_olustur'::text, 'kayit'::text));


--
-- Name: tedarikci_teklif_kalemleri tedtk_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tedtk_select ON public.tedarikci_teklif_kalemleri FOR SELECT USING (public.auth_yetki_var('siparis_olustur'::text, 'goruntule'::text));


--
-- Name: tedarikci_teklif_kalemleri tedtk_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tedtk_update ON public.tedarikci_teklif_kalemleri FOR UPDATE USING (public.auth_yetki_var('siparis_olustur'::text, 'kayit'::text)) WITH CHECK (public.auth_yetki_var('siparis_olustur'::text, 'kayit'::text));


--
-- Name: teklif_talep_kalemleri; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.teklif_talep_kalemleri ENABLE ROW LEVEL SECURITY;

--
-- Name: teklif_talepleri; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.teklif_talepleri ENABLE ROW LEVEL SECURITY;

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

CREATE POLICY tt_insert ON public.teklif_talepleri FOR INSERT WITH CHECK (public.auth_yetki_var('siparis_olustur'::text, 'kayit'::text));


--
-- Name: teklif_talepleri tt_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tt_select ON public.teklif_talepleri FOR SELECT USING (public.auth_yetki_var('siparis_olustur'::text, 'goruntule'::text));


--
-- Name: teklif_talepleri tt_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tt_update ON public.teklif_talepleri FOR UPDATE USING (public.auth_yetki_var('siparis_olustur'::text, 'kayit'::text)) WITH CHECK (public.auth_yetki_var('siparis_olustur'::text, 'kayit'::text));


--
-- Name: teklif_talep_kalemleri ttk_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ttk_insert ON public.teklif_talep_kalemleri FOR INSERT WITH CHECK (public.auth_yetki_var('siparis_olustur'::text, 'kayit'::text));


--
-- Name: teklif_talep_kalemleri ttk_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ttk_select ON public.teklif_talep_kalemleri FOR SELECT USING (public.auth_yetki_var('siparis_olustur'::text, 'goruntule'::text));


--
-- Name: tedarikci_urun_eslesme tue_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tue_select ON public.tedarikci_urun_eslesme FOR SELECT USING (public.auth_yetki_var('fiyat_kontrol'::text, 'goruntule'::text));


--
-- Name: urunler urn_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY urn_select ON public.urunler FOR SELECT USING ((auth.uid() IS NOT NULL));


--
-- Name: urun_birim_donusum; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.urun_birim_donusum ENABLE ROW LEVEL SECURITY;

--
-- Name: urunler; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.urunler ENABLE ROW LEVEL SECURITY;

--
-- Name: uygunsuzluklar uy_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY uy_select ON public.uygunsuzluklar FOR SELECT USING (public.auth_yetki_var('fiyat_kontrol'::text, 'goruntule'::text));


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

CREATE POLICY yetki_insert ON public.banka_kasa_hareketleri FOR INSERT WITH CHECK (public.auth_yetki_var('banka_kasa'::text, 'kayit'::text));


--
-- Name: banka_kasa_hesaplari yetki_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yetki_insert ON public.banka_kasa_hesaplari FOR INSERT WITH CHECK (public.auth_yetki_var('banka_kasa'::text, 'kayit'::text));


--
-- Name: butce_kayitlari yetki_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yetki_insert ON public.butce_kayitlari FOR INSERT WITH CHECK (public.auth_yetki_var('butce_yonetimi'::text, 'kayit'::text));


--
-- Name: cari_hareketler yetki_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yetki_insert ON public.cari_hareketler FOR INSERT WITH CHECK (public.auth_yetki_var('cari_hesaplar'::text, 'kayit'::text));


--
-- Name: cariler yetki_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yetki_insert ON public.cariler FOR INSERT WITH CHECK (public.auth_yetki_var('cari_hesaplar'::text, 'kayit'::text));


--
-- Name: cek_senetler yetki_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yetki_insert ON public.cek_senetler FOR INSERT WITH CHECK (public.auth_yetki_var('cek_senet_yonetimi'::text, 'kayit'::text));


--
-- Name: demirbaslar yetki_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yetki_insert ON public.demirbaslar FOR INSERT WITH CHECK (public.auth_yetki_var('demirbas_yonetimi'::text, 'kayit'::text));


--
-- Name: kullanicilar yetki_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yetki_insert ON public.kullanicilar FOR INSERT WITH CHECK (public.auth_yetki_var('kullanici_yonetimi'::text, 'kayit'::text));


--
-- Name: stok yetki_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yetki_insert ON public.stok FOR INSERT WITH CHECK (public.auth_yetki_var('stok_takip'::text, 'kayit'::text));


--
-- Name: stok_hareketleri yetki_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yetki_insert ON public.stok_hareketleri FOR INSERT WITH CHECK (public.auth_yetki_var('stok_takip'::text, 'kayit'::text));


--
-- Name: banka_kasa_hareketleri yetki_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yetki_select ON public.banka_kasa_hareketleri FOR SELECT USING (public.auth_yetki_var('banka_kasa'::text, 'goruntule'::text));


--
-- Name: banka_kasa_hesaplari yetki_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yetki_select ON public.banka_kasa_hesaplari FOR SELECT USING (public.auth_yetki_var('banka_kasa'::text, 'goruntule'::text));


--
-- Name: butce_kayitlari yetki_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yetki_select ON public.butce_kayitlari FOR SELECT USING (public.auth_yetki_var('butce_yonetimi'::text, 'goruntule'::text));


--
-- Name: cari_hareketler yetki_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yetki_select ON public.cari_hareketler FOR SELECT USING (public.auth_yetki_var('cari_hesaplar'::text, 'goruntule'::text));


--
-- Name: cariler yetki_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yetki_select ON public.cariler FOR SELECT USING (public.auth_yetki_var('cari_hesaplar'::text, 'goruntule'::text));


--
-- Name: cek_senetler yetki_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yetki_select ON public.cek_senetler FOR SELECT USING (public.auth_yetki_var('cek_senet_yonetimi'::text, 'goruntule'::text));


--
-- Name: demirbaslar yetki_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yetki_select ON public.demirbaslar FOR SELECT USING (public.auth_yetki_var('demirbas_yonetimi'::text, 'goruntule'::text));


--
-- Name: faturalar yetki_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yetki_select ON public.faturalar FOR SELECT USING (public.auth_yetki_var('fatura_giris'::text, 'goruntule'::text));


--
-- Name: stok yetki_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yetki_select ON public.stok FOR SELECT USING (public.auth_yetki_var('stok_takip'::text, 'goruntule'::text));


--
-- Name: stok_hareketleri yetki_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yetki_select ON public.stok_hareketleri FOR SELECT USING (public.auth_yetki_var('stok_takip'::text, 'goruntule'::text));


--
-- Name: banka_kasa_hareketleri yetki_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yetki_update ON public.banka_kasa_hareketleri FOR UPDATE USING (public.auth_yetki_var('banka_kasa'::text, 'kayit'::text)) WITH CHECK (public.auth_yetki_var('banka_kasa'::text, 'kayit'::text));


--
-- Name: banka_kasa_hesaplari yetki_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yetki_update ON public.banka_kasa_hesaplari FOR UPDATE USING (public.auth_yetki_var('banka_kasa'::text, 'kayit'::text)) WITH CHECK (public.auth_yetki_var('banka_kasa'::text, 'kayit'::text));


--
-- Name: butce_kayitlari yetki_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yetki_update ON public.butce_kayitlari FOR UPDATE USING (public.auth_yetki_var('butce_yonetimi'::text, 'kayit'::text)) WITH CHECK (public.auth_yetki_var('butce_yonetimi'::text, 'kayit'::text));


--
-- Name: cari_hareketler yetki_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yetki_update ON public.cari_hareketler FOR UPDATE USING (public.auth_yetki_var('cari_hesaplar'::text, 'kayit'::text)) WITH CHECK (public.auth_yetki_var('cari_hesaplar'::text, 'kayit'::text));


--
-- Name: cariler yetki_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yetki_update ON public.cariler FOR UPDATE USING (public.auth_yetki_var('cari_hesaplar'::text, 'kayit'::text)) WITH CHECK (public.auth_yetki_var('cari_hesaplar'::text, 'kayit'::text));


--
-- Name: cek_senetler yetki_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yetki_update ON public.cek_senetler FOR UPDATE USING (public.auth_yetki_var('cek_senet_yonetimi'::text, 'kayit'::text)) WITH CHECK (public.auth_yetki_var('cek_senet_yonetimi'::text, 'kayit'::text));


--
-- Name: demirbaslar yetki_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yetki_update ON public.demirbaslar FOR UPDATE USING (public.auth_yetki_var('demirbas_yonetimi'::text, 'kayit'::text)) WITH CHECK (public.auth_yetki_var('demirbas_yonetimi'::text, 'kayit'::text));


--
-- Name: kullanicilar yetki_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yetki_update ON public.kullanicilar FOR UPDATE USING (public.auth_yetki_var('kullanici_yonetimi'::text, 'kayit'::text)) WITH CHECK (public.auth_yetki_var('kullanici_yonetimi'::text, 'kayit'::text));


--
-- Name: stok yetki_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yetki_update ON public.stok FOR UPDATE USING (public.auth_yetki_var('stok_takip'::text, 'kayit'::text)) WITH CHECK (public.auth_yetki_var('stok_takip'::text, 'kayit'::text));


--
-- Name: stok_hareketleri yetki_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yetki_update ON public.stok_hareketleri FOR UPDATE USING (public.auth_yetki_var('stok_takip'::text, 'kayit'::text)) WITH CHECK (public.auth_yetki_var('stok_takip'::text, 'kayit'::text));


--
-- Name: yevmiye_fisler; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.yevmiye_fisler ENABLE ROW LEVEL SECURITY;

--
-- Name: yevmiye_fisler yf_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yf_insert ON public.yevmiye_fisler FOR INSERT WITH CHECK ((
CASE
    WHEN onaylandi THEN public.auth_yetki_var('yevmiye_fis_onay'::text, 'kayit'::text)
    ELSE public.auth_yetki_var('yevmiye_fis_giris'::text, 'kayit'::text)
END OR public.auth_yetki_var('fiyat_kontrol'::text, 'kayit'::text)));


--
-- Name: yevmiye_fisler yf_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yf_select ON public.yevmiye_fisler FOR SELECT USING (public.auth_yetki_var('yevmiye_fis_giris'::text, 'goruntule'::text));


--
-- Name: yevmiye_fisler yf_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY yf_update ON public.yevmiye_fisler FOR UPDATE USING ((public.auth_yetki_var('yevmiye_fis_giris'::text, 'kayit'::text) OR public.auth_yetki_var('yevmiye_fis_onay'::text, 'kayit'::text) OR public.auth_yetki_var('fiyat_kontrol'::text, 'kayit'::text))) WITH CHECK ((
CASE
    WHEN onaylandi THEN public.auth_yetki_var('yevmiye_fis_onay'::text, 'kayit'::text)
    ELSE public.auth_yetki_var('yevmiye_fis_giris'::text, 'kayit'::text)
END OR public.auth_yetki_var('fiyat_kontrol'::text, 'kayit'::text)));


--
-- PostgreSQL database dump complete
--

\unrestrict Qpbcxu28RPBkE2ymVmBZZUhCTD8xcH89jKlykwNFqZ8Rc0ZItpwBtGrV0zjG32F

