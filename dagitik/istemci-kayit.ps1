<#
Kullanici bilgisayarini eşleşme koduyla merkeze bağlar.

Akış: onay ekranı gösterilir -> kullanıcı kabul ederse kayıt isteği gönderilir ->
merkez cihaz anahtarını yalnızca kodu bilen tarafın çözebileceği biçimde şifreli
döndürür -> anahtar DPAPI ile bu kullanıcıya bağlı saklanır.

Adres iki biçimde olabilir:
  http://192.168.1.20:8787            merkez (aynı ağ ya da port yönlendirme)
  https://posta.firma.com/k/<kutu>    posta kutusu (farklı ağ; merkez o sırada açık olmalı)

Protokol v2'de eşleşme kodu ağa hiç çıkmaz: istek ve yanıt koddan türetilen anahtarla
şifrelenir (uyumluluk/PROTOKOL-V2.md). Eski (yalnızca v1 bilen) merkezde doğrudan
adreste v1 kaydına düşülür.

Onay verilmeden hiçbir şey yazılmaz ve hiçbir veri gönderilmez.

Kullanım:
  .\istemci-kayit.ps1 -SunucuUrl http://192.168.1.20:8787 -Kod ABCD-EFGH-JKMN
  .\istemci-kayit.ps1 -SunucuUrl https://posta.firma.com/k/0123456789abcdef -Kod ...
  .\istemci-kayit.ps1 -SunucuUrl ... -Kod ... -Onayla      # onayı komut satırında ver
#>
param(
    [string]$SunucuUrl,
    [string]$Kod,
    [string]$CihazAdi,
    [string]$HatirlaticiKlasoru,
    [switch]$Onayla,
    [switch]$Sessiz,
    [switch]$GorevKurmadan,

    # Yalnızca onay metnini yazar ve çıkar. Kurulum sihirbazı aynı metni
    # gösterebilsin diye var; metin tek yerde tutulur.
    [switch]$YalnizOnayMetni,

    # Posta kutusuyla kayıtta merkezin yanıtı için beklenecek en uzun süre
    [int]$PostaBeklemeSn = 150
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Ortak.ps1')

$uygulamaKok = Get-DagitikUygulamaKok $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($HatirlaticiKlasoru)) {
    $HatirlaticiKlasoru = Join-Path $uygulamaKok 'hatirlatici'
}
if (-not (Test-Path -LiteralPath $HatirlaticiKlasoru)) { throw 'hatirlatici klasörü bulunamadı.' }

if ([string]::IsNullOrWhiteSpace($SunucuUrl) -and -not $Sessiz -and -not $YalnizOnayMetni) {
    $SunucuUrl = Read-Host 'Merkez adresi (örnek: http://192.168.1.20:8787 ya da https://posta.firma.com/k/...)'
}
$SunucuUrl = ([string]$SunucuUrl).Trim().TrimEnd('/')
if ($YalnizOnayMetni -and [string]::IsNullOrWhiteSpace($SunucuUrl)) { $SunucuUrl = '(kurulumda girilecek)' }
$adres = ConvertFrom-DagitikAdres $SunucuUrl
if (-not $YalnizOnayMetni) {
    if ($null -eq $adres) {
        throw 'Merkez adresi http://sunucu:port ya da https://posta-sunucusu/k/kutu biçiminde olmalıdır.'
    }
    if ($adres.tur -eq 'posta' -and -not (Test-DagitikGuvenliPostaKoku $adres.kok)) {
        throw 'Posta kutusu adresi https:// ile başlamalıdır.'
    }
    $SunucuUrl = $adres.adres
}
if ([string]::IsNullOrWhiteSpace($Kod) -and -not $Sessiz -and -not $YalnizOnayMetni) {
    $Kod = Read-Host 'Yöneticinin verdiği eşleşme kodu'
}
$kodNormal = ConvertTo-DagitikKodNormal $Kod
if (-not $YalnizOnayMetni -and $kodNormal.Length -lt 8) { throw 'Eşleşme kodu eksik veya geçersiz.' }

if ([string]::IsNullOrWhiteSpace($CihazAdi)) { $CihazAdi = $env:COMPUTERNAME }
$CihazAdi = ConvertTo-DagitikSinirliMetin $CihazAdi 80

$surum = ''
$kurulumBilgisi = Read-DagitikJson (Join-Path $PSScriptRoot 'kurulum-bilgisi.json')
if ($null -ne $kurulumBilgisi) { $surum = [string](Get-DagitikDeger $kurulumBilgisi 'paketSurumu' '') }

$onayMetni = @"
============================================================
 Aizen - merkeze bağlanma onayı
============================================================
 Bu bilgisayar : $CihazAdi (Windows kullanıcısı: $env:USERNAME)
 Merkez adresi : $SunucuUrl
 Gönderim      : 5 dakikada bir, yalnızca o günün toplamları
 Aktarım       : şifreli; aradaki ağ ve posta kutusu içeriği göremez

 GÖNDERİLECEK
   - Uygulama adı ve kategorisi (çalışma / diğer / boşta)
   - Uygulama başına günlük süre toplamı
   - Takip sağlığı: izleyici çalışıyor mu, son ölçüm ne zaman

 GÖNDERİLMEYECEK
   - Pencere başlıkları (yönetici ayrıca izin vermedikçe)
   - Tam adres/URL ve arama terimleri
   - Tuş kaydı, pano içeriği, ekran görüntüsü, kamera, mikrofon
   - Dosya adları ve dosya içerikleri

 Bağlantıyı sonradan kapatmak : dagitik\kaldir.ps1 -YalnizMerkez
 Ne gönderildiğini görmek      : dagitik\istemci-durum.ps1
============================================================
"@
Write-Output $onayMetni
if ($YalnizOnayMetni) { exit 0 }

if (-not $Onayla) {
    if ($Sessiz) { throw 'Sessiz kurulumda onay için -Onayla parametresi gerekir.' }
    $cevap = Read-Host 'Bu bilgisayarın yukarıdaki verileri merkeze göndermesini onaylıyor musun? (EVET / hayır)'
    if (($cevap.Trim().ToUpperInvariant()) -notin @('EVET', 'E', 'YES', 'Y')) {
        Write-Output 'Onay verilmedi. Hiçbir şey yazılmadı, bağlantı kurulmadı.'
        exit 2
    }
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Get-KayitHttpKodu {
    param([object]$Hata)
    $kod = 0
    try { $kod = [int]$Hata.Exception.Response.StatusCode } catch { }
    return $kod
}

function Get-KayitIcerigi {
    param([object]$Yanit)
    $icerik = $Yanit.Content
    if ($icerik -is [byte[]]) { $icerik = [System.Text.Encoding]::UTF8.GetString($icerik) }
    return ([string]$icerik | ConvertFrom-Json)
}

function Invoke-V1Kayit {
    # Yalnızca v1 bilen eski merkez (doğrudan adres). Kod bu istekte ağa düz gider.
    $govde = [ordered]@{
        schemaVersion = 1
        kod = $kodNormal
        cihazAdi = $CihazAdi
        kullanici = ConvertTo-DagitikSinirliMetin $env:USERNAME 80
        surum = $surum
        onay = $true
    } | ConvertTo-Json -Depth 4 -Compress
    $cevapJson = $null
    try {
        $yanit = Invoke-WebRequest -Uri "$SunucuUrl/v1/kayit" -Method Post -Body $govde `
            -ContentType 'application/json; charset=utf-8' -UseBasicParsing -TimeoutSec 20
        $cevapJson = $yanit.Content | ConvertFrom-Json
    }
    catch {
        switch (Get-KayitHttpKodu $_) {
            403 { throw 'Kod geçersiz, süresi dolmuş veya daha önce kullanılmış. Yöneticiden yeni kod iste.' }
            429 { throw 'Çok fazla deneme yapıldı. 10 dakika bekleyip tekrar dene.' }
            400 { throw 'Merkez isteği reddetti (biçim veya onay hatası).' }
            default { throw "Merkeze ulaşılamadı: $($_.Exception.Message)" }
        }
    }
    if ($null -eq $cevapJson -or -not [bool](Get-DagitikDeger $cevapJson 'ok' $false)) {
        throw 'Merkez kaydı tamamlayamadı.'
    }
    $anahtarPaketi = Get-DagitikDeger $cevapJson 'anahtar' $null
    if ($null -eq $anahtarPaketi) { throw 'Merkez cihaz anahtarını göndermedi.' }
    $anahtar = Unprotect-DagitikKodIle -Paket $anahtarPaketi -Kod $kodNormal -Tuz ([string](Get-DagitikDeger $anahtarPaketi 'tuz' ''))
    return @{ protokol = 1; govde = $cevapJson; anahtar = $anahtar }
}

function Invoke-V2Kayit {
    $kayit = Get-DagitikKayitAnahtarlari -Kod $kodNormal
    $istekMetni = [ordered]@{
        schemaVersion = 2
        onay = $true
        cihazAdi = $CihazAdi
        kullanici = ConvertTo-DagitikSinirliMetin $env:USERNAME 80
        surum = $surum
    } | ConvertTo-Json -Depth 3 -Compress
    $zarf = New-DagitikZarf -Anahtarlar $kayit -Cihaz $kayit.kanal -Tur 'kayit' -Yon 'istek' -Sayac 1 -Metin $istekMetni
    $yanitZarflari = @()

    if ($adres.tur -eq 'dogrudan') {
        try {
            $yanit = Invoke-WebRequest -Uri "$($adres.kok)/v2/zarf" -Method Post `
                -Body ([System.Text.Encoding]::UTF8.GetBytes((ConvertTo-DagitikZarfJson $zarf))) `
                -ContentType 'application/json; charset=utf-8' -UseBasicParsing -TimeoutSec 20
            $yanitZarflari = @(Get-KayitIcerigi $yanit)
        }
        catch {
            switch (Get-KayitHttpKodu $_) {
                404 { return $null }
                403 { throw 'Kod geçersiz, süresi dolmuş veya daha önce kullanılmış. Yöneticiden yeni kod iste.' }
                429 { throw 'Çok fazla deneme yapıldı. 10 dakika bekleyip tekrar dene.' }
                401 { throw 'Merkez isteği reddetti: bu bilgisayarın saati yanlış olabilir.' }
                400 { throw 'Merkez isteği reddetti (biçim hatası).' }
                default { throw "Merkeze ulaşılamadı: $($_.Exception.Message)" }
            }
        }
    }
    else {
        $basliklar = @{ 'X-Aizen-Kutu' = $adres.kutu; 'X-Aizen-Cihaz' = $kayit.kanal; 'X-Aizen-Jeton' = $kayit.postaJetonu }
        $govde = [System.Text.Encoding]::UTF8.GetBytes(([ordered]@{ anahtar = ''; zarf = $zarf } | ConvertTo-Json -Depth 4 -Compress))
        $bitis = (Get-Date).AddSeconds([math]::Max(20, $PostaBeklemeSn))
        # Fonksiyon ciktisi donus degerine karismasin diye Write-Host
        Write-Host 'Posta kutusuna bağlanılıyor; merkez bilgisayarının isteği alması bekleniyor...'
        # Merkez yeni kodun kanalını kutuya birkaç saniye içinde bildirir; o zamana kadar 401 döner.
        # Kod yanlışsa kanal hiç tanınmaz: süre dolunca anlaşılır bir hata verilir.
        $birakildi = $false
        while (-not $birakildi) {
            try {
                [void](Invoke-WebRequest -Uri "$($adres.kok)/r1/cihaz/gonder" -Method Post -Headers $basliklar -Body $govde `
                    -ContentType 'application/json; charset=utf-8' -UseBasicParsing -TimeoutSec 20)
                $birakildi = $true
            }
            catch {
                $kod = Get-KayitHttpKodu $_
                if ($kod -eq 401 -and (Get-Date) -lt $bitis) { Start-Sleep -Seconds 4; continue }
                if ($kod -eq 401) { throw 'Kod geçersiz ya da merkez bilgisayarı şu anda kapalı. Kodu kontrol et; merkez açıkken tekrar dene.' }
                if ($kod -eq 429) { throw 'Posta kutusu şu anda yoğun; birkaç dakika sonra tekrar dene.' }
                if ($kod -gt 0) { throw "Posta kutusu isteği reddetti (HTTP $kod)." }
                throw "Posta kutusuna ulaşılamadı: $($_.Exception.Message)"
            }
        }
        while ($yanitZarflari.Count -eq 0) {
            try {
                $gelen = Get-KayitIcerigi (Invoke-WebRequest -Uri "$($adres.kok)/r1/cihaz/gelen" -Method Get -Headers $basliklar -UseBasicParsing -TimeoutSec 20)
                $nolar = @()
                foreach ($mesaj in @(Get-DagitikDeger $gelen 'mesajlar' @())) {
                    $nolar += [long](Get-DagitikDeger $mesaj 'no' 0)
                    $z = Get-DagitikDeger $mesaj 'zarf' $null
                    if ([string](Get-DagitikDeger $z 'tur' '') -ceq 'kayit' -and [string](Get-DagitikDeger $z 'yon' '') -ceq 'yanit') { $yanitZarflari += $z }
                }
                if ($nolar.Count -gt 0) {
                    try {
                        [void](Invoke-WebRequest -Uri "$($adres.kok)/r1/cihaz/onay" -Method Post -Headers $basliklar `
                            -Body ([System.Text.Encoding]::UTF8.GetBytes(([ordered]@{ nolar = @($nolar) } | ConvertTo-Json -Compress))) `
                            -ContentType 'application/json; charset=utf-8' -UseBasicParsing -TimeoutSec 20)
                    }
                    catch { }
                }
            }
            catch { if ((Get-KayitHttpKodu $_) -eq 0 -and (Get-Date) -ge $bitis) { throw "Posta kutusuna ulaşılamadı: $($_.Exception.Message)" } }
            if ($yanitZarflari.Count -gt 0) { break }
            if ((Get-Date) -ge $bitis) {
                throw 'Merkez yanıt vermedi. Merkez bilgisayarı açıkken tekrar dene; kod 30 dakika içinde yeniden kullanılabilir.'
            }
            Start-Sleep -Seconds 3
        }
    }

    # Birden fazla yanıt olabilir (önceki denemenin başarılı yanıtı kutuda kaldıysa): başarılı olan seçilir
    $secilen = $null
    foreach ($z in $yanitZarflari) {
        if ([string](Get-DagitikDeger $z 'cihaz' '') -cne $kayit.kanal -or [string](Get-DagitikDeger $z 'tur' '') -cne 'kayit' -or
            [string](Get-DagitikDeger $z 'yon' '') -cne 'yanit') { continue }
        try { $nesne = (Open-DagitikZarf -Anahtarlar $kayit -Zarf $z) | ConvertFrom-Json } catch { continue }
        if ($null -eq $secilen -or [int](Get-DagitikDeger $nesne 'kod' 0) -eq 200) { $secilen = $nesne }
    }
    if ($null -eq $secilen) { throw 'Merkezin yanıtı doğrulanamadı: kod yanlış olabilir ya da yanıt yolda değiştirilmiş.' }
    switch ([int](Get-DagitikDeger $secilen 'kod' 0)) {
        200 { }
        403 { throw 'Kod geçersiz, süresi dolmuş veya daha önce kullanılmış. Yöneticiden yeni kod iste.' }
        400 { throw 'Merkez isteği reddetti (biçim veya onay hatası).' }
        default { throw 'Merkez kaydı tamamlayamadı.' }
    }
    $govdeY = Get-DagitikDeger $secilen 'govde' $null
    if ($null -eq $govdeY -or -not [bool](Get-DagitikDeger $govdeY 'ok' $false)) { throw 'Merkez kaydı tamamlayamadı.' }
    return @{ protokol = 2; govde = $govdeY; anahtar = [string](Get-DagitikDeger $govdeY 'anahtar' '') }
}

$sonuc = Invoke-V2Kayit
if ($null -eq $sonuc) {
    Write-Output 'Merkez eski sürüm (yalnızca v1); yerel ağ kaydı kullanılıyor.'
    $sonuc = Invoke-V1Kayit
}
$cevapJson = $sonuc.govde
$anahtar = $sonuc.anahtar

$cihazId = [string](Get-DagitikDeger $cevapJson 'cihazId' '')
if (-not (Test-DagitikCihazKimligi $cihazId) -or (Test-DagitikKayitKanali $cihazId)) { throw 'Merkez geçersiz cihaz kimliği döndürdü.' }
$anahtarBayt = $null
try { $anahtarBayt = [Convert]::FromBase64String($anahtar) } catch { }
if ($null -eq $anahtarBayt -or $anahtarBayt.Length -ne 32) { throw 'Merkezden gelen anahtar geçersiz.' }

$simdi = [DateTime]::UtcNow.ToString('o')
$ayar = [ordered]@{
    surum = 1
    aktif = $true
    cihazId = $cihazId
    cihazAdi = ConvertTo-DagitikSinirliMetin (Get-DagitikDeger $cevapJson 'cihazAdi' $CihazAdi) 80
    sunucuUrl = $SunucuUrl
    anahtarKorunmus = Protect-DagitikAnahtar -Anahtar $anahtar -Amac "istemci:$cihazId"
    gonderimDakikasi = [int](ConvertTo-DagitikDakika (Get-DagitikDeger $cevapJson 'gonderimDakikasi' 5) 60)
    ayrintiDuzeyi = $(if ([string](Get-DagitikDeger $cevapJson 'ayrintiDuzeyi' 'ozet') -eq 'baslikli') { 'baslikli' } else { 'ozet' })
    sira = 0
    sonDurum = 'kuruldu'
    sonKontrolUtc = $simdi
    sonHata = ''
    veriAciklamasi = ConvertTo-DagitikSinirliMetin (Get-DagitikDeger $cevapJson 'veriAciklamasi' '') 350
    onayUtc = $simdi
}
if ($sonuc.protokol -ge 2) {
    # Doğrudan adresler sırayla denenir, hiçbirine ulaşılamazsa posta kutusu kullanılır.
    # Kayıtta kullanılan adres başta; merkezin bildirdiği diğer adresler (şifreli yanıttan) eklenir.
    $dogrudan = New-Object System.Collections.ArrayList
    $postaUrl = ''
    if ($adres.tur -eq 'dogrudan') { [void]$dogrudan.Add($adres.adres) } else { $postaUrl = $adres.adres }
    $bildirilen = @([string](Get-DagitikDeger $cevapJson 'sunucuUrl' '')) + @(Get-DagitikDeger $cevapJson 'ekAdresler' @())
    foreach ($aday in $bildirilen) {
        $a = ConvertFrom-DagitikAdres ([string]$aday)
        if ($null -eq $a -or $a.tur -ne 'dogrudan' -or $dogrudan -contains $a.adres) { continue }
        # Merkezin yerel döngü adresi başka bir bilgisayardan anlamsızdır
        if ($a.kok -cmatch '^https?://(127\.|localhost(:|$)|\[::1\])') { continue }
        if ($dogrudan.Count -lt 4) { [void]$dogrudan.Add($a.adres) }
    }
    $bildirilenPosta = ConvertFrom-DagitikAdres ([string](Get-DagitikDeger $cevapJson 'postaUrl' ''))
    if (-not $postaUrl -and $null -ne $bildirilenPosta -and $bildirilenPosta.tur -eq 'posta' -and (Test-DagitikGuvenliPostaKoku $bildirilenPosta.kok)) {
        $postaUrl = $bildirilenPosta.adres
    }
    $ayar['protokol'] = 2
    $ayar['sunucuUrl'] = $(if ($dogrudan.Count -gt 0) { [string]$dogrudan[0] } else { '' })
    $ayar['ekAdresler'] = @($dogrudan | Select-Object -Skip 1)
    $ayar['postaUrl'] = $postaUrl
    $ayar['sayac'] = 0
}
Write-DagitikJsonAtomik -Nesne $ayar -Yol (Join-Path $HatirlaticiKlasoru 'merkez.json')

# Onay kaydı: ne zaman, kim, hangi kapsam için onay verdi
$onayKaydi = [ordered]@{
    onayUtc = $simdi
    windowsKullanicisi = $env:USERNAME
    bilgisayar = $env:COMPUTERNAME
    cihazId = $cihazId
    sunucuUrl = $SunucuUrl
    ayrintiDuzeyi = $ayar.ayrintiDuzeyi
    metin = $onayMetni
}
Write-DagitikJsonAtomik -Nesne $onayKaydi -Yol (Join-Path $HatirlaticiKlasoru 'onay.json')

Write-Output ''
Write-Output "Kayıt tamamlandı. Cihaz kimliği: $cihazId"
if ($GorevKurmadan) {
    Write-Output 'Gönderim görevi kurulmadı (-GorevKurmadan).'
    exit 0
}
Write-Output 'Gönderim görevi kuruluyor...'
$psExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
& $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'istemci-kurulum.ps1') -Kur -HazirAyar -HatirlaticiKlasoru $HatirlaticiKlasoru
if ($LASTEXITCODE -ne 0) { throw "Gönderim görevi kurulamadı (kod $LASTEXITCODE)." }
