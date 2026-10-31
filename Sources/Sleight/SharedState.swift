import Foundation
import SleightCore

/// Live numbers about the pipeline, for the HUD and the preview window.
struct QualitySnapshot {
    var fps: Double = 0
    var targetFPS: Double = 30
    var visionMs: Double = 0
    var latencyMs: Double = 0
    var latencyP95Ms: Double = 0
    var luma: Double = 128
    var frameRateLocked = false
    var cameraName = ""
    var resolution = ""
}

/// The single place where the capture/output queues hand state to the main
/// thread. Everything is copied under a lock; the UI reads at display refresh.
final class SharedState {
    private let lock = NSLock()
    private var _hud = HUDState()
    private var _outputCursor: Vec2?
    private var _quality = QualitySnapshot()
    private var _hands: [HandFrame] = []
    private var _pose: HandPose?
    private var _aspect: Double = 4.0 / 3.0
    private var _lastInjectedMove: (p: Vec2, t: Double)?
    private var _lastOwnScroll = 0.0

    var hud: HUDState { lock.withLock { _hud } }
    var outputCursor: Vec2? { lock.withLock { _outputCursor } }
    var quality: QualitySnapshot { lock.withLock { _quality } }
    var hands: (frames: [HandFrame], pose: HandPose?, aspect: Double) { lock.withLock { (_hands, _pose, _aspect) } }

    func setFrame(hud: HUDState, hands: [HandFrame], pose: HandPose?, aspect: Double) {
        lock.withLock {
            _hud = hud
            _hands = hands
            _pose = pose
            _aspect = aspect
        }
    }

    func setOutputCursor(_ p: Vec2) {
        lock.withLock {
            _outputCursor = p
            _lastInjectedMove = (p, CFAbsoluteTimeGetCurrent())
        }
    }

    func clearOutputCursor() { lock.withLock { _outputCursor = nil } }

    func setQuality(_ q: QualitySnapshot) { lock.withLock { _quality = q } }

    func noteOwnScroll() { lock.withLock { _lastOwnScroll = CFAbsoluteTimeGetCurrent() } }

    var isOwnScrollRecent: Bool { lock.withLock { CFAbsoluteTimeGetCurrent() - _lastOwnScroll < 0.05 } }

    /// True if a mouse event at `p` is almost certainly one we just posted.
    func isOwnMouseEvent(at p: Vec2) -> Bool {
        lock.withLock {
            guard let last = _lastInjectedMove else { return false }
            return distance(last.p, p) < 1.5 && CFAbsoluteTimeGetCurrent() - last.t < 0.1
        }
    }
}

/// Rolling latency/fps stats.
struct RollingStats {
    private var values: [Double] = []
    private let capacity: Int
    private var index = 0

    init(capacity: Int = 240) { self.capacity = capacity }

    mutating func add(_ v: Double) {
        if values.count < capacity { values.append(v) } else { values[index] = v; index = (index + 1) % capacity }
    }

    var mean: Double { values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count) }

    func percentile(_ p: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[min(Int(Double(sorted.count - 1) * p), sorted.count - 1)]
    }

    var count: Int { values.count }
}
