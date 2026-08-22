import Darwin
import Foundation
import WhisperShared

/// Legt vast of de vorige run van de app netjes is afgesloten, en houdt een
/// korte geschiedenis van de laatste tien starts bij.
///
/// Achtergrond: op deze Mac verdwijnen macOS-crashrapporten voor WhisperClip
/// (geen enkele `.ips`, ook niet van bekende crashes), dus de app moet zelf
/// onthouden of zijn vorige run netjes eindigde (22 augustus 2026).
enum LaunchHealth {

    /// Vereenvoudigde fase voor de marker en de geschiedenis. Los van
    /// `DictationController.Phase`, die kent meer tussenstappen (`preparing`,
    /// `paused`, `finished`); hier gaat het alleen om wat relevant is bij een
    /// onverwachte afsluiting.
    enum Fase: String, Sendable {
        case idle
        case recording
        case transcribing
        case inserting
    }

    // MARK: - Bestandslocaties

    /// Marker die alleen bestaat terwijl de app draait: `AppSupport.baseDirectory`
    /// is dezelfde map die de watched-folder- en PLAUD-stores al gebruiken.
    private static var markerURL: URL {
        AppSupport.baseDirectory.appendingPathComponent("running.marker")
    }

    private static var historyURL: URL {
        AppSupport.baseDirectory.appendingPathComponent("launch-history.json")
    }

    /// Er is momenteel geen eigen schrijver voor `app.log` in de app (gecheckt:
    /// geen enkele plek schrijft er al naartoe), dus deze klasse schrijft er
    /// zelf naartoe met `FileHandle` in append-modus.
    static var logsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Whisper Clipboard", isDirectory: true)
    }

    private static var appLogURL: URL {
        logsDirectory.appendingPathComponent("app.log")
    }

    /// Starttijd van de huidige run, gezet bij `recordLaunch()`. Blijft
    /// hetzelfde zolang de app draait, ook als `setPhase` de marker herschrijft.
    /// Alle schrijvers (`recordLaunch`, `setPhase`) draaien op de main actor
    /// (aangeroepen vanuit `AppDelegate` en `DictationController`, beide
    /// `@MainActor`), dus de externe synchronisatie is al geregeld.
    nonisolated(unsafe) private static var startedAt = isoNow()

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "onbekend"
    }

    private static var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "onbekend"
    }

    private static func isoNow() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    /// Voor bestandsnamen: dubbele punten uit de ISO-tijd zijn op APFS geen
    /// probleem, maar leveren in Finder een wat rare weergave op. Vervangen
    /// door `-` houdt de bestandsnaam leesbaar.
    private static func fileSafe(_ isoTimestamp: String) -> String {
        isoTimestamp.replacingOccurrences(of: ":", with: "-")
    }

    // MARK: - Start

    /// Zo vroeg mogelijk aanroepen, in `applicationDidFinishLaunching` vóór de
    /// rest van de opbouw. Kijkt of de vorige run een marker heeft
    /// achtergelaten (= onverwacht gestopt), logt dat naar het applog, werkt de
    /// geschiedenis bij, schrijft een verse marker voor deze run en
    /// installeert de crash-handlers.
    static func recordLaunch() {
        startedAt = isoNow()

        let fm = FileManager.default
        let markerAanwezig = fm.fileExists(atPath: markerURL.path)
        let markerInhoud = markerAanwezig ? try? String(contentsOf: markerURL, encoding: .utf8) : nil
        let outcome = LaunchHealthEvaluator.evaluate(markerAanwezig: markerAanwezig, markerInhoud: markerInhoud)

        var faseVoorGeschiedenis: String?
        if case .onverwacht(let fase) = outcome {
            faseVoorGeschiedenis = fase
            appendLog("Vorige run eindigde onverwacht tijdens fase '\(fase)': de marker stond nog klaar bij deze start.")
        }

        appendHistory(
            LaunchHistoryEntry(
                startedAt: startedAt,
                version: appVersion,
                outcome: outcome == .schoon ? "schoon" : "onverwacht",
                fase: faseVoorGeschiedenis
            )
        )

        writeMarker(fase: .idle)
        installCrashHandlers()
    }

    /// Nette afsluiting: marker weg, zodat de volgende start "schoon" ziet.
    /// Vanuit `applicationWillTerminate` in `AppDelegate`.
    static func applicationWillTerminate() {
        try? FileManager.default.removeItem(at: markerURL)
    }

    /// Bijgewerkt op elke faseovergang in `DictationController`, onder andere
    /// vlak vóórdat de microfoon live gaat en vlak vóór het invoegen. Een
    /// synchrone bestandsschrijf op de main actor hoort daar niet tussen, dus
    /// dit loopt via `markerQueue`. Bij een crash mag de marker een fractie
    /// achterlopen op de echte fase, dat is voor dit doel prima (review
    /// 22 augustus 2026).
    static func setPhase(_ fase: Fase) {
        markerQueue.async {
            writeMarker(fase: fase)
        }
    }

    /// Seriële achtergrondqueue voor `setPhase`, zodat opeenvolgende
    /// faseovergangen elkaar niet inhalen en het marker-bestand nooit
    /// gelijktijdig vanuit twee threads wordt herschreven.
    private static let markerQueue = DispatchQueue(label: "nl.nielscroiset.whisperclip.marker")

    // MARK: - Marker lezen/schrijven

    private static func writeMarker(fase: Fase) {
        let contents = "started=\(startedAt)\nversion=\(appVersion)\nbuild=\(appBuild)\nfase=\(fase.rawValue)\n"
        let fm = FileManager.default
        try? fm.createDirectory(at: AppSupport.baseDirectory, withIntermediateDirectories: true)
        try? contents.write(to: markerURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Applog

    private static func appendLog(_ regel: String) {
        let fm = FileManager.default
        try? fm.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: appLogURL.path) {
            fm.createFile(atPath: appLogURL.path, contents: nil)
        }
        guard let data = "[\(isoNow())] LaunchHealth: \(regel)\n".data(using: .utf8) else { return }
        guard let handle = try? FileHandle(forWritingTo: appLogURL) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            // Best-effort: een niet-schrijfbare logmap mag de app niet breken.
        }
    }

    // MARK: - Geschiedenis

    private static func appendHistory(_ entry: LaunchHistoryEntry) {
        var history: [LaunchHistoryEntry] = []
        if let data = try? Data(contentsOf: historyURL),
           let decoded = try? JSONDecoder().decode([LaunchHistoryEntry].self, from: data) {
            history = decoded
        }
        history = LaunchHealthEvaluator.appending(entry, to: history)
        guard let data = try? JSONEncoder().encode(history) else { return }
        try? FileManager.default.createDirectory(at: AppSupport.baseDirectory, withIntermediateDirectories: true)
        try? data.write(to: historyURL, options: .atomic)
    }

    /// Voor Instellingen ▸ Algemeen: de laatste tien starts, nieuwste eerst.
    static func loadHistory() -> [LaunchHistoryEntry] {
        guard let data = try? Data(contentsOf: historyURL),
              let decoded = try? JSONDecoder().decode([LaunchHistoryEntry].self, from: data) else { return [] }
        return decoded
    }

    // MARK: - Crash-handlers

    /// Installeert de vangnetten voor onafgevangen exceptions en fatale
    /// signalen. `NSSetUncaughtExceptionHandler` draait niet in signal-context
    /// en mag dus gewoon Swift-code (het applog) aanroepen; de signal-handlers
    /// zelf mogen dat niet, zie `whisperClipCrashHandler` onderaan dit bestand.
    private static func installCrashHandlers() {
        NSSetUncaughtExceptionHandler { exception in
            let regel = "Onafgevangen NSException: \(exception.name.rawValue): \(exception.reason ?? "geen reden")\n"
                + exception.callStackSymbols.joined(separator: "\n")
            LaunchHealth.appendLog(regel)
        }

        let fm = FileManager.default
        try? fm.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        let crashURL = logsDirectory.appendingPathComponent("crash-\(fileSafe(startedAt)).txt")
        fm.createFile(atPath: crashURL.path, contents: nil)

        // Open vóór de crash, want `open()` binnen de handler zelf zou niet
        // async-signal-veilig zijn.
        whisperCrashFD = crashURL.path.withCString { open($0, O_WRONLY | O_APPEND) }

        // Swift-globals met een niet-triviale initializer worden lazy en
        // thread-safe (`swift_once`) aangemaakt bij de eerste lezing. Zonder
        // deze regel is die eerste lezing de aanroep ín de signal-handler, en
        // dan doet `swift_once` daar alsnog een `malloc`, precies wat de
        // handler moet vermijden. Hier, buiten de handler, aanraken forceert
        // de allocatie vooraf (bevinding review 22 augustus 2026).
        _ = whisperFrameBuffer

        // Vooraf als C-string klaarzetten: `unlink()` in de SIGTERM-handler
        // mag geen Swift-string-naar-C-string-conversie meer doen.
        whisperMarkerPath = strdup(markerURL.path)

        for sig in whisperHandledSignals {
            signal(sig, whisperClipCrashHandler)
        }
        signal(SIGTERM, whisperClipTerminateHandler)
    }
}

// MARK: - LaunchHistoryEntry

/// Eén regel in `launch-history.json`: wat er van een start bekend is.
struct LaunchHistoryEntry: Codable, Equatable {
    var startedAt: String
    var version: String
    /// "schoon" of "onverwacht".
    var outcome: String
    /// Alleen gezet wanneer `outcome == "onverwacht"`.
    var fase: String?
}

// MARK: - LaunchHealthEvaluator

/// De pure logica achter `LaunchHealth`, zonder bestandssysteem, zodat ze los
/// getest kan worden.
enum LaunchHealthEvaluator {

    enum Outcome: Equatable {
        case schoon
        case onverwacht(fase: String)
    }

    /// Leidt uit de marker-toestand af of de vorige run schoon eindigde. Een
    /// aanwezige marker zonder leesbare `fase=`-regel telt als "onverwacht,
    /// fase onbekend" in plaats van als schoon: de marker had immers verwijderd
    /// moeten zijn bij een nette afsluiting.
    static func evaluate(markerAanwezig: Bool, markerInhoud: String?) -> Outcome {
        guard markerAanwezig else { return .schoon }
        return .onverwacht(fase: fase(from: markerInhoud) ?? "onbekend")
    }

    private static func fase(from markerInhoud: String?) -> String? {
        guard let markerInhoud else { return nil }
        for line in markerInhoud.split(separator: "\n") {
            if line.hasPrefix("fase=") {
                return String(line.dropFirst("fase=".count))
            }
        }
        return nil
    }

    /// Zet `entry` vooraan en houdt de lijst op maximaal tien, nieuwste eerst.
    static func appending(_ entry: LaunchHistoryEntry, to history: [LaunchHistoryEntry]) -> [LaunchHistoryEntry] {
        var updated = [entry] + history
        if updated.count > 10 {
            updated.removeLast(updated.count - 10)
        }
        return updated
    }
}

// MARK: - Async-signal-veilige crash-handler

// Alles hieronder staat bewust als kale C-globals buiten `LaunchHealth`: een
// signal-handler mag geen Swift-allocaties doen (geen Array, geen String-
// interpolatie, geen ARC-retain van een class), dus de bestandsdescriptor en
// de framebuffer voor `backtrace` zijn vooraf, buiten de handler, aangemaakt.

private let whisperHandledSignals: [Int32] = [SIGABRT, SIGSEGV, SIGBUS, SIGTRAP, SIGILL]

/// Vooraf geopende bestandsdescriptor voor het huidige crash-bestand, gezet
/// door `installCrashHandlers()`.
nonisolated(unsafe) private var whisperCrashFD: Int32 = -1

private let whisperMaxFrames = 64
/// Statische buffer voor `backtrace()`: vooraf toegewezen, zodat de handler
/// zelf niets hoeft te allocaties.
nonisolated(unsafe) private let whisperFrameBuffer =
    UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: whisperMaxFrames)

/// Pad van `running.marker` als C-string, vooraf gevuld met `strdup` in
/// `installCrashHandlers()`. Een kale SIGTERM (`kill`, geforceerde herstart,
/// een watchdog) loopt niet door `applicationWillTerminate`, dus zonder dit
/// bleef de marker staan en meldde de volgende start onterecht "onverwacht
/// gestopt" (bevinding review 22 augustus 2026).
nonisolated(unsafe) private var whisperMarkerPath: UnsafeMutablePointer<CChar>?

@_cdecl("whisperClipCrashHandler")
func whisperClipCrashHandler(_ sig: Int32) {
    if whisperCrashFD >= 0 {
        let prefix: StaticString
        switch sig {
        case SIGABRT: prefix = "WhisperClip crash: SIGABRT\n"
        case SIGSEGV: prefix = "WhisperClip crash: SIGSEGV\n"
        case SIGBUS: prefix = "WhisperClip crash: SIGBUS\n"
        case SIGTRAP: prefix = "WhisperClip crash: SIGTRAP\n"
        case SIGILL: prefix = "WhisperClip crash: SIGILL\n"
        default: prefix = "WhisperClip crash: onbekend signaal\n"
        }
        prefix.withUTF8Buffer { buf in
            _ = write(whisperCrashFD, buf.baseAddress, buf.count)
        }
        let count = backtrace(whisperFrameBuffer, Int32(whisperMaxFrames))
        backtrace_symbols_fd(whisperFrameBuffer, count, whisperCrashFD)
    }

    // Oorspronkelijke handler herstellen en het signaal opnieuw laten afgaan,
    // zodat macOS zijn eigen afhandeling nog krijgt.
    signal(sig, SIG_DFL)
    raise(sig)
}

/// Aparte handler voor een kale SIGTERM (geen crash, geen backtrace nodig):
/// haalt de marker weg met `unlink(2)` zodat de volgende start niet ten
/// onrechte "onverwacht gestopt" meldt, en geeft het signaal daarna door.
/// `unlink` is async-signal-veilig; er wordt geen Swift-allocatie gedaan.
@_cdecl("whisperClipTerminateHandler")
func whisperClipTerminateHandler(_ sig: Int32) {
    if let path = whisperMarkerPath {
        _ = unlink(path)
    }
    signal(sig, SIG_DFL)
    raise(sig)
}
