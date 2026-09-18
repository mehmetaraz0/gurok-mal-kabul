-- ============================================================================
-- BAR A1 — BAR VE PMS GUVENLIGI (tum barlar)
-- ============================================================================
-- # URETIME UYGULANMADI. Aday migration; yalniz yerel/izole ortamda sinandi. #
--
-- Tasarim : docs/superpowers/specs/2026-09-17-bar-guvenlik-ikmal-kabul-design.md
--           revizyon 5 — bolum 3, 3.5.1, 15 (T23-T26, O11-O15)
-- Plan    : docs/superpowers/plans/2026-09-18-bar-a1-plan.md
-- Standart: docs/kurulum/MIGRATION-GUVENLIK-STANDARDI.md
-- Denetim : node scripts/migration-guvenlik-kontrol.mjs docs/kurulum/2026-09-18-bar-a1-guvenlik.sql
--
-- Tek islem olarak uygulanir (sql-uygula.ps1 --single-transaction). Hata
-- olursa hicbir sey kalmaz.
--
-- NE DEGISIR (ozet):
--  * Ucretli sipariste fiyat anlik goruntusu, oda zorunlulugu, guncel konaklama;
--    iki kanalda da siparis 'bekliyor' baslar; personel ACIK beyanla dogrular,
--    dogrulayan kaydedilir (T23).
--  * Teslim tek islem, tekil (FOR UPDATE), sessiz 0'a kirpma yok; kapali folyoda
--    yalniz YETKILI personel "servis edildi" istisnasi acar; siparis
--    'istisna_bekliyor' olur ve istisna cozulene kadar tamamlanmis sayilmaz;
--    ikinci stok dusumu / ikinci borc tekillik kisitlariyla imkansiz (T24).
--  * Iptalde kullanilan miktar 'iptal_kullanimi' olarak (zayi DEGIL) nedeniyle
--    kaydedilir (T24).
--  * Stok cikis korumasi (rezerve stok baska cikisla tuketilemez) + danisma
--    kilidi; sayim sunucuda, celisen kalem bekler ve DELTA olarak uygulanir (T25).
--  * Siparis/kalem/rezervasyon tablolarina dogrudan yazma kapatilir: tum yazmalar
--    SECURITY DEFINER RPC'lerden gecer.
--  * stok_ekle / stok_transfer yeniden tanimlanir ve 2026-09-18 tarih
--    duzeltmesini TASIR (tasarim 3.5.1).
-- ============================================================================

-- @append-only: bar_stok_tuketimleri

-- ============================================================================
-- 0) ONKOSULLAR — yerini alacagimiz fonksiyonlar olculen halde mi?
-- ----------------------------------------------------------------------------
-- md5 degerleri: stok RPC'leri 2026-09-18 uretim olcumu (yayin T1); bar
-- fonksiyonlari 2026-09-13 uretim sema dokumu (bar/stok fonksiyonlari o
-- tarihten beri degismedi — runbook §12-13). Farkliysa biri araya girmis
-- demektir: EZMEMEK icin dur, yeniden olc.
-- ============================================================================
do $$
declare
  v_olculen constant jsonb := '{
    "stok_ekle(text,text,text,numeric)": "43ec3cfcd28b9a8cb9e5d8b3ed03b47d",
    "stok_transfer(text,text,text,text,numeric)": "8dd27c19ac2da9629a53dae9861766ba",
    "bar_siparis_olustur(text,text,text,text,jsonb)": "69869a956520424545d8402a8ecc933e",
    "bar_siparis_durum_guncelle(uuid,bar_durum)": "c323e93044d574953cd452cde53ba736",
    "bar_siparis_teslim_et(uuid)": "202fb2660b8eb9d5d99c37c9d26cf2ab",
    "bar_siparis_iptal(uuid)": "69d1a29b0759c275d11251801c956802",
    "pms_bar_folio_koprusu()": "ae9e7f6658111467eea7dc36e18caa16",
    "pms_bar_durum_kilit()": "5c4842c42a07fc189dfcb0bfcea4d050"
  }';
  v_imza text;
  v_md5 text;
begin
  if to_regprocedure('public.stok_cikis_korumasi(text,text,numeric)') is not null then
    raise exception 'ONKOSUL: A1 zaten uygulanmis gorunuyor (stok_cikis_korumasi var). Tekrar uygulanmaz.';
  end if;
  for v_imza in select jsonb_object_keys(v_olculen) loop
    select md5(p.prosrc) into v_md5 from pg_proc p where p.oid = to_regprocedure('public.' || v_imza);
    if v_md5 is null then
      raise exception 'ONKOSUL: % bulunamadi.', v_imza;
    end if;
    if v_md5 <> v_olculen ->> v_imza then
      raise exception 'ONKOSUL: % govdesi olcumden farkli (% <> %). Ezmemek icin durduruldu.',
        v_imza, v_md5, v_olculen ->> v_imza;
    end if;
  end loop;
  -- Tasarim 3.5.1(2): tarih duzeltmesi canli olmali.
  if not (select bool_and(prosrc ~* 'guncelleme_tarihi\s*=\s*now\(\)') from pg_proc
           where pronamespace = 'public'::regnamespace and proname in ('stok_ekle', 'stok_transfer')) then
    raise exception 'ONKOSUL: stok_ekle/stok_transfer tarih duzeltmesini (2026-09-17-stok-guncelleme-tarihi.sql) tasimiyor.';
  end if;
  if to_regclass('public.pms_folyolar') is null or to_regprocedure('public.auth_yetki_var(text,text)') is null
     or to_regprocedure('public.auth_otel_erisim(text)') is null or to_regclass('public.sayim_oturumlari') is null then
    raise exception 'ONKOSUL: PMS folyo, yetki fonksiyonlari ya da sayim tablolari yok.';
  end if;
end;
$$;


-- ============================================================================
-- 1) DURUM: istisna_bekliyor
-- ----------------------------------------------------------------------------
-- Ayni islemde yeni deger KULLANILMAZ (PostgreSQL kisiti); yalniz fonksiyon
-- govdelerinde calisma aninda anilir.
-- ============================================================================
alter type public.bar_durum add value if not exists 'istisna_bekliyor' after 'hazir';


-- ============================================================================
-- 2) SIPARIS ve KALEM SUTUNLARI + GECIS
-- ============================================================================
alter table public.bar_siparis_kalemleri
  add column birim_fiyat numeric(12,2),
  add column ucretli boolean;

-- Gecis: tarihsel fiyat bilinmez; guncel menu fiyatiyla doldurulur (tasarim 3.1).
update public.bar_siparis_kalemleri k
   set birim_fiyat = coalesce(m.fiyat, 0), ucretli = m.ucretli
  from public.menu_urunler m
 where m.id = k.menu_urun_id;

alter table public.bar_siparis_kalemleri
  alter column birim_fiyat set not null,
  alter column ucretli set not null,
  add constraint bar_siparis_kalemleri_fiyat_chk check (birim_fiyat >= 0);

alter table public.bar_siparisleri
  add column kanal text,
  add column oda_dogrulama_durumu text,
  add column rezervasyon_id uuid,
  add column folio_id uuid,
  add column dogrulayan uuid,
  add column dogrulama_zamani timestamptz,
  add column dogrulama_beyani text,
  add column iptal_nedeni text,
  add column iptal_eden uuid,
  add column iptal_zamani timestamptz;

-- Gecis: acik ve ucretli eski siparisler dogrulama bekler; kapanmislar 'gecis'.
update public.bar_siparisleri s
   set kanal = 'gecis',
       oda_dogrulama_durumu = case
         when not exists (select 1 from public.bar_siparis_kalemleri k where k.siparis_id = s.id and k.ucretli)
           then 'gerekmiyor'
         when s.durum in ('yeni', 'hazirlaniyor', 'hazir') then 'bekliyor'
         else 'gecis' end;

alter table public.bar_siparisleri
  alter column kanal set not null,
  alter column oda_dogrulama_durumu set not null,
  add constraint bar_siparisleri_kanal_chk check (kanal in ('qr', 'personel', 'gecis')),
  add constraint bar_siparisleri_dogrulama_chk check
    (oda_dogrulama_durumu in ('gerekmiyor', 'bekliyor', 'dogrulandi', 'reddedildi', 'gecis')),
  add constraint bar_siparisleri_dogrulandi_bag_chk check
    (oda_dogrulama_durumu <> 'dogrulandi'
     or (dogrulayan is not null and dogrulama_zamani is not null
         and dogrulama_beyani is not null and folio_id is not null));

do $$
begin
  raise notice 'GECIS: % kalem guncel fiyatla dolduruldu; % acik ucretli siparis dogrulama bekliyor.',
    (select count(*) from public.bar_siparis_kalemleri),
    (select count(*) from public.bar_siparisleri where oda_dogrulama_durumu = 'bekliyor');
end;
$$;


-- ============================================================================
-- 3) YENI TABLOLAR
-- ============================================================================

-- 3.1 Stok tuketimleri (append-only). Aşama 2 ikmal taslaginin kaynagi.
-- Operasyon gunu A1'de YAZILMAZ (tasarim 3.3).
create table public.bar_stok_tuketimleri (
  id               uuid primary key default gen_random_uuid(),
  otel_id          public.otel_id not null,
  bar_depo_id      text not null,
  siparis_id       uuid not null references public.bar_siparisleri(id),
  siparis_kalem_id uuid not null references public.bar_siparis_kalemleri(id),
  rezervasyon_id   uuid not null unique references public.stok_rezervasyonlari(id),
  stok_kodu        text not null,
  miktar           numeric(12,3) not null check (miktar > 0),
  tur              text not null check (tur in ('satis', 'iptal_kullanimi')),
  kullanim_nedeni  text check (kullanim_nedeni in
                     ('hazirlandi_servis_edilmedi', 'dokuldu_kirildi', 'misafir_iade', 'diger')),
  aciklama         text,
  zaman            timestamptz not null default now(),
  personel         uuid,
  constraint bar_stok_tuketimleri_neden_chk check (
    (tur = 'satis' and kullanim_nedeni is null)
    or (tur = 'iptal_kullanimi' and kullanim_nedeni is not null
        and (kullanim_nedeni <> 'diger' or nullif(btrim(aciklama), '') is not null)))
);
create index bar_stok_tuketimleri_siparis_idx on public.bar_stok_tuketimleri (siparis_id);

create or replace function public.bar_stok_tuketimleri_degismez()
returns trigger
language plpgsql
set search_path = pg_catalog, public, pg_temp
as $$
begin
  raise exception 'DEGISMEZ_KAYIT: bar_stok_tuketimleri yalniz eklenir (guncelleme/silme yok)'
    using errcode = '42501';
end;
$$;
create trigger bar_stok_tuketimleri_degismez before update or delete
  on public.bar_stok_tuketimleri for each row execute function public.bar_stok_tuketimleri_degismez();

alter table public.bar_stok_tuketimleri enable row level security;
revoke all on table public.bar_stok_tuketimleri from public, anon, authenticated;
grant select on public.bar_stok_tuketimleri to authenticated;
grant select on public.bar_stok_tuketimleri to service_role;
create policy bar_tuketim_select on public.bar_stok_tuketimleri for select to authenticated
  using (public.auth_yetki_var('bar_siparis_yonetimi', 'goruntule') is true
         and public.auth_otel_erisim(otel_id::text) is true);

-- 3.2 Borc istisnalari: kapali folyoda servis edilen ucretli siparis.
create table public.bar_borc_istisnalari (
  id                  uuid primary key default gen_random_uuid(),
  otel_id             public.otel_id not null,
  siparis_id          uuid not null unique references public.bar_siparisleri(id),
  oda_no              text,
  tutar               numeric(12,2) not null check (tutar > 0),
  eski_folio_id       uuid,
  eski_rezervasyon_id uuid,
  beyan_veren         uuid not null,
  beyan_zamani        timestamptz not null default now(),
  beyan_metni         text not null,
  durum               text not null default 'acik'
                        check (durum in ('acik', 'folyoya_yazildi', 'tahsil_edilemedi')),
  cozen               uuid,
  cozum_zamani        timestamptz,
  hedef_folio_id      uuid,
  cozum_notu          text,
  constraint bar_borc_istisnalari_cozum_chk check (
    (durum = 'acik' and cozen is null and cozum_zamani is null)
    or (durum = 'folyoya_yazildi' and cozen is not null and hedef_folio_id is not null)
    or (durum = 'tahsil_edilemedi' and cozen is not null and nullif(btrim(cozum_notu), '') is not null))
);

alter table public.bar_borc_istisnalari enable row level security;
revoke all on table public.bar_borc_istisnalari from public, anon, authenticated;
grant select on public.bar_borc_istisnalari to authenticated;
grant select on public.bar_borc_istisnalari to service_role;
create policy bar_istisna_select on public.bar_borc_istisnalari for select to authenticated
  using ((public.auth_yetki_var('bar_siparis_yonetimi', 'goruntule') is true
          or public.auth_yetki_var('pms_folio', 'goruntule') is true)
         and public.auth_otel_erisim(otel_id::text) is true);

-- 3.3 Sayim bekleyen duzeltmeleri: rezervasyonla celisen kalemin FARKI (delta).
create table public.stok_sayim_bekleyenleri (
  id                   uuid primary key default gen_random_uuid(),
  oturum_id            uuid not null,
  detay_id             uuid not null unique,
  otel_id              public.otel_id not null,
  depo_kodu            text not null,
  urun_kodu            text not null,
  sayilan_miktar       numeric(12,3) not null,
  onay_anindaki_stok   numeric(12,3) not null,
  onay_anindaki_rezerve numeric(12,3) not null,
  fark                 numeric(12,3) not null check (fark < 0),
  durum                text not null default 'bekliyor' check (durum in ('bekliyor', 'uygulandi', 'iptal')),
  olusturan            uuid,
  olusturma_zamani     timestamptz not null default now(),
  karar_veren          uuid,
  karar_zamani         timestamptz,
  uygulama_oncesi_stok numeric(12,3),
  iptal_nedeni         text,
  constraint stok_sayim_bekleyenleri_karar_chk check (
    (durum = 'bekliyor' and karar_veren is null)
    or (durum = 'uygulandi' and karar_veren is not null and uygulama_oncesi_stok is not null)
    or (durum = 'iptal' and karar_veren is not null and nullif(btrim(iptal_nedeni), '') is not null))
);
create index stok_sayim_bekleyenleri_oturum_idx on public.stok_sayim_bekleyenleri (oturum_id);

alter table public.stok_sayim_bekleyenleri enable row level security;
revoke all on table public.stok_sayim_bekleyenleri from public, anon, authenticated;
grant select on public.stok_sayim_bekleyenleri to authenticated;
grant select on public.stok_sayim_bekleyenleri to service_role;
create policy sayim_bekleyen_select on public.stok_sayim_bekleyenleri for select to authenticated
  using (public.auth_yetki_var('stok_takip', 'goruntule') is true
         and public.auth_otel_erisim(otel_id::text) is true);

-- Kalem bazinda uygulama sonucu (ekranda kismi uygulama gorunsun — T25).
alter table public.sayim_detaylari
  add column uygulama_durumu text
    check (uygulama_durumu in ('uygulandi', 'fark_yok', 'bekliyor', 'sonradan_uygulandi', 'iptal'));


-- ============================================================================
-- 4) SIPARIS TABLOLARINA DOGRUDAN YAZMA KAPATILIR
-- ----------------------------------------------------------------------------
-- Olculdu (2026-09-18): authenticated bu tablolarda ALL hakkina ve bar 'kayit'
-- yazma politikalarina sahipti; bar personeli RPC'leri atlayip durumu
-- 'teslim_edildi' yapabilir (stok dusmeden borc), dogrulama alanlarini ve kalem
-- fiyatini degistirebilirdi. Hicbir ekran bu tablolara dogrudan yazmiyor
-- (kod taramasi). Okuma aynen kalir.
-- ============================================================================
revoke all on table public.bar_siparisleri, public.bar_siparis_kalemleri, public.stok_rezervasyonlari
  from public, anon;
revoke insert, update, delete, truncate, references, trigger
  on table public.bar_siparisleri, public.bar_siparis_kalemleri, public.stok_rezervasyonlari
  from authenticated;
drop policy if exists siparis_write on public.bar_siparisleri;
drop policy if exists kalem_write on public.bar_siparis_kalemleri;
drop policy if exists rez_write on public.stok_rezervasyonlari;


-- ============================================================================
-- 5) KILIT ve STOK CIKIS KORUMASI (tasarim 3.4, 3.5)
-- ============================================================================
-- Tek anahtar sozlesmesi: 'stok:<depo>:<stok_kodu>'. Rezervasyon, teslim,
-- iptal kullanimi, sayim ve TUM stok cikislari ayni kilidi alir.
create or replace function public._stok_kilitle(p_depo_kodu text, p_stok_kodu text)
returns void
language plpgsql security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  perform pg_advisory_xact_lock(hashtextextended('stok:' || p_depo_kodu || ':' || p_stok_kodu, 0));
end;
$$;

-- SECURITY DEFINER ZORUNLU (Z1): stok_rezervasyonlari bar yetkisi isteyen RLS'e
-- tabidir; cagiranin haklariyla calisirsa depo kullanicisi rezervasyonu goremez,
-- toplami 0 okur ve koruma sessizce devre disi kalir.
create or replace function public.stok_cikis_korumasi(p_depo_kodu text, p_stok_kodu text, p_cikis numeric)
returns void
language plpgsql security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_rezerve numeric;
  v_mevcut numeric;
begin
  if p_cikis is null or p_cikis <= 0 then
    return;
  end if;
  perform public._stok_kilitle(p_depo_kodu, p_stok_kodu);

  select coalesce(sum(r.miktar), 0) into v_rezerve
    from public.stok_rezervasyonlari r
   where r.depo_id = p_depo_kodu and r.stok_kodu = p_stok_kodu and r.durum = 'aktif';
  if v_rezerve = 0 then
    return;   -- rezervasyon yoksa davranis BUGUNKUYLE AYNI
  end if;

  if auth.uid() is not null and not (public.auth_otel_erisim(split_part(p_depo_kodu, '_', 1)) is true) then
    raise exception 'OTEL_ERISIMI_YOK: % deposuna erisiminiz yok', p_depo_kodu;
  end if;

  select s.miktar into v_mevcut
    from public.stok s
   where s.urun_kodu = p_stok_kodu and s.depo_kodu = p_depo_kodu;
  if coalesce(v_mevcut, 0) - p_cikis < v_rezerve then
    raise exception 'REZERVE_STOK: % / % icin % birim bekleyen bar siparislerine ayrilmis (mevcut %, cikis %)',
      p_depo_kodu, p_stok_kodu, v_rezerve, coalesce(v_mevcut, 0), p_cikis;
  end if;
end;
$$;

-- Bar icin stok dusumu: yeterlilik ZORUNLU (sessiz 0'a kirpma yok), tarih ve
-- hareket kaydi yazilir. Cagiran kilidi almis olmalidir.
create or replace function public._bar_stok_dus(p_otel_id public.otel_id, p_depo_kodu text, p_stok_kodu text,
                                                p_miktar numeric, p_aciklama text)
returns void
language plpgsql security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  update public.stok
     set miktar = miktar - p_miktar,
         guncelleme_tarihi = now()
   where urun_kodu = p_stok_kodu and depo_kodu = p_depo_kodu and miktar >= p_miktar;
  if not found then
    raise exception 'STOK_TUTARSIZ: % / % stokta % birim yok (kayitli miktar yetersiz); sayim gerekli',
      p_depo_kodu, p_stok_kodu, p_miktar;
  end if;
  insert into public.stok_hareketleri (urun_kodu, depo_kodu, otel_id, tip, miktar, aciklama)
  values (p_stok_kodu, p_depo_kodu, p_otel_id, 'cikis', p_miktar, p_aciklama);
end;
$$;


-- ============================================================================
-- 6) stok_ekle / stok_transfer — koruma + TARIH DUZELTMESI (tasarim 3.5.1)
-- ============================================================================
create or replace function public.stok_ekle(p_urun_kodu text, p_depo_kodu text, p_otel_id text, p_delta numeric)
returns numeric
language plpgsql
set search_path to 'pg_catalog', 'public', 'extensions', 'pg_temp'
as $function$
declare
  v_yeni numeric;
begin
  if p_delta < 0 then
    perform public.stok_cikis_korumasi(p_depo_kodu, p_urun_kodu, -p_delta);
  end if;
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
  perform public.stok_cikis_korumasi(p_kaynak_depo, p_urun_kodu, p_miktar);
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


-- ============================================================================
-- 7) KONAKLAMA COZUMU (ic yardimci)
-- ============================================================================
-- Guncel konaklama: aktif oda atamasi + 'giris_yapildi' rezervasyon + acik folyo.
create or replace function public._bar_konaklama_bul(p_otel_id text, p_oda_no text,
                                                     out rezervasyon_id uuid, out folio_id uuid)
language plpgsql stable security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  select r.id, f.id into rezervasyon_id, folio_id
    from public.pms_odalar o
    join public.pms_oda_atamalari a on a.oda_id = o.id and a.otel_id = o.otel_id and a.aktif
    join public.pms_rezervasyonlar r on r.id = a.rezervasyon_id and r.otel_id = a.otel_id
                                    and r.durum = 'giris_yapildi'
    join public.pms_folyolar f on f.rezervasyon_id = r.id and f.otel_id = r.otel_id and f.durum = 'acik'
   where o.otel_id::text = p_otel_id and upper(o.oda_no) = upper(btrim(p_oda_no))
   order by f.acilis_zamani
   limit 1;
end;
$$;

-- Bagli folyo hala acik ve konaklama suruyor mu?
create or replace function public._bar_folyo_gecerli(p_folio_id uuid, p_rezervasyon_id uuid)
returns boolean
language sql stable security definer
set search_path = pg_catalog, public, pg_temp
as $$
  select exists (
    select 1 from public.pms_folyolar f
      join public.pms_rezervasyonlar r on r.id = f.rezervasyon_id and r.otel_id = f.otel_id
     where f.id = p_folio_id and f.rezervasyon_id = p_rezervasyon_id
       and f.durum = 'acik' and r.durum = 'giris_yapildi');
$$;


-- ============================================================================
-- 8) SIPARIS OLUSTURMA (tasarim 3.1, 3.2, 3.4, 3.7) — imza degismez
-- ============================================================================
-- Iki cagri yolu: musteri QR (Edge Function 'hyper-api', service_role, auth.uid
-- bos) ve personel (bar-garson.html, JWT). Her ucretli kalemde istemci GORDUGU
-- fiyati 'gosterilen_fiyat' ile yollar; farkliysa FIYAT_DEGISTI.
create or replace function public.bar_siparis_olustur(p_otel_id text, p_depo_id text, p_masa_token text,
                                                      p_oda_no text, p_kalemler jsonb)
returns uuid
language plpgsql security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_siparis_id uuid;
  v_kalem jsonb;
  v_menu public.menu_urunler%rowtype;
  v_kalem_id uuid;
  v_ucretli_var boolean := false;
  v_konak record;
  v_ihtiyac record;
  v_musait numeric;
  v_gosterilen numeric;
  v_adet numeric;
begin
  if p_kalemler is null or jsonb_typeof(p_kalemler) <> 'array' or jsonb_array_length(p_kalemler) = 0 then
    raise exception 'BOS_SIPARIS: en az bir kalem gerekli';
  end if;
  if p_otel_id is null or p_depo_id is null or split_part(p_depo_id, '_', 1) <> p_otel_id then
    raise exception 'DEPO_OTEL_UYUSMAZ: % deposu % oteline ait degil', p_depo_id, p_otel_id;
  end if;
  if auth.uid() is not null then
    if not (public.auth_yetki_var('bar_siparis_yonetimi', 'kayit') is true) then
      raise exception 'YETKI_YOK: bar_siparis_yonetimi kayit gerekli';
    end if;
    if not (public.auth_otel_erisim(p_otel_id) is true) then
      raise exception 'OTEL_ERISIMI_YOK: bu otel icin siparis olusturamazsiniz';
    end if;
  end if;

  -- 1) Kalemleri dogrula (henuz hicbir sey yazmadan).
  for v_kalem in select * from jsonb_array_elements(p_kalemler) loop
    v_adet := nullif(v_kalem ->> 'adet', '')::numeric;
    if v_adet is null or v_adet <= 0 then
      raise exception 'GECERSIZ_ADET: %', v_kalem;
    end if;
    select * into v_menu from public.menu_urunler
     where id = (v_kalem ->> 'menu_urun_id')::uuid and aktif and not silindi and otel_id = p_otel_id::otel_id;
    if not found then
      raise exception 'MENU_URUNU_YOK: % bulunamadi ya da pasif', v_kalem ->> 'menu_urun_id';
    end if;
    if v_menu.ucretli then
      v_ucretli_var := true;
      v_gosterilen := nullif(v_kalem ->> 'gosterilen_fiyat', '')::numeric;
      if v_gosterilen is null or v_gosterilen <> coalesce(v_menu.fiyat, 0) then
        raise exception 'FIYAT_DEGISTI: % icin guncel fiyat %', v_menu.ad, coalesce(v_menu.fiyat, 0);
      end if;
    end if;
  end loop;

  -- 2) Ucretli sepette oda zorunlu ve guncel konaklama olmali (T1).
  if v_ucretli_var then
    if nullif(btrim(p_oda_no), '') is null then
      raise exception 'ODA_NO_GEREKLI: ucretli sipariste oda numarasi zorunlu';
    end if;
    select * into v_konak from public._bar_konaklama_bul(p_otel_id, p_oda_no);
    if v_konak.folio_id is null then
      raise exception 'KONAKLAMA_YOK: oda % icin guncel konaklama ve acik folyo yok', p_oda_no;
    end if;
  end if;

  -- 3) Anahtarlari SIRALI kilitle, toplam ihtiyaci kontrol et (yaris: tasarim 3.4).
  for v_ihtiyac in
    with k as (
      select (e ->> 'menu_urun_id')::uuid as menu_id, (e ->> 'adet')::numeric as adet
        from jsonb_array_elements(p_kalemler) e
    ), ihtiyac as (
      select m.stok_kodu, k.adet * coalesce(m.miktar_per_porsiyon, 1) as miktar
        from k join public.menu_urunler m on m.id = k.menu_id
       where m.tip = 'direkt' and m.stok_kodu is not null
      union all
      select b.stok_kodu, k.adet * b.miktar_per_porsiyon
        from k join public.menu_urunler m on m.id = k.menu_id
        join public.recete_bilesenleri b on b.menu_urun_id = m.id
       where m.tip <> 'direkt'
    )
    select stok_kodu, sum(miktar) as miktar from ihtiyac group by stok_kodu order by stok_kodu
  loop
    perform public._stok_kilitle(p_depo_id, v_ihtiyac.stok_kodu);
    v_musait := public.bar_kullanilabilir_stok(v_ihtiyac.stok_kodu, p_depo_id);
    if v_musait < v_ihtiyac.miktar then
      raise exception 'YETERSIZ_STOK: % (gerekli %, musait %)', v_ihtiyac.stok_kodu, v_ihtiyac.miktar, v_musait;
    end if;
  end loop;

  -- 4) Yaz.
  insert into public.bar_siparisleri (otel_id, depo_id, masa_token, oda_no, durum, kanal, oda_dogrulama_durumu)
  values (p_otel_id::otel_id, p_depo_id, p_masa_token, nullif(btrim(p_oda_no), ''), 'yeni',
          case when auth.uid() is null then 'qr' else 'personel' end,
          case when v_ucretli_var then 'bekliyor' else 'gerekmiyor' end)
  returning id into v_siparis_id;

  for v_kalem in select * from jsonb_array_elements(p_kalemler) loop
    select * into v_menu from public.menu_urunler where id = (v_kalem ->> 'menu_urun_id')::uuid;
    v_adet := (v_kalem ->> 'adet')::numeric;
    insert into public.bar_siparis_kalemleri (siparis_id, menu_urun_id, adet, rezerve_edildi, birim_fiyat, ucretli)
    values (v_siparis_id, v_menu.id, v_adet, v_menu.stok_kodu is not null,   -- uretimdeki anlam aynen
            coalesce(v_menu.fiyat, 0), v_menu.ucretli)
    returning id into v_kalem_id;

    if v_menu.tip = 'direkt' then
      if v_menu.stok_kodu is not null then
        insert into public.stok_rezervasyonlari (stok_kodu, otel_id, depo_id, miktar, siparis_kalem_id, durum)
        values (v_menu.stok_kodu, p_otel_id::otel_id, p_depo_id,
                v_adet * coalesce(v_menu.miktar_per_porsiyon, 1), v_kalem_id, 'aktif');
      end if;
    else
      insert into public.stok_rezervasyonlari (stok_kodu, otel_id, depo_id, miktar, siparis_kalem_id, durum)
      select b.stok_kodu, p_otel_id::otel_id, p_depo_id, v_adet * b.miktar_per_porsiyon, v_kalem_id, 'aktif'
        from public.recete_bilesenleri b where b.menu_urun_id = v_menu.id;
    end if;
  end loop;

  return v_siparis_id;
end;
$$;


-- ============================================================================
-- 9) PERSONEL DOGRULAMASI (T23; tasarim 3.2)
-- ============================================================================
create or replace function public.bar_siparis_oda_dogrula(p_siparis_id uuid, p_beyan boolean)
returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_s public.bar_siparisleri%rowtype;
  v_konak record;
begin
  if auth.uid() is null then
    raise exception 'KIMLIK_GEREKLI: dogrulamayi yalniz personel yapar (dogrulayan kaydedilir)';
  end if;
  if not (public.auth_yetki_var('bar_siparis_yonetimi', 'kayit') is true) then
    raise exception 'YETKI_YOK: bar_siparis_yonetimi kayit gerekli';
  end if;
  select * into v_s from public.bar_siparisleri where id = p_siparis_id for update;
  if not found then
    raise exception 'SIPARIS_YOK: %', p_siparis_id;
  end if;
  if not (public.auth_otel_erisim(v_s.otel_id::text) is true) then
    raise exception 'OTEL_ERISIMI_YOK: bu siparis sizin otelinize ait degil';
  end if;
  if v_s.oda_dogrulama_durumu = 'dogrulandi' then
    return jsonb_build_object('sonuc', 'zaten_dogrulandi');
  end if;
  if v_s.oda_dogrulama_durumu <> 'bekliyor' then
    raise exception 'DOGRULAMA_GEREKMIYOR: siparisin dogrulama durumu %', v_s.oda_dogrulama_durumu;
  end if;
  if v_s.durum::text not in ('yeni', 'hazirlaniyor', 'hazir') then
    raise exception 'GECERSIZ_DURUM: % durumundaki siparis dogrulanamaz', v_s.durum;
  end if;
  if p_beyan is not true then
    raise exception 'DOGRULAMA_BEYANI_GEREKLI: misafirin oda kartini/kimligini kontrol ettiginizi onaylayin';
  end if;
  select * into v_konak from public._bar_konaklama_bul(v_s.otel_id::text, v_s.oda_no);
  if v_konak.folio_id is null then
    raise exception 'KONAKLAMA_YOK: oda % icin guncel konaklama ve acik folyo yok', v_s.oda_no;
  end if;

  update public.bar_siparisleri
     set oda_dogrulama_durumu = 'dogrulandi',
         rezervasyon_id = v_konak.rezervasyon_id,
         folio_id = v_konak.folio_id,
         dogrulayan = auth.uid(),
         dogrulama_zamani = now(),
         dogrulama_beyani = 'Misafirin oda kartini/kimligini kontrol ettim'
   where id = v_s.id;
  return jsonb_build_object('sonuc', 'dogrulandi', 'folio_id', v_konak.folio_id);
end;
$$;

create or replace function public.bar_siparis_oda_reddet(p_siparis_id uuid, p_neden text)
returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_s public.bar_siparisleri%rowtype;
begin
  if auth.uid() is null or not (public.auth_yetki_var('bar_siparis_yonetimi', 'kayit') is true) then
    raise exception 'YETKI_YOK: bar_siparis_yonetimi kayit gerekli';
  end if;
  if nullif(btrim(p_neden), '') is null then
    raise exception 'IPTAL_NEDENI_GEREKLI: ret nedeni zorunlu';
  end if;
  select * into v_s from public.bar_siparisleri where id = p_siparis_id for update;
  if not found then
    raise exception 'SIPARIS_YOK: %', p_siparis_id;
  end if;
  if not (public.auth_otel_erisim(v_s.otel_id::text) is true) then
    raise exception 'OTEL_ERISIMI_YOK: bu siparis sizin otelinize ait degil';
  end if;
  if v_s.oda_dogrulama_durumu <> 'bekliyor' or v_s.durum <> 'yeni' then
    raise exception 'GECERSIZ_DURUM: yalniz dogrulama bekleyen yeni siparis reddedilir';
  end if;
  update public.stok_rezervasyonlari r set durum = 'serbest'
    from public.bar_siparis_kalemleri k
   where k.id = r.siparis_kalem_id and k.siparis_id = v_s.id and r.durum = 'aktif';
  update public.bar_siparisleri
     set durum = 'iptal', oda_dogrulama_durumu = 'reddedildi',
         iptal_nedeni = btrim(p_neden), iptal_eden = auth.uid(), iptal_zamani = now()
   where id = v_s.id;
  return jsonb_build_object('sonuc', 'reddedildi');
end;
$$;


-- ============================================================================
-- 10) DURUM GUNCELLEME — dogrulama beklerken hazirlik yok
-- ============================================================================
create or replace function public.bar_siparis_durum_guncelle(p_siparis_id uuid, p_durum public.bar_durum)
returns void
language plpgsql security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_s public.bar_siparisleri%rowtype;
begin
  if not (public.auth_yetki_var('bar_siparis_yonetimi', 'kayit') is true) then
    raise exception 'YETKI_YOK: bar_siparis_yonetimi kayit gerekli';
  end if;
  if p_durum::text not in ('hazirlaniyor', 'hazir') then
    raise exception 'GECERSIZ_DURUM: bu fonksiyon yalniz hazirlaniyor/hazir icin — teslim/iptal ayri RPC';
  end if;
  select * into v_s from public.bar_siparisleri where id = p_siparis_id for update;
  if not found then
    raise exception 'SIPARIS_YOK: %', p_siparis_id;
  end if;
  if not (public.auth_otel_erisim(v_s.otel_id::text) is true) then
    raise exception 'OTEL_ERISIMI_YOK: bu siparis sizin otelinize ait degil';
  end if;
  if v_s.oda_dogrulama_durumu = 'bekliyor' then
    raise exception 'ODA_DOGRULAMASI_BEKLIYOR: ucretli siparis personel dogrulamasi olmadan hazirlanamaz';
  end if;
  if v_s.durum::text not in ('yeni', 'hazirlaniyor', 'hazir') then
    raise exception 'GECERSIZ_DURUM: % durumundaki siparisin hazirlik durumu degistirilemez', v_s.durum;
  end if;
  update public.bar_siparisleri set durum = p_durum where id = v_s.id;
end;
$$;


-- ============================================================================
-- 11) TESLIM (T3, T24; tasarim 3.3, O12, O13)
-- ============================================================================
drop function public.bar_siparis_teslim_et(uuid);

create function public.bar_siparis_teslim_et(p_siparis_id uuid, p_fiziksel_servis_beyani boolean default false)
returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_s public.bar_siparisleri%rowtype;
  v_rez record;
  v_tutar numeric(12,2);
  v_istisna boolean := false;
begin
  if not (public.auth_yetki_var('bar_siparis_yonetimi', 'kayit') is true) then
    raise exception 'YETKI_YOK: bar_siparis_yonetimi kayit gerekli';
  end if;
  -- Tekillik: ayni siparisin iki teslimi sirayla calisir; ikincisi 'zaten_teslim' gorur.
  select * into v_s from public.bar_siparisleri where id = p_siparis_id for update;
  if not found then
    raise exception 'SIPARIS_YOK: %', p_siparis_id;
  end if;
  if not (public.auth_otel_erisim(v_s.otel_id::text) is true) then
    raise exception 'OTEL_ERISIMI_YOK: bu siparis sizin otelinize ait degil';
  end if;
  if v_s.durum = 'teslim_edildi' then
    return jsonb_build_object('sonuc', 'zaten_teslim');
  end if;
  if v_s.durum::text = 'istisna_bekliyor' then
    return jsonb_build_object('sonuc', 'zaten_istisnali');
  end if;
  if v_s.durum <> 'hazir' then
    raise exception 'GECERSIZ_DURUM: yalniz hazir siparis teslim edilir (su an %)', v_s.durum;
  end if;
  if v_s.oda_dogrulama_durumu = 'bekliyor' then
    raise exception 'ODA_DOGRULAMASI_BEKLIYOR: ucretli siparis personel dogrulamasi olmadan teslim edilemez';
  end if;

  select coalesce(sum(k.adet * k.birim_fiyat), 0) into v_tutar
    from public.bar_siparis_kalemleri k where k.siparis_id = v_s.id and k.ucretli;

  if v_tutar > 0 and v_s.folio_id is not null
     and not public._bar_folyo_gecerli(v_s.folio_id, v_s.rezervasyon_id) then
    if p_fiziksel_servis_beyani is not true then
      raise exception 'FOLYO_KAPALI: oda % folyosu artik acik degil; urun servis edildiyse yetkili personel istisna acar', v_s.oda_no;
    end if;
    if not (public.auth_yetki_var('bar_siparis_yonetimi', 'tam') is true) then
      raise exception 'YETKI_YOK: servis edildi istisnasini yalniz yetkili (bar_siparis_yonetimi tam) personel acar';
    end if;
    v_istisna := true;
  end if;

  -- Tuketim: rezervasyon once 'kullanildi' olur (koruma kendi rezervasyonuna
  -- takilmaz), sonra stok yeterlilik zorunluluguyla duser.
  for v_rez in
    select r.* from public.stok_rezervasyonlari r
      join public.bar_siparis_kalemleri k on k.id = r.siparis_kalem_id
     where k.siparis_id = v_s.id and r.durum = 'aktif'
     order by r.stok_kodu, r.id
  loop
    perform public._stok_kilitle(v_rez.depo_id, v_rez.stok_kodu);
    update public.stok_rezervasyonlari set durum = 'kullanildi' where id = v_rez.id;
    perform public._bar_stok_dus(v_rez.otel_id, v_rez.depo_id, v_rez.stok_kodu, v_rez.miktar,
                                 'Bar satis: siparis ' || left(v_s.id::text, 8));
    insert into public.bar_stok_tuketimleri
      (otel_id, bar_depo_id, siparis_id, siparis_kalem_id, rezervasyon_id, stok_kodu, miktar, tur, personel)
    values (v_rez.otel_id, v_rez.depo_id, v_s.id, v_rez.siparis_kalem_id, v_rez.id, v_rez.stok_kodu,
            v_rez.miktar, 'satis', auth.uid());
  end loop;
  update public.bar_siparis_kalemleri set teslim_edildi = true where siparis_id = v_s.id;

  if v_istisna then
    insert into public.bar_borc_istisnalari
      (otel_id, siparis_id, oda_no, tutar, eski_folio_id, eski_rezervasyon_id, beyan_veren, beyan_metni)
    values (v_s.otel_id, v_s.id, v_s.oda_no, v_tutar, v_s.folio_id, v_s.rezervasyon_id, auth.uid(),
            'Urun misafire fiziksel olarak servis edildi (folyo kapaliyken)');
    update public.bar_siparisleri set durum = 'istisna_bekliyor' where id = v_s.id;
    return jsonb_build_object('sonuc', 'istisna_acildi', 'tutar', v_tutar);
  end if;

  update public.bar_siparisleri set durum = 'teslim_edildi' where id = v_s.id;   -- kopru borcu yazar
  return jsonb_build_object('sonuc', 'teslim_edildi', 'tutar', v_tutar);
end;
$$;


-- ============================================================================
-- 12) IPTAL (T5, T19, T24; O11)
-- ============================================================================
drop function public.bar_siparis_iptal(uuid);

create function public.bar_siparis_iptal(p_siparis_id uuid, p_neden text, p_kullanilanlar jsonb default null)
returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_s public.bar_siparisleri%rowtype;
  v_rez record;
  v_giris jsonb;
  v_kul numeric;
  v_neden text;
  v_aciklama text;
  v_aktif_sayisi int;
  v_toplam numeric := 0;
begin
  if not (public.auth_yetki_var('bar_siparis_yonetimi', 'kayit') is true) then
    raise exception 'YETKI_YOK: bar_siparis_yonetimi kayit gerekli';
  end if;
  select * into v_s from public.bar_siparisleri where id = p_siparis_id for update;
  if not found then
    raise exception 'SIPARIS_YOK: %', p_siparis_id;
  end if;
  if not (public.auth_otel_erisim(v_s.otel_id::text) is true) then
    raise exception 'OTEL_ERISIMI_YOK: bu siparis sizin otelinize ait degil';
  end if;
  if v_s.durum = 'iptal' then
    return jsonb_build_object('sonuc', 'zaten_iptal');
  end if;
  if v_s.durum::text not in ('yeni', 'hazirlaniyor', 'hazir') then
    raise exception 'GECERSIZ_DURUM: % durumundaki siparis iptal edilemez', v_s.durum;
  end if;
  if nullif(btrim(p_neden), '') is null then
    raise exception 'IPTAL_NEDENI_GEREKLI: iptal nedeni zorunlu';
  end if;
  if p_kullanilanlar is not null and jsonb_typeof(p_kullanilanlar) <> 'array' then
    raise exception 'KULLANILAN_MIKTAR_GECERSIZ: kullanilanlar bir dizi olmali';
  end if;

  if v_s.durum = 'yeni' then
    if coalesce(jsonb_array_length(p_kullanilanlar), 0) > 0 then
      raise exception 'KULLANILAN_MIKTAR_GECERSIZ: yeni siparis hazirlanmadi, kullanilan miktar girilmez';
    end if;
    update public.stok_rezervasyonlari r set durum = 'serbest'
      from public.bar_siparis_kalemleri k
     where k.id = r.siparis_kalem_id and k.siparis_id = v_s.id and r.durum = 'aktif';
  else
    -- hazirlaniyor / hazir: HER aktif rezervasyon icin acik giris zorunlu (varsayilan yok).
    select count(*) into v_aktif_sayisi
      from public.stok_rezervasyonlari r join public.bar_siparis_kalemleri k on k.id = r.siparis_kalem_id
     where k.siparis_id = v_s.id and r.durum = 'aktif';
    if v_aktif_sayisi > 0 and p_kullanilanlar is null then
      raise exception 'KULLANILAN_MIKTAR_GEREKLI: hazirlanan siparisin her bileseni icin kullanilan miktar girilir';
    end if;
    if coalesce(jsonb_array_length(p_kullanilanlar), 0) <> v_aktif_sayisi then
      raise exception 'KULLANILAN_MIKTAR_GEREKLI: % bilesen icin % giris var', v_aktif_sayisi,
        coalesce(jsonb_array_length(p_kullanilanlar), 0);
    end if;

    for v_rez in
      select r.* from public.stok_rezervasyonlari r
        join public.bar_siparis_kalemleri k on k.id = r.siparis_kalem_id
       where k.siparis_id = v_s.id and r.durum = 'aktif'
       order by r.stok_kodu, r.id
    loop
      select e.value into v_giris from jsonb_array_elements(p_kullanilanlar) e
       where e.value ->> 'rezervasyon_id' = v_rez.id::text
       limit 1;
      if v_giris is null then
        raise exception 'KULLANILAN_MIKTAR_GEREKLI: % bileseni icin giris yok', v_rez.stok_kodu;
      end if;
      v_kul := nullif(v_giris ->> 'kullanilan_miktar', '')::numeric;
      if v_kul is null or v_kul < 0 or v_kul > v_rez.miktar then
        raise exception 'KULLANILAN_MIKTAR_GECERSIZ: % icin 0 ile % arasinda olmali', v_rez.stok_kodu, v_rez.miktar;
      end if;

      if v_kul = 0 then
        update public.stok_rezervasyonlari set durum = 'serbest' where id = v_rez.id;
      else
        v_neden := v_giris ->> 'kullanim_nedeni';
        v_aciklama := nullif(btrim(v_giris ->> 'aciklama'), '');
        if v_neden is null or v_neden not in ('hazirlandi_servis_edilmedi', 'dokuldu_kirildi', 'misafir_iade', 'diger')
           or (v_neden = 'diger' and v_aciklama is null) then
          raise exception 'KULLANIM_NEDENI_GEREKLI: % icin kullanim nedeni (diger ise aciklama) zorunlu', v_rez.stok_kodu;
        end if;
        perform public._stok_kilitle(v_rez.depo_id, v_rez.stok_kodu);
        if v_kul < v_rez.miktar then
          -- Rezervasyon bolunur: kullanilan kisim tuketime baglanir, kalan serbest.
          update public.stok_rezervasyonlari set miktar = v_kul, durum = 'kullanildi' where id = v_rez.id;
          insert into public.stok_rezervasyonlari (stok_kodu, otel_id, depo_id, miktar, siparis_kalem_id, durum)
          values (v_rez.stok_kodu, v_rez.otel_id, v_rez.depo_id, v_rez.miktar - v_kul, v_rez.siparis_kalem_id, 'serbest');
        else
          update public.stok_rezervasyonlari set durum = 'kullanildi' where id = v_rez.id;
        end if;
        perform public._bar_stok_dus(v_rez.otel_id, v_rez.depo_id, v_rez.stok_kodu, v_kul,
                                     'Bar iptal kullanimi (' || v_neden || '): siparis ' || left(v_s.id::text, 8));
        insert into public.bar_stok_tuketimleri
          (otel_id, bar_depo_id, siparis_id, siparis_kalem_id, rezervasyon_id, stok_kodu, miktar, tur,
           kullanim_nedeni, aciklama, personel)
        values (v_rez.otel_id, v_rez.depo_id, v_s.id, v_rez.siparis_kalem_id, v_rez.id, v_rez.stok_kodu,
                v_kul, 'iptal_kullanimi', v_neden, v_aciklama, auth.uid());
        v_toplam := v_toplam + v_kul;
      end if;
    end loop;
  end if;

  update public.bar_siparisleri
     set durum = 'iptal', iptal_nedeni = btrim(p_neden), iptal_eden = auth.uid(), iptal_zamani = now()
   where id = v_s.id;
  return jsonb_build_object('sonuc', 'iptal', 'kullanilan_toplam', v_toplam);
end;
$$;


-- ============================================================================
-- 13) BORC ISTISNASI COZUMU (T24; O12, O13)
-- ============================================================================
create or replace function public.bar_borc_istisnasi_coz(p_istisna_id uuid, p_sonuc text,
                                                          p_hedef_folio_id uuid default null,
                                                          p_misafir_dogrulandi boolean default false,
                                                          p_not text default null)
returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_i public.bar_borc_istisnalari%rowtype;
  v_folio public.pms_folyolar%rowtype;
begin
  if auth.uid() is null or not (public.auth_yetki_var('pms_folio', 'kayit') is true) then
    raise exception 'YETKI_YOK: istisnayi yalniz pms_folio kayit yetkili personel cozer';
  end if;
  select * into v_i from public.bar_borc_istisnalari where id = p_istisna_id for update;
  if not found then
    raise exception 'ISTISNA_YOK: %', p_istisna_id;
  end if;
  if not (public.auth_otel_erisim(v_i.otel_id::text) is true) then
    raise exception 'OTEL_ERISIMI_YOK: bu istisna sizin otelinize ait degil';
  end if;
  if v_i.durum <> 'acik' then
    return jsonb_build_object('sonuc', 'zaten_cozuldu', 'durum', v_i.durum);
  end if;
  perform 1 from public.bar_siparisleri where id = v_i.siparis_id for update;

  if p_sonuc = 'folyoya_yaz' then
    if p_misafir_dogrulandi is not true then
      raise exception 'DOGRULAMA_BEYANI_GEREKLI: borc yazilacak misafir yeniden dogrulanmali';
    end if;
    select * into v_folio from public.pms_folyolar
     where id = p_hedef_folio_id and otel_id = v_i.otel_id and durum = 'acik';
    if not found then
      raise exception 'FOLYO_KAPALI: secilen folyo bu otelde acik degil';
    end if;
    insert into public.pms_folio_hareketleri (otel_id, folio_id, tip, aciklama, tutar, kaynak_tip, kaynak_id)
    values (v_folio.otel_id, v_folio.id, 'bar',
            'Bar/restoran siparisi (istisna cozumu, oda ' || coalesce(v_i.oda_no, '-') || ')',
            v_i.tutar, 'bar', v_i.siparis_id);
    update public.bar_borc_istisnalari
       set durum = 'folyoya_yazildi', cozen = auth.uid(), cozum_zamani = now(),
           hedef_folio_id = v_folio.id, cozum_notu = nullif(btrim(p_not), '')
     where id = v_i.id;
  elsif p_sonuc = 'tahsil_edilemedi' then
    if nullif(btrim(p_not), '') is null then
      raise exception 'COZUM_NOTU_GEREKLI: tahsil edilemedi kararinin gerekcesi zorunlu';
    end if;
    update public.bar_borc_istisnalari
       set durum = 'tahsil_edilemedi', cozen = auth.uid(), cozum_zamani = now(), cozum_notu = btrim(p_not)
     where id = v_i.id;
  else
    raise exception 'GECERSIZ_COZUM: folyoya_yaz ya da tahsil_edilemedi';
  end if;

  -- Siparis ancak simdi tamamlanir (T24). Kopru istisnali siparisi atlar.
  update public.bar_siparisleri set durum = 'teslim_edildi' where id = v_i.siparis_id;
  return jsonb_build_object('sonuc', p_sonuc);
end;
$$;


-- ============================================================================
-- 14) FOLYO KOPRUSU ve DURUM KILIDI (tetikleyici fonksiyonlari)
-- ============================================================================
create or replace function public.pms_bar_folio_koprusu()
returns trigger
language plpgsql security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_tutar  numeric(12,2);
  v_folio  public.pms_folyolar%rowtype;
begin
  if not (new.durum = 'teslim_edildi' and old.durum is distinct from 'teslim_edildi') then
    return null;
  end if;
  -- Istisnali siparisin borcu (varsa) cozum fonksiyonunda secilen folyoya yazilir.
  if exists (select 1 from public.bar_borc_istisnalari i where i.siparis_id = new.id) then
    return null;
  end if;

  -- Tutar SIPARIS ANINDAKI fiyattan (anlik goruntu — tasarim 3.1).
  select coalesce(sum(k.adet * k.birim_fiyat), 0) into v_tutar
    from public.bar_siparis_kalemleri k
   where k.siparis_id = new.id and k.ucretli;

  if new.oda_no is null or btrim(new.oda_no) = '' or v_tutar = 0 then
    return null;
  end if;

  if new.folio_id is not null then
    -- Dogrulamada baglanan folyo.
    select f.* into v_folio from public.pms_folyolar f where f.id = new.folio_id and f.durum = 'acik';
  else
    -- Gecis siparisleri: eski tanim (aktif atama + giris_yapildi + acik folyo).
    select f.* into v_folio
      from public.pms_odalar o
      join public.pms_oda_atamalari a on a.oda_id = o.id and a.otel_id = o.otel_id and a.aktif
      join public.pms_rezervasyonlar r on r.id = a.rezervasyon_id and r.otel_id = a.otel_id
                                      and r.durum = 'giris_yapildi'
      join public.pms_folyolar f on f.rezervasyon_id = r.id and f.otel_id = r.otel_id and f.durum = 'acik'
     where o.otel_id = new.otel_id and upper(o.oda_no) = upper(btrim(new.oda_no))
     order by f.acilis_zamani
     limit 1;
  end if;

  if not found then
    raise exception 'FOLYO_KAPALI: oda % icin acik folyo yok; oda devri yapilamaz', new.oda_no;
  end if;

  insert into public.pms_folio_hareketleri
    (otel_id, folio_id, tip, aciklama, tutar, kaynak_tip, kaynak_id)
  values (v_folio.otel_id, v_folio.id, 'bar',
          'Bar/restoran siparisi (oda ' || new.oda_no || ')',
          v_tutar, 'bar', new.id)
  on conflict do nothing;   -- ayni siparis iki kez borclandirilamaz
  return null;
end;
$$;

create or replace function public.pms_bar_durum_kilit()
returns trigger
language plpgsql
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if new.durum is not distinct from old.durum then
    return new;
  end if;
  if old.durum::text in ('teslim_edildi', 'iptal') then
    raise exception
      'Bar siparisi % durumundan cikarilamaz (son durum). Duzeltme folyoya duzeltme satiri olarak girilir',
      old.durum
      using errcode = '42501';
  end if;
  if old.durum::text = 'istisna_bekliyor' and new.durum::text <> 'teslim_edildi' then
    raise exception 'GECERSIZ_DURUM: istisna bekleyen siparis yalniz istisna cozulunce tamamlanir'
      using errcode = '42501';
  end if;
  if new.durum::text = 'istisna_bekliyor' and old.durum::text <> 'hazir' then
    raise exception 'GECERSIZ_DURUM: istisna yalniz hazir siparisin tesliminde acilir'
      using errcode = '42501';
  end if;
  return new;
end;
$$;


-- ============================================================================
-- 15) SAYIM (T22, T25; O14, O15)
-- ============================================================================
-- Ic yardimci: stoga DELTA uygular (yoksa satir acar), tarihi ve hareketi yazar.
create or replace function public._stok_delta_uygula(p_otel_id public.otel_id, p_depo_kodu text,
                                                     p_urun_kodu text, p_delta numeric, p_belge text,
                                                     p_aciklama text)
returns numeric
language plpgsql security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_yeni numeric;
begin
  insert into public.stok as s (urun_kodu, depo_kodu, otel_id, miktar)
  values (p_urun_kodu, p_depo_kodu, p_otel_id, p_delta)
  on conflict (urun_kodu, depo_kodu)
  do update set miktar = s.miktar + p_delta,
                guncelleme_tarihi = now()
  returning s.miktar into v_yeni;
  if v_yeni < 0 then
    raise exception 'STOK_TUTARSIZ: % / % sayim farki uygulaninca stok eksiye duser (%); yeni sayim gerekli',
      p_depo_kodu, p_urun_kodu, v_yeni;
  end if;
  insert into public.stok_hareketleri (urun_kodu, depo_kodu, otel_id, tip, miktar, belge_no, aciklama)
  values (p_urun_kodu, p_depo_kodu, p_otel_id, case when p_delta > 0 then 'giris' else 'cikis' end,
          abs(p_delta), p_belge, p_aciklama);
  return v_yeni;
end;
$$;

create or replace function public.stok_sayim_onayla(p_oturum_id uuid)
returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_o public.sayim_oturumlari%rowtype;
  v_otel public.otel_id;
  v_d record;
  v_mevcut numeric;
  v_rezerve numeric;
  v_fark numeric;
  v_durum text;
  v_kalemler jsonb := '[]'::jsonb;
  v_uyg int := 0; v_bek int := 0; v_yok int := 0;
  v_belge text;
begin
  if not (public.auth_yetki_var('stok_takip', 'kayit') is true) then
    raise exception 'YETKI_YOK: stok_takip kayit gerekli';
  end if;
  select * into v_o from public.sayim_oturumlari where id = p_oturum_id for update;
  if not found then
    raise exception 'SAYIM_YOK: %', p_oturum_id;
  end if;
  if not (public.auth_otel_erisim(split_part(v_o.depo_kodu, '_', 1)) is true) then
    raise exception 'OTEL_ERISIMI_YOK: bu sayim sizin otelinize ait degil';
  end if;
  if v_o.durum = 'onaylandi' then
    return jsonb_build_object('sonuc', 'zaten_onaylandi');
  end if;
  if v_o.durum <> 'onay_bekliyor' then
    raise exception 'GECERSIZ_DURUM: % durumundaki sayim onaylanamaz', v_o.durum;
  end if;
  v_otel := split_part(v_o.depo_kodu, '_', 1)::public.otel_id;
  v_belge := 'SAYIM-' || left(v_o.id::text, 8);

  for v_d in select * from public.sayim_detaylari where oturum_id = v_o.id order by urun_kodu, id loop
    perform public._stok_kilitle(v_o.depo_kodu, v_d.urun_kodu);
    select s.miktar into v_mevcut from public.stok s
     where s.urun_kodu = v_d.urun_kodu and s.depo_kodu = v_o.depo_kodu for update;
    v_mevcut := coalesce(v_mevcut, 0);
    v_fark := round(coalesce(v_d.sayilan_miktar, 0) - v_mevcut, 3);

    if v_fark = 0 then
      v_durum := 'fark_yok'; v_yok := v_yok + 1;
    else
      select coalesce(sum(r.miktar), 0) into v_rezerve from public.stok_rezervasyonlari r
       where r.depo_id = v_o.depo_kodu and r.stok_kodu = v_d.urun_kodu and r.durum = 'aktif';
      if v_fark < 0 and v_mevcut + v_fark < v_rezerve then
        -- Gozlem kaydedilir, duzeltme BEKLER (T22, T25).
        insert into public.stok_sayim_bekleyenleri
          (oturum_id, detay_id, otel_id, depo_kodu, urun_kodu, sayilan_miktar, onay_anindaki_stok,
           onay_anindaki_rezerve, fark, olusturan)
        values (v_o.id, v_d.id, v_otel, v_o.depo_kodu, v_d.urun_kodu, v_d.sayilan_miktar, v_mevcut,
                v_rezerve, v_fark, auth.uid());
        v_durum := 'bekliyor'; v_bek := v_bek + 1;
      else
        perform public._stok_delta_uygula(v_otel, v_o.depo_kodu, v_d.urun_kodu, v_fark, v_belge,
          case when v_fark > 0 then 'sayim' else 'sayim — ' || coalesce(nullif(btrim(v_d.aciklama), ''),
               'Fiziksel sayım düzeltmesi') end);
        v_durum := 'uygulandi'; v_uyg := v_uyg + 1;
      end if;
    end if;
    update public.sayim_detaylari set uygulama_durumu = v_durum where id = v_d.id;
    v_kalemler := v_kalemler || jsonb_build_object('urun_kodu', v_d.urun_kodu, 'durum', v_durum,
                                                   'sayilan', v_d.sayilan_miktar, 'onay_anindaki_stok', v_mevcut,
                                                   'fark', v_fark);
  end loop;

  update public.sayim_oturumlari
     set durum = 'onaylandi',
         onaylayan_ad = coalesce((select k.ad from public.kullanicilar k where k.auth_user_id = auth.uid() limit 1), '—'),
         onay_tarihi = now(),
         kismi_uygulandi = (v_bek > 0)
   where id = v_o.id;
  return jsonb_build_object('sonuc', 'onaylandi', 'uygulanan', v_uyg, 'bekleyen', v_bek, 'fark_yok', v_yok,
                            'kismi', v_bek > 0, 'kalemler', v_kalemler);
end;
$$;

create or replace function public.stok_sayim_bekleyen_uygula(p_bekleyen_id uuid)
returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_b public.stok_sayim_bekleyenleri%rowtype;
  v_mevcut numeric;
  v_rezerve numeric;
  v_yeni numeric;
begin
  if auth.uid() is null or not (public.auth_yetki_var('stok_takip', 'tam') is true) then
    raise exception 'YETKI_YOK: bekleyen sayim duzeltmesini yalniz stok_takip tam yetkili uygular';
  end if;
  select * into v_b from public.stok_sayim_bekleyenleri where id = p_bekleyen_id for update;
  if not found then
    raise exception 'BEKLEYEN_YOK: %', p_bekleyen_id;
  end if;
  if not (public.auth_otel_erisim(v_b.otel_id::text) is true) then
    raise exception 'OTEL_ERISIMI_YOK: bu kayit sizin otelinize ait degil';
  end if;
  if v_b.durum <> 'bekliyor' then
    return jsonb_build_object('sonuc', 'zaten_' || v_b.durum);
  end if;
  perform public._stok_kilitle(v_b.depo_kodu, v_b.urun_kodu);
  select s.miktar into v_mevcut from public.stok s
   where s.urun_kodu = v_b.urun_kodu and s.depo_kodu = v_b.depo_kodu for update;
  v_mevcut := coalesce(v_mevcut, 0);
  select coalesce(sum(r.miktar), 0) into v_rezerve from public.stok_rezervasyonlari r
   where r.depo_id = v_b.depo_kodu and r.stok_kodu = v_b.urun_kodu and r.durum = 'aktif';
  if v_mevcut + v_b.fark < v_rezerve then
    raise exception 'REZERVE_STOK: % / % icin hala % birim rezerve (mevcut %, fark %)',
      v_b.depo_kodu, v_b.urun_kodu, v_rezerve, v_mevcut, v_b.fark;
  end if;
  -- FARK (delta) o anki stoga eklenir: aradaki hareketler korunur; sayilan
  -- miktar dogrudan yazilmaz (T25).
  v_yeni := public._stok_delta_uygula(v_b.otel_id, v_b.depo_kodu, v_b.urun_kodu, v_b.fark,
                                      'SAYIM-' || left(v_b.oturum_id::text, 8),
                                      'sayim — bekleyen düzeltme sonradan uygulandı');
  update public.stok_sayim_bekleyenleri
     set durum = 'uygulandi', karar_veren = auth.uid(), karar_zamani = now(), uygulama_oncesi_stok = v_mevcut
   where id = v_b.id;
  update public.sayim_detaylari set uygulama_durumu = 'sonradan_uygulandi' where id = v_b.detay_id;
  update public.sayim_oturumlari
     set kismi_uygulandi = exists (select 1 from public.stok_sayim_bekleyenleri x
                                    where x.oturum_id = v_b.oturum_id and x.durum = 'bekliyor')
   where id = v_b.oturum_id;
  return jsonb_build_object('sonuc', 'uygulandi', 'onceki_stok', v_mevcut, 'yeni_stok', v_yeni);
end;
$$;

create or replace function public.stok_sayim_bekleyen_iptal(p_bekleyen_id uuid, p_neden text)
returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_b public.stok_sayim_bekleyenleri%rowtype;
begin
  if auth.uid() is null or not (public.auth_yetki_var('stok_takip', 'tam') is true) then
    raise exception 'YETKI_YOK: bekleyen sayim duzeltmesini yalniz stok_takip tam yetkili iptal eder';
  end if;
  if nullif(btrim(p_neden), '') is null then
    raise exception 'IPTAL_NEDENI_GEREKLI: iptal nedeni zorunlu';
  end if;
  select * into v_b from public.stok_sayim_bekleyenleri where id = p_bekleyen_id for update;
  if not found then
    raise exception 'BEKLEYEN_YOK: %', p_bekleyen_id;
  end if;
  if not (public.auth_otel_erisim(v_b.otel_id::text) is true) then
    raise exception 'OTEL_ERISIMI_YOK: bu kayit sizin otelinize ait degil';
  end if;
  if v_b.durum <> 'bekliyor' then
    return jsonb_build_object('sonuc', 'zaten_' || v_b.durum);
  end if;
  update public.stok_sayim_bekleyenleri
     set durum = 'iptal', karar_veren = auth.uid(), karar_zamani = now(), iptal_nedeni = btrim(p_neden)
   where id = v_b.id;
  update public.sayim_detaylari set uygulama_durumu = 'iptal' where id = v_b.detay_id;
  update public.sayim_oturumlari
     set kismi_uygulandi = exists (select 1 from public.stok_sayim_bekleyenleri x
                                    where x.oturum_id = v_b.oturum_id and x.durum = 'bekliyor')
   where id = v_b.oturum_id;
  return jsonb_build_object('sonuc', 'iptal');
end;
$$;


-- ============================================================================
-- 16) MASA YONETIMI YETKI KAPSAMI (rapid-handler; tasarim 3.7)
-- ============================================================================
-- CAGIRANIN JWT'siyle calisir (SECURITY INVOKER): yetki ve otel kapsami
-- kullanicinin kendi kimligiyle hesaplanir; pasif kullanici fail-closed.
create or replace function public.bar_masa_yetki_kapsami()
returns jsonb
language sql stable
set search_path = pg_catalog, public, pg_temp
as $$
  select jsonb_build_object(
    'yetkili', auth.uid() is not null and (public.auth_yetki_var('bar_siparis_yonetimi', 'kayit') is true),
    'oteller', coalesce((select jsonb_agg(o::text order by o::text)
                           from unnest(enum_range(null::public.otel_id)) o
                          where auth.uid() is not null
                            and public.auth_yetki_var('bar_siparis_yonetimi', 'kayit') is true
                            and public.auth_otel_erisim(o::text) is true), '[]'::jsonb));
$$;


-- ============================================================================
-- 17) YETKILER — acik karar + supurge (standart bolum 2)
-- ============================================================================
-- Disa acik RPC'ler
revoke all on function public.bar_siparis_olustur(text, text, text, text, jsonb) from public, anon;
grant execute on function public.bar_siparis_olustur(text, text, text, text, jsonb) to authenticated, service_role;
revoke all on function public.bar_siparis_oda_dogrula(uuid, boolean) from public, anon;
grant execute on function public.bar_siparis_oda_dogrula(uuid, boolean) to authenticated, service_role;
revoke all on function public.bar_siparis_oda_reddet(uuid, text) from public, anon;
grant execute on function public.bar_siparis_oda_reddet(uuid, text) to authenticated, service_role;
revoke all on function public.bar_siparis_durum_guncelle(uuid, public.bar_durum) from public, anon;
grant execute on function public.bar_siparis_durum_guncelle(uuid, public.bar_durum) to authenticated, service_role;
revoke all on function public.bar_siparis_teslim_et(uuid, boolean) from public, anon;
grant execute on function public.bar_siparis_teslim_et(uuid, boolean) to authenticated, service_role;
revoke all on function public.bar_siparis_iptal(uuid, text, jsonb) from public, anon;
grant execute on function public.bar_siparis_iptal(uuid, text, jsonb) to authenticated, service_role;
revoke all on function public.bar_borc_istisnasi_coz(uuid, text, uuid, boolean, text) from public, anon;
grant execute on function public.bar_borc_istisnasi_coz(uuid, text, uuid, boolean, text) to authenticated, service_role;
revoke all on function public.stok_sayim_onayla(uuid) from public, anon;
grant execute on function public.stok_sayim_onayla(uuid) to authenticated, service_role;
revoke all on function public.stok_sayim_bekleyen_uygula(uuid) from public, anon;
grant execute on function public.stok_sayim_bekleyen_uygula(uuid) to authenticated, service_role;
revoke all on function public.stok_sayim_bekleyen_iptal(uuid, text) from public, anon;
grant execute on function public.stok_sayim_bekleyen_iptal(uuid, text) to authenticated, service_role;
revoke all on function public.bar_masa_yetki_kapsami() from public, anon;
grant execute on function public.bar_masa_yetki_kapsami() to authenticated, service_role;
revoke all on function public.stok_cikis_korumasi(text, text, numeric) from public, anon;
grant execute on function public.stok_cikis_korumasi(text, text, numeric) to authenticated, service_role;
-- stok_ekle / stok_transfer: mevcut karar aynen (2026-08-09 pentest adim 3)
revoke all on function public.stok_ekle(text, text, text, numeric) from public, anon;
grant execute on function public.stok_ekle(text, text, text, numeric) to authenticated, service_role;
revoke all on function public.stok_transfer(text, text, text, text, numeric) from public, anon;
grant execute on function public.stok_transfer(text, text, text, text, numeric) to authenticated, service_role;

-- Ic yardimcilar: kimseye acik degil (yalniz SECURITY DEFINER fonksiyonlardan)
revoke all on function public._stok_kilitle(text, text) from public, anon, authenticated, service_role;
revoke all on function public._bar_stok_dus(public.otel_id, text, text, numeric, text) from public, anon, authenticated, service_role;
revoke all on function public._bar_konaklama_bul(text, text) from public, anon, authenticated, service_role;
revoke all on function public._bar_folyo_gecerli(uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function public._stok_delta_uygula(public.otel_id, text, text, numeric, text, text) from public, anon, authenticated, service_role;

-- Supurge: YALNIZ bu migration'in dokundugu fonksiyonlarda PUBLIC/anon kapali.
-- (Genis 'stok_%' deseni kullanilmaz: 2026-09-15'te yayinlanan stok_ozet vb.
-- bu migration'in konusu degildir.)
do $$
declare v record;
begin
  for v in select p.oid::regprocedure as f
             from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
            where ns.nspname = 'public'
              and (p.proname like 'bar\_%' or p.proname like '\_bar\_%' or p.proname like '\_stok\_%'
                   or p.proname like 'pms\_bar\_%' or p.proname like 'stok\_sayim\_%'
                   or p.proname in ('stok_ekle', 'stok_transfer', 'stok_cikis_korumasi'))
  loop
    execute format('revoke all on function %s from public, anon', v.f);
  end loop;
end;
$$;


-- ============================================================================
-- 18) SON KOSULLAR
-- ============================================================================
do $$
declare
  v_f text;
begin
  -- Tarih duzeltmesi tasindi (3.5.1).
  if not (select bool_and(prosrc ~* 'guncelleme_tarihi\s*=\s*now\(\)') from pg_proc
           where pronamespace = 'public'::regnamespace
             and proname in ('stok_ekle', 'stok_transfer', '_bar_stok_dus', '_stok_delta_uygula')) then
    raise exception 'SON KOSUL: stok yazan fonksiyonlardan biri guncelleme_tarihi yazmiyor.';
  end if;
  -- Dogrudan yazma kapali.
  if has_table_privilege('authenticated', 'public.bar_siparisleri', 'UPDATE')
     or has_table_privilege('authenticated', 'public.bar_siparis_kalemleri', 'UPDATE')
     or has_table_privilege('authenticated', 'public.stok_rezervasyonlari', 'UPDATE')
     or has_table_privilege('authenticated', 'public.bar_siparisleri', 'INSERT') then
    raise exception 'SON KOSUL: siparis tablolarina dogrudan yazma hala acik.';
  end if;
  -- Anon hicbir A1 fonksiyonunu cagiramaz.
  for v_f in select p.oid::regprocedure::text from pg_proc p
              where p.pronamespace = 'public'::regnamespace
                and (p.proname like 'bar\_%' or p.proname like 'stok\_%' or p.proname like '\_bar\_%' or p.proname like '\_stok\_%')
                and has_function_privilege('anon', p.oid, 'EXECUTE') loop
    raise exception 'SON KOSUL: anon % fonksiyonunu cagirabiliyor.', v_f;
  end loop;
  -- Eski imzalar kalmadi (belirsiz cagri olmasin).
  if to_regprocedure('public.bar_siparis_teslim_et(uuid)') is not null
     or to_regprocedure('public.bar_siparis_iptal(uuid)') is not null then
    raise exception 'SON KOSUL: eski teslim/iptal imzasi duruyor.';
  end if;
  if not (select relrowsecurity from pg_class where oid = 'public.bar_stok_tuketimleri'::regclass)
     or not (select relrowsecurity from pg_class where oid = 'public.bar_borc_istisnalari'::regclass)
     or not (select relrowsecurity from pg_class where oid = 'public.stok_sayim_bekleyenleri'::regclass) then
    raise exception 'SON KOSUL: yeni tablolardan birinde RLS kapali.';
  end if;
end;
$$;
