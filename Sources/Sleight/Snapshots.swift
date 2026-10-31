import AppKit
import SwiftUI
import SleightCore
import SleightBrand

/// `--snapshots DIR`: renders the UI to PNGs without a camera, for review and the README.
@MainActor
enum Snapshots {
    static func render(to dir: URL, injector: EventInjector, monitor: InputMonitor) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let scale: CGFloat = 2

        // Gesture chips: hints, confirmations, pointer mode.
        let chips: [Chip] = [
            .cue(.scroll, progress: 0), .cue(.swipe, progress: 0), .cue(.grab, progress: 0),
            .cue(.media, progress: 0), .cue(.point, progress: 0.6), .cue(.frame, progress: 0.4),
            .cue(.curtains, progress: 0), .cue(.clap, progress: 0), Chip.resting, .pointer(progress: 0),
            Chip.flash(for: .shortcut(.spaceLeft))!, Chip.flash(for: .media(.playPause))!,
            Chip.flash(for: .activeChanged(true))!,
        ]
        let images = chips.compactMap { ChipRenderer.render($0, scale: scale) }
        let width = (images.map { CGFloat($0.width) / scale }.max() ?? 300) + 80
        let rowH: CGFloat = 62
        let sheet = NSImage(size: NSSize(width: width, height: rowH * CGFloat(images.count) + 30), flipped: true) { rect in
            let ctx = NSGraphicsContext.current!.cgContext
            let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                               colors: [CGColor(srgbRed: 0.20, green: 0.30, blue: 0.48, alpha: 1),
                                        CGColor(srgbRed: 0.62, green: 0.44, blue: 0.52, alpha: 1)] as CFArray, locations: [0, 1])!
            ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: rect.width, y: rect.height), options: [])
            for (i, img) in images.enumerated() {
                let w = CGFloat(img.width) / scale, h = CGFloat(img.height) / scale
                let r = CGRect(x: (rect.width - w) / 2, y: 15 + CGFloat(i) * rowH + (rowH - h) / 2, width: w, height: h)
                NSImage(cgImage: img, size: r.size).draw(in: r)
            }
            return true
        }
        write(sheet, to: dir.appendingPathComponent("chips.png"), scale: scale)

        // Keyboard on a dark stand-in for the vibrancy (which does not render offscreen).
        let kb = KeyboardView(injector: injector, monitor: monitor)
        kb.frame = NSRect(origin: .zero, size: kb.intrinsicContentSize)
        let kbImage = NSImage(size: kb.frame.size, flipped: true) { rect in
            NSColor(srgbRed: 0.11, green: 0.12, blue: 0.16, alpha: 1).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 22, yRadius: 22).fill()
            kb.draw(rect)
            return true
        }
        write(kbImage, to: dir.appendingPathComponent("keyboard.png"), scale: scale)

        let r = ImageRenderer(content: GuideView()
            .background(Color(red: 0.07, green: 0.08, blue: 0.11))
            .environment(\.colorScheme, .dark))
        r.scale = scale
        if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: dir.appendingPathComponent("guide.png"))
        }

        if let png = Brand.iconPNG(pixels: 1024) { try? png.write(to: dir.appendingPathComponent("logo.png")) }

        // The wordmark: mark + name, for the README header.
        let word = NSImage(size: NSSize(width: 720, height: 220), flipped: false) { rect in
            let ctx = NSGraphicsContext.current!.cgContext
            ctx.setFillColor(Brand.ink)
            ctx.fill(rect)
            Brand.drawMark(in: ctx, rect: CGRect(x: -20, y: -10, width: 240, height: 240))
            let font = NSFont.systemFont(ofSize: 84, weight: .light)
            ("Sleight" as NSString).draw(at: NSPoint(x: 236, y: 58),
                                         withAttributes: [.font: font, .foregroundColor: NSColor(cgColor: Brand.ivory)!, .kern: 3])
            return true
        }
        write(word, to: dir.appendingPathComponent("wordmark.png"), scale: scale)
    }

    private static func write(_ image: NSImage, to url: URL, scale: CGFloat) {
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        if let data = Brand.png(of: image, pixels: size) { try? data.write(to: url) }
    }
}
