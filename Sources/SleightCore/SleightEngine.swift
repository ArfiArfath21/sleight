import Foundation

/// Top level: tracks hands, switches between active and resting, routes frames
/// to command or pointer mode, and steps aside whenever the user touches a real
/// keyboard or trackpad.
///
/// Resting: the camera keeps watching, but only a double clap (👏👏) is heard,
/// which makes Sleight active again. A double clap while active rests it.
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
        if two.events.contains(.doubleClap) {
            actions += setActive(!active, time: t)
        }

        guard active else {
            hud.active = false
            hud.cue = two.cue == .clap ? .clap : nil
            return EngineOutput(actions: actions, hud: hud, pose: pose)
        }

        for e in two.events {
            switch e {
            case .curtains: actions.append(.shortcut(.showDesktop))
            case .frame: actions.append(.shortcut(.screenshot))
            case .clap, .doubleClap: break
            }
        }
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
            if let hand = r.enterPointer {
                pointer.enter(hand: hand, cursor: input.systemCursor, time: t)
                mode = .pointer
                actions.append(.stopMomentum)
                actions.append(.modeChanged(.pointer, .gesture))
            }
        case .pointer:
            let r = pointer.step(tracks: tracks, time: t, aspect: input.aspect,
                                 flickActions: command.flickActions, hud: &hud)
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
