# Atomik Stok Güncelleme (RPC) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Kod tabanındaki tüm 7 stok-yazma noktasını, race condition'lı "GET→hesapla→mutlak POST" deseninden, sunucu tarafında atomik `miktar += delta` yapan iki Supabase RPC'sine (`stok_ekle`, `stok_transfer`) geçirmek.

**Architecture:** İki Postgres RPC fonksiyonu oluşturulur. `stok_ekle` atomik upsert-increment yapıp yeni miktarı döndürür; `stok_transfer` düş+ekle'yi tek transaction'da yapar. Her HTML dosyasındaki stok-yazma kodu, mutlak-değer upsert yerine RPC çağıracak şekilde değiştirilir; helper her dosyaya ayrı uyarlanır (kod tabanının mevcut deseni — paylaşılan modül yok).

**Tech Stack:** Vanilla JS, Supabase Postgres RPC (kullanıcı SQL editöründe çalıştırır) + PostgREST `POST /rest/v1/rpc/<fn>`. Build aracı yok, test çerçevesi yok — doğrulama grep + manuel kod okuma + kullanıcının tarayıcıda uçtan uca testi.

## Global Constraints

- RPC 1: `stok_ekle(p_urun_kodu text, p_depo_kodu text, p_otel_id text, p_delta numeric) returns numeric` — `insert ... on conflict (urun_kodu,depo_kodu) do update set miktar = greatest(0, stok.miktar + p_delta)`, yeni miktarı döndürür.
- RPC 2: `stok_transfer(p_urun_kodu text, p_kaynak_depo text, p_hedef_depo text, p_hedef_otel text, p_miktar numeric) returns void` — kaynaktan `greatest(0, miktar - p_miktar)`, hedefe atomik ekleme; tek plpgsql fonksiyonu = tek transaction.
- Negatif stok davranışı korunur: `greatest(0, ...)` (mevcut `Math.max(0, ...)` ile aynı).
- `on_conflict` anahtarı `urun_kodu,depo_kodu` — mevcut upsert anahtarıyla aynı.
- `p_delta` pozitif = giriş, negatif = çıkış. RPC çağrı gövdesindeki parametre adları fonksiyon argüman adlarıyla BİREBİR aynı olmalı (PostgREST kuralı): `p_urun_kodu, p_depo_kodu, p_otel_id, p_delta` / `p_urun_kodu, p_kaynak_depo, p_hedef_depo, p_hedef_otel, p_miktar`.
- `stok_hareketleri` (hareket geçmişi) INSERT'leri DEĞİŞMEZ — append-only, race'e tabi değil.
- Bu iş SADECE race condition'ı çözer. Kapsamlı hata-yönetimi UX'i (her çağrı noktasında kullanıcıya görünür uyarı) ayrı bir sonraki iştir; bu işte her nokta MEVCUT hata davranışını korur (stokaIsle'nin `hatalar[]`/`alert`'i, gunluk-tuketim'in catch/toast'ı, saveStok'un `console.warn`'ı).
- Migrasyon sonrası hiçbir dosyada `POST /rest/v1/stok?on_conflict` mutlak-değer yazımı KALMAMALI (sadece `rpc/stok_ekle` ve `rpc/stok_transfer`).

---

### Task 1: Supabase RPC fonksiyonları

**Files:** (yok — SQL, kullanıcı Supabase SQL editöründe çalıştırır)

- [ ] **Step 1: SQL'i kullanıcıya ver**

```sql
create or replace function stok_ekle(
  p_urun_kodu text,
  p_depo_kodu text,
  p_otel_id text,
  p_delta numeric
) returns numeric
language plpgsql
as $$
declare
  v_yeni numeric;
begin
  insert into stok (urun_kodu, depo_kodu, otel_id, miktar)
  values (p_urun_kodu, p_depo_kodu, p_otel_id, greatest(0, p_delta))
  on conflict (urun_kodu, depo_kodu)
  do update set miktar = greatest(0, stok.miktar + p_delta)
  returning miktar into v_yeni;
  return v_yeni;
end;
$$;

create or replace function stok_transfer(
  p_urun_kodu text,
  p_kaynak_depo text,
  p_hedef_depo text,
  p_hedef_otel text,
  p_miktar numeric
) returns void
language plpgsql
as $$
begin
  update stok set miktar = greatest(0, miktar - p_miktar)
    where urun_kodu = p_urun_kodu and depo_kodu = p_kaynak_depo;
  insert into stok (urun_kodu, depo_kodu, otel_id, miktar)
    values (p_urun_kodu, p_hedef_depo, p_hedef_otel, p_miktar)
    on conflict (urun_kodu, depo_kodu)
    do update set miktar = greatest(0, stok.miktar + p_miktar);
end;
$$;
```

- [ ] **Step 2: Kullanıcıdan onay al**

"Çalıştı" onayını bekle. Onaysız Task 2'ye geçme.

---

### Task 2: `mal-kabul-v2.html` — stokaIsle + stoktanGeriAl

**Files:**
- Modify: `mal-kabul-v2.html` (`stokaIsle` ~1318-1357, `stoktanGeriAl` ~1193-1218)

**Interfaces:**
- Consumes: `stok_ekle` RPC (Task 1). Mevcut `SB_URL`, `SB_HEADERS`.
- Produces: (yok — bu fonksiyonlar başka task tarafından tüketilmiyor)

- [ ] **Step 1: `stokaIsle` içindeki GET+hesapla+POST bloğunu RPC ile değiştir**

`mal-kabul-v2.html`'de şu bloğu (satır ~1327-1342):

```js
    let mevcut=0;
    try{
      const r=await fetch(SB_URL+`/rest/v1/stok?urun_kodu=eq.${encodeURIComponent(u.kod)}&depo_kodu=eq.${encodeURIComponent(depoKompozit)}&select=miktar`,{headers:SB_HEADERS});
      if(r.ok){const rows=await r.json();if(rows[0])mevcut=parseFloat(rows[0].miktar)||0;}
    }catch(e){}
    const yeniMiktar=mevcut+miktar;
    const rStok=await fetch(SB_URL+'/rest/v1/stok?on_conflict=urun_kodu,depo_kodu',{
      method:'POST',headers:{...SB_HEADERS,'Prefer':'resolution=merge-duplicates'},
      body:JSON.stringify({urun_kodu:u.kod,depo_kodu:depoKompozit,otel_id:otelId,miktar:yeniMiktar})
    });
    if(!rStok.ok){
      const hataMetni=await rStok.text();
      console.error('stok POST hatası:',hataMetni);
      hatalar.push(`${u.ad}: ${hataMetni}`);
      continue; // bu ürün için hareket kaydı da atma, stok yazılmadıysa tutarsız olur
    }
```

şununla değiştir:

```js
    // Atomik stok girişi (rpc/stok_ekle) — yarış durumu yok, GET+hesapla+POST kalktı
    const rStok=await fetch(SB_URL+'/rest/v1/rpc/stok_ekle',{
      method:'POST',headers:SB_HEADERS,
      body:JSON.stringify({p_urun_kodu:u.kod,p_depo_kodu:depoKompozit,p_otel_id:otelId,p_delta:miktar})
    });
    if(!rStok.ok){
      const hataMetni=await rStok.text();
      console.error('stok_ekle RPC hatası:',hataMetni);
      hatalar.push(`${u.ad}: ${hataMetni}`);
      continue; // bu ürün için hareket kaydı da atma, stok yazılmadıysa tutarsız olur
    }
```

- [ ] **Step 2: `stoktanGeriAl` içindeki GET+hesapla+POST bloğunu RPC ile değiştir**

`mal-kabul-v2.html`'de şu bloğu (satır ~1201-1211):

```js
    let mevcut=0;
    try{
      const r=await fetch(SB_URL+`/rest/v1/stok?urun_kodu=eq.${encodeURIComponent(u.kod)}&depo_kodu=eq.${encodeURIComponent(depoKompozit)}&select=miktar`,{headers:SB_HEADERS});
      if(r.ok){const rows=await r.json();if(rows[0])mevcut=parseFloat(rows[0].miktar)||0;}
    }catch(e){}
    const yeniMiktar=Math.max(0,mevcut-miktar);
    try{
      await fetch(SB_URL+'/rest/v1/stok?on_conflict=urun_kodu,depo_kodu',{
        method:'POST',headers:{...SB_HEADERS,'Prefer':'resolution=merge-duplicates'},
        body:JSON.stringify({urun_kodu:u.kod,depo_kodu:depoKompozit,otel_id:otelId,miktar:yeniMiktar})
      });
```

şununla değiştir:

```js
    try{
      // Atomik stok düşümü (rpc/stok_ekle, negatif delta)
      await fetch(SB_URL+'/rest/v1/rpc/stok_ekle',{
        method:'POST',headers:SB_HEADERS,
        body:JSON.stringify({p_urun_kodu:u.kod,p_depo_kodu:depoKompozit,p_otel_id:otelId,p_delta:-miktar})
      });
```

(Not: sonraki `await fetch(.../stok_hareketleri...)` satırı ve `}catch(e){console.warn('stoktanGeriAl hatası:',e);}` DEĞİŞMEZ.)

- [ ] **Step 3: Doğrulama**

```bash
grep -n "rest/v1/stok?on_conflict\|rpc/stok_ekle" mal-kabul-v2.html
```
Expected: `stok?on_conflict` için 0 eşleşme, `rpc/stok_ekle` için 2 eşleşme.

- [ ] **Step 4: Commit**

```bash
git add mal-kabul-v2.html
git commit -m "refactor: mal-kabul-v2 stok yazımını atomik stok_ekle RPC'sine geçir"
```

---

### Task 3: `gunluk-tuketim.html` — tuketimKaydet + tuketKaydet

**Files:**
- Modify: `gunluk-tuketim.html` (`tuketimKaydet` ~300-342, `tuketKaydet` ~652-694)

**Interfaces:**
- Consumes: `stok_ekle` RPC (Task 1).

- [ ] **Step 1: `tuketimKaydet` içindeki canlı-GET+hesapla+POST bloğunu RPC ile değiştir**

`gunluk-tuketim.html`'de şu bloğu (satır ~320-331):

```js
      // Önbellekteki (DB.stok) miktar bayat olabilir — yazmadan hemen önce canlı değeri
      // tazele, aksi halde eşzamanlı iki tüketim girişi birbirinin düşüşünü sessizce siler.
      let mevcut=u.miktar;
      try{
        const rTaze=await fetch(SB_URL+`/rest/v1/stok?depo_kodu=eq.${encodeURIComponent(depoId)}&urun_kodu=eq.${encodeURIComponent(u.kod)}&select=miktar`,{headers:SB_HEADERS});
        if(rTaze.ok){const rows=await rTaze.json();if(rows[0])mevcut=parseFloat(rows[0].miktar)||0;}
      }catch(e){}
      const yeniMiktar=Math.max(0,mevcut-miktar);
      await fetch(SB_URL+'/rest/v1/stok?on_conflict=urun_kodu,depo_kodu',{
        method:'POST',headers:{...SB_HEADERS,'Prefer':'resolution=merge-duplicates'},
        body:JSON.stringify({urun_kodu:u.kod,depo_kodu:depoId,otel_id:otelId,miktar:yeniMiktar})
      });
```

şununla değiştir:

```js
      // Atomik stok düşümü (rpc/stok_ekle, negatif delta) — yarış durumu yok
      const rStok=await fetch(SB_URL+'/rest/v1/rpc/stok_ekle',{
        method:'POST',headers:SB_HEADERS,
        body:JSON.stringify({p_urun_kodu:u.kod,p_depo_kodu:depoId,p_otel_id:otelId,p_delta:-miktar})
      });
      const yeniMiktar=rStok.ok?(parseFloat(await rStok.json())||0):Math.max(0,u.miktar-miktar);
```

(Not: sonraki `stok_hareketleri` POST'u ve `u.miktar=yeniMiktar;u.giris='';` satırları DEĞİŞMEZ — `yeniMiktar` artık RPC'nin döndürdüğü gerçek değer.)

- [ ] **Step 2: `tuketKaydet` içindeki canlı-GET+hesapla+POST bloğunu RPC ile değiştir**

`gunluk-tuketim.html`'de şu bloğu (satır ~663-673):

```js
      // Önbellekteki (DB.stok) miktar bayat olabilir — yazmadan hemen önce canlı değeri tazele.
      let mevcut=parseFloat(DB.stok?.[k.kod]?.miktar)||0;
      try{
        const rTaze=await fetch(SB_URL+`/rest/v1/stok?depo_kodu=eq.${encodeURIComponent(depoId)}&urun_kodu=eq.${encodeURIComponent(k.kod)}&select=miktar`,{headers:SB_HEADERS});
        if(rTaze.ok){const rows=await rTaze.json();if(rows[0])mevcut=parseFloat(rows[0].miktar)||0;}
      }catch(e){}
      const yeniMiktar=Math.max(0,mevcut-gerekli);
      await fetch(SB_URL+'/rest/v1/stok?on_conflict=urun_kodu,depo_kodu',{
        method:'POST',headers:{...SB_HEADERS,'Prefer':'resolution=merge-duplicates'},
        body:JSON.stringify({urun_kodu:k.kod,depo_kodu:depoId,otel_id:otelId,miktar:yeniMiktar})
      });
```

şununla değiştir:

```js
      // Atomik stok düşümü (rpc/stok_ekle, negatif delta) — yarış durumu yok
      const rStok=await fetch(SB_URL+'/rest/v1/rpc/stok_ekle',{
        method:'POST',headers:SB_HEADERS,
        body:JSON.stringify({p_urun_kodu:k.kod,p_depo_kodu:depoId,p_otel_id:otelId,p_delta:-gerekli})
      });
      const yeniMiktar=rStok.ok?(parseFloat(await rStok.json())||0):Math.max(0,(parseFloat(DB.stok?.[k.kod]?.miktar)||0)-gerekli);
```

(Not: sonraki `stok_hareketleri` POST'u ve `if(DB.stok[k.kod])DB.stok[k.kod].miktar=yeniMiktar;` satırı DEĞİŞMEZ.)

- [ ] **Step 3: Doğrulama**

```bash
grep -n "rest/v1/stok?on_conflict\|rpc/stok_ekle" gunluk-tuketim.html
```
Expected: `stok?on_conflict` için 0 eşleşme, `rpc/stok_ekle` için 2 eşleşme.

- [ ] **Step 4: Commit**

```bash
git add gunluk-tuketim.html
git commit -m "refactor: gunluk-tuketim stok yazımını atomik stok_ekle RPC'sine geçir"
```

---

### Task 4: `stok-takip.html` — saveStok yeniden yazımı + çağrı noktaları + güvenlik ağı

**Files:**
- Modify: `stok-takip.html` (`saveStok` ~776-795, çağrı noktaları 867/1363/1404/1469/1644/1950, `malKabulOnayKontrolEt` ~2138-2146)

**Interfaces:**
- Consumes: `stok_ekle` + `stok_transfer` RPC (Task 1). Mevcut `giris()/cikis()/transfer()` hareket nesneleri (`{tip, depoId|kaynakDepoId|hedefDepoId, lnKod, miktar}`), `otelFromDepoId()`.
- Produces: yeni `saveStok(harekets)` imzası — artık hareket NESNELERİ alır (eski `[{depoId,kod}]` değil), delta'yı `tip`+`miktar`'dan türetir.

- [ ] **Step 1: `saveStok`'u RPC tabanlı yeniden yaz**

`stok-takip.html`'de mevcut `saveStok` fonksiyonunu (satır 776-795, `async function saveStok(hedefler){` ile başlayıp `}` ile biten blok) tamamen şununla değiştir:

```js
async function saveStok(harekets){
  // harekets: giris/cikis/transfer hareket nesneleri.
  // giris/cikis → rpc/stok_ekle (delta), transfer → rpc/stok_transfer (iki bacak tek transaction).
  // rpc/stok_ekle yeni gerçek miktarı döndürür → db.stok o değere set edilir (bayat kalmaz).
  for(const h of (harekets||[])){
    try{
      if(h.tip==='transfer'){
        const r=await fetch(SB_URL+'/rest/v1/rpc/stok_transfer',{
          method:'POST',headers:SB_HEADERS,
          body:JSON.stringify({p_urun_kodu:h.lnKod,p_kaynak_depo:h.kaynakDepoId,p_hedef_depo:h.hedefDepoId,p_hedef_otel:otelFromDepoId(h.hedefDepoId),p_miktar:h.miktar})
        });
        if(!r.ok)console.warn('stok_transfer RPC hatası',await r.text());
        // transfer() önbelleği (db.stok) zaten güncelledi; RPC void döner.
      }else{
        const delta=h.tip==='giris'?h.miktar:-h.miktar;
        const r=await fetch(SB_URL+'/rest/v1/rpc/stok_ekle',{
          method:'POST',headers:SB_HEADERS,
          body:JSON.stringify({p_urun_kodu:h.lnKod,p_depo_kodu:h.depoId,p_otel_id:otelFromDepoId(h.depoId),p_delta:delta})
        });
        if(r.ok){
          const yeni=parseFloat(await r.json())||0;
          if(db.stok[h.depoId]&&db.stok[h.depoId][h.lnKod])db.stok[h.depoId][h.lnKod].miktar=yeni;
        }else console.warn('stok_ekle RPC hatası',await r.text());
      }
    }catch(e){console.warn('saveStok RPC hatası',e);}
  }
}
```

- [ ] **Step 2: 6 çağrı noktasını yeni imzaya çevir**

Aşağıdaki 6 satırı sırasıyla değiştir (her biri `saveStok`'a artık hareket nesnesi/nesneleri geçirecek):

`stok-takip.html:867` — mevcut:
```js
  await saveStok(hareketler.map(h=>({depoId:h.depoId,kod:h.lnKod})));
```
yeni:
```js
  await saveStok(hareketler);
```

`stok-takip.html:1363` — mevcut:
```js
  await saveStok([{depoId,kod}]);await saveHareket(h);
```
yeni:
```js
  await saveStok([h]);await saveHareket(h);
```

`stok-takip.html:1404` — mevcut:
```js
  await saveStok([{depoId:kaynakDepoId,kod},{depoId:hedefDepoId,kod}]);await saveHareket(h);
```
yeni:
```js
  await saveStok([h]);await saveHareket(h);
```

`stok-takip.html:1469` — mevcut:
```js
  await saveStok(harlar.map(h=>({depoId:h.depoId,kod:h.lnKod})));for(const h of harlar)await saveHareket(h);
```
yeni:
```js
  await saveStok(harlar);for(const h of harlar)await saveHareket(h);
```

`stok-takip.html:1644` — mevcut:
```js
  await saveStok(hareketler.map(h=>({depoId:h.depoId,kod:h.lnKod})));
```
yeni:
```js
  await saveStok(hareketler);
```

`stok-takip.html:1950` (sayimOnayla içinde) — mevcut:
```js
      await saveStok(hareketler.map(h=>({depoId:h.depoId,kod:h.lnKod})));
```
yeni:
```js
      await saveStok(hareketler);
```

- [ ] **Step 3: Güvenlik ağı `malKabulOnayKontrolEt`'i RPC'ye çevir**

`stok-takip.html`'de şu bloğu (satır ~2138-2146):

```js
        let mevcut=0;
        try{
          const rr=await fetch(SB_URL+`/rest/v1/stok?urun_kodu=eq.${encodeURIComponent(u.urun_kodu)}&depo_kodu=eq.${encodeURIComponent(depoKompozit)}&select=miktar`,{headers:SB_HEADERS});
          if(rr.ok){const rows2=await rr.json();if(rows2[0])mevcut=parseFloat(rows2[0].miktar)||0;}
        }catch(e){}
        await fetch(SB_URL+'/rest/v1/stok?on_conflict=urun_kodu,depo_kodu',{
          method:'POST',headers:{...SB_HEADERS,'Prefer':'resolution=merge-duplicates'},
          body:JSON.stringify({urun_kodu:u.urun_kodu,depo_kodu:depoKompozit,otel_id:otelId,miktar:mevcut+miktar})
        });
```

şununla değiştir:

```js
        // Atomik stok girişi (rpc/stok_ekle)
        await fetch(SB_URL+'/rest/v1/rpc/stok_ekle',{
          method:'POST',headers:SB_HEADERS,
          body:JSON.stringify({p_urun_kodu:u.urun_kodu,p_depo_kodu:depoKompozit,p_otel_id:otelId,p_delta:miktar})
        });
```

(Not: sonraki `stok_hareketleri` POST'u ve `mal_kabuller ... PATCH stok_islendi:true` DEĞİŞMEZ.)

- [ ] **Step 4: Doğrulama**

```bash
grep -n "rest/v1/stok?on_conflict\|rpc/stok_ekle\|rpc/stok_transfer\|saveStok(" stok-takip.html
```
Expected: `stok?on_conflict` için 0 eşleşme; `saveStok(` çağrıları hareket nesnesi/dizisi geçiyor (`.map(h=>({depoId` kalmamış); `rpc/stok_ekle` (saveStok içi 1 + safety-net 1 = 2) ve `rpc/stok_transfer` (saveStok içi 1) mevcut.

- [ ] **Step 5: Commit**

```bash
git add stok-takip.html
git commit -m "refactor: stok-takip saveStok'u atomik stok_ekle/stok_transfer RPC'lerine geçir"
```

---

### Task 5: `depo-siparis.html` — transfer onayla

**Files:**
- Modify: `depo-siparis.html` (`onayla` içindeki iki `saveStok` çağrısı ~951-952)

**Interfaces:**
- Consumes: `stok_transfer` RPC (Task 1). Mevcut `transfer()` hareket nesneleri (`harlar[]`, her biri `{tip:'transfer', lnKod, kaynakDepoId, hedefDepoId, miktar}`), `otelFromDepoId()`.

- [ ] **Step 1: `onayla` içindeki iki whole-depot saveStok çağrısını RPC transfer döngüsüyle değiştir**

`depo-siparis.html`'de şu iki satırı (satır ~951-952):

```js
    await saveStok(merkeziDepoId,DB.stok[merkeziDepoId]||{});
    await saveStok(hedefDepoId,DB.stok[hedefDepoId]||{});
```

şununla değiştir:

```js
    // Atomik transfer (rpc/stok_transfer) — her ürün için düş+ekle tek transaction'da.
    // Eski whole-depot saveStok'u tam-tablo clobber riski taşıyordu; kaldırıldı.
    for(const h of harlar){
      try{
        const rT=await fetch(SB_URL+'/rest/v1/rpc/stok_transfer',{
          method:'POST',headers:SB_HEADERS,
          body:JSON.stringify({p_urun_kodu:h.lnKod,p_kaynak_depo:h.kaynakDepoId,p_hedef_depo:h.hedefDepoId,p_hedef_otel:otelFromDepoId(h.hedefDepoId),p_miktar:h.miktar})
        });
        if(!rT.ok)console.warn('stok_transfer RPC hatası',await rT.text());
      }catch(e){console.warn('stok_transfer RPC hatası',e);}
    }
```

(Not: `transfer()` çağrıları `DB.stok` önbelleğini zaten güncelledi — ekrandaki değerler doğru kalır. Eski `saveStok(depoId,stokObj)` fonksiyonu artık kullanılmıyor ama kaldırılmasına gerek yok, dokunma.)

- [ ] **Step 2: Doğrulama**

```bash
grep -n "rest/v1/stok?on_conflict\|rpc/stok_transfer\|saveStok(" depo-siparis.html
```
Expected: `onayla` içinde artık `rpc/stok_transfer` var; `onayla`'daki iki whole-depot `saveStok(` çağrısı kalktı. (`saveStok` fonksiyon TANIMI hala durabilir — kullanılmıyor; onu saymıyoruz.) `stok?on_conflict` sadece kullanılmayan `saveStok` tanımında kalabilir — o satır ölü kod, sorun değil; başka aktif çağrı olmamalı.

- [ ] **Step 3: Commit**

```bash
git add depo-siparis.html
git commit -m "refactor: depo-siparis transferini atomik stok_transfer RPC'sine geçir"
```

---

### Task 6: Uçtan uca doğrulama

**Files:** (yok — sadece doğrulama)

- [ ] **Step 1: Tüm kod tabanında tutarlılık kontrolü**

```bash
grep -rn "rest/v1/stok?on_conflict" mal-kabul-v2.html gunluk-tuketim.html stok-takip.html depo-siparis.html
```
Expected: SADECE `depo-siparis.html`'deki kullanılmayan `saveStok` tanımında kalan 1 satır (ölü kod) olabilir; başka HİÇBİR aktif yazma noktası kalmamalı. (İstenirse o ölü satır da bir sonraki temizlikte kaldırılabilir.)

```bash
grep -rn "rpc/stok_ekle\|rpc/stok_transfer" mal-kabul-v2.html gunluk-tuketim.html stok-takip.html depo-siparis.html
```
Expected: mal-kabul-v2 (2 stok_ekle), gunluk-tuketim (2 stok_ekle), stok-takip (2 stok_ekle + 1 stok_transfer), depo-siparis (1 stok_transfer).

- [ ] **Step 2: Kullanıcıya manuel test adımlarını bildir**

Node/Python yok, otomatik test yazılamıyor. Kullanıcının tarayıcıda doğrulaması gereken akış:
1. **Mal kabul girişi:** Bir mal kabulü kalite onayından geçir → ilgili ürünün stoğunun doğru arttığını `stok-takip.html`'de gör.
2. **Manuel çıkış:** `stok-takip.html`'den bir ürün çıkışı yap → stoğun doğru azaldığını gör.
3. **Transfer:** İki depo arası transfer yap → kaynağın azaldığını, hedefin arttığını, ikisinin de tutarlı olduğunu gör.
4. **Depo iç talep onayı:** `depo-siparis.html`'de bir talebi onayla → merkezi depodan düşüp talep eden departmana eklendiğini gör.
5. **Günlük tüketim + reçete tüketimi:** `gunluk-tuketim.html`'de tüketim gir → stoğun doğru azaldığını gör.
6. **Sayım onayı:** Bir fiziksel sayımı cost_control ile onayla → stoğun sayılan değere geldiğini gör (bu akış en hassası, özellikle test et).
7. **Eşzamanlılık (mümkünse):** Aynı ürün için iki sekmede arka arkaya hızlı işlem yap → ikisinin de uygulandığını (biri diğerini ezmediğini) gör.

- [ ] **Step 3: Kullanıcıdan onay al, sonra push**

```bash
git fetch
git log --oneline main..origin/main
```
Expected: paralel değişiklik var mı kontrol et, varsa kullanıcıya bildir. Yoksa kullanıcı onayıyla `git push`.
