import XCTest
import WhisperShared

final class AudioStorageAlarmTests: XCTestCase {
    private let gb: Int64 = 1_000_000_000

    func testOnderVijfGBNooitWaarschuwen() {
        XCTAssertNil(AudioStorageAlarm.stepToWarn(bytes: 4 * gb, lastWarnedStep: 0).warn)
    }

    func testEersteKeerBovenVijfGBWaarschuwtEenKeer() {
        let first = AudioStorageAlarm.stepToWarn(bytes: 5 * gb + 1, lastWarnedStep: 0)
        XCTAssertEqual(first.warn, 1)
        let again = AudioStorageAlarm.stepToWarn(bytes: 6 * gb, lastWarnedStep: first.remember)
        XCTAssertNil(again.warn, "zelfde stap, geen tweede seintje")
    }

    func testVolgendeStapWaarschuwtOpnieuw() {
        XCTAssertEqual(AudioStorageAlarm.stepToWarn(bytes: 10 * gb, lastWarnedStep: 1).warn, 2)
    }

    func testKrimpenZetDeTellerTerug() {
        let shrunk = AudioStorageAlarm.stepToWarn(bytes: 3 * gb, lastWarnedStep: 1)
        XCTAssertNil(shrunk.warn)
        XCTAssertEqual(shrunk.remember, 0)
        XCTAssertEqual(AudioStorageAlarm.stepToWarn(bytes: 5 * gb, lastWarnedStep: shrunk.remember).warn, 1)
    }
}
