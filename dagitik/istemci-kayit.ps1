<#
Kullanici bilgisayarini eşleşme koduyla merkeze bağlar.

Akış: onay ekranı gösterilir -> kullanıcı kabul ederse merkeze POST /v1/kayit
gönderilir -> merkez cihaz anahtarını yalnızca kodu bilen tarafın çözebileceği
biçimde şifreli döndürür -> anahtar DPAPI ile bu kullanıcıya bağlı saklanır.

Onay verilmeden hiçbir şey yazılmaz ve hiçbir veri gönderilmez.

Kullanım:
  .\istemci-kayit.ps1 -SunucuUrl http://192.168.1.20:8787 -Kod ABCD-EFGH-JKMN
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
    [switch]$YalnizOnayMetni
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Ortak.ps1')

$uygulamaKok = Get-DagitikUygulamaKok $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($HatirlaticiKlasoru)) {
    $HatirlaticiKlasoru = Join-Path $uygulamaKok 'hatirlatici'
}
if (-not (Test-Path -LiteralPath $HatirlaticiKlasoru)) { throw 'hatirlatici klasörü bulunamadı.' }

if ([string]::IsNullOrWhiteSpace($SunucuUrl) -and -not $Sessiz -and -not $YalnizOnayMetni) {
    $SunucuUrl = Read-Host 'Merkez adresi (örnek: http://192.168.1.20:8787)'
}
$SunucuUrl = ([string]$SunucuUrl).Trim().TrimEnd('/')
if ($YalnizOnayMetni -and [string]::IsNullOrWhiteSpace($SunucuUrl)) { $SunucuUrl = '(kurulumda girilecek)' }
if (-not $YalnizOnayMetni -and $SunucuUrl -notmatch '^https?://[^/\\]+(?::\d+)?$') {
    throw 'Merkez adresi http://sunucu:port biçiminde olmalıdır.'
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

$govde = [ordered]@{
    schemaVersion = 1
    kod = $kodNormal
    cihazAdi = $CihazAdi
    kullanici = ConvertTo-DagitikSinirliMetin $env:USERNAME 80
    surum = $surum
    onay = $true
} | ConvertTo-Json -Depth 4 -Compress

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$cevapJson = $null
try {
    $yanit = Invoke-WebRequest -Uri "$SunucuUrl/v1/kayit" -Method Post -Body $govde `
        -ContentType 'application/json; charset=utf-8' -UseBasicParsing -TimeoutSec 20
    $cevapJson = $yanit.Content | ConvertFrom-Json
}
catch {
    $kod = 0
    try { $kod = [int]$_.Exception.Response.StatusCode } catch { }
    switch ($kod) {
        403 { throw 'Kod geçersiz, süresi dolmuş veya daha önce kullanılmış. Yöneticiden yeni kod iste.' }
        429 { throw 'Çok fazla deneme yapıldı. 10 dakika bekleyip tekrar dene.' }
        400 { throw 'Merkez isteği reddetti (biçim veya onay hatası).' }
        default { throw "Merkeze ulaşılamadı: $($_.Exception.Message)" }
    }
}
if ($null -eq $cevapJson -or -not [bool](Get-DagitikDeger $cevapJson 'ok' $false)) {
    throw 'Merkez kaydı tamamlayamadı.'
}

$cihazId = [string](Get-DagitikDeger $cevapJson 'cihazId' '')
if (-not (Test-DagitikCihazKimligi $cihazId)) { throw 'Merkez geçersiz cihaz kimliği döndürdü.' }
$anahtarPaketi = Get-DagitikDeger $cevapJson 'anahtar' $null
if ($null -eq $anahtarPaketi) { throw 'Merkez cihaz anahtarını göndermedi.' }
$anahtar = Unprotect-DagitikKodIle -Paket $anahtarPaketi -Kod $kodNormal -Tuz ([string](Get-DagitikDeger $anahtarPaketi 'tuz' ''))
try { [void][Convert]::FromBase64String($anahtar) } catch { throw 'Merkezden gelen anahtar geçersiz.' }

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
