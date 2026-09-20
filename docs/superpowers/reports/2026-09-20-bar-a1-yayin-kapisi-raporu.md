# Bar A1 — Yayın Kapısı Düzeltmesi, Eşleştirme ve Tarayıcı Testi Yolu

**Tarih:** 2026-09-20 (ikinci tur) · **Dal:** `bar-a1` (yerel) · **Üretim:** yazma yok. Push,
deploy, canlı migration ve Aşama 2 **yok**; yayın talimatı yok.

| # | Madde | Durum |
|---|---|---|
| 1 | Yayın kapısı: sunucu tarafı yazma duraklatması | **UYGULANDI ve ÖLÇÜLDÜ** |
| 2 | "Başlamış işlemlerin tamamlandığı" doğrulaması | **MÜMKÜN DEĞİL — kalan risk açıkça yazıldı** |
| 3 | "Ekranlar sorguyla kapalı doğrulandı" ifadesi | **KALDIRILDI** (hareketsizlik = yardımcı kanıt) |
| 4 | Yayın sonrası eşleştirme: sayım yerine satır bazlı stok etkisi | **DÜZELTİLDİ ve ÖLÇÜLDÜ** |
| 5 | Koşullu tarayıcı testleri | **YOL AÇILDI:** manuel test betiği hazır; sizden bir tur bekliyor |
| 6a | Sayım oluşturma/listeleme — canlı doğrulama | **ÖLÇÜLDÜ 2026-09-20:** üretimde çalışmıyor (RLS), tablolar boş |
| 6b | Canlı Edge kodu / müşteri şeması | **AÇIK** (Dashboard girişi gerekiyor) |
| 7 | Yayın sırası | **KARAR GEREKİYOR** |

---

## 1. Sunucu tarafı yazma duraklatması (asıl kontrol)

Yeni dosyalar: `docs/kurulum/2026-09-20-yayin-yazma-duraklat.sql` ve `…-surdur.sql`.
Duraklatma, `authenticated` rolünden stok yazma haklarını alır: `stok_ekle` (iki imza),
`stok_transfer`, `stok_hareketleri` INSERT ve doğrudan `stok` INSERT/UPDATE. **Okuma açık kalır.**
Şema değişmez, yeni nesne eklenmez; yalnız yetki alınır ve geri verilir. Her ikisi de denetim izine
kayıt düşer (`A1-YAYIN-DURAKLATMA`, `A1-YAYIN-SURDURME`).

Ölçüm — `scripts/bar-a1-yayin-kilidi.test.mjs` (7/7):

| Kanıt | Sonuç |
|---|---|
| D1 taban | duraklatmadan önce istemci yazabiliyor |
| D2 duraklatma | `stok_ekle`, `stok_transfer`, hareket INSERT ve doğrudan `stok` yazma **reddedildi**; okuma açık; stok değişmedi |
| D3 kapsam sınırı | bar siparişi ve teslimi **çalışmaya devam etti** (sunucu fonksiyonu yazıyor) |
| D4 kalan risk | duraklatma, süren çok satırlı işlemin **sonraki satırını kesiyor** |
| D5 | migration duraklatma altında uygulandı |
| D6 sürdürme | yeni istemci yazabiliyor; eski imza (4 parametre) A1 nedeniyle yine yazamıyor |
| D7 | duraklatma/sürdürme denetim izinde |

Sürdürme dosyası **migration başarısız olsa da** çalıştırılır; yoksa stok yazmaları kapalı kalır.
Bu, planın geri dönüş adımına yazıldı.

## 2. Kalan risk — açıkça

Sunucu, bir istemcinin **çok satırlı işleminin ortasında olup olmadığını bilemez**: her satır ayrı
HTTP isteğidir, bir işlem kimliği yoktur. Bu yüzden:

- Duraklatma, **başlamış bir işlemi tamamlamaz**; tam tersine sonraki satırında keser.
- "Başlamış işlemlerin tamamlandığı" sunucu tarafında **doğrulanamaz**.
- Hareketsizlik sorgusu (`2026-09-20-yayin-oncesi-islem-kontrol.sql`) yalnızca **yardımcı
  kanıttır**: "şu an yazan yok" der, "açık sekme yok" demez. Raporda ve planda artık
  **"ekranlar sorguyla kapalı doğrulandı" denmiyor.**
- Risk azaltma: duraklatmadan önce hareketsizlik beklenir, personele duyurulur, duraklatmadan
  sonra "hata alan işlem oldu mu" diye sorulur ve alınan hatalar 4. maddedeki eşleştirmeyle
  incelenir. Risk **sıfırlanmaz.**

## 3. Yayın sonrası eşleştirme (sayım değil)

Kontrol sorgusunun 4. bölümü yeniden yazıldı. Miktar (stok) ve hareket **ayrı** isteklerde
yazıldığı için "hareket yok" ≠ "stok yazılmadı". Artık her kalem için şunlar birlikte gösteriliyor:
eşleşen hareket sayısı, ürünün o oteldeki stok satırlarının **son değişim zamanı**, mal kabulün
denetim izinden okunan **onay zamanı** ve bir değerlendirme:

| Durum | Değerlendirme |
|---|---|
| Hareket var | "kalem işlenmiş say" |
| Hareket yok **ama** stok onaydan sonra değişmiş | **"ŞÜPHELİ — yeniden yazma!"** |
| Stok satırı yok | "işlenmemiş görünüyor" |
| Hareket yok ve stok onaydan beri değişmemiş | "işlenmemiş görünüyor" |

Ek olarak 4b bölümü, o belgeye yazılmış tüm hareketleri listeler (mükerrer var mı). Ölçüm:
`scripts/bar-a1-yayin-kontrol-sorgu.test.mjs` (4/4) — tehlikeli durum (stok yazılmış, hareket yok)
"eksik" değil **şüpheli** olarak işaretleniyor. Planda: şüpheli satırlar **yeniden yazılmaz**, önce
iz ve gerekirse fiziksel sayımla doğrulanır; yalnız işlenmediği kanıtlanan satır tamamlanır.

## 4. Koşullu tarayıcı testleri — ölçüm ve yol

Ekran değiştirmedim. İki otomasyon yolu denendi:

| Yol | Sonuç |
|---|---|
| Uygulama içi tarayıcı bölmesi | yerel `confirm/prompt` pencerelerini **kendiliğinden kapatıyor**; kabul edilemiyor |
| Chrome eklentisi (gerçek Chrome) | pencere **gerçekten çıkıyor ve sayfayı bloke ediyor**; otomasyon o pencereye tıklayamıyor (pencere tarayıcının parçası, sayfanın değil — tıklama ve JS çağrıları zaman aşımına uğradı) |

Kalan yol: **sizinle manuel bir tur.** Adım adım betik hazır:
`docs/kurulum/2026-09-20-manuel-tarayici-testi.md` — ortamı tek komutla siz başlatıyorsunuz
(`node scripts/bar-edge-e2e/tarayici-ortami.mjs`), 11 adım ve beklenen sonuçlar yazılı. Sonuçları
iletirseniz raporda "koşullu geçti" yerine "manuel doğrulandı" yazarım. Bu adımların **sunucu
tarafı sonuçları zaten otomatik testlerde doğrulandı**; manuel turda sınanan şey yalnız yerel
pencerelerin kendisi (metin, "İptal" hiçbir şey yazmıyor mu, "Tamam" akışı tamamlıyor mu).

## 5. Bu turda koşan testler

Tamamlanmış takımlar gereksiz tekrarlanmadı; yalnız bu turda eklenen/etkilenenler koşuldu:

| Takım | Sonuç |
|---|---|
| `bar-a1-yayin-kilidi` (yeni) | 7/7 |
| `bar-a1-yayin-kontrol-sorgu` (yeni) | 4/4 |
| migration denetleyicisi (yeni SQL dosyaları dahil) | 27 dosya, 0 hata |

Önceki turun sonuçları değişmedi: veritabanı 72/72, geçiş provası 16/16, geçiş migration 6/6,
çağrı sınırı 9/9, ekranlar 37/37, sıra/geri alma 17/17, Edge 22/22.

## 6. Sayım tabloları — canlı ölçüm (kapandı)

Salt okuma sorgusunu çalıştırdınız (2026-09-20). Üretim, izole ölçümle birebir aynı:

| Ölçüm | Üretim |
|---|---|
| RLS | iki tabloda da açık |
| Politikalar | `sayim_oturumlari`: yalnız RESTRICTIVE; `sayim_detaylari`: **hiç politika yok** |
| `authenticated` tablo hakları | TAM (SELECT/INSERT/UPDATE/DELETE) — yani engel **yetki değil, RLS** |
| Satır sayısı | `sayim_oturumlari` **0**, `sayim_detaylari` **0**; son 30 günde kayıt yok |
| Aktif cost_control kullanıcısının gördüğü | **0 satır** |

Sonuç: izin veren (permissive) politika olmadığı için sayım **oluşturulamıyor ve listelenemiyor**;
özellik üretimde bugüne kadar kullanılamamış ve **kaybolmuş veri yok**. Bu A1 dışı, önceden
kaydedilmiş bir kusurdur; A1 bunu ne düzeltir ne kötüleştirir. A1'in sayım değişiklikleri
(onay RPC'si, bekleyen düzeltme, eski sekme durdurma) canlıda **boş tabloya** uygulanır.

**Ayrı iş için not:** bu kusur düzeltilirken `sayim_detaylari`'na doğrudan `SELECT` grant'i geri
verilmemelidir. A1 o grant'i bilerek kaldırdı; yeni ekran detayları `stok_sayim_detaylari()`
RPC'siyle okuyor (eski sekme durdurmasının bir katmanı). Düzeltme yalnız **permissive politika**
eklemelidir.

## 7. Sizden gerekenler

1. Manuel tarayıcı turu (yukarıdaki betik) — sonuçları iletin.
2. Canlı Edge kodu / müşteri şeması için Supabase Dashboard girişi.
3. Yayın sırası kararı.
