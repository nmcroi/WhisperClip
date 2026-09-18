# WhisperClip iPhone — reparatie en gerichte review, 17 september 2026

WhisperClip is een native SwiftUI-app voor lokale transcriptie, notities, vergaderingen en optionele iCloud-synchronisatie. De onderzochte opslag- en schermtests slagen. De meest concrete gevonden vertrager is gerepareerd: Geschiedenis deed bij iedere hertekening een synchrone databaselezing en een dure datumsortering. De native tabbar met bubbel is behouden. Ook het ongevraagd opnieuw inschakelen van iCloud in de speciale Development-build is gerepareerd.

Dit is een gerichte review van de iPhone-schermen en hun gedeelde opslag-, herstel-, sync- en AI-code, geen volledige audit van alle functionaliteit of dependencies. De fysieke hapering op Niels' iPhone is in deze ronde niet geprofileerd. Er is niets op een echte iPhone geïnstalleerd, gepubliceerd of naar App Store Connect geüpload.

## Werkbasis en architectuur

- Map: `/Users/nielscroiset/Werkmappen/Development/WhisperClip/v2`.
- Branch: `werk/augustus-2026`; commit: `8f99db0479f0718adb3327e4ada55e34b0daffc2`.
- Er waren al veel lokale wijzigingen, onder meer aan audio-opslag, synchronisatie en schermen. Deze zijn behouden. Het rapport beoordeelt de actuele werkboom, niet alleen de genoemde commit.
- Xcode-project `WhisperClipboard.xcodeproj`, configuratiebron `project.yml`, Swift 6 met strikte concurrency. iOS-doel 17.0; Mac-doel 26.0. Gedeelde Swift Packages Core en WhisperShared; GRDB/SQLite/FTS5 en FluidAudio/Parakeet. Geen webview of eigen server in de onderzochte iPhone-route.
- Entrypoint `WhisperClipboardiOSApp` → `ContentShell` → native `TabView`: Opnemen, Notulist, Notities, Geschiedenis. `AppModel` bewaart gedeelde voorkeuren en services; `RecordController` beheert opname en afronding.
- Lokale transcriptie via Parakeet; optionele tekstverwerking via eigen providersleutels voor Anthropic/OpenAI/Gemini. PLAUD-import is een aanvullende Personal-functie. iCloud gebruikt CloudKit-private database, met accountkoppeling en aparte sync-statusbestanden.
- Onvervangbare gegevens: transcripties, notities, lokaal bewaarde audio en instellingen. Audio blijft lokaal; tijdelijke en permanente audio hebben backup-uitsluiting. Providersleutels staan in Keychain. Dit is een app voor dagelijks gebruik door Niels en Vincent, geen wegwerpprototype.
- Vastgelegd gewenst gedrag: native bubbel behouden, knoppen bereikbaar, bewaren optioneel, notitieopnames niet los in Geschiedenis, bestaande gegevens behouden. Hieronder zijn implementatiebevindingen en suggesties apart gehouden.

## Bevindingen op prioriteit

### IP-01 — Hoofdthread geblokkeerd door geschiedeniswerk — P1, performance, gerepareerd

**Bevestigd codepad en gemeten deelbewerking; de koppeling met iedere fysieke bubbelhapering is nog een hypothese.**

Vóór deze reparatie riep `listBody` bij elke render `fetch()` aan. Die las en decodeerde tot 5.000 volledige transcripties synchroon en sorteerde ze met `TranscriptEntry.timestamp` in iedere vergelijking. `timestamp` maakt telkens ISO8601DateFormatter-instanties aan. Dit werk draaide op de UI-thread en was bereikbaar bij het openen en hertekenen van Geschiedenis.

Bewijs: de behouden modelimplementatie staat in `Packages/Core/Sources/Core/Model/TranscriptEntry.swift:66`; de gerepareerde route staat in `WhisperClipboardiOS/History/HistoryListiOSView.swift:55`, `:551` en `Packages/Shared/Sources/WhisperShared/HistoryStore.swift:876`. Een geoptimaliseerde synthetische benchmark met de echte modeltypes en 1.000 reeds gesorteerde entries mat **0,5506 seconde** voor alleen de oude, overbodige sortering op deze Mac. Dat is geen iPhone-framemeting of totale schermlaadtijd.

Oplossing: asynchrone GRDB-snapshot; resultaat in view-state; vernieuwen op query/filter/revision; bestaande databasevolgorde gebruiken voor nieuwste/oudste. Geen sprekertelling als het sprekersfilter uit staat. Eén record ophalen voor een detailroute in plaats van alle records. Een geannuleerde zoekactie kan het nieuwere resultaat niet overschrijven. Bij een leesfout blijft de vorige snapshot zichtbaar en verschijnt de fout.

Verificatie: iOS-build, gedeelde snapshottests en vijf bestaande UI-tests geslaagd. De eerder aangebrachte warm-engine-guard in `ParakeetEngine.swift:175` is behouden. Nog nodig: Instruments-profiel op het echte toestel tijdens opnemen en tabwisselen. Naam- en sprekersfilters doen nog eenmalig verwerking op de hoofdthread; bij zeer grote collecties blijft verdere meting relevant.

### IP-02 — iCloud werd na uitzetten opnieuw aangezet — P1, privacy, gerepareerd

**Bevestigde bug in de speciale `WHISPERCLIP_ICLOUD_DEVELOPMENT`-build.**

In de initializer stond een onvoorwaardelijke `UserDefaults.standard.set(true, ...)`. Daardoor verloor een expliciete uitschakeling haar werking na herstart; bij een reeds gekoppeld account kon sync opnieuw starten.

Kleinste reparatie: die overschrijving verwijderen en de bewaarde keuze lezen, met standaard uit. Actuele locatie: `WhisperClipboardiOS/Model/AppModel.swift:255–263`. Gewone Release-builds blijven volgens de bestaande distributiekeuze uitgeschakeld; dat is niet als bug aangemerkt.

Verificatie: nieuwe UI-test `testICloudOptOutSurvivesRelaunch` zet aan en uit, herstart zonder commandoregeloverride en controleert uit. Uitgevoerd met de speciale Development-compilatievlag: **geslaagd**. Geen echt iCloud-account gebruikt; werkelijke netwerkstilte op fysieke hardware is niet gemeten.

### IP-03 — Databasewijziging en sync-wijzigingenbestand zijn niet atomair — P1, betrouwbaarheid, open

**Bevestigd vanuit de opslagvolgorde; de fout is niet op productiegegevens opgewekt.**

`HistoryStore.swift:202–214` commit bijvoorbeeld hernoemen eerst in SQLite en roept daarna `emit` aan. `HistorySyncEngine.swift:383–390` probeert pas dan het afzonderlijke journal te schrijven. Bij schrijffalen verschijnt een foutstatus, maar is de databasewijziging al definitief en ontbreekt een duurzaam opnieuw te proberen item. Na een crash of herstart kan vooral een verwijdering niet uit de resterende rijen worden afgeleid. De eenmalige seed (`HistorySyncEngine.swift:407–435`) repareert dit niet voor een account dat al eerder gesynchroniseerd heeft.

Daarnaast behandelt `HistoryChange.swift:152–154` een onleesbaar of beschadigd journal als leeg. Een volgende succesvolle append kan de eerder wachtende wijzigingen vervangen. Deze gevallen zijn één finding omdat dezelfde aparte, niet-transactionele sync-wachtrij de oorzaak is.

Gevolg: een lokale wijziging kan op andere apparaten ontbreken; dit bewijst niet dat dit de oorzaak was van de eerdere ontbrekende PLAUD-opnames.

Passende oplossing: sync-opdrachten/tombstones in dezelfde SQLite-transactie als de gebruikerswijziging vastleggen en na bevestiging opruimen, met een nieuwe migratie. Beschadigde bestaande journals expliciet melden en behouden bij overname. Dit is een aparte opslagwijziging die niet ongemerkt in de UI-reparatie is meegenomen. Bestaande opslagtests bewijzen dit herstelgat niet afgedekt. Nodig: foutinjectie op de grens databasecommit/journal, herstart en herhaalde levering zonder duplicaten.

### IP-04 — Geschiedenis kon meer dan 5.000 opnames niet tonen — P2, correctheid, gerepareerd

**Bevestigde codegrens.** De oude view las maximaal 5.000 rijen, maar de teller telde de hele database. Oudere opnames konden daardoor zonder actieve zoekopdracht ontbreken; filters zagen slechts die deelverzameling.

De nieuwe snapshot in `HistoryStore.swift:876–881` heeft geen impliciete limiet en leest teller en rijen binnen één databaselezing. Regressietest `testAsyncSnapshotDoesNotTruncateLargeHistory` vult een geïsoleerde database met 5.001 records en controleert dat alle 5.001 terugkomen. De tweede nieuwe test controleert tijdzones, zoeken, gewijzigde gegevens en uitsluiting van notitieopnames. Geslaagd. Voor uitzonderlijk grote archieven blijft paginering een mogelijke latere verbetering om geheugen te sparen.

### IP-05 — Updatecontrole herkent niet iedere verkeerde databasevariant — P2, updatebetrouwbaarheid, open

**Bevestigde beperking van de controle, geen nieuw aangetoond gegevensverlies.** `HistoryStore.swift:111–125` kiest verschillende databasebestanden voor Debug en Release. `scripts/update_vincent_iphone.sh:90–94` blokkeert een verkeerde variant alleen als de doeldatabase leeg is. Als beide bestanden inhoud hebben, kan een andere selectie zichtbaar worden zonder dat deze controle ingrijpt.

De backupregel en het herstelincident staan in `VINCENT_IPHONE_UPDATE.md`. Het script is alleen gelezen, niet uitgevoerd. Er zijn geen gebruikersdatabases geopend of gewijzigd in deze review.

Kleinste passende vervolgstap: vóór een update de werkelijk gebruikte variant vaststellen; bij twee gevulde databases en een variantwissel stoppen totdat een gecontroleerde migratie is voorbereid. Aantallen alleen bewijzen geen gegevensgelijkheid. Test dit met twee tijdelijke databases, ook als beide niet leeg zijn. De huidige scheiding zomaar opheffen zou testisolatie en gegevensbehoud juist riskeren.

## Hypotheses en optionele verbeteringen

- De overbodige sortering is aantoonbaar traag, maar opname-ticks, CoreML-opstart, brede AppModel-hertekeningen en de iOS-glasanimering kunnen ook meespelen. Zonder fysiek Time Profiler/Hangs-profiel is hun aandeel onbekend.
- P3, toegankelijkheid: bij Accessibility XXXL kapt de lege Notities-pagina de lange hulpzin af (`NotesListiOSView.swift:128–146`). De opnameknop blijft bereikbaar, bevestigd in screenshot en test. Een scrollbare lege toestand is een kleine optionele verbetering. Het modeldownloadscherm is al scrollbaar; een deels zichtbare tekst in de Duitse screenshot bewijst daar geen onbereikbare knop.
- Geen vastgestelde exploiteerbare kwetsbaarheid in deze steekproef. Er is geen volledige secrets-, dependency-advisory- of privacycompliance-audit uitgevoerd; dus ook geen verklaring van volledige veiligheid.

## Onderzochte controles en beperkingen

Statisch gevolgd: opname → transcriptieresultaat → `commitRecording` → audio bewaren/opruimen; herstel bij ontbrekende notitie; audio-export en conversiefouten; transactioneel bulkverwijderen/samenvoegen; migraties; private CloudKit-accountbinding; sleutels en AI-requestopbouw; PLAUD-import. Modeloutput wordt in de onderzochte AI-route als tekst verwerkt, niet als uitvoerbare opdracht. Providersleutels zijn gebruikerssleutels in Keychain, geen gebundelde beheerderssleutels. AI-requests gebruiken HTTPS en providersleutels in headers; streamingtaken hebben annulering. Deze observaties zijn geen penetratietest van de externe diensten.

Opslagtests gebruiken in-memory databases en tijdelijke bestanden. Tests voor volle schijf injecteren een schrijffout; ze vullen geen echte schijf. Crashgevallen simuleren onderbroken opslagstappen; zij beëindigen geen echte iPhone tijdens een opname. De audio-exporttest gebruikt synthetische audio. UI-tests draaien zonder gedownload spraakmodel: zij bewijzen layout, instellingen en opgeslagen-audioacties, niet de kwaliteit of snelheid van echte transcriptie.

## Uitgevoerde tests

Omgeving: macOS 26.5.1, Xcode 26.6 (17F113), Swift 6-projectmodus; geïsoleerde simulator “WhisperClip Audio Review”, iPhone 17 Pro / iOS 26.5.

| Controle | Status | Resultaat en beperking |
|---|---|---|
| Core-unit-tests | Geslaagd | 199 tests / 17 suites. Eerste poging geblokkeerd door verplaatste oude compiler-cache; nieuwe scratch-map loste dit op, geen appbug. |
| Gedeelde opslagtests | Geslaagd | 81 tests, 0 fouten. Inclusief twee nieuwe snapshottests, migratie, herstel, rollback, retentie, remote deletion en M4A-export. |
| iOS-simulatorbuild | Geslaagd | Debug, normale signingconfiguratie; geen bewijs voor fysieke opnamekwaliteit. |
| Bestaande iPhone-UI-suite | Geslaagd | 5 tests, 0 skips: native tabs/Notities-knop, audio-instelling, reset/Notulist, afspelen/export/audio verwijderen, NL/EN/DE licht/donker/grote tekst. |
| iCloud-opt-out na herstart | Geslaagd | 1 extra test, 0 skips, met `WHISPERCLIP_ICLOUD_DEVELOPMENT`; simulator zonder echt account. |
| Visuele inspectie | Uitgevoerd | Native Notities-tab en Duitse opname/onboarding bij grote tekst bekeken; geen volledige visuele inspectie van alle schermtoestanden. |
| Sorteerbenchmark | Uitgevoerd | 1.000 fictieve entries, 0,5506 s oude sortering; databasevolgorde behouden circa 0,000003 s. Geen complete scherm- of toestelbenchmark. |
| `git diff --check` | Geslaagd | Geen whitespacefouten in de werkboom. |
| Echte iPhone: opname, achtergrond, lock, onderbreking, lange opname, bubbel-FPS | Niet uitgevoerd | Nog fysieke controle nodig. |
| Live iCloud/PLAUD en AI-providers | Niet uitgevoerd | Geen accountdata verstuurd of betaalde provideracties gestart. |
| Volledige Mac-appsuite, iPad, iOS 17-runtime, VoiceOver | Niet uitgevoerd | Buiten de geteste simulatorconfiguratie. |
| Dependency-advisories en volledige secrets-scan | Niet uitgevoerd | Geen claims over actuele kwetsbaarheidsvrijheid. |

Reproduceerbare opdrachten, vanuit `v2`:

```sh
swift test --package-path Packages/Core --scratch-path /tmp/WhisperClipCoreReview20260917
swift test --package-path Packages/Shared
xcodebuild -quiet -project WhisperClipboard.xcodeproj -scheme WhisperClipboardiOS -configuration Debug -destination 'generic/platform=iOS Simulator' build
python3 scripts/seed_audio_review.py 17F0E4EA-1A2A-478D-A8E5-96624C2453E8
xcodebuild -quiet -project WhisperClipboard.xcodeproj -scheme WhisperClipAudioReview -destination 'platform=iOS Simulator,id=17F0E4EA-1A2A-478D-A8E5-96624C2453E8' -resultBundlePath /tmp/WhisperClipReview20260917.xcresult test
xcodebuild -quiet -project WhisperClipboard.xcodeproj -scheme WhisperClipAudioReview -destination 'platform=iOS Simulator,id=17F0E4EA-1A2A-478D-A8E5-96624C2453E8' 'OTHER_SWIFT_FLAGS=$(inherited) -DWHISPERCLIP_ICLOUD_DEVELOPMENT' -only-testing:WhisperClipboardiOSUITests/AudioUITests/testICloudOptOutSurvivesRelaunch -resultBundlePath /tmp/WhisperClipSyncOptOut20260917.xcresult test
```

De eerste UI-run had vijf tests; de zesde is daarna toegevoegd en apart onder de relevante compilatievlag uitgevoerd. Gebruik bij herhaling nieuwe resultBundlePath-mappen. Het seed-script is vooraf gelezen en weigert andere simulatornamen; het maakt uitsluitend een synthetische fixture. Projectinstellingen, signinginstellingen en dependencies zijn niet gewijzigd.

Bewijsbestanden: `ReviewScreenshots/2026-09-17-iphone/` bevat twee bekeken screenshots, beide testresultaatsamenvattingen en de benchmarkbron. De volledige xcresults en logs staan tijdelijk onder `/tmp/WhisperClip*20260917*` en `/tmp/whisper-review-*.log`.

Benchmark herhalen: kopieer `sort-benchmark.swift` naar een tijdelijke `main.swift` en compileer met `swiftc -O`, samen met `Packages/Core/Sources/Core/Model/TranscriptEntry.swift` en `TranscriptSegment.swift`. Draai het resulterende programma. De benchmark gebruikt geen database of persoonlijke gegevens.

## Aanbevolen vervolgstappen

1. De gerepareerde build na backup op Niels' iPhone controleren met een fysiek Hangs/Time Profiler-profiel tijdens tabwisselen en opnemen.
2. IP-03 oplossen met een transactionele sync-wachtrij en foutinjectietests; daarna live tussen twee eigen apparaten controleren.
3. IP-05 aanscherpen vóór een volgende variantwissel; Vincents verplichte backup-updateprocedure behouden.
4. Fysieke opnamecontroles uitvoeren: vergrendeling, onderbreking, lange opname, herstel en export; daarna gerichte controle op iOS 17/iPad.
5. Desgewenst de afgekapte lege-hulptekst bij maximale tekstgrootte verbeteren.

De onderzochte flows slagen in de genoemde testomgeving. Voor de fysieke bubbelanimatie, synchronisatie tussen apparaten en apparaatpermissies ontbreken nog praktijktests.

## Aanvulling: installatie na expliciete opdracht, 17 september 15:00

Na afronding van bovenstaande review vroeg Niels de versie op zijn iPhone te zetten. De getekende Debug-toestelbuild met dezelfde Development-iCloud-vlag is succesvol gebouwd en geïnstalleerd op zijn iPhone 17 Pro. Na ontgrendeling is de app succesvol geopend. Dit is geen fysieke performance- of opnameproef.

Vooraf is Application Support plus de voorkeuren gekopieerd naar `../device-backups/Niels-iPhone/2026-09-17-1458-performance/before/`. Na installatie zijn controlekopieën gemaakt. Beide databases geven `integrity_check = ok`; alle rijen van transcripties en notities zijn ongewijzigd behouden: Development 1.050 transcripties / 3 notities, andere variant 1.411 / 7. Alle bestaande voorkeurwaarden waren eveneens gelijk. Bewijs: `manifest.json` en `verification.json` in die backupmap. Geen databasevariant gewisseld, geen container verwijderd. De Mac-app is niet bijgewerkt.
