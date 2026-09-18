import Core
import Foundation
import GRDB
import XCTest
@testable import WhisperShared

/// Tests rond de twee transactievarianten in ``HistoryStore``: meervoudig
/// verwijderen en samenvoegen-met-vervangen. Ze draaien op een in-memory
/// `DatabaseQueue` en raken CloudKit niet aan; de sync-kant wordt gemeten via de
/// `onChange`-hook en het echte pending-journaal.
///
/// Waarom deze bestaan: allebei de acties liepen eerder als een lus van losse
/// mutaties, dus een fout halverwege liet een deel van de selectie verwijderd
/// achter of een samengevoegde opname naast de originelen die weg hadden gemoeten.
@MainActor
final class HistoryTransactionTests: XCTestCase {

    // MARK: - Helpers

    private func makeStore(retention: Int? = nil) throws -> HistoryStore {
        try HistoryStore(dbQueue: try DatabaseQueue(), retentionProvider: { retention })
    }

    private func entry(
        id: String,
        text: String = "Hallo",
        createdAt: String = "2026-06-21T10:00:00+02:00"
    ) -> TranscriptEntry {
        TranscriptEntry(
            id: id, text: text, createdAt: createdAt, name: "",
            pinned: false, language: "nl", model: "parakeet", source: "mic",
            duration: 1.5, segments: []
        )
    }

    private func makeJournal() throws -> HistoryPendingJournal {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("journal-\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return HistoryPendingJournal(fileURL: url)
    }

    // MARK: - deleteMany

    func testDeleteManyRemovesEveryChosenEntryAndKeepsTheRest() throws {
        let store = try makeStore()
        try store.add(entry(id: "a"))
        try store.add(entry(id: "b"))
        try store.add(entry(id: "c"))

        var changes: [HistoryChange] = []
        store.onChange = { changes.append($0) }
        try store.deleteMany(ids: ["a", "b"])

        XCTAssertEqual(try store.allRecordIDs(), ["c"])
        XCTAssertEqual(changes, [.delete(id: "a"), .delete(id: "b")])
    }

    func testDeleteManyWithoutIdsChangesNothing() throws {
        let store = try makeStore()
        try store.add(entry(id: "a"))
        let revision = store.revision

        var changes: [HistoryChange] = []
        store.onChange = { changes.append($0) }
        try store.deleteMany(ids: [])

        XCTAssertEqual(try store.allRecordIDs(), ["a"])
        XCTAssertTrue(changes.isEmpty)
        XCTAssertEqual(store.revision, revision)
    }

    // MARK: - mergeAndReplace

    func testMergeAndReplaceRemovesOriginalsAndAddsTheMergedEntry() throws {
        let store = try makeStore()
        try store.add(entry(id: "a", text: "eerste"))
        try store.add(entry(id: "b", text: "tweede"))

        let journal = try makeJournal()
        store.onChange = { journal.append($0) }
        try store.mergeAndReplace(
            merged: entry(id: "m", text: "eerste tweede"),
            deleting: ["a", "b"]
        )

        XCTAssertEqual(try store.allRecordIDs(), ["m"])
        XCTAssertEqual(try store.record(id: "m")?.text, "eerste tweede")
        XCTAssertEqual(journal.pending(), [
            .delete(id: "a"),
            .delete(id: "b"),
            .upsert(id: "m")
        ])
    }

    /// De samengevoegde opname krijgt hier bewust een id die al bestaat, zodat de
    /// insert stukloopt nádat de originelen in dezelfde transactie zijn verwijderd.
    /// Slaat de terugdraaiing over, dan zijn "a" en "b" weg én is er niets voor
    /// teruggekomen: precies het gegevensverlies dat deze transactie moet uitsluiten.
    func testFailedMergeLeavesEveryEntryAndTheJournalUntouched() throws {
        let store = try makeStore()
        try store.add(entry(id: "a", text: "eerste"))
        try store.add(entry(id: "b", text: "tweede"))
        try store.add(entry(id: "botsing", text: "bestaat al"))

        let journal = try makeJournal()
        store.onChange = { journal.append($0) }

        XCTAssertThrowsError(
            try store.mergeAndReplace(
                merged: entry(id: "botsing", text: "samengevoegd"),
                deleting: ["a", "b"]
            )
        )

        XCTAssertEqual(try store.allRecordIDs(), ["a", "b", "botsing"])
        XCTAssertEqual(try store.record(id: "botsing")?.text, "bestaat al")
        XCTAssertTrue(journal.pending().isEmpty)
    }

    /// Samenvoegen moet hetzelfde bewaarlimiet respecteren als `add(_:)`, en de
    /// rijen die daardoor sneuvelen moeten óók als sync-verwijdering naar buiten.
    func testMergeAndReplaceAppliesRetentionAndReportsPrunedEntries() throws {
        let store = try makeStore(retention: 2)
        try store.add(entry(id: "oud", createdAt: "2026-06-21T10:00:00+02:00"))
        try store.add(entry(id: "nieuw", createdAt: "2026-06-21T11:00:00+02:00"))

        var changes: [HistoryChange] = []
        store.onChange = { changes.append($0) }
        // Niets te verwijderen, dus de derde opname duwt de oudste over de limiet.
        try store.mergeAndReplace(
            merged: entry(id: "m", createdAt: "2026-06-21T12:00:00+02:00"),
            deleting: []
        )

        XCTAssertEqual(try store.allRecordIDs(), ["m", "nieuw"])
        XCTAssertEqual(changes, [.upsert(id: "m"), .delete(id: "oud")])
    }
}
