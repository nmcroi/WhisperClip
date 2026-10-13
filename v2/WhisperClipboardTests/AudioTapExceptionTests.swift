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
    func testStableInputRequiresConsecutiveMatchingFormats() {
        let bluetooth = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!
        let previous = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        var stability = AudioInputStability()
        XCTAssertFalse(stability.observe(hardware: bluetooth, client: previous))
        XCTAssertFalse(stability.observe(hardware: bluetooth, client: bluetooth))
        XCTAssertTrue(stability.observe(hardware: bluetooth, client: bluetooth))
    }

    func testRouteChangesAndMismatchesResetStability() {
        let mono = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let stereo = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        let bluetooth = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!
        var stability = AudioInputStability()
        XCTAssertFalse(stability.observe(hardware: mono, client: mono))
        XCTAssertFalse(stability.observe(hardware: stereo, client: stereo))
        XCTAssertFalse(stability.observe(hardware: stereo, client: mono))
        XCTAssertFalse(stability.observe(hardware: stereo, client: stereo))
        XCTAssertTrue(stability.observe(hardware: stereo, client: stereo))
        XCTAssertFalse(stability.observe(hardware: bluetooth, client: bluetooth))
        XCTAssertTrue(stability.observe(hardware: bluetooth, client: bluetooth))
    }

}
