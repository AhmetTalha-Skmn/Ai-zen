<#
Cihaz kaydini baslatir: her cihaz icin tek kullanimlik eslesme kodu uretir.

Kod kullaniciya soylenir; kullanici kendi bilgisayarinda kurulumu calistirir,
onay ekranini okuyup kabul ederse cihaz merkeze baglanir. Cihaz anahtari bu
makinede uretilmez ve dosyayla tasinmaz: kayit aninda merkez uretir, yalnizca
kodu bilen taraf cozebilecek bicimde sifreli gonderir.

Kullanim:
  .\cihaz-ekle.ps1 -Ad 'Ofis-PC-01'
  .\cihaz-ekle.ps1 -Adlar 'Ofis-1','Ofis-2','Ofis-3' -GecerlilikDakika 120
  .\cihaz-ekle.ps1 -Ad 'Ofis-PC-01' -KoduYenile          # kodu/kaydi yenile
  .\cihaz-ekle.ps1 -Ad 'Ofis-PC-01' -HedefDk 300         # bu cihaz icin gunluk hedef
#>
param(
    [string]$Ad,
    [string[]]$Adlar,
    [string]$CihazKimligi,
    [string]$SunucuUrl,
    [int]$HedefDk = 0,
    [int]$GecerlilikDakika = 60,
    [string]$YapilandirmaYolu,
    [switch]$BasliklaraIzinVer,
    [switch]$AlanAdlarinaIzinVer,
    # Bu cihazda verilen siniflandirma kararlari ortak kural kumesine yazilsin
    # (kendi bilgisayarlarin icin ver; izlenen kullaniciya varsayilan olarak verme)
    [switch]$KuralYazabilir,
    [Alias('AnahtariYenile')][switch]$KoduYenile
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Ortak.ps1')
. (Join-Path $PSScriptRoot 'Merkez-Kural.ps1')
if ([string]::IsNullOrWhiteSpace($YapilandirmaYolu)) {
    $YapilandirmaYolu = Join-Path $PSScriptRoot 'merkez-ayarlari.json'
}
if ($GecerlilikDakika -lt 5 -or $GecerlilikDakika -gt 10080) {
    throw 'GecerlilikDakika 5 ile 10080 (bir hafta) arasinda olmalidir.'
}

function New-VarsayilanMerkezAyari {
    return [ordered]@{
        surum = 1
        port = 8787
        dinlemeOnEki = 'http://+:8787/'
        istemciSunucuUrl = 'http://127.0.0.1:8787'
        saklamaGun = 90
        cihazlar = @()
        olusturulduUtc = [DateTime]::UtcNow.ToString('o')
    }
}

function New-CihazKimligi {
    param([string]$Baslik)
    $kok = ($Baslik -creplace '[^A-Za-z0-9_-]', '-').Trim('-')
    if ($kok.Length -lt 3) { $kok = 'cihaz' }
    if ($kok.Length -gt 50) { $kok = $kok.Substring(0, 50) }
    return "$kok-$([guid]::NewGuid().ToString('N').Substring(0,8))"
}

Invoke-MerkezDosyaKilidi $YapilandirmaYolu {
$merkez = Read-DagitikJson $YapilandirmaYolu
if ($null -eq $merkez) {
    $merkez = New-VarsayilanMerkezAyari
    Write-DagitikJsonAtomik -Nesne $merkez -Yol $YapilandirmaYolu
}

# Ad listesi: -Adlar oncelikli, virgulle ayrilmis tek metin de kabul edilir
$adListesi = @()
if ($Adlar -and $Adlar.Count -gt 0) {
    foreach ($parca in $Adlar) { foreach ($tek in ([string]$parca -split ',')) { $adListesi += $tek } }
}
elseif (-not [string]::IsNullOrWhiteSpace($Ad)) { $adListesi = @($Ad) }
$adListesi = @($adListesi | ForEach-Object { ConvertTo-DagitikSinirliMetin $_ 80 } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($adListesi.Count -eq 0) { throw 'En az bir cihaz adi verin: -Ad ya da -Adlar.' }
if ($adListesi.Count -gt 1 -and -not [string]::IsNullOrWhiteSpace($CihazKimligi)) {
    throw 'CihazKimligi yalnizca tek cihaz eklenirken verilebilir.'
}

if ([string]::IsNullOrWhiteSpace($SunucuUrl)) {
    $SunucuUrl = [string](Get-DagitikDeger $merkez 'istemciSunucuUrl' 'http://127.0.0.1:8787')
}
$SunucuUrl = $SunucuUrl.Trim().TrimEnd('/')
if ($SunucuUrl -notmatch '^https?://[^/\\]+(?::\d+)?$') {
    throw 'SunucuUrl http://sunucu:port biciminde olmalidir; yol ve sorgu eklemeyin.'
}

$kayitlar = @()
if ($null -ne $merkez.cihazlar) { $kayitlar = @($merkez.cihazlar) }
$bitisUtc = [DateTime]::UtcNow.AddMinutes($GecerlilikDakika)
$uretilen = @()

foreach ($cihazAdi in $adListesi) {
    $kimlik = $CihazKimligi
    $mevcut = $null
    if ([string]::IsNullOrWhiteSpace($kimlik)) {
        $mevcut = @($kayitlar | Where-Object { [string]$_.ad -eq $cihazAdi } | Select-Object -First 1)[0]
        if ($null -ne $mevcut) { $kimlik = [string]$mevcut.id }
        else { $kimlik = New-CihazKimligi $cihazAdi }
    }
    else {
        $mevcut = @($kayitlar | Where-Object { [string]$_.id -eq $kimlik } | Select-Object -First 1)[0]
    }
    if (-not (Test-DagitikCihazKimligi $kimlik)) {
        throw 'Cihaz kimligi yalnizca harf, rakam, tire ve alt cizgi icerebilir (3-64 karakter).'
    }
    if ($null -ne $mevcut -and -not $KoduYenile) {
        throw "'$cihazAdi' zaten kayitli ($kimlik). Yeni kod icin -KoduYenile kullanin."
    }

    $kod = New-DagitikEslesmeKodu
    $tuz = Get-DagitikTuz
    $ozet = Get-DagitikKodOzeti -Kod (ConvertTo-DagitikKodNormal $kod) -Tuz $tuz

    if ($null -eq $mevcut) {
        $kayit = [ordered]@{
            id = $kimlik
            ad = $cihazAdi
            aktif = $true
            durum = 'bekliyor'
            anahtarKorunmus = ''
            baslikIzinli = [bool]$BasliklaraIzinVer
            alanAdiIzinli = [bool]$AlanAdlarinaIzinVer
            kuralYazabilir = [bool]$KuralYazabilir
            hedefDk = [int]$HedefDk
            kayitTuzu = $tuz
            kayitOzeti = $ozet
            kayitBitisUtc = $bitisUtc.ToString('o')
            onayUtc = ''
            eklenmeUtc = [DateTime]::UtcNow.ToString('o')
        }
        $kayitlar += [pscustomobject]$kayit
    }
    else {
        # Yenilemede eski anahtar, yeni kayit tamamlanana kadar calismaya devam eder
        Set-DagitikDeger $mevcut 'ad' $cihazAdi
        Set-DagitikDeger $mevcut 'durum' 'bekliyor'
        Set-DagitikDeger $mevcut 'aktif' $true
        Set-DagitikDeger $mevcut 'kayitTuzu' $tuz
        Set-DagitikDeger $mevcut 'kayitOzeti' $ozet
        Set-DagitikDeger $mevcut 'kayitBitisUtc' $bitisUtc.ToString('o')
        if ($BasliklaraIzinVer) { Set-DagitikDeger $mevcut 'baslikIzinli' $true }
        if ($AlanAdlarinaIzinVer) { Set-DagitikDeger $mevcut 'alanAdiIzinli' $true }
        if ($KuralYazabilir) { Set-DagitikDeger $mevcut 'kuralYazabilir' $true }
        if ($HedefDk -gt 0) { Set-DagitikDeger $mevcut 'hedefDk' ([int]$HedefDk) }
    }
    $uretilen += [pscustomobject][ordered]@{ Ad = $cihazAdi; Kimlik = $kimlik; Kod = $kod }
}

$merkez.cihazlar = @($kayitlar)
$merkez.surum = 1
Set-DagitikDeger $merkez 'istemciSunucuUrl' $SunucuUrl
Set-DagitikDeger $merkez 'sonDegisiklikUtc' ([DateTime]::UtcNow.ToString('o'))
Write-DagitikJsonAtomik -Nesne $merkez -Yol $YapilandirmaYolu

Write-Output ''
Write-Output '=== Eslesme kodlari ==='
Write-Output ("{0,-24} {1,-30} {2}" -f 'Cihaz', 'Kimlik', 'Kod')
foreach ($satir in $uretilen) {
    Write-Output ("{0,-24} {1,-30} {2}" -f $satir.Ad, $satir.Kimlik, $satir.Kod)
}
Write-Output ''
Write-Output "Merkez adresi : $SunucuUrl"
Write-Output "Gecerlilik    : $GecerlilikDakika dakika (son: $($bitisUtc.ToLocalTime().ToString('dd.MM.yyyy HH:mm')))"
Write-Output ''
Write-Output 'Kullanicinin yapacagi: paketi acip Kurulum-Kullanici.cmd calistirmak, merkez'
Write-Output 'adresini ve kodu girmek, onay ekranini okuyup kabul etmek.'
Write-Output 'Kod tek kullanimliktir ve sure sonunda gecersiz olur. Yuz yuze ya da telefonla'
Write-Output 'soyleyin; e-posta veya ortak klasorde birakmayin.'

}
