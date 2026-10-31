import Foundation

/// The default mode: a handful of gestures grouped by what you are doing, not by
/// hand shape. Nothing depends on where the hand is, only on its shape and motion.
///
/// | Task      | Gesture                              | Action                          |
/// |-----------|--------------------------------------|---------------------------------|
/// | Reading   | ✌️ flick up / down                    | scroll, with momentum           |
/// |           | ✌️ flick right / left                 | back / forward                  |
/// | Windows   | ✋ swipe right / left                 | switch desktop                  |
/// |           | ✋ swipe up                           | Mission Control                 |
/// |           | ✊ grab, slide sideways, open hand    | switch app (⌘-Tab)              |
/// | Media     | 🤏 tap                                | play / pause                    |
/// |           | 🤏 hold + slide up / down             | volume                          |
/// |           | 🤏 slide right / left                 | next / previous track           |
/// | Aiming    | ☝️ hold                               | pointer mode                    |
///
/// Two-hand gestures (clap, curtains, frame) live in `TwoHandGestures`.
public final class CommandEngine {
    public var config: SleightConfig

    private enum Axis { case horizontal, vertical }

    /// 🤏 held: the media remote.
    private struct Remote {
        var handID: Int
        var start: Double
        var origin: Vec2
        var axis: Axis?
        var base = 0.0
        var index = 0
    }

    /// ✊ held: the app switcher.
    private struct Grab {
        var handID: Int
        var origin: Vec2
        var open = false
        var base = 0.0
        var index = 0
    }

    private var swipes = FlickDetector()
    private var flicks = FlickDetector()
    private var remote: Remote?
    private var grab: Grab?
    private var pointSince: Double?
    private var quietUntil = -Double.infinity

    public init(config: SleightConfig = .default) { self.config = config }

    /// Ignore everything until `time`.
    public func quiet(until time: Double) {
        quietUntil = max(quietUntil, time)
        pointSince = nil
    }

    /// Abandon whatever is in progress, leaving the OS clean (never ⌘ held down).
    public func cancel() -> [EngineAction] {
        defer {
            remote = nil
            grab = nil
            pointSince = nil
            swipes.reset()
            flicks.reset()
        }
        return grab?.open == true ? [.switcher(.cancel)] : []
    }

    public struct Result {
        public var actions: [EngineAction] = []
        public var enterPointer: TrackedHand?
    }

    public func step(tracks: HandTracks, time t: Double, hud: inout HUDState) -> Result {
        var r = Result()
        guard t >= quietUntil else { return r }

        if remote != nil { stepRemote(tracks: tracks, time: t, hud: &hud, result: &r); return r }
        if grab != nil { stepGrab(tracks: tracks, time: t, hud: &hud, result: &r); return r }

        let ready = tracks.visible.filter { $0.anchor.y < config.activeBelowLine }
        guard let hand = primary(ready) else { pointSince = nil; return r }
        let settled = t - hand.firstSeen >= config.settleTime

        if hand.pinchBegan, settled {
            remote = Remote(handID: hand.id, start: t, origin: hand.anchor)
            hud.cue = .media
            pointSince = nil
            return r
        }
        if config.grabEnabled, hand.shape(heldFor: config.settleTime, at: t) == .fist, settled {
            grab = Grab(handID: hand.id, origin: hand.anchor)
            hud.cue = .grab
            pointSince = nil
            return r
        }

        if hand.shape != .point { pointSince = nil }

        switch hand.shape {
        case .open:
            hud.cue = .swipe
            guard config.swipesEnabled else { break }
            var allow: Set<FlickDirection> = [.left, .right, .up]
            if config.swipeDownEnabled { allow.insert(.down) }
            let th = FlickDetector.Thresholds(minSpeed: config.swipeMinSpeed, minDistance: config.swipeMinDistance,
                                              window: config.swipeWindow, dominance: config.swipeAxisDominance,
                                              repeatGap: config.flickRepeatGap, returnGap: config.flickReturnGap)
            if let f = swipes.detect(hand, shape: .open, at: t, settle: config.settleTime, allow: allow, th) {
                switch f.direction {
                // Content follows the hand, like the trackpad.
                case .right: r.actions.append(.shortcut(.spaceLeft))
                case .left: r.actions.append(.shortcut(.spaceRight))
                case .up: r.actions.append(.shortcut(.missionControl))
                case .down: r.actions.append(.shortcut(.appExpose))
                }
            }

        case .vee:
            hud.cue = .scroll
            if let f = flicks.detect(hand, shape: .vee, at: t, settle: config.settleTime,
                                     allow: config.backForwardEnabled ? [.up, .down, .left, .right] : [.up, .down],
                                     flickThresholds) {
                r.actions += flickActions(f)
            }

        case .point:
            hud.cue = .point
            if hand.speed < config.pointMaxSpeed {
                let since = pointSince ?? max(t, hand.shapeSince)
                pointSince = since
                hud.progress = clamp((t - since) / config.pointHoldTime, 0, 1)
                if t - since >= config.pointHoldTime {
                    r.enterPointer = hand
                    pointSince = nil
                }
            } else {
                pointSince = nil
            }

        case .fist, .other:
            break
        }
        return r
    }

    var flickThresholds: FlickDetector.Thresholds {
        FlickDetector.Thresholds(minSpeed: config.flickMinSpeed, minDistance: config.flickMinDistance,
                                 window: config.flickWindow, dominance: config.swipeAxisDominance,
                                 repeatGap: config.flickRepeatGap, returnGap: config.flickReturnGap)
    }

    /// ✌️ flick → scroll momentum or back/forward. Shared with pointer mode.
    func flickActions(_ f: Flick) -> [EngineAction] {
        let mag = clamp(f.speed * config.scrollFlickGain, config.scrollFlickMin, config.scrollFlickMax)
        // Wheel axis: negative y = content moves up (reveals what is below).
        let natural: Double = config.scrollNatural ? 1 : -1
        switch f.direction {
        case .up: return [.scrollFlick(velocity: Vec2(0, -mag * natural))]
        case .down: return [.scrollFlick(velocity: Vec2(0, mag * natural))]
        case .right: return [.shortcut(.back)]
        case .left: return [.shortcut(.forward)]
        }
    }

    /// The hand to listen to: one that is pinching, else one holding a gesture
    /// shape, else the biggest.
    private func primary(_ hands: [TrackedHand]) -> TrackedHand? {
        func rank(_ h: TrackedHand) -> Int {
            if h.pinched { return 0 }
            switch h.shape {
            case .vee, .point, .fist: return 1
            case .open: return 2
            case .other: return 3
            }
        }
        return hands.min { a, b in rank(a) != rank(b) ? rank(a) < rank(b) : a.scale > b.scale }
    }

    /// Steps centred on multiples of `step` with a hysteresis band, so sliding
    /// back feels exactly like sliding forward and never flickers.
    private func stepper(_ pos: Double, _ step: Double, index: inout Int,
                         up: EngineAction, down: EngineAction, into actions: inout [EngineAction]) {
        while pos - Double(index) * step > 0.65 * step { index += 1; actions.append(up) }
        while Double(index) * step - pos > 0.65 * step { index -= 1; actions.append(down) }
    }

    // MARK: 🤏 media remote

    private func stepRemote(tracks: HandTracks, time t: Double, hud: inout HUDState, result r: inout Result) {
        guard var m = remote else { return }
        guard let hand = tracks.hand(id: m.handID) else { remote = nil; return }
        hud.cue = m.axis == .vertical ? .volume : .media
        guard hand.visible else { return }

        if hand.pinchEnded || !hand.pinched {
            if m.axis == nil, t - m.start <= config.pinchTapMax { r.actions.append(.media(.playPause)) }
            remote = nil
            return
        }

        let offset = (hand.anchor - m.origin) / hand.scale
        if m.axis == nil, offset.length >= config.pinchAxisLock {
            if abs(offset.y) >= abs(offset.x) {
                m.axis = .vertical
                m.base = offset.y
                r.actions.append(.media(offset.y < 0 ? .volumeUp : .volumeDown))
            } else {
                m.axis = .horizontal
                // One skip per pinch: right = next track.
                if config.trackSkipEnabled { r.actions.append(.media(offset.x > 0 ? .next : .previous)) }
            }
        }
        if m.axis == .vertical {
            // Hand up (negative y) = louder.
            stepper(m.base - offset.y, config.volumeStep, index: &m.index,
                    up: .media(.volumeUp), down: .media(.volumeDown), into: &r.actions)
        }
        remote = m
    }

    // MARK: ✊ app switcher

    private func stepGrab(tracks: HandTracks, time t: Double, hud: inout HUDState, result r: inout Result) {
        guard var g = grab else { return }
        guard let hand = tracks.hand(id: g.handID) else {
            if g.open { r.actions.append(.switcher(.cancel)) }
            grab = nil
            return
        }
        hud.cue = g.open ? .apps : .grab
        guard hand.visible else { return }

        // Opening the hand drops the selection.
        if hand.shape != .fist {
            if g.open { r.actions.append(.switcher(.commit)) }
            grab = nil
            return
        }

        let offset = (hand.anchor - g.origin) / hand.scale
        if !g.open, abs(offset.x) >= config.grabLock, abs(offset.x) > abs(offset.y) {
            g.open = true
            g.base = offset.x
            // ⌘-Tab already selects the next app.
            r.actions.append(.switcher(.begin))
        }
        if g.open {
            stepper(offset.x - g.base, config.appStep, index: &g.index,
                    up: .switcher(.next), down: .switcher(.previous), into: &r.actions)
        }
        grab = g
    }
}
