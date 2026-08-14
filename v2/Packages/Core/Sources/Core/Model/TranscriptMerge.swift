import Foundation

/// Meerdere opnames tot één opname samenvoegen, en meerdere opnames als één
/// stuk tekst uitschrijven.
///
/// Stond tot 14 augustus 2026 alleen in de iPhone-lijst
/// (`HistoryListiOSView.merge` en `.combinedText`). Nu gedeeld, zodat de Mac
/// exact hetzelfde doet: het is precies het soort logica dat stil uit elkaar
/// gaat lopen als je hem twee keer schrijft.
///
/// Bewust vrij van UI: de aanroeper levert de naam en de titels aan, want die
/// zijn per platform anders opgebouwd (de iPhone vertaalt ze, de Mac niet).
public enum TranscriptMerge {

    /// Voegt de opnames samen tot één nieuwe opname.
    ///
    /// Op tijdsvolgorde en niet op de volgorde van de lijst: samenvoegen is het
    /// herstellen van een gesprek dat in stukken is opgenomen, en met de lijst
    /// op "nieuwste eerst" zou het verhaal achterstevoren komen te staan.
    ///
    /// Geeft `nil` bij minder dan twee opnames, want dan valt er niets samen te
    /// voegen.
    ///
    /// - Parameters:
    ///   - naam: de naam van de nieuwe opname, inclusief eventuele toevoeging
    ///     als "(samengevoegd)". De aanroeper bepaalt de taal.
    ///   - nu: het tijdstip van de nieuwe opname. Meegegeven zodat een test hem
    ///     kan vastzetten.
    public static func merge(
        _ entries: [TranscriptEntry],
        naam: String,
        nu: Date = Date()
    ) -> TranscriptEntry? {
        guard entries.count >= 2 else { return nil }
        let ordered = sortedByTime(entries)
        guard let first = ordered.first else { return nil }

        let text = ordered
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")

        return TranscriptEntry(
            id: UUID().uuidString,
            text: text,
            createdAt: ISO8601DateFormatter().string(from: nu),
            name: naam,
            pinned: false,
            language: first.language,
            model: first.model,
            source: first.source,
            duration: ordered.reduce(0) { $0 + $1.duration },
            // Sprekerlabels lopen per opname vanaf "Spreker 1"; die zomaar
            // achter elkaar plakken zou twee verschillende mensen tot één
            // spreker maken.
            segments: []
        )
    }

    /// De opnames als één stuk leesbare tekst: titel, datum en tekst per
    /// opname, gescheiden door lege regels.
    ///
    /// Bewust zonder scheidingsstreepjes: dit gaat vaak rechtstreeks een mail of
    /// een notitie in en moet daar leesbaar zijn zonder opmaak.
    public static func combinedText(
        _ entries: [TranscriptEntry],
        locale: Locale,
        titel: (TranscriptEntry) -> String
    ) -> String {
        sortedByTime(entries).map { entry in
            var kop = titel(entry)
            if let date = entry.timestamp {
                kop += "\n" + date.formatted(
                    .dateTime.day().month(.abbreviated).year().hour().minute().locale(locale)
                )
            }
            return kop + "\n\n" + entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .joined(separator: "\n\n\n")
    }

    /// Oudste eerst. Opnames zonder tijdstempel gaan vooraan, want dan is er
    /// niets beters om op te sorteren en horen ze niet het verhaal te breken.
    public static func sortedByTime(_ entries: [TranscriptEntry]) -> [TranscriptEntry] {
        entries.sorted { ($0.timestamp ?? .distantPast) < ($1.timestamp ?? .distantPast) }
    }
}
