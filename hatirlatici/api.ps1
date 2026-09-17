# ============================================================
#  Takip API -- yapay zekalar ve scriptler icin tek giris noktasi
#  Bu dosya UTF-8 BOM ile kaydedilir (Turkce metinleri PS 5.1 dogru okusun diye).
#
#  Komut satiri (cikti: tek satir JSON, UTF-8; hata: {"hata":"..."} + cikis kodu 1):
#    powershell -NoProfile -ExecutionPolicy Bypass -File hatirlatici/api.ps1 <komut> [secenekler]
#      durum                                  bugunku sayac, seri, takip sagligi
#      brifing [-Kaydet]                      sabah brifingi; .metin hazir markdown. -Kaydet gunluge yazar
#      rapor [-Tarih yyyy-MM-dd]              bir gunun kompakt ozeti (gerekirse raporu yeniden uretir)
#      siniflandir -Oge <ad> -Karar calisma|yasakli|belirsiz [-Tur surec|baslik|alanadi]
#  mcp.ps1 bu dosyayi nokta-kaynak (.) olarak yukler ve ayni fonksiyonlari arac olarak sunar.
#  Test icin: $env:TAKIP_KASA = baska bir hatirlatici klasoru (gercek veriye dokunulmaz).
# ============================================================
param(
    [Parameter(Position = 0)][string]$Komut = 'durum',
    [string]$Tarih,
    [string]$Oge,
    [string]$Karar,
    [string]$Tur = 'surec',
    [switch]$Kaydet
)
$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'
$script:H = $PSScriptRoot; if ($env:TAKIP_KASA) { $script:H = $env:TAKIP_KASA }
$script:INV = [Globalization.CultureInfo]::InvariantCulture
$script:TR  = [Globalization.CultureInfo]'tr-TR'
$script:ERTELEME_HAKKI = 3
$script:SORU_ESIGI_DK = 5        # bu kadar dakikadan kisa siniflanmamis ogeler sorulmaz, topluca gecilir

# ---------- yardimcilar ----------
function Tk-Json { param($yol)
    if (-not (Test-Path $yol)) { return $null }
    try { return (Get-Content $yol -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null } }
# PS 5.1: Get-Content | ConvertFrom-Json diziyi tek nesneye cokertir -- once degiskene ata, sonra sar
function Tk-JsonDizi { param($yol)
    if (-not (Test-Path $yol)) { return @() }
    $ham = Get-Content $yol -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($ham)) { return @() }
    $o = $null; try { $o = ConvertFrom-Json $ham } catch { return @() }
    if ($null -eq $o) { return @() }
    return @($o) }
function Tk-Say { param($x) if ($null -eq $x) { return 0 }; return @($x).Count }
function Tk-Klasor { return (Split-Path $script:H -Parent) }
function Tk-Liste { param($ogeler, [int]$n = 4)
    return ((@($ogeler) | Select-Object -First $n | ForEach-Object { "$($_.ad) $($_.dk)" }) -join ' · ') }

# ---------- saglik ----------
function Takip-Saglik {
    $s = [ordered]@{ durum = 'normal'; sorunlar = @(); gorev = ''; izleyici = ''; duraklatma = ''; periyot = $false; acilDurdur = $false; sonLog = '' }
    $ad = 'Calisma Takip Sistemi'; $gt = $null; $svc = $null; $gorevOkunamadi = $false
    try { $svc = New-Object -ComObject Schedule.Service; $svc.Connect(); $gt = $svc.GetFolder('\').GetTask($ad) } catch { $gorevOkunamadi = $true }
    if (-not $gt) { try { $yol = (Get-ScheduledTask -TaskName $ad -ErrorAction Stop).TaskPath; $gt = $svc.GetFolder($yol.TrimEnd('\')).GetTask($ad) } catch { $gorevOkunamadi = $true } }
    if ($gt) {
        $durumAd = switch ([int]$gt.State) { 1 {'devre dışı'} 2 {'sırada'} 3 {'hazır'} 4 {'çalışıyor'} default {'bilinmiyor'} }
        $sonraki = 'YOK'; if ($gt.NextRunTime -gt [datetime]'2000-01-01') { $sonraki = $gt.NextRunTime.ToString('HH:mm') }
        $s.gorev = "$durumAd · son tur $($gt.LastRunTime.ToString('HH:mm')) (sonuç $($gt.LastTaskResult)) · sonraki $sonraki"
        if (-not $gt.Enabled) { $s.sorunlar += 'görev devre dışı' }
        elseif ($sonraki -eq 'YOK') { $s.sorunlar += 'görevin sonraki çalışması yok' }
    } elseif ($gorevOkunamadi) {
        # Kisitli istemcilerde (sandbox/MCP hostu vb.) gorev okunamayabilir; bunu
        # "yok" diye raporlamak gercek bir kurulum sorununu taklit eder.
        $s.gorev = 'erişim kısıtlı · görev doğrulanamadı'
        $s.sorunlar += 'zamanlanmış görev bu oturumda okunamıyor'
    } else { $s.gorev = 'bulunamadı'; $s.sorunlar += 'zamanlanmış görev yok' }
    $ay = Tk-Json (Join-Path $script:H 'ayarlar.json')
    if ($ay -and $ay.duraklat) { $s.duraklatma = [string]$ay.duraklat }
    $p = Tk-Json (Join-Path $script:H 'periyot.json')
    if ($p -and $p.aktif) { $s.periyot = $true }
    $s.acilDurdur = (Test-Path (Join-Path $script:H 'DUR'))
    # Izleyici her 10 sn'de bir ornek yazar (AFK'da da); duraklatmada yazmaz
    $csv = Get-ChildItem (Join-Path $script:H 'aktivite') -Filter '*.csv' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $yas = -1; if ($csv) { $yas = [int]((Get-Date) - $csv.LastWriteTime).TotalSeconds }
    if ($yas -ge 0 -and $yas -le 90) { $s.izleyici = "canlı · son örnek $yas sn önce" }
    elseif ($s.duraklatma) { $s.izleyici = 'duraklatmada · örnek yazmıyor (beklenen)' }
    else { $s.izleyici = "örnek yok ($yas sn)"; $s.sorunlar += 'izleyici örnek yazmıyor' }
    $son = Get-Content (Join-Path $script:H 'log.txt') -Tail 1 -Encoding UTF8
    if ($son) { $s.sonLog = $son.Substring(0, [math]::Min(140, $son.Length)) }
    if ($s.sorunlar.Count) { $s.durum = 'sorun' }
    return $s
}

# ---------- durum ----------
function Takip-Durum {
    $bugun = (Get-Date).ToString('yyyy-MM-dd')
    $ay = Tk-Json (Join-Path $script:H 'ayarlar.json')
    $hedef = 240; if ($ay -and $ay.hedef) { $hedef = [int]$ay.hedef }
    $d = Tk-Json (Join-Path $script:H 'durum.json')
    $dk = 0; $ert = 0; $vaz = $false
    if ($d -and $d.tarih -eq $bugun) { $dk = [int]$d.dakika; $ert = [int]$d.ertSayi; $vaz = [bool]$d.vazgecti }
    # Ortak sayac: dakika bu makinenin olcumu, toplam tum cihazlarin (takip.ps1 ile ayni)
    $digerDk = 0
    $ortakPs = Join-Path $script:H 'ortak-sayac.ps1'
    if (Test-Path $ortakPs) { . $ortakPs; $digerDk = [int](Get-OrtakSayac -Klasor $script:H).digerCihazDk }
    $toplam = $dk + $digerDk
    $gec = Tk-JsonDizi (Join-Path $script:H 'gecmis.json')
    # takip.ps1 ile ayni kural: seri gecmisten sayilir, bugun hedef tutulduysa +1
    $seri = 0
    for ($i = $gec.Count - 1; $i -ge 0; $i--) { if ($gec[$i].basarili) { $seri++ } else { break } }
    if ($toplam -ge $hedef) { $seri++ }
    $esik = (Get-Date).Date.AddDays(-6).ToString('yyyy-MM-dd')
    $son7 = $toplam
    foreach ($g in $gec) {
        if ([string]$g.tarih -ge $esik -and $g.tarih -ne $bugun) {
            $gunDk = [int]$g.dakika
            if ($g.PSObject.Properties['toplam'] -and [int]$g.toplam -gt $gunDk) { $gunDk = [int]$g.toplam }
            $son7 += $gunDk
        }
    }
    return [ordered]@{
        tarih = $bugun; dakika = $dk; digerCihazDk = $digerDk; toplamDakika = $toplam
        hedef = $hedef; yuzde = [math]::Round($toplam / $hedef * 100)
        kalanDk = [math]::Max($hedef - $toplam, 0); ertelemeHakki = [math]::Max($script:ERTELEME_HAKKI - $ert, 0)
        vazgecti = $vaz; seri = $seri; son7GunDk = $son7; saglik = (Takip-Saglik)
    }
}

# ---------- rapor ----------
# Incelenecek ogeler: rapordaki belirsiz uygulama ve alan adlarindan BUGUNKU kurallarda karari
# olmayanlar (rapor sonradan verilen kararlardan eski olabilir). Brifing sorulari (Takip-Rapor) ve
# rapor penceresinin Incelenecek sekmesi ayni listeyi kullanir: "karar verilmis mi" tek yerde.
function Tk-Incelenecekler { param($Rapor)
    $k = Tk-Json (Join-Path $script:H 'kurallar.json')
    $bilerek = @(); $surecler = @(); $baslikKel = @(); $alanAdlari = @()
    if ($k) {
        if ($k.bilerekBelirsiz) { $bilerek = @($k.bilerekBelirsiz) }
        $surecler = @($k.calisma.surec) + @($k.yasakli.surec)
        $baslikKel = @(@($k.calisma.baslik) + @($k.yasakli.baslik) | Where-Object { $_ })
        $alanAdlari = @(@($k.calisma.alanadi) + @($k.yasakli.alanadi) | Where-Object { $_ })
    }
    $liste = @()
    foreach ($u in @($Rapor.incelenecekUygulamalar)) {
        if (-not $u.ad -or $bilerek -contains $u.ad -or $surecler -contains $u.ad) { continue }
        $ob = [string]$u.ornekBaslik
        if ($ob -and @($baslikKel | Where-Object { $ob -like "*$_*" }).Count) { continue }
        $liste += [ordered]@{ tur = 'surec'; ad = [string]$u.ad; dk = [int]$u.dakika; ornek = $ob }
    }
    foreach ($a in @($Rapor.incelenecekAlanlar)) {
        $al = [string]$a.alan
        if (-not $al -or $bilerek -contains $al) { continue }
        # izleyici/gunluk-rapor ile ayni eslesme: kural alan adinin parcasiysa karar verilmistir
        if (@($alanAdlari | Where-Object { $al -like "*$_*" }).Count) { continue }
        $liste += [ordered]@{ tur = 'alanadi'; ad = $al; ziyaret = [int]$a.ziyaret }
    }
    return $liste
}
function Takip-Rapor { param([string]$Tarih)
    if (-not $Tarih) { $Tarih = (Get-Date).ToString('yyyy-MM-dd') }
    $gun = [datetime]::ParseExact($Tarih, 'yyyy-MM-dd', $script:INV)
    $yol = Join-Path $script:H "rapor\$Tarih.json"
    # Gecmis gun: gun bittikten sonra uretilmemisse yenile. Bugun: 10 dk'dan eskiyse yenile.
    $taze = $false
    if (Test-Path $yol) {
        $yazim = (Get-Item $yol).LastWriteTime
        if ($gun.Date -eq (Get-Date).Date) { $taze = ((Get-Date) - $yazim).TotalMinutes -lt 10 } else { $taze = $yazim -ge $gun.Date.AddDays(1) }
    }
    $uretildi = $false
    if (-not $taze -and (Test-Path (Join-Path $script:H "aktivite\$Tarih.csv"))) {
        $gr = Join-Path $script:H 'gunluk-rapor.ps1'
        if (Test-Path $gr) { & $gr -Tarih $Tarih -GecmisDahil | Out-Null; $uretildi = $true }
    }
    $r = Tk-Json $yol
    if (-not $r) { return [ordered]@{ tarih = $Tarih; var = $false } }
    $uyg = @($r.uygulamalar)
    $yasakli = @($uyg | Where-Object { $_.kaynak -eq 'yasakli' -and $_.dakika -gt 0 } | Select-Object -First 5 | ForEach-Object { [ordered]@{ ad = $_.ad; dk = [int]$_.dakika } })
    $calisma = @($uyg | Where-Object { $_.kategori -eq 'calisma' -and $_.dakika -gt 0 } | Select-Object -First 5 | ForEach-Object { [ordered]@{ ad = $_.ad; dk = [int]$_.dakika } })
    $bekleyen = @(); $kisa = @()
    foreach ($o in @(Tk-Incelenecekler $r)) {
        $olcu = $o.dk; if ($o.tur -eq 'alanadi') { $olcu = $o.ziyaret }
        if ($olcu -ge $script:SORU_ESIGI_DK) { $bekleyen += $o } else { $kisa += $o.ad }
    }
    # Eski raporlarda tarayiciDurum, hata mesajiyla birlikte on binlerce karakter olabiliyor -- kirp
    $td = [string]$r.tarayiciDurum; if ($td.Length -gt 150) { $td = $td.Substring(0, 150) + '...' }
    return [ordered]@{
        tarih = $Tarih; var = $true; uretildi = $uretildi
        calismaDk = [int]$r.calismaDk; digerDk = [int]$r.digerDk; bostaDk = [int]$r.bostaDk; hedefDk = [int]$r.hedefDk
        yasakli = $yasakli; calisma = $calisma
        basliklar = @(@($r.enCokBakilan) | Select-Object -First 5 | ForEach-Object { "$($_.uygulama): $($_.baslik) ($($_.dakika) dk)" })
        tarayici = [ordered]@{ durum = $td; alanlar = @(@($r.alanlar) | Select-Object -First 5 | ForEach-Object { "$($_.alan) $($_.ziyaret)" }); aramalar = @(@($r.aramalar) | ForEach-Object { $_.terim } | Select-Object -Unique | Select-Object -First 20) }
        bekleyen = $bekleyen; kisaGecilen = $kisa
    }
}

# ---------- brifing ----------
# Takip gunlugunde yalnizca isaretli blogu yonetir; elle yazilmis icerige dokunmaz.
function Tk-GunlukBlok { param([string]$Tarih, [string]$Ad, [string]$Baslik, [string]$Icerik)
    $dir = Join-Path (Tk-Klasor) 'Gunluk'
    [void][IO.Directory]::CreateDirectory($dir)
    $yol = Join-Path $dir "$Tarih.md"
    $bas = "<!-- otomatik:$Ad -->"; $son = "<!-- /otomatik:$Ad -->"
    $blok = "$bas`r`n$Icerik`r`n$son"
    if (Test-Path $yol) {
        $m = [IO.File]::ReadAllText($yol, [Text.Encoding]::UTF8)
        if ($m.Contains($bas)) {
            $i = $m.IndexOf($bas); $j = $m.IndexOf($son, $i)
            if ($j -lt 0) { return 'isaret bozuk, dokunulmadi' }
            $m = $m.Substring(0, $i) + $blok + $m.Substring($j + $son.Length)
        } elseif ($m -match "(?m)^##\s+$([regex]::Escape($Baslik))") { return 'elle yazilmis bolum var, dokunulmadi' }
        else { $m = $m.TrimEnd() + "`r`n`r`n## $Baslik`r`n`r`n$blok`r`n" }
    } else {
        $g = [datetime]::ParseExact($Tarih, 'yyyy-MM-dd', $script:INV)
        $m = "---`r`ntarih: $Tarih`r`ntags: [calisma-takip]`r`nsure: 0`r`n---`r`n`r`n# $($g.ToString('d MMMM yyyy — dddd', $script:TR))`r`n`r`n## $Baslik`r`n`r`n$blok`r`n"
    }
    [IO.File]::WriteAllText($yol, $m, (New-Object Text.UTF8Encoding $false))
    return 'yazildi'
}
function Takip-Brifing { param([switch]$Kaydet)
    $simdi = Get-Date
    $dunT = $simdi.Date.AddDays(-1).ToString('yyyy-MM-dd')
    $dur = Takip-Durum; $s = $dur.saglik
    $dun = Takip-Rapor -Tarih $dunT
    # Resmi sayac gecmis.json'dadir (hedef ve seri buna gore); rapor yalnizca ayrinti icin
    $gk = Tk-JsonDizi (Join-Path $script:H 'gecmis.json') | Where-Object { $_.tarih -eq $dunT } | Select-Object -First 1
    $dunDk = $null
    if ($gk) { $dunDk = [int]$gk.dakika } elseif ($dun.var) { $dunDk = [int]$dun.calismaDk }
    $bek = @(); $kisa = @(); if ($dun.var) { $bek = @($dun.bekleyen); $kisa = @($dun.kisaGecilen) }

    $dunL = New-Object 'System.Collections.Generic.List[string]'
    if ($null -ne $dunDk) {
        $isaret = '❌'; if ($dunDk -ge $dur.hedef) { $isaret = '✅' }
        $dunL.Add("**Dün: $dunDk / $($dur.hedef) dk $isaret**")
        if ($dun.var) {
            if (Tk-Say $dun.yasakli) { $dunL.Add("- Yasaklı: $(Tk-Liste $dun.yasakli)") }
            if (Tk-Say $dun.calisma) { $dunL.Add("- Çalışma: $(Tk-Liste $dun.calisma)") }
            if (Tk-Say $dun.tarayici.alanlar) { $dunL.Add("- Tarayıcı: $($dun.tarayici.alanlar -join ' · ')") }
        }
    } else { $dunL.Add('**Dün:** kayıt yok') }
    $L = New-Object 'System.Collections.Generic.List[string]'
    $L.Add("**☀️ Günlük çalışma özeti — $($simdi.ToString('d MMMM dddd', $script:TR))**"); $L.Add('')
    foreach ($x in $dunL) { $L.Add($x) }
    $L.Add('')
    $L.Add("**Bugün:** $($dur.dakika) / $($dur.hedef) dk · seri $($dur.seri) gün · erteleme hakkı $($dur.ertelemeHakki)/$($script:ERTELEME_HAKKI)")
    if ($s.durum -eq 'normal') { $L.Add('**Takip:** normal') } else { $L.Add("**Takip:** ⚠️ SORUN — $($s.sorunlar -join '; ')") }
    if ($s.duraklatma) { $L.Add("**Duraklatma:** $($s.duraklatma)") }
    if ($bek.Count) {
        $L.Add('**Sorulacak** (çalışma / yasaklı / belirsiz?):')
        foreach ($b in $bek) {
            if ($b.tur -eq 'alanadi') { $L.Add("- ``$($b.ad)`` — $($b.ziyaret) ziyaret") }
            else { $L.Add("- ``$($b.ad)`` — $($b.dk) dk (`"$($b.ornek)`")") }
        }
    }
    if ($kisa.Count) { $L.Add("**Kısa kaldı, sorulmadı:** $($kisa -join ', ')") }
    $kayit = [ordered]@{}
    if ($Kaydet) {
        $kayit.bugun = Tk-GunlukBlok -Tarih $dur.tarih -Ad 'sabah' -Baslik 'Sabah kontrolü' -Icerik (($L | Select-Object -Skip 2) -join "`r`n")
        if ($null -ne $dunDk) { $kayit.dun = Tk-GunlukBlok -Tarih $dunT -Ad 'gun-sonu' -Baslik 'Gün sonu' -Icerik ($dunL -join "`r`n") }
    }
    return [ordered]@{
        tarih = $dur.tarih
        # Rapor burada tasinmaz (brifingi sisirir); ayrinti icin gun_raporu / 'rapor' komutu
        dun = [ordered]@{ tarih = $dunT; dakika = $dunDk; hedefTuttu = ($null -ne $dunDk -and $dunDk -ge $dur.hedef) }
        bugun = [ordered]@{ dakika = $dur.dakika; hedef = $dur.hedef; seri = $dur.seri; ertelemeHakki = $dur.ertelemeHakki; son7GunDk = $dur.son7GunDk }
        saglik = $s; bekleyenSorular = $bek; gunluk = $kayit; metin = ($L -join "`n")
    }
}

# ---------- siniflandir ----------
function Takip-Siniflandir { param([string]$Oge, [string]$Karar, [string]$Tur = 'surec')
    if ([string]::IsNullOrWhiteSpace($Oge)) { throw 'oge bos olamaz' }
    if (@('calisma', 'yasakli', 'belirsiz') -notcontains $Karar) { throw 'karar calisma, yasakli veya belirsiz olmali' }
    if (@('surec', 'baslik', 'alanadi') -notcontains $Tur) { throw 'tur surec, baslik veya alanadi olmali' }
    $yol = Join-Path $script:H 'kurallar.json'
    $k = Get-Content $yol -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    if (-not $k) { throw 'kurallar.json okunamadi' }
    # once her listeden cikar (karar degisebilir), sonra hedefe ekle
    foreach ($grup in @('calisma', 'yasakli')) { $k.$grup.$Tur = @(@($k.$grup.$Tur) | Where-Object { $_ -and $_ -ne $Oge }) }
    $bb = @(); if ($k.PSObject.Properties['bilerekBelirsiz']) { $bb = @(@($k.bilerekBelirsiz) | Where-Object { $_ -and $_ -ne $Oge }) }
    if ($Karar -eq 'belirsiz') { $bb += $Oge } else { $k.$Karar.$Tur = @($k.$Karar.$Tur) + $Oge }
    if ($k.PSObject.Properties['bilerekBelirsiz']) { $k.bilerekBelirsiz = $bb } else { $k | Add-Member -NotePropertyName bilerekBelirsiz -NotePropertyValue $bb }
    $json = ConvertTo-Json -InputObject $k -Depth 6
    $null = ConvertFrom-Json $json -ErrorAction Stop   # yazmadan once dogrula
    Copy-Item $yol "$yol.bak" -Force
    $gecici = "$yol.yeni"
    [IO.File]::WriteAllText($gecici, $json, (New-Object Text.UTF8Encoding $true))
    # izleyici o an okuyorsa tasima kisa sure takilabilir -- birkac kez dene
    $tamam = $false
    for ($i = 0; $i -lt 5 -and -not $tamam; $i++) { try { Move-Item $gecici $yol -Force -ErrorAction Stop; $tamam = $true } catch { Start-Sleep -Milliseconds 200 } }
    if (-not $tamam) { throw 'kurallar.json yazilamadi (dosya kilitli)' }
    Add-Content (Join-Path $script:H 'log.txt') "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))  kural (api): $Tur '$Oge' -> $Karar" -Encoding UTF8
    # Merkeze bagliysa karar diger cihazlara da gitsin (gonderici kuyrugu bosaltir)
    $senkronPs = Join-Path $script:H 'kural-senkron.ps1'
    if ((Test-Path $senkronPs) -and (Test-Path (Join-Path $script:H 'merkez.json'))) {
        try { . $senkronPs; [void](Add-KuralKuyruk -Klasor $script:H -Oge $Oge -Tur $Tur -Karar $Karar) } catch { }
    }
    return [ordered]@{ tamam = $true; oge = $Oge; tur = $Tur; karar = $Karar; not = 'izleyici 60 sn icinde yeni kurali alir; gecmis kayitlar degismez' }
}

# ---------- komut satiri (nokta-kaynak yuklemede calismaz) ----------
if ($MyInvocation.InvocationName -ne '.') {
    $sonuc = $null; $kod = 0
    try {
        switch ($Komut) {
            'durum'       { $sonuc = Takip-Durum }
            'brifing'     { $sonuc = Takip-Brifing -Kaydet:$Kaydet }
            'rapor'       { $sonuc = Takip-Rapor -Tarih $Tarih }
            'siniflandir' { $sonuc = Takip-Siniflandir -Oge $Oge -Karar $Karar -Tur $Tur }
            default       { throw "bilinmeyen komut: $Komut (durum, brifing, rapor, siniflandir)" }
        }
    } catch { $sonuc = [ordered]@{ hata = $_.Exception.Message }; $kod = 1 }
    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false
    [Console]::Out.Write((ConvertTo-Json -InputObject $sonuc -Depth 8 -Compress))
    exit $kod
}
