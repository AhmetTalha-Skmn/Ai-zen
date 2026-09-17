# ============================================================
#  Gunluk rapor -- aktivite kaydi + (varsa) tarayici gecmisi
#  Ciktisi: hatirlatici/rapor/YYYY-MM-DD.json  ve okunabilir ozet
# ============================================================
param([string]$Tarih = (Get-Date).ToString('yyyy-MM-dd'), [switch]$GecmisDahil)
$bakimIsareti = Join-Path $PSScriptRoot 'GERI-YUKLEME'; if (Test-Path -LiteralPath $bakimIsareti) { try { [IO.File]::Open($bakimIsareti, 'Open', 'ReadWrite', 'None').Dispose(); [IO.File]::Delete($bakimIsareti) } catch { exit 0 } }
$ErrorActionPreference = 'SilentlyContinue'
$hDir = $PSScriptRoot; if (-not $hDir) { $hDir = Split-Path $MyInvocation.MyCommand.Path -Parent }
$klasor = Split-Path $hDir -Parent
$raporDir = Join-Path $hDir 'rapor'
[void][System.IO.Directory]::CreateDirectory($raporDir)

$K = $null
try { $K = Get-Content (Join-Path $hDir 'kurallar.json') -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
function Eslesir { param($m,$l) if ([string]::IsNullOrWhiteSpace($m)) { return $false }
    foreach ($x in $l) { if ($x -and $m -like "*$x*") { return $true } }; return $false }

# ---------- 1) Aktivite ----------
$csv = Join-Path $hDir "aktivite\$Tarih.csv"
$rw = @(); if (Test-Path $csv) { $rw = @(Import-Csv $csv -Delimiter ';' -Encoding UTF8) }
function Sn { param($l) $t=0; foreach ($x in $l) { $t += [int]$x.sure }; return $t }

$uygulamalar = @()
foreach ($g in ($rw | Group-Object uygulama)) {
    $uygulamalar += [pscustomobject]@{
        ad      = $g.Name
        dakika  = [math]::Round((Sn $g.Group)/60)
        kategori= ($g.Group | Group-Object kategori | Sort-Object Count -Descending | Select-Object -First 1).Name
        kaynak  = ($g.Group | Group-Object kaynak   | Sort-Object Count -Descending | Select-Object -First 1).Name
        ornekBaslik = ($g.Group | Where-Object { $_.baslik -ne '' } | Select-Object -First 1).baslik
    }
}
$basliklar = @()
foreach ($g in ($rw | Where-Object { $_.baslik -ne '' } | Group-Object { "$($_.uygulama)|$($_.baslik)" })) {
    $p = $g.Name -split '\|',2
    $dk = [math]::Round((Sn $g.Group)/60)
    if ($dk -ge 1) { $basliklar += [pscustomobject]@{ uygulama=$p[0]; baslik=$p[1]; dakika=$dk } }
}

# ---------- 2) Tarayici gecmisi (istege bagli) ----------
# Okuyucunun dondurdugu zaman JSON'dan UTC olarak geri gelir (\/Date()\/ bicimi).
# Gune ayirmadan once yerel saate cevir; yoksa gece 00:00-03:00 ziyaretleri bir onceki gune yazilir.
function YerelGun { param($z) $t = [datetime]$z; if ($t.Kind -eq [DateTimeKind]::Utc) { $t = $t.ToLocalTime() }; return $t.ToString('yyyy-MM-dd') }
$alanlar = @(); $aramalar = @(); $gecmisDurum = 'atlandi'
if ($GecmisDahil) {
    $og = Join-Path $hDir 'gecmis-okuyucu.ps1'
    if (Test-Path $og) {
        try {
            # Okuyucu "bugun 00:00'dan beri" okur. Gecmis bir gunun raporunda o gune kadar geri git,
            # yoksa sabah uretilen dunku rapor tarayici verisini sifir gosterir (2026-09-10'da bulundu).
            $gunSayisi = 1
            try { $gunSayisi = [math]::Max(1, ((Get-Date).Date - [datetime]::ParseExact($Tarih, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)).Days + 1) } catch { }
            $ham = & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File $og -GunSayisi $gunSayisi
            $g = $ham | ConvertFrom-Json
            $gunZiyaret = 0
            $grup = @{}
            foreach ($z in $g.ziyaretler) {
                if ($z.zaman -and (YerelGun $z.zaman) -ne $Tarih) { continue }
                $gunZiyaret++
                $dom = ''
                try { $dom = ([uri]$z.url).Host -replace '^www\.','' } catch { }
                # chrome://, about:, file:// gibi sema-ici URL'lerde host bos olur -- atla
                if ([string]::IsNullOrWhiteSpace($dom)) { continue }
                if (-not $grup.ContainsKey($dom)) { $grup[$dom] = 0 }
                $grup[$dom] = $grup[$dom] + 1
            }
            foreach ($d in $grup.Keys) {
                $kat = 'belirsiz'
                if (Eslesir $d $K.yasakli.alanadi) { $kat = 'yasakli' }
                elseif (Eslesir $d $K.calisma.alanadi) { $kat = 'calisma' }
                $alanlar += [pscustomobject]@{ alan=$d; ziyaret=$grup[$d]; kategori=$kat }
            }
            foreach ($a in $g.aramalar) {
                if ($a.zaman -and (YerelGun $a.zaman) -ne $Tarih) { continue }
                $aramalar += [pscustomobject]@{ terim=$a.terim; tarayici=$a.tarayici }
            }
            # Sayilar yalnizca raporun gunune ait (okuyucu birden fazla gun dondurebilir)
            $gecmisDurum = "okundu ($gunZiyaret ziyaret, $($aramalar.Count) arama)"
        } catch {
            # PS 5.1 ConvertFrom-Json hata mesajina girdinin TAMAMINI ekler (on binlerce karakter) -- kirp
            $hm = [string]$_.Exception.Message; if ($hm.Length -gt 120) { $hm = $hm.Substring(0, 120) + '...' }
            $gecmisDurum = "okunamadi: $hm"
        }
    } else { $gecmisDurum = 'gecmis-okuyucu.ps1 bulunamadi' }
}

# ---------- 3) Ozet ----------
$toplamDk   = [math]::Round((Sn $rw)/60)
$calismaDk  = [math]::Round((Sn @($rw | Where-Object { $_.kategori -eq 'calisma' }))/60)
$digerDk    = [math]::Round((Sn @($rw | Where-Object { $_.kategori -eq 'diger'   }))/60)
$bostaDk    = [math]::Round((Sn @($rw | Where-Object { $_.kategori -eq 'bosta'   }))/60)
$hedef = 240; try { $hedef = [int](Get-Content (Join-Path $hDir 'ayarlar.json') -Raw -Encoding UTF8 | ConvertFrom-Json).hedef } catch { }

$rapor = [ordered]@{
    tarih            = $Tarih
    hedefDk          = $hedef
    calismaDk        = $calismaDk
    digerDk          = $digerDk
    bostaDk          = $bostaDk
    kayitDk          = $toplamDk
    hedefTuttuMu     = ($calismaDk -ge $hedef)
    uygulamalar      = @($uygulamalar | Sort-Object dakika -Descending)
    enCokBakilan     = @($basliklar   | Sort-Object dakika -Descending | Select-Object -First 25)
    incelenecekUygulamalar = @($uygulamalar | Where-Object { $_.kaynak -eq 'belirsiz' } | Sort-Object dakika -Descending)
    tarayiciDurum    = $gecmisDurum
    alanlar          = @($alanlar   | Sort-Object ziyaret -Descending)
    incelenecekAlanlar = @($alanlar | Where-Object { $_.kategori -eq 'belirsiz' } | Sort-Object ziyaret -Descending)
    aramalar         = @($aramalar)
}
$rapor | ConvertTo-Json -Depth 5 | Out-File (Join-Path $raporDir "$Tarih.json") -Encoding utf8

Write-Output "===== $Tarih ====="
Write-Output ("Calisma: {0} dk / {1} dk hedef   |   Diger: {2} dk   |   Bosta: {3} dk" -f $calismaDk,$hedef,$digerDk,$bostaDk)
Write-Output ""
Write-Output "--- Uygulamalar ---"
foreach ($u in ($rapor.uygulamalar | Select-Object -First 20)) {
    Write-Output ("  {0,-26} {1,4} dk   {2,-8} ({3})" -f $u.ad, $u.dakika, $u.kategori, $u.kaynak)
}
if ($rapor.incelenecekUygulamalar.Count -gt 0) {
    Write-Output ""
    Write-Output "--- INCELENECEK: siniflandirilmamis uygulamalar ---"
    foreach ($u in $rapor.incelenecekUygulamalar) { Write-Output ("  {0,-26} {1,4} dk   ornek: {2}" -f $u.ad, $u.dakika, $u.ornekBaslik) }
}
Write-Output ""
Write-Output "--- Tarayici gecmisi: $gecmisDurum ---"
if ($rapor.incelenecekAlanlar.Count -gt 0) {
    Write-Output "--- INCELENECEK: siniflandirilmamis alan adlari ---"
    foreach ($a in ($rapor.incelenecekAlanlar | Select-Object -First 25)) { Write-Output ("  {0,-36} {1,3} ziyaret" -f $a.alan, $a.ziyaret) }
}
Write-Output ""
Write-Output "JSON: $(Join-Path $raporDir "$Tarih.json")"

