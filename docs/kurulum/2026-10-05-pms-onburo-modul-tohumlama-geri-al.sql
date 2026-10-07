-- ===========================================================================
-- PMS — Ön Büro modül/yetki tohumlamasının GERİ ALINMASI
-- ===========================================================================
-- Eşi: 2026-10-05-pms-onburo-modul-tohumlama.sql
--
-- SABİT ÇİFT LİSTESİ KULLANMAZ. Sebebi: kurulum `on conflict do nothing` ile
-- çalıştığı için önceden var olan satırlar EKLENMEMİŞ olabilir; sabit listeyi
-- silmek başkasının yetkisini kaldırırdı.
--
-- Kurulum eklediği her satırı `guncelleyen` alanına şu damgayı yazarak imzalar:
--     tohum:pms-onburo:<uygulama_id>@<uygulama_zamani>#<yazilan_yetki>
-- Geri alma YALNIZ bu damganın kimlik kısmı TAM EŞLEŞEN satırlara bakar.
--
-- Bir satır ancak şu iki koşul da sağlanırsa silinir:
--   (a) `guncelleme_tarihi` damgadaki uygulama zamanıyla AYNI, ve
--   (b) `yetki` damgadaki yazılan seviyeyle AYNI.
-- Ölçüldü: yetki-yonetimi.html düzenlemesi `guncelleyen`'i yazmaz ama
-- `guncelleme_tarihi`'ni günceller ve `yetki`'yi değiştirir.
--
--   * (a) tutmuyorsa  -> satır SONRADAN DEĞİŞTİRİLMİŞ: KORUNUR, raporlanır.
--   * (b) tutmuyorsa  -> ÇELİŞKİ: HİÇBİR ŞEY SİLİNMEZ, işlem durur, raporlanır.
--
-- PMS-S2: kimlik ZORUNLU ve GEÇERLİ UUID olmalı. Eşleştirme LIKE deseniyle
--   değil TAM EŞİTLİKLE yapılır; `%`, `_` veya bozuk UUID hiçbir silme yapmaz.
-- PMS-S3: karar okuması ile silme arasına EŞ ZAMANLI düzenleme giremez:
--   fotoğraf `for update of ym` ile KİLİTLİ alınır ve DELETE güncel satırın
--   damga/seviye/zaman alanlarını TEKRAR denetler.
--
-- Modül satırları KALDIRILMAZ: aynı satırlar PMS migration'larından da gelir ve
-- başka kurulumlarda zaten bulunabilir. Silmek yabancı anahtar ve başka
-- rollerin yetki kaybı riski taşır. İstenirse ayrı ve açık kararla kaldırılır.
--
-- ÇALIŞTIRMA: dosyanın tamamını olduğu gibi verin. Kimlik satırı `begin;`ten
-- SONRA olduğu için dışarıdan bir işlemle sarmaya GEREK YOKTUR (PMS-S1).
-- ===========================================================================

begin;

-- --- UYGULAMA KİMLİĞİ — zorunlu, geçerli UUID -----------------------------
-- Kurulum çıktısındaki "GERI ALMA ICIN UYGULAMA KIMLIGI" değerini yazın
-- (aşağıdaki satırın başındaki `--` işaretini silip id'yi değiştirin):

--   set local app.pms_uygulama_id = '00000000-0000-0000-0000-000000000000';

-- Verilmezse veya geçerli UUID değilse hiçbir satıra dokunulmadan HATA verilir.

do $$
declare
  v_ham     text := current_setting('app.pms_uygulama_id', true);
  v_id      uuid;
  v_imza    text;
  v_catisma text;
  v_degisen text;
  v_silinen int;
  v_aday    int;
begin
  if v_ham is null or btrim(v_ham) = '' then
    raise exception
      'UYGULAMA KIMLIGI VERILMEDI. Dosyadaki (begin sonrasi) satiri acin: '
      '"set local app.pms_uygulama_id = ''<kurulum ciktisindaki id>'';" '
      'Hicbir satira dokunulmadi.'
      using errcode = '22023';
  end if;

  -- PMS-S2: UUID dogrulamasi. '%', '_', bozuk metin burada DUSER; LIKE
  -- desenine kullanici girdisi HIC gecmez.
  begin
    v_id := btrim(v_ham)::uuid;
  exception when others then
    raise exception
      'GECERSIZ UYGULAMA KIMLIGI: % — gecerli bir UUID olmali. Joker karakter '
      '(%% veya _) kimlik DEGILDIR. Hicbir satira dokunulmadi.', v_ham
      using errcode = '22023';
  end;

  -- Damganin kimlik kismi: TAM ESITLIK ile eslesir (desen yok).
  v_imza := 'tohum:pms-onburo:' || v_id::text;

  create temporary table pms_geri (
    id uuid, rol text, modul text,
    guncelleyen text,
    mevcut_yetki text, beklenen_yetki text,
    mevcut_zaman timestamptz, beklenen_zaman timestamptz
  ) on commit drop;

  -- PMS-S3: satirlar KILITLENEREK okunur. Es zamanli bir oturum duzenleme
  -- yapmissa `for update` onun commit'ini bekler ve fotograf GUNCEL degerle
  -- alinir; boylece eski fotografla silme olmaz.
  insert into pms_geri
  select ym.id, r.kod, m.kod, ym.guncelleyen,
         ym.yetki::text,
         split_part(ym.guncelleyen, '#', 2),
         ym.guncelleme_tarihi,
         (split_part(split_part(ym.guncelleyen, '#', 1), '@', 2))::timestamptz
  from public.yetki_matrisi ym
  join public.roller   r on r.id = ym.rol_id
  join public.moduller m on m.id = ym.modul_id
  where split_part(ym.guncelleyen, '@', 1) = v_imza
  for update of ym;

  select count(*) into v_aday from pms_geri;
  if v_aday = 0 then
    raise notice 'Bu uygulama kimligine ait imzali satir YOK (id=%). '
                 'Hicbir sey silinmedi.', v_id;
    return;
  end if;

  -- (b) ÇELİŞKİ: zaman aynı ama seviye farklı -> hiçbir şey silinmez.
  select string_agg(rol || '/' || modul || ': mevcut=' || mevcut_yetki
                    || ' damga=' || beklenen_yetki, ', ' order by rol, modul)
    into v_catisma
  from pms_geri
  where mevcut_zaman = beklenen_zaman and mevcut_yetki <> beklenen_yetki;
  if v_catisma is not null then
    raise exception
      'CELISKI: imzali satirin seviyesi damgadan farkli, uygulama zamani ise ayni. '
      'HICBIR SATIR SILINMEDI. Elle inceleyin: %', v_catisma
      using errcode = '23514';
  end if;

  -- (a) SONRADAN DEĞİŞTİRİLMİŞ (eş zamanlı düzenleme dahil): korunur.
  select string_agg(rol || '/' || modul || ': yetki=' || mevcut_yetki
                    || ' guncelleme=' || mevcut_zaman::text, ', ' order by rol, modul)
    into v_degisen
  from pms_geri
  where mevcut_zaman <> beklenen_zaman;
  if v_degisen is not null then
    raise notice 'SONRADAN DEGISTIRILMIS, KORUNDU (silinmedi): %', v_degisen;
  end if;

  -- Yalnız bu uygulamada gerçekten eklenen VE değiştirilmemiş satırlar.
  -- PMS-S3: DELETE guncel satirin damga/seviye/zaman alanlarini TEKRAR
  -- denetler; fotograf ile satir arasinda fark varsa silmez.
  with silinecek as (
    select id, guncelleyen, mevcut_yetki, mevcut_zaman from pms_geri
    where mevcut_zaman = beklenen_zaman and mevcut_yetki = beklenen_yetki
  )
  delete from public.yetki_matrisi ym using silinecek s
  where ym.id = s.id
    and ym.guncelleyen = s.guncelleyen
    and ym.yetki::text = s.mevcut_yetki
    and ym.guncelleme_tarihi = s.mevcut_zaman;
  get diagnostics v_silinen = row_count;

  raise notice 'GERI ALMA: imzali=% silinen=% korunan=%',
    v_aday, v_silinen, v_aday - v_silinen;
end $$;

commit;

-- --- Doğrulama sorgusu ----------------------------------------------------
-- select count(*) from public.yetki_matrisi
--  where split_part(guncelleyen, '@', 1) = 'tohum:pms-onburo:<id>';
