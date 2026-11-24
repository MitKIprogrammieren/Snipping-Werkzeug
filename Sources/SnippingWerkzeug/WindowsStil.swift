import SwiftUI
import AppKit

// Bausteine, die das Snipping Tool von Windows 11 möglichst genau nachbilden.

// MARK: - Titelzeile mit Windows-Fensterknöpfen

struct WindowsTitelZeile: View {
    @AppStorage(Schluessel.darstellung) private var darstellung: Darstellung = .windows

    var body: some View {
        let stil = Stil(darstellung: darstellung)
        ZStack {
            FensterZiehFlaeche()
            HStack(spacing: 0) {
                HStack(spacing: 10) {
                    AppLogo(groesse: 22)
                    Text("Snipping Werkzeug").font(.system(size: 12))
                }
                .padding(.leading, 14)
                .allowsHitTesting(false)
                Spacer()
                CaptionKnopf(art: .minimieren)
                CaptionKnopf(art: .maximieren)
                CaptionKnopf(art: .schliessen)
            }
        }
        .frame(height: 32)
        .background(stil.leiste)
    }
}

struct CaptionKnopf: View {
    enum Art { case minimieren, maximieren, schliessen }
    let art: Art

    @ObservedObject private var hover = HoverSpeicher.shared

    private var kennung: String { "caption-\(art)" }

    private var symbol: String {
        switch art {
        case .minimieren: return "minus"
        case .maximieren: return "square"
        case .schliessen: return "xmark"
        }
    }

    var body: some View {
        let ueber = hover.id == kennung
        Button {
            let w = Hauptfenster.shared.fenster
            switch art {
            case .minimieren: w?.miniaturize(nil)
            case .maximieren: w?.zoom(nil)
            case .schliessen: w?.performClose(nil)
            }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: art == .maximieren ? 10 : 12, weight: .light))
                .frame(width: 46, height: 32)
                .foregroundStyle(art == .schliessen && ueber ? Color.white : Color.primary)
                .background(
                    Rectangle().fill(ueber
                                     ? (art == .schliessen ? Color(red: 0.77, green: 0.17, blue: 0.11) : Color.primary.opacity(0.07))
                                     : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover.setze(kennung, $0) }
        .help(art == .minimieren ? "Minimieren" : (art == .maximieren ? "Maximieren" : "Schließen"))
    }
}

// MARK: - Befehlsleiste

struct WindowsLeiste: View {
    @ObservedObject var zustand: HauptZustand
    @ObservedObject private var k = KuerzelSpeicher.shared
    @AppStorage(Schluessel.darstellung) private var darstellung: Darstellung = .windows

    var body: some View {
        let stil = Stil(darstellung: darstellung)
        HStack(spacing: 4) {
            // Links: immer sichtbar
            HStack(spacing: 4) {
                NeuKnopf()
                WinArtUmschalter().padding(.leading, 4)
                WinModusMenue()
                WinVerzoegerungsMenue(mitText: zustand.editor == nil && zustand.video == nil)
            }
            .fixedSize()

            // Mitte: Werkzeuge – wird bei schmalem Fenster seitlich scrollbar statt abgeschnitten
            MittelLeiste {
                if let m = zustand.editor {
                    BearbeitungsWerkzeuge(m: m, mitRueckgaengig: false)
                }
                if zustand.video != nil {
                    LeistenKnopf(symbol: "scissors", hilfe: "Video kürzen") { zustand.videoKuerzen() }
                    LeistenKnopf(symbol: "photo.stack", hilfe: "Als GIF speichern") { zustand.alsGif() }
                }
            }

            // Rechts: immer sichtbar
            HStack(spacing: 4) {
            if let m = zustand.editor {
                RueckgaengigKnoepfe(m: m)
            }
            if zustand.editor != nil {
                LeistenKnopf(symbol: "pin", hilfe: k.hilfe("Anheften", .anheften)) { zustand.anheften() }
                LeistenKnopf(symbol: zustand.sendetGerade ? "ellipsis" : "paperplane",
                             hilfe: k.hilfe("An Meldewerk senden (WhatsApp)", .meldewerk)) { zustand.anMeldewerk() }
            }
            if zustand.hatInhalt {
                LeistenKnopf(symbol: "square.and.arrow.down", hilfe: k.hilfe("Speichern unter", .speichern)) { zustand.speichern() }
                LeistenKnopf(symbol: "doc.on.doc", hilfe: k.hilfe("Kopieren", .kopieren)) { zustand.kopieren() }
                LeistenKnopf(symbol: "square.and.arrow.up", hilfe: "Teilen") { zustand.teilen() }
            }
            LeistenKnopf(symbol: "clock.arrow.circlepath", hilfe: "Verlauf") { Verlauf.zeigeMenue() }
            MehrMenue(zustand: zustand)
            }
            .fixedSize()
        }
        .padding(.horizontal, 8)
        .frame(height: 48)
        .background(stil.leiste)
    }
}

struct NeuKnopf: View {
    @AppStorage(Schluessel.darstellung) private var darstellung: Darstellung = .windows
    @ObservedObject private var hover = HoverSpeicher.shared

    var body: some View {
        let stil = Stil(darstellung: darstellung)
        let ueber = hover.id == "neu"
        Button {
            AufnahmeSteuerung.shared.neu()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus").font(.system(size: 13, weight: .medium))
                Text("Neu").font(.system(size: 13, weight: .medium))
            }
            .padding(.horizontal, 14)
            .frame(height: 32)
            .foregroundStyle(stil.aufAkzent)
            .background(RoundedRectangle(cornerRadius: 4).fill(stil.akzent.opacity(ueber ? 0.9 : 1)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover.setze("neu", $0) }
        .help(KuerzelSpeicher.shared.hilfe("Neuer Ausschnitt", .neu))
    }
}

/// Umschalter Ausschnitt / Aufnahme wie im Windows-Original
struct WinArtUmschalter: View {
    @AppStorage(Schluessel.art) private var art: Art = .foto
    @AppStorage(Schluessel.darstellung) private var darstellung: Darstellung = .windows

    var body: some View {
        let stil = Stil(darstellung: darstellung)
        HStack(spacing: 0) {
            ForEach(Art.allCases) { a in
                Button {
                    art = a
                } label: {
                    Image(systemName: a.symbol)
                        .font(.system(size: 14))
                        .frame(width: 36, height: 28)
                        .foregroundStyle(a == art ? stil.akzent : Color.primary)
                        .background(Rectangle().fill(a == art ? stil.akzent.opacity(0.14) : Color.clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(a.name)
            }
        }
        .background(RoundedRectangle(cornerRadius: 4).fill(stil.karte))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(stil.linie, lineWidth: 1))
    }
}

struct WinModusMenue: View {
    @AppStorage(Schluessel.modus) private var modus: Modus = .rechteck

    var body: some View {
        HoverKnopf(kennung: "modus", hilfe: "Ausschnittmodus") {
            Klappmenue.zeige(Modus.allCases.map { mo in
                Klappmenue.Eintrag(titel: mo.langName, symbol: mo.symbol, an: mo == modus) {
                    UserDefaults.standard.set(mo.rawValue, forKey: Schluessel.modus)
                }
            })
        } inhalt: {
            HStack(spacing: 6) {
                Image(systemName: modus.symbol).font(.system(size: 16))
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
        }
    }
}

struct WinVerzoegerungsMenue: View {
    var mitText: Bool
    @AppStorage(Schluessel.verzoegerung) private var verzoegerung = 0

    private static func text(_ s: Int) -> String {
        s == 0 ? "Keine Verzögerung" : "\(s) Sekunden"
    }

    var body: some View {
        HoverKnopf(kennung: "verzoegerung", hilfe: "Verzögerung") {
            Klappmenue.zeige(VerzoegerungsMenue.optionen.map { s in
                Klappmenue.Eintrag(titel: Self.text(s), an: s == verzoegerung) {
                    UserDefaults.standard.set(s, forKey: Schluessel.verzoegerung)
                }
            })
        } inhalt: {
            HStack(spacing: 6) {
                Image(systemName: "clock").font(.system(size: 15))
                if mitText {
                    Text(Self.text(verzoegerung)).font(.system(size: 13))
                }
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
        }
    }
}

/// „…“ – weitere Optionen wie im Windows-Original
struct MehrMenue: View {
    @ObservedObject var zustand: HauptZustand

    var body: some View {
        LeistenKnopf(symbol: "ellipsis", hilfe: "Weitere Optionen") {
            var eintraege: [Klappmenue.Eintrag] = []
            eintraege.append(.init(titel: "Datei öffnen …", symbol: "doc") { zustand.oeffnen() })
            eintraege.append(.trenner)
            if zustand.video != nil {
                eintraege.append(.init(titel: "Im Finder zeigen", symbol: "folder") { zustand.imFinderZeigen() })
            }
            eintraege.append(.init(titel: "Speicherort öffnen", symbol: "folder.badge.gearshape") {
                if let ordner = try? Speicher.zielOrdner() { NSWorkspace.shared.open(ordner) }
            })
            eintraege.append(.trenner)
            eintraege.append(.init(titel: "Einstellungen", symbol: "gearshape") { EinstellungenFenster.shared.zeigen() })
            eintraege.append(.init(titel: "Über Snipping Werkzeug \(Einstellungen.version)", symbol: "info.circle") {
                NSApp.orderFrontStandardAboutPanel(nil)
            })
            Klappmenue.zeige(eintraege)
        }
    }
}

// MARK: - Hinweis unten rechts nach einem Ausschnitt

struct HinweisAnsicht: View {
    let vorschau: NSImage
    let titel: String
    let text: String
    let oeffnen: () -> Void
    let schliessen: () -> Void

    @AppStorage(Schluessel.darstellung) private var darstellung: Darstellung = .windows

    var body: some View {
        let stil = Stil(darstellung: darstellung)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                AppLogo(groesse: 20)
                Text("Snipping Werkzeug").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Button(action: schliessen) {
                    Image(systemName: "xmark").font(.system(size: 11))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Schließen")
            }
            HStack(spacing: 12) {
                Image(nsImage: vorschau)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 96, height: 64)
                    .background(Color.primary.opacity(0.04))
                    .overlay(Rectangle().strokeBorder(stil.linie, lineWidth: 1))
                VStack(alignment: .leading, spacing: 3) {
                    Text(titel).font(.system(size: 13, weight: .semibold))
                    Text(text).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .frame(width: 360)
        .background {
            if stil.istWindows {
                RoundedRectangle(cornerRadius: 8).fill(stil.karte)
            } else {
                VisualEffect(material: .popover).clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .overlay(RoundedRectangle(cornerRadius: stil.istWindows ? 8 : 12).strokeBorder(stil.linie, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture(perform: oeffnen)
    }
}

/// Mittlerer Teil der Leiste: mittig, wenn Platz ist – sonst seitlich scrollbar (Mausrad/Trackpad),
/// damit links „Neu“ und rechts „Kopieren“ nie abgeschnitten werden.
struct MittelLeiste<Inhalt: View>: View {
    @ViewBuilder let inhalt: () -> Inhalt

    var body: some View {
        GeometryReader { geo in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) { inhalt() }
                    .frame(minWidth: geo.size.width, minHeight: geo.size.height)
            }
        }
        .frame(minWidth: 40, maxWidth: .infinity)
    }
}
