# Stok güncelleme tarihi — yayın planı (2026-09-18)

> **URETIME UYGULANMADI.** Bu belge hazırlıktır. Uygulama yalnız kullanıcı
> açıkça `CANLIYA UYGULA` dediğinde başlar (runbook §0, §2.1).

## Kapsam

| Giriyor | Girmiyor |
|---|---|
| `fix/migration-denetleyici-crlf` — denetleyicinin CRLF kör noktası (yayın kapısının ön şartı) | **Bar A1** (`stok_cikis_korumasi`, rezervasyon) — ayrı dal, ayrı yayın |
| `docs/kurulum/2026-09-17-stok-guncelleme-tarihi.sql` — `stok_ekle`/`stok_transfer` UPDATE yollarına `guncelleme_tarihi = now()` | Başka hiçbir fonksiyon, tablo, politika, yetki |
| `stok-takip.html` — "Son güncelleme" sunucudan okunur; okunamazsa `—` | Diğer ekranlar |
| Test tabanı, testler, yayın sorguları, prova ve karşılaştırıcı betikleri | |

`main`'e hızlı ileri sarma ile gider: önce denetleyici commit'i, üstünde stok
paketi. Bar A1 izi her anlık görüntüde (`bar_a1_izi`) ayrıca ölçülür.

## Yayın kapısı — ölçülmüş durum

| Kapı | Sonuç |
|---|---|
| Denetleyici testleri (`node --test scripts/migration-guvenlik-kontrol.test.mjs`) | 15/15 — her sabotaj LF **ve** CRLF'de aynı bulguyu veriyor |
| Stok paketi, düzeltilmiş denetleyiciyle, LF + CRLF | 8 dosya, 0 HATA, 0 UYARI |
| Argümansız denetim (tüm yeni migration'lar) | 19 dosya, 0 HATA |
| İzole paketler | migration 14/14 · sıra 11/11 · ekran 21/21 · veri 33/33 |
| Üretim şema dökümü üzerinde prova (`scripts/stok-tarih-yayin-prova.mjs`) | 12/12 |
| Karşılaştırıcı testleri | 12/12 |

## Sıra

Her anlık görüntü `Tee-Object` ile dosyaya da yazılır; karşılaştırıcı bu
dosyaları okur. Parolalar her adımda kullanıcıdan istenir.

```
$Y = 'C:\Users\USER\ERP-Yedek'
.\docs\kurulum\sql-uygula.ps1 -Dosya docs\kurulum\2026-09-18-stok-tarih-yayin-anlik.sql -SaltOkuma | Tee-Object -FilePath "$Y\2026-09-18-stok-tarih-T0.txt"
```

| # | Adım | Kim | Geçme şartı |
|---|---|---|---|
| 0 | Duman hazırlık sorgusu (`2026-09-18-stok-tarih-duman-hazirlik.sql`), ürün ve belge seçimi, planın doldurulması | kullanıcı çalıştırır, birlikte seçilir | Bölüm 2 (güvenlik ağı) boş ya da seçilen üründen bağımsız |
| 1 | **Yazma penceresini aç**: seçilen ürün için iki depoda stok işlemi yapılmayacağı ekibe duyurulur | kullanıcı | — |
| 2 | Uzak dal: `git fetch`, `origin/main` = `9d31e17` mi | ben | değişmişse DUR, yeniden rebase + test |
| 3 | **T0** | kullanıcı | `olcumle_ayni=t`, `tarih_duzeltmesi=f`, `bar_a1_izi=f`, ACL + sütun yetkisi beklenen |
| 4 | Yedek: `yedek-ve-sayac-al.ps1 -Etiket 2026-09-18-pre-stok-tarih` | kullanıcı | betik başarılı, sayaç dosyası var |
| 5 | Migration: `sql-uygula.ps1 -Dosya docs\kurulum\2026-09-17-stok-guncelleme-tarihi.sql` | kullanıcı | `BASARILI`; migration kendi ön koşullarını uygulama anında yeniden doğrular |
| 6 | **T1** + karşılaştırıcı (T0→T1) | kullanıcı + ben | migration aralığı `GECTI`/`BILGI`; `INCELE` varsa DUR |
| 7 | Arayüz: `origin/main` tekrar kontrol, hızlı ileri sarma push | ben | canlı `stok-takip.html` SHA-256 = yayın commit'indeki dosya |
| 8 | Giriş (mal kabul onayı) → **T2a** | kullanıcı | — |
| 9 | Transfer `810_100 → <IKINCI_DEPO>` 1 birim → **T2b** | kullanıcı | — |
| 10 | Çıkış `<IKINCI_DEPO>` 1 birim, neden `Diğer`, not `DUMAN TESTI 2026-09-18 — SILINECEK`, QR **okutulmaz** → **T2c** | kullanıcı | — |
| 11 | Karşılaştırıcı (tümü) | ben | `GENEL KARAR: GECTI/BILGI` |
| 12 | Sayfa yenileme: kartlardaki "Son güncelleme" karşılaştırıcının yazdığı `KART` satırlarıyla aynı | kullanıcı | birebir aynı metin |
| 13 | **Yazma penceresini kapat**, runbook §4'e kayıt | ben | — |

Karşılaştırıcı:
```
node scripts/stok-tarih-yayin-karsilastir.mjs --plan docs/kurulum/2026-09-18-stok-tarih-duman-plani.json T0.txt T1.txt T2a.txt T2b.txt T2c.txt
```

Neden üç ayrı duman görüntüsü: aynı satıra sonradan yazan işlem öncekinin
tarihini ezer. Her işlemin tarihini **kendi** anında ölçmek için ara
görüntü gerekir (giriş → 810_100; transfer → iki taraf; çıkış → ikinci depo).

## Yazma izolasyonu (T0–T2)

Üretimde teknik bir kilit **konmaz**: kilit de bir üretim yazmasıdır ve bu
yayının kapsamı dışındadır. Yerine üç katman:

1. **Seçim:** ürün, hazırlık sorgusunun 6. bölümünden gelir — iki satırda da
   son 14 gün hareket yok, bekleyen ya da stoğa işlenmemiş hiçbir belgede
   geçmiyor, iki satır da zaten var (transfer yeni satır yaratmaz;
   `stok.urun_kodu → urunler` yabancı anahtarı yüzünden yeni ürün kodu da
   uydurulamaz).
2. **Duyuru:** pencere boyunca bu ürün için iki depoda işlem yapılmaz.
   Hazırlık sorgusunun 7. bölümü en sessiz saati gösterir. Bölüm 2'de
   onaylanmış ama stoğa işlenmemiş belge varsa, `stok-takip.html` açıldığı
   anda bunları kendiliğinden işler — pencere öncesinde işlenmeleri ya da
   seçilen üründen bağımsız oldukları doğrulanır.
3. **Ayrıştırma:** karşılaştırıcı her değişikliği o aralıktaki stok
   hareketiyle eşleştirir. Başka bir işlemin değişikliği **migration hatası
   sayılmaz**: migration aralığında `BILGI` (hareketle açıklanan) ya da
   `INCELE` (hareketsiz) olur; duman satırına yabancı yazma girdiyse
   `DUMAN_GECERSIZ` olur ve o adım tekrarlanır.

Karar kodları: `GECTI` · `BILGI` · `DUMAN_GECERSIZ` (tekrarla) · `INCELE`
(insan kararı) · `BASARISIZ` (duman satırı tarihi sunucuda güncellenmedi ya
da dokunulmayan satırın tarihi değişti).

## Giriş belgesi (Karar 2)

**Öncelik:** Hazırlık sorgusunun 1. bölümünde, zaten operasyonel olarak
onaylanacak bir belge varsa kullanıcı onu seçer. O durumda plandaki giriş
satırı o belgenin ürün/miktar/numarasıyla doldurulur; transfer ve çıkış
aynı ürünle yapılır. Çıkış, test belgesiyle telafi edilmediği için
**gerçek stoktan 1 birim düşer**. Bu durumda çıkış yerine ikinci depodan
geri transfer (net sıfır) seçilebilir; plan buna göre değiştirilir.

**Yoksa — etiketli test belgesi (önceden belirlenmiş):**

| Alan | Değer |
|---|---|
| Otel / depo | 810 / `810_100` (merkez) |
| Firma (serbest metin) | `DUMAN TESTI — SILINECEK` |
| İrsaliye | `DUMAN-2026-09-18` |
| Fatura no | **boş** (fiyat kontrol listesine girmesin) |
| Sipariş bağlantısı | **yok** (sipariş kalemleri ve durumu değişmesin) |
| Notlar | `DUMAN TESTI 2026-09-18 — stok guncelleme_tarihi yayini — SILINECEK` |
| Kalem | `<URUN>` × 1 `<BIRIM>`; koli yok, SKT yok, QR yok |

### Test belgesinin kayıt etkileri (koddan çıkarıldı)

| Aşama | Yazılan | Etki |
|---|---|---|
| Oluşturma (`mal_kabul_kaydet` RPC) | `mal_kabuller` +1, `mal_kabul_urunleri` +1 | Koli ve SKT girilmediği için `koli_etiketleri`/`skt_kayitlari` yazılmaz |
| Onay (`kaliteOnayla`) | `mal_kabuller.durum = onaylandi`, `stok_islendi = true` | — |
| | `stok` `<URUN>@810_100` **+1**, tarih | çıkışla telafi edilir |
| | `stok_hareketleri` +1 `giris` (belge = MK no) | kalıcı |
| | `erp_islem_audit` +1 (`approve mal_kabul`) | kalıcı, silinmez |
| Transfer | `stok` iki satır (−1 / +1), `stok_hareketleri` +1 `transfer` | kalıcı hareket |
| Çıkış | `stok` `<URUN>@<IKINCI_DEPO>` −1, `stok_hareketleri` +1 `cikis` | kalıcı hareket |
| **Net stok** | `810_100`: 0 · `<IKINCI_DEPO>`: 0 | |

Hazırlık sorgusunun 3. ve 4. bölümleri, bu tabloların üretimde koddan
görünmeyen tetikleyicileri ya da ek yazmaları olup olmadığını ölçer; varsa
tablo güncellenir.

### Dikkat — belge görünürlüğü ve numara

- **MK numarası:** `yeniMkNoUret()` numarayı *bu yılın belge sayısı + 1*
  olarak üretir. Test belgesi sayacı kalıcı olarak bir artırır. **Belge
  sonradan silinmemeli:** arada yeni belgeler açılırsa silme, bir sonraki
  belgeye mevcut bir numarayı verdirir (hazırlık 5. bölümü `mk_no`'nun tekil
  kısıtı olup olmadığını ölçer).
- **LN aktarımı (`mal-kabul-lnexport.html`):** aynı günün onaylı belgelerini
  listeler — test belgesi **aktarım listesinde görünür**. LN'e
  aktarılmamalı; aktarım yapan kişi bilgilendirilir.
- **Tedarikçi karnesi (`satin-alma-skorkart.html`):** iptal dışı tüm belgeleri
  sayar; `DUMAN TESTI — SILINECEK` sahte bir tedarikçi olarak görünür.
- **Mal kabul izleme / muhasebe faturaları:** belge listelerde görünür.
- Fiyat kontrol: fatura no boş olduğu için **görünmez**.

Belgenin sonradan gizlenmesi (ör. `iptal`) arayüzden yapılamaz, çünkü onaylı
bir belgeyi iptal etmek düzeltme akışını tetikler ve stoğu yeniden oynatır.
Doğrudan veritabanı güncellemesi ayrı bir üretim yazmasıdır ve ayrı onay
gerektirir. Karar kullanıcıya aittir.

## Geri alma

- **Migration:** `create or replace` ile 2026-09-17 teşhisindeki gövdeler
  (`scripts/stok-rpc-govde.mjs`, md5 `24d255cc…` / `4c6fe121…`) yeniden
  yazılır. Satır verisi değişmediği için veri geri alması yoktur.
- **Arayüz:** yayın commit'i `git revert` + push. Eski ekran, düzeltilmiş
  fonksiyonlarla da çalışır (yalnız yerel saati gösterir).
- **Duman kayıtları:** silinmez (denetim izi + MK numarası). Etiketleriyle
  ayırt edilir.
