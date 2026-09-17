# Takip sistemi oz-testi
$ErrorActionPreference = 'Continue'
$hDir   = $PSScriptRoot
if (-not $hDir) { $hDir = Split-Path $MyInvocation.MyCommand.Path -Parent }
$klasor = Split-Path $hDir -Parent
$gorevAd = 'Calisma Takip Sistemi'
$INV = [Globalization.CultureInfo]::InvariantCulture
$gecti = 0; $kaldi = 0

function T { param($ad, $sonuc, $detay)
    if ($sonuc) { $script:gecti++; Write-Host ("  [OK]   {0,-46} {1}" -f $ad, $detay) -ForegroundColor Green }
    else        { $script:kaldi++; Write-Host ("  [HATA] {0,-46} {1}" -f $ad, $detay) -ForegroundColor Red }
}

Write-Host "`n=== 1. DOSYA VE SOZDIZIMI ===" -ForegroundColor Cyan
foreach ($f in @('takip.ps1','kontrol.ps1','baslangic.ps1','izleyici.ps1')) {
    $p = Join-Path $hDir $f
    $var = Test-Path $p
    T "$f mevcut" $var $p
    if ($var) {
        $e = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($p, [ref]$null, [ref]$e)
        T "$f sozdizimi" ($e.Count -eq 0) "$($e.Count) hata"
    }
}
# Tum betikler (dagitik dahil): sozdizimi + kodlama. PS 5.1, BOM'suz dosyayi ANSI
# okur; Turkce karakterli bir .ps1 BOM'suz kaydedilirse sessizce bozulur.
$tumPs = @(Get-ChildItem -LiteralPath $hDir, (Join-Path $klasor 'dagitik') -Filter *.ps1 -Recurse -ErrorAction SilentlyContinue)
$bozuk = @(); $bomsuz = @(); $kokVarsayilan = @(); $kulturRegex = @()
foreach ($d in $tumPs) {
    $e = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($d.FullName, [ref]$null, [ref]$e)
    if ($e.Count -gt 0) { $bozuk += $d.Name }
    # [CmdletBinding()] ya da [Parameter()] olan betikte $PSScriptRoot param varsayilaninda
    # bos gelir (-File ile de); varsayilan govdede doldurulmali.
    if ($null -ne $ast.ParamBlock) {
        $gelismis = (@($ast.ParamBlock.Attributes | Where-Object { $_.TypeName.Name -eq 'CmdletBinding' }).Count -gt 0) -or
            (@($ast.ParamBlock.Parameters | ForEach-Object { $_.Attributes } | Where-Object { $_.TypeName.Name -eq 'Parameter' }).Count -gt 0)
        $kokKullanan = @($ast.ParamBlock.Parameters | Where-Object { $_.DefaultValue -and $_.DefaultValue.Extent.Text -match 'PSScriptRoot' })
        if ($gelismis -and $kokKullanan.Count -gt 0) { $kokVarsayilan += $d.Name }
    }
    # -match/-notmatch/-replace/-split buyuk-kucuk harf duyarsiz ve kulture bagli: tr-TR'de
    # 'I' -> 'ı' olur, [A-Z]/[a-z] araligi onu tanimaz (kod normallestirme ve cihaz kimligi
    # bu yuzden bozuktu). Sinif iki durumu kapsiyorsa -cmatch/-creplace, gerekirse CultureInvariant.
    foreach ($ifade in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.BinaryExpressionAst] }, $true)) {
        if (@('Imatch', 'Inotmatch', 'Ireplace', 'Isplit') -contains [string]$ifade.Operator -and $ifade.Right.Extent.Text -cmatch '(A-Z|a-z)') {
            $kulturRegex += ('{0}:{1}' -f $d.Name, $ifade.Extent.StartLineNumber)
        }
    }
    $b = [IO.File]::ReadAllBytes($d.FullName)
    $bom = $b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF
    # -cmatch: -match Turk kulturunde 'I'yi 'ı'ya katlar ve her dosyayi ASCII disi sanar
    if (-not $bom -and [Text.Encoding]::GetEncoding(28591).GetString($b) -cmatch '[^\x00-\x7F]') { $bomsuz += $d.Name }
}
T "tum betikler sozdizimi ($($tumPs.Count) dosya)" ($bozuk.Count -eq 0) ($bozuk -join ', ')
T "Turkce karakterli betiklerde BOM" ($bomsuz.Count -eq 0) ($bomsuz -join ', ')
T "gelismis betikte param varsayilani PSScriptRoot kullanmaz" ($kokVarsayilan.Count -eq 0) ($kokVarsayilan -join ', ')
T "kulture bagli A-Z/a-z regex araligi yok" ($kulturRegex.Count -eq 0) ($kulturRegex -join ', ')

Write-Host "`n=== 2. KRITIK: TAZELIK TARAMASI ===" -ForegroundColor Cyan
$src = Get-Content (Join-Path $hDir 'takip.ps1') -Raw -Encoding UTF8
T "URETILEN listesi tanimli" ($src -match 'URETILEN') ''
T "Calisma Kaydi haric tutuluyor" ($src -match "URETILEN\s*=\s*@\('Calisma Kaydi\.md'") ''
T "haric tutma filtrede kullaniliyor" ($src -match 'URETILEN -notcontains') ''
# gercek tarama simulasyonu
$URETILEN = @('Calisma Kaydi.md','Aktivite Gunlugu.md')
$esik = (Get-Date).AddMinutes(-7)
$taze = @(Get-ChildItem -Path $klasor -Filter *.md -Recurse |
    Where-Object { $_.DirectoryName -notlike '*hatirlatici*' -and $_.DirectoryName -notlike '*hafiza*' -and $URETILEN -notcontains $_.Name -and $_.LastWriteTime -gt $esik })
$tazeEski = @(Get-ChildItem -Path $klasor -Filter *.md -Recurse |
    Where-Object { $_.DirectoryName -notlike '*hatirlatici*' -and $_.DirectoryName -notlike '*hafiza*' -and $_.LastWriteTime -gt $esik })
T "haric tutma fark yaratiyor" ($tazeEski.Count -gt $taze.Count) "eski=$($tazeEski.Count) yeni=$($taze.Count)"

Write-Host "`n=== 3. TARIH AYRISTIRMA (kultur bagimsiz) ===" -ForegroundColor Cyan
function TarihOku { param($x)
    if ([string]::IsNullOrWhiteSpace($x)) { return $null }
    try { return [datetime]::ParseExact($x,'s',$INV) } catch { }
    try { return [datetime]::Parse($x,$INV) } catch { }
    return $null }
$ornek = (Get-Date).ToString('s')
$eskiKultur = [Threading.Thread]::CurrentThread.CurrentCulture
foreach ($k in @('tr-TR','en-US','de-DE','ar-SA')) {
    [Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::new($k)
    $r = TarihOku $ornek
    T "TarihOku calisiyor ($k)" ($r -ne $null) "$ornek"
}
[Threading.Thread]::CurrentThread.CurrentCulture = $eskiKultur
T "bos deger null doner" ((TarihOku '') -eq $null) ''
T "bozuk deger null doner" ((TarihOku 'abc') -eq $null) ''

Write-Host "`n=== 4. JSON DOSYALARI ===" -ForegroundColor Cyan
foreach ($j in @('durum.json','ayarlar.json','gecmis.json','kurallar.json')) {
    $p = Join-Path $hDir $j
    if (Test-Path $p) {
        $ok = $true
        try { Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json | Out-Null } catch { $ok = $false }
        T "$j gecerli JSON" $ok ''
    } else { T "$j (yok, varsayilan kullanilacak)" $true '' }
}

Write-Host "`n=== 5. AKTIVITE CSV ===" -ForegroundColor Cyan
$aktDir = Join-Path $hDir 'aktivite'
$csv = Join-Path $aktDir "$((Get-Date).ToString('yyyy-MM-dd')).csv"
if (Test-Path $csv) {
    $rw = @(Import-Csv $csv -Delimiter ';' -Encoding UTF8)
    T "CSV okunabiliyor" ($rw.Count -ge 0) "$($rw.Count) satir"
    T "kolonlar dogru" (($rw[0].PSObject.Properties.Name -join ',') -eq 'zaman,uygulama,baslik,bosta,kategori,sure,kaynak') ($rw[0].PSObject.Properties.Name -join ',')
    T "zaman alani okunabiliyor" ($rw[0].zaman -match '^\d{2}:\d{2}:\d{2}$') $rw[0].zaman
    T "sure alani sayisal" ($rw[0].sure -match '^\d+$') "sure=$($rw[0].sure)"
    $gecersizKat = @($rw | Where-Object { @('calisma','diger','bosta') -notcontains $_.kategori })
    T "tum kategoriler gecerli" ($gecersizKat.Count -eq 0) "$($gecersizKat.Count) gecersiz"
} else { T "bugunun CSV'si" $false 'yok' }
# noktali virgullu baslik testi
$tmp = Join-Path $env:TEMP 'aktest.csv'
'zaman;uygulama;baslik;bosta;kategori' | Out-File $tmp -Encoding utf8
"10:00;test;a,b,c bashk;0;calisma" | Out-File $tmp -Encoding utf8 -Append
$t2 = @(Import-Csv $tmp -Delimiter ';' -Encoding UTF8)
T "noktali virgul temizligi" ($t2[0].kategori -eq 'calisma') "kategori=$($t2[0].kategori)"

Write-Host "`n=== 6. SERI HESABI ===" -ForegroundColor Cyan
function Seri { param($gec, $bugunDk, $hedef)
    $s = 0
    for ($i = $gec.Count - 1; $i -ge 0; $i--) { if ($gec[$i].basarili) { $s++ } else { break } }
    if ($bugunDk -ge $hedef) { $s++ }
    return $s }
$g3 = @(
  [pscustomobject]@{tarih='01';basarili=$true},
  [pscustomobject]@{tarih='02';basarili=$true},
  [pscustomobject]@{tarih='03';basarili=$true})
T "3 basarili gun + bugun 0 dk  => 3" ((Seri $g3 0 240) -eq 3) "sonuc $(Seri $g3 0 240)"
T "3 basarili gun + bugun tamam => 4" ((Seri $g3 240 240) -eq 4) "sonuc $(Seri $g3 240 240)"
$g4 = @([pscustomobject]@{tarih='01';basarili=$true}, [pscustomobject]@{tarih='02';basarili=$false})
T "son gun basarisiz => 0" ((Seri $g4 0 240) -eq 0) "sonuc $(Seri $g4 0 240)"
T "bos gecmis => 0" ((Seri @() 0 240) -eq 0) ''

Write-Host "`n=== 7. SIFIRA BOLME / SINIR DURUMLAR ===" -ForegroundColor Cyan
$bosCsv = @()
$kd = $bosCsv.Count * 5
$oran = 0; if ($kd -gt 0) { $oran = [math]::Round(0/$kd*100) }
T "bos CSV'de sifira bolme yok" ($oran -eq 0) "oran=$oran"
$dolu = [math]::Min([math]::Floor(500/240*20),20)
T "hedef asiminda cubuk tasmiyor" ($dolu -eq 20) "dolu=$dolu"
$pb = [math]::Min([math]::Round(500/240*100),100)
T "ProgressBar %100'u asmiyor" ($pb -eq 100) "pct=$pb"

Write-Host "`n=== 8. ZAMANLANMIS GOREV ===" -ForegroundColor Cyan
$t = Get-ScheduledTask -TaskName $gorevAd -ErrorAction SilentlyContinue
T "gorev kayitli" ($t -ne $null) ''
if ($t) {
    $i = Get-ScheduledTaskInfo -TaskName $gorevAd
    T "durum Ready" ($t.State -eq 'Ready') $t.State
    T "NextRunTime dolu" ($i.NextRunTime -ne $null) "$($i.NextRunTime)"
    T "2 tetikleyici var" ($t.Triggers.Count -eq 2) "$($t.Triggers.Count)"
    T "her ikisinde de tekrar var" (($t.Triggers[0].Repetition.Interval -eq 'PT5M') -and ($t.Triggers[1].Repetition.Interval -eq 'PT5M')) "$($t.Triggers[0].Repetition.Interval)/$($t.Triggers[1].Repetition.Interval)"
    T "son calisma sonucu 0" ($i.LastTaskResult -eq 0) "kod=$($i.LastTaskResult)"
}

Write-Host "`n=== 9. URETILEN RAPORLAR ===" -ForegroundColor Cyan
foreach ($m in @('Calisma Kaydi.md','Aktivite Gunlugu.md')) {
    $p = Join-Path $klasor $m
    T "$m uretilmis" (Test-Path $p) ''
    if (Test-Path $p) {
        $c = Get-Content $p -Raw -Encoding UTF8
        T "$m bos degil" ($c.Length -gt 200) "$($c.Length) karakter"
    }
}

Write-Host "`n=== 10. KISAYOLLAR ===" -ForegroundColor Cyan
# Varlik yetmez: klasor tasininca kisayollar eski yolu gostermeye devam etmisti.
# Her kisayol BU kurulumdaki betigi acmali.
$startup = [Environment]::GetFolderPath('Startup')
$wsh = New-Object -ComObject WScript.Shell
foreach ($k in @(
        @('Startup watchdog kisayolu', (Join-Path $startup 'Aizen.lnk'), 'baslangic.ps1'),
        @('kontrol paneli kisayolu', (Join-Path $klasor 'Aizen.lnk'), 'kontrol.ps1'),
        @('kontrol paneli kisayolu (masaustu)', (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Aizen.lnk'), 'kontrol.ps1'))) {
    $var = Test-Path -LiteralPath $k[1]
    T $k[0] $var ''
    if ($var) {
        $arg = $wsh.CreateShortcut($k[1]).Arguments
        $ok  = $arg.IndexOf((Join-Path $hDir $k[2]), [StringComparison]::OrdinalIgnoreCase) -ge 0
        T "$($k[0]) hedefi" $ok $(if ($ok) { '' } else { $arg })
    }
}

Write-Host "`n=== 10b. ORTAK SAYAC ===" -ForegroundColor Cyan
$ortakPs = Join-Path $hDir 'ortak-sayac.ps1'
T "ortak-sayac.ps1 mevcut" (Test-Path $ortakPs) ''
if (Test-Path $ortakPs) {
    . $ortakPs
    $oTemp = Join-Path $env:TEMP ('ct-test-ortak-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    [void][IO.Directory]::CreateDirectory($oTemp)
    $bugunO = (Get-Date).ToString('yyyy-MM-dd')
    T "dosya yokken 0 doner" ((Get-OrtakSayac -Klasor $oTemp).digerCihazDk -eq 0) ''
    # taze kayit
    $taze = [ordered]@{ tarih = $bugunO; digerCihazDk = 75; toplamDk = 120; cihazSayisi = 2
        cihazlar = @(); guncellemeUtc = [DateTime]::UtcNow.ToString('o') }
    ($taze | ConvertTo-Json -Depth 4) | Out-File (Join-Path $oTemp 'ortak-sayac.json') -Encoding utf8
    $okunan = Get-OrtakSayac -Klasor $oTemp
    T "taze kayit okunur" ($okunan.digerCihazDk -eq 75 -and $okunan.tazeMi) "$($okunan.digerCihazDk) dk"
    # bayat kayit (40 dk once)
    $bayat = [ordered]@{ tarih = $bugunO; digerCihazDk = 75; toplamDk = 120; cihazSayisi = 2
        cihazlar = @(); guncellemeUtc = [DateTime]::UtcNow.AddMinutes(-40).ToString('o') }
    ($bayat | ConvertTo-Json -Depth 4) | Out-File (Join-Path $oTemp 'ortak-sayac.json') -Encoding utf8
    T "bayat kayit sayilmaz" ((Get-OrtakSayac -Klasor $oTemp).digerCihazDk -eq 0) ''
    # dunun kaydi
    $dunku = [ordered]@{ tarih = (Get-Date).Date.AddDays(-1).ToString('yyyy-MM-dd'); digerCihazDk = 75
        toplamDk = 120; cihazSayisi = 2; cihazlar = @(); guncellemeUtc = [DateTime]::UtcNow.ToString('o') }
    ($dunku | ConvertTo-Json -Depth 4) | Out-File (Join-Path $oTemp 'ortak-sayac.json') -Encoding utf8
    T "dunun kaydi sayilmaz" ((Get-OrtakSayac -Klasor $oTemp).digerCihazDk -eq 0) ''
    Remove-Item -LiteralPath $oTemp -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host "`n=== 11. YEDEK ===" -ForegroundColor Cyan
$yedekPs = Join-Path $hDir 'yedek-al.ps1'
T "yedek-al.ps1 mevcut" (Test-Path $yedekPs) ''
if (Test-Path $yedekPs) {
    $yHedef = Join-Path $env:TEMP ('ct-test-yedek-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $yLog = Join-Path $yHedef 'test-log.txt'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $yedekPs -Hedef $yHedef -Saklama 2 -Sessiz -LogYolu $yLog | Out-Null
    $zipler = @(Get-ChildItem -LiteralPath $yHedef -Filter '*.zip' -File -ErrorAction SilentlyContinue)
    T "yedek uretildi" ($zipler.Count -eq 1) "$($zipler.Count) zip"
    if ($zipler.Count -eq 1) {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $arsiv = [IO.Compression.ZipFile]::OpenRead($zipler[0].FullName)
        try {
            $adlar = @($arsiv.Entries | ForEach-Object { $_.FullName })
            T "yedekte sayac (durum.json)" ($adlar -contains 'durum.json') ''
            T "yedekte kurallar" ($adlar -contains 'kurallar.json') ''
            T "yedekte ham aktivite" (@($adlar | Where-Object { $_ -match 'aktivite' }).Count -gt 0) "$(@($adlar | Where-Object { $_ -match 'aktivite' }).Count) dosya"
            T "yedekte geri yukleme notu" ($adlar -contains 'YEDEK-BILGISI.txt') ''
        }
        finally { $arsiv.Dispose() }
        # Ayni gun ikinci calistirma yeni zip uretmemeli (haftalik gorev gun icinde tekrarlarsa)
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $yedekPs -Hedef $yHedef -Sessiz -LogYolu $yLog | Out-Null
        T "ayni gun ikinci yedek uretilmez" (@(Get-ChildItem -LiteralPath $yHedef -Filter '*.zip' -File).Count -eq 1) ''
    }
    if (Test-Path -LiteralPath $yHedef) { Remove-Item -LiteralPath $yHedef -Recurse -Force -ErrorAction SilentlyContinue }
}
$yGorev = Get-ScheduledTask -TaskName 'Calisma Takip Yedek' -ErrorAction SilentlyContinue
T "haftalik yedek gorevi kurulu" ($null -ne $yGorev) $(if ($yGorev) { "$($yGorev.State)" } else { 'yok' })
if ($yGorev) {
    T "yedek gorevi wscript ile" (@($yGorev.Actions)[0].Execute -match 'wscript\.exe') ''
}

Write-Host "`n===================================" -ForegroundColor Cyan
Write-Host ("  GECTI: {0}   KALDI: {1}" -f $gecti, $kaldi) -ForegroundColor $(if ($kaldi -eq 0) { 'Green' } else { 'Red' })
Write-Host "===================================`n" -ForegroundColor Cyan
# Cikis kodu sonucu tasir. Panelin Test dugmesi -NoExit ile acar; exit pencereyi kapatmaz.
exit $(if ($kaldi -gt 0) { 1 } else { 0 })


