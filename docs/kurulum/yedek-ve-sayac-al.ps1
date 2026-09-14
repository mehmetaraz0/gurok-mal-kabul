# ============================================================================
# yedek-ve-sayac-al.ps1 - VERI YEDEGI + DOGRULAMA SAYACLARI (tek parola istemi)
# ============================================================================
# NEDEN: Yayin plani E-5, yedegin sayaclarla AYNI DURUMU gormesini sart kosar.
# Bu betik iki kabul edilen yolu da otomatiklestirir:
#
#   (A) AYNI SNAPSHOT  - varsayilan. Tek psql oturumunda REPEATABLE READ islemi
#       acilir, pg_export_snapshot() alinir, pg_dump AYNI snapshot ile calisir
#       ve sayaclar ayni islemden okunur.
#   (B) DOGRULANMIS YAZMA DURAKLATMASI - -Duraklatma. Sayaclar yedekten ONCE ve
#       SONRA okunur; ikisi ayni degilse yedek REDDEDILIR.
#
# Pooler snapshot disari vermeyi desteklemezse (A) basarisiz olur; betik bunu
# soyler ve (B) ile tekrar calistirmanizi ister. Tahmin yapmaz.
#
# KULLANIM (repo kokunde):
#   .\docs\kurulum\yedek-ve-sayac-al.ps1 -Etiket 2026-09-13-pre-faz2
#   .\docs\kurulum\yedek-ve-sayac-al.ps1 -Etiket 2026-09-13-pre-faz2 -Duraklatma
#
# Sifre ekranda gorunmez, komut satirina ve PowerShell gecmisine yazilmaz;
# yalnizca bu surecin PGPASSWORD ortam degiskeninde tutulur ve sonunda silinir.
#
# URETILEN DOSYALAR (REPO DISI, varsayilan C:\Users\USER\ERP-Yedek):
#   <Etiket>-veri-yedegi.sql.enc   public + phase0_private VERISI  *** SIFRELI ***
#   <Etiket>-sayaclar.json     ayni durumu temsil eden uretim sayaclari
#   <Etiket>-auth-yedegi.sql.enc   auth semasi VERISI  *** SIFRELI, SIR TASIR ***
#   <Etiket>-auth-sema.sql     auth semasi YAPISI  (sir tasimaz, prova icin)
#
# *** AUTH YEDEGI SIR TASIR ***  Parola hash'leri, e-postalar ve CANLI oturum /
# yenileme tokenlari icerir. Paylasilmaz, repoya konmaz, e-posta ile
# gonderilmez. SAKLAMA: yalniz EN YENI auth yedegi durur; yeni yedek alinirken
# hedef klasordeki eski *-auth-*.sql dosyalari SILINIR.
#
# KURTARMA KAPSAMI. Yedek public + phase0_private VERISINI ve auth semasini
# kapsar; kimlikler kapsamdadir, yani bos bir projeye geri yuklendiginde giris
# kurtarilabilir (hedef projenin auth SEMASI platformdan gelir; bu dosyadaki
# sema yalniz izole prova icindir). Kapsam disi: storage, realtime, veritabani
# rolleri ve uzantilar, proje ayarlari.
#
# ---------------------------------------------------------------------------
# BU DOSYA SALT ASCII OLMALI (dokum-al.ps1 basindaki aciklamaya bakin).
# ---------------------------------------------------------------------------

param(
  [string]$Etiket = (Get-Date -Format 'yyyy-MM-dd'),
  [string]$Hedef = $(if ($env:GUROK_YEDEK) { $env:GUROK_YEDEK } else { 'C:\Users\USER\ERP-Yedek' }),
  [switch]$Duraklatma,
  # Yalniz baglantiyi ve parolayi sinar; hicbir dosya uretmez.
  [switch]$YalnizBaglanti,
  # Yalniz yerel mekanizma denemesi icin: parola istemez, var olan PGPASSWORD
  # degerini kullanir ve YALNIZ localhost ile calisir. Uretimde kullanilmaz.
  [switch]$YerelDeneme,
  [string]$Sunucu = '',
  [int]$Port = 5432,
  [string]$Kullanici = '',
  [string]$Veritabani = 'postgres'
)

$ErrorActionPreference = 'Stop'
$NL = [string][char]10

$bin     = 'C:\Program Files\PostgreSQL\17\bin'
$pgDump  = Join-Path $bin 'pg_dump.exe'
$psqlExe = Join-Path $bin 'psql.exe'
foreach ($x in @($pgDump, $psqlExe)) {
  if (-not (Test-Path $x)) { Write-Host "HATA: bulunamadi: $x" -ForegroundColor Red; exit 1 }
}

# SIFRELEME. Yedekler diskte DUZ METIN durmaz: veri ve auth dosyalari
# sertifikayla (genel anahtar) sifrelenir, duz kopyalar silinir. Cozme anahtari
# bu makinede YOKTUR; parola yoneticisindedir.
# GPG DEGIL OpenSSL: Git for Windows'un gpg'si MSYS yapisidir ve PowerShell'den
# calismaz ("No Keybox daemon running"). Olculdu, 2026-09-13.
$opensslExe = 'C:\Program Files\Git\mingw64\bin\openssl.exe'
if (-not (Test-Path $opensslExe)) {
  Write-Host "HATA: openssl bulunamadi: $opensslExe" -ForegroundColor Red
  Write-Host 'Yedek SIFRELENMEDEN alinmaz.' -ForegroundColor Red
  exit 1
}
$sertifika = Join-Path $PSScriptRoot 'yedek-anahtari.pem'
if (-not (Test-Path $sertifika)) {
  Write-Host "HATA: sifreleme sertifikasi yok: $sertifika" -ForegroundColor Red
  Write-Host 'Once anahtari uretin: docs/superpowers/plans/2026-09-13-yedek-sifreleme.md (Task 1).' -ForegroundColor Red
  exit 1
}
# Alici dogrulamasi bu seri ile yapilir: serial=086416... -> CMS icinde 0x086416...
$sertifikaSeri = ((& $opensslExe x509 -in $sertifika -noout -serial) -replace '^serial=', '').Trim()
if (-not $sertifikaSeri) {
  Write-Host "HATA: sertifikanin serisi okunamadi: $sertifika" -ForegroundColor Red
  exit 1
}

$surucu   = Join-Path $PSScriptRoot 'yedek-snapshot-surucu.sql'
$sayacSql = Join-Path $PSScriptRoot '2026-09-13-yedek-dogrulama-sayaclari.sql'
foreach ($x in @($surucu, $sayacSql)) {
  if (-not (Test-Path $x)) { Write-Host "HATA: bulunamadi: $x" -ForegroundColor Red; exit 1 }
}

$projectRef = 'xwytofysmgqtqjzkplfi'
$region     = 'ap-northeast-1'

if ($Sunucu) { $sunucular = @($Sunucu) }
else { $sunucular = @("aws-0-$region.pooler.supabase.com", "aws-1-$region.pooler.supabase.com") }
if (-not $Kullanici) { $Kullanici = "postgres.$projectRef" }

if ($YerelDeneme) {
  if ($sunucular.Count -ne 1 -or ($sunucular[0] -ne 'localhost' -and $sunucular[0] -ne '127.0.0.1')) {
    Write-Host 'HATA: -YerelDeneme yalniz localhost ile kullanilir.' -ForegroundColor Red; exit 1
  }
}

if (-not (Test-Path $Hedef)) { New-Item -ItemType Directory -Path $Hedef | Out-Null }
$veriYedegi = Join-Path $Hedef ($Etiket + '-veri-yedegi.sql')
$sayacDosya = Join-Path $Hedef ($Etiket + '-sayaclar.json')
$sayacOnce  = Join-Path $Hedef ($Etiket + '-sayaclar-once.json')
$sayacSonra = Join-Path $Hedef ($Etiket + '-sayaclar-sonra.json')
# Auth yedegi SIR TASIR (parola hash'i, e-posta, canli oturum ve yenileme
# tokenlari). Sema dosyasi yalniz yapidir ve sir tasimaz; izole provanin
# gercek auth tablolarini kurabilmesi icin gerekir.
$authVeri = Join-Path $Hedef ($Etiket + '-auth-yedegi.sql')
$authSema = Join-Path $Hedef ($Etiket + '-auth-sema.sql')

foreach ($f in @($veriYedegi, $sayacDosya, $authVeri, $authSema, ($veriYedegi + '.enc'), ($authVeri + '.enc'))) {
  if ((Test-Path $f) -and -not $YalnizBaglanti) {
    Write-Host "HATA: $f zaten var. Uzerine YAZILMAZ; farkli bir -Etiket verin." -ForegroundColor Red
    exit 1
  }
}

Write-Host ''
Write-Host ('Hedef klasor (repo disi) : ' + $Hedef) -ForegroundColor Cyan
Write-Host ('Yontem                   : ' + $(if ($Duraklatma) { 'B - dogrulanmis yazma duraklatmasi' } else { 'A - ayni snapshot' })) -ForegroundColor Cyan
Write-Host  'Kapsam                   : public + phase0_private VERISI + auth semasi (storage HARIC)' -ForegroundColor Cyan

if ($Duraklatma) {
  Write-Host ''
  Write-Host 'YONTEM B - devam etmeden once uygulama yazmalarini DURDURUN.' -ForegroundColor Yellow
  Write-Host 'Sayaclar yedekten once ve sonra okunacak; degisirlerse yedek reddedilecek.' -ForegroundColor Yellow
}

if ($YerelDeneme) {
  if (-not $env:PGPASSWORD) { $env:PGPASSWORD = 'yerel' }
} else {
  $sec = Read-Host -Prompt 'Supabase DB sifresi' -AsSecureString
  $plain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
  $env:PGPASSWORD = $plain
}
$env:PGCLIENTENCODING = 'UTF8'

function Sayac-Oku([string]$h, [string]$cikti) {
  & $psqlExe -h $h -p $Port -U $Kullanici -d $Veritabani -X -A -t -v ON_ERROR_STOP=1 -o $cikti -f $sayacSql | Out-Null
  return ($LASTEXITCODE -eq 0 -and (Test-Path $cikti) -and (Get-Item $cikti).Length -gt 200)
}

function Yedek-Gecerli([string]$f) {
  if (-not (Test-Path $f)) { return $false }
  $son = (Get-Content $f -Tail 5 -ErrorAction SilentlyContinue) -join $NL
  return ($son -match 'PostgreSQL database dump complete')
}

function Sayac-Gecerli([string]$f) {
  if (-not (Test-Path $f)) { return $false }
  try { $j = (Get-Content $f -Raw) | ConvertFrom-Json } catch { return $false }
  return ($null -ne $j.satir_sayilari -and $null -ne $j.tablo_sayisi)
}

# Dosyayi sertifikayla sifreler (AES-256 + RSA), ALICIYI DOGRULAR, sonra duz
# kopyayi siler. Basarisizlikta ikisini de siler: yarim korunmus dosya birakmaz.
# Basarida sifreli dosyanin yolunu, basarisizlikta $null doner.
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
  [System.IO.File]::Delete($dosya)   # duz kopya diskte KALMAZ
  return $hedefDosya
}

# Once UCUZ bir baglanti denemesi yapilir: parola yanlissa yedek/sayac zinciri
# hic baslamaz ve hatayi DOGRU adlandiririz. (2026-09-13: parola hatasi,
# "pooler snapshot desteklemiyor" gibi yanlis yonlendiriliyordu.)
#   DURUM: TAMAM | PAROLA | KIRACI | AG | BILINMEYEN
function Baglanti-Dene([string]$h) {
  $gecici = [System.IO.Path]::GetTempFileName()
  $cikti  = [System.IO.Path]::GetTempFileName()
  $hataD  = [System.IO.Path]::GetTempFileName()
  [System.IO.File]::WriteAllText($gecici, 'select 1;')
  $p = Start-Process -FilePath $psqlExe -NoNewWindow -Wait -PassThru -RedirectStandardOutput $cikti -RedirectStandardError $hataD `
       -ArgumentList @('-h', $h, '-p', "$Port", '-U', $Kullanici, '-d', $Veritabani, '-X', '-A', '-t', '-v', 'ON_ERROR_STOP=1', '-f', $gecici)
  $hata = ''
  try { $hata = [System.IO.File]::ReadAllText($hataD) } catch { }
  foreach ($x in @($gecici, $cikti, $hataD)) { try { [System.IO.File]::Delete($x) } catch { } }
  $durum = 'BILINMEYEN'
  if ($p.ExitCode -eq 0) { $durum = 'TAMAM' }
  elseif ($hata -match 'password authentication failed') { $durum = 'PAROLA' }
  elseif ($hata -match 'ENOTFOUND|Tenant or user not found') { $durum = 'KIRACI' }
  elseif ($hata -match 'could not translate host name|Connection refused|timeout expired|No route to host') { $durum = 'AG' }
  return [pscustomobject]@{ Durum = $durum; Kod = $p.ExitCode; Hata = ($hata -replace "`r?`n", ' ').Trim() }
}

try {

$calisan = @()
$parolaHatasi = $false
foreach ($h in $sunucular) {
  $b = Baglanti-Dene $h
  switch ($b.Durum) {
    'TAMAM'  { Write-Host ("  baglanti TAMAM  : " + $h) -ForegroundColor Green; $calisan += $h }
    'PAROLA' { Write-Host ("  PAROLA HATALI   : " + $h) -ForegroundColor Red; $parolaHatasi = $true }
    'KIRACI' { Write-Host ("  bu havuzda yok  : " + $h + " (proje baska bolgede)") -ForegroundColor DarkGray }
    'AG'     { Write-Host ("  aga ulasilamadi : " + $h) -ForegroundColor Yellow }
    default  { Write-Host ("  bilinmeyen hata : " + $h + " -> " + $b.Hata.Substring(0, [Math]::Min(160, $b.Hata.Length))) -ForegroundColor Yellow }
  }
}

if ($calisan.Count -eq 0) {
  Write-Host ''
  if ($parolaHatasi) {
    Write-Host 'PAROLA DOGRULANAMADI. Hicbir dosya olusturulmadi.' -ForegroundColor Red
    Write-Host 'Sunucu projeyi buldu ama parolayi reddetti; bu bir snapshot ya da havuz sorunu DEGILDIR.' -ForegroundColor Red
    Write-Host 'Dogru parolayla tekrar deneyin. Parolayi hatirlamiyorsaniz Supabase panelinden' -ForegroundColor Yellow
    Write-Host 'sifirlamaniz gerekir (sifirlama mevcut baglantilari koparir).' -ForegroundColor Yellow
    Write-Host 'Yalniz baglantiyi sinamak icin: -YalnizBaglanti' -ForegroundColor Yellow
  } else {
    Write-Host 'HICBIR SUNUCUYA BAGLANILAMADI. Hicbir dosya olusturulmadi.' -ForegroundColor Red
    Write-Host 'Supabase panelindeki Session pooler adresini ve bolgeyi kontrol edin.' -ForegroundColor Yellow
  }
  exit 1
}
$sunucular = $calisan

if ($YalnizBaglanti) {
  Write-Host ''
  Write-Host ('Baglanti dogrulandi: ' + ($calisan -join ', ')) -ForegroundColor Green
  Write-Host 'Yedek alinmadi (-YalnizBaglanti).' -ForegroundColor Cyan
  exit 0
}

  $basarili = $false
  $sureSn = 0
  $duraklatmaSn = 0

  foreach ($h in $sunucular) {
    Write-Host ''
    Write-Host "--> Deneniyor: $h" -ForegroundColor Cyan
    $t0 = Get-Date

    if ($Duraklatma) {
      if (-not (Sayac-Oku $h $sayacOnce)) { Write-Host '    sayac (once) alinamadi' -ForegroundColor Yellow; continue }
      Write-Host '    sayac (once) alindi' -ForegroundColor Green
      & $pgDump -h $h -p $Port -U $Kullanici -d $Veritabani --data-only --no-owner --schema=public --schema=phase0_private -f $veriYedegi
      if ($LASTEXITCODE -ne 0 -or -not (Yedek-Gecerli $veriYedegi)) {
        Write-Host "    veri yedegi basarisiz (cikis kodu $LASTEXITCODE)" -ForegroundColor Yellow
        if (Test-Path $veriYedegi) { [System.IO.File]::Delete($veriYedegi) }
        continue
      }
      Write-Host '    veri yedegi alindi' -ForegroundColor Green
      & $pgDump -h $h -p $Port -U $Kullanici -d $Veritabani --data-only --no-owner --schema=auth -f $authVeri
      if ($LASTEXITCODE -ne 0) { Write-Host '    auth veri yedegi basarisiz' -ForegroundColor Yellow; continue }
      & $pgDump -h $h -p $Port -U $Kullanici -d $Veritabani --schema-only --no-owner --no-privileges --schema=auth -f $authSema
      if ($LASTEXITCODE -ne 0) { Write-Host '    auth sema dokumu basarisiz' -ForegroundColor Yellow; continue }
      Write-Host '    auth yedegi alindi' -ForegroundColor Green
      if (-not (Sayac-Oku $h $sayacSonra)) { Write-Host '    sayac (sonra) alinamadi' -ForegroundColor Yellow; continue }
      $duraklatmaSn = [math]::Round(((Get-Date) - $t0).TotalSeconds, 1)

      $a = ((Get-Content $sayacOnce)  | Where-Object { $_ -notmatch 'alinma_zamani' }) -join $NL
      $b = ((Get-Content $sayacSonra) | Where-Object { $_ -notmatch 'alinma_zamani' }) -join $NL
      if ($a -ne $b) {
        Write-Host ''
        Write-Host 'RED: sayaclar yedekten once ve sonra FARKLI.' -ForegroundColor Red
        Write-Host 'Yazmalar surmus demektir; yedek ile sayaclar ayni durumu gostermiyor.' -ForegroundColor Red
        Write-Host 'Yazmalari gercekten durdurup bastan alin. Yedek dosyasi silindi.' -ForegroundColor Red
        if (Test-Path $veriYedegi) { [System.IO.File]::Delete($veriYedegi) }
        exit 1
      }
      Copy-Item $sayacOnce $sayacDosya
      Write-Host ('    sayaclar ONCE == SONRA (duraklatma penceresi ' + $duraklatmaSn + ' sn)') -ForegroundColor Green
    }
    else {
      $env:PMS_PGDUMP = $pgDump
      $env:PMS_HOST = $h
      $env:PMS_PORT = "$Port"
      $env:PMS_USER = $Kullanici
      $env:PMS_DB   = $Veritabani
      $env:PMS_VERI = $veriYedegi
      $env:PMS_AUTH_VERI = $authVeri
      $env:PMS_AUTH_SEMA = $authSema
      & $psqlExe -h $h -p $Port -U $Kullanici -d $Veritabani -X -A -t -v ON_ERROR_STOP=1 -v ("sayac_dosyasi=" + $sayacDosya) -v ("sayac_sorgusu=" + $sayacSql) -f $surucu
      $kod = $LASTEXITCODE
      if ($kod -ne 0 -or -not (Yedek-Gecerli $veriYedegi) -or -not (Sayac-Gecerli $sayacDosya) -or -not (Yedek-Gecerli $authVeri) -or -not (Yedek-Gecerli $authSema)) {
        Write-Host "    (A) basarisiz (psql cikis kodu $kod)" -ForegroundColor Yellow
        if (-not (Yedek-Gecerli $veriYedegi)) { Write-Host '    veri yedegi eksik/yarim' -ForegroundColor Yellow }
        if (-not (Yedek-Gecerli $authVeri))   { Write-Host '    auth veri yedegi eksik/yarim' -ForegroundColor Yellow }
        if (-not (Yedek-Gecerli $authSema))   { Write-Host '    auth sema dokumu eksik/yarim' -ForegroundColor Yellow }
        foreach ($f in @($veriYedegi, $sayacDosya, $authVeri, $authSema)) { if (Test-Path $f) { [System.IO.File]::Delete($f) } }
        continue
      }
    }

    $sureSn = [math]::Round(((Get-Date) - $t0).TotalSeconds, 1)
    $basarili = $true
    break
  }

  if (-not $basarili) {
    Write-Host ''
    Write-Host 'BASARISIZ. Hicbir sunucuda yedek + sayac ciftini alamadim.' -ForegroundColor Red
    Write-Host 'Baglanti ve parola dogrulanmisti; sorun yedek/sayac adimindadir.' -ForegroundColor Red
    if (-not $Duraklatma) {
      Write-Host 'Havuz snapshot disari vermeyi desteklemiyorsa (A) calismaz. (B) ile tekrar deneyin:' -ForegroundColor Yellow
      Write-Host ('  .\docs\kurulum\yedek-ve-sayac-al.ps1 -Etiket ' + $Etiket + ' -Duraklatma') -ForegroundColor Yellow
    }
    exit 1
  }

  # SAKLAMA KURALI: auth yedegi canli oturum anahtari tasir; yalniz EN YENISI
  # durur. Veri yedekleri ve sayaclar birikmeye devam eder (sir tasimazlar).
  $veriSifreli = Sifrele $veriYedegi
  $authSifreli = Sifrele $authVeri
  if (-not $veriSifreli -or -not $authSifreli) {
    Write-Host ''
    Write-Host 'SIFRELEME BASARISIZ. Duz kopyalar silindi; yedek ALINMADI.' -ForegroundColor Red
    Write-Host 'Sertifikayi ve openssl kurulumunu kontrol edip tekrar deneyin.' -ForegroundColor Red
    exit 1
  }

  # DIKKAT: desen SONEK olmali. '*-auth-*.sql' kullanilirsa, etiketi 'auth' ile
  # biten bir kosuda VERI yedegi de eslesir ve silinir (2026-09-13'te oldu).
  $silinen = 0
  @(Get-ChildItem -Path $Hedef -Filter '*-auth-yedegi.sql.enc' -ErrorAction SilentlyContinue) +
  @(Get-ChildItem -Path $Hedef -Filter '*-auth-yedegi.sql'     -ErrorAction SilentlyContinue) +
  @(Get-ChildItem -Path $Hedef -Filter '*-auth-sema.sql'       -ErrorAction SilentlyContinue) | ForEach-Object {
    if ($_.FullName -ne $authSifreli -and $_.FullName -ne $authSema) {
      try { [System.IO.File]::Delete($_.FullName); $silinen++ }
      catch { Write-Host ('  UYARI: eski auth yedegi silinemedi: ' + $_.Name) -ForegroundColor Yellow }
    }
  }

  $vy = Get-Item $veriSifreli
  $sy = Get-Item $sayacDosya
  $hash = (Get-FileHash $veriSifreli -Algorithm SHA256).Hash
  Write-Host ''
  Write-Host 'TAMAM.' -ForegroundColor Green
  Write-Host ('  veri yedegi : ' + $vy.FullName + '  (' + $vy.Length + ' bayt, SIFRELI)')
  Write-Host ('  SHA-256     : ' + $hash)
  Write-Host ('  sayaclar    : ' + $sy.FullName + '  (' + $sy.Length + ' bayt, duz)')
  Write-Host ('  auth yedegi : ' + $authSifreli + '  (' + (Get-Item $authSifreli).Length + ' bayt, SIFRELI)')
  Write-Host ('  auth SHA-256: ' + (Get-FileHash $authSifreli -Algorithm SHA256).Hash)
  Write-Host ('  auth semasi : ' + $authSema + '  (' + (Get-Item $authSema).Length + ' bayt, duz)')
  if ($silinen -gt 0) { Write-Host ('  eski auth yedegi silindi : ' + $silinen + ' dosya') -ForegroundColor DarkGray }
  Write-Host ('  sure        : ' + $sureSn + ' sn')
  Write-Host ''
  Write-Host 'Sifreli dosyalar yalniz PAROLA YONETICINIZDEKI gizli anahtarla acilir.' -ForegroundColor Yellow
  Write-Host 'Anahtari kaybederseniz bu yedekler KALICI OLARAK acilamaz.' -ForegroundColor Yellow
  if ($Duraklatma) { Write-Host ('  duraklatma penceresi : ' + $duraklatmaSn + ' sn') }
  Write-Host ''
  Write-Host 'Sonraki adim - geri yukleme provasi (E-5):' -ForegroundColor Cyan
  Write-Host ('  node scripts/pms-yedek-geri-yukleme-provasi.mjs "' + $vy.FullName + '" "' + $sy.FullName + '" --sema "<sema-dokumu.sql>"')
  exit 0
}
finally {
  Remove-Item Env:\PGPASSWORD -ErrorAction SilentlyContinue
  foreach ($v in 'PMS_PGDUMP','PMS_HOST','PMS_PORT','PMS_USER','PMS_DB','PMS_VERI','PMS_AUTH_VERI','PMS_AUTH_SEMA','PMS_SNAPSHOT') {
    Remove-Item ('Env:\' + $v) -ErrorAction SilentlyContinue
  }
  $plain = $null
  [System.GC]::Collect()
}
