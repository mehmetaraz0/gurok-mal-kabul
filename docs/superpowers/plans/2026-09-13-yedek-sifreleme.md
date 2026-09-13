# Yedek Şifreleme — Uygulama Planı

> **Ajan çalışanlar için:** Görev görev uygulanır. Adımlar onay kutusu (`- [ ]`) biçimindedir.

**Amaç:** Yedek dosyaları diskte şifreli dursun; çözme anahtarı makinede bulunmasın; her prova aynı zamanda anahtarın çalıştığını kanıtlasın.

**Mimari:** GnuPG ile genel anahtar şifrelemesi. Yedek betiği yalnız genel anahtarı kullanır (ikinci parola istemi yok), şifreler, alıcıyı doğrular ve düz kopyaları siler. Prova, `.gpg` girdileri geçici klasöre çözer ve iş bitince siler; gizli anahtar yoksa açık mesajla durur.

**Teknoloji:** Git for Windows ile gelen GnuPG 2.4.9 (`C:\Program Files\Git\usr\bin\gpg.exe`), PowerShell 5.1, Node.

**Spec:** `docs/superpowers/specs/2026-09-13-yedek-sifreleme-design.md`

## Global Constraints

- **Gizli anahtar ajana geçmez.** Anahtar üretimi ve parola yöneticisine taşınması kullanıcıya aittir; bu plan gizli anahtarı okumaz, kopyalamaz, yazmaz.
- **Düz metin bırakma yasağı:** şifreleme başarısızsa betik durur ve düz kopyaları siler. Sessizce düz yedek bırakmak yasaktır.
- Prova, çözülen dosyayı **işletim sistemi geçici klasörüne** yazar ve `finally` içinde siler; repoya ya da yedek klasörüne düz kopya düşmez.
- Şifreli dosya doğrulaması: `gpg --list-packets` çıktısındaki alıcı `keyid`, anahtarlıktaki **şifreleme alt anahtarının** (capability `e`) kimliğiyle eşleşmeli.
- Şifrelenecekler yalnız `*-veri-yedegi.sql` ve `*-auth-yedegi.sql`. `*-auth-sema.sql` ve `*-sayaclar.json` düz kalır.
- `.gpg` olmayan girdiler eskisi gibi çalışır (eski yedekler kullanılabilir kalsın).
- PowerShell dosyaları **salt ASCII**, backtick yok.
- Kilitli iki dosya değişecek; sonunda `hazirlik-kilidi.mjs --yaz`.

---

## Dosya yapısı

| Dosya | Sorumluluk | Değişiklik |
|---|---|---|
| `docs/kurulum/yedek-anahtari.pub.asc` | Yedeklerin alıcısı olan **genel** anahtar | Yeni (kullanıcı üretir, repoya girer) |
| `docs/kurulum/yedek-ve-sayac-al.ps1` | Yedek üretimi | Şifreleme, doğrulama, düz kopya silme, `.gpg` saklama kuralı |
| `scripts/pms-yedek-geri-yukleme-provasi.mjs` | E-5 provası | `.gpg` çözme, geçici dosya temizliği, anahtar yoksa durma |
| `docs/kurulum/URETIM-YAYIN-RUNBOOK.md` | Kayıt | §11: anahtar tatbikatı ve ölçüm |

---

### Task 1: Anahtar (kullanıcı yürütür)

**Files:**
- Create: `docs/kurulum/yedek-anahtari.pub.asc`

**Interfaces:**
- Produces: repoya girecek genel anahtar dosyası ve şifreleme alt anahtarının kimliği. Task 2 ve 3 bu dosyayı kullanır.

- [ ] **Step 1: gpg-agent'i başlat**

Bu makinede ajan kendiliğinden başlamadı; anahtar üretimi "No agent running" ile düştü. Önce:

```powershell
& 'C:\Program Files\Git\usr\bin\gpg-connect-agent.exe' /bye
```

Beklenen: "starting '/usr/bin/gpg-agent'" ve ardından istem geri gelir.

**Not:** bu adımlar **PowerShell** içindir. Yol tırnaklıysa başına `&` (çağırma operatörü) konmalıdır; `"C:\...\gpg.exe" /bye` biçimi PowerShell'de ayrıştırma hatası verir.

- [ ] **Step 2: Anahtarı üret (parolalı)**

```powershell
& 'C:\Program Files\Git\usr\bin\gpg.exe' --quick-generate-key 'Gurok ERP Yedek <yedek@dornevi.local>' default default never
```

GPG bir **parola** soracak: bu, gizli anahtarın kendi parolasıdır. Parola yöneticisinde saklanacak; buraya, konuşmaya ya da bir dosyaya yazılmaz.

- [ ] **Step 3: Genel anahtarı repoya çıkar**

```powershell
cd C:\Users\USER\Projects\gurok-mal-kabul-faz2-yayin; & 'C:\Program Files\Git\usr\bin\gpg.exe' --armor --export 'yedek@dornevi.local' | Out-File -Encoding ascii docs\kurulum\yedek-anahtari.pub.asc; (Get-Item docs\kurulum\yedek-anahtari.pub.asc).Length
```

Beklenen: sıfırdan büyük bir bayt sayısı (tipik olarak birkaç yüz bayt). `Out-File -Encoding ascii` bilinçlidir: PowerShell'in varsayılan yönlendirmesi BOM ekler ve anahtar dosyasını bozabilir.

- [ ] **Step 4: Gizli anahtarı parola yöneticisine al**

```powershell
& 'C:\Program Files\Git\usr\bin\gpg.exe' --armor --export-secret-keys 'yedek@dornevi.local' | Out-File -Encoding ascii $env:TEMP\gurok-yedek-gizli.asc
```

Bu dosyayı **parola yöneticisine ek olarak** yükleyin, parolasını da aynı kayda yazın, sonra diskteki kopyayı silin. Dosya repoya, buluta ya da e-postaya **konmaz**.

- [ ] **Step 5: Gizli anahtarı makineden sil**

```powershell
(& 'C:\Program Files\Git\usr\bin\gpg.exe' --list-keys --with-colons | Select-String '^fpr' | Select-Object -First 1).ToString().Split(':')[9]
```

çıkan parmak iziyle:

```powershell
& 'C:\Program Files\Git\usr\bin\gpg.exe' --delete-secret-keys <PARMAK_IZI>
```

Beklenen: genel anahtar anahtarlıkta kalır (şifreleme için yeterli), gizli anahtar gider. Doğrulama: `gpg --list-secret-keys` çıktısı boş.

- [ ] **Step 6: Commit**

```bash
git add docs/kurulum/yedek-anahtari.pub.asc
git commit -m "chore(pms): yedek sifreleme genel anahtari"
```

---

### Task 2: Yedek betiği şifrelesin

**Files:**
- Modify: `docs/kurulum/yedek-ve-sayac-al.ps1`

**Interfaces:**
- Consumes: `docs/kurulum/yedek-anahtari.pub.asc`.
- Produces: `<etiket>-veri-yedegi.sql.gpg`, `<etiket>-auth-yedegi.sql.gpg`. Task 3 bunları tüketir.

- [ ] **Step 1: GPG yolunu ve anahtarı çöz**

Betiğin başına, `$psqlExe` kontrolünden sonra:

```powershell
$gpgExe = 'C:\Program Files\Git\usr\bin\gpg.exe'
if (-not (Test-Path $gpgExe)) {
  Write-Host "HATA: gpg bulunamadi: $gpgExe" -ForegroundColor Red
  Write-Host 'Yedek SIFRELENMEDEN alinmaz. Git for Windows kurulu olmali.' -ForegroundColor Red
  exit 1
}
$acikAnahtar = Join-Path $PSScriptRoot 'yedek-anahtari.pub.asc'
if (-not (Test-Path $acikAnahtar)) {
  Write-Host "HATA: genel anahtar yok: $acikAnahtar" -ForegroundColor Red
  exit 1
}
& $gpgExe --batch --quiet --import $acikAnahtar 2>$null
# Sifreleme ALT anahtarinin kimligi (capability 'e'); alici dogrulamasi bununla yapilir.
$aliciKimlik = (& $gpgExe --list-keys --with-colons |
  Where-Object { $_ -like 'sub:*' } |
  ForEach-Object { $p = $_.Split(':'); if ($p[11] -like '*e*') { $p[4] } } |
  Select-Object -First 1)
if (-not $aliciKimlik) {
  Write-Host 'HATA: genel anahtarda sifreleme alt anahtari bulunamadi.' -ForegroundColor Red
  exit 1
}
```

- [ ] **Step 2: Şifreleme fonksiyonunu ekle**

`Sayac-Gecerli` fonksiyonundan sonra:

```powershell
# Dosyayi genel anahtarla sifreler, aliciyi DOGRULAR, sonra duz kopyayi siler.
# Basarisizlikta duz kopya da silinir: yarim korunmus dosya birakilmaz.
function Sifrele([string]$dosya) {
  $hedefDosya = $dosya + '.gpg'
  & $gpgExe --batch --yes --quiet --trust-model always --recipient $aliciKimlik --output $hedefDosya --encrypt $dosya
  $ok = ($LASTEXITCODE -eq 0) -and (Test-Path $hedefDosya) -and ((Get-Item $hedefDosya).Length -gt 0)
  if ($ok) {
    $paket = (& $gpgExe --list-packets $hedefDosya 2>$null) -join ' '
    if ($paket -notmatch $aliciKimlik) {
      Write-Host ('HATA: sifreli dosya beklenen aliciyi tasimiyor: ' + $hedefDosya) -ForegroundColor Red
      $ok = $false
    }
  }
  if (-not $ok) {
    foreach ($x in @($dosya, $hedefDosya)) { if (Test-Path $x) { [System.IO.File]::Delete($x) } }
    return $null
  }
  [System.IO.File]::Delete($dosya)   # duz kopya diskte KALMAZ
  return $hedefDosya
}
```

- [ ] **Step 3: Başarı bloğunda şifrele**

Saklama temizliğinden **önce**, `$vy = Get-Item $veriYedegi` satırından **önce**:

```powershell
  $veriSifreli = Sifrele $veriYedegi
  $authSifreli = Sifrele $authVeri
  if (-not $veriSifreli -or -not $authSifreli) {
    Write-Host ''
    Write-Host 'SIFRELEME BASARISIZ. Duz kopyalar silindi; yedek alinmadi.' -ForegroundColor Red
    Write-Host 'Genel anahtari ve gpg kurulumunu kontrol edip tekrar deneyin.' -ForegroundColor Red
    exit 1
  }
```

- [ ] **Step 4: Özeti şifreli dosyalara göre yaz**

`$vy = Get-Item $veriYedegi` ve auth satırları şifreli yollara çevrilir:

```powershell
  $vy = Get-Item $veriSifreli
  $sy = Get-Item $sayacDosya
  $hash = (Get-FileHash $veriSifreli -Algorithm SHA256).Hash
```

ve auth satırları:

```powershell
  Write-Host ('  auth yedegi : ' + $authSifreli + '  (' + (Get-Item $authSifreli).Length + ' bayt, SIFRELI)')
  Write-Host ('  auth SHA-256: ' + (Get-FileHash $authSifreli -Algorithm SHA256).Hash)
```

Uyarı metni de güncellenir: dosya şifrelidir, ama **gizli anahtar olmadan açılamaz** — anahtar parola yöneticisindedir.

- [ ] **Step 5: Saklama kuralını `.gpg` adlarına taşı**

Desenler `*-auth-yedegi.sql.gpg` ve `*-auth-sema.sql` olur (şema düz kalır):

```powershell
  @(Get-ChildItem -Path $Hedef -Filter '*-auth-yedegi.sql.gpg' -ErrorAction SilentlyContinue) +
  @(Get-ChildItem -Path $Hedef -Filter '*-auth-yedegi.sql'     -ErrorAction SilentlyContinue) +
  @(Get-ChildItem -Path $Hedef -Filter '*-auth-sema.sql'       -ErrorAction SilentlyContinue) | ForEach-Object {
    if ($_.FullName -ne $authSifreli -and $_.FullName -ne $authSema) {
```

(Eski düz `.sql` auth yedekleri de böylece temizlenir.)

- [ ] **Step 6: Üzerine yazma kontrolüne `.gpg` yollarını ekle**

```powershell
foreach ($f in @($veriYedegi, $sayacDosya, $authVeri, $authSema, ($veriYedegi + '.gpg'), ($authVeri + '.gpg'))) {
```

- [ ] **Step 7: Sözdizimi ve ASCII**

```bash
powershell -NoProfile -Command "$e=$null;$t=$null;[System.Management.Automation.Language.Parser]::ParseFile('docs/kurulum/yedek-ve-sayac-al.ps1',[ref]$t,[ref]$e)|Out-Null; if($e.Count -eq 0){'SOZDIZIMI OK'}else{$e|%{$_.Message}}"
node -e "const b=require('fs').readFileSync('docs/kurulum/yedek-ve-sayac-al.ps1');console.log('ascii-disi:',[...b].filter(x=>x>127).length)"
```

- [ ] **Step 8: Yerel uçtan uca deneme**

Task 1'deki gerçek anahtarla, yerel konteynere karşı (`-YerelDeneme`). Beklenen: `-veri-yedegi.sql.gpg` ve `-auth-yedegi.sql.gpg` üretilir, **düz `.sql` kopyalar yoktur**, sayaç ve auth şeması düz durur.

Ek kontrol — şifreli dosyada düz metin sızıntısı olmadığı:

```bash
grep -c "INSERT INTO\|COPY " "<hedef>/<etiket>-veri-yedegi.sql.gpg" || echo "sizinti yok"
```

- [ ] **Step 9: Commit**

```bash
git add docs/kurulum/yedek-ve-sayac-al.ps1
git commit -m "feat(pms): yedekleri genel anahtarla sifrele"
```

---

### Task 3: Prova şifreli dosyayı çözsün

**Files:**
- Modify: `scripts/pms-yedek-geri-yukleme-provasi.mjs`

**Interfaces:**
- Consumes: `.gpg` uzantılı girdiler; gizli anahtar kullanıcı tarafından içe aktarılmış olmalı.
- Produces: çözme süresi satırı; anahtar yoksa açık hata ve çıkış kodu 1.

- [ ] **Step 1: Çözme yardımcısını ekle**

`const sn = ...` satırından sonra:

```js
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { unlinkSync } from 'node:fs';

const GPG = 'C:\\Program Files\\Git\\usr\\bin\\gpg.exe';
const gecici = [];          // silinecek cozulmus dosyalar
let cozmeSn = '0.0';

// .gpg girdiyi GECICI klasore cozer. Duz kopya yedek klasorune ya da repoya
// DUSMEZ; islem sonunda finally icinde silinir.
function coz(yol) {
  if (!yol || !/\.gpg$/i.test(yol)) return yol;
  const t0 = Date.now();
  spawnSync('C:\\Program Files\\Git\\usr\\bin\\gpg-connect-agent.exe', ['/bye'],
    { encoding: 'utf8', timeout: 60000 });
  const hedef = join(tmpdir(), 'pms-coz-' + process.pid + '-' + gecici.length + '.sql');
  const r = spawnSync(GPG, ['--batch', '--yes', '--quiet', '--output', hedef, '--decrypt', yol],
    { encoding: 'utf8', timeout: 600000 });
  if (r.status !== 0 || !existsSync(hedef)) {
    const hata = String(r.stderr || '');
    console.error('COZME BASARISIZ: ' + yol);
    if (/No secret key/i.test(hata)) {
      console.error('  Gizli anahtar bu makinede YOK. Parola yoneticisinden ice aktarin:');
      console.error('    gpg --import <gizli-anahtar.asc>');
      console.error('  Prova bittikten sonra: gpg --delete-secret-keys <parmak-izi>');
    } else {
      console.error('  ' + hata.split('\n').filter((l) => l.trim()).slice(-2).join(' | '));
    }
    process.exit(1);
  }
  gecici.push(hedef);
  cozmeSn = (Number(cozmeSn) + Number(sn(t0))).toFixed(1);
  return hedef;
}

function geciciTemizle() {
  for (const g of gecici) {
    try { unlinkSync(g); }
    catch (e) { console.error('UYARI: cozulmus gecici dosya silinemedi: ' + g); }
  }
}
```

- [ ] **Step 2: Girdileri çöz**

Konteyner başlatıldıktan sonra, ilk kullanım yerlerinden önce:

```js
const yedekYolu = coz(yedek);
const semaYolu = semaDosyasi;             // sema dosyalari sifrelenmez
const authVeriYolu = coz(authVeri);
const authSemaYolu = authSema;
```

Sonraki tüm `readFileSync(yedek, ...)` çağrıları `yedekYolu`, `readFileSync(authVeri, ...)` çağrıları `authVeriYolu` olur. `statSync(yedek)` boyut raporu **şifreli** dosyayı göstermeye devam eder (kullanıcı diskteki gerçek dosyayı görsün).

- [ ] **Step 3: Her çıkışta temizle**

`process.exit` çağrılarından önce ve sonuç bloğunun sonunda `geciciTemizle()` çağrılır. En sağlamı:

```js
process.on('exit', geciciTemizle);
```

- [ ] **Step 4: Süre satırı**

```js
if (gecici.length) console.log('  cozme (' + gecici.length + ' dosya)         : ' + cozmeSn + ' sn');
```

- [ ] **Step 5: Sözdizimi**

```bash
node --check scripts/pms-yedek-geri-yukleme-provasi.mjs && node scripts/check.mjs
```

- [ ] **Step 6: Anahtar yokken başarısızlığı doğrula**

Gizli anahtar makinede yokken provayı `.gpg` girdiyle çalıştırın.

Beklenen: "COZME BASARISIZ", "Gizli anahtar bu makinede YOK" yönergesi ve çıkış kodu 1. Geçici klasörde artık dosya kalmamalı.

- [ ] **Step 7: Commit**

```bash
git add scripts/pms-yedek-geri-yukleme-provasi.mjs
git commit -m "feat(pms): prova sifreli yedegi cozerek kossun"
```

---

### Task 4: Gerçek yedekle tatbikat ve kayıt

**Files:**
- Modify: `docs/kurulum/URETIM-YAYIN-RUNBOOK.md`
- Modify: `docs/kurulum/2026-09-13-hazirlik-kilidi.json`

- [ ] **Step 1: Kullanıcı şifreli yedeği alır**

```powershell
cd C:\Users\USER\Projects\gurok-mal-kabul-faz2-yayin; .\docs\kurulum\yedek-ve-sayac-al.ps1 -Etiket 2026-09-13-sifreli
```

Beklenen: iki `.gpg` dosyası, düz `.sql` yok, sayaç ve auth şeması düz.

- [ ] **Step 2: Anahtar tatbikatı + prova**

Kullanıcı gizli anahtarı parola yöneticisinden içe aktarır; ajan koşar; prova `.gpg` girdilerle koşulur ve **geçer**; ardından gizli anahtar makineden silinir.

- [ ] **Step 3: Runbook §11**

Yazılacaklar: anahtar modeli, hangi dosyaların şifrelendiği, tatbikat komutları, ölçülen süreler (çözme dâhil), ve "gizli anahtar makinede tutulmaz" kuralı.

- [ ] **Step 4: Kilidi yenile ve commit**

```bash
node scripts/hazirlik-kilidi.mjs --yaz && node scripts/hazirlik-kilidi.mjs
git add docs/ && git commit -m "docs(pms): yedek sifreleme kaydi ve kilit"
```

---

## Plan öz denetimi

- **Spec kapsamı:** anahtar üretimi ve saklama (T1), hangi dosyaların şifrelendiği (T2/S3), alıcı doğrulaması (T2/S2), düz kopya silme ve fail-closed (T2/S2–S3), saklama kuralı (T2/S5), provanın çözmesi ve geçici dosya temizliği (T3/S1–S3), anahtar yokken açık hata (T3/S1, S6), çözme süresi (T3/S4), tatbikat ve kayıt (T4). Karşılıksız madde yok.
- **Yer tutucu taraması:** yok.
- **Ad tutarlılığı:** `$gpgExe`, `$acikAnahtar`, `$aliciKimlik`, `Sifrele`, `$veriSifreli`, `$authSifreli` (ps1); `coz`, `geciciTemizle`, `yedekYolu`, `authVeriYolu`, `cozmeSn` (prova) — tanım ve kullanım aynı.
