import Foundation

/// A fixed-duration ring of timestamped samples. Used to rewind the cursor to
/// where it was just before a gesture started (pinch, fist, swipe, dropping the
/// hand), which removes the cursor drift those motions cause.
public struct TimedHistory<Value: Sendable>: Sendable {
    public private(set) var samples: [(time: Double, value: Value)] = []
    public var span: Double

    public init(span: Double) { self.span = span }

    public mutating func append(_ value: Value, at time: Double) {
        samples.append((time, value))
        let cutoff = time - span
        if let firstKeep = samples.firstIndex(where: { $0.time >= cutoff }), firstKeep > 0 {
            samples.removeFirst(firstKeep)
        }
    }

    public mutating func removeAll() { samples.removeAll() }

    /// The latest sample at or before `time`, or the oldest sample if `time` is
    /// before the window.
    public func value(atOrBefore time: Double) -> Value? {
        guard !samples.isEmpty else { return nil }
        var result = samples[0].value
        for s in samples {
            if s.time <= time { result = s.value } else { break }
        }
        return result
    }

    public var last: (time: Double, value: Value)? { samples.last }
    public var isEmpty: Bool { samples.isEmpty }

    public func since(_ time: Double) -> ArraySlice<(time: Double, value: Value)> {
        let idx = samples.firstIndex(where: { $0.time >= time }) ?? samples.count
        return samples[idx...]
    }
}
