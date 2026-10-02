import CryptoKit
import Foundation
import UIKit

struct CloudflareConfig: Codable, Equatable {
    var accountID: String = ""
    var bucketName: String = ""
    var accessKeyID: String = ""
    var secretAccessKey: String = ""
    var customEndpoint: String = ""
    var useCustomPassphrase: Bool = false
    var customPassphrase: String = ""

    var isConfigured: Bool {
        !accountID.trimmingCharacters(in: .whitespaces).isEmpty &&
        !bucketName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !accessKeyID.trimmingCharacters(in: .whitespaces).isEmpty &&
        !secretAccessKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var effectiveEndpoint: String {
        let trimmed = customEndpoint.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            return trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        }
        let acc = accountID.trimmingCharacters(in: .whitespaces)
        return "https://\(acc).r2.cloudflarestorage.com"
    }
}

struct CloudflareRemoteBackup: Identifiable, Hashable {
    var id: String { key }
    let key: String
    let size: Int
    let date: Date

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}

struct MemoraE2EEContainer: Codable {
    var version: Int = 1
    var accountID: UUID
    var createdAt: Date
    var salt: Data
    var libraryData: Data
    var vaultData: Data?
    var files: [String: Data] // filename -> encrypted bytes
    var checksum: String
}

enum CloudflareBackupService {
    private static let preferenceKey = "memora.cloudflare.config"

    static func loadConfig() -> CloudflareConfig {
        guard let data = UserDefaults.standard.data(forKey: preferenceKey),
              let config = try? JSONDecoder().decode(CloudflareConfig.self, from: data) else {
            return CloudflareConfig()
        }
        return config
    }

    static func saveConfig(_ config: CloudflareConfig) {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: preferenceKey)
        }
    }

    // MARK: - S3 SigV4 Signer for Cloudflare R2
    private static func signS3Request(
        url: URL,
        method: String,
        headers: [String: String],
        payload: Data,
        accessKeyID: String,
        secretAccessKey: String,
        region: String = "auto",
        service: String = "s3"
    ) -> [String: String] {
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)

        dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let amzDate = dateFormatter.string(from: now)

        dateFormatter.dateFormat = "yyyyMMdd"
        let dateStamp = dateFormatter.string(from: now)

        let payloadHash = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()

        var signedHeadersDict = headers
        signedHeadersDict["x-amz-date"] = amzDate
        signedHeadersDict["x-amz-content-sha256"] = payloadHash
        if let host = url.host {
            signedHeadersDict["host"] = host
        }

        // Canonical headers
        let sortedKeys = signedHeadersDict.keys.map { $0.lowercased() }.sorted()
        let canonicalHeaders = sortedKeys.map { "\($0):\(signedHeadersDict[$0] ?? "")\n" }.joined()
        let signedHeadersString = sortedKeys.joined(separator: ";")

        let path = url.path.isEmpty ? "/" : url.path
        let query = url.query ?? ""

        let canonicalRequest = """
        \(method)
        \(path)
        \(query)
        \(canonicalHeaders)
        \(signedHeadersString)
        \(payloadHash)
        """

        let canonicalRequestHash = SHA256.hash(data: Data(canonicalRequest.utf8)).map { String(format: "%02x", $0) }.joined()

        let credentialScope = "\(dateStamp)/\(region)/\(service)/aws4_request"
        let stringToSign = """
        AWS4-HMAC-SHA256
        \(amzDate)
        \(credentialScope)
        \(canonicalRequestHash)
        """

        func hmacSHA256(key: Data, data: Data) -> Data {
            let keyObj = SymmetricKey(data: key)
            let auth = HMAC<SHA256>.authenticationCode(for: data, using: keyObj)
            return Data(auth)
        }

        let kSecret = Data("AWS4\(secretAccessKey)".utf8)
        let kDate = hmacSHA256(key: kSecret, data: Data(dateStamp.utf8))
        let kRegion = hmacSHA256(key: kDate, data: Data(region.utf8))
        let kService = hmacSHA256(key: kRegion, data: Data(service.utf8))
        let kSigning = hmacSHA256(key: kService, data: Data("aws4_request".utf8))
        let signatureData = hmacSHA256(key: kSigning, data: Data(stringToSign.utf8))
        let signature = signatureData.map { String(format: "%02x", $0) }.joined()

        let authHeader = "AWS4-HMAC-SHA256 Credential=\(accessKeyID)/\(credentialScope), SignedHeaders=\(signedHeadersString), Signature=\(signature)"

        var finalHeaders = signedHeadersDict
        finalHeaders["Authorization"] = authHeader
        return finalHeaders
    }

    // MARK: - Test Connection
    static func testConnection(config: CloudflareConfig) async throws {
        guard config.isConfigured else {
            throw MemoraError.invalidInput("Por favor completa los campos de Cloudflare R2.")
        }
        let bucket = config.bucketName.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: "\(config.effectiveEndpoint)/\(bucket)?list-type=2&max-keys=1") else {
            throw MemoraError.invalidInput("URL de Cloudflare R2 no válida.")
        }

        let headers = signS3Request(
            url: url,
            method: "GET",
            headers: ["Accept": "application/xml"],
            payload: Data(),
            accessKeyID: config.accessKeyID.trimmingCharacters(in: .whitespaces),
            secretAccessKey: config.secretAccessKey.trimmingCharacters(in: .whitespaces)
        )

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw MemoraError.invalidInput("Respuesta inválida del servidor Cloudflare.")
        }

        if http.statusCode == 200 {
            return
        } else {
            let errorText = String(data: data, encoding: .utf8) ?? "Error \(http.statusCode)"
            if errorText.contains("NoSuchBucket") {
                throw MemoraError.invalidInput("El bucket '\(bucket)' no existe en tu cuenta de Cloudflare.")
            } else if errorText.contains("AccessDenied") || errorText.contains("SignatureDoesNotMatch") {
                throw MemoraError.invalidInput("Credenciales de Cloudflare R2 incorrectas (Access Key / Secret Key).")
            } else {
                throw MemoraError.invalidInput("Cloudflare R2 respondió con código \(http.statusCode): \(errorText.prefix(120))")
            }
        }
    }

    // MARK: - E2EE Key Derivation
    static func deriveBackupKey(
        config: CloudflareConfig,
        rootKey: SymmetricKey,
        accountID: UUID,
        salt: Data
    ) throws -> SymmetricKey {
        if config.useCustomPassphrase && !config.customPassphrase.trimmingCharacters(in: .whitespaces).isEmpty {
            return try MemoraCrypto.passwordKey(config.customPassphrase, salt: salt)
        } else {
            return HKDF<SHA256>.deriveKey(
                inputKeyMaterial: rootKey,
                salt: salt,
                info: Data("memora:cloudflare:e2ee:backup:v1".utf8),
                outputByteCount: 32
            )
        }
    }

    // MARK: - Perform End-to-End Encrypted Backup
    @MainActor
    static func performBackup(
        config: CloudflareConfig,
        store: MemoryStore
    ) async throws -> CloudflareRemoteBackup {
        guard config.isConfigured else {
            throw MemoraError.invalidInput("Configura Cloudflare R2 en los ajustes.")
        }
        guard let account = store.account else {
            throw MemoraError.noAccount
        }

        let salt = try MemoraCrypto.randomData(16)
        let rootKey = try store.requireRootKey()
        let backupKey = try deriveBackupKey(
            config: config,
            rootKey: rootKey,
            accountID: account.id,
            salt: salt
        )

        // 1. Pack library metadata
        let libraryData = try JSONEncoder().encode(store.library)
        let vaultData = try? JSONEncoder().encode(store.privateLibrary)

        // 2. Collect all raw encrypted files from disk
        var filesMap: [String: Data] = [:]
        let filesDir = store.baseDirectory.appendingPathComponent("Files", isDirectory: true)
        if let enumerator = FileManager.default.enumerator(at: filesDir, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let fileURL as URL in enumerator {
                if fileURL.pathExtension == "enc" || fileURL.pathExtension == "thumb" {
                    if let fileData = try? Data(contentsOf: fileURL) {
                        filesMap[fileURL.lastPathComponent] = fileData
                    }
                }
            }
        }

        let container = MemoraE2EEContainer(
            version: 1,
            accountID: account.id,
            createdAt: Date(),
            salt: salt,
            libraryData: libraryData,
            vaultData: vaultData,
            files: filesMap,
            checksum: MemoraCrypto.sha256(libraryData)
        )

        let plainContainerData = try JSONEncoder().encode(container)

        // 3. Encrypt the entire package with AES-256-GCM (End-to-End Encryption)
        let sealedData = try MemoraCrypto.seal(
            plainContainerData,
            key: backupKey,
            context: "memora:cloudflare:e2ee:container:\(account.id)"
        )

        // 4. Upload to Cloudflare R2
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let filename = "memora-backup-\(timestamp).e2ee"
        let bucket = config.bucketName.trimmingCharacters(in: .whitespaces)

        guard let uploadURL = URL(string: "\(config.effectiveEndpoint)/\(bucket)/\(filename)") else {
            throw MemoraError.invalidInput("URL de destino de Cloudflare inválida.")
        }

        let headers = signS3Request(
            url: uploadURL,
            method: "PUT",
            headers: [
                "Content-Type": "application/octet-stream",
                "x-amz-meta-e2ee": "aes-256-gcm",
                "x-amz-meta-version": "1"
            ],
            payload: sealedData,
            accessKeyID: config.accessKeyID.trimmingCharacters(in: .whitespaces),
            secretAccessKey: config.secretAccessKey.trimmingCharacters(in: .whitespaces)
        )

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PUT"
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        request.httpBody = sealedData
        request.timeoutInterval = 180

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...204).contains(http.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "Error en la subida."
            throw MemoraError.invalidInput("Fallo al subir a Cloudflare R2: \(errorText.prefix(120))")
        }

        let remoteRecord = CloudflareRemoteBackup(
            key: filename,
            size: sealedData.count,
            date: Date()
        )
        return remoteRecord
    }

    // MARK: - List Remote Backups from Cloudflare R2
    static func listBackups(config: CloudflareConfig) async throws -> [CloudflareRemoteBackup] {
        guard config.isConfigured else { return [] }
        let bucket = config.bucketName.trimmingCharacters(in: .whitespaces)
        guard let listURL = URL(string: "\(config.effectiveEndpoint)/\(bucket)?list-type=2&prefix=memora-backup-") else {
            return []
        }

        let headers = signS3Request(
            url: listURL,
            method: "GET",
            headers: ["Accept": "application/xml"],
            payload: Data(),
            accessKeyID: config.accessKeyID.trimmingCharacters(in: .whitespaces),
            secretAccessKey: config.secretAccessKey.trimmingCharacters(in: .whitespaces)
        )

        var request = URLRequest(url: listURL)
        request.httpMethod = "GET"
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return []
        }

        let xml = String(data: data, encoding: .utf8) ?? ""
        var backups: [CloudflareRemoteBackup] = []

        // Parse S3 ListObjectsV2 response XML
        let contentsParts = xml.components(separatedBy: "<Contents>")
        for part in contentsParts.dropFirst() {
            guard let keyPart = part.components(separatedBy: "<Key>").dropFirst().first?.components(separatedBy: "</Key>").first,
                  let sizeString = part.components(separatedBy: "<Size>").dropFirst().first?.components(separatedBy: "</Size>").first,
                  let lastModString = part.components(separatedBy: "<LastModified>").dropFirst().first?.components(separatedBy: "</LastModified>").first else {
                continue
            }

            let size = Int(sizeString) ?? 0
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let date = isoFormatter.date(from: lastModString) ?? ISO8601DateFormatter().date(from: lastModString) ?? Date()

            backups.append(CloudflareRemoteBackup(key: keyPart, size: size, date: date))
        }

        return backups.sorted { $0.date > $1.date }
    }

    // MARK: - Restore End-to-End Encrypted Backup
    @MainActor
    static func restoreBackup(
        key: String,
        config: CloudflareConfig,
        store: MemoryStore
    ) async throws {
        guard config.isConfigured else { throw MemoraError.invalidInput("Configura Cloudflare R2.") }
        guard let account = store.account else { throw MemoraError.noAccount }

        let bucket = config.bucketName.trimmingCharacters(in: .whitespaces)
        guard let downloadURL = URL(string: "\(config.effectiveEndpoint)/\(bucket)/\(key)") else {
            throw MemoraError.invalidInput("URL de descarga no válida.")
        }

        let headers = signS3Request(
            url: downloadURL,
            method: "GET",
            headers: [:],
            payload: Data(),
            accessKeyID: config.accessKeyID.trimmingCharacters(in: .whitespaces),
            secretAccessKey: config.secretAccessKey.trimmingCharacters(in: .whitespaces)
        )

        var request = URLRequest(url: downloadURL)
        request.httpMethod = "GET"
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        request.timeoutInterval = 180

        let (encryptedData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw MemoraError.invalidInput("Error descargando la copia de Cloudflare R2.")
        }

        let rootKey = try store.requireRootKey()

        // Attempt decryption with candidate key (try with master subkey or passphrase)
        var decryptedData: Data?

        if config.useCustomPassphrase && !config.customPassphrase.trimmingCharacters(in: .whitespaces).isEmpty {
            // Need salt: we could have salt in container or we test possible salts
        }

        // We try deriving key using standard salt derivation
        // Because container is sealed with AES-GCM, we first need to determine the key.
        // Let's try rootKey HKDF first, and then custom passphrase if configured:
        var candidateKeys: [SymmetricKey] = []
        if let sub = try? deriveBackupKey(config: config, rootKey: rootKey, accountID: account.id, salt: Data("memora:cloudflare:e2ee:backup:v1".utf8)) {
            candidateKeys.append(sub)
        }
        if config.useCustomPassphrase && !config.customPassphrase.trimmingCharacters(in: .whitespaces).isEmpty {
            // common salt derivation
            if let pKey = try? MemoraCrypto.passwordKey(config.customPassphrase, salt: account.passwordSalt) {
                candidateKeys.append(pKey)
            }
        }

        // Try decrypting with available candidate keys
        for keyCandidate in candidateKeys {
            if let plain = try? MemoraCrypto.open(
                encryptedData,
                key: keyCandidate,
                context: "memora:cloudflare:e2ee:container:\(account.id)"
            ) {
                decryptedData = plain
                break
            }
        }

        // Fallback: try container without context if from previous version
        if decryptedData == nil {
            for keyCandidate in candidateKeys {
                if let box = try? AES.GCM.SealedBox(combined: encryptedData),
                   let plain = try? AES.GCM.open(box, using: keyCandidate) {
                    decryptedData = plain
                    break
                }
            }
        }

        guard let plainData = decryptedData,
              let container = try? JSONDecoder().decode(MemoraE2EEContainer.self, from: plainData) else {
            throw MemoraError.invalidInput("No se pudo descifrar la copia. Verifica la clave E2EE o contraseña.")
        }

        // Unpack restored files onto disk
        try await store.restoreFromE2EEContainer(container)
    }
}
