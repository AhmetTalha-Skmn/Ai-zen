# ============================================================
#  Tarayici gecmisi okuyucu
#  Windows'un yerlesik winsqlite3.dll'i ile okur -- kurulum gerekmez.
#  Veri YALNIZCA yerelde kalir, hicbir yere gonderilmez.
# ============================================================
param([int]$GunSayisi = 1)
$ErrorActionPreference = 'SilentlyContinue'

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class SQL {
  [DllImport("winsqlite3.dll", EntryPoint="sqlite3_open16", CharSet=CharSet.Unicode)]
  public static extern int Open(string f, out IntPtr db);
  [DllImport("winsqlite3.dll", EntryPoint="sqlite3_prepare16_v2", CharSet=CharSet.Unicode)]
  public static extern int Prepare(IntPtr db, string sql, int n, out IntPtr st, IntPtr tail);
  [DllImport("winsqlite3.dll", EntryPoint="sqlite3_step")]
  public static extern int Step(IntPtr st);
  [DllImport("winsqlite3.dll", EntryPoint="sqlite3_column_text16")]
  public static extern IntPtr Text(IntPtr st, int c);
  [DllImport("winsqlite3.dll", EntryPoint="sqlite3_column_int64")]
  public static extern long Int64(IntPtr st, int c);
  [DllImport("winsqlite3.dll", EntryPoint="sqlite3_finalize")]
  public static extern int Final(IntPtr st);
  [DllImport("winsqlite3.dll", EntryPoint="sqlite3_close")]
  public static extern int Close(IntPtr db);
}
"@

function SorguCalistir { param($dosya, $sql, $kolonTipleri)
    $sonuc = New-Object System.Collections.ArrayList
    $gecici = Join-Path $env:TEMP ("hist_" + [guid]::NewGuid().ToString('N').Substring(0,8) + ".db")
    try { Copy-Item $dosya $gecici -Force -ErrorAction Stop } catch { return $sonuc }
    $db = [IntPtr]::Zero; $st = [IntPtr]::Zero
    if ([SQL]::Open($gecici, [ref]$db) -ne 0) { [System.IO.File]::Delete($gecici); return $sonuc }
    if ([SQL]::Prepare($db, $sql, -1, [ref]$st, [IntPtr]::Zero) -ne 0) { [void][SQL]::Close($db); [System.IO.File]::Delete($gecici); return $sonuc }
    while ([SQL]::Step($st) -eq 100) {
        $satir = @()
        for ($i = 0; $i -lt $kolonTipleri.Count; $i++) {
            if ($kolonTipleri[$i] -eq 'n') { $satir += [SQL]::Int64($st, $i) }
            else { $satir += [Runtime.InteropServices.Marshal]::PtrToStringUni([SQL]::Text($st, $i)) }
        }
        [void]$sonuc.Add($satir)
    }
    [void][SQL]::Final($st); [void][SQL]::Close($db)
    [System.IO.File]::Delete($gecici)
    return $sonuc }

$esik = (Get-Date).Date.AddDays(-($GunSayisi - 1))
# Chromium: 1601'den beri mikrosaniye | Firefox: 1970'ten beri mikrosaniye
$chromeEsik  = [long](($esik.ToUniversalTime() - [datetime]'1601-01-01').TotalSeconds * 1000000)
$firefoxEsik = [long](($esik.ToUniversalTime() - [datetime]'1970-01-01').TotalSeconds * 1000000)

$LA = $env:LOCALAPPDATA; $AD = $env:APPDATA
$tarayicilar = @(
    @{ ad='Brave';   tip='chromium'; yol="$LA\BraveSoftware\Brave-Browser\User Data" }
    @{ ad='Chrome';  tip='chromium'; yol="$LA\Google\Chrome\User Data" }
    @{ ad='Edge';    tip='chromium'; yol="$LA\Microsoft\Edge\User Data" }
    @{ ad='Opera';   tip='chromium'; yol="$AD\Opera Software\Opera Stable" }
    @{ ad='Firefox'; tip='firefox';  yol="$AD\Mozilla\Firefox\Profiles" }
)

$ziyaretler = New-Object System.Collections.ArrayList
$aramalar   = New-Object System.Collections.ArrayList

foreach ($t in $tarayicilar) {
    if (-not (Test-Path $t.yol)) { continue }
    if ($t.tip -eq 'chromium') {
        $profiller = @(Get-ChildItem $t.yol -Directory | Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile*' })
        if ($t.ad -eq 'Opera') { $profiller = @([pscustomobject]@{ FullName = $t.yol; Name = 'Default' }) }
        foreach ($p in $profiller) {
            $hf = Join-Path $p.FullName 'History'
            if (-not (Test-Path $hf)) { continue }
            foreach ($r in (SorguCalistir $hf "SELECT url,title,last_visit_time,visit_count FROM urls WHERE last_visit_time > $chromeEsik ORDER BY last_visit_time DESC LIMIT 3000" @('s','s','n','n'))) {
                [void]$ziyaretler.Add([pscustomobject]@{
                    tarayici=$t.ad; url=$r[0]; baslik=$r[1]; sayi=$r[3]
                    zaman=([datetime]::FromFileTimeUtc($r[2] * 10)).ToLocalTime() })
            }
            foreach ($r in (SorguCalistir $hf "SELECT k.term,u.url,u.last_visit_time FROM keyword_search_terms k JOIN urls u ON k.url_id=u.id WHERE u.last_visit_time > $chromeEsik ORDER BY u.last_visit_time DESC LIMIT 1000" @('s','s','n'))) {
                [void]$aramalar.Add([pscustomobject]@{
                    tarayici=$t.ad; terim=$r[0]; url=$r[1]
                    zaman=([datetime]::FromFileTimeUtc($r[2] * 10)).ToLocalTime() })
            }
        }
    } else {
        foreach ($p in @(Get-ChildItem $t.yol -Directory)) {
            $hf = Join-Path $p.FullName 'places.sqlite'
            if (-not (Test-Path $hf)) { continue }
            foreach ($r in (SorguCalistir $hf "SELECT url,title,last_visit_date,visit_count FROM moz_places WHERE last_visit_date > $firefoxEsik ORDER BY last_visit_date DESC LIMIT 3000" @('s','s','n','n'))) {
                [void]$ziyaretler.Add([pscustomobject]@{
                    tarayici=$t.ad; url=$r[0]; baslik=$r[1]; sayi=$r[3]
                    zaman=([datetime]'1970-01-01').AddSeconds($r[2]/1000000).ToLocalTime() })
            }
        }
    }
}

$json = [pscustomobject]@{ ziyaretler = @($ziyaretler); aramalar = @($aramalar) } | ConvertTo-Json -Depth 4 -Compress
# Cikti konsol kod sayfasiyla (857) tasinir; Windows'un "en yakin karsilik" donusumu karakter degistirir:
# kivrik tirnak (U+201C) -> ASCII tirnak (JSON'u bozar -- 2026-09-10 raporu boyle okunamadi), emoji -> ??.
# Cozum: ASCII disi her karakteri \uXXXX olarak kacir; her kod sayfasinda bozulmadan tasinir, ConvertFrom-Json geri cozer.
[regex]::Replace($json, '[^\x00-\x7F]', { param($m) '\u{0:x4}' -f [int][char]$m.Value })
