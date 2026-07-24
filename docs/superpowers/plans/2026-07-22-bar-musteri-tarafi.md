# Bar Modülü — Müşteri Tarafı (İzole Proje + Köprü + QR Sayfası) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Müşterinin QR okutup telefonundan bar/restoran siparişi verebildiği, ana ERP veritabanına fiziksel olarak erişimi OLMAYAN izole bir müşteri katmanı kurmak: ayrı Supabase projesi + Edge Function köprüsü + statik menü/sipariş sayfası.

**Architecture:** İki izole Supabase projesi. Müşteri telefonu SADECE müşteri projesinin anon key'ini görür (menü okuma + Edge Function çağırma). Sipariş, müşteri projesindeki Edge Function `siparis-gonder` üzerinden ANA projedeki `bar_siparis_olustur` RPC'sine `service_role` ile iletilir — stok hard-block'u ve rezervasyon ana projede işler, sonuç senkron olarak müşteriye döner. Müşteri projesi ana projeye asla doğrudan bağlanmaz; ana projenin anon/service key'i müşteri telefonuna hiç çıkmaz.

**Tech Stack:** İzole Supabase projesi (PostgreSQL + RLS), Supabase Edge Function (Deno/TypeScript), vanilla HTML/JS statik sayfa (GitHub Pages alt alan adı).

## Global Constraints

- **İki-izole-proje mimarisi korunur.** Müşteri sayfası ANA projenin (`xwytofysmgqtqjzkplfi`) hiçbir key'ini/URL'ini içermez. Ana projeye tek erişim: Edge Function'ın `service_role` secret'ı (Deno ortamında, tarayıcıya çıkmaz).
- **Dış ajans/WordPress YOK.** Statik sayfa kendi GitHub Pages alt alan adımızda (`menu.alibeyclub.com` veya eşdeğeri) barındırılır. Spec bölüm 6'daki WordPress-link maddesi bu plandan düşürüldü.
- Müşteri projesi RLS (spec bölüm 8): `menu_urunler` yalnız `SELECT USING (aktif=true)`; `masa_tokenlari` anon'a KAPALI (yalnız Edge Function service_role okur); sipariş arşiv tablosu (varsa) yalnız Edge Function yazar.
- QR opak token taşır (`?t=<token>`); ham masa/oda ID taşımaz. Token→{otel_id, depo_id, masa_adi} eşleşmesi Edge Function'da (sunucu tarafı) `masa_tokenlari`'ndan çözülür.
- Ücretli kalem kuralı (spec bölüm 2): sepette `ucretli=true` en az bir kalem varsa `oda_no` zorunlu; yalnız ücretsiz kalemler varsa oda_no istenmez.
- Rate-limit / miktar üst sınırı (spec bölüm 8): Edge Function sipariş başına maksimum kalem sayısı ve kalem başına maksimum adet uygular (durumsuz kontrol). Zaman-bazlı token rate-limit v1'de yok, takip maddesi.
- Ana proje `bar_siparis_olustur` fonksiyonunun `anon` GRANT'i bu planda KALDIRILIR — yalnız `service_role`/`authenticated` çağırabilir (DoS yüzeyini kapatır; Edge Function service_role kullanır).
- Müşteri Supabase projesi URL + anon key kullanıcı tarafından sağlanır (Task 1'de projeyi açar). Plan boyunca `<CUSTOMER_SB_URL>` ve `<CUSTOMER_ANON_KEY>` bu gerçek değerlerle DOLDURULUR — bunlar placeholder değil, kullanıcının vereceği runtime değerlerdir.
- Ana proje sabitleri: `MAIN_SB_URL='https://xwytofysmgqtqjzkplfi.supabase.co'`, `MAIN_PROJECT_REF='xwytofysmgqtqjzkplfi'`.
- Menü verisi v1'de MANUEL doldurulur (personel "yayınla" otomasyonu ayrı/ileride) — Task 1'de örnek insert ile.
- Bu proje paralel oturumla ortak repo: her task öncesi `git fetch origin` + gerekirse `git pull --ff-only`. Commit `git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com"`.
- Kapsam DIŞI: menü yayınlama otomasyonu (ana→müşteri senkron), `menu.alibeyclub.com` DNS CNAME kaydının fiili yapılması (kullanıcının domain paneli işi — plan sadece dosyayı hazırlar), zaman-bazlı rate-limit.

---

## Task 1: Müşteri Supabase Projesi Şeması + RLS

**Files:**
- Create: `docs/kurulum/musteri-projesi/01-musteri-sema.sql` (repoya + kullanıcıya)
- Modify: `.superpowers/sdd/progress.md`

**Interfaces:**
- Produces: Müşteri projesinde `menu_urunler` (salt okunur), `masa_tokenlari` (Edge Function okur), `siparis_arsiv` (Edge Function yazar) tabloları. Task 2 (Edge Function) `masa_tokenlari` + `siparis_arsiv`'i, Task 3 (sayfa) `menu_urunler`'i tüketir.

- [ ] **Step 1: Kullanıcı müşteri projesini açar**

Kullanıcıdan: supabase.com → New Project (örn. ad "gurok-bar-musteri"). Oluşunca **Settings → API**'den Project URL ve anon (public) key'i al. Bu ikisini controller'a ver — plan boyunca `<CUSTOMER_SB_URL>`/`<CUSTOMER_ANON_KEY>` yerine bunlar yazılır. Ayrıca ana projenin **service_role** key'i Task 2'de gerekecek (Edge Function secret'ı olarak); şimdilik alma.

- [ ] **Step 2: Şema SQL dosyasını oluştur**

`docs/kurulum/musteri-projesi/01-musteri-sema.sql`:

```sql
-- Bar müşteri projesi (İZOLE) — şema + RLS. Ana ERP projesinden AYRI bir Supabase
-- projesinde çalıştırılır. Bu projede SADECE bu 3 tablo vardır.
begin;

-- Menü önizleme (ana projeden manuel/yayınla ile doldurulur, müşteri okur)
create table public.menu_urunler (
  id uuid primary key,          -- ana projedeki menu_urunler.id ile AYNI (eşleştirme)
  ad text not null,
  kategori text,
  fiyat numeric(12,2) default 0,
  ucretli boolean not null default false,
  aktif boolean not null default true
);

-- Masa token haritası — anon ERİŞEMEZ, yalnız Edge Function (service_role) okur
create table public.masa_tokenlari (
  token text primary key,       -- opak, tahmin edilemez (örn. gen_random_uuid()::text)
  otel_id text not null,        -- '810' | '811'
  depo_id text not null,        -- bar/restoran depo kodu
  masa_adi text not null,
  aktif boolean not null default true
);

-- Sipariş arşivi — yalnız Edge Function yazar (izlenebilirlik/yeniden deneme için)
create table public.siparis_arsiv (
  id uuid primary key default gen_random_uuid(),
  token text,
  oda_no text,
  kalemler jsonb not null,
  ana_siparis_id uuid,          -- ana projeden dönen id (başarılıysa)
  sonuc text,                   -- 'basarili' | 'hata'
  hata_mesaji text,
  olusturma_zamani timestamptz default now()
);

alter table public.menu_urunler enable row level security;
alter table public.masa_tokenlari enable row level security;
alter table public.siparis_arsiv enable row level security;

-- menu_urunler: anon yalnız aktif ürünleri OKUR
create policy menu_anon_select on public.menu_urunler for select
  to anon using (aktif = true);

-- masa_tokenlari: anon'a HİÇBİR policy yok → varsayılan deny (Edge Function service_role
-- RLS'i bypass eder, o okur). Bilinçli olarak boş bırakıldı.

-- siparis_arsiv: anon'a policy yok → deny. Edge Function service_role yazar.

commit;

-- ============ ÖRNEK VERİ (v1 manuel) — controller gerçek menüyle günceller ============
-- insert into public.masa_tokenlari (token, otel_id, depo_id, masa_adi)
-- values ('demo-token-abc123', '810', '100', 'Havuz Bar Masa 1');
-- insert into public.menu_urunler (id, ad, kategori, fiyat, ucretli, aktif)
-- values ('<ana-projedeki-menu_urun-id>', 'Örnek Kokteyl', 'icecek', 120, true, true);
```

- [ ] **Step 3: Kullanıcı müşteri projesinde çalıştırır, onay bekle**

Kullanıcı `01-musteri-sema.sql`'i MÜŞTERİ projesinin SQL Editor'ünde çalıştırır. "Çalıştı" onayı bekle.

- [ ] **Step 4: curl ile doğrula (müşteri anon key ile)**

```bash
C_URL='<CUSTOMER_SB_URL>'; C_KEY='<CUSTOMER_ANON_KEY>'
# menu_urunler anon SELECT çalışmalı (boş liste, tablo var)
curl -s "$C_URL/rest/v1/menu_urunler?select=id&limit=1" -H "apikey: $C_KEY" -H "Authorization: Bearer $C_KEY"
# masa_tokenlari anon'a KAPALI olmalı ([] veya 42501 — asla token dönmemeli)
curl -s "$C_URL/rest/v1/masa_tokenlari?select=token&limit=1" -H "apikey: $C_KEY" -H "Authorization: Bearer $C_KEY"
# siparis_arsiv anon INSERT reddedilmeli
curl -s -X POST "$C_URL/rest/v1/siparis_arsiv" -H "apikey: $C_KEY" -H "Authorization: Bearer $C_KEY" -H "Content-Type: application/json" -d '{"kalemler":[]}'
```

Beklenen: menu_urunler `[]`, masa_tokenlari `[]` (boş — RLS token sızdırmıyor), siparis_arsiv INSERT `42501`.

- [ ] **Step 5: Commit**

```bash
git add docs/kurulum/musteri-projesi/01-musteri-sema.sql
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: bar müşteri projesi şeması (menu_urunler/masa_tokenlari/siparis_arsiv + RLS)"
```

İlerleme kaydı ekle.

---

## Task 2: Edge Function Köprüsü + Ana Proje Anon İzni Kaldırma

**Files:**
- Create: `docs/kurulum/musteri-projesi/siparis-gonder/index.ts` (Edge Function kaynağı, repoda referans)
- Create: `docs/kurulum/musteri-projesi/02-ana-proje-anon-kaldir.sql`
- Modify: `.superpowers/sdd/progress.md`

**Interfaces:**
- Consumes: Task 1'in `masa_tokenlari`/`siparis_arsiv` tabloları; ana projenin `bar_siparis_olustur(p_otel_id,p_depo_id,p_masa_token,p_oda_no,p_kalemler)` RPC'si.
- Produces: `<CUSTOMER_SB_URL>/functions/v1/siparis-gonder` endpoint'i. POST `{token, kalemler:[{menu_urun_id,adet}], oda_no}` → `{ok:true, siparis_id}` veya `{ok:false, mesaj}`. Task 3 (sayfa) bunu çağırır.

- [ ] **Step 1: Edge Function kaynağını oluştur**

`docs/kurulum/musteri-projesi/siparis-gonder/index.ts`:

```typescript
// Supabase Edge Function: siparis-gonder
// Müşteri sayfasından POST alır, ana ERP projesindeki bar_siparis_olustur RPC'sini
// service_role ile çağırır, sonucu senkron döner. Arşive yazar.
// Deploy: supabase functions deploy siparis-gonder --project-ref <CUSTOMER_PROJECT_REF>
// Secrets: MAIN_SB_URL, MAIN_SERVICE_KEY (ana proje service_role), CUSTOMER_SB_URL, CUSTOMER_SERVICE_KEY

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const MAX_KALEM = 20;        // sipariş başına max farklı kalem
const MAX_ADET = 30;         // kalem başına max adet

Deno.serve(async (req) => {
  const cors = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ ok: false, mesaj: "POST bekleniyor" }, 405, cors);

  let body: any;
  try { body = await req.json(); } catch { return json({ ok: false, mesaj: "Geçersiz JSON" }, 400, cors); }
  const { token, kalemler, oda_no } = body ?? {};

  if (!token || !Array.isArray(kalemler) || kalemler.length === 0)
    return json({ ok: false, mesaj: "token ve kalemler zorunlu" }, 400, cors);
  if (kalemler.length > MAX_KALEM)
    return json({ ok: false, mesaj: "Çok fazla kalem" }, 400, cors);
  for (const k of kalemler) {
    const adet = Number(k?.adet);
    if (!k?.menu_urun_id || !(adet > 0) || adet > MAX_ADET)
      return json({ ok: false, mesaj: "Geçersiz kalem/adet" }, 400, cors);
  }

  const custUrl = Deno.env.get("CUSTOMER_SB_URL")!;
  const custKey = Deno.env.get("CUSTOMER_SERVICE_KEY")!;
  const mainUrl = Deno.env.get("MAIN_SB_URL")!;
  const mainKey = Deno.env.get("MAIN_SERVICE_KEY")!;

  // 1) Token'ı çöz (service_role, RLS bypass)
  const cust = createClient(custUrl, custKey);
  const { data: masa, error: mErr } = await cust
    .from("masa_tokenlari").select("otel_id,depo_id,masa_adi,aktif")
    .eq("token", token).eq("aktif", true).maybeSingle();
  if (mErr || !masa) return json({ ok: false, mesaj: "Geçersiz masa" }, 400, cors);

  // 2) Ana projede sipariş oluştur (service_role, hard-block orada işler)
  const main = createClient(mainUrl, mainKey);
  const { data: siparisId, error: rErr } = await main.rpc("bar_siparis_olustur", {
    p_otel_id: masa.otel_id,
    p_depo_id: masa.depo_id,
    p_masa_token: masa.masa_adi,
    p_oda_no: oda_no ?? null,
    p_kalemler: kalemler,
  });

  // 3) Arşivle
  const basarili = !rErr && !!siparisId;
  await cust.from("siparis_arsiv").insert({
    token, oda_no: oda_no ?? null, kalemler,
    ana_siparis_id: basarili ? siparisId : null,
    sonuc: basarili ? "basarili" : "hata",
    hata_mesaji: rErr?.message ?? null,
  });

  if (!basarili)
    return json({ ok: false, mesaj: rErr?.message ?? "Sipariş oluşturulamadı" }, 200, cors);
  return json({ ok: true, siparis_id: siparisId }, 200, cors);
});

function json(obj: unknown, status: number, cors: Record<string, string>) {
  return new Response(JSON.stringify(obj), {
    status, headers: { ...cors, "Content-Type": "application/json" },
  });
}
```

- [ ] **Step 2: Kullanıcıya deploy adımlarını ver**

Kullanıcıdan (Supabase CLI kurulu olmalı — `npm i -g supabase` ya da scoop; giriş `supabase login`):

```bash
# Edge Function dizinine kaynağı koy (kullanıcı kendi makinesinde)
#   supabase/functions/siparis-gonder/index.ts  ← yukarıdaki index.ts

# Secret'ları ayarla (MÜŞTERİ projesine)
supabase secrets set MAIN_SB_URL=https://xwytofysmgqtqjzkplfi.supabase.co --project-ref <CUSTOMER_PROJECT_REF>
supabase secrets set MAIN_SERVICE_KEY=<ANA_PROJE_SERVICE_ROLE_KEY> --project-ref <CUSTOMER_PROJECT_REF>
supabase secrets set CUSTOMER_SB_URL=<CUSTOMER_SB_URL> --project-ref <CUSTOMER_PROJECT_REF>
supabase secrets set CUSTOMER_SERVICE_KEY=<CUSTOMER_SERVICE_ROLE_KEY> --project-ref <CUSTOMER_PROJECT_REF>

# Deploy (anon çağrılabilsin diye --no-verify-jwt)
supabase functions deploy siparis-gonder --project-ref <CUSTOMER_PROJECT_REF> --no-verify-jwt
```

- [ ] **Step 3: Ana projede bar_siparis_olustur anon iznini kaldır**

`docs/kurulum/musteri-projesi/02-ana-proje-anon-kaldir.sql` (ANA projede çalıştırılır):

```sql
-- Edge Function artık service_role ile çağırıyor; anon'un doğrudan çağırmasına gerek yok
-- (DoS/sahte-rezervasyon yüzeyini kapatır). authenticated (personel) korunur.
begin;
revoke execute on function public.bar_siparis_olustur(text,text,text,text,jsonb) from anon;
commit;
```

Kullanıcı bunu ANA projede çalıştırır, "çalıştı" onayı bekle.

- [ ] **Step 4: curl ile köprüyü doğrula**

Önce kullanıcı, Task 1'deki örnek `masa_tokenlari` satırını ve ana projeye karşılık gelen bir test menü ürününü (hem ana hem müşteri projesinde aynı id) ekler. Sonra:

```bash
C_URL='<CUSTOMER_SB_URL>'; C_KEY='<CUSTOMER_ANON_KEY>'
# anon artık ana bar_siparis_olustur'u ÇAĞIRAMAMALI (ana projede, ana anon key ile test):
MAIN_KEY='<ANA_PROJE_ANON_KEY>'
curl -s -X POST "https://xwytofysmgqtqjzkplfi.supabase.co/rest/v1/rpc/bar_siparis_olustur" -H "apikey: $MAIN_KEY" -H "Authorization: Bearer $MAIN_KEY" -H "Content-Type: application/json" -d '{"p_otel_id":"810","p_depo_id":"100","p_masa_token":"x","p_oda_no":null,"p_kalemler":[]}'
# Beklenen: 42501/permission denied (anon izni kaldırıldı)

# Edge Function anon ile çağrılabilmeli ve sonuç dönmeli:
curl -s -X POST "$C_URL/functions/v1/siparis-gonder" -H "apikey: $C_KEY" -H "Content-Type: application/json" -d '{"token":"<test-token>","oda_no":null,"kalemler":[{"menu_urun_id":"<test-menu-id>","adet":1}]}'
# Beklenen: {"ok":true,"siparis_id":"..."} (stok varsa) veya {"ok":false,"mesaj":"Yetersiz stok..."}
```

- [ ] **Step 5: Commit**

```bash
git add docs/kurulum/musteri-projesi/siparis-gonder/index.ts docs/kurulum/musteri-projesi/02-ana-proje-anon-kaldir.sql
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: bar sipariş Edge Function köprüsü + ana proje anon izni kaldırma"
```

---

## Task 3: Müşteri Menü/Sipariş Sayfası (Statik)

**Files:**
- Create: `bar-menu.html` (repo kökü — GitHub Pages alt alan adında yayınlanır)
- Create: `CNAME-bar-ornegi.txt` (menu.alibeyclub.com CNAME notu — DNS adımı için referans)
- Modify: `.superpowers/sdd/progress.md`

**Interfaces:**
- Consumes: `<CUSTOMER_SB_URL>`/`<CUSTOMER_ANON_KEY>` (menü okuma), Task 2'nin `functions/v1/siparis-gonder` endpoint'i.
- Produces: QR ile açılan müşteri arayüzü.

- [ ] **Step 1: Sayfayı oluştur**

`bar-menu.html` — bu sayfa ANA projeye HİÇBİR referans içermez, yalnız müşteri projesi + Edge Function. `<CUSTOMER_SB_URL>`/`<CUSTOMER_ANON_KEY>` gerçek değerlerle doldurulur:

```html
<!DOCTYPE html>
<html lang="tr">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
<title>Menü & Sipariş</title>
<style>
*{box-sizing:border-box;margin:0;padding:0;-webkit-tap-highlight-color:transparent}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;background:#f1f3f5;color:#15213a;padding-bottom:90px}
.hdr{background:#15213a;color:#fff;padding:16px;font-size:18px;font-weight:700}
.kat{padding:10px 16px 4px;font-size:13px;font-weight:700;color:#6c757d;text-transform:uppercase}
.urun{background:#fff;margin:8px 16px;border-radius:12px;padding:12px 14px;display:flex;align-items:center;gap:10px;box-shadow:0 1px 4px rgba(0,0,0,.06)}
.urun-ad{flex:1;font-size:15px;font-weight:600}
.urun-fiyat{font-size:13px;color:#b5442a;font-weight:700}
.urun-ucretsiz{font-size:11px;color:#27ae60;font-weight:600}
.adet{display:flex;align-items:center;gap:8px}
.adet button{width:30px;height:30px;border-radius:50%;border:none;background:#15213a;color:#fff;font-size:18px;cursor:pointer}
.adet span{min-width:20px;text-align:center;font-weight:700}
.sepet{position:fixed;bottom:0;left:0;right:0;background:#fff;box-shadow:0 -2px 12px rgba(0,0,0,.12);padding:12px 16px}
.oda-alani{margin-bottom:8px}
.oda-alani input{width:100%;padding:10px 12px;border:1.5px solid #dee2e6;border-radius:8px;font-size:15px;outline:none}
.gonder{width:100%;padding:14px;border:none;border-radius:10px;background:#27ae60;color:#fff;font-size:16px;font-weight:700;cursor:pointer}
.gonder:disabled{background:#adb5bd}
.mesaj{padding:10px 16px;text-align:center;font-size:14px}
.mesaj.ok{color:#155724}.mesaj.err{color:#9b1c1c}
</style>
</head>
<body>
<div class="hdr" id="hdr">Menü</div>
<div id="liste"></div>
<div class="sepet">
  <div class="oda-alani" id="odaAlani" style="display:none">
    <input id="odaNo" placeholder="Oda numaranız (ücretli ürün için zorunlu)">
  </div>
  <div class="mesaj" id="mesaj"></div>
  <button class="gonder" id="gonderBtn" onclick="gonder()">Sipariş Ver</button>
</div>
<script>
const CUSTOMER_SB_URL = '<CUSTOMER_SB_URL>';
const CUSTOMER_ANON_KEY = '<CUSTOMER_ANON_KEY>';
const H = { apikey: CUSTOMER_ANON_KEY, Authorization: 'Bearer ' + CUSTOMER_ANON_KEY, 'Content-Type': 'application/json' };
const token = new URLSearchParams(location.search).get('t') || '';
let MENU = [], SEPET = {};

function esc(s){return String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));}

async function menuYukle(){
  try{
    const r = await fetch(CUSTOMER_SB_URL + '/rest/v1/menu_urunler?select=*&aktif=eq.true&order=kategori', { headers: H });
    if(r.ok) MENU = await r.json();
  }catch(e){}
  render();
}

function render(){
  const el = document.getElementById('liste');
  if(!MENU.length){ el.innerHTML = '<div class="mesaj">Menü yüklenemedi.</div>'; return; }
  let html = '', sonKat = null;
  for(const u of MENU){
    if(u.kategori !== sonKat){ html += `<div class="kat">${esc(u.kategori||'Diğer')}</div>`; sonKat = u.kategori; }
    const adet = SEPET[u.id]?.adet || 0;
    const fiyat = u.ucretli ? `<span class="urun-fiyat">${u.fiyat} ₺</span>` : `<span class="urun-ucretsiz">Dahil</span>`;
    html += `<div class="urun">
      <div class="urun-ad">${esc(u.ad)}</div>${fiyat}
      <div class="adet">
        <button onclick="degis('${u.id}',-1)">−</button>
        <span id="a-${u.id}">${adet}</span>
        <button onclick="degis('${u.id}',1)">+</button>
      </div></div>`;
  }
  el.innerHTML = html;
  odaAlaniGuncelle();
}

function degis(id, d){
  const u = MENU.find(x => x.id === id); if(!u) return;
  const yeni = Math.max(0, (SEPET[id]?.adet || 0) + d);
  if(yeni === 0) delete SEPET[id]; else SEPET[id] = { adet: yeni, ucretli: u.ucretli };
  document.getElementById('a-' + id).textContent = yeni;
  odaAlaniGuncelle();
}

function ucretliVar(){ return Object.values(SEPET).some(x => x.ucretli); }
function odaAlaniGuncelle(){
  document.getElementById('odaAlani').style.display = ucretliVar() ? 'block' : 'none';
}

async function gonder(){
  const kalemler = Object.entries(SEPET).map(([menu_urun_id, v]) => ({ menu_urun_id, adet: v.adet }));
  const mesaj = document.getElementById('mesaj');
  if(!kalemler.length){ mesaj.className = 'mesaj err'; mesaj.textContent = 'Sepetiniz boş.'; return; }
  const odaNo = document.getElementById('odaNo').value.trim();
  if(ucretliVar() && !odaNo){ mesaj.className = 'mesaj err'; mesaj.textContent = 'Ücretli ürün için oda no zorunlu.'; return; }
  const btn = document.getElementById('gonderBtn'); btn.disabled = true; mesaj.className = 'mesaj'; mesaj.textContent = 'Gönderiliyor…';
  try{
    const r = await fetch(CUSTOMER_SB_URL + '/functions/v1/siparis-gonder', {
      method: 'POST', headers: H,
      body: JSON.stringify({ token, oda_no: ucretliVar() ? odaNo : null, kalemler })
    });
    const d = await r.json();
    if(d.ok){ mesaj.className = 'mesaj ok'; mesaj.textContent = '✅ Siparişiniz alındı!'; SEPET = {}; render(); }
    else { mesaj.className = 'mesaj err'; mesaj.textContent = '❌ ' + (d.mesaj || 'Sipariş alınamadı'); }
  }catch(e){ mesaj.className = 'mesaj err'; mesaj.textContent = '❌ Bağlantı hatası'; }
  btn.disabled = false;
}

if(!token){ document.getElementById('liste').innerHTML = '<div class="mesaj err">Geçersiz QR — masa bilgisi yok.</div>'; }
else menuYukle();
</script>
</body>
</html>
```

- [ ] **Step 2: DNS notunu oluştur**

`CNAME-bar-ornegi.txt`:

```
menu.alibeyclub.com için DNS kaydı (domain panelinde eklenecek):
  Tip: CNAME
  Ad:  menu
  Değer: mehmetaraz0.github.io
GitHub repo Settings → Pages → Custom domain: menu.alibeyclub.com
QR kodu şuna yönlendirir: https://menu.alibeyclub.com/bar-menu.html?t=<masa-token>
(Not: alt alan adı yayına girene kadar test için doğrudan
 https://mehmetaraz0.github.io/gurok-mal-kabul/bar-menu.html?t=<token> kullanılabilir.)
```

- [ ] **Step 3: Statik doğrulama**

`grep -c "xwytofysmgqtqjzkplfi" bar-menu.html` → **0** (müşteri sayfası ana projeye ASLA referans vermez — kritik izolasyon kontrolü). `grep -c "esc(" bar-menu.html` ≥ 3 (menü adı/kategori kaçışlı).

- [ ] **Step 4: Tarayıcı testi (kullanıcı)**

Kullanıcı `bar-menu.html?t=<test-token>`'ı açar (deploy sonrası): menü listelenmeli, adet ± çalışmalı, ücretli ürün ekleyince oda no alanı çıkmalı, "Sipariş Ver" → başarı mesajı, ve ana projedeki `bar-siparis-kuyrugu.html`'de siparişin belirmesi.

- [ ] **Step 5: Commit**

```bash
git add bar-menu.html CNAME-bar-ornegi.txt
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: bar müşteri menü/sipariş sayfası (izole, Edge Function ile ana projeye)"
```

---

## Task 4: Uçtan Uca Doğrulama + İzolasyon Denetimi

**Files:**
- Modify: `.superpowers/sdd/progress.md`

**Interfaces:**
- Consumes: Task 1-3.

- [ ] **Step 1: İzolasyon denetimi (kritik)**

```bash
cd "C:\Users\USER\Projects\gurok-mal-kabul"
# Müşteri sayfası ana proje ref'i içermemeli:
grep -c "xwytofysmgqtqjzkplfi" bar-menu.html          # 0 olmalı
# Ana projenin service key'i hiçbir repo dosyasında olmamalı:
grep -rn "service_role" bar-menu.html docs/kurulum/musteri-projesi/ | grep -iv "secret\|deploy\|comment\|--" || echo "service key sızıntısı yok"
```

- [ ] **Step 2: Uçtan uca akış (kullanıcı, canlı)**

Kullanıcı: (a) müşteri projesine bir test masa_tokenı + ana projeyle eşleşen bir test menü ürünü ekler, ana projede o ürünün stok_kodu'na stok koyar; (b) `bar-menu.html?t=<token>` açıp ürün seçip sipariş verir; (c) siparişin ana projedeki `bar-siparis-kuyrugu.html`'de belirdiğini, teslim edince stokun düştüğünü doğrular; (d) stok yetersizken sipariş verince müşteri sayfasında "Yetersiz stok" mesajının göründüğünü (hard-block'un uçtan uca çalıştığını) doğrular; (e) test verisini temizler.

- [ ] **Step 3: İlerleme kaydı + push**

`.superpowers/sdd/progress.md`'ye tamamlanma satırı; `git fetch origin` (drift) + `git push origin main`.

---

## Self-Review Notu

- **Spec kapsaması:** Spec bölüm 1 (iki-proje mimarisi) Task 1-2, bölüm 3 (QR token/oda no) Task 1 masa_tokenlari + Task 3 sayfa, bölüm 6 (köprü — WordPress maddesi düşürüldü) Task 2, bölüm 8 (müşteri RLS + rate-limit) Task 1 RLS + Task 2 Edge Function limitleri. Menü yayınlama otomasyonu bilinçli kapsam dışı (v1 manuel), Global Constraints'te belirtildi.
- **Placeholder taraması:** `<CUSTOMER_SB_URL>`/`<CUSTOMER_ANON_KEY>`/`<CUSTOMER_PROJECT_REF>`/`<ANA_PROJE_SERVICE_ROLE_KEY>` gerçek runtime değerleridir (kullanıcı Task 1-2'de sağlar), yasak placeholder değil — her biri nereden geldiği açıkça yazıldı. Kod blokları tam.
- **Tip/isim tutarlılığı:** Edge Function `bar_siparis_olustur` çağrısı parametreleri (`p_otel_id,p_depo_id,p_masa_token,p_oda_no,p_kalemler`) ana proje imzasıyla eşleşiyor; `masa_tokenlari` sütunları (otel_id/depo_id/masa_adi) Edge Function'ın okuduğuyla, `menu_urunler.id` müşteri↔ana eşleşmesi ve sayfanın gönderdiği `menu_urun_id` ile tutarlı; endpoint yolu `functions/v1/siparis-gonder` Task 2-3 arasında aynı.
- **Güvenlik:** Müşteri sayfası ana projeye sıfır referans (Task 3 Step 3 + Task 4 Step 1 grep ile zorlanır); ana projenin anahtarları yalnız Edge Function secret'ında (tarayıcıya çıkmaz); `bar_siparis_olustur` anon izni kaldırılır. Bugünkü güvenlik dersleriyle uyumlu.
