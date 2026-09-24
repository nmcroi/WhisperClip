import AVFoundation
import Core
import XCTest
@testable import WhisperClipboard

/// Bewijst dat het ObjC-vangnet precies de exceptie vangt die op 23 september
/// 2026 de crashfamilie van 2.0.2 tot 2.0.5 veroorzaakte: `installTap` met een
/// formaat dat niet bij de hardware past.
@MainActor
final class AudioTapExceptionTests: XCTestCase {

    func testFormaatverschilBijInstallTapWordtEenSwiftFout() throws {
        let engine = AVAudioEngine()
        let node = engine.inputNode
        let hardware = node.inputFormat(forBus: 0)
        try XCTSkipIf(hardware.sampleRate == 0, "Geen invoerapparaat op deze testmachine")

        // Bewust een ander formaat dan de hardware levert.
        let wrong = AVAudioFormat(standardFormatWithSampleRate: hardware.sampleRate == 8_000 ? 16_000 : 8_000, channels: 1)!
        defer { node.removeTap(onBus: 0) }

        XCTAssertThrowsError(try catchingObjCException {
            node.installTap(onBus: 0, bufferSize: 4096, format: wrong) { _, _ in }
        }) { error in
            let objc = error as? ObjCExceptionError
            XCTAssertNotNil(objc, "verwachtte een opgevangen NSException, kreeg \(error)")
            XCTAssertTrue(objc?.reason.localizedCaseInsensitiveContains("format") ?? false, objc?.reason ?? "")
        }
    }
}
