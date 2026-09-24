# macOS 27 — WhisperClip 2.0.2 (6)

18 september 2026, MacBook Pro Apple silicon, macOS 27.0 (26A428), Xcode 26.6 (17F113). Bestaande kandidaat van 2.0.2 build 6 geïnstalleerd; geen gewijzigde binary onder hetzelfde nummer.

## Automatische controle

334 Mac-tests geslaagd, nul fouten/skips. De drie externe E2E-suites expliciet uitgesloten:

```sh
xcodebuild -quiet -project WhisperClipboard.xcodeproj -scheme WhisperClipboard -destination 'platform=macOS,arch=arm64' -skip-testing:WhisperClipboardTests/E2EImportSmokeTests -skip-testing:WhisperClipboardTests/E2EDiarizationSmokeTests -skip-testing:WhisperClipboardTests/E2ECaptionsSmokeTests -resultBundlePath /tmp/WhisperClipMacOS27Review.xcresult test
```

Samenvatting: `test-results.json` (toestel-ID verwijderd). Het betreft uitvoering op OS 27 met de bestaande Xcode-toolchain, geen build met een nieuwe Xcode 27-toolchain. Core/Shared-suites niet opnieuw afzonderlijk uitgevoerd; hun eerdere resultaten zijn geen nieuwe OS-27-testresultaten.

## Gecontroleerd in geïnstalleerde app

- Rode sluitknop via Accessibility bediend; hoofdvenster verdween en proces bleef actief.
- Control-spatie startte daarna een echte microfoonopname; HUD zichtbaar zonder hoofdvenster.
- Pauzeknop bediend; via echte muis-down/drag/up-events aan het nieuwe sleepvlak de HUD omhoog verplaatst. AX-positie van (176,839) naar (420,342), venstergrootte na pauzeren 360x58. Stopknop bleef bedienbaar.
- Opname gestopt; hoofdvenster opnieuw geopend met hetzelfde proces (8462).
- Bij volgende opname verscheen de HUD opnieuw in het bovenste schermdeel. Een AppleScript-variabele `bounds` veroorzaakte een automatiseringsfout; de opname is vervolgens met Control-spatie gestopt. Dit was geen appfout. Geen doorlopende opname achtergelaten.
- Korte echte opnameproeven kunnen extra transcripties opleveren; bestaande gebruikersrijen niet verwijderd of bewerkt. Geen inhoud opgenomen in dit rapport.

## Installatie en gegevens

App: `~/Applications/WhisperClip.app`, versie 2.0.2 (6). Apple Development/Debug, identieke ondertekende entitlements als de vorige installatie; codesign-verificatie geslaagd. Eerst app afgesloten en app/data/voorkeuren geback-upt naar `../../../device-backups/Niels-Mac/2026-09-18-153822-macos27-202/` vanaf deze map.

Controle na installatie en eerste proeven: beide databases integer; alle 1447 bestaande Development-transcripties en 7 notities ongewijzigd; één extra transcript aanwezig. Andere database 3 transcripties ongewijzigd. settings.json bytegelijk. Latere opnameproeven kunnen het aantal nieuwe records verhogen. Privébewijzen staan in de backupmap, niet in Git.

## Grenzen en volgende stap

Niet getest: werk-Mac, fysieke externe-monitorwissels, resolutie/schaalwijzigingen, alle Dock-posities, lange opname, live iCloud-tweetoesteluitwisseling en transcriptiekwaliteit met een referentietekst. Schermranden, negatieve monitorcoördinaten en verdwenen displays zijn geometrisch getest, niet met fysiek aangesloten meerdere displays.

De lokale ZIP in `Packaging/dist/WhisperClip-2.0.2-6-local-test/` bevat dezelfde geteste app. Geen App Store-upload, notarization of verzending uitgevoerd. Vóór installatie op de werk-Mac diens signing/provisioning en Debug/Release-databasevariant controleren en backup maken; nooit de app/container verwijderen om een update te forceren.
