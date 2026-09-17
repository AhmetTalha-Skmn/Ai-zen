# Posta kutusu sunucusu API testleri. Windows PowerShell 5.1 ve PowerShell 7 (Linux) ile calisir.
# Sunucuyu gecici bir veri klasoruyle 127.0.0.1 uzerinde baslatir; sifreleme kullanmaz (sahte zarflar):
# sunucunun kimlik denetimi, birlestirme, yalitim, kota ve boyut sinirlari sinanir.
$ErrorActionPreference = 'Stop'
$gecen = 0; $kalan = 0
function Test-Esit { param([string]$Ad, [object]$Beklenen, [object]$Gercek) if ($Beklenen -ceq $Gercek) { $script:gecen++; Write-Output "  OK  $Ad" } else { $script:kalan++; Write-Output "  HATA  $Ad | beklenen=[$Beklenen] gercek=[$Gercek]"; if ($env:GITHUB_ACTIONS -eq 'true') { Write-Output "::error title=Aizen posta test::$Ad" } } }
function Test-Dogru { param([string]$Ad, [bool]$Kosul) if ($Kosul) { $script:gecen++; Write-Output "  OK  $Ad" } else { $script:kalan++; Write-Output "  HATA  $Ad"; if ($env:GITHUB_ACTIONS -eq 'true') { Write-Output "::error title=Aizen posta test::$Ad" } } }

function Get-Ozet {
    param([string]$Metin)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Metin)))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}
function New-Hex {
    param([int]$Bayt = 32)
    $b = New-Object byte[] $Bayt
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($b) } finally { $rng.Dispose() }
    return ([BitConverter]::ToString($b)).Replace('-', '').ToLowerInvariant()
}
function Invoke-Http {
    param([string]$Uri, [string]$Yontem = 'GET', [hashtable]$Basliklar = @{}, [string]$Govde)
    $p = @{ Uri = $Uri; Method = $Yontem; Headers = $Basliklar; UseBasicParsing = $true; TimeoutSec = 20 }
    if ($PSBoundParameters.ContainsKey('Govde')) { $p.Body = [Text.Encoding]::UTF8.GetBytes($Govde); $p.ContentType = 'application/json; charset=utf-8' }
    try {
        $y = Invoke-WebRequest @p
        $icerik = $y.Content
        if ($icerik -is [byte[]]) { $icerik = [Text.Encoding]::UTF8.GetString($icerik) }
        $json = $null
        try { $json = $icerik | ConvertFrom-Json } catch { }
        return [pscustomobject]@{ Kod = [int]$y.StatusCode; Json = $json }
    }
    catch {
        $kod = 0
        try { $kod = [int]$_.Exception.Response.StatusCode } catch { }
        return [pscustomobject]@{ Kod = $kod; Json = $null }
    }
}
function New-SahteZarf {
    param([string]$Cihaz, [string]$Yon = 'istek', [string]$Tur = 'ozet', [long]$Sayac = 1)
    return [ordered]@{ v = 2; cihaz = $Cihaz; tur = $Tur; yon = $Yon; sayac = $Sayac; zaman = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds(); iv = 'AAAAAAAAAAAAAAAAAAAAAA=='; veri = 'QUJDREVGR0hJSktMTU5PUA=='; etiket = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=' }
}
function ConvertTo-Json1 { param([object]$Nesne) return ($Nesne | ConvertTo-Json -Depth 6 -Compress) }

$exe = (Get-Process -Id $PID).Path
$betik = Join-Path $PSScriptRoot 'posta-sunucu.ps1'
$kok = Join-Path ([IO.Path]::GetTempPath()) ('aizen-posta-test-' + [guid]::NewGuid().ToString('N').Substring(0, 10))
$veri = Join-Path $kok 'veri'
$sunucu = $null
Write-Output '=== Posta kutusu sunucusu API ==='
try {
    [void][IO.Directory]::CreateDirectory($kok)
    $uret = @(& $exe -NoProfile -ExecutionPolicy Bypass -File $betik -VeriKlasoru $veri -YonetimJetonuUret 2>&1 | ForEach-Object { [string]$_ })
    $yonetim = [string]@($uret | Where-Object { $_ -cmatch '^[A-Za-z0-9_-]{32,128}$' } | Select-Object -Last 1)[0]
    Test-Dogru 'Yonetim jetonu uretildi' ($yonetim.Length -ge 32)

    $port = Get-Random -Minimum 37000 -Maximum 41000
    $url = "http://127.0.0.1:$port"
    $argumanlar = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$betik`"", '-VeriKlasoru', "`"$veri`"", '-Dinle', '127.0.0.1', '-Port', "$port", '-CalismaSuresiSn', '300')
    $sunucu = Start-Process -FilePath $exe -ArgumentList $argumanlar -PassThru `
        -RedirectStandardOutput (Join-Path $kok 'sunucu.stdout') -RedirectStandardError (Join-Path $kok 'sunucu.stderr')
    $hazir = $false
    for ($i = 0; $i -lt 80 -and -not $hazir; $i++) { if ((Invoke-Http "$url/saglik").Kod -eq 200) { $hazir = $true } else { Start-Sleep -Milliseconds 250 } }
    Test-Dogru 'Sunucu hazir' $hazir
    if (-not $hazir) {
        if (Test-Path -LiteralPath (Join-Path $kok 'sunucu.stderr')) { Write-Output ('  stderr: ' + ([IO.File]::ReadAllText((Join-Path $kok 'sunucu.stderr')) -replace '\s+', ' ')) }
        throw 'Sunucu baslamadi.'
    }

    $kutu = New-Hex 16
    $merkezJetonu = New-Hex 32
    $yH = @{ 'X-Aizen-Yonetim' = $yonetim }
    Test-Esit 'Yanlis yonetim jetonu 401' 401 (Invoke-Http "$url/r1/kutu" 'POST' @{ 'X-Aizen-Yonetim' = ('a' * 43) } -Govde (ConvertTo-Json1 @{ kutu = $kutu; merkezJetonOzeti = (Get-Ozet $merkezJetonu) })).Kod
    Test-Esit 'Gecersiz kutu kimligi 400' 400 (Invoke-Http "$url/r1/kutu" 'POST' $yH -Govde (ConvertTo-Json1 @{ kutu = '../x'; merkezJetonOzeti = (Get-Ozet $merkezJetonu) })).Kod
    Test-Esit 'Kutu olusturuldu' 200 (Invoke-Http "$url/r1/kutu" 'POST' $yH -Govde (ConvertTo-Json1 @{ kutu = $kutu; merkezJetonOzeti = (Get-Ozet $merkezJetonu) })).Kod

    $mH = @{ 'X-Aizen-Kutu' = $kutu; 'X-Aizen-Jeton' = $merkezJetonu }
    Test-Esit 'Yanlis merkez jetonu 401' 401 (Invoke-Http "$url/r1/merkez/gelen" 'GET' @{ 'X-Aizen-Kutu' = $kutu; 'X-Aizen-Jeton' = (New-Hex 32) }).Kod
    $bos = Invoke-Http "$url/r1/merkez/gelen" 'GET' $mH
    Test-Dogru 'Merkez bos kutuyu okur' ($bos.Kod -eq 200 -and @($bos.Json.mesajlar).Count -eq 0)

    $j1 = New-Hex 32; $j2 = New-Hex 32; $jk = New-Hex 32
    $kanal = 'k-' + (New-Hex 12)
    $simdi = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $liste = @(
        @{ cihaz = 'pc-1'; jetonOzeti = (Get-Ozet $j1); bitis = 0 },
        @{ cihaz = 'pc-2'; jetonOzeti = (Get-Ozet $j2); bitis = ($simdi + 3600) },
        @{ cihaz = $kanal; jetonOzeti = (Get-Ozet $jk); bitis = ($simdi - 10) }
    )
    Test-Esit 'Gecersiz cihaz listesi 400' 400 (Invoke-Http "$url/r1/merkez/cihazlar" 'POST' $mH -Govde (ConvertTo-Json1 @{ cihazlar = @(@{ cihaz = '../x'; jetonOzeti = 'z'; bitis = 0 }) })).Kod
    Test-Esit 'Cihaz listesi kaydedildi' 200 (Invoke-Http "$url/r1/merkez/cihazlar" 'POST' $mH -Govde (ConvertTo-Json1 @{ cihazlar = $liste })).Kod

    $c1 = @{ 'X-Aizen-Kutu' = $kutu; 'X-Aizen-Cihaz' = 'pc-1'; 'X-Aizen-Jeton' = $j1 }
    $c2 = @{ 'X-Aizen-Kutu' = $kutu; 'X-Aizen-Cihaz' = 'pc-2'; 'X-Aizen-Jeton' = $j2 }
    Test-Esit 'Cihaz baska cihazin jetonuyla giremez' 401 (Invoke-Http "$url/r1/cihaz/gelen" 'GET' @{ 'X-Aizen-Kutu' = $kutu; 'X-Aizen-Cihaz' = 'pc-1'; 'X-Aizen-Jeton' = $j2 }).Kod
    Test-Esit 'Suresi dolmus kayit kanali 401' 401 (Invoke-Http "$url/r1/cihaz/gonder" 'POST' @{ 'X-Aizen-Kutu' = $kutu; 'X-Aizen-Cihaz' = $kanal; 'X-Aizen-Jeton' = $jk } -Govde (ConvertTo-Json1 @{ anahtar = ''; zarf = (New-SahteZarf $kanal) })).Kod
    Test-Esit 'Kayitsiz kutu 401' 401 (Invoke-Http "$url/r1/cihaz/gelen" 'GET' @{ 'X-Aizen-Kutu' = (New-Hex 16); 'X-Aizen-Cihaz' = 'pc-1'; 'X-Aizen-Jeton' = $j1 }).Kod

    Test-Esit 'Birlestirmeli zarf 1' 200 (Invoke-Http "$url/r1/cihaz/gonder" 'POST' $c1 -Govde (ConvertTo-Json1 @{ anahtar = 'ozet-2026-09-17'; zarf = (New-SahteZarf 'pc-1' -Sayac 1) })).Kod
    Test-Esit 'Birlestirmeli zarf 2 (eskisinin yerine)' 200 (Invoke-Http "$url/r1/cihaz/gonder" 'POST' $c1 -Govde (ConvertTo-Json1 @{ anahtar = 'ozet-2026-09-17'; zarf = (New-SahteZarf 'pc-1' -Sayac 2) })).Kod
    Test-Esit 'Birlestirmesiz zarf 1' 200 (Invoke-Http "$url/r1/cihaz/gonder" 'POST' $c1 -Govde (ConvertTo-Json1 @{ anahtar = ''; zarf = (New-SahteZarf 'pc-1' -Tur 'kural' -Sayac 3) })).Kod
    Test-Esit 'Birlestirmesiz zarf 2' 200 (Invoke-Http "$url/r1/cihaz/gonder" 'POST' $c1 -Govde (ConvertTo-Json1 @{ anahtar = ''; zarf = (New-SahteZarf 'pc-1' -Tur 'kural' -Sayac 4) })).Kod
    Test-Esit 'Ikinci cihazin zarfi' 200 (Invoke-Http "$url/r1/cihaz/gonder" 'POST' $c2 -Govde (ConvertTo-Json1 @{ anahtar = 'ozet-2026-09-17'; zarf = (New-SahteZarf 'pc-2') })).Kod
    Test-Esit 'Baska cihaz adina zarf 400' 400 (Invoke-Http "$url/r1/cihaz/gonder" 'POST' $c1 -Govde (ConvertTo-Json1 @{ anahtar = ''; zarf = (New-SahteZarf 'pc-2') })).Kod
    Test-Esit 'Cihaz yanit zarfi birakamaz 400' 400 (Invoke-Http "$url/r1/cihaz/gonder" 'POST' $c1 -Govde (ConvertTo-Json1 @{ anahtar = ''; zarf = (New-SahteZarf 'pc-1' -Yon 'yanit') })).Kod
    Test-Esit 'Gecersiz birlestirme anahtari 400' 400 (Invoke-Http "$url/r1/cihaz/gonder" 'POST' $c1 -Govde (ConvertTo-Json1 @{ anahtar = 'A B'; zarf = (New-SahteZarf 'pc-1') })).Kod
    Test-Esit 'Bozuk JSON 400' 400 (Invoke-Http "$url/r1/cihaz/gonder" 'POST' $c1 -Govde '{bozuk').Kod

    $gelen = Invoke-Http "$url/r1/merkez/gelen?en=50" 'GET' $mH
    $mesajlar = @($gelen.Json.mesajlar)
    Test-Esit 'Merkez 4 mesaj gorur (birlestirme sonrasi)' 4 $mesajlar.Count
    $pc1Ozet = @($mesajlar | Where-Object { $_.cihaz -eq 'pc-1' -and $_.anahtar -eq 'ozet-2026-09-17' })
    Test-Dogru 'Birlestirmede en yeni zarf kaldi' ($pc1Ozet.Count -eq 1 -and [int]$pc1Ozet[0].zarf.sayac -eq 2)
    $nolar = @($mesajlar | ForEach-Object { [long]$_.no })
    Test-Dogru 'Mesajlar eskiden yeniye' ((($nolar | Sort-Object) -join ',') -eq ($nolar -join ','))
    Test-Esit 'en=1 tek mesaj doner' 1 @((Invoke-Http "$url/r1/merkez/gelen?en=1" 'GET' $mH).Json.mesajlar).Count

    $gonder = Invoke-Http "$url/r1/merkez/gonder" 'POST' $mH -Govde (ConvertTo-Json1 @{ mesajlar = @(
        @{ cihaz = 'pc-1'; anahtar = 'kurallar'; zarf = (New-SahteZarf 'pc-1' -Yon 'yanit' -Tur 'kurallar' -Sayac 5) },
        @{ cihaz = 'pc-1'; anahtar = 'kurallar'; zarf = (New-SahteZarf 'pc-1' -Yon 'yanit' -Tur 'kurallar' -Sayac 6) },
        @{ cihaz = 'bilinmeyen'; anahtar = ''; zarf = (New-SahteZarf 'bilinmeyen' -Yon 'yanit') },
        @{ cihaz = 'pc-1'; anahtar = ''; zarf = (New-SahteZarf 'pc-1' -Yon 'istek') }
    ) })
    Test-Dogru 'Merkez yanitlari: bilinmeyen cihaz ve yanlis yon atlandi' ($gonder.Kod -eq 200 -and [int]$gonder.Json.kaydedilen -eq 2 -and [int]$gonder.Json.atlanan -eq 2)
    $g1 = Invoke-Http "$url/r1/cihaz/gelen" 'GET' $c1
    Test-Dogru 'Cihaz yalnizca en yeni kurallar yanitini alir' ($g1.Kod -eq 200 -and @($g1.Json.mesajlar).Count -eq 1 -and [int]@($g1.Json.mesajlar)[0].zarf.sayac -eq 6)
    Test-Esit 'Diger cihaz baskasinin yanitini goremez' 0 @((Invoke-Http "$url/r1/cihaz/gelen" 'GET' $c2).Json.mesajlar).Count
    Test-Esit 'Cihaz onayi' 1 ([int](Invoke-Http "$url/r1/cihaz/onay" 'POST' $c1 -Govde (ConvertTo-Json1 @{ nolar = @([long]@($g1.Json.mesajlar)[0].no) })).Json.silinen)
    Test-Esit 'Onaydan sonra cihaz kutusu bos' 0 @((Invoke-Http "$url/r1/cihaz/gelen" 'GET' $c1).Json.mesajlar).Count
    Test-Esit 'Cihaz merkezin mesajlarini silemez' 0 ([int](Invoke-Http "$url/r1/cihaz/onay" 'POST' $c1 -Govde (ConvertTo-Json1 @{ nolar = $nolar })).Json.silinen)
    Test-Esit 'Merkez onayi' 4 ([int](Invoke-Http "$url/r1/merkez/onay" 'POST' $mH -Govde (ConvertTo-Json1 @{ nolar = $nolar })).Json.silinen)
    Test-Esit 'Onaydan sonra merkez kutusu bos' 0 @((Invoke-Http "$url/r1/merkez/gelen" 'GET' $mH).Json.mesajlar).Count

    $buyuk = '{"anahtar":"","zarf":{"v":2,"veri":"' + ('A' * 1700000) + '"}}'
    $buyukKod = (Invoke-Http "$url/r1/cihaz/gonder" 'POST' $c1 -Govde $buyuk).Kod
    Test-Dogru 'Buyuk govde reddedildi' ($buyukKod -eq 413 -or $buyukKod -eq 0)
    Test-Esit 'Sunucu buyuk govdeden sonra calisiyor' 200 (Invoke-Http "$url/saglik").Kod

    $kotaKodu = 0
    [void](Invoke-Http "$url/r1/cihaz/gonder" 'POST' $c2 -Govde (ConvertTo-Json1 @{ anahtar = 'ozet-2026-09-17'; zarf = (New-SahteZarf 'pc-2' -Sayac 500) }))
    for ($i = 1; $i -le 201; $i++) {
        $kotaKodu = (Invoke-Http "$url/r1/cihaz/gonder" 'POST' $c2 -Govde (ConvertTo-Json1 @{ anahtar = ''; zarf = (New-SahteZarf 'pc-2' -Tur 'kural' -Sayac $i) })).Kod
        if ($kotaKodu -ne 200) { break }
    }
    Test-Esit 'Cihaz basina kota (200 bekleyen mesaj)' 429 $kotaKodu
    Test-Esit 'Kota dolunca yeni zarf da kabul edilmez' 429 (Invoke-Http "$url/r1/cihaz/gonder" 'POST' $c2 -Govde (ConvertTo-Json1 @{ anahtar = 'toplam'; zarf = (New-SahteZarf 'pc-2' -Tur 'toplam') })).Kod
    Test-Esit 'Kota doluyken bekleyen ozetin guncellenmesi yapilir' 200 (Invoke-Http "$url/r1/cihaz/gonder" 'POST' $c2 -Govde (ConvertTo-Json1 @{ anahtar = 'ozet-2026-09-17'; zarf = (New-SahteZarf 'pc-2' -Sayac 999) })).Kod

    $yeniMerkez = New-Hex 32
    Test-Esit 'Merkez jetonu yenilendi' 200 (Invoke-Http "$url/r1/kutu" 'POST' $yH -Govde (ConvertTo-Json1 @{ kutu = $kutu; merkezJetonOzeti = (Get-Ozet $yeniMerkez) })).Kod
    Test-Esit 'Eski merkez jetonu gecersiz' 401 (Invoke-Http "$url/r1/merkez/gelen" 'GET' $mH).Kod
    Test-Esit 'Yeni merkez jetonu gecerli' 200 (Invoke-Http "$url/r1/merkez/gelen" 'GET' @{ 'X-Aizen-Kutu' = $kutu; 'X-Aizen-Jeton' = $yeniMerkez }).Kod
    Test-Esit 'Jeton yenilemede cihazlar korunur' 200 (Invoke-Http "$url/r1/cihaz/gelen" 'GET' $c1).Kod
    Test-Esit 'Bilinmeyen yol 404' 404 (Invoke-Http "$url/r1/yok" 'GET' $c1).Kod

    $disk = (@(Get-ChildItem -LiteralPath $veri -Recurse -File | ForEach-Object { [IO.File]::ReadAllText($_.FullName) }) -join "`n")
    Test-Dogru 'Diskte jetonlarin kendisi yok' ($disk -notmatch $j1 -and $disk -notmatch $merkezJetonu -and $disk -notmatch [regex]::Escape($yonetim))

    # En sonda: hatali kimlik denemeleri adresi 10 dakika kilitler
    $sinirKodu = 0
    for ($i = 0; $i -lt 70; $i++) {
        $sinirKodu = (Invoke-Http "$url/r1/cihaz/gelen" 'GET' @{ 'X-Aizen-Kutu' = $kutu; 'X-Aizen-Cihaz' = 'pc-1'; 'X-Aizen-Jeton' = (New-Hex 32) }).Kod
        if ($sinirKodu -eq 429) { break }
    }
    Test-Esit 'Hatali kimlik denemesi siniri' 429 $sinirKodu
    Test-Esit 'Kilitli adres dogru jetonla da bekler' 429 (Invoke-Http "$url/r1/cihaz/gelen" 'GET' $c1).Kod
    Test-Esit 'Saglik ucu kilitte de acik' 200 (Invoke-Http "$url/saglik").Kod
}
catch {
    $kalan++
    Write-Output "  HATA  Posta testi: $($_.Exception.Message) [$($_.InvocationInfo.ScriptLineNumber)]"
}
finally {
    if ($null -ne $sunucu -and -not $sunucu.HasExited) { try { $sunucu.Kill(); [void]$sunucu.WaitForExit(5000) } catch { } }
    if (Test-Path -LiteralPath $kok) { Remove-Item -LiteralPath $kok -Recurse -Force -ErrorAction SilentlyContinue }
}
Write-Output "Sonuc: $gecen basarili, $kalan hatali"
if ($kalan -gt 0) { exit 1 }
exit 0
