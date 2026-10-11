import Foundation

/// Decides which Macs an edge gesture wakes, and keeps the books on wakes in flight.
///
/// A Mac is woken when it is online, its display is off, it sits on the gesture's side (or its
/// side is unknown), no wake to it is awaiting an answer, and it last acknowledged a wake at least
/// `cooldown` seconds ago. The cooldown starts at the acknowledgement, so a wake that was lost
/// can be retried as soon as it times out.
public struct WakeScheduler: Sendable {
    public enum Decision: Equatable, Sendable {
        case wake([UUID])
        /// The gesture aimed at a Mac known to be on that side, but it is offline.
        case reportOffline(UUID)
        case nothing
    }

    public var cooldown: Double
    public var timeout: Double
    private var pending: [UUID: (peer: UUID, sentAt: Double)] = [:]
    private var lastAcknowledged: [UUID: Double] = [:]
    private var lastOfflineReport: [UUID: Double] = [:]

    public init(cooldown: Double = 10, timeout: Double = 4) {
        self.cooldown = cooldown
        self.timeout = timeout
    }

    public mutating func decide(gestureOn side: Side, peers: [WakeCandidate], now: Double) -> Decision {
        expire(at: now)
        let onThisSide = peers.filter { $0.side == nil || $0.side == side }
        let waking = onThisSide.filter {
            $0.isOnline && $0.displayAsleep && !isPending($0.id) && isPast(lastAcknowledged[$0.id], now)
        }
        if !waking.isEmpty {
            return .wake(waking.map(\.id))
        }
        // Only a Mac known to be on that side explains the gesture; an unplaced one may be anywhere.
        if let offline = onThisSide.first(where: { $0.side == side && !$0.isOnline }), isPast(lastOfflineReport[offline.id], now) {
            lastOfflineReport[offline.id] = now
            return .reportOffline(offline.id)
        }
        return .nothing
    }

    public mutating func sent(_ wakeID: UUID, to peer: UUID, at time: Double) {
        pending[wakeID] = (peer, time)
    }

    /// Returns the Mac that answered, or `nil` for an unknown or expired wake.
    public mutating func acknowledged(_ wakeID: UUID, at time: Double) -> UUID? {
        expire(at: time)
        guard let wake = pending.removeValue(forKey: wakeID) else { return nil }
        lastAcknowledged[wake.peer] = time
        return wake.peer
    }

    public mutating func hasPendingWakes(at time: Double) -> Bool {
        expire(at: time)
        return !pending.isEmpty
    }

    private func isPending(_ peer: UUID) -> Bool {
        pending.values.contains { $0.peer == peer }
    }

    private func isPast(_ time: Double?, _ now: Double) -> Bool {
        guard let time else { return true }
        return now - time >= cooldown
    }

    private mutating func expire(at time: Double) {
        pending = pending.filter { time - $0.value.sentAt < timeout }
    }
}
