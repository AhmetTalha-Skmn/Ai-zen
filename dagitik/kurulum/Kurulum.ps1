#requires -Version 5.1
<#!
.SYNOPSIS
    Aizen (Çalışma Takip Sistemi) kurulumu. İki rol vardır: Admin ve Kullanici.

.DESCRIPTION
    Admin      : Bu bilgisayar merkez olur; yetkilendirilmiş cihazların özetlerini
                 toplar ve panelden gösterir. Kendi çalışmasını da ölçer.
    Kullanici  : Bu bilgisayar ölçülür. İsteğe bağlı olarak, kullanıcı onay verirse
                 bir merkeze bağlanır. Bağlanmadan da tek başına çalışır.

    Rolden bağımsız olarak bir kurulum türü seçilir (dagitik\kurulum-bilgisi.json):
    Bireysel   : 45 dakikalık hatırlatmalar ve ekran kilidi açık (ikisi de Ayarlar'dan kapanır).
    Sirket     : hatırlatma yok; ekran kilidi kapalı (Ayarlar'dan açılabilir).
    Ozel       : -Hatirlatmalar ve -EkranKilidi ile seçilir.
    -KurulumTuru verilmezse: mevcut kurulumun türü (türü yazılmamış eski kurulum Bireysel
    sayılır) -> yeni kurulumda CT_KURULUM_TURU ortam değişkeni (Kurulum-Admin.cmd ve
    Kurulum-Kullanici.cmd Sirket verir) -> Bireysel. Kurulum ayarlar.json'a yazmaz; kullanıcının
    Ayarlar'daki seçimi kurulumdaki seçimin önüne geçer.

    Kurulum varsayılan olarak geçerli kullanıcının LocalAppData klasörüne yapılır;
    yönetici yetkisi yalnızca merkez dinleyicisi için gerekir.

    Güncellemede kullanıcıya ait dosyalar (kurallar, ayarlar, ölçüm verisi, merkez
    kaydı) korunur; yalnızca uygulama dosyaları yenilenir.
#>
[CmdletBinding()]
param(
    [ValidateSet('Admin', 'Kullanici', 'AnaYonetici', 'Istemci')]
    [string]$Rol,

    [Alias('Kayit', 'EnrollmentFile', 'YapilandirmaYolu')]
    [string]$KayitDosyasi,

    [string]$Kod,
    [string]$SunucuUrl,

    [Alias('Hedef')]
    [string]$KurulumDizini,

    [ValidateSet('Bireysel', 'Sirket', 'Ozel')]
    [string]$KurulumTuru,

    # Kurulumdaki özellik seçimi (çoğunlukla Ozel için). Sirket türünde hatırlatma açılamaz.
    [ValidateSet('Acik', 'Kapali')]
    [string]$Hatirlatmalar,
    [ValidateSet('Acik', 'Kapali')]
    [string]$EkranKilidi,

    [switch]$Onayla,
    [switch]$Sessiz,

    # Yalnızca dosyaları kopyalar: görev, kısayol ve merkez bağlantısına dokunmaz.
    # Hazırlık/güncelleme provası ve testler için.
    [switch]$YalnizKopyala
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Güncellemede üzerine yazılmayacak kullanıcı dosyaları ve klasörleri
$script:KorunanDosyalar = @(
    'kurallar.json', 'ayarlar.json', 'periyot.json', 'merkez.json', 'onay.json',
    'durum.json', 'gecmis.json', 'merkez-ayarlari.json', 'kurulum-bilgisi.json',
    'ortak-sayac.json', 'kural-outbox.json', 'merkez-kurallar.json', 'GERI-YUKLEME'
)
$script:KorunanKlasorler = @('aktivite', 'rapor', 'veri', 'merkez-outbox', 'cihaz-paketleri', 'cikti', 'Gunluk', 'geri-yukleme-yedekleri')

function Get-TamYol {
    param([Parameter(Mandatory = $true)][string]$Yol)
    return [System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Yol))
}

function Test-AltYol {
    param(
        [Parameter(Mandatory = $true)][string]$AltYol,
        [Parameter(Mandatory = $true)][string]$UstYol
    )
    $alt = (Get-TamYol -Yol $AltYol).TrimEnd('\')
    $ust = (Get-TamYol -Yol $UstYol).TrimEnd('\')
    return $alt.StartsWith($ust + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-NesneOzelligi {
    param(
        [Parameter(Mandatory = $true)][object]$Nesne,
        [Parameter(Mandatory = $true)][string[]]$Adlar
    )
    foreach ($ad in $Adlar) {
        $ozellik = $Nesne.PSObject.Properties | Where-Object { $_.Name -ieq $ad } | Select-Object -First 1
        if ($null -ne $ozellik -and $null -ne $ozellik.Value) {
            $metin = [string]$ozellik.Value
            if (-not [string]::IsNullOrWhiteSpace($metin)) { return $metin.Trim() }
        }
    }
    return $null
}

function Test-CihazKaydi {
    # Eski yöntem: yöneticinin ürettiği dosya tabanlı kayıt paketi (hâlâ desteklenir).
    param([Parameter(Mandatory = $true)][string]$Yol)

    $tamYol = Get-TamYol -Yol $Yol
    if (-not (Test-Path -LiteralPath $tamYol -PathType Leaf)) {
        throw "Cihaz kayıt dosyası bulunamadı: $tamYol"
    }
    if ((Get-Item -LiteralPath $tamYol).Length -gt 128KB) {
        throw 'Cihaz kayıt dosyası beklenenden büyük; kurulum durduruldu.'
    }
    try { $kayit = Get-Content -LiteralPath $tamYol -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { throw "Cihaz kayıt dosyası geçerli JSON değil: $($_.Exception.Message)" }

    $cihazId = Get-NesneOzelligi -Nesne $kayit -Adlar @('cihazId', 'deviceId')
    $anahtar = Get-NesneOzelligi -Nesne $kayit -Adlar @('anahtar', 'apiAnahtari', 'key', 'secret')
    $sunucu = Get-NesneOzelligi -Nesne $kayit -Adlar @('sunucuUrl', 'merkezUrl', 'serverUrl')

    if ([string]::IsNullOrWhiteSpace($cihazId) -or $cihazId -cnotmatch '^[A-Za-z0-9][A-Za-z0-9_-]{2,63}$') {
        throw 'Cihaz kayıt dosyasındaki cihaz kimliği geçersiz.'
    }
    if ([string]::IsNullOrWhiteSpace($anahtar) -or $anahtar.Length -lt 16) {
        throw 'Cihaz kayıt dosyasında güvenli bir cihaz anahtarı bulunamadı.'
    }
    try {
        if (([Convert]::FromBase64String($anahtar)).Length -lt 16) { throw 'kisa' }
    }
    catch { throw 'Cihaz kayıt dosyasındaki cihaz anahtarı geçerli değil.' }
    try { $uri = [System.Uri]$sunucu } catch { throw 'Cihaz kayıt dosyasındaki merkez adresi geçersiz.' }
    if (($uri.Scheme -ne 'http' -and $uri.Scheme -ne 'https') -or [string]::IsNullOrWhiteSpace($uri.Host)) {
        throw 'Cihaz kayıt dosyasındaki merkez adresi HTTP veya HTTPS olmalıdır.'
    }
    return [pscustomobject]@{ Yol = $tamYol; CihazId = $cihazId }
}

function Copy-UygulamaYuku {
    # Uygulama dosyalarını kopyalar; kullanıcıya ait dosya ve klasörlere dokunmaz.
    param(
        [Parameter(Mandatory = $true)][string]$Kaynak,
        [Parameter(Mandatory = $true)][string]$Hedef
    )
    $kaynakKok = (Get-TamYol -Yol $Kaynak).TrimEnd('\') + '\'
    $kopyalanan = 0
    $korunan = 0
    foreach ($dosya in Get-ChildItem -LiteralPath $Kaynak -Recurse -File -Force) {
        $goreli = (Get-TamYol -Yol $dosya.FullName).Substring($kaynakKok.Length)
        $atla = $false
        foreach ($parca in ($goreli -split '\\')) {
            if ($script:KorunanKlasorler -contains $parca) { $atla = $true; break }
        }
        if ($atla) { continue }

        $hedefYol = Join-Path $Hedef $goreli
        if ((Test-Path -LiteralPath $hedefYol -PathType Leaf) -and ($script:KorunanDosyalar -contains $dosya.Name)) {
            $korunan++
            continue
        }
        $hedefKlasor = Split-Path -Parent $hedefYol
        if (-not (Test-Path -LiteralPath $hedefKlasor -PathType Container)) {
            New-Item -ItemType Directory -Path $hedefKlasor -Force | Out-Null
        }
        Copy-Item -LiteralPath $dosya.FullName -Destination $hedefYol -Force
        $kopyalanan++
    }
    return [pscustomobject]@{ Kopyalanan = $kopyalanan; Korunan = $korunan }
}

function Get-WindowsPowerShell {
    $yol = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (Test-Path -LiteralPath $yol -PathType Leaf) { return $yol }
    $komut = Get-Command -Name 'powershell.exe' -ErrorAction SilentlyContinue
    if ($null -ne $komut) { return $komut.Source }
    throw 'Windows PowerShell 5.1 bulunamadı; kurulum devam edemiyor.'
}

function Get-PaketSurumu {
    param([Parameter(Mandatory = $true)][string]$PaketKoku)
    $yol = Join-Path $PaketKoku 'PAKET-MANIFEST.json'
    if (-not (Test-Path -LiteralPath $yol -PathType Leaf)) { return '' }
    try {
        $manifest = Get-Content -LiteralPath $yol -Raw -Encoding UTF8 | ConvertFrom-Json
        $surum = Get-NesneOzelligi -Nesne $manifest -Adlar @('paketSurumu', 'surum', 'version')
        if ($null -eq $surum) { return '' }
        return [string]$surum
    }
    catch { return '' }
}

function Invoke-Betik {
    param(
        [Parameter(Mandatory = $true)][string]$BetikYolu,
        [string]$Etiket = 'Adım',
        [string[]]$Parametreler = @(),
        [int[]]$KabulEdilenKodlar = @(0)
    )
    if (-not (Test-Path -LiteralPath $BetikYolu -PathType Leaf)) {
        Write-Warning "$Etiket betiği pakette bulunamadı: $BetikYolu"
        return 1
    }
    $psExe = Get-WindowsPowerShell
    Write-Host "$Etiket..." -ForegroundColor Cyan
    # Diziler ayrı ayrı argüman olarak geçirilir; '+' komut satırında birleştirme yapmaz.
    # Alt sürecin çıktısı Out-Host ile ekrana gider, fonksiyonun dönüş değerine karışmaz.
    $argumanlar = @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $BetikYolu) + $Parametreler
    & $psExe $argumanlar | Out-Host
    $kod = $LASTEXITCODE
    if ($KabulEdilenKodlar -notcontains $kod) {
        throw "$Etiket $kod koduyla sonlandı."
    }
    return $kod
}

function Get-TurAdi {
    param([string]$Tur)
    switch ($Tur) { 'sirket' { return 'Şirket' } 'ozel' { return 'Özel' } default { return 'Bireysel' } }
}

function Get-KurulumOzellikleri {
    # Türün varsayılanı; aynı türde güncellemede önceki kurulum seçimi; en son açık parametreler.
    param(
        [Parameter(Mandatory = $true)][string]$Tur,
        [object]$Mevcut,
        [string]$HatirlatmaSecimi = '',
        [string]$KilitSecimi = ''
    )
    $oz = [ordered]@{ hatirlatmalar = ($Tur -ne 'sirket'); ekranKilidi = ($Tur -eq 'bireysel') }
    if ($null -ne $Mevcut) {
        $mevcutTur = Get-NesneOzelligi -Nesne $Mevcut -Adlar @('kurulumTuru')
        $eski = $Mevcut.PSObject.Properties['ozellikler']
        if ($null -ne $mevcutTur -and $mevcutTur.ToLowerInvariant() -eq $Tur -and $null -ne $eski -and $null -ne $eski.Value) {
            foreach ($ad in @('hatirlatmalar', 'ekranKilidi')) {
                $p = $eski.Value.PSObject.Properties[$ad]
                if ($null -ne $p -and $p.Value -is [bool]) { $oz[$ad] = $p.Value }
            }
        }
    }
    if ($HatirlatmaSecimi) { $oz.hatirlatmalar = ($HatirlatmaSecimi -eq 'Acik') }
    if ($KilitSecimi) { $oz.ekranKilidi = ($KilitSecimi -eq 'Acik') }
    if ($Tur -eq 'sirket') {
        if ($HatirlatmaSecimi -eq 'Acik') { Write-Warning 'Şirket kurulumunda hatırlatma yoktur; -Hatirlatmalar Acik yok sayıldı.' }
        $oz.hatirlatmalar = $false
    }
    return $oz
}

function Write-KurulumBilgisi {
    param(
        [Parameter(Mandatory = $true)][string]$Hedef,
        [Parameter(Mandatory = $true)][string]$KurulumRolu,
        [string]$PaketSurumu = '',
        [string]$CihazId = '',
        [string]$Tur = 'bireysel',
        [System.Collections.IDictionary]$Ozellikler
    )
    if ($null -eq $Ozellikler) { $Ozellikler = Get-KurulumOzellikleri -Tur $Tur }
    $bilgi = [ordered]@{
        surum = 1
        rol = $KurulumRolu
        kurulumTuru = $Tur
        ozellikler = [ordered]@{ hatirlatmalar = [bool]$Ozellikler['hatirlatmalar']; ekranKilidi = [bool]$Ozellikler['ekranKilidi'] }
        paketSurumu = $PaketSurumu
        kurulumTarihiUtc = [DateTime]::UtcNow.ToString('o')
        cihazId = $CihazId
        kurulumDizini = $Hedef
        calistiranKullanici = [Environment]::UserName
    }
    $bilgiYolu = Join-Path $Hedef 'dagitik\kurulum-bilgisi.json'
    # Kopyalama yalnızca dosyaları taşır; hedefte boş klasör oluşmaz.
    $bilgiKlasoru = Split-Path -Parent $bilgiYolu
    if (-not (Test-Path -LiteralPath $bilgiKlasoru -PathType Container)) {
        New-Item -ItemType Directory -Path $bilgiKlasoru -Force | Out-Null
    }
    $bilgi | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $bilgiYolu -Encoding UTF8
}

try {
    if ($Rol -eq 'AnaYonetici') { $Rol = 'Admin' }
    elseif ($Rol -eq 'Istemci') { $Rol = 'Kullanici' }

    if ([string]::IsNullOrWhiteSpace($Rol)) {
        if ($Sessiz) { throw 'Sessiz kurulum için -Rol Admin veya -Rol Kullanici zorunludur.' }
        Write-Host ''
        Write-Host 'Aizen - Kurulum' -ForegroundColor Cyan
        Write-Host '1) Şirket · yönetici bilgisayarı - çalışan bilgisayarlarının özetlerini burada görürsün'
        Write-Host '2) Şirket · çalışan bilgisayarı  - bu bilgisayar ölçülür, istersen merkeze bağlanır'
        Write-Host '3) Bireysel kullanım             - kendi çalışmanı ölçer; hatırlatma ve ekran kilidi açık'
        Write-Host '   (Özel kurulum için: -Rol ... -KurulumTuru Ozel -Hatirlatmalar Acik|Kapali -EkranKilidi Acik|Kapali)'
        $secim = Read-Host 'Kurulum türünü seç (1/2/3)'
        switch ($secim.Trim()) {
            '1' { $Rol = 'Admin'; if (-not $KurulumTuru) { $KurulumTuru = 'Sirket' } }
            '2' { $Rol = 'Kullanici'; if (-not $KurulumTuru) { $KurulumTuru = 'Sirket' } }
            '3' { $Rol = 'Kullanici'; if (-not $KurulumTuru) { $KurulumTuru = 'Bireysel' } }
            default { throw 'Geçerli bir kurulum türü seçilmedi.' }
        }
    }

    $paketKoku = Get-TamYol -Yol $PSScriptRoot
    $uygulamaKaynagi = Join-Path $paketKoku 'uygulama'
    if (-not (Test-Path -LiteralPath $uygulamaKaynagi -PathType Container)) {
        throw "Uygulama yükü bulunamadı: $uygulamaKaynagi"
    }

    if ([string]::IsNullOrWhiteSpace($KurulumDizini)) {
        if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
            throw 'LOCALAPPDATA ortam değişkeni bulunamadı; -KurulumDizini belirtin.'
        }
        $KurulumDizini = Join-Path $env:LOCALAPPDATA 'CalismaTakipSistemi'
    }
    $hedefKoku = Get-TamYol -Yol $KurulumDizini
    $surucuKoku = [System.IO.Path]::GetPathRoot($hedefKoku).TrimEnd('\')
    if ($hedefKoku.TrimEnd('\') -ieq $surucuKoku) { throw 'Kurulum dizini bir sürücü kökü olamaz.' }
    if ((Test-AltYol -AltYol $hedefKoku -UstYol $paketKoku) -or (Test-AltYol -AltYol $paketKoku -UstYol $hedefKoku)) {
        throw 'Kurulum dizini, ZIP paketinin içinde veya üstünde olamaz.'
    }

    # Kurulum türü ve özellikler: açık parametre -> mevcut kurulum -> CT_KURULUM_TURU -> Bireysel
    $mevcutBilgi = $null
    $mevcutBilgiYolu = Join-Path $hedefKoku 'dagitik\kurulum-bilgisi.json'
    if (Test-Path -LiteralPath $mevcutBilgiYolu -PathType Leaf) {
        try { $mevcutBilgi = Get-Content -LiteralPath $mevcutBilgiYolu -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $mevcutBilgi = $null }
    }
    if (-not [string]::IsNullOrWhiteSpace($KurulumTuru)) { $kurulumTuruSecimi = $KurulumTuru }
    elseif ($null -ne $mevcutBilgi) {
        # Türü yazılmamış eski kurulum bireysel davranışla çalışıyordu; güncelleme bunu değiştirmez
        $kurulumTuruSecimi = Get-NesneOzelligi -Nesne $mevcutBilgi -Adlar @('kurulumTuru')
        if ([string]::IsNullOrWhiteSpace($kurulumTuruSecimi)) { $kurulumTuruSecimi = 'Bireysel' }
    }
    elseif (-not [string]::IsNullOrWhiteSpace($env:CT_KURULUM_TURU)) { $kurulumTuruSecimi = $env:CT_KURULUM_TURU }
    else { $kurulumTuruSecimi = 'Bireysel' }
    $tur = $kurulumTuruSecimi.Trim().ToLowerInvariant()
    if (@('bireysel', 'sirket', 'ozel') -notcontains $tur) { throw "Geçersiz kurulum türü: $kurulumTuruSecimi (Bireysel, Sirket ya da Ozel)" }
    $ozellikler = Get-KurulumOzellikleri -Tur $tur -Mevcut $mevcutBilgi -HatirlatmaSecimi $Hatirlatmalar -KilitSecimi $EkranKilidi
    $hatirlatmaMetni = if ($tur -eq 'sirket') { 'hatırlatma yok' } elseif ($ozellikler.hatirlatmalar) { 'hatırlatma açık' } else { 'hatırlatma kapalı' }
    $kilitMetni = if ($ozellikler.ekranKilidi) { 'ekran kilidi açık' } else { 'ekran kilidi kapalı' }
    Write-Host ("Kurulum türü: {0} · {1} · {2}" -f (Get-TurAdi $tur), $hatirlatmaMetni, $kilitMetni)

    $kayit = $null
    if ($Rol -eq 'Kullanici' -and -not [string]::IsNullOrWhiteSpace($KayitDosyasi)) {
        $kayit = Test-CihazKaydi -Yol $KayitDosyasi
    }

    $guncelleme = Test-Path -LiteralPath (Join-Path $hedefKoku 'hatirlatici') -PathType Container
    if (-not (Test-Path -LiteralPath $hedefKoku -PathType Container)) {
        New-Item -ItemType Directory -Path $hedefKoku -Force | Out-Null
    }

    if ($guncelleme) { Write-Host "Mevcut kurulum güncelleniyor: $hedefKoku" -ForegroundColor Cyan }
    else { Write-Host "Uygulama dosyaları kuruluyor: $hedefKoku" -ForegroundColor Cyan }
    $kopyaSonucu = Copy-UygulamaYuku -Kaynak $uygulamaKaynagi -Hedef $hedefKoku
    Write-Host ("  {0} dosya yazıldı, {1} kullanıcı dosyası korundu." -f $kopyaSonucu.Kopyalanan, $kopyaSonucu.Korunan)

    # Kişisel kurallar, ayarlar ve periyot pakette bulunmaz; yalnızca eksik dosyayı nötr
    # şablondan oluştur. Mevcut dosya (güncelleme) baytına kadar korunur.
    foreach ($ad in @('kurallar', 'ayarlar', 'periyot')) {
        $kullaniciYolu = Join-Path $hedefKoku "hatirlatici\$ad.json"
        if (-not (Test-Path -LiteralPath $kullaniciYolu)) {
            [System.IO.File]::Copy((Join-Path $hedefKoku "hatirlatici\$ad.varsayilan.json"), $kullaniciYolu, $false)
        }
    }
    $paketSurumu = Get-PaketSurumu -PaketKoku $paketKoku
    $dagitikKoku = Join-Path $hedefKoku 'dagitik'
    $hatirlaticiKoku = Join-Path $hedefKoku 'hatirlatici'
    $psExe = Get-WindowsPowerShell

    if ($YalnizKopyala) {
        Write-KurulumBilgisi -Hedef $hedefKoku -KurulumRolu $Rol -PaketSurumu $paketSurumu -Tur $tur -Ozellikler $ozellikler
        Write-Host ''
        Write-Host 'Yalnızca dosyalar kopyalandı: görev, kısayol ve merkez bağlantısı ayarlanmadı.' -ForegroundColor Yellow
        Write-Host "Kurulum dizini: $hedefKoku"
        exit 0
    }

    # İnternetten indirilen paketten gelen dosyalarda "engellendi" işareti kalabilir
    try {
        Get-ChildItem -LiteralPath $hedefKoku -Recurse -File -ErrorAction SilentlyContinue |
            Unblock-File -ErrorAction SilentlyContinue
    }
    catch { }

    # Yerel takip her iki rolde de kurulur: görev, izleyici ve kısayollar
    [void](Invoke-Betik -BetikYolu (Join-Path $hatirlaticiKoku 'baslangic.ps1') -Etiket 'Yerel takip hazırlanıyor')
    . (Join-Path $dagitikKoku 'kisayol.ps1')
    $kisayollar = @(New-CtKurulumKisayollari -UygulamaKok $hedefKoku -MerkezPaneli:($Rol -eq 'Admin'))
    $kisayollar += @(New-CtBaslatMenusuKisayollari -UygulamaKok $hedefKoku -MerkezPaneli:($Rol -eq 'Admin'))
    Write-Host ("  {0} kısayol oluşturuldu (masaüstü, başlangıç, Başlat menüsü)." -f $kisayollar.Count)
    [void](Register-CtUygulamaKaydi -UygulamaKok $hedefKoku -Surum $paketSurumu -Rol $Rol)
    Write-Host '  Windows "Uygulamalar" listesine kaydedildi (kaldırma oradan da yapılabilir).'

    $cihazId = ''
    if ($Rol -eq 'Admin') {
        # 2 = yönetici onayı verilmedi; kurulumun kalanı yine de geçerlidir
        $merkezKodu = Invoke-Betik -BetikYolu (Join-Path $dagitikKoku 'ana-kurulum.ps1') `
            -Etiket 'Merkez dinleyicisi kuruluyor' -Parametreler @('-Kur') -KabulEdilenKodlar @(0, 2)
        if ($merkezKodu -eq 2) {
            Write-Warning ('Yönetici onayı verilmedi: merkez dinleyicisi kurulmadı. Ayarlar yazıldı. ' +
                'Kurulum-Admin.cmd dosyasına sağ tıklayıp "Yönetici olarak çalıştır" ile tekrar deneyebilirsin.')
        }
        Write-KurulumBilgisi -Hedef $hedefKoku -KurulumRolu $Rol -PaketSurumu $paketSurumu -Tur $tur -Ozellikler $ozellikler
        Write-Host ''
        Write-Host 'Yönetici kurulumu tamamlandı.' -ForegroundColor Green
        Write-Host 'Sıradaki adım: izlenecek her bilgisayar için eşleşme kodu üret.'
        Write-Host "  cd `"$dagitikKoku`""
        Write-Host "  .\cihaz-ekle.ps1 -Ad 'Ofis-PC-01'"
        Write-Host 'Kodu kullanıcıya söyle; o kendi bilgisayarında Kurulum-Kullanici.cmd çalıştırıp girsin.'
        Write-Host 'Özetleri masaüstündeki "Aizen Merkez" kısayolundan izleyebilirsin.'
    }
    else {
        $baglandi = $false
        if ($null -ne $kayit) {
            # Eski yöntem: dosya tabanlı kayıt paketi
            $merkezYolu = Join-Path $hatirlaticiKoku 'merkez.json'
            if (Test-Path -LiteralPath $merkezYolu -PathType Leaf) {
                Copy-Item -LiteralPath $merkezYolu -Destination "$merkezYolu.yedek-$(Get-Date -Format 'yyyyMMdd-HHmmss')" -Force
            }
            Copy-Item -LiteralPath $kayit.Yol -Destination $merkezYolu -Force
            [void](Invoke-Betik -BetikYolu (Join-Path $dagitikKoku 'istemci-kurulum.ps1') `
                -Etiket 'Merkez bağlantısı kuruluyor' -Parametreler @('-Kur', '-YapilandirmaYolu', $merkezYolu))
            $cihazId = $kayit.CihazId
            $baglandi = $true
        }
        else {
            if ([string]::IsNullOrWhiteSpace($Kod) -and -not $Sessiz) {
                Write-Host ''
                $cevap = Read-Host 'Bu bilgisayar bir yönetici merkezine bağlansın mı? (E/h)'
                if ($cevap.Trim().ToUpperInvariant() -in @('E', 'EVET', 'Y', 'YES')) {
                    if ([string]::IsNullOrWhiteSpace($SunucuUrl)) { $SunucuUrl = Read-Host 'Merkez adresi (örnek: http://192.168.1.20:8787)' }
                    $Kod = Read-Host 'Yöneticinin verdiği eşleşme kodu'
                }
            }
            if (-not [string]::IsNullOrWhiteSpace($Kod)) {
                $kayitParametreleri = @('-SunucuUrl', $SunucuUrl, '-Kod', $Kod)
                if ($Onayla) { $kayitParametreleri += '-Onayla' }
                if ($Sessiz) { $kayitParametreleri += '-Sessiz' }
                # 2 = kullanıcı onay vermedi; bu bir hata değil
                $kayitKodu = Invoke-Betik -BetikYolu (Join-Path $dagitikKoku 'istemci-kayit.ps1') `
                    -Etiket 'Merkeze bağlanılıyor' -Parametreler $kayitParametreleri -KabulEdilenKodlar @(0, 2)
                if ($kayitKodu -eq 0) { $baglandi = $true }
                else { Write-Warning 'Onay verilmedi; bu bilgisayar merkeze bağlanmadı. Yerel takip çalışmaya devam ediyor.' }
            }
        }
        Write-KurulumBilgisi -Hedef $hedefKoku -KurulumRolu $Rol -PaketSurumu $paketSurumu -Tur $tur -Ozellikler $ozellikler -CihazId $cihazId
        Write-Host ''
        Write-Host 'Kullanıcı kurulumu tamamlandı.' -ForegroundColor Green
        if ($baglandi) {
            Write-Host 'Bu bilgisayar merkeze bağlı. Ne gönderildiğini görmek için:'
            Write-Host "  .\dagitik\istemci-durum.ps1"
            Write-Host 'Bağlantıyı kapatmak için:'
            Write-Host "  .\dagitik\kaldir.ps1 -YalnizMerkez"
        }
        else {
            Write-Host 'Bu bilgisayar tek başına çalışıyor; hiçbir yere veri göndermiyor.'
            Write-Host 'Sonradan bağlanmak istersen yöneticiden kod al ve şunu çalıştır:'
            Write-Host "  .\dagitik\istemci-kayit.ps1 -SunucuUrl http://sunucu:8787 -Kod KOD"
        }
        Write-Host 'Günlük takibi masaüstündeki "Aizen" kısayolundan açabilirsin.'
    }

    Write-Host ''
    Write-Host "Kurulum dizini: $hedefKoku"
    exit 0
}
catch {
    Write-Error "Kurulum tamamlanamadı: $($_.Exception.Message)"
    exit 1
}
