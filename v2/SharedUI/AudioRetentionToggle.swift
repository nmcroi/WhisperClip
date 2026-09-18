import SwiftUI
import WhisperShared

struct AudioRetentionToggle: View {
    @Binding var keep: Bool
    var locale: Locale = .current
    var disabled = false
    var body: some View {
        Toggle(AudioCopy.text(.choice, locale: locale), isOn: $keep)
            .accessibilityIdentifier("audio.keepThisRecording")
            .toggleStyle(.switch).tint(Theme.accent)
            .font(ThemeFont.ui(13))
            .disabled(disabled)
            .foregroundStyle(Theme.text)
    }
}
