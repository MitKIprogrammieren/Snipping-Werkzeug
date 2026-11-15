import SwiftUI
import AppKit

enum Werkzeug {
    case keins, stift, marker, radierer, zuschneiden
}

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
    case nichts, zeichnen, lineal(versatz: CGPoint), radieren, zuschneiden
}

struct Strich: Identifiable {
    let id = UUID()
    var punkte: [CGPoint]          // Bildpixel, Ursprung oben links
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

@MainActor
final class EditorModell: ObservableObject {
    private struct Schnappschuss {
        let bild: CGImage
        let striche: [Strich]
    }

    @Published private(set) var bild: CGImage
    @Published private(set) var striche: [Strich] = []
    @Published var aktuell: Strich?
    @Published var werkzeug: Werkzeug = .keins
    @Published var stiftFarbe: Farbe = .rot
    @Published var stiftBreite: CGFloat = 6
    @Published var markerFarbe: Farbe = .gelb
    @Published var markerBreite: CGFloat = 28
    @Published var zuschnitt: CGRect?
    @Published var zeigeText = false
    @Published var erkannterText = ""
    @Published var erkenntGerade = false
    @Published var lineal: Lineal?

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

    // MARK: Werkzeuge

    func waehle(_ w: Werkzeug) {
        if w == .zuschneiden {
            zuschnitt = CGRect(origin: .zero, size: groesse)
            werkzeug = .zuschneiden
            return
        }
        zuschnitt = nil
        werkzeug = (werkzeug == w) ? .keins : w
    }

    func beginneStrich(_ p: CGPoint) {
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
        aktuell = Strich(punkte: [anLineal(p)],
                         farbe: istMarker ? markerFarbe : stiftFarbe,
                         breite: breite,
                         marker: istMarker)
    }

    func erweitereStrich(_ p: CGPoint) {
        guard var s = aktuell else { return }
        if kante != nil, let erster = s.punkte.first {
            s.punkte = [erster, anLineal(p)]       // gerade Linie entlang der Kante
        } else {
            s.punkte.append(p)
        }
        aktuell = s
    }

    private func anLineal(_ p: CGPoint) -> CGPoint {
        guard let k = kante, let l = lineal else { return p }
        return l.punkt(t: l.lokal(p).t, n: k)
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
        // an 0°, 45°, 90° … leicht einrasten
        let naechste = (g / 45).rounded() * 45
        if abs(g - naechste) < 0.8 { g = naechste }
        l.winkel = g * .pi / 180
        lineal = l
    }

    // MARK: Maus auf der Zeichenfläche (Bildpixel)

    func zeigerBewegt(start: CGPoint, aktuell p: CGPoint, radiererRadius: CGFloat) {
        if geste == nil { geste = waehleGeste(start) }
        switch geste {
        case .zeichnen:
            if aktuell == nil { beginneStrich(start) }
            erweitereStrich(p)
        case .lineal(let v):
            lineal?.mitte = CGPoint(x: p.x + v.x, y: p.y + v.y)
        case .radieren:
            radiere(p, radius: radiererRadius)
        case .zuschneiden:
            setzeZuschnitt(CGRect(x: min(start.x, p.x), y: min(start.y, p.y),
                                  width: abs(p.x - start.x), height: abs(p.y - start.y)))
        case .nichts, .none:
            break
        }
    }

    func zeigerLos() {
        switch geste {
        case .zeichnen:
            beendeStrich()
        case .radieren:
            radiererEnde()
        case .zuschneiden:
            if let z = zuschnitt, z.width >= 4, z.height >= 4 { break }
            setzeZuschnitt(CGRect(origin: .zero, size: groesse))
        default:
            break
        }
        geste = nil
        kante = nil
    }

    private func waehleGeste(_ start: CGPoint) -> Geste {
        if werkzeug == .zuschneiden { return .zuschneiden }
        if let l = lineal {
            let lo = l.lokal(start)
            if abs(lo.t) <= l.laenge / 2 && abs(lo.n) < l.breite / 2 - 8 {
                return .lineal(versatz: CGPoint(x: l.mitte.x - start.x, y: l.mitte.y - start.y))
            }
        }
        switch werkzeug {
        case .stift, .marker: return .zeichnen
        case .radierer: return .radieren
        default: return .nichts
        }
    }

    func beendeStrich() {
        guard let s = aktuell else { return }
        merkeUndo()
        striche.append(s)
        aktuell = nil
    }

    func radiere(_ p: CGPoint, radius: CGFloat) {
        let treffer = striche.filter { s in
            s.punkte.contains { hypot($0.x - p.x, $0.y - p.y) <= radius + s.breite / 2 }
        }
        guard !treffer.isEmpty else { return }
        if !radiererAktiv {
            merkeUndo()
            radiererAktiv = true
        }
        let ids = Set(treffer.map(\.id))
        striche.removeAll { ids.contains($0.id) }
    }

    func radiererEnde() {
        radiererAktiv = false
    }

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
        let flach = gerendert()
        if let neu = flach.cropping(to: r) {
            bild = neu
            striche = []
        }
        zuschnitt = nil
        werkzeug = .keins
    }

    func zuschneidenAbbrechen() {
        zuschnitt = nil
        werkzeug = .keins
    }

    // MARK: Rückgängig

    private func merkeUndo() {
        undoStapel.append(Schnappschuss(bild: bild, striche: striche))
        if undoStapel.count > 50 { undoStapel.removeFirst() }
        redoStapel.removeAll()
    }

    func rueckgaengig() {
        guard let z = undoStapel.popLast() else { return }
        redoStapel.append(Schnappschuss(bild: bild, striche: striche))
        bild = z.bild
        striche = z.striche
    }

    func wiederholen() {
        guard let z = redoStapel.popLast() else { return }
        undoStapel.append(Schnappschuss(bild: bild, striche: striche))
        bild = z.bild
        striche = z.striche
    }

    // MARK: Ausgabe

    /// Bild mit allen Zeichnungen zusammengeführt.
    func gerendert() -> CGImage {
        guard !striche.isEmpty else { return bild }
        let w = bild.width, h = bild.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: Bildbearbeitung.farbraum,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return bild }
        ctx.draw(bild, in: CGRect(x: 0, y: 0, width: w, height: h))
        // Striche sind oben-links-basiert → Koordinaten spiegeln
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        for s in striche {
            ctx.saveGState()
            ctx.setLineWidth(s.breite)
            ctx.setLineJoin(.round)
            if s.marker {
                ctx.setBlendMode(.multiply)
                ctx.setLineCap(.square)
                ctx.setStrokeColor(s.farbe.nsColor.withAlphaComponent(0.5).cgColor)
            } else {
                ctx.setLineCap(.round)
                ctx.setStrokeColor(s.farbe.nsColor.cgColor)
            }
            ctx.addPath(s.cgPfad)
            ctx.strokePath()
            ctx.restoreGState()
        }
        return ctx.makeImage() ?? bild
    }

    func erkenneText() async {
        erkenntGerade = true
        let text = await Texterkennung.erkenne(gerendert())
        erkenntGerade = false
        erkannterText = text.isEmpty ? "Im Ausschnitt wurde kein Text gefunden." : text
        zeigeText = true
    }
}

// MARK: - Zeichenfläche

struct EditorFlaeche: View {
    @ObservedObject var m: EditorModell
    @AppStorage(Schluessel.darstellung) private var darstellung: Darstellung = .windows

    var body: some View {
        let stil = Stil(darstellung: darstellung)
        GeometryReader { geo in
            let faktor = NSScreen.main?.backingScaleFactor ?? 2
            let iw = CGFloat(m.bild.width)
            let ih = CGFloat(m.bild.height)
            let s = max(0.01, min((geo.size.width - 48) / iw, (geo.size.height - 48) / ih, 1 / faktor))
            leinwand(s: s)
                .frame(width: iw * s, height: ih * s)
                .overlay(Rectangle().strokeBorder(stil.linie, lineWidth: 1))
                .shadow(color: Color.black.opacity(stil.istWindows ? 0.12 : 0.25), radius: stil.istWindows ? 4 : 10, y: 2)
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(stil.flaeche)
        .overlay {
            if m.erkenntGerade {
                ProgressView("Text wird erkannt …")
                    .padding(20)
                    .background(RoundedRectangle(cornerRadius: 10).fill(.regularMaterial))
            }
        }
        .sheet(isPresented: $m.zeigeText) {
            TextErgebnisAnsicht(text: m.erkannterText) { m.zeigeText = false }
        }
    }

    private func leinwand(s: CGFloat) -> some View {
        ZStack {
            Canvas { ctx, size in
                ctx.draw(Image(decorative: m.bild, scale: 1), in: CGRect(origin: .zero, size: size))
                ctx.scaleBy(x: s, y: s)
                for strich in m.striche { zeichne(strich, in: ctx) }
                if let a = m.aktuell { zeichne(a, in: ctx) }
                if let l = m.lineal { zeichneLineal(l, s: s, in: ctx) }
            }

            if m.werkzeug == .zuschneiden, let z = m.zuschnitt {
                Canvas { ctx, size in
                    let r = CGRect(x: z.minX * s, y: z.minY * s, width: z.width * s, height: z.height * s)
                    var pfad = Path(CGRect(origin: .zero, size: size))
                    pfad.addRect(r)
                    ctx.fill(pfad, with: .color(Color.black.opacity(0.5)), style: FillStyle(eoFill: true))
                    ctx.stroke(Path(r), with: .color(Color.white), lineWidth: 1.5)
                    // Drittel-Linien
                    var linien = Path()
                    for i in 1...2 {
                        let x = r.minX + r.width * CGFloat(i) / 3
                        let y = r.minY + r.height * CGFloat(i) / 3
                        linien.move(to: CGPoint(x: x, y: r.minY)); linien.addLine(to: CGPoint(x: x, y: r.maxY))
                        linien.move(to: CGPoint(x: r.minX, y: y)); linien.addLine(to: CGPoint(x: r.maxX, y: y))
                    }
                    ctx.stroke(linien, with: .color(Color.white.opacity(0.5)), lineWidth: 0.5)
                    for ecke in [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                                 CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)] {
                        ctx.fill(Path(CGRect(x: ecke.x - 4, y: ecke.y - 4, width: 8, height: 8)), with: .color(Color.white))
                    }
                }
                .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            if case .active = phase, m.werkzeug != .keins { NSCursor.crosshair.set() }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    m.zeigerBewegt(start: CGPoint(x: v.startLocation.x / s, y: v.startLocation.y / s),
                                   aktuell: CGPoint(x: v.location.x / s, y: v.location.y / s),
                                   radiererRadius: 10 / s)
                }
                .onEnded { _ in m.zeigerLos() }
        )
    }

    private func zeichneLineal(_ l: Lineal, s: CGFloat, in ctx: GraphicsContext) {
        var c = ctx
        c.translateBy(x: l.mitte.x, y: l.mitte.y)
        c.rotate(by: .radians(Double(l.winkel)))
        let r = CGRect(x: -l.laenge / 2, y: -l.breite / 2, width: l.laenge, height: l.breite)
        let form = Path(roundedRect: r, cornerRadius: 6 / s)
        c.fill(form, with: .color(Color(white: 0.97).opacity(0.88)))
        c.stroke(form, with: .color(Color.black.opacity(0.35)), lineWidth: 1 / s)

        // Teilstriche an beiden Kanten
        var striche = Path()
        let abstand = max(4, 5 / s)
        var i = 0
        var x = -l.laenge / 2 + abstand
        while x < l.laenge / 2 {
            let lang: CGFloat = (i + 1) % 10 == 0 ? l.breite * 0.28 : ((i + 1) % 5 == 0 ? l.breite * 0.2 : l.breite * 0.11)
            striche.move(to: CGPoint(x: x, y: -l.breite / 2))
            striche.addLine(to: CGPoint(x: x, y: -l.breite / 2 + lang))
            striche.move(to: CGPoint(x: x, y: l.breite / 2))
            striche.addLine(to: CGPoint(x: x, y: l.breite / 2 - lang))
            x += abstand
            i += 1
        }
        c.stroke(striche, with: .color(Color.black.opacity(0.55)), lineWidth: 1 / s)

        c.draw(Text("\(l.grad)°")
                .font(.system(size: 13 / s, weight: .semibold))
                .foregroundColor(Color.black.opacity(0.75)),
               at: .zero)
    }

    private func zeichne(_ s: Strich, in ctx: GraphicsContext) {
        var c = ctx
        let pfad = Path(s.cgPfad)
        if s.marker {
            c.blendMode = .multiply
            c.stroke(pfad, with: .color(s.farbe.color.opacity(0.5)),
                     style: StrokeStyle(lineWidth: s.breite, lineCap: .square, lineJoin: .round))
        } else {
            c.stroke(pfad, with: .color(s.farbe.color),
                     style: StrokeStyle(lineWidth: s.breite, lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Werkzeuge in der Leiste

struct BearbeitungsWerkzeuge: View {
    @ObservedObject var m: EditorModell
    var mitRueckgaengig: Bool = true
    @ObservedObject private var k = KuerzelSpeicher.shared

    var body: some View {
        HStack(spacing: 2) {
            if m.werkzeug == .zuschneiden {
                Text("Bereich aufziehen").font(.system(size: 12)).foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                Button("Abbrechen") { m.zuschneidenAbbrechen() }
                    .keyboardShortcut(.cancelAction)
                Button("Übernehmen") { m.zuschneidenAnwenden() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            } else {
                LeistenKnopf(symbol: "pencil.tip", hilfe: k.hilfe("Kugelschreiber", .stift), aktiv: m.werkzeug == .stift) { m.waehle(.stift) }
                FarbMenue(farbe: $m.stiftFarbe, breite: $m.stiftBreite, breiten: [3, 6, 12])
                LeistenKnopf(symbol: "highlighter", hilfe: k.hilfe("Textmarker", .marker), aktiv: m.werkzeug == .marker) { m.waehle(.marker) }
                FarbMenue(farbe: $m.markerFarbe, breite: $m.markerBreite, breiten: [16, 28, 44])
                LeistenKnopf(symbol: "eraser", hilfe: k.hilfe("Radierer", .radierer), aktiv: m.werkzeug == .radierer) { m.waehle(.radierer) }
                LeistenKnopf(symbol: "ruler", hilfe: k.hilfe("Lineal (mit dem Mausrad drehen)", .lineal), aktiv: m.lineal != nil) { m.schalteLineal() }
                LeistenKnopf(symbol: "crop", hilfe: k.hilfe("Zuschneiden", .zuschneiden)) { m.waehle(.zuschneiden) }
                LeistenKnopf(symbol: "text.viewfinder", hilfe: k.hilfe("Textaktionen", .texterkennung)) {
                    Task { await m.erkenneText() }
                }
                if mitRueckgaengig {
                    Trenner()
                    RueckgaengigKnoepfe(m: m)
                }
            }
        }
    }
}

struct RueckgaengigKnoepfe: View {
    @ObservedObject var m: EditorModell
    @ObservedObject private var k = KuerzelSpeicher.shared

    var body: some View {
        HStack(spacing: 2) {
            LeistenKnopf(symbol: "arrow.uturn.backward", hilfe: k.hilfe("Rückgängig", .rueckgaengig)) { m.rueckgaengig() }
                .opacity(m.kannRueckgaengig ? 1 : 0.35)
            LeistenKnopf(symbol: "arrow.uturn.forward", hilfe: k.hilfe("Wiederholen", .wiederholen)) { m.wiederholen() }
                .opacity(m.kannWiederholen ? 1 : 0.35)
        }
    }
}

struct FarbMenue: View {
    @Binding var farbe: Farbe
    @Binding var breite: CGFloat
    let breiten: [CGFloat]

    private func breitenName(_ b: CGFloat) -> String {
        switch breiten.firstIndex(of: b) ?? 2 {
        case 0: return "Dünn"
        case 1: return "Mittel"
        default: return "Dick"
        }
    }

    var body: some View {
        let farbBindung = $farbe
        let breitenBindung = $breite
        return HoverKnopf(kennung: "farbe-\(breiten.first ?? 0)", hilfe: "Farbe und Stärke") {
            var eintraege: [Klappmenue.Eintrag] = [.ueberschrift("Farbe")]
            for f in Farbe.allCases {
                eintraege.append(.init(titel: f.name, bild: f.punkt, an: f == farbe) { farbBindung.wrappedValue = f })
            }
            eintraege.append(.trenner)
            eintraege.append(.ueberschrift("Stärke"))
            for b in breiten {
                eintraege.append(.init(titel: breitenName(b), an: b == breite) { breitenBindung.wrappedValue = b })
            }
            Klappmenue.zeige(eintraege)
        } inhalt: {
            VStack(spacing: 2) {
                Circle().fill(farbe.color)
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 0.5))
                    .frame(width: 10, height: 10)
                Image(systemName: "chevron.down").font(.system(size: 7, weight: .semibold))
            }
            .frame(width: 16, height: 32)
        }
    }
}

struct TextErgebnisAnsicht: View {
    let text: String
    let schliessen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Erkannter Text").font(.headline)
            ScrollView {
                Text(text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
            HStack {
                Spacer()
                Button("Alles kopieren") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                Button("Fertig", action: schliessen)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520, height: 420)
    }
}
