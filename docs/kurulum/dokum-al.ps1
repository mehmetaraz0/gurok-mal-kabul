# dokum-al.ps1 - Canli Supabase veritabanindan kurulum dokumlerini alir.
#
# Kullanim (repo kokunde, PowerShell'de - SQL Editor'de DEGIL):
#   .\docs\kurulum\dokum-al.ps1
#   .\docs\kurulum\dokum-al.ps1 -Etiket '2026-09-07-post-pms-faz1'
#
# Sifre ekranda gorunmez, PowerShell gecmisine yazilmaz ve komut satirina
# gecirilmez (pg_dump onu PGPASSWORD ortam degiskeninden okur).
#
# Uretilen dosyalar:
#   docs\kurulum\<Etiket>-sema-dokumu.sql   - tablolar, RLS, fonksiyonlar,
#                                             GRANT'ler, varsayilan ACL (VERI YOK)
#   docs\kurulum\<Etiket>-referans-veri.sql - yalniz roller/moduller/yetki_matrisi
#
# ---------------------------------------------------------------------------
# BU DOSYA SALT ASCII OLMALI.
# Windows PowerShell 5.1, BOM'suz .ps1 dosyalarini ANSI (cp1254) olarak okur.
# UTF-8 uzun tire (U+2014 = E2 80 94) o kod sayfasinda "a EUR "" olur ve
# son bayt (0x94) KIVRIK KAPANIS TIRNAGI'dir: bir Write-Host dizesinin
# icindeyse dizeyi erken kapatir ve dosya ayristirilamaz.
# (2026-09-07'de tam olarak bu oldu.) Turkce karakter ve tire kullanma.
# ---------------------------------------------------------------------------
# UC KRITIK BAYRAK - ucu de 6 Eylul 2026'da aci deneyimle ogrenildi.
# Degistirmeden once docs/kurulum/2026-09-06-staging-branch-kurulum.md okuyun.
#
#   1) --schema=public --schema=phase0_private
#      phase0_private ATLANIRSA denetim izi ve otel degismezlik tetikleyicileri
#      dokumde OLMAZ; yukleme sirasinda 42 CREATE TRIGGER sessizce duser ve
#      dokum "calisti" gibi gorunur.
#
#   2) --no-privileges KULLANMA
#      Ilk dokumun asil kusuru oydu: sifir GRANT satiri. RLS politikalari
#      dokulur ama izinler dokulmezse dokum uretimi TEMSIL ETMEZ.
#      --no-owner sahiplik satirlarini atar, izinleri korur - o yeterli.
#
#   3) -f kullan, kabuk yonlendirmesi ( > ) KULLANMA
#      PowerShell yonlendirmesi dosyayi UTF-16LE yazar ve fonksiyon
#      govdelerindeki satir sonlarini bozar; dogrulama 26 fonksiyonun 25'ini
#      "farkli" gosterir, dokum kusursuz olsa bile.
# ---------------------------------------------------------------------------

param(
  [string]$Etiket = (Get-Date -Format 'yyyy-MM-dd')
)

$ErrorActionPreference = 'Stop'

$pgDump = 'C:\Program Files\PostgreSQL\17\bin\pg_dump.exe'
if (-not (Test-Path $pgDump)) {
  Write-Host "HATA: pg_dump bulunamadi: $pgDump" -ForegroundColor Red
  exit 1
}

$projectRef = 'xwytofysmgqtqjzkplfi'
$region     = 'ap-northeast-1'

$hedef = $PSScriptRoot
$sema  = Join-Path $hedef ($Etiket + '-sema-dokumu.sql')
$veri  = Join-Path $hedef ($Etiket + '-referans-veri.sql')

if (Test-Path $sema) {
  Write-Host "HATA: $sema zaten var. Mevcut baseline'in uzerine YAZILMAZ." -ForegroundColor Red
  Write-Host "      Farkli bir -Etiket verin." -ForegroundColor Red
  exit 1
}

$sec = Read-Host -Prompt 'Supabase DB sifresi' -AsSecureString
$plain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
  [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))

# Parolayi komut satirina KOYMA: pg_dump PGPASSWORD'u ortamdan okur.
$env:PGPASSWORD = $plain

try {
  $basarili = $false

  foreach ($h in @("aws-0-$region.pooler.supabase.com", "aws-1-$region.pooler.supabase.com")) {
    Write-Host ''
    Write-Host "--> Deneniyor: $h" -ForegroundColor Cyan

    # pg_dump yerel bir .exe - hata verdiginde PowerShell istisnasi FIRLATMAZ,
    # yalnizca $LASTEXITCODE'u sifirdan farkli yapar.
    & $pgDump -h $h -p 5432 -U "postgres.$projectRef" -d postgres `
        --schema-only --schema=public --schema=phase0_private --no-owner -f $sema
    if ($LASTEXITCODE -ne 0) {
      Write-Host "    sema dokumu basarisiz (cikis kodu $LASTEXITCODE)" -ForegroundColor Yellow
      if (Test-Path $sema) { Remove-Item $sema -Force }   # yarim dosya birakma
      continue
    }

    & $pgDump -h $h -p 5432 -U "postgres.$projectRef" -d postgres `
        --data-only --no-owner `
        --table=public.roller --table=public.moduller --table=public.yetki_matrisi -f $veri
    if ($LASTEXITCODE -ne 0) {
      Write-Host "    referans veri dokumu basarisiz (cikis kodu $LASTEXITCODE)" -ForegroundColor Yellow
      continue
    }

    $basarili = $true
    break
  }

  if (-not $basarili) {
    Write-Host ''
    Write-Host "Her iki pooler da basarisiz oldu. Sifreyi ve Supabase panelindeki" -ForegroundColor Red
    Write-Host "Session pooler adresini kontrol edin." -ForegroundColor Red
    exit 1
  }

  Write-Host ''
  Write-Host 'TAMAM. Olusan dosyalar:' -ForegroundColor Green
  Get-Item $sema, $veri | Select-Object Name, Length

  # Dokumun gercekten yeterli oldugunu SAYARAK goster - "olustu" yetmez.
  $icerik = Get-Content $sema -Raw
  $phase0 = ([regex]::Matches($icerik, 'phase0_private')).Count
  $grant  = ([regex]::Matches($icerik, '(?m)^GRANT ')).Count
  $defacl = ([regex]::Matches($icerik, 'ALTER DEFAULT PRIVILEGES')).Count

  Write-Host ''
  Write-Host 'Icerik kontrolu (hepsi > 0 olmali):' -ForegroundColor Cyan
  Write-Host "  phase0_private referansi : $phase0"
  Write-Host "  GRANT satiri             : $grant"
  Write-Host "  ALTER DEFAULT PRIVILEGES : $defacl"

  if ($phase0 -eq 0 -or $grant -eq 0) {
    Write-Host ''
    Write-Host 'UYARI: dokum EKSIK gorunuyor. Bayraklari kontrol edin.' -ForegroundColor Red
    exit 1
  }

  Write-Host ''
  Write-Host 'Sonraki adim - dokumu yerelde dogrula:' -ForegroundColor Cyan
  Write-Host ('  node scripts/dokum-dogrula.mjs docs/kurulum/' + $Etiket + '-sema-dokumu.sql [esitlik-dosyasi.sql]')
  exit 0
}
finally {
  # Parolayi ortamdan ve bellekten temizle.
  Remove-Item Env:\PGPASSWORD -ErrorAction SilentlyContinue
  $plain = $null
  [System.GC]::Collect()
}
