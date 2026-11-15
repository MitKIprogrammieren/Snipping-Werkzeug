import SwiftUI
import AppKit

enum Schluessel {
    static let darstellung = "darstellung"
    static let art = "art"
    static let modus = "modus"
    static let verzoegerung = "verzoegerung"
    static let autoKopieren = "autoKopieren"
    static let autoSpeichern = "autoSpeichern"
    static let ordner = "speicherOrdner"
    static let mauszeiger = "mauszeiger"
    static let systemton = "systemton"
    static let mikrofon = "mikrofon"
}

enum Einstellungen {
    static var standardOrdner: String {
        let bilder = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
        return bilder.appendingPathComponent("Snipping Werkzeug").path
    }

    static func registrieren() {
        UserDefaults.standard.register(defaults: [
            Schluessel.darstellung: Darstellung.windows.rawValue,
            Schluessel.art: Art.foto.rawValue,
            Schluessel.modus: Modus.rechteck.rawValue,
            Schluessel.verzoegerung: 0,
            Schluessel.autoKopieren: true,
            Schluessel.autoSpeichern: true,
            Schluessel.ordner: standardOrdner,
            Schluessel.mauszeiger: true,
            Schluessel.systemton: false,
            Schluessel.mikrofon: false,
        ])
    }

    private static var d: UserDefaults { .standard }

    static var art: Art { Art(rawValue: d.string(forKey: Schluessel.art) ?? "") ?? .foto }
    static var modus: Modus { Modus(rawValue: d.string(forKey: Schluessel.modus) ?? "") ?? .rechteck }
    static var verzoegerung: Int { d.integer(forKey: Schluessel.verzoegerung) }
    static var autoKopieren: Bool { d.bool(forKey: Schluessel.autoKopieren) }
    static var autoSpeichern: Bool { d.bool(forKey: Schluessel.autoSpeichern) }
    static var mauszeiger: Bool { d.bool(forKey: Schluessel.mauszeiger) }
    static var systemton: Bool { d.bool(forKey: Schluessel.systemton) }
    static var mikrofon: Bool { d.bool(forKey: Schluessel.mikrofon) }
    static var ordner: URL {
        URL(fileURLWithPath: d.string(forKey: Schluessel.ordner) ?? standardOrdner, isDirectory: true)
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.1"
    }
}

struct EinstellungenAnsicht: View {
    @AppStorage(Schluessel.darstellung) private var darstellung: Darstellung = .windows
    @AppStorage(Schluessel.autoKopieren) private var autoKopieren = true
    @AppStorage(Schluessel.autoSpeichern) private var autoSpeichern = true
    @AppStorage(Schluessel.ordner) private var ordner = Einstellungen.standardOrdner
    @AppStorage(Schluessel.mauszeiger) private var mauszeiger = true
    @AppStorage(Schluessel.systemton) private var systemton = false
    @AppStorage(Schluessel.mikrofon) private var mikrofon = false

    var body: some View {
        Form {
            Section("Darstellung") {
                Picker("Stil", selection: $darstellung) {
                    ForEach(Darstellung.allCases) { d in
                        Text(d.name).tag(d)
                    }
                }
                .pickerStyle(.segmented)
                Text(darstellung == .windows
                     ? "Wie das Snipping Tool von Windows 11: Fensterknöpfe rechts, Aufnahmeleiste oben, Hinweis unten rechts, Lineal."
                     : "Wie die Bildschirmfoto-App von macOS (⇧⌘5): Aufnahmeleiste unten mit „Aufnehmen“-Knopf.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Ausschnitte") {
                Toggle("Automatisch in die Zwischenablage kopieren", isOn: $autoKopieren)
                Toggle("Automatisch speichern", isOn: $autoSpeichern)
                LabeledContent("Speicherort") {
                    HStack {
                        Text((ordner as NSString).abbreviatingWithTildeInPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("Ändern …") { waehleOrdner() }
                    }
                }
                Button("Speicherort im Finder öffnen") {
                    let url = URL(fileURLWithPath: ordner, isDirectory: true)
                    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(url)
                }
            }

            Section("Bildschirmaufnahme") {
                Toggle("Mauszeiger aufnehmen", isOn: $mauszeiger)
                Toggle("Systemton aufnehmen", isOn: $systemton)
                Toggle("Mikrofon aufnehmen", isOn: $mikrofon)
            }

            Section {
                ForEach(Aktion.allCases.filter(\.global)) { a in KuerzelZeile(aktion: a) }
            } header: {
                Text("Tastenkürzel – überall")
            } footer: {
                Text("Funktionieren auch, wenn die App im Hintergrund ist.")
            }

            Section {
                ForEach(Aktion.allCases.filter { !$0.global }) { a in KuerzelZeile(aktion: a) }
            } header: {
                Text("Tastenkürzel – in der App")
            } footer: {
                HStack {
                    Text("esc bricht ab, ↩ bestätigt – diese beiden sind fest.")
                    Spacer()
                    Button("Alle zurücksetzen") { KuerzelSpeicher.shared.allesZuruecksetzen() }
                }
            }

            Section("Über") {
                LabeledContent("Version", value: Einstellungen.version)
            }
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 720)
    }

    private func waehleOrdner() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.canCreateDirectories = true
        p.prompt = "Auswählen"
        p.directoryURL = URL(fileURLWithPath: ordner, isDirectory: true)
        if p.runModal() == .OK, let url = p.url {
            ordner = url.path
        }
    }
}

@MainActor
final class EinstellungenFenster {
    static let shared = EinstellungenFenster()
    private var fenster: NSWindow?

    func zeigen() {
        if fenster == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 720),
                             styleMask: [.titled, .closable],
                             backing: .buffered, defer: false)
            w.title = "Einstellungen"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: EinstellungenAnsicht())
            w.center()
            fenster = w
        }
        fenster?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
