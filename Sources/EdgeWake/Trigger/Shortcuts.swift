import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Wakes every paired Mac. Registered through Carbon hot keys, so it needs no permission.
    static let wakePeers = Self("wakePeers", initial: .init(.w, modifiers: [.control, .option, .command]))
}
