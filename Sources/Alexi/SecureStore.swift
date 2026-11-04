import CryptoKit
import Foundation
import Security

enum SecureStore {
    private static let service = "com.alexi.local"

    static func load<Value: Decodable>(_ type: Value.Type, from fileURL: URL, keyName: String) throws -> Value? {
        guard let encryptedData = try? Data(contentsOf: fileURL) else { return nil }
        let payload = try JSONDecoder().decode(EncryptedPayload.self, from: encryptedData)
        let sealedBox = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: payload.nonce), ciphertext: payload.ciphertext, tag: payload.tag)
        let decryptedData = try AES.GCM.open(sealedBox, using: try key(named: keyName))
        return try JSONDecoder().decode(Value.self, from: decryptedData)
    }

    static func save<Value: Encodable>(_ value: Value, to fileURL: URL, keyName: String) throws {
        let data = try JSONEncoder().encode(value)
        let sealedBox = try AES.GCM.seal(data, using: try key(named: keyName))
        let nonce = sealedBox.nonce.withUnsafeBytes { Data($0) }
        let payload = EncryptedPayload(nonce: nonce, ciphertext: sealedBox.ciphertext, tag: sealedBox.tag)
        let encryptedData = try JSONEncoder().encode(payload)
        try encryptedData.write(to: fileURL, options: [.atomic])
    }

    private static func key(named keyName: String) throws -> SymmetricKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: keyName,
            kSecReturnData as String: true
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let keyData = result as? Data {
            return SymmetricKey(data: keyData)
        }
        guard status == errSecItemNotFound else { throw SecureStoreError.keychain(status) }

        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: keyName,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw SecureStoreError.keychain(addStatus) }
        return newKey
    }
}

private struct EncryptedPayload: Codable {
    let nonce: Data
    let ciphertext: Data
    let tag: Data
}

enum SecureStoreError: LocalizedError {
    case keychain(OSStatus)

    var errorDescription: String? {
        "Alexi could not access its local encryption key."
    }
}
