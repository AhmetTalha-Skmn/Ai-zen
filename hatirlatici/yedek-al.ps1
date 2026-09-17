# ============================================================
#  Ölçüm verisinin yedeği. Kod geri gelir, veri gelmez: aktivite kayıtları,
#  raporlar, sayaç, geçmiş ve kurallar tek klasörde duruyor ve git'e girmiyor.
#
#  Varsayılan hedef Belgeler altındadır. Bulut klasörü (OneDrive vb.) bilerek
#  varsayılan DEĞİL: veri dışarı çıkacaksa kullanıcı -Hedef ile açıkça seçer.
#
#  Kullanım:
#    .\yedek-al.ps1                       varsayılan klasöre yedek al
#    .\yedek-al.ps1 -Hedef D:\Yedek       başka klasöre
#    .\yedek-al.ps1 -Saklama 12 -Zorla    12 yedek sakla, bugünkini yeniden üret
# ============================================================
param(
    [string]$Hedef,
    [string]$KaynakKok,
    [switch]$Eksiksiz,
    [int]$Saklama = 8,
    [switch]$Zorla,
    [switch]$Sessiz,
    [string]$LogYolu
)

$ErrorActionPreference = 'Stop'
$hDir = $PSScriptRoot
if (-not $hDir) { $hDir = Split-Path $MyInvocation.MyCommand.Path -Parent }
. (Join-Path $PSScriptRoot 'Yedek-Ortak.ps1')
if ($KaynakKok) { $hDir = Join-Path (Assert-CtNormalYol $KaynakKok) 'hatirlatici' }
$klasor = Split-Path $hDir -Parent
$logD = if ($LogYolu) { $LogYolu } else { Join-Path $hDir 'log.txt' }

function Log {
    param([string]$m)
    try { "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))  [yedek] $m" | Out-File -FilePath $logD -Encoding utf8 -Append } catch { }
}

function Yaz {
    param([string]$m)
    if (-not $Sessiz) { Write-Output $m }
}

# Izleyici CSV'ye yazarken dosya kilitli olabilir; paylasimli okumayla kopyalanir
function Kopyala-Guvenli {
    param([string]$Kaynak, [string]$HedefYol)
    [void](Assert-CtNormalYol $Kaynak)
    try {
        Copy-Item -LiteralPath $Kaynak -Destination $HedefYol -Force
        return $true
    }
    catch {
        try {
            $giris = [IO.File]::Open($Kaynak, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
            try {
                $cikis = [IO.File]::Create($HedefYol)
                try { $giris.CopyTo($cikis) } finally { $cikis.Dispose() }
            }
            finally { $giris.Dispose() }
            return $true
        }
        catch { return $false }
    }
}

if ([string]::IsNullOrWhiteSpace($Hedef)) {
    $ayarYolu = Join-Path $hDir 'ayarlar.json'
    if (Test-Path -LiteralPath $ayarYolu) {
        try {
            $ayar = Get-Content -LiteralPath $ayarYolu -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($ayar -and $ayar.PSObject.Properties['yedekKlasoru']) {
                $Hedef = [string]$ayar.yedekKlasoru
            }
        }
        catch { }
    }
}
if ([string]::IsNullOrWhiteSpace($Hedef)) {
    $Hedef = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'CalismaTakipYedek'
}
[void][IO.Directory]::CreateDirectory($Hedef)

$bugun = (Get-Date).ToString('yyyy-MM-dd')
$zipYolu = Join-Path $Hedef "calisma-takip-yedek-$bugun.zip"
if ((Test-Path -LiteralPath $zipYolu) -and -not $Zorla) {
    Yaz "Bugunun yedegi zaten var: $zipYolu"
    exit 0
}

$gecici = Join-Path $env:TEMP ('ct-yedek-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$sahne = Join-Path $gecici 'yedek'
[void][IO.Directory]::CreateDirectory($sahne)
$kopyalanan = 0
$atlanan = @()

try {
    # 1) Tekil ayar ve sayac dosyalari
    foreach ($ad in 'durum.json', 'gecmis.json', 'kurallar.json', 'ayarlar.json', 'periyot.json') {
        $kaynak = Join-Path $hDir $ad
        if (-not (Test-Path -LiteralPath $kaynak)) { continue }
        if (Kopyala-Guvenli $kaynak (Join-Path $sahne $ad)) { $kopyalanan++ } else { $atlanan += $ad }
    }

    # 2) Ham olcum ve raporlar
    foreach ($altKlasor in 'aktivite', 'rapor') {
        $kaynakKok = Join-Path $hDir $altKlasor
        if (-not (Test-Path -LiteralPath $kaynakKok)) { continue }
        $hedefKok = Join-Path $sahne $altKlasor
        [void][IO.Directory]::CreateDirectory($hedefKok)
        foreach ($dosya in @(Get-ChildItem -LiteralPath $kaynakKok -File -ErrorAction SilentlyContinue)) {
            if (Kopyala-Guvenli $dosya.FullName (Join-Path $hedefKok $dosya.Name)) { $kopyalanan++ }
            else { $atlanan += "$altKlasor\$($dosya.Name)" }
        }
    }

    # 3) Gunluk notlar (uygulama kokunde)
    $gunlukKok = Join-Path $klasor 'Gunluk'
    if (Test-Path -LiteralPath $gunlukKok) {
        $hedefKok = Join-Path $sahne 'Gunluk'
        [void][IO.Directory]::CreateDirectory($hedefKok)
        foreach ($dosya in @(Get-ChildItem -LiteralPath $gunlukKok -File -ErrorAction SilentlyContinue)) {
            if (Kopyala-Guvenli $dosya.FullName (Join-Path $hedefKok $dosya.Name)) { $kopyalanan++ }
            else { $atlanan += "Gunluk\$($dosya.Name)" }
        }
    }

    if ($kopyalanan -eq 0 -and -not $Eksiksiz) {
        Yaz 'Yedeklenecek veri bulunamadi.'
        Log 'yedeklenecek veri yok'
        exit 0
    }

    [void][IO.File]::WriteAllText((Join-Path $sahne 'YEDEK-BILGISI.txt'), (@(
        'Aizen - veri yedegi',
        "Tarih      : $((Get-Date).ToString('yyyy-MM-dd HH:mm'))",
        "Bilgisayar : $env:COMPUTERNAME ($env:USERNAME)",
        "Kaynak     : $hDir",
        "Dosya      : $kopyalanan",
        '',
        'Geri yuklemek icin yedek-geri-yukle.ps1 kullanin; Gunluk uygulama kokune gider.',
        'Aktivite CSV dosyalari ham olcumdur; rapor ve gunluk notlar yeniden uretilebilir.'
    ) -join [Environment]::NewLine), (New-Object Text.UTF8Encoding($true)))

    if ($atlanan.Count -gt 0 -and $Eksiksiz) { throw 'Güvenlik yedeği eksik; geri yükleme başlamadı.' }
    Write-CtYedekManifesti $sahne
    $yeniZip = Join-Path $gecici 'yeni.zip'
    Compress-Archive -Path (Join-Path $sahne '*') -DestinationPath $yeniZip -Force
    [void](Test-CtVeriYedegi $yeniZip)
    Move-Item -LiteralPath $yeniZip -Destination $zipYolu -Force
    $boyutKb = [math]::Round((Get-Item -LiteralPath $zipYolu).Length / 1KB)

    # Saklama: en yeni N yedek kalir
    $silinen = 0
    if ($Saklama -gt 0) {
        $eskiler = @(Get-ChildItem -LiteralPath $Hedef -Filter 'calisma-takip-yedek-*.zip' -File -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending | Select-Object -Skip $Saklama)
        foreach ($eski in $eskiler) {
            Remove-Item -LiteralPath $eski.FullName -Force -ErrorAction SilentlyContinue
            $silinen++
        }
    }

    Yaz "Yedek alindi: $zipYolu ($kopyalanan dosya, $boyutKb KB)"
    if ($atlanan.Count -gt 0) { Yaz "Kopyalanamayan: $($atlanan -join ', ')" }
    if ($silinen -gt 0) { Yaz "Eski yedek silindi: $silinen" }
    Log "yedek: $zipYolu, $kopyalanan dosya, $boyutKb KB, atlanan=$($atlanan.Count), silinen=$silinen"
}
finally {
    if (Test-Path -LiteralPath $gecici) {
        $tempKok = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') + '\'
        if (-not [IO.Path]::GetFullPath($gecici).StartsWith($tempKok,[StringComparison]::OrdinalIgnoreCase)) { throw 'Geçici yedek yolu geçersiz.' }
        Remove-Item -LiteralPath $gecici -Recurse -Force -ErrorAction SilentlyContinue
    }
}
