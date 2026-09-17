$bakimIsareti = Join-Path $PSScriptRoot 'GERI-YUKLEME'; if (Test-Path -LiteralPath $bakimIsareti) { try { [IO.File]::Open($bakimIsareti, 'Open', 'ReadWrite', 'None').Dispose(); [IO.File]::Delete($bakimIsareti) } catch { exit 0 } }
# ============================================================
#  Aktivite Izleyici -- kalici arka plan servisi
#  10 saniyede bir on plandaki uygulamayi ve pencere basligini kaydeder
# ============================================================
$ErrorActionPreference = 'SilentlyContinue'
Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices;
public class IZ {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern int GetWindowThreadProcessId(IntPtr h, out int pid);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [StructLayout(LayoutKind.Sequential)] public struct LII { public uint cbSize; public uint dwTime; }
  [DllImport("user32.dll")] public static extern bool GetLastInputInfo(ref LII p);
  [DllImport("kernel32.dll")] public static extern uint GetTickCount();
}
"@
try { Add-Type -AssemblyName UIAutomationClient -ErrorAction Stop } catch { }

$hDir = $PSScriptRoot
if (-not $hDir) { $hDir = Split-Path $MyInvocation.MyCommand.Path -Parent }
$klasor = Split-Path $hDir -Parent

# --- tek ornek garantisi (kasa yoluna ozel) ---
$md5 = [System.Security.Cryptography.MD5]::Create()
$iz  = [BitConverter]::ToString($md5.ComputeHash([Text.Encoding]::UTF8.GetBytes($klasor.ToLower()))).Replace('-','').Substring(0,12)
$yeni = $false
$mtx = New-Object System.Threading.Mutex($true, "Local\CalismaTakipIzleyici_$iz", [ref]$yeni)
if (-not $yeni) { exit }
$aktDir = Join-Path $hDir 'aktivite'
$ayarD  = Join-Path $hDir 'ayarlar.json'
$izLog  = Join-Path $hDir 'izleyici.log'
$perD   = Join-Path $hDir 'periyot.json'
$engelPs = Join-Path $hDir 'engel.ps1'
$vbsYol = Join-Path $hDir 'gizli.vbs'
$sonEngel = [datetime]::MinValue
$engelGecmisi = @()
$pidD   = Join-Path $hDir 'izleyici.pid'
# Ekran kilidi ayari (kurulum turu + Ayarlar). Dosya yoksa eski davranis: kilit acik.
$ozPs = Join-Path $hDir 'ozellikler.ps1'
$ozellikVar = Test-Path $ozPs
if ($ozellikVar) { . $ozPs }

$ARALIK    = 10        # saniye
$AFK_SINIR = 5         # dakika
$TAZELIK   = 7         # dakika
$kuralD = Join-Path $hDir 'kurallar.json'
$K = $null
if (Test-Path $kuralD) { try { $K = Get-Content $kuralD -Raw -Encoding UTF8 | ConvertFrom-Json } catch { } }
if (-not $K) {
    $K = [pscustomobject]@{
        yasakli  = [pscustomobject]@{ surec=@(); baslik=@() }
        calisma  = [pscustomobject]@{ surec=@('Obsidian','Claude','Code','VSCodium','WindowsTerminal'); baslik=@() }
        belirsizSayilsin = $true }
}
function EslesirMi { param($metin, $liste)
    if ([string]::IsNullOrWhiteSpace($metin)) { return $false }
    foreach ($x in $liste) { if ($x -and $metin -like "*$x*") { return $true } }
    return $false }
$URETILEN = @('Calisma Kaydi.md','Aktivite Gunlugu.md')
$INV = [Globalization.CultureInfo]::InvariantCulture
$TARAYICILAR = @('brave','chrome','msedge','firefox','opera')

# Tarayicinin gorunen adres cubugundan alan adini alir. UI Automation kullanilamazsa
# bos doner; bu durumda baslik/surec kurallari normal sekilde calismaya devam eder.
function TarayiciAlanAdi { param([IntPtr]$pencere, [string]$surec)
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

[void][System.IO.Directory]::CreateDirectory($aktDir)
$PID | Out-File $pidD -Encoding utf8
"$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))  izleyici basladi (pid $PID, aralik ${ARALIK}s)" | Out-File $izLog -Encoding utf8 -Append

function TarihOku { param($x)
    if ([string]::IsNullOrWhiteSpace($x)) { return $null }
    try { return [datetime]::ParseExact($x,'s',$INV) } catch { }
    return $null }

$tazeCache = $false
$tazeSayac = 0
$kalpSayac = 0

while ($true) {
    $simdi = Get-Date
    $bugun = $simdi.ToString('yyyy-MM-dd')
    $csv   = Join-Path $aktDir "$bugun.csv"

    # --- duraklatma ---
    $durakli = $false
    if (Test-Path $ayarD) {
        $a = Get-Content $ayarD -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($a -and $a.duraklat) {
            if ($a.duraklat -eq 'sonsuz') { $durakli = $true }
            else { $db = TarihOku $a.duraklat; if ($db -and $simdi -lt $db) { $durakli = $true } }
        }
    }

    if (-not $durakli) {
        if (-not (Test-Path $csv)) { 'zaman;uygulama;baslik;bosta;kategori;sure;kaynak' | Out-File $csv -Encoding utf8 }

        # bosta suresi
        $li = New-Object IZ+LII
        $li.cbSize = [uint32][System.Runtime.InteropServices.Marshal]::SizeOf($li)
        [void][IZ]::GetLastInputInfo([ref]$li)
        # GetLastInputInfo ve GetTickCount ayni 32-bit zaman tabanini kullanir.
        # Isaretli Environment.TickCount 24,9 gunde negatife doner; unsigned fark
        # kullanmak 49,7 gunluk sarma sonrasinda da AFK suresini dogru tutar.
        $simdiTick = [uint32][IZ]::GetTickCount()
        $sonGirdiTick = [uint32]$li.dwTime
        [uint64]$bosMs = 0
        if ($simdiTick -ge $sonGirdiTick) { $bosMs = [uint64]$simdiTick - [uint64]$sonGirdiTick }
        else { $bosMs = 4294967296L + [uint64]$simdiTick - [uint64]$sonGirdiTick }
        $bosDk = [math]::Round($bosMs / 60000, 1)

        # on plandaki pencere
        $hw = [IZ]::GetForegroundWindow()
        $uyg = '(bilinmiyor)'; $basl = ''
        if ($hw -ne [IntPtr]::Zero) {
            $fp = 0; [void][IZ]::GetWindowThreadProcessId($hw, [ref]$fp)
            if ($fp -gt 0) { $pr = Get-Process -Id $fp -ErrorAction SilentlyContinue; if ($pr) { $uyg = $pr.ProcessName } }
            $sb = New-Object System.Text.StringBuilder 300
            [void][IZ]::GetWindowText($hw, $sb, 300)
            $basl = $sb.ToString()
        }
        if ($basl.Length -gt 90) { $basl = $basl.Substring(0,90) }
        $basl = ($basl -replace ';', ',') -replace "`r|`n", ' '
        $alan = TarayiciAlanAdi -pencere $hw -surec $uyg

        # taze .md kontrolu + kural tazeleme (60 saniyede bir, arada onbellekten)
        $tazeSayac++
        if ($tazeSayac -ge 6 -or $tazeSayac -eq 1) {
            $tazeSayac = 1
            # kurallar.json degistiyse yeniden yukle (servisi durdurmaya gerek yok)
            if (Test-Path $kuralD) {
                try {
                    $yeniK = Get-Content $kuralD -Raw -Encoding UTF8 | ConvertFrom-Json
                    if ($yeniK) { $K = $yeniK }
                } catch { }
            }
            $tazeCache = $false
            $esik = $simdi.AddMinutes(-$TAZELIK)
            Get-ChildItem -Path $klasor -Filter *.md -Recurse |
                Where-Object { $_.DirectoryName -notlike '*hatirlatici*' -and $_.DirectoryName -notlike '*hafiza*' -and $URETILEN -notcontains $_.Name } |
                ForEach-Object { if ($_.LastWriteTime -gt $esik) { $tazeCache = $true } }
        }

        # --- kategori karari (oncelik sirasi onemli) ---
        $kat = 'diger'; $kaynak = 'bilinmiyor'
        if ($bosDk -ge $AFK_SINIR) {
            $kat = 'bosta'; $kaynak = 'afk'
        }
        elseif ((EslesirMi $basl $K.calisma.baslik) -or (EslesirMi $alan $K.calisma.alanadi)) {
            # Calisma basligi veya adres cubugundan okunan alan adi yasagi ezer:
            # tarayıcıdaki izinli çalışma kaynağı sayılır.
            $kat = 'calisma'; $kaynak = 'baslik-calisma'
            if (EslesirMi $alan $K.calisma.alanadi) { $kaynak = 'alanadi-calisma' }
        }
        elseif ((EslesirMi $uyg $K.yasakli.surec) -or (EslesirMi $basl $K.yasakli.baslik) -or (EslesirMi $alan $K.yasakli.alanadi)) {
            $kat = 'diger'; $kaynak = 'yasakli'
        }
        elseif (EslesirMi $uyg $K.calisma.surec) {
            $kat = 'calisma'; $kaynak = 'izinli'
        }
        elseif ($tazeCache) {
            $kat = 'calisma'; $kaynak = 'taze-md'
        }
        elseif ($K.belirsizSayilsin) {
            # Bilinmeyen uygulama -> supheden faydalanir, SAYILIR ama isaretlenir
            $kat = 'calisma'; $kaynak = 'belirsiz'
        }

        "$($simdi.ToString('HH:mm:ss'));$uyg;$basl;$bosDk;$kat;$ARALIK;$kaynak" | Out-File $csv -Encoding utf8 -Append

        # --- CALISMA PERIYODU: yasakli uygulama aninda engellenir ---
        # GUVENLIK KAPILARI (hepsi gecilmeden engel tetiklenmez):
        #   1) hatirlatici\DUR panik dosyasi yoksa
        #   2) uygulama "asla engelleme" listesinde degilse (toplanti, kurulum, sistem)
        #   3) son 1 saatte 6'dan az engel gosterilmisse
        #   4) ekran kilidi aciksa (sirket kurulumunda varsayilan kapali; Ayarlar'dan degisir)
        $engelIzin = $true
        if (Test-Path (Join-Path $hDir 'DUR')) { $engelIzin = $false }
        if ($engelIzin -and $K.aslaEngelleme) {
            if ((EslesirMi $uyg $K.aslaEngelleme) -or (EslesirMi $basl $K.aslaEngelleme)) { $engelIzin = $false }
        }
        if ($engelIzin) {
            $engelGecmisi = @($engelGecmisi | Where-Object { ($simdi - $_).TotalMinutes -lt 60 })
            if ($engelGecmisi.Count -ge 6) { $engelIzin = $false }
        }
        # Ayar yalnizca yasakli ornekte okunur: her 10 sn'de iki JSON okumasi gereksiz
        if ($kaynak -eq 'yasakli' -and $engelIzin -and $ozellikVar) {
            $ozI = Get-TakipOzellikleri -HatirlaticiKlasoru $hDir
            if ($ozI -and -not $ozI.ekranKilidi) { $engelIzin = $false }
        }
        if ($kaynak -eq 'yasakli' -and $engelIzin) {
            $perAktif = $false
            if (Test-Path $perD) {
                try {
                    $P = Get-Content $perD -Raw -Encoding UTF8 | ConvertFrom-Json
                    if ($P.aktif) {
                        $bit = [datetime]::ParseExact($P.bitis,'s',$INV)
                        if ($simdi -lt $bit) {
                            $perAktif = $true
                            # mola varsa engelleme
                            if ($P.molaBitis) {
                                try { if ($simdi -lt [datetime]::ParseExact($P.molaBitis,'s',$INV)) { $perAktif = $false } } catch { }
                            }
                        } else {
                            # periyot doldu -> kapat
                            $P.aktif = $false
                            $P | ConvertTo-Json | Out-File $perD -Encoding utf8
                            "$($simdi.ToString('yyyy-MM-dd HH:mm:ss'))  periyot suresi doldu" | Out-File $izLog -Encoding utf8 -Append
                        }
                    }
                } catch { }
            }
            if ($perAktif -and (($simdi - $sonEngel).TotalSeconds -ge 60)) {
                $sonEngel = $simdi
                $engelGecmisi += $simdi
                Start-Process -FilePath "$env:SystemRoot\System32\wscript.exe" `
                    -ArgumentList "//B //Nologo `"$vbsYol`" `"$engelPs`" `"$uyg`" `"$basl`"" -WindowStyle Hidden
                "$($simdi.ToString('yyyy-MM-dd HH:mm:ss'))  ENGEL tetiklendi -- $uyg" | Out-File $izLog -Encoding utf8 -Append
            }
        }
    }

    # 5 dakikada bir kalp atisi
    $kalpSayac++
    if ($kalpSayac -ge 30) {
        $kalpSayac = 0
        $mb = [math]::Round((Get-Process -Id $PID).WorkingSet64 / 1MB, 1)
        $dr = 'aktif'; if ($durakli) { $dr = 'duraklatildi' }
        "$($simdi.ToString('yyyy-MM-dd HH:mm:ss'))  kalp atisi -- $dr, bellek ${mb}MB" | Out-File $izLog -Encoding utf8 -Append
        $l = @(Get-Content $izLog -Encoding UTF8)
        if ($l.Count -gt 600) { $l[-400..-1] | Out-File $izLog -Encoding utf8 }
    }

    Start-Sleep -Seconds $ARALIK
}






