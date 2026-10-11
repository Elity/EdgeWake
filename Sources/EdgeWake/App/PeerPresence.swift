import SwiftUI

/// What the menu shows for one paired Mac.
enum PeerPresence {
    case offline
    case screenOn
    case screenOff

    var label: LocalizedStringResource {
        switch self {
        case .offline: "Offline"
        case .screenOn: "Display on"
        case .screenOff: "Display off"
        }
    }

    var tint: Color {
        switch self {
        case .offline: .secondary
        case .screenOn: .green
        case .screenOff: .orange
        }
    }
}
