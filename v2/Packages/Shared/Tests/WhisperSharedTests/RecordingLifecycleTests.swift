import AVFoundation
import Core
import Foundation
import GRDB
import XCTest
@testable import WhisperShared

@MainActor
final class RecordingLifecycleTests: XCTestCase {
    private var root: URL!
    private var repo: RecordingRepository!
    private var db: DatabaseQueue!
    private var store: HistoryStore!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("wc-lifecycle-" + UUID().uuidString)
        repo = RecordingRepository(root: root)
        db = try DatabaseQueue()
        store = try HistoryStore(dbQueue: db, retentionProvider: { nil }, recordingRepository: repo)
    }
    override func tearDown() async throws { try? FileManager.default.removeItem(at: root) }

    private func session(_ id: String = UUID().uuidString, keep: Bool = true, source: String = "mic.ios", noteID: String? = nil) throws -> RecordingSession {
        var session = RecordingSession(id: id, source: source, language: "nl", noteID: noteID, keepAudio: keep)
        session.entry = session.transcript(text: "test", segments: [], duration: 1)
        try repo.save(session)
        try Data("audio".utf8).write(to: repo.audioURL(id))
        return session
    }
    private func finish(_ session: RecordingSession) throws {
        try store.commitRecording(session, entry: XCTUnwrap(session.entry))
    }

    func testDiskFullDuringJournalWriteKeepsPriorResultAndAudioForRetry() throws {
        let s = try session(keep: false)
        let fullDisk = RecordingRepository(root: root, writeJournal: { _, _ in
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))
        })
        let failing = try HistoryStore(dbQueue: db, retentionProvider: { nil }, recordingRepository: fullDisk)
        XCTAssertThrowsError(try failing.commitRecording(s, entry: s.entry!))
        XCTAssertFalse(try store.containsTranscript(s.id))
        XCTAssertEqual(try repo.load(s.id).entry, s.entry)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try repo.audioURL(s.id).path))
        try finish(s)
        XCTAssertEqual(try store.entries().map(\.id), [s.id])
        XCTAssertTrue(try repo.pendingIDs().isEmpty)
    }
    func testPreparedRetryContinuesPastDamagedJournalAndDoesNotCommitRawText() throws {
        var prepared = try session("z-prepared")
        prepared.resultIsProcessed = true
        try repo.save(prepared)
        let raw = try session("raw")
        try repo.prepareDirectory(repo.sessionDirectory("a-damaged"))
        store.retryPreparedAudio()
        XCTAssertTrue(try store.containsTranscript(prepared.id))
        XCTAssertFalse(try store.containsTranscript(raw.id))
        XCTAssertNotNil(store.audioStorageError)
        XCTAssertNotNil(repo.savedAudio(prepared.id))
    }
    func testDefaultDoesNotKeepButKeepsRecoveryUntilCommit() throws {
        let s = try session(keep: false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try repo.audioURL(s.id).path))
        try finish(s)
        XCTAssertTrue(try store.containsTranscript(s.id))
        XCTAssertNil(repo.savedAudio(s.id))
        XCTAssertTrue(try repo.pending().isEmpty)
    }
    func testDatabaseFailureLeavesRecoverableAudioAndResult() throws {
        let s = try session(keep: false)
        try db.write { try $0.execute(sql: "CREATE TRIGGER fail_insert BEFORE INSERT ON transcripts BEGIN SELECT RAISE(ABORT, 'disk full'); END") }
        XCTAssertThrowsError(try finish(s))
        XCTAssertEqual(try repo.load(s.id).entry?.text, "test")
        XCTAssertTrue(FileManager.default.fileExists(atPath: try repo.audioURL(s.id).path))
        try db.write { try $0.execute(sql: "DROP TRIGGER fail_insert") }
        let reopened = try HistoryStore(dbQueue: db, retentionProvider: { nil }, recordingRepository: repo)
        try reopened.commitRecording(repo.load(s.id), entry: XCTUnwrap(s.entry))
        XCTAssertEqual(try reopened.allRecordIDs(), [s.id])
    }
    func testMoveFailureThenRetryDoesNotDuplicateTranscript() throws {
        let s = try session()
        try Data("not a directory".utf8).write(to: repo.recordingsDirectory)
        XCTAssertThrowsError(try finish(s))
        XCTAssertTrue(try store.containsTranscript(s.id))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try repo.audioURL(s.id).path))
        try FileManager.default.removeItem(at: repo.recordingsDirectory)
        try finish(repo.load(s.id))
        XCTAssertEqual(try store.allRecordIDs(), [s.id])
        XCTAssertNotNil(repo.savedAudio(s.id))
    }
    func testCrashAfterFileMoveFinishesWithoutLosingAudio() throws {
        let s = try session()
        try db.write { db in
            try TranscriptRecord(entry: s.entry!).insert(db)
            try db.execute(sql: "INSERT INTO recording_commits(id) VALUES (?)", arguments: [s.id])
        }
        try repo.prepareDirectory(repo.recordingsDirectory)
        try FileManager.default.moveItem(at: repo.audioURL(s.id), to: repo.recordingsDirectory.appendingPathComponent(s.id + ".caf"))
        try finish(repo.load(s.id))
        XCTAssertNotNil(repo.savedAudio(s.id))
        XCTAssertTrue(try repo.pending().isEmpty)
    }
    func testDeletionCancelsUnfinishedCommitAndCannotResurrect() throws {
        let s = try session()
        try Data().write(to: repo.recordingsDirectory)
        XCTAssertThrowsError(try finish(s))
        try FileManager.default.removeItem(at: repo.recordingsDirectory)
        try store.delete(id: s.id)
        try finish(s) // simulate a stale completion arriving after the delete
        XCTAssertFalse(try store.containsTranscript(s.id))
        XCTAssertNil(repo.savedAudio(s.id))
        XCTAssertTrue(try repo.pending().isEmpty)
    }
    func testRemoteDeletionAlsoRemovesAudio() throws {
        let s = try session(); try finish(s)
        try store.applyRemoteDelete(id: s.id)
        XCTAssertNil(repo.savedAudio(s.id))
    }
    func testRetentionAlsoRemovesAudio() throws {
        let limited = try HistoryStore(dbQueue: db, retentionProvider: { 1 }, recordingRepository: repo)
        let a = try session("old"); try limited.commitRecording(a, entry: a.entry!)
        var b = try session("new"); b.entry?.createdAt = "2099-01-01T00:00:00Z"
        try limited.commitRecording(b, entry: b.entry!)
        XCTAssertNil(repo.savedAudio(a.id)); XCTAssertNotNil(repo.savedAudio(b.id))
    }
    func testMeetingCannotRetainEvenIfLegacyPreferenceIsTrue() throws {
        var s = try session(keep: true, source: "meeting.mac")
        XCTAssertFalse(s.keepAudio)
        s.keepAudio = true // coordinator also enforces the invariant on decoded old data
        try finish(s)
        XCTAssertTrue(try store.containsTranscript(s.id))
        XCTAssertNil(repo.savedAudio(s.id))
    }
    func testSilenceCanBeKeptWithoutInventingText() throws {
        var s = try session(); s.entry?.text = ""
        try finish(s)
        XCTAssertEqual(try store.entries().first?.text, "")
        XCTAssertNotNil(repo.savedAudio(s.id))
    }
    func testAudioOnlyDeletionKeepsTranscript() throws {
        let s = try session(); try finish(s)
        try store.removeRecordingAudio(id: s.id)
        XCTAssertTrue(try store.containsTranscript(s.id)); XCTAssertNil(repo.savedAudio(s.id))
    }
    func testBulkFailureRollsBackRowsAndAudioDeletionQueue() throws {
        let a = try session("a"), b = try session("b")
        try finish(a); try finish(b)
        try db.write { try $0.execute(sql: "CREATE TRIGGER fail_delete BEFORE DELETE ON transcripts WHEN OLD.id = 'b' BEGIN SELECT RAISE(ABORT, 'disk failure'); END") }
        XCTAssertThrowsError(try store.deleteMany(ids: ["a", "b"]))
        XCTAssertEqual(try store.allRecordIDs().sorted(), ["a", "b"])
        XCTAssertNotNil(repo.savedAudio("a")); XCTAssertNotNil(repo.savedAudio("b"))
        let queued = try db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM audio_deletions") }
        XCTAssertEqual(queued, 0)
    }
    func testMergeFailureRollsBackEverything() throws {
        let a = try session("a"), b = try session("b")
        try finish(a); try finish(b)
        try db.write { try $0.execute(sql: "CREATE TRIGGER fail_delete BEFORE DELETE ON transcripts WHEN OLD.id = 'b' BEGIN SELECT RAISE(ABORT, 'disk failure'); END") }
        let merged = RecordingSession(source: "mic.mac", language: "nl").transcript(text: "merged", segments: [], duration: 2)
        XCTAssertThrowsError(try store.mergeAndReplace(merged: merged, deleting: ["a", "b"]))
        XCTAssertFalse(try store.containsTranscript(merged.id))
        XCTAssertNotNil(repo.savedAudio("a")); XCTAssertNotNil(repo.savedAudio("b"))
    }
    func testMissingNoteFallsBackToHistory() throws {
        let s = try session(noteID: "missing")
        XCTAssertTrue(try store.commitRecording(s, entry: s.entry!))
        XCTAssertEqual(try store.entries().map(\.id), [s.id])
    }
    func testLegacyAudioStaysDiscoverableAndIsNotDeleted() throws {
        try repo.prepareDirectory(repo.recordingsDirectory)
        let url = repo.recordingsDirectory.appendingPathComponent("found.caf")
        try Data("old".utf8).write(to: url)
        store.retryAudioCleanup()
        XCTAssertEqual(try store.foundRecordings().map { $0.resolvingSymlinksInPath() }, [url.resolvingSymlinksInPath()])
        XCTAssertEqual(try Data(contentsOf: url), Data("old".utf8))
    }
    func testLegacyTemporaryFileAdoptionIsIdempotent() throws {
        let url = root.appendingPathComponent("whisperclip-live-recording-nl-test.caf")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: url)
        let first = try repo.adoptLegacy(url, language: "nl", source: "mic.ios")
        let second = try repo.adoptLegacy(url, language: "nl", source: "mic.ios")
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(try repo.pending().count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
    func testAudioDirectoriesExcludedFromBackup() throws {
        let s = try session(); try finish(s)
        let values = try repo.recordingsDirectory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
    }
    func testNoteDeletionDetachesOrDeletesAudioAccordingToChoice() throws {
        let note = try store.createNote(title: "Meeting notes")
        let a = try session(noteID: note.id); try finish(a)
        try store.deleteNote(id: note.id, deleteEntries: false)
        XCTAssertNotNil(repo.savedAudio(a.id))
        XCTAssertEqual(try store.entries().map(\.id), [a.id])
        let secondNote = try store.createNote(title: "Remove")
        let b = try session(noteID: secondNote.id); try finish(b)
        try store.deleteNote(id: secondNote.id, deleteEntries: true)
        XCTAssertNil(repo.savedAudio(b.id))
    }
    func testMigrationPreservesExistingTranscriptAndAudio() throws {
        let oldDB = try DatabaseQueue()
        try HistorySchema.migrator().migrate(oldDB, upTo: "v7_plaud_duration_ms_fix")
        let s = try session("existing")
        try oldDB.write { try TranscriptRecord(entry: s.entry!).insert($0) }
        try repo.finish(s, keep: true)
        let upgraded = try HistoryStore(dbQueue: oldDB, retentionProvider: { nil }, recordingRepository: repo)
        XCTAssertTrue(try upgraded.containsTranscript(s.id))
        XCTAssertNotNil(repo.savedAudio(s.id))
        try upgraded.delete(id: s.id)
        XCTAssertNil(repo.savedAudio(s.id))
    }
    func testLegacyAdoptionResumesAfterCrashBeforeMove() throws {
        let url = root.appendingPathComponent("old.caf")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: url)
        try repo.save(RecordingSession(id: "legacy-old", source: "mic.mac", language: "nl"))
        let adopted = try repo.adoptLegacy(url, language: "nl", source: "mic.mac")
        XCTAssertTrue(FileManager.default.fileExists(atPath: try repo.audioURL(adopted.id).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
    func testOneDamagedJournalDoesNotHideOtherPendingIDs() throws {
        let s = try session("good")
        try repo.prepareDirectory(repo.sessionDirectory("bad"))
        try Data("corrupt".utf8).write(to: repo.sessionDirectory("bad").appendingPathComponent("session.json"))
        XCTAssertEqual(try repo.pendingIDs(), ["bad", "good"])
        XCTAssertEqual(try repo.load(s.id).entry, s.entry)
    }
    func testInvalidIDCannotEscapeContainer() throws {
        XCTAssertThrowsError(try repo.removeAudio("../outside"))
        XCTAssertThrowsError(try repo.save(RecordingSession(id: "..", source: "mic.ios", language: "nl")))
    }
    func testExportProducesPlayableM4AAndKeepsOriginal() async throws {
        let s = try session()
        let url = try repo.audioURL(s.id)
        try FileManager.default.removeItem(at: url)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16000))
        buffer.frameLength = 16000
        for i in 0..<16000 { buffer.floatChannelData![0][i] = Float(sin(Double(i) * 0.1) * 0.2) }
        do { let file = try AVAudioFile(forWriting: url, settings: format.settings); try file.write(from: buffer) }
        try finish(s)
        let saved = try XCTUnwrap(repo.savedAudio(s.id))
        let original = try Data(contentsOf: saved)
        let exported = try await repo.exportM4A(saved)
        let player = try AVAudioPlayer(contentsOf: exported)
        XCTAssertGreaterThan(player.duration, 0.9)
        XCTAssertEqual(try Data(contentsOf: saved), original)
        repo.removeExport(exported)
        XCTAssertFalse(FileManager.default.fileExists(atPath: exported.path))
    }
    func testExportFailureKeepsOriginalAndCleansTemporaryOutput() async throws {
        let s = try session(); try finish(s)
        let original = try XCTUnwrap(repo.savedAudio(s.id))
        do { _ = try await repo.exportM4A(original); XCTFail("Invalid audio should fail") } catch {}
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        let exports = root.appendingPathComponent("AudioExports")
        XCTAssertTrue((try? FileManager.default.contentsOfDirectory(atPath: exports.path).isEmpty) ?? true)
    }
    func testPreparedRecoveryNeedsNoModelAndPreservesMeetingIdentity() async throws {
        let s = try session("prepared", keep: false, source: "meeting.ios")
        let engine = ParakeetEngine(recordingRepository: repo)
        let result = try await engine.recoverOrphanedRecordings(defaultLocale: Locale(identifier: "en"), includeUntranscribed: false)
        XCTAssertEqual(result.recordings.count, 1)
        XCTAssertEqual(result.recordings.first?.result.recording?.id, s.id)
        XCTAssertEqual(result.recordings.first?.result.recording?.source, "meeting.ios")
        XCTAssertFalse(result.recordings.first?.result.recording?.keepAudio ?? true)
    }
    func testDeferredAudioCleanupKeepsOneFileUntilPostProcessingEnds() throws {
        let s = try session(keep: false)
        try store.commitRecording(s, entry: s.entry!, deferAudioCleanup: true)
        XCTAssertTrue(try store.containsTranscript(s.id))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try repo.audioURL(s.id).path))
        XCTAssertNil(repo.savedAudio(s.id))
        try store.completeRecordingAudio(s)
        XCTAssertTrue(try repo.pending().isEmpty)
    }
    func testCleanupFailureRemainsQueuedAndRetryCompletes() throws {
        let s = try session(); try finish(s)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: repo.recordingsDirectory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: repo.recordingsDirectory.path) }
        try store.delete(id: s.id)
        XCTAssertNotNil(store.audioCleanupError)
        XCTAssertNotNil(repo.savedAudio(s.id))
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: repo.recordingsDirectory.path)
        store.retryAudioCleanup()
        XCTAssertNil(repo.savedAudio(s.id)); XCTAssertNil(store.audioCleanupError)
    }
    func testRecordingHealthReportsPartialLossAndActualZeroDuration() {
        let session = RecordingSession(source: "mic.ios", language: "nl")
        let failure = TranscriptionResult(text: "", segments: [], audioDuration: 0, partialFailure: "disk full", recording: session)
        let health = RecordingHealth(result: failure, elapsed: 30)
        XCTAssertTrue(health.incomplete); XCTAssertEqual(health.duration, 0)
        let gap = RecordingHealth(result: TranscriptionResult(text: "some", segments: [], audioDuration: 10), elapsed: 30)
        XCTAssertTrue(gap.incomplete); XCTAssertEqual(gap.duration, 10)
        let normal = RecordingHealth(result: TranscriptionResult(text: "all", segments: [], audioDuration: 30), elapsed: 30.1)
        XCTAssertFalse(normal.incomplete)
    }
    func testMappedCAFMatchesRecordedSamples() throws {
        let s = try session(); let url = try repo.audioURL(s.id)
        try FileManager.default.removeItem(at: url)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16000))
        buffer.frameLength = 16000
        for i in 0..<16000 { buffer.floatChannelData![0][i] = Float(i) / 16000 }
        do { let file = try AVAudioFile(forWriting: url, settings: format.settings); try file.write(from: buffer) }
        let mapped = try MappedRecordingSamples(url: url)
        XCTAssertEqual(mapped.count, 16000)
        for i in [0, 1, 100, 15999] { XCTAssertEqual(mapped[i], Float(i) / 16000, accuracy: 0.00001) }
        XCTAssertEqual(Array(mapped[100..<110]).count, 10)
    }
    func testExplicitAudioDeletionWinsOverLateCompletion() throws {
        let s = try session()
        try store.commitRecording(s, entry: s.entry!, deferAudioCleanup: true)
        try store.removeRecordingAudio(id: s.id)
        try store.completeRecordingAudio(s)
        try finish(s)
        XCTAssertTrue(try store.containsTranscript(s.id))
        XCTAssertNil(repo.savedAudio(s.id))
        XCTAssertTrue(try repo.pending().isEmpty)
        XCTAssertNil(store.audioStorageError)
    }
}
