-- 2026-08-05 — Başarılı giriş kaydını İSTEMCİ tarafından yazmak için RPC.
-- Neden: EF deploy'una bağımlı olmasın (git ile otomatik yayılsın). Güvenlik:
-- kullanıcı JWT'den (auth.uid() -> kullanicilar) türetilir; client kimliği
-- uyduramaz, yalnızca KENDİ girişini loglar. SECURITY DEFINER → RLS'i (insert
-- policy'si yok) aşarak giris_kayitlari'na yazar.

begin;

create or replace function public.giris_kaydi_ekle(p_giris_tipi text default 'pin')
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id   uuid;
  v_ad   text;
  v_otel public.otel_id;
begin
  select k.id, k.ad, k.otel_id
    into v_id, v_ad, v_otel
  from public.kullanicilar k
  where k.auth_user_id = auth.uid()
  limit 1;

  if v_id is null then
    return;  -- oturum yok / eşleşen kullanıcı yok → sessizce çık
  end if;

  insert into public.giris_kayitlari (kullanici_id, ad, otel_id, giris_tipi, ip_hash)
  values (v_id, v_ad, v_otel, coalesce(nullif(p_giris_tipi,''),'pin'), null);
end;
$$;

revoke all on function public.giris_kaydi_ekle(text) from public;
revoke all on function public.giris_kaydi_ekle(text) from anon;
grant execute on function public.giris_kaydi_ekle(text) to authenticated;

commit;

notify pgrst, 'reload schema';

-- Test (SQL Editor'de auth.uid() null olduğu için 0 satır ekler — normal;
-- gerçek test uygulamada PIN'le giriş yapıp giris_kayitlari'na bakmaktır):
-- select public.giris_kaydi_ekle('pin');
