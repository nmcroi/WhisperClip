# WhisperClip macOS 2.0.4 (10) — Dock-heropenen

22 september 2026. Gerichte vervolgreparatie, geen volledige appreview.

## Vastgesteld

Het nieuwe rapport is daadwerkelijk van 2.0.3 (9). ARM64-UUID F27DDE9F-E180-32C6-AF6B-96F988EC4CD0 is met dwarfdump gecontroleerd tegen de geleverde app. macOS 27.0 (26A428), circa 85 minuten na starten. De hoofdthread crasht bij een AppleEvent voor heropenen, in `@objc AppDelegate.applicationShouldHandleReopen(_:hasVisibleWindows:)`, via `swift_task_isCurrentExecutorWithFlagsImpl` en `SerialExecutor._isSameExecutor`, adres `0xaaaaaaaaaaaaaad0`.

De vorige panelgetterreparatie was onvoldoende om de terugkerende crashes te verhelpen. De crash ligt nu in een andere Objective-C-ingang met hetzelfde runtimepatroon. De oorzaak van de ongeldige executorverwijzing is nog onbekend. Thread 9 meldt een eerder door HIServices opgevangen exception; het rapport bevat geen naam/redencode daarvan. Dit is een onderzoeksspoor, geen bewezen oorzaak. Een eerdere exception kan mogelijk terug te vinden zijn in `~/Library/Logs/Whisper Clipboard/app.log` op de werk-Mac. De werk-Mac-log is niet ingezien en bevat mogelijk tekst; niet automatisch publiceren. De lokale app.log heeft nul regels met onafgevangen NSException; dat zegt niets over de werk-Mac.

Actuele codeplaatsen: `WhisperClipboard/App/AppDelegate.swift:374` (sluiten), `:378` (heropenen), `:471` (venster openen); tests `WhisperClipboardTests/WhisperClipboardTests.swift:13` en `:31`.

## Wijzigingen

- `AppDelegate.applicationShouldHandleReopen` is een `nonisolated` grenscallback. Deze retourneert onmiddellijk false en laat een expliciete `Task { @MainActor ... }` het hoofdvenster openen. De callback gebruikt geen AppKit-toestand, assumeIsolated of onveilige actorcasts. UI-toegang blijft hoofdactor-geïsoleerd.
- De constante `applicationShouldTerminateAfterLastWindowClosed` retourneert nonisolated false. Het rode kruisje sluit nog steeds uitsluitend het venster.
- De overbodige `windowDidBecomeKey`-observer die bij iedere focusverandering opnieuw activeerde is verwijderd. De app is al regular bij starten; expliciet vensteropenen en de bestaande WindowConfigurator regelen activatie. showMainWindow activeert alleen als de app nog niet actief is.
- Andere menu-/lifecyclecallbacks zijn bekeken en behouden: de nieuwe rapporten bewijzen geen crash op die ingangen. Er is geen globale uitschakeling van concurrencycontroles, geen dependency-update en geen database- of syncwijziging.
- macOS verhoogd naar 2.0.4 (10) in project.yml; XcodeGen uitgevoerd. Scheme-productnaam weer afgestemd op PRODUCT_NAME WhisperClip. iPhone/widget blijven 2.0.2 (8).

Dit is een afgebakende mitigatie van de bevestigde heropenroute, geen bewezen oplossing van de onderliggende geheugencorruptie. Ook SwiftUI en andere frameworkcallbacks bevatten executorcontroles.

## Verificatie en beperkingen

Omgeving: macOS 27.0 (26A428), Xcode 27.0 (27A266a), Apple silicon. Echte gebruikersdata niet gebruikt.

- Geslaagd: 337 Mac-tests, 0 fouten. Debug-suite: bestaande drie externe E2E-suites bewust uitgesloten, zoals bij 2.0.3. Exacte uitsluitingen: E2EImportSmokeTests, E2EDiarizationSmokeTests, E2ECaptionsSmokeTests.
- Tests bevestigen onmiddellijk terugkeren zonder synchrone vensteractivatie; vervolgens juiste hoofdscene en hoofdthread, zowel met als zonder zichtbare vensters. Nieuwe test doet 200 aanroepen via de echte Objective-C-IMP.
- Geoptimaliseerde zelfstandige AppKit-harness: 50 echte LaunchServices-heropenverzoeken via `open -a`, steeds venster openen/sluiten, hoofdthread gecontroleerd en proces blijft actief. Callbackmethoden zijn letterlijk uit productiecode overgenomen. Bron en resultaat in `ReviewScreenshots/2026-09-22-mac-reopen/`.
- Release-build geslaagd. De ARM64-machinecode van beide gewijzigde lifecyclecallbacks bevat geen `swift_task_isCurrentExecutor` of `swift_task_reportUnexpectedExecutor`. De oude 2.0.3-heropencallback bevat die controle wel; voor/na-disassembly is opgeslagen. Dit bewijst verwijdering van de ingang, niet herstel van de onderliggende runtimeverwijzing.
- Zeven geïsoleerde backup-helpertests geslaagd.
- De ongeldige executorverwijzing zelf is niet gereproduceerd. Geen langdurige volledige-app-run, echte transcriptie of live iCloud op de werk-Mac getest. Groene tests bewijzen niet dat alle crashes weg zijn.

Reproduceerbare suite vanuit v2:
```
xcodebuild -quiet -project WhisperClipboard.xcodeproj -scheme WhisperClipboard -destination 'platform=macOS,arch=arm64' -skip-testing:WhisperClipboardTests/E2EImportSmokeTests -skip-testing:WhisperClipboardTests/E2EDiarizationSmokeTests -skip-testing:WhisperClipboardTests/E2ECaptionsSmokeTests -resultBundlePath /tmp/WhisperClip204FinalTests.xcresult test
xcodebuild -quiet -project WhisperClipboard.xcodeproj -scheme WhisperClipboard -configuration Release -destination 'platform=macOS,arch=arm64' build
```

## Onderzoeksbronnen

De [Swift-runtimebron](https://github.com/swiftlang/swift/blob/main/stdlib/public/Concurrency/Executor.swift) beschrijft de executorvergelijking. Er bestaan soortgelijke meldingen in [CodexBar](https://github.com/steipete/CodexBar/issues/2250) en [cmux](https://github.com/manaflow-ai/cmux/issues/9553). Dat zijn oorspronkelijke projectmeldingen, geen bewijs dat WhisperClip dezelfde grondoorzaak heeft of dat dit een door Apple bevestigde OS-bug is.

## Installatie

Normale Release-variant met history.db en CloudKit Production. Eerst Cmd-Q, dan de backup-helper in de DMG, vervolgens de app op dezelfde locatie vervangen. Geen appdata wissen. Geen publicatie naar App Store Connect en geen commit in deze sessie.

## Definitieve distributiecontrole

Klaar: `Releases/WhisperClip-2.0.4.dmg`. App en DMG Developer ID-ondertekend, Apple Accepted en tickets aangehecht. Gatekeeper accepteert beide. hdiutil verify, gemounte appversie 2.0.4 (10), diepe strikte handtekeningcontrole en gelijkheid van helper/instructies geslaagd. SHA-256: `0bd152f3c7f0bf0967ebcf2e250f1b66cbf22189b0e7482a3872fdffe411eb50`. Geen installatie op de werk-Mac in deze sessie.
