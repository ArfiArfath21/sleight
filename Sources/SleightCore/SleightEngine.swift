import Foundation

/// Top level: tracks hands, routes frames to command or pointer mode, and
/// steps aside whenever the user touches a real keyboard or trackpad.
public final class SleightEngine {
    public var config: SleightConfig {
        didSet { command.config = config; pointer.config = config }
    }
    public var screens: ScreenLayout {
        didSet { pointer.screens = screens }
    }

    public let tracks = HandTracks()
    public let command: CommandEngine
    public let pointer: PointerEngine
    public private(set) var mode: Mode = .command

    public init(config: SleightConfig = .default, screens: ScreenLayout = .fallback) {
        self.config = config
        self.screens = screens
        command = CommandEngine(config: config)
        pointer = PointerEngine(config: config, screens: screens)
    }

    public func process(_ input: FrameInput) -> EngineOutput {
        let t = input.time
        var actions: [EngineAction] = []
        var hud = HUDState()
        tracks.update(frames: input.hands, time: t, config: config)

        // Real keyboard / trackpad use always wins.
        if let real = input.lastRealInput, t - real < config.realInputCooldown {
            if mode == .pointer {
                actions += pointer.exit()
                mode = .command
                actions.append(.modeChanged(.command, .userInput))
            }
            actions += command.cancel()
            command.quiet(until: real + config.realInputCooldown)
            hud.mode = mode
            hud.cursor = input.systemCursor
            return EngineOutput(actions: actions, hud: hud, pose: nil)
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
        if mode == .command { hud.cursor = input.systemCursor }
        hud.handsVisible = tracks.visible.count
        if tracks.visible.isEmpty, tracks.rejectedSmall { hud.warning = .tooFar }
        let pose = tracks.visible.max { $0.scale < $1.scale }?.pose
        return EngineOutput(actions: actions, hud: hud, pose: pose)
    }

    /// Switch modes from outside (menu, hotkey).
    public func setMode(_ m: Mode, systemCursor: Vec2, time t: Double) -> [EngineAction] {
        guard m != mode else { return [] }
        var actions: [EngineAction] = []
        if m == .pointer {
            actions += command.cancel()
            pointer.enter(hand: tracks.visible.max { $0.scale < $1.scale }, cursor: systemCursor, time: t)
        } else {
            actions += pointer.exit()
            command.quiet(until: t + 0.3)
        }
        mode = m
        actions.append(.modeChanged(m, .manual))
        return actions
    }

    /// Release everything (pause / quit).
    public func shutdown() -> [EngineAction] {
        var actions = command.cancel()
        if mode == .pointer {
            actions += pointer.exit()
            mode = .command
            actions.append(.modeChanged(.command, .manual))
        }
        tracks.reset()
        return actions
    }
}
