# Auth Yedeği — Uygulama Planı

> **Ajan çalışanlar için:** Görev görev uygulanır. Adımlar onay kutusu (`- [ ]`) biçimindedir.

**Amaç:** Elle alınan yedek `auth` şemasını da kapsasın ve giriş kurtarmasının mümkün olduğu izole provada **ölçülerek** kanıtlansın.

**Mimari:** `yedek-ve-sayac-al.ps1` aynı parola istemiyle ve aynı snapshot'tan iki dosya daha üretir (auth verisi + auth şema yapısı). Geri yükleme provasına, mevcut altı aşamadan **sonra** çalışan yedinci bir aşama eklenir: iskele `auth` şeması kenara alınır, gerçek auth yüklenir, `kullanicilar.auth_user_id` ↔ `auth.users` eşleşmesi ölçülür.

**Teknoloji:** PowerShell 5.1 + pg_dump/psql; Node + Docker (izole prova). Birim test çerçevesi yoktur; doğrulama gerçek üretim yedeğiyle yapılır.

**Spec:** `docs/superpowers/specs/2026-09-13-auth-yedegi-design.md`

## Global Constraints

- **Üretime yazma YOK.** Bu iş yalnız yedek alır ve izole kopyada okur.
- Auth veri dosyası **sır taşır** (parola hash'i, e-posta, 143 oturum/token satırı). İçeriği hiçbir çıktıya, log'a ya da konuşmaya basılmaz; yalnız yol, bayt ve SHA-256 raporlanır.
- **Yalnız en yeni auth yedeği saklanır**: yeni yedek alınırken hedef klasördeki eski `*-auth-yedegi.sql` ve `*-auth-sema.sql` silinir.
- Auth şema dosyası `--no-owner --no-privileges` ile alınır (platform rolleri izole kopyada yok).
- Mevcut altı prova aşaması ve çıkış kodu davranışı **değişmez**; yedinci aşama eklenir.
- Auth yedeği verilmediğinde prova bugünkü gibi çalışır ve bugünkü kapsam uyarısını yazar.
- PowerShell dosyaları **salt ASCII** olur; ters tırnak (backtick) kullanılmaz.
- Kilitli iki dosya değiştiği için `scripts/hazirlik-kilidi.mjs --yaz` ile kilit yenilenir.

---

## Dosya yapısı

| Dosya | Sorumluluk | Değişiklik |
|---|---|---|
| `docs/kurulum/yedek-ve-sayac-al.ps1` | Yedek + sayaç üretimi | Auth dosyaları, saklama kuralı, uyarı çıktısı |
| `docs/kurulum/yedek-snapshot-surucu.sql` | Yol (A) sürücüsü | Aynı snapshot'tan iki pg_dump daha |
| `scripts/pms-yedek-geri-yukleme-provasi.mjs` | E-5 provası | Yedinci aşama + özet satırları |
| `.gitignore` | Repo koruması | `docs/kurulum/*-auth-*.sql` |
| `docs/kurulum/2026-09-11-pms-faz2-yayin-plani.md` | Yayın kararı belgesi | §1.8 kurtarma kapsamı tablosu |

---

### Task 1: Yedek betiği auth dosyalarını da üretsin

**Files:**
- Modify: `docs/kurulum/yedek-snapshot-surucu.sql` (pg_dump satırından sonra)
- Modify: `docs/kurulum/yedek-ve-sayac-al.ps1` (dosya yolları, yol A ortam değişkenleri, yol B pg_dump çağrıları, doğrulama, saklama, özet)
- Modify: `.gitignore`

**Interfaces:**
- Produces: `<Hedef>\<Etiket>-auth-yedegi.sql`, `<Hedef>\<Etiket>-auth-sema.sql`. Task 2 bu iki dosyayı `--auth-veri` ve `--auth-sema` seçenekleriyle tüketir.

- [ ] **Step 1: `.gitignore`'a auth desenini ekle**

Dosyanın sonuna:

```
docs/kurulum/*-auth-*.sql
```

- [ ] **Step 2: Sürücüye iki pg_dump daha ekle**

`docs/kurulum/yedek-snapshot-surucu.sql` içindeki mevcut `\!` satırından **sonra**, `\echo '--> sayaclar ayni snapshot icinden okunuyor...'` satırından **önce** ekleyin:

```
\echo '--> auth semasi ayni snapshot ile aliniyor (SIR TASIR)...'
\! "%PMS_PGDUMP%" -h %PMS_HOST% -p %PMS_PORT% -U %PMS_USER% -d %PMS_DB% --data-only --no-owner --schema=auth --snapshot=%PMS_SNAPSHOT% -f "%PMS_AUTH_VERI%"
\! "%PMS_PGDUMP%" -h %PMS_HOST% -p %PMS_PORT% -U %PMS_USER% -d %PMS_DB% --schema-only --no-owner --no-privileges --schema=auth --snapshot=%PMS_SNAPSHOT% -f "%PMS_AUTH_SEMA%"
```

Aynı dosyanın başlığındaki "Beklenen ortam değişkenleri" listesine `PMS_AUTH_VERI` ve `PMS_AUTH_SEMA` eklenir.

- [ ] **Step 3: ps1 — dosya yollarını tanımla**

`$sayacSonra` satırından sonra:

```powershell
$authVeri = Join-Path $Hedef ($Etiket + '-auth-yedegi.sql')
$authSema = Join-Path $Hedef ($Etiket + '-auth-sema.sql')
```

Üzerine yazma kontrolüne bu ikisi de eklenir: `foreach ($f in @($veriYedegi, $sayacDosya, $authVeri, $authSema))`.

- [ ] **Step 4: ps1 — yol (A) ortam değişkenleri**

Yol A bloğundaki `$env:PMS_VERI = $veriYedegi` satırından sonra:

```powershell
      $env:PMS_AUTH_VERI = $authVeri
      $env:PMS_AUTH_SEMA = $authSema
```

`finally` bloğundaki temizlik listesine `'PMS_AUTH_VERI','PMS_AUTH_SEMA'` eklenir.

- [ ] **Step 5: ps1 — yol (B) pg_dump çağrıları**

Yol B'de veri yedeği alındıktan **sonra**, ikinci sayaç okumasından **önce**:

```powershell
      & $pgDump -h $h -p $Port -U $Kullanici -d $Veritabani --data-only --no-owner --schema=auth -f $authVeri
      if ($LASTEXITCODE -ne 0) { Write-Host '    auth veri yedegi basarisiz' -ForegroundColor Yellow; continue }
      & $pgDump -h $h -p $Port -U $Kullanici -d $Veritabani --schema-only --no-owner --no-privileges --schema=auth -f $authSema
      if ($LASTEXITCODE -ne 0) { Write-Host '    auth sema dokumu basarisiz' -ForegroundColor Yellow; continue }
      Write-Host '    auth yedegi alindi' -ForegroundColor Green
```

- [ ] **Step 6: ps1 — üretilen auth dosyalarını doğrula**

Yol A'nın başarı kontrolüne (`Yedek-Gecerli $veriYedegi` yanına) auth dosyaları da eklenir:

```powershell
      if ($kod -ne 0 -or -not (Yedek-Gecerli $veriYedegi) -or -not (Sayac-Gecerli $sayacDosya) -or -not (Yedek-Gecerli $authVeri) -or -not (Yedek-Gecerli $authSema)) {
```

ve başarısızlık temizliğine `$authVeri, $authSema` eklenir.

- [ ] **Step 7: ps1 — eski auth yedeklerini sil (saklama kuralı)**

Başarı bloğunda, özet yazdırmadan **önce**:

```powershell
  # SAKLAMA KURALI: auth yedegi canli oturum anahtari tasir; yalniz EN YENISI
  # durur. Veri yedekleri ve sayaclar birikmeye devam eder (sir tasimazlar).
  $silinen = 0
  Get-ChildItem -Path $Hedef -Filter '*-auth-*.sql' -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.FullName -ne $authVeri -and $_.FullName -ne $authSema) {
      try { [System.IO.File]::Delete($_.FullName); $silinen++ }
      catch { Write-Host ('  UYARI: eski auth yedegi silinemedi: ' + $_.Name) -ForegroundColor Yellow }
    }
  }
```

- [ ] **Step 8: ps1 — özete auth satırlarını ekle**

`SHA-256` satırından sonra:

```powershell
  Write-Host ('  auth yedegi : ' + $authVeri + '  (' + (Get-Item $authVeri).Length + ' bayt)')
  Write-Host ('  auth SHA-256: ' + (Get-FileHash $authVeri -Algorithm SHA256).Hash)
  Write-Host ('  auth semasi : ' + $authSema + '  (' + (Get-Item $authSema).Length + ' bayt)')
  if ($silinen -gt 0) { Write-Host ('  eski auth yedegi silindi : ' + $silinen + ' dosya') -ForegroundColor DarkGray }
  Write-Host ''
  Write-Host 'DIKKAT: auth yedegi PAROLA HASH LERI ve CANLI OTURUM TOKENLARI tasir.' -ForegroundColor Yellow
  Write-Host 'Bu dosyayi paylasmayin, repoya koymayin, e-posta ile gondermeyin.' -ForegroundColor Yellow
```

Başlıktaki "Kapsam" satırı da güncellenir: `public + phase0_private VERISI + auth semasi`.

- [ ] **Step 9: Sözdizimi ve ASCII kontrolü**

```bash
powershell -NoProfile -Command "$e=$null;$t=$null;[System.Management.Automation.Language.Parser]::ParseFile('docs/kurulum/yedek-ve-sayac-al.ps1',[ref]$t,[ref]$e)|Out-Null; if($e.Count -eq 0){'SOZDIZIMI OK'}else{$e|%{$_.Message}}"
```

Beklenen: `SOZDIZIMI OK`. Ayrıca ASCII dışı bayt sayısı **0** olmalı:

```bash
node -e "const b=require('fs').readFileSync('docs/kurulum/yedek-ve-sayac-al.ps1');console.log('ascii-disi:',[...b].filter(x=>x>127).length)"
```

- [ ] **Step 10: Yerel uçtan uca deneme (üretime bağlanmadan)**

Yerel bir PostgreSQL 17 konteynerinde `auth` şeması olan bir kopya kurun ve betiği `-YerelDeneme` ile çalıştırın:

```bash
docker container rm -f pms-auth-deneme >/dev/null 2>&1; MSYS_NO_PATHCONV=1 docker run --detach --rm --name pms-auth-deneme -p 55434:5432 -e POSTGRES_PASSWORD=dogruparola --tmpfs /var/lib/postgresql/data postgres:17 >/dev/null && sleep 8 && docker exec pms-auth-deneme createdb -U postgres yerel && docker exec -i pms-auth-deneme psql -X -U postgres -d yerel -q < scripts/supabase-shim.sql && docker exec pms-auth-deneme psql -X -U postgres -d yerel -c "insert into auth.users (id) values (gen_random_uuid()), (gen_random_uuid())"
```

Sonra:

```powershell
$env:PGPASSWORD='dogruparola'; .\docs\kurulum\yedek-ve-sayac-al.ps1 -Etiket auth-deneme -Hedef $env:TEMP\auth-deneme -YerelDeneme -Sunucu localhost -Port 55434 -Kullanici postgres -Veritabani yerel
```

Beklenen: dört dosya üretilir (veri, sayaç, auth-yedegi, auth-sema), auth uyarısı yazılır, çıkış kodu 0.

- [ ] **Step 11: Saklama kuralını doğrula**

Aynı komutu `-Etiket auth-deneme2` ile tekrar çalıştırın.

Beklenen: `eski auth yedegi silindi : 2 dosya` satırı görünür; klasörde yalnız `auth-deneme2-auth-*.sql` kalır, `auth-deneme-veri-yedegi.sql` ve sayaç dosyaları **durmaya devam eder**.

- [ ] **Step 12: Konteyneri kaldır ve commit**

```bash
docker container rm -f pms-auth-deneme >/dev/null 2>&1
git add .gitignore docs/kurulum/yedek-ve-sayac-al.ps1 docs/kurulum/yedek-snapshot-surucu.sql
git commit -m "feat(pms): yedege auth semasini ekle"
```

---

### Task 2: Provaya yedinci aşama

**Files:**
- Modify: `scripts/pms-yedek-geri-yukleme-provasi.mjs` (argüman ayrıştırma, yeni aşama, süre özeti, kapsam satırları, geçme ölçütü)

**Interfaces:**
- Consumes: Task 1'in ürettiği `<etiket>-auth-yedegi.sql` ve `<etiket>-auth-sema.sql`; mevcut `d()`, `psql()`, `tek()`, `yukHatalari()`, `sn()` yardımcıları.
- Produces: `--auth-veri <dosya>` ve `--auth-sema <dosya>` seçenekleri; çıktıda "9) AUTH KURTARMA" aşaması.

- [ ] **Step 1: Argümanları ekle**

`const semaDosyasi = ...` satırından sonra:

```js
const authVeri = deger('--auth-veri') || process.env.PMS_AUTH_VERI;
const authSema = deger('--auth-sema') || process.env.PMS_AUTH_SEMA;
```

`konum` hesabındaki filtre, yeni seçeneklerin değerlerini konumsal argüman saymamalıdır:

```js
const konum = argv.filter((a, i) => !a.startsWith('--')
  && argv[i - 1] !== '--sema' && argv[i - 1] !== '--auth-veri' && argv[i - 1] !== '--auth-sema');
```

Kullanım metnine iki satır eklenir:

```
//   --auth-veri <dosya>  Auth VERI yedegi (sir tasir) — yedinci asamayi acar
//   --auth-sema <dosya>  Auth SEMA yapisi (sir tasimaz) — --auth-veri ile birlikte
```

- [ ] **Step 2: Yedinci aşamayı ekle**

`const erisimSn = sn(tErisim);` satırından **sonra**, `// --- SONUC ---` bloğundan **önce**:

```js
// --- 7) AUTH KURTARMA -------------------------------------------------------
// SIRA ONEMLI: buraya kadarki alti asama, iskele auth semasindaki auth.uid()
// sozlesmesiyle kanitlandi. Gercek auth semasi onun USTUNE yuklenirse o kanit
// gecersizlesir; bu yuzden iskele KENARA ALINIR ve gercek auth ayri kurulur.
const tAuth2 = Date.now();
let authDurum = 'atlandi';
let authGereken = 0, authEslesen = 0, authEksik = -1;
let authHatalari = [];
if (authVeri) {
  if (!authSema) {
    console.log('9) AUTH KURTARMA    : BASARISIZ — --auth-sema verilmedi, yapi olmadan veri yuklenemez');
    authDurum = 'basarisiz';
  } else if (!existsSync(authVeri) || !existsSync(authSema)) {
    console.log('9) AUTH KURTARMA    : BASARISIZ — dosya bulunamadi');
    authDurum = 'basarisiz';
  } else {
    d(psql(['-v', 'ON_ERROR_STOP=1']), 'alter schema auth rename to auth_iskele; create schema auth;');
    let r2 = d(psql(), readFileSync(authSema, 'utf8'));
    authHatalari = yukHatalari(r2.err);
    r2 = d(psql(), 'set session_replication_role = replica;\n' + readFileSync(authVeri, 'utf8'));
    authHatalari = authHatalari.concat(yukHatalari(r2.err));
    authGereken = Number(tek(
      'select count(*) from public.kullanicilar where auth_user_id is not null;'));
    authEslesen = Number(tek(
      'select count(*) from public.kullanicilar k where k.auth_user_id is not null'
      + ' and exists (select 1 from auth.users u where u.id = k.auth_user_id);'));
    authEksik = authGereken - authEslesen;
    authDurum = (authHatalari.length === 0 && authEksik === 0) ? 'gecti' : 'basarisiz';
    console.log('9) AUTH KURTARMA    : ' + authEslesen + '/' + authGereken
      + ' kimlik YEDEKTEN geldi · yukleme hatasi ' + authHatalari.length);
    for (const h of authHatalari.slice(0, 5)) console.log('   ' + h.slice(0, 160));
    if (authEksik > 0) {
      const adlar = tek("select string_agg(k.ad, ', ') from public.kullanicilar k"
        + " where k.auth_user_id is not null"
        + " and not exists (select 1 from auth.users u where u.id = k.auth_user_id);");
      console.log('   YEDEKTE KARSILIGI OLMAYAN ERP KULLANICISI: ' + adlar);
    }
  }
}
const auth2Sn = sn(tAuth2);
```

- [ ] **Step 3: Geçme ölçütünü ve özeti güncelle**

`const gecti = ...` satırına auth koşulu eklenir:

```js
const gecti = yuklemeHatalari.length === 0 && semaHatalari.length === 0 && fark === 0
  && tutarsiz === 0 && erisimSorun === 0 && fkIhlal === 0 && authDurum !== 'basarisiz';
```

Süre listesine:

```js
if (authVeri) console.log('  auth kurtarma                 : ' + auth2Sn + ' sn');
```

Kapsam satırları, auth yedeği verildiğinde farklı yazılır:

```js
if (authDurum === 'gecti') {
  console.log('KURTARMA KAPSAMI: public + phase0_private VERISI + auth semasi.');
  console.log('  Kimlikler KAPSAMDA — ' + authEslesen + '/' + authGereken
    + ' ERP kullanicisinin karsiligi yedekten geldi; sentetik kimlik gerekmedi.');
  console.log('  Bos projeye geri yuklemede giris kurtarilabilir (hedef projenin auth semasi platformdan gelir).');
} else {
  console.log('KURTARMA KAPSAMI: yedek public + phase0_private VERISIDIR.');
  console.log('  auth semasi KAPSAM DISI — kullanicilar tablosu ' + gerekenKimlik
    + ' kimlik istiyor, yedekten ' + yedektenGelenKimlik + ' geldi.');
  console.log('  Bos projeye geri yukleme GIRIS SAGLAMAZ; gecerli senaryo ayni projede veri kaybini geri almaktir.');
}
```

- [ ] **Step 4: Sözdizimi kontrolü**

```bash
node --check scripts/pms-yedek-geri-yukleme-provasi.mjs && node scripts/check.mjs
```

Beklenen: hata yok; statik kontroller geçti.

- [ ] **Step 5: Commit**

```bash
git add scripts/pms-yedek-geri-yukleme-provasi.mjs
git commit -m "feat(pms): provaya auth kurtarma asamasi"
```

---

### Task 3: Gerçek üretim yedeğiyle doğrulama

**Files:** yok (ölçüm görevi).

- [ ] **Step 1: Kullanıcı yeni yedeği alır**

```powershell
cd C:\Users\USER\Projects\gurok-mal-kabul-faz2-yayin; .\docs\kurulum\yedek-ve-sayac-al.ps1 -Etiket 2026-09-13-auth
```

Beklenen: dört dosya, auth uyarısı, çıkış kodu 0.

- [ ] **Step 2: Prova auth aşamasıyla koşulur**

```bash
node scripts/pms-yedek-geri-yukleme-provasi.mjs \
  /c/Users/USER/ERP-Yedek/2026-09-13-auth-veri-yedegi.sql \
  /c/Users/USER/ERP-Yedek/2026-09-13-auth-sayaclar.json \
  --sema /c/Users/USER/ERP-Yedek/2026-09-12-pre-faz2-sema-dokumu.sql \
  --auth-veri /c/Users/USER/ERP-Yedek/2026-09-13-auth-auth-yedegi.sql \
  --auth-sema /c/Users/USER/ERP-Yedek/2026-09-13-auth-auth-sema.sql
```

Beklenen: ilk altı aşama bugünkü gibi geçer; **9) AUTH KURTARMA: 13/13 kimlik YEDEKTEN geldi · yukleme hatasi 0**; sonuç "GERI YUKLEME PROVASI GECTI".

- [ ] **Step 3: Dosya içeriği hiçbir yere basılmadı mı**

Prova çıktısında e-posta, hash ya da token **görünmemeli**; yalnız sayılar ve gerekirse ERP kullanıcı adları.

---

### Task 4: Kayıt ve kilit

**Files:**
- Modify: `docs/kurulum/2026-09-11-pms-faz2-yayin-plani.md` (§1.8 kurtarma kapsamı tablosu)
- Modify: `docs/kurulum/URETIM-YAYIN-RUNBOOK.md` (§9 sonrası kısa kayıt)
- Modify: `docs/kurulum/2026-09-13-hazirlik-kilidi.json` (yenilenir)

- [ ] **Step 1: Yayın planındaki kapsam tablosunu güncelle**

§1.8'deki iki satırlık tabloda "Proje/veritabanı tümden kaybı" satırı şu hâle getirilir:

```markdown
| **Proje/veritabanı tümden kaybı** | İş verisi **ve kimlikler** geri gelir (auth yedeği 2026-09-13'ten beri kapsamda). Kalan sınır: hedef projenin `auth` şeması platform tarafından sağlanır; GoTrue sürüm uyumu ayrıca kontrol edilmelidir. |
```

Eski hâli silinmez; satırın altına tarihli bir not düşülür:

```markdown
> **DÜZELTME (2026-09-13):** yukarıdaki "kimse giriş yapamaz" tespiti, auth yedeği eklenmeden önceki durumu anlatır. Auth yedeği ve provanın yedinci aşaması eklendikten sonra kimlikler kapsamdadır.
```

- [ ] **Step 2: Runbook'a kısa kayıt**

`## 10. Auth yedeği — 2026-09-13` başlığıyla: ne eklendi, hangi dosyalar üretiliyor, saklama kuralı (yalnız en yeni), provanın ölçtüğü sonuç (N/N kimlik), ve dosyanın sır taşıdığı uyarısı.

- [ ] **Step 3: Kilidi yenile ve doğrula**

```bash
node scripts/hazirlik-kilidi.mjs --yaz && node scripts/hazirlik-kilidi.mjs
```

Beklenen: `HAZIRLIK KILIDI: 11 dosya AYNI`.

- [ ] **Step 4: Commit**

```bash
git add docs/
git commit -m "docs(pms): auth yedegi kaydi ve kapsam duzeltmesi"
```

---

## Plan öz denetimi

- **Spec kapsamı:** iki dosya üretimi (T1/S2–S5), saklama kuralı (T1/S7, S11), gitignore (T1/S1), uyarı çıktısı (T1/S8), yedinci aşama ve sıra gerekçesi (T2/S2), hata durumları tablosu (T2/S2 — eksik `--auth-sema`, dosya yok, yükleme hatası, eşleşmeyen > 0), atlanma davranışı (T2/S3), gerçek veriyle ölçüm (T3), kayıt ve kilit (T4). Karşılıksız spec maddesi yok.
- **Yer tutucu taraması:** yok.
- **Ad tutarlılığı:** `$authVeri`/`$authSema` (ps1), `PMS_AUTH_VERI`/`PMS_AUTH_SEMA` (ortam), `--auth-veri`/`--auth-sema` (prova), `authDurum`/`authGereken`/`authEslesen`/`authEksik` (prova) — tanımlandıkları yerle kullanıldıkları yer aynı.
