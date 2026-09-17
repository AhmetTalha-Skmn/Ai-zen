#requires -Version 5.1
<#!
.SYNOPSIS
    Aizen (Çalışma Takip Sistemi) için kişisel verisiz kurulum ZIP'i üretir.

.DESCRIPTION
    Paket, izin verilen çalışma dosyalarını açık bir allow-list ile kopyalar.
    Aktivite CSV'leri, günlük raporlar, durum dosyaları, kayıtlı cihazlar,
    merkez anahtarları ve önceki paket çıktıları hiçbir zaman yükte yer almaz.
#>
[CmdletBinding()]
param(
    [string]$CiktiYolu,

    # Tek dosya kurulum (.exe) üretimini atlar. Varsayılan: iexpress varsa üretilir.
    [switch]$ExeAtla
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-TamYol {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Yol
    )

    return [System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Yol))
}

function Copy-StageDosyasi {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo]$Dosya,

        [Parameter(Mandatory = $true)]
        [string]$KaynakKoku,

        [Parameter(Mandatory = $true)]
        [string]$HedefKoku
    )

    $normalKaynakKoku = (Get-TamYol -Yol $KaynakKoku).TrimEnd('\') + '\'
    $normalDosyaYolu = Get-TamYol -Yol $Dosya.FullName
    if (-not $normalDosyaYolu.StartsWith($normalKaynakKoku, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Paketlenecek dosya kaynak kökün dışında: $normalDosyaYolu"
    }

    $goreliYol = $normalDosyaYolu.Substring($normalKaynakKoku.Length)
    $hedefYolu = Join-Path $HedefKoku $goreliYol
    $hedefKlasoru = Split-Path -Parent $hedefYolu
    if (-not (Test-Path -LiteralPath $hedefKlasoru -PathType Container)) {
        New-Item -ItemType Directory -Path $hedefKlasoru -Force | Out-Null
    }

    Copy-Item -LiteralPath $normalDosyaYolu -Destination $hedefYolu -Force
}

function Write-Utf8Bom {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Yol,

        [Parameter(Mandatory = $true)]
        [string]$Metin
    )

    $encoding = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($Yol, $Metin, $encoding)
}

function Get-PaketSha256 {
    # Get-FileHash, Windows PowerShell 5.1 PowerShell 7'nin modül yolunu
    # devraldığında yüklenemeyebilir. Paket bütünlüğü ortamdan bağımsız kalmalı.
    param([Parameter(Mandatory = $true)][string]$Yol)

    $akim = [System.IO.File]::Open($Yol, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($akim))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $akim.Dispose()
        $sha.Dispose()
    }
}

function Get-DosyaManifesti {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Kok
    )

    $normalKok = (Get-TamYol -Yol $Kok).TrimEnd('\') + '\'
    $kayitlar = @()
    foreach ($dosya in Get-ChildItem -LiteralPath $Kok -File -Recurse | Sort-Object FullName) {
        $goreliYol = (Get-TamYol -Yol $dosya.FullName).Substring($normalKok.Length).Replace('\', '/')
        $kayitlar += [ordered]@{
            yol    = $goreliYol
            boyut  = $dosya.Length
            sha256 = Get-PaketSha256 -Yol $dosya.FullName
        }
    }

    return $kayitlar
}

function Test-PaketIcerigi {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ZipYolu
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $arsiv = [System.IO.Compression.ZipFile]::OpenRead($ZipYolu)
    try {
        $adlar = @($arsiv.Entries | ForEach-Object { $_.FullName.Replace('\', '/') })
        foreach ($gerekli in @('Kurulum.ps1', 'Kurulum.cmd', 'Kurulum-Admin.cmd', 'Kurulum-Kullanici.cmd', 'Kur.ps1', 'Kur.cmd', 'README.md', 'PAKET-MANIFEST.json', 'uygulama/hatirlatici/kurallar.varsayilan.json', 'uygulama/hatirlatici/ayarlar.varsayilan.json', 'uygulama/hatirlatici/periyot.varsayilan.json', 'uygulama/hatirlatici/ozellikler.ps1', 'uygulama/hatirlatici/wiki.ps1', 'uygulama/hatirlatici/ayarlar-penceresi.ps1', 'uygulama/hatirlatici/wiki-penceresi.ps1', 'uygulama/wiki/baslarken.md', 'uygulama/wiki/hatirlatmalar.md')) {
            if ($adlar -notcontains $gerekli) {
                throw "Paket gerekli dosyayı içermiyor: $gerekli"
            }
        }

        $yasakliDesenler = @(
            '(^|/)aktivite(/|$)',
            '(^|/)rapor(/|$)',
            '(^|/)veri(/|$)',
            '(^|/)cihaz-paketleri(/|$)',
            '(^|/)cikti(/|$)',
            '(^|/)(kurallar|ayarlar|periyot|merkez-kurallar|kural-outbox|ortak-sayac|onay)\.json$',
            '(^|/)durum\.json$',
            '(^|/)gecmis\.json$',
            '(^|/)merkez\.json$',
            '(^|/)merkez-ayarlari\.json$',
            '\.csv$',
            '\.log$',
            '\.pid$'
        )

        foreach ($ad in $adlar) {
            foreach ($desen in $yasakliDesenler) {
                if ($ad -match $desen) {
                    throw "Kişisel veya çalışma zamanı verisi pakete sızdı: $ad"
                }
            }
        }
    }
    finally {
        $arsiv.Dispose()
    }
}

function Remove-GeciciKlasor {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Yol
    )

    $tempKoku = (Get-TamYol -Yol ([System.IO.Path]::GetTempPath())).TrimEnd('\') + '\'
    $tamYol = Get-TamYol -Yol $Yol
    if (-not $tamYol.StartsWith($tempKoku, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Geçici klasör beklenen temp kökünde değil: $tamYol"
    }

    if (Test-Path -LiteralPath $tamYol -PathType Container) {
        Remove-Item -LiteralPath $tamYol -Recurse -Force
    }
}

$dagitikKoku = Get-TamYol -Yol $PSScriptRoot
$projeKoku = Split-Path -Parent $dagitikKoku
$hatirlaticiKoku = Join-Path $projeKoku 'hatirlatici'
$kurulumKoku = Join-Path $dagitikKoku 'kurulum'

foreach ($gerekliYol in @($hatirlaticiKoku, $kurulumKoku)) {
    if (-not (Test-Path -LiteralPath $gerekliYol -PathType Container)) {
        throw "Gerekli kaynak klasörü bulunamadı: $gerekliYol"
    }
}

if ([string]::IsNullOrWhiteSpace($CiktiYolu)) {
    $CiktiYolu = Join-Path $dagitikKoku 'cikti\Aizen-Kurulum.zip'
}
$CiktiYolu = Get-TamYol -Yol $CiktiYolu
if ([System.IO.Path]::GetExtension($CiktiYolu) -ine '.zip') {
    throw 'Çıktı yolu .zip uzantılı olmalıdır.'
}

$ciktiKlasoru = Split-Path -Parent $CiktiYolu
if (-not (Test-Path -LiteralPath $ciktiKlasoru -PathType Container)) {
    New-Item -ItemType Directory -Path $ciktiKlasoru -Force | Out-Null
}

$geciciKoku = Join-Path ([System.IO.Path]::GetTempPath()) ("calisma-takip-paket-" + [Guid]::NewGuid().ToString('N'))
$sahneKoku = Join-Path $geciciKoku 'Calisma-Takip-Dagitik-Kurulum'

try {
    New-Item -ItemType Directory -Path $sahneKoku -Force | Out-Null

    foreach ($dosyaAdi in @('Kurulum.ps1', 'Kurulum.cmd', 'Kurulum-Admin.cmd', 'Kurulum-Kullanici.cmd', 'Kur.ps1', 'Kur.cmd', 'README.md')) {
        $kaynak = Join-Path $kurulumKoku $dosyaAdi
        if (-not (Test-Path -LiteralPath $kaynak -PathType Leaf)) {
            throw "Kurulum dosyası bulunamadı: $kaynak"
        }
        Copy-Item -LiteralPath $kaynak -Destination (Join-Path $sahneKoku $dosyaAdi) -Force
    }

    $uygulamaKoku = Join-Path $sahneKoku 'uygulama'
    New-Item -ItemType Directory -Path $uygulamaKoku -Force | Out-Null

    $projeReadme = Join-Path $projeKoku 'README.md'
    if (Test-Path -LiteralPath $projeReadme -PathType Leaf) {
        Copy-Item -LiteralPath $projeReadme -Destination (Join-Path $uygulamaKoku 'README.md') -Force
    }

    $hatirlaticiHedefi = Join-Path $uygulamaKoku 'hatirlatici'
    foreach ($dosya in Get-ChildItem -LiteralPath $hatirlaticiKoku -File -Recurse) {
        $dahilEt = $false
        if ($dosya.Extension -in @('.ps1', '.vbs') -and $dosya.Name -notmatch '^test([-.]|\.ps1$)') {
            $dahilEt = $true
        }
        # Canli ayar/periyot/kural dosyalari degil, notr sablonlari tasinir: paketi ureten
        # makine duraklatilmis ya da periyot acikken bu durum yeni kurulumlara gitmesin.
        elseif ($dosya.Name -in @('kurallar.varsayilan.json', 'ayarlar.varsayilan.json', 'periyot.varsayilan.json', 'README.md')) {
            $dahilEt = $true
        }

        if ($dahilEt) {
            Copy-StageDosyasi -Dosya $dosya -KaynakKoku $hatirlaticiKoku -HedefKoku $hatirlaticiHedefi
        }
    }

    # Uygulama ici yardim: wiki-penceresi.ps1 <kurulum>\wiki klasorunu okur. README yazarlar icindir.
    $wikiKoku = Join-Path $projeKoku 'wiki'
    $wikiHedefi = Join-Path $uygulamaKoku 'wiki'
    foreach ($dosya in Get-ChildItem -LiteralPath $wikiKoku -File -Filter '*.md') {
        if ($dosya.Name -ieq 'README.md') { continue }
        Copy-StageDosyasi -Dosya $dosya -KaynakKoku $wikiKoku -HedefKoku $wikiHedefi
    }

    $dagitikHedefi = Join-Path $uygulamaKoku 'dagitik'
    foreach ($dosya in Get-ChildItem -LiteralPath $dagitikKoku -File -Recurse) {
        $goreliYol = (Get-TamYol -Yol $dosya.FullName).Substring(((Get-TamYol -Yol $dagitikKoku).TrimEnd('\') + '\').Length).Replace('\', '/')
        $canliKlasor = $goreliYol -match '^(kurulum|veri|cihaz-paketleri|cikti)(/|$)'
        $canliYapilandirma = $dosya.Name -in @('merkez.json', 'merkez-ayarlari.json', 'kurulum-bilgisi.json')
        $sablonJson = $dosya.Extension -ieq '.json' -and $dosya.Name -match '(^|[-_])(ornek|varsayilan|sablon)([-_]|\.)'
        $calisabilirDosya = $dosya.Extension -in @('.ps1', '.cmd', '.vbs', '.md') -and $dosya.Name -notmatch '^test([-.]|\.ps1$)' -and $dosya.Name -ne 'paket-olustur.ps1'

        if (-not $canliKlasor -and -not $canliYapilandirma -and ($calisabilirDosya -or $sablonJson)) {
            Copy-StageDosyasi -Dosya $dosya -KaynakKoku $dagitikKoku -HedefKoku $dagitikHedefi
        }
    }

    $manifest = [ordered]@{
        paketAdi        = 'Calisma-Takip-Dagitik-Kurulum'
        paketSurumu     = 1
        olusturulmaUtc  = [DateTime]::UtcNow.ToString('o')
        dosyalar        = @(Get-DosyaManifesti -Kok $sahneKoku)
    }
    Write-Utf8Bom -Yol (Join-Path $sahneKoku 'PAKET-MANIFEST.json') -Metin ($manifest | ConvertTo-Json -Depth 6)

    Compress-Archive -Path (Join-Path $sahneKoku '*') -DestinationPath $CiktiYolu -Force
    Test-PaketIcerigi -ZipYolu $CiktiYolu

    $hash = Get-PaketSha256 -Yol $CiktiYolu
    $hashYolu = "$CiktiYolu.sha256"
    Write-Utf8Bom -Yol $hashYolu -Metin ("$hash  " + [System.IO.Path]::GetFileName($CiktiYolu) + "`r`n")

    # ---- Tek dosya kurulum (Windows'un kendi IExpress aracıyla) ----
    # İçinde ZIP + Baslat.cmd vardır: çalıştırılınca geçici klasöre açılır ve
    # kurulum sihirbazı başlar. İmzalı değildir; SmartScreen uyarısı çıkabilir.
    $exeYolu = ''
    $exeHash = ''
    if (-not $ExeAtla) {
        $iexpress = Join-Path $env:WINDIR 'System32\iexpress.exe'
        if (-not (Test-Path -LiteralPath $iexpress -PathType Leaf)) {
            Write-Warning 'iexpress.exe bulunamadı; tek dosya kurulum üretilmedi. ZIP kullanılabilir.'
        }
        else {
            $sfxKoku = Join-Path $geciciKoku 'sfx'
            New-Item -ItemType Directory -Path $sfxKoku -Force | Out-Null
            # Baslat.cmd bu sabit adi acar; cikti ZIP'inin adindan bagimsiz (eskiden -CiktiYolu farkli adla verilince EXE acilmiyordu)
            $zipAdi = 'Calisma-Takip-Dagitik-Kurulum.zip'
            Copy-Item -LiteralPath $CiktiYolu -Destination (Join-Path $sfxKoku $zipAdi) -Force
            $baslatKaynak = Join-Path $kurulumKoku 'Baslat.cmd'
            if (-not (Test-Path -LiteralPath $baslatKaynak -PathType Leaf)) {
                throw "Tek dosya kurulum başlatıcısı bulunamadı: $baslatKaynak"
            }
            Copy-Item -LiteralPath $baslatKaynak -Destination (Join-Path $sfxKoku 'Baslat.cmd') -Force

            $exeYolu = Join-Path (Split-Path -Parent $CiktiYolu) 'Aizen-Kurulum.exe'
            if (Test-Path -LiteralPath $exeYolu) { Remove-Item -LiteralPath $exeYolu -Force }
            $sedYolu = Join-Path $geciciKoku 'paket.sed'
            $sedMetni = @"
[Version]
Class=IEXPRESS
SEDVersion=3
[Options]
PackagePurpose=InstallApp
ShowInstallProgramWindow=0
HideExtractAnimation=1
UseLongFileName=1
InsideCompressed=0
CAB_FixedSize=0
CAB_ResvCodeSigning=0
RebootMode=N
InstallPrompt=%InstallPrompt%
DisplayLicense=%DisplayLicense%
FinishMessage=%FinishMessage%
TargetName=%TargetName%
FriendlyName=%FriendlyName%
AppLaunched=%AppLaunched%
PostInstallCmd=%PostInstallCmd%
AdminQuietInstCmd=%AdminQuietInstCmd%
UserQuietInstCmd=%UserQuietInstCmd%
SourceFiles=SourceFiles
[Strings]
InstallPrompt=
DisplayLicense=
FinishMessage=
TargetName=$exeYolu
FriendlyName=Aizen Kurulumu
AppLaunched=cmd.exe /c Baslat.cmd
PostInstallCmd=<None>
AdminQuietInstCmd=
UserQuietInstCmd=
FILE0="$zipAdi"
FILE1="Baslat.cmd"
[SourceFiles]
SourceFiles0=$sfxKoku
[SourceFiles0]
%FILE0%=
%FILE1%=
"@
            [System.IO.File]::WriteAllText($sedYolu, $sedMetni, [System.Text.Encoding]::ASCII)
            & $iexpress /N /Q $sedYolu | Out-Null
            if (-not (Test-Path -LiteralPath $exeYolu -PathType Leaf)) {
                throw 'Tek dosya kurulum üretilemedi (iexpress).'
            }
            $exeHash = Get-PaketSha256 -Yol $exeYolu
            Write-Utf8Bom -Yol "$exeYolu.sha256" -Metin ("$exeHash  " + [System.IO.Path]::GetFileName($exeYolu) + "`r`n")
        }
    }

    Write-Host 'Dağıtım paketi hazırlandı.' -ForegroundColor Green
    Write-Host "ZIP: $CiktiYolu"
    Write-Host "SHA-256: $hash"
    if (-not [string]::IsNullOrWhiteSpace($exeYolu)) {
        Write-Host "EXE: $exeYolu" -ForegroundColor Green
        Write-Host "SHA-256: $exeHash"
    }
}
finally {
    if (Test-Path -LiteralPath $geciciKoku -PathType Container) {
        Remove-GeciciKlasor -Yol $geciciKoku
    }
}
