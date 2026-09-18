import AudioToolbox
import Foundation

/// Random-access view of a local mono Float32 CAF. Only pages being used need reside in RAM.
/// Used after capture, so the microphone path never accumulates the recording in an array.
public struct MappedRecordingSamples: RandomAccessCollection {
    public typealias Index = Int
    public typealias Element = Float
    private let bytes: Data
    private let offset: Int
    private let bigEndian: Bool
    public let startIndex = 0
    public let endIndex: Int

    public init(url: URL) throws {
        var file: AudioFileID?
        guard AudioFileOpenURL(url as CFURL, .readPermission, 0, &file) == noErr, let file else {
            throw RecordingStorageError.missingAudio
        }
        defer { AudioFileClose(file) }
        var format = AudioStreamBasicDescription()
        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var dataOffset: Int64 = 0
        var offsetSize = UInt32(MemoryLayout<Int64>.size)
        var byteCount: UInt64 = 0
        var countSize = UInt32(MemoryLayout<UInt64>.size)
        guard AudioFileGetProperty(file, kAudioFilePropertyDataFormat, &formatSize, &format) == noErr,
              AudioFileGetProperty(file, kAudioFilePropertyDataOffset, &offsetSize, &dataOffset) == noErr,
              AudioFileGetProperty(file, kAudioFilePropertyAudioDataByteCount, &countSize, &byteCount) == noErr,
              format.mFormatID == kAudioFormatLinearPCM, format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mBitsPerChannel == 32, format.mChannelsPerFrame == 1, format.mSampleRate == 16000,
              dataOffset >= 0, byteCount <= UInt64(Int.max) else {
            throw RecordingStorageError.conversionFailed
        }
        bytes = try Data(contentsOf: url, options: .alwaysMapped)
        offset = Int(dataOffset)
        guard offset <= bytes.count, Int(byteCount) <= bytes.count - offset else { throw RecordingStorageError.missingAudio }
        endIndex = Int(byteCount) / MemoryLayout<Float>.size
        bigEndian = format.mFormatFlags & kAudioFormatFlagIsBigEndian != 0
    }
    public subscript(position: Int) -> Float {
        precondition(position >= 0 && position < endIndex)
        let bits = bytes.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset + position * 4, as: UInt32.self) }
        return Float(bitPattern: bigEndian ? UInt32(bigEndian: bits) : UInt32(littleEndian: bits))
    }
}
