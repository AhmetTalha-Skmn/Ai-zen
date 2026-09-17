<#
Merkez sunucusu: kayitli cihazlardan gunluk ozet, kural karari ve ortak toplam isteklerini
alir. Mevcut yerel API/MCP yuzeylerini agda acmaz ve istemciye komut gondermez.

  v1  /v1/*      imzali duz JSON. Yalnizca yerel ag ve VPN adreslerinden kabul edilir
                 (eski istemciler; v1 kaydinda eslesme kodu agda duz gider).
  v2  /v2/zarf   sifreli zarf (uyumluluk/PROTOKOL-V2.md). Yerel agdan, port yonlendirmeyle
                 internetten ya da posta kutusu sunucusu uzerinden gelir.

Posta kutusu ayarliysa (posta-baglan.ps1) sunucu calistigi surece kutudaki zarflari
duzenli araliklarla alir, isler ve yanitlari kutuya birakir.
#>
param(
    [int]$Port = 0,
    [string]$DinlemeOnEki,
    [string]$YapilandirmaYolu,
    [string]$VeriKlasoru,
    [switch]$BirKere,
    [int]$IstekSayisi = 0,
    # Testler icin: bu kadar saniye sonra kapanir (0 = surekli)
    [int]$CalismaSuresiSn = 0
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Ortak.ps1')
. (Join-Path $PSScriptRoot 'Merkez-Ozet.ps1')
. (Join-Path $PSScriptRoot 'Merkez-Kural.ps1')
. (Join-Path $PSScriptRoot 'Merkez-Posta.ps1')

if ([string]::IsNullOrWhiteSpace($YapilandirmaYolu)) {
    $YapilandirmaYolu = Join-Path $PSScriptRoot 'merkez-ayarlari.json'
}
if ([string]::IsNullOrWhiteSpace($VeriKlasoru)) {
    $VeriKlasoru = Join-Path $PSScriptRoot 'veri'
}
# Ortak kural kumesi yapilandirmanin yaninda durur (-YapilandirmaYolu ile tasinabilir)
$KuralYolu = Join-Path (Split-Path -Parent $YapilandirmaYolu) 'merkez-kurallar.json'
$guncelKlasoru = Join-Path $VeriKlasoru 'guncel'
$gunlukKlasoru = Join-Path $VeriKlasoru 'gunluk'
$sayacKlasoru = Join-Path $VeriKlasoru 'sayac'
$logYolu = Join-Path $VeriKlasoru 'merkez.log'
$postaDurumYolu = Join-Path $VeriKlasoru 'posta-durum.json'
$durYolu = Join-Path $PSScriptRoot 'DUR-MERKEZ'

function MerkezLog {
    param([string]$Mesaj)
    $satir = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [merkez] $Mesaj"
    try { $satir | Out-File -LiteralPath $logYolu -Encoding utf8 -Append } catch { }
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

function Get-MerkezAyari {
    $ayar = Read-DagitikJson $YapilandirmaYolu
    if ($null -eq $ayar) {
        $ayar = New-VarsayilanMerkezAyari
        Write-DagitikJsonAtomik -Nesne $ayar -Yol $YapilandirmaYolu
    }
    return $ayar
}

function New-MerkezSonuc {
    param([int]$Kod, [object]$Nesne)
    return @{ kod = $Kod; nesne = $Nesne }
}

function Write-HttpYanit {
    param([System.Net.HttpListenerContext]$Baglam, [int]$Kod, [object]$Nesne)
    try {
        $json = $Nesne | ConvertTo-Json -Depth 6 -Compress
        $baytlar = [System.Text.Encoding]::UTF8.GetBytes($json)
        $Baglam.Response.StatusCode = $Kod
        $Baglam.Response.ContentType = 'application/json; charset=utf-8'
        $Baglam.Response.ContentLength64 = $baytlar.Length
        $Baglam.Response.OutputStream.Write($baytlar, 0, $baytlar.Length)
    }
    catch { }
    finally {
        try { $Baglam.Response.Close() } catch { }
    }
}

function Read-HttpGovde {
    param([System.Net.HttpListenerRequest]$Istek, [int]$EnFazla = 524288)
    if ($Istek.ContentLength64 -lt 1 -or $Istek.ContentLength64 -gt $EnFazla) { throw 'Gecersiz paket boyutu.' }
    $okuyucu = New-Object System.IO.StreamReader($Istek.InputStream, [System.Text.Encoding]::UTF8, $true, 4096, $false)
    try {
        $metin = $okuyucu.ReadToEnd()
        if ([System.Text.Encoding]::UTF8.GetByteCount($metin) -gt $EnFazla) { throw 'Gecersiz paket boyutu.' }
        return $metin
    }
    finally { $okuyucu.Dispose() }
}

# ---------- istemci adresi ve sinirlar ----------

function Get-MerkezIstemciAdresi {
    param([System.Net.HttpListenerContext]$Baglam)
    try {
        $adres = $Baglam.Request.RemoteEndPoint.Address
        if ($adres.IsIPv4MappedToIPv6) { $adres = $adres.MapToIPv4() }
        return $adres
    }
    catch { return $null }
}

$script:IpHatalari = @{}
function Test-MerkezIpSiniri {
    # Adres basina 10 dakikada 30 basarisiz zarf/kayit denemesi.
    param([object]$Adres)
    $anahtar = [string]$Adres
    $kayit = $script:IpHatalari[$anahtar]
    if ($null -eq $kayit) { return $true }
    if (([DateTime]::UtcNow - $kayit.pencere).TotalMinutes -gt 10) { $script:IpHatalari.Remove($anahtar); return $true }
    return ($kayit.sayi -lt 30)
}

function Add-MerkezIpHatasi {
    param([object]$Adres)
    $anahtar = [string]$Adres
    $simdi = [DateTime]::UtcNow
    if ($script:IpHatalari.Count -gt 2000) {
        foreach ($eski in @($script:IpHatalari.Keys | Where-Object { ($simdi - $script:IpHatalari[$_].pencere).TotalMinutes -gt 10 })) {
            $script:IpHatalari.Remove($eski)
        }
    }
    $kayit = $script:IpHatalari[$anahtar]
    if ($null -eq $kayit -or ($simdi - $kayit.pencere).TotalMinutes -gt 10) { $script:IpHatalari[$anahtar] = @{ pencere = $simdi; sayi = 1 } }
    else { $kayit.sayi++ }
}

function Test-KayitHizSiniri {
    # Kaba kuvvet denemesini yavaslatir: 10 dakikalik pencerede 10 basarisiz deneme sonrasi kilit.
    param([object]$Ayar)
    $pencere = Get-MerkezZaman (Get-DagitikDeger $Ayar 'kayitDenemePencereUtc' $null)
    if ($null -eq $pencere -or ([DateTime]::UtcNow - $pencere).TotalMinutes -gt 10) { return $true }
    return ([int](Get-DagitikDeger $Ayar 'kayitDenemeSayisi' 0) -lt 10)
}

function Add-KayitDenemesi {
    param([object]$Ayar)
    $simdi = [DateTime]::UtcNow
    $pencere = Get-MerkezZaman (Get-DagitikDeger $Ayar 'kayitDenemePencereUtc' $null)
    if ($null -eq $pencere -or ($simdi - $pencere).TotalMinutes -gt 10) {
        Set-DagitikDeger $Ayar 'kayitDenemePencereUtc' $simdi.ToString('o')
        Set-DagitikDeger $Ayar 'kayitDenemeSayisi' 1
    }
    else { Set-DagitikDeger $Ayar 'kayitDenemeSayisi' ([int](Get-DagitikDeger $Ayar 'kayitDenemeSayisi' 0) + 1) }
}

function Test-MerkezSayac {
    # Kural yazma zarflarinda tekrar korumasi: kayan pencere (1024). Pencerenin gerisinde
    # kalan ya da daha once gorulen sayac reddedilir. Ozet ve okuma istekleri zaten
    # tekrarlanabilir (bayat ozet atlanir), onlar icin sayac tutulmaz.
    param([string]$CihazId, [long]$Sayac)
    if ($Sayac -le 0) { return $false }
    $pencere = 1024
    $yol = Join-Path $sayacKlasoru "$CihazId.json"
    $durum = Read-DagitikJson $yol
    [long]$ust = 0
    $gorulen = @()
    if ($null -ne $durum) {
        [void][long]::TryParse([string](Get-DagitikDeger $durum 'ust' 0), [ref]$ust)
        $gorulen = @(@(Get-DagitikDeger $durum 'gorulen' @()) | ForEach-Object { [long]$_ })
    }
    if ($Sayac -le ($ust - $pencere)) { return $false }
    if ($gorulen -contains $Sayac) { return $false }
    if ($Sayac -gt $ust) { $ust = $Sayac }
    $gorulen = @(@($gorulen + $Sayac) | Where-Object { $_ -gt ($ust - $pencere) } | Sort-Object)
    Write-DagitikJsonAtomik -Nesne ([ordered]@{ ust = $ust; gorulen = $gorulen }) -Yol $yol
    return $true
}

# ---------- guvenli alanlar ----------

function Get-GuvenliUygulamalar {
    param([object[]]$Kaynak)
    $sonuc = @()
    foreach ($satir in @($Kaynak | Select-Object -First 100)) {
        $ad = ConvertTo-DagitikSinirliMetin (Get-DagitikDeger $satir 'ad' '') 100
        if ([string]::IsNullOrWhiteSpace($ad)) { continue }
        $sonuc += [pscustomobject][ordered]@{
            ad = $ad
            dakika = ConvertTo-DagitikDakika (Get-DagitikDeger $satir 'dakika' 0)
            kategori = ConvertTo-DagitikSinirliMetin (Get-DagitikDeger $satir 'kategori' 'diger') 30
            kaynak = ConvertTo-DagitikSinirliMetin (Get-DagitikDeger $satir 'kaynak' 'bilinmiyor') 40
        }
    }
    return @($sonuc | Sort-Object dakika -Descending)
}

function Get-GuvenliBasliklar {
    param([object[]]$Kaynak)
    $sonuc = @()
    foreach ($satir in @($Kaynak | Select-Object -First 50)) {
        $uygulama = ConvertTo-DagitikSinirliMetin (Get-DagitikDeger $satir 'uygulama' '') 100
        $baslik = ConvertTo-DagitikSinirliMetin (Get-DagitikDeger $satir 'baslik' '') 160
        if ([string]::IsNullOrWhiteSpace($uygulama) -or [string]::IsNullOrWhiteSpace($baslik)) { continue }
        $sonuc += [pscustomobject][ordered]@{
            uygulama = $uygulama
            baslik = $baslik
            dakika = ConvertTo-DagitikDakika (Get-DagitikDeger $satir 'dakika' 0)
        }
    }
    return @($sonuc | Sort-Object dakika -Descending)
}

# ---------- islem cekirdegi (tasimadan bagimsiz; @{ kod; nesne } doner) ----------

function Complete-MerkezCihazKaydi {
    # Kod dogrulandiktan sonra: yeni cihaz anahtari uretilir, kod verisi (v1 ve v2) silinir.
    # -PostaKanaliniKoru: v2 kaydinda yanit posta kutusundan alinabilsin diye kanal 30 dk tanimli kalir.
    param([object]$Ayar, [object]$Bulunan, [object]$Istek, [switch]$PostaKanaliniKoru)
    $simdi = [DateTime]::UtcNow
    $cihazId = [string](Get-DagitikDeger $Bulunan 'id' '')
    $anahtar = New-DagitikAnahtar
    $ad = ConvertTo-DagitikSinirliMetin (Get-DagitikDeger $Istek 'cihazAdi' (Get-DagitikDeger $Bulunan 'ad' $cihazId)) 80

    Set-DagitikDeger $Bulunan 'anahtarKorunmus' (Protect-DagitikAnahtar -Anahtar $anahtar -Amac "merkez:$cihazId")
    Set-DagitikDeger $Bulunan 'durum' 'kayitli'
    Set-DagitikDeger $Bulunan 'aktif' $true
    Set-DagitikDeger $Bulunan 'ad' $ad
    Set-DagitikDeger $Bulunan 'onayUtc' $simdi.ToString('o')
    Set-DagitikDeger $Bulunan 'istemciSurumu' (ConvertTo-DagitikSinirliMetin (Get-DagitikDeger $Istek 'surum' '') 20)
    Set-DagitikDeger $Bulunan 'istemciKullanicisi' (ConvertTo-DagitikSinirliMetin (Get-DagitikDeger $Istek 'kullanici' '') 80)
    # Kod tek kullanimlik: iki protokolun eslesme verisi de silinir
    Set-DagitikDeger $Bulunan 'kayitOzeti' ''
    Set-DagitikDeger $Bulunan 'kayitTuzu' ''
    Set-DagitikDeger $Bulunan 'kayitBitisUtc' ''
    Set-DagitikDeger $Bulunan 'kayitAnaAnahtarV2Korunmus' ''
    if ($PostaKanaliniKoru -and (Test-DagitikKayitKanali ([string](Get-DagitikDeger $Bulunan 'kayitKanaliV2' '')))) {
        Set-DagitikDeger $Bulunan 'postaKayitBitisUtc' $simdi.AddMinutes(30).ToString('o')
    }
    else {
        Set-DagitikDeger $Bulunan 'kayitKanaliV2' ''
        Set-DagitikDeger $Bulunan 'postaKayitJetonOzeti' ''
        Set-DagitikDeger $Bulunan 'postaKayitBitisUtc' ''
    }
    Set-DagitikDeger $Ayar 'kayitDenemeSayisi' 0
    Write-DagitikJsonAtomik -Nesne $Ayar -Yol $YapilandirmaYolu
    # Yeni anahtarla sayac sifirdan baslar
    $sayacYolu = Join-Path $sayacKlasoru "$cihazId.json"
    if (Test-Path -LiteralPath $sayacYolu) { Remove-Item -LiteralPath $sayacYolu -Force -ErrorAction SilentlyContinue }
    return @{
        cihazId = $cihazId
        anahtar = $anahtar
        ad = $ad
        baslikIzinli = [bool](Get-DagitikDeger $Bulunan 'baslikIzinli' $false)
    }
}

function Invoke-KurallarCekirdek {
    # Ortak kural kumesi. Kayitli her cihaz okuyabilir: hangi uygulamanin calisma/yasakli
    # sayildigi izlenen kisiden gizlenmez.
    $kurallar = Get-MerkezKurallari -Yol $KuralYolu
    return (New-MerkezSonuc 200 ([ordered]@{
        ok = $true
        sonDegisiklikUtc = [string](Get-DagitikDeger $kurallar 'sonDegisiklikUtc' '')
        kuralSayisi = (Get-MerkezKuralOzeti $kurallar)
        calisma = (Get-DagitikDeger $kurallar 'calisma' $null)
        yasakli = (Get-DagitikDeger $kurallar 'yasakli' $null)
        bilerekBelirsiz = @(Get-DagitikDeger $kurallar 'bilerekBelirsiz' @())
        silinenKurallar = @(Get-DagitikDeger $kurallar 'silinenKurallar' @())
    }))
}

function Invoke-KuralYazCekirdek {
    # Cihazdan gelen siniflandirma karari ortak kumeye islenir.
    # Yalnizca kuralYazabilir izni verilmis cihazlar yazabilir.
    param([object]$Kayit, [string]$CihazId, [string]$Govde)
    if (-not [bool](Get-DagitikDeger $Kayit 'kuralYazabilir' $false)) {
        MerkezLog "Kural yazma izni yok: $CihazId"
        return (New-MerkezSonuc 403 ([ordered]@{ ok = $false; hata = 'Bu cihazin kural yazma izni yok.' }))
    }
    try { $istek = $Govde | ConvertFrom-Json }
    catch { return (New-MerkezSonuc 400 ([ordered]@{ ok = $false; hata = 'JSON okunamadi.' })) }
    if ($null -eq $istek -or [int](Get-DagitikDeger $istek 'schemaVersion' 0) -ne 1) {
        return (New-MerkezSonuc 400 ([ordered]@{ ok = $false; hata = 'Paket semasi gecersiz.' }))
    }

    $kurallar = Get-MerkezKurallari -Yol $KuralYolu
    $islenen = 0
    $hatali = 0
    foreach ($karar in @(Get-DagitikDeger $istek 'kararlar' @())) {
        try {
            [void](Set-MerkezKural -Kurallar $kurallar `
                -Oge ([string](Get-DagitikDeger $karar 'oge' '')) `
                -Tur ([string](Get-DagitikDeger $karar 'tur' 'surec')) `
                -Karar ([string](Get-DagitikDeger $karar 'karar' '')))
            $islenen++
        }
        catch { $hatali++ }
    }
    if ($islenen -gt 0) {
        try { Write-DagitikJsonAtomik -Nesne $kurallar -Yol $KuralYolu }
        catch { return (New-MerkezSonuc 500 ([ordered]@{ ok = $false; hata = 'Kural kumesi yazilamadi.' })) }
        MerkezLog "Kural guncellendi: $CihazId, $islenen karar"
    }
    return (New-MerkezSonuc 200 ([ordered]@{
        ok = $true
        islenen = $islenen
        hatali = $hatali
        sonDegisiklikUtc = [string](Get-DagitikDeger $kurallar 'sonDegisiklikUtc' '')
    }))
}

function Invoke-ToplamCekirdek {
    # Istemci gun icindeki ORTAK toplami buradan ogrenir: kullanici birden fazla
    # bilgisayarda calisiyorsa hedef ve uyarilar toplam uzerinden isler.
    # Yalnizca sayilar doner; ham aktivite ya da baslik gitmez.
    param([string]$CihazId, [string]$Tarih)
    if ($Tarih -notmatch '^\d{4}-\d{2}-\d{2}$') { $Tarih = (Get-Date).ToString('yyyy-MM-dd') }
    $toplam = Get-MerkezGunToplami -VeriKlasoru $VeriKlasoru -Tarih $Tarih -HaricCihazId $CihazId
    return (New-MerkezSonuc 200 ([ordered]@{
        ok = $true
        tarih = $toplam.tarih
        toplamDk = $toplam.toplamDk
        buCihazDk = $toplam.buCihazDk
        digerCihazDk = $toplam.digerCihazDk
        cihazSayisi = $toplam.cihazSayisi
        cihazlar = @($toplam.cihazlar)
    }))
}

function Invoke-OzetCekirdek {
    param([object]$Kayit, [string]$CihazId, [string]$Govde)
    try { $paket = $Govde | ConvertFrom-Json }
    catch { return (New-MerkezSonuc 400 ([ordered]@{ ok = $false; hata = 'JSON paketi okunamadi.' })) }
    if ($null -eq $paket -or [int](Get-DagitikDeger $paket 'schemaVersion' 0) -ne 1 -or
        [string](Get-DagitikDeger $paket 'cihazId' '') -ne $CihazId) {
        return (New-MerkezSonuc 400 ([ordered]@{ ok = $false; hata = 'Paket semasi gecersiz.' }))
    }

    $tarih = [string](Get-DagitikDeger $paket 'clientTarih' '')
    [datetime]$tarihDegeri = [datetime]::MinValue
    if ($tarih -notmatch '^\d{4}-\d{2}-\d{2}$' -or -not [datetime]::TryParseExact(
        $tarih, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::None, [ref]$tarihDegeri)) {
        return (New-MerkezSonuc 400 ([ordered]@{ ok = $false; hata = 'Istemci tarihi gecersiz.' }))
    }
    $ozet = Get-DagitikDeger $paket 'ozet' $null
    if ($null -eq $ozet) {
        return (New-MerkezSonuc 400 ([ordered]@{ ok = $false; hata = 'Ozet alani eksik.' }))
    }

    $izinliBaslik = [bool](Get-DagitikDeger $Kayit 'baslikIzinli' $false)
    $uygulamalar = Get-GuvenliUygulamalar @((Get-DagitikDeger $paket 'uygulamalar' @()))
    $basliklar = @()
    if ($izinliBaslik) { $basliklar = Get-GuvenliBasliklar @((Get-DagitikDeger $paket 'basliklar' @())) }
    $alindi = [DateTime]::UtcNow.ToString('o')
    $sira = ConvertTo-DagitikDakika (Get-DagitikDeger $paket 'sira' 0) 2147483647
    $health = Get-DagitikDeger $paket 'health' $null
    $anlik = [ordered]@{
        schemaVersion = 1
        cihazId = $CihazId
        cihazAdi = ConvertTo-DagitikSinirliMetin (Get-DagitikDeger $Kayit 'ad' $CihazId) 80
        alindiUtc = $alindi
        sonGorulmeUtc = $alindi
        gonderildiUtc = ConvertTo-DagitikSinirliMetin (Get-DagitikDeger $paket 'gonderildiUtc' '') 40
        clientTarih = $tarih
        sira = $sira
        veriKapsami = [ordered]@{
            uygulamaOzetleri = $true
            pencereBasliklari = $izinliBaslik
            alanAdlari = $false
            tamUrl = $false
            aramaTerimleri = $false
            ekranGoruntusu = $false
            tusKaydi = $false
        }
        ozet = [ordered]@{
            calismaDk = ConvertTo-DagitikDakika (Get-DagitikDeger $ozet 'calismaDk' 0)
            digerDk = ConvertTo-DagitikDakika (Get-DagitikDeger $ozet 'digerDk' 0)
            bostaDk = ConvertTo-DagitikDakika (Get-DagitikDeger $ozet 'bostaDk' 0)
            kayitDk = ConvertTo-DagitikDakika (Get-DagitikDeger $ozet 'kayitDk' 0)
            hedefDk = ConvertTo-DagitikDakika (Get-DagitikDeger $ozet 'hedefDk' 240)
        }
        uygulamalar = @($uygulamalar)
        basliklar = @($basliklar)
        alanlar = @()
        health = [ordered]@{
            senkron = $(if ($null -ne (Get-DagitikDeger $health 'senkron' $null)) {
                $sn = Get-DagitikDeger $health 'senkron' $null
                [ordered]@{
                    sonBasariliGonderimUtc = ConvertTo-DagitikSinirliMetin (Get-DagitikDeger $sn 'sonBasariliGonderimUtc' '') 40
                    sonKuralAlimiUtc = ConvertTo-DagitikSinirliMetin (Get-DagitikDeger $sn 'sonKuralAlimiUtc' '') 40
                    bekleyenKarar = $(if ($null -eq (Get-DagitikDeger $sn 'bekleyenKarar' $null)) { $null } else { ConvertTo-DagitikDakika (Get-DagitikDeger $sn 'bekleyenKarar' 0) 1000000 })
                    hata = ConvertTo-DagitikSinirliMetin (Get-DagitikDeger $sn 'hata' '') 720
                    bildirimUtc = ConvertTo-DagitikSinirliMetin (Get-DagitikDeger $sn 'bildirimUtc' '') 40
                }
            } else { $null })
            kayitSatiri = ConvertTo-DagitikDakika (Get-DagitikDeger $health 'kayitSatiri' 0) 1000000
            sonOrnekUtc = ConvertTo-DagitikSinirliMetin (Get-DagitikDeger $health 'sonOrnekUtc' '') 40
            yerelIzleyiciCalisiyor = [bool](Get-DagitikDeger $health 'yerelIzleyiciCalisiyor' $false)
        }
    }
    $anlikYol = Join-Path $guncelKlasoru "$CihazId.json"
    $gunlukYol = Join-Path (Join-Path $gunlukKlasoru $tarih) "$CihazId.json"

    # Gec kalmis paket, ayni gunun daha yeni kumulatif ozetini geri almasin. Yeniden
    # kurulumda sira sifirlandigi icin once gonderim zamanina bakilir, sira tie-break'tir.
    $mevcut = Read-DagitikJson $anlikYol
    if ($null -ne $mevcut -and [string](Get-DagitikDeger $mevcut 'clientTarih' '') -eq $tarih) {
        $eskiGonderim = Get-MerkezZaman (Get-DagitikDeger $mevcut 'gonderildiUtc' $null)
        $yeniGonderim = Get-MerkezZaman (Get-DagitikDeger $paket 'gonderildiUtc' $null)
        $eskiSira = [int](Get-DagitikDeger $mevcut 'sira' 0)
        $bayat = $false
        if ($null -ne $eskiGonderim -and $null -ne $yeniGonderim) {
            if ($yeniGonderim -lt $eskiGonderim) { $bayat = $true }
            elseif ($yeniGonderim -eq $eskiGonderim -and $sira -le $eskiSira) { $bayat = $true }
        }
        elseif ($sira -le $eskiSira) { $bayat = $true }
        if ($bayat) {
            MerkezLog "Bayat paket atlandi: $CihazId (sira=$sira, kayitli=$eskiSira)"
            return (New-MerkezSonuc 200 ([ordered]@{ ok = $true; atlandi = $true; alindiUtc = $alindi }))
        }
    }

    try {
        Write-DagitikJsonAtomik -Nesne $anlik -Yol $anlikYol -Derinlik 8
        Write-DagitikJsonAtomik -Nesne $anlik -Yol $gunlukYol -Derinlik 8
    }
    catch {
        MerkezLog "Yazma hatasi: $CihazId"
        return (New-MerkezSonuc 500 ([ordered]@{ ok = $false; hata = 'Merkez veriyi kaydedemedi.' }))
    }
    MerkezLog "Ozet alindi: $CihazId, tarih=$tarih, uygulama=$($uygulamalar.Count)"
    return (New-MerkezSonuc 200 ([ordered]@{ ok = $true; alindiUtc = $alindi }))
}

# ---------- v1: imzali duz JSON (yalnizca yerel ag) ----------

function Invoke-KayitIstek {
    # Kullanici kurulumu eslesme koduyla buraya baglanir. Cihaz anahtari yalnizca
    # kodu bilen tarafin cozebilecegi bicimde sifreli doner; duz metin aga cikmaz.
    param([System.Net.HttpListenerContext]$Baglam)

    try { $govde = Read-HttpGovde $Baglam.Request }
    catch { Write-HttpYanit $Baglam 413 ([ordered]@{ ok = $false; hata = 'Paket boyutu gecersiz.' }); return }
    try { $istek = $govde | ConvertFrom-Json }
    catch { Write-HttpYanit $Baglam 400 ([ordered]@{ ok = $false; hata = 'JSON okunamadi.' }); return }
    if ($null -eq $istek -or [int](Get-DagitikDeger $istek 'schemaVersion' 0) -ne 1) {
        Write-HttpYanit $Baglam 400 ([ordered]@{ ok = $false; hata = 'Paket semasi gecersiz.' }); return
    }
    if (-not [bool](Get-DagitikDeger $istek 'onay' $false)) {
        Write-HttpYanit $Baglam 400 ([ordered]@{ ok = $false; hata = 'Kullanici onayi olmadan kayit yapilmaz.' }); return
    }
    $kod = ConvertTo-DagitikKodNormal ([string](Get-DagitikDeger $istek 'kod' ''))
    if ($kod.Length -lt 8) {
        Write-HttpYanit $Baglam 400 ([ordered]@{ ok = $false; hata = 'Kod gecersiz.' }); return
    }

    $ayar = Get-MerkezAyari
    if (-not (Test-KayitHizSiniri $ayar)) {
        MerkezLog 'Kayit hiz siniri asildi; istek reddedildi.'
        Write-HttpYanit $Baglam 429 ([ordered]@{ ok = $false; hata = 'Cok fazla deneme yapildi. 10 dakika sonra tekrar deneyin.' })
        return
    }

    $simdi = [DateTime]::UtcNow
    $bulunan = $null
    foreach ($cihaz in @(Get-DagitikDeger $ayar 'cihazlar' @())) {
        if ([string](Get-DagitikDeger $cihaz 'durum' '') -ne 'bekliyor') { continue }
        $tuz = [string](Get-DagitikDeger $cihaz 'kayitTuzu' '')
        $ozet = [string](Get-DagitikDeger $cihaz 'kayitOzeti' '')
        if ([string]::IsNullOrWhiteSpace($tuz) -or [string]::IsNullOrWhiteSpace($ozet)) { continue }
        $bitis = Get-MerkezZaman (Get-DagitikDeger $cihaz 'kayitBitisUtc' $null)
        if ($null -ne $bitis -and $bitis -lt $simdi) { continue }
        try { $hesaplanan = Get-DagitikKodOzeti -Kod $kod -Tuz $tuz } catch { continue }
        if (Test-DagitikBaytEsitlik ([Convert]::FromBase64String($hesaplanan)) ([Convert]::FromBase64String($ozet))) {
            $bulunan = $cihaz
            break
        }
    }

    if ($null -eq $bulunan) {
        Add-KayitDenemesi $ayar
        try { Write-DagitikJsonAtomik -Nesne $ayar -Yol $YapilandirmaYolu } catch { }
        MerkezLog 'Kayit kodu eslesmedi.'
        Write-HttpYanit $Baglam 403 ([ordered]@{ ok = $false; hata = 'Kod gecersiz, suresi dolmus veya kullanilmis.' })
        return
    }

    try { $sonuc = Complete-MerkezCihazKaydi -Ayar $ayar -Bulunan $bulunan -Istek $istek }
    catch {
        MerkezLog "Kayit yazilamadi: $([string](Get-DagitikDeger $bulunan 'id' ''))"
        Write-HttpYanit $Baglam 500 ([ordered]@{ ok = $false; hata = 'Merkez kaydi yazamadi.' })
        return
    }
    $sifreTuzu = Get-DagitikTuz
    $sarmal = Protect-DagitikKodIle -Metin $sonuc.anahtar -Kod $kod -Tuz $sifreTuzu

    MerkezLog "Cihaz kaydi tamamlandi: $($sonuc.cihazId) ($($sonuc.ad))"
    Write-HttpYanit $Baglam 200 ([ordered]@{
        ok = $true
        cihazId = $sonuc.cihazId
        cihazAdi = $sonuc.ad
        sunucuUrl = [string](Get-DagitikDeger $ayar 'istemciSunucuUrl' '')
        gonderimDakikasi = 5
        ayrintiDuzeyi = $(if ($sonuc.baslikIzinli) { 'baslikli' } else { 'ozet' })
        anahtar = [ordered]@{ tuz = $sifreTuzu; iv = $sarmal.iv; veri = $sarmal.veri; etiket = $sarmal.etiket }
        veriAciklamasi = 'Uygulama adi, kategori ve gunluk sure ozeti gonderilir. Tam URL, arama terimi, tus kaydi, pano ve ekran goruntusu gonderilmez.'
    })
}

function Test-IstekKimligi {
    # Imzali istek dogrulamasi (GET icin govde yerine yol+sorgu imzalanir).
    # Basarisizsa yaniti kendisi yazar ve $null doner.
    param(
        [System.Net.HttpListenerContext]$Baglam,
        [string]$Govde
    )
    $cihazKimligi = [string]$Baglam.Request.Headers['X-CT-Cihaz']
    $zaman = [string]$Baglam.Request.Headers['X-CT-Zaman']
    $imza = [string]$Baglam.Request.Headers['X-CT-Imza']
    if (-not (Test-DagitikCihazKimligi $cihazKimligi)) {
        Write-HttpYanit $Baglam 401 ([ordered]@{ ok = $false; hata = 'Kimlik dogrulanamadi.' })
        return $null
    }
    [long]$zamanSayi = 0
    if (-not [long]::TryParse($zaman, [ref]$zamanSayi) -or
        [math]::Abs([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - $zamanSayi) -gt 900) {
        Write-HttpYanit $Baglam 401 ([ordered]@{ ok = $false; hata = 'Zaman damgasi gecersiz.' })
        return $null
    }
    $ayar = Get-MerkezAyari
    $kayit = @($ayar.cihazlar | Where-Object { $_.id -eq $cihazKimligi -and [bool]$_.aktif } | Select-Object -First 1)
    if ($kayit.Count -ne 1 -or [string]::IsNullOrWhiteSpace([string]$kayit[0].anahtarKorunmus)) {
        Write-HttpYanit $Baglam 401 ([ordered]@{ ok = $false; hata = 'Cihaz kayitli veya etkin degil.' })
        return $null
    }
    try {
        $anahtar = Unprotect-DagitikAnahtar -KorunmusAnahtar $kayit[0].anahtarKorunmus -Amac "merkez:$cihazKimligi"
        $beklenen = Get-DagitikHmac -Anahtar $anahtar -ZamanDamgasi $zaman -Govde $Govde
    }
    catch {
        Write-HttpYanit $Baglam 401 ([ordered]@{ ok = $false; hata = 'Kimlik dogrulanamadi.' })
        return $null
    }
    if (-not (Test-DagitikSabitZamanliEsitlik $beklenen $imza)) {
        MerkezLog "Gecersiz imza: $cihazKimligi ($($Baglam.Request.Url.AbsolutePath))"
        Write-HttpYanit $Baglam 401 ([ordered]@{ ok = $false; hata = 'Kimlik dogrulanamadi.' })
        return $null
    }
    return [ordered]@{ cihazId = $cihazKimligi; kayit = $kayit[0]; ayar = $ayar }
}

function Invoke-KurallarIstek {
    param([System.Net.HttpListenerContext]$Baglam)
    $kimlik = Test-IstekKimligi -Baglam $Baglam -Govde ([string]$Baglam.Request.Url.PathAndQuery)
    if ($null -eq $kimlik) { return }
    $sonuc = Invoke-KurallarCekirdek
    Write-HttpYanit $Baglam $sonuc.kod $sonuc.nesne
}

function Invoke-KuralYazIstek {
    param([System.Net.HttpListenerContext]$Baglam)
    try { $govde = Read-HttpGovde $Baglam.Request }
    catch { Write-HttpYanit $Baglam 413 ([ordered]@{ ok = $false; hata = 'Paket boyutu gecersiz.' }); return }
    $kimlik = Test-IstekKimligi -Baglam $Baglam -Govde $govde
    if ($null -eq $kimlik) { return }
    $sonuc = Invoke-KuralYazCekirdek -Kayit $kimlik.kayit -CihazId $kimlik.cihazId -Govde $govde
    Write-HttpYanit $Baglam $sonuc.kod $sonuc.nesne
}

function Invoke-ToplamIstek {
    param([System.Net.HttpListenerContext]$Baglam)
    # GET isteginde govde yok: imza yol+sorgu uzerinden dogrulanir
    $kimlik = Test-IstekKimligi -Baglam $Baglam -Govde ([string]$Baglam.Request.Url.PathAndQuery)
    if ($null -eq $kimlik) { return }
    $tarih = ''
    try { $tarih = [string]$Baglam.Request.QueryString['tarih'] } catch { }
    $sonuc = Invoke-ToplamCekirdek -CihazId $kimlik.cihazId -Tarih $tarih
    Write-HttpYanit $Baglam $sonuc.kod $sonuc.nesne
}

function Invoke-OzetIstek {
    param([System.Net.HttpListenerContext]$Baglam)

    if ($Baglam.Request.HttpMethod -ne 'POST' -or $Baglam.Request.Url.AbsolutePath -ne '/v1/ozet') {
        Write-HttpYanit $Baglam 404 ([ordered]@{ ok = $false; hata = 'Bulunamadi.' })
        return $false
    }
    $cihazKimligi = [string]$Baglam.Request.Headers['X-CT-Cihaz']
    $zaman = [string]$Baglam.Request.Headers['X-CT-Zaman']
    $imza = [string]$Baglam.Request.Headers['X-CT-Imza']
    if (-not (Test-DagitikCihazKimligi $cihazKimligi)) {
        Write-HttpYanit $Baglam 401 ([ordered]@{ ok = $false; hata = 'Kimlik dogrulanamadi.' })
        return $false
    }
    [long]$zamanSayi = 0
    if (-not [long]::TryParse($zaman, [ref]$zamanSayi)) {
        Write-HttpYanit $Baglam 401 ([ordered]@{ ok = $false; hata = 'Zaman damgasi gecersiz.' })
        return $false
    }
    $simdiUnix = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    if ([math]::Abs($simdiUnix - $zamanSayi) -gt 900) {
        Write-HttpYanit $Baglam 401 ([ordered]@{ ok = $false; hata = 'Zaman damgasi gecersiz veya cok eski.' })
        return $false
    }
    try { $govde = Read-HttpGovde $Baglam.Request }
    catch {
        Write-HttpYanit $Baglam 413 ([ordered]@{ ok = $false; hata = 'Paket boyutu gecersiz.' })
        return $false
    }

    $ayar = Get-MerkezAyari
    $kayit = @($ayar.cihazlar | Where-Object { $_.id -eq $cihazKimligi -and [bool]$_.aktif } | Select-Object -First 1)
    if ($kayit.Count -ne 1 -or [string]::IsNullOrWhiteSpace([string]$kayit[0].anahtarKorunmus)) {
        Write-HttpYanit $Baglam 401 ([ordered]@{ ok = $false; hata = 'Cihaz kayitli veya etkin degil.' })
        return $false
    }
    try {
        $anahtar = Unprotect-DagitikAnahtar -KorunmusAnahtar $kayit[0].anahtarKorunmus -Amac "merkez:$cihazKimligi"
        $beklenen = Get-DagitikHmac -Anahtar $anahtar -ZamanDamgasi $zaman -Govde $govde
    }
    catch {
        MerkezLog "Anahtar okunamadi: $cihazKimligi"
        Write-HttpYanit $Baglam 401 ([ordered]@{ ok = $false; hata = 'Kimlik dogrulanamadi.' })
        return $false
    }
    if (-not (Test-DagitikSabitZamanliEsitlik $beklenen $imza)) {
        MerkezLog "Gecersiz imza: $cihazKimligi"
        Write-HttpYanit $Baglam 401 ([ordered]@{ ok = $false; hata = 'Kimlik dogrulanamadi.' })
        return $false
    }
    $sonuc = Invoke-OzetCekirdek -Kayit $kayit[0] -CihazId $cihazKimligi -Govde $govde
    Write-HttpYanit $Baglam $sonuc.kod $sonuc.nesne
    return ($sonuc.kod -eq 200)
}

# ---------- v2: sifreli zarf ----------

function Get-MerkezIstemciAdresleri {
    # v2 kayit yanitinda istemciye bildirilen adresler (istemci sirayla dener).
    param([object]$Ayar)
    $ek = @()
    $internet = ConvertFrom-DagitikAdres ([string](Get-DagitikDeger $Ayar 'internetUrl' ''))
    if ($null -ne $internet -and $internet.tur -eq 'dogrudan') { $ek += $internet.adres }
    return [ordered]@{
        sunucuUrl = [string](Get-DagitikDeger $Ayar 'istemciSunucuUrl' '')
        ekAdresler = @($ek)
        postaUrl = (Get-MerkezPostaAdresi $Ayar)
    }
}

function Invoke-MerkezKayitZarfi {
    # v2 kaydi: kanal kimligi koddan turetilir, istek ve yanit koddan turetilen anahtarla
    # sifrelidir. Kod ve cihaz anahtari aga duz metin cikmaz.
    param([object]$Zarf)
    $red = @{ http = 403; hata = 'Kod gecersiz, suresi dolmus veya kullanilmis.'; kimlikHatasi = $true }
    if ([string]$Zarf.tur -cne 'kayit') { return @{ http = 400; hata = 'Zarf turu gecersiz.'; kimlikHatasi = $true } }
    $kanal = [string]$Zarf.cihaz
    $ayar = Get-MerkezAyari
    $simdi = [DateTime]::UtcNow
    $bulunan = $null
    foreach ($cihaz in @(Get-DagitikDeger $ayar 'cihazlar' @())) {
        if ([string](Get-DagitikDeger $cihaz 'durum' '') -ne 'bekliyor') { continue }
        if ([string](Get-DagitikDeger $cihaz 'kayitKanaliV2' '') -cne $kanal) { continue }
        if ([string]::IsNullOrWhiteSpace([string](Get-DagitikDeger $cihaz 'kayitAnaAnahtarV2Korunmus' ''))) { continue }
        $bitis = Get-MerkezZaman (Get-DagitikDeger $cihaz 'kayitBitisUtc' $null)
        if ($null -ne $bitis -and $bitis -lt $simdi) { continue }
        $bulunan = $cihaz
        break
    }
    if ($null -eq $bulunan) { MerkezLog 'Kayit kanali eslesmedi (v2).'; return $red }
    $cihazId = [string](Get-DagitikDeger $bulunan 'id' '')
    try {
        $ana = Unprotect-DagitikAnahtar -KorunmusAnahtar ([string]$bulunan.kayitAnaAnahtarV2Korunmus) -Amac "merkez-kayit:$cihazId"
        $kayitAnahtarlari = Get-DagitikKayitAltAnahtarlari -AnaAnahtar $ana
        if ($kayitAnahtarlari.kanal -cne $kanal) { throw 'Kanal uyusmuyor.' }
        $metin = Open-DagitikZarf -Anahtarlar $kayitAnahtarlari -Zarf $Zarf
        $istek = $metin | ConvertFrom-Json
    }
    catch { MerkezLog "Kayit zarfi dogrulanamadi (v2): $cihazId"; return $red }

    $yanitla = {
        param([int]$Kod, [object]$Govde)
        $yanitMetni = [ordered]@{ kod = $Kod; govde = $Govde } | ConvertTo-Json -Depth 6 -Compress
        return @{ http = 200; zarf = (New-DagitikZarf -Anahtarlar $kayitAnahtarlari -Cihaz $kanal -Tur 'kayit' -Yon 'yanit' -Sayac ([long]$Zarf.sayac) -Metin $yanitMetni) }
    }
    if ($null -eq $istek -or [int](Get-DagitikDeger $istek 'schemaVersion' 0) -ne 2) {
        return (& $yanitla 400 ([ordered]@{ ok = $false; hata = 'Paket semasi gecersiz.' }))
    }
    if (-not [bool](Get-DagitikDeger $istek 'onay' $false)) {
        return (& $yanitla 400 ([ordered]@{ ok = $false; hata = 'Kullanici onayi olmadan kayit yapilmaz.' }))
    }
    try { $sonuc = Complete-MerkezCihazKaydi -Ayar $ayar -Bulunan $bulunan -Istek $istek -PostaKanaliniKoru }
    catch {
        MerkezLog "Kayit yazilamadi: $cihazId"
        return (& $yanitla 500 ([ordered]@{ ok = $false; hata = 'Merkez kaydi yazamadi.' }))
    }
    $adresler = Get-MerkezIstemciAdresleri $ayar
    MerkezLog "Cihaz kaydi tamamlandi (v2): $($sonuc.cihazId) ($($sonuc.ad))"
    return (& $yanitla 200 ([ordered]@{
        ok = $true
        cihazId = $sonuc.cihazId
        cihazAdi = $sonuc.ad
        anahtar = $sonuc.anahtar
        sunucuUrl = $adresler.sunucuUrl
        ekAdresler = @($adresler.ekAdresler)
        postaUrl = $adresler.postaUrl
        gonderimDakikasi = 5
        ayrintiDuzeyi = $(if ($sonuc.baslikIzinli) { 'baslikli' } else { 'ozet' })
        veriAciklamasi = 'Uygulama adi, kategori ve gunluk sure ozeti gonderilir. Tam URL, arama terimi, tus kaydi, pano ve ekran goruntusu gonderilmez.'
    }))
}

function Invoke-MerkezZarf {
    # Tasimadan bagimsiz v2 islemi. Donen: @{ http; hata; zarf (yanit zarfi); kimlikHatasi }
    #   http 200 -> zarf dolu; islem sonucu (kod + govde) zarfin icindedir.
    #   Diger    -> zarf acilamadi/reddedildi; yanit sifrelenemez, duz hata doner.
    param([object]$Zarf)
    if (-not (Test-DagitikZarfBicimi $Zarf) -or [string](Get-DagitikDeger $Zarf 'yon' '') -cne 'istek') {
        return @{ http = 400; hata = 'Zarf bicimi gecersiz.'; kimlikHatasi = $true }
    }
    $simdiUnix = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    [long]$zaman = $Zarf.zaman
    # Posta kutusunda bekleyen zarf gunlerce eski olabilir; 30 gun ust sinirdir. Gelecek en fazla 15 dk.
    if ($zaman -gt ($simdiUnix + 900) -or $zaman -lt ($simdiUnix - 30 * 86400)) {
        return @{ http = 401; hata = 'Zarf zamani gecersiz.'; kimlikHatasi = $true }
    }
    $cihaz = [string]$Zarf.cihaz
    if (Test-DagitikKayitKanali $cihaz) { return (Invoke-MerkezKayitZarfi -Zarf $Zarf) }

    $tur = [string]$Zarf.tur
    [long]$sayac = $Zarf.sayac
    $ayar = Get-MerkezAyari
    $kayit = @(@(Get-DagitikDeger $ayar 'cihazlar' @()) | Where-Object { [string]$_.id -ceq $cihaz -and [bool]$_.aktif } | Select-Object -First 1)
    if ($kayit.Count -ne 1 -or [string]::IsNullOrWhiteSpace([string]$kayit[0].anahtarKorunmus)) {
        return @{ http = 401; hata = 'Kimlik dogrulanamadi.'; kimlikHatasi = $true }
    }
    try {
        $anahtar = Unprotect-DagitikAnahtar -KorunmusAnahtar ([string]$kayit[0].anahtarKorunmus) -Amac "merkez:$cihaz"
        $anahtarlar = Get-DagitikZarfAnahtarlari $anahtar
        $metin = Open-DagitikZarf -Anahtarlar $anahtarlar -Zarf $Zarf
    }
    catch {
        MerkezLog "Gecersiz zarf: $cihaz ($tur)"
        return @{ http = 401; hata = 'Kimlik dogrulanamadi.'; kimlikHatasi = $true }
    }
    if ($tur -ceq 'kural' -and -not (Test-MerkezSayac -CihazId $cihaz -Sayac $sayac)) {
        MerkezLog "Tekrarlanan kural zarfi reddedildi: $cihaz (sayac=$sayac)"
        return @{ http = 409; hata = 'Bu zarf daha once islendi.'; kimlikHatasi = $false }
    }

    switch -CaseSensitive ($tur) {
        'ozet' { $sonuc = Invoke-OzetCekirdek -Kayit $kayit[0] -CihazId $cihaz -Govde $metin }
        'kural' { $sonuc = Invoke-MerkezDosyaKilidi $KuralYolu { Invoke-KuralYazCekirdek -Kayit $kayit[0] -CihazId $cihaz -Govde $metin } }
        'kurallar' { $sonuc = Invoke-KurallarCekirdek }
        'toplam' {
            $tarih = ''
            try { $tarih = [string](Get-DagitikDeger ($metin | ConvertFrom-Json) 'tarih' '') } catch { }
            $sonuc = Invoke-ToplamCekirdek -CihazId $cihaz -Tarih $tarih
        }
        default { $sonuc = New-MerkezSonuc 404 ([ordered]@{ ok = $false; hata = 'Bilinmeyen islem.' }) }
    }
    # Guncel adresler her yanitta sifreli gider: posta kutusu sonradan eklense ya da merkezin
    # yerel adresi degisse de kayitli cihazlar yeniden eslesmeden ogrenir.
    $yanitMetni = [ordered]@{ kod = $sonuc.kod; govde = $sonuc.nesne; adresler = (Get-MerkezIstemciAdresleri $ayar) } | ConvertTo-Json -Depth 8 -Compress
    return @{ http = 200; zarf = (New-DagitikZarf -Anahtarlar $anahtarlar -Cihaz $cihaz -Tur $tur -Yon 'yanit' -Sayac $sayac -Metin $yanitMetni) }
}

function Invoke-MerkezZarfKilitli {
    # Kayit zarfi merkez-ayarlari.json'u gunceller; cihaz-ekle.ps1 ile ayni kilidi kullanir.
    param([object]$Zarf)
    if (Test-DagitikKayitKanali ([string](Get-DagitikDeger $Zarf 'cihaz' ''))) {
        return (Invoke-MerkezDosyaKilidi $YapilandirmaYolu { Invoke-MerkezZarf -Zarf $Zarf })
    }
    return (Invoke-MerkezZarf -Zarf $Zarf)
}

function Invoke-ZarfIstek {
    param([System.Net.HttpListenerContext]$Baglam)
    $adres = Get-MerkezIstemciAdresi $Baglam
    if (-not (Test-MerkezIpSiniri $adres)) {
        Write-HttpYanit $Baglam 429 ([ordered]@{ ok = $false; hata = 'Cok fazla hatali deneme. 10 dakika sonra tekrar deneyin.' })
        return
    }
    try { $govde = Read-HttpGovde $Baglam.Request -EnFazla 1048576 }
    catch { Write-HttpYanit $Baglam 413 ([ordered]@{ ok = $false; hata = 'Paket boyutu gecersiz.' }); return }
    $zarf = $null
    try { $zarf = $govde | ConvertFrom-Json } catch { }
    if ($null -eq $zarf) {
        Add-MerkezIpHatasi $adres
        Write-HttpYanit $Baglam 400 ([ordered]@{ ok = $false; hata = 'Zarf okunamadi.' })
        return
    }
    try { $sonuc = Invoke-MerkezZarfKilitli -Zarf $zarf }
    catch {
        MerkezLog "Zarf islenemedi: $($_.Exception.GetType().Name)"
        Write-HttpYanit $Baglam 500 ([ordered]@{ ok = $false; hata = 'Merkez istegi tamamlayamadi.' })
        return
    }
    if ([bool]$sonuc.kimlikHatasi) { Add-MerkezIpHatasi $adres }
    if ($sonuc.http -eq 200) { Write-HttpYanit $Baglam 200 $sonuc.zarf }
    else { Write-HttpYanit $Baglam ([int]$sonuc.http) ([ordered]@{ ok = $false; hata = [string]$sonuc.hata }) }
}

# ---------- posta kutusu ----------

$script:PostaSonTur = [DateTime]::MinValue
$script:PostaSonKontrol = [DateTime]::MinValue
$script:PostaListeImzasi = ''
$script:PostaListeZamani = [DateTime]::MinValue
$script:PostaSonHata = ''

function Invoke-MerkezPostaTuru {
    # Posta kutusundaki zarflari alir, isler, yanitlari kutuya birakir. Hata yerel islemi durdurmaz.
    param([switch]$Zorla)
    # Dongu her saniye cagirir; ayar dosyasi en fazla 2 saniyede bir okunur
    if (-not $Zorla -and ([DateTime]::UtcNow - $script:PostaSonKontrol).TotalSeconds -lt 2) { return }
    $script:PostaSonKontrol = [DateTime]::UtcNow
    $ayar = Read-DagitikJson $YapilandirmaYolu
    $posta = Get-MerkezPostaAyari $ayar
    if ($null -eq $posta) { return }
    [int]$aralik = 60
    [void][int]::TryParse([string](Get-DagitikDeger $posta 'aralikSn' 60), [ref]$aralik)
    if ($aralik -lt 2) { $aralik = 2 }
    if ($aralik -gt 3600) { $aralik = 3600 }
    # Kayit bekleyen cihaz varsa kullanici kurulum ekraninda bekliyordur: sik bak
    if ($aralik -gt 5 -and (Test-MerkezBekleyenV2Kayit $ayar)) { $aralik = 5 }
    # Kutuya ulasilamiyorsa dinleyiciyi zaman asimlariyla sik sik bekletme
    elseif ($script:PostaSonHata -and $aralik -lt 60) { $aralik = 60 }
    if (-not $Zorla -and ([DateTime]::UtcNow - $script:PostaSonTur).TotalSeconds -lt $aralik) { return }
    $script:PostaSonTur = [DateTime]::UtcNow

    $islenen = 0
    try {
        $jeton = Unprotect-DagitikAnahtar -KorunmusAnahtar ([string]$posta.jetonKorunmus) -Amac 'merkez-posta'
        $kok = ([string]$posta.url).TrimEnd('/')
        $basliklar = @{ 'X-Aizen-Kutu' = [string]$posta.kutu; 'X-Aizen-Jeton' = $jeton }

        $liste = Get-MerkezPostaCihazListesi $ayar
        $imza = Get-DagitikMetinOzeti ((@{ l = @($liste) } | ConvertTo-Json -Depth 4 -Compress))
        if ($imza -ne $script:PostaListeImzasi -or ([DateTime]::UtcNow - $script:PostaListeZamani).TotalMinutes -ge 30) {
            [void](Invoke-MerkezPostaIstegi -Kok $kok -Basliklar $basliklar -Yontem POST -Yol '/r1/merkez/cihazlar' -Govde ([ordered]@{ cihazlar = @($liste) }))
            $script:PostaListeImzasi = $imza
            $script:PostaListeZamani = [DateTime]::UtcNow
        }

        for ($tur = 0; $tur -lt 20; $tur++) {
            $cevap = Invoke-MerkezPostaIstegi -Kok $kok -Basliklar $basliklar -Yol '/r1/merkez/gelen?en=25' -ZamanAsimiSn 30
            $mesajlar = @(Get-DagitikDeger $cevap 'mesajlar' @())
            if ($mesajlar.Count -eq 0) { break }
            $yanitlar = @()
            $nolar = @()
            foreach ($mesaj in $mesajlar) {
                $nolar += [long](Get-DagitikDeger $mesaj 'no' 0)
                $zarf = Get-DagitikDeger $mesaj 'zarf' $null
                if ([string](Get-DagitikDeger $zarf 'cihaz' '') -cne [string](Get-DagitikDeger $mesaj 'cihaz' '')) { continue }
                try { $sonuc = Invoke-MerkezZarfKilitli -Zarf $zarf }
                catch { MerkezLog "Posta zarfi islenemedi: $($_.Exception.GetType().Name)"; continue }
                if ($sonuc.http -eq 200) {
                    $yanitlar += [ordered]@{
                        cihaz = [string]$zarf.cihaz
                        anahtar = (Get-MerkezPostaYanitAnahtari ([string]$zarf.tur))
                        zarf = $sonuc.zarf
                    }
                }
                else { MerkezLog "Posta zarfi reddedildi: $([string]$zarf.cihaz) (HTTP $($sonuc.http))" }
            }
            if ($yanitlar.Count -gt 0) {
                [void](Invoke-MerkezPostaIstegi -Kok $kok -Basliklar $basliklar -Yontem POST -Yol '/r1/merkez/gonder' -Govde ([ordered]@{ mesajlar = @($yanitlar) }) -ZamanAsimiSn 30)
            }
            [void](Invoke-MerkezPostaIstegi -Kok $kok -Basliklar $basliklar -Yontem POST -Yol '/r1/merkez/onay' -Govde ([ordered]@{ nolar = @($nolar) }))
            $islenen += $mesajlar.Count
            if ($mesajlar.Count -lt 25) { break }
        }
        if ($islenen -gt 0) { MerkezLog "Posta kutusundan $islenen zarf islendi." }
        $script:PostaSonHata = ''
        try {
            Write-DagitikJsonAtomik -Nesne ([ordered]@{
                sonDenemeUtc = [DateTime]::UtcNow.ToString('o')
                sonBasariliUtc = [DateTime]::UtcNow.ToString('o')
                sonIslenen = $islenen
                hata = ''
            }) -Yol $postaDurumYolu
        } catch { }
    }
    catch {
        $kod = 0
        try { $kod = [int]$_.Exception.Response.StatusCode } catch { }
        $hata = $(if ($kod -gt 0) { "Posta kutusu HTTP $kod dondurdu." } else { 'Posta kutusuna ulasilamadi.' })
        if ($hata -ne $script:PostaSonHata) { MerkezLog $hata; $script:PostaSonHata = $hata }
        # Liste gonderilemediyse bir sonraki turda yeniden denensin
        $script:PostaListeImzasi = ''
        try {
            $onceki = Read-DagitikJson $postaDurumYolu
            Write-DagitikJsonAtomik -Nesne ([ordered]@{
                sonDenemeUtc = [DateTime]::UtcNow.ToString('o')
                sonBasariliUtc = [string](Get-DagitikDeger $onceki 'sonBasariliUtc' '')
                sonIslenen = $islenen
                hata = $hata
            }) -Yol $postaDurumYolu
        } catch { }
    }
}

# ---------- ana dongu ----------

[void][System.IO.Directory]::CreateDirectory($guncelKlasoru)
[void][System.IO.Directory]::CreateDirectory($gunlukKlasoru)
[void][System.IO.Directory]::CreateDirectory($sayacKlasoru)
$ayar = Get-MerkezAyari
if ($Port -gt 0) { $DinlemeOnEki = "http://+:$Port/" }
if ([string]::IsNullOrWhiteSpace($DinlemeOnEki)) { $DinlemeOnEki = [string](Get-DagitikDeger $ayar 'dinlemeOnEki' 'http://+:8787/') }
if (-not $DinlemeOnEki.EndsWith('/')) { $DinlemeOnEki += '/' }
if ($DinlemeOnEki -notmatch '^https?://.+/$') { throw 'DinlemeOnEki gecersiz.' }

$sonTemizlik = (Get-Date).Date
$silinenGun = Remove-MerkezEskiGunluk -VeriKlasoru $VeriKlasoru -SaklamaGun ([int](Get-DagitikDeger $ayar 'saklamaGun' 90))
if ($silinenGun -gt 0) { MerkezLog "Saklama suresi temizligi: $silinenGun gun silindi." }

$baslangic = [DateTime]::UtcNow
$dinleyici = New-Object System.Net.HttpListener
$dinleyici.Prefixes.Add($DinlemeOnEki)
try {
    $dinleyici.Start()
    MerkezLog "Sunucu basladi: $DinlemeOnEki"
    Write-Output "Merkez sunucusu dinliyor: $DinlemeOnEki"
    # Merkez kapaliyken posta kutusunda biriken zarflar dogrudan gelecek yenilerinden once islensin
    Invoke-MerkezPostaTuru -Zorla
    $islenen = 0
    # Testlerde sunucu belirli sayida istekten sonra kapanir; -BirKere = 1 istek
    $istekSiniri = $IstekSayisi
    if ($BirKere -and $istekSiniri -le 0) { $istekSiniri = 1 }
    $sureDoldu = $false
    while ($dinleyici.IsListening) {
        if (Test-Path -LiteralPath $durYolu) {
            MerkezLog 'DUR-MERKEZ istendi; sunucu kapaniyor.'
            break
        }
        $bekleyen = $dinleyici.BeginGetContext($null, $null)
        while (-not $bekleyen.AsyncWaitHandle.WaitOne(1000)) {
            if (Test-Path -LiteralPath $durYolu) { break }
            if ($CalismaSuresiSn -gt 0 -and ([DateTime]::UtcNow - $baslangic).TotalSeconds -ge $CalismaSuresiSn) { $sureDoldu = $true; break }
            Invoke-MerkezPostaTuru
        }
        if ((Test-Path -LiteralPath $durYolu) -or $sureDoldu) { break }
        # Gunde bir kez saklama suresi disindaki gunluk arsivi temizle
        if ((Get-Date).Date -ne $sonTemizlik) {
            $sonTemizlik = (Get-Date).Date
            $silinenGun = Remove-MerkezEskiGunluk -VeriKlasoru $VeriKlasoru -SaklamaGun ([int](Get-DagitikDeger (Get-MerkezAyari) 'saklamaGun' 90))
            if ($silinenGun -gt 0) { MerkezLog "Saklama suresi temizligi: $silinenGun gun silindi." }
        }
        $baglam = $dinleyici.EndGetContext($bekleyen)
        $istekYolu = $baglam.Request.Url.AbsolutePath
        $yontem = $baglam.Request.HttpMethod
        if ($yontem -eq 'GET' -and $istekYolu -eq '/health') {
            Write-HttpYanit $baglam 200 ([ordered]@{ ok = $true; zamanUtc = [DateTime]::UtcNow.ToString('o'); protokol = 2 })
        }
        elseif ($yontem -eq 'POST' -and $istekYolu -eq '/v2/zarf') {
            Invoke-ZarfIstek $baglam
            $islenen++
        }
        elseif (-not (Test-DagitikYerelAdres (Get-MerkezIstemciAdresi $baglam))) {
            # v1 kaydinda kod duz gider ve imzali istekler sifresizdir: internete acilmaz
            Write-HttpYanit $baglam 403 ([ordered]@{ ok = $false; hata = 'Bu uc yalnizca yerel agdan kullanilabilir; Aizen istemcisini guncelleyin.' })
            $islenen++
        }
        elseif ($yontem -eq 'POST' -and $istekYolu -eq '/v1/kayit') {
            Invoke-MerkezDosyaKilidi $YapilandirmaYolu { Invoke-KayitIstek $baglam }
            $islenen++
        }
        elseif ($yontem -eq 'GET' -and $istekYolu -eq '/v1/toplam') {
            Invoke-ToplamIstek $baglam
            $islenen++
        }
        elseif ($yontem -eq 'GET' -and $istekYolu -eq '/v1/kurallar') {
            Invoke-KurallarIstek $baglam
            $islenen++
        }
        elseif ($yontem -eq 'POST' -and $istekYolu -eq '/v1/kural') {
            Invoke-MerkezDosyaKilidi $KuralYolu { Invoke-KuralYazIstek $baglam }
            $islenen++
        }
        else {
            [void](Invoke-OzetIstek $baglam)
            $islenen++
        }
        if ($istekSiniri -gt 0 -and $islenen -ge $istekSiniri) { break }
    }
}
finally {
    try { if ($dinleyici.IsListening) { $dinleyici.Stop() } } catch { }
    try { $dinleyici.Close() } catch { }
}
