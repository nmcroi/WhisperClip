import FluidAudio
import Foundation

/// Ondersteunt het handmatig importeren van het Parakeet-model op iOS wanneer
/// de download over mobiel of wifi telkens vastloopt (bijvoorbeeld door
/// schermvergrendeling): Niels airdropt de modelmap `parakeet-tdt-0.6b-v3` van
/// zijn Mac naar de iPhone en kiest hem via een `fileImporter`. Alleen
/// FileManager en paden hier, geen UIKit, zodat dit los van de app te testen
/// is.
public enum ParakeetModelImport {

    /// Naam van de modelmap zoals FluidAudio hem op de doellocatie verwacht.
    /// Gelijk aan `Repo.parakeetV3.folderName` in FluidAudio, hier als eigen
    /// constante zodat dit bestand niet van een private FluidAudio-detail
    /// afhangt.
    public static let modelFolderName = "parakeet-tdt-0.6b-v3"

    /// Exacte bestandsnamen van de vereiste modelonderdelen, opgezocht in
    /// FluidAudio's `ModelNames.swift` en `AsrModels.requiredModelsV3`
    /// (encoderprecisie `.int8`, de standaard die de app gebruikt).
    public enum RequiredFile {
        public static let preprocessor = "Preprocessor.mlmodelc"
        public static let encoder = "Encoder.mlmodelc"
        public static let decoder = "Decoder.mlmodelc"
        public static let joint = "JointDecisionv3.mlmodelc"
        public static let vocabulary = "parakeet_vocab.json"

        public static let all = [preprocessor, encoder, decoder, joint, vocabulary]
    }

    /// Pad van het gewichtenbestand binnen het encoder-CoreML-pakket, en de
    /// minimale grootte waaronder een AirDrop als onvolledig geldt. Een
    /// afgebroken overdracht laat de mappenstructuur van het encoder-pakket
    /// intact maar met een leeg of half geschreven `weight.bin`, terwijl de
    /// kleinere bestanden (preprocessor, decoder, vocab) meestal wel compleet
    /// aankomen.
    public static let encoderWeightsRelativePath = "weights/weight.bin"
    public static let minimumEncoderWeightsBytes: Int64 = 300 * 1024 * 1024

    public enum ValidationError: Error, Equatable {
        case notADirectory
        case missingFile(String)
        case encoderWeightsTooSmall(actualBytes: Int64, minimumBytes: Int64)

        /// Nederlandse foutmelding die specifiek zegt wat er mis is, voor
        /// directe weergave in de UI.
        public var localizedDescriptionNL: String {
            switch self {
            case .notADirectory:
                return "Dit is geen map."
            case .missingFile(let name):
                return "De map mist \"\(name)\". Kies de map \"\(modelFolderName)\" zelf, of de map die hem bevat."
            case .encoderWeightsTooSmall(let actual, let minimum):
                let actualMB = actual / (1024 * 1024)
                let minimumMB = minimum / (1024 * 1024)
                return "Het encoder-gewichtenbestand is te klein (\(actualMB) MB, verwacht minstens \(minimumMB) MB). De AirDrop is waarschijnlijk niet compleet aangekomen."
            }
        }
    }

    /// Zoekt de daadwerkelijke modelmap onder de door de gebruiker gekozen map.
    /// Niels kiest soms de map `parakeet-tdt-0.6b-v3` zelf, soms de
    /// bovenliggende map waar die submap in zit (bijvoorbeeld de hele AirDrop-
    /// ontvangstmap). Beide worden geaccepteerd.
    public static func resolveModelDirectory(chosen: URL) -> URL {
        let nested = chosen.appendingPathComponent(modelFolderName, isDirectory: true)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: nested.path, isDirectory: &isDir), isDir.boolValue {
            return nested
        }
        return chosen
    }

    /// Pure validatie: controleert of alle vereiste modelbestanden aanwezig
    /// zijn en of het encoder-gewichtenbestand niet halverwege is afgebroken.
    /// Doet geen I/O buiten lezen, kopieert niets.
    public static func validate(directory: URL) -> Result<URL, ValidationError> {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: directory.path, isDirectory: &isDir), isDir.boolValue else {
            return .failure(.notADirectory)
        }

        for file in RequiredFile.all {
            let path = directory.appendingPathComponent(file)
            guard fm.fileExists(atPath: path.path) else {
                return .failure(.missingFile(file))
            }
        }

        let weightsURL = directory
            .appendingPathComponent(RequiredFile.encoder)
            .appendingPathComponent(encoderWeightsRelativePath)
        guard let attributes = try? fm.attributesOfItem(atPath: weightsURL.path),
              let size = attributes[.size] as? Int
        else {
            return .failure(.missingFile("\(RequiredFile.encoder)/\(encoderWeightsRelativePath)"))
        }

        let sizeBytes = Int64(size)
        guard sizeBytes >= minimumEncoderWeightsBytes else {
            return .failure(.encoderWeightsTooSmall(actualBytes: sizeBytes, minimumBytes: minimumEncoderWeightsBytes))
        }

        return .success(directory)
    }

    /// De map waar FluidAudio het v3-model op deze machine verwacht
    /// (`Library/Application Support/FluidAudio/Models/parakeet-tdt-0.6b-v3`
    /// in de eigen sandbox van de app). Hergebruikt FluidAudio's eigen
    /// padlogica zodat dit nooit uit de pas loopt met waar de engine leest.
    public static var destinationDirectory: URL {
        AsrModels.defaultCacheDirectory(for: .v3)
    }

    /// Kopieert een gevalideerde modelmap naar de doellocatie. Puur bestandswerk
    /// zonder UIKit, dus aan te roepen vanaf een achtergrondtaak.
    ///
    /// De kopie gaat eerst naar een tijdelijke buurmap en vervangt het doel pas
    /// als hij compleet is. Voorheen werd het bestaande model als eerste
    /// weggegooid: brak de kopie daarna af (te weinig ruimte, AirDrop-map
    /// ingetrokken), dan had de gebruiker helemaal geen model meer.
    public static func install(from source: URL, to destination: URL = destinationDirectory) throws {
        let fm = FileManager.default
        let parent = destination.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)

        let staging = parent.appendingPathComponent(
            ".\(destination.lastPathComponent).import-\(UUID().uuidString)"
        )
        do {
            try fm.copyItem(at: source, to: staging)
        } catch {
            try? fm.removeItem(at: staging)
            throw error
        }

        do {
            if fm.fileExists(atPath: destination.path) {
                // Wisselt de mappen om en ruimt de oude op; `staging` bestaat
                // daarna niet meer.
                _ = try fm.replaceItemAt(destination, withItemAt: staging)
            } else {
                try fm.moveItem(at: staging, to: destination)
            }
        } catch {
            try? fm.removeItem(at: staging)
            throw error
        }
    }
}
