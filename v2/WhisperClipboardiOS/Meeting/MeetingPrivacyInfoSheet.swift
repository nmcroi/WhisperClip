import AVFoundation
import SwiftUI

/// Heldere uitleg vóór een Notulist-opname. Deze wordt pas op verzoek getoond
/// of voorgelezen; het openen of afspelen start nadrukkelijk géén opname.
struct MeetingPrivacyInfoSheet: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var narrator = MeetingPrivacyNarrator()
    let makeAIMinutes: Bool

    private var copy: MeetingPrivacyCopy {
        MeetingPrivacyCopy.make(
            languageCode: app.interfaceLanguage.resolvedCode,
            ai: !app.allowMeetingAI ? .unavailable : (makeAIMinutes ? .on : .off)
        )
    }

    var body: some View {
            ZStack {
                Theme.window.ignoresSafeArea()
                ScrollView {
                    // Kaal op verzoek van Niels (13 aug 2026): geen i-icoon,
                    // geen dubbele titel, geen ondertitel. Eén grote kop
                    // "Uitleg", meteen daaronder de voorleesknop
                    // ("Audio-uitleg"), dan pas de tekstkaarten.
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Uitleg")
                            .font(ThemeFont.ui(28, weight: .bold))
                            .foregroundStyle(Theme.text)

                        // Halve breedte (wens 13 aug 2026): de knop deelt de
                        // regel met een leeg vak van dezelfde breedte.
                        HStack(spacing: 0) {
                            ActionButton(
                                title: narrator.isSpeaking
                                    ? copy.stop
                                    : L10n.string( "Audio-uitleg", locale: app.interfaceLanguage.locale),
                                systemImage: narrator.isSpeaking ? "stop.fill" : "play.fill",
                                role: .primary
                            ) {
                                narrator.toggle(text: copy.spokenText, language: app.interfaceLanguage.speechLanguage)
                            }
                            .accessibilityHint(copy.voiceAccessibilityHint)
                            Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                        }

                        ForEach(copy.cards) { card in
                            explanationCard(title: card.title, symbol: card.symbol, text: card.text)
                        }

                        Text(copy.voiceHint)
                            .font(ThemeFont.ui(13))
                            .foregroundStyle(Theme.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .onDisappear { narrator.stop() }
    }

    private func explanationCard(title: String, symbol: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(ThemeFont.ui(16, weight: .semibold))
                .foregroundStyle(Theme.text)
            Text(text)
                .font(ThemeFont.ui(15))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .themeCard()
    }
}

@MainActor
private final class MeetingPrivacyNarrator: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var isSpeaking = false
    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func toggle(text: String, language: String) {
        if synthesizer.isSpeaking {
            stop()
            return
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        utterance.rate = 0.47
        synthesizer.speak(utterance)
        isSpeaking = true
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            self?.isSpeaking = false
        }
    }
}
