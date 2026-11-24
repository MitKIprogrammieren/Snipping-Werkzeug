import SwiftUI
import AppKit
import ScreenCaptureKit

// Scrollaufnahme: Der Bereich wird laufend aufgenommen, während du scrollst.
// Neue Zeilen werden über einen Zeilenvergleich erkannt und unten angehängt.

@MainActor
final class ScrollModell: ObservableObject {
    @Published var hoehe = 0
    @Published var breite = 0
    @Published var hinweis = "Jetzt langsam nach unten scrollen"
}

@MainActor
final class ScrollAufnahme {
    private static var laufend: ScrollAufnahme?

    private let filter: SCContentFilter
    private let konfig: SCStreamConfiguration
    private let modell = ScrollModell()
    private let fertig: (CGImage?) -> Void
    private var streifen: [CGImage] = []
    private var signaturen: [UInt64]?
    private var aktiv = true
    private var panel: SchwebePanel?
    private var rahmen: NSWindow?
    static let maximaleHoehe = 40_000

    static func starte(bereich r: CGRect, screen: NSScreen, display: SCDisplay, inhalt: SCShareableContent,
                       fertig: @escaping (CGImage?) -> Void) {
        let filter = SCContentFilter(display: display, excludingApplications: Bildschirm.eigeneApp(inhalt), exceptingWindows: [])
        let k = SCStreamConfiguration()
        k.sourceRect = r
        k.width = Int((r.width * screen.backingScaleFactor).rounded())
        k.height = Int((r.height * screen.backingScaleFactor).rounded())
        k.showsCursor = false
        k.captureResolution = .best
        let sitzung = ScrollAufnahme(filter: filter, konfig: k, fertig: fertig)
        laufend = sitzung
        let global = CGRect(x: screen.frame.minX + r.minX, y: screen.frame.maxY - r.maxY, width: r.width, height: r.height)
        sitzung.zeigeOberflaeche(rahmen: global, screen: screen)
        sitzung.schleife()
    }

    private init(filter: SCContentFilter, konfig: SCStreamConfiguration, fertig: @escaping (CGImage?) -> Void) {
        self.filter = filter
        self.konfig = konfig
        self.fertig = fertig
    }

    // MARK: Oberfläche

    private func zeigeOberflaeche(rahmen r: CGRect, screen: NSScreen) {
        let w = NSWindow(contentRect: r.insetBy(dx: -3, dy: -3), styleMask: [.borderless], backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.ignoresMouseEvents = true          // Scrollen geht durch ans Programm darunter
        w.level = .statusBar
        w.isReleasedWhenClosed = false
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        w.contentView = NSHostingView(rootView:
            Rectangle().strokeBorder(Color.blue, style: StrokeStyle(lineWidth: 2, dash: [8, 4])))
        w.orderFrontRegardless()
        rahmen = w

        let p = SchwebePanel.erstelle()
        p.setzeInhalt(ScrollSteuerAnsicht(m: modell,
                                          fertig: { [weak self] in self?.beende(uebernehmen: true) },
                                          abbrechen: { [weak self] in self?.beende(uebernehmen: false) }))
        p.platziere(auf: screen, oben: true)
        p.orderFrontRegardless()
        panel = p
    }

    // MARK: Aufnehmen und zusammensetzen

    private func schleife() {
        Task {
            while aktiv {
                if let bild = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: konfig) {
                    verarbeite(bild)
                }
                try? await Task.sleep(for: .milliseconds(180))
            }
        }
    }

    private func verarbeite(_ bild: CGImage) {
        let neu = Zeilenabgleich.signaturen(bild)
        guard let alt = signaturen else {
            streifen = [bild]
            signaturen = neu
            modell.breite = bild.width
            modell.hoehe = bild.height
            return
        }
        guard let dy = Zeilenabgleich.versatz(alt: alt, neu: neu), dy > 0,
              let streifenNeu = bild.cropping(to: CGRect(x: 0, y: bild.height - dy, width: bild.width, height: dy)) else {
            return          // nichts gescrollt oder nicht eindeutig – nächstes Bild abwarten
        }
        streifen.append(streifenNeu)
        signaturen = neu
        modell.hoehe += dy
        modell.hinweis = "Weiter scrollen – oder auf „Fertig“ klicken"
        if modell.hoehe >= Self.maximaleHoehe {
            modell.hinweis = "Maximale Länge erreicht"
            beende(uebernehmen: true)
        }
    }

    private func beende(uebernehmen: Bool) {
        guard aktiv else { return }
        aktiv = false
        panel?.orderOut(nil)
        rahmen?.orderOut(nil)
        Self.laufend = nil
        fertig(uebernehmen ? zusammensetzen() : nil)
    }

    private func zusammensetzen() -> CGImage? {
        guard let erstes = streifen.first else { return nil }
        let breite = erstes.width
        let hoehe = streifen.reduce(0) { $0 + $1.height }
        guard let ctx = CGContext(data: nil, width: breite, height: hoehe, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: Bildbearbeitung.farbraum,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return erstes }
        // CGContext zählt von unten: der erste Streifen gehört ganz nach oben
        var y = hoehe
        for s in streifen {
            y -= s.height
            ctx.draw(s, in: CGRect(x: 0, y: y, width: s.width, height: s.height))
        }
        return ctx.makeImage()
    }
}

/// Vergleicht Bildzeilen über kurze Prüfsummen, um den Scroll-Versatz zu finden.
enum Zeilenabgleich {
    /// 0 = einfarbige Zeile (taugt nicht zum Vergleichen)
    static func signaturen(_ bild: CGImage) -> [UInt64] {
        let w = bild.width, h = bild.height
        var ergebnis = [UInt64](repeating: 0, count: h)
        var puffer = [UInt8](repeating: 0, count: w * h * 4)
        puffer.withUnsafeMutableBytes { roh in
            guard let ctx = CGContext(data: roh.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: Bildbearbeitung.farbraum,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            ctx.draw(bild, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        let schritt = max(1, w / 400)
        for zeile in 0..<h {
            // Puffer ist von oben nach unten gespeichert (Zeile 0 = oben)
            let basis = zeile * w * 4
            var hash: UInt64 = 1469598103934665603
            var erster: UInt32?
            var einfarbig = true
            var x = 0
            while x < w {
                let i = basis + x * 4
                let wert = (UInt32(puffer[i] >> 3) << 10) | (UInt32(puffer[i + 1] >> 3) << 5) | UInt32(puffer[i + 2] >> 3)
                if let e = erster { if e != wert { einfarbig = false } } else { erster = wert }
                hash = (hash ^ UInt64(wert)) &* 1099511628211
                x += schritt
            }
            ergebnis[zeile] = einfarbig ? 0 : (hash == 0 ? 1 : hash)
        }
        return ergebnis
    }

    /// Um wie viele Zeilen wurde zwischen „alt“ und „neu“ nach unten gescrollt? nil = unklar
    static func versatz(alt: [UInt64], neu: [UInt64]) -> Int? {
        let h = min(alt.count, neu.count)
        guard h > 40 else { return nil }
        // Unverändert?
        if zaehle(alt, neu, dy: 0, h: h).anteil > 0.98 { return 0 }
        let minUeberlappung = h / 5
        var bester: (dy: Int, anteil: Double) = (0, 0)
        for dy in 1...(h - minUeberlappung) {
            let (anteil, gueltig) = zaehle(alt, neu, dy: dy, h: h)
            if gueltig >= 8 && anteil > bester.anteil {
                bester = (dy, anteil)
                if anteil > 0.995 { break }
            }
        }
        return bester.anteil >= 0.92 ? bester.dy : nil
    }

    /// Anteil gleicher Zeilen, wenn neu[i] == alt[i + dy]
    private static func zaehle(_ alt: [UInt64], _ neu: [UInt64], dy: Int, h: Int) -> (anteil: Double, gueltig: Int) {
        var gleich = 0, gueltig = 0
        var i = 0
        while i + dy < h {
            let a = alt[i + dy], b = neu[i]
            if a != 0 || b != 0 {
                gueltig += 1
                if a == b { gleich += 1 }
            }
            i += 2
        }
        return (gueltig == 0 ? 0 : Double(gleich) / Double(gueltig), gueltig)
    }
}

struct ScrollSteuerAnsicht: View {
    @ObservedObject var m: ScrollModell
    let fertig: () -> Void
    let abbrechen: () -> Void
    @AppStorage(Schluessel.darstellung) private var darstellung: Darstellung = .windows

    var body: some View {
        let stil = Stil(darstellung: darstellung)
        HStack(spacing: 12) {
            Image(systemName: "scroll").font(.system(size: 16)).foregroundStyle(stil.akzent)
            VStack(alignment: .leading, spacing: 2) {
                Text(m.hinweis).font(.system(size: 13, weight: .medium))
                Text(m.hoehe > 0 ? "\(m.breite) × \(m.hoehe) px" : "Bereich wird aufgenommen …")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Button("Abbrechen", action: abbrechen)
            Button("Fertig", action: fertig)
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: stil.istWindows ? 8 : 12).fill(stil.karte))
        .overlay(RoundedRectangle(cornerRadius: stil.istWindows ? 8 : 12).strokeBorder(stil.linie, lineWidth: 1))
    }
}
