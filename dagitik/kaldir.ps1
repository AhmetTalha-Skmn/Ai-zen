<#
Bu bilgisayardaki kurulumu geri alir.

  .\kaldir.ps1 -YalnizMerkez     merkez baglantisini keser, yerel takip kalir
  .\kaldir.ps1                   yerel takibi ve merkez baglantisini kaldirir
  .\kaldir.ps1 -VeriyiDeSil      ek olarak biriken olcum verisini de siler
  .\kaldir.ps1 -Deneme           hicbir sey yapmaz, ne yapacagini yazar

Olcum verisi (aktivite, rapor, durum, gecmis) -VeriyiDeSil verilmedikce silinmez.
Merkez dinleyicisinin urlacl ve guvenlik duvari kurali yonetici yetkisi ister;
yetki yoksa bu iki adim atlanir ve ekranda bildirilir.
#>
param(
    [switch]$YalnizMerkez,
    [switch]$VeriyiDeSil,
    [switch]$Onayla,
    [switch]$Deneme,
    [string]$UygulamaKok
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Ortak.ps1')
. (Join-Path $PSScriptRoot 'kisayol.ps1')

if ([string]::IsNullOrWhiteSpace($UygulamaKok)) { $UygulamaKok = Get-DagitikUygulamaKok $PSScriptRoot }
$hatirlatici = Join-Path $UygulamaKok 'hatirlatici'
$yapilan = New-Object System.Collections.Generic.List[string]

function Test-Yonetici {
    $kimlik = [Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object Security.Principal.WindowsPrincipal($kimlik)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Kaldir-Gorev {
    param([string]$Ad)
    $gorev = Get-ScheduledTask -TaskName $Ad -ErrorAction SilentlyContinue
    if ($null -eq $gorev) { return }
    if (-not $Deneme) {
        try { Stop-ScheduledTask -TaskName $Ad -ErrorAction SilentlyContinue } catch { }
        Unregister-ScheduledTask -TaskName $Ad -Confirm:$false -ErrorAction SilentlyContinue
    }
    $yapilan.Add("gorev kaldirildi: $Ad")
}

function Kaldir-Dosya {
    param([string]$Yol, [string]$Etiket)
    if (-not (Test-Path -LiteralPath $Yol)) { return }
    if (-not $Deneme) { Remove-Item -LiteralPath $Yol -Recurse -Force -ErrorAction SilentlyContinue }
    $yapilan.Add("silindi: $Etiket")
}

$kapsam = if ($YalnizMerkez) { 'yalnizca merkez baglantisi' } else { 'yerel takip + merkez baglantisi' }
Write-Output "Kaldirilacak: $kapsam"
Write-Output "Kurulum klasoru: $UygulamaKok"
if ($VeriyiDeSil) { Write-Output 'UYARI: biriken olcum verisi de silinecek (aktivite, rapor, durum, gecmis).' }
if ($Deneme) { Write-Output '(-Deneme: hicbir degisiklik yapilmayacak)' }

if (-not $Onayla -and -not $Deneme) {
    $cevap = Read-Host 'Devam edilsin mi? (EVET / hayir)'
    if (($cevap.Trim().ToUpperInvariant()) -notin @('EVET', 'E', 'YES', 'Y')) {
        Write-Output 'Vazgecildi. Hicbir sey degistirilmedi.'
        exit 2
    }
}

# 1) Merkez baglantisi: gonderim gorevi, kayit ve kuyruk
Kaldir-Gorev 'Calisma Takip Gonderici'
Kaldir-Dosya (Join-Path $hatirlatici 'merkez.json') 'merkez kaydi (merkez.json)'
Kaldir-Dosya (Join-Path $hatirlatici 'merkez-outbox') 'gonderim kuyrugu'
Kaldir-Dosya (Join-Path $hatirlatici 'onay.json') 'onay kaydi'
Kaldir-Dosya (Join-Path $UygulamaKok 'VERI-KAPSAMI.txt') 'veri kapsami bildirimi'

if (-not $YalnizMerkez) {
    # 2) Yerel takip: gorev, izleyici sureci, kisayollar
    Kaldir-Gorev 'Calisma Takip Sistemi'
    Kaldir-Gorev 'Calisma Takip Merkezi'
    Kaldir-Gorev 'Calisma Takip Yedek'
    $izleyiciPid = Join-Path $hatirlatici 'izleyici.pid'
    if (Test-Path -LiteralPath $izleyiciPid) {
        $numara = 0
        if ([int]::TryParse((Get-Content -LiteralPath $izleyiciPid -Raw).Trim(), [ref]$numara) -and $numara -gt 0) {
            $surec = Get-Process -Id $numara -ErrorAction SilentlyContinue
            if ($null -ne $surec -and -not $Deneme) { try { $surec.Kill() } catch { } }
            if ($null -ne $surec) { $yapilan.Add("izleyici durduruldu (PID $numara)") }
        }
    }
    foreach ($yol in (Remove-CtKurulumKisayollari -MerkezDahil -Deneme:$Deneme)) { $yapilan.Add("kisayol silindi: $yol") }
    if (Remove-CtBaslatMenusu -Deneme:$Deneme) { $yapilan.Add('Baslat menusu klasoru silindi') }
    if (Unregister-CtUygulamaKaydi -Deneme:$Deneme) { $yapilan.Add('Windows "Uygulamalar" kaydi silindi') }

    # 3) Merkez dinleyicisi: urlacl ve guvenlik duvari (yonetici gerekir)
    $merkezAyar = Read-DagitikJson (Join-Path $PSScriptRoot 'merkez-ayarlari.json')
    if ($null -ne $merkezAyar) {
        $port = [int](Get-DagitikDeger $merkezAyar 'port' 0)
        if ($port -gt 0) {
            if (Test-Yonetici) {
                if (-not $Deneme) {
                    & netsh http delete urlacl "url=http://+:$port/" | Out-Null
                    try { Get-NetFirewallRule -DisplayName "Calisma Takip Merkezi $port" -ErrorAction SilentlyContinue |
                        Remove-NetFirewallRule -ErrorAction SilentlyContinue } catch { }
                }
                $yapilan.Add("urlacl ve guvenlik duvari kurali kaldirildi (port $port)")
            }
            else {
                $yapilan.Add("ATLANDI (yonetici degil): urlacl ve guvenlik duvari kurali, port $port")
            }
        }
    }
}

if ($VeriyiDeSil) {
    foreach ($ad in 'aktivite', 'rapor', 'durum.json', 'gecmis.json', 'log.txt', 'izleyici.log', 'izleyici.pid') {
        Kaldir-Dosya (Join-Path $hatirlatici $ad) "olcum verisi: $ad"
    }
    if (-not $YalnizMerkez) { Kaldir-Dosya (Join-Path $PSScriptRoot 'veri') 'merkezdeki cihaz verisi' }
}

Write-Output ''
if ($yapilan.Count -eq 0) { Write-Output 'Kaldirilacak bir sey bulunamadi.' }
else { foreach ($satir in $yapilan) { Write-Output "  - $satir" } }
Write-Output ''
if ($Deneme) { Write-Output 'Deneme modu: hicbir degisiklik yapilmadi.' }
else {
    Write-Output 'Tamamlandi. Uygulama dosyalari klasorde duruyor; klasoru elle silebilirsin.'
    if (-not $VeriyiDeSil) { Write-Output 'Olcum verisi korundu (-VeriyiDeSil ile silinebilir).' }
}
