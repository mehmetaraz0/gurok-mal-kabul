# Bar A1 — Manuel Tarayıcı Testi (yerel onay pencereli akışlar)

**Neden manuel:** Bu akışlarda tarayıcının **yerel** `confirm` / `prompt` penceresi çıkar.
Ölçüldü (2026-09-20): uygulama içi tarayıcı bölmesi bu pencereleri kendiliğinden kapatıyor;
Chrome eklentisinde pencere gerçekten çıkıyor ve sayfayı bloke ediyor ama otomasyon o pencereye
tıklayamıyor (pencere sayfanın değil tarayıcının parçası). Kalan tek yol: **insan eliyle bir tur.**
Bunun için ekranda değişiklik yapılmadı.

**Üretime bağlanmaz.** Her şey yerel, izole ortamda çalışır; üretim adresi ve anahtarı yüklenmez.

## Ortamı başlat

```bash
node scripts/bar-edge-e2e/tarayici-ortami.mjs
```

`HAZIR http://127.0.0.1:3300` satırını görünce tarayıcıda o adresi açın. Kapatmak için Ctrl+C
(konteynerler silinir). Docker Desktop açık olmalı.

Giriş bağlantıları (PIN ekranı kapsam dışı; oturum doğrudan kurulur):

| Kişi | Bağlantı |
|---|---|
| Bar personeli (kayıt) | `http://127.0.0.1:3300/__giris?kisi=bar810&hedef=bar-siparis-kuyrugu.html` |
| Bar şefi (tam) | `http://127.0.0.1:3300/__giris?kisi=sef810&hedef=bar-siparis-kuyrugu.html` |
| Cost control | `http://127.0.0.1:3300/__giris?kisi=cc810&hedef=stok-takip.html` |
| Garson | `http://127.0.0.1:3300/__giris?kisi=bar810&hedef=bar-garson.html` |
| Müşteri menüsü | `http://127.0.0.1:3300/bar-menu.html?t=tok-810-a` |

Sipariş oluşturmak için müşteri menüsünü kullanın: Viski ×1 + oda **101** → "Sipariş Ver".

## Test adımları ve beklenen sonuç

| # | Adım | Beklenen |
|---|---|---|
| 1 | Kuyrukta ücretli siparişte **Doğrula** → çıkan pencerede **İptal** | Hiçbir şey değişmez; sipariş "oda doğrulaması bekliyor" kalır |
| 2 | Yine **Doğrula** → pencerede **Tamam** | "Oda doğrulandı" bildirimi; kart "✔ Oda doğrulandı" olur |
| 3 | Yeni bir ücretli siparişte **Reddet** → açılan kutuyu **boş bırakıp** Tamam | "Ret nedeni zorunlu" uyarısı; sipariş değişmez |
| 4 | Aynı siparişte **Reddet** → neden yazıp Tamam | Sipariş iptal olur, kart "reddedildi" gösterir |
| 5 | Doğrulanmış siparişi Hazırlanıyor → Hazır yapın. Ayrı bir pencerede folyoyu kapatın (aşağıdaki komut). Sonra **Teslim Et** → çıkan "servis edildi mi" penceresinde **İptal** | Hiçbir şey yazılmaz; sipariş "hazır" kalır |
| 6 | Aynı siparişte **Teslim Et** → **Tamam** (bar personeli, kayıt yetkisi) | "Bu işlem için yetkiniz yok"; sipariş "hazır" kalır |
| 7 | Şef bağlantısıyla girip **Teslim Et** → **Tamam** | "İstisna açıldı"; kart "istisna — ön büro çözümü bekliyor" olur, borç yazılmaz |
| 8 | Yeni (hazırlanmamış) bir siparişte **İptal** → nedeni boş bırakın | "İptal nedeni zorunlu"; sipariş durur |
| 9 | Aynı siparişte **İptal** → neden yazın | Sipariş iptal olur, ayrılan stok serbest kalır |
| 10 | Stok-takip → Sayım → Onay Bekleyen → İncele → **Onayla** | Kısmi uygulama uyarısı çıkar (varsa) ve sonuç ekranda görünür |
| 11 | Bekleyen düzeltme listesinde **Uygula** → çıkan pencerede **Tamam** | "Uygulandı: X → Y" bildirimi |

Folyo kapatma komutu (5. adım için):

```bash
docker exec -i bar-tarayici-ana-db psql -X -U postgres -d bar -c "set session_replication_role = replica; update public.pms_folyolar set durum='kapali', kapanis_zamani=now() where id='55555555-0000-0000-0000-000000000101';"
```

## Sonuç kaydı

Her adım için "geçti / geçmedi + görülen" yazıp bana iletin; raporda **koşullu geçti** yerine
**manuel doğrulandı** olarak işaretleyeyim. Beklenenden farklı tek bir sonuç bile olursa
adım numarasıyla yazın — o akışı düzeltmeden yayın sırası önerisi güncellenmez.

**Not:** 1–11 arasındaki sunucu tarafı sonuçların hepsi otomatik testlerde zaten doğrulandı
(`bar-a1-ekran` 37/37, `bar-a1-guvenlik` 72/72). Bu turda sınanan tek şey, **yerel pencerelerin
kendisi**: doğru metni gösteriyor mu, "İptal" gerçekten hiçbir şey yazmıyor mu, "Tamam" akışı
tamamlıyor mu.
