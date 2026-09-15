# ===========================================================================
# SQL UYGULA — uretim yayin kanali (psql)
# ===========================================================================
# NEDEN: 2026-09-13 yayininda tarayici otomasyonu pencere ortasinda coktu
# (JS calisiyor, tiklama/tus ulasmiyor). O gun ayni baytlar psql ile uygulandi.
# Runbook karari: birincil kanal psql, SQL Editor yedek kanaldir.
#
# NE YAPAR:
#   1. Dosyanin SHA-256 ozetini yazar (uygulanan baytin kaniti).
#   2. Parolayi bir kez sorar (Read-Host -AsSecureString). Parola komut
#      satirina, gecmise ya da dosyaya YAZILMAZ.
#   3. Calisan havuz adresini 'select 1' ile bulur (aws-0 / aws-1).
#   4. SQL'i -v ON_ERROR_STOP=1 ile uygular. -SaltOkuma verilmezse islem
#      --single-transaction altinda kosar: hata olursa hicbir sey kalmaz.
#
# KULLANIM:
#   .\docs\kurulum\sql-uygula.ps1 -Dosya docs\kurulum\<migration>.sql
#   .\docs\kurulum\sql-uygula.ps1 -Dosya <sorgu>.sql -SaltOkuma
# ===========================================================================
param(
  [Parameter(Mandatory = $true)][string]$Dosya,
  # Salt okuma sorgulari icin: tek islem sarmalayicisi yok, cikti ekrana gelir.
  [switch]$SaltOkuma,
  [string]$Sunucu = '',
  [int]$Port = 5432,
  [string]$Kullanici = '',
  [string]$Veritabani = 'postgres'
)

$ErrorActionPreference = 'Stop'

$bin = 'C:\Program Files\PostgreSQL\17\bin'
$psqlExe = Join-Path $bin 'psql.exe'
if (-not (Test-Path $psqlExe)) { Write-Host "HATA: bulunamadi: $psqlExe" -ForegroundColor Red; exit 1 }
if (-not (Test-Path $Dosya)) { Write-Host "HATA: SQL dosyasi yok: $Dosya" -ForegroundColor Red; exit 1 }

$projectRef = 'xwytofysmgqtqjzkplfi'
$region = 'ap-northeast-1'
if ($Sunucu) { $sunucular = @($Sunucu) }
else { $sunucular = @("aws-0-$region.pooler.supabase.com", "aws-1-$region.pooler.supabase.com") }
if (-not $Kullanici) { $Kullanici = "postgres.$projectRef" }

$ozet = (Get-FileHash -Path $Dosya -Algorithm SHA256).Hash
Write-Host ''
Write-Host ('Dosya      : ' + (Resolve-Path $Dosya)) -ForegroundColor Cyan
Write-Host ('SHA-256    : ' + $ozet) -ForegroundColor Cyan
Write-Host ('Kip        : ' + $(if ($SaltOkuma) { 'SALT OKUMA' } else { 'UYGULAMA (--single-transaction)' })) -ForegroundColor Cyan

$sec = Read-Host -Prompt 'Supabase DB sifresi' -AsSecureString
$env:PGPASSWORD = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
  [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
$env:PGCLIENTENCODING = 'UTF8'

# Once ucuz bir yoklama: parola mi yanlis, adres mi? Yayin gunu bu ayrimi
# yapmamak kesintiyi uzatmisti.
$secilen = ''
foreach ($h in $sunucular) {
  $gecici = [System.IO.Path]::GetTempFileName()
  & $psqlExe -h $h -p $Port -U $Kullanici -d $Veritabani -X -A -t -v ON_ERROR_STOP=1 `
    -c 'select 1' -o $gecici | Out-Null
  $kod = $LASTEXITCODE
  Remove-Item $gecici -ErrorAction SilentlyContinue
  if ($kod -eq 0) { $secilen = $h; break }
}
if (-not $secilen) {
  $env:PGPASSWORD = ''
  Write-Host 'HATA: hicbir havuz adresine baglanilamadi. Parolayi ve adresi kontrol edin.' -ForegroundColor Red
  exit 1
}
Write-Host ('Sunucu     : ' + $secilen) -ForegroundColor Cyan
Write-Host ''

$argumanlar = @('-h', $secilen, '-p', $Port, '-U', $Kullanici, '-d', $Veritabani,
  '-X', '-v', 'ON_ERROR_STOP=1', '-f', $Dosya)
if (-not $SaltOkuma) { $argumanlar = @('--single-transaction') + $argumanlar }

& $psqlExe @argumanlar
$sonuc = $LASTEXITCODE
$env:PGPASSWORD = ''

Write-Host ''
if ($sonuc -eq 0) {
  Write-Host ('BASARILI (cikis kodu 0) — SHA-256 ' + $ozet) -ForegroundColor Green
} else {
  Write-Host ('BASARISIZ (cikis kodu ' + $sonuc + ') — degisiklik uygulanmadi') -ForegroundColor Red
}
exit $sonuc
