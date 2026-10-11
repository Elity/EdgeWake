import CryptoKit
import Foundation
import Testing
@testable import EdgeWakeCore

@Suite struct PairingTests {
    private let initiator = P256.KeyAgreement.PrivateKey()
    private let responder = P256.KeyAgreement.PrivateKey()
    private let initiatorID = UUID()
    private let responderID = UUID()

    @Test func proofWithTheRightCodeIsValid() {
        let proof = Pairing.proof(code: "123456", role: .initiator, initiatorID: initiatorID, responderID: responderID,
                                  initiatorKey: initiator.publicKey.rawRepresentation,
                                  responderKey: responder.publicKey.rawRepresentation)
        #expect(Pairing.isValid(proof, code: "123456", role: .initiator, initiatorID: initiatorID, responderID: responderID,
                                initiatorKey: initiator.publicKey.rawRepresentation,
                                responderKey: responder.publicKey.rawRepresentation))
    }

    @Test func proofWithTheWrongCodeOrRoleIsRejected() {
        let i = initiator.publicKey.rawRepresentation
        let r = responder.publicKey.rawRepresentation
        let (a, b) = (initiatorID, responderID)
        let proof = Pairing.proof(code: "123456", role: .initiator, initiatorID: a, responderID: b, initiatorKey: i, responderKey: r)
        #expect(!Pairing.isValid(proof, code: "654321", role: .initiator, initiatorID: a, responderID: b, initiatorKey: i, responderKey: r))
        #expect(!Pairing.isValid(proof, code: "123456", role: .responder, initiatorID: a, responderID: b, initiatorKey: i, responderKey: r))
        #expect(!Pairing.isValid(proof, code: "123456", role: .initiator, initiatorID: a, responderID: b, initiatorKey: r, responderKey: i))
    }

    /// A proof made for one pair of Macs does not vouch for another, even with the same keys.
    @Test func proofForOtherDeviceIDsIsRejected() {
        let i = initiator.publicKey.rawRepresentation
        let r = responder.publicKey.rawRepresentation
        let proof = Pairing.proof(code: "123456", role: .initiator, initiatorID: initiatorID, responderID: responderID,
                                  initiatorKey: i, responderKey: r)
        #expect(!Pairing.isValid(proof, code: "123456", role: .initiator, initiatorID: UUID(), responderID: responderID,
                                 initiatorKey: i, responderKey: r))
        #expect(!Pairing.isValid(proof, code: "123456", role: .initiator, initiatorID: responderID, responderID: initiatorID,
                                 initiatorKey: i, responderKey: r))
    }

    @Test func bothSidesDeriveTheSameLongTermKey() throws {
        let i = initiator.publicKey.rawRepresentation
        let r = responder.publicKey.rawRepresentation
        let a = try Pairing.longTermKey(privateKey: initiator, peerPublicKey: r, initiatorID: initiatorID, responderID: responderID,
                                        initiatorKey: i, responderKey: r)
        let b = try Pairing.longTermKey(privateKey: responder, peerPublicKey: i, initiatorID: initiatorID, responderID: responderID,
                                        initiatorKey: i, responderKey: r)
        #expect(a == b)
        #expect(a.count == 32)
    }

    @Test func longTermKeyDependsOnTheDeviceIDs() throws {
        let i = initiator.publicKey.rawRepresentation
        let r = responder.publicKey.rawRepresentation
        let a = try Pairing.longTermKey(privateKey: initiator, peerPublicKey: r, initiatorID: initiatorID, responderID: responderID,
                                        initiatorKey: i, responderKey: r)
        let b = try Pairing.longTermKey(privateKey: initiator, peerPublicKey: r, initiatorID: initiatorID, responderID: UUID(),
                                        initiatorKey: i, responderKey: r)
        #expect(a != b)
    }

    @Test func codesAreSixDigits() {
        for _ in 0..<100 {
            let code = Pairing.newCode()
            #expect(code.count == 6)
            #expect(code.allSatisfy { $0.isNumber })
        }
    }
}

@Suite struct SecureChannelTests {
    private let key = Data((0..<32).map { UInt8($0) })
    private let idA = UUID()
    private let idB = UUID()
    private let nonceA = SecureChannel.newNonce()
    private let nonceB = SecureChannel.newNonce()

    private func pair() -> (SecureChannel, SecureChannel) {
        (SecureChannel(longTermKey: key, localID: idA, localNonce: nonceA, peerID: idB, peerNonce: nonceB),
         SecureChannel(longTermKey: key, localID: idB, localNonce: nonceB, peerID: idA, peerNonce: nonceA))
    }

    @Test func messagesRoundTripInBothDirections() throws {
        var (a, b) = pair()
        for text in ["one", "two", "three"] {
            #expect(try b.open(a.seal(Data(text.utf8))) == Data(text.utf8))
            #expect(try a.open(b.seal(Data(text.utf8))) == Data(text.utf8))
        }
    }

    @Test func tamperedMessageIsRejected() throws {
        var (a, b) = pair()
        var sealed = try a.seal(Data("wake".utf8))
        sealed[0] ^= 0xFF
        #expect(throws: SecureChannel.Failure.cannotOpen) { try b.open(sealed) }
    }

    @Test func replayedMessageIsRejected() throws {
        var (a, b) = pair()
        let sealed = try a.seal(Data("wake".utf8))
        _ = try b.open(sealed)
        #expect(throws: SecureChannel.Failure.cannotOpen) { try b.open(sealed) }
    }

    @Test func reorderedMessagesAreRejected() throws {
        var (a, b) = pair()
        _ = try a.seal(Data("first".utf8))
        let second = try a.seal(Data("second".utf8))
        #expect(throws: SecureChannel.Failure.cannotOpen) { try b.open(second) }
    }

    @Test func aDifferentLongTermKeyCannotOpen() throws {
        var (a, _) = pair()
        var stranger = SecureChannel(longTermKey: Data(repeating: 9, count: 32), localID: idB,
                                     localNonce: nonceB, peerID: idA, peerNonce: nonceA)
        #expect(throws: SecureChannel.Failure.cannotOpen) { try stranger.open(a.seal(Data("wake".utf8))) }
    }
}

@Suite struct WireTests {
    @Test func framesSurviveArbitrarySplits() throws {
        let payloads = [Data("a".utf8), Data(repeating: 7, count: 300), Data()]
        let stream = payloads.map(FrameBuffer.frame).reduce(Data(), +)
        var buffer = FrameBuffer()
        var received: [Data] = []
        for byte in stream {
            received += try buffer.append(Data([byte]))
        }
        #expect(received == payloads)
    }

    @Test func manyFramesInOneReadArriveInOrder() throws {
        let payloads = (0..<1_000).map { Data("frame \($0)".utf8) }
        var buffer = FrameBuffer()
        let stream = payloads.map(FrameBuffer.frame).reduce(Data(), +)
        let received = try buffer.append(stream + FrameBuffer.frame(Data("tail".utf8)).prefix(5))
        #expect(received == payloads)
        #expect(try buffer.append(Data("ail".utf8)) == [Data("tail".utf8)])
    }

    @Test func oversizedFrameIsRefused() {
        var buffer = FrameBuffer()
        let header = Data([0x7F, 0xFF, 0xFF, 0xFF])
        #expect(throws: FrameBuffer.Failure.self) { try buffer.append(header) }
    }

    @Test func messagesRoundTrip() throws {
        let messages: [PeerMessage] = [
            .status(PeerStatus(name: "Mac mini", displayAsleep: true,
                               checks: [CheckResult(id: .bluetooth, state: .failed)], version: "0.1.0")),
            .wake(id: UUID()),
            .wakeAck(id: UUID()),
            .pointerEntered(edge: .right),
            .showCheck(.handoff),
        ]
        for message in messages {
            #expect(try Wire.decode(PeerMessage.self, from: Wire.encode(message)) == message)
        }
        let hello = HandshakeMessage.hello(deviceID: UUID(), name: "MacBook", nonce: SecureChannel.newNonce())
        #expect(try Wire.decode(HandshakeMessage.self, from: Wire.encode(hello)) == hello)
    }
}
