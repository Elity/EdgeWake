import KeyboardShortcuts
import SwiftUI

/// The menu shown from the menu bar icon. A native menu rather than a popover, as the HIG asks of
/// menu bar extras: each paired Mac is a section with its state and a Wake item.
struct MenuPanel: View {
    let model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        if model.pairedPeers.isEmpty {
            Text("No Mac Paired Yet")
        }
        ForEach(model.pairedPeers) { peer in
            Section(peer.name) {
                PeerMenuItems(peer: peer, presence: model.presence(of: peer.id)) {
                    model.wake(peer.id)
                }
            }
        }

        Divider()

        Button("Wake All Macs", action: model.wakeAll)
            .globalKeyboardShortcut(.wakePeers)
            .disabled(model.pairedPeers.isEmpty)

        Divider()

        if model.needsAttention {
            Button("Some Settings Need Attention…", systemImage: "exclamationmark.triangle", action: model.requestSetupWindow)
        }
        Button("Set Up EdgeWake…", action: model.requestSetupWindow)
        Button("Settings…", action: showSettings)
            .keyboardShortcut(",")

        Divider()

        Button("Quit EdgeWake", action: quit)
            .keyboardShortcut("q")
    }

    private func showSettings() {
        NSApp.activate()
        openSettings()
    }

    private func quit() {
        NSApp.terminate(nil)
    }
}
