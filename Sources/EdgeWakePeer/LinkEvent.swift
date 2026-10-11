import EdgeWakeCore
import Foundation

/// Everything a `PeerLink` reports to its owner.
public enum LinkEvent {
    /// The encrypted channel is up.
    case ready(peerID: UUID, name: String)
    case message(PeerMessage)
    case closed
    /// Responder: show this code until the other Mac types it.
    case pairingCodeShown(code: String, peerName: String)
    /// Initiator: ask the person for the code shown on `peerName`.
    case pairingCodeNeeded(peerName: String)
    case paired(PairedPeer)
    case pairingFailed(PairRejection)
}

public struct LocalIdentity: Sendable {
    public var id: UUID
    public var name: String

    public init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }
}
