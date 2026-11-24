import SwiftUI
import AppKit

/// Schwebendes, randloses Panel für Aufnahmeleiste, Countdown und Aufnahme-Steuerung.
final class SchwebePanel: NSPanel {
    override var canBecomeKey: Bool { true }

    static func erstelle() -> SchwebePanel {
        let p = SchwebePanel(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.isMovableByWindowBackground = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return p
    }

    func setzeInhalt<V: View>(_ ansicht: V) {
        let h = NSHostingView(rootView: ansicht)
        let groesse = h.fittingSize
        h.frame = NSRect(origin: .zero, size: groesse)
        contentView = h
        setContentSize(groesse)
    }

    func platziere(auf screen: NSScreen, oben: Bool) {
        let vf = screen.visibleFrame
        let g = frame.size
        let y = oben ? vf.maxY - g.height - 10 : vf.minY + 36
        setFrameOrigin(NSPoint(x: vf.midX - g.width / 2, y: y))
    }

    func zentriere(auf screen: NSScreen) {
        let vf = screen.visibleFrame
        let g = frame.size
        setFrameOrigin(NSPoint(x: vf.midX - g.width / 2, y: vf.midY - g.height / 2))
    }
}

// MARK: - Aufnahmeleiste

struct AufnahmeleisteAnsicht: View {
    let starten: (Modus) -> Void
    let schliessen: () -> Void

    @AppStorage(Schluessel.darstellung) private var darstellung: Darstellung = .windows
    @AppStorage(Schluessel.art) private var art: Art = .foto
    @AppStorage(Schluessel.modus) private var modus: Modus = .rechteck
    @AppStorage(Schluessel.verzoegerung) private var verzoegerung = 0

    var body: some View {
        if darstellung == .windows {
            windowsLeiste
        } else {
            macLeiste
        }
    }

    /// Wie Win+Umschalt+S: links Ausschnitt/Aufnahme, dann die Modi, ein Klick startet sofort.
    private var windowsLeiste: some View {
        let stil = Stil(darstellung: darstellung)
        return HStack(spacing: 2) {
            WinArtUmschalter().padding(.trailing, 6)
            ForEach(Modus.allCases) { mo in
                if art == .foto || mo.fuerVideo {
                    LeistenKnopf(symbol: mo.symbol, hilfe: mo.langName, aktiv: mo == modus) {
                        modus = mo
                        starten(mo)
                    }
                }
            }
            Rectangle().fill(stil.linie).frame(width: 1, height: 20).padding(.horizontal, 4)
            LeistenKnopf(symbol: "eyedropper", hilfe: "Farbpipette") { schliessen(); HilfsSteuerung.shared.starte(.farbe) }
            LeistenKnopf(symbol: "ruler", hilfe: "Messen") { schliessen(); HilfsSteuerung.shared.starte(.messen) }
            Rectangle().fill(stil.linie).frame(width: 1, height: 20).padding(.horizontal, 4)
            WinVerzoegerungsMenue(mitText: false)
            Rectangle().fill(stil.linie).frame(width: 1, height: 20).padding(.horizontal, 4)
            LeistenKnopf(symbol: "xmark", hilfe: "Schließen (esc)") { schliessen() }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 8).fill(stil.karte))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(stil.linie, lineWidth: 1))
    }

    /// Wie ⇧⌘5 auf dem Mac: Modus wählen, dann „Aufnehmen“.
    private var macLeiste: some View {
        HStack(spacing: 6) {
            Button {
                schliessen()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(Color.secondary)
            }
            .buttonStyle(.plain)
            .help("Schließen (esc)")

            Trenner()

            ForEach(Modus.allCases) { mo in
                MacModusKnopf(symbol: mo.symbol, titel: mo.name, aktiv: mo == modus) { modus = mo }
            }

            Trenner()

            ForEach(Art.allCases) { a in
                MacModusKnopf(symbol: a.symbol, titel: a == .foto ? "Foto" : "Video", aktiv: a == art) { art = a }
            }

            Trenner()

            MacModusKnopf(symbol: "eyedropper", titel: "Farbe", aktiv: false) { schliessen(); HilfsSteuerung.shared.starte(.farbe) }
            MacModusKnopf(symbol: "ruler", titel: "Messen", aktiv: false) { schliessen(); HilfsSteuerung.shared.starte(.messen) }

            Trenner()

            Menu {
                Section("Timer") {
                    ForEach(VerzoegerungsMenue.optionen, id: \.self) { s in
                        Button {
                            verzoegerung = s
                        } label: {
                            if s == verzoegerung {
                                Label(VerzoegerungsMenue.text(s), systemImage: "checkmark")
                            } else {
                                Text(VerzoegerungsMenue.text(s))
                            }
                        }
                    }
                }
            } label: {
                Text("Optionen")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Button(art == .foto ? "Aufnehmen" : "Aufnahme starten") { starten(modus) }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(VisualEffect(material: .hudWindow))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .environment(\.colorScheme, .dark)
    }
}

struct MacModusKnopf: View {
    let symbol: String
    let titel: String
    let aktiv: Bool
    let aktion: () -> Void

    var body: some View {
        Button(action: aktion) {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 17))
                Text(titel).font(.system(size: 10))
            }
            .frame(width: 58, height: 44)
            .foregroundStyle(Color.white)
            .background(RoundedRectangle(cornerRadius: 6).fill(aktiv ? Color.white.opacity(0.22) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Countdown

@MainActor
final class CountdownModell: ObservableObject {
    @Published var zahl = 0
}

struct CountdownAnsicht: View {
    @ObservedObject var m: CountdownModell

    var body: some View {
        Text("\(m.zahl)")
            .font(.system(size: 64, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(Color.white)
            .frame(width: 140, height: 140)
            .background(Circle().fill(Color.black.opacity(0.6)))
    }
}

// MARK: - Steuerung während der Videoaufnahme

struct AufnahmeSteuerAnsicht: View {
    let start: Date
    let stoppen: () -> Void
    let verwerfen: () -> Void

    @AppStorage(Schluessel.darstellung) private var darstellung: Darstellung = .windows
    @Environment(\.colorScheme) private var farbschema

    var body: some View {
        let windows = darstellung == .windows
        HStack(spacing: 10) {
            Circle().fill(Color.red).frame(width: 10, height: 10)
            TimelineView(.periodic(from: start, by: 1)) { kontext in
                Text(dauer(bis: kontext.date))
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
            }
            Button(action: stoppen) {
                Label("Stopp", systemImage: "stop.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(windows ? Color(red: 0.0, green: 0.37, blue: 0.72) : Color.red)
            Button(action: verwerfen) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Aufnahme verwerfen")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background {
            if windows {
                RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .windowBackgroundColor))
            } else {
                VisualEffect(material: .hudWindow).clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .environment(\.colorScheme, windows ? farbschema : .dark)
    }

    private func dauer(bis jetzt: Date) -> String {
        let s = max(0, Int(jetzt.timeIntervalSince(start)))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}

struct RahmenAnsicht: View {
    var body: some View {
        Rectangle()
            .strokeBorder(Color.red, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
    }
}
