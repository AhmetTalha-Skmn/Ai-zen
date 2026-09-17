<#
Merkezi bir posta kutusu sunucusuna baglar (farkli aglardaki cihazlar icin).

Posta kutusu sunucusu kiralik bir Linux sunucuda calisir (posta-sunucusu/README.md).
Bu betik merkez bilgisayarinda bir kez calistirilir:
  - rastgele bir kutu kimligi ve merkez jetonu uretir,
  - sunucunun yonetim jetonuyla kutuyu olusturur (sunucuya yalnizca jetonun ozeti gider),
  - merkez jetonunu bu Windows kullanicisina bagli DPAPI ile merkez-ayarlari.json'a yazar.
Merkez sunucusu calisiyorsa yeniden baslatmaya gerek yoktur; ayari bir dakika icinde okur.

Kullanim:
  .\posta-baglan.ps1 -PostaUrl https://posta.firma.com
  .\posta-baglan.ps1 -Durum
  .\posta-baglan.ps1 -Kapat          # posta kutusunu kullanmayi birakir (kutu sunucuda kalir)
#>
param(
    [string]$PostaUrl,
    [string]$YonetimJetonu,
    [string]$YapilandirmaYolu,
    [ValidateRange(2, 3600)][int]$AralikSn = 60,
    [switch]$Durum,
    [switch]$Kapat
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Ortak.ps1')
. (Join-Path $PSScriptRoot 'Merkez-Ozet.ps1')
. (Join-Path $PSScriptRoot 'Merkez-Kural.ps1')
. (Join-Path $PSScriptRoot 'Merkez-Posta.ps1')
if ([string]::IsNullOrWhiteSpace($YapilandirmaYolu)) {
    $YapilandirmaYolu = Join-Path $PSScriptRoot 'merkez-ayarlari.json'
}

if ($Durum) {
    $ayar = Read-DagitikJson $YapilandirmaYolu
    $adres = Get-MerkezPostaAdresi $ayar
    if (-not $adres) { Write-Output 'Posta kutusu ayarli degil.'; exit 0 }
    Write-Output "Posta kutusu adresi (istemciler icin): $adres"
    $durumYolu = Join-Path (Join-Path $PSScriptRoot 'veri') 'posta-durum.json'
    $d = Read-DagitikJson $durumYolu
    if ($null -ne $d) {
        Write-Output "Son basarili baglanti: $([string](Get-DagitikDeger $d 'sonBasariliUtc' '-'))"
        $hata = [string](Get-DagitikDeger $d 'hata' '')
        if ($hata) { Write-Output "Son hata: $hata" }
    }
    exit 0
}

if ($Kapat) {
    Invoke-MerkezDosyaKilidi $YapilandirmaYolu {
        $ayar = Read-DagitikJson $YapilandirmaYolu
        if ($null -eq $ayar) { throw 'merkez-ayarlari.json bulunamadi.' }
        $posta = Get-DagitikDeger $ayar 'posta' $null
        if ($null -ne $posta) {
            Set-DagitikDeger $posta 'aktif' $false
            Set-DagitikDeger $posta 'jetonKorunmus' ''
            Write-DagitikJsonAtomik -Nesne $ayar -Yol $YapilandirmaYolu
        }
    }
    Write-Output 'Posta kutusu kullanimi kapatildi. Farkli agdaki cihazlar merkeze artik ulasamaz.'
    exit 0
}

if ([string]::IsNullOrWhiteSpace($PostaUrl)) { $PostaUrl = Read-Host 'Posta kutusu sunucusunun adresi (ornek: https://posta.firma.com)' }
$adres = ConvertFrom-DagitikAdres $PostaUrl
if ($null -eq $adres -or $adres.tur -ne 'dogrudan') { throw 'Posta kutusu adresi https://sunucu biciminde olmalidir (yol eklemeyin).' }
if (-not (Test-DagitikGuvenliPostaKoku $adres.kok)) { throw 'Posta kutusu adresi https:// ile baslamalidir; jetonlar sifresiz baglantidan gonderilmez.' }
$kok = $adres.kok

if ([string]::IsNullOrWhiteSpace($YonetimJetonu)) {
    $gizli = Read-Host 'Posta kutusu sunucusunun yonetim jetonu' -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($gizli)
    try { $YonetimJetonu = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}
$YonetimJetonu = ([string]$YonetimJetonu).Trim()
if ($YonetimJetonu -cnotmatch '^[A-Za-z0-9_-]{32,128}$') { throw 'Yonetim jetonu bicimi gecersiz.' }

$ayar = Read-DagitikJson $YapilandirmaYolu
if ($null -eq $ayar) { throw 'merkez-ayarlari.json bulunamadi; once ana-kurulum.ps1 calistirin.' }

# Ayni sunucuya yeniden baglanirken kutu kimligi korunur: istemcilerdeki adres degismez
$eski = Get-DagitikDeger $ayar 'posta' $null
$kutu = [string](Get-DagitikDeger $eski 'kutu' '')
if ([string](Get-DagitikDeger $eski 'url' '') -cne $kok -or $kutu -cnotmatch '^[0-9a-f]{16,64}$') {
    $kutu = ConvertTo-DagitikHex ([Convert]::FromBase64String((New-DagitikAnahtar))[0..15])
}
$merkezJetonu = ConvertTo-DagitikHex ([Convert]::FromBase64String((New-DagitikAnahtar)))

try {
    $cevap = Invoke-MerkezPostaIstegi -Kok $kok -Basliklar @{ 'X-Aizen-Yonetim' = $YonetimJetonu } -Yontem POST -Yol '/r1/kutu' `
        -Govde ([ordered]@{ kutu = $kutu; merkezJetonOzeti = (Get-DagitikMetinOzeti $merkezJetonu) })
}
catch {
    $kod = 0
    try { $kod = [int]$_.Exception.Response.StatusCode } catch { }
    if ($kod -eq 401) { throw 'Posta kutusu yonetim jetonunu kabul etmedi.' }
    if ($kod -gt 0) { throw "Posta kutusu HTTP $kod dondurdu." }
    throw "Posta kutusuna ulasilamadi: $($_.Exception.Message)"
}
if ($null -eq $cevap -or -not [bool](Get-DagitikDeger $cevap 'ok' $false)) { throw 'Posta kutusu kutuyu olusturamadi.' }

Invoke-MerkezDosyaKilidi $YapilandirmaYolu {
    $guncel = Read-DagitikJson $YapilandirmaYolu
    Set-DagitikDeger $guncel 'posta' ([ordered]@{
        aktif = $true
        url = $kok
        kutu = $kutu
        jetonKorunmus = (Protect-DagitikAnahtar -Anahtar $merkezJetonu -Amac 'merkez-posta')
        aralikSn = $AralikSn
        baglandiUtc = [DateTime]::UtcNow.ToString('o')
    })
    Set-DagitikDeger $guncel 'sonDegisiklikUtc' ([DateTime]::UtcNow.ToString('o'))
    Write-DagitikJsonAtomik -Nesne $guncel -Yol $YapilandirmaYolu
}

Write-Output 'Posta kutusu baglandi.'
Write-Output "Farkli agdaki cihazlar icin adres: $kok/k/$kutu"
Write-Output 'Yeni eslesme kodlari (cihaz-ekle.ps1) bu adresi de gosterir. Kayitli cihazlar adresi merkeze'
Write-Output 'bir sonraki dogrudan baglantilarinda sifreli yanitla ogrenir. Merkez sunucusu calistigi surece kutuyu yoklar.'
