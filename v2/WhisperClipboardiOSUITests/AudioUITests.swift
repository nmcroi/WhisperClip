import XCTest

@MainActor
final class AudioUITests: XCTestCase {
    private let app = XCUIApplication()
    override func setUpWithError() throws { continueAfterFailure = false }
    private func launch(language: String = "nl", appearance: String = "dark", show: Bool = false, large: Bool = false) {
        app.launchArguments = ["-ios.interfaceLanguage", language, "-ios.appearance", appearance,
            "-ios.showAudioRetentionOption", show ? "YES" : "NO", "-ios.icloudSyncEnabled", "NO"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        if app.alerts.firstMatch.waitForExistence(timeout: 1) { app.alerts.firstMatch.buttons.firstMatch.tap() }
    }
    private func screenshot(_ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
    }
    func testNativeTabsAndNoteRecordingButtonRemainReachable() {
        launch(show: true, large: true)
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 5))
        tabs.buttons["Notities"].tap()
        let record = app.buttons["Nieuwe notitie (start direct met opnemen)"]
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        XCTAssertTrue(record.isHittable)
        XCTAssertLessThanOrEqual(record.frame.maxY, tabs.frame.minY)
        screenshot("restored-native-tabs-notes-large")
    }
    func testICloudOptOutSurvivesRelaunch() {
        launch()
        app.buttons["settings.open"].tap()
        app.staticTexts["Synchronisatie"].tap()
        let sync = app.switches["Synchroniseren via iCloud"]
        XCTAssertTrue(sync.waitForExistence(timeout: 5))
        // Persist a deliberate on -> off choice in this isolated simulator.
        sync.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(sync.value as? String, "1")
        sync.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(sync.value as? String, "0")
        app.terminate()
        // No command-line sync override: exercise the actual saved preference.
        app.launchArguments = ["-ios.interfaceLanguage", "nl", "-ios.appearance", "dark"]
        app.launch()
        app.buttons["settings.open"].tap()
        app.staticTexts["Synchronisatie"].tap()
        XCTAssertTrue(sync.waitForExistence(timeout: 5))
        XCTAssertEqual(sync.value as? String, "0")
    }

    func testDefaultIsQuietAndSettingCanBeEnabled() {
        launch()
        XCTAssertFalse(app.switches["audio.keepThisRecording"].exists)
        app.buttons["settings.open"].tap()
        let recordingSettings = app.staticTexts["Opnemen en transcriptie"]
        XCTAssertTrue(recordingSettings.waitForExistence(timeout: 5))
        recordingSettings.tap()
        let option = app.switches["audio.showOption"]
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        XCTAssertEqual(option.value as? String, "0")
        option.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '1'"), object: option)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 3), .completed)
        XCTAssertEqual(option.value as? String, "1")
        screenshot("nl-settings-audio-enabled")
    }
    func testChoiceResetsAfterRelaunchAndNotulistHasNoChoice() {
        launch(show: true)
        let choice = app.switches["audio.keepThisRecording"]
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        XCTAssertEqual(choice.value as? String, "0")
        choice.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(choice.value as? String, "1")
        app.terminate()
        launch(show: true)
        XCTAssertEqual(app.switches["audio.keepThisRecording"].value as? String, "0")
        app.tabBars.buttons["Notulist"].tap()
        XCTAssertFalse(app.switches["audio.keepThisRecording"].exists)
        screenshot("nl-notulist-no-audio-choice")
    }
    // Prepare with scripts/seed_audio_review.py on the dedicated review simulator.
    func testSeededAudioPlaybackExportAndAudioOnlyDeletion() throws {
        launch()
        app.tabBars.buttons["Geschiedenis"].tap()
        let fixture = app.staticTexts["Audio review fixture"].firstMatch
        guard fixture.waitForExistence(timeout: 5) else {
            throw XCTSkip("Run seed_audio_review.py on the isolated review simulator first")
        }
        fixture.tap()
        let play = app.buttons["audio.playPause"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        play.tap()
        XCTAssertTrue(app.sliders.firstMatch.waitForExistence(timeout: 3))
        screenshot("nl-audio-playback")
        app.buttons["audio.exportM4A"].tap()
        let dutchClose = app.buttons["Sluit"].firstMatch
        let close = app.buttons["Close"].firstMatch
        XCTAssertTrue(dutchClose.waitForExistence(timeout: 10) || close.exists)
        screenshot("nl-m4a-share-sheet")
        if dutchClose.exists { dutchClose.tap() } else { close.tap() }
        app.buttons["audio.remove"].tap()
        let confirmation = app.alerts.firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 3))
        confirmation.buttons["Alleen audio verwijderen"].tap()
        XCTAssertTrue(app.staticTexts["Geen audio op dit apparaat"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Synthetische testaudio, geen echte opname."].exists)
        screenshot("nl-audio-only-deleted-text-retained")
    }
    func testVisibleChoiceLanguageAndAppearanceMatrix() {
        for language in ["nl", "en", "de"] {
            for appearance in ["light", "dark"] {
                launch(language: language, appearance: appearance, show: true, large: true)
                let choice = app.switches["audio.keepThisRecording"]
                XCTAssertTrue(choice.waitForExistence(timeout: 5))
                XCTAssertTrue(choice.isHittable)
                screenshot("\(language)-\(appearance)-audio-large-text")
                app.terminate()
            }
        }
    }
}
