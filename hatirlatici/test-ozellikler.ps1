# ============================================================
#  Kurulum turu, ozellik anahtarlari, ayar yazimi ve uygulama ici wiki testleri.
#  Pencere acmaz, canli dosyalara yazmaz (gecici kasalar %TEMP% altinda).
#  Kullanim: powershell -NoProfile -ExecutionPolicy Bypass -File hatirlatici\test-ozellikler.ps1
# ============================================================
$ErrorActionPreference = 'Stop'
$hDir = $PSScriptRoot; if (-not $hDir) { $hDir = Split-Path $MyInvocation.MyCommand.Path -Parent }
$kok = Split-Path $hDir -Parent
$script:gecti = 0; $script:kaldi = 0
function T { param($ad, $sonuc, $detay = '')
    if ($sonuc) { $script:gecti++; Write-Host ("  [OK]   {0,-58} {1}" -f $ad, $detay) -ForegroundColor Green }
    else        { $script:kaldi++; Write-Host ("  [HATA] {0,-58} {1}" -f $ad, $detay) -ForegroundColor Red } }
function Baslik { param($t) Write-Host "`n=== $t ===" -ForegroundColor Cyan }

. (Join-Path $hDir 'ozellikler.ps1')
. (Join-Path $hDir 'wiki.ps1')

$kasalar = New-Object System.Collections.Generic.List[string]
function Yeni-Kasa {
    $k = Join-Path $env:TEMP ('ct-ozellik-' + [guid]::NewGuid().ToString('N').Substring(0, 10))
    [void][IO.Directory]::CreateDirectory((Join-Path $k 'hatirlatici'))
    [void][IO.Directory]::CreateDirectory((Join-Path $k 'dagitik'))
    $kasalar.Add($k); return $k }
function Yaz { param($Yol, $Metin) [IO.File]::WriteAllText($Yol, $Metin, (New-Object Text.UTF8Encoding($true))) }

try {
    Baslik '1. ONCELIK: ayarlar.json > kurulum-bilgisi.json > turun varsayilani'
    $k = Yeni-Kasa; $h = Join-Path $k 'hatirlatici'; $bilgi = Join-Path $k 'dagitik\kurulum-bilgisi.json'; $ayar = Join-Path $h 'ayarlar.json'
    $durumlar = @(
        # ad, ayarlar.json (bos = yok), kurulum-bilgisi.json (bos = yok), beklenen tur, hatirlatma, kilit, ayarlanabilir
        @('dosya yok: bireysel, ikisi acik', '', '', 'bireysel', $true, $true, $true),
        @('eski ayarlar (yeni alan yok)', '{"hedef":240,"duraklat":""}', '', 'bireysel', $true, $true, $true),
        @('eski kurulum bilgisi (tur yok)', '', '{"surum":1,"rol":"Kullanici"}', 'bireysel', $true, $true, $true),
        @('sirket: ikisi kapali', '', '{"kurulumTuru":"sirket","ozellikler":{"hatirlatmalar":false,"ekranKilidi":false}}', 'sirket', $false, $false, $false),
        @('sirket, ozellik yazilmamis: varsayilan kapali', '', '{"kurulumTuru":"Sirket"}', 'sirket', $false, $false, $false),
        @('sirket: ayarlar hatirlatmayi acamaz', '{"hatirlatmalar":true}', '{"kurulumTuru":"sirket"}', 'sirket', $false, $false, $false),
        @('sirket: ayarlar kilidi acar', '{"ekranKilidi":true}', '{"kurulumTuru":"sirket"}', 'sirket', $false, $true, $false),
        @('ozel: kurulum secimi', '', '{"kurulumTuru":"ozel","ozellikler":{"hatirlatmalar":false,"ekranKilidi":true}}', 'ozel', $false, $true, $true),
        @('ozel, ozellik yok: hatirlatma acik kilit kapali', '', '{"kurulumTuru":"ozel"}', 'ozel', $true, $false, $true),
        @('bireysel: ayar kilidi kapatir', '{"ekranKilidi":false}', '{"kurulumTuru":"bireysel"}', 'bireysel', $true, $false, $true),
        @('bireysel: ayar hatirlatmayi kapatir', '{"hatirlatmalar":"kapali"}', '', 'bireysel', $false, $true, $true),
        @('ayarlardaki tur kurulumun onune gecer', '{"kurulumTuru":"sirket"}', '{"kurulumTuru":"bireysel"}', 'sirket', $false, $false, $false),
        @('Turkce yazimli tur (Sirket, s-cedilla)', '', ('{"kurulumTuru":"' + [char]0x015E + 'irket"}'), 'sirket', $false, $false, $false),
        @('anlasilmayan deger yok sayilir', '{"ekranKilidi":"belki"}', '{"kurulumTuru":"ozel","ozellikler":{"ekranKilidi":true}}', 'ozel', $true, $true, $true),
        @('bozuk ayarlar: kurulum gecerli', '{bozuk', '{"kurulumTuru":"sirket","ozellikler":{"ekranKilidi":true}}', 'sirket', $false, $true, $false),
        @('bozuk kurulum bilgisi: bireysel', '', 'bozuk{', 'bireysel', $true, $true, $true)
    )
    foreach ($d in $durumlar) {
        foreach ($p in @($ayar, $bilgi)) { if (Test-Path $p) { Remove-Item $p -Force } }
        if ($d[1]) { Yaz $ayar $d[1] }
        if ($d[2]) { Yaz $bilgi $d[2] }
        $o = Get-TakipOzellikleri -HatirlaticiKlasoru $h
        $ok = ($o.kurulumTuru -eq $d[3] -and $o.hatirlatmalar -eq $d[4] -and $o.ekranKilidi -eq $d[5] -and $o.hatirlatmaAyarlanabilir -eq $d[6])
        T $d[0] $ok ("tur={0} hatirlatma={1} kilit={2} ayarlanabilir={3}" -f $o.kurulumTuru, $o.hatirlatmalar, $o.ekranKilidi, $o.hatirlatmaAyarlanabilir)
    }
    Yaz $ayar '{"ekranKilidi":false}'; Yaz $bilgi '{"kurulumTuru":"bireysel"}'
    $o = Get-TakipOzellikleri -HatirlaticiKlasoru $h
    T 'kaynak bilgisi: kilit ayarlardan, hatirlatma varsayilandan' ($o.ekranKilidiKaynagi -eq 'ayarlar' -and $o.hatirlatmalarKaynagi -eq 'varsayilan') "$($o.ekranKilidiKaynagi)/$($o.hatirlatmalarKaynagi)"
    $taban = Get-TakipOzellikleri -HatirlaticiKlasoru $h -Ayarlar @{}
    T '-Ayarlar @{}: ayarlar olmadan gecerli deger' ($taban.ekranKilidi -eq $true) "kilit=$($taban.ekranKilidi)"
    T 'tur adlari' ((Oz-TurAdi 'bireysel') -eq 'Bireysel' -and (Oz-TurAdi 'sirket') -eq ([string][char]0x015E + 'irket') -and (Oz-TurAdi 'ozel') -eq ([string][char]0x00D6 + 'zel')) ''

    Baslik '2. AYAR YAZIMI: alanlar korunur, null anahtari siler'
    $k = Yeni-Kasa; $h = Join-Path $k 'hatirlatici'; $ayar = Join-Path $h 'ayarlar.json'
    Yaz $ayar '{"hedef":90,"duraklat":"sonsuz","yedekKlasoru":"D:/Yedek","gelecekAlani":{"a":1}}'
    [void](Oz-AyarGuncelle $h ([ordered]@{ ekranKilidi = $false; hatirlatmalar = $true }))
    $a = Get-Content $ayar -Raw -Encoding UTF8 | ConvertFrom-Json
    T 'yeni anahtarlar yazildi' ($a.ekranKilidi -eq $false -and $a.hatirlatmalar -eq $true) ''
    T 'hedef/duraklat korundu' ($a.hedef -eq 90 -and $a.duraklat -eq 'sonsuz') "$($a.hedef) $($a.duraklat)"
    T 'bilinmeyen alanlar korundu' ($a.yedekKlasoru -eq 'D:/Yedek' -and $a.gelecekAlani.a -eq 1) ''
    [void](Oz-AyarGuncelle $h ([ordered]@{ ekranKilidi = $null }))
    $a = Get-Content $ayar -Raw -Encoding UTF8 | ConvertFrom-Json
    T 'null deger anahtari siler' ($null -eq $a.PSObject.Properties['ekranKilidi'] -and $a.hatirlatmalar -eq $true) ''
    $b = [IO.File]::ReadAllBytes($ayar)
    T 'UTF-8 BOM ile yazilir (diger okuyucularla ayni)' ($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) ''
    T 'gecici dosya kalmaz' (-not (Test-Path "$ayar.yeni")) ''
    Remove-Item $ayar
    [void](Oz-AyarGuncelle $h ([ordered]@{ ekranKilidi = $true }))
    $a = Get-Content $ayar -Raw -Encoding UTF8 | ConvertFrom-Json
    T 'dosya yoksa varsayilanlarla olusur' ($a.hedef -eq 240 -and $a.ekranKilidi -eq $true) ''
    Yaz $ayar '{"hedef":75, bozuk'
    [void](Oz-AyarGuncelle $h ([ordered]@{ ekranKilidi = $false }))
    $yedek = @(Get-ChildItem $h -Filter 'ayarlar.json.bozuk-*')
    T 'bozuk dosya ezilmeden once kenara alinir' ($yedek.Count -eq 1 -and [IO.File]::ReadAllText($yedek[0].FullName).Contains('bozuk')) "$($yedek.Count) yedek"

    Baslik '3. BETIK BAGLANTILARI'
    $takip = Get-Content (Join-Path $hDir 'takip.ps1') -Raw -Encoding UTF8
    T 'takip.ps1 ozellikleri okur' ($takip -match 'Get-TakipOzellikleri') ''
    T 'takip.ps1 hatirlatma kapaliysa uyaridan once cikar' ($takip -match 'if \(-not \$HATIRLATMA\) \{ exit \}') ''
    T 'takip.ps1 kilit kapaliysa pencere kipi' ($takip -match '-Pencere:\(-not \$EKRAN_KILIDI\)') ''
    T 'takip.ps1 test ciftinin degistirdigi satirlar yerinde' ($takip.Contains('$sonuc = $f.ShowDialog()') -and $takip.Contains('Start-Process explorer.exe $klasor')) ''
    $izleyici = Get-Content (Join-Path $hDir 'izleyici.ps1') -Raw -Encoding UTF8
    T 'izleyici engeli ekran kilidine bagli' ($izleyici -match '-not \$ozI\.ekranKilidi') ''
    $kontrol = Get-Content (Join-Path $hDir 'kontrol.ps1') -Raw -Encoding UTF8
    T 'kontrol paneli ayarlari alan koruyarak yazar' ($kontrol -match 'Oz-AyarYaz' -and $kontrol -notmatch 'ConvertTo-Json \| Out-File -FilePath \$ayarD') ''
    T 'kontrol paneli Ayarlar ve Yardim dugmeleri' ($kontrol -match 'Ayarlar-Penceresi' -and $kontrol -match 'wiki-penceresi\.ps1') ''
    $tema = Get-Content (Join-Path $hDir 'tema.ps1') -Raw
    T 'tema: tam ekran kart pencere kipini destekler' ($tema -match '\[switch\]\$Pencere') ''

    Baslik '4. WIKI: on bilgi, suzme, HTML'
    $wk = Join-Path (Yeni-Kasa) 'wiki'; [void][IO.Directory]::CreateDirectory($wk)
    Yaz (Join-Path $wk 'a.md') "---`nbaslik: A sayfasi`nturler: hepsi`nplatformlar: hepsi`nsira: 20`n---`n# A`n`nOrtak.`n<!-- yalniz: sirket -->`nSirkete ozel.`n<!-- /yalniz -->`n<!-- yalniz: windows -->`nWin`n<!-- yalniz: bireysel -->`nWin+bireysel.`n<!-- /yalniz -->`nWin son.`n<!-- /yalniz -->`n- bir`n<!-- yalniz: mac -->`n- mac`n<!-- /yalniz -->`n- iki`n  devam`n`n[B'ye git](b) ve [gizli](c) ve **kalin** ``<kod>```n`n| x | y |`n|---|---|`n| 1 | <b> |"
    Yaz (Join-Path $wk 'b.md') "---`nbaslik: B`nturler: bireysel, ozel`nsira: 10`n---`nB govde"
    Yaz (Join-Path $wk 'c.md') "---`nbaslik: C`nplatformlar: mac`nsira: 30`n---`nC"
    Yaz (Join-Path $wk 'README.md') "# yazar notu"
    $bw = @(Wiki-Sayfalar $wk 'bireysel' 'windows')
    T 'sira ve tur/platform filtresi (bireysel windows)' ((($bw | ForEach-Object ad) -join ',') -eq 'b,a') (($bw | ForEach-Object ad) -join ',')
    $sw = @(Wiki-Sayfalar $wk 'sirket' 'windows')
    T 'sirket: bireysel/ozel sayfasi gizli' ((($sw | ForEach-Object ad) -join ',') -eq 'a') (($sw | ForEach-Object ad) -join ',')
    $om = @(Wiki-Sayfalar $wk 'ozel' 'mac')
    T 'mac: yalniz mac sayfasi gorunur' ((($om | ForEach-Object ad) -join ',') -eq 'b,a,c') (($om | ForEach-Object ad) -join ',')
    T 'README listelenmez' (@($bw + $sw + $om | Where-Object { $_.ad -eq 'readme' }).Count -eq 0) ''
    $a = $bw | Where-Object ad -eq 'a'
    T 'on bilgi okundu' ($a.baslik -eq 'A sayfasi' -and $a.sira -eq 20) ''
    T 'blok: baska turun bolumu gizli' (-not $a.govde.Contains('Sirkete ozel')) ''
    T 'blok: ic ice (windows > bireysel) gorunur' ($a.govde.Contains('Win+bireysel.') -and $a.govde.Contains('Win son.')) ''
    $as = ($sw | Where-Object ad -eq 'a').govde
    T 'blok: ic ice, dis gorunur ic gizli' ($as.Contains('Win son.') -and -not $as.Contains('Win+bireysel.') -and $as.Contains('Sirkete ozel')) ''
    T 'isaret satirlari ciktida kalmaz' (-not $a.govde.Contains('yalniz')) ''
    $adlar = @($bw | ForEach-Object ad)
    $html = Wiki-Html $a.govde $adlar
    T 'HTML: gorunen sayfaya baglanti' ($html.Contains('<a href="wiki:b">')) ''
    T 'HTML: gizli sayfaya baglanti duz metin' ($html.Contains('ve gizli ve') -and -not $html.Contains('wiki:c')) ''
    T 'HTML: kod ve tablo icerigi kacislanir' ($html.Contains('<code>&lt;kod&gt;</code>') -and $html.Contains('<td>&lt;b&gt;</td>')) ''
    T 'HTML: kalin, baslik, tablo basligi' ($html.Contains('<strong>kalin</strong>') -and $html.Contains('<h1>A</h1>') -and $html.Contains('<th>x</th>')) ''
    T 'HTML: gizli liste ogesi listeyi bolmez, devam satiri birlesir' ($html -match '<ul>\s*<li>bir</li>\s*<li>iki devam</li>\s*</ul>') ''
    T 'HTML belgesi: karakter kumesi ve stil' ((Wiki-Belge $a $adlar) -match '<meta charset="utf-8">.*<style>') ''

    Baslik '5. WIKI ICERIGI: gercek sayfalar'
    $gercek = Join-Path $kok 'wiki'
    $hepsi = @(Get-ChildItem $gercek -Filter '*.md' | Where-Object { $_.Name -ne 'README.md' })
    T 'wiki sayfalari var' ($hepsi.Count -ge 8) "$($hepsi.Count) sayfa"
    $onBilgisiz = @($hepsi | Where-Object { -not [IO.File]::ReadAllText($_.FullName, [Text.Encoding]::UTF8).Replace("`r`n", "`n").StartsWith("---`nbaslik:") })
    T 'her sayfa on bilgiyle baslar' ($onBilgisiz.Count -eq 0) (($onBilgisiz | ForEach-Object Name) -join ', ')
    $tumAdlar = @($hepsi | ForEach-Object { $_.BaseName.ToLowerInvariant() })
    $kirik = @(); $dengesiz = @()
    foreach ($d in $hepsi) {
        $metin = [IO.File]::ReadAllText($d.FullName, [Text.Encoding]::UTF8)
        foreach ($m in [regex]::Matches($metin, '\]\(([^)\s]+)\)')) { if ($tumAdlar -notcontains $m.Groups[1].Value) { $kirik += "$($d.Name)->$($m.Groups[1].Value)" } }
        $ac = [regex]::Matches($metin, '<!--\s*yalniz\s*:').Count; $kapa = [regex]::Matches($metin, '<!--\s*/yalniz\s*-->').Count
        if ($ac -ne $kapa) { $dengesiz += "$($d.Name) ($ac/$kapa)" }
    }
    T 'sayfa baglantilari var olan sayfalara gider' ($kirik.Count -eq 0) ($kirik -join ', ')
    T 'yalniz bloklari dengeli' ($dengesiz.Count -eq 0) ($dengesiz -join ', ')
    foreach ($tur in 'bireysel', 'sirket', 'ozel') {
        foreach ($pl in 'windows', 'mac') {
            $s = @(Wiki-Sayfalar $gercek $tur $pl)
            $hat = @($s | Where-Object ad -eq 'hatirlatmalar').Count -eq 1
            $beklenen = ($tur -ne 'sirket')
            $bos = @($s | Where-Object { [string]::IsNullOrWhiteSpace($_.govde) }).Count
            T "$tur/$pl`: hatirlatma sayfasi $(if ($beklenen) { 'var' } else { 'yok' }), bos sayfa yok" ($hat -eq $beklenen -and $bos -eq 0) "$($s.Count) sayfa"
        }
    }
    $sirketMetni = (@(Wiki-Sayfalar $gercek 'sirket' 'windows') | ForEach-Object govde) -join "`n"
    T 'sirket metninde erteleme/vazgecme anlatilmaz' ($sirketMetni -notmatch 'ertele|Vazgeçtim') ''
    $htmlHepsi = (@(Wiki-Sayfalar $gercek 'bireysel' 'windows') | ForEach-Object { Wiki-Html $_.govde $tumAdlar }) -join "`n"
    T 'gercek sayfalar HTML''e cevrilir' ($htmlHepsi.Length -gt 4000 -and $htmlHepsi -notmatch '\*\*') "$($htmlHepsi.Length) karakter"

    Baslik '6. MAC: uretilmis wiki icerigi guncel'
    $uretici = Join-Path $kok 'macos\scripts\generate-wiki.ps1'
    T 'uretici betik var' (Test-Path $uretici) ''
    if (Test-Path $uretici) {
        $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        $cikti = @(& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File $uretici -Kontrol 2>&1)
        $kodu = $LASTEXITCODE; $ErrorActionPreference = $eap
        T 'WikiIcerik.swift wiki klasoruyle ayni (degistiysen: generate-wiki.ps1)' ($kodu -eq 0) (($cikti | Select-Object -Last 1) -join '')
    }
}
catch {
    $script:kaldi++
    Write-Host "  [HATA] beklenmeyen: $($_.Exception.Message) [satir $($_.InvocationInfo.ScriptLineNumber)]" -ForegroundColor Red
}
finally {
    foreach ($k in $kasalar) { if (Test-Path $k) { Remove-Item -LiteralPath $k -Recurse -Force } }
}

Write-Host ("`n  GECTI: {0}   KALDI: {1}" -f $script:gecti, $script:kaldi) -ForegroundColor $(if ($script:kaldi -eq 0) { 'Green' } else { 'Red' })
exit $(if ($script:kaldi -gt 0) { 1 } else { 0 })
