# WhisperClip macOS 2.0.10 (16) — HUD-dictaten apart

Status 2 oktober 2026: `../../Releases/WhisperClip-2.0.10.dmg` is klaar voor handmatige installatie op de werk-Mac. SHA-256: `5caf052ef0bb7a276b961415255c7cd77b6de345734e5ea77e92eba706b0655e`. De iPhone-versie blijft 2.0.4 (10). De 2.0.9 (15)-tussenbuild diende uitsluitend voor lokale schermcontrole en is niet de actuele distributieversie.

## Gedrag en gegevens

- Geschiedenis opent standaard op Gesprekken. Dictaten toont alleen bron `mic.mac`; Alles toont de volledige geschiedenis. PLAUD blijft een snelle keuze; Microfoon en Bestanden staan onder Filter > Bron.
- De Home-lijst met recente gesprekken laat de HUD-dictaten weg. Binnen Geschiedenis krijgt een HUD-transcript het label Dictaat. Een directe verwijzing naar zo'n transcript opent het Dictaten-filter.
- De filter is gebaseerd op bestaande bronstrings. Oudere `mic`-items kunnen van de Mac of iPhone komen en blijven daarom bij Gesprekken; er is geen inhoudsanalyse of automatische herclassificatie. Notulist (`meeting.mac`), bestanden, PLAUD en iPhone-microfoonopnames blijven bij Gesprekken.
- Transcripties, notities, audiobestanden, bronwaarden, CloudKit-records en synchronisatie-identiteit zijn niet gemigreerd of verplaatst. Alleen de Mac-weergave is gewijzigd.

## Verificatie

- macOS 27.0.1, Xcode 27.0: 46 `HistoryStoreTests` geslaagd; de nieuwe regressietest controleert HUD-, iPhone-, legacy-, PLAUD- en bestandsbronnen, plus zoeken en aantallen. 351 Mac-tests geslaagd, 5 bestaande echte-model-E2E-tests overgeslagen. iPhone Debug-simulatorbuild en universal Mac Release-build geslaagd. `git diff --check` schoon.
- In de echte privé-Mac-app: Home, Gesprekken (462 zichtbare items), Dictaten (1.120) en Alles (1.582) gecontroleerd; bij een vensterbreedte van 950 punten passen alle vier de snelle filterknoppen. Er is geen nieuwe opname gedaan voor deze release.
- Release-app en DMG zijn met Developer ID ondertekend, door Apple geaccepteerd, gestapeld en door Gatekeeper geaccepteerd. De aangekoppelde DMG bevat versie 2.0.10 (16), Production-CloudKit, installatie-uitleg en een bytegelijke `Controleer en maak backup.command`. De lokale kopie in `Releases/` heeft dezelfde SHA-256 als het distributiemanifest.
- Deze privé-Mac is na een nieuwe 4,0 GB-back-up bijgewerkt. Beide databasevarianten bleven integer en behielden alle eerdere transcript-ID's en teksten en alle notitie-ID's; instellingen en voorkeuren bleven bytegelijk. Back-up: `../../device-backups/Niels-Mac/2026-10-02-222318-before-2010-hud-separation/`.

De werk-Mac is nog niet bijgewerkt. De al bekende instabiliteit op die Mac, langdurig gebruik, echte microfoonopnames, HUD-sneltoetsen en iCloud-uitwisseling na installatie van deze versie zijn daarmee niet opnieuw fysiek bewezen. Gebruik daar eerst de helper in de DMG; die stopt bij een onveilige databasevariant. Publicatie of automatische uitrol is niet gedaan.
