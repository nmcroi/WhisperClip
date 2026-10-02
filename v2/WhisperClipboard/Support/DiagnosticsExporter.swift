import Foundation
import WhisperShared

/// Produces a deliberately allowlisted report. Raw app logs and .ips reports
/// can contain application names, file paths or transcript text and are never
/// copied into the exported file.
enum DiagnosticsExporter {
    static func write(to destination: URL) throws {
        let report = makeReport()
        try report.write(to: destination, atomically: true, encoding: .utf8)
    }

    static func makeReport() -> String {
        let fm = FileManager.default
        let logURL = LaunchHealth.logsDirectory.appendingPathComponent("app.log")
        let log = (try? tail(of: logURL, maximumBytes: 256_000)) ?? Data()
        let events = sanitizedEvents(from: String(decoding: log, as: UTF8.self))
        let history = LaunchHealth.loadHistory()
        let ownCrashes = (try? fm.contentsOfDirectory(at: LaunchHealth.logsDirectory,
                                                     includingPropertiesForKeys: [.fileSizeKey], options: [])) ?? []
        let ownCrashCount = ownCrashes.filter {
            $0.lastPathComponent.hasPrefix("crash-") && $0.pathExtension == "txt"
                && ((try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 0
        }.count
        let diagnosticReports = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true)
        let appleReports = ((try? fm.contentsOfDirectory(at: diagnosticReports,
                                                        includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                                                        options: [])) ?? [])
            .filter { $0.pathExtension == "ips" &&
                ($0.lastPathComponent.hasPrefix("WhisperClip-") || $0.lastPathComponent.hasPrefix("Whisper Clipboard-")) }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .prefix(3)
        let crashSummaries = appleReports.compactMap { url -> String? in
            guard ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) <= 2_000_000,
                  let data = try? Data(contentsOf: url) else { return nil }
            return crashSummary(from: data)
        }

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "onbekend"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "onbekend"
        let microphoneChoice = SettingsStore.load().preferredMicrophoneUID.isEmpty ? "systeemstandaard" : "expliciet gekozen"
        var lines = [
            "WhisperClip-diagnostiek",
            "Gemaakt: \(ISO8601DateFormatter().string(from: Date()))",
            "Appversie: \(safeToken(version) ?? "onbekend") (\(safeToken(build) ?? "onbekend"))",
            "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Microfoonkeuze: \(microphoneChoice); beschikbare invoerbronnen: \(MicrophoneDevices.available().count)",
            "",
            "Privacy: alleen onderstaande categorieën en systeemvelden zijn geëxporteerd.",
            "Geen ruwe logs, paden, appnamen, audio, transcripties of sleutels.",
            "",
            "Laatste starts:"
        ]
        if history.isEmpty { lines.append("- Geen startgeschiedenis") }
        for entry in history.prefix(10) {
            let timestamp = safeTimestamp(entry.startedAt) ?? "tijd onbekend"
            let outcome = entry.outcome == "onverwacht" ? "onverwacht" : "schoon"
            let phase = ["idle", "recording", "transcribing", "inserting"].contains(entry.fase ?? "")
                ? " / \(entry.fase!)" : ""
            lines.append("- \(timestamp): \(outcome)\(phase)")
        }
        lines += ["", "Recente technische gebeurtenissen:"]
        lines += events.isEmpty ? ["- Geen herkende gebeurtenissen"] : events.map { "- \($0)" }
        lines += ["", "Eigen crashsignalen: \(ownCrashCount) niet-lege bestanden", "macOS-crashrapporten (maximaal 3):"]
        lines += crashSummaries.isEmpty ? ["- Geen leesbaar rapport gevonden"] : crashSummaries.map { "- \($0)" }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// Pure allowlist: it never prints an original log line, even if a future
    /// log writer adds private fields to a familiar event.
    static func sanitizedEvents(from rawLog: String) -> [String] {
        rawLog.split(separator: "\n").suffix(400).compactMap { line -> String? in
            let text = String(line)
            guard let close = text.firstIndex(of: "]"), text.first == "[",
                  let timestamp = safeTimestamp(String(text[text.index(after: text.startIndex)..<close])),
                  let marker = text.range(of: "LaunchHealth: ") else { return nil }
            let message = text[marker.upperBound...]
            let event: String
            if message.hasPrefix("Appstart ") { event = "appstart" }
            else if message.hasPrefix("Vorige run eindigde onverwacht") { event = "vorige run onverwacht" }
            else if message.hasPrefix("AudioEngine: formaatverschil") {
                event = "microfoonformaat gewijzigd" + formatPair(in: String(message))
            }
            else if message.hasPrefix("AudioEngine: onbruikbaar invoerformaat") {
                event = "microfoonformaat instabiel; opname niet gestart" + formatPair(in: String(message))
            }
            else if message.hasPrefix("AudioEngine: ObjC-exceptie") { event = "audio-exceptie opgevangen" }
            else if message.hasPrefix("AudioEngine: invoerformaat lezen mislukt") { event = "microfoonformaat kon niet worden gelezen" }
            else if message.hasPrefix("AudioEngine: klaarzetten mislukt") { event = "microfoonvoorbereiding mislukt" }
            else if message.hasPrefix("Invoegen: Cmd+V-gebeurtenis") { event = "plakgebeurtenis kon niet worden verzonden" }
            else if message.hasPrefix("Invoegen: keuze=") {
                event = message.contains("clipboardOnly") ? "invoegen overgeslagen; tekst op klembord" : "invoegen geprobeerd"
            }
            else if message.hasPrefix("Dictaat ") {
                if message.contains(": start;") { event = "dictaat: gestart" }
                else if message.contains(": microfoon actief") { event = "dictaat: microfoon actief" }
                else if message.contains(": stop;") { event = "dictaat: gestopt" }
                else if message.contains(": invoegresultaat=") {
                    event = message.contains("clipboardOnly") ? "dictaat: alleen klembord"
                        : message.contains("insertionFailed") ? "dictaat: invoegen mislukt" : "dictaat: invoegen gelukt"
                } else { return nil }
            }
            else if message.hasPrefix("Onafgevangen NSException") { event = "onafgevangen NSException" }
            else { return nil }
            return "\(timestamp) · \(event)"
        }.suffix(120).map { $0 }
    }

    /// macOS .ips files contain a metadata JSON line followed by a JSON body.
    /// Only fixed exception fields and symbol names without path characters pass.
    static func crashSummary(from data: Data) -> String? {
        let text = String(decoding: data, as: UTF8.self)
        let body = text.firstIndex(of: "\n").map { String(text[text.index(after: $0)...]) } ?? text
        guard let object = try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any] else { return nil }
        let exception = object["exception"] as? [String: Any] ?? [:]
        let timestamp = safeTimestamp(object["captureTime"] as? String ?? object["timestamp"] as? String ?? "") ?? "tijd onbekend"
        let kind = safeToken(exception["type"] as? String ?? "") ?? "type onbekend"
        let signal = safeToken(exception["signal"] as? String ?? "") ?? "signaal onbekend"
        let threads = object["threads"] as? [[String: Any]] ?? []
        let index = object["faultingThread"] as? Int ?? -1
        let frames = threads.indices.contains(index) ? (threads[index]["frames"] as? [[String: Any]] ?? []) : []
        let symbols = frames.prefix(5).compactMap { safeSymbol($0["symbol"] as? String) }
        return "\(timestamp) · \(kind) / \(signal)" + (symbols.isEmpty ? "" : " · " + symbols.joined(separator: " → "))
    }

    private static func tail(of url: URL, maximumBytes: UInt64) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let end = try handle.seekToEnd()
        try handle.seek(toOffset: end > maximumBytes ? end - maximumBytes : 0)
        return try handle.readToEnd() ?? Data()
    }

    private static func formatPair(in message: String) -> String {
        let pattern = #"hardware ([0-9]{1,6}) Hz/([0-9]{1,2}) ch, client ([0-9]{1,6}) Hz/([0-9]{1,2}) ch"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)) else { return "" }
        let values = (1...4).compactMap { index -> String? in
            guard let range = Range(match.range(at: index), in: message) else { return nil }
            return String(message[range])
        }
        guard values.count == 4 else { return "" }
        return " (hardware \(values[0]) Hz/\(values[1]) ch; client \(values[2]) Hz/\(values[3]) ch)"
    }

    private static func safeTimestamp(_ text: String) -> String? {
        guard (10...40).contains(text.count), text.first?.isNumber == true,
              text.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "0123456789-:.TZ+ ").contains($0) }) else { return nil }
        return text
    }

    private static func safeToken(_ text: String) -> String? {
        guard !text.isEmpty, text.count <= 40,
              text.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-").contains($0) }) else { return nil }
        return text
    }

    private static func safeSymbol(_ text: String?) -> String? {
        guard let text, !text.isEmpty, text.count <= 120,
              text.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.$<>:+()- ").contains($0) }) else { return nil }
        return text
    }
}
