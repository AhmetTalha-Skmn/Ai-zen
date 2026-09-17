<#
Yerel aktivite kayitlarindan gizlilik filtreli gunluk ozet uretir ve merkeze gonderir.
Bu dosya izleyici dongusunden AYRI calisir. Merkez kapaliysa en son gunluk ozet
yerel outbox klasorunde kalir; ham tus, ekran goruntusu, tam URL ve arama verisi
toplanmaz veya gonderilmez.
#>
param(
    [string]$HatirlaticiKlasoru,
    [switch]$SadeceKuyrugaAl
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Ortak.ps1')
. (Join-Path $PSScriptRoot 'Senkron-Durum.ps1')

if ([string]::IsNullOrWhiteSpace($HatirlaticiKlasoru)) {
    $HatirlaticiKlasoru = Join-Path (Get-DagitikUygulamaKok $PSScriptRoot) 'hatirlatici'
}

$bakimIsareti = Join-Path $HatirlaticiKlasoru 'GERI-YUKLEME'; if (Test-Path -LiteralPath $bakimIsareti) { try { [IO.File]::Open($bakimIsareti, 'Open', 'ReadWrite', 'None').Dispose(); [IO.File]::Delete($bakimIsareti) } catch { exit 0 } }
# Gorev wscript + gizli.vbs ile baslar ve hemen doner; Gorev Zamanlayici'nin
# IgnoreNew korumasi bu yuzden isler degil. Ust uste binen iki gonderimi bu kilit onler.
$kilitYolu = ([IO.Path]::GetFullPath($HatirlaticiKlasoru)).TrimEnd('\').ToLower()
$kilitOzet = [Security.Cryptography.MD5]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($kilitYolu))
$kilitIz = [BitConverter]::ToString($kilitOzet).Replace('-', '').Substring(0, 12)
$kilitYeni = $false
$kilit = New-Object System.Threading.Mutex($true, "Local\CalismaTakipGonderici_$kilitIz", [ref]$kilitYeni)
if (-not $kilitYeni) { exit 0 }

$ayarYolu = Join-Path $HatirlaticiKlasoru 'merkez.json'
$durumYolu = Join-Path $HatirlaticiKlasoru 'durum.json'
$hedefYolu = Join-Path $HatirlaticiKlasoru 'ayarlar.json'
$outboxKlasoru = Join-Path $HatirlaticiKlasoru 'merkez-outbox'
$redKlasoru = Join-Path $outboxKlasoru 'reddedilen'
$logYolu = Join-Path $HatirlaticiKlasoru 'merkez-gonderici.log'

function GondericiLog {
    param([string]$Mesaj)
    $satir = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [gonderici] $Mesaj"
    try { $satir | Out-File -LiteralPath $logYolu -Encoding utf8 -Append } catch { }
}

function Get-Saniye {
    param([object]$Deger)
    [double]$sayi = 0
    if (-not [double]::TryParse(([string]$Deger), [Globalization.NumberStyles]::Float,
        [Globalization.CultureInfo]::InvariantCulture, [ref]$sayi)) {
        [void][double]::TryParse(([string]$Deger), [ref]$sayi)
    }
    if ($sayi -lt 0) { return 0 }
    if ($sayi -gt 86400) { return 86400 }
    return $sayi
}

function Get-SureToplami {
    param([object[]]$Satirlar)
    [double]$toplam = 0
    foreach ($satir in @($Satirlar)) { $toplam += Get-Saniye $satir.sure }
    return $toplam
}

function Get-BaskinAlan {
    param([object[]]$Satirlar, [string]$Alan, [string]$Varsayilan)
    $degerler = @($Satirlar | ForEach-Object { [string](Get-DagitikDeger $_ $Alan '') } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($degerler.Count -eq 0) { return $Varsayilan }
    return [string](($degerler | Group-Object | Sort-Object Count -Descending | Select-Object -First 1).Name)
}

function New-GunlukOzet {
    param([string]$Tarih, [object]$Ayar)
    $csvYolu = Join-Path $HatirlaticiKlasoru ("aktivite\\$Tarih.csv")
    $satirlar = @()
    if (Test-Path -LiteralPath $csvYolu) {
        try {
            $satirlar = @(Import-Csv -LiteralPath $csvYolu -Delimiter ';' -Encoding UTF8 |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_.uygulama) })
        }
        catch { GondericiLog "CSV okunamadi ($Tarih): $($_.Exception.GetType().Name)" }
    }

    $uygulamalar = @()
    foreach ($grup in @($satirlar | Group-Object uygulama)) {
        $dakika = [math]::Round((Get-SureToplami @($grup.Group)) / 60)
        if ($dakika -le 0) { continue }
        $uygulamalar += [pscustomobject][ordered]@{
            ad = ConvertTo-DagitikSinirliMetin $grup.Name 100
            dakika = [int]$dakika
            kategori = Get-BaskinAlan @($grup.Group) 'kategori' 'diger'
            kaynak = Get-BaskinAlan @($grup.Group) 'kaynak' 'bilinmiyor'
        }
    }
    $uygulamalar = @($uygulamalar | Sort-Object dakika -Descending | Select-Object -First 80)

    $baslikDahil = ([string](Get-DagitikDeger $Ayar 'ayrintiDuzeyi' 'ozet')).ToLowerInvariant() -eq 'baslikli'
    $basliklar = @()
    if ($baslikDahil) {
        $baslikSatirlari = @($satirlar | Where-Object { -not [string]::IsNullOrWhiteSpace($_.baslik) })
        foreach ($grup in @($baslikSatirlari | Group-Object { "$($_.uygulama)`n$($_.baslik)" })) {
            $parca = $grup.Name -split "`n", 2
            $dakika = [math]::Round((Get-SureToplami @($grup.Group)) / 60)
            if ($dakika -le 0) { continue }
            $basliklar += [pscustomobject][ordered]@{
                uygulama = ConvertTo-DagitikSinirliMetin $parca[0] 100
                baslik = ConvertTo-DagitikSinirliMetin $(if ($parca.Count -gt 1) { $parca[1] } else { '' }) 160
                dakika = [int]$dakika
            }
        }
        $basliklar = @($basliklar | Sort-Object dakika -Descending | Select-Object -First 40)
    }

    $calisma = [math]::Round((Get-SureToplami @($satirlar | Where-Object { $_.kategori -eq 'calisma' })) / 60)
    $diger = [math]::Round((Get-SureToplami @($satirlar | Where-Object { $_.kategori -eq 'diger' })) / 60)
    $bosta = [math]::Round((Get-SureToplami @($satirlar | Where-Object { $_.kategori -eq 'bosta' })) / 60)
    $hedef = 240
    $hedefAyari = Read-DagitikJson $hedefYolu
    if ($null -ne $hedefAyari) { $hedef = ConvertTo-DagitikDakika (Get-DagitikDeger $hedefAyari 'hedef' 240) 1440 }
    $sonOrnek = ''
    if (Test-Path -LiteralPath $csvYolu) { $sonOrnek = (Get-Item -LiteralPath $csvYolu).LastWriteTimeUtc.ToString('o') }

    return [ordered]@{
        schemaVersion = 1
        cihazId = [string]$Ayar.cihazId
        cihazAdi = ConvertTo-DagitikSinirliMetin (Get-DagitikDeger $Ayar 'cihazAdi' $env:COMPUTERNAME) 80
        gonderildiUtc = [DateTime]::UtcNow.ToString('o')
        clientTarih = $Tarih
        zamanDilimiOfsetDk = [int][TimeZoneInfo]::Local.GetUtcOffset((Get-Date)).TotalMinutes
        sira = [int](Get-DagitikDeger $Ayar 'sira' 0)
        veriKapsami = [ordered]@{
            uygulamaOzetleri = $true
            pencereBasliklari = $baslikDahil
            alanAdlari = $false
            tamUrl = $false
            aramaTerimleri = $false
            ekranGoruntusu = $false
            tusKaydi = $false
        }
        ozet = [ordered]@{
            calismaDk = [int]$calisma
            digerDk = [int]$diger
            bostaDk = [int]$bosta
            kayitDk = [int]($calisma + $diger + $bosta)
            hedefDk = [int]$hedef
        }
        uygulamalar = @($uygulamalar)
        basliklar = @($basliklar)
        alanlar = @()
        health = [ordered]@{
            senkron = Get-CtSenkronDurumu $HatirlaticiKlasoru $Ayar
            kayitSatiri = [int]$satirlar.Count
            sonOrnekUtc = $sonOrnek
            yerelIzleyiciCalisiyor = -not [string]::IsNullOrWhiteSpace($sonOrnek)
        }
    }
}

function Set-GondericiDurumu {
    param([object]$Ayar, [string]$Durum, [string]$Hata = '')
    Set-DagitikDeger $Ayar 'sonDurum' $Durum
    Set-DagitikDeger $Ayar 'sonKontrolUtc' ([DateTime]::UtcNow.ToString('o'))
    Set-DagitikDeger $Ayar 'sonHata' (ConvertTo-DagitikSinirliMetin $Hata 180)
    try { Write-DagitikJsonAtomik -Nesne $Ayar -Yol $ayarYolu } catch { }
}

$ayar = Read-DagitikJson $ayarYolu
if ($null -eq $ayar -or -not [bool](Get-DagitikDeger $ayar 'aktif' $false)) {
    Write-Output 'Merkez gonderimi yapilandirilmamis veya devre disi.'
    exit 0
}
if (-not (Test-DagitikCihazKimligi ([string]$ayar.cihazId))) { throw 'merkez.json cihazId gecersiz.' }
if ([string]::IsNullOrWhiteSpace([string]$ayar.anahtarKorunmus)) {
    throw 'merkez.json anahtari korunmus degil. Istemci kurulumunu kayit paketiyle tekrar calistirin.'
}
$protokol = [int](Get-DagitikDeger $ayar 'protokol' 1)
$sunucuUrl = ([string](Get-DagitikDeger $ayar 'sunucuUrl' '')).Trim().TrimEnd('/')
# v2'de dogrudan adres bos olabilir (yalnizca posta kutusu)
if ($protokol -lt 2 -and $sunucuUrl -notmatch '^https?://[^/\\]+(?::\d+)?$') { throw 'merkez.json sunucuUrl gecersiz.' }

try { $anahtar = Unprotect-DagitikAnahtar -KorunmusAnahtar $ayar.anahtarKorunmus -Amac "istemci:$($ayar.cihazId)" }
catch { throw 'Merkez anahtari bu Windows kullanicisi tarafindan acilamiyor. Istemci kurulumunu bu oturumda tekrar calistirin.' }

[void][System.IO.Directory]::CreateDirectory($outboxKlasoru)
$bugun = (Get-Date).ToString('yyyy-MM-dd')
$dun = (Get-Date).Date.AddDays(-1).ToString('yyyy-MM-dd')

# Gun donumu: gunun son turundan sonraki dakikalar (en fazla 5 dk) aksi halde hic
# gonderilmezdi. Yeni gunun ilk turunda dunun kesin ozeti bir kez kuyruga alinir.
if ([string](Get-DagitikDeger $ayar 'sonKapatilanGun' '') -ne $dun -and
    (Test-Path -LiteralPath (Join-Path $HatirlaticiKlasoru ("aktivite\$dun.csv")))) {
    Set-DagitikDeger $ayar 'sira' ([int](Get-DagitikDeger $ayar 'sira' 0) + 1)
    $dunOzet = New-GunlukOzet -Tarih $dun -Ayar $ayar
    Write-DagitikJsonAtomik -Nesne $dunOzet -Yol (Join-Path $outboxKlasoru "$dun.json")
    Set-DagitikDeger $ayar 'sonKapatilanGun' $dun
    GondericiLog "Gun kapanisi kuyruga alindi: $dun"
}

Set-DagitikDeger $ayar 'sira' ([int](Get-DagitikDeger $ayar 'sira' 0) + 1)
$yeniOzet = New-GunlukOzet -Tarih $bugun -Ayar $ayar
$kuyrukYolu = Join-Path $outboxKlasoru "$bugun.json"
Write-DagitikJsonAtomik -Nesne $yeniOzet -Yol $kuyrukYolu
Set-GondericiDurumu -Ayar $ayar -Durum 'kuyrukta'

if ($SadeceKuyrugaAl) {
    Write-Output "Gunluk ozet kuyruga alindi: $kuyrukYolu"
    exit 0
}

if ($protokol -ge 2) {
    # Sifreli zarf: dogrudan adres ya da posta kutusu (Istemci-Kanal.ps1)
    $senkronPs = Join-Path $HatirlaticiKlasoru 'kural-senkron.ps1'
    if (Test-Path -LiteralPath $senkronPs) { . $senkronPs }
    . (Join-Path $PSScriptRoot 'Istemci-Kanal.ps1')
    $gonderilen = Invoke-IstemciV2Turu -Ayar $ayar -Anahtar $anahtar
    Write-DagitikJsonAtomik -Nesne $ayar -Yol $ayarYolu
    if ($gonderilen -gt 0 -and [string](Get-DagitikDeger $ayar 'sonKanal' '') -eq 'posta') { Write-Output "Posta kutusuna $gonderilen gunluk ozet birakildi." }
    elseif ($gonderilen -gt 0) { Write-Output "Merkeze $gonderilen gunluk ozet gonderildi." }
    exit 0
}

$endpoint = "$sunucuUrl/v1/ozet"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$gonderilen = 0
$dosyalar = @(Get-ChildItem -LiteralPath $outboxKlasoru -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object Name)
foreach ($dosya in $dosyalar) {
    $paket = Read-DagitikJson $dosya.FullName
    if ($null -eq $paket) { continue }
    try {
        $govde = $paket | ConvertTo-Json -Depth 10 -Compress
        $zaman = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds().ToString([Globalization.CultureInfo]::InvariantCulture)
        $imza = Get-DagitikHmac -Anahtar $anahtar -ZamanDamgasi $zaman -Govde $govde
        $basliklar = @{
            'X-CT-Cihaz' = [string]$ayar.cihazId
            'X-CT-Zaman' = $zaman
            'X-CT-Imza' = $imza
        }
        $yanit = Invoke-WebRequest -Uri $endpoint -Method Post -Headers $basliklar -ContentType 'application/json; charset=utf-8' `
            -Body $govde -UseBasicParsing -TimeoutSec 12
        if ($yanit.StatusCode -lt 200 -or $yanit.StatusCode -ge 300) { throw "HTTP $($yanit.StatusCode)" }
        Remove-Item -LiteralPath $dosya.FullName -Force
        $gonderilen++
        Set-DagitikDeger $ayar 'sonBasariliSenkronUtc' ([DateTime]::UtcNow.ToString('o'))
        Set-GondericiDurumu -Ayar $ayar -Durum 'baglandi'
    }
    catch {
        $kod = 0
        try { $kod = [int]$_.Exception.Response.StatusCode } catch { }
        $hata = Get-CtAgHatasi $_ 'Özet gönderimi'
        if ($kod -ge 400 -and $kod -lt 500) {
            [void][System.IO.Directory]::CreateDirectory($redKlasoru)
            $hedef = Join-Path $redKlasoru ("$($dosya.BaseName)-$(Get-Date -Format 'yyyyMMdd-HHmmss').json")
            Move-Item -LiteralPath $dosya.FullName -Destination $hedef -Force
            $hata = "Merkez paketi reddetti (HTTP $kod); paket reddedilen klasorune tasindi."
        }
        Set-GondericiDurumu -Ayar $ayar -Durum 'hata' -Hata $hata
        GondericiLog $hata
        break
    }
}

# Kural senkronu: once bekleyen yerel kararlar merkeze itilir, sonra ortak kume
# cekilip yerel kurallar.json ile birlestirilir. Her adim tek tek korunur;
# basarisizlik yerel takibi etkilemez.
$senkronPs = Join-Path $HatirlaticiKlasoru 'kural-senkron.ps1'
if (Test-Path -LiteralPath $senkronPs) {
    . $senkronPs
    try {
        Set-DagitikDeger $ayar 'kuralGonderimHata' ''
        $bekleyen = @(Get-KuralKuyruk -Klasor $HatirlaticiKlasoru)
        if ($bekleyen.Count -gt 0) {
            $kuralGovde = [ordered]@{
                schemaVersion = 1
                cihazId = [string]$ayar.cihazId
                kararlar = @($bekleyen | ForEach-Object {
                    [ordered]@{ oge = [string]$_.oge; tur = [string]$_.tur; karar = [string]$_.karar }
                })
            } | ConvertTo-Json -Depth 5 -Compress
            $zamanK = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds().ToString([Globalization.CultureInfo]::InvariantCulture)
            $imzaK = Get-DagitikHmac -Anahtar $anahtar -ZamanDamgasi $zamanK -Govde $kuralGovde
            $yanitK = Invoke-WebRequest -Uri "$sunucuUrl/v1/kural" -Method Post -Body $kuralGovde `
                -ContentType 'application/json; charset=utf-8' -UseBasicParsing -TimeoutSec 12 -Headers @{
                'X-CT-Cihaz' = [string]$ayar.cihazId; 'X-CT-Zaman' = $zamanK; 'X-CT-Imza' = $imzaK
            }
            $kuralCevap = $yanitK.Content | ConvertFrom-Json
            if ($null -ne $kuralCevap -and [bool](Get-DagitikDeger $kuralCevap 'ok' $false)) {
                Clear-KuralKuyruk -Klasor $HatirlaticiKlasoru
                GondericiLog "Kural kuyrugu merkeze gonderildi: $($bekleyen.Count) karar"
            }
        }
    }
    catch {
        $kod = 0
        try { $kod = [int]$_.Exception.Response.StatusCode } catch { }
        Set-DagitikDeger $ayar 'kuralGonderimHata' (Get-CtAgHatasi $_ 'Kural gönderimi')
        # 403 = bu cihazin yazma izni yok; kuyruk birikmesin
        if ($kod -eq 403) {
            Clear-KuralKuyruk -Klasor $HatirlaticiKlasoru
            GondericiLog 'Kural yazma izni yok; kuyruk temizlendi.'
        }
        else { GondericiLog "Kural kuyrugu gonderilemedi: $($_.Exception.GetType().Name)" }
    }

    try {
        $yolKural = '/v1/kurallar'
        $zamanKg = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds().ToString([Globalization.CultureInfo]::InvariantCulture)
        $imzaKg = Get-DagitikHmac -Anahtar $anahtar -ZamanDamgasi $zamanKg -Govde $yolKural
        $yanitKg = Invoke-WebRequest -Uri "$sunucuUrl$yolKural" -Method Get -UseBasicParsing -TimeoutSec 10 -Headers @{
            'X-CT-Cihaz' = [string]$ayar.cihazId; 'X-CT-Zaman' = $zamanKg; 'X-CT-Imza' = $imzaKg
        }
        $merkezKural = $yanitKg.Content | ConvertFrom-Json
        if ($null -ne $merkezKural -and [bool](Get-DagitikDeger $merkezKural 'ok' $false)) {
            Set-DagitikDeger $ayar 'kuralAlimHata' ''
            Set-DagitikDeger $ayar 'sonKuralAlimiUtc' ([DateTime]::UtcNow.ToString('o'))
            $damga = [string](Get-DagitikDeger $merkezKural 'sonDegisiklikUtc' '')
            if ($damga -ne [string](Get-DagitikDeger $ayar 'kuralSenkronUtc' '')) {
                $degisen = Merge-YerelKurallar -Klasor $HatirlaticiKlasoru -Merkez $merkezKural
                Set-DagitikDeger $ayar 'kuralSenkronUtc' $damga
                if ($degisen -gt 0) { GondericiLog "Ortak kurallar alindi: $degisen degisiklik" }
            }
        }
    }
    catch { Set-DagitikDeger $ayar 'kuralAlimHata' (Get-CtAgHatasi $_ 'Kural alımı'); GondericiLog "Ortak kurallar alinamadi: $($_.Exception.GetType().Name)" }
}

# Ortak sayac: diger cihazlarin bugunku toplami yerel dosyaya yazilir. Basarisiz
# olursa sessizce gecilir; yerel takip her kosulda calismaya devam eder.
try {
    $toplamYolu = "/v1/toplam?tarih=$((Get-Date).ToString('yyyy-MM-dd'))"
    $zamanT = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds().ToString([Globalization.CultureInfo]::InvariantCulture)
    $imzaT = Get-DagitikHmac -Anahtar $anahtar -ZamanDamgasi $zamanT -Govde $toplamYolu
    $yanitT = Invoke-WebRequest -Uri "$sunucuUrl$toplamYolu" -Method Get -UseBasicParsing -TimeoutSec 10 -Headers @{
        'X-CT-Cihaz' = [string]$ayar.cihazId
        'X-CT-Zaman' = $zamanT
        'X-CT-Imza' = $imzaT
    }
    $toplamCevap = $yanitT.Content | ConvertFrom-Json
    if ($null -ne $toplamCevap -and [bool](Get-DagitikDeger $toplamCevap 'ok' $false)) {
        Set-DagitikDeger $ayar 'ortakSayacHata' ''
        Write-DagitikJsonAtomik -Nesne ([ordered]@{
            tarih = [string](Get-DagitikDeger $toplamCevap 'tarih' '')
            digerCihazDk = [int](ConvertTo-DagitikDakika (Get-DagitikDeger $toplamCevap 'digerCihazDk' 0))
            toplamDk = [int](ConvertTo-DagitikDakika (Get-DagitikDeger $toplamCevap 'toplamDk' 0))
            cihazSayisi = [int](Get-DagitikDeger $toplamCevap 'cihazSayisi' 0)
            cihazlar = @(Get-DagitikDeger $toplamCevap 'cihazlar' @())
            guncellemeUtc = [DateTime]::UtcNow.ToString('o')
        }) -Yol (Join-Path $HatirlaticiKlasoru 'ortak-sayac.json')
    }
}
catch { Set-DagitikDeger $ayar 'ortakSayacHata' (Get-CtAgHatasi $_ 'Ortak sayaç'); GondericiLog "Ortak sayac alinamadi: $($_.Exception.GetType().Name)" }

Write-DagitikJsonAtomik -Nesne $ayar -Yol $ayarYolu
if ($gonderilen -gt 0) { Write-Output "Merkeze $gonderilen gunluk ozet gonderildi." }
elseif ($dosyalar.Count -eq 0) { Write-Output 'Gonderilecek ozet yok.' }
