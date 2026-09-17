#requires -Version 5.1
<#
  Aizen — kurulum sihirbazı.

  Bütün kurulum mantığı Kurulum.ps1'dedir; bu dosya yalnızca onu sessiz kipte
  çağıran arayüzdür. Görünüm, uygulamanın kendi teması (hatirlatici\tema.ps1).

  Önizleme/test: $env:ARAYUZ_ONIZLEME = <png yolu> ve -Sayfa <1-4> verilirse
  pencere gösterilmeden PNG'ye çizilir.
#>
param(
    [ValidateRange(1, 4)]
    [int]$Sayfa = 1
)

$ErrorActionPreference = 'Stop'
$script:PaketKoku = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($script:PaketKoku)) {
    $script:PaketKoku = Split-Path -Parent $MyInvocation.MyCommand.Path
}

# Tema paketin içinden gelir; depodan çalıştırıldığında bir üst klasörden bulunur
$temaAdaylari = @(
    (Join-Path $script:PaketKoku 'uygulama\hatirlatici\tema.ps1'),
    (Join-Path (Split-Path -Parent (Split-Path -Parent $script:PaketKoku)) 'hatirlatici\tema.ps1')
)
$temaYolu = @($temaAdaylari | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1)[0]
if ($null -eq $temaYolu) { throw 'tema.ps1 bulunamadı; paket eksik görünüyor.' }
. $temaYolu

$script:KurulumPs = Join-Path $script:PaketKoku 'Kurulum.ps1'
$kayitAdaylari = @(
    (Join-Path $script:PaketKoku 'uygulama\dagitik\istemci-kayit.ps1'),
    (Join-Path (Split-Path -Parent $script:PaketKoku) 'istemci-kayit.ps1')
)
$script:KayitPs = @($kayitAdaylari | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1)[0]
if ($null -eq $script:KayitPs) { $script:KayitPs = $kayitAdaylari[0] }
$script:PsExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$script:VarsayilanDizin = Join-Path $env:LOCALAPPDATA 'CalismaTakipSistemi'
$script:Surec = $null
$script:CiktiDosyasi = ''
$script:HataDosyasi = ''
$script:OkunanUzunluk = 0
$script:Bitti = $false

function Get-KuruluBilgi {
    param([string]$Dizin)
    $yol = Join-Path $Dizin 'dagitik\kurulum-bilgisi.json'
    if (-not (Test-Path -LiteralPath $yol)) { return $null }
    try { return (Get-Content -LiteralPath $yol -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}

function Get-OnayMetni {
    param([string]$SunucuUrl)
    if (Test-Path -LiteralPath $script:KayitPs) {
        try {
            $metin = (& $script:PsExe -NoProfile -ExecutionPolicy Bypass -File $script:KayitPs `
                -YalnizOnayMetni -SunucuUrl $SunucuUrl -CihazAdi $env:COMPUTERNAME) | Out-String
            if (-not [string]::IsNullOrWhiteSpace($metin)) { return $metin.Trim() }
        }
        catch { }
    }
    return @"
Bu bilgisayarın çalışma özeti merkeze gönderilecek.

GÖNDERİLECEK: uygulama adı ve kategorisi, uygulama başına günlük süre,
takip sağlığı (izleyici çalışıyor mu).

GÖNDERİLMEYECEK: pencere başlıkları, tam adres/URL, arama terimleri,
tuş kaydı, pano, ekran görüntüsü, dosya adı ve içerikleri.
"@
}

# ---------------- pencere ----------------
$f = New-Object System.Windows.Forms.Form
Tema-Pencere $f 'Aizen — Kurulum' 720 560
$f.FormBorderStyle = 'FixedSingle'
$f.MaximizeBox = $false

[void](Tema-Etiket $f 'Aizen' 24 20 400 30 15 -Kalin)
$script:AltBaslik = Tema-Etiket $f 'Kurulum türünü seç' 26 52 620 20 9.5 -Renk $TEMA.Soluk

$kart = Tema-Kart $f 24 84 672 372

# --- Sayfa 1: rol ---
$s1 = New-Object System.Windows.Forms.Panel
$s1.Location = (Tema-Konum 1 1); $s1.Size = (Tema-Boyut 670 370); $s1.BackColor = $TEMA.Kart
$kart.Controls.Add($s1)
[void](Tema-Etiket $s1 'Bu bilgisayara hangi kurulum yapılacak?' 28 18 600 24 11 -Kalin)
# Tur (bireysel/sirket/ozel) ve rol (Admin/Kullanici) ayri kavramlardir; sihirbaz ikisini dort secenekte toplar.
function Yeni-Secenek { param([string]$Metin, [int]$Y, [string]$Aciklama, [int]$AciklamaBoy = 36)
    $rb = New-Object System.Windows.Forms.RadioButton
    $rb.Text = $Metin; $rb.Font = (Tema-Yazi 10 -Kalin)
    $rb.Location = (Tema-Konum 34 $Y); $rb.Size = (Tema-Boyut 560 24)
    $s1.Controls.Add($rb)
    [void](Tema-Etiket $s1 $Aciklama 56 ($Y + 24) 580 $AciklamaBoy 9 -Renk $TEMA.Soluk)
    return $rb }
$rbBireysel = Yeni-Secenek 'Bireysel kullanım' 50 'Kendi çalışmanı ölçer. 45 dakikalık hatırlatmalar ve ekran kilidi açık; ikisi de Ayarlar''dan kapatılabilir. İstersen bir merkeze bağlanırsın.'
$rbAdmin = Yeni-Secenek 'Şirket · yönetici bilgisayarı' 112 'Çalışan bilgisayarlarının günlük özetlerini toplar ve panelde gösterir. Ağ dinleme izni için Windows yönetici onayı ister. Hatırlatma yok, ekran kilidi kapalı.'
$rbKullanici = Yeni-Secenek 'Şirket · çalışan bilgisayarı' 174 'Bu bilgisayarın süresi ölçülür; yöneticiden alınan kod ve onay ekranıyla merkeze bağlanır. Hatırlatma yok, ekran kilidi kapalı (Ayarlar''dan açılabilir).'
$rbOzel = Yeni-Secenek 'Özel kurulum' 236 'Özellikleri kendin seç:' 20
$rbBireysel.Checked = $true
function Yeni-OzelKutu { param([string]$Metin, [int]$X, [int]$En, [bool]$Secili)
    $c = New-Object System.Windows.Forms.CheckBox
    $c.Text = $Metin; $c.Font = (Tema-Yazi 9.5); $c.Checked = $Secili
    $c.Location = (Tema-Konum $X 280); $c.Size = (Tema-Boyut $En 24); $c.Enabled = $false
    $s1.Controls.Add($c); return $c }
$chkOzelHat = Yeni-OzelKutu 'Hatırlatmalar' 56 130 $true
$chkOzelKilit = Yeni-OzelKutu 'Ekran kilidi' 196 120 $false
$chkOzelMerkez = Yeni-OzelKutu 'Bu bilgisayar merkez olsun' 326 240 $false
$rbOzel.Add_CheckedChanged({ foreach ($c in @($chkOzelHat, $chkOzelKilit, $chkOzelMerkez)) { $c.Enabled = $rbOzel.Checked } })
$script:DurumEtiketi = Tema-Etiket $s1 '' 28 314 610 44 9 -Renk $TEMA.Soluk

function Admin-Mi { return ($rbAdmin.Checked -or ($rbOzel.Checked -and $chkOzelMerkez.Checked)) }
function Secilen-Tur {
    if ($rbBireysel.Checked) { return 'Bireysel' }
    if ($rbOzel.Checked) { return 'Ozel' }
    return 'Sirket' }
function Secilen-Ad {
    if ($rbBireysel.Checked) { return 'Bireysel' }
    if ($rbAdmin.Checked) { return 'Şirket · yönetici' }
    if ($rbKullanici.Checked) { return 'Şirket · çalışan' }
    if (Admin-Mi) { return 'Özel · merkez' }
    return 'Özel' }

# --- Sayfa 2: klasör ve merkez ---
$s2 = New-Object System.Windows.Forms.Panel
$s2.Location = (Tema-Konum 1 1); $s2.Size = (Tema-Boyut 670 370); $s2.BackColor = $TEMA.Kart
$s2.Visible = $false
$kart.Controls.Add($s2)
[void](Tema-Etiket $s2 'Kurulum klasörü' 28 26 300 22 10 -Kalin)
$txtDizin = New-Object System.Windows.Forms.TextBox
$txtDizin.Location = (Tema-Konum 30 54); $txtDizin.Size = (Tema-Boyut 500 26)
$txtDizin.Font = (Tema-Yazi 9.5)
$txtDizin.Text = $script:VarsayilanDizin
$s2.Controls.Add($txtDizin)
$btnGozat = Tema-Dugme $s2 'Değiştir' 540 52 100 30
[void](Tema-Etiket $s2 'Yönetici yetkisi gerekmez. Aynı klasöre tekrar kurulursa kurallar, ayarlar ve ölçüm verisi korunur.' 30 88 600 20 9 -Renk $TEMA.Soluk)

$grpMerkez = New-Object System.Windows.Forms.Panel
$grpMerkez.Location = (Tema-Konum 28 124); $grpMerkez.Size = (Tema-Boyut 614 200); $grpMerkez.BackColor = $TEMA.Kart
$s2.Controls.Add($grpMerkez)
$chkBaglan = New-Object System.Windows.Forms.CheckBox
$chkBaglan.Text = 'Bir yönetici merkezine bağlan'
$chkBaglan.Font = (Tema-Yazi 10 -Kalin)
$chkBaglan.Location = (Tema-Konum 2 4); $chkBaglan.Size = (Tema-Boyut 480 26)
$grpMerkez.Controls.Add($chkBaglan)
[void](Tema-Etiket $grpMerkez 'İşaretlemezsen bu bilgisayar tek başına çalışır, hiçbir yere veri göndermez.' 24 30 560 20 9 -Renk $TEMA.Soluk)
[void](Tema-Etiket $grpMerkez 'Merkez adresi' 24 64 120 22 9.5)
$txtSunucu = New-Object System.Windows.Forms.TextBox
$txtSunucu.Location = (Tema-Konum 150 62); $txtSunucu.Size = (Tema-Boyut 300 26); $txtSunucu.Font = (Tema-Yazi 9.5)
$txtSunucu.Text = 'http://'
$grpMerkez.Controls.Add($txtSunucu)
[void](Tema-Etiket $grpMerkez 'örnek: http://192.168.1.20:8787' 150 90 300 18 8.5 -Renk $TEMA.Soluk)
[void](Tema-Etiket $grpMerkez 'Eşleşme kodu' 24 122 120 22 9.5)
$txtKod = New-Object System.Windows.Forms.TextBox
$txtKod.Location = (Tema-Konum 150 120); $txtKod.Size = (Tema-Boyut 220 28)
$txtKod.Font = New-Object System.Drawing.Font('Consolas', 11)
$txtKod.CharacterCasing = 'Upper'
$grpMerkez.Controls.Add($txtKod)
[void](Tema-Etiket $grpMerkez 'Yöneticinin verdiği tek kullanımlık kod (ABCD-EFGH-JKMN)' 150 150 420 18 8.5 -Renk $TEMA.Soluk)

# --- Sayfa 3: onay ---
$s3 = New-Object System.Windows.Forms.Panel
$s3.Location = (Tema-Konum 1 1); $s3.Size = (Tema-Boyut 670 370); $s3.BackColor = $TEMA.Kart
$s3.Visible = $false
$kart.Controls.Add($s3)
[void](Tema-Etiket $s3 'Merkeze ne gönderilecek?' 28 22 500 24 11 -Kalin)
$txtOnay = New-Object System.Windows.Forms.TextBox
$txtOnay.Location = (Tema-Konum 30 54); $txtOnay.Size = (Tema-Boyut 610 236)
$txtOnay.Multiline = $true; $txtOnay.ReadOnly = $true; $txtOnay.ScrollBars = 'Vertical'
$txtOnay.BackColor = $TEMA.Zemin; $txtOnay.BorderStyle = 'FixedSingle'
$txtOnay.Font = New-Object System.Drawing.Font('Consolas', 9)
$s3.Controls.Add($txtOnay)
$chkOnay = New-Object System.Windows.Forms.CheckBox
$chkOnay.Text = 'Okudum, bu bilgisayarın yukarıdaki verileri göndermesini onaylıyorum.'
$chkOnay.Font = (Tema-Yazi 9.5 -Kalin)
$chkOnay.Location = (Tema-Konum 30 302); $chkOnay.Size = (Tema-Boyut 610 26)
$s3.Controls.Add($chkOnay)

# --- Sayfa 4: kurulum ---
$s4 = New-Object System.Windows.Forms.Panel
$s4.Location = (Tema-Konum 1 1); $s4.Size = (Tema-Boyut 670 370); $s4.BackColor = $TEMA.Kart
$s4.Visible = $false
$kart.Controls.Add($s4)
$script:KurulumBaslik = Tema-Etiket $s4 'Kuruluyor...' 28 24 500 24 11 -Kalin
$cubuk = New-Object System.Windows.Forms.ProgressBar
$cubuk.Location = (Tema-Konum 30 58); $cubuk.Size = (Tema-Boyut 610 10)
$cubuk.Style = 'Marquee'; $cubuk.MarqueeAnimationSpeed = 30
$s4.Controls.Add($cubuk)
$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Location = (Tema-Konum 30 84); $txtLog.Size = (Tema-Boyut 610 250)
$txtLog.Multiline = $true; $txtLog.ReadOnly = $true; $txtLog.ScrollBars = 'Vertical'
$txtLog.BackColor = $TEMA.Zemin; $txtLog.BorderStyle = 'FixedSingle'
$txtLog.Font = New-Object System.Drawing.Font('Consolas', 8.5)
$s4.Controls.Add($txtLog)

# --- alt şerit ---
$btnKapat = Tema-Dugme $f 'Vazgeç' 24 478 110 36
$btnGeri = Tema-Dugme $f 'Geri' 360 478 100 36
$btnIleri = Tema-Dugme $f 'İleri' 470 478 110 36 'birincil'
$btnKur = Tema-Dugme $f 'Kur' 588 478 108 36 'birincil'
$btnKur.Visible = $false

$script:Adim = 1
$sayfalar = @($s1, $s2, $s3, $s4)

function Baglanacak-Mi { return ((-not (Admin-Mi)) -and $chkBaglan.Checked) }

function Goster-Adim {
    param([int]$n)
    $script:Adim = $n
    for ($i = 0; $i -lt 4; $i++) { $sayfalar[$i].Visible = (($i + 1) -eq $n) }
    switch ($n) {
        1 {
            $script:AltBaslik.Text = 'Kurulum türünü seç'
            $btnGeri.Visible = $false; $btnIleri.Visible = $true; $btnKur.Visible = $false
            $kurulu = Get-KuruluBilgi $script:VarsayilanDizin
            if ($null -ne $kurulu) {
                $kuruluTur = 'bireysel'
                if ($kurulu.PSObject.Properties['kurulumTuru'] -and $kurulu.kurulumTuru) { $kuruluTur = ([string]$kurulu.kurulumTuru).ToLowerInvariant() }
                $turAd = switch ($kuruluTur) { 'sirket' { 'Şirket' } 'ozel' { 'Özel' } default { 'Bireysel' } }
                $script:DurumEtiketi.Text = "Bu bilgisayarda kurulu sürüm bulundu (tür: $turAd, rol: $($kurulu.rol)). Aynı klasöre kurulum güncelleme yapar; kuralların, ayarların ve ölçüm verin korunur."
            }
            else { $script:DurumEtiketi.Text = '' }
        }
        2 {
            $script:AltBaslik.Text = 'Kurulum klasörü ve merkez bağlantısı'
            $grpMerkez.Visible = -not (Admin-Mi)
            $btnGeri.Visible = $true
            $btnIleri.Visible = (Baglanacak-Mi)
            $btnKur.Visible = -not (Baglanacak-Mi)
            $btnKur.Enabled = $true
        }
        3 {
            $script:AltBaslik.Text = 'Veri paylaşımı onayı'
            $txtOnay.Text = (Get-OnayMetni $txtSunucu.Text) -replace "`r?`n", "`r`n"
            $txtOnay.SelectionStart = 0; $txtOnay.SelectionLength = 0
            $btnGeri.Visible = $true; $btnIleri.Visible = $false; $btnKur.Visible = $true
            $btnKur.Enabled = $chkOnay.Checked
        }
        4 {
            $script:AltBaslik.Text = 'Kurulum'
            $btnGeri.Visible = $false; $btnIleri.Visible = $false; $btnKur.Visible = $false
            $btnKapat.Text = 'Kapat'
        }
    }
}

function Ileri-Git {
    if ($script:Adim -eq 1) { Goster-Adim 2; return }
    if ($script:Adim -eq 2) {
        if ([string]::IsNullOrWhiteSpace($txtDizin.Text)) {
            [void][System.Windows.Forms.MessageBox]::Show('Kurulum klasörü boş olamaz.', 'Kurulum', 'OK', 'Warning'); return
        }
        if (Baglanacak-Mi) {
            $url = $txtSunucu.Text.Trim().TrimEnd('/')
            if ($url -notmatch '^https?://[^/\\]+(?::\d+)?$') {
                [void][System.Windows.Forms.MessageBox]::Show("Merkez adresi http://sunucu:port biçiminde olmalı.`r`nÖrnek: http://192.168.1.20:8787", 'Kurulum', 'OK', 'Warning'); return
            }
            if (($txtKod.Text -creplace '[^0-9A-Za-z]', '').Length -lt 8) {
                [void][System.Windows.Forms.MessageBox]::Show('Eşleşme kodunu eksiksiz gir.', 'Kurulum', 'OK', 'Warning'); return
            }
            Goster-Adim 3
        }
    }
}

function Basla-Kurulum {
    Goster-Adim 4
    $rol = if (Admin-Mi) { 'Admin' } else { 'Kullanici' }
    $script:KurulumBaslik.Text = "Kuruluyor... ($(Secilen-Ad))"
    $argumanlar = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script:KurulumPs,
        '-Rol', $rol, '-KurulumTuru', (Secilen-Tur), '-Sessiz', '-KurulumDizini', $txtDizin.Text.Trim())
    if ($rbOzel.Checked) {
        $argumanlar += @('-Hatirlatmalar', $(if ($chkOzelHat.Checked) { 'Acik' } else { 'Kapali' }),
            '-EkranKilidi', $(if ($chkOzelKilit.Checked) { 'Acik' } else { 'Kapali' }))
    }
    if (Baglanacak-Mi) {
        $argumanlar += @('-SunucuUrl', $txtSunucu.Text.Trim().TrimEnd('/'), '-Kod', $txtKod.Text.Trim(), '-Onayla')
    }
    $script:CiktiDosyasi = Join-Path $env:TEMP ('ct-kurulum-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.log')
    $script:HataDosyasi = "$($script:CiktiDosyasi).err"
    $script:OkunanUzunluk = 0
    $script:Bitti = $false
    $txtLog.Text = ''
    try {
        $script:Surec = Start-Process -FilePath $script:PsExe -ArgumentList $argumanlar -PassThru `
            -RedirectStandardOutput $script:CiktiDosyasi -RedirectStandardError $script:HataDosyasi -WindowStyle Hidden
        $izleyici.Start()
    }
    catch {
        $cubuk.Style = 'Continuous'; $cubuk.Value = 0
        $script:KurulumBaslik.Text = 'Kurulum başlatılamadı'
        $txtLog.Text = $_.Exception.Message
    }
}

function Log-Ekle {
    if ([string]::IsNullOrWhiteSpace($script:CiktiDosyasi)) { return }
    $metin = ''
    try { $metin = [IO.File]::ReadAllText($script:CiktiDosyasi) } catch { return }
    if ($metin.Length -le $script:OkunanUzunluk) { return }
    $yeni = $metin.Substring($script:OkunanUzunluk)
    $script:OkunanUzunluk = $metin.Length
    $txtLog.AppendText(($yeni -replace "`r?`n", "`r`n"))
}

function Bitir-Kurulum {
    if ($script:Bitti) { return }
    $script:Bitti = $true
    $izleyici.Stop()
    Log-Ekle
    $cubuk.Style = 'Continuous'
    $kod = 1
    try { $kod = $script:Surec.ExitCode } catch { }
    if ($kod -eq 0) {
        $cubuk.Value = 100
        $script:KurulumBaslik.Text = 'Kurulum tamamlandı'
        $script:KurulumBaslik.ForeColor = $TEMA.Basari
        $btnKapat.Text = 'Bitir'
    }
    else {
        $cubuk.Value = 0
        $script:KurulumBaslik.Text = "Kurulum tamamlanamadı (kod $kod)"
        $script:KurulumBaslik.ForeColor = $TEMA.Tehlike
        try {
            $hata = [IO.File]::ReadAllText($script:HataDosyasi)
            if (-not [string]::IsNullOrWhiteSpace($hata)) { $txtLog.AppendText("`r`n" + $hata) }
        }
        catch { }
    }
}

$izleyici = New-Object System.Windows.Forms.Timer
$izleyici.Interval = 400
$izleyici.Add_Tick({
    Log-Ekle
    if ($null -ne $script:Surec -and $script:Surec.HasExited) { Bitir-Kurulum }
})

foreach ($rb in @($rbBireysel, $rbAdmin, $rbKullanici, $rbOzel, $chkOzelMerkez)) { $rb.Add_CheckedChanged({ if ($script:Adim -eq 2) { Goster-Adim 2 } }) }
$chkBaglan.Add_CheckedChanged({
    $txtSunucu.Enabled = $chkBaglan.Checked
    $txtKod.Enabled = $chkBaglan.Checked
    if ($script:Adim -eq 2) { Goster-Adim 2 }
})
$chkOnay.Add_CheckedChanged({ $btnKur.Enabled = $chkOnay.Checked })
$btnGozat.Add_Click({
    $secici = New-Object System.Windows.Forms.FolderBrowserDialog
    $secici.Description = 'Kurulum klasörünü seç'
    if ($secici.ShowDialog() -eq 'OK') { $txtDizin.Text = Join-Path $secici.SelectedPath 'CalismaTakipSistemi' }
})
$btnIleri.Add_Click({ Ileri-Git })
$btnGeri.Add_Click({ if ($script:Adim -gt 1) { Goster-Adim ($script:Adim - 1) } })
$btnKur.Add_Click({ Basla-Kurulum })
$btnKapat.Add_Click({ $f.Close() })

$txtSunucu.Enabled = $false
$txtKod.Enabled = $false

# Guncellemede mevcut tur ve rol secili gelir. Turu yazilmamis eski kurulum bireysel davranisla
# calisiyordu; eski yonetici kurulumu bu yuzden "Ozel · merkez" (hatirlatma ve kilit acik) olarak gelir.
$kuruluIlk = Get-KuruluBilgi $script:VarsayilanDizin
if ($null -ne $kuruluIlk) {
    $kt = ''; if ($kuruluIlk.PSObject.Properties['kurulumTuru']) { $kt = ([string]$kuruluIlk.kurulumTuru).ToLowerInvariant() }
    $kr = [string]$kuruluIlk.rol
    if ($kt -eq 'sirket') { if ($kr -eq 'Admin') { $rbAdmin.Checked = $true } else { $rbKullanici.Checked = $true } }
    elseif ($kt -eq 'ozel' -or ($kt -eq '' -and $kr -eq 'Admin')) {
        $rbOzel.Checked = $true; $chkOzelMerkez.Checked = ($kr -eq 'Admin')
        $chkOzelHat.Checked = $true; $chkOzelKilit.Checked = ($kt -eq '')
        if ($kuruluIlk.PSObject.Properties['ozellikler'] -and $null -ne $kuruluIlk.ozellikler) {
            $chkOzelHat.Checked = [bool]$kuruluIlk.ozellikler.hatirlatmalar; $chkOzelKilit.Checked = [bool]$kuruluIlk.ozellikler.ekranKilidi
        }
    }
    else { $rbBireysel.Checked = $true }
}
Goster-Adim 1

if ($env:ARAYUZ_ONIZLEME) {
    if ($Sayfa -eq 1 -and $env:ARAYUZ_ONIZLEME_OZEL) { $rbOzel.Checked = $true }
    if ($Sayfa -ge 2) { $rbKullanici.Checked = $true; $chkBaglan.Checked = $true }
    if ($Sayfa -ge 3) { $txtSunucu.Text = 'http://192.168.1.20:8787'; $txtKod.Text = 'K7M4-P2QX-9RTB' }
    Goster-Adim $Sayfa
    Tema-Onizleme $f $env:ARAYUZ_ONIZLEME
    return
}

[void]$f.ShowDialog()
