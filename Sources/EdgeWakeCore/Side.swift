/// A horizontal side of this Mac's screen layout. Universal Control places neighbours left or right.
public enum Side: String, Codable, Sendable, CaseIterable {
    case left
    case right

    public var opposite: Side {
        self == .left ? .right : .left
    }
}
