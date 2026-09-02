import Core
import SwiftUI

/// The iOS companion app entry point: a four-tab shell ("Opnemen" / "Notule" /
/// "Notities" / "Geschiedenis") with a Settings gear in the toolbar. Record →
/// transcribe locally with Parakeet (Dutch) → history, iCloud-synced with the Mac
/// in a later round. Notities are doorlopende, benoemde notities waaraan je kunt
/// blijven toevoegen (i2; nog niet gesynct — zie HistorySchema/TranscriptCloudRecord).
@main
struct WhisperClipboardiOSApp: App {
    @StateObject private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentShell()
                .environmentObject(app)
                .environment(\.locale, app.interfaceLanguage.locale)
                .preferredColorScheme(app.appearance.preferredColorScheme)
                .tint(Theme.accentText)
        }
    }
}

/// Houdt Instellingen en de gekozen tab BUITEN de herbouw-grens. De tabs
/// worden bij een merk- of weergavewissel herbouwd (kleuren worden bij het
/// tekenen opgelost; zonder herbouw hielden tint, toolbar en pickers oude
/// kleuren vast), maar het instellingenvenster en de tabkeuze staan hier en
/// blijven dus gewoon open: wisselen schoot Niels eerst uit Instellingen
/// terug naar het startscherm (13 aug 2026).
private struct ContentShell: View {
    @EnvironmentObject private var app: AppModel
    @State private var showSettings = false
    @State private var selectedTab = 0

    /// Wanneer de app naar de achtergrond ging. Nil zolang hij op de voorgrond
    /// staat.
    @State private var backgroundedAt: Date?

    @Environment(\.scenePhase) private var scenePhase

    /// De tab met het opnamescherm. Zie `RootView`, waar de tags worden gezet.
    private static let recordTab = 0

    /// De sleutel die de herbouw van de schermboom stuurt. Bewust een eigen
    /// `@State` en niet rechtstreeks merk plus weergave: een wissel tijdens een
    /// opname zou de hele boom vervangen en daarmee de `RecordController` met de
    /// lopende opname weggooien zonder hem netjes af te sluiten. De sleutel loopt
    /// daarom pas mee zodra er niets meer opneemt.
    @State private var rebuildKey = ""

    private var themeKey: String {
        "\(app.brand.rawValue)-\(app.appearance.rawValue)"
    }

    private func refreshRebuildKey() {
        guard !app.isRecordingActive else { return }
        rebuildKey = themeKey
    }

    var body: some View {
        RootView(selection: $selectedTab, showSettings: $showSettings)
            .id(rebuildKey)
            .onAppear { rebuildKey = themeKey }
            .onChange(of: themeKey) { _, _ in refreshRebuildKey() }
            .onChange(of: app.isRecordingActive) { _, _ in refreshRebuildKey() }
            .onChange(of: scenePhase) { _, phase in
                handle(phase)
            }
            .sheet(isPresented: $showSettings) {
                SettingsSheet()
                    .environmentObject(app)
                    .preferredColorScheme(app.appearance.preferredColorScheme)
                    // Expliciet, niet alleen via de WindowGroup: het open
                    // venster hield anders de oude accentkleur vast tot je een
                    // scherm terugklikte (bug 13 aug 2026).
                    .tint(Theme.accentText)
            }
    }

    /// Zet de app bij terugkomst weer klaar op het opnamescherm, als hij lang
    /// genoeg weg is geweest.
    ///
    /// Waarom dit bestaat (17 augustus 2026): Niels verandert iets in
    /// Instellingen, veegt de app weg, en wil een uur later even snel iets
    /// inspreken. Hij kwam dan terug in Instellingen ▸ Algemeen en moest eerst
    /// terugklikken, op Gereed drukken, naar Opnemen en pas dán op de
    /// opnameknop. Dicteren is juist het snelle pad van deze app.
    ///
    /// Bewust `.background` en niet `.inactive`: dat laatste vuurt ook bij een
    /// binnenkomend belletje, het bedieningspaneel of de app-kiezer, en dan zou
    /// hij zijn scherm kwijtraken terwijl hij nergens heen is geweest.
    private func handle(_ phase: ScenePhase) {
        switch phase {
        case .background:
            backgroundedAt = Date()
        case .active:
            defer { backgroundedAt = nil }
            let drempel = app.returnToRecordAfter
            guard drempel > 0, let weg = backgroundedAt else { return }
            guard Date().timeIntervalSince(weg) >= drempel else { return }
            // Eerst het instellingenvenster dicht, dan de tab. Andersom zie je
            // het opnamescherm even achter een venster dat nog dichtklapt.
            showSettings = false
            selectedTab = Self.recordTab
        default:
            break
        }
    }
}

/// The tab shell. Tinted, themed, with the shared error alert.
struct RootView: View {
    @EnvironmentObject private var app: AppModel
    @Binding var selection: Int
    @Binding var showSettings: Bool

    /// De tabbalk tekent de systeemtint met een waas, waardoor het oranje er
    /// lichter uitzag dan op de knoppen (13 aug 2026). Hier pinnen we de
    /// exacte themakleur; RootView wordt bij een merk- of weergavewissel
    /// herbouwd, dus dit loopt vanzelf mee.
    private func applyTabBarColors() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        let item = UITabBarItemAppearance()
        let selected = UIColor(Theme.accentText)
        item.selected.iconColor = selected
        item.selected.titleTextAttributes = [.foregroundColor: selected]
        appearance.stackedLayoutAppearance = item
        appearance.inlineLayoutAppearance = item
        appearance.compactInlineLayoutAppearance = item
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        TabView(selection: $selection) {
            RecordView()
                .tabItem { Label("Opnemen", systemImage: "mic.fill") }
                .tag(0)

            NavigationStack {
                MeetingSetupView()
            }
            .tabItem { Label("Notulist", systemImage: "person.2.wave.2.fill") }
            .tag(1)

            NotesListiOSView()
                .tabItem { Label("Notities", systemImage: "note.text") }
                .tag(2)

            HistoryListiOSView()
                .tabItem { Label("Geschiedenis", systemImage: "clock.fill") }
                .tag(3)
        }
        .onAppear(perform: applyTabBarColors)
        .overlay(alignment: .topTrailing) {
            // Settings gear floats over de tab-content (elke tab is z'n eigen
            // NavigationStack, dus een gedeelde toolbar-knop zou dupliceren).
            // Bewust op ÉLKE pagina zichtbaar — ook in gepushte detailweergaven.
            // Die detailschermen zetten hun eigen knoppen daarom links (topBarLeading),
            // zodat niets rechtsboven met dit tandwiel botst.
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Theme.accentText)
                    .padding(10)
            }
            .padding(.trailing, 8)
            .padding(.top, 4)
        }
        .alert(
            "Er ging iets mis",
            isPresented: Binding(
                get: { app.errorMessage != nil },
                set: { if !$0 { app.errorMessage = nil } }
            ),
            actions: { Button("OK", role: .cancel) { app.errorMessage = nil } },
            message: { Text(app.errorMessage ?? "") }
        )
        .alert(
            "Opname hersteld",
            isPresented: Binding(
                get: { app.noticeMessage != nil },
                set: { if !$0 { app.noticeMessage = nil } }
            ),
            actions: { Button("OK", role: .cancel) { app.noticeMessage = nil } },
            message: { Text(app.noticeMessage ?? "") }
        )
    }
}
