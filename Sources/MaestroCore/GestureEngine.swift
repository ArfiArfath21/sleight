import Foundation

/// Turns a stream of hand frames into OS actions.
///
/// State machine:
///
///     idle ──open palm, steady, 0.3 s──▶ arming ──▶ engaged
///       ▲                                             │
///       └── hand lost 1.2 s / dropped to rest / back of hand shown / real input
///
/// While engaged:
/// - palm anchor moves the cursor (relative, accelerated, precision when slow)
/// - thumb+index pinch  = left button (click, double-click, drag)
/// - thumb+middle pinch = right click
/// - fist + move        = scroll, with momentum on release
/// - fast open-palm flick left/right/up = Spaces / Mission Control
/// - hold a peace sign  = toggle the on-screen keyboard
///
/// Every gesture that physically disturbs the hand (closing a pinch, making a
/// fist, a flick, dropping the hand) rewinds the cursor to where it was just
/// before the gesture began, so the action lands where you were pointing.
public final class GestureEngine {
    public var config: MaestroConfig {
        didSet { configureFilter() }
    }
    public var screens: ScreenLayout

    public init(config: MaestroConfig = .default, screens: ScreenLayout = .fallback) {
        self.config = config
        self.screens = screens
        self.filter = OneEuroFilter2D()
        configureFilter()
    }

    // MARK: State

    private enum Phase: Equatable { case idle, arming(since: Double), engaged }

    private enum Press: Equatable {
        case none
        case left(clickCount: Int, pending: Vec2, dragging: Bool)
        case right
    }

    private struct ScrollState {
        var lastAnchor: Vec2
        var velocity = TimedHistory<Vec2>(span: 0.25)
        var exitFrames = 0
    }

    private struct MotionSample: Sendable {
        var anchor: Vec2
        var scale: Double
        var open: Bool
    }

    private var phase: Phase = .idle
    private var press: Press = .none
    private var scroll: ScrollState?
    private var filter: OneEuroFilter2D
    private var scale: Double = 0
    private var prevAnchor: Vec2?
    private var prevTime: Double?
    private var lastSeen: Double?
    private var lastRawAnchor: Vec2?
    private var prevExtended: [Bool]?
    private var cursor: Vec2 = .zero
    private var cursorHistory = TimedHistory<Vec2>(span: 1.0)
    private var pinchHistory = TimedHistory<Double>(span: 0.5)
    private var motionHistory = TimedHistory<MotionSample>(span: 0.6)
    private var speed: Double = 0
    private var precision: Double = 0
    private var lastClick: (time: Double, pos: Vec2, count: Int)?
    private var releaseFrames = 0
    private var fistFrames = 0
    private var swipeCooldownUntil = -Double.infinity
    private var peaceSince: Double?
    private var keyboardCooldownUntil = -Double.infinity
    private var flipSince: Double?
    private var restSince: Double?
    private var palmSign: Double?
    private var blockedSign: Double?
    private var exitRewound = false
    private var glideArmed = (left: false, right: false, top: false, bottom: false)

    public var isEngaged: Bool { phase == .engaged }
    public var cursorPosition: Vec2 { cursor }

    private func configureFilter() {
        filter.minCutoff = config.filterMinCutoff
        filter.beta = config.filterBeta
        filter.derivativeCutoff = config.filterDerivativeCutoff
    }

    // MARK: Public control

    /// Disengage from outside (menu, hotkey, pause). Releases anything held.
    public func forceDisengage() -> [EngineAction] {
        guard phase == .engaged else { phase = .idle; return [] }
        var actions: [EngineAction] = []
        disengage(.manual, &actions)
        return actions
    }

    // MARK: Frame processing

    public func process(_ input: FrameInput) -> EngineOutput {
        var actions: [EngineAction] = []
        var hud = HUDState()
        let t = input.time

        // Real keyboard/trackpad use always wins: get out of the way at once.
        if let real = input.lastRealInput, t - real < config.realInputCooldown {
            if phase == .engaged { disengage(.userInput, &actions) }
            phase = .idle
            lastSeen = nil
            // Hands on the keyboard are in view: show nothing at all.
            hud.mode = .off
            hud.cursor = input.systemCursor
            return EngineOutput(actions: actions, hud: hud, pose: nil)
        }

        let all = input.hands.compactMap { HandPose.make(from: $0, config: config, previousExtended: prevExtended) }
        let usable = all.filter { $0.scale >= config.minHandScale }
        let pose = selectHand(usable, time: t)

        guard let pose else {
            handleMissingHand(t, &actions, &hud)
            if !all.isEmpty && usable.isEmpty { hud.hint = .tooFar }
            hud.cursor = phase == .engaged ? cursor : input.systemCursor
            return EngineOutput(actions: actions, hud: hud, pose: nil)
        }

        // Fresh acquisition: start filters from scratch so nothing jumps.
        let reacquired = lastSeen.map { t - $0 > config.lostGrace } ?? true
        if reacquired {
            filter.reset()
            prevAnchor = nil
            prevTime = nil
            scale = 0
            motionHistory.removeAll()
            pinchHistory.removeAll()
            speed = 0
        }
        lastSeen = t
        exitRewound = false
        lastRawAnchor = pose.anchor
        prevExtended = pose.extended

        scale = scale == 0 ? pose.scale : lerp(scale, pose.scale, 0.25)
        let anchor = filter.filter(pose.anchor * 1000, time: t) / 1000
        let dt = prevTime.map { max(t - $0, 1e-3) } ?? (1.0 / 30)
        let deltaHS = prevAnchor.map { (anchor - $0) / scale } ?? .zero
        let instSpeed = deltaHS.length / dt
        speed = lerp(speed, instSpeed, 0.5)
        motionHistory.append(MotionSample(anchor: anchor, scale: scale, open: pose.isOpenPalm), at: t)
        pinchHistory.append(pose.pinchIndex, at: t)
        defer {
            prevAnchor = anchor
            prevTime = t
        }

        let u = Vec2(anchor.x / input.aspect, anchor.y)
        if min(u.x, 1 - u.x, u.y) < config.edgeGlideMargin { hud.hint = .nearEdge }

        switch phase {
        case .idle, .arming:
            stepIdle(pose: pose, anchor: anchor, input: input, hud: &hud, actions: &actions)
        case .engaged:
            stepEngaged(pose: pose, anchor: anchor, u: u, deltaHS: deltaHS, dt: dt,
                        time: t, hud: &hud, actions: &actions)
        }

        if phase == .engaged {
            cursorHistory.append(cursor, at: t)
            hud.cursor = cursor
        } else {
            hud.cursor = input.systemCursor
        }
        return EngineOutput(actions: actions, hud: hud, pose: pose)
    }

    // MARK: Hand selection

    private func selectHand(_ poses: [HandPose], time t: Double) -> HandPose? {
        guard !poses.isEmpty else { return nil }
        // Already following a hand: stick with the one nearest to where it was.
        if let last = lastRawAnchor, let seen = lastSeen, t - seen <= config.lostGrace {
            let best = poses.min { distance($0.anchor, last) < distance($1.anchor, last) }!
            let jump = distance(best.anchor, last) / max(best.scale, 1e-4)
            // A big jump is a tracking glitch or someone else's hand: ignore the frame.
            return jump > config.teleportDistance ? nil : best
        }
        var pool = poses
        if config.preferredHand != .unknown {
            let preferred = poses.filter { $0.frame.chirality == config.preferredHand }
            if !preferred.isEmpty { pool = preferred }
        }
        return pool.max { $0.scale < $1.scale }
    }

    // MARK: Idle / arming

    private func stepIdle(pose: HandPose, anchor: Vec2, input: FrameInput,
                          hud: inout HUDState, actions: inout [EngineAction]) {
        let t = input.time
        let sign = orientationSign(pose)
        if let blocked = blockedSign, let s = sign, s != blocked { blockedSign = nil }
        let blocked = blockedSign != nil && sign == blockedSign
        let canArm = pose.isOpenPalm && speed < config.armMaxSpeed
            && anchor.y < config.restLine && !blocked
        guard canArm else {
            phase = .idle
            hud.mode = .watching
            return
        }
        let since: Double
        if case .arming(let s) = phase { since = s } else { since = t }
        phase = .arming(since: since)
        let progress = (t - since) / config.armTime
        if progress >= 1 {
            engage(pose: pose, input: input, actions: &actions)
            hud.mode = .engaged
        } else {
            hud.mode = .arming
            hud.armProgress = progress
        }
    }

    private func engage(pose: HandPose, input: FrameInput, actions: inout [EngineAction]) {
        phase = .engaged
        cursor = screens.clamp(input.systemCursor)
        cursorHistory.removeAll()
        cursorHistory.append(cursor, at: input.time)
        palmSign = orientationSign(pose)
        blockedSign = nil
        press = .none
        scroll = nil
        flipSince = nil
        restSince = nil
        peaceSince = nil
        fistFrames = 0
        precision = 0
        lastClick = nil
        glideArmed = (false, false, false, false)
        actions.append(.stopMomentum)
        actions.append(.engaged)
    }

    private func orientationSign(_ pose: HandPose) -> Double? {
        abs(pose.orientation) > 0.15 ? (pose.orientation > 0 ? 1 : -1) : nil
    }

    // MARK: Engaged

    private func stepEngaged(pose: HandPose, anchor: Vec2, u: Vec2, deltaHS: Vec2, dt: Double,
                             time t: Double, hud: inout HUDState, actions: inout [EngineAction]) {
        // Dropping the hand to rest.
        if anchor.y > config.restLine { restSince = restSince ?? t } else { restSince = nil }
        if let since = restSince, t - since >= config.restTime {
            rewindExitMotion(endTime: since, actions: &actions)
            disengage(.rested, &actions)
            hud.mode = .watching
            return
        }

        // Turning the back of the hand to the camera.
        let sign = orientationSign(pose)
        if palmSign == nil, pose.isOpenPalm { palmSign = sign }
        if config.flipDisengageEnabled, let ref = palmSign, let s = sign {
            if s != ref, abs(pose.orientation) > 0.2 { flipSince = flipSince ?? t } else if s == ref { flipSince = nil }
            if let since = flipSince, t - since >= config.flipDisengageTime {
                rewind(to: since - 0.05, actions: &actions)
                blockedSign = s
                disengage(.flipped, &actions)
                hud.mode = .watching
                return
            }
        }

        var frozen = false

        // Pinches.
        switch press {
        case .none:
            guard scroll == nil else { break }
            if pose.pinchIndex < config.pinchClose && pose.pinchIndex <= pose.pinchMiddle
                && pose.indexRatio() >= config.pinchMinIndexExtension {
                rewind(to: pinchOnset(t), actions: &actions)
                let count = nextClickCount(t)
                actions.append(.stopMomentum)
                actions.append(.mouseDown(.left, at: cursor, clickCount: count))
                press = .left(clickCount: count, pending: .zero, dragging: false)
                releaseFrames = 0
                frozen = true
            } else if config.rightClickEnabled,
                      pose.pinchMiddle < config.pinchClose,
                      pose.pinchIndex > pose.pinchMiddle + 0.1,
                      pose.middleRatio() >= config.pinchMinIndexExtension {
                rewind(to: t - 0.1, actions: &actions)
                actions.append(.stopMomentum)
                actions.append(.mouseDown(.right, at: cursor, clickCount: 1))
                press = .right
                releaseFrames = 0
                frozen = true
            }
        case .left(let count, _, _):
            releaseFrames = pose.pinchIndex > config.pinchOpen ? releaseFrames + 1 : 0
            if releaseFrames >= config.pinchReleaseFrames {
                actions.append(.mouseUp(.left, at: cursor, clickCount: count))
                lastClick = (t, cursor, count)
                press = .none
                frozen = true
            }
        case .right:
            frozen = true
            releaseFrames = pose.pinchMiddle > config.pinchOpen ? releaseFrames + 1 : 0
            if releaseFrames >= config.pinchReleaseFrames {
                actions.append(.mouseUp(.right, at: cursor, clickCount: 1))
                press = .none
            }
        }

        // Fist scroll.
        if config.scrollEnabled, press == .none {
            if var s = scroll {
                frozen = true
                s.exitFrames = pose.extendedCount >= 2 ? s.exitFrames + 1 : 0
                if s.exitFrames >= config.scrollExitFrames {
                    scroll = s
                    endScroll(momentum: true, actions: &actions)
                } else {
                    if s.exitFrames == 0 {
                        let d = (anchor - s.lastAnchor) / scale * config.scrollGain
                        let delta = config.scrollNatural ? d : -d
                        if delta.length > 0.01 { actions.append(.scroll(delta: delta, phase: .changed)) }
                        s.velocity.append(delta / dt, at: t)
                    }
                    // While the hand is opening, the anchor shifts: don't scroll on it.
                    s.lastAnchor = anchor
                    scroll = s
                }
            } else if !frozen {
                fistFrames = pose.isFist(config: config) ? fistFrames + 1 : 0
                if fistFrames >= config.scrollEnterFrames {
                    rewind(to: t - Double(config.scrollEnterFrames) * dt - 0.03, actions: &actions)
                    actions.append(.stopMomentum)
                    actions.append(.scroll(delta: .zero, phase: .began))
                    scroll = ScrollState(lastAnchor: anchor)
                    fistFrames = 0
                    frozen = true
                }
            }
        }

        // Peace sign: toggle keyboard.
        if config.keyboardGestureEnabled, press == .none, scroll == nil,
           pose.isPeace, t >= keyboardCooldownUntil {
            let since = peaceSince ?? t
            peaceSince = since
            hud.keyboardProgress = clamp((t - since) / config.keyboardHoldTime, 0, 1)
            if t - since >= config.keyboardHoldTime {
                rewind(to: since - 0.05, actions: &actions)
                actions.append(.toggleKeyboard)
                keyboardCooldownUntil = t + 1.2
                peaceSince = nil
                hud.keyboardProgress = 0
            }
        } else {
            peaceSince = nil
        }

        // Swipes.
        if config.swipesEnabled, press == .none, scroll == nil, !frozen, t >= swipeCooldownUntil,
           let dir = detectSwipe(at: t) {
            rewind(to: t - config.swipeWindow - 0.05, actions: &actions)
            actions.append(.swipe(dir))
            swipeCooldownUntil = t + config.swipeCooldown
        }
        // Ignore the return stroke after a flick.
        if t < swipeCooldownUntil { frozen = true }

        // Pointer motion.
        let movement = pointerMovement(deltaHS: deltaHS, u: u, dt: dt)
        if case .left(let count, var pending, let dragging) = press {
            if dragging {
                moveCursor(by: movement, actions: &actions)
            } else {
                pending = config.mappingMode == .absolute ? movement : pending + movement
                if pending.length > config.dragDeadzone {
                    press = .left(clickCount: count, pending: .zero, dragging: true)
                    moveCursor(by: pending, actions: &actions)
                } else {
                    press = .left(clickCount: count, pending: pending, dragging: false)
                }
            }
        } else if !frozen {
            moveCursor(by: movement, actions: &actions)
        }

        // HUD.
        switch press {
        case .left(_, _, let dragging): hud.mode = dragging ? .dragging : .pressing
        case .right: hud.mode = .rightPressing
        case .none: hud.mode = scroll != nil ? .scrolling : .engaged
        }
        if press == .none {
            let far = config.pinchOpen * 1.6
            hud.pinchProgress = clamp((far - pose.pinchIndex) / (far - config.pinchClose), 0, 1)
        } else {
            hud.pinchProgress = 1
        }
        hud.precision = precision
    }

    private func pointerMovement(deltaHS: Vec2, u: Vec2, dt: Double) -> Vec2 {
        switch config.mappingMode {
        case .absolute:
            let inset = config.absoluteInset
            let span = max(1 - 2 * inset, 0.1)
            let nx = clamp((u.x - inset) / span, 0, 1)
            let ny = clamp((u.y - inset) / span, 0, 1)
            let b = screens.bounds
            let target = Vec2(b.minX + nx * b.width, b.minY + ny * b.height)
            precision = 0
            return target - cursor

        case .relative:
            let accel = smoothstep(config.accelLowSpeed, config.accelHighSpeed, speed)
            var gain = lerp(config.slowGain, config.fastGain, accel)
            let target: Double = speed < config.precisionSpeed ? 1 : 0
            let tau = target > precision ? config.precisionAttack : config.precisionAttack * 0.35
            precision += (target - precision) * (1 - exp(-dt / max(tau, 1e-3)))
            gain *= lerp(1, config.precisionFactor, precision)
            return deltaHS * gain + edgeGlide(u: u, deltaHS: deltaHS, dt: dt)
        }
    }

    /// When the hand reaches the edge of the camera view while moving outward,
    /// keep the cursor travelling that way so the screen edge is always reachable.
    private func edgeGlide(u: Vec2, deltaHS: Vec2, dt: Double) -> Vec2 {
        let m = config.edgeGlideMargin
        guard m > 0, config.edgeGlideSpeed > 0 else { return .zero }
        let v = deltaHS / dt
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

    /// When the hand leaves (drops out of view), the last few frames usually drag
    /// the cursor down. Undo that if the final motion was a fast downward exit.
    private func rewindExitMotion(endTime: Double, actions: inout [EngineAction]) {
        guard !exitRewound, let back = cursorHistory.value(atOrBefore: endTime - 0.2) else { return }
        exitRewound = true
        let d = cursor - back
        if d.length > 25, d.y > 0.6 * d.length {
            cursor = back
            actions.append(.warp(to: cursor))
        }
    }

    /// When the fingers started closing: walk back while the pinch distance was
    /// still shrinking.
    private func pinchOnset(_ t: Double) -> Double {
        let samples = Array(pinchHistory.since(t - config.pinchRollbackMax))
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

    // MARK: Swipe

    private func detectSwipe(at t: Double) -> SwipeDirection? {
        let window = Array(motionHistory.since(t - config.swipeWindow))
        guard window.count >= 3, let first = window.first, let last = window.last else { return nil }
        let span = last.time - first.time
        guard span >= config.swipeWindow * 0.6 else { return nil }
        let openShare = Double(window.filter { $0.value.open }.count) / Double(window.count)
        guard openShare >= 0.75 else { return nil }
        let d = (last.value.anchor - first.value.anchor) / last.value.scale
        let v = d / span
        if abs(d.x) > config.swipeMinDistance, abs(v.x) > config.swipeMinSpeed,
           abs(d.x) > config.swipeAxisDominance * abs(d.y) {
            return d.x > 0 ? .right : .left
        }
        if config.swipeUpEnabled, -d.y > config.swipeMinDistance, -v.y > config.swipeMinSpeed,
           abs(d.y) > config.swipeAxisDominance * abs(d.x) {
            return .up
        }
        return nil
    }

    // MARK: Lost / disengage

    private func handleMissingHand(_ t: Double, _ actions: inout [EngineAction], _ hud: inout HUDState) {
        guard phase == .engaged, let seen = lastSeen else {
            phase = .idle
            hud.mode = .off
            return
        }
        let gap = t - seen
        if gap > config.lostGrace {
            rewindExitMotion(endTime: seen, actions: &actions)
            releaseHeld(&actions)
        }
        if gap > config.lostDisengage {
            disengage(.lost, &actions)
            hud.mode = .off
            return
        }
        hud.mode = .lost
    }

    private func releaseHeld(_ actions: inout [EngineAction]) {
        switch press {
        case .left(let count, _, _):
            actions.append(.mouseUp(.left, at: cursor, clickCount: count))
        case .right:
            actions.append(.mouseUp(.right, at: cursor, clickCount: 1))
        case .none: break
        }
        press = .none
        if scroll != nil { endScroll(momentum: false, actions: &actions) }
    }

    private func endScroll(momentum: Bool, actions: inout [EngineAction]) {
        guard let s = scroll else { return }
        actions.append(.scroll(delta: .zero, phase: .ended))
        if momentum, let lastT = s.velocity.last?.time {
            let recent = s.velocity.since(lastT - 0.1)
            if !recent.isEmpty {
                let v = recent.reduce(Vec2.zero) { $0 + $1.value } / Double(recent.count)
                if v.length > config.momentumMinSpeed { actions.append(.scrollMomentum(velocity: v)) }
            }
        }
        scroll = nil
        fistFrames = 0
    }

    private func disengage(_ reason: DisengageReason, _ actions: inout [EngineAction]) {
        releaseHeld(&actions)
        phase = .idle
        peaceSince = nil
        restSince = nil
        flipSince = nil
        precision = 0
        actions.append(.disengaged(reason))
    }
}
