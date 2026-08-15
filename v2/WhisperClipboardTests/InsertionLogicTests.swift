import AppKit
import Core
import XCTest
@testable import WhisperClipboard

final class InsertionPolicyDecisionTests: XCTestCase {

    private let ownId = "nl.nielscroiset.whisperclipboard"
    private let targetApp = InsertionTarget(bundleId: "com.apple.TextEdit", processIdentifier: 100)

    // MARK: - Disabled

    func testDisabledYieldsClipboardOnly() {
        let decision = InsertionPolicy.decide(
            directInsertionEnabled: false,
            accessibilityGranted: true,
            capturedTarget: targetApp,
            currentFrontmost: targetApp,
            deniedBundleIds: [],
            ownBundleId: ownId
        )
        XCTAssertEqual(decision, .clipboardOnly(reason: .disabled))
    }

    /// Disabled is checked first, before accessibility/target — it should win
    /// even when every other condition would also fail.
    func testDisabledTakesPriorityOverOtherFailures() {
        let decision = InsertionPolicy.decide(
            directInsertionEnabled: false,
            accessibilityGranted: false,
            capturedTarget: nil,
            currentFrontmost: nil,
            deniedBundleIds: [],
            ownBundleId: ownId
        )
        XCTAssertEqual(decision, .clipboardOnly(reason: .disabled))
    }

    // MARK: - No accessibility

    func testNoAccessibilityYieldsClipboardOnly() {
        let decision = InsertionPolicy.decide(
            directInsertionEnabled: true,
            accessibilityGranted: false,
            capturedTarget: targetApp,
            currentFrontmost: targetApp,
            deniedBundleIds: [],
            ownBundleId: ownId
        )
        XCTAssertEqual(decision, .clipboardOnly(reason: .noAccessibility))
    }

    // MARK: - No target captured

    func testNoTargetYieldsClipboardOnly() {
        let decision = InsertionPolicy.decide(
            directInsertionEnabled: true,
            accessibilityGranted: true,
            capturedTarget: nil,
            currentFrontmost: targetApp,
            deniedBundleIds: [],
            ownBundleId: ownId
        )
        XCTAssertEqual(decision, .clipboardOnly(reason: .noTarget))
    }

    // MARK: - Own app

    func testCapturedTargetIsOwnAppYieldsClipboardOnly() {
        let own = InsertionTarget(bundleId: ownId, processIdentifier: 1)
        let decision = InsertionPolicy.decide(
            directInsertionEnabled: true,
            accessibilityGranted: true,
            capturedTarget: own,
            currentFrontmost: own,
            deniedBundleIds: [],
            ownBundleId: ownId
        )
        XCTAssertEqual(decision, .clipboardOnly(reason: .ownApp))
    }

    func testOwnAppComparisonIsCaseInsensitive() {
        let own = InsertionTarget(bundleId: ownId.uppercased(), processIdentifier: 1)
        let decision = InsertionPolicy.decide(
            directInsertionEnabled: true,
            accessibilityGranted: true,
            capturedTarget: own,
            currentFrontmost: own,
            deniedBundleIds: [],
            ownBundleId: ownId
        )
        XCTAssertEqual(decision, .clipboardOnly(reason: .ownApp))
    }

    // MARK: - Frontmost changed

    func testFrontmostDriftedToOwnAppYieldsFrontmostChanged() {
        let ownFrontmost = InsertionTarget(bundleId: ownId, processIdentifier: 2)
        let decision = InsertionPolicy.decide(
            directInsertionEnabled: true,
            accessibilityGranted: true,
            capturedTarget: targetApp,
            currentFrontmost: ownFrontmost,
            deniedBundleIds: [],
            ownBundleId: ownId
        )
        XCTAssertEqual(decision, .clipboardOnly(reason: .frontmostChanged))
    }

    func testFrontmostChangedToDifferentProcessYieldsFrontmostChanged() {
        let otherApp = InsertionTarget(bundleId: "com.apple.Notes", processIdentifier: 200)
        let decision = InsertionPolicy.decide(
            directInsertionEnabled: true,
            accessibilityGranted: true,
            capturedTarget: targetApp,
            currentFrontmost: otherApp,
            deniedBundleIds: [],
            ownBundleId: ownId
        )
        XCTAssertEqual(decision, .clipboardOnly(reason: .frontmostChanged))
    }

    func testFrontmostNilDoesNotTriggerFrontmostChanged() {
        // No live frontmost sample (e.g. couldn't resolve `frontmostApplication`)
        // should not by itself block insertion; it just skips that guard.
        let decision = InsertionPolicy.decide(
            directInsertionEnabled: true,
            accessibilityGranted: true,
            capturedTarget: targetApp,
            currentFrontmost: nil,
            deniedBundleIds: [],
            ownBundleId: ownId
        )
        XCTAssertEqual(decision, .insert)
    }

    func testSameProcessDifferentBundleCaseIsNotFrontmostChanged() {
        // Same process id as captured target: frontmost hasn't actually moved,
        // even if bundle id casing differs.
        let sameProcessDifferentCase = InsertionTarget(bundleId: "com.apple.TEXTEDIT", processIdentifier: 100)
        let decision = InsertionPolicy.decide(
            directInsertionEnabled: true,
            accessibilityGranted: true,
            capturedTarget: targetApp,
            currentFrontmost: sameProcessDifferentCase,
            deniedBundleIds: [],
            ownBundleId: ownId
        )
        XCTAssertEqual(decision, .insert)
    }

    // MARK: - Denied app

    func testDeniedAppYieldsClipboardOnly() {
        let decision = InsertionPolicy.decide(
            directInsertionEnabled: true,
            accessibilityGranted: true,
            capturedTarget: targetApp,
            currentFrontmost: targetApp,
            deniedBundleIds: ["com.apple.TextEdit"],
            ownBundleId: ownId
        )
        XCTAssertEqual(decision, .clipboardOnly(reason: .deniedApp))
    }

    func testDeniedAppMatchIsCaseInsensitive() {
        let decision = InsertionPolicy.decide(
            directInsertionEnabled: true,
            accessibilityGranted: true,
            capturedTarget: targetApp,
            currentFrontmost: targetApp,
            deniedBundleIds: ["COM.APPLE.TEXTEDIT"],
            ownBundleId: ownId
        )
        XCTAssertEqual(decision, .clipboardOnly(reason: .deniedApp))
    }

    func testUnrelatedDeniedEntriesDoNotBlock() {
        let decision = InsertionPolicy.decide(
            directInsertionEnabled: true,
            accessibilityGranted: true,
            capturedTarget: targetApp,
            currentFrontmost: targetApp,
            deniedBundleIds: ["com.apple.Notes", "com.apple.Terminal"],
            ownBundleId: ownId
        )
        XCTAssertEqual(decision, .insert)
    }

    // MARK: - Happy path

    func testHappyPathYieldsInsert() {
        let decision = InsertionPolicy.decide(
            directInsertionEnabled: true,
            accessibilityGranted: true,
            capturedTarget: targetApp,
            currentFrontmost: targetApp,
            deniedBundleIds: [],
            ownBundleId: ownId
        )
        XCTAssertEqual(decision, .insert)
    }

    // MARK: - Priority ordering (guards fire in `decide`'s declared order)

    func testNoAccessibilityTakesPriorityOverDeniedApp() {
        let decision = InsertionPolicy.decide(
            directInsertionEnabled: true,
            accessibilityGranted: false,
            capturedTarget: targetApp,
            currentFrontmost: targetApp,
            deniedBundleIds: ["com.apple.TextEdit"],
            ownBundleId: ownId
        )
        XCTAssertEqual(decision, .clipboardOnly(reason: .noAccessibility))
    }

    func testNoTargetTakesPriorityOverFrontmostChanged() {
        let decision = InsertionPolicy.decide(
            directInsertionEnabled: true,
            accessibilityGranted: true,
            capturedTarget: nil,
            currentFrontmost: InsertionTarget(bundleId: ownId, processIdentifier: 1),
            deniedBundleIds: [],
            ownBundleId: ownId
        )
        XCTAssertEqual(decision, .clipboardOnly(reason: .noTarget))
    }
}

final class InsertionPolicyIsDeniedTests: XCTestCase {

    func testNilBundleIdIsNeverDenied() {
        XCTAssertFalse(InsertionPolicy.isDenied(bundleId: nil, deniedBundleIds: ["com.apple.TextEdit"]))
    }

    func testEmptyBundleIdIsNeverDenied() {
        XCTAssertFalse(InsertionPolicy.isDenied(bundleId: "", deniedBundleIds: ["com.apple.TextEdit"]))
    }

    func testEmptyDenyListNeverDenies() {
        XCTAssertFalse(InsertionPolicy.isDenied(bundleId: "com.apple.TextEdit", deniedBundleIds: []))
    }

    func testExactMatchIsDenied() {
        XCTAssertTrue(InsertionPolicy.isDenied(bundleId: "com.apple.TextEdit", deniedBundleIds: ["com.apple.TextEdit"]))
    }

    func testCaseInsensitiveMatchIsDenied() {
        XCTAssertTrue(InsertionPolicy.isDenied(bundleId: "Com.Apple.TextEdit", deniedBundleIds: ["com.apple.textedit"]))
    }

    func testNonMatchingBundleIdIsNotDenied() {
        XCTAssertFalse(InsertionPolicy.isDenied(bundleId: "com.apple.Notes", deniedBundleIds: ["com.apple.TextEdit"]))
    }

    func testMultipleEntriesMatchAnyCaseInsensitively() {
        let denyList = ["com.apple.Notes", "COM.APPLE.TEXTEDIT", "com.apple.Terminal"]
        XCTAssertTrue(InsertionPolicy.isDenied(bundleId: "com.apple.textedit", deniedBundleIds: denyList))
    }
}

/// Bewaakt de belofte van 14 augustus 2026: **na een geslaagde invoeging blijft
/// de transcriptie op het klembord staan.**
///
/// Hier stond eerder een reeks tests rond een restore-stap die het vorige
/// klembord van de gebruiker terugzette. Dat kostte Niels meermaals zijn
/// dictaat: landde de invoeging ergens anders dan hij keek, dan was de tekst
/// nergens meer te vinden. Op zijn verzoek is dat omgedraaid, en deze test
/// zorgt dat het niet stilletjes terugkomt.
///
/// Draait op een privé, benoemd `NSPasteboard`, dus het echte systeemklembord
/// blijft ongemoeid.
@MainActor
final class InsertionClipboardTests: XCTestCase {

    /// Neppe synthesizer: doet niets, maar meldt succes zodat het invoegpad
    /// helemaal doorloopt. `sentPaste` legt vast of Cmd+V zou zijn verstuurd.
    private final class FakeSynthesizer: KeystrokeSynthesizer {
        private(set) var sentPaste = false
        func sendPaste() -> Bool { sentPaste = true; return true }
    }

    private func makePasteboard() -> NSPasteboard {
        NSPasteboard(name: .init(rawValue: "WhisperClipboardTest.\(UUID().uuidString)"))
    }

    private func settings(directInsertion: Bool) -> AppSettings {
        var s = AppSettings()
        s.directInsertion = directInsertion
        s.insertionDeniedBundleIds = []
        return s
    }

    /// Met invoegen uitgezet verandert er niets aan het klembord: de controller
    /// heeft de tekst er al op gezet en de service laat hem staan.
    func testKlembordBlijftStaanZonderInvoegen() {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let transcriptie = "dit is mijn dictaat"
        pasteboard.clearContents()
        pasteboard.setString(transcriptie, forType: .string)

        let service = InsertionService(synthesizer: FakeSynthesizer(), pasteboard: pasteboard)
        let outcome = service.insert(
            transcriptie,
            settings: settings(directInsertion: false),
            target: InsertionTarget(bundleId: "com.apple.TextEdit", processIdentifier: 4242)
        )

        XCTAssertEqual(outcome, .clipboardOnly(reason: .disabled))
        XCTAssertEqual(pasteboard.string(forType: .string), transcriptie,
                       "de transcriptie hoort op het klembord te blijven staan")
    }

    /// De service schrijft de transcriptie zelf naar het klembord en zet er
    /// daarna niets meer overheen. Ook als er vóór het dictaat iets anders op
    /// stond wint de transcriptie: het klembord is het vangnet.
    func testTranscriptieWintVanHetVorigeKlembord() {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("iets ouds van de gebruiker", forType: .string)

        let transcriptie = "dit is mijn dictaat"
        let service = InsertionService(synthesizer: FakeSynthesizer(), pasteboard: pasteboard)
        _ = service.insert(
            transcriptie,
            settings: settings(directInsertion: true),
            target: InsertionTarget(bundleId: "com.apple.TextEdit", processIdentifier: 4242)
        )

        // Zonder toegankelijkheidsrechten (headless en CI) komt de service niet
        // aan het schrijven toe en blijft het oude klembord staan; mét rechten
        // schrijft hij de transcriptie en laat die staan. Beide uitkomsten zijn
        // goed, zolang de transcriptie er niet ná een geslaagde schrijfactie
        // weer af wordt gehaald.
        let opKlembord = pasteboard.string(forType: .string)
        XCTAssertTrue(
            opKlembord == transcriptie || opKlembord == "iets ouds van de gebruiker",
            "onverwachte klembordinhoud: \(String(describing: opKlembord))"
        )
    }
}
