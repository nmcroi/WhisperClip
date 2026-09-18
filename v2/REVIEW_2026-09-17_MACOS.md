# WhisperClip macOS — gerichte review en reparaties

17 september 2026. Native SwiftUI/AppKit-app voor dicteren via sneltoets, lokale transcriptie, bestandsimport, ondertitels, notities en optionele iCloud/AI-verwerking. De onderzochte logica en opslag slagen in de tests. De Mac-geschiedenis, veilige audiopaden en testisolatie zijn gericht gerepareerd. De bijgewerkte lokale app is na backup geïnstalleerd en gestart. Live microfoon, sneltoetsinvoeging en iCloud-uitwisseling zijn niet praktisch doorgetest; er blijven expliciete open bevindingen.

## Werkbasis en scope

- Repository: `/Users/nielscroiset/Werkmappen/Development/WhisperClip/v2`; branch `werk/augustus-2026`; basiscommit `8f99db0479f0718adb3327e4ada55e34b0daffc2`.
- Er waren al veel lokale wijzigingen, inclusief audio/herstel/sync en de iPhone-reparaties. Deze zijn behouden. De werkboom is beoordeeld, niet uitsluitend de basiscommit.
- macOS 26.0+, Swift 6, SwiftUI plus AppKit-panelen/menu's. Project `WhisperClipboard.xcodeproj`, scheme `WhisperClipboard`, configuratiebron `project.yml` en bestaande lokale xcconfig voor signing.
- Gedeeld: Core en WhisperShared, GRDB 7.11.1/SQLite/FTS5, FluidAudio 0.15.4/Parakeet. Mac-specifiek: Apple SpeechAnalyzer, KeyboardShortcuts 2.4.0, Sparkle 2.9.4, Accessibility-invoeging en systeem-audiocapture.
- Entrypoint `WhisperClipboardApp` → `AppDelegate`/`AppEnvironment`. Home/History/Notes/Settings, aparte HUD en MeetingSheet. Opnamecoördinatie via DictationController/MeetingController en gedeelde opnamejournal/opslag. Geen webapp of eigen backend in de onderzochte route.
- Gegevens: lokale SQLite-transcripties/notities, JSON-voorkeuren, lokaal bewaarde audio, Keychain-sleutels. CloudKit-private database voor optionele sync; optionele BYOK-providerverwerking en PLAUD-import. De productieapp is bewust niet gesandboxed; dat is geen bevinding op zichzelf.
- Vastgelegde eisen: rustige vormgeving/HUD behouden, audio bewaren optioneel, instellingen live toepassen, gegevens behouden, geen publicatie. De review is een gerichte code- en testcontrole van de kernroutes, geen volledige beveiligings- of visuele audit.

## Bevindingen op prioriteit

### MAC-01 — Unit-tests konden de echte API-sleutel overschrijven — P1, testveiligheid, gerepareerd

**Bevestigd codepad; niet met een echte sleutel uitgevoerd.** De oude `KeychainStoreTests` schreef een probe en testsleutel via de statische productie-account en verwijderde deze daarna. Alleen de suite draaien kon daarmee een bestaande Anthropic-sleutel vervangen/verwijderen. Daarnaast startte de testhost via `AppDelegate` de gewone `AppEnvironment`, inclusief persoonlijke services.

Kleinste oplossing: unieke testaccounts gebruiken en opruimen; de PLAUD-onafhankelijkheidstest gebruikt nu eveneens een tweede fictief account in plaats van de echte sleutel te lezen. AppEnvironment is lazy en tijdens hosted unit-tests worden de gewone schermen, appbootstrap en launch-health-mutaties overgeslagen. Productiestart blijft ongewijzigd in functie; Release schakelt de testdetectie uit.

Actuele locaties: `WhisperClipboardTests/KeychainStoreTests.swift:10`, `WhisperClipboardTests/PlaudKeychainTests.swift` bij `testApiKeyAndPlaudItemsAreIndependent`; `WhisperClipboard/App/AppDelegate.swift:12`, `:69`, `:539`; `WhisperClipboard/App/WhisperClipboardApp.swift:9`, `:23`.

Verificatie: de Mac-suite slaagt inclusief Keychain-roundtrips en `testHostedTestsDoNotBootstrapUserServices`. Geen echte sleutel gelezen, afgedrukt of gewijzigd door de aangepaste tests. Er is niet beweerd dat eerdere testruns daadwerkelijk een gebruikerssleutel hadden gewist.

### IP-03 — Gedeelde sync-wachtrij is niet atomair met SQLite — P1, betrouwbaarheid, open

Dit is **dezelfde finding** uit `REVIEW_2026-09-17_IPHONE.md`, geen nieuw probleem met een tweede ID. Beide apps gebruiken de betreffende code.

`Packages/Shared/Sources/WhisperShared/HistoryStore.swift:202–214` commit een wijziging vóór het sync-event. `HistorySyncEngine.swift:383–390` schrijft daarna een apart journal. Bij een schrijffout of crash tussen deze stappen is een wijziging niet duurzaam klaargezet. Vooral een verwijdering is na herstart niet uit de resterende rijen te reconstrueren. `HistoryChange.swift:152–154` behandelt een onleesbaar journal bovendien als leeg.

Bewijs: statisch gevolgde commit/emit/append-route. Geen fout op echte gebruikersgegevens opgewekt. Passende oplossing: outbox/tombstones in dezelfde SQLite-transactie, nieuwe migratie en overname van bestaande journals. Nodig: foutinjectie, herstart, herlevering en een live tweetoesteltest. De groene mapping- en journaltests bewijzen deze crashgrens niet veilig.

### MAC-02 — Geschiedenis beperkte resultaten en blokkeerde bij verversen — P2, correctheid/performance, gerepareerd

**Bevestigd codepad.** De Mac haalde maximaal 500 rijen op; daarna pas volgden enkele lokale filters. Oudere opnames konden daardoor buiten de lijst en buiten die filters vallen. Iedere echte vernieuwing deed bovendien een synchrone lezing en herhaalde datumparsing in de sorteercomparator op de hoofdthread. Anders dan de oude iPhone-route gebeurde dit op Mac niet bij elke render, maar bij verschijnen, zoek/filterwijzigingen en store-revisies.

Oplossing: de gedeelde async snapshot accepteert nu ook het bronfilter; de Mac leest/decodeert op GRDB's queue zonder verborgen limiet. Nieuwste/oudste gebruiken de databasevolgorde. Sprekers worden alleen geteld bij een actief sprekersfilter. Nieuwe verzoeken annuleren verouderde resultaten. Bij leesfouten blijft de vorige lijst staan en wordt de fout gemeld. Selectie na geslaagde verwijdering wacht op de vernieuwde lijst; een mislukte transactie behoudt de selectie.

Locaties: `WhisperClipboard/UI/History/HistoryListView.swift:592–620`, `:308–319`; `Packages/Shared/Sources/WhisperShared/HistoryStore.swift:876`. Geen ontwerpwijziging aan HUD, sidebar of geschiedenisopmaak.

Verificatie: builds en tests slagen. De gedeelde tests gebruiken 5.001 fictieve records en controleren tijdzones, bronfilter, zoekfunctie, uitsluiting van notitieopnames en wijziging na verwijderen. Geen actuele fysieke HUD-latentie of frame-rate gemeten. Lokale niet-datumfilters en titel-sortering doen nog verwerking op de hoofdthread; grote archieven kunnen aanvullende profiling vereisen.

### MAC-03 — Audiopad vertrouwde het transcript-ID — P2, bestandsveiligheid, gerepareerd

**Bevestigd met synthetische bestanden.** De oude `TranscriptAudioStore.audioURL` bouwde rechtstreeks `<id>.<ext>` onder de opnamemap. Een ID zoals `../outside` kon een bestaand audiobestand buiten die map selecteren. IDs zijn ook persistente/importeerbare/synchroniseerbare gegevens en horen geen bestandspad te bepalen. Dit is geen aangetoonde publieke of ongeauthenticeerde aanval; het vereist een afwijkend record en een bereikbaar bestand.

Oplossing: gebruik dezelfde gevalideerde lookup als `RecordingRepository`, die padscheiding en ongeldige IDs weigert. De bewaarroute en de Mac-audiozoekroute spreken daarmee dezelfde regels af.

Locatie: `WhisperClipboard/Files/TranscriptAudioStore.swift:28–32`. Regressietest: `WhisperClipboardTests/TranscriptAudioStoreTests.swift:28`; maakt in een tijdelijke map een bestand binnen en buiten de opnamemap, controleert dat het normale bestand wordt gevonden en `../outside` niet. Geslaagd; beide synthetische bestanden blijven behouden.

### MAC-04 — Automatische export en mapscan kunnen de UI blokkeren — P2, performance-risico, open

**Blokkerende code op MainActor bevestigd; merkbare vertraging onder een trage opslaglocatie niet gemeten.** `AutoExportService` is MainActor-geïsoleerd; `exportIfEnabled` doet synchroon padcontroles en export (`WhisperClipboard/Automation/AutoExportService.swift:42–58`). De `Task` in `AppEnvironment.swift:516` verplaatst dit naar een volgende beurt, maar niet naar een achtergrondthread. `WatchedFolderService.swift:94–120` scant eveneens synchroon voordat de busy-check volgt. Bij een trage/netwerklocatie kan dit de opnamebediening vertragen, ook tijdens ander werk.

Passende oplossing: bestandswerk met een onveranderlijke opdracht op een eigen queue/actor uitvoeren; alleen status en configuratie op MainActor, en mapscans niet overlappen. Bookmarks/toegangsduur en exportvolgorde moeten behouden blijven. Er is geen algemene herbouw nodig. Verificatie: bestaande functionele auto-export- en scanlogica-tests slagen, maar geen trage-netwerkschijfproef uitgevoerd. Dit is niet bewezen als oorzaak van Niels' iPhone-bubbelhapering.

### MAC-05 — Audio bijsnijden kan een mislukte bronopruiming verbergen — P2, foutafhandeling, open

**Bevestigde foutafhandelingsroute, niet met gebruikersaudio opgewekt.** `WhisperClipboard/Files/TranscriptAudioStore.swift:121–133` plaatst eerst de nieuwe M4A en verwijdert daarna de oorspronkelijke WAV/CAF met `try?`. Als dat laatste mislukt blijft het onverkorte origineel staan zonder foutmelding. Een volgende lookup kan het origineel weer kiezen. Ook wordt bij de export alleen `.failed` expliciet afgewezen, niet iedere niet-voltooide status.

Passende oplossing: moderne throwing export met gegarandeerde tijdelijke-opruiming en expliciete melding bij mislukte bronverwijdering. De oorspronkelijke audio moet bij een conversiefout behouden blijven. Test de echte conversie en injecteer afzonderlijk een verwijderfout; de bestaande tests op atomaire bestandsvervanging bewijzen dat laatste niet. De review heeft de gevalideerde lookup gerepareerd, niet de volledige trim-transactie.

## Hypotheses en optionele verbeteringen

- Hapering van de HUD kan ook ontstaan door modelopstart, audiocapture of brede view-updates. Zonder Time Profiler/Hangs-meting tijdens echte dictatie is de verdeling onbekend.
- Notities gebruikt op enkele leesroutes nog `try?` met een lege lijst als fallback (`NotesListView.swift:252`, `:272`). Bij een databasefout ontbreekt daar duidelijke uitleg. Dit is een kleinere vervolgreparatie; geslaagde schrijfacties gebruiken al `DataChange`.
- De mapbewaker markeert items vóór import als verwerkt. Dat voorkomt dubbele enqueues, maar na een crash/mislukte import kan handmatig opnieuw importeren nodig zijn. Dit is een betrouwbaarheidstrade-off uit de huidige implementatie, geen bewijs dat bestanden zijn verdwenen.
- Er zijn bestaande Swift-concurrencywaarschuwingen in tests en verouderde AVFoundation-aanroepen. Ze verdienen onderhoud, maar een waarschuwing alleen bewijst geen gebruikersbug.
- Geen volledige secrets- of actuele dependency-advisoryscan uitgevoerd. Er wordt geen kwetsbaarheidsvrijheid, App Store-goedkeuring of productiegereedheid geclaimd.

## Wat is onderzocht

Statisch gevolgd: sneltoets → DictationController → Parakeet/Apple Speech → afronding/opslag/HUD; audio-keuze en reset; non-activating HUD met bescherming tegen een verouderde hide-animatie; Notulist-opslag en gedeeltelijke audiofouten; history-selectie, bulkverwijderen en samenvoegen; Notities-lees/schrijfroutes; audio lookup/trim; Accessibility-invoegbeleid en behoud van klembordtekst; automatische export en mapbewaking; testfixtures, Keychain-gebruik, entitlements en updatefeedconfiguratie.

Bestaande guards voor invoegen controleren onder meer toestemming, vastgelegd doel, huidige voorgrondapp en de denylist. De kernregels zijn getest met geïnjecteerde componenten; er is niet in een echte andere app geplakt. Sparkle's feed staat niet als actieve productie-updatefeed geconfigureerd. Gewone Release- en lokale Development-iCloud-builds hebben verschillende distributiedoelen; de bestaande lokale signingconfiguratie is behouden. De geraadpleegde entitlements zijn configuratiebewijs, geen onafhankelijke privacycertificering.

De nieuwe code verandert geen schema/migratie, dependencies, opgeslagen voorkeuren of UI-vormgeving. Bestaande transactionele delete/merge en opnameherstel zijn met tijdelijke testgegevens getest. Tests voor CloudKit mappen lokale CKRecords en journals; zij communiceren niet met echte CloudKit-accounts.

## Uitgevoerde controles

Omgeving: MacBook Pro arm64, macOS 26.5.1, Xcode 26.6 (17F113). Bestaande lokale signingconfiguratie, geen instellingen gewijzigd om builds te laten slagen.

| Controle | Status | Resultaat / beperking |
|---|---|---|
| Mac Debug-build | Geslaagd | Inclusief een gewone build ná XCTest, zodat de te installeren app geen extra testhost-entitlements draagt. |
| Mac Release-build | Geslaagd | Compile/buildcontrole, geen distributie/notarisatie of Release-installatie. |
| Mac-unit/integratiesuite | Geslaagd | 332 tests, 0 fouten, 0 runtime-skips in de geselecteerde suite. Drie E2E-klassen expliciet uitgesloten. |
| Eerste Mac-testrun | Mislukt, opgelost | 330 geslaagd, één test gebruikte nog de oude tijdelijke-bestandsroute. Test is aangepast aan de echte nieuwe sessie-eigendom en een geïsoleerde repository; de productiecode is niet teruggedraaid naar onveilige bestandsverwijdering. |
| WhisperShared-tests | Geslaagd | 81 tests; inclusief source-filter en grote async snapshot, opslagfouten, herstel, migratie, verwijdering en export. |
| Core-tests | Geslaagd | 199 tests in 17 suites. |
| Nieuwe testveiligheid/audio-ID-controles | Geslaagd | Binnen bovenstaande 332; unieke Keychain-testaccounts, host-bootstrapdetectie en path-traversalcontrole. |
| `git diff --check` | Geslaagd | Bestaande lokale wijzigingen behouden. |
| Gewone lokale appstart | Geslaagd | Na backup geïnstalleerd, proces blijft draaien; dit is geen complete UI-test. |
| Gegevens na installatie | Geslaagd | Integriteitscontrole en volledige rijvergelijking van transcripties/notities; instellingenbestand gelijk. |
| Live microfoon, sneltoets, plakken, systeem-audio, pauze/onderbreking, lange opname | Niet uitgevoerd | Vereist praktische hardwarecontrole, geen opname gemaakt tijdens deze review. |
| Live iCloud-uitwisseling, netwerkuitval en AI-verzoeken | Niet uitgevoerd als test | Geen accounts gemuteerd door tests of betaalde verzoeken gestart. De gewone geïnstalleerde app gebruikt na start de bestaande gebruikersinstellingen. |
| Visuele matrix, VoiceOver, Intel-runtime | Niet uitgevoerd | Geen volledige visuele/toegankelijkheidsclaim. |

Commando's vanuit `v2`:

```sh
xcodebuild -quiet -project WhisperClipboard.xcodeproj -scheme WhisperClipboard -configuration Debug -destination 'platform=macOS,arch=arm64' build
xcodebuild -quiet -project WhisperClipboard.xcodeproj -scheme WhisperClipboard -configuration Release -destination 'platform=macOS,arch=arm64' build
xcodebuild -quiet -project WhisperClipboard.xcodeproj -scheme WhisperClipboard -destination 'platform=macOS,arch=arm64' -skip-testing:WhisperClipboardTests/E2EImportSmokeTests -skip-testing:WhisperClipboardTests/E2EDiarizationSmokeTests -skip-testing:WhisperClipboardTests/E2ECaptionsSmokeTests -resultBundlePath /tmp/WhisperClipMacReviewFinal20260917.xcresult test
swift test --package-path Packages/Shared
swift test --package-path Packages/Core --scratch-path /tmp/WhisperClipCoreReview20260917
```

De E2E-klassen kunnen bestaande `/tmp`-opt-inbestanden gebruiken om echte model/audio-runs te starten. Ze zijn bewust uitgesloten; die uitsluiting staat niet als runtime-skip in het getal 332. Gebruik een nieuw resultBundlePath bij herhaling. Samenvatting: `ReviewScreenshots/2026-09-17-macos/test-results.json`. Volledige logs: `/tmp/whisper-mac-*.log`, xcresult hierboven.

## Installatie en gegevensbehoud

Geïnstalleerd: `/Users/nielscroiset/Applications/WhisperClip.app`, dezelfde Debug-databasevariant en exact dezelfde ondertekende rechten als de bestaande app, inclusief Development CloudKit. Geen App Store-upload/publicatie. Geen iPhone-update in deze ronde.

Backup: `/Users/nielscroiset/Werkmappen/Development/WhisperClip/device-backups/Niels-Mac/2026-09-17-150858-review/`. Bevat Application Support, voorkeuren en de oude app. Voor afsluiten waren er geen actieve hersteljournal-sessies. De oude app is normaal afgesloten; pas na geslaagde backup, database-integriteit en codehandtekeningcontrole is het appbundle vervangen.

Na start: `history-dev.db` bevat onveranderd 1.420 transcripties en 7 notities; alle betreffende rijen zijn identiek aan de backup. De andere database bevat nog dezelfde 3 transcripties. Het instellingenbestand is byte-voor-byte gelijk. Bewijs staat in `manifest.json` en `verification.json` in de backupmap. De sleutelhanger is niet gemigreerd of opgeschoond.

## Maximaal vijf vervolgstappen

1. De gedeelde transactionele sync-wachtrij (IP-03) repareren met crash-/schrijffouttests.
2. Echte Mac-dictatie en HUD profileren; indien nodig export/mapscans van MainActor halen.
3. De audio-trimroute en bijbehorende foutinjectie afmaken.
4. Praktisch testen: sneltoets, verkeerde voorgrondapp, microfoonpermissie, onderbreking, lange opname en live iCloud tussen apparaten.
5. Leesfouten in Notities en de bestaande concurrency/deprecation-waarschuwingen gericht opruimen.

De onderzochte logica slaagt in de genoemde testomgeving en de lokale app start met behouden gegevens. Hardwaregedrag, visuele regressies en live synchronisatie zijn daarmee nog niet volledig bewezen.
