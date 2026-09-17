# Istemcinin merkez bildirim ayarlarini goruntuler. Anahtar degerini asla yazdirmaz.
param([string]$HatirlaticiKlasoru, [switch]$Kontrol)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Ortak.ps1')
. (Join-Path $PSScriptRoot 'Senkron-Durum.ps1')
if ([string]::IsNullOrWhiteSpace($HatirlaticiKlasoru)) {
    $HatirlaticiKlasoru = Join-Path (Get-DagitikUygulamaKok $PSScriptRoot) 'hatirlatici'
}
$ayar = Read-DagitikJson (Join-Path $HatirlaticiKlasoru 'merkez.json')
$senkron = Get-CtSenkronDurumu $HatirlaticiKlasoru $ayar
if ($Kontrol) { $senkron | ConvertTo-Json -Depth 5; exit 0 }
Write-Output "Bekleyen karar: $($senkron.bekleyenKarar)"
Write-Output "Son kural alimi: $($senkron.sonKuralAlimiUtc)"
Write-Output "Senkron hatasi: $($senkron.hata)"
if ($null -eq $ayar) {
    Write-Output 'Bu bilgisayar merkez bildirimine kayitli degil.'
    exit 0
}
$outbox = Join-Path $HatirlaticiKlasoru 'merkez-outbox'
$bekleyen = @(Get-ChildItem -LiteralPath $outbox -Filter '*.json' -File -ErrorAction SilentlyContinue).Count
$reddedilen = @(Get-ChildItem -LiteralPath (Join-Path $outbox 'reddedilen') -Filter '*.json' -File -ErrorAction SilentlyContinue).Count

Write-Output '=== Aizen - Merkez Bildirimi ==='
Write-Output "Cihaz: $($ayar.cihazAdi) ($($ayar.cihazId))"
Write-Output "Merkez: $($ayar.sunucuUrl)"
Write-Output "Etkin: $($ayar.aktif)"
Write-Output "Ayrinti: $($ayar.ayrintiDuzeyi)"
Write-Output "Son durum: $($ayar.sonDurum)"
Write-Output "Son basarili senkron: $($ayar.sonBasariliSenkronUtc)"
Write-Output "Kuyrukta gun: $bekleyen | Reddedilen paket: $reddedilen"
Write-Output 'Varsayilan kapsam: uygulama adi, kategori ve sure. Tam URL, arama, tus, pano ve ekran goruntusu gonderilmez.'
