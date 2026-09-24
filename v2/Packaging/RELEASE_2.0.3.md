# WhisperClip macOS 2.0.3 (9) — crashreparatie

Datum: 21 september 2026. Gerichte reparatie; geen volledige nieuwe appreview.

## Bewijs en wijziging

Het ontvangen rapport betreft 2.0.2 (7), ARM64, macOS 27.0 (26A428), na circa 2 uur 13 minuten gebruik. De executable-UUID komt exact overeen met de eerder geleverde distributie. Bij AppKit-vensteractivatie crasht de hoofdthread met EXC_BAD_ACCESS in `SerialExecutor._isSameExecutor`, via de Objective-C-getter `NonKeyPanel.canBecomeKey`. Het ongeldige adres is `0xaaaaaaaaaaaaaad0`.

De oude getter doet uitsluitend `false` retourneren, maar bevat een compilergegenereerde MainActor-executorcontrole. `RecordingHUDPanel.swift` en `CaptionOverlayPanel.swift` verklaren nu alleen deze constante `canBecomeKey`/`canBecomeMain`-getters `nonisolated`. Actuele locaties: `WhisperClipboard/UI/HUD/RecordingHUDPanel.swift:275` en `WhisperClipboard/UI/Captions/CaptionOverlayPanel.swift:138`; tests in `WhisperClipboardTests/WhisperClipboardTests.swift:48` en `:65`. De panelen blijven niet-activerend. Andere UI-toegang behoudt zijn actorisolatie. De twee klassen zijn intern zichtbaar gemaakt voor gerichte regressietests.

De oorzaak van de ongeldige runtime-pointer is niet bewezen. Deze reparatie verwijdert aantoonbaar de betreffende controle uit alle vier focusgetters; zij bewijst niet dat iedere mogelijke crash verholpen is. Dit past bij [Swift nonisolated-documentatie](https://docs.swift.org/compiler/documentation/diagnostics/actor-isolated-call/): de getters lezen geen geïsoleerde toestand.

## Verificatie

Omgeving: lokale Apple-silicon Mac, macOS 27.0 (26A428), Xcode 27.0 (27A266a).

- Geslaagd: Release-build via `xcodebuild -quiet -project WhisperClipboard.xcodeproj -scheme WhisperClipboard -configuration Release -destination 'platform=macOS,arch=arm64' build` vanuit v2.
- Geslaagd: 336 Mac-tests, 0 fouten. De drie bestaande E2E-suites E2EImportSmokeTests, E2EDiarizationSmokeTests en E2ECaptionsSmokeTests zijn expliciet uitgesloten. Geen nieuwe uitvoering van Core- of iPhone-tests.
- Testcommando: `xcodebuild -quiet -project WhisperClipboard.xcodeproj -scheme WhisperClipboard -destination 'platform=macOS,arch=arm64' -skip-testing:WhisperClipboardTests/E2EImportSmokeTests -skip-testing:WhisperClipboardTests/E2EDiarizationSmokeTests -skip-testing:WhisperClipboardTests/E2ECaptionsSmokeTests -resultBundlePath /tmp/WhisperClip203CrashTestsFinal.xcresult test`.
- Nieuwe tests: herhaalde Objective-C-callbacks voor beide panelen; constante focusantwoorden vanuit een detached taak zonder benodigde executor.
- Geslaagd: geoptimaliseerde zelfstandige AppKit-harness, 500 panellevenscycli en 100.000 Objective-C-getteraanroepen; panelen verkrijgen geen toetsenbordfocus. Compileer `ReviewScreenshots/2026-09-21-mac-crash/PassivePanelStress.swift` met `swiftc -swift-version 6 -O -parse-as-library` en voer de binary uit. Een eerste harnesspoging riep ten onrechte makeMain aan op een paneel dat expliciet niet main mag worden; die ongeldige testactie is verwijderd.
- Geslaagd: Release-disassembly. Alle vier Objective-C-getters bestaan uitsluitend uit `mov w0, #0` en `ret`. Voor/na-fragmenten staan in `ReviewScreenshots/2026-09-21-mac-crash/`.
- Geslaagd: zeven geïsoleerde backup-helpertests via `python3 v2/Packaging/test_work_mac_backup.py` vanuit de repository-root.

Niet getest: langdurig gebruik op de werk-Mac, diens schermen, echte opname/transcriptie en live iCloud in de nieuwe distributie. De zelfstandige harness gebruikt de gewijzigde panelklassen maar is niet de volledige app. Geen persoonlijke database geopend of gewijzigd voor tests. Geen wijziging aan iPhone-versie 2.0.2 (8).

## Installatie en distributie

Nieuwe zichtbare versie 2.0.3, build 9; project.yml en Xcode-project gelijk bijgewerkt. Release gebruikt history.db en CloudKit Production. Gebruik de bijgeleverde backup-helper vóór vervanging op dezelfde locatie; nooit appgegevens verwijderen. Bestaande bronwijzigingen blijven behouden. Deze reparatie is nog niet gecommit.


Distributie voltooid: `Releases/WhisperClip-2.0.3.dmg`, Developer ID ondertekend, app en DMG door Apple geaccepteerd en tickets aangehecht. Gatekeeper accepteert beide. De uiteindelijke DMG is alleen-lezen gemount: appversie 2.0.3 (9), diepe strikte handtekeningcontrole, ticket, instructies en backup-helper geverifieerd. `hdiutil verify` geslaagd.

SHA-256: `1ef5a9313283a3f1f5b90eb12ce6ec897c3772aaf807b3ee41fcbfd56b410629`. Bewijs: `ReviewScreenshots/2026-09-21-mac-crash/distribution-verification.txt`. Niet gepubliceerd naar App Store Connect; niet op de werk-Mac geïnstalleerd vanuit deze sessie.
