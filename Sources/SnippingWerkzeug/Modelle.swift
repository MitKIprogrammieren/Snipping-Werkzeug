import SwiftUI
import AppKit

enum Darstellung: String, CaseIterable, Identifiable {
    case windows, mac
    var id: String { rawValue }
    var name: String { self == .windows ? "Windows" : "Mac" }
}

enum Art: String, CaseIterable, Identifiable {
    case foto, video
    var id: String { rawValue }
    var name: String { self == .foto ? "Ausschnitt (Foto)" : "Bildschirmaufnahme (Video)" }
    var symbol: String { self == .foto ? "camera" : "video" }
}

enum Modus: String, CaseIterable, Identifiable {
    case rechteck, freiform, fenster, vollbild
    var id: String { rawValue }
    var name: String {
        switch self {
        case .rechteck: return "Rechteck"
        case .freiform: return "Freihand"
        case .fenster: return "Fenster"
        case .vollbild: return "Vollbild"
        }
    }
    var langName: String {
        switch self {
        case .rechteck: return "Rechteckiger Ausschnitt"
        case .freiform: return "Freihandausschnitt"
        case .fenster: return "Fensterausschnitt"
        case .vollbild: return "Vollbildausschnitt"
        }
    }
    var symbol: String {
        switch self {
        case .rechteck: return "rectangle.dashed"
        case .freiform: return "lasso"
        case .fenster: return "macwindow"
        case .vollbild: return "display"
        }
    }
}

enum Farbe: String, CaseIterable, Identifiable {
    case schwarz, weiss, rot, gelb, gruen, blau, lila
    var id: String { rawValue }

    var name: String {
        switch self {
        case .schwarz: return "Schwarz"
        case .weiss: return "Weiß"
        case .rot: return "Rot"
        case .gelb: return "Gelb"
        case .gruen: return "Grün"
        case .blau: return "Blau"
        case .lila: return "Lila"
        }
    }

    var nsColor: NSColor {
        switch self {
        case .schwarz: return NSColor(srgbRed: 0.10, green: 0.10, blue: 0.10, alpha: 1)
        case .weiss: return NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        case .rot: return NSColor(srgbRed: 0.88, green: 0.16, blue: 0.16, alpha: 1)
        case .gelb: return NSColor(srgbRed: 1.0, green: 0.86, blue: 0.0, alpha: 1)
        case .gruen: return NSColor(srgbRed: 0.18, green: 0.70, blue: 0.30, alpha: 1)
        case .blau: return NSColor(srgbRed: 0.10, green: 0.45, blue: 0.92, alpha: 1)
        case .lila: return NSColor(srgbRed: 0.56, green: 0.30, blue: 0.86, alpha: 1)
        }
    }

    var color: Color { Color(nsColor: nsColor) }

    /// Kleiner farbiger Punkt für Menüs (Menüs auf macOS zeigen nur Bilder zuverlässig an).
    var punkt: NSImage {
        let farbe = nsColor
        return NSImage(size: NSSize(width: 12, height: 12), flipped: false) { r in
            let kreis = NSBezierPath(ovalIn: r.insetBy(dx: 1, dy: 1))
            farbe.setFill()
            kreis.fill()
            NSColor.black.withAlphaComponent(0.3).setStroke()
            kreis.lineWidth = 0.5
            kreis.stroke()
            return true
        }
    }
}

enum Fehler: LocalizedError {
    case speichern
    case keinBildschirm
    case aufnahmeLeer

    var errorDescription: String? {
        switch self {
        case .speichern: return "Die Datei konnte nicht gespeichert werden."
        case .keinBildschirm: return "Der Bildschirm unter dem Mauszeiger wurde nicht gefunden."
        case .aufnahmeLeer: return "Die Bildschirmaufnahme enthält keine Daten."
        }
    }
}

enum Meldung {
    @MainActor
    static func fehler(_ error: Error) {
        let a = NSAlert()
        a.messageText = "Da ist etwas schiefgelaufen"
        a.informativeText = error.localizedDescription
        a.alertStyle = .warning
        a.runModal()
    }
}
