-- 2026-07-31 — Madde D / FAZ 2 PİLOT: stok + faturalar otel izolasyonu
--
-- Faz 1 (kolon+fonksiyon+merkez bayrağı) canlı olmalı. Bu script, SADECE 2 tabloda
-- (stok, faturalar) mevcut yetki politikalarına `AND auth_otel_erisim(otel_id::text)`
-- ekler → tek-otel kullanıcı yalnızca kendi otelini görür/yazar; merkez (tum_oteller)
-- hepsini. stok_ekle/stok_transfer SECURITY DEFINER DEĞİL (INVOKER) olduğundan RLS
-- yazmayı da kapsar; ek RPC değişikliği GEREKMEZ.
--
-- GERİ DÖNÜŞ: en alttaki ROLLBACK bloğu politikaları eski (otel-koşulsuz) haline döndürür.
--
-- ⚠️ ÇALIŞTIRDIKTAN SONRA MUTLAKA TEST (aşağıda) — özellikle tek-otel bir kullanıcıyla
--    giriş yapıp yalnızca kendi otelini gördüğünü doğrula. Doğrulanmadan Faz 3'e geçme.

begin;

-- ============ STOK ============
drop policy if exists yetki_select on public.stok;
create policy yetki_select on public.stok for select
  using (public.auth_yetki_var('stok_takip','goruntule') and public.auth_otel_erisim(otel_id::text));

drop policy if exists yetki_insert on public.stok;
create policy yetki_insert on public.stok for insert
  with check (public.auth_yetki_var('stok_takip','kayit') and public.auth_otel_erisim(otel_id::text));

drop policy if exists yetki_update on public.stok;
create policy yetki_update on public.stok for update
  using (public.auth_yetki_var('stok_takip','kayit') and public.auth_otel_erisim(otel_id::text))
  with check (public.auth_yetki_var('stok_takip','kayit') and public.auth_otel_erisim(otel_id::text));

-- ============ FATURALAR ============
drop policy if exists yetki_select on public.faturalar;
create policy yetki_select on public.faturalar for select
  using (public.auth_yetki_var('fatura_giris','goruntule') and public.auth_otel_erisim(otel_id::text));

drop policy if exists fat_insert on public.faturalar;
create policy fat_insert on public.faturalar for insert
  with check (
    (public.auth_yetki_var('fatura_giris','kayit') or public.auth_yetki_var('fiyat_kontrol','kayit') or public.auth_yetki_var('siparis_olustur','kayit'))
    and public.auth_otel_erisim(otel_id::text)
  );

drop policy if exists fat_update on public.faturalar;
create policy fat_update on public.faturalar for update
  using (
    (public.auth_yetki_var('fatura_giris','kayit') or public.auth_yetki_var('fiyat_kontrol','kayit') or public.auth_yetki_var('siparis_olustur','kayit'))
    and public.auth_otel_erisim(otel_id::text)
  )
  with check (
    (public.auth_yetki_var('fatura_giris','kayit') or public.auth_yetki_var('fiyat_kontrol','kayit') or public.auth_yetki_var('siparis_olustur','kayit'))
    and public.auth_otel_erisim(otel_id::text)
  );

commit;
notify pgrst, 'reload schema';

-- ============================================================
-- TEST (çalıştırdıktan HEMEN sonra):
-- 1) MERKEZ kullanıcı (sen, yonetici) → Stok Takip + Muhasebe/Faturalar aç:
--    her iki otelin verisi de görünmeli, ekleme/kaydetme çalışmalı (bozulma YOK).
-- 2) TEK-OTEL kullanıcı (810 veya 811 operasyonel; depo/mutfak) ile GİRİŞ yap →
--    Stok Takip'te YALNIZCA kendi otelinin stoğu görünmeli, diğer otel görünmemeli.
--    (Bu adım izolasyonun asıl kanıtı — atlanırsa doğrulanmış sayılmaz.)
-- 3) Tek-otel kullanıcı bir stok girişi/mal kabul yapsın → kendi oteline yazabilmeli.
-- Herhangi biri kırılırsa → ROLLBACK.
-- ============================================================
-- ROLLBACK (sorun çıkarsa bu bloğu ayrıca çalıştır — politikaları otel-koşulsuz eski
-- haline döndürür; hiçbir veriye dokunmaz):
-- begin;
-- drop policy if exists yetki_select on public.stok;
-- create policy yetki_select on public.stok for select using (public.auth_yetki_var('stok_takip','goruntule'));
-- drop policy if exists yetki_insert on public.stok;
-- create policy yetki_insert on public.stok for insert with check (public.auth_yetki_var('stok_takip','kayit'));
-- drop policy if exists yetki_update on public.stok;
-- create policy yetki_update on public.stok for update using (public.auth_yetki_var('stok_takip','kayit')) with check (public.auth_yetki_var('stok_takip','kayit'));
-- drop policy if exists yetki_select on public.faturalar;
-- create policy yetki_select on public.faturalar for select using (public.auth_yetki_var('fatura_giris','goruntule'));
-- drop policy if exists fat_insert on public.faturalar;
-- create policy fat_insert on public.faturalar for insert with check ((public.auth_yetki_var('fatura_giris','kayit') or public.auth_yetki_var('fiyat_kontrol','kayit') or public.auth_yetki_var('siparis_olustur','kayit')));
-- drop policy if exists fat_update on public.faturalar;
-- create policy fat_update on public.faturalar for update using ((public.auth_yetki_var('fatura_giris','kayit') or public.auth_yetki_var('fiyat_kontrol','kayit') or public.auth_yetki_var('siparis_olustur','kayit'))) with check ((public.auth_yetki_var('fatura_giris','kayit') or public.auth_yetki_var('fiyat_kontrol','kayit') or public.auth_yetki_var('siparis_olustur','kayit')));
-- commit; notify pgrst, 'reload schema';
