#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="PhotoPic"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
DMG_PATH="$DIST_DIR/$APP_NAME-Installer.dmg"
ZIP_PATH="$DIST_DIR/$APP_NAME-macOS-arm64.zip"
DMG_STAGING="$DIST_DIR/dmg_staging"

cd "$ROOT_DIR"

BASE_VER="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION" 2>/dev/null || echo '2.6')"
BUILD_NUM="$(git rev-list --count HEAD 2>/dev/null || echo '1')"
SHORT_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo 'local')"
FULL_VER="${BASE_VER}.${BUILD_NUM}"

echo "==> 0. Versioning PhotoPic v$FULL_VER (build $BUILD_NUM, commit $SHORT_SHA)..."
echo "==> 1. Generating Pictogrammers PhotoPic logo & native icons (.svg, .icns, .ico)..."
swift macos/Scripts/generate_icon.swift macos/Resources/AppIcon.icns

echo "==> 2. Generating & linting PhotoPic.xcodeproj..."
python3 macos/Scripts/generate_xcodeproj.py
plutil -lint macos/Resources/Info.plist
plutil -lint macos/Resources/PhotoPic.entitlements
plutil -lint PhotoPic.xcodeproj/project.pbxproj

echo "==> 3. Building arm64 Release binary..."
swift build -c release --product PhotoPic
BIN_PATH="$(swift build -c release --show-bin-path)/PhotoPic"

if [[ ! -x "$BIN_PATH" ]]; then
  echo "ERROR: Release binary not found at $BIN_PATH" >&2
  exit 1
fi

echo "==> 4. Assembling standalone $APP_BUNDLE..."
rm -rf "$APP_BUNDLE" "$DMG_STAGING" "$DMG_PATH" "$ZIP_PATH"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp macos/Resources/Info.plist "$APP_BUNDLE/Contents/Info.plist"
cp macos/Resources/AppIcon.icns "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
printf "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

PLIST="$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $FULL_VER" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUM" "$PLIST"
/usr/libexec/PlistBuddy -c "Delete :PhotoPicCommitSHA" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :PhotoPicCommitSHA string $SHORT_SHA" "$PLIST"
/usr/libexec/PlistBuddy -c "Delete :PhotoPicRepository" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :PhotoPicRepository string stevensb2003-afk/PhotoPic" "$PLIST"

echo "==> 5. Signing $APP_BUNDLE with entitlements..."
codesign --force --deep --sign - --entitlements macos/Resources/PhotoPic.entitlements "$APP_BUNDLE"
codesign --verify --deep --strict -vvv "$APP_BUNDLE"

echo "==> 6. Running runtime launch smoke check..."
"$APP_BUNDLE/Contents/MacOS/$APP_NAME" >/dev/null 2>&1 &
APP_PID=$!
sleep 1.5
if kill -0 "$APP_PID" 2>/dev/null; then
  echo "Launch smoke check PASSED (PID $APP_PID running cleanly under macOS)."
  kill -TERM "$APP_PID" 2>/dev/null || true
  wait "$APP_PID" 2>/dev/null || true
else
  wait "$APP_PID" || STATUS=$?
  echo "ERROR: App terminated prematurely during launch smoke check (exit ${STATUS:-unknown})." >&2
  exit 1
fi

echo "==> 7. Packaging $DMG_PATH and OTA $ZIP_PATH..."
mkdir -p "$DMG_STAGING"
cp -R "$APP_BUNDLE" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"
hdiutil create -volname "PhotoPic" -srcfolder "$DMG_STAGING" -ov -format UDZO "$DMG_PATH"
rm -rf "$DMG_STAGING"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"
hdiutil imageinfo "$DMG_PATH" | head -n 15

echo "==> Packaging complete:"
ls -lh "$APP_BUNDLE/Contents/MacOS/$APP_NAME" "$DMG_PATH" "$ZIP_PATH"
