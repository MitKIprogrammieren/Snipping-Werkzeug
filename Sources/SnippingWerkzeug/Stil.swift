import SwiftUI
import AppKit

/// Optik je nach gewählter Darstellung (Windows oder Mac).
struct Stil {
    let darstellung: Darstellung

    static var aktuell: Stil {
        let roh = UserDefaults.standard.string(forKey: Schluessel.darstellung) ?? ""
        return Stil(darstellung: Darstellung(rawValue: roh) ?? .windows)
    }

    var istWindows: Bool { darstellung == .windows }

    /// Windows-11-Akzentblau (hell #005FB8, dunkel #60CDFF) oder die Akzentfarbe des Macs.
    var akzent: Color { istWindows ? dynamisch(0x005FB8, 0x60CDFF) : Color.accentColor }
    /// Schrift auf dem gefüllten Akzentknopf („Neu“)
    var aufAkzent: Color { istWindows ? dynamisch(0xFFFFFF, 0x000000) : Color.white }

    /// Mica-Hintergrund von Windows 11
    var leiste: Color { istWindows ? dynamisch(0xF3F3F3, 0x202020) : Color.clear }
    var flaeche: Color { istWindows ? dynamisch(0xEAEAEA, 0x1A1A1A) : dynamisch(0xE4E4E4, 0x1E1E1E) }
    var linie: Color { istWindows ? dynamisch(0xE5E5E5, 0x2E2E2E) : dynamisch(0xDDDDDD, 0x3A3A3A) }
    var karte: Color { istWindows ? dynamisch(0xFBFBFB, 0x2C2C2C) : Color(nsColor: .windowBackgroundColor) }
    var eckenradius: CGFloat { istWindows ? 4 : 6 }
    var knopfHoehe: CGFloat { istWindows ? 32 : 26 }
    var knopfBreite: CGFloat { istWindows ? 36 : 32 }
}

/// Merkt sich, über welchem Knopf die Maus gerade ist (ohne @State, das ohne Xcode nicht baut).
@MainActor
final class HoverSpeicher: ObservableObject {
    static let shared = HoverSpeicher()
    @Published var id: String?

    func setze(_ kennung: String, _ drin: Bool) {
        if drin {
            if id != kennung { id = kennung }
        } else if id == kennung {
            id = nil
        }
    }
}

func dynamisch(_ hell: UInt32, _ dunkel: UInt32) -> Color {
    Color(nsColor: NSColor(name: nil) { a in
        a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(hex: dunkel) : NSColor(hex: hell)
    })
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

// MARK: - Gemeinsame Bausteine

struct LeistenKnopf: View {
    let symbol: String
    let hilfe: String
    var aktiv: Bool = false
    var farbe: Color? = nil
    let aktion: () -> Void

    @AppStorage(Schluessel.darstellung) private var darstellung: Darstellung = .windows

    var body: some View {
        let stil = Stil(darstellung: darstellung)
        HoverKnopf(kennung: "knopf-\(symbol)-\(hilfe)", aktiv: aktiv, hilfe: hilfe, aktion: aktion) {
            Image(systemName: symbol)
                .font(.system(size: stil.istWindows ? 16 : 14))
                .frame(width: stil.knopfBreite, height: stil.knopfHoehe)
                .foregroundStyle(farbe ?? (aktiv ? stil.akzent : Color.primary))
                .overlay(alignment: .bottom) {
                    if stil.istWindows && aktiv {
                        Capsule().fill(stil.akzent).frame(width: 16, height: 3).offset(y: -1)
                    }
                }
        }
    }
}

/// Knopf mit Hover- und Druck-Hintergrund im Stil der jeweiligen Darstellung.
struct HoverKnopf<Inhalt: View>: View {
    let kennung: String
    var aktiv: Bool = false
    var hilfe: String = ""
    let aktion: () -> Void
    @ViewBuilder let inhalt: () -> Inhalt

    @AppStorage(Schluessel.darstellung) private var darstellung: Darstellung = .windows
    @ObservedObject private var hover = HoverSpeicher.shared

    var body: some View {
        let stil = Stil(darstellung: darstellung)
        Button(action: aktion) {
            inhalt().contentShape(Rectangle())
        }
        .buttonStyle(LeistenKnopfStil(aktiv: aktiv, ueber: hover.id == kennung, stil: stil))
        .help(hilfe)
        .onHover { hover.setze(kennung, $0) }
    }
}

/// Hintergrund für Leistenknöpfe: hervorgehoben, wenn aktiv, leicht grau bei Hover, dunkler beim Drücken.
struct LeistenKnopfStil: ButtonStyle {
    let aktiv: Bool
    var ueber: Bool = false
    let stil: Stil

    func makeBody(configuration: Configuration) -> some View {
        let grund: Color
        if configuration.isPressed {
            grund = Color.primary.opacity(0.10)
        } else if aktiv {
            grund = stil.istWindows ? Color.primary.opacity(0.06) : stil.akzent.opacity(0.15)
        } else if ueber {
            grund = Color.primary.opacity(0.06)
        } else {
            grund = Color.clear
        }
        return configuration.label
            .background(RoundedRectangle(cornerRadius: stil.eckenradius).fill(grund))
    }
}

/// Klappmenü, das wie ein normales Kontextmenü an der Maus aufgeht (volle Kontrolle über den Knopf-Look).
@MainActor
enum Klappmenue {
    struct Eintrag {
        var titel: String
        var symbol: String? = nil
        var bild: NSImage? = nil
        var an: Bool = false
        var aktion: (() -> Void)? = nil

        static let trenner = Eintrag(titel: "—")
        static func ueberschrift(_ t: String) -> Eintrag { Eintrag(titel: t) }
    }

    final class Ziel: NSObject {
        let block: () -> Void
        init(_ block: @escaping () -> Void) { self.block = block }
        @objc func ausfuehren() { block() }
    }

    static func zeige(_ eintraege: [Eintrag]) {
        let menue = NSMenu()
        menue.autoenablesItems = false
        for e in eintraege {
            if e.titel == "—" && e.aktion == nil {
                menue.addItem(.separator())
                continue
            }
            guard let aktion = e.aktion else {
                menue.addItem(NSMenuItem.sectionHeader(title: e.titel))
                continue
            }
            let ziel = Ziel(aktion)
            let item = NSMenuItem(title: e.titel, action: #selector(Ziel.ausfuehren), keyEquivalent: "")
            item.target = ziel
            item.representedObject = ziel
            item.state = e.an ? .on : .off
            if let bild = e.bild {
                item.image = bild
            } else if let symbol = e.symbol {
                item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            }
            menue.addItem(item)
        }
        menue.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}

struct Trenner: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.15))
            .frame(width: 1, height: 22)
            .padding(.horizontal, 4)
    }
}

struct VerzoegerungsMenue: View {
    @Binding var verzoegerung: Int
    static let optionen = [0, 3, 5, 10]

    static func text(_ s: Int) -> String { s == 0 ? "Keine Verzögerung" : "\(s) Sekunden Verzögerung" }
    static func kurz(_ s: Int) -> String { s == 0 ? "Aus" : "\(s) s" }

    var body: some View {
        Menu {
            ForEach(Self.optionen, id: \.self) { s in
                Button {
                    verzoegerung = s
                } label: {
                    if s == verzoegerung {
                        Label(Self.text(s), systemImage: "checkmark")
                    } else {
                        Text(Self.text(s))
                    }
                }
            }
        } label: {
            Label(Self.kurz(verzoegerung), systemImage: "timer")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Verzögerung")
    }
}

struct VisualEffect: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
    }
}

/// Fläche, mit der man das Fenster verschieben kann (die Titelleiste ist durch eigene Inhalte überdeckt).
struct FensterZiehFlaeche: NSViewRepresentable {
    var doppelklick: (() -> Void)? = nil

    func makeNSView(context: Context) -> ZiehView {
        let v = ZiehView()
        v.doppelklick = doppelklick
        return v
    }

    func updateNSView(_ nsView: ZiehView, context: Context) {
        nsView.doppelklick = doppelklick
    }

    final class ZiehView: NSView {
        var doppelklick: (() -> Void)?
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                if let doppelklick { doppelklick() } else { window?.performZoom(nil) }
            } else {
                window?.performDrag(with: event)
            }
        }
    }
}

struct AppLogo: View {
    var groesse: CGFloat = 16
    var body: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .frame(width: groesse, height: groesse)
    }
}
