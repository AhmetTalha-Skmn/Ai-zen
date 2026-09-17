<#
Merkez ozet alma sunucusu. Yalnizca /v1/ozet endpointini kabul eder;
mevcut yerel API/MCP yuzeylerini agda acmaz ve istemciye komut gondermez.
LAN/VPN disinda kullanmak icin HTTPS sonlandirma ve kurumun erisim politikasi gerekir.
#>
param(
    [int]$Port = 0,
    [string]$DinlemeOnEki,
    [string]$YapilandirmaYolu,
    [string]$VeriKlasoru,
    [switch]$BirKere,
    [int]$IstekSayisi = 0
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Ortak.ps1')
. (Join-Path $PSScriptRoot 'Merkez-Ozet.ps1')
. (Join-Path $PSScriptRoot 'Merkez-Kural.ps1')

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
$logYolu = Join-Path $VeriKlasoru 'merkez.log'
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
    param([System.Net.HttpListenerRequest]$Istek)
    if ($Istek.ContentLength64 -lt 1 -or $Istek.ContentLength64 -gt 524288) { throw 'Gecersiz paket boyutu.' }
    $okuyucu = New-Object System.IO.StreamReader($Istek.InputStream, [System.Text.Encoding]::UTF8, $true, 4096, $false)
    try {
        $metin = $okuyucu.ReadToEnd()
        if ([System.Text.Encoding]::UTF8.GetByteCount($metin) -gt 524288) { throw 'Gecersiz paket boyutu.' }
        return $metin
    }
    finally { $okuyucu.Dispose() }
}

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

    $cihazId = [string](Get-DagitikDeger $bulunan 'id' '')
    $anahtar = New-DagitikAnahtar
    $sifreTuzu = Get-DagitikTuz
    $sarmal = Protect-DagitikKodIle -Metin $anahtar -Kod $kod -Tuz $sifreTuzu
    $ad = ConvertTo-DagitikSinirliMetin (Get-DagitikDeger $istek 'cihazAdi' (Get-DagitikDeger $bulunan 'ad' $cihazId)) 80
    $baslikIzinli = [bool](Get-DagitikDeger $bulunan 'baslikIzinli' $false)

    Set-DagitikDeger $bulunan 'anahtarKorunmus' (Protect-DagitikAnahtar -Anahtar $anahtar -Amac "merkez:$cihazId")
    Set-DagitikDeger $bulunan 'durum' 'kayitli'
    Set-DagitikDeger $bulunan 'aktif' $true
    Set-DagitikDeger $bulunan 'ad' $ad
    Set-DagitikDeger $bulunan 'onayUtc' $simdi.ToString('o')
    Set-DagitikDeger $bulunan 'istemciSurumu' (ConvertTo-DagitikSinirliMetin (Get-DagitikDeger $istek 'surum' '') 20)
    Set-DagitikDeger $bulunan 'istemciKullanicisi' (ConvertTo-DagitikSinirliMetin (Get-DagitikDeger $istek 'kullanici' '') 80)
    # Kod tek kullanimlik: eslesme verisi silinir
    Set-DagitikDeger $bulunan 'kayitOzeti' ''
    Set-DagitikDeger $bulunan 'kayitTuzu' ''
    Set-DagitikDeger $bulunan 'kayitBitisUtc' ''
    Set-DagitikDeger $ayar 'kayitDenemeSayisi' 0
    try { Write-DagitikJsonAtomik -Nesne $ayar -Yol $YapilandirmaYolu }
    catch {
        MerkezLog "Kayit yazilamadi: $cihazId"
        Write-HttpYanit $Baglam 500 ([ordered]@{ ok = $false; hata = 'Merkez kaydi yazamadi.' })
        return
    }

    MerkezLog "Cihaz kaydi tamamlandi: $cihazId ($ad)"
    Write-HttpYanit $Baglam 200 ([ordered]@{
        ok = $true
        cihazId = $cihazId
        cihazAdi = $ad
        sunucuUrl = [string](Get-DagitikDeger $ayar 'istemciSunucuUrl' '')
        gonderimDakikasi = 5
        ayrintiDuzeyi = $(if ($baslikIzinli) { 'baslikli' } else { 'ozet' })
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
    # Ortak kural kumesini dondurur. Kayitli her cihaz okuyabilir: hangi
    # uygulamanin calisma/yasakli sayildigi izlenen kisiden gizlenmez.
    param([System.Net.HttpListenerContext]$Baglam)
    $kimlik = Test-IstekKimligi -Baglam $Baglam -Govde ([string]$Baglam.Request.Url.PathAndQuery)
    if ($null -eq $kimlik) { return }
    $kurallar = Get-MerkezKurallari -Yol $KuralYolu
    Write-HttpYanit $Baglam 200 ([ordered]@{
        ok = $true
        sonDegisiklikUtc = [string](Get-DagitikDeger $kurallar 'sonDegisiklikUtc' '')
        kuralSayisi = (Get-MerkezKuralOzeti $kurallar)
        calisma = (Get-DagitikDeger $kurallar 'calisma' $null)
        yasakli = (Get-DagitikDeger $kurallar 'yasakli' $null)
        bilerekBelirsiz = @(Get-DagitikDeger $kurallar 'bilerekBelirsiz' @())
        silinenKurallar = @(Get-DagitikDeger $kurallar 'silinenKurallar' @())
    })
}

function Invoke-KuralYazIstek {
    # Cihazdan gelen siniflandirma karari ortak kumeye islenir.
    # Yalnizca kuralYazabilir izni verilmis cihazlar yazabilir.
    param([System.Net.HttpListenerContext]$Baglam)
    try { $govde = Read-HttpGovde $Baglam.Request }
    catch { Write-HttpYanit $Baglam 413 ([ordered]@{ ok = $false; hata = 'Paket boyutu gecersiz.' }); return }
    $kimlik = Test-IstekKimligi -Baglam $Baglam -Govde $govde
    if ($null -eq $kimlik) { return }
    if (-not [bool](Get-DagitikDeger $kimlik.kayit 'kuralYazabilir' $false)) {
        MerkezLog "Kural yazma izni yok: $($kimlik.cihazId)"
        Write-HttpYanit $Baglam 403 ([ordered]@{ ok = $false; hata = 'Bu cihazin kural yazma izni yok.' })
        return
    }
    try { $istek = $govde | ConvertFrom-Json }
    catch { Write-HttpYanit $Baglam 400 ([ordered]@{ ok = $false; hata = 'JSON okunamadi.' }); return }
    if ($null -eq $istek -or [int](Get-DagitikDeger $istek 'schemaVersion' 0) -ne 1) {
        Write-HttpYanit $Baglam 400 ([ordered]@{ ok = $false; hata = 'Paket semasi gecersiz.' }); return
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
        catch {
            Write-HttpYanit $Baglam 500 ([ordered]@{ ok = $false; hata = 'Kural kumesi yazilamadi.' })
            return
        }
        MerkezLog "Kural guncellendi: $($kimlik.cihazId), $islenen karar"
    }
    Write-HttpYanit $Baglam 200 ([ordered]@{
        ok = $true
        islenen = $islenen
        hatali = $hatali
        sonDegisiklikUtc = [string](Get-DagitikDeger $kurallar 'sonDegisiklikUtc' '')
    })
}

function Invoke-ToplamIstek {
    # Istemci gun icindeki ORTAK toplami buradan ogrenir: kullanici birden fazla
    # bilgisayarda calisiyorsa hedef ve uyarilar toplam uzerinden isler.
    # Yalnizca sayilar doner; ham aktivite ya da baslik gitmez.
    param([System.Net.HttpListenerContext]$Baglam)

    # GET isteginde govde yok: imza yol+sorgu uzerinden dogrulanir
    $kimlik = Test-IstekKimligi -Baglam $Baglam -Govde ([string]$Baglam.Request.Url.PathAndQuery)
    if ($null -eq $kimlik) { return }
    $cihazKimligi = $kimlik.cihazId

    $tarih = ''
    try { $tarih = [string]$Baglam.Request.QueryString['tarih'] } catch { }
    if ($tarih -notmatch '^\d{4}-\d{2}-\d{2}$') { $tarih = (Get-Date).ToString('yyyy-MM-dd') }
    $toplam = Get-MerkezGunToplami -VeriKlasoru $VeriKlasoru -Tarih $tarih -HaricCihazId $cihazKimligi
    Write-HttpYanit $Baglam 200 ([ordered]@{
        ok = $true
        tarih = $toplam.tarih
        toplamDk = $toplam.toplamDk
        buCihazDk = $toplam.buCihazDk
        digerCihazDk = $toplam.digerCihazDk
        cihazSayisi = $toplam.cihazSayisi
        cihazlar = @($toplam.cihazlar)
    })
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
    try { $paket = $govde | ConvertFrom-Json }
    catch {
        Write-HttpYanit $Baglam 400 ([ordered]@{ ok = $false; hata = 'JSON paketi okunamadi.' })
        return $false
    }
    if ($null -eq $paket -or [int](Get-DagitikDeger $paket 'schemaVersion' 0) -ne 1 -or
        [string](Get-DagitikDeger $paket 'cihazId' '') -ne $cihazKimligi) {
        Write-HttpYanit $Baglam 400 ([ordered]@{ ok = $false; hata = 'Paket semasi gecersiz.' })
        return $false
    }

    $tarih = [string](Get-DagitikDeger $paket 'clientTarih' '')
    [datetime]$tarihDegeri = [datetime]::MinValue
    if ($tarih -notmatch '^\d{4}-\d{2}-\d{2}$' -or -not [datetime]::TryParseExact(
        $tarih, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::None, [ref]$tarihDegeri)) {
        Write-HttpYanit $Baglam 400 ([ordered]@{ ok = $false; hata = 'Istemci tarihi gecersiz.' })
        return $false
    }
    $ozet = Get-DagitikDeger $paket 'ozet' $null
    if ($null -eq $ozet) {
        Write-HttpYanit $Baglam 400 ([ordered]@{ ok = $false; hata = 'Ozet alani eksik.' })
        return $false
    }

    $izinliBaslik = [bool](Get-DagitikDeger $kayit[0] 'baslikIzinli' $false)
    $uygulamalar = Get-GuvenliUygulamalar @((Get-DagitikDeger $paket 'uygulamalar' @()))
    $basliklar = @()
    if ($izinliBaslik) { $basliklar = Get-GuvenliBasliklar @((Get-DagitikDeger $paket 'basliklar' @())) }
    $alindi = [DateTime]::UtcNow.ToString('o')
    $sira = ConvertTo-DagitikDakika (Get-DagitikDeger $paket 'sira' 0) 2147483647
    $health = Get-DagitikDeger $paket 'health' $null
    $anlik = [ordered]@{
        schemaVersion = 1
        cihazId = $cihazKimligi
        cihazAdi = ConvertTo-DagitikSinirliMetin (Get-DagitikDeger $kayit[0] 'ad' $cihazKimligi) 80
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
    $anlikYol = Join-Path $guncelKlasoru "$cihazKimligi.json"
    $gunlukYol = Join-Path (Join-Path $gunlukKlasoru $tarih) "$cihazKimligi.json"

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
            MerkezLog "Bayat paket atlandi: $cihazKimligi (sira=$sira, kayitli=$eskiSira)"
            Write-HttpYanit $Baglam 200 ([ordered]@{ ok = $true; atlandi = $true; alindiUtc = $alindi })
            return $true
        }
    }

    try {
        Write-DagitikJsonAtomik -Nesne $anlik -Yol $anlikYol -Derinlik 8
        Write-DagitikJsonAtomik -Nesne $anlik -Yol $gunlukYol -Derinlik 8
    }
    catch {
        MerkezLog "Yazma hatasi: $cihazKimligi"
        Write-HttpYanit $Baglam 500 ([ordered]@{ ok = $false; hata = 'Merkez veriyi kaydedemedi.' })
        return $false
    }
    MerkezLog "Ozet alindi: $cihazKimligi, tarih=$tarih, uygulama=$($uygulamalar.Count)"
    Write-HttpYanit $Baglam 200 ([ordered]@{ ok = $true; alindiUtc = $alindi })
    return $true
}

[void][System.IO.Directory]::CreateDirectory($guncelKlasoru)
[void][System.IO.Directory]::CreateDirectory($gunlukKlasoru)
$ayar = Get-MerkezAyari
if ($Port -gt 0) { $DinlemeOnEki = "http://+:$Port/" }
if ([string]::IsNullOrWhiteSpace($DinlemeOnEki)) { $DinlemeOnEki = [string](Get-DagitikDeger $ayar 'dinlemeOnEki' 'http://+:8787/') }
if (-not $DinlemeOnEki.EndsWith('/')) { $DinlemeOnEki += '/' }
if ($DinlemeOnEki -notmatch '^https?://.+/$') { throw 'DinlemeOnEki gecersiz.' }

$sonTemizlik = (Get-Date).Date
$silinenGun = Remove-MerkezEskiGunluk -VeriKlasoru $VeriKlasoru -SaklamaGun ([int](Get-DagitikDeger $ayar 'saklamaGun' 90))
if ($silinenGun -gt 0) { MerkezLog "Saklama suresi temizligi: $silinenGun gun silindi." }

$dinleyici = New-Object System.Net.HttpListener
$dinleyici.Prefixes.Add($DinlemeOnEki)
try {
    $dinleyici.Start()
    MerkezLog "Sunucu basladi: $DinlemeOnEki"
    Write-Output "Merkez sunucusu dinliyor: $DinlemeOnEki"
    $islenen = 0
    # Testlerde sunucu belirli sayida istekten sonra kapanir; -BirKere = 1 istek
    $istekSiniri = $IstekSayisi
    if ($BirKere -and $istekSiniri -le 0) { $istekSiniri = 1 }
    while ($dinleyici.IsListening) {
        if (Test-Path -LiteralPath $durYolu) {
            MerkezLog 'DUR-MERKEZ istendi; sunucu kapaniyor.'
            break
        }
        $bekleyen = $dinleyici.BeginGetContext($null, $null)
        while (-not $bekleyen.AsyncWaitHandle.WaitOne(1000)) {
            if (Test-Path -LiteralPath $durYolu) { break }
        }
        if (Test-Path -LiteralPath $durYolu) { break }
        # Gunde bir kez saklama suresi disindaki gunluk arsivi temizle
        if ((Get-Date).Date -ne $sonTemizlik) {
            $sonTemizlik = (Get-Date).Date
            $silinenGun = Remove-MerkezEskiGunluk -VeriKlasoru $VeriKlasoru -SaklamaGun ([int](Get-DagitikDeger (Get-MerkezAyari) 'saklamaGun' 90))
            if ($silinenGun -gt 0) { MerkezLog "Saklama suresi temizligi: $silinenGun gun silindi." }
        }
        $baglam = $dinleyici.EndGetContext($bekleyen)
        $istekYolu = $baglam.Request.Url.AbsolutePath
        if ($baglam.Request.HttpMethod -eq 'GET' -and $istekYolu -eq '/health') {
            Write-HttpYanit $baglam 200 ([ordered]@{ ok = $true; zamanUtc = [DateTime]::UtcNow.ToString('o') })
        }
        elseif ($baglam.Request.HttpMethod -eq 'POST' -and $istekYolu -eq '/v1/kayit') {
            Invoke-MerkezDosyaKilidi $YapilandirmaYolu { Invoke-KayitIstek $baglam }
            $islenen++
        }
        elseif ($baglam.Request.HttpMethod -eq 'GET' -and $istekYolu -eq '/v1/toplam') {
            Invoke-ToplamIstek $baglam
            $islenen++
        }
        elseif ($baglam.Request.HttpMethod -eq 'GET' -and $istekYolu -eq '/v1/kurallar') {
            Invoke-KurallarIstek $baglam
            $islenen++
        }
        elseif ($baglam.Request.HttpMethod -eq 'POST' -and $istekYolu -eq '/v1/kural') {
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
