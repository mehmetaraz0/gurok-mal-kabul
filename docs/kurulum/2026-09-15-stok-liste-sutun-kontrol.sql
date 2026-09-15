-- ============================================================================
-- STOK LISTE/OZET MIGRATION'I — SUTUN KONTROLU (SALT OKUMA)
-- Tarih: 2026-09-15
-- ============================================================================
-- Migration'in ADIYLA kullandigi her sutunun uretimde var oldugunu dogrular.
-- Hicbir sey yazmaz. Eksik varsa exception firlatir: cikis kodu 0 DEGILDIR.
-- ============================================================================

do $kontrol$
declare
  v_eksik text := '';
  r record;
  gerekli text[][] := array[
    ['stok', 'otel_id'], ['stok', 'depo_kodu'], ['stok', 'urun_kodu'],
    ['stok', 'miktar'], ['stok', 'guncelleme_tarihi'],
    ['urunler', 'kod'], ['urunler', 'ad'], ['urunler', 'birim'],
    ['stok_minimumlar', 'urun_kodu'], ['stok_minimumlar', 'min_miktar'],
    ['stok_hareketleri', 'urun_kodu'], ['stok_hareketleri', 'tip'],
    ['stok_hareketleri', 'miktar'], ['stok_hareketleri', 'tarih'],
    ['stok_hareketleri', 'aciklama']
  ];
begin
  for i in 1 .. array_length(gerekli, 1) loop
    if not exists (
      select 1 from information_schema.columns
       where table_schema = 'public'
         and table_name = gerekli[i][1]
         and column_name = gerekli[i][2]
    ) then
      v_eksik := v_eksik || gerekli[i][1] || '.' || gerekli[i][2] || ' ';
    end if;
  end loop;

  if v_eksik <> '' then
    raise exception 'EKSIK SUTUN: %', v_eksik;
  end if;
  raise notice 'TUM SUTUNLAR VAR — migration uygulanabilir.';
end
$kontrol$;

-- Tiplerin de beklenene uydugunu goz ile gorelim.
select table_name as tablo, column_name as sutun, data_type as tip
  from information_schema.columns
 where table_schema = 'public'
   and (
     (table_name = 'stok' and column_name in ('otel_id','depo_kodu','urun_kodu','miktar','guncelleme_tarihi'))
  or (table_name = 'urunler' and column_name in ('kod','ad','birim'))
  or (table_name = 'stok_minimumlar' and column_name in ('urun_kodu','min_miktar'))
  or (table_name = 'stok_hareketleri' and column_name in ('urun_kodu','tip','miktar','tarih','aciklama'))
   )
 order by 1, 2;
