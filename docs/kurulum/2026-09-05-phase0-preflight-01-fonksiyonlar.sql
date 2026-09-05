-- ============================================================================
-- PHASE 0 PREFLIGHT 1/5 — FONKSIYON KATALOGU
-- ============================================================================
-- SALT-OKUMA. Hicbir mutation icermez. Supabase SQL Editor'de calistirilabilir:
-- dosya TEK sonuc kumesi uretir (editor yalniz son sorgunun sonucunu gosterir).
--
-- Dosya adlarindan cikarilan kronoloji degil, GERCEK etkin durum.
-- Bakilacaklar: prosecdef (DEFINER mi), proconfig (search_path acik mi),
-- owner, ve anon/authenticated EXECUTE izinleri.
--
-- Ciktiyi ozel tutun: fonksiyon tanimlari ve politika ifadeleri is mantigi icerir.
-- Satir verisi, PIN, hash, JWT veya kimlik bilgisi SECILMEZ.
-- ============================================================================

select p.oid::regprocedure                             as imza,
       pg_get_userbyid(p.proowner)                      as sahip,
       p.prosecdef                                      as security_definer,
       coalesce(array_to_string(p.proconfig, ', '), '(yok)') as ayarlar,
       p.provolatile                                    as volatilite,
       has_function_privilege('anon', p.oid, 'EXECUTE')          as anon_calistirabilir,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') as personel_calistirabilir,
       has_function_privilege('service_role', p.oid, 'EXECUTE')  as servis_calistirabilir,
       coalesce(array_to_string(p.proacl::text[], ', '), 'NULL (varsayilan PUBLIC)') as acl,
       md5(pg_get_functiondef(p.oid))                   as tanim_parmak_izi
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname in ('public', 'phase0_private')
  and p.prokind = 'f'
  and (p.prosecdef
       or p.proname like 'auth\_%'
       or p.proname in ('stok_ekle','stok_transfer','talep_karar_ver',
                        'talep_siparise_donustur','fatura_kaydet','mal_kabul_kaydet',
                        'teklif_talebi_olustur','siparis_yeniden_yonlendir',
                        'bar_siparis_olustur','bar_siparis_iptal',
                        'bar_siparis_teslim_et','bar_siparis_durum_guncelle'))
order by p.prosecdef desc, p.oid::regprocedure::text;
