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
        let hex = input.filter { $0 != "-" && !$0.isWhitespace && $0 != ":" && $0 != "_" }
            .uppercased()
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

enum BiometricAuth {
    enum BiometricType {
        case none, touchID, faceID
        var title: String {
            switch self {
            case .none: return "No disponible"
            case .touchID: return "Touch ID"
            case .faceID: return "Face ID"
            }
        }
    }

    static var biometricType: BiometricType {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        case .opticID: return .faceID
        case .none: return .none
        @unknown default: return .none
        }
    }

    static func available() -> Bool {
        let context = LAContext()
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    static func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Cancelar"
        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }
}

// MARK: - Biometric Account Key (Face ID Login & Recovery)
enum BiometricAccountKey {
    private static let service = "app.memora.native.account-root"

    static func available() -> Bool {
        BiometricAuth.available()
    }

    static func save(_ key: SymmetricKey, email: String) throws {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: normalizedEmail
        ]
        SecItemDelete(query as CFDictionary)
        
        var add = query
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        add[kSecValueData as String] = MemoraCrypto.bytes(key)
        
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw MemoraError.corruptData
        }
    }

    static func read(email: String) async throws -> SymmetricKey {
        guard available() else {
            throw MemoraError.invalidInput("Face ID no está disponible en este dispositivo.")
        }
        let authenticated = await BiometricAuth.authenticate(reason: "Identifícate con Face ID para acceder a tu cuenta Memora")
        guard authenticated else {
            throw MemoraError.invalidInput("Verificación Face ID cancelada o no reconocida.")
        }
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: normalizedEmail,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data, data.count == 32 else {
            throw MemoraError.invalidInput("No se encontró una llave Face ID guardada para esta cuenta. Usa tu contraseña o código de recuperación.")
        }
        return SymmetricKey(data: data)
    }

    static func hasKey(email: String) -> Bool {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: normalizedEmail,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        return SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess
    }

    static func remove(email: String) {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: normalizedEmail
        ] as CFDictionary)
    }
}

// MARK: - iCloud Cloud Account Store (Zero Data Loss)
enum CloudAccountStore {
    private static let keyPrefix = "memora.cloud.account."
    private static let activeKey = "memora.cloud.active_email"

    static func saveAccount(_ record: AccountRecord) {
        let key = keyPrefix + record.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let encoded = try? JSONEncoder().encode(record) {
            NSUbiquitousKeyValueStore.default.set(encoded, forKey: key)
            NSUbiquitousKeyValueStore.default.set(record.email, forKey: activeKey)
            NSUbiquitousKeyValueStore.default.synchronize()
        }
    }

    static func fetchAccount(email: String) -> AccountRecord? {
        let key = keyPrefix + email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let data = NSUbiquitousKeyValueStore.default.data(forKey: key),
              let record = try? JSONDecoder().decode(AccountRecord.self, from: data) else {
            return nil
        }
        return record
    }

    static func lastActiveEmail() -> String? {
        NSUbiquitousKeyValueStore.default.string(forKey: activeKey)
    }

    static func removeAccount(email: String) {
        let key = keyPrefix + email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        NSUbiquitousKeyValueStore.default.removeObject(forKey: key)
        NSUbiquitousKeyValueStore.default.synchronize()
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

enum PersistentSession {
    private static let service = "app.memora.native.session"

    static func save(_ key: SymmetricKey, account: UUID) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.uuidString
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        add[kSecValueData as String] = MemoraCrypto.bytes(key)
        guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else {
            throw MemoraError.corruptData
        }
    }

    static func read(account: UUID) -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, data.count == 32 else { return nil }
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
