import XCTest
@testable import MaestroCore

/// Drives the engine like the camera would: frames at a fixed rate, a virtual
/// system cursor that follows move/warp actions, and a log of everything emitted.
final class Sim {
    let engine: GestureEngine
    var time: Double = 100
    let fps: Double
    var systemCursor = Vec2(700, 450)
    var lastRealInput: Double?
    var actions: [(time: Double, action: EngineAction)] = []
    var lastHUD = HUDState()
    var rng = SplitMix64(seed: 42)
    var noise: Double = 0

    init(config: MaestroConfig = .default, fps: Double = 30) {
        engine = GestureEngine(config: config, screens: ScreenLayout(screens: [ScreenRect(x: 0, y: 0, width: 1512, height: 982)]))
        self.fps = fps
    }

    var dt: Double { 1 / fps }

    @discardableResult
    func step(_ hands: [SyntheticHand]) -> EngineOutput {
        time += dt
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
    func stepEmpty() { step([]) }

    func hold(_ hand: SyntheticHand, for seconds: Double) {
        for _ in 0..<Int((seconds * fps).rounded()) { step(hand) }
    }

    func empty(for seconds: Double) {
        for _ in 0..<Int((seconds * fps).rounded()) { stepEmpty() }
    }

    /// Moves the hand linearly from its current wrist to `to` over `seconds`,
    /// with an optional per-frame mutation (e.g. closing a pinch on the way).
    @discardableResult
    func move(_ hand: inout SyntheticHand, to: Vec2, over seconds: Double,
              _ mutate: ((inout SyntheticHand, Double) -> Void)? = nil) -> SyntheticHand {
        let from = hand.wrist
        let n = max(Int((seconds * fps).rounded()), 1)
        for i in 1...n {
            let f = Double(i) / Double(n)
            hand.wrist = lerp(from, to, f)
            mutate?(&hand, f)
            step(hand)
        }
        return hand
    }

    /// Open palm held still until engaged.
    func engage(at wrist: Vec2 = Vec2(0.65, 0.6)) -> SyntheticHand {
        let h = SyntheticHand.openPalm(at: wrist)
        hold(h, for: 0.5)
        XCTAssertTrue(engine.isEngaged, "expected engagement")
        return h
    }

    func clear() { actions.removeAll() }

    func count(_ pred: (EngineAction) -> Bool) -> Int { actions.filter { pred($0.action) }.count }

    var downs: [(MouseButton, Vec2, Int)] {
        actions.compactMap { if case .mouseDown(let b, let p, let c) = $0.action { return (b, p, c) }; return nil }
    }

    var ups: [(MouseButton, Vec2, Int)] {
        actions.compactMap { if case .mouseUp(let b, let p, let c) = $0.action { return (b, p, c) }; return nil }
    }

    var swipes: [SwipeDirection] {
        actions.compactMap { if case .swipe(let d) = $0.action { return d }; return nil }
    }

    var scrolls: [(Vec2, ScrollPhase)] {
        actions.compactMap { if case .scroll(let d, let p) = $0.action { return (d, p) }; return nil }
    }

    var disengages: [DisengageReason] {
        actions.compactMap { if case .disengaged(let r) = $0.action { return r }; return nil }
    }
}
