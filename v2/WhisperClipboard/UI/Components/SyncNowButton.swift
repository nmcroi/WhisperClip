import SwiftUI
import WhisperShared

/// Eén knop "Synchroniseer met iCloud" voor de hele Mac-app.
///
/// Stond tot 22 augustus 2026 alleen rechtsboven in Geschiedenis, als los
/// stukje code in `HistoryListView`. Niels miste hem op Home, waar hij zit
/// als hij net heeft gedicteerd en wil zien of zijn iPhone al mee is. Nu één
/// component, op Home mét tekst (daar moet hij opvallen) en in Geschiedenis
/// als icoon (daar is de kop al vol).
///
/// Gedrag: draait zolang de synchronisatie loopt, grijs wanneer er niets te
/// synchroniseren valt (schakelaar uit, of deze build draagt het CloudKit-recht
/// niet), en de volledige status als tooltip. De engine kent geen eigen
/// "bezig"-status, vandaar de lokale vlag.
struct SyncNowButton: View {
    let historySync: HistorySyncEngine
    /// Met tekst ernaast (Home) of alleen het icoon (Geschiedenis).
    var showsLabel = false

    @State private var isSyncing = false

    var body: some View {
        Button {
            guard !isSyncing else { return }
            isSyncing = true
            Task {
                await historySync.syncNow()
                isSyncing = false
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 12, weight: .medium))
                    .rotationEffect(.degrees(isSyncing ? 360 : 0))
                    .animation(
                        isSyncing
                            ? .linear(duration: 1).repeatForever(autoreverses: false)
                            : .default,
                        value: isSyncing
                    )
                if showsLabel {
                    Text(isSyncing ? "Synchroniseert…" : "Synchroniseer met iCloud")
                        .font(ThemeFont.ui(12, weight: .medium))
                }
            }
            // Grijs als er niets te synchroniseren valt: de Designregels zeggen
            // dat een uitgeschakelde knop niet de accentkleur houdt.
            .foregroundStyle(isAvailable ? Theme.accentText : Theme.textTertiary)
            .padding(.horizontal, showsLabel ? 10 : 0)
            .padding(.vertical, showsLabel ? 5 : 0)
            .background(
                showsLabel
                    ? RoundedRectangle(cornerRadius: Theme.Metrics.radius, style: .continuous)
                        .fill(Theme.surface)
                    : nil
            )
            .overlay(
                showsLabel
                    ? RoundedRectangle(cornerRadius: Theme.Metrics.radius, style: .continuous)
                        .strokeBorder(Theme.border, lineWidth: 1)
                    : nil
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable || isSyncing)
        .help(tooltip)
        .accessibilityLabel("Synchroniseer met iCloud")
    }

    /// Bij `disabled` staat de schakelaar uit, bij `unavailable` draagt deze
    /// build het CloudKit-recht niet of is er geen iCloud-account: in beide
    /// gevallen doet klikken niets.
    private var isAvailable: Bool {
        switch historySync.status {
        case .disabled, .unavailable: return false
        case .requiresApproval, .active, .error: return true
        }
    }

    private var tooltip: String {
        isSyncing ? "Bezig met synchroniseren" : "iCloud: \(historySync.status.dutchLabel)"
    }
}
