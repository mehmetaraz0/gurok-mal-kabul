# Bar A1 — Kararların Uygulanması Raporu (2026-09-19, ikinci tur)

**Dal:** `bar-a1` (yerel). **Üretim:** yazma yok. Push, deploy, canlı migration ve Aşama 2 **yok**.
**Önceki:** `2026-09-19-bar-a1-eksikler-raporu.md`. Durum: **KANITLANDI** · **KOŞULLU GEÇTİ** · **EKSİK** · **KARAR GEREKİYOR**.

| # | Madde | Durum |
|---|---|---|
| 1 | Eski sayım sekmesinin migration sonrası yanlış yazması sunucuda engellenir | ~~KANITLANDI~~ → **erken kapatıldı**; bkz. düzeltme |
| 2 | Yedek, ilk üretim değişikliğinden önce | **KANITLANDI** (plan düzenlendi) |
| 3 | İstisna ekranı K1–K5 | **KANITLANDI** (gerçek tıklamayla dahil) |
| 4 | Önceki tur tarayıcı testleri | **KOŞULLU GEÇTİ** |
| 5 | Sayım oluşturma / listeleme gerçek yetki düzeniyle | **EKSİK** |
| 6 | Yayın sırası | **KARAR GEREKİYOR** |
| 7 | Canlı Edge kodu / müşteri şeması / sayım RLS canlı | **EKSİK** (sizin girişiniz / parolanız gerekiyor) |

---

## 1. Eski sayım sekmesi — KANITLANDI

> **DÜZELTME (2026-09-19, üçüncü tur):** Bu madde erken kapatıldı. Detayları migration'dan ÖNCE okumuş
> ve yazması migration sonrasına kalmış bir sekme okuma engeline takılmıyordu. Yazma yolunda ayrım
> eklendi ve senaryo sınandı: .

**Mekanizma (migration §15b):** Eski ekran farkı istemcide hesaplayıp `stok_ekle` ile yazıyor;
`stok_ekle` normal giriş/çıkışın da yolu olduğu için o çağrı ayırt edilemez. Eski ekran yazmadan
**önce** sayım detaylarını tablodan doğrudan okur ve okuyamazsa tek satır yazmadan durur. Bu yüzden:

1. `sayim_detaylari` tablosundan doğrudan `SELECT` kapatıldı. Yeni ekran detayları
   `stok_sayim_detaylari()` RPC'siyle okur (stok_takip ≥ kayıt + otel kapsamı; sayfalama aynı).
2. İkinci katman: oturumu `onaylandi` yapmak ya da `kismi_uygulandi` bayrağını değiştirmek yalnız
   sunucu sayım fonksiyonlarından mümkün (tetikleyici; sahip rolde bile).

| Kanıt | Sonuç |
|---|---|
| E12 doğrudan okuma | `permission denied` |
| E13 RPC | stok kayıt yetkilisi okur; stok yetkisiz, başka otel, anon reddedilir |
| E14 / E15 | durum ve bayrak sunucu dışında değiştirilemez; sunucu onayı çalışır |
| **Geçiş provası G10** (eski `origin/main` stok-takip + A1, gerçek PostgREST) | eski ekran detay okuyamadı, **0 yazma isteği**, stok 80, oturum onay bekliyor |
| **G11** aynı sayım yeni ekranla | 100 → fiziksel 90 → çıkış 20 → **70**, oturum onaylandı |
| Negatif K6 / K7 | kapatma kaldırılınca okunabiliyor; tetikleyici kaldırılınca onay zorlanabiliyor — testler yakalıyor |
| Geri alma 4b3 | sayım tablolarının yetkisi ve tetikleyicileri A1 öncesiyle birebir |

Not: Bu kapatma cost_control yetkisini **genişletmez**; detay okuma yetkisi onay RPC'siyle aynı
seviyede (stok_takip ≥ kayıt).

## 2. Yedek önce — KANITLANDI (plan)

Plan G9 "Yayın anı" yeniden yazıldı: 0) salt okuma ön kontrolleri → **1) yedek, ilk üretim
değişikliğinden (ekran push, migration, Edge deploy — hangisi önce gelirse) ÖNCE; doğrulanmadan
devam yok** → 2) onaylanan sıra, her adım ayrı `CANLIYA UYGULA` → 3) geri dönüş yolları.

## 3. Ön büro istisna ekranı — KANITLANDI

Kararlarınıza göre:

| Karar | Uygulama | Kanıt |
|---|---|---|
| K1 | `pms-folio.html` içinde, yalnız açık istisna varken görünen bölüm | O1, O9, tarayıcı |
| K2 | "Tahsil edilemedi" `pms_folio = tam` + zorunlu gerekçe (sunucu); çözen/zaman/gerekçe kaydı | B7a–c, O7–O8, negatif K9, tarayıcı |
| K3 | Borç yalnız doğrulanmış konaklamanın (`eski_rezervasyon_id`) açık folyosuna; başka konaklama `FOLYO_BASKA_KONAKLAMA`, bağ yoksa `KONAKLAMA_BAGI_YOK` (sunucu). Ekran yalnız o konaklamanın folyolarını listeler | B8–B10, O2–O3 (ekran atlatılınca sunucu reddetti), negatif K8, tarayıcı |
| K4 | Bekleme yaşı gösterilir; otomatik kapatma / hatırlatma yok | O1, tarayıcı |
| K5 | Bar kuyruğunda "istisna açık" / "çözüldü: borç folyoya yazıldı / tahsil edilemedi" | O10, tarayıcı |

Ekranda yerel `confirm/prompt` kullanılmadı; formlar sayfa içinde. Bu sayede **gerçek tarayıcıda
gerçek tıklamayla** sınandı: kayıt yetkilisi "Göster" → "Folyoya yaz" → folyo seçimi → doğrulama
kutusu işaretsizken engellendi → kutu + not → borç doğru folyoya yazıldı (DB: çözen = ön büro,
not, sipariş tamamlandı). Tam yetkili: açık folyo yokken "Folyoya yaz" pasif ve sebep yazılı →
"Tahsil edilemedi" → gerekçesiz engellendi → gerekçeyle kapandı (DB: çözen = müdür). Bar
kuyruğunda iki çözüm durumu görüldü. Tek istisna: hedef folyo seçimi `form_input` ile yapıldı
(seçim kutusu), düğmeler ve metin girişi gerçek tıklama/klavye.

## 4. Önceki tur tarayıcı testleri — KOŞULLU GEÇTİ

Gerçek kullanıcı tıklamasıyla sınanmış **sayılmayanlar**:
- Kuyrukta doğrulama/ret, kapalı folyoda "servis edildi" sorusu, yeni sipariş iptali: yerel
  `confirm/prompt` bir kayıt fonksiyonuyla değiştirildi. Soru metni doğrulandı; yerel pencere sınanmadı.
- Sayım onay penceresindeki "Onayla" ve bekleyen listesindeki "Uygula": DOM'dan tetiklendi.
- PIN giriş ekranı sınanmadı (oturum GoTrue parola girişiyle kuruldu).

Gerçek tıklamayla sınananlar: müşteri menüsü sepet/oda/gönder, garson otel/bar/masa seçimi,
doğrulama kutusu ve düğmesi, kuyrukta Hazırlanıyor/Hazır/Teslim, iptal formu (miktar, neden,
açıklama, düğme), ön büro istisna bölümü (madde 3).

## 5. Sayım oluşturma / listeleme — EKSİK

Üretim dökümünde sayım tabloları oturum açmış kullanıcıya kapalı (A1 dışı bulgu). Testlerde okuma
politikası **yalnız test ortamına** eklendi; sayım **oluşturma** hiç sınanmadı. Canlı durum salt okuma
sorgusuyla doğrulanmadan ve (gerekiyorsa) ayrı bir düzeltme yapılmadan bu akış tamamlanmış sayılmaz.
A1'in sayım değişiklikleri onay ve bekleyen düzeltme yolunu kapsar.

## 6. Yayın sırası — KARAR GEREKİYOR

15b sonrası ölçülen ara dönem etkileri (`gecis-provasi` 14/14):

| Sıra | Ara dönemde |
|---|---|
| Önce migration, sonra ekranlar | eski kuyrukta ücretli sipariş doğrulanamaz (takılı kalır, yeni kuyrukla çözülür); iptal çalışmaz; eski garson/menü ücretli siparişte reddedilir; eski sayım **güvenli şekilde reddedilir** (yeni) |
| Önce ekranlar, sonra migration | yeni kuyrukta iptal çalışmaz (ölçüldü); sayım onayı güvenli başarısız (ölçüldü); garson doğrulama panelinin hata vermesi **beklenir, ölçülmedi** |

İki sırada da veri bozulması ölçülmedi. Her iki durumda `rapid-handler` migration'dan sonra deploy
edilmeli (Y2). Yedek her durumda önce.

## 7. Sizden gerekenler

1. Salt okuma: `.\docs\kurulum\sql-uygula.ps1 -Dosya docs\kurulum\2026-09-19-sayim-rls-salt-okuma.sql -SaltOkuma`
2. Canlı Edge kodu ve müşteri şeması için uygulama içi tarayıcıda Supabase Dashboard girişi.
3. Yayın sırası kararı.

## Test sonuçları (bu tur)

Toplu koşu (bu turun son hali, hepsi izole):

| Takım | Sonuç | Bu turda yeni |
|---|---|---|
| bar-a1-guvenlik | 67/67 | E12–E15, B7a–c, B8–B10 |
| bar-a1-negatif | 10/10 | K6–K9 |
| stok-guncelleme-tarihi-bar-sira | 17/17 | 4b3 |
| bar-a1-ekran | 36/36 | O1–O10, S0 güncellendi |
| gecis-provasi | 14/14 | G10 (eski reddedildi), G11 |
| bar-edge-e2e | 22/22 | — |
| stok-veri-eksiksizlik | 33/33 | sayım detayı RPC üzerinden sayfalama |
| stok-ekran / stok-guncelleme-tarihi / taban / önce | 21/21 · 14/14 · 9/9 · 9/9 | — |
| migration denetleyicisi | 24 dosya 0 hata; birim 15/15 | — |
| Tarayıcı (bu tur) | istisna ekranı + kuyruk K5, gerçek tıklama | yeni |
