import Foundation

/// Generates anatomically plausible 21-point hands. Used by the tests and the
/// simulator to drive the engine without a camera.
public struct SyntheticHand: Sendable {
    /// Wrist position in frame units.
    public var wrist: Vec2 = Vec2(0.65, 0.65)
    /// Wrist to middle knuckle, in frame heights.
    public var scale: Double = 0.16
    /// In-plane rotation in radians (0 = fingers pointing up).
    public var rotation: Double = 0
    /// Back of the hand toward the camera.
    public var flipped: Bool = false
    /// Per finger (index, middle, ring, little): 1 = straight, 0 = curled into the palm.
    public var fingers: [Double] = [1, 1, 1, 1]
    /// 0 = thumb away, 1 = thumb tip touching index tip.
    public var pinch: Double = 0
    /// 0 = thumb away, 1 = thumb tip touching middle tip.
    public var middlePinch: Double = 0
    public var chirality: Chirality = .right
    public var confidence: Float = 0.9

    public init() {}

    public static func openPalm(at wrist: Vec2, scale: Double = 0.16) -> SyntheticHand {
        var h = SyntheticHand(); h.wrist = wrist; h.scale = scale; return h
    }

    public static func fist(at wrist: Vec2, scale: Double = 0.16) -> SyntheticHand {
        var h = openPalm(at: wrist, scale: scale); h.fingers = [0, 0, 0, 0]; return h
    }

    public static func peace(at wrist: Vec2, scale: Double = 0.16) -> SyntheticHand {
        var h = openPalm(at: wrist, scale: scale); h.fingers = [1, 1, 0, 0]; return h
    }

    /// Relaxed pointing hand: fingers loosely extended.
    public static func relaxed(at wrist: Vec2, scale: Double = 0.16) -> SyntheticHand {
        var h = openPalm(at: wrist, scale: scale); h.fingers = [0.9, 0.85, 0.8, 0.8]; return h
    }

    /// Where the engine's palm anchor lands for this hand (useful for placing hands).
    public var anchorOffset: Vec2 {
        let f = frame()
        return HandPose.make(from: f, config: .default)!.anchor - wrist
    }

    public func frame() -> HandFrame { build { .zero } }

    public func frame(noise: Double, rng: inout SplitMix64) -> HandFrame {
        var local = rng
        let f = build { Vec2(local.gaussian(), local.gaussian()) * noise }
        rng = local
        return f
    }

    private func build(_ jitter: () -> Vec2) -> HandFrame {
        // Local coordinates in hand scales: wrist at origin, +y toward the fingers,
        // index side at -x (right hand, palm toward camera, mirrored view).
        let mcps: [Vec2] = [Vec2(-0.35, 0.95), Vec2(0, 1.0), Vec2(0.3, 0.95), Vec2(0.55, 0.85)]
        let fan: [Double] = [-0.12, -0.03, 0.06, 0.16]
        let lengths: [Double] = [0.92, 1.0, 0.95, 0.75]

        var local = [Vec2](repeating: .zero, count: 21)
        local[Joint.wrist.rawValue] = .zero

        for f in Finger.allCases {
            let i = f.rawValue
            let mcp = mcps[i]
            let e = clamp(fingers[i], 0, 1)
            let dir = Vec2(sin(fan[i]), cos(fan[i]))
            let L = lengths[i]
            let straight = [mcp + dir * L * 0.48, mcp + dir * L * 0.76, mcp + dir * L]
            let curled = [mcp + Vec2(0, 0.28 * L), mcp + Vec2(0, 0.02), mcp + Vec2(0, -0.38 * L)]
            let base = f.mcp.rawValue
            local[base] = mcp
            for k in 0..<3 { local[base + 1 + k] = lerp(curled[k], straight[k], e) }
        }

        let thumbOpen: [Vec2] = [Vec2(-0.32, 0.22), Vec2(-0.58, 0.42), Vec2(-0.74, 0.62), Vec2(-0.86, 0.82)]
        let fistThumb = Vec2(-0.15, 0.72)
        let avgExt = fingers.reduce(0, +) / 4
        var thumbTip = lerp(fistThumb, thumbOpen[3], clamp(avgExt, 0, 1))
        if pinch > 0 {
            thumbTip = lerp(thumbTip, local[Joint.indexTip.rawValue], clamp(pinch, 0, 1) * 0.97)
        } else if middlePinch > 0 {
            thumbTip = lerp(thumbTip, local[Joint.middleTip.rawValue], clamp(middlePinch, 0, 1) * 0.97)
        }
        local[Joint.thumbCMC.rawValue] = thumbOpen[0]
        local[Joint.thumbMP.rawValue] = lerp(thumbOpen[1], thumbTip, 0.25)
        local[Joint.thumbIP.rawValue] = lerp(thumbOpen[2], thumbTip, 0.55)
        local[Joint.thumbTip.rawValue] = thumbTip

        let c = cos(rotation), s = sin(rotation)
        var points: [JointPoint?] = []
        for var p in local {
            if flipped { p.x = -p.x }
            // Rotate, flip y (image y is down), scale, translate.
            let r = Vec2(p.x * c - p.y * s, p.x * s + p.y * c)
            let img = wrist + Vec2(r.x, -r.y) * scale + jitter()
            points.append(JointPoint(img, confidence: confidence))
        }
        return HandFrame(points: points, chirality: chirality, confidence: Double(confidence))
    }
}

/// Small deterministic RNG so tests are reproducible.
public struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Standard normal sample (Box-Muller).
    public mutating func gaussian() -> Double {
        let u1 = max(Double.random(in: 0..<1, using: &self), 1e-12)
        let u2 = Double.random(in: 0..<1, using: &self)
        return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }
}

/// One recorded camera frame. A recording is a JSON-lines file of these, so real
/// sessions can be replayed through the engine while tuning.
public struct RecordedFrame: Codable, Sendable {
    public var time: Double
    public var aspect: Double
    public var hands: [HandFrame]

    public init(time: Double, aspect: Double, hands: [HandFrame]) {
        self.time = time; self.aspect = aspect; self.hands = hands
    }

    public static func load(jsonLines data: Data) throws -> [RecordedFrame] {
        let decoder = JSONDecoder()
        return try data.split(separator: UInt8(ascii: "\n")).map { try decoder.decode(RecordedFrame.self, from: Data($0)) }
    }
}
