# ============================================================
#  Aizen (Çalışma Takip) MCP sunucusu -- stdio, JSON-RPC 2.0, satir basina bir mesaj
#  Bu dosya UTF-8 BOM ile kaydedilir (Turkce arac aciklamalari icin).
#  MCP destekleyen her istemci baglanabilir (Claude, Cursor, VS Code, Gemini CLI...):
#    command: powershell.exe
#    args:    -NoProfile -ExecutionPolicy Bypass -File <kurulum-klasoru>/hatirlatici/mcp.ps1
#  Butun is api.ps1'de; burasi yalnizca protokol katmani.
#  KURAL: stdout'a protokol mesaji disinda hicbir sey yazilmaz (tek bir satir bile istemciyi bozar).
# ============================================================
$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'api.ps1')

$utf8 = New-Object System.Text.UTF8Encoding $false
$giris = New-Object System.IO.StreamReader([Console]::OpenStandardInput(), $utf8)
$cikis = New-Object System.IO.StreamWriter([Console]::OpenStandardOutput(), $utf8)
$cikis.AutoFlush = $true
$cikis.NewLine = "`n"

$SURUMLER = @('2024-11-05', '2025-03-26', '2025-06-18')
$TALIMAT = 'Kullanıcının bağımsız çalışma takip sistemi. Günün ilk oturumunda ya da kullanıcı "günaydın" dediğinde sabah_brifingi çağır ve dönen metni olduğu gibi göster. Bekleyen sınıflandırmalar varsa kullanıcıya sor, kararını siniflandir ile uygula. Veriyi yorumlarken ahlak dersi verme. Ham dosyaları (aktivite CSV, rapor JSON, kurallar.json) okuma; bu araçlar aynı bilgiyi kompakt verir.'

function Sema { param($ozellikler, $zorunlu)
    $o = [ordered]@{ type = 'object'; properties = $ozellikler }
    if ($zorunlu) { $o.required = @($zorunlu) }
    return $o }
$ARACLAR = @(
    [ordered]@{ name = 'sabah_brifingi'
        description = 'Günlük çalışma özeti: dünün gün sonu özeti, bugünkü sayaç ve seri, takip sağlığı ve sorulacak sınıflandırmalar. Kullanıcı "günaydın" dediğinde veya günün ilk oturumunda çağır. İlk içerik kullanıcıya olduğu gibi gösterilecek hazır metin, ikincisi aynı verinin JSON''u. Dünün raporu gerekirse yeniden üretilir (~5 sn).'
        inputSchema = (Sema ([ordered]@{ kaydet = [ordered]@{ type = 'boolean'; description = 'Brifingi günlük dosyalarına yaz (varsayılan true)' } })) }
    [ordered]@{ name = 'takip_durum'
        description = 'Bugünkü çalışma dakikası, hedef, seri, erteleme hakkı ve takip sisteminin sağlığı (zamanlanmış görev, izleyici). Hızlı, yan etkisiz.'
        inputSchema = (Sema ([ordered]@{})) }
    [ordered]@{ name = 'gun_raporu'
        description = 'Bir günün kompakt özeti: çalışma/diğer/boşta dakikaları, en çok vakit alan yasaklı ve çalışma uygulamaları, pencere başlıkları, tarayıcı, sorulacak sınıflandırmalar.'
        inputSchema = (Sema ([ordered]@{ tarih = [ordered]@{ type = 'string'; description = 'YYYY-MM-DD; boşsa bugün' } })) }
    [ordered]@{ name = 'siniflandir'
        description = 'Bir uygulamayı (surec), pencere başlığındaki kelimeyi (baslik) veya alan adını (alanadi) çalışma, yasaklı ya da bilerek-belirsiz olarak işaretler. YALNIZCA kullanıcı açıkça karar verdiğinde çağır. Yasaklı: çalışma periyodunda anında engel ekranı demektir.'
        inputSchema = (Sema ([ordered]@{
            oge   = [ordered]@{ type = 'string'; description = 'Süreç adı, başlık kelimesi veya alan adı (rapordaki haliyle)' }
            karar = [ordered]@{ type = 'string'; enum = @('calisma', 'yasakli', 'belirsiz') }
            tur   = [ordered]@{ type = 'string'; enum = @('surec', 'baslik', 'alanadi'); description = 'Varsayılan surec' } }) @('oge', 'karar')) }
)

function Gonder { param($obj) $cikis.WriteLine((ConvertTo-Json -InputObject $obj -Depth 20 -Compress)) }
function Sonuc { param($id, $result) Gonder ([ordered]@{ jsonrpc = '2.0'; id = $id; result = $result }) }
function Hata { param($id, [int]$kod, [string]$mesaj) Gonder ([ordered]@{ jsonrpc = '2.0'; id = $id; error = [ordered]@{ code = $kod; message = $mesaj } }) }
# Istemcinin baglamini sisirmesin: her metin en fazla 20.000 karakter (bir kez 75.000 karakterlik cikti oldu)
function AracSonucu { param($metinler, [bool]$hata = $false)
    return [ordered]@{ content = @(@($metinler) | ForEach-Object { $t = [string]$_; if ($t.Length -gt 20000) { $t = $t.Substring(0, 20000) + ' ...(kirpildi)' }; [ordered]@{ type = 'text'; text = $t } }); isError = $hata } }
function Json { param($o) return (ConvertTo-Json -InputObject $o -Depth 8 -Compress) }

while ($true) {
    $satir = $giris.ReadLine()
    if ($null -eq $satir) { break }
    $satir = $satir.TrimStart([char]0xFEFF)   # bazi borular akisin basina BOM koyar (PS 5.1 $OutputEncoding gibi)
    if ([string]::IsNullOrWhiteSpace($satir)) { continue }
    $istek = $null
    try { $istek = ConvertFrom-Json $satir -ErrorAction Stop } catch { Hata $null -32700 'Parse error'; continue }
    # id'si olmayan mesaj bildirimdir (notifications/initialized vb.): cevap verilmez. id 0 olabilir, varligina bak.
    if (-not $istek.PSObject.Properties['id']) { continue }
    $id = $istek.id; $m = [string]$istek.method
    try {
        switch ($m) {
            'initialize' {
                $v = [string]$istek.params.protocolVersion
                if ($SURUMLER -notcontains $v) { $v = $SURUMLER[-1] }
                Sonuc $id ([ordered]@{ protocolVersion = $v; capabilities = [ordered]@{ tools = [ordered]@{ listChanged = $false } }
                    serverInfo = [ordered]@{ name = 'calisma-takip'; version = '2.0.0' }; instructions = $TALIMAT })
            }
            'ping' { Sonuc $id ([ordered]@{}) }
            'tools/list' { Sonuc $id ([ordered]@{ tools = $ARACLAR }) }
            'tools/call' {
                $ad = [string]$istek.params.name; $a = $istek.params.arguments
                switch ($ad) {
                    'sabah_brifingi' {
                        $kaydet = $true; if ($a -and $null -ne $a.kaydet) { $kaydet = [bool]$a.kaydet }
                        $b = Takip-Brifing -Kaydet:$kaydet; $metin = $b.metin; $b.Remove('metin')
                        Sonuc $id (AracSonucu @($metin, (Json $b)))
                    }
                    'takip_durum' { Sonuc $id (AracSonucu (Json (Takip-Durum))) }
                    'gun_raporu'  { Sonuc $id (AracSonucu (Json (Takip-Rapor -Tarih ([string]$a.tarih)))) }
                    'siniflandir' {
                        $t = 'surec'; if ($a.tur) { $t = [string]$a.tur }
                        Sonuc $id (AracSonucu (Json (Takip-Siniflandir -Oge ([string]$a.oge) -Karar ([string]$a.karar) -Tur $t)))
                    }
                    default { Hata $id -32602 "Bilinmeyen araç: $ad" }
                }
            }
            'resources/list'           { Sonuc $id ([ordered]@{ resources = @() }) }
            'resources/templates/list' { Sonuc $id ([ordered]@{ resourceTemplates = @() }) }
            'prompts/list'             { Sonuc $id ([ordered]@{ prompts = @() }) }
            default { Hata $id -32601 "Method not found: $m" }
        }
    } catch {
        if ($m -eq 'tools/call') { Sonuc $id (AracSonucu "Hata: $($_.Exception.Message)" $true) } else { Hata $id -32603 $_.Exception.Message }
    }
}
