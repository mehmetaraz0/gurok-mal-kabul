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
#   <Etiket>-veri-yedegi.sql   public + phase0_private VERISI (--data-only)
#   <Etiket>-sayaclar.json     ayni durumu temsil eden uretim sayaclari
#
# KURTARMA KAPSAMI - SINIRLIDIR. Bu yedek YALNIZ public + phase0_private
# semalarinin VERISINI icerir. Icermedikleri: auth semasi (auth.users,
# kimlikler, oturumlar), storage, realtime, veritabani rolleri ve uzantilar,
# proje ayarlari. Bos bir projeye geri yuklendiginde KIMSE GIRIS YAPAMAZ:
# kullanicilar.auth_user_id -> auth.users(id) yabanci anahtari karsiliksiz kalir.
# Gecerli kurtarma senaryosu: AYNI projede veri kaybini geri almak.
#
# ---------------------------------------------------------------------------
# BU DOSYA SALT ASCII OLMALI (dokum-al.ps1 basindaki aciklamaya bakin).
# ---------------------------------------------------------------------------

param(
  [string]$Etiket = (Get-Date -Format 'yyyy-MM-dd'),
  [string]$Hedef = $(if ($env:GUROK_YEDEK) { $env:GUROK_YEDEK } else { 'C:\Users\USER\ERP-Yedek' }),
  [switch]$Duraklatma,
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

foreach ($f in @($veriYedegi, $sayacDosya)) {
  if (Test-Path $f) {
    Write-Host "HATA: $f zaten var. Uzerine YAZILMAZ; farkli bir -Etiket verin." -ForegroundColor Red
    exit 1
  }
}

Write-Host ''
Write-Host ('Hedef klasor (repo disi) : ' + $Hedef) -ForegroundColor Cyan
Write-Host ('Yontem                   : ' + $(if ($Duraklatma) { 'B - dogrulanmis yazma duraklatmasi' } else { 'A - ayni snapshot' })) -ForegroundColor Cyan
Write-Host  'Kapsam                   : public + phase0_private VERISI (auth/storage HARIC)' -ForegroundColor Cyan

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

try {
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
      & $psqlExe -h $h -p $Port -U $Kullanici -d $Veritabani -X -A -t -v ON_ERROR_STOP=1 -v ("sayac_dosyasi=" + $sayacDosya) -v ("sayac_sorgusu=" + $sayacSql) -f $surucu
      $kod = $LASTEXITCODE
      if ($kod -ne 0 -or -not (Yedek-Gecerli $veriYedegi) -or -not (Sayac-Gecerli $sayacDosya)) {
        Write-Host "    (A) basarisiz (psql cikis kodu $kod)" -ForegroundColor Yellow
        if (-not (Yedek-Gecerli $veriYedegi)) { Write-Host '    veri yedegi eksik/yarim' -ForegroundColor Yellow }
        foreach ($f in @($veriYedegi, $sayacDosya)) { if (Test-Path $f) { [System.IO.File]::Delete($f) } }
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
    if (-not $Duraklatma) {
      Write-Host 'Pooler snapshot disari vermeyi desteklemiyorsa (A) calismaz.' -ForegroundColor Red
      Write-Host 'Yazmalari durdurup (B) ile tekrar deneyin:' -ForegroundColor Yellow
      Write-Host ('  .\docs\kurulum\yedek-ve-sayac-al.ps1 -Etiket ' + $Etiket + ' -Duraklatma') -ForegroundColor Yellow
    }
    exit 1
  }

  $vy = Get-Item $veriYedegi
  $sy = Get-Item $sayacDosya
  $hash = (Get-FileHash $veriYedegi -Algorithm SHA256).Hash
  Write-Host ''
  Write-Host 'TAMAM.' -ForegroundColor Green
  Write-Host ('  veri yedegi : ' + $vy.FullName + '  (' + $vy.Length + ' bayt)')
  Write-Host ('  SHA-256     : ' + $hash)
  Write-Host ('  sayaclar    : ' + $sy.FullName + '  (' + $sy.Length + ' bayt)')
  Write-Host ('  sure        : ' + $sureSn + ' sn')
  if ($Duraklatma) { Write-Host ('  duraklatma penceresi : ' + $duraklatmaSn + ' sn') }
  Write-Host ''
  Write-Host 'Sonraki adim - geri yukleme provasi (E-5):' -ForegroundColor Cyan
  Write-Host ('  node scripts/pms-yedek-geri-yukleme-provasi.mjs "' + $vy.FullName + '" "' + $sy.FullName + '" --sema "<sema-dokumu.sql>"')
  exit 0
}
finally {
  Remove-Item Env:\PGPASSWORD -ErrorAction SilentlyContinue
  foreach ($v in 'PMS_PGDUMP','PMS_HOST','PMS_PORT','PMS_USER','PMS_DB','PMS_VERI','PMS_SNAPSHOT') {
    Remove-Item ('Env:\' + $v) -ErrorAction SilentlyContinue
  }
  $plain = $null
  [System.GC]::Collect()
}
