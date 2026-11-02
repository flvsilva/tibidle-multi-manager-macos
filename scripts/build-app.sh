#!/bin/zsh
# Builds dist/Tibidle Multi-Manager.app, plus a DMG and a ZIP for distribution.
# Reads only the source tree: it never touches your profiles or settings.
set -euo pipefail
cd "${0:a:h}/.."

APP_NAME="Tibidle Multi-Manager"
BUNDLE_ID="io.github.flvsilva.tibidle-multi-manager"
VERSION="${VERSION:-1.0.0}"
DIST="dist"
APP="$DIST/$APP_NAME.app"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/TibidleMultiManager"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/TibidleMultiManager"

swift scripts/make-icon.swift "$WORK/icon.png"
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$WORK/icon.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) "$WORK/icon.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>TibidleMultiManager</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.games</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>MIT License</string>
</dict>
</plist>
PLIST

cp LICENSE README.md THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/"
# The file provider may re-add Finder metadata between the two commands; retry until the signature takes.
for attempt in 1 2 3 4 5; do
  xattr -cr "$APP" 2>/dev/null || true
  xattr -d com.apple.FinderInfo "$APP" 2>/dev/null || true
  codesign --force --deep --sign - "$APP" && break
  [ "$attempt" = 5 ] && { echo "Falha ao assinar o app" >&2; exit 1; }
  sleep 1
done

# The packages come from a copy outside the synced folder, without extended attributes, signed and checked
# there: the file provider can put Finder metadata back on the app in dist/, which breaks the signature.
mkdir -p "$WORK/dmg"
PACKED="$WORK/dmg/$APP_NAME.app"
ditto --noextattr --noqtn "$APP" "$PACKED"
xattr -cr "$PACKED"
codesign --force --deep --sign - "$PACKED"
codesign --verify --deep --strict "$PACKED" || { echo "Assinatura inválida na cópia para os pacotes" >&2; exit 1; }

rm -f "$DIST/TibidleMultiManager-macOS.zip"
ditto -c -k --keepParent "$PACKED" "$DIST/TibidleMultiManager-macOS.zip"
# The DMG opens to the app next to an Applications link: drag one onto the other to install.
DMG="$DIST/TibidleMultiManager-macOS.dmg"
ln -s /Applications "$WORK/dmg/Applications"
rm -f "$DMG"
hdiutil create -quiet -volname "$APP_NAME" -srcfolder "$WORK/dmg" -fs HFS+ -format UDZO -ov "$DMG"

# Check what a download gets: the app inside the DMG.
MOUNT="$WORK/mount"
mkdir -p "$MOUNT"
hdiutil attach -quiet -nobrowse -readonly -mountpoint "$MOUNT" "$DMG"
VALID=0
codesign --verify --deep --strict "$MOUNT/$APP_NAME.app" && VALID=1
hdiutil detach -quiet "$MOUNT"
[ "$VALID" = 1 ] || { echo "Assinatura inválida no app dentro do DMG" >&2; exit 1; }

echo "App:    $APP"
echo "DMG:    $DMG"
echo "Pacote: $DIST/TibidleMultiManager-macOS.zip"
