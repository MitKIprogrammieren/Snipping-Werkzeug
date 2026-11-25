import AppKit
import ScreenCaptureKit
import AVFoundation
import CoreMedia

enum Bildschirm {
    static func displayID(of screen: NSScreen) -> CGDirectDisplayID {
        let nummer = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        return nummer?.uint32Value ?? 0
    }

    static func screenUnterMaus() -> NSScreen {
        let p = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    static func inhalt() async throws -> SCShareableContent {
        try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    }

    static func display(fuer screen: NSScreen, in inhalt: SCShareableContent) -> SCDisplay? {
        let id = displayID(of: screen)
        return inhalt.displays.first { $0.displayID == id }
    }

    /// Die eigene App wird bei allen Aufnahmen ausgeblendet.
    static func eigeneApp(_ inhalt: SCShareableContent) -> [SCRunningApplication] {
        let pid = ProcessInfo.processInfo.processIdentifier
        return inhalt.applications.filter { $0.processID == pid }
    }

    static func aufnahmeDisplay(_ display: SCDisplay, screen: NSScreen, inhalt: SCShareableContent) async throws -> CGImage {
        let filter = SCContentFilter(display: display, excludingApplications: eigeneApp(inhalt), exceptingWindows: [])
        let konfig = SCStreamConfiguration()
        let faktor = screen.backingScaleFactor
        konfig.width = Int(CGFloat(display.width) * faktor)
        konfig.height = Int(CGFloat(display.height) * faktor)
        konfig.showsCursor = false
        konfig.captureResolution = .best
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: konfig)
    }

    static func aufnahmeFenster(_ fenster: SCWindow, faktor: CGFloat) async throws -> CGImage {
        let filter = SCContentFilter(desktopIndependentWindow: fenster)
        let konfig = SCStreamConfiguration()
        konfig.width = Int(fenster.frame.width * faktor)
        konfig.height = Int(fenster.frame.height * faktor)
        konfig.showsCursor = false
        konfig.captureResolution = .best
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: konfig)
    }

    /// Normale App-Fenster, sortiert von vorne nach hinten.
    static func fensterGeordnet(_ inhalt: SCShareableContent) -> [SCWindow] {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        var reihenfolge: [CGWindowID: Int] = [:]
        for (i, eintrag) in info.enumerated() {
            if let nummer = eintrag[kCGWindowNumber as String] as? CGWindowID {
                reihenfolge[nummer] = i
            }
        }
        let pid = ProcessInfo.processInfo.processIdentifier
        return inhalt.windows
            .filter {
                $0.isOnScreen && $0.windowLayer == 0
                    && $0.frame.width > 40 && $0.frame.height > 40
                    && $0.owningApplication != nil
                    && $0.owningApplication?.processID != pid
            }
            .sorted { (reihenfolge[$0.windowID] ?? Int.max) < (reihenfolge[$1.windowID] ?? Int.max) }
    }

    static func videoKonfiguration() -> SCStreamConfiguration {
        let k = SCStreamConfiguration()
        k.showsCursor = Einstellungen.mauszeiger
        k.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        k.queueDepth = 6
        k.capturesAudio = Einstellungen.systemton
        k.excludesCurrentProcessAudio = true
        k.captureMicrophone = Einstellungen.mikrofon
        k.showMouseClicks = Einstellungen.klicksZeigen
        return k
    }

    /// H.264 mag gerade Pixelmaße.
    static func gerade(_ wert: CGFloat) -> Int {
        max(2, (Int(wert.rounded()) / 2) * 2)
    }
}

/// Nimmt mit ScreenCaptureKit direkt in eine MP4-Datei auf.
final class Videoaufnahme: NSObject, SCStreamDelegate, SCRecordingOutputDelegate, @unchecked Sendable {
    let url: URL
    private var stream: SCStream?
    private var ausgabe: SCRecordingOutput?
    private let lock = NSLock()
    private var fertig: CheckedContinuation<Void, Never>?

    init(url: URL) {
        self.url = url
    }

    func starte(filter: SCContentFilter, konfig: SCStreamConfiguration) async throws {
        let s = SCStream(filter: filter, configuration: konfig, delegate: self)
        let rk = SCRecordingOutputConfiguration()
        rk.outputURL = url
        rk.outputFileType = .mp4
        rk.videoCodecType = .h264
        let a = SCRecordingOutput(configuration: rk, delegate: self)
        try s.addRecordingOutput(a)
        try await s.startCapture()
        stream = s
        ausgabe = a
    }

    func stoppe() async {
        guard let s = stream else { return }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            setzeFertig(c)
            Task {
                do {
                    try await s.stopCapture()
                } catch {
                    self.melde()
                }
                // Sicherheitsnetz, falls der Delegate nicht meldet
                try? await Task.sleep(for: .seconds(5))
                self.melde()
            }
        }
        stream = nil
        ausgabe = nil
    }

    private func setzeFertig(_ c: CheckedContinuation<Void, Never>) {
        lock.lock()
        fertig = c
        lock.unlock()
    }

    private func melde() {
        lock.lock()
        let c = fertig
        fertig = nil
        lock.unlock()
        c?.resume()
    }

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) { melde() }
    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) { melde() }
    func stream(_ stream: SCStream, didStopWithError error: Error) { melde() }
}

/// Berechtigung „Bildschirm- und Systemaudioaufnahme“.
/// Geprüft wird über den echten Zugriff (ScreenCaptureKit) – die Vorab-Abfrage von macOS meldet
/// nach dem Einschalten oft noch „nein“, bis die App neu gestartet ist.
enum Berechtigung {
    static func istFehlend(_ fehler: Error) -> Bool {
        if let s = fehler as? SCStreamError, s.code == .userDeclined { return true }
        let ns = fehler as NSError
        if ns.domain == SCStreamErrorDomain && ns.code == SCStreamError.Code.userDeclined.rawValue { return true }
        return !CGPreflightScreenCaptureAccess()
    }

    @MainActor
    static func zeigeHinweis() {
        let a = NSAlert()
        a.messageText = "Bildschirmaufnahme erlauben"
        a.informativeText = """
        Öffne Systemeinstellungen → Datenschutz & Sicherheit → Bildschirm- und Systemaudioaufnahme \
        und schalte „Snipping Werkzeug“ ein. Danach die App neu starten.

        Ist der Schalter schon an und es klappt trotzdem nicht: Eintrag markieren, mit „–“ entfernen, \
        die App neu starten und beim nächsten Ausschnitt erneut erlauben. (Nach einem Update erkennt macOS \
        die App sonst manchmal nicht wieder.)
        """
        a.addButton(withTitle: "Systemeinstellungen öffnen")
        a.addButton(withTitle: "App neu starten")
        a.addButton(withTitle: "Abbrechen")
        switch a.runModal() {
        case .alertFirstButtonReturn:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        case .alertSecondButtonReturn:
            neuStarten()
        default:
            break
        }
    }

    @MainActor
    static func neuStarten() {
        let pfad = Bundle.main.bundlePath
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; open \"\(pfad)\""]
        try? p.run()
        NSApp.terminate(nil)
    }
}
