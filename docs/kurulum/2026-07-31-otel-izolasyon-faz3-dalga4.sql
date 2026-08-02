-- 2026-07-31 — Madde D / FAZ 3 DALGA 4 (SON DALGA — henüz ÇALIŞTIRILMADI)
--
-- Faz 3 durumu: Pilot (stok,faturalar) + Dalga 1-3 CANLI+doğrulandı (16 tablo).
-- Bu dosya kalan 5 tabloyu otel-izole eder. Aynı kanıtlanmış desen:
-- mevcut auth_yetki_var politikalarına `and auth_otel_erisim(otel_id::text)` AND'lenir.
-- Yalnızca VAR OLAN politikalar recreate edilir (bazı tablolarda insert/update yok).
--
-- ⚠️ sayim_oturumlari + edefter_sube_bilgileri BU DALGADA YOK: canlıda RLS açık ama
--    0 politika = RPC-gated (doğrudan erişim kapalı). RLS politikası EKLENMEZ (kapalı
--    yolu açar). Otel izolasyonu gerekiyorsa kendi SECURITY DEFINER RPC'lerinde yapılır
--    — ayrı, küçük follow-up.
--
-- Çalıştırma: SQL Editor → Run. Sonra test (Reçeteler/Tüketim, SKT, Koli, Uygunsuzluk;
-- merkez ikisini de, tek-otel kendi otelini). Rollback: her create'i eski (otel-koşulsuz)
-- haline döndür (bkz. faz2-pilot dosyasındaki rollback deseni).

begin;

-- receteler (gunluk_tuketim)
drop policy if exists r_select on public.receteler;
create policy r_select on public.receteler for select
  using (public.auth_yetki_var('gunluk_tuketim','goruntule') and public.auth_otel_erisim(otel_id::text));
drop policy if exists r_insert on public.receteler;
create policy r_insert on public.receteler for insert
  with check (public.auth_yetki_var('gunluk_tuketim','kayit') and public.auth_otel_erisim(otel_id::text));
drop policy if exists r_update on public.receteler;
create policy r_update on public.receteler for update
  using (public.auth_yetki_var('gunluk_tuketim','kayit') and public.auth_otel_erisim(otel_id::text))
  with check (public.auth_yetki_var('gunluk_tuketim','kayit') and public.auth_otel_erisim(otel_id::text));

-- recete_tuketimleri (gunluk_tuketim) — update policy YOK
drop policy if exists rt_select on public.recete_tuketimleri;
create policy rt_select on public.recete_tuketimleri for select
  using (public.auth_yetki_var('gunluk_tuketim','goruntule') and public.auth_otel_erisim(otel_id::text));
drop policy if exists rt_insert on public.recete_tuketimleri;
create policy rt_insert on public.recete_tuketimleri for insert
  with check (public.auth_yetki_var('gunluk_tuketim','kayit') and public.auth_otel_erisim(otel_id::text));

-- skt_kayitlari (mal_kabul_kalite)
drop policy if exists skt_select on public.skt_kayitlari;
create policy skt_select on public.skt_kayitlari for select
  using (public.auth_yetki_var('mal_kabul_kalite','goruntule') and public.auth_otel_erisim(otel_id::text));
drop policy if exists skt_insert on public.skt_kayitlari;
create policy skt_insert on public.skt_kayitlari for insert
  with check (public.auth_yetki_var('mal_kabul_kalite','kayit') and public.auth_otel_erisim(otel_id::text));
drop policy if exists skt_update on public.skt_kayitlari;
create policy skt_update on public.skt_kayitlari for update
  using (public.auth_yetki_var('mal_kabul_kalite','kayit') and public.auth_otel_erisim(otel_id::text))
  with check (public.auth_yetki_var('mal_kabul_kalite','kayit') and public.auth_otel_erisim(otel_id::text));

-- koli_etiketleri (fiyat_kontrol) — insert policy YOK
drop policy if exists ke_select on public.koli_etiketleri;
create policy ke_select on public.koli_etiketleri for select
  using (public.auth_yetki_var('fiyat_kontrol','goruntule') and public.auth_otel_erisim(otel_id::text));
drop policy if exists ke_update on public.koli_etiketleri;
create policy ke_update on public.koli_etiketleri for update
  using (public.auth_yetki_var('fiyat_kontrol','kayit') and public.auth_otel_erisim(otel_id::text))
  with check (public.auth_yetki_var('fiyat_kontrol','kayit') and public.auth_otel_erisim(otel_id::text));

-- uygunsuzluklar (fiyat_kontrol) — sadece select policy var
drop policy if exists uy_select on public.uygunsuzluklar;
create policy uy_select on public.uygunsuzluklar for select
  using (public.auth_yetki_var('fiyat_kontrol','goruntule') and public.auth_otel_erisim(otel_id::text));

commit;
notify pgrst, 'reload schema';
