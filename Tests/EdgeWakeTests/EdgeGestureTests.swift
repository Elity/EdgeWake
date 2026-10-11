import Testing
@testable import EdgeWakeCore

@Suite struct EdgeGestureTests {
    /// A pointer sample `x` pixels away from the left outer edge (and far from the right one).
    private func left(_ x: Double, at time: Double, buttons: Bool = false) -> PointerSample {
        PointerSample(time: time, distanceToLeft: x, distanceToRight: 1000, buttonsDown: buttons)
    }

    private func right(_ x: Double, at time: Double) -> PointerSample {
        PointerSample(time: time, distanceToLeft: 1000, distanceToRight: x, buttonsDown: false)
    }

    @Test func twoBumpsWithinWindowTrigger() {
        var gesture = EdgeGesture()
        #expect(gesture.observe(left(0, at: 0.0)) == nil)
        #expect(gesture.observe(left(20, at: 0.1)) == nil)
        #expect(gesture.observe(left(0, at: 0.3)) == .left)
    }

    @Test func singleBumpNeverTriggers() {
        var gesture = EdgeGesture()
        #expect(gesture.observe(left(0, at: 0.0)) == nil)
        // Pinned against the edge: many samples, still one bump.
        for step in 1...50 {
            #expect(gesture.observe(left(0, at: Double(step) * 0.01)) == nil)
        }
    }

    @Test func mustLeaveTheEdgeByReleaseDistanceBetweenBumps() {
        var gesture = EdgeGesture()
        _ = gesture.observe(left(0, at: 0.0))
        _ = gesture.observe(left(5, at: 0.1)) // less than 8px: still the same bump
        #expect(gesture.observe(left(0, at: 0.2)) == nil)
        _ = gesture.observe(left(8, at: 0.3))
        #expect(gesture.observe(left(0, at: 0.4)) == .left)
    }

    @Test func bumpsOutsideTheWindowDoNotCount() {
        var gesture = EdgeGesture()
        _ = gesture.observe(left(0, at: 0.0))
        _ = gesture.observe(left(30, at: 0.3))
        #expect(gesture.observe(left(0, at: 0.7)) == nil) // 0.7s after the first bump
        _ = gesture.observe(left(30, at: 0.8))
        #expect(gesture.observe(left(0, at: 1.0)) == .left) // 0.3s after the previous one
    }

    @Test func heldButtonCancelsTheGesture() {
        var gesture = EdgeGesture()
        _ = gesture.observe(left(0, at: 0.0))
        _ = gesture.observe(left(30, at: 0.1, buttons: true))
        #expect(gesture.observe(left(0, at: 0.2, buttons: true)) == nil)
        _ = gesture.observe(left(30, at: 0.3))
        #expect(gesture.observe(left(0, at: 0.4)) == nil) // the dragged bump did not count
    }

    @Test func switchingSidesStartsOver() {
        var gesture = EdgeGesture()
        _ = gesture.observe(left(0, at: 0.0))
        _ = gesture.observe(right(0, at: 0.1))
        _ = gesture.observe(right(30, at: 0.2))
        #expect(gesture.observe(left(0, at: 0.3)) == nil)
    }

    @Test func gestureResetsAfterTriggering() {
        var gesture = EdgeGesture()
        _ = gesture.observe(left(0, at: 0.0))
        _ = gesture.observe(left(20, at: 0.1))
        #expect(gesture.observe(left(0, at: 0.2)) == .left)
        _ = gesture.observe(left(20, at: 0.3))
        #expect(gesture.observe(left(0, at: 0.4)) == nil)
    }

    @Test func requiredBumpsIsConfigurable() {
        var gesture = EdgeGesture(configuration: .init(bumpsRequired: 3, window: 1.0))
        _ = gesture.observe(left(0, at: 0.0))
        _ = gesture.observe(left(20, at: 0.1))
        #expect(gesture.observe(left(0, at: 0.2)) == nil)
        _ = gesture.observe(left(20, at: 0.3))
        #expect(gesture.observe(left(0, at: 0.4)) == .left)
    }
}
