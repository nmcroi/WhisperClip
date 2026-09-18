import Foundation

public struct RecordingHealth: Equatable, Sendable {
    public let duration: Double
    public let incomplete: Bool
    public init(result: TranscriptionResult, elapsed: Double) {
        duration = result.recording != nil || result.audioDuration > 0 ? result.audioDuration : elapsed
        incomplete = result.partialFailure != nil
            || (result.audioDuration > 0 && elapsed - result.audioDuration > max(5, elapsed * 0.05))
    }
}
