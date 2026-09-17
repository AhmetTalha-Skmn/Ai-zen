$bakimIsareti = Join-Path $PSScriptRoot 'GERI-YUKLEME'; if (Test-Path -LiteralPath $bakimIsareti) { try { [IO.File]::Open($bakimIsareti, 'Open', 'ReadWrite', 'None').Dispose(); [IO.File]::Delete($bakimIsareti) } catch { exit 0 } }
# ============================================================
#  Aizen (Çalışma Takip Sistemi)
#  5 dakikada bir olcer, aktivite loglar; hatirlatmalar aciksa 45 dakikada bir uyarir
#  (kurulum turu ve ayarlar: ozellikler.ps1)
# ============================================================
$ErrorActionPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class W32 {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern int GetWindowThreadProcessId(IntPtr h, out int pid);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, System.Text.StringBuilder s, int n);
  [StructLayout(LayoutKind.Sequential)] public struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
  [DllImport("user32.dll")] public static extern bool GetLastInputInfo(ref LASTINPUTINFO p);
  [DllImport("kernel32.dll")] public static extern uint GetTickCount();
}
"@
try { Add-Type -AssemblyName UIAutomationClient -ErrorAction Stop } catch { }

# ---------- yollar (klasor tasinsa da calisir) ----------
$hDir   = $PSScriptRoot
if (-not $hDir) { $hDir = Split-Path $MyInvocation.MyCommand.Path -Parent }
$klasor = Split-Path $hDir -Parent

# --- tek ornek kilidi (kasa yoluna ozel) ---
$md5x = [System.Security.Cryptography.MD5]::Create()
$izx  = [BitConverter]::ToString($md5x.ComputeHash([Text.Encoding]::UTF8.GetBytes($klasor.ToLower()))).Replace('-','').Substring(0,12)
$yenix = $false
$mtxT = New-Object System.Threading.Mutex($true, "Local\CalismaTakip_$izx", [ref]$yenix)
if (-not $yenix) { exit }

$durumD  = Join-Path $hDir 'durum.json'
$gecmisD = Join-Path $hDir 'gecmis.json'
$ayarD   = Join-Path $hDir 'ayarlar.json'
$logD    = Join-Path $hDir 'log.txt'
$aktDir  = Join-Path $hDir 'aktivite'
$kayitMd = Join-Path $klasor 'Calisma Kaydi.md'
$aktMd   = Join-Path $klasor 'Aktivite Gunlugu.md'

# Takipcinin KENDI urettigi dosyalar -- tazelik taramasindan haric tutulmali
$URETILEN = @('Calisma Kaydi.md', 'Aktivite Gunlugu.md')

# ---------- sabitler ----------
$HEDEF        = 240
$TICK         = 5
$UYARI_ARALIK = 45
$AFK_SINIR    = 5
$ERTELEME_DK  = 30
$MAX_ERTELEME = 3
$TAZELIK_DK   = $TICK + 2
$DIYALOG_SN   = 240
# Yedek liste -- kurallar.json okunamazsa kullanilir
$IZINLI = @('Obsidian','Claude','Code','VSCodium','WindowsTerminal','phpstorm64','sublime_text','devenv','notepad++')

$simdi = Get-Date
$bugun = $simdi.ToString('yyyy-MM-dd')
$INV   = [Globalization.CultureInfo]::InvariantCulture
$TARAYICILAR = @('brave','chrome','msedge','firefox','opera')

function Log { param($m)
    $satir = "$($simdi.ToString('yyyy-MM-dd HH:mm:ss'))  $m"
    # Dosya kilitliyse satir SESSIZCE kaybolmasin -- 5 kez dene
    $yazildi = $false
    for ($dn = 0; $dn -lt 5; $dn++) {
        try {
            [System.IO.File]::AppendAllText($logD, $satir + [Environment]::NewLine, [Text.Encoding]::UTF8)
            $yazildi = $true; break
        } catch { Start-Sleep -Milliseconds 120 }
    }
    $l = @(Get-Content $logD -Encoding UTF8)
    if ($l.Count -gt 800) { $l[-500..-1] | Out-File -FilePath $logD -Encoding utf8 }
}
# Kultur bagimsiz tarih okuma (tr-TR'de [datetime]::Parse patlayabiliyor)
function TarihOku { param($x)
    if ([string]::IsNullOrWhiteSpace($x)) { return $null }
    try { return [datetime]::ParseExact($x, 's', $INV) } catch { }
    try { return [datetime]::Parse($x, $INV) } catch { }
    return $null
}

# Izleyici kapaliysa yedek karar ayni alan-adi bilgisini kullanir.
function TarayiciAlanAdiT { param([IntPtr]$pencere, [string]$surec)
    if ([string]::IsNullOrWhiteSpace($surec) -or $TARAYICILAR -notcontains $surec.ToLowerInvariant()) { return '' }
    if (-not ('System.Windows.Automation.AutomationElement' -as [type])) { return '' }
    try {
        $kok = [System.Windows.Automation.AutomationElement]::FromHandle($pencere)
        if (-not $kok) { return '' }
        $kosul = [System.Windows.Automation.PropertyCondition]::new(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::Edit)
        foreach ($edit in $kok.FindAll([System.Windows.Automation.TreeScope]::Descendants, $kosul)) {
            $deger = ''
            try { $deger = $edit.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value } catch { }
            if (-not [regex]::IsMatch($deger, '^(?:https?://)?(?:[A-Za-z0-9-]+\.)+[A-Za-z]{2,}(?:[/:?#]|$)', 'IgnoreCase, CultureInvariant')) { continue }
            if ($deger -notmatch '^https?://') { $deger = "https://$deger" }
            try {
                $alan = ([uri]$deger).Host.TrimEnd('.').ToLowerInvariant()
                if ($alan -like 'www.*') { $alan = $alan.Substring(4) }
                if ($alan) { return $alan }
            } catch { }
        }
    } catch { }
    return ''
}

# PS 5.1 tuzagi: "Get-Content | ConvertFrom-Json" bir JSON dizisini pipeline'a TEK nesne
# olarak yazar; @() ile sarinca butun kayitlar tek elemana coker.
# Cozum: once degiskene ata, sonra sar.
function JsonDiziOku { param($yol)
    if (-not (Test-Path $yol)) { return @() }
    $ham = Get-Content $yol -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($ham)) { return @() }
    $o = $null
    try { $o = ConvertFrom-Json $ham } catch { return @() }
    if ($null -eq $o) { return @() }
    return @($o) }

# ---------- ayarlar / duraklatma ----------
$duraklat = ''
if (Test-Path $ayarD) {
    $a = Get-Content $ayarD -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($a) {
        if ($a.hedef) { $HEDEF = [int]$a.hedef }
        $duraklat = [string]$a.duraklat
    }
}
if ($duraklat -ne '') {
    if ($duraklat -eq 'sonsuz') { Log 'DURAKLATILDI (suresiz)'; exit }
    $db = TarihOku $duraklat
    if ($db -and $simdi -lt $db) { Log "DURAKLATILDI (bitis $duraklat)"; exit }
}

# ---------- kurulum turu / ozellikler ----------
# Hatirlatmalar kapaliysa (sirket kurulumu ya da Ayarlar) olcum surer ama 45 dk uyarisi ve hedef mesaji cikmaz.
# Ekran kilidi kapaliysa uyari tam ekran degil, kapatilabilir normal bir penceredir.
# ozellikler.ps1 yoksa ya da okunamazsa eski davranis: ikisi de acik.
$HATIRLATMA = $true; $EKRAN_KILIDI = $true
$ozPs = Join-Path $hDir 'ozellikler.ps1'
if (Test-Path $ozPs) {
    . $ozPs
    $oz = Get-TakipOzellikleri -HatirlaticiKlasoru $hDir
    if ($oz) { $HATIRLATMA = [bool]$oz.hatirlatmalar; $EKRAN_KILIDI = [bool]$oz.ekranKilidi }
}

# ---------- durum ----------
# dakika = yalnizca bu makinenin olcumu (resmi yerel sayac)
# toplam = bu makine + merkeze bagli diger cihazlar (ortak sayac)
$d = [ordered]@{ tarih=$bugun; dakika=0; toplam=0; uyari=0; sonUyari=''; erteleme=''; ertSayi=0; vazgecti=$false; kutlandi=$false }
if (Test-Path $durumD) {
    $j = Get-Content $durumD -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($j) {
        if ($j.tarih -eq $bugun) {
            $d.dakika=[int]$j.dakika; $d.uyari=[int]$j.uyari; $d.sonUyari=[string]$j.sonUyari
            $d.erteleme=[string]$j.erteleme; $d.ertSayi=[int]$j.ertSayi
            $d.vazgecti=[bool]$j.vazgecti; $d.kutlandi=[bool]$j.kutlandi
        } else {
            $g = @()
            $g = @(JsonDiziOku $gecmisD)
            if (-not ($g | Where-Object { $_.tarih -eq $j.tarih })) {
                # Basari o gunun TOPLAM dakikasina gore: kullanici baska bir
                # bilgisayarda calistiysa bu makinenin sayaci tek basina eksik kalir.
                $arsivDk = [int]$j.dakika
                $arsivToplam = $arsivDk
                if ($j.PSObject.Properties['toplam'] -and [int]$j.toplam -gt $arsivDk) { $arsivToplam = [int]$j.toplam }
                $g += [pscustomobject]@{ tarih=$j.tarih; dakika=$arsivDk; toplam=$arsivToplam; hedef=$HEDEF; basarili=($arsivToplam -ge $HEDEF) }
                ConvertTo-Json -InputObject @($g) -Depth 4 | Out-File $gecmisD -Encoding utf8
                Log "yeni gun -- $($j.tarih) arsivlendi ($($j.dakika) dk)"
            }
        }
    }
}
function Kaydet { $d | ConvertTo-Json | Out-File -FilePath $durumD -Encoding utf8 }

# ---------- aktif mi ----------
$li = New-Object W32+LASTINPUTINFO
$li.cbSize = [uint32][System.Runtime.InteropServices.Marshal]::SizeOf($li)
[void][W32]::GetLastInputInfo([ref]$li)
# GetLastInputInfo ve GetTickCount ayni 32-bit zaman tabanini kullanir.
# Unsigned fark, TickCount isaret/sarma noktasinda AFK suresini korur.
$simdiTick = [uint32][W32]::GetTickCount()
$sonGirdiTick = [uint32]$li.dwTime
[uint64]$bosMs = 0
if ($simdiTick -ge $sonGirdiTick) { $bosMs = [uint64]$simdiTick - [uint64]$sonGirdiTick }
else { $bosMs = 4294967296L + [uint64]$simdiTick - [uint64]$sonGirdiTick }
$bosDk = [math]::Round($bosMs / 60000, 1)

$hw = [W32]::GetForegroundWindow()
$fpid = 0
$onPlan = '(bilinmiyor)'
$basl = ''
if ($hw -ne [IntPtr]::Zero) {
    [void][W32]::GetWindowThreadProcessId($hw, [ref]$fpid)
    if ($fpid -gt 0) {
        $pr = Get-Process -Id $fpid -ErrorAction SilentlyContinue
        if ($pr) { $onPlan = $pr.ProcessName }
    }
    $sbT = New-Object System.Text.StringBuilder 300
    [void][W32]::GetWindowText($hw, $sbT, 300)
    $basl = $sbT.ToString()
}
if ($basl.Length -gt 70) { $basl = $basl.Substring(0,70) }
$basl = ($basl -replace ';', ',') -replace "`r|`n", ' '
$alan = TarayiciAlanAdiT -pencere $hw -surec $onPlan

# DUZELTME: takipcinin kendi urettigi .md dosyalari haric
$tazeYazim = $false
$esik = $simdi.AddMinutes(-$TAZELIK_DK)
Get-ChildItem -Path $klasor -Filter *.md -Recurse |
    Where-Object {
        $_.DirectoryName -notlike '*hatirlatici*' -and
        $_.DirectoryName -notlike '*hafiza*' -and
        $URETILEN -notcontains $_.Name
    } | ForEach-Object { if ($_.LastWriteTime -gt $esik) { $tazeYazim = $true } }

# Izleyici olu ise yedek karar: kurallar.json'u kullan (sabit listeye dusme)
$KT = $null
$kuralYol = Join-Path $hDir 'kurallar.json'
if (Test-Path $kuralYol) { try { $KT = Get-Content $kuralYol -Raw -Encoding UTF8 | ConvertFrom-Json } catch { } }
function EslesirMiT { param($m,$l) if ([string]::IsNullOrWhiteSpace($m)) { return $false }
    foreach ($x in $l) { if ($x -and $m -like "*$x*") { return $true } }; return $false }
if ($KT) {
    $izinliMi = (EslesirMiT $onPlan $KT.calisma.surec)
    $yasakMi  = (EslesirMiT $onPlan $KT.yasakli.surec) -or (EslesirMiT $basl $KT.yasakli.baslik) -or (EslesirMiT $alan $KT.yasakli.alanadi)
    $basIzin  = (EslesirMiT $basl $KT.calisma.baslik) -or (EslesirMiT $alan $KT.calisma.alanadi)
    if ($basIzin)      { $aktif = ($bosDk -lt $AFK_SINIR) }
    elseif ($yasakMi)  { $aktif = $false }
    else               { $aktif = ($bosDk -lt $AFK_SINIR) -and ($tazeYazim -or $izinliMi) }
} else {
    $aktif = ($bosDk -lt $AFK_SINIR) -and ($tazeYazim -or ($IZINLI -contains $onPlan))
}

# ---------- izleyici servisi ayakta mi ----------
$izPs  = Join-Path $hDir 'izleyici.ps1'
$izPidD = Join-Path $hDir 'izleyici.pid'
$izCalisiyor = $false
if (Test-Path $izPidD) {
    $izPid = 0
    [void][int]::TryParse((Get-Content $izPidD -Encoding UTF8 | Select-Object -First 1), [ref]$izPid)
    if ($izPid -gt 0 -and (Get-Process -Id $izPid -ErrorAction SilentlyContinue)) { $izCalisiyor = $true }
}
if (-not $izCalisiyor -and (Test-Path $izPs)) {
    $vbsYol = Join-Path $hDir 'gizli.vbs'
    Start-Process -FilePath "$env:SystemRoot\System32\wscript.exe" -ArgumentList "//B //Nologo `"$vbsYol`" `"$izPs`"" -WindowStyle Hidden
    Log 'izleyici servisi CALISMIYORDU -> yeniden baslatildi'
}

# ---------- gunluk dakika: izleyicinin gercek olcumlerinden ----------
if (-not (Test-Path $aktDir)) { New-Item -ItemType Directory -Path $aktDir -Force | Out-Null }
$aktCsv = Join-Path $aktDir "$bugun.csv"
$ornekler = @()
if (Test-Path $aktCsv) { $ornekler = @(Import-Csv $aktCsv -Delimiter ';' -Encoding UTF8) }
$calSn = 0
foreach ($o in $ornekler) { if ($o.kategori -eq 'calisma') { $calSn += [int]$o.sure } }
$d.dakika = [math]::Round($calSn / 60)

# Ortak sayac: kullanici birden fazla bilgisayarda calisiyorsa hedef, uyari ve
# seri TOPLAM uzerinden isler. Merkez yoksa ya da veri bayatsa diger = 0 olur ve
# davranis tek cihazdakiyle aynidir.
$digerDk = 0
$ortakPs = Join-Path $hDir 'ortak-sayac.ps1'
if (Test-Path $ortakPs) {
    . $ortakPs
    $digerDk = [int](Get-OrtakSayac -Klasor $hDir).digerCihazDk
}
$toplamDk = $d.dakika + $digerDk
$d.toplam = $toplamDk

# Aktiflik karari: izleyicinin son ornegi 90 sn'den yeniyse ONU esas al
# (tek kaynak ilkesi -- takip.ps1 ikinci bir karar vermesin)
$ornekKaynak = 'kendi'
if ($ornekler.Count -gt 0) {
    $so = $ornekler[-1]
    $ot = $null
    try { $ot = [datetime]::ParseExact("$bugun $($so.zaman)", 'yyyy-MM-dd HH:mm:ss', $INV) } catch { }
    if ($ot -and ([math]::Abs(($simdi - $ot).TotalSeconds) -le 90)) {
        $aktif = ($so.kategori -eq 'calisma')
        $ornekKaynak = 'izleyici'
    }
}
if ($aktif) { $d.uyari = 0; $d.erteleme = '' }
Log "tick aktif=$aktif($ornekKaynak) bos=$bosDk onplan=$onPlan taze=$tazeYazim izleyici=$izCalisiyor toplam=$toplamDk/$HEDEF (yerel $($d.dakika) + diger $digerDk)"

# ---------- seri (DUZELTME: bugun tamamlanmadiysa gecmis seriyi sifirlamaz) ----------
$gec = @()
$gec = @(JsonDiziOku $gecmisD)
$seri = 0
for ($i = $gec.Count - 1; $i -ge 0; $i--) { if ($gec[$i].basarili) { $seri++ } else { break } }
if ($toplamDk -ge $HEDEF) { $seri++ }

$dolu  = [math]::Min([math]::Floor($toplamDk / $HEDEF * 20), 20)
$bar   = ('#' * $dolu) + ('.' * (20 - $dolu))
$yuzde = [math]::Round($toplamDk / $HEDEF * 100)

# ---------- Calisma Kaydi.md ----------
$hafta = 0; $sayac7 = 0
for ($i = $gec.Count - 1; $i -ge 0 -and $sayac7 -lt 6; $i--) { $hafta += [int]$gec[$i].dakika; $sayac7++ }
$hafta += $d.dakika
$tumDk = ($gec | Measure-Object -Property dakika -Sum).Sum + $d.dakika
$ort = 0; if (($gec.Count + 1) -gt 0) { $ort = [math]::Round($tumDk / ($gec.Count + 1)) }

$s = @('---','tags: [takip, sayac]','---','','# Calisma Kaydi','',
       '> [!abstract] Otomatik','> Bu dosyayi takipci yaziyor, elle duzenleme. 5 dakikada bir guncellenir.','',
       "## Bugun -- $bugun",'','```',"[$bar] %$yuzde",
       "$toplamDk / $HEDEF dakika    ($([math]::Round($toplamDk/60,1)) / $([math]::Round($HEDEF/60,1)) saat)",'```','')
if ($digerDk -gt 0) { $s += @("> [!info] Bu bilgisayar $($d.dakika) dk, diger cihazlar $digerDk dk.", '') }
if ($toplamDk -ge $HEDEF) { $s += '> [!success] Gunluk hedef tamamlandi.' }
elseif ($d.vazgecti)      { $s += '> [!failure] Bugun vazgecildi. Kayda basarisiz gecti.' }
else                      { $s += "> [!warning] $($HEDEF - $toplamDk) dakika kaldi." }
$s += @('','| | |','|---|---:|',
        "| Seri | $seri gun |",
        "| Son 7 gun | $hafta dk ($([math]::Round($hafta/60,1)) saat) |",
        "| Gunluk ortalama | $ort dk |",
        "| Erteleme hakki | $($MAX_ERTELEME - $d.ertSayi) / $MAX_ERTELEME |",
        '','## Gecmis','','| Tarih | Dakika | Saat | Hedef | Durum |','|---|---:|---:|---:|---|')
$tumu = @($gec) + @([pscustomobject]@{ tarih=$bugun; dakika=$toplamDk; hedef=$HEDEF; basarili=($toplamDk -ge $HEDEF) })
for ($i = $tumu.Count - 1; $i -ge 0; $i--) {
    $r = $tumu[$i]; $ds = 'X'; if ($r.basarili) { $ds = 'OK' }
    $s += "| $($r.tarih) | $($r.dakika) | $([math]::Round($r.dakika/60,1)) | $($r.hedef) | $ds |"
}
$s += @('',"**Program toplami:** $tumDk dakika ($([math]::Round($tumDk/60,1)) saat) / 180 saat")
$s -join "`r`n" | Out-File -FilePath $kayitMd -Encoding utf8

# ---------- Aktivite Gunlugu.md ----------
$rw = $ornekler
$topSn = 0; foreach ($o in $rw) { $topSn += [int]$o.sure }
$kayitDk = [math]::Round($topSn / 60)

function SnTopla { param($liste) $t = 0; foreach ($x in $liste) { $t += [int]$x.sure }; return $t }
function DkYaz { param($sn)
    $m = [math]::Round($sn / 60)
    if ($m -ge 60) { return "$([math]::Floor($m/60))s $($m%60)dk" }
    return "$m dk" }

$v = @('---','tags: [takip, aktivite]','---','','# Aktivite Gunlugu','',
       '> [!abstract] Otomatik',"> Arka plan servisi **10 saniyede bir** on plandaki uygulamayi kaydeder. Duraklatma sirasinda kayit durur.",
       '',"## Bugun -- $bugun",'',"Kayit altindaki sure: **$(DkYaz $topSn)**",'',
       '### Kategori dagilimi','','| Kategori | Sure | Oran |','|---|---:|---:|')
foreach ($k in @('calisma','diger','bosta')) {
    $sn = SnTopla @($rw | Where-Object { $_.kategori -eq $k })
    $o = 0; if ($topSn -gt 0) { $o = [math]::Round($sn / $topSn * 100) }
    $ad = @{ calisma='Calisma'; diger='Diger'; bosta='Bosta (AFK)' }[$k]
    $v += "| $ad | $(DkYaz $sn) | %$o |"
}

$v += @('','### Uygulamalar','','| Uygulama | Sure | Oran | Kategori (kaynak) | |','|---|---:|---:|---|---|')
$uygGrup = @()
foreach ($g in ($rw | Group-Object uygulama)) {
    $bask = ($g.Group | Group-Object kategori | Sort-Object Count -Descending | Select-Object -First 1).Name
    $kayn = ($g.Group | Group-Object kaynak    | Sort-Object Count -Descending | Select-Object -First 1).Name
    if (-not $kayn) { $kayn = '-' }
    $uygGrup += [pscustomobject]@{ ad=$g.Name; sn=(SnTopla $g.Group); kat=$bask; kaynak=$kayn }
}
foreach ($u in ($uygGrup | Sort-Object sn -Descending | Select-Object -First 20)) {
    $o = 0; if ($topSn -gt 0) { $o = [math]::Round($u.sn / $topSn * 100) }
    $bl = [math]::Max([math]::Round($o / 5), 1)
    $v += "| $($u.ad) | $(DkYaz $u.sn) | %$o | $($u.kat) ($($u.kaynak)) | $('#' * $bl) |"
}

# --- GUNLUK INCELEME: kural listelerinde olmayan uygulamalar ---
$bel = @($uygGrup | Where-Object { $_.kaynak -eq 'belirsiz' } | Sort-Object sn -Descending)
$v += @('','### Siniflandirilmamis uygulamalar','')
if ($bel.Count -eq 0) {
    $v += 'Bugun kural listelerinde olmayan uygulama gorulmedi.'
} else {
    $v += 'Hicbir listede yok. Supheden faydalanip **calisma sayildilar** -- Claude ile gozden gecir:'
    $v += ''
    $v += '| Uygulama | Sure | Ornek baslik |'
    $v += '|---|---:|---|'
    foreach ($u in ($bel | Select-Object -First 15)) {
        $ob = ($rw | Where-Object { $_.uygulama -eq $u.ad -and $_.baslik -ne '' } | Select-Object -First 1).baslik
        if (-not $ob) { $ob = '-' }
        $v += "| $($u.ad) | $(DkYaz $u.sn) | $ob |"
    }
}

$v += @('','### Neye ne kadar baktin (pencere basligi)','','| Uygulama | Baslik | Sure |','|---|---|---:|')
$basGrup = @()
foreach ($g in ($rw | Where-Object { $_.baslik -ne '' } | Group-Object { "$($_.uygulama)|$($_.baslik)" })) {
    $par = $g.Name -split '\|', 2
    $basGrup += [pscustomobject]@{ uyg=$par[0]; bas=$par[1]; sn=(SnTopla $g.Group) }
}
foreach ($b in ($basGrup | Sort-Object sn -Descending | Select-Object -First 25)) {
    if ($b.sn -ge 60) { $v += "| $($b.uyg) | $($b.bas) | $(DkYaz $b.sn) |" }
}

$v += @('','### Saatlik dagilim','','`#` calisma  `-` diger  `.` bosta  -- her karakter ~5 dakika','','```')
foreach ($h in ($rw | Group-Object { $_.zaman.Substring(0,2) } | Sort-Object Name)) {
    $c1 = SnTopla @($h.Group | Where-Object { $_.kategori -eq 'calisma' })
    $c2 = SnTopla @($h.Group | Where-Object { $_.kategori -eq 'diger' })
    $c3 = SnTopla @($h.Group | Where-Object { $_.kategori -eq 'bosta' })
    function Blok { param($sn) if ($sn -le 0) { return 0 }; return [math]::Max([math]::Ceiling($sn/300), 1) }
    $cz = ('#' * (Blok $c1)) + ('-' * (Blok $c2)) + ('.' * (Blok $c3))
    $v += ("{0}:00  {1,-13} calisma {2,-9} diger {3}" -f $h.Name, $cz, (DkYaz $c1), (DkYaz $c2))
}
$v += '```'

$v += @('','## Gecmis gunler','','| Tarih | Kayit | Calisma | Diger | Bosta |','|---|---:|---:|---:|---:|')
foreach ($cf in @(Get-ChildItem $aktDir -Filter '*.csv' | Sort-Object Name -Descending | Select-Object -First 30)) {
    $rr = @(Import-Csv $cf.FullName -Delimiter ';' -Encoding UTF8)
    $v += "| $($cf.BaseName) | $(DkYaz (SnTopla $rr)) | $(DkYaz (SnTopla @($rr | Where-Object { $_.kategori -eq 'calisma' }))) | $(DkYaz (SnTopla @($rr | Where-Object { $_.kategori -eq 'diger' }))) | $(DkYaz (SnTopla @($rr | Where-Object { $_.kategori -eq 'bosta' }))) |"
}
$v += @('','> [!note] Ham veri','> `hatirlatici/aktivite/YYYY-MM-DD.csv` -- zaman;uygulama;baslik;bosta;kategori;sure (10 sn araliklarla)')
$v -join "`r`n" | Out-File -FilePath $aktMd -Encoding utf8
# ---------- hedef tamam ----------
if ($toplamDk -ge $HEDEF) {
    if (-not $d.kutlandi) {
        $d.kutlandi = $true; Kaydet
        Log "HEDEF TAMAMLANDI ($toplamDk dk, seri $seri)"
        if ($HATIRLATMA) {
            [System.Windows.Forms.MessageBox]::Show("Gunluk hedef tamam: $toplamDk dakika.`r`nSeri: $seri gun.",'Hedef tamamlandi','OK',[System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        }
    }
    Kaydet; exit
}
Kaydet
if (-not $HATIRLATMA) { exit }
if ($aktif)      { exit }
if ($d.vazgecti) { exit }
$eb = TarihOku $d.erteleme
if ($eb -and $simdi -lt $eb) { exit }
$sb2 = TarihOku $d.sonUyari
if ($sb2 -and $simdi -lt $sb2.AddMinutes($UYARI_ARALIK)) { exit }

# ---------- uyari ----------
# Takip sistemi bir müfredat ya da proje dosyasına bağlı değildir.
$siradaki = 'Çalışma oturumuna dön'
$d.uyari = $d.uyari + 1
switch ($d.uyari) {
    1 { $b='Bugün henüz başlamadın.';               $c=[System.Drawing.ColorTranslator]::FromHtml('#2563EB') }
    2 { $b='İkinci uyarı. 45 dakika daha geçti.';   $c=[System.Drawing.ColorTranslator]::FromHtml('#D97706') }
    3 { $b='Üçüncü uyarı. Hâlâ sıfırdasın.';        $c=[System.Drawing.ColorTranslator]::FromHtml('#EA580C') }
    4 { $b='Dördüncü uyarı. Bu iş böyle yürümez.';  $c=[System.Drawing.ColorTranslator]::FromHtml('#DC2626') }
    default { $b="$($d.uyari). uyarı. Gün bitiyor, hedef duruyor."; $c=[System.Drawing.ColorTranslator]::FromHtml('#B91C1C') }
}
Log "UYARI #$($d.uyari) gosteriliyor (onplan=$onPlan)"

# ---------- UYARI PENCERESI ----------
# Ekran kilidi ACIK (bireysel varsayilani) -> tam ekran engelleyici:
#   Kenarliksiz  -> baslik cubugu yok, surukleyip kenara atilamaz
#   FormClosing  -> Alt+F4 ile kapanmaz
#   1 sn'lik timer -> Alt+Tab ile arkaya atilirsa one geri doner
#   Cikis yolu SADECE uc dugmeden biri
# Ekran kilidi KAPALI -> ayni kart normal pencerede: dugmeler hemen acik, kapatilabilir,
#   one zorlanmaz. Secim yapmadan kapatmak 'Abort' sayilir: bir sonraki uyari 45 dk sonra.
$vs = [System.Windows.Forms.SystemInformation]::VirtualScreen
$script:secildi = $false
$script:elleKapandi = $false
$script:gecenSn = 0
$KILIT_SN   = [math]::Min(5 + 5 * $d.uyari, 30)
if ($env:CALISMATAKIP_TEST_SN) { $KILIT_SN = 1 }
if (-not $EKRAN_KILIDI) { $KILIT_SN = 0 }
$GUVENLIK_DK = 15
$GUVENLIK_SN = $GUVENLIK_DK * 60
# Test modu: pencere kendi kapansin, ekranda asili kalmasin
if ($env:CALISMATAKIP_TEST_SN) { $ts = 0; if ([int]::TryParse($env:CALISMATAKIP_TEST_SN, [ref]$ts) -and $ts -gt 0) { $GUVENLIK_SN = $ts; $KILIT_TEST = $true } }

. (Join-Path $hDir 'tema.ps1')   # gorunum: Tema-TamEkranKart (engel ekrani ve panelle ortak)
$kalanErt = $MAX_ERTELEME - $d.ertSayi
$ertMetin = "$ERTELEME_DK dk ertele ($kalanErt hak)"; if ($kalanErt -le 0) { $ertMetin = 'Erteleme hakkın bitti' }
$bugunMetin = "$toplamDk / $HEDEF dk  ·  %$yuzde"
if ($digerDk -gt 0) { $bugunMetin = "$toplamDk / $HEDEF dk  ·  %$yuzde  ·  bu bilgisayar $($d.dakika) dk" }
$satirlar = @(
    @('Bugün',    $bugunMetin),
    @('Kalan',    "$([math]::Max($HEDEF - $toplamDk, 0)) dk"),
    @('Seri',     "$seri gün"),
    @('Şu an',    "$onPlan"),
    @('Sıradaki', "$siradaki")
)
$u = Tema-TamEkranKart -Alan $vs -Vurgu $c -Baslik $b -Yuzde $yuzde -Satirlar $satirlar `
    -Dugmeler @('Çalışmaya başla', $ertMetin, 'Vazgeçtim') -Turler @('birincil', 'ikincil', 'tehlike') -Pencere:(-not $EKRAN_KILIDI)
$f = $u.Form; $lKilit = $u.Durum
$b1 = $u.Dugmeler[0]; $b2 = $u.Dugmeler[1]; $b3 = $u.Dugmeler[2]
$b1.DialogResult = [System.Windows.Forms.DialogResult]::Yes
$b2.DialogResult = [System.Windows.Forms.DialogResult]::No
$b3.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
if ($EKRAN_KILIDI) {
    $f.Add_FormClosing({ if (-not $script:secildi) { $_.Cancel = $true } })
    $lKilit.Text = "Seçim $KILIT_SN saniye sonra açılacak."
    $b1.Enabled = $false; $b2.Enabled = $false; $b3.Enabled = $false
} else {
    $f.Text = 'Aizen · hatırlatma'
    $f.Add_FormClosing({ if (-not $script:secildi) { $script:elleKapandi = $true } })
    $lKilit.ForeColor = $TEMA.Soluk
    $lKilit.Text = 'Pencereyi kapatabilirsin; bir sonraki hatırlatma 45 dk sonra gelir.'
    if ($kalanErt -le 0) { $b2.Enabled = $false }
}

$b1.Add_Click({ $script:secildi = $true })
$b2.Add_Click({ $script:secildi = $true })
$b3.Add_Click({ $script:secildi = $true })

# 1 sn'lik nobetci: geri sayim + one getirme + guvenlik zaman asimi
$oto = New-Object System.Windows.Forms.Timer
$oto.Interval = 1000
$oto.Add_Tick({
    $script:gecenSn++
    if ($EKRAN_KILIDI) {
        if ($script:gecenSn -lt $KILIT_SN) {
            $lKilit.Text = "Seçim $($KILIT_SN - $script:gecenSn) saniye sonra açılacak."
        } elseif (-not $b1.Enabled) {
            $b1.Enabled = $true
            $b3.Enabled = $true
            if ($kalanErt -gt 0) { $b2.Enabled = $true }
            $lKilit.ForeColor = $TEMA.Soluk
            $lKilit.Text = 'Bu pencere taşınamaz ve kapatılamaz. Üç seçenekten birini seç.'
        }
        # odak kaybedilirse geri al
        $f.TopMost = $true
        if (-not $f.ContainsFocus) { $f.Activate(); [void][W32]::SetForegroundWindow($f.Handle) }
    }
    # guvenlik: cok uzun surerse kapat ama 5 dk sonra geri gel
    if ($script:gecenSn -ge $GUVENLIK_SN) {
        $oto.Stop(); $script:secildi = $true
        $f.DialogResult = [System.Windows.Forms.DialogResult]::Ignore
        $f.Close()
    }
})
$oto.Start()

$f.Add_Shown({
    $f.Activate(); $f.BringToFront()
    [void][W32]::ShowWindow($f.Handle, 9)
    [void][W32]::SetForegroundWindow($f.Handle)
})
$ses = [math]::Min(3 + $d.uyari, 8)
if (-not $EKRAN_KILIDI) { $ses = 1 }
for ($i = 1; $i -le $ses; $i++) { [System.Media.SystemSounds]::Exclamation.Play(); Start-Sleep -Milliseconds 450 }

$sonuc = $f.ShowDialog()
if (-not $script:secildi -and $script:elleKapandi) { $sonuc = 'Abort' }
$oto.Stop()
$d.sonUyari = $simdi.ToString('s')
switch ($sonuc) {
    'Yes' { $d.erteleme=''; Kaydet; Log 'kullanici: calismaya basla'; Start-Process explorer.exe $klasor }
    'No'  { $d.ertSayi=$d.ertSayi+1; $d.erteleme=$simdi.AddMinutes($ERTELEME_DK).ToString('s'); Kaydet; Log "kullanici: $ERTELEME_DK dk ertele (kalan $($MAX_ERTELEME-$d.ertSayi))" }
    'Cancel' {
        $onay=[System.Windows.Forms.MessageBox]::Show("Bugun $toplamDk/$HEDEF dakika yaptin.`r`nVazgecersen bu gun kayda BASARISIZ gecer ve serin sifirlanir.`r`n`r`nEmin misin?",'Emin misin?','YesNo',[System.Windows.Forms.MessageBoxIcon]::Warning)
        if ($onay -eq 'Yes') { $d.vazgecti=$true; Log 'kullanici: VAZGECTI' } else { Log 'kullanici: vazgecmekten vazgecti' }
        Kaydet
    }
    'Abort' { Kaydet; Log 'uyari penceresi kapatildi -- 45 dk sonra tekrar' }
    default {
        $d.sonUyari = $simdi.AddMinutes(-($UYARI_ARALIK - 5)).ToString('s')
        Kaydet; Log 'uyari yanitsiz kapandi -- 5 dk sonra tekrar gelecek'
    }
}



