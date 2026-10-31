import Foundation

public enum MappingMode: String, Codable, Sendable, CaseIterable {
    /// Hand motion moves the cursor like a trackpad, with acceleration. Default:
    /// it hides landmark jitter and lets you "clutch" by re-engaging.
    case relative
    /// A box in the camera view maps straight onto the screen.
    case absolute
}

/// Every tunable number in one place. Units:
/// - "hs" = hand scales (wrist to middle knuckle, about 9 cm on an adult hand).
///   Using hand scales makes everything independent of how far you sit from the camera.
/// - "frame" = fraction of the camera frame height.
/// - "pt" = screen points.
public struct MaestroConfig: Codable, Equatable, Sendable {
    // MARK: Tracking
    public var minJointConfidence: Float = 0.3
    /// Which hand to follow when several are visible. `.unknown` = whichever is biggest.
    public var preferredHand: Chirality = .right
    /// Hands smaller than this (in frame heights) are ignored: people in the background.
    public var minHandScale: Double = 0.06
    /// A jump bigger than this (in hs) between frames is treated as a glitch or a
    /// different hand, not as motion.
    public var teleportDistance: Double = 2.5

    // MARK: Smoothing (One Euro filter on the palm anchor, in thousandths of frame height)
    public var filterMinCutoff: Double = 2.0
    public var filterBeta: Double = 0.012
    public var filterDerivativeCutoff: Double = 1.0

    // MARK: Pointer
    public var mappingMode: MappingMode = .relative
    /// Points per hand scale when moving slowly.
    public var slowGain: Double = 200
    /// Points per hand scale when moving fast.
    public var fastGain: Double = 1600
    /// Speeds (hs/s) between which gain ramps from slow to fast.
    public var accelLowSpeed: Double = 0.5
    public var accelHighSpeed: Double = 4.0
    /// Below this speed (hs/s) the pointer eases into precision mode.
    public var precisionSpeed: Double = 0.35
    /// Gain multiplier at full precision.
    public var precisionFactor: Double = 0.4
    /// How quickly precision mode fades in (seconds time constant).
    public var precisionAttack: Double = 0.12
    /// Absolute mode: the part of the camera frame that maps to the screen.
    public var absoluteInset: Double = 0.18
    /// When the hand is this close to the frame edge (fraction of frame), the
    /// cursor keeps gliding in that direction so you never run out of camera.
    public var edgeGlideMargin: Double = 0.06
    public var edgeGlideSpeed: Double = 900

    // MARK: Engagement (resting vs acting)
    /// Hold an open palm still this long to engage.
    public var armTime: Double = 0.30
    /// Max speed (hs/s) while arming: a hand passing through never engages.
    public var armMaxSpeed: Double = 1.2
    /// Short tracking dropouts shorter than this are bridged seamlessly.
    public var lostGrace: Double = 0.25
    /// Tracking gone this long = disengage.
    public var lostDisengage: Double = 1.2
    /// Turning the back of the hand to the camera for this long disengages.
    public var flipDisengageTime: Double = 0.35
    public var flipDisengageEnabled: Bool = true
    /// Palm anchor below this line (fraction of frame height) = hand is dropping to rest.
    public var restLine: Double = 0.96
    public var restTime: Double = 0.18
    /// Real keyboard/trackpad use pauses gestures for this long.
    public var realInputCooldown: Double = 1.0

    // MARK: Pinch / click
    /// Thumb-index distance (hs) below which a pinch closes.
    public var pinchClose: Double = 0.25
    /// Distance (hs) above which it opens again. The gap is the hysteresis.
    public var pinchOpen: Double = 0.38
    /// Frames the pinch must read "open" before release (debounces flicker).
    public var pinchReleaseFrames: Int = 2
    /// While pinched, the cursor stays put until the hand moves this far (pt). Kills
    /// the "click lands a few pixels off" problem and separates click from drag.
    public var dragDeadzone: Double = 9
    /// When a pinch closes, rewind the cursor to where it was when the fingers
    /// started closing, up to this long ago (s).
    public var pinchRollbackMax: Double = 0.15
    public var doubleClickInterval: Double = 0.42
    public var doubleClickRadius: Double = 12
    public var rightClickEnabled: Bool = true
    /// Index extension ratio required for a pinch (a fist is not a pinch).
    public var pinchMinIndexExtension: Double = 1.15

    // MARK: Finger extension (tip-to-wrist / knuckle-to-wrist ratio)
    public var fingerExtendedAbove: Double = 1.6
    public var fingerCurledBelow: Double = 1.3

    // MARK: Scroll (make a fist and move it)
    public var scrollEnabled: Bool = true
    /// Points of scroll per hand scale of motion.
    public var scrollGain: Double = 1300
    /// true: moving the fist up moves content up, like grabbing a sheet of paper.
    public var scrollNatural: Bool = true
    public var scrollEnterFrames: Int = 2
    public var scrollExitFrames: Int = 2
    /// Momentum after letting go: velocity decay time constant (s).
    public var momentumDecay: Double = 0.33
    /// Minimum release speed (pt/s) that starts momentum.
    public var momentumMinSpeed: Double = 250

    // MARK: Swipes (fast open-palm flick)
    public var swipesEnabled: Bool = true
    public var swipeUpEnabled: Bool = true
    /// Average speed (hs/s) over the window.
    public var swipeMinSpeed: Double = 7.0
    /// Distance covered (hs).
    public var swipeMinDistance: Double = 1.3
    public var swipeWindow: Double = 0.16
    /// Primary axis must dominate the other by this factor.
    public var swipeAxisDominance: Double = 2.0
    public var swipeCooldown: Double = 0.7

    // MARK: Keyboard toggle (hold a peace sign)
    public var keyboardGestureEnabled: Bool = true
    public var keyboardHoldTime: Double = 0.6

    // MARK: Output
    /// At 30 fps the cursor would step visibly on a 120 Hz display. The output
    /// stage jumps part of the way at once (no added latency) and glides the rest.
    public var glideEnabled: Bool = true
    /// Fraction of each step applied immediately.
    public var glideLead: Double = 0.5

    public init() {}

    public static let `default` = MaestroConfig()
}

extension MaestroConfig {
    /// Decodes leniently: keys missing from an older config file keep their defaults.
    public static func decode(from data: Data) throws -> MaestroConfig {
        let base = try JSONSerialization.jsonObject(with: JSONEncoder().encode(MaestroConfig()))
        guard var merged = base as? [String: Any],
              let saved = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return MaestroConfig()
        }
        for (k, v) in saved where merged[k] != nil { merged[k] = v }
        let mergedData = try JSONSerialization.data(withJSONObject: merged)
        return try JSONDecoder().decode(MaestroConfig.self, from: mergedData)
    }
}
