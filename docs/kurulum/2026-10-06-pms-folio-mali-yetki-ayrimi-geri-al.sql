-- ===========================================================================
-- PMS folyo mali yetki ayrımının GERİ ALINMASI — güvenli geri dönüş
-- ===========================================================================
-- Eşi: 2026-10-06-pms-folio-mali-yetki-ayrimi.sql
--
-- YAYIN BAĞIMLILIĞI (onaylı tasarımın yayın kapısı):
--   Yeni sunucu kuralı, personel ve vardiyaya `pms_folio=kayit` verilmesinin
--   ÖN KOŞULUDUR. Bu yüzden geri dönüş, o roller `kayit` taşırken eski GENİŞ
--   INSERT kuralını geri getirmez — getirirse personel/vardiya iade, indirim
--   ve düzeltme yazabilir hâle gelir.
--
--   Bu dosya bunu ZORLAR: `onburo_personel` veya `onburo_vardiya` üzerinde
--   `pms_folio` yetkisi `kayit` ise DURUR ve hiçbir şey değiştirmez.
--   Doğru sıra:
--     1) tohumlama geri alması ile o rollerin `kayit` satırlarını kaldırın
--        (2026-10-05-pms-onburo-modul-tohumlama-geri-al.sql),
--     2) sonra bu dosyayı çalıştırın.
--
--   MY-2: ZORLAMA YOLU YOKTUR. Önceki sürümde bir bayrakla bu şart
--   atlanabiliyordu; bu, onaylı tasarımın şartını kaldıran yeni bir yetki
--   genişletme yoluydu ve uyarı yazmak kullanıcı onayı yerine geçmez.
--   Tek güvenli sıra: önce yetkiyi kaldır, sonra kuralı geri al.
--
-- DEĞİŞMEZLİK HER HÂLDE KORUNUR: bu dosya append-only kurguya dokunmaz.
-- Mali satırlar geri alma sonrasında da UPDATE/DELETE edilemez.
-- ===========================================================================

begin;

do $$
declare
  v_acik  text;
begin
  select string_agg(r.kod || '=' || ym.yetki::text, ', ' order by r.kod)
    into v_acik
  from public.yetki_matrisi ym
  join public.roller   r on r.id = ym.rol_id
  join public.moduller m on m.id = ym.modul_id
  where m.kod = 'pms_folio'
    and r.kod in ('onburo_personel','onburo_vardiya')
    and ym.yetki::text = 'kayit';

  if v_acik is not null then
    raise exception
      'GUVENLI GERI DONUS ENGELI: su roller hala `pms_folio=kayit` tasiyor: %. '
      'Kurali geri almak onlara iade/indirim/duzeltme hakki verir. Once '
      '2026-10-05-pms-onburo-modul-tohumlama-geri-al.sql ile bu yetkileri '
      'kaldirin, SONRA bu dosyayi calistirin. Bu sarti atlayan bir bayrak '
      'YOKTUR. Hicbir sey degistirilmedi.', v_acik
      using errcode = '23514';
  end if;
end $$;

-- --- 1) INSERT politikalarını 09-06 sürümüne döndür -----------------------
drop policy if exists pms_folio_hareketleri_insert on public.pms_folio_hareketleri;
create policy pms_folio_hareketleri_insert on public.pms_folio_hareketleri
  for insert to authenticated
  with check (public.auth_yetki_var('pms_folio','kayit') is true
              and public.auth_otel_erisim(otel_id::text) is true);

drop policy if exists pms_folio_odemeler_insert on public.pms_folio_odemeler;
create policy pms_folio_odemeler_insert on public.pms_folio_odemeler
  for insert to authenticated
  with check (public.auth_yetki_var('pms_folio','kayit') is true
              and public.auth_otel_erisim(otel_id::text) is true);

-- --- 2) Hassas kapı tetikleyicilerini kaldır ------------------------------
drop trigger if exists pms_folio_hassas_kapi on public.pms_folio_hareketleri;
drop trigger if exists pms_folio_hassas_kapi on public.pms_folio_odemeler;
drop function if exists public.pms_folio_hassas_kapi();
drop function if exists public.pms_folio_hassas_mi(text, numeric, text, boolean);

-- --- 3) Değişmezliğin hâlâ yerinde olduğunu ÖLÇ --------------------------
do $$
declare v_t text; v_n int; v_hata text := '';
begin
  foreach v_t in array array['pms_folio_hareketleri','pms_folio_odemeler'] loop
    if has_table_privilege('authenticated', 'public.' || v_t, 'UPDATE')
       or has_table_privilege('authenticated', 'public.' || v_t, 'DELETE') then
      v_hata := v_hata || v_t || ': UPDATE/DELETE ayricaligi VAR; ';
    end if;
    select count(*) into v_n from pg_policies
     where schemaname='public' and tablename=v_t and cmd in ('UPDATE','DELETE');
    if v_n > 0 then v_hata := v_hata || v_t || ': update/delete politikasi VAR; '; end if;
    if not exists (select 1 from pg_trigger t join pg_class c on c.oid=t.tgrelid
                    where c.relname=v_t and t.tgname='pms_folio_degismez'
                      and not t.tgisinternal) then
      v_hata := v_hata || v_t || ': pms_folio_degismez YOK; ';
    end if;
  end loop;
  if v_hata <> '' then
    raise exception 'GERI ALMA SONRASI DEGISMEZLIK BOZULMUS: %', v_hata
      using errcode = '23514';
  end if;
  raise notice 'Geri alma tamam. Degismezlik korunuyor; INSERT kurali 09-06 '
               'surumune dondu (hassas/normal ayrimi YOK).';
end $$;

commit;
