import CryptoKit
import Foundation

/// AES-256-GCM in both directions over an ordered stream (TCP). Each connection mixes fresh
/// nonces from both Macs into the long-term key, so every session has its own keys. The GCM nonce
/// is an implicit per-direction counter: a replayed, reordered or dropped message fails to open.
public struct SecureChannel: Sendable {
    public enum Failure: Error, Equatable {
        case cannotOpen
    }

    private let sendKey: SymmetricKey
    private let receiveKey: SymmetricKey
    private var sendCounter: UInt64 = 0
    private var receiveCounter: UInt64 = 0

    public init(longTermKey: Data, localID: UUID, localNonce: Data, peerID: UUID, peerNonce: Data) {
        let localFirst = localID.uuidString < peerID.uuidString
        let salt = localFirst ? localNonce + peerNonce : peerNonce + localNonce
        let master = SymmetricKey(data: longTermKey)
        func key(sentBy id: UUID) -> SymmetricKey {
            HKDF<SHA256>.deriveKey(
                inputKeyMaterial: master,
                salt: salt,
                info: Data("edgewake session v1 \(id.uuidString)".utf8),
                outputByteCount: 32
            )
        }
        sendKey = key(sentBy: localID)
        receiveKey = key(sentBy: peerID)
    }

    public static func newNonce() -> Data {
        Data((0..<16).map { _ in UInt8.random(in: .min ... .max) })
    }

    public mutating func seal(_ plaintext: Data) throws -> Data {
        let box = try AES.GCM.seal(plaintext, using: sendKey, nonce: Self.nonce(sendCounter))
        sendCounter += 1
        return Data(box.ciphertext) + box.tag // Data(...) re-bases a slice to index 0
    }

    public mutating func open(_ sealed: Data) throws -> Data {
        guard sealed.count >= 16 else { throw Failure.cannotOpen }
        do {
            let box = try AES.GCM.SealedBox(
                nonce: Self.nonce(receiveCounter),
                ciphertext: sealed.dropLast(16),
                tag: sealed.suffix(16)
            )
            let plaintext = try AES.GCM.open(box, using: receiveKey)
            receiveCounter += 1
            return plaintext
        } catch {
            throw Failure.cannotOpen
        }
    }

    private static func nonce(_ counter: UInt64) -> AES.GCM.Nonce {
        var bytes = Data(count: 4)
        withUnsafeBytes(of: counter.bigEndian) { bytes.append(contentsOf: $0) }
        // 12 bytes is always a valid GCM nonce length.
        return try! AES.GCM.Nonce(data: bytes)
    }
}
