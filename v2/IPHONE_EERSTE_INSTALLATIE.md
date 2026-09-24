# Eerste installatie op een andere iPhone

Werkrecept, bijgewerkt 19 september 2026. Gebaseerd op de bij Vincent vastgelegde kabelroute in `WhisperClip.md` in de ChiefOfStaff-projectmap. Voor een update van Vincent blijft uitsluitend `VINCENT_IPHONE_UPDATE.md` en zijn updatescript gelden.

1. Identificeer het juiste toestel met `xcrun devicectl list devices`; nooit alleen aannemen dat de zichtbare iPhone die van de bezoeker is. Laat op de iPhone de computer vertrouwen.
2. Ontwikkelaarsmodus inschakelen bij Instellingen → Privacy en beveiliging; herstarten en inschakelen bevestigen. Controleer `developerModeStatus: enabled`.
3. Controleer met `device info apps` of WhisperClip al bestaat. Zo ja, eerst backup van Application Support en voorkeuren, integriteit/aantallen en de databasevariant controleren. Nooit app of container verwijderen. Een eerste installatie zonder bestaande app heeft geen oude WhisperClip-container om te back-uppen.
4. Bouw voor de exacte toestel-ID met geldige Apple Development-signering. Projectdefaults schakelen iOS-signering uit; de opdracht moet expliciet `CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=... CODE_SIGN_IDENTITY='Apple Development' -allowProvisioningUpdates -allowProvisioningDeviceRegistration` doorgeven. Controleer daarna dat het embedded provisioning profile dit toestel bevat. Zo nodig toestelregistratie via Xcode oplossen; vertrouw geen buildmelding zonder profielcontrole.
5. Iedere nieuwe geleverde binary krijgt een uniek buildnummer. Houd app en widgetversie gelijk. Gebruik bij bestaande data dezelfde Debug/Release-variant. Voor nieuwe persoonlijke installaties sluit Debug met `OTHER_SWIFT_FLAGS='$(inherited) -DWHISPERCLIP_ICLOUD_DEVELOPMENT'` aan bij de bestaande iPhone-builds. Kopieer geen persoonlijke voorkeuren/API-sleutels van Niels of Vincent.
6. Installeer de app, maar open deze nog niet. Kopieer Parakeet rechtstreeks via de kabel; zo is geen mogelijk haperende appdownload nodig:

```sh
xcrun devicectl device copy to --device TOESTEL_ID \
  --source "$HOME/Library/Application Support/FluidAudio/Models/parakeet-tdt-0.6b-v3" \
  --destination "Library/Application Support/FluidAudio/Models/parakeet-tdt-0.6b-v3" \
  --domain-type appDataContainer \
  --domain-identifier nl.nielscroiset.whisperclipboard.ios
```

Laat de app tijdens de hele kopie dicht: een gelijktijdige download/herstelpoging kan onvolledige modellen opruimen. Geen `--remove-existing-content` gebruiken op de appcontainer. De modelmap op deze Mac bevatte 23 bestanden, samen 483.256.769 bytes; dit is een controlewaarde voor de huidige modelversie, geen universele eis. Controleer bestandsgroottes en liefst hashes na terugkopiëren, vooral het grote encoderbestand.

7. Start de app pas na de volledige overdracht. Controleer dat het proces blijft draaien en laat de eigenaar een korte opname doen om model laden, microfoontoegang en herkenning te bevestigen. Een geslaagde bestandsoverdracht of processtart bewijst op zichzelf geen transcriptiekwaliteit.

Toestel-ID's, profielgegevens en controlekopieën lokaal onder `../device-backups/<persoon>/`, uitgesloten van Git. De ondertekening verloopt volgens het provisioning profile; lees de echte vervaldatum in plaats van een vaste geldigheidsduur te beloven.
