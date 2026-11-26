import CommonCrypto
import CryptoKit
import Foundation

public enum CryptoUtils {
    private static let jioSaavnDesKey = "38346591"

    /// Computes YouTube's `SAPISIDHASH {epochSec}_{sha1}` authorization header value.
    public static func sapisidHash(
        sapisid: String,
        origin: String,
        timestamp: Int = Int(Date().timeIntervalSince1970)
    ) -> String {
        let payload = "\(timestamp) \(sapisid) \(origin)"
        let digest = Insecure.SHA1.hash(data: Data(payload.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "SAPISIDHASH \(timestamp)_\(hex)"
    }

    /// Parses an HTTP `Cookie` header string into key/value pairs.
    public static func parseCookieHeader(_ cookie: String) -> [String: String] {
        var result: [String: String] = [:]
        for part in cookie.split(separator: ";") {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let eqIdx = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[..<eqIdx]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: eqIdx)...]).trimmingCharacters(in: .whitespaces)
            if !key.isEmpty {
                result[key] = value
            }
        }
        return result
    }

    /// Extracts `SAPISID` (or fallback `__Secure-3PAPISID`) from a cookie string.
    public static func extractSAPISID(from cookie: String) -> String? {
        let map = parseCookieHeader(cookie)
        return map["SAPISID"] ?? map["__Secure-3PAPISID"]
    }

    /// Decrypts JioSaavn Base64 DES/ECB/PKCS7 encrypted `encrypted_media_url` strings.
    public static func decryptJioSaavnMediaURL(_ encryptedBase64: String) -> String? {
        guard let inputData = Data(base64Encoded: encryptedBase64),
              !inputData.isEmpty else {
            return nil
        }
        let keyData = Data(jioSaavnDesKey.utf8)
        guard keyData.count == kCCKeySizeDES else { return nil }

        let bufferSize = inputData.count + kCCBlockSizeDES
        var outBuffer = [UInt8](repeating: 0, count: bufferSize)
        var outLength = 0

        let status = inputData.withUnsafeBytes { inputPtr in
            keyData.withUnsafeBytes { keyPtr in
                CCCrypt(
                    CCOperation(kCCDecrypt),
                    CCAlgorithm(kCCAlgorithmDES),
                    CCOptions(kCCOptionECBMode | kCCOptionPKCS7Padding),
                    keyPtr.baseAddress,
                    kCCKeySizeDES,
                    nil,
                    inputPtr.baseAddress,
                    inputData.count,
                    &outBuffer,
                    bufferSize,
                    &outLength
                )
            }
        }

        guard status == kCCSuccess else { return nil }
        return String(bytes: outBuffer.prefix(outLength), encoding: .utf8)
    }

    /// Encrypts a JioSaavn media URL with DES/ECB/PKCS7 (useful for unit tests & verification).
    public static func encryptJioSaavnMediaURL(_ plainURL: String) -> String? {
        let inputData = Data(plainURL.utf8)
        let keyData = Data(jioSaavnDesKey.utf8)
        guard keyData.count == kCCKeySizeDES else { return nil }

        let bufferSize = inputData.count + kCCBlockSizeDES
        var outBuffer = [UInt8](repeating: 0, count: bufferSize)
        var outLength = 0

        let status = inputData.withUnsafeBytes { inputPtr in
            keyData.withUnsafeBytes { keyPtr in
                CCCrypt(
                    CCOperation(kCCEncrypt),
                    CCAlgorithm(kCCAlgorithmDES),
                    CCOptions(kCCOptionECBMode | kCCOptionPKCS7Padding),
                    keyPtr.baseAddress,
                    kCCKeySizeDES,
                    nil,
                    inputPtr.baseAddress,
                    inputData.count,
                    &outBuffer,
                    bufferSize,
                    &outLength
                )
            }
        }

        guard status == kCCSuccess else { return nil }
        return Data(outBuffer.prefix(outLength)).base64EncodedString()
    }
}
