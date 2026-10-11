import EdgeWakeCore
import SwiftUI

/// One check: what it means, its state on every Mac, and the way to fix it.
struct CheckRow: View {
    let model: AppModel
    let check: CheckID

    var body: some View {
        let localState = model.state(of: check)
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(check.title)
                Text(check.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                CheckActions(model: model, check: check, localState: localState)
            }
            Spacer()
            CheckStateBadge(state: localState)
            ForEach(model.pairedPeers) { peer in
                CheckStateBadge(state: model.state(of: check, on: peer.id))
            }
        }
        .padding(.vertical, 2)
        .listRowBackground(model.highlightedCheck == check ? Color.accentColor.opacity(0.12) : nil)
    }
}
