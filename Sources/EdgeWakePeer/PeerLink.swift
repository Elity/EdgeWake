import CryptoKit
import EdgeWakeCore
import Foundation
import Network

/// One TCP connection to another EdgeWake Mac. It starts with a plaintext handshake (`hello` for
/// paired Macs, the `pair…` exchange otherwise) and then carries `PeerMessage`s over a
/// `SecureChannel`. After `hello`, each side's first encrypted frame is a `LinkConfirmation`; the
/// link is ready only once the peer's opens, which proves it holds the long-term key.
/// All callbacks run on the main queue.
@MainActor
public final class PeerLink {
    public enum Opening: Sendable {
        case hello
        case pairRequest
        case incoming
    }

    private struct PairingContext {
        var privateKey = P256.KeyAgreement.PrivateKey()
        var role: Pairing.Role
        var code: String?
        var peerKey: Data?
        var wrongAttempts = 0

        var publicKey: Data { privateKey.publicKey.rawRepresentation }
        var initiatorKey: Data? { role == .initiator ? publicKey : peerKey }
        var responderKey: Data? { role == .responder ? publicKey : peerKey }
    }

    static let maximumWrongCodes = 3
    /// How long a pairing exchange may wait for a person to type the code: the code's lifetime.
    static let pairingTimeout: TimeInterval = 120

    public var onEvent: ((PeerLink, LinkEvent) -> Void)?
    public private(set) var peerID: UUID?
    public private(set) var peerName: String?
    public private(set) var isReady = false

    private let connection: NWConnection
    private let identity: LocalIdentity
    private let keyLookup: (UUID) -> Data?
    private let opening: Opening
    private var buffer = FrameBuffer()
    private var channel: SecureChannel?
    private let localNonce = SecureChannel.newNonce()
    private var pairing: PairingContext?
    private let handshakeTimeout: TimeInterval
    private var timeoutExtended = false
    /// Set as soon as the link decides to decline or close; nothing it receives counts after that.
    private var closing = false
    private var closed = false

    init(connection: NWConnection, opening: Opening, identity: LocalIdentity, expectedPeer: UUID? = nil,
         handshakeTimeout: TimeInterval, keyLookup: @escaping (UUID) -> Data?) {
        self.connection = connection
        self.opening = opening
        self.identity = identity
        self.peerID = expectedPeer
        self.handshakeTimeout = handshakeTimeout
        self.keyLookup = keyLookup
    }

    /// Whether this Mac opened the connection.
    public var isOutgoing: Bool { opening != .incoming }

    static func parameters(requiredInterface: NWInterface.InterfaceType? = nil) -> NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        // Notice a vanished peer (shut down, off the network) within roughly 10 seconds.
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 4
        tcp.keepaliveInterval = 2
        tcp.keepaliveCount = 3
        tcp.connectionTimeout = 5
        let parameters = NWParameters(tls: nil, tcp: tcp)
        if let requiredInterface {
            parameters.requiredInterfaceType = requiredInterface
        }
        return parameters
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated { self?.connectionChanged(state) }
        }
        connection.start(queue: .main)
        receive()
        scheduleTimeout(after: handshakeTimeout)
    }

    public func send(_ message: PeerMessage) {
        guard isReady, let payload = try? Wire.encode(message) else { return }
        sendSealed(payload)
    }

    /// Initiator: the person typed the code shown on the other Mac.
    public func submitCode(_ code: String) {
        guard !closing, var pairing, pairing.role == .initiator, let i = pairing.initiatorKey, let r = pairing.responderKey,
              let peerID else { return }
        pairing.code = code
        self.pairing = pairing
        sendPlain(.pairProof(Pairing.proof(code: code, role: .initiator, initiatorID: identity.id, responderID: peerID,
                                           initiatorKey: i, responderKey: r)))
    }

    public func decline(_ reason: PairRejection) {
        guard !closing else { return }
        closing = true
        sendPlain(.pairRejected(reason)) { [weak self] in self?.close() }
    }

    public func close() {
        closing = true
        connection.cancel()
        finish()
    }

    // MARK: - Connection

    private func connectionChanged(_ state: NWConnection.State) {
        switch state {
        case .ready:
            switch opening {
            case .hello:
                sendPlain(.hello(deviceID: identity.id, name: identity.name, nonce: localNonce))
            case .pairRequest:
                let context = PairingContext(role: .initiator)
                pairing = context
                sendPlain(.pairRequest(deviceID: identity.id, name: identity.name, publicKey: context.publicKey))
            case .incoming:
                break
            }
        case .waiting:
            // Refused or unreachable. Network.framework would wait for the network to change;
            // give up instead, so the service's retry timer can dial again.
            close()
        case .failed:
            close()
        case .cancelled:
            finish()
        default:
            break
        }
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let data, !data.isEmpty {
                    do {
                        for frame in try self.buffer.append(data) {
                            // Frames that arrived in the same read as the one that ended the link
                            // must not count: they could be more guesses at the code.
                            guard !self.closing else { break }
                            self.handle(frame)
                        }
                    } catch {
                        self.close()
                        return
                    }
                }
                if isComplete || error != nil {
                    self.close()
                } else if !self.closing {
                    self.receive()
                }
            }
        }
    }

    private func handle(_ frame: Data) {
        if var channel {
            guard let plaintext = try? channel.open(frame) else { return close() }
            self.channel = channel
            if isReady {
                guard let message = try? Wire.decode(PeerMessage.self, from: plaintext) else { return close() }
                emit(.message(message))
            } else {
                guard let confirmation = try? Wire.decode(LinkConfirmation.self, from: plaintext), let peerID else { return close() }
                peerName = confirmation.name
                isReady = true
                emit(.ready(peerID: peerID, name: confirmation.name))
            }
        } else if let message = try? Wire.decode(HandshakeMessage.self, from: frame) {
            handle(message)
        } else {
            close()
        }
    }

    // MARK: - Handshake

    private func handle(_ message: HandshakeMessage) {
        switch message {
        case let .hello(deviceID, _, nonce):
            guard opening != .pairRequest, pairing == nil else { return close() }
            guard let key = keyLookup(deviceID) else {
                decline(.unknownDevice)
                return
            }
            if opening == .incoming {
                sendPlain(.hello(deviceID: identity.id, name: identity.name, nonce: localNonce))
            } else if deviceID != peerID {
                close()
                return
            }
            peerID = deviceID
            channel = SecureChannel(longTermKey: key, localID: identity.id, localNonce: localNonce, peerID: deviceID, peerNonce: nonce)
            guard let confirmation = try? Wire.encode(LinkConfirmation(name: identity.name)) else { return close() }
            sendSealed(confirmation)

        case let .pairRequest(deviceID, name, publicKey):
            guard opening == .incoming, pairing == nil else { return close() }
            var context = PairingContext(role: .responder)
            context.peerKey = publicKey
            context.code = Pairing.newCode()
            pairing = context
            peerID = deviceID
            peerName = name
            // Reported before answering, so the owner can still decline (busy, cooling down)
            // before the requester learns anything.
            emit(.pairingCodeShown(code: context.code ?? "", peerName: name))
            guard !closing else { return }
            sendPlain(.pairReady(deviceID: identity.id, name: identity.name, publicKey: context.publicKey))

        case let .pairReady(deviceID, name, publicKey):
            // The answer must come from the Mac we asked, and only once.
            guard pairing?.role == .initiator, pairing?.peerKey == nil, deviceID == peerID else { return close() }
            pairing?.peerKey = publicKey
            peerName = name
            emit(.pairingCodeNeeded(peerName: name))

        case let .pairProof(proof):
            handleProof(proof)

        case let .pairRejected(reason):
            // Only the Mac that opened the exchange is ever answered with a rejection: the
            // initiator of a pairing, or a `hello` the other Mac does not recognise.
            guard pairing?.role == .initiator || opening == .hello else { return }
            emit(.pairingFailed(reason))
            // A wrong code leaves the exchange open so the person can type it again.
            if reason != .wrongCode || pairing == nil { close() }
        }
    }

    private func handleProof(_ proof: Data) {
        guard var context = pairing, context.wrongAttempts < Self.maximumWrongCodes, let code = context.code,
              let i = context.initiatorKey, let r = context.responderKey, let peerID, let peerName else { return close() }
        let senderRole: Pairing.Role = context.role == .responder ? .initiator : .responder
        let (initiatorID, responderID) = context.role == .initiator ? (identity.id, peerID) : (peerID, identity.id)
        guard Pairing.isValid(proof, code: code, role: senderRole, initiatorID: initiatorID, responderID: responderID,
                              initiatorKey: i, responderKey: r) else {
            if context.role == .responder {
                context.wrongAttempts += 1
                pairing = context
                if context.wrongAttempts >= Self.maximumWrongCodes {
                    emit(.pairingFailed(.wrongCode))
                    decline(.wrongCode)
                } else {
                    sendPlain(.pairRejected(.wrongCode))
                }
            } else {
                // The responder's proof is wrong although it accepted ours: not the Mac we think.
                emit(.pairingFailed(.declined))
                close()
            }
            return
        }
        guard let key = try? Pairing.longTermKey(privateKey: context.privateKey, peerPublicKey: context.peerKey ?? Data(),
                                                  initiatorID: initiatorID, responderID: responderID,
                                                  initiatorKey: i, responderKey: r) else { return close() }
        let finish: @MainActor @Sendable () -> Void = { [weak self] in
            guard let self else { return }
            self.emit(.paired(PairedPeer(id: peerID, name: peerName, key: key, side: nil)))
            self.close()
        }
        if context.role == .responder {
            let answer = Pairing.proof(code: code, role: .responder, initiatorID: initiatorID, responderID: responderID,
                                       initiatorKey: i, responderKey: r)
            sendPlain(.pairProof(answer), then: finish)
        } else {
            finish()
        }
    }

    private func sendPlain(_ message: HandshakeMessage, then completion: (@MainActor @Sendable () -> Void)? = nil) {
        guard let payload = try? Wire.encode(message) else { return }
        connection.send(content: FrameBuffer.frame(payload), completion: .contentProcessed { _ in
            MainActor.assumeIsolated { completion?() }
        })
    }

    private func sendSealed(_ payload: Data) {
        guard var channel, let sealed = try? channel.seal(payload) else { return }
        self.channel = channel
        connection.send(content: FrameBuffer.frame(sealed), completion: .contentProcessed { _ in })
    }

    /// Reports an event, unless the link has already decided to decline or close.
    private func emit(_ event: LinkEvent) {
        guard !closing else { return }
        onEvent?(self, event)
    }

    // MARK: - Timeout

    private func scheduleTimeout(after seconds: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            MainActor.assumeIsolated { self?.handshakeTimedOut() }
        }
    }

    /// Drops a link that never finished its handshake, so strangers cannot hold connections open.
    /// A pairing exchange waits for a person to type the code, so it gets the code's lifetime.
    private func handshakeTimedOut() {
        guard !isReady, !closed else { return }
        if pairing != nil, !timeoutExtended {
            timeoutExtended = true
            scheduleTimeout(after: max(0, Self.pairingTimeout - handshakeTimeout))
        } else {
            close()
        }
    }

    private func finish() {
        guard !closed else { return }
        closing = true
        closed = true
        isReady = false
        onEvent?(self, .closed)
    }
}
