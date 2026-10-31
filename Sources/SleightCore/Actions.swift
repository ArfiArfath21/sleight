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
    case nextTab, previousTab     // ⌃⇥ ⌃⇧⇥
    case newTab, reopenTab        // ⌘T ⌘⇧T
    case spaceLeft, spaceRight    // ⌃← ⌃→
    case missionControl           // ⌃↑
    case appExpose                // ⌃↓
    case showDesktop              // F11
    case hideApp, minimize        // ⌘H ⌘M
    case fullScreen               // ⌃⌘F
    case zoomIn, zoomOut          // ⌘= ⌘-
    case arrowLeft, arrowRight, arrowUp, arrowDown
    case screenshot               // ⌘⇧3
    case screenshotSelection      // ⌘⇧4
    case screenshotTool           // ⌘⇧5
    case spotlight                // ⌘Space
    case lockScreen               // ⌃⌘Q
}

public enum MediaKey: String, Codable, Sendable {
    case playPause, volumeUp, volumeDown, next, previous, mute, brightnessUp, brightnessDown
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
    case toggleKeyboard
    /// A gesture was recognised (assigned or not). Only the Practice window listens.
    case recognized(GestureID)
}

/// What the HUD should show. Cheap to compute every frame.
public struct HUDState: Equatable, Sendable {
    public enum PointerState: String, Sendable {
        case engaged, pressing, dragging, rightPressing, lost
    }

    public enum Warning: String, Sendable {
        case tooFar, lowLight, lowFPS, nearEdge
    }

    /// Which gesture family the hands in view are ready for, in command mode.
    /// The HUD fills in what each one does from the user's assignments.
    public enum Cue: String, Sendable {
        case vee            // ✌️ ready to flick
        case open           // ✋ ready to swipe
        case ok             // 👌 held
        case okSlideVertical, okSlideSideways
        case fist           // ✊ held, ready to slide
        case fistSliding
        case point          // ☝️: hold for pointer mode
        case curtains       // 🖐🖐 held together: part them
        case frame          // two "L" hands: hold
        case clap           // first clap heard: clap again
        case handsUp        // both hands raised and still: hold to rest / wake
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
