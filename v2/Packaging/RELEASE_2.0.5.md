# WhisperClip macOS 2.0.5 (11) — structurele hoverreparatie

23 september 2026. Deze release verwijdert de volledige SwiftUI-hoverroute uit de macOS-app.

## Waarom

De crashrapporten van 2.0.2, 2.0.3 en 2.0.4 hadden verschillende AppKit-ingangen, maar dezelfde beschadigde Swift-concurrencycontrole op macOS 27: panel-focus, Dock-heropenen en uiteindelijk `NSHostingView.mouseEntered` tijdens SwiftUI hover/hit-testing. De laatste crashstack bevatte geen WhisperClip-frame tussen SwiftUI en AppKit. Dat maakt losse callbackreparaties onvoldoende als langetermijnstrategie.

## Wijziging

Alle macOS `.onHover`- en daarmee verbonden hover-state zijn verwijderd uit de HUD, actiekaarten en transcriptdetailrijen. Hover had geen functionele rol; het wijzigde alleen schaal, kleur, rand, cursor of de zichtbaarheid van trimknoppen. Trimknoppen zijn nu altijd zichtbaar wanneer de actie beschikbaar is. Klikken, toetsenbordbediening, opname, sneltoetsen en navigatie blijven behouden. De iPhone-target is niet gewijzigd.

## Verificatie

- Statische broncontrole: geen `.onHover`, `hoverEffect`, `onContinuousHover`, `NSTrackingArea`, `mouseEntered`, `mouseExited` of `pointingHandCursor` in `WhisperClipboard`.
- 337 Mac-tests geslaagd, 0 fouten, 0 skips; de drie bestaande E2E-suites zijn expliciet uitgesloten: `E2EImportSmokeTests`, `E2EDiarizationSmokeTests`, `E2ECaptionsSmokeTests`.
- Release-build op macOS 27.0 (26A428), Xcode 27.0 (27A266a) geslaagd.
- Bestaande Dock-heropen- en panelstresscontroles blijven onderdeel van de voorafgaande reparatiereeks; geen hovercallbacks meer om te triggeren.
- Backup-helpertests geslaagd.

De wijziging bewijst dat deze kwetsbare route niet meer bestaat. Zij bewijst niet dat iedere toekomstige macOS- of SwiftUI-crash onmogelijk is. Langdurig gebruik op de werk-Mac blijft nodig.

## Distributie

Versie 2.0.5, build 11. Release gebruikt `history.db` en CloudKit Production. De DMG wordt Developer ID-ondertekend, genotariseerd, gestapled en met Gatekeeper en `hdiutil verify` gecontroleerd. Installeer eerst de meegeleverde backuphelper en vervang de app op dezelfde locatie. Geen appgegevens verwijderen; geen App Store-publicatie.

Definitieve controle geslaagd: `Releases/WhisperClip-2.0.5.dmg`. De gemounte app is versie 2.0.5 (11); diepe codesigncontrole, app- en DMG-ticket, Gatekeeper, helper/instructies en `hdiutil verify` zijn gecontroleerd. Apple heeft zowel app als DMG geaccepteerd. SHA-256: `f2b347afbe9c9e540b8a47b5d4e5021ef103e98fca1f8f15d50e6bbbb8d08a6b`. Niet op de werk-Mac geïnstalleerd vanuit deze sessie.
