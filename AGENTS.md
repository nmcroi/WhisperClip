# Whisper Clipboard

## Project context
- Whisper Clipboard is een zelfstandige, veilige macOS-app als vervanger van Whisper Flow/Whisper Transcription — waarom: Niels wil hem aan anderen kunnen geven en op zijn werkcomputer draaien, dus geen shortcuts of privacygevoelige afhankelijkheden — wanneer: bij elke architectuur-, distributie- of privacykeuze in dit project.

## Vincent iPhone
- Installeer nooit rechtstreeks een WhisperClip-update op Vincents iPhone. Gebruik altijd `v2/scripts/update_vincent_iphone.sh`; dit script maakt en controleert eerst een lokale back-up. Verwijder de app of haar container nooit. Zie `v2/VINCENT_IPHONE_UPDATE.md`.

## Actuele overdracht
- Lees eerst `v2/CURRENT_STATUS.md` en de daarin genoemde reviews. Oudere startprompts en backlogs beschrijven historische plannen; gebruik ze niet als actuele opleverstatus. De actieve bron staat in `v2/`.

## Versies bij oplevering
- Iedere gewijzigde appbuild die aan Niels, Vincent of een andere Mac wordt geleverd krijgt een nieuw buildnummer. Een herkenbare gebruikersupdate krijgt ook een hoger zichtbaar versienummer. Hergebruik nooit hetzelfde versie/build-paar voor verschillende geleverde binaries.
- `v2/project.yml` is de bron: werk zowel globale waarden als de relevante target-override bij, genereer het Xcode-project en controleer de waarden in de gebouwde app. Verhoog niet onbedoeld de versie van het andere platform. Noteer versie, build, wijzigingen, test-OS en distributiestatus in `v2/CURRENT_STATUS.md`.
