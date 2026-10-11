/// Learns which side the peer is on from a real Universal Control crossing: the pointer was last
/// seen at this Mac's outer edge on side S, and moments later the peer reports the pointer
/// arriving at its opposite edge. That pairing is unambiguous, so the caller can trust the result.
public struct SideLearner: Sendable {
    /// Seconds between the last local touch and the peer's report.
    public var maximumDelay: Double
    private var candidate: (side: Side, time: Double)?

    public init(maximumDelay: Double = 0.7) {
        self.maximumDelay = maximumDelay
    }

    public mutating func localTouchedEdge(_ side: Side, at time: Double) {
        candidate = (side, time)
    }

    /// The pointer is still on this Mac, away from the edge, so it did not cross.
    public mutating func localMovedAway(at time: Double) {
        candidate = nil
    }

    /// `edge` is the peer's own edge where the pointer appeared. `time` is when the report was
    /// received here, so both times come from this Mac's clock.
    public mutating func peerReportedEntry(from edge: Side, at time: Double) -> Side? {
        defer { candidate = nil }
        guard let candidate, edge == candidate.side.opposite, time - candidate.time <= maximumDelay else { return nil }
        return candidate.side
    }
}
