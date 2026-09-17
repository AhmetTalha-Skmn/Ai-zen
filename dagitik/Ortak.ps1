# Ortak yardimcilar. Bu dosya hem merkez hem de istemci tarafinda kullanilir.
# PowerShell 5.1 uyumludur; gizli anahtarlar loglara veya hata mesajlaryna yazilmaz.

function Get-DagitikUygulamaKok {
    param([string]$Baslangic = $PSScriptRoot)
    return (Split-Path -LiteralPath $Baslangic)
}

function Get-DagitikDeger {
    param(
        [object]$Nesne,
        [string]$Ad,
        [object]$Varsayilan = $null
    )

    if ($null -eq $Nesne) { return $Varsayilan }
    if ($Nesne -is [System.Collections.IDictionary]) {
        if ($Nesne.Contains($Ad)) { return $Nesne[$Ad] }
        return $Varsayilan
    }
    $alan = $Nesne.PSObject.Properties[$Ad]
    if ($null -eq $alan -or $null -eq $alan.Value) { return $Varsayilan }
    return $alan.Value
}

function Set-DagitikDeger {
    param([object]$Nesne, [string]$Ad, [object]$Deger)
    if ($Nesne -is [System.Collections.IDictionary]) {
        $Nesne[$Ad] = $Deger
        return
    }
    $alan = $Nesne.PSObject.Properties[$Ad]
    if ($null -eq $alan) {
        $Nesne | Add-Member -MemberType NoteProperty -Name $Ad -Value $Deger -Force
    }
    else { $alan.Value = $Deger }
}

function Test-DagitikCihazKimligi {
    param([string]$CihazKimligi)
    # -cmatch: -match tr-TR'de 'I'yi noktasiz i'ye katlar; baska dilde ya da platformda uretilmis
    # 'I' iceren kimlik Turkce Windows'ta reddedilirdi. Sinif zaten iki durumu kapsar.
    return (-not [string]::IsNullOrWhiteSpace($CihazKimligi) -and $CihazKimligi -cmatch '^[A-Za-z0-9_-]{3,64}$')
}

function New-DagitikAnahtar {
    $baytlar = New-Object byte[] 32
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($baytlar) } finally { $rng.Dispose() }
    return [Convert]::ToBase64String($baytlar)
}

function Get-DagitikHmac {
    param(
        [Parameter(Mandatory = $true)][string]$Anahtar,
        [Parameter(Mandatory = $true)][string]$ZamanDamgasi,
        [Parameter(Mandatory = $true)][string]$Govde
    )

    $anahtarBayt = [Convert]::FromBase64String($Anahtar)
    $metin = "$ZamanDamgasi`n$Govde"
    $hmac = New-Object System.Security.Cryptography.HMACSHA256(,$anahtarBayt)
    try {
        $sonuc = $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($metin))
        return ([BitConverter]::ToString($sonuc)).Replace('-', '').ToLowerInvariant()
    }
    finally { $hmac.Dispose() }
}

function Test-DagitikSabitZamanliEsitlik {
    param([string]$Birinci, [string]$Ikinci)
    if ([string]::IsNullOrWhiteSpace($Birinci) -or [string]::IsNullOrWhiteSpace($Ikinci)) { return $false }
    $a = [System.Text.Encoding]::ASCII.GetBytes($Birinci.ToLowerInvariant())
    $b = [System.Text.Encoding]::ASCII.GetBytes($Ikinci.ToLowerInvariant())
    if ($a.Length -ne $b.Length) { return $false }
    [int]$fark = 0
    for ($i = 0; $i -lt $a.Length; $i++) { $fark = $fark -bor ($a[$i] -bxor $b[$i]) }
    return ($fark -eq 0)
}

function Get-DagitikEntropi {
    param([string]$Amac)
    $tohum = "CalismaTakipDagitik|$Amac|v1"
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($tohum)) }
    finally { $sha.Dispose() }
}

function Initialize-DagitikDpapi {
    # Windows PowerShell 5.1 bazi oturumlarda System.Security derlemesini otomatik
    # yuklemez; DPAPI turunu kullanmadan once yuklemek gerekir.
    try { [void][System.Security.Cryptography.ProtectedData] }
    catch { Add-Type -AssemblyName System.Security -ErrorAction Stop }
}

function Protect-DagitikAnahtar {
    param([Parameter(Mandatory = $true)][string]$Anahtar, [Parameter(Mandatory = $true)][string]$Amac)
    Initialize-DagitikDpapi
    $veri = [System.Text.Encoding]::UTF8.GetBytes($Anahtar)
    $korunmus = [System.Security.Cryptography.ProtectedData]::Protect(
        $veri, (Get-DagitikEntropi $Amac), [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
    return [Convert]::ToBase64String($korunmus)
}

function Unprotect-DagitikAnahtar {
    param([Parameter(Mandatory = $true)][string]$KorunmusAnahtar, [Parameter(Mandatory = $true)][string]$Amac)
    Initialize-DagitikDpapi
    $veri = [Convert]::FromBase64String($KorunmusAnahtar)
    $acik = [System.Security.Cryptography.ProtectedData]::Unprotect(
        $veri, (Get-DagitikEntropi $Amac), [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
    return [System.Text.Encoding]::UTF8.GetString($acik)
}

function Read-DagitikJson {
    param([Parameter(Mandatory = $true)][string]$Yol)
    if (-not (Test-Path -LiteralPath $Yol)) { return $null }
    try {
        $ham = [System.IO.File]::ReadAllText($Yol, [System.Text.Encoding]::UTF8)
        if ([string]::IsNullOrWhiteSpace($ham)) { return $null }
        return ($ham | ConvertFrom-Json)
    }
    catch { return $null }
}

function Write-DagitikJsonAtomik {
    param(
        [Parameter(Mandatory = $true)][object]$Nesne,
        [Parameter(Mandatory = $true)][string]$Yol,
        [int]$Derinlik = 8
    )
    $klasor = Split-Path -LiteralPath $Yol
    if (-not (Test-Path -LiteralPath $klasor)) { [void][System.IO.Directory]::CreateDirectory($klasor) }
    $gecici = Join-Path $klasor ('.' + [System.IO.Path]::GetRandomFileName() + '.tmp')
    $json = $Nesne | ConvertTo-Json -Depth $Derinlik
    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    try {
        [System.IO.File]::WriteAllText($gecici, $json, $utf8Bom)
        Move-Item -LiteralPath $gecici -Destination $Yol -Force
    }
    finally {
        if (Test-Path -LiteralPath $gecici) { Remove-Item -LiteralPath $gecici -Force -ErrorAction SilentlyContinue }
    }
}

function ConvertTo-DagitikSinirliMetin {
    param([object]$Deger, [int]$EnFazla = 120)
    if ($null -eq $Deger) { return '' }
    $metin = ([string]$Deger).Trim() -replace '[\r\n\t]+', ' '
    if ($metin.Length -gt $EnFazla) { return $metin.Substring(0, $EnFazla) }
    return $metin
}

function ConvertTo-DagitikDakika {
    param([object]$Deger, [int]$EnFazla = 1440)
    [double]$sayi = 0
    if (-not [double]::TryParse(([string]$Deger), [Globalization.NumberStyles]::Float,
        [Globalization.CultureInfo]::InvariantCulture, [ref]$sayi)) {
        [void][double]::TryParse(([string]$Deger), [ref]$sayi)
    }
    if ($sayi -lt 0) { $sayi = 0 }
    if ($sayi -gt $EnFazla) { $sayi = $EnFazla }
    return [math]::Round($sayi)
}

# ---------- eslesme kodu ----------
# Kullanici kurulumu merkeze bu kodla baglanir. Yonetici kodu uretir, kullaniciya
# soyler; kod tek kullanimliktir ve sureli olarak gecerlidir.
#   - Merkez kodun kendisini saklamaz, PBKDF2 ozetini saklar (kayitTuzu ile).
#   - Cihaz anahtari aga duz metin cikmaz: koddan AYRI bir tuzla turetilen
#     anahtarla sifrelenir ve HMAC ile imzalanir (sifre-sonra-imza).
#   - Iki tuz ayridir; ayni tuz kullanilsaydi saklanan ozet, sifreleme
#     anahtarinin ilk 32 baytiyla ayni olurdu.
# Alfabe: Crockford base32 (I, L, O, U yok; 256 mod 32 = 0, sapma olusmaz).
$script:DAGITIK_KOD_ALFABE = '0123456789ABCDEFGHJKMNPQRSTVWXYZ'

function New-DagitikEslesmeKodu {
    param([int]$Uzunluk = 12)
    if ($Uzunluk -lt 8 -or $Uzunluk -gt 32) { throw 'Kod uzunlugu 8-32 arasinda olmalidir.' }
    $baytlar = New-Object byte[] $Uzunluk
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($baytlar) } finally { $rng.Dispose() }
    $yazi = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt $Uzunluk; $i++) {
        if ($i -gt 0 -and ($i % 4) -eq 0) { [void]$yazi.Append('-') }
        [void]$yazi.Append($script:DAGITIK_KOD_ALFABE[$baytlar[$i] -band 31])
    }
    return $yazi.ToString()
}

function ConvertTo-DagitikKodNormal {
    param([string]$Kod)
    if ([string]::IsNullOrWhiteSpace($Kod)) { return '' }
    # -creplace: -replace tr-TR'de 'I'yi silerdi (1'e cevrilmesi gerekirken)
    $temiz = ($Kod.ToUpperInvariant() -creplace '[^0-9A-Z]', '')
    # Crockford: elle yazarken karistirilan harfler rakama cevrilir
    return $temiz.Replace('I', '1').Replace('L', '1').Replace('O', '0')
}

function Get-DagitikTuz {
    param([int]$Uzunluk = 16)
    $t = New-Object byte[] $Uzunluk
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($t) } finally { $rng.Dispose() }
    return [Convert]::ToBase64String($t)
}

function Get-DagitikKodAnahtari {
    param(
        [Parameter(Mandatory = $true)][string]$Kod,
        [Parameter(Mandatory = $true)][string]$Tuz,
        [int]$Tur = 120000,
        [int]$Uzunluk = 64
    )
    $tuzBayt = [Convert]::FromBase64String($Tuz)
    $turetici = $null
    try {
        $turetici = New-Object System.Security.Cryptography.Rfc2898DeriveBytes(
            $Kod, $tuzBayt, $Tur, [System.Security.Cryptography.HashAlgorithmName]::SHA256)
    }
    catch {
        # .NET 4.7.2 oncesi: SHA256 asiri yuk yok, SHA1 tabanli PBKDF2'ye dusulur
        $turetici = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($Kod, $tuzBayt, $Tur)
    }
    try { return $turetici.GetBytes($Uzunluk) } finally { $turetici.Dispose() }
}

function Get-DagitikKodOzeti {
    param(
        [Parameter(Mandatory = $true)][string]$Kod,
        [Parameter(Mandatory = $true)][string]$Tuz,
        [int]$Tur = 120000
    )
    return [Convert]::ToBase64String((Get-DagitikKodAnahtari -Kod $Kod -Tuz $Tuz -Tur $Tur -Uzunluk 32))
}

function Test-DagitikBaytEsitlik {
    param([byte[]]$Birinci, [byte[]]$Ikinci)
    if ($null -eq $Birinci -or $null -eq $Ikinci) { return $false }
    if ($Birinci.Length -ne $Ikinci.Length -or $Birinci.Length -eq 0) { return $false }
    [int]$fark = 0
    for ($i = 0; $i -lt $Birinci.Length; $i++) { $fark = $fark -bor ($Birinci[$i] -bxor $Ikinci[$i]) }
    return ($fark -eq 0)
}

function Protect-DagitikKodIle {
    param(
        [Parameter(Mandatory = $true)][string]$Metin,
        [Parameter(Mandatory = $true)][string]$Kod,
        [Parameter(Mandatory = $true)][string]$Tuz
    )
    $turetilen = Get-DagitikKodAnahtari -Kod $Kod -Tuz $Tuz -Uzunluk 64
    $aesAnahtar = New-Object byte[] 32; [Array]::Copy($turetilen, 0, $aesAnahtar, 0, 32)
    $macAnahtar = New-Object byte[] 32; [Array]::Copy($turetilen, 32, $macAnahtar, 0, 32)
    $aes = [System.Security.Cryptography.Aes]::Create()
    try {
        $aes.KeySize = 256
        $aes.Key = $aesAnahtar
        $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
        $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
        $aes.GenerateIV()
        $sifreleyici = $aes.CreateEncryptor()
        try {
            $duz = [System.Text.Encoding]::UTF8.GetBytes($Metin)
            $sifreli = $sifreleyici.TransformFinalBlock($duz, 0, $duz.Length)
        }
        finally { $sifreleyici.Dispose() }
        $birlesik = New-Object byte[] ($aes.IV.Length + $sifreli.Length)
        [Array]::Copy($aes.IV, 0, $birlesik, 0, $aes.IV.Length)
        [Array]::Copy($sifreli, 0, $birlesik, $aes.IV.Length, $sifreli.Length)
        $hmac = New-Object System.Security.Cryptography.HMACSHA256(,$macAnahtar)
        try { $etiket = $hmac.ComputeHash($birlesik) } finally { $hmac.Dispose() }
        return [ordered]@{
            iv = [Convert]::ToBase64String($aes.IV)
            veri = [Convert]::ToBase64String($sifreli)
            etiket = [Convert]::ToBase64String($etiket)
        }
    }
    finally { $aes.Dispose() }
}

function Unprotect-DagitikKodIle {
    param(
        [Parameter(Mandatory = $true)][object]$Paket,
        [Parameter(Mandatory = $true)][string]$Kod,
        [Parameter(Mandatory = $true)][string]$Tuz
    )
    $iv = [Convert]::FromBase64String([string](Get-DagitikDeger $Paket 'iv' ''))
    $sifreli = [Convert]::FromBase64String([string](Get-DagitikDeger $Paket 'veri' ''))
    $etiket = [Convert]::FromBase64String([string](Get-DagitikDeger $Paket 'etiket' ''))
    $turetilen = Get-DagitikKodAnahtari -Kod $Kod -Tuz $Tuz -Uzunluk 64
    $aesAnahtar = New-Object byte[] 32; [Array]::Copy($turetilen, 0, $aesAnahtar, 0, 32)
    $macAnahtar = New-Object byte[] 32; [Array]::Copy($turetilen, 32, $macAnahtar, 0, 32)
    $birlesik = New-Object byte[] ($iv.Length + $sifreli.Length)
    [Array]::Copy($iv, 0, $birlesik, 0, $iv.Length)
    [Array]::Copy($sifreli, 0, $birlesik, $iv.Length, $sifreli.Length)
    $hmac = New-Object System.Security.Cryptography.HMACSHA256(,$macAnahtar)
    try { $beklenen = $hmac.ComputeHash($birlesik) } finally { $hmac.Dispose() }
    # Imza once dogrulanir: kod yanlissa ya da paket degistirildiyse cozme denenmez
    if (-not (Test-DagitikBaytEsitlik $beklenen $etiket)) { throw 'Kod yanlis veya paket degistirilmis.' }
    $aes = [System.Security.Cryptography.Aes]::Create()
    try {
        $aes.KeySize = 256
        $aes.Key = $aesAnahtar
        $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
        $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
        $aes.IV = $iv
        $cozucu = $aes.CreateDecryptor()
        try { $duz = $cozucu.TransformFinalBlock($sifreli, 0, $sifreli.Length) }
        finally { $cozucu.Dispose() }
        return [System.Text.Encoding]::UTF8.GetString($duz)
    }
    finally { $aes.Dispose() }
}
