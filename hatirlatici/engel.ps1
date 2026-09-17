# ============================================================
#  ENGEL -- calisma periyodu sirasinda yasakli uygulama acilinca
#  aninda ekrani kapatan tam ekran uyari. Gorunum: tema.ps1 (Tema-TamEkranKart)
#  Kullanim: engel.ps1 -Uygulama <ad> -Baslik <baslik>
#  UTF-8 BOM ile kaydedilir (Turkce metinler).
# ============================================================
param([string]$Uygulama = '?', [string]$Baslik = '')
$ErrorActionPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public class EW {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
}
"@

$hDir = $PSScriptRoot; if (-not $hDir) { $hDir = Split-Path $MyInvocation.MyCommand.Path -Parent }
$klasor = Split-Path $hDir -Parent
$perD   = Join-Path $hDir 'periyot.json'
$logD   = Join-Path $hDir 'log.txt'

# tek ornek
$md5 = [System.Security.Cryptography.MD5]::Create()
$iz  = [BitConverter]::ToString($md5.ComputeHash([Text.Encoding]::UTF8.GetBytes($klasor.ToLower()))).Replace('-','').Substring(0,12)
$yeni = $false
$mtx = New-Object System.Threading.Mutex($true, "Local\CalismaTakipEngel_$iz", [ref]$yeni)
if (-not $yeni) { exit }

# PANIK: hatirlatici\DUR dosyasi varsa engel HIC acilmaz
if (Test-Path (Join-Path $hDir 'DUR')) { exit }

function Log { param($m)
    $s = "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))  $m"
    for ($i=0;$i -lt 5;$i++) { try { [System.IO.File]::AppendAllText($logD, $s + [Environment]::NewLine, [Text.Encoding]::UTF8); break } catch { Start-Sleep -Milliseconds 120 } } }

# periyot bilgisi
$kalanDk = 0
if (Test-Path $perD) {
    try {
        $p = Get-Content $perD -Raw -Encoding UTF8 | ConvertFrom-Json
        $bit = [datetime]::ParseExact($p.bitis,'s',[Globalization.CultureInfo]::InvariantCulture)
        $kalanDk = [math]::Max([math]::Round(($bit - (Get-Date)).TotalMinutes), 0)
    } catch { }
}
Log "ENGEL gosteriliyor -- yasakli: $Uygulama (periyot kalan $kalanDk dk)"

. (Join-Path $hDir 'tema.ps1')
$vs = [System.Windows.Forms.SystemInformation]::VirtualScreen
$script:secildi = $false
$satirlar = @(,@('Yasaklı uygulama', $Uygulama))
if ($Baslik) { $satirlar += ,@('Pencere', $Baslik) }
$satirlar += ,@('Periyot kalan', "$kalanDk dk")
$u = Tema-TamEkranKart -Alan $vs -Vurgu $TEMA.Tehlike -Baslik 'Çalışma periyodundasın.' `
    -AltBaslik 'Bu süre çalışma olarak sayılmıyor. Devam etmek için birini seç.' -Satirlar $satirlar `
    -Dugmeler @('Çalışmaya dön', '5 dk mola', 'Periyodu bitir') -Turler @('birincil', 'ikincil', 'tehlike')
$f = $u.Form; $l3 = $u.Durum
$b1 = $u.Dugmeler[0]; $b2 = $u.Dugmeler[1]; $b3 = $u.Dugmeler[2]
$f.Add_FormClosing({ if (-not $script:secildi) { $_.Cancel = $true } })
$b1.DialogResult = [System.Windows.Forms.DialogResult]::Yes; $f.AcceptButton = $b1
$b2.DialogResult = [System.Windows.Forms.DialogResult]::No
$b3.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
$b1.Add_Click({ $script:secildi=$true }); $b2.Add_Click({ $script:secildi=$true }); $b3.Add_Click({ $script:secildi=$true })

# GUVENLIK: hicbir kosulda 3 dakikadan fazla ekranda kalamaz.
# Kilitli kalma riskine karsi sert ust sinir.
$script:gecen = 0
$AZAMI_SN = 180
# Test modu: CALISMATAKIP_TEST_SN ortam degiskeni varsa o kadar saniye sonra kendi kapanir
if ($env:CALISMATAKIP_TEST_SN) { $t2 = 0; if ([int]::TryParse($env:CALISMATAKIP_TEST_SN, [ref]$t2) -and $t2 -gt 0) { $AZAMI_SN = $t2 } }
$l3.ForeColor = $TEMA.Soluk
$l3.Text = "$AZAMI_SN sn sonra kendiliğinden kapanır."
$t=New-Object System.Windows.Forms.Timer; $t.Interval=1000
$t.Add_Tick({
    $script:gecen++
    $l3.Text = "$([math]::Max($AZAMI_SN - $script:gecen,0)) sn sonra kendiliğinden kapanır."
    $f.TopMost=$true
    if (-not $f.ContainsFocus) { $f.Activate(); [void][EW]::SetForegroundWindow($f.Handle) }
    if ($script:gecen -ge $AZAMI_SN) {
        $t.Stop(); $script:secildi=$true
        $f.DialogResult=[System.Windows.Forms.DialogResult]::Abort; $f.Close()
    }
})
$t.Start()
$f.Add_Shown({ $f.Activate(); $f.BringToFront(); [void][EW]::ShowWindow($f.Handle,9); [void][EW]::SetForegroundWindow($f.Handle) })
for ($i=1;$i -le 3;$i++) { [System.Media.SystemSounds]::Hand.Play(); Start-Sleep -Milliseconds 400 }

$sonuc = $f.ShowDialog(); $t.Stop()
switch ($sonuc) {
    'Yes' { Log 'engel: calismaya don' }
    'No'  {
        Log 'engel: 5 dk mola'
        try {
            $p = Get-Content $perD -Raw -Encoding UTF8 | ConvertFrom-Json
            $p | Add-Member -NotePropertyName molaBitis -NotePropertyValue (Get-Date).AddMinutes(5).ToString('s') -Force
            $p | ConvertTo-Json | Out-File $perD -Encoding utf8
        } catch { }
    }
    'Abort' { Log 'engel: zaman asimi ile kapandi (3 dk)' }
    'Cancel' {
        Log 'engel: PERIYOT BITIRILDI'
        try {
            $p = Get-Content $perD -Raw -Encoding UTF8 | ConvertFrom-Json
            $p.aktif = $false
            $p | ConvertTo-Json | Out-File $perD -Encoding utf8
        } catch { }
    }
}
