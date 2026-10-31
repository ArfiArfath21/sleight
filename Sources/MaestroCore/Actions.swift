import Foundation

public enum MouseButton: String, Codable, Sendable { case left, right }

public enum ScrollPhase: String, Codable, Sendable { case began, changed, ended }

public enum SwipeDirection: String, Codable, Sendable { case left, right, up }

public enum DisengageReason: String, Codable, Sendable {
    case lost, rested, flipped, userInput, manual
}

/// What the engine wants the OS to do. Positions are global CG coordinates.
public enum EngineAction: Equatable, Sendable {
    /// Smoothly move the cursor (output may glide toward it).
    case move(to: Vec2)
    /// Put the cursor here right now (used to rewind gesture drift).
    case warp(to: Vec2)
    case mouseDown(MouseButton, at: Vec2, clickCount: Int)
    case mouseUp(MouseButton, at: Vec2, clickCount: Int)
    case scroll(delta: Vec2, phase: ScrollPhase)
    /// Let go of a scroll with this velocity (pt/s): output runs momentum.
    case scrollMomentum(velocity: Vec2)
    /// Stop any running momentum (hand grabbed again, or engaged a pinch).
    case stopMomentum
    case swipe(SwipeDirection)
    case toggleKeyboard
    case engaged
    case disengaged(DisengageReason)
}

/// What the on-screen HUD should show. Cheap to compute every frame.
public struct HUDState: Equatable, Sendable {
    public enum Mode: String, Sendable {
        case off          // no hand, not engaged
        case watching     // hand visible, not engaged
        case arming       // open palm held, filling up
        case engaged
        case pressing     // left button held, not yet dragging
        case dragging
        case rightPressing
        case scrolling
        case lost         // engaged but tracking dropped
    }

    public enum Hint: String, Sendable {
        case nearEdge, tooFar, lowLight, lowFPS, paused
    }

    public var mode: Mode = .off
    public var cursor: Vec2 = .zero
    /// 0…1 while arming.
    public var armProgress: Double = 0
    /// 0 = fingers apart, 1 = pinch closed. Lets the ring contract *before* the
    /// click so you can see a click coming.
    public var pinchProgress: Double = 0
    /// 0…1, how deep into precision mode the pointer is.
    public var precision: Double = 0
    /// 0…1 while the keyboard peace sign is held.
    public var keyboardProgress: Double = 0
    public var hint: Hint?

    public init() {}
}

public struct EngineOutput: Sendable {
    public var actions: [EngineAction]
    public var hud: HUDState
    /// The pose that drove this frame, for preview/debugging.
    public var pose: HandPose?
}
