-- ============================================================================
-- GECIS OLCUMU — SALT OKUMA (hicbir sey yazmaz, islem acmaz)
-- Tasarim: docs/superpowers/specs/2026-10-11-talep-siparis-bagi-design.md §10
--
-- Tasarim §10: bagi olmayan eski talepler OTOMATIK IPTAL EDILMEZ, OTOMATIK
-- BAGLANMAZ. Bu dosya yalniz KARAR icin liste cikarir. Geciş adimi
-- migration'in parcasi DEGILDIR.
--
-- Calistirma:
--   .\docs\kurulum\sql-uygula.ps1 -Dosya docs\kurulum\2026-10-11-talep-siparis-gecis-olcumu.sql -SaltOkuma
--
-- BU DOSYA SALT OKUMADIR; "UYGULANDI/UYGULANMADI" kavrami gecersizdir.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1) Yeni gorunumde YENIDEN ACIK gorunecek talepler
--
-- Eski gorunum (2026-10-11-stok-acik-talep-durum-filtresi.sql) su satirlari
-- disliyordu:  `t.siparis_no is not null` VEYA durum IN
-- ('reddedildi','iptal','siparise_donustu','siparis').
-- Yeni gorunum yalniz ('iptal','reddedildi') disliyor ve kalani BAG
-- toplamindan hesapliyor. Dolayisiyla BAGI OLMAYAN her 'siparis' /
-- 'siparise_donustu' talep, yeni gorunumde yeniden ACIK gorunur.
--
-- `siparise_donustu` ETIKETI DE OLCULUR: bagimsiz inceleme (I9) hakli olarak
-- isaret etti — tasarim §10 yalniz durum='siparis' olan 7 kaydi olcmustu,
-- oysa eski gorunumun disladigi IKI etiket var. Populasyonu bilmeden etki
-- buyuklugu bilinemez.
-- ---------------------------------------------------------------------------
select t.durum::text            as durum,
       t.id,
       t.otel_id::text          as otel_id,
       t.talep_no,
       t.siparis_no             as olu_kolon_siparis_no,
       t.olusturma_tarihi,
       count(tk.id)             as kalem_sayisi,
       sum(tk.miktar)           as toplam_miktar
  from public.satin_alma_talepleri t
  join public.satin_alma_talep_kalemleri tk on tk.talep_id = t.id
 where t.durum::text in ('siparis', 'siparise_donustu')
   and not exists (select 1 from public.talep_siparis_baglari b
                    where b.talep_id = t.id)
 group by t.durum, t.id, t.otel_id, t.talep_no, t.siparis_no, t.olusturma_tarihi
 order by t.durum::text, t.olusturma_tarihi;

-- ---------------------------------------------------------------------------
-- 2) Ozet: etiket basina bagsiz talep sayisi
-- ---------------------------------------------------------------------------
select t.durum::text as durum, count(*) as bagsiz_talep_sayisi
  from public.satin_alma_talepleri t
 where t.durum::text in ('siparis', 'siparise_donustu')
   and not exists (select 1 from public.talep_siparis_baglari b
                    where b.talep_id = t.id)
 group by t.durum
 order by t.durum::text;

-- ---------------------------------------------------------------------------
-- 3) ETKI BUYUKLUGU: kalan miktar, birim bazinda
--
-- Birimler TOPLANMAZ — farkli birimlerin toplami anlamsizdir.
--
-- DIKKAT — `stok_acik_talep` GORUNUMU BU DOSYADA KULLANILMAZ. Sebebi
-- OLCULDU: gorunum `security_invoker=true` ve bag toplamini
-- `talep_bag_toplam()` uzerinden alir; o yardimci `auth_otel_erisim` +
-- modul yetkisi sorar, ikisi de `auth.uid()`'e dayanir. psql / SQL Editor /
-- `sql-uygula.ps1` oturumunda JWT YOKTUR, dolayisiyla `auth.uid()` null,
-- yardimci 0 satir doner ve gorunum baglari HIC dusmez: 10 KOL kalem + 6 KOL
-- bag varken JWT'li yetkili kimlik 4.000 gorurken JWT'siz oturum 10.000
-- gorur. Yani gorunum uzerinden alinan "etki buyuklugu" SISTEMATIK OLARAK
-- SISIKTIR. Hesap burada tablolardan DOGRUDAN yapilir.
-- ---------------------------------------------------------------------------
select tk.birim,
       count(*)                                        as kalem_sayisi,
       sum(tk.miktar)                                  as talep_toplami,
       sum(coalesce(b.bagli, 0))                       as bagli_toplami,
       sum(tk.miktar - coalesce(b.bagli, 0))           as kalan_toplami
  from public.satin_alma_talep_kalemleri tk
  join public.satin_alma_talepleri t on t.id = tk.talep_id
  left join (
    select b.talep_kalem_id, b.hedef_birim, sum(b.miktar) as bagli
      from public.talep_siparis_baglari b
      join public.siparisler s on s.siparis_no = b.siparis_no
     where s.durum <> 'iptal'
     group by b.talep_kalem_id, b.hedef_birim
  ) b on b.talep_kalem_id = tk.id and b.hedef_birim = tk.birim
 where t.durum not in ('iptal', 'reddedildi')
   and tk.miktar - coalesce(b.bagli, 0) > 0
 group by tk.birim
 order by tk.birim;

-- 3b) Gorunumun JWT'siz oturumda ne dondurdugu — KARSILASTIRMA icin, karar
--     icin DEGIL. Madde 3 ile ayni cikmasi beklenmez; fark bag toplamidir.
select birim, count(*) as satir_sayisi, sum(talep_miktar) as gorunum_toplami
  from public.stok_acik_talep
 group by birim
 order by birim;

-- ---------------------------------------------------------------------------
-- 4) DENETIM: `hedef_birim` ayrismasi — beklenen 0 SATIR
--
-- Bag yazilirken `hedef_birim` talep kaleminin birimine DONDURULUR ve K6
-- kapisi bagli kalemde birim degisimini engeller. Bu sorgu satir verirse
-- gorunumun `b.hedef_birim = tk.birim` eslesmesi kopmus demektir ve o baglar
-- kalan hesabindan tumuyle duser.
-- ---------------------------------------------------------------------------
select b.id, b.talep_kalem_id, b.hedef_birim, tk.birim as kalem_birim
  from public.talep_siparis_baglari b
  join public.satin_alma_talep_kalemleri tk on tk.id = b.talep_kalem_id
 where b.hedef_birim <> tk.birim;

-- ---------------------------------------------------------------------------
-- 5) DENETIM: INV ihlali olan kalem — beklenen 0 SATIR
--
-- Iptal olmayan siparislere ait bag toplami, kalem miktarini asmamali.
-- Kapilar bunu korur; bu sorgu kapilarin URETIMDE tuttugunu dogrular.
-- ---------------------------------------------------------------------------
select tk.id as talep_kalem_id, tk.birim, tk.miktar as kalem_miktar,
       sum(b.miktar) as bagli_toplam
  from public.satin_alma_talep_kalemleri tk
  join public.talep_siparis_baglari b on b.talep_kalem_id = tk.id
  join public.siparisler s on s.siparis_no = b.siparis_no
 where s.durum <> 'iptal' and b.hedef_birim = tk.birim
 group by tk.id, tk.birim, tk.miktar
having sum(b.miktar) > tk.miktar;

-- ---------------------------------------------------------------------------
-- 6) DENETIM: tetikleyici fonksiyonlari `security definer` mi?
--
-- Bagimsiz inceleme (C1/C3) olctu: `security invoker` olduklarinda K5/K6
-- SESSIZCE atlaniyor, K3 ise kalici `permission denied` veriyor. Beklenen:
-- alti satirin ALTISI da `t` (prosecdef).
-- ---------------------------------------------------------------------------
select p.proname, p.prosecdef as security_definer
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname in ('talep_bag_inv_kontrol','tsb_inv_tetik',
                     'sip_iptal_geri_al_inv_tetik','sipk_miktar_inv_tetik',
                     'talep_kalem_inv_tetik','sip_bagli_silinemez_tetik')
 order by p.proname;
