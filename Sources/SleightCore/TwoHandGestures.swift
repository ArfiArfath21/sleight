import Foundation

/// Gestures made with both hands. They are for big, rare actions, so each one
/// is shaped to be hard to do by accident:
///
/// - 👏👏 **double clap**: two fast meetings of the hands within ~0.9 s. Hands
///   occlude each other on contact and the tracker often loses one, so a clap is
///   "hands rushing together, then touching *or merging*". A single clap does
///   nothing (rubbing or folding hands looks similar); two in a row are deliberate.
/// - 🖐🖐 **part the curtains**: open hands held together for a moment, then
///   swept apart sideways → show desktop. The hold keeps the separation after a
///   clap from counting.
/// - 🤞🤞 **frame**: both hands in an "L" (index up, thumb out) held still →
///   screenshot.
public final class TwoHandGestures {
    public var config: SleightConfig

    public enum Event: Equatable, Sendable {
        case clap, doubleClap, curtains, frame
    }

    public struct Result {
        public var events: [Event] = []
        /// True while a two-hand gesture is forming: one-hand gestures stand down.
        public var busy = false
        public var cue: HUDState.Cue?
        public var progress: Double = 0
    }

    private var prevDistance: Double?
    private var prevTime: Double?
    private var lastPairDistance: Double?
    private var approachAt: Double?
    private var contactLatched = false
    private var lastClap: Double?
    private var togetherSince: Double?
    private var togetherDistance: Double = 0
    private var frameSince: Double?
    private var quietUntil = -Double.infinity

    public init(config: SleightConfig = .default) { self.config = config }

    public func reset() {
        prevDistance = nil
        approachAt = nil
        contactLatched = false
        togetherSince = nil
        frameSince = nil
    }

    public func step(tracks: HandTracks, time t: Double) -> Result {
        var r = Result()
        let pair = Array(tracks.visible.sorted { $0.scale > $1.scale }.prefix(2))

        if pair.count == 2 {
            let a = pair[0], b = pair[1]
            let scale = (a.scale + b.scale) / 2
            let d = distance(a.anchor, b.anchor) / scale
            lastPairDistance = d

            detectClap(distance: d, time: t, result: &r)
            if t >= quietUntil {
                detectCurtains(a, b, distance: d, time: t, result: &r)
                detectFrame(a, b, time: t, result: &r)
            }
            prevDistance = d
            prevTime = t
        } else {
            // The pair just became one (or none): hands that were rushing
            // together and are now a single blob were a clap.
            if let at = approachAt, t - at < 0.2, let last = lastPairDistance, last < 2.8, !contactLatched {
                registerClap(t, result: &r)
            }
            approachAt = nil
            prevDistance = nil
            contactLatched = false
            togetherSince = nil
            frameSince = nil
        }

        if let c = lastClap, t - c < config.doubleClapMax, r.events.isEmpty || r.events == [.clap] {
            r.cue = .clap
            r.busy = true
        }
        return r
    }

    // MARK: Clap

    private func detectClap(distance d: Double, time t: Double, result r: inout Result) {
        guard config.clapEnabled else { return }
        if contactLatched {
            // Wait for the hands to separate before another clap can count.
            if d > config.clapContactDistance + 0.6 { contactLatched = false }
            return
        }
        if let pd = prevDistance, let pt = prevTime, t - pt < 0.12 {
            let closing = (pd - d) / max(t - pt, 1e-3)
            if closing > config.clapApproachSpeed { approachAt = t }
        }
        if let at = approachAt, t - at < 0.25, d < config.clapContactDistance {
            registerClap(t, result: &r)
            contactLatched = true
        }
    }

    private func registerClap(_ t: Double, result r: inout Result) {
        approachAt = nil
        togetherSince = nil
        // Parting after a clap must never read as curtains.
        quietUntil = t + 1.0
        if let c = lastClap, t - c >= config.doubleClapMin, t - c <= config.doubleClapMax {
            r.events.append(.doubleClap)
            lastClap = nil
        } else {
            r.events.append(.clap)
            lastClap = t
        }
    }

    // MARK: Curtains

    private func detectCurtains(_ a: TrackedHand, _ b: TrackedHand, distance d: Double, time t: Double,
                                result r: inout Result) {
        guard config.curtainsEnabled else { return }
        let bothOpen = a.shape(heldFor: config.settleTime, at: t) == .open
            && b.shape(heldFor: config.settleTime, at: t) == .open
        if bothOpen, d < config.curtainsTogether, a.speed < 1.5, b.speed < 1.5 {
            if togetherSince == nil { togetherSince = t; togetherDistance = d }
            togetherDistance = min(togetherDistance, d)
            let held = t - togetherSince!
            if held >= config.curtainsHold {
                r.cue = .curtains
                r.busy = true
            }
            return
        }
        guard let since = togetherSince else { return }
        let armed = t - since >= config.curtainsHold
        // Parting: distance grows, mostly sideways, hands moving in opposite directions.
        let dx = abs(a.anchor.x - b.anchor.x), dy = abs(a.anchor.y - b.anchor.y)
        let left = a.anchor.x < b.anchor.x ? a : b, right = left === a ? b : a
        let opposite = left.deltaHS.x <= 0.02 && right.deltaHS.x >= -0.02
        if armed, d - togetherDistance >= config.curtainsSpread, dx > 2 * dy, opposite {
            r.events.append(.curtains)
            togetherSince = nil
            quietUntil = t + 1.0
        } else if !armed || t - since > 1.6 || d > config.curtainsTogether + config.curtainsSpread + 2 {
            togetherSince = nil
        } else {
            r.busy = true
            r.cue = .curtains
        }
    }

    // MARK: Frame

    private func detectFrame(_ a: TrackedHand, _ b: TrackedHand, time t: Double, result r: inout Result) {
        guard config.frameEnabled else { return }
        let framing = a.pose.isFrameL(config: config) && b.pose.isFrameL(config: config)
            && a.speed < 1.2 && b.speed < 1.2
        guard framing else { frameSince = nil; return }
        let since = frameSince ?? t
        frameSince = since
        r.busy = true
        r.cue = .frame
        r.progress = clamp((t - since) / config.frameHold, 0, 1)
        if t - since >= config.frameHold {
            r.events.append(.frame)
            frameSince = nil
            quietUntil = t + 2.0
        }
    }
}
