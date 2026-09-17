# Merkez tarafi ozetleme: cihaz karsilastirmasi, trend, uygulama kirilimi,
# sessizlik durumu ve saklama suresi temizligi. Panel, disa aktarim ve testler
# ayni fonksiyonlari kullanir; gorsel kod burada yer almaz.
# Bu dosya yalnizca merkezde calisir, istemci paketine girse de kullanilmaz.

function Get-MerkezZaman {
    # ConvertFrom-Json ISO tarihi yerel Kind ile dondurebilir; her iki hali de UTC'ye cevirir.
    param([object]$Deger)
    if ($null -eq $Deger) { return $null }
    if ($Deger -is [datetime]) { return ([datetime]$Deger).ToUniversalTime() }
    $metin = [string]$Deger
    if ([string]::IsNullOrWhiteSpace($metin)) { return $null }
    [datetime]$sonuc = [datetime]::MinValue
    $stil = [Globalization.DateTimeStyles]::AdjustToUniversal -bor [Globalization.DateTimeStyles]::AssumeUniversal
    if ([datetime]::TryParse($metin, [Globalization.CultureInfo]::InvariantCulture, $stil, [ref]$sonuc)) {
        return $sonuc
    }
    return $null
}

function Get-MerkezKlasorleri {
    param([Parameter(Mandatory = $true)][string]$VeriKlasoru)
    return [ordered]@{
        guncel = Join-Path $VeriKlasoru 'guncel'
        gunluk = Join-Path $VeriKlasoru 'gunluk'
    }
}

function Get-MerkezAnlikKayitlar {
    param([Parameter(Mandatory = $true)][string]$VeriKlasoru)
    $klasor = (Get-MerkezKlasorleri -VeriKlasoru $VeriKlasoru).guncel
    $sonuc = @()
    foreach ($dosya in @(Get-ChildItem -LiteralPath $klasor -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
        $kayit = Read-DagitikJson $dosya.FullName
        if ($null -ne $kayit) { $sonuc += $kayit }
    }
    return $sonuc
}

function Get-MerkezGunKaydi {
    param(
        [Parameter(Mandatory = $true)][string]$VeriKlasoru,
        [Parameter(Mandatory = $true)][string]$CihazId,
        [Parameter(Mandatory = $true)][string]$Tarih
    )
    $klasor = (Get-MerkezKlasorleri -VeriKlasoru $VeriKlasoru).gunluk
    return (Read-DagitikJson (Join-Path (Join-Path $klasor $Tarih) "$CihazId.json"))
}

function Get-MerkezCihazSatirlari {
    # Kayitli her cihaz icin tek satir: hic veri gelmemis olsa bile satir doner.
    param(
        [object]$Ayar,
        [Parameter(Mandatory = $true)][string]$VeriKlasoru,
        [string]$Tarih = '',
        [int]$SessizlikSaati = 6,
        [int]$VarsayilanHedef = 240
    )
    $simdi = [DateTime]::UtcNow
    $anlikListe = @(Get-MerkezAnlikKayitlar -VeriKlasoru $VeriKlasoru)
    $cihazlar = @()
    if ($null -ne $Ayar) { $cihazlar = @(Get-DagitikDeger $Ayar 'cihazlar' @()) }
    $satirlar = @()
    foreach ($cihaz in $cihazlar) {
        $id = [string](Get-DagitikDeger $cihaz 'id' '')
        if ([string]::IsNullOrWhiteSpace($id)) { continue }
        $kayit = $null
        if ([string]::IsNullOrWhiteSpace($Tarih)) {
            $kayit = @($anlikListe | Where-Object { [string](Get-DagitikDeger $_ 'cihazId' '') -eq $id } | Select-Object -First 1)[0]
        }
        else {
            $kayit = Get-MerkezGunKaydi -VeriKlasoru $VeriKlasoru -CihazId $id -Tarih $Tarih
        }
        $hedef = ConvertTo-DagitikDakika (Get-DagitikDeger $cihaz 'hedefDk' 0)
        $ozet = $null
        $calisma = 0; $diger = 0; $bosta = 0; $uygulamaSayisi = 0; $enCok = ''
        $sonGorulme = $null; $izleyici = $false; $gunTarih = $Tarih
        if ($null -ne $kayit) {
            $ozet = Get-DagitikDeger $kayit 'ozet' $null
            $calisma = ConvertTo-DagitikDakika (Get-DagitikDeger $ozet 'calismaDk' 0)
            $diger = ConvertTo-DagitikDakika (Get-DagitikDeger $ozet 'digerDk' 0)
            $bosta = ConvertTo-DagitikDakika (Get-DagitikDeger $ozet 'bostaDk' 0)
            if ($hedef -le 0) { $hedef = ConvertTo-DagitikDakika (Get-DagitikDeger $ozet 'hedefDk' $VarsayilanHedef) }
            $uygulamalar = @(Get-DagitikDeger $kayit 'uygulamalar' @())
            $uygulamaSayisi = $uygulamalar.Count
            if ($uygulamaSayisi -gt 0) { $enCok = [string](Get-DagitikDeger $uygulamalar[0] 'ad' '') }
            $sonGorulme = Get-MerkezZaman (Get-DagitikDeger $kayit 'sonGorulmeUtc' $null)
            $saglik = Get-DagitikDeger $kayit 'health' $null
            $izleyici = [bool](Get-DagitikDeger $saglik 'yerelIzleyiciCalisiyor' $false)
            $gunTarih = [string](Get-DagitikDeger $kayit 'clientTarih' $Tarih)
        }
        if ($hedef -le 0) { $hedef = $VarsayilanHedef }
        $sessizDk = -1
        if ($null -ne $sonGorulme) { $sessizDk = [int][math]::Max(0, [math]::Round(($simdi - $sonGorulme).TotalMinutes)) }
        $durum = 'veri yok'
        if ($null -ne $sonGorulme) {
            if ($sessizDk -gt ($SessizlikSaati * 60)) { $durum = 'sessiz' } else { $durum = 'canli' }
        }
        $yuzde = 0
        if ($hedef -gt 0) { $yuzde = [int][math]::Round(($calisma / $hedef) * 100) }
        $satirlar += [pscustomobject][ordered]@{
            cihazId = $id
            ad = [string](Get-DagitikDeger $cihaz 'ad' $id)
            aktif = [bool](Get-DagitikDeger $cihaz 'aktif' $true)
            kuralYazabilir = [bool](Get-DagitikDeger $cihaz 'kuralYazabilir' $false)
            senkron = Get-DagitikDeger (Get-DagitikDeger $kayit 'health' $null) 'senkron' $null
            tarih = $gunTarih
            calismaDk = $calisma
            digerDk = $diger
            bostaDk = $bosta
            hedefDk = $hedef
            yuzde = $yuzde
            uygulamaSayisi = $uygulamaSayisi
            enCokUygulama = $enCok
            sonGorulmeUtc = $sonGorulme
            sessizDk = $sessizDk
            izleyiciCalisiyor = $izleyici
            durum = $durum
            onayUtc = [string](Get-DagitikDeger $cihaz 'onayUtc' '')
        }
    }
    return $satirlar
}

function Get-MerkezTrend {
    # Son N gunun gunluk arsivinden cihaz serisi. Eksik gunler 0 dakika olarak doner.
    param(
        [Parameter(Mandatory = $true)][string]$VeriKlasoru,
        [Parameter(Mandatory = $true)][string]$CihazId,
        [int]$Gun = 7,
        [datetime]$Bitis = (Get-Date),
        [int]$VarsayilanHedef = 240
    )
    if ($Gun -lt 1) { $Gun = 1 }
    if ($Gun -gt 180) { $Gun = 180 }
    $seri = @()
    for ($i = $Gun - 1; $i -ge 0; $i--) {
        $tarih = $Bitis.Date.AddDays(-$i).ToString('yyyy-MM-dd')
        $kayit = Get-MerkezGunKaydi -VeriKlasoru $VeriKlasoru -CihazId $CihazId -Tarih $tarih
        $calisma = 0; $hedef = $VarsayilanHedef; $veriVar = $false
        if ($null -ne $kayit) {
            $veriVar = $true
            $ozet = Get-DagitikDeger $kayit 'ozet' $null
            $calisma = ConvertTo-DagitikDakika (Get-DagitikDeger $ozet 'calismaDk' 0)
            $hedef = ConvertTo-DagitikDakika (Get-DagitikDeger $ozet 'hedefDk' $VarsayilanHedef)
            if ($hedef -le 0) { $hedef = $VarsayilanHedef }
        }
        $seri += [pscustomobject][ordered]@{
            tarih = $tarih
            calismaDk = $calisma
            hedefDk = $hedef
            yuzde = [int][math]::Round(($calisma / $hedef) * 100)
            veriVar = $veriVar
        }
    }
    return $seri
}

function Get-MerkezUygulamaKirilimi {
    param(
        [Parameter(Mandatory = $true)][string]$VeriKlasoru,
        [Parameter(Mandatory = $true)][string]$CihazId,
        [string]$Tarih = '',
        [int]$EnFazla = 12
    )
    $kayit = $null
    if ([string]::IsNullOrWhiteSpace($Tarih)) {
        $klasor = (Get-MerkezKlasorleri -VeriKlasoru $VeriKlasoru).guncel
        $kayit = Read-DagitikJson (Join-Path $klasor "$CihazId.json")
    }
    else { $kayit = Get-MerkezGunKaydi -VeriKlasoru $VeriKlasoru -CihazId $CihazId -Tarih $Tarih }
    if ($null -eq $kayit) { return @() }
    return @(@(Get-DagitikDeger $kayit 'uygulamalar' @()) | Select-Object -First $EnFazla)
}

function Get-MerkezGunKlasorleri {
    param([Parameter(Mandatory = $true)][string]$VeriKlasoru)
    $klasor = (Get-MerkezKlasorleri -VeriKlasoru $VeriKlasoru).gunluk
    return @(Get-ChildItem -LiteralPath $klasor -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}$' })
}

function Remove-MerkezEskiGunluk {
    # saklamaGun'den eski gunluk arsiv klasorlerini siler. Silinen klasor sayisini doner.
    param(
        [Parameter(Mandatory = $true)][string]$VeriKlasoru,
        [int]$SaklamaGun = 90,
        [datetime]$Bugun = (Get-Date)
    )
    if ($SaklamaGun -lt 1) { return 0 }
    $sinir = $Bugun.Date.AddDays(-$SaklamaGun)
    $silinen = 0
    foreach ($klasor in @(Get-MerkezGunKlasorleri -VeriKlasoru $VeriKlasoru)) {
        [datetime]$gun = [datetime]::MinValue
        if (-not [datetime]::TryParseExact($klasor.Name, 'yyyy-MM-dd',
                [Globalization.CultureInfo]::InvariantCulture,
                [Globalization.DateTimeStyles]::None, [ref]$gun)) { continue }
        if ($gun -lt $sinir) {
            try { Remove-Item -LiteralPath $klasor.FullName -Recurse -Force -ErrorAction Stop; $silinen++ }
            catch { }
        }
    }
    return $silinen
}

function ConvertTo-MerkezCsv {
    # Alanlar: cikacak ozellik adlari. Basliklar verilmezse alan adlari kullanilir.
    param(
        [object[]]$Satirlar,
        [string[]]$Alanlar,
        [string[]]$Basliklar,
        [string]$Ayirac = ';'
    )
    if (-not $Alanlar -or $Alanlar.Count -eq 0) { return '' }
    $bas = $Basliklar
    if (-not $bas -or $bas.Count -ne $Alanlar.Count) { $bas = $Alanlar }
    $satirMetni = New-Object System.Collections.Generic.List[string]
    $satirMetni.Add(($bas -join $Ayirac))
    foreach ($satir in @($Satirlar)) {
        $hucreler = @()
        foreach ($alan in $Alanlar) {
            $deger = Get-DagitikDeger $satir $alan ''
            if ($deger -is [datetime]) { $deger = ([datetime]$deger).ToString('yyyy-MM-dd HH:mm') }
            $metin = ([string]$deger) -replace '[\r\n]+', ' '
            if ($metin.Contains($Ayirac)) { $metin = '"' + $metin.Replace('"', '""') + '"' }
            $hucreler += $metin
        }
        $satirMetni.Add(($hucreler -join $Ayirac))
    }
    return ($satirMetni -join [Environment]::NewLine)
}

function Get-MerkezGunToplami {
    # Bir gunun tum cihazlardaki calisma toplami. HaricCihazId verilirse o cihaz
    # "diger cihazlar" toplamindan dusulur: istemci kendi dakikasini iki kez saymasin.
    param(
        [Parameter(Mandatory = $true)][string]$VeriKlasoru,
        [string]$Tarih = '',
        [string]$HaricCihazId = ''
    )
    if ([string]::IsNullOrWhiteSpace($Tarih)) { $Tarih = (Get-Date).ToString('yyyy-MM-dd') }
    $kayitlar = @()
    if ($Tarih -eq (Get-Date).ToString('yyyy-MM-dd')) {
        $kayitlar = @(Get-MerkezAnlikKayitlar -VeriKlasoru $VeriKlasoru)
    }
    else {
        $gunKlasoru = Join-Path (Get-MerkezKlasorleri -VeriKlasoru $VeriKlasoru).gunluk $Tarih
        foreach ($dosya in @(Get-ChildItem -LiteralPath $gunKlasoru -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
            $kayit = Read-DagitikJson $dosya.FullName
            if ($null -ne $kayit) { $kayitlar += $kayit }
        }
    }

    $toplam = 0
    $buCihaz = 0
    $liste = @()
    $sayi = 0
    foreach ($kayit in $kayitlar) {
        # Bayat anlik kayit (dunden kalma) bugunun toplamina karismasin
        if ([string](Get-DagitikDeger $kayit 'clientTarih' '') -ne $Tarih) { continue }
        $sayi++
        $id = [string](Get-DagitikDeger $kayit 'cihazId' '')
        $dk = ConvertTo-DagitikDakika (Get-DagitikDeger (Get-DagitikDeger $kayit 'ozet' $null) 'calismaDk' 0)
        $toplam += $dk
        if (-not [string]::IsNullOrWhiteSpace($HaricCihazId) -and $id -eq $HaricCihazId) {
            $buCihaz = $dk
        }
        else {
            $liste += [ordered]@{
                cihazId = $id
                ad = ConvertTo-DagitikSinirliMetin (Get-DagitikDeger $kayit 'cihazAdi' $id) 80
                calismaDk = $dk
            }
        }
    }
    return [ordered]@{
        tarih = $Tarih
        toplamDk = $toplam
        buCihazDk = $buCihaz
        digerCihazDk = ($toplam - $buCihaz)
        cihazSayisi = $sayi
        cihazlar = $liste
    }
}

function Get-MerkezPanelToplami {
    param([object]$Ayar, [string]$VeriKlasoru, [string]$Tarih = '')
    $toplam = Get-MerkezGunToplami -VeriKlasoru $VeriKlasoru -Tarih $Tarih
    $hedef = ConvertTo-DagitikDakika (Get-DagitikDeger $Ayar 'ortakHedefDk' 240) 1440
    if ($hedef -le 0) { $hedef = 240 }
    $toplam['hedefDk'] = $hedef
    $toplam['kalanDk'] = [math]::Max(0, $hedef - $toplam.toplamDk)
    $toplam['yuzde'] = [int][math]::Round(100 * $toplam.toplamDk / $hedef)
    return $toplam
}