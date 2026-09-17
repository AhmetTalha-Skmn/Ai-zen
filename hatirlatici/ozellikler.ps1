# ============================================================
#  Kurulum turu ve ozellik anahtarlari: hatirlatmalar, ekran kilidi.
#
#  Oncelik (ilk bulunan kazanir):
#    1) hatirlatici\ayarlar.json      kurulumTuru, hatirlatmalar, ekranKilidi  (kullanicinin Ayarlar'daki secimi)
#    2) dagitik\kurulum-bilgisi.json  kurulumTuru, ozellikler.{hatirlatmalar, ekranKilidi}  (kurulumdaki secim)
#    3) turun varsayilani             bireysel: ikisi acik | sirket: ikisi kapali | ozel: hatirlatma acik, kilit kapali
#  Tur hic yazilmamissa (eski kurulum, gelistirme klasoru) bireysel sayilir: davranis degismez.
#  Sirket kurulumunda hatirlatma yoktur (ayar da acamaz); ekran kilidi her turde ayardan acilip kapanir.
#
#  Kullanim: . (Join-Path $hDir 'ozellikler.ps1'); $oz = Get-TakipOzellikleri -HatirlaticiKlasoru $hDir
#  ASCII tutulur (BOM gerekmez). Set-StrictMode altinda da calisir.
# ============================================================
$script:OZ_TURLER = @('bireysel', 'sirket', 'ozel')
$script:OZ_ANAHTARLAR = @('hatirlatmalar', 'ekranKilidi')

function Oz-Deger { param($Nesne, [string]$Ad)
    if ($null -eq $Nesne) { return $null }
    if ($Nesne -is [System.Collections.IDictionary]) { if ($Nesne.Contains($Ad)) { return $Nesne[$Ad] }; return $null }
    $p = $Nesne.PSObject.Properties[$Ad]
    if ($null -eq $p) { return $null }
    return $p.Value }

# true/false disinda elle yazilmis "acik", "0" gibi degerleri de kabul eder; anlasilmazsa $null (yok sayilir)
function Oz-Bool { param($Deger)
    if ($null -eq $Deger) { return $null }
    if ($Deger -is [bool]) { return $Deger }
    if ($Deger -is [int] -or $Deger -is [long]) { return ($Deger -ne 0) }
    $m = ([string]$Deger).Trim().ToLowerInvariant()
    if (@('true', '1', 'acik', 'evet', 'on') -contains $m) { return $true }
    if (@('false', '0', 'kapali', 'hayir', 'off') -contains $m) { return $false }
    return $null }

function Oz-Tur { param($Deger)
    if ($null -eq $Deger) { return $null }
    # "Sirket" yazimi s-cedilla ile, "Ozel" o-umlaut ile de gelebilir: ASCII karsiligina indirilir
    $m = ([string]$Deger).Trim().ToLowerInvariant().Replace([string][char]0x015F, 's').Replace([string][char]0x00F6, 'o')
    if ($script:OZ_TURLER -contains $m) { return $m }
    return $null }

function Oz-TurVarsayilani { param([string]$Tur)
    switch ($Tur) {
        'sirket' { return @{ hatirlatmalar = $false; ekranKilidi = $false } }
        'ozel'   { return @{ hatirlatmalar = $true;  ekranKilidi = $false } }
        default  { return @{ hatirlatmalar = $true;  ekranKilidi = $true } }
    } }

function Oz-JsonOku { param([string]$Yol)
    if ([string]::IsNullOrWhiteSpace($Yol) -or -not (Test-Path -LiteralPath $Yol -PathType Leaf)) { return $null }
    try {
        $ham = [System.IO.File]::ReadAllText($Yol, [System.Text.Encoding]::UTF8)
        if ([string]::IsNullOrWhiteSpace($ham)) { return $null }
        return (ConvertFrom-Json $ham)
    } catch { return $null } }

function Oz-KurulumBilgisiYolu { param([string]$HatirlaticiKlasoru)
    return (Join-Path (Split-Path $HatirlaticiKlasoru -Parent) 'dagitik\kurulum-bilgisi.json') }

# Etkin ozellikler. -Ayarlar: zaten okunmus ayarlar.json nesnesi (verilirse dosya tekrar okunmaz)
function Get-TakipOzellikleri { param([string]$HatirlaticiKlasoru, $Ayarlar)
    $ayar = $Ayarlar
    if ($null -eq $ayar -and $HatirlaticiKlasoru) { $ayar = Oz-JsonOku (Join-Path $HatirlaticiKlasoru 'ayarlar.json') }
    $bilgi = $null
    if ($HatirlaticiKlasoru) { $bilgi = Oz-JsonOku (Oz-KurulumBilgisiYolu $HatirlaticiKlasoru) }
    $bilgiOz = Oz-Deger $bilgi 'ozellikler'

    $tur = Oz-Tur (Oz-Deger $ayar 'kurulumTuru'); $turKaynagi = 'ayarlar'
    if (-not $tur) { $tur = Oz-Tur (Oz-Deger $bilgi 'kurulumTuru'); $turKaynagi = 'kurulum' }
    if (-not $tur) { $tur = 'bireysel'; $turKaynagi = 'varsayilan' }
    $varsayilan = Oz-TurVarsayilani $tur

    $sonuc = [ordered]@{ kurulumTuru = $tur; turKaynagi = $turKaynagi; hatirlatmaAyarlanabilir = ($tur -ne 'sirket') }
    foreach ($ad in $script:OZ_ANAHTARLAR) {
        $deger = Oz-Bool (Oz-Deger $ayar $ad); $kaynak = 'ayarlar'
        if ($null -eq $deger) { $deger = Oz-Bool (Oz-Deger $bilgiOz $ad); $kaynak = 'kurulum' }
        if ($null -eq $deger) { $deger = $varsayilan[$ad]; $kaynak = 'varsayilan' }
        $sonuc[$ad] = [bool]$deger
        $sonuc[$ad + 'Kaynagi'] = $kaynak
        $sonuc[$ad + 'Varsayilani'] = [bool]$varsayilan[$ad]
    }
    if ($tur -eq 'sirket') { $sonuc.hatirlatmalar = $false; $sonuc.hatirlatmalarKaynagi = 'kurulum turu' }
    return [pscustomobject]$sonuc }

# ayarlar.json'u sirali sozluk olarak okur. Bilinmeyen alanlar (yedekKlasoru vb.) aynen korunur.
function Oz-AyarOku { param([string]$HatirlaticiKlasoru)
    $o = [ordered]@{ hedef = 240; duraklat = '' }
    $a = Oz-JsonOku (Join-Path $HatirlaticiKlasoru 'ayarlar.json')
    if ($null -ne $a) { foreach ($p in $a.PSObject.Properties) { $o[$p.Name] = $p.Value } }
    return $o }

# Tam dosyayi yazar: once gecici dosya, JSON dogrulanir, sonra yerine konur (yarim dosya kalmaz).
function Oz-AyarYaz { param([string]$HatirlaticiKlasoru, $Ayarlar)
    $yol = Join-Path $HatirlaticiKlasoru 'ayarlar.json'
    $gecici = "$yol.yeni"
    $json = $Ayarlar | ConvertTo-Json -Depth 6
    [void](ConvertFrom-Json $json)
    [System.IO.File]::WriteAllText($gecici, $json, (New-Object System.Text.UTF8Encoding($true)))
    if ([System.IO.File]::Exists($yol)) {
        try { [System.IO.File]::Replace($gecici, $yol, [NullString]::Value) }
        catch { [System.IO.File]::Copy($gecici, $yol, $true); [System.IO.File]::Delete($gecici) }
    } else { [System.IO.File]::Move($gecici, $yol) } }

# Degisiklikleri mevcut ayarlarin uzerine yazar. Deger $null ise anahtar silinir: kurulumdaki/turun varsayilani gecerli olur.
function Oz-AyarGuncelle { param([string]$HatirlaticiKlasoru, [System.Collections.IDictionary]$Degisiklikler)
    # Okunamayan (bozuk) dosya varsayilanlarla ezilmeden once kenara alinir; icindeki elle yazilmis alanlar kaybolmasin
    $yol = Join-Path $HatirlaticiKlasoru 'ayarlar.json'
    if ([System.IO.File]::Exists($yol) -and $null -eq (Oz-JsonOku $yol) -and (Get-Item -LiteralPath $yol).Length -gt 3) {
        [System.IO.File]::Copy($yol, "$yol.bozuk-$((Get-Date).ToString('yyyyMMdd-HHmmss'))", $true) }
    $o = Oz-AyarOku $HatirlaticiKlasoru
    foreach ($k in @($Degisiklikler.Keys)) {
        if ($null -eq $Degisiklikler[$k]) { if ($o.Contains($k)) { $o.Remove($k) } }
        else { $o[$k] = $Degisiklikler[$k] }
    }
    Oz-AyarYaz $HatirlaticiKlasoru $o
    return $o }

# Arayuz metinleri icin (Turkce karakterler kod noktasiyla: dosya ASCII kalir)
function Oz-TurAdi { param([string]$Tur)
    switch ($Tur) {
        'sirket' { return ([string][char]0x015E + 'irket') }
        'ozel'   { return ([string][char]0x00D6 + 'zel') }
        default  { return 'Bireysel' }
    } }
