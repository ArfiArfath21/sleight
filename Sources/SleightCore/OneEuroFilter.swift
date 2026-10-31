import Foundation

/// One Euro filter (Casiez et al., CHI 2012): an adaptive low-pass filter whose
/// cutoff rises with speed. Slow hand = heavy smoothing (no jitter), fast hand =
/// light smoothing (no lag). This is the single most important piece for "feels
/// instant but rock steady".
public struct OneEuroFilter: Sendable {
    public var minCutoff: Double
    public var beta: Double
    public var derivativeCutoff: Double

    private var x: Double?
    private var dx: Double = 0
    private var lastTime: Double?

    public init(minCutoff: Double = 1.0, beta: Double = 0.0, derivativeCutoff: Double = 1.0) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.derivativeCutoff = derivativeCutoff
    }

    @inlinable static func alpha(cutoff: Double, dt: Double) -> Double {
        let tau = 1.0 / (2 * Double.pi * cutoff)
        return 1.0 / (1.0 + tau / dt)
    }

    public mutating func filter(_ value: Double, time: Double) -> Double {
        guard let prev = x, let lt = lastTime else {
            x = value; lastTime = time; dx = 0
            return value
        }
        let dt = max(time - lt, 1e-4)
        lastTime = time
        let rawDx = (value - prev) / dt
        dx += OneEuroFilter.alpha(cutoff: derivativeCutoff, dt: dt) * (rawDx - dx)
        let cutoff = minCutoff + beta * abs(dx)
        let next = prev + OneEuroFilter.alpha(cutoff: cutoff, dt: dt) * (value - prev)
        x = next
        return next
    }

    public mutating func reset() {
        x = nil; lastTime = nil; dx = 0
    }

    public var value: Double? { x }
}

/// One Euro filter over a 2D point. Uses the joint speed (not per-axis) to set the
/// cutoff, so diagonal motion is smoothed the same as axis-aligned motion.
public struct OneEuroFilter2D: Sendable {
    public var minCutoff: Double
    public var beta: Double
    public var derivativeCutoff: Double

    private var x: Vec2?
    private var dx: Vec2 = .zero
    private var lastTime: Double?

    public init(minCutoff: Double = 1.0, beta: Double = 0.0, derivativeCutoff: Double = 1.0) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.derivativeCutoff = derivativeCutoff
    }

    public mutating func filter(_ value: Vec2, time: Double) -> Vec2 {
        guard let prev = x, let lt = lastTime else {
            x = value; lastTime = time; dx = .zero
            return value
        }
        let dt = max(time - lt, 1e-4)
        lastTime = time
        let rawDx = (value - prev) / dt
        dx += OneEuroFilter.alpha(cutoff: derivativeCutoff, dt: dt) * (rawDx - dx)
        let cutoff = minCutoff + beta * dx.length
        let next = prev + OneEuroFilter.alpha(cutoff: cutoff, dt: dt) * (value - prev)
        x = next
        return next
    }

    public mutating func reset() {
        x = nil; lastTime = nil; dx = .zero
    }

    public var value: Vec2? { x }
    /// Smoothed velocity in input units per second.
    public var velocity: Vec2 { dx }
}
