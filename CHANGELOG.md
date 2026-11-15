# Changelog

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
