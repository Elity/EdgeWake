import EdgeWakeCore
import Foundation
import Testing
@testable import EdgeWakePeer

/// Two `PeerService`s in one process, talking over real Bonjour and TCP on loopback.
@MainActor
@Suite(.serialized)
struct PeerIntegrationTests {
    @Test func pairThenWakeOverRealSockets() async throws {
        let mini = TestPeer(name: "Mini")
        let book = TestPeer(name: "Book")
        try await pairAndConnect(mini, book)
        #expect(mini.keys[book.identity.id] == book.keys[mini.identity.id])

        let wakeID = UUID()
        book.service.send(.wake(id: wakeID), to: mini.identity.id)
        try await waitUntil("wake acknowledgement") { book.messages.contains(.wakeAck(id: wakeID)) }
        #expect(mini.messages.contains(.wake(id: wakeID)))

        let status = PeerStatus(name: "Mini", displayAsleep: true, checks: [CheckResult(id: .wifi, state: .passed)], version: "test")
        mini.service.broadcast(.status(status))
        try await waitUntil("status") { book.messages.contains(.status(status)) }
    }

    @Test func wrongCodesAreRefusedAndPairingStops() async throws {
        let mini = TestPeer(name: "Mini")
        let book = TestPeer(name: "Book")
        book.codeToType = { mini.shownCode == "000000" ? "111111" : "000000" }
        mini.service.start()
        book.service.start()

        try await waitUntil("discovery") { book.service.discovered[mini.identity.id] != nil }
        book.service.requestPairing(with: mini.identity.id)
        try await waitUntil("first rejection") { book.failures.contains(.wrongCode) }
        #expect(book.keys.isEmpty && mini.keys.isEmpty)
    }

    @Test func strangerCannotOpenAnEncryptedLink() async throws {
        let mini = TestPeer(name: "Mini")
        let stranger = TestPeer(name: "Stranger")
        // The stranger believes it is paired with mini; mini has never heard of it.
        stranger.keys[mini.identity.id] = Data(repeating: 1, count: 32)
        mini.service.start()
        stranger.service.start()

        try await waitUntil("discovery") { stranger.service.discovered[mini.identity.id] != nil }
        stranger.service.connect(to: mini.identity.id)
        try await waitUntil("rejection") { stranger.failures.contains(.unknownDevice) }
        #expect(mini.ready.isEmpty && stranger.ready.isEmpty)
    }
}
