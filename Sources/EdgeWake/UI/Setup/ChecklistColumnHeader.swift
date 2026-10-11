import SwiftUI

/// The name above a column of check states. Shares its width with `CheckStateBadge`.
struct ChecklistColumnHeader: View {
    static let width: CGFloat = 84

    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(width: Self.width)
    }
}
