-- ============================================================================
-- PMS FAZ 2 (KAT HİZMETLERİ) — YAYIN ÖNCESİ ÜRETİM PREFLIGHT'I (SALT OKUMA)
-- Tarih: 2026-09-11
-- ============================================================================
-- Nerede çalışır : Supabase SQL Editor, ÜRETİM. Tek bir SELECT'tir.
-- Ne yapar       : HİÇBİR ŞEY YAZMAZ. DDL yok, DML yok, GRANT yok. Çağrılan tek
--                  fonksiyon `public.pms_bugun()` (language sql stable, tabloya
--                  dokunmaz).
-- Ne zaman       : (1) Yayın planı onayından ÖNCE — karar girdisi.
--                  (2) Yayın penceresinde, Adım 1 migration'ından HEMEN ÖNCE.
-- Beklenen       : `durum = 'SAPMA'` olan satır YOK. Tek bir SAPMA yayını durdurur.
--                  `BILGI` satırları karar değil, kayıttır.
--
-- NE KANITLAMAZ  : Bu dosya migration'ın BAŞARIYLA UYGULANACAĞINI tek başına
--                  kanıtlamaz. Yalnız bilinen önkoşulları, çakışan nesneleri,
--                  migration'ın yerine yazdığı gövdeleri ve veri çelişkilerini
--                  ölçer. Uygulanabilirlik ancak güncel üretim dökümüne yapılan
--                  izole provada gösterilir (yayın planı, Aşama 0).
--
-- Beklenen değerlerin KAYNAĞI: 2026-09-07-post-pms-faz1-sema-dokumu.sql +
--   2026-09-08-pms-fonksiyon-acl-temizligi.sql, tek kullanımlık PostgreSQL 17
--   konteynerinde yüklenip ÖLÇÜLDÜ (2026-09-11). Döküm, 28/28 fonksiyon gövdesi
--   eşleşmesiyle üretimi temsil ettiği doğrulanmış tabandır.
--
-- ÇIKTISINI yayın kaydına OLDUĞU GİBİ yapıştırın.
-- ============================================================================

with
kontroller(sira, kod, kontrol, bulunan, beklenen, tur) as (values

-- ---------------------------------------------------------------------------
-- A) FAZ 2 NESNELERİ ÜRETİMDE HENÜZ OLMAMALI
-- ---------------------------------------------------------------------------
-- Varsa: bilinmeyen biri migration'ı (kısmen) uygulamış demektir. 6 Eylül
-- Phase 0 olayının tekrarı. Kim/ne zaman cevaplanmadan ilerlenmez.
  (10, 'A1', 'pms_housekeeping_gorevleri tablosu yok',
   (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relname = 'pms_housekeeping_gorevleri')::text, '0', 'esit'),
  (11, 'A2', 'public.pms_housekeeping_* fonksiyonu yok',
   (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname like 'pms\_housekeeping\_%')::text, '0', 'esit'),
  (12, 'A3', 'phase0_private.hk_* fonksiyonu yok',
   (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'phase0_private' and p.proname like 'hk\_%')::text, '0', 'esit'),
  (13, 'A4', 'pms_housekeeping_* tetikleyicisi yok',
   (select count(*) from pg_trigger t
     where not t.tgisinternal and t.tgname like 'pms\_housekeeping\_%')::text, '0', 'esit'),
  (14, 'A5', 'pms_housekeeping modül kaydı yok',
   (select count(*) from public.moduller where kod = 'pms_housekeeping')::text, '0', 'esit'),
  (15, 'A6', 'pms_odalar.temizlik_gorevi_id kolonu yok',
   (select count(*) from information_schema.columns
     where table_schema = 'public' and table_name = 'pms_odalar'
       and column_name = 'temizlik_gorevi_id')::text, '0', 'esit'),
  (16, 'A7', 'erp_islem_audit.islem_detayi kolonu yok',
   (select count(*) from information_schema.columns
     where table_schema = 'public' and table_name = 'erp_islem_audit'
       and column_name = 'islem_detayi')::text, '0', 'esit'),
  (17, 'A8', 'pms_oda_atamalari_id_oda_otel_key kısıtı yok',
   (select count(*) from pg_constraint
     where conname = 'pms_oda_atamalari_id_oda_otel_key')::text, '0', 'esit'),
  (18, 'A9', 'pms_odalar üzerinde phase0_islem_audit tetikleyicisi yok (migration kurar)',
   (select count(*) from pg_trigger t
     where t.tgrelid = 'public.pms_odalar'::regclass and not t.tgisinternal
       and t.tgname = 'phase0_islem_audit')::text, '0', 'esit'),

-- ---------------------------------------------------------------------------
-- B) MİGRATION ÖNKOŞULLARI (Adım 1 bölüm 0 + katalog varsayımları)
-- ---------------------------------------------------------------------------
  (20, 'B1', 'yetki motoru tabloları (moduller, yetki_matrisi, kullanicilar)',
   (select count(*) from unnest(array['public.moduller','public.yetki_matrisi','public.kullanicilar']) t
     where to_regclass(t) is not null)::text, '3', 'esit'),
  (21, 'B2', 'auth_* yardımcıları (4 imza)',
   (select count(*) from unnest(array['public.auth_yetki_var(text,text)','public.auth_otel_erisim(text)',
                                      'public.auth_erp_kullanicisi()','public.auth_tum_oteller()']) t
     where to_regprocedure(t) is not null)::text, '4', 'esit'),
  (22, 'B3', 'denetim altyapısı (şema + tablo + islem_audit + otel_degismez)',
   ((select count(*) from pg_namespace where nspname = 'phase0_private')
    + (case when to_regclass('public.erp_islem_audit') is not null then 1 else 0 end)
    + (case when to_regprocedure('phase0_private.islem_audit()') is not null then 1 else 0 end)
    + (case when to_regprocedure('phase0_private.otel_degismez()') is not null then 1 else 0 end))::text,
   '4', 'esit'),
  (23, 'B4', 'Faz 1 tabloları (pms_odalar, pms_oda_atamalari, pms_rezervasyonlar)',
   (select count(*) from unnest(array['public.pms_odalar','public.pms_oda_atamalari','public.pms_rezervasyonlar']) t
     where to_regclass(t) is not null)::text, '3', 'esit'),
  (24, 'B5', 'pms_odalar UNIQUE (id, otel_id) — sütun sırası birebir',
   (select count(*) from pg_constraint
     where conrelid = 'public.pms_odalar'::regclass and contype = 'u'
       and conkey = array[
         (select attnum from pg_attribute where attrelid = 'public.pms_odalar'::regclass and attname = 'id'),
         (select attnum from pg_attribute where attrelid = 'public.pms_odalar'::regclass and attname = 'otel_id')
       ]::smallint[])::text, '1', 'esit'),
  (25, 'B6', 'Faz 1 tutarlılık kısıtları (3 ad)',
   (select count(*) from pg_constraint
     where conname in ('pms_tutarlilik_oda','pms_tutarlilik_rezervasyon','pms_tutarlilik_atama'))::text,
   '3', 'esit'),
  (26, 'B7', 'moduller.kod benzersiz (ON CONFLICT hedefi)',
   (select count(*) from pg_index i
     where i.indrelid = 'public.moduller'::regclass and i.indisunique and i.indnkeyatts = 1
       and i.indkey[0] = (select attnum from pg_attribute
                           where attrelid = 'public.moduller'::regclass and attname = 'kod'))::text,
   '1', 'esit'),
  (27, 'B8', 'pms_odalar BEFORE tetikleyicileri (bölüm 13 sıra doğrulaması bunu şart koşar)',
   (select coalesce(string_agg(t.tgname, ',' order by t.tgname), '-') from pg_trigger t
     where t.tgrelid = 'public.pms_odalar'::regclass and not t.tgisinternal and (t.tgtype & 2) <> 0),
   'phase0_otel_degismez,pms_oda_envanter_kontrol,pms_oda_gecis,pms_odalar_guncelleme', 'esit'),
  (28, 'B9', 'pms_rezervasyonlar AFTER tetikleyicileri',
   (select coalesce(string_agg(t.tgname, ',' order by t.tgname), '-') from pg_trigger t
     where t.tgrelid = 'public.pms_rezervasyonlar'::regclass and not t.tgisinternal and (t.tgtype & 2) = 0),
   'phase0_islem_audit,pms_folio_otomatik_ac,pms_iptal_atama_serbest,pms_tutarlilik_rezervasyon', 'esit'),
  (29, 'B10', 'devre dışı bırakılmış tetikleyici (PMS + denetim tabloları)',
   (select count(*) from pg_trigger t join pg_class c on c.oid = t.tgrelid
     where not t.tgisinternal and t.tgenabled = 'D'
       and c.relname in ('pms_odalar','pms_rezervasyonlar','pms_oda_atamalari','erp_islem_audit'))::text,
   '0', 'esit'),
  (30, 'B11', 'pms_kullanim_durumu değerleri',
   (select string_agg(e.enumlabel, ',' order by e.enumsortorder) from pg_enum e
     join pg_type t on t.oid = e.enumtypid where t.typname = 'pms_kullanim_durumu'),
   'bos,dolu,bloke,ariza', 'esit'),
  (31, 'B12', 'pms_temizlik_durumu değerleri',
   (select string_agg(e.enumlabel, ',' order by e.enumsortorder) from pg_enum e
     join pg_type t on t.oid = e.enumtypid where t.typname = 'pms_temizlik_durumu'),
   'temiz,kirli,temizleniyor,kontrol_edildi', 'esit'),
  (32, 'B13', 'onburo kategorisinde en yüksek sira (mimari §16.1)',
   (select max(sira) from public.moduller where kategori = 'onburo')::text, '48', 'esit'),
  (33, 'B14', 'sira = 49 kullanılmıyor',
   (select count(*) from public.moduller where sira = 49)::text, '0', 'esit'),
  (34, 'B15', 'PostgreSQL >= 13 (pg_current_xact_id, gen_random_uuid)',
   (current_setting('server_version_num')::int >= 130000)::text, 'true', 'esit'),
  (35, 'B16', 'auth.uid() ve auth.role() var',
   (select count(*) from unnest(array['auth.uid()','auth.role()']) t
     where to_regprocedure(t) is not null)::text, '2', 'esit'),

-- ---------------------------------------------------------------------------
-- C) GÖVDE EŞİTLİĞİ — md5(prosrc)
-- ---------------------------------------------------------------------------
-- C1 KRİTİK: Adım 1 bölüm 22 `phase0_private.islem_audit()` fonksiyonunu
-- YERİNE YAZAR. Bu fonksiyon mal kabul, fatura, stok, bar ve PMS denetim
-- tetikleyicilerinin ORTAK gövdesidir. Üretimdeki gövde tabandan farklıysa
-- migration o farkı SESSİZCE siler.
-- C3-C9: migration bunlara dokunmaz ama davranışı bunlara DAYANIR
-- (SECURITY INVOKER oldukları için 2026-09-07 eşitlik dosyasının kapsamında
-- DEĞİLLER; burada ayrıca ölçülürler).
  (40, 'C1', 'phase0_private.islem_audit() — migration YERİNE YAZAR',
   coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('phase0_private.islem_audit()')), 'YOK'),
   'b6206c011206dd018d1b0fae64a8aff0', 'esit'),
  (41, 'C2', 'phase0_private.otel_degismez()',
   coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('phase0_private.otel_degismez()')), 'YOK'),
   '6f69b342e5add98f16b64a11b71bb39c', 'esit'),
  (42, 'C3', 'pms_check_in(uuid,uuid)',
   coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('public.pms_check_in(uuid,uuid)')), 'YOK'),
   '3798c9461390f18f97e537bd9be07612', 'esit'),
  (43, 'C4', 'pms_check_out(uuid)',
   coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('public.pms_check_out(uuid)')), 'YOK'),
   '6d6bb0ecbef41ff1a13fc437857f49fa', 'esit'),
  (44, 'C5', 'pms_oda_gecis()',
   coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('public.pms_oda_gecis()')), 'YOK'),
   '4002e118f13092343356717fcbb0b5c4', 'esit'),
  (45, 'C6', 'pms_oda_envanter_kontrol()',
   coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('public.pms_oda_envanter_kontrol()')), 'YOK'),
   'f60c8455b54b6d856b8e609f7cec95d4', 'esit'),
  (46, 'C7', 'pms_tutarlilik_oda()',
   coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('public.pms_tutarlilik_oda()')), 'YOK'),
   '7d18bfe7471ae71179810b06f1a16a9e', 'esit'),
  (47, 'C8', 'pms_tutarlilik_rezervasyon()',
   coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('public.pms_tutarlilik_rezervasyon()')), 'YOK'),
   '732c324f32cf777fdd5aa92ed623b6a3', 'esit'),
  (48, 'C9', 'pms_tutarlilik_atama()',
   coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('public.pms_tutarlilik_atama()')), 'YOK'),
   '789d08ad9ac20445e9ea266be7bba6cf', 'esit'),
  (49, 'C10', 'phase0_private.audit_immutable()',
   coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('phase0_private.audit_immutable()')), 'YOK'),
   '0f8eb62acdf5357fab41818977942130', 'esit'),

-- ---------------------------------------------------------------------------
-- D) TABAN (POST-PMS-FAZ1 + 2026-09-08 ACL temizliği)
-- ---------------------------------------------------------------------------
  (60, 'D1', 'public tablo sayısı',
   (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind = 'r')::text, '75', 'esit'),
  (61, 'D2', 'public politika sayısı',
   (select count(*) from pg_policy p join pg_class c on c.oid = p.polrelid
     join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public')::text, '234', 'esit'),
  (62, 'D3', 'kısıtlayıcı politika sayısı',
   (select count(*) from pg_policy p join pg_class c on c.oid = p.polrelid
     join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and not p.polpermissive)::text, '40', 'esit'),
  (63, 'D4', 'public pms_* fonksiyon sayısı',
   (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname like 'pms\_%')::text, '22', 'esit'),
  (64, 'D5', 'RLS kapalı public tablo',
   (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity)::text, '0', 'esit'),
  (65, 'D6', 'search_path pinsiz SECURITY DEFINER (public + phase0_private)',
   (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname in ('public','phase0_private') and p.prosecdef
       and (p.proconfig is null
            or not exists (select 1 from unnest(p.proconfig) k where k like 'search\_path=%')))::text,
   '0', 'esit'),
  (66, 'D7', 'anon tablo hakkı (public)',
   (select count(*) from information_schema.role_table_grants
     where table_schema = 'public' and grantee = 'anon')::text, '0', 'esit'),
  (67, 'D8', 'anon EXECUTE hakkı olan public fonksiyon',
   (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and has_function_privilege('anon', p.oid, 'EXECUTE'))::text, '0', 'esit'),
  (68, 'D9', 'pms_odalar authenticated tablo hakları (bölüm 27 bunları daraltır)',
   (select coalesce(string_agg(privilege_type, ',' order by privilege_type), '-')
      from information_schema.role_table_grants
     where table_schema = 'public' and table_name = 'pms_odalar' and grantee = 'authenticated'),
   'DELETE,INSERT,REFERENCES,SELECT,TRIGGER,TRUNCATE,UPDATE', 'esit'),
  (69, 'D10', 'FORCE RLS açık PMS/denetim tablosu (açıksa E satırları eksik sayar)',
   (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relforcerowsecurity
       and c.relname in ('pms_odalar','pms_rezervasyonlar','pms_oda_atamalari','kullanicilar','erp_islem_audit'))::text,
   '0', 'esit'),

-- ---------------------------------------------------------------------------
-- E) VERİ — yeni kısıtlarla ÇELİŞEN kayıtlar
-- ---------------------------------------------------------------------------
  (80, 'E1', 'temizleniyor durumunda oda (Adım 1 önkoşulu: >0 ise migration SERT DURUR)',
   (select count(*) from public.pms_odalar where temizlik_durumu = 'temizleniyor')::text, '0', 'esit'),
  (81, 'E2', 'giris_yapildi rezervasyon, aktif atama sayısı <> 1 (çıkış üreticisi ve check-out reddeder)',
   (select count(*) from (
      select r.id from public.pms_rezervasyonlar r
      left join public.pms_oda_atamalari a
        on a.rezervasyon_id = r.id and a.otel_id = r.otel_id and a.aktif
      where r.durum = 'giris_yapildi'
      group by r.id having count(a.id) <> 1) x)::text, '0', 'esit'),
  (82, 'E3', 'dolu oda, üzerinde giris_yapildi konaklaması yok',
   (select count(*) from public.pms_odalar o
     where o.kullanim_durumu = 'dolu'
       and not exists (select 1 from public.pms_oda_atamalari a
                         join public.pms_rezervasyonlar r on r.id = a.rezervasyon_id and r.otel_id = a.otel_id
                        where a.oda_id = o.id and a.otel_id = o.otel_id and a.aktif
                          and r.durum = 'giris_yapildi'))::text, '0', 'esit'),
  (83, 'E4', 'giris_yapildi konaklama, odası dolu değil (çıkış bekçisi reddeder)',
   (select count(*) from public.pms_rezervasyonlar r
      join public.pms_oda_atamalari a on a.rezervasyon_id = r.id and a.otel_id = r.otel_id and a.aktif
      join public.pms_odalar o on o.id = a.oda_id and o.otel_id = a.otel_id
     where r.durum = 'giris_yapildi' and o.kullanim_durumu <> 'dolu')::text, '0', 'esit'),
  (84, 'E5', 'aktif kullanıcılarda tekrarlanan auth_user_id (hk_aktor kimliği belirsizleşir)',
   (select count(*) from (select auth_user_id from public.kullanicilar
                           where aktif is true and auth_user_id is not null
                           group by auth_user_id having count(*) > 1) x)::text, '0', 'esit'),
  (85, 'E6', 'BILGI oda dağılımı (otel: boş-kirli / boş-hazır / dolu / bloke+arıza / pasif)',
   (select coalesce(string_agg(s, ' | ' order by s), 'oda yok') from (
      select o.otel_id::text || ': bos-kirli=' || count(*) filter (where o.aktif and o.kullanim_durumu = 'bos' and o.temizlik_durumu = 'kirli')
          || ' bos-hazir=' || count(*) filter (where o.aktif and o.kullanim_durumu = 'bos' and o.temizlik_durumu in ('temiz','kontrol_edildi'))
          || ' dolu=' || count(*) filter (where o.aktif and o.kullanim_durumu = 'dolu')
          || ' bloke+ariza=' || count(*) filter (where o.aktif and o.kullanim_durumu in ('bloke','ariza'))
          || ' pasif=' || count(*) filter (where not o.aktif) as s
        from public.pms_odalar o group by o.otel_id) z),
   null, 'bilgi'),
  (86, 'E7', 'BILGI dolu odalardan temizliği kirli olan (misafir odada; çıkışta yine kirli olur)',
   (select count(*) from public.pms_odalar where aktif and kullanim_durumu = 'dolu' and temizlik_durumu = 'kirli')::text,
   null, 'bilgi'),
  (87, 'E8', 'BILGI bugün veya daha önce planlı çıkışı olan giris_yapildi konaklama',
   (select count(*) from public.pms_rezervasyonlar r
     where r.durum = 'giris_yapildi' and r.cikis_tarihi <= public.pms_bugun(r.otel_id))::text,
   null, 'bilgi'),
  (88, 'E9', 'BILGI erp_islem_audit satır sayısı / son kayıt (duman testi karşılaştırması)',
   (select count(*)::text || ' / ' || coalesce(max(server_timestamp)::text, '-') from public.erp_islem_audit),
   null, 'bilgi'),

-- ---------------------------------------------------------------------------
-- F) YETKİ ENVANTERİ — modül etkinleştirme kararı için (BILGI)
-- ---------------------------------------------------------------------------
-- Kişi adı dökülmez; yalnız rol adı ve sayılar.
  (90, 'F1', 'BILGI pms_rezervasyon kayit/tam rolleri (check-out + çıkış üreticisi bunu ister)',
   (select coalesce(string_agg(r.ad || '=' || ym.yetki::text, '; ' order by r.ad), '-')
      from public.yetki_matrisi ym join public.roller r on r.id = ym.rol_id
      join public.moduller m on m.id = ym.modul_id
     where m.kod = 'pms_rezervasyon' and ym.yetki::text in ('kayit','tam')),
   null, 'bilgi'),
  (91, 'F2', 'BILGI yetki_yonetimi tam rolleri (yetki ekranından modül/rol ayarı yapabilir)',
   (select coalesce(string_agg(r.ad, '; ' order by r.ad), '-')
      from public.yetki_matrisi ym join public.roller r on r.id = ym.rol_id
      join public.moduller m on m.id = ym.modul_id
     where m.kod = 'yetki_yonetimi' and ym.yetki::text = 'tam'),
   null, 'bilgi'),
  (92, 'F3', 'BILGI aktif roller (kat hizmeti çalışanı/şefi rolü seçimi için)',
   (select coalesce(string_agg(ad, '; ' order by sira, ad), '-') from public.roller where aktif is true),
   null, 'bilgi'),
  (93, 'F4', 'BILGI aktif ERP kullanıcısı: otel atamalı / tüm oteller / otelsiz (otelsiz görev alamaz)',
   (select count(*) filter (where otel_id is not null and tum_oteller is not true)::text || ' / '
        || count(*) filter (where tum_oteller is true)::text || ' / '
        || count(*) filter (where otel_id is null and tum_oteller is not true)::text
      from public.kullanicilar where aktif is true and auth_user_id is not null),
   null, 'bilgi'),
  (94, 'F5', 'BILGI event trigger listesi (ensure_rls bekleniyor)',
   (select coalesce(string_agg(evtname || ':' || evtenabled::text, ', ' order by evtname), '-') from pg_event_trigger),
   null, 'bilgi'),
  (95, 'F6', 'BILGI sunucu sürümü',
   current_setting('server_version'), null, 'bilgi')
)
select sira, kod, kontrol, bulunan, beklenen,
       case when tur = 'bilgi' then 'BILGI'
            when bulunan is not distinct from beklenen then 'GECTI'
            else 'SAPMA' end as durum
  from kontroller
 order by sira;

-- ============================================================================
-- YORUMLAMA
-- ============================================================================
-- A*  SAPMA : Faz 2 nesnesi zaten var. DUR. Kim uyguladı sorusu cevaplanmadan
--             ilerlenmez; migration idempotent olsa bile kısmi/yabancı uygulama
--             "zaten var" diye kabul EDİLMEZ.
-- B*  SAPMA : Migration kendi önkoşul/doğrulama bloğunda ya da bölüm 13 tetikleyici
--             sırası kontrolünde duracaktır. DUR, farkı raporla.
-- C1  SAPMA : Ortak denetim fonksiyonu tabandan farklı. Migration o farkı SİLER.
--             DUR; üretim gövdesi alınmadan ve Adım 1 bölüm 22'ye yansıtılmadan
--             yayın yapılmaz.
-- C2-C10 SAPMA: Faz 2 testleri bu gövdelerle koşmadı. DUR, güncel dökümle prova.
-- D*  SAPMA : Üretim test edilen tabandan farklı. DUR; eşitlik dosyası ve güncel
--             döküm ile farkı belirle. Sayıyı zorla eşitleme.
-- E1  SAPMA : Odalar operasyonel olarak tamamlanmadan (eski ekrandan temiz'e
--             alınmadan) migration çalışmaz. Bu, yayın penceresinden ÖNCE
--             resepsiyonun yapacağı iştir; SQL ile düzeltilmez.
-- E2-E4 SAPMA: Önceden var olan tutarsızlık. Migration'dan bağımsız olarak o
--             konaklamaların çıkışı reddedilir. Raporla, yayın öncesi karar al.
-- E5  SAPMA : Kimlik belirsizliği. Kat hizmeti aktörü yanlış kişiye çözülebilir. DUR.
-- ============================================================================
