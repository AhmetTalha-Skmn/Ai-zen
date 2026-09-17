# ============================================================
#  Gunaydin -- ~/.claude/settings.json icindeki UserPromptSubmit hook'u, mesaj
#  "gunaydin" ile basliyorsa bunu calistirir. Butun is api.ps1'de (Takip-Brifing);
#  burasi yalnizca Claude hook bicimine ceviren ince katman: hazir brifing metni
#  additionalContext'e konur -> Claude dosya okumadan, arac cagirmadan gosterir.
#  Hicbir kosulda hata firlatmaz; kullanicinin mesajini engellemez.
# ============================================================
$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'
$baglam = ''; $mesaj = ''
try {
    . (Join-Path $PSScriptRoot 'api.ps1')
    $b = Takip-Brifing -Kaydet
    # Hook her klasorde calisir; komut ipucu mutlak yol vermeli
    $api = (Join-Path $PSScriptRoot 'api.ps1').Replace('\', '/')
    $sorular = ''
    if (@($b.bekleyenSorular).Count) { $sorular = " Sorulacak siniflandirmalar var: kullanicinin acik kararini siniflandir ile uygula (MCP araci ya da: powershell -NoProfile -ExecutionPolicy Bypass -File $api siniflandir -Oge <ad> -Karar <calisma|yasakli|belirsiz>)." }
    $baglam = "GUNLUK CALISMA OZETI (hook uretti, gunluge yazildi). Asagidaki metni kullaniciya oldugu gibi goster; takip verisi icin ham dosya okuma.$sorular Sonra 'gunaydin' skill'inin kalan adimlarini izle.`n`n$($b.metin)"
    $mesaj = "Gunaydin! Brifing hazir (takip: $($b.saglik.durum))."
} catch {
    $baglam = "SABAH BRIFINGI URETILEMEDI ($($_.Exception.Message)). 'gunaydin' skill'indeki yedek yolu izle."
    $mesaj = 'Gunaydin! Brifing uretilemedi; yedek yol kullanilacak.'
}
$cikti = [ordered]@{ systemMessage = $mesaj; hookSpecificOutput = [ordered]@{ hookEventName = 'UserPromptSubmit'; additionalContext = $baglam } }
# Turkce Windows'ta konsol kod sayfasi 857; Claude Code stdout'u UTF-8 okur (BOM'suz)
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false
[Console]::Out.Write((ConvertTo-Json -InputObject $cikti -Depth 4 -Compress))
exit 0
