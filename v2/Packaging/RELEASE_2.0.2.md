# WhisperClip 2.0.2 — DMG voor de werk-Mac

Oplevering 18 september 2026. Definitief bestand: `../../Releases/WhisperClip-2.0.2.dmg` (19.254.574 bytes). SHA-256 ernaast. Appversie 2.0.2, build 7, Release. De lokaal eerder geteste Debug-kandidaat blijft build 6; verschillende binaries delen dus niet hetzelfde versie/build-paar.

## Gecontroleerd

- Release-build geslaagd met Xcode 26.6 op macOS 27.0. Mach-O bevat arm64 en x86_64; praktische appcontrole alleen op Apple silicon.
- 334 Mac-tests en HUD/sneltoets/sluiten/heropenen op macOS 27 uit de voorafgaande ronde: `../ReviewScreenshots/2026-09-18-macos27/`. Die runtimecontrole gebruikte Debug build 6; de Release-binary is niet over de persoonlijke Debug-installatie heen gezet.
- App ondertekend met Developer ID; hardened runtime, geen get-task-allow. Provisioning profile geldt voor alle apparaten, is geldig en bevat het daadwerkelijk gebruikte ondertekeningscertificaat.
- Production CloudKit-rechten en dezelfde bundle-ID. Normale Release-database `history.db`; ontwikkelvariant `history-dev.db` wordt niet stilzwijgend overgenomen. Dit bewijst geen live iCloud-uitwisseling of Production-schemawerking.
- App en definitieve DMG afzonderlijk door Apple geaccepteerd. Eerst app gestapeld, daarna DMG gemaakt; dus ook de app binnen de DMG heeft haar ticket.
- `hdiutil verify`: geslaagd. Read-only aangekoppelde DMG: Info.plist 2.0.2/7, `codesign --verify --deep --strict`, `stapler validate` en `spctl --assess --type execute`: geslaagd; verdict `accepted`, `source=Notarized Developer ID`.
- DMG zelf: stapler en Gatekeeper open-assessment geslaagd.
- Installatie-uitleg en back-uphulp in de definitieve DMG bytegelijk aan de bron. Geen persoonlijke databases/opnames of private sleutelbestanden in de app.
- Zeven geïsoleerde controles back-uphulp: gewone Release, Development-rechten, alleen ontwikkelgeschiedenis, beide databases gevuld, alleen ontwikkelnotities, corrupte database en dubbele installatie. Alle geslaagd. Alleen gewone Release gaat door naar backup; probleemgevallen stoppen zonder wijzigingen.

## Installeren

Stop op de werk-Mac WhisperClip met Cmd-Q, open de DMG en voer eerst `Controleer en maak backup.command` uit. Die wijzigt geen app/database. Als deze slaagt: vervang de oude app op dezelfde locatie met de app uit de DMG. Bij een stopmelding niet doorgaan. Geen app/container verwijderen en geen nieuwe geschiedenis initialiseren als een bestaande variant niet klopt.

De oude lokaal beschikbare 2.0.1-DMG was een Release met alleen microfoonrecht, zonder CloudKit-entitlements. Dit is onderzocht; welke binary daadwerkelijk op de werk-Mac staat is nog niet rechtstreeks vastgesteld. De back-uphulp controleert daarom ter plaatse en stopt bij ontwikkelgegevens of onduidelijke dubbele installatie.

## Reproduceerbaarheid en grenzen

Nieuwe packager: `package_work_mac.py`; instructies in `RELEASING.md`. Uitvoer/notariseringsresultaten en manifest lokaal onder `dist/WhisperClip-2.0.2-7-distribution/`. Definitieve uitgiftekopie onder `../../Releases/`. Niet publiceren via GitHub Releases/Sparkle/App Store zonder nieuwe opdracht.

Niet fysiek getest: werk-Mac, diens externe monitoren/schaal/Dock, bedrijfsbeleid, Intel en live iCloud. De open reviewbevindingen IP-03/MAC-04/MAC-05 uit de bestaande reviews zijn hiermee niet opgelost.
