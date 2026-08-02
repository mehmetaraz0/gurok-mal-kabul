-- 2026-08-01 — TIER 1: Veri kaybı / yarım kayıt bug'ları için atomik RPC'ler
-- (Codex bug raporu #5 fatura düzenleme, #6 mal kabul, #12 RFQ telafi silmesi)
--
-- ÖN KOŞUL: docs/kurulum/2026-08-01-hepsi-temizligi.sql CANLIDA ÇALIŞTIRILMIŞ OLMALI
-- (mal_kabuller/mal_kabul_urunleri/teklif_talepleri/teklif_kalemleri/teklif_fiyatlari
-- artık otel-scoped; bu dosyadaki RPC'ler security definer olduğu için RLS'i baypas
-- eder ve kendi içlerinde eşdeğer auth_yetki_var + auth_otel_erisim kontrolünü yapar).
--
-- Desen: bar_siparis_olustur (docs/kurulum/2026-07-22-bar-02-rpc.sql) ile aynı —
-- plpgsql, security definer, jsonb kalem parametresi, `raise exception` = otomatik
-- rollback (fonksiyon tek transaction; hata durumunda HİÇBİR şey yazılmaz).
--
-- Bu 3 RPC'nin çözdüğü bug'lar:
--   #5  fatura_kaydet        — PATCH+DELETE+INSERT ayrı ayrıydı, kalem INSERT başarısızsa
--                              fatura satırsız kalabiliyordu.
--   #6  mal_kabul_kaydet     — başlık/kalem/koli ayrı INSERT'ti, kalem/koli başarısızsa
--                              başlık yarım kalıyordu (kod bunu kullanıcıya itiraf ediyordu).
--   #12 teklif_talebi_olustur — kalem INSERT başarısızsa başlık DELETE'i kontrolsüzdü,
--                              DELETE de başarısız olursa yetim RFQ kalıyordu.
--
-- NOT (TIER 2 hazırlığı, #8 fatura no yarışı): fatura_kaydet, fatura numarasını
-- p_satir->>'no' üzerinden CLIENT'TAN olduğu gibi alıyor (şu an client hâlâ
-- yeniFaturaNo() ile sayaç+1 üretiyor — TIER 2'de bu üretim advisory-lock ile RPC
-- İÇİNE alınacak). TIER 1 kapsamı SADECE atomiklik; numara üretimi bilerek
-- dokunulmadan bırakıldı.
--
-- Yetki kontrolleri, ilgili tabloların (RLS baypas edilmeden önceki) mevcut politika
-- desenleriyle birebir:
--   fatura_kaydet        -> auth_yetki_var(fatura_giris veya fiyat_kontrol veya
--                           siparis_olustur, kayit) + auth_otel_erisim(otel_id)
--                           (faturalar Faz 2 pilot'ta zaten otel-scoped canlı — RPC
--                           bu korumayı bypass etmesin diye burada da uygulanıyor)
--   mal_kabul_kaydet     -> auth_yetki_var('mal_kabul_form','kayit') + auth_otel_erisim(otel_id)
--   teklif_talebi_olustur -> auth_yetki_var('siparis_olustur','kayit') + auth_otel_erisim(otel_id)
--
-- Çalıştırma: Supabase Dashboard → SQL Editor → tamamını yapıştır → Run.
-- Sonra TEST bölümünü uygula (en altta). Rollback en altta.

begin;

-- ============================================================
-- 1) fatura_kaydet — #5 fix
-- ============================================================
create or replace function public.fatura_kaydet(
  p_fatura_id uuid,
  p_satir jsonb,
  p_kalemler jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_fatura_id uuid;
  v_eski_otel public.otel_id;
  v_kalem jsonb;
begin
  if not (
    public.auth_yetki_var('fatura_giris', 'kayit')
    or public.auth_yetki_var('fiyat_kontrol', 'kayit')
    or public.auth_yetki_var('siparis_olustur', 'kayit')
  ) then
    raise exception 'Yetki yok: fatura kaydı için fatura_giris/fiyat_kontrol/siparis_olustur kayıt yetkisi gerekli';
  end if;

  if p_kalemler is null or jsonb_array_length(p_kalemler) = 0 then
    raise exception 'En az bir fatura kalemi gerekli';
  end if;

  if not public.auth_otel_erisim(p_satir->>'otel_id') then
    raise exception 'Yetki yok: bu otel için fatura kaydedemezsiniz';
  end if;

  if p_fatura_id is not null then
    select otel_id into v_eski_otel from faturalar where id = p_fatura_id;
    if not found then
      raise exception 'Fatura bulunamadı: %', p_fatura_id;
    end if;
    if not public.auth_otel_erisim(v_eski_otel::text) then
      raise exception 'Yetki yok: bu faturanın oteline erişiminiz yok';
    end if;

    update faturalar set
      no = p_satir->>'no',
      tur = (p_satir->>'tur')::fatura_tur,
      tarih = (p_satir->>'tarih')::date,
      vade_tarihi = (p_satir->>'vade_tarihi')::date,
      cari_id = (p_satir->>'cari_id')::uuid,
      cari_ad = p_satir->>'cari_ad',
      siparis_no = p_satir->>'siparis_no',
      ara_toplam = coalesce((p_satir->>'ara_toplam')::numeric, 0),
      kdv_toplam = coalesce((p_satir->>'kdv_toplam')::numeric, 0),
      genel_toplam = coalesce((p_satir->>'genel_toplam')::numeric, 0),
      komisyon_orani = coalesce((p_satir->>'komisyon_orani')::numeric, 0),
      komisyon_tutari = coalesce((p_satir->>'komisyon_tutari')::numeric, 0),
      iade = coalesce((p_satir->>'iade')::boolean, false),
      otel_id = (p_satir->>'otel_id')::otel_id,
      not_alani = p_satir->>'not_alani',
      durum = (p_satir->>'durum')::fatura_durum,
      odeme_tarihi = (p_satir->>'odeme_tarihi')::timestamptz,
      odeme_tutari = (p_satir->>'odeme_tutari')::numeric,
      odeme_yontemi = p_satir->>'odeme_yontemi',
      guncelleme_tarihi = now()
    where id = p_fatura_id
    returning id into v_fatura_id;

    delete from fatura_kalemleri where fatura_id = v_fatura_id;
  else
    insert into faturalar (
      no, tur, tarih, vade_tarihi, cari_id, cari_ad, siparis_no,
      ara_toplam, kdv_toplam, genel_toplam, komisyon_orani, komisyon_tutari,
      iade, otel_id, not_alani, durum, odeme_tarihi, odeme_tutari, odeme_yontemi
    ) values (
      p_satir->>'no', (p_satir->>'tur')::fatura_tur, (p_satir->>'tarih')::date,
      (p_satir->>'vade_tarihi')::date, (p_satir->>'cari_id')::uuid, p_satir->>'cari_ad',
      p_satir->>'siparis_no', coalesce((p_satir->>'ara_toplam')::numeric, 0),
      coalesce((p_satir->>'kdv_toplam')::numeric, 0), coalesce((p_satir->>'genel_toplam')::numeric, 0),
      coalesce((p_satir->>'komisyon_orani')::numeric, 0), coalesce((p_satir->>'komisyon_tutari')::numeric, 0),
      coalesce((p_satir->>'iade')::boolean, false), (p_satir->>'otel_id')::otel_id,
      p_satir->>'not_alani', coalesce((p_satir->>'durum')::fatura_durum, 'taslak'),
      (p_satir->>'odeme_tarihi')::timestamptz, (p_satir->>'odeme_tutari')::numeric,
      p_satir->>'odeme_yontemi'
    )
    returning id into v_fatura_id;
  end if;

  for v_kalem in select * from jsonb_array_elements(p_kalemler)
  loop
    insert into fatura_kalemleri (
      fatura_id, urun_kodu, urun_adi, miktar, birim, birim_fiyat, iskonto_yuzde, kdv_orani, toplam
    ) values (
      v_fatura_id, v_kalem->>'urun_kodu', v_kalem->>'urun_adi',
      (v_kalem->>'miktar')::numeric, coalesce(v_kalem->>'birim', 'KG'),
      (v_kalem->>'birim_fiyat')::numeric, coalesce((v_kalem->>'iskonto_yuzde')::numeric, 0),
      coalesce((v_kalem->>'kdv_orani')::numeric, 20), (v_kalem->>'toplam')::numeric
    );
  end loop;

  return v_fatura_id;
end;
$$;

-- ============================================================
-- 2) mal_kabul_kaydet — #6 fix
-- p_kalemler eleman formatı: {urun_kodu, urun_adi, birim, miktar, seri_no, marka, sicaklik,
--   koliler:[{miktar, koli_no, skt_tarihi, birim_fiyat, fiyat_kaynagi}, ...]}
-- Kalem->koli bağlama RPC içinde: her kalem INSERT'i `returning id`, koliler o id ile
-- (mk_urun_id) aynı döngü adımında yazılır — jsonb sırası/index eşleştirmesi YOK, doğrudan id.
-- ============================================================
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

-- ============================================================
-- 3) teklif_talebi_olustur — #12 fix
-- ============================================================
create or replace function public.teklif_talebi_olustur(
  p_olusturan text,
  p_otel_id text,
  p_kalemler jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_talep_id uuid;
  v_otel text;
  v_kalem jsonb;
begin
  if not public.auth_yetki_var('siparis_olustur', 'kayit') then
    raise exception 'Yetki yok: teklif talebi için siparis_olustur kayıt yetkisi gerekli';
  end if;

  if p_kalemler is null or jsonb_array_length(p_kalemler) = 0 then
    raise exception 'En az bir kalem seçin';
  end if;

  v_otel := coalesce(p_otel_id, '810');

  if not public.auth_otel_erisim(v_otel) then
    raise exception 'Yetki yok: bu otel için teklif talebi oluşturamazsınız';
  end if;

  insert into teklif_talepleri (olusturan, otel_id, durum)
  values (p_olusturan, v_otel, 'acik')
  returning id into v_talep_id;

  for v_kalem in select * from jsonb_array_elements(p_kalemler)
  loop
    insert into teklif_kalemleri (
      teklif_talebi_id, urun_kodu, urun_adi, miktar, birim, kaynak_ic_talep_kalemi_id
    ) values (
      v_talep_id, v_kalem->>'urun_kodu', v_kalem->>'urun_adi',
      (v_kalem->>'miktar')::numeric, coalesce(v_kalem->>'birim', 'KG'),
      nullif(v_kalem->>'kaynak_ic_talep_kalemi_id', '')::uuid
    );
  end loop;

  return v_talep_id;
end;
$$;

-- ============================================================
-- İzinler — sadece authenticated (staff-only yazma, bar RPC'lerinin aksine anon yok)
-- ============================================================
revoke all on function public.fatura_kaydet(uuid, jsonb, jsonb) from public;
grant execute on function public.fatura_kaydet(uuid, jsonb, jsonb) to authenticated;

revoke all on function public.mal_kabul_kaydet(jsonb, jsonb) from public;
grant execute on function public.mal_kabul_kaydet(jsonb, jsonb) to authenticated;

revoke all on function public.teklif_talebi_olustur(text, text, jsonb) from public;
grant execute on function public.teklif_talebi_olustur(text, text, jsonb) to authenticated;

commit;
notify pgrst, 'reload schema';

-- ============================================================
-- TEST (SQL çalıştıktan sonra, UYGULAMA ÜZERİNDE taze login ile):
-- a) Fatura düzenleme (muhasebe-faturalar.html): mevcut bir faturayı aç, kalemleri
--    değiştir, kaydet — fatura_kalemleri tabloda eksiksiz güncellenmeli. Kasıtlı olarak
--    geçersiz bir kalem (ör. miktar='' -> numeric cast hatası) gönderip fonksiyonun
--    exception fırlattığını ve BAŞLIĞIN DA değişmediğini doğrula (rollback testi).
-- b) Mal kabul (mal-kabul-liste.html): "Koli Bazlı Giriş" ile yeni bir kayıt oluştur —
--    başlık + kalemler + koli etiketleri tek seferde oluşmalı, koli_etiketleri.mk_urun_id
--    doğru kaleme bağlanmalı (rastgele değil). Zorla bir kalem adını NULL yaparak
--    (urun_adi NOT NULL ihlali) fonksiyonun patlayıp mal_kabuller'de YARIM KAYIT
--    bırakmadığını doğrula.
-- c) RFQ (satin-alma-teklif-toplama.html): yeni teklif talebi oluştur — talep+kalemler
--    tek seferde oluşmalı. Zorla bir kalemi bozup (miktar eksik) fonksiyonun patlayıp
--    teklif_talepleri'nde YETİM BAŞLIK bırakmadığını doğrula.
-- d) Otel izolasyonu: tek-otel kullanıcı kendi otelinin dışında bir otel_id ile
--    fatura/mal kabul/RFQ oluşturmaya çalışınca "Yetki yok" hatası almalı.
-- e) select proname, prosecdef from pg_proc where proname in
--    ('fatura_kaydet','mal_kabul_kaydet','teklif_talebi_olustur');
--    prosecdef = true olmalı (security definer doğru uygulanmış).
-- ============================================================

-- ============================================================
-- ROLLBACK (gerekirse — client hâlâ eski çok-adımlı REST akışını kullanıyorsa bu RPC'ler
-- sadece kullanılmaz kalır, zararsızdır; tam geri almak için):
-- begin;
-- drop function if exists public.fatura_kaydet(uuid, jsonb, jsonb);
-- drop function if exists public.mal_kabul_kaydet(jsonb, jsonb);
-- drop function if exists public.teklif_talebi_olustur(text, text, jsonb);
-- commit;
-- notify pgrst, 'reload schema';
-- ============================================================
