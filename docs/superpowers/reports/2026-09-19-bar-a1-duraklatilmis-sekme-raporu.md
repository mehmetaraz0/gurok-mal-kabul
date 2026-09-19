# Bar A1 — Duraklatılmış Eski Sekme Senaryosu ve Yazma Yolu Ayrımı

**Tarih:** 2026-09-19 (üçüncü tur) · **Dal:** `bar-a1` (yerel) · **Üretim:** yazma yok; push, deploy,
canlı migration, Aşama 2 yok. **Yayın talimatı yok.**

| # | Madde | Durum |
|---|---|---|
| 1 | Duraklatılmış eski sekme: okuma → bekletme → migration → yazma devam; stok değişmemeli | **KANITLANDI** (önce başarısızdı) |
| 2 | "Eski sekme sunucuda engellendi" | **KANITLANDI** — yazma yolunda ayrım; yalnız okuma engeline dayanmıyor |
| 3 | Yeni bulgu: A1 migration'ı dolu `bar_siparisleri` tablosunda duruyordu | **DÜZELTİLDİ ve KANITLANDI** |
| 4 | Plan: tek yayın talimatı, beklenmeyen farkta dur | **DÜZENLENDİ** |
| 5 | Sayım oluşturma / listeleme gerçek yetkiyle | **EKSİK** (açık) |
| 6 | Canlı Edge kodu / müşteri şeması karşılaştırması | **EKSİK** (açık) |
| 7 | Önceki tarayıcı testleri (yerel pencere / DOM tetikleme) | **KOŞULLU** — tamamlanmış sayılmıyor |
| 8 | Yayın sırası | **KARAR GEREKİYOR** |

> **DÜZELTME (önceki rapor):** `2026-09-19-bar-a1-karar-uygulama-raporu.md` madde 1'i ("eski sayım
> sekmesi sunucuda engellendi — KANITLANDI") **erken kapatmıştım.** Okuma engeli, detayları migration'dan
> önce okumuş bir sekmeyi durdurmuyordu; aşağıdaki test ilk koşuda bunu gösterdi.

## 1. Senaryo ve sonuç

`scripts/bar-edge-e2e/gecis-provasi.test.mjs` G12. Gerçek Edge/GoTrue/PostgREST ortamı; eski ekran
`origin/main` (9c06661) `stok-takip.html`'in gerçek betiği:

1. Veritabanı **A1'siz**. Sayım: sistem 100, fiziksel 90. Sayımdan sonra çıkış 20 → stok 80.
2. Eski ekran onayı başlatır: detayları okur, farkı eski kurala göre hesaplar (90 − 80 = **+10**).
3. Eski ekranın **ilk yazma isteği** (`rpc/stok_ekle`) tutulur.
4. A1 migration'ı tek işlemde uygulanır, PostgREST şema önbelleği yenilenir.
5. Tutulan istek (ve ardından gelen hareket ve oturum yazmaları) serbest bırakılır.

| Ölçüm | İlk koşu (eski tasarım) | Son koşu |
|---|---|---|
| Migration | **durdu:** `Aktif ERP personeli gerekli` | uygulandı |
| Stok | (migration durduğu için ölçülemedi; tasarım gereği +10 yazılacaktı) | **80 → 80** |
| Sayım hareketi | — | **0** |
| Oturum | — | `onay_bekliyor`, kısmi bayrak `false` |
| Eski sekmenin yazma denemeleri | — | 3, hepsi reddedildi |
| G13 aynı sayım yeni ekranla | 90 (eski kural) | **70** |

## 2. Yazma yolunda ayrım (yalnız okuma engeline güvenilmiyor)

Eski sekme stok farkını, normal giriş/çıkışın da yolu olan `stok_ekle` ile yazıyor; çağrı içeriğinden
sayım olduğu anlaşılamaz. Ayrım bu yüzden **istemci sürümü** üzerinden yapıldı:

1. **İstemci nesli.** A1 ile 4 parametreli `stok_ekle` hiçbir şey yazmaz, `ESKI_ISTEMCI` döner.
   Yeni ekranlar 5. parametre `p_istemci_nesli` ile çağırır (`ortak.js` → `stokEkleCagir`). Böylece
   migration anında açık kalan **her** eski stok ekranı, sayım dahil, stok yazamaz.
   A1 öncesi veritabanında 5 parametreli fonksiyon yoktur (PGRST202); yalnız o durumda eski imzaya
   düşülür. Bu sayede ekranlar migration'dan önce yayınlanabilir.
2. **Sayım hareketi yalnız sunucudan.** Eski sekme stok yazamasa da hareketi tabloya doğrudan
   ekliyordu. Artık `sayim…` açıklamalı hareket yalnız sunucu sayım fonksiyonlarından yazılabiliyor.
3. Önceki katmanlar da duruyor: detay okuma RPC'ye taşındı, onay durumu yalnız sunucudan değişir.

| Kanıt | Sonuç |
|---|---|
| E16 / E16b | 4 parametre ve geçersiz nesil: `ESKI_ISTEMCI`, stok değişmedi; nesil 1 yazıyor |
| E17 | dışarıdan `sayim` hareketi reddedildi; diğer doğrudan hareketler etkilenmedi |
| S5 | yeni ekran A1 veritabanında tek istekte yazıyor (düşüş yolu kullanılmadı) |
| `stok-ekran` 21/21 | aynı ekran A1 öncesi şemada düşüş yoluyla çalışıyor |
| Negatif K10 / K11 | ayrım kaldırılınca eski istemci yazıyor; tetikleyici kaldırılınca `sayim` hareketi yazılıyor — testler yakalıyor |
| Geri alma | 5 parametreli fonksiyon ve tetikleyici kalkar, 4 parametreli eski yazan gövde döner (sıra testi 17/17) |

**Yayın etkisi (yeni):** Migration anında açık olan eski stok-takip, günlük tüketim ve mal kabul
sekmeleri, sayfa yenilenene kadar stok yazamaz. Bir sekme migration anında çok satırlı bir işlemin
ortasındaysa işlem kısmi kalabilir. Bu yüzden plana şu eklendi: yayın sessiz bir saatte ve bu ekranlar
kapalıyken yapılır. `stok_transfer` değişmedi, çünkü eski sayım yolu onu kullanmıyor.

## 3. Yeni bulgu: migration dolu tabloda duruyordu

`bar_siparisleri` tablosunda phase0 denetim tetikleyicisi var. Bu tetikleyici kimliksiz (postgres) veri
değişikliğini `Aktif ERP personeli gerekli` ile reddediyor. A1'in geçiş `UPDATE`'i bu yüzden, tabloda
sipariş varken **duruyordu** (tek işlem olduğu için hiçbir şey yazılmadan). Önceki testlerde migration
hep boş sipariş tablosuna uygulanmıştı; üretimde tablo dolu olduğu için yayın durmuş olurdu.

Düzeltme: tetikleyici atlanmıyor (replica rolü kullanılmıyor). Geçiş güncellemesi işlem-yerel
`service_role` kimliğiyle yapılıyor ve denetim kaydına `service_role` olarak düşüyor; hemen ardından
kimlik geri alınıyor. G12'de migration dolu tabloda uygulandı.

## 4. Plan

G9 düzenlendi. Kesin kapsamı ve sırası onaylanmış **tek** bir yayın talimatı yeterli; her adım için ayrı
onay istenmiyor. Yazan adımlar yine tek tek çalışır, her adımdan sonra ölçüm ve duman testi yapılır.
Onaylanan kapsam ve sıradan beklenmeyen bir farkta durulur ve size dönülür. Yedek, ilk üretim
değişikliğinden önce alınır. Şu an yayın talimatı yok.

## 5. Açık kalanlar

- Sayım oluşturma / listeleme gerçek yetki düzeniyle doğrulanmadı. Canlı salt okuma sorgusu sizde:
  `.\docs\kurulum\sql-uygula.ps1 -Dosya docs\kurulum\2026-09-19-sayim-rls-salt-okuma.sql -SaltOkuma`
- Canlı Edge kodu ve müşteri şeması karşılaştırması: Supabase Dashboard girişi gerekiyor.
- Koşullu tarayıcı testleri (yerel `confirm/prompt` değiştirilen ve DOM'dan tetiklenen adımlar)
  tamamlanmış sayılmıyor.
- Yayın sırası kararı.

## Test sonuçları (bu turun son hali)

| Takım | Sonuç |
|---|---|
| gecis-provasi (G12, G13 yeni) | 16/16 |
| bar-a1-guvenlik (E16, E17 yeni) | 70/70 |
| bar-a1-negatif (K10, K11 yeni) | 12/12 |
| bar-a1-ekran (S5 yeni) | 37/37 |
| stok-guncelleme-tarihi-bar-sira | 17/17 |
| bar-edge-e2e | 22/22 |
| stok-ekran · stok-veri-eksiksizlik · stok-guncelleme-tarihi | 21/21 · 33/33 · 14/14 |
| taban · önce ölçümü | 9/9 · 9/9 |
| migration denetleyicisi | 24 dosya 0 hata; birim 15/15; phase0 6/6 |
