import Core
import Foundation
import SwiftUI
import UIKit
import WhisperShared

/// The transcript detail screen: grouped body text (Core `SegmentGrouping` so
/// diarized turns / sentences read naturally), with copy, share and delete.
struct HistoryDetailiOSView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    let entry: TranscriptEntry

    @State private var didCopy = false
    @State private var showsAI = false
    @State private var showAddToNote = false
    @State private var showSettings = false
    /// Verwijderen vroeg hier niets, terwijl dezelfde actie in de
    /// meervoudsselectie wel een bevestiging kreeg (2 sep 2026).
    @State private var showDeleteConfirm = false
    @State private var showRename = false
    @State private var renameText = ""

    var body: some View {
        ZStack {
            Theme.window.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // De titel staat bewust ín de inhoud en niet in de
                    // navigatiebalk: het instellingen-tandwiel van RootView
                    // zweeft daar los overheen, waardoor een lange titel er
                    // dwars doorheen liep (bevinding 2026-08-02).
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        // Zelfde hairline als onder de actiebalk: de titel
                        // plakte tegen de informatie aan (13 aug 2026).
                        Divider().overlay(Theme.border)
                            .padding(.vertical, 12)
                        Text(title)
                            .font(ThemeFont.ui(22, weight: .bold))
                            .foregroundStyle(Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if showsAI, let modes = app.modes {
                        AIRunnerView(
                            entry: entry,
                            modes: modes,
                            onAddToNote: { showAddToNote = true },
                            onOpenSettings: { showSettings = true }
                        )
                        Divider().overlay(Theme.border)
                    }
                    bodyText
                }
                .padding(20)
            }
            // Het AI-paneel heeft een invoerveld: naar beneden vegen sluit het
            // toetsenbord (2 sep 2026).
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top, spacing: 0) {
            actionBar
        }
        // Het losse rondje met drie puntjes naast de terug-chevron is vervallen:
        // het was de enige knop op dit scherm met een eigen vorm (13 aug 2026).
        // Dezelfde acties zitten nu als vierde knop in de actiebalk, in precies
        // dezelfde vorm als Kopieer, Deel en AI.
        .sheet(isPresented: $showAddToNote) {
            AddToNoteSheet(entryId: entry.id) {
                // De opname hoort nu bij een notitie en verdwijnt uit de losse
                // Geschiedenis: sluit het detailscherm.
                dismiss()
            }
            .environmentObject(app)
            .preferredColorScheme(app.appearance.preferredColorScheme)
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet()
                .environmentObject(app)
                .preferredColorScheme(app.appearance.preferredColorScheme)
        }
        .alert(
            L10n.string( "Opname verwijderen", locale: app.interfaceLanguage.locale),
            isPresented: $showDeleteConfirm
        ) {
            Button("Verwijder", role: .destructive) { deleteTranscript() }
            Button("Annuleer", role: .cancel) {}
        } message: {
            Text("Deze opname wordt definitief verwijderd.")
        }
        .alert("Opname hernoemen", isPresented: $showRename) {
            TextField("Titel", text: $renameText)
            Button("Bewaar") { renameTranscript() }
            Button("Annuleer", role: .cancel) {}
        }
    }

    private func renameTranscript() {
        guard let history = app.history else { return }
        do {
            try history.rename(id: entry.id, name: renameText)
        } catch {
            app.presentDataChangeError(error)
        }
    }

    private func deleteTranscript() {
        guard let history = app.history else { return }
        do {
            try history.delete(id: entry.id)
            dismiss()
        } catch {
            app.errorMessage = String(
                format: L10n.string(
                    "Het transcript kon niet worden verwijderd: %@",
                    locale: app.interfaceLanguage.locale
                ),
                locale: app.interfaceLanguage.locale,
                error.localizedDescription
            )
        }
    }

    /// Twee regels in plaats van één: bron en duur boven, opnamemoment en taal
    /// eronder. Alles op één regel stond te gepropt (bevinding 2026-08-02).
    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                // Informatie, geen knop: geel is voor acties en gekozen
                // waarden, dus het bronicoon is grijs (afspraak 13 aug 2026).
                Image(systemName: TranscriptSourceStyle.icon(for: entry.source))
                    .foregroundStyle(Theme.textSecondary)
                Text(sourceLabel)
                if entry.duration > 0 {
                    Text("·")
                    Text(durationText)
                }
            }
            HStack(spacing: 8) {
                if let recordedAtText {
                    Text(recordedAtText)
                    Text("·")
                }
                Text(languageLabel)
            }
        }
        .font(ThemeFont.ui(14))
        .foregroundStyle(Theme.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var bodyText: some View {
        let turns = SegmentGrouping.speakerTurns(from: entry.segments)
        if turns.count > 1 || (turns.first?.speaker != nil) {
            // Diarized / multi-turn: render each turn with its (renamed) speaker.
            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(turns.enumerated()), id: \.offset) { _, turn in
                    VStack(alignment: .leading, spacing: 4) {
                        if let raw = turn.speaker {
                            Text(entry.displayName(forSpeaker: raw))
                                .font(ThemeFont.ui(13, weight: .semibold))
                                .foregroundStyle(Theme.accentText)
                        }
                        Text(turn.text)
                            .font(ThemeFont.ui(17))
                            .foregroundStyle(Theme.text)
                    }
                }
            }
            .textSelection(.enabled)
        } else {
            // Plain transcript: use sentence grouping for readable paragraphs.
            let sentences = SegmentGrouping.sentences(from: entry.segments)
            let text = sentences.isEmpty
                ? entry.text
                : sentences.map(\.text).joined(separator: " ")
            Text(text)
                .font(ThemeFont.ui(17))
                .foregroundStyle(Theme.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

    }

    /// Proefstijl van 13 augustus 2026: de knop ís het icoon, groot en geel,
    /// tekst in wit eronder, zonder kader. Alle vijf de acties zichtbaar, geen
    /// Meer-menu meer: Niels wil zien wat er kan.
    private var actionBar: some View {
        HStack(spacing: 4) {
            Button {
                UIPasteboard.general.string = entry.text
                didCopy = true
            } label: {
                IconActionLabel(
                    title: didCopy
                        ? L10n.string( "Gekopieerd", locale: app.interfaceLanguage.locale)
                        : L10n.string( "Kopieer", locale: app.interfaceLanguage.locale),
                    systemImage: didCopy ? "checkmark" : "doc.on.doc"
                )
            }
            .buttonStyle(.plain)

            ShareLink(item: entry.text) {
                IconActionLabel(
                    title: L10n.string( "Deel", locale: app.interfaceLanguage.locale),
                    systemImage: "square.and.arrow.up"
                )
            }
            .buttonStyle(.plain)

            Button {
                renameText = liveName
                showRename = true
            } label: {
                IconActionLabel(
                    title: L10n.string( "Hernoem", locale: app.interfaceLanguage.locale),
                    systemImage: "pencil"
                )
            }
            .buttonStyle(.plain)

            Button {
                showAddToNote = true
            } label: {
                IconActionLabel(
                    title: L10n.string( "Notitie", locale: app.interfaceLanguage.locale),
                    systemImage: "note.text.badge.plus"
                )
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showsAI.toggle()
                }
            } label: {
                IconActionLabel(
                    title: "AI",
                    systemImage: "sparkles",
                    isActive: showsAI
                )
            }
            .buttonStyle(.plain)

            // Geel als de andere acties, met een bevestigvraag die een mistik
            // opvangt. Dezelfde keuze als in de selectiebalk van de lijst
            // (wens Niels, 2 sep 2026).
            Button {
                showDeleteConfirm = true
            } label: {
                IconActionLabel(
                    title: L10n.string( "Verwijder", locale: app.interfaceLanguage.locale),
                    systemImage: "trash"
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        // Vaste balken die niet meescrollen dragen allemaal hetzelfde vlak.
        .background(Theme.surface)
        .overlay(alignment: .bottom) {
            Divider().overlay(Theme.border)
        }
    }

    /// De naam zoals hij nú in de database staat. Dit scherm krijgt `entry` als
    /// vaste waarde mee, dus zonder deze herlezing bleef de oude titel staan na
    /// het hernoemen. De revisie-lezing zorgt dat de view opnieuw tekent.
    private var liveName: String {
        _ = app.history?.revision
        guard let history = app.history,
              let record = try? history.record(id: entry.id)
        else { return entry.name }
        return record.name
    }

    private var title: String {
        let trimmedName = liveName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty && trimmedName.localizedCaseInsensitiveCompare("PLAUD-opname") != .orderedSame {
            return trimmedName
        }
        // 15 tekens: bij 30 brak de titel bijna altijd naar een tweede regel
        // (13 aug 2026).
        return String(entry.text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(15))
    }

    /// De taal waarin deze opname is uitgeschreven. Leest zowel de nieuwe codes
    /// als oudere opgeslagen waarden.
    private var languageLabel: String {
        TranscriptionLanguage(metadataCode: entry.language)
            .whisperClipLabel(in: app.interfaceLanguage)
    }

    private var durationText: String {
        DurationText.string(seconds: entry.duration, locale: app.interfaceLanguage.locale)
    }

    /// Datum en tijdstip van de opname zelf. In de lijst staat "11 uur geleden";
    /// hier hoort de werkelijke datum (wens Niels, 2026-08-02).
    private var recordedAtText: String? {
        guard let date = entry.timestamp else { return nil }
        // Cijferdatum: "13 augustus 2026 om 15:42" brak de regel af, waardoor
        // de taal erachter niet meer paste (13 aug 2026).
        let formatter = DateFormatter()
        formatter.locale = app.interfaceLanguage.locale
        formatter.dateFormat = "dd-MM-yyyy 'om' HH:mm"
        return formatter.string(from: date)
    }

    private var sourceLabel: String {
        let base = entry.source.split(separator: ".").first.map(String.init) ?? entry.source
        return switch base {
        case "file": L10n.string( "Bestand", locale: app.interfaceLanguage.locale)
        case "captions": L10n.string( "Ondertitels", locale: app.interfaceLanguage.locale)
        case "plaud": "PLAUD"
        case "meeting": L10n.string( "Notulist", locale: app.interfaceLanguage.locale)
        default: "iPhone"
        }
    }
}
