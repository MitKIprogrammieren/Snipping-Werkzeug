import SwiftUI
import AppKit
@preconcurrency import Vision

// Automatisch schwärzen: findet sensible Daten per Texterkennung und macht sie unkenntlich.

enum SchwaerzKategorie: String, CaseIterable, Identifiable {
    case ip, mac, email, telefon, iban, passwort, token, url
    var id: String { rawValue }

    var name: String {
        switch self {
        case .ip: return "IP-Adressen"
        case .mac: return "MAC-Adressen"
        case .email: return "E-Mail-Adressen"
        case .telefon: return "Telefonnummern"
        case .iban: return "IBAN"
        case .passwort: return "Passwörter"
        case .token: return "Schlüssel und Tokens"
        case .url: return "Links"
        }
    }

    /// Links sind meist harmlos – standardmäßig nicht angehakt
    var standardAn: Bool { self != .url && self != .token }
}

struct SchwaerzFund: Identifiable {
    let id = UUID()
    let kategorie: SchwaerzKategorie
    let text: String
    let rahmen: CGRect           // Bildpixel, Ursprung oben links
}

enum Schwaerzer {
    /// Reihenfolge zählt: Spezielleres zuerst, Überschneidungen werden danach ausgefiltert.
    private static let muster: [(SchwaerzKategorie, NSRegularExpression, Int)] = {
        func r(_ s: String) -> NSRegularExpression {
            // swiftlint:disable:next force_try
            try! NSRegularExpression(pattern: s, options: [.caseInsensitive])
        }
        return [
            (.passwort, r(#"(?:passwort|password|kennwort|passphrase|pin|pw)\s*[:=]\s*(\S.*)"#), 1),
            (.mac, r(#"\b(?:[0-9a-f]{2}[:-]){5}[0-9a-f]{2}\b"#), 0),
            (.email, r(#"[a-z0-9._%+\-]+@[a-z0-9.\-]+\.[a-z]{2,}"#), 0),
            (.ip, r(#"\b(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)(?:/\d{1,2})?(?::\d{1,5})?\b"#), 0),
            (.ip, r(#"\b(?:[0-9a-f]{1,4}:){3,7}[0-9a-f]{1,4}\b"#), 0),
            (.iban, r(#"\b[a-z]{2}\d{2}(?: ?[a-z0-9]{4}){3,7}(?: ?[a-z0-9]{1,4})?\b"#), 0),
            (.telefon, r(#"(?:\+|00)[1-9][\d \-/()]{7,}\d"#), 0),
            (.telefon, r(#"\b0[1-9]\d{1,4}[ /\-]?\d{4,}\b"#), 0),
            (.url, r(#"https?://\S+"#), 0),
            (.token, r(#"\beyJ[a-z0-9_\-]{10,}(?:\.[a-z0-9_\-]+){0,2}"#), 0),
            (.token, r(#"\b(?=[a-z0-9_\-]*\d)(?=[a-z0-9_\-]*[a-z])[a-z0-9_\-]{20,}\b"#), 0),
        ]
    }()

    static func finde(in bild: CGImage) async -> [SchwaerzFund] {
        let breite = CGFloat(bild.width), hoehe = CGFloat(bild.height)
        return await withCheckedContinuation { (c: CheckedContinuation<[SchwaerzFund], Never>) in
            let einmal = Einmal()
            let anfrage = VNRecognizeTextRequest { req, _ in
                var funde: [SchwaerzFund] = []
                for beobachtung in (req.results as? [VNRecognizedTextObservation]) ?? [] {
                    guard let kandidat = beobachtung.topCandidates(1).first else { continue }
                    let zeile = kandidat.string
                    let ganz = NSRange(zeile.startIndex..., in: zeile)
                    for (kategorie, regex, gruppe) in muster {
                        for treffer in regex.matches(in: zeile, range: ganz) {
                            let bereich = treffer.range(at: gruppe)
                            guard bereich.location != NSNotFound,
                                  let r = Range(bereich, in: zeile),
                                  let box = try? kandidat.boundingBox(for: r) else { continue }
                            let bb = box.boundingBox      // normiert, Ursprung unten links
                            let rahmen = CGRect(x: bb.minX * breite, y: (1 - bb.maxY) * hoehe,
                                                width: bb.width * breite, height: bb.height * hoehe)
                            // Überschneidet sich das mit einem schon gefundenen Treffer? Dann überspringen.
                            let doppelt = funde.contains { alt in
                                let schnitt = alt.rahmen.intersection(rahmen)
                                return !schnitt.isNull && schnitt.width * schnitt.height > 0.5 * rahmen.width * rahmen.height
                            }
                            if !doppelt {
                                funde.append(SchwaerzFund(kategorie: kategorie, text: String(zeile[r]), rahmen: rahmen))
                            }
                        }
                    }
                }
                einmal.ausfuehren { c.resume(returning: funde) }
            }
            anfrage.recognitionLevel = .accurate
            anfrage.usesLanguageCorrection = false    // sonst „verbessert“ Vision Codes und Adressen
            anfrage.recognitionLanguages = ["de-DE", "en-US"]
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try VNImageRequestHandler(cgImage: bild, options: [:]).perform([anfrage])
                } catch {
                    einmal.ausfuehren { c.resume(returning: []) }
                }
            }
        }
    }
}

extension EditorModell {
    func sucheSensibleDaten() async {
        beendeTextBearbeitung()
        erkenntGerade = true
        let funde = await Schwaerzer.finde(in: gerendert())
        erkenntGerade = false
        schwaerzFunde = funde
        schwaerzAuswahl = Set(funde.filter { $0.kategorie.standardAn }.map(\.id))
        zeigeSchwaerzen = true
    }

    func schwaerzenAbbrechen() {
        zeigeSchwaerzen = false
        schwaerzFunde = []
        schwaerzAuswahl = []
    }

    func schwaerzeAuswahl() {
        let ziele = schwaerzFunde.filter { schwaerzAuswahl.contains($0.id) }
        guard !ziele.isEmpty else {
            schwaerzenAbbrechen()
            return
        }
        var neu = bild
        for f in ziele {
            // etwas Rand, damit keine Buchstabenreste stehen bleiben
            let rand = max(3, f.rahmen.height * 0.2)
            if let ergebnis = Bildbearbeitung.verpixle(neu, rahmen: f.rahmen.insetBy(dx: -rand, dy: -rand).integral, art: verpixelnArt) {
                neu = ergebnis
            }
        }
        ersetzeBild(neu)
        schwaerzenAbbrechen()
    }
}

/// Liste der Funde rechts oben im Editor
struct SchwaerzenAnsicht: View {
    @ObservedObject var m: EditorModell
    @AppStorage(Schluessel.darstellung) private var darstellung: Darstellung = .windows

    var body: some View {
        let stil = Stil(darstellung: darstellung)
        VStack(alignment: .leading, spacing: 8) {
            Text(m.schwaerzFunde.isEmpty ? "Keine sensiblen Daten gefunden" : "Sensible Daten gefunden")
                .font(.system(size: 13, weight: .semibold))
            if m.schwaerzFunde.isEmpty {
                Text("Die Texterkennung hat nichts gefunden, das nach Adressen, Passwörtern oder Schlüsseln aussieht. Bereiche kannst du mit „Verpixeln“ auch von Hand unkenntlich machen.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("\(m.schwaerzFunde.count) Treffer · rot markiert wird geschwärzt")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(SchwaerzKategorie.allCases) { k in
                            let funde = m.schwaerzFunde.filter { $0.kategorie == k }
                            if !funde.isEmpty {
                                Text(k.name)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 4)
                                ForEach(funde) { f in
                                    Toggle(isOn: Binding(
                                        get: { m.schwaerzAuswahl.contains(f.id) },
                                        set: { an in
                                            if an { m.schwaerzAuswahl.insert(f.id) } else { m.schwaerzAuswahl.remove(f.id) }
                                        }
                                    )) {
                                        Text(f.text)
                                            .font(.system(size: 12, design: .monospaced))
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 260)

                Picker("Art", selection: $m.verpixelnArt) {
                    Text("Pixel").tag(VerpixelnArt.pixel)
                    Text("Weich").tag(VerpixelnArt.weich)
                    Text("Balken").tag(VerpixelnArt.balken)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            HStack {
                Spacer()
                Button(m.schwaerzFunde.isEmpty ? "Schließen" : "Abbrechen") { m.schwaerzenAbbrechen() }
                    .keyboardShortcut(.cancelAction)
                if !m.schwaerzFunde.isEmpty {
                    Button("Schwärzen") { m.schwaerzeAuswahl() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(m.schwaerzAuswahl.isEmpty)
                }
            }
        }
        .padding(14)
        .frame(width: 290)
        .background(RoundedRectangle(cornerRadius: stil.istWindows ? 8 : 12).fill(stil.karte))
        .overlay(RoundedRectangle(cornerRadius: stil.istWindows ? 8 : 12).strokeBorder(stil.linie, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.15), radius: 8, y: 2)
        .padding(12)
    }
}
