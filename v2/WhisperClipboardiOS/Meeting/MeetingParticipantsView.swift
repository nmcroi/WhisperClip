import Core
import SwiftUI

/// Het deelnemersbeheer van de notulist, losgetrokken uit `MeetingSetupView`.
///
/// Niels' opdracht van 13 augustus 2026: het notulescherm toonde alles tegelijk
/// (invulvelden per deelnemer, twee toevoegknoppen, twee lappen uitlegtekst, de
/// AI-schakelaar en de taalkeuze) en werd daar onrustig van. Het startscherm
/// houdt nu vier regels over; alles wat met deelnemers te maken heeft, staat
/// hier en alleen hier.
struct MeetingParticipantsView: View {
    @EnvironmentObject private var app: AppModel
    @Binding var rows: [MeetingSetupView.Row]

    var body: some View {
        ZStack {
            Theme.window.ignoresSafeArea()
            List {
                Section {
                    ForEach($rows) { $row in
                        participantRow($row)
                    }
                    .onDelete { offsets in
                        rows.remove(atOffsets: offsets)
                    }

                    ActionButton(
                        title: L10n.string( "Nieuwe deelnemer", locale: app.interfaceLanguage.locale),
                        systemImage: "person.badge.plus"
                    ) {
                        rows.append(MeetingSetupView.Row())
                    }

                    if !app.meetingContacts.isEmpty {
                        Menu {
                            ForEach(app.meetingContacts.filter(\.isValid)) { contact in
                                Button(contact.name) { add(contact) }
                            }
                        } label: {
                            ActionButtonLabel(
                                title: L10n.string( "Kies vaste deelnemer", locale: app.interfaceLanguage.locale),
                                systemImage: "person.crop.circle.badge.checkmark"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                } footer: {
                    if app.showHelpTips {
                        Text("Je mag dit leeg laten om alleen lokaal te transcriberen. Iedere ingevulde deelnemer is een e-mailontvanger en ontvangt na afloop exact hetzelfde verslag. Vaste deelnemers beheer je in Instellingen.")
                    }
                }
                .listRowBackground(Theme.surface)
            }
            .scrollContentBackground(.hidden)
            // Naar beneden vegen sluit het toetsenbord boven de naam- en
            // e-mailvelden (2 sep 2026).
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("Deelnemers")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func participantRow(_ row: Binding<MeetingSetupView.Row>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Naam", text: row.name)
                .font(ThemeFont.ui(16))
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(Theme.surfaceHover)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Theme.border, lineWidth: 1)
                }
            TextField("E-mailadres", text: row.email)
                .font(ThemeFont.ui(16))
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(Theme.surfaceHover)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Theme.border, lineWidth: 1)
                }
            if !isStoredContact(row.wrappedValue) {
                Toggle(isOn: row.saveContact) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Bewaren")
                            .font(ThemeFont.ui(14))
                        if app.showHelpTips {
                            Text("Bewaar deze naam en dit e-mailadres voor volgende vergaderingen.")
                                .font(ThemeFont.ui(12))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                .tint(Theme.accent)
                .disabled(!(row.wrappedValue.participant(
                    defaultName: L10n.string( "Deelnemer", locale: app.interfaceLanguage.locale)
                )?.isValid ?? false))
            }
        }
        .padding(.trailing, 46)
        .overlay(alignment: .topTrailing) {
            Button {
                removeRow(id: row.wrappedValue.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(
                format: L10n.string( "Verwijder %@ uit deze vergadering", locale: app.interfaceLanguage.locale),
                locale: app.interfaceLanguage.locale,
                row.wrappedValue.name.isEmpty
                    ? L10n.string( "deelnemer", locale: app.interfaceLanguage.locale)
                    : row.wrappedValue.name
            ))
        }
        .padding(.vertical, 4)
    }

    private func isStoredContact(_ row: MeetingSetupView.Row) -> Bool {
        let email = row.email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty else { return false }
        return app.meetingContacts.contains {
            $0.email.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(email) == .orderedSame
        }
    }

    private func removeRow(id: UUID) {
        rows.removeAll { $0.id == id }
    }

    private func add(_ contact: SavedMeetingContact) {
        guard !rows.contains(where: {
            $0.name.caseInsensitiveCompare(contact.name) == .orderedSame
                && $0.email.caseInsensitiveCompare(contact.email) == .orderedSame
        }) else { return }
        rows.append(MeetingSetupView.Row(name: contact.name, email: contact.email))
    }
}
