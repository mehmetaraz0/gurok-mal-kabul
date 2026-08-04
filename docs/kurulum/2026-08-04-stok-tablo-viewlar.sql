-- Stok tablo (grid) görünümü — 3 agregat view
-- security_invoker=true → RLS otel-scope parent tablolardan otomatik gelir.
-- Kullanıcı SQL Editor'de çalıştırır.

begin;

-- 1) Açık siparişlerde ürün bazlı gelmemiş (kalan) miktar
create or replace view public.stok_acik_siparis with (security_invoker=true) as
  select s.otel_id, sk.urun_kodu, sum(sk.kalan_miktar) as bekleyen_miktar
  from public.siparis_kalemleri sk
  join public.siparisler s on s.siparis_no = sk.siparis_no
  where s.durum not in ('tamamlandi','iptal') and sk.kalan_miktar > 0
  group by s.otel_id, sk.urun_kodu;

-- 2) Siparişe dönüşmemiş taleplerde ürün bazlı miktar
--    (siparis_no is null = henüz siparişe dönmemiş; iptal/reddedilmiş/tamamlanmış hariç)
create or replace view public.stok_acik_talep with (security_invoker=true) as
  select t.otel_id, tk.urun_kodu, sum(tk.miktar) as talep_miktar
  from public.satin_alma_talep_kalemleri tk
  join public.satin_alma_talepleri t on t.id = tk.talep_id
  where t.siparis_no is null and t.durum::text not in ('reddedildi','iptal','tamamlandi')
  group by t.otel_id, tk.urun_kodu;

-- 3) Ürün + depo bazlı son hareket tarihi
create or replace view public.stok_son_hareket with (security_invoker=true) as
  select otel_id, depo_kodu, urun_kodu, max(tarih) as son_tarih
  from public.stok_hareketleri
  group by otel_id, depo_kodu, urun_kodu;

grant select on public.stok_acik_siparis, public.stok_acik_talep, public.stok_son_hareket to authenticated;

commit;

notify pgrst, 'reload schema';

-- Doğrulama (opsiyonel):
-- select count(*) from public.stok_acik_siparis;
-- select count(*) from public.stok_acik_talep;
-- select count(*) from public.stok_son_hareket;
