#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$HOME/Applications/TempBar.app"

"$ROOT/scripts/build-app.sh" "${1:-release}"

mkdir -p "$HOME/Applications"

# Quit a running copy before replacing the bundle.
if pgrep -x TempBar >/dev/null 2>&1; then
    osascript -e 'tell application "TempBar" to quit' >/dev/null 2>&1 || true
    sleep 0.4
    pkill -x TempBar >/dev/null 2>&1 || true
fi

rm -rf "$DEST"
cp -R "$ROOT/build/TempBar.app" "$DEST"

echo "Installed $DEST"
open "$DEST"
echo "TempBar is running in the menu bar."
