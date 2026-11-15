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

    /// Windows-Blau (Fluent) oder die Akzentfarbe des Macs.
    var akzent: Color { istWindows ? Color(red: 0.0, green: 0.37, blue: 0.72) : Color.accentColor }

    var leiste: Color { istWindows ? dynamisch(0xF9F9F9, 0x2B2B2B) : Color.clear }
    var flaeche: Color { istWindows ? dynamisch(0xEDEDED, 0x1C1C1C) : dynamisch(0xE4E4E4, 0x1E1E1E) }
    var linie: Color { dynamisch(0xDDDDDD, 0x3A3A3A) }
    var eckenradius: CGFloat { istWindows ? 4 : 6 }
    var knopfHoehe: CGFloat { istWindows ? 32 : 26 }
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
    let aktion: () -> Void

    @AppStorage(Schluessel.darstellung) private var darstellung: Darstellung = .windows
    @State private var hover = false

    var body: some View {
        let stil = Stil(darstellung: darstellung)
        Button(action: aktion) {
            Image(systemName: symbol)
                .font(.system(size: stil.istWindows ? 15 : 14))
                .frame(width: 32, height: stil.knopfHoehe)
                .foregroundStyle(aktiv ? stil.akzent : Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: stil.eckenradius)
                        .fill(aktiv ? stil.akzent.opacity(0.15) : (hover ? Color.primary.opacity(0.08) : Color.clear))
                )
                .overlay(alignment: .bottom) {
                    if stil.istWindows && aktiv {
                        Capsule().fill(stil.akzent).frame(width: 14, height: 3).offset(y: -1)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(hilfe)
        .onHover { hover = $0 }
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
    func makeNSView(context: Context) -> NSView { ZiehView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class ZiehView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                window?.performZoom(nil)
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
