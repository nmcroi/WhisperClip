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
    /// Geschiedenis gebruikt dit om de zichtbare cache na elke handmatige sync
    /// opnieuw uit de database op te bouwen, ook als CloudKit geen mutatie-event
    /// meer levert omdat de records vlak daarvoor al zijn opgeslagen.
    var onCompletion: () -> Void = {}

    @State private var isSyncing = false
    @State private var result: ResultState?

    private enum ResultState {
        case success
        case failure
    }

    var body: some View {
        Button {
            guard !isSyncing else { return }
            result = nil
            isSyncing = true
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            Task {
                await historySync.syncNow()
                onCompletion()
                isSyncing = false
                if case .active = historySync.status {
                    result = .success
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                } else {
                    result = .failure
                }
                try? await Task.sleep(for: .seconds(1.6))
                result = nil
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: iconName)
                    .font(.system(size: 12, weight: .medium))
                    .rotationEffect(.degrees(isSyncing ? 360 : 0))
                    .animation(
                        isSyncing
                            ? .linear(duration: 1).repeatForever(autoreverses: false)
                            : .default,
                        value: isSyncing
                    )
                if showsLabel {
                    Text(buttonLabel)
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
        .accessibilityValue(accessibilityValue)
    }

    private var iconName: String {
        if isSyncing { return "arrow.triangle.2.circlepath" }
        switch result {
        case .success: return "checkmark.circle.fill"
        case .failure: return "exclamationmark.triangle.fill"
        case nil: return "arrow.triangle.2.circlepath"
        }
    }

    private var buttonLabel: String {
        if isSyncing { return "Synchroniseert…" }
        switch result {
        case .success: return "Bijgewerkt"
        case .failure: return "Controleer iCloud"
        case nil: return "Synchroniseer met iCloud"
        }
    }

    private var accessibilityValue: String {
        if isSyncing { return "Bezig met synchroniseren" }
        switch result {
        case .success: return "Synchronisatie voltooid"
        case .failure: return historySync.status.dutchLabel
        case nil: return historySync.status.dutchLabel
        }
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
