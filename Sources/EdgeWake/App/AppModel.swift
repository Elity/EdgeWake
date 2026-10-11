import AppKit
import EdgeWakeCore
import EdgeWakePeer
import KeyboardShortcuts
import Observation
import ServiceManagement
import UserNotifications

/// Wires the parts together and holds the state the UI shows. Behaviour lives in the parts:
/// `PeerService` (network), `EdgeTrigger` (gesture), `DisplayStateMonitor`/`DisplayWaker`
/// (this Mac's display) and `SystemChecks` (settings).
@MainActor
@Observable
final class AppModel {
    let identity: LocalIdentity
    private(set) var pairedPeers: [PairedPeer]
    private(set) var peerStatus: [UUID: PeerStatus] = [:]
    private(set) var onlinePeers: Set<UUID> = []
    private(set) var discovered: [DiscoveredMac] = []
    private(set) var localChecks: [CheckResult] = []
    private(set) var localDisplayAsleep = false
    private(set) var pairing: PairingState = .idle
    private(set) var highlightedCheck: CheckID?

    var bumpsRequired: Int {
        didSet { defaults.set(bumpsRequired, forKey: Keys.bumpsRequired); applyGestureConfiguration() }
    }
    var bumpWindow: Double {
        didSet { defaults.set(bumpWindow, forKey: Keys.bumpWindow); applyGestureConfiguration() }
    }
    var confirmedSameAppleID: Bool {
        didSet { defaults.set(confirmedSameAppleID, forKey: Keys.sameAppleID); refreshChecks() }
    }
    var confirmedUniversalControl: Bool {
        didSet { defaults.set(confirmedUniversalControl, forKey: Keys.universalControl); refreshChecks() }
    }
    var setupCompleted: Bool {
        didSet { defaults.set(setupCompleted, forKey: Keys.setupCompleted) }
    }
    var launchAtLogin: Bool {
        didSet { setLoginItem(launchAtLogin) }
    }

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let store = PeerStore()
    @ObservationIgnored private let service: PeerService
    @ObservationIgnored private let display = DisplayStateMonitor()
    @ObservationIgnored private let pointer = PointerMonitor()
    @ObservationIgnored private let trigger = EdgeTrigger()
    @ObservationIgnored private let hud = WakeHUD()
    @ObservationIgnored private weak var pairingLink: PeerLink?
    @ObservationIgnored private var scheduler = WakeScheduler()
    /// Discards results from a check run that a newer one has overtaken.
    @ObservationIgnored private var checksGeneration = 0
    @ObservationIgnored private var checksTimer: Timer?
    /// Brings the Setup window forward; installed by the app, which owns the window.
    @ObservationIgnored var showSetup: () -> Void = {}

    private enum Keys {
        static let deviceID = "deviceID"
        static let bumpsRequired = "bumpsRequired"
        static let bumpWindow = "bumpWindow"
        static let sameAppleID = "confirmedSameAppleID"
        static let universalControl = "confirmedUniversalControl"
        static let setupCompleted = "setupCompleted"
        static let loginItemConfigured = "loginItemConfigured"
    }

    init() {
        let deviceID = defaults.string(forKey: Keys.deviceID).flatMap(UUID.init(uuidString:)) ?? UUID()
        defaults.set(deviceID.uuidString, forKey: Keys.deviceID)
        let identity = LocalIdentity(id: deviceID, name: Host.current().localizedName ?? "Mac")
        self.identity = identity
        pairedPeers = store.load()
        bumpsRequired = defaults.object(forKey: Keys.bumpsRequired) as? Int ?? 2
        bumpWindow = defaults.object(forKey: Keys.bumpWindow) as? Double ?? 0.6
        confirmedSameAppleID = defaults.bool(forKey: Keys.sameAppleID)
        confirmedUniversalControl = defaults.bool(forKey: Keys.universalControl)
        setupCompleted = defaults.bool(forKey: Keys.setupCompleted)
        launchAtLogin = SMAppService.mainApp.status == .enabled
        service = PeerService(identity: identity)
    }

    var isBundled: Bool { Bundle.main.bundleIdentifier != nil }

    var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    func start() {
        service.pairedKey = { [weak self] id in self?.pairedPeers.first { $0.id == id }?.key }
        service.onDiscoveredChange = { [weak self] macs in self?.discovered = macs }
        service.onLinkEvent = { [weak self] link, event in self?.handle(event, from: link) }
        service.start()

        localDisplayAsleep = display.isAsleep
        display.onChange = { [weak self] asleep in
            self?.localDisplayAsleep = asleep
            self?.broadcastStatus()
        }
        display.start()

        applyGestureConfiguration()
        trigger.onGesture = { [weak self] side in self?.gestureCompleted(on: side) }
        trigger.onArrival = { [weak self] edge in self?.service.broadcast(.pointerEntered(edge: edge)) }
        pointer.onSample = { [weak self] sample in self?.trigger.handle(sample) }
        pointer.start()

        KeyboardShortcuts.onKeyUp(for: .wakePeers) { [weak self] in self?.wakeAll() }

        refreshChecks()
        checksTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshChecks() }
        }

        if isBundled, !defaults.bool(forKey: Keys.loginItemConfigured) {
            defaults.set(true, forKey: Keys.loginItemConfigured)
            launchAtLogin = true
        }
        if !setupCompleted {
            DispatchQueue.main.async { [weak self] in self?.requestSetupWindow() }
        }
    }

    // MARK: - Queries for the UI

    func presence(of peerID: UUID) -> PeerPresence {
        guard onlinePeers.contains(peerID), let status = peerStatus[peerID] else { return .offline }
        return status.displayAsleep ? .screenOff : .screenOn
    }

    /// A paired Mac's checks; `nil` while it is offline, since what it last reported may be stale.
    func peerChecks(_ peerID: UUID) -> [CheckResult]? {
        onlinePeers.contains(peerID) ? peerStatus[peerID]?.checks : nil
    }

    /// The state of one check on this Mac (`peerID == nil`) or on a paired Mac.
    func state(of check: CheckID, on peerID: UUID? = nil) -> CheckState? {
        let checks = peerID.map(peerChecks) ?? localChecks
        return checks?.first { $0.id == check }?.state
    }

    var unpairedDiscovered: [DiscoveredMac] {
        discovered.filter { mac in !pairedPeers.contains { $0.id == mac.id } }
    }

    var needsAttention: Bool {
        localChecks.contains { $0.state.needsAttention }
            || pairedPeers.contains { peerChecks($0.id)?.contains { $0.state.needsAttention } ?? false }
    }

    // MARK: - Waking

    func wakeAll() {
        guard !pairedPeers.isEmpty else { return }
        for peer in pairedPeers {
            wake(peer.id)
        }
    }

    func wake(_ peerID: UUID) {
        guard let peer = pairedPeers.first(where: { $0.id == peerID }) else { return }
        guard onlinePeers.contains(peerID) else {
            showOffline(peer)
            return
        }
        let wakeID = UUID()
        scheduler.sent(wakeID, to: peerID, at: now)
        service.send(.wake(id: wakeID), to: peerID)
        hud.show(String(localized: "Waking \(peer.name)…"), symbol: "display", duration: scheduler.timeout)
    }

    private func gestureCompleted(on side: Side) {
        guard !FullscreenDetector.frontmostAppIsFullscreen() else { return }
        let candidates = pairedPeers.map {
            WakeCandidate(id: $0.id, side: $0.side, isOnline: onlinePeers.contains($0.id),
                          displayAsleep: peerStatus[$0.id]?.displayAsleep == true)
        }
        switch scheduler.decide(gestureOn: side, peers: candidates, now: now) {
        case let .wake(peerIDs):
            peerIDs.forEach(wake)
        case let .reportOffline(peerID):
            if let peer = pairedPeers.first(where: { $0.id == peerID }) {
                showOffline(peer)
            }
        case .nothing:
            break
        }
    }

    private func showOffline(_ peer: PairedPeer) {
        hud.show(String(localized: "\(peer.name) is offline"), symbol: "wifi.slash", duration: 2)
    }

    private var now: Double {
        ProcessInfo.processInfo.systemUptime
    }

    // MARK: - Pairing

    func startPairing(with mac: DiscoveredMac) {
        guard !pairing.isInProgress else { return }
        guard let link = service.requestPairing(with: mac.id) else {
            pairing = .failed(.declined)
            return
        }
        // Held from the start, so a connection that fails before the other Mac answers ends the attempt.
        pairingLink = link
        pairing = .connecting(peerName: mac.name)
    }

    func submitPairingCode(_ code: String) {
        guard case let .enteringCode(name, _) = pairing else { return }
        pairing = .verifying(peerName: name)
        pairingLink?.submitCode(code)
    }

    func cancelPairing() {
        pairingLink?.close()
        pairingLink = nil
        pairing = .idle
    }

    func dismissPairingResult() {
        if !pairing.isInProgress {
            pairing = .idle
        }
    }

    func unpair(_ peerID: UUID) {
        // Tell the other Mac first, so it forgets this one too instead of retrying forever.
        service.send(.unpaired, to: peerID)
        forget(peerID)
    }

    private func forget(_ peerID: UUID) {
        pairedPeers.removeAll { $0.id == peerID }
        peerStatus[peerID] = nil
        onlinePeers.remove(peerID)
        store.save(pairedPeers)
        service.disconnect(from: peerID)
    }

    /// Bindable as `$model[sideFor: id]`.
    subscript(sideFor peerID: UUID) -> Side? {
        get { pairedPeers.first { $0.id == peerID }?.side }
        set {
            guard let index = pairedPeers.firstIndex(where: { $0.id == peerID }) else { return }
            pairedPeers[index].side = newValue
            store.save(pairedPeers)
        }
    }

    /// Bindable as `$model[confirmed: check]` for checks the person confirms themselves.
    subscript(confirmed check: CheckID) -> Bool {
        get {
            switch check {
            case .sameAppleID: confirmedSameAppleID
            case .universalControl: confirmedUniversalControl
            default: false
            }
        }
        set {
            switch check {
            case .sameAppleID: confirmedSameAppleID = newValue
            case .universalControl: confirmedUniversalControl = newValue
            default: break
            }
        }
    }

    // MARK: - Checks

    func refreshChecks() {
        let confirmations = SystemChecks.Confirmations(sameAppleID: confirmedSameAppleID, universalControl: confirmedUniversalControl)
        checksGeneration += 1
        let generation = checksGeneration
        Task {
            let checks = await SystemChecks.run(confirmations: confirmations)
            if generation == checksGeneration, checks != localChecks {
                localChecks = checks
                broadcastStatus()
            }
        }
    }

    func showCheckOnPeer(_ check: CheckID, peerID: UUID) {
        service.send(.showCheck(check), to: peerID)
    }

    func clearHighlight() {
        highlightedCheck = nil
    }

    func requestSetupWindow() {
        showSetup()
    }

    // MARK: - Link events

    private func handle(_ event: LinkEvent, from link: PeerLink) {
        switch event {
        case let .ready(peerID, name):
            onlinePeers.insert(peerID)
            if let index = pairedPeers.firstIndex(where: { $0.id == peerID }), pairedPeers[index].name != name {
                pairedPeers[index].name = name
                store.save(pairedPeers)
            }
            link.send(.status(currentStatus))

        case let .message(message):
            guard let peerID = link.peerID else { return }
            handle(message, from: peerID)

        case .closed:
            if let peerID = link.peerID, service.link(to: peerID) == nil {
                onlinePeers.remove(peerID)
            }
            if link === pairingLink, pairing.isInProgress {
                // The showing Mac hangs up after too many wrong codes.
                if case .enteringCode(_, lastAttemptWrong: true) = pairing {
                    pairing = .failed(.wrongCode)
                } else {
                    pairing = .failed(.declined)
                }
                pairingLink = nil
            }

        case let .pairingCodeShown(code, peerName):
            if pairing.isInProgress {
                link.decline(.busy)
                return
            }
            pairingLink = link
            pairing = .showingCode(code: code, peerName: peerName)
            requestSetupWindow()

        case let .pairingCodeNeeded(peerName):
            pairingLink = link
            pairing = .enteringCode(peerName: peerName, lastAttemptWrong: false)

        case let .paired(peer):
            pairedPeers.removeAll { $0.id == peer.id }
            pairedPeers.append(peer)
            store.save(pairedPeers)
            pairingLink = nil
            pairing = .paired(peerName: peer.name)
            service.connectToPairedPeers()

        case let .pairingFailed(reason):
            if reason == .wrongCode, case let .verifying(name) = pairing {
                pairing = .enteringCode(peerName: name, lastAttemptWrong: true)
            } else if pairing.isInProgress {
                pairing = .failed(reason)
                pairingLink = nil
            }
        }
    }

    private func handle(_ message: PeerMessage, from peerID: UUID) {
        switch message {
        case let .status(status):
            peerStatus[peerID] = status

        case let .wake(wakeID):
            DisplayWaker.wake()
            service.send(.wakeAck(id: wakeID), to: peerID)

        case let .wakeAck(wakeID):
            // Keep the bubble while another Mac woken by the same gesture has yet to answer.
            if scheduler.acknowledged(wakeID, at: now) != nil, !scheduler.hasPendingWakes(at: now) {
                hud.hide()
            }

        case .unpaired:
            service.disconnect(from: peerID)
            forget(peerID)

        case let .pointerEntered(edge):
            guard let side = trigger.peerReportedArrival(at: edge),
                  let index = pairedPeers.firstIndex(where: { $0.id == peerID }),
                  pairedPeers[index].side != side else { return }
            let hadSide = pairedPeers[index].side != nil
            pairedPeers[index].side = side
            store.save(pairedPeers)
            if hadSide {
                notifySideChanged(pairedPeers[index])
            }

        case let .showCheck(check):
            highlightedCheck = check
            requestSetupWindow()
        }
    }

    // MARK: - Helpers

    private var currentStatus: PeerStatus {
        PeerStatus(name: identity.name, displayAsleep: localDisplayAsleep, checks: localChecks, version: version)
    }

    private func broadcastStatus() {
        service.broadcast(.status(currentStatus))
    }

    private func applyGestureConfiguration() {
        trigger.configuration = EdgeGesture.Configuration(bumpsRequired: bumpsRequired, window: bumpWindow)
    }

    private func setLoginItem(_ enabled: Bool) {
        guard isBundled else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("EdgeWake: login item change failed: \(error)")
        }
        let actual = SMAppService.mainApp.status == .enabled
        if actual != launchAtLogin {
            launchAtLogin = actual
        }
    }

    private func notifySideChanged(_ peer: PairedPeer) {
        guard isBundled else { return }
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = String(localized: "\(peer.name) moved")
        content.body = peer.side == .left
            ? String(localized: "EdgeWake now wakes \(peer.name) from the left edge.")
            : String(localized: "EdgeWake now wakes \(peer.name) from the right edge.")
        Task {
            _ = try? await center.requestAuthorization(options: [.alert])
            try? await center.add(UNNotificationRequest(identifier: "side-\(peer.id)", content: content, trigger: nil))
        }
    }
}

#if DEBUG
extension AppModel {
    /// Fills the model with a paired, half-configured Mac mini for UI snapshots. Debug builds only.
    func loadSnapshotState(pairing: PairingState) {
        let mini = PairedPeer(id: UUID(), name: "Fighting的Mac mini", key: Data(count: 32), side: .left)
        pairedPeers = [mini]
        onlinePeers = [mini.id]
        peerStatus[mini.id] = PeerStatus(name: mini.name, displayAsleep: true, checks: [
            CheckResult(id: .wifi, state: .passed),
            CheckResult(id: .bluetooth, state: .failed),
            CheckResult(id: .handoff, state: .passed),
            CheckResult(id: .firewall, state: .passed),
            CheckResult(id: .sameAppleID, state: .unconfirmed),
            CheckResult(id: .universalControl, state: .passed),
            CheckResult(id: .systemSleep, state: .passed),
        ], version: version)
        self.pairing = pairing
    }
}
#endif
