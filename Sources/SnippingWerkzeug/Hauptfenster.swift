import SwiftUI
import AppKit
import AVKit

@MainActor
final class HauptZustand: ObservableObject {
    enum Inhalt {
        case leer
        case bild(EditorModell)
        case video(URL)
    }

    @Published var inhalt: Inhalt = .leer
    @Published var meldung = ""

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
    private var letzteDarstellung: Darstellung?

    func zeigen() {
        let w = fenster ?? erstelle()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func zeigeBild(_ bild: CGImage, meldung: String) {
        zustand.inhalt = .bild(EditorModell(bild: bild))
        zustand.meldung = meldung
        let w = fenster ?? erstelle()
        passeGroesseAn(w, an: CGSize(width: bild.width, height: bild.height))
        zeigen()
    }

    func zeigeVideo(_ url: URL, meldung: String) {
        zustand.inhalt = .video(url)
        zustand.meldung = meldung
        zeigen()
    }

    private func erstelle() -> NSWindow {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 620),
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
            w.minSize = NSSize(width: 1000, height: 460)
        } else {
            w.toolbar = nil
            w.toolbarStyle = .automatic
            w.minSize = NSSize(width: 860, height: 460)
        }
        if w.frame.width < w.minSize.width {
            var f = w.frame
            f.size.width = w.minSize.width
            w.setFrame(f, display: true)
        }
    }

    private func passeGroesseAn(_ w: NSWindow, an pixel: CGSize) {
        let faktor = w.backingScaleFactor
        let chrome: CGFloat = Stil.aktuell.istWindows ? (30 + 48 + 1 + 24) : (52 + 1 + 24)
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
                // Titelzeile wie in der Claude-App: Logo und Titel neben den Fensterknöpfen
                ZStack {
                    FensterZiehFlaeche()
                    HStack(spacing: 8) {
                        Spacer().frame(width: 72)
                        AppLogo()
                        Text("Snipping Werkzeug").font(.system(size: 12))
                        Spacer()
                    }
                    .allowsHitTesting(false)
                }
                .frame(height: 30)
                .background(stil.leiste)

                HStack(spacing: 6) {
                    AufnahmeKnoepfe()
                    Spacer(minLength: 12)
                    if let m = zustand.editor { BearbeitungsWerkzeuge(m: m) }
                    Spacer(minLength: 12)
                    AusgabeKnoepfe(zustand: zustand)
                }
                .padding(.horizontal, 10)
                .frame(height: 48)
                .background(stil.leiste)

                Rectangle().fill(stil.linie).frame(height: 1)
            } else {
                ZStack {
                    FensterZiehFlaeche()
                    HStack(spacing: 6) {
                        Spacer().frame(width: 74)
                        AppLogo(groesse: 18).allowsHitTesting(false)
                        Text("Snipping Werkzeug")
                            .font(.system(size: 13, weight: .semibold))
                            .allowsHitTesting(false)
                        Trenner()
                        AufnahmeKnoepfe()
                        Spacer(minLength: 8)
                        if let m = zustand.editor { BearbeitungsWerkzeuge(m: m) }
                        Spacer(minLength: 8)
                        AusgabeKnoepfe(zustand: zustand)
                    }
                    .padding(.trailing, 12)
                }
                .frame(height: 52)
                .background(.bar)

                Divider()
            }

            inhaltsBereich
                .frame(maxWidth: .infinity, maxHeight: .infinity)

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
        case .video(let url):
            VideoAnsicht(url: url)
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
            .help("Neuer Ausschnitt (⌘N, überall ⌃⇧S)")

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

    var body: some View {
        HStack(spacing: 2) {
            if zustand.hatInhalt {
                if zustand.video != nil {
                    LeistenKnopf(symbol: "folder", hilfe: "Im Finder zeigen") { zustand.imFinderZeigen() }
                }
                LeistenKnopf(symbol: "doc.on.doc", hilfe: "Kopieren (⇧⌘C)") { zustand.kopieren() }
                LeistenKnopf(symbol: "square.and.arrow.down", hilfe: "Speichern unter … (⌘S)") { zustand.speichern() }
                LeistenKnopf(symbol: "square.and.arrow.up", hilfe: "Teilen") { zustand.teilen() }
                Trenner()
            }
            LeistenKnopf(symbol: "gearshape", hilfe: "Einstellungen") { EinstellungenFenster.shared.zeigen() }
        }
    }
}

struct LeerAnsicht: View {
    @AppStorage(Schluessel.darstellung) private var darstellung: Darstellung = .windows

    var body: some View {
        let stil = Stil(darstellung: darstellung)
        VStack(spacing: 14) {
            Image(systemName: "scissors")
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(stil.akzent)
            Text("Noch kein Ausschnitt")
                .font(.title3.weight(.semibold))
            Text("Drücke ⌃⇧S oder klicke auf „Neu“, um einen Ausschnitt oder eine Bildschirmaufnahme zu erstellen.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(stil.flaeche)
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

struct VideoAnsicht: View {
    let url: URL
    @State private var player = AVPlayer()

    var body: some View {
        VideoPlayer(player: player)
            .onAppear { lade(url) }
            .onChange(of: url) { _, neu in lade(neu) }
            .onDisappear { player.pause() }
    }

    private func lade(_ u: URL) {
        player.replaceCurrentItem(with: AVPlayerItem(url: u))
    }
}
