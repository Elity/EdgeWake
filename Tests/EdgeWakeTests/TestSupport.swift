import EdgeWakeCore
import Foundation
import Network
import Testing
@testable import EdgeWakePeer

/// One EdgeWake Mac inside the test process: a real `PeerService` on loopback, plus a record of
/// what it observed. Uses its own service type so a running EdgeWake app never sees it, and
/// loopback so the macOS Application Firewall (which drops LAN connections to an unapproved test
/// runner) stays out of it.
@MainActor
final class TestPeer {
    static let serviceType = "_edgewaketest._tcp"

    let identity: LocalIdentity
    let service: PeerService
    var keys: [UUID: Data] = [:]
    var shownCode: String?
    var codeToType: () -> String = { "" }
    var ready: Set<UUID> = []
    var readyNames: [String] = []
    var messages: [PeerMessage] = []
    var failures: [PairRejection] = []

    init(name: String, id: UUID = UUID()) {
        identity = LocalIdentity(id: id, name: "\(name) \(UUID().uuidString.prefix(6))")
        service = PeerService(identity: identity, serviceType: Self.serviceType, requiredInterface: .loopback)
        service.pairedKey = { [unowned self] in keys[$0] }
        service.onLinkEvent = { [unowned self] link, event in handle(event, link) }
    }

    private func handle(_ event: LinkEvent, _ link: PeerLink) {
        switch event {
        case let .ready(peerID, name):
            ready.insert(peerID)
            readyNames.append(name)
        case let .message(message):
            messages.append(message)
            if case let .wake(id) = message { link.send(.wakeAck(id: id)) }
        case let .pairingCodeShown(code, _): shownCode = code
        case .pairingCodeNeeded: link.submitCode(codeToType())
        case let .paired(peer): keys[peer.id] = peer.key
        case let .pairingFailed(reason): failures.append(reason)
        case .closed: break
        }
    }
}

/// A hand-driven TCP client that speaks raw EdgeWake frames, for playing an attacker.
@MainActor
final class RawClient {
    private let connection: NWConnection
    private var buffer = FrameBuffer()
    private(set) var received: [HandshakeMessage] = []
    private(set) var isClosed = false

    init(to endpoint: NWEndpoint) {
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        connection = NWConnection(to: endpoint, using: parameters)
        connection.stateUpdateHandler = { [weak self] state in
            if case .cancelled = state { MainActor.assumeIsolated { self?.isClosed = true } }
            if case .failed = state { MainActor.assumeIsolated { self?.isClosed = true } }
        }
        connection.start(queue: .main)
        receive()
    }

    /// Sends every message in a single write, so the receiver handles them in one batch.
    func send(_ messages: [HandshakeMessage]) {
        let bytes = messages.compactMap { try? Wire.encode($0) }.map(FrameBuffer.frame).reduce(Data(), +)
        connection.send(content: bytes, completion: .contentProcessed { _ in })
    }

    func cancel() {
        connection.cancel()
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let data, let frames = try? self.buffer.append(data) {
                    self.received += frames.compactMap { try? Wire.decode(HandshakeMessage.self, from: $0) }
                }
                if isComplete || error != nil {
                    self.isClosed = true
                } else {
                    self.receive()
                }
            }
        }
    }
}

@MainActor
func waitUntil(_ what: String, timeout: Double = 15, _ condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        guard Date() < deadline else {
            Issue.record("Timed out waiting for \(what)")
            throw CancellationError()
        }
        try await Task.sleep(for: .milliseconds(50))
    }
}

/// Pairs `book` with `mini` through the real UI flow and waits for the encrypted link.
@MainActor
func pairAndConnect(_ mini: TestPeer, _ book: TestPeer) async throws {
    book.codeToType = { mini.shownCode ?? "" }
    mini.service.start()
    book.service.start()
    try await waitUntil("discovery") { book.service.discovered[mini.identity.id] != nil }
    book.service.requestPairing(with: mini.identity.id)
    try await waitUntil("pairing") { mini.keys[book.identity.id] != nil && book.keys[mini.identity.id] != nil }
    mini.service.connectToPairedPeers()
    book.service.connectToPairedPeers()
    try await waitUntil("encrypted link") { mini.ready.contains(book.identity.id) && book.ready.contains(mini.identity.id) }
}
