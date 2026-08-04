-- 2026-08-04 — Geciken sipariş yeniden yönlendirme (atomik RPC)
-- Eski siparişi 'iptal' yapar + kalan_miktar>0 kalemlerle yeni teklif talebi (RFQ) açar. TEK transaction.
-- Bir adım patlarsa hiçbir şey yazılmaz (raise exception = rollback).
-- Yetki: auth_yetki_var('siparis_olustur','kayit') + auth_otel_erisim (mevcut desen).
-- Tasarım: docs/superpowers/specs/2026-08-04-geciken-siparis-yeniden-yonlendirme-design.md
-- Çalıştırma: SQL Editor → Run. Rollback: en altta.

begin;

create or replace function public.siparis_yeniden_yonlendir(p_siparis_no text, p_olusturan text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_otel public.otel_id;
  v_durum text;
  v_talep_id uuid;
  v_kalan_sayi int;
  v_kalem record;
begin
  if not public.auth_yetki_var('siparis_olustur','kayit') then
    raise exception 'Yetki yok: sipariş yeniden yönlendirme için siparis_olustur kayıt yetkisi gerekli';
  end if;

  select otel_id, durum into v_otel, v_durum
  from public.siparisler where siparis_no = p_siparis_no;
  if not found then
    raise exception 'Sipariş bulunamadı: %', p_siparis_no;
  end if;
  if not public.auth_otel_erisim(v_otel::text) then
    raise exception 'Yetki yok: bu siparişin oteline erişiminiz yok';
  end if;
  if v_durum in ('iptal','tamamlandi') then
    raise exception 'Bu sipariş yeniden yönlendirilemez (durum: %)', v_durum;
  end if;

  select count(*) into v_kalan_sayi
  from public.siparis_kalemleri
  where siparis_no = p_siparis_no and kalan_miktar > 0;
  if v_kalan_sayi = 0 then
    raise exception 'Gelmeyen (kalan) kalem yok — yeniden yönlendirmeye gerek yok';
  end if;

  update public.siparisler
    set durum = 'iptal',
        not_alani = coalesce(not_alani || ' | ', '') ||
          'Gecikme nedeniyle iptal + yeniden yönlendirildi (' || to_char(now(),'YYYY-MM-DD') || ')',
        son_guncelleme = now()
  where siparis_no = p_siparis_no;

  insert into public.teklif_talepleri (olusturan, otel_id, durum)
  values (p_olusturan, v_otel::text, 'acik')
  returning id into v_talep_id;

  for v_kalem in
    select urun_kodu, urun_adi, birim, kalan_miktar
    from public.siparis_kalemleri
    where siparis_no = p_siparis_no and kalan_miktar > 0
  loop
    insert into public.teklif_kalemleri (teklif_talebi_id, urun_kodu, urun_adi, miktar, birim)
    values (v_talep_id, v_kalem.urun_kodu, v_kalem.urun_adi, v_kalem.kalan_miktar, v_kalem.birim);
  end loop;

  return v_talep_id;
end;
$$;

revoke all on function public.siparis_yeniden_yonlendir(text, text) from public;
grant execute on function public.siparis_yeniden_yonlendir(text, text) to authenticated;

commit;
notify pgrst, 'reload schema';

-- ROLLBACK:
-- begin;
-- drop function if exists public.siparis_yeniden_yonlendir(text, text);
-- commit;
-- notify pgrst, 'reload schema';
