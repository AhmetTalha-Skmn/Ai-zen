# Kural senkronu (istemci tarafi).
#
# "Bir kere karar ver, tum cihazlarda gecerli olsun":
#   - api.ps1 siniflandir bir karar yazdiginda karar kuyruga da eklenir.
#   - istemci-gonderici.ps1 kuyrugu merkeze iter, sonra ortak kumeyi ceker ve
#     yerel kurallar.json ile birlestirir.
#
# Birlestirme: merkezdeki her oge yerelde ayni kategoriye alinir (merkez kazanir,
# cunku her karar merkeze itilir; merkezdeki deger en son karardir). Yerelde olup
# merkezde olmayan ogeler ASLA silinmez. aslaEngelleme hic tasinmaz: makineye
# ozel guvenlik kapisidir.

function Get-KuralKuyrukYolu {
    param([string]$Klasor)
    return (Join-Path $Klasor 'kural-outbox.json')
}

function Add-KuralKuyruk {
    param(
        [Parameter(Mandatory = $true)][string]$Klasor,
        [Parameter(Mandatory = $true)][string]$Oge,
        [string]$Tur = 'surec',
        [Parameter(Mandatory = $true)][string]$Karar
    )
    $yol = Get-KuralKuyrukYolu $Klasor
    $kuyruk = @()
    if (Test-Path -LiteralPath $yol) {
        try {
            $ham = Get-Content -LiteralPath $yol -Raw -Encoding UTF8
            if (-not [string]::IsNullOrWhiteSpace($ham)) {
                $okunan = ConvertFrom-Json $ham
                if ($null -ne $okunan) { $kuyruk = @($okunan) }
            }
        }
        catch { $kuyruk = @() }
    }
    # Ayni oge/tur icin eski karar dussun: son karar gecerlidir
    $kuyruk = @($kuyruk | Where-Object { $_ -and -not ([string]$_.oge -eq $Oge -and [string]$_.tur -eq $Tur) })
    $kuyruk += [pscustomobject]@{ oge = $Oge; tur = $Tur; karar = $Karar; zamanUtc = [DateTime]::UtcNow.ToString('o') }
    if ($kuyruk.Count -gt 200) { $kuyruk = @($kuyruk | Select-Object -Last 200) }
    try {
        ConvertTo-Json -InputObject @($kuyruk) -Depth 4 | Out-File -FilePath $yol -Encoding utf8
        return $true
    }
    catch { return $false }
}

function Get-KuralKuyruk {
    param([Parameter(Mandatory = $true)][string]$Klasor)
    $yol = Get-KuralKuyrukYolu $Klasor
    if (-not (Test-Path -LiteralPath $yol)) { return @() }
    try {
        $ham = Get-Content -LiteralPath $yol -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($ham)) { return @() }
        $okunan = ConvertFrom-Json $ham
        if ($null -eq $okunan) { return @() }
        return @($okunan)
    }
    catch { return @() }
}

function Clear-KuralKuyruk {
    param([Parameter(Mandatory = $true)][string]$Klasor)
    $yol = Get-KuralKuyrukYolu $Klasor
    if (Test-Path -LiteralPath $yol) { Remove-Item -LiteralPath $yol -Force -ErrorAction SilentlyContinue }
}

function Get-KuralImzasi {
    # Listelerin o anki hali. "Once tum listelerden cikar, sonra ekle" deseni
    # zaten dogru yerde olan ogeyi de degisiklik sayiyordu; onces/sonrasi
    # karsilastirilinca islem idempotent olur.
    param([object]$Kurallar)
    $parcalar = @()
    foreach ($grup in 'calisma', 'yasakli') {
        foreach ($tur in 'surec', 'baslik', 'alanadi') {
            $liste = @()
            if ($null -ne $Kurallar.$grup) { $liste = @($Kurallar.$grup.$tur) }
            $parcalar += ($grup + '.' + $tur + '=' + (($liste | Sort-Object) -join '|'))
        }
    }
    $bb = @()
    if ($Kurallar.PSObject.Properties['bilerekBelirsiz']) { $bb = @($Kurallar.bilerekBelirsiz) }
    $parcalar += ('belirsiz=' + (($bb | Sort-Object) -join '|'))
    return ($parcalar -join "`n")
}

function Set-YerelKural {
    # Tek karari yerel kural nesnesine isler (Takip-Siniflandir ile ayni anlam).
    # Donus: gercekten bir sey degistiyse $true.
    param([object]$Kurallar, [string]$Oge, [string]$Tur, [string]$Karar)
    if ([string]::IsNullOrWhiteSpace($Oge)) { return $false }
    if (@('surec', 'baslik', 'alanadi') -notcontains $Tur) { return $false }
    if (@('calisma', 'yasakli', 'belirsiz') -notcontains $Karar) { return $false }

    $once = Get-KuralImzasi $Kurallar
    foreach ($grup in 'calisma', 'yasakli') {
        if ($null -eq $Kurallar.$grup) { continue }
        $Kurallar.$grup.$Tur = @(@($Kurallar.$grup.$Tur) | Where-Object { $_ -and $_ -ne $Oge })
    }
    $bb = @()
    if ($Kurallar.PSObject.Properties['bilerekBelirsiz']) { $bb = @($Kurallar.bilerekBelirsiz) }
    $bbYeni = @($bb | Where-Object { $_ -and $_ -ne $Oge })

    if ($Karar -eq 'belirsiz') { $bbYeni += $Oge }
    else { $Kurallar.$Karar.$Tur = @(@($Kurallar.$Karar.$Tur) + $Oge) }

    if ($Kurallar.PSObject.Properties['bilerekBelirsiz']) { $Kurallar.bilerekBelirsiz = $bbYeni }
    else { $Kurallar | Add-Member -NotePropertyName bilerekBelirsiz -NotePropertyValue $bbYeni }
    return ((Get-KuralImzasi $Kurallar) -ne $once)
}

function Merge-YerelKurallar {
    # Merkezden gelen ortak kumeyi yerel kurallar.json ile birlestirir.
    # Donus: uygulanan degisiklik sayisi (0 ise dosyaya dokunulmaz).
    param(
        [Parameter(Mandatory = $true)][string]$Klasor,
        [Parameter(Mandatory = $true)][object]$Merkez
    )
    $yol = Join-Path $Klasor 'kurallar.json'
    if (-not (Test-Path -LiteralPath $yol)) { throw 'Yerel kural dosyası yok.' }
    $kurallar = $null
    try { $kurallar = Get-Content -LiteralPath $yol -Raw -Encoding UTF8 | ConvertFrom-Json } catch { throw 'Yerel kural dosyası okunamıyor.' }
    if ($null -eq $kurallar) { throw 'Yerel kural dosyası boş.' }

    $degisiklik = 0
    foreach ($grup in 'calisma', 'yasakli') {
        $merkezGrup = $Merkez.$grup
        if ($null -eq $merkezGrup) { continue }
        foreach ($tur in 'surec', 'baslik', 'alanadi') {
            foreach ($oge in @($merkezGrup.$tur)) {
                if ([string]::IsNullOrWhiteSpace([string]$oge)) { continue }
                if (Set-YerelKural -Kurallar $kurallar -Oge ([string]$oge) -Tur $tur -Karar $grup) { $degisiklik++ }
            }
        }
    }
    if ($Merkez.PSObject.Properties['bilerekBelirsiz']) {
        foreach ($oge in @($Merkez.bilerekBelirsiz)) {
            if ([string]::IsNullOrWhiteSpace([string]$oge)) { continue }
            if (Set-YerelKural -Kurallar $kurallar -Oge ([string]$oge) -Tur 'surec' -Karar 'belirsiz') { $degisiklik++ }
        }
    }
    if ($Merkez.PSObject.Properties['silinenKurallar']) {
        foreach ($sil in @($Merkez.silinenKurallar)) {
            if (@('surec','baslik','alanadi') -notcontains [string]$sil.tur) { continue }
            if (@('calisma','yasakli','belirsiz') -notcontains [string]$sil.karar) { continue }
            $once = Get-KuralImzasi $kurallar
            if ($sil.karar -eq 'belirsiz') {
                if ($kurallar.PSObject.Properties['bilerekBelirsiz']) { $kurallar.bilerekBelirsiz = @($kurallar.bilerekBelirsiz | Where-Object { $_ -ne $sil.oge }) }
            } else {
                $g = $kurallar.($sil.karar)
                $g.($sil.tur) = @($g.($sil.tur) | Where-Object { $_ -ne $sil.oge })
            }
            if ((Get-KuralImzasi $kurallar) -ne $once) { $degisiklik++ }
        }
    }
    if ($degisiklik -eq 0) { return 0 }

    $json = ConvertTo-Json -InputObject $kurallar -Depth 6
    $null = ConvertFrom-Json $json   # yazmadan once dogrula
    Copy-Item -LiteralPath $yol -Destination "$yol.bak" -Force -ErrorAction SilentlyContinue
    $gecici = "$yol.yeni"
    [IO.File]::WriteAllText($gecici, $json, (New-Object Text.UTF8Encoding($true)))
    $tamam = $false
    for ($i = 0; $i -lt 5 -and -not $tamam; $i++) {
        try { Move-Item -LiteralPath $gecici -Destination $yol -Force -ErrorAction Stop; $tamam = $true }
        catch { Start-Sleep -Milliseconds 200 }
    }
    if (-not $tamam) { throw 'Yerel kurallar yazılamadı.' }
    return $degisiklik
}
