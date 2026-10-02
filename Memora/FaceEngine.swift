import CoreGraphics
import Foundation
import UIKit
import Vision

enum FaceEngine {
    // Umbrales calibrados para el Confidence Engine
    static let thresholdAccept: Double = 0.80   // Alta confianza -> asignación automática
    static let thresholdReview: Double = 0.62   // Dudoso -> sugiere revisión al usuario
    static let qualityGateMinimum: Double = 0.45 // Quality Gate para aprender prototipos

    // MARK: - 1. Pipeline de Análisis de Rostros en una Imagen
    static func analyzeImage(_ image: UIImage, assetID: UUID) async -> [DetectedFace] {
        guard let cgImage = image.cgImage else { return [] }

        return await withCheckedContinuation { continuation in
            let landmarksRequest = VNDetectFaceLandmarksRequest()
            let qualityRequest = VNDetectFaceCaptureQualityRequest()

            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
            do {
                try handler.perform([landmarksRequest, qualityRequest])
            } catch {
                continuation.resume(returning: [])
                return
            }

            guard let observations = landmarksRequest.results, !observations.isEmpty else {
                continuation.resume(returning: [])
                return
            }

            let qualityMap: [UUID: Float] = Dictionary(
                uniqueKeysWithValues: (qualityRequest.results ?? []).compactMap { qObs in
                    guard let q = qObs.faceCaptureQuality else { return nil }
                    return (qObs.uuid, q)
                }
            )

            var detected: [DetectedFace] = []

            for obs in observations {
                let bbox = FaceBoundingBox(
                    x: Double(obs.boundingBox.origin.x),
                    y: Double(obs.boundingBox.origin.y),
                    width: Double(obs.boundingBox.size.width),
                    height: Double(obs.boundingBox.size.height)
                )

                // 2. Quality Gate
                let sizeRatio = min(Double(obs.boundingBox.width * obs.boundingBox.height) * 4.0, 1.0)
                let captureQ = Double(qualityMap[obs.uuid] ?? 0.6)
                let confidenceScore = Double(obs.confidence)

                // Cálculo del ángulo según posición de los ojos
                var angleScore = 0.8
                var alignmentRotation: Double = 0.0
                if let landmarks = obs.landmarks,
                   let leftEye = landmarks.leftEye?.normalizedPoints.first,
                   let rightEye = landmarks.rightEye?.normalizedPoints.first {
                    let dy = Double(rightEye.y - leftEye.y)
                    let dx = Double(rightEye.x - leftEye.x)
                    alignmentRotation = atan2(dy, dx)
                    let tilt = abs(alignmentRotation)
                    angleScore = max(0.2, 1.0 - (tilt / .pi))
                }

                let qualityScore = (sizeRatio * 0.25) +
                                   (captureQ * 0.35) +
                                   (angleScore * 0.20) +
                                   (confidenceScore * 0.20)

                // 3. Extracción de Embedding Vectorial (128 dimensiones normalizado)
                let embedding = generateEmbedding(for: obs, in: cgImage, rotation: alignmentRotation)

                detected.append(
                    DetectedFace(
                        id: UUID(),
                        assetID: assetID,
                        bbox: bbox,
                        quality: qualityScore,
                        embedding: embedding,
                        personID: nil,
                        confidence: confidenceScore,
                        reviewStatus: .unassigned
                    )
                )
            }

            continuation.resume(returning: detected)
        }
    }

    // MARK: - 3. Normalización y Extracción de Embedding Vectorial
    private static func generateEmbedding(
        for observation: VNFaceObservation,
        in cgImage: CGImage,
        rotation: Double
    ) -> [Float] {
        var vector = [Float](repeating: 0.0, count: 128)

        // Características geométricas y biométricas basadas en landmarks faciales
        if let landmarks = observation.landmarks {
            var featureIndex = 0

            func addPoint(_ pt: CGPoint) {
                guard featureIndex < 120 else { return }
                vector[featureIndex] = Float(pt.x)
                vector[featureIndex + 1] = Float(pt.y)
                featureIndex += 2
            }

            if let median = landmarks.medianLine?.normalizedPoints {
                for p in median.prefix(6) { addPoint(p) }
            }
            if let nose = landmarks.nose?.normalizedPoints {
                for p in nose.prefix(8) { addPoint(p) }
            }
            if let outerLips = landmarks.outerLips?.normalizedPoints {
                for p in outerLips.prefix(10) { addPoint(p) }
            }
            if let leftEye = landmarks.leftEye?.normalizedPoints {
                for p in leftEye.prefix(6) { addPoint(p) }
            }
            if let rightEye = landmarks.rightEye?.normalizedPoints {
                for p in rightEye.prefix(6) { addPoint(p) }
            }
            if let leftEyebrow = landmarks.leftEyebrow?.normalizedPoints {
                for p in leftEyebrow.prefix(4) { addPoint(p) }
            }
            if let rightEyebrow = landmarks.rightEyebrow?.normalizedPoints {
                for p in rightEyebrow.prefix(4) { addPoint(p) }
            }
        }

        // Bounding box y características globales en los últimos índices
        let w = Float(observation.boundingBox.width)
        let h = Float(observation.boundingBox.height)
        vector[124] = w
        vector[125] = h
        vector[126] = Float(rotation)
        vector[127] = Float(observation.confidence)

        // Normalización L2 del vector a longitud unitaria
        return normalizeL2(vector)
    }

    // MARK: - 4. Normalización L2 y Similitud de Coseno
    static func normalizeL2(_ vector: [Float]) -> [Float] {
        let sumSquares = vector.reduce(0.0) { $0 + ($1 * $1) }
        let norm = sqrt(sumSquares)
        guard norm > 0.00001 else { return vector }
        return vector.map { $0 / norm }
    }

    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0.0 }
        var dot: Float = 0.0
        for i in 0..<a.count {
            dot += a[i] * b[i]
        }
        return Double(max(0.0, min(1.0, dot)))
    }

    // MARK: - 5. Cálculo del Identity Prototype (Mean + L2 Normalize)
    static func computePrototype(from embeddings: [[Float]]) -> [Float]? {
        guard !embeddings.isEmpty else { return nil }
        let dimension = embeddings[0].count
        var accumulator = [Float](repeating: 0.0, count: dimension)

        for emb in embeddings {
            guard emb.count == dimension else { continue }
            for i in 0..<dimension {
                accumulator[i] += emb[i]
            }
        }

        let count = Float(embeddings.count)
        let mean = accumulator.map { $0 / count }
        return normalizeL2(mean)
    }

    // MARK: - 6. Confidence Engine (Evaluación con 3 Zonas)
    static func classifyFace(
        _ face: DetectedFace,
        against people: [MemoryPerson],
        facesCatalog: [UUID: DetectedFace]
    ) -> (personID: UUID?, confidence: Double, zone: FaceMatchResult.ConfidenceZone) {
        var bestPersonID: UUID?
        var bestScore: Double = 0.0

        for person in people {
            var scores: [Double] = []

            // Comparar contra el Prototype (Rápido)
            if let prototype = person.prototype {
                let score = cosineSimilarity(face.embedding, prototype)
                scores.append(score)
            }

            // Comparar contra los 5-20 Exemplars representativos
            for faceID in person.exemplarFaceIDs.prefix(20) {
                if let exemplar = facesCatalog[faceID] {
                    let score = cosineSimilarity(face.embedding, exemplar.embedding)
                    scores.append(score)
                }
            }

            let maxScore = scores.max() ?? 0.0
            if maxScore > bestScore {
                bestScore = maxScore
                bestPersonID = person.id
            }
        }

        if bestScore >= thresholdAccept {
            return (bestPersonID, bestScore, .high)
        } else if bestScore >= thresholdReview {
            return (bestPersonID, bestScore, .review)
        } else {
            return (nil, bestScore, .low)
        }
    }

    // MARK: - 7. Búsqueda Funcional Mediante Fotografía (Search by Photo)
    static func searchPeopleByPhoto(
        queryImage: UIImage,
        people: [MemoryPerson],
        albums: [MemoryAlbum],
        sections: [MemorySection] = [],
        assets: [MemoryAsset],
        facesCatalog: [UUID: DetectedFace]
    ) async -> [FaceMatchResult] {
        let faces = await analyzeImage(queryImage, assetID: UUID())
        guard let queryFace = faces.sorted(by: { $0.quality > $1.quality }).first else {
            return []
        }

        var results: [FaceMatchResult] = []

        for person in people {
            var candidateScores: [Double] = []

            if let prototype = person.prototype {
                candidateScores.append(cosineSimilarity(queryFace.embedding, prototype))
            }

            for exemplarID in person.exemplarFaceIDs.prefix(20) {
                if let ex = facesCatalog[exemplarID] {
                    candidateScores.append(cosineSimilarity(queryFace.embedding, ex.embedding))
                }
            }

            let score = candidateScores.max() ?? 0.0
            let zone: FaceMatchResult.ConfidenceZone = {
                if score >= thresholdAccept { return .high }
                if score >= thresholdReview { return .review }
                return .low
            }()

            let personAssets = assets.filter { $0.personIDs.contains(person.id) }
            let personAlbums = albums.filter { album in
                personAssets.contains { $0.albumIDs.contains(album.id) }
            }
            let sectionIDs = Set(personAlbums.compactMap(\.sectionID))
            let relatedSections = sections.filter { sectionIDs.contains($0.id) }.map(\.name)
            let relatedAlbums = personAlbums.map(\.name)

            results.append(
                FaceMatchResult(
                    person: person,
                    confidence: score,
                    zone: zone,
                    albumCount: personAlbums.count,
                    assetCount: personAssets.count,
                    relatedSectionNames: relatedSections,
                    relatedAlbumNames: relatedAlbums
                )
            )
        }

        // Ordenar por similitud decreciente
        return results.sorted { $0.confidence > $1.confidence }
    }

    // MARK: - 8. Clustering de Rostros Desconocidos (Antes de conocer nombres)
    static func clusterFaces(
        unassignedFaces: [DetectedFace],
        similarityThreshold: Double = 0.72
    ) -> [FaceCluster] {
        var clusters: [[DetectedFace]] = []

        for face in unassignedFaces.filter({ $0.quality >= qualityGateMinimum }) {
            var matchedClusterIndex: Int?

            for (idx, cluster) in clusters.enumerated() {
                let similarities = cluster.map { cosineSimilarity(face.embedding, $0.embedding) }
                if let avg = similarities.max(), avg >= similarityThreshold {
                    matchedClusterIndex = idx
                    break
                }
            }

            if let idx = matchedClusterIndex {
                clusters[idx].append(face)
            } else {
                clusters.append([face])
            }
        }

        return clusters.compactMap { clusterFaces in
            guard let representative = clusterFaces.max(by: { $0.quality < $1.quality }) else { return nil }
            return FaceCluster(
                id: UUID(),
                faceIDs: clusterFaces.map(\.id),
                representativeFaceID: representative.id,
                suggestedName: nil
            )
        }
    }
}
