import SwiftUI
import AppKit
import ScreenCaptureKit

enum AuswahlErgebnis {
    case rechteck(CGRect)       // Punkte, lokal zum Bildschirm, Ursprung oben links
    case freiform([CGPoint])
    case fenster(SCWindow)
}

@MainActor
final class AuswahlModell: ObservableObject {
    let modus: Modus
    let bild: CGImage?
    let fenster: [(fenster: SCWindow, rahmen: CGRect)]
    let pixelFaktor: CGFloat
    let abdunkeln: Double

    @Published var start: CGPoint?
    @Published var ende: CGPoint?
    @Published var punkte: [CGPoint] = []
    @Published var hoverIndex: Int?

    var fertig: (AuswahlErgebnis) -> Void = { _ in }

    init(modus: Modus, bild: CGImage?, fenster: [(fenster: SCWindow, rahmen: CGRect)],
         pixelFaktor: CGFloat, abdunkeln: Double) {
        self.modus = modus
        self.bild = bild
        self.fenster = fenster
        self.pixelFaktor = pixelFaktor
        self.abdunkeln = abdunkeln
    }

    var rechteck: CGRect? {
        guard let s = start, let e = ende else { return nil }
        return CGRect(x: min(s.x, e.x), y: min(s.y, e.y), width: abs(e.x - s.x), height: abs(e.y - s.y))
    }

    var loch: Path? {
        switch modus {
        case .rechteck, .scroll:
            guard let r = rechteck else { return nil }
            return Path(r)
        case .freiform:
            guard punkte.count > 1 else { return nil }
            var p = Path()
            p.addLines(punkte)
            return p
        case .fenster:
            guard let i = hoverIndex else { return nil }
            return Path(fenster[i].rahmen)
        case .vollbild:
            return nil
        }
    }

    func hover(_ p: CGPoint) {
        guard modus == .fenster else { return }
        let neu = fenster.firstIndex { $0.rahmen.contains(p) }
        if neu != hoverIndex { hoverIndex = neu }
    }

    func gezogen(start s: CGPoint, aktuell p: CGPoint) {
        switch modus {
        case .rechteck, .scroll:
            start = s
            ende = p
        case .freiform:
            if punkte.isEmpty { punkte.append(s) }
            if let letzter = punkte.last, hypot(letzter.x - p.x, letzter.y - p.y) > 1.5 {
                punkte.append(p)
            }
        case .fenster, .vollbild:
            hover(p)
        }
    }

    func losgelassen(bei p: CGPoint) {
        switch modus {
        case .rechteck, .scroll:
            if let r = rechteck, r.width >= 4, r.height >= 4 {
                fertig(.rechteck(r))
            } else {
                start = nil
                ende = nil
            }
        case .freiform:
            if punkte.count > 5 {
                fertig(.freiform(punkte))
            } else {
                punkte = []
            }
        case .fenster:
            hover(p)
            if let i = hoverIndex { fertig(.fenster(fenster[i].fenster)) }
        case .vollbild:
            break
        }
    }
}

struct AuswahlAnsicht: View {
    @ObservedObject var m: AuswahlModell

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Fast unsichtbare Fläche, damit alle Klicks im Fenster landen
            Color.black.opacity(0.001)

            if let bild = m.bild {
                Image(decorative: bild, scale: m.pixelFaktor)
                    .resizable()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Canvas { ctx, size in
                var pfad = Path(CGRect(origin: .zero, size: size))
                if let loch = m.loch { pfad.addPath(loch) }
                ctx.fill(pfad, with: .color(Color.black.opacity(m.abdunkeln)), style: FillStyle(eoFill: true))
                if let loch = m.loch {
                    ctx.stroke(loch, with: .color(Color.white), lineWidth: 1.5)
                }
            }
            .allowsHitTesting(false)

            if m.modus == .rechteck || m.modus == .scroll, let r = m.rechteck, r.width > 4 {
                Text("\(Int(r.width * m.pixelFaktor)) × \(Int(r.height * m.pixelFaktor))")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.7)))
                    .offset(x: r.minX, y: max(4, r.minY - 26))
                    .allowsHitTesting(false)
            }

            if m.modus == .fenster, let i = m.hoverIndex {
                let r = m.fenster[i].rahmen
                Text(m.fenster[i].fenster.owningApplication?.applicationName ?? "Fenster")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.black.opacity(0.7)))
                    .offset(x: max(4, r.minX + 8), y: max(4, r.minY + 8))
                    .allowsHitTesting(false)
            }

            if m.modus == .vollbild {
                Text("Klicke, um diesen Bildschirm aufzunehmen")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.white)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.6)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in m.gezogen(start: v.startLocation, aktuell: v.location) }
                .onEnded { v in m.losgelassen(bei: v.location) }
        )
    }
}

final class AuswahlFenster: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    static func erstelle(fuer screen: NSScreen) -> AuswahlFenster {
        let w = AuswahlFenster(contentRect: screen.frame, styleMask: [.borderless],
                               backing: .buffered, defer: false)
        w.setFrame(screen.frame, display: false)
        w.level = .screenSaver
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.isReleasedWhenClosed = false
        w.ignoresMouseEvents = false
        w.acceptsMouseMovedEvents = true
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return w
    }
}
