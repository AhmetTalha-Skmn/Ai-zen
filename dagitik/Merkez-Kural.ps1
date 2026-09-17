# Ortak kural kumesi: "bir kere karar ver, tum cihazlarda gecerli olsun".
#
# Merkez yalnizca calisma/yasakli listeleriyle bilerekBelirsiz'i tasir.
# aslaEngelleme BILEREK tasinmaz: o liste makineye ozel guvenlik kapisidir
# (bir cihazda kritik olan uygulama digerinde olmayabilir).
#
# Cakisma kurali: merkez kazanir. Kullanici karari her verildiginde merkeze
# itilir, yani merkezdeki deger "en son karar"dir. Yerelde olup merkezde
# olmayan ogeler asla silinmez.

function New-VarsayilanMerkezKurallari {
    return [ordered]@{
        surum = 1
        sonDegisiklikUtc = [DateTime]::UtcNow.ToString('o')
        calisma = [ordered]@{ surec = @(); baslik = @(); alanadi = @() }
        yasakli = [ordered]@{ surec = @(); baslik = @(); alanadi = @() }
        bilerekBelirsiz = @()
    }
}

function Get-MerkezKurallari {
    param([Parameter(Mandatory = $true)][string]$Yol)
    $kurallar = Read-DagitikJson $Yol
    if ($null -eq $kurallar) { return (New-VarsayilanMerkezKurallari) }
    # Eksik alanlari tamamla (elle duzenlenmis dosya panigi olmasin)
    foreach ($grup in 'calisma', 'yasakli') {
        if ($null -eq (Get-DagitikDeger $kurallar $grup $null)) {
            Set-DagitikDeger $kurallar $grup ([ordered]@{ surec = @(); baslik = @(); alanadi = @() })
        }
        else {
            $g = Get-DagitikDeger $kurallar $grup $null
            foreach ($tur in 'surec', 'baslik', 'alanadi') {
                if ($null -eq (Get-DagitikDeger $g $tur $null)) { Set-DagitikDeger $g $tur @() }
            }
        }
    }
    if ($null -eq (Get-DagitikDeger $kurallar 'bilerekBelirsiz' $null)) {
        Set-DagitikDeger $kurallar 'bilerekBelirsiz' @()
    }
    return $kurallar
}

function Set-MerkezKural {
    # Tek bir karari ortak kumeye isler. Takip-Siniflandir ile ayni anlam:
    # once tum listelerden cikar, sonra hedefe ekle.
    param(
        [Parameter(Mandatory = $true)][object]$Kurallar,
        [Parameter(Mandatory = $true)][string]$Oge,
        [string]$Tur = 'surec',
        [Parameter(Mandatory = $true)][string]$Karar
    )
    $temizOge = ConvertTo-DagitikSinirliMetin $Oge 160
    if ([string]::IsNullOrWhiteSpace($temizOge)) { throw 'oge bos olamaz' }
    if (@('surec', 'baslik', 'alanadi') -notcontains $Tur) { throw 'tur surec, baslik veya alanadi olmali' }
    if (@('calisma', 'yasakli', 'belirsiz') -notcontains $Karar) { throw 'karar calisma, yasakli veya belirsiz olmali' }

    # Ayni karar tekrar gelirse zaman damgasi bosuna degismesin: istemciler
    # her degisiklikte kumeyi yeniden cekiyor.
    $onceImza = Get-MerkezKuralImzasi $Kurallar
    $silinen = @(@(Get-DagitikDeger $Kurallar 'silinenKurallar' @()) | Where-Object { -not ($_.oge -eq $temizOge -and ($_.tur -eq $Tur -or $_.karar -eq 'belirsiz')) })
    Set-DagitikDeger $Kurallar 'silinenKurallar' $silinen
    foreach ($grup in 'calisma', 'yasakli') {
        $g = Get-DagitikDeger $Kurallar $grup $null
        $liste = @(@(Get-DagitikDeger $g $Tur @()) | Where-Object { $_ -and $_ -ne $temizOge })
        Set-DagitikDeger $g $Tur $liste
    }
    $bb = @(@(Get-DagitikDeger $Kurallar 'bilerekBelirsiz' @()) | Where-Object { $_ -and $_ -ne $temizOge })
    if ($Karar -eq 'belirsiz') { $bb += $temizOge }
    else {
        $g = Get-DagitikDeger $Kurallar $Karar $null
        $liste = @(Get-DagitikDeger $g $Tur @())
        $liste += $temizOge
        Set-DagitikDeger $g $Tur $liste
    }
    Set-DagitikDeger $Kurallar 'bilerekBelirsiz' $bb
    if ((Get-MerkezKuralImzasi $Kurallar) -ne $onceImza) {
        Set-DagitikDeger $Kurallar 'sonDegisiklikUtc' ([DateTime]::UtcNow.ToString('o'))
    }
    return $Kurallar
}

function Get-MerkezKuralImzasi {
    # Listelerin o anki hali; "once cikar sonra ekle" deseni degisiklik
    # uretmis gibi gorunmesin diye onces/sonrasi karsilastirilir.
    param([Parameter(Mandatory = $true)][object]$Kurallar)
    $parcalar = @()
    foreach ($grup in 'calisma', 'yasakli') {
        $g = Get-DagitikDeger $Kurallar $grup $null
        foreach ($tur in 'surec', 'baslik', 'alanadi') {
            $liste = @(Get-DagitikDeger $g $tur @())
            $parcalar += ($grup + '.' + $tur + '=' + (($liste | Sort-Object) -join '|'))
        }
    }
    $parcalar += ('belirsiz=' + ((@(Get-DagitikDeger $Kurallar 'bilerekBelirsiz' @()) | Sort-Object) -join '|'))
    return ($parcalar -join "`n")
}

function Merge-MerkezKurallari {
    # Bir istemci kurallar.json'unu ortak kumeye katar (ilk doldurma icin).
    # Yalnizca ekler; merkezdeki hicbir karar silinmez.
    param(
        [Parameter(Mandatory = $true)][object]$Kurallar,
        [Parameter(Mandatory = $true)][object]$Kaynak
    )
    $eklenen = 0
    foreach ($grup in 'calisma', 'yasakli') {
        $kaynakGrup = Get-DagitikDeger $Kaynak $grup $null
        if ($null -eq $kaynakGrup) { continue }
        foreach ($tur in 'surec', 'baslik', 'alanadi') {
            foreach ($oge in @(Get-DagitikDeger $kaynakGrup $tur @())) {
                if ([string]::IsNullOrWhiteSpace([string]$oge)) { continue }
                $mevcut = @(Get-DagitikDeger (Get-DagitikDeger $Kurallar $grup $null) $tur @())
                if ($mevcut -contains [string]$oge) { continue }
                [void](Set-MerkezKural -Kurallar $Kurallar -Oge ([string]$oge) -Tur $tur -Karar $grup)
                $eklenen++
            }
        }
    }
    foreach ($oge in @(Get-DagitikDeger $Kaynak 'bilerekBelirsiz' @())) {
        if ([string]::IsNullOrWhiteSpace([string]$oge)) { continue }
        if (@(Get-DagitikDeger $Kurallar 'bilerekBelirsiz' @()) -contains [string]$oge) { continue }
        [void](Set-MerkezKural -Kurallar $Kurallar -Oge ([string]$oge) -Tur 'surec' -Karar 'belirsiz')
        $eklenen++
    }
    return $eklenen
}

function Get-MerkezKuralOzeti {
    param([Parameter(Mandatory = $true)][object]$Kurallar)
    $sayi = 0
    foreach ($grup in 'calisma', 'yasakli') {
        $g = Get-DagitikDeger $Kurallar $grup $null
        foreach ($tur in 'surec', 'baslik', 'alanadi') { $sayi += @(Get-DagitikDeger $g $tur @()).Count }
    }
    $sayi += @(Get-DagitikDeger $Kurallar 'bilerekBelirsiz' @()).Count
    return $sayi
}

function Invoke-MerkezDosyaKilidi {
    param([string]$Yol, [scriptblock]$Islem)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $iz = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes([IO.Path]::GetFullPath($Yol).ToUpperInvariant()))).Replace('-', '') }
    finally { $sha.Dispose() }
    $mutex = New-Object Threading.Mutex($false, "Local\CtMerkez_$iz")
    $alindi = $false
    try {
        try { $alindi = $mutex.WaitOne(10000) } catch [Threading.AbandonedMutexException] { $alindi = $true }
        if (-not $alindi) { throw 'Dosya başka bir işlem tarafından güncelleniyor; yeniden deneyin.' }
        & $Islem
    }
    finally { if ($alindi) { $mutex.ReleaseMutex() }; $mutex.Dispose() }
}

function Get-MerkezKuralSatirlari {
    param([object]$Kurallar)
    foreach ($grup in 'calisma','yasakli') {
        foreach ($tur in 'surec','baslik','alanadi') {
            foreach ($oge in @(Get-DagitikDeger (Get-DagitikDeger $Kurallar $grup $null) $tur @())) {
                [pscustomobject]@{ oge=[string]$oge; tur=$tur; karar=$grup }
            }
        }
    }
    foreach ($oge in @(Get-DagitikDeger $Kurallar 'bilerekBelirsiz' @())) {
        [pscustomobject]@{ oge=[string]$oge; tur='surec'; karar='belirsiz' }
    }
}

function Remove-MerkezKural {
    param([object]$Kurallar, [string]$Oge, [ValidateSet('surec','baslik','alanadi')][string]$Tur, [ValidateSet('calisma','yasakli','belirsiz')][string]$Karar)
    $var = @(Get-MerkezKuralSatirlari $Kurallar | Where-Object { $_.oge -eq $Oge -and $_.tur -eq $Tur -and $_.karar -eq $Karar })
    if ($var.Count -eq 0) { return }
    if ($Karar -eq 'belirsiz') {
        Set-DagitikDeger $Kurallar 'bilerekBelirsiz' @(@(Get-DagitikDeger $Kurallar 'bilerekBelirsiz' @()) | Where-Object { $_ -ne $Oge })
    } else {
        $g = Get-DagitikDeger $Kurallar $Karar $null
        Set-DagitikDeger $g $Tur @(@(Get-DagitikDeger $g $Tur @()) | Where-Object { $_ -ne $Oge })
    }
    $silinen = @(@(Get-DagitikDeger $Kurallar 'silinenKurallar' @()) | Where-Object { -not ($_.oge -eq $Oge -and $_.tur -eq $Tur -and $_.karar -eq $Karar) })
    $silinen += [pscustomobject]@{ oge=$Oge; tur=$Tur; karar=$Karar }
    Set-DagitikDeger $Kurallar 'silinenKurallar' $silinen
    Set-DagitikDeger $Kurallar 'sonDegisiklikUtc' ([DateTime]::UtcNow.ToString('o'))
}

function Save-MerkezKuralKarari {
    param([string]$Yol, [string]$Oge, [string]$Tur, [string]$Karar, [switch]$Sil)
    Invoke-MerkezDosyaKilidi $Yol {
        if ((Test-Path -LiteralPath $Yol) -and $null -eq (Read-DagitikJson $Yol)) { throw 'Kural dosyası okunamıyor; üzerine yazılmadı.' }
        $k = Get-MerkezKurallari $Yol
        if ($Sil) { Remove-MerkezKural $k $Oge $Tur $Karar }
        else { [void](Set-MerkezKural $k $Oge $Tur $Karar) }
        Write-DagitikJsonAtomik -Nesne $k -Yol $Yol -Derinlik 8
    }
}

function Set-MerkezCihazAyari {
    param([string]$Yol, [string]$CihazId, [bool]$Aktif, [bool]$KuralYazabilir, [ValidateRange(0,1440)][int]$HedefDk)
    Invoke-MerkezDosyaKilidi $Yol {
        $ayar = Read-DagitikJson $Yol
        if ($null -eq $ayar) { throw 'Merkez ayarları okunamıyor.' }
        $cihaz = @(@(Get-DagitikDeger $ayar 'cihazlar' @()) | Where-Object { $_.id -eq $CihazId })
        if ($cihaz.Count -ne 1) { throw 'Cihaz bulunamadı veya kimliği tekil değil.' }
        Set-DagitikDeger $cihaz[0] 'aktif' $Aktif
        Set-DagitikDeger $cihaz[0] 'kuralYazabilir' $KuralYazabilir
        Set-DagitikDeger $cihaz[0] 'hedefDk' $HedefDk
        Set-DagitikDeger $ayar 'sonDegisiklikUtc' ([DateTime]::UtcNow.ToString('o'))
        Write-DagitikJsonAtomik -Nesne $ayar -Yol $Yol -Derinlik 8
    }
}