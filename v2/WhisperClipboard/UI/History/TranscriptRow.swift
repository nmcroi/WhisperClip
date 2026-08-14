import Core
import Foundation
import SwiftUI
import WhisperShared

/// A single history row: title (name or first words), relative Dutch date,
/// duration, source glyph, and (in full mode) a pin toggle. Used both in the
/// Home "recent" list and the full history list.
struct TranscriptRow: View {
    let entry: TranscriptEntry
    var compact = false
    var onTogglePin: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: TranscriptSourceStyle.icon(for: entry.source))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 3) {
                Text(TranscriptFormatting.title(for: entry))
                    .font(ThemeFont.ui(13, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(TranscriptFormatting.relativeDate(for: entry))
                    if entry.duration >= 1 {
                        Text("·")
                        Text(TranscriptFormatting.duration(entry.duration))
                    }
                }
                .font(ThemeFont.ui(11))
                .foregroundStyle(Theme.textTertiary)
            }

            Spacer(minLength: 8)

            if entry.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.accentText)
            }

            if !compact, let onTogglePin {
                Button(action: onTogglePin) {
                    Image(systemName: entry.pinned ? "pin.slash" : "pin")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .help(entry.pinned ? "Losmaken" : "Vastzetten")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

// MARK: - Formatting helpers

enum TranscriptFormatting {
    /// The row title: the entry name, else the first ~8 words of the text.
    static func title(for entry: TranscriptEntry) -> String {
        let name = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty && name.localizedCaseInsensitiveCompare("PLAUD-opname") != .orderedSame { return name }
        let words = entry.text
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .prefix(8)
        let joined = words.joined(separator: " ")
        if joined.isEmpty { return "Zonder titel" }
        return entry.text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count > 8
            ? joined + "…"
            : joined
    }

    /// Een echte datum en tijd in de lijstregel: "13 aug 2026 15:42".
    ///
    /// Hier stond "vandaag 14:32", "gisteren 09:10" en anders alleen "dd-MM",
    /// dus zonder jaartal. Niels zoekt op datum en moest daarvoor telkens een
    /// opname openen. Op de iPhone is dit op 13 augustus 2026 al rechtgezet
    /// (`TranscriptRowiOS.relativeDate`); dit is de Mac-tegenhanger.
    static func relativeDate(for entry: TranscriptEntry) -> String {
        guard let date = entry.timestamp else { return entry.createdAt }
        return date.formatted(
            .dateTime.day().month(.abbreviated).year().hour().minute()
                .locale(Locale(identifier: "nl_NL"))
        )
    }

    /// A longer date line for the detail view: "21-06-2026 10:27".
    static func fullDate(for entry: TranscriptEntry) -> String {
        guard let date = entry.timestamp else { return entry.createdAt }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nl_NL")
        formatter.dateFormat = "dd-MM-yyyy HH:mm"
        return formatter.string(from: date)
    }

    /// De duur mét eenheid: "42 s", "3:07 m", "1:02:15 u".
    ///
    /// Dit was kaal "3:07", wat naast een datum niet te lezen is: is dat drie
    /// minuten of drie uur? Zelfde vorm als op de iPhone (`DurationText`).
    static func duration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total < 60 {
            return "\(total) s"
        }
        if total < 3600 {
            return String(format: "%d:%02d m", total / 60, total % 60)
        }
        return String(format: "%d:%02d:%02d u", total / 3600, (total % 3600) / 60, total % 60)
    }

    /// A "m:ss" timecode for segment lists.
    static func timecode(_ seconds: Double) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
