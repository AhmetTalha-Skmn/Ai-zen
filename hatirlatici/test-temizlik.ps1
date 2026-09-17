# ============================================================
#  Test temizligi -- testlerin actigi pencere ve gecici kasalari kapatir
#  Testler bittiginde otomatik cagrilir; elle de calistirilabilir.
# ============================================================
$ErrorActionPreference = 'SilentlyContinue'
$hDir = $PSScriptRoot; if (-not $hDir) { $hDir = Split-Path $MyInvocation.MyCommand.Path -Parent }

$kasalar = @('diyalog-testi','phptest-kasa','php-kapsamli','izole-dbg','php-dbg','php-dbg2','seri-dbg')
$kapatilan = 0; $silinen = 0

# 1) Gecici kasadan calisan powershell/wscript sureclerini kapat
#    (kendi surecimizi ASLA kapatma)
$benim = $PID
foreach ($p in (Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='wscript.exe'")) {
    if ($p.ProcessId -eq $benim) { continue }
    if (-not $p.CommandLine) { continue }
    $esles = $false
    foreach ($k in $kasalar) {
        # Gercek dosya yolu araniyor, duz metin degil -- kendi komutunu yakalamasin
        if ($p.CommandLine -like "*\Temp\$k\*") { $esles = $true; break }
    }
    if ($esles) { Stop-Process -Id $p.ProcessId -Force; $kapatilan++ }
}

# 2) Test amacli acilan yardimci uygulamalar
foreach ($ad in @('notepad','mspaint')) {
    foreach ($p in (Get-Process -Name $ad -ErrorAction SilentlyContinue)) { Stop-Process -Id $p.Id -Force; $kapatilan++ }
}

Start-Sleep -Milliseconds 600

# 3) Gecici kasalari sil
foreach ($k in $kasalar) {
    $yol = Join-Path $env:TEMP $k
    if ([System.IO.Directory]::Exists($yol)) {
        try { [System.IO.Directory]::Delete($yol, $true); $silinen++ } catch { }
    }
}

Write-Output "temizlik: $kapatilan surec kapatildi, $silinen gecici kasa silindi"
