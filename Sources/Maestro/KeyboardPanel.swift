import AppKit
import MaestroBrand

/// A floating, non-activating keyboard: clicking (pinching) its keys types into
/// whatever app has focus, without ever taking focus itself. Keys are big
/// (hand-pointing targets, not fingertip targets) and highlight on hover so you
/// can see what a pinch will hit before you make it.
final class KeyboardPanelController {
    private let panel: KeyboardPanel
    private let view: KeyboardView

    init(injector: EventInjector, monitor: InputMonitor) {
        view = KeyboardView(injector: injector, monitor: monitor)
        let size = view.intrinsicContentSize
        panel = KeyboardPanel(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovableByWindowBackground = false

        let glass = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.cornerRadius = 22
        glass.layer?.masksToBounds = true
        glass.layer?.borderWidth = 1
        glass.layer?.borderColor = NSColor(white: 1, alpha: 0.12).cgColor
        view.frame = glass.bounds
        view.autoresizingMask = [.width, .height]
        glass.addSubview(view)
        panel.contentView = glass
        view.onHide = { [weak self] in self?.hide() }
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() { isVisible ? hide() : show() }

    func show() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main!
        let vf = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: vf.midX - size.width / 2, y: vf.minY + 24))
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: { [panel] in panel.orderOut(nil) })
    }
}

final class KeyboardPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class KeyboardView: NSView {
    enum Action: Equatable {
        case text(String)
        case code(CGKeyCode)
        case shift, layer, hide
    }

    struct Key {
        var label: String
        var action: Action
        var width: CGFloat = 1
        var special = false
    }

    private let injector: EventInjector
    private let monitor: InputMonitor
    var onHide: (() -> Void)?

    private let unit: CGFloat = 60
    private let rowHeight: CGFloat = 56
    private let pad: CGFloat = 16
    private let handle: CGFloat = 22

    private var symbols = false
    private var shift = false
    private var capsLock = false
    private var lastShiftTap = Date.distantPast
    private var hovered: Int?
    private var pressed: Int?
    private var repeatTimer: Timer?
    private var dragOrigin: NSPoint?

    init(injector: EventInjector, monitor: InputMonitor) {
        self.injector = injector
        self.monitor = monitor
        super.init(frame: .zero)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: pad * 2 + unit * 11.5, height: pad + handle + rowHeight * 4 + pad - 4)
    }

    private var rows: [[Key]] {
        if symbols {
            return [
                "1234567890".map { Key(label: String($0), action: .text(String($0))) } + [Key(label: "⌫", action: .code(KeyCode.delete), width: 1.5, special: true)],
                [Key(label: "", action: .text(""), width: 0.5, special: true)] + "-/:;()$&@".map { Key(label: String($0), action: .text(String($0))) }
                    + [Key(label: "return", action: .code(KeyCode.returnKey), width: 2, special: true)],
                [Key(label: "tab", action: .code(KeyCode.tab), width: 1.5, special: true)] + ".,?!'\"_=+%".map { Key(label: String($0), action: .text(String($0))) },
                bottomRow(layerLabel: "ABC"),
            ]
        }
        let up = shift || capsLock
        func letters(_ s: String) -> [Key] {
            s.map { c in let t = up ? String(c).uppercased() : String(c); return Key(label: t, action: .text(t)) }
        }
        return [
            letters("qwertyuiop") + [Key(label: "⌫", action: .code(KeyCode.delete), width: 1.5, special: true)],
            [Key(label: "", action: .text(""), width: 0.5, special: true)] + letters("asdfghjkl")
                + [Key(label: "return", action: .code(KeyCode.returnKey), width: 2, special: true)],
            [Key(label: capsLock ? "⇪" : "⇧", action: .shift, width: 1.5, special: true)] + letters("zxcvbnm")
                + [Key(label: ",", action: .text(",")), Key(label: ".", action: .text(".")), Key(label: "?", action: .text("?"))],
            bottomRow(layerLabel: "123"),
        ]
    }

    private func bottomRow(layerLabel: String) -> [Key] {
        [Key(label: layerLabel, action: .layer, width: 1.5, special: true),
         Key(label: "←", action: .code(KeyCode.left), special: true),
         Key(label: "space", action: .code(KeyCode.space), width: 6, special: true),
         Key(label: "→", action: .code(KeyCode.right), special: true),
         Key(label: "hide ⌄", action: .hide, width: 2, special: true)]
    }

    /// Flattened keys with their frames.
    private var layout: [(Key, NSRect)] {
        var out: [(Key, NSRect)] = []
        var y = pad + handle - 6
        for row in rows {
            var x = pad
            for k in row {
                let w = unit * k.width
                if !(k.label.isEmpty && k.special) {
                    out.append((k, NSRect(x: x + 4, y: y + 4, width: w - 8, height: rowHeight - 8)))
                }
                x += w
            }
            y += rowHeight
        }
        return out
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        // Grab handle.
        let hw: CGFloat = 44
        NSColor(white: 1, alpha: 0.28).setFill()
        NSBezierPath(roundedRect: NSRect(x: bounds.midX - hw / 2, y: 10, width: hw, height: 5), xRadius: 2.5, yRadius: 2.5).fill()

        let gold = NSColor(cgColor: Brand.gold)!
        for (i, (k, r)) in layout.enumerated() {
            let isPressed = pressed == i
            let isHovered = hovered == i
            let active = (k.action == .shift && (shift || capsLock))
            let base: CGFloat = k.special ? 0.07 : 0.13
            let fill: NSColor
            if isPressed { fill = gold }
            else if active { fill = NSColor(white: 1, alpha: 0.85) }
            else if isHovered { fill = NSColor(white: 1, alpha: base + 0.16) }
            else { fill = NSColor(white: 1, alpha: base) }
            fill.setFill()
            let path = NSBezierPath(roundedRect: r, xRadius: 11, yRadius: 11)
            path.fill()
            if isHovered && !isPressed {
                gold.withAlphaComponent(0.9).setStroke()
                path.lineWidth = 2
                path.stroke()
            }

            let dark = isPressed || active
            let size: CGFloat = k.special ? 15 : 22
            let font = NSFont.systemFont(ofSize: size, weight: k.special ? .medium : .regular)
            let rounded = font.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? font
            let attrs: [NSAttributedString.Key: Any] = [
                .font: rounded,
                .foregroundColor: dark ? NSColor(white: 0.08, alpha: 1) : NSColor(white: 1, alpha: k.special ? 0.75 : 0.95),
            ]
            let s = k.label as NSString
            let ts = s.size(withAttributes: attrs)
            s.draw(at: NSPoint(x: r.midX - ts.width / 2, y: r.midY - ts.height / 2), withAttributes: attrs)
        }
    }

    // MARK: Input

    private func keyIndex(at p: NSPoint) -> Int? {
        layout.firstIndex { $0.1.insetBy(dx: -4, dy: -4).contains(p) }
    }

    override func mouseMoved(with event: NSEvent) {
        let i = keyIndex(at: convert(event.locationInWindow, from: nil))
        if i != hovered { hovered = i; needsDisplay = true }
    }

    override func mouseExited(with event: NSEvent) {
        hovered = nil; needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if p.y < pad + handle - 6 {
            dragOrigin = event.locationInWindow
            return
        }
        guard let i = keyIndex(at: p) else { return }
        pressed = i
        needsDisplay = true
        let key = layout[i].0
        // Type on press, like a real keyboard: lowest latency for pinch typing.
        perform(key.action)
        if key.action == .code(KeyCode.delete) {
            repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
                self?.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.07, repeats: true) { _ in
                    self?.perform(.code(KeyCode.delete))
                }
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let origin = dragOrigin, let w = window else { return }
        let now = event.locationInWindow
        w.setFrameOrigin(NSPoint(x: w.frame.origin.x + now.x - origin.x, y: w.frame.origin.y + now.y - origin.y))
    }

    override func mouseUp(with event: NSEvent) {
        dragOrigin = nil
        repeatTimer?.invalidate()
        repeatTimer = nil
        pressed = nil
        needsDisplay = true
    }

    private func perform(_ action: Action) {
        switch action {
        case .text(let t):
            guard !t.isEmpty else { return }
            monitor.noteOwnKey()
            injector.type(t)
            if shift && !capsLock { shift = false; needsDisplay = true }
        case .code(let c):
            monitor.noteOwnKey()
            injector.key(c)
        case .shift:
            let now = Date()
            if capsLock { capsLock = false; shift = false }
            else if now.timeIntervalSince(lastShiftTap) < 0.4 { capsLock = true; shift = false }
            else { shift.toggle() }
            lastShiftTap = now
        case .layer:
            symbols.toggle()
        case .hide:
            onHide?()
        }
        needsDisplay = true
    }
}
