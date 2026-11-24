#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG_DIR="$ROOT_DIR/Goose"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/Gooose.app"
VERSION="${VERSION:-2.2.0}"
BUILD_NUMBER="${BUILD_NUMBER:-5}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"

echo "==> Building Release ARM64 binary..."
cd "$PKG_DIR"
swift package resolve
swift build -c release --arch arm64

BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"
REL_BIN="$BIN_DIR/Goose"
REL_BUNDLE="$BIN_DIR/Goose_Goose.bundle"

if [[ ! -x "$REL_BIN" ]]; then
  echo "error: Release binary not found at $REL_BIN" >&2
  exit 1
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources/Sprites"

cp "$REL_BIN" "$APP_BUNDLE/Contents/MacOS/Goose"
chmod +x "$APP_BUNDLE/Contents/MacOS/Goose"
ln -sf "Goose" "$APP_BUNDLE/Contents/MacOS/Gooose"

if [[ -d "$REL_BUNDLE" ]]; then
  cp -R "$REL_BUNDLE" "$APP_BUNDLE/Contents/Resources/Goose_Goose.bundle"
fi

if [[ -d "$PKG_DIR/Sources/Goose/Resources/Sprites/Goose" ]]; then
  cp -R "$PKG_DIR/Sources/Goose/Resources/Sprites/Goose" "$APP_BUNDLE/Contents/Resources/Sprites/Goose"
fi

if [[ -f "$PKG_DIR/Sources/Goose/Resources/AppIcon.icns" ]]; then
  cp "$PKG_DIR/Sources/Goose/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>Goose</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.pkrutaa.supergoosedesktop</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Gooose</string>
    <key>CFBundleDisplayName</key>
    <string>Gooose</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key>
    <string>26.1</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.entertainment</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 PKrutaa, li-bao. MIT License.</string>
    <key>NSAccessibilityUsageDescription</key>
    <string>Super Goose Desktop uses Accessibility permission to read active window bounds/titles for window pranks and peeks. 超級桌面鵝需要輔助使用權限以讀取前景視窗位置與標題，用於視窗惡作劇與探頭互動。</string>
    <key>NSScreenCaptureUsageDescription</key>
    <string>Super Goose Desktop uses Screen Recording permission to capture local screen content for on-device Vision OCR and contextual awareness. 超級桌面鵝需要螢幕錄影權限以在本機進行 Vision OCR 與畫面情境感知，影像絕不上傳。</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Super Goose Desktop optionally controls Spotify via local AppleScript during chill mode.</string>
    <key>NSUserNotificationAlertStyle</key>
    <string>banner</string>
</dict>
</plist>
PLIST

plutil -lint "$APP_BUNDLE/Contents/Info.plist"

echo "==> Signing nested bundle and application with identity: $SIGNING_IDENTITY"
if [[ -d "$APP_BUNDLE/Contents/Resources/Goose_Goose.bundle" ]]; then
  if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    codesign --force --sign - --timestamp=none "$APP_BUNDLE/Contents/Resources/Goose_Goose.bundle"
  else
    codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp "$APP_BUNDLE/Contents/Resources/Goose_Goose.bundle"
  fi
fi

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  echo "Notice: Using ad-hoc signing (-). TCC permissions bind to CDHash across rebuilds."
  codesign --force --sign - --timestamp=none --deep "$APP_BUNDLE"
else
  codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp --deep "$APP_BUNDLE"
fi

codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
echo "Built and signed: $APP_BUNDLE"
