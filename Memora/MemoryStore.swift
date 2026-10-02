import CryptoKit
import Foundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
final class MemoryStore: ObservableObject {
    @Published private(set) var account: AccountRecord?
    @Published private(set) var authenticated = false
    @Published private(set) var library = MemoryLibrary()
    @Published private(set) var privateLibrary: PrivateLibrary?
    @Published var recoveryCode: String?
    @Published var notice: String?
    @Published var busy = false
    @Published private(set) var persistentSessionEnabled = true

    private var rootKey: SymmetricKey?
    private var vaultKey: SymmetricKey?
    private var vaultDeadline: Date?
    private var thumbnailCache: [UUID: UIImage] = [:]

    private let base: URL
    private let fileLimit = 50 * 1024 * 1024
    private let persistentSessionPreference = "memora.persistent-session.enabled"

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        base = support.appendingPathComponent("Memora", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            account = try read(AccountRecord.self, from: base.appendingPathComponent("account.json"))
            if UserDefaults.standard.object(forKey: persistentSessionPreference) != nil {
                persistentSessionEnabled = UserDefaults.standard.bool(forKey: persistentSessionPreference)
            }
            if persistentSessionEnabled, let account,
               let savedKey = PersistentSession.read(account: account.id) {
                rootKey = savedKey
                do {
                    try loadLibrary()
                    authenticated = true
                } catch {
                    rootKey = nil
                    PersistentSession.remove(account: account.id)
                    notice = "La sesión guardada no pudo verificarse. Inicia sesión de nuevo."
                }
            }
        } catch {
            notice = "No se pudo abrir el almacenamiento local: \(error.localizedDescription)"
        }
    }

    var hasAccount: Bool { account != nil }
    var vaultUnlocked: Bool { privateLibrary != nil && vaultKey != nil }
    var vaultConfigured: Bool { account?.wrappedVaultKey != nil }
    var biometricAvailable: Bool { BiometricVault.available() }
    var activeAssets: [MemoryAsset] { library.assets.filter { $0.deletedAt == nil } }
    var trash: [MemoryAsset] { library.assets.filter { $0.deletedAt != nil } }
    var usedBytes: Int {
        library.assets.reduce(0) { $0 + $1.size } + (privateLibrary?.assets.reduce(0) { $0 + $1.size } ?? 0)
    }

    private var accountURL: URL { base.appendingPathComponent("account.json") }
    private var libraryURL: URL { base.appendingPathComponent("library.enc") }
    private var vaultURL: URL { base.appendingPathComponent("vault.enc") }
    private var filesURL: URL { base.appendingPathComponent("Files", isDirectory: true) }
    private var temporaryURL: URL { base.appendingPathComponent("Temporary", isDirectory: true) }

    private func read<T: Decodable>(_ type: T.Type, from url: URL) throws -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }

    private func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
    }

    private func saveAccount() throws {
        guard let account else { throw MemoraError.noAccount }
        try write(JSONEncoder().encode(account), to: accountURL)
    }

    private func normalized(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func validate(name: String, email: String, password: String) throws {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty, name.count <= 80 else {
            throw MemoraError.invalidInput("Escribe un nombre de hasta 80 caracteres.")
        }
        guard email.count <= 254, email.contains("@"), email.split(separator: "@").count == 2,
              email.split(separator: "@").last?.contains(".") == true else {
            throw MemoraError.invalidInput("Escribe un correo válido.")
        }
        guard password.count >= 12 else {
            throw MemoraError.invalidInput("Usa una contraseña de al menos 12 caracteres.")
        }
    }

    func register(name: String, email input: String, password: String) throws -> String {
        guard account == nil else {
            throw MemoraError.invalidInput("Ya existe una cuenta local. Inicia sesión.")
        }
        let email = normalized(input)
        try validate(name: name, email: email, password: password)
        let root = MemoraCrypto.randomKey()
        let recovery = try MemoraCrypto.randomData(32)
        let salt = try MemoraCrypto.randomData(16)
        let id = UUID()
        let record = AccountRecord(
            id: id, name: name.trimmingCharacters(in: .whitespacesAndNewlines), email: email,
            createdAt: .now, passwordSalt: salt,
            wrappedRootKey: try MemoraCrypto.seal(
                MemoraCrypto.bytes(root), key: MemoraCrypto.passwordKey(password, salt: salt),
                context: "memora:account:\(id):password"
            ),
            wrappedRecoveryKey: try MemoraCrypto.seal(
                MemoraCrypto.bytes(root), key: SymmetricKey(data: recovery),
                context: "memora:account:\(id):recovery"
            )
        )
        account = record
        try saveAccount()
        rootKey = root
        library = MemoryLibrary()
        try saveLibrary()
        authenticated = true
        try? persistSessionIfEnabled()
        let code = MemoraCrypto.recoveryString(recovery)
        recoveryCode = code
        return code
    }

    func login(email input: String, password: String) throws {
        guard var record = account, record.email == normalized(input) else { throw MemoraError.wrongCredentials }
        if let blocked = record.blockedUntil, blocked > .now { throw MemoraError.locked }
        let plain: Data
        do {
            plain = try MemoraCrypto.open(
                record.wrappedRootKey,
                key: MemoraCrypto.passwordKey(password, salt: record.passwordSalt),
                context: "memora:account:\(record.id):password"
            )
        } catch {
            record.failedAttempts += 1
            if record.failedAttempts >= 5 {
                record.failedAttempts = 0
                record.blockedUntil = Date().addingTimeInterval(30)
            }
            account = record
            try? saveAccount()
            throw MemoraError.wrongCredentials
        }
        guard plain.count == 32 else { throw MemoraError.corruptData }
        rootKey = SymmetricKey(data: plain)
        do { try loadLibrary() } catch { rootKey = nil; throw error }
        record.failedAttempts = 0
        record.blockedUntil = nil
        account = record
        try saveAccount()
        authenticated = true
        try? persistSessionIfEnabled()
    }

    func recover(email input: String, code: String, newPassword: String) throws -> String {
        guard var record = account, record.email == normalized(input) else { throw MemoraError.wrongCredentials }
        guard newPassword.count >= 12, let recovery = MemoraCrypto.recoveryData(code) else {
            throw MemoraError.invalidInput("Revisa el código y usa una contraseña de 12 caracteres o más.")
        }
        let plain = try MemoraCrypto.open(
            record.wrappedRecoveryKey, key: SymmetricKey(data: recovery),
            context: "memora:account:\(record.id):recovery"
        )
        guard plain.count == 32 else { throw MemoraError.corruptData }
        let newRecovery = try MemoraCrypto.randomData(32)
        let newSalt = try MemoraCrypto.randomData(16)
        record.passwordSalt = newSalt
        record.wrappedRootKey = try MemoraCrypto.seal(
            plain, key: MemoraCrypto.passwordKey(newPassword, salt: newSalt),
            context: "memora:account:\(record.id):password"
        )
        record.wrappedRecoveryKey = try MemoraCrypto.seal(
            plain, key: SymmetricKey(data: newRecovery),
            context: "memora:account:\(record.id):recovery"
        )
        record.failedAttempts = 0
        record.blockedUntil = nil
        account = record
        try saveAccount()
        rootKey = SymmetricKey(data: plain)
        try loadLibrary()
        authenticated = true
        try? persistSessionIfEnabled()
        let code = MemoraCrypto.recoveryString(newRecovery)
        recoveryCode = code
        return code
    }

    func logout() {
        if let account { PersistentSession.remove(account: account.id) }
        lockVault()
        rootKey = nil
        thumbnailCache.removeAll()
        library = MemoryLibrary()
        authenticated = false
        recoveryCode = nil
    }

    func setPersistentSession(_ enabled: Bool) throws {
        persistentSessionEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: persistentSessionPreference)
        if enabled {
            try persistSessionIfEnabled()
        } else if let account {
            PersistentSession.remove(account: account.id)
        }
    }

    private func persistSessionIfEnabled() throws {
        guard persistentSessionEnabled, let account, let rootKey else { return }
        try PersistentSession.save(rootKey, account: account.id)
    }

    func updateProfileName(_ name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, var record = account else {
            throw MemoraError.invalidInput("Escribe un nombre válido.")
        }
        record.name = trimmed
        account = record
        try saveAccount()
        try? persistSessionIfEnabled()
    }

    func changePassword(current: String, new: String) throws {
        guard new.count >= 12, var record = account, let rootKey else {
            throw MemoraError.invalidInput("La contraseña nueva debe tener al menos 12 caracteres.")
        }
        _ = try MemoraCrypto.open(
            record.wrappedRootKey,
            key: MemoraCrypto.passwordKey(current, salt: record.passwordSalt),
            context: "memora:account:\(record.id):password"
        )
        let salt = try MemoraCrypto.randomData(16)
        record.passwordSalt = salt
        record.wrappedRootKey = try MemoraCrypto.seal(
            MemoraCrypto.bytes(rootKey),
            key: MemoraCrypto.passwordKey(new, salt: salt),
            context: "memora:account:\(record.id):password"
        )
        record.failedAttempts = 0
        record.blockedUntil = nil
        account = record
        try saveAccount()
    }

    private func metadataKey() throws -> SymmetricKey {
        guard let rootKey, let account else { throw MemoraError.noAccount }
        return MemoraCrypto.subkey(rootKey, account: account.id, purpose: "metadata")
    }

    private func fileWrapKey() throws -> SymmetricKey {
        guard let rootKey, let account else { throw MemoraError.noAccount }
        return MemoraCrypto.subkey(rootKey, account: account.id, purpose: "file-wrap")
    }

    private func loadLibrary() throws {
        guard let account else { throw MemoraError.noAccount }
        if FileManager.default.fileExists(atPath: libraryURL.path) {
            let plain = try MemoraCrypto.open(
                Data(contentsOf: libraryURL), key: metadataKey(),
                context: "memora:account:\(account.id):library"
            )
            library = try JSONDecoder().decode(MemoryLibrary.self, from: plain)
        } else { library = MemoryLibrary() }
    }

    private func saveLibrary() throws {
        guard let account else { throw MemoraError.noAccount }
        try write(MemoraCrypto.seal(
            JSONEncoder().encode(library), key: metadataKey(),
            context: "memora:account:\(account.id):library"
        ), to: libraryURL)
    }

    private func loadVault() throws {
        guard let account, let vaultKey else { throw MemoraError.noAccount }
        if FileManager.default.fileExists(atPath: vaultURL.path) {
            let plain = try MemoraCrypto.open(
                Data(contentsOf: vaultURL), key: vaultKey,
                context: "memora:account:\(account.id):vault-manifest"
            )
            privateLibrary = try JSONDecoder().decode(PrivateLibrary.self, from: plain)
        } else { privateLibrary = PrivateLibrary() }
    }

    private func saveVault() throws {
        guard let account, let vaultKey, let privateLibrary else { throw MemoraError.noAccount }
        try write(MemoraCrypto.seal(
            JSONEncoder().encode(privateLibrary), key: vaultKey,
            context: "memora:account:\(account.id):vault-manifest"
        ), to: vaultURL)
    }

    func createSection(_ name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        library.sections.append(MemorySection(id: UUID(), name: trimmed, symbol: "folder"))
        try saveLibrary()
    }

    func createAlbum(_ name: String, sectionID: UUID? = nil, inVault: Bool = false) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let album = MemoryAlbum(id: UUID(), name: trimmed, sectionID: sectionID, createdAt: .now)
        if inVault {
            guard privateLibrary != nil else { throw MemoraError.locked }
            privateLibrary?.albums.append(album)
            try saveVault()
        } else {
            library.albums.append(album)
            try saveLibrary()
        }
    }

    func createPerson(_ name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        library.people.append(MemoryPerson(id: UUID(), name: trimmed))
        try saveLibrary()
    }

    func mergePeople(source: UUID, into target: UUID) throws {
        guard source != target, library.people.contains(where: { $0.id == source }),
              library.people.contains(where: { $0.id == target }) else { return }
        if FileManager.default.fileExists(atPath: vaultURL.path), !vaultUnlocked {
            throw MemoraError.invalidInput("Desbloquea la bóveda antes de combinar personas.")
        }
        library.assets = library.assets.map { asset in
            var result = asset
            result.personIDs = Array(Set(asset.personIDs.map { $0 == source ? target : $0 }))
            return result
        }
        library.people.removeAll { $0.id == source }
        if privateLibrary != nil {
            privateLibrary?.assets = privateLibrary!.assets.map { asset in
                var result = asset
                result.personIDs = Array(Set(asset.personIDs.map { $0 == source ? target : $0 }))
                return result
            }
            try saveVault()
        }
        try saveLibrary()
    }

    func toggleFavorite(_ id: UUID) throws {
        guard let index = library.assets.firstIndex(where: { $0.id == id }) else { return }
        library.assets[index].favorite.toggle()
        try saveLibrary()
    }

    func add(_ assetID: UUID, to albumID: UUID) throws {
        guard library.albums.contains(where: { $0.id == albumID }),
              let index = library.assets.firstIndex(where: { $0.id == assetID }) else { return }
        if !library.assets[index].albumIDs.contains(albumID) {
            library.assets[index].albumIDs.append(albumID)
            try saveLibrary()
        }
    }

    func assign(_ assetID: UUID, to personID: UUID) throws {
        guard library.people.contains(where: { $0.id == personID }),
              let index = library.assets.firstIndex(where: { $0.id == assetID }) else { return }
        if !library.assets[index].personIDs.contains(personID) {
            library.assets[index].personIDs.append(personID)
            try saveLibrary()
        }
    }

    func moveToTrash(_ id: UUID) throws {
        guard let index = library.assets.firstIndex(where: { $0.id == id }) else { return }
        library.assets[index].deletedAt = .now
        try saveLibrary()
    }

    func restore(_ id: UUID) throws {
        guard let index = library.assets.firstIndex(where: { $0.id == id }) else { return }
        library.assets[index].deletedAt = nil
        try saveLibrary()
    }

    func deleteForever(_ id: UUID) throws {
        guard let index = library.assets.firstIndex(where: { $0.id == id }) else { return }
        library.assets.remove(at: index)
        try saveLibrary()
        for suffix in [".enc", ".thumb"] {
            try? FileManager.default.removeItem(at: filesURL.appendingPathComponent(id.uuidString + suffix))
        }
        thumbnailCache[id] = nil
    }

    func restoreFromTrash(_ id: UUID) throws {
        try restore(id)
    }

    func emptyTrash() throws {
        let trashIDs = trash.map { $0.id }
        for id in trashIDs {
            try deleteForever(id)
        }
    }

    private func assetKey(_ asset: MemoryAsset, secure: Bool) throws -> SymmetricKey {
        guard let account else { throw MemoraError.noAccount }
        let wrapping = try (secure ? requiredVaultKey() : fileWrapKey())
        let plain = try MemoraCrypto.open(
            asset.wrappedFileKey, key: wrapping,
            context: "memora:account:\(account.id):file-key:\(asset.id)"
        )
        guard plain.count == 32 else { throw MemoraError.corruptData }
        return SymmetricKey(data: plain)
    }

    private func requiredVaultKey() throws -> SymmetricKey {
        guard let vaultKey, vaultUnlocked else { throw MemoraError.locked }
        return vaultKey
    }

    func importData(_ data: Data, name: String, mime: String, secure: Bool = false) throws {
        guard let account, authenticated else { throw MemoraError.noAccount }
        guard data.count <= fileLimit else { throw MemoraError.fileTooLarge }
        let hash = MemoraCrypto.sha256(data)
        let exists = secure
            ? privateLibrary?.assets.contains(where: { $0.sha256 == hash }) == true
            : library.assets.contains(where: { $0.sha256 == hash })
        guard !exists else { throw MemoraError.duplicate }
        let id = UUID()
        let key = MemoraCrypto.randomKey()
        let wrapping = try (secure ? requiredVaultKey() : fileWrapKey())
        let envelope = try MemoraCrypto.seal(
            MemoraCrypto.bytes(key), key: wrapping,
            context: "memora:account:\(account.id):file-key:\(id)"
        )
        let encrypted = try MemoraCrypto.seal(
            data, key: key, context: "memora:account:\(account.id):original:\(id)"
        )
        let previousLibrary = library
        let previousPrivateLibrary = privateLibrary
        try FileManager.default.createDirectory(at: filesURL, withIntermediateDirectories: true)
        let originalURL = filesURL.appendingPathComponent(id.uuidString + ".enc")
        try write(encrypted, to: originalURL)
        var thumbnail = false
        do {
            if mime.hasPrefix("image/"), let image = UIImage(data: data) {
                let side: CGFloat = 420
                let ratio = min(side / image.size.width, side / image.size.height, 1)
                let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
                let scaled = UIGraphicsImageRenderer(size: size).image { _ in
                    image.draw(in: CGRect(origin: .zero, size: size))
                }
                if let jpeg = scaled.jpegData(compressionQuality: 0.75) {
                    try write(MemoraCrypto.seal(
                        jpeg, key: key, context: "memora:account:\(account.id):thumb:\(id)"
                    ), to: filesURL.appendingPathComponent(id.uuidString + ".thumb"))
                    thumbnail = true
                }
            }
            let asset = MemoryAsset(
                id: id, name: name, mime: mime, kind: .classify(mime), size: data.count,
                addedAt: .now, capturedAt: .now, sha256: hash, wrappedFileKey: envelope,
                hasThumbnail: thumbnail
            )
            if secure {
                guard privateLibrary != nil else { throw MemoraError.locked }
                privateLibrary?.assets.insert(asset, at: 0)
                try saveVault()
            } else {
                library.assets.insert(asset, at: 0)
                try saveLibrary()
            }
        } catch {
            library = previousLibrary
            privateLibrary = previousPrivateLibrary
            try? FileManager.default.removeItem(at: originalURL)
            try? FileManager.default.removeItem(at: filesURL.appendingPathComponent(id.uuidString + ".thumb"))
            throw error
        }
    }

    func importPhotoItems(_ items: [PhotosPickerItem], secure: Bool = false) async {
        busy = true
        defer { busy = false }
        var imported = 0
        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    notice = "iOS no entregó una representación compatible de uno de los archivos."
                    continue
                }
                let type = item.supportedContentTypes.first
                let mime = type?.preferredMIMEType ?? "application/octet-stream"
                let ext = type?.preferredFilenameExtension ?? "bin"
                try importData(data, name: "Recuerdo-\(UUID().uuidString.prefix(8)).\(ext)", mime: mime, secure: secure)
                imported += 1
            } catch MemoraError.duplicate {
                continue
            } catch {
                notice = error.localizedDescription
                break
            }
        }
        if imported > 0 { notice = "\(imported) archivo\(imported == 1 ? "" : "s") importado\(imported == 1 ? "" : "s")." }
    }

    func importURLs(_ urls: [URL], secure: Bool = false) {
        var imported = 0
        for url in urls {
            let granted = url.startAccessingSecurityScopedResource()
            defer { if granted { url.stopAccessingSecurityScopedResource() } }
            do {
                if (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) > fileLimit {
                    throw MemoraError.fileTooLarge
                }
                let data = try Data(contentsOf: url)
                try importData(data, name: url.lastPathComponent,
                               mime: (UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"),
                               secure: secure)
                imported += 1
            } catch MemoraError.duplicate {
                continue
            } catch {
                notice = error.localizedDescription
                break
            }
        }
        if imported > 0 { notice = "\(imported) archivo\(imported == 1 ? "" : "s") importado\(imported == 1 ? "" : "s")." }
    }

    func thumbnail(for asset: MemoryAsset, secure: Bool = false) -> UIImage? {
        guard asset.hasThumbnail else { return nil }
        if let cached = thumbnailCache[asset.id] { return cached }
        guard let account,
              let encrypted = try? Data(contentsOf: filesURL.appendingPathComponent(asset.id.uuidString + ".thumb")),
              let key = try? assetKey(asset, secure: secure),
              let plain = try? MemoraCrypto.open(
                encrypted, key: key,
                context: "memora:account:\(account.id):thumb:\(asset.id)"
              ), let image = UIImage(data: plain) else { return nil }
        thumbnailCache[asset.id] = image
        return image
    }

    func original(for asset: MemoryAsset, secure: Bool = false) throws -> Data {
        guard let account else { throw MemoraError.noAccount }
        let encrypted = try Data(contentsOf: filesURL.appendingPathComponent(asset.id.uuidString + ".enc"))
        let plain = try MemoraCrypto.open(
            encrypted, key: assetKey(asset, secure: secure),
            context: "memora:account:\(account.id):original:\(asset.id)"
        )
        guard MemoraCrypto.sha256(plain) == asset.sha256 else { throw MemoraError.corruptData }
        return plain
    }

    func temporaryOriginal(for asset: MemoryAsset, secure: Bool = false) throws -> URL {
        let data = try original(for: asset, secure: secure)
        try FileManager.default.createDirectory(at: temporaryURL, withIntermediateDirectories: true)
        let ext = UTType(mimeType: asset.mime)?.preferredFilenameExtension
            ?? (asset.name as NSString).pathExtension
        let url = temporaryURL.appendingPathComponent(
            asset.id.uuidString + "." + (ext.isEmpty ? "bin" : ext)
        )
        try write(data, to: url)
        return url
    }

    func removeTemporary(_ url: URL) {
        guard url.deletingLastPathComponent() == temporaryURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    func clearPreviewCache() {
        thumbnailCache.removeAll()
        try? FileManager.default.removeItem(at: temporaryURL)
        notice = "Caché temporal liberada. Los originales cifrados se conservan."
    }

    func configureVault(password: String) throws -> String {
        guard password.count >= 12, var account else {
            throw MemoraError.invalidInput("La bóveda necesita una contraseña de al menos 12 caracteres.")
        }
        guard account.wrappedVaultKey == nil else {
            throw MemoraError.invalidInput("La bóveda ya existe.")
        }
        let salt = try MemoraCrypto.randomData(16)
        let key = MemoraCrypto.randomKey()
        let recovery = try MemoraCrypto.randomData(32)
        let previous = account
        account.vaultSalt = salt
        account.wrappedVaultKey = try MemoraCrypto.seal(
            MemoraCrypto.bytes(key), key: MemoraCrypto.passwordKey(password, salt: salt),
            context: "memora:account:\(account.id):vault-key"
        )
        account.vaultRecoveryEnvelope = try MemoraCrypto.seal(
            MemoraCrypto.bytes(key), key: SymmetricKey(data: recovery),
            context: "memora:account:\(account.id):vault-recovery"
        )
        self.account = account
        vaultKey = key
        privateLibrary = PrivateLibrary()
        do {
            try saveVault()
            try saveAccount()
        } catch {
            self.account = previous
            lockVault()
            try? FileManager.default.removeItem(at: vaultURL)
            throw error
        }
        vaultDeadline = Date().addingTimeInterval(15 * 60)
        return MemoraCrypto.recoveryString(recovery)
    }

    func recoverVault(code: String, newPassword: String) throws -> String {
        guard var account, let envelope = account.vaultRecoveryEnvelope,
              let recovery = MemoraCrypto.recoveryData(code), newPassword.count >= 12 else {
            throw MemoraError.invalidInput("Revisa el código y usa una contraseña de 12 caracteres o más.")
        }
        let plain = try MemoraCrypto.open(
            envelope, key: SymmetricKey(data: recovery),
            context: "memora:account:\(account.id):vault-recovery"
        )
        guard plain.count == 32 else { throw MemoraError.corruptData }
        let nextRecovery = try MemoraCrypto.randomData(32)
        let salt = try MemoraCrypto.randomData(16)
        account.vaultSalt = salt
        account.wrappedVaultKey = try MemoraCrypto.seal(
            plain, key: MemoraCrypto.passwordKey(newPassword, salt: salt),
            context: "memora:account:\(account.id):vault-key"
        )
        account.vaultRecoveryEnvelope = try MemoraCrypto.seal(
            plain, key: SymmetricKey(data: nextRecovery),
            context: "memora:account:\(account.id):vault-recovery"
        )
        vaultKey = SymmetricKey(data: plain)
        do { try loadVault() } catch { lockVault(); throw error }
        self.account = account
        try saveAccount()
        vaultDeadline = Date().addingTimeInterval(15 * 60)
        BiometricVault.remove(account: account.id)
        return MemoraCrypto.recoveryString(nextRecovery)
    }

    func unlockVault(password: String) throws {
        guard let account, let salt = account.vaultSalt,
              let envelope = account.wrappedVaultKey else { throw MemoraError.noAccount }
        let plain = try MemoraCrypto.open(
            envelope, key: MemoraCrypto.passwordKey(password, salt: salt),
            context: "memora:account:\(account.id):vault-key"
        )
        guard plain.count == 32 else { throw MemoraError.corruptData }
        vaultKey = SymmetricKey(data: plain)
        do { try loadVault() } catch { lockVault(); throw error }
        vaultDeadline = Date().addingTimeInterval(15 * 60)
    }

    func unlockVaultWithBiometrics() throws {
        guard let account else { throw MemoraError.noAccount }
        vaultKey = try BiometricVault.read(account: account.id)
        do { try loadVault() } catch { lockVault(); throw error }
        vaultDeadline = Date().addingTimeInterval(15 * 60)
    }

    func enableVaultBiometrics() throws {
        guard let account, let vaultKey else { throw MemoraError.locked }
        try BiometricVault.save(vaultKey, account: account.id)
    }

    func lockVault() {
        vaultKey = nil
        vaultDeadline = nil
        privateLibrary = nil
        thumbnailCache.removeAll()
        try? FileManager.default.removeItem(at: temporaryURL)
    }

    func checkVaultDeadline() {
        if let vaultDeadline, vaultDeadline <= .now { lockVault() }
    }
}
