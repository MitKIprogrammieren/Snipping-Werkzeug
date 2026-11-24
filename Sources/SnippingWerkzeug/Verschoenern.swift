import SwiftUI
import AppKit

// Rahmen und Hintergrund: Farbverlauf, Abstand, runde Ecken, Schatten, optional Fensterleiste.

enum Hintergrund: String, CaseIterable, Identifiable {
    case lila, ozean, sonne, wald, nacht, rosa, weiss, transparent
    var id: String { rawValue }

    var name: String {
        switch self {
        case .lila: return "Lila"
        case .ozean: return "Ozean"
        case .sonne: return "Sonnenuntergang"
        case .wald: return "Wald"
        case .nacht: return "Nacht"
        case .rosa: return "Rosa"
        case .weiss: return "Weiß"
        case .transparent: return "Transparent"
        }
    }

    /// Zwei Farben für den Verlauf (oben links → unten rechts)
    var farben: (NSColor, NSColor)? {
        func f(_ h: UInt32) -> NSColor { NSColor(hex: h) }
        switch self {
        case .lila: return (f(0xAFA9EC), f(0x5DCAA5))
        case .ozean: return (f(0x5AA9F0), f(0x1D3F8A))
        case .sonne: return (f(0xFAC775), f(0xD85A30))
        case .wald: return (f(0xC0DD97), f(0x2F6B3A))
        case .nacht: return (f(0x3C3489), f(0x0B0B1A))
        case .rosa: return (f(0xF4C0D1), f(0x993556))
        case .weiss: return (f(0xF4F4F4), f(0xE8E8E8))
        case .transparent: return nil
        }
    }

    var vorschau: NSImage {
        let paar = farben
        return NSImage(size: NSSize(width: 14, height: 14), flipped: false) { r in
            let pfad = NSBezierPath(roundedRect: r.insetBy(dx: 1, dy: 1), xRadius: 3, yRadius: 3)
            if let paar {
                NSGradient(starting: paar.0, ending: paar.1)?.draw(in: pfad, angle: -45)
            } else {
                NSColor.white.setFill(); pfad.fill()
                NSColor.lightGray.setFill()
                NSBezierPath(rect: NSRect(x: 1, y: 1, width: 6, height: 6)).fill()
                NSBezierPath(rect: NSRect(x: 7, y: 7, width: 6, height: 6)).fill()
            }
            NSColor.black.withAlphaComponent(0.25).setStroke()
            pfad.lineWidth = 0.5
            pfad.stroke()
            return true
        }
    }
}

struct RahmenOptionen: Equatable {
    var hintergrund: Hintergrund = .lila
    var abstand: Double = 8          // Prozent der längeren Bildseite
    var ecken: Double = 2            // Prozent der kürzeren Bildseite
    var schatten = true
    var fensterleiste = false
}

enum Verschoenern {
    static func anwenden(_ bild: CGImage, _ o: RahmenOptionen) -> CGImage? {
        let w = CGFloat(bild.width), h = CGFloat(bild.height)
        let rand = max(w, h) * o.abstand / 100
        let leiste: CGFloat = o.fensterleiste ? max(22, min(w, h) * 0.06) : 0
        let karteW = w, karteH = h + leiste
        let gesamtW = Int((karteW + rand * 2).rounded()), gesamtH = Int((karteH + rand * 2).rounded())
        guard let ctx = CGContext(data: nil, width: gesamtW, height: gesamtH, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: Bildbearbeitung.farbraum,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let ganz = CGRect(x: 0, y: 0, width: gesamtW, height: gesamtH)

        // Hintergrund-Verlauf (CG zählt von unten: oben links = (0, H))
        if let paar = o.hintergrund.farben,
           let verlauf = CGGradient(colorsSpace: Bildbearbeitung.farbraum,
                                    colors: [paar.0.cgColor, paar.1.cgColor] as CFArray, locations: [0, 1]) {
            ctx.drawLinearGradient(verlauf, start: CGPoint(x: 0, y: ganz.height), end: CGPoint(x: ganz.width, y: 0), options: [])
        }

        let karte = CGRect(x: rand, y: rand, width: karteW, height: karteH)
        let radius = min(karteW, karteH) * o.ecken / 100
        let form = CGPath(roundedRect: karte, cornerWidth: radius, cornerHeight: radius, transform: nil)

        if o.schatten && rand > 0 {
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -max(w, h) * 0.012), blur: max(w, h) * 0.035,
                          color: NSColor.black.withAlphaComponent(0.4).cgColor)
            ctx.addPath(form)
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fillPath()
            ctx.restoreGState()
        }

        ctx.saveGState()
        ctx.addPath(form)
        ctx.clip()
        ctx.draw(bild, in: CGRect(x: rand, y: rand, width: w, height: h))
        if leiste > 0 {
            // Fensterleiste oben mit den drei Punkten
            let leistenRahmen = CGRect(x: rand, y: rand + h, width: w, height: leiste)
            ctx.setFillColor(NSColor(hex: 0xECECEC).cgColor)
            ctx.fill(leistenRahmen)
            let d = leiste * 0.42
            for (i, farbe) in [NSColor(hex: 0xFF5F57), NSColor(hex: 0xFEBC2E), NSColor(hex: 0x28C840)].enumerated() {
                ctx.setFillColor(farbe.cgColor)
                ctx.fillEllipse(in: CGRect(x: leistenRahmen.minX + leiste * 0.5 + CGFloat(i) * d * 1.6,
                                           y: leistenRahmen.midY - d / 2, width: d, height: d))
            }
        }
        ctx.restoreGState()
        return ctx.makeImage()
    }

    /// Kleine, schnelle Vorschau für das Bedienfeld
    static func vorschau(_ bild: CGImage, _ o: RahmenOptionen) -> NSImage? {
        let s = min(1, 320 / CGFloat(max(bild.width, bild.height)))
        let w = max(1, Int(CGFloat(bild.width) * s)), h = max(1, Int(CGFloat(bild.height) * s))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: Bildbearbeitung.farbraum,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(bild, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let klein = ctx.makeImage(), let fertig = anwenden(klein, o) else { return nil }
        return NSImage(cgImage: fertig, size: NSSize(width: fertig.width, height: fertig.height))
    }
}

extension EditorModell {
    func oeffneRahmen() {
        beendeTextBearbeitung()
        zeigeSchwaerzen = false
        rahmenVorschau = Verschoenern.vorschau(gerendert(), rahmen)
        zeigeRahmen = true
    }

    func aktualisiereRahmenVorschau() {
        rahmenVorschau = Verschoenern.vorschau(gerendert(textBeenden: false), rahmen)
    }

    func rahmenUebernehmen() {
        if let neu = Verschoenern.anwenden(gerendert(), rahmen) {
            ersetzeBildUndElemente(neu)
        }
        zeigeRahmen = false
        rahmenVorschau = nil
    }
}

struct RahmenAnsichtPanel: View {
    @ObservedObject var m: EditorModell
    @AppStorage(Schluessel.darstellung) private var darstellung: Darstellung = .windows

    private func bindung<T>(_ pfad: WritableKeyPath<RahmenOptionen, T>) -> Binding<T> {
        Binding(get: { m.rahmen[keyPath: pfad] },
                set: { m.rahmen[keyPath: pfad] = $0; m.aktualisiereRahmenVorschau() })
    }

    var body: some View {
        let stil = Stil(darstellung: darstellung)
        VStack(alignment: .leading, spacing: 10) {
            Text("Rahmen und Hintergrund").font(.system(size: 13, weight: .semibold))
            if let v = m.rahmenVorschau {
                Image(nsImage: v)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 170)
                    .background(Color.primary.opacity(0.04))
            }
            Text("Hintergrund").font(.system(size: 11)).foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 6), count: 8), spacing: 6) {
                ForEach(Hintergrund.allCases) { h in
                    Button {
                        m.rahmen.hintergrund = h
                        m.aktualisiereRahmenVorschau()
                    } label: {
                        Image(nsImage: h.vorschau)
                            .resizable()
                            .frame(width: 24, height: 24)
                            .overlay(RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(m.rahmen.hintergrund == h ? stil.akzent : Color.clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .help(h.name)
                }
            }
            HStack {
                Text("Abstand").font(.system(size: 12)).frame(width: 60, alignment: .leading)
                Slider(value: bindung(\.abstand), in: 0...20)
            }
            HStack {
                Text("Ecken").font(.system(size: 12)).frame(width: 60, alignment: .leading)
                Slider(value: bindung(\.ecken), in: 0...10)
            }
            Toggle("Schatten", isOn: bindung(\.schatten))
            Toggle("Fensterleiste mit drei Punkten", isOn: bindung(\.fensterleiste))
            HStack {
                Spacer()
                Button("Abbrechen") {
                    m.zeigeRahmen = false
                    m.rahmenVorschau = nil
                }
                .keyboardShortcut(.cancelAction)
                Button("Übernehmen") { m.rahmenUebernehmen() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .font(.system(size: 12))
        .padding(14)
        .frame(width: 300)
        .background(RoundedRectangle(cornerRadius: stil.istWindows ? 8 : 12).fill(stil.karte))
        .overlay(RoundedRectangle(cornerRadius: stil.istWindows ? 8 : 12).strokeBorder(stil.linie, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.15), radius: 8, y: 2)
        .padding(12)
    }
}
