# Changelog

## 0.1.0 – 24.11.2026

- **Scrollaufnahme:** neuer Modus „Scrollen“ in der Aufnahmeleiste – Bereich wählen, langsam scrollen, „Fertig“; die App setzt alles zu einem langen Bild zusammen (bis 40.000 px)
- **Verlauf durchsuchen (⌘F):** eigenes Fenster mit allen Ausschnitten als Raster und Suchfeld; der Text jedes Ausschnitts wird im Hintergrund erkannt, auch nachträglich für ältere; Doppelklick öffnet, Rechtsklick für Kopieren, Finder, Löschen
- **Rahmen und Hintergrund:** Farbverläufe, Abstand, runde Ecken, Schatten und Fensterleiste mit drei Punkten – mit Live-Vorschau
- **Lupe:** Stelle anklicken, mit gedrückter Maus die vergrößerte Ansicht platzieren; 2×–4×, drei Größen, Farbe wählbar
- **Farbpipette und Messen:** neue Knöpfe in der Aufnahmeleiste (auch als Menüleisten-Eintrag und globales Kürzel) – Farbe als Hex-Code kopieren, Abstände in Pixeln messen (⇧ = waagerecht/senkrecht)
- **Videos:** Mausklicks werden hervorgehoben; optional Tastenkürzel einblenden (nur Kürzel und Sondertasten, nie normale Buchstaben); Aufnahmen als GIF speichern
- **An Meldewerk senden:** Papierflieger im Editor schickt den Ausschnitt per WhatsApp an dich; Adresse und Schlüssel in den Einstellungen, mit Testnachricht

## 0.0.12 – 24.11.2026

- Verlauf: Anzahl einstellbar (30, 100, 500 oder unbegrenzt, Standard jetzt 100 statt 30)
- Verlauf-Menü zeigt die neuesten 40 statt 15, mit Gesamtzahl; „Alle im Finder zeigen“ für den Rest

## 0.0.11 – 24.11.2026

- Neu: „Änderungen automatisch kopieren“ (wie bei Windows, standardmäßig an) – nach jedem Zeichnen, Schreiben, Schwärzen oder Zuschneiden liegt das bearbeitete Bild nach einer halben Sekunde in der Zwischenablage

## 0.0.10 – 24.11.2026

- Fenster behält seine Größe: es springt nicht mehr bei jedem Ausschnitt auf die Bildgröße, das Bild passt sich ans Fenster an
- Leiste wird nicht mehr abgeschnitten: „Neu“, Modus und Verzögerung links sowie Speichern, Kopieren, Teilen, Verlauf und „…“ rechts sind immer sichtbar; die Werkzeuge in der Mitte werden bei schmalem Fenster seitlich scrollbar (Mausrad oder Trackpad)
- Fenster lässt sich schmaler ziehen (ab 760 px statt 1240 px)

## 0.0.9 – 15.11.2026

Nummerierte Marker:
- Sechs Formen: Kreis gefüllt, Kreis umrandet, Quadrat, Stecknadel (Spitze zeigt auf die Stelle), Sprechblase, Etikett „Schritt 1“
- Zählweisen 1 2 3, A B C, a b c, I II III; Startwert frei wählbar
- Größen Klein, Mittel, Groß
- Mit gedrückter Maus ziehen: Pfeil vom Marker zur gemeinten Stelle

Schriften (für Text und Marker):
- System, Gerundet, Serif, Schreibmaschine, Handschrift, Filzstift, Kreide, Comic, Plakativ
- „Alle Schriften des Macs …“ – jede installierte Schriftfamilie, im Menü in ihrer eigenen Schrift
- Gewählte Einstellungen für Text und Marker bleiben für die nächsten Ausschnitte erhalten

## 0.0.8 – 15.11.2026

- Größeres App-Symbol: richtige macOS-Kachel, damit macOS es nicht verkleinert in eine graue Kachel setzt
- Logo in der Titelzeile größer (22 px Windows, 24 px Mac) und ohne Kachel

## 0.0.7 – 15.11.2026

- Neu: Automatisch schwärzen (Auge-durchgestrichen-Knopf) – die Texterkennung sucht IP- und MAC-Adressen, E-Mail-Adressen, Telefonnummern, IBANs, Passwörter (hinter „Passwort:“, „PIN:“ …), Schlüssel/Tokens und Links
  - Treffer werden im Bild markiert und rechts aufgelistet, einzeln an- und abwählbar (Tokens und Links standardmäßig aus)
  - Wahlweise Pixel, Weichzeichnen oder schwarzer Balken, mit ⌘Z rückgängig

## 0.0.6 – 15.11.2026

Neue Werkzeuge im Editor:
- Formen: Pfeil, Linie, Rechteck, Kreis/Ellipse – mit Farbe, Stärke und Füllung (keine, halbtransparent, voll); mit ⇧ gerade Linien in 45°-Schritten und gleichmäßige Formen
- Text: ins Bild klicken und tippen, drei Größen, Farben, optional weißer Hintergrund; Doppelklick bearbeitet einen Text nachträglich
- Nummerierte Marker ①②③ – jeder Klick setzt die nächste Zahl
- Verpixeln, Weichzeichnen oder schwarzer Balken – fest ins Bild eingerechnet
- Radierer entfernt auch Formen, Texte und Marker
- Jedes Werkzeug hat ein eigenes Optionen-Menü (Pfeil neben dem Knopf) und ein frei belegbares Kürzel

Außerdem:
- Textaktionen erkennen jetzt auch QR- und Strichcodes (Link öffnen, kopieren)
- Verlauf: die letzten 30 Ausschnitte mit Miniaturen, auch nach einem Neustart (abschaltbar in den Einstellungen)
- Datei öffnen (⌘O) und Bilder oder Videos per Drag & Drop ins Fenster ziehen
- Videos kürzen mit der eingebauten Kürzen-Ansicht von macOS, gespeichert als „… (gekürzt).mp4“
- Mac-Darstellung: Werkzeuge in einer eigenen Zeile unter der Titelleiste

## 0.0.5 – 15.11.2026

- Neu: Ausschnitte anheften – schwebende Fenster, die immer im Vordergrund bleiben
  - Knopf „Anheften“ (Reißnagel) im Editor, Menü Werkzeuge → „Ausschnitt anheften“
  - Globales Kürzel ⌃⇧A: Ausschnitt aufnehmen und sofort anheften
  - Deckkraft 20–100 %, Zoom mit Mausrad oder Lupen-Knöpfen, mit der Maus verschieben
  - Durchklicken: Klicks gehen ans Programm darunter; zurück mit ⌃⇧D oder über das Menüleisten-Symbol (gestrichelter Rand zeigt den Modus)
  - Doppelklick öffnet den Ausschnitt im Editor, mehrere angeheftete Ausschnitte gleichzeitig möglich

## 0.0.4 – 15.11.2026

- Neues App-Symbol im Stil des Windows-11-Snipping-Tools (Dock, Titelzeile, Hinweis unten rechts)

## 0.0.3 – 15.11.2026

Windows-Darstellung so nah wie möglich am Snipping Tool von Windows 11 (die Mac-Darstellung bleibt wählbar):

- Titelzeile mit Symbol und Namen links, Minimieren/Maximieren/Schließen rechts (Schließen wird beim Überfahren rot), keine Mac-Ampel
- Befehlsleiste wie im Original: blauer „+ Neu“-Knopf, Umschalter Ausschnitt/Aufnahme, Klappmenüs für Modus und „Keine Verzögerung“, Werkzeuge in der Mitte, Rückgängig/Speichern/Kopieren/Teilen rechts, „…“-Menü mit Einstellungen
- Windows-11-Farben: Mica-Grau, Akzentblau #005FB8 (dunkel #60CDFF), 4-px-Ecken, 32 px hohe Knöpfe mit Hover-Hintergrund
- Aufnahmeleiste: Umschalter Ausschnitt/Aufnahme links, dann die Modi, Verzögerung, Schließen
- Hinweis unten rechts mit Vorschaubild nach einem Ausschnitt per Tastenkürzel – Klick öffnet den Editor (über „Neu“ geht der Editor direkt auf)
- Neu: Lineal – verschieben mit der Maus, drehen mit dem Mausrad (rastet bei 0°/45°/90° ein), Stift und Textmarker ziehen an der Kante gerade Linien
- Farb- und Stärkeauswahl als Klappmenü unter Stift und Textmarker
- Leerer Zustand mit dem Windows-Hinweis „Drücken Sie ⌃⇧S, um einen Ausschnitt zu starten.“

## 0.0.2 – 15.11.2026

- Alle Tastenkürzel sind in den Einstellungen änderbar: ins Feld klicken, neue Kombination drücken
- Pro Kürzel „Kein Kürzel“ und „Zurück auf Standard“, dazu „Alle zurücksetzen“
- Warnung, wenn ein Kürzel schon vergeben ist – in der App oder von macOS bzw. einer anderen App
- Neue globale Kürzel: Bildschirmaufnahme (Standard ⌃⇧R, wie Win+Umschalt+R) und Vollbild sofort aufnehmen (ohne Standard)
- Neues Menü „Werkzeuge“ mit Kugelschreiber, Textmarker, Radierer, Zuschneiden und Text erkennen – auch diese mit eigenen Kürzeln belegbar
- Menüleisten-Symbol und Hinweistexte zeigen immer die aktuellen Kürzel
- Lässt sich jetzt auch nur mit den Command Line Tools bauen (ohne volles Xcode)

## 0.0.1 – 15.11.2026

Erste Version.

- Aufnahmeleiste mit den Modi Rechteck, Freihand, Fenster und Vollbild
- Foto (Ausschnitt) und Video (Bildschirmaufnahme als MP4)
- Verzögerung: aus, 3, 5 oder 10 Sekunden mit Countdown
- Globales Tastenkürzel ⌃⇧S (Gegenstück zu Win+Umschalt+S), Symbol in der Menüleiste
- Editor: Kugelschreiber und Textmarker (Farben und Stärken), Radierer, Zuschneiden, Rückgängig/Wiederholen
- Texterkennung (Deutsch und Englisch) mit „Alles kopieren“
- Kopieren (⇧⌘C), Speichern unter (PNG/JPEG, ⌘S), Teilen
- Automatisch in die Zwischenablage kopieren und automatisch speichern (Ordner wählbar)
- Videos: Mauszeiger, Systemton und Mikrofon zuschaltbar, Vorschau im Fenster
- Darstellung umschaltbar: Windows (Snipping-Tool-Look, Leiste oben) oder Mac (⇧⌘5-Look, Leiste unten)
- Titelleiste mit Logo und Titel auf Höhe der Fensterknöpfe
