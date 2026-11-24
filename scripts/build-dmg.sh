#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/Gooose.app"
DMG_PATH="$DIST_DIR/Gooose-macOS-arm64.dmg"
STAGE_DIR="$(mktemp -d /tmp/super-goose-dmg.XXXXXX)"

cleanup() {
  rm -rf "$STAGE_DIR"
}
trap cleanup EXIT

if [[ ! -d "$APP_BUNDLE" ]]; then
  "$ROOT_DIR/scripts/build-app.sh"
fi

cp -R "$APP_BUNDLE" "$STAGE_DIR/"
ln -s /Applications "$STAGE_DIR/Applications"

rm -f "$DMG_PATH" "$DIST_DIR/.DS_Store"
hdiutil create -volname "Gooose" -srcfolder "$STAGE_DIR" -ov -format UDZO "$DMG_PATH"

cd "$DIST_DIR"
shasum -a 256 "Gooose-macOS-arm64.dmg" "Gooose.app/Contents/MacOS/Goose" > "$DIST_DIR/SHA256.txt"
echo "Created DMG: $DMG_PATH"
cat "$DIST_DIR/SHA256.txt"
