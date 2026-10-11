import AppKit
import EdgeWakeCore

/// Watches pointer movement anywhere on screen. Global monitors for mouse events need no
/// Accessibility or Input Monitoring permission; a pointer pinned against an edge still produces
/// `mouseMoved` events, which is what the edge gesture relies on.
@MainActor
final class PointerMonitor {
    var onSample: ((PointerSample) -> Void)?
    private var monitors: [Any] = []

    func start() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.sample() }
            return event
        }) {
            monitors.append(local)
        }
    }

    private func sample() {
        let distances = ScreenEdges.distances(at: NSEvent.mouseLocation, screens: NSScreen.screens.map(\.frame))
        onSample?(PointerSample(
            time: ProcessInfo.processInfo.systemUptime,
            distanceToLeft: distances.left,
            distanceToRight: distances.right,
            buttonsDown: NSEvent.pressedMouseButtons != 0
        ))
    }
}
