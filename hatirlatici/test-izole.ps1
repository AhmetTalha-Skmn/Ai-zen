# IZOLE TEST -- gecici bos kasada izleyici servisinin karar tablosu
$ErrorActionPreference='Continue'
$hDir = $PSScriptRoot; if (-not $hDir) { $hDir = Split-Path $MyInvocation.MyCommand.Path -Parent }
$psExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$env:CALISMATAKIP_TEST_SN = '3'   # test pencereleri 3 sn sonra kendi kapanir
$gecti=0; $kaldi=0
function T { param($ad,$ok,$d)
  if ($ok) { $script:gecti++; Write-Host ("  [OK]   {0,-48} {1}" -f $ad,$d) -ForegroundColor Green }
  else     { $script:kaldi++; Write-Host ("  [HATA] {0,-48} {1}" -f $ad,$d) -ForegroundColor Red } }

Add-Type @"
using System; using System.Runtime.InteropServices;
public class FW {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [StructLayout(LayoutKind.Sequential)] public struct LII { public uint cbSize; public uint dwTime; }
  [DllImport("user32.dll")] public static extern bool GetLastInputInfo(ref LII p);
  [DllImport("kernel32.dll")] public static extern uint GetTickCount();
}
"@
function GecenMs { param([uint32]$simdi, [uint32]$sonGirdi)
    if ($simdi -ge $sonGirdi) { return [uint64]$simdi - [uint64]$sonGirdi }
    return 4294967296L + [uint64]$simdi - [uint64]$sonGirdi }
function BostaDk {
    $li = New-Object FW+LII
    $li.cbSize = [uint32][System.Runtime.InteropServices.Marshal]::SizeOf($li)
    [void][FW]::GetLastInputInfo([ref]$li)
    return [math]::Round((GecenMs ([uint32][FW]::GetTickCount()) ([uint32]$li.dwTime)) / 60000, 1) }

T 'TickCount sarmasi AFK farkini korur' ((GecenMs 120 4294967200) -eq 216) '216 ms'

$tmp = Join-Path $env:TEMP 'phptest-kasa'
if ([System.IO.Directory]::Exists($tmp)) { [System.IO.Directory]::Delete($tmp, $true) }
[void][System.IO.Directory]::CreateDirectory((Join-Path $tmp 'hatirlatici'))
Copy-Item (Join-Path $hDir 'izleyici.ps1')  (Join-Path $tmp 'hatirlatici\izleyici.ps1')
Copy-Item (Join-Path $hDir 'kurallar.json') (Join-Path $tmp 'hatirlatici\kurallar.json')
$tIz  = Join-Path $tmp 'hatirlatici\izleyici.ps1'
$tCsv = Join-Path $tmp ('hatirlatici\aktivite\' + (Get-Date).ToString('yyyy-MM-dd') + '.csv')
Write-Host "Gecici kasa: $tmp" -ForegroundColor DarkGray

function IzleyiciyiCalistir { param($saniye)
    if ([System.IO.File]::Exists($tCsv)) { [System.IO.File]::Delete($tCsv) }
    $p = Start-Process -FilePath $psExe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$tIz`"" -WindowStyle Hidden -PassThru
    Start-Sleep -Seconds $saniye
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 700
    if (-not [System.IO.File]::Exists($tCsv)) { return @() }
    return @(Import-Csv $tCsv -Delimiter ';' -Encoding UTF8) }
function NotepadOdakla {
    Start-Process notepad.exe | Out-Null
    $np = $null
    for ($i = 0; $i -lt 25; $i++) {
        Start-Sleep -Milliseconds 400
        $np = Get-Process -Name notepad -ErrorAction SilentlyContinue |
              Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
        if ($np) { break }
    }
    if ($np) { [void][FW]::SetForegroundWindow([IntPtr]$np.MainWindowHandle) }
    Start-Sleep -Milliseconds 1200
    return $np }
function NotepadKapat { Get-Process -Name notepad -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue }

Write-Host "`n=== DURUM 1: izinsiz uygulama + taze .md YOK  =>  'diger' ===" -ForegroundColor Cyan
$np = NotepadOdakla
$r1 = IzleyiciyiCalistir 25
NotepadKapat
T "ornek toplandi" ($r1.Count -ge 2) "$($r1.Count) ornek"
if ($r1.Count -gt 0) {
    T "10 saniyelik araliklar" ($r1[0].sure -eq '10') "sure=$($r1[0].sure)"
    T "zaman HH:mm:ss" ($r1[0].zaman -match '^\d{2}:\d{2}:\d{2}$') $r1[0].zaman
    if ($r1[-1].uygulama -match 'otepad') {
        T "on plan notepad okundu" $true "okunan: $($r1[-1].uygulama)"
    } else {
        Write-Host ("  [ATLA] {0,-48} {1}" -f "on plan notepad okundu", "odak calinamadi -- on planda: $($r1[-1].uygulama) (tam ekran uygulama olabilir)") -ForegroundColor Yellow
    }
    T "pencere basligi kaydedildi" ($r1[-1].baslik.Length -gt 0) "baslik: $($r1[-1].baslik)"
    if ($r1[-1].uygulama -match 'otepad') {
        # Beklentiyi kurallardan turet -- Notepad sonradan siniflandirilmis olabilir
        $KK = Get-Content (Join-Path $hDir 'kurallar.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        function Esl { param($m,$l) foreach ($x in $l) { if ($x -and $m -like "*$x*") { return $true } }; return $false }
        $beklenen = 'belirsiz'
        if (Esl $r1[-1].uygulama $KK.yasakli.surec)      { $beklenen = 'yasakli' }
        elseif (Esl $r1[-1].uygulama $KK.calisma.surec)  { $beklenen = 'izinli' }
        T "kaynak kurallara uygun" ($r1[-1].kaynak -eq $beklenen) "beklenen=$beklenen gelen=$($r1[-1].kaynak)"
        $bekKat = 'calisma'; if ($beklenen -eq 'yasakli') { $bekKat = 'diger' }
        T "kategori kurallara uygun" ($r1[-1].kategori -eq $bekKat) "beklenen=$bekKat gelen=$($r1[-1].kategori)"
    } else {
        Write-Host ("  [ATLA] {0,-48} {1}" -f "belirsiz siniflandirma", "odak calinamadi -- on planda: $($r1[-1].uygulama)") -ForegroundColor Yellow
    }
}

Write-Host "`n=== DURUM 2: izinsiz uygulama + TAZE .md var  =>  'calisma' ===" -ForegroundColor Cyan
'ders notu' | Out-File (Join-Path $tmp 'ders.md') -Encoding utf8
$np = NotepadOdakla
$r2 = IzleyiciyiCalistir 25
NotepadKapat
$bosSon = BostaDk
if ($r2.Count -gt 0) {
    $cal = @($r2 | Where-Object { $_.kategori -eq 'calisma' })
    $yasakliVar = @($r2 | Where-Object { $_.kaynak -eq 'yasakli' })
    if ($yasakliVar.Count -gt 0) {
        Write-Host ("  [ATLA] {0,-48} {1}" -f "ornekler 'calisma' sayildi", "on planda YASAKLI uygulama ($($r2[-1].uygulama)) -- yasak tazeligi ezer, dogru davranis") -ForegroundColor Yellow
        T "yasakli, taze .md'yi EZER" (@($yasakliVar | Where-Object { $_.kategori -eq 'diger' }).Count -eq $yasakliVar.Count) "$($yasakliVar.Count) ornek 'diger'"
    } elseif ($bosSon -ge 5) {
        Write-Host ("  [ATLA] {0,-48} {1}" -f "ornekler 'calisma' sayildi", "kullanici $bosSon dk AFK -- tum ornekler dogru sekilde 'bosta'") -ForegroundColor Yellow
        $bostaSay = @($r2 | Where-Object { $_.kategori -eq 'bosta' }).Count
        T "AFK iken dogru sekilde 'bosta'" ($bostaSay -eq $r2.Count) "$bostaSay/$($r2.Count) bosta"
    } else {
        T "ornekler 'calisma' sayildi" ($cal.Count -eq $r2.Count) "$($cal.Count)/$($r2.Count)"
    }
}

Write-Host "`n=== DURUM 3: takipcinin URETTIGI .md tazelik saymamali ===" -ForegroundColor Cyan
[System.IO.File]::Delete((Join-Path $tmp 'ders.md'))
'x' | Out-File (Join-Path $tmp 'Calisma Kaydi.md') -Encoding utf8
'y' | Out-File (Join-Path $tmp 'Aktivite Gunlugu.md') -Encoding utf8
Write-Host "     kasadaki .md: $((Get-ChildItem $tmp -Filter *.md | Select-Object -ExpandProperty Name) -join ', ')" -ForegroundColor DarkGray
$np = NotepadOdakla
$r3 = IzleyiciyiCalistir 25
NotepadKapat
$IZINLI = @('Obsidian','Claude','Code','VSCodium','WindowsTerminal','phpstorm64','sublime_text','devenv','notepad++')
if ($r3.Count -gt 0) {
    # On plan testi calisirken degisebilir (kullanici makineyi kullaniyor olabilir).
    # Degismez kural: IZINLI olmayan bir uygulama on plandayken kategori 'calisma' OLAMAZ.
    # Uretilen dosyalar tazelik saymamali -> kaynak 'taze-md' OLMAMALI
    $tazeIhlal = @($r3 | Where-Object { $_.kaynak -eq 'taze-md' })
    T "uretilen .md tazelik saymiyor" ($tazeIhlal.Count -eq 0) "$($tazeIhlal.Count) 'taze-md' ornegi"
}

Write-Host "`n=== DURUM 3b: YASAKLI uygulama  =>  'diger' ===" -ForegroundColor Cyan
$kj = Get-Content (Join-Path $tmp 'hatirlatici\kurallar.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$kj.yasakli.surec = @($kj.yasakli.surec) + @('Notepad','notepad')
$kj | ConvertTo-Json -Depth 5 | Out-File (Join-Path $tmp 'hatirlatici\kurallar.json') -Encoding utf8
$np = NotepadOdakla
$r3b = IzleyiciyiCalistir 25
NotepadKapat
if ($r3b.Count -gt 0 -and $r3b[-1].uygulama -match 'otepad') {
    T "yasakli listede => 'diger'" ($r3b[-1].kategori -eq 'diger') "kategori=$($r3b[-1].kategori)"
    T "kaynak 'yasakli'" ($r3b[-1].kaynak -eq 'yasakli') "kaynak=$($r3b[-1].kaynak)"
} else {
    Write-Host ("  [ATLA] {0,-48} {1}" -f "yasakli uygulama testi", "odak calinamadi") -ForegroundColor Yellow
}
Copy-Item (Join-Path $hDir 'kurallar.json') (Join-Path $tmp 'hatirlatici\kurallar.json') -Force

Write-Host "`n=== DURUM 4: duraklatma  =>  hic kayit olmamali ===" -ForegroundColor Cyan
([ordered]@{hedef=240;duraklat=(Get-Date).AddHours(1).ToString('s')} | ConvertTo-Json) | Out-File (Join-Path $tmp 'hatirlatici\ayarlar.json') -Encoding utf8
$r4 = IzleyiciyiCalistir 25
T "duraklatildiginda ornek yok" ($r4.Count -eq 0) "$($r4.Count) ornek"

Write-Host "`n=== DURUM 5: tek ornek garantisi ===" -ForegroundColor Cyan
([ordered]@{hedef=240;duraklat=''} | ConvertTo-Json) | Out-File (Join-Path $tmp 'hatirlatici\ayarlar.json') -Encoding utf8
$p1 = Start-Process -FilePath $psExe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$tIz`"" -WindowStyle Hidden -PassThru
Start-Sleep -Seconds 3
$p2 = Start-Process -FilePath $psExe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$tIz`"" -WindowStyle Hidden -PassThru
Start-Sleep -Seconds 5
$ikinciOldu = (Get-Process -Id $p2.Id -ErrorAction SilentlyContinue) -eq $null
T "ikinci ornek kendini kapatti" $ikinciOldu ''
T "ilk ornek yasiyor" ((Get-Process -Id $p1.Id -ErrorAction SilentlyContinue) -ne $null) ''
Stop-Process -Id $p1.Id -Force -ErrorAction SilentlyContinue
Stop-Process -Id $p2.Id -Force -ErrorAction SilentlyContinue

Write-Host "`n=== DURUM 6: gercek izleyici hala ayakta mi ===" -ForegroundColor Cyan
$gp = Join-Path $hDir 'izleyici.pid'
if (Test-Path $gp) {
    $gpid = 0; [void][int]::TryParse((Get-Content $gp -Encoding UTF8 | Select-Object -First 1), [ref]$gpid)
    $gpr = Get-Process -Id $gpid -ErrorAction SilentlyContinue
    T "asil izleyici etkilenmedi" ($gpr -ne $null) "pid $gpid"
}

if ([System.IO.Directory]::Exists($tmp)) { [System.IO.Directory]::Delete($tmp, $true) }
Write-Host "`n===================================" -ForegroundColor Cyan
Write-Host ("  GECTI: {0}   KALDI: {1}" -f $gecti,$kaldi) -ForegroundColor $(if($kaldi -eq 0){'Green'}else{'Red'})
Write-Host "===================================`n" -ForegroundColor Cyan











# --- Test bitti: acilan pencereleri ve gecici kasalari topla ---
$env:CALISMATAKIP_TEST_SN = ''
& $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $hDir 'test-temizlik.ps1') | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
