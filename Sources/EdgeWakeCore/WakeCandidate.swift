import Foundation

/// What the scheduler needs to know about one paired Mac at the moment of a gesture.
public struct WakeCandidate: Sendable, Equatable {
    public var id: UUID
    public var side: Side?
    public var isOnline: Bool
    public var displayAsleep: Bool

    public init(id: UUID, side: Side?, isOnline: Bool, displayAsleep: Bool) {
        self.id = id
        self.side = side
        self.isOnline = isOnline
        self.displayAsleep = displayAsleep
    }
}
