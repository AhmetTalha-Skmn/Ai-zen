# ============================================================
#  Ayarlar penceresi: kurulum turu (salt okunur), hatirlatmalar, ekran kilidi, gunluk hedef.
#  Kontrol paneli noktayla yukler ve Ayarlar-Penceresi'ni cagirir; tek basina da calisir.
#  Yazim ozellikler.ps1 uzerinden: ayarlar.json'daki diger alanlar (duraklat, yedekKlasoru...) korunur.
#  Yalnizca kullanicinin degistirdigi anahtar yazilir; "Varsayilana don" iki anahtari siler.
#  UTF-8 BOM ile kaydedilir (Turkce metinler).
#  Onizleme: $env:ARAYUZ_ONIZLEME = <png yolu> ise pencereyi gostermeden PNG'ye cizer.
# ============================================================
$ErrorActionPreference = 'SilentlyContinue'
$script:ayarPencereDir = $PSScriptRoot; if (-not $script:ayarPencereDir) { $script:ayarPencereDir = Split-Path $MyInvocation.MyCommand.Path -Parent }
if (-not (Get-Command Tema-Pencere -ErrorAction SilentlyContinue)) { . (Join-Path $script:ayarPencereDir 'tema.ps1') }
if (-not (Get-Command Get-TakipOzellikleri -ErrorAction SilentlyContinue)) { . (Join-Path $script:ayarPencereDir 'ozellikler.ps1') }

function Ayar-AcikKapali { param([bool]$Deger) if ($Deger) { return 'açık' }; return 'kapalı' }

# Kaydedildiyse $true dondurur (cagiran paneli yeniler)
function Ayarlar-Penceresi { param([string]$HatirlaticiKlasoru, [string]$Onizleme = '')
    $h = $HatirlaticiKlasoru
    $oz = Get-TakipOzellikleri -HatirlaticiKlasoru $h
    # ayarlar.json'daki secimler olmasaydi gecerli olacak degerler (kurulum ya da turun varsayilani)
    $taban = Get-TakipOzellikleri -HatirlaticiKlasoru $h -Ayarlar @{}
    $ayar = Oz-AyarOku $h
    $script:ayarKaydedildi = $false

    $fa = New-Object System.Windows.Forms.Form
    Tema-Pencere $fa 'Aizen · Ayarlar' 520 588
    $fa.FormBorderStyle = 'FixedDialog'; $fa.MaximizeBox = $false; $fa.MinimizeBox = $false
    [void](Tema-Etiket $fa 'Ayarlar' 20 16 300 32 16 -Kalin)

    # ---- kurulum ----
    $ka1 = Tema-Kart $fa 20 62 480 96
    [void](Tema-Bolum $ka1 'Kurulum' 20 14)
    [void](Tema-Etiket $ka1 'Kurulum türü' 20 38 130 22)
    [void](Tema-Etiket $ka1 (Oz-TurAdi $oz.kurulumTuru) 150 38 300 22 10 -Kalin)
    $turAciklama = switch ($oz.kurulumTuru) {
        'sirket' { 'Şirket bilgisayarı: hatırlatma yok; ekran kilidi varsayılan olarak kapalı.' }
        'ozel'   { 'Özel kurulum: hatırlatma ve ekran kilidi kurulumda seçildi.' }
        default  { 'Kişisel kullanım: hatırlatma ve ekran kilidi varsayılan olarak açık.' }
    }
    [void](Tema-Etiket $ka1 $turAciklama 20 62 440 22 9 -Renk $TEMA.Soluk)

    # ---- hatirlatmalar ----
    $ka2 = Tema-Kart $fa 20 170 480 120
    [void](Tema-Bolum $ka2 'Hatırlatmalar' 20 14)
    $cbHat = New-Object System.Windows.Forms.CheckBox
    $cbHat.Text = '45 dakikalık çalışma uyarıları ve hedef mesajı'; $cbHat.Font = (Tema-Yazi 10)
    $cbHat.Location = (Tema-Konum 20 38); $cbHat.Size = (Tema-Boyut 440 26); $cbHat.BackColor = $TEMA.Kart
    $cbHat.Checked = [bool]$oz.hatirlatmalar
    $ka2.Controls.Add($cbHat)
    $lbHat = Tema-Etiket $ka2 '' 20 68 440 42 9 -Renk $TEMA.Soluk
    if (-not $oz.hatirlatmaAyarlanabilir) {
        $cbHat.Enabled = $false; $cbHat.Checked = $false
        $lbHat.Text = 'Şirket kurulumunda hatırlatma yoktur. Ölçüm, rapor ve günlük hedef çalışmaya devam eder.'
    } else {
        $lbHat.Text = "Kapatınca ölçüm ve rapor sürer, yalnızca uyarılar çıkmaz. Kurulumdaki değer: $(Ayar-AcikKapali $taban.hatirlatmalar)."
    }

    # ---- ekran kilidi ----
    $ka3 = Tema-Kart $fa 20 302 480 136
    [void](Tema-Bolum $ka3 'Ekran kilidi' 20 14)
    $cbKilit = New-Object System.Windows.Forms.CheckBox
    $cbKilit.Text = 'Uyarılar ve çalışma periyodu engeli ekranı kaplasın'; $cbKilit.Font = (Tema-Yazi 10)
    $cbKilit.Location = (Tema-Konum 20 38); $cbKilit.Size = (Tema-Boyut 440 26); $cbKilit.BackColor = $TEMA.Kart
    $cbKilit.Checked = [bool]$oz.ekranKilidi
    $ka3.Controls.Add($cbKilit)
    [void](Tema-Etiket $ka3 ("Açık: tam ekran, kapatılamayan uyarı; çalışma periyodunda izinsiz uygulama engellenir.`r`n" +
        "Kapalı: uyarılar normal pencerede, engel yok. Kurulumdaki değer: $(Ayar-AcikKapali $taban.ekranKilidi).") 20 68 440 58 9 -Renk $TEMA.Soluk)

    # ---- gunluk hedef ----
    $ka4 = Tema-Kart $fa 20 450 480 70
    [void](Tema-Bolum $ka4 'Günlük hedef' 20 14)
    $nuHedef = New-Object System.Windows.Forms.NumericUpDown
    $nuHedef.Location = (Tema-Konum 20 34); $nuHedef.Size = (Tema-Boyut 80 26); $nuHedef.Font = (Tema-Yazi 9.5)
    $nuHedef.Minimum = 15; $nuHedef.Maximum = 720; $nuHedef.Increment = 15
    $hedef = 240; try { $hedef = [int]$ayar.hedef } catch { }
    $nuHedef.Value = [math]::Max(15, [math]::Min(720, $hedef))
    $ka4.Controls.Add($nuHedef)
    $lbHedefSaat = Tema-Etiket $ka4 '' 108 36 200 22 9.5 -Renk $TEMA.Soluk
    $lbHedefSaat.Text = "dakika  = $(Tema-Sayi ($nuHedef.Value / 60)) saat"
    $nuHedef.Add_ValueChanged({ $lbHedefSaat.Text = "dakika  = $(Tema-Sayi ($nuHedef.Value / 60)) saat" })

    # ---- dugmeler ----
    $btnVars   = Tema-Dugme $fa 'Varsayılana dön' 20 536 136 36
    $btnAyarYardim = Tema-Dugme $fa 'Yardım' 164 536 84 36
    $btnVazgec = Tema-Dugme $fa 'Vazgeç' 300 536 90 36
    $btnKaydet = Tema-Dugme $fa 'Kaydet' 398 536 102 36 'birincil'
    $fa.AcceptButton = $btnKaydet; $fa.CancelButton = $btnVazgec

    $btnVazgec.Add_Click({ $fa.Close() })
    $btnKaydet.Add_Click({
        $d = [ordered]@{ hedef = [int]$nuHedef.Value }
        if ($oz.hatirlatmaAyarlanabilir -and $cbHat.Checked -ne [bool]$oz.hatirlatmalar) { $d.hatirlatmalar = [bool]$cbHat.Checked }
        if ($cbKilit.Checked -ne [bool]$oz.ekranKilidi) { $d.ekranKilidi = [bool]$cbKilit.Checked }
        try { [void](Oz-AyarGuncelle $h $d); $script:ayarKaydedildi = $true; $fa.Close() }
        catch { [void][System.Windows.Forms.MessageBox]::Show("Ayarlar kaydedilemedi:`r`n$($_.Exception.Message)", 'Ayarlar', 'OK', 'Error') }
    })
    $btnVars.Add_Click({
        $o = [System.Windows.Forms.MessageBox]::Show("Hatırlatma ve ekran kilidi seçimlerin silinecek; kurulumdaki değerler geçerli olacak.`r`n" +
            "Hatırlatmalar: $(Ayar-AcikKapali $taban.hatirlatmalar)  ·  Ekran kilidi: $(Ayar-AcikKapali $taban.ekranKilidi)`r`n`r`nDevam edilsin mi?",
            'Varsayılana dön', 'YesNo', 'Question')
        if ($o -ne 'Yes') { return }
        try { [void](Oz-AyarGuncelle $h ([ordered]@{ hatirlatmalar = $null; ekranKilidi = $null })); $script:ayarKaydedildi = $true; $fa.Close() }
        catch { [void][System.Windows.Forms.MessageBox]::Show("Ayarlar kaydedilemedi:`r`n$($_.Exception.Message)", 'Ayarlar', 'OK', 'Error') }
    })
    $btnAyarYardim.Add_Click({
        $ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
        Start-Process -FilePath $ps -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"" + (Join-Path $h 'wiki-penceresi.ps1') + "`" -Sayfa ayarlar") -WindowStyle Hidden
    })

    if ($Onizleme) { Tema-Onizleme $fa $Onizleme; return $false }
    [void]$fa.ShowDialog()
    return $script:ayarKaydedildi
}

# Tek basina calistirildiysa pencereyi ac (noktayla yuklendiyse yalnizca fonksiyon tanimlanir)
if ($MyInvocation.InvocationName -ne '.') {
    [void](Ayarlar-Penceresi -HatirlaticiKlasoru $script:ayarPencereDir -Onizleme $env:ARAYUZ_ONIZLEME)
}
