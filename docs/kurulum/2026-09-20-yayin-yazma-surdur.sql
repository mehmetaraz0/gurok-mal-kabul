-- ============================================================================
-- YAYIN PENCERESI — STOK YAZMALARINI SURDUR (2026-09-20)
-- ============================================================================
-- 2026-09-20-yayin-yazma-duraklat.sql ile kapatilan yazma yollarini geri acar.
-- Migration BASARILI olsa da OLMASA da calistirilir; aksi halde stok yazmalari
-- kapali kalir. Yetkiler A1'in (ve A1 oncesinin) verdigi hale dondurulur:
--   * stok_ekle 4 parametreli: her iki durumda da authenticated'a EXECUTE
--     (A1 uygulandiysa govde zaten ESKI_ISTEMCI dondurur, yazmaz)
--   * stok_ekle 5 parametreli: YALNIZ varsa (A1 uygulandiysa)
--   * stok_transfer, stok_hareketleri INSERT, stok INSERT/UPDATE
--
--   .\docs\kurulum\sql-uygula.ps1 -Dosya docs\kurulum\2026-09-20-yayin-yazma-surdur.sql
-- ============================================================================
begin;

grant execute on function public.stok_ekle(text, text, text, numeric) to authenticated;
do $$
begin
  if to_regprocedure('public.stok_ekle(text,text,text,numeric,integer)') is not null then
    execute 'grant execute on function public.stok_ekle(text, text, text, numeric, integer) to authenticated';
  end if;
end;
$$;
grant execute on function public.stok_transfer(text, text, text, text, numeric) to authenticated;
grant insert on table public.stok_hareketleri to authenticated;
grant insert, update on table public.stok to authenticated;

insert into public.erp_islem_audit (hotel_id, actor_user_id, actor_role, event_type,
                                    entity_type, entity_id, transaction_id, islem_detayi)
values (null, null, 'service_role', 'UPDATE', 'stok', 'A1-YAYIN-SURDURME', pg_current_xact_id()::text,
        jsonb_build_object('islem', 'yazma_surduruldu', 'dosya', '2026-09-20-yayin-yazma-surdur.sql'));

-- Son kosul: yazma yolu geri acildi mi? (A1 uygulandiysa 5 parametreli de acik olmali)
do $$
begin
  if not has_function_privilege('authenticated', 'public.stok_ekle(text,text,text,numeric)', 'EXECUTE')
     or not has_table_privilege('authenticated', 'public.stok_hareketleri', 'INSERT')
     or not has_table_privilege('authenticated', 'public.stok', 'UPDATE')
     or not has_function_privilege('authenticated', 'public.stok_transfer(text,text,text,text,numeric)', 'EXECUTE') then
    raise exception 'SON KOSUL: stok yazma yolu geri acilmadi.';
  end if;
  if to_regprocedure('public.stok_ekle(text,text,text,numeric,integer)') is not null
     and not has_function_privilege('authenticated', 'public.stok_ekle(text,text,text,numeric,integer)', 'EXECUTE') then
    raise exception 'SON KOSUL: A1 imzasi (5 parametre) authenticated icin kapali kaldi.';
  end if;
end;
$$;

commit;

\echo '== SURDURULDU. Yeni surumdeki ekranlar yazabilir (A1 sonrasi eski sekmeler ESKI_ISTEMCI alir).'
