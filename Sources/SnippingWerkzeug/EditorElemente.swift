import AppKit
import CoreGraphics

// Alles, was man auf einen Ausschnitt zeichnen kann – und wie es gezeichnet wird.
// Koordinaten sind immer Bildpixel mit Ursprung oben links (y nach unten).

enum Werkzeug {
    case keins, stift, marker, radierer, form, text, nummer, verpixeln, zuschneiden
}

enum FormArt: String, CaseIterable, Identifiable {
    case pfeil, linie, rechteck, ellipse
    var id: String { rawValue }
    var name: String {
        switch self {
        case .pfeil: return "Pfeil"
        case .linie: return "Linie"
        case .rechteck: return "Rechteck"
        case .ellipse: return "Kreis / Ellipse"
        }
    }
    var symbol: String {
        switch self {
        case .pfeil: return "arrow.up.right"
        case .linie: return "line.diagonal"
        case .rechteck: return "rectangle"
        case .ellipse: return "circle"
        }
    }
}

enum Fuellung: String, CaseIterable, Identifiable {
    case keine, halb, voll
    var id: String { rawValue }
    var name: String {
        switch self {
        case .keine: return "Keine Füllung"
        case .halb: return "Halbtransparent"
        case .voll: return "Gefüllt"
        }
    }
}

enum VerpixelnArt: String, CaseIterable, Identifiable {
    case pixel, weich, balken
    var id: String { rawValue }
    var name: String {
        switch self {
        case .pixel: return "Verpixeln"
        case .weich: return "Weichzeichnen"
        case .balken: return "Schwarzer Balken"
        }
    }
    var symbol: String {
        switch self {
        case .pixel: return "square.grid.3x3.fill"
        case .weich: return "drop"
        case .balken: return "rectangle.fill"
        }
    }
}

struct Strich {
    let id = UUID()
    var punkte: [CGPoint]
    let farbe: Farbe
    let breite: CGFloat
    let marker: Bool

    var cgPfad: CGPath {
        let p = CGMutablePath()
        guard let erster = punkte.first else { return p }
        if punkte.count == 1 {
            p.move(to: erster)
            p.addLine(to: CGPoint(x: erster.x + 0.1, y: erster.y))
        } else {
            p.addLines(between: punkte)
        }
        return p
    }
}

struct Form {
    let id = UUID()
    var art: FormArt
    var start: CGPoint
    var ende: CGPoint
    var farbe: Farbe
    var breite: CGFloat
    var fuellung: Fuellung

    var rahmen: CGRect {
        CGRect(x: min(start.x, ende.x), y: min(start.y, ende.y),
               width: abs(ende.x - start.x), height: abs(ende.y - start.y))
    }
}

struct TextElement {
    let id = UUID()
    var position: CGPoint            // oben links
    var text: String
    var farbe: Farbe
    var groesse: CGFloat
    var hintergrund: Bool

    var schrift: NSFont { NSFont.systemFont(ofSize: groesse, weight: .semibold) }

    var attributiert: NSAttributedString {
        NSAttributedString(string: text.isEmpty ? " " : text,
                           attributes: [.font: schrift, .foregroundColor: farbe.nsColor])
    }

    var rand: CGFloat { groesse * 0.25 }

    var rahmen: CGRect {
        let g = attributiert.size()
        return CGRect(origin: position, size: g).insetBy(dx: -rand, dy: -rand)
    }
}

struct Nummer {
    let id = UUID()
    var mitte: CGPoint
    var zahl: Int
    var farbe: Farbe
    var radius: CGFloat
}

enum Element {
    case strich(Strich)
    case form(Form)
    case text(TextElement)
    case nummer(Nummer)

    var id: UUID {
        switch self {
        case .strich(let s): return s.id
        case .form(let f): return f.id
        case .text(let t): return t.id
        case .nummer(let n): return n.id
        }
    }

    /// Für den Radierer und zum Anklicken von Texten
    func trifft(_ p: CGPoint, radius r: CGFloat) -> Bool {
        switch self {
        case .strich(let s):
            return s.punkte.contains { hypot($0.x - p.x, $0.y - p.y) <= r + s.breite / 2 }
        case .form(let f):
            switch f.art {
            case .linie, .pfeil:
                return Geometrie.abstand(p, zuStrecke: f.start, f.ende) <= r + f.breite / 2 + 2
            case .rechteck, .ellipse:
                let aussen = f.rahmen.insetBy(dx: -(r + f.breite), dy: -(r + f.breite))
                guard aussen.contains(p) else { return false }
                if f.fuellung != .keine { return true }
                let innen = f.rahmen.insetBy(dx: r + f.breite, dy: r + f.breite)
                return innen.isNull || innen.isEmpty || !innen.contains(p)
            }
        case .text(let t):
            return t.rahmen.insetBy(dx: -r, dy: -r).contains(p)
        case .nummer(let n):
            return hypot(n.mitte.x - p.x, n.mitte.y - p.y) <= n.radius + r
        }
    }
}

enum Geometrie {
    static func abstand(_ p: CGPoint, zuStrecke a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let laenge2 = dx * dx + dy * dy
        guard laenge2 > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / laenge2))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    /// Mit ⇧: Linien in 45°-Schritten, Rechtecke/Kreise gleichmäßig
    static func eingeschraenkt(_ start: CGPoint, _ p: CGPoint, art: FormArt) -> CGPoint {
        guard NSEvent.modifierFlags.contains(.shift) else { return p }
        let dx = p.x - start.x, dy = p.y - start.y
        switch art {
        case .linie, .pfeil:
            let laenge = hypot(dx, dy)
            let schritt = CGFloat.pi / 4
            let winkel = (atan2(dy, dx) / schritt).rounded() * schritt
            return CGPoint(x: start.x + cos(winkel) * laenge, y: start.y + sin(winkel) * laenge)
        case .rechteck, .ellipse:
            let d = max(abs(dx), abs(dy))
            return CGPoint(x: start.x + (dx < 0 ? -d : d), y: start.y + (dy < 0 ? -d : d))
        }
    }
}

/// Zeichnet Elemente in einen CGContext, dessen y-Achse nach unten zeigt
/// (SwiftUI-Canvas oder das gespiegelte Export-Bild).
enum Zeichner {
    static func zeichne(_ e: Element, in cg: CGContext) {
        cg.saveGState()
        defer { cg.restoreGState() }
        switch e {
        case .strich(let s): zeichne(s, in: cg)
        case .form(let f): zeichne(f, in: cg)
        case .text(let t): zeichne(t, in: cg)
        case .nummer(let n): zeichne(n, in: cg)
        }
    }

    private static func zeichne(_ s: Strich, in cg: CGContext) {
        cg.setLineWidth(s.breite)
        cg.setLineJoin(.round)
        if s.marker {
            cg.setBlendMode(.multiply)
            cg.setLineCap(.square)
            cg.setStrokeColor(s.farbe.nsColor.withAlphaComponent(0.5).cgColor)
        } else {
            cg.setLineCap(.round)
            cg.setStrokeColor(s.farbe.nsColor.cgColor)
        }
        cg.addPath(s.cgPfad)
        cg.strokePath()
    }

    private static func zeichne(_ f: Form, in cg: CGContext) {
        let farbe = f.farbe.nsColor
        cg.setStrokeColor(farbe.cgColor)
        cg.setFillColor(farbe.cgColor)
        cg.setLineWidth(f.breite)
        cg.setLineCap(.round)
        cg.setLineJoin(.round)

        switch f.art {
        case .linie:
            cg.move(to: f.start)
            cg.addLine(to: f.ende)
            cg.strokePath()

        case .pfeil:
            let dx = f.ende.x - f.start.x, dy = f.ende.y - f.start.y
            let laenge = hypot(dx, dy)
            guard laenge > 1 else { return }
            let ux = dx / laenge, uy = dy / laenge
            let kopf = min(max(f.breite * 4, 14), laenge * 0.6)
            let basis = CGPoint(x: f.ende.x - ux * kopf * 0.85, y: f.ende.y - uy * kopf * 0.85)
            cg.move(to: f.start)
            cg.addLine(to: basis)
            cg.strokePath()
            // Pfeilspitze
            let quer = kopf * 0.55
            cg.move(to: f.ende)
            cg.addLine(to: CGPoint(x: f.ende.x - ux * kopf - uy * quer, y: f.ende.y - uy * kopf + ux * quer))
            cg.addLine(to: CGPoint(x: f.ende.x - ux * kopf + uy * quer, y: f.ende.y - uy * kopf - ux * quer))
            cg.closePath()
            cg.fillPath()

        case .rechteck, .ellipse:
            let r = f.rahmen
            let pfad = CGMutablePath()
            if f.art == .rechteck {
                pfad.addRoundedRect(in: r, cornerWidth: min(4, r.width / 2), cornerHeight: min(4, r.height / 2))
            } else {
                pfad.addEllipse(in: r)
            }
            if f.fuellung != .keine {
                cg.setFillColor(farbe.withAlphaComponent(f.fuellung == .halb ? 0.3 : 1).cgColor)
                cg.addPath(pfad)
                cg.fillPath()
            }
            cg.addPath(pfad)
            cg.strokePath()
        }
    }

    private static func zeichne(_ t: TextElement, in cg: CGContext) {
        if t.hintergrund {
            let pfad = CGPath(roundedRect: t.rahmen, cornerWidth: t.rand, cornerHeight: t.rand, transform: nil)
            cg.setFillColor(NSColor.white.withAlphaComponent(0.92).cgColor)
            cg.addPath(pfad)
            cg.fillPath()
        }
        mitNSKontext(cg) {
            t.attributiert.draw(at: t.position)
        }
    }

    private static func zeichne(_ n: Nummer, in cg: CGContext) {
        let r = CGRect(x: n.mitte.x - n.radius, y: n.mitte.y - n.radius, width: n.radius * 2, height: n.radius * 2)
        cg.setFillColor(n.farbe.nsColor.cgColor)
        cg.fillEllipse(in: r)
        cg.setStrokeColor(NSColor.white.cgColor)
        cg.setLineWidth(max(1.5, n.radius * 0.12))
        cg.strokeEllipse(in: r.insetBy(dx: n.radius * 0.06, dy: n.radius * 0.06))

        let schriftfarbe: NSColor = (n.farbe == .weiss || n.farbe == .gelb) ? .black : .white
        let text = NSAttributedString(string: "\(n.zahl)", attributes: [
            .font: NSFont.systemFont(ofSize: n.radius * 1.15, weight: .bold),
            .foregroundColor: schriftfarbe,
        ])
        let g = text.size()
        mitNSKontext(cg) {
            text.draw(at: CGPoint(x: n.mitte.x - g.width / 2, y: n.mitte.y - g.height / 2))
        }
    }

    /// AppKit-Textzeichnung braucht einen aktuellen NSGraphicsContext (gespiegelt, weil y nach unten zeigt).
    private static func mitNSKontext(_ cg: CGContext, _ f: () -> Void) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
        f()
        NSGraphicsContext.restoreGraphicsState()
    }
}
