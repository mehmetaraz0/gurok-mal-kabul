# Bar A1 — KESİN YAYIN TALİMATI (tek onayla uygulanır)

**Durum:** onay bekliyor. Bu belge onaylanana kadar **push, deploy, canlı migration yok.**
Onay cümlesi tek satırdır ve kapsamı bu belgedir:

> **CANLIYA UYGULA — Bar A1, bu belgedeki kapsam ve sıra.**

Onaylanan kapsam ve sıradan **herhangi bir beklenmeyen farkta durulur** ve size dönülür; talimat
o noktadan sonrasını kapsamaz.

---

## 1. Kesin kapsam

| Öğe | Değer |
|---|---|
| Dal | `bar-a1` |
| **Uç commit** | **`5ef7e7d`** (yayın anında `git rev-parse bar-a1` ile teyit edilir) |
| Taban | `origin/main` = **`9c06661`** — 2026-09-20'de `git fetch` ile doğrulandı: **hâlâ ata** |
| Commit sayısı | 42 |
| Ekran/JS dosyaları (10) | `bar-siparis-kuyrugu.html`, `bar-garson.html`, `bar-menu.html`, `stok-takip.html`, `pms-folio.html`, `gunluk-tuketim.html`, `mal-kabul-liste.html`, `ortak.js`, `stok-veri.js`, `hata-kodlari.js` |
| Migration | `docs/kurulum/2026-09-18-bar-a1-guvenlik.sql` (sayım erişimi **15c** dahil) |
| Geri alma | `docs/kurulum/2026-09-18-bar-a1-guvenlik-geri-al.sql` |
| Edge | `rapid-handler` (müşteri projesi) — **yalnız bu fonksiyon**; `hyper-api` ve `smooth-service` A1'de değişmedi |
| Edge geri dönüş kaynağı | `docs/kurulum/musteri-projesi/masa-yonetim/index.canli-bolge1.ts` (canlıdan alındı) |

**Ön koşullar — hepsi karşılandı:**

- Canlı `rapid-handler` kaynağı alındı ve repo tabanıyla diff'lendi: iş mantığında fark **yok**
  (15 satır kozmetik). Deploy, repoda bulunmayan bir değişikliği silmeyecek.
- Canlı HTTP sözleşmesi birleşik sürümde **tamamen** korundu (405/400/401 + diğer tüm ret ve hata
  yolları 200 + `ok:false`). Sonda karşılaştırması: 9 yoldan tek fark kasıtlı `ping` etiketi.
- Geri dönüş kaynağı repoda.

## 2. Sıra ve gerekçesi (ölçüme dayalı)

1. **Ekranlar önce** — yeni ekranlar A1 **öncesi** veritabanıyla çalışıyor (`stok_ekle` yalnız
   `PGRST202`de eski imzaya düşer; 9/9). Tersi doğru değil: eski stok-takip + A1 veritabanı sayımı
   yanlış yazardı.
2. **Migration sonra.**
3. **Edge en son** — yeni `rapid-handler` migration'dan **önce çalışmaz** (`bar_masa_yetki_kapsami`
   yok; E2E'de ölçüldü).

## 3. Adımlar

| # | Adım | Komut / dosya | Durma ölçütü |
|---|---|---|---|
| 0 | Salt okuma ön kontroller | `git fetch` + ata kontrolü; A1 ön koşul md5'leri (migration kendi içinde); işlem kapısı sorgusu (taban ölçüsü) | ata değilse **DUR** |
| 1 | **YEDEK** | Üretim şema + veri yedeği. **İlk üretim değişikliğinden önce** — ekran push'undan da önce | dosya yok / boyut 0 ise **DUR** |
| 2 | Yazma duraklatma | `2026-09-20-yayin-yazma-duraklat.sql` | denetimde `A1-YAYIN-DURAKLATMA` yoksa **DUR** |
| 3 | İşlem kapısı | `2026-09-20-yayin-oncesi-islem-kontrol.sql` | yarım kalan şüphesi varsa **DUR** |
| 4 | Ekranlar | `main` → `5ef7e7d` (fast-forward) | sayfa açılış duman testi başarısızsa **DUR** |
| 5 | Migration | `sql-uygula.ps1 -Dosya docs\kurulum\2026-09-18-bar-a1-guvenlik.sql` | dosyanın kendi son koşulu hata verirse **DUR** (tek işlem, hiçbir şey kalmaz) |
| 6 | Edge deploy | `rapid-handler` ← `docs/kurulum/musteri-projesi/masa-yonetim/index.ts` | `ping` `v:"a1-kapsam"` dönmezse **DUR** |
| 7 | **YENİDEN AÇMA KAPISI** | `2026-09-20-kesinti-uzlastirma.sql` (`set uzl.kesinti = '<duraklatma anı>'`) | **"YENİDEN AÇMA: HAYIR" ise 8. adım YAPILMAZ** |
| 8 | Yazma sürdürme | `2026-09-20-yayin-yazma-surdur.sql` | — |
| 9 | Duman testleri + eşleştirme | aşağıdaki liste; sonra işlem kapısı sorgusu tekrar | ŞÜPHELİ satır **yeniden yazılmaz**, incelenir |

**7. adım istisnası:** prosedür çalıştırılamıyorsa karar alınamaz; bu da "HAYIR" sayılır.
**8. adım kuralı:** migration başarısız olsa bile sürdürme çalıştırılır (7. adım geçtiyse) —
yoksa stok yazmaları kapalı kalır.

## 4. Yeniden açma (duman) kontrolleri — 9. adım

1. Stok-takip: bir üründe **+1 / −1** hareket → yazıyor mu (duraklatma gerçekten kalktı mı).
2. Mal kabul: açık bir belgede tek kalem onayı → **stok ve hareket birlikte** yazıldı mı.
3. Bar: QR menüden ücretli sipariş → kuyrukta "oda doğrulaması bekliyor" çıkıyor mu; doğrula →
   teslim → folyoya borç yazıldı mı.
4. **Sayım (15c ile artık çalışıyor):** depo/cost control kullanıcısı sayım açıp kaydedebiliyor
   ve listeleyebiliyor mu; **onay/ret yalnız cost control'de** görünüyor mu.
5. Bar masa yönetimi: masa listesi geliyor mu, **başka otelin masası görünmüyor** mu.
6. Ön büro: `pms-folio` istisna bölümü açılıyor mu (açık istisna yoksa boş liste beklenir).
7. Denetim izi: `A1-YAYIN-DURAKLATMA`, `A1-GECIS-ISARETI`, `A1-YAYIN-SURDURME` satırları var mı.

## 5. Geri dönüş

| Katman | Yol |
|---|---|
| Edge | `index.canli-bolge1.ts` yeniden deploy (canlıdan alınan birebir kopya) |
| Migration | `2026-09-18-bar-a1-guvenlik-geri-al.sql` — ön koşul: açık istisna ve bekleyen sayım yok. **Yetkileri birebir geri getirmez:** korunan güvenlik daraltmaları dosyanın başında tablo tablo listeli. Geri alma sonrası **eski ekran akışı gerçek personel kimliğiyle ölçüldü: çalışıyor (11/11)** |
| Ekranlar | `main` → `9c06661` |
| Yazma hakları | `…-yayin-yazma-surdur.sql` her hâlükârda |

## 6. Bu yayının kapsamı DIŞINDA kalanlar

- `authenticated` rolünde **TRUNCATE** hakkı: A1 yalnız 5 tabloda kaldırıyor, **75 tabloda
  duruyor**. Ayrı ve yüksek öncelikli iş (`task_7fcfaa3c`), ayrı rapor. Üretimde TRUNCATE
  denenmeyecek; canlı doğrulama salt okuma dosyasıyla.
- Sayım "İptal"/boş bırakma dallarının gerçek tıklamayla sınanması (otomatik testlerde var).

## 7. Dayanak ölçümler (hepsi izole, üretime bağlanmaz)

veritabanı 72/72 · negatif 12/12 · ekran 38/38 · sıra+geri alma 17/17 · geçiş migration 6/6 ·
çağrı sınırı 9/9 · yazma duraklatma 7/7 · kontrol sorgusu 4/4 · geçiş provası 16/16 ·
**Edge E2E 22/22** · sayım 15c 22/22 · kesinti uzlaştırma 20/20 · TRUNCATE ölçümü 13/13 ·
geri alma sonrası eski ekran 11/11 · migration denetleyicisi 0 hata.
