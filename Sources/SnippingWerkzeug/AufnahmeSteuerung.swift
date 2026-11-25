import SwiftUI
import AppKit
import ScreenCaptureKit

/// Steuert den ganzen Ablauf: Leiste → Verzögerung → Auswahl → Foto oder Video.
@MainActor
final class AufnahmeSteuerung {
    static let shared = AufnahmeSteuerung()

    private var leiste: SchwebePanel?
    private var auswahl: [(screen: NSScreen, fenster: AuswahlFenster, modell: AuswahlModell)] = []
    private var mausTimer: Timer?
    private var tastenMonitor: Any?
    private var escAktion: (() -> Void)?

    private var aufnahme: Videoaufnahme?
    private var steuerPanel: SchwebePanel?
    private var rahmenFenster: NSWindow?
    private var hauptWarSichtbar = false
    /// true, wenn über „Neu“ in der App gestartet (dann öffnet sich der Editor direkt, sonst kommt der Hinweis)
    var ausApp = false
    /// Nach der Aufnahme direkt anheften statt Hinweis/Editor
    private var anheftenNachAufnahme = false
    private var laeuft = false
    private var artFuerDiesenLauf: Art?

    var nimmtAuf: Bool { aufnahme != nil }

    // MARK: Einstieg

    /// „Neu“ aus Menü oder Werkzeugleiste: Windows startet sofort, Mac zeigt die Leiste.
    func neu() {
        ausApp = true
        anheftenNachAufnahme = false
        if Stil.aktuell.istWindows {
            starte(modus: Einstellungen.modus)
        } else {
            zeigeLeiste()
        }
    }

    func zeigeLeiste(art: Art? = nil, anheften: Bool = false) {
        if let art { UserDefaults.standard.set(art.rawValue, forKey: Schluessel.art) }
        if !laeuft && !nimmtAuf { anheftenNachAufnahme = anheften }
        if nimmtAuf {
            stoppeVideo(verwerfen: false)
            return
        }
        guard !laeuft else { return }
        if leiste != nil {
            // Gleiches Kürzel noch einmal schließt die Leiste, ein anderes (z. B. Video) lässt sie offen
            if art == nil { schliesseLeiste() }
            return
        }
        let panel = SchwebePanel.erstelle()
        panel.setzeInhalt(AufnahmeleisteAnsicht(
            starten: { [weak self] modus in self?.starte(modus: modus) },
            schliessen: { [weak self] in self?.schliesseLeiste() }
        ))
        panel.platziere(auf: Bildschirm.screenUnterMaus(), oben: Stil.aktuell.istWindows)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate()
        leiste = panel
        installiereEsc { [weak self] in self?.schliesseLeiste() }
    }

    func schliesseLeiste() {
        leiste?.orderOut(nil)
        leiste = nil
        entferneEsc()
    }

    func starte(modus: Modus, art: Art? = nil) {
        guard !laeuft, !nimmtAuf else { return }
        laeuft = true
        artFuerDiesenLauf = art
        schliesseLeiste()
        let haupt = Hauptfenster.shared.fenster
        hauptWarSichtbar = haupt?.isVisible ?? false
        haupt?.orderOut(nil)
        Task { await ablauf(modus: modus) }
    }

    // MARK: Ablauf

    private func ablauf(modus: Modus) async {
        let art = artFuerDiesenLauf ?? Einstellungen.art
        artFuerDiesenLauf = nil
        let v = Einstellungen.verzoegerung
        if v > 0 {
            await countdown(v)
        } else {
            // kurz warten, bis das Hauptfenster verschwunden ist
            try? await Task.sleep(for: .milliseconds(150))
        }

        do {
            let inhalt = try await Bildschirm.inhalt()
            let screen = Bildschirm.screenUnterMaus()

            if modus == .vollbild {
                guard let display = Bildschirm.display(fuer: screen, in: inhalt) else { throw Fehler.keinBildschirm }
                if art == .foto {
                    let bild = try await Bildschirm.aufnahmeDisplay(display, screen: screen, inhalt: inhalt)
                    laeuft = false
                    fertigBild(bild)
                } else {
                    starteVideoVollbild(display: display, screen: screen, inhalt: inhalt)
                }
                return
            }

            var bilder: [CGDirectDisplayID: CGImage] = [:]
            if art == .foto {
                for s in NSScreen.screens {
                    if let d = Bildschirm.display(fuer: s, in: inhalt) {
                        bilder[d.displayID] = try await Bildschirm.aufnahmeDisplay(d, screen: s, inhalt: inhalt)
                    }
                }
            }
            // Videos gibt es nur als Rechteck, Fenster oder Vollbild
            let m: Modus = (art == .video && !modus.fuerVideo) ? .rechteck : modus
            zeigeAuswahl(modus: m, art: art, inhalt: inhalt, bilder: bilder)
        } catch {
            abgebrochen()
            if Berechtigung.istFehlend(error) {
                Berechtigung.zeigeHinweis()
            } else {
                Meldung.fehler(error)
            }
        }
    }

    private func countdown(_ sekunden: Int) async {
        let modell = CountdownModell()
        let panel = SchwebePanel.erstelle()
        panel.hasShadow = false
        panel.setzeInhalt(CountdownAnsicht(m: modell))
        panel.zentriere(auf: Bildschirm.screenUnterMaus())
        panel.orderFrontRegardless()
        for i in stride(from: sekunden, to: 0, by: -1) {
            modell.zahl = i
            try? await Task.sleep(for: .seconds(1))
        }
        panel.orderOut(nil)
    }

    // MARK: Auswahl

    private func zeigeAuswahl(modus: Modus, art: Art, inhalt: SCShareableContent, bilder: [CGDirectDisplayID: CGImage]) {
        let alleFenster = Bildschirm.fensterGeordnet(inhalt)
        let stil = Stil.aktuell

        for screen in NSScreen.screens {
            guard let display = Bildschirm.display(fuer: screen, in: inhalt) else { continue }
            let bild = bilder[display.displayID]
            let flaeche = CGRect(origin: .zero, size: display.frame.size)
            let lokal: [(fenster: SCWindow, rahmen: CGRect)] = alleFenster.compactMap { w in
                let r = CGRect(x: w.frame.minX - display.frame.minX, y: w.frame.minY - display.frame.minY,
                               width: w.frame.width, height: w.frame.height)
                guard r.intersects(flaeche) else { return nil }
                return (fenster: w, rahmen: r)
            }
            let faktor = bild.map { CGFloat($0.width) / screen.frame.width } ?? screen.backingScaleFactor
            let abdunkeln = bild == nil ? 0.3 : (stil.istWindows ? 0.45 : 0.3)
            let modell = AuswahlModell(modus: modus, bild: bild, fenster: lokal,
                                       pixelFaktor: faktor, abdunkeln: abdunkeln)
            modell.fertig = { [weak self] ergebnis in
                self?.auswahlFertig(ergebnis, art: art, modus: modus, screen: screen, display: display, bild: bild, inhalt: inhalt)
            }
            let fenster = AuswahlFenster.erstelle(fuer: screen)
            fenster.contentView = NSHostingView(rootView: AuswahlAnsicht(m: modell))
            fenster.orderFrontRegardless()
            auswahl.append((screen: screen, fenster: fenster, modell: modell))
        }

        NSApp.activate()
        let unterMaus = Bildschirm.screenUnterMaus()
        auswahl.first { $0.screen == unterMaus }?.fenster.makeKey()
        NSCursor.crosshair.set()

        // Mausposition verfolgen (Fenster hervorheben, richtigen Bildschirm aktiv machen)
        mausTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.mausTick() }
        }
        installiereEsc { [weak self] in
            self?.schliesseAuswahl()
            self?.abgebrochen()
        }
    }

    private func mausTick() {
        let p = NSEvent.mouseLocation
        for eintrag in auswahl {
            let f = eintrag.screen.frame
            if NSMouseInRect(p, f, false) {
                if !eintrag.fenster.isKeyWindow { eintrag.fenster.makeKey() }
                eintrag.modell.hover(CGPoint(x: p.x - f.minX, y: f.maxY - p.y))
            } else if eintrag.modell.hoverIndex != nil {
                eintrag.modell.hoverIndex = nil
            }
        }
        NSCursor.crosshair.set()
    }

    private func schliesseAuswahl() {
        mausTimer?.invalidate()
        mausTimer = nil
        for eintrag in auswahl { eintrag.fenster.orderOut(nil) }
        auswahl.removeAll()
        entferneEsc()
        NSCursor.arrow.set()
    }

    private func auswahlFertig(_ ergebnis: AuswahlErgebnis, art: Art, modus: Modus, screen: NSScreen,
                               display: SCDisplay, bild: CGImage?, inhalt: SCShareableContent) {
        schliesseAuswahl()

        if art == .foto, modus == .scroll, case .rechteck(let r) = ergebnis {
            ScrollAufnahme.starte(bereich: r, screen: screen, display: display, inhalt: inhalt) { [weak self] ergebnis in
                guard let self else { return }
                self.laeuft = false
                if let ergebnis { self.fertigBild(ergebnis) } else { self.abgebrochen() }
            }
            return
        }

        if art == .foto, let bild {
            let f = CGFloat(bild.width) / screen.frame.width
            switch ergebnis {
            case .rechteck(let r):
                let px = CGRect(x: r.minX * f, y: r.minY * f, width: r.width * f, height: r.height * f).integral
                laeuft = false
                if let ausschnitt = bild.cropping(to: px) { fertigBild(ausschnitt) } else { abgebrochen() }
            case .freiform(let punkte):
                laeuft = false
                let px = punkte.map { CGPoint(x: $0.x * f, y: $0.y * f) }
                if let ausschnitt = Bildbearbeitung.freiform(bild, punkte: px) { fertigBild(ausschnitt) } else { abgebrochen() }
            case .fenster(let w):
                Task {
                    do {
                        let fensterBild = try await Bildschirm.aufnahmeFenster(w, faktor: screen.backingScaleFactor)
                        laeuft = false
                        fertigBild(fensterBild)
                    } catch {
                        abgebrochen()
                        Meldung.fehler(error)
                    }
                }
            }
            return
        }

        switch ergebnis {
        case .rechteck(let r):
            starteVideoBereich(r, screen: screen, display: display, inhalt: inhalt)
        case .fenster(let w):
            starteVideoFenster(w, screen: screen)
        case .freiform:
            abgebrochen()
        }
    }

    // MARK: Video

    private func starteVideoVollbild(display: SCDisplay, screen: NSScreen, inhalt: SCShareableContent) {
        let filter = SCContentFilter(display: display, excludingApplications: Bildschirm.eigeneApp(inhalt), exceptingWindows: [])
        let k = Bildschirm.videoKonfiguration()
        k.width = Bildschirm.gerade(CGFloat(display.width) * screen.backingScaleFactor)
        k.height = Bildschirm.gerade(CGFloat(display.height) * screen.backingScaleFactor)
        starteVideo(filter: filter, konfig: k, rahmen: nil, screen: screen, display: display, tastenBereich: screen.frame)
    }

    private func starteVideoBereich(_ r: CGRect, screen: NSScreen, display: SCDisplay, inhalt: SCShareableContent) {
        let filter = SCContentFilter(display: display, excludingApplications: Bildschirm.eigeneApp(inhalt), exceptingWindows: [])
        let k = Bildschirm.videoKonfiguration()
        k.sourceRect = r
        k.width = Bildschirm.gerade(r.width * screen.backingScaleFactor)
        k.height = Bildschirm.gerade(r.height * screen.backingScaleFactor)
        let global = CGRect(x: screen.frame.minX + r.minX, y: screen.frame.maxY - r.maxY,
                            width: r.width, height: r.height)
        starteVideo(filter: filter, konfig: k, rahmen: global, screen: screen, display: display, tastenBereich: global)
    }

    private func starteVideoFenster(_ w: SCWindow, screen: NSScreen) {
        let filter = SCContentFilter(desktopIndependentWindow: w)
        let k = Bildschirm.videoKonfiguration()
        k.width = Bildschirm.gerade(w.frame.width * screen.backingScaleFactor)
        k.height = Bildschirm.gerade(w.frame.height * screen.backingScaleFactor)
        let hauptHoehe = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let global = CGRect(x: w.frame.minX, y: hauptHoehe - w.frame.maxY,
                            width: w.frame.width, height: w.frame.height)
        starteVideo(filter: filter, konfig: k, rahmen: global, screen: screen)
    }

    private func starteVideo(filter: SCContentFilter, konfig: SCStreamConfiguration, rahmen: CGRect?, screen: NSScreen,
                             display: SCDisplay? = nil, tastenBereich: CGRect? = nil) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Aufnahme-\(UUID().uuidString).mp4")
        let neu = Videoaufnahme(url: url)
        aufnahme = neu
        Task {
            do {
                var filter = filter
                // Eingeblendete Tasten sollen mit aufs Video – alle anderen eigenen Fenster nicht
                if Einstellungen.tastenZeigen, let display, let bereich = tastenBereich,
                   TastenEinblendung.shared.starte(ueber: bereich) {
                    try? await Task.sleep(for: .milliseconds(150))
                    if let inhalt = try? await Bildschirm.inhalt(),
                       let w = inhalt.windows.first(where: { Int($0.windowID) == TastenEinblendung.shared.fensterNummer }) {
                        filter = SCContentFilter(display: display, excludingApplications: Bildschirm.eigeneApp(inhalt), exceptingWindows: [w])
                    }
                }
                try await neu.starte(filter: filter, konfig: konfig)
                laeuft = false
                zeigeSteuerung(rahmen: rahmen, screen: screen)
            } catch {
                aufnahme = nil
                abgebrochen()
                Meldung.fehler(error)
            }
        }
    }

    private func zeigeSteuerung(rahmen: CGRect?, screen: NSScreen) {
        let panel = SchwebePanel.erstelle()
        panel.setzeInhalt(AufnahmeSteuerAnsicht(
            start: Date(),
            stoppen: { [weak self] in self?.stoppeVideo(verwerfen: false) },
            verwerfen: { [weak self] in self?.stoppeVideo(verwerfen: true) }
        ))
        panel.platziere(auf: screen, oben: true)
        panel.orderFrontRegardless()
        steuerPanel = panel

        if let rahmen {
            let w = NSWindow(contentRect: rahmen.insetBy(dx: -3, dy: -3), styleMask: [.borderless],
                             backing: .buffered, defer: false)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = false
            w.ignoresMouseEvents = true
            w.level = .statusBar
            w.isReleasedWhenClosed = false
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            w.contentView = NSHostingView(rootView: RahmenAnsicht())
            w.orderFrontRegardless()
            rahmenFenster = w
        }
    }

    func stoppeVideo(verwerfen: Bool) {
        guard let a = aufnahme else { return }
        TastenEinblendung.shared.beende()
        steuerPanel?.orderOut(nil)
        steuerPanel = nil
        rahmenFenster?.orderOut(nil)
        rahmenFenster = nil
        Task {
            await a.stoppe()
            aufnahme = nil
            if verwerfen {
                try? FileManager.default.removeItem(at: a.url)
                abgebrochen()
            } else {
                fertigVideo(a.url)
            }
        }
    }

    // MARK: Ergebnisse

    private func fertigBild(_ bild: CGImage) {
        Verlauf.merke(bild)
        var teile: [String] = []
        if Einstellungen.autoKopieren {
            Ablage.kopiere(bild)
            teile.append("In die Zwischenablage kopiert")
        }
        if Einstellungen.autoSpeichern {
            do {
                let url = try Speicher.autoSpeichern(bild)
                teile.append("Gespeichert in „\(url.deletingLastPathComponent().lastPathComponent)“")
            } catch {
                teile.append("Automatisches Speichern fehlgeschlagen")
            }
        }
        let meldung = teile.joined(separator: " · ")
        if anheftenNachAufnahme {
            anheftenNachAufnahme = false
            Hauptfenster.shared.zeigeBild(bild, meldung: meldung, anzeigen: false)
            AnheftVerwaltung.shared.anheften(bild)
        } else if ausApp {
            // Aus der App gestartet → wie bei Windows direkt im Editor öffnen
            Hauptfenster.shared.zeigeBild(bild, meldung: meldung)
        } else {
            // Per Tastenkürzel gestartet → Hinweis unten rechts, Klick öffnet den Editor
            Hauptfenster.shared.zeigeBild(bild, meldung: meldung, anzeigen: false)
            zeigeHinweis(bild, kopiert: Einstellungen.autoKopieren)
        }
    }

    private var hinweis: SchwebePanel?
    private var hinweisNummer = 0

    private func zeigeHinweis(_ bild: CGImage, kopiert: Bool) {
        hinweis?.orderOut(nil)
        hinweisNummer += 1
        let nummer = hinweisNummer
        let panel = SchwebePanel.erstelle()
        panel.isMovableByWindowBackground = false
        panel.setzeInhalt(HinweisAnsicht(
            vorschau: NSImage(cgImage: bild, size: .zero),
            titel: kopiert ? "Ausschnitt in Zwischenablage kopiert" : "Ausschnitt erstellt",
            text: "Zum Markieren und Teilen hier klicken",
            oeffnen: { [weak self] in
                self?.schliesseHinweis()
                Hauptfenster.shared.zeigeAktuellesBild()
            },
            schliessen: { [weak self] in self?.schliesseHinweis() }
        ))
        let vf = Bildschirm.screenUnterMaus().visibleFrame
        panel.setFrameOrigin(NSPoint(x: vf.maxX - panel.frame.width - 16, y: vf.minY + 16))
        panel.orderFrontRegardless()
        hinweis = panel
        Task {
            try? await Task.sleep(for: .seconds(7))
            if hinweisNummer == nummer { schliesseHinweis() }
        }
    }

    private func schliesseHinweis() {
        hinweis?.orderOut(nil)
        hinweis = nil
    }

    private func fertigVideo(_ quelle: URL) {
        guard let werte = try? quelle.resourceValues(forKeys: [.fileSizeKey]),
              (werte.fileSize ?? 0) > 0 else {
            abgebrochen()
            Meldung.fehler(Fehler.aufnahmeLeer)
            return
        }
        var ziel = quelle
        var teile: [String] = []
        if Einstellungen.autoSpeichern {
            if let url = try? Speicher.autoSpeichernVideo(quelle) {
                ziel = url
                teile.append("Gespeichert in „\(url.deletingLastPathComponent().lastPathComponent)“")
            } else {
                teile.append("Automatisches Speichern fehlgeschlagen")
            }
        }
        if Einstellungen.autoKopieren {
            Ablage.kopiereDatei(ziel)
            teile.insert("Datei in die Zwischenablage kopiert", at: 0)
        }
        Hauptfenster.shared.zeigeVideo(ziel, meldung: teile.joined(separator: " · "))
    }

    private func abgebrochen() {
        laeuft = false
        anheftenNachAufnahme = false
        if hauptWarSichtbar { Hauptfenster.shared.zeigen() }
    }

    // MARK: Escape-Taste

    private func installiereEsc(_ aktion: @escaping () -> Void) {
        entferneEsc()
        escAktion = aktion
        tastenMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard e.keyCode == 53 else { return e }
            MainActor.assumeIsolated { self?.escAktion?() }
            return nil
        }
    }

    private func entferneEsc() {
        if let m = tastenMonitor { NSEvent.removeMonitor(m) }
        tastenMonitor = nil
        escAktion = nil
    }
}
