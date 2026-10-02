# Werk-Mac: audio-opstart en direct invoegen, 2 oktober 2026

Status: **2.0.6 (12) is op de werk-Mac niet afdoende bewezen; de audio-opstartfout treedt daar nog op.** De aanpassing hieronder is lokaal in broncode en nog niet op de werk-Mac geïnstalleerd of langdurig getest.

## Bewijs van de werk-Mac

De gebruiker leverde een onderzoek uit een sessie op die Mac aan. Daarop draait macOS 27.0 (26A428) en `/Applications/WhisperClip.app` 2.0.6 (12). In `app.log` komen na een hardware/client-formaatverschil nog `Failed to create tap due to format mismatch`-exceptions voor, onder meer op 30 september en 1 en 2 oktober. Een volgende appstart ligt soms seconden later, maar dat bewijst geen crashoorzaak. De recente `crash-*.txt`-bestanden zijn leeg en er is geen recente `.ips` gevonden. De werk-Mac meldde ook dat `codesign --verify` faalt. Dit is een afzonderlijk installatieprobleem totdat de gewijzigde component is gevonden.

De SHA-256 van de werk-Mac-executable is `6f393ca977a9614b4e1dd9fce7dbf6e48a30dd6f212ba4e4123363611fc5df46`. Deze is **gelijk** aan de executable in de 2.0.6-DMG én de hier geïnstalleerde app; beide laatste appbundles slagen lokaal voor `codesign --verify --deep --strict`. De ondertekeningsfout op de werk-Mac betekent dus niet dat een andere executable draait, maar kan nog wijzen op een veranderd ander bundlebestand of een lokaal verificatieprobleem. Controleer op de werk-Mac met volledige `codesign`-uitvoer en een bestandsvergelijking met de DMG; wijzig of verwijder geen appdata.

## Codeoorzaak en wijziging

In `AudioEngine.tapFormatAfterHardwareCheck()` riep 2.0.6 bij een mismatch `AVAudioEngine.reset()` aan en probeerde daarna opnieuw `installTap`. Volgens Apple's documentatie reset `reset()` de toestand van audionodes; na een hardwareconfiguratiewijziging blijven eerdere verbindingsformaten gekoppeld. De werk-Mac-log laat zien dat reset gevolgd kon worden door dezelfde mismatch. De broncode maakt nu bij mismatch een nieuwe `AVAudioEngine` aan, controleert beide formaten opnieuw en installeert **geen** tap wanneer ze nog verschillen of ongeldig zijn. Een gevangen Objective-C-exceptie maakt eveneens een nieuwe engine aan. Hervatten installeert na een succesvolle enginewissel de configuratie-observer opnieuw. Opstartvoorbereiding vangt Objective-C-excepties ook af. Dit voorkomt dat een *bekende, vooraf zichtbare* mismatch toch in `installTap` belandt; het bewijst nog niet dat elke hardwarewissel wordt opgevangen.

De app logt voortaan zonder transcriptinhoud: versie/build en pid bij start, dictaat-ID, start/stop en duur, gekozen en actieve doelapp met pid, actuele Toegankelijkheidsstatus, invoegbeslissing en het audioapparaat-ID bij een formaatprobleem. Dit maakt de volgende klembord-only gebeurtenis te onderscheiden van een mislukte opname. `InsertionPolicy` kiest bewust voor klembord-only bij ontbrekende toestemming, geen doelapp, een gewijzigde voorgrond-app of een uitgesloten app; vóór deze wijziging verdween die reden in de normale flow uit de logs.

## Wat de huidige signalen niet bewijzen

- Een leeg `crash-*.txt`-bestand is verwacht: `LaunchHealth.installCrashHandlers()` maakt het bij **elke start** vooraf aan om een bestandsdescriptor voor de signaalhandler klaar te hebben. Het wordt alleen gevuld wanneer de handler werkelijk schrijft.
- `launch-history.json` met `schoon` betekent uitsluitend dat bij de volgende start geen `running.marker` meer aanwezig was. Dat onderscheidt een gewone stop van een proces dat bijvoorbeeld een SIGTERM-handler doorliep; het is geen volledige stabiliteitsmeting.
- De toegestane Toegankelijkheid en ingeschakelde Direct invoegen op het moment van het werk-Mac-onderzoek verklaren een eerdere klembord-only gebeurtenis niet. De status op het foutmoment en de doelapp ontbraken.
- De oudere `swift_task_isCurrentExecutor`-crashes en de recente audio-opstartfouten zijn waarschijnlijk gerelateerd, maar de aangeleverde tijdstippen alleen bewijzen geen nieuwe post-2.0.6-crashroute.

## Verificatie en open controles

Op de privé-Mac met macOS 27 en Xcode 27 slaagde de Mac-testsuite op 2 oktober:

```sh
xcodebuild test -project v2/WhisperClipboard.xcodeproj \
  -scheme WhisperClipboard -destination 'platform=macOS' \
  -derivedDataPath /tmp/whisperclip-codex-20261002 CODE_SIGNING_ALLOWED=NO
```

347 tests uitgevoerd, 0 fouten, 5 E2E-tests voor echte modellen overgeslagen. De bestaande `AudioTapExceptionTests` test met een echte `AVAudioEngine` dat een formaatfout door het Objective-C-vangnet een Swift-fout wordt. Deze suite simuleert **geen** werk-Mac-microfoonwissel en geen uur lang opnemen of direct plakken in een andere app. `git diff --check` was schoon.

Daarna is versie 2.0.7 (13) als Release gebouwd op de privé-Mac. De appbundel is met de aanwezige Developer ID en productie-iCloud-profiel ondertekend; `codesign --verify --deep --strict` slaagt. De kandidaat staat uitsluitend in `Packaging/dist/WhisperClip-2.0.7-13-pending-notarization/`. De zeven tests voor de backuphelper slagen. **Er is nog geen installatieklare DMG:** voor Apple-notarisatie ontbreekt lokaal een bruikbare App Store Connect API-sleutel of opgeslagen `notarytool`-profiel. De kandidaat mag daarom niet als distributieversie worden aangemerkt.

Test op de werk-Mac na een veilige update minstens een uur met herhaalde opnames, microfoon- en dockwissels, pauze/hervatten en doelappwissels. Vergelijk op het foutmoment de nieuwe `app.log`-regels met de fase in `running.marker`; verzamel een echte backtrace of `.ips` indien de app nog crasht. De werk-Mac staat onder beheer: vraag geen schermopname- of andere extra privacyrechten aan en log geen transcriptinhoud.

Bronnen: het aangeleverde werk-Mac-onderzoek; `AudioEngine.swift`, `InsertionService.swift`, `DictationController.swift` en `LaunchHealth.swift`; Apple-documentatie voor [`AVAudioEngine.reset()`](https://developer.apple.com/documentation/avfaudio/avaudioengine/reset%28%29) en [`AVAudioEngineConfigurationChangeNotification`](https://developer.apple.com/documentation/avfaudio/avaudioengineconfigurationchangenotification).
