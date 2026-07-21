# dokum-al.ps1 — Canlı Supabase veritabanından kurulum dökümlerini alır.
# Kullanım: repo kökünde  .\docs\kurulum\dokum-al.ps1
# Şifre ekranda görünmez ve PowerShell geçmişine yazılmaz.
#
# Üretilen dosyalar:
#   docs\kurulum\01-sema-dokumu.sql   — tablolar, RLS politikaları, fonksiyonlar (VERİ YOK)
#   docs\kurulum\02-referans-veri.sql — yalnız roller/moduller/yetki_matrisi verisi

$ErrorActionPreference = 'Stop'

$pgDump = 'C:\Program Files\PostgreSQL\17\bin\pg_dump.exe'
if (-not (Test-Path $pgDump)) { Write-Host "HATA: pg_dump bulunamadi: $pgDump" -ForegroundColor Red; exit 1 }

$projectRef = 'xwytofysmgqtqjzkplfi'
$region     = 'ap-northeast-1'

$sec = Read-Host -Prompt 'Supabase DB sifresi' -AsSecureString
$plain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
  [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
$enc = [uri]::EscapeDataString($plain)   # ozel karakterleri percent-encode et

$hedef = Join-Path $PSScriptRoot ''
$sema  = Join-Path $hedef '01-sema-dokumu.sql'
$veri  = Join-Path $hedef '02-referans-veri.sql'

# pg_dump yerel bir .exe — hata verdiginde PowerShell istisnasi FIRLATMAZ,
# yalnizca $LASTEXITCODE'u sifirdan farkli yapar. Bu yuzden try/catch yerine
# cikis kodunu kontrol ediyoruz.
foreach ($host_ in @("aws-0-$region.pooler.supabase.com", "aws-1-$region.pooler.supabase.com")) {
  $uri = "postgresql://postgres.$projectRef`:$enc@$host_`:5432/postgres"
  Write-Host "`n--> Deneniyor: $host_" -ForegroundColor Cyan

  & $pgDump $uri --schema=public --schema-only --no-owner --no-privileges -f $sema
  if ($LASTEXITCODE -ne 0) { Write-Host "    sema dokumu basarisiz (cikis kodu $LASTEXITCODE)" -ForegroundColor Yellow; continue }

  & $pgDump $uri --schema=public --data-only --no-owner `
      --table=public.roller --table=public.moduller --table=public.yetki_matrisi -f $veri
  if ($LASTEXITCODE -ne 0) { Write-Host "    referans veri dokumu basarisiz (cikis kodu $LASTEXITCODE)" -ForegroundColor Yellow; continue }

  Write-Host "`nTAMAM. Olusan dosyalar:" -ForegroundColor Green
  Get-Item $sema, $veri | Select-Object Name, Length
  exit 0
}

Write-Host "`nHer iki pooler da basarisiz oldu. Sifreyi ve Supabase panelindeki Session pooler adresini kontrol edin." -ForegroundColor Red
exit 1
