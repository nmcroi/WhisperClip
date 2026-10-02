# WhisperClip macOS 2.0.11 (17) — rustige transcriptdetails

Status 2 oktober 2026: `../../Releases/WhisperClip-2.0.11.dmg` is een lokaal gecontroleerde, genotariseerde installatie-DMG. SHA-256: `a147591bf537bc3a36a2b38c826f52c52ff4182e62de5b2d8f631ba353eab320`. De privé-Mac is bijgewerkt; de werk-Mac nog niet. De iPhone blijft 2.0.4 (10).

## Gedrag

- De losse verwijderknoppen staan standaard niet meer na elke zin of spreekbeurt. **Meer > Fragmenten verwijderen** toont ze alleen zolang die stand actief is. Een toelichting en **Gereed** maken de stand zichtbaar en afsluitbaar.
- Een klik op zo'n knop opent de bestaande bevestiging vóór er tekst of audio wordt aangepast. Het gewone **Bewerk** blijft de editor voor de hele tekst. Bij een ander transcript of starten van die editor sluit de fragmentstand.
- Geen hoverevents toegevoegd. De wijziging raakt alleen de Mac-weergave; transcripties, notities, audiobestanden en CloudKit-gegevens zijn niet gemigreerd.
- De installatie-uitleg in de DMG krijgt versie en build nu automatisch uit de gebouwde app; een vorige pakketpoging met verouderde uitleg is vervangen door de definitieve DMG hierboven.

## Verificatie en grens

- macOS 27.0.1, Xcode 27.0: 346 Mac-tests geslaagd, 5 bestaande model-E2E-tests overgeslagen. `git diff --check` schoon. De universele Release-app bevat arm64 en x86_64 en toont 2.0.11 (17).
- De definitieve DMG en de app erin slagen voor codesign, notarization-ticket en Gatekeeper. De read-only aangekoppelde DMG bevat de juiste versie in app en LEESMIJ, Production-CloudKit en een bytegelijke backuphelper. De backuphelper slaagt voor zeven geïsoleerde testsituaties.
- Deze privé-Mac is pas na normaal afgesloten opnames bijgewerkt. Volledige backup: `../../device-backups/Niels-Mac/2026-10-02-230137-before-2011-fragment-controls/`. Production en Development slagen vóór en na installatie voor `PRAGMA integrity_check`; respectievelijk 1.600 en 1.536 transcripties en elk 7 notities, zonder ontbrekende oorspronkelijke ID's of gewijzigde transcripttekst. Instellingen en voorkeuren bleven bytegelijk. De geïnstalleerde app start, toont Home en is Gatekeeper-geaccepteerd.
- De nieuwe fragmentstand is nog niet met klikken in de draaiende app beproefd; de bestaande tests zijn geen UI-tests voor deze stand. Er is geen nieuwe opname gedaan met 2.0.11. Werk-Mac-installatie, langdurig gebruik en de eerdere werk-Mac-crash blijven open voor praktijkcontrole.

Publicatie, automatische uitrol en iPhone-installatie zijn niet uitgevoerd.
