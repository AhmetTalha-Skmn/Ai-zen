# ============================================================
#  Arayuz onizlemesi: pencereleri ekrana cikarmadan PNG'ye cizer.
#  Kullanim: powershell -NoProfile -ExecutionPolicy Bypass -File hatirlatici/onizleme.ps1 [-Klasor <dizin>]
#  UTF-8 BOM ile kaydedilir (ornek metinler Turkce).
# ============================================================
param([string]$Klasor = (Join-Path $env:TEMP 'arayuz-onizleme'))
$ErrorActionPreference = 'SilentlyContinue'
$hDir = $PSScriptRoot; if (-not $hDir) { $hDir = Split-Path $MyInvocation.MyCommand.Path -Parent }
[void][IO.Directory]::CreateDirectory($Klasor)
$ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

# Kontrol paneli ve rapor penceresi: gercek scriptler, gercek veriyle, gosterilmeden
foreach ($s in 'kontrol', 'rapor-penceresi', 'ayarlar-penceresi', 'wiki-penceresi') {
    $env:ARAYUZ_ONIZLEME = Join-Path $Klasor "$s.png"
    & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $hDir "$s.ps1") | Out-Null
}
# Rapor penceresinin Incelenecek sekmesi (karar seridi)
$env:ARAYUZ_ONIZLEME = Join-Path $Klasor 'rapor-incelenecek.png'
& $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $hDir 'rapor-penceresi.ps1') -Sekme 4 | Out-Null
$env:ARAYUZ_ONIZLEME = $null

# Uyari ve engel: ayni tema fonksiyonu, ornek veriyle (gercek scriptler ses calar ve log yazar)
. (Join-Path $hDir 'tema.ps1')
$alan = New-Object System.Drawing.Rectangle(0, 0, 900, 620)
$u = Tema-TamEkranKart -Alan $alan -Vurgu (Tema-Renk '#D97706') -Baslik 'İkinci uyarı. 45 dakika daha geçti.' -Yuzde 16 `
    -Satirlar @(@('Bugün', '38 / 240 dk  ·  %16'), @('Kalan', '202 dk'), @('Seri', '0 gün'), @('Şu an', 'TFTClient-Win64-Shipping'), @('Sıradaki', 'Çalışma oturumuna dön')) `
    -Dugmeler @('Çalışmaya başla', '30 dk ertele (2 hak)', 'Vazgeçtim') -Turler @('birincil', 'ikincil', 'tehlike')
$u.Durum.Text = 'Seçim 12 saniye sonra açılacak.'
foreach ($b in $u.Dugmeler) { $b.Enabled = $false }
Tema-Onizleme $u.Form (Join-Path $Klasor 'uyari.png')

# Ekran kilidi kapaliyken ayni uyari: kapatilabilir normal pencere
$p = Tema-TamEkranKart -Alan $alan -Vurgu (Tema-Renk '#D97706') -Baslik 'İkinci uyarı. 45 dakika daha geçti.' -Yuzde 16 `
    -Satirlar @(@('Bugün', '38 / 240 dk  ·  %16'), @('Kalan', '202 dk'), @('Seri', '0 gün'), @('Şu an', 'chrome'), @('Sıradaki', 'Çalışma oturumuna dön')) `
    -Dugmeler @('Çalışmaya başla', '30 dk ertele (2 hak)', 'Vazgeçtim') -Turler @('birincil', 'ikincil', 'tehlike') -Pencere
$p.Form.Text = 'Aizen · hatırlatma'
$p.Durum.ForeColor = $TEMA.Soluk; $p.Durum.Text = 'Pencereyi kapatabilirsin; bir sonraki hatırlatma 45 dk sonra gelir.'
Tema-Onizleme $p.Form (Join-Path $Klasor 'uyari-pencere.png')

$e = Tema-TamEkranKart -Alan $alan -Vurgu $TEMA.Tehlike -Baslik 'Çalışma periyodundasın.' `
    -AltBaslik 'Bu süre çalışma olarak sayılmıyor. Devam etmek için birini seç.' `
    -Satirlar @(@('Yasaklı uygulama', 'LeagueClientUx'), @('Pencere', 'League of Legends'), @('Periyot kalan', '32 dk')) `
    -Dugmeler @('Çalışmaya dön', '5 dk mola', 'Periyodu bitir') -Turler @('birincil', 'ikincil', 'tehlike')
$e.Durum.ForeColor = $TEMA.Soluk; $e.Durum.Text = '164 sn sonra kendiliğinden kapanır.'
Tema-Onizleme $e.Form (Join-Path $Klasor 'engel.png')

Get-ChildItem $Klasor -Filter *.png | ForEach-Object { '{0,-22} {1,4} KB' -f $_.Name, [math]::Round($_.Length / 1KB) }
