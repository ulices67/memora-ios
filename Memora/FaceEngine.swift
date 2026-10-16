import CoreGraphics
import CoreML
import Foundation
import ImageIO
import UIKit
import Vision

// MARK: - FaceEngine 2.5 (Biometría Híbrida Procrustes + Apariencia Invariante + NMS)
enum FaceEngine {

    /// Dimensión fija del vector biométrico híbrido para garantizar compatibilidad total
    static let embeddingDimension: Int = 256

    // MARK: - 1. Calibración de Umbrales y Gates (Vectores Centrados en Cero L2)
    /// Umbral para auto-asignación (Known)
    static let thresholdAccept: Double = 0.62
    /// Margen mínimo entre el mejor candidato (Top-1) y el segundo (Top-2)
    static let autoMargin: Double = 0.05
    /// Umbral para sugerencia de revisión al usuario (Review)
    static let thresholdReview: Double = 0.46

    /// Recognition Gate: descarta detecciones espurias o ruido de fondo
    static let recognitionGateMinimum: Double = 0.42
    /// Alias de compatibilidad
    static let qualityGateMinimum: Double = 0.42
    /// Enrollment Gate: calidad mínima para ser exemplar permanente
    static let enrollmentGateMinimum: Double = 0.55

    // MARK: - 2. Normalización de Orientación EXIF a Coordenadas Upright
    static func normalizeToUprightCGImage(_ image: UIImage) -> CGImage? {
        if image.imageOrientation == .up, let cg = image.cgImage {
            return cg
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        let upright = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
        return upright.cgImage
    }

    // MARK: - 3. Validación Anatómica Estricta (Evita "sujetos de más" / falsos positivos)
    private static func isValidHumanFace(_ obs: VNFaceObservation) -> Bool {
        // 1. Confianza mínima de Vision
        guard obs.confidence >= 0.72 else { return false }

        // 2. Tamaño mínimo relativo en la imagen (evita ruido de fondo o texturas pequeñas)
        let w = Double(obs.boundingBox.width)
        let h = Double(obs.boundingBox.height)
        guard w >= 0.065, h >= 0.065, (w * h) >= 0.005 else { return false }

        // Proporción de aspecto razonable para un rostro humano
        let aspect = w / max(h, 0.0001)
        guard aspect >= 0.45 && aspect <= 2.1 else { return false }

        // 3. Verificación de landmarks anatómicos obligatorios
        guard let landmarks = obs.landmarks,
              let leftEye = landmarks.leftEye?.normalizedPoints, leftEye.count >= 4,
              let rightEye = landmarks.rightEye?.normalizedPoints, rightEye.count >= 4,
              let nose = landmarks.nose?.normalizedPoints, nose.count >= 3,
              let outerLips = landmarks.outerLips?.normalizedPoints, outerLips.count >= 4 else {
            return false
        }

        // 4. Coherencia geométrica interna (en coordenadas locales del boundingBox 0..1)
        let lEyeCenter = centroid(of: leftEye)
        let rEyeCenter = centroid(of: rightEye)
        let noseCenter = centroid(of: nose)
        let mouthCenter = centroid(of: outerLips)

        let eyeDist = hypot(rEyeCenter.x - lEyeCenter.x, rEyeCenter.y - lEyeCenter.y)
        // La distancia interocular dentro de la caja facial debe ser coherente (15% a 78% del ancho)
        guard eyeDist >= 0.15 && eyeDist <= 0.78 else { return false }

        // En coordenadas locales de Vision (origen abajo-izquierda), los ojos están arriba de la boca
        let eyesMidY = (lEyeCenter.y + rEyeCenter.y) * 0.5
        guard eyesMidY > mouthCenter.y + 0.08 else { return false }
        guard noseCenter.y < eyesMidY + 0.05 && noseCenter.y > mouthCenter.y - 0.02 else { return false }

        return true
    }

    private static func centroid(of points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }
        let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
    }

    // MARK: - 4. Non-Maximum Suppression (Elimina cajas duplicadas sobre la misma cara)
    static func intersectionOverUnion(_ a: FaceBoundingBox, _ b: FaceBoundingBox) -> Double {
        let xA = max(a.x, b.x)
        let yA = max(a.y, b.y)
        let xB = min(a.x + a.width, b.x + b.width)
        let yB = min(a.y + a.height, b.y + b.height)

        let interW = max(0.0, xB - xA)
        let interH = max(0.0, yB - yA)
        let interArea = interW * interH
        guard interArea > 0 else { return 0.0 }

        let areaA = a.width * a.height
        let areaB = b.width * b.height
        let minArea = min(areaA, areaB)
        // Si una caja está contenida > 55% dentro de otra, también es duplicada
        if minArea > 0, (interArea / minArea) > 0.55 {
            return 1.0
        }
        let unionArea = areaA + areaB - interArea
        return unionArea > 0 ? (interArea / unionArea) : 0.0
    }

    private static func nonMaximumSuppression(_ faces: [DetectedFace], iouThreshold: Double = 0.30) -> [DetectedFace] {
        let sorted = faces.sorted { ($0.quality * $0.confidence) > ($1.quality * $1.confidence) }
        var kept: [DetectedFace] = []

        for candidate in sorted {
            let overlaps = kept.contains { existing in
                intersectionOverUnion(candidate.bbox, existing.bbox) > iouThreshold
            }
            if !overlaps {
                kept.append(candidate)
            }
        }
        return kept
    }

    // MARK: - 5. Pipeline de Análisis de Rostros en una Imagen
    static func analyzeImage(_ image: UIImage, assetID: UUID) async -> [DetectedFace] {
        guard let uprightCGImage = normalizeToUprightCGImage(image) else { return [] }
        let imageWidth = CGFloat(uprightCGImage.width)
        let imageHeight = CGFloat(uprightCGImage.height)

        return await withCheckedContinuation { continuation in
            let landmarksRequest = VNDetectFaceLandmarksRequest()
            let qualityRequest = VNDetectFaceCaptureQualityRequest()

            let handler = VNImageRequestHandler(cgImage: uprightCGImage, orientation: .up, options: [:])
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

            var rawDetected: [DetectedFace] = []

            for obs in observations {
                // Filtro anatómico estricto contra falsos positivos
                guard isValidHumanFace(obs) else { continue }

                let normX = Double(obs.boundingBox.origin.x)
                let normY = Double(1.0 - obs.boundingBox.origin.y - obs.boundingBox.height)
                let normW = Double(obs.boundingBox.size.width)
                let normH = Double(obs.boundingBox.size.height)

                let bbox = FaceBoundingBox(x: normX, y: normY, width: normW, height: normH)

                let roll = obs.roll?.doubleValue ?? 0.0
                let yaw = obs.yaw?.doubleValue ?? 0.0
                let pitch = obs.pitch?.doubleValue ?? 0.0

                // Descartar perfiles extremos donde la identidad no es fiable (> 65 grados)
                if abs(yaw) > 1.15 || abs(pitch) > 1.05 { continue }

                let rollScore = max(0.0, 1.0 - (abs(roll) / (.pi / 3.0)))
                let yawScore = max(0.0, 1.0 - (abs(yaw) / (.pi / 2.5)))
                let pitchScore = max(0.0, 1.0 - (abs(pitch) / (.pi / 2.5)))
                let poseScore = (rollScore * 0.20) + (yawScore * 0.50) + (pitchScore * 0.30)

                let sizeRatio = min(Double(obs.boundingBox.width * obs.boundingBox.height) * 5.0, 1.0)
                let captureQ = Double(qualityMap[obs.uuid] ?? 0.55)
                let confidenceScore = Double(obs.confidence)

                let qualityScore = (sizeRatio * 0.20) +
                                   (captureQ * 0.35) +
                                   (poseScore * 0.25) +
                                   (confidenceScore * 0.20)

                guard qualityScore >= recognitionGateMinimum else { continue }

                let alignedPatch = createAlignedInnerFacePatch(
                    from: uprightCGImage,
                    observation: obs,
                    roll: roll,
                    imageWidth: imageWidth,
                    imageHeight: imageHeight
                )

                let embedding = FaceEmbeddingModel.extractHybridEmbedding(
                    observation: obs,
                    alignedFacePatch: alignedPatch,
                    yaw: yaw,
                    pitch: pitch,
                    roll: roll
                )

                rawDetected.append(
                    DetectedFace(
                        id: UUID(),
                        assetID: assetID,
                        bbox: bbox,
                        quality: qualityScore,
                        embedding: embedding,
                        personID: nil,
                        confidence: confidenceScore,
                        reviewStatus: .unassigned,
                        yaw: yaw,
                        pitch: pitch,
                        roll: roll
                    )
                )
            }

            // Aplicar Non-Maximum Suppression para garantizar 1 sola detección por sujeto real
            let deduplicated = nonMaximumSuppression(rawDetected)
            continuation.resume(returning: deduplicated)
        }
    }

    // MARK: - 6. Recorte de Rostro para UI y para Modelo (Alineado por Ojos y Sin Fondo)
    static func cropFaceForDisplay(from image: UIImage, bbox: FaceBoundingBox) -> UIImage? {
        guard let cg = normalizeToUprightCGImage(image) else { return nil }
        let w = CGFloat(cg.width)
        let h = CGFloat(cg.height)

        let marginX = CGFloat(bbox.width) * w * 0.22
        let marginY = CGFloat(bbox.height) * h * 0.22
        let x = max(0, CGFloat(bbox.x) * w - marginX)
        let y = max(0, CGFloat(bbox.y) * h - marginY)
        let rectW = min(w - x, CGFloat(bbox.width) * w + marginX * 2)
        let rectH = min(h - y, CGFloat(bbox.height) * h + marginY * 2)

        guard rectW > 4, rectH > 4,
              let cropped = cg.cropping(to: CGRect(x: x, y: y, width: rectW, height: rectH)) else {
            return nil
        }
        return UIImage(cgImage: cropped)
    }

    private static func createAlignedInnerFacePatch(
        from image: CGImage,
        observation: VNFaceObservation,
        roll: Double,
        imageWidth: CGFloat,
        imageHeight: CGFloat
    ) -> CGImage? {
        let boundingBox = observation.boundingBox
        let x = boundingBox.origin.x * imageWidth
        let y = (1.0 - boundingBox.origin.y - boundingBox.height) * imageHeight
        let w = boundingBox.width * imageWidth
        let h = boundingBox.height * imageHeight

        // Recorte ajustado al óvalo facial interno (sin fondo externo que contamine el descriptor)
        let insetW = w * 0.04
        let insetH = h * 0.04
        let cropX = max(0, x + insetW)
        let cropY = max(0, y + insetH)
        let cropW = min(imageWidth - cropX, max(8, w - insetW * 2))
        let cropH = min(imageHeight - cropY, max(8, h - insetH * 2))

        let cropRect = CGRect(x: cropX, y: cropY, width: cropW, height: cropH)
        guard let cropped = image.cropping(to: cropRect) else { return nil }

        // Ángulo exacto entre ambos ojos si están disponibles
        var eyeAngle = roll
        if let landmarks = observation.landmarks,
           let lPts = landmarks.leftEye?.normalizedPoints, !lPts.isEmpty,
           let rPts = landmarks.rightEye?.normalizedPoints, !rPts.isEmpty {
            let lC = centroid(of: lPts)
            let rC = centroid(of: rPts)
            eyeAngle = Double(atan2(rC.y - lC.y, rC.x - lC.x))
        }

        let targetSize = CGSize(width: 96, height: 96)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let context = CGContext(
            data: nil,
            width: Int(targetSize.width),
            height: Int(targetSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return cropped
        }

        context.interpolationQuality = .high
        // Alinear horizontalmente los ojos rotando alrededor del centro
        context.translateBy(x: targetSize.width * 0.5, y: targetSize.height * 0.5)
        if abs(eyeAngle) < (.pi / 3.0) {
            context.rotate(by: CGFloat(-eyeAngle))
        }
        context.translateBy(x: -targetSize.width * 0.5, y: -targetSize.height * 0.5)
        context.draw(cropped, in: CGRect(origin: .zero, size: targetSize))
        return context.makeImage() ?? cropped
    }

    // MARK: - 7. Normalización L2 y Similitud de Coseno
    static func normalizeL2(_ vector: [Float]) -> [Float] {
        let sumSquares = vector.reduce(0.0) { $0 + ($1 * $1) }
        let norm = sqrt(sumSquares)
        guard norm > 0.00001 else { return vector }
        return vector.map { $0 / norm }
    }

    static func zeroCenterAndNormalizeL2(_ vector: [Float]) -> [Float] {
        guard !vector.isEmpty else { return vector }
        let mean = vector.reduce(0.0, +) / Float(vector.count)
        let centered = vector.map { $0 - mean }
        return normalizeL2(centered)
    }

    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 0.0 }
        if a.count == b.count {
            var dot: Float = 0.0
            for i in 0..<a.count {
                dot += a[i] * b[i]
            }
            return Double(max(-1.0, min(1.0, dot)))
        } else {
            // Compatibilidad cruzada si existe algún vector de dimensión anterior antes de reindexar
            let minCount = min(a.count, b.count)
            let sliceA = normalizeL2(Array(a.prefix(minCount)))
            let sliceB = normalizeL2(Array(b.prefix(minCount)))
            var dot: Float = 0.0
            for i in 0..<minCount {
                dot += sliceA[i] * sliceB[i]
            }
            return Double(max(-1.0, min(1.0, dot)))
        }
    }

    // MARK: - 8. Cálculo de Prototipos de Identidad (Multi-Prototype + Centroide)
    static func computePrototype(from embeddings: [[Float]]) -> [Float]? {
        let valid = embeddings.filter { !$0.isEmpty }
        guard !valid.isEmpty else { return nil }
        // Priorizar la dimensión actual (256)
        let targetDim = valid.contains(where: { $0.count == embeddingDimension }) ? embeddingDimension : valid[0].count
        let matching = valid.filter { $0.count == targetDim }
        guard !matching.isEmpty else { return nil }

        var accumulator = [Float](repeating: 0.0, count: targetDim)
        for emb in matching {
            for i in 0..<targetDim {
                accumulator[i] += emb[i]
            }
        }

        let count = Float(matching.count)
        let mean = accumulator.map { $0 / count }
        return normalizeL2(mean)
    }

    static func computeMultiPrototypes(from embeddings: [[Float]], maxPrototypes: Int = 4) -> [[Float]] {
        let valid = embeddings.filter { $0.count == embeddingDimension }
        let pool = valid.isEmpty ? embeddings.filter { !$0.isEmpty } : valid
        guard !pool.isEmpty else { return [] }
        guard pool.count > maxPrototypes else {
            return pool.map { normalizeL2($0) }
        }

        var prototypes: [[Float]] = []
        if let primary = computePrototype(from: pool) {
            prototypes.append(primary)
        }

        // Seleccionar prototipos adicionales por diversidad angular (K-Means++ / Furthest Point)
        while prototypes.count < maxPrototypes {
            var worstCandidate: [Float]?
            var lowestMaxSim: Double = 1.0

            for emb in pool {
                let maxSimToExisting = prototypes.map { cosineSimilarity(emb, $0) }.max() ?? 1.0
                if maxSimToExisting < lowestMaxSim {
                    lowestMaxSim = maxSimToExisting
                    worstCandidate = emb
                }
            }

            if let candidate = worstCandidate, lowestMaxSim < 0.85 {
                // Promediar el candidato con sus vecinos cercanos del mismo ángulo
                let neighbors = pool.filter { cosineSimilarity($0, candidate) >= 0.72 }
                if let clusterProto = computePrototype(from: neighbors) {
                    prototypes.append(clusterProto)
                } else {
                    prototypes.append(normalizeL2(candidate))
                }
            } else {
                break
            }
        }

        return prototypes
    }

    // MARK: - 9. Evaluación de Identidad Ponderada
    static func evaluateIdentityAffinity(
        embedding: [Float],
        person: MemoryPerson,
        facesCatalog: [UUID: DetectedFace]
    ) -> Double {
        var protoScores: [Double] = []
        for proto in person.allPrototypes {
            protoScores.append(cosineSimilarity(embedding, proto))
        }
        let bestProtoScore = protoScores.max()

        var exemplarScores: [Double] = []
        for exemplarID in person.exemplarFaceIDs.prefix(35) {
            if let ex = facesCatalog[exemplarID] {
                exemplarScores.append(cosineSimilarity(embedding, ex.embedding))
            }
        }

        let sortedExemplars = exemplarScores.sorted(by: >)
        let topK = Array(sortedExemplars.prefix(3))
        let bestExemplar = sortedExemplars.first
        let meanTop3: Double? = topK.isEmpty ? nil : (topK.reduce(0.0, +) / Double(topK.count))

        switch (bestProtoScore, meanTop3, bestExemplar) {
        case let (.some(pScore), .some(eMean), .some(eMax)):
            // Si hay una coincidencia directa muy fuerte con un exemplar específico (misma pose/luz), darle peso
            let blendedExemplar = (eMax * 0.55) + (eMean * 0.45)
            return max(eMax * 0.94, (pScore * 0.50) + (blendedExemplar * 0.50))
        case let (.some(pScore), .none, _):
            return pScore
        case let (.none, .some(eMean), .some(eMax)):
            return (eMax * 0.60) + (eMean * 0.40)
        default:
            return 0.0
        }
    }

    // MARK: - 10. Confidence Engine: Top-1 vs Top-2 Margin & Open-Set Classification
    static func classifyFace(
        _ face: DetectedFace,
        against people: [MemoryPerson],
        facesCatalog: [UUID: DetectedFace]
    ) -> (personID: UUID?, confidence: Double, zone: FaceMatchResult.ConfidenceZone) {
        guard !people.isEmpty, face.quality >= recognitionGateMinimum else {
            return (nil, 0.0, .low)
        }

        var candidateScores: [(person: MemoryPerson, score: Double)] = []
        for person in people {
            let score = evaluateIdentityAffinity(embedding: face.embedding, person: person, facesCatalog: facesCatalog)
            if score > 0.0 {
                candidateScores.append((person, score))
            }
        }

        candidateScores.sort { $0.score > $1.score }

        guard let top1 = candidateScores.first else {
            return (nil, 0.0, .low)
        }

        // Si solo hay 1 persona registrada en la biblioteca, no exigir margen contra un segundo inexistente
        let margin: Double
        if candidateScores.count > 1 {
            margin = top1.score - candidateScores[1].score
        } else {
            margin = 1.0
        }

        if top1.score >= thresholdAccept && margin >= autoMargin {
            return (top1.person.id, top1.score, .high)
        } else if top1.score >= thresholdReview {
            return (top1.person.id, top1.score, .review)
        } else {
            return (nil, max(0.0, top1.score), .low)
        }
    }

    // MARK: - 11. Multi-Face Photo Conflict Resolution
    static func classifyAndResolveFaces(
        _ faces: [DetectedFace],
        against people: [MemoryPerson],
        facesCatalog: [UUID: DetectedFace]
    ) -> [(face: DetectedFace, personID: UUID?, confidence: Double, zone: FaceMatchResult.ConfidenceZone)] {
        var initialResults: [(face: DetectedFace, personID: UUID?, confidence: Double, zone: FaceMatchResult.ConfidenceZone)] = []

        for face in faces {
            let res = classifyFace(face, against: people, facesCatalog: facesCatalog)
            initialResults.append((face, res.personID, res.confidence, res.zone))
        }

        var assignedPersons: [UUID: Int] = [:]
        for (index, item) in initialResults.enumerated() {
            guard let personID = item.personID else { continue }
            if let existingIndex = assignedPersons[personID] {
                if item.confidence > initialResults[existingIndex].confidence {
                    initialResults[existingIndex].personID = nil
                    initialResults[existingIndex].zone = .low
                    assignedPersons[personID] = index
                } else {
                    initialResults[index].personID = nil
                    initialResults[index].zone = .low
                }
            } else {
                assignedPersons[personID] = index
            }
        }

        return initialResults
    }

    // MARK: - 12. Smart Enrollment Gate y Diversidad de Exemplars
    static func shouldEnrollFace(
        _ face: DetectedFace,
        for person: MemoryPerson?,
        facesCatalog: [UUID: DetectedFace]
    ) -> Bool {
        guard let person = person else { return false }
        guard face.quality >= enrollmentGateMinimum else { return false }

        let existingEmbeddings: [[Float]] = person.exemplarFaceIDs.compactMap { facesCatalog[$0]?.embedding }
        for existing in existingEmbeddings {
            if cosineSimilarity(face.embedding, existing) > 0.965 {
                return false
            }
        }
        return true
    }

    // MARK: - 13. Búsqueda por Fotografía (Search by Photo)
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
            let score = evaluateIdentityAffinity(embedding: queryFace.embedding, person: person, facesCatalog: facesCatalog)
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
                    confidence: max(0.0, score),
                    zone: zone,
                    albumCount: personAlbums.count,
                    assetCount: personAssets.count,
                    relatedSectionNames: relatedSections,
                    relatedAlbumNames: relatedAlbums
                )
            )
        }

        return results.sorted { $0.confidence > $1.confidence }
    }

    // MARK: - 14. Clustering Inteligente de Rostros Sin Identificar (Single-Linkage + Centroid)
    static func clusterFaces(
        unassignedFaces: [DetectedFace],
        similarityThreshold: Double = 0.56
    ) -> [FaceCluster] {
        let validFaces = unassignedFaces
            .filter { $0.quality >= recognitionGateMinimum && !$0.embedding.isEmpty }
            .sorted { $0.quality > $1.quality }

        guard !validFaces.isEmpty else { return [] }

        var clusters: [[DetectedFace]] = []
        var centroids: [[Float]] = []

        for face in validFaces {
            var bestClusterIdx: Int?
            var bestSim: Double = -1.0

            for (idx, cluster) in clusters.enumerated() {
                let centroidSim = cosineSimilarity(face.embedding, centroids[idx])
                let maxMemberSim = cluster.prefix(8).map { cosineSimilarity(face.embedding, $0.embedding) }.max() ?? 0.0
                let effectiveSim = max(centroidSim, maxMemberSim * 0.95)

                if effectiveSim >= similarityThreshold && effectiveSim > bestSim {
                    bestSim = effectiveSim
                    bestClusterIdx = idx
                }
            }

            if let idx = bestClusterIdx {
                clusters[idx].append(face)
                if let updatedProto = computePrototype(from: clusters[idx].map(\.embedding)) {
                    centroids[idx] = updatedProto
                }
            } else {
                clusters.append([face])
                centroids.append(face.embedding)
            }
        }

        // Ordenar clusters: primero los que tienen más fotos, permitiendo también grupos de 1 rostro claro para nombrado rápido
        let sortedClusters = clusters.sorted { a, b in
            if a.count != b.count { return a.count > b.count }
            return (a.first?.quality ?? 0) > (b.first?.quality ?? 0)
        }

        return sortedClusters.compactMap { clusterGroup in
            guard let representative = clusterGroup.max(by: { $0.quality < $1.quality }) else { return nil }
            return FaceCluster(
                id: representative.id, // ID determinista basado en el rostro representante
                faceIDs: clusterGroup.map(\.id),
                representativeFaceID: representative.id,
                suggestedName: nil
            )
        }
    }
}

// MARK: - FaceEmbeddingModel (Descriptor Biométrico Híbrido 256D Invariante)
enum FaceEmbeddingModel {

    static func extractHybridEmbedding(
        observation: VNFaceObservation,
        alignedFacePatch: CGImage?,
        yaw: Double,
        pitch: Double,
        roll: Double
    ) -> [Float] {
        // Subespacio 1 (96D): Geometría craneofacial Procrustes invariante a escala, rotación y traslación
        let geoSubspace = extractProcrustesGeometricSubspace(observation: observation, yaw: yaw, pitch: pitch)

        // Subespacio 2 (96D): Textura HOG + Contraste Local Z-Score en óvalo facial interno (invariante a iluminación y fondo)
        let hogSubspace: [Float]
        if let patch = alignedFacePatch {
            hogSubspace = extractAlignedAppearanceSubspace(from: patch)
        } else {
            hogSubspace = [Float](repeating: 0.0, count: 96)
        }

        // Subespacio 3 (64D): Proyección neuronal profunda centrada en cero (CoreML / Vision FeaturePrint)
        let deepSubspace: [Float]
        if let patch = alignedFacePatch {
            deepSubspace = extractDeepNeuralSubspace(from: patch)
        } else {
            deepSubspace = [Float](repeating: 0.0, count: 64)
        }

        // Fusión ponderada de los 3 subespacios ortogonales (Total = 256 dimensiones)
        var combined = [Float](repeating: 0.0, count: FaceEngine.embeddingDimension)
        for i in 0..<96 {
            combined[i] = geoSubspace[i] * 0.62
        }
        for i in 0..<96 {
            combined[96 + i] = hogSubspace[i] * 0.58
        }
        for i in 0..<64 {
            combined[192 + i] = deepSubspace[i] * 0.52
        }

        return FaceEngine.normalizeL2(combined)
    }

    // MARK: - Subespacio 1: Procrustes Canonical Craniofacial Geometry (96D)
    private static func extractProcrustesGeometricSubspace(
        observation: VNFaceObservation,
        yaw: Double,
        pitch: Double
    ) -> [Float] {
        var rawFeatures = [Float](repeating: 0.0, count: 96)
        guard let landmarks = observation.landmarks else { return rawFeatures }

        let lEyePts = landmarks.leftEye?.normalizedPoints ?? []
        let rEyePts = landmarks.rightEye?.normalizedPoints ?? []
        let nosePts = landmarks.nose?.normalizedPoints ?? []
        let noseCrestPts = landmarks.noseCrest?.normalizedPoints ?? []
        let outerLipsPts = landmarks.outerLips?.normalizedPoints ?? []
        let innerLipsPts = landmarks.innerLips?.normalizedPoints ?? []
        let lBrowPts = landmarks.leftEyebrow?.normalizedPoints ?? []
        let rBrowPts = landmarks.rightEyebrow?.normalizedPoints ?? []
        let contourPts = landmarks.faceContour?.normalizedPoints ?? []

        guard !lEyePts.isEmpty, !rEyePts.isEmpty else { return rawFeatures }

        let lEyeCenter = meanPoint(lEyePts)
        let rEyeCenter = meanPoint(rEyePts)
        let eyesMid = CGPoint(x: (lEyeCenter.x + rEyeCenter.x) * 0.5, y: (lEyeCenter.y + rEyeCenter.y) * 0.5)

        let dx = Double(rEyeCenter.x - lEyeCenter.x)
        let dy = Double(rEyeCenter.y - lEyeCenter.y)
        let angle = atan2(dy, dx)
        let cosA = cos(-angle)
        let sinA = sin(-angle)

        // Compensación de escorzo horizontal por guiñada (yaw)
        let yawScale = max(0.65, cos(yaw))
        let pitchScale = max(0.70, cos(pitch))
        let eyeDist = max(0.05, hypot(dx, dy) / yawScale)

        // Transformación Procrustes al marco canónico interocular:
        // Ojo izquierdo queda en (-0.5, 0), ojo derecho en (+0.5, 0)
        func canonical(_ pt: CGPoint) -> (x: Float, y: Float) {
            let tx = Double(pt.x - eyesMid.x)
            let ty = Double(pt.y - eyesMid.y)
            let rx = (tx * cosA - ty * sinA) / (eyeDist * yawScale)
            let ry = (tx * sinA + ty * cosA) / (eyeDist * pitchScale)
            return (Float(rx), Float(ry))
        }

        func spanWidth(_ pts: [CGPoint]) -> Float {
            guard pts.count >= 2 else { return 0 }
            let xs = pts.map { canonical($0).x }
            return (xs.max() ?? 0) - (xs.min() ?? 0)
        }

        func spanHeight(_ pts: [CGPoint]) -> Float {
            guard pts.count >= 2 else { return 0 }
            let ys = pts.map { canonical($0).y }
            return (ys.max() ?? 0) - (ys.min() ?? 0)
        }

        // 1. Proporciones antropométricas invariantes (índices 0..<24)
        let noseC = canonical(meanPoint(nosePts))
        let mouthC = canonical(meanPoint(outerLipsPts))
        let lBrowC = canonical(meanPoint(lBrowPts))
        let rBrowC = canonical(meanPoint(rBrowPts))

        let lEyeW = spanWidth(lEyePts)
        let rEyeW = spanWidth(rEyePts)
        let lEyeH = spanHeight(lEyePts)
        let rEyeH = spanHeight(rEyePts)
        let noseW = spanWidth(nosePts)
        let noseH = spanHeight(nosePts)
        let mouthW = spanWidth(outerLipsPts)
        let mouthH = spanHeight(outerLipsPts)
        let browW = (spanWidth(lBrowPts) + spanWidth(rBrowPts)) * 0.5
        let jawW = spanWidth(contourPts)
        let jawH = spanHeight(contourPts)

        // Diferencias centradas respecto a medias anatómicas humanas estándar
        rawFeatures[0] = ((lEyeW + rEyeW) * 0.5 - 0.42) * 4.0
        rawFeatures[1] = ((lEyeH / max(lEyeW, 0.05) + rEyeH / max(rEyeW, 0.05)) * 0.5 - 0.32) * 5.0
        rawFeatures[2] = (noseW - 0.58) * 3.5
        rawFeatures[3] = (noseH - 0.52) * 3.5
        rawFeatures[4] = (abs(noseC.y) - 0.56) * 3.5
        rawFeatures[5] = (mouthW - 0.82) * 3.0
        rawFeatures[6] = (mouthH / max(mouthW, 0.1) - 0.28) * 4.0
        rawFeatures[7] = (abs(mouthC.y) - 1.08) * 3.0
        rawFeatures[8] = (abs(mouthC.y - noseC.y) - 0.52) * 4.0
        rawFeatures[9] = (noseW / max(mouthW, 0.1) - 0.70) * 3.5
        rawFeatures[10] = (((lBrowC.y + rBrowC.y) * 0.5) - 0.34) * 4.0
        rawFeatures[11] = (browW - 0.52) * 3.5
        rawFeatures[12] = (jawW - 1.85) * 2.0
        rawFeatures[13] = (jawH - 1.65) * 2.0
        rawFeatures[14] = (jawW / max(jawH, 0.2) - 1.12) * 2.5
        rawFeatures[15] = (mouthW / max(jawW, 0.2) - 0.44) * 3.5

        // 2. Muestreo Procrustes uniforme de contornos anatómicos (índices 16..<96)
        var idx = 16
        func encodeResampled(_ pts: [CGPoint], count: Int) {
            guard !pts.isEmpty else {
                idx += count * 2
                return
            }
            for k in 0..<count {
                guard idx + 1 < 96 else { return }
                let pos = Double(k) * Double(max(0, pts.count - 1)) / Double(max(1, count - 1))
                let lo = Int(floor(pos))
                let hi = min(pts.count - 1, lo + 1)
                let frac = CGFloat(pos - Double(lo))
                let interp = CGPoint(
                    x: pts[lo].x + (pts[hi].x - pts[lo].x) * frac,
                    y: pts[lo].y + (pts[hi].y - pts[lo].y) * frac
                )
                let c = canonical(interp)
                rawFeatures[idx] = c.x
                rawFeatures[idx + 1] = c.y
                idx += 2
            }
        }

        encodeResampled(lEyePts, count: 5)       // 10 dims (16..<26)
        encodeResampled(rEyePts, count: 5)       // 10 dims (26..<36)
        encodeResampled(lBrowPts, count: 4)      // 8 dims  (36..<44)
        encodeResampled(rBrowPts, count: 4)      // 8 dims  (44..<52)
        encodeResampled(nosePts, count: 6)       // 12 dims (52..<64)
        encodeResampled(noseCrestPts, count: 3)  // 6 dims  (64..<70)
        encodeResampled(outerLipsPts, count: 6)  // 12 dims (70..<82)
        encodeResampled(innerLipsPts, count: 3)  // 6 dims  (82..<88)
        encodeResampled(contourPts, count: 4)    // 8 dims  (88..<96)

        return FaceEngine.zeroCenterAndNormalizeL2(rawFeatures)
    }

    private static func meanPoint(_ pts: [CGPoint]) -> CGPoint {
        guard !pts.isEmpty else { return .zero }
        var sx: CGFloat = 0
        var sy: CGFloat = 0
        for p in pts {
            sx += p.x
            sy += p.y
        }
        return CGPoint(x: sx / CGFloat(pts.count), y: sy / CGFloat(pts.count))
    }

    // MARK: - Subespacio 2: HOG + Contraste Zonal Invariante a la Luz en Óvalo Interno (96D)
    private static func extractAlignedAppearanceSubspace(from patch: CGImage) -> [Float] {
        let gridSize = 32
        let colorSpace = CGColorSpaceCreateDeviceGray()
        var pixels = [UInt8](repeating: 0, count: gridSize * gridSize)

        guard let context = CGContext(
            data: &pixels,
            width: gridSize,
            height: gridSize,
            bitsPerComponent: 8,
            bytesPerRow: gridSize,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return [Float](repeating: 0.0, count: 96)
        }

        context.interpolationQuality = .medium
        context.draw(patch, in: CGRect(x: 0, y: 0, width: gridSize, height: gridSize))

        // Normalización Z-score sobre el óvalo interno para eliminar sombras y diferencias de exposición
        var floatPixels = pixels.map { Float($0) / 255.0 }
        let meanLum = floatPixels.reduce(0.0, +) / Float(floatPixels.count)
        let variance = floatPixels.reduce(0.0) { $0 + ($1 - meanLum) * ($1 - meanLum) } / Float(floatPixels.count)
        let stdLum = max(0.05, sqrt(variance))
        for i in 0..<floatPixels.count {
            floatPixels[i] = (floatPixels[i] - meanLum) / stdLum
        }

        var descriptor = [Float](repeating: 0.0, count: 96)
        var outIdx = 0

        // 1. Bloques espaciales 4x4 en región central de ojos-nariz-boca (16 bloques x 4 orientación/contraste = 64 dims)
        for by in 0..<4 {
            for bx in 0..<4 {
                let startY = 2 + by * 7
                let startX = 2 + bx * 7
                var sumGxPos: Float = 0
                var sumGxNeg: Float = 0
                var sumGyPos: Float = 0
                var sumGyNeg: Float = 0

                for y in startY..<(startY + 6) {
                    for x in startX..<(startX + 6) {
                        let gx = floatPixels[y * gridSize + (x + 1)] - floatPixels[y * gridSize + (x - 1)]
                        let gy = floatPixels[(y + 1) * gridSize + x] - floatPixels[(y - 1) * gridSize + x]
                        if gx >= 0 { sumGxPos += gx } else { sumGxNeg -= gx }
                        if gy >= 0 { sumGyPos += gy } else { sumGyNeg -= gy }
                    }
                }
                if outIdx + 3 < 64 {
                    descriptor[outIdx] = sumGxPos
                    descriptor[outIdx + 1] = sumGxNeg
                    descriptor[outIdx + 2] = sumGyPos
                    descriptor[outIdx + 3] = sumGyNeg
                    outIdx += 4
                }
            }
        }

        // 2. Perfil de luminancia simétrica (32 dims: índices 64..<96)
        for i in 0..<32 {
            let r = (i / 4) * 3 + 4
            let c = (i % 4) * 3 + 4
            let leftVal = floatPixels[r * gridSize + c]
            let rightVal = floatPixels[r * gridSize + (gridSize - 1 - c)]
            descriptor[64 + i] = (leftVal + rightVal) * 0.5
        }

        return FaceEngine.zeroCenterAndNormalizeL2(descriptor)
    }

    // MARK: - Subespacio 3: Proyección Neuronal Profunda Centrada en Cero (64D)
    private static func extractDeepNeuralSubspace(from faceCrop: CGImage) -> [Float] {
        let request = VNGenerateImageFeaturePrintRequest()
        request.imageCropAndScaleOption = .scaleFill
        let handler = VNImageRequestHandler(cgImage: faceCrop, orientation: .up, options: [:])
        do {
            try handler.perform([request])
            if let observation = request.results?.first as? VNFeaturePrintObservation {
                let count = observation.elementCount
                guard count > 0 else { return [Float](repeating: 0.0, count: 64) }

                var rawFloats = [Float](repeating: 0.0, count: count)
                if observation.elementType == .float {
                    _ = observation.data.withUnsafeBytes { rawBuffer in
                        if let ptr = rawBuffer.bindMemory(to: Float.self).baseAddress {
                            for i in 0..<count { rawFloats[i] = ptr[i] }
                        }
                    }
                } else if observation.elementType == .double {
                    _ = observation.data.withUnsafeBytes { rawBuffer in
                        if let ptr = rawBuffer.bindMemory(to: Double.self).baseAddress {
                            for i in 0..<count { rawFloats[i] = Float(ptr[i]) }
                        }
                    }
                }

                // Centrar en cero las activaciones antes de proyectar a 64 dimensiones
                let centered = FaceEngine.zeroCenterAndNormalizeL2(rawFloats)
                var projected = [Float](repeating: 0.0, count: 64)
                for (i, val) in centered.enumerated() {
                    let sign: Float = ((i / 64) % 2 == 0) ? 1.0 : -1.0
                    projected[i % 64] += val * sign
                }
                return FaceEngine.zeroCenterAndNormalizeL2(projected)
            }
        } catch {
            // Ignorar silenciosamente en simulador si ANE no está disponible
        }
        return [Float](repeating: 0.0, count: 64)
    }
}
