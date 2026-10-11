import EdgeWakeCore

enum PairingState: Equatable {
    case idle
    case connecting(peerName: String)
    /// This Mac shows a code for the other Mac to type.
    case showingCode(code: String, peerName: String)
    /// The other Mac shows a code; type it here.
    case enteringCode(peerName: String, lastAttemptWrong: Bool)
    case verifying(peerName: String)
    case paired(peerName: String)
    case failed(PairRejection)

    var isInProgress: Bool {
        switch self {
        case .connecting, .showingCode, .enteringCode, .verifying: true
        case .idle, .paired, .failed: false
        }
    }
}
