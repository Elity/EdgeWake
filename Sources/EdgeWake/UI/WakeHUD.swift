import AppKit
import SwiftUI

/// A small non-activating bubble next to the pointer, so a gesture or shortcut visibly registers.
@MainActor
final class WakeHUD {
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    func show(_ message: String, symbol: String, duration: TimeInterval = 4) {
        let panel = panel ?? makePanel()
        self.panel = panel
        let host = NSHostingView(rootView: HUDBubble(message: message, symbol: symbol))
        panel.contentView = host
        panel.setContentSize(host.fittingSize)

        // Keep the bubble on the screen under the pointer, offset so it does not hide the cursor.
        let mouse = NSEvent.mouseLocation
        let visible = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }?.visibleFrame ?? .zero
        let size = panel.frame.size
        var origin = CGPoint(x: mouse.x + 16, y: mouse.y - size.height - 16)
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    func hide() {
        hideWork?.cancel()
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        return panel
    }
}

private struct HUDBubble: View {
    let message: String
    let symbol: String

    var body: some View {
        Label(message, systemImage: symbol)
            .font(.callout.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: .capsule)
            .overlay(Capsule().strokeBorder(.separator, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
            .padding(8)
            .fixedSize()
    }
}
