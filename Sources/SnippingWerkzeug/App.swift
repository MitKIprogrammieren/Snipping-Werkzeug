import SwiftUI
import AppKit
import Carbon.HIToolbox

@main
struct SnippingWerkzeugApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        Einstellungen.registrieren()
    }

    var body: some Scene {
        Settings {
            EinstellungenAnsicht()
        }
        .commands {
            BefehlsMenues()
        }
    }
}

/// Menübefehle – alle Kürzel kommen aus den Einstellungen.
struct BefehlsMenues: Commands {
    // Sorgt dafür, dass die Menüs sich neu aufbauen, wenn ein Kürzel geändert wird
    @AppStorage(KuerzelSpeicher.schluessel) private var kuerzelRoh = ""

    private var k: KuerzelSpeicher {
        _ = kuerzelRoh
        return KuerzelSpeicher.shared
    }
    private var editor: EditorModell? { Hauptfenster.shared.zustand.editor }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Neuer Ausschnitt") { AufnahmeSteuerung.shared.neu() }
                .keyboardShortcut(k.shortcut(.neu))
            Button("Öffnen …") { Hauptfenster.shared.zustand.oeffnen() }
                .keyboardShortcut(k.shortcut(.oeffnen))
            Button("Verlauf durchsuchen …") { VerlaufFenster.shared.zeigen() }
                .keyboardShortcut(k.shortcut(.verlaufSuchen))
        }
        CommandGroup(replacing: .saveItem) {
            Button("Speichern unter …") { Hauptfenster.shared.zustand.speichern() }
                .keyboardShortcut(k.shortcut(.speichern))
        }
        CommandGroup(replacing: .undoRedo) {
            Button("Rückgängig") { editor?.rueckgaengig() }
                .keyboardShortcut(k.shortcut(.rueckgaengig))
            Button("Wiederholen") { editor?.wiederholen() }
                .keyboardShortcut(k.shortcut(.wiederholen))
        }
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Ausschnitt kopieren") { Hauptfenster.shared.zustand.kopieren() }
                .keyboardShortcut(k.shortcut(.kopieren))
        }
        CommandMenu("Werkzeuge") {
            Button("Kugelschreiber") { editor?.waehle(.stift) }
                .keyboardShortcut(k.shortcut(.stift))
            Button("Textmarker") { editor?.waehle(.marker) }
                .keyboardShortcut(k.shortcut(.marker))
            Button("Formen") { editor?.waehle(.form) }
                .keyboardShortcut(k.shortcut(.form))
            Button("Text") { editor?.waehle(.text) }
                .keyboardShortcut(k.shortcut(.text))
            Button("Nummerierte Marker") { editor?.waehle(.nummer) }
                .keyboardShortcut(k.shortcut(.nummer))
            Button("Rahmen und Hintergrund") { editor?.oeffneRahmen() }
                .keyboardShortcut(k.shortcut(.rahmen))
            Button("Lupe") { editor?.waehle(.lupe) }
                .keyboardShortcut(k.shortcut(.lupe))
            Button("Verpixeln") { editor?.waehle(.verpixeln) }
                .keyboardShortcut(k.shortcut(.verpixeln))
            Button("Automatisch schwärzen") {
                if let m = editor { Task { await m.sucheSensibleDaten() } }
            }
            .keyboardShortcut(k.shortcut(.schwaerzen))
            Button("Radierer") { editor?.waehle(.radierer) }
                .keyboardShortcut(k.shortcut(.radierer))
            Button("Ausschnitt anheften") { Hauptfenster.shared.zustand.anheften() }
                .keyboardShortcut(k.shortcut(.anheften))
            Button("An Meldewerk senden (WhatsApp)") { Hauptfenster.shared.zustand.anMeldewerk() }
                .keyboardShortcut(k.shortcut(.meldewerk))
            Divider()
            Button("Lineal") { editor?.schalteLineal() }
                .keyboardShortcut(k.shortcut(.lineal))
            Button("Zuschneiden") { editor?.waehle(.zuschneiden) }
                .keyboardShortcut(k.shortcut(.zuschneiden))
            Divider()
            Button("Text erkennen") {
                if let m = editor { Task { await m.erkenneText() } }
            }
            .keyboardShortcut(k.shortcut(.texterkennung))
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        Hauptfenster.shared.zeigen()

        // Globale Kürzel (Standard ⌃⇧S – Gegenstück zu Win+Umschalt+S)
        HotKeyVerwaltung.shared.start()

        richteStatusMenueEin()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Hauptfenster.shared.zeigen()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func richteStatusMenueEin() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "scissors", accessibilityDescription: "Snipping Werkzeug")
        let menue = NSMenu()
        menue.delegate = self
        item.menu = menue
        statusItem = item
    }

    /// Menü bei jedem Öffnen neu aufbauen, damit die aktuellen Kürzel dranstehen.
    func menuNeedsUpdate(_ menue: NSMenu) {
        menue.removeAllItems()
        let k = KuerzelSpeicher.shared
        func eintrag(_ titel: String, _ aktion: Selector, _ a: Aktion? = nil) {
            let text = a.flatMap { k.text($0) }.map { "\(titel)  (\($0))" } ?? titel
            let e = NSMenuItem(title: text, action: aktion, keyEquivalent: "")
            e.target = self
            menue.addItem(e)
        }
        eintrag("Neuer Ausschnitt", #selector(neuerAusschnitt), .ausschnittGlobal)
        if AufnahmeSteuerung.shared.nimmtAuf {
            eintrag("Bildschirmaufnahme beenden", #selector(aufnahmeBeenden), .videoGlobal)
        } else {
            eintrag("Bildschirmaufnahme", #selector(videoStarten), .videoGlobal)
        }
        eintrag("Vollbild aufnehmen", #selector(vollbild), .vollbildGlobal)
        eintrag("Aufnehmen und anheften", #selector(aufnehmenUndAnheften), .anheftenGlobal)
        eintrag("Farbpipette", #selector(farbpipette), .farbeGlobal)
        eintrag("Messen", #selector(messen), .messenGlobal)
        let anh = AnheftVerwaltung.shared
        if anh.anzahl > 0 {
            menue.addItem(.separator())
            eintrag(anh.irgendwoDurchklicken ? "Angeheftete: Durchklicken beenden" : "Angeheftete: Durchklicken",
                    #selector(durchklicken), .durchklickenGlobal)
            eintrag("Alle angehefteten Ausschnitte schließen", #selector(angehefteteSchliessen))
        }
        menue.addItem(.separator())
        eintrag("Fenster zeigen", #selector(fensterZeigen))
        eintrag("Einstellungen …", #selector(einstellungenZeigen))
        menue.addItem(.separator())
        eintrag("Snipping Werkzeug beenden", #selector(beenden))
    }

    @objc private func neuerAusschnitt() {
        AufnahmeSteuerung.shared.ausApp = false
        AufnahmeSteuerung.shared.zeigeLeiste()
    }
    @objc private func videoStarten() {
        AufnahmeSteuerung.shared.ausApp = false
        AufnahmeSteuerung.shared.zeigeLeiste(art: .video)
    }
    @objc private func vollbild() {
        AufnahmeSteuerung.shared.ausApp = false
        AufnahmeSteuerung.shared.starte(modus: .vollbild, art: .foto)
    }
    @objc private func aufnehmenUndAnheften() {
        AufnahmeSteuerung.shared.ausApp = false
        AufnahmeSteuerung.shared.zeigeLeiste(art: .foto, anheften: true)
    }
    @objc private func farbpipette() { HilfsSteuerung.shared.starte(.farbe) }
    @objc private func messen() { HilfsSteuerung.shared.starte(.messen) }
    @objc private func durchklicken() { AnheftVerwaltung.shared.schalteDurchklicken() }
    @objc private func angehefteteSchliessen() { AnheftVerwaltung.shared.alleSchliessen() }
    @objc private func aufnahmeBeenden() { AufnahmeSteuerung.shared.stoppeVideo(verwerfen: false) }
    @objc private func fensterZeigen() { Hauptfenster.shared.zeigen() }
    @objc private func einstellungenZeigen() { EinstellungenFenster.shared.zeigen() }
    @objc private func beenden() { NSApp.terminate(nil) }
}
