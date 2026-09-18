import AppKit
import Core
import Combine
import Foundation
import SwiftUI
import WhisperShared

/// The full history browser: a searchable, filterable list on the left and the
/// selected transcript's detail on the right.
struct HistoryListView: View {
    @ObservedObject var store: HistoryStore
    @ObservedObject var navigation: AppNavigation
    var modes: ModesService

    /// Voor de sync-knop in de kop. Tot 14 augustus 2026 zat synchroniseren
    /// alleen in Instellingen ▸ Algemeen, drie klikken diep, terwijl je juist
    /// hier staat als je je opnames mist.
    @EnvironmentObject private var environment: AppEnvironment

    @State private var rawQuery = ""
    @State private var debouncedQuery = ""
    @State private var filter: HistoryFilter = .all
    @State private var durationFilter: DurationFilter = .any
    @State private var deviceFilter: DeviceFilter = .any
    @State private var speakerFilter: SpeakerFilter = .any
    @State private var titleFilter: TitleFilter = .any
    @State private var sortOrder: SortOrder = .newest
    /// De geselecteerde opnames. Meervoud sinds 14 augustus 2026, op de
    /// Mac-manier: cmd-klik zet er één bij of haalt er één weg, shift-klik pakt
    /// een reeks, gewoon klikken selecteert er één. Geen knop "Selecteer" en
    /// geen rondjes voor de rijen: dat is de iPhone-vorm, en op een Mac verwacht
    /// je Finder-gedrag (keuze van Niels).
    @State private var selection: Set<String> = []

    /// Het vertrekpunt voor shift-klik: de laatst met een gewone klik of
    /// cmd-klik aangeraakte rij.
    @State private var anchorID: String?
    @State private var renamingID: String?
    @State private var renameText = ""
    @State private var deletingEntry: TranscriptEntry?


    /// Of de keuzevraag bij samenvoegen open staat: originelen bewaren of niet.
    @State private var showMergeChoice = false

    /// Of de bevestigvraag bij het verwijderen van een selectie open staat.
    @State private var showMultiDeleteConfirmation = false

    /// De zichtbare lijst, één keer opgehaald per echte wijziging.
    ///
    /// Bevinding 2026-08-04: dit was een computed property die bij ELKE
    /// body-pass een blokkerende `dbQueue.read` van 500 rijen deed, inclusief
    /// JSON-decode van alle segmenten — en `listPane`, `listContent`,
    /// `detailPane` en `selectedEntry` lazen hem allemaal, dus drie à vier van
    /// die queries per pass, synchroon op de main thread. Dat is de merkbare
    /// vertraging bij elke klik.
    @State private var entries: [TranscriptEntry] = []
    @State private var refreshTask: Task<Void, Never>?
    @State private var selectFirstAfterRefresh = false

    /// Of de eerste query al gedraaid heeft. Zonder deze vlag zou de lege staat
    /// ("Nog geen transcripties") één frame flitsen voordat `onAppear` de cache
    /// vult. Bevinding 2026-08-04.
    @State private var hasLoaded = false

    /// Melding van een mislukte schrijfactie naar de store. Bevinding
    /// 2026-08-03: verwijderen, vastzetten en hernoemen liepen via `try?`, dus
    /// een mislukte opslag was onzichtbaar en de lijst deed alsof het gelukt was.
    @State private var dataError: String?

    @State private var searchDebounce = PassthroughSubject<String, Never>()

    var body: some View {
        // A plain HSplitView inside the single NavigationSplitView's detail column
        // (never a nested NavigationSplitView). Minimums are chosen so the pair
        // fits the window's minimum content width alongside the 180pt sidebar.
        HSplitView {
            listPane
                .frame(minWidth: 300, idealWidth: 340, maxWidth: 420)
            detailPane
                .frame(minWidth: 460, maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.window)
        .confirmationDialog(
            "Verwijder deze transcriptie?",
            isPresented: Binding(
                get: { deletingEntry != nil },
                set: { if !$0 { deletingEntry = nil } }
            ),
            presenting: deletingEntry
        ) { entry in
            Button("Verwijder", role: .destructive) {
                // Bevinding 2026-08-03: de selectie schoof onvoorwaardelijk door,
                // ook wanneer het verwijderen mislukte — de rij stond er nog maar
                // de gebruiker zag hem niet meer.
                let deleted = DataChange.perform(
                    "Het verwijderen van de transcriptie",
                    reporting: $dataError
                ) {
                    try store.delete(id: entry.id)
                }
                deletingEntry = nil
                guard deleted else { return }
                // Eerst verversen, dan pas de selectie doorschuiven: de cache
                // bevat anders nog de zojuist verwijderde rij (bevinding
                // 2026-08-04).
                refreshEntries()
                if selection.contains(entry.id) {
                    selection.remove(entry.id)
                    if selection.isEmpty { selectFirstAfterRefresh = true }
                }
            }
            Button("Annuleer", role: .cancel) { deletingEntry = nil }
        } message: { _ in
            Text(AudioCopy.text(.deleteTogether))
        }
        .confirmationDialog(
            "\(selection.count) opnames samenvoegen tot één?",
            isPresented: $showMergeChoice
        ) {
            Button("Samenvoegen, originelen bewaren") { mergeSelection(deleteOriginals: false) }
            Button("Samenvoegen, originelen verwijderen", role: .destructive) {
                mergeSelection(deleteOriginals: true)
            }
            Button("Annuleer", role: .cancel) {}
        } message: {
            Text(AudioCopy.text(.mergeWarning))
        }
        .confirmationDialog(
            "\(selection.count) opnames verwijderen?",
            isPresented: $showMultiDeleteConfirmation
        ) {
            Button("Verwijder", role: .destructive) { deleteSelection() }
            Button("Annuleer", role: .cancel) {}
        } message: {
            Text(AudioCopy.text(.deleteTogether))
        }
        .dataChangeAlert($dataError)
        // DispatchQueue.main delivers across run-loop modes, so the debounce
        // still fires while the user is scrolling or dragging the divider.
        .onReceive(searchDebounce.debounce(for: .milliseconds(220), scheduler: DispatchQueue.main)) { value in
            debouncedQuery = value
        }
        .onChange(of: navigation.pendingTranscriptID) { _, id in
            if let id { select(id); navigation.pendingTranscriptID = nil }
        }
        // Eén query per echte wijziging: zoektekst, filters of sortering
        // (samengebald in `criteria`), of een mutatie in de store.
        .onChange(of: criteria) { _, _ in refreshEntries() }
        // `revision` bumpt na élke mutatie van de store — lokaal (verwijderen,
        // hernoemen, vastzetten, import) én bij binnenkomende iCloud-sync.
        .onChange(of: store.revision) { _, _ in refreshEntries() }
        .onDisappear { refreshTask?.cancel() }
        .onAppear {
            refreshEntries()
            if let id = navigation.pendingTranscriptID {
                select(id)
                navigation.pendingTranscriptID = nil
            } else if selection.isEmpty {
                selectFirstAfterRefresh = true
            }
        }
    }

    // MARK: - List pane

    private var listPane: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Geschiedenis")
                    .font(ThemeFont.ui(20, weight: .bold))
                    .foregroundStyle(Theme.text)
                Spacer()
                Text("\(entries.count)")
                    .font(ThemeFont.ui(12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                SyncNowButton(
                    historySync: environment.historySync,
                    onCompletion: refreshEntries
                )
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 2)
            searchField
            filterChips
            advancedControls
            selectionBar
            Divider().overlay(Theme.border)
            listContent
        }
        .background(Theme.window)
    }

    // MARK: - Selectie

    /// Eén selectie, zoals bij een gewone klik.
    private func select(_ id: String?) {
        selection = id.map { [$0] } ?? []
        anchorID = id
    }

    /// De opname die rechts in het detailpaneel staat. Bij meer dan één
    /// geselecteerde rij toont het detailpaneel niets: dan gaat het om de
    /// selectie als geheel en niet om één transcript.
    private var selectedID: String? {
        selection.count == 1 ? selection.first : nil
    }

    private func handleClick(on entry: TranscriptEntry, modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.command) {
            if selection.contains(entry.id) {
                selection.remove(entry.id)
            } else {
                selection.insert(entry.id)
            }
            anchorID = entry.id
            return
        }
        if modifiers.contains(.shift), let anchorID,
           let van = entries.firstIndex(where: { $0.id == anchorID }),
           let tot = entries.firstIndex(where: { $0.id == entry.id }) {
            let bereik = van <= tot ? van...tot : tot...van
            selection.formUnion(entries[bereik].map(\.id))
            return
        }
        select(entry.id)
    }

    /// De geselecteerde opnames, in de volgorde van de lijst.
    private var selectedEntries: [TranscriptEntry] {
        entries.filter { selection.contains($0.id) }
    }

    // MARK: - Selectiebalk

    /// Verschijnt zodra er meer dan één opname geselecteerd is. Bewust geen
    /// balk onderaan zoals op de iPhone: op een Mac horen de acties bij de
    /// bediening boven de lijst.
    @ViewBuilder
    private var selectionBar: some View {
        if selection.count >= 2 {
            HStack(spacing: 8) {
                Text("\(selection.count) geselecteerd")
                    .font(ThemeFont.ui(11))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize()
                Spacer(minLength: 8)
                ActionButton(
                    title: "Voeg samen",
                    systemImage: "arrow.triangle.merge",
                    role: .primary,
                    size: .compact
                ) { showMergeChoice = true }
                ActionButton(
                    title: "Kopieer",
                    systemImage: "doc.on.doc",
                    size: .compact
                ) { copySelection() }
                ActionButton(
                    title: "Verwijder",
                    systemImage: "trash",
                    role: .destructive,
                    size: .compact
                ) { showMultiDeleteConfirmation = true }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
    }

    /// Voegt de selectie samen tot één nieuwe opname. Het samenvoegen zelf komt
    /// uit `TranscriptMerge` (Core), dezelfde code die de iPhone gebruikt.
    private func mergeSelection(deleteOriginals: Bool) {
        let gekozen = selectedEntries
        guard let eerste = TranscriptMerge.sortedByTime(gekozen).first,
              let samengevoegd = TranscriptMerge.merge(
                  gekozen,
                  naam: "\(TranscriptFormatting.title(for: eerste)) (samengevoegd)"
              )
        else { return }
        let gelukt = DataChange.perform(
            "Het samenvoegen van de transcripties",
            reporting: $dataError
        ) {
            if deleteOriginals {
                try store.mergeAndReplace(merged: samengevoegd, deleting: gekozen.map(\.id))
            } else { try store.add(samengevoegd) }
        }
        guard gelukt else { return }
        refreshEntries()
        select(samengevoegd.id)
    }

    /// De selectie als één stuk leesbare tekst op het klembord. De Mac heeft
    /// geen deelvenster zoals de iPhone; kopiëren is hier de gewone weg.
    private func copySelection() {
        let tekst = TranscriptMerge.combinedText(
            selectedEntries,
            locale: Locale(identifier: "nl_NL")
        ) { TranscriptFormatting.title(for: $0) }
        guard !tekst.isEmpty else { return }
        Clipboard.copy(tekst)
        Notifications.post("\(selection.count) transcripties gekopieerd")
    }

    private func deleteSelection() {
        let ids = selection
        let gelukt = DataChange.perform(
            "Het verwijderen van de transcripties",
            reporting: $dataError
        ) {
            try store.deleteMany(ids: Array(ids))
        }
        guard gelukt else { return }
        selection.removeAll()
        selectFirstAfterRefresh = true
        refreshEntries()
    }

    private var advancedControls: some View {
        HStack(spacing: 8) {
            Menu {
                Picker("Apparaat", selection: $deviceFilter) {
                    ForEach(DeviceFilter.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Divider()
                Picker("Lengte", selection: $durationFilter) {
                    ForEach(DurationFilter.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Divider()
                Picker("Sprekers", selection: $speakerFilter) {
                    ForEach(SpeakerFilter.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Divider()
                Picker("Titel", selection: $titleFilter) {
                    ForEach(TitleFilter.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                if hasAdvancedFilters {
                    Divider()
                    Button("Wis extra filters") {
                        deviceFilter = .any
                        durationFilter = .any
                        speakerFilter = .any
                        titleFilter = .any
                    }
                }
            } label: {
                Label(hasAdvancedFilters ? "Filter actief" : "Filter", systemImage: "line.3.horizontal.decrease.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.radius))
            .overlay(RoundedRectangle(cornerRadius: Theme.Metrics.radius).strokeBorder(Theme.border, lineWidth: 1))

            Menu {
                Picker("Sortering", selection: $sortOrder) {
                    ForEach(SortOrder.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            } label: {
                Label(sortOrder.label, systemImage: "arrow.up.arrow.down")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.radius))
            .overlay(RoundedRectangle(cornerRadius: Theme.Metrics.radius).strokeBorder(Theme.border, lineWidth: 1))
            Spacer()
        }
        .font(ThemeFont.ui(11, weight: .medium))
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private var hasAdvancedFilters: Bool {
        deviceFilter != .any || durationFilter != .any || speakerFilter != .any || titleFilter != .any
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
            TextField("Zoek in transcripties", text: $rawQuery)
                .textFieldStyle(.plain)
                .font(ThemeFont.ui(13))
                .foregroundStyle(Theme.text)
                .onChange(of: rawQuery) { _, value in searchDebounce.send(value) }
            if !rawQuery.isEmpty {
                // Also push "" through the debounce so a still-pending emission
                // from a rapid type-then-clear can't re-apply the old query.
                Button { rawQuery = ""; debouncedQuery = ""; searchDebounce.send("") } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Metrics.radius).strokeBorder(Theme.border, lineWidth: 1))
        .padding(12)
    }

    private var filterChips: some View {
        HStack(spacing: 8) {
            ForEach(HistoryFilter.allCases, id: \.self) { option in
                FilterChip(
                    label: label(for: option),
                    selected: filter == option
                ) { filter = option }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private func label(for filter: HistoryFilter) -> String {
        switch filter {
        case .all: return "Alles"
        case .mic: return "Microfoon"
        case .file: return "Bestanden"
        case .plaud: return "PLAUD"
        }
    }

    @ViewBuilder
    private var listContent: some View {
        let items = entries
        if !hasLoaded {
            Color.clear
        } else if items.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(items, id: \.id) { entry in
                        row(for: entry)
                        Divider().overlay(Theme.border)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func row(for entry: TranscriptEntry) -> some View {
        Group {
            if renamingID == entry.id {
                renameRow(for: entry)
            } else {
                Button {
                    // De modifiers komen uit het klikevent zelf. SwiftUI geeft
                    // ze niet door aan een Button-actie, en een aparte
                    // TapGesture met .modifiers() naast de gewone tik levert
                    // twee gestures die om dezelfde klik vechten.
                    handleClick(on: entry, modifiers: NSApp.currentEvent?.modifierFlags ?? [])
                } label: {
                    TranscriptRow(
                        entry: entry,
                        onTogglePin: { togglePin(entry) }
                    )
                    .background(selection.contains(entry.id) ? Theme.surfaceHover : Color.clear)
                }
                .buttonStyle(.plain)
                .contextMenu { rowMenu(for: entry) }
            }
        }
    }

    private func renameRow(for entry: TranscriptEntry) -> some View {
        HStack(spacing: 8) {
            TextField("Naam", text: $renameText)
                .textFieldStyle(.plain)
                .font(ThemeFont.ui(13, weight: .medium))
                .foregroundStyle(Theme.text)
                .onSubmit { commitRename(entry) }
            Button("Bewaar") { commitRename(entry) }
                .buttonStyle(.plain)
                .font(ThemeFont.ui(11, weight: .semibold))
                .foregroundStyle(Theme.accentText)
            Button("Annuleer") { renamingID = nil }
                .buttonStyle(.plain)
                .font(ThemeFont.ui(11))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.surfaceHover)
    }

    @ViewBuilder
    private func rowMenu(for entry: TranscriptEntry) -> some View {
        Button("Kopieer") { Clipboard.copy(entry.text) }
        Button("Hernoem") {
            renameText = entry.name
            renamingID = entry.id
        }
        Button(entry.pinned ? "Losmaken" : "Vastzetten") { togglePin(entry) }
        Divider()
        Button("Verwijder", role: .destructive) { deletingEntry = entry }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: debouncedQuery.isEmpty ? "tray" : "magnifyingglass")
                .font(.system(size: 26))
                .foregroundStyle(Theme.textTertiary)
            Text(debouncedQuery.isEmpty ? "Nog geen transcripties" : "Geen resultaten")
                .font(ThemeFont.ui(13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            if debouncedQuery.isEmpty {
                Text("Start een opname om je eerste transcriptie te maken.")
                    .font(ThemeFont.ui(12))
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    // MARK: - Detail pane

    @ViewBuilder
    private var detailPane: some View {
        if let entry = selectedEntry {
            TranscriptDetailView(
                entry: entry,
                store: store,
                modes: modes,
                // Ook hier eerst verversen: de cache bevat de zojuist in het
                // detailpaneel verwijderde rij nog (bevinding 2026-08-04).
                onDeleted: {
                    selection.removeAll()
                    selectFirstAfterRefresh = true
                    refreshEntries()
                }
            )
            .id(entry.id)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 28))
                    .foregroundStyle(Theme.textTertiary)
                Text("Kies een transcriptie")
                    .font(ThemeFont.ui(13))
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.window)
        }
    }

    // MARK: - Data

    /// Alles wat de zichtbare lijst bepaalt, in één waarde. Zo volstaat één
    /// `onChange` en kan er geen filter vergeten worden bij het verversen.
    private struct ListCriteria: Equatable {
        var query: String
        var filter: HistoryFilter
        var device: DeviceFilter
        var duration: DurationFilter
        var speaker: SpeakerFilter
        var title: TitleFilter
        var sort: SortOrder
    }

    private var criteria: ListCriteria {
        ListCriteria(
            query: debouncedQuery,
            filter: filter,
            device: deviceFilter,
            duration: durationFilter,
            speaker: speakerFilter,
            title: titleFilter,
            sort: sortOrder
        )
    }

    /// Read/decode off the UI thread; cancel stale searches and retain the last
    /// successful list on failure. SQLite already orders by absolute timestamp.
    private func refreshEntries() {
        refreshTask?.cancel()
        let requested = criteria
        refreshTask = Task { @MainActor in
            do {
                let snapshot = try await store.historySnapshot(query: requested.query, filter: requested.filter)
                try Task.checkCancellation()
                let filtered = snapshot.entries
                    .filter { requested.device.matches($0) }
                    .filter { requested.duration.matches($0.duration) }
                    .filter { requested.speaker == .any || requested.speaker.matches(speakerCount(of: $0)) }
                    .filter { requested.title.matches($0) }
                switch requested.sort {
                case .newest: entries = filtered
                case .oldest: entries = Array(filtered.reversed())
                default: entries = filtered.sorted(by: requested.sort.areInIncreasingOrder)
                }
                hasLoaded = true
                if selectFirstAfterRefresh {
                    select(entries.first?.id)
                    selectFirstAfterRefresh = false
                }
            } catch is CancellationError {
                // A newer request owns the result.
            } catch {
                guard !Task.isCancelled else { return }
                dataError = error.localizedDescription
            }
        }
    }

    private func speakerCount(of entry: TranscriptEntry) -> Int {
        Set(entry.segments.compactMap(\.speaker).filter { !$0.isEmpty }).count
    }

    /// The selected entry, resolved only within the currently visible list. If
    /// the selection was filtered/searched out (or deleted), the detail pane
    /// clears rather than showing a row that isn't in the list.
    ///
    /// Bevinding 2026-08-04: dit deed de volledige query nóg een keer over.
    /// Leest nu uit de al opgehaalde lijst.
    private var selectedEntry: TranscriptEntry? {
        guard let selectedID else { return nil }
        return entries.first { $0.id == selectedID }
    }

    // MARK: - Actions

    private func togglePin(_ entry: TranscriptEntry) {
        DataChange.perform(
            entry.pinned ? "Het losmaken van de transcriptie" : "Het vastzetten van de transcriptie",
            reporting: $dataError
        ) {
            try store.setPinned(id: entry.id, !entry.pinned)
        }
    }

    private func commitRename(_ entry: TranscriptEntry) {
        // Bevinding 2026-08-03: het naamveld klapte dicht alsof de naam bewaard
        // was. Blijf bij een fout in bewerkmodus zodat de ingetypte naam blijft.
        let saved = DataChange.perform(
            "Het hernoemen van de transcriptie",
            reporting: $dataError
        ) {
            try store.rename(id: entry.id, name: renameText)
        }
        guard saved else { return }
        renamingID = nil
    }
}

private enum DeviceFilter: CaseIterable {
    case any, mac, iphone, unknown
    var label: String {
        switch self { case .any: "Alle apparaten"; case .mac: "Mac"; case .iphone: "iPhone"; case .unknown: "Ouder/onbekend" }
    }
    func matches(_ entry: TranscriptEntry) -> Bool {
        let device = TranscriptSourceStyle.device(for: entry.source)
        switch self { case .any: return true; case .mac: return device == "Mac"; case .iphone: return device == "iPhone"; case .unknown: return device == nil }
    }
}

private enum DurationFilter: CaseIterable {
    case any, under1, oneTo5, fiveTo10, tenTo20, twentyTo60, over60
    var label: String {
        switch self { case .any: "Alle lengtes"; case .under1: "Korter dan 1 minuut"; case .oneTo5: "1–5 minuten"; case .fiveTo10: "5–10 minuten"; case .tenTo20: "10–20 minuten"; case .twentyTo60: "20–60 minuten"; case .over60: "Langer dan 1 uur" }
    }
    func matches(_ seconds: Double) -> Bool {
        switch self { case .any: return true; case .under1: return seconds < 60; case .oneTo5: return seconds >= 60 && seconds < 300; case .fiveTo10: return seconds >= 300 && seconds < 600; case .tenTo20: return seconds >= 600 && seconds < 1200; case .twentyTo60: return seconds >= 1200 && seconds < 3600; case .over60: return seconds >= 3600 }
    }
}

private enum SpeakerFilter: CaseIterable {
    case any, one, two, threePlus
    var label: String { switch self { case .any: "Alle aantallen sprekers"; case .one: "1 spreker"; case .two: "2 sprekers"; case .threePlus: "3 of meer sprekers" } }
    func matches(_ count: Int) -> Bool { switch self { case .any: return true; case .one: return count <= 1; case .two: return count == 2; case .threePlus: return count >= 3 } }
}

private enum TitleFilter: CaseIterable {
    case any, titled, untitled
    var label: String { switch self { case .any: "Met en zonder titel"; case .titled: "Titel ingevuld"; case .untitled: "Geen titel ingevuld" } }
    func matches(_ entry: TranscriptEntry) -> Bool {
        let name = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasTitle = !name.isEmpty && name.localizedCaseInsensitiveCompare("PLAUD-opname") != .orderedSame
        switch self { case .any: return true; case .titled: return hasTitle; case .untitled: return !hasTitle }
    }
}

private enum SortOrder: CaseIterable {
    case newest, oldest, nameAZ, nameZA, longest, shortest
    var label: String { switch self { case .newest: "Nieuwste"; case .oldest: "Oudste"; case .nameAZ: "Naam A–Z"; case .nameZA: "Naam Z–A"; case .longest: "Langste"; case .shortest: "Kortste" } }
    func areInIncreasingOrder(_ lhs: TranscriptEntry, _ rhs: TranscriptEntry) -> Bool {
        switch self {
        case .newest: return (lhs.timestamp ?? .distantPast) > (rhs.timestamp ?? .distantPast)
        case .oldest: return (lhs.timestamp ?? .distantPast) < (rhs.timestamp ?? .distantPast)
        case .nameAZ: return displayName(lhs).localizedCaseInsensitiveCompare(displayName(rhs)) == .orderedAscending
        case .nameZA: return displayName(lhs).localizedCaseInsensitiveCompare(displayName(rhs)) == .orderedDescending
        case .longest: return lhs.duration > rhs.duration
        case .shortest: return lhs.duration < rhs.duration
        }
    }
    private func displayName(_ entry: TranscriptEntry) -> String {
        let name = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty || name.localizedCaseInsensitiveCompare("PLAUD-opname") == .orderedSame
            ? entry.text
            : name
    }
}

// MARK: - Filter chip

private struct FilterChip: View {
    let label: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(ThemeFont.ui(12, weight: .medium))
                .foregroundStyle(selected ? Theme.onAccent : Theme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(selected ? Theme.accent : Theme.surface)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(selected ? Color.clear : Theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
