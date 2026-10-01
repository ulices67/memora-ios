import CommonCrypto
import CryptoKit
import Foundation
import LocalAuthentication
import Security

enum MemoraCrypto {
    static func randomKey() -> SymmetricKey { SymmetricKey(size: .bits256) }

    static func randomData(_ count: Int) throws -> Data {
        var bytes = Data(count: count)
        let status = bytes.withUnsafeMutableBytes { pointer in
            SecRandomCopyBytes(kSecRandomDefault, count, pointer.baseAddress!)
        }
        guard status == errSecSuccess else { throw MemoraError.corruptData }
        return bytes
    }

    static func passwordKey(_ password: String, salt: Data) throws -> SymmetricKey {
        var result = Data(count: 32)
        let status = password.withCString { characters in
            salt.withUnsafeBytes { saltBytes in
                result.withUnsafeMutableBytes { output in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2), characters, password.utf8.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), 310_000,
                        output.bindMemory(to: UInt8.self).baseAddress, 32
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw MemoraError.corruptData }
        return SymmetricKey(data: result)
    }

    static func subkey(_ root: SymmetricKey, account: UUID, purpose: String) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: root,
            salt: Data("memora:\(account.uuidString):v1".utf8),
            info: Data(purpose.utf8), outputByteCount: 32
        )
    }

    static func seal(_ plain: Data, key: SymmetricKey, context: String) throws -> Data {
        guard let combined = try AES.GCM.seal(
            plain, using: key, authenticating: Data(context.utf8)
        ).combined else { throw MemoraError.corruptData }
        return combined
    }

    static func open(_ encrypted: Data, key: SymmetricKey, context: String) throws -> Data {
        do {
            return try AES.GCM.open(
                AES.GCM.SealedBox(combined: encrypted), using: key,
                authenticating: Data(context.utf8)
            )
        } catch { throw MemoraError.corruptData }
    }

    static func bytes(_ key: SymmetricKey) -> Data { key.withUnsafeBytes { Data($0) } }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func recoveryString(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined()
            .split(every: 8).joined(separator: "-")
    }

    static func recoveryData(_ input: String) -> Data? {
        let hex = input.filter { $0 != "-" && !$0.isWhitespace }
        guard hex.count == 64 else { return nil }
        var data = Data()
        var offset = hex.startIndex
        while offset < hex.endIndex {
            let next = hex.index(offset, offsetBy: 2)
            guard let byte = UInt8(hex[offset..<next], radix: 16) else { return nil }
            data.append(byte)
            offset = next
        }
        return data
    }
}

private extension String {
    func split(every length: Int) -> [String] {
        stride(from: 0, to: count, by: length).map { index in
            let start = self.index(startIndex, offsetBy: index)
            let end = self.index(start, offsetBy: min(length, count - index))
            return String(self[start..<end])
        }
    }
}

enum BiometricVault {
    private static let service = "app.memora.native.vault"

    static func available() -> Bool {
        let context = LAContext()
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    static func save(_ key: SymmetricKey, account: UUID) throws {
        guard available() else { throw MemoraError.invalidInput("Face ID no está disponible.") }
        var error: Unmanaged<CFError>?
        guard let control = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .biometryCurrentSet, &error
        ) else { throw MemoraError.corruptData }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.uuidString
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecAttrAccessControl as String] = control
        add[kSecValueData as String] = MemoraCrypto.bytes(key)
        guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else {
            throw MemoraError.corruptData
        }
    }

    static func read(account: UUID) throws -> SymmetricKey {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else {
            throw MemoraError.invalidInput("Face ID no está disponible.")
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context,
            kSecUseOperationPrompt as String: "Desbloquear la bóveda de Memora"
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, data.count == 32 else {
            throw MemoraError.invalidInput("No se pudo desbloquear con Face ID. Usa la contraseña de la bóveda.")
        }
        return SymmetricKey(data: data)
    }

    static func remove(account: UUID) {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.uuidString
        ] as CFDictionary)
    }
}
