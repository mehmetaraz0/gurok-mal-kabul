# Tekrarlanabilir Müşteri Kurulum Süreci Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Yeni bir otel/turizm grubuna kurulum yapmayı belgelenmiş, tekrarlanabilir bir sürece dönüştürmek: şema dökümleri + `yeni-musteri-kurulum.html` aracı + `docs/KURULUM-REHBERI.md` checklist'i.

**Architecture:** Şema/referans-veri SQL'leri canlı veritabanından dökülüp repoya alınır (tek doğru kaynak). Yeni kurulum aracı, `migrate-to-supabase.html` deseninde (service-role key yalnız çalışma anında, bellekte) çalışır ve iki iş yapar: `otel-config.js` içeriği üretmek + ilk yönetici kullanıcısını eklemek. Rehber, bu parçaları 10 adımlı sıralı bir checklist'te birleştirir.

**Tech Stack:** Vanilla HTML/JS, Supabase REST, pg_dump (şema dökümü için).

## Global Constraints

- Service-role anahtarı HİÇBİR ZAMAN localStorage'a/koda yazılmaz — yalnız sayfa açıkken bellekte (`migrate-to-supabase.html`'deki mevcut desen ve güvenlik notu birebir korunur).
- `02-referans-veri.sql` SADECE `roller`, `moduller`, `yetki_matrisi` verisini içerir — gerçek müşteri verisi (cariler, faturalar, urunler, kullanicilar...) KESİNLİKLE dökülmez (CLAUDE.md kural 10).
- Ürün kataloğu doldurma kapsam dışı — rehberde yalnızca mevcut Excel toplu veri yönetimine yönlendirme.
- Rehbere güvenlik denetimi (2026-07-21) önerisi eklenir: kurulum bitince `migrate-to-supabase.html` VE `yeni-musteri-kurulum.html` production deploy'undan kaldırılır.
- Paralel oturum aynı klasörde aktif: her task öncesi `git fetch origin` + gerekirse `git pull --ff-only`; satır numarasına değil arama kalıbına güven.
- Commit kimliği: `git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit ...`.

---

## Task 1: `yeni-musteri-kurulum.html` Aracı

**Files:**
- Create: `yeni-musteri-kurulum.html`
- Referans olarak OKU (değiştirme): `migrate-to-supabase.html` (service-key/yönetici-gate deseni), `otel-config.js` (üretilecek şablonun birebir yapısı), `kullanici-yonetimi.html` (kullanıcı INSERT payload'unun gerçek alan adları)

**Interfaces:**
- Consumes: `auth-guard.js` → `requireLogin()`, `requireRole(user,['yonetici'])`.
- Produces: bağımsız, tek seferlik kurulum sayfası. Task 2'nin rehberi bu sayfanın iki formuna (otel-config üretici + ilk yönetici) adım olarak atıf yapar.

- [ ] **Step 1: Kullanıcı INSERT payload şeklini gerçek koddan teyit et**

`Grep "rest/v1/kullanicilar" kullanici-yonetimi.html` ile kullanıcı EKLEYEN POST çağrısını bul ve gövdesindeki alan adlarını (örn. `ad`, `pin`, `rol`, `rol_id`, `otel_id`, `aktif` — gerçek liste neyse) not al. Step 2'deki `ilkYoneticiOlustur()` gövdesindeki payload'u BU gerçek alanlarla birebir eşle (aşağıdaki kod makul varsayımdır, gerçek koda göre düzelt).

- [ ] **Step 2: Dosyayı oluştur**

```html
<!DOCTYPE html>
<html lang="tr">
<head>
<meta charset="UTF-8">
<script src="auth-guard.js"></script>
<script>
let OTURUM_KULLANICI = requireLogin();
if (OTURUM_KULLANICI) requireRole(OTURUM_KULLANICI, ['yonetici']);
</script>
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Gürok — Yeni Müşteri Kurulumu</title>
<style>
:root{--primary:#15213a;--success:#27ae60;--danger:#b5442a;--gray-100:#f1f3f5;--gray-300:#dee2e6;--gray-500:#adb5bd;--gray-600:#6c757d}
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;background:var(--gray-100);font-size:13px}
.header{background:var(--primary);color:white;padding:14px 20px}
.header h1{font-size:16px}.header p{font-size:12px;opacity:.8;margin-top:2px}
.content{padding:16px;max-width:800px;margin:0 auto}
.uyari{background:#fff3cd;color:#856404;border-radius:10px;padding:12px 14px;margin-bottom:16px;font-size:12px;line-height:1.5;border:1.5px solid #fcd34d}
.card{background:white;border-radius:10px;padding:14px;margin-bottom:10px;box-shadow:0 2px 8px rgba(0,0,0,.08)}
.card-title{font-size:13px;font-weight:700;color:var(--primary);margin-bottom:8px}
.field{margin-bottom:10px}
.field label{display:block;font-size:11px;font-weight:600;color:var(--gray-600);margin-bottom:4px;text-transform:uppercase}
.field input{width:100%;padding:9px 11px;border:1.5px solid var(--gray-300);border-radius:8px;font-size:13px;outline:none}
.grid2{display:grid;grid-template-columns:1fr 1fr;gap:10px}
.btn{padding:9px 16px;border:none;border-radius:8px;font-size:12px;font-weight:600;cursor:pointer;background:var(--primary);color:white}
textarea{width:100%;min-height:220px;font-family:monospace;font-size:12px;padding:10px;border:1.5px solid var(--gray-300);border-radius:8px}
#durum{margin-left:10px;font-size:12px}
</style>
</head>
<body>
<div class="header">
  <h1>Yeni Müşteri Kurulumu</h1>
  <p>Tek seferlik araç — 01/02 SQL dökümleri BOŞ Supabase projesinde çalıştırıldıktan SONRA kullanılır. Kurulum bitince bu dosyayı deploy'dan kaldırın.</p>
</div>
<div class="content">
  <div class="uyari">⚠️ Service-role anahtarı RLS'yi bypass eder. Anahtar KALICI OLARAK SAKLANMAZ — yalnızca bu sayfa açıkken bellekte tutulur, sayfa kapanınca silinir.</div>

  <div class="card">
    <div class="card-title">1) Yeni Projenin Bağlantı Bilgileri</div>
    <div class="field"><label>Supabase Project URL</label><input type="text" id="sb-url" placeholder="https://xxxxx.supabase.co"></div>
    <div class="field"><label>Service Role Key</label><input type="password" id="sb-key" placeholder="eyJhbG..."></div>
  </div>

  <div class="card">
    <div class="card-title">2) Otel Bilgileri → otel-config.js Üret</div>
    <div class="grid2">
      <div class="field"><label>Otel 1 Kodu *</label><input id="o1-kod" required placeholder="810"></div>
      <div class="field"><label>Otel 2 Kodu (opsiyonel)</label><input id="o2-kod" placeholder="811"></div>
      <div class="field"><label>Otel 1 Adı *</label><input id="o1-ad" required placeholder="Örnek Otel Merkez"></div>
      <div class="field"><label>Otel 2 Adı</label><input id="o2-ad"></div>
      <div class="field"><label>Otel 1 Kısa Ad *</label><input id="o1-kisa" required placeholder="Merkez"></div>
      <div class="field"><label>Otel 2 Kısa Ad</label><input id="o2-kisa"></div>
      <div class="field"><label>Otel 1 Ticari Unvan *</label><input id="o1-unvan" required></div>
      <div class="field"><label>Otel 2 Ticari Unvan</label><input id="o2-unvan"></div>
      <div class="field"><label>Otel 1 Merkezi Depo Kodu *</label><input id="o1-depo" required placeholder="100"></div>
      <div class="field"><label>Otel 2 Merkezi Depo Kodu</label><input id="o2-depo" placeholder="300"></div>
    </div>
    <div class="field"><label>Grup Adı *</label><input id="grup-ad" required placeholder="Örnek Turizm Grubu"></div>
    <div class="field"><label>Dahili E-posta Domaini *</label><input id="email-domain" required placeholder="ornekotel.internal"></div>
    <button class="btn" onclick="configUret()">otel-config.js İçeriğini Üret</button>
    <div class="field" style="margin-top:10px"><label>Üretilen içerik — kopyalayıp repo kökündeki otel-config.js'e yapıştırın</label><textarea id="config-cikti" readonly></textarea></div>
  </div>

  <div class="card">
    <div class="card-title">3) İlk Yönetici Kullanıcısı</div>
    <div class="grid2">
      <div class="field"><label>Ad Soyad *</label><input id="yon-ad" required></div>
      <div class="field"><label>PIN (4-6 hane) *</label><input id="yon-pin" required maxlength="6" placeholder="1234"></div>
    </div>
    <button class="btn" onclick="ilkYoneticiOlustur()">Yöneticiyi Oluştur</button><span id="durum"></span>
  </div>
</div>

<script>
function deger(id){return document.getElementById(id).value.trim();}

function configUret(){
  const zorunlu=['o1-kod','o1-ad','o1-kisa','o1-unvan','o1-depo','grup-ad','email-domain'];
  for(const id of zorunlu){if(!deger(id)){alert('Zorunlu alan boş: '+id);return;}}
  const o1k=deger('o1-kod'),o2k=deger('o2-kod');
  const cift=o2k!=='';
  const harita=(a1,a2)=>cift?`{'${o1k}':'${a1}','${o2k}':'${a2}'}`:`{'${o1k}':'${a1}'}`;
  const icerik=`// otel-config.js — müşteriye özel kurulum sabitleri.
// Yeni bir müşteri kurulumunda SADECE bu dosya düzenlenir, başka hiçbir
// dosyaya dokunulmaz. auth-guard.js -> supabase-config.js -> otel-config.js
// -> ortak.js sırasında, senkron olarak yüklenir.

const OTEL_ISIMLERI = ${harita(deger('o1-ad'),deger('o2-ad'))};
const OTEL_KISA = ${harita(deger('o1-kisa'),deger('o2-kisa'))};
const OTEL_TICARI_UNVAN = ${harita(deger('o1-unvan'),deger('o2-unvan'))};
const GRUP_ADI = '${deger('grup-ad')}';
const DAHILI_EMAIL_DOMAIN = '${deger('email-domain')}';
const MERKEZI_DEPO = ${harita(deger('o1-depo'),deger('o2-depo'))};

function merkeziDepoKodu(otelId){ return MERKEZI_DEPO[otelId] || '${deger('o1-depo')}'; }
function otelFromDepoId(depoId){ const i=(depoId||'').indexOf('_'); return i>=0 ? depoId.slice(0,i) : '${o1k}'; }
`;
  document.getElementById('config-cikti').value=icerik;
}

async function ilkYoneticiOlustur(){
  const url=deger('sb-url').replace(/\/$/,''),key=deger('sb-key');
  const ad=deger('yon-ad'),pin=deger('yon-pin');
  const durum=document.getElementById('durum');
  if(!url||!key){durum.textContent='⚠️ Önce bağlantı bilgilerini girin';return;}
  if(!ad||!pin){durum.textContent='⚠️ Ad ve PIN zorunlu';return;}
  const h={'apikey':key,'Authorization':'Bearer '+key,'Content-Type':'application/json'};
  try{
    const rRol=await fetch(url+'/rest/v1/roller?kod=eq.sistem_admin&select=id',{headers:h});
    const roller=await rRol.json();
    if(!roller.length){durum.textContent='❌ sistem_admin rolü bulunamadı — 02-referans-veri.sql çalıştırıldı mı?';return;}
    // DİKKAT (implementer): payload alanlarını kullanici-yonetimi.html'deki gerçek
    // kullanıcı-ekleme POST gövdesiyle birebir eşle (Step 1'de not aldığın liste).
    const payload={ad,pin,rol:'yonetici',rol_id:roller[0].id,aktif:true};
    const r=await fetch(url+'/rest/v1/kullanicilar',{method:'POST',headers:{...h,'Prefer':'return=representation'},body:JSON.stringify(payload)});
    if(!r.ok){durum.textContent='❌ Hata: '+(await r.text()).slice(0,200);return;}
    durum.textContent='✅ Yönetici oluşturuldu — artık '+ad+' / PIN ile giriş yapılabilir';
  }catch(e){durum.textContent='❌ Bağlantı hatası: '+e.message;}
}
</script>
</body>
</html>
```

- [ ] **Step 3: Statik doğrulama**

Parantez dengesi + `grep -c "localStorage" yeni-musteri-kurulum.html` → `0` (anahtar hiçbir yere yazılmıyor olmalı).

- [ ] **Step 4: Commit**

```bash
git add yeni-musteri-kurulum.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: yeni-musteri-kurulum.html — otel-config üretici + ilk yönetici aracı"
```

---

## Task 2: `docs/KURULUM-REHBERI.md`

**Files:**
- Create: `docs/KURULUM-REHBERI.md`

**Interfaces:**
- Consumes: Task 1'in sayfası (adım 6-7'de atıf), Task 3'ün SQL dosya adları (`docs/kurulum/01-sema-dokumu.sql`, `docs/kurulum/02-referans-veri.sql`).

- [ ] **Step 1: Dosyayı oluştur**

```markdown
# Yeni Müşteri Kurulum Rehberi

Bu rehber, sistemi yeni bir otel/turizm grubuna sıfırdan kurmak için izlenecek
sıralı adımları tanımlar. Her adım bir öncekine bağımlıdır — sırayı bozmayın.

## Ön Koşullar
- Yeni bir Supabase hesabı/organizasyonu
- Bu reponun bir kopyası (fork veya klon)
- Statik hosting (GitHub Pages veya eşdeğeri)

## Adımlar

1. **Supabase projesi oluştur.** [supabase.com](https://supabase.com) → New Project.
   Bölge ve güçlü bir DB şifresi seçin.

2. **Şemayı kur.** Supabase SQL Editor'de `docs/kurulum/01-sema-dokumu.sql`
   dosyasının tamamını çalıştırın (tablolar, RLS policy'leri, fonksiyonlar).

3. **Referans veriyi yükle.** Aynı editörde `docs/kurulum/02-referans-veri.sql`
   dosyasını çalıştırın (roller, modüller, yetki matrisi — müşteri verisi içermez).

4. **Repoyu klonlayın** (veya fork'layın) ve yerel bir kopyada çalışın.

5. **`supabase-config.js`'i güncelleyin.** Yeni projenin URL'i ve anon (public)
   anahtarı ile (Settings → API). Service-role anahtarını ASLA bu dosyaya yazmayın.

6. **`otel-config.js`'i üretin.** `yeni-musteri-kurulum.html`'i tarayıcıda açın,
   bölüm 2'deki formu müşterinin otel bilgileriyle doldurun, üretilen içeriği
   repo kökündeki `otel-config.js`'e yapıştırıp kaydedin ve commit edin.

7. **İlk yöneticiyi oluşturun.** Aynı sayfada bölüm 1'e yeni projenin URL'i +
   service-role anahtarını girin (yalnız bellekte tutulur), bölüm 3'ten ilk
   yönetici kullanıcısını ekleyin.

8. **Deploy edin.** GitHub Pages (veya eşdeğeri) üzerinden yayınlayın; ilk
   yöneticiyle giriş yapıp portalın açıldığını doğrulayın.

9. **Modülleri ayarlayın.** `yetki-yonetimi.html`'de, müşterinin satın almadığı
   modüllerin başlığına tıklayarak pasif yapın (🔒). Pasif modül hem menülerden
   kalkar hem RLS seviyesinde kapanır.

10. **Ürün/tedarikçi kataloğunu doldurun.** Müşterinin kendi verisiyle —
    ilgili sayfalardaki Excel toplu içe aktarma özelliğini kullanın
    (`gurok_veritabani.js` içeriği de müşteri kataloğuyla değiştirilmelidir).

## Kurulum Sonrası Güvenlik (zorunlu)

- `migrate-to-supabase.html` ve `yeni-musteri-kurulum.html` dosyalarını
  production deploy'undan KALDIRIN (2026-07-21 güvenlik denetimi önerisi) —
  ikisi de service-role anahtarı kabul eden tek seferlik araçlardır.
- Service-role anahtarını hiçbir dosyaya/nota yazmadığınızı doğrulayın.
```

- [ ] **Step 2: Commit**

```bash
git add docs/KURULUM-REHBERI.md
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "docs: yeni müşteri kurulum rehberi (10 adımlı checklist)"
```

---

## Task 3: Şema ve Referans Veri Dökümleri (CONTROLLER — kullanıcı etkileşimi gerekir)

**Bu task bir subagent'a devredilmez** — kullanıcının kendi makinesinde pg_dump çalıştırması (DB şifresi gerekir) ve çıktıyı paylaşması gerekiyor.

**Files:**
- Create: `docs/kurulum/01-sema-dokumu.sql`, `docs/kurulum/02-referans-veri.sql`

- [ ] **Step 1: Kullanıcıya pg_dump komutlarını ver**

Kullanıcıdan Supabase Dashboard → Settings → Database → Connection string (URI) alıp şu iki komutu çalıştırmasını iste (şifreyi kendisi doldurur; pg_dump yoksa `winget install PostgreSQL.PostgreSQL` ile client araçları kurulabilir):

```bash
pg_dump "<CONNECTION_URI>" --schema=public --schema-only --no-owner --no-privileges > 01-sema-dokumu.sql
pg_dump "<CONNECTION_URI>" --schema=public --data-only --no-owner --table=public.roller --table=public.moduller --table=public.yetki_matrisi > 02-referans-veri.sql
```

- [ ] **Step 2: Dosyaları al, İÇERİĞİNİ DENETLE, repoya koy**

Kullanıcı dosyaları paylaşınca/`docs/kurulum/` içine koyunca: (a) `01`'de gerçek VERİ satırı (INSERT/COPY) olmadığını, (b) `02`'de YALNIZCA roller/moduller/yetki_matrisi COPY bloklarının bulunduğunu, (c) hiçbir dosyada şifre/anahtar geçmediğini grep ile doğrula. Sorun varsa kullanıcıya bildir, temiz dökümü iste.

- [ ] **Step 3: Commit + push**

```bash
git add docs/kurulum/01-sema-dokumu.sql docs/kurulum/02-referans-veri.sql
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "docs: kurulum şema ve referans veri dökümleri (canlı DB'den pg_dump)"
git push origin main
```

---

## Task 4: Uçtan Uca Doğrulama

- [ ] **Step 1: Bütünlük kontrolleri**

```bash
cd "C:\Users\USER\Projects\gurok-mal-kabul"
ls docs/kurulum/01-sema-dokumu.sql docs/kurulum/02-referans-veri.sql docs/KURULUM-REHBERI.md yeni-musteri-kurulum.html
grep -c "auth_yetki_var" docs/kurulum/01-sema-dokumu.sql          # >0: fonksiyon dökümde var
grep -c "sistem_admin" docs/kurulum/02-referans-veri.sql          # >0: rol seed'i var
grep -c "localStorage" yeni-musteri-kurulum.html                  # 0: anahtar saklanmıyor
grep -c "KALDIRIN" docs/KURULUM-REHBERI.md                        # >0: güvenlik notu var
```

- [ ] **Step 2: Kullanıcıya opsiyonel tam prova öner**

Gerçek doğrulama ancak İKİNCİ bir boş Supabase projesiyle yapılabilir (rehberi baştan sona uygulayarak). Kullanıcıya bunu ilk gerçek müşteri kurulumundan ÖNCE bir kez prova etmesini öner — zorunlu değil ama şiddetle tavsiye edilir; ledger'a "prova bekliyor" notu düş.

- [ ] **Step 3: İlerleme kaydı + push**

`.superpowers/sdd/progress.md`'ye tamamlanma satırı + "Satış stratejisi punch list'i 4/4 TAMAMLANDI" notu; `git push origin main`.

## Self-Review Notu

- **Spec kapsaması:** Spec'in 3 bölümü → Task 3 (dökümler), Task 1 (araç), Task 2 (rehber); test planı → Task 4. Güvenlik denetimi önerisi rehberin "Kurulum Sonrası Güvenlik" bölümünde.
- **Placeholder taraması:** temiz — tek bilinçli esneklik, Task 1 Step 1'in payload'u gerçek koda göre düzeltme talimatı (somut bir doğrulama adımı, boşluk değil).
- **İsim tutarlılığı:** dosya adları (`01-sema-dokumu.sql`, `02-referans-veri.sql`, `KURULUM-REHBERI.md`, `yeni-musteri-kurulum.html`) tüm task'larda birebir aynı.
