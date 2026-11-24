import SwiftUI
import AppKit
import ScreenCaptureKit

// Farbpipette und Messen: auf einem eingefrorenen Bildschirmfoto Farbe abgreifen oder Abstände messen.

enum HilfsArt {
    case farbe, messen
}

@MainActor
final class HilfsModell: ObservableObject {
    let art: HilfsArt
    let bild: CGImage
    let faktor: CGFloat           // Pixel pro Punkt
    @Published var maus: CGPoint?
    @Published var start: CGPoint?
    @Published var ende: CGPoint?
    @Published var gemessen = false
    var fertig: (String) -> Void = { _ in }

    init(art: HilfsArt, bild: CGImage, faktor: CGFloat) {
        self.art = art
        self.bild = bild
        self.faktor = faktor
    }

    // MARK: Farbe

    func farbe(bei p: CGPoint) -> (hex: String, nsColor: NSColor)? {
        let x = Int(p.x * faktor), y = Int(p.y * faktor)
        guard x >= 0, y >= 0, x < bild.width, y < bild.height,
              let punkt = bild.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)) else { return nil }
        var px = [UInt8](repeating: 0, count: 4)
        px.withUnsafeMutableBytes { roh in
            guard let ctx = CGContext(data: roh.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: Bildbearbeitung.farbraum,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            ctx.draw(punkt, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        let hex = String(format: "#%02X%02X%02X", px[0], px[1], px[2])
        let farbe = NSColor(srgbRed: CGFloat(px[0]) / 255, green: CGFloat(px[1]) / 255, blue: CGFloat(px[2]) / 255, alpha: 1)
        return (hex, farbe)
    }

    /// 15×15 Pixel rund um die Maus für die Lupe
    func lupenBild(bei p: CGPoint) -> CGImage? {
        let x = Int(p.x * faktor) - 7, y = Int(p.y * faktor) - 7
        return bild.cropping(to: CGRect(x: x, y: y, width: 15, height: 15))
    }

    // MARK: Messen

    var messText: String? {
        guard let a = start, let b = ende else { return nil }
        let dx = abs(b.x - a.x) * faktor, dy = abs(b.y - a.y) * faktor
        let laenge = hypot(dx, dy)
        return "\(Int(laenge.rounded())) px   ·   \(Int(dx.rounded())) × \(Int(dy.rounded()))"
    }

    func gezogen(_ s: CGPoint, _ p: CGPoint) {
        guard art == .messen else { return }
        start = s
        // Mit ⇧ waagerecht/senkrecht
        if NSEvent.modifierFlags.contains(.shift) {
            ende = abs(p.x - s.x) > abs(p.y - s.y) ? CGPoint(x: p.x, y: s.y) : CGPoint(x: s.x, y: p.y)
        } else {
            ende = p
        }
        gemessen = false
    }

    func losgelassen(_ p: CGPoint) {
        switch art {
        case .farbe:
            if let f = farbe(bei: p) { fertig(f.hex) }
        case .messen:
            guard let a = start, let b = ende, hypot(b.x - a.x, b.y - a.y) > 2 else { return }
            gemessen = true
            let dx = abs(b.x - a.x) * faktor, dy = abs(b.y - a.y) * faktor
            let wert = "\(Int(hypot(dx, dy).rounded())) px"
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(wert, forType: .string)
        }
    }
}

struct HilfsAnsicht: View {
    @ObservedObject var m: HilfsModell

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(decorative: m.bild, scale: m.faktor)
                .resizable()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if m.art == .messen, let a = m.start, let b = m.ende {
                Canvas { ctx, _ in
                    var linie = Path()
                    linie.move(to: a)
                    linie.addLine(to: b)
                    ctx.stroke(linie, with: .color(Color.black.opacity(0.6)), lineWidth: 3)
                    ctx.stroke(linie, with: .color(Color.yellow), lineWidth: 1.5)
                    for p in [a, b] {
                        ctx.fill(Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)), with: .color(Color.yellow))
                    }
                }
                .allowsHitTesting(false)
                if let t = m.messText {
                    Text(m.gemessen ? t + "   ·   kopiert" : t)
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.black.opacity(0.75)))
                        .offset(x: (a.x + b.x) / 2 + 12, y: (a.y + b.y) / 2 + 12)
                        .allowsHitTesting(false)
                }
            }

            if m.art == .farbe, let p = m.maus, let f = m.farbe(bei: p) {
                VStack(spacing: 6) {
                    if let ausschnitt = m.lupenBild(bei: p) {
                        Image(decorative: ausschnitt, scale: 1)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: 105, height: 105)
                            .overlay(Rectangle().strokeBorder(Color.white, lineWidth: 1).frame(width: 8, height: 8))
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(Color.white, lineWidth: 3))
                            .shadow(radius: 4)
                    }
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 3).fill(Color(nsColor: f.nsColor))
                            .frame(width: 14, height: 14)
                            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.white.opacity(0.7), lineWidth: 1))
                        Text(f.hex).font(.system(size: 12, weight: .semibold, design: .monospaced))
                    }
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.black.opacity(0.75)))
                }
                .offset(x: p.x + 18, y: p.y + 18)
                .allowsHitTesting(false)
            }

            Text(m.art == .farbe ? "Klicken kopiert den Farbwert · esc beendet"
                                 : "Ziehen misst den Abstand (⇧ = gerade) · esc beendet")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.7)))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 40)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in m.gezogen(v.startLocation, v.location) }
                .onEnded { v in m.losgelassen(v.location) }
        )
    }
}

@MainActor
final class HilfsSteuerung {
    static let shared = HilfsSteuerung()

    private var eintraege: [(screen: NSScreen, fenster: AuswahlFenster, modell: HilfsModell)] = []
    private var timer: Timer?
    private var monitor: Any?

    func starte(_ art: HilfsArt) {
        guard eintraege.isEmpty else { return }
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else { return }
        Task {
            do {
                let inhalt = try await Bildschirm.inhalt()
                for screen in NSScreen.screens {
                    guard let d = Bildschirm.display(fuer: screen, in: inhalt) else { continue }
                    let bild = try await Bildschirm.aufnahmeDisplay(d, screen: screen, inhalt: inhalt)
                    let modell = HilfsModell(art: art, bild: bild, faktor: CGFloat(bild.width) / screen.frame.width)
                    modell.fertig = { [weak self] hex in self?.farbeGewaehlt(hex) }
                    let w = AuswahlFenster.erstelle(fuer: screen)
                    w.contentView = NSHostingView(rootView: HilfsAnsicht(m: modell))
                    w.orderFrontRegardless()
                    eintraege.append((screen: screen, fenster: w, modell: modell))
                }
                NSApp.activate()
                eintraege.first { $0.screen == Bildschirm.screenUnterMaus() }?.fenster.makeKey()
                timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.tick() }
                }
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
                    guard e.keyCode == 53 else { return e }
                    MainActor.assumeIsolated { self?.beende() }
                    return nil
                }
            } catch {
                beende()
                Meldung.fehler(error)
            }
        }
    }

    private func tick() {
        let p = NSEvent.mouseLocation
        for e in eintraege {
            let f = e.screen.frame
            if NSMouseInRect(p, f, false) {
                if !e.fenster.isKeyWindow { e.fenster.makeKey() }
                e.modell.maus = CGPoint(x: p.x - f.minX, y: f.maxY - p.y)
            } else if e.modell.maus != nil {
                e.modell.maus = nil
            }
        }
        NSCursor.crosshair.set()
    }

    private func farbeGewaehlt(_ hex: String) {
        beende()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(hex, forType: .string)
        Kurzhinweis.zeige("\(hex) in die Zwischenablage kopiert")
    }

    func beende() {
        timer?.invalidate()
        timer = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        for e in eintraege { e.fenster.orderOut(nil) }
        eintraege.removeAll()
        NSCursor.arrow.set()
    }
}

/// Kleine Meldung mittig unten, verschwindet von selbst
@MainActor
enum Kurzhinweis {
    private static var panel: SchwebePanel?

    static func zeige(_ text: String) {
        panel?.orderOut(nil)
        let p = SchwebePanel.erstelle()
        p.setzeInhalt(
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.8)))
        )
        let vf = Bildschirm.screenUnterMaus().visibleFrame
        p.setFrameOrigin(NSPoint(x: vf.midX - p.frame.width / 2, y: vf.minY + 80))
        p.orderFrontRegardless()
        panel = p
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            if panel === p {
                p.orderOut(nil)
                panel = nil
            }
        }
    }
}
