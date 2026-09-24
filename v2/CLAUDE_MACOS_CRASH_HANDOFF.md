# WhisperClip macOS 27 crashonderzoek — overdracht aan Claude

Bijgewerkt: 23 september 2026  
Status: **probleem nog niet opgelost**. Versie 2.0.5 is wel gebouwd en gedistribueerd, maar mag niet als crashvrij worden beschouwd.

## Doel van deze overdracht

Gebruik dit document als startpunt voor verder onderzoek. De drie rapporten tonen dezelfde familie van crashes in `libswift_Concurrency.dylib`, maar via verschillende macOS-ingangen. De eerdere reparaties hebben telkens één ingang verwijderd; het terugkerende probleem bewijst dat de onderliggende oorzaak nog niet gevonden is.

## Omgeving en geleverde versies

- Werk-Mac: MacBook Pro `Mac15,6`, Apple M3 Pro, 18 GB.
- macOS `27.0 (26A428)`, ARM64, Xcode `27.0 (27A266a)`.
- App-pad: `/Applications/WhisperClip.app`.
- Productievariant: `history.db`, CloudKit Production.
- 2.0.2 (7): eerste rapport, na ongeveer 2 uur 13 minuten.
- 2.0.3 (9): tweede rapport, na ongeveer 85 minuten.
- 2.0.4 (10): derde rapport, na ongeveer 51 minuten.
- 2.0.5 (11): structurele hoverwijziging, DMG genotariseerd maar nog niet op de werk-Mac getest.

## Crash 1 — 2.0.2 (7), panel-focus

Stackroute:

```
AppKit vensteractivatie
  -> @objc NonKeyPanel.canBecomeKey
  -> swift_task_isCurrentExecutorWithFlagsImpl
  -> SerialExecutor.isMainExecutor
  -> SerialExecutor._isSameExecutor
  -> EXC_BAD_ACCESS, 0xaaaaaaaaaaaaaad0
```

Wijziging in 2.0.3:

- `NonKeyPanel.canBecomeKey` en `canBecomeMain` werden `nonisolated` en retourneren alleen `false`.
- Hetzelfde is gedaan voor `NonKeyCaptionPanel`.
- Release-disassembly liet daarna uitsluitend `mov w0, #0; ret` zien.

Dit verhielp de route in de binary, maar niet de algemene crashfamilie.

Bewijsbestanden:

- `ReviewScreenshots/2026-09-21-mac-crash/2.0.2-focus-getters.txt`
- `ReviewScreenshots/2026-09-21-mac-crash/2.0.3-focus-getters.txt`
- `Packaging/RELEASE_2.0.3.md`

## Crash 2 — 2.0.3 (9), Dock/heropenen

Stackroute:

```
AppleEvent voor opnieuw openen via Dock
  -> @objc AppDelegate.applicationShouldHandleReopen
  -> swift_task_isMainExecutorSwift
  -> SerialExecutor.isMainExecutor
  -> SerialExecutor._isSameExecutor
  -> EXC_BAD_ACCESS, 0xaaaaaaaaaaaaaad0
```

Wijziging in 2.0.4:

- `applicationShouldHandleReopen` werd `nonisolated`.
- De callback retourneert onmiddellijk `false`.
- Het hoofdvenster wordt daarna geopend via `Task { @MainActor ... }`.
- De overbodige `windowDidBecomeKey`-observer, die de app opnieuw activeerde bij elke focuswisseling, is verwijderd.
- `applicationShouldTerminateAfterLastWindowClosed` werd eveneens `nonisolated`.

Dit verhielp de route in de Release-machinecode, maar niet de algemene crashfamilie.

Bewijsbestanden:

- `ReviewScreenshots/2026-09-22-mac-reopen/2.0.3-reopen.txt`
- `ReviewScreenshots/2026-09-22-mac-reopen/release-reopen.txt`
- `ReviewScreenshots/2026-09-22-mac-reopen/release-close.txt`
- `ReviewScreenshots/2026-09-22-mac-reopen/DockReopenStress.swift`
- `Packaging/RELEASE_2.0.4.md`

## Crash 3 — 2.0.4 (10), SwiftUI hover/hit-testing

Stackroute:

```
AppKit mouseEntered
  -> SwiftUI NSHostingView.mouseEntered
  -> SwiftUI HoverEventDispatcher / hit testing
  -> MainActor.assumeIsolated
  -> swift_task_isMainExecutorImpl
  -> swift_getObjectType
  -> EXC_BAD_ACCESS, 0xaaaaaaaaaaaaaad0
```

Belangrijk: in deze stack staat geen WhisperClip-functie tussen AppKit en SwiftUI. De crash gebeurt tijdens een muisbeweging over een SwiftUI-view. Dit was de aanleiding voor de structurele keuze in 2.0.5.

## Wat in 2.0.5 is gewijzigd

Alle macOS-hovermechanismen zijn verwijderd uit:

- `WhisperClipboard/UI/HUD/RecordingHUDView.swift`;
- `WhisperClipboard/UI/Components/ActionCard.swift`;
- `WhisperClipboard/UI/History/TranscriptDetailView.swift`.

Concreet verwijderd:

- `.onHover`;
- hover-statevariabelen;
- `PointingHandCursor` en `NSCursor.push/pop`;
- hoverkleur-, hoverrand- en hover-schaalanimaties;
- hoverafhankelijke zichtbaarheid van trimknoppen.

Trimknoppen zijn permanent zichtbaar als de actie beschikbaar is. Klikken, toetsenbordbediening, opnemen, pauzeren, stoppen, kopiëren en navigatie zijn niet verwijderd. De iPhone-target is niet aangepast.

Statische controle na de wijziging:

```
rg -n '\\.onHover|hoverEffect|onContinuousHover|NSTrackingArea|mouseEntered|mouseExited|pointingHandCursor' v2/WhisperClipboard
```

Resultaat: geen treffers.

## Testbewijs

- 337 Mac-tests: geslaagd, 0 fouten, 0 skips.
- Bestaande E2E-suites zijn expliciet uitgesloten: `E2EImportSmokeTests`, `E2EDiarizationSmokeTests`, `E2ECaptionsSmokeTests`.
- Release-build 2.0.5 (11): geslaagd op macOS 27.
- Panelstress: 500 panellevenscycli en 100.000 Objective-C-getteraanroepen geslaagd.
- Dockstress: 50 echte LaunchServices-heropenverzoeken met venster openen/sluiten geslaagd.
- Backup-helper: 7 geïsoleerde tests geslaagd.
- 2.0.5 DMG: Developer ID, Apple notarization, stapler, Gatekeeper en `hdiutil verify` geslaagd.

Dit zijn lokale tests op de ontwikkel-Mac. Er is geen langdurige volledige-app-run op de werk-Mac uitgevoerd en er is geen live iCloud- of echte microfoontest met deze nieuwe DMG gedaan.

## Wat nog niet bewezen is

1. Of de werk-Mac werkelijk 2.0.5 (11) draait.
2. Of de crash ook optreedt wanneer de muis niet over een WhisperClip-venster beweegt.
3. Of een eerder opgevangen Objective-C/AppKit-exception de geheugenbeschadiging voorafgaat.
4. Of de `0xaaaaaaaa...`-waarde uit een macOS 27-runtimebug, use-after-free, actor-lifetimeprobleem of een nog niet gevonden app-callback komt.
5. Of dezelfde beschadigde executorreferentie ook in andere SwiftUI-eventroutes voorkomt.

## Aanbevolen vervolgonderzoek

1. Bevestig op de werk-Mac dat `WhisperClip.app` versie 2.0.5 (11) en de UUID van de nieuwe DMG draait.
2. Verzamel uitsluitend het lokale WhisperClip-logbestand na de volgende crash: `~/Library/Logs/Whisper Clipboard/app.log`. Controleer vooral `Onafgevangen NSException` vlak vóór het crashmoment. Publiceer geen transcripttekst of persoonsgegevens.
3. Noteer de trigger exact: muis boven venster, Dock-heropenen, rood kruisje, statusbalkmenu, opname, schermvergrendeling of iCloud-sync.
4. Vergelijk een run met het hoofdvenster gesloten en alleen de menubalkfunctie actief. Als de crash dan blijft optreden, is hover niet langer een plausibele directe trigger.
5. Gebruik Instruments/Console op de werk-Mac voor Main Thread Checker, Zombies en Exception Breakpoint. De huidige rapporten bewijzen alleen de crashlocatie, niet wie de beschadigde executorreferentie heeft veroorzaakt.

## Belangrijke werkafspraak

Rapporteer 2.0.5 niet als definitieve oplossing. De juiste status is: **hoverroute structureel verwijderd; crashprobleem nog open totdat de werk-Mac langdurig zonder crash draait of een nieuwe crashroute is onderzocht**.
