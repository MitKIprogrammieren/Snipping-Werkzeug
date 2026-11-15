import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@preconcurrency import Vision

enum Ablage {
    static func kopiere(_ bild: CGImage) {
        let rep = NSBitmapImageRep(cgImage: bild)
        let pb = NSPasteboard.general
        pb.clearContents()
        if let png = rep.representation(using: .png, properties: [:]) {
            pb.setData(png, forType: .png)
        }
        if let tiff = rep.tiffRepresentation {
            pb.setData(tiff, forType: .tiff)
        }
    }

    static func kopiereDatei(_ url: URL) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([url as NSURL])
    }
}

enum Speicher {
    static func zeitstempel() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "yyyy-MM-dd 'um' HH.mm.ss"
        return f.string(from: Date())
    }

    static func zielOrdner() throws -> URL {
        let url = Einstellungen.ordner
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func schreibe(_ bild: CGImage, nach url: URL) throws {
        let istJPEG = ["jpg", "jpeg"].contains(url.pathExtension.lowercased())
        let typ: UTType = istJPEG ? .jpeg : .png
        guard let ziel = CGImageDestinationCreateWithURL(url as CFURL, typ.identifier as CFString, 1, nil) else {
            throw Fehler.speichern
        }
        var optionen: [CFString: Any] = [:]
        if istJPEG { optionen[kCGImageDestinationLossyCompressionQuality] = 0.92 }
        CGImageDestinationAddImage(ziel, bild, optionen as CFDictionary)
        guard CGImageDestinationFinalize(ziel) else { throw Fehler.speichern }
    }

    static func autoSpeichern(_ bild: CGImage) throws -> URL {
        let url = try zielOrdner().appendingPathComponent("Ausschnitt \(zeitstempel()).png")
        try schreibe(bild, nach: url)
        return url
    }

    static func autoSpeichernVideo(_ quelle: URL) throws -> URL {
        let url = try zielOrdner().appendingPathComponent("Bildschirmaufnahme \(zeitstempel()).mp4")
        try FileManager.default.copyItem(at: quelle, to: url)
        return url
    }

    static func temporaeresPNG(_ bild: CGImage) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Ausschnitt \(zeitstempel()).png")
        try? FileManager.default.removeItem(at: url)
        try schreibe(bild, nach: url)
        return url
    }

    @MainActor
    static func speichernUnter(bild: CGImage) -> URL? {
        let p = NSSavePanel()
        p.allowedContentTypes = [.png, .jpeg]
        p.nameFieldStringValue = "Ausschnitt \(zeitstempel()).png"
        p.directoryURL = try? zielOrdner()
        p.canCreateDirectories = true
        guard p.runModal() == .OK, let url = p.url else { return nil }
        do {
            try schreibe(bild, nach: url)
            return url
        } catch {
            Meldung.fehler(error)
            return nil
        }
    }

    @MainActor
    static func videoSpeichernUnter(_ quelle: URL) -> URL? {
        let p = NSSavePanel()
        p.allowedContentTypes = [.mpeg4Movie]
        p.nameFieldStringValue = quelle.lastPathComponent
        p.directoryURL = try? zielOrdner()
        p.canCreateDirectories = true
        guard p.runModal() == .OK, let url = p.url else { return nil }
        do {
            if url.standardizedFileURL == quelle.standardizedFileURL { return url }
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            try FileManager.default.copyItem(at: quelle, to: url)
            return url
        } catch {
            Meldung.fehler(error)
            return nil
        }
    }
}

enum Teilen {
    @MainActor
    static func zeige(_ url: URL) {
        guard let view = NSApp.keyWindow?.contentView else { return }
        let picker = NSSharingServicePicker(items: [url])
        let y = view.isFlipped ? 60 : view.bounds.maxY - 60
        picker.show(relativeTo: NSRect(x: view.bounds.maxX - 150, y: y, width: 1, height: 1),
                    of: view, preferredEdge: .minY)
    }
}

enum Bildbearbeitung {
    static var farbraum: CGColorSpace { CGColorSpace(name: CGColorSpace.sRGB)! }

    /// Schneidet einen Freihand-Bereich aus (Pixel, Ursprung oben links). Außerhalb bleibt transparent.
    static func freiform(_ bild: CGImage, punkte: [CGPoint]) -> CGImage? {
        guard punkte.count > 2 else { return nil }
        let xs = punkte.map(\.x), ys = punkte.map(\.y)
        let gesamt = CGRect(x: 0, y: 0, width: bild.width, height: bild.height)
        let box = CGRect(x: xs.min()!, y: ys.min()!,
                         width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
            .integral.intersection(gesamt)
        guard !box.isNull, box.width >= 2, box.height >= 2 else { return nil }

        guard let ctx = CGContext(data: nil, width: Int(box.width), height: Int(box.height),
                                  bitsPerComponent: 8, bytesPerRow: 0, space: farbraum,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // CGContext hat den Ursprung unten links → y spiegeln
        let pfad = CGMutablePath()
        pfad.addLines(between: punkte.map { CGPoint(x: $0.x - box.minX, y: box.maxY - $0.y) })
        pfad.closeSubpath()
        ctx.addPath(pfad)
        ctx.clip()
        ctx.draw(bild, in: CGRect(x: -box.minX, y: -(CGFloat(bild.height) - box.maxY),
                                  width: CGFloat(bild.width), height: CGFloat(bild.height)))
        return ctx.makeImage()
    }
}

/// Sorgt dafür, dass eine Continuation nur einmal fortgesetzt wird.
final class Einmal: @unchecked Sendable {
    private let lock = NSLock()
    private var erledigt = false

    func ausfuehren(_ f: () -> Void) {
        lock.lock()
        let los = !erledigt
        erledigt = true
        lock.unlock()
        if los { f() }
    }
}

enum Texterkennung {
    static func erkenne(_ bild: CGImage) async -> String {
        await withCheckedContinuation { (c: CheckedContinuation<String, Never>) in
            let einmal = Einmal()
            let anfrage = VNRecognizeTextRequest { req, _ in
                let zeilen = (req.results as? [VNRecognizedTextObservation])?
                    .compactMap { $0.topCandidates(1).first?.string } ?? []
                einmal.ausfuehren { c.resume(returning: zeilen.joined(separator: "\n")) }
            }
            anfrage.recognitionLevel = .accurate
            anfrage.usesLanguageCorrection = true
            anfrage.recognitionLanguages = ["de-DE", "en-US"]
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try VNImageRequestHandler(cgImage: bild, options: [:]).perform([anfrage])
                } catch {
                    einmal.ausfuehren { c.resume(returning: "") }
                }
            }
        }
    }
}
