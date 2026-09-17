# test-dagitik.ps1 tarafindan ayni sayaclarla calistirilir; bagimsiz calistirildiginda bagimliliklari yukler.
$script:bagimsizGelistirme = $false
if (-not (Get-Command 'Test-Esit' -ErrorAction SilentlyContinue)) {
    $script:bagimsizGelistirme = $true
    $script:gecen = 0; $script:kalan = 0
    function Test-Esit { param([string]$Ad, [object]$Beklenen, [object]$Gercek) if ($Beklenen -ceq $Gercek) { $script:gecen++; Write-Output "  OK  $Ad" } else { $script:kalan++; Write-Output "  HATA  $Ad | beklenen=[$Beklenen] gercek=[$Gercek]" } }
    function Test-Dogru { param([string]$Ad, [bool]$Kosul) if ($Kosul) { $script:gecen++; Write-Output "  OK  $Ad" } else { $script:kalan++; Write-Output "  HATA  $Ad" } }
    function Remove-TestKlasoru { param([string]$Yol) $temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'; $tam = [IO.Path]::GetFullPath($Yol); if ($tam.StartsWith($temp, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $tam)) { Remove-Item -LiteralPath $tam -Recurse -Force } }
}
if (-not (Get-Command 'Read-DagitikJson' -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'Ortak.ps1')
}
if (-not (Get-Command 'Get-MerkezPanelToplami' -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'Merkez-Ozet.ps1')
}
. (Join-Path $PSScriptRoot 'Merkez-Kural.ps1')
. (Join-Path $PSScriptRoot '..\hatirlatici\kural-senkron.ps1')
function Invoke-GelBetik {
    # Beklenen hatalar stderr'e yazar; EAP Stop iken cagiran testi dusurmesin
    param([object[]]$Arguman)
    $eskiEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $cikti = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File @Arguman 2>$null)
        return [pscustomobject]@{ Kod = $LASTEXITCODE; Metin = ($cikti -join [Environment]::NewLine) }
    }
    finally { $ErrorActionPreference = $eskiEap }
}
$gelKok =Join-Path $env:TEMP ('ct-gel-' + [guid]::NewGuid().ToString('N').Substring(0,8))
try {
    [void][IO.Directory]::CreateDirectory($gelKok)
    $ky = Join-Path $gelKok 'merkez-kurallar.json'
    Save-MerkezKuralKarari $ky 'editor-test' 'surec' 'calisma'
    Save-MerkezKuralKarari $ky 'oyun-test' 'surec' 'yasakli'
    Test-Esit 'Panel kural ekler' 2 @(Get-MerkezKuralSatirlari (Get-MerkezKurallari $ky)).Count
    Save-MerkezKuralKarari $ky 'editor-test' 'surec' 'yasakli'
    Test-Esit 'Panel karar degistirir' 0 @((Get-MerkezKurallari $ky).calisma.surec).Count
    $yerel = Join-Path $gelKok 'hatirlatici'
    [void][IO.Directory]::CreateDirectory($yerel)
    Copy-Item (Join-Path $PSScriptRoot '..\hatirlatici\kurallar.varsayilan.json') (Join-Path $yerel 'kurallar.json')
    [void](Merge-YerelKurallar $yerel (Get-MerkezKurallari $ky))
    Save-MerkezKuralKarari $ky 'oyun-test' 'surec' 'yasakli' -Sil
    [void](Merge-YerelKurallar $yerel (Get-MerkezKurallari $ky))
    $yerelK = Read-DagitikJson (Join-Path $yerel 'kurallar.json')
    Test-Dogru 'Merkezden silinen kural cihazdan kalkar' ($yerelK.yasakli.surec -notcontains 'oyun-test')
    Test-Dogru 'Diger karar korunur' ($yerelK.yasakli.surec -contains 'editor-test')
    Test-Dogru 'Guvenlik istisnalari korunur' ($yerelK.aslaEngelleme -contains 'explorer')
    Save-MerkezKuralKarari $ky 'oyun-test' 'surec' 'calisma'
    Test-Esit 'Yeniden ekleme silme kaydini kaldirir' 0 @((Get-MerkezKurallari $ky).silinenKurallar).Count
    $ay = Join-Path $gelKok 'merkez-ayarlari.json'
    Write-DagitikJsonAtomik -Yol $ay -Nesne ([ordered]@{cihazlar=@([ordered]@{id='test-pc';ad='Test PC';aktif=$true;anahtarKorunmus='TEST-SECRET';onayUtc='2026-09-12T01:00:00Z'})})
    Set-MerkezCihazAyari $ay 'test-pc' $false $true 300
    $a = Read-DagitikJson $ay
    Test-Esit 'Panel cihazi pasif yapar' $false $a.cihazlar[0].aktif
    Test-Esit 'Panel yazma yetkisi verir' $true $a.cihazlar[0].kuralYazabilir
    Test-Esit 'Panel hedefi kaydeder' 300 $a.cihazlar[0].hedefDk
    Test-Esit 'Panel anahtari korur' 'TEST-SECRET' $a.cihazlar[0].anahtarKorunmus
    $panelJson = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'merkez-panel.ps1') -Kontrol -VeriYolu (Join-Path $gelKok 'veri') -AyarDosyasi $ay) -join [Environment]::NewLine
    Test-Esit 'Yeni panel kontrol cikisi' 0 $LASTEXITCODE
    $panel = ConvertFrom-Json $panelJson
    Test-Esit 'Panel kontrol kurallari gosterir' 2 @($panel.kurallar).Count
    Test-Esit 'Panel kontrol pasif cihazi gosterir' $false $panel.cihazlar[0].aktif
    Test-Dogru 'Panel kontrol anahtar sizdirmaz' (-not $panelJson.Contains('TEST-SECRET'))

    $veri = Join-Path $gelKok 'veri'
    $bugun = (Get-Date).ToString('yyyy-MM-dd')
    foreach ($ci in @(@('test-pc',100,$bugun),@('ikinci-pc',65,$bugun),@('eski-pc',500,'2020-01-01'))) {
        Write-DagitikJsonAtomik -Yol (Join-Path $veri "guncel\$($ci[0]).json") -Nesne ([ordered]@{cihazId=$ci[0];clientTarih=$ci[2];ozet=@{calismaDk=$ci[1]}})
    }
    $top = Get-MerkezPanelToplami $a $veri
    Test-Esit 'Ortak toplam eski gunu saymaz' 165 $top.toplamDk
    Test-Esit 'Ortak hedef cihaz hedeflerini toplamaz' 240 $top.hedefDk
    Test-Esit 'Ortak kalan sure' 75 $top.kalanDk
    Test-Esit 'Ortak cihaz katkilari' 2 @($top.cihazlar).Count
    Test-Esit 'Eksik gun toplami sifir' 0 (Get-MerkezPanelToplami $a $veri '2020-01-02').toplamDk

    . (Join-Path $PSScriptRoot 'Senkron-Durum.ps1')
    Write-DagitikJsonAtomik -Yol (Join-Path $yerel 'merkez.json') -Nesne ([ordered]@{aktif=$true;anahtarKorunmus='TEST-SECRET';sonBasariliSenkronUtc='2026-09-12T01:00:00Z';kuralAlimHata='HTTP 403'})
    [void](Add-KuralKuyruk $yerel 'bekleyen-test' 'surec' 'calisma')
    $sn = Get-CtSenkronDurumu $yerel
    Test-Esit 'Senkron bekleyen karar sayisi' 1 $sn.bekleyenKarar
    Test-Esit 'Senkron son basarili gonderim' '2026-09-12T01:00:00Z' $sn.sonBasariliGonderimUtc
    Test-Esit 'Senkron hata gorunur' 'HTTP 403' $sn.hata
    Test-Dogru 'Senkron anahtar sizdirmaz' (-not (($sn | ConvertTo-Json -Depth 5).Contains('TEST-SECRET')))

    . (Join-Path $PSScriptRoot '..\hatirlatici\Yedek-Ortak.ps1')
    $kaynak = Join-Path $gelKok 'kaynak'
    $hedef = Join-Path $gelKok 'hedef'
    foreach ($kok in @($kaynak,$hedef)) { [void][IO.Directory]::CreateDirectory((Join-Path $kok 'hatirlatici')) }
    [void][IO.Directory]::CreateDirectory((Join-Path $kaynak 'Gunluk'))
    [IO.File]::WriteAllText((Join-Path $kaynak 'hatirlatici\durum.json'),'{"dakika":123}')
    [IO.File]::WriteAllText((Join-Path $kaynak 'Gunluk\not.md'),'not-123')
    [IO.File]::WriteAllText((Join-Path $hedef 'hatirlatici\durum.json'),'{"dakika":9}')
    [IO.File]::WriteAllText((Join-Path $hedef 'hatirlatici\merkez.json'),'{"koru":true}')
    $yedekKok = Join-Path $gelKok 'yedek'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot '..\hatirlatici\yedek-al.ps1') -KaynakKok $kaynak -Hedef $yedekKok -Eksiksiz -Sessiz
    Test-Esit 'Yeni yedek uretimi' 0 $LASTEXITCODE
    $zip = @(Get-ChildItem -LiteralPath $yedekKok -Filter '*.zip')[0].FullName
    $b = Test-CtVeriYedegi $zip
    Test-Dogru 'Yedek manifesti dogrulandi' $b.manifestli
    Test-Esit 'Yedek dosya sayisi' 2 $b.dosyaSayisi
    $geri = Join-Path $PSScriptRoot '..\hatirlatici\yedek-geri-yukle.ps1'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $geri -Yedek $zip -UygulamaKok $hedef -Kontrol | Out-Null
    Test-Esit 'Geri yukleme kontrol cikisi' 0 $LASTEXITCODE
    Test-Esit 'Kontrol veri degistirmez' '{"dakika":9}' ([IO.File]::ReadAllText((Join-Path $hedef 'hatirlatici\durum.json')))
    $geriMetin = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $geri -Yedek $zip -UygulamaKok $hedef -Onayla) -join [Environment]::NewLine
    Test-Esit 'Geri yukleme cikisi' 0 $LASTEXITCODE
    $geriSonuc = ConvertFrom-Json $geriMetin
    Test-Esit 'Sayac geri yuklendi' '{"dakika":123}' ([IO.File]::ReadAllText((Join-Path $hedef 'hatirlatici\durum.json')))
    Test-Esit 'Gunluk dogru koke yuklendi' 'not-123' ([IO.File]::ReadAllText((Join-Path $hedef 'Gunluk\not.md')))
    Test-Esit 'Merkez baglantisi korundu' '{"koru":true}' ([IO.File]::ReadAllText((Join-Path $hedef 'hatirlatici\merkez.json')))
    $eski = Join-Path $gelKok 'guvenlik-acik'
    Expand-Archive -LiteralPath $geriSonuc.guvenlikYedegi -DestinationPath $eski
    Test-Esit 'Guvenlik yedeginde onceki sayac var' '{"dakika":9}' ([IO.File]::ReadAllText((Join-Path $eski 'durum.json')))
    Test-Dogru 'Bakim isareti temizlendi' (-not (Test-Path (Join-Path $hedef 'hatirlatici\GERI-YUKLEME')))

    # Baslat menusu kisayolu -UygulamaKok vermez: kok betigin ust klasorunden bulunmali
    $kisayolKok = Join-Path $gelKok 'kisayol'
    [void][IO.Directory]::CreateDirectory((Join-Path $kisayolKok 'hatirlatici'))
    foreach ($ad in 'yedek-geri-yukle.ps1', 'Yedek-Ortak.ps1', 'yedek-al.ps1') {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot "..\hatirlatici\$ad") -Destination (Join-Path $kisayolKok 'hatirlatici')
    }
    $r = Invoke-GelBetik @((Join-Path $kisayolKok 'hatirlatici\yedek-geri-yukle.ps1'), '-Yedek', $zip, '-Kontrol')
    Test-Esit 'Kisayol bicimi (UygulamaKok yok) calisir' 0 $r.Kod
    $kisayolHedef = ''
    try { $kisayolHedef = [string](ConvertFrom-Json $r.Metin).hedef } catch { }
    Test-Esit 'Varsayilan kok betigin ust klasoru' ([IO.Path]::GetFullPath($kisayolKok)) $kisayolHedef

    # Yarida kalmis geri yuklemenin isaretini hicbir surec tutmaz: engel olmamali
    $isaretYolu = Join-Path $hedef 'hatirlatici\GERI-YUKLEME'
    [IO.File]::WriteAllText($isaretYolu, '')
    $r = Invoke-GelBetik @($geri, '-Yedek', $zip, '-UygulamaKok', $hedef, '-Onayla')
    Test-Esit 'Kalmis bakim isareti geri yuklemeyi engellemez' 0 $r.Kod
    Test-Dogru 'Kalmis bakim isareti temizlendi' (-not (Test-Path -LiteralPath $isaretYolu))

    # Suren bir geri yukleme (isaret acik tutuluyor) varken ikincisi veri yazmamali
    [IO.File]::WriteAllText((Join-Path $hedef 'hatirlatici\durum.json'), '{"dakika":7}')
    $tutulan = [IO.File]::Open($isaretYolu, 'CreateNew', 'ReadWrite', 'Read')
    try {
        $r = Invoke-GelBetik @($geri, '-Yedek', $zip, '-UygulamaKok', $hedef, '-Onayla')
        Test-Esit 'Suren geri yukleme varken ikincisi reddedilir' 1 $r.Kod
        Test-Esit 'Reddedilen ikinci geri yukleme veri degistirmez' '{"dakika":7}' ([IO.File]::ReadAllText((Join-Path $hedef 'hatirlatici\durum.json')))
        Test-Dogru 'Reddedilen ikinci geri yukleme baskasinin isaretine dokunmaz' (Test-Path -LiteralPath $isaretYolu)
    }
    finally { $tutulan.Dispose(); [IO.File]::Delete($isaretYolu) }

    # Canli makinede izleyici hep acik: geri yukleme onu durdurup islemi tamamlamali
    $sahteIzleyici = Join-Path $hedef 'hatirlatici\izleyici.ps1'
    [IO.File]::WriteAllText($sahteIzleyici, 'Start-Sleep -Seconds 120')
    $izSurec = Start-Process -FilePath powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$sahteIzleyici`"") -WindowStyle Hidden -PassThru
    try {
        $r = Invoke-GelBetik @($geri, '-Yedek', $zip, '-UygulamaKok', $hedef, '-Onayla')
        Test-Esit 'Izleyici acikken geri yukleme tamamlanir' 0 $r.Kod
        Test-Esit 'Izleyici acikken sayac geri yuklendi' '{"dakika":123}' ([IO.File]::ReadAllText((Join-Path $hedef 'hatirlatici\durum.json')))
        Test-Dogru 'Geri yukleme izleyiciyi durdurdu' ($izSurec.WaitForExit(5000))
    }
    finally { if (-not $izSurec.HasExited) { $izSurec.Kill() } }

    # Acik bir takip penceresi veri yazabilir: kullanici kapatana kadar reddedilmeli
    $sahtePanel = Join-Path $hedef 'hatirlatici\kontrol.ps1'
    [IO.File]::WriteAllText($sahtePanel, 'Start-Sleep -Seconds 120')
    [IO.File]::WriteAllText((Join-Path $hedef 'hatirlatici\durum.json'), '{"dakika":7}')
    $panelSurec = Start-Process -FilePath powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$sahtePanel`"") -WindowStyle Hidden -PassThru
    try {
        $r = Invoke-GelBetik @($geri, '-Yedek', $zip, '-UygulamaKok', $hedef, '-Onayla')
        Test-Esit 'Acik takip penceresi varken reddedilir' 1 $r.Kod
        Test-Esit 'Pencere yuzunden reddedilen geri yukleme veri degistirmez' '{"dakika":7}' ([IO.File]::ReadAllText((Join-Path $hedef 'hatirlatici\durum.json')))
        Test-Dogru 'Reddedilen geri yukleme isaret birakmaz (exit sonrasi finally)' (-not (Test-Path -LiteralPath $isaretYolu))
        Test-Dogru 'Reddedilen geri yukleme pencereyi kapatmaz' (-not $panelSurec.HasExited)
    }
    finally { if (-not $panelSurec.HasExited) { $panelSurec.Kill() } }

    # Arka plan betiklerinin bakim bekcisi: ayni satir her yerde ve davranisi dogru
    $bekciSatiri = @(Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\hatirlatici\izleyici.ps1') -TotalCount 1 -Encoding UTF8)[0]
    Test-Dogru 'Bekci satiri isareti tutan sureci ayirt eder' ($bekciSatiri.Contains("'None'") -and $bekciSatiri.Contains('GERI-YUKLEME'))
    foreach ($ad in 'takip.ps1', 'baslangic.ps1', 'gunluk-rapor.ps1') {
        Test-Dogru "Bekci satiri ayni: $ad" (@(Get-Content -LiteralPath (Join-Path $PSScriptRoot "..\hatirlatici\$ad") -Encoding UTF8) -contains $bekciSatiri)
    }
    Test-Dogru 'Bekci satiri ayni: istemci-gonderici.ps1' (@(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'istemci-gonderici.ps1') -Encoding UTF8) -contains $bekciSatiri.Replace('$PSScriptRoot', '$HatirlaticiKlasoru'))
    $bekciKlasoru = Join-Path $gelKok 'bekci'
    [void][IO.Directory]::CreateDirectory($bekciKlasoru)
    $bekci = Join-Path $bekciKlasoru 'bekci.ps1'
    [IO.File]::WriteAllText($bekci, ($bekciSatiri + "`r`n'devam'"), (New-Object Text.UTF8Encoding($true)))
    $bekciIsareti = Join-Path $bekciKlasoru 'GERI-YUKLEME'
    Test-Esit 'Bekci: isaret yokken tur calisir' 'devam' (Invoke-GelBetik @($bekci)).Metin
    [IO.File]::WriteAllText($bekciIsareti, '')
    Test-Esit 'Bekci: kalmis isarette tur calisir' 'devam' (Invoke-GelBetik @($bekci)).Metin
    Test-Dogru 'Bekci: kalmis isareti siler' (-not (Test-Path -LiteralPath $bekciIsareti))
    $tutulan = [IO.File]::Open($bekciIsareti, 'CreateNew', 'ReadWrite', 'Read')
    try {
        $r = Invoke-GelBetik @($bekci)
        Test-Esit 'Bekci: suren geri yuklemede tur calismaz' '' $r.Metin
        Test-Esit 'Bekci: suren geri yuklemede cikis 0' 0 $r.Kod
        Test-Dogru 'Bekci: suren isarete dokunmaz' (Test-Path -LiteralPath $bekciIsareti)
    }
    finally { $tutulan.Dispose(); [IO.File]::Delete($bekciIsareti) }
    $bozuk = Join-Path $gelKok 'bozuk.zip'
    $za = [IO.Compression.ZipFile]::Open($bozuk,[IO.Compression.ZipArchiveMode]::Create)
    try { $g = $za.CreateEntry('../disari.json'); $w = New-Object IO.StreamWriter($g.Open()); try {$w.Write('{}')} finally {$w.Dispose()} } finally {$za.Dispose()}
    $reddedildi = $false
    try { [void](Test-CtVeriYedegi $bozuk) } catch { $reddedildi = $true }
    Test-Dogru 'Zip yol tasmasi reddedildi' $reddedildi
    $degisik = Join-Path $gelKok 'degisik.zip'
    Copy-Item $zip $degisik
    $za = [IO.Compression.ZipFile]::Open($degisik,[IO.Compression.ZipArchiveMode]::Update)
    try { $za.GetEntry('durum.json').Delete(); $g=$za.CreateEntry('durum.json'); $w=New-Object IO.StreamWriter($g.Open());try{$w.Write('{"dakika":999}')}finally{$w.Dispose()} } finally {$za.Dispose()}
    $reddedildi = $false
    try { [void](Test-CtVeriYedegi $degisik) } catch { $reddedildi = $true }
    Test-Dogru 'Degistirilmis yedek hash kontrolunde reddedildi' $reddedildi
}
catch { $script:kalan++; Write-Output "  HATA  Gelistirme: $($_.Exception.Message) [$($_.InvocationInfo.ScriptLineNumber)]" }
finally {
    Remove-TestKlasoru $gelKok
    if ($script:bagimsizGelistirme) {
        Write-Output "Sonuc: $script:gecen basarili, $script:kalan hatali"
        if ($script:kalan -gt 0) { exit 1 } else { exit 0 }
    }
}
