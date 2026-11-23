import CoreGraphics
import Foundation
import os
import Vision

/// 100% offline Apple Vision engine classifying person count, faces, eye openness,
/// framing, and body poses directly from rendered RAW/compressed pixel buffers.
package actor PhotoVisionAnalyzer {
    private let logger = Logger(subsystem: "com.kairosvisuals.photopic", category: "PhotoVisionAnalyzer")

    package init() {}

    package func analyze(cgImage: CGImage, includeBodyPose: Bool = true) -> PhotoVisionTags {
        let faceLandmarksReq = VNDetectFaceLandmarksRequest()
        if VNDetectFaceLandmarksRequest.supportedRevisions.contains(VNDetectFaceLandmarksRequestRevision3) {
            faceLandmarksReq.revision = VNDetectFaceLandmarksRequestRevision3
        }
        let faceQualityReq = VNDetectFaceCaptureQualityRequest()
        let bodyPoseReq = VNDetectHumanBodyPoseRequest()
        let humanRectReq = VNDetectHumanRectanglesRequest()
        humanRectReq.upperBodyOnly = false

        let requests: [VNRequest] = includeBodyPose
            ? [faceLandmarksReq, faceQualityReq, bodyPoseReq, humanRectReq]
            : [faceLandmarksReq, faceQualityReq]

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform(requests)
        } catch {
            logger.warning("Vision analysis warning: \(error.localizedDescription, privacy: .public)")
        }

        let rawFaces = (faceLandmarksReq.results ?? []).filter { face in
            let bb = face.boundingBox
            return face.confidence >= 0.62
                && bb.width >= 0.025
                && bb.height >= 0.025
                && (bb.width * bb.height) >= 0.0008
        }
        let faces = deduplicateOverlappingFaces(rawFaces)
        let qualityFaces = (faceQualityReq.results ?? []).filter { $0.confidence >= 0.60 }
        let poses = includeBodyPose
            ? (bodyPoseReq.results ?? []).filter { confidentJointCount(in: $0) >= 6 }
            : []
        let humanRects = includeBodyPose
            ? (humanRectReq.results ?? []).filter { rect in
                let bb = rect.boundingBox
                return rect.confidence >= 0.68 && bb.width >= 0.05 && bb.height >= 0.10
            }
            : []

        let personCount = estimateUniquePersonCount(faces: faces, poses: poses, humanRects: humanRects)
        var autoTags: [String] = []

        switch personCount {
        case 0:
            autoTags.append("Sin personas")
            return PhotoVisionTags(
                personCount: 0,
                faceCount: 0,
                hasClosedEyesWarning: false,
                autoTags: autoTags
            )
        case 1:
            autoTags.append("1 persona")
            autoTags.append("Individual")
        case 2:
            autoTags.append("2 personas")
            autoTags.append("Pareja")
        case 3...5:
            autoTags.append("\(personCount) personas")
            autoTags.append("Grupo")
        default:
            autoTags.append("\(personCount) personas")
            autoTags.append("Grupo grande")
        }

        appendFramingTags(faces: faces, poses: poses, humanRects: humanRects, into: &autoTags)
        let hasClosedEyes = appendEyeAndQualityTags(faces: faces, qualityFaces: qualityFaces, into: &autoTags)
        appendPoseTags(poses: poses, into: &autoTags)

        return PhotoVisionTags(
            personCount: personCount,
            faceCount: faces.count,
            hasClosedEyesWarning: hasClosedEyes,
            autoTags: deduplicate(autoTags)
        )
    }

    // MARK: - People Count Fusion

    private func estimateUniquePersonCount(
        faces: [VNFaceObservation],
        poses: [VNHumanBodyPoseObservation],
        humanRects: [VNDetectedObjectObservation]
    ) -> Int {
        var anchorsX: [CGFloat] = faces.map { $0.boundingBox.midX }

        for pose in poses {
            if let center = poseHorizontalCenter(pose) {
                let alreadyCounted = anchorsX.contains { abs($0 - center) < 0.085 }
                if !alreadyCounted {
                    anchorsX.append(center)
                }
            }
        }

        for rect in humanRects {
            let center = rect.boundingBox.midX
            let tolerance = max(0.08, rect.boundingBox.width * 0.42)
            let alreadyCounted = anchorsX.contains { abs($0 - center) < tolerance }
            if !alreadyCounted {
                anchorsX.append(center)
            }
        }

        return max(faces.count, anchorsX.count)
    }

    // MARK: - Framing, Eye Blink (EAR) & Quality

    private func appendFramingTags(
        faces: [VNFaceObservation],
        poses: [VNHumanBodyPoseObservation],
        humanRects: [VNDetectedObjectObservation],
        into tags: inout [String]
    ) {
        let maxFaceHeight = faces.map { $0.boundingBox.height }.max() ?? 0
        let maxHumanHeight = humanRects.map { $0.boundingBox.height }.max() ?? 0
        let hasFullBodyJoints = poses.contains { poseHasAnkles($0) }

        if maxFaceHeight >= 0.25 {
            tags.append("Primer plano")
        } else if hasFullBodyJoints || maxHumanHeight >= 0.65 {
            tags.append("Cuerpo entero")
        } else if maxFaceHeight >= 0.10 {
            tags.append("Plano medio")
        } else if !faces.isEmpty {
            tags.append("Retrato")
        }
    }

    private func appendEyeAndQualityTags(
        faces: [VNFaceObservation],
        qualityFaces: [VNFaceObservation],
        into tags: inout [String]
    ) -> Bool {
        guard !faces.isEmpty else { return false }

        var anyClosed = false
        var anyOpenVerified = false

        for face in faces {
            // Skip distant faces and steep side profiles where eye landmarks compress artificially.
            guard face.boundingBox.height >= 0.055 else { continue }
            if let yaw = face.yaw?.doubleValue, abs(yaw) > 0.55 { continue }
            if let pitch = face.pitch?.doubleValue, abs(pitch) > 0.45 { continue }

            guard let landmarks = face.landmarks else { continue }
            let leftEAR = eyeAspectRatio(landmarks.leftEye)
            let rightEAR = eyeAspectRatio(landmarks.rightEye)

            if let l = leftEAR, let r = rightEAR {
                let avgEAR = (l + r) * 0.5
                if l < 0.125 && r < 0.125 && avgEAR < 0.120 {
                    anyClosed = true
                } else if l >= 0.145 || r >= 0.145 {
                    anyOpenVerified = true
                }
            }
        }

        if anyClosed {
            tags.append("Ojos cerrados")
        } else if anyOpenVerified {
            tags.append("Ojos abiertos")
        }

        if let bestQuality = qualityFaces.compactMap(\.faceCaptureQuality).max(), bestQuality >= 0.65 {
            tags.append("Rostro nítido")
        }

        return anyClosed
    }

    private func eyeAspectRatio(_ region: VNFaceLandmarkRegion2D?) -> CGFloat? {
        guard let region, region.pointCount >= 4 else { return nil }
        let pts = region.normalizedPoints
        let xs = pts.map(\.x)
        let ys = pts.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else {
            return nil
        }
        let width = maxX - minX
        guard width >= 0.04 else { return nil }
        return (maxY - minY) / width
    }

    private func deduplicateOverlappingFaces(_ faces: [VNFaceObservation]) -> [VNFaceObservation] {
        let sorted = faces.sorted { $0.confidence > $1.confidence }
        var kept: [VNFaceObservation] = []
        var keptBoxes: [CGRect] = []
        for candidate in sorted {
            let candidateBox = candidate.boundingBox
            var overlaps = false
            for existingBox in keptBoxes {
                if Self.rectIoU(existingBox, candidateBox) > 0.45 {
                    overlaps = true
                    break
                }
            }
            if !overlaps {
                kept.append(candidate)
                keptBoxes.append(candidateBox)
            }
        }
        return kept
    }

    nonisolated private static func rectIoU(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = a.intersection(b)
        guard !intersection.isNull && !intersection.isEmpty else { return 0 }
        let interArea = intersection.width * intersection.height
        let unionArea = (a.width * a.height) + (b.width * b.height) - interArea
        guard unionArea > 0 else { return 0 }
        return interArea / unionArea
    }

    // MARK: - 19-Joint Body Pose Classification

    private func appendPoseTags(poses: [VNHumanBodyPoseObservation], into tags: inout [String]) {
        for pose in poses {
            guard let pts = try? pose.recognizedPoints(.all) else { continue }
            let minConf: Float = 0.45

            let lShoulder = validPoint(pts[.leftShoulder], minConfidence: minConf)
            let rShoulder = validPoint(pts[.rightShoulder], minConfidence: minConf)
            let lElbow = validPoint(pts[.leftElbow], minConfidence: minConf)
            let rElbow = validPoint(pts[.rightElbow], minConfidence: minConf)
            let lWrist = validPoint(pts[.leftWrist], minConfidence: minConf)
            let rWrist = validPoint(pts[.rightWrist], minConfidence: minConf)
            let lHip = validPoint(pts[.leftHip], minConfidence: minConf)
            let rHip = validPoint(pts[.rightHip], minConfidence: minConf)
            let lKnee = validPoint(pts[.leftKnee], minConfidence: minConf)
            let rKnee = validPoint(pts[.rightKnee], minConfidence: minConf)

            // Vision coordinates have origin at bottom-left (Y increases upward).
            if let lw = lWrist, let ls = lShoulder, lElbow != nil, lw.y > ls.y + 0.06 {
                tags.append("Brazos arriba")
            } else if let rw = rWrist, let rs = rShoulder, rElbow != nil, rw.y > rs.y + 0.06 {
                tags.append("Brazos arriba")
            }

            if let lw = lWrist, let rw = rWrist, let lh = lHip, let rh = rHip,
               lElbow != nil, rElbow != nil {
                let hipSpan = max(0.08, hypot(rh.x - lh.x, rh.y - lh.y))
                let hipRadius = min(0.14, max(0.06, hipSpan * 0.65))
                let leftNearHip = hypot(lw.x - lh.x, lw.y - lh.y) < hipRadius
                let rightNearHip = hypot(rw.x - rh.x, rw.y - rh.y) < hipRadius
                if leftNearHip && rightNearHip {
                    tags.append("Manos en cintura")
                }
            }

            if let shoulderMidY = midpointY(lShoulder, rShoulder),
               let hipMidY = midpointY(lHip, rHip),
               let kneeMidY = midpointY(lKnee, rKnee) {
                let torso = max(0.06, shoulderMidY - hipMidY)
                let thighDrop = hipMidY - kneeMidY
                tags.append(thighDrop < torso * 0.50 ? "Sentado" : "De pie")
            } else if poseHasAnkles(pose) {
                tags.append("De pie")
            }

            if let ls = lShoulder, let rs = rShoulder {
                let shoulderSpan = hypot(rs.x - ls.x, rs.y - ls.y)
                if shoulderSpan >= 0.06 {
                    let tilt = abs(atan2(rs.y - ls.y, max(0.001, abs(rs.x - ls.x)))) * (180.0 / .pi)
                    if tilt > 18.0 {
                        tags.append("Pose dinámica")
                    }
                }
            }
        }
    }

    private func confidentJointCount(in pose: VNHumanBodyPoseObservation) -> Int {
        guard let pts = try? pose.recognizedPoints(.all) else { return 0 }
        return pts.values.filter { $0.confidence >= 0.40 }.count
    }

    private func poseHorizontalCenter(_ pose: VNHumanBodyPoseObservation) -> CGFloat? {
        guard let pts = try? pose.recognizedPoints(.all) else { return nil }
        let validX = pts.values.filter { $0.confidence >= 0.40 }.map { $0.location.x }
        guard !validX.isEmpty else { return nil }
        return validX.reduce(0, +) / CGFloat(validX.count)
    }

    private func poseHasAnkles(_ pose: VNHumanBodyPoseObservation) -> Bool {
        guard let pts = try? pose.recognizedPoints(.all) else { return false }
        return (pts[.leftAnkle]?.confidence ?? 0) >= 0.45 || (pts[.rightAnkle]?.confidence ?? 0) >= 0.45
    }

    private func validPoint(_ pt: VNRecognizedPoint?, minConfidence: Float) -> CGPoint? {
        guard let pt, pt.confidence >= minConfidence else { return nil }
        return pt.location
    }

    private func midpointY(_ a: CGPoint?, _ b: CGPoint?) -> CGFloat? {
        switch (a, b) {
        case (let p1?, let p2?): return (p1.y + p2.y) * 0.5
        case (let p1?, nil): return p1.y
        case (nil, let p2?): return p2.y
        case (nil, nil): return nil
        }
    }

    private func deduplicate(_ input: [String]) -> [String] {
        var seen = Set<String>()
        return input.filter { seen.insert($0).inserted }
    }
}
