# İç Talepler — Excel Al/Ver (Round-Trip) — Tasarım

## Problem

Kullanıcı LN Infor'da alışkın olduğu bir iş akışını (bir listeyi Excel'e çıkar,
Excel'de düzenle/karar ver, düzenlenmiş dosyayı sisteme geri yükle — sistem
farkları uygular) Gürok ERP'ye de kazandırmak istiyor. `/haftalik-siparis-takip`
skill'i bu deseni tek seferlik bir PDF→Excel dönüşümü için zaten kanıtlamış
durumda (3-4 saatlik elle kopyala-yapıştır işini 1-2 dakikaya indirmiş).

İlk somut hedef: **`satin-alma.html` → İç Talepler** sekmesi. Departmanlardan
gelen satın alma taleplerini toplu şekilde Excel'e çıkarıp, Excel'de karar
(onayla/reddet) ve miktar düzeltmesi yapıp, geri yükleyince sistemin bu
kararları/düzeltmeleri uygulaması.

## Hedef

- İç Talepler listesini (o an ekrandaki filtreye göre) kalem bazında Excel'e
  aktarmak.
- Düzenlenmiş Excel'i geri yükleyince: Karar kolonu doluysa talebi onayla/
  reddet, Miktar değişmişse ilgili kalemin miktarını güncelle.
- Var olan `xlsx-js-style` kütüphanesini (bu dosyada zaten `parseLNExcel()`
  içinde kullanılıyor) tekrar kullanmak — yeni bir bağımlılık eklenmiyor.
- Yazmadan hemen önce her talebin canlı durumunu tekrar kontrol etmek (bu
  oturumda birkaç kez uygulanan "bayat veri" koruma deseniyle tutarlı) —
  eşzamanlı bir değişiklik varsa o satırı atlayıp raporlamak.

## Kapsam dışı

- Diğer modüllerdeki (Stok Takip, Depo Siparişleri) Excel al/ver — bu ayrı bir
  sonraki iş, bu spec'in kapsamında değil.
- LN Siparişleri (`ln_siparisler`) ve Fiyat Kontrolü listeleri için Excel al/ver
  — kapsam dışı.
- Talep oluşturma (yeni talep açma) Excel üzerinden değil, sadece var olan
  taleplerin karar/miktar güncellemesi.

## Veri Modeli (mevcut, değişmiyor)

- `satin_alma_talepleri`: id, departman, aciliyet, not_alani, durum
  (bekleyen/onaylandi/siparis/reddedildi — zaten kullanılan, enum sorunu yok),
  talep_eden, otel_id, olusturma_tarihi.
- `satin_alma_talep_kalemleri`: id, talep_id, urun_adi, urun_kodu, miktar, birim.

**Küçük bir ön-hazırlık gerekiyor:** `loadDB()` içinde `DB.talepler[id].satirlar`
şu an kalemin `id`'sini taşımıyor (`{ad,kod,miktar,birim}` — sadece bunlar).
Excel'den geri gelen bir satırı doğru kaleme eşlemek için kalem `id`'si lazım.
Bu yüzden mapping'e `id:k.id` eklenecek (satin-alma.html:480 civarı,
`satirlar:(r.satin_alma_talep_kalemleri||[]).map(k=>({id:k.id,ad:k.urun_adi,...}))`).
Bu değişiklik geriye dönük uyumlu — mevcut hiçbir kodu bozmaz, sadece yeni bir
alan ekler.

## Dışa Aktarma — "📤 Excel'e Aktar"

İç Talepler sekmesinde, mevcut filtre butonlarının yanına yeni bir buton.
Tıklanınca:

1. `talepFilter`'a göre filtrelenmiş `DB.talepler` listesini al (renderTalepler
   ile aynı filtre mantığı — `filterTalep`'te zaten var).
2. Her talebin her kalemi için bir satır oluştur (kalemsiz/boş satırlar olan
   talep yoksa atla). Kolonlar (Türkçe başlıklar, bu sırayla):
   `Talep ID | Kalem ID | Departman | Tarih | Personel | Aciliyet | Talep Notu | Ürün Adı | Miktar | Birim | Mevcut Durum | Karar`
   **Kalem ID** kullanıcı için görsel gürültü ama silinmemesi gerekiyor — geri
   yüklerken satırı doğru kaleme eşlemenin tek güvenilir yolu bu (ürün adına
   göre eşleştirmek, aynı talepte aynı isimde iki kalem olursa veya kullanıcı
   ürün adını da düzenlerse yanlış eşleşebilir). Son kolon (Karar) boş
   bırakılır — kullanıcı dolduracak.
3. `XLSX.utils.json_to_sheet(satirlar)` ile sayfa, `XLSX.utils.book_new()` +
   `book_append_sheet()` ile kitap oluştur, `XLSX.writeFile(wb, 'ic-talepler-'+bugununTarihi+'.xlsx')`
   ile indir. XLSX kütüphanesi yüklü değilse `parseLNExcel()`'deki ile birebir
   aynı lazy-load deseni kullanılır.
4. Liste boşsa (`0` talep/kalem), Excel oluşturmadan `toast('⚠️ Aktarılacak talep yok')`.

## Geri Yükleme — "📥 Excel'den Yükle"

Aynı sekmede, dosya seçici tetikleyen bir buton. Dosya seçilince:

1. `parseLNExcel()`'deki desenle XLSX'i oku, `sheet_to_json` ile satırlara çevir
   (`header:1` DEĞİL — bu sefer başlıklı obje formatı kullanılacak, yani
   `sheet_to_json(ws)` düz çağrı, çünkü kolon sırası kullanıcı tarafından
   bozulmuş olabilir; başlık adına göre eşleştirmek daha sağlam).
2. Satırları `Talep ID`'ye göre grupla.
3. Her talep grubu için:
   a. O talebin **canlı** durumunu Supabase'den tek satır sorguyla tazele
      (`GET /satin_alma_talepleri?id=eq.<id>&select=durum`) — önbellekteki
      `DB.talepler` değerine güvenilmiyor.
   b. Canlı durum `'bekleyen'` değilse (biri zaten karar vermiş veya siparişe
      dönüştürülmüş): bu talebi tamamen atla, sonuç raporuna
      `{talepId, sebep:'zaten karara bağlanmış'}` olarak ekle.
   c. Gruptaki satırların `Karar` değerlerini topla (boş olmayanlar). Hepsi
      aynıysa (`Onayla` ya da `Reddet`) devam et; farklı değerler varsa
      (çelişki) bu talebi tamamen atla, sonuç raporuna
      `{talepId, sebep:'çelişkili karar'}` olarak ekle.
   d. Her satırda Miktar, mevcut kalemin miktarından farklıysa, o kalemi
      (satır içindeki kalem `id`'siyle eşleştirerek) `PATCH
      satin_alma_talep_kalemleri?id=eq.<kalemId>` ile güncelle.
   e. Karar `Onayla` ise `talepOnayla(talepId)` ile AYNI PATCH'i (durum:
      'onaylandi'), `Reddet` ise `talepReddet(talepId)` ile aynısını
      (durum: 'reddedildi') uygula. Karar boşsa (sadece miktar değişmiş
      olabilir) durum değiştirilmez.
4. İşlem bitince özet modal/toast: `"✅ 4 talep onaylandı, 1 reddedildi, 7 kalem miktarı güncellendi. ⚠️ 2 satır atlandı (detay için konsola bak)."`
   Atlanan satırların sebepleri `console.warn` ile de yazılır (basit hata
   ayıklama için — bu projede özel bir log ekranı yok).
5. İşlem sonunda `renderTalepler()` çağrılarak liste tazelenir.

## Hata durumları

- Excel'de `Talep ID` sütunu eksik/bozuksa veya sistemde karşılığı yoksa: o
  satır atlanır, rapora `{talepId (varsa), sebep:'talep bulunamadı'}` eklenir.
- `Karar` sütununda "Onayla"/"Reddet" dışında bir değer varsa (yazım hatası
  vb.): geçersiz sayılır, boş muamelesi görür (durum değişmez), ama miktar
  güncellemesi yine de uygulanır.
- Ağ hatası (fetch başarısız): o talep/kalem için işlem atlanır, rapora
  eklenir, kalan satırlarla devam edilir (tek bir hata tüm içe aktarmayı
  durdurmaz).

## Test/doğrulama planı

Bu ortamda gerçek tarayıcıda dosya indirme/yükleme akışı tıklanarak test
edilemiyor (önceki oturumlarda belirtildiği gibi). Doğrulama:
1. Dışa aktarılan sütun adlarının/sırasının tasarımdakiyle birebir eştiğini
   statik olarak doğrulamak.
2. `Karar`/`Miktar` eşleştirme mantığını elle iz sürerek (kod okuyarak)
   doğrulamak — özellikle çelişkili karar ve "zaten karara bağlanmış" dallarını.
3. Kullanıcının gerçek bir Excel dosyasıyla uçtan uca denemesi (bu adım bu
   oturumun dışında, kullanıcı tarafından yapılacak).
