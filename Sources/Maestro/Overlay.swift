import AppKit
import QuartzCore
import MaestroCore
import MaestroBrand

/// Transparent, click-through windows (one per display) that draw the cursor
/// halo, gesture feedback and toasts. Redrawn on the display's refresh, reading
/// the latest shared state, so feedback is never behind the cursor.
final class Overlay {
    private var windows: [OverlayWindow] = []
    private let shared: SharedState
    private var displayLink: CADisplayLink?
    var showStats = false
    var enabled = true { didSet { if !enabled { windows.forEach { $0.halo.hideAll() } } } }

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

    func toast(_ text: String) {
        let main = windows.first { $0.screen == NSScreen.main } ?? windows.first
        main?.halo.showToast(text)
    }

    @objc private func frame() {
        guard enabled else { return }
        let hud = shared.hud
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        // Engaged: follow the cursor we are driving. Otherwise follow the real one.
        let engagedModes: Set<HUDState.Mode> = [.engaged, .pressing, .dragging, .rightPressing, .scrolling, .lost]
        let cg: Vec2 = engagedModes.contains(hud.mode) ? (shared.outputCursor ?? hud.cursor) : EventInjector.currentCursor()
        let global = NSPoint(x: cg.x, y: primaryHeight - cg.y)
        let q = showStats ? shared.quality : nil
        for w in windows {
            let local = NSPoint(x: global.x - w.frame.minX, y: global.y - w.frame.minY)
            let onThis = w.frame.contains(global)
            w.halo.update(hud: onThis ? hud : nil, at: local, stats: w.screen == NSScreen.main ? q : nil)
        }
    }
}

final class OverlayWindow: NSWindow {
    let halo: HaloView

    init(screen: NSScreen) {
        halo = HaloView(frame: NSRect(origin: .zero, size: screen.frame.size))
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false
        contentView = halo
        setFrame(screen.frame, display: false)
    }
}

final class HaloView: NSView {
    private let ring = CAShapeLayer()
    private let fill = CAShapeLayer()
    private let arc = CAShapeLayer()
    private let chevrons = CAShapeLayer()
    private let hintLayer = CATextLayer()
    private let toastLayer = CALayer()
    private let toastText = CATextLayer()
    private let statsLayer = CATextLayer()

    private var radius: CGFloat = 15
    private var ringAlpha: CGFloat = 0
    private var fillAlpha: CGFloat = 0
    private var lastStatsText = ""

    private let white = NSColor(white: 1, alpha: 1).cgColor
    private let gold = Brand.gold
    private let violet = Brand.violet

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        let root = layer!
        let scale = NSScreen.main?.backingScaleFactor ?? 2

        for l in [fill, ring, arc, chevrons] {
            l.fillColor = nil
            l.contentsScale = scale
            l.actions = ["position": NSNull(), "path": NSNull(), "opacity": NSNull(), "strokeEnd": NSNull(),
                         "strokeColor": NSNull(), "fillColor": NSNull(), "lineDashPattern": NSNull()]
            root.addSublayer(l)
        }
        ring.lineWidth = 2
        ring.strokeColor = white
        ring.shadowColor = NSColor.black.cgColor
        ring.shadowOpacity = 0.45
        ring.shadowRadius = 3
        ring.shadowOffset = .zero
        fill.fillColor = gold
        arc.strokeColor = gold
        arc.lineWidth = 3
        arc.lineCap = .round
        chevrons.strokeColor = white
        chevrons.lineWidth = 2
        chevrons.lineCap = .round
        chevrons.lineJoin = .round

        hintLayer.fontSize = 11
        hintLayer.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        hintLayer.foregroundColor = white
        hintLayer.backgroundColor = NSColor(white: 0.08, alpha: 0.78).cgColor
        hintLayer.cornerRadius = 8
        hintLayer.alignmentMode = .center
        hintLayer.contentsScale = scale
        hintLayer.actions = ["position": NSNull(), "contents": NSNull(), "bounds": NSNull()]
        hintLayer.opacity = 0
        root.addSublayer(hintLayer)

        toastLayer.backgroundColor = NSColor(white: 0.07, alpha: 0.82).cgColor
        toastLayer.cornerRadius = 22
        toastLayer.borderColor = NSColor(white: 1, alpha: 0.12).cgColor
        toastLayer.borderWidth = 1
        toastLayer.opacity = 0
        toastText.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        toastText.fontSize = 15
        toastText.foregroundColor = white
        toastText.alignmentMode = .center
        toastText.contentsScale = scale
        toastLayer.addSublayer(toastText)
        root.addSublayer(toastLayer)

        statsLayer.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        statsLayer.fontSize = 11
        statsLayer.foregroundColor = NSColor(white: 1, alpha: 0.92).cgColor
        statsLayer.backgroundColor = NSColor(white: 0.07, alpha: 0.75).cgColor
        statsLayer.cornerRadius = 9
        statsLayer.alignmentMode = .center
        statsLayer.contentsScale = scale
        statsLayer.opacity = 0
        root.addSublayer(statsLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    func hideAll() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for l in [ring, fill, arc, chevrons, hintLayer, statsLayer] { l.opacity = 0 }
        CATransaction.commit()
    }

    func update(hud: HUDState?, at p: NSPoint, stats: QualitySnapshot?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        updateStats(stats)

        guard let hud, hud.mode != .off else {
            ringAlpha *= 0.7
            fillAlpha *= 0.7
            applyRing(at: p, dashed: false, color: white)
            arc.opacity = 0; chevrons.opacity = 0; hintLayer.opacity = 0
            return
        }

        var targetRadius: CGFloat = 15
        var targetAlpha: CGFloat = 0.95
        var targetFill: CGFloat = 0
        var color = white
        var dashed = false
        var arcProgress: CGFloat = 0
        var arcColor = gold

        switch hud.mode {
        case .off: targetAlpha = 0
        case .watching:
            targetRadius = 10; targetAlpha = 0.22
        case .arming:
            targetRadius = 15; targetAlpha = 0.55
            arcProgress = CGFloat(hud.armProgress)
        case .engaged:
            let precise = CGFloat(hud.precision)
            let pinch = CGFloat(hud.pinchProgress)
            targetRadius = (15 - 6 * precise) * (1 - 0.35 * pinch)
            targetFill = 0.55 * pinch * pinch
            if precise > 0.5 { color = violet }
        case .pressing:
            targetRadius = 8; targetFill = 0.9
        case .dragging:
            targetRadius = 11; targetFill = 0.6
        case .rightPressing:
            targetRadius = 9; color = violet; targetFill = 0.0
            arcProgress = 1; arcColor = violet
        case .scrolling:
            targetRadius = 13
        case .lost:
            targetAlpha = 0.4; dashed = true
        }
        if hud.keyboardProgress > 0 {
            arcProgress = CGFloat(hud.keyboardProgress); arcColor = violet
        }

        // Critically damped-ish smoothing: fast but never jumpy.
        radius += (targetRadius - radius) * 0.45
        ringAlpha += (targetAlpha - ringAlpha) * 0.4
        fillAlpha += (targetFill - fillAlpha) * 0.5
        applyRing(at: p, dashed: dashed, color: color)

        if arcProgress > 0.01 {
            arc.opacity = 1
            arc.strokeColor = arcColor
            let r: CGFloat = 21
            let path = CGMutablePath()
            path.addArc(center: p, radius: r, startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi * min(arcProgress, 1), clockwise: true)
            arc.path = path
        } else {
            arc.opacity = 0
        }

        if hud.mode == .scrolling {
            chevrons.opacity = 1
            let path = CGMutablePath()
            let s: CGFloat = 4
            path.move(to: CGPoint(x: p.x - s, y: p.y + 19)); path.addLine(to: CGPoint(x: p.x, y: p.y + 19 + s)); path.addLine(to: CGPoint(x: p.x + s, y: p.y + 19))
            path.move(to: CGPoint(x: p.x - s, y: p.y - 19)); path.addLine(to: CGPoint(x: p.x, y: p.y - 19 - s)); path.addLine(to: CGPoint(x: p.x + s, y: p.y - 19))
            chevrons.path = path
        } else {
            chevrons.opacity = 0
        }

        if let hint = hud.hint, hud.mode != .off {
            let text: String
            switch hint {
            case .nearEdge: text = "Edge of camera view"
            case .tooFar: text = "Move closer"
            case .lowLight: text = "Low light: tracking may suffer"
            case .lowFPS: text = "Camera is slow: add light"
            case .paused: text = "Paused"
            }
            if (hintLayer.string as? String) != text {
                hintLayer.string = text
                let w = (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold)]).width + 18
                hintLayer.bounds = CGRect(x: 0, y: 0, width: w, height: 20)
            }
            hintLayer.position = CGPoint(x: p.x, y: p.y - 38)
            hintLayer.opacity = 1
        } else {
            hintLayer.opacity = 0
        }
    }

    private func applyRing(at p: NSPoint, dashed: Bool, color: CGColor) {
        let r = max(radius, 2)
        ring.path = CGPath(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2), transform: nil)
        ring.opacity = Float(max(ringAlpha, 0))
        ring.strokeColor = color
        ring.lineDashPattern = dashed ? [3, 4] : nil
        let fr = r - 1.5
        fill.path = CGPath(ellipseIn: CGRect(x: p.x - fr, y: p.y - fr, width: fr * 2, height: fr * 2), transform: nil)
        fill.opacity = Float(max(fillAlpha * ringAlpha, 0))
    }

    private func updateStats(_ q: QualitySnapshot?) {
        guard let q else { statsLayer.opacity = 0; return }
        let light = q.luma < 40 ? "dark" : (q.luma < 70 ? "dim" : "ok")
        let text = String(format: "%.0f fps · %.0f ms vision · %.0f ms pipeline · light %@", q.fps, q.visionMs, q.latencyMs, light)
        if text != lastStatsText {
            lastStatsText = text
            statsLayer.string = text
            let w = (text as NSString).size(withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)]).width + 22
            statsLayer.bounds = CGRect(x: 0, y: 0, width: w, height: 22)
            statsLayer.position = CGPoint(x: bounds.width - w / 2 - 16, y: bounds.height - 50)
        }
        statsLayer.opacity = 1
    }

    func showToast(_ text: String) {
        let font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        let w = (text as NSString).size(withAttributes: [.font: font]).width + 44
        CATransaction.begin(); CATransaction.setDisableActions(true)
        toastLayer.bounds = CGRect(x: 0, y: 0, width: w, height: 44)
        toastLayer.position = CGPoint(x: bounds.midX, y: 120)
        toastText.string = text
        toastText.frame = CGRect(x: 0, y: 12, width: w, height: 22)
        CATransaction.commit()

        toastLayer.removeAllAnimations()
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 1, 1, 0]
        fade.keyTimes = [0, 0.12, 0.75, 1]
        fade.duration = 1.1
        let rise = CABasicAnimation(keyPath: "transform.scale")
        rise.fromValue = 0.92; rise.toValue = 1
        rise.duration = 0.18
        rise.timingFunction = CAMediaTimingFunction(name: .easeOut)
        toastLayer.add(fade, forKey: "fade")
        toastLayer.add(rise, forKey: "rise")
    }
}
