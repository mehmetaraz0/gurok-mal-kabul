-- ============================================================
-- 2026-08-10 — PENTEST TUR 3, BULGU [4]: %120 TOLERANSI SUNUCUDA YOKTU
-- ============================================================
-- SORUN: "gelen miktar, sipariş edilenin %120'sini geçemez" kuralı yalnızca
-- tarayıcıda uygulanıyordu (mal-kabul-liste.html:837). mal_kabul_kaydet RPC'si
-- yetki ve otel kapsamını doğruluyor ama TOLERANSI doğrulamıyordu → doğrudan
-- RPC/REST çağrısıyla tolerans dışı mal kabul kaydedilebiliyordu.
--
-- İş etkisi: fazla mal kabulü stok ve maliyet hesabına doğrudan yansır;
-- tedarikçi fazla teslimatı sistemsel bir kontrole takılmadan kayda geçer.
--
-- ÇÖZÜM: aynı kural RPC'nin içine, en alt sunucu katmanına indirildi.
-- Fonksiyon gövdesi kaynak dosyadan (2026-08-01-tier1-atomik-rpc.sql)
-- PROGRAMATİK olarak alındı ve YALNIZCA tolerans bloğu eklendi —
-- diff doğrulaması: 57 satır eklendi, 0 satır silindi/değişti.
--
-- MANTIK İSTEMCİYLE BİREBİR AYNI TUTULDU:
--   • sipariş edilenin en fazla %120'si kabul edilir
--   • kısmi teslimatlarda ZATEN GELEN miktar hesaba katılır
--   • 0.001 kayan nokta payı
--   • birden fazla sipariş no verilmişse İLK eşleşen sipariş esas alınır
--   • ürün hiçbir siparişte bulunamazsa kontrol UYGULANMAZ
--     (siparişsiz mal kabul meşru bir akıştır — kural değiştirilmedi)
--
-- İSTEMCİDEN TEK FARKI: satır FOR UPDATE ile kilitlenir. İstemci kodunun
-- kendi yorumunda "eşzamanlı iki teslimat aynı bayat gelen_miktar üzerinden
-- ikisi de kontrolü geçebilir" diye endişe ediliyordu; sunucu tarafında bu
-- yarış gerçekten kapanıyor.
--
-- ⚠️ İSTEMCİ KONTROLÜ KALDIRILMADI ve kaldırılmamalı: kullanıcıya anında
-- geri bildirim veriyor (formu doldurup kaydete basmadan uyarıyor). Artık
-- güvenlik sınırı değil, kullanılabilirlik katmanı.
-- ============================================================

begin;

create or replace function public.mal_kabul_kaydet(
  p_baslik jsonb,
  p_kalemler jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_mk_id uuid;
  v_kalem jsonb;
  v_koli jsonb;
  v_kalem_id uuid;
  v_siparis_nolar text[];
  v_sip_miktar numeric;
  v_sip_gelen  numeric;
  v_sip_birim  text;
  v_bu_sefer_max numeric;
  v_istenen numeric;
begin
  if not public.auth_yetki_var('mal_kabul_form', 'kayit') then
    raise exception 'Yetki yok: mal kabul kaydı için mal_kabul_form kayıt yetkisi gerekli';
  end if;

  if p_kalemler is null or jsonb_array_length(p_kalemler) = 0 then
    raise exception 'En az bir ürün kalemi gerekli';
  end if;

  if not public.auth_otel_erisim(p_baslik->>'otel_id') then
    raise exception 'Yetki yok: bu otel için mal kabul kaydedemezsiniz';
  end if;

  -- ------------------------------------------------------------
  -- TESLİMAT TOLERANSI (%120) — pentest tur 3 bulgu [4]
  -- ------------------------------------------------------------
  -- Bu kural şimdiye kadar YALNIZCA istemcideydi (mal-kabul-liste.html:837);
  -- doğrudan RPC/REST çağrısıyla atlanabiliyordu. Mantık istemcidekiyle
  -- BİREBİR aynı tutuldu:
  --   • sipariş edilenin en fazla %120'si kabul edilir,
  --   • kısmi teslimatlarda ZATEN GELEN miktar da hesaba katılır,
  --   • 0.001'lik kayan nokta payı bırakılır,
  --   • birden fazla sipariş no verilmişse İLK eşleşen sipariş esas alınır,
  --   • ürün hiçbir siparişte bulunamazsa kontrol UYGULANMAZ (siparişsiz
  --     mal kabul meşru bir akış).
  -- İstemciden FARKI: satır FOR UPDATE ile kilitlenir, böylece eşzamanlı iki
  -- teslimat aynı bayat 'gelen_miktar' üzerinden ikisi birden geçemez —
  -- istemci kodunun yorumunda endişe edilen yarış durumu burada kapanır.
  if coalesce(p_baslik->>'ln_siparis_no', '') <> '' then
    select array_agg(btrim(x)) into v_siparis_nolar
    from unnest(string_to_array(p_baslik->>'ln_siparis_no', ',')) as x
    where btrim(x) <> '';

    if v_siparis_nolar is not null and array_length(v_siparis_nolar, 1) > 0 then
      for v_kalem in select * from jsonb_array_elements(p_kalemler)
      loop
        if coalesce(v_kalem->>'urun_kodu', '') = '' then
          continue;
        end if;

        select sk.miktar, sk.gelen_miktar, sk.birim
          into v_sip_miktar, v_sip_gelen, v_sip_birim
        from siparis_kalemleri sk
        where sk.siparis_no = any(v_siparis_nolar)
          and sk.urun_kodu = v_kalem->>'urun_kodu'
        order by array_position(v_siparis_nolar, sk.siparis_no)
        limit 1
        for update;

        if found then
          v_bu_sefer_max := v_sip_miktar * 1.2 - coalesce(v_sip_gelen, 0);
          v_istenen := coalesce((v_kalem->>'miktar')::numeric, 0);
          if v_istenen > v_bu_sefer_max + 0.001 then
            raise exception
              'Tolerans aşıldı (%): sipariş % %, zaten gelen % — bu teslimatta en fazla % % girilebilir',
              coalesce(v_kalem->>'urun_adi', v_kalem->>'urun_kodu'),
              v_sip_miktar, coalesce(v_sip_birim,''), coalesce(v_sip_gelen,0),
              round(greatest(v_bu_sefer_max, 0), 2), coalesce(v_sip_birim,'');
          end if;
        end if;
      end loop;
    end if;
  end if;

  insert into mal_kabuller (
    mk_no, form_tarihi, firma_ad, fatura_no, irsaliye_no, ln_siparis_no,
    otel_id, depo_kodu, arac_hijyen, arac_sicaklik, notlar, personel_ad, durum
  ) values (
    p_baslik->>'mk_no', (p_baslik->>'form_tarihi')::date, p_baslik->>'firma_ad',
    p_baslik->>'fatura_no', p_baslik->>'irsaliye_no', p_baslik->>'ln_siparis_no',
    (p_baslik->>'otel_id')::otel_id, p_baslik->>'depo_kodu',
    p_baslik->>'arac_hijyen', p_baslik->>'arac_sicaklik', p_baslik->>'notlar',
    p_baslik->>'personel_ad', coalesce((p_baslik->>'durum')::mal_kabul_durum, 'bekleyen')
  )
  returning id into v_mk_id;

  for v_kalem in select * from jsonb_array_elements(p_kalemler)
  loop
    insert into mal_kabul_urunleri (mk_id, urun_kodu, urun_adi, birim, miktar, seri_no, marka, sicaklik)
    values (
      v_mk_id, v_kalem->>'urun_kodu', v_kalem->>'urun_adi', coalesce(v_kalem->>'birim', 'KG'),
      (v_kalem->>'miktar')::numeric, v_kalem->>'seri_no', v_kalem->>'marka', v_kalem->>'sicaklik'
    )
    returning id into v_kalem_id;

    if v_kalem ? 'koliler' and jsonb_array_length(v_kalem->'koliler') > 0 then
      for v_koli in select * from jsonb_array_elements(v_kalem->'koliler')
      loop
        insert into koli_etiketleri (
          mk_id, mk_urun_id, urun_kodu, urun_adi, birim, miktar, koli_no,
          seri_no, marka, skt_tarihi, otel_id, depo_kodu, durum, birim_fiyat, fiyat_kaynagi
        ) values (
          v_mk_id, v_kalem_id, v_kalem->>'urun_kodu', v_kalem->>'urun_adi', coalesce(v_kalem->>'birim', 'KG'),
          (v_koli->>'miktar')::numeric, (v_koli->>'koli_no')::integer,
          v_kalem->>'seri_no', v_kalem->>'marka', (v_koli->>'skt_tarihi')::date,
          p_baslik->>'otel_id', p_baslik->>'depo_kodu', 'depoda',
          (v_koli->>'birim_fiyat')::numeric, v_koli->>'fiyat_kaynagi'
        );
      end loop;
    end if;
  end loop;

  return v_mk_id;
end;
$$;
revoke all on function public.mal_kabul_kaydet(jsonb, jsonb) from public, anon;
grant execute on function public.mal_kabul_kaydet(jsonb, jsonb) to authenticated;

commit;

notify pgrst, 'reload schema';


-- ============================================================
-- DOĞRULAMA — true dönmeli
-- ============================================================
-- select pg_get_functiondef(oid) like '%TESLİMAT TOLERANSI%' as tolerans_var
-- from pg_proc where proname = 'mal_kabul_kaydet';

-- ============================================================
-- UYGULAMADA TEST
-- ============================================================
-- 1) Siparişe bağlı NORMAL mal kabul (sipariş miktarı kadar) → kaydedilmeli
-- 2) Sipariş miktarının %110'u kadar → kaydedilmeli (tolerans içinde)
-- 3) Sipariş miktarının %130'u kadar → REDDEDİLMELİ
--    (istemci zaten uyarır; sunucu testi için doğrudan RPC çağrısı gerekir)
-- 4) Kısmi teslimat: önce %70, sonra %60 gir → İKİNCİSİ REDDEDİLMELİ
--    (toplam %130 olurdu) — bu, "zaten gelen" mantığının testidir
-- 5) SİPARİŞSİZ mal kabul (sipariş no boş) → kaydedilmeli, kontrol uygulanmaz
--
-- 4. madde en önemlisi: hem yeni sunucu kontrolünü hem de mevcut
-- gelen_miktar takibini birlikte doğrular.

-- ============================================================
-- GERİ ALMA
-- ============================================================
-- Fonksiyonun tolerans bloğu OLMAYAN hali:
--   docs/kurulum/2026-08-01-tier1-atomik-rpc.sql
