# ============================================================
#  Aizen -- kontrol paneli. Gorunum: tema.ps1, veri: api.ps1 (Takip-Durum)
#  UTF-8 BOM ile kaydedilir (Turkce metinler).
#  Onizleme: $env:ARAYUZ_ONIZLEME = <png yolu> ise pencereyi gostermeden PNG'ye cizer.
# ============================================================
$ErrorActionPreference = 'SilentlyContinue'
$hDir = $PSScriptRoot; if (-not $hDir) { $hDir = Split-Path $MyInvocation.MyCommand.Path -Parent }
. (Join-Path $hDir 'tema.ps1')
. (Join-Path $hDir 'api.ps1')
. (Join-Path $hDir 'ozellikler.ps1')          # kurulum turu, hatirlatma, ekran kilidi; alan koruyan ayar yazimi
. (Join-Path $hDir 'ayarlar-penceresi.ps1')   # Ayarlar-Penceresi
$ayarD   = Join-Path $hDir 'ayarlar.json'
$durumD  = Join-Path $hDir 'durum.json'
$logD    = Join-Path $hDir 'log.txt'
$aktDir  = Join-Path $hDir 'aktivite'
$perD    = Join-Path $hDir 'periyot.json'
$durD    = Join-Path $hDir 'DUR'
$takipPs = Join-Path $hDir 'takip.ps1'
$testPs  = Join-Path $hDir 'test.ps1'
$vbsYol  = Join-Path $hDir 'gizli.vbs'
$psExe   = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$INV     = [Globalization.CultureInfo]::InvariantCulture

# ayarlar.json'daki tum alanlar korunur (eskiden yalnizca hedef/duraklat yazilip yedekKlasoru gibi alanlar siliniyordu)
function AyarOku { $o = Oz-AyarOku $hDir
    $h = 240; try { if ($o.hedef) { $h = [int]$o.hedef } } catch { }; $o.hedef = $h; $o.duraklat = [string]$o.duraklat
    return $o }
function AyarYaz { param($o) Oz-AyarYaz $hDir $o }
function PerYaz { param([bool]$Aktif, [int]$Dk = 0)
    $o = [ordered]@{ aktif = $Aktif; baslangic = ''; bitis = ''; molaBitis = '' }
    if ($Aktif) { $o.baslangic = (Get-Date).ToString('s'); $o.bitis = (Get-Date).AddMinutes($Dk).ToString('s') }
    ($o | ConvertTo-Json) | Out-File $perD -Encoding utf8 }
function Bilgi { param([string]$Metin, [string]$Baslik = 'Aizen', [string]$Simge = 'Information')
    [void][System.Windows.Forms.MessageBox]::Show($Metin, $Baslik, 'OK', $Simge) }

# ---------- pencere ----------
$f = New-Object System.Windows.Forms.Form
Tema-Pencere $f 'Aizen' 460 804
$f.FormBorderStyle = 'FixedSingle'; $f.MaximizeBox = $false
$X = 16; $G = 428

# Bugun
$k1 = Tema-Kart $f $X 16 $G 112
[void](Tema-Bolum $k1 'Bugün' 20 14)
$lbBuyuk = Tema-Etiket $k1 '' 20 32 240 40 20 -Kalin
$lbSaat  = Tema-Etiket $k1 '' 250 44 158 22 9.5 -Renk $TEMA.Soluk; $lbSaat.TextAlign = 'MiddleRight'
$cub     = Tema-Cubuk $k1 20 78 388 8
$lbAlt   = Tema-Etiket $k1 '' 20 88 388 20 9 -Renk $TEMA.Soluk

# Bugunun aktivitesi
# Pencere boyu buyumez: 1536x864 (%125) ekranda panel zaten ekrani dolduruyor. Kurulum satiri icin
# aktivite karti 8 px kisaldi, takip sistemi karti o kadar uzadi.
$k2 = Tema-Kart $f $X 136 $G 96
[void](Tema-Bolum $k2 'Bugünün aktivitesi' 20 14)
$lbKat = Tema-Etiket $k2 '' 20 34 388 20 9.5 -Kalin
$lbUyg = Tema-Etiket $k2 '' 20 56 388 36 9 -Renk $TEMA.Soluk

# Takip sistemi
$k3 = Tema-Kart $f $X 240 $G 136
[void](Tema-Bolum $k3 'Takip sistemi' 20 14)
$lbSagDurum = Tema-Etiket $k3 '' 228 12 156 20 9 -Kalin; $lbSagDurum.TextAlign = 'MiddleRight'
$nokta = Tema-Nokta $k3 394 17 $TEMA.Basari
$satir = @{}; $yy = 36
foreach ($ad in 'Kurulum', 'Görev', 'İzleyici', 'Duraklatma', 'Periyot') {
    [void](Tema-Etiket $k3 $ad 20 $yy 90 20 9.5 -Renk $TEMA.Soluk)
    $satir[$ad] = Tema-Etiket $k3 '' 112 $yy 296 20 9.5
    $yy += 19 }

# Ayarlar
$k4 = Tema-Kart $f $X 384 $G 150
[void](Tema-Bolum $k4 'Ayarlar' 20 14)
[void](Tema-Etiket $k4 'Günlük hedef' 20 42 125 22)
$nu = New-Object System.Windows.Forms.NumericUpDown
$nu.Location = (Tema-Konum 150 40); $nu.Size = (Tema-Boyut 72 26); $nu.Font = (Tema-Yazi 9.5)
$nu.Minimum = 15; $nu.Maximum = 720; $nu.Increment = 15; $nu.Value = (AyarOku).hedef
$k4.Controls.Add($nu)
$btnHedef = Tema-Dugme $k4 'Kaydet' 230 38 80 30
$lbSaatHedef = Tema-Etiket $k4 '' 318 42 90 22 9 -Renk $TEMA.Soluk
[void](Tema-Etiket $k4 'Duraklat' 20 80 125 22)
$cb = New-Object System.Windows.Forms.ComboBox
$cb.Location = (Tema-Konum 150 78); $cb.Size = (Tema-Boyut 100 26); $cb.DropDownStyle = 'DropDownList'; $cb.FlatStyle = 'Flat'; $cb.Font = (Tema-Yazi 9.5)
[void]$cb.Items.AddRange(@('1 saat', '3 saat', '6 saat', 'Bugünlük', 'Süresiz')); $cb.SelectedIndex = 1
$k4.Controls.Add($cb)
$btnDuraklat = Tema-Dugme $k4 'Duraklat' 258 76 72 30
$btnSurdur   = Tema-Dugme $k4 'Sürdür'   336 76 72 30
[void](Tema-Etiket $k4 'Çalışma periyodu' 20 118 125 22)
$cbPer = New-Object System.Windows.Forms.ComboBox
$cbPer.Location = (Tema-Konum 150 116); $cbPer.Size = (Tema-Boyut 100 26); $cbPer.DropDownStyle = 'DropDownList'; $cbPer.FlatStyle = 'Flat'; $cbPer.Font = (Tema-Yazi 9.5)
[void]$cbPer.Items.AddRange(@('25 dk', '50 dk', '90 dk', '120 dk')); $cbPer.SelectedIndex = 1
$k4.Controls.Add($cbPer)
$btnPerBas = Tema-Dugme $k4 'Başlat' 258 114 72 30
$btnPerBit = Tema-Dugme $k4 'Bitir'  336 114 72 30

# Eylemler
$btnRapor  = Tema-Dugme $f 'Günlük raporu aç' $X 546 ($G - 184) 40 'birincil'
$btnAyar   = Tema-Dugme $f 'Ayarlar' ($X + $G - 176) 546 84 40
$btnYardim = Tema-Dugme $f 'Yardım'  ($X + $G - 84)  546 84 40
$btnSimdi = Tema-Dugme $f 'Şimdi kontrol et'   $X          594 140 34
$btnTest  = Tema-Dugme $f 'Testleri çalıştır'  ($X + 144)  594 140 34
$btnSifir = Tema-Dugme $f 'Sayacı sıfırla'     ($X + 288)  594 140 34
$btnAcil  = Tema-Dugme $f 'ACİL DURDUR · tüm engelleri kapat' $X 636 $G 36 'tehlike'

# Son kayitlar
$k5 = Tema-Kart $f $X 684 $G 104
[void](Tema-Bolum $k5 'Son kayıtlar' 20 12)
$tb = New-Object System.Windows.Forms.TextBox
$tb.Location = (Tema-Konum 20 32); $tb.Size = (Tema-Boyut 388 64); $tb.Multiline = $true; $tb.ReadOnly = $true; $tb.WordWrap = $false
$tb.BorderStyle = 'None'; $tb.BackColor = $TEMA.Kart; $tb.ForeColor = $TEMA.Soluk; $tb.Font = New-Object System.Drawing.Font('Consolas', 8.25)
$k5.Controls.Add($tb)

# ---------- veri ----------
function AktiviteYenile {
    $csv = Join-Path $aktDir "$((Get-Date).ToString('yyyy-MM-dd')).csv"
    if (-not (Test-Path $csv)) { $lbKat.Text = 'Bugün için kayıt yok'; $lbUyg.Text = ''; return }
    # sure kolonu saniyedir; yoksa ornekleme araligi olan 10 sn sayilir
    $sn = @{ calisma = 0; diger = 0; bosta = 0 }; $uy = @{}
    foreach ($r in @(Import-Csv $csv -Delimiter ';' -Encoding UTF8)) {
        $s = 10; if ($r.sure) { $s = [int]$r.sure }
        if ($sn.ContainsKey($r.kategori)) { $sn[$r.kategori] += $s }
        if (-not $uy.ContainsKey($r.uygulama)) { $uy[$r.uygulama] = 0 }; $uy[$r.uygulama] += $s }
    $lbKat.Text = "Çalışma $([math]::Round($sn.calisma / 60)) dk  ·  Diğer $([math]::Round($sn.diger / 60)) dk  ·  Boşta $([math]::Round($sn.bosta / 60)) dk"
    $lbUyg.Text = (($uy.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 3 | ForEach-Object { '{0} {1} dk' -f $_.Key, [math]::Round($_.Value / 60) }) -join '   ·   ')
}
$script:tur = 0
function Yenile {
    # Buyuk sayac TOPLAM'i gosterir (bu makine + merkeze bagli diger cihazlar)
    $dur = Takip-Durum; $s = $dur.saglik; $hedef = $dur.hedef
    $oz = Get-TakipOzellikleri -HatirlaticiKlasoru $hDir
    $dk = [int]$dur.toplamDakika
    $diger = [int]$dur.digerCihazDk
    $lbBuyuk.Text = "$dk / $hedef dk"
    $lbSaat.Text = "$(Tema-Sayi ($dk / 60)) / $(Tema-Sayi ($hedef / 60)) saat"
    $renk = $TEMA.Vurgu; if ($dk -ge $hedef) { $renk = $TEMA.Basari } elseif ($dur.vazgecti) { $renk = $TEMA.Pasif }
    Tema-CubukAyarla $cub $dur.yuzde $renk
    $ek = ''; if ($dur.vazgecti) { $ek = '  ·  bugün vazgeçildi' }
    if ($diger -gt 0) { $ek = "  ·  bu bilgisayar $($dur.dakika) dk$ek" }
    $ert = ''; if ($oz.hatirlatmalar) { $ert = "  ·  Erteleme hakkı $($dur.ertelemeHakki)/3" }
    $lbAlt.Text = "Seri $($dur.seri) gün  ·  %$($dur.yuzde)$ert$ek"
    $lbSaatHedef.Text = "= $(Tema-Sayi ($nu.Value / 60)) saat"
    # aktivite ozeti her dakika (CSV gun icinde binlerce satira cikar)
    if ($script:tur % 6 -eq 0) { AktiviteYenile }
    $script:tur++

    if ($s.durum -eq 'normal') { $lbSagDurum.Text = 'Normal'; $lbSagDurum.ForeColor = $TEMA.Basari; Tema-NoktaAyarla $nokta $TEMA.Basari }
    else { $lbSagDurum.Text = 'Sorun var'; $lbSagDurum.ForeColor = $TEMA.Tehlike; Tema-NoktaAyarla $nokta $TEMA.Tehlike }
    $hatMetin = 'hatırlatma yok'
    if ($oz.hatirlatmaAyarlanabilir) { $hatMetin = "hatırlatma $(Ayar-AcikKapali $oz.hatirlatmalar)" }
    $satir['Kurulum'].Text = "$(Oz-TurAdi $oz.kurulumTuru)  ·  $hatMetin  ·  ekran kilidi $(Ayar-AcikKapali $oz.ekranKilidi)"
    $satir['Görev'].Text = $s.gorev
    $satir['İzleyici'].Text = $s.izleyici
    $pd = 'kapalı'
    if ($s.duraklatma -eq 'sonsuz') { $pd = 'süresiz' }
    elseif ($s.duraklatma) { try { $db = [datetime]::ParseExact($s.duraklatma, 's', $INV); if ((Get-Date) -lt $db) { $pd = "açık · bitiş $($db.ToString('dd.MM HH:mm'))" } else { $pd = 'süresi doldu' } } catch { $pd = $s.duraklatma } }
    $satir['Duraklatma'].Text = $pd
    $P = Tk-Json $perD
    if (Test-Path $durD) {
        $satir['Periyot'].Text = 'ACİL DURDURMA AKTİF · engeller kapalı'; $satir['Periyot'].ForeColor = $TEMA.Tehlike
        $btnAcil.Text = 'Acil durdurmayı kaldır'
    } elseif (-not $oz.ekranKilidi) {
        # Kilit kapaliyken izleyici engel acmaz; periyot baslatmanin anlami yok
        $satir['Periyot'].Text = 'ekran kilidi kapalı · periyotta engel yok'; $satir['Periyot'].ForeColor = $TEMA.Soluk
        $btnAcil.Text = 'ACİL DURDUR · tüm engelleri kapat'
    } elseif ($P -and $P.aktif) {
        $kalan = 0; try { $kalan = [math]::Max([math]::Round(([datetime]::ParseExact($P.bitis, 's', $INV) - (Get-Date)).TotalMinutes), 0) } catch { }
        $satir['Periyot'].Text = "aktif · $kalan dk kaldı · yasaklı uygulama engellenir"; $satir['Periyot'].ForeColor = $TEMA.Basari
        $btnAcil.Text = 'ACİL DURDUR · tüm engelleri kapat'
    } else {
        $perYok = 'yok'; if ($oz.hatirlatmalar) { $perYok = 'yok · uyarılar 45 dk kuralına göre' }
        $satir['Periyot'].Text = $perYok; $satir['Periyot'].ForeColor = $TEMA.Metin
        $btnAcil.Text = 'ACİL DURDUR · tüm engelleri kapat'
    }
    $btnPerBas.Enabled = [bool]$oz.ekranKilidi; $cbPer.Enabled = [bool]$oz.ekranKilidi
    $tb.Text = ((@(Get-Content $logD -Tail 6 -Encoding UTF8) | ForEach-Object { $_ -replace '^\d{4}-\d{2}-\d{2} ', '' }) -join "`r`n")
}

# ---------- olaylar ----------
$nu.Add_ValueChanged({ $lbSaatHedef.Text = "= $(Tema-Sayi ($nu.Value / 60)) saat" })
$btnHedef.Add_Click({ $a = AyarOku; $a.hedef = [int]$nu.Value; AyarYaz $a
    Bilgi "Günlük hedef $($nu.Value) dakika ($(Tema-Sayi ($nu.Value / 60)) saat) olarak kaydedildi." 'Kaydedildi'; Yenile })
# Eskiden bu kod ACIL DURDUR dugmesine bagliydi (ayni degisken adi iki kez kullanilmisti) ve Duraklat dugmesi hicbir sey yapmiyordu
$btnDuraklat.Add_Click({ $a = AyarOku
    switch ($cb.SelectedItem) {
        '1 saat'   { $a.duraklat = (Get-Date).AddHours(1).ToString('s') }
        '3 saat'   { $a.duraklat = (Get-Date).AddHours(3).ToString('s') }
        '6 saat'   { $a.duraklat = (Get-Date).AddHours(6).ToString('s') }
        'Bugünlük' { $a.duraklat = (Get-Date).Date.AddDays(1).ToString('s') }
        'Süresiz'  { $a.duraklat = 'sonsuz' } }
    AyarYaz $a
    $uyariMetni = ''; if ((Get-TakipOzellikleri -HatirlaticiKlasoru $hDir).hatirlatmalar) { $uyariMetni = 'uyarı çıkmaz, ' }
    Bilgi "Duraklatıldı: $($cb.SelectedItem)`r`n`r`nBu süre boyunca $($uyariMetni)sayaç ilerlemez, aktivite kaydı tutulmaz." 'Duraklatıldı'; Yenile })
$btnSurdur.Add_Click({ $a = AyarOku; $a.duraklat = ''; AyarYaz $a; Bilgi 'Takip yeniden aktif.' 'Sürdürüldü'; Yenile })
$btnSimdi.Add_Click({
    Start-Process -FilePath "$env:SystemRoot\System32\wscript.exe" -ArgumentList "//B //Nologo `"$vbsYol`" `"$takipPs`"" -WindowStyle Hidden
    Start-Sleep -Seconds 3; Yenile })
$btnSifir.Add_Click({
    $o = [System.Windows.Forms.MessageBox]::Show("Bugünün sayacı ve aktivite kaydı silinecek.`r`nGeçmiş günler etkilenmez.`r`n`r`nEmin misin?", 'Sayacı sıfırla', 'YesNo', 'Warning')
    if ($o -eq 'Yes') {
        ([ordered]@{ tarih = (Get-Date).ToString('yyyy-MM-dd'); dakika = 0; uyari = 0; sonUyari = ''; erteleme = ''; ertSayi = 0; vazgecti = $false; kutlandi = $false } | ConvertTo-Json) | Out-File $durumD -Encoding utf8
        # izleyicinin yazdigi 7 kolonla ayni baslik (eskiden sure/kaynak eksikti; rapor o gunu 0 dk goruyordu)
        'zaman;uygulama;baslik;bosta;kategori;sure;kaynak' | Out-File (Join-Path $aktDir "$((Get-Date).ToString('yyyy-MM-dd')).csv") -Encoding utf8
        $script:tur = 0; Yenile } })
$btnPerBas.Add_Click({ $dk = [int](($cbPer.SelectedItem -replace ' dk', '')); PerYaz $true $dk
    Bilgi "$dk dakikalık çalışma periyodu başladı.`r`n`r`nBu süre boyunca YASAKLI bir uygulama açarsan 10 saniye içinde tam ekran uyarı çıkar." 'Periyot başladı'; Yenile })
$btnPerBit.Add_Click({ PerYaz $false; Yenile })
$btnAcil.Add_Click({
    if (Test-Path $durD) { [System.IO.File]::Delete($durD); Bilgi 'Engelleme yeniden açıldı.' 'Açıldı' }
    else {
        'acil durdurma aktif' | Out-File $durD -Encoding utf8; PerYaz $false
        Bilgi "Tüm engeller kapatıldı ve periyot sonlandırıldı.`r`n`r`nTekrar açmak için aynı düğmeye bas." 'Acil durdurma' 'Warning'
    }
    Yenile })
$btnRapor.Add_Click({ Start-Process -FilePath $psExe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$(Join-Path $hDir 'rapor-penceresi.ps1')`"" -WindowStyle Hidden })
$btnTest.Add_Click({ Start-Process -FilePath $psExe -ArgumentList "-NoExit -NoProfile -ExecutionPolicy Bypass -File `"$testPs`"" })
# Ayarlar ayni surecte modal acilir. Zamanlayici durdurulur: olay betikleri dinamik kapsamda calisir,
# acik pencere surerken Yenile ayarlar penceresinin degiskenlerini gorebilirdi.
$btnAyar.Add_Click({
    $zm.Stop()
    try { $kaydedildi = Ayarlar-Penceresi -HatirlaticiKlasoru $hDir } finally { $zm.Start() }
    if ($kaydedildi) { $nu.Value = [math]::Max(15, [math]::Min(720, [int](AyarOku).hedef)) }
    Yenile })
$btnYardim.Add_Click({ Start-Process -FilePath $psExe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$(Join-Path $hDir 'wiki-penceresi.ps1')`"" -WindowStyle Hidden })

$zm = New-Object System.Windows.Forms.Timer; $zm.Interval = 10000; $zm.Add_Tick({ Yenile })
Yenile
if ($env:ARAYUZ_ONIZLEME) { Tema-Onizleme $f $env:ARAYUZ_ONIZLEME; return }
$zm.Start()
[void]$f.ShowDialog()
$zm.Stop()
