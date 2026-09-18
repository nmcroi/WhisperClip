# WhisperClip — review en voorstel audio bewaren

Datum: 13 september 2026. Gecontroleerde bron: commit `8f99db0` in deze werkmap; werkboom was bij aanvang schoon. Scope: broncodereview van de huidige Swift iPhone- en Mac-app, met nadruk op opnemen, transcriptie, opslag, herstel en geschiedenis. De oude Python-app valt buiten deze beoordeling.

Dit is een codebeoordeling, geen goedkeuring van een geïnstalleerde app of release. De versie op Vincents telefoon is niet vastgesteld. Er zijn geen productbestanden gewijzigd, apps geïnstalleerd, productiegegevens bewerkt of publicaties uitgevoerd.

## Voorstel voor Vincent

Behoud de standaard: audio verdwijnt na succesvolle transcriptie én duurzame opslag van het resultaat. Voeg onder Instellingen → Opnemen en transcriptie één instelling toe:

**Toon ‘Audio bewaren’ bij opnemen** — standaard uit.

Toelichting: “Kies per opname of je ook het geluidsbestand wilt bewaren.”

Wie dit inschakelt ziet bij de opnameknop **Bewaar audio van deze opname**. Die keuze staat voor iedere nieuwe opname opnieuw uit. Maak kiezen vóór en tijdens de opname mogelijk; leg de keuze bij Stop vast. Toon bij een ingeschakelde keuze tijdens opnemen de status “Audio wordt bewaard”. Een instelling die alleen de zichtbaarheid regelt moet niet ongemerkt het besluit voor een lopende opname veranderen.

Na succesvolle opslag staat bij het transcript in Geschiedenis een kleine audiosectie met afspelen, delen/exporteren en alleen audio verwijderen. Geen aparte audiobibliotheek of extra hoofdtab nodig. Op iPhone loopt export via het deelvenster, op Mac via Bewaar als. Voor Vincent is de handeling dus: eenmalig de optie zichtbaar maken, en vervolgens alleen bij de gewenste opname aanvinken.

Houd dezelfde betekenis op beide platformen. Migreer bestaande Mac-gebruikers met ‘altijd bewaren’ ingeschakeld niet stilzwijgend naar een ander gedrag: behoud hun bestaande voorkeur of maak de wijziging expliciet. Voor deze uitbreiding is een nieuwe algemene ‘altijd bewaren’-modus niet noodzakelijk.

### Audio en MP3 zijn twee verschillende keuzes

De huidige microfoonroute schrijft CAF met 16 kHz mono Float32; er bestaat nog geen MP3-bewaarroute. Gebruik daarom ‘Audio bewaren’ in de interface. Bewaar het oorspronkelijke bestand betrouwbaar en bied MP3 aan als expliciet exportformaat als Vincent dat werkelijk nodig heeft. Een bestandsnaam veranderen naar `.mp3` is geen conversie. Voor MP3 moet een encoder worden gekozen en op beide platformen worden getest; die technische keuze is in deze review niet gemaakt.

Als alleen terugluisteren of doorsturen nodig is, kan een gecomprimeerde M4A-export een eenvoudiger productkeuze zijn. Dit is een voorstel, geen reeds aanwezige opname-exportfunctie. Laat een mislukte conversie nooit het oorspronkelijke bestand verwijderen.

### Gedrag dat onderdeel van de functie moet zijn

- Geen automatische audiosynchronisatie: bij een gesynchroniseerde transcriptie op een ander apparaat staat zo nodig “Audio alleen beschikbaar op het opnameapparaat”. Gebruikers kunnen zelf exporteren/delen. Verduidelijk apart hoe apparaatback-ups met lokale audio omgaan.
- Bij Notulist moet de uitleg aan aanwezigen de gekozen audiobewaring weerspiegelen. Voeg audio niet automatisch aan het notulenbericht toe.
- Een gekozen audio-opname moet ook bewaard kunnen worden als de herkenner geen tekst vindt; dat is juist een reden om het origineel te willen hebben.
- Verwijderen van een transcript moet duidelijk maken wat met de bijbehorende audio gebeurt. Zorg ook voor opruimen bij bewaartermijnen en gesynchroniseerde verwijderingen.
- Maak opnamefouten en mislukte audio-opslag zichtbaar. Bewaar een herstelbaar origineel tot de afgesproken opslag werkelijk gelukt is.
- Onderscheid tijdelijke herstelbestanden van bewust bewaarde audio. Alleen achteraf een downloadknop toevoegen werkt niet: in de huidige standaardroute is audio bij het tonen van het resultaat al verwijderd.

## Bevindingen

Onderstaande uitkomsten zijn afgeleid uit de genoemde bronpaden. De scenario's beschrijven gerichte reproductiestappen voor een testbuild; ze zijn niet uitgevoerd op een fysieke iPhone of in de draaiende Mac-app.

### R-001 — Mac: bewaarinstelling heeft pas na herstart effect

**Ernst:** P1, privacy/functioneel. **Omgeving:** Mac, Parakeet-microfoonroute.

**Scenario:** start met bewaren aan, zet ‘Geluidsopname bewaren na transcriptie’ uit en maak een nieuwe opname zonder de app opnieuw te starten. Het omgekeerde scenario is starten met uit en daarna aanzetten.

**Verwacht:** de volgende opname volgt de zichtbare keuze.

**Werkelijk volgens code:** de toggle verandert `settings.saveRecordings`, maar de engine ontvangt deze waarde uitsluitend in `start()`. De `settings.didSet` verwerkt dit veld niet. Daardoor blijft de oude instelling actief: uitzetten kan alsnog audio bewaren; aanzetten kan de gewenste opname alsnog laten verwijderen.

**Bewijs:** `WhisperClipboard/UI/Settings/GeneralSettingsView.swift:210–213`; `WhisperClipboard/App/AppEnvironment.swift:55–76,600–602`; `Packages/Shared/Sources/WhisperShared/ParakeetEngine.swift:583–586,655–665`. Een zoekactie door alle Swift-bronnen vond slechts deze ene aanroep van `setPreserveFinishedRecording`.

**Advies:** geef de bewaarbeslissing expliciet per opnamesessie door, met een vastgelegd moment waarop wijzigingen voor die sessie worden overgenomen.

### R-002 — Mac: verwijderen van transcript laat bewaarde audio achter

**Ernst:** P1, privacy/opslag. **Omgeving:** Mac, transcript met lokaal bewaarde audio.

**Scenario:** start met bewaren aan, dicteer en verwijder vervolgens het transcript uit Geschiedenis. Inspecteer het bijbehorende bestand in `Recordings` in een geïsoleerde testcontainer.

**Verwacht:** de gebruiker krijgt een duidelijke verwijderkeuze en de app voert die volledig uit; verwijderde opnames blijven niet ongemerkt als los audiobestand achter.

**Werkelijk volgens code:** de UI verwijdert alleen de databaserij. De store stuurt een synchronisatiegebeurtenis en actualiseert de UI; er is geen opruimroute naar de bijbehorende audio. De audiostore kent vinden en bijsnijden, maar geen lifecycle-koppeling aan transcriptverwijdering. De audio kan daardoor lokaal blijven bestaan zonder zichtbare transcriptie.

**Bewijs:** `WhisperClipboard/UI/History/TranscriptDetailView.swift:88–97`; `Packages/Shared/Sources/WhisperShared/HistoryStore.swift:134–139`; `Packages/Shared/Sources/WhisperShared/HistorySyncEngine.swift:90–92`; `WhisperClipboard/Files/TranscriptAudioStore.swift`; opslag in `WhisperClipboard/App/AppEnvironment.swift:643–665`.

**Bereik:** ook automatische retentie en verwijderen via synchronisatie hebben een expliciet audiobeleid nodig.

**Advies:** centraliseer de relatie transcript–audio en voeg betrouwbare, herstelbare opruiming toe. Maak de verwijdertekst expliciet.

### R-003 — Mac: Notulist koppelt bewaarde audio niet aan het verslag

**Ernst:** P1, gegevensbeheer/gegevensverlies. **Omgeving:** Mac, bewaren aan vóór appstart, Notulist.

**Scenario:** maak een Notulist-opname met bewaren aan, rond af en start later de app opnieuw.

**Verwacht:** één verslag met het gekozen audiobestand, blijvend gekoppeld aan dat verslag.

**Werkelijk volgens code:** Notulist gebruikt dezelfde Parakeet-engine, die bij bewaren aan een `preservedAudioURL` retourneert. `MeetingController.finishSession()` bewaart uitsluitend het transcript en verwerkt deze URL nergens. Het CAF-bestand blijft dus in de tijdelijke herstelmap staan. De herstelroute kan het bij volgende start opnieuw transcriberen tot een tweede item met bron `mic.mac` en verwijdert daarna de audio, ook als bewaren aanstaat.

**Bewijs:** `WhisperClipboard/Meeting/MeetingController.swift:191–261`; `Packages/Shared/Sources/WhisperShared/ParakeetEngine.swift:655–662`; `WhisperClipboard/App/AppEnvironment.swift:668–713`. De audioverplaatsing op regel 507 wordt alleen door de dicteerroute gebruikt.

**Advies:** laat dictaat en Notulist dezelfde afrondings- en opslagroute gebruiken; bewaar bron, transcript-ID en audiobeslissing ook in herstelmetadata.

### R-004 — iPhone: gedeeltelijk verloren audio krijgt geen waarschuwing

**Ernst:** P1, gegevensverlies/functioneel. **Omgeving:** iPhone Opnemen en andere routes met `RecordController`, waaronder Notulist.

**Scenario:** laat een test-engine een bruikbare transcriptie met `partialFailure` en een kortere `audioDuration` teruggeven, zoals bij een tijdelijke schrijffout gedurende de opname.

**Verwacht:** behoud de bruikbare tekst, meld dat een deel van de audio ontbreekt en sla de werkelijke audioduur op.

**Werkelijk volgens code:** de controller verwerkt alleen tekst en segmenten en bewaart de duur van zijn teller. `partialFailure` en `audioDuration` worden niet gelezen. Een gedeeltelijke opname verschijnt dus als normaal afgerond. Als niets geschreven kon worden, kan de gebruiker ‘Geen audio of spraak herkend’ zien in plaats van een opslagfout.

**Bewijs:** `WhisperClipboardiOS/Record/RecordController.swift:370–388`; `Packages/Shared/Sources/WhisperShared/ParakeetEngine.swift:639–641,667–672`. Zoeken op `partialFailure` in alle iOS Swift-bronnen gaf geen verwerking; de Mac-controllers verwerken dit veld wel.

**Advies:** geef fouten en echte audioduur uit de engine door aan de iPhone-interface, inclusief de toestand met lege tekst.

### R-005 — Beide platformen: audio verdwijnt vóór het transcript duurzaam is opgeslagen

**Ernst:** P1, gegevensverlies bij opslagfout/crash. **Omgeving:** standaardinstelling, audio niet bewaren.

**Scenario:** laat transcriptie slagen maar de daaropvolgende database-write mislukken; beëindig daarna de app voordat kopiëren of opnieuw bewaren gelukt is.

**Verwacht:** herstel blijft mogelijk totdat het transcript duurzaam is opgeslagen, waarna tijdelijke audio mag verdwijnen.

**Werkelijk volgens code:** `finalize()` verwijdert de audio voordat de controller aan opslaan toekomt. De iPhone bewaart bij een databasefout alleen een `pendingSave` in geheugen; de Mac waarschuwt dat de tekst nog op het klembord staat. Deze noodmaatregelen zijn nuttig, maar overleven geen appbeëindiging respectievelijk overschreven klembord. De normale route heeft daarmee een herstelgat dat de aparte crashherstelroute juist vermijdt.

**Bewijs:** `Packages/Shared/Sources/WhisperShared/ParakeetEngine.swift:664–672`; `WhisperClipboardiOS/Record/RecordController.swift:371–387,438–445`; `WhisperClipboard/App/AppEnvironment.swift:503–528`. Vergelijk de herstelroute die pas na `history.add` verwijdert, op regels 709–711.

**Advies:** laat finalize tijdelijk eigendom van de audio aan de opslagcoördinator overdragen. Verwijder pas na een geslaagde transcript-write en alleen wanneer de gebruiker audio niet wil bewaren. Geef herstelitems een stabiele identiteit om dubbelen na een crash te voorkomen.

### R-006 — Mac: meervoudig verwijderen en samenvoegen zijn niet atomair

**Ernst:** P2, functioneel/gegevensconsistentie. **Omgeving:** Mac Geschiedenis, meerdere geselecteerde items.

**Scenario:** selecteer meerdere transcripties; injecteer een databasefout bij de tweede verwijdering. Herhaal bij samenvoegen met verwijderen van originelen.

**Verwacht:** de bewerking slaagt volledig of laat de oude situatie intact.

**Werkelijk volgens code:** de Mac-interface voert afzonderlijke `delete`-aanroepen uit; samenvoegen schrijft eerst het nieuwe item en verwijdert daarna originelen in een lus. Bij een fout blijven gedeeltelijke wijzigingen staan, ondanks de foutmelding. De gedeelde store bevat al transactionele `deleteMany` en `mergeAndReplace`-methoden, maar deze Mac-acties gebruiken ze niet.

**Bewijs:** `WhisperClipboard/UI/History/HistoryListView.swift:269–290,305–317`; `Packages/Shared/Sources/WhisperShared/HistoryStore.swift:143–173`.

**Advies:** verbind de Mac-acties aan de bestaande transactionele methoden en neem de audio-lifecycle mee bij de verdere uitbreiding.

## Validatie en beperkingen

Uitgevoerd: `swift test --package-path v2/Packages/Core --scratch-path /tmp/whisperclip-review-20260913-core`.

Resultaat: **197 tests in 17 suites geslaagd**. De build gebruikte een afzonderlijke scratchmap. Deze suite controleert gedeelde logica, onder meer tekstverwerking, instellingen, export, taalmetadata, pauzeteller en AI-clients met mocks. Zij test niet de daadwerkelijke appcontrollers of het bewaren/verwijderen van microfoonaudio. De geslaagde tests ontkrachten bovenstaande bevindingen dus niet.

Niet uitgevoerd: volledige Xcode-appbuilds, XCTest-appintegratietests, fysieke opnames, simulatorinteractie, achtergrond- en vergrendelschermgedrag, VoiceOver, visuele schermmatrix, CloudKit/PLAUD/Mail met accounts, distributiesigning, netwerkinspectie of belasting-/batterijmetingen. Er is geen audio-encoder gekozen of getest. De historische screenshots en reviewdocumenten zijn geen bewijs voor de huidige geïnstalleerde app.

De aanbeveling is om eerst de opslag- en verwijderroute betrouwbaar te maken en daar de optionele keuze per opname aan te koppelen. Zo blijft audio niet bewaren de rustige standaard, terwijl Vincent gericht een opname kan behouden.
