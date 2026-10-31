import Vision
import CoreVideo
import SleightCore

/// Runs Vision's hand pose detector (Neural Engine) and converts results into
/// mirrored, aspect-correct `HandFrame`s.
final class VisionHandDetector {
    private let request: VNDetectHumanHandPoseRequest
    var mirror = true

    private static let jointMap: [(SleightCore.Joint, VNHumanHandPoseObservation.JointName)] = [
        (.wrist, .wrist),
        (.thumbCMC, .thumbCMC), (.thumbMP, .thumbMP), (.thumbIP, .thumbIP), (.thumbTip, .thumbTip),
        (.indexMCP, .indexMCP), (.indexPIP, .indexPIP), (.indexDIP, .indexDIP), (.indexTip, .indexTip),
        (.middleMCP, .middleMCP), (.middlePIP, .middlePIP), (.middleDIP, .middleDIP), (.middleTip, .middleTip),
        (.ringMCP, .ringMCP), (.ringPIP, .ringPIP), (.ringDIP, .ringDIP), (.ringTip, .ringTip),
        (.littleMCP, .littleMCP), (.littlePIP, .littlePIP), (.littleDIP, .littleDIP), (.littleTip, .littleTip),
    ]

    init() {
        request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 2
    }

    func detect(in pixelBuffer: CVPixelBuffer, aspect: Double) -> [HandFrame] {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        guard let results = request.results else { return [] }
        return results.compactMap { convert($0, aspect: aspect) }
    }

    private func convert(_ obs: VNHumanHandPoseObservation, aspect: Double) -> HandFrame? {
        guard let recognized = try? obs.recognizedPoints(.all) else { return nil }
        var points = [JointPoint?](repeating: nil, count: SleightCore.Joint.allCases.count)
        for (joint, name) in VisionHandDetector.jointMap {
            guard let p = recognized[name], p.confidence > 0 else { continue }
            // Vision: normalised, origin bottom-left. Ours: origin top-left, y down,
            // mirrored like a selfie, x scaled by aspect so distances are true.
            let x = mirror ? 1 - Double(p.location.x) : Double(p.location.x)
            let y = 1 - Double(p.location.y)
            points[joint.rawValue] = JointPoint(Vec2(x * aspect, y), confidence: p.confidence)
        }
        let chirality: SleightCore.Chirality
        switch obs.chirality {
        case .left: chirality = .left
        case .right: chirality = .right
        default: chirality = .unknown
        }
        return HandFrame(points: points, chirality: chirality, confidence: Double(obs.confidence))
    }
}

/// Mean brightness of the luma plane, sampled sparsely (a few hundred reads).
func meanLuma(_ pixelBuffer: CVPixelBuffer) -> Double {
    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
    guard CVPixelBufferGetPlaneCount(pixelBuffer) > 0,
          let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { return 128 }
    let w = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
    let h = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
    let stride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
    let ptr = base.assumingMemoryBound(to: UInt8.self)
    var sum = 0, n = 0
    let stepX = max(w / 32, 1), stepY = max(h / 24, 1)
    var y = stepY / 2
    while y < h {
        var x = stepX / 2
        while x < w {
            sum += Int(ptr[y * stride + x]); n += 1
            x += stepX
        }
        y += stepY
    }
    return n > 0 ? Double(sum) / Double(n) : 128
}
