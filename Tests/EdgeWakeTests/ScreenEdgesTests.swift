import CoreGraphics
import Testing
@testable import EdgeWakeCore

@Suite struct ScreenEdgesTests {
    private let builtIn = CGRect(x: 0, y: 0, width: 1512, height: 982)
    /// An external display to the left of the built-in one, taller and offset upwards.
    private let external = CGRect(x: -1920, y: 0, width: 1920, height: 1080)

    @Test func singleDisplayMeasuresBothEdges() {
        let d = ScreenEdges.distances(at: CGPoint(x: 0, y: 500), screens: [builtIn])
        #expect(d.left == 0)
        #expect(d.right == 1511)
    }

    @Test func pointerPinnedToTheRightIsAtZero() {
        let d = ScreenEdges.distances(at: CGPoint(x: 1511, y: 500), screens: [builtIn])
        #expect(d.right == 0)
    }

    @Test func edgeSharedWithAnotherDisplayIsNotOuter() {
        let d = ScreenEdges.distances(at: CGPoint(x: 0, y: 500), screens: [builtIn, external])
        #expect(d.left == .infinity)
        let outer = ScreenEdges.distances(at: CGPoint(x: -1920, y: 500), screens: [builtIn, external])
        #expect(outer.left == 0)
    }

    @Test func sharedEdgeIsOuterWhereTheNeighbourEnds() {
        // The external display is 1080 tall; above that the built-in display's left edge is outer.
        let tall = CGRect(x: 0, y: 0, width: 1512, height: 1400)
        let d = ScreenEdges.distances(at: CGPoint(x: 0, y: 1200), screens: [tall, external])
        #expect(d.left == 0)
    }

    @Test func pointOutsideEveryDisplayIsFarFromEdges() {
        let d = ScreenEdges.distances(at: CGPoint(x: 5000, y: 5000), screens: [builtIn])
        #expect(d.left == .infinity && d.right == .infinity)
    }
}
