import AppKit
import CoreGraphics

/// The Sleight mark: a faint ring (the camera's field of view, the stage), a
/// single pen stroke sweeping around it, and the gold point where the motion
/// lands: the moment a gesture becomes an action.
public enum Brand {
    public static let ivory = CGColor(srgbRed: 0.97, green: 0.95, blue: 0.90, alpha: 1)
    public static let gold = CGColor(srgbRed: 1.0, green: 0.78, blue: 0.40, alpha: 1)
    public static let inkTop = CGColor(srgbRed: 0.11, green: 0.11, blue: 0.16, alpha: 1)
    public static let ink = CGColor(srgbRed: 0.03, green: 0.03, blue: 0.05, alpha: 1)

    // Geometry in a 1024 canvas, y up.
    static let center = CGPoint(x: 512, y: 512)
    static let radius: CGFloat = 250
    static let sweepStart: CGFloat = -.pi * 0.35
    static let sweepEnd: CGFloat = .pi * 0.62
    static let strokeMax: CGFloat = 30

    /// Where the stroke lands.
    public static var landing: CGPoint { point(at: sweepEnd) }

    static func point(at angle: CGFloat) -> CGPoint {
        CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
    }

    /// Points along the sweep (for animating it).
    public static func sweepPoints(count: Int = 120) -> [CGPoint] {
        (0..<count).map { point(at: sweepStart + (sweepEnd - sweepStart) * CGFloat($0) / CGFloat(count - 1)) }
    }

    /// Draws the mark into `rect` (y-up space). `progress` < 1 draws part of the
    /// sweep (for the intro). `monochrome` draws one colour (template images).
    public static func drawMark(in ctx: CGContext, rect: CGRect, progress: CGFloat = 1,
                                monochrome: CGColor? = nil, glow: Bool = true, weight: CGFloat = 1) {
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.minY)
        ctx.scaleBy(x: rect.width / 1024, y: rect.height / 1024)

        // The ring.
        ctx.setStrokeColor((monochrome ?? ivory).copy(alpha: monochrome == nil ? 0.16 : 0.45)!)
        ctx.setLineWidth(monochrome == nil ? 4 : 4 * weight * 3)
        ctx.strokeEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))

        // The sweep: swells in the middle like a pen stroke, fades in from its tail.
        let steps = 900
        let last = Int(CGFloat(steps) * min(max(progress, 0), 1))
        for i in 0...max(last, 1) {
            let t = CGFloat(i) / CGFloat(steps)
            let a = sweepStart + (sweepEnd - sweepStart) * t
            let w = (3 + strokeMax * sin(.pi * min(t * 1.05, 1)) * (1 - 0.15 * t)) * weight
            let fade = min(1, t * 2)
            let alpha = monochrome == nil ? 0.35 + 0.65 * fade * fade * (3 - 2 * fade) : 0.6 + 0.4 * fade
            ctx.setFillColor((monochrome ?? ivory).copy(alpha: alpha)!)
            let p = point(at: a)
            ctx.fillEllipse(in: CGRect(x: p.x - w / 2, y: p.y - w / 2, width: w, height: w))
        }

        // The landing point.
        let head = point(at: sweepStart + (sweepEnd - sweepStart) * min(max(progress, 0), 1))
        let r: CGFloat = 30 * (monochrome == nil ? 1 : weight * 1.3)
        if glow, monochrome == nil { ctx.setShadow(offset: .zero, blur: 44, color: gold.copy(alpha: 0.75)) }
        ctx.setFillColor(monochrome ?? gold)
        ctx.fillEllipse(in: CGRect(x: head.x - r, y: head.y - r, width: r * 2, height: r * 2))
        ctx.restoreGState()
    }

    /// Full app icon on the macOS icon grid (824 pt body in a 1024 canvas).
    public static func drawAppIcon(in ctx: CGContext, size: CGFloat) {
        let s = size / 1024
        ctx.saveGState()
        ctx.scaleBy(x: s, y: s)
        let body = CGRect(x: 100, y: 100, width: 824, height: 824)
        let shape = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: CGColor(gray: 0, alpha: 0.4))
        ctx.addPath(shape)
        ctx.setFillColor(ink)
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(shape)
        ctx.clip()
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let bg = CGGradient(colorsSpace: space, colors: [inkTop, ink] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.addPath(CGPath(roundedRect: body.insetBy(dx: 1.5, dy: 1.5), cornerWidth: 184, cornerHeight: 184, transform: nil))
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.07))
        ctx.setLineWidth(3)
        ctx.strokePath()
        drawMark(in: ctx, rect: CGRect(x: 0, y: 0, width: 1024, height: 1024))
        ctx.restoreGState()
        ctx.restoreGState()
    }

    public static func appIconImage(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            drawAppIcon(in: ctx, size: size)
            return true
        }
    }

    /// Template image for the menu bar. Resting = hollow point, just the ring and stroke.
    public static func menuBarImage(active: Bool = true, pointer: Bool = false) -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let rect = CGRect(x: -4.6, y: -4.6, width: 27.2, height: 27.2)
            if active {
                drawMark(in: ctx, rect: rect, monochrome: .black, glow: false, weight: pointer ? 2.4 : 2.0)
            } else {
                // Resting: the ring alone, dimmed.
                ctx.saveGState()
                ctx.translateBy(x: rect.minX, y: rect.minY)
                ctx.scaleBy(x: rect.width / 1024, y: rect.height / 1024)
                ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.55))
                ctx.setLineWidth(40)
                ctx.strokeEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
                ctx.restoreGState()
            }
            return true
        }
        img.isTemplate = true
        return img
    }

    public static func iconPNG(pixels: Int) -> Data? {
        render(pixels: NSSize(width: pixels, height: pixels)) { ctx in drawAppIcon(in: ctx, size: CGFloat(pixels)) }
    }

    public static func png(of image: NSImage, pixels: NSSize) -> Data? {
        render(pixels: pixels) { _ in image.draw(in: NSRect(origin: .zero, size: pixels)) }
    }

    private static func render(pixels: NSSize, _ draw: (CGContext) -> Void) -> Data? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(pixels.width), pixelsHigh: Int(pixels.height),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let gc = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = gc
        draw(gc.cgContext)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}
