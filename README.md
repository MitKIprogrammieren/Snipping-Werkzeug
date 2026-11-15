# Snipping Werkzeug

Das Snipping Tool von Windows 11 als native Mac-App (Swift/SwiftUI, ScreenCaptureKit, Vision).

## Funktionen

- **Ausschnitte:** Rechteck, Freihand, Fenster, Vollbild – mit optionaler Verzögerung
- **Bildschirmaufnahme:** Bereich, Fenster oder Vollbild als MP4, auf Wunsch mit Systemton und Mikrofon
- **Bearbeiten:** Kugelschreiber, Textmarker, Formen und Pfeile, Text, nummerierte Marker, Verpixeln, Radierer, Lineal, Zuschneiden, Rückgängig
- **Anheften:** Ausschnitte als schwebende Fenster immer im Vordergrund
- **Verlauf:** die letzten 30 Ausschnitte
- **Texterkennung:** Text aus dem Ausschnitt erkennen und kopieren
- **Ausgabe:** automatisch in die Zwischenablage und in einen Ordner, Speichern unter, Teilen
- **Zwei Darstellungen:** Windows oder Mac, umschaltbar in den Einstellungen

## Tastenkürzel

Alle Kürzel lassen sich in den Einstellungen ändern oder abschalten. Standard:

| Kürzel | Aktion |
|---|---|
| ⌃⇧S | Aufnahmeleiste öffnen (überall) bzw. laufende Aufnahme beenden |
| ⌃⇧R | Bildschirmaufnahme (überall) |
| – | Vollbild sofort aufnehmen (überall) |
| ⌃⇧A | Ausschnitt aufnehmen und anheften (überall) |
| ⌃⇧D | Angeheftete Ausschnitte: Durchklicken ein/aus (überall) |
| ⌘N | Neuer Ausschnitt |
| ⌘O | Datei öffnen |
| ⇧⌘C | Ausschnitt kopieren |
| ⌘S | Speichern unter |
| ⌘Z / ⇧⌘Z | Rückgängig / Wiederholen |
| – | Kugelschreiber, Textmarker, Formen, Text, Marker, Verpixeln, Radierer, Lineal, Zuschneiden, Textaktionen |

Fest sind nur esc (abbrechen) und ↩ (bestätigen).

## Bauen und installieren

Voraussetzung: macOS 15 oder neuer und die Command Line Tools (`xcode-select --install`) – volles Xcode ist nicht nötig.

```bash
./scripts/mac-installieren.sh
```

Das Skript baut die App, legt sie nach `/Applications/Snipping Werkzeug.app` und startet sie.

Beim ersten Ausschnitt fragt macOS nach der Berechtigung **Bildschirm- und Systemaudioaufnahme**.
Nach dem Einschalten die App einmal neu starten. Weil die App ad-hoc signiert wird, muss die Freigabe
nach jedem neuen Bau erneut erteilt werden – außer man signiert mit einem eigenen Zertifikat:

```bash
SIGN_ID="Name des Zertifikats" ./scripts/mac-installieren.sh
```
