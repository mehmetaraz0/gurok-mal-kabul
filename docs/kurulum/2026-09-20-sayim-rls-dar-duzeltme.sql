-- ===========================================================================
-- SAYIM ERISIM DUZELTMESI — DAR KAPSAM   ** ONAY BEKLIYOR, UYGULANMADI **
-- ===========================================================================
-- SORUN (olculdu 2026-09-20, hem uretimde hem izole ortamda):
--   sayim_oturumlari ve sayim_detaylari tablolarinda RLS acik ama IZIN VEREN
--   (permissive) hicbir politika yok. Ekran sayimi DOGRUDAN tabloya yaziyor:
--     * olusturma  -> INSERT  -> RLS reddi
--     * listeleme  -> SELECT  -> 0 satir
--     * reddetme   -> UPDATE  -> 0 satir
--   Yani sayim ozelligi uretimde hic calismamis (iki tablo da 0 satir).
--   A1'in onay/detay yollari SECURITY DEFINER RPC oldugu icin calisir; bu
--   dosya yalnizca EKSIK olan uc yolu acar.
--
-- DAR KAPSAM ILKESI (kullanici karari 2026-09-20: "mevcut cost-control
-- sinirini koruyan dar kapsamli duzeltme"):
--   1. Yeni yetki seviyesi ICAT EDILMEZ. Kapi, stok yazan diger tablolarin
--      (stok, stok_hareketleri, stok_minimumlar) bugun kullandigi kapinin
--      AYNISIDIR: auth_yetki_var('stok_takip', ...) + auth_otel_erisim().
--      Boylece sayim, stok yazma hakkiyla ayni kumeye acilir; kimse stok
--      uzerinde bugun sahip olmadigi bir yetki kazanmaz.
--   2. sayim_detaylari'na SELECT politikasi EKLENMEZ. Detay okuma A1'in
--      stok_sayim_detaylari() RPC'siyle yapilir (duraklatilmis eski sekme
--      korumasinin bir katmani). A1'in kaldirdigi SELECT grant'i geri
--      VERILMEZ.
--   3. UPDATE yalnizca REDDETME icindir: 'onay_bekliyor' -> 'reddedildi'.
--      Dogrudan 'onaylandi' yazilamaz; onay yalnizca stok_sayim_onayla()
--      RPC'sinden gecer (stok hareketi ve bekleyen duzeltme mantigi orada).
--   4. DELETE / TRUNCATE politikasi ve hakki YOK (asagida geri alinir).
--
-- EK GUVENLIK DUZELTMESI (bu iki tabloyla sinirli):
--   Uretim dokumunde bu tablolar 'GRANT ALL ... TO authenticated' almis; bu
--   TRUNCATE'i de kapsiyor ve **TRUNCATE RLS'i DINLEMEZ**. Yani politika
--   eklemek tek basina yetmez: TRUNCATE geri alinmadan herhangi bir ERP
--   kullanicisi sayim tablolarini bosaltabilir. Asagida yalnizca bu iki tablo
--   icin geri alinir. AYNI KUSUR BASKA TABLOLARDA DA VAR (dokumde 77 tablo
--   'GRANT ALL' almis) — o, bu dosyanin kapsami DISINDA, ayri bir istir.
--
-- ONAYA SUNULAN YETKI DEGISIKLIKLERI (tamami asagida, baskasi yok):
--   (a) 4 adet permissive RLS politikasi (select/insert/update + detay insert)
--   (b) REVOKE: delete, truncate, references, trigger  (yalniz 2 sayim tablosu)
--   YENI GRANT YOKTUR. Mevcut select/insert/update haklari zaten var.
--
-- GERI ALMA: 2026-09-20-sayim-rls-dar-duzeltme-geri-al.sql
-- ===========================================================================
begin;

-- --------------------------------------------------------------------------
-- 0. On kosullar
-- --------------------------------------------------------------------------
do $$
begin
  if to_regprocedure('public.stok_sayim_detaylari(uuid)') is null then
    raise exception 'ON KOSUL: A1 migration (2026-09-18-bar-a1-guvenlik.sql) once uygulanmalidir';
  end if;
  if to_regprocedure('public.auth_yetki_var(text,text)') is null
     or to_regprocedure('public.auth_otel_erisim(text)') is null then
    raise exception 'ON KOSUL: auth_yetki_var / auth_otel_erisim bulunamadi';
  end if;
  if exists (select 1 from pg_policies
              where schemaname = 'public' and tablename = 'sayim_detaylari'
                and permissive = 'PERMISSIVE' and cmd in ('SELECT','ALL')) then
    raise exception 'ON KOSUL: sayim_detaylari uzerinde izin veren SELECT politikasi var — A1 katmani bozulmus';
  end if;
end $$;

-- --------------------------------------------------------------------------
-- 1. sayim_oturumlari — listeleme
-- --------------------------------------------------------------------------
drop policy if exists sayim_oturum_select on public.sayim_oturumlari;
create policy sayim_oturum_select on public.sayim_oturumlari
  for select to authenticated
  using (public.auth_yetki_var('stok_takip', 'kayit') is true
         and public.auth_otel_erisim(otel_id::text) is true);

comment on policy sayim_oturum_select on public.sayim_oturumlari is
  'Sayim oturumlarini, stok yazma yetkisi olan kullanici KENDI otelinde listeler. '
  'Kapi stok/stok_hareketleri ile ayni: auth_yetki_var(stok_takip,kayit) + auth_otel_erisim.';

-- --------------------------------------------------------------------------
-- 2. sayim_oturumlari — olusturma (yalniz 'onay_bekliyor' olarak)
-- --------------------------------------------------------------------------
drop policy if exists sayim_oturum_insert on public.sayim_oturumlari;
create policy sayim_oturum_insert on public.sayim_oturumlari
  for insert to authenticated
  with check (public.auth_yetki_var('stok_takip', 'kayit') is true
              and public.auth_otel_erisim(otel_id::text) is true
              and durum = 'onay_bekliyor');

comment on policy sayim_oturum_insert on public.sayim_oturumlari is
  'Yeni sayim yalnizca onay_bekliyor durumunda acilir; onayli/reddedilmis oturum '
  'dogrudan olusturulamaz.';

-- --------------------------------------------------------------------------
-- 3. sayim_oturumlari — REDDETME (onay DEGIL)
-- --------------------------------------------------------------------------
drop policy if exists sayim_oturum_reddet on public.sayim_oturumlari;
create policy sayim_oturum_reddet on public.sayim_oturumlari
  for update to authenticated
  using (public.auth_yetki_var('stok_takip', 'kayit') is true
         and public.auth_otel_erisim(otel_id::text) is true
         and durum = 'onay_bekliyor'
         and kismi_uygulandi is not true)
  with check (public.auth_yetki_var('stok_takip', 'kayit') is true
              and public.auth_otel_erisim(otel_id::text) is true
              and durum = 'reddedildi');

comment on policy sayim_oturum_reddet on public.sayim_oturumlari is
  'Yalniz onay_bekliyor -> reddedildi gecisi. Dogrudan onaylandi YAZILAMAZ (onay '
  'stok_sayim_onayla() RPC''sinden gecer). Kismen uygulanmis oturum reddedilemez: '
  'bazi urunlerin stogu zaten degismistir (ekrandaki fail-closed kontrolun sunucu esi).';

-- --------------------------------------------------------------------------
-- 4. sayim_detaylari — yalniz olusturma (OKUMA YOK: RPC ile okunur)
-- --------------------------------------------------------------------------
drop policy if exists sayim_detay_insert on public.sayim_detaylari;
create policy sayim_detay_insert on public.sayim_detaylari
  for insert to authenticated
  with check (public.auth_yetki_var('stok_takip', 'kayit') is true
              and exists (select 1 from public.sayim_oturumlari o
                           where o.id = oturum_id
                             and o.durum = 'onay_bekliyor'
                             and public.auth_otel_erisim(o.otel_id::text) is true));

comment on policy sayim_detay_insert on public.sayim_detaylari is
  'Detay satiri yalnizca kullanicinin gorebildigi, ACIK (onay_bekliyor) bir oturuma '
  'eklenir. SELECT politikasi BILEREK YOKTUR: detaylar stok_sayim_detaylari() '
  'RPC''si ile okunur (A1 eski sekme korumasi).';

-- --------------------------------------------------------------------------
-- 5. Fazla haklarin geri alinmasi (yalniz bu iki tablo)
--    TRUNCATE kritik: RLS'i DINLEMEZ, politika eklemek onu durdurmaz.
-- --------------------------------------------------------------------------
revoke delete, truncate, references, trigger on table public.sayim_oturumlari from authenticated;
revoke delete, truncate, references, trigger on table public.sayim_detaylari  from authenticated;

-- --------------------------------------------------------------------------
-- 6. Son kosullar — dosya kendi sonucunu dogrular
-- --------------------------------------------------------------------------
do $$
declare v_n integer;
begin
  select count(*) into v_n from pg_policies
   where schemaname = 'public'
     and policyname in ('sayim_oturum_select','sayim_oturum_insert','sayim_oturum_reddet','sayim_detay_insert');
  if v_n <> 4 then raise exception 'SON KOSUL: 4 politika bekleniyordu, % bulundu', v_n; end if;

  if has_table_privilege('authenticated', 'public.sayim_detaylari', 'select') then
    raise exception 'SON KOSUL: sayim_detaylari SELECT hakki authenticated''a geri verilmis (A1 katmani bozuk)';
  end if;
  if has_table_privilege('authenticated', 'public.sayim_oturumlari', 'truncate')
     or has_table_privilege('authenticated', 'public.sayim_detaylari', 'truncate') then
    raise exception 'SON KOSUL: TRUNCATE hakki hala duruyor';
  end if;
  if has_table_privilege('authenticated', 'public.sayim_oturumlari', 'delete')
     or has_table_privilege('authenticated', 'public.sayim_detaylari', 'delete') then
    raise exception 'SON KOSUL: DELETE hakki hala duruyor';
  end if;
  if not has_table_privilege('authenticated', 'public.sayim_oturumlari', 'insert')
     or not has_table_privilege('authenticated', 'public.sayim_detaylari', 'insert') then
    raise exception 'SON KOSUL: INSERT hakki eksik — ekran sayim olusturamaz';
  end if;
end $$;

commit;
