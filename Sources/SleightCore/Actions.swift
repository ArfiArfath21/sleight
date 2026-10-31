import Foundation

public enum HandShape: String, Codable, Sendable, CaseIterable {
    case open, vee, point, fist, other
}

public enum MouseButton: String, Codable, Sendable { case left, right }

public enum Mode: String, Codable, Sendable { case command, pointer }

public enum ModeChangeReason: String, Codable, Sendable {
    case gesture, lost, rested, flipped, userInput, manual, resting
}

/// Keyboard shortcuts the gestures trigger. Kept to what macOS ships enabled by
/// default (Mission Control shortcuts) or what every app understands.
public enum Shortcut: String, Codable, Sendable {
    case back, forward            // ⌘[ ⌘]
    case spaceLeft, spaceRight    // ⌃← ⌃→
    case missionControl           // ⌃↑
    case appExpose                // ⌃↓
    case showDesktop              // F11
    case screenshot               // ⌘⇧3
}

public enum MediaKey: String, Codable, Sendable {
    case playPause, volumeUp, volumeDown, next, previous
}

/// ⌘-Tab, driven step by step: begin holds ⌘ and shows the switcher.
public enum SwitcherStep: String, Codable, Sendable {
    case begin, next, previous, commit, cancel
}

/// What the engine wants the OS to do. Positions are global CG coordinates.
public enum EngineAction: Equatable, Sendable {
    // Pointer mode.
    case move(to: Vec2)
    case warp(to: Vec2)
    case mouseDown(MouseButton, at: Vec2, clickCount: Int)
    case mouseUp(MouseButton, at: Vec2, clickCount: Int)
    // Scrolling: a flick adds momentum (pt/s, wheel axes: +y = content down).
    case scrollFlick(velocity: Vec2)
    case stopMomentum
    // Commands.
    case shortcut(Shortcut)
    case media(MediaKey)
    case switcher(SwitcherStep)
    case modeChanged(Mode, ModeChangeReason)
    /// Gestures switched on (active) or off (resting, camera still watching).
    case activeChanged(Bool)
}

/// What the HUD should show. Cheap to compute every frame.
public struct HUDState: Equatable, Sendable {
    public enum PointerState: String, Sendable {
        case engaged, pressing, dragging, rightPressing, lost
    }

    public enum Warning: String, Sendable {
        case tooFar, lowLight, lowFPS, nearEdge
    }

    /// What the hands in view are about to do, in command mode.
    public enum Cue: String, Sendable {
        case swipe       // open palm: desktops / Mission Control
        case scroll      // ✌️: flick to scroll, sideways for back/forward
        case media       // 🤏: tap play/pause, slide volume, flick tracks
        case volume      // 🤏 sliding vertically
        case grab        // ✊: slide to switch apps
        case apps        // ✊ sliding: app switcher open
        case point       // ☝️: hold for pointer mode
        case curtains    // 🖐🖐 held together: part them to show the desktop
        case frame       // two "L" hands: hold to take a screenshot
        case clap        // first clap heard: clap again
        case handsUp     // both hands raised and still: hold to rest / wake
    }

    public var mode: Mode = .command
    /// false = resting: watching only for the wake clap.
    public var active = true
    public var handsVisible = 0
    public var cue: Cue?
    /// 0…1 for hold-to-trigger gestures (point → pointer, fist → exit).
    public var progress: Double = 0
    public var warning: Warning?

    // Pointer mode.
    public var pointer: PointerState = .engaged
    public var cursor: Vec2 = .zero
    public var pinchProgress: Double = 0
    public var precision: Double = 0

    public init() {}
}

public struct EngineOutput: Sendable {
    public var actions: [EngineAction]
    public var hud: HUDState
    /// The hand that drove this frame, for the preview window.
    public var pose: HandPose?
}
