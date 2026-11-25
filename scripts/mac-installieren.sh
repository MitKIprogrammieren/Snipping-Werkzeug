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

# Signieren mit einem eigenen, gleichbleibenden Zertifikat: Dann erkennt macOS die App nach jedem
# Update wieder und die Freigabe „Bildschirmaufnahme“ bleibt erhalten. Das Zertifikat wird beim
# ersten Mal einmalig im Schlüsselbund angelegt (nur für diesen Mac, nur zum Signieren).
ZERT="Snipping Werkzeug Signatur"
if [ -z "${SIGN_ID:-}" ]; then
  if ! security find-certificate -c "$ZERT" >/dev/null 2>&1; then
    echo "▶︎ Lege einmalig ein Signatur-Zertifikat im Schlüsselbund an …"
    TMPZ="$(mktemp -d)"
    /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
      -subj "/CN=$ZERT" \
      -addext "keyUsage=critical,digitalSignature" \
      -addext "extendedKeyUsage=critical,codeSigning" \
      -keyout "$TMPZ/key.pem" -out "$TMPZ/cert.pem" >/dev/null 2>&1 \
    && /usr/bin/openssl pkcs12 -export -inkey "$TMPZ/key.pem" -in "$TMPZ/cert.pem" \
      -name "$ZERT" -out "$TMPZ/id.p12" -passout pass:snipping >/dev/null 2>&1 \
    && security import "$TMPZ/id.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
      -P snipping -T /usr/bin/codesign >/dev/null 2>&1 \
    || echo "  (Zertifikat konnte nicht angelegt werden – signiere ad-hoc)"
    rm -rf "$TMPZ"
  fi
  if security find-certificate -c "$ZERT" >/dev/null 2>&1; then SIGN_ID="$ZERT"; else SIGN_ID="-"; fi
fi
if ! codesign --force --deep --sign "$SIGN_ID" "$APP" 2>/dev/null; then
  echo "  (Signieren mit „$SIGN_ID“ ging nicht – signiere ad-hoc)"
  SIGN_ID="-"
  codesign --force --deep --sign - "$APP"
fi
echo "▶︎ Signiert mit: $SIGN_ID"

# Wechsel der Signatur (z. B. ad-hoc → Zertifikat) einmalig erkennen und die alte Freigabe aufräumen
SIG_MERKER="$HOME/Library/Application Support/Snipping Werkzeug/signatur"
mkdir -p "$(dirname "$SIG_MERKER")"
LETZTE_SIG="$(cat "$SIG_MERKER" 2>/dev/null || true)"

echo "▶︎ Installiere nach /Applications …"
pkill -x SnippingWerkzeug 2>/dev/null || true
rm -rf "/Applications/${APP_NAME}.app"
ditto "$APP" "/Applications/${APP_NAME}.app"

if [ "$SIGN_ID" = "-" ] || [ "$LETZTE_SIG" != "$SIGN_ID" ]; then
  # Alte Freigabe passt nicht mehr zur Signatur → zurücksetzen, die App fragt beim nächsten Ausschnitt neu
  tccutil reset ScreenCapture "$BUNDLE_ID" >/dev/null 2>&1 || true
  echo "  Hinweis: Beim nächsten Ausschnitt einmal „Bildschirmaufnahme“ erlauben und die App neu starten."
fi
echo "$SIGN_ID" > "$SIG_MERKER"

open "/Applications/${APP_NAME}.app"
echo "✓ Snipping Werkzeug ${VERSION} ist installiert."

# Aktualisieren-Befehl mit App-Logo auf den Schreibtisch legen
./scripts/befehl-einrichten.sh || true
