import Foundation
import QuartzCore
import MaestroCore

/// Turns engine actions into OS events, on its own high-priority queue so Vision
/// work on the capture queue can never delay output.
///
/// Camera frames arrive at 30 fps but displays refresh at 60-120 Hz. Posting one
/// cursor move per frame looks steppy, while fully interpolating adds a frame
/// of lag. Instead each new target is applied `glideLead` of the way at once
/// (zero added latency for that part), and the rest glides over one frame
/// interval at 120 Hz. Scroll deltas are spread the same way, and scroll
/// momentum runs here too.
final class OutputDriver {
    let queue = DispatchQueue(label: "maestro.output", qos: .userInteractive)
    private let injector: EventInjector
    private let shared: SharedState

    var config = MaestroConfig() // only touched on `queue`
    var dryRun = false
    /// Engine events the UI cares about (called on main).
    var onEvent: ((EngineAction) -> Void)?

    private var pos: Vec2?
    private var glideFrom = Vec2.zero, glideTo = Vec2.zero
    private var glideStart = 0.0, glideDuration = 0.0
    private var gliding = false

    private var scrollRemaining = Vec2.zero
    private var scrollRate = Vec2.zero
    private var scrollActive = false

    private var momentum: Vec2?
    private var momentumBegun = false

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
            stopMomentum()
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

        case .scroll(let delta, let phase):
            stopMomentum()
            switch phase {
            case .began:
                scrollActive = true
                scrollRemaining = .zero
                postScroll(.zero, phase: .began)
            case .changed:
                if config.glideEnabled, frameInterval > 1.0 / 50 {
                    let now = delta * config.glideLead
                    postScroll(now + scrollRemaining, phase: .changed)
                    scrollRemaining = delta - now
                    scrollRate = scrollRemaining / (frameInterval * 0.9)
                    ensureTimer()
                } else {
                    postScroll(delta, phase: .changed)
                }
            case .ended:
                if scrollRemaining.length > 0.01 { postScroll(scrollRemaining, phase: .changed) }
                scrollRemaining = .zero
                scrollActive = false
                postScroll(.zero, phase: .ended)
            }

        case .scrollMomentum(let v):
            momentum = v
            momentumBegun = false
            ensureTimer()

        case .stopMomentum:
            stopMomentum()

        case .swipe(let dir):
            if !dryRun {
                switch dir {
                // Like the trackpad: content follows the hand, so flicking right
                // reveals the Space on the left.
                case .right: injector.switchSpace(left: true)
                case .left: injector.switchSpace(left: false)
                case .up: injector.missionControl()
                }
            }
            notify(action)

        case .toggleKeyboard, .engaged, .disengaged:
            if case .disengaged = action { gliding = false }
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

    private func postScroll(_ d: Vec2, phase: ScrollPhase?, momentumPhase: EventInjector.MomentumPhase = .none) {
        guard !dryRun else { return }
        shared.noteOwnScroll()
        injector.scroll(d, phase: phase, momentum: momentumPhase)
    }

    private func stopMomentum() {
        if momentum != nil, momentumBegun { postScroll(.zero, phase: nil, momentumPhase: .end) }
        momentum = nil
        momentumBegun = false
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

        if scrollActive, scrollRemaining.length > 0.01 {
            var step = scrollRate * dt
            if step.length > scrollRemaining.length { step = scrollRemaining }
            scrollRemaining -= step
            postScroll(step, phase: .changed)
            busy = true
        }

        if var v = momentum {
            postScroll(v * dt, phase: nil, momentumPhase: momentumBegun ? .continue : .begin)
            momentumBegun = true
            v *= exp(-dt / max(config.momentumDecay, 0.05))
            if v.length < 15 {
                postScroll(.zero, phase: nil, momentumPhase: .end)
                momentum = nil
                momentumBegun = false
            } else {
                momentum = v
                busy = true
            }
        }

        if !busy, timerRunning {
            timer?.suspend()
            timerRunning = false
        }
    }
}
