-- 2026-07-28 — Madde B: ln_siparisler + excel_import_* USING(true) kapatma
--
-- SORUN: Asagidaki 3 tabloda anon key'e (giris yapmadan) tum satirlari
-- okuma/yazma/guncelleme izni veren USING(true)/WITH CHECK(true) politikalari
-- var:
--   - public.ln_siparisler          -> policy "anon_all_ln_siparisler" (ALL komutlar)
--   - public.excel_import_gecmisi   -> "allow_select"/"allow_insert"/"allow_update"
--   - public.excel_import_satirlari -> "allow_select"/"allow_insert"/"allow_update"
--
-- KOD INCELEMESI (uygulamadan onaysiz degistirme yapilmadi, yalnizca okundu):
--   1) ln_siparisler: satin-alma-siparisler.html yalnizca SELECT (satir 128) ve
--      POST upsert (?on_conflict=siparis_no, satir 150) yapiyor. DELETE cagrisi
--      YOK (repo genelinde grep edildi, tek kullanici bu dosya). Tabloda zaten
--      auth-bazli ln_select/ln_insert/ln_update politikalari var
--      (public.auth_yetki_var('siparis_takip', 'goruntule'|'kayit')) --
--      bunlar YETERLI, ln_delete EKLENMEDI (kullanilmayan bir komut icin
--      politika acmak gereksiz saldiri yuzeyi olur).
--   2) excel_import_gecmisi/satirlari: yazan tek yer ortak-excel.js
--      (excelImportGecmisiYaz()) -- ancak bu ortak yardimci fonksiyon TEK bir
--      modulun degil, 9 farkli ekranin Excel import akisindan cagriliyor:
--      stok-takip.html, urun-yonetimi.html, satin-alma-talepler.html,
--      muhasebe-butce.html, muhasebe-kur.html, muhasebe-cariler.html,
--      muhasebe-cek-senet.html, muhasebe-demirbas.html, muhasebe-hesap-plani.html.
--      Tek bir auth_yetki_var(modul) ile sinirlamak yanlis olur (8 modulden
--      birini rastgele secmek gerekir) -- bu yuzden onerilen fallback'e
--      gore AUTHENTICATED-ONLY (auth.uid() is not null) uygulaniyor. Bu,
--      ln_siparisler'deki auth_yetki_var() politikalarinin da dayandigi ayni
--      auth.uid() mekanizmasi (Faz 3 pin-girisi Edge Function JWT'si) --
--      giris yapmis herhangi bir kullanici yazabilir/okuyabilir, anon kapanir.
--      Bu tablolar zaten sadece bir DENETIM IZI (audit log) -- hicbir ekran
--      henuz bunlari GORUNTULEMIYOR (grep: SELECT cagrisi yok), sadece yaziliyor.
--
-- Calistirma: Supabase Dashboard -> SQL Editor -> bu dosyanin tamamini
-- yapistir -> Run. Sonra TEST bolumundeki sorgularla dogrulayin.
-- Geri alma: en alttaki ROLLBACK blogunu ayrica calistirin.

begin;

-- ============================================================
-- 1) ln_siparisler — anon-all politikasini kapat
-- ============================================================
drop policy if exists anon_all_ln_siparisler on public.ln_siparisler;
revoke all on public.ln_siparisler from anon;
-- ln_select/ln_insert/ln_update (auth_yetki_var bazli) DOKUNULMADI, aynen kaliyor.
-- ln_delete EKLENMEDI -- uygulama bu tablodan hic DELETE yapmiyor.

-- ============================================================
-- 2) excel_import_gecmisi — allow_* (USING true) -> authenticated-only
-- ============================================================
drop policy if exists allow_select on public.excel_import_gecmisi;
drop policy if exists allow_insert on public.excel_import_gecmisi;
drop policy if exists allow_update on public.excel_import_gecmisi;

create policy authenticated_select on public.excel_import_gecmisi
  for select using (auth.uid() is not null);
create policy authenticated_insert on public.excel_import_gecmisi
  for insert with check (auth.uid() is not null);
create policy authenticated_update on public.excel_import_gecmisi
  for update using (auth.uid() is not null) with check (auth.uid() is not null);

revoke all on public.excel_import_gecmisi from anon;

-- ============================================================
-- 3) excel_import_satirlari — allow_* (USING true) -> authenticated-only
-- ============================================================
drop policy if exists allow_select on public.excel_import_satirlari;
drop policy if exists allow_insert on public.excel_import_satirlari;
drop policy if exists allow_update on public.excel_import_satirlari;

create policy authenticated_select on public.excel_import_satirlari
  for select using (auth.uid() is not null);
create policy authenticated_insert on public.excel_import_satirlari
  for insert with check (auth.uid() is not null);
create policy authenticated_update on public.excel_import_satirlari
  for update using (auth.uid() is not null) with check (auth.uid() is not null);

revoke all on public.excel_import_satirlari from anon;

commit;

-- ============================================================
-- TEST — Supabase SQL Editor / curl ile dogrulayin:
-- ============================================================

-- a) ANON KEY ile (giris yapmadan) -- ucu de BOS/401/403 donmeli:
--    curl -s "{SB_URL}/rest/v1/ln_siparisler?select=*" -H "apikey: <ANON_KEY>" -H "Authorization: Bearer <ANON_KEY>"
--    curl -s "{SB_URL}/rest/v1/excel_import_gecmisi?select=*" -H "apikey: <ANON_KEY>" -H "Authorization: Bearer <ANON_KEY>"
--    curl -s -X POST "{SB_URL}/rest/v1/excel_import_gecmisi" -H "apikey: <ANON_KEY>" -H "Authorization: Bearer <ANON_KEY>" -H "Content-Type: application/json" -d '{"tablo_adi":"test"}'
--    Beklenen: bos dizi [] (RLS filtreledi) veya 401/403 (revoke calisti).

-- b) AUTHENTICATED (uygulamaya giris yapmis, JWT'li) akis calismali:
--    - satin-alma-siparisler.html'i acip siparis listesini goruntule (SELECT calismali).
--    - Herhangi bir Excel import ekranindan (orn. stok-takip.html) bir Excel dosyasi
--      ice aktar -> excel_import_gecmisi'nde yeni satir olustugunu dogrula:
--      select * from public.excel_import_gecmisi order by created_at desc limit 5;
--      (created_at yoksa tablonun gercek zaman damgasi sutunu ile sirala)

-- c) ln_siparisler icin auth_yetki_var uzerinden yetkisiz rol denemesi
--    (siparis_takip yetkisi olmayan bir rolle giris yapip listeyi acmaya calis)
--    -> bos donmeli/erisim reddedilmeli (mevcut ln_select politikasi zaten bunu yapiyor).

-- ============================================================
-- ROLLBACK — bir sorun cikarsa bu blogu ayrica calistirin. Hicbir veriye
-- DOKUNMAZ, yalnizca politika/grant durumunu bu script'ten ONCEKI haline
-- dondurur:
-- ============================================================
-- begin;
-- create policy anon_all_ln_siparisler on public.ln_siparisler using (true) with check (true);
-- grant all on public.ln_siparisler to anon;
--
-- drop policy if exists authenticated_select on public.excel_import_gecmisi;
-- drop policy if exists authenticated_insert on public.excel_import_gecmisi;
-- drop policy if exists authenticated_update on public.excel_import_gecmisi;
-- create policy allow_select on public.excel_import_gecmisi for select using (true);
-- create policy allow_insert on public.excel_import_gecmisi for insert with check (true);
-- create policy allow_update on public.excel_import_gecmisi for update using (true) with check (true);
-- grant all on public.excel_import_gecmisi to anon;
--
-- drop policy if exists authenticated_select on public.excel_import_satirlari;
-- drop policy if exists authenticated_insert on public.excel_import_satirlari;
-- drop policy if exists authenticated_update on public.excel_import_satirlari;
-- create policy allow_select on public.excel_import_satirlari for select using (true);
-- create policy allow_insert on public.excel_import_satirlari for insert with check (true);
-- create policy allow_update on public.excel_import_satirlari for update using (true) with check (true);
-- grant all on public.excel_import_satirlari to anon;
-- commit;
