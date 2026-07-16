# Soft-Delete — Tasarım

## Problem / Hedef

Kullanıcılar cari/fatura/demirbaş/çek-senet/banka hesabı/bütçe kaydı gibi
mali-kritik kayıtları kalıcı `DELETE` ile siliyor. Kayıt veritabanından
tamamen kayboluyor — geçmiş raporlar bozuluyor, "bu kayıt neden yok"
sorusunun cevabı olmuyor, yanlışlıkla (veya kötü niyetle) silinen bir
kayıt kurtarılamıyor. Güvenlik/bütünlük denetim raporunun P1 maddesi.

## Kapsam

**Bu işte soft-delete'e geçirilecek 7 tablo:**
`cariler`, `faturalar`, `demirbaslar`, `cek_senetler`,
`banka_kasa_hesaplari`, `butce_kayitlari`, `kullanicilar` (bu sonuncusu
zaten `aktif` bayrağına sahip — sadece DELETE'in kendisi PATCH'e çevrilecek).

**Paralel çalışma nedeniyle kasıtlı olarak ERTELENEN:** `hesap_plani` —
bu tablo `satin-alma.html`'de de okunuyor, o dosya şu an aktif olarak
başka bir oturumda (RFQ/teklif yönetimi) değiştiriliyor. Çakışma riskini
önlemek için bu iş dışında bırakıldı, RFQ işi bitince ayrı ele alınabilir.

**Kapsam dışı bırakılan diğer DELETE'ler (gerçek "kayıt silme" değil):**
- `yevmiye_kalemleri`/`fatura_kalemleri`/`recete_kalemleri` reinsert'leri
  — bunlar "düzenlerken satırları sil, yeniden yaz" deseni (kayıt
  düzenlemenin parçası), kullanıcının bilinçli sildiği bir kayıt değil.
  Soft-delete'e çevirmek düzenleme akışını bozar.
- `doviz_kurlari` — bir günün kurunu güncellerken sil-yeniden-yaz.
- `sene_sonu_kapanislar`/`yevmiye_fisler` (sene-sonu geri-alma akışı) —
  bir kapanış işlemini tersine çevirme, kayıt temizliği değil.
- Geri getirme (restore) arayüzü — bu iş sadece silmeyi geri döndürülebilir
  kılıyor (veritabanında kayıt duruyor); bir "geri getir" butonu bu işin
  kapsamında değil, ayrı bir iş olarak sonra eklenebilir.

## Mimari

### 1. SQL — 6 tabloya `silindi` kolonu

`kullanicilar` hariç (zaten `aktif` var) her tabloya:

```sql
alter table cariler add column if not exists silindi boolean default false;
alter table faturalar add column if not exists silindi boolean default false;
alter table demirbaslar add column if not exists silindi boolean default false;
alter table cek_senetler add column if not exists silindi boolean default false;
alter table banka_kasa_hesaplari add column if not exists silindi boolean default false;
alter table butce_kayitlari add column if not exists silindi boolean default false;
```

### 2. Silme butonları: DELETE → PATCH

Her tablonun mevcut "Sil" butonunun çağırdığı fonksiyon, `method:'DELETE'`
yerine `method:'PATCH', body:{silindi:true}` gönderir. Kullanıcı deneyimi
**değişmez** — aynı `confirm()` uyarısı, aynı buton, kayıt aynı şekilde
listeden kayboluyormuş gibi görünür; farkı sadece kayıt veritabanında
kalıcı olarak durur.

**Alt kayıt temizliği artık gereksiz:** Bugün bir cari silinirken önce
`cari_hareketler` (o cariye ait tüm hareketler) da `DELETE` ediliyor
(`muhasebe-cariler.html:614`), aynı şekilde bir banka hesabı silinirken
`banka_kasa_hareketleri` siliniyor (`muhasebe-banka.html:440`). Soft-delete
ile üst kayıt (cari/hesap) silinmiyor, sadece işaretleniyor — bu yüzden
alt kayıtları da silmeye gerek yok, onlar **denetim izi olarak olduğu
gibi kalır** (bugünden daha iyi bir davranış). Bu iki alt-kayıt DELETE
çağrısı tamamen kaldırılır.

`kullanicilar` için: `kullanici-yonetimi.html:240`'daki DELETE,
`PATCH {aktif:false}`'a çevrilir (kolon zaten var, sadece bu tek nokta
değişir).

### 3. Okuma filtreleri — her yerde aynı filtre, mevcut UX korunur

Bu 6 tablo için (kullanıcı yönetiminden farklı olarak) hiçbir düzenleme
formunda "aktif/silindi" onay kutusu yok, ve bu işin kapsamında bir geri
getirme (restore) arayüzü de yok. Bu yüzden "kayıt sahibi ekran hepsini
gösterir" deseni burada değer katmaz — kullanıcı gördüğü ama üzerinde
hiçbir şey yapamadığı bir "silinmiş" satırla kafası karışır. Bunun yerine
**her okuma noktasına** (tablonun kendi yönetim ekranı dahil)
`&silindi=eq.false` eklenir — kullanıcı deneyimi bugünle birebir aynı
kalır (silinen kayıt her yerde kaybolur), tek fark kaydın veritabanında
kalıcı olarak durmasıdır.

| Tablo | Tüm okuma noktaları (hepsine `&silindi=eq.false` eklenir) |
|---|---|
| `cariler` | `muhasebe-cariler.html:337` (kendi ekranı), `mal-kabul-v2.html:402`, `stok-takip.html:687`, `muhasebe.html:137`, `muhasebe-cek-senet.html:225`, `muhasebe-raporlar.html:181`, `muhasebe-asistan.html:137`, `muhasebe-faturalar.html:432` |
| `faturalar` | `muhasebe-faturalar.html:431` (kendi ekranı), `muhasebe-asistan.html:139`, `muhasebe-raporlar.html:183`, `muhasebe-cariler.html:339` |
| `demirbaslar` | `muhasebe-demirbas.html:233` (kendi ekranı), `muhasebe-raporlar.html:184` |
| `cek_senetler` | `muhasebe-cek-senet.html:224` (kendi ekranı), `muhasebe-raporlar.html:185` |
| `banka_kasa_hesaplari` | `muhasebe-banka.html:272` (kendi ekranı), `muhasebe-asistan.html:141` |
| `butce_kayitlari` | `muhasebe-butce.html:179` (tek okuma noktası, kendi ekranı) |

Örnek: `cariler?select=id,kod,ad,tip&tip=in.(tedarikci,her_ikisi)` →
`cariler?select=id,kod,ad,tip&tip=in.(tedarikci,her_ikisi)&silindi=eq.false`.

Bu iş kapsamında görsel "silindi" rozeti veya geri getirme (restore)
arayüzü YOK — kapsam dışı, ayrı bir iş olarak sonra eklenebilir.

## Test/doğrulama planı

Statik: Her tabloda silme butonunun artık `DELETE` değil `PATCH
{silindi:true}` gönderdiğini; alt-kayıt DELETE'lerinin (cari_hareketler,
banka_kasa_hareketleri) kaldırıldığını; listelenen her okuma noktasının
(yönetim ekranı hariç) `&silindi=eq.false` içerdiğini kod okuyarak
doğrulamak.

Gerçek uçtan uca test (kullanıcı): Bir cari/fatura/demirbaş/çek-senet/
banka hesabı/bütçe kaydı sil → (1) o kaydın SAHİP olduğu yönetim ekranında
"🗑️ Silindi" rozetiyle hâlâ göründüğünü, (2) diğer tüm ekranlarda
(raporlar, seçim listeleri, ilişkili modüller) artık hiç görünmediğini,
(3) Supabase'de satırın hâlâ veritabanında durduğunu (sadece
`silindi=true`) doğrulamak.
