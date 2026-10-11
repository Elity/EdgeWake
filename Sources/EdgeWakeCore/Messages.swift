import Foundation

/// Plaintext messages exchanged before the encrypted channel exists.
/// A paired Mac opens with `hello`; an unpaired one opens with `pairRequest`. The `hello` name is
/// unauthenticated and ignored; the trusted name arrives in `LinkConfirmation`.
public enum HandshakeMessage: Codable, Equatable, Sendable {
    case hello(deviceID: UUID, name: String, nonce: Data)
    /// Sent by the Mac where the code will be typed.
    case pairRequest(deviceID: UUID, name: String, publicKey: Data)
    /// The responder is now showing a code.
    case pairReady(deviceID: UUID, name: String, publicKey: Data)
    case pairProof(Data)
    case pairRejected(PairRejection)
}

/// The first encrypted frame in each direction after `hello`. Opening it proves the sender holds
/// the long-term key, so a link is only trusted, and the peer's name only believed, from here on.
public struct LinkConfirmation: Codable, Equatable, Sendable {
    public var name: String

    public init(name: String) {
        self.name = name
    }
}

public enum PairRejection: String, Codable, Sendable {
    case wrongCode
    case declined
    case busy
    case unknownDevice
}

/// Messages carried inside the encrypted channel.
public enum PeerMessage: Codable, Equatable, Sendable {
    case status(PeerStatus)
    case wake(id: UUID)
    case wakeAck(id: UUID)
    /// The pointer arrived on the sender's screen through its outer `edge`.
    case pointerEntered(edge: Side)
    /// Asks the receiver to show the fix for one of its own checks.
    case showCheck(CheckID)
    /// The sender removed this Mac from its paired Macs.
    case unpaired
}

public struct PeerStatus: Codable, Equatable, Sendable {
    public var name: String
    public var displayAsleep: Bool
    public var checks: [CheckResult]
    public var version: String

    public init(name: String, displayAsleep: Bool, checks: [CheckResult], version: String) {
        self.name = name
        self.displayAsleep = displayAsleep
        self.checks = checks
        self.version = version
    }
}

public enum CheckID: String, Codable, CaseIterable, Sendable {
    case wifi
    case bluetooth
    case handoff
    case firewall
    case systemSleep
    case sameAppleID
    case universalControl
}

public enum CheckState: String, Codable, Sendable {
    case passed
    case failed
    /// Works, with a caveat worth showing (for example: this Mac may sleep).
    case warning
    /// Cannot be detected; the person confirms it themselves.
    case unconfirmed
    case unknown
}

public struct CheckResult: Codable, Equatable, Sendable, Identifiable {
    public var id: CheckID
    public var state: CheckState

    public init(id: CheckID, state: CheckState) {
        self.id = id
        self.state = state
    }
}

public enum Wire {
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        try JSONEncoder().encode(value)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }
}
