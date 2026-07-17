# Hareket Geçmişi Bağlam Kaybı Düzeltmesi Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `stok-takip.html`'in Hareketler sekmesinde giriş/çıkış/transfer kayıtlarının, sayfa yenilendikten sonra bile ürün adını, giriş kaynağını, çıkış nedenini ve transfer kaynak→hedef bilgisini göstermesini sağlamak.

**Architecture:** Şema değişikliği yok. `giris()`/`cikis()`/`transfer()` fonksiyonları döndürdükleri hareket nesnesine, kod tabanının zaten kullandığı desenle (mal-kabul-v2.html, depo-siparis.html) tutarlı, okunabilir bir `aciklama` metni ekler — bu zaten `saveHareket()` tarafından DB'ye yazılıyor. `renderHareketler()` bu kalıcı `aciklama`'yı öncelikli gösterecek, ürün adını da zaten yüklü `db.urunler` kataloğundan koda göre eşleştirerek çözecek şekilde güncellenir.

**Tech Stack:** Vanilla JS, tek dosya (`stok-takip.html`). Build aracı yok, test çerçevesi yok — doğrulama grep + manuel kod okuma + kullanıcının tarayıcıda uçtan uca testi (özellikle: sayfa yenilendikten SONRA kalıcılık).

## Global Constraints

- `stok_hareketleri` tablosuna YENİ KOLON eklenmez — mevcut `aciklama` (text) alanı kullanılır.
- `saveHareket()` (satır 807-814) DEĞİŞTİRİLMEZ — zaten `aciklama:h.aciklama||null` yazıyor; sadece çağıranların ürettiği nesnede `aciklama` artık dolu gelecek.
- Geçmiş (mevcut) hareket kayıtları geriye dönük doldurulmaz — sadece bu değişiklikten SONRA oluşan kayıtlar için düzelir.
- `mal-kabul-v2.html`, `gunluk-tuketim.html`, `depo-siparis.html` dosyalarına DOKUNULMAZ — onlar zaten `aciklama`'ya anlamlı metin yazıyor.

---

### Task 1: `giris()`/`cikis()`/`transfer()` — aciklama alanı ekle + transfer() kayıt hatasını düzelt

**Files:**
- Modify: `stok-takip.html:821-862`

**Interfaces:**
- Consumes: (yok — bu fonksiyonlar bağımsız, mevcut `depoAdi()` yardımcısını kullanır, satır 641)
- Produces: `giris()`/`cikis()`/`transfer()`'in döndürdüğü hareket nesnesi artık dolu bir `aciklama: string` alanı taşıyor. `transfer()`'in döndürdüğü nesne artık ayrıca `depoId: hedefDepoId` taşıyor (Task 2 ve `saveHareket()` bunu tüketir).

**Önemli bulgu (investigation sırasında tespit edildi):** `transfer()`'in döndürdüğü nesnede `depoId` alanı hiç yok (sadece `kaynakDepoId`/`hedefDepoId` var). `saveHareket(h)` ise `depo_kodu:h.depoId` yazıyor — transfer nesnesinde bu `undefined` olduğu için `JSON.stringify` bu alanı tamamen atlıyor ve Supabase `stok_hareketleri.depo_kodu` NOT NULL kısıtı yüzünden isteği `23502` hatasıyla reddediyor (curl ile doğrudan doğrulandı). Bu, `stok-takip.html`'in Transfer modalıyla yapılan HİÇBİR transferin şu ana kadar hareket geçmişine kaydolmadığı anlamına geliyor — sessizce (saveHareket kendi hatasını yutuyor, `catch(e){console.warn(e)}`). Bu task, `depoId:hedefDepoId` ekleyerek bunu da düzeltir — kod tabanındaki mevcut yerleşik kural budur (`depo-siparis.html`'in "İç Talep" transfer akışı da hareket kaydını hedef depo_kodu altında tutuyor, curl ile DB'de doğrulandı).

- [ ] **Step 1: `giris()`'e aciklama ekle**

`stok-takip.html:821-829`'daki mevcut kod:

```js
function giris(depoId,lnKod,urunAd,miktar,birim,kaynak,kaynakId){
  ensureDepoStok(depoId);
  const s=db.stok[depoId];
  if(!s[lnKod])s[lnKod]={lnKod,urunAd,miktar:0,birim,sonGuncelleme:Date.now()};
  s[lnKod].miktar=(parseFloat(s[lnKod].miktar)||0)+parseFloat(miktar);
  s[lnKod].sonGuncelleme=Date.now();
  s[lnKod].urunAd=urunAd;
  return {id:Date.now()+'_'+Math.random().toString(36).slice(2,5),tip:'giris',depoId,lnKod,urunAd,miktar:parseFloat(miktar),birim,tarih:Date.now(),kaynak,kaynakId,personel:currentUser?.ad||'—'};
}
```

Şununla değiştir:

```js
function giris(depoId,lnKod,urunAd,miktar,birim,kaynak,kaynakId){
  ensureDepoStok(depoId);
  const s=db.stok[depoId];
  if(!s[lnKod])s[lnKod]={lnKod,urunAd,miktar:0,birim,sonGuncelleme:Date.now()};
  s[lnKod].miktar=(parseFloat(s[lnKod].miktar)||0)+parseFloat(miktar);
  s[lnKod].sonGuncelleme=Date.now();
  s[lnKod].urunAd=urunAd;
  return {id:Date.now()+'_'+Math.random().toString(36).slice(2,5),tip:'giris',depoId,lnKod,urunAd,miktar:parseFloat(miktar),birim,tarih:Date.now(),kaynak,kaynakId,aciklama:kaynak||'',personel:currentUser?.ad||'—'};
}
```

(Tek değişiklik: dönen nesneye `aciklama:kaynak||''` eklendi.)

- [ ] **Step 2: `cikis()`'e aciklama ekle**

`stok-takip.html:831-838`'deki mevcut kod:

```js
function cikis(depoId,lnKod,urunAd,miktar,birim,neden,not){
  ensureDepoStok(depoId);
  const s=db.stok[depoId];
  if(!s[lnKod])s[lnKod]={lnKod,urunAd,miktar:0,birim,sonGuncelleme:Date.now()};
  s[lnKod].miktar=Math.max(0,(parseFloat(s[lnKod].miktar)||0)-parseFloat(miktar));
  s[lnKod].sonGuncelleme=Date.now();
  return {id:Date.now()+'_'+Math.random().toString(36).slice(2,5),tip:'cikis',depoId,lnKod,urunAd,miktar:parseFloat(miktar),birim,tarih:Date.now(),neden,not:not||'',personel:currentUser?.ad||'—'};
}
```

Şununla değiştir:

```js
function cikis(depoId,lnKod,urunAd,miktar,birim,neden,not){
  ensureDepoStok(depoId);
  const s=db.stok[depoId];
  if(!s[lnKod])s[lnKod]={lnKod,urunAd,miktar:0,birim,sonGuncelleme:Date.now()};
  s[lnKod].miktar=Math.max(0,(parseFloat(s[lnKod].miktar)||0)-parseFloat(miktar));
  s[lnKod].sonGuncelleme=Date.now();
  return {id:Date.now()+'_'+Math.random().toString(36).slice(2,5),tip:'cikis',depoId,lnKod,urunAd,miktar:parseFloat(miktar),birim,tarih:Date.now(),neden,not:not||'',aciklama:(neden||'')+(not?(' — '+not):''),personel:currentUser?.ad||'—'};
}
```

(Tek değişiklik: dönen nesneye `aciklama:(neden||'')+(not?(' — '+not):'')` eklendi.)

- [ ] **Step 3: `transfer()`'e aciklama ekle ve depoId hatasını düzelt**

`stok-takip.html:840-862`'deki mevcut kod:

```js
function transfer(kaynakDepoId,hedefDepoId,lnKod,urunAd,miktar,birim,not){
  // Kaynaktan çıkar
  ensureDepoStok(kaynakDepoId);
  const ks=db.stok[kaynakDepoId];
  if(!ks[lnKod])ks[lnKod]={lnKod,urunAd,miktar:0,birim,sonGuncelleme:Date.now()};
  ks[lnKod].miktar=Math.max(0,(parseFloat(ks[lnKod].miktar)||0)-parseFloat(miktar));
  ks[lnKod].sonGuncelleme=Date.now();
  // Hedefe ekle
  ensureDepoStok(hedefDepoId);
  const hs=db.stok[hedefDepoId];
  if(!hs[lnKod])hs[lnKod]={lnKod,urunAd,miktar:0,birim,sonGuncelleme:Date.now()};
  hs[lnKod].miktar=(parseFloat(hs[lnKod].miktar)||0)+parseFloat(miktar);
  hs[lnKod].sonGuncelleme=Date.now();
  const baseId=Date.now()+'_'+Math.random().toString(36).slice(2,5);
  const kaynakDepoAd=depoAdi(kaynakDepoId);
  const hedefDepoAd=depoAdi(hedefDepoId);
  return {
    id:baseId,tip:'transfer',
    kaynakDepoId,kaynakDepoAd,hedefDepoId,hedefDepoAd,
    lnKod,urunAd,miktar:parseFloat(miktar),birim,
    tarih:Date.now(),not:not||'',personel:currentUser?.ad||'—'
  };
}
```

Şununla değiştir:

```js
function transfer(kaynakDepoId,hedefDepoId,lnKod,urunAd,miktar,birim,not){
  // Kaynaktan çıkar
  ensureDepoStok(kaynakDepoId);
  const ks=db.stok[kaynakDepoId];
  if(!ks[lnKod])ks[lnKod]={lnKod,urunAd,miktar:0,birim,sonGuncelleme:Date.now()};
  ks[lnKod].miktar=Math.max(0,(parseFloat(ks[lnKod].miktar)||0)-parseFloat(miktar));
  ks[lnKod].sonGuncelleme=Date.now();
  // Hedefe ekle
  ensureDepoStok(hedefDepoId);
  const hs=db.stok[hedefDepoId];
  if(!hs[lnKod])hs[lnKod]={lnKod,urunAd,miktar:0,birim,sonGuncelleme:Date.now()};
  hs[lnKod].miktar=(parseFloat(hs[lnKod].miktar)||0)+parseFloat(miktar);
  hs[lnKod].sonGuncelleme=Date.now();
  const baseId=Date.now()+'_'+Math.random().toString(36).slice(2,5);
  const kaynakDepoAd=depoAdi(kaynakDepoId);
  const hedefDepoAd=depoAdi(hedefDepoId);
  return {
    id:baseId,tip:'transfer',depoId:hedefDepoId,
    kaynakDepoId,kaynakDepoAd,hedefDepoId,hedefDepoAd,
    lnKod,urunAd,miktar:parseFloat(miktar),birim,
    tarih:Date.now(),not:not||'',aciklama:kaynakDepoAd+' → '+hedefDepoAd+(not?(' — '+not):''),
    personel:currentUser?.ad||'—'
  };
}
```

(İki değişiklik: `depoId:hedefDepoId` eklendi — bu, `saveHareket()`'in `depo_kodu:h.depoId` satırının artık geçerli bir değer yazmasını sağlar, kayıt hatası çözülür; ve `aciklama:kaynakDepoAd+' → '+hedefDepoAd+(not?(' — '+not):'')` eklendi.)

- [ ] **Step 4: Grep ile doğrula**

Şu komutu çalıştır:

```bash
grep -n "aciklama:" stok-takip.html | grep -E "giris|cikis|transfer|kaynakDepoAd"
```

Expected: `giris()`, `cikis()`, `transfer()` fonksiyonlarının üçünde de yeni `aciklama:` satırlarının göründüğünü, ve `transfer()`'de ayrıca `depoId:hedefDepoId` satırının bulunduğunu gözle teyit et (`grep -n "depoId:hedefDepoId" stok-takip.html` ile ayrıca kontrol edilebilir).

- [ ] **Step 5: Commit**

```bash
cd "C:\Users\USER\Projects\gurok-mal-kabul"
git add stok-takip.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "fix: persist descriptive aciklama + fix transfer hareket kayıt hatası"
```

---

### Task 2: `renderHareketler()` — kalıcı aciklama ve ürün adı önceliği

**Files:**
- Modify: `stok-takip.html:1133-1188`

**Interfaces:**
- Consumes: Task 1'in ürettiği hareket nesnelerindeki `aciklama` alanı; `db.urunler` (satır 687, `{kod,ad,birim}` dizisi, zaten `loadDB()` tarafından dolduruluyor).
- Produces: (yok — bu, render fonksiyonu, başka task tarafından tüketilmiyor)

- [ ] **Step 1: Ürün adı eşleştirmesi ve aciklama önceliği ekle**

`stok-takip.html:1133-1188`'deki mevcut kod:

```js
function renderHareketler(){
  const startV=document.getElementById('har-start').value;
  const endV=document.getElementById('har-end').value;
  const start=startV?new Date(startV).getTime():0;
  const end=endV?new Date(endV+'T23:59:59').getTime():Date.now()+86400000;

  let harlar=Object.values(db.hareketler).filter(h=>{
    if(h.tarih<start||h.tarih>end)return false;
    // Aktif depo filtresi
    if(h.depoId&&h.depoId!==aktifDepoId&&h.kaynakDepoId!==aktifDepoId&&h.hedefDepoId!==aktifDepoId)return false;
    if(harFilter!=='tumu'&&h.tip!==harFilter)return false;
    return true;
  }).sort((a,b)=>b.tarih-a.tarih);

  const container=document.getElementById('hareketler-liste');
  if(!harlar.length){
    container.innerHTML=`<div class="empty-state"><div class="empty-icon">📋</div><div class="empty-text">Hareket kaydı bulunamadı</div></div>`;
    return;
  }

  // Gün bazlı grupla
  const gruplar={};
  harlar.forEach(h=>{const g=new Date(h.tarih).toLocaleDateString('tr-TR');if(!gruplar[g])gruplar[g]=[];gruplar[g].push(h);});

  container.innerHTML=Object.entries(gruplar).map(([gun,liste])=>`
    <div style="font-size:11px;font-weight:600;color:var(--gray-500);margin:10px 0 6px;text-transform:uppercase;">${gun}</div>
    <div class="card" style="padding:8px;">
      ${liste.map(h=>{
        let ikon,renk,etiket,miktar_str;
        const depoAd=depoAdi(aktifDepoId);
        if(h.tip==='transfer'){
          const giden=h.kaynakDepoId===aktifDepoId;
          ikon='🔄';renk=giden?'var(--danger)':'var(--success)';
          etiket=giden?`${depoAd} → ${h.hedefDepoAd||h.hedefDepoId}`:`${h.kaynakDepoAd||h.kaynakDepoId} → ${depoAd}`;
          miktar_str=(giden?'-':'+')+h.miktar+' '+(h.birim||'');
        }else if(h.tip==='giris'){
          ikon='⬆️';renk='var(--success)';
          etiket=`Giriş — ${h.kaynak||'—'}`;
          miktar_str='+'+h.miktar+' '+(h.birim||'');
        }else{
          ikon='⬇️';renk='var(--danger)';
          etiket=`Çıkış — ${h.neden||'—'}`;
          miktar_str='-'+h.miktar+' '+(h.birim||'');
        }
        return`<div class="har-item">
          <div class="har-icon ${h.tip}">${ikon}</div>
          <div style="flex:1;min-width:0;">
            <div style="font-size:12px;font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">${h.urunAd||h.lnKod||'—'}</div>
            <div style="font-size:11px;color:var(--gray-500);">${etiket}</div>
            <div style="font-size:10px;color:var(--gray-400);">${new Date(h.tarih).toLocaleTimeString('tr-TR',{hour:'2-digit',minute:'2-digit'})} • ${h.personel||'—'}</div>
          </div>
          <div style="font-size:13px;font-weight:700;color:${renk};flex-shrink:0;">${miktar_str}</div>
        </div>`;
      }).join('')}
    </div>`).join('');
}
```

Şununla değiştir:

```js
function renderHareketler(){
  const startV=document.getElementById('har-start').value;
  const endV=document.getElementById('har-end').value;
  const start=startV?new Date(startV).getTime():0;
  const end=endV?new Date(endV+'T23:59:59').getTime():Date.now()+86400000;

  let harlar=Object.values(db.hareketler).filter(h=>{
    if(h.tarih<start||h.tarih>end)return false;
    // Aktif depo filtresi
    if(h.depoId&&h.depoId!==aktifDepoId&&h.kaynakDepoId!==aktifDepoId&&h.hedefDepoId!==aktifDepoId)return false;
    if(harFilter!=='tumu'&&h.tip!==harFilter)return false;
    return true;
  }).sort((a,b)=>b.tarih-a.tarih);

  const container=document.getElementById('hareketler-liste');
  if(!harlar.length){
    container.innerHTML=`<div class="empty-state"><div class="empty-icon">📋</div><div class="empty-text">Hareket kaydı bulunamadı</div></div>`;
    return;
  }

  // Ürün adı eşlemesi — db.hareketler DB'den geldiğinde urunAd taşımaz, koddan çözülür
  const urunMap={};
  db.urunler.forEach(u=>{urunMap[u.kod]=u.ad;});

  // Gün bazlı grupla
  const gruplar={};
  harlar.forEach(h=>{const g=new Date(h.tarih).toLocaleDateString('tr-TR');if(!gruplar[g])gruplar[g]=[];gruplar[g].push(h);});

  container.innerHTML=Object.entries(gruplar).map(([gun,liste])=>`
    <div style="font-size:11px;font-weight:600;color:var(--gray-500);margin:10px 0 6px;text-transform:uppercase;">${gun}</div>
    <div class="card" style="padding:8px;">
      ${liste.map(h=>{
        let ikon,renk,etiket,miktar_str;
        const depoAd=depoAdi(aktifDepoId);
        if(h.tip==='transfer'){
          const giden=h.kaynakDepoId===aktifDepoId;
          ikon='🔄';renk=giden?'var(--danger)':'var(--success)';
          etiket=h.aciklama||(giden?`${depoAd} → ${h.hedefDepoAd||h.hedefDepoId}`:`${h.kaynakDepoAd||h.kaynakDepoId} → ${depoAd}`);
          miktar_str=(giden?'-':'+')+h.miktar+' '+(h.birim||'');
        }else if(h.tip==='giris'){
          ikon='⬆️';renk='var(--success)';
          etiket=`Giriş — ${h.aciklama||h.kaynak||'—'}`;
          miktar_str='+'+h.miktar+' '+(h.birim||'');
        }else{
          ikon='⬇️';renk='var(--danger)';
          etiket=`Çıkış — ${h.aciklama||h.neden||'—'}`;
          miktar_str='-'+h.miktar+' '+(h.birim||'');
        }
        return`<div class="har-item">
          <div class="har-icon ${h.tip}">${ikon}</div>
          <div style="flex:1;min-width:0;">
            <div style="font-size:12px;font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">${h.urunAd||urunMap[h.lnKod]||h.lnKod||'—'}</div>
            <div style="font-size:11px;color:var(--gray-500);">${etiket}</div>
            <div style="font-size:10px;color:var(--gray-400);">${new Date(h.tarih).toLocaleTimeString('tr-TR',{hour:'2-digit',minute:'2-digit'})} • ${h.personel||'—'}</div>
          </div>
          <div style="font-size:13px;font-weight:700;color:${renk};flex-shrink:0;">${miktar_str}</div>
        </div>`;
      }).join('')}
    </div>`).join('');
}
```

(Üç değişiklik: `urunMap` kuruldu; `${h.urunAd||h.lnKod||'—'}` → `${h.urunAd||urunMap[h.lnKod]||h.lnKod||'—'}`; her üç `etiket=` satırı artık `h.aciklama`'yı önce deniyor.)

- [ ] **Step 2: Grep ile doğrula**

```bash
grep -n "urunMap\[h.lnKod\]" stok-takip.html
grep -n "h.aciklama||h.kaynak\|h.aciklama||h.neden\|h.aciklama||(giden" stok-takip.html
```

Expected: her iki komut da eşleşme döndürmeli (sırasıyla ürün adı satırı ve üç etiket satırı).

- [ ] **Step 3: Commit**

```bash
cd "C:\Users\USER\Projects\gurok-mal-kabul"
git add stok-takip.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "fix: renderHareketler kalıcı aciklama ve ürün adı öncelikli göstersin"
```

---

### Task 3: Uçtan uca doğrulama

**Files:** (yok — sadece doğrulama)

- [ ] **Step 1: Statik doğrulama**

Task 1 ve Task 2'nin grep adımlarının ikisinin de temiz geçtiğini, `saveHareket()`'in (satır 807-814) DEĞİŞMEDİĞİNİ (`git diff` ile) teyit et.

- [ ] **Step 2: Bilinen kapsam sınırını not et**

`stok_hareketleri` tablosunda transfer için tek `depo_kodu` kolonu var (kaynak/hedef ayrı kolon değil) — bu, transfer kaydının sadece HEDEF depo altında saklandığı, kaynak depo tarafında (o depo tabından bakıldığında) sayfa yenilendikten sonra görünmeyeceği anlamına gelir. Bu, `depo-siparis.html`'in İç Talep akışıyla birebir aynı, kod tabanının önceden var olan davranışı — bu plan bunu değiştirmiyor, sadece stok-takip.html'in transfer modalını bu davranışa kavuşturuyor (önceden hiç kaydolmuyordu).

- [ ] **Step 3: Kullanıcıya manuel test adımlarını bildir**

Kullanıcının tarayıcıda doğrulaması gereken akış:
1. Bir ürüne **Giriş** yap, kaynak alanını doldur → Hareketler sekmesinde ürün adı ve girdiğin kaynak görünmeli.
2. Bir ürüne **Çıkış** yap, neden seç → Hareketler sekmesinde ürün adı ve neden görünmeli.
3. Bir **Transfer** yap (kaynak→hedef depo) → hata almadan tamamlanmalı, Hareketler sekmesinde (hedef depo tabındayken) "Kaynak → Hedef" formatında görünmeli.
4. **Sayfayı yenile (F5)** → yukarıdaki üç kayıt hâlâ aynı detaylarla (ürün adı, kaynak/neden/kaynak→hedef) görünmeli — bu, bug'ın asıl kanıtı.
5. Herhangi bir hata/eksik görülürse bildir.

- [ ] **Step 4: Kullanıcıdan onay al**

"Test ettim, çalışıyor" onayını bekle, ardından push kararını sor.
