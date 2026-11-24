import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Schickt Ausschnitte über das eigene Meldewerk (WhatsApp-Dienst auf dem NUC) aufs Handy.
enum Meldewerk {
    static var adresse: String {
        let a = (UserDefaults.standard.string(forKey: Schluessel.meldewerkAdresse) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return a.hasSuffix("/") ? String(a.dropLast()) : a
    }
    static var schluessel: String {
        (UserDefaults.standard.string(forKey: Schluessel.meldewerkSchluessel) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static var eingerichtet: Bool { !adresse.isEmpty && !schluessel.isEmpty }

    enum Problem: LocalizedError {
        case nichtEingerichtet, adresse, antwort(String)
        var errorDescription: String? {
            switch self {
            case .nichtEingerichtet: return "Meldewerk ist noch nicht eingerichtet. Trage Adresse und Schlüssel in den Einstellungen ein."
            case .adresse: return "Die Meldewerk-Adresse ist ungültig."
            case .antwort(let t): return "Meldewerk meldet: \(t)"
            }
        }
    }

    /// Bild als JPEG (max. 2560 px lange Seite) – so bleibt die WhatsApp-Nachricht klein.
    static func jpegDatenURL(_ bild: CGImage) -> String? {
        var quelle = bild
        let lang = max(bild.width, bild.height)
        if lang > 2560 {
            let s = 2560 / CGFloat(lang)
            let w = Int(CGFloat(bild.width) * s), h = Int(CGFloat(bild.height) * s)
            if let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                   space: Bildbearbeitung.farbraum,
                                   bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) {
                ctx.interpolationQuality = .high
                ctx.draw(bild, in: CGRect(x: 0, y: 0, width: w, height: h))
                if let klein = ctx.makeImage() { quelle = klein }
            }
        }
        let daten = NSMutableData()
        guard let ziel = CGImageDestinationCreateWithData(daten, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(ziel, quelle, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(ziel) else { return nil }
        return "data:image/jpeg;base64," + (daten as Data).base64EncodedString()
    }

    static func senden(bild: CGImage?, titel: String, text: String) async throws {
        guard eingerichtet else { throw Problem.nichtEingerichtet }
        guard let url = URL(string: adresse + "/api/senden") else { throw Problem.adresse }
        var nutzlast: [String: String] = ["quelle": "snipping", "titel": titel, "text": text]
        if let bild, let daten = jpegDatenURL(bild) { nutzlast["bild"] = daten }

        var anfrage = URLRequest(url: url, timeoutInterval: 30)
        anfrage.httpMethod = "POST"
        anfrage.setValue("application/json", forHTTPHeaderField: "Content-Type")
        anfrage.setValue(schluessel, forHTTPHeaderField: "X-Schluessel")
        anfrage.httpBody = try JSONSerialization.data(withJSONObject: nutzlast)

        let (daten, antwort) = try await URLSession.shared.data(for: anfrage)
        let code = (antwort as? HTTPURLResponse)?.statusCode ?? 0
        if code == 200 { return }
        let json = (try? JSONSerialization.jsonObject(with: daten)) as? [String: Any]
        let grund = (json?["text"] as? String) ?? (json?["fehler"] as? String) ?? "Fehler \(code)"
        throw Problem.antwort(grund)
    }

    static func zeitText() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "dd.MM.yyyy, HH:mm"
        return f.string(from: Date())
    }
}
