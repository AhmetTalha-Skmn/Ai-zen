<#
Aizen posta kutusu sunucusu (relay).

Merkez bilgisayari ile calisan bilgisayarlar farkli aglardayken aradaki "posta kutusu"dur:
cihazlar sifreli zarflarini buraya birakir, merkez acik oldugunda alir ve yanitlarini
birakir, cihazlar bir sonraki turda yanitlari alir. Sunucu zarflarin icerigini okuyamaz
ve degistiremez (uyumluluk/PROTOKOL-V2.md); yalnizca jetonlarin SHA-256 ozetlerini saklar.

Calisma: Linux VPS'te PowerShell 7 (pwsh), onunde HTTPS icin ters vekil (ornegin Caddy).
Windows PowerShell 5.1'de de calisir (testler). Kurulum rehberi: posta-sunucusu/README.md

  pwsh posta-sunucu.ps1 -VeriKlasoru /var/lib/aizen-posta -YonetimJetonuUret   # bir kez
  pwsh posta-sunucu.ps1 -VeriKlasoru /var/lib/aizen-posta -Dinle 127.0.0.1 -Port 8790
#>
param(
    [string]$VeriKlasoru,
    [string]$Dinle = '127.0.0.1',
    [int]$Port = 8790,
    # Yeni yonetim jetonu uretir, ozetini kaydeder, jetonu bir kez yazar ve cikar
    [switch]$YonetimJetonuUret,
    # Testler icin: bu kadar istekten / saniyeden sonra kapanir (0 = surekli)
    [int]$IstekSayisi = 0,
    [int]$CalismaSuresiSn = 0
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2

if ([string]::IsNullOrWhiteSpace($VeriKlasoru)) { $VeriKlasoru = Join-Path $PSScriptRoot 'veri' }
$VeriKlasoru = [IO.Path]::GetFullPath($VeriKlasoru)
[void][IO.Directory]::CreateDirectory($VeriKlasoru)
$ayarYolu = Join-Path $VeriKlasoru 'ayar.json'
$kutularKlasoru = Join-Path $VeriKlasoru 'kutular'
$logYolu = Join-Path $VeriKlasoru 'posta.log'

$script:EN_BUYUK_GOVDE = 1572864        # 1.5 MB (zarf + JSON zarfi)
$script:EN_BUYUK_YANIT = 4194304        # tek yanitta en fazla 4 MB mesaj
$script:CIHAZ_BASINA_MESAJ = 200
$script:KUTU_BASINA_MESAJ = 20000
$script:SAKLAMA_GUN = 30

function PostaLog {
    param([string]$Mesaj)
    $satir = "$([DateTime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss'))Z [posta] $Mesaj"
    try { [IO.File]::AppendAllText($logYolu, $satir + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false))) } catch { }
    Write-Output $satir
}

function Get-Unix { return [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }

function Get-Ozet {
    param([string]$Metin)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Metin)))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Test-SabitEsit {
    param([string]$A, [string]$B)
    if ([string]::IsNullOrEmpty($A) -or [string]::IsNullOrEmpty($B) -or $A.Length -ne $B.Length) { return $false }
    [int]$fark = 0
    for ($i = 0; $i -lt $A.Length; $i++) { $fark = $fark -bor ([int][char]$A[$i] -bxor [int][char]$B[$i]) }
    return ($fark -eq 0)
}

function Get-Deger {
    param([object]$Nesne, [string]$Ad, [object]$Varsayilan = $null)
    if ($null -eq $Nesne -or $Nesne -is [string] -or $Nesne -is [ValueType]) { return $Varsayilan }
    if ($Nesne -is [Collections.IDictionary]) { if ($Nesne.Contains($Ad)) { return $Nesne[$Ad] }; return $Varsayilan }
    $alan = $Nesne.PSObject.Properties[$Ad]
    if ($null -eq $alan -or $null -eq $alan.Value) { return $Varsayilan }
    return $alan.Value
}

function Read-Json {
    param([string]$Yol)
    if (-not (Test-Path -LiteralPath $Yol)) { return $null }
    try {
        $ham = [IO.File]::ReadAllText($Yol, [Text.Encoding]::UTF8)
        if ([string]::IsNullOrWhiteSpace($ham)) { return $null }
        return ($ham | ConvertFrom-Json)
    }
    catch { return $null }
}

function Write-Atomik {
    param([string]$Yol, [string]$Metin)
    $klasor = Split-Path -Parent $Yol
    [void][IO.Directory]::CreateDirectory($klasor)
    $gecici = Join-Path $klasor ('.' + [IO.Path]::GetRandomFileName() + '.tmp')
    try {
        [IO.File]::WriteAllText($gecici, $Metin, (New-Object Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $gecici -Destination $Yol -Force
    }
    finally { if (Test-Path -LiteralPath $gecici) { Remove-Item -LiteralPath $gecici -Force -ErrorAction SilentlyContinue } }
}

function New-Jeton {
    $bayt = New-Object byte[] 32
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bayt) } finally { $rng.Dispose() }
    return ([Convert]::ToBase64String($bayt)).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

if ($YonetimJetonuUret) {
    $jeton = New-Jeton
    Write-Atomik $ayarYolu (([ordered]@{ surum = 1; yonetimJetonuOzeti = (Get-Ozet $jeton); uretildi = (Get-Unix) }) | ConvertTo-Json -Compress)
    Write-Output 'Yonetim jetonu (yalnizca simdi gosterilir; merkez bilgisayarinda posta-baglan.ps1 ister):'
    Write-Output $jeton
    exit 0
}

# ---------- HTTP yardimcilari ----------

function Write-Yanit {
    param([Net.HttpListenerContext]$Baglam, [int]$Kod, [object]$Nesne, [string]$HamJson)
    try {
        $json = $(if ($PSBoundParameters.ContainsKey('HamJson')) { $HamJson } else { $Nesne | ConvertTo-Json -Depth 6 -Compress })
        $baytlar = [Text.Encoding]::UTF8.GetBytes($json)
        $Baglam.Response.StatusCode = $Kod
        $Baglam.Response.ContentType = 'application/json; charset=utf-8'
        try { $Baglam.Response.AddHeader('Cache-Control', 'no-store') } catch { }
        $Baglam.Response.ContentLength64 = $baytlar.Length
        $Baglam.Response.OutputStream.Write($baytlar, 0, $baytlar.Length)
    }
    catch { }
    finally { try { $Baglam.Response.Close() } catch { } }
}

function Write-Hata {
    param([Net.HttpListenerContext]$Baglam, [int]$Kod, [string]$Metin)
    Write-Yanit $Baglam $Kod ([ordered]@{ ok = $false; hata = $Metin })
}

function Read-Govde {
    # Content-Length olmasa da (parcali aktarim) en fazla EN_BUYUK_GOVDE bayt okunur.
    param([Net.HttpListenerRequest]$Istek)
    if ($Istek.ContentLength64 -gt $script:EN_BUYUK_GOVDE) { throw 'buyuk' }
    $akim = New-Object IO.MemoryStream
    try {
        $tampon = New-Object byte[] 65536
        while ($true) {
            $okunan = $Istek.InputStream.Read($tampon, 0, $tampon.Length)
            if ($okunan -le 0) { break }
            if (($akim.Length + $okunan) -gt $script:EN_BUYUK_GOVDE) { throw 'buyuk' }
            $akim.Write($tampon, 0, $okunan)
        }
        return (New-Object Text.UTF8Encoding($false, $true)).GetString($akim.ToArray())
    }
    finally { $akim.Dispose() }
}

function Get-IstemciAdresi {
    param([Net.HttpListenerContext]$Baglam)
    $adres = ''
    try { $adres = [string]$Baglam.Request.RemoteEndPoint.Address } catch { }
    # Ters vekil ayni makinedeyse gercek adres X-Forwarded-For'un son ogesidir
    if ($adres -in @('127.0.0.1', '::1', '::ffff:127.0.0.1')) {
        $xff = [string]$Baglam.Request.Headers['X-Forwarded-For']
        if ($xff) { $adres = ($xff.Split(',')[-1]).Trim() }
    }
    return $adres
}

$script:IpHatalari = @{}
function Test-IpSiniri {
    param([string]$Adres)
    $kayit = $script:IpHatalari[$Adres]
    if ($null -eq $kayit) { return $true }
    if (((Get-Unix) - $kayit.pencere) -gt 600) { $script:IpHatalari.Remove($Adres); return $true }
    return ($kayit.sayi -lt 60)
}

function Add-IpHatasi {
    param([string]$Adres)
    $simdi = Get-Unix
    if ($script:IpHatalari.Count -gt 5000) { $script:IpHatalari.Clear() }
    $kayit = $script:IpHatalari[$Adres]
    if ($null -eq $kayit -or ($simdi - $kayit.pencere) -gt 600) { $script:IpHatalari[$Adres] = @{ pencere = $simdi; sayi = 1 } }
    else { $kayit.sayi++ }
}

# ---------- kutu verisi ----------

function Test-KutuKimligi { param([string]$Kutu) return ($Kutu -cmatch '^[0-9a-f]{16,64}$') }
function Test-CihazKimligi { param([string]$Cihaz) return ($Cihaz -cmatch '^[A-Za-z0-9_-]{3,64}$') }
function Test-BirlestirmeAnahtari { param([string]$Anahtar) return ($Anahtar -cmatch '^[a-z0-9-]{0,40}$') }

function Get-KutuKlasoru { param([string]$Kutu) return (Join-Path $kutularKlasoru $Kutu) }

function Read-Kutu {
    param([string]$Kutu)
    if (-not (Test-KutuKimligi $Kutu)) { return $null }
    return (Read-Json (Join-Path (Get-KutuKlasoru $Kutu) 'kutu.json'))
}

function Get-YeniNo {
    param([string]$Kutu)
    $yol = Join-Path (Get-KutuKlasoru $Kutu) 'no.txt'
    [long]$no = 0
    if (Test-Path -LiteralPath $yol) { [void][long]::TryParse(([IO.File]::ReadAllText($yol)).Trim(), [ref]$no) }
    $no++
    Write-Atomik $yol ([string]$no)
    return $no
}

function Test-ZarfKabaBicimi {
    # Icerik dogrulamasi merkezde ve cihazda yapilir; burada yalnizca tasinacak bicim denetlenir.
    param([object]$Zarf, [string]$Cihaz, [string]$Yon)
    if ($null -eq $Zarf -or $Zarf -is [string] -or $Zarf -is [ValueType] -or $Zarf -is [Array]) { return $false }
    if ([string](Get-Deger $Zarf 'v' '') -ne '2') { return $false }
    if ([string](Get-Deger $Zarf 'cihaz' '') -cne $Cihaz) { return $false }
    if ([string](Get-Deger $Zarf 'yon' '') -cne $Yon) { return $false }
    if ([string](Get-Deger $Zarf 'tur' '') -cnotmatch '^[a-z]{2,16}$') { return $false }
    foreach ($alan in @('iv', 'veri', 'etiket')) {
        $deger = Get-Deger $Zarf $alan $null
        if (-not ($deger -is [string]) -or $deger -cnotmatch '^[A-Za-z0-9+/]+={0,2}$') { return $false }
    }
    foreach ($alan in @('sayac', 'zaman')) {
        if ([string](Get-Deger $Zarf $alan '') -cnotmatch '^[0-9]{1,15}$') { return $false }
    }
    return $true
}

function Get-Mesajlar {
    # Klasordeki mesaj dosyalari, eskiden yeniye: <no 16 hane>~...json
    param([string]$Klasor)
    if (-not (Test-Path -LiteralPath $Klasor)) { return @() }
    return @(Get-ChildItem -LiteralPath $Klasor -File -Filter '*.json' | Where-Object { $_.Name -cmatch '^[0-9]{16}~' } | Sort-Object Name)
}

function Save-Mesaj {
    # Ayni birlestirme anahtarli bekleyen mesaj yenisiyle degisir (bos anahtar birlestirilmez).
    param([string]$Kutu, [string]$Klasor, [string]$AdEki, [string]$BirlestirmeEki, [object]$Kayit)
    [void][IO.Directory]::CreateDirectory($Klasor)
    if ($BirlestirmeEki) {
        foreach ($eski in @(Get-Mesajlar $Klasor | Where-Object { $_.Name.Substring(16) -ceq "~$BirlestirmeEki.json" })) {
            Remove-Item -LiteralPath $eski.FullName -Force -ErrorAction SilentlyContinue
        }
    }
    $no = Get-YeniNo $Kutu
    $Kayit['no'] = $no
    $ad = ('{0:D16}~{1}.json' -f $no, $AdEki)
    Write-Atomik (Join-Path $Klasor $ad) ($Kayit | ConvertTo-Json -Depth 6 -Compress)
    return $no
}

function Get-MesajYaniti {
    param([string]$Klasor, [int]$EnFazla)
    $parcalar = New-Object Collections.Generic.List[string]
    $boyut = 0
    foreach ($dosya in (Get-Mesajlar $Klasor | Select-Object -First $EnFazla)) {
        try { $metin = [IO.File]::ReadAllText($dosya.FullName, [Text.Encoding]::UTF8).Trim() } catch { continue }
        if (-not $metin.StartsWith('{')) { continue }
        if ($parcalar.Count -gt 0 -and ($boyut + $metin.Length) -gt $script:EN_BUYUK_YANIT) { break }
        $parcalar.Add($metin)
        $boyut += $metin.Length
    }
    return ('{"ok":true,"mesajlar":[' + ($parcalar -join ',') + ']}')
}

function Remove-Mesajlar {
    param([string]$Klasor, [object[]]$Nolar)
    $istenen = @{}
    foreach ($n in @($Nolar | Select-Object -First 500)) {
        [long]$sayi = 0
        if ([long]::TryParse([string]$n, [ref]$sayi) -and $sayi -gt 0) { $istenen[('{0:D16}' -f $sayi)] = $true }
    }
    $silinen = 0
    foreach ($dosya in (Get-Mesajlar $Klasor)) {
        if ($istenen.ContainsKey($dosya.Name.Substring(0, 16))) {
            Remove-Item -LiteralPath $dosya.FullName -Force -ErrorAction SilentlyContinue
            $silinen++
        }
    }
    return $silinen
}

function Get-CihazKaydi {
    param([object]$KutuVerisi, [string]$Cihaz)
    $simdi = Get-Unix
    foreach ($c in @(Get-Deger $KutuVerisi 'cihazlar' @())) {
        if ([string](Get-Deger $c 'cihaz' '') -cne $Cihaz) { continue }
        [long]$bitis = 0
        [void][long]::TryParse([string](Get-Deger $c 'bitis' 0), [ref]$bitis)
        if ($bitis -gt 0 -and $bitis -lt $simdi) { return $null }
        return $c
    }
    return $null
}

$script:SonTemizlik = 0
function Invoke-Temizlik {
    $simdi = Get-Unix
    if (($simdi - $script:SonTemizlik) -lt 3600) { return }
    $script:SonTemizlik = $simdi
    if (-not (Test-Path -LiteralPath $kutularKlasoru)) { return }
    $sinir = [DateTime]::UtcNow.AddDays(-$script:SAKLAMA_GUN)
    $silinen = 0
    foreach ($dosya in @(Get-ChildItem -LiteralPath $kutularKlasoru -Recurse -File -Filter '*.json' | Where-Object { $_.Name -cmatch '^[0-9]{16}~' -and $_.LastWriteTimeUtc -lt $sinir })) {
        Remove-Item -LiteralPath $dosya.FullName -Force -ErrorAction SilentlyContinue
        $silinen++
    }
    if ($silinen -gt 0) { PostaLog "Saklama suresi dolan $silinen mesaj silindi." }
}

# ---------- uc noktalar ----------

function Invoke-KutuOlustur {
    param([Net.HttpListenerContext]$Baglam, [string]$Govde, [string]$Adres)
    $ayar = Read-Json $ayarYolu
    $beklenen = [string](Get-Deger $ayar 'yonetimJetonuOzeti' '')
    $jeton = [string]$Baglam.Request.Headers['X-Aizen-Yonetim']
    if (-not $beklenen -or $jeton -cnotmatch '^[A-Za-z0-9_-]{32,128}$' -or -not (Test-SabitEsit (Get-Ozet $jeton) $beklenen)) {
        Add-IpHatasi $Adres
        Write-Hata $Baglam 401 'Yonetim jetonu gecersiz.'
        return
    }
    $istek = $null
    try { $istek = $Govde | ConvertFrom-Json } catch { }
    $kutu = [string](Get-Deger $istek 'kutu' '')
    $merkezOzeti = [string](Get-Deger $istek 'merkezJetonOzeti' '')
    if (-not (Test-KutuKimligi $kutu) -or $merkezOzeti -cnotmatch '^[0-9a-f]{64}$') { Write-Hata $Baglam 400 'Kutu bilgisi gecersiz.'; return }
    $mevcut = Read-Kutu $kutu
    $kayit = [ordered]@{
        surum = 1
        merkezJetonOzeti = $merkezOzeti
        cihazlar = @($(if ($null -ne $mevcut) { @(Get-Deger $mevcut 'cihazlar' @()) } else { @() }))
        olusturuldu = $(if ($null -ne $mevcut) { Get-Deger $mevcut 'olusturuldu' (Get-Unix) } else { Get-Unix })
        guncellendi = (Get-Unix)
    }
    Write-Atomik (Join-Path (Get-KutuKlasoru $kutu) 'kutu.json') ($kayit | ConvertTo-Json -Depth 5 -Compress)
    PostaLog $(if ($null -ne $mevcut) { "Kutu jetonu yenilendi: $kutu" } else { "Kutu olusturuldu: $kutu" })
    Write-Yanit $Baglam 200 ([ordered]@{ ok = $true; kutu = $kutu })
}

function Invoke-MerkezIstegi {
    param([Net.HttpListenerContext]$Baglam, [string]$Yol, [string]$Govde, [string]$Adres)
    $kutu = [string]$Baglam.Request.Headers['X-Aizen-Kutu']
    $jeton = [string]$Baglam.Request.Headers['X-Aizen-Jeton']
    $veri = Read-Kutu $kutu
    if ($null -eq $veri -or $jeton -cnotmatch '^[0-9a-f]{64}$' -or -not (Test-SabitEsit (Get-Ozet $jeton) ([string](Get-Deger $veri 'merkezJetonOzeti' '')))) {
        Add-IpHatasi $Adres
        Write-Hata $Baglam 401 'Kimlik dogrulanamadi.'
        return
    }
    $klasor = Get-KutuKlasoru $kutu
    $merkezeKlasoru = Join-Path $klasor 'merkeze'
    $istek = $null
    if ($Govde) { try { $istek = $Govde | ConvertFrom-Json } catch { Write-Hata $Baglam 400 'JSON okunamadi.'; return } }

    switch -CaseSensitive ($Yol) {
        '/r1/merkez/gelen' {
            [int]$en = 25
            [void][int]::TryParse([string]$Baglam.Request.QueryString['en'], [ref]$en)
            if ($en -lt 1) { $en = 1 }
            if ($en -gt 100) { $en = 100 }
            Write-Yanit $Baglam 200 -HamJson (Get-MesajYaniti $merkezeKlasoru $en)
        }
        '/r1/merkez/onay' {
            $silinen = Remove-Mesajlar $merkezeKlasoru @(Get-Deger $istek 'nolar' @())
            Write-Yanit $Baglam 200 ([ordered]@{ ok = $true; silinen = $silinen })
        }
        '/r1/merkez/cihazlar' {
            $liste = @(Get-Deger $istek 'cihazlar' $null)
            if ($null -eq (Get-Deger $istek 'cihazlar' $null) -or $liste.Count -gt 5000) { Write-Hata $Baglam 400 'Cihaz listesi gecersiz.'; return }
            $temiz = @()
            foreach ($c in $liste) {
                $id = [string](Get-Deger $c 'cihaz' '')
                $ozet = [string](Get-Deger $c 'jetonOzeti' '')
                [long]$bitis = 0
                [void][long]::TryParse([string](Get-Deger $c 'bitis' 0), [ref]$bitis)
                if (-not (Test-CihazKimligi $id) -or $ozet -cnotmatch '^[0-9a-f]{64}$') { Write-Hata $Baglam 400 'Cihaz listesi gecersiz.'; return }
                $temiz += [ordered]@{ cihaz = $id; jetonOzeti = $ozet; bitis = $bitis }
            }
            $kayit = [ordered]@{
                surum = 1
                merkezJetonOzeti = [string](Get-Deger $veri 'merkezJetonOzeti' '')
                cihazlar = @($temiz)
                olusturuldu = (Get-Deger $veri 'olusturuldu' (Get-Unix))
                guncellendi = (Get-Unix)
            }
            Write-Atomik (Join-Path $klasor 'kutu.json') ($kayit | ConvertTo-Json -Depth 5 -Compress)
            Write-Yanit $Baglam 200 ([ordered]@{ ok = $true; cihazSayisi = $temiz.Count })
        }
        '/r1/merkez/gonder' {
            $mesajlar = @(Get-Deger $istek 'mesajlar' @())
            if ($mesajlar.Count -gt 200) { Write-Hata $Baglam 413 'Tek seferde en fazla 200 mesaj.'; return }
            $kaydedilen = 0
            $atlanan = 0
            foreach ($m in $mesajlar) {
                $cihaz = [string](Get-Deger $m 'cihaz' '')
                $anahtar = [string](Get-Deger $m 'anahtar' '')
                $zarf = Get-Deger $m 'zarf' $null
                if (-not (Test-CihazKimligi $cihaz) -or -not (Test-BirlestirmeAnahtari $anahtar) -or
                    -not (Test-ZarfKabaBicimi $zarf $cihaz 'yanit') -or $null -eq (Get-CihazKaydi $veri $cihaz)) { $atlanan++; continue }
                $cihazKlasoru = Join-Path (Join-Path $klasor 'cihaza') $cihaz
                [void](Save-Mesaj $kutu $cihazKlasoru $anahtar $anahtar ([ordered]@{ no = 0; anahtar = $anahtar; alindi = (Get-Unix); zarf = $zarf }))
                # Cihaz uzun sure kapaliysa en eski yanitlar dusurulur
                $fazla = @(Get-Mesajlar $cihazKlasoru)
                if ($fazla.Count -gt $script:CIHAZ_BASINA_MESAJ) {
                    foreach ($eski in ($fazla | Select-Object -First ($fazla.Count - $script:CIHAZ_BASINA_MESAJ))) { Remove-Item -LiteralPath $eski.FullName -Force -ErrorAction SilentlyContinue }
                }
                $kaydedilen++
            }
            Write-Yanit $Baglam 200 ([ordered]@{ ok = $true; kaydedilen = $kaydedilen; atlanan = $atlanan })
        }
        default { Write-Hata $Baglam 404 'Bulunamadi.' }
    }
}

function Invoke-CihazIstegi {
    param([Net.HttpListenerContext]$Baglam, [string]$Yol, [string]$Govde, [string]$Adres)
    $kutu = [string]$Baglam.Request.Headers['X-Aizen-Kutu']
    $cihaz = [string]$Baglam.Request.Headers['X-Aizen-Cihaz']
    $jeton = [string]$Baglam.Request.Headers['X-Aizen-Jeton']
    $veri = Read-Kutu $kutu
    $kayit = $null
    if ($null -ne $veri -and (Test-CihazKimligi $cihaz)) { $kayit = Get-CihazKaydi $veri $cihaz }
    if ($null -eq $kayit -or $jeton -cnotmatch '^[0-9a-f]{64}$' -or -not (Test-SabitEsit (Get-Ozet $jeton) ([string](Get-Deger $kayit 'jetonOzeti' '')))) {
        Add-IpHatasi $Adres
        Write-Hata $Baglam 401 'Kimlik dogrulanamadi.'
        return
    }
    $klasor = Get-KutuKlasoru $kutu
    $cihazKlasoru = Join-Path (Join-Path $klasor 'cihaza') $cihaz
    $istek = $null
    if ($Govde) { try { $istek = $Govde | ConvertFrom-Json } catch { Write-Hata $Baglam 400 'JSON okunamadi.'; return } }

    switch -CaseSensitive ($Yol) {
        '/r1/cihaz/gonder' {
            $anahtar = [string](Get-Deger $istek 'anahtar' '')
            $zarf = Get-Deger $istek 'zarf' $null
            if (-not (Test-BirlestirmeAnahtari $anahtar) -or -not (Test-ZarfKabaBicimi $zarf $cihaz 'istek')) { Write-Hata $Baglam 400 'Zarf bicimi gecersiz.'; return }
            $merkezeKlasoru = Join-Path $klasor 'merkeze'
            $mevcut = @(Get-Mesajlar $merkezeKlasoru)
            $bu = @($mevcut | Where-Object { $_.Name.Substring(16).StartsWith("~$cihaz~", [StringComparison]::Ordinal) })
            $degisecek = $(if ($anahtar) { @($bu | Where-Object { $_.Name.Substring(16) -ceq "~$cihaz~$anahtar.json" }).Count } else { 0 })
            if (($bu.Count - $degisecek) -ge $script:CIHAZ_BASINA_MESAJ -or ($mevcut.Count - $degisecek) -ge $script:KUTU_BASINA_MESAJ) {
                Write-Hata $Baglam 429 'Posta kutusu dolu; merkez mesajlari aldiktan sonra tekrar deneyin.'
                return
            }
            $birlestirme = $(if ($anahtar) { "$cihaz~$anahtar" } else { '' })
            $no = Save-Mesaj $kutu $merkezeKlasoru "$cihaz~$anahtar" $birlestirme ([ordered]@{ no = 0; cihaz = $cihaz; anahtar = $anahtar; alindi = (Get-Unix); zarf = $zarf })
            Write-Yanit $Baglam 200 ([ordered]@{ ok = $true; no = $no })
        }
        '/r1/cihaz/gelen' {
            Write-Yanit $Baglam 200 -HamJson (Get-MesajYaniti $cihazKlasoru 50)
        }
        '/r1/cihaz/onay' {
            $silinen = Remove-Mesajlar $cihazKlasoru @(Get-Deger $istek 'nolar' @())
            Write-Yanit $Baglam 200 ([ordered]@{ ok = $true; silinen = $silinen })
        }
        default { Write-Hata $Baglam 404 'Bulunamadi.' }
    }
}

# ---------- ana dongu ----------

if ($Port -lt 1 -or $Port -gt 65535) { throw 'Port gecersiz.' }
if ($Dinle -cnotmatch '^([0-9.]+|\+|\*|localhost|\[[0-9a-fA-F:]+\])$') { throw 'Dinle adresi gecersiz.' }
if (-not (Test-Path -LiteralPath $ayarYolu)) {
    PostaLog 'Uyari: yonetim jetonu yok; kutu olusturulamaz. -YonetimJetonuUret ile bir kez uretin.'
}
[void][IO.Directory]::CreateDirectory($kutularKlasoru)

$onEk = "http://$($Dinle):$Port/"
$dinleyici = New-Object Net.HttpListener
$dinleyici.Prefixes.Add($onEk)
$baslangic = Get-Unix
$islenen = 0
try {
    $dinleyici.Start()
    PostaLog "Posta kutusu dinliyor: $onEk"
    while ($dinleyici.IsListening) {
        $bekleyen = $dinleyici.BeginGetContext($null, $null)
        $sureDoldu = $false
        while (-not $bekleyen.AsyncWaitHandle.WaitOne(1000)) {
            if ($CalismaSuresiSn -gt 0 -and ((Get-Unix) - $baslangic) -ge $CalismaSuresiSn) { $sureDoldu = $true; break }
            try { Invoke-Temizlik } catch { }
        }
        if ($sureDoldu) { break }
        $baglam = $dinleyici.EndGetContext($bekleyen)
        $islenen++
        try {
            $yol = $baglam.Request.Url.AbsolutePath
            $yontem = $baglam.Request.HttpMethod
            $adres = Get-IstemciAdresi $baglam
            if ($yontem -eq 'GET' -and ($yol -eq '/saglik' -or $yol -eq '/health')) {
                Write-Yanit $baglam 200 ([ordered]@{ ok = $true; hizmet = 'aizen-posta'; surum = 1; zaman = (Get-Unix) })
            }
            elseif (-not (Test-IpSiniri $adres)) {
                Write-Hata $baglam 429 'Cok fazla hatali deneme. 10 dakika sonra tekrar deneyin.'
            }
            else {
                $govde = ''
                if ($yontem -eq 'POST') {
                    try { $govde = Read-Govde $baglam.Request }
                    catch { Write-Hata $baglam 413 'Istek cok buyuk veya okunamadi.'; continue }
                }
                elseif ($yontem -ne 'GET') { Write-Hata $baglam 405 'Yontem desteklenmiyor.'; continue }

                if ($yontem -eq 'POST' -and $yol -ceq '/r1/kutu') { Invoke-KutuOlustur $baglam $govde $adres }
                elseif ($yol.StartsWith('/r1/merkez/', [StringComparison]::Ordinal) -and
                    (($yontem -eq 'GET' -and $yol -ceq '/r1/merkez/gelen') -or ($yontem -eq 'POST' -and $yol -cne '/r1/merkez/gelen'))) {
                    Invoke-MerkezIstegi $baglam $yol $govde $adres
                }
                elseif ($yol.StartsWith('/r1/cihaz/', [StringComparison]::Ordinal) -and
                    (($yontem -eq 'GET' -and $yol -ceq '/r1/cihaz/gelen') -or ($yontem -eq 'POST' -and $yol -cne '/r1/cihaz/gelen'))) {
                    Invoke-CihazIstegi $baglam $yol $govde $adres
                }
                else { Write-Hata $baglam 404 'Bulunamadi.' }
            }
        }
        catch {
            PostaLog "Istek islenemedi: $($_.Exception.GetType().Name)"
            try { Write-Hata $baglam 500 'Sunucu istegi tamamlayamadi.' } catch { }
        }
        if ($IstekSayisi -gt 0 -and $islenen -ge $IstekSayisi) { break }
    }
}
finally {
    try { if ($dinleyici.IsListening) { $dinleyici.Stop() } } catch { }
    try { $dinleyici.Close() } catch { }
}
