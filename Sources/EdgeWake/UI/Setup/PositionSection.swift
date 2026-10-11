import EdgeWakeCore
import SwiftUI

/// Step 2: which side each paired Mac is on, matching the Universal Control arrangement.
struct PositionSection: View {
    @Bindable var model: AppModel

    var body: some View {
        Section {
            ForEach(model.pairedPeers) { peer in
                Picker(peer.name, selection: $model[sideFor: peer.id]) {
                    Text("On the left").tag(Side?.some(.left))
                    Text("On the right").tag(Side?.some(.right))
                }
                .pickerStyle(.segmented)
            }
        } header: {
            Text("Where Is Each Mac?")
        } footer: {
            Text("Bump the edge facing that Mac to wake it. If you rearrange the Macs in Universal Control, EdgeWake notices the next time the pointer crosses and updates this for you.")
                .foregroundStyle(.secondary)
        }
    }
}
