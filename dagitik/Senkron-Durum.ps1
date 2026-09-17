# Anahtar, sunucu adresi veya kural icerigi donmez.
function Get-CtSenkronDurumu {
    param([string]$Klasor, [object]$Ayar)
    if ($null -eq $Ayar) { $Ayar = Read-DagitikJson (Join-Path $Klasor 'merkez.json') }
    $kuyruk = Read-DagitikJson (Join-Path $Klasor 'kural-outbox.json')
    $bekleyen = @()
    if ($null -ne $kuyruk) { $bekleyen = @($kuyruk) }
    $hatalar = @()
    foreach ($alan in 'sonHata','kuralGonderimHata','kuralAlimHata','ortakSayacHata') {
        $metin = [string](Get-DagitikDeger $Ayar $alan '')
        if ($metin) { $hatalar += ConvertTo-DagitikSinirliMetin $metin 180 }
    }
    $kuyrukBozuk = (Test-Path -LiteralPath (Join-Path $Klasor 'kural-outbox.json')) -and $null -eq $kuyruk
    if ($kuyrukBozuk) { $hatalar += 'Karar kuyruğu okunamıyor.' }
    return [ordered]@{
        kayitli = ($null -ne $Ayar)
        aktif = [bool](Get-DagitikDeger $Ayar 'aktif' $false)
        sonBasariliGonderimUtc = [string](Get-DagitikDeger $Ayar 'sonBasariliSenkronUtc' '')
        sonKuralAlimiUtc = [string](Get-DagitikDeger $Ayar 'sonKuralAlimiUtc' '')
        kuralSurumuUtc = [string](Get-DagitikDeger $Ayar 'kuralSenkronUtc' '')
        bekleyenKarar = $(if ($kuyrukBozuk) { $null } else { $bekleyen.Count })
        bekleyenOzet = @(Get-ChildItem -LiteralPath (Join-Path $Klasor 'merkez-outbox') -Filter '*.json' -File -ErrorAction SilentlyContinue).Count
        hata = ($hatalar -join ' | ')
        bildirimUtc = [DateTime]::UtcNow.ToString('o')
    }
}

function Get-CtAgHatasi {
    param([object]$Hata, [string]$Adim)
    $kod = 0
    try { $kod = [int]$Hata.Exception.Response.StatusCode } catch { }
    switch ($kod) {
        401 { return "$Adim : cihaz kimliği veya anahtar kabul edilmedi (HTTP 401)." }
        403 { return "$Adim : cihazın işlem yetkisi yok (HTTP 403)." }
        429 { return "$Adim : istek sınırına ulaşıldı (HTTP 429)." }
    }
    if ($kod -gt 0) { return "$Adim : merkez HTTP $kod döndürdü." }
    return "$Adim : bağlantı kurulamadı, zaman aşımı veya yanıt işleme hatası."
}