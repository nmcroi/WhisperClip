import Foundation

/// Waarschuwt één keer per overschreden stap van 5 GB bewaarde audio, niet bij
/// elke start opnieuw. Niels wil alles laten staan maar wel een seintje als het
/// groot wordt (24 sep 2026).
public enum AudioStorageAlarm {
    /// Stapgrootte in bytes: 5 GB.
    public static let stepBytes: Int64 = 5 * 1_000_000_000
    public static let defaultsKey = "audio.storageWarnedStep"

    /// De stap (1 = 5 GB, 2 = 10 GB, ...) waar `bytes` in valt; 0 onder 5 GB.
    public static func step(for bytes: Int64) -> Int {
        Int(bytes / stepBytes)
    }

    /// Geeft de nieuwe stap terug als er gewaarschuwd moet worden, anders nil.
    /// Er wordt alleen gewaarschuwd als de stap hoger is dan de laatst gemelde;
    /// krimpt de map weer, dan zakt de gemelde stap mee zodat een volgende
    /// groei opnieuw een seintje geeft.
    public static func stepToWarn(bytes: Int64, lastWarnedStep: Int) -> (warn: Int?, remember: Int) {
        let current = step(for: bytes)
        if current > lastWarnedStep { return (current, current) }
        return (nil, min(lastWarnedStep, current))
    }

    /// Leesbare omvang, bijvoorbeeld "2,9 GB".
    public static func formatted(_ bytes: Int64, locale: Locale = .current) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useMB, .useGB]
        return formatter.string(fromByteCount: bytes)
    }

    /// Voert de controle uit tegen UserDefaults en geeft de waarschuwingstekst
    /// terug als er nu gewaarschuwd moet worden.
    public static func check(bytes: Int64, defaults: UserDefaults = .standard, locale: Locale = .current) -> String? {
        let last = defaults.integer(forKey: defaultsKey)
        let result = stepToWarn(bytes: bytes, lastWarnedStep: last)
        defaults.set(result.remember, forKey: defaultsKey)
        guard result.warn != nil else { return nil }
        return String(format: AudioCopy.text(.storageWarning, locale: locale), formatted(bytes, locale: locale))
    }
}
