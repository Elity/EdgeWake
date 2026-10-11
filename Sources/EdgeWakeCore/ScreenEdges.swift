import CoreGraphics

/// Distances from a pointer to the outer left and right edges of a multi-display layout.
/// An edge is outer when no other display of this Mac continues past it at the pointer's height;
/// edges between this Mac's own displays report `.infinity`. Coordinates are AppKit screen space,
/// where a pointer pinned to the right edge sits one point inside `maxX`.
public enum ScreenEdges {
    public static func distances(at point: CGPoint, screens: [CGRect]) -> (left: Double, right: Double) {
        guard let screen = screens.first(where: { contains($0, point) }) else { return (.infinity, .infinity) }
        let y = point.y
        let hasLeftNeighbour = screens.contains { $0 != screen && abs($0.maxX - screen.minX) < 1 && $0.minY <= y && y < $0.maxY }
        let hasRightNeighbour = screens.contains { $0 != screen && abs($0.minX - screen.maxX) < 1 && $0.minY <= y && y < $0.maxY }
        let left = hasLeftNeighbour ? .infinity : max(0, point.x - screen.minX)
        let right = hasRightNeighbour ? .infinity : max(0, screen.maxX - 1 - point.x)
        return (Double(left), Double(right))
    }

    private static func contains(_ rect: CGRect, _ point: CGPoint) -> Bool {
        rect.minX <= point.x && point.x < rect.maxX && rect.minY <= point.y && point.y <= rect.maxY
    }
}
