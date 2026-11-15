import SwiftUI
import AppKit

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
            TextErgebnisAnsicht(text: m.erkannterText, codes: m.erkannteCodes) { m.zeigeText = false }
        }
    }

    private func leinwand(s: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Canvas { ctx, size in
                ctx.draw(Image(decorative: m.bild, scale: 1), in: CGRect(origin: .zero, size: size))
                ctx.scaleBy(x: s, y: s)
                let bearbeitet = m.bearbeiteterText
                let elemente = m.elemente
                let aktuell = m.aktuell
                ctx.withCGContext { cg in
                    for e in elemente where e.id != bearbeitet {
                        Zeichner.zeichne(e, in: cg)
                    }
                    if let a = aktuell { Zeichner.zeichne(a, in: cg) }
                }
                if let r = m.verpixelnRahmen {
                    ctx.fill(Path(r), with: .color(Color.black.opacity(0.25)))
                    ctx.stroke(Path(r), with: .color(Color.white),
                               style: StrokeStyle(lineWidth: 1.5 / s, dash: [6 / s, 4 / s]))
                }
                if let l = m.lineal { zeichneLineal(l, s: s, in: ctx) }
            }

            if m.werkzeug == .zuschneiden, let z = m.zuschnitt {
                Canvas { ctx, size in
                    let r = CGRect(x: z.minX * s, y: z.minY * s, width: z.width * s, height: z.height * s)
                    var pfad = Path(CGRect(origin: .zero, size: size))
                    pfad.addRect(r)
                    ctx.fill(pfad, with: .color(Color.black.opacity(0.5)), style: FillStyle(eoFill: true))
                    ctx.stroke(Path(r), with: .color(Color.white), lineWidth: 1.5)
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

            // Texteingabe direkt an der Stelle im Bild
            if let id = m.bearbeiteterText, let t = m.textElement(id) {
                let breite = max(140, (t.attributiert.size().width + t.groesse) * s + 30)
                TextEingabe(text: t.text,
                            schrift: NSFont.systemFont(ofSize: t.groesse * s, weight: .semibold),
                            farbe: t.farbe.nsColor,
                            hintergrund: t.hintergrund,
                            aenderung: { m.setzeTextInhalt(id, $0) },
                            fertig: { m.beendeTextBearbeitung() })
                    .frame(width: breite, height: t.groesse * s * 1.45)
                    .offset(x: t.position.x * s - 2, y: t.position.y * s - t.groesse * s * 0.12)
            }
        }
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            if case .active = phase {
                if m.werkzeug == .text { NSCursor.iBeam.set() }
                else if m.werkzeug != .keins { NSCursor.crosshair.set() }
            }
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
}

/// Einzeiliges Textfeld, das sofort den Fokus bekommt (ohne @FocusState).
struct TextEingabe: NSViewRepresentable {
    let text: String
    let schrift: NSFont
    let farbe: NSColor
    let hintergrund: Bool
    let aenderung: (String) -> Void
    let fertig: () -> Void

    func makeCoordinator() -> Koordinator { Koordinator() }

    func makeNSView(context: Context) -> NSTextField {
        let f = NSTextField(string: text)
        f.isBordered = false
        f.isBezeled = false
        f.focusRingType = .none
        f.delegate = context.coordinator
        f.placeholderString = "Text eingeben"
        DispatchQueue.main.async { f.window?.makeFirstResponder(f) }
        return f
    }

    func updateNSView(_ f: NSTextField, context: Context) {
        context.coordinator.aenderung = aenderung
        context.coordinator.fertig = fertig
        f.font = schrift
        f.textColor = farbe
        f.drawsBackground = hintergrund
        f.backgroundColor = hintergrund ? NSColor.white.withAlphaComponent(0.92) : .clear
    }

    final class Koordinator: NSObject, NSTextFieldDelegate {
        var aenderung: (String) -> Void = { _ in }
        var fertig: () -> Void = {}

        func controlTextDidChange(_ notification: Notification) {
            guard let f = notification.object as? NSTextField else { return }
            aenderung(f.stringValue)
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            fertig()
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selektor: Selector) -> Bool {
            if selektor == #selector(NSResponder.insertNewline(_:)) || selektor == #selector(NSResponder.cancelOperation(_:)) {
                control.window?.makeFirstResponder(nil)
                return true
            }
            return false
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
                OptionenKnopf(kennung: "stift", farbe: m.stiftFarbe) { stiftMenue }
                LeistenKnopf(symbol: "highlighter", hilfe: k.hilfe("Textmarker", .marker), aktiv: m.werkzeug == .marker) { m.waehle(.marker) }
                OptionenKnopf(kennung: "marker", farbe: m.markerFarbe) { markerMenue }
                LeistenKnopf(symbol: m.formArt.symbol, hilfe: k.hilfe("Formen", .form), aktiv: m.werkzeug == .form) { m.waehle(.form) }
                OptionenKnopf(kennung: "form", farbe: m.formFarbe) { formMenue }
                LeistenKnopf(symbol: "textformat", hilfe: k.hilfe("Text", .text), aktiv: m.werkzeug == .text) { m.waehle(.text) }
                OptionenKnopf(kennung: "text", farbe: m.textFarbe) { textMenue }
                LeistenKnopf(symbol: "1.circle", hilfe: k.hilfe("Nummerierte Marker", .nummer), aktiv: m.werkzeug == .nummer) { m.waehle(.nummer) }
                OptionenKnopf(kennung: "nummer", farbe: m.nummerFarbe) { nummerMenue }
                LeistenKnopf(symbol: m.verpixelnArt.symbol, hilfe: k.hilfe(m.verpixelnArt.name, .verpixeln), aktiv: m.werkzeug == .verpixeln) { m.waehle(.verpixeln) }
                OptionenKnopf(kennung: "verpixeln", farbe: nil) { verpixelnMenue }
                LeistenKnopf(symbol: "eraser", hilfe: k.hilfe("Radierer", .radierer), aktiv: m.werkzeug == .radierer) { m.waehle(.radierer) }
                LeistenKnopf(symbol: "ruler", hilfe: k.hilfe("Lineal (mit dem Mausrad drehen)", .lineal), aktiv: m.lineal != nil) { m.schalteLineal() }
                LeistenKnopf(symbol: "crop", hilfe: k.hilfe("Zuschneiden", .zuschneiden)) { m.waehle(.zuschneiden) }
                LeistenKnopf(symbol: "text.viewfinder", hilfe: k.hilfe("Textaktionen (Text und QR-Codes)", .texterkennung)) {
                    Task { await m.erkenneText() }
                }
                if mitRueckgaengig {
                    Trenner()
                    RueckgaengigKnoepfe(m: m)
                }
            }
        }
    }

    // MARK: Menüs der Werkzeuge

    private func farben(_ aktuell: Farbe, _ setzen: @escaping (Farbe) -> Void) -> [Klappmenue.Eintrag] {
        var e: [Klappmenue.Eintrag] = [.ueberschrift("Farbe")]
        for f in Farbe.allCases {
            e.append(.init(titel: f.name, bild: f.punkt, an: f == aktuell) { setzen(f) })
        }
        return e
    }

    private func staerken(_ werte: [CGFloat], _ aktuell: CGFloat, _ setzen: @escaping (CGFloat) -> Void) -> [Klappmenue.Eintrag] {
        let namen = ["Dünn", "Mittel", "Dick"]
        var e: [Klappmenue.Eintrag] = [.trenner, .ueberschrift("Stärke")]
        for (i, w) in werte.enumerated() {
            e.append(.init(titel: namen[min(i, 2)], an: w == aktuell) { setzen(w) })
        }
        return e
    }

    private var stiftMenue: [Klappmenue.Eintrag] {
        let m = self.m
        return farben(m.stiftFarbe) { m.stiftFarbe = $0 } + staerken([3, 6, 12], m.stiftBreite) { m.stiftBreite = $0 }
    }

    private var markerMenue: [Klappmenue.Eintrag] {
        let m = self.m
        return farben(m.markerFarbe) { m.markerFarbe = $0 } + staerken([16, 28, 44], m.markerBreite) { m.markerBreite = $0 }
    }

    private var formMenue: [Klappmenue.Eintrag] {
        let m = self.m
        var e: [Klappmenue.Eintrag] = [.ueberschrift("Form")]
        for a in FormArt.allCases {
            e.append(.init(titel: a.name, symbol: a.symbol, an: a == m.formArt) {
                m.formArt = a
                if m.werkzeug != .form { m.waehle(.form) }
            })
        }
        e.append(.trenner)
        e += farben(m.formFarbe) { m.formFarbe = $0 }
        e += staerken([3, 6, 12], m.formBreite) { m.formBreite = $0 }
        e.append(.trenner)
        e.append(.ueberschrift("Füllung (Rechteck und Kreis)"))
        for f in Fuellung.allCases {
            e.append(.init(titel: f.name, an: f == m.fuellung) { m.fuellung = f })
        }
        e.append(.trenner)
        e.append(.ueberschrift("Tipp: Mit ⇧ gerade Linien und gleichmäßige Formen"))
        return e
    }

    private var textMenue: [Klappmenue.Eintrag] {
        let m = self.m
        var e = farben(m.textFarbe) { m.textFarbe = $0 }
        e.append(.trenner)
        e.append(.ueberschrift("Größe"))
        for (name, wert) in [("Klein", CGFloat(22)), ("Mittel", 36), ("Groß", 56)] {
            e.append(.init(titel: name, an: wert == m.textGroesse) { m.textGroesse = wert })
        }
        e.append(.trenner)
        e.append(.init(titel: "Weißer Hintergrund", an: m.textHintergrund) { m.textHintergrund.toggle() })
        return e
    }

    private var nummerMenue: [Klappmenue.Eintrag] {
        let m = self.m
        return farben(m.nummerFarbe) { m.nummerFarbe = $0 }
    }

    private var verpixelnMenue: [Klappmenue.Eintrag] {
        let m = self.m
        var e: [Klappmenue.Eintrag] = [.ueberschrift("Unkenntlich machen")]
        for a in VerpixelnArt.allCases {
            e.append(.init(titel: a.name, symbol: a.symbol, an: a == m.verpixelnArt) {
                m.verpixelnArt = a
                if m.werkzeug != .verpixeln { m.waehle(.verpixeln) }
            })
        }
        return e
    }
}

/// Kleiner Pfeil-Knopf neben einem Werkzeug (mit Farbpunkt), öffnet dessen Optionen.
struct OptionenKnopf: View {
    let kennung: String
    let farbe: Farbe?
    let eintraege: () -> [Klappmenue.Eintrag]

    var body: some View {
        HoverKnopf(kennung: "optionen-\(kennung)", hilfe: "Optionen") {
            Klappmenue.zeige(eintraege())
        } inhalt: {
            VStack(spacing: 2) {
                if let farbe {
                    Circle().fill(farbe.color)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 0.5))
                        .frame(width: 10, height: 10)
                }
                Image(systemName: "chevron.down").font(.system(size: 7, weight: .semibold))
            }
            .frame(width: 16, height: 32)
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

struct TextErgebnisAnsicht: View {
    let text: String
    let codes: [String]
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

            if !codes.isEmpty {
                Text("QR- und Strichcodes").font(.headline)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(codes, id: \.self) { code in
                        HStack(spacing: 8) {
                            Image(systemName: "qrcode")
                            Text(code)
                                .textSelection(.enabled)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if let url = URL(string: code), let schema = url.scheme, ["http", "https"].contains(schema.lowercased()) {
                                Button("Öffnen") { NSWorkspace.shared.open(url) }
                            }
                            Button("Kopieren") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(code, forType: .string)
                            }
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Text kopieren") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                Button("Fertig", action: schliessen)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560, height: codes.isEmpty ? 420 : 520)
    }
}
