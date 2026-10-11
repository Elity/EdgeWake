import Foundation

/// Splits a TCP byte stream into frames, each prefixed with a 4-byte big-endian length.
public struct FrameBuffer: Sendable {
    public enum Failure: Error {
        case frameTooLarge
    }

    public static let maximumFrameSize = 64 * 1024
    private var pending = Data()

    public init() {}

    public static func frame(_ payload: Data) -> Data {
        var length = UInt32(payload.count).bigEndian
        return Data(bytes: &length, count: 4) + payload
    }

    /// Appends received bytes and returns every frame that is now complete.
    public mutating func append(_ bytes: Data) throws -> [Data] {
        pending.append(bytes)
        var frames: [Data] = []
        // Walk the frames by offset and drop the consumed bytes once, not once per frame.
        var offset = pending.startIndex
        defer { pending.removeSubrange(pending.startIndex..<offset) }
        while pending.endIndex - offset >= 4 {
            let length = pending[offset..<offset + 4].reduce(0) { $0 << 8 | Int($1) }
            guard length <= Self.maximumFrameSize else { throw Failure.frameTooLarge }
            let start = offset + 4
            guard pending.endIndex - start >= length else { break }
            frames.append(Data(pending[start..<start + length]))
            offset = start + length
        }
        return frames
    }
}
