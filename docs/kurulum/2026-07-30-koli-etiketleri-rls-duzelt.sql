-- koli_etiketleri RLS düzeltmesi
--
-- Sorun: koli_etiketleri tablosunda RLS açık (ENABLE ROW LEVEL SECURITY) ama
-- HİÇ INSERT politikası yok. Postgres RLS varsayılan olarak "izin yoksa reddet"
-- çalıştığı için, HER rol/kullanıcı için koli_etiketleri'ne yazma denemesi
-- "new row violates row-level security policy" (42501) hatasıyla başarısız
-- oluyordu -- Mal Kabul'de "Koli Bazlı Giriş" kullanılsa bile QR etiketleri
-- hiç oluşmuyordu.
--
-- Ayrıca mevcut ke_select/ke_update politikaları sadece fiyat_kontrol
-- yetkisine bağlıydı -- ama bu tabloyu asıl okuyan/güncelleyen modüller
-- Mal Kabul (etiket oluşturma+yazdırma), Stok Takip (Manuel Çıkış okutma,
-- FEFO kontrolü, Sayım QR okutma) ve Depo Siparişi (transfer okutma) idi.
-- Yani fiyat_kontrol yetkisi olmayan bir depo/mal kabul çalışanı için bu
-- tablo baştan sona görünmez/güncellenemezdi.
--
-- Bu dosya:
--   1) Eksik INSERT politikasını ekliyor (mal_kabul_form/kayit -- koli
--      etiketleri sadece Mal Kabul'de oluşturuluyor).
--   2) ke_select'i, tabloyu gerçekten okuyan tüm modülleri kapsayacak
--      şekilde genişletiyor (fiyat_kontrol korunuyor, üstüne ekleniyor).
--   3) ke_update'i, tabloyu gerçekten güncelleyen tüm modülleri kapsayacak
--      şekilde genişletiyor (fiyat_kontrol korunuyor, üstüne ekleniyor).
--
-- Mevcut/canlı bir Supabase projesine karşı çalıştırılabilir -- hiçbir
-- tabloyu/veriyi silmiyor, sadece politika tanımlarını değiştiriyor.

begin;

-- 1) Eksik INSERT politikası
drop policy if exists ke_insert on public.koli_etiketleri;
create policy ke_insert on public.koli_etiketleri
  for insert
  with check (public.auth_yetki_var('mal_kabul_form'::text, 'kayit'::text));

-- 2) SELECT -- Mal Kabul, Stok Takip, Depo Siparişi, Fiyat Kontrolü hepsi okuyabilsin
drop policy if exists ke_select on public.koli_etiketleri;
create policy ke_select on public.koli_etiketleri
  for select
  using (
    public.auth_yetki_var('mal_kabul_form'::text, 'goruntule'::text)
    or public.auth_yetki_var('mal_kabul_kalite'::text, 'goruntule'::text)
    or public.auth_yetki_var('stok_takip'::text, 'goruntule'::text)
    or public.auth_yetki_var('depo_siparis'::text, 'goruntule'::text)
    or public.auth_yetki_var('fiyat_kontrol'::text, 'goruntule'::text)
  );

-- 3) UPDATE -- Stok Takip (çıkış işaretleme) ve Depo Siparişi (transfer) de güncelleyebilsin
drop policy if exists ke_update on public.koli_etiketleri;
create policy ke_update on public.koli_etiketleri
  for update
  using (
    public.auth_yetki_var('stok_takip'::text, 'kayit'::text)
    or public.auth_yetki_var('depo_siparis'::text, 'kayit'::text)
    or public.auth_yetki_var('fiyat_kontrol'::text, 'kayit'::text)
  )
  with check (
    public.auth_yetki_var('stok_takip'::text, 'kayit'::text)
    or public.auth_yetki_var('depo_siparis'::text, 'kayit'::text)
    or public.auth_yetki_var('fiyat_kontrol'::text, 'kayit'::text)
  );

commit;

-- Doğrulama (SQL Editor'de bu dosyadan sonra ayrıca çalıştırın):
-- select polname, cmd, qual, with_check from pg_policies where tablename='koli_etiketleri';
-- Beklenen: ke_insert (INSERT), ke_select (SELECT), ke_update (UPDATE) -- üçü de yukarıdaki tanımlarla.
