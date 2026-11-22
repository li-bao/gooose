#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
DMG_PATH="$DIST_DIR/Super-Goose-Desktop-Apple-Silicon.dmg"
MNT_DIR="$(mktemp -d /tmp/super-goose-mount.XXXXXX)"

cleanup() {
  if mount | grep -q "$MNT_DIR"; then
    hdiutil detach "$MNT_DIR" -force >/dev/null 2>&1 || true
  fi
  rm -rf "$MNT_DIR"
}
trap cleanup EXIT

if [[ ! -f "$DMG_PATH" ]]; then
  echo "error: DMG not found at $DMG_PATH" >&2
  exit 1
fi

hdiutil attach -nobrowse -mountpoint "$MNT_DIR" "$DMG_PATH"

MOUNTED_APP="$MNT_DIR/Super Goose Desktop.app"
MOUNTED_BIN="$MOUNTED_APP/Contents/MacOS/Goose"

file "$MOUNTED_BIN"
lipo -archs "$MOUNTED_BIN"
plutil -lint "$MOUNTED_APP/Contents/Info.plist"
codesign --verify --deep --strict --verbose=2 "$MOUNTED_APP"

"$MOUNTED_BIN" --diagnose-permissions
"$MOUNTED_BIN" --brain-dryrun >/dev/null
echo "Mounted --brain-dryrun: OK"

hdiutil detach "$MNT_DIR"

if [[ -f "$DIST_DIR/SHA256.txt" ]]; then
  (cd "$DIST_DIR" && shasum -a 256 -c SHA256.txt)
fi

echo "Release verification complete."
