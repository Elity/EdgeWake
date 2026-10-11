import SwiftUI

/// The menu bar icon. Menu bar extras are template images, so state is shown through the symbol's
/// shape rather than colour.
struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        Image(systemName: model.needsAttention ? "display.trianglebadge.exclamationmark" : "display.2")
            .accessibilityLabel(model.needsAttention ? "EdgeWake – settings need attention" : "EdgeWake")
    }
}
