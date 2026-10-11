import SwiftUI

/// Step 1: find the other Mac on the network and pair with a 6-digit code.
struct PairingSection: View {
    let model: AppModel

    var body: some View {
        Section {
            if model.pairing != .idle {
                PairingProgressView(model: model)
            }

            ForEach(model.pairedPeers) { peer in
                LabeledContent {
                    Label("Paired", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } label: {
                    Label(peer.name, systemImage: "display")
                }
            }

            ForEach(model.unpairedDiscovered) { mac in
                LabeledContent {
                    Button("Pair…") { model.startPairing(with: mac) }
                        .disabled(model.pairing.isInProgress)
                } label: {
                    Label(mac.name, systemImage: "display")
                }
            }

            if model.unpairedDiscovered.isEmpty && model.pairedPeers.isEmpty {
                LabeledContent {
                    ProgressView()
                        .controlSize(.small)
                } label: {
                    Text("Looking for other Macs running EdgeWake…")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Pair Your Macs")
        } footer: {
            Text("Install and open EdgeWake on both Macs. They find each other on the local network; pairing once is enough. No password or special permission is needed.")
                .foregroundStyle(.secondary)
        }
    }
}
