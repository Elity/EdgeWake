import SwiftUI

@main
struct EdgeWakeApp: App {
    @State private var model: AppModel
    @State private var setupWindow: SetupWindowController

    init() {
        let model = AppModel()
        let setupWindow = SetupWindowController()
        model.showSetup = { [weak model] in
            if let model { setupWindow.show(model: model) }
        }
        model.start()
        _setupWindow = State(initialValue: setupWindow)
        _model = State(initialValue: model)
        #if DEBUG
        Snapshots.runIfRequested(model: model)
        #endif
    }

    var body: some Scene {
        MenuBarExtra {
            MenuPanel(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(model: model)
        }
    }
}
