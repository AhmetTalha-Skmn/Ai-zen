<#
Kayit paketini bu kullanicinin DPAPI korumasiyla saklar ve ayri istemci gonderim
gorevini olusturur. Gorev kullanici oturumunda calisir; SYSTEM hesabi kullanilmaz.
#>
param(
    [switch]$Kur,
    [string]$YapilandirmaYolu,
    [string]$HatirlaticiKlasoru,
    [switch]$HazirAyar
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Ortak.ps1')
if ([string]::IsNullOrWhiteSpace($HatirlaticiKlasoru)) {
    $HatirlaticiKlasoru = Join-Path (Get-DagitikUygulamaKok $PSScriptRoot) 'hatirlatici'
}
if (-not (Test-Path -LiteralPath $HatirlaticiKlasoru)) { throw 'hatirlatici klasoru bulunamadi.' }
$hedefAyarYolu = Join-Path $HatirlaticiKlasoru 'merkez.json'
$gondericiYolu = Join-Path $PSScriptRoot 'istemci-gonderici.ps1'
$gorevAdi = 'Calisma Takip Gonderici'

function Get-GorevTetikleyicileri {
    $gunluk = New-ScheduledTaskTrigger -Daily -At '00:00'
    $gunluk.Repetition = (New-ScheduledTaskTrigger -Once -At '00:00' `
        -RepetitionInterval (New-TimeSpan -Minutes 5) `
        -RepetitionDuration (New-TimeSpan -Hours 23 -Minutes 55)).Repetition
    $oturum = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    $oturum.Delay = 'PT1M'
    $oturum.Repetition = (New-ScheduledTaskTrigger -Once -At '00:00' `
        -RepetitionInterval (New-TimeSpan -Minutes 5) `
        -RepetitionDuration (New-TimeSpan -Hours 23 -Minutes 55)).Repetition
    return @($gunluk, $oturum)
}

if (-not $Kur) {
    Write-Output 'Kullanim: .\istemci-kurulum.ps1 -Kur -YapilandirmaYolu C:\guvenli\merkez.json'
    exit 0
}
if ($HazirAyar) {
    # Kayit istemci-kayit.ps1 tarafindan eslesme koduyla tamamlandi; merkez.json hazir.
    $ayar = Read-DagitikJson $hedefAyarYolu
    if ($null -eq $ayar -or -not (Test-DagitikCihazKimligi ([string](Get-DagitikDeger $ayar 'cihazId' '')))) {
        throw 'merkez.json bulunamadi veya gecersiz; once istemci-kayit.ps1 calistirin.'
    }
    if ([string]::IsNullOrWhiteSpace([string](Get-DagitikDeger $ayar 'anahtarKorunmus' ''))) {
        throw 'merkez.json icinde korunmus anahtar yok; kaydi tekrar calistirin.'
    }
}
else {

if ([string]::IsNullOrWhiteSpace($YapilandirmaYolu) -or -not (Test-Path -LiteralPath $YapilandirmaYolu)) {
    throw 'Yonetici tarafindan uretilen merkez.json kayit paketi secilmelidir.'
}
$gelen = Read-DagitikJson $YapilandirmaYolu
if ($null -eq $gelen -or -not [bool](Get-DagitikDeger $gelen 'aktif' $false)) { throw 'Kayit paketi gecersiz veya devre disi.' }
$cihazId = [string](Get-DagitikDeger $gelen 'cihazId' '')
$anahtar = [string](Get-DagitikDeger $gelen 'anahtar' '')
$sunucuUrl = ([string](Get-DagitikDeger $gelen 'sunucuUrl' '')).Trim().TrimEnd('/')
if (-not (Test-DagitikCihazKimligi $cihazId)) { throw 'Kayit paketindeki cihaz kimligi gecersiz.' }
if ([string]::IsNullOrWhiteSpace($anahtar)) { throw 'Kayit paketinde cihaz anahtari yok.' }
try { [void][Convert]::FromBase64String($anahtar) } catch { throw 'Kayit paketindeki cihaz anahtari gecersiz.' }
if ($sunucuUrl -notmatch '^https?://[^/\\]+(?::\d+)?$') { throw 'Kayit paketindeki sunucu adresi gecersiz.' }

$ayar = [ordered]@{
    surum = 1
    aktif = $true
    cihazId = $cihazId
    cihazAdi = ConvertTo-DagitikSinirliMetin (Get-DagitikDeger $gelen 'cihazAdi' $env:COMPUTERNAME) 80
    sunucuUrl = $sunucuUrl
    anahtarKorunmus = Protect-DagitikAnahtar -Anahtar $anahtar -Amac "istemci:$cihazId"
    gonderimDakikasi = 5
    ayrintiDuzeyi = if ([string](Get-DagitikDeger $gelen 'ayrintiDuzeyi' 'ozet') -eq 'baslikli') { 'baslikli' } else { 'ozet' }
    sira = 0
    sonDurum = 'kuruldu'
    sonKontrolUtc = [DateTime]::UtcNow.ToString('o')
    sonHata = ''
    veriAciklamasi = ConvertTo-DagitikSinirliMetin (Get-DagitikDeger $gelen 'veriAciklamasi' '') 350
}
Write-DagitikJsonAtomik -Nesne $ayar -Yol $hedefAyarYolu

}

$psExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
# powershell.exe dogrudan baslatilirsa 5 dakikada bir konsol flasi olur; yerel takip
# gorevi gibi wscript + gizli.vbs kullanilir. Ust uste binmeyi gondericideki kilit onler.
$vbsYol = Join-Path $HatirlaticiKlasoru 'gizli.vbs'
if (Test-Path -LiteralPath $vbsYol) {
    $eylem = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\wscript.exe" `
        -Argument "//B //Nologo `"$vbsYol`" `"$gondericiYolu`"" `
        -WorkingDirectory (Split-Path -LiteralPath $HatirlaticiKlasoru)
}
else {
    $eylem = New-ScheduledTaskAction -Execute $psExe `
        -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$gondericiYolu`"" `
        -WorkingDirectory (Split-Path -LiteralPath $HatirlaticiKlasoru)
}
$ayarlar = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 10) `
    -RestartCount 2 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName $gorevAdi -Action $eylem -Trigger (Get-GorevTetikleyicileri) `
    -Settings $ayarlar -Force -Description 'Aizen - merkez ozet gonderimi (5 dk)' | Out-Null

# Yerel takip gorevi merkezden bagimsizdir; kurulum onu da ayni kullanici
# oturumunda hazirlar. Basarili olmazsa merkez gondericisi yine gorunur hata
# verir, ancak mevcut yerel kullanici verisi degistirilmez.
$yerelBaslatma = Join-Path $HatirlaticiKlasoru 'baslangic.ps1'
if (Test-Path -LiteralPath $yerelBaslatma) {
    try {
        & $psExe -NoProfile -ExecutionPolicy Bypass -File $yerelBaslatma
    }
    catch { Write-Warning 'Yerel takip baslangici calistirilamadi; Aizen kisayolunu daha sonra acin.' }
}

$bilgiYolu = Join-Path (Split-Path -LiteralPath $HatirlaticiKlasoru) 'VERI-KAPSAMI.txt'
$bilgi = @(
    'AIZEN - MERKEZ BILDIRIMI',
    '',
    "Cihaz: $($ayar.cihazAdi) ($cihazId)",
    "Merkez: $sunucuUrl",
    "Gonderim araligi: $($ayar.gonderimDakikasi) dakika",
    '',
    'Gonderilen varsayilan veri: uygulama adi, kategori ve gunluk sure ozeti.',
    'Gonderilmeyen veri: tam URL, tarayici arama terimi, tus kaydi, pano ve ekran goruntusu.',
    $(if ($ayar.ayrintiDuzeyi -eq 'baslikli') { 'Pencere basligi ozetleri YONETICI TARAFINDAN ACIKCA etkinlestirildi.' } else { 'Pencere basligi ozetleri GONDERILMEZ.' }),
    '',
    "Durum: $HatirlaticiKlasoru\merkez.json",
    "Gonderim gorevi: Gorev Zamanlayici > $gorevAdi",
    'Durdurmak icin gorevi devre disi birakin; yerel takip ayri calismaya devam eder.'
) -join [Environment]::NewLine
[System.IO.File]::WriteAllText($bilgiYolu, $bilgi, (New-Object System.Text.UTF8Encoding($true)))

try { Start-ScheduledTask -TaskName $gorevAdi } catch { }
Write-Output "Istemci kaydi tamamlandi. Durum bilgisi: $bilgiYolu"
Write-Output 'Kayit paketi anahtar icerir; kurulumdan sonra kayit paketini guvenli bicimde silin veya saklayin.'
