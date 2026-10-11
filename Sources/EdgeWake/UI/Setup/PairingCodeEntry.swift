import SwiftUI

/// Typing the code shown on the other Mac. Submits as soon as six digits are in.
struct PairingCodeEntry: View {
    let peerName: String
    let lastAttemptWrong: Bool
    let submit: (String) -> Void
    let cancel: () -> Void

    @State private var code = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Type the code shown on \(peerName)")
            HStack {
                TextField("6-digit code", text: $code, prompt: Text(verbatim: "000000"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.title2, design: .monospaced))
                    .frame(width: 140)
                    .focused($focused)
                    .onSubmit(submitIfComplete)
                    .onChange(of: code, digitsChanged)
                Button("Cancel", action: cancel)
            }
            if lastAttemptWrong {
                Label("That code didn't match. Check it and try again.", systemImage: "exclamationmark.circle")
                    .foregroundStyle(.red)
            }
        }
        .onAppear { focused = true }
    }

    private func digitsChanged() {
        let digits = String(code.filter(\.isNumber).prefix(6))
        if digits != code {
            code = digits
        }
        submitIfComplete()
    }

    private func submitIfComplete() {
        if code.count == 6 {
            submit(code)
        }
    }
}
