// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EdgeWake",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "3.1.0"),
    ],
    targets: [
        // Platform-free logic: gesture and side-learning state machines, pairing crypto,
        // the encrypted channel and the wire messages. Everything here is unit tested.
        .target(name: "EdgeWakeCore"),
        // Bonjour discovery, pairing and the encrypted link between Macs. Separate from the app so
        // the tests can exercise it end to end over real sockets.
        .target(name: "EdgeWakePeer", dependencies: ["EdgeWakeCore"]),
        .executableTarget(
            name: "EdgeWake",
            dependencies: ["EdgeWakeCore", "EdgeWakePeer", "KeyboardShortcuts"],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "EdgeWakeTests", dependencies: ["EdgeWakeCore", "EdgeWakePeer"]),
    ]
)
