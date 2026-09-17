#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
if [[ "$(uname -s)" != Darwin ]]; then
    echo "Bu paket macOS 13 ve üzeri için derlenir." >&2; exit 1
fi
if ! xcrun --find swift >/dev/null 2>&1; then
    echo "Önce Xcode Command Line Tools kurun: xcode-select --install" >&2; exit 1
fi
cd "$ROOT"
echo "Swift testleri çalışıyor..."
swift test
echo "Bu Mac'in mimarisi için release derleniyor..."
swift build -c release --product CalismaTakip
BIN="$(swift build -c release --show-bin-path)"
mkdir -p "$ROOT/dist"
STAGE="$(mktemp -d "$ROOT/dist/.app-build.XXXXXX")"
trap 'rm -rf -- "$STAGE"' EXIT
APP="$STAGE/Aizen.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/CalismaTakip" "$APP/Contents/MacOS/CalismaTakip"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
chmod 755 "$APP/Contents/MacOS/CalismaTakip"
plutil -lint "$APP/Contents/Info.plist"
codesign --force --sign - --identifier local.calisma-takip.macos "$APP"
codesign --verify --strict "$APP"
DEST="$ROOT/dist/Aizen.app"
if [[ -e "$DEST" || -L "$DEST" ]]; then
    [[ ! -L "$DEST" ]] || { echo "Çıktı uygulaması sembolik bağlantı olamaz." >&2; exit 1; }
    ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$DEST/Contents/Info.plist" 2>/dev/null || true)"
    [[ "$ID" == local.calisma-takip.macos ]] || { echo "Bilinmeyen çıktı uygulaması korunuyor." >&2; exit 1; }
    mv "$DEST" "$STAGE/previous.app"
fi
if ! mv "$APP" "$DEST"; then
    [[ ! -d "$STAGE/previous.app" ]] || mv "$STAGE/previous.app" "$DEST"
    exit 1
fi
echo "Uygulama hazır: $DEST"
