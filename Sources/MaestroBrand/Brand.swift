import AppKit
import CoreGraphics

/// The Maestro mark: one baton stroke drawing an "M". Two arches fall into a
/// sharp centre point, the ictus, where a conductor's beat lands; the gold dot
/// beneath it is the beat point (the pinch, the click).
public enum Brand {
    public static let indigoTop = CGColor(srgbRed: 0.20, green: 0.15, blue: 0.52, alpha: 1)
    public static let indigoBottom = CGColor(srgbRed: 0.05, green: 0.04, blue: 0.15, alpha: 1)
    public static let glow = CGColor(srgbRed: 0.46, green: 0.38, blue: 1.0, alpha: 0.55)
    public static let ink = CGColor(srgbRed: 0.97, green: 0.96, blue: 1.0, alpha: 1)
    public static let gold = CGColor(srgbRed: 1.0, green: 0.78, blue: 0.37, alpha: 1)
    public static let violet = CGColor(srgbRed: 0.55, green: 0.49, blue: 1.0, alpha: 1)

    /// The baton's path in a 1024 canvas (y up): rise, arch, fall to the ictus,
    /// arch again, then sweep down and out to land on the beat.
    static let segments: [(CGPoint, CGPoint, CGPoint, CGPoint)] = [
        (CGPoint(x: 268, y: 330), CGPoint(x: 296, y: 500), CGPoint(x: 340, y: 692), CGPoint(x: 386, y: 700)),
        (CGPoint(x: 386, y: 700), CGPoint(x: 430, y: 708), CGPoint(x: 474, y: 540), CGPoint(x: 500, y: 452)),
        (CGPoint(x: 500, y: 452), CGPoint(x: 524, y: 540), CGPoint(x: 568, y: 708), CGPoint(x: 612, y: 700)),
        (CGPoint(x: 612, y: 700), CGPoint(x: 662, y: 690), CGPoint(x: 676, y: 392), CGPoint(x: 748, y: 334)),
    ]

    /// Where the stroke lands; the gold beat sits here.
    static let dotCenter = CGPoint(x: 772, y: 322)
    static let dotRadius: CGFloat = 40
    static let startWidth: CGFloat = 70
    static let endWidth: CGFloat = 28

    /// Evenly spaced samples along the path with their stroke radius.
    static func samples(spacing: CGFloat = 1.5) -> [(CGPoint, CGFloat)] {
        func at(_ s: (CGPoint, CGPoint, CGPoint, CGPoint), _ t: CGFloat) -> CGPoint {
            let u = 1 - t
            let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
            return CGPoint(x: a * s.0.x + b * s.1.x + c * s.2.x + d * s.3.x,
                           y: a * s.0.y + b * s.1.y + c * s.2.y + d * s.3.y)
        }
        var dense: [CGPoint] = []
        for seg in segments { for i in 0...400 { dense.append(at(seg, CGFloat(i) / 400)) } }
        var lengths: [CGFloat] = [0]
        for i in 1..<dense.count { lengths.append(lengths[i - 1] + hypot(dense[i].x - dense[i - 1].x, dense[i].y - dense[i - 1].y)) }
        let total = lengths.last!
        var out: [(CGPoint, CGFloat)] = []
        var target: CGFloat = 0, j = 0
        while target <= total {
            while j < lengths.count - 1, lengths[j + 1] < target { j += 1 }
            let f = target / total
            // Ease the taper so the stroke stays strong through the M and thins in the sweep.
            let w = startWidth + (endWidth - startWidth) * pow(f, 1.6)
            out.append((dense[j], w / 2))
            target += spacing
        }
        return out
    }

    /// Draws the mark scaled into `rect` (rect in the context's y-up space).
    public static func drawMark(in ctx: CGContext, rect: CGRect, stroke: CGColor, dot: CGColor,
                                widthScale: CGFloat = 1, dotGlow: Bool = false) {
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.minY)
        ctx.scaleBy(x: rect.width / 1024, y: rect.height / 1024)
        // Stamping discs gives round ends and clean corners at any width.
        let path = CGMutablePath()
        let spacing = max(1.5, 1024 / max(rect.width, 1) * 0.5)
        for (p, r) in samples(spacing: spacing) {
            let rr = r * widthScale
            path.addEllipse(in: CGRect(x: p.x - rr, y: p.y - rr, width: rr * 2, height: rr * 2))
        }
        ctx.addPath(path)
        ctx.setFillColor(stroke)
        ctx.fillPath(using: .winding)
        if dotGlow {
            ctx.setShadow(offset: .zero, blur: 56, color: dot.copy(alpha: 0.85))
        }
        let r = dotRadius * (widthScale > 1 ? 1 + (widthScale - 1) * 0.6 : 1)
        ctx.setFillColor(dot)
        ctx.fillEllipse(in: CGRect(x: dotCenter.x - r, y: dotCenter.y - r, width: r * 2, height: r * 2))
        ctx.restoreGState()
    }

    /// Full app icon, following the macOS icon grid (824 pt body in 1024).
    public static func drawAppIcon(in ctx: CGContext, size: CGFloat) {
        let s = size / 1024
        ctx.saveGState()
        ctx.scaleBy(x: s, y: s)

        let body = CGRect(x: 100, y: 100, width: 824, height: 824)
        let shape = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

        // Soft drop shadow under the tile.
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28,
                      color: CGColor(gray: 0, alpha: 0.35))
        ctx.addPath(shape)
        ctx.setFillColor(indigoBottom)
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(shape)
        ctx.clip()
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let bg = CGGradient(colorsSpace: space, colors: [indigoTop, indigoBottom] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(bg, start: CGPoint(x: 280, y: 924), end: CGPoint(x: 744, y: 100),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        // A violet glow behind the arches, like stage light.
        let g = CGGradient(colorsSpace: space, colors: [glow, glow.copy(alpha: 0)!] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: 512, y: 600), startRadius: 0,
                               endCenter: CGPoint(x: 512, y: 600), endRadius: 430, options: [])
        // Hairline highlight on the top edge.
        ctx.addPath(CGPath(roundedRect: body.insetBy(dx: 1.5, dy: 1.5), cornerWidth: 184, cornerHeight: 184, transform: nil))
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.10))
        ctx.setLineWidth(3)
        ctx.strokePath()

        // The mark's bounding box is slightly right-heavy (the landing beat); nudge it to optical centre.
        drawMark(in: ctx, rect: CGRect(x: -8, y: 0, width: 1024, height: 1024), stroke: ink, dot: gold, dotGlow: true)
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

    /// Template image for the menu bar (system tints it).
    public static func menuBarImage(engaged: Bool = false) -> NSImage {
        let img = NSImage(size: NSSize(width: 22, height: 18), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            // The mark spans roughly x 233…812, y 282…740 of the 1024 canvas; frame it tightly.
            let markRect = CGRect(x: -6.1, y: -7.75, width: 33.5, height: 33.5)
            drawMark(in: ctx, rect: markRect, stroke: .black, dot: .black, widthScale: engaged ? 1.25 : 1.1)
            _ = rect
            return true
        }
        img.isTemplate = true
        return img
    }

    /// PNG of the app icon at `pixels` square.
    public static func iconPNG(pixels: Int) -> Data? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let gc = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = gc
        drawAppIcon(in: gc.cgContext, size: CGFloat(pixels))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    /// PNG of an arbitrary image (for checking the menu bar glyph).
    public static func png(of image: NSImage, pixels: NSSize) -> Data? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(pixels.width), pixelsHigh: Int(pixels.height),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let gc = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = gc
        image.draw(in: NSRect(origin: .zero, size: pixels))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}
