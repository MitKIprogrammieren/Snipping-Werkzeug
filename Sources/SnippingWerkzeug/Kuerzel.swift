import SwiftUI
import AppKit
import Carbon.HIToolbox

// MARK: - Ein Tastenkürzel

struct Kuerzel: Codable, Equatable, Hashable {
    var tastenCode: UInt16
    var zeichen: String          // Grundzeichen ohne Modifikatoren, z. B. "s"
    var modifikatoren: UInt      // NSEvent.ModifierFlags (nur ⌃⌥⇧⌘)

    static let erlaubteFlags: NSEvent.ModifierFlags = [.control, .option, .shift, .command]

    init(tastenCode: Int, zeichen: String, flags: NSEvent.ModifierFlags) {
        self.tastenCode = UInt16(tastenCode)
        self.zeichen = zeichen
        self.modifikatoren = flags.intersection(Kuerzel.erlaubteFlags).rawValue
    }

    init?(event: NSEvent) {
        guard event.type == .keyDown, Int(event.keyCode) != kVK_Escape else { return nil }
        let code = Int(event.keyCode)
        let basis = (event.characters(byApplyingModifiers: []) ?? event.charactersIgnoringModifiers ?? "").lowercased()
        if Kuerzel.sondertasten[code] == nil && basis.isEmpty { return nil }
        self.init(tastenCode: code, zeichen: basis, flags: event.modifierFlags)
    }

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifikatoren) }

    var istFunktionstaste: Bool { Kuerzel.funktionstasten.contains(Int(tastenCode)) }

    /// Mindestens eine Sondertaste (⌃⌥⇧⌘) oder eine F-Taste – sonst stört das Kürzel beim Tippen.
    var gueltig: Bool { !flags.subtracting(.shift).isEmpty || istFunktionstaste }

    var text: String {
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option) { s += "⌥" }
        if flags.contains(.shift) { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        return s + tastenName
    }

    var tastenName: String {
        if let sonder = Kuerzel.sondertasten[Int(tastenCode)] { return sonder.name }
        return zeichen.uppercased()
    }

    var carbonModifikatoren: UInt32 {
        var m = 0
        if flags.contains(.command) { m |= cmdKey }
        if flags.contains(.shift) { m |= shiftKey }
        if flags.contains(.option) { m |= optionKey }
        if flags.contains(.control) { m |= controlKey }
        return UInt32(m)
    }

    var swiftUI: KeyboardShortcut? {
        let taste: KeyEquivalent
        if let sonder = Kuerzel.sondertasten[Int(tastenCode)] {
            taste = sonder.taste
        } else if let c = zeichen.first {
            taste = KeyEquivalent(c)
        } else {
            return nil
        }
        var m: SwiftUI.EventModifiers = []
        if flags.contains(.command) { m.insert(.command) }
        if flags.contains(.shift) { m.insert(.shift) }
        if flags.contains(.option) { m.insert(.option) }
        if flags.contains(.control) { m.insert(.control) }
        return KeyboardShortcut(taste, modifiers: m)
    }

    // MARK: Tastentabellen

    static let funktionstasten: [Int] = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6,
                                         kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12]

    static let sondertasten: [Int: (name: String, taste: KeyEquivalent)] = {
        var t: [Int: (name: String, taste: KeyEquivalent)] = [
            kVK_Return: ("↩", .return),
            kVK_Tab: ("⇥", .tab),
            kVK_Space: ("Leertaste", .space),
            kVK_Delete: ("⌫", .delete),
            kVK_ForwardDelete: ("⌦", .deleteForward),
            kVK_LeftArrow: ("←", .leftArrow),
            kVK_RightArrow: ("→", .rightArrow),
            kVK_UpArrow: ("↑", .upArrow),
            kVK_DownArrow: ("↓", .downArrow),
            kVK_Home: ("↖", .home),
            kVK_End: ("↘", .end),
            kVK_PageUp: ("⇞", .pageUp),
            kVK_PageDown: ("⇟", .pageDown),
        ]
        for (i, code) in funktionstasten.enumerated() {
            let zeichen = Character(Unicode.Scalar(UInt32(NSF1FunctionKey + i))!)
            t[code] = ("F\(i + 1)", KeyEquivalent(zeichen))
        }
        return t
    }()
}

// MARK: - Alle Aktionen mit Kürzel

enum Aktion: String, CaseIterable, Identifiable {
    case ausschnittGlobal, videoGlobal, vollbildGlobal
    case neu, kopieren, speichern, rueckgaengig, wiederholen
    case stift, marker, radierer, lineal, zuschneiden, texterkennung

    var id: String { rawValue }

    var titel: String {
        switch self {
        case .ausschnittGlobal: return "Aufnahmeleiste öffnen"
        case .videoGlobal: return "Bildschirmaufnahme (Video)"
        case .vollbildGlobal: return "Vollbild sofort aufnehmen"
        case .neu: return "Neuer Ausschnitt"
        case .kopieren: return "Ausschnitt kopieren"
        case .speichern: return "Speichern unter"
        case .rueckgaengig: return "Rückgängig"
        case .wiederholen: return "Wiederholen"
        case .stift: return "Kugelschreiber"
        case .marker: return "Textmarker"
        case .radierer: return "Radierer"
        case .lineal: return "Lineal"
        case .zuschneiden: return "Zuschneiden"
        case .texterkennung: return "Textaktionen (Text erkennen)"
        }
    }

    /// Globale Kürzel funktionieren überall, auch wenn die App im Hintergrund ist.
    var global: Bool {
        switch self {
        case .ausschnittGlobal, .videoGlobal, .vollbildGlobal: return true
        default: return false
        }
    }

    var standard: Kuerzel? {
        switch self {
        case .ausschnittGlobal: return Kuerzel(tastenCode: kVK_ANSI_S, zeichen: "s", flags: [.control, .shift])
        case .videoGlobal: return Kuerzel(tastenCode: kVK_ANSI_R, zeichen: "r", flags: [.control, .shift])
        case .vollbildGlobal: return nil
        case .neu: return Kuerzel(tastenCode: kVK_ANSI_N, zeichen: "n", flags: [.command])
        case .kopieren: return Kuerzel(tastenCode: kVK_ANSI_C, zeichen: "c", flags: [.command, .shift])
        case .speichern: return Kuerzel(tastenCode: kVK_ANSI_S, zeichen: "s", flags: [.command])
        case .rueckgaengig: return Kuerzel(tastenCode: kVK_ANSI_Z, zeichen: "z", flags: [.command])
        case .wiederholen: return Kuerzel(tastenCode: kVK_ANSI_Z, zeichen: "z", flags: [.command, .shift])
        case .stift, .marker, .radierer, .lineal, .zuschneiden, .texterkennung: return nil
        }
    }
}

// MARK: - Speicher

@MainActor
final class KuerzelSpeicher: ObservableObject {
    static let shared = KuerzelSpeicher()
    static let schluessel = "kuerzel"

    /// Nur Abweichungen vom Standard; ein Eintrag mit nil heißt „bewusst kein Kürzel“.
    @Published private var gespeichert: [String: Kuerzel?] = [:]

    /// Zustand der Aufnahmefelder in den Einstellungen
    @Published var aufnehmend: Aktion?
    @Published var fehler: [Aktion: String] = [:]

    private init() {
        if let roh = UserDefaults.standard.string(forKey: Self.schluessel),
           let daten = roh.data(using: .utf8),
           let werte = try? JSONDecoder().decode([String: Kuerzel?].self, from: daten) {
            gespeichert = werte
        }
    }

    func kuerzel(_ a: Aktion) -> Kuerzel? {
        if let eintrag = gespeichert[a.rawValue] { return eintrag }
        return a.standard
    }

    func text(_ a: Aktion) -> String? { kuerzel(a)?.text }

    func shortcut(_ a: Aktion) -> KeyboardShortcut? { kuerzel(a)?.swiftUI }

    /// Hilfetext für Knöpfe, z. B. „Kopieren (⇧⌘C)“.
    func hilfe(_ titel: String, _ a: Aktion) -> String {
        guard let t = text(a) else { return titel }
        return "\(titel) (\(t))"
    }

    func istStandard(_ a: Aktion) -> Bool { gespeichert[a.rawValue] == nil }

    /// Setzt ein Kürzel. Gibt eine Fehlermeldung zurück, wenn es nicht geht.
    func setze(_ k: Kuerzel?, fuer a: Aktion) -> String? {
        if let k {
            if !k.gueltig {
                return "Bitte mit ⌃, ⌥ oder ⌘ kombinieren (oder eine F-Taste nehmen)."
            }
            if let andere = Aktion.allCases.first(where: { $0 != a && kuerzel($0) == k }) {
                return "\(k.text) ist schon für „\(andere.titel)“ vergeben."
            }
        }
        let vorher = gespeichert[a.rawValue]
        if k == a.standard {
            gespeichert.removeValue(forKey: a.rawValue)
        } else {
            gespeichert[a.rawValue] = .some(k)
        }
        sichern()

        if a.global {
            let fehlgeschlagen = HotKeyVerwaltung.shared.aktualisieren()
            if fehlgeschlagen.contains(a) {
                if let vorher { gespeichert[a.rawValue] = vorher } else { gespeichert.removeValue(forKey: a.rawValue) }
                sichern()
                HotKeyVerwaltung.shared.aktualisieren()
                return "\(k?.text ?? "Das Kürzel") wird schon von macOS oder einer anderen App benutzt."
            }
        }
        return nil
    }

    func zuruecksetzen(_ a: Aktion) {
        gespeichert.removeValue(forKey: a.rawValue)
        sichern()
        if a.global { HotKeyVerwaltung.shared.aktualisieren() }
    }

    func allesZuruecksetzen() {
        gespeichert = [:]
        sichern()
        HotKeyVerwaltung.shared.aktualisieren()
    }

    private func sichern() {
        let roh = (try? JSONEncoder().encode(gespeichert)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        UserDefaults.standard.set(roh, forKey: Self.schluessel)
    }
}

// MARK: - Globale Kürzel (Carbon, braucht keine Bedienungshilfen-Freigabe)

@MainActor
final class HotKeyVerwaltung {
    static let shared = HotKeyVerwaltung()

    private var handler: EventHandlerRef?
    private var refs: [EventHotKeyRef] = []
    private var aktionen: [UInt32: Aktion] = [:]
    private var pausiert = false

    func start() {
        if handler == nil {
            var typ = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var hk = EventHotKeyID()
                let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                               EventParamType(typeEventHotKeyID), nil,
                                               MemoryLayout<EventHotKeyID>.size, nil, &hk)
                guard status == noErr else { return OSStatus(eventNotHandledErr) }
                let id = hk.id
                MainActor.assumeIsolated { HotKeyVerwaltung.shared.ausloesen(id) }
                return OSStatus(noErr)
            }, 1, &typ, nil, &handler)
        }
        aktualisieren()
    }

    /// Meldet alle globalen Kürzel neu an. Gibt die Aktionen zurück, die nicht angemeldet werden konnten.
    @discardableResult
    func aktualisieren() -> [Aktion] {
        for ref in refs { UnregisterEventHotKey(ref) }
        refs.removeAll()
        aktionen.removeAll()
        guard !pausiert else { return [] }

        var fehlgeschlagen: [Aktion] = []
        for (i, a) in Aktion.allCases.filter(\.global).enumerated() {
            guard let k = KuerzelSpeicher.shared.kuerzel(a) else { continue }
            let id = EventHotKeyID(signature: OSType(0x534E_5057), id: UInt32(i + 1))
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(k.tastenCode), k.carbonModifikatoren, id,
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                refs.append(ref)
                aktionen[id.id] = a
            } else {
                fehlgeschlagen.append(a)
            }
        }
        return fehlgeschlagen
    }

    /// Während in den Einstellungen ein Kürzel aufgenommen wird, sind die globalen Kürzel aus.
    func pausieren(_ p: Bool) {
        guard p != pausiert else { return }
        pausiert = p
        aktualisieren()
    }

    private func ausloesen(_ id: UInt32) {
        guard let a = aktionen[id] else { return }
        AufnahmeSteuerung.shared.ausApp = false
        switch a {
        case .ausschnittGlobal: AufnahmeSteuerung.shared.zeigeLeiste()
        case .videoGlobal: AufnahmeSteuerung.shared.zeigeLeiste(art: .video)
        case .vollbildGlobal: AufnahmeSteuerung.shared.starte(modus: .vollbild, art: .foto)
        default: break
        }
    }
}

// MARK: - Aufnahmefeld in den Einstellungen

struct KuerzelZeile: View {
    let aktion: Aktion
    @ObservedObject private var speicher = KuerzelSpeicher.shared

    private var aufnehmend: Bool { speicher.aufnehmend == aktion }
    private var fehler: String? { speicher.fehler[aktion] }

    private func setzeFehler(_ text: String?) { speicher.fehler[aktion] = text }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            LabeledContent(aktion.titel) {
                HStack(spacing: 6) {
                    feld
                    Button {
                        setzeFehler(speicher.setze(nil, fuer: aktion))
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Kein Kürzel")
                    .disabled(speicher.kuerzel(aktion) == nil)

                    Button {
                        speicher.zuruecksetzen(aktion)
                        setzeFehler(nil)
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .buttonStyle(.borderless)
                    .help("Zurück auf Standard (\(aktion.standard?.text ?? "kein Kürzel"))")
                    .disabled(speicher.istStandard(aktion))
                }
            }
            if let fehler {
                Text(fehler)
                    .font(.caption)
                    .foregroundStyle(Color.red)
            }
        }
    }

    private var feld: some View {
        let k = speicher.kuerzel(aktion)
        return Text(aufnehmend ? "Tasten drücken …" : (k?.text ?? "Kein Kürzel"))
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(aufnehmend ? Color.accentColor : (k == nil ? Color.secondary : Color.primary))
            .frame(minWidth: 120)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 6)
                .fill(aufnehmend ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(aufnehmend ? Color.accentColor : Color.primary.opacity(0.15),
                              lineWidth: aufnehmend ? 1.5 : 0.5))
            .overlay(
                KuerzelRecorder(
                    beiKuerzel: { neu in setzeFehler(speicher.setze(neu, fuer: aktion)) },
                    beiStatus: { an in
                        if an {
                            speicher.aufnehmend = aktion
                            setzeFehler(nil)
                        } else if speicher.aufnehmend == aktion {
                            speicher.aufnehmend = nil
                        }
                        HotKeyVerwaltung.shared.pausieren(speicher.aufnehmend != nil)
                    }
                )
            )
            .help("Klicken und neue Tastenkombination drücken – esc bricht ab")
    }
}

struct KuerzelRecorder: NSViewRepresentable {
    let beiKuerzel: (Kuerzel) -> Void
    let beiStatus: (Bool) -> Void

    func makeNSView(context: Context) -> RecorderView {
        let v = RecorderView()
        v.beiKuerzel = beiKuerzel
        v.beiStatus = beiStatus
        return v
    }

    func updateNSView(_ nsView: RecorderView, context: Context) {
        nsView.beiKuerzel = beiKuerzel
        nsView.beiStatus = beiStatus
    }

    final class RecorderView: NSView {
        var beiKuerzel: ((Kuerzel) -> Void)?
        var beiStatus: ((Bool) -> Void)?
        private var aufnehmend = false {
            didSet { if aufnehmend != oldValue { beiStatus?(aufnehmend) } }
        }

        override var acceptsFirstResponder: Bool { true }

        override func mouseDown(with event: NSEvent) {
            if aufnehmend {
                window?.makeFirstResponder(nil)
            } else {
                window?.makeFirstResponder(self)
                aufnehmend = true
            }
        }

        override func resignFirstResponder() -> Bool {
            aufnehmend = false
            return true
        }

        override func keyDown(with event: NSEvent) {
            guard aufnehmend else {
                super.keyDown(with: event)
                return
            }
            behandle(event)
        }

        // ⌘-Kombinationen kommen hier an, bevor das Menü sie bekommt
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard aufnehmend, event.type == .keyDown else { return false }
            behandle(event)
            return true
        }

        private func behandle(_ event: NSEvent) {
            if Int(event.keyCode) == kVK_Escape {
                window?.makeFirstResponder(nil)
                return
            }
            guard let k = Kuerzel(event: event) else {
                NSSound.beep()
                return
            }
            window?.makeFirstResponder(nil)
            beiKuerzel?(k)
        }
    }
}
