import Foundation

public typealias Vec2 = SIMD2<Double>

extension SIMD2 where Scalar == Double {
    @inlinable public var length: Double { (x * x + y * y).squareRoot() }

    @inlinable public var normalized: Vec2 {
        let l = length
        return l > 1e-12 ? self / l : .zero
    }
}

@inlinable public func distance(_ a: Vec2, _ b: Vec2) -> Double { (a - b).length }

/// 2D cross product (z component). Sign tells winding of a -> b.
@inlinable public func cross(_ a: Vec2, _ b: Vec2) -> Double { a.x * b.y - a.y * b.x }

@inlinable public func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

@inlinable public func lerp(_ a: Vec2, _ b: Vec2, _ t: Double) -> Vec2 { a + (b - a) * t }

@inlinable public func clamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double { min(max(x, lo), hi) }

@inlinable public func smoothstep(_ e0: Double, _ e1: Double, _ x: Double) -> Double {
    let t = clamp((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)
}

/// Axis-aligned rectangle in global screen coordinates (CoreGraphics: origin top-left, y down).
public struct ScreenRect: Codable, Equatable, Sendable {
    public var x: Double, y: Double, width: Double, height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }

    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }

    public func contains(_ p: Vec2) -> Bool { p.x >= minX && p.x < maxX && p.y >= minY && p.y < maxY }

    public func clamped(_ p: Vec2) -> Vec2 {
        Vec2(clamp(p.x, minX, maxX - 1), clamp(p.y, minY, maxY - 1))
    }
}

/// The set of displays the cursor may live on. Clamping keeps the cursor on the
/// nearest display so it can never get lost in the gaps of an L-shaped layout.
public struct ScreenLayout: Codable, Equatable, Sendable {
    public var screens: [ScreenRect]

    public init(screens: [ScreenRect]) { self.screens = screens }

    public static let fallback = ScreenLayout(screens: [ScreenRect(x: 0, y: 0, width: 1512, height: 982)])

    public func clamp(_ p: Vec2) -> Vec2 {
        guard !screens.isEmpty else { return p }
        if screens.contains(where: { $0.contains(p) }) { return p }
        var best = p
        var bestDist = Double.infinity
        for s in screens {
            let c = s.clamped(p)
            let d = distance(c, p)
            if d < bestDist { bestDist = d; best = c }
        }
        return best
    }

    public var bounds: ScreenRect {
        guard let first = screens.first else { return ScreenLayout.fallback.screens[0] }
        var minX = first.minX, minY = first.minY, maxX = first.maxX, maxY = first.maxY
        for s in screens {
            minX = min(minX, s.minX); minY = min(minY, s.minY)
            maxX = max(maxX, s.maxX); maxY = max(maxY, s.maxY)
        }
        return ScreenRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// The display containing `p`, or the nearest one.
    public func screen(containing p: Vec2) -> ScreenRect {
        if let s = screens.first(where: { $0.contains(p) }) { return s }
        let c = clamp(p)
        return screens.first(where: { $0.contains(c) }) ?? bounds
    }
}
