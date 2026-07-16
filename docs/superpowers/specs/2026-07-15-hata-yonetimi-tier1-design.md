# Hata Yönetimi — Tier 1 (Sessiz Yanlış-Başarıyı Durdur) — Tasarım

## Problem / Hedef

Kod tabanındaki kritik yazma işlemlerinin çoğu (~25-30 nokta) başarısız
olduğunda kullanıcıya hiçbir uyarı vermiyor — sadece `console.warn` ile
bastırılıyor ya da hiç yakalanmıyor. Kullanıcı işlem başarısız olsa bile
"başarılı" toast'ı görüyor. Güvenlik/bütünlük denetim raporunun P1
maddesi. Bu iş, en yüksek riskli iki grubu (Tier 1) ele alır ve sessiz
yanlış-başarıyı durdurur.

## Kapsam

İki en tehlikeli grup:

1. **`depo-siparis.html` `onayla()`** — iç talep onayı: stok transfer RPC,
   `saveHar` (hareket), `saveSipDurum` (durum) ve koli-PATCH yazmalarının
   hepsi sessiz (`console.warn`). Fonksiyon `s.durum='onaylandi'`'yı
   yazmadan ÖNCE set edip her koşulda "✅ Onaylandı, stok transferi
   yapıldı" toast'ı gösteriyor — yarı-yazma olursa kullanıcı bilmiyor.

2. **5 muhasebe dosyası** (`muhasebe-yevmiye.html`, `muhasebe-faturalar.html`,
   `muhasebe-demirbas.html`, `muhasebe-cek-senet.html`,
   `muhasebe-sene-sonu.html`) — her biri kayıt güncellerken **PATCH başlık
   → satır kalemlerini DELETE → yeniden POST** deseni kullanıyor, hepsi
   tek `try{...}catch(e){console.warn(e)}` içinde, hiç `.ok` kontrolü yok.
   Reinsert POST başarısız olursa (constraint/izin/ağ) kayıt **satırsız**
   kalır (borç≠alacak / yetim fatura) ve çağıran "kaydedildi" gösterir.

## Kapsam dışı

- Muhasebe yarı-silmenin TAM atomik çözümü (DELETE+reinsert'i tek Postgres
  RPC transaction'ında yapmak) — bu, stok transferindeki gibi ayrı ve
  büyük bir "muhasebe transaction" işidir. Bu iş, işlemi atomik yapmaz;
  sadece başarısızlığı **görünür ve engelleyici** kılar (kullanıcı eksik
  kaydı bilir ve düzeltir).
- ~25 düşük-riskli sessiz-silme noktası (cariler/banka/fatura/butce
  DELETE'leri) — başarısız bir DELETE kaydı olduğu gibi bırakır, yarı-silme
  kadar tehlikeli değil; sonraki bir işte ele alınabilir.
- Ortak `sbWrite()` fetch wrapper'ı — çok fazla dosyaya dokunur, bu işin
  kapsamını aşar; her nokta mevcut ham-fetch deseniyle yerinde düzeltilir.
- Zaten iyi ele alınmış akışlar (`sayimOnayla`, `stokaIsle`/`kaliteOnayla`,
  yeni RPC `.ok` kontrolleri) — dokunulmaz.

## Mimari

### 1. `depo-siparis.html` `onayla()`

- `saveHar(h)` ve `saveSipDurum(s)` yardımcıları `r.ok` (boolean) döndürecek
  şekilde güncellenir (şu an `void`, hatayı `console.warn` ile yutuyorlar —
  `console.warn` korunur ama artık dönüş değeri de verirler).
- `onayla()` içinde bir `basarili` bayrağı: transfer RPC `!rT.ok`,
  `saveHar` `false`, veya `saveSipDurum` `false` olursa `basarili=false`.
- Sonda: `basarili` ise mevcut "✅ Onaylandı, stok transferi yapıldı"
  toast'ı; değilse "⚠️ Onay kısmen başarısız oldu — stok/durum tam
  güncellenemedi. Sayfayı yenileyip talebin durumunu kontrol edin, gerekirse
  tekrar deneyin." (engelleyici değil ama net bir hata toast'ı, 4sn).
- Koli-PATCH (fiziksel etiket metadata'sı, satır ~970) düşük risk: hatası
  ayrı `console.warn`'da kalır, `basarili`'yı etkilemez (stok/durum
  bütünlüğünü bozmaz).

### 2. Muhasebe DELETE-sonra-reinsert (5 dosya)

Her `saveYevmiye`/`saveFatura`/`saveDemirbas`/`saveCekSenet`/sene-sonu-kayıt
fonksiyonunda, satır-kalemi reinsert POST'u `.ok` kontrol edilir:

```js
    if(kalemSatirlar.length){
      const rK=await fetch(SB_URL+'/rest/v1/<kalem_tablosu>',{method:'POST',headers:SB_HEADERS,body:JSON.stringify(kalemSatirlar)});
      if(!rK.ok){
        console.error('kalem reinsert hatası:',await rK.text());
        alert('⚠️ DİKKAT: Kayıt başlığı güncellendi ama satır kalemleri yazılamadı — bu kayıt şu an EKSİK/DENGESİZ olabilir. Lütfen kaydı tekrar açıp yeniden kaydedin veya bir yetkiliyle iletişime geçin.');
        return false;
      }
    }
    return true;
```

Fonksiyonun sonunda (hepsi başarılıysa) `return true`; en dıştaki
`catch(e)` bloğunda da `console.warn(e); return false;` (exception
durumunda da sahte başarı olmasın). Çağıran kod, bu fonksiyonun
`false` döndürdüğü durumda kendi "kaydedildi" toast'ını göstermez —
çağıran her sitede dönüş değeri kontrol edilir (`if(await saveYevmiye(y)){ toast('✅ ...') }` gibi).

## Test/doğrulama planı

Statik: Her 6 dosyada, kritik yazma noktalarının artık `.ok` kontrol
ettiğini ve başarısızlıkta ya engelleyici `alert` ya da net hata toast'ı
gösterip sahte başarıyı önlediğini kod okuyarak doğrulamak; dönüş
değerlerinin (`saveYevmiye` vb. `false`) çağıranlarca kontrol edildiğini
doğrulamak.

Gerçek uçtan uca test (kullanıcı, mümkünse): Ağ sekmesinden bir reinsert
POST'unu bilerek başarısız kılıp (veya geçici bir hatalı payload ile)
kullanıcının artık "kaydedildi" yerine uyarı gördüğünü; depo-siparis
onayında bir yazma başarısız olduğunda "⚠️ kısmen başarısız" mesajının
çıktığını doğrulamak. Normal (başarılı) akışlarda hiçbir davranış
değişmemeli — başarı toast'ları eskisi gibi görünmeli.
