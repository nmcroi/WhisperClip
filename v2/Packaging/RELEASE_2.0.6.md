# WhisperClip macOS 2.0.6 (12), 24 september 2026

## Wat er is veranderd

De crashfamilie van 2.0.2 tot 2.0.5 (EXC_BAD_ACCESS in `swift_task_isCurrentExecutor`, via panel-focus, Dock-heropenen, hover of een timer) heeft één oorzaak: een Objective-C-exceptie uit `AVAudioInputNode.installTap` bij een formaatverschil na een microfoonwissel, die door een Swift-async-taak heen vloog en de concurrency-runtime kapot achterliet. Bewijs en mechanisme staan in `CLAUDE_MACOS_CRASH_HANDOFF.md`.

Reparatie in drie lagen (`WhisperClipboard/Audio/AudioEngine.swift`, `Packages/Core`):

1. Vóór elke start en hervatting wordt het hardwareformaat vergeleken met het clientformaat; bij verschil wordt de engine gereset.
2. Een Objective-C-vangnet (`ObjCExceptionCatcher`) om `installTap`, `prepare` en `start`: een NSException wordt een gewone Swift-fout met de melding "De microfoon is gewisseld of niet beschikbaar. Probeer het opnieuw." Ook op de iPhone.
3. Beide gebeurtenissen worden in `~/Library/Logs/Whisper Clipboard/app.log` geschreven.

De hover-, panel- en Dock-wijzigingen van 2.0.3 tot 2.0.5 blijven staan.

## Controle

- Mac-testsuite volledig groen, inclusief `AudioTapExceptionTests` (de echte installTap-formaatfout op een echte AVAudioEngine gaat door het vangnet) en `ObjCExceptionTests` in Core.
- iOS-build groen.
- Release-build 2.0.6 (12) op macOS 27.0, ingepakt via `package_work_mac.py`: Developer ID, Apple-notarisatie van app en DMG, tickets aangehecht, Gatekeeper "accepted, Notarized Developer ID", CloudKit-rechten aanwezig.
- `Releases/WhisperClip-2.0.6.dmg`, SHA-256 `140b6f5814b2edabf60936063c9491ce6042ac1eed244ae1dd3883ffbd6001f0`.

## Installatie op de werk-Mac

Zoals bij 2.0.5: eerst Cmd-Q, dan "Controleer en maak backup.command" uit de DMG, daarna de app op dezelfde plek vervangen. Geen appgegevens verwijderen.

## Wat het bewijs is dat het werkt

Na een microfoonwissel (AirPods, dock) gevolgd door een dictaat hoort `app.log` een regel "AudioEngine: invoerformaat gewisseld" of "AudioEngine: ObjC-exceptie opgevangen" te bevatten, en de app hoort door te draaien. Dagenlang geen crash mét zulke regels in het log is het bewijs.
