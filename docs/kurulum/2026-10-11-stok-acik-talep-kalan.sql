-- ============================================================================
-- stok_acik_talep: ACIK TALEP = KALAN MIKTAR
-- Tasarim: docs/superpowers/specs/2026-10-11-talep-siparis-bagi-design.md §8
--
-- BU GORUNUM KATALOG TABLOLARINA KATILMAZ. Sebebi olculdu: talep miktarini
-- GUNCEL carpanla yeniden hesaplayan bir formul eski kalani bozar.
--   Referans ornek: 10 KOL talep · siparis satiri 72 KG · yazma aninda
--   12 KG/KOL -> bag 6 KOL (hedef_birim=KOL, dondurulur) -> kalan 4 KOL.
--   Carpan 24 olunca "miktar × guncel carpan − bagli" = 10×24 − 6 = 234 (YANLIS)
--
-- Bag yazilirken `hedef_birim` DONDURULUR; burada yalniz AYNI BIRIMDEKI bag
-- toplami cikarilir ve sonuclar birime gore gruplanir.
--
-- SOZLESME DEGISIKLIGI: gorunum artik `birim` kolonu dondurur. stok-takip.html
-- bununla BIRLIKTE yayinlanmalidir, yoksa farkli birimler toplanir.
--
-- 2026-10-11-stok-acik-talep-durum-filtresi.sql BILINCLE asiliyor; o dosya
-- yeniden yazilmaz (standart bolum 5).
--
-- BU DOSYA YAZILDI, URETIME UYGULANMADI.
-- ============================================================================

do $$
begin
  if to_regclass('public.stok_acik_talep') is null then
    raise exception 'ONKOSUL: stok_acik_talep gorunumu yok.';
  end if;
  if to_regclass('public.talep_siparis_baglari') is null then
    raise exception 'ONKOSUL: talep_siparis_baglari yok.';
  end if;
end;
$$;

begin;

-- BAG TOPLAMI `security definer` YARDIMCIDAN OKUNUR (bagimsiz inceleme
-- bulgusu C2; izole ortamda OLCULDU). Gorunum `security_invoker=true`
-- oldugu icin bag alt sorgusu CAGIRANIN RLS'i altinda kosuyordu:
-- `tsb_select` ve `sip_select` politikalari siparis modulu yetkisi ister,
-- gorunumun tuketicisi olan stok ekrani ise `stok_takip` + `ic_talep`
-- yetkisiyle kapilidir. Iki yetki kumesi AYNI DEGIL: siparis modulunde
-- yetkisi olmayan bir depo kullanicisi icin `bagli` daima 0 doner ve
-- "kalan miktar" sessizce "tum talep miktari"na dondu. Hata yok, uyari yok,
-- iki kullanici ayni ekranda FARKLI sayi gorur.
--
-- ATLANAN KONTROLUN YENIDEN UYGULANMASI (MY-4 dersi): yardimci definer
-- oldugu icin RLS'i atlar, bu yuzden OTEL KAPSAMI kontrolu burada ACIKCA
-- yeniden uygulanir (`auth_otel_erisim`). Fonksiyon yalniz toplam dondurur;
-- firma, fiyat, siparis numarasi gibi siparis ayrintisi SIZDIRMAZ.
create or replace function public.talep_bag_toplam()
returns table (talep_kalem_id uuid, hedef_birim text, bagli numeric)
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $fn$
  select b.talep_kalem_id, b.hedef_birim, sum(b.miktar)
    from public.talep_siparis_baglari b
    join public.siparisler s on s.siparis_no = b.siparis_no
   where s.durum <> 'iptal'
     and public.auth_otel_erisim(b.otel_id::text) is true
   group by b.talep_kalem_id, b.hedef_birim
$fn$;

-- ACL KARARI ACIKCA (standart R9 + R11)
revoke all on function public.talep_bag_toplam() from public, anon;
revoke all on function public.talep_bag_toplam() from service_role;
grant execute on function public.talep_bag_toplam() to authenticated;

-- KOLON SIRASI BILINCLI: `birim` EN SONA eklenir.
-- Olculdu: `create or replace view` kolonu ORTAYA ekleyemiyor —
--   ERROR: cannot change name of view column "talep_miktar" to "birim"
-- Yalniz SONA ekleme serbesttir. Boylece gorunum DROP edilmeden guncellenir
-- ve mevcut izinler (grant select) korunur. Istemci kolonlari ada gore
-- sectigi icin sira onemsizdir.
create or replace view public.stok_acik_talep with (security_invoker=true) as
select t.otel_id,
       tk.urun_kodu,
       sum(tk.miktar - coalesce(b.bagli, 0)) as talep_miktar,
       tk.birim
  from public.satin_alma_talep_kalemleri tk
  join public.satin_alma_talepleri t on t.id = tk.talep_id
  left join public.talep_bag_toplam() b
         on b.talep_kalem_id = tk.id and b.hedef_birim = tk.birim
 where t.durum not in ('iptal', 'reddedildi')
 group by t.otel_id, tk.urun_kodu, tk.birim
having sum(tk.miktar - coalesce(b.bagli, 0)) > 0;

-- ACL KARARI ACIKCA (standart R10): cagiran yalniz authenticated.
revoke all on public.stok_acik_talep from public, anon;
grant select on public.stok_acik_talep to authenticated;

commit;

notify pgrst, 'reload schema';

-- ============================================================================
-- DENETIM SORGUSU (kapi degil, gorunurluk) — beklenen 0 satir:
--   select b.id, b.hedef_birim, tk.birim
--     from public.talep_siparis_baglari b
--     join public.satin_alma_talep_kalemleri tk on tk.id = b.talep_kalem_id
--    where b.hedef_birim <> tk.birim;
--
-- GERI ALMA: 2026-10-11-stok-acik-talep-durum-filtresi.sql dosyasindaki
-- gorunum tanimi yeniden uygulanir (o dosya degistirilmez, yeniden kosulur).
-- UYARI: geri alinirsa kismi karsilanan talebin KALANI ekranda gorunmez.
-- ============================================================================
