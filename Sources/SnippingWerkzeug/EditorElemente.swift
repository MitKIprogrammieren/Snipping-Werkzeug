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

enum Schriftart: String, CaseIterable, Identifiable {
    case system, gerundet, serif, mono, handschrift, filzstift, kreide, comic, plakativ
    var id: String { rawValue }

    var name: String {
        switch self {
        case .system: return "System"
        case .gerundet: return "Gerundet"
        case .serif: return "Serif"
        case .mono: return "Schreibmaschine"
        case .handschrift: return "Handschrift"
        case .filzstift: return "Filzstift"
        case .kreide: return "Kreide"
        case .comic: return "Comic"
        case .plakativ: return "Plakativ"
        }
    }

    func schrift(_ groesse: CGFloat, fett: Bool = true) -> NSFont {
        let gewicht: NSFont.Weight = fett ? .bold : .semibold
        let basis = NSFont.systemFont(ofSize: groesse, weight: gewicht)
        func design(_ d: NSFontDescriptor.SystemDesign) -> NSFont {
            guard let desc = basis.fontDescriptor.withDesign(d) else { return basis }
            return NSFont(descriptor: desc, size: groesse) ?? basis
        }
        switch self {
        case .system: return basis
        case .gerundet: return design(.rounded)
        case .serif: return design(.serif)
        case .mono: return NSFont.monospacedSystemFont(ofSize: groesse, weight: gewicht)
        case .handschrift: return NSFont(name: "Noteworthy-Bold", size: groesse) ?? basis
        case .filzstift: return NSFont(name: "MarkerFelt-Wide", size: groesse) ?? basis
        case .kreide: return NSFont(name: "ChalkboardSE-Bold", size: groesse) ?? basis
        case .comic: return NSFont(name: "ComicSansMS-Bold", size: groesse) ?? basis
        case .plakativ: return NSFont(name: "Impact", size: groesse) ?? basis
        }
    }

    /// Beliebige installierte Schriftfamilie
    static func familie(_ name: String, _ groesse: CGFloat, fett: Bool) -> NSFont? {
        NSFontManager.shared.font(withFamily: name, traits: fett ? .boldFontMask : [], weight: 5, size: groesse)
            ?? NSFontManager.shared.font(withFamily: name, traits: [], weight: 5, size: groesse)
    }

    static var alleFamilien: [String] {
        NSFontManager.shared.availableFontFamilies
            .filter { !$0.hasPrefix(".") }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}

enum MarkerForm: String, CaseIterable, Identifiable {
    case kreis, ring, quadrat, nadel, blase, etikett
    var id: String { rawValue }
    var name: String {
        switch self {
        case .kreis: return "Kreis gefüllt"
        case .ring: return "Kreis umrandet"
        case .quadrat: return "Quadrat"
        case .nadel: return "Stecknadel"
        case .blase: return "Sprechblase"
        case .etikett: return "Etikett „Schritt 1“"
        }
    }
    var symbol: String {
        switch self {
        case .kreis: return "1.circle.fill"
        case .ring: return "1.circle"
        case .quadrat: return "1.square.fill"
        case .nadel: return "mappin"
        case .blase: return "bubble.left.fill"
        case .etikett: return "tag.fill"
        }
    }
}

enum Zaehlweise: String, CaseIterable, Identifiable {
    case zahlen, gross, klein, roemisch
    var id: String { rawValue }
    var name: String {
        switch self {
        case .zahlen: return "1, 2, 3"
        case .gross: return "A, B, C"
        case .klein: return "a, b, c"
        case .roemisch: return "I, II, III"
        }
    }

    func text(_ n: Int) -> String {
        switch self {
        case .zahlen: return "\(n)"
        case .gross: return Self.buchstaben(n)
        case .klein: return Self.buchstaben(n).lowercased()
        case .roemisch: return Self.roemisch(n)
        }
    }

    private static func buchstaben(_ n: Int) -> String {
        var n = max(1, n)
        var s = ""
        while n > 0 {
            n -= 1
            s = String(UnicodeScalar(UInt8(65 + n % 26))) + s
            n /= 26
        }
        return s
    }

    private static func roemisch(_ n: Int) -> String {
        let werte: [(Int, String)] = [(1000, "M"), (900, "CM"), (500, "D"), (400, "CD"), (100, "C"), (90, "XC"),
                                      (50, "L"), (40, "XL"), (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")]
        var rest = max(1, min(n, 3999))
        var s = ""
        for (wert, zeichen) in werte {
            while rest >= wert {
                s += zeichen
                rest -= wert
            }
        }
        return s
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

struct FormElement {
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
    var schriftart: Schriftart = .system
    var familie: String? = nil

    var schrift: NSFont {
        familie.flatMap { Schriftart.familie($0, groesse, fett: false) } ?? schriftart.schrift(groesse, fett: false)
    }

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
    var form: MarkerForm = .kreis
    var zaehlweise: Zaehlweise = .zahlen
    var schriftart: Schriftart = .system
    var familie: String? = nil
    /// Optionaler Pfeil vom Marker zu einer Stelle
    var pfeilZiel: CGPoint?

    var beschriftung: String {
        let t = zaehlweise.text(zahl)
        return form == .etikett ? "Schritt \(t)" : t
    }

    func schrift(_ groesse: CGFloat) -> NSFont {
        familie.flatMap { Schriftart.familie($0, groesse, fett: true) } ?? schriftart.schrift(groesse)
    }

    /// Mittelpunkt der eigentlichen Marke (bei der Stecknadel oberhalb der Spitze)
    var kopf: CGPoint {
        form == .nadel ? CGPoint(x: mitte.x, y: mitte.y - radius * 1.9) : mitte
    }
}

enum Element {
    case strich(Strich)
    case form(FormElement)
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
            if hypot(n.kopf.x - p.x, n.kopf.y - p.y) <= n.radius * (n.form == .etikett ? 2.5 : 1.3) + r { return true }
            if let ziel = n.pfeilZiel, Geometrie.abstand(p, zuStrecke: n.kopf, ziel) <= n.radius * 0.3 + r { return true }
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

    private static func zeichne(_ f: FormElement, in cg: CGContext) {
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
        let farbe = n.farbe.nsColor
        let r = n.radius
        let k = n.kopf
        let hell = n.farbe == .weiss || n.farbe == .gelb
        var schriftfarbe: NSColor = hell ? .black : .white
        let text = n.beschriftung
        let schriftgroesse = r * (text.count >= 3 && n.form != .etikett ? 0.8 : (text.count == 2 ? 0.95 : 1.15))

        // Pfeil vom Marker zur Stelle (unter dem Marker)
        if let ziel = n.pfeilZiel {
            let pfeil = FormElement(art: .pfeil, start: k, ende: ziel, farbe: n.farbe, breite: max(3, r * 0.22), fuellung: .keine)
            zeichne(pfeil, in: cg)
        }

        cg.setFillColor(farbe.cgColor)
        cg.setStrokeColor(NSColor.white.cgColor)

        switch n.form {
        case .kreis:
            let rahmen = CGRect(x: k.x - r, y: k.y - r, width: r * 2, height: r * 2)
            cg.fillEllipse(in: rahmen)
            cg.setLineWidth(max(1.5, r * 0.12))
            cg.strokeEllipse(in: rahmen.insetBy(dx: r * 0.06, dy: r * 0.06))

        case .ring:
            let rahmen = CGRect(x: k.x - r, y: k.y - r, width: r * 2, height: r * 2)
            let dicke = max(2, r * 0.2)
            cg.setFillColor(NSColor.white.cgColor)
            cg.fillEllipse(in: rahmen)
            cg.setStrokeColor(farbe.cgColor)
            cg.setLineWidth(dicke)
            cg.strokeEllipse(in: rahmen.insetBy(dx: dicke / 2, dy: dicke / 2))
            schriftfarbe = hell ? .black : farbe

        case .quadrat:
            let rahmen = CGRect(x: k.x - r, y: k.y - r, width: r * 2, height: r * 2)
            cg.addPath(CGPath(roundedRect: rahmen, cornerWidth: r * 0.35, cornerHeight: r * 0.35, transform: nil))
            cg.fillPath()

        case .nadel:
            // Tropfenform: Kreis um den Kopf, Spitze genau auf dem Klickpunkt
            let abstand = r * 1.9
            let phi = acos(r / abstand)
            let start = CGFloat.pi / 2 + phi
            let bogen = 2 * CGFloat.pi - 2 * phi
            let pfad = CGMutablePath()
            pfad.move(to: n.mitte)
            for i in 0...48 {
                let w = start + bogen * CGFloat(i) / 48
                pfad.addLine(to: CGPoint(x: k.x + cos(w) * r, y: k.y + sin(w) * r))
            }
            pfad.closeSubpath()
            cg.addPath(pfad)
            cg.fillPath()
            cg.setFillColor(NSColor.white.cgColor)
            cg.fillEllipse(in: CGRect(x: k.x - r * 0.72, y: k.y - r * 0.72, width: r * 1.44, height: r * 1.44))
            schriftfarbe = hell ? .black : farbe

        case .blase:
            let g = attributiert(text, n, schriftgroesse, schriftfarbe).size()
            let breite = max(r * 2, g.width + r)
            let rahmen = CGRect(x: k.x - breite / 2, y: k.y - r * 0.9, width: breite, height: r * 1.8)
            cg.addPath(CGPath(roundedRect: rahmen, cornerWidth: r * 0.35, cornerHeight: r * 0.35, transform: nil))
            cg.fillPath()
            cg.move(to: CGPoint(x: rahmen.minX + r * 0.5, y: rahmen.maxY - 1))
            cg.addLine(to: CGPoint(x: rahmen.minX + r * 0.3, y: rahmen.maxY + r * 0.7))
            cg.addLine(to: CGPoint(x: rahmen.minX + r * 1.1, y: rahmen.maxY - 1))
            cg.closePath()
            cg.fillPath()

        case .etikett:
            let g = attributiert(text, n, schriftgroesse * 0.85, schriftfarbe).size()
            let rahmen = CGRect(x: k.x - (g.width + r * 1.2) / 2, y: k.y - r * 0.8,
                                width: g.width + r * 1.2, height: r * 1.6)
            cg.addPath(CGPath(roundedRect: rahmen, cornerWidth: r * 0.8, cornerHeight: r * 0.8, transform: nil))
            cg.fillPath()
        }

        let groesse = n.form == .etikett ? schriftgroesse * 0.85 : schriftgroesse
        let beschriftet = attributiert(text, n, groesse, schriftfarbe)
        let g = beschriftet.size()
        mitNSKontext(cg) {
            beschriftet.draw(at: CGPoint(x: k.x - g.width / 2, y: k.y - g.height / 2))
        }
    }

    private static func attributiert(_ text: String, _ n: Nummer, _ groesse: CGFloat, _ farbe: NSColor) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: n.schrift(groesse), .foregroundColor: farbe])
    }

    /// AppKit-Textzeichnung braucht einen aktuellen NSGraphicsContext (gespiegelt, weil y nach unten zeigt).
    private static func mitNSKontext(_ cg: CGContext, _ f: () -> Void) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
        f()
        NSGraphicsContext.restoreGraphicsState()
    }
}
