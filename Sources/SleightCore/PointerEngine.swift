import Foundation

/// Pointer mode, entered on purpose (hold ☝️, or the menu/hotkey). The palm
/// anchor drives the cursor; everything else is about landing clicks exactly.
///
/// - move hand            → cursor (relative, accelerated, precision when slow)
/// - pinch thumb + index  → click; twice = double-click; hold + move = drag
/// - pinch thumb + middle → right click
/// - ✌️ flick up / down    → scroll (same as command mode)
/// - hold a fist          → back to command mode (so do dropping the hand,
///                          showing its back, losing it, or touching the trackpad)
///
/// Gestures that disturb the hand (closing a pinch, making a fist, dropping
/// the hand) rewind the cursor to where it was just before they began.
public final class PointerEngine {
    public var config: SleightConfig
    public var screens: ScreenLayout

    public init(config: SleightConfig = .default, screens: ScreenLayout = .fallback) {
        self.config = config
        self.screens = screens
    }

    private enum Press: Equatable {
        case none
        case left(clickCount: Int, pending: Vec2, dragging: Bool)
        case right
    }

    private var handID: Int?
    private var cursor: Vec2 = .zero
    private var cursorHistory = TimedHistory<Vec2>(span: 1.0)
    private var press: Press = .none
    private var rightReleaseFrames = 0
    private var precision: Double = 0
    private var lastClick: (time: Double, pos: Vec2, count: Int)?
    private var flipSince: Double?
    private var restSince: Double?
    private var palmSign: Double?
    private var lostSince: Double?
    private var released = false
    private var flicks = FlickDetector()
    private var glideArmed = (left: false, right: false, top: false)

    public var cursorPosition: Vec2 { cursor }

    /// Start pointer mode. `hand` may be nil (entered from the menu): the first
    /// hand that shows up is adopted.
    public func enter(hand: TrackedHand?, cursor start: Vec2, time t: Double) {
        handID = hand?.id
        cursor = screens.clamp(start)
        cursorHistory.removeAll()
        cursorHistory.append(cursor, at: t)
        press = .none
        precision = 0
        lastClick = nil
        flipSince = nil
        restSince = nil
        lostSince = nil
        released = false
        flicks.reset()
        glideArmed = (false, false, false)
        palmSign = hand.flatMap { orientationSign($0.pose) }
    }

    /// Leave pointer mode: release anything held.
    public func exit() -> [EngineAction] {
        var a: [EngineAction] = []
        releaseHeld(&a)
        handID = nil
        return a
    }

    public struct Result {
        public var actions: [EngineAction] = []
        public var exit: ModeChangeReason?
    }

    public func step(tracks: HandTracks, time t: Double, aspect: Double,
                     flickActions: (Flick) -> [EngineAction], hud: inout HUDState) -> Result {
        var r = Result()
        hud.cursor = cursor

        var hand = handID.flatMap { tracks.hand(id: $0) }
        if hand == nil, let adopt = tracks.visible.max(by: { $0.scale < $1.scale }) {
            // Original hand gone (or entered from the menu): adopt the hand in view.
            hand = adopt
            handID = adopt.id
            palmSign = orientationSign(adopt.pose)
            flipSince = nil
        }

        guard let hand, hand.visible else {
            let since = lostSince ?? t
            lostSince = since
            if t - since > config.lostGrace, !released {
                rewindExitMotion(before: since, actions: &r.actions)
                releaseHeld(&r.actions)
                released = true
            }
            if t - since > config.lostExit {
                r.exit = .lost
            }
            hud.pointer = .lost
            hud.cursor = cursor
            return r
        }
        lostSince = nil
        released = false

        // Dropping the hand to rest.
        if hand.anchor.y > config.restLine { restSince = restSince ?? t } else { restSince = nil }
        if let since = restSince, t - since >= config.restTime {
            rewindExitMotion(before: since, actions: &r.actions)
            releaseHeld(&r.actions)
            r.exit = .rested
            return r
        }

        // Turning the back of the hand to the camera.
        let sign = orientationSign(hand.pose)
        if palmSign == nil, hand.pose.isOpenPalm { palmSign = sign }
        if config.flipExitEnabled, let ref = palmSign, let s = sign {
            if s != ref, abs(hand.pose.orientation) > 0.2 { flipSince = flipSince ?? t } else if s == ref { flipSince = nil }
            if let since = flipSince, t - since >= config.flipExitTime {
                rewind(to: since - 0.05, actions: &r.actions)
                releaseHeld(&r.actions)
                r.exit = .flipped
                return r
            }
        }

        var frozen = false

        // Hold a fist to leave.
        if press == .none, hand.shape == .fist {
            frozen = true
            let held = t - hand.shapeSince
            hud.progress = clamp(held / config.exitHoldTime, 0, 1)
            if held >= config.exitHoldTime {
                rewind(to: hand.shapeSince - 0.1, actions: &r.actions)
                r.exit = .gesture
                return r
            }
        }

        // ✌️ flick: scroll, without moving the cursor.
        if press == .none, hand.shape == .vee {
            frozen = true
            let th = FlickDetector.Thresholds(minSpeed: config.flickMinSpeed, minDistance: config.flickMinDistance,
                                              window: config.flickWindow, dominance: config.swipeAxisDominance,
                                              repeatGap: config.flickRepeatGap, returnGap: config.flickReturnGap)
            if let f = flicks.detect(hand, shape: .vee, at: t, settle: 0.1, allow: [.up, .down], th) {
                r.actions += flickActions(f)
            }
        }

        // Clicks.
        switch press {
        case .none:
            if hand.pinchBegan, hand.shape != .fist {
                rewind(to: pinchOnset(hand, t), actions: &r.actions)
                let count = nextClickCount(t)
                r.actions.append(.stopMomentum)
                r.actions.append(.mouseDown(.left, at: cursor, clickCount: count))
                press = .left(clickCount: count, pending: .zero, dragging: false)
                frozen = true
            } else if config.rightClickEnabled, !hand.pinched,
                      hand.pose.pinchMiddle < config.pinchClose,
                      hand.pose.pinchIndex > hand.pose.pinchMiddle + 0.1,
                      hand.pose.middleRatio() >= config.pinchMinIndexExtension {
                rewind(to: t - 0.1, actions: &r.actions)
                r.actions.append(.mouseDown(.right, at: cursor, clickCount: 1))
                press = .right
                rightReleaseFrames = 0
                frozen = true
            }
        case .left(let count, _, _):
            if hand.pinchEnded || !hand.pinched {
                r.actions.append(.mouseUp(.left, at: cursor, clickCount: count))
                lastClick = (t, cursor, count)
                press = .none
                frozen = true
            }
        case .right:
            frozen = true
            rightReleaseFrames = hand.pose.pinchMiddle > config.pinchOpen ? rightReleaseFrames + 1 : 0
            if rightReleaseFrames >= config.pinchReleaseFrames {
                r.actions.append(.mouseUp(.right, at: cursor, clickCount: 1))
                press = .none
            }
        }

        // Motion.
        let u = hand.normalizedAnchor(aspect: aspect)
        let movement = pointerMovement(hand: hand, u: u, time: t)
        if case .left(let count, var pending, let dragging) = press {
            if dragging {
                moveCursor(by: movement, actions: &r.actions)
            } else {
                pending = config.mappingMode == .absolute ? movement : pending + movement
                if pending.length > config.dragDeadzone {
                    press = .left(clickCount: count, pending: .zero, dragging: true)
                    moveCursor(by: pending, actions: &r.actions)
                } else {
                    press = .left(clickCount: count, pending: pending, dragging: false)
                }
            }
        } else if !frozen {
            moveCursor(by: movement, actions: &r.actions)
        }
        cursorHistory.append(cursor, at: t)

        switch press {
        case .left(_, _, let dragging): hud.pointer = dragging ? .dragging : .pressing
        case .right: hud.pointer = .rightPressing
        case .none: hud.pointer = .engaged
        }
        if press == .none {
            let far = config.pinchOpen * 1.6
            hud.pinchProgress = clamp((far - hand.pose.pinchIndex) / (far - config.pinchClose), 0, 1)
        } else {
            hud.pinchProgress = 1
        }
        if min(u.x, 1 - u.x, u.y) < config.edgeGlideMargin { hud.warning = .nearEdge }
        hud.precision = precision
        hud.cursor = cursor
        return r
    }

    // MARK: Motion

    private func pointerMovement(hand: TrackedHand, u: Vec2, time t: Double) -> Vec2 {
        let dt = hand.dt
        switch config.mappingMode {
        case .absolute:
            let inset = config.absoluteInset
            let span = max(1 - 2 * inset, 0.1)
            let nx = clamp((u.x - inset) / span, 0, 1)
            let ny = clamp((u.y - inset) / span, 0, 1)
            let b = screens.bounds
            precision = 0
            return Vec2(b.minX + nx * b.width, b.minY + ny * b.height) - cursor
        case .relative:
            let speed = hand.speed
            let accel = smoothstep(config.accelLowSpeed, config.accelHighSpeed, speed)
            var gain = lerp(config.slowGain, config.fastGain, accel)
            let target: Double = speed < config.precisionSpeed ? 1 : 0
            let tau = target > precision ? config.precisionAttack : config.precisionAttack * 0.35
            precision += (target - precision) * (1 - exp(-dt / max(tau, 1e-3)))
            gain *= lerp(1, config.precisionFactor, precision)
            return hand.deltaHS * gain + edgeGlide(u: u, v: hand.deltaHS / dt, dt: dt)
        }
    }

    /// At the edge of the camera view, while still pushing outward, keep moving.
    private func edgeGlide(u: Vec2, v: Vec2, dt: Double) -> Vec2 {
        let m = config.edgeGlideMargin
        guard m > 0, config.edgeGlideSpeed > 0 else { return .zero }
        func update(_ armed: inout Bool, depth: Double, outward: Double) -> Double {
            if depth <= 0 { armed = false; return 0 }
            if outward > 0.8 { armed = true }
            if outward < -0.5 { armed = false }
            return armed ? min(depth / m, 1) * min(depth / m, 1) : 0
        }
        var g = Vec2.zero
        g.x -= update(&glideArmed.left, depth: m - u.x, outward: -v.x)
        g.x += update(&glideArmed.right, depth: u.x - (1 - m), outward: v.x)
        g.y -= update(&glideArmed.top, depth: m - u.y, outward: -v.y)
        return g * config.edgeGlideSpeed * dt
    }

    private func moveCursor(by movement: Vec2, actions: inout [EngineAction]) {
        guard movement.length > 0.02 else { return }
        let next = screens.clamp(cursor + movement)
        guard distance(next, cursor) > 0.02 else { return }
        cursor = next
        actions.append(.move(to: cursor))
    }

    // MARK: Rewind

    private func rewind(to time: Double, actions: inout [EngineAction]) {
        guard let back = cursorHistory.value(atOrBefore: time), distance(back, cursor) > 0.5 else { return }
        cursor = back
        actions.append(.warp(to: cursor))
    }

    private func rewindExitMotion(before time: Double, actions: inout [EngineAction]) {
        guard let back = cursorHistory.value(atOrBefore: time - 0.2) else { return }
        let d = cursor - back
        if d.length > 25, d.y > 0.6 * d.length {
            cursor = back
            actions.append(.warp(to: cursor))
        }
    }

    private func pinchOnset(_ hand: TrackedHand, _ t: Double) -> Double {
        let samples = Array(hand.pinchHistory.since(t - config.pinchRollbackMax))
        guard samples.count >= 2 else { return t }
        var i = samples.count - 1
        while i > 0, samples[i - 1].value >= samples[i].value - 0.02 { i -= 1 }
        return samples[i].time - 0.001
    }

    private func nextClickCount(_ t: Double) -> Int {
        if let lc = lastClick, t - lc.time < config.doubleClickInterval,
           distance(lc.pos, cursor) < config.doubleClickRadius {
            return min(lc.count + 1, 3)
        }
        return 1
    }

    private func releaseHeld(_ actions: inout [EngineAction]) {
        switch press {
        case .left(let count, _, _): actions.append(.mouseUp(.left, at: cursor, clickCount: count))
        case .right: actions.append(.mouseUp(.right, at: cursor, clickCount: 1))
        case .none: break
        }
        press = .none
    }

    private func orientationSign(_ pose: HandPose) -> Double? {
        abs(pose.orientation) > 0.15 ? (pose.orientation > 0 ? 1 : -1) : nil
    }
}
