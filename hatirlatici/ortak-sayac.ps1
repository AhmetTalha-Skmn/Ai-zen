# Diger cihazlarin bugunku calisma dakikasi.
#
# istemci-gonderici.ps1 merkezden alip 'ortak-sayac.json' dosyasina yazar;
# takip.ps1, api.ps1 ve kontrol.ps1 burayi okur. Merkez yoksa, cihaz bagli
# degilse ya da veri bayatsa 0 doner -- sistem tek basina calismaya devam eder.
# Resmi yerel sayac (durum.json) her zaman yalnizca bu bilgisayarin olcumudur;
# ortak toplam turetilmis degerdir.

function Get-OrtakSayac {
    param(
        [string]$Klasor,
        [int]$TazelikDk = 30
    )
    $bos = [ordered]@{ digerCihazDk = 0; tazeMi = $false; cihazlar = @(); guncellemeUtc = '' }
    if ([string]::IsNullOrWhiteSpace($Klasor)) { return $bos }
    $yol = Join-Path $Klasor 'ortak-sayac.json'
    if (-not (Test-Path -LiteralPath $yol)) { return $bos }

    $veri = $null
    try { $veri = Get-Content -LiteralPath $yol -Raw -Encoding UTF8 | ConvertFrom-Json } catch { return $bos }
    if ($null -eq $veri) { return $bos }
    if ([string]$veri.tarih -ne (Get-Date).ToString('yyyy-MM-dd')) { return $bos }

    # ConvertFrom-Json ISO tarihi DateTime'a cevirebilir; iki hali de desteklenir
    $zaman = [datetime]::MinValue
    $ham = $veri.guncellemeUtc
    if ($ham -is [datetime]) { $zaman = ([datetime]$ham).ToUniversalTime() }
    else {
        $stil = [Globalization.DateTimeStyles]::AdjustToUniversal -bor [Globalization.DateTimeStyles]::AssumeUniversal
        if (-not [datetime]::TryParse([string]$ham, [Globalization.CultureInfo]::InvariantCulture, $stil, [ref]$zaman)) {
            return $bos
        }
    }
    if (([DateTime]::UtcNow - $zaman).TotalMinutes -gt $TazelikDk) { return $bos }

    $dk = 0
    [void][int]::TryParse([string]$veri.digerCihazDk, [ref]$dk)
    if ($dk -lt 0) { $dk = 0 }
    if ($dk -gt 1440) { $dk = 1440 }
    return [ordered]@{
        digerCihazDk = $dk
        tazeMi = $true
        cihazlar = @($veri.cihazlar)
        guncellemeUtc = [string]$ham
    }
}
