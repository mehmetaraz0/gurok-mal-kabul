# Bar QR + Masa Token Yönetimi Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans (inline). Steps use checkbox (`- [ ]`).

**Goal:** Personelin ana portaldan (F&B Bar) masa oluşturup token üretmesi, QR kodunu görüp yazdırması, masayı kapatıp açması.

**Architecture:** Yeni personel sayfası `bar-masa-yonetimi.html` → JWT-doğrulamalı Edge Function `masa-yonetim` (customer projesi) → `masa_tokenlari` CRUD. QR client-side, repoya gömülü `qr-mini.js` ile. F&B Bar portal kartı canlandırılıp bir hub sayfasına (`bar.html`) bağlanır.

**Tech Stack:** Vanilla HTML/JS, Supabase REST + Edge Function (Deno), gömülü QR JS kütüphanesi.

## Global Constraints

- CUSTOMER ref `udjpcsjifgdzvfflezaa`, MAIN ref `xwytofysmgqtqjzkplfi`.
- MAIN anon key (JWT doğrulaması için, SB_KEY ile aynı): `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inh3eXRvZnlzbWdxdHFqemtwbGZpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMyMjg5ODMsImV4cCI6MjA5ODgwNDk4M30.E7cRcOAvCmUFXWs45t4HE-igpmqWmSN2J66dOuvCHjA`
- CUSTOMER anon key (sayfa QR base için gerekmez; masa-yonetim çağrıları JWT ile): masa-yonetim çağrısında apikey=CUSTOMER anon (mevcut `eyJ...udjpcsjifgdzvfflezaa...`).
- Token gizli — masa-yonetim endpoint'i JWT doğrulamadan hiçbir şey döndürmez.
- JWT `oturumAccessTokenGetir()` (auth-guard.js) ile alınır. Yetki modülü `bar_siparis_yonetimi`, min seviye `kayit`.
- QR BASE sabit: `https://mehmetaraz0.github.io/gurok-mal-kabul/bar-menu.html?t=<token>`.
- Commit `git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com"`. Her task öncesi `git fetch origin`.
- Deploy Dashboard'dan (kullanıcı); curl doğrulamaları controller'da. Kullanıcı teknik değil, adımlar sade verilir.

---

## Task 1: Edge Function `masa-yonetim` (JWT korumalı CRUD)

**Files:** Create `docs/kurulum/musteri-projesi/masa-yonetim/index.ts`; Modify `.superpowers/sdd/progress.md`

**Interfaces:** Produces `POST /functions/v1/<ad>` → `{jwt, action, ...}`. `action:'liste'` → `{ok, masalar:[...]}`; `action:'ekle',otel_id,depo_id,masa_adi` → `{ok, masa}`; `action:'durum',token,aktif` → `{ok}`. JWT geçersiz → `{ok:false, mesaj:'Yetki yok'}`.

- [ ] **Step 1: index.ts oluştur**

```typescript
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

Deno.serve(async (req) => {
  const cors = { "Access-Control-Allow-Origin":"*", "Access-Control-Allow-Headers":"content-type", "Access-Control-Allow-Methods":"POST, OPTIONS" };
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ ok:false, mesaj:"POST bekleniyor" }, 405, cors);

  let body:any; try { body = await req.json(); } catch { return json({ ok:false, mesaj:"Geçersiz JSON" }, 400, cors); }
  const { jwt, action } = body ?? {};
  if (!jwt) return json({ ok:false, mesaj:"Oturum yok" }, 401, cors);

  // Yetki kontrolü: JWT'yi ana projede doğrula + bar_siparis_yonetimi kayıt yetkisi
  const mainUrl = Deno.env.get("MAIN_SB_URL")!;
  const mainAnon = Deno.env.get("MAIN_ANON_KEY")!;
  const asUser = createClient(mainUrl, mainAnon, { global: { headers: { Authorization: "Bearer " + jwt } } });
  const { data: yetkili, error: yErr } = await asUser.rpc("auth_yetki_var", { p_modul_kod:"bar_siparis_yonetimi", p_min_seviye:"kayit" });
  if (yErr || yetkili !== true) return json({ ok:false, mesaj:"Yetki yok" }, 403, cors);

  // Yetki tamam → customer service_role ile işlem
  const cust = createClient(Deno.env.get("CUSTOMER_SB_URL")!, Deno.env.get("CUSTOMER_SERVICE_KEY")!);

  if (action === "liste") {
    const { data, error } = await cust.from("masa_tokenlari").select("token,otel_id,depo_id,masa_adi,aktif").order("masa_adi");
    if (error) return json({ ok:false, mesaj:error.message }, 200, cors);
    return json({ ok:true, masalar:data }, 200, cors);
  }
  if (action === "ekle") {
    const { otel_id, depo_id, masa_adi } = body;
    if (!otel_id || !depo_id || !masa_adi) return json({ ok:false, mesaj:"otel/depo/masa adı zorunlu" }, 400, cors);
    const token = crypto.randomUUID();
    const { data, error } = await cust.from("masa_tokenlari").insert({ token, otel_id, depo_id, masa_adi, aktif:true }).select().single();
    if (error) return json({ ok:false, mesaj:error.message }, 200, cors);
    return json({ ok:true, masa:data }, 200, cors);
  }
  if (action === "durum") {
    const { token, aktif } = body;
    if (!token || typeof aktif !== "boolean") return json({ ok:false, mesaj:"token/aktif zorunlu" }, 400, cors);
    const { error } = await cust.from("masa_tokenlari").update({ aktif }).eq("token", token);
    if (error) return json({ ok:false, mesaj:error.message }, 200, cors);
    return json({ ok:true }, 200, cors);
  }
  return json({ ok:false, mesaj:"Bilinmeyen aksiyon" }, 400, cors);
});

function json(obj:unknown, status:number, cors:Record<string,string>) {
  return new Response(JSON.stringify(obj), { status, headers:{ ...cors, "Content-Type":"application/json" } });
}
```

- [ ] **Step 2: Kullanıcı deploy eder + MAIN_ANON_KEY secret ekler**

Dashboard → Edge Functions → Via Editor → ad `masa-yonetim` → kodu yapıştır → Deploy. Sonra Secrets → yeni secret `MAIN_ANON_KEY` = (yukarıdaki MAIN anon key). Deploy adı controller'a bildirilir (rastgele ad alabilir).

- [ ] **Step 3: curl reddetme doğrulaması (controller)**

```bash
C_URL='https://udjpcsjifgdzvfflezaa.supabase.co'; C_KEY='<customer anon>'
# JWT'siz/geçersiz → reddedilmeli
curl -s -X POST "$C_URL/functions/v1/<deploy-adi>" -H "apikey: $C_KEY" -H "Authorization: Bearer $C_KEY" -H "Content-Type: application/json" -d '{"action":"liste"}'
curl -s -X POST "$C_URL/functions/v1/<deploy-adi>" -H "apikey: $C_KEY" -H "Authorization: Bearer $C_KEY" -H "Content-Type: application/json" -d '{"jwt":"sahte-jwt","action":"liste"}'
```
Beklenen: ikisi de `{"ok":false,"mesaj":"Oturum yok"}` / `{"ok":false,"mesaj":"Yetki yok"}`. (Kabul yolu Task 5'te sayfayla test edilir.)

- [ ] **Step 4: Commit** — `git add docs/kurulum/musteri-projesi/masa-yonetim/index.ts` + ledger.

---

## Task 2: Gömülü QR kütüphanesi `qr-mini.js`

**Files:** Create `qr-mini.js` (repo kökü); Modify `.superpowers/sdd/progress.md`

**Interfaces:** Produces global `QRCode` (davidshimjs/qrcodejs, MIT). Kullanım: `new QRCode(elDiv, { text, width, height, correctLevel: QRCode.CorrectLevel.M })`.

- [ ] **Step 1: Kütüphaneyi repoya indir (bundle — runtime CDN değil)**

```bash
cd "C:/Users/USER/Projects/gurok-mal-kabul"
curl -sL "https://cdn.jsdelivr.net/gh/davidshimjs/qrcodejs@04f46c6a0708c9a09fd58a8a5e01c9d3a2c9d9be/qrcode.min.js" -o qr-mini.js
grep -c "QRCode" qr-mini.js   # >0 olmalı
```
Beklenen: dosya indi, `QRCode` içeriyor. (İndirilemezse alternatif pin: aynı repo `qrcode.js`.)

- [ ] **Step 2: Commit** — `git add qr-mini.js` + ledger.

---

## Task 3: Sayfa `bar-masa-yonetimi.html`

**Files:** Create `bar-masa-yonetimi.html`; Modify `.superpowers/sdd/progress.md`

**Interfaces:** Consumes Task 1 endpoint + Task 2 `QRCode`. `oturumAccessTokenGetir()`, `requireRole`, `kullaniciYetkileriGetir`, `escapeHtml`, `otel-config` (`merkeziDepoKodu`).

- [ ] **Step 1: Sayfayı oluştur** — bar-siparis-kuyrugu.html desenini izle:
  - `<head>`: auth-guard.js, supabase-config.js, nav-drawer, otel-config.js, ortak.js, theme.css, **qr-mini.js**.
  - Sabitler: `CUSTOMER_SB_URL`, `CUSTOMER_ANON_KEY`, `MASA_FN='/functions/v1/<deploy-adi>'`, `QR_BASE='https://mehmetaraz0.github.io/gurok-mal-kabul/bar-menu.html?t='`.
  - init: `requireRole(CU,['mutfak','bar','yonetici'])`; `YETKI_HARITASI=await kullaniciYetkileriGetir()`; `yazabilir()`.
  - `masaCagir(payload)`: `oturumAccessTokenGetir()` ile jwt ekleyip Edge Function'a POST (apikey=CUSTOMER_ANON_KEY). jwt yoksa "Oturum doğrulanamadı, tekrar giriş yapın".
  - Form: otel `<select>` (810/811), depo `<input>` (otel değişince `merkeziDepoKodu` ile ön-dolar, düzenlenebilir), masa adı `<input>`. "Ekle" → `masaCagir({action:'ekle',...})` → listeyi yenile.
  - Liste: `masaCagir({action:'liste'})` → satırlar (masa_adi, otel, aktif rozet). Her satır: "QR Göster" (modal), "Kapat"/"Aç" (`action:'durum'`).
  - QR modal: bir `<div id="qrKutu">` içine `new QRCode(el,{text:QR_BASE+token,width:220,height:220})`; "Yazdır" butonu `window.print()` (yazdırırken yalnız QR+masa adı görünsün — `@media print`).
  - Tüm DB metni `escapeHtml()`.

- [ ] **Step 2: Statik doğrulama**
```bash
grep -c "oturumAccessTokenGetir\|masaCagir\|QRCode\|escapeHtml" bar-masa-yonetimi.html   # >=4
node -e "require('fs').readFileSync('bar-masa-yonetimi.html','utf8')" && echo ok
```

- [ ] **Step 3: Commit** + ledger.

---

## Task 4: F&B Bar hub + portal kartı aktivasyonu

**Files:** Create `bar.html`; Modify `index.html` (F&B Bar kart tanımı ~satır 394)

- [ ] **Step 1: `bar.html` hub sayfası** — iki kart: "Masa / QR Yönetimi" → `bar-masa-yonetimi.html`, "Sipariş Kuyruğu" → `bar-siparis-kuyrugu.html`. auth-guard + `requireRole(['mutfak','bar','yonetici'])`. Basit kart düzeni (mevcut sayfa stilini izle).

- [ ] **Step 2: index.html kartını aktifleştir** — `id:'bar'` kartını güncelle:
```javascript
{
  id: 'bar', ad: 'F&B Bar', desc: 'Masa/QR, sipariş kuyruğu',
  url: 'bar.html', moduller: ['bar_siparis_yonetimi'], durum: 'aktif',
  svg: '<path d="M3 11l18-5v12L3 13z"/>'
}
```
(`bar_qr_siparis` → `bar_siparis_yonetimi`; `yapiyor` → `aktif`.)

- [ ] **Step 3: Doğrulama** — `grep -n "bar_siparis_yonetimi.*durum: 'aktif'\|id: 'bar'" index.html`; portal kartın artık tıklanabilir olduğunu Task 5'te görsel doğrula.

- [ ] **Step 4: Commit** + ledger.

---

## Task 5: Uçtan uca + push

- [ ] **Step 1: Kullanıcı sayfayı açar (canlı)** — portal → F&B Bar → Masa/QR Yönetimi. Masa ekle (810, "Havuz Bar 1"). Liste'de görünmeli.
- [ ] **Step 2: controller doğrular** — kullanıcı yeni tokenı söyler/görür; controller: `masa_oteli_getir(token)` → '810'. QR modalın `QR_BASE+token` kodladığını kullanıcı görür.
- [ ] **Step 3: Kapat testi** — "Kapat" → controller `masa_oteli_getir(token)` → null.
- [ ] **Step 4: push** — `git fetch origin` + `git push origin main`.

---

## Self-Review Notu
- Spec kapsaması: Edge Function→Task 1, QR lib→Task 2, sayfa→Task 3, navigasyon→Task 4, test→Task 5. Tamam.
- Güvenlik: masa-yonetim JWT olmadan hiçbir şey döndürmez (Task 1 Step 3 reddetme); token yalnız yetkili personele döner.
- Tip tutarlılığı: `masaCagir` payload action'ları (liste/ekle/durum) Task 1 imzasıyla eşleşiyor; `QRCode` API Task 2-3 arası aynı; `MASA_FN` deploy adı Task 1-3 arası aynı.
- Bilinen risk: QR lib CDN indirilemezse alternatif pin/kaynak (Task 2 Step 1 notu).
