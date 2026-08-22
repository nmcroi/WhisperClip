import XCTest
@testable import WhisperClipboard

/// Tests voor de pure logica in `LaunchHealthEvaluator`: geen bestandssysteem,
/// alleen de afleiding uit (markerAanwezig, markerInhoud) en het bijhouden van
/// de geschiedenislijst op tien (22 augustus 2026).
final class LaunchHealthTests: XCTestCase {

    // MARK: - evaluate

    func testGeenMarkerIsSchoon() {
        let outcome = LaunchHealthEvaluator.evaluate(markerAanwezig: false, markerInhoud: nil)
        XCTAssertEqual(outcome, .schoon)
    }

    func testMarkerMetFaseIsOnverwacht() {
        let inhoud = "started=2026-08-22T10:00:00Z\nversion=1.0\nbuild=1\nfase=transcribing\n"
        let outcome = LaunchHealthEvaluator.evaluate(markerAanwezig: true, markerInhoud: inhoud)
        XCTAssertEqual(outcome, .onverwacht(fase: "transcribing"))
    }

    func testMarkerZonderLeesbareFaseIsOnbekend() {
        let outcome = LaunchHealthEvaluator.evaluate(markerAanwezig: true, markerInhoud: "kapotte inhoud")
        XCTAssertEqual(outcome, .onverwacht(fase: "onbekend"))
    }

    func testMarkerAanwezigMaarInhoudOnleesbaarIsOnbekend() {
        let outcome = LaunchHealthEvaluator.evaluate(markerAanwezig: true, markerInhoud: nil)
        XCTAssertEqual(outcome, .onverwacht(fase: "onbekend"))
    }

    func testFaseRegelKanTussenAndereRegelsStaan() {
        let inhoud = "started=2026-08-22T10:00:00Z\nfase=recording\nversion=1.0\n"
        let outcome = LaunchHealthEvaluator.evaluate(markerAanwezig: true, markerInhoud: inhoud)
        XCTAssertEqual(outcome, .onverwacht(fase: "recording"))
    }

    // MARK: - appending (geschiedenis op tien houden)

    private func entry(_ startedAt: String) -> LaunchHistoryEntry {
        LaunchHistoryEntry(startedAt: startedAt, version: "1.0", outcome: "schoon", fase: nil)
    }

    func testAppendingAanLegeGeschiedenis() {
        let result = LaunchHealthEvaluator.appending(entry("1"), to: [])
        XCTAssertEqual(result.map(\.startedAt), ["1"])
    }

    func testNieuwsteStaatVooraan() {
        let history = [entry("2"), entry("1")]
        let result = LaunchHealthEvaluator.appending(entry("3"), to: history)
        XCTAssertEqual(result.map(\.startedAt), ["3", "2", "1"])
    }

    func testGeschiedenisBlijftOpTien() {
        let history = (1...10).reversed().map { entry("\($0)") } // 10..1, nieuwste eerst
        let result = LaunchHealthEvaluator.appending(entry("11"), to: history)
        XCTAssertEqual(result.count, 10)
        XCTAssertEqual(result.first?.startedAt, "11")
        XCTAssertEqual(result.last?.startedAt, "2") // "1" viel eraf
    }

    func testGeschiedenisOnderTienBlijftGewoonGroeien() {
        let history = [entry("3"), entry("2"), entry("1")]
        let result = LaunchHealthEvaluator.appending(entry("4"), to: history)
        XCTAssertEqual(result.count, 4)
    }
}
