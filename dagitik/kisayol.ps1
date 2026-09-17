# Kisayol yardimcilari: kurulum ve kaldirma ayni kodu kullanir.
# Masaustu ve Startup kisayollari, klasor tasinsa bile bu kurulumu gostermelidir.
# Konsol flasi olmasin diye arka plan isleri wscript + gizli.vbs uzerinden baslar.

# Uygulamanin gorunen adi Aizen. Gorev adlari, kurulum klasoru ve kayit anahtari eski teknik
# adlarini korur (mevcut kurulumlar ve canli gorev bozulmasin); yalnizca kullanicinin gordugu adlar degisti.
$script:CT_PANEL_KISAYOL = 'Aizen.lnk'
$script:CT_ACILIS_KISAYOL = 'Aizen.lnk'
$script:CT_MERKEZ_KISAYOL = 'Aizen Merkez.lnk'
# Onceki adlar: kurulum/guncelleme yenisini olusturunca eskisini siler, kaldirma ikisini de siler.
$script:CT_ESKI_PANEL_KISAYOL = 'Calisma Takibi.lnk'
$script:CT_ESKI_ACILIS_KISAYOL = 'Calisma Takip Sistemi.lnk'
$script:CT_ESKI_MERKEZ_KISAYOL = 'Calisma Takip Merkezi.lnk'

function Remove-CtEskiKisayol {
    param([Parameter(Mandatory = $true)][string]$Klasor, [Parameter(Mandatory = $true)][string]$Ad)
    $yol = Join-Path $Klasor $Ad
    if (Test-Path -LiteralPath $yol -PathType Leaf) { Remove-Item -LiteralPath $yol -Force -ErrorAction SilentlyContinue }
}

function Set-CtKisayol {
    param(
        [Parameter(Mandatory = $true)][string]$Yol,
        [Parameter(Mandatory = $true)][string]$Hedef,
        [string]$Argumanlar = '',
        [string]$CalismaDizini = '',
        [string]$Ikon = '',
        [int]$PencereStili = 7
    )
    $kabuk = New-Object -ComObject WScript.Shell
    $kisayol = $kabuk.CreateShortcut($Yol)
    $kisayol.TargetPath = $Hedef
    $kisayol.Arguments = $Argumanlar
    if ($CalismaDizini) { $kisayol.WorkingDirectory = $CalismaDizini }
    if ($Ikon) { $kisayol.IconLocation = $Ikon }
    $kisayol.WindowStyle = $PencereStili
    $kisayol.Save()
}

function New-CtKurulumKisayollari {
    # Yerel takip icin: masaustunde kontrol paneli, Startup'ta acilis watchdog'u.
    param(
        [Parameter(Mandatory = $true)][string]$UygulamaKok,
        [switch]$MerkezPaneli
    )
    $hatirlatici = Join-Path $UygulamaKok 'hatirlatici'
    $psExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $wscript = "$env:SystemRoot\System32\wscript.exe"
    $vbs = Join-Path $hatirlatici 'gizli.vbs'
    $olusan = @()

    $kontrolPs = Join-Path $hatirlatici 'kontrol.ps1'
    $masaustu = [Environment]::GetFolderPath('Desktop')
    if ((Test-Path -LiteralPath $kontrolPs) -and (Test-Path -LiteralPath $masaustu)) {
        $yol = Join-Path $masaustu $script:CT_PANEL_KISAYOL
        Set-CtKisayol -Yol $yol -Hedef $psExe `
            -Argumanlar ("-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$kontrolPs`"") `
            -CalismaDizini $UygulamaKok -Ikon "$env:SystemRoot\System32\shell32.dll,16"
        $olusan += $yol
        Remove-CtEskiKisayol -Klasor $masaustu -Ad $script:CT_ESKI_PANEL_KISAYOL
    }

    $baslangicPs = Join-Path $hatirlatici 'baslangic.ps1'
    $startup = [Environment]::GetFolderPath('Startup')
    if ((Test-Path -LiteralPath $baslangicPs) -and (Test-Path -LiteralPath $vbs) -and (Test-Path -LiteralPath $startup)) {
        $yol = Join-Path $startup $script:CT_ACILIS_KISAYOL
        Set-CtKisayol -Yol $yol -Hedef $wscript `
            -Argumanlar ("//B //Nologo `"$vbs`" `"$baslangicPs`"") -CalismaDizini $UygulamaKok
        $olusan += $yol
        # Eski adli Startup kisayolu kalirsa acilis watchdog'u iki kez calisir
        Remove-CtEskiKisayol -Klasor $startup -Ad $script:CT_ESKI_ACILIS_KISAYOL
    }

    if ($MerkezPaneli) {
        $panelPs = Join-Path (Join-Path $UygulamaKok 'dagitik') 'merkez-panel.ps1'
        if ((Test-Path -LiteralPath $panelPs) -and (Test-Path -LiteralPath $masaustu)) {
            $yol = Join-Path $masaustu $script:CT_MERKEZ_KISAYOL
            Set-CtKisayol -Yol $yol -Hedef $psExe `
                -Argumanlar ("-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$panelPs`"") `
                -CalismaDizini $UygulamaKok -Ikon "$env:SystemRoot\System32\shell32.dll,44"
            $olusan += $yol
            Remove-CtEskiKisayol -Klasor $masaustu -Ad $script:CT_ESKI_MERKEZ_KISAYOL
        }
    }
    return $olusan
}

function Remove-CtKurulumKisayollari {
    param([switch]$MerkezDahil, [switch]$Deneme)
    $silinen = @()
    $masaustu = [Environment]::GetFolderPath('Desktop')
    $startup = [Environment]::GetFolderPath('Startup')
    $adaylar = @(
        (Join-Path $masaustu $script:CT_PANEL_KISAYOL),
        (Join-Path $startup $script:CT_ACILIS_KISAYOL),
        (Join-Path $masaustu $script:CT_ESKI_PANEL_KISAYOL),
        (Join-Path $startup $script:CT_ESKI_ACILIS_KISAYOL)
    )
    if ($MerkezDahil) { $adaylar += @((Join-Path $masaustu $script:CT_MERKEZ_KISAYOL), (Join-Path $masaustu $script:CT_ESKI_MERKEZ_KISAYOL)) }
    foreach ($yol in $adaylar) {
        if (Test-Path -LiteralPath $yol) {
            if (-not $Deneme) { Remove-Item -LiteralPath $yol -Force -ErrorAction SilentlyContinue }
            $silinen += $yol
        }
    }
    return $silinen
}

# ---------- Baslat menusu ve Windows "Uygulamalar" kaydi ----------
# Kurulumun resmi gorunmesi icin: Baslat menusunde kendi klasoru, Ayarlar >
# Uygulamalar listesinde kayit ve oradan calisan bir kaldirma komutu.
# Kayit HKCU altindadir; yonetici yetkisi gerekmez.

$script:CT_MENU_KLASORU = 'Aizen'
$script:CT_ESKI_MENU_KLASORU = 'Calisma Takip Sistemi'
$script:CT_KAYIT_YOLU = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\CalismaTakipSistemi'

function Get-CtBaslatMenusuKlasoru {
    param([switch]$Eski)
    $ad = $script:CT_MENU_KLASORU; if ($Eski) { $ad = $script:CT_ESKI_MENU_KLASORU }
    return (Join-Path ([Environment]::GetFolderPath('Programs')) $ad)
}

function New-CtBaslatMenusuKisayollari {
    param(
        [Parameter(Mandatory = $true)][string]$UygulamaKok,
        [switch]$MerkezPaneli
    )
    $klasor = Get-CtBaslatMenusuKlasoru
    [void][IO.Directory]::CreateDirectory($klasor)
    # Eski adli Baslat menusu klasoru yalnizca bu kurulumun kisayollarini tasir
    $eskiKlasor = Get-CtBaslatMenusuKlasoru -Eski
    if (Test-Path -LiteralPath $eskiKlasor -PathType Container) { Remove-Item -LiteralPath $eskiKlasor -Recurse -Force -ErrorAction SilentlyContinue }
    $hatirlatici = Join-Path $UygulamaKok 'hatirlatici'
    $dagitik = Join-Path $UygulamaKok 'dagitik'
    $psExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $olusan = @()

    $kontrolPs = Join-Path $hatirlatici 'kontrol.ps1'
    if (Test-Path -LiteralPath $kontrolPs) {
        $yol = Join-Path $klasor $script:CT_PANEL_KISAYOL
        Set-CtKisayol -Yol $yol -Hedef $psExe `
            -Argumanlar ("-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$kontrolPs`"") `
            -CalismaDizini $UygulamaKok -Ikon "$env:SystemRoot\System32\shell32.dll,16"
        $olusan += $yol
    }
    if ($MerkezPaneli) {
        $panelPs = Join-Path $dagitik 'merkez-panel.ps1'
        if (Test-Path -LiteralPath $panelPs) {
            $yol = Join-Path $klasor $script:CT_MERKEZ_KISAYOL
            Set-CtKisayol -Yol $yol -Hedef $psExe `
                -Argumanlar ("-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$panelPs`"") `
                -CalismaDizini $UygulamaKok -Ikon "$env:SystemRoot\System32\shell32.dll,44"
            $olusan += $yol
        }
    }
    $geriPs = Join-Path $hatirlatici 'yedek-geri-yukle.ps1'
    if (Test-Path -LiteralPath $geriPs) {
        $yol = Join-Path $klasor 'Yedekten geri yukle.lnk'
        $arguman = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $geriPs + '" -Arayuz'
        Set-CtKisayol -Yol $yol -Hedef $psExe -Argumanlar $arguman -CalismaDizini $UygulamaKok -Ikon "$env:SystemRoot\System32\shell32.dll,46"
        $olusan += $yol
    }
    $kaldirPs = Join-Path $dagitik 'kaldir.ps1'
    if (Test-Path -LiteralPath $kaldirPs) {
        # Kaldirma penceresi gorunur olmali: kullanici onay sorusunu gormeli
        $yol = Join-Path $klasor 'Kaldir.lnk'
        Set-CtKisayol -Yol $yol -Hedef $psExe `
            -Argumanlar ("-NoProfile -ExecutionPolicy Bypass -File `"$kaldirPs`"") `
            -CalismaDizini $UygulamaKok -Ikon "$env:SystemRoot\System32\shell32.dll,31" -PencereStili 1
        $olusan += $yol
    }
    return $olusan
}

function Register-CtUygulamaKaydi {
    param(
        [Parameter(Mandatory = $true)][string]$UygulamaKok,
        [string]$Surum = '1.0',
        [string]$Rol = '',
        [string]$KayitYolu = ''
    )
    if ([string]::IsNullOrWhiteSpace($KayitYolu)) { $KayitYolu = $script:CT_KAYIT_YOLU }
    if ([string]::IsNullOrWhiteSpace($Surum)) { $Surum = '1.0' }
    $psExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $kaldirPs = Join-Path (Join-Path $UygulamaKok 'dagitik') 'kaldir.ps1'
    $boyutKb = 0
    try {
        $toplam = (Get-ChildItem -LiteralPath $UygulamaKok -Recurse -File -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum).Sum
        if ($toplam -gt 0) { $boyutKb = [int]($toplam / 1KB) }
    }
    catch { }
    if (-not (Test-Path -LiteralPath $KayitYolu)) { [void](New-Item -Path $KayitYolu -Force) }
    $degerler = [ordered]@{
        DisplayName = 'Aizen'
        DisplayVersion = $Surum
        Publisher = 'Yerel kurulum'
        InstallLocation = $UygulamaKok
        DisplayIcon = "$env:SystemRoot\System32\shell32.dll,16"
        UninstallString = "`"$psExe`" -NoProfile -ExecutionPolicy Bypass -File `"$kaldirPs`""
        QuietUninstallString = "`"$psExe`" -NoProfile -ExecutionPolicy Bypass -File `"$kaldirPs`" -Onayla"
        Comments = "Rol: $Rol"
        NoModify = 1
        NoRepair = 1
        EstimatedSize = $boyutKb
    }
    foreach ($ad in $degerler.Keys) {
        $tur = 'String'
        if (@('NoModify', 'NoRepair', 'EstimatedSize') -contains $ad) { $tur = 'DWord' }
        [void](New-ItemProperty -Path $KayitYolu -Name $ad -Value $degerler[$ad] -PropertyType $tur -Force)
    }
    return $KayitYolu
}

function Unregister-CtUygulamaKaydi {
    param([string]$KayitYolu = '', [switch]$Deneme)
    if ([string]::IsNullOrWhiteSpace($KayitYolu)) { $KayitYolu = $script:CT_KAYIT_YOLU }
    if (-not (Test-Path -LiteralPath $KayitYolu)) { return $false }
    if (-not $Deneme) { Remove-Item -LiteralPath $KayitYolu -Recurse -Force -ErrorAction SilentlyContinue }
    return $true
}

function Remove-CtBaslatMenusu {
    param([switch]$Deneme)
    $bulundu = $false
    foreach ($klasor in @((Get-CtBaslatMenusuKlasoru), (Get-CtBaslatMenusuKlasoru -Eski))) {
        if (-not (Test-Path -LiteralPath $klasor)) { continue }
        $bulundu = $true
        if (-not $Deneme) { Remove-Item -LiteralPath $klasor -Recurse -Force -ErrorAction SilentlyContinue }
    }
    return $bulundu
}
