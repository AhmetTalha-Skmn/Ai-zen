#!/bin/bash
# Mac kurulum/güncelleme/kaldırma mantığının tek sahibi bu betiktir.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
[[ "$(uname -s)" == Darwin ]] || { echo "Yalnız macOS üzerinde çalışır." >&2; exit 1; }
MODE=install
if [[ $# -gt 0 ]]; then MODE="$1"; fi
[[ "$MODE" == install || "$MODE" == uninstall ]] || { echo "Geçersiz işlem." >&2; exit 1; }
PARENT="$HOME/Applications"
TARGET="$PARENT/Aizen.app"
# Uygulamanın önceki adı. Paket kimliği, çalıştırılabilir dosya ve veri klasörü değişmedi;
# güncelleme eski paketi kaldırır, veriler (Application Support/CalismaTakip) yerinde kalır.
LEGACY="$PARENT/Calisma Takip.app"
if pgrep -x CalismaTakip >/dev/null; then
    echo "Önce menü çubuğundan Aizen > Çıkış seçin; sonra tekrar çalıştırın." >&2
    exit 1
fi
for APP_PATH in "$TARGET" "$LEGACY"; do
    [[ ! -L "$APP_PATH" ]] || { echo "Uygulama yolu sembolik bağlantı olamaz: $APP_PATH" >&2; exit 1; }
    if [[ -e "$APP_PATH" ]]; then
        ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Contents/Info.plist" 2>/dev/null || true)"
        [[ "$ID" == local.calisma-takip.macos ]] || { echo "Bu adla başka bir uygulama var; korundu: $APP_PATH" >&2; exit 1; }
    fi
done
if [[ "$MODE" == uninstall ]]; then
    for APP_PATH in "$TARGET" "$LEGACY"; do
        if [[ -d "$APP_PATH" ]]; then
            "$APP_PATH/Contents/MacOS/CalismaTakip" --unregister-login
            rm -rf -- "$APP_PATH"
        fi
    done
    echo "Uygulama kaldırıldı. Application Support/CalismaTakip ve Anahtar Zinciri verileri korundu."
    exit 0
fi
bash "$ROOT/scripts/build.sh"
mkdir -p "$PARENT"
STAGE="$(mktemp -d "$PARENT/.calisma-takip-install.XXXXXX")"
trap 'rm -rf -- "$STAGE"' EXIT
ditto "$ROOT/dist/Aizen.app" "$STAGE/new.app"
codesign --verify --strict "$STAGE/new.app"
[[ ! -d "$TARGET" ]] || mv "$TARGET" "$STAGE/previous.app"
if ! mv "$STAGE/new.app" "$TARGET"; then
    [[ ! -d "$STAGE/previous.app" ]] || mv "$STAGE/previous.app" "$TARGET"
    exit 1
fi
if [[ -d "$LEGACY" ]]; then
    # Oturum açılış kaydı eski paket yoluna bağlıdır; eski paket silinmeden önce kapatılır.
    "$LEGACY/Contents/MacOS/CalismaTakip" --unregister-login || true
    mv "$LEGACY" "$STAGE/legacy.app"
    echo "Eski ad (Calisma Takip.app) kaldırıldı. Oturum açınca başlatma açıksa Aizen'de Ayarlar ve yedek bölümünden yeniden aç."
fi
echo "Kuruldu: $TARGET"
echo "Yerel ayarlar, kurallar, ölçümler, merkez verileri, yedekler ve anahtarlar korundu."
open "$TARGET"
