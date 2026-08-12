-- ============================================================
-- 2026-08-10 — POLİTİKA DENETİMİ SORGU 4+5 BULGUSU:
-- ALT TABLOLARDA OTEL KAPSAMI YOK (BAŞLIK KORUNUYOR, DETAY SIZIYOR)
-- ============================================================
-- 2026-07-31 otel izolasyonu 21 tabloyu kapattı ama bunların ÇOĞU "başlık"
-- tablosuydu. Detay (kalem) tablolarında otel_id kolonu YOK — kapsamları
-- üst tabloya exists(...) ile bağlanmak zorunda. Bu bağ 6 tabloda hiç
-- kurulmamış; ayrıca otel_id'si OLAN 2 tabloda da kontrol atlanmış.
--
-- SONUÇ: tek-otel bir kullanıcı, ilgili modül yetkisi varsa DİĞER OTELİN
-- fatura kalemlerini, yevmiye satırlarını, sipariş kalemlerini okuyabiliyor
-- (bazılarında yazabiliyor da). Başlıklar izole, detaylar değil.
--
-- Pentest tur 4 [3] "child-table policies" diyerek bu sınıfa işaret etmişti;
-- o turda YALNIZCA bar tarafı (bar_siparis_kalemleri, recete_bilesenleri)
-- kapatılmıştı. Bu dosya sınıfın geri kalanını kapatır.
--
-- ⚠️ PERMISSIVE POLİTİKA TUZAĞI: fatura_kalemleri ve yevmiye_kalemleri'nde
-- hem `_write (ALL)` hem ayrı insert/update/delete politikaları var.
-- PostgreSQL permissive politikaları OR'lar → BİRİNİ düzeltip diğerini
-- bırakmak hiçbir işe yaramaz. Bu yüzden her tablonun TÜM politikaları
-- yeniden yazılıyor.
--
-- ------------------------------------------------------------
-- KAPSAMA ALINANLAR (join kolonları şemadan doğrulandı)
-- ------------------------------------------------------------
--   fatura_kalemleri            -> faturalar            (fatura_id)
--   yevmiye_kalemleri           -> yevmiye_fisler       (fis_id)
--   satin_alma_talep_kalemleri  -> satin_alma_talepleri (talep_id)
--   siparis_kalemleri           -> siparisler           (siparis_no, text)
--   ic_talep_kalemleri          -> ic_talepler          (talep_id)
--   recete_kalemleri            -> receteler            (recete_id)
--   koli_etiketleri             -> kendi otel_id'si (yalnız INSERT atlanmıştı)
--   stok_rezervasyonlari        -> kendi otel_id'si (ikisi de atlanmıştı)
--
-- KAPSAM DIŞI BIRAKILANLAR (gerekçeli):
--   • amortisman_kosustu — alt tablo DEĞİL, bir çalıştırma logu
--     (donem, tarih, demirbaş sayısı, toplam tutar, çalıştıran). FK yok,
--     otel boyutu yok, grup geneli. Kapsam uygulanamaz.
--   • mal_kabul_urunleri, teklif_kalemleri, teklif_fiyatlari — ZATEN doğru
--     bağlanmış (denetimde exists(...) ile otele bağlı çıktılar).
--   • banka_kasa_hareketleri, cari_hareketler — kendi otel_id'leri var ve
--     politikaları zaten kontrol ediyor.
--   • kullanicilar (3 politika) — bilinçli karar: kullanici_yonetimi yetkisi
--     yalnız merkez rollerde, merkez zaten tum_oteller=true → kapsam no-op,
--     üstelik giriş/yetki zincirini kırma riski var.
--   • giris_kayitlari — yönetici ekranı, aynı gerekçe.
--
-- Her politikanın MEVCUT modül yetkisi mantığı AYNEN korundu; yalnızca
-- otel şartı AND'lendi.
-- ============================================================

begin;

-- ------------------------------------------------------------
-- 1) fatura_kalemleri -> faturalar (fatura_id)   [FİNANSAL]
-- ------------------------------------------------------------
drop policy if exists fk_select on public.fatura_kalemleri;
create policy fk_select on public.fatura_kalemleri for select to authenticated
  using (
    public.auth_yetki_var('fatura_giris','goruntule')
    and exists (select 1 from public.faturalar f
                where f.id = fatura_id and public.auth_otel_erisim(f.otel_id::text))
  );

drop policy if exists fk_insert on public.fatura_kalemleri;
create policy fk_insert on public.fatura_kalemleri for insert to authenticated
  with check (
    (public.auth_yetki_var('fatura_giris','kayit')
     or public.auth_yetki_var('fiyat_kontrol','kayit')
     or public.auth_yetki_var('siparis_olustur','kayit'))
    and exists (select 1 from public.faturalar f
                where f.id = fatura_id and public.auth_otel_erisim(f.otel_id::text))
  );

drop policy if exists fk_update on public.fatura_kalemleri;
create policy fk_update on public.fatura_kalemleri for update to authenticated
  using (
    (public.auth_yetki_var('fatura_giris','kayit')
     or public.auth_yetki_var('fiyat_kontrol','kayit')
     or public.auth_yetki_var('siparis_olustur','kayit'))
    and exists (select 1 from public.faturalar f
                where f.id = fatura_id and public.auth_otel_erisim(f.otel_id::text))
  )
  with check (
    (public.auth_yetki_var('fatura_giris','kayit')
     or public.auth_yetki_var('fiyat_kontrol','kayit')
     or public.auth_yetki_var('siparis_olustur','kayit'))
    and exists (select 1 from public.faturalar f
                where f.id = fatura_id and public.auth_otel_erisim(f.otel_id::text))
  );

drop policy if exists fk_delete on public.fatura_kalemleri;
create policy fk_delete on public.fatura_kalemleri for delete to authenticated
  using (
    (public.auth_yetki_var('fatura_giris','kayit')
     or public.auth_yetki_var('fiyat_kontrol','kayit')
     or public.auth_yetki_var('siparis_olustur','kayit'))
    and exists (select 1 from public.faturalar f
                where f.id = fatura_id and public.auth_otel_erisim(f.otel_id::text))
  );

-- fk_write (ALL) yukarıdaki dördünü zaten kapsıyor ve OR'landığı için
-- hepsini etkisiz kılıyordu → KALDIRILIYOR.
drop policy if exists fk_write on public.fatura_kalemleri;

-- ------------------------------------------------------------
-- 2) yevmiye_kalemleri -> yevmiye_fisler (fis_id)   [FİNANSAL]
-- ------------------------------------------------------------
drop policy if exists yk_select on public.yevmiye_kalemleri;
create policy yk_select on public.yevmiye_kalemleri for select to authenticated
  using (
    public.auth_yetki_var('yevmiye_fis_giris','goruntule')
    and exists (select 1 from public.yevmiye_fisler y
                where y.id = fis_id and public.auth_otel_erisim(y.otel_id::text))
  );

drop policy if exists yk_insert on public.yevmiye_kalemleri;
create policy yk_insert on public.yevmiye_kalemleri for insert to authenticated
  with check (
    (public.auth_yetki_var('yevmiye_fis_giris','kayit')
     or public.auth_yetki_var('yevmiye_fis_onay','kayit')
     or public.auth_yetki_var('fiyat_kontrol','kayit'))
    and exists (select 1 from public.yevmiye_fisler y
                where y.id = fis_id and public.auth_otel_erisim(y.otel_id::text))
  );

drop policy if exists yk_update on public.yevmiye_kalemleri;
create policy yk_update on public.yevmiye_kalemleri for update to authenticated
  using (
    (public.auth_yetki_var('yevmiye_fis_giris','kayit')
     or public.auth_yetki_var('yevmiye_fis_onay','kayit')
     or public.auth_yetki_var('fiyat_kontrol','kayit'))
    and exists (select 1 from public.yevmiye_fisler y
                where y.id = fis_id and public.auth_otel_erisim(y.otel_id::text))
  )
  with check (
    (public.auth_yetki_var('yevmiye_fis_giris','kayit')
     or public.auth_yetki_var('yevmiye_fis_onay','kayit')
     or public.auth_yetki_var('fiyat_kontrol','kayit'))
    and exists (select 1 from public.yevmiye_fisler y
                where y.id = fis_id and public.auth_otel_erisim(y.otel_id::text))
  );

drop policy if exists yk_delete on public.yevmiye_kalemleri;
create policy yk_delete on public.yevmiye_kalemleri for delete to authenticated
  using (
    public.auth_yetki_var('yevmiye_fis_giris','kayit')
    and exists (select 1 from public.yevmiye_fisler y
                where y.id = fis_id and public.auth_otel_erisim(y.otel_id::text))
  );

drop policy if exists yk_write on public.yevmiye_kalemleri;

-- ------------------------------------------------------------
-- 3) satin_alma_talep_kalemleri -> satin_alma_talepleri (talep_id)
-- ------------------------------------------------------------
drop policy if exists satk_select on public.satin_alma_talep_kalemleri;
create policy satk_select on public.satin_alma_talep_kalemleri for select to authenticated
  using (
    public.auth_yetki_var('ic_talep','goruntule')
    and exists (select 1 from public.satin_alma_talepleri t
                where t.id = talep_id and public.auth_otel_erisim(t.otel_id::text))
  );

drop policy if exists satk_insert on public.satin_alma_talep_kalemleri;
create policy satk_insert on public.satin_alma_talep_kalemleri for insert to authenticated
  with check (
    public.auth_yetki_var('ic_talep','kayit')
    and exists (select 1 from public.satin_alma_talepleri t
                where t.id = talep_id and public.auth_otel_erisim(t.otel_id::text))
  );

drop policy if exists satk_update on public.satin_alma_talep_kalemleri;
create policy satk_update on public.satin_alma_talep_kalemleri for update to authenticated
  using (
    public.auth_yetki_var('ic_talep','kayit')
    and exists (select 1 from public.satin_alma_talepleri t
                where t.id = talep_id and public.auth_otel_erisim(t.otel_id::text))
  )
  with check (
    public.auth_yetki_var('ic_talep','kayit')
    and exists (select 1 from public.satin_alma_talepleri t
                where t.id = talep_id and public.auth_otel_erisim(t.otel_id::text))
  );

-- ------------------------------------------------------------
-- 4) siparis_kalemleri -> siparisler (siparis_no, TEXT)
-- ------------------------------------------------------------
drop policy if exists sipk_select on public.siparis_kalemleri;
create policy sipk_select on public.siparis_kalemleri for select to authenticated
  using (
    (public.auth_yetki_var('siparis_olustur','goruntule')
     or public.auth_yetki_var('siparis_takip','goruntule'))
    and exists (select 1 from public.siparisler s
                where s.siparis_no = siparis_kalemleri.siparis_no
                  and public.auth_otel_erisim(s.otel_id::text))
  );

drop policy if exists sipk_insert on public.siparis_kalemleri;
create policy sipk_insert on public.siparis_kalemleri for insert to authenticated
  with check (
    public.auth_yetki_var('siparis_olustur','kayit')
    and exists (select 1 from public.siparisler s
                where s.siparis_no = siparis_kalemleri.siparis_no
                  and public.auth_otel_erisim(s.otel_id::text))
  );

drop policy if exists sipk_update on public.siparis_kalemleri;
create policy sipk_update on public.siparis_kalemleri for update to authenticated
  using (
    public.auth_yetki_var('siparis_olustur','kayit')
    and exists (select 1 from public.siparisler s
                where s.siparis_no = siparis_kalemleri.siparis_no
                  and public.auth_otel_erisim(s.otel_id::text))
  )
  with check (
    public.auth_yetki_var('siparis_olustur','kayit')
    and exists (select 1 from public.siparisler s
                where s.siparis_no = siparis_kalemleri.siparis_no
                  and public.auth_otel_erisim(s.otel_id::text))
  );

-- ------------------------------------------------------------
-- 5) ic_talep_kalemleri -> ic_talepler (talep_id)
-- ------------------------------------------------------------
drop policy if exists itk_select on public.ic_talep_kalemleri;
create policy itk_select on public.ic_talep_kalemleri for select to authenticated
  using (
    public.auth_yetki_var('depo_siparis','goruntule')
    and exists (select 1 from public.ic_talepler t
                where t.id = talep_id and public.auth_otel_erisim(t.otel_id::text))
  );

drop policy if exists itk_insert on public.ic_talep_kalemleri;
create policy itk_insert on public.ic_talep_kalemleri for insert to authenticated
  with check (
    public.auth_yetki_var('depo_siparis','kayit')
    and exists (select 1 from public.ic_talepler t
                where t.id = talep_id and public.auth_otel_erisim(t.otel_id::text))
  );

drop policy if exists itk_update on public.ic_talep_kalemleri;
create policy itk_update on public.ic_talep_kalemleri for update to authenticated
  using (
    public.auth_yetki_var('depo_siparis','kayit')
    and exists (select 1 from public.ic_talepler t
                where t.id = talep_id and public.auth_otel_erisim(t.otel_id::text))
  )
  with check (
    public.auth_yetki_var('depo_siparis','kayit')
    and exists (select 1 from public.ic_talepler t
                where t.id = talep_id and public.auth_otel_erisim(t.otel_id::text))
  );

-- ------------------------------------------------------------
-- 6) recete_kalemleri -> receteler (recete_id)
-- ------------------------------------------------------------
drop policy if exists rk_select on public.recete_kalemleri;
create policy rk_select on public.recete_kalemleri for select to authenticated
  using (
    public.auth_yetki_var('gunluk_tuketim','goruntule')
    and exists (select 1 from public.receteler r
                where r.id = recete_id and public.auth_otel_erisim(r.otel_id::text))
  );

drop policy if exists rk_insert on public.recete_kalemleri;
create policy rk_insert on public.recete_kalemleri for insert to authenticated
  with check (
    public.auth_yetki_var('gunluk_tuketim','kayit')
    and exists (select 1 from public.receteler r
                where r.id = recete_id and public.auth_otel_erisim(r.otel_id::text))
  );

drop policy if exists rk_delete on public.recete_kalemleri;
create policy rk_delete on public.recete_kalemleri for delete to authenticated
  using (
    public.auth_yetki_var('gunluk_tuketim','kayit')
    and exists (select 1 from public.receteler r
                where r.id = recete_id and public.auth_otel_erisim(r.otel_id::text))
  );

-- ------------------------------------------------------------
-- 7) koli_etiketleri — kendi otel_id'si var, YALNIZ INSERT atlanmıştı
-- ------------------------------------------------------------
drop policy if exists ke_insert on public.koli_etiketleri;
create policy ke_insert on public.koli_etiketleri for insert to authenticated
  with check (
    public.auth_yetki_var('mal_kabul_form','kayit')
    and public.auth_otel_erisim(otel_id)
  );

-- ------------------------------------------------------------
-- 8) stok_rezervasyonlari — kendi otel_id'si var, İKİSİ DE atlanmıştı
-- ------------------------------------------------------------
drop policy if exists rez_select on public.stok_rezervasyonlari;
create policy rez_select on public.stok_rezervasyonlari for select to authenticated
  using (
    public.auth_yetki_var('bar_siparis_yonetimi','goruntule')
    and public.auth_otel_erisim(otel_id::text)
  );

drop policy if exists rez_write on public.stok_rezervasyonlari;
create policy rez_write on public.stok_rezervasyonlari for all to authenticated
  using (
    public.auth_yetki_var('bar_siparis_yonetimi','kayit')
    and public.auth_otel_erisim(otel_id::text)
  )
  with check (
    public.auth_yetki_var('bar_siparis_yonetimi','kayit')
    and public.auth_otel_erisim(otel_id::text)
  );

commit;

notify pgrst, 'reload schema';


-- ============================================================
-- DOĞRULAMA 1 — sorgu 5 artık temiz mi (hepsi true olmalı)
-- ============================================================
-- select tablename, policyname, cmd,
--        (coalesce(qual,'')||coalesce(with_check,'')) ~* 'auth_otel_erisim' as otel_bagli
-- from pg_policies
-- where schemaname='public'
--   and tablename in ('fatura_kalemleri','yevmiye_kalemleri','satin_alma_talep_kalemleri',
--                     'siparis_kalemleri','ic_talep_kalemleri','recete_kalemleri',
--                     'koli_etiketleri','stok_rezervasyonlari')
-- order by tablename, policyname;

-- ============================================================
-- DOĞRULAMA 2 — _write (ALL) politikaları gerçekten kalktı mı (BOŞ dönmeli)
-- ============================================================
-- select tablename, policyname from pg_policies
-- where schemaname='public' and policyname in ('fk_write','yk_write');


-- ============================================================
-- UYGULAMADA TEST — bu SQL muhasebeye ve satın almaya dokunuyor
-- ============================================================
-- 1) Muhasebe > Faturalar: fatura aç, KALEMLERİ görünmeli; yeni fatura
--    kaydet, kalem düzenle, kalem sil
-- 2) Muhasebe > Yevmiye: fiş aç, SATIRLARI görünmeli; fiş kaydet/düzelt
-- 3) Satın Alma > Talepler: talep detayı kalemleri görünmeli, yeni talep
--    oluşturulabilmeli
-- 4) Satın Alma > Sipariş oluştur / Sipariş takip: kalemler görünmeli
-- 5) Depo Siparişleri: iç talep kalemleri görünmeli
-- 6) Günlük Tüketim: reçete bileşenleri görünmeli
-- 7) Mal Kabul: koli etiketi basma çalışmalı
-- 8) Bar: sipariş ver → teslim et (stok rezervasyonu akışı)
--
-- ⚠️ Herhangi bir yerde KALEMLER BOŞ geliyorsa hemen söyle — sebep
-- büyük ihtimalle join kolonu değil, üst kaydın otel_id'sinin boş olması
-- olur. Geri alma için: bu politikalardan `and exists (...)` bloğunu çıkar.
