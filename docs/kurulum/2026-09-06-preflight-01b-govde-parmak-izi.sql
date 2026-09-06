-- ============================================================================
-- PREFLIGHT 01b — SÜRÜM BAĞIMSIZ GÖVDE PARMAK İZİ
-- ============================================================================
-- SALT-OKUMA. Tek sonuç kümesi üretir.
--
-- NEDEN 01'İN YERİNE BU:
-- 01, parmak izi olarak md5(pg_get_functiondef(oid)) kullanıyordu.
-- pg_get_functiondef gövdeyi SUNUCUNUN biçimlendiricisinden geçirerek üretir
-- ve çıktısı PostgreSQL minor sürümüne duyarlıdır. Üretim 17.6, doğrulama
-- konteyneri 17.11; bu yüzden döküm kusursuz olsa bile 26 fonksiyonun 25'i
-- "farklı" görünüyordu. Ölçüm aracının kusuruydu, dökümün değil.
--
-- prosrc, gövdenin HAM metnidir: sunucu biçimlendirmesi yok, sürüm duyarlılığı
-- yok. Karşılaştırma için doğru primitif budur.
--
-- Yapılandırma (SECURITY DEFINER, search_path, volatilite, imza) ayrı
-- sütunlarda tutulur — hash'e karıştırılmaz ki sapma çıktığında NEYİN
-- değiştiği görünsün.
--
-- KULLANIM: erp SQL Editor'de çalıştır, çıktının tamamını ver.
-- Çıktı 2026-09-06-staging-esitlik-dogrulama.sql içindeki tabana işlenecek.
-- ============================================================================

select p.oid::regprocedure::text                        as imza,
       p.prosecdef                                      as secdef,
       coalesce(array_to_string(p.proconfig, ', '), '(yok)') as ayarlar,
       p.provolatile                                    as volatilite,
       md5(p.prosrc)                                    as govde_md5,
       length(p.prosrc)                                 as govde_uzunluk
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.prokind = 'f'
  -- 01 ile AYNI kapsam: ayrıcalıklı olan her şey + auth yardımcıları.
  -- Kapsamı burada sabitliyoruz ki eşitlik kontrolü "fazla fonksiyon" için
  -- de aynı filtreyi kullanabilsin; aksi hâlde ai_q_* gibi meşru INVOKER
  -- fonksiyonlar yanlış alarm üretir.
  -- stok_ekle / stok_transfer INVOKER olduklari icin ilk iki kosula
  -- takilmaz; Phase 0 onlarin search_path ini pinledigi icin kapsamdalar.
  and (p.prosecdef
       or p.proname like 'auth\_%'
       or p.proname in ('stok_ekle','stok_transfer'))
order by p.oid::regprocedure::text;
