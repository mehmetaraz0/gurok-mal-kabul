-- ============================================================================
-- PHASE 0 PREFLIGHT 2/5 — TABLO VE KOLON İZİNLERİ
-- ============================================================================
-- SALT-OKUMA. Hiçbir mutation içermez. Supabase SQL Editor'de çalıştırılabilir:
-- dosya TEK sonuç kümesi üretir (editör yalnız son sorgunun sonucunu gösterir).
--
-- Ham izin listesi binlerce satır olduğu ve editörde okunamadığı için burada
-- yalnızca KARAR GEREKTİREN satırlar dökülür:
--   * anon veya PUBLIC'e verilmiş HER izin  -> anomali, tek tek listelenir
--   * authenticated / service_role          -> yalnızca özet sayı
--   * rol üyelikleri ve varsayılan ACL'ler  -> az satır, tam listelenir
--
-- BEKLENEN: "ANOMALI" ile başlayan satır ÇIKMAMALI. 2026-08-09'da anon tüm
-- tablolardan alınmıştı (56 -> 0) ve varsayılan izinler de kapatılmıştı.
--
-- Rol üyeliği satırları önemlidir: authenticated başka bir role üyeyse, o
-- rolün izinlerini DEVRALIR ve tablo bazlı revoke tek başına yetmez.
-- ============================================================================

select * from (
  -- 1) anon / PUBLIC tablo izinleri — her satır bir anomalidir
  select 1 as sira,
         'ANOMALI: anon/PUBLIC tablo izni' as kategori,
         table_name                        as nesne,
         grantee                           as rol,
         privilege_type                    as ayrinti
  from information_schema.table_privileges
  where table_schema = 'public' and grantee in ('PUBLIC','anon')

  union all
  -- 2) anon / PUBLIC kolon izinleri — tablo revoke'unu delebilir
  select 2,
         'ANOMALI: anon/PUBLIC kolon izni',
         table_name || '.' || column_name,
         grantee,
         privilege_type
  from information_schema.column_privileges
  where table_schema = 'public' and grantee in ('PUBLIC','anon')

  union all
  -- 3) Rol üyelikleri — devralma zinciri. authenticated'ın üye olduğu her rol,
  --    o rolün izinlerini ona taşır.
  select 3,
         'ROL UYELIGI (devralma)',
         pg_get_userbyid(roleid)::text,
         pg_get_userbyid(member)::text,
         'uye'
  from pg_auth_members
  where pg_get_userbyid(member)::text in ('anon','authenticated','service_role')
     or pg_get_userbyid(roleid)::text  in ('anon','authenticated','service_role')

  union all
  -- 4) Varsayılan ACL'ler — YENİ oluşturulacak nesnelerin izni.
  --    Burada anon görünüyorsa, bundan sonra eklenecek her tablo açık doğar.
  select 4,
         'VARSAYILAN ACL (yeni nesneler)',
         coalesce(n.nspname, '(global)'),
         d.defaclrole::regrole::text,
         d.defaclobjtype::text || ' -> ' ||
           coalesce(array_to_string(d.defaclacl::text[], ', '), '(yok)')
  from pg_default_acl d
  left join pg_namespace n on n.oid = d.defaclnamespace

  union all
  -- 5) Özet — beklenen izinler. Sayı olarak, tek tek değil.
  select 5,
         'OZET: personel/servis izni (beklenen)',
         grantee,
         count(*)::text || ' tablo-izin satiri',
         ''
  from information_schema.table_privileges
  where table_schema = 'public' and grantee in ('authenticated','service_role')
  group by grantee
) x
order by sira, kategori, nesne, rol;
