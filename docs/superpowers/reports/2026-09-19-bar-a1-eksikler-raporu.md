# Bar A1 — Eksiklerin Tamamlanması Raporu

**Tarih:** 2026-09-19 · **Dal:** `bar-a1` (yerel) · **Önceki rapor:** `2026-09-18-bar-a1-rapor.md`
**Üretim:** Yazma yok. Push, deploy, canlı migration ve Aşama 2 **yok**.
Durum etiketleri: **KANITLANDI** · **EKSİK** · **KARAR GEREKİYOR**.

| # | Madde | Durum |
|---|---|---|
| 1 | 100 → 90 → −20 → 70 ve tekrar uygulanamama | **KANITLANDI** (önce bir hata bulundu ve düzeltildi) |
| 2 | Sayım tablolarının canlı erişimi (salt okuma) | **EKSİK** — sorgu hazır ve provası yapıldı; canlıda çalıştırılması sizin parolanızı gerektiriyor |
| 3 | Ön büro istisna çözüm ekranı tasarımı | **KARAR GEREKİYOR** — tasarım hazır, 5 karar noktası |
| 4 | Gerçek tarayıcıda izole akışlar | **KANITLANDI** (iki sınırlamayla, aşağıda) |
| 5a | Eski ekranlarla geçiş provası | **KANITLANDI** + **KARAR GEREKİYOR** (yayın sırası) |
| 5b | Müşteri şeması ve canlı Edge kodu farkı | **EKSİK** — Supabase Dashboard'da oturum yok |

---

## 1. Sayım senaryosu — KANITLANDI (hata bulundu, düzeltildi)

**Bulgu:** Önceki raporda "sayım kararı karşılandı" dedim; bu **yanlıştı**. `stok_sayim_onayla`
farkı **onay anındaki** stoğa göre hesaplıyordu: sayımda 100, fiziksel 90, arada çıkış 20 → onayda
90 − 80 = +10 → sonuç **90**. Yani sayılan miktar güncel stoğun üzerine yazılıyordu. Önceki E4
testi yalnız bekleyen düzeltme yolunu sınıyordu, doğrudan yolu değil.

**Düzeltme:** fark = `sayilan_miktar − sistem_miktar` (sayım anı), o anki stoğa delta olarak
eklenir. Sistem ya da sayılan miktarı eksik satırda `SAYIM_EKSIK` ile tek satır yazılmadan durur.

| Test | Sonuç |
|---|---|
| E7 100 → fiziksel 90 → arada çıkış 20 → onay | stok **70**, tek sayım hareketi |
| E8 aynı sayımın ikinci onayı | `zaten_onaylandi`, stok 70 |
| E9 aynı sayımın **eşzamanlı** iki onayı | fark bir kez uygulandı |
| E10 aynı senaryo, rezervasyonla çelişen yol (75 ayrılmış) | düzeltme bekler, stok 80, bekleyen fark −10 |
| E11 rezervasyon kalkınca uygula; eşzamanlı ikinci + sonraki üçüncü deneme | **70**; diğerleri `zaten_uygulandi` |
| K5 negatif kontrol: eski formül geri konunca | **90** çıkıyor ve E7 bunu yakalıyor |
| Tarayıcı (bölüm 4) | LIMON 100 → 90 → −20 → **70**; BIRA bekledi, rezervasyon kalkınca 80 → **70** |

## 2. Sayım tablolarının canlı erişimi — EKSİK (sizin çalıştırmanız gerekiyor)

Hazır: `docs/kurulum/2026-09-19-sayim-rls-salt-okuma.sql`. `-SaltOkuma` kipi veritabanı düzeyinde
salt okuma **zorlamadığı** için dosyanın kendisi `begin transaction read only … rollback` içinde.
Çıktı yalnızca sayı, politika adı ve tarih içerir. Cost_control yetkisi **genişletilmedi**; sorgu
yalnız mevcut bir cost_control kullanıcısının kimliğiyle ne gördüğünü ölçer.

İzole prova (üretim dökümü): RLS açık, `sayim_oturumlari` yalnız RESTRICTIVE, `sayim_detaylari`
politikasız; tabloda 1 satır var, cost_control kullanıcısı **0** görüyor.

Çalıştırma komutu raporun sonunda.

## 3. Ön büro istisna çözüm akışı — KARAR GEREKİYOR

Tasarım: `docs/superpowers/specs/2026-09-19-onburo-istisna-cozum-ekrani.md`. Öneri: `pms-folio.html`
içinde, yalnız açık istisna varken görünen küçük bir bölüm; "Folyoya yaz" (açık folyo seçimi,
varsayılan seçim yok, misafir yeniden doğrulama zorunlu, farklı misafir uyarısı) ve "Tahsil
edilemedi" (gerekçe zorunlu). Kod yazılmadı. Kararlar: K1 yer · K2 "tahsil edilemedi" için yetki
seviyesi · K3 başka misafirin folyosuna yazma sunucuda da kısıtlansın mı · K4 bekleme süresi ·
K5 bar ekranına geri bildirim.

## 4. Gerçek tarayıcı — KANITLANDI

İzole ortam: `scripts/bar-edge-e2e/tarayici-ortami.mjs` (A1'li DB + GoTrue + iki PostgREST + Edge
Runtime; ekranlar bu çalışma kopyasından, yalnız iki yapılandırma dosyası yerel adrese
yönlendirildi). Uygulama içi tarayıcıda:

| Akış | Görülen |
|---|---|
| Müşteri QR menüsü | Odasız ücretli sipariş engellendi; boş oda (103) "konaklama yok"; oda 101 kabul → DB `qr / bekliyor`. Fiyat ana projede 300'e çıkınca bayat menü "250 ₺ → 300 ₺" gösterdi, sepet korundu, ikinci gönderim kabul edildi |
| Kuyruk — doğrulama | Doğrula (beyan sorusu) → `dogrulandi`; Reddet (neden) → `iptal / reddedildi` |
| Kuyruk — kapalı folyo | `kayit` personeli "servis edildi" deyince "yetkiniz yok"; `tam` şef → `istisna_bekliyor`, stok 2 → 1, borç 0, istisna açık, kartta "ön büro çözümü bekliyor" |
| Garson | 811 seçilince 0 bar (kapsam); 810'da tek masa; ücretli siparişte doğrulama paneli, kutu işaretlenmeden Doğrula pasif, işaretlenince doğrulandı; ücretsiz siparişte panel yok |
| Kuyruk — teslim + iptal | Doğrulanmış Viski teslim → borç **300,00** (sipariş anındaki fiyat); hazırlanmış Bira ×2 iptalinde miktar boşken engellendi, 1 + "döküldü" + açıklama → `iptal_kullanimi`, stok 10 → 9 |
| Stok-takip — sayım | Bölüm 1 son satırı; kısmi uygulama açık uyarıyla, bekleyen listesi; rezervasyon varken Uygula reddedildi |

**Sınırlamalar:** (a) Tarayıcı bölmesi yerel `confirm/prompt/alert` pencerelerini kendiliğinden
kapattığı için bu çağrılar bir kayıt fonksiyonuyla değiştirildi: soru metni doğrulandı, yerel
pencerenin tıklanması sınanmadı. (b) Bölme ekranda çizilmediği için sayım onay penceresinin kayma
animasyonu bitmedi ve iki düğmeye fare tıklaması ulaşmadı; bu iki adımda **gerçek düğmenin
kendi tıklama işleyicisi** DOM'dan tetiklendi. (c) PIN giriş ekranı sınanmadı; oturum GoTrue
parola girişiyle alındı. (d) Ayrı bulgu gereği sayım tablolarına **yalnız bu ortamda** okuma
politikası eklendi. Sayım oluşturma ekranı bu yüzden sınanmadı.
Küçük düzeltme: `REZERVE_STOK` metni "çıkış yapılamaz" diyordu; sayımda yanıltıcıydı, genelleştirildi.

## 5a. Eski ekranlarla geçiş provası — KANITLANDI + KARAR GEREKİYOR

`scripts/bar-edge-e2e/gecis-provasi.test.mjs`: `origin/main` (9c06661) ekranları ve eski
`rapid-handler`, gerçek Edge/GoTrue/PostgREST üzerinde. **13/13 ölçüm**:

| Aralık | Ölçülen |
|---|---|
| Yeni menü + eski DB | Ücretli sipariş çalışıyor |
| Yeni kuyruk + eski DB | Hazırlık/teslim çalışıyor; **iptal çalışmıyor** |
| Yeni stok-takip + eski DB | Sayım onayı **güvenli başarısız** (hiçbir şey yazılmaz) |
| Eski menü + A1 | Ücretli sipariş ham `FIYAT_DEGISTI` ile reddediliyor |
| Eski garson + A1 | Ücretli sipariş reddediliyor; ücretsiz çalışıyor |
| Eski kuyruk + A1 | Doğrula düğmesi yok → ücretli sipariş **takılı kalıyor**; iptal çalışmıyor; ücretsiz teslim çalışıyor |
| **Eski stok-takip + A1** | **Sayım yanlış yazıyor: 70 yerine 90 (veri bozulması)** |
| Eski rapid-handler + A1 | Çalışıyor ama eski açık sürüyor (810 → 811 masaları, pasif kullanıcı) |
| Yeni ekranlar + eski rapid-handler | Masa listesi geliyor; takılı sipariş yeni kuyrukta doğrulanıp hazırlanıyor |

**KARAR GEREKİYOR — yayın sırası.** Ölçüme göre tüm ekranları **migration'dan önce** yayınlamak
daha güvenli: o aralıkta yalnız iptal ve garson doğrulama paneli geçici hata verir, sayım
güvenli şekilde başarısız olur. Tersi sırada (migration önce) eski stok-takip veri bozar. Öneri:
(1) tüm ekranlar push, (2) hemen yedek + migration, (3) `rapid-handler` deploy. Önceki raporda
"önce yalnız menü" önermiştim; bu ölçüm o öneriyi değiştiriyor. Not: sayım tabloları canlıda
kapalıysa (madde 2) eski stok-takip riski pratikte oluşmaz; yine de sıra buna dayanmamalı.

## 5b. Müşteri şeması ve canlı Edge kodu — EKSİK

Uygulama içi tarayıcıda Supabase Dashboard oturumu yok. Salt okuma için gereken: müşteri projesi
(`udjpcsjifgdzvfflezaa`) Edge Functions → `hyper-api`, `rapid-handler`, `smooth-service` kod
görünümü ve Table Editor'da `masa_tokenlari` / `menu_urunler` / `siparis_arsiv` sütunları. Siz
giriş yapınca yalnız okuyup depodaki kodla karşılaştıracağım; hiçbir şeyi değiştirmeyeceğim.

## Yeni test sonuçları

| Takım | Sonuç |
|---|---|
| `bar-a1-guvenlik` (E7–E11 eklendi) | 59/59 |
| `bar-a1-negatif` (K5 eklendi) | 6/6 |
| `gecis-provasi` (yeni) | 13/13 |
| Tarayıcı akışları (bölüm 4) | 6 akış, beklenmeyen sonuç yok |
| Etkilenenlerin yeniden koşusu (değişiklik sonrası) | ekran 26/26, sıra/geri alma 16/16, stok ekran 21/21, Edge 22/22, denetleyici 24 dosya 0 hata |

## Sizden gereken

1. Salt okuma (parolayı siz girersiniz):
   `.\docs\kurulum\sql-uygula.ps1 -Dosya docs\kurulum\2026-09-19-sayim-rls-salt-okuma.sql -SaltOkuma`
   (çalışma dizini `C:\Users\USER\Projects\gurok-bar-a1`), çıktıyı yapıştırın.
2. Uygulama içi tarayıcıda Supabase Dashboard'a giriş (5b için).
3. Kararlar: yayın sırası (5a), istisna ekranı K1–K5 (3).
