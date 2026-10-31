import Foundation
import QuartzCore
import SleightCore

/// Turns engine actions into OS events on its own high-priority queue, so
/// Vision work on the capture queue can never delay output.
///
/// - Cursor: camera frames arrive at 30 fps but displays refresh at 60–120 Hz.
///   Each new target is applied `glideLead` of the way at once (no added
///   latency for that part) and the rest glides over one frame at 120 Hz.
/// - Scroll: a flick adds momentum, which decays smoothly at 120 Hz. Flicking
///   again in the same direction stacks speed, like flinging a long page.
final class OutputDriver {
    let queue = DispatchQueue(label: "sleight.output", qos: .userInteractive)
    private let injector: EventInjector
    private let shared: SharedState

    var config = SleightConfig() // only touched on `queue`
    var dryRun = false
    /// Actions the UI shows feedback for (called on main).
    var onEvent: ((EngineAction) -> Void)?

    private var pos: Vec2?
    private var glideFrom = Vec2.zero, glideTo = Vec2.zero
    private var glideStart = 0.0, glideDuration = 0.0
    private var gliding = false
    private var momentum: Vec2?

    private var timer: DispatchSourceTimer?
    private var timerRunning = false
    private var lastTick = 0.0

    init(injector: EventInjector, shared: SharedState) {
        self.injector = injector
        self.shared = shared
    }

    func handle(_ actions: [EngineAction], frameInterval: Double) {
        guard !actions.isEmpty else { return }
        queue.async { [self] in
            for a in actions { apply(a, frameInterval: frameInterval) }
        }
    }

    func releaseAll() {
        queue.sync {
            momentum = nil
            gliding = false
            injector.releaseAll(at: pos ?? EventInjector.currentCursor())
        }
    }

    private func apply(_ action: EngineAction, frameInterval: Double) {
        switch action {
        case .move(let p):
            let cur = pos ?? p
            if config.glideEnabled, frameInterval > 1.0 / 50 {
                let lead = lerp(cur, p, clamp(config.glideLead, 0, 1))
                postMove(lead)
                glideFrom = lead
                glideTo = p
                glideStart = CACurrentMediaTime()
                glideDuration = frameInterval * 0.9
                gliding = true
                ensureTimer()
            } else {
                gliding = false
                postMove(p)
            }

        case .warp(let p):
            gliding = false
            postMove(p)

        case .mouseDown(let b, let p, let c):
            finishGlide(at: p)
            if !dryRun { injector.button(b, down: true, at: p, clickCount: c) }

        case .mouseUp(let b, let p, let c):
            finishGlide(at: p)
            if !dryRun { injector.button(b, down: false, at: p, clickCount: c) }
            notify(action)

        case .scrollFlick(let v):
            if let m = momentum, (m.y > 0) == (v.y > 0), (m.x > 0) == (v.x > 0) {
                let sum = m + v
                momentum = sum.length > 9000 ? sum.normalized * 9000 : sum
            } else {
                momentum = v
            }
            ensureTimer()
            notify(action)

        case .stopMomentum:
            momentum = nil

        case .shortcut(let s):
            if !dryRun { injector.shortcut(s) }
            notify(action)

        case .media(let m):
            if !dryRun { injector.media(m) }
            notify(action)

        case .switcher(let step):
            if !dryRun { injector.switcher(step) }
            notify(action)

        case .modeChanged(let m, _):
            gliding = false
            if m == .command { pos = nil; shared.clearOutputCursor() }
            notify(action)

        case .activeChanged:
            momentum = nil
            notify(action)
        }
    }

    private func notify(_ action: EngineAction) {
        DispatchQueue.main.async { self.onEvent?(action) }
    }

    private func postMove(_ p: Vec2) {
        let prev = pos ?? p
        pos = p
        shared.setOutputCursor(p)
        if !dryRun { injector.move(to: p, delta: p - prev) }
    }

    private func finishGlide(at p: Vec2) {
        gliding = false
        if pos.map({ distance($0, p) > 0.01 }) ?? true { postMove(p) }
    }

    // MARK: 120 Hz ticker (runs only while something is in flight)

    private func ensureTimer() {
        if timer == nil {
            let t = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
            t.schedule(deadline: .now(), repeating: .nanoseconds(8_333_333), leeway: .microseconds(500))
            t.setEventHandler { [weak self] in self?.tick() }
            timer = t
        }
        if !timerRunning {
            lastTick = CACurrentMediaTime()
            timer?.resume()
            timerRunning = true
        }
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(max(now - lastTick, 1e-4), 0.05)
        lastTick = now
        var busy = false

        if gliding {
            let f = clamp((now - glideStart) / max(glideDuration, 1e-3), 0, 1)
            postMove(lerp(glideFrom, glideTo, f))
            if f >= 1 { gliding = false } else { busy = true }
        }

        if var v = momentum {
            if !dryRun {
                shared.noteOwnScroll()
                injector.scroll(v * dt)
            }
            v *= exp(-dt / max(config.momentumDecay, 0.05))
            if v.length < 20 { momentum = nil } else { momentum = v; busy = true }
        }

        if !busy, timerRunning {
            timer?.suspend()
            timerRunning = false
        }
    }
}
