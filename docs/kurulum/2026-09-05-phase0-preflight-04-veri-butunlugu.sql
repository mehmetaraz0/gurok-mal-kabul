-- ============================================================================
-- PHASE 0 PREFLIGHT 4/5 — VERI BUTUNLUGU
-- ============================================================================
-- SALT-OKUMA. Hicbir mutation icermez. Supabase SQL Editor'de calistirilabilir:
-- dosya TEK sonuc kumesi uretir (editor yalniz son sorgunun sonucunu gosterir).
--
-- YALNIZCA SAYIM. Hicbir kayit duzeltilmez.
--
-- ONEMLI AYRIM: merkez kullanicilarinin (tum_oteller = true) otel_id alani
-- BOS olabilir ve bu MESRUDUR. Asagida ayri satirlarda raporlanir; ikisini
-- karistirmak yanlis alarm uretir.
--
-- Ciktiyi ozel tutun: fonksiyon tanimlari ve politika ifadeleri is mantigi icerir.
-- Satir verisi, PIN, hash, JWT veya kimlik bilgisi SECILMEZ.
-- ============================================================================

select 'personel: otel atamasi yok VE merkez degil'   as kontrol,
       count(*) filter (where aktif and otel_id is null and not tum_oteller) as sayi,
       'ANOMALI — incelenmeli'                          as yorum
from public.kullanicilar
union all
select 'personel: otel bos AMA merkez (tum_oteller)',
       count(*) filter (where aktif and otel_id is null and tum_oteller),
       'BEKLENEN — anomali degil'
from public.kullanicilar
union all
select 'personel: rol atanmamis',
       count(*) filter (where aktif and rol_id is null), 'ANOMALI'
from public.kullanicilar
union all
select 'personel: pasif ama Auth kimligi bagli',
       count(*) filter (where not aktif and auth_user_id is not null),
       'Bilgi — pasif kullanici artik yetki cozemez'
from public.kullanicilar
union all
select 'mukerrer Auth kimligi (grup)', count(*), 'MIGRATION ENGELI'
from (select auth_user_id from public.kullanicilar
      where auth_user_id is not null group by auth_user_id having count(*) > 1) d
union all
select 'bar kalemi: siparis ile menu farkli otelde', count(*), 'ANOMALI'
from public.bar_siparis_kalemleri k
join public.bar_siparisleri b on b.id = k.siparis_id
join public.menu_urunler m on m.id = k.menu_urun_id
where b.otel_id is distinct from m.otel_id
union all
select 'fatura ile siparis farkli otelde', count(*), 'ANOMALI'
from public.faturalar f
join public.siparisler s on s.siparis_no = f.siparis_no
where f.otel_id::text is distinct from s.otel_id::text
union all
select 'depo kodu birden fazla otelde (stok kaynakli)', count(*),
       'BILGI — depo master DB de yok, otel-config.js otoriter'
from (select depo_kodu from public.stok
      group by depo_kodu having count(distinct otel_id) > 1) a
order by 1;
