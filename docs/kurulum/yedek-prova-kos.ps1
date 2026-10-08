# ===========================================================================
# yedek-prova-kos.ps1 - YEDEK GERI YUKLEME PROVASINI TEK SURECTE KOSAR
# ===========================================================================
# NEDEN: 2026-10-08 incelemesi (SO-1a) olctu ki belgedeki iki adimli talimat
# CALISMIYOR. Alt bir PowerShell'de kurulan ortam degiskeni EBEVEYNE geri
# TASINMAZ (olculdu: PARENT_HAS_VALUE=False), bu yuzden ardindan calistirilan
# `node` ayni parola ortamini hic gormez. Ayrica cift tirnak icindeki
# degiskenler dis kabukta genisler.
#
# Bu betik dort isi AYNI SURECTE yapar:
#   1. Anahtar parolasini alir (Read-Host -AsSecureString ya da -Parola)
#   2. $env:YEDEK_ANAHTAR_PAROLA'yi kurar
#   3. node scripts/pms-yedek-geri-yukleme-provasi.mjs calistirir
#   4. finally: BSTR bellegini sifirlar, ortam degiskenini siler, istenirse
#      anahtarin GECICI kopyasini siler
#
# ONEMLI: -GizliAnahtar bir GECICI KOPYA olmalidir. -GeciciAnahtariSil yalniz
# o kopyayi siler; ASIL KURTARMA ANAHTARINA DOKUNMAZ. Parola hicbir zaman
# komut satirina, PowerShell gecmisine ya da bir dosyaya yazilmaz.
#
# KULLANIM (repo kokunde, TEK komut):
#   .\docs\kurulum\yedek-prova-kos.ps1 `
#     -Yedek     C:\Users\USER\ERP-Yedek\<Etiket>-veri-yedegi.sql.enc `
#     -Sayaclar  C:\Users\USER\ERP-Yedek\<Etiket>-sayaclar.json `
#     -Sema      C:\Users\USER\ERP-Yedek\<Etiket>-sema-dokumu.sql `
#     -ParmakIzi C:\Users\USER\ERP-Yedek\<Etiket>-parmakizi.json `
#     -AuthVeri  C:\Users\USER\ERP-Yedek\<Etiket>-auth-yedegi.sql.enc `
#     -AuthSema  C:\Users\USER\ERP-Yedek\<Etiket>-auth-sema.sql `
#     -GizliAnahtar C:\gecici\anahtar-kopyasi.pem -GeciciAnahtariSil
# ===========================================================================
param(
  [Parameter(Mandatory = $true)][string]$Yedek,
  [Parameter(Mandatory = $true)][string]$Sema,
  [Parameter(Mandatory = $true)][string]$ParmakIzi,
  [Parameter(Mandatory = $true)][string]$GizliAnahtar,
  [string]$Sayaclar = '',
  [string]$AuthVeri = '',
  [string]$AuthSema = '',
  # Testlerde ve otomasyonda parolayi onceden hazirlamak icin. Verilmezse
  # betik Read-Host ile sorar. Duz metin parametre YOKTUR.
  [System.Security.SecureString]$Parola,
  [switch]$GeciciAnahtariSil,
  [switch]$Mekanik
)

$ErrorActionPreference = 'Stop'

foreach ($yol in @($Yedek, $Sema, $ParmakIzi, $GizliAnahtar)) {
  if (-not (Test-Path $yol)) {
    Write-Host ("HATA: dosya yok: " + $yol) -ForegroundColor Red
    exit 2
  }
}
foreach ($yol in @($Sayaclar, $AuthVeri, $AuthSema)) {
  if ($yol -and -not (Test-Path $yol)) {
    Write-Host ("HATA: dosya yok: " + $yol) -ForegroundColor Red
    exit 2
  }
}
if ($AuthVeri -and -not $AuthSema) {
  Write-Host "HATA: -AuthVeri ile -AuthSema birlikte verilir." -ForegroundColor Red
  exit 2
}

if (-not $Parola) {
  $Parola = Read-Host -Prompt 'Yedek gizli anahtar parolasi' -AsSecureString
}

$bstr = [System.IntPtr]::Zero
$cikis = 1
try {
  $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Parola)
  $env:YEDEK_ANAHTAR_PAROLA = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)

  $argumanlar = @('scripts/pms-yedek-geri-yukleme-provasi.mjs', $Yedek)
  if ($Sayaclar) { $argumanlar += $Sayaclar }
  $argumanlar += @('--sema', $Sema, '--parmakizi', $ParmakIzi, '--gizli-anahtar', $GizliAnahtar)
  if ($AuthVeri) { $argumanlar += @('--auth-veri', $AuthVeri, '--auth-sema', $AuthSema) }
  if ($Mekanik)  { $argumanlar += '--mekanik' }

  Write-Host ''
  Write-Host 'Prova baslatiliyor (parola AYNI surecte, komut satirinda DEGIL).' -ForegroundColor Cyan
  & node @argumanlar
  $cikis = $LASTEXITCODE
}
finally {
  if ($bstr -ne [System.IntPtr]::Zero) {
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
  }
  Remove-Item Env:\YEDEK_ANAHTAR_PAROLA -ErrorAction SilentlyContinue
  if ($GeciciAnahtariSil) {
    # YALNIZ gecici kopya. Asil kurtarma anahtari parola yoneticisindedir ve
    # bu betik ona hicbir kosulda dokunmaz.
    Remove-Item -LiteralPath $GizliAnahtar -Force -ErrorAction SilentlyContinue
    if (Test-Path $GizliAnahtar) {
      Write-Host ('UYARI: gecici anahtar kopyasi silinemedi: ' + $GizliAnahtar) -ForegroundColor Yellow
    } else {
      Write-Host 'Gecici anahtar kopyasi silindi.' -ForegroundColor DarkGray
    }
  }
  $kaldiMi = [bool]$env:YEDEK_ANAHTAR_PAROLA
  Write-Host ('Parola ortami temizlendi (YEDEK_ANAHTAR_PAROLA ayarli mi: ' + $kaldiMi + ').') -ForegroundColor DarkGray
}

exit $cikis
