import Foundation

/// One hand followed across frames: filtered position, speed, a debounced
/// shape and a debounced pinch. Both modes read from these.
public final class TrackedHand {
    public struct Sample: Sendable {
        public var anchor: Vec2
        public var scale: Double
        public var shape: HandShape
    }

    public let id: Int
    public private(set) var pose: HandPose
    /// Filtered palm anchor (frame units).
    public private(set) var anchor: Vec2
    /// Smoothed hand scale (frame heights).
    public private(set) var scale: Double
    /// This frame's anchor motion in hand scales.
    public private(set) var deltaHS: Vec2 = .zero
    /// Seconds since the previous frame of this hand.
    public private(set) var dt: Double = 1.0 / 30
    /// Smoothed speed in hand scales per second.
    public private(set) var speed: Double = 0
    public private(set) var firstSeen: Double
    public private(set) var lastSeen: Double
    /// Seen in the latest frame (false while bridging a short dropout).
    public internal(set) var visible = true
    /// Debounced shape and when it started.
    public private(set) var shape: HandShape
    public private(set) var shapeSince: Double
    /// Debounced thumb-index pinch.
    public private(set) var pinched = false
    public private(set) var pinchSince: Double = 0
    /// True only on the frame the pinch closed / opened.
    public private(set) var pinchBegan = false
    public private(set) var pinchEnded = false

    public private(set) var history = TimedHistory<Sample>(span: 0.8)
    public private(set) var pinchHistory = TimedHistory<Double>(span: 0.5)

    private var filter: OneEuroFilter2D
    private var candidateShape: HandShape
    private var candidateFrames = 0
    private var releaseFrames = 0
    private var prevTime: Double

    init(id: Int, pose: HandPose, time: Double, config: SleightConfig) {
        self.id = id
        self.pose = pose
        filter = OneEuroFilter2D(minCutoff: config.filterMinCutoff, beta: config.filterBeta,
                                 derivativeCutoff: config.filterDerivativeCutoff)
        anchor = filter.filter(pose.anchor * 1000, time: time) / 1000
        scale = pose.scale
        firstSeen = time
        lastSeen = time
        prevTime = time
        let s = pose.shape(config: config)
        shape = s
        shapeSince = time
        candidateShape = s
        history.append(Sample(anchor: anchor, scale: scale, shape: s), at: time)
        pinchHistory.append(pose.pinchIndex, at: time)
    }

    func update(pose: HandPose, time t: Double, config: SleightConfig) {
        filter.minCutoff = config.filterMinCutoff
        filter.beta = config.filterBeta
        let bridged = !visible
        self.pose = pose
        visible = true
        scale = lerp(scale, pose.scale, 0.25)
        let next = filter.filter(pose.anchor * 1000, time: t) / 1000
        dt = max(t - prevTime, 1e-3)
        // After a dropout, don't treat the jump as motion.
        deltaHS = bridged ? .zero : (next - anchor) / scale
        speed = lerp(speed, deltaHS.length / dt, 0.5)
        anchor = next
        prevTime = t
        lastSeen = t

        // Shape changes must persist a couple of frames.
        let raw = pose.shape(config: config)
        if raw == shape {
            candidateFrames = 0
        } else if raw == candidateShape {
            candidateFrames += 1
            if candidateFrames >= config.shapeFrames - 1 {
                shape = raw
                shapeSince = t
                candidateFrames = 0
            }
        } else {
            candidateShape = raw
            candidateFrames = config.shapeFrames <= 1 ? 1 : 0
            if config.shapeFrames <= 1 { shape = raw; shapeSince = t }
        }

        // Pinch closes at once (latency matters), opens only after a few frames.
        pinchBegan = false
        pinchEnded = false
        if !pinched {
            if pose.pinchCloses(config: config) {
                pinched = true
                pinchSince = t
                pinchBegan = true
                releaseFrames = 0
            }
        } else {
            releaseFrames = pose.pinchIndex > config.pinchOpen ? releaseFrames + 1 : 0
            if releaseFrames >= config.pinchReleaseFrames {
                pinched = false
                pinchEnded = true
            }
        }

        history.append(Sample(anchor: anchor, scale: scale, shape: shape), at: t)
        pinchHistory.append(pose.pinchIndex, at: t)
    }

    func markMissing() {
        visible = false
        pinchBegan = false
        pinchEnded = false
        deltaHS = .zero
    }

    /// The current shape, if it has been held for at least `duration`.
    public func shape(heldFor duration: Double, at t: Double) -> HandShape? {
        t - shapeSince >= duration ? shape : nil
    }

    /// Anchor position in [0,1]² of the frame.
    public func normalizedAnchor(aspect: Double) -> Vec2 { Vec2(anchor.x / aspect, anchor.y) }
}

/// Keeps up to two hands matched across frames.
public final class HandTracks {
    public private(set) var hands: [TrackedHand] = []
    private var nextID = 1
    /// Raw poses that were too small or too uncertain (for the "move closer" hint).
    public private(set) var rejectedSmall = false

    public init() {}

    public var visible: [TrackedHand] { hands.filter(\.visible) }

    public func hand(id: Int) -> TrackedHand? { hands.first { $0.id == id } }

    public func update(frames: [HandFrame], time t: Double, config: SleightConfig) {
        var poses: [HandPose] = []
        rejectedSmall = false
        for f in frames {
            let previous = hands.min { a, b in
                guard let pa = f.position(.middleMCP, minConfidence: 0) else { return false }
                return distance(a.anchor, pa) < distance(b.anchor, pa)
            }?.pose.extended
            guard let p = HandPose.make(from: f, config: config, previousExtended: previous) else { continue }
            if p.scale < config.minHandScale { rejectedSmall = true; continue }
            poses.append(p)
        }

        // Greedy nearest matching, closest pairs first.
        var pairs: [(Int, Int, Double)] = []
        for (hi, h) in hands.enumerated() {
            for (pi, p) in poses.enumerated() {
                let d = distance(h.anchor, p.anchor) / max(h.scale, 1e-4)
                if d <= config.teleportDistance { pairs.append((hi, pi, d)) }
            }
        }
        pairs.sort { $0.2 < $1.2 }
        var usedH = Set<Int>(), usedP = Set<Int>()
        for (hi, pi, _) in pairs where !usedH.contains(hi) && !usedP.contains(pi) {
            hands[hi].update(pose: poses[pi], time: t, config: config)
            usedH.insert(hi)
            usedP.insert(pi)
        }
        for (hi, h) in hands.enumerated() where !usedH.contains(hi) { h.markMissing() }
        hands.removeAll { !$0.visible && t - $0.lastSeen > config.lostGrace }

        // New hands, biggest first, at most two tracked.
        let fresh = poses.enumerated().filter { !usedP.contains($0.offset) }.map(\.element).sorted { $0.scale > $1.scale }
        for p in fresh where hands.count < 2 {
            hands.append(TrackedHand(id: nextID, pose: p, time: t, config: config))
            nextID += 1
        }
    }

    public func reset() { hands.removeAll() }
}
