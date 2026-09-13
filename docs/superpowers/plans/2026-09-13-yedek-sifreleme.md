# Yedek Şifreleme — Uygulama Planı

> **Ajan çalışanlar için:** Görev görev uygulanır. Adımlar onay kutusu (`- [ ]`) biçimindedir.

**Amaç:** Yedek dosyaları diskte şifreli dursun; çözme anahtarı makinede bulunmasın; her prova aynı zamanda anahtarın çalıştığını kanıtlasın.

**Mimari:** OpenSSL CMS ile genel anahtar şifrelemesi (AES-256 + RSA-4096). Yedek betiği yalnız sertifikayı kullanır (ikinci parola istemi yok), şifreler, alıcıyı doğrular ve düz kopyaları siler. Prova `.enc` girdileri geçici klasöre çözer ve siler; gizli anahtar ya da parolası yoksa açık mesajla durur.

**Teknoloji:** `C:\Program Files\Git\mingw64\bin\openssl.exe` (OpenSSL 3.5.7, native Windows), PowerShell 5.1, Node.

**Spec:** `docs/superpowers/specs/2026-09-13-yedek-sifreleme-design.md`

## Global Constraints

- **Gizli anahtar ajana geçmez.** Üretimi ve parola yöneticisine taşınması kullanıcıya aittir.
- **Düz metin bırakma yasağı:** şifreleme başarısızsa betik durur ve düz kopyaları siler.
- Prova, çözülen dosyayı **geçici klasöre** yazar ve çıkışta siler; repoya ya da yedek klasörüne düz kopya düşmez.
- Alıcı doğrulaması: sertifikanın serisi (`openssl x509 -noout -serial`) şifreli dosyadaki `serialNumber: 0x…` ile eşleşmeli.
- Şifrelenecekler yalnız `*-veri-yedegi.sql` ve `*-auth-yedegi.sql`; `*-auth-sema.sql` ve `*-sayaclar.json` düz kalır.
- `.enc` olmayan girdiler eskisi gibi çalışır.
- PowerShell dosyaları **salt ASCII**, backtick yok.
- GPG kullanılmaz: Git for Windows'un GPG'si MSYS yapısıdır ve PowerShell'den çalışmaz (ölçüldü: "No Keybox daemon running").

---

### Task 1: Anahtar (kullanıcı yürütür)

**Files:** Create `docs/kurulum/yedek-anahtari.pem` (sertifika; sır değil)

- [ ] **Step 1: Anahtar çiftini üret (parolalı)**

OpenSSL'in kendi parola istemi bu terminalde **okuyamıyor** (ölçüldü: `UI routines:UI_process:processing error`). Parola PowerShell'in güvenli istemiyle alınır ve ortam değişkeniyle verilir; komut satırına ve geçmişe yazılmaz, iş biter bitmez ortamdan silinir.

```powershell
$p = Read-Host 'Gizli anahtar parolasi' -AsSecureString; $env:PMS_KEY_PASS = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($p)); & 'C:\Program Files\Git\mingw64\bin\openssl.exe' req -x509 -newkey rsa:4096 -keyout $env:TEMP\gurok-yedek-gizli.pem -out docs\kurulum\yedek-anahtari.pem -days 36500 -subj "/CN=Gurok ERP Yedek" -passout env:PMS_KEY_PASS; Remove-Item Env:\PMS_KEY_PASS
```

Bu parola gizli anahtarın parolasıdır; parola yöneticisine yazılır, konuşmaya ya da dosyaya değil. Aynı kalıp provada çözme için de kullanılır (`-passin env:`).

- [ ] **Step 2: Üretileni doğrula**

```powershell
& 'C:\Program Files\Git\mingw64\bin\openssl.exe' x509 -in docs\kurulum\yedek-anahtari.pem -noout -subject -serial -enddate
```

Beklenen: `subject=CN=Gurok ERP Yedek`, bir seri numarası ve uzak bir bitiş tarihi.

- [ ] **Step 3: Gizli anahtarı parola yöneticisine taşı**

`%TEMP%\gurok-yedek-gizli.pem` dosyasını parola yöneticisine **ek olarak** yükleyin, parolasını aynı kayda yazın. Kaydın kendisinin de yedeği olsun.

- [ ] **Step 4: Gizli anahtarı makineden sil**

```powershell
Remove-Item $env:TEMP\gurok-yedek-gizli.pem -Force; Test-Path $env:TEMP\gurok-yedek-gizli.pem
```

Beklenen: `False`.

- [ ] **Step 5: Commit**

```powershell
git add docs\kurulum\yedek-anahtari.pem; git commit -m "chore(pms): yedek sifreleme sertifikasi"
```

---

### Task 2: Yedek betiği şifrelesin

**Files:** Modify `docs/kurulum/yedek-ve-sayac-al.ps1`

**Interfaces:** Consumes `docs/kurulum/yedek-anahtari.pem`. Produces `<etiket>-veri-yedegi.sql.enc`, `<etiket>-auth-yedegi.sql.enc`.

- [ ] **Step 1: OpenSSL ve sertifikayı çöz**

`$psqlExe` kontrolünden sonra:

```powershell
$opensslExe = 'C:\Program Files\Git\mingw64\bin\openssl.exe'
if (-not (Test-Path $opensslExe)) {
  Write-Host "HATA: openssl bulunamadi: $opensslExe" -ForegroundColor Red
  Write-Host 'Yedek SIFRELENMEDEN alinmaz.' -ForegroundColor Red
  exit 1
}
$sertifika = Join-Path $PSScriptRoot 'yedek-anahtari.pem'
if (-not (Test-Path $sertifika)) {
  Write-Host "HATA: sertifika yok: $sertifika" -ForegroundColor Red
  Write-Host 'Once anahtari uretin (plan: 2026-09-13-yedek-sifreleme.md, Task 1).' -ForegroundColor Red
  exit 1
}
# Alici dogrulamasi bu seri ile yapilir: serial=58AC... -> CMS icinde 0x58AC...
$sertifikaSeri = ((& $opensslExe x509 -in $sertifika -noout -serial) -replace '^serial=', '').Trim()
```

- [ ] **Step 2: Şifreleme fonksiyonu**

```powershell
function Sifrele([string]$dosya) {
  $hedefDosya = $dosya + '.enc'
  & $opensslExe smime -encrypt -binary -aes-256-cbc -in $dosya -out $hedefDosya -outform DER $sertifika
  $ok = ($LASTEXITCODE -eq 0) -and (Test-Path $hedefDosya) -and ((Get-Item $hedefDosya).Length -gt 0)
  if ($ok) {
    $paket = ((& $opensslExe cms -cmsout -inform DER -in $hedefDosya -print 2>$null) -join ' ')
    if ($paket -notmatch [regex]::Escape($sertifikaSeri)) {
      Write-Host ('HATA: sifreli dosya beklenen aliciyi tasimiyor: ' + $hedefDosya) -ForegroundColor Red
      $ok = $false
    }
  }
  if (-not $ok) {
    foreach ($x in @($dosya, $hedefDosya)) { if (Test-Path $x) { [System.IO.File]::Delete($x) } }
    return $null
  }
  [System.IO.File]::Delete($dosya)
  return $hedefDosya
}
```

- [ ] **Step 3: Başarı bloğunda şifrele, başarısızlıkta dur**

Saklama temizliğinden önce:

```powershell
  $veriSifreli = Sifrele $veriYedegi
  $authSifreli = Sifrele $authVeri
  if (-not $veriSifreli -or -not $authSifreli) {
    Write-Host ''
    Write-Host 'SIFRELEME BASARISIZ. Duz kopyalar silindi; yedek alinmadi.' -ForegroundColor Red
    exit 1
  }
```

- [ ] **Step 4: Özet, saklama ve üzerine yazma kontrolü**

Özet şifreli yolları yazar; saklama deseni `*-auth-yedegi.sql.enc` + eski düz adlar; üzerine yazma kontrolüne `.enc` yolları eklenir.

- [ ] **Step 5: Sözdizimi, ASCII, yerel uçtan uca deneme**

Beklenen: `.sql.enc` dosyaları üretilir, düz `.sql` kalmaz, sayaç ve auth şeması düz durur, şifreli dosyada düz metin izi yoktur.

- [ ] **Step 6: Commit**

---

### Task 3: Prova çözerek koşsun

**Files:** Modify `scripts/pms-yedek-geri-yukleme-provasi.mjs`

- [ ] **Step 1: Çözme yardımcısı**

`.enc` girdiyi geçici klasöre çözer; parola `YEDEK_ANAHTAR_PAROLA` ortam değişkeninden okunur (`-passin env:`). Gizli anahtar yolu `--gizli-anahtar` ile verilir.

- [ ] **Step 2: Eksik anahtar/parola durumunda açık hata**

Mesaj, parola yöneticisinden anahtarı çıkarıp yolu ve parolayı nasıl vereceğini yazar; çıkış kodu 1.

- [ ] **Step 3: Geçici dosyaları her çıkışta sil** (`process.on('exit', ...)`)

- [ ] **Step 4: Çözme süresi satırı**

- [ ] **Step 5: Sözdizimi + anahtarsız başarısızlık denemesi**

- [ ] **Step 6: Commit**

---

### Task 4: Gerçek yedekle tatbikat ve kayıt

- [ ] **Step 1:** Kullanıcı şifreli yedeği alır.
- [ ] **Step 2:** Anahtar tatbikatı: gizli anahtar parola yöneticisinden geçici olarak indirilir, prova `.enc` girdilerle koşar ve geçer, sonra anahtar dosyası silinir.
- [ ] **Step 3:** Runbook §11: anahtar modeli, şifrelenen dosyalar, tatbikat komutları, ölçülen süreler.
- [ ] **Step 4:** `hazirlik-kilidi.mjs --yaz` ve commit.

---

## Plan öz denetimi

- **Spec kapsamı:** anahtar üretimi/saklama (T1), şifrelenecek dosyalar (T2/S3), alıcı doğrulaması (T2/S1–S2), düz kopya silme ve fail-closed (T2/S2–S3), saklama kuralı (T2/S4), provanın çözmesi ve temizliği (T3), anahtarsız açık hata (T3/S2), çözme süresi (T3/S4), tatbikat ve kayıt (T4).
- **Yer tutucu yok.** Kod gerektiren adımlarda kod var; T3 adımları uygulama sırasında ölçülen komutlarla yazılır.
- **Ad tutarlılığı:** `$opensslExe`, `$sertifika`, `$sertifikaSeri`, `Sifrele`, `$veriSifreli`, `$authSifreli`.
