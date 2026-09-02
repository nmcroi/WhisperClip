import Core
import SwiftUI

/// Stap 1 van de private notulist: e-mailontvangers invoeren. Ontvangers zijn
/// optioneel, zodat de Notulist ook volledig lokaal en zonder e-mail kan worden
/// gebruikt. Een lege rij wordt genegeerd; een deels ingevulde rij moet geldig
/// zijn voordat de opname kan starten.
struct MeetingSetupView: View {
    @EnvironmentObject private var app: AppModel

    /// Bewerkbare rijen; omgezet naar `MeetingParticipant` bij de start.
    @State private var rows: [Row] = [Row()]
    @State private var started = false
    @State private var seededOwnContact = false
    @State private var showPrivacyInfo = false
    @State private var showParticipants = false
    @State private var makeAIMinutes = false

    struct Row: Identifiable {
        let id = UUID()
        var name = ""
        var email = ""
        var saveContact = false

        func participant(defaultName: String) -> MeetingParticipant? {
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !trimmedName.isEmpty || !trimmedEmail.isEmpty else { return nil }

            return MeetingParticipant(
                name: trimmedName.isEmpty ? defaultName : trimmedName,
                email: trimmedEmail
            )
        }
    }

    private var enteredParticipants: [MeetingParticipant] {
        let fallback = L10n.string( "Deelnemer", locale: app.interfaceLanguage.locale)
        return rows.compactMap { $0.participant(defaultName: fallback) }
    }
    private var sessionParticipants: [MeetingParticipant] { enteredParticipants }

    /// Start kan ook zonder deelnemers: dan nemen we lokaal op als "Ik". Alleen
    /// ingevulde rijen moeten geldig zijn; lege rijen worden genegeerd.
    private var canStart: Bool {
        enteredParticipants.allSatisfy(\.isValid)
            && app.modelStatus.isReady
    }

    var body: some View {
        ZStack {
            Theme.window.ignoresSafeArea()
            VStack(spacing: 0) {
                MainPageHeader(title: "De Notulist")
                List {
                    // Vier blokken, elk precies één regel, volgens de
                    // knoppentaal in START_PROMPT_NEXT_CHAT.md (13 aug 2026).
                    // Volgorde van Niels (13 aug 2026): eerst de instellingen,
                    // de uitleg als laatste, met een dun accentrandje zodat hij
                    // zich onderscheidt.
                    Section {
                        Button {
                            showParticipants = true
                        } label: {
                            navRow("Deelnemers toevoegen")
                        }
                        .buttonStyle(.plain)
                    }
                    .listRowBackground(Theme.surface)

                    Section {
                        // Eigen label met exacte kleur: de systeemtint tekent
                        // menuwaarden met een waas, waardoor er twee tinten
                        // oranje ontstonden (13 aug 2026).
                        Menu {
                            Picker("Transcriptietaal", selection: $app.transcriptionLanguage) {
                                ForEach(TranscriptionLanguage.allCases) { language in
                                    Text(language.whisperClipLabel(in: app.interfaceLanguage))
                                        .tag(language)
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text("Transcriptietaal")
                                    .foregroundStyle(Theme.text)
                                Spacer()
                                Text(app.transcriptionLanguage.whisperClipLabel(in: app.interfaceLanguage))
                                    .foregroundStyle(Theme.accentText)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Theme.accentText)
                            }
                            .frame(minHeight: 32)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .listRowBackground(Theme.surface)

                    if app.allowMeetingAI {
                        Section {
                            Toggle("AI-notulen", isOn: $makeAIMinutes)
                                .tint(Theme.accent)
                                .frame(minHeight: 32)
                        }
                        .listRowBackground(Theme.surface)
                    }

                    Section {
                        Button {
                            showPrivacyInfo = true
                        } label: {
                            navRow("Hoe werkt de notulist?")
                        }
                        .buttonStyle(.plain)
                    }
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .fill(Theme.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 26, style: .continuous)
                                    .strokeBorder(Theme.accentText.opacity(0.55), lineWidth: 1)
                            )
                    )
                }
                .scrollContentBackground(.hidden)
                meetingRecordBar
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Wordmark(size: 20)
            }
        }
        .onAppear(perform: seedOwnContact)
        // Zelfde schuifrichting als Deelnemers (rechts naar links): eerst
        // kwam de uitleg van onderen en dat was de enige afwijking (13 aug 2026).
        .navigationDestination(isPresented: $showPrivacyInfo) {
            MeetingPrivacyInfoSheet(makeAIMinutes: app.allowMeetingAI && makeAIMinutes)
                .environmentObject(app)
        }
        .navigationDestination(isPresented: $showParticipants) {
            MeetingParticipantsView(rows: $rows)
                .environmentObject(app)
        }
        .navigationDestination(isPresented: $started) {
            MeetingRecordView(
                participants: sessionParticipants,
                makeAIMinutes: app.allowMeetingAI && makeAIMinutes,
                language: app.transcriptionLanguage
            )
        }
    }

    private func navRow(_ title: LocalizedStringKey) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .foregroundStyle(Theme.text)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accentText)
        }
        .frame(minHeight: 32)
        .contentShape(Rectangle())
    }

    /// De start van een notule is bewust losgezet van deelnemersbeheer: dezelfde
    /// grote, rustige opnameknop als op Notities, maar met een heldere actie-naam.
    private var meetingRecordBar: some View {
        VStack(spacing: 0) {
            Button {
                startMeeting()
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(canStart ? Theme.accent : Theme.textTertiary, lineWidth: 6)
                        .frame(width: 112, height: 112)
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(canStart ? Theme.accent : Theme.textTertiary)
                        .frame(width: 48, height: 48)
                }
            }
            .buttonStyle(.plain)
            .disabled(!canStart)
            .accessibilityLabel("Start notulen-opname")

            if !app.modelStatus.isReady {
                Text("Download eerst het spraakmodel via Opnemen.")
                    .font(ThemeFont.ui(13))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, 9)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Theme.surface)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.border).frame(height: Theme.Metrics.hairline)
        }
    }

    private func seedOwnContact() {
        guard !seededOwnContact else { return }
        seededOwnContact = true
        guard let own = app.meetingContacts.first(where: \.isMe) else { return }
        rows = []
        add(own)
    }

    private func add(_ contact: SavedMeetingContact) {
        guard !rows.contains(where: {
            $0.name.caseInsensitiveCompare(contact.name) == .orderedSame
                && $0.email.caseInsensitiveCompare(contact.email) == .orderedSame
        }) else { return }
        rows.append(Row(name: contact.name, email: contact.email))
    }

    private func removeRow(id: UUID) {
        rows.removeAll { $0.id == id }
    }

    private func startMeeting() {
        var contacts = app.meetingContacts
        for row in rows where row.saveContact && !isStoredContact(row) {
            guard let participant = row.participant(
                defaultName: L10n.string( "Deelnemer", locale: app.interfaceLanguage.locale)
            ) else { continue }
            contacts = MeetingContactList.saving(participant, in: contacts)
        }
        if contacts != app.meetingContacts {
            app.meetingContacts = contacts
        }
        started = true
    }

    private func isStoredContact(_ row: Row) -> Bool {
        let email = row.email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty else { return false }
        return app.meetingContacts.contains {
            $0.email.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(email) == .orderedSame
        }
    }
}
