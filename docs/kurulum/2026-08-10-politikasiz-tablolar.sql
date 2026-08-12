-- ============================================================
-- 2026-08-10 — POLİTİKA DENETİMİ SORGU 2 BULGUSU:
-- RLS AÇIK + 0 POLİTİKA = SESSİZCE ÖLÜ İKİ ÖZELLİK
-- ============================================================
-- Denetimde 7 tablo "RLS açık, politika yok" çıktı. Beşi DOĞRU durumda
-- (yalnızca SECURITY DEFINER RPC üzerinden erişiliyor, doğrudan yol kapalı):
--   sayim_oturumlari, sayim_detaylari, edefter_kurum_bilgileri,
--   edefter_sube_bilgileri, giris_denemeleri
-- ⚠️ BUNLARA POLİTİKA EKLEME — kapalı yolu açar.
--
-- Ama İKİSİ istemciden DOĞRUDAN okunuyor/yazılıyor → deny-all yüzünden
-- boş dönüyor ve yazma sessizce başarısız oluyor:
--
--   1) urun_birim_donusum  — ortak.js:135 HER SAYFADA okuyor (5 ekranda
--      "≈X KOLİ" gösterimi için), urun-yonetimi.html hem okuyor hem yazıyor.
--   2) gelen_efaturalar    — muhasebe-faturalar.html gelen e-fatura kutusu
--      (satır 444 okuma, 1330 mükerrer kontrolü, 1352 yazma).
--
-- NE ZAMANDAN BERİ: 2026-07-30 tarihli şema dökümünde de bu iki tabloda
-- `ENABLE ROW LEVEL SECURITY` var ama sıfır politika. Yani RLS dalgalarının
-- birinde RLS açılmış, politika eklenmemiş; özellikler o günden beri ölü.
-- Kimse fark etmemiş çünkü ekran hata vermiyor, sadece BOŞ geliyor —
-- stok tablo görünümünün 3 view'ıyla birebir aynı sınıf hata.
--
-- KÖK NEDEN (bilinen, hâlâ açık): şemada `rls_auto_enable()` fonksiyonu var
-- ama onu bir DDL olayına bağlayan CREATE EVENT TRIGGER YOK. "Yeni tabloda
-- RLS'i otomatik aç" güvenlik ağı kurulmuş ama hiç bağlanmamış. Bu, 2026-07-22
-- RLS denetiminde de aynı gerekçeyle işaretlenmişti.
--
-- OTEL KAPSAMI: ikisinde de otel_id kolonu YOK, dolayısıyla otel kapsamı
-- uygulanamaz. Bu bilinçli:
--   • urun_birim_donusum, urunler tablosunun uzantısı = paylaşımlı referans
--     verisi (tıpkı urunler, hesap_plani, roller gibi).
--   • gelen_efaturalar, faturaya dönüşmeden önceki ham gelen kutusu;
--     otel ataması fatura oluşturulurken yapılır ve faturalar zaten
--     otel-izole.
-- ============================================================

begin;

-- ------------------------------------------------------------
-- 1) urun_birim_donusum
-- ------------------------------------------------------------
-- OKUMA: aktif her ERP kullanıcısı. Gerekçe: bu veri ortak.js üzerinden
-- stok-takip, gunluk-tuketim, trend-raporlama, siparis-olustur ve
-- mal-kabul-liste ekranlarında sadece BİRİM ETİKETİ göstermek için okunuyor.
-- 'urun_yonetimi' modül yetkisine bağlarsak, stok yetkisi olup ürün yönetimi
-- yetkisi olmayan kullanıcılarda etiketler kaybolur. `urunler` tablosunun
-- SELECT'i 2026-08-09'da tam bu seviyeye (auth_erp_kullanicisi) çekilmişti;
-- bu tablo onun uzantısı olduğu için AYNI seviyede tutuluyor.
drop policy if exists ubd_select on public.urun_birim_donusum;
create policy ubd_select on public.urun_birim_donusum
  for select to authenticated
  using (public.auth_erp_kullanicisi());

-- YAZMA: yalnız ürün yönetimi modülü (urun-yonetimi.html ekranı).
-- İstemci upsert (on_conflict=urun_kodu) kullandığı için INSERT ve UPDATE
-- birlikte gerekli. Silme soft-delete (silindi=true) ile yapılıyor → UPDATE
-- yeterli, DELETE politikası bilerek YOK.
drop policy if exists ubd_insert on public.urun_birim_donusum;
create policy ubd_insert on public.urun_birim_donusum
  for insert to authenticated
  with check (public.auth_yetki_var('urun_yonetimi','kayit'));

drop policy if exists ubd_update on public.urun_birim_donusum;
create policy ubd_update on public.urun_birim_donusum
  for update to authenticated
  using (public.auth_yetki_var('urun_yonetimi','kayit'))
  with check (public.auth_yetki_var('urun_yonetimi','kayit'));

-- ------------------------------------------------------------
-- 2) gelen_efaturalar
-- ------------------------------------------------------------
-- Ekranın kendi yetki kontrolüyle aynı modül: muhasebe-faturalar.html
-- YETKI_HARITASI['fatura_giris'] bakıyor (satır 815, 1365).
drop policy if exists gef_select on public.gelen_efaturalar;
create policy gef_select on public.gelen_efaturalar
  for select to authenticated
  using (public.auth_yetki_var('fatura_giris','goruntule'));

drop policy if exists gef_insert on public.gelen_efaturalar;
create policy gef_insert on public.gelen_efaturalar
  for insert to authenticated
  with check (public.auth_yetki_var('fatura_giris','kayit'));

-- Gelen fatura "işlendi" olarak işaretlenir (durum + alis_fatura_id) →
-- UPDATE gerekli. Kayıt silinmiyor → DELETE politikası bilerek YOK.
drop policy if exists gef_update on public.gelen_efaturalar;
create policy gef_update on public.gelen_efaturalar
  for update to authenticated
  using (public.auth_yetki_var('fatura_giris','kayit'))
  with check (public.auth_yetki_var('fatura_giris','kayit'));

commit;

notify pgrst, 'reload schema';


-- ============================================================
-- DOĞRULAMA 1 — iki tabloda da politika oluştu mu (6 satır)
-- ============================================================
-- select tablename, policyname, cmd
-- from pg_policies
-- where schemaname='public'
--   and tablename in ('urun_birim_donusum','gelen_efaturalar')
-- order by tablename, policyname;

-- ============================================================
-- DOĞRULAMA 2 — politikasız tablo listesi 7'den 5'e inmeli
-- (kalanlar: sayim_oturumlari, sayim_detaylari, edefter_kurum_bilgileri,
--            edefter_sube_bilgileri, giris_denemeleri — hepsi DOĞRU)
-- ============================================================
-- select c.relname from pg_class c
-- join pg_namespace n on n.oid = c.relnamespace
-- where n.nspname='public' and c.relkind='r' and c.relrowsecurity=true
--   and not exists (select 1 from pg_policies p
--                   where p.schemaname='public' and p.tablename=c.relname)
-- order by 1;


-- ============================================================
-- UYGULAMADA TEST — bu iki özellik ŞU AN ÖLÜ, canlanmalı
-- ============================================================
-- 1) Stok Takip / Günlük Tüketim / Mal Kabul Listesi aç →
--    birim dönüşümü tanımlı ürünlerde "≈ X KOLİ" etiketi GÖRÜNMELİ
--    (şu ana kadar hiç görünmüyordu)
-- 2) Ürün Yönetimi ekranı → mevcut dönüşümler listelenmeli,
--    yeni dönüşüm kaydedilebilmeli
-- 3) Muhasebe > Faturalar > gelen e-fatura kutusu → liste gelmeli
--
-- ⚠️ 1. maddede etiket ÇIKMIYORSA sebep muhtemelen politika değil,
-- urun_birim_donusum tablosunun BOŞ olmasıdır (özellik ölüyken kimse
-- kayıt girememiş olabilir). Önce 2. maddeden bir kayıt gir, sonra bak.


-- ============================================================
-- AYRICA YAPILMALI (bu dosyanın kapsamı dışında)
-- ============================================================
-- rls_auto_enable() event trigger'ını gerçekten bağla. Aksi halde bir sonraki
-- yeni tablo yine RLS'siz/politikasız kalır ve bu sınıf hata tekrarlar.
-- 2026-07-22 denetiminde de aynı öneri yapılmış, uygulanmamış.
