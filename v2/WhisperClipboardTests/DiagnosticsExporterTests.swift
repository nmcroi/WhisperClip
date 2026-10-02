import Foundation
import XCTest
@testable import WhisperClipboard

final class DiagnosticsExporterTests: XCTestCase {
    func testLogExportUsesAllowlistedEventsWithoutPrivateData() {
        let log = """
        [2026-10-02T10:00:00Z] LaunchHealth: AudioEngine: formaatverschil bij input 42 (hardware 24000 Hz/1 ch, client 48000 Hz/1 ch); nieuwe engine aangemaakt
        [2026-10-02T10:01:00Z] LaunchHealth: Invoegen: keuze=clipboardOnly(reason: targetChanged), AX=true, doel=com.secret.notes/12, actief=com.secret.mail/14
        [2026-10-02T10:02:00Z] LaunchHealth: Dictaat private-id: invoegresultaat=inserted
        [2026-10-02T10:03:00Z] LaunchHealth: transcript=Een zeer privé zin
        """
        let output = DiagnosticsExporter.sanitizedEvents(from: log).joined(separator: "\n")
        XCTAssertTrue(output.contains("microfoonformaat gewijzigd"))
        XCTAssertTrue(output.contains("tekst op klembord"))
        XCTAssertFalse(output.contains("com.secret"))
        XCTAssertFalse(output.contains("private-id"))
        XCTAssertFalse(output.contains("privé zin"))
        XCTAssertTrue(output.contains("hardware 24000 Hz/1 ch; client 48000 Hz/1 ch"))
    }

    func testCrashExportAllowsOnlySafeSymbols() {
        let report = """
        {"timestamp":"2026-10-02T10:00:00Z"}
        {"captureTime":"2026-10-02T10:00:00Z","exception":{"type":"EXC_BAD_ACCESS","signal":"SIGSEGV","subtype":"/Users/private/secret"},"faultingThread":0,"threads":[{"frames":[{"symbol":"swift_task_isCurrentExecutor"},{"symbol":"/Users/private/secret"}]}]}
        """
        let output = DiagnosticsExporter.crashSummary(from: Data(report.utf8)) ?? ""
        XCTAssertTrue(output.contains("EXC_BAD_ACCESS"))
        XCTAssertTrue(output.contains("swift_task_isCurrentExecutor"))
        XCTAssertFalse(output.contains("/Users/"))
        XCTAssertFalse(output.contains("secret"))
    }
}
