import XCTest
@testable import SleightCore

/// Drives the engine like the camera would: frames at a fixed rate, a virtual
/// system cursor that follows move/warp actions, and a log of everything emitted.
final class Sim {
    let engine: SleightEngine
    var time: Double = 100
    let fps: Double
    var systemCursor = Vec2(700, 450)
    var lastRealInput: Double?
    var actions: [(time: Double, action: EngineAction)] = []
    var lastHUD = HUDState()
    var rng = SplitMix64(seed: 42)
    var noise: Double = 0

    init(config: SleightConfig = .default, fps: Double = 30) {
        engine = SleightEngine(config: config, screens: ScreenLayout(screens: [ScreenRect(x: 0, y: 0, width: 1512, height: 982)]))
        self.fps = fps
    }

    var mode: Mode { engine.mode }

    @discardableResult
    func step(_ hands: [SyntheticHand]) -> EngineOutput {
        time += 1 / fps
        let frames = hands.map { noise > 0 ? $0.frame(noise: noise, rng: &rng) : $0.frame() }
        let out = engine.process(FrameInput(time: time, hands: frames, systemCursor: systemCursor,
                                            lastRealInput: lastRealInput))
        for a in out.actions {
            actions.append((time, a))
            switch a {
            case .move(let p), .warp(let p): systemCursor = p
            case .mouseDown(_, let p, _), .mouseUp(_, let p, _): systemCursor = p
            default: break
            }
        }
        lastHUD = out.hud
        return out
    }

    func step(_ hand: SyntheticHand) { step([hand]) }

    func hold(_ hands: [SyntheticHand], for seconds: Double) {
        for _ in 0..<Int((seconds * fps).rounded()) { step(hands) }
    }

    func hold(_ hand: SyntheticHand, for seconds: Double) { hold([hand], for: seconds) }

    func empty(for seconds: Double) { hold([], for: seconds) }

    /// Moves the hand linearly to `to` over `seconds`, optionally mutating it on the way.
    func move(_ hand: inout SyntheticHand, to: Vec2, over seconds: Double,
              _ mutate: ((inout SyntheticHand, Double) -> Void)? = nil) {
        let from = hand.wrist
        let n = max(Int((seconds * fps).rounded()), 1)
        for i in 1...n {
            let f = Double(i) / Double(n)
            hand.wrist = lerp(from, to, f)
            mutate?(&hand, f)
            step(hand)
        }
    }

    func move(_ hand: inout SyntheticHand, by delta: Vec2, over seconds: Double,
              _ mutate: ((inout SyntheticHand, Double) -> Void)? = nil) {
        move(&hand, to: hand.wrist + delta, over: seconds, mutate)
    }

    func pinch(_ h: inout SyntheticHand, over seconds: Double = 0.1, drift: Vec2 = .zero) {
        move(&h, by: drift, over: seconds) { hand, f in hand.pinch = f; hand.fingers[0] = lerp(1, 0.6, f) }
    }

    func unpinch(_ h: inout SyntheticHand, over seconds: Double = 0.1) {
        move(&h, by: .zero, over: seconds) { hand, f in hand.pinch = 1 - f; hand.fingers[0] = lerp(0.6, 1, f) }
    }

    /// Point and hold until pointer mode starts.
    func enterPointer(at wrist: Vec2 = Vec2(0.65, 0.6)) -> SyntheticHand {
        let p = SyntheticHand.point(at: wrist)
        hold(p, for: 0.8)
        XCTAssertEqual(engine.mode, .pointer, "expected pointer mode")
        // Relax into a loosely open hand for pointing.
        var h = SyntheticHand.relaxed(at: wrist)
        h.fingers = [1, 0.9, 0.85, 0.85]
        hold(h, for: 0.2)
        return h
    }

    func clear() { actions.removeAll() }

    func count(_ pred: (EngineAction) -> Bool) -> Int { actions.filter { pred($0.action) }.count }

    var all: [EngineAction] { actions.map(\.action) }

    var shortcuts: [Shortcut] { all.compactMap { if case .shortcut(let s) = $0 { return s }; return nil } }
    var media: [MediaKey] { all.compactMap { if case .media(let m) = $0 { return m }; return nil } }
    var switcher: [SwitcherStep] { all.compactMap { if case .switcher(let s) = $0 { return s }; return nil } }
    var flicks: [Vec2] { all.compactMap { if case .scrollFlick(let v) = $0 { return v }; return nil } }
    var modes: [(Mode, ModeChangeReason)] { all.compactMap { if case .modeChanged(let m, let r) = $0 { return (m, r) }; return nil } }

    var downs: [(MouseButton, Vec2, Int)] {
        all.compactMap { if case .mouseDown(let b, let p, let c) = $0 { return (b, p, c) }; return nil }
    }

    var ups: [(MouseButton, Vec2, Int)] {
        all.compactMap { if case .mouseUp(let b, let p, let c) = $0 { return (b, p, c) }; return nil }
    }

    /// Anything that changes the OS (everything except mode bookkeeping).
    var effects: [EngineAction] {
        all.filter { if case .modeChanged = $0 { return false }; if case .stopMomentum = $0 { return false }; return true }
    }
}
