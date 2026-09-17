# ============================================================
#  Yardim / wiki penceresi. Sayfalar: <kok>\wiki\*.md (wiki.ps1), kurulum turune gore suzulur.
#  UTF-8 BOM ile kaydedilir (Turkce metinler).
#  -Sayfa <ad>: acilista gosterilecek sayfa (ornek: ayarlar)
#  -Tur <bireysel|sirket|ozel>: turu zorlar (onizleme); verilmezse bu kurulumun turu
#  Onizleme: $env:ARAYUZ_ONIZLEME = <png yolu> ise pencereyi gostermeden PNG'ye cizer.
# ============================================================
param([string]$Sayfa = '', [string]$Tur = '')
$ErrorActionPreference = 'SilentlyContinue'
$hDir = $PSScriptRoot; if (-not $hDir) { $hDir = Split-Path $MyInvocation.MyCommand.Path -Parent }
. (Join-Path $hDir 'tema.ps1')
. (Join-Path $hDir 'ozellikler.ps1')
. (Join-Path $hDir 'wiki.ps1')
$wikiDir = Join-Path (Split-Path $hDir -Parent) 'wiki'
$Tur = Oz-Tur $Tur
if (-not $Tur) { $Tur = (Get-TakipOzellikleri -HatirlaticiKlasoru $hDir).kurulumTuru }
$sayfalar = @(Wiki-Sayfalar $wikiDir $Tur 'windows')
$adlar = @($sayfalar | ForEach-Object { $_.ad })

$f = New-Object System.Windows.Forms.Form
Tema-Pencere $f 'Aizen · Yardım' 940 660
$f.MinimumSize = (Tema-Boyut 760 520)

[void](Tema-Etiket $f 'Yardım' 20 16 300 32 16 -Kalin)
$lbTur = Tema-Etiket $f "Kurulum türü: $(Oz-TurAdi $Tur)  ·  bu türe ait sayfalar" 330 26 590 22 9.5 -Renk $TEMA.Soluk
$lbTur.TextAlign = 'MiddleRight'; $lbTur.Anchor = 'Top,Left,Right'

# ---- sayfa listesi ----
$k1 = Tema-Kart $f 20 62 220 578; $k1.Anchor = 'Top,Bottom,Left'
$k1.Padding = New-Object System.Windows.Forms.Padding(1)
$lb = New-Object System.Windows.Forms.ListBox
$lb.Dock = 'Fill'; $lb.BorderStyle = 'None'; $lb.IntegralHeight = $false
$lb.DrawMode = 'OwnerDrawFixed'; $lb.ItemHeight = 34; $lb.BackColor = $TEMA.Kart
$k1.Controls.Add($lb)
$yaziNormal = Tema-Yazi 10; $yaziSecili = Tema-Yazi 10 -Kalin
$lb.Add_DrawItem({ param($s, $e)
    if ($e.Index -lt 0) { return }
    $secili = ($e.State -band [System.Windows.Forms.DrawItemState]::Selected) -ne 0
    $zemin = $TEMA.Kart; $renk = $TEMA.Metin; $yazi = $yaziNormal
    if ($secili) { $zemin = $TEMA.VurguAcik; $renk = $TEMA.Vurgu; $yazi = $yaziSecili }
    $fr = New-Object System.Drawing.SolidBrush($zemin); $e.Graphics.FillRectangle($fr, $e.Bounds); $fr.Dispose()
    $r = New-Object System.Drawing.Rectangle(($e.Bounds.X + 16), $e.Bounds.Y, ($e.Bounds.Width - 20), $e.Bounds.Height)
    [System.Windows.Forms.TextRenderer]::DrawText($e.Graphics, [string]$s.Items[$e.Index], $yazi, $r, $renk,
        [System.Windows.Forms.TextFormatFlags]'VerticalCenter, Left, EndEllipsis')
})

# ---- sayfa icerigi ----
$k2 = Tema-Kart $f 252 62 668 578; $k2.Anchor = 'Top,Bottom,Left,Right'
$k2.Padding = New-Object System.Windows.Forms.Padding(1)
$wb = New-Object System.Windows.Forms.WebBrowser
$wb.Dock = 'Fill'; $wb.ScriptErrorsSuppressed = $true; $wb.AllowWebBrowserDrop = $false
$wb.IsWebBrowserContextMenuEnabled = $false; $wb.AllowNavigation = $true
$k2.Controls.Add($wb)

foreach ($s in $sayfalar) { [void]$lb.Items.Add($s.baslik) }
if ($sayfalar.Count -eq 0) {
    $wb.DocumentText = '<html><body style="font-family:Segoe UI;margin:24px;color:#6B7280">Yardım sayfaları bulunamadı: ' +
        [System.Net.WebUtility]::HtmlEncode($wikiDir) + '</body></html>'
}
$lb.Add_SelectedIndexChanged({
    $n = $lb.SelectedIndex
    if ($n -ge 0 -and $n -lt $sayfalar.Count) { $wb.DocumentText = Wiki-Belge $sayfalar[$n] $adlar }
})
# Sayfa ici baglanti "wiki:<ad>": gezinme iptal edilir, listeden o sayfa secilir.
# Dis adreslere hic gidilmez. Secim olay bittikten sonra yapilir (gezinme icinden belge degistirilmez).
$script:hedefSayfa = -1
$wb.Add_Navigating({ param($s, $e)
    $u = [string]$e.Url
    if ($u -eq 'about:blank') { return }
    $e.Cancel = $true
    if ($u.StartsWith('wiki:')) {
        $script:hedefSayfa = [array]::IndexOf($adlar, $u.Substring(5).Trim('/').ToLowerInvariant())
        if ($script:hedefSayfa -ge 0) { [void]$f.BeginInvoke([Action]{ $lb.SelectedIndex = $script:hedefSayfa }) }
    }
})

$ilk = [array]::IndexOf($adlar, ([string]$Sayfa).ToLowerInvariant())
if ($ilk -lt 0 -and $sayfalar.Count -gt 0) { $ilk = 0 }
if ($ilk -ge 0) { $lb.SelectedIndex = $ilk }

if ($env:ARAYUZ_ONIZLEME) { Tema-Onizleme $f $env:ARAYUZ_ONIZLEME; return }
[void]$f.ShowDialog()
