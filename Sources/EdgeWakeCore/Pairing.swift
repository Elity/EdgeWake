import CryptoKit
import Foundation

/// Pairing turns a 6-digit code, shown on one Mac and typed on the other, into a long-term key.
///
/// Both sides exchange P-256 public keys, prove knowledge of the code with an HMAC over both keys
/// and both device IDs, and derive the long-term key from the ECDH secret, bound to the same IDs. The code never crosses the network.
/// Known limit: an attacker who actively intercepts the 2-minute pairing exchange can brute-force
/// the 6 digits offline from a proof. EdgeWake only ever carries "wake your display" and status,
/// so this is accepted; see docs/SPEC.md.
public enum Pairing {
    /// The Mac that shows the code is the responder; the Mac where it is typed is the initiator.
    public enum Role: String, Sendable {
        case initiator
        case responder
    }

    public static func newCode() -> String {
        String(format: "%06d", Int.random(in: 0..<1_000_000))
    }

    public static func proof(code: String, role: Role, initiatorID: UUID, responderID: UUID,
                             initiatorKey: Data, responderKey: Data) -> Data {
        let (key, message) = proofInputs(code: code, role: role, initiatorID: initiatorID, responderID: responderID,
                                         initiatorKey: initiatorKey, responderKey: responderKey)
        return Data(HMAC<SHA256>.authenticationCode(for: message, using: key))
    }

    public static func isValid(_ proof: Data, code: String, role: Role, initiatorID: UUID, responderID: UUID,
                               initiatorKey: Data, responderKey: Data) -> Bool {
        let (key, message) = proofInputs(code: code, role: role, initiatorID: initiatorID, responderID: responderID,
                                         initiatorKey: initiatorKey, responderKey: responderKey)
        return HMAC<SHA256>.isValidAuthenticationCode(proof, authenticating: message, using: key)
    }

    private static func proofInputs(code: String, role: Role, initiatorID: UUID, responderID: UUID,
                                    initiatorKey: Data, responderKey: Data) -> (SymmetricKey, Data) {
        let key = SymmetricKey(data: Data("edgewake pairing code \(code)".utf8))
        return (key, Data(role.rawValue.utf8) + bytes(initiatorID) + bytes(responderID) + initiatorKey + responderKey)
    }

    public static func longTermKey(
        privateKey: P256.KeyAgreement.PrivateKey,
        peerPublicKey: Data,
        initiatorID: UUID,
        responderID: UUID,
        initiatorKey: Data,
        responderKey: Data
    ) throws -> Data {
        let peer = try P256.KeyAgreement.PublicKey(rawRepresentation: peerPublicKey)
        let shared = try privateKey.sharedSecretFromKeyAgreement(with: peer)
        let key = shared.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: initiatorKey + responderKey,
            sharedInfo: Data("edgewake long-term key v1".utf8) + bytes(initiatorID) + bytes(responderID),
            outputByteCount: 32
        )
        return key.withUnsafeBytes { Data($0) }
    }

    /// The 16 raw bytes of a device ID.
    private static func bytes(_ id: UUID) -> Data {
        withUnsafeBytes(of: id.uuid) { Data($0) }
    }
}
