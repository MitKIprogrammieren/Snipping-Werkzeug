#!/bin/zsh
# Doppelklick: neueste Version holen, bauen und installieren.
# Schlägt der Bau fehl, landen die Fehler in „Snipping-Fehler.txt“ auf dem Schreibtisch.

REPO="$HOME/snipping-werkzeug"
LOG="$(mktemp -t snipping)"
FEHLER="$HOME/Desktop/Snipping-Fehler.txt"

printf '\e]0;Snipping Werkzeug aktualisieren\a'
echo "✂️  Snipping Werkzeug aktualisieren"
echo

if [ ! -d "$REPO/.git" ]; then
  echo "▶︎ Repo fehlt – wird nach $REPO geladen …"
  git clone https://github.com/MitKIprogrammieren/snipping-werkzeug.git "$REPO" || { read -k1 "?Taste drücken zum Schließen"; exit 1; }
fi

cd "$REPO" || exit 1
echo "▶︎ Hole neueste Version …"
git pull --ff-only || { echo "⚠️  git pull hat nicht geklappt"; read -k1 "?Taste drücken zum Schließen"; exit 1; }
echo

if ./scripts/mac-installieren.sh 2>&1 | tee "$LOG"; [ "${pipestatus[1]}" -eq 0 ]; then
  rm -f "$FEHLER"
  echo
  echo "✅ Fertig – Version $(cat VERSION) ist installiert und gestartet."
  sleep 2
  osascript -e 'tell application "Terminal" to close (every window whose name contains "Snipping Werkzeug aktualisieren")' >/dev/null 2>&1 &
  exit 0
else
  grep -B2 -A6 "error:" "$LOG" | head -200 > "$FEHLER"
  [ -s "$FEHLER" ] || tail -80 "$LOG" > "$FEHLER"
  echo
  echo "❌ Bau fehlgeschlagen. Die Fehler liegen in: $FEHLER"
  echo "   Schick mir die Datei einfach im Chat."
  open -R "$FEHLER"
  read -k1 "?Taste drücken zum Schließen"
  exit 1
fi
