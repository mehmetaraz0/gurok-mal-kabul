# PMS Repository Analysis

> DORNEVİ ERP (eski adı Araz) — Gürok Turizm grubu depo/satın alma/muhasebe ERP'si.
> Bu rapor Front Office / PMS modülü eklenmeden önce repository intelligence amaçlı hazırlanmıştır.
> Keşif tarihi: 2026-09-05 · Git: `main`, working tree clean (0740cfb).
> Not verified olarak işaretlenmemiş her tespit ilgili dosyada doğrudan doğrulanmıştır.

## 1. Repository Overview

- Tek kiracı + 2 otelli (810 Club Manavgat / 811 Resort Sorgun) otel grubu ERP'si. Amacı depo/stok, mal kabul, satın alma, muhasebe ve F&B bar yönetimi.
- Mimari: **düz (flat) vanilla JS/HTML**, her modül bağımsız bir `.html` sayfası; backend **Supabase** (PostgREST + RLS + Edge Functions). Build aracı, framework, package.json, node_modules **yok** (glob ile doğrulandı).
- Hosting: GitHub Pages, custom domain `demo.otel.dornevi.com` (CNAME). PWA: `manifest.json` + `sw.js`, ikisi de `index.html`'de kayıtlı (commit 0740cfb).
- Marka geçişi Araz → Dornevi (commit a590287); kod içinde hâlâ `araz_` önekleri ve Türkçe tanımlayıcılar baskın.
- Reponun kök dizini aynı zamanda uygulamanın tamamıdır: ~40 modül HTML'i + ~15 paylaşılan JS + SQL migration'lar `docs/kurulum/` altında.

## 2. Technology Stack

| Katman | Teknoloji | Kanıt |
|---|---|---|
| Frontend | Vanilla ES6+ JS, inline CSS, tek dosyalık modüller | tüm kök `*.html` |
| Data access | Ham `fetch()` → Supabase REST (PostgREST), supabase-js **kullanılmıyor** | `supabase-config.js` |
| Auth | 6 haneli PIN + Supabase Auth (Edge Function üzerinden) | `index.html`, `docs/kurulum/ana-proje/pin-girisi/index.ts` |
| Backend | Supabase (PostgreSQL 15, RLS, SECURITY DEFINER RPC, Deno Edge Functions) | `docs/kurulum/*.sql`, `docs/kurulum/ana-proje/` |
| Excel | xlsx-js-style CDN (SRI hash'li) | `ortak.js:117-127` (`loadXlsxLib`) |
| CI | GitHub Actions + Node 20 statik kontroller | `.github/workflows/statik-kontroller.yml` |
| Yük testi | k6 salt-okuma takımı | `scripts/yuk-testi/k6-okuma.js` |
| Canlı izleme | Güvenlik sondası | `scripts/canli-sonda.mjs`, `.github/workflows/canli-sonda.yml` |

## 3. Directory Map

```
/ (kök = uygulama)
├── index.html              → giriş (PIN) + portal kabuğu (iframe sekme sistemi)
├── auth-guard.js           → oturum + requireLogin/requireRole (paylaşılan)
├── supabase-config.js      → SB_URL/SB_KEY/SB_HEADERS
├── otel-config.js          → otel/departman/depo sabitleri (müşteri kurulum dosyası)
├── ortak.js, onay-motoru.js, tablo.js, filtre.js, ortak-excel.js, nav-drawer.js
├── bar-config.js, qr-mini.js, efatura-adapter.js, fetch-kur.js, theme.css, sw.js
├── araz_veritabani.js      → statik ürün/tedarikçi katalog anlık görüntüsü (211 KB)
├── mal-kabul-*.html (7)    → Mal Kabul modülü
├── satin-alma-*.html (10)  → Satın Alma modülü
├── muhasebe*.html (17)     → Muhasebe modülü
├── bar-*.html (6)          → F&B Bar modülü
├── kullanici-yonetimi.html / yetki-yonetimi.html / giris-kayitlari.html
└── docs/
    ├── KURULUM-REHBERI.md  → yeni müşteri kurulum adımları
    ├── kurulum/            → tüm SQL migration'lar (01-sema-dokumu.sql = canlı şema dökümü, 3932 satır, 55 tablo)
    │   ├── ana-proje/      → Edge Function kaynakları (pin-girisi, ai-analiz-sorgula)
    │   └── musteri-projesi/→ izole bar müşteri projesi (şema + 3 Edge Function)
    └── superpowers/
        ├── plans/          → uygulama planları (task-by-task)
        └── specs/          → tasarım dokümanları
scripts/                    → check.mjs (CI statik kontrol), canli-sonda.mjs, yuk-testi/
.github/workflows/          → statik-kontroller.yml, canli-sonda.yml, kur-guncelle.yml
```

Dış dokümantasyon kasası: `D:\ERP-Bilgi-Haritasi` (Obsidian) — `CLAUDE.md` + `AGENTS.md` kuralları gereği.

## 4. Application Entry Points

- **index.html** — tek gerçek giriş noktası: PIN ekranı (`#screen-login`) → `checkPin()` (index.html:550) → portal kabuğu (`#screen-portal`).
- Portal kabuğu: sidebar + **iframe tabanlı sekme sistemi** (`sekmeAc/sekmeSec`, index.html:668-757, tasarım: `docs/superpowers/specs/2026-07-29-sekme-sistemi-design.md`). Modüller iframe içinde açılır; `auth-guard.js:134-147` iframe içi "eve dön" düğmelerini gizler.
- Hub sayfaları: `muhasebe.html`, `satin-alma.html`, `bar.html` — alt modül kartlarını listeleyen ara sayfalar.
- Her modül sayfası `<head>` içinde **sabit yükleme sırası** izler: `auth-guard.js → supabase-config.js → otel-config.js → ortak.js/onay-motoru.js`. Bu sıra CI'da `scripts/check.mjs:27-44` ile zorunlu tutulur.
- `requireLogin()` (auth-guard.js:56) her modülde çağrılır; `returnTo` parametresiyle giriş sonrası dönüş yapılır.

## 5. Authentication Architecture

- **Yöntem:** 6 haneli PIN. PIN asla Auth parolası olarak gönderilmez; akış tamamen sunucuda (index.html:502-519 yorumu + kod):
  1. `POST /functions/v1/pin-girisi` → Edge Function `docs/kurulum/ana-proje/pin-girisi/index.ts`
  2. EF, `pin_dogrula` RPC'sini **service_role** ile çağırır (bcrypt karşılaştırma + sunucu taraflı rate-limit 10 deneme/15 dk, `giris_denemeleri.ip_hash` — ham IP saklanmaz, sha256)
  3. Eşleşme → Admin API `generateLink('magiclink')` + `verifyOtp` ile **gerçek Supabase Auth session** üretilir; `auth_user_id` boşsa self-heal (createUser / orphan linkleme)
  4. Yanıt: `{ok, kullanici, access_token, refresh_token}` — hatalı PIN ve rate-limit **aynı genel mesaj** döner (oracle yok)
- **İstemci oturumu:** `auth-guard.js:6-34` — `sessionStorage['araz_portal_session']` = {user, accessToken, expiry}, süre 30 dk. `SB_HEADERS.Authorization` bir **getter**'dır (supabase-config.js:16-23): her istekte taze token okunur (bayat-token hatası kökten çözülmüş, commit 999158b).
- **refresh_token istemcide saklanmaz/yenilenmez** (index.html:568 yalnızca access_token'ı alır) → 30 dk sonra anon key'e düşülür, kullanıcı yeniden PIN girer. (PMS resepsiyon vardiyası için tasarım kararı gerekli.)
- İstemci tarafı PIN kilidi: `auth-guard.js:107-123` (5 deneme → 30 sn…5 dk artan kilit).
- Başarılı giriş kaydı: `giris_kaydi_ekle` RPC (index.html:572-578) → `giris_kayitlari` tablosu; başarısız denemeler `giris_denemeleri`.
- Kimlik eşleme: `kullanicilar.auth_user_id` ↔ Supabase Auth; e-posta `<id>@gurok.internal` (EF index.ts:48, 105).

## 6. Authorization Architecture

- **Veri tabanlı RBAC** — üç tablo (`docs/kurulum/01-sema-dokumu.sql`):
  - `roller` (satır 1003): 19 rol, `kod`, `seviye: 'otel'|'grup'`, `gizli`
  - `moduller` (satır 934): `kod`, `ad`, `kategori`, `sira`, `aktif` — modül aç/kapa hem UI hem RLS kapatır
  - `yetki_matrisi` (satır 1407): (rol_id × modul_id) → `yetki ∈ {yok, goruntule, kayit, tam}`
- **Sunucu tarafı:** `public.auth_yetki_var(p_modul_kod, p_min_seviye)` SECURITY DEFINER (01-sema-dokumu.sql:262) — `auth.uid()` → `kullanicilar.rol_id` → matris çözümü; `auth_kullanici_rol_id()` (satır 251). Tüm RPC'ler ve RLS bu motoru kullanır.
- **İstemci tarafı (yalnız UX):** `kullaniciYetkileriGetir()` (auth-guard.js:40-51) → `{modul_kod: yetki}` haritası; index.html `MODULLER` listesi ve `nav-drawer.js` `ND_MODULLER` listesi bununla filtrelenir (izinli seviyeler: goruntule/kayit/tam). `requireRole(user, roller)` (auth-guard.js:75) eski `rol` enum'una bakar, sayfa içi kabuk kontrolüdür — **yetki gerçek kararı RLS/RPC'de**.
- **Onay motoru:** `onay-motoru.js` — çok aşamalı onay (depo → cost → mdr/direktor/gm/ust_yonetim, tutar eşikli). Karar **sunucuda** `talep_karar_ver` RPC'siyle (onay-motoru.js:71-111, pentest-2 bulgu [2] sonrası); `talep_siparise_donustur` RPC onaylı talebi siparişe çevirir.
- Yönetim UI: `yetki-yonetimi.html` (matris editörü, hücre tıkla: yok→goruntule→kayit→tam; modül aktif/pasif), `kullanici-yonetimi.html` (kullanıcı + PIN + rol + otel ataması; `ROL_KODU_ESKI_ENUM` ile yeni rol kodları eski enum'a düşürülür).

## 7. Supabase Architecture

- **İki ayrı proje:**
  - Ana ERP: `https://xwytofysmgqtqjzkplfi.supabase.co` (supabase-config.js:9) — tüm ERP verisi.
  - Bar müşteri projesi (fiziksel izolasyon): `https://udjpcsjifgdzvfflezaa.supabase.co` (bar-config.js:6) — sadece 3 tablo: `menu_urunler`, `masa_tokenlari`, `siparis_arsiv` (`docs/kurulum/musteri-projesi/01-musteri-sema.sql`); misafir QR akışı anon erişimli, token → Edge Function doğrulaması.
- Edge Functions: ana projede `pin-girisi`, `pin-girisi-test-faz0`, `ai-analiz-sorgula`; müşteri projesinde `masa-yonetim`, `menu-yayinla`, `siparis-gonder` (kaynakları `docs/kurulum/{ana-proje,musteri-projesi}/` altında).
- Migration yaklaşımı: `docs/kurulum/YYYY-MM-DD-*.sql` dosyaları elle **Supabase SQL Editor**'de çalıştırılır; her dosyada TEST + ROLLBACK bölümleri standarttır; doğrulama curl ile (repo genelinde yerleşik desen). Migration tool / CLI yok.
- `rls_auto_enable()` event trigger (01-sema-dokumu.sql:287; bağlama: `2026-09-01-rls-auto-enable-baglama.sql`) — yeni tablolarda RLS'in unutulmasını engeller.
- Yazma güvenliği: `sbYaz()` (ortak.js:53-68) — sessiz başarısız POST'ları kalıcı hata şeridiyle görünür kılar (60+ kontrolsüz fetch'ten sonra eklendi).

## 8. Database Schema

Ana şema dökümü: `docs/kurulum/01-sema-dokumu.sql` (55 tablo). Referans veri: `02-referans-veri.sql` (roller/modüller/yetki matrisi — müşteri verisi içermez).

- **Kimlik/Yetki:** `kullanicilar` (satır 836: id, auth_user_id, ad, pin_hash, rol enum, rol_id, departman, otel_id, depo_id, eposta, aktif, gizli — ayrıca legacy `pin text` kolonu hâlâ mevcut, bkz. §19), `roller`, `moduller`, `yetki_matrisi`, `giris_kayitlari` (2026-08-05-giris-kayitlari.sql), `giris_denemeleri`.
- **Mal Kabul:** `mal_kabuller` (satır 891, otel_id NOT NULL), `mal_kabul_urunleri`, `uygunsuzluklar`, `skt_kayitlari`, `koli_etiketleri`.
- **Stok:** `stok` (urun_kodu+depo_kodu benzersiz, otel_id), `stok_hareketleri`, `stok_minimumlar`, `sayim_oturumlari`, `sayim_detaylari`; RPC `stok_ekle`/`stok_transfer` (satır 320/340).
- **Satın Alma:** `ic_talepler` + `ic_talep_kalemleri`, `satin_alma_talepleri` + kalemleri, `teklif_talepleri` + kalemleri, `tedarikci_teklifler/kalemler/urun_eslesme`, `siparisler` + `siparis_kalemleri`, `ln_siparisler` (LN Infor entegrasyon girişi), `talep_onay_gecmisi`.
- **Ürün:** `urunler`, `urun_birim_donusum`, sınıflandırma tabloları (`2026-07-26-urun-siniflandirma-sema.sql`).
- **Muhasebe:** `cariler`, `cari_hareketler`, `faturalar` + `fatura_kalemleri`, `gelen_efaturalar`, `hesap_plani`, `yevmiye_fisler` + `yevmiye_kalemleri`, `banka_kasa_hesaplari` + `banka_kasa_hareketleri`, `cek_senetler`, `demirbaslar` + `amortisman_kosustu`, `butce_kayitlari`, `doviz_kurlari`, `mali_donemler`, `edefter_*`, `sene_sonu_kapanislar`, `virmanlar`.
- **F&B Bar (ana proje):** `menu_urunler`, `recete_bilesenleri`, `bar_siparisleri` (**`oda_no text`** — PMS için önemli), `bar_siparis_kalemleri`, `stok_rezervasyonlari`; enum `bar_durum`, `rezervasyon_durum` (`2026-07-22-bar-01-sema.sql`). Reçete tüketimi: `receteler`, `recete_kalemleri`, `recete_tuketimleri`.
- **Sistem:** `audit_log`, `excel_import_gecmisi/satirlari`, kayıtlı filtreler (`2026-08-04-kayitli-filtreler.sql`), AI view'ları (`2026-08-01-ai-faz1-views.sql`), intent RPC'leri (`2026-08-02-ai-faz2-intent-rpc.sql`).

## 9. RLS Architecture

- Tüm tablolarda `enable row level security`; politikasız tablo taraması rutin (`.github` commit'leri + `docs/kurulum/2026-08-10-politikasiz-tablolar.sql`, `2026-08-23-sistemik-rls-denetim.sql`).
- **Standart politika deseni** (örnek `2026-07-31-otel-izolasyon-faz3-dalga4.sql:22-29`):
  `using (public.auth_yetki_var('modul_kod','goruntule') and public.auth_otel_erisim(otel_id::text))`
  ve yazma için aynı koşullu `with check`.
- Anon kilitleme: `2026-08-09-anon-tablo-kilit.sql`, `2026-08-09-guvenlik-pentest-adim3-public-revoke.sql`, `2026-08-23-auth-kullanici-rol-id-anon-revoke.sql`, `2026-07-28-anon-rls-kapatma.sql` — kullanicilar/yetki_matrisi gibi tablolar anon'a kapalı; `kullanicilar_genel` view'ı yalnız oturumlu erişim (index.html:819-831 yorumu).
- SECURITY DEFINER fonksiyon kapsamı denetimi: `2026-08-10-definer-fonksiyon-kapsami.sql` (bar RPC'leri dahil tüm definer fonksiyonlara içsel yetki/otel kontrolü).
- Pentest dalgaları 1-4 remediation dosyaları `docs/kurulum/2026-08-09-*` ve `2026-08-10-*`; özet rapor `2026-08-09-pentest-remediasyon-raporu.md`.

## 10. Hotel / Tenant Isolation

- **Model:** otel-seviyesi izolasyon (depo-seviyesi değil) + merkez istisnası. Tasarım: `docs/kurulum/2026-07-31-otel-izolasyon-tasarim.md`; uygulama: `2026-07-31-otel-izolasyon-faz1.sql` (yardımcılar), `-faz2-pilot.sql` (stok+faturalar), `-faz3-dalga4.sql`, `2026-08-10-alt-tablo-otel-kapsami.sql` (22+ politika).
- Yardımcılar (SECURITY DEFINER): `auth_otel_id()`, `auth_tum_oteller()`, `auth_otel_erisim(p_otel)` — `kullanicilar.otel_id` + `kullanicilar.tum_oteller` bayrağı (merkez kullanıcıları tüm otelleri görür).
- Kapsam: 22 tablo otel-scoped; paylaşımlı (bilerek ortak): `urunler`, `hesap_plani`, `roller`, `moduller`, `yetki_matrisi`, `cariler` (master), `doviz_kurlari`.
- **Kullanıcı → otel ilişkisi:** `kullanicilar.otel_id` ('810'|'811' enum `public.otel_id`); atama UI'ı `kullanici-yonetimi.html:80-86` (810 / 811 / boş = Her İkisi). Oturum nesnesinde `otelId` taşınır (index.html:484, EF index.ts:182).
- Tip borcu: `otel_id` 17 tabloda enum, 7 tabloda text — politikalar `::text` cast ile normalize eder (faz1.sql:8-9); yeni PMS tablolarında bu tutarlılığa dikkat.
- İstemci sabitleri: `otel-config.js` — `OTEL_ISIMLERI`, `MERKEZI_DEPO`, `BAR_DEPOLARI` (otel etiketli) ve tam departman dizini `DEPOLAR_810/811`.

## 11. Shared Components

| Dosya | İçerik |
|---|---|
| `auth-guard.js` | oturum, requireLogin/requireRole, yetki haritası, PIN kilidi, escapeHtml ön-ortak `agEsc` |
| `supabase-config.js` | SB_URL/SB_KEY/SB_HEADERS (getter'lı Bearer) |
| `otel-config.js` | otel sabitleri, departman/depo dizinleri, `merkeziDepoKodu`, `otelFromDepoId`, `depoAdi` |
| `ortak.js` | `toast`, `escapeHtml`, `jsAttrStr` (inline onclick XSS koruması), `sbYaz`, `bugunYerelStr`/`yerelTarihStr` (UTC tuzağı düzenlemesi), `kModal/aModal`, `sLD/hLD`, `loadXlsxLib`, birim dönüşüm |
| `onay-motoru.js` | çok aşamalı onay + `talep_karar_ver`/`talep_siparise_donustur` RPC köprüleri |
| `tablo.js` | `window.Tablo` — Excel benzeri grid + sütun-altı operatör filtresi (`Tablo.olustur`) |
| `filtre.js` | `window.Filtre` — Türkçe-duyarlı predicate motoru (text/number/date/multi_select/boolean) |
| `ortak-excel.js` | spec-tabanlı Excel dışa/içe aktarma motoru (`excelSutunStilUygula` vb.) |
| `nav-drawer.js` | bağımsız sayfalarda hamburger modül menüsü (yetki filtreli) |
| `bar-config.js` | müşteri projesi bağlantı sabitleri (tek kaynak; CI çoğaltmayı yasaklar) |
| `qr-mini.js`, `efatura-adapter.js`, `fetch-kur.js` | QR, e-Fatura, döviz kuru yardımcıları |
| `araz_veritabani.js` | statik ürün/firma kataloğu (LN Infor anlık görüntüsü) |
| `theme.css` | ortak tema değişkenleri |

## 12. Navigation Architecture

- Portal: `index.html` `MODULLER` dizisi (index.html:401-462) — id, ad, url, `moduller:[kod...]`, svg; sidebar + modül grid'i yetki haritasıyla filtrelenir (index.html:611-618).
- Bağımsız sayfalar: `nav-drawer.js` `ND_MODULLER` (nav-drawer.js:8-75) — aynı yapı; **iki liste elle senkron tutulur, yeni modül İKİSİNE de eklenmelidir** (CI bunu denetlemez — bilinen tekrar riski).
- Modül kayıt zinciri (yeni modül eklemek için 4 nokta): (1) `moduller` tablosuna satır + `yetki_matrisi` dağıtımı (SQL), (2) `index.html MODULLER`, (3) `nav-drawer.js ND_MODULLER`, (4) modül HTML sayfası (standart head sırası + `requireLogin`).
- Sekme sistemi iframe'li; hub sayfaları (`muhasebe.html:57+`) kart grid'iyle alt modülleri açar.

## 13. Existing ERP Modules

- **Mal Kabul:** `mal-kabul-v2.html` (hub) + `mal-kabul-liste/izleme/skt/uygunsuzluk/lnexport/siparistakip.html` — modül kodları `mal_kabul_form`, `mal_kabul_kalite`
- **Stok Takip:** `stok-takip.html` (`stok_takip`), Ürün Yönetimi: `urun-yonetimi.html`, `urun-tanimlama.html`
- **Depo Siparişleri:** `depo-siparis.html` (`depo_siparis`)
- **Satın Alma:** `satin-alma.html` + talepler/siparistakip/siparisolustur/siparisler/fiyatkontrol/iade/firmalar/teklif-toplama/skorkart (`ic_talep`, `siparis_*`, `fiyat_kontrol`, `firma_yonetimi`, `tedarikci_skorkart`)
- **Muhasebe:** `muhasebe.html` + 16 alt sayfa (hesap planı, cariler, faturalar, banka, çek/senet, demirbaş, yevmiye, e-defter, e-fatura, mizan, bütçe, dönem/denetim, sene sonu, kur, asistan) — 20 modül kodu index.html:434'te listelenir (`denetim_izi`, `e_fatura` vb.)
- **F&B Bar:** `bar.html` (hub), `bar-masa-yonetimi.html`, `bar-garson.html`, `bar-menu-yonetimi.html`, `bar-menu.html` (müşteri tarafı, QR), `bar-siparis-kuyrugu.html` (`bar_siparis_yonetimi`)
- **Diğer:** `gunluk-tuketim.html`, `trend-raporlama.html`, `analiz-merkezi.html` (AI), `giris-kayitlari.html`, `kullanici-yonetimi.html`, `yetki-yonetimi.html`, `muhasebe-denetim.html`

## 14. Audit / Logging

- **`audit_log`** tablosu (01-sema-dokumu.sql:375): action, entity_type, entity_id, detail, kullanici_ad, zaman + `auth_user_id`.
- İstemci deseni: her modülde `auditLogYaz(action, ...)` → REST POST (örn. kullanici-yonetimi.html:119); global köprü `window.arazAuditLog` (muhasebe-denetim.html:159).
- **Bütünlük:** `tg_audit_log_damgala` BEFORE INSERT trigger (`2026-08-01-audit-log-butunluk.sql`) — `auth_user_id = auth.uid()` damgalar, istemcinin gönderdiği `kullanici_ad` gerçek adla EZİLİR (sahtecilik kapatıldı).
- Bağımsız denetim kaydı: event trigger migration'ı (commit 541e085, N-1).
- Giriş denetimi: `giris_kayitlari` (sadece yönetici okur; INSERT yalnız service_role — `2026-08-05-giris-kayitlari.sql`) + `giris_denemeleri` (başarısız denemeler, ip_hash).
- Görüntüleyiciler: `muhasebe-denetim.html` (Denetim İzi sekmesi, limit 500), `giris-kayitlari.html` (limit 2000).

## 15. Testing Infrastructure

- **Unit test yok.** Doğrulama üç katmanda:
  1. **Statik (CI):** `scripts/check.mjs` — kök .js sözdizimi (`node --check`), paylaşılan script yükleme sırası, UTC tarih tuzağı yasağı (`toISOString().split('T')[0]` hatası), bar-config tek kaynağı. Çalıştırıcı: `.github/workflows/statik-kontroller.yml`.
  2. **SQL yerleşik test:** her migration dosyasında TEST senaryoları + ROLLBACK bölümü; doğrulama **curl** ile beklenen-yanıt deseni (örn. `docs/superpowers/plans/2026-07-22-fb-bar-veri-modeli-rezervasyon.md` Task 1-3).
  3. **Canlı:** `scripts/canli-sonda.mjs` (güvenlik sondası, workflow), k6 salt-okuma yük testi `scripts/yuk-testi/k6-okuma.js` + `sonuc-ozet.md`.
- Yeni PMS sayfaları `check.mjs` yükleme-sırası ve sözdizimi taramasına otomatik girer (kök taraması).

## 16. PMS İçin Yeniden Kullanılabilecek Sistemler

- **Kiralama/ayan müsaitlik modeli — doğrudan analog:** `stok_rezervasyonlari` (`aktif|serbest|kullanildi`) + `bar_kullanilabilir_stok = stok − SUM(aktif rezervasyon)` formülü ve `bar_siparis_olustur`'ın **atomik hard-block** (kısmi rezervasyon yok, overselling engel) deseni (`docs/kurulum/2026-07-22-bar-02-rpc.sql`) — oda müsaitliği/çakışma engeli için birebir örnek.
- **Oda-ücreti tohumu:** `bar_siparisleri.oda_no` kolonu zaten var ("yalnız ücretli kalem varsa dolu" — bar-01-sema.sql:40) → folio/oda-charge bağlantısının mevcut ucu.
- **Atomik RPC deseni:** `fatura_kaydet`, `mal_kabul_kaydet`, `teklif_talebi_olustur` (`2026-08-01-tier1-atomik-rpc.sql`) — plpgsql + SECURITY DEFINER + `raise exception` = tek transaction otomatik rollback; check-in/check-out/folio post için kalıp.
- **Yetki motoru:** `moduller` + `yetki_matrisi` + `auth_yetki_var` — PMS modül kodları (`pms_*`) tek INSERT + matris dağıtımıyla eklenir; `moduller.aktif=false` modülü RLS dahil kapatır (KURULUM-REHBERI.md adım 9).
- **Otel izolasyonu:** `public.otel_id` enum + `auth_otel_erisim()` + `kullanicilar.otel_id/tum_oteller` — rooms/guests/reservations tabloları için hazır.
- **Rapor/liste UI:** `tablo.js` + `filtre.js` (Room Rack, rezervasyon listeleri, tarih filtreleri dahil — `filtre.js` date op'ları: this_week/last7/overdue vb.) + `ortak-excel.js` (export/import).
- **Onay akışı:** `onay-motoru.js` (tutar eşikli katmanlar) — rate değişikliği / grup rezervasyonu onayı için.
- **Denetim:** `audit_log` + damga trigger'ı; `giris_kayitlari` deseni.
- **Portal kabuğu:** iframe sekme sistemi + `MODULLER`/`ND_MODULLER` kayıt; KPI şeridi deseni (index.html:768-792) — occupancy/arrival KPI'ları için.
- **Departman/zemin bilgi:** `otel-config.js` DEPOLAR listelerinde Resepsiyon (COB201/ROB201), Rezervasyon (COB301/ROB301), Misafir İlişkileri (COB401/ROB401), Kat Hizmetleri (CYA201/RBYA21), Odalar (CYA202/RBYA22), Oda Servisi (RSM308) birimleri zaten tanımlı — housekeeping/front-office organizasyon eşlemesi hazır.
- **Misafire dönük akış:** izole müşteri projesi + QR (`bar-menu.html?t=<token>` + `masa_tokenlari`) — misafir self-servis (online check-in vb.) için izolasyon deseni.
- **PWA + oturum:** `sw.js`/`manifest.json` kayıtlı; `check.mjs` yeni sayfaları otomatik kapsar.
- **Sicil/deneyim notu:** `2026-07-31-otel-izolasyon-tasarim.md` fazlı uygulama + rollback + test planı şablonu.

## 17. PMS İçin Eksik Sistemler

- **Veri modeli yok:** room_types, rooms, guests, reservations, folio, folio_charges, payments, rates/seasons tablolarının hiçbiri mevcut değil (§8 tablo listesinde yok; "oda/misafir" taraması yalnız `oda_no` ve departman adlarında sonuç verdi).
- **Modül kodları yok:** `moduller` tablosunda PMS kodu yok → RLS ve nav hiçbir PMS ekranını tanımıyor.
- **Tarih-uzamlı müsaitlik motoru yok:** `stok_rezervasyonlari` miktar-temelli, tarih boyutu yok; rezervasyon çakışması için date-range/EXCLUDE USING daterange yaklaşımı repoda hiç kullanılmamış (yeni desen geliştirilmeli).
- **Misafir kimlik modeli yok:** `kullanicilar` personel-bazlı; misafir PII (kimlik, pasaport, KVKK) için yeni tablo + RLS + veri minimizasyonu gerekecek.
- **Folio/muhasebe köprüsü yok:** `cari_hareketler`/`faturalar` tedarikçi-muhasebesi odaklı; oda-folio → muhasebe entegrasyonu (oda servisi bar siparişlerinin folio'ya düşmesi dahil) tasarlanmalı.
- **Ödeme altyapısı yok:** `banka_kasa_*` iç kasa hareketleri içindir; misafir ödemesi/sanal POS yok.
- **Housekeeping durum makinesi yok** (temizlik status geçişleri/trigger yok).
- **Fiyat motoru yok:** `menu_urunler.fiyat` statik; sezon/tarih-uzamlı rate yok.
- **Refresh-token akışı yok** (§5) — resepsiyon 8-12 saatlik vardiyası için oturum stratejisi kararı gerekli.
- **Gerçek zamanlı yayında kullanılmıyor:** repoda Supabase Realtime aboneliği görülmedi (not verified — derin tarama yapılmadı); Room Rack canlı güncelleme istiyorsa yeni desen.

## 18. Critical Files Astra Should Read

1. `AGENTS.md` — çalışma kuralları (plan onayı zorunlu)
2. `index.html` — giriş + portal kabuğu + `MODULLER`
3. `auth-guard.js` — oturum/yetki çekirdeği
4. `supabase-config.js` — bağlantı + SB_HEADERS
5. `otel-config.js` — otel/departman sabitleri
6. `ortak.js` — ortak yardımcılar + `sbYaz` + tarih düzenlemesi
7. `onay-motoru.js` — onay deseni
8. `tablo.js` + `filtre.js` + `ortak-excel.js` — liste/filtre/Excel UI altyapısı
9. `nav-drawer.js` — `ND_MODULLER` (modül kayıt noktası 3)
10. `docs/kurulum/01-sema-dokumu.sql` — 55 tablo + `auth_yetki_var` + `stok_ekle` (en azından satır 251-360, 836-941, 1176-1236, 1407-1421)
11. `docs/kurulum/02-referans-veri.sql` — rol/modül/matris tohumu
12. `docs/kurulum/2026-07-22-bar-01-sema.sql` — tablo + RLS + modül kayıt şablonu (PMS şeması için en yakın kalıp)
13. `docs/kurulum/2026-07-22-bar-02-rpc.sql` — müsaitlik/atomik rezervasyon RPC deseni
14. `docs/kurulum/2026-08-01-tier1-atomik-rpc.sql` — atomik kayıt RPC deseni (check-in/out için)
15. `docs/kurulum/2026-07-31-otel-izolasyon-tasarim.md` (+ faz1/2/3 SQL) — izolasyon modeli ve fazlı uygulama şablonu
16. `docs/kurulum/ana-proje/pin-girisi/index.ts` — auth EF
17. `docs/kurulum/2026-08-05-giris-kayitlari.sql` — denetim tablosu deseni
18. `docs/kurulum/2026-08-01-audit-log-butunluk.sql` — audit damga trigger'ı
19. `kullanici-yonetimi.html` + `yetki-yonetimi.html` — kullanıcı/otel/rol yönetimi
20. `muhasebe.html` — hub sayfa deseni (PMS hub'ı için)
21. `scripts/check.mjs` — CI'in yeni dosyalardan beklediği kurallar
22. `docs/KURULUM-REHBERI.md` — kurulum/deploy akışı

## 19. Security Concerns

1. **Anon key istemcide açık (tasarım gereği):** güvenlik tamamen RLS'e yaslanır (supabase-config.js:6-7). Anon kilit migrations'ları bunu derinleştirmiş; **yeni PMS tablolarında politika yazmayı atlamak = veri sızıntısı**.
2. **Legacy `kullanicilar.pin text` kolonu hâlâ şemada** (01-sema-dokumu.sql:846) — `pin_hash` (bcrypt) yanında düz metin kolonu duruyor. İçinde veri kalıp kalmadığı **not verified**; PMS öncesi temizlik/drop değerlendirilmeli.
3. **İstemci tarafı requireRole yalnız kabuk koruması:** `yetki-yonetimi.html:49` ve `kullanici-yonetimi.html:62` kendileri bunu açıkça beyan eder; gerçek engel RLS/RPC'de. PMS ekranlarında da aynı hiyerarşi korunmalı.
4. **audit_log istemci-yazılır** ancak trigger damgası sahteciliği kapatır (§14); audit_log üzerinde UPDATE/DELETE politikalarının sertliği **not verified**.
5. **Oturum 30 dk + refresh yok** (§5) — hem UX hem resepsiyon sürekli PIN girişi riski; refresh_token akışı veya uzun oturum kararı PMS tasarımına dahil edilmeli.
6. **`bar_siparis_olustur` anon grant'ı tartışmalı:** plan fcd78be "anon'a KAPALI olmalı" düzeltmesini getirdi (`2026-08-10-pentest4-yuksek-uc-bulgu.sql`); canlı durumu **not verified**. PMS misafir akışında aynı kalıbı kopyalamadan önce güncel duruma bakılmalı.
7. **Tip tutarsızlığı:** `otel_id` enum/text karışık (§10) — `::text` cast disiplini yeni PMS SQL'inde zorunlu.
8. **Edge Function ön koşulları:** `pin-girisi` için "Enforce JWT Verification" KAPALI olmalı (index.ts:38-40); DAHILI_EMAIL_DOMAIN EF ve otel-config.js'te çift tanımlı (index.ts:33-36 kendisi riski belgeliyor).
9. CORS `*` (EF index.ts:57-60) ve GitHub Pages'te CSP bulunmaması **not verified** (genel HTML taramasında CSP meta görülmedi) — XSS koruması `escapeHtml`/`jsAttrStr` disiplinine yaslanıyor; PMS sayfaları bu iki yardımcıyı kullanmalı.
10. Service-role anahtarı repoya ASLA girmez (`.gitignore` başındaki uyarı bloğu); tek seferlik kurulum araçları production'dan kaldırılır (KURULUM-REHBERI.md:47-52).

## 20. Recommended PMS Implementation Order

AGENTS.md gereği her faz: plan → onay → `docs/kurulum/YYYY-MM-DD-pms-*.sql` (TEST + ROLLBACK) → SQL Editor'de kullanıcı çalıştırır → curl doğrulama → docs senkronizasyonu.

1. **Modül kaydı + kabuk:** `moduller`e `pms_*` kodları (öneri: `pms_rezervasyon`, `pms_front_office`, `pms_housekeeping`, `pms_folio`) + `yetki_matrisi` dağıtımı + `index.html MODULLER` + `nav-drawer.js ND_MODULLER` kaydı; `pms.html` hub (muhasebe.html deseni).
2. **Şema Faz 1 — Oda temeli:** `oda_tipleri`, `odalar` (otel_id NOT NULL, `oda_no` benzersiz per otel) + tam RLS deseni (`auth_yetki_var AND auth_otel_erisim`) — kalıp: `2026-07-22-bar-01-sema.sql`.
3. **Şema Faz 2 — Misafir:** `misafirler` (PII minimizasyonu + otel kapsamı; KVKK notu).
4. **Rezervasyon + müsaitlik:** `rezervasyonlar` + `rezervasyon_durumu` enum + çakışma engeli. Tarih-uzamlı UNIQUE/EXCLUDE constraint önerilir (repoda yeni desen); atomik `rezervasyon_olustur` RPC'si `bar_siparis_olustur` hard-block kalıbıyla.
5. **Check-in / Check-out:** durum makinesi RPC'leri (`rezervasyon_gir/`_cik`) — `talep_karar_ver`/`fatura_kaydet` deseni; state geçişleri yalnız RPC'de.
6. **Housekeeping:** oda durumu (kirli/temiz/bakımda) + görev akışı; `otel-config.js` Kat Hizmetleri/Odalar departmanlarıyla eşleme.
7. **Folio:** `folio_hareketleri` + `bar_siparisleri.oda_no` bağlantısı (oda servisi ücretleri folio'ya düşer) + muhasebe köprüsü (`faturalar`/`cari_hareketler`).
8. **Ödemeler:** `banka_kasa_hareketleri` entegrasyonu (sanal POS kapsam kararı ayrı).
9. **Rates:** sezon/tarih-uzamlı fiyat tablosu + `onay-motoru.js` ile rate değişikliği onayı.
10. **Raporlar:** occupancy/arrival/departure view'ları (`2026-08-01-ai-faz1-views.sql` view deseni) + `tablo.js`/`ortak-excel.js` ekranları.
11. **Her fazda:** `check.mjs` CI geçişi, curl doğrulama, `D:\ERP-Bilgi-Haritasi` Obsidian doküman güncellemesi, rollback planı (izolasyon tasarım md'sindeki şablon).

---
*Rapor yalnızca keşif amaçlıdır; hiçbir kod/şema değişikliği önerisi uygulanmamıştır. Uygulamadan önce AGENTS.md uyarınca plan onayı gerekir.*
