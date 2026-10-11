/// One pointer event, reduced to what the gesture needs. Distances are measured from the pointer to
/// the outer left and right edges of the screen layout; an edge shared with another of this Mac's
/// displays is not outer and should be reported as a large distance.
public struct PointerSample: Sendable {
    public var time: Double
    public var distanceToLeft: Double
    public var distanceToRight: Double
    public var buttonsDown: Bool

    public init(time: Double, distanceToLeft: Double, distanceToRight: Double, buttonsDown: Bool) {
        self.time = time
        self.distanceToLeft = distanceToLeft
        self.distanceToRight = distanceToRight
        self.buttonsDown = buttonsDown
    }

    func distance(to side: Side) -> Double {
        side == .left ? distanceToLeft : distanceToRight
    }
}

/// Recognises "bump the outer edge N times in quick succession". A pointer pinned against an edge
/// keeps producing events at distance zero; that is one bump, and the pointer must move at least
/// `releaseDistance` away before the next touch counts. Whether a recognised gesture should wake
/// anything (peer asleep, side allowed, cooldown) is the caller's decision.
public struct EdgeGesture: Sendable {
    public struct Configuration: Sendable, Equatable {
        public var bumpsRequired: Int
        /// Seconds from the first to the last bump.
        public var window: Double
        public var releaseDistance: Double
        public var touchTolerance: Double

        public init(bumpsRequired: Int = 2, window: Double = 0.6, releaseDistance: Double = 8, touchTolerance: Double = 1) {
            self.bumpsRequired = max(1, bumpsRequired)
            self.window = window
            self.releaseDistance = releaseDistance
            self.touchTolerance = touchTolerance
        }
    }

    public var configuration: Configuration
    private var side: Side?
    private var touching = false
    private var bumps: [Double] = []

    public init(configuration: Configuration = .init()) {
        self.configuration = configuration
    }

    /// Feeds one sample; returns the side when the gesture completes.
    public mutating func observe(_ sample: PointerSample) -> Side? {
        if sample.buttonsDown {
            reset()
            return nil
        }
        guard let touched = Side.allCases.first(where: { sample.distance(to: $0) <= configuration.touchTolerance }) else {
            if touching, let side, sample.distance(to: side) >= configuration.releaseDistance {
                touching = false
            }
            return nil
        }
        if touched != side {
            bumps = []
            side = touched
        } else if touching {
            return nil
        }
        touching = true
        bumps = bumps.filter { sample.time - $0 <= configuration.window }
        bumps.append(sample.time)
        guard bumps.count >= configuration.bumpsRequired else { return nil }
        bumps = []
        return touched
    }

    public mutating func reset() {
        side = nil
        touching = false
        bumps = []
    }
}
