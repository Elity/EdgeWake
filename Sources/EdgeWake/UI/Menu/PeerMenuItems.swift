import EdgeWakeCore
import EdgeWakePeer
import SwiftUI

/// The items for one paired Mac: its state as a disabled line, then the Wake command.
struct PeerMenuItems: View {
    let peer: PairedPeer
    let presence: PeerPresence
    let wake: () -> Void

    var body: some View {
        switch peer.side {
        case .left: Text("\(Text(presence.label)) · On the Left")
        case .right: Text("\(Text(presence.label)) · On the Right")
        case nil: Text(presence.label)
        }
        Button("Wake Display", action: wake)
            .disabled(presence == .offline)
    }
}
