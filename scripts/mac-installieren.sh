#!/usr/bin/env bash
# Baut das Snipping Werkzeug auf dem Mac, packt es als .app und installiert es in /Applications.
# Aufruf im Repo-Ordner:  ./scripts/mac-installieren.sh
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="$(cat VERSION)"
APP_NAME="Snipping Werkzeug"
BUNDLE_ID="de.mitkiprogrammieren.snippingwerkzeug"
APP="build/${APP_NAME}.app"

echo "▶︎ Baue Snipping Werkzeug ${VERSION} …"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/SnippingWerkzeug"

echo "▶︎ Packe die App …"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SnippingWerkzeug"

# App-Symbol aus assets/AppIcon.png
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s assets/AppIcon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) assets/AppIcon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
cp assets/Logo.png "$APP/Contents/Resources/Logo.png"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
  <key>CFBundleExecutable</key><string>SnippingWerkzeug</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleDevelopmentRegion</key><string>de</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSLocalNetworkUsageDescription</key><string>Das Snipping Werkzeug schickt Ausschnitte auf Wunsch an dein Meldewerk im Heimnetz.</string>
  <key>NSAppTransportSecurity</key><dict><key>NSAllowsArbitraryLoads</key><true/><key>NSAllowsLocalNetworking</key><true/></dict>
  <key>NSMicrophoneUsageDescription</key><string>Das Snipping Werkzeug nimmt bei Bildschirmaufnahmen auf Wunsch das Mikrofon mit auf.</string>
</dict>
</plist>
PLIST

# Signieren: mit SIGN_ID="Name des Zertifikats" bleibt die Bildschirmaufnahme-Freigabe über Updates erhalten,
# ohne (ad-hoc) muss sie nach jedem Bau neu erteilt werden.
SIGN_ID="${SIGN_ID:--}"
codesign --force --deep --sign "$SIGN_ID" "$APP"

echo "▶︎ Installiere nach /Applications …"
pkill -x SnippingWerkzeug 2>/dev/null || true
rm -rf "/Applications/${APP_NAME}.app"
ditto "$APP" "/Applications/${APP_NAME}.app"

if [ "$SIGN_ID" = "-" ]; then
  # Alte Freigabe passt nicht mehr zur neuen Signatur → zurücksetzen, die App fragt neu
  tccutil reset ScreenCapture "$BUNDLE_ID" >/dev/null 2>&1 || true
fi

open "/Applications/${APP_NAME}.app"
echo "✓ Snipping Werkzeug ${VERSION} ist installiert."

# Aktualisieren-Befehl mit App-Logo auf den Schreibtisch legen
./scripts/befehl-einrichten.sh || true
