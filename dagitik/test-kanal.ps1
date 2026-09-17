# Protokol v2 (sifreli zarf), dogrudan kayit/gonderim ve posta kutusu uzerinden uctan uca testler.
# test-dagitik.ps1 tarafindan ayni sayaclarla calistirilir; bagimsiz calistirildiginda bagimliliklari yukler.
# Gercek yapilandirma, gorev veya ag duvarina dokunmaz; sunucular 127.0.0.1 uzerinde gecici klasorlerle calisir.
$script:bagimsizKanal = $false
if (-not (Get-Command 'Test-Esit' -ErrorAction SilentlyContinue)) {
    $script:bagimsizKanal = $true
    $script:gecen = 0; $script:kalan = 0
    function Test-Esit { param([string]$Ad, [object]$Beklenen, [object]$Gercek) if ($Beklenen -ceq $Gercek) { $script:gecen++; Write-Output "  OK  $Ad" } else { $script:kalan++; Write-Output "  HATA  $Ad | beklenen=[$Beklenen] gercek=[$Gercek]" } }
    function Test-Dogru { param([string]$Ad, [bool]$Kosul) if ($Kosul) { $script:gecen++; Write-Output "  OK  $Ad" } else { $script:kalan++; Write-Output "  HATA  $Ad" } }
    function Remove-TestKlasoru { param([string]$Yol) $temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'; $tam = [IO.Path]::GetFullPath($Yol); if ($tam.StartsWith($temp, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $tam)) { Remove-Item -LiteralPath $tam -Recurse -Force } }
}
if (-not (Get-Command 'New-DagitikZarf' -ErrorAction SilentlyContinue)) { . (Join-Path $PSScriptRoot 'Ortak.ps1') }
$kanalPsExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

function Invoke-KanalHttp {
    param([string]$Uri, [string]$Yontem = 'GET', [hashtable]$Basliklar = @{}, [string]$Govde)
    $p = @{ Uri = $Uri; Method = $Yontem; Headers = $Basliklar; UseBasicParsing = $true; TimeoutSec = 20 }
    if ($PSBoundParameters.ContainsKey('Govde')) { $p.Body = [Text.Encoding]::UTF8.GetBytes($Govde); $p.ContentType = 'application/json; charset=utf-8' }
    try {
        $y = Invoke-WebRequest @p
        $icerik = $y.Content
        if ($icerik -is [byte[]]) { $icerik = [Text.Encoding]::UTF8.GetString($icerik) }
        $json = $null
        try { $json = $icerik | ConvertFrom-Json } catch { }
        return [pscustomobject]@{ Kod = [int]$y.StatusCode; Json = $json; Metin = [string]$icerik }
    }
    catch {
        $kod = 0
        try { $kod = [int]$_.Exception.Response.StatusCode } catch { }
        return [pscustomobject]@{ Kod = $kod; Json = $null; Metin = '' }
    }
}

function Start-KanalSureci {
    param([string]$Betik, [string[]]$Arguman, [string]$Kok, [string]$Ad)
    $liste = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$Betik`"") + $Arguman
    return (Start-Process -FilePath $kanalPsExe -ArgumentList $liste -PassThru `
        -RedirectStandardOutput (Join-Path $Kok "$Ad.stdout") -RedirectStandardError (Join-Path $Kok "$Ad.stderr"))
}

function Wait-KanalSaglik {
    param([string]$Url, [int]$Deneme = 60)
    for ($i = 0; $i -lt $Deneme; $i++) {
        $r = Invoke-KanalHttp $Url
        if ($r.Kod -eq 200) { return $r }
        Start-Sleep -Milliseconds 250
    }
    return $null
}

function Invoke-KanalBetik {
    # Beklenen hatalar stderr'e yazar; EAP Stop iken testi dusurmesin
    param([string]$Betik, [object[]]$Arguman)
    $eskiEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $cikti = @(& $kanalPsExe -NoProfile -ExecutionPolicy Bypass -File $Betik @Arguman 2>&1 | ForEach-Object { [string]$_ })
        return [pscustomobject]@{ Kod = $LASTEXITCODE; Metin = ($cikti -join "`n"); Satirlar = $cikti }
    }
    finally { $ErrorActionPreference = $eskiEap }
}

function Stop-KanalSureci {
    param([object]$Surec)
    if ($null -ne $Surec -and -not $Surec.HasExited) { try { $Surec.Kill(); $Surec.WaitForExit(5000) | Out-Null } catch { } }
}

function Write-KanalTestCsv {
    param([string]$Hatirlatici)
    [void][IO.Directory]::CreateDirectory((Join-Path $Hatirlatici 'aktivite'))
    Write-DagitikJsonAtomik -Nesne ([ordered]@{ hedef = 200 }) -Yol (Join-Path $Hatirlatici 'ayarlar.json')
    $csv = @(
        'zaman;uygulama;baslik;bosta;kategori;sure;kaynak',
        '10:00:00;Code;Gizli Proje Basligi;0;calisma;180;izinli',
        '10:05:00;Chrome;Site;0;diger;60;yasakli'
    ) -join [Environment]::NewLine
    [IO.File]::WriteAllText((Join-Path $Hatirlatici ("aktivite\" + (Get-Date -Format 'yyyy-MM-dd') + '.csv')), $csv, (New-Object Text.UTF8Encoding($true)))
}

function Get-KanalKodu {
    param([string[]]$Satirlar, [string]$Ad)
    $satir = @($Satirlar | Where-Object { $_ -match ('^' + [regex]::Escape($Ad) + '\s') } | Select-Object -First 1)[0]
    if (-not $satir) { return '' }
    return @([regex]::Split($satir.Trim(), '\s+'))[-1]
}

Write-Output '=== Protokol v2: sifreli zarf ==='
try {
    $zAnahtar = New-DagitikAnahtar
    $zk = Get-DagitikZarfAnahtarlari $zAnahtar
    Test-Esit 'Alt anahtar uzunlugu' 32 $zk.sifre.Length
    Test-Dogru 'Sifre ve imza anahtarlari farkli' (-not (Test-DagitikBaytEsitlik $zk.sifre $zk.imza))
    Test-Dogru 'Posta jetonu 64 hex' ($zk.postaJetonu -cmatch '^[0-9a-f]{64}$')
    $zMetin = '{"ad":"' + [char]0x00C7 + 'al' + [char]0x0131 + [char]0x015F + 'ma","gizli":"Gizli Proje"}'
    $zJson = ConvertTo-DagitikZarfJson (New-DagitikZarf -Anahtarlar $zk -Cihaz 'test-pc' -Tur 'ozet' -Sayac 7 -Metin $zMetin)
    Test-Esit 'Zarf gidis-donus (UTF-8)' $zMetin (Open-DagitikZarf -Anahtarlar $zk -Zarf ($zJson | ConvertFrom-Json))
    Test-Dogru 'Zarfta duz icerik yok' ($zJson -cnotmatch 'Gizli Proje')
    $iki = ConvertTo-DagitikZarfJson (New-DagitikZarf -Anahtarlar $zk -Cihaz 'test-pc' -Tur 'ozet' -Sayac 7 -Metin $zMetin)
    Test-Dogru 'Ayni metin her seferinde farkli sifrelenir (rastgele IV)' (($iki | ConvertFrom-Json).veri -cne ($zJson | ConvertFrom-Json).veri)

    foreach ($degisim in @(@('sayac', 8), @('tur', 'kural'), @('yon', 'yanit'), @('cihaz', 'baska-pc'), @('zaman', 1))) {
        $kopya = $zJson | ConvertFrom-Json
        $kopya.($degisim[0]) = $degisim[1]
        $reddedildi = $false
        try { [void](Open-DagitikZarf -Anahtarlar $zk -Zarf $kopya) } catch { $reddedildi = $true }
        Test-Dogru "Imza kapsaminda: $($degisim[0]) degisirse reddedilir" $reddedildi
    }
    $kopya = $zJson | ConvertFrom-Json
    $kopya.veri = $(if ($kopya.veri[0] -ceq 'A') { 'B' } else { 'A' }) + $kopya.veri.Substring(1)
    $reddedildi = $false
    try { [void](Open-DagitikZarf -Anahtarlar $zk -Zarf $kopya) } catch { $reddedildi = $true }
    Test-Dogru 'Degistirilmis sifreli veri reddedilir' $reddedildi
    $reddedildi = $false
    try { [void](Open-DagitikZarf -Anahtarlar (Get-DagitikZarfAnahtarlari (New-DagitikAnahtar)) -Zarf ($zJson | ConvertFrom-Json)) } catch { $reddedildi = $true }
    Test-Dogru 'Baska cihaz anahtariyla acilmaz' $reddedildi
    $kopya = $zJson | ConvertFrom-Json; $kopya.sayac = '7'
    Test-Dogru 'Metin sayac gecersiz bicim' (-not (Test-DagitikZarfBicimi $kopya))
    $kopya = $zJson | ConvertFrom-Json; $kopya.sayac = 7.5
    Test-Dogru 'Ondalikli sayac gecersiz bicim' (-not (Test-DagitikZarfBicimi $kopya))
    $kopya = $zJson | ConvertFrom-Json; $kopya.v = 1
    Test-Dogru 'Surum 1 zarf gecersiz' (-not (Test-DagitikZarfBicimi $kopya))
    Test-Dogru 'Dizi zarf gecersiz' (-not (Test-DagitikZarfBicimi ('[1,2]' | ConvertFrom-Json)))

    $ka = Get-DagitikKayitAnahtarlari 'abcd efgh jkmn'
    $kb = Get-DagitikKayitAnahtarlari 'ABCD-EFGH-JKMN'
    $kc = Get-DagitikKayitAnahtarlari 'ABCD-EFGH-JKMP'
    Test-Dogru 'Kayit kanali bicimi' (Test-DagitikKayitKanali $ka.kanal)
    Test-Esit 'Kayit anahtari normallestirilmis koddan' $ka.kanal $kb.kanal
    Test-Dogru 'Farkli kod farkli kanal' ($ka.kanal -cne $kc.kanal)
    Test-Dogru 'Cihaz kimligi kayit kanali sayilmaz' (-not (Test-DagitikKayitKanali 'Ofis-PC-1a2b3c4d'))

    $pa = ConvertFrom-DagitikAdres 'HTTPS://Posta.Ornek.com/K/0123456789ABCDEF/'
    Test-Esit 'Posta adresi turu' 'posta' $pa.tur
    Test-Esit 'Posta adresi normallestirildi' 'https://Posta.Ornek.com/k/0123456789abcdef' $pa.adres
    Test-Esit 'Dogrudan adres' 'dogrudan' (ConvertFrom-DagitikAdres 'http://192.168.1.20:8787').tur
    Test-Dogru 'Yollu dogrudan adres reddedilir' ($null -eq (ConvertFrom-DagitikAdres 'http://192.168.1.20:8787/v1'))
    Test-Dogru 'Kullanici bilgili adres reddedilir' ($null -eq (ConvertFrom-DagitikAdres 'https://a:b@posta.ornek.com/k/0123456789abcdef'))
    Test-Dogru 'Kisa kutu reddedilir' ($null -eq (ConvertFrom-DagitikAdres 'https://posta.ornek.com/k/0123'))
    Test-Dogru 'Posta HTTPS zorunlu' (-not (Test-DagitikGuvenliPostaKoku 'http://posta.ornek.com'))
    Test-Dogru 'Posta HTTP yalniz bu bilgisayarda' (Test-DagitikGuvenliPostaKoku 'http://127.0.0.1:9000')

    foreach ($ornek in @(@('127.0.0.1', $true), @('10.1.2.3', $true), @('172.16.0.1', $true), @('172.31.255.1', $true),
        @('172.32.0.1', $false), @('192.168.1.5', $true), @('100.100.1.1', $true), @('100.128.0.1', $false),
        @('169.254.3.4', $true), @('8.8.8.8', $false), @('::1', $true), @('fd12::1', $true), @('fe80::1', $true),
        @('2001:4860::8888', $false), @('::ffff:192.168.1.9', $false))) {
        $ip = [Net.IPAddress]::Parse($ornek[0])
        Test-Esit "Yerel adres siniflamasi: $($ornek[0])" $ornek[1] (Test-DagitikYerelAdres $ip)
    }
}
catch {
    $script:kalan++
    Write-Output "  HATA  Zarf birim testleri: $($_.Exception.Message) [$($_.InvocationInfo.ScriptLineNumber)]"
    if (Get-Command Write-CiTestHatasi -ErrorAction SilentlyContinue) { Write-CiTestHatasi 'Zarf birim testleri' }
}

Write-Output '=== Protokol v2: dogrudan kayit ve gonderim ==='
$kok5 = Join-Path ([IO.Path]::GetTempPath()) ('ct-v2-' + [guid]::NewGuid().ToString('N').Substring(0, 10))
$sunucu5 = $null
try {
    $istemci5 = Join-Path $kok5 'istemci\hatirlatici'
    $merkez5 = Join-Path $kok5 'merkez'
    [void][IO.Directory]::CreateDirectory($merkez5)
    Write-KanalTestCsv $istemci5
    $port5 = Get-Random -Minimum 29000 -Maximum 33000
    $url5 = "http://127.0.0.1:$port5"
    $ayar5 = Join-Path $merkez5 'merkez-ayarlari.json'
    $veri5 = Join-Path $merkez5 'veri'
    $internet5 = 'http://aizen.ornek.test:8787'
    Write-DagitikJsonAtomik -Nesne ([ordered]@{
        surum = 1; port = $port5; dinlemeOnEki = "$url5/"; istemciSunucuUrl = $url5; internetUrl = $internet5; saklamaGun = 7; cihazlar = @()
    }) -Yol $ayar5

    $ekle5 = Invoke-KanalBetik (Join-Path $PSScriptRoot 'cihaz-ekle.ps1') @('-Ad', 'V2-PC', '-YapilandirmaYolu', $ayar5, '-SunucuUrl', $url5, '-GecerlilikDakika', '30')
    $kod5 = Get-KanalKodu $ekle5.Satirlar 'V2-PC'
    Test-Dogru 'v2: eslesme kodu uretildi' ($kod5 -cmatch '^[0-9A-Z]{4}-[0-9A-Z]{4}-[0-9A-Z]{4}$')
    Test-Dogru 'v2: cihaz-ekle internet adresini gosterir' ($ekle5.Metin -match [regex]::Escape($internet5))
    $mk5 = @((Read-DagitikJson $ayar5).cihazlar)[0]
    Test-Dogru 'v2: kayit kanali saklandi' (Test-DagitikKayitKanali ([string]$mk5.kayitKanaliV2))
    Test-Dogru 'v2: kayit ana anahtari korunmus saklandi' (-not [string]::IsNullOrWhiteSpace([string]$mk5.kayitAnaAnahtarV2Korunmus))
    $v2Beklenen = Get-DagitikKayitAnahtarlari $kod5
    Test-Esit 'v2: merkez kanali koddan turetilenle ayni' $v2Beklenen.kanal ([string]$mk5.kayitKanaliV2)
    $ayarMetni5 = [IO.File]::ReadAllText($ayar5)
    Test-Dogru 'v2: kod, ana anahtar ve posta jetonu duz saklanmaz' (
        $ayarMetni5 -notmatch [regex]::Escape($kod5) -and $ayarMetni5 -notmatch [regex]::Escape($v2Beklenen.anaAnahtar) -and
        $ayarMetni5 -notmatch $v2Beklenen.postaJetonu)

    $sunucu5 = Start-KanalSureci (Join-Path $PSScriptRoot 'merkez-sunucu.ps1') @('-DinlemeOnEki', "`"$url5/`"", '-YapilandirmaYolu', "`"$ayar5`"", '-VeriKlasoru', "`"$veri5`"", '-CalismaSuresiSn', '300') $kok5 'merkez'
    $saglik5 = Wait-KanalSaglik "$url5/health"
    Test-Dogru 'v2: merkez hazir' ($null -ne $saglik5)
    if ($null -ne $saglik5) {
        Test-Esit 'v2: merkez protokol 2 bildirir' 2 ([int]$saglik5.Json.protokol)
        $kayitPs = Join-Path $PSScriptRoot 'istemci-kayit.ps1'

        $r = Invoke-KanalBetik $kayitPs @('-SunucuUrl', $url5, '-Kod', 'ZZZZ-ZZZZ-ZZZZ', '-Onayla', '-Sessiz', '-GorevKurmadan', '-HatirlaticiKlasoru', $istemci5)
        Test-Dogru 'v2: yanlis kod reddedildi' ($r.Kod -ne 0)
        Test-Dogru 'v2: yanlis kodda merkez.json yazilmadi' (-not (Test-Path -LiteralPath (Join-Path $istemci5 'merkez.json')))

        $r = Invoke-KanalBetik $kayitPs @('-SunucuUrl', $url5, '-Kod', $kod5.ToLowerInvariant(), '-Onayla', '-Sessiz', '-GorevKurmadan', '-HatirlaticiKlasoru', $istemci5)
        Test-Esit 'v2: kayit cikis kodu' 0 $r.Kod
        if ($r.Kod -ne 0) { Write-Output ('    ' + ($r.Metin -replace '\s+', ' ')) }
        $im5 = Read-DagitikJson (Join-Path $istemci5 'merkez.json')
        Test-Esit 'v2: istemci protokol 2' 2 ([int](Get-DagitikDeger $im5 'protokol' 0))
        Test-Esit 'v2: dogrudan adres' $url5 ([string](Get-DagitikDeger $im5 'sunucuUrl' ''))
        Test-Dogru 'v2: internet adresi sifreli yanitla geldi' (@(Get-DagitikDeger $im5 'ekAdresler' @()) -contains $internet5)
        $mk5 = @((Read-DagitikJson $ayar5).cihazlar)[0]
        $id5 = [string]$mk5.id
        Test-Esit 'v2: merkezde cihaz kayitli' 'kayitli' ([string]$mk5.durum)
        Test-Dogru 'v2: iki protokolun kod verisi de silindi' ([string]::IsNullOrWhiteSpace([string]$mk5.kayitOzeti) -and [string]::IsNullOrWhiteSpace([string]$mk5.kayitAnaAnahtarV2Korunmus))
        $anahtar5 = ''
        try {
            $anahtar5 = Unprotect-DagitikAnahtar -KorunmusAnahtar ([string]$im5.anahtarKorunmus) -Amac "istemci:$id5"
            Test-Esit 'v2: merkez ve istemci ayni cihaz anahtarini tutar' $anahtar5 (Unprotect-DagitikAnahtar -KorunmusAnahtar ([string]$mk5.anahtarKorunmus) -Amac "merkez:$id5")
        }
        catch { Test-Dogru 'v2: cihaz anahtari acilabildi' $false }

        $v1Govde = [ordered]@{ schemaVersion = 1; kod = (ConvertTo-DagitikKodNormal $kod5); cihazAdi = 'Saldirgan'; onay = $true } | ConvertTo-Json -Compress
        Test-Esit 'v2 ile kullanilan kod v1 ucunda da gecersiz' 403 (Invoke-KanalHttp "$url5/v1/kayit" 'POST' -Govde $v1Govde).Kod
        $tekrarKayit = New-DagitikZarf -Anahtarlar $v2Beklenen -Cihaz $v2Beklenen.kanal -Tur 'kayit' -Sayac 1 -Metin '{"schemaVersion":2,"onay":true}'
        Test-Esit 'v2: kullanilmis kodla ikinci kayit reddedildi' 403 (Invoke-KanalHttp "$url5/v2/zarf" 'POST' -Govde (ConvertTo-DagitikZarfJson $tekrarKayit)).Kod

        $g = Invoke-KanalBetik (Join-Path $PSScriptRoot 'istemci-gonderici.ps1') @('-HatirlaticiKlasoru', $istemci5)
        $anlik5 = Read-DagitikJson (Join-Path $veri5 "guncel\$id5.json")
        Test-Dogru 'v2: ozet merkeze ulasti' ($null -ne $anlik5)
        if ($null -eq $anlik5) { Write-Output ('    ' + ($g.Metin -replace '\s+', ' ')) }
        else { Test-Esit 'v2: ozet calisma dakikasi' 3 ([int]$anlik5.ozet.calismaDk) }
        Test-Esit 'v2: outbox temiz' 0 (@(Get-ChildItem -LiteralPath (Join-Path $istemci5 'merkez-outbox') -Filter '*.json' -File -ErrorAction SilentlyContinue).Count)
        $im5 = Read-DagitikJson (Join-Path $istemci5 'merkez.json')
        Test-Esit 'v2: kanal dogrudan' 'dogrudan' ([string](Get-DagitikDeger $im5 'sonKanal' ''))
        Test-Dogru 'v2: sayac ilerledi ve diske yazildi' ([int](Get-DagitikDeger $im5 'sayac' 0) -ge 3)
        Test-Dogru 'v2: ortak sayac yazildi' (Test-Path -LiteralPath (Join-Path $istemci5 'ortak-sayac.json'))
        Test-Dogru 'v2: ortak kurallar alindi' (-not [string]::IsNullOrWhiteSpace([string](Get-DagitikDeger $im5 'sonKuralAlimiUtc' '')))
        Test-Dogru 'v2: internet adresi korundu' (@(Get-DagitikDeger $im5 'ekAdresler' @()) -contains $internet5)

        if ($anahtar5) {
            $k5 = Get-DagitikZarfAnahtarlari $anahtar5
            $ayarK = Read-DagitikJson $ayar5
            Set-DagitikDeger (@($ayarK.cihazlar)[0]) 'kuralYazabilir' $true
            Write-DagitikJsonAtomik -Nesne $ayarK -Yol $ayar5
            $kararMetni = [ordered]@{ schemaVersion = 1; cihazId = $id5; kararlar = @([ordered]@{ oge = 'OyunV2'; tur = 'surec'; karar = 'yasakli' }) } | ConvertTo-Json -Depth 4 -Compress
            $kuralZarfi = ConvertTo-DagitikZarfJson (New-DagitikZarf -Anahtarlar $k5 -Cihaz $id5 -Tur 'kural' -Sayac 5000 -Metin $kararMetni)
            $r1 = Invoke-KanalHttp "$url5/v2/zarf" 'POST' -Govde $kuralZarfi
            Test-Esit 'v2: kural zarfi kabul edildi' 200 $r1.Kod
            if ($r1.Kod -eq 200) {
                $ic1 = (Open-DagitikZarf -Anahtarlar $k5 -Zarf $r1.Json) | ConvertFrom-Json
                Test-Esit 'v2: kural yaniti sifreli govdede' 1 ([int]$ic1.govde.islenen)
                Test-Esit 'v2: yanit zarfi istek sayacini tasir' 5000 ([int]$r1.Json.sayac)
                Test-Dogru 'v2: yanit guncel adresleri tasir' (@($ic1.adresler.ekAdresler) -contains $internet5)
                Test-Dogru 'v2: yanit metninde duz govde yok' ($r1.Metin -cnotmatch '"islenen"')
            }
            Test-Esit 'v2: ayni kural zarfi ikinci kez reddedildi (tekrar)' 409 (Invoke-KanalHttp "$url5/v2/zarf" 'POST' -Govde $kuralZarfi).Kod
            $eskiSayac = ConvertTo-DagitikZarfJson (New-DagitikZarf -Anahtarlar $k5 -Cihaz $id5 -Tur 'kural' -Sayac 3000 -Metin $kararMetni)
            Test-Esit 'v2: pencerenin gerisindeki sayac reddedildi' 409 (Invoke-KanalHttp "$url5/v2/zarf" 'POST' -Govde $eskiSayac).Kod
            $yakinSayac = ConvertTo-DagitikZarfJson (New-DagitikZarf -Anahtarlar $k5 -Cihaz $id5 -Tur 'kural' -Sayac 4990 -Metin $kararMetni)
            Test-Esit 'v2: pencere icinde gec gelen sayac kabul' 200 (Invoke-KanalHttp "$url5/v2/zarf" 'POST' -Govde $yakinSayac).Kod
            $bozuk = $kuralZarfi | ConvertFrom-Json
            $bozuk.sayac = 5001
            Test-Esit 'v2: kurcalanmis zarf 401' 401 (Invoke-KanalHttp "$url5/v2/zarf" 'POST' -Govde ($bozuk | ConvertTo-Json -Compress)).Kod
            $yabanci = New-DagitikZarf -Anahtarlar (Get-DagitikZarfAnahtarlari (New-DagitikAnahtar)) -Cihaz $id5 -Tur 'kurallar' -Sayac 1 -Metin '{}'
            Test-Esit 'v2: baska anahtarla zarf 401' 401 (Invoke-KanalHttp "$url5/v2/zarf" 'POST' -Govde (ConvertTo-DagitikZarfJson $yabanci)).Kod
            $eskiZaman = New-DagitikZarf -Anahtarlar $k5 -Cihaz $id5 -Tur 'kurallar' -Sayac 6000 -Metin '{}' -Zaman ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - 31 * 86400)
            Test-Esit 'v2: 30 gunden eski zarf 401' 401 (Invoke-KanalHttp "$url5/v2/zarf" 'POST' -Govde (ConvertTo-DagitikZarfJson $eskiZaman)).Kod
            $gecZarf = New-DagitikZarf -Anahtarlar $k5 -Cihaz $id5 -Tur 'kurallar' -Sayac 6001 -Metin '{}' -Zaman ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - 3 * 86400)
            Test-Esit 'v2: posta kutusunda bekleyip gec gelen okuma zarfi kabul' 200 (Invoke-KanalHttp "$url5/v2/zarf" 'POST' -Govde (ConvertTo-DagitikZarfJson $gecZarf)).Kod
            Test-Esit 'v2: bozuk JSON 400' 400 (Invoke-KanalHttp "$url5/v2/zarf" 'POST' -Govde '{bozuk').Kod
        }
        $log5 = ''
        try { $log5 = [IO.File]::ReadAllText((Join-Path $veri5 'merkez.log')) } catch { }
        Test-Dogru 'v2: merkez gunlugunde kod ve anahtar yok' ($log5 -notmatch [regex]::Escape($kod5) -and (-not $anahtar5 -or $log5 -notmatch [regex]::Escape($anahtar5)))
    }
}
catch {
    $script:kalan++
    Write-Output "  HATA  v2 dogrudan akis: $($_.Exception.Message) [$($_.InvocationInfo.ScriptLineNumber)]"
    if (Get-Command Write-CiTestHatasi -ErrorAction SilentlyContinue) { Write-CiTestHatasi 'v2 dogrudan akis' }
}
finally {
    Stop-KanalSureci $sunucu5
    Remove-TestKlasoru $kok5
}

Write-Output '=== Posta kutusu: uctan uca ==='
$kok6 = Join-Path ([IO.Path]::GetTempPath()) ('ct-posta-' + [guid]::NewGuid().ToString('N').Substring(0, 10))
$posta6 = $null
$sunucu6 = $null
try {
    $istemci6 = Join-Path $kok6 'istemci\hatirlatici'
    $merkez6 = Join-Path $kok6 'merkez'
    $postaVeri6 = Join-Path $kok6 'posta-veri'
    [void][IO.Directory]::CreateDirectory($merkez6)
    Write-KanalTestCsv $istemci6
    $postaPs = Join-Path $PSScriptRoot '..\posta-sunucusu\posta-sunucu.ps1'
    $postaPort = Get-Random -Minimum 33000 -Maximum 37000
    $postaUrl6 = "http://127.0.0.1:$postaPort"
    $port6 = $postaPort + 1
    $url6 = "http://127.0.0.1:$port6"
    $ayar6 = Join-Path $merkez6 'merkez-ayarlari.json'
    $veri6 = Join-Path $merkez6 'veri'
    Write-DagitikJsonAtomik -Nesne ([ordered]@{ surum = 1; port = $port6; dinlemeOnEki = "$url6/"; istemciSunucuUrl = $url6; saklamaGun = 7; cihazlar = @() }) -Yol $ayar6

    $jetonCikti = Invoke-KanalBetik $postaPs @('-VeriKlasoru', $postaVeri6, '-YonetimJetonuUret')
    $yonetim6 = [string]@($jetonCikti.Satirlar | Where-Object { $_ -cmatch '^[A-Za-z0-9_-]{32,128}$' } | Select-Object -Last 1)[0]
    Test-Dogru 'Posta: yonetim jetonu uretildi' ($yonetim6.Length -ge 32)
    Test-Dogru 'Posta: sunucu yonetim jetonunun kendisini saklamaz' ([IO.File]::ReadAllText((Join-Path $postaVeri6 'ayar.json')) -notmatch [regex]::Escape($yonetim6))

    $posta6 = Start-KanalSureci $postaPs @('-VeriKlasoru', "`"$postaVeri6`"", '-Dinle', '127.0.0.1', '-Port', "$postaPort", '-CalismaSuresiSn', '400') $kok6 'posta'
    Test-Dogru 'Posta: sunucu hazir' ($null -ne (Wait-KanalSaglik "$postaUrl6/saglik"))

    $baglaPs = Join-Path $PSScriptRoot 'posta-baglan.ps1'
    $yanlis = Invoke-KanalBetik $baglaPs @('-PostaUrl', $postaUrl6, '-YonetimJetonu', ('x' * 43), '-YapilandirmaYolu', $ayar6)
    Test-Dogru 'Posta: yanlis yonetim jetonu reddedildi' ($yanlis.Kod -ne 0)
    $bagla = Invoke-KanalBetik $baglaPs @('-PostaUrl', $postaUrl6, '-YonetimJetonu', $yonetim6, '-YapilandirmaYolu', $ayar6, '-AralikSn', '2')
    Test-Esit 'Posta: merkez kutuya baglandi' 0 $bagla.Kod
    $postaAdresi6 = ''
    $eslesme = [regex]::Match($bagla.Metin, [regex]::Escape($postaUrl6) + '/k/[0-9a-f]{32}')
    if ($eslesme.Success) { $postaAdresi6 = $eslesme.Value }
    Test-Dogru 'Posta: istemci adresi yazildi' ([bool]$postaAdresi6)
    $kutu6 = ($postaAdresi6 -split '/k/')[-1]
    $ayarMetni6 = [IO.File]::ReadAllText($ayar6)
    $bagla2 = Invoke-KanalBetik $baglaPs @('-PostaUrl', $postaUrl6, '-YonetimJetonu', $yonetim6, '-YapilandirmaYolu', $ayar6, '-AralikSn', '2')
    Test-Dogru 'Posta: yeniden baglanmada kutu adresi korunur' ($bagla2.Kod -eq 0 -and $bagla2.Metin -match [regex]::Escape($postaAdresi6))

    $ekle6 = Invoke-KanalBetik (Join-Path $PSScriptRoot 'cihaz-ekle.ps1') @('-Ad', 'Uzak-PC', '-YapilandirmaYolu', $ayar6, '-SunucuUrl', $url6, '-GecerlilikDakika', '30')
    $kod6 = Get-KanalKodu $ekle6.Satirlar 'Uzak-PC'
    Test-Dogru 'Posta: cihaz-ekle posta adresini gosterir' ($postaAdresi6 -and $ekle6.Metin -match [regex]::Escape($postaAdresi6))

    $sunucu6 = Start-KanalSureci (Join-Path $PSScriptRoot 'merkez-sunucu.ps1') @('-DinlemeOnEki', "`"$url6/`"", '-YapilandirmaYolu', "`"$ayar6`"", '-VeriKlasoru', "`"$veri6`"", '-CalismaSuresiSn', '400') $kok6 'merkez'
    Test-Dogru 'Posta: merkez hazir' ($null -ne (Wait-KanalSaglik "$url6/health"))

    $r = Invoke-KanalBetik (Join-Path $PSScriptRoot 'istemci-kayit.ps1') @('-SunucuUrl', $postaAdresi6, '-Kod', $kod6, '-Onayla', '-Sessiz', '-GorevKurmadan', '-HatirlaticiKlasoru', $istemci6, '-PostaBeklemeSn', '90')
    Test-Esit 'Posta: kutu uzerinden kayit' 0 $r.Kod
    if ($r.Kod -ne 0) { Write-Output ('    ' + ($r.Metin -replace '\s+', ' ')) }
    $im6 = Read-DagitikJson (Join-Path $istemci6 'merkez.json')
    Test-Esit 'Posta: istemcide posta adresi' $postaAdresi6 ([string](Get-DagitikDeger $im6 'postaUrl' ''))
    Test-Esit 'Posta: merkezin dongu adresi istemciye yazilmadi' '' ([string](Get-DagitikDeger $im6 'sunucuUrl' ''))
    $id6 = [string](Get-DagitikDeger $im6 'cihazId' '')

    if ($id6) {
        $k6 = Get-DagitikZarfAnahtarlari (Unprotect-DagitikAnahtar -KorunmusAnahtar ([string]$im6.anahtarKorunmus) -Amac "istemci:$id6")
        $h6 = @{ 'X-Aizen-Kutu' = $kutu6; 'X-Aizen-Cihaz' = $id6; 'X-Aizen-Jeton' = $k6.postaJetonu }
        # Merkez kayitli cihazin jetonunu bir sonraki turda (2 sn) bildirir
        $tanindi = $false
        for ($i = 0; $i -lt 40 -and -not $tanindi; $i++) {
            if ((Invoke-KanalHttp "$postaUrl6/r1/cihaz/gelen" 'GET' $h6).Kod -eq 200) { $tanindi = $true } else { Start-Sleep -Milliseconds 500 }
        }
        Test-Dogru 'Posta: kayitli cihaz kutuda tanindi' $tanindi

        $g1 = Invoke-KanalBetik (Join-Path $PSScriptRoot 'istemci-gonderici.ps1') @('-HatirlaticiKlasoru', $istemci6)
        $im6 = Read-DagitikJson (Join-Path $istemci6 'merkez.json')
        Test-Esit 'Posta: kanal posta' 'posta' ([string](Get-DagitikDeger $im6 'sonKanal' ''))
        Test-Esit 'Posta: ozet kutuya birakildi' 'postada' ([string](Get-DagitikDeger $im6 'sonDurum' ''))
        if ([string](Get-DagitikDeger $im6 'sonDurum' '') -ne 'postada') { Write-Output ('    ' + ([string](Get-DagitikDeger $im6 'sonHata' '')) + ' ' + ($g1.Metin -replace '\s+', ' ')) }
        Test-Esit 'Posta: outbox temiz' 0 (@(Get-ChildItem -LiteralPath (Join-Path $istemci6 'merkez-outbox') -Filter '*.json' -File -ErrorAction SilentlyContinue).Count)

        $anlik6 = $null
        for ($i = 0; $i -lt 60 -and $null -eq $anlik6; $i++) {
            $anlik6 = Read-DagitikJson (Join-Path $veri6 "guncel\$id6.json")
            if ($null -eq $anlik6) { Start-Sleep -Milliseconds 500 }
        }
        Test-Dogru 'Posta: merkez ozeti kutudan aldi' ($null -ne $anlik6)
        if ($null -ne $anlik6) { Test-Esit 'Posta: ozet calisma dakikasi' 3 ([int]$anlik6.ozet.calismaDk) }

        $yanitlar6 = $null
        for ($i = 0; $i -lt 40; $i++) {
            $yanitlar6 = Invoke-KanalHttp "$postaUrl6/r1/cihaz/gelen" 'GET' $h6
            if ($yanitlar6.Kod -eq 200 -and @($yanitlar6.Json.mesajlar).Count -ge 3) { break }
            Start-Sleep -Milliseconds 500
        }
        Test-Dogru 'Posta: merkez yanitlari kutuya birakti' ($null -ne $yanitlar6 -and @($yanitlar6.Json.mesajlar).Count -ge 3)
        $hamYanit = $(if ($null -ne $yanitlar6) { $yanitlar6.Metin } else { '' })
        Test-Dogru 'Posta: kutudaki yanitlarda duz veri yok' ($hamYanit -and $hamYanit -cnotmatch '"toplamDk"|"calisma"|"sonDegisiklikUtc"|"islenen"')
        $kutuDosyalari = (@(Get-ChildItem -LiteralPath $postaVeri6 -Recurse -File | ForEach-Object { [IO.File]::ReadAllText($_.FullName) }) -join "`n")
        Test-Dogru 'Posta: sunucu diskinde duz veri, kod ve cihaz anahtari yok' (
            $kutuDosyalari -cnotmatch 'Gizli Proje|"calismaDk"|"toplamDk"' -and $kutuDosyalari -notmatch [regex]::Escape($kod6) -and
            $kutuDosyalari -notmatch $k6.postaJetonu)

        [void](Invoke-KanalBetik (Join-Path $PSScriptRoot 'istemci-gonderici.ps1') @('-HatirlaticiKlasoru', $istemci6))
        $im6 = Read-DagitikJson (Join-Path $istemci6 'merkez.json')
        Test-Dogru 'Posta: ozet yaniti alindi' (-not [string]::IsNullOrWhiteSpace([string](Get-DagitikDeger $im6 'sonBasariliSenkronUtc' '')))
        Test-Dogru 'Posta: ortak kurallar alindi' (-not [string]::IsNullOrWhiteSpace([string](Get-DagitikDeger $im6 'sonKuralAlimiUtc' '')))
        Test-Dogru 'Posta: ortak sayac yazildi' (Test-Path -LiteralPath (Join-Path $istemci6 'ortak-sayac.json'))

        $sahte = @{ 'X-Aizen-Kutu' = $kutu6; 'X-Aizen-Cihaz' = $id6; 'X-Aizen-Jeton' = ('0' * 64) }
        Test-Esit 'Posta: yanlis cihaz jetonu 401' 401 (Invoke-KanalHttp "$postaUrl6/r1/cihaz/gelen" 'GET' $sahte).Kod
        Test-Esit 'Posta: cihaz jetonu merkez ucunda gecmez' 401 (Invoke-KanalHttp "$postaUrl6/r1/merkez/gelen" 'GET' @{ 'X-Aizen-Kutu' = $kutu6; 'X-Aizen-Jeton' = $k6.postaJetonu }).Kod
        $baskasi = ConvertTo-DagitikZarfJson (New-DagitikZarf -Anahtarlar $k6 -Cihaz 'baska-cihaz' -Tur 'ozet' -Sayac 1 -Metin '{}')
        Test-Esit 'Posta: baska cihaz adina zarf birakilamaz' 400 (Invoke-KanalHttp "$postaUrl6/r1/cihaz/gonder" 'POST' $h6 -Govde ('{"anahtar":"","zarf":' + $baskasi + '}')).Kod
    }
}
catch {
    $script:kalan++
    Write-Output "  HATA  Posta kutusu akisi: $($_.Exception.Message) [$($_.InvocationInfo.ScriptLineNumber)]"
    if (Get-Command Write-CiTestHatasi -ErrorAction SilentlyContinue) { Write-CiTestHatasi 'Posta kutusu akisi' }
}
finally {
    Stop-KanalSureci $sunucu6
    Stop-KanalSureci $posta6
    Remove-TestKlasoru $kok6
}

# Posta kutusu sunucusunun kendi API testleri (Linux CI'da pwsh ile de calisir)
$postaTestPs = Join-Path $PSScriptRoot '..\posta-sunucusu\test-posta.ps1'
if (Test-Path -LiteralPath $postaTestPs) {
    $pt = Invoke-KanalBetik $postaTestPs @()
    Test-Esit 'Posta kutusu sunucusu API testleri' 0 $pt.Kod
    if ($pt.Kod -ne 0) { $pt.Satirlar | Where-Object { $_ -match 'HATA|Sonuc' } | ForEach-Object { Write-Output "    $_" } }
}

if ($script:bagimsizKanal) {
    Write-Output "Sonuc: $script:gecen basarili, $script:kalan hatali"
    if ($script:kalan -gt 0) { exit 1 } else { exit 0 }
}
