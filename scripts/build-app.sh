#!/bin/sh
# Builds "BLAKE2b Miner.app" as a universal (Apple Silicon + Intel) app for
# macOS 13 or later, with the b2bminer command-line tool inside, and packages
# it as a .zip and a .dmg in dist/.
#
# Needs only the Xcode Command Line Tools (xcode-select --install).
#
# Signing: ad-hoc by default (users confirm the first launch in System Settings).
# For a Developer ID signed and notarized build set:
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
#   NOTARY_PROFILE=<profile saved with `xcrun notarytool store-credentials`>
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
VERSION=$(sed -n 's/.*static let version = "\(.*\)".*/\1/p' Sources/MinerCore/Miner.swift)
APP_NAME="BLAKE2b Miner"
BUNDLE_ID="io.github.taimouralneimat.blake2bminer"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
SIGN_IDENTITY=${SIGN_IDENTITY:--}

echo "== Building $APP_NAME $VERSION (arm64 + x86_64)"
for arch in arm64 x86_64; do
    swift build -c release --triple "$arch-apple-macosx13.0" 2>&1 | grep -E "error|warning: |Compiling|Build complete" || true
    [ -x ".build/$arch-apple-macosx/release/BLAKE2bMiner" ] || { echo "build failed for $arch"; exit 1; }
done

GATEWAY="$ROOT/build/datum/datum_gateway"
if [ ! -x "$GATEWAY" ]; then
    echo "== Building the DATUM Gateway (first time only)"
    scripts/build-datum-gateway.sh
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
for product in BLAKE2bMiner b2bminer; do
    lipo -create -output "$APP/Contents/MacOS/$product" \
        ".build/arm64-apple-macosx/release/$product" ".build/x86_64-apple-macosx/release/$product"
done
cp "$GATEWAY" "$APP/Contents/MacOS/datum_gateway"
cp THIRD_PARTY_NOTICES.md LICENSE "$APP/Contents/Resources/"

echo "== Icon"
ICONSET=$(mktemp -d)/AppIcon.iconset
swift scripts/make-icon.swift "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>BLAKE2bMiner</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>MIT License</string>
</dict>
</plist>
EOF

echo "== Signing ($SIGN_IDENTITY)"
if [ "$SIGN_IDENTITY" = "-" ]; then
    for exe in b2bminer datum_gateway; do codesign --force --sign - "$APP/Contents/MacOS/$exe"; done
    codesign --force --sign - "$APP"
else
    for exe in b2bminer datum_gateway; do
        codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP/Contents/MacOS/$exe"
    done
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
fi
codesign --verify --strict "$APP"

echo "== Packaging"
ZIP="$DIST/BLAKE2bMiner-$VERSION-macOS.zip"
DMG="$DIST/BLAKE2bMiner-$VERSION-macOS.dmg"
rm -f "$ZIP" "$DMG"
ditto -c -k --keepParent "$APP" "$ZIP"
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"

if [ -n "${NOTARY_PROFILE:-}" ] && [ "$SIGN_IDENTITY" != "-" ]; then
    echo "== Notarizing"
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    xcrun stapler staple "$APP"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
fi

(cd "$DIST" && shasum -a 256 "$(basename "$ZIP")" "$(basename "$DMG")" > SHA256SUMS.txt)
echo "== Done"
lipo -archs "$APP/Contents/MacOS/BLAKE2bMiner"
ls -lh "$DIST"
