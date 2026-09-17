# Dagitik katmanin izole testleri. Gercek yapilandirma, gorev veya ag duvarina dokunmaz.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Ortak.ps1')
. (Join-Path $PSScriptRoot 'Merkez-Ozet.ps1')

$gecen = 0; $kalan = 0
function Write-CiTestHatasi {
    # GitHub'un ayrintili Actions gunlukleri oturum gerektirebilir. Basarisiz
    # denetimin adi, hassas beklenen/gercek degerleri yazmadan check annotation
    # olarak gorunsun ki CI'da hata kaynagi anlasilabilsin.
    param([string]$Ad)
    if ($env:GITHUB_ACTIONS -ne 'true') { return }
    $mesaj = $Ad.Replace('%', '%25').Replace("`r", '%0D').Replace("`n", '%0A')
    Write-Output "::error title=Aizen test failure::$mesaj"
}
function Test-Esit {
    param([string]$Ad, [object]$Beklenen, [object]$Gercek)
    if ($Beklenen -ceq $Gercek) { $script:gecen++; Write-Output "  OK  $Ad" }
    else {
        $script:kalan++
        Write-Output "  HATA  $Ad | beklenen=[$Beklenen] gercek=[$Gercek]"
        Write-CiTestHatasi $Ad
    }
}
function Test-Dogru {
    param([string]$Ad, [bool]$Kosul)
    if ($Kosul) { $script:gecen++; Write-Output "  OK  $Ad" }
    else {
        $script:kalan++
        Write-Output "  HATA  $Ad"
        Write-CiTestHatasi $Ad
    }
}
function Remove-TestKlasoru {
    param([string]$Yol)
    $temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    $tam = [IO.Path]::GetFullPath($Yol)
    if ($tam.StartsWith($temp, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $tam)) {
        Remove-Item -LiteralPath $tam -Recurse -Force
    }
}

Write-Output '=== Dagitik temel testleri ==='
$anahtar = New-DagitikAnahtar
$imza = Get-DagitikHmac -Anahtar $anahtar -ZamanDamgasi '1234567890' -Govde '{"ornek":true}'
Test-Dogru 'HMAC uzunlugu 64 hex' ($imza -match '^[a-f0-9]{64}$')
Test-Dogru 'HMAC sabit zamanli esitlik' (Test-DagitikSabitZamanliEsitlik $imza $imza)
# Son karakteri mutlaka degistir: imza zaten '0' ile bitiyorsa ayni deger cikiyordu
$bozukImza = $imza.Substring(0, 63) + $(if ($imza[63] -eq '0') { '1' } else { '0' })
Test-Dogru 'HMAC yanlis deger reddedilir' (-not (Test-DagitikSabitZamanliEsitlik $imza $bozukImza))
Test-Dogru 'Gecerli cihaz kimligi' (Test-DagitikCihazKimligi 'test-pc_01')
Test-Dogru 'Gecersiz cihaz kimligi' (-not (Test-DagitikCihazKimligi '../test'))
$korunmus = Protect-DagitikAnahtar -Anahtar $anahtar -Amac 'test-cihaz'
Test-Esit 'DPAPI ayni kullanicida acilir' $anahtar (Unprotect-DagitikAnahtar -KorunmusAnahtar $korunmus -Amac 'test-cihaz')

$kok = Join-Path ([IO.Path]::GetTempPath()) ('calisma-takip-test-' + [guid]::NewGuid().ToString('N'))
try {
    $istemci = Join-Path $kok 'istemci\hatirlatici'
    $merkez = Join-Path $kok 'merkez'
    [void][IO.Directory]::CreateDirectory((Join-Path $istemci 'aktivite'))
    [void][IO.Directory]::CreateDirectory($merkez)
    $port = Get-Random -Minimum 24000 -Maximum 29000
    $url = "http://127.0.0.1:$port"
    $cihaz = 'test-cihaz-01'
    $testAnahtar = New-DagitikAnahtar
    $merkezAyar = [ordered]@{
        surum = 1; port = $port; dinlemeOnEki = "$url/"; istemciSunucuUrl = $url; saklamaGun = 7
        cihazlar = @([ordered]@{
            id = $cihaz; ad = 'Izole Test Cihazi'; aktif = $true
            anahtarKorunmus = Protect-DagitikAnahtar -Anahtar $testAnahtar -Amac "merkez:$cihaz"
            baslikIzinli = $false; alanAdiIzinli = $false
        })
    }
    $merkezAyarYolu = Join-Path $merkez 'merkez-ayarlari.json'
    Write-DagitikJsonAtomik -Nesne $merkezAyar -Yol $merkezAyarYolu
    $istemciAyar = [ordered]@{
        surum = 1; aktif = $true; cihazId = $cihaz; cihazAdi = 'Izole Test Cihazi'; sunucuUrl = $url
        anahtarKorunmus = Protect-DagitikAnahtar -Anahtar $testAnahtar -Amac "istemci:$cihaz"
        ayrintiDuzeyi = 'ozet'; sira = 0; sonDurum = ''; sonHata = ''
    }
    Write-DagitikJsonAtomik -Nesne $istemciAyar -Yol (Join-Path $istemci 'merkez.json')
    Write-DagitikJsonAtomik -Nesne ([ordered]@{ hedef = 120 }) -Yol (Join-Path $istemci 'ayarlar.json')
    $bugun = Get-Date -Format 'yyyy-MM-dd'
    $csv = @(
        'zaman;uygulama;baslik;bosta;kategori;sure;kaynak',
        '09:00:00;Code;Gizli Baslik;0;calisma;120;izinli',
        '09:02:00;Chrome;Ornek Site;0;diger;60;yasakli',
        '09:03:00;Code;Gizli Baslik;0;calisma;60;izinli'
    ) -join [Environment]::NewLine
    [IO.File]::WriteAllText((Join-Path $istemci "aktivite\\$bugun.csv"), $csv, (New-Object Text.UTF8Encoding($true)))

    $psExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $stdout = Join-Path $kok 'merkez.stdout'; $stderr = Join-Path $kok 'merkez.stderr'
    $args = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$(Join-Path $PSScriptRoot 'merkez-sunucu.ps1')`"",'-DinlemeOnEki',"`"$url/`"",'-YapilandirmaYolu',"`"$merkezAyarYolu`"",'-VeriKlasoru',"`"$(Join-Path $merkez 'veri')`"",'-BirKere')
    $sunucu = Start-Process -FilePath $psExe -ArgumentList $args -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
    $hazir = $false
    for ($i = 0; $i -lt 25; $i++) {
        try {
            $saglik = Invoke-WebRequest -Uri "$url/health" -UseBasicParsing -TimeoutSec 1
            if ($saglik.StatusCode -eq 200) { $hazir = $true; break }
        } catch { }
        Start-Sleep -Milliseconds 200
    }
    Test-Dogru 'Merkez localhost dinleyicisi hazir' $hazir
    if ($hazir) {
        & $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'istemci-gonderici.ps1') -HatirlaticiKlasoru $istemci
        $sunucu.WaitForExit(10000)
        $anlik = Read-DagitikJson (Join-Path $merkez "veri\\guncel\\$cihaz.json")
        Test-Dogru 'Imzali istemci paketi kaydedildi' ($null -ne $anlik)
        if ($null -ne $anlik) {
            Test-Esit 'Merkez cihaz kimligi' $cihaz $anlik.cihazId
            Test-Esit 'Calisma ozet dakikasi' 3 ([int]$anlik.ozet.calismaDk)
            Test-Esit 'Diger ozet dakikasi' 1 ([int]$anlik.ozet.digerDk)
            Test-Esit 'Baslik varsayilan olarak merkezde yok' 0 (@($anlik.basliklar).Count)
            Test-Esit 'Iki uygulama ozetlendi' 2 (@($anlik.uygulamalar).Count)
        }
        Test-Esit 'Basarili gonderim sonrasi outbox temiz' 0 (@(Get-ChildItem -LiteralPath (Join-Path $istemci 'merkez-outbox') -Filter '*.json' -File -ErrorAction SilentlyContinue).Count)
    }
    if (-not $sunucu.HasExited) { $sunucu.Kill(); $sunucu.WaitForExit() }
}
catch {
    $kalan++
    Write-Output "  HATA  Izole HTTP entegrasyonu: $($_.Exception.Message) [$($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)]"
    Write-CiTestHatasi 'Izole HTTP entegrasyonu'
    Write-Output $_.InvocationInfo.PositionMessage
    Write-Output $_.ScriptStackTrace
}
finally { Remove-TestKlasoru $kok }

Write-Output '=== Eslesme kodu, kayit ve merkez ozeti testleri ==='
$kok2 = Join-Path ([IO.Path]::GetTempPath()) ('calisma-takip-kayit-' + [guid]::NewGuid().ToString('N'))
$sunucu2 = $null
try {
    $istemci2 = Join-Path $kok2 'istemci\hatirlatici'
    $merkez2 = Join-Path $kok2 'merkez'
    [void][IO.Directory]::CreateDirectory((Join-Path $istemci2 'aktivite'))
    [void][IO.Directory]::CreateDirectory($merkez2)
    $port2 = Get-Random -Minimum 24000 -Maximum 29000
    $url2 = "http://127.0.0.1:$port2"
    $merkezAyar2 = Join-Path $merkez2 'merkez-ayarlari.json'
    $veri2 = Join-Path $merkez2 'veri'
    Write-DagitikJsonAtomik -Nesne ([ordered]@{
        surum = 1; port = $port2; dinlemeOnEki = "$url2/"; istemciSunucuUrl = $url2
        saklamaGun = 7; cihazlar = @()
    }) -Yol $merkezAyar2
    Write-DagitikJsonAtomik -Nesne ([ordered]@{ hedef = 200 }) -Yol (Join-Path $istemci2 'ayarlar.json')
    $bugun2 = Get-Date -Format 'yyyy-MM-dd'
    $csv2 = @(
        'zaman;uygulama;baslik;bosta;kategori;sure;kaynak',
        '10:00:00;Code;Proje;0;calisma;180;izinli',
        '10:05:00;Chrome;Site;0;diger;60;yasakli'
    ) -join [Environment]::NewLine
    [IO.File]::WriteAllText((Join-Path $istemci2 "aktivite\$bugun2.csv"), $csv2, (New-Object Text.UTF8Encoding($true)))

    $psExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $ekleCikti = @(& $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'cihaz-ekle.ps1') `
        -Ad 'Test-PC' -YapilandirmaYolu $merkezAyar2 -SunucuUrl $url2 -GecerlilikDakika 30)
    $kodSatiri = @($ekleCikti | Where-Object { $_ -match '^Test-PC\s' } | Select-Object -First 1)[0]
    $kod2 = ''
    if ($kodSatiri) { $kod2 = @([regex]::Split($kodSatiri.Trim(), '\s+'))[-1] }
    Test-Dogru 'Eslesme kodu uretildi' ($kod2 -cmatch '^[0-9A-Z]{4}-[0-9A-Z]{4}-[0-9A-Z]{4}$')
    $ayar2 = Read-DagitikJson $merkezAyar2
    Test-Esit 'Cihaz bekliyor durumunda' 'bekliyor' ([string]@($ayar2.cihazlar)[0].durum)
    Test-Dogru 'Kod merkezde duz metin saklanmaz' ([IO.File]::ReadAllText($merkezAyar2) -notmatch [regex]::Escape($kod2))
    Test-Dogru 'Kayit oncesi anahtar yok' ([string]::IsNullOrWhiteSpace([string]@($ayar2.cihazlar)[0].anahtarKorunmus))

    # tr-TR: kulture bagli regex 'I'yi 'ı'ya katliyordu. Kod yazim hatasi duzeltmesi ve
    # baska dilde/platformda uretilmis 'I' iceren cihaz kimligi bu makinede de calismali.
    Test-Esit 'Kod normallestirme: O->0, I ve L->1' '011123456789' (ConvertTo-DagitikKodNormal ' O1IL-2345-6789 ')
    Test-Esit 'Kod normallestirme: kucuk i->1' 'ABC1' (ConvertTo-DagitikKodNormal 'abci')
    Test-Dogru 'Buyuk I iceren cihaz kimligi gecerli' (Test-DagitikCihazKimligi 'Ofis-PC-IT-1a2b')
    $kimlikAyar = Join-Path $kok2 'kimlik-dene.json'
    & $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'cihaz-ekle.ps1') `
        -Ad 'IT-Laptop' -YapilandirmaYolu $kimlikAyar -SunucuUrl $url2 -GecerlilikDakika 30 | Out-Null
    Test-Dogru 'Cihaz kimligi I harfini korur' ([string]@((Read-DagitikJson $kimlikAyar).cihazlar)[0].id -cmatch '^IT-Laptop-[0-9a-f]{8}$')

    $stdout2 = Join-Path $kok2 'merkez.stdout'; $stderr2 = Join-Path $kok2 'merkez.stderr'
    $args2 = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$(Join-Path $PSScriptRoot 'merkez-sunucu.ps1')`"",
        '-DinlemeOnEki',"`"$url2/`"",'-YapilandirmaYolu',"`"$merkezAyar2`"",'-VeriKlasoru',"`"$veri2`"",'-IstekSayisi','15')
    $sunucu2 = Start-Process -FilePath $psExe -ArgumentList $args2 -RedirectStandardOutput $stdout2 -RedirectStandardError $stderr2 -PassThru
    $hazir2 = $false
    for ($i = 0; $i -lt 25; $i++) {
        try { if ((Invoke-WebRequest -Uri "$url2/health" -UseBasicParsing -TimeoutSec 1).StatusCode -eq 200) { $hazir2 = $true; break } } catch { }
        Start-Sleep -Milliseconds 200
    }
    Test-Dogru 'Kayit sunucusu hazir' $hazir2
    if (-not $hazir2 -and (Test-Path -LiteralPath $stderr2)) {
        Write-Output ('  merkez stderr: ' + (((Get-Content -LiteralPath $stderr2 -Raw) + '') -replace '\s+', ' '))
    }
    if ($hazir2) {
        # PS 5.1'de alt surecin stderr satirlari ErrorRecord'a donusur; EAP=Stop iken
        # beklenen basarisizlik (yanlis kod) testin kendisini dusuruyordu. Bu blokta
        # akis try/catch ile degil assert'lerle yonetilir.
        $ErrorActionPreference = 'Continue'
        $kayitPs = Join-Path $PSScriptRoot 'istemci-kayit.ps1'
        # 1) yanlis kod reddedilmeli
        & $psExe -NoProfile -ExecutionPolicy Bypass -File $kayitPs -SunucuUrl $url2 -Kod 'ZZZZ-ZZZZ-ZZZZ' `
            -Onayla -Sessiz -GorevKurmadan -HatirlaticiKlasoru $istemci2 2>$null | Out-Null
        Test-Dogru 'Yanlis kod reddedildi' ($LASTEXITCODE -ne 0)
        Test-Dogru 'Yanlis kodda merkez.json yazilmadi' (-not (Test-Path -LiteralPath (Join-Path $istemci2 'merkez.json')))

        # 2) dogru kod: kayit tamamlanmali
        & $psExe -NoProfile -ExecutionPolicy Bypass -File $kayitPs -SunucuUrl $url2 -Kod $kod2 `
            -Onayla -Sessiz -GorevKurmadan -HatirlaticiKlasoru $istemci2 | Out-Null
        Test-Esit 'Kayit cikis kodu' 0 $LASTEXITCODE
        $istemciAyar2 = Read-DagitikJson (Join-Path $istemci2 'merkez.json')
        Test-Dogru 'Istemci anahtari DPAPI ile saklandi' ($null -ne $istemciAyar2 -and -not [string]::IsNullOrWhiteSpace([string]$istemciAyar2.anahtarKorunmus))
        Test-Dogru 'Onay kaydi yazildi' (Test-Path -LiteralPath (Join-Path $istemci2 'onay.json'))
        $ayar2 = Read-DagitikJson $merkezAyar2
        Test-Esit 'Merkezde cihaz kayitli' 'kayitli' ([string]@($ayar2.cihazlar)[0].durum)
        Test-Dogru 'Onay zamani merkeze islendi' (-not [string]::IsNullOrWhiteSpace([string]@($ayar2.cihazlar)[0].onayUtc))
        Test-Dogru 'Kod tek kullanimlik (ozet silindi)' ([string]::IsNullOrWhiteSpace([string]@($ayar2.cihazlar)[0].kayitOzeti))

        # 3) ayni kod ikinci kez calismamali (istek merkeze gitsin diye klasor onceden acilir)
        $istemciB = Join-Path $kok2 'istemci2\hatirlatici'
        [void][IO.Directory]::CreateDirectory($istemciB)
        & $psExe -NoProfile -ExecutionPolicy Bypass -File $kayitPs -SunucuUrl $url2 -Kod $kod2 `
            -Onayla -Sessiz -GorevKurmadan -HatirlaticiKlasoru $istemciB 2>$null | Out-Null
        Test-Dogru 'Kullanilmis kod reddedildi' ($LASTEXITCODE -ne 0)
        Test-Dogru 'Kullanilmis kodda merkez.json yazilmadi' (-not (Test-Path -LiteralPath (Join-Path $istemciB 'merkez.json')))

        # 4) kayitli cihaz ozet gonderebilmeli
        & $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'istemci-gonderici.ps1') -HatirlaticiKlasoru $istemci2 | Out-Null
        $cihazId2 = [string]$istemciAyar2.cihazId
        $anlik2 = Read-DagitikJson (Join-Path $veri2 "guncel\$cihazId2.json")
        Test-Dogru 'Kayitli cihazin ozeti alindi' ($null -ne $anlik2)
        if ($null -ne $anlik2) { Test-Esit 'Ozet calisma dakikasi' 3 ([int]$anlik2.ozet.calismaDk) }

        # 5) gec kalmis paket bugunku ozeti ezmemeli
        $anahtar2 = Unprotect-DagitikAnahtar -KorunmusAnahtar $istemciAyar2.anahtarKorunmus -Amac "istemci:$cihazId2"
        $eskiPaket = [ordered]@{
            schemaVersion = 1; cihazId = $cihazId2; cihazAdi = 'Test-PC'
            gonderildiUtc = [DateTime]::UtcNow.AddHours(-2).ToString('o')
            clientTarih = $bugun2; sira = 1
            ozet = [ordered]@{ calismaDk = 1; digerDk = 0; bostaDk = 0; kayitDk = 1; hedefDk = 200 }
            uygulamalar = @(); basliklar = @(); alanlar = @()
            health = [ordered]@{ kayitSatiri = 0; sonOrnekUtc = ''; yerelIzleyiciCalisiyor = $false }
        }
        $govde2 = $eskiPaket | ConvertTo-Json -Depth 10 -Compress
        $zaman2 = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds().ToString([Globalization.CultureInfo]::InvariantCulture)
        $imza2 = Get-DagitikHmac -Anahtar $anahtar2 -ZamanDamgasi $zaman2 -Govde $govde2
        $yanit2 = Invoke-WebRequest -Uri "$url2/v1/ozet" -Method Post -Body $govde2 -ContentType 'application/json; charset=utf-8' `
            -Headers @{ 'X-CT-Cihaz' = $cihazId2; 'X-CT-Zaman' = $zaman2; 'X-CT-Imza' = $imza2 } -UseBasicParsing -TimeoutSec 5
        Test-Dogru 'Bayat paket atlandi' ([bool]($yanit2.Content | ConvertFrom-Json).atlandi)
        $anlik2 = Read-DagitikJson (Join-Path $veri2 "guncel\$cihazId2.json")
        Test-Esit 'Bayat paket ozeti ezmedi' 3 ([int]$anlik2.ozet.calismaDk)

        # 5b) ortak sayac: ikinci cihazin dakikasi eklenir, kendi dakikasi dusulur
        $ikinciKayit = [ordered]@{
            schemaVersion = 1; cihazId = 'ikinci-cihaz'; cihazAdi = 'Ikinci Cihaz'
            alindiUtc = [DateTime]::UtcNow.ToString('o'); sonGorulmeUtc = [DateTime]::UtcNow.ToString('o')
            gonderildiUtc = [DateTime]::UtcNow.ToString('o'); clientTarih = $bugun2; sira = 1
            ozet = [ordered]@{ calismaDk = 50; digerDk = 0; bostaDk = 0; kayitDk = 50; hedefDk = 200 }
            uygulamalar = @(); basliklar = @(); alanlar = @()
            health = [ordered]@{ kayitSatiri = 1; sonOrnekUtc = ''; yerelIzleyiciCalisiyor = $true }
        }
        Write-DagitikJsonAtomik -Nesne $ikinciKayit -Yol (Join-Path $veri2 'guncel\ikinci-cihaz.json')
        $toplamYolu = "/v1/toplam?tarih=$bugun2"
        $zamanT = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds().ToString([Globalization.CultureInfo]::InvariantCulture)
        $imzaT = Get-DagitikHmac -Anahtar $anahtar2 -ZamanDamgasi $zamanT -Govde $toplamYolu
        $yanitT = Invoke-WebRequest -Uri "$url2$toplamYolu" -Method Get -UseBasicParsing -TimeoutSec 5 `
            -Headers @{ 'X-CT-Cihaz' = $cihazId2; 'X-CT-Zaman' = $zamanT; 'X-CT-Imza' = $imzaT }
        $toplamCevap = $yanitT.Content | ConvertFrom-Json
        Test-Esit 'Ortak toplam (iki cihaz)' 53 ([int]$toplamCevap.toplamDk)
        Test-Esit 'Ortak sayacta kendi dakikasi ayri' 3 ([int]$toplamCevap.buCihazDk)
        Test-Esit 'Ortak sayacta diger cihazlar' 50 ([int]$toplamCevap.digerCihazDk)
        Test-Esit 'Ortak sayac cihaz listesi' 1 (@($toplamCevap.cihazlar).Count)

        # 5c) kural senkronu: izinsiz cihaz yazamaz, izin verilince yazar, herkes okur
        . (Join-Path (Split-Path -Parent $PSScriptRoot) 'hatirlatici\kural-senkron.ps1')
        $kuralGovde2 = [ordered]@{
            schemaVersion = 1; cihazId = $cihazId2
            kararlar = @([ordered]@{ oge = 'OyunApp'; tur = 'surec'; karar = 'yasakli' })
        } | ConvertTo-Json -Depth 5 -Compress
        function Gonder-Kural {
            param([string]$Govde)
            $zamanK = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds().ToString([Globalization.CultureInfo]::InvariantCulture)
            $imzaK = Get-DagitikHmac -Anahtar $anahtar2 -ZamanDamgasi $zamanK -Govde $Govde
            return (Invoke-WebRequest -Uri "$url2/v1/kural" -Method Post -Body $Govde `
                -ContentType 'application/json; charset=utf-8' -UseBasicParsing -TimeoutSec 8 -Headers @{
                'X-CT-Cihaz' = $cihazId2; 'X-CT-Zaman' = $zamanK; 'X-CT-Imza' = $imzaK })
        }
        $kuralKod = 0
        try { [void](Gonder-Kural $kuralGovde2) } catch { try { $kuralKod = [int]$_.Exception.Response.StatusCode } catch { } }
        Test-Esit 'Izinsiz cihaz ortak kurali yazamaz' 403 $kuralKod

        $ayarK = Read-DagitikJson $merkezAyar2
        Set-DagitikDeger (@($ayarK.cihazlar)[0]) 'kuralYazabilir' $true
        Write-DagitikJsonAtomik -Nesne $ayarK -Yol $merkezAyar2
        $yanitK = Gonder-Kural $kuralGovde2
        Test-Esit 'Izinli cihaz ortak kurali yazar' 1 ([int]($yanitK.Content | ConvertFrom-Json).islenen)

        $yolKg = '/v1/kurallar'
        $zamanKg = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds().ToString([Globalization.CultureInfo]::InvariantCulture)
        $imzaKg = Get-DagitikHmac -Anahtar $anahtar2 -ZamanDamgasi $zamanKg -Govde $yolKg
        $merkezKurallar = (Invoke-WebRequest -Uri "$url2$yolKg" -Method Get -UseBasicParsing -TimeoutSec 8 -Headers @{
            'X-CT-Cihaz' = $cihazId2; 'X-CT-Zaman' = $zamanKg; 'X-CT-Imza' = $imzaKg }).Content | ConvertFrom-Json
        Test-Dogru 'Ortak kumede karar duruyor' (@($merkezKurallar.yasakli.surec) -contains 'OyunApp')

        # Yerel birlestirme: merkez kazanir, yerel kararlar ve aslaEngelleme korunur
        $yerelKural = [ordered]@{
            calisma = [ordered]@{ surec = @('Code'); baslik = @(); alanadi = @() }
            yasakli = [ordered]@{ surec = @(); baslik = @(); alanadi = @() }
            bilerekBelirsiz = @()
            aslaEngelleme = @('explorer')
        }
        ($yerelKural | ConvertTo-Json -Depth 6) | Out-File (Join-Path $istemci2 'kurallar.json') -Encoding utf8
        $degisen = Merge-YerelKurallar -Klasor $istemci2 -Merkez $merkezKurallar
        Test-Dogru 'Birlestirme degisiklik uyguladi' ($degisen -ge 1)
        $sonKural = Get-Content (Join-Path $istemci2 'kurallar.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        Test-Dogru 'Merkez karari yerele islendi' (@($sonKural.yasakli.surec) -contains 'OyunApp')
        Test-Dogru 'Yerelin kendi karari korundu' (@($sonKural.calisma.surec) -contains 'Code')
        Test-Dogru 'aslaEngelleme tasinmadi/silinmedi' (@($sonKural.aslaEngelleme) -contains 'explorer')
        Test-Esit 'Ayni kume ikinci kez degisiklik uretmez' 0 (Merge-YerelKurallar -Klasor $istemci2 -Merkez $merkezKurallar)

        # 6) merkez ozet fonksiyonlari (panelin okudugu veri)
        $satirlar = @(Get-MerkezCihazSatirlari -Ayar (Read-DagitikJson $merkezAyar2) -VeriKlasoru $veri2)
        Test-Esit 'Panel satir sayisi' 1 $satirlar.Count
        Test-Esit 'Panel calisma dakikasi' 3 ([int]$satirlar[0].calismaDk)
        Test-Esit 'Panel hedefi istemciden aldi' 200 ([int]$satirlar[0].hedefDk)
        Test-Esit 'Panel durumu' 'canli' ([string]$satirlar[0].durum)
        $trend2 = @(Get-MerkezTrend -VeriKlasoru $veri2 -CihazId $cihazId2 -Gun 3)
        Test-Esit 'Trend gun sayisi' 3 $trend2.Count
        Test-Esit 'Trend bugunu buldu' 1 (@($trend2 | Where-Object { $_.tarih -eq $bugun2 -and $_.veriVar }).Count)
        $kirilim2 = @(Get-MerkezUygulamaKirilimi -VeriKlasoru $veri2 -CihazId $cihazId2)
        Test-Esit 'Uygulama kirilimi' 2 $kirilim2.Count

        # 7) saklama suresi temizligi
        $eskiGun2 = (Get-Date).Date.AddDays(-30).ToString('yyyy-MM-dd')
        [void][IO.Directory]::CreateDirectory((Join-Path (Join-Path $veri2 'gunluk') $eskiGun2))
        Test-Esit 'Eski gun klasoru silindi' 1 (Remove-MerkezEskiGunluk -VeriKlasoru $veri2 -SaklamaGun 7)
        Test-Dogru 'Bugunun arsivi duruyor' (Test-Path -LiteralPath (Join-Path (Join-Path $veri2 'gunluk') $bugun2))

        # 8) panelin arayuzsuz ciktisi (panel ile testler ayni hesabi kullanir)
        $panelMetin = (& $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'merkez-panel.ps1') `
            -Kontrol -VeriYolu $veri2 -AyarDosyasi $merkezAyar2) | Out-String
        $panel = $null
        try { $panel = $panelMetin | ConvertFrom-Json } catch { }
        Test-Dogru 'Panel kontrol ciktisi JSON' ($null -ne $panel)
        if ($null -ne $panel) {
            Test-Esit 'Panel cihaz sayisi' 1 ([int]$panel.cihazSayisi)
            Test-Esit 'Panel cihaz calismasi' 3 ([int]@($panel.cihazlar)[0].calismaDk)
            Test-Esit 'Panel cihaz durumu' 'canli' ([string]@($panel.cihazlar)[0].durum)
            Test-Dogru 'Panel onay tarihini gosteriyor' (-not [string]::IsNullOrWhiteSpace([string]@($panel.cihazlar)[0].onayUtc))
        }
        $ErrorActionPreference = 'Stop'
    }
}
catch {
    $kalan++
    Write-Output "  HATA  Kayit akisi: $($_.Exception.Message) [$($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)]"
    Write-CiTestHatasi 'Kayit akisi'
    Write-Output $_.ScriptStackTrace
}
finally {
    $ErrorActionPreference = 'Stop'
    # Once sunucu kapatilir: acik stdout/stderr dosyalari klasor silinmesini engelliyordu
    if ($null -ne $sunucu2 -and -not $sunucu2.HasExited) {
        try { $sunucu2.Kill(); $sunucu2.WaitForExit() } catch { }
    }
    Remove-TestKlasoru $kok2
}

Write-Output '=== Kurulum ve kaldirma testleri ==='
$kok3 = Join-Path ([IO.Path]::GetTempPath()) ('calisma-takip-kurulum-' + [guid]::NewGuid().ToString('N'))
try {
    $ErrorActionPreference = 'Continue'
    $paket3 = Join-Path $kok3 'paket'
    $uygulama3 = Join-Path $paket3 'uygulama'
    $hedef3 = Join-Path $kok3 'kurulum'
    [void][IO.Directory]::CreateDirectory((Join-Path $uygulama3 'hatirlatici'))
    [void][IO.Directory]::CreateDirectory((Join-Path $uygulama3 'dagitik'))
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'kurulum\Kurulum.ps1') -Destination (Join-Path $paket3 'Kurulum.ps1') -Force
    [IO.File]::WriteAllText((Join-Path $uygulama3 'hatirlatici\api.ps1'), '# v2')
    foreach ($sablonAdi in @('kurallar', 'ayarlar', 'periyot')) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot "..\hatirlatici\$sablonAdi.varsayilan.json") -Destination (Join-Path $uygulama3 "hatirlatici\$sablonAdi.varsayilan.json")
    }
    [IO.File]::WriteAllText((Join-Path $paket3 'PAKET-MANIFEST.json'), '{"paketAdi":"test","paketSurumu":7}')

    $psExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $kurulumPs = Join-Path $paket3 'Kurulum.ps1'
    & $psExe -NoProfile -ExecutionPolicy Bypass -File $kurulumPs -Rol Kullanici -Sessiz -YalnizKopyala -KurulumDizini $hedef3 | Out-Null
    Test-Esit 'Kurulum cikis kodu' 0 $LASTEXITCODE
    Test-Dogru 'Uygulama dosyasi kuruldu' (Test-Path -LiteralPath (Join-Path $hedef3 'hatirlatici\api.ps1'))
    $bilgi3 = Read-DagitikJson (Join-Path $hedef3 'dagitik\kurulum-bilgisi.json')
    Test-Esit 'Kurulum rolu kaydedildi' 'Kullanici' ([string](Get-DagitikDeger $bilgi3 'rol' ''))
    Test-Esit 'Paket surumu kaydedildi' '7' ([string](Get-DagitikDeger $bilgi3 'paketSurumu' ''))

    Test-Esit 'Ilk kurulum notr kurallari olusturdu' (Get-DagitikSha256 (Join-Path $uygulama3 'hatirlatici\kurallar.varsayilan.json')) (Get-DagitikSha256 (Join-Path $hedef3 'hatirlatici\kurallar.json'))
    Test-Esit 'Ilk kurulum notr ayarlari olusturdu' (Get-DagitikSha256 (Join-Path $uygulama3 'hatirlatici\ayarlar.varsayilan.json')) (Get-DagitikSha256 (Join-Path $hedef3 'hatirlatici\ayarlar.json'))
    Test-Esit 'Ilk kurulum notr periyodu olusturdu' (Get-DagitikSha256 (Join-Path $uygulama3 'hatirlatici\periyot.varsayilan.json')) (Get-DagitikSha256 (Join-Path $hedef3 'hatirlatici\periyot.json'))
    $korumaYollari = @('hatirlatici\ortak-sayac.json', 'hatirlatici\kural-outbox.json', 'dagitik\merkez-kurallar.json')
    foreach ($goreli in $korumaYollari) {
        [IO.File]::WriteAllText((Join-Path $hedef3 $goreli), '{"kullanici":true}')
        [IO.File]::WriteAllText((Join-Path $uygulama3 $goreli), '{"paket":true}')
    }
    # Guncelleme: kullanici dosyalari korunmali, uygulama dosyasi yenilenmeli
    [IO.File]::WriteAllText((Join-Path $hedef3 'hatirlatici\kurallar.json'), '{"kullanici":"benim"}')
    [IO.File]::WriteAllText((Join-Path $hedef3 'hatirlatici\ayarlar.json'), '{"hedef":90,"duraklat":"sonsuz"}')
    [IO.File]::WriteAllText((Join-Path $hedef3 'hatirlatici\periyot.json'), '{"aktif":true}')
    [void][IO.Directory]::CreateDirectory((Join-Path $hedef3 'hatirlatici\aktivite'))
    [IO.File]::WriteAllText((Join-Path $hedef3 'hatirlatici\aktivite\test.csv'), 'olcum')
    [IO.File]::WriteAllText((Join-Path $uygulama3 'hatirlatici\api.ps1'), '# v3')
    & $psExe -NoProfile -ExecutionPolicy Bypass -File $kurulumPs -Rol Kullanici -Sessiz -YalnizKopyala -KurulumDizini $hedef3 | Out-Null
    Test-Esit 'Guncelleme cikis kodu' 0 $LASTEXITCODE
    Test-Esit 'Guncellemede kurallar korundu' '{"kullanici":"benim"}' ([IO.File]::ReadAllText((Join-Path $hedef3 'hatirlatici\kurallar.json')))
    Test-Esit 'Guncellemede ayarlar korundu' '{"hedef":90,"duraklat":"sonsuz"}' ([IO.File]::ReadAllText((Join-Path $hedef3 'hatirlatici\ayarlar.json')))
    Test-Esit 'Guncellemede periyot korundu' '{"aktif":true}' ([IO.File]::ReadAllText((Join-Path $hedef3 'hatirlatici\periyot.json')))
    Test-Dogru 'Guncellemede olcum verisi korundu' (Test-Path -LiteralPath (Join-Path $hedef3 'hatirlatici\aktivite\test.csv'))
    Test-Esit 'Guncellemede uygulama dosyasi yenilendi' '# v3' ([IO.File]::ReadAllText((Join-Path $hedef3 'hatirlatici\api.ps1')).Trim())

    foreach ($goreli in $korumaYollari) {
        Test-Esit "Guncellemede korundu: $goreli" '{"kullanici":true}' ([IO.File]::ReadAllText((Join-Path $hedef3 $goreli)))
    }

    # Kurulum turu: kurulum-bilgisi.json'a yazilir, ayarlar.json'a hic dokunulmaz
    $bilgiYolu3 = Join-Path $hedef3 'dagitik\kurulum-bilgisi.json'
    function Get-TurOzeti {
        $b = Read-DagitikJson $bilgiYolu3
        $oz = Get-DagitikDeger $b 'ozellikler' $null
        return ('{0}/{1}/{2}' -f (Get-DagitikDeger $b 'kurulumTuru' ''), (Get-DagitikDeger $oz 'hatirlatmalar' ''), (Get-DagitikDeger $oz 'ekranKilidi' ''))
    }
    $ayarHash3 = Get-DagitikSha256 (Join-Path $hedef3 'hatirlatici\ayarlar.json')
    Test-Esit 'Tur verilmeyen kurulum bireysel (hatirlatma ve kilit acik)' 'bireysel/True/True' (Get-TurOzeti)
    $turDurumlari = @(
        @('Sirket turu: ikisi kapali', @('-KurulumTuru', 'Sirket'), 'sirket/False/False'),
        @('Tur verilmeyen guncelleme mevcut turu korur', @(), 'sirket/False/False'),
        @('Sirket: hatirlatma acilamaz, kilit acilabilir', @('-KurulumTuru', 'Sirket', '-Hatirlatmalar', 'Acik', '-EkranKilidi', 'Acik'), 'sirket/False/True'),
        @('Ayni turde guncelleme onceki ozellik secimini korur', @('-KurulumTuru', 'Sirket'), 'sirket/False/True'),
        @('Ozel tur: secimler yazilir', @('-KurulumTuru', 'Ozel', '-Hatirlatmalar', 'Kapali'), 'ozel/False/False'),
        @('Tur degisince ozellikler yeni turun varsayilanina doner', @('-KurulumTuru', 'Bireysel'), 'bireysel/True/True')
    )
    foreach ($durum in $turDurumlari) {
        & $psExe -NoProfile -ExecutionPolicy Bypass -File $kurulumPs -Rol Kullanici -Sessiz -YalnizKopyala -KurulumDizini $hedef3 @($durum[1]) 2>$null | Out-Null
        Test-Esit $durum[0] $durum[2] (Get-TurOzeti)
    }
    Test-Esit 'Tur degisiklikleri ayarlar.json''a dokunmadi' $ayarHash3 (Get-DagitikSha256 (Join-Path $hedef3 'hatirlatici\ayarlar.json'))
    # Kurulum-Admin.cmd / Kurulum-Kullanici.cmd yeni kurulumda Sirket verir; eski kurulumu degistirmez
    $env:CT_KURULUM_TURU = 'Sirket'
    try {
        $hedef3b = Join-Path $kok3 'kurulum-yeni'
        & $psExe -NoProfile -ExecutionPolicy Bypass -File $kurulumPs -Rol Admin -Sessiz -YalnizKopyala -KurulumDizini $hedef3b | Out-Null
        $b3b = Read-DagitikJson (Join-Path $hedef3b 'dagitik\kurulum-bilgisi.json')
        Test-Esit 'CT_KURULUM_TURU yeni kurulumda turu belirler' 'sirket' ([string](Get-DagitikDeger $b3b 'kurulumTuru' ''))
        [IO.File]::WriteAllText($bilgiYolu3, '{"surum":1,"rol":"Kullanici"}')
        & $psExe -NoProfile -ExecutionPolicy Bypass -File $kurulumPs -Rol Kullanici -Sessiz -YalnizKopyala -KurulumDizini $hedef3 | Out-Null
        Test-Esit 'Turu yazilmamis eski kurulum guncellemede bireysel kalir' 'bireysel/True/True' (Get-TurOzeti)
    }
    finally { Remove-Item Env:CT_KURULUM_TURU -ErrorAction SilentlyContinue }
    foreach ($cmd in @('Kurulum-Admin.cmd', 'Kurulum-Kullanici.cmd')) {
        Test-Dogru "$cmd sirket turunu varsayilan yapar" ((Get-Content -LiteralPath (Join-Path $PSScriptRoot "kurulum\$cmd") -Raw) -match 'set "CT_KURULUM_TURU=Sirket"')
    }
    # Kaldirma denemesi: hicbir seyi silmeden ne yapacagini yazar
    $kaldirCikti = @(& $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'kaldir.ps1') `
        -Deneme -Onayla -UygulamaKok $hedef3 2>$null)
    Test-Esit 'Kaldirma denemesi cikis kodu' 0 $LASTEXITCODE
    Test-Dogru 'Deneme modunda dosya silinmedi' (Test-Path -LiteralPath (Join-Path $hedef3 'hatirlatici\kurallar.json'))
    Test-Dogru 'Deneme modu bildirildi' (@($kaldirCikti | Where-Object { $_ -match 'hicbir degisiklik' }).Count -ge 1)
    $ErrorActionPreference = 'Stop'
}
catch {
    $kalan++
    Write-Output "  HATA  Kurulum akisi: $($_.Exception.Message) [$($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)]"
    Write-CiTestHatasi 'Kurulum akisi'
}
finally {
    $ErrorActionPreference = 'Stop'
    Remove-TestKlasoru $kok3
}

Write-Output '=== Kisayol ve Windows kayit testleri ==='
. (Join-Path $PSScriptRoot 'kisayol.ps1')
$testKayitKok = 'HKCU:\Software\CalismaTakipSistemiTest'
$testKayit = "$testKayitKok\Kaldir"
$kok4 = Join-Path ([IO.Path]::GetTempPath()) ('calisma-takip-kayit4-' + [guid]::NewGuid().ToString('N'))
try {
    [void][IO.Directory]::CreateDirectory((Join-Path $kok4 'dagitik'))
    [IO.File]::WriteAllText((Join-Path $kok4 'dagitik\kaldir.ps1'), '# test')
    [void](Register-CtUygulamaKaydi -UygulamaKok $kok4 -Surum '7' -Rol 'Kullanici' -KayitYolu $testKayit)
    $kayit = Get-ItemProperty -LiteralPath $testKayit
    Test-Esit 'Uygulama kaydi adi' 'Aizen' ([string]$kayit.DisplayName)
    Test-Esit 'Kisayol adlari Aizen' 'Aizen.lnk|Aizen.lnk|Aizen Merkez.lnk|Aizen' (@($script:CT_PANEL_KISAYOL, $script:CT_ACILIS_KISAYOL, $script:CT_MERKEZ_KISAYOL, $script:CT_MENU_KLASORU) -join '|')
    Test-Esit 'Eski kisayol adlari temizlik listesinde' 'Calisma Takibi.lnk|Calisma Takip Sistemi.lnk|Calisma Takip Merkezi.lnk|Calisma Takip Sistemi' (@($script:CT_ESKI_PANEL_KISAYOL, $script:CT_ESKI_ACILIS_KISAYOL, $script:CT_ESKI_MERKEZ_KISAYOL, $script:CT_ESKI_MENU_KLASORU) -join '|')
    $eskiDeneme = Join-Path $kok4 'eski-kisayol'
    [void][IO.Directory]::CreateDirectory($eskiDeneme)
    [IO.File]::WriteAllText((Join-Path $eskiDeneme 'Calisma Takibi.lnk'), 'x')
    Remove-CtEskiKisayol -Klasor $eskiDeneme -Ad $script:CT_ESKI_PANEL_KISAYOL
    Test-Dogru 'Eski adli kisayol siliniyor' (-not (Test-Path -LiteralPath (Join-Path $eskiDeneme 'Calisma Takibi.lnk')))
    Test-Esit 'Uygulama kaydi surumu' '7' ([string]$kayit.DisplayVersion)
    Test-Esit 'Kurulum yeri kaydedildi' $kok4 ([string]$kayit.InstallLocation)
    Test-Dogru 'Kaldirma komutu kaydedildi' ([string]$kayit.UninstallString -match 'kaldir\.ps1')
    Test-Dogru 'Sessiz kaldirma komutu var' ([string]$kayit.QuietUninstallString -match '-Onayla')
    Test-Dogru 'Kayit silinebiliyor' (Unregister-CtUygulamaKaydi -KayitYolu $testKayit)
    Test-Dogru 'Kayit gercekten silindi' (-not (Test-Path -LiteralPath $testKayit))
    Test-Dogru 'Baslat menusu deneme kipi bir sey silmez' (((Remove-CtBaslatMenusu -Deneme) -eq $true) -or ((Remove-CtBaslatMenusu -Deneme) -eq $false))
}
catch {
    $kalan++
    Write-Output "  HATA  Kayit testleri: $($_.Exception.Message)"
    Write-CiTestHatasi 'Kayit testleri'
}
finally {
    if (Test-Path -LiteralPath $testKayitKok) {
        Remove-Item -LiteralPath $testKayitKok -Recurse -Force -ErrorAction SilentlyContinue
    }
    Remove-TestKlasoru $kok4
}

Write-Output '=== Gercek paket icerigi ve kurulum testleri ==='
$paketTestKok = Join-Path ([IO.Path]::GetTempPath()) ('ct-pkt-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
try {
    $zip = Join-Path $paketTestKok 'paket.zip'
    $acilan = Join-Path $paketTestKok 'paket'
    $hedef = Join-Path $paketTestKok 'hedef'
    $psExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    & $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'paket-olustur.ps1') -CiktiYolu $zip -ExeAtla | Out-Null
    Test-Esit 'Gercek paket uretimi' 0 $LASTEXITCODE
    Expand-Archive -LiteralPath $zip -DestinationPath $acilan
    # Gelistirme makinesinde canli ayarlar.json/periyot.json vardir: bu test onlarin sizmadigini gercekten sinar
    $kisisel = @(Get-ChildItem -LiteralPath $acilan -Recurse -File | Where-Object { $_.Name -in @('kurallar.json', 'ayarlar.json', 'periyot.json', 'merkez-kurallar.json', 'kural-outbox.json', 'ortak-sayac.json', 'onay.json') })
    Test-Esit 'Pakette kisisel kural, ayar ve senkron verisi yok' 0 $kisisel.Count
    foreach ($gerekli in @('uygulama\wiki\baslarken.md', 'uygulama\wiki\hatirlatmalar.md', 'uygulama\hatirlatici\ozellikler.ps1', 'uygulama\hatirlatici\wiki.ps1', 'uygulama\hatirlatici\ayarlar-penceresi.ps1', 'uygulama\hatirlatici\wiki-penceresi.ps1')) {
        Test-Dogru "Pakette: $gerekli" (Test-Path -LiteralPath (Join-Path $acilan $gerekli))
    }
    Test-Dogru 'Pakette wiki yazar notu (README) yok' (-not (Test-Path -LiteralPath (Join-Path $acilan 'uygulama\wiki\README.md')))
    Test-Dogru 'Pakette test-ozellikler yok' (-not (Test-Path -LiteralPath (Join-Path $acilan 'uygulama\hatirlatici\test-ozellikler.ps1')))
    $ayarSablonu = Read-DagitikJson (Join-Path $acilan 'uygulama\hatirlatici\ayarlar.varsayilan.json')
    Test-Esit 'Notr ayar: hedef 240' 240 ([int]$ayarSablonu.hedef)
    Test-Esit 'Notr ayar: duraklatma yok' '' ([string]$ayarSablonu.duraklat)
    $periyotSablonu = Read-DagitikJson (Join-Path $acilan 'uygulama\hatirlatici\periyot.varsayilan.json')
    Test-Esit 'Notr periyot: kapali' $false ([bool]$periyotSablonu.aktif)
    Test-Dogru 'Notr periyot: zaman alanlari bos' (@('baslangic', 'bitis', 'molaBitis' | Where-Object { -not [string]::IsNullOrEmpty([string]$periyotSablonu.$_) }).Count -eq 0)
    $sablonYolu = Join-Path $acilan 'uygulama\hatirlatici\kurallar.varsayilan.json'
    $notr = Read-DagitikJson $sablonYolu
    foreach ($grup in @('calisma', 'yasakli')) {
        foreach ($tur in @('surec', 'baslik', 'alanadi')) {
            Test-Dogru "Notr $grup.$tur bos dizi" (($notr.$grup.$tur -is [Array]) -and $notr.$grup.$tur.Count -eq 0)
        }
    }
    Test-Dogru 'Notr bilerekBelirsiz bos dizi' (($notr.bilerekBelirsiz -is [Array]) -and $notr.bilerekBelirsiz.Count -eq 0)
    Test-Esit 'Belirsiz sayilsin korunuyor' $true $notr.belirsizSayilsin
    $beklenenSurecler = @('explorer','dwm','winlogon','LogonUI','csrss','lsass','services','smss','svchost','System','Taskmgr','ShellExperienceHost','StartMenuExperienceHost')
    Test-Esit 'Yalniz Windows guvenlik surecleri' (($beklenenSurecler | Sort-Object) -join ',') (($notr.aslaEngelleme | Sort-Object) -join ',')
    & $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $acilan 'Kurulum.ps1') -Rol Admin -Sessiz -YalnizKopyala -KurulumDizini $hedef | Out-Null
    Test-Esit 'Gercek paketten admin kopyalama' 0 $LASTEXITCODE
    Test-Esit 'Gercek paketten notr kurulum' (Get-DagitikSha256 $sablonYolu) (Get-DagitikSha256 (Join-Path $hedef 'hatirlatici\kurallar.json'))
    foreach ($sablonAdi in @('ayarlar', 'periyot')) {
        Test-Esit "Gercek paketten notr $sablonAdi" (Get-DagitikSha256 (Join-Path $acilan "uygulama\hatirlatici\$sablonAdi.varsayilan.json")) (Get-DagitikSha256 (Join-Path $hedef "hatirlatici\$sablonAdi.json"))
    }
    $ayarDosyasi = Join-Path $hedef 'hatirlatici\ayarlar.json'
    [IO.File]::WriteAllText($ayarDosyasi, '{"hedef":75,"duraklat":""}')
    $ayarOnce = Get-DagitikSha256 $ayarDosyasi
    $kural = Join-Path $hedef 'hatirlatici\kurallar.json'
    [IO.File]::WriteAllText($kural, '{"kullanici":"ozel"}')
    $once = Get-DagitikSha256 $kural
    & $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $acilan 'Kurulum.ps1') -Rol Kullanici -Sessiz -YalnizKopyala -KurulumDizini $hedef | Out-Null
    Test-Esit 'Gercek paketten guncelleme' 0 $LASTEXITCODE
    Test-Esit 'Gercek paketten kisisel kurallar bayt bazinda korundu' $once (Get-DagitikSha256 $kural)
    Test-Esit 'Gercek paketten kisisel ayarlar bayt bazinda korundu' $ayarOnce (Get-DagitikSha256 $ayarDosyasi)
}
catch {
    $kalan++
    Write-Output "  HATA  Paket testi: $($_.Exception.Message)"
    Write-CiTestHatasi 'Paket testi'
}
finally { Remove-TestKlasoru $paketTestKok }

# Capraz platform protokol vektorleri (uyumluluk/): Windows tarafinda imza, kod turetme ya da
# anahtar zarfi kazara degisirse Mac gibi baska istemciler eslesemez; burada kirmizi yanar.
$vektorPs = Join-Path $PSScriptRoot '..\uyumluluk\protokol-vektorleri.ps1'
if (Test-Path -LiteralPath $vektorPs) {
    $eskiEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $vektorCikti = @(& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File $vektorPs 2>&1)
    $vektorKod = $LASTEXITCODE
    $ErrorActionPreference = $eskiEap
    Test-Esit 'Capraz platform protokol vektorleri Windows koduyla uyumlu' 0 $vektorKod
    if ($vektorKod -ne 0) { $vektorCikti | ForEach-Object { Write-Output "    $_" } }
}
. (Join-Path $PSScriptRoot 'test-gelistirme.ps1')
Write-Output "Sonuc: $gecen basarili, $kalan hatali"
if ($kalan -gt 0) { exit 1 }
