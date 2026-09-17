# Merkezin posta kutusu sunucusuyla konusmasi. merkez-sunucu.ps1 ve posta-baglan.ps1 kullanir.
# Posta kutusu yalnizca sifreli zarflari tasir: merkez jetonu ve cihaz jetonlarinin
# SHA-256 ozetlerini bilir, zarf icerigini ve cihaz anahtarlarini bilmez.
# Ortak.ps1 ve Merkez-Ozet.ps1 (Get-MerkezZaman) once yuklenmis olmalidir.

$script:MerkezPostaJetonOnbellegi = @{}

function Get-MerkezPostaAyari {
    param([object]$Ayar)
    $posta = Get-DagitikDeger $Ayar 'posta' $null
    if ($null -eq $posta -or -not [bool](Get-DagitikDeger $posta 'aktif' $false)) { return $null }
    $adres = ConvertFrom-DagitikAdres ([string](Get-DagitikDeger $posta 'url' ''))
    if ($null -eq $adres -or $adres.tur -ne 'dogrudan' -or -not (Test-DagitikGuvenliPostaKoku $adres.kok)) { return $null }
    if ([string](Get-DagitikDeger $posta 'kutu' '') -cnotmatch '^[0-9a-f]{16,64}$') { return $null }
    if ([string]::IsNullOrWhiteSpace([string](Get-DagitikDeger $posta 'jetonKorunmus' ''))) { return $null }
    return $posta
}

function Get-MerkezPostaAdresi {
    # Istemcinin girecegi posta kutusu adresi: https://sunucu/k/<kutu>
    param([object]$Ayar)
    $posta = Get-MerkezPostaAyari $Ayar
    if ($null -eq $posta) { return '' }
    return ('{0}/k/{1}' -f ([string]$posta.url).TrimEnd('/'), [string]$posta.kutu)
}

function Invoke-MerkezPostaIstegi {
    param(
        [Parameter(Mandatory = $true)][string]$Kok,
        [Parameter(Mandatory = $true)][hashtable]$Basliklar,
        [ValidateSet('GET', 'POST')][string]$Yontem = 'GET',
        [Parameter(Mandatory = $true)][string]$Yol,
        [object]$Govde,
        [int]$ZamanAsimiSn = 15
    )
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $parametreler = @{
        Uri = ($Kok.TrimEnd('/') + $Yol)
        Method = $Yontem
        Headers = $Basliklar
        UseBasicParsing = $true
        TimeoutSec = $ZamanAsimiSn
    }
    if ($null -ne $Govde) {
        $metin = $(if ($Govde -is [string]) { $Govde } else { $Govde | ConvertTo-Json -Depth 8 -Compress })
        $parametreler.Body = [System.Text.Encoding]::UTF8.GetBytes($metin)
        $parametreler.ContentType = 'application/json; charset=utf-8'
    }
    $yanit = Invoke-WebRequest @parametreler
    $icerik = $yanit.Content
    if ($icerik -is [byte[]]) { $icerik = [System.Text.Encoding]::UTF8.GetString($icerik) }
    if ([string]::IsNullOrWhiteSpace([string]$icerik)) { return $null }
    return ($icerik | ConvertFrom-Json)
}

function Get-MerkezPostaCihazListesi {
    # Posta kutusuna bildirilecek kimlikler: kayitli cihazlar ve suresi dolmamis v2 kayit kanallari.
    param([object]$Ayar)
    $simdi = [DateTime]::UtcNow
    $liste = New-Object System.Collections.ArrayList
    foreach ($cihaz in @(Get-DagitikDeger $Ayar 'cihazlar' @())) {
        $id = [string](Get-DagitikDeger $cihaz 'id' '')
        $korunmus = [string](Get-DagitikDeger $cihaz 'anahtarKorunmus' '')
        if ((Test-DagitikCihazKimligi $id) -and [bool](Get-DagitikDeger $cihaz 'aktif' $false) -and $korunmus) {
            $onbellekAnahtari = "$id|$korunmus"
            $ozet = $script:MerkezPostaJetonOnbellegi[$onbellekAnahtari]
            if ($null -eq $ozet) {
                try {
                    $anahtar = Unprotect-DagitikAnahtar -KorunmusAnahtar $korunmus -Amac "merkez:$id"
                    $ozet = Get-DagitikMetinOzeti (Get-DagitikZarfAnahtarlari $anahtar).postaJetonu
                    $script:MerkezPostaJetonOnbellegi[$onbellekAnahtari] = $ozet
                }
                catch { $ozet = $null }
            }
            if ($ozet) { [void]$liste.Add([ordered]@{ cihaz = $id; jetonOzeti = $ozet; bitis = 0 }) }
        }
        $kanal = [string](Get-DagitikDeger $cihaz 'kayitKanaliV2' '')
        $jetonOzeti = [string](Get-DagitikDeger $cihaz 'postaKayitJetonOzeti' '')
        if ((Test-DagitikKayitKanali $kanal) -and $jetonOzeti -cmatch '^[0-9a-f]{64}$') {
            $bekliyor = [string](Get-DagitikDeger $cihaz 'durum' '') -eq 'bekliyor' -and
                -not [string]::IsNullOrWhiteSpace([string](Get-DagitikDeger $cihaz 'kayitAnaAnahtarV2Korunmus' ''))
            $bitis = Get-MerkezZaman (Get-DagitikDeger $cihaz $(if ($bekliyor) { 'kayitBitisUtc' } else { 'postaKayitBitisUtc' }) $null)
            if ($null -ne $bitis -and $bitis -gt $simdi) {
                $unix = [DateTimeOffset]::new([DateTime]::SpecifyKind($bitis, [DateTimeKind]::Utc)).ToUnixTimeSeconds()
                [void]$liste.Add([ordered]@{ cihaz = $kanal; jetonOzeti = $jetonOzeti; bitis = $unix })
            }
        }
    }
    return ,@($liste.ToArray())
}

function Test-MerkezBekleyenV2Kayit {
    param([object]$Ayar)
    $simdi = [DateTime]::UtcNow
    foreach ($cihaz in @(Get-DagitikDeger $Ayar 'cihazlar' @())) {
        if ([string](Get-DagitikDeger $cihaz 'durum' '') -ne 'bekliyor') { continue }
        if (-not (Test-DagitikKayitKanali ([string](Get-DagitikDeger $cihaz 'kayitKanaliV2' '')))) { continue }
        $bitis = Get-MerkezZaman (Get-DagitikDeger $cihaz 'kayitBitisUtc' $null)
        if ($null -eq $bitis -or $bitis -gt $simdi) { return $true }
    }
    return $false
}

function Get-MerkezPostaYanitAnahtari {
    # Posta kutusunda ayni anahtarli eski yanit yenisiyle degisir; cihaz yalnizca en guncelini alir.
    param([string]$Tur)
    switch ($Tur) {
        'kurallar' { return 'kurallar' }
        'toplam' { return 'toplam' }
        'ozet' { return 'ozet' }
        default { return '' }
    }
}
