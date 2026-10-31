import Foundation

/// Features derived from one `HandFrame`: the things gestures are made of.
public struct HandPose: Sendable {
    public let frame: HandFrame
    /// Hand size in frame heights: max(wrist→middle knuckle, 1.3 × knuckle width).
    /// The max keeps it stable when the hand tilts in either axis.
    public let scale: Double
    /// A point on the palm that barely moves when fingers move: weighted centroid
    /// of the wrist and the four knuckles. The cursor follows this, not a
    /// fingertip, so pinching does not drag the cursor.
    public let anchor: Vec2
    public let wrist: Vec2
    /// Tip-to-wrist / knuckle-to-wrist, per finger. ~1.8 extended, ~0.8 curled.
    /// nil when the tip was not confidently tracked.
    public let extensionRatio: [Double?]
    /// Per finger extended state, with hysteresis applied against `previous`.
    public let extended: [Bool]
    /// Thumb tip to index tip, in hand scales.
    public let pinchIndex: Double
    /// Thumb tip to middle tip, in hand scales.
    public let pinchMiddle: Double
    /// Signed area of wrist→index knuckle→little knuckle, normalised by scale².
    /// Its sign flips when the hand turns over (palm vs back toward camera),
    /// independent of in-plane rotation.
    public let orientation: Double
    /// Mean joint confidence (missing joints count as 0).
    public let confidence: Double

    public var extendedCount: Int { extended.filter { $0 }.count }
    public var isOpenPalm: Bool { extended.allSatisfy { $0 } }

    /// All four fingers curled, with the index clearly folded (so a pinch never
    /// reads as a fist).
    public func isFist(config: MaestroConfig) -> Bool {
        guard extendedCount == 0 else { return false }
        for r in extensionRatio {
            if let r, r > config.fingerCurledBelow { return false }
        }
        return true
    }

    /// Index and middle up, ring and little folded.
    public var isPeace: Bool {
        extended[0] && extended[1] && !extended[2] && !extended[3]
    }

    public func indexRatio() -> Double { extensionRatio[0] ?? 0 }
    public func middleRatio() -> Double { extensionRatio[1] ?? 0 }

    /// Builds features, or returns nil when the frame is too poor to trust
    /// (any of the joints the cursor and pinch depend on is missing).
    public static func make(from frame: HandFrame, config: MaestroConfig,
                            previousExtended: [Bool]? = nil) -> HandPose? {
        let c = config.minJointConfidence
        let meanConfidence = frame.points.reduce(0.0) { $0 + Double($1?.confidence ?? 0) } / Double(frame.points.count)
        guard meanConfidence >= config.minHandConfidence else { return nil }
        guard let wrist = frame.position(.wrist, minConfidence: c),
              let indexMCP = frame.position(.indexMCP, minConfidence: c),
              let middleMCP = frame.position(.middleMCP, minConfidence: c),
              let littleMCP = frame.position(.littleMCP, minConfidence: c),
              let thumbTip = frame.position(.thumbTip, minConfidence: c),
              let indexTip = frame.position(.indexTip, minConfidence: c)
        else { return nil }
        let ringMCP = frame.position(.ringMCP, minConfidence: c) ?? lerp(middleMCP, littleMCP, 0.5)

        let palmLength = distance(wrist, middleMCP)
        let palmWidth = distance(indexMCP, littleMCP)
        let scale = max(palmLength, palmWidth * 1.3)
        guard scale > 1e-4 else { return nil }

        let anchor = (wrist * 0.5 + indexMCP + middleMCP * 1.5 + ringMCP + littleMCP) / 5.0

        var ratios: [Double?] = []
        var ext: [Bool] = []
        for f in Finger.allCases {
            let mcp = frame.position(f.mcp, minConfidence: c) ?? (f == .ring ? ringMCP : nil)
            let tip = frame.position(f.tip, minConfidence: c)
            guard let mcp, let tip else {
                ratios.append(nil)
                ext.append(previousExtended?[f.rawValue] ?? false)
                continue
            }
            let base = max(distance(mcp, wrist), 1e-4)
            let r = distance(tip, wrist) / base
            ratios.append(r)
            let was = previousExtended?[f.rawValue]
            let isExt: Bool
            if r > config.fingerExtendedAbove { isExt = true }
            else if r < config.fingerCurledBelow { isExt = false }
            else { isExt = was ?? (r > (config.fingerExtendedAbove + config.fingerCurledBelow) / 2) }
            ext.append(isExt)
        }

        let pinchIndex = distance(thumbTip, indexTip) / scale
        let pinchMiddle: Double
        if let middleTip = frame.position(.middleTip, minConfidence: c) {
            pinchMiddle = distance(thumbTip, middleTip) / scale
        } else {
            pinchMiddle = .infinity
        }

        let orientation = cross(indexMCP - wrist, littleMCP - wrist) / (scale * scale)

        return HandPose(frame: frame, scale: scale, anchor: anchor, wrist: wrist,
                        extensionRatio: ratios, extended: ext,
                        pinchIndex: pinchIndex, pinchMiddle: pinchMiddle,
                        orientation: orientation, confidence: meanConfidence)
    }
}
