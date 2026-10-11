-- ============================================================================
-- BAG GERI YAZMA — insan tarafindan INCELENMIS 12 eslesme
-- Tasarim: docs/superpowers/specs/2026-10-11-talep-siparis-bagi-design.md §10
--
-- NEDEN: 7 bagsiz talebin 5'i GERCEKTEN siparis edilmisti; eski akis siparisi
-- yaziyor ama BAGI kaydetmiyordu (kusurun kendisi). Aday eslesme sondasi
-- (2026-10-11-talep-siparis-aday-eslesme-sondasi.sql) her biri icin AYNI GUN
-- ve TAM MIKTAR eslesen siparisleri gosterdi; ozellikle 1f80e26a'nin 10
-- kaleminin 8 ayri firmanin 8 ayri siparisine dagilmasi, ekranin firma bazli
-- gruplama davranisinin birebir izidir.
--
-- Asagidaki liste SONDA CIKTISINDAN insan incelemesiyle secildi. Otomatik
-- eslestirme YOK: her satir elle onaylandi.
--
-- KAPSAM DISI BIRAKILANLAR (bilincli, dokunulmuyor):
--   * YIY03000010 PARMESAN TOZ (1f80e26a) — tek aday C00091138 ve o siparis
--     IPTAL. Iptal siparisin bagi sayilmaz; kalem haklı olarak acik gorunur.
--     Ustelik kapi, iptal siparise bag yazarken de kotayi tuketir.
--   * YIY04000020 CARTE DOR cifti (49a7bab2 + c06e4939) — ikisi de AYNI
--     siparisi (C00091144, 10 KTU) gosteriyor, talepler 11 + 10 = 21 KTU.
--     Siparisin hangi talebi karsiladigi INSAN BILGISI; yanlis bag yazmak
--     sessiz bir yalan olur.
--   * 0f3febe3 ve 86c05d06 (dept 100, Agustos) — HIC adayi yok, siparis
--     edilmemis. Yeni gorunumde acik gorunmeleri DOGRU.
--
-- BU DOSYA URETIME UYGULANMADI.
-- SIRA: alti migration'dan SONRA kosar (yayin paketi adim 8).
-- ============================================================================

-- 0) ONKOSULLAR — bag altyapisi kurulu olmali, yoksa bu dosyanin anlami yok.
do $$
begin
  if to_regclass('public.talep_siparis_baglari') is null then
    raise exception 'ONKOSUL: talep_siparis_baglari yok. Once alti migration uygulanmali.';
  end if;
  if not exists (select 1 from pg_trigger
                  where tgname = 'tsb_inv_ekle' and tgrelid = 'public.talep_siparis_baglari'::regclass) then
    raise exception 'ONKOSUL: tsb_inv_ekle tetikleyicisi yok. INV kapisi olmadan geri yazma YAPILMAZ.';
  end if;
end;
$$;

begin;

-- 1) INCELENMIS ESLESME LISTESI (talep, urun, siparis, beklenen miktar, birim)
create temporary table _geri_yazma (
  talep_id        uuid not null,
  urun_kodu       text not null,
  siparis_no      text not null,
  beklenen_miktar numeric(12,3) not null,
  beklenen_birim  text not null
) on commit drop;

insert into _geri_yazma values
  -- 9a109899 · DEPO · 2026-07-09
  ('9a109899-75ad-4a5c-a06d-4bf839447baf','YIY01000002','C00091129',   69.000,'KG'),
  ('9a109899-75ad-4a5c-a06d-4bf839447baf','YIY06000001','C00091130', 1500.000,'KG'),
  -- 1f80e26a · DEPO · 2026-07-15 (PARMESAN kapsam disi)
  ('1f80e26a-1eb8-449e-885a-1807f8ada01d','YIY03000001','C00091136',    7.000,'TNK'),
  ('1f80e26a-1eb8-449e-885a-1807f8ada01d','YIY03000002','C00091139',  180.000,'KG'),
  ('1f80e26a-1eb8-449e-885a-1807f8ada01d','YIY03000004','C00091139',   20.000,'KG'),
  ('1f80e26a-1eb8-449e-885a-1807f8ada01d','YIY03000005','C00091139',   50.000,'KG'),
  ('1f80e26a-1eb8-449e-885a-1807f8ada01d','YIY03000006','C00091140',  100.000,'KG'),
  ('1f80e26a-1eb8-449e-885a-1807f8ada01d','YIY03000007','C00091139',   38.000,'KG'),
  ('1f80e26a-1eb8-449e-885a-1807f8ada01d','YIY03000008','C00091139',   20.000,'KG'),
  ('1f80e26a-1eb8-449e-885a-1807f8ada01d','YIY03000009','C00091135',   18.000,'KG'),
  ('1f80e26a-1eb8-449e-885a-1807f8ada01d','YIY11000005','C00091137',  120.000,'KG'),
  -- 72f378c0 · ANA_MUTFAK · 2026-07-30
  ('72f378c0-9269-4f71-85bf-cfc605ea2a37','YIY06000010','C00091145',   11.000,'KG');

-- 2) DOGRULAMA — tek bir uyusmazlikta TUM islem geri alinir.
--    Sessiz atlama YOK: her kontrol sayiyi karsilastirir ve hata firlatir.
do $$
declare
  v_liste int; v_kalem int; v_hata text;
begin
  select count(*) into v_liste from _geri_yazma;
  if v_liste <> 12 then
    raise exception 'LISTE: 12 satir beklenirken % satir var', v_liste;
  end if;

  -- 2a) Her satir TAM OLARAK bir talep kalemine cozulmeli.
  select string_agg(g.talep_id::text || '/' || g.urun_kodu || ' -> ' || c.n, '; ')
    into v_hata
    from _geri_yazma g
    cross join lateral (select count(*) as n
                          from public.satin_alma_talep_kalemleri tk
                         where tk.talep_id = g.talep_id
                           and tk.urun_kodu = g.urun_kodu) c
   where c.n <> 1;
  if v_hata is not null then
    raise exception 'KALEM COZULMEDI (1 beklenirken): %', v_hata;
  end if;

  -- 2b) Miktar ve birim, sondada gorulen degerle BIREBIR tutmali.
  select string_agg(g.urun_kodu || ': kalem ' || tk.miktar || ' ' || tk.birim ||
                    ' <> liste ' || g.beklenen_miktar || ' ' || g.beklenen_birim, '; ')
    into v_hata
    from _geri_yazma g
    join public.satin_alma_talep_kalemleri tk
      on tk.talep_id = g.talep_id and tk.urun_kodu = g.urun_kodu
   where tk.miktar <> g.beklenen_miktar or tk.birim <> g.beklenen_birim;
  if v_hata is not null then
    raise exception 'MIKTAR/BIRIM UYUSMAZ: %', v_hata;
  end if;

  -- 2c) Siparis var olmali ve IPTAL OLMAMALI (iptal bagin anlamini bozar).
  select string_agg(g.siparis_no || ': ' || coalesce(s.durum::text,'<yok>'), '; ')
    into v_hata
    from _geri_yazma g
    left join public.siparisler s on s.siparis_no = g.siparis_no
   where s.siparis_no is null or s.durum::text = 'iptal';
  if v_hata is not null then
    raise exception 'SIPARIS YOK veya IPTAL: %', v_hata;
  end if;

  -- 2d) Siparisin oteli talebin oteliyle ayni olmali.
  select string_agg(g.siparis_no || ': siparis ' || s.otel_id::text ||
                    ' <> talep ' || t.otel_id::text, '; ')
    into v_hata
    from _geri_yazma g
    join public.siparisler s on s.siparis_no = g.siparis_no
    join public.satin_alma_talepleri t on t.id = g.talep_id
   where s.otel_id <> t.otel_id;
  if v_hata is not null then
    raise exception 'OTEL UYUSMAZ: %', v_hata;
  end if;

  -- 2e) Bu kalemlerde ONCEDEN bag olmamali (mukerrer geri yazma kalkani).
  select count(*) into v_kalem
    from _geri_yazma g
    join public.satin_alma_talep_kalemleri tk
      on tk.talep_id = g.talep_id and tk.urun_kodu = g.urun_kodu
    join public.talep_siparis_baglari b on b.talep_kalem_id = tk.id;
  if v_kalem > 0 then
    raise exception 'ZATEN BAG VAR: % satir. Geri yazma IKINCI KEZ kosulmaz.', v_kalem;
  end if;
end;
$$;

-- 3) YAZMA — miktar talep kaleminin KENDI biriminde, donusum YOK (carpan null).
--    INV kapilari (tsb_inv_ekle, ENABLE ALWAYS) burada da korur: asim olursa
--    islem geri alinir.
insert into public.talep_siparis_baglari
  (otel_id, talep_id, talep_kalem_id, siparis_no, urun_kodu,
   miktar, hedef_birim, kaynak_miktar, kaynak_birim, carpan, olusturan_ad)
select t.otel_id, t.id, tk.id, g.siparis_no, tk.urun_kodu,
       tk.miktar, tk.birim, tk.miktar, tk.birim, null,
       'geri-yazma-2026-10-11'
  from _geri_yazma g
  join public.satin_alma_talepleri t on t.id = g.talep_id
  join public.satin_alma_talep_kalemleri tk
    on tk.talep_id = g.talep_id and tk.urun_kodu = g.urun_kodu;

-- 4) YAZMA SONRASI DOGRULAMA — beklenen sonuc olusmadiysa geri al.
do $$
declare v_bag int; v_kalan int;
begin
  select count(*) into v_bag from public.talep_siparis_baglari
   where olusturan_ad = 'geri-yazma-2026-10-11';
  if v_bag <> 12 then
    raise exception 'YAZILAN BAG SAYISI: 12 beklenirken %', v_bag;
  end if;

  -- Bu 12 kalemin KALANI sifir olmali (tam karsilama).
  select count(*) into v_kalan
    from _geri_yazma g
    join public.satin_alma_talep_kalemleri tk
      on tk.talep_id = g.talep_id and tk.urun_kodu = g.urun_kodu
   where tk.miktar <> (select coalesce(sum(b.miktar), 0)
                         from public.talep_siparis_baglari b
                         join public.siparisler s on s.siparis_no = b.siparis_no
                        where b.talep_kalem_id = tk.id
                          and s.durum <> 'iptal'
                          and b.hedef_birim = tk.birim);
  if v_kalan > 0 then
    raise exception 'KALAN SIFIR DEGIL: % kalemde tam karsilama olusmadi', v_kalan;
  end if;
end;
$$;

commit;

-- ============================================================================
-- UYGULAMA SONRASI BEKLENEN DURUM
--   * 12 bag satiri (`olusturan_ad = 'geri-yazma-2026-10-11'`)
--   * 9a109899, 1f80e26a (PARMESAN haric) ve 72f378c0 kalemleri gorunumde YOK
--   * Gorunumde ACIK kalanlar, bilincli olarak:
--       PARMESAN TOZ 10 KG · CARTE DOR 11 + 10 KTU · dept 100'un 2 kalemi
--
-- GERI ALMA
--   begin;
--   delete from public.talep_siparis_baglari
--    where olusturan_ad = 'geri-yazma-2026-10-11';
--   commit;
-- Bag gecmisini silmek normalde YASAK (§7 K7: duzeltme yolu durum='iptal'),
-- ancak bu satirlar gercek bir is akisindan degil GERI YAZMADAN dogdu ve
-- `olusturan_ad` ile tekil olarak isaretli; yanlis eslesme cikarsa tek
-- guvenli duzeltme budur.
-- ============================================================================
