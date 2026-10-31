import AppKit
import CoreGraphics

/// The Sleight mark: an "S" drawn as one flick of a fingertip. The stroke
/// grows from a faint tail into a bright head, the way a fast motion looks,
/// and fades through the holographic palette (magenta → indigo → cyan). Faint
/// concentric rings sit behind it like a HUD.
public enum Brand {
    public static let cyan = CGColor(srgbRed: 0.24, green: 0.92, blue: 1.0, alpha: 1)
    public static let indigo = CGColor(srgbRed: 0.38, green: 0.45, blue: 1.0, alpha: 1)
    public static let magenta = CGColor(srgbRed: 0.86, green: 0.36, blue: 1.0, alpha: 1)
    public static let night = CGColor(srgbRed: 0.07, green: 0.08, blue: 0.13, alpha: 1)
    public static let deep = CGColor(srgbRed: 0.015, green: 0.02, blue: 0.04, alpha: 1)

    /// Colour along the stroke, t = 0 at the tail, 1 at the head.
    public static func gradient(_ t: CGFloat) -> CGColor {
        func mix(_ a: CGColor, _ b: CGColor, _ t: CGFloat) -> CGColor {
            let x = a.components!, y = b.components!
            return CGColor(srgbRed: x[0] + (y[0] - x[0]) * t, green: x[1] + (y[1] - x[1]) * t,
                           blue: x[2] + (y[2] - x[2]) * t, alpha: 1)
        }
        let t = min(max(t, 0), 1)
        return t < 0.5 ? mix(magenta, indigo, t * 2) : mix(indigo, cyan, (t - 0.5) * 2)
    }

    /// The S, as cubic segments in a 1024 canvas (y up), tail → head.
    static let segments: [(CGPoint, CGPoint, CGPoint, CGPoint)] = [
        (CGPoint(x: 330, y: 300), CGPoint(x: 560, y: 230), CGPoint(x: 720, y: 330), CGPoint(x: 640, y: 470)),
        (CGPoint(x: 640, y: 470), CGPoint(x: 580, y: 570), CGPoint(x: 370, y: 520), CGPoint(x: 380, y: 640)),
        (CGPoint(x: 380, y: 640), CGPoint(x: 390, y: 760), CGPoint(x: 600, y: 780), CGPoint(x: 700, y: 712)),
    ]

    static let tailWidth: CGFloat = 6
    static let headWidth: CGFloat = 74

    /// Evenly spaced points along the S.
    public static func pathPoints(spacing: CGFloat = 1.2) -> [CGPoint] {
        var dense: [CGPoint] = []
        for s in segments {
            for i in 0...300 {
                let t = CGFloat(i) / 300, u = 1 - t
                dense.append(CGPoint(x: u * u * u * s.0.x + 3 * u * u * t * s.1.x + 3 * u * t * t * s.2.x + t * t * t * s.3.x,
                                     y: u * u * u * s.0.y + 3 * u * u * t * s.1.y + 3 * u * t * t * s.2.y + t * t * t * s.3.y))
            }
        }
        var out = [dense[0]]
        var acc: CGFloat = 0
        for i in 1..<dense.count {
            acc += hypot(dense[i].x - dense[i - 1].x, dense[i].y - dense[i - 1].y)
            if acc >= spacing { out.append(dense[i]); acc = 0 }
        }
        return out
    }

    /// Draws the comet S into `rect` (y-up space). `progress` < 1 draws only the
    /// first part of the stroke (used to animate the mark drawing itself).
    /// `monochrome` draws in one colour with the same alpha falloff (template images).
    public static func drawMark(in ctx: CGContext, rect: CGRect, progress: CGFloat = 1,
                                monochrome: CGColor? = nil, glow: Bool = true, widthScale: CGFloat = 1) {
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.minY)
        ctx.scaleBy(x: rect.width / 1024, y: rect.height / 1024)
        let spacing = max(1.2, 1024 / max(rect.width, 1) * 0.6)
        let pts = pathPoints(spacing: spacing)
        let count = max(Int(CGFloat(pts.count) * min(max(progress, 0), 1)), 2)
        for i in 0..<count {
            let t = CGFloat(i) / CGFloat(pts.count - 1)
            let w = (tailWidth + (headWidth - tailWidth) * pow(t, 1.3)) * widthScale
            // Template glyphs are tiny: keep the tail visible.
            let floor: CGFloat = monochrome == nil ? 0.15 : 0.5
            let a = floor + (1 - floor) * pow(t, 0.7)
            let color = (monochrome ?? gradient(t)).copy(alpha: a)!
            ctx.setFillColor(color)
            let p = pts[i]
            ctx.fillEllipse(in: CGRect(x: p.x - w / 2, y: p.y - w / 2, width: w, height: w))
        }
        // The fingertip: a white-hot point at the head.
        let head = pts[count - 1]
        let t = CGFloat(count - 1) / CGFloat(pts.count - 1)
        let r = (tailWidth + (headWidth - tailWidth) * pow(t, 1.3)) * widthScale * 0.5
        if glow { ctx.setShadow(offset: .zero, blur: 64, color: cyan.copy(alpha: 0.95)) }
        ctx.setFillColor(monochrome ?? CGColor(gray: 1, alpha: 1))
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
        ctx.setFillColor(deep)
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(shape)
        ctx.clip()
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let bg = CGGradient(colorsSpace: space, colors: [night, deep] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(bg, start: CGPoint(x: 300, y: 924), end: CGPoint(x: 724, y: 100),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        let glowColor = CGColor(srgbRed: 0.3, green: 0.4, blue: 1, alpha: 0.35)
        let g = CGGradient(colorsSpace: space, colors: [glowColor, glowColor.copy(alpha: 0)!] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: 512, y: 512), startRadius: 0,
                               endCenter: CGPoint(x: 512, y: 512), endRadius: 420, options: [])
        for (r, a) in [(170.0, 0.10), (260.0, 0.07), (350.0, 0.05)] as [(CGFloat, CGFloat)] {
            ctx.setStrokeColor(CGColor(srgbRed: 0.6, green: 0.8, blue: 1, alpha: a))
            ctx.setLineWidth(2)
            ctx.strokeEllipse(in: CGRect(x: 512 - r, y: 512 - r, width: r * 2, height: r * 2))
        }
        ctx.addPath(CGPath(roundedRect: body.insetBy(dx: 1.5, dy: 1.5), cornerWidth: 184, cornerHeight: 184, transform: nil))
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.08))
        ctx.setLineWidth(3)
        ctx.strokePath()
        drawMark(in: ctx, rect: CGRect(x: -14, y: 0, width: 1024, height: 1024))
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

    /// Template image for the menu bar. `active` thickens it while a hand is tracked.
    public static func menuBarImage(active: Bool = false) -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            // The S spans about x 300…760, y 250…800 of the canvas.
            drawMark(in: ctx, rect: CGRect(x: -5.5, y: -5.8, width: 28, height: 28),
                     monochrome: .black, glow: false, widthScale: active ? 1.5 : 1.25)
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
