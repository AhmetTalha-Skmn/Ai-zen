<#
Ana yonetici bilgisayarda merkez dinleyicisini hazirlar.
Dinleme izni ve Windows Guvenlik Duvari kurali icin bu betik Yonetici olarak calistirilmalidir.

Erisim yollari (uyumluluk/PROTOKOL-V2.md):
  - Yerel ag / VPN: varsayilan. Guvenlik duvari kurali yalnizca Ozel (Private) ag profilinde acilir.
  - Internet (port yonlendirme): -InternetUrl ile. Kural tum profillerde acilir; merkez internetten
    yalnizca sifreli v2 zarflarini kabul eder, eski v1 uclari yerel ag disina kapali kalir.
  - Posta kutusu: modemde port acilamiyorsa. Bu betik degil posta-baglan.ps1 kullanilir.

  .\ana-kurulum.ps1 -Kur
  .\ana-kurulum.ps1 -Kur -InternetUrl http://aizen.ornek-dinamikdns.net:8787
  .\ana-kurulum.ps1 -Kur -InternetKapat
#>
param(
    [switch]$Kur,
    [int]$Port = 8787,
    [string]$IstemciSunucuUrl,
    # Modemde port yonlendirme yapildiysa internetten erisilen adres (dinamik DNS adi onerilir)
    [string]$InternetUrl,
    [switch]$InternetKapat,
    [switch]$Baslat
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Ortak.ps1')
$ayarYolu = Join-Path $PSScriptRoot 'merkez-ayarlari.json'
$sunucuYolu = Join-Path $PSScriptRoot 'merkez-sunucu.ps1'
$panelYolu = Join-Path $PSScriptRoot 'merkez-panel.ps1'
$gorevAdi = 'Calisma Takip Merkezi'

function Test-Yonetici {
    $kimlik = [Security.Principal.WindowsIdentity]::GetCurrent()
    $asli = New-Object Security.Principal.WindowsPrincipal($kimlik)
    return $asli.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-OzelIpv4 {
    param([string]$Adres)
    if ($Adres -match '^10\.') { return $true }
    if ($Adres -match '^192\.168\.') { return $true }
    if ($Adres -match '^172\.(1[6-9]|2[0-9]|3[0-1])\.') { return $true }
    return $false
}

function Get-OzelIpv4 {
    $adaylar = @()
    if (Get-Command Get-NetIPAddress -ErrorAction SilentlyContinue) {
        $adaylar = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -and (Test-OzelIpv4 $_.IPAddress) -and $_.AddressState -ne 'Tentative' } |
            Select-Object -ExpandProperty IPAddress)
    }
    if ($adaylar.Count -eq 0) {
        $adaylar = @([Net.Dns]::GetHostAddresses($env:COMPUTERNAME) |
            Where-Object { $_.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork -and (Test-OzelIpv4 $_.IPAddressToString) } |
            ForEach-Object { $_.IPAddressToString })
    }
    return @($adaylar | Select-Object -First 1)[0]
}

function New-VarsayilanMerkezAyari {
    param([string]$Adres)
    return [ordered]@{
        surum = 1
        port = $Port
        dinlemeOnEki = "http://+:$Port/"
        istemciSunucuUrl = $Adres
        saklamaGun = 90
        cihazlar = @()
        olusturulduUtc = [DateTime]::UtcNow.ToString('o')
    }
}

if ($Port -lt 1024 -or $Port -gt 65535) { throw 'Port 1024 ile 65535 arasinda olmalidir.' }
if ($InternetKapat -and -not [string]::IsNullOrWhiteSpace($InternetUrl)) { throw '-InternetUrl ve -InternetKapat birlikte kullanilamaz.' }
if (-not [string]::IsNullOrWhiteSpace($InternetUrl)) {
    $internetAdresi = ConvertFrom-DagitikAdres $InternetUrl
    if ($null -eq $internetAdresi -or $internetAdresi.tur -ne 'dogrudan') { throw 'InternetUrl http://alanadi:port biciminde olmalidir.' }
    $InternetUrl = $internetAdresi.adres
}
$varsayilanIp = Get-OzelIpv4
if ([string]::IsNullOrWhiteSpace($IstemciSunucuUrl)) {
    if ([string]::IsNullOrWhiteSpace($varsayilanIp)) { $IstemciSunucuUrl = "http://127.0.0.1:$Port" }
    else { $IstemciSunucuUrl = "http://$varsayilanIp`:$Port" }
}
$IstemciSunucuUrl = $IstemciSunucuUrl.Trim().TrimEnd('/')
if ($IstemciSunucuUrl -notmatch '^https?://[^/\\]+(?::\d+)?$') { throw 'IstemciSunucuUrl gecersiz.' }

$merkez = Read-DagitikJson $ayarYolu
if ($null -eq $merkez) { $merkez = New-VarsayilanMerkezAyari $IstemciSunucuUrl }
Set-DagitikDeger $merkez 'surum' 1
Set-DagitikDeger $merkez 'port' $Port
Set-DagitikDeger $merkez 'dinlemeOnEki' "http://+:$Port/"
Set-DagitikDeger $merkez 'istemciSunucuUrl' $IstemciSunucuUrl
if (-not [string]::IsNullOrWhiteSpace($InternetUrl)) { Set-DagitikDeger $merkez 'internetUrl' $InternetUrl }
if ($InternetKapat) { Set-DagitikDeger $merkez 'internetUrl' '' }
if ($null -eq (Get-DagitikDeger $merkez 'cihazlar' $null)) { Set-DagitikDeger $merkez 'cihazlar' @() }
if ($null -eq (Get-DagitikDeger $merkez 'saklamaGun' $null)) { Set-DagitikDeger $merkez 'saklamaGun' 90 }
Set-DagitikDeger $merkez 'sonDegisiklikUtc' ([DateTime]::UtcNow.ToString('o'))
Write-DagitikJsonAtomik -Nesne $merkez -Yol $ayarYolu
$internetAcik = -not [string]::IsNullOrWhiteSpace([string](Get-DagitikDeger $merkez 'internetUrl' ''))

if (-not $Kur) {
    Write-Output "Merkez ayarlari hazir. Istemci adresi: $IstemciSunucuUrl"
    Write-Output 'Dinleyiciyi kurmak icin PowerShelli Yonetici olarak acip su komutu calistirin:'
    Write-Output ".\ana-kurulum.ps1 -Kur -Port $Port"
    exit 0
}

if (-not (Test-Yonetici)) {
    Write-Output 'Dinleme izni ve guvenlik duvari kurali icin Windows yonetici onayi isteniyor.'
    $psExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    # Ayarlar yukarida yazildi; yukseltilmis surec ayni dosyadan okur
    $argumanlar = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Kur', '-Port', "$Port", '-IstemciSunucuUrl', "`"$IstemciSunucuUrl`"")
    try {
        $islem = Start-Process -FilePath $psExe -Verb RunAs -ArgumentList $argumanlar -Wait -PassThru
        exit $islem.ExitCode
    }
    catch {
        Write-Warning 'Yonetici onayi verilmedi. Ayarlar yazildi, ancak merkez sunucusu istemcileri kabul edecek sekilde kurulmadi.'
        exit 2
    }
}

$dinlemeOnEki = "http://+:$Port/"
$kullanici = if ([string]::IsNullOrWhiteSpace($env:USERDOMAIN)) { $env:USERNAME } else { "$env:USERDOMAIN\$env:USERNAME" }
& netsh http add urlacl "url=$dinlemeOnEki" "user=$kullanici" | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Warning "URL ACL eklenemedi. Bu adres daha once baska bir hesap icin ayrilmis olabilir: $dinlemeOnEki"
}

$kuralAdi = "Calisma Takip Merkezi $Port"
# Internet acikken kural tum profillerde gecerlidir (port yonlendirmeyle gelen baglanti Ozel profile
# dusmeyebilir); kapaliyken yalnizca Ozel ag. Merkez v1 uclarini yerel ag disina zaten kapatir.
$profil = $(if ($internetAcik) { 'Any' } else { 'Private' })
try {
    $kural = Get-NetFirewallRule -DisplayName $kuralAdi -ErrorAction SilentlyContinue
    if ($null -eq $kural) {
        New-NetFirewallRule -DisplayName $kuralAdi -Direction Inbound -Action Allow -Protocol TCP `
            -LocalPort $Port -Profile $profil -Description 'Aizen merkezi (v2 sifreli zarf; v1 yalnizca yerel ag)' | Out-Null
    }
    else { $kural | Set-NetFirewallRule -Profile $profil | Out-Null }
}
catch { Write-Warning "Windows Guvenlik Duvari kurali otomatik eklenemedi; TCP $Port portuna elle izin verin." }

$psExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$eylem = New-ScheduledTaskAction -Execute $psExe `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$sunucuYolu`"" `
    -WorkingDirectory (Get-DagitikUygulamaKok $PSScriptRoot)
$oturum = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$ayarlar = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Days 365) `
    -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName $gorevAdi -Action $eylem -Trigger $oturum -Settings $ayarlar -Force `
    -Description 'Aizen - merkez ozet alma sunucusu' | Out-Null

$masaustu = [Environment]::GetFolderPath('Desktop')
if ((Test-Path -LiteralPath $masaustu) -and (Test-Path -LiteralPath $panelYolu)) {
    try {
        $kabuk = New-Object -ComObject WScript.Shell
        # Gorunen ad Aizen; eski adli kisayol kalmasin (kisayol.ps1 ile ayni adlar)
        $eskiKisayol = Join-Path $masaustu 'Calisma Takip Merkezi.lnk'
        if (Test-Path -LiteralPath $eskiKisayol) { Remove-Item -LiteralPath $eskiKisayol -Force -ErrorAction SilentlyContinue }
        $kisayol = $kabuk.CreateShortcut((Join-Path $masaustu 'Aizen Merkez.lnk'))
        $kisayol.TargetPath = $psExe
        $kisayol.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$panelYolu`""
        $kisayol.WorkingDirectory = (Get-DagitikUygulamaKok $PSScriptRoot)
        $kisayol.IconLocation = "$env:SystemRoot\System32\shell32.dll,44"
        $kisayol.Save()
    }
    catch { }
}

try { Start-ScheduledTask -TaskName $gorevAdi } catch { Write-Warning 'Merkez gorevi baslatilamadi; Gorev Zamanlayici kaydini kontrol edin.' }
Write-Output "Merkez kuruldu. Ayni agdaki istemciler icin adres: $IstemciSunucuUrl"
if ($internetAcik) {
    Write-Output "Internet adresi: $([string](Get-DagitikDeger $merkez 'internetUrl' ''))"
    Write-Output "Modemde TCP $Port portunu bu bilgisayarin yerel adresine ($varsayilanIp) yonlendirin."
    Write-Output 'Internetten yalnizca sifreli v2 zarflari kabul edilir; kayit kodu ve veriler aga duz cikmaz.'
}
else {
    Write-Output 'Farkli agdaki cihazlar icin: -InternetUrl ile port yonlendirme ya da posta-baglan.ps1 ile posta kutusu.'
}
Write-Output 'Yeni bir istemci eklemek icin cihaz-ekle.ps1 kullanin.'
