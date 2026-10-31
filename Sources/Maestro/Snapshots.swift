import AppKit
import SwiftUI
import MaestroCore
import MaestroBrand

/// `--snapshots DIR`: renders every UI surface to PNG without a camera, for
/// visual review and the README.
@MainActor
enum Snapshots {
    static func render(to dir: URL, injector: EventInjector, monitor: InputMonitor, store: ConfigStore) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // HUD states, side by side on a wallpaper-like backdrop.
        let states: [(String, HUDState)] = {
            func s(_ m: HUDState.Mode, _ f: (inout HUDState) -> Void = { _ in }) -> HUDState {
                var h = HUDState(); h.mode = m; f(&h); return h
            }
            return [
                ("watching", s(.watching)),
                ("arming", s(.arming) { $0.armProgress = 0.62 }),
                ("engaged", s(.engaged)),
                ("pinching", s(.engaged) { $0.pinchProgress = 0.7 }),
                ("precision", s(.engaged) { $0.precision = 1 }),
                ("pressing", s(.pressing)),
                ("dragging", s(.dragging)),
                ("scrolling", s(.scrolling)),
                ("keyboard ✌︎", s(.engaged) { $0.keyboardProgress = 0.55 }),
                ("lost", s(.lost)),
                ("hint", s(.engaged) { $0.hint = .lowLight }),
            ]
        }()
        let cell = NSSize(width: 170, height: 150)
        let sheet = NSImage(size: NSSize(width: cell.width * CGFloat(states.count), height: cell.height), flipped: false) { rect in
            let ctx = NSGraphicsContext.current!.cgContext
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            let g = CGGradient(colorsSpace: space, colors: [CGColor(srgbRed: 0.30, green: 0.42, blue: 0.62, alpha: 1),
                                                            CGColor(srgbRed: 0.85, green: 0.62, blue: 0.55, alpha: 1)] as CFArray,
                               locations: [0, 1])!
            ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: rect.width, y: rect.height), options: [])
            for (i, (name, hud)) in states.enumerated() {
                let view = HaloView(frame: NSRect(origin: .zero, size: cell))
                // Settle the smoothed radius/alpha.
                for _ in 0..<40 { view.update(hud: hud, at: NSPoint(x: cell.width / 2, y: cell.height / 2 + 12), stats: nil) }
                ctx.saveGState()
                ctx.translateBy(x: CGFloat(i) * cell.width, y: 0)
                view.layer?.render(in: ctx)
                (name as NSString).draw(at: NSPoint(x: 12, y: 10), withAttributes: [
                    .font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.white,
                ])
                ctx.restoreGState()
            }
            return true
        }
        write(sheet, to: dir.appendingPathComponent("hud-states.png"), scale: 2)

        // Keyboard on a dark glass stand-in (vibrancy does not render offscreen).
        let kb = KeyboardView(injector: injector, monitor: monitor)
        kb.frame = NSRect(origin: .zero, size: kb.intrinsicContentSize)
        let kbImage = NSImage(size: kb.frame.size, flipped: true) { rect in
            NSColor(srgbRed: 0.13, green: 0.13, blue: 0.16, alpha: 1).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 22, yRadius: 22).fill()
            kb.draw(rect)
            return true
        }
        write(kbImage, to: dir.appendingPathComponent("keyboard.png"), scale: 2)

        renderSwiftUI(GuideView(), to: dir.appendingPathComponent("guide.png"))

        if let png = Brand.iconPNG(pixels: 1024) { try? png.write(to: dir.appendingPathComponent("logo.png")) }
    }

    @MainActor
    private static func renderSwiftUI<V: View>(_ view: V, to url: URL) {
        let r = ImageRenderer(content: view
            .background(Color(red: 0.12, green: 0.12, blue: 0.14))
            .environment(\.colorScheme, .dark))
        r.scale = 2
        if let img = r.nsImage, let tiff = img.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: url)
        }
    }

    private static func write(_ image: NSImage, to url: URL, scale: CGFloat) {
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        if let data = Brand.png(of: image, pixels: size) { try? data.write(to: url) }
    }
}
