#!/usr/bin/env bash
# Vygeneruje Resources/AppIcon.icns z 1024px masteru (sips + iconutil). Idempotentní.
set -euo pipefail
SRC="Resources/AppIcon/AppIcon-1024.png"
IS="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$IS"
gen() { sips -z "$1" "$1" "$SRC" --out "$IS/$2" >/dev/null; }
gen 16   icon_16x16.png
gen 32   icon_16x16@2x.png
gen 32   icon_32x32.png
gen 64   icon_32x32@2x.png
gen 128  icon_128x128.png
gen 256  icon_128x128@2x.png
gen 256  icon_256x256.png
gen 512  icon_256x256@2x.png
gen 512  icon_512x512.png
gen 1024 icon_512x512@2x.png
iconutil -c icns "$IS" -o Resources/AppIcon.icns
echo "Hotovo: Resources/AppIcon.icns"
