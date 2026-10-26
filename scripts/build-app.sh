#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${1:-release}"
APP="$ROOT/build/TempBar.app"

cd "$ROOT"

echo "Building TempBar ($CONFIGURATION)…"
swift build -c "$CONFIGURATION"
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

install -m 755 "$BIN_DIR/TempBar" "$APP/Contents/MacOS/TempBar"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

plutil -lint "$APP/Contents/Info.plist" >/dev/null

# Ad-hoc signature. Enough for a locally built app.
codesign --force --sign - --identifier "com.inar.tempbar" --timestamp=none "$APP" >/dev/null

echo "Built $APP"
