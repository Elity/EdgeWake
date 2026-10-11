import AppKit
import SwiftUI

/// Owns the Setup window. AppKit rather than a SwiftUI `Window` scene because the model asks for it
/// at moments no view is on screen (first launch, a pairing request, a peer's "Show on…").
@MainActor
final class SetupWindowController {
    private var window: NSWindow?

    func show(model: AppModel) {
        let window = window ?? makeWindow(model: model)
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow(model: AppModel) -> NSWindow {
        let host = NSHostingController(rootView: SetupView(model: model) { [weak self] in self?.window?.close() })
        // Let the Form scroll instead of growing the window to its full content height.
        host.sizingOptions = []
        let window = NSWindow(contentViewController: host)
        window.title = String(localized: "Set Up EdgeWake")
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 620, height: 700))
        window.contentMinSize = NSSize(width: 560, height: 420)
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("EdgeWake Setup")
        return window
    }
}
