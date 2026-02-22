import Vision
import AVFoundation
import CoreGraphics // Import CoreGraphics for CGFloat

final class PoseEstimator {

    private let request = VNDetectHumanBodyPoseRequest()

    func process(sampleBuffer: CMSampleBuffer,
                 completion: @escaping (VNHumanBodyPoseObservation?) -> Void) {

        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            completion(nil)
            return
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .leftMirrored)

        do {
            try handler.perform([request])
        } catch {
            completion(nil)
            return
        }

        guard let obs = request.results?.first else {
            completion(nil)
            return
        }
        completion(obs)
    }

    // MARK: - Score
    func score(current: [VNHumanBodyPoseObservation.JointName: CGPoint],
               target: [VNHumanBodyPoseObservation.JointName: CGPoint]) -> Double {

        var total: CGFloat = 0
        var count: CGFloat = 0

        for (joint, targetPoint) in target {
            guard let currentPoint = current[joint] else { continue }
            let distance = hypot(currentPoint.x - targetPoint.x, currentPoint.y - targetPoint.y)
            total += distance
            count += 1
        }

        guard count > 0 else { return 0 }

        let avg = total / count

        // 距離が小さいほど高スコア（0.0 ~ 1.0）
        return max(0, 1 - Double(avg * 2))
    }
}
