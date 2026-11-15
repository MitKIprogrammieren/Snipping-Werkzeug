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
            CommandGroup(replacing: .newItem) {
                Button("Neuer Ausschnitt") { AufnahmeSteuerung.shared.neu() }
                    .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(replacing: .saveItem) {
                Button("Speichern unter …") { Hauptfenster.shared.zustand.speichern() }
                    .keyboardShortcut("s", modifiers: .command)
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Rückgängig") { Hauptfenster.shared.zustand.editor?.rueckgaengig() }
                    .keyboardShortcut("z", modifiers: .command)
                Button("Wiederholen") { Hauptfenster.shared.zustand.editor?.wiederholen() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
            }
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Ausschnitt kopieren") { Hauptfenster.shared.zustand.kopieren() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotKey: HotKey?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        Hauptfenster.shared.zeigen()

        // ⌃⇧S – Gegenstück zu Win+Umschalt+S
        hotKey = HotKey(taste: UInt32(kVK_ANSI_S), modifikatoren: UInt32(controlKey | shiftKey)) {
            AufnahmeSteuerung.shared.zeigeLeiste()
        }

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
        func eintrag(_ titel: String, _ aktion: Selector) {
            let e = NSMenuItem(title: titel, action: aktion, keyEquivalent: "")
            e.target = self
            menue.addItem(e)
        }
        eintrag("Neuer Ausschnitt  (⌃⇧S)", #selector(neuerAusschnitt))
        eintrag("Bildschirmaufnahme beenden", #selector(aufnahmeBeenden))
        menue.addItem(.separator())
        eintrag("Fenster zeigen", #selector(fensterZeigen))
        eintrag("Einstellungen …", #selector(einstellungenZeigen))
        menue.addItem(.separator())
        eintrag("Snipping Werkzeug beenden", #selector(beenden))
        item.menu = menue
        statusItem = item
    }

    @objc private func neuerAusschnitt() { AufnahmeSteuerung.shared.zeigeLeiste() }
    @objc private func aufnahmeBeenden() { AufnahmeSteuerung.shared.stoppeVideo(verwerfen: false) }
    @objc private func fensterZeigen() { Hauptfenster.shared.zeigen() }
    @objc private func einstellungenZeigen() { EinstellungenFenster.shared.zeigen() }
    @objc private func beenden() { NSApp.terminate(nil) }
}

/// Globales Tastenkürzel über Carbon (braucht keine Bedienungshilfen-Freigabe).
final class HotKey {
    private var ref: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let aktion: @MainActor () -> Void

    init(taste: UInt32, modifikatoren: UInt32, aktion: @escaping @MainActor () -> Void) {
        self.aktion = aktion
        var typ = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selbst = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let hk = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { hk.aktion() }
            return OSStatus(noErr)
        }, 1, &typ, selbst, &handlerRef)
        let id = EventHotKeyID(signature: OSType(0x534E_5057), id: 1)
        RegisterEventHotKey(taste, modifikatoren, id, GetApplicationEventTarget(), 0, &ref)
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
