$bakimIsareti = Join-Path $PSScriptRoot 'GERI-YUKLEME'; if (Test-Path -LiteralPath $bakimIsareti) { try { [IO.File]::Open($bakimIsareti, 'Open', 'ReadWrite', 'None').Dispose(); [IO.File]::Delete($bakimIsareti) } catch { exit 0 } }
# Acilis kontrolu -- her oturum acilisinda calisir.
# 1) Zamanlanmis gorev duruyor mu, NextRunTime dolu mu diye bakar
# 2) Gorev yoksa ya da eylemi eskiyse (powershell dogrudan / baska klasor) yeniden kurar
# 3) Bir tur takip calistirir
$ErrorActionPreference = 'SilentlyContinue'

$hDir = $PSScriptRoot
if (-not $hDir) { $hDir = Split-Path $MyInvocation.MyCommand.Path -Parent }
$klasor = Split-Path $hDir -Parent
$takipPs = Join-Path $hDir 'takip.ps1'
$logD    = Join-Path $hDir 'log.txt'
$gorevAd = 'Calisma Takip Sistemi'
$vbsYol  = Join-Path $hDir 'gizli.vbs'

function Log { param($m)
    "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))  [acilis] $m" | Out-File -FilePath $logD -Encoding utf8 -Append
}

function GorevKur {
    # powershell.exe dogrudan baslatilirsa her 5 dakikada konsol flasi olur;
    # wscript + gizli.vbs hic konsol ayirmaz. Tek ornek kilidi takip.ps1'de.
    $eylem = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\wscript.exe" `
        -Argument "//B //Nologo `"$vbsYol`" `"$takipPs`"" `
        -WorkingDirectory $klasor

    # Gunluk: acik olan oturumlarda gun boyu tekrar
    $gunluk = New-ScheduledTaskTrigger -Daily -At '00:00'
    $gunluk.Repetition = (New-ScheduledTaskTrigger -Once -At '00:00' `
        -RepetitionInterval (New-TimeSpan -Minutes 5) `
        -RepetitionDuration (New-TimeSpan -Hours 23 -Minutes 55)).Repetition

    # Oturum acilisi: bilgisayar yeni acildiginda tekrari BASLATIR
    $logon = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    $logon.Delay = 'PT1M'
    $logon.Repetition = (New-ScheduledTaskTrigger -Once -At '00:00' `
        -RepetitionInterval (New-TimeSpan -Minutes 5) `
        -RepetitionDuration (New-TimeSpan -Hours 23 -Minutes 55)).Repetition

    $ayar = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -StartWhenAvailable -MultipleInstances IgnoreNew `
        -ExecutionTimeLimit (New-TimeSpan -Hours 2) `
        -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)

    Register-ScheduledTask -TaskName $gorevAd -Action $eylem -Trigger @($gunluk, $logon) `
        -Settings $ayar -Force `
        -Description 'Aizen - 5 dk ölçüm turu' | Out-Null
}

$g = Get-ScheduledTask -TaskName $gorevAd -ErrorAction SilentlyContinue

if (-not $g) {
    Log 'GOREV YOK -> yeniden kuruluyor'
    GorevKur
    $g = Get-ScheduledTask -TaskName $gorevAd
}
elseif ($g.State -eq 'Disabled') {
    # Kullanici bilerek kapatmis olabilir -- dokunma, sadece not dus
    Log 'gorev DEVRE DISI (kullanici kapatmis) -- dokunulmadi'
    exit
}
else {
    $inf = Get-ScheduledTaskInfo -TaskName $gorevAd
    $e0  = @($g.Actions)[0]
    $guncel = ($e0.Execute -match 'wscript\.exe$') -and ($e0.Arguments -match [regex]::Escape($vbsYol)) -and ($e0.Arguments -match [regex]::Escape($takipPs))
    if (-not $inf.NextRunTime) {
        Log 'NextRunTime BOS -> gorev yeniden kuruluyor'
        GorevKur
    }
    elseif (-not $guncel) {
        # Eski kurulum (konsol flasi) ya da klasor tasinmis: eylemi guncelle
        Log "gorev eylemi guncel degil ($($e0.Execute)) -> yeniden kuruluyor"
        GorevKur
    }
}

$inf = Get-ScheduledTaskInfo -TaskName $gorevAd
Log "kontrol tamam. durum=$((Get-ScheduledTask -TaskName $gorevAd).State) sonraki=$($inf.NextRunTime)"

# Haftalik veri yedegi gorevi: olcum verisi git'te tutulmuyor, tek kopya kalmasin
$yedekAd = 'Calisma Takip Yedek'
$yedekPs = Join-Path $hDir 'yedek-al.ps1'
function YedekGoreviKur {
    $eylem = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\wscript.exe" `
        -Argument "//B //Nologo `"$vbsYol`" `"$yedekPs`"" `
        -WorkingDirectory $klasor
    $tetik = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At '20:00'
    $ayarlar = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 30)
    Register-ScheduledTask -TaskName $yedekAd -Action $eylem -Trigger $tetik -Settings $ayarlar -Force `
        -Description 'Aizen - haftalık veri yedeği' | Out-Null
}
if (Test-Path $yedekPs) {
    $yg = Get-ScheduledTask -TaskName $yedekAd -ErrorAction SilentlyContinue
    if (-not $yg) {
        Log 'yedek gorevi YOK -> kuruluyor'
        YedekGoreviKur
    }
    elseif ($yg.State -ne 'Disabled') {
        $ye = @($yg.Actions)[0]
        if ($ye.Execute -notmatch 'wscript\.exe$' -or $ye.Arguments -notmatch [regex]::Escape($yedekPs)) {
            Log 'yedek gorev eylemi guncel degil -> yeniden kuruluyor'
            YedekGoreviKur
        }
    }
}

# Izleyici servisini baslat (mutex sayesinde ikinci ornek acilmaz)
$izPs = Join-Path $hDir 'izleyici.ps1'
if (Test-Path $izPs) {
    Start-Process -FilePath "$env:SystemRoot\System32\wscript.exe" -ArgumentList "//B //Nologo `"$vbsYol`" `"$izPs`"" -WindowStyle Hidden
    Log 'izleyici servisi baslatildi'
}

# Beklemeden bir tur takip calistir
Start-Process -FilePath "$env:SystemRoot\System32\wscript.exe" -ArgumentList "//B //Nologo `"$vbsYol`" `"$takipPs`"" -WindowStyle Hidden



