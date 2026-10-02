import Foundation

enum AssetKind: String, Codable, CaseIterable, Hashable {
    case photo, video, audio, document

    var label: String {
        switch self {
        case .photo: "Fotos"
        case .video: "Videos"
        case .audio: "Audio"
        case .document: "Documentos"
        }
    }

    var symbol: String {
        switch self {
        case .photo: "photo"
        case .video: "video"
        case .audio: "waveform"
        case .document: "doc"
        }
    }

    static func classify(_ mime: String) -> AssetKind {
        if mime.hasPrefix("image/") { return .photo }
        if mime.hasPrefix("video/") { return .video }
        if mime.hasPrefix("audio/") { return .audio }
        return .document
    }
}

struct MemoryAsset: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var mime: String
    var kind: AssetKind
    var size: Int
    var addedAt: Date
    var capturedAt: Date
    var sha256: String
    var wrappedFileKey: Data
    var albumIDs: [UUID] = []
    var personIDs: [UUID] = []
    var tags: [String] = []
    var location: String = ""
    var favorite = false
    var hasThumbnail = false
    var deletedAt: Date?
    // Metadatos EXIF y técnicos
    var cameraModel: String? = nil
    var iso: Int? = nil
    var aperture: Double? = nil
    var focalLength: Double? = nil
    var width: Int? = nil
    var height: Int? = nil
    var latitude: Double? = nil
    var longitude: Double? = nil
}

struct MemorySection: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var symbol: String
}

struct MemoryAlbum: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var sectionID: UUID?
    var createdAt: Date
    var coverAssetID: UUID?
}

struct MemoryPerson: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var coverAssetID: UUID?
    var prototype: [Float]? = nil
    var prototypes: [[Float]]? = nil
    var exemplarFaceIDs: [UUID] = []
    var reviewCandidateAssetIDs: [UUID] = []

    var allPrototypes: [[Float]] {
        if let protos = prototypes, !protos.isEmpty {
            return protos
        }
        if let single = prototype {
            return [single]
        }
        return []
    }
}

// MARK: - Modelos de Face Engine 2.0
struct FaceBoundingBox: Codable, Hashable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

enum FaceReviewStatus: String, Codable, Hashable {
    case confirmed
    case suggested
    case unassigned
}

struct FaceDescriptor {
    let embedding: [Float]
    let quality: Double
    let yaw: Double
    let pitch: Double
    let roll: Double
    let boundingBox: CGRect
    let sourceAssetID: UUID
}

struct DetectedFace: Identifiable, Codable, Hashable {
    var id: UUID
    var assetID: UUID
    var bbox: FaceBoundingBox
    var quality: Double
    var embedding: [Float]
    var personID: UUID?
    var confidence: Double
    var reviewStatus: FaceReviewStatus = .unassigned
    var yaw: Double? = nil
    var pitch: Double? = nil
    var roll: Double? = nil
}

struct FaceCluster: Identifiable, Codable, Hashable {
    var id: UUID
    var faceIDs: [UUID]
    var representativeFaceID: UUID
    var suggestedName: String?
}

struct FaceMatchResult: Identifiable, Hashable {
    var id: UUID { person.id }
    let person: MemoryPerson
    let confidence: Double
    let zone: ConfidenceZone
    let albumCount: Int
    let assetCount: Int
    var relatedSectionNames: [String] = []
    var relatedAlbumNames: [String] = []

    enum ConfidenceZone: String, Hashable {
        case high = "Alta confianza"
        case review = "Dudoso (Revisar)"
        case low = "Baja coincidencia"
    }
}

struct MemoryLibrary: Codable {
    var version = 2
    var assets: [MemoryAsset] = []
    var sections: [MemorySection] = []
    var albums: [MemoryAlbum] = []
    var people: [MemoryPerson] = []
    var detectedFaces: [DetectedFace] = []
    var clusters: [FaceCluster] = []
    var processedAssetHashes: [String] = []
}

struct PrivateLibrary: Codable {
    var version = 1
    var assets: [MemoryAsset] = []
    var albums: [MemoryAlbum] = []
}

struct AccountRecord: Codable {
    var id: UUID
    var name: String
    var email: String
    var createdAt: Date
    var passwordSalt: Data
    var wrappedRootKey: Data
    var wrappedRecoveryKey: Data
    var failedAttempts = 0
    var blockedUntil: Date?
    var vaultSalt: Data?
    var wrappedVaultKey: Data?
    var vaultRecoveryEnvelope: Data?
    var profilePhotoData: Data? = nil
}

enum MemoraError: LocalizedError {
    case invalidInput(String)
    case wrongCredentials
    case locked
    case noAccount
    case corruptData
    case fileTooLarge
    case duplicate

    var errorDescription: String? {
        switch self {
        case .invalidInput(let message): message
        case .wrongCredentials: "El correo o la contraseña no son correctos."
        case .locked: "Espera un momento antes de volver a intentarlo."
        case .noAccount: "Crea una cuenta local en este dispositivo."
        case .corruptData: "No se pudieron verificar los datos cifrados."
        case .fileTooLarge: "Esta versión admite hasta 50 MB por archivo."
        case .duplicate: "Este archivo ya existe en tu biblioteca."
        }
    }
}

extension Int {
    var memorySize: String { ByteCountFormatter.string(fromByteCount: Int64(self), countStyle: .file) }
}
