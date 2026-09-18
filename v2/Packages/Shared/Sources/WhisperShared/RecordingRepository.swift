import AVFoundation
import Core
import Foundation

/// Durable ownership of one microphone recording. The ID is also its transcript ID.
public struct RecordingSession: Codable, Sendable, Equatable {
    public var id: String
    public var source: String
    public var language: String
    public var model: String
    public var noteID: String?
    public var keepAudio: Bool
    public var createdAt: Date
    public var entry: TranscriptEntry?
    public var warning: String?
    public var resultIsProcessed: Bool?

    public init(id: String = UUID().uuidString, source: String, language: String,
                model: String = "parakeet-tdt-0.6b-v3", noteID: String? = nil,
                keepAudio: Bool = false, createdAt: Date = Date()) {
        self.id = id; self.source = source; self.language = language
        self.model = model; self.noteID = noteID
        self.keepAudio = source.hasPrefix("meeting") ? false : keepAudio
        self.createdAt = createdAt
    }

    public func transcript(text: String, segments: [TranscriptSegment], duration: Double) -> TranscriptEntry {
        TranscriptEntry(id: id, text: text,
            createdAt: ISO8601DateFormatter().string(from: createdAt), name: "", pinned: false,
            language: language, model: model, source: source, duration: duration, segments: segments)
    }
}

public enum RecordingStorageError: LocalizedError {
    case invalidID, missingAudio, unreadableJournal, conversionFailed
    public var errorDescription: String? {
        switch self {
        case .invalidID: "Invalid recording identifier."
        case .missingAudio: "The recording file is missing."
        case .unreadableJournal: "Recording recovery information could not be read."
        case .conversionFailed: "Audio export failed. The original recording is preserved."
        }
    }
}

/// All paths are injectable. Tests never use the live container. No audio goes to CloudKit.
public struct RecordingRepository: Sendable {
    public let root: URL
    private let writeJournal: @Sendable (Data, URL) throws -> Void
    public init(root: URL) {
        self.root = root
        self.writeJournal = { try $0.write(to: $1, options: .atomic) }
    }
    // Fault injection keeps ENOSPC tests isolated from the host filesystem.
    init(root: URL, writeJournal: @escaping @Sendable (Data, URL) throws -> Void) {
        self.root = root; self.writeJournal = writeJournal
    }
    public static var live: RecordingRepository {
        #if DEBUG
        return RecordingRepository(root: AppSupport.baseDirectory.appendingPathComponent("Audio-dev"))
        #else
        return RecordingRepository(root: AppSupport.baseDirectory)
        #endif
    }
    public var recoveryDirectory: URL { root.appendingPathComponent("RecordingRecovery", isDirectory: true) }
    public var recordingsDirectory: URL { root.appendingPathComponent("Recordings", isDirectory: true) }
    public static let extensions = ["caf", "m4a", "wav", "mp3", "aac", "aiff", "mp4", "mov"]

    public func validate(_ id: String) throws {
        guard !id.isEmpty, id != ".", id != "..", !id.contains("/"), !id.contains("\\"),
              id.utf8.count < 240 else { throw RecordingStorageError.invalidID }
    }
    public func sessionDirectory(_ id: String) throws -> URL {
        try validate(id)
        return recoveryDirectory.appendingPathComponent(id, isDirectory: true)
    }
    public func audioURL(_ id: String) throws -> URL {
        try sessionDirectory(id).appendingPathComponent("audio.caf")
    }
    public func protect(_ url: URL) throws {
        var protectedURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try protectedURL.setResourceValues(values)
        #if os(iOS)
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
        #endif
    }
    public func prepareDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try protect(url)
    }
    public func save(_ session: RecordingSession) throws {
        try prepareDirectory(recoveryDirectory)
        let directory = try sessionDirectory(session.id)
        try prepareDirectory(directory)
        let url = directory.appendingPathComponent("session.json")
        try writeJournal(JSONEncoder().encode(session), url)
        try protect(url)
    }
    public func load(_ id: String) throws -> RecordingSession {
        let url = try sessionDirectory(id).appendingPathComponent("session.json")
        let session = try JSONDecoder().decode(RecordingSession.self, from: Data(contentsOf: url))
        guard session.id == id else { throw RecordingStorageError.unreadableJournal }
        return session
    }
    public func pendingIDs() throws -> [String] {
        guard FileManager.default.fileExists(atPath: recoveryDirectory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: recoveryDirectory,
            includingPropertiesForKeys: [.isDirectoryKey]).filter {
                (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }.map(\.lastPathComponent).sorted()
    }
    public func pending() throws -> [RecordingSession] {
        guard FileManager.default.fileExists(atPath: recoveryDirectory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: recoveryDirectory,
            includingPropertiesForKeys: [.isDirectoryKey]).filter {
                (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }.map { try load($0.lastPathComponent) }.sorted { $0.createdAt < $1.createdAt }
    }
    public func savedAudio(_ id: String) -> URL? {
        guard (try? validate(id)) != nil else { return nil }
        return Self.extensions.map { recordingsDirectory.appendingPathComponent(id).appendingPathExtension($0) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }
    public func finish(_ session: RecordingSession, keep: Bool) throws {
        let source = try audioURL(session.id)
        if keep {
            try prepareDirectory(recordingsDirectory)
            if savedAudio(session.id) == nil {
                guard FileManager.default.fileExists(atPath: source.path) else { throw RecordingStorageError.missingAudio }
                let destination = recordingsDirectory.appendingPathComponent(session.id).appendingPathExtension("caf")
                try FileManager.default.moveItem(at: source, to: destination)
            }
            if let saved = savedAudio(session.id) { try protect(saved) }
        }
        let directory = try sessionDirectory(session.id)
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }
    public func removeAudio(_ id: String) throws {
        try validate(id)
        for ext in Self.extensions {
            let url = recordingsDirectory.appendingPathComponent(id).appendingPathExtension(ext)
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
        // A deletion also cancels an unfinished audio commit, so recovery cannot resurrect it.
        let dir = try sessionDirectory(id)
        if FileManager.default.fileExists(atPath: dir.path) { try FileManager.default.removeItem(at: dir) }
    }
    public func prepareForLaunch() throws {
        // Export copies are never a source of truth and no share operation survives process death.
        let exports = root.appendingPathComponent("AudioExports")
        if FileManager.default.fileExists(atPath: exports.path) { try FileManager.default.removeItem(at: exports) }
        if FileManager.default.fileExists(atPath: recordingsDirectory.path) {
            try protect(recordingsDirectory)
            for file in try savedFiles() { try protect(file) }
        }
    }
    public func savedFiles() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: recordingsDirectory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: recordingsDirectory,
            includingPropertiesForKeys: nil).filter { Self.extensions.contains($0.pathExtension.lowercased()) }
    }
    /// Atomic adoption: a restart reuses the same ID derived from the old filename.
    public func adoptLegacy(_ url: URL, language: String, source: String) throws -> RecordingSession {
        let id = "legacy-" + url.deletingPathExtension().lastPathComponent
        if let existing = try? load(id) {
            // A crash may have happened after saving metadata but before moving the old file.
            let destination = try audioURL(id)
            if !FileManager.default.fileExists(atPath: destination.path), FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.moveItem(at: url, to: destination)
            }
            return existing
        }
        let createdAt = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
        let session = RecordingSession(id: id, source: source, language: language, createdAt: createdAt)
        try save(session)
        try FileManager.default.moveItem(at: url, to: audioURL(id))
        return session
    }

    public func exportM4A(_ source: URL) async throws -> URL {
        let directory = root.appendingPathComponent("AudioExports").appendingPathComponent(UUID().uuidString)
        try prepareDirectory(directory)
        let output = directory.appendingPathComponent("WhisperClip.m4a")
        do {
            let asset = AVURLAsset(url: source)
            guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
                throw RecordingStorageError.conversionFailed
            }
            if #available(iOS 18, macOS 15, *) {
                try await exporter.export(to: output, as: .m4a)
            } else {
                exporter.outputURL = output; exporter.outputFileType = .m4a
                await exporter.export()
                guard exporter.status == .completed else { throw RecordingStorageError.conversionFailed }
            }
            try protect(output)
            return output
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }
    public func removeExport(_ url: URL) {
        let parent = url.deletingLastPathComponent()
        guard parent.deletingLastPathComponent().standardizedFileURL == root.appendingPathComponent("AudioExports").standardizedFileURL else { return }
        try? FileManager.default.removeItem(at: parent)
    }
}
