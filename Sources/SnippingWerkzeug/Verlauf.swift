import AppKit
import ImageIO

/// Die letzten Ausschnitte – bleiben auch nach einem Neustart erhalten.
enum Verlauf {
    /// Wie viele Ausschnitte aufgehoben werden (0 = unbegrenzt), einstellbar in den Einstellungen
    static var maximal: Int { UserDefaults.standard.integer(forKey: Schluessel.verlaufAnzahl) }
    static let optionen = [30, 100, 500, 0]
    static func name(_ n: Int) -> String { n == 0 ? "Unbegrenzt" : "\(n) Ausschnitte" }
    /// So viele zeigt das Menü direkt an
    static let imMenue = 40

    static var ordner: URL {
        let basis = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return basis.appendingPathComponent("Snipping Werkzeug/Verlauf", isDirectory: true)
    }

    static var aktiv: Bool { UserDefaults.standard.bool(forKey: Schluessel.verlauf) }

    static func merke(_ bild: CGImage) {
        guard aktiv else { return }
        do {
            try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd'_'HH-mm-ss-SSS"
            let url = ordner.appendingPathComponent("\(f.string(from: Date())).png")
            try Speicher.schreibe(bild, nach: url)
            aufraeumen()
        } catch {
            // Verlauf ist nur ein Komfort – Fehler hier nicht melden
        }
    }

    /// Neueste zuerst
    static func eintraege() -> [(url: URL, datum: Date)] {
        let dateien = (try? FileManager.default.contentsOfDirectory(
            at: ordner, includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles])) ?? []
        return dateien
            .filter { $0.pathExtension.lowercased() == "png" }
            .map { url in
                let datum = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return (url: url, datum: datum)
            }
            .sorted { $0.datum > $1.datum }
    }

    static func lade(_ url: URL) -> CGImage? {
        guard let quelle = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(quelle, 0, nil)
    }

    static func vorschau(_ url: URL) -> NSImage? {
        let optionen: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 160,
        ]
        guard let quelle = CGImageSourceCreateWithURL(url as CFURL, nil),
              let mini = CGImageSourceCreateThumbnailAtIndex(quelle, 0, optionen as CFDictionary) else { return nil }
        // In ein festes 64×40-Feld einpassen, damit das Menü ordentlich aussieht
        let ziel = NSSize(width: 64, height: 40)
        return NSImage(size: ziel, flipped: false) { r in
            let w = CGFloat(mini.width), h = CGFloat(mini.height)
            let s = min(r.width / w, r.height / h)
            let g = NSSize(width: w * s, height: h * s)
            let rahmen = NSRect(x: (r.width - g.width) / 2, y: (r.height - g.height) / 2, width: g.width, height: g.height)
            NSImage(cgImage: mini, size: g).draw(in: rahmen)
            NSColor.black.withAlphaComponent(0.2).setStroke()
            NSBezierPath(rect: rahmen.insetBy(dx: 0.25, dy: 0.25)).stroke()
            return true
        }
    }

    static func leeren() {
        try? FileManager.default.removeItem(at: ordner)
    }

    private static func aufraeumen() {
        let alle = eintraege()
        guard maximal > 0, alle.count > maximal else { return }
        for e in alle.dropFirst(maximal) {
            try? FileManager.default.removeItem(at: e.url)
        }
    }

    /// Klappmenü mit Miniaturen; Klick öffnet den Ausschnitt im Editor.
    @MainActor
    static func zeigeMenue() {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateStyle = .short
        f.timeStyle = .short
        f.doesRelativeDateFormatting = true

        var e: [Klappmenue.Eintrag] = []
        let liste = eintraege()
        if !aktiv {
            e.append(.ueberschrift("Verlauf ist in den Einstellungen ausgeschaltet"))
        } else if liste.isEmpty {
            e.append(.ueberschrift("Noch keine Ausschnitte im Verlauf"))
        } else {
            e.append(.ueberschrift(liste.count > imMenue
                                   ? "Die neuesten \(imMenue) von \(liste.count) Ausschnitten"
                                   : "\(liste.count) Ausschnitte im Verlauf"))
            for eintrag in liste.prefix(imMenue) {
                let url = eintrag.url
                e.append(.init(titel: f.string(from: eintrag.datum), bild: vorschau(url)) {
                    if let bild = lade(url) {
                        Hauptfenster.shared.zeigeBild(bild, meldung: "Aus dem Verlauf geöffnet")
                    }
                })
            }
        }
        e.append(.trenner)
        e.append(.init(titel: liste.count > imMenue ? "Alle \(liste.count) im Finder zeigen" : "Verlauf-Ordner öffnen",
                       symbol: "folder") {
            try? FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
            NSWorkspace.shared.open(ordner)
        })
        if !liste.isEmpty {
            e.append(.init(titel: "Verlauf leeren", symbol: "trash") { leeren() })
        }
        Klappmenue.zeige(e)
    }
}
