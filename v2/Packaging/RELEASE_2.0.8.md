# WhisperClip macOS 2.0.8 (14) — installatie-DMG gereed

Status 2 oktober 2026: `../../Releases/WhisperClip-2.0.8.dmg` is klaar voor handmatige installatie op de werk-Mac. SHA-256: `2ed8666bf77f842c3887f57328448bb6c6d57a9cb7df49cfbe6edb95f222ae01`. De eerdere notarisatiefout HTTP 403 trad op vóór de nieuwe aanvraag; bij accountinspectie waren de Developer Program License Agreement en Free Apps Agreement actief. De nieuwe aanvraag voor app en DMG is door Apple geaccepteerd. De vorige 2.0.7 (13)-kandidaat bevat de onderstaande functies niet.

Dezelfde DMG is inmiddels ook op Niels' privé-Mac geïnstalleerd. Zijn Production-geschiedenis, Development-geschiedenis, instellingen en iCloud-accountkoppeling zijn vooraf geback-upt; daarna zijn versie 2.0.8 (14), start, recente geschiedenis, oorspronkelijke Production-IDs/tekst, 7 notities, 65 iPhone-PLAUD-opnames, lege syncwachtrij, ondertekening, notarization en Gatekeeper gecontroleerd. Back-up: `../../device-backups/Niels-Mac/2026-10-02-211023-before-208-local-install/`. De werk-Mac is nog niet bijgewerkt of langdurig getest.

## Wijzigingen

- Herstelt de audio-opstart na een hardware/client-formaatverschil door een nieuwe `AVAudioEngine` te maken en geen tap te installeren zolang de formaten afwijken. Voeg inhoudsvrije opname- en invoegdiagnostiek toe. Dit is nog niet langdurig op de werk-Mac bewezen; zie `../WORK_MAC_DIAGNOSIS_2026-10-02.md`.
- In Instellingen > Algemeen: kies de systeemstandaard of een CoreAudio-microfoon. De stabiele apparaat-UID staat lokaal in `settings.json`. De keuze geldt bij de volgende dictaat- of Notulist-opname en verandert geen lopende sessie. Een verdwenen gekozen apparaat veroorzaakt een duidelijke fout.
- In Instellingen > Algemeen > Stabiliteit: `Exporteer diagnostiek`. Dit schrijft na een expliciete bestandskeuze een tekstbestand met vaste technische categorieën, formaatwaarden en beperkte crashinformatie. De export kopieert geen ruwe logs, paden, appnamen, audio, transcripties of sleutels. De gebruiker wordt gevraagd het bestand voor delen te controleren.
- Het syncwieltje opent Instellingen wanneer de productiegeschiedenis eerst aan het actuele iCloud-account moet worden gekoppeld; een gewone synchronisatie is daarvoor onvoldoende. De Mac-knop en Release-DMG zijn met deze wijziging opnieuw gebouwd.
- De macOS-wijzigingen passen de iPhone-interface niet aan; de afzonderlijke iPhone-correctie 2.0.3 (9) is geïnstalleerd. De live uitwisseling met de huidige privé-Mac is bevestigd: beide Production-databases bevatten 1.593 transcripties en 7 notities, waaronder 65 iPhone-PLAUD-opnames; beide uitgaande wachtrijen zijn leeg.

## Verificatie tot nu toe

- Privé-Mac: macOS 27.0.1, Xcode 27.0. Mac-testsuite: 350 tests, nul fouten, vijf bestaande echte-model-E2E-tests overgeslagen. Vier gerichte tests voor microfoonselectie en private diagnostiek slagen, inclusief het koppelen van een invoerapparaat aan `AVAudioEngine` en controleren dat `prepare()` deze keuze behoudt.
- Core: 200 tests geslaagd, inclusief migratie en JSON-roundtrip van de nieuwe microfoonvoorkeur.
- iPhone: Debug-simulatorbuild geslaagd na wijziging van het gedeelde instellingenmodel.
- Mac: Release-build geslaagd; Info.plist gecontroleerd op 2.0.8 (14). Zeven geïsoleerde backuphelper-scenario's slagen. `git diff --check` schoon.
- De opnieuw gebouwde Release-app en DMG in `Packaging/dist/WhisperClip-2.0.8-14-production-schema-20261002/` zijn met Developer ID ondertekend. `notarytool` accepteerde beide uploads; beide tickets zijn gestapeld. De read-only aangekoppelde DMG is gecontroleerd op versie 2.0.8 (14), Production-CloudKit-entitlement, `codesign --verify --deep --strict`, `stapler validate`, Gatekeeper-acceptatie, installatie-uitleg en bytegelijke backuphelper. De SHA-256 van de kopie in `Releases/` komt overeen met het manifest.
- Op de privé-Mac liep de productie-CloudKit-wachtrij na schema-uitrol en appherstart van 50 naar 0; de 50 lokale transcripties bleven intact. Daarna uploadde de bijgewerkte iPhone zijn geschiedenis en haalde de privé-Mac die op: 1.593 gelijke transcript-ID's, 7 gelijke notitie-ID's en lege uitgaande wachtrijen aan beide kanten. De data-uitwisseling is dus live gecontroleerd, maar niet met de nieuwe DMG op de werk-Mac.
- Niet gedaan: echte opname met een tweede microfoon, werk-Mac-installatie, urenlang gebruik en direct invoegen in de werkapps.

Op de werk-Mac: open de DMG, voer eerst `Controleer en maak backup.command` uit, en volg `LEESMIJ.txt`. De helper stopt bij een onduidelijke databasevariant of ontbrekende backup. De API-sleutel en het Developer ID-certificaat waren lokaal aanwezig; hun inhoud staat niet in deze DMG of dit rapport.
