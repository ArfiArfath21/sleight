import Foundation

/// Top level: tracks hands, switches between active and resting, routes frames
/// to command or pointer mode, and steps aside whenever the user touches a real
/// keyboard or trackpad.
///
/// Resting: the camera keeps watching, but only the wake gesture is seen: both
/// open hands raised and held still for a second (or a double clap, if enabled).
/// The same gesture while active rests it.
public final class SleightEngine {
    public var config: SleightConfig {
        didSet { command.config = config; pointer.config = config; twoHands.config = config }
    }
    public var screens: ScreenLayout {
        didSet { pointer.screens = screens }
    }

    public let tracks = HandTracks()
    public let command: CommandEngine
    public let pointer: PointerEngine
    public let twoHands: TwoHandGestures
    public private(set) var mode: Mode = .command
    public private(set) var active = true
    /// Recognise every gesture, assigned or not, and report it (Practice window).
    public var detectAll = false {
        didSet { command.detectAll = detectAll; twoHands.detectAll = detectAll }
    }

    public init(config: SleightConfig = .default, screens: ScreenLayout = .fallback) {
        self.config = config
        self.screens = screens
        command = CommandEngine(config: config)
        pointer = PointerEngine(config: config, screens: screens)
        twoHands = TwoHandGestures(config: config)
    }

    public func process(_ input: FrameInput) -> EngineOutput {
        let t = input.time
        var actions: [EngineAction] = []
        var hud = HUDState()
        hud.cursor = input.systemCursor
        tracks.update(frames: input.hands, time: t, config: config)
        hud.handsVisible = tracks.visible.count
        let pose = tracks.visible.max { $0.scale < $1.scale }?.pose

        // Real keyboard / trackpad use always wins.
        if let real = input.lastRealInput, t - real < config.realInputCooldown {
            actions += leavePointer(reason: .userInput)
            actions += command.cancel()
            twoHands.reset()
            command.quiet(until: real + config.realInputCooldown)
            hud.mode = mode
            hud.active = active
            return EngineOutput(actions: actions, hud: hud, pose: nil)
        }

        let two = twoHands.step(tracks: tracks, time: t)
        var twoHandFired: [EngineAction] = []
        for e in two.events {
            let g: GestureID
            switch e {
            case .curtains: g = .curtains
            case .frame: g = .frame
            case .doubleClap: g = .doubleClap
            case .handsUp, .clap: continue
            }
            twoHandFired += command.fire(g, speed: nil)
        }
        if two.events.contains(.handsUp) || wantsRestToggle(twoHandFired) {
            actions += setActive(!active, time: t)
            if !active { actions += twoHandFired.filter { if case .recognized = $0 { return true }; return false } }
        }

        guard active else {
            hud.active = false
            if two.cue == .clap || two.cue == .handsUp {
                hud.cue = two.cue
                hud.progress = two.progress
            }
            return EngineOutput(actions: actions, hud: hud, pose: pose)
        }

        actions += twoHandFired
        // A forming two-hand gesture outranks anything one hand might be doing.
        if two.busy || !two.events.isEmpty {
            actions += command.cancel()
            command.quiet(until: t + 0.3)
            hud.cue = two.cue
            hud.progress = two.progress
        }

        switch mode {
        case .command:
            let r = command.step(tracks: tracks, time: t, hud: &hud)
            actions += r.actions
            if wantsRestToggle(r.actions) {
                actions += setActive(false, time: t)
                hud.active = false
                return EngineOutput(actions: actions, hud: hud, pose: pose)
            }
            if let hand = r.enterPointer {
                pointer.enter(hand: hand, cursor: input.systemCursor, time: t)
                mode = .pointer
                actions.append(.stopMomentum)
                actions.append(.modeChanged(.pointer, .gesture))
            }
        case .pointer:
            let r = pointer.step(tracks: tracks, time: t, aspect: input.aspect, veeFlick: { [command] hand, flicks in
                command.veeFlick(hand, time: t, settle: 0.1, flicks: &flicks, only: [.up, .down])
            }, hud: &hud)
            actions += r.actions
            if let reason = r.exit {
                actions += pointer.exit()
                mode = .command
                command.quiet(until: t + 0.6)
                actions.append(.modeChanged(.command, reason))
            }
        }

        hud.mode = mode
        hud.active = true
        if mode == .command { hud.cursor = input.systemCursor }
        if tracks.visible.isEmpty, tracks.rejectedSmall { hud.warning = .tooFar }
        return EngineOutput(actions: actions, hud: hud, pose: pose)
    }

    /// A recognised gesture the user assigned to "Rest / wake".
    private func wantsRestToggle(_ actions: [EngineAction]) -> Bool {
        actions.contains { if case .recognized(let g) = $0 { return config.gestures[g] == .restWake }; return false }
    }

    /// Active ↔ resting, from a gesture or from outside (menu, hotkey).
    public func setActive(_ on: Bool, time t: Double) -> [EngineAction] {
        guard on != active else { return [] }
        var actions: [EngineAction] = []
        if !on {
            actions += leavePointer(reason: .resting)
            actions += command.cancel()
            actions.append(.stopMomentum)
        } else {
            // Hands are still up after the wake clap: give them a moment.
            command.quiet(until: t + 0.8)
        }
        active = on
        actions.append(.activeChanged(on))
        return actions
    }

    /// Switch modes from outside (menu, hotkey, mode bar).
    public func setMode(_ m: Mode, systemCursor: Vec2, time t: Double) -> [EngineAction] {
        guard m != mode else { return [] }
        var actions: [EngineAction] = []
        if !active { actions += setActive(true, time: t) }
        if m == .pointer {
            actions += command.cancel()
            pointer.enter(hand: tracks.visible.max { $0.scale < $1.scale }, cursor: systemCursor, time: t)
            mode = .pointer
            actions.append(.modeChanged(.pointer, .manual))
        } else {
            actions += leavePointer(reason: .manual)
            command.quiet(until: t + 0.3)
        }
        return actions
    }

    /// Release everything (camera off / quit).
    public func shutdown() -> [EngineAction] {
        var actions = command.cancel()
        actions += leavePointer(reason: .manual)
        tracks.reset()
        twoHands.reset()
        return actions
    }

    private func leavePointer(reason: ModeChangeReason) -> [EngineAction] {
        guard mode == .pointer else { return [] }
        mode = .command
        return pointer.exit() + [.modeChanged(.command, reason)]
    }
}
