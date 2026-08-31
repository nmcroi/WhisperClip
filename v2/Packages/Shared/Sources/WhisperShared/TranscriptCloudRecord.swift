import CloudKit
import Core
import Foundation

/// The CloudKit ↔ local mapping for a transcript, plus the last-writer-wins
/// conflict decision. Kept free of any `CKSyncEngine` reference so it is fully
/// unit-testable without a CloudKit account (the engine wiring lives in
/// `HistorySyncEngine`).
///
/// One `CKRecord` of type `Transcript` maps to one `TranscriptRecord`
/// (recordName == entry id). All fields are stored inline; the two structured
/// blobs (segments, speakerNames) travel as JSON `Data`, exactly as they are
/// persisted locally, so no lossy re-encoding happens in transit.
public enum TranscriptCloudRecord {

    /// The CloudKit record type.
    public static let recordType = "Transcript"

    /// The custom private-database zone holding all transcript records.
    public static let zoneName = "Transcripts"

    /// Field keys on the `Transcript` record.
    public enum Field {
        public static let text = "text"
        public static let createdAt = "createdAt"
        public static let name = "name"
        public static let pinned = "pinned"
        public static let language = "language"
        public static let model = "model"
        public static let source = "source"
        public static let duration = "duration"
        public static let segments = "segments"          // JSON Data
        public static let speakerNames = "speakerNames"  // JSON Data
        public static let modifiedAt = "modifiedAt"      // Int64 epoch ms (LWW clock)
        public static let noteId = "noteId"
        public static let noteLinkVersion = "noteLinkVersion"
        /// CKAsset-varianten van `text` en `segments` voor opnames die anders
        /// boven de recordlimiet van 1 MB uitkomen ("record too large" bij een
        /// lange PLAUD-opname, 31 aug 2026). Assets tellen niet mee in die
        /// limiet. Aanwezig alleen op grote records; kleine blijven inline.
        public static let textAsset = "textAsset"
        public static let segmentsAsset = "segmentsAsset"
    }

    /// Boven deze gezamenlijke omvang van tekst plus segmenten (bytes) gaan
    /// beide velden als CKAsset mee. Ruim onder de harde servergrens van 1 MB,
    /// zodat de overige velden en CloudKit-overhead er altijd naast passen.
    public static let inlineByteLimit = 600_000

    /// Writes the local record's fields onto a `CKRecord` (create the CKRecord
    /// with the transcript id as its recordName in the transcripts zone first,
    /// or reuse the server-provided one to preserve its change tag).
    public static func apply(_ local: TranscriptRecord, to ck: CKRecord) {
        let textData = Data(local.text.utf8)
        let segmentsData = Data(local.segments.utf8)

        if textData.count + segmentsData.count > inlineByteLimit,
           let textURL = writeAssetFile(textData),
           let segmentsURL = writeAssetFile(segmentsData) {
            // Groot record: beide blobs als asset, inline leeg. Lukt het
            // wegschrijven niet, dan valt de record terug op inline en weigert
            // de server hem zoals voorheen; er gaat nooit stil iets verloren.
            ck[Field.textAsset] = CKAsset(fileURL: textURL)
            ck[Field.segmentsAsset] = CKAsset(fileURL: segmentsURL)
            ck[Field.text] = "" as CKRecordValue
            ck[Field.segments] = Data() as CKRecordValue
        } else {
            ck[Field.text] = local.text as CKRecordValue
            ck[Field.segments] = segmentsData as CKRecordValue
            // Een eerder groot record dat lokaal is ingekort mag zijn oude
            // assets niet houden, anders wint de asset weer bij het lezen.
            ck[Field.textAsset] = nil
            ck[Field.segmentsAsset] = nil
        }
        ck[Field.createdAt] = local.createdAt as CKRecordValue
        ck[Field.name] = local.name as CKRecordValue
        ck[Field.pinned] = (local.pinned ? 1 : 0) as CKRecordValue
        ck[Field.language] = local.language as CKRecordValue
        ck[Field.model] = local.model as CKRecordValue
        ck[Field.source] = local.source as CKRecordValue
        ck[Field.duration] = local.duration as CKRecordValue
        ck[Field.speakerNames] = Data(local.speakerNames.utf8) as CKRecordValue
        ck[Field.modifiedAt] = local.modifiedAt as CKRecordValue
        ck[Field.noteId] = local.noteId as CKRecordValue?
        ck[Field.noteLinkVersion] = 1 as CKRecordValue
    }

    /// Schrijft één blob naar een tijdelijk bestand voor CKAsset. CloudKit
    /// leest het bestand pas bij het daadwerkelijke opslaan, dus het blijft
    /// staan tot het systeem de tijdelijke map opruimt.
    private static func writeAssetFile(_ data: Data) -> URL? {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("whisperclip-ck-assets", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(UUID().uuidString)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// Reconstructs a local `TranscriptRecord` from a fetched `CKRecord`.
    /// Tolerant: missing/oddly-typed fields fall back to the same defaults the
    /// local schema uses, so a record written by a newer/older client version
    /// still decodes rather than being dropped.
    public static func local(from ck: CKRecord) -> TranscriptRecord {
        func string(_ key: String, _ fallback: String = "") -> String {
            ck[key] as? String ?? fallback
        }
        func jsonString(_ key: String, _ fallback: String) -> String {
            if let data = ck[key] as? Data, let s = String(data: data, encoding: .utf8) {
                return s
            }
            // Also accept a raw string (defensive against schema drift).
            return ck[key] as? String ?? fallback
        }
        // A large record carries its blobs as CKAsset files; the asset wins
        // over the (emptied) inline field. An unreadable asset file falls back
        // to inline so nothing crashes on a half-downloaded record.
        func assetString(_ key: String) -> String? {
            guard let asset = ck[key] as? CKAsset,
                  let url = asset.fileURL,
                  let data = try? Data(contentsOf: url),
                  !data.isEmpty,
                  let s = String(data: data, encoding: .utf8)
            else { return nil }
            return s
        }
        let pinned: Bool
        if let n = ck[Field.pinned] as? Int64 { pinned = n != 0 }
        else if let n = ck[Field.pinned] as? Int { pinned = n != 0 }
        else if let b = ck[Field.pinned] as? Bool { pinned = b }
        else { pinned = false }

        let modifiedAt: Int64 = (ck[Field.modifiedAt] as? Int64)
            ?? Int64(ck[Field.modifiedAt] as? Int ?? 0)

        // Derive the sort key from createdAt (matches the local insert path).
        let createdAt = string(Field.createdAt)
        let sortKey = TranscriptEntry(id: ck.recordID.recordName, text: "", createdAt: createdAt)
            .timestamp?.timeIntervalSince1970 ?? 0

        return TranscriptRecord(
            id: ck.recordID.recordName,
            text: assetString(Field.textAsset) ?? string(Field.text),
            createdAt: createdAt,
            name: string(Field.name),
            pinned: pinned,
            language: string(Field.language),
            model: string(Field.model),
            source: string(Field.source, "mic"),
            duration: ck[Field.duration] as? Double ?? 0,
            segments: assetString(Field.segmentsAsset) ?? jsonString(Field.segments, "[]"),
            sortKey: sortKey,
            speakerNames: jsonString(Field.speakerNames, "{}"),
            modifiedAt: modifiedAt,
            noteId: ck[Field.noteId] as? String
        )
    }

    /// Old CloudKit records predate note syncing. Only a record carrying this
    /// version marker may explicitly attach or detach a local transcript.
    public static func carriesNoteLink(_ ck: CKRecord) -> Bool {
        (ck[Field.noteLinkVersion] as? Int64 ?? Int64(ck[Field.noteLinkVersion] as? Int ?? 0)) >= 1
    }

    // MARK: - Conflict resolution (last-writer-wins)

    /// The decision the sync engine takes when it holds both a local `modifiedAt`
    /// and a remote one for the same id.
    public enum Resolution: Equatable, Sendable {
        /// The remote copy is newer (or equal): apply it locally.
        case takeRemote
        /// The local copy is strictly newer: keep it and resubmit to the server.
        case keepLocal
    }

    /// Last-writer-wins by `modifiedAt` (epoch ms). A remote record for an id we
    /// do not have locally (`localModifiedAt == nil`) is always taken. On an
    /// exact tie the remote wins — this is deterministic and avoids a resubmit
    /// storm when two devices independently converge on the same content.
    public static func resolve(localModifiedAt: Int64?, remoteModifiedAt: Int64) -> Resolution {
        guard let local = localModifiedAt else { return .takeRemote }
        return remoteModifiedAt >= local ? .takeRemote : .keepLocal
    }
}
