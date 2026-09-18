import Combine
import Core
import Foundation
import SwiftUI
import UIKit
import WhisperShared

/// The app-wide environment for the iOS companion: the shared Parakeet engine,
/// the GRDB history store (in this app's own sandboxed Application Support), the
/// current appearance, and the model-download state machine.
///
/// Kept deliberately small: this is the i0+i1 scaffold. Settings beyond the
/// theme (replacements, retention, filler removal) and iCloud sync come in later
/// rounds; the data layer is already sync-compatible with the Mac (identical
/// `TranscriptEntry` schema via `WhisperShared`).
@MainActor
final class AppModel: ObservableObject {

    /// The one shared transcription engine (pre-warmed, kept alive across records).
    let engine = ParakeetEngine()
    @Published var showAudioRetentionOption = UserDefaults.standard.bool(forKey: "ios.showAudioRetentionOption") {
        didSet { UserDefaults.standard.set(showAudioRetentionOption, forKey: "ios.showAudioRetentionOption") }
    }

    /// The history store, or `nil` if the DB couldn't be opened (rare, surfaced
    /// as an error banner rather than crashing).
    let history: HistoryStore?

    /// Stuurt wijzigingen in de HistoryStore (revision-bump bij hernoemen,
    /// verplaatsen, opslaan, …) door naar de views. Die observeren alleen
    /// AppModel; zonder deze doorgifte bleef bv. een hernoemde notitie zijn oude
    /// titel tonen tot een toevallige andere her-render (bug 2026-07-05).
    private var historyObservation: AnyCancellable?

    /// iCloud history sync (i2). `nil` when the DB couldn't be opened (no store to
    /// sync). Dormant until the toggle is on AND an iCloud account is available.
    let historySync: HistorySyncEngine?

    /// AI post-processing (Claude) service, shared by History- en Note-detail.
    /// `nil` wanneer de DB niet geopend kon worden (geen store om resultaten in
    /// te bewaren). Leest de API-key uit de Keychain van dit toestel.
    let modes: ModesService?

    #if WHISPERCLIP_PERSONAL || !WHISPERCLIP_PUBLIC
    /// PLAUD-cloudsync bestaat uitsluitend in de Personal-compilatie.
    lazy var plaudSync = PlaudSynciOSService(app: self)
    #endif

    /// Whether iCloud sync is enabled. Persisted in `UserDefaults` under
    /// `ios.icloudSyncEnabled`; available in Debug and in the explicitly signed
    /// Personal Development-CloudKit build. Ordinary Release builds stay off
    /// while the Production schema is not live.
    @Published var icloudSyncEnabled: Bool {
        didSet {
            guard icloudSyncEnabled != oldValue else { return }
            UserDefaults.standard.set(icloudSyncEnabled, forKey: Self.icloudSyncKey)
            Task { await historySync?.settingChanged() }
        }
    }

    /// Chosen appearance. Persisted in `UserDefaults` under `ios.appearance`.
    @Published var appearance: AppSettings.AppearanceMode {
        didSet { Self.persistAppearance(appearance) }
    }

    /// Het merkthema (WhisperClip of GHX). Persisted onder `app.brand`.
    /// `Theme.brand` wordt meegezet; de `@Published`-wijziging tekent alle
    /// schermen opnieuw, dus de kleuren wisselen direct.
    @Published var brand: AppBrand {
        didSet {
            Theme.brand = brand
            UserDefaults.standard.set(brand.rawValue, forKey: Self.brandKey)
        }
    }

    /// Interface language. System follows the current supported system locale;
    /// the explicit alternatives override it app-wide without changing iOS.
    @Published var interfaceLanguage: AppLanguage {
        didSet { UserDefaults.standard.set(interfaceLanguage.rawValue, forKey: Self.interfaceLanguageKey) }
    }

    /// Toont korte, niet-essentiële aanwijzingen in de hoofdschermen, zoals
    /// “Tik om op te nemen”. Statussen, voortgang en fouten blijven altijd staan.
    @Published var showHelpTips: Bool {
        didSet { UserDefaults.standard.set(showHelpTips, forKey: Self.showHelpTipsKey) }
    }

    /// Na hoeveel seconden in de achtergrond de app bij terugkomst weer op het
    /// opnamescherm klaarstaat. 0 betekent uit: hij blijft dan staan waar je hem
    /// achterliet.
    ///
    /// Wens van Niels op 17 augustus 2026: hij verandert iets in Instellingen,
    /// veegt de app weg, wil daarna dicteren en moet dan eerst terugklikken,
    /// op Gereed drukken, naar Opnemen en pas dan opnemen. Vier handelingen
    /// voordat hij kan praten, terwijl dicteren juist het snelle pad hoort te
    /// zijn.
    @Published var returnToRecordAfter: TimeInterval {
        didSet { UserDefaults.standard.set(returnToRecordAfter, forKey: Self.returnToRecordAfterKey) }
    }

    /// Algemene hoofdschakelaar voor externe AI in de Notulist. Standaard uit;
    /// per vergadering is daarna nog een tweede expliciete keuze vereist.
    @Published var allowMeetingAI: Bool {
        didSet { UserDefaults.standard.set(allowMeetingAI, forKey: Self.allowMeetingAIKey) }
    }

    /// Laatst gekozen taal is de standaard voor de volgende opname. De keuze
    /// wordt ook afzonderlijk in ieder transcript opgeslagen.
    @Published var transcriptionLanguage: TranscriptionLanguage {
        didSet {
            UserDefaults.standard.set(transcriptionLanguage.rawValue, forKey: Self.transcriptionLanguageKey)
        }
    }

    /// Globale standaard-AI-aanbieder. Modellen blijven per aanbieder onthouden.
    @Published var aiProvider: AIProvider {
        didSet {
            UserDefaults.standard.set(aiProvider.rawValue, forKey: Self.aiProviderKey)
            // Notulist-AI heeft twee toestemmingen nodig. Een overstap naar een
            // aanbieder zonder sleutel trekt de algemene toestemming daarom in.
            if !hasAPIKey(for: aiProvider) { allowMeetingAI = false }
        }
    }

    @Published var aiModels: [AIProvider: String] {
        didSet {
            for provider in AIProvider.allCases {
                let model = aiModels[provider] ?? provider.defaultModel
                UserDefaults.standard.set(model, forKey: Self.aiModelKey(provider))
            }
        }
    }

    /// De woordenlijst (find → replace-regels), toegepast op elke transcriptie,
    /// zelfde regels als op de Mac. Lokaal bewaard als JSON in `UserDefaults`
    /// (`ios.replacements`) en gesynct met de Mac via ``ReplacementsCloudSync``
    /// (iCloud key-value store, last-writer-wins).
    @Published var replacements: [Replacement] {
        didSet {
            guard replacements != oldValue else { return }
            Self.persistReplacements(replacements)
            // Publiceer alleen eigen bewerkingen; een binnengekomen remote lijst
            // (applyingRemoteReplacements) mag niet terug de cloud in echoën.
            // publish() is gedebounced: tikken in de editor spamt de store niet.
            guard !applyingRemoteReplacements else { return }
            replacementsSync.publish(replacements)
        }
    }

    /// Herbruikbare deelnemers voor de Notulist, lokaal bewaard en via iCloud met
    /// de Mac gedeeld. Maximaal één contact is gemarkeerd als 'ik'.
    @Published var meetingContacts: [SavedMeetingContact] {
        didSet {
            guard meetingContacts != oldValue else { return }
            Self.persistMeetingContacts(meetingContacts)
            guard !applyingRemoteMeetingContacts else { return }
            meetingContactsSync.publish(meetingContacts)
        }
    }

    /// iCloud KV-sync voor de woordenlijst. Los van `historySync` (CKSyncEngine):
    /// werkt ook nu die nog uit staat, en degradeert stil zonder entitlement.
    private let replacementsSync = ReplacementsCloudSync(updatedAtKey: "ios.replacementsUpdatedAt")
    /// Vlag rond het toepassen van een remote lijst, zodat de didSet hierboven
    /// niet opnieuw publiceert (sync-lus-preventie, laag 2).
    private var applyingRemoteReplacements = false
    private let meetingContactsSync = MeetingContactsCloudSync(updatedAtKey: "ios.meetingContactsUpdatedAt")
    private var applyingRemoteMeetingContacts = false

    /// Current model-download / readiness state, driving the onboarding card.
    @Published var modelStatus: ModelAssetStatus = .unknown

    /// Aan tijdens het kopiëren van een handmatig geïmporteerde modelmap naar de
    /// FluidAudio-cache. Los van `modelStatus`, want dat blijft `.needsDownload`
    /// terwijl het kopiëren op de achtergrond loopt.
    @Published var isImportingModel = false

    /// Byte-level download progress ("X van Y MB"), nil when not downloading.
    /// Kept separate from `modelStatus` so the fraction and the byte text update
    /// together without widening the shared `ModelAssetStatus` enum.
    @Published var downloadBytes: ModelDownloadByteProgress?

    /// The last user-facing error message (nil = none).
    @Published var errorMessage: String?
    /// Niet-foutieve, eenmalige melding, bijvoorbeeld na geslaagd crashherstel.
    @Published var noticeMessage: String?

    private var didAttemptRecordingRecovery = false

    /// True zolang er ergens in de app een opname loopt. Gezet door
    /// ``RecordController``; gebruikt om de herbouw van de schermboom bij een
    /// merk- of weergavewissel uit te stellen tot na de opname.
    @Published private(set) var isRecordingActive = false
    /// Er kan meer dan één opnamescherm bestaan (Opnemen en Notulist), dus tellen
    /// in plaats van een enkele vlag.
    private var activeRecordings = 0

    func recordingBegan() {
        activeRecordings += 1
        isRecordingActive = true
    }

    func recordingEnded() {
        activeRecordings = max(0, activeRecordings - 1)
        isRecordingActive = activeRecordings > 0
    }

    private static let appearanceKey = "ios.appearance"
    private static let interfaceLanguageKey = "ios.interfaceLanguage"
    private static let showHelpTipsKey = "ios.showHelpTips"
    private static let allowMeetingAIKey = "ios.allowMeetingAI"
    private static let returnToRecordAfterKey = "ios.returnToRecordAfter"
    private static let icloudSyncKey = "ios.icloudSyncEnabled"
    private static let replacementsKey = "ios.replacements"
    private static let meetingContactsKey = "ios.meetingContacts"
    private static let transcriptionLanguageKey = "ios.transcriptionLanguage"
    private static let aiProviderKey = "ai.defaultProvider"
    private static let brandKey = "app.brand"

    init() {
        self.appearance = Self.loadAppearance()
        let storedBrand = AppBrand(
            rawValue: UserDefaults.standard.string(forKey: Self.brandKey) ?? ""
        ) ?? .whisperClip
        self.brand = storedBrand
        Theme.brand = storedBrand
        self.interfaceLanguage = AppLanguage(
            rawValue: UserDefaults.standard.string(forKey: Self.interfaceLanguageKey) ?? ""
        ) ?? .system
        self.showHelpTips = UserDefaults.standard.object(forKey: Self.showHelpTipsKey) as? Bool ?? true
        self.allowMeetingAI = UserDefaults.standard.bool(forKey: Self.allowMeetingAIKey)
        // Standaard één minuut. `object(forKey:)` en niet `double(forKey:)`,
        // want die laatste geeft 0 terug als er nog niets is opgeslagen en dat
        // is hier juist de stand "uit".
        self.returnToRecordAfter =
            UserDefaults.standard.object(forKey: Self.returnToRecordAfterKey) as? TimeInterval ?? 60
        self.transcriptionLanguage = TranscriptionLanguage(
            rawValue: UserDefaults.standard.string(forKey: Self.transcriptionLanguageKey) ?? ""
        ) ?? AppFeatureConfiguration.defaultTranscriptionLanguage
        self.aiProvider = AIProvider(
            rawValue: UserDefaults.standard.string(forKey: Self.aiProviderKey) ?? ""
        ) ?? .anthropic
        self.aiModels = Dictionary(uniqueKeysWithValues: AIProvider.allCases.map { provider in
            let saved = UserDefaults.standard.string(forKey: Self.aiModelKey(provider))
            return (provider, saved?.isEmpty == false ? saved! : provider.defaultModel)
        })
        self.replacements = Self.loadReplacements()
        self.meetingContacts = Self.loadMeetingContacts()
        // De entitlement-check in `HistorySyncEngine.hasCloudKitEntitlement` is
        // gerepareerd (leest niet meer het provisioning-profiel maar de echte,
        // ondertekende grant), dus aanzetten laat de app niet meer crashen.
        // Debug mag expliciet tegen het Development-schema testen, maar begint
        // altijd met de eerder gekozen (standaard uitgeschakelde) stand. Release
        // blijft hard uit totdat het schema bewust naar Production is uitgerold.
        #if DEBUG || WHISPERCLIP_ICLOUD_DEVELOPMENT
        UserDefaults.standard.register(defaults: [Self.icloudSyncKey: false])
        // A Development build must also respect an explicit opt-out after restart.
        let initialSyncEnabled = UserDefaults.standard.bool(forKey: Self.icloudSyncKey)
        #else
        UserDefaults.standard.set(false, forKey: Self.icloudSyncKey)
        let initialSyncEnabled = false
        #endif
        self.icloudSyncEnabled = initialSyncEnabled
        // Retention is unlimited for now (settings round adds a control). The DB
        // lives in this app's own sandbox, isolated from the Mac's copy.
        let store: HistoryStore?
        var storeFailure: String?
        do {
            store = try HistoryStore(retentionProvider: { nil })
        } catch {
            // Zonder dit verdween de enige aanwijzing waaróm de database niet
            // openging, en zat de gebruiker met een app zonder geschiedenis en
            // een melding waar niemand iets mee kan.
            NSLog("WhisperClip: HistoryStore kon niet worden geopend: %@", error.localizedDescription)
            storeFailure = error.localizedDescription
            store = nil
        }
        self.history = store
        self.modes = store.map { ModesService(history: $0) }
        if let store {
            let engine = HistorySyncEngine(
                store: store,
                isEnabled: { UserDefaults.standard.bool(forKey: Self.icloudSyncKey) }
            )
            self.historySync = engine
            // Bring sync up if enabled + an iCloud account is available; dormant
            // otherwise (e.g. an unsigned simulator build with no CloudKit).
            Task {
                await engine.start()
                #if WHISPERCLIP_ICLOUD_DEVELOPMENT
                // The installation request is the merge authorization. Bind a
                // previously unbound database, but never auto-approve an actual
                // Apple-account change.
                if case .requiresApproval(_, accountChanged: false) = engine.status {
                    await engine.approveCurrentAccountMerge()
                }
                await engine.syncNow()
                #endif
            }
        } else {
            self.historySync = nil
        }

        // Zombie-sweep bij app-start: een opname sterft mét het proces, dus bij
        // launch loopt er nooit een legitieme opname. Alles wat nog als Live
        // Activity op het lock-screen hangt, is achtergebleven door een gekild
        // proces, ruim het onmiddellijk op. Draait ook als de gebruiker nooit een
        // nieuwe opname start (RecordingLiveActivityController.start() zou anders
        // pas bij de volgende opname opruimen).
        Task { await RecordingStopBus.endAllActivities() }
        Task { _ = await runRecordingRecovery(announcing: true, includeUntranscribed: false) }

        // Geef store-wijzigingen door aan de views (zie historyObservation-doc).
        // Bewust als LAATSTE in init: de closure vangt `self` en dat mag pas
        // wanneer alle stored properties geïnitialiseerd zijn.
        self.historyObservation = store?.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        if store == nil {
            let base = L10n.string(
                "De geschiedenis kon niet worden geopend.",
                locale: interfaceLanguage.locale
            )
            self.errorMessage = storeFailure.map { "\(base) (\($0))" } ?? base
        }

        // Woordenlijst-sync: pas een remote lijst toe onder de vlag (didSet
        // publiceert dan niet terug). De timestamp-administratie doet het
        // sync-component zelf.
        replacementsSync.onRemoteChange = { [weak self] list in
            guard let self, self.replacements != list else { return }
            self.applyingRemoteReplacements = true
            self.replacements = list
            self.applyingRemoteReplacements = false
        }
        replacementsSync.start()
        meetingContactsSync.onRemoteChange = { [weak self] contacts in
            guard let self, self.meetingContacts != contacts else { return }
            self.applyingRemoteMeetingContacts = true
            self.meetingContacts = contacts
            self.applyingRemoteMeetingContacts = false
        }
        meetingContactsSync.start()
    }

    // MARK: - Model lifecycle

    /// Refreshes `modelStatus` from the engine (called on appear).
    func refreshModelStatus() async {
        let status = await engine.assetStatus(for: transcriptionLanguage.locale)
        modelStatus = status
        // If already installed, pre-warm so the first record is instant.
        if status.isReady {
            do {
                try await engine.prepare()
                // Opnieuw afleiden: `prepare()` kan een kapot model hebben gewist,
                // en dan is `.installed` van hierboven niet meer waar.
                modelStatus = await engine.assetStatus(for: transcriptionLanguage.locale)
                await recoverInterruptedRecordingsIfNeeded()
            } catch {
                modelStatus = await engine.assetStatus(for: transcriptionLanguage.locale)
                errorMessage = ErrorLocalization.message(for: error, language: interfaceLanguage)
            }
        }
    }

    /// Kicks off the model download, streaming progress into `modelStatus`.
    func downloadModel() async {
        errorMessage = nil
        modelStatus = .downloading(progress: 0)
        // Keep the screen awake for the duration: a multi-minute download over
        // a locked/dimmed screen is where interrupted, half-written models come
        // from (Issue 3). Restored in the defer below.
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = false }
        // En vraag extra achtergrondtijd aan: zonder dit wordt de app opgeschort
        // zodra Niels tijdens de download even naar een andere app kijkt, en ligt
        // de download stil tot hij terugkomt.
        beginDownloadBackgroundTask()
        defer { endDownloadBackgroundTask() }

        // Poll the engine's fraction *and* byte progress while the download runs
        // so both the bar and the "X van Y MB" text keep moving.
        let pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let status = await self.engine.assetStatus(for: self.transcriptionLanguage.locale)
                let bytes = await self.engine.downloadByteProgress()
                await MainActor.run {
                    if case .downloading = status { self.modelStatus = status }
                    self.downloadBytes = bytes
                }
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
        do {
            try await engine.downloadAssets(for: transcriptionLanguage.locale)
            pollTask.cancel()
            downloadBytes = nil
            modelStatus = .installed
            await recoverInterruptedRecordingsIfNeeded()
        } catch {
            pollTask.cancel()
            downloadBytes = nil
            modelStatus = .needsDownload(progress: 0)
            errorMessage = ErrorLocalization.message(for: error, language: interfaceLanguage)
        }
    }

    /// Loopt tijdens de modeldownload; `.invalid` als er geen aanvraag openstaat.
    private var downloadBackgroundTask: UIBackgroundTaskIdentifier = .invalid

    private func beginDownloadBackgroundTask() {
        endDownloadBackgroundTask()
        downloadBackgroundTask = UIApplication.shared.beginBackgroundTask(
            withName: "Parakeet-modeldownload"
        ) {
            // iOS trekt de extra tijd in. Netjes teruggeven, anders beëindigt het
            // systeem de app hard.
            Task { @MainActor [weak self] in self?.endDownloadBackgroundTask() }
        }
    }

    private func endDownloadBackgroundTask() {
        guard downloadBackgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(downloadBackgroundTask)
        downloadBackgroundTask = .invalid
    }

    /// Alternatieve importroute wanneer de download over het netwerk niet lukt:
    /// Niels airdropt de map `parakeet-tdt-0.6b-v3` (~460 MB) van zijn Mac naar
    /// de iPhone en kiest hem hier via een `fileImporter`. `pickedURL` is een
    /// security-scoped resource (buiten de sandbox van deze app), dus toegang
    /// moet expliciet aan en weer uit.
    func importModel(from pickedURL: URL) async {
        errorMessage = nil
        let didAccess = pickedURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess { pickedURL.stopAccessingSecurityScopedResource() }
        }

        // Niels kiest soms de modelmap zelf, soms de map eromheen (bijv. de
        // hele AirDrop-ontvangstmap); resolve zoekt de juiste in beide gevallen.
        let candidate = ParakeetModelImport.resolveModelDirectory(chosen: pickedURL)

        switch ParakeetModelImport.validate(directory: candidate) {
        case .failure(let validationError):
            errorMessage = validationError.localizedDescriptionNL
        case .success(let validated):
            isImportingModel = true
            defer { isImportingModel = false }
            do {
                // Bestandswerk op de achtergrond: dit kopieert ~460 MB, dat mag
                // de UI niet blokkeren.
                try await Task.detached(priority: .utility) {
                    try ParakeetModelImport.install(from: validated)
                }.value
                await refreshModelStatus()
            } catch {
                errorMessage = ErrorLocalization.message(for: error, language: interfaceLanguage)
                // Ook na een mislukte import de stand opnieuw afleiden: het
                // eerder geïnstalleerde model staat er nog en de kaart moet dat
                // laten zien in plaats van te blijven hangen.
                await refreshModelStatus()
            }
        }
    }

    /// Zet na een crash of geforceerd afsluiten achtergebleven tijdelijke audio
    /// alsnog om in gewone geschiedenis-items. Het audiobestand wordt pas gewist
    /// nadat de database-write is geslaagd.
    private func recoverInterruptedRecordingsIfNeeded() async {
        guard !didAttemptRecordingRecovery else { return }
        didAttemptRecordingRecovery = true
        await runRecordingRecovery(announcing: true)
    }

    /// Directe herstelronde buiten de eenmalige start-sweep om, voor een opname
    /// die net na Stop niet getranscribeerd kon worden. Geeft terug hoeveel
    /// opnamen alsnog in Geschiedenis staan; meldt zelf niets, de aanroeper
    /// bepaalt wat de gebruiker te zien krijgt.
    func recoverPendingRecordingsNow() async -> Int {
        await runRecordingRecovery(announcing: false)
    }

    @discardableResult
    private func runRecordingRecovery(announcing: Bool, includeUntranscribed: Bool = true) async -> Int {
        guard let history else { return 0 }

        do {
            let batch = try await engine.recoverOrphanedRecordings(
                defaultLocale: transcriptionLanguage.locale,
                includeUntranscribed: includeUntranscribed
            )
            var savedCount = 0
            var failedCount = batch.failedCount
            var recoveredIncompleteAudio = false
            history.retryAudioCleanup()
            for recovered in batch.recordings {
                do {
                    guard let session = recovered.result.recording, var entry = session.entry else { continue }
                    if session.warning != nil { recoveredIncompleteAudio = true }
                    if session.resultIsProcessed != true {
                        let cleaned = TextProcessor.process(entry.text, replacements: replacements, clean: true, language: session.language)
                        if !cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { entry.text = cleaned }
                    }
                    if entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !session.keepAudio {
                        try history.discardRecording(session)
                    } else {
                        let detached = try history.commitRecording(session, entry: entry)
                        if detached { noticeMessage = AudioCopy.text(.noteMissing, locale: interfaceLanguage.locale) }
                        savedCount += 1
                    }
                } catch { failedCount += 1 }
            }

            guard announcing else {
                if recoveredIncompleteAudio { errorMessage = AudioCopy.text(.partialAudio, locale: interfaceLanguage.locale) }
                return savedCount
            }

            if failedCount > 0 {
                // RootView toont fout- en succesmeldingen met twee aparte alerts.
                // Bied bij een gemengd resultaat alleen de fout aan, zodat twee
                // gelijktijdige modal alerts elkaar niet kunnen verdringen.
                noticeMessage = nil
                errorMessage = L10n.string(
                    "Een onderbroken opname kon niet automatisch worden hersteld. De tijdelijke audio blijft bewaard voor een volgende poging.",
                    locale: interfaceLanguage.locale
                )
            } else if recoveredIncompleteAudio {
                noticeMessage = nil
                errorMessage = AudioCopy.text(.partialAudio, locale: interfaceLanguage.locale)
            } else if savedCount == 1 {
                noticeMessage = L10n.string(
                    "Een onderbroken opname is hersteld en in Geschiedenis bewaard.",
                    locale: interfaceLanguage.locale
                )
            } else if savedCount > 1 {
                noticeMessage = String(
                    format: L10n.string(
                        "%lld onderbroken opnamen zijn hersteld en in Geschiedenis bewaard.",
                        locale: interfaceLanguage.locale
                    ),
                    locale: interfaceLanguage.locale,
                    savedCount
                )
            }
            return savedCount
        } catch {
            if announcing {
                errorMessage = ErrorLocalization.message(for: error, language: interfaceLanguage)
            }
            return 0
        }
    }

    // MARK: - Appearance persistence

    private static func loadAppearance() -> AppSettings.AppearanceMode {
        let raw = UserDefaults.standard.string(forKey: appearanceKey) ?? ""
        return AppSettings.AppearanceMode(rawValue: raw) ?? .dark
    }

    private static func persistAppearance(_ mode: AppSettings.AppearanceMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: appearanceKey)
    }

    func presentDataChangeError(_ error: Error) {
        errorMessage = String(
            format: L10n.string(
                "De wijziging kon niet worden opgeslagen: %@",
                locale: interfaceLanguage.locale
            ),
            locale: interfaceLanguage.locale,
            error.localizedDescription
        )
    }

    // MARK: - Woordenlijst-persistentie

    private static func loadReplacements() -> [Replacement] {
        guard let data = UserDefaults.standard.data(forKey: replacementsKey) else { return [] }
        return (try? JSONDecoder().decode([Replacement].self, from: data)) ?? []
    }

    private static func persistReplacements(_ replacements: [Replacement]) {
        guard let data = try? JSONEncoder().encode(replacements) else { return }
        UserDefaults.standard.set(data, forKey: replacementsKey)
    }

    private static func loadMeetingContacts() -> [SavedMeetingContact] {
        guard let data = UserDefaults.standard.data(forKey: meetingContactsKey) else { return [] }
        return (try? JSONDecoder().decode([SavedMeetingContact].self, from: data)) ?? []
    }

    private static func persistMeetingContacts(_ contacts: [SavedMeetingContact]) {
        guard let data = try? JSONEncoder().encode(contacts) else { return }
        UserDefaults.standard.set(data, forKey: meetingContactsKey)
    }

    // MARK: - AI-providerinstellingen

    func selectedModel(for provider: AIProvider) -> String {
        aiModels[provider] ?? provider.defaultModel
    }

    func setSelectedModel(_ model: String, for provider: AIProvider) {
        var updated = aiModels
        updated[provider] = model
        aiModels = updated
    }

    func hasAPIKey(for provider: AIProvider) -> Bool {
        KeychainStore.hasKey(for: provider)
    }

    func availableModels(for provider: AIProvider) async throws -> [String] {
        guard let key = try KeychainStore.read(for: provider), !key.isEmpty else {
            throw AIServiceError.missingKey(provider)
        }
        let live = try await AIClientFactory.make(provider: provider, apiKey: key).listModels()
        return live.isEmpty ? provider.fallbackModels : live
    }

    private static func aiModelKey(_ provider: AIProvider) -> String {
        "ai.model.\(provider.rawValue)"
    }
}
