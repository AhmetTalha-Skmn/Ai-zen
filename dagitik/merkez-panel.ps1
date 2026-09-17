# ============================================================
#  Aizen — merkez paneli
#
#  Bu panel yalnızca bu bilgisayarda biriken cihaz özetlerini okur:
#    dagitik\veri\guncel\*.json   (bugünün son durumu)
#    dagitik\veri\gunluk\<tarih>\ (geçmiş günler)
#  Ağ dinleyicisi açmaz, başka bilgisayara komut göndermez, ham gezinme
#  geçmişi okumaz. Hesaplamalar Merkez-Ozet.ps1 içindedir (testlerle aynı kod).
#
#  -Kontrol: arayüz açmadan satırları JSON olarak yazar (izleme ve test için).
# ============================================================
[CmdletBinding()]
param(
    [ValidateRange(5, 3600)]
    [int]$YenilemeSn = 20,

    [ValidateRange(1, 72)]
    [int]$SessizlikSaati = 6,

    [string]$Tarih = '',

    # Veri ve yapılandırma başka bir klasörde tutuluyorsa (ya da test ediliyorsa)
    [string]$VeriYolu = '',
    [string]$AyarDosyasi = '',

    [ValidateSet('Ozet','Kurallar')][string]$Sekme = 'Ozet',
    [switch]$Kontrol
)

$ErrorActionPreference = 'Stop'
$script:PanelKlasoru = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($script:PanelKlasoru)) {
    $script:PanelKlasoru = Split-Path -Parent $MyInvocation.MyCommand.Path
}
. (Join-Path $script:PanelKlasoru 'Ortak.ps1')
. (Join-Path $script:PanelKlasoru 'Merkez-Ozet.ps1')
. (Join-Path $script:PanelKlasoru 'Merkez-Kural.ps1')

$script:VeriKlasoru = $(if ([string]::IsNullOrWhiteSpace($VeriYolu)) { Join-Path $script:PanelKlasoru 'veri' } else { $VeriYolu })
$script:AyarYolu = $(if ([string]::IsNullOrWhiteSpace($AyarDosyasi)) { Join-Path $script:PanelKlasoru 'merkez-ayarlari.json' } else { $AyarDosyasi })
$script:KuralYolu = Join-Path (Split-Path -Parent ([IO.Path]::GetFullPath($script:AyarYolu))) 'merkez-kurallar.json'
$script:SeciliTarih = $Tarih
$script:Satirlar = @()
# Gun listesi doldurulurken SelectedIndexChanged tetiklenir; tablo daha satir
# uretmeden yenileme yapilmasin diye bayrakla bastirilir.
$script:Yukleniyor = $false

function Get-PanelAyari { return (Read-DagitikJson $script:AyarYolu) }

function Get-PanelSatirlari {
    return @(Get-MerkezCihazSatirlari -Ayar (Get-PanelAyari) -VeriKlasoru $script:VeriKlasoru `
        -Tarih $script:SeciliTarih -SessizlikSaati $SessizlikSaati)
}

function Format-PanelDakika {
    param([object]$Dakika)
    if ($null -eq $Dakika) { return '—' }
    return ('{0} dk' -f [math]::Max([int]$Dakika, 0))
}

function Format-PanelSessizlik {
    param([int]$SessizDk)
    if ($SessizDk -lt 0) { return 'hiç' }
    if ($SessizDk -lt 1) { return 'şimdi' }
    if ($SessizDk -lt 60) { return ('{0} dk önce' -f $SessizDk) }
    if ($SessizDk -lt 1440) { return ('{0} sa önce' -f [int][math]::Floor($SessizDk / 60)) }
    return ('{0} gün önce' -f [int][math]::Floor($SessizDk / 1440))
}

function Format-PanelDurum {
    param([string]$Durum)
    switch ($Durum) {
        'canli' { return 'Canlı' }
        'sessiz' { return 'SESSİZ' }
        default { return 'Veri yok' }
    }
}

function Get-PanelCubuk {
    param([int]$Yuzde)
    # 12 blok = %100; daha uzunu sutuna sigmiyor ve "..." ile kirpiliyor
    $uzunluk = [math]::Max(0, [math]::Min(12, [int][math]::Round($Yuzde / 8.5)))
    if ($uzunluk -eq 0) { return '' }
    return ([string][char]0x2588) * $uzunluk
}

# ---------- -Kontrol: arayüzsüz çıktı ----------
if ($Kontrol) {
    # PS 5.1: fonksiyondan donen tek elemanli dizi tek nesneye coker, .Count bos kalir
    $satirlar = @(Get-PanelSatirlari)
    [ordered]@{
        tamam = $true
        veriKlasoru = $script:VeriKlasoru
        tarih = $(if ([string]::IsNullOrWhiteSpace($script:SeciliTarih)) { 'bugun' } else { $script:SeciliTarih })
        kurallar = @(Get-MerkezKuralSatirlari (Get-MerkezKurallari $script:KuralYolu))
        ortakToplam = Get-MerkezPanelToplami (Get-PanelAyari) $script:VeriKlasoru $script:SeciliTarih
        cihazSayisi = $satirlar.Count
        cihazlar = @($satirlar | ForEach-Object {
            [ordered]@{
                aktif = $_.aktif
                kuralYazabilir = $_.kuralYazabilir
                cihazId = $_.cihazId
                ad = $_.ad
                durum = $_.durum
                calismaDk = $_.calismaDk
                hedefDk = $_.hedefDk
                yuzde = $_.yuzde
                sessizDk = $_.sessizDk
                izleyiciCalisiyor = $_.izleyiciCalisiyor
                uygulamaSayisi = $_.uygulamaSayisi
                senkron = $_.senkron
                sonBasariliGonderimUtc = $(if ($null -eq $_.sonGorulmeUtc) { $null } else { $_.sonGorulmeUtc.ToString('o') })
                onayUtc = $_.onayUtc
            }
        })
    } | ConvertTo-Json -Depth 5
    return
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$RENK = @{
    Zemin = [Drawing.Color]::FromArgb(248, 250, 252)
    Metin = [Drawing.Color]::FromArgb(15, 23, 42)
    Soluk = [Drawing.Color]::FromArgb(71, 85, 105)
    Basari = [Drawing.Color]::FromArgb(22, 163, 74)
    Uyari = [Drawing.Color]::FromArgb(217, 119, 6)
    Tehlike = [Drawing.Color]::FromArgb(220, 38, 38)
    Baslik = [Drawing.Color]::FromArgb(237, 242, 247)
}

function Ayarla-PanelIzgara {
    param([System.Windows.Forms.DataGridView]$Izgara)
    $Izgara.ReadOnly = $true
    $Izgara.AllowUserToAddRows = $false
    $Izgara.AllowUserToDeleteRows = $false
    $Izgara.AllowUserToOrderColumns = $false
    $Izgara.AllowUserToResizeRows = $false
    $Izgara.RowHeadersVisible = $false
    $Izgara.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
    $Izgara.MultiSelect = $false
    $Izgara.AutoGenerateColumns = $false
    $Izgara.BackgroundColor = [Drawing.Color]::White
    $Izgara.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $Izgara.EnableHeadersVisualStyles = $false
    $Izgara.ColumnHeadersDefaultCellStyle.BackColor = $RENK.Baslik
    $Izgara.ColumnHeadersDefaultCellStyle.ForeColor = $RENK.Metin
    $Izgara.ColumnHeadersDefaultCellStyle.Font = New-Object Drawing.Font('Segoe UI', 9, [Drawing.FontStyle]::Bold)
    $Izgara.DefaultCellStyle.SelectionBackColor = [Drawing.Color]::FromArgb(219, 234, 254)
    $Izgara.DefaultCellStyle.SelectionForeColor = $RENK.Metin
}

function Ekle-PanelSutunu {
    param(
        [System.Windows.Forms.DataGridView]$Izgara,
        [string]$Baslik,
        [string]$Ozellik,
        [int]$Genislik,
        [System.Windows.Forms.DataGridViewContentAlignment]$Hizalama = [System.Windows.Forms.DataGridViewContentAlignment]::MiddleLeft
    )
    $sutun = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $sutun.HeaderText = $Baslik
    $sutun.DataPropertyName = $Ozellik
    $sutun.Name = $Ozellik
    $sutun.Width = $Genislik
    $sutun.DefaultCellStyle.Alignment = $Hizalama
    [void]$Izgara.Columns.Add($sutun)
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Aizen — Merkez Paneli'
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.Size = New-Object Drawing.Size(1240, 820)
$form.MinimumSize = New-Object Drawing.Size(1240, 820)
$form.BackColor = $RENK.Zemin
$form.Font = New-Object Drawing.Font('Segoe UI', 9)

$anaDuzen = New-Object System.Windows.Forms.TableLayoutPanel
$anaDuzen.Dock = [System.Windows.Forms.DockStyle]::Fill
$anaDuzen.ColumnCount = 1
$anaDuzen.RowCount = 3
$anaDuzen.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 116))) | Out-Null
$anaDuzen.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 48))) | Out-Null
$anaDuzen.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 52))) | Out-Null
$form.Controls.Add($anaDuzen)

# ---------- üst bar ----------
$ustPanel = New-Object System.Windows.Forms.Panel
$ustPanel.Size = New-Object Drawing.Size(1210,116)
$ustPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$ustPanel.Padding = New-Object System.Windows.Forms.Padding(16, 12, 16, 8)

$baslik = New-Object System.Windows.Forms.Label
$baslik.Text = 'Cihazların çalışma özeti'
$baslik.Font = New-Object Drawing.Font('Segoe UI', 15, [Drawing.FontStyle]::Bold)
$baslik.ForeColor = $RENK.Metin
$baslik.AutoSize = $true
$baslik.Location = New-Object Drawing.Point(0, 0)
$ustPanel.Controls.Add($baslik)

$altBaslik = New-Object System.Windows.Forms.Label
$altBaslik.Text = 'Yalnızca kayıtlı ve onay vermiş cihazlar görünür. Varsayılan kapsam: uygulama adı, kategori ve süre.'
$altBaslik.ForeColor = $RENK.Soluk
$altBaslik.AutoSize = $true
$altBaslik.Location = New-Object Drawing.Point(2, 30)
$ustPanel.Controls.Add($altBaslik)

$gunEtiketi = New-Object System.Windows.Forms.Label
$gunEtiketi.Text = 'Gün:'
$gunEtiketi.AutoSize = $true
$gunEtiketi.ForeColor = $RENK.Soluk
$gunEtiketi.Location = New-Object Drawing.Point(2, 56)
$ustPanel.Controls.Add($gunEtiketi)

$script:GunKutusu = New-Object System.Windows.Forms.ComboBox
$script:GunKutusu.DropDownStyle = 'DropDownList'
$script:GunKutusu.Width = 150
$script:GunKutusu.Location = New-Object Drawing.Point(36, 52)
$ustPanel.Controls.Add($script:GunKutusu)

$disaAktarDugmesi = New-Object System.Windows.Forms.Button
$disaAktarDugmesi.Text = 'CSV dışa aktar'
$disaAktarDugmesi.Width = 130
$disaAktarDugmesi.Height = 30
$disaAktarDugmesi.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$disaAktarDugmesi.Location = New-Object Drawing.Point(930, 50)
$ustPanel.Controls.Add($disaAktarDugmesi)

$yenileDugmesi = New-Object System.Windows.Forms.Button
$yenileDugmesi.Text = 'Şimdi yenile'
$yenileDugmesi.Width = 110
$yenileDugmesi.Height = 30
$yenileDugmesi.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$yenileDugmesi.Location = New-Object Drawing.Point(1070, 50)
$ustPanel.Controls.Add($yenileDugmesi)
$script:ToplamEtiketi = New-Object System.Windows.Forms.Label
$script:ToplamEtiketi.Location = New-Object Drawing.Point(2, 86)
$script:ToplamEtiketi.Size = New-Object Drawing.Size(1170, 26)
$script:ToplamEtiketi.Font = New-Object Drawing.Font('Segoe UI', 11, [Drawing.FontStyle]::Bold)
$script:ToplamEtiketi.ForeColor = $RENK.Basari
$ustPanel.Controls.Add($script:ToplamEtiketi)
[void]$anaDuzen.Controls.Add($ustPanel, 0, 0)

# ---------- cihaz karşılaştırma tablosu ----------
$cihazGrubu = New-Object System.Windows.Forms.GroupBox
$cihazGrubu.Text = 'Cihazlar'
$cihazGrubu.Dock = [System.Windows.Forms.DockStyle]::Fill
$cihazGrubu.Margin = New-Object System.Windows.Forms.Padding(16, 4, 16, 6)

$script:CihazOzeti = New-Object System.Windows.Forms.Label
$script:CihazOzeti.Dock = [System.Windows.Forms.DockStyle]::Top
$script:CihazOzeti.Height = 24
$script:CihazOzeti.Padding = New-Object System.Windows.Forms.Padding(8, 4, 8, 0)
$script:CihazOzeti.ForeColor = $RENK.Soluk
$cihazGrubu.Controls.Add($script:CihazOzeti)

$script:CihazIzgarasi = New-Object System.Windows.Forms.DataGridView
$script:CihazIzgarasi.Dock = [System.Windows.Forms.DockStyle]::Fill
Ayarla-PanelIzgara $script:CihazIzgarasi
Ekle-PanelSutunu -Izgara $script:CihazIzgarasi -Baslik 'Cihaz' -Ozellik 'Cihaz' -Genislik 190
Ekle-PanelSutunu -Izgara $script:CihazIzgarasi -Baslik 'Durum' -Ozellik 'Durum' -Genislik 85
Ekle-PanelSutunu -Izgara $script:CihazIzgarasi -Baslik 'Çalışma' -Ozellik 'Calisma' -Genislik 85 -Hizalama ([System.Windows.Forms.DataGridViewContentAlignment]::MiddleRight)
Ekle-PanelSutunu -Izgara $script:CihazIzgarasi -Baslik 'Hedef' -Ozellik 'Hedef' -Genislik 80 -Hizalama ([System.Windows.Forms.DataGridViewContentAlignment]::MiddleRight)
Ekle-PanelSutunu -Izgara $script:CihazIzgarasi -Baslik '%' -Ozellik 'Yuzde' -Genislik 55 -Hizalama ([System.Windows.Forms.DataGridViewContentAlignment]::MiddleRight)
Ekle-PanelSutunu -Izgara $script:CihazIzgarasi -Baslik '' -Ozellik 'Cubuk' -Genislik 130
Ekle-PanelSutunu -Izgara $script:CihazIzgarasi -Baslik 'Diğer' -Ozellik 'Diger' -Genislik 75 -Hizalama ([System.Windows.Forms.DataGridViewContentAlignment]::MiddleRight)
Ekle-PanelSutunu -Izgara $script:CihazIzgarasi -Baslik 'Boşta' -Ozellik 'Bosta' -Genislik 75 -Hizalama ([System.Windows.Forms.DataGridViewContentAlignment]::MiddleRight)
Ekle-PanelSutunu -Izgara $script:CihazIzgarasi -Baslik 'Son veri' -Ozellik 'SonVeri' -Genislik 110
Ekle-PanelSutunu -Izgara $script:CihazIzgarasi -Baslik 'İzleyici' -Ozellik 'Izleyici' -Genislik 80
Ekle-PanelSutunu -Izgara $script:CihazIzgarasi -Baslik 'Onay' -Ozellik 'Onay' -Genislik 110
$script:CihazIzgarasi.Columns['Cihaz'].AutoSizeMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::Fill
# Veri baglama (BindingSource + DataPropertyName) PowerShell nesnelerinde hucreleri
# bos birakiyor: satir sayisi doğru, iceriği boş. Satirlar elle doldurulur.
$cihazGrubu.Controls.Add($script:CihazIzgarasi)
$script:CihazOzeti.BringToFront()

$script:CihazBosEtiket = New-Object System.Windows.Forms.Label
$script:CihazBosEtiket.Dock = [System.Windows.Forms.DockStyle]::Fill
$script:CihazBosEtiket.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$script:CihazBosEtiket.ForeColor = $RENK.Soluk
$script:CihazBosEtiket.BackColor = [Drawing.Color]::White
$script:CihazBosEtiket.Text = 'Henüz kayıtlı cihaz yok. cihaz-ekle.ps1 ile eşleşme kodu üret, kullanıcı kendi bilgisayarında girsin.'
$cihazGrubu.Controls.Add($script:CihazBosEtiket)
[void]$anaDuzen.Controls.Add($cihazGrubu, 0, 1)

# ---------- alt bölüm: uygulama kırılımı + trend + hedef ----------
$altDuzen = New-Object System.Windows.Forms.TableLayoutPanel
$altDuzen.Dock = [System.Windows.Forms.DockStyle]::Fill
$altDuzen.ColumnCount = 2
$altDuzen.RowCount = 1
$altDuzen.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 58))) | Out-Null
$altDuzen.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 42))) | Out-Null

$uygulamaGrubu = New-Object System.Windows.Forms.GroupBox
$uygulamaGrubu.Text = 'Seçili cihaz — neye ne kadar'
$uygulamaGrubu.Dock = [System.Windows.Forms.DockStyle]::Fill
$uygulamaGrubu.Margin = New-Object System.Windows.Forms.Padding(16, 2, 8, 8)
$script:UygulamaIzgarasi = New-Object System.Windows.Forms.DataGridView
$script:UygulamaIzgarasi.Dock = [System.Windows.Forms.DockStyle]::Fill
Ayarla-PanelIzgara $script:UygulamaIzgarasi
Ekle-PanelSutunu -Izgara $script:UygulamaIzgarasi -Baslik 'Uygulama' -Ozellik 'Uygulama' -Genislik 240
Ekle-PanelSutunu -Izgara $script:UygulamaIzgarasi -Baslik 'Süre' -Ozellik 'Sure' -Genislik 85 -Hizalama ([System.Windows.Forms.DataGridViewContentAlignment]::MiddleRight)
Ekle-PanelSutunu -Izgara $script:UygulamaIzgarasi -Baslik 'Kategori' -Ozellik 'Kategori' -Genislik 110
$script:UygulamaIzgarasi.Columns['Uygulama'].AutoSizeMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::Fill
$uygulamaGrubu.Controls.Add($script:UygulamaIzgarasi)
$gizlilikNotu = New-Object System.Windows.Forms.Label
$gizlilikNotu.Dock = [System.Windows.Forms.DockStyle]::Bottom
$gizlilikNotu.Height = 24
$gizlilikNotu.Padding = New-Object System.Windows.Forms.Padding(8, 4, 8, 0)
$gizlilikNotu.Text = 'Pencere başlıkları ve adresler gönderilmez; yalnızca uygulama süreleri.'
$gizlilikNotu.ForeColor = $RENK.Soluk
$uygulamaGrubu.Controls.Add($gizlilikNotu)
$script:SenkronEtiketi = New-Object System.Windows.Forms.Label
$script:SenkronEtiketi.Dock = 'Top'
$script:SenkronEtiketi.Height = 90
$script:SenkronEtiketi.Padding = New-Object System.Windows.Forms.Padding(8)
$script:SenkronEtiketi.ForeColor = $RENK.Soluk
$uygulamaGrubu.Controls.Add($script:SenkronEtiketi)
[void]$altDuzen.Controls.Add($uygulamaGrubu, 0, 0)

$sagPanel = New-Object System.Windows.Forms.TableLayoutPanel
$sagPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$sagPanel.ColumnCount = 1
$sagPanel.RowCount = 2
$sagPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100))) | Out-Null
$sagPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 140))) | Out-Null

$trendGrubu = New-Object System.Windows.Forms.GroupBox
$trendGrubu.Text = 'Son 14 gün'
$trendGrubu.Dock = [System.Windows.Forms.DockStyle]::Fill
$trendGrubu.Margin = New-Object System.Windows.Forms.Padding(8, 2, 16, 4)
$script:TrendIzgarasi = New-Object System.Windows.Forms.DataGridView
$script:TrendIzgarasi.Dock = [System.Windows.Forms.DockStyle]::Fill
Ayarla-PanelIzgara $script:TrendIzgarasi
Ekle-PanelSutunu -Izgara $script:TrendIzgarasi -Baslik 'Tarih' -Ozellik 'Tarih' -Genislik 95
Ekle-PanelSutunu -Izgara $script:TrendIzgarasi -Baslik 'Çalışma' -Ozellik 'Calisma' -Genislik 80 -Hizalama ([System.Windows.Forms.DataGridViewContentAlignment]::MiddleRight)
Ekle-PanelSutunu -Izgara $script:TrendIzgarasi -Baslik '%' -Ozellik 'Yuzde' -Genislik 55 -Hizalama ([System.Windows.Forms.DataGridViewContentAlignment]::MiddleRight)
Ekle-PanelSutunu -Izgara $script:TrendIzgarasi -Baslik '' -Ozellik 'Cubuk' -Genislik 120
$script:TrendIzgarasi.Columns['Cubuk'].AutoSizeMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::Fill
$trendGrubu.Controls.Add($script:TrendIzgarasi)
[void]$sagPanel.Controls.Add($trendGrubu, 0, 0)

$hedefGrubu = New-Object System.Windows.Forms.GroupBox
$hedefGrubu.Text = 'Seçili cihazın ayarları'
$hedefGrubu.Dock = [System.Windows.Forms.DockStyle]::Fill
$hedefGrubu.Margin = New-Object System.Windows.Forms.Padding(8, 2, 16, 8)
$script:HedefKutusu = New-Object System.Windows.Forms.NumericUpDown
$script:HedefKutusu.Location = New-Object Drawing.Point(12, 26)
$script:HedefKutusu.Width = 90
$script:HedefKutusu.Minimum = 0
$script:HedefKutusu.Maximum = 1440
$script:HedefKutusu.Increment = 15
$hedefGrubu.Controls.Add($script:HedefKutusu)
$hedefBirim = New-Object System.Windows.Forms.Label
$hedefBirim.Text = 'dakika (0 = cihazın kendi hedefi)'
$hedefBirim.AutoSize = $true
$hedefBirim.ForeColor = $RENK.Soluk
$hedefBirim.Location = New-Object Drawing.Point(110, 30)
$hedefGrubu.Controls.Add($hedefBirim)
$hedefKaydet = New-Object System.Windows.Forms.Button
$hedefKaydet.Text = 'Kaydet'
$hedefKaydet.Width = 90
$hedefKaydet.Height = 28
$hedefKaydet.Location = New-Object Drawing.Point(12, 100)
$hedefGrubu.Controls.Add($hedefKaydet)
$script:AktifKutusu = New-Object System.Windows.Forms.CheckBox
$script:AktifKutusu.Text = 'Cihaz aktif'
$script:AktifKutusu.AutoSize = $true
$script:AktifKutusu.Location = New-Object Drawing.Point(12, 65)
$hedefGrubu.Controls.Add($script:AktifKutusu)
$script:KuralYetkiKutusu = New-Object System.Windows.Forms.CheckBox
$script:KuralYetkiKutusu.Text = 'Ortak kurallara yazabilir'
$script:KuralYetkiKutusu.AutoSize = $true
$script:KuralYetkiKutusu.Location = New-Object Drawing.Point(130, 65)
$hedefGrubu.Controls.Add($script:KuralYetkiKutusu)
[void]$sagPanel.Controls.Add($hedefGrubu, 0, 1)
[void]$altDuzen.Controls.Add($sagPanel, 1, 0)
$sekmeler = New-Object System.Windows.Forms.TabControl
$sekmeler.Dock = 'Fill'
$ozetSekmesi = New-Object System.Windows.Forms.TabPage
$ozetSekmesi.Text = 'Cihaz ayrıntısı'
$ozetSekmesi.Controls.Add($altDuzen)
$kuralSekmesi = New-Object System.Windows.Forms.TabPage
$kuralSekmesi.Text = 'Ortak kurallar'
$sekmeler.TabPages.Add($ozetSekmesi)
$sekmeler.TabPages.Add($kuralSekmesi)
if ($Sekme -eq 'Kurallar') { $sekmeler.SelectedTab = $kuralSekmesi }
[void]$anaDuzen.Controls.Add($sekmeler, 0, 2)

$script:KuralIzgarasi = New-Object System.Windows.Forms.DataGridView
$script:KuralIzgarasi.Dock = 'Fill'
Ayarla-PanelIzgara $script:KuralIzgarasi
Ekle-PanelSutunu $script:KuralIzgarasi 'Öğe' 'Oge' 550
Ekle-PanelSutunu $script:KuralIzgarasi 'Tür' 'Tur' 160
Ekle-PanelSutunu $script:KuralIzgarasi 'Karar' 'Karar' 160
$script:KuralIzgarasi.Columns['Oge'].AutoSizeMode = 'Fill'
$kuralSekmesi.Controls.Add($script:KuralIzgarasi)

$kuralSeridi = New-Object System.Windows.Forms.FlowLayoutPanel
$kuralSeridi.Dock = 'Bottom'
$kuralSeridi.Height = 82
$kuralSeridi.Padding = New-Object System.Windows.Forms.Padding(8)
$script:KuralOge = New-Object System.Windows.Forms.TextBox
$script:KuralOge.Width = 350
$script:KuralOge.MaxLength = 160
$script:KuralTur = New-Object System.Windows.Forms.ComboBox
$script:KuralTur.DropDownStyle = 'DropDownList'
$script:KuralTur.Width = 130
$script:KuralTur.Items.AddRange(@('Süreç','Tam başlık','Alan adı'))
$script:KuralTur.SelectedIndex = 0
$script:KuralKarar = New-Object System.Windows.Forms.ComboBox
$script:KuralKarar.DropDownStyle = 'DropDownList'
$script:KuralKarar.Width = 130
$script:KuralKarar.Items.AddRange(@('İzinli','İzinsiz','Belirsiz'))
$script:KuralKarar.SelectedIndex = 0
$kuralKaydet = New-Object System.Windows.Forms.Button
$kuralKaydet.Text = 'Ekle / güncelle'
$kuralKaydet.Width = 125
$kuralSil = New-Object System.Windows.Forms.Button
$kuralSil.Text = 'Seçili kuralı sil'
$kuralSil.Width = 125
$kuralNotu = New-Object System.Windows.Forms.Label
$kuralNotu.Text = 'Başlıkta tam pencere adını kullan. Değişiklikler cihazlara sonraki senkronda uygulanır.'
$kuralNotu.AutoSize = $true
foreach ($c in @($script:KuralOge,$script:KuralTur,$script:KuralKarar,$kuralKaydet,$kuralSil,$kuralNotu)) { $kuralSeridi.Controls.Add($c) }
$kuralSeridi.SetFlowBreak($kuralSil,$true)
$kuralSekmesi.Controls.Add($kuralSeridi)

function Yenile-Kurallar {
    $script:KuralIzgarasi.Rows.Clear()
    foreach ($k in @(Get-MerkezKuralSatirlari (Get-MerkezKurallari $script:KuralYolu))) {
        $turAdi = @{surec='Süreç';baslik='Tam başlık';alanadi='Alan adı'}[$k.tur]
        $kararAdi = @{calisma='İzinli';yasakli='İzinsiz';belirsiz='Belirsiz'}[$k.karar]
        $i = $script:KuralIzgarasi.Rows.Add($k.oge,$turAdi,$kararAdi)
        $script:KuralIzgarasi.Rows[$i].Tag = $k
    }
}
$script:KuralIzgarasi.Add_SelectionChanged({
    if ($script:KuralIzgarasi.SelectedRows.Count -eq 0) { return }
    $k = $script:KuralIzgarasi.SelectedRows[0].Tag
    if ($null -eq $k) { return }
    $script:KuralOge.Text = $k.oge
    $script:KuralTur.SelectedIndex = [array]::IndexOf(@('surec','baslik','alanadi'),$k.tur)
    $script:KuralKarar.SelectedIndex = [array]::IndexOf(@('calisma','yasakli','belirsiz'),$k.karar)
})
$kuralKaydet.Add_Click({
    try {
        $tur = @('surec','baslik','alanadi')[$script:KuralTur.SelectedIndex]
        $karar = @('calisma','yasakli','belirsiz')[$script:KuralKarar.SelectedIndex]
        Save-MerkezKuralKarari $script:KuralYolu $script:KuralOge.Text.Trim() $tur $karar
        Yenile-Kurallar
        $script:DurumEtiketi.Text = 'Ortak kural kaydedildi.'
    } catch { $script:DurumEtiketi.Text = $_.Exception.Message }
})
$kuralSil.Add_Click({
    if ($script:KuralIzgarasi.SelectedRows.Count -eq 0) { return }
    $k = $script:KuralIzgarasi.SelectedRows[0].Tag
    if ($null -eq $k) { return }
    try {
        Save-MerkezKuralKarari $script:KuralYolu $k.oge $k.tur $k.karar -Sil
        Yenile-Kurallar
        $script:DurumEtiketi.Text = 'Kural silindi; cihazlara sonraki senkronda uygulanacak.'
    } catch { $script:DurumEtiketi.Text = $_.Exception.Message }
})

$durumCubugu = New-Object System.Windows.Forms.StatusStrip
$script:DurumEtiketi = New-Object System.Windows.Forms.ToolStripStatusLabel
$script:DurumEtiketi.Spring = $true
$script:DurumEtiketi.TextAlign = [Drawing.ContentAlignment]::MiddleLeft
[void]$durumCubugu.Items.Add($script:DurumEtiketi)
$form.Controls.Add($durumCubugu)

Yenile-Kurallar
# ---------- veri akışı ----------
function Doldur-GunListesi {
    $script:Yukleniyor = $true
    try {
        $secili = [string]$script:GunKutusu.SelectedItem
        $script:GunKutusu.Items.Clear()
        [void]$script:GunKutusu.Items.Add('Bugün')
        foreach ($klasor in @(Get-MerkezGunKlasorleri -VeriKlasoru $script:VeriKlasoru | Sort-Object Name -Descending)) {
            [void]$script:GunKutusu.Items.Add($klasor.Name)
        }
        if (-not [string]::IsNullOrWhiteSpace($secili) -and $script:GunKutusu.Items.Contains($secili)) {
            $script:GunKutusu.SelectedItem = $secili
        }
        else { $script:GunKutusu.SelectedIndex = 0 }
    }
    finally { $script:Yukleniyor = $false }
}

function Get-SeciliCihazId {
    # Cihaz kimligi satirin Tag'inde tutulur (gorunur sutunlarda yer kaplamasin diye)
    if ($script:CihazIzgarasi.SelectedRows.Count -eq 0) { return '' }
    $etiket = $script:CihazIzgarasi.SelectedRows[0].Tag
    if ($null -eq $etiket) { return '' }
    return [string]$etiket
}

function Goster-SeciliCihaz {
    $kimlik = Get-SeciliCihazId
    $script:UygulamaIzgarasi.Rows.Clear()
    $script:TrendIzgarasi.Rows.Clear()
    if ([string]::IsNullOrWhiteSpace($kimlik)) {
        $uygulamaGrubu.Text = 'Seçili cihaz — neye ne kadar'
        return
    }
    $satir = @($script:Satirlar | Where-Object { $_.cihazId -eq $kimlik } | Select-Object -First 1)[0]
    $uygulamalar = @(Get-MerkezUygulamaKirilimi -VeriKlasoru $script:VeriKlasoru -CihazId $kimlik -Tarih $script:SeciliTarih -EnFazla 15)
    foreach ($uygulama in $uygulamalar) {
        [void]$script:UygulamaIzgarasi.Rows.Add(
            [string](Get-DagitikDeger $uygulama 'ad' ''),
            (Format-PanelDakika (Get-DagitikDeger $uygulama 'dakika' 0)),
            [string](Get-DagitikDeger $uygulama 'kategori' 'belirsiz'))
    }
    if ($null -ne $satir) {
        $sn = $satir.senkron
        if ($null -eq $sn) { $script:SenkronEtiketi.Text = 'Bu cihaz henüz senkron ayrıntısı bildirmedi.' }
        else {
            $bekleyen = Get-DagitikDeger $sn 'bekleyenKarar' $null
            $son = Get-MerkezZaman $satir.sonGorulmeUtc
            $zaman = $(if ($null -eq $son) { 'yok' } else { $son.ToLocalTime().ToString('dd.MM HH:mm') })
            $hata = [string](Get-DagitikDeger $sn 'hata' '')
            $script:SenkronEtiketi.Text = "Son başarılı gönderim: $zaman | Bekleyen karar (son bildirim): $bekleyen" + [Environment]::NewLine + "Son bildirilen hata: $(if ($hata) { $hata } else { 'yok' })"
        }
        $script:AktifKutusu.Checked = $satir.aktif
        $script:KuralYetkiKutusu.Checked = $satir.kuralYazabilir
        $uygulamaGrubu.Text = ('Seçili cihaz — {0} ({1} uygulama)' -f $satir.ad, $uygulamalar.Count)
        $script:HedefKutusu.Value = [decimal][math]::Min(1440, [math]::Max(0, [int](Get-DagitikDeger (Get-PanelCihazKaydi $kimlik) 'hedefDk' 0)))
    }

    $bitis = Get-Date
    if (-not [string]::IsNullOrWhiteSpace($script:SeciliTarih)) {
        [datetime]$gun = [datetime]::MinValue
        if ([datetime]::TryParseExact($script:SeciliTarih, 'yyyy-MM-dd',
                [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$gun)) {
            $bitis = $gun
        }
    }
    $trend = @(Get-MerkezTrend -VeriKlasoru $script:VeriKlasoru -CihazId $kimlik -Gun 14 -Bitis $bitis)
    foreach ($gun in @($trend | Sort-Object tarih -Descending)) {
        [void]$script:TrendIzgarasi.Rows.Add(
            $gun.tarih,
            (Format-PanelDakika $gun.calismaDk),
            ('%{0}' -f $gun.yuzde),
            (Get-PanelCubuk $gun.yuzde))
    }
}

function Get-PanelCihazKaydi {
    param([string]$CihazId)
    $ayar = Get-PanelAyari
    if ($null -eq $ayar) { return $null }
    return @(@(Get-DagitikDeger $ayar 'cihazlar' @()) | Where-Object { [string](Get-DagitikDeger $_ 'id' '') -eq $CihazId } | Select-Object -First 1)[0]
}

function Yenile-Panel {
    $toplam = Get-MerkezPanelToplami (Get-PanelAyari) $script:VeriKlasoru $script:SeciliTarih
    $script:ToplamEtiketi.Text = ('{0} · Ortak toplam {1} / {2} dk · %{3} · Kalan {4} dk · {5} cihazın katkısı' -f $toplam.tarih,$toplam.toplamDk,$toplam.hedefDk,$toplam.yuzde,$toplam.kalanDk,$toplam.cihazSayisi)
    $oncekiSecim = Get-SeciliCihazId
    $script:Satirlar = @(Get-PanelSatirlari)
    $script:CihazIzgarasi.Rows.Clear()
    foreach ($kayit in $script:Satirlar) {
        $indeksYeni = $script:CihazIzgarasi.Rows.Add(
            $kayit.ad,
            $(if (-not $kayit.aktif) { 'Pasif' } else { Format-PanelDurum $kayit.durum }),
            (Format-PanelDakika $kayit.calismaDk),
            (Format-PanelDakika $kayit.hedefDk),
            ('%{0}' -f $kayit.yuzde),
            (Get-PanelCubuk $kayit.yuzde),
            (Format-PanelDakika $kayit.digerDk),
            (Format-PanelDakika $kayit.bostaDk),
            (Format-PanelSessizlik $kayit.sessizDk),
            $(if ($kayit.izleyiciCalisiyor) { 'çalışıyor' } else { '—' }),
            $(if ([string]::IsNullOrWhiteSpace($kayit.onayUtc)) { '—' } else { (Get-MerkezZaman $kayit.onayUtc).ToLocalTime().ToString('dd.MM.yyyy') })
        )
        $yeniSatir = $script:CihazIzgarasi.Rows[$indeksYeni]
        $yeniSatir.Tag = $kayit.cihazId
        if ($kayit.durum -eq 'sessiz') { $yeniSatir.DefaultCellStyle.ForeColor = $RENK.Tehlike }
        elseif ($kayit.durum -eq 'veri yok') { $yeniSatir.DefaultCellStyle.ForeColor = $RENK.Soluk }
    }
    $script:CihazBosEtiket.Visible = ($script:Satirlar.Count -eq 0)

    if ($script:CihazIzgarasi.Rows.Count -gt 0) {
        $indeks = 0
        if (-not [string]::IsNullOrWhiteSpace($oncekiSecim)) {
            for ($i = 0; $i -lt $script:CihazIzgarasi.Rows.Count; $i++) {
                if ([string]$script:CihazIzgarasi.Rows[$i].Tag -eq $oncekiSecim) { $indeks = $i; break }
            }
        }
        $script:CihazIzgarasi.ClearSelection()
        $script:CihazIzgarasi.Rows[$indeks].Selected = $true
        $script:CihazIzgarasi.CurrentCell = $script:CihazIzgarasi.Rows[$indeks].Cells[0]
    }

    $sessiz = @($script:Satirlar | Where-Object { $_.durum -eq 'sessiz' }).Count
    $veriYok = @($script:Satirlar | Where-Object { $_.durum -eq 'veri yok' }).Count
    $ozet = ('{0} cihaz · okuma {1}' -f $script:Satirlar.Count, (Get-Date).ToString('HH:mm:ss'))
    if ($sessiz -gt 0) { $ozet += (' · {0} cihaz {1} saattir sessiz' -f $sessiz, $SessizlikSaati) }
    if ($veriYok -gt 0) { $ozet += (' · {0} cihaz hiç veri göndermedi' -f $veriYok) }
    $script:CihazOzeti.Text = $ozet
    $script:DurumEtiketi.Text = ('Veri klasörü: {0} · otomatik yenileme {1} sn' -f $script:VeriKlasoru, $YenilemeSn)
    Goster-SeciliCihaz
}

function DisaAktar-Csv {
    if ($script:Satirlar.Count -eq 0) {
        $script:DurumEtiketi.Text = 'Dışa aktarılacak cihaz yok.'
        return
    }
    $alanlar = @('ad', 'durum', 'tarih', 'calismaDk', 'hedefDk', 'yuzde', 'digerDk', 'bostaDk', 'sessizDk', 'izleyiciCalisiyor', 'onayUtc')
    $basliklar = @('Cihaz', 'Durum', 'Tarih', 'Calisma dk', 'Hedef dk', 'Yuzde', 'Diger dk', 'Bosta dk', 'Sessiz dk', 'Izleyici', 'Onay')
    $metin = ConvertTo-MerkezCsv -Satirlar $script:Satirlar -Alanlar $alanlar -Basliklar $basliklar
    $etiket = $(if ([string]::IsNullOrWhiteSpace($script:SeciliTarih)) { (Get-Date).ToString('yyyy-MM-dd') } else { $script:SeciliTarih })
    $yol = Join-Path ([Environment]::GetFolderPath('Desktop')) ("calisma-ozeti-$etiket.csv")
    try {
        [IO.File]::WriteAllText($yol, $metin, (New-Object Text.UTF8Encoding($true)))
        $script:DurumEtiketi.Text = ('CSV kaydedildi: {0}' -f $yol)
    }
    catch {
        $script:DurumEtiketi.Text = ('CSV yazilamadi: {0}' -f $_.Exception.Message)
    }
}

function Kaydet-Hedef {
    $kimlik = Get-SeciliCihazId
    if ([string]::IsNullOrWhiteSpace($kimlik)) { return }
    try {
        Set-MerkezCihazAyari $script:AyarYolu $kimlik $script:AktifKutusu.Checked $script:KuralYetkiKutusu.Checked ([int]$script:HedefKutusu.Value)
        Yenile-Panel
        $script:DurumEtiketi.Text = 'Cihaz ayarları kaydedildi.'
    } catch { $script:DurumEtiketi.Text = $_.Exception.Message }
}
$script:CihazIzgarasi.Add_SelectionChanged({ Goster-SeciliCihaz })
$script:GunKutusu.Add_SelectedIndexChanged({
    if ($script:Yukleniyor) { return }
    $secim = [string]$script:GunKutusu.SelectedItem
    $script:SeciliTarih = $(if ($secim -eq 'Bugün') { '' } else { $secim })
    Yenile-Panel
})
$yenileDugmesi.Add_Click({ Doldur-GunListesi; Yenile-Panel; Yenile-Kurallar })
$disaAktarDugmesi.Add_Click({ DisaAktar-Csv })
$hedefKaydet.Add_Click({ Kaydet-Hedef })

$zamanlayici = New-Object System.Windows.Forms.Timer
$zamanlayici.Interval = $YenilemeSn * 1000
$zamanlayici.Add_Tick({ if ([string]::IsNullOrWhiteSpace($script:SeciliTarih)) { Yenile-Panel } })
$form.Add_Shown({
    Doldur-GunListesi
    Yenile-Panel
    $zamanlayici.Start()
})
$form.Add_FormClosing({ $zamanlayici.Stop() })

if ($env:ARAYUZ_ONIZLEME) {
    Doldur-GunListesi
    Yenile-Panel
    $form.ShowInTaskbar = $false
    $form.StartPosition = 'Manual'
    $form.Location = New-Object Drawing.Point(-32000, -32000)
    $form.Show()
    [System.Windows.Forms.Application]::DoEvents()
    $bmp = New-Object System.Drawing.Bitmap($form.Width, $form.Height)
    $form.DrawToBitmap($bmp, (New-Object System.Drawing.Rectangle(0, 0, $form.Width, $form.Height)))
    $bmp.Save($env:ARAYUZ_ONIZLEME, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    $form.Hide()
    $form.Dispose()
    return
}

[void]$form.ShowDialog()
