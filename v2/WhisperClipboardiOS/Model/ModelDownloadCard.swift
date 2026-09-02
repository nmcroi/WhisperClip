import SwiftUI
import UniformTypeIdentifiers
import WhisperShared

/// First-launch onboarding card shown on the Record tab until the ~460 MB
/// Parakeet model is on device. Drives ``AppModel/downloadModel()`` and shows
/// live progress. Once installed it disappears and the record button takes over.
struct ModelDownloadCard: View {
    @EnvironmentObject private var app: AppModel

    /// Open/dicht van de map-picker voor de secundaire importroute.
    @State private var showingImporter = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(Theme.accentText)

            Text("Spraakmodel downloaden")
                .font(ThemeFont.ui(18, weight: .semibold))
                .foregroundStyle(Theme.text)

            Text("WhisperClip transcribeert volledig op je iPhone. Download eenmalig het meertalige Parakeet-model (~460 MB). Daarna werkt alles offline.")
                .font(ThemeFont.ui(14))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            content

            if let message = app.errorMessage {
                Text(message)
                    .font(ThemeFont.ui(13))
                    .foregroundStyle(Theme.danger)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .themeCard()
        .padding(.horizontal, 20)
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task { await app.importModel(from: url) }
            case .failure(let error):
                app.errorMessage = ErrorLocalization.message(for: error, language: app.interfaceLanguage)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch app.modelStatus {
        case _ where app.isImportingModel:
            // Kopiëren van de geïmporteerde map naar de FluidAudio-cache loopt
            // op de achtergrond; geen fractie beschikbaar, dus een spinner.
            VStack(spacing: 8) {
                ProgressView()
                Text("Model importeren…")
                    .font(ThemeFont.ui(13))
                    .foregroundStyle(Theme.textTertiary)
            }
        case .downloading(let progress):
            VStack(spacing: 8) {
                ProgressView(value: progress)
                    .tint(Theme.accent)
                Text(progressLabel(progress))
                    .font(ThemeFont.ui(13))
                    .foregroundStyle(Theme.textTertiary)
                    .contentTransition(.numericText())
                Text("Houd de app open tijdens het downloaden.")
                    .font(ThemeFont.ui(12))
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
            }
        case .unsupported:
            Text("Dit toestel wordt niet ondersteund.")
                .font(ThemeFont.ui(14))
                .foregroundStyle(Theme.danger)
        default:
            VStack(spacing: 10) {
                // Na een mislukte poging is dit meteen de opnieuw-knop.
                ActionButton(
                    title: app.errorMessage == nil
                        ? L10n.string( "Download model", locale: app.interfaceLanguage.locale)
                        : L10n.string( "Opnieuw proberen", locale: app.interfaceLanguage.locale),
                    role: .primary
                ) {
                    Task { await app.downloadModel() }
                }

                // Secundaire route wanneer de download over het netwerk niet
                // lukt (bijv. schermvergrendeling breekt hem telkens af):
                // handmatig een geairdropte modelmap importeren.
                ActionButton(
                    title: L10n.string( "Importeer model…", locale: app.interfaceLanguage.locale),
                    role: .secondary,
                    size: .regular
                ) {
                    showingImporter = true
                }
            }
        }
    }

    /// "45% · 210 van 460 MB" when byte progress is known, else just the percent.
    private func progressLabel(_ progress: Double) -> String {
        let percent = "\(Int(progress * 100))%"
        if let bytes = app.downloadBytes, bytes.totalMB > 0 {
            return String(
                format: L10n.string( "%1$@ · %2$lld van %3$lld MB", locale: app.interfaceLanguage.locale),
                locale: app.interfaceLanguage.locale,
                percent,
                bytes.downloadedMB,
                bytes.totalMB
            )
        }
        return percent
    }
}
