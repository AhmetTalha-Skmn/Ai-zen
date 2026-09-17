# ============================================================
#  KAPSAMLI TEST -- durum makinesi, veri dayanikliligi, raporlar
# ============================================================
$ErrorActionPreference = 'Continue'
$hDir = $PSScriptRoot; if (-not $hDir) { $hDir = Split-Path $MyInvocation.MyCommand.Path -Parent }
$psExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$env:CALISMATAKIP_TEST_SN = '3'   # test pencereleri 3 sn sonra kendi kapanir
$gecti=0; $kaldi=0; $atlandi=0
function T { param($ad,$ok,$d)
  if ($ok) { $script:gecti++; Write-Host ("  [OK]   {0,-50} {1}" -f $ad,$d) -ForegroundColor Green }
  else     { $script:kaldi++; Write-Host ("  [HATA] {0,-50} {1}" -f $ad,$d) -ForegroundColor Red } }
function Baslik { param($t) Write-Host "`n=== $t ===" -ForegroundColor Cyan }

$tmp  = Join-Path $env:TEMP 'php-kapsamli'
$tH   = Join-Path $tmp 'hatirlatici'
$tAkt = Join-Path $tH 'aktivite'

function KasaKur {
    if ([System.IO.Directory]::Exists($tmp)) { [System.IO.Directory]::Delete($tmp, $true) }
    [void][System.IO.Directory]::CreateDirectory($tAkt)
    $k = Get-Content (Join-Path $hDir 'takip.ps1') -Raw -Encoding UTF8
    # Bayrak uyari penceresinin kipini de yazar: ekran kilidi, kenarlik, en ustte mi
    $k = $k.Replace('$sonuc = $f.ShowDialog()', "(`"UYARI kilit=`$EKRAN_KILIDI form=`$(`$f.FormBorderStyle) ust=`$(`$f.TopMost)`") | Out-File (Join-Path `$hDir 'test.flag') -Encoding utf8 -Append`r`n`$sonuc = `$env:TESTYANIT; if (-not `$sonuc) { `$sonuc = 'Ignore' }")
    $k = $k.Replace('for ($i = 1; $i -le $ses; $i++) { [System.Media.SystemSounds]::Exclamation.Play(); Start-Sleep -Milliseconds 450 }', '$null = 3')
    $k = $k.Replace('[System.Windows.Forms.MessageBox]::Show("Gunluk hedef tamam: $toplamDk dakika.`r`nSeri: $seri gun.",''Hedef tamamlandi'',''OK'',[System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null', "'KUTLAMA' | Out-File (Join-Path `$hDir 'test.flag') -Encoding utf8 -Append")
    $k = $k.Replace('$onay=[System.Windows.Forms.MessageBox]::Show("Bugun $toplamDk/$HEDEF dakika yaptin.`r`nVazgecersen bu gun kayda BASARISIZ gecer ve serin sifirlanir.`r`n`r`nEmin misin?",''Emin misin?'',''YesNo'',[System.Windows.Forms.MessageBoxIcon]::Warning)', "`$onay = `$env:TESTONAY; if (-not `$onay) { `$onay = 'Yes' }")
    $k = $k.Replace('Start-Process explorer.exe $klasor', '$null = 1')
    $k = $k.Replace('Start-Process -FilePath "$env:SystemRoot\System32\wscript.exe" -ArgumentList "//B //Nologo `"$vbsYol`" `"$izPs`"" -WindowStyle Hidden', '$null = 2')
    $k | Out-File (Join-Path $tH 'takip.ps1') -Encoding utf8
    Copy-Item (Join-Path $hDir 'izleyici.ps1') (Join-Path $tH 'izleyici.ps1')
    Copy-Item (Join-Path $hDir 'gizli.vbs')    (Join-Path $tH 'gizli.vbs')
    Copy-Item (Join-Path $hDir 'kurallar.json') (Join-Path $tH 'kurallar.json')
    Copy-Item (Join-Path $hDir 'tema.ps1')      (Join-Path $tH 'tema.ps1')   # uyari penceresinin gorunumu
    Copy-Item (Join-Path $hDir 'ozellikler.ps1') (Join-Path $tH 'ozellikler.ps1')   # kurulum turu, hatirlatma, ekran kilidi
}
function Bugun { (Get-Date).ToString('yyyy-MM-dd') }
function DurumYaz { param($o)
    $v = [ordered]@{ tarih=(Bugun); dakika=0; uyari=0; sonUyari=''; erteleme=''; ertSayi=0; vazgecti=$false; kutlandi=$false }
    if ($o) { foreach ($k in $o.Keys) { $v[$k] = $o[$k] } }
    ($v | ConvertTo-Json) | Out-File (Join-Path $tH 'durum.json') -Encoding utf8 }
function DurumOku { Get-Content (Join-Path $tH 'durum.json') -Raw -Encoding UTF8 | ConvertFrom-Json }
function AyarYaz { param($hedef=240,$duraklat='') ([ordered]@{hedef=$hedef;duraklat=$duraklat}|ConvertTo-Json)|Out-File (Join-Path $tH 'ayarlar.json') -Encoding utf8 }
function CsvYaz { param($calisma=0,$diger=0,$bosta=0)
    $toplam = $calisma + $diger + $bosta
    $bas = (Get-Date).AddSeconds(-10 * [math]::Max($toplam - 1, 0))
    $liste = New-Object System.Collections.ArrayList
    [void]$liste.Add('zaman;uygulama;baslik;bosta;kategori;sure;kaynak')
    $t = 0
    for ($i=0;$i -lt $calisma;$i++) { [void]$liste.Add($bas.AddSeconds(10*$t).ToString('HH:mm:ss') + ';Obsidian;Ders notu;0;calisma;10;izinli'); $t++ }
    for ($i=0;$i -lt $diger;$i++)   { [void]$liste.Add($bas.AddSeconds(10*$t).ToString('HH:mm:ss') + ';chrome;YouTube;0;diger;10;yasakli');      $t++ }
    for ($i=0;$i -lt $bosta;$i++)   { [void]$liste.Add($bas.AddSeconds(10*$t).ToString('HH:mm:ss') + ';explorer;;9;bosta;10;afk');           $t++ }
    ($liste -join "`r`n") | Out-File (Join-Path $tAkt "$(Bugun).csv") -Encoding utf8 }
function BayrakOku { $f = Join-Path $tH 'test.flag'; if ([System.IO.File]::Exists($f)) { return (Get-Content $f -Encoding UTF8) -join ',' }; return '' }
function TakipCalistir { param($yanit='Ignore',$onay='Yes')
    $f = Join-Path $tH 'test.flag'; if ([System.IO.File]::Exists($f)) { [System.IO.File]::Delete($f) }
    $env:TESTYANIT = $yanit; $env:TESTONAY = $onay
    & $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $tH 'takip.ps1') 2>&1 | Out-Null
    Start-Sleep -Milliseconds 350
    $env:TESTYANIT = ''; $env:TESTONAY = '' }

KasaKur
Write-Host "Gecici kasa: $tmp   (diyaloglar test cifti ile degistirildi)" -ForegroundColor DarkGray

Baslik '1. SAYAC -- izleyici verisinden hesaplama'
AyarYaz; DurumYaz; CsvYaz -calisma 6 -diger 12 -bosta 3
TakipCalistir
T "6 ornek x 10 sn = 1 dk" ((DurumOku).dakika -eq 1) "dakika=$((DurumOku).dakika)"
CsvYaz -calisma 144 -diger 30
TakipCalistir
T "144 ornek = 24 dk" ((DurumOku).dakika -eq 24) "dakika=$((DurumOku).dakika)"
CsvYaz -calisma 0 -diger 100 -bosta 50
TakipCalistir
T "diger/bosta sayilmiyor" ((DurumOku).dakika -eq 0) "dakika=$((DurumOku).dakika)"

Baslik '2. UYARI MANTIGI'
AyarYaz; DurumYaz; CsvYaz -diger 20
TakipCalistir
T "calisma yoksa uyari cikar" ((BayrakOku) -match 'UYARI') "bayrak=$(BayrakOku)"
T "uyari sayaci 1" ((DurumOku).uyari -eq 1) "uyari=$((DurumOku).uyari)"
T "sonUyari damgalandi" ((DurumOku).sonUyari -ne '') "$((DurumOku).sonUyari)"
DurumYaz @{ sonUyari=(Get-Date).AddMinutes(-10).ToString('s'); uyari=1 }
TakipCalistir
T "45 dk dolmadan uyari CIKMAZ" ((BayrakOku) -notmatch 'UYARI') "bayrak='$(BayrakOku)'"
T "uyari sayaci artmadi" ((DurumOku).uyari -eq 1) "uyari=$((DurumOku).uyari)"
DurumYaz @{ sonUyari=(Get-Date).AddMinutes(-46).ToString('s'); uyari=1 }
TakipCalistir
T "45 dk dolunca uyari CIKAR" ((BayrakOku) -match 'UYARI') "bayrak=$(BayrakOku)"
T "uyari sayaci 2" ((DurumOku).uyari -eq 2) "uyari=$((DurumOku).uyari)"
DurumYaz @{ uyari=5; sonUyari=(Get-Date).AddMinutes(-46).ToString('s') }
CsvYaz -calisma 12
TakipCalistir
T "calisinca uyari sayaci sifirlanir" ((DurumOku).uyari -eq 0) "uyari=$((DurumOku).uyari)"
T "calisinca uyari cikmaz" ((BayrakOku) -notmatch 'UYARI') "bayrak='$(BayrakOku)'"

Baslik '3. ERTELEME'
AyarYaz; CsvYaz -diger 20
DurumYaz @{ erteleme=(Get-Date).AddMinutes(15).ToString('s') }
TakipCalistir
T "erteleme suresinde uyari cikmaz" ((BayrakOku) -notmatch 'UYARI') "bayrak='$(BayrakOku)'"
DurumYaz @{ erteleme=(Get-Date).AddMinutes(-1).ToString('s') }
TakipCalistir
T "erteleme dolunca uyari cikar" ((BayrakOku) -match 'UYARI') "bayrak=$(BayrakOku)"
DurumYaz @{ ertSayi=1 }
TakipCalistir -yanit 'No'
$d = DurumOku
T "ertele secilince ertSayi arttı" ($d.ertSayi -eq 2) "ertSayi=$($d.ertSayi)"
$eb = $d.erteleme
if ($eb -isnot [datetime]) { $eb = [datetime]::ParseExact([string]$eb,'s',[Globalization.CultureInfo]::InvariantCulture) }
$fark = [math]::Round(($eb - (Get-Date)).TotalMinutes)
T "erteleme ~30 dakika" ($fark -ge 28 -and $fark -le 31) "$fark dk"

Baslik '4. VAZGECME'
AyarYaz; CsvYaz -diger 20; DurumYaz
TakipCalistir -yanit 'Cancel' -onay 'Yes'
T "onaylayinca vazgecti=true" ((DurumOku).vazgecti -eq $true) "vazgecti=$((DurumOku).vazgecti)"
TakipCalistir
T "vazgecilince uyari cikmaz" ((BayrakOku) -notmatch 'UYARI') "bayrak='$(BayrakOku)'"
DurumYaz
TakipCalistir -yanit 'Cancel' -onay 'No'
T "onaylamayinca vazgecmez" ((DurumOku).vazgecti -eq $false) "vazgecti=$((DurumOku).vazgecti)"

Baslik '5. HEDEF TAMAMLAMA'
AyarYaz -hedef 60; DurumYaz; CsvYaz -calisma 360
TakipCalistir
$d = DurumOku
T "hedefe ulasildi" ($d.dakika -ge 60) "dakika=$($d.dakika)"
T "kutlama tetiklendi" ((BayrakOku) -match 'KUTLAMA') "bayrak=$(BayrakOku)"
T "kutlandi kaydedildi" ($d.kutlandi -eq $true) "kutlandi=$($d.kutlandi)"
TakipCalistir
T "kutlama SADECE bir kez" ((BayrakOku) -notmatch 'KUTLAMA') "bayrak='$(BayrakOku)'"
T "hedef sonrasi uyari cikmaz" ((BayrakOku) -notmatch 'UYARI') "bayrak='$(BayrakOku)'"
T "raporda success callout" ((Get-Content (Join-Path $tmp 'Calisma Kaydi.md') -Raw -Encoding UTF8) -match 'success') ''

Baslik '6. GUN DONUMU VE ARSIVLEME'
AyarYaz -hedef 240
$dun = (Get-Date).AddDays(-1).ToString('yyyy-MM-dd')
([ordered]@{tarih=$dun;dakika=250;uyari=3;sonUyari='';erteleme='';ertSayi=1;vazgecti=$false;kutlandi=$true}|ConvertTo-Json)|Out-File (Join-Path $tH 'durum.json') -Encoding utf8
$gd = Join-Path $tH 'gecmis.json'
if ([System.IO.File]::Exists($gd)) { [System.IO.File]::Delete($gd) }
CsvYaz -calisma 6
TakipCalistir
$g = @(Get-Content $gd -Raw -Encoding UTF8 | ConvertFrom-Json)
T "dun arsivlendi" ($g.Count -eq 1) "$($g.Count) kayit"
T "arsiv tarihi dogru" ($g[0].tarih -eq $dun) "$($g[0].tarih)"
T "arsiv dakikasi dogru" ([int]$g[0].dakika -eq 250) "$($g[0].dakika)"
T "250>=240 => basarili" ($g[0].basarili -eq $true) "basarili=$($g[0].basarili)"
T "durum bugune sifirlandi" ((DurumOku).tarih -eq (Bugun)) "$((DurumOku).tarih)"
T "yeni gunde ertSayi sifir" ((DurumOku).ertSayi -eq 0) "ertSayi=$((DurumOku).ertSayi)"
TakipCalistir
$ham = Get-Content $gd -Raw -Encoding UTF8
T "gecmis.json duz JSON dizisi" ($ham.TrimStart().StartsWith('[')) "basliyor: $($ham.TrimStart().Substring(0,1))"
T "sarmalayici nesne yok" ($ham -notmatch '"Count"\s*:') 'value/Count sarmalayicisi olmamali'
    T "mukerrer arsivleme yok" (@(Get-Content $gd -Raw -Encoding UTF8 | ConvertFrom-Json).Count -eq 1) "$(@(Get-Content $gd -Raw -Encoding UTF8 | ConvertFrom-Json).Count) kayit"

Baslik '7. SERI HESABI'
$g3 = @(); foreach ($i in 5,4,3,2) { $g3 += [pscustomobject]@{tarih=(Get-Date).AddDays(-$i).ToString('yyyy-MM-dd');dakika=250;hedef=240;basarili=$true} }
ConvertTo-Json -InputObject @($g3) -Depth 4 | Out-File $gd -Encoding utf8
DurumYaz; CsvYaz -diger 10
TakipCalistir
$km = Get-Content (Join-Path $tmp 'Calisma Kaydi.md') -Raw -Encoding UTF8
T "4 basarili gun + bugun 0 => 4" ($km -match 'Seri \| 4 gun') "$(([regex]::Match($km,'Seri \| (\d+) gun')).Groups[1].Value)"
CsvYaz -calisma 1440
TakipCalistir
$km = Get-Content (Join-Path $tmp 'Calisma Kaydi.md') -Raw -Encoding UTF8
T "bugun tamamlaninca => 5" ($km -match 'Seri \| 5 gun') "$(([regex]::Match($km,'Seri \| (\d+) gun')).Groups[1].Value)"
$g4 = @($g3) + @([pscustomobject]@{tarih=(Get-Date).AddDays(-1).ToString('yyyy-MM-dd');dakika=10;hedef=240;basarili=$false})
ConvertTo-Json -InputObject @($g4) -Depth 4 | Out-File $gd -Encoding utf8
DurumYaz; CsvYaz -diger 10
TakipCalistir
$km = Get-Content (Join-Path $tmp 'Calisma Kaydi.md') -Raw -Encoding UTF8
T "son gun basarisizsa => 0" ($km -match 'Seri \| 0 gun') "$(([regex]::Match($km,'Seri \| (\d+) gun')).Groups[1].Value)"

Baslik '8. BOZUK VERI DAYANIKLILIGI'
if ([System.IO.File]::Exists($gd)) { [System.IO.File]::Delete($gd) }
AyarYaz
'{ gecerli json degil ###' | Out-File (Join-Path $tH 'durum.json') -Encoding utf8
CsvYaz -calisma 12
TakipCalistir
T "bozuk durum.json cokmuyor" (Test-Path (Join-Path $tH 'durum.json')) ''
T "bozuk durum.json sonrasi toparliyor" ((DurumOku).tarih -eq (Bugun)) "tarih=$((DurumOku).tarih)"
'{{{ bozuk' | Out-File (Join-Path $tH 'ayarlar.json') -Encoding utf8
DurumYaz
TakipCalistir
T "bozuk ayarlar.json cokmuyor" ((DurumOku).dakika -ge 0) "dakika=$((DurumOku).dakika)"
AyarYaz
'yok boyle json' | Out-File $gd -Encoding utf8
DurumYaz
TakipCalistir
T "bozuk gecmis.json cokmuyor" (Test-Path (Join-Path $tmp 'Calisma Kaydi.md')) ''
if ([System.IO.File]::Exists($gd)) { [System.IO.File]::Delete($gd) }
"zaman;uygulama;baslik;bosta;kategori;sure`r`nBOZUK SATIR`r`n10:00:00;Obsidian;x;0;calisma;10" | Out-File (Join-Path $tAkt "$(Bugun).csv") -Encoding utf8
DurumYaz
TakipCalistir
T "bozuk CSV satiri cokmuyor" (Test-Path (Join-Path $tmp 'Aktivite Gunlugu.md')) ''
[System.IO.File]::Delete((Join-Path $tAkt "$(Bugun).csv"))
DurumYaz
TakipCalistir
T "CSV hic yoksa cokmuyor" ((DurumOku).dakika -eq 0) "dakika=$((DurumOku).dakika)"
'zaman;uygulama;baslik;bosta;kategori;sure;kaynak' | Out-File (Join-Path $tAkt "$(Bugun).csv") -Encoding utf8
TakipCalistir
T "bos CSV cokmuyor" ((DurumOku).dakika -eq 0) "dakika=$((DurumOku).dakika)"

Baslik '9. SINIR DEGERLER'
AyarYaz -hedef 15; DurumYaz; CsvYaz -calisma 600
TakipCalistir
$km = Get-Content (Join-Path $tmp 'Calisma Kaydi.md') -Raw -Encoding UTF8
T "hedef asiminda cubuk tasmaz" ($km -match '\[####################\]') 'tam dolu'
AyarYaz -hedef 720; DurumYaz; CsvYaz -calisma 6
TakipCalistir
T "hedef 720 kabul edildi" ((Get-Content (Join-Path $tmp 'Calisma Kaydi.md') -Raw -Encoding UTF8) -match '/ 720 dakika') ''
AyarYaz -hedef 240
"zaman;uygulama;baslik;bosta;kategori;sure`r`n10:00:00;test;$('A'*200);0;calisma;10" | Out-File (Join-Path $tAkt "$(Bugun).csv") -Encoding utf8
DurumYaz; TakipCalistir
T "cok uzun baslik cokmuyor" (Test-Path (Join-Path $tmp 'Aktivite Gunlugu.md')) ''
$bl = @('zaman;uygulama;baslik;bosta;kategori;sure')
1..8 | ForEach-Object { $bl += ((Get-Date).AddSeconds(-10*(9-$_)).ToString('HH:mm:ss') + ';test;Turkce GUSIOC baslik;0;calisma;10;izinli') }
($bl -join "`r`n") | Out-File (Join-Path $tAkt "$(Bugun).csv") -Encoding utf8
DurumYaz; TakipCalistir
T "ozel karakterli baslik islendi" ((Get-Content (Join-Path $tmp 'Aktivite Gunlugu.md') -Raw -Encoding UTF8) -match 'GUSIOC') ''

Baslik '10. RAPOR TUTARLILIGI'
AyarYaz -hedef 240; DurumYaz; CsvYaz -calisma 60 -diger 30 -bosta 30
TakipCalistir
$am = Get-Content (Join-Path $tmp 'Aktivite Gunlugu.md') -Raw -Encoding UTF8
T "toplam kayit 20 dk" ($am -match 'Kayit altindaki sure: \*\*20 dk\*\*') "$(([regex]::Match($am,'Kayit altindaki sure: \*\*(.+?)\*\*')).Groups[1].Value)"
$kat = [regex]::Matches($am, '\| (Calisma|Diger|Bosta \(AFK\)) \| (\d+) dk \| %(\d+) \|')
$kt = 0; foreach ($m in $kat) { $kt += [int]$m.Groups[2].Value }
T "kategori toplami = kayit suresi" ($kt -eq 20) "toplam=$kt dk"
$ot = 0; foreach ($m in $kat) { $ot += [int]$m.Groups[3].Value }
T "oranlar toplami ~%100" ($ot -ge 98 -and $ot -le 102) "%$ot"
T "calisma 10 dk / %50" ($am -match '\| Calisma \| 10 dk \| %50 \|') ''
T "sayac raporla tutarli" ((DurumOku).dakika -eq 10) "durum=$((DurumOku).dakika)"

Baslik '11. DURAKLATMA'
AyarYaz -duraklat (Get-Date).AddHours(1).ToString('s')
DurumYaz @{ dakika=99 }; CsvYaz -diger 50
TakipCalistir
T "duraklatildiginda uyari cikmaz" ((BayrakOku) -notmatch 'UYARI') "bayrak='$(BayrakOku)'"
T "duraklatildiginda durum degismez" ((DurumOku).dakika -eq 99) "dakika=$((DurumOku).dakika)"
AyarYaz -duraklat 'sonsuz'
TakipCalistir
T "suresiz duraklatma calisiyor" ((DurumOku).dakika -eq 99) "dakika=$((DurumOku).dakika)"
AyarYaz -duraklat 'bozuk-tarih'
TakipCalistir
T "bozuk duraklat degeri engellemiyor" ((DurumOku).dakika -ne 99) "dakika=$((DurumOku).dakika)"

Baslik '11b. KURULUM TURU: HATIRLATMA VE EKRAN KILIDI'
$bilgiD = Join-Path $tmp 'dagitik\kurulum-bilgisi.json'
function BilgiYaz { param($json)
    if (-not $json) { if ([System.IO.File]::Exists($bilgiD)) { [System.IO.File]::Delete($bilgiD) }; return }
    [void][System.IO.Directory]::CreateDirectory((Split-Path $bilgiD)); [System.IO.File]::WriteAllText($bilgiD, $json) }
function AyarHam { param($json) [System.IO.File]::WriteAllText((Join-Path $tH 'ayarlar.json'), $json) }
BilgiYaz $null; AyarYaz; DurumYaz; CsvYaz -diger 20
TakipCalistir
T "tur yok (eski kurulum): tam ekran kilitli uyari" ((BayrakOku) -match 'UYARI kilit=True form=None ust=True') "bayrak=$(BayrakOku)"
BilgiYaz '{"kurulumTuru":"sirket","ozellikler":{"hatirlatmalar":false,"ekranKilidi":false}}'
AyarYaz; DurumYaz; CsvYaz -calisma 6 -diger 20
TakipCalistir
T "sirket: uyari cikmaz" ((BayrakOku) -notmatch 'UYARI') "bayrak='$(BayrakOku)'"
T "sirket: olcum surer" ((DurumOku).dakika -eq 1) "dakika=$((DurumOku).dakika)"
T "sirket: uyari sayaci/zamani degismez" ((DurumOku).uyari -eq 0 -and -not (DurumOku).sonUyari) "uyari=$((DurumOku).uyari)"
AyarHam '{"hedef":240,"duraklat":"","hatirlatmalar":true}'
DurumYaz; CsvYaz -diger 20
TakipCalistir
T "sirket: ayarlar hatirlatmayi acamaz" ((BayrakOku) -notmatch 'UYARI') "bayrak='$(BayrakOku)'"
AyarYaz -hedef 60; DurumYaz; CsvYaz -calisma 360
TakipCalistir
T "sirket: hedef mesaji cikmaz" ((BayrakOku) -notmatch 'KUTLAMA') "bayrak='$(BayrakOku)'"
T "sirket: hedef yine kaydedilir" ((DurumOku).kutlandi -eq $true -and (DurumOku).dakika -ge 60) "kutlandi=$((DurumOku).kutlandi)"
BilgiYaz '{"kurulumTuru":"ozel","ozellikler":{"hatirlatmalar":true,"ekranKilidi":false}}'
AyarYaz; DurumYaz; CsvYaz -diger 20
TakipCalistir
T "ozel, kilit kapali: uyari normal pencerede" ((BayrakOku) -match 'UYARI kilit=False form=FixedDialog ust=False') "bayrak=$(BayrakOku)"
DurumYaz; CsvYaz -diger 20
TakipCalistir -yanit 'Abort'
$su = (DurumOku).sonUyari
if ($su -isnot [datetime]) { $su = [datetime]::ParseExact([string]$su, 's', [Globalization.CultureInfo]::InvariantCulture) }
T "pencere secimsiz kapatilinca sonraki uyari 45 dk sonra" ([math]::Abs(((Get-Date) - $su).TotalMinutes) -lt 2) "sonUyari=$su"
CsvYaz -diger 20
TakipCalistir
T "kapatildiktan hemen sonra uyari tekrar cikmaz" ((BayrakOku) -notmatch 'UYARI') "bayrak='$(BayrakOku)'"
BilgiYaz $null
AyarHam '{"hedef":240,"duraklat":"","ekranKilidi":false}'
DurumYaz; CsvYaz -diger 20
TakipCalistir
T "bireysel + Ayarlar'da kilit kapali: normal pencere" ((BayrakOku) -match 'UYARI kilit=False') "bayrak=$(BayrakOku)"
AyarHam '{"hedef":240,"duraklat":"","hatirlatmalar":false}'
DurumYaz; CsvYaz -diger 20
TakipCalistir
T "bireysel + Ayarlar'da hatirlatma kapali: uyari yok" ((BayrakOku) -notmatch 'UYARI') "bayrak='$(BayrakOku)'"
T "ayarlar.json alanlari takip turunda korunur" ((Get-Content (Join-Path $tH 'ayarlar.json') -Raw) -match '"hatirlatmalar":false') ''
BilgiYaz $null; AyarYaz

Baslik '12. LOG ROTASYONU'
AyarYaz; DurumYaz; CsvYaz -calisma 12
$lg = Join-Path $tH 'log.txt'
(1..900 | ForEach-Object { "dolgu $_" }) -join "`r`n" | Out-File $lg -Encoding utf8
TakipCalistir
$ss = @(Get-Content $lg -Encoding UTF8).Count
T "log 800'u gecince kirpiliyor" ($ss -le 510) "$ss satir"
T "kirpma sonrasi taze kayit var" (((Get-Content $lg -Encoding UTF8 -Tail 3) -join ' ') -match 'tick') ''

Baslik '13. TEK ORNEK KILIDI'
$src = Get-Content (Join-Path $hDir 'takip.ps1') -Raw -Encoding UTF8
T "takip.ps1 mutex kilidi" ($src -match 'CalismaTakip_') ''
T "izleyici.ps1 mutex kilidi" ((Get-Content (Join-Path $hDir 'izleyici.ps1') -Raw -Encoding UTF8) -match 'CalismaTakipIzleyici_') ''
T "mutex kasa yoluna ozel" ($src -match 'ComputeHash') 'MD5(klasor)'

Baslik '14. YOL BAGIMSIZLIGI'
foreach ($f in @('takip.ps1','izleyici.ps1','kontrol.ps1','baslangic.ps1')) {
    $c = Get-Content (Join-Path $hDir $f) -Raw -Encoding UTF8
    # Herhangi bir kullanici profiline sabit yol (C:\Users\<ad>) olmamali; betikler PSScriptRoot'a gore calisir
    $sb = [regex]::Matches($c, '[A-Za-z]:[\\/]Users[\\/][^\\/''"\s]+').Count
    T "$f sabit yol icermiyor" ($sb -eq 0) "$sb tane"
}
T "takip.ps1 PSScriptRoot kullaniyor" ($src -match 'PSScriptRoot') ''

Baslik '15. GIZLI BASLATICI'
$vbs = Get-Content (Join-Path $hDir 'gizli.vbs') -Raw
T "gizli.vbs mevcut" ($vbs.Length -gt 0) "$($vbs.Length) karakter"
T "pencere stili 0 (gizli)" ($vbs -match 'Run cmd, 0, False') ''
T "ExecutionPolicy Bypass" ($vbs -match 'ExecutionPolicy Bypass') ''
$gorev = Get-ScheduledTask -TaskName 'Calisma Takip Sistemi' -ErrorAction SilentlyContinue
if ($gorev) {
    T "gorev wscript kullaniyor" ($gorev.Actions[0].Execute -match 'wscript') ''
    T "gorev gizli.vbs cagiriyor" ($gorev.Actions[0].Arguments -match 'gizli\.vbs') ''
}

if ([System.IO.Directory]::Exists($tmp)) { [System.IO.Directory]::Delete($tmp, $true) }
Write-Host "`n=======================================" -ForegroundColor Cyan
Write-Host ("  GECTI: {0}   KALDI: {1}" -f $gecti,$kaldi) -ForegroundColor $(if($kaldi -eq 0){'Green'}else{'Red'})
Write-Host "=======================================`n" -ForegroundColor Cyan







# --- Test bitti: acilan pencereleri ve gecici kasalari topla ---
$env:CALISMATAKIP_TEST_SN = ''
& $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $hDir 'test-temizlik.ps1') | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
exit $(if ($kaldi -gt 0) { 1 } else { 0 })
