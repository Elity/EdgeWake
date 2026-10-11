#if DEBUG
import AppKit
import SwiftUI

/// `EDGEWAKE_SNAPSHOTS=<dir> swift run EdgeWake` renders the main views into PNGs and quits, so the
/// UI can be reviewed without clicking through it. Debug builds only.
@MainActor
enum Snapshots {
    static func runIfRequested(model: AppModel) {
        guard let directory = ProcessInfo.processInfo.environment["EDGEWAKE_SNAPSHOTS"] else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            let url = URL(filePath: directory)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            save(SetupView(model: model, close: {}).frame(width: 620), "setup-empty", in: url)
            model.loadSnapshotState(pairing: .showingCode(code: "482913", peerName: "MacBook Pro"))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                save(SetupView(model: model, close: {}).frame(width: 620), "setup-paired", in: url)
                save(SettingsView(model: model), "settings", in: url)
                model.loadSnapshotState(pairing: .enteringCode(peerName: "Fighting的Mac mini", lastAttemptWrong: true))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    save(SetupView(model: model, close: {}).frame(width: 620), "setup-entering", in: url)
                    NSApp.terminate(nil)
                }
            }
        }
    }

    private static func save(_ view: some View, _ name: String, in directory: URL) {
        for scheme in [ColorScheme.light, .dark] {
            let host = NSHostingView(rootView: view.environment(\.colorScheme, scheme).background(.windowBackground))
            host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            let size = host.fittingSize
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            host.frame = NSRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let file = directory.appending(path: "\(name)-\(scheme == .dark ? "dark" : "light").png")
            try? bitmap.representation(using: .png, properties: [:])?.write(to: file)
        }
    }
}
#endif
