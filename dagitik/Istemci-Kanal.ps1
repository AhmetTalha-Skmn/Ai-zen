# İstemci v2 gönderimi: şifreli zarf (uyumluluk/PROTOKOL-V2.md).
#
# Kanal seçimi her turda yapılır: merkez.json'daki doğrudan adresler (yerel ağ, port
# yönlendirme) sırayla denenir; hiçbiri yanıt vermezse ya da bağlantı tur ortasında
# koparsa posta kutusu kullanılır. Posta kutusunda zarflar merkez açılana kadar bekler,
# yanıtlar bir sonraki turda alınır.
#
# istemci-gonderici.ps1 içinden yüklenir: GondericiLog, Set-GondericiDurumu, $ayarYolu,
# $outboxKlasoru, $redKlasoru, $HatirlaticiKlasoru ve Senkron-Durum.ps1 oradan gelir.

function Get-IstemciYeniSayac {
    param([object]$Ayar)
    [long]$sayac = 0
    [void][long]::TryParse([string](Get-DagitikDeger $Ayar 'sayac' 0), [ref]$sayac)
    $sayac++
    Set-DagitikDeger $Ayar 'sayac' $sayac
    # Sayaç zarf gönderilmeden diske yazılır: çökme sonrası aynı sayaç yeniden kullanılmaz
    Write-DagitikJsonAtomik -Nesne $Ayar -Yol $ayarYolu
    return $sayac
}

function Get-IstemciYanitIcerigi {
    param([object]$Yanit)
    $icerik = $Yanit.Content
    if ($icerik -is [byte[]]) { $icerik = [System.Text.Encoding]::UTF8.GetString($icerik) }
    if ([string]::IsNullOrWhiteSpace([string]$icerik)) { return $null }
    return ([string]$icerik | ConvertFrom-Json)
}

function Select-IstemciDogrudanAdres {
    param([object]$Ayar)
    $adaylar = @([string](Get-DagitikDeger $Ayar 'sunucuUrl' '')) + @(Get-DagitikDeger $Ayar 'ekAdresler' @())
    foreach ($aday in $adaylar) {
        $a = ConvertFrom-DagitikAdres ([string]$aday)
        if ($null -eq $a -or $a.tur -ne 'dogrudan') { continue }
        try {
            $saglik = Get-IstemciYanitIcerigi (Invoke-WebRequest -Uri "$($a.kok)/health" -Method Get -UseBasicParsing -TimeoutSec 4)
            if ([bool](Get-DagitikDeger $saglik 'ok' $false) -and [int](Get-DagitikDeger $saglik 'protokol' 1) -ge 2) { return $a.kok }
        }
        catch { }
    }
    return $null
}

function Get-IstemciPostaAdresi {
    param([object]$Ayar)
    $posta = ConvertFrom-DagitikAdres ([string](Get-DagitikDeger $Ayar 'postaUrl' ''))
    if ($null -eq $posta -or $posta.tur -ne 'posta' -or -not (Test-DagitikGuvenliPostaKoku $posta.kok)) { return $null }
    return $posta
}

function Update-IstemciAdresleri {
    # Merkezin şifreli yanıtla bildirdiği adresler. Çalışan adres başta kalır; en fazla 4 doğrudan adres.
    param([object]$Ayar, [object]$Adresler, [string]$KullanilanKok = '')
    if ($null -eq $Adresler) { return }
    $dogrudan = New-Object System.Collections.ArrayList
    $bildirilen = @([string](Get-DagitikDeger $Adresler 'sunucuUrl' '')) + @(Get-DagitikDeger $Adresler 'ekAdresler' @())
    $mevcut = @([string](Get-DagitikDeger $Ayar 'sunucuUrl' '')) + @(Get-DagitikDeger $Ayar 'ekAdresler' @())
    $adaylar = @(@{ adres = $KullanilanKok; bildirilen = $false }) +
        @($bildirilen | ForEach-Object { @{ adres = [string]$_; bildirilen = $true } }) +
        @($mevcut | ForEach-Object { @{ adres = [string]$_; bildirilen = $false } })
    foreach ($aday in $adaylar) {
        $a = ConvertFrom-DagitikAdres $aday.adres
        if ($null -eq $a -or $a.tur -ne 'dogrudan' -or $dogrudan -contains $a.adres -or $dogrudan.Count -ge 4) { continue }
        # Merkezin kendi döngü adresi başka bir bilgisayardan anlamsızdır
        if ($aday.bildirilen -and $a.kok -cmatch '^https?://(127\.|localhost(:|$)|\[::1\])') { continue }
        [void]$dogrudan.Add($a.adres)
    }
    $sunucu = $(if ($dogrudan.Count -gt 0) { [string]$dogrudan[0] } else { '' })
    $ek = @($dogrudan | Select-Object -Skip 1)
    $degisti = ($sunucu -ne [string](Get-DagitikDeger $Ayar 'sunucuUrl' '')) -or
        (($ek -join ' ') -ne (@(Get-DagitikDeger $Ayar 'ekAdresler' @()) -join ' '))
    Set-DagitikDeger $Ayar 'sunucuUrl' $sunucu
    Set-DagitikDeger $Ayar 'ekAdresler' $ek
    $posta = ConvertFrom-DagitikAdres ([string](Get-DagitikDeger $Adresler 'postaUrl' ''))
    if ($null -ne $posta -and $posta.tur -eq 'posta' -and (Test-DagitikGuvenliPostaKoku $posta.kok) -and
        $posta.adres -ne [string](Get-DagitikDeger $Ayar 'postaUrl' '')) {
        Set-DagitikDeger $Ayar 'postaUrl' $posta.adres
        $degisti = $true
    }
    if ($degisti) { GondericiLog 'Merkez adresleri guncellendi.' }
}

function Invoke-IstemciYanitIsle {
    # Doğrudan ve posta kutusu yanıtları aynı yoldan işlenir.
    param([object]$Ayar, [string]$Tur, [int]$Kod, [object]$Govde, [long]$Zaman = 0)
    $basarili = ($Kod -ge 200 -and $Kod -lt 300 -and [bool](Get-DagitikDeger $Govde 'ok' $false))
    switch -CaseSensitive ($Tur) {
        'ozet' {
            if ($basarili) { Set-DagitikDeger $Ayar 'sonBasariliSenkronUtc' ([DateTime]::UtcNow.ToString('o')) }
            else { GondericiLog "Merkez ozeti kaydetmedi (kod $Kod)." }
        }
        'kural' {
            if ($basarili) { Set-DagitikDeger $Ayar 'kuralGonderimHata' '' }
            elseif ($Kod -eq 403) {
                Set-DagitikDeger $Ayar 'kuralGonderimHata' 'Kural gönderimi : cihazın işlem yetkisi yok (HTTP 403).'
                GondericiLog 'Kural yazma izni yok.'
            }
            else { Set-DagitikDeger $Ayar 'kuralGonderimHata' "Kural gönderimi : merkez HTTP $Kod döndürdü." }
        }
        'kurallar' {
            if (-not $basarili) { Set-DagitikDeger $Ayar 'kuralAlimHata' "Kural alımı : merkez HTTP $Kod döndürdü."; return }
            Set-DagitikDeger $Ayar 'kuralAlimHata' ''
            Set-DagitikDeger $Ayar 'sonKuralAlimiUtc' ([DateTime]::UtcNow.ToString('o'))
            $damga = [string](Get-DagitikDeger $Govde 'sonDegisiklikUtc' '')
            if ($damga -ne [string](Get-DagitikDeger $Ayar 'kuralSenkronUtc' '') -and (Get-Command Merge-YerelKurallar -ErrorAction SilentlyContinue)) {
                $degisen = Merge-YerelKurallar -Klasor $HatirlaticiKlasoru -Merkez $Govde
                Set-DagitikDeger $Ayar 'kuralSenkronUtc' $damga
                if ($degisen -gt 0) { GondericiLog "Ortak kurallar alindi: $degisen degisiklik" }
            }
        }
        'toplam' {
            if (-not $basarili) { Set-DagitikDeger $Ayar 'ortakSayacHata' "Ortak sayaç : merkez HTTP $Kod döndürdü."; return }
            Set-DagitikDeger $Ayar 'ortakSayacHata' ''
            # Posta kutusundan gelen yanıt saatler önce hesaplanmış olabilir: tazelik merkezin zarf zamanından ölçülür
            $guncelleme = [DateTime]::UtcNow
            if ($Zaman -gt 0) {
                $merkezZamani = [DateTimeOffset]::FromUnixTimeSeconds($Zaman).UtcDateTime
                if ($merkezZamani -lt $guncelleme) { $guncelleme = $merkezZamani }
            }
            Write-DagitikJsonAtomik -Nesne ([ordered]@{
                tarih = [string](Get-DagitikDeger $Govde 'tarih' '')
                digerCihazDk = [int](ConvertTo-DagitikDakika (Get-DagitikDeger $Govde 'digerCihazDk' 0))
                toplamDk = [int](ConvertTo-DagitikDakika (Get-DagitikDeger $Govde 'toplamDk' 0))
                cihazSayisi = [int](Get-DagitikDeger $Govde 'cihazSayisi' 0)
                cihazlar = @(Get-DagitikDeger $Govde 'cihazlar' @())
                guncellemeUtc = $guncelleme.ToString('o')
            }) -Yol (Join-Path $HatirlaticiKlasoru 'ortak-sayac.json')
        }
    }
}

function Invoke-IstemciDogrudanZarf {
    # Donen: @{ kod; govde; zaman }. Ag ya da dogrulama hatasinda hata firlatir.
    param([string]$Kok, [object]$Anahtarlar, [object]$Ayar, [string]$Tur, [string]$Metin)
    $cihaz = [string]$Ayar.cihazId
    $sayac = Get-IstemciYeniSayac $Ayar
    $zarf = New-DagitikZarf -Anahtarlar $Anahtarlar -Cihaz $cihaz -Tur $Tur -Yon 'istek' -Sayac $sayac -Metin $Metin
    $yanit = Invoke-WebRequest -Uri "$Kok/v2/zarf" -Method Post `
        -Body ([System.Text.Encoding]::UTF8.GetBytes((ConvertTo-DagitikZarfJson $zarf))) `
        -ContentType 'application/json; charset=utf-8' -UseBasicParsing -TimeoutSec 15
    $yanitZarfi = Get-IstemciYanitIcerigi $yanit
    if ([string](Get-DagitikDeger $yanitZarfi 'cihaz' '') -cne $cihaz -or [string](Get-DagitikDeger $yanitZarfi 'tur' '') -cne $Tur -or
        [string](Get-DagitikDeger $yanitZarfi 'yon' '') -cne 'yanit' -or [string](Get-DagitikDeger $yanitZarfi 'sayac' '') -ne [string]$sayac) {
        throw 'Merkez yaniti bu istege ait degil.'
    }
    $nesne = (Open-DagitikZarf -Anahtarlar $Anahtarlar -Zarf $yanitZarfi) | ConvertFrom-Json
    Update-IstemciAdresleri -Ayar $Ayar -Adresler (Get-DagitikDeger $nesne 'adresler' $null) -KullanilanKok $Kok
    return @{ kod = [int](Get-DagitikDeger $nesne 'kod' 0); govde = (Get-DagitikDeger $nesne 'govde' $null); zaman = [long]$yanitZarfi.zaman }
}

function Get-IstemciOutbox {
    return @(Get-ChildItem -LiteralPath $outboxKlasoru -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object Name)
}

function Move-IstemciReddedilen {
    param([System.IO.FileInfo]$Dosya)
    [void][System.IO.Directory]::CreateDirectory($redKlasoru)
    $hedef = Join-Path $redKlasoru ("$($Dosya.BaseName)-$(Get-Date -Format 'yyyyMMdd-HHmmss').json")
    Move-Item -LiteralPath $Dosya.FullName -Destination $hedef -Force
}

function Get-IstemciKuralKuyrugu {
    if (-not (Get-Command Get-KuralKuyruk -ErrorAction SilentlyContinue)) { return @() }
    return @(Get-KuralKuyruk -Klasor $HatirlaticiKlasoru)
}

function ConvertTo-IstemciKuralGovdesi {
    param([object]$Ayar, [object[]]$Bekleyen)
    return ([ordered]@{
        schemaVersion = 1
        cihazId = [string]$Ayar.cihazId
        kararlar = @($Bekleyen | ForEach-Object { [ordered]@{ oge = [string]$_.oge; tur = [string]$_.tur; karar = [string]$_.karar } })
    } | ConvertTo-Json -Depth 5 -Compress)
}

function Invoke-IstemciDogrudanTuru {
    # Ag hatasi disari firlatilir; cagiran posta kutusuna gecer. Merkezin reddi (kod) burada islenir.
    param([string]$Kok, [object]$Anahtarlar, [object]$Ayar)
    $gonderilen = 0
    foreach ($dosya in (Get-IstemciOutbox)) {
        $paket = Read-DagitikJson $dosya.FullName
        if ($null -eq $paket) { continue }
        $sonuc = Invoke-IstemciDogrudanZarf -Kok $Kok -Anahtarlar $Anahtarlar -Ayar $Ayar -Tur 'ozet' -Metin ($paket | ConvertTo-Json -Depth 10 -Compress)
        if ($sonuc.kod -ge 200 -and $sonuc.kod -lt 300) {
            Remove-Item -LiteralPath $dosya.FullName -Force
            $gonderilen++
            Invoke-IstemciYanitIsle -Ayar $Ayar -Tur 'ozet' -Kod $sonuc.kod -Govde $sonuc.govde
            Set-GondericiDurumu -Ayar $Ayar -Durum 'baglandi'
        }
        elseif ($sonuc.kod -ge 400 -and $sonuc.kod -lt 500) {
            Move-IstemciReddedilen $dosya
            $hata = "Merkez paketi reddetti (HTTP $($sonuc.kod)); paket reddedilen klasorune tasindi."
            Set-GondericiDurumu -Ayar $Ayar -Durum 'hata' -Hata $hata
            GondericiLog $hata
        }
        else {
            Set-GondericiDurumu -Ayar $Ayar -Durum 'hata' -Hata "Merkez ozeti kaydedemedi (HTTP $($sonuc.kod))."
            break
        }
    }

    $bekleyen = @(Get-IstemciKuralKuyrugu)
    if ($bekleyen.Count -gt 0) {
        $sonuc = Invoke-IstemciDogrudanZarf -Kok $Kok -Anahtarlar $Anahtarlar -Ayar $Ayar -Tur 'kural' -Metin (ConvertTo-IstemciKuralGovdesi $Ayar $bekleyen)
        Invoke-IstemciYanitIsle -Ayar $Ayar -Tur 'kural' -Kod $sonuc.kod -Govde $sonuc.govde
        # 403 = bu cihazin yazma izni yok; kuyruk birikmesin
        if (($sonuc.kod -eq 200 -and [bool](Get-DagitikDeger $sonuc.govde 'ok' $false)) -or $sonuc.kod -eq 403) {
            Clear-KuralKuyruk -Klasor $HatirlaticiKlasoru
            if ($sonuc.kod -eq 200) { GondericiLog "Kural kuyrugu merkeze gonderildi: $($bekleyen.Count) karar" }
        }
    }

    $sonuc = Invoke-IstemciDogrudanZarf -Kok $Kok -Anahtarlar $Anahtarlar -Ayar $Ayar -Tur 'kurallar' -Metin '{}'
    Invoke-IstemciYanitIsle -Ayar $Ayar -Tur 'kurallar' -Kod $sonuc.kod -Govde $sonuc.govde
    $tarihMetni = ([ordered]@{ tarih = (Get-Date).ToString('yyyy-MM-dd') } | ConvertTo-Json -Compress)
    $sonuc = Invoke-IstemciDogrudanZarf -Kok $Kok -Anahtarlar $Anahtarlar -Ayar $Ayar -Tur 'toplam' -Metin $tarihMetni
    Invoke-IstemciYanitIsle -Ayar $Ayar -Tur 'toplam' -Kod $sonuc.kod -Govde $sonuc.govde -Zaman $sonuc.zaman
    return $gonderilen
}

function Get-IstemciPostaBasliklari {
    param([object]$Posta, [object]$Anahtarlar, [object]$Ayar)
    return @{ 'X-Aizen-Kutu' = $Posta.kutu; 'X-Aizen-Cihaz' = [string]$Ayar.cihazId; 'X-Aizen-Jeton' = [string]$Anahtarlar.postaJetonu }
}

function Send-IstemciPostaZarfi {
    param([object]$Posta, [object]$Anahtarlar, [object]$Ayar, [string]$Tur, [string]$Metin, [string]$BirlestirmeAnahtari = '')
    $sayac = Get-IstemciYeniSayac $Ayar
    $zarf = New-DagitikZarf -Anahtarlar $Anahtarlar -Cihaz ([string]$Ayar.cihazId) -Tur $Tur -Yon 'istek' -Sayac $sayac -Metin $Metin
    $govde = [ordered]@{ anahtar = $BirlestirmeAnahtari; zarf = $zarf } | ConvertTo-Json -Depth 4 -Compress
    [void](Invoke-WebRequest -Uri "$($Posta.kok)/r1/cihaz/gonder" -Method Post -Headers (Get-IstemciPostaBasliklari $Posta $Anahtarlar $Ayar) `
        -Body ([System.Text.Encoding]::UTF8.GetBytes($govde)) -ContentType 'application/json; charset=utf-8' -UseBasicParsing -TimeoutSec 20)
    Set-DagitikDeger $Ayar 'postaYanitBekleniyor' $true
}

function Receive-IstemciPostaYanitlari {
    param([object]$Posta, [object]$Anahtarlar, [object]$Ayar)
    $basliklar = Get-IstemciPostaBasliklari $Posta $Anahtarlar $Ayar
    $cevap = Get-IstemciYanitIcerigi (Invoke-WebRequest -Uri "$($Posta.kok)/r1/cihaz/gelen" -Method Get -Headers $basliklar -UseBasicParsing -TimeoutSec 20)
    $mesajlar = @(Get-DagitikDeger $cevap 'mesajlar' @())
    $nolar = @()
    $cihaz = [string]$Ayar.cihazId
    foreach ($mesaj in $mesajlar) {
        $nolar += [long](Get-DagitikDeger $mesaj 'no' 0)
        $zarf = Get-DagitikDeger $mesaj 'zarf' $null
        if ([string](Get-DagitikDeger $zarf 'cihaz' '') -cne $cihaz -or [string](Get-DagitikDeger $zarf 'yon' '') -cne 'yanit') { continue }
        try { $nesne = (Open-DagitikZarf -Anahtarlar $Anahtarlar -Zarf $zarf) | ConvertFrom-Json }
        catch { GondericiLog 'Posta kutusundaki yanit dogrulanamadi; atlandi.'; continue }
        # Eski bir yanit yenisinin etkisini geri almasin: tur basina islenen en buyuk sayac tutulur
        $tur = [string]$zarf.tur
        $sonlar = Get-DagitikDeger $Ayar 'postaSonYanit' $null
        if ($null -eq $sonlar) { $sonlar = [pscustomobject]@{}; Set-DagitikDeger $Ayar 'postaSonYanit' $sonlar }
        [long]$onceki = 0
        [void][long]::TryParse([string](Get-DagitikDeger $sonlar $tur 0), [ref]$onceki)
        if ([long]$zarf.sayac -le $onceki) { continue }
        Set-DagitikDeger $sonlar $tur ([long]$zarf.sayac)
        Update-IstemciAdresleri -Ayar $Ayar -Adresler (Get-DagitikDeger $nesne 'adresler' $null)
        Invoke-IstemciYanitIsle -Ayar $Ayar -Tur $tur -Kod ([int](Get-DagitikDeger $nesne 'kod' 0)) -Govde (Get-DagitikDeger $nesne 'govde' $null) -Zaman ([long]$zarf.zaman)
    }
    if ($nolar.Count -gt 0) {
        [void](Invoke-WebRequest -Uri "$($Posta.kok)/r1/cihaz/onay" -Method Post -Headers $basliklar `
            -Body ([System.Text.Encoding]::UTF8.GetBytes(([ordered]@{ nolar = @($nolar) } | ConvertTo-Json -Compress))) `
            -ContentType 'application/json; charset=utf-8' -UseBasicParsing -TimeoutSec 20)
    }
    else { Set-DagitikDeger $Ayar 'postaYanitBekleniyor' $false }
    return $mesajlar.Count
}

function Invoke-IstemciPostaTuru {
    param([object]$Posta, [object]$Anahtarlar, [object]$Ayar)
    try { [void](Receive-IstemciPostaYanitlari -Posta $Posta -Anahtarlar $Anahtarlar -Ayar $Ayar) }
    catch { GondericiLog "Posta kutusundan yanit alinamadi: $($_.Exception.GetType().Name)" }

    # Özetler kutuya bırakılır; aynı günün eski özeti kutuda yenisiyle değişir
    $birakilan = 0
    $hata = ''
    foreach ($dosya in (Get-IstemciOutbox)) {
        $paket = Read-DagitikJson $dosya.FullName
        if ($null -eq $paket) { continue }
        $tarih = [string](Get-DagitikDeger $paket 'clientTarih' '')
        if ($tarih -cnotmatch '^[0-9]{4}-[0-9]{2}-[0-9]{2}$') { $tarih = 'gun' }
        try {
            Send-IstemciPostaZarfi -Posta $Posta -Anahtarlar $Anahtarlar -Ayar $Ayar -Tur 'ozet' `
                -Metin ($paket | ConvertTo-Json -Depth 10 -Compress) -BirlestirmeAnahtari "ozet-$tarih"
            Remove-Item -LiteralPath $dosya.FullName -Force
            $birakilan++
        }
        catch {
            $kod = 0
            try { $kod = [int]$_.Exception.Response.StatusCode } catch { }
            if ($kod -eq 400 -or $kod -eq 413) {
                Move-IstemciReddedilen $dosya
                $hata = "Posta kutusu paketi reddetti (HTTP $kod); paket reddedilen klasorune tasindi."
                GondericiLog $hata
                continue
            }
            $hata = Get-CtAgHatasi $_ 'Posta kutusu'
            if ($kod -eq 401) { $hata = 'Posta kutusu : cihaz henüz tanınmıyor; merkez bilgisayarı açılınca düzelir (HTTP 401).' }
            GondericiLog $hata
            break
        }
    }
    if (-not $hata) {
        $bekleyen = @(Get-IstemciKuralKuyrugu)
        try {
            if ($bekleyen.Count -gt 0) {
                Send-IstemciPostaZarfi -Posta $Posta -Anahtarlar $Anahtarlar -Ayar $Ayar -Tur 'kural' -Metin (ConvertTo-IstemciKuralGovdesi $Ayar $bekleyen)
                Clear-KuralKuyruk -Klasor $HatirlaticiKlasoru
                GondericiLog "Kural kuyrugu posta kutusuna birakildi: $($bekleyen.Count) karar"
            }
            Send-IstemciPostaZarfi -Posta $Posta -Anahtarlar $Anahtarlar -Ayar $Ayar -Tur 'kurallar' -Metin '{}' -BirlestirmeAnahtari 'kurallar'
            Send-IstemciPostaZarfi -Posta $Posta -Anahtarlar $Anahtarlar -Ayar $Ayar -Tur 'toplam' `
                -Metin ([ordered]@{ tarih = (Get-Date).ToString('yyyy-MM-dd') } | ConvertTo-Json -Compress) -BirlestirmeAnahtari 'toplam'
        }
        catch { $hata = Get-CtAgHatasi $_ 'Posta kutusu'; GondericiLog $hata }
    }
    if ($hata) { Set-GondericiDurumu -Ayar $Ayar -Durum 'hata' -Hata $hata }
    else { Set-GondericiDurumu -Ayar $Ayar -Durum 'postada' }
    return $birakilan
}

function Invoke-IstemciV2Turu {
    # Donen: dogrudan gonderilen ya da posta kutusuna birakilan ozet sayisi
    param([object]$Ayar, [string]$Anahtar)
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $anahtarlar = Get-DagitikZarfAnahtarlari $Anahtar
    $posta = Get-IstemciPostaAdresi $Ayar
    $kok = Select-IstemciDogrudanAdres $Ayar
    $sayi = 0
    if ($null -ne $kok) {
        try {
            $sayi = Invoke-IstemciDogrudanTuru -Kok $kok -Anahtarlar $anahtarlar -Ayar $Ayar
            Set-DagitikDeger $Ayar 'sonKanal' 'dogrudan'
            # Daha once posta kutusuna birakilmis isteklerin yanitlari kalmis olabilir
            if ($null -ne $posta -and [bool](Get-DagitikDeger $Ayar 'postaYanitBekleniyor' $false)) {
                try { [void](Receive-IstemciPostaYanitlari -Posta $posta -Anahtarlar $anahtarlar -Ayar $Ayar) } catch { }
            }
            return $sayi
        }
        catch {
            $hata = Get-CtAgHatasi $_ 'Özet gönderimi'
            GondericiLog "Dogrudan baglanti kullanilamadi: $hata"
            if ($null -eq $posta) { Set-GondericiDurumu -Ayar $Ayar -Durum 'hata' -Hata $hata; return $sayi }
        }
    }
    if ($null -eq $posta) {
        Set-GondericiDurumu -Ayar $Ayar -Durum 'hata' -Hata 'Merkeze ulaşılamadı: doğrudan adres yanıt vermedi, posta kutusu tanımlı değil.'
        return 0
    }
    Set-DagitikDeger $Ayar 'sonKanal' 'posta'
    return ($sayi + (Invoke-IstemciPostaTuru -Posta $posta -Anahtarlar $anahtarlar -Ayar $Ayar))
}
