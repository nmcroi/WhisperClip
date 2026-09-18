# WhisperClip — actuele overdracht

Bijgewerkt: 18 september 2026. Startpunt voor Claude, Codex en andere ontwikkelaars.

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
