# WhisperClip — actuele overdracht

Bijgewerkt: 2 oktober 2026. Startpunt voor Claude, Codex en andere ontwikkelaars.

## Actueel: macOS 2.0.10 (16), HUD-dictaten apart in Geschiedenis, 2 oktober

De Mac-geschiedenis opent nu op **Gesprekken**. De HUD-dictaten (`mic.mac`) staan onder **Dictaten**; **Alles** toont beide. PLAUD blijft direct bereikbaar, Microfoon en Bestanden via Filter > Bron. Home toont recente gesprekken/opnames zonder de HUD-dictaten. De bronnaam van een HUD-item is nu zichtbaar als Dictaat. Dit zijn uitsluitend weergavefilters: geen database- of CloudKit-migratie, geen verplaatsing en geen verwijdering van transcripties. Oudere bron `mic` blijft bij Gesprekken, omdat die niet betrouwbaar aan HUD of iPhone kan worden toegeschreven. Notulist (`meeting.mac`) blijft bij Gesprekken.

De eerste visuele tussenbuild 2.0.9 (15) is vervangen door de definitieve **2.0.10 (16)**. Bij openen van Geschiedenis wordt Gesprekken expliciet opnieuw gekozen; een directe verwijzing naar een HUD-item opent Dictaten. De iPhone blijft **2.0.4 (10)**. Op de huidige Production-database zijn 1.120 zichtbare HUD-dictaten en 462 overige zichtbare geschiedenisitems gemeten; notitiegekoppelde opnames blijven, zoals voorheen, bij de notitie.

Verificatie op macOS 27.0.1 / Xcode 27.0: 46 gerichte Shared-tests en 351 Mac-tests geslaagd (5 bestaande model-E2E-tests overgeslagen); iPhone Debug-simulatorbuild en Mac universal Release-build geslaagd. In de geïnstalleerde Mac-app zijn Gesprekken (462), Dictaten (1.120), Alles (1.582), Home en de filterknoppen bij 950 punten vensterbreedte zichtbaar gecontroleerd. De ondertekende en genotariseerde installatie-DMG staat in `../Releases/WhisperClip-2.0.10.dmg` (SHA-256 `5caf052ef0bb7a276b961415255c7cd77b6de345734e5ea77e92eba706b0655e`), met Production-CloudKit en een bytegelijke backuphelper. Zie `Packaging/RELEASE_2.0.10.md`.

2.0.10 is na een nieuwe volledige backup op deze privé-Mac geïnstalleerd. Back-up: `../device-backups/Niels-Mac/2026-10-02-222318-before-2010-hud-separation/`. Vóór en na de start: Production 1.593 transcripties, Development 1.536, beide 7 notities; integriteit OK, geen ontbrekende transcript-ID/tekst of notitie-ID, `settings.json` en voorkeuren ongewijzigd. **Werk-Mac nog niet geïnstalleerd of langdurig getest.** Deze weergavewijziging is geen bewijs dat de eerdere werk-Mac-opname- of crashproblemen opgelost zijn.

## Vorige versie: privé-Mac 2.0.8 (14) geïnstalleerd, 2 oktober

Niels wees erop dat op deze privé-Mac nog 2.0.6 (12) draaide. Op 2 oktober is de genotariseerde `../Releases/WhisperClip-2.0.8.dmg` daarom ook hier geïnstalleerd op dezelfde locatie, `/Applications/WhisperClip.app`. De DMG-helper stopte terecht omdat de Mac naast de gebruikte Production-geschiedenis ook een oude Development-geschiedenis heeft. Vóór de vervanging is daarom handmatig de volledige Application Support-map, voorkeuren en bestaande app gekopieerd naar `../device-backups/Niels-Mac/2026-10-02-211023-before-208-local-install/`; beide databasekopieën slagen voor `PRAGMA integrity_check`. De bestaande app gebruikte aantoonbaar `history.db` en een Production-CloudKit-entitlement; de nieuwe app gebruikt dezelfde databasevariant en entitlement. Er was geen actieve opname of herstelbestand. De oude app is normaal afgesloten en buiten `/Applications` bewaard.

De geïnstalleerde app is geopend en toont het Home-scherm met recente transcripties. Versie/build zijn in de geïnstalleerde Info.plist 2.0.8 (14), met geldige Developer ID-handtekening, notarization-ticket en Gatekeeper-acceptatie. Voor en na de start: 1.593 Production-transcripties, 7 notities en 65 `plaud.ios`-opnames; alle oorspronkelijke transcript-ID's en tekst zijn behouden, `integrity_check=ok`, uitgaande Production-syncwachtrij leeg. De oude Development-database blijft 1.536 transcripties en 7 notities bevatten. `settings.json`, de Production-accountkoppeling en voorkeuren zijn bytegelijk gebleven. Dit is een korte lokale start- en gegevenscontrole; opname met een andere microfoon, direct invoegen, urenlang gebruik en de werk-Mac blijven nog onbeproefd.

## Actueel: iPhone 2.0.4 (10), opslagtekst op opnamescherm, 2 oktober

De tekst `Bewaarde audio op dit apparaat: 0,3 MB` stond tijdens opnemen over het woordmerk heen. `RecordView` plaatste `AudioStorageStatusView` als bovenste safe-area-inset buiten de `NavigationStack`; bij aanwezige lokale audio viel die opslagregel daardoor samen met de navigatiebalk. De 0,3 MB kwam van een eerder bewaarde iPhone-microfoonopname van 13 september en zegt niets over de bewaarbeslissing voor de lopende opname. De opslagstatus blijft beschikbaar onder Instellingen > Transcriptie, maar is van het opnamescherm verwijderd. XcodeGen-project opnieuw gegenereerd; Release-build voor Niels' iPhone geslaagd met Production-CloudKit-recht, geldige ondertekening en versie 2.0.4 (10). Na een nieuwe kopie van Application Support en voorkeuren is de app met dezelfde bundle-ID geïnstalleerd zonder containerverwijdering. Back-up: `../device-backups/Niels-iPhone/2026-10-02-205746-before-204-ui-fix/`. Beide databases waren voor en na installatie integer; de Production-geschiedenis bleef 1.593 transcripties en 7 notities met dezelfde IDs en transcripttekst, Development 1.543 en 7. De iPhone-instellingen waren na installatie bytegelijk. Op 2 oktober om 21:05 is het openstaande opnamescherm op het echte toestel vastgelegd: de opslagregel is weg en het woordmerk vrij. De screenshot staat uitsluitend lokaal in `/tmp/whisperclip-iphone-after-204-open.png`.

## Actueel: iCloud-geschiedenis iPhone ↔ Mac, 2 oktober

De gebruiker zag op de Mac 0 PLAUD-opnames terwijl de iPhone nieuwe PLAUD-transcripties heeft. Oorzaak: de Mac gebruikte CloudKit Production, de oude iPhone-build Development; bovendien ontbraken `Transcript` en `Note` in het Production-schema. Na backups zijn de twee recordtypen met indexen uitgerold, is de Mac-Production-account via de bestaande samenvoegbevestiging gekoppeld en is iPhone **2.0.3 (9)** met dezelfde bundle-ID en behouden container geïnstalleerd. Een gecontroleerde migratie nam de 132 records mee die alleen in de iPhone-Development-database stonden en bood de volledige iPhone-geschiedenis opnieuw aan Production aan. **Live eindcontrole:** de iPhone- en Mac-Production-databases hebben elk 1.593 transcripties, 7 notities en 65 `plaud.ios`-opnames; beide slagen voor `PRAGMA integrity_check`. Hun transcript- en notitie-ID-verzamelingen zijn gelijk. Alle 1.543 oorspronkelijke iPhone-Development-transcript-ID's zijn behouden, zonder tekstverschillen; de oorspronkelijke notities zijn ongewijzigd. Beide uitgaande syncwachtrijen zijn leeg. De iPhone kreeg daarna de aparte layoutcorrectie 2.0.4 (10) en de privé-Mac kreeg 2.0.8 (14). De 2.0.8-DMG is ook voor de werk-Mac klaargemaakt, maar daar nog niet geïnstalleerd. Zie `ICLOUD_SYNC_DIAGNOSIS_2026-10-02.md` voor oorzaak, backups, uitvoering en beperkingen.

## Vorige versie: macOS 2.0.8 (14), microfoonkeuze en diagnostiek, 2 oktober

- In Instellingen > Algemeen kan de gebruiker de systeemstandaard of een concrete CoreAudio-invoerbron kiezen. De stabiele apparaat-UID blijft lokaal in `settings.json`; dictaat en Notulist gebruiken die bron vanaf hun volgende opname. Een ontbrekende gekozen microfoon geeft een fout in plaats van een stille terugval. De keuze van een lopende, ook gepauzeerde opname staat vast.
- Onder Stabiliteit staat `Exporteer diagnostiek`. Dit schrijft na een expliciete bestandskeuze een tekstbestand met versie, macOS-versie, geanonimiseerde logcategorieën, samplefrequenties/kanaalaantallen bij formaatfouten, startgeschiedenis en beperkte `.ips`-crashsymbolen. Ruwe logs, apparaatnamen, appnamen, audiobestanden, transcripties, accountgegevens en sleutels worden niet gekopieerd. Lees het bestand alsnog na vóór delen.
- Verificatie: 350 Mac-tests geslaagd (5 bestaande model-E2E-tests overgeslagen), 200 Core-tests geslaagd, iPhone-simulatorbuild geslaagd. De gerichte Mac-tests verifiëren dat privétekst uit de export blijft en dat een CoreAudio-invoerapparaat op deze Mac aan een `AVAudioEngine` kan worden gekoppeld. Release-build 2.0.8 (14) slaagt op macOS 27.0.1 met Xcode 27. Geen iPhone-interface gewijzigd.
- **Installatieklare, lokaal geverifieerde 2.0.8-DMG:** `../Releases/WhisperClip-2.0.8.dmg`, SHA-256 `2ed8666bf77f842c3887f57328448bb6c6d57a9cb7df49cfbe6edb95f222ae01`. De Apple Developer-licentie en Free Apps Agreement stonden op 2 oktober actief; de nieuwe app en DMG zijn met Developer ID ondertekend, door Apple geaccepteerd, gestapeld en door Gatekeeper geaccepteerd. De read-only aangekoppelde DMG bevat versie 2.0.8 (14), Production-CloudKit en een bytegelijke backuphelper. Het syncwieltje opent nu Instellingen wanneer accountkoppeling nodig is. De eerdere 2.0.7-kandidaat zonder microfoonkeuze/diagnostiek is vervangen. **Nog niet bewezen:** installatie en langer gebruik op de werk-Mac, echte hardwarewissels tijdens opname en direct invoegen in de werkapps.

## Eerdere kandidaat: werk-Mac 2.0.6 heeft nog audio-opstartfouten; 2.0.7, 2 oktober

Het onderzoek op de werk-Mac toont dat `installTap` na een hardware/client-formaatverschil nog faalt op 2.0.6 (12). De nabijgelegen herstarts bewijzen niet dat deze exceptie een nieuwe crash veroorzaakte; recente eigen crashbestanden zijn leeg en een `.ips` ontbreekt. De executable-hash komt overeen met de 2.0.6-DMG, terwijl verificatie van de geïnstalleerde appbundle op de werk-Mac faalt. De 2.0.7-broncode vervangt bij formaatverschil de engine in plaats van alleen `reset()` aan te roepen, weigert een tap zolang formaten niet overeenkomen en logt inhoudsvrije opname- en invoegdiagnostiek. 347 Mac-tests slaagden en versie 2.0.7 (13) is als Release gebouwd en lokaal met Developer ID en productie-iCloud-profiel ondertekend. **Nog geen installatieklare DMG of werk-Mac-validatie:** Apple-notarisatie wacht op een lokaal beschikbare API-sleutel of opgeslagen `notarytool`-profiel. De ondertekende kandidaat in `Packaging/dist/WhisperClip-2.0.7-13-pending-notarization/` is geen distributieversie. Zie `WORK_MAC_DIAGNOSIS_2026-10-02.md` en `MACWHISPER_REVIEW_2026-10-02.md`.

## Eerdere status: oorzaak gevonden en gedicht, macOS 2.0.6 (12), 24 september

- De crashfamilie had één oorzaak: een NSException uit `installTap` na een microfoonwissel (formaatverschil), die door een Swift-async-taak heen vloog en de concurrency-runtime kapot achterliet. Bewijs: eigen crash van 23 september plus systeemlog. Volledig beschreven in `CLAUDE_MACOS_CRASH_HANDOFF.md`.
- Reparatie: formaatcontrole met engine-reset vóór elke start, ObjC-vangnet om installTap/start (Core/ObjCExceptionCatcher, Mac en iPhone), logging in app.log. Tests groen, waaronder een test die de echte fout nabootst.
- Klaar: `Releases/WhisperClip-2.0.6.dmg`, genotariseerd. Zie `Packaging/RELEASE_2.0.6.md`. Nog niet op de werk-Mac geïnstalleerd. Het bewijs is: dagenlang draaien met microfoonwissels, en regels "AudioEngine: invoerformaat gewisseld" in app.log.
- Alles gecommit (`2e6c610` ChatGPT-werk 2.0.2 tot 2.0.5, `645e799` de reparatie).

## Historisch: structurele hoverreparatie macOS 2.0.5 (11), 23 september (was niet de oorzaak)

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
