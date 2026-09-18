# WhisperClip — audio bewaren en herstel

Implementatie van het goedgekeurde plan in de Swift-apps, 13 september 2026.
De eerdere bevindingen staan in `REVIEW_2026-09-13_AUDIO_BEWAREN.md`.
Geen publicatie, verspreiding of installatie over een bestaande gebruikersapp.

## Gedrag

- Nieuwe installaties bewaren audio niet automatisch. Instellingen kan ‘Bewaar audio van deze opname’ zichtbaar maken; de keuze wordt per opname gereset en bij Stop vastgelegd.
- De bestaande Mac-voorkeur voor automatisch bewaren blijft herkenbaar behouden. Wijzigingen werken voor nieuwe opnames zonder appherstart. Een zichtbaarheidwijziging wijzigt de lopende bewaarbeslissing niet.
- Gewone opnames en iPhone-notitieopnames kunnen audio bewaren. Notulist gebruikt uitsluitend tijdelijke herstelaudio.
- Geschiedenis en notitie-items tonen bij lokale audio afspelen/pauzeren, voortgang, M4A-export en ‘Alleen audio verwijderen’. Lege herkenning blijft lege tekst; ‘Geen spraak herkend’ is alleen interface-uitleg.
- iPhone gebruikt het systeemdeelvenster; Mac gebruikt Bewaar als. Export converteert met AVFoundation en behoudt het origineel bij fouten. Exportkopieën worden bij afsluiten/annuleren en na een procesherstart opgeruimd.
- Audio blijft lokaal, buiten automatische back-ups en CloudKit. Transcriptverwijdering, retentie, bulkacties, notitieverwijdering met transcripties en ontvangen sync-verwijderingen ruimen audio op. Bij alleen loskoppelen uit een notitie blijft het transcript met audio bestaan. Zelf geëxporteerde bestanden blijven intact.
- Samenvoegen voegt alleen tekst samen; de bevestiging vermeldt de gevolgen voor audio van verwijderde originelen.
- Nieuwe audio-instellingen, bediening en meldingen hebben NL/EN/DE-teksten en toegankelijke labels. Bestaande kleuren en componenten blijven in gebruik.

## Reparaties en opslagroute

| Review | Implementatie |
|---|---|
| R-001: instelling alleen bij starten app | Opnamesessie met eigen bewaarbeslissing; engine krijgt de laatste keuze bij Stop. Updates zijn gekoppeld aan de sessie-ID zodat een late update de volgende opname niet wijzigt. |
| R-002: achterblijvende audio | SQLite-verwijdertrigger en duurzame `audio_deletions`-wachtrij. Bestanden worden pas na commit verwijderd. Mislukte opruiming blijft gemeld en wordt opnieuw geprobeerd. |
| R-003: Notulist en dubbel herstel | Dezelfde sessie- en opslagroute, vergaderbron blijft behouden; permanent bewaren is op meerdere lagen uitgesloten. |
| R-004: gedeeltelijke iPhone-audio | `RecordingHealth` beoordeelt expliciete opnamefouten en werkelijke duur, inclusief nul. Bruikbare tekst verhindert een waarschuwing niet. |
| R-005: audio vóór databaseopslag weg | Engines sluiten de opname en leveren eigendom over. Journal, transcriptcommit, audiobesluit en journalopruiming gebeuren in herstelbare stappen met hetzelfde ID. |
| R-006: Mac-bulkacties | UI gebruikt `deleteMany` en `mergeAndReplace`. Een mislukte transactie laat de selectie en oorspronkelijke rijen intact. |

`RecordingSession`, `RecordingRepository` en de opnamefuncties van `HistoryStore` vormen samen de gedeelde coördinatie. Het journal onder Application Support bevat bron, taal, model, notitiekoppeling, bewaarbeslissing, resultaat en verwerkingsstatus. Een herhaling van een voltooide stap maakt geen tweede transcript. Een verdwenen notitie geeft een los transcript en een melding.

De microfoon schrijft naar één CAF-bestand op schijf. Optionele Mac-sprekerherkenning leest dat bestand via een memory map; er wordt tijdens opnemen geen volledige sample-array meer verzameld. Pas na duurzame transcriptopslag wordt het bestand verwijderd of naar Recordings verplaatst. Ook Apple Speech draagt zijn opname aan deze route over. Verwijderen tijdens uitgestelde nabewerking wint van een later bewaarverzoek.

## Migratie

- Alleen nieuwe migraties `v8_recording_lifecycle` en `v9_explicit_audio_deletion`; v1–v7 zijn ongewijzigd. Automatisch wissen bij schemawijzigingen is uitgezet.
- Geen reset van geschiedenis, notities, instellingen, sleutels of synchronisatie-identiteit.
- Bestaande audio wordt aan de hand van het transcript-ID in de bestandsnaam gevonden, zonder hercodering. Niet-gekoppelde bestanden blijven bestaan en worden als gevonden opnames aangeboden voor export of expliciete verwijdering.
- Oude tijdelijke CAF-bestanden worden idempotent overgenomen in de herstelmap. Onleesbare journals verbergen andere herstelbare opnames niet.
- Release gebruikt de bestaande Application Support/Recordings-map. Debug gebruikt bewust `Audio-dev`, naast de bestaande ontwikkelgeschiedenis, zodat verificatie geen productieaudio opruimt.

## Uitgevoerde verificatie

| Controle | Resultaat |
|---|---|
| Core-package | 199 tests geslaagd |
| Gedeeld opslagpackage | 79 tests geslaagd: 31 nieuwe lifecycle-tests en 48 bestaande geschiedenis-/transactietests |
| iPhone-integratie in geïsoleerde simulator | 4 UI-tests geslaagd; inclusief synthetische audiofixture |
| Mac Debug-build | Geslaagd; ook `build-for-testing` van de Mac-tests slaagt |
| iPhone Simulator Debug-build | Geslaagd als onderdeel van de UI-tests |
| iPhone device Debug-build | Geslaagd, zonder ondertekenen/installeren |
| Patchcontrole | `git diff --check` zonder fouten |

De bestaande `HistoryStoreTests` en `HistoryTransactionTests` zijn verplaatst naar het gedeelde package. Zij hebben geen Mac-apphost nodig en draaien nu met geïsoleerde databases, zonder de geïnstalleerde app of de gebruikerssleutels te starten.

De nieuwe tests controleren databasefouten/rollback, een geïnjecteerde ENOSPC-fout bij journaling, mislukte verplaatsing, heropenen en herhalen na opslaggrenzen, audio-only-verwijdering tijdens uitgestelde afronding, retentie, remote deletion, notitieverwijdering, migratie vanuit v7, legacy-bestanden, een beschadigd journal, backup-uitsluiting, lege herkenning, gedeeltelijke/ontbrekende audio, CAF-memorymapping en daadwerkelijke synthetische CAF→M4A-conversie. Een bestandsverwijderfout wordt met geïsoleerde bestandstoegangsrechten opgewekt en daarna succesvol herhaald.

De UI-tests controleren standaard verborgen/uit, de instelling inschakelen, keuze reset na herstart, afwezigheid bij Notulist, en NL/EN/DE in licht/donker met de grootste Dynamic Type-instelling. Met drie seconden synthetische testaudio zijn afspelen, voortgang, het echte M4A-deelvenster, annuleren en audio-only-verwijdering met behoud van tekst gecontroleerd. Een onafhankelijke controle van de simulatorbestanden bevestigt na afloop dat zowel de oorspronkelijke audio als de tijdelijke M4A weg zijn en de transcripttekst nog in SQLite staat. Screenshots staan in `ReviewScreenshots/2026-09-13-audio/`.

## Nog niet fysiek of volledig end-to-end gecontroleerd

- Echte spraakopname en herkenning met Parakeet en Apple Speech, inclusief een lange opname en geheugen-/batterijmetingen.
- iPhone-achtergrondopname, schermvergrendeling, telefoon-/audio-onderbrekingen, pauzeren/hervatten en hervatten na geforceerde procesbeëindiging tijdens echte opname.
- Bewaarinstelling wijzigen tijdens een echte opname en opnieuw opnemen zonder appherstart; de logica en UI zijn gecontroleerd, de volledige microfoonroute niet.
- Een fysieke volle schijf of stroomuitval. De automatische tests simuleren fouten en heropenen opslag op relevante stapgrenzen; ze zijn geen stroomuitvaltest.
- Mac-interface, sneltoets/HUD, live opname en het uiteindelijke Bewaar-als-venster op de geïnstalleerde app.
- Volledige VoiceOver-bediening en alle gewijzigde schermen op alle tekstgroottes. De screenshotmatrix dekt de nieuwe iPhone-opnamekeuze; settings en audiogeschiedenis zijn aanvullend op normale tekstgrootte bekeken.
- Echte CloudKit-verwijdering tussen twee apparaten. De ontvangende store-route is met geïsoleerde data getest.
- Levering aan een externe deelbestemming zoals Mail/Bestanden en controle van een geëxporteerd bestand buiten de app. De conversie naar leesbare M4A en het openen/annuleren van het deelvenster zijn wel getest.
- Upgrade van de daadwerkelijk bij Vincent geïnstalleerde versie. De database- en audiomigratie zijn op fixtures gecontroleerd.

## Reproduceren

Vanuit `v2`:

```sh
swift test --package-path Packages/Core
swift test --package-path Packages/Shared
xcodegen generate
xcodebuild -project WhisperClipboard.xcodeproj -scheme WhisperClipboard -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

De iOS-review gebruikt scheme `WhisperClipAudioReview` en een afzonderlijke simulator met naam `WhisperClip Audio Review`. Start de Debug-app eerst eenmaal zodat de lege ontwikkelgeschiedenis bestaat. Maak daarna uitsluitend op die simulator de fixture:

```sh
python3 scripts/seed_audio_review.py SIMULATOR_UUID
xcodebuild -project WhisperClipboard.xcodeproj -scheme WhisperClipAudioReview -configuration Debug -destination 'platform=iOS Simulator,id=SIMULATOR_UUID' CODE_SIGNING_ALLOWED=NO test
```

Het script weigert andere simulatornamen. Zonder fixture wordt alleen de expliciete audiofixture-test overgeslagen. De gerapporteerde reviewrun heeft de fixture gebruikt en geen test overgeslagen.

## Vervolg: installatie op Niels' iPhone

Op 13 september 2026, na de afzonderlijke opdracht om de app op de iPhone te zetten, is de huidige bron als Release gebouwd en ondertekend met Apple Development, team APC9FD5B67. `codesign --verify --deep --strict` slaagt. De build is met behoud van de appcontainer over bundle-id `nl.nielscroiset.whisperclipboard.ios` geïnstalleerd op **iPhone 17 Pro NMC** en daarna succesvol gestart via `devicectl`. Er is geen uninstall of containerreset uitgevoerd. Versie/build blijft 2.0.1 (5). Dit bevestigt installatie en starten; de hierboven genoemde opnamepraktijkchecks zijn hiermee nog niet uitgevoerd.

Bewijs van deze lokale installatie: `/tmp/whisperclip-audio-device-install-build.log`, `/tmp/whisperclip-phone-install.json`, `/tmp/whisperclip-phone-launch.json` en `/tmp/whisperclip-phone-after.json`.
