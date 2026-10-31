import Foundation

public enum FlickDirection: String, Sendable { case left, right, up, down }

public struct Flick: Sendable, Equatable {
    public var direction: FlickDirection
    /// Average speed over the window, hand scales per second.
    public var speed: Double
}

/// Finds deliberate, fast, straight hand motions ("flicks") while the hand
/// holds one shape. Built to reject the motions that are not gestures:
/// - a hand entering the frame (must have been in view and settled first)
/// - slow drifting (speed and distance thresholds)
/// - diagonal waving (one axis must dominate)
/// - the return stroke after a flick (opposite direction is locked out briefly)
public struct FlickDetector: Sendable {
    public struct Thresholds: Sendable {
        public var minSpeed: Double
        public var minDistance: Double
        public var window: Double
        public var dominance: Double
        public var repeatGap: Double
        public var returnGap: Double
    }

    private var last: (direction: FlickDirection, time: Double)?
    /// The hand must slow down between flicks: one long motion is one flick.
    private var rearmed = true

    public init() {}

    public mutating func reset() { last = nil; rearmed = true }

    public mutating func detect(_ hand: TrackedHand, shape: HandShape, at t: Double,
                                settle: Double, allow: Set<FlickDirection>, _ th: Thresholds) -> Flick? {
        if hand.speed < th.minSpeed * 0.4 { rearmed = true }
        guard rearmed else { return nil }
        let samples = Array(hand.history.since(t - th.window))
        guard samples.count >= 3, let first = samples.first, let lastS = samples.last else { return nil }
        let span = lastS.time - first.time
        guard span >= th.window * 0.55 else { return nil }
        // The hand must have been visible and settled before the motion started.
        guard first.time - hand.firstSeen >= settle else { return nil }
        let inShape = samples.filter { $0.value.shape == shape }.count
        guard Double(inShape) / Double(samples.count) >= 0.75 else { return nil }

        let d = (lastS.value.anchor - first.value.anchor) / lastS.value.scale
        let v = d / span
        // Peak speed along an axis (mean of the two fastest steps): a flick that
        // is detected early, mid-motion, still reports how hard it was.
        func peak(_ axis: (Vec2) -> Double) -> Double {
            var steps: [Double] = []
            for i in 1..<samples.count {
                let dt = max(samples[i].time - samples[i - 1].time, 1e-3)
                steps.append(abs(axis(samples[i].value.anchor - samples[i - 1].value.anchor)) / samples[i].value.scale / dt)
            }
            let top = steps.sorted(by: >).prefix(2)
            return top.reduce(0, +) / Double(max(top.count, 1))
        }
        let dir: FlickDirection
        let speed: Double
        if abs(d.x) >= th.dominance * abs(d.y) {
            guard abs(d.x) >= th.minDistance, abs(v.x) >= th.minSpeed else { return nil }
            dir = d.x > 0 ? .right : .left
            speed = peak { $0.x }
        } else if abs(d.y) >= th.dominance * abs(d.x) {
            guard abs(d.y) >= th.minDistance, abs(v.y) >= th.minSpeed else { return nil }
            dir = d.y > 0 ? .down : .up
            speed = peak { $0.y }
        } else {
            return nil
        }
        guard allow.contains(dir) else { return nil }

        if let l = last {
            let gap = t - l.time
            if l.direction == dir, gap < th.repeatGap { return nil }
            if l.direction.opposite == dir, gap < th.returnGap { return nil }
            // Perpendicular flicks right after one another are almost always one
            // wobbly motion.
            if l.direction != dir, l.direction.opposite != dir, gap < th.repeatGap { return nil }
        }
        last = (dir, t)
        rearmed = false
        return Flick(direction: dir, speed: speed)
    }
}

extension FlickDirection {
    public var opposite: FlickDirection {
        switch self {
        case .left: return .right
        case .right: return .left
        case .up: return .down
        case .down: return .up
        }
    }
}
