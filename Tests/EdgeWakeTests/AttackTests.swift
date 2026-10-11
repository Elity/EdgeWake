import CryptoKit
import EdgeWakeCore
import Foundation
import Testing
@testable import EdgeWakePeer

/// What a hostile device on the same network can and cannot do.
@MainActor
@Suite(.serialized)
struct AttackTests {
    /// Guessing the code is limited to three tries per pairing, even when every guess arrives in
    /// one TCP write and the last one happens to be right.
    @Test func batchedGuessesCannotExceedTheWrongCodeLimit() async throws {
        let mini = TestPeer(name: "Mini")
        let observer = TestPeer(name: "Observer")
        mini.service.start()
        observer.service.start()
        try await waitUntil("discovery") { observer.service.discovered[mini.identity.id] != nil }

        let attacker = RawClient(to: try #require(observer.service.discovered[mini.identity.id]).endpoint)
        let attackerKey = P256.KeyAgreement.PrivateKey()
        let attackerID = UUID()
        attacker.send([.pairRequest(deviceID: attackerID, name: "Attacker", publicKey: attackerKey.publicKey.rawRepresentation)])
        try await waitUntil("code shown") { mini.shownCode != nil && !attacker.received.isEmpty }
        guard case let .pairReady(responderID, _, responderKey) = attacker.received.first else {
            Issue.record("Expected pairReady, got \(attacker.received)")
            return
        }

        let code = try #require(mini.shownCode)
        let wrong = code == "000000" ? "111111" : "000000"
        let proof = { (guess: String) in
            HandshakeMessage.pairProof(Pairing.proof(code: guess, role: .initiator,
                                                     initiatorID: attackerID, responderID: responderID,
                                                     initiatorKey: attackerKey.publicKey.rawRepresentation,
                                                     responderKey: responderKey))
        }
        attacker.send([proof(wrong), proof(wrong), proof(wrong), proof(code)])

        try await Task.sleep(for: .seconds(1))
        let accepted = attacker.received.contains { if case .pairProof = $0 { true } else { false } }
        #expect(!accepted, "Mini must not answer a guess made after the third wrong one")
        #expect(mini.keys.isEmpty)
    }

    /// A stranger that claims a paired Mac's device ID must not displace the real link or rename
    /// the paired Mac: without the long-term key it never gets past the handshake.
    @Test func impostorHelloDoesNotDisplaceTheRealLink() async throws {
        // Fixed IDs make Mini the larger one: its real link is the one Book dialled, which is
        // incoming on Mini, exactly like the impostor's.
        let mini = TestPeer(name: "Mini", id: UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000000")!)
        let book = TestPeer(name: "Book", id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        try await pairAndConnect(mini, book)
        let namesBefore = mini.readyNames

        let impostor = RawClient(to: try #require(book.service.discovered[mini.identity.id]).endpoint)
        impostor.send([.hello(deviceID: book.identity.id, name: "Impostor", nonce: SecureChannel.newNonce())])
        try await Task.sleep(for: .seconds(1))

        #expect(mini.readyNames == namesBefore, "The impostor must not be reported as ready")
        let wakeID = UUID()
        book.service.send(.wake(id: wakeID), to: mini.identity.id)
        try await waitUntil("wake over the real link", timeout: 5) { book.messages.contains(.wakeAck(id: wakeID)) }
        impostor.cancel()
    }

    /// Once someone has used up the wrong-code limit, this Mac turns away new pairing requests for
    /// a while instead of showing a fresh code to guess.
    @Test func pairingIsRefusedForAWhileAfterTooManyWrongCodes() async throws {
        let mini = TestPeer(name: "Mini")
        let observer = TestPeer(name: "Observer")
        mini.service.start()
        observer.service.start()
        try await waitUntil("discovery") { observer.service.discovered[mini.identity.id] != nil }
        let endpoint = try #require(observer.service.discovered[mini.identity.id]).endpoint

        let attacker = RawClient(to: endpoint)
        let attackerKey = P256.KeyAgreement.PrivateKey()
        let attackerID = UUID()
        attacker.send([.pairRequest(deviceID: attackerID, name: "Attacker", publicKey: attackerKey.publicKey.rawRepresentation)])
        try await waitUntil("code shown") { mini.shownCode != nil && !attacker.received.isEmpty }
        guard case let .pairReady(responderID, _, responderKey) = attacker.received.first else {
            Issue.record("Expected pairReady, got \(attacker.received)")
            return
        }
        let wrong = mini.shownCode == "000000" ? "111111" : "000000"
        let proof = HandshakeMessage.pairProof(Pairing.proof(code: wrong, role: .initiator,
                                                             initiatorID: attackerID, responderID: responderID,
                                                             initiatorKey: attackerKey.publicKey.rawRepresentation,
                                                             responderKey: responderKey))
        for _ in 0..<PeerLink.maximumWrongCodes {
            attacker.send([proof])
        }
        try await waitUntil("hang-up") { attacker.isClosed }

        mini.shownCode = nil
        let second = RawClient(to: endpoint)
        second.send([.pairRequest(deviceID: UUID(), name: "Second", publicKey: P256.KeyAgreement.PrivateKey().publicKey.rawRepresentation)])
        try await waitUntil("refusal") { second.received.contains(.pairRejected(.busy)) }
        #expect(!second.received.contains { if case .pairReady = $0 { true } else { false } })
        #expect(mini.shownCode == nil)
    }

    /// A connection that never completes a handshake is dropped, and only a few may wait at once.
    @Test func idleStrangersAreDisconnectedAndCapped() async throws {
        let mini = TestPeer(name: "Mini")
        let observer = TestPeer(name: "Observer")
        mini.service.handshakeTimeout = 2
        mini.service.start()
        observer.service.start()
        try await waitUntil("discovery") { observer.service.discovered[mini.identity.id] != nil }
        let endpoint = try #require(observer.service.discovered[mini.identity.id]).endpoint

        let strangers = (0...PeerService.maximumUnreadyIncomingLinks).map { _ in RawClient(to: endpoint) }
        try await Task.sleep(for: .seconds(1))
        #expect(strangers.count { $0.isClosed } == 1, "Only the connection over the cap is refused")
        try await waitUntil("timeout", timeout: 5) { strangers.allSatisfy(\.isClosed) }
    }
}
