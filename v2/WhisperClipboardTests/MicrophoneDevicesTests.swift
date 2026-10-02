import AVFoundation
import AudioToolbox
import XCTest
@testable import WhisperClipboard

final class MicrophoneDevicesTests: XCTestCase {
    func testDefaultInputIsOfferedAsAChoice() throws {
        guard let systemDefault = MicrophoneDevices.systemDefault() else {
            throw XCTSkip("Geen macOS-invoerapparaat beschikbaar")
        }
        let choices = MicrophoneDevices.available()
        XCTAssertTrue(choices.contains(where: { $0.id == systemDefault.id }))
        XCTAssertFalse(systemDefault.id.isEmpty)
        XCTAssertFalse(systemDefault.name.isEmpty)
        XCTAssertEqual(Set(choices.map(\.id)).count, choices.count)
    }

    @MainActor
    func testChosenInputCanBeBoundToAnAudioEngine() throws {
        let systemDefault = MicrophoneDevices.systemDefault()
        guard let device = MicrophoneDevices.available().first(where: {
            $0.audioObjectID != systemDefault?.audioObjectID
        }) ?? systemDefault else {
            throw XCTSkip("Geen macOS-invoerapparaat beschikbaar")
        }
        let engine = AVAudioEngine()
        guard let unit = engine.inputNode.audioUnit else {
            return XCTFail("Input AudioUnit ontbreekt")
        }
        var requested = device.audioObjectID
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        XCTAssertEqual(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                                            kAudioUnitScope_Global, 0, &requested, size), noErr)
        var actual = AudioDeviceID(0)
        var readSize = size
        XCTAssertEqual(AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                                            kAudioUnitScope_Global, 0, &actual, &readSize), noErr)
        XCTAssertEqual(actual, device.audioObjectID)
        XCTAssertEqual(MicrophoneDevices.systemDefault()?.id, systemDefault?.id,
                       "Apparaatkeuze mag de macOS-systeemstandaard niet veranderen")
        _ = engine.inputNode.outputFormat(forBus: 0)
        engine.prepare()
        readSize = size
        XCTAssertEqual(AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                                            kAudioUnitScope_Global, 0, &actual, &readSize), noErr)
        XCTAssertEqual(actual, device.audioObjectID)
    }
}
