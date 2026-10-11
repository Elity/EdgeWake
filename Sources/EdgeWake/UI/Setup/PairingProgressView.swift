import EdgeWakeCore
import SwiftUI

/// The current pairing exchange: the code to read out, the field to type it in, or the outcome.
struct PairingProgressView: View {
    let model: AppModel

    var body: some View {
        switch model.pairing {
        case .idle:
            EmptyView()

        case let .connecting(peerName):
            LabeledContent {
                Button("Cancel", action: model.cancelPairing)
            } label: {
                Label {
                    Text("Asking \(peerName) for a code…")
                } icon: {
                    ProgressView().controlSize(.small)
                }
            }

        case let .showingCode(code, peerName):
            VStack(spacing: 8) {
                Text("Enter this code on \(peerName)")
                    .foregroundStyle(.secondary)
                Text(code)
                    .font(.system(.largeTitle, design: .monospaced).bold())
                    .tracking(6)
                    .textSelection(.enabled)
                    .accessibilityLabel(code.map(String.init).joined(separator: " "))
                Button("Cancel", action: model.cancelPairing)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)

        case let .enteringCode(peerName, lastAttemptWrong):
            PairingCodeEntry(peerName: peerName, lastAttemptWrong: lastAttemptWrong,
                             submit: model.submitPairingCode, cancel: model.cancelPairing)

        case let .verifying(peerName):
            Label {
                Text("Pairing with \(peerName)…")
            } icon: {
                ProgressView().controlSize(.small)
            }

        case let .paired(peerName):
            LabeledContent {
                Button("OK", action: model.dismissPairingResult)
            } label: {
                Label("Paired with \(peerName)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }

        case let .failed(reason):
            LabeledContent {
                Button("OK", action: model.dismissPairingResult)
            } label: {
                Label(Self.message(for: reason), systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }
        }
    }

    private static func message(for reason: PairRejection) -> LocalizedStringResource {
        switch reason {
        case .wrongCode: "Pairing stopped after too many wrong codes."
        case .busy: "The other Mac is busy pairing. Try again in a moment."
        case .declined, .unknownDevice: "Pairing was cancelled."
        }
    }
}
