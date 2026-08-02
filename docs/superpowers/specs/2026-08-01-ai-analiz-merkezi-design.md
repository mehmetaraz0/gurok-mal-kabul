# Akıllı Veri Analiz Merkezi — v1 Tasarım Dokümanı

**Tarih:** 2026-08-01
**Durum:** Tasarım onaylandı (kullanıcı). Uygulama terminal SDD pipeline'ında yapılacak.
**Kaynak analiz:** Bu oturumda üretilen fizibilite raporu (v2). Güvenlik ön koşulları
(S1/S2/S3/S6 otel izolasyonu) bu oturumda zaten çözüldü — `auth_otel_erisim(otel_id)` +
`auth_tum_oteller()` + `kullanicilar.tum_oteller` CANLI.

## Amaç
Mevcut Gürok ERP'ye, iki oteli (810/811) yöneten depo/muhasebe verisi üzerinde **salt-okunur
AI destekli analiz** ekleyen bir modül. AI (OpenAI-uyumlu bir model) yalnızca **yorumlar**;
tüm sayısal hesaplama SQL view'larında yapılır. Hiçbir mevcut tablo/dosya değişmez — üstüne ekleme.

## v1 Kapsamı (3 özellik)
1. **Stok anomalisi ve israf tespiti** (istatistiksel olağandışı hareket, yaklaşan SKT, yavaş dönen, min-altı)
2. **Doğal dilde yönetici sorgulama** (serbest soru → sabit niyet → view → yorum)
3. **Günlük/haftalık yönetici raporu** (on-demand özet, otel karşılaştırmalı)

## Alınan Kararlar (kullanıcı onaylı)
- **AI backend:** OpenAI-uyumlu endpoint soyutlaması. Sağlayıcı 3 Edge Function secret'ı:
  `AI_API_URL`, `AI_API_KEY`, `AI_MODEL`. **Varsayılan sağlayıcı: NVIDIA API Catalog**
  (`https://integrate.api.nvidia.com/v1`, model ör. `meta/llama-3.3-70b-instruct`) — bedava
  API anahtarı, kurulum yok, "NVIDIA destekli" adıyla uyumlu. Tek secret değiştirilerek
  GLM/LiteLLM/başka sağlayıcıya geçilebilir.
- **Soru→veri eşleme:** HİBRİT niyet-sınıflandırma. Model serbest soruyu SABİT bir niyet
  menüsünden birine eşler + parametre çıkarır; Edge Function whitelisted view'ı çalıştırır;
  model sonucu yorumlar. Model ASLA SQL üretmez/çalıştırmaz.
- **Çalışma modeli:** TAMAMEN ON-DEMAND. Scheduling/e-posta/proaktif uyarı v1'de YOK.

## Mimari + Veri Akışı
```
analiz-merkezi.html (kullanıcı JWT) ──POST {soru}──▶ Edge Function ai-analiz-sorgula
  1) Kullanıcı JWT doğrula + auth_yetki_var('ai_analiz_merkezi','goruntule')  [reddedilirse 403]
  2) NVIDIA çağrı-1 SINIFLANDIRMA: {soru + sabit niyet menüsü JSON} → {intent_id, params}
  3) Whitelist: intent_id 6 niyetten biri mi? params sanitize (otel/tarih/ürün/eşik)
  4) İlgili VIEW'ı KULLANICININ JWT'siyle çalıştır → RLS + otel izolasyonu OTOMATİK
  5) Sonuç = küçük agregat tablo (PII yok, otel-scoped)
  6) NVIDIA çağrı-2 YORUMLAMA: {soru + agregat} → Türkçe özet
  ──▶ {ozet, kaynak_tablo, intent, kullanilan_view} ──▶ UI
```

### KRİTİK GÜVENLİK TASARIMI (basitleştirme — otel izolasyonu işinin meyvesi)
- View'lar **`security_invoker=true`** → kullanıcının JWT'siyle çalışınca RLS + `auth_otel_erisim`
  otel-scoping'i OTOMATİK uygular. **EF'in veri için service_role'e ihtiyacı YOK, elle
  `WHERE otel_id` YOK.** EF'in tek sırrı `AI_API_KEY`. (Eski rapor service_role + elle WHERE
  öneriyordu; otel izolasyonu artık DB'de olduğu için gereksiz.)
- Model ASLA: SQL üretmez, ham satır görmez (sadece küçük agregat), yetki/otel kararı vermez.
- NVIDIA'ya giden payload: yalnızca hesaplanmış küçük agregat tablo — **PII yok, ham/kişisel satır yok.**
- Whitelist: EF yalnızca 6 sabit niyete karşılık gelen 5 view'ı çalıştırır; başka hiçbir sorgu yok.

## v1 Niyet Menüsü (whitelist'in kendisi — EF içinde sabit)
| intent_id | Açıklama | Parametreler | View |
|---|---|---|---|
| tuketim_artan | Dönem karşılaştırmalı en çok artan tüketim | otel?, gun=30 | ai_tuketim_trend |
| skt_yaklasan | N günde SKT'si dolacaklar | otel?, gun=14 | ai_skt_risk |
| stok_anomali | İstatistiksel olağandışı hareket (ort±k·σ) | otel?, esik=2 | ai_stok_anomali |
| yavas_donen | X gündür çıkışı olmayan stoklu ürünler | otel?, gun=30 | ai_stok_anomali/tuketim |
| min_alti_stok | Minimum seviyenin altındaki ürünler | otel? | ai_gunluk_ozet/stok |
| gunluk_ozet | Bekleyen mal kabul + kritik SKT + min-altı (otel karşılaştırmalı) | otel? | ai_gunluk_ozet |

Model eşleyemezse: "bu soruyu v1'de yanıtlayamıyorum" (uydurmaz).

## Bileşenler
### 1) SQL View'lar (5-6, security_invoker, SALT-OKUNUR — yeni .sql dosyası, kullanıcı çalıştırır)
- `ai_otel_ref` — otel_id→ad (otel-config.js'in SQL yansıması)
- `ai_tuketim_trend` — `stok_hareketleri` tip='cikis', haftalık, urun+otel+depo bazlı
- `ai_stok_anomali` — window function (son 30 hareket ort/stddev), sapma adayları
- `ai_skt_risk` — `skt_kayitlari` durum='aktif' + kalan_gun
- `ai_gunluk_ozet` — otel bazlı bekleyen mal kabul + kritik SKT + min-altı stok
- (opsiyonel) `ai_yavas_donen` — son N gün cikis'i olmayan stoklu ürünler

**Veri notları (view yazımında dikkat):**
- `stok_hareketleri.tip` = **text** ('giris'/'cikis'/'transfer'), enum değil.
- **Tüketim, `aciklama ILIKE '%gunluk_tuketim%'/'%recete_tuketim%'` desenine bağlı** — temiz
  kategori yok. Bu tanım TEK view'da (ai_tuketim_trend) kapsüllensin; değişirse tek yer.
- `stok_hareketleri`'nde **aktör/kullanıcı alanı YOK** → kullanıcı-bazlı şüpheli işlem v1 dışı
  (gerekirse audit_log — bu oturumda auth_user_id damgası eklendi).
- `stok_ekle()` `stok_hareketleri` yazmıyor (JS ayrı yazıyor) → miktar/log sapma riski;
  anomali view'ı bunu "veri" sanabilir, yorumda "olası kayıt sapması" notu düşülebilir.
- Karışık otel_id tipi (enum vs text) → view'larda tutarlı `::text` yaklaşımı.

### 2) Edge Function `ai-analiz-sorgula` (yeni index.ts, Dashboard "Via Editor" deploy)
- Secret: `AI_API_URL`, `AI_API_KEY`, `AI_MODEL` (service_role YOK — v1 veri için gerekmiyor).
- Adımlar: JWT doğrula → auth_yetki_var('ai_analiz_merkezi','goruntule') → NVIDIA classify →
  whitelist+sanitize → view'ı kullanıcı JWT'siyle çalıştır → NVIDIA interpret → dön.
- "Enforce JWT Verification" AÇIK olabilir (kullanıcı girişli çağırıyor) — ama EF kendi de
  auth_yetki_var kontrolü yapıyor.
- Hata yönetimi: NVIDIA hatası/timeout → kullanıcıya "AI şu an yanıt veremedi, ham veri
  gösteriliyor" + agregat tabloyu yine göster (AI olmadan da veri değerli).

### 3) UI `analiz-merkezi.html` (yeni)
- Sohbet kutusu (serbest soru → özet + kaynak tablo, satıra tıkla→ilgili ekran).
- Açılışta günlük özet kartı (gunluk_ozet, iki otel yan yana — merkez kullanıcı için).
- Anomali/İsraf listesi (stok_anomali + skt_risk).
- Her AI cevabı **Doğrulanmış bulgu / Tahmin / Öneri** olarak ayrı etiketli.
- Mevcut desen: auth-guard.js + supabase-config.js + otel-config.js + nav-drawer.js; requireRole.

### 4) Yetki
- Yeni modül `ai_analiz_merkezi` → `yetki_matrisi`'ne seed (rollere goruntule).
- `nav-drawer.js` ND_MODULLER +1 satır, `index.html` MODULLER +1 satır (mevcut satırlar değişmez).

## Kapsam DIŞI (YAGNI — v1'de YOK)
Scheduling/cron/e-posta · proaktif uyarı · sipariş tahmini · fatura-teklif-mal kabul karşılaştırma
· tam tool-use (model view/param seçimi) · service_role veri erişimi · yeni tablo/migration.

## Kurallar (uygulama boyunca)
- NVIDIA: sadece yorumlar; stok/sipariş/ödeme/mal kabul DEĞİŞTİRMEZ/ONAYLAMAZ. Sayısal her şey SQL'de.
- service_role/AI_API_KEY tarayıcıya/koda ASLA — Edge Function secret'ı.
- Otel/depo izolasyonu korunur (security_invoker view + kullanıcı JWT + auth_otel_erisim).
- RLS devre dışı bırakılmaz.
- PII/gereksiz hassas veri modele gitmez (sadece agregat).
- AI cevabında Doğrulanmış/Tahmin/Öneri ayrı; her bulgu kaynak view/satırla doğrulanabilir.
- Mevcut çalışan sistem yeniden yazılmaz; ortak yapılar (auth-guard, nav-drawer, otel-config,
  Bar JWT-relay EF deseni) tekrar kullanılır.
- SQL'ler dosya olarak verilir, kullanıcı SQL Editor'de çalıştırır. EF Dashboard'dan deploy.

## Bağımlılıklar / Açık İşler (uygulamadan önce)
- NVIDIA API Catalog anahtarı (build.nvidia.com — kullanıcı alır, EF secret'a girer). Model seçimi teyit.
- Canlı şema teyidi (şema dökümü bayat — view yazmadan önce ilgili tabloların canlı kolonları doğrulanmalı).
- S4: sayim/urun_birim_donusum RLS-gated — v1 view'ları bunlara dokunmuyor (kapsam dışı), sorun değil.

## Test / Doğrulama Planı
- Her view: gerçek veride bilinen örnekle elle doğrulama (SKT-kritik ürün vb.).
- **Otel izolasyonu:** 810 test kullanıcısıyla 811 verisinin view/EF'ten GÖRÜNMEDİĞİNİ doğrula.
- NVIDIA payload manuel inceleme: sadece agregat, PII yok.
- Boş/eksik veri: hareketsiz ürün için view hatasız boş döner.
- EF: yetkisiz kullanıcı 403; NVIDIA down → ham veri yine gösterilir.
- `EXPLAIN ANALYZE`: view'lar makul; `stok_hareketleri(urun_kodu,depo_kodu,tarih)`+`(tip,tarih)` index önerisi.

## Uygulama Devri (terminal SDD)
Bu doküman writing-plans → subagent-driven-development ile fazlı uygulanacak. Faz sırası:
Faz 1 SQL view'lar (kullanıcı çalıştırır, SQL Editor'de doğrular) → Faz 2 Edge Function
(classify→run→interpret, kullanıcı Dashboard'dan deploy + curl test) → Faz 3 UI +
yetki/nav entegrasyonu → Faz 4 uçtan uca test (otel izolasyonu + PII-free + yetki).
Her faz için Opus review + kullanıcı testi.
