import CryptoKit
import Foundation

enum CryptoService {
    enum CryptoError: Error {
        case invalidKey
        case invalidPayload
        case invalidURL
    }

    static func subscriptionURL() throws -> URL {
        var bytes = [CChar](repeating: 0, count: 512)
        let length = bytes.withUnsafeMutableBufferPointer { buffer in
            NicecatCopySubscriptionURL(buffer.baseAddress, buffer.count)
        }
        let text = bytes.withUnsafeBufferPointer { buffer in
            buffer.baseAddress.flatMap { String(validatingUTF8: $0) }
        }
        guard length > 0, let text, let url = URL(string: text) else {
            throw CryptoError.invalidURL
        }
        return url
    }

    static func decryptBase64Payload(_ text: String) throws -> Data {
        guard let combined = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              combined.count > 28 else {
            throw CryptoError.invalidPayload
        }
        let nonceData = combined.prefix(12)
        let cipherAndTag = combined.dropFirst(12)
        let ciphertext = cipherAndTag.dropLast(16)
        let tag = cipherAndTag.suffix(16)
        let sealedBox = try AES.GCM.SealedBox(
            nonce: AES.GCM.Nonce(data: Data(nonceData)),
            ciphertext: Data(ciphertext),
            tag: Data(tag)
        )
        return try AES.GCM.open(sealedBox, using: SymmetricKey(data: secretKey()))
    }

    static func encryptToBase64Payload(_ plain: Data) throws -> String {
        let nonce = AES.GCM.Nonce()
        let sealedBox = try AES.GCM.seal(plain, using: SymmetricKey(data: secretKey()), nonce: nonce)
        var combined = Data()
        nonce.withUnsafeBytes { rawBuffer in
            combined.append(contentsOf: rawBuffer)
        }
        combined.append(sealedBox.ciphertext)
        combined.append(sealedBox.tag)
        return combined.base64EncodedString()
    }

    private static func secretKey() throws -> Data {
        var key = [UInt8](repeating: 0, count: 16)
        let length = key.withUnsafeMutableBufferPointer { buffer in
            NicecatCopySecretKey(buffer.baseAddress, buffer.count)
        }
        guard length == 16 else {
            throw CryptoError.invalidKey
        }
        return Data(key)
    }
}
