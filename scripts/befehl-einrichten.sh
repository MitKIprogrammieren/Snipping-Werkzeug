#!/usr/bin/env bash
# Legt „Snipping Werkzeug aktualisieren.command“ mit eigenem Symbol auf den Schreibtisch.
set -euo pipefail
cd "$(dirname "$0")/.."
BEFEHL="$HOME/Desktop/Snipping Werkzeug aktualisieren.command"
cp "scripts/Snipping Werkzeug aktualisieren.command" "$BEFEHL"
chmod +x "$BEFEHL"
# Ausführen nach Doppelklick erlauben (Download-Markierung entfernen)
xattr -d com.apple.quarantine "$BEFEHL" 2>/dev/null || true
osascript -l JavaScript -e "ObjC.import('AppKit'); \$.NSWorkspace.sharedWorkspace.setIconForFileOptions(\$.NSImage.alloc.initWithContentsOfFile('$PWD/assets/BefehlIcon.png'), '$BEFEHL', 0)" >/dev/null
echo "✓ „Snipping Werkzeug aktualisieren“ liegt mit Logo auf dem Schreibtisch."
