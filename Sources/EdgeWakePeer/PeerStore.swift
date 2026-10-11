import EdgeWakeCore
import Foundation

public struct PairedPeer: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var key: Data
    /// Which side of this Mac the peer sits on in Universal Control. `nil` until set or learned;
    /// while unknown, both outer edges may wake it.
    public var side: Side?

    public init(id: UUID, name: String, key: Data, side: Side?) {
        self.id = id
        self.name = name
        self.key = key
        self.side = side
    }
}

/// Paired Macs and their long-term keys, in a 0600 JSON file under Application Support.
/// Not the Keychain: legacy Keychain items are bound to the code signature and would ask for the
/// login password after every rebuild, which defeats the "no password" goal. The key only lets a
/// Mac wake this display, so a user-readable file is an acceptable home for it.
public struct PeerStore {
    private let url: URL

    public init(directory: URL = URL.applicationSupportDirectory.appending(path: "EdgeWake", directoryHint: .isDirectory)) {
        url = directory.appending(path: "peers.json")
    }

    public func load() -> [PairedPeer] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([PairedPeer].self, from: data)) ?? []
    }

    public func save(_ peers: [PairedPeer]) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(peers).write(to: url, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            NSLog("EdgeWake: could not save paired Macs: \(error)")
        }
    }
}
