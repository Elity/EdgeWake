import EdgeWakeCore
import SwiftUI

/// A check's state on one Mac: a symbol plus a word, so it never relies on colour alone.
/// `nil` means the Mac has not reported yet (offline or still connecting).
struct CheckStateBadge: View {
    let state: CheckState?

    var body: some View {
        VStack(spacing: 2) {
            if let state {
                Image(systemName: state.symbol)
                    .foregroundStyle(state.tint)
                    .font(.title3)
                Text(state.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "ellipsis")
                    .foregroundStyle(.tertiary)
                    .font(.title3)
                Text("Waiting")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: ChecklistColumnHeader.width)
        .accessibilityElement(children: .combine)
    }
}
