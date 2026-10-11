import CoreWLAN
import EdgeWakeCore
import Foundation

/// Reads the settings Universal Control depends on, without asking for any permission.
/// Settings that cannot be detected are reported as confirmed or unconfirmed by the person.
enum SystemChecks {
    struct Confirmations {
        var sameAppleID: Bool
        var universalControl: Bool
    }

    static func run(confirmations: Confirmations) async -> [CheckResult] {
        async let bluetooth = bluetoothState()
        async let sleep = systemSleepState()
        async let firewall = firewallState()
        return [
            CheckResult(id: .wifi, state: wifiState()),
            CheckResult(id: .bluetooth, state: await bluetooth),
            CheckResult(id: .handoff, state: handoffState()),
            CheckResult(id: .firewall, state: await firewall),
            CheckResult(id: .sameAppleID, state: confirmations.sameAppleID ? .passed : .unconfirmed),
            CheckResult(id: .universalControl, state: confirmations.universalControl ? .passed : .unconfirmed),
            CheckResult(id: .systemSleep, state: await sleep),
        ]
    }

    /// Wi-Fi must be on for Universal Control even when the Mac reaches the network over Ethernet.
    private static func wifiState() -> CheckState {
        guard let interface = CWWiFiClient.shared().interface() else { return .unknown }
        return interface.powerOn() ? .passed : .failed
    }

    /// Absent keys mean the defaults, which allow Handoff.
    private static func handoffState() -> CheckState {
        func allowed(_ key: String) -> Bool {
            CFPreferencesCopyValue(key as CFString, "com.apple.coreservices.useractivityd" as CFString,
                                   kCFPreferencesCurrentUser, kCFPreferencesCurrentHost) as? Bool ?? true
        }
        return allowed("ActivityAdvertisingAllowed") && allowed("ActivityReceivingAllowed") ? .passed : .failed
    }

    /// `system_profiler` reads the controller state without the Bluetooth permission prompt that
    /// IOBluetooth and Core Bluetooth would trigger.
    private static func bluetoothState() async -> CheckState {
        guard let output = await run("/usr/sbin/system_profiler", ["SPBluetoothDataType", "-json"]) else { return .unknown }
        if output.contains("\"controller_state\" : \"attrib_on\"") { return .passed }
        if output.contains("\"controller_state\" : \"attrib_off\"") { return .failed }
        return .unknown
    }

    /// The Application Firewall silently drops connections from the other Mac to an app it has
    /// not allowed. EdgeWake copes with one blocked side, but not both.
    private static func firewallState() async -> CheckState {
        guard let output = await run("/usr/libexec/ApplicationFirewall/socketfilterfw",
                                     ["--getappblocked", Bundle.main.bundlePath]) else { return .unknown }
        if output.contains("is permitted") { return .passed }
        if output.contains("is blocked") { return .failed }
        return .unknown
    }

    /// A Mac that goes to sleep cannot be woken over the network by EdgeWake. On a laptop that is
    /// expected, so it is a warning rather than a failure.
    private static func systemSleepState() async -> CheckState {
        guard let output = await run("/usr/bin/pmset", ["-g"]),
              let line = output.split(separator: "\n").first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("sleep ") })
        else { return .unknown }
        let fields = line.split(separator: " ")
        guard fields.count >= 2, let minutes = Int(fields[1]) else { return .unknown }
        // A temporary assertion ("sleep prevented by …") does not make the setting itself safe.
        return minutes == 0 ? .passed : .warning
    }

    private static func run(_ path: String, _ arguments: [String]) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                let pipe = Pipe()
                process.executableURL = URL(filePath: path)
                process.arguments = arguments
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: nil)
                    return
                }
                // A stuck tool must not stall the checks forever; terminating it ends the read below.
                let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + 10, execute: watchdog)
                defer { watchdog.cancel() }
                // Read before waiting, or a large output fills the pipe and the process never exits.
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                continuation.resume(returning: String(data: data, encoding: .utf8))
            }
        }
    }
}
