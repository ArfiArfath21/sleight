import Foundation

/// The 21 hand landmarks, matching Vision's `VNHumanHandPoseObservation.JointName`.
public enum Joint: Int, CaseIterable, Codable, Sendable {
    case wrist
    case thumbCMC, thumbMP, thumbIP, thumbTip
    case indexMCP, indexPIP, indexDIP, indexTip
    case middleMCP, middlePIP, middleDIP, middleTip
    case ringMCP, ringPIP, ringDIP, ringTip
    case littleMCP, littlePIP, littleDIP, littleTip
}

/// The four non-thumb fingers, in order.
public enum Finger: Int, CaseIterable, Sendable {
    case index, middle, ring, little

    public var mcp: Joint { [.indexMCP, .middleMCP, .ringMCP, .littleMCP][rawValue] }
    public var pip: Joint { [.indexPIP, .middlePIP, .ringPIP, .littlePIP][rawValue] }
    public var tip: Joint { [.indexTip, .middleTip, .ringTip, .littleTip][rawValue] }
}

public enum Chirality: String, Codable, Sendable, CaseIterable {
    case left, right, unknown
}

public struct JointPoint: Codable, Equatable, Sendable {
    /// Position in "frame height" units: origin top-left, y down, already mirrored
    /// so it matches what the user sees. x spans [0, aspect], y spans [0, 1].
    public var position: Vec2
    public var confidence: Float

    public init(_ position: Vec2, confidence: Float = 1) {
        self.position = position
        self.confidence = confidence
    }
}

/// One detected hand in one camera frame.
public struct HandFrame: Codable, Equatable, Sendable {
    public var points: [JointPoint?]
    public var chirality: Chirality
    public var confidence: Double

    public init(points: [JointPoint?], chirality: Chirality = .unknown, confidence: Double = 1) {
        precondition(points.count == Joint.allCases.count)
        self.points = points
        self.chirality = chirality
        self.confidence = confidence
    }

    public subscript(_ j: Joint) -> JointPoint? {
        get { points[j.rawValue] }
        set { points[j.rawValue] = newValue }
    }

    /// Position of `j` if its confidence clears `minConfidence`.
    @inlinable public func position(_ j: Joint, minConfidence: Float) -> Vec2? {
        guard let p = points[j.rawValue], p.confidence >= minConfidence else { return nil }
        return p.position
    }
}

/// Everything the engine needs for one camera frame.
public struct FrameInput: Sendable {
    /// Capture timestamp in seconds (host clock).
    public var time: Double
    public var hands: [HandFrame]
    /// Frame width / height. Joint x coordinates span [0, aspect].
    public var aspect: Double
    /// Where the system cursor is right now (global CG coordinates).
    public var systemCursor: Vec2
    /// Last time the user touched a real keyboard, trackpad or mouse, if known.
    public var lastRealInput: Double?

    public init(time: Double, hands: [HandFrame], aspect: Double = 4.0 / 3.0,
                systemCursor: Vec2 = .zero, lastRealInput: Double? = nil) {
        self.time = time
        self.hands = hands
        self.aspect = aspect
        self.systemCursor = systemCursor
        self.lastRealInput = lastRealInput
    }
}
