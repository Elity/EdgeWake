import SwiftUI

/// Setup, shown on first launch and from the menu: pair, place, and check both Macs.
struct SetupView: View {
    let model: AppModel
    let close: () -> Void

    var body: some View {
        Form {
            PairingSection(model: model)
            if !model.pairedPeers.isEmpty {
                PositionSection(model: model)
            }
            ChecklistSection(model: model)
            Section {
                HStack {
                    Spacer()
                    Button("Done", action: close)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: model.refreshChecks)
        .onDisappear(perform: finish)
    }

    /// Closing the window by any means counts as finishing setup; it stays one click away in the menu.
    private func finish() {
        model.setupCompleted = true
        model.clearHighlight()
    }
}
