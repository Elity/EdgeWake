import AppKit

/// Reports whether this Mac's displays are asleep. Universal Control drops a Mac whose display is
/// off even though the Mac itself is awake, so this is the state peers care about.
@MainActor
final class DisplayStateMonitor {
    var onChange: ((Bool) -> Void)?
    private(set) var isAsleep = CGDisplayIsAsleep(CGMainDisplayID()) != 0
    private var observers: [NSObjectProtocol] = []

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        for (name, asleep) in [(NSWorkspace.screensDidSleepNotification, true), (NSWorkspace.screensDidWakeNotification, false)] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.update(asleep) }
            })
        }
    }

    private func update(_ asleep: Bool) {
        guard asleep != isAsleep else { return }
        isAsleep = asleep
        onChange?(asleep)
    }
}
