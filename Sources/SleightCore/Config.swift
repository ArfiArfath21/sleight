import Foundation

public enum MappingMode: String, Codable, Sendable, CaseIterable {
    /// Hand motion moves the cursor like a trackpad, with acceleration.
    case relative
    /// A box in the camera view maps straight onto the screen.
    case absolute
}

/// Every tunable number in one place. Units:
/// - "hs" = hand scales (wrist to middle knuckle, about 9 cm on an adult hand).
///   Using hand scales makes everything independent of distance to the camera.
/// - "frame" = fraction of the camera frame height.
/// - "pt" = screen points.
public struct SleightConfig: Codable, Equatable, Sendable {
    // MARK: Tracking
    public var minJointConfidence: Float = 0.3
    /// Mean confidence over all 21 joints (missing = 0). Rejects the "ghost
    /// hands" Vision reports in dark or cluttered scenes.
    public var minHandConfidence: Double = 0.4
    /// Hands smaller than this (frame heights) are people in the background.
    public var minHandScale: Double = 0.06
    /// A jump bigger than this (hs) in one frame is a glitch or another hand.
    public var teleportDistance: Double = 2.5
    /// Short dropouts are bridged; the hand keeps its identity.
    public var lostGrace: Double = 0.25
    /// A new shape must persist this many frames before it counts.
    public var shapeFrames: Int = 2

    // MARK: Smoothing (One Euro filter on the palm anchor, in thousandths of frame height)
    public var filterMinCutoff: Double = 2.0
    public var filterBeta: Double = 0.012
    public var filterDerivativeCutoff: Double = 1.0

    // MARK: Fingers
    public var fingerExtendedAbove: Double = 1.6
    public var fingerCurledBelow: Double = 1.3

    // MARK: Pinch
    public var pinchClose: Double = 0.25
    public var pinchOpen: Double = 0.38
    public var pinchReleaseFrames: Int = 2
    public var pinchMinIndexExtension: Double = 1.15

    // MARK: Command mode: intent
    /// A hand must be in view this long before its motion can trigger anything:
    /// a hand swinging into the frame is never a swipe.
    public var settleTime: Double = 0.15
    /// Gestures only start above this line (fraction of frame height): hands
    /// resting on the keyboard at the bottom of the frame are ignored.
    public var activeBelowLine: Double = 0.9
    /// Real keyboard/trackpad use pauses gestures for this long.
    public var realInputCooldown: Double = 1.0

    // MARK: Command mode: swipes (open palm)
    public var swipesEnabled: Bool = true
    public var swipeDownEnabled: Bool = false
    public var swipeMinSpeed: Double = 4.0
    public var swipeMinDistance: Double = 0.9
    public var swipeWindow: Double = 0.2
    public var swipeAxisDominance: Double = 1.6

    // MARK: Command mode: two-finger flicks (scroll, back/forward)
    public var flickMinSpeed: Double = 2.6
    public var flickMinDistance: Double = 0.5
    public var flickWindow: Double = 0.18
    /// Scroll velocity (pt/s) per unit of flick speed (hs/s).
    public var scrollFlickGain: Double = 420
    public var scrollFlickMin: Double = 900
    public var scrollFlickMax: Double = 5000
    /// true: flicking up moves content up (like the trackpad's natural scrolling).
    public var scrollNatural: Bool = true
    public var backForwardEnabled: Bool = true
    /// After a flick, the same direction can fire again after this long...
    public var flickRepeatGap: Double = 0.22
    /// ...and the opposite direction (the return stroke) after this long.
    public var flickReturnGap: Double = 0.6

    // MARK: Command mode: pinch = media remote
    /// Pinch released within this time without sliding = play/pause.
    public var pinchTapMax: Double = 0.45
    /// Slide this far (hs) to choose: vertical = volume, sideways = next/previous track.
    public var pinchAxisLock: Double = 0.3
    public var volumeStep: Double = 0.2
    public var trackSkipEnabled: Bool = true

    // MARK: Command mode: fist = grab the app switcher
    public var grabEnabled: Bool = true
    /// Slide this far (hs) with a fist before the switcher opens.
    public var grabLock: Double = 0.35
    public var appStep: Double = 0.45

    // MARK: Command mode: point to enter pointer mode
    public var pointHoldTime: Double = 0.45
    public var pointMaxSpeed: Double = 1.0

    // MARK: Two hands
    /// Double clap toggles active / resting.
    public var clapEnabled: Bool = true
    /// Hands must close faster than this (hs/s) for a clap...
    public var clapApproachSpeed: Double = 5.0
    /// ...and meet (palms closer than this, hs) or merge into one detection.
    public var clapContactDistance: Double = 1.4
    /// Second clap must follow the first within this window.
    public var doubleClapMin: Double = 0.12
    public var doubleClapMax: Double = 0.9
    /// Part the curtains: open hands held together, then swept apart.
    public var curtainsEnabled: Bool = true
    public var curtainsTogether: Double = 2.6
    public var curtainsHold: Double = 0.25
    public var curtainsSpread: Double = 2.2
    /// Frame: both hands in an "L", held this long.
    public var frameEnabled: Bool = true
    public var frameHold: Double = 0.5
    public var thumbOutAbove: Double = 0.62

    // MARK: Pointer mode
    public var mappingMode: MappingMode = .relative
    public var slowGain: Double = 200
    public var fastGain: Double = 1600
    public var accelLowSpeed: Double = 0.5
    public var accelHighSpeed: Double = 4.0
    public var precisionSpeed: Double = 0.35
    public var precisionFactor: Double = 0.4
    public var precisionAttack: Double = 0.12
    public var absoluteInset: Double = 0.18
    public var edgeGlideMargin: Double = 0.06
    public var edgeGlideSpeed: Double = 900
    public var dragDeadzone: Double = 9
    public var pinchRollbackMax: Double = 0.15
    public var doubleClickInterval: Double = 0.42
    public var doubleClickRadius: Double = 12
    public var rightClickEnabled: Bool = true
    /// Hold a fist this long to leave pointer mode.
    public var exitHoldTime: Double = 0.35
    /// Tracking gone this long = back to command mode.
    public var lostExit: Double = 1.5
    public var flipExitEnabled: Bool = true
    public var flipExitTime: Double = 0.35
    /// Palm anchor below this line = hand dropped to rest.
    public var restLine: Double = 0.96
    public var restTime: Double = 0.18

    // MARK: Output
    public var glideEnabled: Bool = true
    public var glideLead: Double = 0.5
    public var momentumDecay: Double = 0.4

    public init() {}

    public static let `default` = SleightConfig()
}

extension SleightConfig {
    /// Decodes leniently: keys missing from an older config file keep their defaults.
    public static func decode(from data: Data) throws -> SleightConfig {
        let base = try JSONSerialization.jsonObject(with: JSONEncoder().encode(SleightConfig()))
        guard var merged = base as? [String: Any],
              let saved = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return SleightConfig()
        }
        for (k, v) in saved where merged[k] != nil { merged[k] = v }
        let mergedData = try JSONSerialization.data(withJSONObject: merged)
        return try JSONDecoder().decode(SleightConfig.self, from: mergedData)
    }
}
