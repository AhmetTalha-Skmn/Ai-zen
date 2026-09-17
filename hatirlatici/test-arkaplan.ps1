# Arka plan davranis testi
$ErrorActionPreference = 'Continue'
$hDir = $PSScriptRoot; if (-not $hDir) { $hDir = Split-Path $MyInvocation.MyCommand.Path -Parent }
$klasor  = Split-Path $hDir -Parent
$gorevAd = 'Calisma Takip Sistemi'
$psExe   = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$takipPs = Join-Path $hDir 'takip.ps1'
$aktCsv  = Join-Path $hDir "aktivite\$((Get-Date).ToString('yyyy-MM-dd')).csv"
$env:CALISMATAKIP_TEST_SN = '3'   # test pencereleri 3 sn sonra kendi kapanir
$gecti=0; $kaldi=0
function T { param($ad,$ok,$d)
  if ($ok) { $script:gecti++; Write-Host ("  [OK]   {0,-44} {1}" -f $ad,$d) -ForegroundColor Green }
  else     { $script:kaldi++; Write-Host ("  [HATA] {0,-44} {1}" -f $ad,$d) -ForegroundColor Red } }

Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices;
public class WE {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern int GetWindowThreadProcessId(IntPtr h, out int pid);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
}
"@

function GorunurPencereler {
  $liste = New-Object System.Collections.ArrayList
  $cb = [WE+EnumProc]{ param($h,$l)
    if ([WE]::IsWindowVisible($h)) {
      $sb = New-Object System.Text.StringBuilder 300
      [void][WE]::GetWindowText($h,$sb,300)
      $t = $sb.ToString()
      if ($t.Trim().Length -gt 0) {
        $pid2=0; [void][WE]::GetWindowThreadProcessId($h,[ref]$pid2)
        $pn = (Get-Process -Id $pid2 -ErrorAction SilentlyContinue).ProcessName
        [void]$liste.Add("$pn|$t")
      }
    }
    return $true }
  [void][WE]::EnumWindows($cb,[IntPtr]::Zero)
  return $liste }

Write-Host "`n=== A. EKRANI OKUYOR MU? (uygulama degistirerek) ===" -ForegroundColor Cyan
# Uyari diyalogu cikmasin diye sonUyari'yi simdiye cek
$dj = Get-Content (Join-Path $hDir 'durum.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$dj.sonUyari = (Get-Date).ToString('s')
$dj | ConvertTo-Json | Out-File (Join-Path $hDir 'durum.json') -Encoding utf8

$denekler = @(
  @{ ad='notepad';  komut='notepad.exe';  beklenen='notepad' },
  @{ ad='calc';     komut='calc.exe';     beklenen='CalculatorApp|Calculator' },
  @{ ad='mspaint';  komut='mspaint.exe';  beklenen='mspaint' }
)
foreach ($dn in $denekler) {
    $p = Start-Process $dn.komut -PassThru
    Start-Sleep -Seconds 2
    $hnd = (Get-Process | Where-Object { $_.MainWindowTitle -ne '' -and $_.ProcessName -match $dn.ad } | Select-Object -First 1).MainWindowHandle
    if (-not $hnd) { $hnd = (Get-Process | Where-Object { $_.MainWindowTitle -match 'Hesap|Calculator|Adsız|Untitled|Paint' } | Select-Object -First 1).MainWindowHandle }
    if ($hnd) { [void][WE]::SetForegroundWindow($hnd); Start-Sleep -Milliseconds 800 }

    # izleyici 10 sn'de bir ornekliyor -- taze ornek gelene kadar bekle
    $oncekiSayi = @(Get-Content $aktCsv -Encoding UTF8).Count
    $satirlar = @()
    for ($w = 0; $w -lt 35; $w++) {
        Start-Sleep -Milliseconds 700
        $satirlar = @(Get-Content $aktCsv -Encoding UTF8)
        if ($satirlar.Count -gt $oncekiSayi) { break }
    }
    $son = $satirlar[-1]
    $alan = $son -split ';'
    $okundu = $alan[1]
    $kategori = $alan[4]
    T "$($dn.ad) on planda okundu" ($satirlar.Count -gt $oncekiSayi) "kaydedilen: $okundu / kategori: $kategori"
    $kaynak = $alan[6]
    if ($okundu -match 'otepad|mspaint|ApplicationFrameHost') {
        # Beklentiyi kurallardan turet -- listeler her gun degisiyor
        $KK = Get-Content (Join-Path $hDir 'kurallar.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        function Esl2 { param($m,$l) foreach ($x in $l) { if ($x -and $m -like "*$x*") { return $true } }; return $false }
        $bek = 'belirsiz'
        if (Esl2 $okundu $KK.yasakli.surec)      { $bek = 'yasakli' }
        elseif (Esl2 $okundu $KK.calisma.surec)  { $bek = 'izinli' }
        T "$($dn.ad) kurallara uygun siniflandi" ($kaynak -eq $bek) "beklenen=$bek gelen=$kaynak"
    } else {
        Write-Host ("  [ATLA] {0,-44} {1}" -f "$($dn.ad) siniflandirma", "on plan degisti -> $okundu") -ForegroundColor Yellow
    }
    Get-Process -Id $p.Id -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
}

Write-Host "`n=== B. ARKA PLANDA MI? (ekrana bir sey firlatiyor mu) ===" -ForegroundColor Cyan
$once = GorunurPencereler
& $psExe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File $takipPs
$yeniler = @()
for ($i=0; $i -lt 40; $i++) {
    Start-Sleep -Milliseconds 150
    foreach ($w in (GorunurPencereler)) { if ($once -notcontains $w -and $yeniler -notcontains $w) { $yeniler += $w } }
}
$psPencere = @($yeniler | Where-Object { $_ -match '^(powershell|pwsh|conhost|WindowsTerminal)\|' })
T "PowerShell konsolu gorunmedi" ($psPencere.Count -eq 0) "$($psPencere.Count) pencere"
$diyalog = @($yeniler | Where-Object { $_ -match 'Aizen|Calisma Takibi|Hedef tamamlandi' })
T "beklenmeyen diyalog acilmadi" ($diyalog.Count -eq 0) "$($diyalog.Count) diyalog"
if ($yeniler.Count -gt 0) { Write-Host "     (gorulen yeni pencereler: $($yeniler -join ' , '))" -ForegroundColor DarkGray }

Write-Host "`n=== B2. KONSOL FLASI (gorev zamanlayici ile baslatma) ===" -ForegroundColor Cyan
Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices;
public class KF {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
}
"@
function KonsolSay {
  $n = 0
  $cb = [KF+EnumProc]{ param($h,$l)
    if ([KF]::IsWindowVisible($h)) {
      $sb = New-Object System.Text.StringBuilder 128
      [void][KF]::GetClassName($h,$sb,128)
      if ($sb.ToString() -match 'Console|CASCADIA|PseudoConsole') { $script:n++ }
    }
    return $true }
  [void][KF]::EnumWindows($cb,[IntPtr]::Zero)
  return $n }
$temelSayi = KonsolSay
$flas = 0
Start-ScheduledTask -TaskName $gorevAd
for ($i=0; $i -lt 300; $i++) {
    Start-Sleep -Milliseconds 15
    $simdiki = KonsolSay
    if ($simdiki -gt $temelSayi) { $flas++ }
}
T "konsol penceresi acilmadi" ($flas -eq 0) "$flas tespit (15 ms araliklarla 4.5 sn)"
$gAct = (Get-ScheduledTask -TaskName $gorevAd).Actions[0]
T "gorev wscript ile baslatiyor" ($gAct.Execute -match 'wscript\.exe') $gAct.Execute
T "gizli.vbs mevcut" (Test-Path (Join-Path $hDir 'gizli.vbs')) ''

Write-Host "`n=== C. GOREV YAPILANDIRMASI (acilista calisir mi) ===" -ForegroundColor Cyan
$t = Get-ScheduledTask -TaskName $gorevAd -ErrorAction SilentlyContinue
T "gorev kayitli" ($t -ne $null) ''
if ($t) {
    $i = Get-ScheduledTaskInfo -TaskName $gorevAd
    $act = $t.Actions[0]
    T "durum Ready"                ($t.State -eq 'Ready') $t.State
    T "NextRunTime dolu"           ($i.NextRunTime -ne $null) "$($i.NextRunTime)"
    $vbsIcerik = ''
    if (Test-Path (Join-Path $hDir 'gizli.vbs')) { $vbsIcerik = Get-Content (Join-Path $hDir 'gizli.vbs') -Raw }
    T "gizli.vbs uzerinden cagriliyor" ($act.Arguments -match 'gizli\.vbs') ''
    T "//B batch modu"                ($act.Arguments -match '//B') ''
    T "VBS: pencere stili 0 (gizli)"  ($vbsIcerik -match 'sh\.Run cmd, 0, False') ''
    T "VBS: -WindowStyle Hidden"      ($vbsIcerik -match 'WindowStyle Hidden') ''
    T "VBS: -ExecutionPolicy Bypass"  ($vbsIcerik -match 'ExecutionPolicy Bypass') ''
    T "script yolu gecerli"        (Test-Path $takipPs) ''
    T "logon tetikleyicisi var"    (@($t.Triggers | Where-Object { $_.CimClass.CimClassName -eq 'MSFT_TaskLogonTrigger' }).Count -eq 1) ''
    T "gunluk tetikleyici var"     (@($t.Triggers | Where-Object { $_.CimClass.CimClassName -eq 'MSFT_TaskDailyTrigger' }).Count -eq 1) ''
    T "her ikisinde 5 dk tekrar"   (($t.Triggers[0].Repetition.Interval -eq 'PT5M') -and ($t.Triggers[1].Repetition.Interval -eq 'PT5M')) ''
    T "kacirilani telafi et"       ($t.Settings.StartWhenAvailable) ''
    T "pilde de calisir"           (-not $t.Settings.DisallowStartIfOnBatteries) ''
    T "pile gecince durmaz"        (-not $t.Settings.StopIfGoingOnBatteries) ''
    T "hata halinde yeniden dene"  ($t.Settings.RestartCount -ge 1) "$($t.Settings.RestartCount) kez"
    T "gorev etkin"                ($t.Settings.Enabled) ''
    T "kullanici oturumunda calisir" ($t.Principal.LogonType -in @('Interactive','InteractiveToken','InteractiveTokenOrPassword','S4U')) $t.Principal.LogonType
}

Write-Host "`n=== D. STARTUP WATCHDOG ===" -ForegroundColor Cyan
$startup = [Environment]::GetFolderPath('Startup')
$lnkYol = Join-Path $startup 'Aizen.lnk'
T "kisayol var" (Test-Path $lnkYol) ''
if (Test-Path $lnkYol) {
    $ws = New-Object -ComObject WScript.Shell
    $sc = $ws.CreateShortcut($lnkYol)
    T "hedef wscript.exe"        ($sc.TargetPath -match 'wscript\.exe') $sc.TargetPath
    T "gizli.vbs uzerinden"      ($sc.Arguments -match 'gizli\.vbs') ''
    T "baslangic.ps1'i cagiriyor" ($sc.Arguments -match 'baslangic\.ps1') ''
    T "//B batch modu"           ($sc.Arguments -match '//B') ''
    T "kisayol minimize (7)"      ($sc.WindowStyle -eq 7) "WindowStyle=$($sc.WindowStyle)"
    T "hedef script mevcut"       (Test-Path (Join-Path $hDir 'baslangic.ps1')) ''
}

Write-Host "`n=== E. AKTIFKEN SESSIZ KALIYOR MU ===" -ForegroundColor Cyan
$oncePenc = GorunurPencereler
& $psExe -NoProfile -ExecutionPolicy Bypass -File $takipPs
Start-Sleep -Seconds 3
$sonLog = (Get-Content (Join-Path $hDir 'log.txt') -Encoding UTF8 -Tail 1)
T "tick loglandi" ($sonLog -match 'tick|DURAKLATILDI') $sonLog
$sonrPenc = GorunurPencereler
# Sadece KENDI sureclerimizin pencerelerine bak -- kullanici bu sirada
# baska uygulama acmis olabilir, o bizim sorunumuz degil.
$fark = @($sonrPenc | Where-Object { $oncePenc -notcontains $_ -and $_ -match '^(powershell|pwsh|conhost|WindowsTerminal|wscript)\|' })
T "kendi surecimizden pencere kalmadi" ($fark.Count -eq 0) "$($fark.Count)  (tum yeni pencereler: $(@($sonrPenc | Where-Object { $oncePenc -notcontains $_ }).Count))"

Write-Host "`n===================================" -ForegroundColor Cyan
Write-Host ("  GECTI: {0}   KALDI: {1}" -f $gecti,$kaldi) -ForegroundColor $(if($kaldi -eq 0){'Green'}else{'Red'})
Write-Host "===================================`n" -ForegroundColor Cyan










# --- Test bitti: acilan pencereleri ve gecici kasalari topla ---
$env:CALISMATAKIP_TEST_SN = ''
& $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $hDir 'test-temizlik.ps1') | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
