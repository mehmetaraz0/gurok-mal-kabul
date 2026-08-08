# Madde D — Otel/Depo RLS İzolasyonu — TASARIM

**Durum:** TASARIM (kod/canlı değişiklik YOK). Kullanıcı onayı sonrası fazlı uygulama.
**Tarih:** 2026-07-31

## Karar verilen model
- **Otel-seviyesi izolasyon** (depo-seviyesi YOK — daha basit, kullanıcı kararı).
- **Otel + merkez istisnası:** kullanıcı yalnızca kendi `otel_id`'sinin (810 Club / 811 Resort)
  verisini görür; **merkez** kullanıcılar tüm otelleri görür.
- **Merkez sinyali = kullanıcı başına bayrak:** `kullanicilar.tum_oteller boolean`.
  (Ayrı bir "merkez" otel_id yok; sadece 810/811 var. Merkez-yönetim kullanıcıları da
  810/811 taşıyor, o yüzden otel_id'den türetilemez — açık bir bayrak gerekli.)

## Yardımcı fonksiyonlar (SECURITY DEFINER — auth_yetki_var deseniyle aynı)
```
auth_otel_id()            -> caller'ın kullanicilar.otel_id'si (auth.uid() ile)
auth_tum_oteller()        -> caller'ın tum_oteller bayrağı (bool)
auth_otel_erisim(p_otel)  -> auth_tum_oteller() OR p_otel = auth_otel_id()
```
Hepsi SECURITY DEFINER (RLS'i baypas edip kullanicilar'ı okur; mevcut auth_yetki_var ile aynı güvenli desen).

## Tablo kategorizasyonu

### Otel-kapsamlı olacak (22 tablo — RLS'e `auth_otel_erisim(otel_id)` AND'lenecek)
banka_kasa_hareketleri, banka_kasa_hesaplari, butce_kayitlari, cari_hareketler,
cek_senetler, demirbaslar, edefter_sube_bilgileri, faturalar, ic_talepler,
koli_etiketleri, mal_kabuller, recete_tuketimleri, receteler, satin_alma_talepleri,
sayim_oturumlari, siparisler, skt_kayitlari, stok, stok_hareketleri, stok_minimumlar,
teklif_talepleri, uygunsuzluklar, yevmiye_fisler

### Özel — DİKKAT
- **kullanicilar** (otel_id var): Login `pin_dogrula` SECURITY DEFINER olduğu için RLS'i
  baypas eder → **giriş etkilenmez.** Sadece Kullanıcı Yönetimi listesinin otel-kapsamı
  sorusu var. En sona, ayrı ve dikkatli ele alınacak (yanlışlıkla admin'in kendini
  kilitlemesi riski).

### Paylaşımlı — DOKUNULMAZ (otel_id yok, doğal olarak ortak)
urunler, hesap_plani, roller, moduller, yetki_matrisi, cariler/firmalar (master),
kur, vb. — ürün kataloğu/hesap planı/yetki tüm otellerde ortak, bilerek paylaşımlı.

## Fazlı uygulama (güvenli, geri-dönüşlü)

**Faz 1 — RİSKSİZ (canlı davranış değişmez):**
- `alter table kullanicilar add column tum_oteller boolean not null default false;`
- 3 yardımcı fonksiyonu oluştur.
- Merkez kullanıcıları işaretle: `update kullanicilar set tum_oteller=true where <merkez kriteri>`
  **MERKEZ KRİTERİ (kullanıcı kararı 2026-07-31):** müdür + yönetici + **depo yöneticisi**
  rolleri tum_oteller=true. Operasyonel roller (mutfak/garson/satınalma personeli) kendi oteli.
  Depo yöneticisinin çapraz-otel görmesi güvenli: izolasyon `auth_yetki_var(modul) AND
  auth_otel_erisim(otel_id)` iki katmanlı → depo yöneticisi yalnızca yetkili olduğu
  (stok/depo) modüllerde her iki oteli görür, muhasebe yetkisi olmadığı için diğer otelin
  muhasebesini göremez. Yetki katmanı fazla-paylaşımı engelliyor.
  Faz 1'de: `select id,ad,kod,seviye from roller order by seviye desc;` ile müdür/yönetici/
  depo-yöneticisi rol_id'leri belirlenip UPDATE yazılacak (departman='MERKEZ YÖNETİM' de dahil).
- Politikalara HENÜZ dokunulmaz → hiçbir şey değişmez. Doğrulama: fonksiyonlar doğru
  otel_id/bayrak dönüyor mu.

**Faz 2 — PİLOT (2 tablo):**
- `stok` + `faturalar` politikalarına `and auth_otel_erisim(otel_id)` ekle
  (SELECT + INSERT/UPDATE/DELETE with check dahil).
- Test: 810 kullanıcısı sadece 810 görür, 811 sadece 811, merkez hepsini;
  ilgili ekranlar (Stok Takip, Faturalar) kırılmıyor; INSERT'te otel_id doğru gidiyor.

**Faz 3 — DALGALAR:** kalan 20 tabloyu 4-5'erli gruplar halinde, her dalgadan sonra test.

**Faz 4 — kullanicilar:** en son, ayrı; Kullanıcı Yönetimi listesini otel-kapsa
(merkez tümünü, otel-admini kendi otelini) — admin kendini kilitlemesin diye dikkatli.

## Kritik riskler + önlemler
1. **Boş/yanlış otel_id → kullanıcı hiçbir şey görmez.** Faz 1 öncesi ÖN-KONTROL:
   tüm aktif kullanıcıların geçerli (810/811) otel_id'si var mı? (null varsa önce düzelt.)
2. **INSERT with check:** yeni satır otel_id'si caller'ın oteliyle eşleşmeli. İstemci
   zaten doğru otel_id gönderiyor mu — her insert akışı Faz 2/3'te kontrol edilecek.
   Göndermiyorsa insert kırılır → gerekirse otel_id'yi set eden trigger.
3. **Merkez bayrağı Faz 2'den ÖNCE set edilmeli** yoksa merkez kullanıcılar çapraz-otel
   görünürlüğünü kaybeder.
4. **İstemci UX:** tek-otel kullanıcı için "diğer otel" seçicileri boş kalır — RLS kırılmaz,
   sadece boş döner; otel seçiciyi gizlemek ayrı bir UX iyileştirmesi (bloklamaz).
5. Her fazın rollback'i: eklenen `and auth_otel_erisim(...)` koşulunu politikadan çıkar
   (veya önceki politikayı geri koy). Faz 1 rollback: kolon + fonksiyon drop.

## Uygulama notu
Faz 1 risksiz (bugün prep edilebilir). Faz 2-4 dikkatli test + fazlı — düşük-kullanım
penceresi + taze oturum önerilir (tıpkı [3] cutover gibi). auth_yetki_var RLS'i bozan
regresyon dersi burada da geçerli: yeni auth.uid()-bağlı koşul eklerken tüm giriş
yolları SB_HEADERS'ı login'de tazeliyor olmalı (zaten [3] sonrası öyle).
