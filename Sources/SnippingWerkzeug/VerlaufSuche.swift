import SwiftUI
import AppKit

// Verlauf durchsuchen: alle Ausschnitte als Raster, Suche im erkannten Text.

@MainActor
final class VerlaufModell: ObservableObject {
    static let shared = VerlaufModell()

    struct Eintrag: Identifiable {
        var id: URL { url }
        let url: URL
        let datum: Date
        var text: String?
        var vorschau: NSImage?
    }

    @Published var alle: [Eintrag] = []
    @Published var suche = ""
    @Published var status = ""
    private var indexiert = false
    private var ladeNummer = 0

    private static let datumsFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateStyle = .medium
        f.timeStyle = .short
        f.doesRelativeDateFormatting = true
        return f
    }()

    func datum(_ e: Eintrag) -> String { Self.datumsFormat.string(from: e.datum) }

    var gefiltert: [Eintrag] {
        let woerter = suche.lowercased().split(separator: " ").map(String.init)
        guard !woerter.isEmpty else { return alle }
        return alle.filter { e in
            let heu = ((e.text ?? "") + " " + datum(e)).lowercased()
            return woerter.allSatisfy { heu.contains($0) }
        }
    }

    /// Zeile im erkannten Text, in der der Suchbegriff steht
    func fundstelle(_ e: Eintrag) -> String? {
        guard let erstes = suche.lowercased().split(separator: " ").first, let text = e.text else { return nil }
        return text.split(separator: "\n").first { $0.lowercased().contains(erstes) }.map(String.init)
    }

    func laden() {
        ladeNummer += 1
        let nummer = ladeNummer
        alle = Verlauf.eintraege().map { e in
            Eintrag(url: e.url, datum: e.datum,
                    text: try? String(contentsOf: Verlauf.textDatei(e.url), encoding: .utf8))
        }
        Task {
            // Vorschaubilder nach und nach laden, damit das Fenster sofort da ist
            for i in alle.indices {
                guard nummer == ladeNummer, i < alle.count else { return }
                alle[i].vorschau = Verlauf.vorschau(alle[i].url, ziel: NSSize(width: 200, height: 120), pixel: 400)
                await Task.yield()
            }
            await textErkennen(nummer)
        }
    }

    /// Ältere Ausschnitte ohne erkannten Text nachträglich lesen
    private func textErkennen(_ nummer: Int) async {
        let fehlend = alle.indices.filter { alle[$0].text == nil }
        for (n, i) in fehlend.enumerated() {
            guard nummer == ladeNummer, i < alle.count else { return }
            status = "Lese Text … \(n + 1) von \(fehlend.count)"
            let url = alle[i].url
            guard let bild = Verlauf.lade(url) else { continue }
            let text = await Texterkennung.erkenne(bild)
            try? text.write(to: Verlauf.textDatei(url), atomically: true, encoding: .utf8)
            if i < alle.count, alle[i].url == url { alle[i].text = text }
        }
        status = ""
    }

    func oeffnen(_ e: Eintrag) {
        if let bild = Verlauf.lade(e.url) {
            Hauptfenster.shared.zeigeBild(bild, meldung: "Aus dem Verlauf geöffnet")
        }
    }

    func kopieren(_ e: Eintrag) {
        if let bild = Verlauf.lade(e.url) { Ablage.kopiere(bild) }
    }

    func loeschen(_ e: Eintrag) {
        Verlauf.loesche(e.url)
        alle.removeAll { $0.url == e.url }
    }
}

struct VerlaufAnsicht: View {
    @ObservedObject var m: VerlaufModell
    @AppStorage(Schluessel.darstellung) private var darstellung: Darstellung = .windows

    var body: some View {
        let stil = Stil(darstellung: darstellung)
        let liste = m.gefiltert
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Text in Ausschnitten suchen – z. B. eine IP, Fehlermeldung oder ein Datum", text: $m.suche)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                if !m.suche.isEmpty {
                    Button { m.suche = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
                Text(m.status.isEmpty ? "\(liste.count) von \(m.alle.count)" : m.status)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(stil.leiste)
            Divider()

            if liste.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: m.alle.isEmpty ? "clock.arrow.circlepath" : "magnifyingglass")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(.secondary)
                    Text(m.alle.isEmpty ? "Noch keine Ausschnitte im Verlauf" : "Nichts gefunden")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 14)], spacing: 14) {
                        ForEach(liste) { e in
                            kachel(e, stil: stil)
                        }
                    }
                    .padding(14)
                }
                .background(stil.flaeche)
            }
        }
        .frame(minWidth: 520, minHeight: 360)
    }

    private func kachel(_ e: VerlaufModell.Eintrag, stil: Stil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if let v = e.vorschau {
                    Image(nsImage: v).resizable().aspectRatio(contentMode: .fit)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 120)
            Text(m.datum(e)).font(.system(size: 12, weight: .medium))
            if let f = m.fundstelle(e) {
                Text(f)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: stil.eckenradius + 2).fill(stil.karte))
        .overlay(RoundedRectangle(cornerRadius: stil.eckenradius + 2).strokeBorder(stil.linie, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { m.oeffnen(e) }
        .help("Doppelklick öffnet im Editor")
        .contextMenu {
            Button("Im Editor öffnen") { m.oeffnen(e) }
            Button("Kopieren") { m.kopieren(e) }
            Button("Im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting([e.url]) }
            Divider()
            Button("Aus dem Verlauf löschen") { m.loeschen(e) }
        }
    }
}

@MainActor
final class VerlaufFenster {
    static let shared = VerlaufFenster()
    private var fenster: NSWindow?

    func zeigen() {
        if fenster == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 640),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable],
                             backing: .buffered, defer: false)
            w.title = "Verlauf"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: VerlaufAnsicht(m: VerlaufModell.shared))
            w.center()
            w.setFrameAutosaveName("Verlauf")
            fenster = w
        }
        VerlaufModell.shared.laden()
        fenster?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
