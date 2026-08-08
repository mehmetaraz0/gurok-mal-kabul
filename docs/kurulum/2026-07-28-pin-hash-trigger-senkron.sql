-- 2026-07-28 — [3] Faz 3 sonrasi YAN-BOSLUK duzeltmesi: pin <-> pin_hash senkronu
--
-- SORUN: kullanici-yonetimi.html (kullaniciKaydet()) yalnizca `pin` sutununu
-- yaziyor, `pin_hash`'e hic dokunmuyor. Faz 3 cutover'dan (cd531d2) sonra giris
-- akisi tamamen pin_dogrula() RPC'si uzerinden `pin_hash` ile calistigi icin:
--   - UI'dan PIN degistirmek girise YANSIMIYOR (eski PIN girise devam ediyor),
--   - yeni kullanici pin_hash'siz kaliyor -> HIC giris yapamiyor.
--
-- COZUM: kullanicilar tablosuna BEFORE INSERT/UPDATE OF pin trigger'i eklenir.
-- `pin` sutunu her yazildiginda (insert her zaman, update yalnizca pin SET
-- listesindeyse) pin_hash otomatik olarak crypt(pin, gen_salt('bf')) ile
-- yeniden hesaplanir. kullanici-yonetimi.html DEGISTIRILMEZ -- mevcut PATCH/POST
-- gövdesi (yalnizca pin gonderen) oldugu gibi calismaya devam eder.
--
-- GUVENLIK ROTUSLARI (bu revizyonda eklendi):
--   1) Trigger fonksiyonu SECURITY DEFINER: crypt()/gen_salt() `extensions`
--      semasinda; PATCH'i yapan 'authenticated' rolunun bu fonksiyonlara
--      dogrudan EXECUTE yetkisi olmayabilir/ileride kisitlanabilir. DEFINER
--      (owner=postgres) ile trigger bu yetkiden bagimsiz calisir. Fonksiyon
--      yalnizca NEW.pin_hash'i hesapliyor, hicbir tabloya erismiyor -> DEFINER
--      guvenli (ayricalik yukseltme riski yok).
--   2) Bos string PIN hash'lenmez (`NEW.pin <> ''` kontrolu) -- pin_dogrula()
--      zaten char_length(p_giris)=6 sarti koyuyor, bu ek bir temizlik katmani.
--
-- Calistirma: Supabase Dashboard -> SQL Editor -> bu dosyanin tamamini
-- yapistir -> Run. Sonra asagidaki TEST bolumundeki sorgularla dogrulayin.
-- Geri alma: en alttaki ROLLBACK blogunu ayrica calistirin (mevcut
-- kullanicilar.pin / pin_hash verisine DOKUNMAZ, yalnizca trigger+fonksiyonu
-- kaldirir).

begin;

-- 0) Guvenlik payi: Faz 1'den sonra UI'dan eklenmis, pin_hash'siz kalmis
-- kullanici varsa kapat (Faz 1'deki backfill ile ayni sorgu, idempotent).
update public.kullanicilar
set pin_hash = crypt(pin, gen_salt('bf'))
where pin is not null
  and pin <> ''
  and pin_hash is null;

-- 1) Trigger fonksiyonu — SECURITY DEFINER, yalnizca NEW.pin_hash hesaplar.
create or replace function public.pin_hash_senkronize_tetikleyici()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if NEW.pin is not null and NEW.pin <> '' then
    NEW.pin_hash := crypt(NEW.pin, gen_salt('bf'));
  end if;
  return NEW;
end;
$$;

-- 2) Trigger — insert her zaman, update yalnizca `pin` SET listesindeyse tetiklenir.
drop trigger if exists tg_pin_hash_senkronize on public.kullanicilar;
create trigger tg_pin_hash_senkronize
before insert or update of pin on public.kullanicilar
for each row
execute function public.pin_hash_senkronize_tetikleyici();

commit;

-- ============================================================
-- TEST — Supabase SQL Editor'de sirayla calistirip dogrulayin:
-- ============================================================

-- a) Kalan bosluk kapandi mi? (0 donmeli)
-- select count(*) from public.kullanicilar where pin is not null and pin <> '' and pin_hash is null;

-- b) YENI KULLANICI: kullanici-yonetimi.html'den bir test kullanicisi olustur,
--    ardindan pin_hash dolu mu kontrol et (true donmeli):
-- select (pin_hash is not null) as pin_hash_doldu
-- from public.kullanicilar where ad = '<test kullanicisinin adi>';

-- c) PIN DEGISTIR: mevcut bir kullanicinin PIN'ini UI'dan degistir, sonra:
--    - ESKI PIN ile pin_dogrula 0 satir donmeli:
-- select * from public.pin_dogrula('<ESKI PIN>', 'test-ip-hash-1');
--    - YENI PIN ile pin_dogrula 1 satir donmeli:
-- select * from public.pin_dogrula('<YENI PIN>', 'test-ip-hash-1');

-- ============================================================
-- ROLLBACK — bir sorun cikarsa bu blogu ayrica calistirin. Mevcut
-- kullanicilar.pin / pin_hash verisine DOKUNMAZ, yalnizca bu script'in
-- ekledigi trigger+fonksiyonu kaldirir:
-- ============================================================
-- begin;
-- drop trigger if exists tg_pin_hash_senkronize on public.kullanicilar;
-- drop function if exists public.pin_hash_senkronize_tetikleyici();
-- commit;
