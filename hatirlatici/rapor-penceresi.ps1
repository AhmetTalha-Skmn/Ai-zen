# ============================================================
#  Gunluk rapor penceresi -- kontrol panelinden acilir. Gorunum: tema.ps1
#  Incelenecek sekmesinde kullanici izinli/izinsiz/belirsiz karari verir (api.ps1 Takip-Siniflandir).
#  UTF-8 BOM ile kaydedilir (Turkce metinler).
#  Onizleme: $env:ARAYUZ_ONIZLEME = <png yolu> ise pencereyi gostermeden PNG'ye cizer.
#  -Sekme <0-4>: acilista gosterilecek sekme (4 = Incelenecek).
# ============================================================
param([int]$Sekme = 0)
$ErrorActionPreference = 'SilentlyContinue'
$hDir = $PSScriptRoot; if (-not $hDir) { $hDir = Split-Path $MyInvocation.MyCommand.Path -Parent }
. (Join-Path $hDir 'tema.ps1')
. (Join-Path $hDir 'api.ps1')
$raporDir = Join-Path $hDir 'rapor'
$psExe    = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

$f = New-Object System.Windows.Forms.Form
Tema-Pencere $f 'Aizen · Çalışma raporu' 920 680
$f.MinimumSize = (Tema-Boyut 780 540)

# ---- ust bar ----
[void](Tema-Etiket $f 'Çalışma raporu' 20 16 300 32 16 -Kalin)
$cbGun = New-Object System.Windows.Forms.ComboBox
$cbGun.DropDownStyle = 'DropDownList'; $cbGun.FlatStyle = 'Flat'; $cbGun.Font = (Tema-Yazi 9.5)
$cbGun.Location = (Tema-Konum 562 21); $cbGun.Size = (Tema-Boyut 120 26); $cbGun.Anchor = 'Top,Right'
$f.Controls.Add($cbGun)
$btnYenile = Tema-Dugme $f 'Yeniden üret' 690 17 110 32; $btnYenile.Anchor = 'Top,Right'
$btnKlasor = Tema-Dugme $f 'Ham veri'     808 17 92 32;  $btnKlasor.Anchor = 'Top,Right'

# ---- ozet ----
$k1 = Tema-Kart $f 20 62 880 100; $k1.Anchor = 'Top,Left,Right'
$lbOzet = Tema-Etiket $k1 '' 20 14 300 40 20 -Kalin
$lbSaat = Tema-Etiket $k1 '' 330 26 530 22 9.5 -Renk $TEMA.Soluk; $lbSaat.Anchor = 'Top,Left,Right'
$cub    = Tema-Cubuk $k1 20 60 840 8; $cub.Anchor = 'Top,Left,Right'
$lbAlt  = Tema-Etiket $k1 '' 20 72 840 20 9 -Renk $TEMA.Soluk; $lbAlt.Anchor = 'Top,Left,Right'

# ---- sekmeler: duz dugmeler, secili olan vurgu renginde ----
$sekmeAdlari = @('Uygulamalar', 'Neye ne kadar baktım', 'Tarayıcı', 'Aramalar', 'İncelenecek')
$sekmeEn = @(118, 176, 96, 96, 132)
$sekmeler = @(); $xx = 20
for ($i = 0; $i -lt 5; $i++) {
    $s = Tema-Dugme $f $sekmeAdlari[$i] $xx 174 $sekmeEn[$i] 32 'sekme'; $s.Name = [string]$i
    $sekmeler += $s; $xx += $sekmeEn[$i] + 6 }

$k2 = Tema-Kart $f 20 214 880 446; $k2.Anchor = 'Top,Bottom,Left,Right'
$k2.Padding = New-Object System.Windows.Forms.Padding(1)
function YeniListe { param($kolonlar)
    $lv = New-Object System.Windows.Forms.ListView
    $lv.View = 'Details'; $lv.FullRowSelect = $true; $lv.GridLines = $false; $lv.BorderStyle = 'None'
    $lv.HeaderStyle = 'Nonclickable'; $lv.Dock = 'Fill'; $lv.Font = (Tema-Yazi 9.5)
    $lv.BackColor = $TEMA.Kart; $lv.ForeColor = $TEMA.Metin
    foreach ($k in $kolonlar) { [void]$lv.Columns.Add($k[0], $k[1]) }
    $lv.Visible = $false; $k2.Controls.Add($lv); return $lv }
$lvUyg = YeniListe @(@('Uygulama', 240), @('Süre', 80), @('Kategori', 100), @('Kaynak', 120), @('Örnek başlık', 320))
$lvBas = YeniListe @(@('Uygulama', 180), @('Başlık', 560), @('Süre', 100))
$lvWeb = YeniListe @(@('Alan adı', 380), @('Ziyaret', 100), @('Kategori', 140))
$lvAra = YeniListe @(@('Arama terimi', 560), @('Tarayıcı', 140))
$lvInc = YeniListe @(@('Tür', 90), @('Ad', 280), @('Süre / ziyaret', 120), @('Karar', 110), @('Örnek başlık', 240))
$listeler = @($lvUyg, $lvBas, $lvWeb, $lvAra, $lvInc)

# Incelenecek sekmesinin alt seridi: kullanici karari. Listeler Dock=Fill oldugu icin serit
# onlardan SONRA eklenir (WinForms yerlesimi en arkadaki kontrolden baslar).
$KARAR_IPUCU = 'İzinli: çalışma sayılır  ·  İzinsiz: periyotta engellenir  ·  Belirsiz: sorulmaz'
$pnKarar = New-Object System.Windows.Forms.Panel
$pnKarar.Size = (Tema-Boyut 878 56); $pnKarar.Dock = 'Bottom'; $pnKarar.BackColor = $TEMA.Uzerinde; $pnKarar.Visible = $false
$k2.Controls.Add($pnKarar)
$cizgi = New-Object System.Windows.Forms.Panel; $cizgi.Dock = 'Top'; $cizgi.Height = 1; $cizgi.BackColor = $TEMA.Kenar
$pnKarar.Controls.Add($cizgi)
$lbKarar = Tema-Etiket $pnKarar $KARAR_IPUCU 16 17 500 22 9 -Renk $TEMA.Soluk; $lbKarar.Anchor = 'Top,Left,Right'
$btnIzinli   = Tema-Dugme $pnKarar 'İzinli'          528 11 96 34 'birincil'
$btnIzinsiz  = Tema-Dugme $pnKarar 'İzinsiz'         632 11 96 34 'tehlike'
$btnBelirsiz = Tema-Dugme $pnKarar 'Belirsiz kalsın' 736 11 130 34
foreach ($b in $btnIzinli, $btnIzinsiz, $btnBelirsiz) { $b.Anchor = 'Top,Right'; $b.Enabled = $false }

function SekmeSec { param([int]$n)
    $pnKarar.Visible = ($n -eq 4)
    for ($i = 0; $i -lt 5; $i++) {
        $listeler[$i].Visible = ($i -eq $n)
        if ($i -eq $n) { $sekmeler[$i].BackColor = $TEMA.Vurgu; $sekmeler[$i].ForeColor = [System.Drawing.Color]::White; $sekmeler[$i].FlatAppearance.MouseOverBackColor = $TEMA.VurguKoyu }
        else { $sekmeler[$i].BackColor = $TEMA.Zemin; $sekmeler[$i].ForeColor = $TEMA.Soluk; $sekmeler[$i].FlatAppearance.MouseOverBackColor = $TEMA.Kenar }
    } }
foreach ($s in $sekmeler) { $s.Add_Click({ SekmeSec ([int]$this.Name) }) }

# ---- veri ----
function GunleriYukle {
    $cbGun.Items.Clear()
    foreach ($d in @(Get-ChildItem $raporDir -Filter '*.json' | Sort-Object Name -Descending)) { [void]$cbGun.Items.Add($d.BaseName) }
    if ($cbGun.Items.Count -gt 0) { $cbGun.SelectedIndex = 0 } }
function Satir { param($lv, [string[]]$degerler, $renk, $etiket)
    $it = New-Object System.Windows.Forms.ListViewItem($degerler[0])
    for ($i = 1; $i -lt $degerler.Count; $i++) { [void]$it.SubItems.Add($degerler[$i]) }
    if ($renk) { $it.ForeColor = $renk }
    if ($etiket) { $it.Tag = $etiket }
    [void]$lv.Items.Add($it) }
# Sekme basligindaki sayi: henuz karar verilmemis satirlar
function IncSayac {
    $n = @($lvInc.Items | Where-Object { -not $_.SubItems[3].Text }).Count
    $sekmeler[4].Text = 'İncelenecek'; if ($n -gt 0) { $sekmeler[4].Text = "İncelenecek ($n)" } }
function RaporGoster {
    foreach ($lv in $listeler) { $lv.Items.Clear() }
    $lbKarar.Text = $KARAR_IPUCU; $lbKarar.ForeColor = $TEMA.Soluk
    $r = $null
    if ($cbGun.SelectedItem) {
        $yol = Join-Path $raporDir "$($cbGun.SelectedItem).json"
        if (Test-Path $yol) { try { $r = Get-Content $yol -Raw -Encoding UTF8 | ConvertFrom-Json } catch { } } }
    if (-not $r) { $lbOzet.Text = 'Rapor yok'; $lbSaat.Text = ''; $lbAlt.Text = ''; Tema-CubukAyarla $cub 0; IncSayac; return }

    $hedef = [int]$r.hedefDk; if ($hedef -le 0) { $hedef = 240 }
    $lbOzet.Text = "$($r.calismaDk) / $hedef dk"
    $tuttu = 'hedef tutmadı'; $renk = $TEMA.Vurgu; if ($r.hedefTuttuMu) { $tuttu = 'hedef tuttu'; $renk = $TEMA.Basari }
    $lbSaat.Text = "çalışma  ·  $(Tema-Sayi ($r.calismaDk / 60)) / $(Tema-Sayi ($hedef / 60)) saat  ·  $tuttu"; $lbOzet.Width = $lbOzet.PreferredWidth; $lbSaat.Left = $lbOzet.Right + 10
    Tema-CubukAyarla $cub ([math]::Round($r.calismaDk / $hedef * 100)) $renk
    $td = [string]$r.tarayiciDurum; if ($td.Length -gt 60) { $td = $td.Substring(0, 60) + '...' }
    $lbAlt.Text = "Diğer $($r.digerDk) dk  ·  Boşta $($r.bostaDk) dk  ·  Kayıt $($r.kayitDk) dk  ·  Tarayıcı: $td"

    foreach ($u in $r.uygulamalar) {
        $rk = $TEMA.Soluk; if ($u.kategori -eq 'calisma') { $rk = $TEMA.Basari } elseif ($u.kaynak -eq 'yasakli') { $rk = $TEMA.Tehlike }
        Satir $lvUyg @([string]$u.ad, "$($u.dakika) dk", [string]$u.kategori, [string]$u.kaynak, [string]$u.ornekBaslik) $rk }
    foreach ($b in $r.enCokBakilan) { Satir $lvBas @([string]$b.uygulama, [string]$b.baslik, "$($b.dakika) dk") $null }
    foreach ($a in $r.alanlar) {
        $rk = $null; if ($a.kategori -eq 'calisma') { $rk = $TEMA.Basari } elseif ($a.kategori -eq 'yasakli') { $rk = $TEMA.Tehlike }
        Satir $lvWeb @([string]$a.alan, [string]$a.ziyaret, [string]$a.kategori) $rk }
    foreach ($s in $r.aramalar) { Satir $lvAra @([string]$s.terim, [string]$s.tarayici) $null }
    # Rapor sonradan verilen kararlardan eski olabilir: api.ps1 bugunku kurallarla suzer (brifingle ayni)
    foreach ($o in @(Tk-Incelenecekler $r)) {
        if ($o.tur -eq 'surec') { Satir $lvInc @('uygulama', $o.ad, "$($o.dk) dk", '', $o.ornek) $null $o }
        else { Satir $lvInc @('site', $o.ad, "$($o.ziyaret) ziyaret", '', '') $null $o } }
    IncSayac
}

# Karar: api.ps1 Takip-Siniflandir (yapay zekanin kullandigi yolun aynisi). Karar verilen satir
# listede kalir, rengi ve Karar kolonu degisir; yanlissa secilip baska karar verilebilir.
$KARAR_AD = @{ calisma = 'izinli'; yasakli = 'izinsiz'; belirsiz = 'belirsiz' }
function KararVer { param([string]$Karar)
    $secili = @($lvInc.SelectedItems); if ($secili.Count -eq 0) { return }
    $renk = $TEMA.Soluk; if ($Karar -eq 'calisma') { $renk = $TEMA.Basari } elseif ($Karar -eq 'yasakli') { $renk = $TEMA.Tehlike }
    $olan = @(); $hata = ''
    foreach ($it in $secili) {
        try {
            $null = Takip-Siniflandir -Oge $it.Tag.ad -Karar $Karar -Tur $it.Tag.tur
            $it.SubItems[3].Text = $KARAR_AD[$Karar]; $it.ForeColor = $renk; $it.Selected = $false
            $olan += $it.Tag.ad
        } catch { $hata = $_.Exception.Message }
    }
    IncSayac
    if ($hata) { $lbKarar.Text = "Kaydedilemedi: $hata"; $lbKarar.ForeColor = $TEMA.Tehlike; return }
    $ne = $olan[0]; if ($olan.Count -gt 1) { $ne = "$($olan.Count) öğe" }
    $lbKarar.Text = "$ne → $($KARAR_AD[$Karar]). Yanlışsa satırı seçip başka karar ver."
    $lbKarar.ForeColor = $renk
}
$lvInc.Add_SelectedIndexChanged({ $var = $lvInc.SelectedItems.Count -gt 0; foreach ($d in $btnIzinli, $btnIzinsiz, $btnBelirsiz) { $d.Enabled = $var } })
$btnIzinli.Add_Click({ KararVer 'calisma' })
$btnIzinsiz.Add_Click({ KararVer 'yasakli' })
$btnBelirsiz.Add_Click({ KararVer 'belirsiz' })

$cbGun.Add_SelectedIndexChanged({ RaporGoster })
$btnYenile.Add_Click({
    $g = $cbGun.SelectedItem; if (-not $g) { $g = (Get-Date).ToString('yyyy-MM-dd') }
    $btnYenile.Enabled = $false; $btnYenile.Text = 'Üretiliyor...'; $f.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    Start-Process -FilePath $psExe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$hDir\gunluk-rapor.ps1`" -Tarih $g -GecmisDahil" -WindowStyle Hidden -Wait
    $btnYenile.Enabled = $true; $btnYenile.Text = 'Yeniden üret'; $f.Cursor = [System.Windows.Forms.Cursors]::Default
    GunleriYukle; RaporGoster })
$btnKlasor.Add_Click({ Start-Process explorer.exe $raporDir })

GunleriYukle
RaporGoster
SekmeSec ([math]::Max(0, [math]::Min(4, $Sekme)))
if ($env:ARAYUZ_ONIZLEME) { Tema-Onizleme $f $env:ARAYUZ_ONIZLEME; return }
[void]$f.ShowDialog()
