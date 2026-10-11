import EdgeWakeCore
import SwiftUI

/// Step 3: every setting Universal Control needs, for this Mac and each paired Mac side by side.
struct ChecklistSection: View {
    let model: AppModel

    var body: some View {
        Section {
            ForEach(CheckID.allCases, id: \.self) { check in
                CheckRow(model: model, check: check)
            }
        } header: {
            HStack {
                Text("Check Both Macs")
                Spacer()
                ChecklistColumnHeader(title: "This Mac")
                ForEach(model.pairedPeers) { peer in
                    ChecklistColumnHeader(title: "\(peer.name)")
                }
            }
        } footer: {
            Text("Settings on the other Mac are changed on that Mac. “Show on …” opens the right page on its screen.")
                .foregroundStyle(.secondary)
        }
    }
}
