import Foundation

public enum AudioCopy {
    public enum Key: String, Sendable {
        case privacyDeletion, privacySharing
        case showOption, choice, keeping, help, legacy, noAudio, noSpeech, play, pause, export, remove, confirmRemove, deleteTogether, mergeWarning, cancel, close, position, storageFailed, partialAudio, noteMissing, cleanupFailed, retry, found, foundHelp, localOnly, exportFailed, audio
    }
    public static func text(_ key: Key, locale: Locale = .current) -> String {
        let language = locale.language.languageCode?.identifier ?? "nl"
        let index = language == "de" ? 2 : language == "en" ? 1 : 0
        switch key {
        case .privacyDeletion: return ["Tijdelijke audio verdwijnt pas na veilige opslag van het transcript", "Temporary audio is deleted only after the transcript is safely saved", "Temporäres Audio wird erst nach sicherer Speicherung des Transkripts gelöscht"][index]
        case .privacySharing: return ["Audio blijft lokaal, tenzij je het zelf deelt of exporteert", "Audio stays local unless you share or export it yourself", "Audio bleibt lokal, außer Sie teilen oder exportieren es selbst"][index]
        case .showOption: return ["Toon optie Audio bewaren", "Show Save audio option", "Option Audio behalten anzeigen"][index]
        case .choice: return ["Bewaar audio", "Keep audio", "Audio behalten"][index]
        case .keeping: return ["Audio wordt bewaard", "Audio will be kept", "Audio wird behalten"][index]
        case .help: return ["Kies per gewone opname of je ook het geluidsbestand wilt bewaren. Notulist bewaart geen audio.", "Choose whether to keep audio for each regular recording. Meeting Minutes does not keep audio.", "Für jede normale Aufnahme entscheiden, ob das Audio behalten wird. Das Protokoll behält kein Audio."][index]
        case .legacy: return ["Gewone opnames standaard bewaren (bestaande voorkeur)", "Keep regular recordings by default (existing preference)", "Normale Aufnahmen standardmäßig behalten (bisherige Einstellung)"][index]
        case .noAudio: return ["Geen audio op dit apparaat", "No audio on this device", "Kein Audio auf diesem Gerät"][index]
        case .noSpeech: return ["Geen spraak herkend", "No speech recognized", "Keine Sprache erkannt"][index]
        case .play: return ["Afspelen", "Play", "Abspielen"][index]
        case .pause: return ["Pauzeren", "Pause", "Pause"][index]
        case .export: return ["Deel M4A", "Share M4A", "M4A teilen"][index]
        case .remove: return ["Alleen audio verwijderen", "Delete audio only", "Nur Audio löschen"][index]
        case .confirmRemove: return ["De audio wordt van dit apparaat verwijderd. Het transcript blijft behouden.", "Audio will be deleted from this device. The transcript will be kept.", "Das Audio wird von diesem Gerät gelöscht. Das Transkript bleibt erhalten."][index]
        case .deleteTogether: return ["Het transcript en de bijbehorende lokale audio worden verwijderd. Zelf geëxporteerde bestanden blijven behouden.", "The transcript and its local audio will be deleted. Files you exported yourself will be kept.", "Das Transkript und sein lokales Audio werden gelöscht. Selbst exportierte Dateien bleiben erhalten."][index]
        case .mergeWarning: return ["Alleen tekst wordt samengevoegd. Verwijder je de originelen, dan verdwijnt ook hun lokale audio.", "Only text is merged. Deleting the originals also deletes their local audio.", "Nur Text wird zusammengeführt. Beim Löschen der Originale wird auch deren lokales Audio gelöscht."][index]
        case .cancel: return ["Annuleer", "Cancel", "Abbrechen"][index]
        case .close: return ["Sluiten", "Close", "Schließen"][index]
        case .position: return ["Afspeelpositie", "Playback position", "Wiedergabeposition"][index]
        case .storageFailed: return ["Opslaan is nog niet gelukt. De opname blijft beschikbaar voor herstel; probeer opnieuw.", "Saving has not completed. The recording is kept for recovery; try again.", "Das Speichern ist noch nicht abgeschlossen. Die Aufnahme bleibt zur Wiederherstellung erhalten; erneut versuchen."][index]
        case .partialAudio: return ["Een deel van de audio ontbreekt door een opnamefout. De tekst bevat alleen wat kon worden verwerkt.", "Some audio is missing due to a recording error. The text contains only what could be processed.", "Wegen eines Aufnahmefehlers fehlt ein Teil des Audios. Der Text enthält nur, was verarbeitet werden konnte."][index]
        case .noteMissing: return ["De oorspronkelijke notitie bestaat niet meer. De opname staat los in Geschiedenis.", "The original note no longer exists. The recording is in History.", "Die ursprüngliche Notiz existiert nicht mehr. Die Aufnahme steht im Verlauf."][index]
        case .cleanupFailed: return ["Audio kon nog niet volledig worden verwijderd. Probeer opnieuw.", "Audio could not be fully deleted yet. Try again.", "Das Audio konnte noch nicht vollständig gelöscht werden. Erneut versuchen."][index]
        case .retry: return ["Opnieuw proberen", "Try again", "Erneut versuchen"][index]
        case .found: return ["Gevonden opnames", "Found recordings", "Gefundene Aufnahmen"][index]
        case .foundHelp: return ["Deze audiobestanden hebben geen transcript meer. Je kunt ze beluisteren, exporteren of verwijderen.", "These audio files no longer have a transcript. You can listen, export or delete them.", "Diese Audiodateien haben kein Transkript mehr. Sie können sie anhören, exportieren oder löschen."][index]
        case .localOnly: return ["Audio blijft alleen op dit apparaat en valt buiten synchronisatie en automatische back-ups. Verwijderen van het transcript verwijdert ook de audio.", "Audio stays on this device, outside sync and automatic backups. Deleting the transcript also deletes its audio.", "Audio bleibt auf diesem Gerät, ohne Synchronisierung oder automatische Backups. Beim Löschen des Transkripts wird auch das Audio gelöscht."][index]
        case .exportFailed: return ["Exporteren is mislukt. De oorspronkelijke audio blijft behouden.", "Export failed. The original audio is preserved.", "Der Export ist fehlgeschlagen. Das Originalaudio bleibt erhalten."][index]
        case .audio: return ["Audio", "Audio", "Audio"][index]
        }
    }
}
