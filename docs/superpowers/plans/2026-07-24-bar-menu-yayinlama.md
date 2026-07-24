# Bar Menü Yayınlama Otomasyonu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Personelin bar menüsünü tek tıkla (kuyruk ekranından) ana ERP projesinden izole müşteri projesine tek yönlü, otele göre ayrılmış şekilde senkronlaması.

**Architecture:** Kuyruk ekranındaki "Menüyü Yayınla" butonu → müşteri projesindeki yeni Edge Function `menu-yayinla` → ana projeden aktif menüyü service_role ile okur → müşteri projesindeki `menu_yenile(jsonb)` RPC'siyle atomik tam-değiştirme yapar. Müşteri sayfası masanın otelini `masa_oteli_getir(token)` ile çözüp menüyü o otele filtreler.

**Tech Stack:** Vanilla HTML/JS (build yok, test framework yok), Supabase REST + RLS + RPC, Supabase Edge Function (Deno/TypeScript), iki izole Supabase projesi.

## Global Constraints

- Ana proje ref `xwytofysmgqtqjzkplfi` (`MAIN_SB_URL=https://xwytofysmgqtqjzkplfi.supabase.co`). Müşteri proje ref `udjpcsjifgdzvfflezaa` (`CUSTOMER_SB_URL=https://udjpcsjifgdzvfflezaa.supabase.co`).
- Müşteri anon key (public, sayfalarda gömülü): `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVkanBjc2ppZmdkenZmZmxlemFhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQ4OTkzOTksImV4cCI6MjEwMDQ3NTM5OX0.cT-TZ5EImk2MEDuOzMuTpogYeoj8u7ovfO4C5EBM7bc`
- İki-izole-proje mimarisi korunur: `bar-menu.html` ana proje ref'i İÇERMEZ. Ana projeye tek erişim Edge Function service_role (mevcut secret'lar: MAIN_SB_URL/MAIN_SERVICE_KEY/CUSTOMER_SB_URL/CUSTOMER_SERVICE_KEY — YENİ secret gerekmez).
- `menu_yenile` RPC'si anon'a AÇILMAZ (yalnız service_role). `masa_oteli_getir` anon'a açılır ama token listesi sızdırmaz (yalnız verilen token için otel_id döner).
- Edge Function Dashboard → Via Editor ile deploy edilir (kullanıcı CLI kullanamıyor). JWT verify ON (anon key ile çağrılır).
- Kullanıcı teknik değil: SQL'ler MÜŞTERİ/ANA projenin SQL Editor'ünde kullanıcı tarafından çalıştırılır; Edge Function kullanıcı tarafından deploy edilir; curl doğrulamaları controller tarafından yapılır.
- Commit: `git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com"`. Her task öncesi `git fetch origin` (paralel oturum ortak repo).
- Kapsam DIŞI: menü yönetim ekranı (menü SQL ile düzenlenir), iki yönlü senkron, reçete detayının müşteriye taşınması.

---

## Task 1: Müşteri Projesi Şema Eklemeleri

**Files:**
- Create: `docs/kurulum/musteri-projesi/03-menu-yayin.sql`
- Modify: `.superpowers/sdd/progress.md`

**Interfaces:**
- Produces: Müşteri projesinde `menu_urunler.otel_id` sütunu; `masa_oteli_getir(p_token text) returns text` (anon); `menu_yenile(p_menu jsonb) returns integer` (service_role). Task 2 (Edge Function) `menu_yenile`'yi, Task 4 (sayfa) `masa_oteli_getir`'i + `otel_id`'yi tüketir.

- [ ] **Step 1: Şema SQL dosyasını oluştur**

`docs/kurulum/musteri-projesi/03-menu-yayin.sql`:

```sql
-- Bar menü yayınlama — müşteri projesi şema eklemeleri. MÜŞTERİ projesinde çalıştırılır.
begin;

-- menü ürününe otel bilgisi
alter table public.menu_urunler add column if not exists otel_id text;

-- Masa→otel çözümü: yalnız BİLİNEN token için otel_id döner (token listesi sızdırmaz).
create or replace function public.masa_oteli_getir(p_token text)
returns text language sql stable security definer set search_path = public
as $$ select otel_id from public.masa_tokenlari where token = p_token and aktif = true $$;
grant execute on function public.masa_oteli_getir(text) to anon;

-- Atomik menü değiştirme (yalnız Edge Function service_role çağırır; anon'a AÇILMAZ)
create or replace function public.menu_yenile(p_menu jsonb)
returns integer language plpgsql security definer set search_path = public
as $$
declare v_sayi integer;
begin
  delete from public.menu_urunler;
  insert into public.menu_urunler (id, ad, kategori, fiyat, ucretli, aktif, otel_id)
  select (x->>'id')::uuid, x->>'ad', x->>'kategori', (x->>'fiyat')::numeric,
         (x->>'ucretli')::boolean, (x->>'aktif')::boolean, x->>'otel_id'
  from jsonb_array_elements(p_menu) x;
  get diagnostics v_sayi = row_count;
  return v_sayi;
end $$;
-- menu_yenile için anon GRANT YOK — varsayılan olarak public'e kapalı bırakılır.

commit;
```

- [ ] **Step 2: Kullanıcı MÜŞTERİ projesinde çalıştırır**

Kullanıcı `03-menu-yayin.sql`'i müşteri projesinin SQL Editor'ünde çalıştırır. "Çalıştı" onayı bekle.

- [ ] **Step 3: curl ile doğrula (controller)**

```bash
C_URL='https://udjpcsjifgdzvfflezaa.supabase.co'
C_KEY='eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVkanBjc2ppZmdkenZmZmxlemFhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQ4OTkzOTksImV4cCI6MjEwMDQ3NTM5OX0.cT-TZ5EImk2MEDuOzMuTpogYeoj8u7ovfO4C5EBM7bc'
# otel_id sütunu var mı (boş [] dönerse sütun var demektir):
curl -s "$C_URL/rest/v1/menu_urunler?select=id,otel_id&limit=1" -H "apikey: $C_KEY" -H "Authorization: Bearer $C_KEY"
# masa_oteli_getir anon çağrılabilmeli (olmayan token → null):
curl -s -X POST "$C_URL/rest/v1/rpc/masa_oteli_getir" -H "apikey: $C_KEY" -H "Authorization: Bearer $C_KEY" -H "Content-Type: application/json" -d '{"p_token":"yok-123"}'
# menu_yenile anon'a KAPALI olmalı (42501):
curl -s -X POST "$C_URL/rest/v1/rpc/menu_yenile" -H "apikey: $C_KEY" -H "Authorization: Bearer $C_KEY" -H "Content-Type: application/json" -d '{"p_menu":[]}'
```

Beklenen: menu_urunler select `[]` (otel_id kolonu var), masa_oteli_getir `null`, menu_yenile `42501 permission denied`.

- [ ] **Step 4: Commit**

```bash
git add docs/kurulum/musteri-projesi/03-menu-yayin.sql
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: bar menü yayın şeması (menu_urunler.otel_id + masa_oteli_getir + menu_yenile)"
```

İlerleme kaydı ekle.

---

## Task 2: Edge Function `menu-yayinla`

**Files:**
- Create: `docs/kurulum/musteri-projesi/menu-yayinla/index.ts`
- Modify: `.superpowers/sdd/progress.md`

**Interfaces:**
- Consumes: Task 1'in `menu_yenile(p_menu jsonb)` RPC'si; ana projenin `menu_urunler` tablosu (MAIN_SERVICE_KEY ile).
- Produces: `https://udjpcsjifgdzvfflezaa.supabase.co/functions/v1/menu-yayinla` endpoint'i. POST (gövde boş `{}`) → `{ok:true, sayi:N}` veya `{ok:false, mesaj}`. Task 3 (buton) bunu çağırır.

- [ ] **Step 1: Edge Function kaynağını oluştur**

`docs/kurulum/musteri-projesi/menu-yayinla/index.ts`:

```typescript
// Supabase Edge Function: menu-yayinla
// Ana ERP projesindeki aktif menüyü okur (service_role), müşteri projesindeki
// menu_yenile RPC'siyle atomik tam-değiştirme yapar. Yeni secret gerekmez.
// Deploy: Dashboard → Edge Functions → Via Editor, ad "menu-yayinla", JWT verify ON.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

Deno.serve(async (req) => {
  const cors = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ ok: false, mesaj: "POST bekleniyor" }, 405, cors);

  const mainUrl = Deno.env.get("MAIN_SB_URL")!;
  const mainKey = Deno.env.get("MAIN_SERVICE_KEY")!;
  const custUrl = Deno.env.get("CUSTOMER_SB_URL")!;
  const custKey = Deno.env.get("CUSTOMER_SERVICE_KEY")!;

  // 1) Ana projeden aktif menüyü oku
  const main = createClient(mainUrl, mainKey);
  const { data: menu, error: mErr } = await main
    .from("menu_urunler")
    .select("id,ad,kategori,fiyat,ucretli,aktif,otel_id")
    .eq("aktif", true).eq("silindi", false);
  if (mErr) return json({ ok: false, mesaj: "Ana menü okunamadı: " + mErr.message }, 200, cors);

  // 2) Müşteri projesinde atomik değiştir
  const cust = createClient(custUrl, custKey);
  const { data: sayi, error: rErr } = await cust.rpc("menu_yenile", { p_menu: menu ?? [] });
  if (rErr) return json({ ok: false, mesaj: "Yayın hatası: " + rErr.message }, 200, cors);

  return json({ ok: true, sayi }, 200, cors);
});

function json(obj: unknown, status: number, cors: Record<string, string>) {
  return new Response(JSON.stringify(obj), {
    status, headers: { ...cors, "Content-Type": "application/json" },
  });
}
```

- [ ] **Step 2: Kullanıcıya deploy adımlarını ver**

Kullanıcıya (Dashboard, CLI yok):
1. Müşteri projesi → Edge Functions → "Deploy a new function" → "Via Editor" → "Open Editor".
2. Fonksiyon adı: `menu-yayinla`.
3. Örnek kodu sil, yukarıdaki `index.ts`'i yapıştır → Deploy.
4. Secret gerekmez (mevcut 4 secret zaten tanımlı). JWT verify ON kalabilir.

- [ ] **Step 3: curl ile doğrula (controller)**

```bash
C_URL='https://udjpcsjifgdzvfflezaa.supabase.co'
C_KEY='eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ 9...'  # yukarıdaki müşteri anon key
# Yayınla — ana projede aktif menü kaç ürünse o sayı dönmeli (test verisi yoksa 0):
curl -s -X POST "$C_URL/functions/v1/menu-yayinla" -H "apikey: $C_KEY" -H "Authorization: Bearer $C_KEY" -H "Content-Type: application/json" -d '{}'
```

Beklenen: `{"ok":true,"sayi":N}` (N = ana projedeki aktif menü ürünü sayısı; test verisi yoksa 0). Not: gerçek doğrulama Task 5'te test verisiyle yapılır.

- [ ] **Step 4: Commit**

```bash
git add docs/kurulum/musteri-projesi/menu-yayinla/index.ts
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: menu-yayinla Edge Function (ana→müşteri menü senkron köprüsü)"
```

İlerleme kaydı ekle.

---

## Task 3: Kuyruk Ekranı "Menüyü Yayınla" Butonu

**Files:**
- Modify: `bar-siparis-kuyrugu.html` (header'a buton + sabitler + `menuYayinla()` fonksiyonu + init'te görünürlük)
- Modify: `.superpowers/sdd/progress.md`

**Interfaces:**
- Consumes: Task 2'nin `functions/v1/menu-yayinla` endpoint'i. Mevcut `yazabilir()`, `toast()`, `sLD()`/`hLD()` yardımcıları.

- [ ] **Step 1: Müşteri sabitlerini ekle**

`bar-siparis-kuyrugu.html` içinde, `let CU=null, ...` satırının (mevcut ~satır 70) hemen ÜSTÜNE ekle:

```javascript
const CUSTOMER_SB_URL='https://udjpcsjifgdzvfflezaa.supabase.co';
const CUSTOMER_ANON_KEY='eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVkanBjc2ppZmdkenZmZmxlemFhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQ4OTkzOTksImV4cCI6MjEwMDQ3NTM5OX0.cT-TZ5EImk2MEDuOzMuTpogYeoj8u7ovfO4C5EBM7bc';
```

- [ ] **Step 2: Header'a Yayınla butonu ekle**

`bar-siparis-kuyrugu.html`'de Yenile butonunun (mevcut ~satır 52, `onclick="yukle()"`) hemen ÖNCESİNE ekle:

```html
    <button class="header-btn" id="yayinlaBtn" onclick="menuYayinla()" title="Menüyü Yayınla" style="display:none">📢</button>
```

- [ ] **Step 3: `menuYayinla()` fonksiyonunu ekle**

`bar-siparis-kuyrugu.html`'de `iptalEt` fonksiyonunun (mevcut ~satır 159) hemen ARDINA ekle:

```javascript
async function menuYayinla(){
  if(!yazabilir()){ toast('⚠️ Yetkiniz yok'); return; }
  if(!confirm('Müşteri menüsü ana projedeki güncel menüyle değiştirilecek. Devam?')) return;
  sLD();
  try{
    const r=await fetch(CUSTOMER_SB_URL+'/functions/v1/menu-yayinla',{
      method:'POST',
      headers:{apikey:CUSTOMER_ANON_KEY, Authorization:'Bearer '+CUSTOMER_ANON_KEY, 'Content-Type':'application/json'},
      body:'{}'
    });
    const d=await r.json(); hLD();
    if(d.ok) toast('✅ '+d.sayi+' ürün yayınlandı');
    else toast('❌ '+(d.mesaj||'Yayın hatası'));
  }catch(e){ hLD(); toast('❌ Bağlantı hatası'); }
}
```

- [ ] **Step 4: Butonu yetkiye göre göster**

`bar-siparis-kuyrugu.html`'de init içinde `YETKI_HARITASI=await kullaniciYetkileriGetir();` satırının (mevcut ~satır 167) hemen ARDINA ekle:

```javascript
  if(yazabilir()) document.getElementById('yayinlaBtn').style.display='';
```

- [ ] **Step 5: Statik doğrulama + tarayıcı**

Sözdizimi/görünürlük kontrolü:
```bash
cd "C:/Users/USER/Projects/gurok-mal-kabul"
grep -c "menuYayinla\|yayinlaBtn\|CUSTOMER_SB_URL" bar-siparis-kuyrugu.html   # >=4 olmalı
node -e "require('fs').readFileSync('bar-siparis-kuyrugu.html','utf8')" && echo "dosya okunur"
```
Beklenen: grep ≥ 4. Görsel test Task 5'te (yetkili kullanıcı butonu görür, yetkisiz görmez).

- [ ] **Step 6: Commit**

```bash
git add bar-siparis-kuyrugu.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: kuyruk ekranına Menüyü Yayınla butonu"
```

İlerleme kaydı ekle.

---

## Task 4: Müşteri Sayfası Otel Filtresi

**Files:**
- Modify: `bar-menu.html` (`menuYukle()` fonksiyonu — otel çözümü + filtreli fetch)
- Modify: `.superpowers/sdd/progress.md`

**Interfaces:**
- Consumes: Task 1'in `masa_oteli_getir(p_token)` RPC'si + `menu_urunler.otel_id` sütunu.

- [ ] **Step 1: `menuYukle()`'yi otel filtresiyle değiştir**

`bar-menu.html`'deki mevcut `menuYukle` fonksiyonunu (mevcut ~satır 48-56) tamamen şununla değiştir:

```javascript
async function menuYukle(){
  // 1) Masanın otelini çöz (token listesi sızdırmayan RPC)
  let otelId=null;
  try{
    const rr=await fetch(CUSTOMER_SB_URL+'/rest/v1/rpc/masa_oteli_getir',{
      method:'POST', headers:H, body:JSON.stringify({p_token:token})
    });
    if(rr.ok) otelId=await rr.json();
  }catch(e){}
  if(!otelId){ document.getElementById('liste').innerHTML='<div class="mesaj err">Geçersiz masa — otel bulunamadı.</div>'; return; }
  // 2) O otele ait aktif menüyü çek
  try{
    const r = await fetch(CUSTOMER_SB_URL + '/rest/v1/menu_urunler?select=*&otel_id=eq.'+encodeURIComponent(otelId)+'&aktif=eq.true&order=kategori', { headers: H });
    if(r.ok) MENU = await r.json();
  }catch(e){}
  render();
}
```

- [ ] **Step 2: Statik doğrulama**

```bash
cd "C:/Users/USER/Projects/gurok-mal-kabul"
grep -c "masa_oteli_getir\|otel_id=eq" bar-menu.html          # >=2 olmalı
grep -c "xwytofysmgqtqjzkplfi" bar-menu.html                  # 0 (izolasyon korunur)
```
Beklenen: ilk grep ≥ 2, ikinci grep 0.

- [ ] **Step 3: Commit**

```bash
git add bar-menu.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: müşteri menü sayfası otel filtresi (masa_oteli_getir)"
```

İlerleme kaydı ekle.

---

## Task 5: Uçtan Uca Doğrulama + Push

**Files:**
- Modify: `.superpowers/sdd/progress.md`

**Interfaces:**
- Consumes: Task 1-4.

- [ ] **Step 1: Test verisi kur (kullanıcı, iki proje)**

Kullanıcı ANA `erp` projesinde çalıştırır (810 + 811 için birer menü + stok):
```sql
begin;
insert into public.urunler (kod, ad, birim) values
  ('MY_TEST_KOLA','MY Test Kola','ADET'),('MY_TEST_CAY','MY Test Çay','ADET')
  on conflict (kod) do nothing;
insert into public.stok (urun_kodu, depo_kodu, otel_id, miktar) values
  ('MY_TEST_KOLA','100','810',50),('MY_TEST_CAY','300','811',50);
insert into public.menu_urunler (id, ad, kategori, otel_id, fiyat, aktif, ucretli, tip, stok_kodu, miktar_per_porsiyon) values
  ('20000000-0000-0000-0000-000000000001','MY Test Kola','İçecek','810',60,true,true,'direkt','MY_TEST_KOLA',1),
  ('20000000-0000-0000-0000-000000000002','MY Test Çay','Sıcak','811',15,false,true,'direkt','MY_TEST_CAY',1);
commit;
```
Kullanıcı MÜŞTERİ projesinde bir test masası ekler (810):
```sql
insert into public.masa_tokenlari (token, otel_id, depo_id, masa_adi)
  values ('my-test-masa-810','810','100','MY Test Masa 810');
```

- [ ] **Step 2: Yayınla + doğrula (controller curl)**

```bash
C_URL='https://udjpcsjifgdzvfflezaa.supabase.co'
C_KEY='<müşteri anon key>'
# Yayınla (2 aktif ürün bekleniyor):
curl -s -X POST "$C_URL/functions/v1/menu-yayinla" -H "apikey: $C_KEY" -H "Authorization: Bearer $C_KEY" -H "Content-Type: application/json" -d '{}'
# 810 masasının oteli:
curl -s -X POST "$C_URL/rest/v1/rpc/masa_oteli_getir" -H "apikey: $C_KEY" -H "Authorization: Bearer $C_KEY" -H "Content-Type: application/json" -d '{"p_token":"my-test-masa-810"}'
# 810 menüsü (yalnız Kola gelmeli, Çay 811'de):
curl -s "$C_URL/rest/v1/menu_urunler?select=ad,otel_id&otel_id=eq.810&aktif=eq.true" -H "apikey: $C_KEY" -H "Authorization: Bearer $C_KEY"
```
Beklenen: yayınla `{"ok":true,"sayi":2}`; masa_oteli_getir `"810"`; 810 menüsü yalnız `MY Test Kola`.

- [ ] **Step 3: Pasif→tekrar yayınla doğrulaması (kullanıcı + controller)**

Kullanıcı ANA projede: `update public.menu_urunler set aktif=false where id='20000000-0000-0000-0000-000000000002';` Sonra controller tekrar yayınlar:
```bash
curl -s -X POST "$C_URL/functions/v1/menu-yayinla" -H "apikey: $C_KEY" -H "Authorization: Bearer $C_KEY" -H "Content-Type: application/json" -d '{}'
# Müşteride artık 1 ürün olmalı:
curl -s "$C_URL/rest/v1/menu_urunler?select=ad" -H "apikey: $C_KEY" -H "Authorization: Bearer $C_KEY"
```
Beklenen: yayınla `{"ok":true,"sayi":1}`; müşteri menüsü yalnız `MY Test Kola` (pasif Çay kayboldu).

- [ ] **Step 4: İzolasyon denetimi**

```bash
cd "C:/Users/USER/Projects/gurok-mal-kabul"
grep -c "xwytofysmgqtqjzkplfi" bar-menu.html    # 0 olmalı
```

- [ ] **Step 5: Test verisi temizliği (kullanıcı)**

ANA projede: `delete from menu_urunler where id in ('20000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000002'); delete from stok where urun_kodu in ('MY_TEST_KOLA','MY_TEST_CAY'); delete from urunler where kod in ('MY_TEST_KOLA','MY_TEST_CAY');`
MÜŞTERİ projesinde: `delete from masa_tokenlari where token='my-test-masa-810';` sonra son bir kez yayınla (müşteri menüsünü gerçek/boş duruma getirir).

- [ ] **Step 6: İlerleme kaydı + push**

`.superpowers/sdd/progress.md`'ye tamamlanma satırı; `git fetch origin` + `git push origin main`.

---

## Self-Review Notu

- **Spec kapsaması:** Spec Bileşen 1 (şema) → Task 1; Bileşen 2 (Edge Function) → Task 2; Bileşen 3 (kuyruk butonu) → Task 3; Bileşen 4 (sayfa filtresi) → Task 4; Test bölümü → Task 5. Tümü karşılandı.
- **Placeholder taraması:** Tüm kod blokları tam; anon key gerçek runtime değeri (public). Task 2 Step 3'teki curl'de anon key kısaltıldı ama Task 5'te tam kullanım var — controller Global Constraints'teki tam key'i kullanır.
- **Tip/isim tutarlılığı:** `menu_yenile(p_menu jsonb)→integer` Task 1'de tanımlı, Task 2'de `cust.rpc("menu_yenile",{p_menu})` ile çağrılıyor, dönüş `sayi`. `masa_oteli_getir(p_token)→text` Task 1'de tanımlı, Task 4'te `{p_token:token}` ile çağrılıyor. `menu_urunler.otel_id` Task 1'de eklenip Task 2 insert + Task 4 filtresinde kullanılıyor. Endpoint `functions/v1/menu-yayinla` Task 2-3-5'te aynı. Tutarlı.
- **Güvenlik:** `menu_yenile` anon'a kapalı (Task 1 Step 3 grep 42501); `masa_oteli_getir` yalnız verilen token için otel_id döner (enumerasyon yok); `bar-menu.html` ana proje ref'i içermez (Task 4 Step 2 + Task 5 Step 4 grep=0).
