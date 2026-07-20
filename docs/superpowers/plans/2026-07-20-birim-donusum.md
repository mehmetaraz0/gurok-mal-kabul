# Birim Dönüşüm Sistemi Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ürün başına opsiyonel bir "büyük birim + çarpan" (örn. 1 KOLİ = 10 KG) tanımlanabilsin ve bu sadece raporlama/gösterimde kg'yi koli'ye çevirmek için kullanılsın — mal kabul girişi (gerçek ağırlık tartımı) değişmeden kalsın.

**Architecture:** Yeni, küçük, opsiyonel bir Supabase tablosu (`urun_birim_donusum`) — mevcut 1290 ürünlük statik katalog (`gurok_veritabani.js` → `URUN_DB`) değişmeden kalır. Yeni bir yönetim ekranı (`urun-yonetimi.html`) bu tabloyu düzenler. `ortak.js`'e eklenen ortak bir yardımcı (`birimDonusumEtiketi`), harita boşsa/ürün kaydı yoksa sessizce `''` döner — 5 sayfaya (stok-takip, günlük-tüketim, trend-raporlama, satın-alma-siparisoluştur, mal-kabul-liste) sadece gösterim katmanı olarak eklenir.

**Tech Stack:** Vanilla HTML/JS, Supabase REST (`fetch`), PostgreSQL RLS (`auth_yetki_var`).

## Global Constraints

- Mal kabul giriş alanları DEĞİŞMEZ — kullanıcı hep gerçek ağırlığı (kg) elle girer. Çarpan otomatik hesaplama için KULLANILMAZ.
- `URUN_DB` / `gurok_veritabani.js` / Supabase `urunler` tablosu şeması DEĞİŞMEZ.
- Yeni tablo tamamen opsiyonel satırlardan oluşur — bir üründe kayıt yoksa hiçbir sayfa davranışı değişmez (sessiz, katmanlı özellik).
- RLS deseni: `auth_yetki_var('urun_yonetimi', p_min_seviye)`, soft-delete (`silindi` sütunu, gerçek `DELETE` yok).
- Bu proje repoda `.sql` dosyası tutmuyor — şema değişiklikleri kullanıcıya fenced SQL bloğu olarak verilir, Supabase SQL editöründe çalıştırılır, kullanıcının onayından sonra curl ile doğrulanır.
- `SB_URL='https://xwytofysmgqtqjzkplfi.supabase.co'`, anon key oturumda mevcut (önceki fazlarda kullanılan).

---

## Task 1: Supabase Şeması — `urun_birim_donusum` Tablosu + RLS + Modül Seed

**Files:**
- Kullanıcıya verilecek: SQL bloğu (repo dosyası değil)
- Modify: `.superpowers/sdd/progress.md` (ilerleme kaydı)

**Interfaces:**
- Produces: `urun_birim_donusum` tablosu (`urun_kodu`, `buyuk_birim`, `carpan`, `silindi`), `urun_yonetimi` modülü (`moduller.kod='urun_yonetimi'`), `yetki_matrisi` satırları (sonraki tüm task'lar `auth_yetki_var('urun_yonetimi', ...)` ve `birimDonusumHaritasiYukle()` bunu tüketir).

- [ ] **Step 1: SQL bloğunu kullanıcıya ver**

Aşağıdaki SQL'i kullanıcıya ver, Supabase SQL editöründe çalıştırmasını iste:

```sql
-- 1) Yeni tablo — ürün başına opsiyonel büyük birim/çarpan
create table urun_birim_donusum (
  id uuid primary key default gen_random_uuid(),
  urun_kodu text not null unique,
  buyuk_birim text not null,
  carpan numeric not null check (carpan > 0),
  silindi boolean not null default false,
  guncelleme_tarihi timestamptz default now()
);

alter table urun_birim_donusum enable row level security;

create policy urun_birim_donusum_select on urun_birim_donusum
  for select using (auth_yetki_var('urun_yonetimi','goruntule'));

create policy urun_birim_donusum_insert on urun_birim_donusum
  for insert with check (auth_yetki_var('urun_yonetimi','kayit'));

create policy urun_birim_donusum_update on urun_birim_donusum
  for update using (auth_yetki_var('urun_yonetimi','kayit'))
  with check (auth_yetki_var('urun_yonetimi','kayit'));

-- 2) Yeni modül (mevcut son sira=41, bar_qr_siparis)
insert into moduller (kod, ad, sira)
values ('urun_yonetimi', 'Ürün Yönetimi (Birim Dönüşüm)', 42);

-- 3) Yetki dağılımı: stok_takip modülüyle BİREBİR aynı roller/seviyeler
-- (grup_direktor/grup_satinalma/grup_kalite/gm/mali_isler_mdr/satinalma_mdr/
--  satinalma/kalite/fb_mdr/mutfak/bar/it_admin/mutfak_vardiya/mutfak_personel/
--  bar_vardiya/bar_personel = goruntule; grup_finans/cost_control/depo/
--  depo_vardiya = kayit; cost_control_mdr/depo_sef/sistem_admin = tam;
--  muhasebe_mdr/muhasebe = yok)
insert into yetki_matrisi (rol_id, modul_id, yetki)
select rol_id, (select id from moduller where kod='urun_yonetimi'), yetki
from yetki_matrisi
where modul_id = (select id from moduller where kod='stok_takip');
```

**Not:** `urun_kodu` sütunu bilinçli olarak `urunler(kod)`'a FK ile bağlanmadı — `urunler` tablosunun `kod` sütununda UNIQUE/PK kısıtlaması olup olmadığı bu oturumdan doğrulanamadı (RLS ile korunuyor, anon SELECT boş dönüyor). `urun_birim_donusum.urun_kodu unique` kısıtlaması kendi içinde yeterli bütünlük sağlıyor — repo genelinde `urun_kodu` zaten FK'siz, serbest metin olarak kullanılıyor (örn. `stok_hareketleri.urun_kodu`).

- [ ] **Step 2: Kullanıcı onayını bekle, sonra curl ile doğrula**

Kullanıcı "çalıştı" dediğinde:

```bash
SB_URL='https://xwytofysmgqtqjzkplfi.supabase.co'
SB_KEY='eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inh3eXRvZnlzbWdxdHFqemtwbGZpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMyMjg5ODMsImV4cCI6MjA5ODgwNDk4M30.E7cRcOAvCmUFXWs45t4HE-igpmqWmSN2J66dOuvCHjA'
# Anon SELECT boş dönmeli (RLS engelliyor, tablo var — hata değil)
curl -s "$SB_URL/rest/v1/urun_birim_donusum?select=*" -H "apikey: $SB_KEY" -H "Authorization: Bearer $SB_KEY"
# Anon INSERT reddedilmeli (42501 / RLS violation)
curl -s -X POST "$SB_URL/rest/v1/urun_birim_donusum" -H "apikey: $SB_KEY" -H "Authorization: Bearer $SB_KEY" -H "Content-Type: application/json" -d '{"urun_kodu":"TEST","buyuk_birim":"KOLİ","carpan":10}'
# Yeni modül gerçekten eklendi mi
curl -s "$SB_URL/rest/v1/moduller?select=kod,ad,sira&kod=eq.urun_yonetimi" -H "apikey: $SB_KEY" -H "Authorization: Bearer $SB_KEY"
```

Beklenen: ilk çağrı `[]`, ikinci çağrı `{"code":"42501",...}` içeren bir hata, üçüncü çağrı `urun_yonetimi` modülünü döner.

- [ ] **Step 3: İlerleme kaydı**

`.superpowers/sdd/progress.md` dosyasının sonuna ekle:

```
Birim Dönüşüm Task 1 (şema): complete — urun_birim_donusum tablosu + RLS + urun_yonetimi modülü + stok_takip'ten kopyalanan yetki dağılımı, curl ile doğrulandı.
```

---

## Task 2: Yeni Ekran — `urun-yonetimi.html`

**Files:**
- Create: `urun-yonetimi.html`

**Interfaces:**
- Consumes: `requireLogin()`, `requireRole(user, izinliRoller)`, `kullaniciYetkileriGetir()` (auth-guard.js — imzalar Task açıklamasında aynen verildi), `escapeHtml(s)`, `toast(msg,d)`, `sLD()`, `hLD()` (ortak.js), global `URUN_DB` dizisi (`gurok_veritabani.js` — her öğe `{kod,ad,birim,grup,sicaklikKriter}`).
- Produces: `urun_birim_donusum` tablosuna upsert eden bağımsız bir sayfa. Sonraki task'lar bu sayfaya bağımlı değil (sadece bu tabloyu okuyorlar).

- [ ] **Step 1: Dosyayı oluştur**

```html
<!DOCTYPE html>
<html lang="tr">
<head>
<meta charset="UTF-8">
<script src="auth-guard.js"></script>
<script src="supabase-config.js"></script>
<script src="ortak.js"></script>
<script src="gurok_veritabani.js"></script>
<link rel="stylesheet" href="theme.css">
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
<title>Gürok — Ürün Birim Yönetimi</title>
<meta name="theme-color" content="#1a2744">
<style>
*{box-sizing:border-box;margin:0;padding:0;-webkit-tap-highlight-color:transparent}
html,body{height:100%;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;background:var(--gray-100)}
#app{height:100vh;display:flex;flex-direction:column;overflow:hidden}
.header{background:var(--primary);color:white;padding:12px 16px;display:flex;align-items:center;gap:8px;flex-shrink:0;min-height:56px;box-shadow:var(--shadow)}
.header h1{font-size:15px;font-weight:700;flex:1}
.header .sub{font-size:11px;opacity:.7;display:block;margin-top:1px}
.header-btn{background:rgba(255,255,255,.15);border:none;color:white;width:34px;height:34px;border-radius:50%;font-size:16px;cursor:pointer;display:flex;align-items:center;justify-content:center;flex-shrink:0}
.header-btn:active{background:rgba(255,255,255,.3)}
.uyari{background:#fff3cd;color:#856404;border-radius:10px;padding:12px 14px;margin:12px;font-size:12px;line-height:1.5;border:1.5px solid #fcd34d}
.scroll-content{flex:1;overflow-y:auto;-webkit-overflow-scrolling:touch;padding:0 12px 12px}
.scroll-content::-webkit-scrollbar{display:none}
.search-bar{padding:10px 12px;background:white;border-bottom:1px solid var(--gray-200);flex-shrink:0}
.search-bar input{width:100%;padding:10px 12px;border:1.5px solid var(--gray-300);border-radius:8px;font-size:14px;outline:none}
.urow{background:white;border-radius:var(--radius-sm);padding:12px;margin-bottom:8px;box-shadow:0 1px 4px rgba(0,0,0,.08);display:flex;align-items:center;gap:10px;flex-wrap:wrap}
.urow-ad{font-size:13px;font-weight:700;color:var(--primary)}
.urow-kod{font-size:11px;color:var(--gray-500)}
.urow-birim{font-size:11px;color:var(--gray-500)}
.urow-fields{display:flex;gap:8px;margin-left:auto;align-items:center}
.urow-fields input{width:90px;padding:7px 9px;border:1.5px solid var(--gray-300);border-radius:6px;font-size:13px;outline:none}
.urow-fields button{padding:7px 12px;border:none;border-radius:6px;font-size:12px;font-weight:600;cursor:pointer;background:var(--primary);color:white;min-height:32px}
.urow-fields button:disabled{background:var(--gray-300);cursor:not-allowed}
.es{text-align:center;padding:40px 20px;color:var(--gray-400)}.ei{font-size:48px;margin-bottom:12px}.et{font-size:14px}
#toast{position:fixed;bottom:24px;left:50%;transform:translateX(-50%) translateY(20px);background:var(--primary);color:white;padding:10px 20px;border-radius:20px;font-size:13px;z-index:9999;opacity:0;transition:all .3s;pointer-events:none;white-space:nowrap;max-width:90vw;text-align:center}
#toast.show{opacity:1;transform:translateX(-50%) translateY(0)}
#ld{display:none;position:fixed;inset:0;background:rgba(26,39,68,.85);z-index:9998;align-items:center;justify-content:center;flex-direction:column;gap:12px;color:white}
#ld.show{display:flex}
.sp{width:36px;height:36px;border:3px solid rgba(255,255,255,.3);border-top-color:white;border-radius:50%;animation:spin .8s linear infinite}
@keyframes spin{to{transform:rotate(360deg)}}
</style>
</head>
<body>

<div id="app" style="display:none">
  <div class="header">
    <button class="header-btn" onclick="location.href='stok-takip.html'"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" style="width:16px;height:16px;flex-shrink:0"><path d="M19 12H5M12 19l-7-7 7-7"/></svg></button>
    <div style="flex:1"><h1>Ürün Birim Yönetimi</h1><span class="sub" id="hsub"></span></div>
  </div>
  <div class="uyari">Sadece koli/kg gibi büyük-küçük birim ilişkisi olan ürünler için "Büyük Birim" ve "Çarpan" gir (örn. 1 KOLİ = 10 KG için Büyük Birim: KOLİ, Çarpan: 10). Bu, sadece raporlarda kg'yi koli'ye çevirmek için kullanılır — mal kabulde gerçek ağırlık girişini değiştirmez.</div>
  <div class="search-bar"><input type="text" id="arama" placeholder="Ürün kodu veya adı ara (en az 2 karakter)..." oninput="aramaYap()"></div>
  <div class="scroll-content" id="urun-liste">
    <div class="es"><div class="ei">🔍</div><div class="et">Aramaya başlamak için en az 2 karakter yaz</div></div>
  </div>
</div>

<div id="toast"></div>
<div id="ld"><div class="sp"></div><div style="font-size:13px">Yükleniyor...</div></div>

<script>
// SB_URL/SB_KEY/SB_HEADERS -> supabase-config.js
// sLD/hLD/toast/escapeHtml -> ortak.js
// URUN_DB -> gurok_veritabani.js

let CU=null;
let YETKI_HARITASI={};
let MEVCUT_DONUSUMLER={}; // {urun_kodu: {buyuk_birim, carpan}}

async function mevcutDonusumleriYukle(){
  try{
    const r=await fetch(SB_URL+'/rest/v1/urun_birim_donusum?select=urun_kodu,buyuk_birim,carpan&silindi=eq.false',{headers:SB_HEADERS});
    if(r.ok){
      MEVCUT_DONUSUMLER={};
      (await r.json()).forEach(row=>{MEVCUT_DONUSUMLER[row.urun_kodu]={buyuk_birim:row.buyuk_birim,carpan:row.carpan};});
    }
  }catch(e){}
}

function aramaYap(){
  const q=document.getElementById('arama').value.trim().toLocaleUpperCase('tr-TR');
  const el=document.getElementById('urun-liste');
  if(q.length<2){
    el.innerHTML='<div class="es"><div class="ei">🔍</div><div class="et">Aramaya başlamak için en az 2 karakter yaz</div></div>';
    return;
  }
  const sonuclar=URUN_DB.filter(u=>u.kod.toLocaleUpperCase('tr-TR').includes(q)||u.ad.toLocaleUpperCase('tr-TR').includes(q)).slice(0,50);
  if(!sonuclar.length){
    el.innerHTML='<div class="es"><div class="ei">🔍</div><div class="et">Sonuç bulunamadı</div></div>';
    return;
  }
  const kayitliMi=['kayit','tam'].includes(YETKI_HARITASI['urun_yonetimi']);
  el.innerHTML=sonuclar.map(u=>{
    const mevcut=MEVCUT_DONUSUMLER[u.kod]||{};
    return`<div class="urow" id="urow-${escapeHtml(u.kod)}">
      <div>
        <div class="urow-ad">${escapeHtml(u.ad)}</div>
        <div class="urow-kod">${escapeHtml(u.kod)} · <span class="urow-birim">${escapeHtml(u.birim)}</span></div>
      </div>
      <div class="urow-fields">
        <input type="text" id="bb-${escapeHtml(u.kod)}" placeholder="Büyük Birim" value="${escapeHtml(mevcut.buyuk_birim||'')}" ${kayitliMi?'':'disabled'}>
        <input type="number" min="0.01" step="0.01" id="cp-${escapeHtml(u.kod)}" placeholder="Çarpan" value="${mevcut.carpan||''}" ${kayitliMi?'':'disabled'}>
        <button onclick="donusumKaydet('${escapeHtml(u.kod).replace(/'/g,"\\'")}')" ${kayitliMi?'':'disabled'}>Kaydet</button>
      </div>
    </div>`;
  }).join('');
}

async function donusumKaydet(kod){
  const buyukBirim=document.getElementById('bb-'+kod).value.trim();
  const carpan=parseFloat(document.getElementById('cp-'+kod).value);
  if(!buyukBirim||!carpan||carpan<=0){toast('❌ Büyük birim ve çarpan (0\'dan büyük) gerekli');return;}
  sLD();
  try{
    const r=await fetch(SB_URL+'/rest/v1/urun_birim_donusum?on_conflict=urun_kodu',{
      method:'POST',
      headers:{...SB_HEADERS,'Prefer':'resolution=merge-duplicates'},
      body:JSON.stringify({urun_kodu:kod,buyuk_birim:buyukBirim,carpan:carpan,silindi:false})
    });
    if(!r.ok)throw new Error(await r.text());
    MEVCUT_DONUSUMLER[kod]={buyuk_birim:buyukBirim,carpan:carpan};
    toast('✅ Kaydedildi');
  }catch(e){toast('❌ Kaydedilemedi: '+e.message);}
  hLD();
}

(async function(){
  CU=requireLogin();
  if(!CU)return;
  if(!requireRole(CU,['yonetici','depo','cost_control']))return;
  document.getElementById('app').style.display='flex';
  document.getElementById('hsub').textContent=(CU.rol||'')+' '+(CU.ad||'');
  YETKI_HARITASI=await kullaniciYetkileriGetir();
  await mevcutDonusumleriYukle();
})();
</script>
</body>
</html>
```

- [ ] **Step 2: Tarayıcıda manuel doğrula**

Uygulamayı aç, `urun-yonetimi.html`'e git, giriş yap (yetkili bir rolle, örn. depo). "döner" yazıp ara, bir ürün bul, Büyük Birim="KOLİ", Çarpan="10" gir, Kaydet'e bas. Toast "✅ Kaydedildi" göstermeli. Sayfayı yenile, aynı ürünü tekrar ara — değerlerin geri geldiğini doğrula (kalıcılık testi).

Yetkisiz bir rolle (`requireRole` listesinde olmayan) giriş yapmayı dene — "Bu modül sana kapalı" ekranını görmeli.

- [ ] **Step 3: Commit**

```bash
git add urun-yonetimi.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: Ürün Birim Yönetimi ekranı eklendi (urun-yonetimi.html)"
```

---

## Task 3: `ortak.js` — `birimDonusumEtiketi()` Yardımcı Fonksiyonu

**Files:**
- Modify: `ortak.js` (mevcut 38 satır — implementasyon anında satır sayısı DEĞİŞMİŞ olabilir, dosyayı önce oku, sona ekle)

**Interfaces:**
- Produces: `let BIRIM_DONUSUM_HARITASI={}`, `async function birimDonusumHaritasiYukle()`, `function birimDonusumEtiketi(urunKodu, miktar)` → `string` (boş veya `"≈X BUYUK_BIRIM"`). Task 4-8 bunu tüketir.

- [ ] **Step 1: `ortak.js`'in GÜNCEL halini oku**

Implementasyon anında dosyayı `Read` ile aç — Task 1 planlanırken 38 satırdı, ama repo'da paralel bir oturum sürekli değişiklik yapıyor, güncel satır sayısı farklı olabilir. Aşağıdaki kodu dosyanın EN SONUNA ekle (mevcut hiçbir satırı değiştirme).

- [ ] **Step 2: Fonksiyonu ekle**

Dosya sonuna ekle:

```js

// Birim dönüşüm sistemi — ürün başına opsiyonel büyük birim/çarpan gösterimi.
// Sadece raporlama/gösterim amaçlı; mal kabul/stok giriş akışlarını etkilemez.
// Harita boşsa veya ürünün kaydı yoksa '' döner (sessiz, katmanlı özellik).
let BIRIM_DONUSUM_HARITASI={};
async function birimDonusumHaritasiYukle(){
  try{
    const r=await fetch(SB_URL+'/rest/v1/urun_birim_donusum?select=urun_kodu,buyuk_birim,carpan&silindi=eq.false',{headers:SB_HEADERS});
    if(!r.ok)return;
    (await r.json()).forEach(row=>{BIRIM_DONUSUM_HARITASI[row.urun_kodu]={buyuk_birim:row.buyuk_birim,carpan:parseFloat(row.carpan)};});
  }catch(e){}
}
function birimDonusumEtiketi(urunKodu,miktar){
  const d=BIRIM_DONUSUM_HARITASI[urunKodu];
  if(!d||!d.carpan)return'';
  const m=parseFloat(miktar)||0;
  return`≈${(m/d.carpan).toFixed(2)} ${d.buyuk_birim}`;
}
```

- [ ] **Step 3: Tarayıcı konsolunda doğrula**

Herhangi bir sayfayı aç (ör. `stok-takip.html`), tarayıcı konsolunda çalıştır:
```js
await birimDonusumHaritasiYukle();
console.log(BIRIM_DONUSUM_HARITASI);
console.log(birimDonusumEtiketi('OLMAYAN_KOD', 5)); // beklenen: ''
```
Task 2'de kaydettiğin ürün kodu haritada görünmeli, `carpan` değeri sayı olmalı.

- [ ] **Step 4: Commit**

```bash
git add ortak.js
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: ortak.js'e birimDonusumEtiketi() yardımcı fonksiyonu eklendi"
```

---

## Task 4: `stok-takip.html` Entegrasyonu + Yönetim Ekranı Linki

**Files:**
- Modify: `stok-takip.html` (implementasyon anında güncel satır numaralarını `Grep`/`Read` ile teyit et — Task 1 planlanırken render kodu satır 954-972 civarındaydı, `renderStok()` fonksiyonu, öğe değişkeni `s.lnKod`/`s.miktar`/`s.birim`)

**Interfaces:**
- Consumes: `birimDonusumHaritasiYukle()`, `birimDonusumEtiketi(kod, miktar)` (Task 3, `ortak.js`).

- [ ] **Step 1: Header'a "Ürün Yönetimi" linki ekle**

`stok-takip.html` içinde, mevcut `header-btn` butonlarının (Transfer/Çıkış) yanına, aynı desende bir buton ekle — implementasyon anında bu butonların bulunduğu satırı `Grep "header-btn"` ile bul ve hemen sonrasına ekle:

```html
<button class="header-btn" onclick="location.href='urun-yonetimi.html'" title="Ürün Birim Yönetimi"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" style="width:16px;height:16px;flex-shrink:0"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/></svg></button>
```

- [ ] **Step 2: Sayfa init akışına harita yüklemeyi ekle**

`Grep "requireRole\("` ile init IIFE'sini bul (Task 1 planlanırken satır 2175 civarındaydı). `requireRole` başarılı döndükten, ana veri yükleme fonksiyonu çağrılmadan ÖNCE şu satırı ekle:

```js
await birimDonusumHaritasiYukle();
```

- [ ] **Step 3: Render koduna etiketi ekle**

`renderStok()` fonksiyonunda, miktar gösteren satırı (`Grep "s.miktar||0"` ile bul — Task 1 planlanırken satır 965 civarındaydı) şu şekilde güncelle — MEVCUT satırı bul ve hemen altına yeni bir `div` ekle:

Eski (mevcut, referans — implementasyon anında birebir aynı olmayabilir, `Read` ile teyit et):
```js
<div style="font-size:18px;font-weight:800;color:...">${s.miktar||0} <span style="font-size:12px;font-weight:400;">${s.birim||''}</span></div>
```

Yeni (aynı satırın hemen altına eklenecek):
```js
${birimDonusumEtiketi(s.lnKod,s.miktar)?`<div style="font-size:11px;color:var(--gray-500)">${birimDonusumEtiketi(s.lnKod,s.miktar)}</div>`:''}
```

- [ ] **Step 4: Tarayıcıda doğrula**

`stok-takip.html`'i aç. Header'da yeni gear-benzeri buton görünmeli, tıklanınca `urun-yonetimi.html`'e gitmeli. Task 2'de dönüşüm tanımladığın ürünün stok satırında miktarın altında `≈X KOLİ` etiketi görünmeli. Dönüşümü olmayan bir ürünün satırında HİÇBİR ek metin görünmemeli (boş string, layout kayması yok).

- [ ] **Step 5: Commit**

```bash
git add stok-takip.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: stok-takip.html'e birim dönüşüm gösterimi ve Ürün Yönetimi linki eklendi"
```

---

## Task 5: `gunluk-tuketim.html` Entegrasyonu

**Files:**
- Modify: `gunluk-tuketim.html` (Task 1 planlanırken `renderUrunler()` fonksiyonu, "Mevcut stok" satırı satır 288 civarındaydı, öğe değişkeni `u.kod`/`u.miktar`/`meta.birim`)

**Interfaces:**
- Consumes: `birimDonusumHaritasiYukle()`, `birimDonusumEtiketi(kod, miktar)` (Task 3).

- [ ] **Step 1: Sayfa init akışına harita yüklemeyi ekle**

Sayfanın init IIFE'sinde (`requireLogin`/`requireRole` sonrası, ana veri yükleme öncesi) ekle:

```js
await birimDonusumHaritasiYukle();
```

- [ ] **Step 2: Render koduna etiketi ekle**

`renderUrunler()` içinde, `Grep "Mevcut stok:"` ile satırı bul (Task 1 planlanırken satır 288 civarındaydı):

Mevcut (referans, `Read` ile teyit et):
```js
<div class="urow-stok">Mevcut stok: ${u.miktar} ${meta.birim}</div>
```

Yeni (bu satırı şu şekilde değiştir — sonuna koşullu ek metin ekle):
```js
<div class="urow-stok">Mevcut stok: ${u.miktar} ${meta.birim}${birimDonusumEtiketi(u.kod,u.miktar)?` (${birimDonusumEtiketi(u.kod,u.miktar)})`:''}</div>
```

- [ ] **Step 3: Tarayıcıda doğrula**

`gunluk-tuketim.html`'i aç. Task 2'de dönüşüm tanımladığın ürün listede görünüyorsa, "Mevcut stok: X KG (≈Y KOLİ)" şeklinde görünmeli. Giriş alanı (input) davranışı DEĞİŞMEMELİ — hâlâ kg cinsinden elle giriliyor.

- [ ] **Step 4: Commit**

```bash
git add gunluk-tuketim.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: gunluk-tuketim.html'e birim dönüşüm gösterimi eklendi"
```

---

## Task 6: `trend-raporlama.html` Entegrasyonu

**Files:**
- Modify: `trend-raporlama.html` (satır 87-231, `renderStokTrend()` ve `renderTuketimTrend()` fonksiyonları — bu satır numaraları bu plan yazılırken dosyadan doğrudan okunarak doğrulandı, DEĞİŞMEMİŞ olmalı çünkü bu dosya son merge'lerde listede yoktu; yine de implementasyon anında `Read` ile teyit et)

**Interfaces:**
- Consumes: `birimDonusumHaritasiYukle()`, `birimDonusumEtiketi(kod, miktar)`, `round2(n)` (mevcut, `ortak.js`).

- [ ] **Step 1: Init akışına harita yüklemeyi ekle**

Dosya sonundaki init IIFE'sinde (satır 226-231), `requireRole` başarılı döndükten, `basla()` çağrılmadan ÖNCE ekle:

```js
await birimDonusumHaritasiYukle();
```

Güncel IIFE (satır 226-231, `requireRole` satırından sonra eklenecek):
```js
(async function(){
  CU = requireLogin();
  if(!CU) return;
  if(!requireRole(CU, ['yonetici','depo','cost_control'])) return;
  await birimDonusumHaritasiYukle();
  basla();
})();
```

- [ ] **Step 2: `renderStokTrend()`'e özet satırı ekle**

Satır 93-96'daki `el.innerHTML` template'ini güncelle — canvas div'inin ÜSTÜNE bir özet div'i ekle:

Mevcut (satır 93-96):
```js
  el.innerHTML=`
    <div class="card-title">Stok Trendi (pencere içi kümülatif net hareket)</div>
    <div class="field"><select id="stok-trend-urun" onchange="_stokTrendUrun=this.value;renderStokTrend()">${secenekler}</select></div>
    <div style="position:relative;height:220px"><canvas id="stok-trend-canvas"></canvas></div>`;
```

Yeni:
```js
  el.innerHTML=`
    <div class="card-title">Stok Trendi (pencere içi kümülatif net hareket)</div>
    <div class="field"><select id="stok-trend-urun" onchange="_stokTrendUrun=this.value;renderStokTrend()">${secenekler}</select></div>
    <div id="stok-trend-ozet" style="font-size:12px;color:var(--gray-500);margin-bottom:6px"></div>
    <div style="position:relative;height:220px"><canvas id="stok-trend-canvas"></canvas></div>`;
```

Satır 117-118'deki (kümülatif hesap sonrası, `if(!hareketler.length)` kontrolünden ÖNCE) koda ekle — mevcut kodun hemen altına:

Mevcut (satır 117-118):
```js
  let kumulatif=0;
  const veri=gunler.map(g=>{kumulatif+=(gunlukNet[g]||0);return kumulatif;});
```

Yeni (aynı iki satırın hemen altına eklenecek):
```js
  let kumulatif=0;
  const veri=gunler.map(g=>{kumulatif+=(gunlukNet[g]||0);return kumulatif;});
  const netToplam=veri.length?veri[veri.length-1]:0;
  const netEtiket=birimDonusumEtiketi(_stokTrendUrun,Math.abs(netToplam));
  document.getElementById('stok-trend-ozet').textContent=`Net değişim: ${round2(netToplam)}${netEtiket?' (≈'+netEtiket.replace('≈','')+')':''}`;
```

- [ ] **Step 3: `renderTuketimTrend()`'e özet satırı ekle**

Satır 138-141'deki template'i güncelle:

Mevcut (satır 138-141):
```js
  el.innerHTML=`
    <div class="card-title">Tüketim Trendi</div>
    <div class="field"><select id="tuketim-trend-urun" onchange="_tuketimTrendUrun=this.value;renderTuketimTrend()">${secenekler}</select></div>
    <div style="position:relative;height:220px"><canvas id="tuketim-trend-canvas"></canvas></div>`;
```

Yeni:
```js
  el.innerHTML=`
    <div class="card-title">Tüketim Trendi</div>
    <div class="field"><select id="tuketim-trend-urun" onchange="_tuketimTrendUrun=this.value;renderTuketimTrend()">${secenekler}</select></div>
    <div id="tuketim-trend-ozet" style="font-size:12px;color:var(--gray-500);margin-bottom:6px"></div>
    <div style="position:relative;height:220px"><canvas id="tuketim-trend-canvas"></canvas></div>`;
```

Satır 166'daki (`veri` hesabından sonra, `Chart(...)` çağrısından ÖNCE) koda ekle:

Mevcut (satır 166):
```js
  const veri=gunler.map(g=>gunlukToplam[g]||0);
```

Yeni (aynı satırın hemen altına eklenecek):
```js
  const veri=gunler.map(g=>gunlukToplam[g]||0);
  const toplamTuketim=veri.reduce((a,b)=>a+b,0);
  const tukEtiket=birimDonusumEtiketi(_tuketimTrendUrun,toplamTuketim);
  document.getElementById('tuketim-trend-ozet').textContent=`Toplam tüketim: ${round2(toplamTuketim)}${tukEtiket?' ('+tukEtiket+')':''}`;
```

**Not:** `renderFoodCostTrend()`'e DOKUNULMUYOR — food-cost yüzdesi tüm ürünler için toplu bir metrik, tek ürüne özel birim dönüşümü anlamlı değil (spec kapsamı dışı, YAGNI).

- [ ] **Step 4: Tarayıcıda doğrula**

`trend-raporlama.html`'i aç, Task 2'de dönüşüm tanımladığın ürünü Stok Trendi ve Tüketim Trendi sekmelerinde seç. Grafik başlığının altında "Net değişim: ... (≈X KOLİ)" ve "Toplam tüketim: ... (≈X KOLİ)" görünmeli. Dönüşümü olmayan bir ürün seçilince parantez kısmı görünmemeli.

- [ ] **Step 5: Commit**

```bash
git add trend-raporlama.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: trend-raporlama.html'e birim dönüşüm özet gösterimi eklendi"
```

---

## Task 7: `satin-alma-siparisolustur.html` Entegrasyonu

**Files:**
- Modify: `satin-alma-siparisolustur.html` (Task 1 planlanırken satır 345-347 civarındaydı, dizi `SP_SATIRLAR`, öğe `u`, `u.kod`/`u.miktar`)

**Interfaces:**
- Consumes: `birimDonusumHaritasiYukle()`, `birimDonusumEtiketi(kod, miktar)`.

- [ ] **Step 1: Init akışına harita yüklemeyi ekle**

Sayfanın init IIFE'sinde (`requireLogin`/`requireRole` sonrası, ana render öncesi) ekle:

```js
await birimDonusumHaritasiYukle();
```

- [ ] **Step 2: Miktar giriş alanının yanına bilgi etiketi ekle**

`Grep "SP_SATIRLAR\[\$\{i\}\].miktar"` ile satırı bul (Task 1 planlanırken satır 345-347 civarındaydı):

Mevcut (referans, `Read` ile teyit et):
```js
<div><label style="font-size:11px;font-weight:600;color:var(--gray-600)">MİKTAR</label>
  <input type="number" value="${u.miktar}" placeholder="0" oninput="SP_SATIRLAR[${i}].miktar=this.value"
    style="width:100%;padding:9px 12px;border:1.5px solid var(--gray-300);border-radius:8px;font-size:13px;outline:none"></div>
```

Yeni (input'un kapanışından hemen sonra, aynı `div` içine bir etiket ekle):
```js
<div><label style="font-size:11px;font-weight:600;color:var(--gray-600)">MİKTAR</label>
  <input type="number" value="${u.miktar}" placeholder="0" oninput="SP_SATIRLAR[${i}].miktar=this.value"
    style="width:100%;padding:9px 12px;border:1.5px solid var(--gray-300);border-radius:8px;font-size:13px;outline:none">
  ${birimDonusumEtiketi(u.kod,u.miktar)?`<div style="font-size:10px;color:var(--gray-500);margin-top:3px">${birimDonusumEtiketi(u.kod,u.miktar)}</div>`:''}</div>
```

**Not:** Bu statik bir gösterim — kullanıcı miktarı değiştirdikçe etiket CANLI güncellenmiyor (sayfa yeniden render edildiğinde güncellenir, ki bu satırların render edildiği fonksiyon zaten her `SP_SATIRLAR` değişikliğinde tekrar çağrılıyorsa otomatik güncellenir; çağrılmıyorsa bu statik davranış kabul edilebilir — spec sadece "bilgi amaçlı gösterim" istiyor, canlı güncelleme istemiyor).

- [ ] **Step 3: Tarayıcıda doğrula**

Sipariş oluşturma ekranında, Task 2'de dönüşüm tanımladığın ürünü sepete ekle, miktar alanının altında `≈X KOLİ` etiketi göründüğünü doğrula.

- [ ] **Step 4: Commit**

```bash
git add satin-alma-siparisolustur.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: satin-alma-siparisolustur.html'e birim dönüşüm gösterimi eklendi"
```

---

## Task 8: `mal-kabul-liste.html` Entegrasyonu

**Files:**
- Modify: `mal-kabul-liste.html` (Task 1 planlanırken satır 464 civarındaydı, dizi `formKalemleri`, öğe `k`, `k.kod`/`k.miktar`)

**Interfaces:**
- Consumes: `birimDonusumHaritasiYukle()`, `birimDonusumEtiketi(kod, miktar)`.

- [ ] **Step 1: Init akışına harita yüklemeyi ekle**

Sayfanın init IIFE'sinde (`requireLogin`/`requireRole` sonrası, ana render öncesi) ekle:

```js
await birimDonusumHaritasiYukle();
```

- [ ] **Step 2: Miktar giriş alanının yanına bilgi etiketi ekle**

`Grep "k-miktar-\$\{i\}"` ile satırı bul (Task 1 planlanırken satır 464 civarındaydı):

Mevcut (referans, `Read` ile teyit et):
```js
<div class="field"><label>Miktar *</label><input type="number" id="k-miktar-${i}" value="${k.miktar}" placeholder="Miktar" min="0" step="0.01" onchange="formKalemleri[${i}].miktar=this.value"></div>
```

Yeni:
```js
<div class="field"><label>Miktar *</label><input type="number" id="k-miktar-${i}" value="${k.miktar}" placeholder="Miktar" min="0" step="0.01" onchange="formKalemleri[${i}].miktar=this.value">${birimDonusumEtiketi(k.kod,k.miktar)?`<div style="font-size:10px;color:var(--gray-500);margin-top:3px">${birimDonusumEtiketi(k.kod,k.miktar)}</div>`:''}</div>
```

**Not:** "Koli bazlı giriş" modalına (`koliKaydet()`, satır 432-437 civarı) DOKUNULMUYOR — o zaten kg toplamını otomatik hesaplıyor (tek seferlik, o teslimata özel), bizim eklediğimiz etiket ayrı ve tamamlayıcı bir bilgi katmanı (ürünün GENEL referans oranı).

- [ ] **Step 3: Tarayıcıda doğrula**

Mal kabul formunda, Task 2'de dönüşüm tanımladığın ürünü ekle, miktar alanının altında `≈X KOLİ` etiketi göründüğünü doğrula. Koli bazlı giriş modalının eskisi gibi çalıştığını (kg toplamını doğru hesapladığını) doğrula — bu akışa dokunulmadı ama regresyon riski var, mutlaka test et.

- [ ] **Step 4: Commit**

```bash
git add mal-kabul-liste.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: mal-kabul-liste.html'e birim dönüşüm gösterimi eklendi"
```

---

## Task 9: Uçtan Uca Doğrulama

**Files:**
- Modify: `.superpowers/sdd/progress.md` (ilerleme kaydı)

**Interfaces:**
- Consumes: Task 1-8'in tüm çıktıları.

- [ ] **Step 1: Repo genelinde grep taraması**

```bash
cd "C:\Users\USER\Projects\gurok-mal-kabul"
grep -c "birimDonusumEtiketi" ortak.js stok-takip.html gunluk-tuketim.html trend-raporlama.html satin-alma-siparisolustur.html mal-kabul-liste.html
```

Beklenen: `ortak.js` ≥1 (tanım), diğer 5 dosyanın her biri ≥1 (en az bir çağrı).

- [ ] **Step 2: curl ile RLS son kontrol**

```bash
SB_URL='https://xwytofysmgqtqjzkplfi.supabase.co'
SB_KEY='eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inh3eXRvZnlzbWdxdHFqemtwbGZpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMyMjg5ODMsImV4cCI6MjA5ODgwNDk4M30.E7cRcOAvCmUFXWs45t4HE-igpmqWmSN2J66dOuvCHjA'
curl -s -X DELETE "$SB_URL/rest/v1/urun_birim_donusum?urun_kodu=eq.TEST" -H "apikey: $SB_KEY" -H "Authorization: Bearer $SB_KEY"
```

Beklenen: gerçek `DELETE` policy tanımlanmadığı için reddedilmeli (RLS: no policy for DELETE = implicit deny) — hata veya 0 satır etkilenmeli.

- [ ] **Step 3: Kullanıcıya manuel tarayıcı testi iste**

Kullanıcıdan şunu doğrulamasını iste: en az 2 farklı ürün için `urun-yonetimi.html`'den dönüşüm tanımla, 5 dokunulan sayfanın her birinde bu ürünlerin doğru gösterildiğini kontrol et, hiçbir sayfada mevcut giriş/kaydetme akışının bozulmadığını (özellikle mal kabul ve günlük tüketim — bunlar kritik operasyonel akışlar) doğrula.

- [ ] **Step 4: `git fetch origin` ile paralel oturum çakışmasını kontrol et**

```bash
cd "C:\Users\USER\Projects\gurok-mal-kabul"
git fetch origin
git rev-list --left-right --count HEAD...origin/main
```

Eğer origin ilerlemişse, `git diff --name-only $(git merge-base HEAD origin/main) origin/main` ile hangi dosyaların çakıştığını kontrol et, `git merge origin/main` ile birleştir, merge sonrası Task 3-8'de değiştirilen tüm dosyalarda `birimDonusumEtiketi`/`BIRIM_DONUSUM_HARITASI` çağrılarının sağ salim kaldığını `grep` ile TEKRAR doğrula (Faz B6'daki merge doğrulama deseniyle birebir aynı).

- [ ] **Step 5: İlerleme kaydı ve push**

`.superpowers/sdd/progress.md` sonuna ekle:

```
Birim Dönüşüm Sistemi: TAMAMLANDI — urun_birim_donusum tablosu + RLS + urun_yonetimi modülü, urun-yonetimi.html yönetim ekranı, ortak.js birimDonusumEtiketi() yardımcı fonksiyonu, 5 sayfaya (stok-takip, gunluk-tuketim, trend-raporlama, satin-alma-siparisolustur, mal-kabul-liste) gösterim entegrasyonu. Mal kabul/giriş akışları değişmedi.
```

```bash
git push origin main
```

---

## Self-Review Notu

- **Spec kapsaması:** Spec'in tüm bölümleri (veri modeli, yeni ekran, gösterim entegrasyonu, hata yönetimi, test planı) Task 1-9'a dağıtıldı. Hata yönetimi ayrı bir task değil — `birimDonusumEtiketi`'in kendisi (`if(!d||!d.carpan)return''`) ve `birimDonusumHaritasiYukle`'nin `try/catch` ile sessiz başarısızlığı zaten bunu karşılıyor, Task 3'te doğrulanıyor.
- **Placeholder taraması:** Yok — her adımda tam kod var, "TBD"/"benzer şekilde" yok.
- **Tip/isim tutarlılığı:** `BIRIM_DONUSUM_HARITASI` (Task 3'te tanımlı) ve `birimDonusumEtiketi(urunKodu, miktar)` imzası Task 4-8'in hepsinde birebir aynı kullanılıyor. `urun_birim_donusum` tablo/sütun isimleri Task 1-3 arasında tutarlı.
- **Bilinmeyen satır numaraları riski:** Task 4-8'deki bazı satır numaraları bu plan yazılırken (paralel oturumun aktif push yaptığı bir ortamda) alınmış referans değerlerdir — her task'ın Step 1'inde implementer'a `Grep`/`Read` ile güncel konumu teyit etmesi açıkça söylendi, bu B6 fazında kanıtlanmış bir risk azaltma deseni.
