-- 2026-08-01 — "_hepsi" (FOR ALL USING true WITH CHECK true) leftover politika temizliği
--
-- Sorun: mal_kabuller/mk_hepsi, mal_kabul_urunleri/mku_hepsi, teklif_talepleri/tt_hepsi,
-- teklif_kalemleri/tk_hepsi, teklif_fiyatlari/tf_hepsi hâlâ canlıda duruyor. Postgres RLS'te
-- permissive politikalar OR'lanır — bu yüzden bu 5 tabloda Faz 3 otel-izolasyon politikaları
-- (mk_select/mk_update, tt_select/tt_insert/tt_update) yazılmış olsa bile _hepsi tarafından
-- fiilen EZİLİYOR: herkes her satırı görüp yazabiliyor, otel izolasyonu bu 5 tabloda hiç
-- çalışmıyordu.
--
-- Bu dosya TIER 1 (bug/mantık hatası) atomik-RPC dosyasından BAĞIMSIZDIR — RPC'lere ihtiyaç
-- duymaz, sadece politika düzeltir. Deploy edildiği an mal_kabuller/RFQ otel izolasyonu
-- GERÇEKTEN etkinleşir. TIER 1 RPC dosyası (mal_kabul_kaydet / teklif_talebi_olustur) bundan
-- SONRA, ayrı bir adımda çalıştırılacak.
--
-- Sıra kritik: teklif_kalemleri ve teklif_fiyatlari üzerinde _hepsi TEK politika (başka
-- select/insert/update yok). Önce yerine geçecek tam politika seti EKLENİYOR, ancak ondan
-- SONRA _hepsi DROP ediliyor — aksi halde RLS "izin yoksa reddet" olduğundan tablo anlık
-- olarak tamamen kilitlenirdi (tek transaction içinde olduğu için dışarıdan görünmez ama
-- doğru sıra yine de zorunlu tutuluyor, olası kısmi/manuel çalıştırmalara karşı).
--
-- FK/kolon adları kullanıcı tarafından information_schema ile TEYİT EDİLDİ:
--   mal_kabul_urunleri.mk_id          -> mal_kabuller.id       (mal_kabuller.otel_id ENUM, ::text cast)
--   teklif_kalemleri.teklif_talebi_id -> teklif_talepleri.id
--   teklif_fiyatlari.teklif_kalemi_id -> teklif_kalemleri.id
--   teklif_talepleri.otel_id          TEXT (cast YOK)
--
-- Modüller (koddan doğrulandı, tahmin değil):
--   mal_kabul_form  -> mal kabul FORM girişi (mal-kabul-liste.html create akışı; koli_etiketleri
--                      ke_insert zaten bunu kullanıyor, bkz. 2026-07-30-koli-etiketleri-rls-duzelt.sql)
--   fiyat_kontrol   -> mal_kabul_urunleri select/update'in MEVCUT canlı modülü (korunuyor,
--                      değiştirilmiyor — sadece parent-otel exists AND'leniyor)
--   siparis_olustur -> teklif toplama RFQ modülü (satin-alma-teklif-toplama.html yazabilir())
--
-- Çalıştırma: Supabase Dashboard → SQL Editor → tamamını yapıştır → Run.
-- Sonra TEST bölümünü uygula (en altta).

begin;

-- ============================================================
-- 1) mal_kabuller — mk_select/mk_update DOKUNULMUYOR (zaten otel-scoped, canlı, doğrulandı).
--    Sadece mk_hepsi kaldırılıyor + eksik olan mk_insert ekleniyor.
-- ============================================================
create policy mk_insert on public.mal_kabuller
  for insert
  with check (
    public.auth_yetki_var('mal_kabul_form', 'kayit')
    and public.auth_otel_erisim(otel_id::text)
  );

drop policy if exists mk_hepsi on public.mal_kabuller;

-- ============================================================
-- 2) mal_kabul_urunleri — çocuk tablo (otel_id yok). Mevcut modül (fiyat_kontrol) KORUNUYOR,
--    sadece parent mal_kabuller üzerinden otel-scope AND'leniyor. mku_insert yeni (mal_kabul_form).
-- ============================================================
drop policy if exists mku_select on public.mal_kabul_urunleri;
create policy mku_select on public.mal_kabul_urunleri
  for select
  using (
    public.auth_yetki_var('fiyat_kontrol', 'goruntule')
    and exists (
      select 1 from public.mal_kabuller m
      where m.id = mal_kabul_urunleri.mk_id
        and public.auth_otel_erisim(m.otel_id::text)
    )
  );

drop policy if exists mku_update on public.mal_kabul_urunleri;
create policy mku_update on public.mal_kabul_urunleri
  for update
  using (
    public.auth_yetki_var('fiyat_kontrol', 'kayit')
    and exists (
      select 1 from public.mal_kabuller m
      where m.id = mal_kabul_urunleri.mk_id
        and public.auth_otel_erisim(m.otel_id::text)
    )
  )
  with check (
    public.auth_yetki_var('fiyat_kontrol', 'kayit')
    and exists (
      select 1 from public.mal_kabuller m
      where m.id = mal_kabul_urunleri.mk_id
        and public.auth_otel_erisim(m.otel_id::text)
    )
  );

create policy mku_insert on public.mal_kabul_urunleri
  for insert
  with check (
    public.auth_yetki_var('mal_kabul_form', 'kayit')
    and exists (
      select 1 from public.mal_kabuller m
      where m.id = mal_kabul_urunleri.mk_id
        and public.auth_otel_erisim(m.otel_id::text)
    )
  );

drop policy if exists mku_hepsi on public.mal_kabul_urunleri;

-- ============================================================
-- 3) teklif_talepleri — tt_select/tt_insert/tt_update DOKUNULMUYOR (zaten otel-scoped,
--    canlı, doğrulandı). Sadece tt_hepsi kaldırılıyor.
-- ============================================================
drop policy if exists tt_hepsi on public.teklif_talepleri;

-- ============================================================
-- 4) teklif_kalemleri — SADECE tk_hepsi vardı, başka politika YOK. Önce tam set ekleniyor,
--    SONRA tk_hepsi drop ediliyor (sıra kritik).
-- ============================================================
create policy tk_select on public.teklif_kalemleri
  for select
  using (
    public.auth_yetki_var('siparis_olustur', 'goruntule')
    and exists (
      select 1 from public.teklif_talepleri t
      where t.id = teklif_kalemleri.teklif_talebi_id
        and public.auth_otel_erisim(t.otel_id)
    )
  );

create policy tk_insert on public.teklif_kalemleri
  for insert
  with check (
    public.auth_yetki_var('siparis_olustur', 'kayit')
    and exists (
      select 1 from public.teklif_talepleri t
      where t.id = teklif_kalemleri.teklif_talebi_id
        and public.auth_otel_erisim(t.otel_id)
    )
  );

create policy tk_update on public.teklif_kalemleri
  for update
  using (
    public.auth_yetki_var('siparis_olustur', 'kayit')
    and exists (
      select 1 from public.teklif_talepleri t
      where t.id = teklif_kalemleri.teklif_talebi_id
        and public.auth_otel_erisim(t.otel_id)
    )
  )
  with check (
    public.auth_yetki_var('siparis_olustur', 'kayit')
    and exists (
      select 1 from public.teklif_talepleri t
      where t.id = teklif_kalemleri.teklif_talebi_id
        and public.auth_otel_erisim(t.otel_id)
    )
  );

drop policy if exists tk_hepsi on public.teklif_kalemleri;

-- ============================================================
-- 5) teklif_fiyatlari — SADECE tf_hepsi vardı, başka politika YOK. İki seviye join
--    (kalem -> talep). Önce tam set ekleniyor, SONRA tf_hepsi drop ediliyor.
-- ============================================================
create policy tf_select on public.teklif_fiyatlari
  for select
  using (
    public.auth_yetki_var('siparis_olustur', 'goruntule')
    and exists (
      select 1 from public.teklif_kalemleri k
      join public.teklif_talepleri t on t.id = k.teklif_talebi_id
      where k.id = teklif_fiyatlari.teklif_kalemi_id
        and public.auth_otel_erisim(t.otel_id)
    )
  );

create policy tf_insert on public.teklif_fiyatlari
  for insert
  with check (
    public.auth_yetki_var('siparis_olustur', 'kayit')
    and exists (
      select 1 from public.teklif_kalemleri k
      join public.teklif_talepleri t on t.id = k.teklif_talebi_id
      where k.id = teklif_fiyatlari.teklif_kalemi_id
        and public.auth_otel_erisim(t.otel_id)
    )
  );

create policy tf_update on public.teklif_fiyatlari
  for update
  using (
    public.auth_yetki_var('siparis_olustur', 'kayit')
    and exists (
      select 1 from public.teklif_kalemleri k
      join public.teklif_talepleri t on t.id = k.teklif_talebi_id
      where k.id = teklif_fiyatlari.teklif_kalemi_id
        and public.auth_otel_erisim(t.otel_id)
    )
  )
  with check (
    public.auth_yetki_var('siparis_olustur', 'kayit')
    and exists (
      select 1 from public.teklif_kalemleri k
      join public.teklif_talepleri t on t.id = k.teklif_talebi_id
      where k.id = teklif_fiyatlari.teklif_kalemi_id
        and public.auth_otel_erisim(t.otel_id)
    )
  );

drop policy if exists tf_hepsi on public.teklif_fiyatlari;

commit;
notify pgrst, 'reload schema';

-- ============================================================
-- TEST (çalıştırdıktan sonra, taze bir login ile — auth_otel_id()/auth_tum_oteller()
-- kullanıcı bazlı olduğu için SQL Editor'de değil UYGULAMA ÜZERİNDE test edilmeli):
--
-- a) Tek-otel kullanıcı (810 veya 811, tum_oteller=false):
--    - Mal Kabul Girişi: kendi oteline yeni mal kabul kaydı OLUŞTURABİLMELİ.
--    - Mal Kabul Girişi / Kalite Onayı listeleri: SADECE kendi otelinin kayıtlarını görmeli
--      (diğer otelin mal kabulleri listede hiç görünmemeli).
--    - Satın Alma / Teklif Toplama: yeni RFQ (teklif talebi) OLUŞTURABİLMELİ, kendi
--      otelinin RFQ'larını görmeli; diğer otelin RFQ'ları listede görünmemeli.
--    - Mevcut bir RFQ kalemine fiyat teklifi EKLEYEBİLMELİ (kendi oteli için).
-- b) Merkez kullanıcı (tum_oteller=true, yonetici/muhasebe_muduru):
--    - Hem 810 hem 811'in mal kabullerini ve RFQ'larını görmeli, ikisine de yazabilmeli.
-- c) Regresyon: mevcut (otel izolasyonundan önce oluşmuş) mal kabul / RFQ kayıtları hâlâ
--    doğru kullanıcılara görünüyor mu (otel_id'si boş/yanlış olan eski satır var mı diye
--    ayrıca kontrol edilebilir: select id,otel_id from mal_kabuller where otel_id is null;).
-- d) select policyname, cmd from pg_policies where tablename in
--    ('mal_kabuller','mal_kabul_urunleri','teklif_talepleri','teklif_kalemleri','teklif_fiyatlari')
--    order by tablename, policyname;
--    Beklenen: hiçbir tabloda "*_hepsi" kalmamalı.
-- ============================================================

-- ============================================================
-- ROLLBACK (gerekirse — bu migration'ın etkisini geri alır, önceki (izolasyonsuz)
-- duruma döner; mk_select/mk_update/tt_select/tt_insert/tt_update bu dosyada hiç
-- değiştirilmediği için rollback'e dahil değil):
--
-- begin;
--
-- drop policy if exists mk_insert on public.mal_kabuller;
-- create policy mk_hepsi on public.mal_kabuller for all using (true) with check (true);
--
-- drop policy if exists mku_insert on public.mal_kabul_urunleri;
-- drop policy if exists mku_select on public.mal_kabul_urunleri;
-- drop policy if exists mku_update on public.mal_kabul_urunleri;
-- create policy mku_hepsi on public.mal_kabul_urunleri for all using (true) with check (true);
--
-- create policy tt_hepsi on public.teklif_talepleri for all using (true) with check (true);
--
-- drop policy if exists tk_select on public.teklif_kalemleri;
-- drop policy if exists tk_insert on public.teklif_kalemleri;
-- drop policy if exists tk_update on public.teklif_kalemleri;
-- create policy tk_hepsi on public.teklif_kalemleri for all using (true) with check (true);
--
-- drop policy if exists tf_select on public.teklif_fiyatlari;
-- drop policy if exists tf_insert on public.teklif_fiyatlari;
-- drop policy if exists tf_update on public.teklif_fiyatlari;
-- create policy tf_hepsi on public.teklif_fiyatlari for all using (true) with check (true);
--
-- commit;
-- notify pgrst, 'reload schema';
-- ============================================================
