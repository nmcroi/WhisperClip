import Core
import Foundation
import SwiftUI
import WhisperShared

/// The "Geschiedenis" tab: a searchable list of saved transcriptions, newest
/// first. Search hits the shared `HistoryStore` FTS5 index. Rows show a title,
/// relative Dutch date, duration and source glyph; swipe to delete; tap for the
/// detail view.
struct HistoryListiOSView: View {
    @EnvironmentObject private var app: AppModel
    @State private var query = ""
    @State private var visibleEntries: [TranscriptEntry] = []
    @State private var historyTotal = 0

    private var snapshotKey: String {
        "\(app.history?.revision ?? 0)|\(query)|\(durationFilter.rawValue)|\(deviceFilter.rawValue)|\(speakerFilter.rawValue)|\(titleFilter.rawValue)|\(sortOrder.rawValue)"
    }
    @State private var durationFilter = DurationFilter.all
    @State private var deviceFilter = DeviceFilter.all
    @State private var speakerFilter = SpeakerFilter.all
    @State private var titleFilter = TitleFilter.all
    @State private var sortOrder = SortOrder.newest
    /// De opname waarvoor de "Voeg toe aan notitie"-sheet open staat.
    @State private var addToNoteTarget: AddToNoteTarget?
    /// Selectiemodus: meerdere opnames in één keer delen. Niels wilde er drie
    /// tegelijk naar zijn Mac sturen en kon alleen één voor één (13 aug 2026).
    @State private var isSelecting = false
    @State private var selection: Set<String> = []
    /// De opnames waarvoor de bevestiging om samen te voegen open staat.
    @State private var mergeTarget: MergeTarget?
    @State private var showDeleteSelectedConfirm = false
    /// Waar terwijl "Synchroniseer iCloud" vanuit deze pagina loopt.
    @State private var isCloudSyncing = false
    @FocusState private var searchFocused: Bool

    /// Identifiable-wikkel zodat `sheet(item:)` een losse entry-id kan dragen.
    private struct AddToNoteTarget: Identifiable { let id: String }

    private struct MergeTarget: Identifiable {
        let id = UUID()
        let entries: [TranscriptEntry]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.window.ignoresSafeArea()
                VStack(spacing: 0) {
                    MainPageHeader(title: "Geschiedenis")
                    searchField
                    listBody
                }
            }
            .task(id: snapshotKey) { await reloadHistory() }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Wordmark(size: 20)
                }
            }
            .sheet(item: $addToNoteTarget) { target in
                AddToNoteSheet(entryId: target.id)
                    .environmentObject(app)
                    .preferredColorScheme(app.appearance.preferredColorScheme)
            }
            .alert(
                L10n.string( "Opnames verwijderen", locale: app.interfaceLanguage.locale),
                isPresented: $showDeleteSelectedConfirm
            ) {
                Button("Verwijder", role: .destructive) { deleteSelected() }
                Button("Annuleer", role: .cancel) {}
            } message: {
                Text(AudioCopy.text(.deleteTogether, locale: app.interfaceLanguage.locale))
                Text(String(
                    format: L10n.string(
                        "%lld opnames worden definitief verwijderd.",
                        locale: app.interfaceLanguage.locale
                    ),
                    locale: app.interfaceLanguage.locale,
                    selection.count
                ))
            }
            .alert(
                L10n.string( "Opnames samenvoegen", locale: app.interfaceLanguage.locale),
                isPresented: Binding(
                    get: { mergeTarget != nil },
                    set: { if !$0 { mergeTarget = nil } }
                ),
                presenting: mergeTarget
            ) { target in
                Button("Voeg samen") { merge(target.entries, deleteOriginals: false) }
                Button("Samenvoegen en originelen verwijderen", role: .destructive) {
                    merge(target.entries, deleteOriginals: true)
                }
                Button("Annuleer", role: .cancel) {}
            } message: { target in
                Text(AudioCopy.text(.mergeWarning, locale: app.interfaceLanguage.locale))
                Text(String(
                    format: L10n.string(
                        "%lld opnames worden één nieuwe opname, op volgorde van tijd, oudste eerst.",
                        locale: app.interfaceLanguage.locale
                    ),
                    locale: app.interfaceLanguage.locale,
                    target.entries.count
                ))
            }
        }
    }

    /// Voegt de gekozen opnames samen tot één nieuwe opname.
    ///
    /// Het samenvoegen zelf staat sinds 14 augustus 2026 in `TranscriptMerge`
    /// (Core), zodat de Mac exact hetzelfde doet. Hier blijft alleen wat
    /// iPhone-eigen is: de vertaalde naam en de foutmelding.
    private func merge(_ entries: [TranscriptEntry], deleteOriginals: Bool) {
        guard let history = app.history else { return }
        let ordered = TranscriptMerge.sortedByTime(entries)
        guard let first = ordered.first else { return }
        let naam = String(
            format: L10n.string("%@ (samengevoegd)", locale: app.interfaceLanguage.locale),
            locale: app.interfaceLanguage.locale,
            first.displayTitle(locale: app.interfaceLanguage.locale)
        )
        guard let merged = TranscriptMerge.merge(entries, naam: naam) else { return }
        do {
            // Eén transactie: mislukt het verwijderen van een origineel, dan komt
            // ook de samengevoegde opname er niet, in plaats van een dubbele
            // geschiedenis met de helft van de originelen er nog in.
            if deleteOriginals {
                try history.mergeAndReplace(merged: merged, deleting: ordered.map(\.id))
            } else {
                try history.add(merged)
            }
            selection = []
            isSelecting = false
        } catch {
            app.errorMessage = String(
                format: L10n.string(
                    "De opnames konden niet worden samengevoegd: %@",
                    locale: app.interfaceLanguage.locale
                ),
                locale: app.interfaceLanguage.locale,
                error.localizedDescription
            )
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            // Geel: tikken op het veld (inclusief het vergrootglas) opent het
            // toetsenbord, dus dit is aanraakbaar gebied (13 aug 2026).
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.accentText)
            TextField("Zoeken", text: $query)
                .font(ThemeFont.ui(17))
                .foregroundStyle(Theme.text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($searchFocused)
                .submitLabel(.done)
            // Het toetsenbord was niet weg te krijgen zonder te zoeken
            // (13 aug 2026): dit kruisje wist en sluit in één tik.
            if searchFocused || !query.isEmpty {
                Button {
                    query = ""
                    searchFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Wis zoekopdracht en sluit toetsenbord")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: Theme.Metrics.hairline)
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var listBody: some View {
        let entries = visibleEntries
        let total = historyTotal
        VStack(spacing: 0) {
            // De knoppenrij staat buiten de List en scrolt dus niet mee weg:
            // Niels scrolde naar beneden en was zijn knoppen kwijt (2 sep 2026).
            controlsRow(visible: entries.count, total: total)
                .padding(.horizontal, 20)
                .padding(.top, 10)
                // Vaste balken die niet meescrollen dragen allemaal hetzelfde
                // vlak, net als de selectiebalk onderaan (2 sep 2026).
                .background(Theme.surface)
            if entries.isEmpty {
                emptyState.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(entries, id: \.id) { entry in
                        Group {
                            if isSelecting {
                                selectableRow(entry)
                            } else {
                                ZStack {
                                    NavigationLink(value: entry.id) {
                                        EmptyView()
                                    }
                                    .opacity(0)
                                    TranscriptRowiOS(entry: entry)
                                }
                            }
                        }
                        .listRowBackground(Theme.window)
                        .listRowSeparatorTint(Theme.border)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                deleteTranscript(entry.id)
                            } label: {
                                Label("Verwijder", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                addToNoteTarget = AddToNoteTarget(id: entry.id)
                            } label: {
                                Label("Naar notitie", systemImage: "note.text.badge.plus")
                            }
                            .tint(Theme.accentText)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .navigationDestination(for: String.self) { id in
                    if let entry = entryByID(id) {
                        HistoryDetailiOSView(entry: entry)
                    }
                }
                if isSelecting {
                    selectionBar(entries: entries)
                }
            }
        }
    }

    /// Eén regel in selectiemodus: dezelfde regel als anders, met een rondje
    /// ervoor. Tikken selecteert in plaats van openen.
    private func selectableRow(_ entry: TranscriptEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: selection.contains(entry.id) ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20))
                .foregroundStyle(selection.contains(entry.id) ? Theme.accentText : Theme.textTertiary)
            TranscriptRowiOS(entry: entry)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if selection.contains(entry.id) {
                selection.remove(entry.id)
            } else {
                selection.insert(entry.id)
            }
        }
    }

    /// De balk onderaan tijdens het selecteren: drie compacte knoppen in de
    /// knoppentaal, met het aantal gekozen opnames als grijze regel eronder.
    /// Deel is de hoofdactie en dus het enige primaire (gele) blok.
    private func selectionBar(entries: [TranscriptEntry]) -> some View {
        let chosen = entries.filter { selection.contains($0.id) }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Button {
                    selection = chosen.count == entries.count ? [] : Set(entries.map(\.id))
                } label: {
                    IconActionLabel(
                        title: chosen.count == entries.count
                            ? L10n.string( "Niets", locale: app.interfaceLanguage.locale)
                            : L10n.string( "Alles", locale: app.interfaceLanguage.locale),
                        systemImage: "checklist"
                    )
                }
                .buttonStyle(.plain)

                Button {
                    mergeTarget = MergeTarget(entries: chosen)
                } label: {
                    IconActionLabel(
                        title: L10n.string( "Voeg samen", locale: app.interfaceLanguage.locale),
                        systemImage: "arrow.triangle.merge",
                        isEnabled: chosen.count >= 2
                    )
                }
                .buttonStyle(.plain)
                .disabled(chosen.count < 2)

                ShareLink(item: Self.combinedText(chosen, locale: app.interfaceLanguage.locale)) {
                    IconActionLabel(
                        title: L10n.string( "Deel", locale: app.interfaceLanguage.locale),
                        systemImage: "square.and.arrow.up",
                        isEnabled: !chosen.isEmpty
                    )
                }
                .buttonStyle(.plain)
                .disabled(chosen.isEmpty)

                // Geel als de andere acties; de bevestigvraag vangt een
                // mistik op. Rood is voor het kruisje bovenaan, dat de
                // selectie afbreekt (wens Niels, 2 sep 2026).
                Button {
                    showDeleteSelectedConfirm = true
                } label: {
                    IconActionLabel(
                        title: L10n.string( "Verwijder", locale: app.interfaceLanguage.locale),
                        systemImage: "trash",
                        isEnabled: !chosen.isEmpty
                    )
                }
                .buttonStyle(.plain)
                .disabled(chosen.isEmpty)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Theme.surface)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.border).frame(height: Theme.Metrics.hairline)
        }
    }

    /// Titel, datum en tekst per opname, gescheiden door een lege regel.
    ///
    /// Staat sinds 14 augustus 2026 in `TranscriptMerge` (Core), zodat de Mac
    /// dezelfde tekst oplevert. Eén verschil met de oude iPhone-versie: de
    /// opnames staan nu op tijdsvolgorde in plaats van de volgorde van de lijst,
    /// net als bij samenvoegen. Met de lijst op "nieuwste eerst" kwam het
    /// verhaal anders achterstevoren in de mail.
    static func combinedText(_ entries: [TranscriptEntry], locale: Locale) -> String {
        TranscriptMerge.combinedText(entries, locale: locale) { $0.displayTitle(locale: locale) }
    }

    /// Verwijdert alle geselecteerde opnames, na de bevestigvraag.
    private func deleteSelected() {
        guard let history = app.history else { return }
        do {
            // In één transactie: een fout halverwege liet anders een deel van de
            // selectie verwijderd achter.
            try history.deleteMany(ids: Array(selection))
            selection = []
            isSelecting = false
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

    private func deleteTranscript(_ id: String) {
        guard let history = app.history else { return }
        do {
            try history.delete(id: id)
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

    /// De knoppen op een eigen regel, het aantal eronder. Alle drie samen op één
    /// regel mét tekst paste niet naast het aantal: iOS brak de labels toen in
    /// drie stukken af (13 aug 2026). Het aantal is toelichting, dus die mag
    /// eronder en grijs.
    private func controlsRow(visible: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if isSelecting {
                // Tijdens het selecteren: het aantal links, het kruisje
                // rechtsboven, waar iedereen een sluitknop verwacht. Rood,
                // want het breekt de selectie af (wens Niels, 2 sep 2026).
                HStack {
                    Text(String(
                        format: L10n.string( "%lld geselecteerd", locale: app.interfaceLanguage.locale),
                        locale: app.interfaceLanguage.locale,
                        selection.count
                    ))
                    .font(ThemeFont.ui(15, weight: .medium))
                    .foregroundStyle(Theme.text)
                    Spacer()
                    Button {
                        isSelecting = false
                        selection = []
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Theme.danger)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Klaar met selecteren")
                }
                .frame(height: 48)
                .padding(.bottom, 4)
            } else {
                HStack(spacing: 10) {
                    selectButton
                    filterMenu
                    sortMenu
                    // Eén syncknop voor iCloud én PLAUD samen: het onderscheid
                    // zei Niels niets, hij wil gewoon "alles binnenhalen"
                    // (2 sep 2026). Instellen blijft in Instellingen.
                    // Valt er niets te halen (geen iCloud én geen PLAUD-account),
                    // dan staat de knop er helemaal niet; uitgegrijsd liet hij
                    // een dode knop zien waar niets mee te doen was.
                    if SyncAvailability.any(app) {
                        SyncAllButton(app: app, plaud: app.plaudSync, isCloudSyncing: $isCloudSyncing)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 10)
            }
            // Beide strepen zelf getekend, identiek. Eerst was de onderste de
            // systeemscheiding van de lijst en die rendert lichter; het aantal
            // hing bovendien te dicht tegen de knoppen (13 aug 2026).
            Rectangle().fill(Theme.border).frame(height: Theme.Metrics.hairline)
            VStack(alignment: .leading, spacing: 3) {
                Text(countLabel(visible: visible, total: total))
                    .lineLimit(1)
                // De Sync-knop gaf geen enkel teken van leven. Zijn uitkomst
                // hoort hier, in dezelfde grijze regel als het aantal
                // (2 sep 2026).
                if !isSelecting {
                    SyncStatusLine(app: app, plaud: app.plaudSync, isCloudSyncing: isCloudSyncing)
                }
            }
            .font(ThemeFont.ui(13, weight: .medium))
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            Rectangle().fill(Theme.border).frame(height: Theme.Metrics.hairline)
        }
    }

    private var selectButton: some View {
        Button {
            isSelecting.toggle()
            if !isSelecting { selection = [] }
        } label: {
            IconActionLabel(
                title: isSelecting
                    ? L10n.string( "Klaar", locale: app.interfaceLanguage.locale)
                    : L10n.string( "Selecteer", locale: app.interfaceLanguage.locale),
                // Kale varianten, geen cirkels: omcirkelde symbolen ogen
                // kleiner dan de iconen op het detailscherm (13 aug 2026).
                // Label grijs, ook als Klaar: de selectiemodus is geen
                // "actieve stand" die geel verdient (correctie 13 aug 2026).
                systemImage: "checkmark"
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSelecting ? "Klaar met selecteren" : "Selecteer opnames")
    }

    private var filterMenu: some View {
        Menu {
            Picker("Apparaat", selection: $deviceFilter) {
                ForEach(DeviceFilter.allCases) { Text($0.label(in: app.interfaceLanguage)).tag($0) }
            }
            Picker("Lengte", selection: $durationFilter) {
                ForEach(DurationFilter.allCases) { Text($0.label(in: app.interfaceLanguage)).tag($0) }
            }
            Picker("Sprekers", selection: $speakerFilter) {
                ForEach(SpeakerFilter.allCases) { Text($0.label(in: app.interfaceLanguage)).tag($0) }
            }
            Picker("Titel", selection: $titleFilter) {
                ForEach(TitleFilter.allCases) { Text($0.label(in: app.interfaceLanguage)).tag($0) }
            }
            if filtersAreActive {
                Divider()
                Button("Wis filters", role: .destructive) { resetFilters() }
            }
        } label: {
            IconActionLabel(
                title: L10n.string( "Filter", locale: app.interfaceLanguage.locale),
                systemImage: "line.3.horizontal.decrease",
                isActive: filtersAreActive
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Filter")
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sorteren", selection: $sortOrder) {
                ForEach(SortOrder.allCases) { Text($0.label(in: app.interfaceLanguage)).tag($0) }
            }
        } label: {
            IconActionLabel(
                title: L10n.string( "Sorteer", locale: app.interfaceLanguage.locale),
                systemImage: "arrow.up.arrow.down"
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sorteer")
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 40))
                .foregroundStyle(Theme.textTertiary)
            Text(query.isEmpty && !filtersAreActive
                 ? L10n.string( "Nog geen opnames", locale: app.interfaceLanguage.locale)
                 : L10n.string( "Geen resultaten", locale: app.interfaceLanguage.locale))
                .font(ThemeFont.ui(17, weight: .semibold))
                .foregroundStyle(Theme.text)
            if query.isEmpty && !filtersAreActive && app.showHelpTips {
                Text("Neem iets op via het tabblad Opnemen.")
                    .font(ThemeFont.ui(14))
                    .foregroundStyle(Theme.textSecondary)
            } else if deviceFilter == .iphone {
                Text("Nieuwe iPhone-opnames krijgen automatisch het label iPhone. Bij oudere opnames is het apparaat nog onbekend.")
                    .font(ThemeFont.ui(14))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
    }

    private func reloadHistory() async {
        guard let history = app.history else { return }
        do {
            let snapshot = try await history.historySnapshot(query: query.isEmpty ? nil : query)
            try Task.checkCancellation()
            let filtered = snapshot.entries.filter(matchesFilters)
            // SQLite already ordered by the persisted timestamp. Do not reparse
            // ISO dates thousands of times while the native tab animates.
            switch sortOrder {
            case .newest: visibleEntries = filtered
            case .oldest: visibleEntries = Array(filtered.reversed())
            default: visibleEntries = filtered.sorted(by: isOrdered)
            }
            historyTotal = snapshot.total
        } catch is CancellationError {
            // A newer search/filter/revision owns the next result.
        } catch {
            guard !Task.isCancelled else { return }
            // Keep the last successful snapshot rather than presenting data loss.
            app.errorMessage = error.localizedDescription
        }
    }

    private var filtersAreActive: Bool {
        durationFilter != .all || deviceFilter != .all || speakerFilter != .all || titleFilter != .all
    }

    private func resetFilters() {
        durationFilter = .all
        deviceFilter = .all
        speakerFilter = .all
        titleFilter = .all
    }

    private func matchesFilters(_ entry: TranscriptEntry) -> Bool {
        durationFilter.matches(entry.duration)
            && deviceFilter.matches(entry.source)
            && (speakerFilter == .all || speakerFilter.matches(speakerCount(of: entry)))
            && titleFilter.matches(entry.name)
    }

    private func speakerCount(of entry: TranscriptEntry) -> Int {
        Set(entry.segments.compactMap(\.speaker).filter { !$0.isEmpty }).count
    }

    private func isOrdered(_ lhs: TranscriptEntry, _ rhs: TranscriptEntry) -> Bool {
        switch sortOrder {
        case .newest: return (lhs.timestamp ?? .distantPast) > (rhs.timestamp ?? .distantPast)
        case .oldest: return (lhs.timestamp ?? .distantPast) < (rhs.timestamp ?? .distantPast)
        case .nameAZ: return displayTitle(lhs).localizedCaseInsensitiveCompare(displayTitle(rhs)) == .orderedAscending
        case .nameZA: return displayTitle(lhs).localizedCaseInsensitiveCompare(displayTitle(rhs)) == .orderedDescending
        case .longest: return lhs.duration > rhs.duration
        case .shortest: return lhs.duration < rhs.duration
        }
    }

    private func displayTitle(_ entry: TranscriptEntry) -> String {
        let name = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty || name.localizedCaseInsensitiveCompare("PLAUD-opname") == .orderedSame
            ? String(entry.text.prefix(60))
            : name
    }

    private func countLabel(visible: Int, total: Int) -> String {
        let locale = app.interfaceLanguage.locale
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !filtersAreActive {
            return total == 1
                ? L10n.string( "1 opname", locale: locale)
                : String(format: L10n.string( "%lld opnames", locale: locale), locale: locale, total)
        }
        return String(
            format: L10n.string( "%1$lld van %2$lld opnames", locale: locale),
            locale: locale,
            visible,
            total
        )
    }

    private func entryByID(_ id: String) -> TranscriptEntry? {
        (try? app.history?.record(id: id))?.entry
    }
}

private enum DurationFilter: String, CaseIterable, Identifiable {
    case all, underOne, oneToFive, fiveToTen, tenToTwenty, twentyToSixty, overSixty
    var id: String { rawValue }
    func label(in language: AppLanguage) -> String { switch self {
    case .all: L10n.string( "Alle lengtes", locale: language.locale)
    case .underOne: L10n.string( "Korter dan 1 minuut", locale: language.locale)
    case .oneToFive: L10n.string( "1–5 minuten", locale: language.locale)
    case .fiveToTen: L10n.string( "5–10 minuten", locale: language.locale)
    case .tenToTwenty: L10n.string( "10–20 minuten", locale: language.locale)
    case .twentyToSixty: L10n.string( "20–60 minuten", locale: language.locale)
    case .overSixty: L10n.string( "Langer dan 1 uur", locale: language.locale)
    }}
    func matches(_ seconds: Double) -> Bool { switch self {
    case .all: true; case .underOne: seconds < 60; case .oneToFive: seconds >= 60 && seconds < 300
    case .fiveToTen: seconds >= 300 && seconds < 600; case .tenToTwenty: seconds >= 600 && seconds < 1_200
    case .twentyToSixty: seconds >= 1_200 && seconds < 3_600; case .overSixty: seconds >= 3_600
    }}
}

private enum DeviceFilter: String, CaseIterable, Identifiable {
    case all, mac, iphone, plaud, unknown
    var id: String { rawValue }
    func label(in language: AppLanguage) -> String { switch self {
    case .all: L10n.string( "Alle bronnen", locale: language.locale)
    case .mac: "Mac"; case .iphone: "iPhone"
    case .plaud: "PLAUD"
    case .unknown: L10n.string( "Ouder/onbekend", locale: language.locale)
    } }
    func matches(_ source: String) -> Bool { switch self {
    case .all: true
    case .mac: source.hasSuffix(".mac") && !source.hasPrefix("plaud")
    case .iphone: source.hasSuffix(".ios") && !source.hasPrefix("plaud")
    case .plaud: source == "plaud" || source.hasPrefix("plaud.")
    case .unknown: !source.hasSuffix(".mac") && !source.hasSuffix(".ios")
        && source != "plaud" && !source.hasPrefix("plaud.")
    }}
}

private enum SpeakerFilter: String, CaseIterable, Identifiable {
    case all, one, two, threePlus
    var id: String { rawValue }
    func label(in language: AppLanguage) -> String { switch self {
    case .all: L10n.string( "Elk aantal sprekers", locale: language.locale)
    case .one: L10n.string( "1 spreker", locale: language.locale)
    case .two: L10n.string( "2 sprekers", locale: language.locale)
    case .threePlus: L10n.string( "3 of meer sprekers", locale: language.locale)
    } }
    func matches(_ count: Int) -> Bool { switch self { case .all: true; case .one: count == 1; case .two: count == 2; case .threePlus: count >= 3 } }
}

private enum TitleFilter: String, CaseIterable, Identifiable {
    case all, filled, empty
    var id: String { rawValue }
    func label(in language: AppLanguage) -> String { switch self {
    case .all: L10n.string( "Alle titels", locale: language.locale)
    case .filled: L10n.string( "Titel ingevuld", locale: language.locale)
    case .empty: L10n.string( "Geen titel", locale: language.locale)
    } }
    func matches(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let filled = !trimmed.isEmpty && trimmed.localizedCaseInsensitiveCompare("PLAUD-opname") != .orderedSame
        return switch self { case .all: true; case .filled: filled; case .empty: !filled }
    }
}

private enum SortOrder: String, CaseIterable, Identifiable {
    case newest, oldest, nameAZ, nameZA, longest, shortest
    var id: String { rawValue }
    func label(in language: AppLanguage) -> String { switch self {
    case .newest: L10n.string( "Nieuwste eerst", locale: language.locale)
    case .oldest: L10n.string( "Oudste eerst", locale: language.locale)
    case .nameAZ: L10n.string( "Naam A–Z", locale: language.locale)
    case .nameZA: L10n.string( "Naam Z–A", locale: language.locale)
    case .longest: L10n.string( "Langste eerst", locale: language.locale)
    case .shortest: L10n.string( "Kortste eerst", locale: language.locale)
    } }
}

/// Of er überhaupt iets te synchroniseren valt. Gedeeld door de knop en de
/// statusregel eronder, zodat ze nooit uit elkaar lopen.
@MainActor
private enum SyncAvailability {
    static func cloud(_ app: AppModel) -> Bool {
        guard app.icloudSyncEnabled, let sync = app.historySync else { return false }
        switch sync.status {
        case .active, .error: return true
        case .disabled, .unavailable, .requiresApproval: return false
        }
    }

    static var plaud: Bool {
        #if WHISPERCLIP_PERSONAL || !WHISPERCLIP_PUBLIC
        PlaudCredentials.load()?.isConfigured == true
        #else
        false
        #endif
    }

    static func any(_ app: AppModel) -> Bool { cloud(app) || plaud }
}

/// De grijze regel onder de knoppenrij die vertelt wat de Sync-knop doet of
/// heeft gedaan. Eigen view zodat hij met de PLAUD-service meedraait.
private struct SyncStatusLine: View {
    @ObservedObject var app: AppModel
    @ObservedObject var plaud: PlaudSynciOSService
    let isCloudSyncing: Bool

    var body: some View {
        if let text {
            Text(text)
                .foregroundStyle(errorText == nil ? Theme.textSecondary : Theme.danger)
                .lineLimit(2)
        }
    }

    private var text: String? {
        let locale = app.interfaceLanguage.locale
        if isCloudSyncing || plaud.isSyncing {
            return plaud.progressText.isEmpty
                ? L10n.string( "Synchroniseren…", locale: locale)
                : plaud.progressText
        }
        if let errorText { return errorText }
        guard let last = lastSynced else { return nil }
        return String(
            format: L10n.string( "Bijgewerkt om %@", locale: locale),
            locale: locale,
            last.formatted(.dateTime.hour().minute().locale(locale))
        )
    }

    private var errorText: String? {
        if let error = plaud.lastError { return error }
        if case .error(let message) = app.historySync?.status {
            return String(
                format: L10n.string( "Fout: %@", locale: app.interfaceLanguage.locale),
                locale: app.interfaceLanguage.locale,
                message
            )
        }
        return nil
    }

    /// Het jongste van beide momenten: één regel voor twee bronnen.
    private var lastSynced: Date? {
        var moments: [Date] = []
        if let plaudMoment = plaud.lastSyncedAt { moments.append(plaudMoment) }
        if case .active(let cloudMoment) = app.historySync?.status, let cloudMoment {
            moments.append(cloudMoment)
        }
        return moments.max()
    }
}

/// Eén knop die alles binnenhaalt: iCloud (als sync aanstaat en werkt) en
/// PLAUD (als er een account is), tegelijk. Eigen view zodat hij de
/// PLAUD-service observeert en meedraait met de voortgang.
private struct SyncAllButton: View {
    @ObservedObject var app: AppModel
    @ObservedObject var plaud: PlaudSynciOSService
    @Binding var isCloudSyncing: Bool

    private var cloudAvailable: Bool { SyncAvailability.cloud(app) }

    private var plaudAvailable: Bool { SyncAvailability.plaud }

    var body: some View {
        let busy = isCloudSyncing || plaud.isSyncing
        let available = cloudAvailable || plaudAvailable
        Button {
            guard !busy else { return }
            if cloudAvailable, let sync = app.historySync {
                isCloudSyncing = true
                Task {
                    await sync.syncNow()
                    isCloudSyncing = false
                }
            }
            if plaudAvailable {
                plaud.syncNow()
            }
        } label: {
            IconActionLabel(
                title: busy
                    ? L10n.string( "Bezig…", locale: app.interfaceLanguage.locale)
                    : L10n.string( "Sync", locale: app.interfaceLanguage.locale),
                systemImage: "arrow.triangle.2.circlepath",
                isEnabled: available && !busy
            )
        }
        .buttonStyle(.plain)
        .disabled(!available || busy)
        .accessibilityLabel("Synchroniseer met iCloud en PLAUD")
    }
}

// MARK: - Row

struct TranscriptRowiOS: View {
    @EnvironmentObject private var app: AppModel
    let entry: TranscriptEntry

    var body: some View {
        HStack(spacing: 12) {
            // Geel, want de hele regel is klikbaar en opent de opname; in de
            // detailkop is hetzelfde icoon informatie en dus grijs (13 aug 2026).
            Image(systemName: TranscriptSourceStyle.icon(for: entry.source))
                .font(.system(size: 16))
                .foregroundStyle(Theme.accentText)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(ThemeFont.ui(16, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(relativeDate)
                    if entry.duration > 0 {
                        Text("·")
                        Text(durationText)
                    }
                }
                .font(ThemeFont.ui(13))
                .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if entry.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.accentText)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private var title: String {
        entry.displayTitle(locale: app.interfaceLanguage.locale)
    }

    /// Een echte datum en tijd, geen "twee weken geleden": Niels zoekt op datum
    /// en moest daarvoor telkens een opname openen (wens 2026-08-02).
    private var relativeDate: String {
        guard let date = entry.timestamp else { return entry.createdAt }
        return date.formatted(
            .dateTime.day().month(.abbreviated).year().hour().minute()
                .locale(app.interfaceLanguage.locale)
        )
    }

    private var durationText: String {
        DurationText.string(seconds: entry.duration, locale: app.interfaceLanguage.locale)
    }
}

extension TranscriptEntry {
    /// De titel zoals hij in de lijst staat: de eigen naam, of anders de eerste
    /// zestig tekens van het transcript. Eén plek, zodat de lijst en het delen
    /// nooit uit elkaar kunnen lopen.
    func displayTitle(locale: Locale) -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty && trimmedName.localizedCaseInsensitiveCompare("PLAUD-opname") != .orderedSame {
            return trimmedName
        }
        let firstWords = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(60)
        return firstWords.isEmpty
            ? L10n.string( "Naamloze opname", locale: locale)
            : String(firstWords)
    }
}
