import AppKit
import QuartzCore
import SleightCore
import SleightBrand

/// Click-through windows (one per display) that draw:
/// - the gesture chip (top centre): what your hand is about to do, and a flash
///   when something fires, so you never have to guess
/// - the cursor ring in pointer mode
/// - the brand intro when Sleight turns on
/// Driven by the display refresh, reading the latest shared state.
final class Overlay {
    private var windows: [OverlayWindow] = []
    private let shared: SharedState
    private var displayLink: CADisplayLink?
    var showStats = false
    var showHints = true
    var gestures = GestureMap()
    var enabled = true { didSet { if !enabled { windows.forEach { $0.view.hideAll() } } } }
    private var flash: (chip: Chip, until: Double)?

    init(shared: SharedState) {
        self.shared = shared
        rebuild()
        NotificationCenter.default.addObserver(self, selector: #selector(rebuild),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    @objc func rebuild() {
        windows.forEach { $0.orderOut(nil) }
        windows = NSScreen.screens.map { OverlayWindow(screen: $0) }
        windows.forEach { $0.orderFrontRegardless() }
        displayLink?.invalidate()
        if let view = windows.first?.contentView {
            let link = view.displayLink(target: self, selector: #selector(frame))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
    }

    private var activeWindow: OverlayWindow? {
        let mouse = NSEvent.mouseLocation
        return windows.first { $0.frame.contains(mouse) } ?? windows.first
    }

    /// Brief confirmation in the chip.
    func flash(_ chip: Chip, seconds: Double = 0.9) {
        flash = (chip, CACurrentMediaTime() + seconds)
    }

    func playIntro() { activeWindow?.view.playIntro() }

    @objc private func frame() {
        guard enabled else { return }
        let hud = shared.hud
        let now = CACurrentMediaTime()
        if let f = flash, now > f.until { flash = nil }

        var chip: Chip?
        if let f = flash {
            chip = f.chip
        } else if !hud.active {
            // Resting: say so only while a hand is up (or the wake gesture is forming).
            if let cue = hud.cue, cue == .clap || cue == .handsUp {
                chip = Chip.cue(cue, progress: hud.progress, active: false, map: gestures)
            }
            else if hud.handsVisible > 0, showHints { chip = Chip.resting }
        } else if hud.mode == .pointer {
            chip = Chip.pointer(progress: hud.progress)
        } else if showHints, let cue = hud.cue {
            chip = Chip.cue(cue, progress: hud.progress, map: gestures)
        }
        if chip == nil, let w = hud.warning, hud.handsVisible > 0 || hud.mode == .pointer {
            chip = Chip.warning(w)
        }

        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let cg = shared.outputCursor ?? hud.cursor
        let global = NSPoint(x: cg.x, y: primaryHeight - cg.y)
        let q = showStats ? shared.quality : nil
        let active = activeWindow
        for w in windows {
            let local = NSPoint(x: global.x - w.frame.minX, y: global.y - w.frame.minY)
            let ringHere = hud.mode == .pointer && w.frame.contains(global)
            w.view.update(ring: ringHere ? hud : nil, at: local,
                          chip: w === active ? chip : nil, flashing: flash != nil,
                          stats: w === active ? q : nil)
        }
    }
}

/// Content of the gesture chip.
struct Chip: Equatable {
    var symbol: String
    var title: String
    var detail: String?
    var progress: Double = 0
    var accent = false

    /// Hint for what the hands in view are ready for, listing what the user
    /// assigned. nil when nothing in that family is assigned.
    static func cue(_ cue: HUDState.Cue, progress: Double, active: Bool = true, map: GestureMap = GestureMap()) -> Chip? {
        func list(_ items: [(String, GestureID)]) -> String? {
            let parts = items.filter { map.isAssigned($0.1) }.map { "\($0.0) \(map[$0.1].title.lowercased())" }
            return parts.isEmpty ? nil : parts.joined(separator: "   ")
        }
        switch cue {
        case .handsUp:
            return Chip(symbol: "hand.raised", title: active ? "Hold to rest" : "Hold to wake", detail: nil, progress: progress)
        case .vee:
            guard let d = list([("↑", .veeFlickUp), ("↓", .veeFlickDown), ("←", .veeFlickLeft), ("→", .veeFlickRight)]) else { return nil }
            return Chip(symbol: "arrow.up.and.down", title: "Flick", detail: d)
        case .open:
            guard let d = list([("←", .openSwipeLeft), ("→", .openSwipeRight), ("↑", .openSwipeUp), ("↓", .openSwipeDown)]) else { return nil }
            return Chip(symbol: "hand.raised", title: "Swipe", detail: d)
        case .ok:
            let d = [map.isAssigned(.okTap) ? "let go  \(map[.okTap].title.lowercased())" : nil,
                     map.isAssigned(.okSlideVertical) ? "↕ \(map[.okSlideVertical].title.lowercased())" : nil,
                     map.isAssigned(.okSlideSideways) ? "↔ \(map[.okSlideSideways].title.lowercased())" : nil]
                .compactMap { $0 }.joined(separator: "   ")
            return Chip(symbol: "hand.pinch", title: "OK", detail: d.isEmpty ? nil : d)
        case .okSlideVertical:
            let a = map[.okSlideVertical]
            return Chip(symbol: GestureCatalog.symbol(a), title: a.title, detail: "slide up or down")
        case .okSlideSideways:
            let a = map[.okSlideSideways]
            return Chip(symbol: GestureCatalog.symbol(a), title: a.title, detail: "slide left or right")
        case .fist:
            let a = map[.fistSlideSideways]
            return Chip(symbol: "hand.raised.fingers.spread", title: "Grab", detail: "slide sideways: \(a.title.lowercased())")
        case .fistSliding:
            let a = map[.fistSlideSideways]
            return Chip(symbol: GestureCatalog.symbol(a), title: a.title, detail: "slide to step · open hand to finish")
        case .point:
            return Chip(symbol: "cursorarrow.rays", title: "Hold to point", detail: nil, progress: progress)
        case .curtains:
            return Chip(symbol: "rectangle.portrait.split.2x1", title: "Part the curtains",
                        detail: "sweep apart: \(map[.curtains].title.lowercased())")
        case .frame:
            return Chip(symbol: "camera.viewfinder", title: "Hold the frame", detail: map[.frame].title.lowercased(), progress: progress)
        case .clap:
            return Chip(symbol: "hands.clap", title: "Clap again", detail: map[.doubleClap].title.lowercased())
        }
    }

    static let resting = Chip(symbol: "moon", title: "Sleight is resting", detail: "raise both hands and hold to wake")

    static func pointer(progress: Double) -> Chip {
        Chip(symbol: "cursorarrow", title: "Pointer",
             detail: progress > 0.05 ? "keep the fist to exit" : "pinch click   ✌ flick scroll   ✊ hold to exit",
             progress: progress)
    }

    static func warning(_ w: HUDState.Warning) -> Chip {
        switch w {
        case .tooFar: return Chip(symbol: "arrow.up.left.and.arrow.down.right", title: "Move closer", detail: nil)
        case .lowLight: return Chip(symbol: "sun.min", title: "Low light", detail: "tracking may suffer")
        case .lowFPS: return Chip(symbol: "tortoise", title: "Camera is slow", detail: "add light")
        case .nearEdge: return Chip(symbol: "viewfinder", title: "Edge of camera view", detail: nil)
        }
    }

    /// Confirmation for something that just happened, or nil.
    static func flash(for action: EngineAction, map: GestureMap = GestureMap()) -> Chip? {
        func c(_ s: String, _ t: String) -> Chip { Chip(symbol: s, title: t, detail: nil, accent: true) }
        switch action {
        case .recognized(let g):
            let a = map[g]
            // Screenshots must not show the chip; rest/wake has its own confirmation.
            guard a != .none, a != .restWake, a != .screenshot, a != .screenshotSelection, a != .screenshotTool else { return nil }
            return c(GestureCatalog.symbol(a), a.title)
        case .switcher(.commit): return c("checkmark", "Switched")
        case .switcher(.cancel): return c("xmark", "Cancelled")
        case .modeChanged(let m, let reason):
            if reason == .resting { return nil }
            return m == .pointer ? c("cursorarrow", "Pointer mode") : c("hand.raised", "Gestures")
        case .activeChanged(let on):
            return on ? c("sparkle", "Sleight is listening")
                : Chip(symbol: "moon", title: "Resting", detail: "both hands up to wake", accent: true)
        default:
            return nil
        }
    }
}

final class OverlayWindow: NSWindow {
    let view: OverlayView

    init(screen: NSScreen) {
        view = OverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        // Keep the HUD out of screenshots (the frame gesture) and screen sharing.
        sharingType = .none
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false
        contentView = view
        setFrame(screen.frame, display: false)
    }
}

final class OverlayView: NSView {
    // Pointer ring.
    private let ring = CAShapeLayer()
    private let fill = CAShapeLayer()
    private var radius: CGFloat = 15
    private var ringAlpha: CGFloat = 0
    private var fillAlpha: CGFloat = 0
    // Chip.
    private let chipLayer = CALayer()
    private var chipShown: Chip?
    private var chipAlpha: Float = 0
    // Stats.
    private let statsLayer = CATextLayer()
    private var lastStats = ""

    private let scale = NSScreen.main?.backingScaleFactor ?? 2

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        let root = layer!
        for l in [fill, ring] {
            l.fillColor = nil
            l.contentsScale = scale
            l.actions = ["position": NSNull(), "path": NSNull(), "opacity": NSNull(),
                         "strokeColor": NSNull(), "fillColor": NSNull(), "lineDashPattern": NSNull()]
            root.addSublayer(l)
        }
        ring.lineWidth = 2
        ring.strokeColor = NSColor.white.cgColor
        ring.shadowColor = Brand.gold
        ring.shadowOpacity = 0.6
        ring.shadowRadius = 4
        ring.shadowOffset = .zero
        fill.fillColor = Brand.gold

        chipLayer.contentsScale = scale
        chipLayer.contentsGravity = .center
        chipLayer.opacity = 0
        chipLayer.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull(), "opacity": NSNull()]
        chipLayer.shadowColor = NSColor.black.cgColor
        chipLayer.shadowOpacity = 0.35
        chipLayer.shadowRadius = 18
        chipLayer.shadowOffset = CGSize(width: 0, height: -4)
        root.addSublayer(chipLayer)

        statsLayer.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        statsLayer.fontSize = 11
        statsLayer.foregroundColor = NSColor(white: 1, alpha: 0.9).cgColor
        statsLayer.backgroundColor = NSColor(white: 0.05, alpha: 0.75).cgColor
        statsLayer.cornerRadius = 9
        statsLayer.alignmentMode = .center
        statsLayer.contentsScale = scale
        statsLayer.opacity = 0
        root.addSublayer(statsLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    func hideAll() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for l in [ring, fill, chipLayer, statsLayer] { l.opacity = 0 }
        chipAlpha = 0
        CATransaction.commit()
    }

    func update(ring hud: HUDState?, at p: NSPoint, chip: Chip?, flashing: Bool, stats: QualitySnapshot?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updateRing(hud, at: p)
        updateChip(chip, flashing: flashing)
        updateStats(stats)
        CATransaction.commit()
    }

    // MARK: Ring

    private func updateRing(_ hud: HUDState?, at p: NSPoint) {
        var targetRadius: CGFloat = 15, targetAlpha: CGFloat = 0, targetFill: CGFloat = 0
        var dashed = false
        if let hud {
            targetAlpha = 0.95
            switch hud.pointer {
            case .engaged:
                let precise = CGFloat(hud.precision), pinch = CGFloat(hud.pinchProgress)
                targetRadius = (15 - 6 * precise) * (1 - 0.35 * pinch)
                targetFill = 0.5 * pinch * pinch
            case .pressing: targetRadius = 8; targetFill = 0.9
            case .dragging: targetRadius = 11; targetFill = 0.6
            case .rightPressing: targetRadius = 9; targetFill = 0.35
            case .lost: targetAlpha = 0.4; dashed = true
            }
            if hud.progress > 0 { targetRadius *= CGFloat(1 - 0.4 * hud.progress) }
        }
        radius += (targetRadius - radius) * 0.45
        ringAlpha += (targetAlpha - ringAlpha) * 0.4
        fillAlpha += (targetFill - fillAlpha) * 0.5
        let r = max(radius, 2)
        ring.path = CGPath(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2), transform: nil)
        ring.opacity = Float(max(ringAlpha, 0))
        ring.lineDashPattern = dashed ? [3, 4] : nil
        let fr = r - 1.5
        fill.path = CGPath(ellipseIn: CGRect(x: p.x - fr, y: p.y - fr, width: fr * 2, height: fr * 2), transform: nil)
        fill.opacity = Float(max(fillAlpha * ringAlpha, 0))
    }

    // MARK: Chip

    private func updateChip(_ chip: Chip?, flashing: Bool) {
        let target: Float = chip == nil ? 0 : 1
        chipAlpha += (target - chipAlpha) * (target > chipAlpha ? 0.45 : 0.18)
        chipLayer.opacity = chipAlpha
        guard var chip else { return }
        // Re-render only when something visible changed.
        chip.progress = (chip.progress * 20).rounded() / 20
        if chip != chipShown, let img = ChipRenderer.render(chip, scale: scale) {
            chipShown = chip
            chipLayer.contents = img
            let size = CGSize(width: CGFloat(img.width) / scale, height: CGFloat(img.height) / scale)
            chipLayer.bounds = CGRect(origin: .zero, size: size)
            chipLayer.position = CGPoint(x: bounds.midX, y: bounds.height - 74)
            if flashing, chip.accent {
                let pop = CABasicAnimation(keyPath: "transform.scale")
                pop.fromValue = 0.9
                pop.toValue = 1
                pop.duration = 0.22
                pop.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 1.4, 0.4, 1)
                chipLayer.add(pop, forKey: "pop")
            }
        }
    }

    private func updateStats(_ q: QualitySnapshot?) {
        guard let q else { statsLayer.opacity = 0; return }
        let light = q.luma < 40 ? "dark" : (q.luma < 70 ? "dim" : "ok")
        let text = String(format: "%.0f fps · %.0f ms vision · %.0f ms pipeline · light %@", q.fps, q.visionMs, q.latencyMs, light)
        if text != lastStats {
            lastStats = text
            statsLayer.string = text
            let w = (text as NSString).size(withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)]).width + 22
            statsLayer.bounds = CGRect(x: 0, y: 0, width: w, height: 22)
            statsLayer.position = CGPoint(x: bounds.width - w / 2 - 16, y: bounds.height - 50)
        }
        statsLayer.opacity = 1
    }

    // MARK: Intro

    /// The ring fades in, a stroke sweeps around it and lands on the gold point.
    func playIntro() {
        let size: CGFloat = 200
        let container = CALayer()
        container.frame = CGRect(x: bounds.midX - size / 2, y: bounds.midY - size / 2, width: size, height: size)
        layer?.addSublayer(container)
        let k = size / 1024

        let ring = CAShapeLayer()
        let r = 250 * k
        ring.path = CGPath(ellipseIn: CGRect(x: size / 2 - r, y: size / 2 - r, width: r * 2, height: r * 2), transform: nil)
        ring.strokeColor = Brand.ivory.copy(alpha: 0.25)
        ring.fillColor = nil
        ring.lineWidth = 1.5
        container.addSublayer(ring)

        let pts = Brand.sweepPoints().map { CGPoint(x: $0.x * k, y: $0.y * k) }
        let path = CGMutablePath()
        path.addLines(between: pts)
        let stroke = CAShapeLayer()
        stroke.path = path
        stroke.strokeColor = Brand.ivory
        stroke.fillColor = nil
        stroke.lineWidth = 5
        stroke.lineCap = .round
        container.addSublayer(stroke)

        let head = CALayer()
        head.bounds = CGRect(x: 0, y: 0, width: 14, height: 14)
        head.cornerRadius = 7
        head.backgroundColor = Brand.gold
        head.shadowColor = Brand.gold
        head.shadowOpacity = 0.9
        head.shadowRadius = 10
        head.shadowOffset = .zero
        head.position = pts.last!
        container.addSublayer(head)

        let duration = 0.7
        let ease = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1)
        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0; fadeIn.toValue = 1; fadeIn.duration = 0.25
        ring.add(fadeIn, forKey: "in")
        let draw = CABasicAnimation(keyPath: "strokeEnd")
        draw.fromValue = 0; draw.toValue = 1; draw.duration = duration; draw.timingFunction = ease
        stroke.add(draw, forKey: "draw")
        let fly = CAKeyframeAnimation(keyPath: "position")
        fly.path = path; fly.duration = duration; fly.calculationMode = .paced; fly.timingFunction = ease
        head.add(fly, forKey: "fly")
        let land = CAKeyframeAnimation(keyPath: "transform.scale")
        land.values = [1, 1.8, 1]; land.keyTimes = [0, 0.4, 1]
        land.beginTime = CACurrentMediaTime() + duration; land.duration = 0.3
        head.add(land, forKey: "land")

        let out = CAAnimationGroup()
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1; fade.toValue = 0
        let shrink = CABasicAnimation(keyPath: "transform.scale")
        shrink.fromValue = 1; shrink.toValue = 0.7
        out.animations = [fade, shrink]
        out.beginTime = CACurrentMediaTime() + 1.25
        out.duration = 0.4
        out.timingFunction = CAMediaTimingFunction(name: .easeIn)
        out.fillMode = .forwards
        out.isRemovedOnCompletion = false
        container.add(out, forKey: "out")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { container.removeFromSuperlayer() }
    }
}

/// Draws chips into images (symbols + text + progress ring + brand accent).
enum ChipRenderer {
    static func render(_ chip: Chip, scale: CGFloat) -> CGImage? {
        let titleFont = NSFont.systemFont(ofSize: 14, weight: .semibold)
        let detailFont = NSFont.systemFont(ofSize: 12, weight: .regular)
        let title = NSAttributedString(string: chip.title, attributes: [.font: titleFont, .foregroundColor: NSColor.white])
        let detail = chip.detail.map {
            NSAttributedString(string: $0, attributes: [.font: detailFont, .foregroundColor: NSColor(white: 1, alpha: 0.62)])
        }
        let iconBox: CGFloat = 30
        let h: CGFloat = 46
        let gap: CGFloat = 10
        let textW = title.size().width + (detail.map { $0.size().width + 12 } ?? 0)
        let w = ceil(14 + iconBox + gap + textW + 18)

        let image = NSImage(size: NSSize(width: w, height: h), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let rect = CGRect(x: 0.5, y: 0.5, width: w - 1, height: h - 1)
            let shape = CGPath(roundedRect: rect, cornerWidth: h / 2, cornerHeight: h / 2, transform: nil)
            ctx.addPath(shape)
            ctx.setFillColor(CGColor(srgbRed: 0.05, green: 0.06, blue: 0.10, alpha: 0.86))
            ctx.fillPath()

            // Border: brand gradient when confirming an action, hairline otherwise.
            ctx.saveGState()
            ctx.addPath(shape)
            ctx.setLineWidth(chip.accent ? 1.6 : 1)
            ctx.replacePathWithStrokedPath()
            ctx.clip()
            if chip.accent {
                let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                   colors: [Brand.gold, Brand.ivory, Brand.gold] as CFArray, locations: [0, 0.5, 1])!
                ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: w, y: 0), options: [])
            } else {
                ctx.setFillColor(CGColor(gray: 1, alpha: 0.14))
                ctx.fill(rect)
            }
            ctx.restoreGState()

            // Icon.
            let iconCenter = CGPoint(x: 14 + iconBox / 2, y: h / 2)
            if chip.progress > 0 {
                ctx.setLineWidth(2.5)
                ctx.setLineCap(.round)
                ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.15))
                ctx.addArc(center: iconCenter, radius: 15, startAngle: 0, endAngle: .pi * 2, clockwise: false)
                ctx.strokePath()
                ctx.setStrokeColor(Brand.gold)
                ctx.addArc(center: iconCenter, radius: 15, startAngle: .pi / 2,
                           endAngle: .pi / 2 - .pi * 2 * CGFloat(min(chip.progress, 1)), clockwise: true)
                ctx.strokePath()
            }
            let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
                .applying(.init(paletteColors: [chip.accent ? NSColor(cgColor: Brand.gold)! : .white]))
            if let sym = NSImage(systemSymbolName: chip.symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
                let s = sym.size
                sym.draw(in: CGRect(x: iconCenter.x - s.width / 2, y: iconCenter.y - s.height / 2, width: s.width, height: s.height))
            }

            var x = 14 + iconBox + gap
            let ty = (h - title.size().height) / 2
            title.draw(at: CGPoint(x: x, y: ty))
            x += title.size().width + 12
            if let detail {
                detail.draw(at: CGPoint(x: x, y: (h - detail.size().height) / 2))
            }
            return true
        }
        var rect = CGRect(x: 0, y: 0, width: w * scale, height: h * scale)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(w * scale), pixelsHigh: Int(h * scale),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        guard let rep, let gc = NSGraphicsContext(bitmapImageRep: rep) else { return image.cgImage(forProposedRect: &rect, context: nil, hints: nil) }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = gc
        image.draw(in: NSRect(x: 0, y: 0, width: w * scale, height: h * scale))
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage
    }
}
