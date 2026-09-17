# ============================================================
#  Ortak arayuz temasi: kontrol paneli, rapor penceresi, uyari ve engel ekranlari.
#  Sade tutuldu: acik zemin, beyaz kartlar, tek vurgu rengi, duz dugmeler, Segoe UI.
#  Golge, animasyon, saydamlik yok. Windows 11'de pencere koseleri yuvarlanir.
#  Kullanim: . (Join-Path $PSScriptRoot 'tema.ps1')        (ASCII tutulur, BOM gerekmez)
# ============================================================
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
if (-not ('TemaDwm' -as [type])) {
    Add-Type @"
using System; using System.Runtime.InteropServices;
public static class TemaDwm {
    [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr h, int a, ref int v, int s);
    // DWMWA_WINDOW_CORNER_PREFERENCE = 33, DWMWCP_ROUND = 2 (Windows 11; eski surumlerde etkisiz)
    public static void Yuvarla(IntPtr h) { int v = 2; try { DwmSetWindowAttribute(h, 33, ref v, 4); } catch { } }
}
"@
}

function Tema-Renk { param([string]$Hex) return [System.Drawing.ColorTranslator]::FromHtml($Hex) }
$TEMA = @{
    Zemin = (Tema-Renk '#F3F4F6'); Kart = (Tema-Renk '#FFFFFF'); Kenar = (Tema-Renk '#E5E7EB'); Cizgi = (Tema-Renk '#D1D5DB')
    Metin = (Tema-Renk '#111827'); Soluk = (Tema-Renk '#6B7280'); Pasif = (Tema-Renk '#9CA3AF'); PasifZemin = (Tema-Renk '#E5E7EB')
    Vurgu = (Tema-Renk '#2563EB'); VurguKoyu = (Tema-Renk '#1D4ED8'); VurguAcik = (Tema-Renk '#EFF6FF')
    Basari = (Tema-Renk '#16A34A'); Uyari = (Tema-Renk '#D97706'); Tehlike = (Tema-Renk '#DC2626')
    TehlikeAcik = (Tema-Renk '#FEF2F2'); TehlikeKenar = (Tema-Renk '#FECACA'); Uzerinde = (Tema-Renk '#F9FAFB')
    Perde = (Tema-Renk '#0F172A')
}
function Tema-Yazi { param([float]$Boy = 9.5, [switch]$Kalin)
    if ($Kalin) { return (New-Object System.Drawing.Font('Segoe UI Semibold', $Boy)) }
    return (New-Object System.Drawing.Font('Segoe UI', $Boy)) }
function Tema-Konum { param([int]$X, [int]$Y) return (New-Object System.Drawing.Point($X, $Y)) }
function Tema-Boyut { param([int]$En, [int]$Boy) return (New-Object System.Drawing.Size($En, $Boy)) }
# Turkce ondalik gosterim (0,3 gibi)
function Tema-Sayi { param([double]$Deger, [int]$Ondalik = 1) return ([math]::Round($Deger, $Ondalik)).ToString([Globalization.CultureInfo]'tr-TR') }

# Normal pencere: zemin rengi, yazi tipi, Windows 11 yuvarlak koseler
function Tema-Pencere { param($Form, [string]$Baslik, [int]$En, [int]$Boy)
    $Form.Text = $Baslik; $Form.ClientSize = (Tema-Boyut $En $Boy)
    $Form.BackColor = $TEMA.Zemin; $Form.ForeColor = $TEMA.Metin; $Form.Font = (Tema-Yazi 9.5)
    $Form.StartPosition = 'CenterScreen'
    $Form.Add_HandleCreated({ [TemaDwm]::Yuvarla($this.Handle) }) }

# Beyaz kart, ince gri kenar
function Tema-Kart { param($Ust, [int]$X, [int]$Y, [int]$En, [int]$Boy)
    $p = New-Object System.Windows.Forms.Panel
    $p.Location = (Tema-Konum $X $Y); $p.Size = (Tema-Boyut $En $Boy); $p.BackColor = $TEMA.Kart
    $p.Add_Paint({ param($s, $e) $k = New-Object System.Drawing.Pen($TEMA.Kenar); $e.Graphics.DrawRectangle($k, 0, 0, $s.Width - 1, $s.Height - 1); $k.Dispose() })
    $Ust.Controls.Add($p); return $p }

function Tema-Etiket { param($Ust, [string]$Metin, [int]$X, [int]$Y, [int]$En, [int]$Boy = 20, [float]$Yazi = 9.5, [switch]$Kalin, $Renk)
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Metin; $l.Location = (Tema-Konum $X $Y); $l.Size = (Tema-Boyut $En $Boy)
    $l.Font = (Tema-Yazi $Yazi -Kalin:$Kalin); $l.AutoEllipsis = $true; $l.BackColor = [System.Drawing.Color]::Transparent
    $l.ForeColor = $TEMA.Metin; if ($Renk) { $l.ForeColor = $Renk }
    $Ust.Controls.Add($l); return $l }

# Kucuk gri bolum basligi (BUGUN, TAKIP SISTEMI ...)
function Tema-Bolum { param($Ust, [string]$Metin, [int]$X, [int]$Y, [int]$En = 300)
    return (Tema-Etiket $Ust $Metin.ToUpper([Globalization.CultureInfo]'tr-TR') $X $Y $En 18 8.25 -Kalin -Renk $TEMA.Soluk) }

# Duz dugme. Tur: birincil (mavi) | ikincil (beyaz, ince kenar) | tehlike (acik kirmizi) | sekme
function Tema-Dugme { param($Ust, [string]$Metin, [int]$X, [int]$Y, [int]$En, [int]$Boy = 34, [string]$Tur = 'ikincil')
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Metin; $b.Location = (Tema-Konum $X $Y); $b.Size = (Tema-Boyut $En $Boy)
    $b.FlatStyle = 'Flat'; $b.UseVisualStyleBackColor = $false; $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    $b.Font = (Tema-Yazi 9.5 -Kalin)
    switch ($Tur) {
        'birincil' { $b.BackColor = $TEMA.Vurgu; $b.ForeColor = [System.Drawing.Color]::White; $b.FlatAppearance.BorderSize = 0; $b.FlatAppearance.MouseOverBackColor = $TEMA.VurguKoyu }
        'tehlike'  { $b.BackColor = $TEMA.TehlikeAcik; $b.ForeColor = $TEMA.Tehlike; $b.FlatAppearance.BorderColor = $TEMA.TehlikeKenar; $b.FlatAppearance.MouseOverBackColor = (Tema-Renk '#FEE2E2') }
        'sekme'    { $b.BackColor = $TEMA.Zemin; $b.ForeColor = $TEMA.Soluk; $b.FlatAppearance.BorderSize = 0; $b.FlatAppearance.MouseOverBackColor = $TEMA.Kenar }
        default    { $b.BackColor = $TEMA.Kart; $b.ForeColor = $TEMA.Metin; $b.FlatAppearance.BorderColor = $TEMA.Cizgi; $b.FlatAppearance.MouseOverBackColor = $TEMA.Uzerinde }
    }
    # Pasifken (uyari kilidi) gri gorunsun, aktif olunca kendi rengine donsun
    $b.Tag = @{ Arka = $b.BackColor; On = $b.ForeColor }
    $b.Add_EnabledChanged({ if ($this.Enabled) { $this.BackColor = $this.Tag.Arka; $this.ForeColor = $this.Tag.On } else { $this.BackColor = $TEMA.PasifZemin; $this.ForeColor = $TEMA.Pasif } })
    $Ust.Controls.Add($b); return $b }

# Duz ilerleme cubugu (iki panel). Tema-CubukAyarla ile doldurulur; yeniden boyutlanmaya uyar.
function Tema-Cubuk { param($Ust, [int]$X, [int]$Y, [int]$En, [int]$Boy = 8)
    $iz = New-Object System.Windows.Forms.Panel
    $iz.Location = (Tema-Konum $X $Y); $iz.Size = (Tema-Boyut $En $Boy); $iz.BackColor = $TEMA.Kenar; $iz.Tag = 0.0
    $dol = New-Object System.Windows.Forms.Panel
    $dol.Location = (Tema-Konum 0 0); $dol.Size = (Tema-Boyut 0 $Boy); $dol.BackColor = $TEMA.Vurgu
    $iz.Controls.Add($dol)
    $iz.Add_Resize({ $this.Controls[0].Width = [int]($this.Width * [double]$this.Tag / 100); $this.Controls[0].Height = $this.Height })
    $Ust.Controls.Add($iz); return $iz }
function Tema-CubukAyarla { param($Cubuk, [double]$Yuzde, $Renk)
    $y = [math]::Max(0, [math]::Min(100, $Yuzde)); $Cubuk.Tag = $y
    $Cubuk.Controls[0].Width = [int]($Cubuk.Width * $y / 100)
    if ($Renk) { $Cubuk.Controls[0].BackColor = $Renk } }

# Kucuk yuvarlak durum isareti
function Tema-Nokta { param($Ust, [int]$X, [int]$Y, $Renk)
    $n = New-Object System.Windows.Forms.Panel
    $n.Location = (Tema-Konum $X $Y); $n.Size = (Tema-Boyut 10 10); $n.BackColor = [System.Drawing.Color]::Transparent; $n.Tag = $Renk
    $n.Add_Paint({ param($s, $e) $e.Graphics.SmoothingMode = 'AntiAlias'; $fr = New-Object System.Drawing.SolidBrush($s.Tag); $e.Graphics.FillEllipse($fr, 0, 0, 9, 9); $fr.Dispose() })
    $Ust.Controls.Add($n); return $n }
function Tema-NoktaAyarla { param($Nokta, $Renk) $Nokta.Tag = $Renk; $Nokta.Invalidate() }

# Tam ekran perde + ortada kart (uyari ve engel ekranlari).
# Satirlar: @(@('Etiket','Deger'), ...). Donus: @{ Form; Kart; Durum; Dugmeler }
# -Pencere: ayni kart perdesiz, baslik cubuklu, kapatilabilir normal pencerede (ekran kilidi kapaliyken)
function Tema-TamEkranKart { param([System.Drawing.Rectangle]$Alan, $Vurgu, [string]$Baslik, [string]$AltBaslik, [object[]]$Satirlar, [double]$Yuzde = -1, [string[]]$Dugmeler, [string[]]$Turler, [switch]$Pencere)
    $f = New-Object System.Windows.Forms.Form
    $f.FormBorderStyle = 'None'; $f.StartPosition = 'Manual'; $f.Bounds = $Alan
    $f.TopMost = $true; $f.ShowInTaskbar = $false; $f.BackColor = $TEMA.Perde; $f.Opacity = 0.96
    $f.Font = (Tema-Yazi 10); $f.Cursor = [System.Windows.Forms.Cursors]::Arrow
    $kw = 620; $ic = $kw - 80
    $kart = New-Object System.Windows.Forms.Panel; $kart.BackColor = $TEMA.Kart; $kart.Width = $kw
    $f.Controls.Add($kart)
    $serit = New-Object System.Windows.Forms.Panel; $serit.Dock = 'Top'; $serit.Height = 6; $serit.BackColor = $Vurgu
    $kart.Controls.Add($serit)
    $y = 34
    [void](Tema-Etiket $kart $Baslik 40 $y $ic 36 17 -Kalin -Renk $Vurgu); $y += 42
    if ($AltBaslik) { [void](Tema-Etiket $kart $AltBaslik 40 $y $ic 22 10 -Renk $TEMA.Soluk); $y += 30 }
    if ($Yuzde -ge 0) { $c = Tema-Cubuk $kart 40 ($y + 4) $ic 8; Tema-CubukAyarla $c $Yuzde $Vurgu; $y += 26 }
    foreach ($s in $Satirlar) {
        [void](Tema-Etiket $kart ([string]$s[0]) 40 $y 130 24 10 -Renk $TEMA.Soluk)
        [void](Tema-Etiket $kart ([string]$s[1]) 170 $y ($ic - 130) 24 10 -Kalin)
        $y += 30
    }
    $durum = Tema-Etiket $kart '' 40 ($y + 8) $ic 22 9.5 -Renk $TEMA.Uyari; $y += 44
    $n = @($Dugmeler).Count; $bosluk = 10; $bw = [int](($ic - ($n - 1) * $bosluk) / $n)
    $dl = @()
    for ($i = 0; $i -lt $n; $i++) {
        $tur = 'ikincil'; if ($Turler -and $i -lt $Turler.Count) { $tur = $Turler[$i] }
        $dl += (Tema-Dugme $kart $Dugmeler[$i] (40 + $i * ($bw + $bosluk)) $y $bw 46 $tur)
    }
    $kh = $y + 46 + 36
    $kart.Height = $kh
    $kart.Location = (Tema-Konum ([int](($Alan.Width - $kw) / 2)) ([int](($Alan.Height - $kh) / 2)))
    if ($Pencere) {
        $f.FormBorderStyle = 'FixedDialog'; $f.MaximizeBox = $false; $f.MinimizeBox = $true
        $f.TopMost = $false; $f.ShowInTaskbar = $true; $f.BackColor = $TEMA.Zemin; $f.Opacity = 1
        $f.ClientSize = (Tema-Boyut ($kw + 32) ($kh + 32)); $f.StartPosition = 'CenterScreen'
        $kart.Location = (Tema-Konum 16 16)
        $f.Add_HandleCreated({ [TemaDwm]::Yuvarla($this.Handle) })
    }
    return @{ Form = $f; Kart = $kart; Durum = $durum; Dugmeler = $dl }
}

# Pencereyi kullaniciya gostermeden PNG'ye cizer (onizleme ve testler icin)
function Tema-Onizleme { param($Form, [string]$Yol)
    $Form.ShowInTaskbar = $false; $Form.StartPosition = 'Manual'; $Form.Location = (Tema-Konum -32000 -32000)
    $Form.Show(); [System.Windows.Forms.Application]::DoEvents()
    $bmp = New-Object System.Drawing.Bitmap($Form.Width, $Form.Height)
    $Form.DrawToBitmap($bmp, (New-Object System.Drawing.Rectangle(0, 0, $Form.Width, $Form.Height)))
    $bmp.Save($Yol, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    $Form.Hide(); $Form.Dispose() }
