# Hata Yönetimi Tier 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** En yüksek riskli iki grup sessiz-yazma hatasını (muhasebe DELETE-sonra-reinsert yarı-silme + depo-siparis onayla sessiz yazma) görünür/engelleyici kılıp kullanıcının başarısızlıkta "başarılı" sanmasını önlemek.

**Architecture:** Ortak wrapper yok — her nokta yerinde düzeltilir. Muhasebe reinsert POST'larına `.ok` kontrolü + başarısızlıkta engelleyici `alert()` eklenir (modal alert, çağıranın toast'ından önce kullanıcıyı durdurur — asıl güvenlik mekanizması). `depo-siparis.html onayla()`'da yardımcılar `.ok` döndürür ve son toast dürüst olur.

**Tech Stack:** Vanilla JS, ham `fetch()` + Supabase REST. Build/test aracı yok — doğrulama grep + kod okuma + kullanıcı testi.

## Global Constraints

- Muhasebe reinsert güvenlik deseni (her `_kalemleri` POST'una uygulanır): POST'un dönüşünü bir değişkene al, `!r.ok` ise `console.error(await r.text())` + engelleyici `alert('⚠️ DİKKAT: Kayıt başlığı güncellendi ama satır kalemleri yazılamadı — bu kayıt şu an EKSİK/DENGESİZ olabilir. Lütfen kaydı tekrar açıp yeniden kaydedin veya bir yetkiliyle iletişime geçin.')`.
- Temiz save fonksiyonlarında (`saveYevmiye`, `saveFatura`, demirbas/cek-senet kayıt fonksiyonu) başarısızlıkta `return false`, sonda `return true`. Daha büyük akış içine gömülü reinsert'lerde (faturalar oto-yevmiye, sene-sonu) sadece `alert` + `return` (fonksiyonun mevcut dönüş sözleşmesini bozma).
- Asıl güvenlik = engelleyici `alert()`; çağıran kod dönüş değerini kontrol etmek ZORUNDA değil (alert modal olduğu için sahte-başarı toast'ından önce görünür). İstisna: `depo-siparis onayla` yardımcılarının dönüşünü kullanır.
- Normal (başarılı) akışta hiçbir davranış değişmez — başarı toast'ları eskisi gibi.
- Zaten iyi ele alınmış akışlara (sayimOnayla, stokaIsle, RPC `.ok` kontrolleri) dokunulmaz.
- `stok_hareketleri` ve diğer hareket INSERT'leri ile atomiklik (RPC transaction) bu işin kapsamı DIŞINDA.

---

### Task 1: `depo-siparis.html` — onayla dürüst hata bildirimi

**Files:**
- Modify: `depo-siparis.html` (`saveSipDurum` ~434-446, `saveHar` ~447-457, `onayla` transfer loop + son toast ~953-980)

**Interfaces:**
- Produces: `saveSipDurum(s)` → `boolean` (header PATCH `.ok`); `saveHar(h)` → `boolean`.

- [ ] **Step 1: `saveSipDurum`'u boolean döndürecek şekilde güncelle**

`depo-siparis.html`'de `saveSipDurum` (satır 434-446) gövdesini şununla değiştir:

```js
async function saveSipDurum(s){
  try{
    const rH=await fetch(SB_URL+'/rest/v1/ic_talepler?id=eq.'+s.id,{method:'PATCH',headers:SB_HEADERS,body:JSON.stringify({
      durum:s.durum,onaylayan_ad:s.onaylayanAd||null,
      onay_tarihi:s.onayTarih?new Date(s.onayTarih).toISOString():null,red_notu:s.redNot||null
    })});
    for(const u of s.urunler){
      if(u.id&&u.onaylananMiktar!==undefined){
        await fetch(SB_URL+'/rest/v1/ic_talep_kalemleri?id=eq.'+u.id,{method:'PATCH',headers:SB_HEADERS,body:JSON.stringify({onaylanan_miktar:u.onaylananMiktar})});
      }
    }
    return rH.ok;
  }catch(e){console.warn(e);return false;}
}
```

- [ ] **Step 2: `saveHar`'ı boolean döndürecek şekilde güncelle**

`depo-siparis.html`'de `saveHar` (satır 447-457) gövdesini şununla değiştir:

```js
async function saveHar(h){
  try{
    if(h.tip==='transfer'){
      const rHar=await fetch(SB_URL+'/rest/v1/stok_hareketleri',{method:'POST',headers:SB_HEADERS,body:JSON.stringify({
        urun_kodu:h.lnKod,depo_kodu:h.hedefDepoId,otel_id:otelFromDepoId(h.hedefDepoId),
        tip:'transfer',miktar:h.miktar,belge_no:h.siparisId||null,
        aciklama:`İç Talep: ${h.kaynakDepoAd} → ${h.hedefDepoAd}${h.not?' — '+h.not:''}`
      })});
      return rHar.ok;
    }
    return true;
  }catch(e){console.warn(e);return false;}
}
```

- [ ] **Step 3: `onayla`'da başarı bayrağı ve dürüst toast**

`depo-siparis.html`'de `onayla` içindeki transfer RPC döngüsünden (satır ~953) son toast'a (satır ~980) kadar olan şu bloğu:

```js
    for(const h of harlar){
      try{
        const rT=await fetch(SB_URL+'/rest/v1/rpc/stok_transfer',{
          method:'POST',headers:SB_HEADERS,
          body:JSON.stringify({p_urun_kodu:h.lnKod,p_kaynak_depo:h.kaynakDepoId,p_hedef_depo:h.hedefDepoId,p_hedef_otel:otelFromDepoId(h.hedefDepoId),p_miktar:h.miktar})
        });
        if(!rT.ok)console.warn('stok_transfer RPC hatası',await rT.text());
      }catch(e){console.warn('stok_transfer RPC hatası',e);}
    }
  for(const h of harlar)await saveHar(h);
  await saveSipDurum(s);
```

şununla değiştir:

```js
    let yazmaBasarili=true;
    for(const h of harlar){
      try{
        const rT=await fetch(SB_URL+'/rest/v1/rpc/stok_transfer',{
          method:'POST',headers:SB_HEADERS,
          body:JSON.stringify({p_urun_kodu:h.lnKod,p_kaynak_depo:h.kaynakDepoId,p_hedef_depo:h.hedefDepoId,p_hedef_otel:otelFromDepoId(h.hedefDepoId),p_miktar:h.miktar})
        });
        if(!rT.ok){yazmaBasarili=false;console.warn('stok_transfer RPC hatası',await rT.text());}
      }catch(e){yazmaBasarili=false;console.warn('stok_transfer RPC hatası',e);}
    }
  for(const h of harlar){if(!(await saveHar(h)))yazmaBasarili=false;}
  if(!(await saveSipDurum(s)))yazmaBasarili=false;
```

Ardından, `onayla`'nın en sonundaki (satır ~980) şu satırı:

```js
  depoQrDurdur();
  hLD();toast('✅ Onaylandı, stok transferi yapıldı');rGelen();rBugun();
```

şununla değiştir:

```js
  depoQrDurdur();
  hLD();
  if(yazmaBasarili){toast('✅ Onaylandı, stok transferi yapıldı');}
  else{toast('⚠️ Onay kısmen başarısız oldu — stok/durum tam güncellenemedi. Sayfayı yenileyip talebin durumunu kontrol edin, gerekirse tekrar deneyin.',5000);}
  rGelen();rBugun();
```

(Not: koli-PATCH döngüsü (~967-978) DEĞİŞMEZ — fiziksel etiket metadata'sı, düşük risk.)

- [ ] **Step 4: Doğrulama**

```bash
grep -n "yazmaBasarili\|return rH.ok\|return rHar.ok\|Onay kısmen başarısız" depo-siparis.html
```
Expected: `yazmaBasarili` (tanım + set noktaları + 2 kullanım), `return rH.ok`, `return rHar.ok`, "Onay kısmen başarısız" toast'ı mevcut.

- [ ] **Step 5: Commit**

```bash
git add depo-siparis.html
git commit -m "fix: depo-siparis onayla'da yarı-yazmada dürüst hata bildirimi"
```

---

### Task 2: `muhasebe-yevmiye.html` — saveYevmiye reinsert guard

**Files:**
- Modify: `muhasebe-yevmiye.html` (`saveYevmiye` ~293-300)

- [ ] **Step 1: Reinsert POST'una `.ok` kontrolü + return değerleri ekle**

`muhasebe-yevmiye.html`'de `saveYevmiye` içindeki şu bloğu (satır ~293-300):

```js
    if(y.kalemler&&y.kalemler.length){
      const kalemSatirlar=y.kalemler.map(k=>({
        fis_id:fisUuid,hesap_kodu:k.hesapKod,masraf_merkezi:k.masrafMerkezi||null,
        aciklama:k.aciklama||null,borc:k.borc||0,alacak:k.alacak||0
      }));
      await fetch(SB_URL+'/rest/v1/yevmiye_kalemleri',{method:'POST',headers:SB_HEADERS,body:JSON.stringify(kalemSatirlar)});
    }
  }catch(e){console.warn(e);}
}
```

şununla değiştir:

```js
    if(y.kalemler&&y.kalemler.length){
      const kalemSatirlar=y.kalemler.map(k=>({
        fis_id:fisUuid,hesap_kodu:k.hesapKod,masraf_merkezi:k.masrafMerkezi||null,
        aciklama:k.aciklama||null,borc:k.borc||0,alacak:k.alacak||0
      }));
      const rK=await fetch(SB_URL+'/rest/v1/yevmiye_kalemleri',{method:'POST',headers:SB_HEADERS,body:JSON.stringify(kalemSatirlar)});
      if(!rK.ok){
        console.error('yevmiye_kalemleri reinsert hatası:',await rK.text());
        alert('⚠️ DİKKAT: Fiş başlığı güncellendi ama satır kalemleri yazılamadı — bu fiş şu an EKSİK/DENGESİZ olabilir. Lütfen fişi tekrar açıp yeniden kaydedin veya bir yetkiliyle iletişime geçin.');
        return false;
      }
    }
    return true;
  }catch(e){console.warn(e);return false;}
}
```

- [ ] **Step 2: Doğrulama**

```bash
grep -n "yevmiye_kalemleri reinsert hatası\|return true\|return false" muhasebe-yevmiye.html
```
Expected: reinsert hata mesajı + `return true`/`return false` mevcut.

- [ ] **Step 3: Commit**

```bash
git add muhasebe-yevmiye.html
git commit -m "fix: muhasebe-yevmiye saveYevmiye reinsert başarısızlığında engelleyici uyarı"
```

---

### Task 3: `muhasebe-faturalar.html` — iki reinsert noktası

**Files:**
- Modify: `muhasebe-faturalar.html` (oto-yevmiye ~372-378, `saveFatura` ~481-489)

- [ ] **Step 1: `saveFatura` reinsert guard**

`muhasebe-faturalar.html`'de `saveFatura` içindeki şu bloğu (satır ~481-489):

```js
    if(f.kalemler&&f.kalemler.length){
      const kalemSatirlar=f.kalemler.map(k=>({
        fatura_id:fisUuid,urun_kodu:k.kod||null,urun_adi:k.ad,miktar:k.miktar,
        birim:k.birim,birim_fiyat:k.birimFiyat,iskonto_yuzde:k.iskonto||0,
        kdv_orani:k.kdvOran,toplam:k.toplam
      }));
      await fetch(SB_URL+'/rest/v1/fatura_kalemleri',{method:'POST',headers:SB_HEADERS,body:JSON.stringify(kalemSatirlar)});
    }
  }catch(e){console.warn(e);}
}
```

şununla değiştir:

```js
    if(f.kalemler&&f.kalemler.length){
      const kalemSatirlar=f.kalemler.map(k=>({
        fatura_id:fisUuid,urun_kodu:k.kod||null,urun_adi:k.ad,miktar:k.miktar,
        birim:k.birim,birim_fiyat:k.birimFiyat,iskonto_yuzde:k.iskonto||0,
        kdv_orani:k.kdvOran,toplam:k.toplam
      }));
      const rK=await fetch(SB_URL+'/rest/v1/fatura_kalemleri',{method:'POST',headers:SB_HEADERS,body:JSON.stringify(kalemSatirlar)});
      if(!rK.ok){
        console.error('fatura_kalemleri reinsert hatası:',await rK.text());
        alert('⚠️ DİKKAT: Fatura başlığı güncellendi ama satır kalemleri yazılamadı — bu fatura şu an EKSİK olabilir. Lütfen faturayı tekrar açıp yeniden kaydedin veya bir yetkiliyle iletişime geçin.');
        return false;
      }
    }
    return true;
  }catch(e){console.warn(e);return false;}
}
```

- [ ] **Step 2: Oto-yevmiye reinsert guard**

`muhasebe-faturalar.html`'de otomatik yevmiye fişi oluşturan bloktaki şu satırları (satır ~376-378):

```js
    await fetch(SB_URL+'/rest/v1/yevmiye_kalemleri',{method:'POST',headers:SB_HEADERS,body:JSON.stringify(kalemSatirlar)});
    await auditLogYaz('create','yevmiye',fisUuid,`Otomatik yevmiye fişi: ${no} — ${aciklama} (${fmt(topBorc)} ₺)`);
  }catch(e){console.warn('Yevmiye fişi oluşturulamadı:',e);}
```

şununla değiştir:

```js
    const rYK=await fetch(SB_URL+'/rest/v1/yevmiye_kalemleri',{method:'POST',headers:SB_HEADERS,body:JSON.stringify(kalemSatirlar)});
    if(!rYK.ok){
      console.error('otomatik yevmiye_kalemleri reinsert hatası:',await rYK.text());
      alert('⚠️ DİKKAT: Faturanın otomatik muhasebe fişi başlığı oluştu ama satır kalemleri yazılamadı — bu fiş EKSİK/DENGESİZ olabilir. Muhasebe kayıtlarını kontrol edin.');
    }
    await auditLogYaz('create','yevmiye',fisUuid,`Otomatik yevmiye fişi: ${no} — ${aciklama} (${fmt(topBorc)} ₺)`);
  }catch(e){console.warn('Yevmiye fişi oluşturulamadı:',e);}
```

(Not: bu blok daha büyük bir fonksiyonun içinde; `return` eklenmez — sadece uyarı, ardından audit log akışı korunur.)

- [ ] **Step 3: Doğrulama**

```bash
grep -n "fatura_kalemleri reinsert hatası\|otomatik yevmiye_kalemleri reinsert hatası" muhasebe-faturalar.html
```
Expected: iki reinsert hata mesajı mevcut.

- [ ] **Step 4: Commit**

```bash
git add muhasebe-faturalar.html
git commit -m "fix: muhasebe-faturalar iki reinsert noktasında engelleyici uyarı"
```

---

### Task 4: `muhasebe-demirbas.html` + `muhasebe-cek-senet.html` — reinsert guard

**Files:**
- Modify: `muhasebe-demirbas.html` (~316), `muhasebe-cek-senet.html` (~303)

- [ ] **Step 1: `muhasebe-demirbas.html` reinsert guard**

`muhasebe-demirbas.html`'de satır ~316'daki şu satırı:

```js
    await fetch(SB_URL+'/rest/v1/yevmiye_kalemleri',{method:'POST',headers:SB_HEADERS,body:JSON.stringify(kalemSatirlar)});
```

şununla değiştir:

```js
    const rDK=await fetch(SB_URL+'/rest/v1/yevmiye_kalemleri',{method:'POST',headers:SB_HEADERS,body:JSON.stringify(kalemSatirlar)});
    if(!rDK.ok){
      console.error('yevmiye_kalemleri reinsert hatası:',await rDK.text());
      alert('⚠️ DİKKAT: Muhasebe fişi başlığı oluştu ama satır kalemleri yazılamadı — bu fiş EKSİK/DENGESİZ olabilir. Lütfen işlemi tekrarlayın veya muhasebe kayıtlarını kontrol edin.');
    }
```

(Not: Önce bu satırın hangi fonksiyonda olduğuna bak. Fonksiyon temiz bir "kaydet" fonksiyonuysa ve sonrasında `return` deseni varsa `return false;` de ekle; daha büyük akış içindeyse sadece uyarı bırak. Emin değilsen sadece uyarı — akışı bozma.)

- [ ] **Step 2: `muhasebe-cek-senet.html` reinsert guard**

`muhasebe-cek-senet.html`'de satır ~303'teki şu satırı:

```js
    await fetch(SB_URL+'/rest/v1/yevmiye_kalemleri',{method:'POST',headers:SB_HEADERS,body:JSON.stringify(kalemSatirlar)});
```

şununla değiştir:

```js
    const rCK=await fetch(SB_URL+'/rest/v1/yevmiye_kalemleri',{method:'POST',headers:SB_HEADERS,body:JSON.stringify(kalemSatirlar)});
    if(!rCK.ok){
      console.error('yevmiye_kalemleri reinsert hatası:',await rCK.text());
      alert('⚠️ DİKKAT: Muhasebe fişi başlığı oluştu ama satır kalemleri yazılamadı — bu fiş EKSİK/DENGESİZ olabilir. Lütfen işlemi tekrarlayın veya muhasebe kayıtlarını kontrol edin.');
    }
```

- [ ] **Step 3: Doğrulama**

```bash
grep -n "yevmiye_kalemleri reinsert hatası" muhasebe-demirbas.html muhasebe-cek-senet.html
```
Expected: her dosyada 1 eşleşme.

- [ ] **Step 4: Commit**

```bash
git add muhasebe-demirbas.html muhasebe-cek-senet.html
git commit -m "fix: demirbas + cek-senet reinsert başarısızlığında engelleyici uyarı"
```

---

### Task 5: `muhasebe-sene-sonu.html` — reinsert guard

**Files:**
- Modify: `muhasebe-sene-sonu.html` (~175)

- [ ] **Step 1: Reinsert guard ekle**

`muhasebe-sene-sonu.html`'de satır ~175'teki şu satırı:

```js
  await fetch(SB_URL+'/rest/v1/yevmiye_kalemleri',{method:'POST',headers:SB_HEADERS,body:JSON.stringify(kalemSatirlar)});
```

şununla değiştir:

```js
  const rSK=await fetch(SB_URL+'/rest/v1/yevmiye_kalemleri',{method:'POST',headers:SB_HEADERS,body:JSON.stringify(kalemSatirlar)});
  if(!rSK.ok){
    console.error('sene-sonu yevmiye_kalemleri reinsert hatası:',await rSK.text());
    alert('⚠️ DİKKAT: Sene sonu kapanış fişinin başlığı oluştu ama satır kalemleri yazılamadı — kapanış EKSİK/DENGESİZ olabilir. Muhasebe kayıtlarını kontrol edin, gerekirse kapanışı tekrarlayın.');
  }
```

(Not: bu satır daha büyük bir kapanış akışının içinde — `return` eklenmez, sadece uyarı; sonraki akış korunur.)

- [ ] **Step 2: Doğrulama**

```bash
grep -n "sene-sonu yevmiye_kalemleri reinsert hatası" muhasebe-sene-sonu.html
```
Expected: 1 eşleşme.

- [ ] **Step 3: Commit**

```bash
git add muhasebe-sene-sonu.html
git commit -m "fix: sene-sonu kapanış reinsert başarısızlığında engelleyici uyarı"
```

---

### Task 6: Uçtan uca doğrulama

**Files:** (yok — sadece doğrulama)

- [ ] **Step 1: Tutarlılık kontrolü**

```bash
grep -rn "reinsert hatası\|yazmaBasarili\|Onay kısmen başarısız" depo-siparis.html muhasebe-yevmiye.html muhasebe-faturalar.html muhasebe-demirbas.html muhasebe-cek-senet.html muhasebe-sene-sonu.html
```
Expected: depo-siparis (yazmaBasarili + Onay kısmen başarısız); 5 muhasebe dosyasında toplam 6 reinsert-hata guard'ı (faturalar'da 2).

- [ ] **Step 2: Kullanıcıya manuel test adımlarını bildir**

Node/Python yok. Kullanıcının tarayıcıda doğrulaması gereken akış:
1. **Normal akış (regresyon yok):** Bir yevmiye fişi, bir fatura, bir demirbaş, bir çek/senet kaydet → hepsi eskisi gibi "kaydedildi" göstermeli, davranış değişmemeli.
2. **depo-siparis:** Bir iç talebi onayla → başarılıysa "✅ Onaylandı" görünmeli. (Başarısızlık simülasyonu zor; en azından normal akışın bozulmadığını doğrula.)
3. **Hata simülasyonu (isteğe bağlı, ileri):** Tarayıcı ağ sekmesinden bir `_kalemleri` POST'unu bilerek başarısız kıl (örn. offline) → artık sessiz geçmek yerine "⚠️ ... EKSİK/DENGESİZ" engelleyici uyarısının çıktığını doğrula.

- [ ] **Step 3: Kullanıcıdan onay al, sonra push**

```bash
git fetch
git log --oneline main..origin/main
```
Expected: paralel değişiklik var mı kontrol et, varsa bildir. Yoksa kullanıcı onayıyla `git push`.
