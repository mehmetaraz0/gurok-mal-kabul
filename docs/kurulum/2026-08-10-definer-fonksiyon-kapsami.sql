-- ============================================================
-- 2026-08-10 — POLİTİKA DENETİMİ SORGU 6 BULGUSU:
-- KONTROLSÜZ SECURITY DEFINER FONKSİYONLARI
-- ============================================================
-- SECURITY DEFINER fonksiyonlar RLS'i TAMAMEN BAYPAS EDER; politika katmanı
-- onlar için hiç çalışmaz, kontrol fonksiyonun kendi içinde olmak zorundadır.
-- Denetimde 22 DEFINER fonksiyonu tarandı. Çoğu temiz çıktı:
--   fatura_kaydet, mal_kabul_kaydet, teklif_talebi_olustur,
--   siparis_yeniden_yonlendir, talep_siparise_donustur, bar durum RPC'leri
--   → hepsinde yetki + otel kontrolü VAR.
--
-- Üç sorun bulundu:
--
--   [A] bar_siparis_olustur — GERÇEK BOŞLUK (yazma + stok etkisi)
--   [B] bar_kullanilabilir_stok — gereksiz authenticated erişimi
--   [C] rls_auto_enable — gereksiz authenticated erişimi
-- ============================================================

begin;

-- ------------------------------------------------------------
-- [A] bar_siparis_olustur — KOŞULLU otel/yetki kontrolü
-- ------------------------------------------------------------
-- Fonksiyon p_otel_id ve p_depo_id'yi çağırandan alıyor ve doğrulamıyordu.
-- bar-garson.html bunu PERSONEL JWT'siyle çağırıyor (bar-garson.html:167),
-- yani bir otelin personeli diğer oteli yazıp orada sipariş oluşturabiliyor
-- ve STOK REZERVE EDEBİLİYORDU.
--
-- Neden basit revoke ÇÖZÜM DEĞİL: aynı fonksiyonu müşteri QR akışı da
-- çağırıyor (müşteri projesindeki siparis-gonder EF'i, service_role ile).
-- authenticated'dan alırsak garson ekranı kırılır; kontrolü koşulsuz eklersek
-- müşteri akışı kırılır (orada kullanıcı kimliği yok).
--
-- ÇÖZÜM: auth.uid() doluysa (personel) kontrol uygula, boşsa (service_role,
-- müşteri akışı) atla — o yolda doğrulama masa token'ıyla EF'te yapılıyor.
--
-- Gövde kaynak dosyadan (2026-08-09-pentest2-adim1-capraz-otel.sql)
-- programatik alındı; yalnız bu koşullu blok eklendi, kalanı değişmedi.
create or replace function public.bar_siparis_olustur(
  p_otel_id text, p_depo_id text, p_masa_token text, p_oda_no text, p_kalemler jsonb
) returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
  v_siparis_id uuid;
  v_kalem jsonb;
  v_menu menu_urunler%rowtype;
  v_kalem_id uuid;
  v_bilesen record;
  v_gerekli numeric;
  v_musait numeric;
begin
  -- GUARD: boş sepet reddedilir (sipariş satırı bile oluşmaz)
  if p_kalemler is null or jsonb_array_length(p_kalemler) = 0 then
    raise exception 'Boş sipariş: en az bir kalem gerekli';
  end if;

  -- GÜVENLİK (politika denetimi sorgu 6 — 2026-08-10): bu fonksiyon İKİ yoldan çağrılıyor.
  --   • MÜŞTERİ QR AKIŞI: müşteri projesindeki 'siparis-gonder' Edge Function'ı, ANA
  --     projenin service_role anahtarıyla çağırır → auth.uid() BOŞTUR. Otel/depo
  --     doğrulaması orada masa token'ıyla yapılır; burada tekrar edilemez (kullanıcı yok).
  --   • PERSONEL AKIŞI: bar-garson.html, personel JWT'siyle çağırır → auth.uid() DOLUDUR.
  --     Bu yolda p_otel_id/p_depo_id çağırandan geliyordu ve HİÇ DOĞRULANMIYORDU →
  --     bir otelin personeli diğer oteli yazıp orada sipariş oluşturabiliyor ve
  --     STOK REZERVE EDEBİLİYORDU.
  -- Bu yüzden kontrol koşullu: yalnız kimliği olan çağıran için uygulanır.
  if auth.uid() is not null then
    if not auth_yetki_var('bar_siparis_yonetimi','kayit') then
      raise exception 'Yetki yok: bar_siparis_yonetimi kayıt gerekli';
    end if;
    if not auth_otel_erisim(p_otel_id) then
      raise exception 'Bu otel için sipariş oluşturamazsınız';
    end if;
  end if;

  insert into bar_siparisleri (otel_id, depo_id, masa_token, oda_no, durum)
  values (p_otel_id::otel_id, p_depo_id, p_masa_token, p_oda_no, 'yeni')
  returning id into v_siparis_id;

  for v_kalem in select * from jsonb_array_elements(p_kalemler)
  loop
    -- GÜVENLİK (pentest-2 [1]): menü ürünü, masa token'ından çözümlenen OTELE ait
    -- OLMALI. Önceden yalnız id ile aranıyordu → 810'un masasından 811'in menüsü
    -- sipariş edilebiliyor ve stok 810 deposundan düşüyordu (çapraz-otel sızıntı).
    select * into v_menu from menu_urunler
      where id = (v_kalem->>'menu_urun_id')::uuid
        and aktif = true and silindi = false
        and otel_id = p_otel_id::otel_id;
    if not found then
      raise exception 'Menü ürünü bulunamadı/pasif: %', v_kalem->>'menu_urun_id';
    end if;

    insert into bar_siparis_kalemleri (siparis_id, menu_urun_id, adet, rezerve_edildi)
    values (v_siparis_id, v_menu.id, (v_kalem->>'adet')::numeric, v_menu.stok_kodu is not null)
    returning id into v_kalem_id;

    if v_menu.tip = 'direkt' then
      -- stok_kodu YOKSA stok takibi yok (dahil/ücretsiz ürün) → kontrolü ve rezervasyonu atla
      if v_menu.stok_kodu is not null then
        v_gerekli := (v_kalem->>'adet')::numeric * coalesce(v_menu.miktar_per_porsiyon, 1);
        v_musait := bar_kullanilabilir_stok(v_menu.stok_kodu, p_depo_id);
        if v_musait < v_gerekli then
          raise exception 'Yetersiz stok: % (gerekli %, müsait %)', v_menu.stok_kodu, v_gerekli, v_musait;
        end if;
        insert into stok_rezervasyonlari (stok_kodu, otel_id, depo_id, miktar, siparis_kalem_id, durum)
        values (v_menu.stok_kodu, p_otel_id::otel_id, p_depo_id, v_gerekli, v_kalem_id, 'aktif');
      end if;
    else
      for v_bilesen in select * from recete_bilesenleri where menu_urun_id = v_menu.id
      loop
        v_gerekli := (v_kalem->>'adet')::numeric * v_bilesen.miktar_per_porsiyon;
        v_musait := bar_kullanilabilir_stok(v_bilesen.stok_kodu, p_depo_id);
        if v_musait < v_gerekli then
          raise exception 'Yetersiz stok (reçete): % (gerekli %, müsait %)', v_bilesen.stok_kodu, v_gerekli, v_musait;
        end if;
        insert into stok_rezervasyonlari (stok_kodu, otel_id, depo_id, miktar, siparis_kalem_id, durum)
        values (v_bilesen.stok_kodu, p_otel_id::otel_id, p_depo_id, v_gerekli, v_kalem_id, 'aktif');
      end loop;
    end if;
  end loop;

  return v_siparis_id;
end;
$$;
-- ------------------------------------------------------------
-- [B] bar_kullanilabilir_stok — authenticated'a gerek yok
-- ------------------------------------------------------------
-- Hiçbir kontrolü yok; authenticated bir kullanıcı herhangi bir depo/otelin
-- stok seviyesini sorgulayabiliyordu. İstemcide ÇAĞIRANI YOK (kod tarandı) —
-- yalnız bar_siparis_olustur içinden kullanılıyor, orası DEFINER bağlamında
-- çalıştığı için sahip yetkisiyle erişir, bu revoke'tan ETKİLENMEZ.
revoke all on function public.bar_kullanilabilir_stok(text, text) from public, anon, authenticated;

-- ------------------------------------------------------------
-- [C] rls_auto_enable — authenticated'a gerek yok
-- ------------------------------------------------------------
-- "Yeni tablo oluşunca RLS'i otomatik aç" amaçlı event-trigger fonksiyonu.
-- Çağıranı yok. (Zaten hiçbir olaya BAĞLANMAMIŞ — aşağıdaki nota bak.)
revoke all on function public.rls_auto_enable() from public, anon, authenticated;

commit;

notify pgrst, 'reload schema';


-- ============================================================
-- DOĞRULAMA
-- ============================================================
-- 1) bar_siparis_olustur artık kontrol içeriyor mu (true dönmeli):
-- select pg_get_functiondef(oid) ~* 'auth_otel_erisim' as otel_var
-- from pg_proc where proname='bar_siparis_olustur';
--
-- 2) İki fonksiyon authenticated'dan alındı mı (ikisi de false):
-- select proname, has_function_privilege('authenticated', oid, 'EXECUTE') as auth_cagirabilir
-- from pg_proc p join pg_namespace n on n.oid=p.pronamespace
-- where n.nspname='public' and proname in ('bar_kullanilabilir_stok','rls_auto_enable');


-- ============================================================
-- UYGULAMADA TEST
-- ============================================================
-- 1) QR müşteri menüsünden sipariş ver  → ÇALIŞMALI (service_role yolu)
-- 2) Bar garson ekranından sipariş ver  → ÇALIŞMALI (kendi oteli)
-- 3) Bar kuyruğunda sipariş görünmeli, teslim edilebilmeli
-- 4) Tek-otel personelle diğer otelin masasına sipariş → REDDEDİLMELİ
--
-- ⚠️ 1. madde en kritik: müşteri akışının bozulmadığını mutlaka doğrula.
-- Bozulursa sebep koşullu bloktur; auth.uid() beklendiği gibi boş gelmiyor
-- olabilir. Geri alma: `if auth.uid() is not null then ... end if;` bloğunu
-- kaldır (kaynak: 2026-08-09-pentest2-adim1-capraz-otel.sql).


-- ============================================================
-- AYRI İŞ — KÖK NEDEN (bu dosyanın kapsamı dışında)
-- ============================================================
-- rls_auto_enable() tanımlı ama onu bir DDL olayına bağlayan
-- CREATE EVENT TRIGGER ifadesi YOK. Yani "yeni tabloda RLS'i otomatik aç"
-- güvenlik ağı kurulmuş, hiç bağlanmamış. Denetim sorgu 2'de bulunan
-- "RLS açık ama politikasız / politika unutulmuş" sınıfının kök nedeni bu.
-- 2026-07-22 RLS denetiminde de aynı öneri yapılmış, uygulanmamış.
-- Bağlamak ayrı bir karar: tablo oluşturmayı etkileyeceği için önce
-- fonksiyonun gövdesi gözden geçirilmeli.
