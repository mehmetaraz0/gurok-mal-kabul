-- ===========================================================================
-- KESINTI UZLASTIRMASI — BELGE/KALEM BAZINDA TUTARLILIK   ** SALT OKUMA **
-- ===========================================================================
-- NEDEN: yayin penceresinde yazma duraklatmasi (REVOKE) YENI cagrilari durdurur
-- ama ekranlarin cok adimli islemini YARIDA kesebilir. Ekranlar miktari (stok),
-- hareketi (stok_hareketleri) ve rezervasyonu AYRI isteklerde yazar; sunucuda
-- ortak bir islem kimligi yoktur. Bu yuzden "kalem sayisi = hareket sayisi"
-- KANIT DEGILDIR ve yarim kalan is korlemesine tekrarlanamaz.
--
-- BU DOSYA: kesinti penceresinde stok / rezervasyon / hareket ucgenini belge ve
-- kalem bazinda karsilastirir, her satiri KESIN ya da BELIRSIZ olarak siniflar
-- ve sonunda TEK BIR KARAR satiri basar:
--     "YENIDEN ACMA: EVET"  -> belirsiz satir yok, yazma haklari geri verilebilir
--     "YENIDEN ACMA: HAYIR" -> once belirsiz satirlar cozumlenmeli
--
-- HICBIR SEY YAZMAZ: read only islem, sonda rollback.
--
-- KULLANIM:
--   .\docs\kurulum\sql-uygula.ps1 -Dosya docs\kurulum\2026-09-20-kesinti-uzlastirma.sql -SaltOkuma
--
-- Kesinti penceresi varsayilan olarak SON 2 SAATTIR. Duraklatma saatini
-- biliyorsaniz dosyanin basindaki set satirini o ana ayarlayin:
--   set uzl.kesinti = '2026-09-21 03:00+03';
--
-- KARAR KURALI (kullanici karari 2026-09-20): "Sonucu belirsiz islem varken
-- yeniden acma yapma." BELIRSIZ satir varsa yazma haklari GERI VERILMEZ;
-- satirlar once iz (denetim kaydi, hareket, stok son degisim) ve gerekirse
-- fiziksel sayimla cozumlenir. Yalnizca islenmedigi KANITLANAN satir tamamlanir.
-- ===========================================================================
begin transaction read only;

-- Pencere: acikca ayarlanmamissa son 2 saat.
\echo '== 0) KESINTI PENCERESI'
select coalesce(nullif(current_setting('uzl.kesinti', true), '')::timestamptz,
                now() - interval '2 hours') as pencere_baslangici, now() as simdi;

\echo '== UZLASTIRMA SATIRLARI (karar sutunu: BELIRSIZ = yeniden acma yok) =='
with p as (
  select coalesce(nullif(current_setting('uzl.kesinti', true), '')::timestamptz,
                  now() - interval '2 hours') as t0
),

-- ---------------------------------------------------------------------------
-- U1. MAL KABUL — kalem bazinda stok etkisi / hareket / onay zamani
-- ---------------------------------------------------------------------------
mk as (
  select m.id, m.mk_no, m.otel_id,
         (select max(a.server_timestamp) from public.erp_islem_audit a
           where a.entity_type = 'mal_kabuller' and a.entity_id = m.id::text
             and a.event_type = 'UPDATE') as onay_zamani
    from public.mal_kabuller m
   where m.durum = 'onaylandi' and coalesce(m.stok_islendi, false) = false
),
u1 as (
  select 'U1 mal kabul' as kaynak,
         mk.mk_no || ' / ' || k.urun_kodu as anahtar,
         'kalem ' || k.miktar::text || ' | eslesen hareket ' || h.adet::text
           || ' | stok son degisim ' || coalesce(s.guncelleme_tarihi::text, '-')
           || ' | onay ' || coalesce(mk.onay_zamani::text, '-') as ayrinti,
         case
           when h.adet > 0 then 'KESIN: hareket var — kalem islenmis'
           when mk.onay_zamani is not null and s.guncelleme_tarihi >= mk.onay_zamani
             then 'BELIRSIZ: hareket yok ama stok onaydan SONRA degismis'
           when coalesce(s.depo_sayisi, 0) = 0 then 'KESIN: stok satiri yok — islenmemis'
           else 'KESIN: hareket yok, stok onaydan beri degismemis — islenmemis'
         end as karar
    from mk
    join public.mal_kabul_urunleri k on k.mk_id = mk.id
    left join lateral (
      select count(*) as adet from public.stok_hareketleri h2
       where h2.belge_no = mk.mk_no and h2.urun_kodu = k.urun_kodu and h2.tip = 'giris') h on true
    left join lateral (
      select max(s2.guncelleme_tarihi) as guncelleme_tarihi, count(*) as depo_sayisi
        from public.stok s2 where s2.urun_kodu = k.urun_kodu and s2.otel_id = mk.otel_id) s on true
   where coalesce(k.urun_kodu, '') <> '' and k.miktar > 0
),

-- ---------------------------------------------------------------------------
-- U2. STOK DEGISTI AMA HAREKET YOK (transfer, elle giris/cikis, sayim)
--     stok_transfer iki stok satirini TEK fonksiyonda yazar (bolunmez), ama
--     hareket kayitlarini ekran AYRI istekle yazar: kesinti tam araya girebilir.
-- ---------------------------------------------------------------------------
--     KESIN olmak icin DORT ALANIN birden eslesmesi gerekir (kullanici karari
--     2026-09-20): belge/kalem + urun + depo + MIKTAR. belge_no'nun dolu olmasi
--     TEK BASINA yetmez; belge bulunamiyorsa ya da kalem miktari hareketin
--     miktarina esit degilse satir BELIRSIZ kalir.
--     Eslestirilen kaynaklar: mal kabul kalemi, bar stok tuketimi, sayim
--     bekleyen duzeltmesi. Baska bir kaynaktan gelen hareket (elle giris, harici
--     duzeltme) KESIN sayilmaz — insan incelemesine birakilir.
u2 as (
  select 'U2 stok/hareket' as kaynak,
         s.depo_kodu || ' / ' || s.urun_kodu as anahtar,
         'stok son degisim ' || s.guncelleme_tarihi::text
           || ' | pencerede hareket ' || h.adet::text
           || ' (belgeli ' || h.belgeli::text || ', tam eslesen ' || h.tam::text || ')' as ayrinti,
         case when h.tam > 0
                then 'KESIN: belge/kalem + urun + depo + miktar eslesen hareket var'
              when h.belgeli > 0
                then 'BELIRSIZ: belge numarasi var ama kalem/miktar eslesmiyor'
              when h.adet > 0
                then 'BELIRSIZ: hareket var ama belge/kalemle iliskilendirilemiyor'
              else 'BELIRSIZ: stok pencerede degismis, eslesen hareket yok' end as karar
    from public.stok s, p
    left join lateral (
      select count(*) as adet,
             count(*) filter (where coalesce(h2.belge_no, '') <> '') as belgeli,
             count(*) filter (where coalesce(h2.belge_no, '') <> '' and (
               -- (a) mal kabul: belge no + urun + otel + miktar
               exists (select 1 from public.mal_kabuller m
                         join public.mal_kabul_urunleri mu on mu.mk_id = m.id
                        where m.mk_no = h2.belge_no and mu.urun_kodu = h2.urun_kodu
                          and m.otel_id = s.otel_id and round(mu.miktar, 3) = round(h2.miktar, 3))
               -- (b) bar tuketimi: siparis + urun + depo + miktar
               or exists (select 1 from public.bar_stok_tuketimleri t
                           where t.stok_kodu = h2.urun_kodu and t.bar_depo_id = h2.depo_kodu
                             and round(t.miktar, 3) = round(h2.miktar, 3)
                             and h2.belge_no like '%' || left(t.siparis_id::text, 8) || '%')
               -- (c) sayim bekleyen duzeltmesi: urun + depo + fark miktari
               or exists (select 1 from public.stok_sayim_bekleyenleri b
                           where b.urun_kodu = h2.urun_kodu and b.depo_kodu = h2.depo_kodu
                             and round(abs(b.fark), 3) = round(h2.miktar, 3))
             )) as tam
        from public.stok_hareketleri h2, p p2
       where h2.depo_kodu = s.depo_kodu and h2.urun_kodu = s.urun_kodu and h2.tarih >= p2.t0) h on true
   where s.guncelleme_tarihi >= p.t0
),

-- ---------------------------------------------------------------------------
-- U3. BAR REZERVASYON TUTARLILIGI
--     Bar teslim/iptal yollari TEK SECURITY DEFINER fonksiyondur (bolunmez);
--     yine de kesinti sirasinda fonksiyonun kendisi reddedilmis olabilir ve
--     ekran yarim gorunum birakabilir. Uc tutarsizlik aranir.
-- ---------------------------------------------------------------------------
-- A1 SINIRI: bar_stok_tuketimleri A1 ile gelen YENI bir tablodur. A1'den ONCE
-- tamamlanmis siparislerin tuketim kaydi hic olmaz; bunlari "bozuk" saymak
-- yanlis alarmdir (kullanici uyarisi 2026-09-20). Bu yuzden (b) ve (c)
-- kontrolleri yalnizca A1 uygulandiktan SONRA olusmus siparis/rezervasyon
-- satirlarina bakar. A1 isareti yoksa (migration uygulanmamis) bu iki kontrol
-- hic satir uretmez ve KAPSAM DISI olarak raporlanir.
a1 as (
  select max(a.server_timestamp) as t
    from public.erp_islem_audit a
   where a.entity_id = 'A1-GECIS-ISARETI'
),
u3 as (
  -- (a) kapanmis siparisin rezervasyonu hala aktif
  select 'U3a rezervasyon' as kaynak,
         r.id::text as anahtar,
         'siparis ' || s.durum::text || ' | rezervasyon aktif | ' || r.stok_kodu
           || ' ' || r.miktar::text as ayrinti,
         'BELIRSIZ: kapanmis siparisin rezervasyonu serbest birakilmamis' as karar
    from public.stok_rezervasyonlari r
    join public.bar_siparis_kalemleri k on k.id = r.siparis_kalem_id
    join public.bar_siparisleri s on s.id = k.siparis_id
   where r.durum = 'aktif' and s.durum::text in ('teslim_edildi', 'iptal')
  union all
  -- (b) kullanilmis rezervasyonun tuketim kaydi yok
  select 'U3b rezervasyon', r.id::text,
         'rezervasyon kullanildi | tuketim kaydi yok | ' || r.stok_kodu || ' ' || r.miktar::text,
         'BELIRSIZ: rezervasyon kullanildi ama bar_stok_tuketimleri satiri yok'
    from public.stok_rezervasyonlari r, a1
   where r.durum = 'kullanildi'
     and a1.t is not null and r.olusturma_zamani >= a1.t     -- A1 oncesi veri haric
     and not exists (select 1 from public.bar_stok_tuketimleri t where t.rezervasyon_id = r.id)
  union all
  -- (c) teslim edilmis siparis kaleminin tuketimi yok
  select 'U3c siparis', s.id::text,
         'siparis teslim_edildi | kalem ' || k.id::text || ' | tuketim yok',
         'BELIRSIZ: teslim edilmis kalemin stok tuketimi yazilmamis'
    from public.bar_siparisleri s
    join public.bar_siparis_kalemleri k on k.siparis_id = s.id, a1
   where s.durum::text = 'teslim_edildi' and k.rezerve_edildi is true
     and a1.t is not null and s.olusturma_zamani >= a1.t     -- A1 oncesi veri haric
     and not exists (select 1 from public.bar_stok_tuketimleri t where t.siparis_kalem_id = k.id)
),

-- ---------------------------------------------------------------------------
-- U4. ASIRI REZERVASYON — aktif rezerve toplami stogu asiyor
--     Bu durumda stok cikis korumasi TUM yazmalari reddeder: yeniden acilirsa
--     personel hata alir. Yeniden acmadan once cozumlenmelidir.
-- ---------------------------------------------------------------------------
u4 as (
  select 'U4 rezerve/stok' as kaynak,
         r.depo_id || ' / ' || r.stok_kodu as anahtar,
         'aktif rezerve ' || r.rezerve::text || ' | stok ' || coalesce(s.miktar, 0)::text as ayrinti,
         'BELIRSIZ: aktif rezervasyon stoktan fazla — stok yazmalari reddedilir' as karar
    from (select depo_id, stok_kodu, sum(miktar) as rezerve
            from public.stok_rezervasyonlari where durum = 'aktif'
           group by depo_id, stok_kodu) r
    left join public.stok s on s.depo_kodu = r.depo_id and s.urun_kodu = r.stok_kodu
   where r.rezerve > coalesce(s.miktar, 0)
),

-- ---------------------------------------------------------------------------
-- U5. SAYIM BUTUNLUGU
-- ---------------------------------------------------------------------------
u5 as (
  -- (a) detaysiz oturum: olusturma yarida kesilmis
  select 'U5a sayim' as kaynak, o.id::text as anahtar,
         'oturum ' || o.durum || ' | detay 0 | beklenen ' || coalesce(o.toplam_urun_sayisi, 0)::text as ayrinti,
         'BELIRSIZ: sayim oturumu var, detay satiri yok — olusturma yarida kalmis' as karar
    from public.sayim_oturumlari o
   where not exists (select 1 from public.sayim_detaylari d where d.oturum_id = o.id)
  union all
  -- (b) onaylanmis oturumda karara baglanmamis detay
  select 'U5b sayim', o.id::text,
         'oturum onaylandi | kararsiz detay ' || count(*)::text,
         'BELIRSIZ: onaylanmis sayimda uygulama durumu bos detay var'
    from public.sayim_oturumlari o
    join public.sayim_detaylari d on d.oturum_id = o.id
   where o.durum = 'onaylandi' and coalesce(d.uygulama_durumu, '') = ''
   group by o.id
  union all
  -- (c) kismi uygulama + bekleyen: BEKLENEN durum, engel degil (bilgi)
  select 'U5c sayim', o.id::text,
         'kismi uygulama | bekleyen detay ' || count(*) filter (where d.uygulama_durumu = 'bekliyor')::text,
         'KESIN: kismi uygulama beklenen durum — bekleyen duzeltme listesinden islenir'
    from public.sayim_oturumlari o
    join public.sayim_detaylari d on d.oturum_id = o.id
   where o.kismi_uygulandi is true
   group by o.id
  having count(*) filter (where d.uygulama_durumu = 'bekliyor') > 0
),

-- ---------------------------------------------------------------------------
-- U6. NEGATIF STOK
-- ---------------------------------------------------------------------------
u6 as (
  select 'U6 negatif stok' as kaynak, s.depo_kodu || ' / ' || s.urun_kodu as anahtar,
         'miktar ' || s.miktar::text as ayrinti,
         'BELIRSIZ: stok negatif' as karar
    from public.stok s where s.miktar < 0
),

hepsi as (
  select * from u1 union all select * from u2 union all select * from u3
  union all select * from u4 union all select * from u5 union all select * from u6
),
sayac as (select count(*) filter (where karar like 'BELIRSIZ%') as belirsiz, count(*) as toplam from hepsi)
-- Detay satirlari + EN SONDA tek karar satiri. Karar, satirlarla AYNI sorgudan
-- uretilir: ayri bir sorgu kopyalanmaz, dolayisiyla ikisi asla birbirinden
-- ayrisamaz.
select kaynak, anahtar, ayrinti, karar
  from (
    select 0 as sira, kaynak, anahtar, ayrinti, karar from hepsi
    union all
    select 1, 'KARAR', 'olculen satir ' || sayac.toplam::text, '',
           case when sayac.belirsiz = 0
                then 'YENIDEN ACMA: EVET — 0 belirsiz satir (YALNIZ OLCULEN KURALLAR; kapsam disi: '
                     || 'A1 oncesi bar tuketim kayitlari, hic kayit birakmamis islemler, '
                     || 'veritabani disi sistemler)'
                else 'YENIDEN ACMA: HAYIR — ' || sayac.belirsiz::text
                     || ' belirsiz satir var, once cozumleyin' end
      from sayac
  ) z
 order by z.sira, (z.karar like 'BELIRSIZ%') desc, z.kaynak, z.anahtar;
rollback;
