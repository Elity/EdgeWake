import AppKit
import EdgeWakeCore
import SwiftUI

/// How each check is described to the person, and where in System Settings it is fixed.
extension CheckID {
    var title: LocalizedStringResource {
        switch self {
        case .wifi: "Wi‑Fi is on"
        case .bluetooth: "Bluetooth is on"
        case .handoff: "Handoff is on"
        case .firewall: "Firewall lets EdgeWake connect"
        case .sameAppleID: "Signed in with the same Apple Account"
        case .universalControl: "Universal Control is allowed"
        case .systemSleep: "Mac stays awake"
        }
    }

    var detail: LocalizedStringResource {
        switch self {
        case .wifi: "Needed even when this Mac uses Ethernet."
        case .bluetooth: "Universal Control uses Bluetooth to find nearby Macs."
        case .handoff: "General › AirDrop & Handoff › Allow Handoff."
        case .firewall: "Network › Firewall › Options: allow incoming connections for EdgeWake."
        case .sameAppleID: "Both Macs must use the same Apple Account."
        case .universalControl: "Displays › Advanced: allow the pointer and keyboard to move between nearby Macs, push through the edge, and reconnect automatically."
        case .systemSleep: "A Mac that goes to sleep cannot be woken by EdgeWake. Turning off just the display is fine."
        }
    }

    /// Settings that EdgeWake cannot read and the person confirms instead.
    var needsConfirmation: Bool {
        self == .sameAppleID || self == .universalControl
    }

    var settingsURL: URL? {
        let pane = switch self {
        case .wifi: "com.apple.wifi-settings-extension"
        case .bluetooth: "com.apple.BluetoothSettings"
        case .handoff: "com.apple.AirDrop-Handoff-Settings.extension"
        case .firewall: "com.apple.Network-Settings.extension"
        case .sameAppleID: "com.apple.systempreferences.AppleIDSettings"
        case .universalControl: "com.apple.Displays-Settings.extension"
        case .systemSleep: "com.apple.Battery-Settings.extension"
        }
        return URL(string: "x-apple.systempreferences:\(pane)")
    }

    @MainActor
    func openSettings() {
        if let settingsURL {
            NSWorkspace.shared.open(settingsURL)
        }
    }
}

extension CheckState {
    var symbol: String {
        switch self {
        case .passed: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .unconfirmed: "questionmark.circle"
        case .unknown: "minus.circle"
        }
    }

    var tint: Color {
        switch self {
        case .passed: .green
        case .failed: .red
        case .warning: .orange
        case .unconfirmed, .unknown: .secondary
        }
    }

    var label: LocalizedStringResource {
        switch self {
        case .passed: "OK"
        case .failed: "Off"
        case .warning: "May sleep"
        case .unconfirmed: "Not confirmed"
        case .unknown: "Unknown"
        }
    }

    var needsAttention: Bool {
        self == .failed || self == .unconfirmed
    }
}
