import EdgeWakeCore
import Foundation
import Network
import Testing
@testable import EdgeWakePeer

/// A paired Mac's link can die on its side without the other Mac noticing: a content filter or
/// VPN extension may keep the TCP connection alive after the app gave it up. When that Mac dials
/// again, the new link must win, or the other Mac keeps talking into the dead one forever.
@MainActor
@Suite(.serialized)
struct ReconnectTests {
    @Test func redialFromTheSameMacReplacesTheOldLink() async throws {
        // Mini has the smaller ID, so it would rather keep a link it dialled itself. Book never
        // accepts Mini's dials (its firewall drops them), so every link is incoming on Mini.
        let mini = TestPeer(name: "Mini", id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        let observer = TestPeer(name: "Observer")
        let book = LocalIdentity(id: UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000000")!, name: "Book")
        let key = Data(repeating: 7, count: 32)
        mini.keys[book.id] = key
        mini.service.start()
        observer.service.start()
        try await waitUntil("discovery") { observer.service.discovered[mini.identity.id] != nil }
        let endpoint = try #require(observer.service.discovered[mini.identity.id]).endpoint

        let stale = PairedClient(to: endpoint, identity: book, peerID: mini.identity.id, key: key)
        try await waitUntil("first link", timeout: 5) { stale.isConfirmed && mini.ready.contains(book.id) }

        // Book gave up on that link without Mini noticing, and dials again.
        let redial = PairedClient(to: endpoint, identity: book, peerID: mini.identity.id, key: key)
        try await waitUntil("redial confirmed", timeout: 5) { redial.isConfirmed }
        try await Task.sleep(for: .milliseconds(500))

        let status = PeerStatus(name: "Mini", displayAsleep: true, checks: [], version: "test")
        mini.service.broadcast(.status(status))
        try await waitUntil("status over the new link", timeout: 3) { redial.messages.contains(.status(status)) }
        #expect(!redial.isClosed, "Mini must keep the newest link from Book")
        #expect(stale.isClosed, "Mini must drop the link Book abandoned")
        stale.cancel()
        redial.cancel()
    }
}

/// A raw client that holds a paired Mac's identity and key and completes the real handshake.
@MainActor
private final class PairedClient {
    private let connection: NWConnection
    private let identity: LocalIdentity
    private let peerID: UUID
    private let key: Data
    private let nonce = SecureChannel.newNonce()
    private var buffer = FrameBuffer()
    private var channel: SecureChannel?
    private(set) var isConfirmed = false
    private(set) var isClosed = false
    private(set) var messages: [PeerMessage] = []

    init(to endpoint: NWEndpoint, identity: LocalIdentity, peerID: UUID, key: Data) {
        self.identity = identity
        self.peerID = peerID
        self.key = key
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        connection = NWConnection(to: endpoint, using: parameters)
        connection.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                switch state {
                case .ready: self?.sendPlain(.hello(deviceID: identity.id, name: identity.name, nonce: self?.nonce ?? Data()))
                case .cancelled, .failed: self?.isClosed = true
                default: break
                }
            }
        }
        connection.start(queue: .main)
        receive()
    }

    func cancel() {
        connection.cancel()
    }

    private func sendPlain(_ message: HandshakeMessage) {
        guard let payload = try? Wire.encode(message) else { return }
        connection.send(content: FrameBuffer.frame(payload), completion: .contentProcessed { _ in })
    }

    private func sendSealed(_ payload: Data) {
        guard var channel, let sealed = try? channel.seal(payload) else { return }
        self.channel = channel
        connection.send(content: FrameBuffer.frame(sealed), completion: .contentProcessed { _ in })
    }

    private func handle(_ frame: Data) {
        if var channel {
            guard let plaintext = try? channel.open(frame) else { return }
            self.channel = channel
            if isConfirmed {
                if let message = try? Wire.decode(PeerMessage.self, from: plaintext) { messages.append(message) }
            } else if (try? Wire.decode(LinkConfirmation.self, from: plaintext)) != nil {
                isConfirmed = true
            }
        } else if case let .hello(_, _, peerNonce) = try? Wire.decode(HandshakeMessage.self, from: frame) {
            channel = SecureChannel(longTermKey: key, localID: identity.id, localNonce: nonce, peerID: peerID, peerNonce: peerNonce)
            sendSealed((try? Wire.encode(LinkConfirmation(name: identity.name))) ?? Data())
        }
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let data, let frames = try? self.buffer.append(data) {
                    frames.forEach(self.handle)
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
