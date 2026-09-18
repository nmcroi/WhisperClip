# WhisperClip bijwerken op Vincents iPhone

## Harde regel

Gebruik voor Vincents iPhone uitsluitend:

```sh
cd /Users/nielscroiset/Werkmappen/Development/WhisperClip/v2
./scripts/update_vincent_iphone.sh /absoluut/pad/naar/WhisperClipboardiOS.app
```

Installeer nooit rechtstreeks met `devicectl device install app`. Verwijder de
app nooit en voer geen containerreset uit. Het updatescript moet eerst volledig
slagen met de back-up en controles; bij iedere fout stopt het vóór installatie.

## Waarom dit verplicht is

Op 16 september 2026 is een Release-build over Vincents Development-build gezet.
De appcontainer bleef bestaan, maar de Release-build opende `history.db`, terwijl
zijn 10 transcripties en 3 notities in `history-dev.db` stonden. De gegevens
waren niet verwijderd, maar leken in de app verdwenen. Een gecontroleerde
Development-build herstelde de zichtbaarheid.

Dezelfde bundle-id is daarom geen voldoende bewijs dat een update dezelfde
database opent.

## Wat het script controleert

1. Het aangesloten toestel heeft Vincents lokaal geregistreerde ID in `Configs/Vincent-iPhone.udid` (uitgesloten van Git).
2. De nieuwe app heeft bundle-id `nl.nielscroiset.whisperclipboard.ios` en een
   geldige codehandtekening.
3. Vóór installatie worden Application Support en de voorkeuren gekopieerd naar
   `../device-backups/Vincent-iPhone/<tijdstip>/before/`.
4. Iedere gevonden geschiedenisdatabase krijgt `PRAGMA integrity_check`; de
   aantallen transcripties en notities worden in `manifest.txt` vastgelegd.
5. Het script bepaalt of de nieuwe build `history-dev.db` (Debug) of
   `history.db` (Release) opent. Het stopt als de andere database gegevens bevat
   en de doel-database leeg is.
6. Pas daarna installeert en opent het de app.
7. Na installatie wordt de gebruikte database opnieuw gekopieerd en gecontroleerd.

De handmatige herstelback-up van 16 september staat in
`../device-backups/Vincent-iPhone-2026-09-16-2005/`.
