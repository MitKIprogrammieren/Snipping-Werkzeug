import SwiftUI
import AppKit

// Angeheftete Ausschnitte: schwebende Fenster, die immer im Vordergrund bleiben.

@MainActor
final class AngeheftetModell: ObservableObject {
    static let leistenHoehe: CGFloat = 30

    let bild: CGImage
    /// Größe in Punkten bei 100 %
    let basis: CGSize
    weak var fenster: NSWindow?

    @Published private(set) var zoom: CGFloat
    @Published var deckkraft: Double = 1.0 {
        didSet { fenster?.alphaValue = CGFloat(deckkraft) }
    }
    @Published var durchklicken = false {
        didSet { fenster?.ignoresMouseEvents = durchklicken }
    }

    init(bild: CGImage, basis: CGSize, zoom: CGFloat) {
        self.bild = bild
        self.basis = basis
        self.zoom = zoom
    }

    var inhaltsGroesse: NSSize {
        NSSize(width: max(120, basis.width * zoom), height: basis.height * zoom + Self.leistenHoehe)
    }

    func setzeZoom(_ z: CGFloat) {
        zoom = min(max(z, 0.1), 4)
        guard let w = fenster else { return }
        var f = w.frame
        let oben = f.maxY
        f.size = inhaltsGroesse
        f.origin.y = oben - f.size.height
        w.setFrame(f, display: true)
    }
}

final class AngeheftetFenster: NSPanel {
    var modell: AngeheftetModell?

    override var canBecomeKey: Bool { true }

    static func erstelle(modell: AngeheftetModell) -> AngeheftetFenster {
        let w = AngeheftetFenster(contentRect: NSRect(origin: .zero, size: modell.inhaltsGroesse),
                                  styleMask: [.borderless, .nonactivatingPanel],
                                  backing: .buffered, defer: false)
        w.modell = modell
        w.level = .floating
        w.isFloatingPanel = true
        w.hidesOnDeactivate = false
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        w.isReleasedWhenClosed = false
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        w.contentView = NSHostingView(rootView: AngeheftetAnsicht(m: modell))
        modell.fenster = w
        return w
    }
}

@MainActor
final class AnheftVerwaltung {
    static let shared = AnheftVerwaltung()

    private var fenster: [AngeheftetFenster] = []
    private var mausrad: Any?

    var anzahl: Int { fenster.count }
    var irgendwoDurchklicken: Bool { fenster.contains { $0.modell?.durchklicken == true } }

    func anheften(_ bild: CGImage) {
        let screen = Bildschirm.screenUnterMaus()
        let faktor = screen.backingScaleFactor
        let basis = CGSize(width: CGFloat(bild.width) / faktor, height: CGFloat(bild.height) / faktor)
        let vf = screen.visibleFrame
        let start = min(1, (vf.width * 0.6) / basis.width, (vf.height * 0.6) / basis.height)

        let modell = AngeheftetModell(bild: bild, basis: basis, zoom: start)
        let w = AngeheftetFenster.erstelle(modell: modell)
        // Neben der Maus, aber ganz auf dem Bildschirm; mehrere leicht versetzt
        let maus = NSEvent.mouseLocation
        let g = modell.inhaltsGroesse
        let versatz = CGFloat(fenster.count % 6) * 24
        var x = maus.x + 20 + versatz
        var y = maus.y - g.height - 20 - versatz
        x = min(max(x, vf.minX + 8), vf.maxX - g.width - 8)
        y = min(max(y, vf.minY + 8), vf.maxY - g.height - 8)
        w.setFrameOrigin(NSPoint(x: x, y: y))
        w.orderFrontRegardless()
        fenster.append(w)
        installiereMausrad()
    }

    func schliesse(_ m: AngeheftetModell) {
        guard let i = fenster.firstIndex(where: { $0.modell === m }) else { return }
        fenster[i].orderOut(nil)
        fenster.remove(at: i)
    }

    func alleSchliessen() {
        for w in fenster { w.orderOut(nil) }
        fenster.removeAll()
    }

    /// Schaltet „Durchklicken“ für alle angehefteten Ausschnitte um.
    func schalteDurchklicken() {
        let neu = !irgendwoDurchklicken
        for w in fenster { w.modell?.durchklicken = neu }
    }

    private func installiereMausrad() {
        guard mausrad == nil else { return }
        mausrad = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { e in
            MainActor.assumeIsolated { () -> NSEvent? in
                guard let w = e.window as? AngeheftetFenster, let m = w.modell else { return e }
                let delta = e.hasPreciseScrollingDeltas ? e.scrollingDeltaY * 0.01 : e.scrollingDeltaY * 0.05
                m.setzeZoom(m.zoom * (1 + delta))
                return nil
            }
        }
    }
}

struct AngeheftetAnsicht: View {
    @ObservedObject var m: AngeheftetModell
    @AppStorage(Schluessel.darstellung) private var darstellung: Darstellung = .windows

    var body: some View {
        let stil = Stil(darstellung: darstellung)
        let ecke: CGFloat = stil.istWindows ? 6 : 10
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                Image(systemName: "circle.lefthalf.filled")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .help("Deckkraft")
                Slider(value: $m.deckkraft, in: 0.2...1.0)
                    .controlSize(.mini)
                    .frame(width: 64)
                Text("\(Int((m.deckkraft * 100).rounded())) %")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 32, alignment: .leading)
                Spacer(minLength: 2)
                MiniKnopf(m: m, symbol: "minus.magnifyingglass", hilfe: "Verkleinern (Mausrad)") { m.setzeZoom(m.zoom / 1.25) }
                MiniKnopf(m: m, symbol: "plus.magnifyingglass", hilfe: "Vergrößern (Mausrad)") { m.setzeZoom(m.zoom * 1.25) }
                MiniKnopf(m: m, symbol: "cursorarrow.slash", hilfe: durchklickenHilfe) { m.durchklicken = true }
                MiniKnopf(m: m, symbol: "pencil", hilfe: "Im Editor öffnen") {
                    Hauptfenster.shared.zeigeBild(m.bild, meldung: "Aus angeheftetem Ausschnitt geöffnet")
                }
                MiniKnopf(m: m, symbol: "doc.on.doc", hilfe: "Kopieren") { Ablage.kopiere(m.bild) }
                MiniKnopf(m: m, symbol: "xmark", hilfe: "Schließen") { AnheftVerwaltung.shared.schliesse(m) }
            }
            .padding(.horizontal, 6)
            .frame(height: AngeheftetModell.leistenHoehe)
            .background(stil.karte)

            ZStack {
                FensterZiehFlaeche(doppelklick: {
                    Hauptfenster.shared.zeigeBild(m.bild, meldung: "Aus angeheftetem Ausschnitt geöffnet")
                })
                Image(decorative: m.bild, scale: 1)
                    .resizable()
                    .allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: ecke))
        .overlay(
            RoundedRectangle(cornerRadius: ecke)
                .strokeBorder(stil.akzent, style: StrokeStyle(lineWidth: 2, dash: m.durchklicken ? [6, 4] : []))
        )
    }

    private var durchklickenHilfe: String {
        let kuerzel = KuerzelSpeicher.shared.text(.durchklickenGlobal)
        let zurueck = kuerzel.map { "mit \($0) oder " } ?? ""
        return "Durchklicken – Klicks gehen ans Programm darunter (zurück \(zurueck)über das Menüleisten-Symbol)"
    }
}

private struct MiniKnopf: View {
    @ObservedObject var m: AngeheftetModell
    let symbol: String
    let hilfe: String
    let aktion: () -> Void

    var body: some View {
        HoverKnopf(kennung: "pin-\(ObjectIdentifier(m).hashValue)-\(symbol)", hilfe: hilfe, aktion: aktion) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .frame(width: 24, height: 24)
        }
    }
}
