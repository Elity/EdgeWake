import EdgeWakeCore
import EdgeWakePeer
import SwiftUI

/// The fixes offered under a check: confirm it, open the right settings page here, or ask a
/// paired Mac to open it on its own screen.
struct CheckActions: View {
    @Bindable var model: AppModel
    let check: CheckID
    let localState: CheckState?

    var body: some View {
        HStack {
            if check.needsConfirmation {
                Toggle("Confirmed", isOn: $model[confirmed: check])
                    .toggleStyle(.checkbox)
            }
            if localState == .failed || localState == .warning || check.needsConfirmation {
                Button("Open Settings", action: check.openSettings)
            }
            ForEach(peersNeedingAttention) { peer in
                Button("Show on \(peer.name)") { model.showCheckOnPeer(check, peerID: peer.id) }
            }
        }
        .controlSize(.small)
    }

    private var peersNeedingAttention: [PairedPeer] {
        model.pairedPeers.filter { peer in
            model.state(of: check, on: peer.id)?.needsAttention ?? false
        }
    }
}
