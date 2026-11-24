import SwiftUI
import AppKit
import AVKit
import UniformTypeIdentifiers
import ImageIO
import Combine

@MainActor
final class HauptZustand: ObservableObject {
    enum Inhalt {
        case leer
        case bild(EditorModell)
        case video(URL)
    }

    @Published var inhalt: Inhalt = .leer {
        didSet {
            beobachteAenderungen()
            player.pause()
            if let v = video {
                player.replaceCurrentItem(with: AVPlayerItem(url: v))
            } else {
                player.replaceCurrentItem(with: nil)
            }
        }
    }
    @Published var meldung = ""
    @Published var kuerztGerade = false
    let player = AVPlayer()
    weak var playerView: AVPlayerView?

    private var kopierBeobachter: AnyCancellable?

    /// Wie „Änderungen automatisch kopieren“ bei Windows: nach jeder Bearbeitung
    /// (kurz verzögert) das bearbeitete Bild in die Zwischenablage legen.
    private func beobachteAenderungen() {
        kopierBeobachter = nil
        guard let m = editor else { return }
        kopierBeobachter = m.$elemente.map { _ in () }
            .merge(with: m.$bild.map { _ in () })
            .dropFirst(2)                       // die beiden Startwerte überspringen
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self, weak m] _ in
                MainActor.assumeIsolated {
                    guard Einstellungen.autoKopierenAenderungen, let m, let self else { return }
                    Ablage.kopiere(m.gerendert(textBeenden: false))
                    self.meldung = "Änderungen in die Zwischenablage kopiert"
                }
            }
    }

    var editor: EditorModell? {
        if case .bild(let m) = inhalt { return m }
        return nil
    }

    var video: URL? {
        if case .video(let url) = inhalt { return url }
        return nil
    }

    var hatInhalt: Bool { editor != nil || video != nil }

    func kopieren() {
        if let m = editor {
            Ablage.kopiere(m.gerendert())
            meldung = "In die Zwischenablage kopiert"
        } else if let v = video {
            Ablage.kopiereDatei(v)
            meldung = "Datei in die Zwischenablage kopiert"
        }
    }

    func speichern() {
        if let m = editor {
            if let url = Speicher.speichernUnter(bild: m.gerendert()) {
                meldung = "Gespeichert: \(url.lastPathComponent)"
            }
        } else if let v = video {
            if let url = Speicher.videoSpeichernUnter(v) {
                meldung = "Gespeichert: \(url.lastPathComponent)"
            }
        }
    }

    func teilen() {
        if let m = editor {
            do {
                Teilen.zeige(try Speicher.temporaeresPNG(m.gerendert()))
            } catch {
                Meldung.fehler(error)
            }
        } else if let v = video {
            Teilen.zeige(v)
        }
    }

    // MARK: Öffnen

    func oeffnen() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.image, .movie]
        p.allowsMultipleSelection = false
        p.prompt = "Öffnen"
        if p.runModal() == .OK, let url = p.url { laden(url) }
    }

    @discardableResult
    func laden(_ url: URL) -> Bool {
        let typ = UTType(filenameExtension: url.pathExtension)
        if typ?.conforms(to: .movie) == true || typ?.conforms(to: .audiovisualContent) == true {
            Hauptfenster.shared.zeigeVideo(url, meldung: "Geöffnet: \(url.lastPathComponent)")
            return true
        }
        guard let quelle = CGImageSourceCreateWithURL(url as CFURL, nil),
              let bild = CGImageSourceCreateImageAtIndex(quelle, 0, nil) else {
            meldung = "„\(url.lastPathComponent)“ ist kein Bild"
            return false
        }
        Hauptfenster.shared.zeigeBild(bild, meldung: "Geöffnet: \(url.lastPathComponent)")
        return true
    }

    // MARK: Video kürzen

    func videoKuerzen() {
        guard let pv = playerView, pv.canBeginTrimming else {
            meldung = "Dieses Video kann nicht gekürzt werden"
            return
        }
        pv.beginTrimming { [weak self] ergebnis in
            guard ergebnis == .okButton else { return }
            Task { @MainActor in await self?.exportiereGekuerzt() }
        }
    }

    private func exportiereGekuerzt() async {
        guard let quelle = video, let item = player.currentItem else { return }
        kuerztGerade = true
        defer { kuerztGerade = false }
        let dauer = (try? await item.asset.load(.duration)) ?? .positiveInfinity
        let von = item.reversePlaybackEndTime.isValid ? item.reversePlaybackEndTime : .zero
        let bis = item.forwardPlaybackEndTime.isValid ? item.forwardPlaybackEndTime : dauer
        guard let sitzung = AVAssetExportSession(asset: item.asset, presetName: AVAssetExportPresetPassthrough) else {
            meldung = "Kürzen nicht möglich"
            return
        }
        sitzung.timeRange = CMTimeRange(start: von, end: bis)
        let name = quelle.deletingPathExtension().lastPathComponent + " (gekürzt).mp4"
        let ziel = quelle.deletingLastPathComponent().appendingPathComponent(name)
        try? FileManager.default.removeItem(at: ziel)
        do {
            try await sitzung.export(to: ziel, as: .mp4)
            Hauptfenster.shared.zeigeVideo(ziel, meldung: "Gekürzt gespeichert: \(name)")
        } catch {
            Meldung.fehler(error)
        }
    }

    func anheften() {
        if let m = editor { AnheftVerwaltung.shared.anheften(m.gerendert()) }
    }

    func imFinderZeigen() {
        if let v = video { NSWorkspace.shared.activateFileViewerSelecting([v]) }
    }
}

@MainActor
final class Hauptfenster: NSObject, NSWindowDelegate {
    static let shared = Hauptfenster()

    let zustand = HauptZustand()
    private(set) var fenster: NSWindow?
    private var beobachter: NSObjectProtocol?
    private var mausrad: Any?
    private var letzteDarstellung: Darstellung?

    func zeigen() {
        let w = fenster ?? erstelle()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func zeigeBild(_ bild: CGImage, meldung: String, anzeigen: Bool = true) {
        zustand.inhalt = .bild(EditorModell(bild: bild))
        zustand.meldung = meldung
        if anzeigen { zeigeAktuellesBild() }
    }

    /// Öffnet das Fenster mit dem zuletzt aufgenommenen Ausschnitt (z. B. nach Klick auf den Hinweis).
    func zeigeAktuellesBild() {
        // Fenstergröße bleibt, wie du sie eingestellt hast – das Bild passt sich ans Fenster an
        zeigen()
    }

    func zeigeVideo(_ url: URL, meldung: String) {
        zustand.inhalt = .video(url)
        zustand.meldung = meldung
        zeigen()
    }

    private func erstelle() -> NSWindow {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.title = "Snipping Werkzeug"
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.titlebarSeparatorStyle = .none
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: HauptAnsicht(zustand: zustand))
        w.delegate = self
        fenster = w
        wendeStilAn(w)
        w.center()
        w.setFrameAutosaveName("Hauptfenster")

        // Mausrad dreht das Lineal
        mausrad = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] e in
            MainActor.assumeIsolated { () -> NSEvent? in
                guard let self, e.window === self.fenster,
                      let m = self.zustand.editor, m.lineal != nil else { return e }
                let delta = e.hasPreciseScrollingDeltas ? e.scrollingDeltaY / 3 : e.scrollingDeltaY * 3
                m.dreheLineal(um: delta)
                return nil
            }
        }

        // Stil sofort umstellen, wenn er in den Einstellungen geändert wird
        beobachter = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
                                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let w = self.fenster else { return }
                self.wendeStilAn(w)
            }
        }
        return w
    }

    private func wendeStilAn(_ w: NSWindow) {
        let d = Stil.aktuell.darstellung
        guard d != letzteDarstellung else { return }
        letzteDarstellung = d
        if d == .mac {
            // Leere Symbolleiste → hohe Titelleiste, Ampelknöpfe mittig neben Logo und Titel
            w.toolbar = NSToolbar(identifier: "SnippingWerkzeugLeiste")
            w.toolbarStyle = .unified
            w.minSize = NSSize(width: 720, height: 460)
        } else {
            w.toolbar = nil
            w.toolbarStyle = .automatic
            w.minSize = NSSize(width: 760, height: 460)
        }
        // Windows: Mac-Ampel ausblenden, eigene Knöpfe rechts
        for art in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            w.standardWindowButton(art)?.isHidden = (d == .windows)
        }
        if w.frame.width < w.minSize.width {
            var f = w.frame
            f.size.width = w.minSize.width
            w.setFrame(f, display: true)
        }
    }

    private func passeGroesseAn(_ w: NSWindow, an pixel: CGSize) {
        let faktor = w.backingScaleFactor
        let chrome: CGFloat = Stil.aktuell.istWindows ? (32 + 48 + 1 + 24) : (52 + 38 + 2 + 24)
        let bereich = (w.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var groesse = NSSize(width: pixel.width / faktor + 96, height: pixel.height / faktor + chrome + 96)
        groesse.width = min(max(groesse.width, w.minSize.width), bereich.width * 0.9)
        groesse.height = min(max(groesse.height, w.minSize.height), bereich.height * 0.9)

        var f = w.frame
        let oben = f.maxY
        f.size = groesse
        f.origin.y = oben - groesse.height
        if !bereich.contains(f) {
            f.origin = NSPoint(x: bereich.midX - groesse.width / 2, y: bereich.midY - groesse.height / 2)
        }
        w.setFrame(f, display: true)
    }
}

// MARK: - Ansichten

struct HauptAnsicht: View {
    @ObservedObject var zustand: HauptZustand
    @AppStorage(Schluessel.darstellung) private var darstellung: Darstellung = .windows

    var body: some View {
        let stil = Stil(darstellung: darstellung)
        VStack(spacing: 0) {
            if stil.istWindows {
                // Wie Windows 11: Titel links, Minimieren/Maximieren/Schließen rechts
                WindowsTitelZeile()
                WindowsLeiste(zustand: zustand)
                Rectangle().fill(stil.linie).frame(height: 1)
            } else {
                ZStack {
                    FensterZiehFlaeche()
                    HStack(spacing: 6) {
                        Spacer().frame(width: 74)
                        AppLogo(groesse: 24).allowsHitTesting(false)
                        Text("Snipping Werkzeug")
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                            .layoutPriority(-1)
                            .allowsHitTesting(false)
                        Trenner()
                        AufnahmeKnoepfe().fixedSize()
                        Spacer(minLength: 8)
                        AusgabeKnoepfe(zustand: zustand).fixedSize()
                    }
                    .padding(.trailing, 12)
                }
                .frame(height: 52)
                .background(.bar)

                if let m = zustand.editor {
                    Divider()
                    MittelLeiste { BearbeitungsWerkzeuge(m: m) }
                        .frame(height: 38)
                        .background(.bar)
                }
                Divider()
            }

            inhaltsBereich
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .dropDestination(for: URL.self) { urls, _ in
                    guard let url = urls.first else { return false }
                    return zustand.laden(url)
                }
                .overlay {
                    if zustand.kuerztGerade {
                        ProgressView("Video wird gekürzt …")
                            .padding(20)
                            .background(RoundedRectangle(cornerRadius: 10).fill(.regularMaterial))
                    }
                }

            StatusZeile(zustand: zustand)
        }
        .ignoresSafeArea()
        .frame(minWidth: 600, minHeight: 360)
    }

    @ViewBuilder
    private var inhaltsBereich: some View {
        switch zustand.inhalt {
        case .leer:
            LeerAnsicht()
        case .bild(let m):
            EditorFlaeche(m: m)
        case .video:
            VideoAnsicht(zustand: zustand)
        }
    }
}

struct AufnahmeKnoepfe: View {
    @AppStorage(Schluessel.darstellung) private var darstellung: Darstellung = .windows
    @AppStorage(Schluessel.art) private var art: Art = .foto
    @AppStorage(Schluessel.modus) private var modus: Modus = .rechteck
    @AppStorage(Schluessel.verzoegerung) private var verzoegerung = 0

    var body: some View {
        let stil = Stil(darstellung: darstellung)
        HStack(spacing: 6) {
            Button {
                AufnahmeSteuerung.shared.neu()
            } label: {
                Label("Neu", systemImage: "plus")
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 12)
                    .frame(height: stil.istWindows ? 30 : 26)
                    .foregroundStyle(stil.istWindows ? Color.white : Color.primary)
                    .background(
                        RoundedRectangle(cornerRadius: stil.eckenradius)
                            .fill(stil.istWindows ? stil.akzent : Color.primary.opacity(0.08))
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(KuerzelSpeicher.shared.hilfe("Neuer Ausschnitt", .neu))

            Picker("", selection: $art) {
                ForEach(Art.allCases) { a in
                    Image(systemName: a.symbol).help(a.name).tag(a)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Foto oder Video")

            Menu {
                ForEach(Modus.allCases) { mo in
                    Button {
                        modus = mo
                    } label: {
                        Label(mo == modus ? "\(mo.langName) ✓" : mo.langName, systemImage: mo.symbol)
                    }
                }
            } label: {
                Label(modus.name, systemImage: modus.symbol)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Ausschnittmodus")

            VerzoegerungsMenue(verzoegerung: $verzoegerung)
        }
    }
}

struct AusgabeKnoepfe: View {
    @ObservedObject var zustand: HauptZustand
    @ObservedObject private var k = KuerzelSpeicher.shared

    var body: some View {
        HStack(spacing: 2) {
            if zustand.hatInhalt {
                if zustand.video != nil {
                    LeistenKnopf(symbol: "scissors", hilfe: "Video kürzen") { zustand.videoKuerzen() }
                    LeistenKnopf(symbol: "folder", hilfe: "Im Finder zeigen") { zustand.imFinderZeigen() }
                }
                if zustand.editor != nil {
                    LeistenKnopf(symbol: "pin", hilfe: k.hilfe("Anheften (schwebt im Vordergrund)", .anheften)) { zustand.anheften() }
                }
                LeistenKnopf(symbol: "doc.on.doc", hilfe: k.hilfe("Kopieren", .kopieren)) { zustand.kopieren() }
                LeistenKnopf(symbol: "square.and.arrow.down", hilfe: k.hilfe("Speichern unter …", .speichern)) { zustand.speichern() }
                LeistenKnopf(symbol: "square.and.arrow.up", hilfe: "Teilen") { zustand.teilen() }
                Trenner()
            }
            LeistenKnopf(symbol: "clock.arrow.circlepath", hilfe: "Verlauf") { Verlauf.zeigeMenue() }
            LeistenKnopf(symbol: "gearshape", hilfe: "Einstellungen") { EinstellungenFenster.shared.zeigen() }
        }
    }
}

struct LeerAnsicht: View {
    @AppStorage(Schluessel.darstellung) private var darstellung: Darstellung = .windows
    @ObservedObject private var k = KuerzelSpeicher.shared

    private var hinweis: String {
        if darstellung == .windows {
            if let t = k.text(.ausschnittGlobal) {
                return "Drücken Sie \(t), um einen Ausschnitt zu starten."
            }
            return "Klicken Sie auf „Neu“, um einen Ausschnitt zu starten."
        }
        if let t = k.text(.ausschnittGlobal) {
            return "Drücke \(t) oder klicke auf „Neu“, um einen Ausschnitt oder eine Bildschirmaufnahme zu erstellen."
        }
        return "Klicke auf „Neu“, um einen Ausschnitt oder eine Bildschirmaufnahme zu erstellen."
    }

    var body: some View {
        let stil = Stil(darstellung: darstellung)
        VStack(spacing: 14) {
            if !stil.istWindows {
                Image(systemName: "scissors")
                    .font(.system(size: 46, weight: .light))
                    .foregroundStyle(stil.akzent)
                Text("Noch kein Ausschnitt")
                    .font(.title3.weight(.semibold))
            }
            Text(hinweis)
                .font(.system(size: stil.istWindows ? 14 : 13))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(stil.istWindows ? stil.leiste : stil.flaeche)
    }
}

struct StatusZeile: View {
    @ObservedObject var zustand: HauptZustand
    @AppStorage(Schluessel.darstellung) private var darstellung: Darstellung = .windows

    var body: some View {
        let stil = Stil(darstellung: darstellung)
        HStack(spacing: 8) {
            if let m = zustand.editor {
                BildGroesse(m: m)
            } else if let v = zustand.video {
                Text(v.lastPathComponent)
            } else {
                Text("Version \(Einstellungen.version)")
            }
            Spacer()
            Text(zustand.meldung)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 12)
        .frame(height: 24)
        .background(stil.istWindows ? stil.leiste : Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .top) { Rectangle().fill(stil.linie).frame(height: 1) }
    }
}

struct BildGroesse: View {
    @ObservedObject var m: EditorModell
    var body: some View {
        Text("\(m.bild.width) × \(m.bild.height) px")
    }
}


/// Videovorschau mit eingebauter Kürzen-Funktion von macOS (AVPlayerView)
struct VideoAnsicht: NSViewRepresentable {
    @ObservedObject var zustand: HauptZustand

    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView()
        v.player = zustand.player
        v.controlsStyle = .floating
        v.showsSharingServiceButton = false
        zustand.playerView = v
        return v
    }

    func updateNSView(_ v: AVPlayerView, context: Context) {
        if v.player !== zustand.player { v.player = zustand.player }
        zustand.playerView = v
    }
}
