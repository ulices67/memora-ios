import CryptoKit
import Foundation
import ImageIO
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct AssetMetadataExtractor {
    static func extract(from data: Data) -> (
        camera: String?,
        iso: Int?,
        aperture: Double?,
        focalLength: Double?,
        width: Int?,
        height: Int?,
        date: Date?,
        location: String?,
        lat: Double?,
        lon: Double?
    ) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return (nil, nil, nil, nil, nil, nil, nil, nil, nil, nil)
        }

        let width = properties[kCGImagePropertyPixelWidth] as? Int
        let height = properties[kCGImagePropertyPixelHeight] as? Int

        var camera: String?
        if let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            let make = tiff[kCGImagePropertyTIFFMake] as? String
            let model = tiff[kCGImagePropertyTIFFModel] as? String
            if let model, !model.isEmpty {
                camera = model
            } else if let make {
                camera = make
            }
        }

        var iso: Int?
        var aperture: Double?
        var focalLength: Double?
        var capturedDate: Date?

        if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            if let isoArray = exif[kCGImagePropertyExifISOSpeedRatings] as? [Int], let firstIso = isoArray.first {
                iso = firstIso
            } else if let isoVal = exif[kCGImagePropertyExifISOSpeedRatings] as? Int {
                iso = isoVal
            }
            if let fNum = exif[kCGImagePropertyExifFNumber] as? Double {
                aperture = fNum
            }
            if let focal = exif[kCGImagePropertyExifFocalLength] as? Double {
                focalLength = focal
            }
            if let dateStr = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
                let df = DateFormatter()
                df.dateFormat = "yyyy:MM:dd HH:mm:ss"
                capturedDate = df.date(from: dateStr)
            }
        }

        var locationStr: String?
        var lat: Double?
        var lon: Double?
        if let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any] {
            if let latitude = gps[kCGImagePropertyGPSLatitude] as? Double,
               let longitude = gps[kCGImagePropertyGPSLongitude] as? Double {
                let latRef = gps[kCGImagePropertyGPSLatitudeRef] as? String ?? "N"
                let lonRef = gps[kCGImagePropertyGPSLongitudeRef] as? String ?? "E"
                let finalLat = latRef == "S" ? -latitude : latitude
                let finalLon = lonRef == "W" ? -longitude : longitude
                lat = finalLat
                lon = finalLon
                locationStr = String(format: "%.3f, %.3f", finalLat, finalLon)
            }
        }

        return (camera, iso, aperture, focalLength, width, height, capturedDate, locationStr, lat, lon)
    }
}

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
    @Published private(set) var appBiometricsEnabled = false
    @Published var appLocked = false
    @Published var isPerformingBiometricAuth = false
    @Published var autoAlbumByFaceEnabled = true
    @Published private(set) var lastCloudflareBackupDate: Date?

    private var rootKey: SymmetricKey?
    private var vaultKey: SymmetricKey?
    private var vaultDeadline: Date?
    private var thumbnailCache: [UUID: UIImage] = [:]
    private var faceCropCache: [UUID: UIImage] = [:]

    private let base: URL
    private let fileLimit = 50 * 1024 * 1024
    private let persistentSessionPreference = "memora.persistent-session.enabled"
    private let appBiometricsPreference = "memora.app-biometrics.enabled"
    private let autoAlbumPreference = "memora.auto-album-face.enabled"
    private let lastBackupPreference = "memora.cloudflare.lastBackup"

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        base = support.appendingPathComponent("Memora", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            account = try read(AccountRecord.self, from: base.appendingPathComponent("account.json"))
            
            // Auto-restauración desde iCloud si no hay cuenta local
            if account == nil, let activeEmail = CloudAccountStore.lastActiveEmail(),
               let cloudAccount = CloudAccountStore.fetchAccount(email: activeEmail) {
                account = cloudAccount
                try? saveAccount()
            }

            if UserDefaults.standard.object(forKey: persistentSessionPreference) != nil {
                persistentSessionEnabled = UserDefaults.standard.bool(forKey: persistentSessionPreference)
            }
            if UserDefaults.standard.object(forKey: autoAlbumPreference) != nil {
                autoAlbumByFaceEnabled = UserDefaults.standard.bool(forKey: autoAlbumPreference)
            }
            if UserDefaults.standard.bool(forKey: appBiometricsPreference) {
                appBiometricsEnabled = true
                appLocked = true
            }
            if let timestamp = UserDefaults.standard.object(forKey: lastBackupPreference) as? Double {
                lastCloudflareBackupDate = Date(timeIntervalSince1970: timestamp)
            }
            if persistentSessionEnabled, let account,
               let savedKey = PersistentSession.read(account: account.id) {
                rootKey = savedKey
                do {
                    try loadLibrary()
                    authenticated = true
                    Task { [weak self] in
                        await self?.migrateAndCleanFacesIfNeeded()
                    }
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

    var baseDirectory: URL { base }
    var hasAccount: Bool { account != nil || CloudAccountStore.lastActiveEmail() != nil }
    var vaultUnlocked: Bool { privateLibrary != nil && vaultKey != nil }
    var vaultConfigured: Bool { account?.wrappedVaultKey != nil }
    var vaultBiometricsReady: Bool {
        guard let account else { return false }
        return BiometricVault.hasKey(account: account.id)
    }
    var biometricAvailable: Bool { BiometricAuth.available() }
    var biometricType: BiometricAuth.BiometricType { BiometricAuth.biometricType }
    var activeAssets: [MemoryAsset] { library.assets.filter { $0.deletedAt == nil } }
    var unalbumedPhotoAssets: [MemoryAsset] { activeAssets.filter { $0.kind == .photo && $0.albumIDs.isEmpty } }
    var trash: [MemoryAsset] { library.assets.filter { $0.deletedAt != nil } }
    var usedBytes: Int {
        library.assets.reduce(0) { $0 + $1.size } + (privateLibrary?.assets.reduce(0) { $0 + $1.size } ?? 0)
    }
    var detectedCloudEmail: String? { CloudAccountStore.lastActiveEmail() }

    func requireRootKey() throws -> SymmetricKey {
        guard let rootKey else { throw MemoraError.noAccount }
        return rootKey
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
        CloudAccountStore.saveAccount(account)
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

    func syncRecoveryCodeToCloud(email: String, code: String) {
        let key = "memora.recovery.\(email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
        NSUbiquitousKeyValueStore.default.set(code, forKey: key)
        NSUbiquitousKeyValueStore.default.synchronize()
    }
    
    func fetchRecoveryCodeFromCloud(email: String) -> String? {
        let key = "memora.recovery.\(email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
        return NSUbiquitousKeyValueStore.default.string(forKey: key)
    }

    func register(name: String, email input: String, password: String) throws -> String {
        let email = normalized(input)
        if let existing = account, existing.email == email {
            throw MemoraError.invalidInput("Ya existe una cuenta con este correo. Inicia sesión.")
        }
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
        try? BiometricAccountKey.save(root, email: email)
        let code = MemoraCrypto.recoveryString(recovery)
        recoveryCode = code
        syncRecoveryCodeToCloud(email: email, code: code)
        return code
    }

    func login(email input: String, password: String) throws {
        let normalizedEmail = normalized(input)
        
        // Búsqueda local o restauración transparente desde iCloud
        var currentAccount = account
        if currentAccount == nil || currentAccount?.email != normalizedEmail {
            if let cloudRecord = CloudAccountStore.fetchAccount(email: normalizedEmail) {
                currentAccount = cloudRecord
                self.account = cloudRecord
                try? saveAccount()
            }
        }
        
        guard var record = currentAccount, record.email == normalizedEmail else {
            throw MemoraError.wrongCredentials
        }
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
        let verifiedRoot = SymmetricKey(data: plain)
        rootKey = verifiedRoot
        do { try loadLibrary() } catch { rootKey = nil; throw error }
        record.failedAttempts = 0
        record.blockedUntil = nil
        account = record
        try saveAccount()
        try? BiometricAccountKey.save(verifiedRoot, email: normalizedEmail)
        authenticated = true
        try? persistSessionIfEnabled()
        Task { [weak self] in
            await self?.migrateAndCleanFacesIfNeeded()
        }
    }

    func loginWithBiometrics(email input: String) async throws {
        guard !isPerformingBiometricAuth else { return }
        isPerformingBiometricAuth = true
        defer { isPerformingBiometricAuth = false }

        let normalizedEmail = normalized(input)
        var currentAccount = account
        if currentAccount == nil || currentAccount?.email != normalizedEmail {
            if let cloudRecord = CloudAccountStore.fetchAccount(email: normalizedEmail) {
                currentAccount = cloudRecord
                self.account = cloudRecord
                try? saveAccount()
            }
        }
        guard let record = currentAccount, record.email == normalizedEmail else {
            throw MemoraError.invalidInput("No se encontró la cuenta para \(normalizedEmail).")
        }
        let biometricKey = try await BiometricAccountKey.read(email: normalizedEmail)
        rootKey = biometricKey
        do {
            try loadLibrary()
        } catch {
            rootKey = nil
            throw error
        }
        self.account = record
        authenticated = true
        try? persistSessionIfEnabled()
        Task { [weak self] in
            await self?.migrateAndCleanFacesIfNeeded()
        }
    }

    func hasBiometricsEnrolled(email: String) -> Bool {
        BiometricAccountKey.hasKey(email: normalized(email))
    }

    func recover(email input: String, code: String, newPassword: String) throws -> String {
        let normalizedEmail = normalized(input)
        var currentAccount = account
        if currentAccount == nil || currentAccount?.email != normalizedEmail {
            if let cloudRecord = CloudAccountStore.fetchAccount(email: normalizedEmail) {
                currentAccount = cloudRecord
                self.account = cloudRecord
                try? saveAccount()
            }
        }
        guard var record = currentAccount, record.email == normalizedEmail else { throw MemoraError.wrongCredentials }
        guard newPassword.count >= 12, let recovery = MemoraCrypto.recoveryData(code) else {
            throw MemoraError.invalidInput("Revisa el código y usa una contraseña de 12 caracteres o más.")
        }
        let plain = try MemoraCrypto.open(
            record.wrappedRecoveryKey, key: SymmetricKey(data: recovery),
            context: "memora:account:\(record.id):recovery"
        )
        guard plain.count == 32 else { throw MemoraError.corruptData }
        let recoveredRoot = SymmetricKey(data: plain)
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
        rootKey = recoveredRoot
        try loadLibrary()
        try? BiometricAccountKey.save(recoveredRoot, email: normalizedEmail)
        authenticated = true
        try? persistSessionIfEnabled()
        let codeStr = MemoraCrypto.recoveryString(newRecovery)
        recoveryCode = codeStr
        syncRecoveryCodeToCloud(email: record.email, code: codeStr)
        Task { [weak self] in
            await self?.migrateAndCleanFacesIfNeeded()
        }
        return codeStr
    }

    func recoverWithBiometrics(email input: String, newPassword: String) async throws {
        guard !isPerformingBiometricAuth else { return }
        isPerformingBiometricAuth = true
        defer { isPerformingBiometricAuth = false }

        let normalizedEmail = normalized(input)
        var currentAccount = account
        if currentAccount == nil || currentAccount?.email != normalizedEmail {
            if let cloudRecord = CloudAccountStore.fetchAccount(email: normalizedEmail) {
                currentAccount = cloudRecord
                self.account = cloudRecord
                try? saveAccount()
            }
        }
        guard var record = currentAccount, record.email == normalizedEmail else { throw MemoraError.wrongCredentials }
        guard newPassword.count >= 12 else {
            throw MemoraError.invalidInput("La contraseña debe tener al menos 12 caracteres.")
        }
        let verifiedRoot = try await BiometricAccountKey.read(email: normalizedEmail)
        let newRecovery = try MemoraCrypto.randomData(32)
        let newSalt = try MemoraCrypto.randomData(16)
        record.passwordSalt = newSalt
        record.wrappedRootKey = try MemoraCrypto.seal(
            MemoraCrypto.bytes(verifiedRoot), key: MemoraCrypto.passwordKey(newPassword, salt: newSalt),
            context: "memora:account:\(record.id):password"
        )
        record.wrappedRecoveryKey = try MemoraCrypto.seal(
            MemoraCrypto.bytes(verifiedRoot), key: SymmetricKey(data: newRecovery),
            context: "memora:account:\(record.id):recovery"
        )
        record.failedAttempts = 0
        record.blockedUntil = nil
        account = record
        try saveAccount()
        rootKey = verifiedRoot
        try loadLibrary()
        authenticated = true
        try? persistSessionIfEnabled()
        let codeStr = MemoraCrypto.recoveryString(newRecovery)
        recoveryCode = codeStr
        syncRecoveryCodeToCloud(email: record.email, code: codeStr)
        Task { [weak self] in
            await self?.migrateAndCleanFacesIfNeeded()
        }
    }

    func logout() {
        if let account { PersistentSession.remove(account: account.id) }
        lockVault()
        rootKey = nil
        thumbnailCache.removeAll()
        faceCropCache.removeAll()
        library = MemoryLibrary()
        authenticated = false
        recoveryCode = nil
    }

    func wipeLocalData() {
        do {
            if FileManager.default.fileExists(atPath: base.path) {
                try FileManager.default.removeItem(at: base)
            }
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        } catch {
            print("Error wiping data: \(error)")
        }
        
        if let account {
            PersistentSession.remove(account: account.id)
        }
        account = nil
        authenticated = false
        library = MemoryLibrary()
        privateLibrary = nil
        rootKey = nil
        vaultKey = nil
        appLocked = false
        recoveryCode = nil
        faceCropCache.removeAll()
        notice = "Los datos locales han sido borrados. Puedes crear una nueva cuenta o recuperarla desde iCloud."
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

    func setAutoAlbumByFaceEnabled(_ enabled: Bool) {
        autoAlbumByFaceEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: autoAlbumPreference)
    }

    func setAppBiometricsEnabled(_ enabled: Bool) async throws {
        if enabled {
            guard BiometricAuth.available() else {
                throw MemoraError.invalidInput("Face ID o Touch ID no está configurado en este dispositivo.")
            }
            isPerformingBiometricAuth = true
            defer { isPerformingBiometricAuth = false }
            let success = await BiometricAuth.authenticate(reason: "Verifica con Face ID para activar la protección de la app")
            guard success else {
                throw MemoraError.invalidInput("No se pudo verificar tu identidad biométrica.")
            }
        }
        appBiometricsEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: appBiometricsPreference)
        if !enabled { appLocked = false }
    }

    func unlockAppWithBiometrics() async -> Bool {
        guard appBiometricsEnabled else {
            appLocked = false
            return true
        }
        guard !isPerformingBiometricAuth else { return false }
        isPerformingBiometricAuth = true
        defer { isPerformingBiometricAuth = false }

        let success = await BiometricAuth.authenticate(reason: "Desbloquea Memora para acceder a tu biblioteca")
        if success {
            appLocked = false
        }
        return success
    }

    func unlockAppWithPassword(_ password: String) throws {
        guard let account else { throw MemoraError.noAccount }
        let plain = try MemoraCrypto.open(
            account.wrappedRootKey,
            key: MemoraCrypto.passwordKey(password, salt: account.passwordSalt),
            context: "memora:account:\(account.id):password"
        )
        guard plain.count == 32 else { throw MemoraError.corruptData }
        appLocked = false
    }

    func lockApp() {
        guard !isPerformingBiometricAuth else { return }
        if appBiometricsEnabled {
            appLocked = true
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

    func updateProfilePhoto(data: Data) throws {
        guard var record = account else { throw MemoraError.noAccount }
        record.profilePhotoData = data
        account = record
        try saveAccount()
    }

    func removeProfilePhoto() throws {
        guard var record = account else { throw MemoraError.noAccount }
        record.profilePhotoData = nil
        account = record
        try saveAccount()
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

    func albums(in section: MemorySection) -> [MemoryAlbum] {
        library.albums.filter { $0.sectionID == section.id }
    }

    func assets(in section: MemorySection) -> [MemoryAsset] {
        let sectionAlbumIDs = Set(albums(in: section).map(\.id))
        guard !sectionAlbumIDs.isEmpty else { return [] }
        return activeAssets.filter { asset in
            asset.albumIDs.contains(where: { sectionAlbumIDs.contains($0) })
        }
    }

    func renameSection(_ id: UUID, newName: String) throws {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = library.sections.firstIndex(where: { $0.id == id }) else { return }
        library.sections[index].name = trimmed
        try saveLibrary()
    }

    func deleteSection(_ id: UUID) throws {
        library.sections.removeAll { $0.id == id }
        for index in library.albums.indices {
            if library.albums[index].sectionID == id {
                library.albums[index].sectionID = nil
            }
        }
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

    func deletePerson(_ personID: UUID) throws {
        library.people.removeAll { $0.id == personID }
        for idx in library.assets.indices {
            library.assets[idx].personIDs.removeAll { $0 == personID }
        }
        for fIdx in library.detectedFaces.indices {
            if library.detectedFaces[fIdx].personID == personID {
                library.detectedFaces[fIdx].personID = nil
                library.detectedFaces[fIdx].reviewStatus = .unassigned
            }
        }
        recomputeClusters()
        try saveLibrary()
    }

    func mergePeople(source: UUID, into target: UUID) throws {
        guard source != target,
              let sourcePerson = library.people.first(where: { $0.id == source }),
              let targetIdx = library.people.firstIndex(where: { $0.id == target }) else { return }

        library.assets = library.assets.map { asset in
            var result = asset
            result.personIDs = Array(Set(asset.personIDs.map { $0 == source ? target : $0 }))
            return result
        }

        // Transferir todos los rostros detectados y exemplars al perfil destino
        for fIdx in library.detectedFaces.indices {
            if library.detectedFaces[fIdx].personID == source {
                library.detectedFaces[fIdx].personID = target
            }
        }
        for exID in sourcePerson.exemplarFaceIDs {
            if !library.people[targetIdx].exemplarFaceIDs.contains(exID) {
                library.people[targetIdx].exemplarFaceIDs.append(exID)
            }
        }
        for revID in sourcePerson.reviewCandidateAssetIDs {
            if !library.people[targetIdx].reviewCandidateAssetIDs.contains(revID) {
                library.people[targetIdx].reviewCandidateAssetIDs.append(revID)
            }
        }
        if library.people[targetIdx].coverAssetID == nil {
            library.people[targetIdx].coverAssetID = sourcePerson.coverAssetID
        }

        library.people.removeAll { $0.id == source }
        updatePersonPrototype(personID: target)
        reclassifyAllFacesForPerson(personID: target)

        if privateLibrary != nil {
            privateLibrary?.assets = privateLibrary!.assets.map { asset in
                var result = asset
                result.personIDs = Array(Set(asset.personIDs.map { $0 == source ? target : $0 }))
                return result
            }
            try? saveVault()
        }
        try saveLibrary()
    }

    func toggleFavorite(_ id: UUID) throws {
        guard let index = library.assets.firstIndex(where: { $0.id == id }) else { return }
        library.assets[index].favorite.toggle()
        try saveLibrary()
    }

    func add(_ assetID: UUID, to albumID: UUID) throws {
        try addAssets([assetID], toAlbum: albumID)
    }

    func addAssets(_ assetIDs: [UUID], toAlbum albumID: UUID) throws {
        guard library.albums.contains(where: { $0.id == albumID }) else { return }
        for assetID in assetIDs {
            if let index = library.assets.firstIndex(where: { $0.id == assetID }) {
                if !library.assets[index].albumIDs.contains(albumID) {
                    library.assets[index].albumIDs.append(albumID)
                }
            }
        }
        try saveLibrary()
    }

    func removeAsset(_ assetID: UUID, fromAlbum albumID: UUID) throws {
        guard let index = library.assets.firstIndex(where: { $0.id == assetID }) else { return }
        library.assets[index].albumIDs.removeAll { $0 == albumID }
        try saveLibrary()
    }

    func assignAlbum(_ albumID: UUID, toSection sectionID: UUID?) throws {
        guard let index = library.albums.firstIndex(where: { $0.id == albumID }) else { return }
        library.albums[index].sectionID = sectionID
        try saveLibrary()
    }

    func addAssets(_ assetIDs: [UUID], toSection sectionID: UUID) throws {
        guard let section = library.sections.first(where: { $0.id == sectionID }) else { return }
        var targetAlbum = library.albums.first(where: { $0.sectionID == sectionID })
        if targetAlbum == nil {
            let newAlbum = MemoryAlbum(id: UUID(), name: "General · \(section.name)", sectionID: sectionID, createdAt: .now)
            library.albums.append(newAlbum)
            targetAlbum = newAlbum
        }
        if let targetAlbum {
            try addAssets(assetIDs, toAlbum: targetAlbum.id)
        }
    }

    func updateAssetMetadata(id: UUID, location: String, tags: [String], capturedAt: Date? = nil) throws {
        guard let index = library.assets.firstIndex(where: { $0.id == id }) else { return }
        library.assets[index].location = location.trimmingCharacters(in: .whitespaces)
        library.assets[index].tags = tags.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if let capturedAt {
            library.assets[index].capturedAt = capturedAt
        }
        try saveLibrary()
    }

    // MARK: - Catálogo Facial, Recortes y Migración Automática
    var facesCatalog: [UUID: DetectedFace] {
        Dictionary(uniqueKeysWithValues: library.detectedFaces.map { ($0.id, $0) })
    }

    var activeDetectedFaces: [DetectedFace] {
        let activeIDs = Set(activeAssets.map(\.id))
        return library.detectedFaces.filter { activeIDs.contains($0.assetID) }
    }

    var activeUnassignedFaces: [DetectedFace] {
        activeDetectedFaces.filter { $0.personID == nil && $0.reviewStatus == .unassigned }
    }

    var activeSuggestedFaces: [DetectedFace] {
        activeDetectedFaces.filter { $0.reviewStatus == .suggested && $0.personID != nil }
    }

    func faceCropImage(for face: DetectedFace) -> UIImage? {
        if let cached = faceCropCache[face.id] {
            return cached
        }
        guard let asset = library.assets.first(where: { $0.id == face.assetID }),
              let thumb = thumbnail(for: asset) else {
            return nil
        }
        if let cropped = FaceEngine.cropFaceForDisplay(from: thumb, bbox: face.bbox) {
            faceCropCache[face.id] = cropped
            return cropped
        }
        return thumb
    }

    /// Limpia rostros huérfanos, elimina sujetos duplicados en una misma foto y migra vectores antiguos a 256D
    func migrateAndCleanFacesIfNeeded() async {
        guard authenticated else { return }
        let activeIDs = Set(activeAssets.map(\.id))
        var modified = false

        // 1. Eliminar rostros de archivos borrados
        let beforeCount = library.detectedFaces.count
        library.detectedFaces.removeAll { !activeIDs.contains($0.assetID) }
        if library.detectedFaces.count != beforeCount {
            modified = true
        }

        // 2. Eliminar detecciones superpuestas (sujetos duplicados en la misma foto)
        let groupedByAsset = Dictionary(grouping: library.detectedFaces, by: \.assetID)
        var cleanedFaces: [DetectedFace] = []
        for (_, assetFaces) in groupedByAsset {
            let sorted = assetFaces.sorted { a, b in
                let aConfirmed = (a.reviewStatus == .confirmed && a.personID != nil) ? 1 : 0
                let bConfirmed = (b.reviewStatus == .confirmed && b.personID != nil) ? 1 : 0
                if aConfirmed != bConfirmed { return aConfirmed > bConfirmed }
                return (a.quality * a.confidence) > (b.quality * b.confidence)
            }
            var kept: [DetectedFace] = []
            for candidate in sorted {
                guard candidate.quality >= FaceEngine.recognitionGateMinimum else {
                    modified = true
                    continue
                }
                let overlaps = kept.contains { existing in
                    FaceEngine.intersectionOverUnion(candidate.bbox, existing.bbox) > 0.30
                }
                if !overlaps {
                    kept.append(candidate)
                } else {
                    modified = true
                }
            }
            cleanedFaces.append(contentsOf: kept)
        }
        if modified {
            library.detectedFaces = cleanedFaces
        }

        // 3. Reanalizar fotos con embeddings de dimensión antigua (!= 256)
        let assetsNeedingUpgrade = activeAssets.filter { asset in
            guard asset.kind == .photo else { return false }
            let faces = library.detectedFaces.filter { $0.assetID == asset.id }
            return faces.contains { $0.embedding.count != FaceEngine.embeddingDimension }
        }

        for asset in assetsNeedingUpgrade {
            if let img = thumbnail(for: asset) {
                await processFacesForAsset(asset.id, image: img, saveAndCluster: false)
                modified = true
            }
        }

        if modified {
            for person in library.people {
                updatePersonPrototype(personID: person.id)
            }
            for person in library.people {
                reclassifyAllFacesForPerson(personID: person.id)
            }
            recomputeClusters()
            try? saveLibrary()
        }
    }

    func processFacesForAsset(_ assetID: UUID, image: UIImage, saveAndCluster: Bool = true) async {
        let newFaces = await FaceEngine.analyzeImage(image, assetID: assetID)

        // Conservar asignaciones confirmadas previas de esta foto para no perder etiquetas manuales
        let previousConfirmed = library.detectedFaces.filter {
            $0.assetID == assetID && $0.reviewStatus == .confirmed && $0.personID != nil
        }
        // Si la foto ya tenía una persona asignada directamente y hay 1 solo rostro, vincularlo
        let assetAssignedPersonIDs = library.assets.first(where: { $0.id == assetID })?.personIDs ?? []

        // Eliminar TODOS los rostros previos de este assetID para jamás duplicar sujetos en la misma foto
        let removedIDs = Set(library.detectedFaces.filter { $0.assetID == assetID }.map(\.id))
        for rID in removedIDs {
            faceCropCache[rID] = nil
        }
        library.detectedFaces.removeAll { $0.assetID == assetID }

        guard !newFaces.isEmpty else {
            if saveAndCluster {
                recomputeClusters()
                try? saveLibrary()
            }
            return
        }

        let resolved = FaceEngine.classifyAndResolveFaces(newFaces, against: library.people, facesCatalog: facesCatalog)

        for (idx, item) in resolved.enumerated() {
            var faceToAdd = item.face

            // Verificar si coincide espacialmente con un rostro previamente confirmado en esta foto
            if let prev = previousConfirmed.first(where: { FaceEngine.intersectionOverUnion($0.bbox, faceToAdd.bbox) > 0.28 }),
               let prevPersonID = prev.personID {
                faceToAdd.personID = prevPersonID
                faceToAdd.confidence = 1.0
                faceToAdd.reviewStatus = .confirmed
                try? assign(assetID, to: prevPersonID, saveImmediately: false)
                if let pIdx = library.people.firstIndex(where: { $0.id == prevPersonID }) {
                    library.people[pIdx].exemplarFaceIDs.removeAll { removedIDs.contains($0) }
                    library.people[pIdx].exemplarFaceIDs.append(faceToAdd.id)
                }
            } else if resolved.count == 1 && assetAssignedPersonIDs.count == 1,
                      let explicitPersonID = assetAssignedPersonIDs.first {
                faceToAdd.personID = explicitPersonID
                faceToAdd.confidence = 1.0
                faceToAdd.reviewStatus = .confirmed
                if let pIdx = library.people.firstIndex(where: { $0.id == explicitPersonID }) {
                    if !library.people[pIdx].exemplarFaceIDs.contains(faceToAdd.id) {
                        library.people[pIdx].exemplarFaceIDs.append(faceToAdd.id)
                    }
                }
            } else if let matchedPersonID = item.personID {
                if item.zone == .high {
                    faceToAdd.personID = matchedPersonID
                    faceToAdd.confidence = item.confidence
                    faceToAdd.reviewStatus = .confirmed
                    try? assign(assetID, to: matchedPersonID, saveImmediately: false)

                    if let person = library.people.first(where: { $0.id == matchedPersonID }),
                       FaceEngine.shouldEnrollFace(faceToAdd, for: person, facesCatalog: facesCatalog) {
                        if let pIdx = library.people.firstIndex(where: { $0.id == matchedPersonID }) {
                            library.people[pIdx].exemplarFaceIDs.append(faceToAdd.id)
                        }
                    }
                } else if item.zone == .review {
                    faceToAdd.personID = matchedPersonID
                    faceToAdd.confidence = item.confidence
                    faceToAdd.reviewStatus = .suggested
                    if let pIdx = library.people.firstIndex(where: { $0.id == matchedPersonID }) {
                        if !library.people[pIdx].reviewCandidateAssetIDs.contains(assetID) {
                            library.people[pIdx].reviewCandidateAssetIDs.append(assetID)
                        }
                    }
                }
            } else if idx == 0, assetAssignedPersonIDs.count == 1, let explicitPersonID = assetAssignedPersonIDs.first {
                faceToAdd.personID = explicitPersonID
                faceToAdd.confidence = 0.95
                faceToAdd.reviewStatus = .confirmed
            }

            library.detectedFaces.append(faceToAdd)
        }

        // Actualizar prototipos de personas afectadas
        for p in library.people {
            updatePersonPrototype(personID: p.id)
        }

        // Automatización inteligente: si la foto no tiene álbum y se reconoció una cara que está en álbumes, integrarla
        if autoAlbumByFaceEnabled {
            _ = autoIntegrateAssetIntoAlbumsByFace(assetID, saveImmediately: false)
        }

        if saveAndCluster {
            recomputeClusters()
            try? saveLibrary()
        }
    }

    // MARK: - Automatización Inteligente de Álbumes por Reconocimiento Facial
    /// Integra automáticamente un archivo sin álbum en los álbumes donde aparezcan las mismas caras o personas
    @discardableResult
    func autoIntegrateAssetIntoAlbumsByFace(_ assetID: UUID, targetAlbumID: UUID? = nil, saveImmediately: Bool = true) -> Int {
        guard let assetIdx = library.assets.firstIndex(where: { $0.id == assetID }),
              library.assets[assetIdx].deletedAt == nil else { return 0 }

        // Si es automático global, solo organizar elementos que están sin álbum (o hacia un targetAlbumID específico)
        if targetAlbumID == nil && !library.assets[assetIdx].albumIDs.isEmpty {
            return 0
        }

        let assetFaces = library.detectedFaces.filter { $0.assetID == assetID }
        let assetPersonIDs = Set(library.assets[assetIdx].personIDs).union(assetFaces.compactMap(\.personID))
        guard !assetFaces.isEmpty || !assetPersonIDs.isEmpty else { return 0 }

        let candidateAlbums: [MemoryAlbum] = {
            if let targetAlbumID {
                return library.albums.filter { $0.id == targetAlbumID }
            }
            return library.albums
        }()

        var addedCount = 0

        for album in candidateAlbums {
            guard !library.assets[assetIdx].albumIDs.contains(album.id) else { continue }

            let albumAssets = activeAssets.filter { $0.albumIDs.contains(album.id) && $0.id != assetID }
            guard !albumAssets.isEmpty else { continue }

            let albumAssetIDs = Set(albumAssets.map(\.id))
            let albumPersonIDs = Set(albumAssets.flatMap(\.personIDs))
                .union(library.detectedFaces.filter { albumAssetIDs.contains($0.assetID) }.compactMap(\.personID))

            // Criterio 1: Coincidencia por Persona ya identificada dentro del álbum
            var matchesAlbum = !assetPersonIDs.isDisjoint(with: albumPersonIDs)

            // Criterio 2: Coincidencia directa de embeddings faciales con las caras que están dentro del álbum
            // (Funciona incluso sin haber creado personas manualmente)
            if !matchesAlbum && !assetFaces.isEmpty {
                let albumFaces = library.detectedFaces.filter {
                    albumAssetIDs.contains($0.assetID) && !$0.embedding.isEmpty
                }
                if !albumFaces.isEmpty {
                    let albumProto = FaceEngine.computePrototype(from: albumFaces.map(\.embedding))
                    for face in assetFaces {
                        if let proto = albumProto, FaceEngine.cosineSimilarity(face.embedding, proto) >= FaceEngine.thresholdAccept {
                            matchesAlbum = true
                            break
                        }
                        let maxDirect = albumFaces.prefix(25).map { FaceEngine.cosineSimilarity(face.embedding, $0.embedding) }.max() ?? 0.0
                        if maxDirect >= FaceEngine.thresholdAccept {
                            matchesAlbum = true
                            break
                        }
                    }
                }
            }

            if matchesAlbum {
                library.assets[assetIdx].albumIDs.append(album.id)
                addedCount += 1
            }
        }

        if addedCount > 0 && saveImmediately {
            try? saveLibrary()
        }
        return addedCount
    }

    /// Escanea fotos sin álbum (o candidatas para un álbum específico), detecta caras si falta y las integra automáticamente
    @discardableResult
    func autoOrganizeUnalbumedAssetsByFaces(targetAlbumID: UUID? = nil) async -> Int {
        busy = true
        defer { busy = false }

        // 1. Asegurar que todas las fotos activas tengan rostros analizados con el motor actual
        for asset in activeAssets where asset.kind == .photo {
            let existingFaces = library.detectedFaces.filter { $0.assetID == asset.id }
            let needsAnalysis = existingFaces.isEmpty || existingFaces.contains { $0.embedding.count != FaceEngine.embeddingDimension }
            if needsAnalysis, let img = thumbnail(for: asset) {
                await processFacesForAsset(asset.id, image: img, saveAndCluster: false)
            }
        }

        // 2. Propagar autoconocimiento de todas las personas conocidas
        for person in library.people {
            updatePersonPrototype(personID: person.id)
            reclassifyAllFacesForPerson(personID: person.id)
        }

        // 3. Evaluar candidatas para integrar en álbumes
        let candidates: [MemoryAsset] = {
            if let targetAlbumID {
                return activeAssets.filter { !$0.albumIDs.contains(targetAlbumID) }
            }
            return activeAssets.filter { $0.albumIDs.isEmpty }
        }()

        var integratedAssets = 0
        for candidate in candidates {
            let count = autoIntegrateAssetIntoAlbumsByFace(candidate.id, targetAlbumID: targetAlbumID, saveImmediately: false)
            if count > 0 {
                integratedAssets += 1
            }
        }

        recomputeClusters()
        try? saveLibrary()

        if integratedAssets > 0 {
            notice = "Automatización inteligente: \(integratedAssets) recuerdo\(integratedAssets == 1 ? "" : "s") integrado\(integratedAssets == 1 ? "" : "s") en álbumes por reconocimiento facial."
        } else {
            notice = "Análisis completado. No se encontraron nuevas coincidencias faciales para integrar en álbumes."
        }
        return integratedAssets
    }

    // MARK: - Autoconocimiento y Gestión Masiva de Personas
    func confirmFaceReview(faceID: UUID, personID: UUID) throws {
        guard let fIdx = library.detectedFaces.firstIndex(where: { $0.id == faceID }),
              let pIdx = library.people.firstIndex(where: { $0.id == personID }) else { return }
        library.detectedFaces[fIdx].personID = personID
        library.detectedFaces[fIdx].confidence = 1.0
        library.detectedFaces[fIdx].reviewStatus = .confirmed
        let assetID = library.detectedFaces[fIdx].assetID
        try assign(assetID, to: personID, saveImmediately: false)
        library.people[pIdx].reviewCandidateAssetIDs.removeAll { $0 == assetID }

        if !library.people[pIdx].exemplarFaceIDs.contains(faceID) {
            library.people[pIdx].exemplarFaceIDs.append(faceID)
        }
        if library.people[pIdx].coverAssetID == nil {
            library.people[pIdx].coverAssetID = assetID
        }

        // Autoconocimiento en cascada: aprender de esta confirmación y buscar más rostros iguales
        updatePersonPrototype(personID: personID)
        reclassifyAllFacesForPerson(personID: personID)
        if autoAlbumByFaceEnabled {
            _ = autoIntegrateAssetIntoAlbumsByFace(assetID, saveImmediately: false)
        }
        recomputeClusters()
        try saveLibrary()
    }

    /// Confirma de forma masiva todas las sugerencias pendientes (de una persona o de todas)
    @discardableResult
    func confirmAllSuggestedFaces(forPersonID: UUID? = nil) throws -> Int {
        var confirmedCount = 0
        var affectedPersons = Set<UUID>()

        for fIdx in library.detectedFaces.indices {
            let face = library.detectedFaces[fIdx]
            guard face.reviewStatus == .suggested, let pID = face.personID else { continue }
            if let filterID = forPersonID, pID != filterID { continue }

            library.detectedFaces[fIdx].reviewStatus = .confirmed
            library.detectedFaces[fIdx].confidence = 1.0
            try? assign(face.assetID, to: pID, saveImmediately: false)

            if let pIdx = library.people.firstIndex(where: { $0.id == pID }) {
                library.people[pIdx].reviewCandidateAssetIDs.removeAll { $0 == face.assetID }
                if !library.people[pIdx].exemplarFaceIDs.contains(face.id) {
                    library.people[pIdx].exemplarFaceIDs.append(face.id)
                }
            }
            affectedPersons.insert(pID)
            confirmedCount += 1
        }

        for pID in affectedPersons {
            updatePersonPrototype(personID: pID)
            reclassifyAllFacesForPerson(personID: pID)
        }
        recomputeClusters()
        try saveLibrary()
        return confirmedCount
    }

    func rejectFaceSuggestion(faceID: UUID) throws {
        guard let fIdx = library.detectedFaces.firstIndex(where: { $0.id == faceID }) else { return }
        let oldPersonID = library.detectedFaces[fIdx].personID
        let assetID = library.detectedFaces[fIdx].assetID
        library.detectedFaces[fIdx].personID = nil
        library.detectedFaces[fIdx].reviewStatus = .unassigned
        library.detectedFaces[fIdx].confidence = 0.0

        if let oldPersonID, let pIdx = library.people.firstIndex(where: { $0.id == oldPersonID }) {
            library.people[pIdx].reviewCandidateAssetIDs.removeAll { $0 == assetID }
        }
        recomputeClusters()
        try saveLibrary()
    }

    func correctFace(faceID: UUID, correctPersonID: UUID) throws {
        guard let fIdx = library.detectedFaces.firstIndex(where: { $0.id == faceID }),
              let pIdx = library.people.firstIndex(where: { $0.id == correctPersonID }) else { return }

        let oldPersonID = library.detectedFaces[fIdx].personID
        library.detectedFaces[fIdx].personID = correctPersonID
        library.detectedFaces[fIdx].confidence = 1.0
        library.detectedFaces[fIdx].reviewStatus = .confirmed
        let assetID = library.detectedFaces[fIdx].assetID

        try assign(assetID, to: correctPersonID, saveImmediately: false)

        if let oldPersonID, let oldIdx = library.people.firstIndex(where: { $0.id == oldPersonID }) {
            library.people[oldIdx].exemplarFaceIDs.removeAll { $0 == faceID }
            library.people[oldIdx].reviewCandidateAssetIDs.removeAll { $0 == assetID }
            updatePersonPrototype(personID: oldPersonID)
        }

        if !library.people[pIdx].exemplarFaceIDs.contains(faceID) {
            library.people[pIdx].exemplarFaceIDs.append(faceID)
        }
        updatePersonPrototype(personID: correctPersonID)
        reclassifyAllFacesForPerson(personID: correctPersonID)
        recomputeClusters()
        try saveLibrary()
    }

    func updatePersonPrototype(personID: UUID) {
        guard let pIdx = library.people.firstIndex(where: { $0.id == personID }) else { return }
        let catalog = facesCatalog
        var embeddings: [[Float]] = library.people[pIdx].exemplarFaceIDs.compactMap { catalog[$0]?.embedding }
        if embeddings.isEmpty {
            embeddings = library.detectedFaces
                .filter { $0.personID == personID && $0.reviewStatus == .confirmed }
                .map(\.embedding)
        }
        library.people[pIdx].prototype = FaceEngine.computePrototype(from: embeddings)
        library.people[pIdx].prototypes = FaceEngine.computeMultiPrototypes(from: embeddings)
    }

    func nameCluster(_ clusterID: UUID, name: String) throws {
        guard let cluster = library.clusters.first(where: { $0.id == clusterID }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Si ya existe una persona con ese mismo nombre, fusionar en esa persona directamente
        if let existingPerson = library.people.first(where: { $0.name.lowercased() == trimmed.lowercased() }) {
            try assignClusterToExistingPerson(clusterID, personID: existingPerson.id)
            return
        }

        let repFace = library.detectedFaces.first(where: { $0.id == cluster.representativeFaceID })
        let person = MemoryPerson(
            id: UUID(),
            name: trimmed,
            coverAssetID: repFace?.assetID,
            exemplarFaceIDs: cluster.faceIDs
        )
        library.people.append(person)

        for faceID in cluster.faceIDs {
            if let fIdx = library.detectedFaces.firstIndex(where: { $0.id == faceID }) {
                library.detectedFaces[fIdx].personID = person.id
                library.detectedFaces[fIdx].confidence = 1.0
                library.detectedFaces[fIdx].reviewStatus = .confirmed
                let assetID = library.detectedFaces[fIdx].assetID
                try? assign(assetID, to: person.id, saveImmediately: false)
                if autoAlbumByFaceEnabled {
                    _ = autoIntegrateAssetIntoAlbumsByFace(assetID, saveImmediately: false)
                }
            }
        }

        updatePersonPrototype(personID: person.id)
        reclassifyAllFacesForPerson(personID: person.id)
        recomputeClusters()
        try saveLibrary()
    }

    func assignClusterToExistingPerson(_ clusterID: UUID, personID: UUID) throws {
        guard let cluster = library.clusters.first(where: { $0.id == clusterID }) else { return }
        try batchAssignFaces(cluster.faceIDs, toPersonID: personID)
    }

    /// Asigna un lote masivo de rostros seleccionados a una persona existente o nueva y activa el autoconocimiento
    func batchAssignFaces(_ faceIDs: [UUID], toPersonID: UUID?, newPersonName: String? = nil) throws {
        guard !faceIDs.isEmpty else { return }
        var finalPersonID = toPersonID

        if let newPersonName {
            let trimmed = newPersonName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                if let existing = library.people.first(where: { $0.name.lowercased() == trimmed.lowercased() }) {
                    finalPersonID = existing.id
                } else {
                    let firstAssetID = library.detectedFaces.first(where: { faceIDs.contains($0.id) })?.assetID
                    let newPerson = MemoryPerson(
                        id: UUID(),
                        name: trimmed,
                        coverAssetID: firstAssetID,
                        exemplarFaceIDs: faceIDs
                    )
                    library.people.append(newPerson)
                    finalPersonID = newPerson.id
                }
            }
        }

        guard let targetID = finalPersonID,
              let pIdx = library.people.firstIndex(where: { $0.id == targetID }) else { return }

        let faceSet = Set(faceIDs)
        for fIdx in library.detectedFaces.indices where faceSet.contains(library.detectedFaces[fIdx].id) {
            let face = library.detectedFaces[fIdx]
            library.detectedFaces[fIdx].personID = targetID
            library.detectedFaces[fIdx].confidence = 1.0
            library.detectedFaces[fIdx].reviewStatus = .confirmed
            try? assign(face.assetID, to: targetID, saveImmediately: false)

            if !library.people[pIdx].exemplarFaceIDs.contains(face.id) {
                library.people[pIdx].exemplarFaceIDs.append(face.id)
            }
            library.people[pIdx].reviewCandidateAssetIDs.removeAll { $0 == face.assetID }
            if library.people[pIdx].coverAssetID == nil {
                library.people[pIdx].coverAssetID = face.assetID
            }
            if autoAlbumByFaceEnabled {
                _ = autoIntegrateAssetIntoAlbumsByFace(face.assetID, saveImmediately: false)
            }
        }

        // Autoconocimiento: actualizar prototipo y reclasificar toda la biblioteca
        updatePersonPrototype(personID: targetID)
        reclassifyAllFacesForPerson(personID: targetID)
        recomputeClusters()
        try saveLibrary()
    }

    /// Elimina detecciones falsas o irrelevantes seleccionadas por el usuario
    func deleteFalseFaceDetections(_ faceIDs: [UUID]) throws {
        let removeSet = Set(faceIDs)
        for id in removeSet {
            faceCropCache[id] = nil
        }
        library.detectedFaces.removeAll { removeSet.contains($0.id) }
        for pIdx in library.people.indices {
            library.people[pIdx].exemplarFaceIDs.removeAll { removeSet.contains($0) }
        }
        recomputeClusters()
        try saveLibrary()
    }

    /// Encuentra automáticamente todos los rostros sin identificar similares a un rostro semilla
    func similarUnassignedFaces(to seedFaceID: UUID, threshold: Double = 0.50) -> [UUID] {
        guard let seed = library.detectedFaces.first(where: { $0.id == seedFaceID }) else {
            return [seedFaceID]
        }
        return activeUnassignedFaces.compactMap { candidate in
            if candidate.id == seedFaceID { return candidate.id }
            let sim = FaceEngine.cosineSimilarity(seed.embedding, candidate.embedding)
            return sim >= threshold ? candidate.id : nil
        }
    }

    /// Ejecuta un ciclo completo de autoconocimiento en toda la biblioteca
    func runFullFaceAutoKnowledge() async {
        busy = true
        defer { busy = false }

        await migrateAndCleanFacesIfNeeded()

        // Analizar cualquier foto que aún no tenga rostros procesados
        for asset in activeAssets where asset.kind == .photo {
            let faces = library.detectedFaces.filter { $0.assetID == asset.id }
            if faces.isEmpty, let img = thumbnail(for: asset) {
                await processFacesForAsset(asset.id, image: img, saveAndCluster: false)
            }
        }

        for person in library.people {
            updatePersonPrototype(personID: person.id)
        }
        for person in library.people {
            reclassifyAllFacesForPerson(personID: person.id)
        }

        var autoIntegrated = 0
        if autoAlbumByFaceEnabled {
            for asset in unalbumedPhotoAssets {
                if autoIntegrateAssetIntoAlbumsByFace(asset.id, saveImmediately: false) > 0 {
                    autoIntegrated += 1
                }
            }
        }

        recomputeClusters()
        try? saveLibrary()

        if autoIntegrated > 0 {
            notice = "Autoconocimiento completado: rostros agrupados y \(autoIntegrated) foto\(autoIntegrated == 1 ? "" : "s") integrada\(autoIntegrated == 1 ? "" : "s") en álbumes."
        } else {
            notice = "Autoconocimiento y limpieza de rostros completados."
        }
    }

    func facesInAsset(_ assetID: UUID) -> [DetectedFace] {
        library.detectedFaces.filter { $0.assetID == assetID }
    }

    func albumsForPerson(personID: UUID) -> [MemoryAlbum] {
        let personAssets = activeAssets.filter { $0.personIDs.contains(personID) }
        return library.albums.filter { album in
            personAssets.contains { $0.albumIDs.contains(album.id) }
        }
    }

    func sectionsForPerson(personID: UUID) -> [MemorySection] {
        let personAlbums = albumsForPerson(personID: personID)
        let sectionIDs = Set(personAlbums.compactMap(\.sectionID))
        return library.sections.filter { sectionIDs.contains($0.id) }
    }

    func tagFaceInAsset(
        faceID: UUID,
        assetID: UUID,
        personID: UUID?,
        newPersonName: String? = nil,
        learnAsExemplar: Bool = true
    ) throws {
        var targetPersonID = personID

        if let newPersonName, !newPersonName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let trimmed = newPersonName.trimmingCharacters(in: .whitespacesAndNewlines)
            if let existing = library.people.first(where: { $0.name.lowercased() == trimmed.lowercased() }) {
                targetPersonID = existing.id
            } else {
                let newPerson = MemoryPerson(
                    id: UUID(),
                    name: trimmed,
                    coverAssetID: assetID,
                    exemplarFaceIDs: [faceID]
                )
                library.people.append(newPerson)
                targetPersonID = newPerson.id
            }
        }

        guard let finalPersonID = targetPersonID,
              let pIdx = library.people.firstIndex(where: { $0.id == finalPersonID }) else {
            if let fIdx = library.detectedFaces.firstIndex(where: { $0.id == faceID }) {
                let oldPersonID = library.detectedFaces[fIdx].personID
                library.detectedFaces[fIdx].personID = nil
                library.detectedFaces[fIdx].reviewStatus = .unassigned
                if let oldPersonID, let oldPIdx = library.people.firstIndex(where: { $0.id == oldPersonID }) {
                    library.people[oldPIdx].exemplarFaceIDs.removeAll { $0 == faceID }
                    updatePersonPrototype(personID: oldPersonID)
                }
            }
            recomputeClusters()
            try saveLibrary()
            return
        }

        if let fIdx = library.detectedFaces.firstIndex(where: { $0.id == faceID }) {
            let oldPersonID = library.detectedFaces[fIdx].personID
            library.detectedFaces[fIdx].personID = finalPersonID
            library.detectedFaces[fIdx].confidence = 1.0
            library.detectedFaces[fIdx].reviewStatus = .confirmed
            if let oldPersonID, oldPersonID != finalPersonID,
               let oldPIdx = library.people.firstIndex(where: { $0.id == oldPersonID }) {
                library.people[oldPIdx].exemplarFaceIDs.removeAll { $0 == faceID }
                updatePersonPrototype(personID: oldPersonID)
            }
        }

        try assign(assetID, to: finalPersonID, saveImmediately: false)

        if learnAsExemplar {
            if !library.people[pIdx].exemplarFaceIDs.contains(faceID) {
                library.people[pIdx].exemplarFaceIDs.append(faceID)
            }
            updatePersonPrototype(personID: finalPersonID)
            reclassifyAllFacesForPerson(personID: finalPersonID)
            if autoAlbumByFaceEnabled {
                _ = autoIntegrateAssetIntoAlbumsByFace(assetID, saveImmediately: false)
            }
        }

        recomputeClusters()
        try saveLibrary()
    }

    func reclassifyAllFacesForPerson(personID: UUID) {
        guard library.people.contains(where: { $0.id == personID }) else { return }
        let catalog = facesCatalog

        for fIdx in library.detectedFaces.indices {
            let face = library.detectedFaces[fIdx]
            // No sobrescribir rostros ya confirmados manualmente para otra persona
            guard face.reviewStatus != .confirmed || face.personID == nil else { continue }
            guard face.quality >= FaceEngine.recognitionGateMinimum else { continue }

            let classification = FaceEngine.classifyFace(face, against: library.people, facesCatalog: catalog)
            guard let matchedID = classification.personID else { continue }

            if classification.zone == .high {
                library.detectedFaces[fIdx].personID = matchedID
                library.detectedFaces[fIdx].confidence = classification.confidence
                library.detectedFaces[fIdx].reviewStatus = .confirmed
                try? assign(face.assetID, to: matchedID, saveImmediately: false)
                if autoAlbumByFaceEnabled {
                    _ = autoIntegrateAssetIntoAlbumsByFace(face.assetID, saveImmediately: false)
                }
            } else if classification.zone == .review {
                library.detectedFaces[fIdx].personID = matchedID
                library.detectedFaces[fIdx].confidence = classification.confidence
                library.detectedFaces[fIdx].reviewStatus = .suggested
                if let pIdx = library.people.firstIndex(where: { $0.id == matchedID }) {
                    if !library.people[pIdx].reviewCandidateAssetIDs.contains(face.assetID) {
                        library.people[pIdx].reviewCandidateAssetIDs.append(face.assetID)
                    }
                }
            }
        }
    }

    func recomputeClusters() {
        let unassigned = activeUnassignedFaces
        library.clusters = FaceEngine.clusterFaces(unassignedFaces: unassigned)
    }

    func searchPeopleByPhoto(image: UIImage) async -> [FaceMatchResult] {
        return await FaceEngine.searchPeopleByPhoto(
            queryImage: image,
            people: library.people,
            albums: library.albums,
            sections: library.sections,
            assets: activeAssets,
            facesCatalog: facesCatalog
        )
    }

    func assign(_ assetID: UUID, to personID: UUID, saveImmediately: Bool = true) throws {
        guard let pIdx = library.people.firstIndex(where: { $0.id == personID }),
              let index = library.assets.firstIndex(where: { $0.id == assetID }) else { return }
        if !library.assets[index].personIDs.contains(personID) {
            library.assets[index].personIDs.append(personID)
        }
        if library.people[pIdx].coverAssetID == nil {
            library.people[pIdx].coverAssetID = assetID
        }
        // Si la foto tiene un único rostro detectado y aún no tenía persona, aprenderlo automáticamente
        let assetFaces = library.detectedFaces.indices.filter { library.detectedFaces[$0].assetID == assetID }
        if assetFaces.count == 1, let fIdx = assetFaces.first, library.detectedFaces[fIdx].personID == nil {
            let fID = library.detectedFaces[fIdx].id
            library.detectedFaces[fIdx].personID = personID
            library.detectedFaces[fIdx].confidence = 1.0
            library.detectedFaces[fIdx].reviewStatus = .confirmed
            if !library.people[pIdx].exemplarFaceIDs.contains(fID) {
                library.people[pIdx].exemplarFaceIDs.append(fID)
            }
            if saveImmediately {
                updatePersonPrototype(personID: personID)
                reclassifyAllFacesForPerson(personID: personID)
                recomputeClusters()
            }
        }
        if saveImmediately {
            try saveLibrary()
        }
    }

    func moveToTrash(_ id: UUID) throws {
        guard let index = library.assets.firstIndex(where: { $0.id == id }) else { return }
        library.assets[index].deletedAt = .now
        recomputeClusters()
        try saveLibrary()
    }

    func restore(_ id: UUID) throws {
        guard let index = library.assets.firstIndex(where: { $0.id == id }) else { return }
        library.assets[index].deletedAt = nil
        recomputeClusters()
        try saveLibrary()
    }

    func deleteForever(_ id: UUID) throws {
        guard let index = library.assets.firstIndex(where: { $0.id == id }) else { return }
        library.assets.remove(at: index)
        let removedFaceIDs = Set(library.detectedFaces.filter { $0.assetID == id }.map(\.id))
        for fID in removedFaceIDs {
            faceCropCache[fID] = nil
        }
        library.detectedFaces.removeAll { $0.assetID == id }
        for pIdx in library.people.indices {
            library.people[pIdx].exemplarFaceIDs.removeAll { removedFaceIDs.contains($0) }
            library.people[pIdx].reviewCandidateAssetIDs.removeAll { $0 == id }
            if library.people[pIdx].coverAssetID == id {
                library.people[pIdx].coverAssetID = nil
            }
        }
        recomputeClusters()
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

    @discardableResult
    func importData(
        _ data: Data,
        name: String,
        mime: String,
        secure: Bool = false,
        targetAlbumID: UUID? = nil,
        targetSectionID: UUID? = nil,
        targetPersonID: UUID? = nil,
        batchMode: Bool = false
    ) throws -> (assetID: UUID, image: UIImage?) {
        guard let account, authenticated else { throw MemoraError.noAccount }
        guard data.count <= fileLimit else { throw MemoraError.fileTooLarge }
        let hash = MemoraCrypto.sha256(data)

        // Si el archivo ya existe en la biblioteca pero el usuario lo está añadiendo dentro de un álbum, sección o persona,
        // asociarlo directamente al álbum/sección/persona en vez de ignorarlo
        if !secure, let existingIdx = library.assets.firstIndex(where: { $0.sha256 == hash }) {
            let existingID = library.assets[existingIdx].id
            var updatedExisting = false
            if library.assets[existingIdx].deletedAt != nil {
                library.assets[existingIdx].deletedAt = nil
                updatedExisting = true
            }
            if let targetAlbumID, !library.assets[existingIdx].albumIDs.contains(targetAlbumID) {
                library.assets[existingIdx].albumIDs.append(targetAlbumID)
                updatedExisting = true
            }
            if let targetSectionID {
                try? addAssets([existingID], toSection: targetSectionID)
                updatedExisting = true
            }
            if let targetPersonID {
                try? assign(existingID, to: targetPersonID, saveImmediately: !batchMode)
                updatedExisting = true
            }
            if updatedExisting {
                if !batchMode { try? saveLibrary() }
                return (existingID, nil)
            }
            throw MemoraError.duplicate
        }

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
            var scaledImage: UIImage? = nil
            if mime.hasPrefix("image/"), let image = UIImage(data: data) {
                let side: CGFloat = 480
                let ratio = min(side / image.size.width, side / image.size.height, 1)
                let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
                let scaled = UIGraphicsImageRenderer(size: size).image { _ in
                    image.draw(in: CGRect(origin: .zero, size: size))
                }
                scaledImage = scaled
                if let jpeg = scaled.jpegData(compressionQuality: 0.78) {
                    try write(MemoraCrypto.seal(
                        jpeg, key: key, context: "memora:account:\(account.id):thumb:\(id)"
                    ), to: filesURL.appendingPathComponent(id.uuidString + ".thumb"))
                    thumbnail = true
                }
            }

            // Resolver álbum destino si se importó desde dentro de un Álbum o de una Sección
            var initialAlbumIDs: [UUID] = []
            if let targetAlbumID {
                initialAlbumIDs.append(targetAlbumID)
            }
            if let targetSectionID, let section = library.sections.first(where: { $0.id == targetSectionID }) {
                var sectionAlbum = library.albums.first(where: { $0.sectionID == targetSectionID })
                if sectionAlbum == nil {
                    let created = MemoryAlbum(id: UUID(), name: "General · \(section.name)", sectionID: targetSectionID, createdAt: .now)
                    library.albums.append(created)
                    sectionAlbum = created
                }
                if let sAlbumID = sectionAlbum?.id, !initialAlbumIDs.contains(sAlbumID) {
                    initialAlbumIDs.append(sAlbumID)
                }
            }

            var initialPersonIDs: [UUID] = []
            if let targetPersonID {
                initialPersonIDs.append(targetPersonID)
            }

            let meta = AssetMetadataExtractor.extract(from: data)
            let asset = MemoryAsset(
                id: id,
                name: name,
                mime: mime,
                kind: .classify(mime),
                size: data.count,
                addedAt: .now,
                capturedAt: meta.date ?? .now,
                sha256: hash,
                wrappedFileKey: envelope,
                albumIDs: initialAlbumIDs,
                personIDs: initialPersonIDs,
                location: meta.location ?? "",
                hasThumbnail: thumbnail,
                cameraModel: meta.camera,
                iso: meta.iso,
                aperture: meta.aperture,
                focalLength: meta.focalLength,
                width: meta.width,
                height: meta.height,
                latitude: meta.lat,
                longitude: meta.lon
            )

            if secure {
                guard privateLibrary != nil else { throw MemoraError.locked }
                privateLibrary?.assets.insert(asset, at: 0)
                if !batchMode { try saveVault() }
            } else {
                library.assets.insert(asset, at: 0)
                if !library.processedAssetHashes.contains(hash) {
                    library.processedAssetHashes.append(hash)
                }
                if !batchMode {
                    try saveLibrary()
                    if let img = scaledImage {
                        Task { [weak self] in
                            await self?.processFacesForAsset(id, image: img, saveAndCluster: true)
                        }
                    }
                }
            }
            return (id, scaledImage)
        } catch {
            library = previousLibrary
            privateLibrary = previousPrivateLibrary
            try? FileManager.default.removeItem(at: originalURL)
            try? FileManager.default.removeItem(at: filesURL.appendingPathComponent(id.uuidString + ".thumb"))
            throw error
        }
    }

    func importPhotoItems(
        _ items: [PhotosPickerItem],
        secure: Bool = false,
        targetAlbumID: UUID? = nil,
        targetSectionID: UUID? = nil,
        targetPersonID: UUID? = nil
    ) async {
        busy = true
        defer { busy = false }
        var imported = 0
        var pendingFaceAssets: [(UUID, UIImage)] = []

        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    continue
                }
                let type = item.supportedContentTypes.first
                let mime = type?.preferredMIMEType ?? "image/jpeg"
                let ext = type?.preferredFilenameExtension ?? "jpg"
                let result = try importData(
                    data,
                    name: "Recuerdo-\(UUID().uuidString.prefix(8)).\(ext)",
                    mime: mime,
                    secure: secure,
                    targetAlbumID: targetAlbumID,
                    targetSectionID: targetSectionID,
                    targetPersonID: targetPersonID,
                    batchMode: true
                )
                if let img = result.image {
                    pendingFaceAssets.append((result.assetID, img))
                }
                imported += 1
            } catch MemoraError.duplicate {
                continue
            } catch {
                notice = error.localizedDescription
                break
            }
        }

        if imported > 0 {
            if secure {
                try? saveVault()
            } else {
                try? saveLibrary()
            }
            notice = "\(imported) archivo\(imported == 1 ? "" : "s") integrado\(imported == 1 ? "" : "s") correctamente."

            if !secure && !pendingFaceAssets.isEmpty {
                Task { [weak self] in
                    guard let self else { return }
                    for (assetID, img) in pendingFaceAssets {
                        await self.processFacesForAsset(assetID, image: img, saveAndCluster: false)
                    }
                    self.recomputeClusters()
                    try? self.saveLibrary()
                }
            }
        }
    }

    func importURLs(
        _ urls: [URL],
        secure: Bool = false,
        targetAlbumID: UUID? = nil,
        targetSectionID: UUID? = nil,
        targetPersonID: UUID? = nil
    ) {
        var imported = 0
        var pendingFaceAssets: [(UUID, UIImage)] = []

        for url in urls {
            let granted = url.startAccessingSecurityScopedResource()
            defer { if granted { url.stopAccessingSecurityScopedResource() } }
            do {
                if (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) > fileLimit {
                    throw MemoraError.fileTooLarge
                }
                let data = try Data(contentsOf: url)
                let result = try importData(
                    data,
                    name: url.lastPathComponent,
                    mime: (UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"),
                    secure: secure,
                    targetAlbumID: targetAlbumID,
                    targetSectionID: targetSectionID,
                    targetPersonID: targetPersonID,
                    batchMode: true
                )
                if let img = result.image {
                    pendingFaceAssets.append((result.assetID, img))
                }
                imported += 1
            } catch MemoraError.duplicate {
                continue
            } catch {
                notice = error.localizedDescription
                break
            }
        }

        if imported > 0 {
            if secure {
                try? saveVault()
            } else {
                try? saveLibrary()
            }
            notice = "\(imported) archivo\(imported == 1 ? "" : "s") integrado\(imported == 1 ? "" : "s") correctamente."

            if !secure && !pendingFaceAssets.isEmpty {
                Task { [weak self] in
                    guard let self else { return }
                    for (assetID, img) in pendingFaceAssets {
                        await self.processFacesForAsset(assetID, image: img, saveAndCluster: false)
                    }
                    self.recomputeClusters()
                    try? self.saveLibrary()
                }
            }
        }
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
        faceCropCache.removeAll()
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
            try? BiometricVault.save(key, account: account.id)
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
        let unlockedVaultKey = SymmetricKey(data: plain)
        vaultKey = unlockedVaultKey
        do { try loadVault() } catch { lockVault(); throw error }
        self.account = account
        try saveAccount()
        try? BiometricVault.save(unlockedVaultKey, account: account.id)
        vaultDeadline = Date().addingTimeInterval(15 * 60)
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
        let unlockedVaultKey = SymmetricKey(data: plain)
        vaultKey = unlockedVaultKey
        do { try loadVault() } catch { lockVault(); throw error }
        try? BiometricVault.save(unlockedVaultKey, account: account.id)
        vaultDeadline = Date().addingTimeInterval(15 * 60)
    }

    func unlockVaultWithBiometrics() async throws {
        guard let account else { throw MemoraError.noAccount }
        guard !isPerformingBiometricAuth else { return }
        isPerformingBiometricAuth = true
        defer { isPerformingBiometricAuth = false }

        let key = try await BiometricVault.read(account: account.id)
        vaultKey = key
        do { try loadVault() } catch { lockVault(); throw error }
        vaultDeadline = Date().addingTimeInterval(15 * 60)
    }

    func enableVaultBiometrics() throws {
        guard let account, let vaultKey else { throw MemoraError.locked }
        try BiometricVault.save(vaultKey, account: account.id)
    }

    func lockVault() {
        guard !isPerformingBiometricAuth else { return }
        vaultKey = nil
        vaultDeadline = nil
        privateLibrary = nil
        thumbnailCache.removeAll()
        try? FileManager.default.removeItem(at: temporaryURL)
    }

    func checkVaultDeadline() {
        if let vaultDeadline, vaultDeadline <= .now { lockVault() }
    }

    func recordSuccessfulCloudflareBackup(date: Date = Date()) {
        lastCloudflareBackupDate = date
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: lastBackupPreference)
    }

    func restoreFromE2EEContainer(_ container: MemoraE2EEContainer) async throws {
        guard container.accountID == account?.id else {
            throw MemoraError.invalidInput("Esta copia pertenece a otra cuenta de Memora.")
        }
        let restoredLibrary = try JSONDecoder().decode(MemoryLibrary.self, from: container.libraryData)
        let restoredVault: PrivateLibrary? = {
            guard let vd = container.vaultData else { return nil }
            return try? JSONDecoder().decode(PrivateLibrary.self, from: vd)
        }()

        try FileManager.default.createDirectory(at: filesURL, withIntermediateDirectories: true)
        for (filename, fileData) in container.files {
            let target = filesURL.appendingPathComponent(filename)
            try write(fileData, to: target)
        }

        self.library = restoredLibrary
        try saveLibrary()

        if let restoredVault {
            self.privateLibrary = restoredVault
            try saveVault()
        }

        thumbnailCache.removeAll()
        notice = "Copia cifrada restaurada correctamente desde Cloudflare."
    }
}

// MARK: - Soporte en la nube
/// Servicio de sincronización a Cloudflare (mock) para subir y descargar copias de seguridad de forma automatizada y cifrada (E2EE)
struct CloudSyncService {
    static func uploadBackup(accountID: UUID, libraryData: Data, vaultData: Data?, files: [String: Data]) async throws {
        let container = MemoraE2EEContainer(
            version: 1,
            accountID: accountID,
            createdAt: Date(),
            salt: Data(),
            libraryData: libraryData,
            vaultData: vaultData,
            files: files,
            checksum: MemoraCrypto.sha256(libraryData)
        )
        // Simulate upload to Cloudflare R2
        try await Task.sleep(nanoseconds: 1_500_000_000)
        print("Backup cifrado subido a Cloudflare para la cuenta \(accountID)")
    }
    
    static func downloadBackup(accountID: UUID) async throws -> MemoraE2EEContainer {
        // Simulate download from Cloudflare R2
        try await Task.sleep(nanoseconds: 1_500_000_000)
        throw MemoraError.invalidInput("No se encontró copia en Cloudflare para esta cuenta.")
    }
}
