import SwiftUI
import AppKit
import AVFoundation
import ApplicationServices
import ImageIO
import UniformTypeIdentifiers

// MARK: - GIF aus einer Bildschirmaufnahme

enum GifExport {
    enum Problem: LocalizedError {
        case ziel
        var errorDescription: String? { "Die GIF-Datei konnte nicht geschrieben werden." }
    }

    /// 12 Bilder pro Sekunde, längste Seite höchstens 960 px – so bleiben GIFs teilbar.
    static func erstelle(von quelle: URL, nach ziel: URL, fps: Double = 12, maxSeite: CGFloat = 960) async throws {
        let asset = AVURLAsset(url: quelle)
        let dauer = try await asset.load(.duration).seconds
        let anzahl = max(1, min(Int(dauer * fps), 900))

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxSeite, height: maxSeite)
        let toleranz = CMTime(value: 1, timescale: CMTimeScale(fps * 2))
        generator.requestedTimeToleranceBefore = toleranz
        generator.requestedTimeToleranceAfter = toleranz

        try? FileManager.default.removeItem(at: ziel)
        guard let datei = CGImageDestinationCreateWithURL(ziel as CFURL, UTType.gif.identifier as CFString, anzahl, nil) else {
            throw Problem.ziel
        }
        let dateiEigenschaften = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary
        CGImageDestinationSetProperties(datei, dateiEigenschaften)
        let bildEigenschaften = [kCGImagePropertyGIFDictionary: [
            kCGImagePropertyGIFDelayTime: 1.0 / fps,
            kCGImagePropertyGIFUnclampedDelayTime: 1.0 / fps,
        ]] as CFDictionary

        for i in 0..<anzahl {
            let zeit = CMTime(seconds: Double(i) / fps, preferredTimescale: 600)
            let (bild, _) = try await generator.image(at: zeit)
            CGImageDestinationAddImage(datei, bild, bildEigenschaften)
        }
        guard CGImageDestinationFinalize(datei) else { throw Problem.ziel }
    }
}

extension HauptZustand {
    func alsGif() {
        guard let quelle = video else { return }
        let p = NSSavePanel()
        p.allowedContentTypes = [.gif]
        p.nameFieldStringValue = quelle.deletingPathExtension().lastPathComponent + ".gif"
        p.directoryURL = try? Speicher.zielOrdner()
        p.canCreateDirectories = true
        guard p.runModal() == .OK, let ziel = p.url else { return }
        arbeit = "GIF wird erstellt …"
        Task {
            do {
                try await GifExport.erstelle(von: quelle, nach: ziel)
                let groesse = (try? ziel.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                meldung = "GIF gespeichert: \(ziel.lastPathComponent) · \(ByteCountFormatter.string(fromByteCount: Int64(groesse), countStyle: .file))"
                NSWorkspace.shared.activateFileViewerSelecting([ziel])
            } catch {
                Meldung.fehler(error)
            }
            arbeit = nil
        }
    }
}

// MARK: - Tastenkürzel während der Aufnahme einblenden

@MainActor
final class TastenModell: ObservableObject {
    @Published var text = ""
    @Published var sichtbar = false
    var nummer = 0
}

struct TastenAnsicht: View {
    @ObservedObject var m: TastenModell

    var body: some View {
        Text(m.text)
            .font(.system(size: 30, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.75)))
            .opacity(m.sichtbar ? 1 : 0)
            .animation(.easeOut(duration: 0.2), value: m.sichtbar)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@MainActor
final class TastenEinblendung {
    static let shared = TastenEinblendung()

    private var fenster: NSWindow?
    private var monitor: Any?
    private let modell = TastenModell()

    var fensterNummer: Int { fenster?.windowNumber ?? 0 }

    /// Zeigt gedrückte Kürzel unten im Aufnahmebereich. Gibt false zurück, wenn die Freigabe fehlt.
    func starte(ueber bereich: CGRect) -> Bool {
        beende()
        if !AXIsProcessTrusted() {
            let frage = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(frage)
            Kurzhinweis.zeige("Für eingeblendete Tasten „Bedienungshilfen“ erlauben – gilt ab der nächsten Aufnahme")
            return false
        }
        let breite = min(bereich.width, 700), hoehe: CGFloat = 90
        let rahmen = NSRect(x: bereich.midX - breite / 2, y: bereich.minY + 24, width: breite, height: hoehe)
        let w = NSWindow(contentRect: rahmen, styleMask: [.borderless], backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.level = .statusBar
        w.isReleasedWhenClosed = false
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        w.contentView = NSHostingView(rootView: TastenAnsicht(m: modell))
        w.orderFrontRegardless()
        fenster = w
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] e in
            MainActor.assumeIsolated { self?.zeige(e) }
        }
        return true
    }

    private func zeige(_ e: NSEvent) {
        guard let k = Kuerzel(event: e) else { return }
        let flags = k.flags
        let sonder = Kuerzel.sondertasten[Int(k.tastenCode)] != nil && Int(k.tastenCode) != 49   // Leertaste nicht
        // Nur Kürzel und Sondertasten – normales Tippen (z. B. Passwörter) bleibt unsichtbar
        guard flags.contains(.command) || flags.contains(.control) || flags.contains(.option) || sonder else { return }
        modell.text = k.text
        modell.sichtbar = true
        modell.nummer += 1
        let nummer = modell.nummer
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            if modell.nummer == nummer { modell.sichtbar = false }
        }
    }

    func beende() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        fenster?.orderOut(nil)
        fenster = nil
        modell.sichtbar = false
    }
}
