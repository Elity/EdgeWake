import EdgeWakeCore
import Foundation

/// Turns pointer samples into the three things the app cares about: the wake gesture, the pointer
/// arriving from another Mac, and (with the peer's help) which side that Mac is on.
@MainActor
final class EdgeTrigger {
    /// The edge gesture completed on this side.
    var onGesture: ((Side) -> Void)?
    /// The pointer appeared at this outer edge after being away, as when Universal Control
    /// brings it over from a neighbouring Mac.
    var onArrival: ((Side) -> Void)?

    var configuration: EdgeGesture.Configuration {
        get { gesture.configuration }
        set { gesture.configuration = newValue }
    }

    private var gesture = EdgeGesture()
    private var learner = SideLearner()
    private var lastSample: PointerSample?
    private static let absenceBeforeArrival = 0.5
    private static let arrivalTolerance = 2.0

    func handle(_ sample: PointerSample) {
        defer { lastSample = sample }

        // The pointer left this Mac through an edge and, after a pause, came back through the
        // same edge: Universal Control returning it. A pointer that rested elsewhere is not.
        if let last = lastSample, sample.time - last.time > Self.absenceBeforeArrival,
           let edge = Side.allCases.first(where: { distance(sample, $0) <= Self.arrivalTolerance && distance(last, $0) <= Self.arrivalTolerance }) {
            onArrival?(edge)
        }

        if let touched = Side.allCases.first(where: { distance(sample, $0) <= gesture.configuration.touchTolerance }) {
            learner.localTouchedEdge(touched, at: sample.time)
        } else {
            learner.localMovedAway(at: sample.time)
        }

        if let side = gesture.observe(sample) {
            onGesture?(side)
        }
    }

    /// The peer saw the pointer arrive at its `edge`. Returns the side the peer must be on, when
    /// the pointer had just left this Mac through the opposite edge.
    func peerReportedArrival(at edge: Side) -> Side? {
        learner.peerReportedEntry(from: edge, at: ProcessInfo.processInfo.systemUptime)
    }

    private func distance(_ sample: PointerSample, _ side: Side) -> Double {
        side == .left ? sample.distanceToLeft : sample.distanceToRight
    }
}
