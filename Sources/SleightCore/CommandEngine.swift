import Foundation

/// The default mode. Recognises one-hand gestures and fires whatever the user
/// assigned to each (`SleightConfig.gestures`). Recognition depends on the hand's
/// shape and motion only, never on where the hand is.
///
/// - ✌️ flick up / down / left / right
/// - ✋ swipe up / down / left / right
/// - 👌 tap; 👌 hold, then slide up/down or sideways (sliders)
/// - ✊ grab, then slide sideways (slider)
/// - ☝️ hold: pointer mode (reserved)
///
/// Gestures assigned to "Nothing" are not even looked for, so they can never
/// interfere with the ones in use.
public final class CommandEngine {
    public var config: SleightConfig
    /// Recognise every gesture, assigned or not (Practice window).
    public var detectAll = false

    private enum Axis { case horizontal, vertical }

    /// 👌 held.
    private struct Remote {
        var handID: Int
        var start: Double
        var origin: Vec2
        var axis: Axis?
        var action: ActionID = .none
        var base = 0.0
        var index = 0
    }

    /// ✊ held.
    private struct Grab {
        var handID: Int
        var origin: Vec2
        var action: ActionID
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

    private func wanted(_ g: GestureID) -> Bool { detectAll || config.gestures.isAssigned(g) }

    /// Ignore everything until `time`.
    public func quiet(until time: Double) {
        quietUntil = max(quietUntil, time)
        pointSince = nil
    }

    /// Abandon whatever is in progress, leaving the OS clean (never ⌘ held down).
    public func cancel() -> [EngineAction] {
        var out: [EngineAction] = []
        if let g = grab, g.open { out += ActionMapper.end(g.action, cancelled: true) }
        if let m = remote, m.axis != nil { out += ActionMapper.end(m.action, cancelled: true) }
        remote = nil
        grab = nil
        pointSince = nil
        swipes.reset()
        flicks.reset()
        return out
    }

    public struct Result {
        public var actions: [EngineAction] = []
        public var enterPointer: TrackedHand?
    }

    /// The action for a recognised one-shot gesture, plus the recognition event.
    func fire(_ g: GestureID, speed: Double?) -> [EngineAction] {
        [.recognized(g)] + ActionMapper.fire(config.gestures[g], speed: speed, config: config)
    }

    public func step(tracks: HandTracks, time t: Double, hud: inout HUDState) -> Result {
        var r = Result()
        guard t >= quietUntil else { return r }

        if remote != nil { stepRemote(tracks: tracks, time: t, hud: &hud, result: &r); return r }
        if grab != nil { stepGrab(tracks: tracks, time: t, hud: &hud, result: &r); return r }

        // Hands resting low (on the keyboard) are ignored, but a flick that
        // carries the hand down into that zone is still followed.
        let ready = tracks.visible.filter { $0.wasAbove(config.activeBelowLine, within: 0.5, at: t) }
        guard let hand = primary(ready) else { pointSince = nil; return r }
        let settled = t - hand.firstSeen >= config.settleTime

        let okWanted = wanted(.okTap) || wanted(.okSlideVertical) || wanted(.okSlideSideways)
        if okWanted, hand.pinchBegan, settled, hand.pinchDeliberate,
           hand.pinchOKSign || !config.mediaNeedsOKSign {
            remote = Remote(handID: hand.id, start: t, origin: hand.anchor)
            hud.cue = .ok
            pointSince = nil
            return r
        }
        if wanted(.fistSlideSideways), hand.shape(heldFor: config.settleTime, at: t) == .fist, settled {
            grab = Grab(handID: hand.id, origin: hand.anchor, action: config.gestures[.fistSlideSideways])
            hud.cue = .fist
            pointSince = nil
            return r
        }

        if hand.shape != .point { pointSince = nil }

        switch hand.shape {
        case .open:
            let slots: [(FlickDirection, GestureID)] = [(.left, .openSwipeLeft), (.right, .openSwipeRight),
                                                        (.up, .openSwipeUp), (.down, .openSwipeDown)]
            let allow = Set(slots.filter { wanted($0.1) }.map(\.0))
            guard !allow.isEmpty else { break }
            hud.cue = .open
            let th = FlickDetector.Thresholds(minSpeed: config.swipeMinSpeed, minDistance: config.swipeMinDistance,
                                              window: config.swipeWindow, dominance: config.swipeAxisDominance,
                                              repeatGap: config.flickRepeatGap, returnGap: config.flickReturnGap)
            if let f = swipes.detect(hand, shape: .open, at: t, settle: config.settleTime, allow: allow, th),
               let g = slots.first(where: { $0.0 == f.direction })?.1 {
                r.actions += fire(g, speed: f.speed)
            }

        case .vee:
            if let actions = veeFlick(hand, time: t, settle: config.settleTime, flicks: &flicks) {
                hud.cue = .vee
                r.actions += actions
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

    /// ✌️ flicks, shared with pointer mode. nil = no ✌️ gesture is assigned.
    func veeFlick(_ hand: TrackedHand, time t: Double, settle: Double, flicks: inout FlickDetector,
                  only: Set<FlickDirection>? = nil) -> [EngineAction]? {
        let slots: [(FlickDirection, GestureID)] = [(.up, .veeFlickUp), (.down, .veeFlickDown),
                                                    (.left, .veeFlickLeft), (.right, .veeFlickRight)]
        var allow = Set(slots.filter { wanted($0.1) }.map(\.0))
        if let only { allow.formIntersection(only) }
        guard !allow.isEmpty else { return nil }
        let th = FlickDetector.Thresholds(minSpeed: config.flickMinSpeed, minDistance: config.flickMinDistance,
                                          window: config.flickWindow, dominance: config.swipeAxisDominance,
                                          repeatGap: config.flickRepeatGap, returnGap: config.flickReturnGap)
        guard let f = flicks.detect(hand, shape: .vee, at: t, settle: settle, allow: allow, th),
              let g = slots.first(where: { $0.0 == f.direction })?.1 else { return [] }
        return fire(g, speed: f.speed)
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
    private func stepper(_ pos: Double, _ step: Double, index: inout Int, action: ActionID,
                         into actions: inout [EngineAction]) {
        while pos - Double(index) * step > 0.65 * step {
            index += 1
            actions += ActionMapper.step(action, forward: true)
        }
        while Double(index) * step - pos > 0.65 * step {
            index -= 1
            actions += ActionMapper.step(action, forward: false)
        }
    }

    // MARK: 👌

    private func stepRemote(tracks: HandTracks, time t: Double, hud: inout HUDState, result r: inout Result) {
        guard var m = remote else { return }
        guard let hand = tracks.hand(id: m.handID) else {
            if m.axis != nil { r.actions += ActionMapper.end(m.action, cancelled: true) }
            remote = nil
            return
        }
        switch m.axis {
        case .vertical: hud.cue = .okSlideVertical
        case .horizontal: hud.cue = .okSlideSideways
        case nil: hud.cue = .ok
        }
        guard hand.visible else { return }

        if hand.pinchEnded || !hand.pinched {
            if m.axis == nil, t - m.start <= config.pinchTapMax, wanted(.okTap) {
                r.actions += fire(.okTap, speed: nil)
            }
            if m.axis != nil { r.actions += ActionMapper.end(m.action, cancelled: false) }
            remote = nil
            return
        }

        let offset = (hand.anchor - m.origin) / hand.scale
        // A hand that pinched while moving is not using the remote: drop it silently.
        if t - m.start < config.mediaHold {
            if offset.length > config.mediaEarlyMoveCancel { remote = nil }
            return
        }
        if m.axis == nil, offset.length >= config.pinchAxisLock {
            let vertical = abs(offset.y) >= abs(offset.x)
            let g: GestureID = vertical ? .okSlideVertical : .okSlideSideways
            guard wanted(g) else { remote = nil; return }
            m.axis = vertical ? .vertical : .horizontal
            m.action = config.gestures[g]
            m.base = vertical ? offset.y : offset.x
            r.actions.append(.recognized(g))
            // Up and right are "forward".
            r.actions += ActionMapper.begin(m.action, forward: vertical ? offset.y < 0 : offset.x > 0)
        }
        switch m.axis {
        case .vertical:
            stepper(m.base - offset.y, config.volumeStep, index: &m.index, action: m.action, into: &r.actions)
        case .horizontal:
            stepper(offset.x - m.base, config.appStep, index: &m.index, action: m.action, into: &r.actions)
        case nil:
            break
        }
        remote = m
    }

    // MARK: ✊

    private func stepGrab(tracks: HandTracks, time t: Double, hud: inout HUDState, result r: inout Result) {
        guard var g = grab else { return }
        guard let hand = tracks.hand(id: g.handID) else {
            if g.open { r.actions += ActionMapper.end(g.action, cancelled: true) }
            grab = nil
            return
        }
        hud.cue = g.open ? .fistSliding : .fist
        guard hand.visible else { return }

        // Opening the hand ends the slide (and picks the app, for the switcher).
        if hand.shape != .fist {
            if g.open { r.actions += ActionMapper.end(g.action, cancelled: false) }
            grab = nil
            return
        }

        let offset = (hand.anchor - g.origin) / hand.scale
        if !g.open, abs(offset.x) >= config.grabLock, abs(offset.x) > abs(offset.y) {
            g.open = true
            g.base = offset.x
            r.actions.append(.recognized(.fistSlideSideways))
            r.actions += ActionMapper.begin(g.action, forward: offset.x > 0)
        }
        if g.open {
            stepper(offset.x - g.base, config.appStep, index: &g.index, action: g.action, into: &r.actions)
        }
        grab = g
    }
}
