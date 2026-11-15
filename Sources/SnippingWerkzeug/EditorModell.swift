import SwiftUI
import AppKit

/// Lineal wie im Windows-Snipping-Tool: verschieben, mit dem Mausrad drehen, Stift zieht gerade Linien daran.
struct Lineal {
    var mitte: CGPoint
    var winkel: CGFloat = 0          // Bogenmaß
    var laenge: CGFloat
    var breite: CGFloat

    var richtung: CGPoint { CGPoint(x: cos(winkel), y: sin(winkel)) }
    var normale: CGPoint { CGPoint(x: -sin(winkel), y: cos(winkel)) }

    /// t = entlang des Lineals, n = quer dazu
    func lokal(_ p: CGPoint) -> (t: CGFloat, n: CGFloat) {
        let dx = p.x - mitte.x, dy = p.y - mitte.y
        return (dx * richtung.x + dy * richtung.y, dx * normale.x + dy * normale.y)
    }

    func punkt(t: CGFloat, n: CGFloat) -> CGPoint {
        CGPoint(x: mitte.x + richtung.x * t + normale.x * n,
                y: mitte.y + richtung.y * t + normale.y * n)
    }

    var grad: Int {
        let g = Int((winkel * 180 / .pi).rounded()) % 360
        return g < 0 ? g + 360 : g
    }
}

private enum Geste {
    case nichts, zeichnen, form, verpixeln, lineal(versatz: CGPoint), radieren, zuschneiden
}

@MainActor
final class EditorModell: ObservableObject {
    private struct Schnappschuss {
        let bild: CGImage
        let elemente: [Element]
    }

    @Published private(set) var bild: CGImage
    @Published private(set) var elemente: [Element] = []
    @Published var aktuell: Element?
    @Published var werkzeug: Werkzeug = .keins

    // Einstellungen der Werkzeuge
    @Published var stiftFarbe: Farbe = .rot
    @Published var stiftBreite: CGFloat = 6
    @Published var markerFarbe: Farbe = .gelb
    @Published var markerBreite: CGFloat = 28
    @Published var formArt: FormArt = .pfeil
    @Published var formFarbe: Farbe = .rot
    @Published var formBreite: CGFloat = 6
    @Published var fuellung: Fuellung = .keine
    @Published var textFarbe: Farbe = .rot
    @Published var textGroesse: CGFloat = 36
    @Published var textHintergrund = false
    @Published var nummerFarbe: Farbe = .rot
    @Published var verpixelnArt: VerpixelnArt = .pixel

    @Published var zuschnitt: CGRect?
    @Published var verpixelnRahmen: CGRect?
    @Published var lineal: Lineal?
    @Published var bearbeiteterText: UUID?

    // Textaktionen
    @Published var zeigeText = false
    @Published var erkannterText = ""
    @Published var erkannteCodes: [String] = []
    @Published var erkenntGerade = false

    // Automatisch schwärzen
    @Published var zeigeSchwaerzen = false
    @Published var schwaerzFunde: [SchwaerzFund] = []
    @Published var schwaerzAuswahl: Set<UUID> = []

    private var geste: Geste?
    private var kante: CGFloat?      // Abstand der Linealkante, an der gerade gezeichnet wird
    private var undoStapel: [Schnappschuss] = []
    private var redoStapel: [Schnappschuss] = []
    private var radiererAktiv = false

    init(bild: CGImage) {
        self.bild = bild
    }

    var groesse: CGSize { CGSize(width: bild.width, height: bild.height) }
    var kannRueckgaengig: Bool { !undoStapel.isEmpty }
    var kannWiederholen: Bool { !redoStapel.isEmpty }

    // MARK: Werkzeugwahl

    func waehle(_ w: Werkzeug) {
        beendeTextBearbeitung()
        verpixelnRahmen = nil
        if w == .zuschneiden {
            zuschnitt = CGRect(origin: .zero, size: groesse)
            werkzeug = .zuschneiden
            return
        }
        zuschnitt = nil
        werkzeug = (werkzeug == w) ? .keins : w
    }

    // MARK: Maus auf der Zeichenfläche (Bildpixel)

    func zeigerBewegt(start: CGPoint, aktuell p: CGPoint, radiererRadius: CGFloat) {
        if geste == nil { beginneGeste(start) }
        switch geste {
        case .zeichnen:
            if aktuell == nil { beginneStrich(start) }
            erweitereStrich(p)
        case .form:
            if case .form(var f) = aktuell {
                f.ende = Geometrie.eingeschraenkt(f.start, p, art: f.art)
                aktuell = .form(f)
            }
        case .verpixeln:
            verpixelnRahmen = Self.rechteck(start, p).intersection(CGRect(origin: .zero, size: groesse))
        case .lineal(let v):
            lineal?.mitte = CGPoint(x: p.x + v.x, y: p.y + v.y)
        case .radieren:
            radiere(p, radius: radiererRadius)
        case .zuschneiden:
            setzeZuschnitt(Self.rechteck(start, p))
        case .nichts, .none:
            break
        }
    }

    func zeigerLos() {
        switch geste {
        case .zeichnen:
            beendeStrich()
        case .form:
            if case .form(let f) = aktuell, hypot(f.ende.x - f.start.x, f.ende.y - f.start.y) > 4 {
                merkeUndo()
                elemente.append(.form(f))
            }
            aktuell = nil
        case .verpixeln:
            if let r = verpixelnRahmen?.integral, !r.isNull, r.width >= 4, r.height >= 4,
               let neu = Bildbearbeitung.verpixle(bild, rahmen: r, art: verpixelnArt) {
                merkeUndo()
                bild = neu
            }
            verpixelnRahmen = nil
        case .radieren:
            radiererAktiv = false
        case .zuschneiden:
            if let z = zuschnitt, z.width >= 4, z.height >= 4 { break }
            setzeZuschnitt(CGRect(origin: .zero, size: groesse))
        default:
            break
        }
        geste = nil
        kante = nil
    }

    private func beginneGeste(_ start: CGPoint) {
        // Ein Klick außerhalb beendet eine laufende Texteingabe
        let warAmSchreiben = bearbeiteterText != nil
        beendeTextBearbeitung()

        // Doppelklick auf einen Text bearbeitet ihn – mit jedem Werkzeug
        if (NSApp.currentEvent?.clickCount ?? 1) >= 2, let t = textBei(start) {
            starteTextBearbeitung(t)
            geste = .nichts
            return
        }
        if werkzeug == .zuschneiden {
            geste = .zuschneiden
            return
        }
        if let l = lineal {
            let lo = l.lokal(start)
            if abs(lo.t) <= l.laenge / 2 && abs(lo.n) < l.breite / 2 - 8 {
                geste = .lineal(versatz: CGPoint(x: l.mitte.x - start.x, y: l.mitte.y - start.y))
                return
            }
        }
        switch werkzeug {
        case .stift, .marker:
            geste = .zeichnen
        case .radierer:
            geste = .radieren
        case .form:
            aktuell = .form(Form(art: formArt, start: start, ende: start, farbe: formFarbe,
                                 breite: formBreite, fuellung: fuellung))
            geste = .form
        case .verpixeln:
            geste = .verpixeln
        case .text:
            if let t = textBei(start) {
                starteTextBearbeitung(t)
            } else if !warAmSchreiben {
                neuerText(bei: start)
            }
            geste = .nichts
        case .nummer:
            setzeNummer(bei: start)
            geste = .nichts
        default:
            geste = .nichts
        }
    }

    private static func rechteck(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    // MARK: Stift und Textmarker

    private func beginneStrich(_ p: CGPoint) {
        let istMarker = werkzeug == .marker
        let breite = istMarker ? markerBreite : stiftBreite
        kante = nil
        if let l = lineal {
            let lo = l.lokal(p)
            if abs(lo.t) <= l.laenge / 2 + 20 && abs(lo.n) <= l.breite / 2 + 28 {
                let seite: CGFloat = lo.n < 0 ? -1 : 1
                kante = seite * (l.breite / 2 + breite / 2)
            }
        }
        aktuell = .strich(Strich(punkte: [anLineal(p)],
                                 farbe: istMarker ? markerFarbe : stiftFarbe,
                                 breite: breite,
                                 marker: istMarker))
    }

    private func erweitereStrich(_ p: CGPoint) {
        guard case .strich(var s) = aktuell else { return }
        if kante != nil, let erster = s.punkte.first {
            s.punkte = [erster, anLineal(p)]       // gerade Linie entlang der Kante
        } else {
            s.punkte.append(p)
        }
        aktuell = .strich(s)
    }

    private func beendeStrich() {
        guard let a = aktuell else { return }
        merkeUndo()
        elemente.append(a)
        aktuell = nil
    }

    private func anLineal(_ p: CGPoint) -> CGPoint {
        guard let k = kante, let l = lineal else { return p }
        return l.punkt(t: l.lokal(p).t, n: k)
    }

    // MARK: Radierer

    private func radiere(_ p: CGPoint, radius: CGFloat) {
        let treffer = Set(elemente.filter { $0.trifft(p, radius: radius) }.map(\.id))
        guard !treffer.isEmpty else { return }
        if !radiererAktiv {
            merkeUndo()
            radiererAktiv = true
        }
        elemente.removeAll { treffer.contains($0.id) }
    }

    // MARK: Nummerierte Marker

    private func setzeNummer(bei p: CGPoint) {
        let hoechste = elemente.compactMap { e -> Int? in
            if case .nummer(let n) = e { return n.zahl }
            return nil
        }.max() ?? 0
        let radius = min(max(min(groesse.width, groesse.height) * 0.03, 16), 40)
        merkeUndo()
        elemente.append(.nummer(Nummer(mitte: p, zahl: hoechste + 1, farbe: nummerFarbe, radius: radius)))
    }

    // MARK: Text

    private func textBei(_ p: CGPoint) -> TextElement? {
        for e in elemente.reversed() {
            if case .text(let t) = e, t.rahmen.contains(p) { return t }
        }
        return nil
    }

    private func neuerText(bei p: CGPoint) {
        merkeUndo()
        let t = TextElement(position: CGPoint(x: p.x, y: p.y - textGroesse * 0.6), text: "",
                            farbe: textFarbe, groesse: textGroesse, hintergrund: textHintergrund)
        elemente.append(.text(t))
        bearbeiteterText = t.id
    }

    private func starteTextBearbeitung(_ t: TextElement) {
        merkeUndo()
        bearbeiteterText = t.id
    }

    func textElement(_ id: UUID) -> TextElement? {
        for e in elemente {
            if case .text(let t) = e, t.id == id { return t }
        }
        return nil
    }

    func setzeTextInhalt(_ id: UUID, _ inhalt: String) {
        guard let i = elemente.firstIndex(where: { $0.id == id }), case .text(var t) = elemente[i] else { return }
        t.text = inhalt
        elemente[i] = .text(t)
    }

    func beendeTextBearbeitung() {
        guard let id = bearbeiteterText else { return }
        bearbeiteterText = nil
        if let t = textElement(id), t.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            elemente.removeAll { $0.id == id }
            // leeren Rückgängig-Schritt wieder entfernen
            if !undoStapel.isEmpty { undoStapel.removeLast() }
        }
    }

    // MARK: Lineal

    func schalteLineal() {
        if lineal != nil {
            lineal = nil
            return
        }
        let w = groesse.width, h = groesse.height
        lineal = Lineal(mitte: CGPoint(x: w / 2, y: h / 2),
                        laenge: max(w, h) * 1.2,
                        breite: min(max(min(w, h) * 0.14, 70), 160))
    }

    func dreheLineal(um grad: CGFloat) {
        guard var l = lineal else { return }
        var g = l.winkel * 180 / .pi + grad
        let naechste = (g / 45).rounded() * 45
        if abs(g - naechste) < 0.8 { g = naechste }
        l.winkel = g * .pi / 180
        lineal = l
    }

    // MARK: Zuschneiden

    func setzeZuschnitt(_ r: CGRect) {
        let begrenzt = r.standardized.intersection(CGRect(origin: .zero, size: groesse))
        zuschnitt = begrenzt.isNull ? nil : begrenzt
    }

    func zuschneidenAnwenden() {
        let voll = CGRect(origin: .zero, size: groesse)
        guard let r = zuschnitt?.integral, r.width >= 2, r.height >= 2, r != voll else {
            zuschneidenAbbrechen()
            return
        }
        merkeUndo()
        if let neu = gerendert().cropping(to: r) {
            bild = neu
            elemente = []
        }
        zuschnitt = nil
        werkzeug = .keins
    }

    func zuschneidenAbbrechen() {
        zuschnitt = nil
        werkzeug = .keins
    }

    /// Ersetzt das Grundbild (z. B. nach dem Schwärzen) – mit Rückgängig-Schritt
    func ersetzeBild(_ neu: CGImage) {
        merkeUndo()
        bild = neu
    }

    // MARK: Rückgängig

    private func merkeUndo() {
        undoStapel.append(Schnappschuss(bild: bild, elemente: elemente))
        if undoStapel.count > 50 { undoStapel.removeFirst() }
        redoStapel.removeAll()
    }

    func rueckgaengig() {
        beendeTextBearbeitung()
        guard let z = undoStapel.popLast() else { return }
        redoStapel.append(Schnappschuss(bild: bild, elemente: elemente))
        bild = z.bild
        elemente = z.elemente
    }

    func wiederholen() {
        beendeTextBearbeitung()
        guard let z = redoStapel.popLast() else { return }
        undoStapel.append(Schnappschuss(bild: bild, elemente: elemente))
        bild = z.bild
        elemente = z.elemente
    }

    // MARK: Ausgabe

    /// Bild mit allen Zeichnungen zusammengeführt.
    func gerendert() -> CGImage {
        beendeTextBearbeitung()
        guard !elemente.isEmpty else { return bild }
        let w = bild.width, h = bild.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: Bildbearbeitung.farbraum,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return bild }
        ctx.draw(bild, in: CGRect(x: 0, y: 0, width: w, height: h))
        // Elemente sind oben-links-basiert → Koordinaten spiegeln
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        for e in elemente { Zeichner.zeichne(e, in: ctx) }
        return ctx.makeImage() ?? bild
    }

    func erkenneText() async {
        erkenntGerade = true
        let quelle = gerendert()
        let text = await Texterkennung.erkenne(quelle)
        let codes = await Texterkennung.codes(quelle)
        erkenntGerade = false
        erkannterText = text.isEmpty ? "Im Ausschnitt wurde kein Text gefunden." : text
        erkannteCodes = codes
        zeigeText = true
    }
}
