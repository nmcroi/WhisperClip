# WhisperClip — actuele overdracht

Bijgewerkt: 22 september 2026. Startpunt voor Claude, Codex en andere ontwikkelaars.

## Actueel — structurele hoverreparatie macOS 2.0.5 (11), 23 september

- De werk-Mac is opnieuw gecrasht op 2.0.3 (9): dezelfde Swift-executorcontrole, nu via AppDelegate.applicationShouldHandleReopen bij een Dock/AppleEvent-heropenverzoek. De vorige reparatie was onvoldoende.
- Heropenen gaat nu via een nonisolated callback naar een expliciete hoofdactortaak; constante sluitbeslissing is nonisolated. Overbodige heractivatie-observer bij windowDidBecomeKey verwijderd. Andere UI-isolatie behouden.
- 337 Mac-tests geslaagd. Geoptimaliseerde geïsoleerde AppKit-app verwerkt 50 echte LaunchServices-heropenverzoeken met openen/sluiten van vensters. Zeven backup-helpertests geslaagd.
- Root cause van ongeldige executorpointer nog onbekend. Geen langdurige volledige-app-test of live opname/iCloud op werk-Mac. Oude bevindingen blijven open.
- Hover-events zijn volledig verwijderd uit de macOS-HUD, actiekaarten en transcriptdetails. 337 Mac-tests slagen; Release-build en statische broncontrole slagen.
- Klaar als testartefact: `Releases/WhisperClip-2.0.5.dmg` (vanaf Git-root), ondertekend, genotariseerd en definitieve DMG geverifieerd. De crash is nog niet als opgelost bewezen. Zie `Packaging/RELEASE_2.0.5.md` en `CLAUDE_MACOS_CRASH_HANDOFF.md` voor de volledige overdracht. iPhone blijft 2.0.2 (8). Bestaande lokale wijzigingen behouden; geen commit of App Store-publicatie.

## Historisch — Mac-crashreparatie 21 september 2026 (onvoldoende gebleken)

- Mac 2.0.3 (9): gerichte reparatie voor ontvangen 2.0.2 (7)-crash bij AppKit-vensteractivatie via `NonKeyPanel.canBecomeKey` en Swift-executorcontrole.
- Constante focusgetters van HUD en ondertitelpaneel zijn `nonisolated`; overige UI-isolatie blijft behouden. Release-machinecode bevat alleen `false` + return.
- 336 Mac-tests geslaagd; 500 panellevenscycli en 100.000 Objective-C-getteraanroepen in geoptimaliseerde AppKit-harness geslaagd. Zeven backup-helpertests geslaagd.
- Onderliggende oorzaak van het ongeldige runtime-adres is niet bewezen. Langdurig gebruik op de werk-Mac, volledige opnameflow en live iCloud op deze nieuwe distributie moeten nog worden bevestigd.
- Klaar: `Releases/WhisperClip-2.0.3.dmg` (vanaf Git-root), ondertekend, genotariseerd en definitieve DMG geverifieerd. Zie `Packaging/RELEASE_2.0.3.md`. iPhone blijft 2.0.2 (8). Geen iPhone-installatie of gegevensmigratie bij deze reparatie.

## Werkmap en versie

- Git-root: `/Users/nielscroiset/Werkmappen/Development/WhisperClip`.
- Actieve appbron: `v2/`; native iPhone- en macOS-app, gedeelde Swift-packages.
- Branch: `werk/augustus-2026`. Code, tests en reviewdocumentatie gepusht in `30b2ae41e0af21350812cc1c8ff0e9abf5afdd71`.
- Controleer bij een nieuwe sessie altijd de actuele Git-status; bovenstaande is een overdrachtsmoment.
- Oudere startprompts, TODO's en final-run-documenten zijn historische plannen, geen bewijs van de actuele implementatie of een nieuwe publicatieopdracht.

## Eerst lezen

1. `REVIEW_2026-09-17_IPHONE.md`: reparaties, tests, resterende risico's en installatieaanvulling.
2. `REVIEW_2026-09-17_MACOS.md`: Mac-review, reparaties, testcommando's en installatie.
3. `IMPLEMENTATION_2026-09-13_AUDIO.md`: gedeelde audio- en herstelroute.
4. `VINCENT_IPHONE_UPDATE.md`: verplichte veilige updateprocedure.
5. `PRIVACY.md`: gegevensverwerking.

## Behouden gedrag

- Behoud de rustige vormgeving en native iPhone-tabbar met bubbel. Vervang die niet door een eigen menubalk om performance te verbeteren.
- Audio bewaren is optioneel; de opnamekeuze verschijnt alleen volgens de zichtbaarheidinstelling. Houd bestaande Mac-voorkeuren en lopende opnamebeslissingen intact.
- Notulist bewaart geen permanente audio. Bewaarde audio blijft lokaal; export is M4A.
- Notitieopnames blijven bij de notitie; gegevens, instellingen en synchronisatie-identiteit behouden.
- iCloud is vrijwillig en gebruikt de private CloudKit-database van de Apple-account op het apparaat.

## Uitgevoerd en geverifieerd

- iPhone: async geschiedenissnapshots, minder werk op de hoofdthread, respecteren van iCloud-uit na herstart; native bubbel behouden.
- Mac: async geschiedenis zonder de oude 500-resultatengrens, gevalideerde audiopaden en geïsoleerde tests zonder echte API-sleutels of appservices.
- Laatste Mac-review: 332 Mac-tests, 81 gedeelde tests en 199 Core-tests geslaagd (612 totaal); Debug- en Release-build geslaagd. Drie expliciet uitgesloten E2E-suites staan in het rapport.
- iPhone-review: build, vijf UI-tests en aparte iCloud-opt-outtest geslaagd; zie rapport voor omgeving en beperkingen.
- Niels' iPhone en Mac zijn op 17 september na backup bijgewerkt en gestart; databases en instellingen zijn gecontroleerd op behoud. Installeren/starten bewijst geen vloeiende animatie of correcte live synchronisatie.
- Testresultaatsamenvattingen en synthetische screenshots staan in `ReviewScreenshots/`. Volledige tijdelijke logs/xcresults onder `/tmp` kunnen verdwijnen.

## Nog open — niet als opgelost rapporteren

- IP-03 (beide apps, P1): SQLite-mutatie en apart sync-journal zijn niet atomair; transactionele outbox/tombstones en crash-/herleveringstests nodig.
- IP-05: de updateprocedure moet variantwissels met twee reeds gevulde databases beter afvangen. Wissel niet stilzwijgend Debug/Release.
- MAC-04: synchrone bestands-I/O in auto-export en mapbewaking kan de hoofdthread blokkeren; impact op trage mappen nog niet gemeten.
- MAC-05: foutafhandeling bij audio trimmen/converteren en verwijderen van het origineel aanscherpen.
- Fysieke bubbelhapering nog niet geprofileerd. Lange opname, vergrendeling, onderbreking, echte microfoon/sneltoets, live tweetoestel-sync en volledige toegankelijkheids-/apparaatmatrix zijn niet door de groene tests bewezen.
- De rapporten bevatten de volledige bevindingen, kleinere punten en precieze scope; dit is geen volledige veiligheidsaudit.

## Veilig verder werken

- Vincent uitsluitend bijwerken via `scripts/update_vincent_iphone.sh`, met gecontroleerde backup vooraf. Nooit app of container verwijderen.
- Zijn toestel-ID staat lokaal in `Configs/Vincent-iPhone.udid`; dit bestand staat bewust niet op GitHub. Ontbreekt het, dan stopt het updatescript.
- Ook bij Niels bestaande data en de gebruikte databasevariant behouden; controleer beide history-databases vóór en na een update.
- `../device-backups/`, lokale signingconfiguratie en toestelconfiguratie zijn privé en uitgesloten van Git. GitHub bevat geen gebruikersbackup.
- Publiceer of upload niet naar App Store Connect zonder expliciete opdracht. Gebruik geïsoleerde testgegevens; lees scripts vóór uitvoering.

## Aanvulling 18 september — hoofdvenster sluiten

- Rode kruisje sluit alleen het Mac-hoofdvenster; de app blijft actief. Dock-icoon blijft beschikbaar. Heropenen richt zich op de hoofdscene, ook als Instellingen open is. Cmd-Q/Stop sluit wel af.
- AppDelegate houdt de app actief na het laatste venster; heropenen gebruikt SwiftUI openWindow in plaats van een generieke New Window-selector. Apple's beschrijving van het standaard Window-afsluitgedrag: https://developer.apple.com/documentation/swiftui/window
- Gerichte `WhisperClipboardTests/WhisperClipboardTests` en Debug-build geslaagd. In de geïnstalleerde app via Accessibility het echte sluitknopje bediend: proces bleef actief met nul vensters; heropenen gaf hetzelfde proces met één venster. Cmd-Q beëindigde het proces; daarna opnieuw gestart.
- Na lokale backup geïnstalleerd met identieke signing-entitlements. Alle bestaande transcript- en notitierijen ongewijzigd behouden; Development had daarna één extra transcript (1442 naar 1443), herkomst niet onderzocht. Zeven notities en de andere database (3 transcripties) behouden; settings.json bytegelijk. Backup: `../device-backups/Niels-Mac/2026-09-18-135024-window-close/`.
- Geen echte microfoonopname gestart voor deze controle; de sneltoets/HUD-opname na sluiten moet nog praktisch worden bevestigd.

## Voorbereid: macOS 2.0.2 (build 6), 18 september

Status: lokale testkandidaat, nog niet geïnstalleerd of op de werk-Mac getest. De vorige geïnstalleerde app blijft actief totdat de volgende gecontroleerde installatie plaatsvindt. iPhone-versie ongewijzigd.

- HUD-positionering hersteld: een grotendeels verborgen bewaarde positie wordt niet meer geaccepteerd. Het volledige paneel wordt met marge binnen het bruikbare scherm geplaatst, ook bij negatieve monitorcoördinaten, losgekoppelde schermen en veranderende inhoudshoogte.
- Schermwijzigingen en panel-resizes corrigeren de positie. Expliciet sleepvlak bovenaan gebruikt AppKit `performDrag`, onafhankelijk van SwiftUI-achtergrond-hit-testing. De echte sleepbeweging op macOS 27 is nog niet getest.
- Versionering in `project.yml` (globaal en Mac-target) en gegenereerd project: 2.0.2 / 6. In de gebouwde Info.plist gecontroleerd; codesign-verificatie geslaagd. Regel voor unieke geleverde versie/build-paren toegevoegd aan AGENTS.md en CLAUDE.md.
- Gerichte vier tests (`WhisperClipboardTests/WhisperClipboardTests`) geslaagd op macOS 26.5.1; geometrie omvat verborgen strook, randen, afgekoppeld scherm, negatieve coördinaten, ongeldige voorkeuren en groeiende HUD. Debug-build geslaagd. Commando: `xcodebuild -quiet -project WhisperClipboard.xcodeproj -scheme WhisperClipboard -destination 'platform=macOS,arch=arm64' -only-testing:WhisperClipboardTests/WhisperClipboardTests test`.
- Lokale app, ZIP en hashmanifest: `Packaging/dist/WhisperClip-2.0.2-6-local-test/` (bewust niet in Git). Apple Development/Debug, geen genotariseerde distributierelease. Werk-Mac-profiel en databasevariant vóór overzetten verifiëren.
- Deze Mac draait nog 26.5.1. macOS 27-compatibiliteit niet bewezen; gebruiker wil eerst lokaal op 27 testen en daarna overzetten. Geen OS-upgrade gestart. Na OS-upgrade testen: HUD slepen, schermwissel/schaal/Dock, sneltoets na sluiten hoofdvenster, microfoon, iCloud en data behouden. Eerst volledige Mac-backup; de appbackups zijn geen volledige systeembackup.

## Uitgevoerd na OS-upgrade — 18 september, macOS 27.0

De vorige status 'nog niet geïnstalleerd/getest op 27' is voor Niels' lokale Mac vervallen: WhisperClip **2.0.2 (6)** is na nieuwe backup geïnstalleerd op macOS **27.0 (26A428)**. 334 Mac-tests geslaagd. Echte sluitknop, sneltoets met gesloten hoofdvenster, microfoonopname/pauze/stop, HUD omhoog slepen via het sleepvlak en hoofdvenster heropenen gecontroleerd. Bestaande gegevens en settings behouden; opnameproeven kunnen extra transcripties hebben toegevoegd.

Zie `ReviewScreenshots/2026-09-18-macos27/README.md` en `test-results.json` voor bewijs, commando en beperkingen. De werk-Mac en fysieke externe schermopstelling zijn nog niet getest. De geteste kandidaat staat lokaal in `Packaging/dist/WhisperClip-2.0.2-6-local-test/`; signing en databasevariant op de werk-Mac controleren vóór overzetten. Geen appcode aangepast tijdens deze OS-27-controle.

## Distributie gereed — WhisperClip 2.0.2, build 7

DMG voor de werk-Mac: `../Releases/WhisperClip-2.0.2.dmg`. Release-build, Developer ID, Apple-notarisatie en tickets voor zowel app als DMG gecontroleerd, inclusief Gatekeeper-controle van de app binnen de aangekoppelde DMG. Lokale Debug build 6 blijft ongewijzigd; Release build 7 is een apart geleverd bestand.

DMG bevat een back-up-/variantcontrole vóór vervanging, getest met zeven geïsoleerde scenario's. Die stopt bij ontwikkelgegevens, dubbele installatie of corrupte database. Release gebruikt `history.db` en Production-CloudKit; overstappen vanaf Development gebeurt niet stilzwijgend. Geen persoonlijke gegevens/sleutels meegeleverd en niets gepubliceerd.

Details en testgrenzen: `Packaging/RELEASE_2.0.2.md`. De echte werk-Mac is niet rechtstreeks onderzocht; voer daar eerst de meegeleverde controle uit. De app is niet automatisch op een ander apparaat geïnstalleerd.

## Koens eerste iPhone-installatie — 19 september 2026

WhisperClip iOS 2.0.2 (8), Debug met Development-iCloud-vlag, succesvol gebouwd en geïnstalleerd op Koens iPhone 15 Pro (26.6.2). Bestaande WhisperClip-installatie niet aangetroffen. Ondertekening en opname van het toestel in het provisioning profile gecontroleerd; profiel geldig tot 19 september 2027.

Parakeet via de kabel geplaatst terwijl de app dicht was: 23 bestanden, 483.256.769 bytes. Volledig teruggekopieerd en alle SHA-256-hashes gelijk aan de bron. Geen persoonlijke instellingen/API-sleutels gekopieerd. Privé-installatiegegevens onder `../device-backups/Koen-iPhone/`.

Eerste start geblokkeerd door iOS security/trust: toestel vraagt nog ontwikkelaarvertrouwen (na de reeds geslaagde computerkoppeling en Ontwikkelaarsmodus). Nog nodig: op de iPhone via Algemeen → VPN en apparaatbeheer ontwikkelaar vertrouwen, appstart en korte transcriptieproef. Niet als volledig werkend gevalideerd rapporteren voordat die controles zijn afgerond.

Algemeen kabelrecept nu ook in de repo: `IPHONE_EERSTE_INSTALLATIE.md`.
