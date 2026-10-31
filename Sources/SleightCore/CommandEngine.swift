import Foundation

/// The default mode: a handful of coarse gestures that work wherever your hand
/// happens to be. The hand's *shape* chooses the family, its *motion* chooses
/// the action; nothing depends on aiming.
///
/// | Shape          | Motion                 | Action                                   |
/// |----------------|------------------------|------------------------------------------|
/// | ✌️ two fingers  | flick up / down        | scroll, with momentum (flick again to go further) |
/// | ✌️ two fingers  | flick left / right     | back / forward                           |
/// | ✋ open hand    | swipe left / right     | switch desktop / full-screen app         |
/// | ✋ open hand    | swipe up               | Mission Control                          |
/// | 🤏 pinch        | tap (pinch + release)  | play / pause                             |
/// | 🤏 pinch        | hold + slide sideways  | app switcher (⌘-Tab), release to pick    |
/// | 🤏 pinch        | hold + slide up / down | volume                                   |
/// | ☝️ point        | hold still             | pointer mode                             |
/// | 👐 both hands   | spread / squeeze       | zoom in / out                            |
public final class CommandEngine {
    public var config: SleightConfig

    private enum Axis { case horizontal, vertical }

    private struct Slider {
        var handID: Int
        var start: Double
        var origin: Vec2
        var axis: Axis?
        /// Offset along the axis where it locked; steps count from here.
        var base = 0.0
        var index = 0
        var switcherOpen = false
    }

    private var swipes = FlickDetector()
    private var flicks = FlickDetector()
    private var slider: Slider?
    private var pointSince: Double?
    private var zoomBase: Double?
    private var quietUntil = -Double.infinity

    public init(config: SleightConfig = .default) { self.config = config }

    /// Ignore everything until `time` (after leaving pointer mode, the fist
    /// that ended it must not trigger anything).
    public func quiet(until time: Double) {
        quietUntil = max(quietUntil, time)
        pointSince = nil
        zoomBase = nil
    }

    /// Abandon whatever is in progress. Returns the actions needed to leave the
    /// OS in a clean state (e.g. close the app switcher without switching).
    public func cancel() -> [EngineAction] {
        defer {
            slider = nil
            pointSince = nil
            zoomBase = nil
            swipes.reset()
            flicks.reset()
        }
        if slider?.switcherOpen == true { return [.switcher(.cancel)] }
        return []
    }

    public struct Result {
        public var actions: [EngineAction] = []
        public var enterPointer: TrackedHand?
    }

    public func step(tracks: HandTracks, time t: Double, hud: inout HUDState) -> Result {
        var r = Result()
        guard t >= quietUntil else { return r }

        if slider != nil {
            stepSlider(tracks: tracks, time: t, hud: &hud, result: &r)
            return r
        }

        let ready = tracks.visible.filter { $0.anchor.y < config.activeBelowLine }

        // Two open hands: zoom, and nothing else.
        if config.zoomEnabled, ready.count == 2,
           ready.allSatisfy({ $0.shape(heldFor: config.settleTime, at: t) == .open }) {
            let a = ready[0], b = ready[1]
            let d = distance(a.anchor, b.anchor) / ((a.scale + b.scale) / 2)
            if let base = zoomBase {
                if d / base >= config.zoomStepRatio {
                    r.actions.append(.shortcut(.zoomIn)); zoomBase = d
                } else if base / d >= config.zoomStepRatio {
                    r.actions.append(.shortcut(.zoomOut)); zoomBase = d
                }
            } else {
                zoomBase = d
            }
            hud.cue = .zoom
            pointSince = nil
            return r
        }
        zoomBase = nil

        guard let hand = primary(ready) else {
            pointSince = nil
            return r
        }

        // A pinch starts the slider (tap = play/pause, slide = apps or volume).
        if hand.pinchBegan, t - hand.firstSeen >= config.settleTime {
            slider = Slider(handID: hand.id, start: t, origin: hand.anchor)
            hud.cue = .pinch
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
                // Content follows the hand, like the trackpad: pushing right
                // reveals the desktop on the left.
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

    /// Two-finger flick → scroll momentum or back/forward. Shared with pointer mode.
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

    /// The hand to listen to: one that is pinching, else the one holding a
    /// gesture shape, else the biggest.
    private func primary(_ hands: [TrackedHand]) -> TrackedHand? {
        func rank(_ h: TrackedHand) -> Int {
            if h.pinched { return 0 }
            switch h.shape {
            case .vee, .point: return 1
            case .open: return 2
            default: return 3
            }
        }
        return hands.min { a, b in
            rank(a) != rank(b) ? rank(a) < rank(b) : a.scale > b.scale
        }
    }

    private func stepSlider(tracks: HandTracks, time t: Double, hud: inout HUDState, result r: inout Result) {
        guard var s = slider else { return }
        guard let hand = tracks.hand(id: s.handID) else {
            // Hand gone: never leave ⌘ held down.
            if s.switcherOpen { r.actions.append(.switcher(.cancel)) }
            slider = nil
            return
        }
        guard hand.visible else {
            hud.cue = s.axis == nil ? .pinch : (s.axis == .horizontal ? .apps : .volume)
            return
        }

        if hand.pinchEnded || !hand.pinched {
            if s.axis == nil, t - s.start <= config.pinchTapMax {
                r.actions.append(.media(.playPause))
            }
            if s.switcherOpen { r.actions.append(.switcher(.commit)) }
            slider = nil
            return
        }

        let offset = (hand.anchor - s.origin) / hand.scale
        if s.axis == nil, offset.length >= config.pinchAxisLock {
            if abs(offset.x) >= abs(offset.y) {
                s.axis = .horizontal
                s.base = offset.x
                s.switcherOpen = true
                // ⌘-Tab already selects the next app.
                r.actions.append(.switcher(.begin))
            } else {
                s.axis = .vertical
                s.base = offset.y
                r.actions.append(.media(offset.y < 0 ? .volumeUp : .volumeDown))
            }
        }
        // Steps are centred on multiples of the step size with a hysteresis band,
        // so sliding back feels exactly like sliding forward and never flickers.
        func stepper(_ pos: Double, _ step: Double, up: EngineAction, down: EngineAction) {
            while pos - Double(s.index) * step > 0.65 * step { s.index += 1; r.actions.append(up) }
            while Double(s.index) * step - pos > 0.65 * step { s.index -= 1; r.actions.append(down) }
        }
        switch s.axis {
        case .horizontal:
            stepper(offset.x - s.base, config.appStep, up: .switcher(.next), down: .switcher(.previous))
            hud.cue = .apps
        case .vertical:
            // Hand up (negative y) = louder.
            stepper(s.base - offset.y, config.volumeStep, up: .media(.volumeUp), down: .media(.volumeDown))
            hud.cue = .volume
        case nil:
            hud.cue = .pinch
        }
        slider = s
    }
}
