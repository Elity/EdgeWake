import EdgeWakeCore
import Foundation
import Network

/// Another EdgeWake Mac seen on the local network through Bonjour.
public struct DiscoveredMac: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var endpoint: NWEndpoint
}

/// Advertises this Mac, browses for others, and keeps one encrypted link per paired Mac.
///
/// Both Macs dial each other, because the macOS Application Firewall may silently drop incoming
/// connections on one of them; whichever direction gets through is enough. When both succeed,
/// both Macs keep the link dialled by the Mac with the smaller device ID, so they agree.
@MainActor
public final class PeerService {
    public static let defaultServiceType = "_edgewake._tcp"
    /// Incoming connections that have not finished their handshake, at most. More are refused.
    static let maximumUnreadyIncomingLinks = 8
    /// After someone types too many wrong codes, this Mac refuses new pairing requests this long.
    static let wrongCodeCooldown: TimeInterval = 60

    public var onDiscoveredChange: (([DiscoveredMac]) -> Void)?
    public var onLinkEvent: ((PeerLink, LinkEvent) -> Void)?

    /// The long-term key for a paired Mac, `nil` for strangers.
    public var pairedKey: (UUID) -> Data? = { _ in nil }

    private let identity: LocalIdentity
    private let serviceType: String
    private let requiredInterface: NWInterface.InterfaceType?
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var links: [ObjectIdentifier: PeerLink] = [:]
    private var retryTimer: Timer?
    private var pairingRefusedUntil: Date?
    /// How long a link may take to become ready before it is dropped. Tests shorten it.
    var handshakeTimeout: TimeInterval = 10
    public private(set) var discovered: [UUID: DiscoveredMac] = [:] {
        didSet { onDiscoveredChange?(discovered.values.sorted { $0.name < $1.name }) }
    }

    /// `requiredInterface` restricts outgoing connections, for tests that must stay on loopback.
    public init(identity: LocalIdentity, serviceType: String = PeerService.defaultServiceType,
                requiredInterface: NWInterface.InterfaceType? = nil) {
        self.identity = identity
        self.serviceType = serviceType
        self.requiredInterface = requiredInterface
    }

    public func start() {
        startListener()
        startBrowser()
        retryTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.connectToPairedPeers() }
        }
    }

    /// The ready link to `peerID`, if any.
    public func link(to peerID: UUID) -> PeerLink? {
        links.values.first { $0.peerID == peerID && $0.isReady }
    }

    public func send(_ message: PeerMessage, to peerID: UUID) {
        link(to: peerID)?.send(message)
    }

    public func broadcast(_ message: PeerMessage) {
        for link in links.values where link.isReady {
            link.send(message)
        }
    }

    /// Starts pairing with a discovered Mac; it will show a code to type here.
    @discardableResult
    public func requestPairing(with peerID: UUID) -> PeerLink? {
        guard let mac = discovered[peerID] else { return nil }
        return open(NWConnection(to: mac.endpoint, using: PeerLink.parameters(requiredInterface: requiredInterface)),
             opening: .pairRequest, expectedPeer: peerID)
    }

    public func disconnect(from peerID: UUID) {
        for link in links.values where link.peerID == peerID {
            link.close()
        }
    }

    public func connectToPairedPeers() {
        for mac in discovered.values where pairedKey(mac.id) != nil {
            connect(to: mac.id)
        }
    }

    /// Opens an encrypted link to a discovered Mac unless one already exists. An unconfirmed
    /// incoming link does not count: anyone can claim a paired Mac's device ID in `hello`.
    public func connect(to peerID: UUID) {
        guard let mac = discovered[peerID],
              !links.values.contains(where: { $0.peerID == peerID && ($0.isReady || $0.isOutgoing) }) else { return }
        open(NWConnection(to: mac.endpoint, using: PeerLink.parameters(requiredInterface: requiredInterface)),
             opening: .hello, expectedPeer: peerID)
    }

    // MARK: - Private

    private func startListener() {
        do {
            let listener = try NWListener(using: PeerLink.parameters())
            listener.service = NWListener.Service(
                name: identity.name,
                type: serviceType,
                txtRecord: NWTXTRecord(["id": identity.id.uuidString])
            )
            listener.newConnectionHandler = { [weak self] connection in
                MainActor.assumeIsolated { self?.accept(connection) }
            }
            listener.stateUpdateHandler = { [weak self] state in
                if case .failed = state {
                    MainActor.assumeIsolated { self?.restartListenerLater() }
                }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            NSLog("EdgeWake: cannot listen: \(error)")
            restartListenerLater()
        }
    }

    private func restartListenerLater() {
        listener?.cancel()
        listener = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            MainActor.assumeIsolated { self?.startListener() }
        }
    }

    private func startBrowser() {
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: serviceType, domain: nil), using: NWParameters())
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            MainActor.assumeIsolated { self?.update(results) }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    private func update(_ results: Set<NWBrowser.Result>) {
        var found: [UUID: DiscoveredMac] = [:]
        for result in results {
            guard case let .bonjour(txt) = result.metadata, let idText = txt["id"], let id = UUID(uuidString: idText),
                  id != identity.id, case let .service(name, _, _, _) = result.endpoint else { continue }
            found[id] = DiscoveredMac(id: id, name: name, endpoint: result.endpoint)
        }
        if found != discovered {
            discovered = found
        }
        connectToPairedPeers()
    }

    private func accept(_ connection: NWConnection) {
        let unready = links.values.count { !$0.isOutgoing && !$0.isReady }
        guard unready < Self.maximumUnreadyIncomingLinks else {
            connection.cancel()
            return
        }
        open(connection, opening: .incoming, expectedPeer: nil)
    }

    @discardableResult
    private func open(_ connection: NWConnection, opening: PeerLink.Opening, expectedPeer: UUID?) -> PeerLink {
        let link = PeerLink(connection: connection, opening: opening, identity: identity, expectedPeer: expectedPeer,
                            handshakeTimeout: handshakeTimeout, keyLookup: { [weak self] id in self?.pairedKey(id) })
        link.onEvent = { [weak self] link, event in
            self?.handle(event, from: link)
        }
        links[ObjectIdentifier(link)] = link
        link.start()
        return link
    }

    /// Of two ready links to the same peer, the one dialled by the Mac with the smaller ID.
    private func preferredLink(_ a: PeerLink, _ b: PeerLink, peerID: UUID) -> PeerLink {
        let smallerIsMe = identity.id.uuidString < peerID.uuidString
        return a.isOutgoing == smallerIsMe ? a : b
    }

    private func handle(_ event: LinkEvent, from link: PeerLink) {
        switch event {
        case let .ready(peerID, _):
            let others = links.values.filter { $0 !== link && $0.peerID == peerID && $0.isReady }
            guard let other = others.first else { break }
            let preferred = preferredLink(link, other, peerID: peerID)
            // A wake in flight on the dropped link is lost; the sender's HUD times out.
            (preferred === link ? other : link).close()
            if preferred !== link { return }
        case .pairingCodeShown:
            if let until = pairingRefusedUntil, Date() < until {
                link.decline(.busy)
                return
            }
        case .pairingFailed(.wrongCode) where !link.isOutgoing:
            // The showing side reports a wrong code only once the limit is reached.
            pairingRefusedUntil = Date().addingTimeInterval(Self.wrongCodeCooldown)
        case .closed:
            links[ObjectIdentifier(link)] = nil
        default:
            break
        }
        onLinkEvent?(link, event)
    }
}
