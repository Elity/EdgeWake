import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("General") {
                Toggle("Open at login", isOn: $model.launchAtLogin)
                    .disabled(!model.isBundled)
                KeyboardShortcuts.Recorder("Wake all Macs:", name: .wakePeers)
            }

            Section {
                Picker("Bumps needed", selection: $model.bumpsRequired) {
                    ForEach(2...4, id: \.self) { count in
                        Text(count.formatted()).tag(count)
                    }
                }
                LabeledContent("Within") {
                    HStack {
                        Slider(value: $model.bumpWindow, in: 0.3...1.2, step: 0.1)
                        Text(Duration.milliseconds(Int(model.bumpWindow * 1000)), format: .units(allowed: [.seconds, .milliseconds], width: .abbreviated))
                            .monospacedDigit()
                            .frame(width: 60, alignment: .trailing)
                    }
                }
            } header: {
                Text("Edge Gesture")
            } footer: {
                Text("EdgeWake only reacts when the Mac on that side has its display off, no mouse button is held, and no app is full screen.")
                    .foregroundStyle(.secondary)
            }

            Section("Paired Macs") {
                if model.pairedPeers.isEmpty {
                    Text("None yet")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.pairedPeers) { peer in
                    LabeledContent(peer.name) {
                        Button("Unpair", role: .destructive) { model.unpair(peer.id) }
                    }
                }
                Button("Set Up EdgeWake…", action: model.requestSetupWindow)
            }

            Section {
                LabeledContent("This Mac", value: model.identity.name)
                LabeledContent("Version", value: model.version)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
