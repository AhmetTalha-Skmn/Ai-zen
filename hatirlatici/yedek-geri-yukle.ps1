# Veri geri yukleme: dogrulama -> eksiksiz guvenlik yedegi -> uygulama.
[CmdletBinding()]
param(
    [string]$Yedek,
    # Bos ise betigin ust klasoru. [CmdletBinding()] olan betikte $PSScriptRoot param
    # varsayilaninda bos gelir; Baslat menusu kisayolu bu parametreyi vermez.
    [string]$UygulamaKok,
    [switch]$Kontrol,
    [switch]$Onayla,
    [switch]$Arayuz
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Yedek-Ortak.ps1')
if ([string]::IsNullOrWhiteSpace($UygulamaKok)) { $UygulamaKok = Split-Path -Parent $PSScriptRoot }
$gecici = $null
$bakimAkimi = $null
$bakimYolu = $null
$h = $null
$izleyiciDurdu = $false
try {
    if ($Arayuz) {
        Add-Type -AssemblyName System.Windows.Forms
        if (-not $Yedek) {
            $secici = New-Object Windows.Forms.OpenFileDialog
            $secici.Filter = 'Aizen yedeği (*.zip)|*.zip'
            $secici.Title = 'Geri yüklenecek yedeği seç'
            try { if ($secici.ShowDialog() -ne 'OK') { exit 2 }; $Yedek = $secici.FileName } finally { $secici.Dispose() }
        }
    }
    if (-not $Yedek) { throw '-Yedek ile ZIP yolunu belirtin veya -Arayuz kullanın.' }
    $kok = Assert-CtNormalYol $UygulamaKok
    if ($kok.TrimEnd('\') -eq [IO.Path]::GetPathRoot($kok).TrimEnd('\')) { throw 'Sürücü köküne geri yüklenemez.' }
    $h = Join-Path $kok 'hatirlatici'
    if (-not (Test-Path -LiteralPath $h -PathType Container)) { throw 'Hedefte hatirlatici klasörü yok.' }
    $Yedek = Assert-CtNormalYol $Yedek
    $bilgi = Test-CtVeriYedegi $Yedek
    if ($bilgi.dosyaSayisi -eq 0) { throw 'Yedekte geri yüklenecek veri yok.' }
    if ($Kontrol) {
        [ordered]@{ tamam=$true; dosyaSayisi=$bilgi.dosyaSayisi; bayt=$bilgi.bayt; manifestli=$bilgi.manifestli; hedef=$kok } | ConvertTo-Json -Depth 4
        exit 0
    }
    if ($Arayuz -and -not $Onayla) {
        $mesaj = "$($bilgi.dosyaSayisi) dosya doğrulandı. Hedef: $kok" + [Environment]::NewLine +
            'Önce mevcut verinin güvenlik yedeği alınacak. Yedekteki dosyalar mevcut dosyaların üzerine yazılacak; diğer dosyalar korunacak.' +
            [Environment]::NewLine + 'Açık takip pencerelerini kapatın; arka plan izleyicisi işlem boyunca durdurulur. Geri yükleme başlasın mı?'
        $Onayla = [Windows.Forms.MessageBox]::Show($mesaj,'Yedekten geri yükle','YesNo','Warning') -eq 'Yes'
    }
    if (-not $Onayla) { throw 'Doğrulama için -Kontrol, geri yüklemeyi uygulamak için -Onayla kullanın.' }

    # Bakim isareti acik tutuldugu surece takip, izleyici, acilis, rapor ve gonderici
    # yeni tur baslatmaz. Yarida kalmis bir geri yuklemenin isaretini hicbir surec
    # tutmaz (surec olunce isletim sistemi kapatir); oyle bir isaret silinir.
    $bakimYolu = Join-Path $h 'GERI-YUKLEME'
    if (Test-Path -LiteralPath $bakimYolu) {
        try { [IO.File]::Open($bakimYolu, 'Open', 'ReadWrite', 'None').Dispose(); [IO.File]::Delete($bakimYolu) }
        catch { throw 'Başka bir geri yükleme sürüyor; veri değiştirilmedi.' }
    }
    $bakimAkimi = [IO.File]::Open($bakimYolu,[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::Read)

    # Izleyici surekli calisir: durdurulur, is bitince yeniden baslatilir. Kisa turlar
    # kendiliginden biter, beklenir. Acik pencereler (panel, rapor, MCP) veri yazabilir;
    # onlari kullanici kapatir. Merkez sunucusu gibi hatirlatici verisine yazmayanlar engel degil.
    $kisaTurlar = @('takip.ps1', 'gunluk-rapor.ps1', 'baslangic.ps1', 'istemci-gonderici.ps1', 'yedek-al.ps1')
    $hOnEki = $h.TrimEnd('\') + '\'
    $gondericiYolu = Join-Path $kok 'dagitik\istemci-gonderici.ps1'
    $sonBekleme = (Get-Date).AddSeconds(60)
    while ($true) {
        $surecler = @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
            $_.ProcessId -ne $PID -and $_.Name -match '^(powershell|pwsh|wscript)\.exe$' -and $_.CommandLine -and
            $_.CommandLine -notmatch 'yedek-geri-yukle\.ps1' -and
            ($_.CommandLine.IndexOf($hOnEki, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or
             $_.CommandLine.IndexOf($gondericiYolu, [StringComparison]::OrdinalIgnoreCase) -ge 0)
        })
        if ($surecler.Count -eq 0) { break }
        $engel = @()
        foreach ($s in $surecler) {
            $betikler = [regex]::Matches($s.CommandLine, '[^\\/"\s]+\.ps1')
            $betik = $(if ($betikler.Count -gt 0) { $betikler[$betikler.Count - 1].Value.ToLowerInvariant() } else { [string]$s.Name })
            if ($betik -eq 'izleyici.ps1') { Stop-Process -Id $s.ProcessId -Force -ErrorAction SilentlyContinue; $izleyiciDurdu = $true }
            elseif ($kisaTurlar -notcontains $betik) { $engel += $betik }
        }
        if ($engel.Count -gt 0) { throw ('Açık takip penceresi var (' + ((@($engel) | Sort-Object -Unique) -join ', ') + '). Kapatıp yeniden deneyin; veri değiştirilmedi.') }
        if ((Get-Date) -gt $sonBekleme) { throw 'Arka plan turu bitmedi; biraz sonra yeniden deneyin. Veri değiştirilmedi.' }
        Start-Sleep -Milliseconds 500
    }
    $gecici = Join-Path $env:TEMP ('ct-geri-' + [guid]::NewGuid().ToString('N').Substring(0,8))
    [void][IO.Directory]::CreateDirectory($gecici)
    # Kaynagin dogrulama ve uygulama arasinda degismesini onle.
    $kopya = Join-Path $gecici 'kaynak.zip'
    Copy-Item -LiteralPath $Yedek -Destination $kopya
    $sahne = Join-Path $gecici 'veri'
    [void][IO.Directory]::CreateDirectory($sahne)
    $bilgi = Test-CtVeriYedegi $kopya $sahne
    $plan = @()
    foreach ($d in $bilgi.dosyalar) {
        $hedef = Assert-CtNormalYol (Get-CtYedekHedefi $kok $d.yol)
        if (Test-Path -LiteralPath $hedef -PathType Container) { throw 'Dosya hedefinde klasör var; veri değiştirilmedi.' }
        $plan += [pscustomobject]@{ ad=$d.yol; hedef=$hedef; var=(Test-Path -LiteralPath $hedef -PathType Leaf) }
    }
    $guvenlik = Join-Path $kok ('geri-yukleme-yedekleri\' + (Get-Date).ToString('yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,6))
    [void](Assert-CtNormalYol $guvenlik)
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'yedek-al.ps1') -KaynakKok $kok -Hedef $guvenlik -Eksiksiz -Sessiz
    if ($LASTEXITCODE -ne 0) { throw 'Güvenlik yedeği alınamadı; veri değiştirilmedi.' }
    $guvenlikZip = @(Get-ChildItem -LiteralPath $guvenlik -Filter '*.zip' -File)
    if ($guvenlikZip.Count -ne 1) { throw 'Güvenlik yedeği bulunamadı; veri değiştirilmedi.' }
    $eskiSahne = Join-Path $gecici 'eski'
    [void][IO.Directory]::CreateDirectory($eskiSahne)
    [void](Test-CtVeriYedegi $guvenlikZip[0].FullName $eskiSahne)
    $yazilan = New-Object System.Collections.Generic.List[object]
    try {
        foreach ($d in $plan) {
            [void][IO.Directory]::CreateDirectory((Split-Path -Parent $d.hedef))
            $yazilan.Add($d)
            Copy-Item -LiteralPath (Join-Path $sahne $d.ad) -Destination $d.hedef -Force
        }
    }
    catch {
        $ilkHata = $_
        $geriHata = 0
        foreach ($d in $yazilan) {
            try {
                if ($d.var) { Copy-Item -LiteralPath (Join-Path $eskiSahne $d.ad) -Destination $d.hedef -Force }
                else { [IO.File]::Delete($d.hedef) }
            } catch { $geriHata++ }
        }
        if ($geriHata -gt 0) { throw "Geri alma $geriHata dosyada tamamlanamadı. Güvenlik yedeği: $($guvenlikZip[0].FullName)" }
        throw "Geri yükleme uygulanamadı; yazılan dosyalar geri alındı. Güvenlik yedeği: $($guvenlikZip[0].FullName). $($ilkHata.Exception.GetType().Name)"
    }
    $sonuc = [ordered]@{ tamam=$true; dosyaSayisi=$plan.Count; guvenlikYedegi=$guvenlikZip[0].FullName; hedef=$kok }
    $sonuc | ConvertTo-Json -Depth 4
    if ($Arayuz) { [void][Windows.Forms.MessageBox]::Show("Geri yükleme tamamlandı. Güvenlik yedeği: $($guvenlikZip[0].FullName)",'Tamamlandı') }
}
catch {
    if ($Arayuz) { [void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'Geri yüklenemedi','OK','Error') }
    Write-Error $_.Exception.Message -ErrorAction Continue
    exit 1
}
finally {
    if ($null -ne $bakimAkimi) {
        $bakimAkimi.Dispose()
        # Tam bu anda bir arka plan betigi isareti acmis olabilir; o zaman onu o siler.
        try { [IO.File]::Delete($bakimYolu) } catch { }
    }
    if ($izleyiciDurdu) {
        $vbs = Join-Path $h 'gizli.vbs'
        $izPs = Join-Path $h 'izleyici.ps1'
        if ((Test-Path -LiteralPath $vbs) -and (Test-Path -LiteralPath $izPs)) {
            Start-Process -FilePath "$env:SystemRoot\System32\wscript.exe" -ArgumentList "//B //Nologo `"$vbs`" `"$izPs`"" -WindowStyle Hidden
        }
    }
    if ($gecici) {
        $tempKok = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') + '\'
        if ([IO.Path]::GetFullPath($gecici).StartsWith($tempKok,[StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $gecici -Recurse -Force }
    }
}