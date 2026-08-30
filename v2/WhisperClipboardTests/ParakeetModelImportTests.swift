import XCTest
@testable import WhisperShared

/// Tests voor de pure validatielogica achter de handmatige modelimport op iOS
/// (`ParakeetModelImport`). Geen UIKit, geen echte download: werkt met een
/// tijdelijke map vol nepbestanden in de juiste namen en groottes.
final class ParakeetModelImportTests: XCTestCase {

    /// Bouwt een tijdelijke, geldige modelmap op met alle vereiste bestanden.
    /// `encoderWeightsBytes` maakt het mogelijk om een te klein gewichten-
    /// bestand te simuleren voor de afkeur-test.
    private func makeFixtureDirectory(encoderWeightsBytes: Int) throws -> URL {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("wc-parakeet-import-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)

        // De kleinere bestanden: gewoon aanwezig, inhoud maakt niet uit.
        for file in [
            ParakeetModelImport.RequiredFile.preprocessor,
            ParakeetModelImport.RequiredFile.decoder,
            ParakeetModelImport.RequiredFile.joint,
        ] {
            let dir = root.appendingPathComponent(file)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try Data("vocab".utf8).write(to: root.appendingPathComponent(ParakeetModelImport.RequiredFile.vocabulary))

        // Het encoder-pakket met het gewichtenbestand op de opgegeven grootte.
        let encoderDir = root.appendingPathComponent(ParakeetModelImport.RequiredFile.encoder)
        let weightsDir = encoderDir.appendingPathComponent("weights")
        try fm.createDirectory(at: weightsDir, withIntermediateDirectories: true)
        let weightsURL = encoderDir.appendingPathComponent(ParakeetModelImport.encoderWeightsRelativePath)
        try Data(count: encoderWeightsBytes).write(to: weightsURL)

        return root
    }

    // MARK: - Test 1: volledige, geldige modelmap wordt goedgekeurd

    func testCompleteValidModelDirectoryIsAccepted() throws {
        let fixture = try makeFixtureDirectory(
            encoderWeightsBytes: Int(ParakeetModelImport.minimumEncoderWeightsBytes) + 1_000
        )
        defer { try? FileManager.default.removeItem(at: fixture) }

        switch ParakeetModelImport.validate(directory: fixture) {
        case .success(let validated):
            XCTAssertEqual(validated, fixture)
        case .failure(let error):
            XCTFail("Verwachtte een geldige map, kreeg fout: \(error)")
        }
    }

    // MARK: - Test 2: te klein (of ontbrekend) encoder-gewichtenbestand wordt afgekeurd

    func testTooSmallEncoderWeightsIsRejectedWithReason() throws {
        let tooSmall = 10_000_000 // ruim onder de 300 MB-grens
        let fixture = try makeFixtureDirectory(encoderWeightsBytes: tooSmall)
        defer { try? FileManager.default.removeItem(at: fixture) }

        switch ParakeetModelImport.validate(directory: fixture) {
        case .success:
            XCTFail("Een te klein gewichtenbestand had afgekeurd moeten worden")
        case .failure(let error):
            XCTAssertEqual(
                error,
                .encoderWeightsTooSmall(
                    actualBytes: Int64(tooSmall),
                    minimumBytes: ParakeetModelImport.minimumEncoderWeightsBytes
                )
            )
            XCTAssertTrue(error.localizedDescriptionNL.contains("te klein"))
        }
    }

    func testMissingEncoderWeightsFileIsRejected() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("wc-parakeet-import-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        for file in ParakeetModelImport.RequiredFile.all {
            let path = root.appendingPathComponent(file)
            if file == ParakeetModelImport.RequiredFile.vocabulary {
                try Data("vocab".utf8).write(to: path)
            } else {
                try fm.createDirectory(at: path, withIntermediateDirectories: true)
            }
        }
        // Geen weights/weight.bin geschreven onder Encoder.mlmodelc: simuleert
        // een AirDrop die halverwege het grootste bestand is afgebroken.

        switch ParakeetModelImport.validate(directory: root) {
        case .success:
            XCTFail("Een ontbrekend gewichtenbestand had afgekeurd moeten worden")
        case .failure(let error):
            XCTAssertEqual(
                error,
                .missingFile("\(ParakeetModelImport.RequiredFile.encoder)/\(ParakeetModelImport.encoderWeightsRelativePath)")
            )
        }
    }

    // MARK: - Mapstructuur: submap versus de gekozen map zelf

    func testResolveModelDirectoryFindsNestedSubfolder() throws {
        let fm = FileManager.default
        let parent = fm.temporaryDirectory
            .appendingPathComponent("wc-parakeet-parent-\(UUID().uuidString)")
        let nested = parent.appendingPathComponent(ParakeetModelImport.modelFolderName)
        try fm.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: parent) }

        // Vergelijk op .path: appendingPathComponent(isDirectory: true) voegt een
        // trailing slash toe die URL-gelijkheid zou breken terwijl het dezelfde
        // locatie is.
        XCTAssertEqual(
            ParakeetModelImport.resolveModelDirectory(chosen: parent).path,
            nested.path
        )
    }

    func testResolveModelDirectoryFallsBackToChosenDirectory() throws {
        let fixture = try makeFixtureDirectory(
            encoderWeightsBytes: Int(ParakeetModelImport.minimumEncoderWeightsBytes) + 1
        )
        defer { try? FileManager.default.removeItem(at: fixture) }

        // Geen submap "parakeet-tdt-0.6b-v3" hierin: de gekozen map is dus zelf
        // de modelmap.
        XCTAssertEqual(ParakeetModelImport.resolveModelDirectory(chosen: fixture), fixture)
    }
}
