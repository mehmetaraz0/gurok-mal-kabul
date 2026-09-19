-- ============================================================================
-- GERI AL: 2026-09-18-bar-a1-guvenlik.sql
-- ============================================================================
-- # URETIME UYGULANMADI. Yalniz A1 uygulanmis ve geri alinmasi gerekiyorsa. #
-- URETILMIS DOSYA — elle degistirme: node scripts/bar-a1-geri-al-uret.mjs
-- Kaynaklar: 2026-09-13-post-faz2-sema-dokumu.sql (eski bar fonksiyonlari) +
--            2026-09-17-stok-guncelleme-tarihi.sql (A1 oncesi stok govdeleri)
-- Tek islem olarak uygulanir (sql-uygula.ps1 --single-transaction).
--
-- KORUNUR (geri alinmaz):
--  * Veri: bar_stok_tuketimleri, bar_borc_istisnalari, stok_sayim_bekleyenleri,
--    yeni sutunlar. Eski fonksiyonlar calissin diye yalniz NOT NULL gevsetilir.
--  * Siparis/kalem/rezervasyon tablolarina DOGRUDAN YAZMANIN KAPALI olmasi
--    (runbook §3: ekranlar calissin diye bilinen acik izinler geri acilmaz;
--    hicbir ekran dogrudan yazmiyor).
--  * bar_durum enum'undaki 'istisna_bekliyor' degeri (PostgreSQL enum degeri
--    silinemez; onkosul hic kullanilmadigini dogrular).
--  * 2026-09-17 stok TARIH DUZELTMESI: A1'e ait degildir; stok govdeleri
--    tarih duzeltmeli A1-oncesi haline doner (tasarim 3.5.1(3)).
-- ============================================================================

-- 0) ONKOSULLAR — geri alma veri kaybettirmemeli
do $$
begin
  if to_regprocedure('public.stok_cikis_korumasi(text,text,numeric)') is null then
    raise exception 'ONKOSUL: A1 uygulanmis gorunmuyor; geri alinacak bir sey yok.';
  end if;
  if exists (select 1 from public.bar_borc_istisnalari where durum = 'acik') then
    raise exception 'ONKOSUL: acik borc istisnasi var; once cozulmeli (eski fonksiyonlar istisnayi bilmez).';
  end if;
  if exists (select 1 from public.bar_siparisleri where durum::text = 'istisna_bekliyor') then
    raise exception 'ONKOSUL: istisna bekleyen siparis var; once cozulmeli.';
  end if;
  if exists (select 1 from public.stok_sayim_bekleyenleri where durum = 'bekliyor') then
    raise exception 'ONKOSUL: bekleyen sayim duzeltmesi var; once uygulanmali ya da iptal edilmeli.';
  end if;
end;
$$;

-- Tarih duzeltmesi su an canli mi? Eski govdeler yazilmadan ONCE olculur.
create temp table _a1_geri_tarih on commit drop as
select coalesce(bool_and(prosrc ~* 'guncelleme_tarihi'), false) as vardi
  from pg_proc where pronamespace = 'public'::regnamespace and proname in ('stok_ekle', 'stok_transfer');

-- 1) A1'IN YENI FONKSIYONLARI
drop function if exists public.bar_siparis_teslim_et(uuid, boolean);
drop function if exists public.bar_siparis_iptal(uuid, text, jsonb);
drop function if exists public.bar_siparis_oda_dogrula(uuid, boolean);
drop function if exists public.bar_siparis_oda_reddet(uuid, text);
drop function if exists public.bar_borc_istisnasi_coz(uuid, text, uuid, boolean, text);
drop function if exists public.bar_istisna_listesi();
drop function if exists public.stok_sayim_onayla(uuid);
drop function if exists public.stok_sayim_bekleyen_uygula(uuid);
drop function if exists public.stok_sayim_bekleyen_iptal(uuid, text);
drop function if exists public.bar_masa_yetki_kapsami();
drop function if exists public._bar_konaklama_bul(text, text);
drop function if exists public._bar_folyo_gecerli(uuid, uuid);
-- 15b: eski sayim istemcisi durdurmasi geri alinir (eski istemci detaylari dogrudan okur)
drop trigger if exists stok_sayim_oturum_koruma on public.sayim_oturumlari;
drop function if exists public._stok_sayim_oturum_koruma();
drop function if exists public.stok_sayim_detaylari(uuid);
grant select on table public.sayim_detaylari to authenticated;

-- 2) ESKI FONKSIYONLAR CALISSIN DIYE GEVSETILEN KISITLAR (veri korunur)
alter table public.bar_siparis_kalemleri
  alter column birim_fiyat drop not null,
  alter column ucretli drop not null;
alter table public.bar_siparisleri
  alter column kanal drop not null,
  alter column oda_dogrulama_durumu drop not null;

-- 3) ESKI BAR FONKSIYONLARI (uretim dokumunden) + yetkileri
CREATE OR REPLACE FUNCTION public.bar_siparis_olustur(p_otel_id text, p_depo_id text, p_masa_token text, p_oda_no text, p_kalemler jsonb) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path = 'pg_catalog', 'public', 'pg_temp'
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

REVOKE ALL ON FUNCTION public.bar_siparis_olustur(p_otel_id text, p_depo_id text, p_masa_token text, p_oda_no text, p_kalemler jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.bar_siparis_olustur(p_otel_id text, p_depo_id text, p_masa_token text, p_oda_no text, p_kalemler jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bar_siparis_olustur(p_otel_id text, p_depo_id text, p_masa_token text, p_oda_no text, p_kalemler jsonb) TO service_role;

CREATE OR REPLACE FUNCTION public.bar_siparis_durum_guncelle(p_siparis_id uuid, p_durum public.bar_durum) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path = 'pg_catalog', 'public', 'pg_temp'
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

REVOKE ALL ON FUNCTION public.bar_siparis_durum_guncelle(p_siparis_id uuid, p_durum public.bar_durum) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.bar_siparis_durum_guncelle(p_siparis_id uuid, p_durum public.bar_durum) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bar_siparis_durum_guncelle(p_siparis_id uuid, p_durum public.bar_durum) TO service_role;

CREATE OR REPLACE FUNCTION public.bar_siparis_teslim_et(p_siparis_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path = 'pg_catalog', 'public', 'pg_temp'
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

REVOKE ALL ON FUNCTION public.bar_siparis_teslim_et(p_siparis_id uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.bar_siparis_teslim_et(p_siparis_id uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bar_siparis_teslim_et(p_siparis_id uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.bar_siparis_iptal(p_siparis_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path = 'pg_catalog', 'public', 'pg_temp'
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

REVOKE ALL ON FUNCTION public.bar_siparis_iptal(p_siparis_id uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.bar_siparis_iptal(p_siparis_id uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bar_siparis_iptal(p_siparis_id uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.pms_bar_folio_koprusu() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path = 'pg_catalog', 'public', 'pg_temp'
    AS $$
declare
  v_tutar  numeric(12,2);
  v_folio  public.pms_folyolar%rowtype;
begin
  -- Yalniz ucretli kalemlerin toplami folyoya duser.
  select coalesce(sum(k.adet * m.fiyat), 0) into v_tutar
    from public.bar_siparis_kalemleri k
    join public.menu_urunler m on m.id = k.menu_urun_id
   where k.siparis_id = new.id and m.ucretli;

  -- ---- TESLIM: borc yaz ----
  if new.durum = 'teslim_edildi' and old.durum is distinct from 'teslim_edildi' then
    if new.oda_no is null or btrim(new.oda_no) = '' or v_tutar = 0 then
      return null;   -- oda devri yok ya da ikram: folyoyu ilgilendirmez
    end if;

    -- GUNCEL KONAKLAMA (Adim 3 tanimi): aktif atama + giris_yapildi.
    select f.* into v_folio
      from public.pms_odalar o
      join public.pms_oda_atamalari a
        on a.oda_id = o.id and a.otel_id = o.otel_id and a.aktif
      join public.pms_rezervasyonlar r
        on r.id = a.rezervasyon_id and r.otel_id = a.otel_id
       and r.durum = 'giris_yapildi'
      join public.pms_folyolar f
        on f.rezervasyon_id = r.id and f.otel_id = r.otel_id and f.durum = 'acik'
     where o.otel_id = new.otel_id and upper(o.oda_no) = upper(btrim(new.oda_no))
     order by f.acilis_zamani
     limit 1;

    if not found then
      -- Tahsil edilemeyecek borc yazmak yerine yanlis oda numarasi ANINDA
      -- gorunur olsun. Ucretsiz siparislerde buraya hic gelinmez.
      raise exception 'Oda % icin acik folyo yok (odada konaklayan yok veya folyo kapali); oda devri yapilamaz',
        new.oda_no;
    end if;

    insert into public.pms_folio_hareketleri
      (otel_id, folio_id, tip, aciklama, tutar, kaynak_tip, kaynak_id)
    values (v_folio.otel_id, v_folio.id, 'bar',
            'Bar/restoran siparisi (oda ' || new.oda_no || ')',
            v_tutar, 'bar', new.id)
    on conflict do nothing;   -- ayni siparis iki kez borclandirilamaz
    return null;
  end if;

  -- TESLIMDEN CIKIS DIYE BIR SEY YOK: 'teslim_edildi' TERMINAL durumdur
  -- (asagidaki pms_bar_durum_kilit). Teslimden sonra yapilan duzeltme folyoya
  -- elle 'duzeltme' satiri olarak girilir; bar siparisinin durumu geri alinmaz.
  -- Bu yuzden burada ters kayit dali YOKTUR: ulasilamayan, dolayisiyla
  -- sinanamayan bir finansal kod yolu birakmiyoruz.
  return null;
end;
$$;

REVOKE ALL ON FUNCTION public.pms_bar_folio_koprusu() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.pms_bar_folio_koprusu() TO authenticated;
GRANT EXECUTE ON FUNCTION public.pms_bar_folio_koprusu() TO service_role;

CREATE OR REPLACE FUNCTION public.pms_bar_durum_kilit() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = 'pg_catalog', 'public', 'pg_temp'
    AS $$
begin
  if new.durum is not distinct from old.durum then
    return new;   -- durum degismiyor: diger kolonlar serbest
  end if;
  if old.durum in ('teslim_edildi','iptal') then
    raise exception
      'Bar siparisi % durumundan cikarilamaz (son durum). Duzeltme folyoya duzeltme satiri olarak girilir',
      old.durum
      using errcode = '42501';
  end if;
  return new;
end;
$$;

REVOKE ALL ON FUNCTION public.pms_bar_durum_kilit() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.pms_bar_durum_kilit() TO authenticated;
GRANT EXECUTE ON FUNCTION public.pms_bar_durum_kilit() TO service_role;

-- 4) STOK RPC'LERI — A1 oncesi (TARIH DUZELTMELI) hal
do $$
begin
  if not (select vardi from _a1_geri_tarih) then
    raise exception 'ONKOSUL: A1 govdeleri tarih duzeltmesini tasimiyordu; beklenmeyen durum, dur.';
  end if;
end;
$$;
-- <<STOK_GOVDELERI>>
create or replace function public.stok_ekle(p_urun_kodu text, p_depo_kodu text, p_otel_id text, p_delta numeric)
returns numeric
language plpgsql
set search_path to 'pg_catalog', 'public', 'extensions', 'pg_temp'
as $function$
declare
  v_yeni numeric;
begin
  insert into stok (urun_kodu, depo_kodu, otel_id, miktar)
  values (p_urun_kodu, p_depo_kodu, p_otel_id::otel_id, greatest(0, p_delta))
  on conflict (urun_kodu, depo_kodu)
  do update set miktar = greatest(0, stok.miktar + p_delta),
                guncelleme_tarihi = now()
  returning miktar into v_yeni;
  return v_yeni;
end;
$function$;

create or replace function public.stok_transfer(p_urun_kodu text, p_kaynak_depo text, p_hedef_depo text, p_hedef_otel text, p_miktar numeric)
returns void
language plpgsql
set search_path to 'pg_catalog', 'public', 'extensions', 'pg_temp'
as $function$
begin
  update stok set miktar = greatest(0, miktar - p_miktar),
                  guncelleme_tarihi = now()
    where urun_kodu = p_urun_kodu and depo_kodu = p_kaynak_depo;
  insert into stok (urun_kodu, depo_kodu, otel_id, miktar)
    values (p_urun_kodu, p_hedef_depo, p_hedef_otel::otel_id, p_miktar)
    on conflict (urun_kodu, depo_kodu)
    do update set miktar = greatest(0, stok.miktar + p_miktar),
                  guncelleme_tarihi = now();
end;
$function$;
-- <</STOK_GOVDELERI>>
revoke all on function public.stok_ekle(text, text, text, numeric) from public, anon;
grant execute on function public.stok_ekle(text, text, text, numeric) to authenticated, service_role;
revoke all on function public.stok_transfer(text, text, text, text, numeric) from public, anon;
grant execute on function public.stok_transfer(text, text, text, text, numeric) to authenticated, service_role;

-- 5) A1 IC YARDIMCILARI (artik cagiran yok)
drop function if exists public.stok_cikis_korumasi(text, text, numeric);
drop function if exists public._bar_stok_dus(public.otel_id, text, text, numeric, text);
drop function if exists public._stok_delta_uygula(public.otel_id, text, text, numeric, text, text);
drop function if exists public._stok_kilitle(text, text);

-- 6) SON KOSULLAR
do $$
begin
  if not (select bool_and(prosrc ~* 'guncelleme_tarihi\s*=\s*now\(\)') from pg_proc
           where pronamespace = 'public'::regnamespace and proname in ('stok_ekle', 'stok_transfer')) then
    raise exception 'SON KOSUL: geri alma tarih duzeltmesini kaybettirdi.';
  end if;
  if exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace
              and prosrc ~* 'stok_cikis_korumasi' and proname in ('stok_ekle', 'stok_transfer')) then
    raise exception 'SON KOSUL: stok RPCleri hala A1 korumasini cagiriyor.';
  end if;
  if to_regprocedure('public.bar_siparis_teslim_et(uuid)') is null
     or to_regprocedure('public.bar_siparis_iptal(uuid)') is null then
    raise exception 'SON KOSUL: eski teslim/iptal imzasi geri gelmedi.';
  end if;
  if has_table_privilege('authenticated', 'public.bar_siparisleri', 'UPDATE') then
    raise exception 'SON KOSUL: dogrudan yazma yeniden acilmis — acilmamaliydi.';
  end if;
end;
$$;
