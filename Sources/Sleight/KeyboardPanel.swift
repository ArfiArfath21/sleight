import AppKit
import SleightBrand

/// A floating, non-activating Mac keyboard: pinching its keys types into the
/// app that has focus, without ever taking focus itself. Full ANSI layout with
/// ⌘ ⌥ ⌃ ⇧: tap a modifier for the next key, double-tap to lock it. Keys are
/// big (hand-pointing targets) and highlight on hover.
final class KeyboardPanelController {
    private let panel: NonActivatingPanel
    private let view: KeyboardView
    var onVisibilityChange: ((NSRect?) -> Void)?

    init(injector: EventInjector, monitor: InputMonitor) {
        view = KeyboardView(injector: injector, monitor: monitor)
        let size = view.intrinsicContentSize
        panel = NonActivatingPanel(contentRect: NSRect(origin: .zero, size: size),
                                   styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

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
        view.onMoved = { [weak self] in self.map { $0.onVisibilityChange?($0.panel.frame) } }
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() { isVisible ? hide() : show() }

    func show() {
        guard !isVisible else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main!
        let vf = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: vf.midX - panel.frame.width / 2, y: vf.minY + 16))
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.18; panel.animator().alphaValue = 1 }
        onVisibilityChange?(panel.frame)
    }

    func hide() {
        guard isVisible else { return }
        view.resetModifiers()
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.15; panel.animator().alphaValue = 0 },
                                            completionHandler: { [panel] in panel.orderOut(nil) })
        onVisibilityChange?(nil)
    }
}

final class KeyboardView: NSView {
    enum Modifier: CaseIterable {
        case command, option, control, shift

        var flag: CGEventFlags {
            switch self {
            case .command: return .maskCommand
            case .option: return .maskAlternate
            case .control: return .maskControl
            case .shift: return .maskShift
            }
        }
    }

    enum Action: Equatable {
        /// A character key: what it types, what it types shifted, its ANSI key code.
        case char(String, String, CGKeyCode)
        case code(CGKeyCode)
        case modifier(Modifier)
        case hide
    }

    struct Key {
        var label: String
        var action: Action
        var width: CGFloat = 1
        var special = false
    }

    private enum ModState { case off, once, locked }

    private let injector: EventInjector
    private let monitor: InputMonitor
    var onHide: (() -> Void)?
    var onMoved: (() -> Void)?

    private let unit: CGFloat = 50
    private let rowHeight: CGFloat = 50
    private let pad: CGFloat = 14
    private let handle: CGFloat = 20

    private var mods: [Modifier: ModState] = [:]
    private var lastModTap: [Modifier: Date] = [:]
    private var hovered: Int?
    private var pressed: Int?
    private var repeatTimer: Timer?
    private var dragOrigin: NSPoint?
    private var cachedLayout: [(Key, NSRect)]?

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
        NSSize(width: pad * 2 + unit * 16, height: pad + handle + rowHeight * 5 + pad - 6)
    }

    func resetModifiers() { mods = [:]; needsDisplay = true }

    private func isOn(_ m: Modifier) -> Bool { (mods[m] ?? .off) != .off }

    // MARK: Layout (ANSI, 16 units wide)

    private static func c(_ base: String, _ shifted: String, _ code: CGKeyCode) -> Key {
        Key(label: base, action: .char(base, shifted, code))
    }

    private static let rows: [[Key]] = {
        let digits: [(String, String, CGKeyCode)] = [("1", "!", 18), ("2", "@", 19), ("3", "#", 20), ("4", "$", 21), ("5", "%", 23),
                                                     ("6", "^", 22), ("7", "&", 26), ("8", "*", 28), ("9", "(", 25), ("0", ")", 29)]
        let qrow: [(String, CGKeyCode)] = [("q", 12), ("w", 13), ("e", 14), ("r", 15), ("t", 17), ("y", 16), ("u", 32), ("i", 34), ("o", 31), ("p", 35)]
        let arow: [(String, CGKeyCode)] = [("a", 0), ("s", 1), ("d", 2), ("f", 3), ("g", 5), ("h", 4), ("j", 38), ("k", 40), ("l", 37)]
        let zrow: [(String, CGKeyCode)] = [("z", 6), ("x", 7), ("c", 8), ("v", 9), ("b", 11), ("n", 45), ("m", 46)]
        func letter(_ l: (String, CGKeyCode)) -> Key { c(l.0, l.0.uppercased(), l.1) }
        return [
            [Key(label: "esc", action: .code(KeyCode.escape), width: 1.5, special: true), c("`", "~", 50)]
                + digits.map { c($0.0, $0.1, $0.2) }
                + [c("-", "_", 27), c("=", "+", 24), Key(label: "⌫", action: .code(KeyCode.delete), width: 1.5, special: true)],
            [Key(label: "tab", action: .code(KeyCode.tab), width: 2, special: true)] + qrow.map(letter)
                + [c("[", "{", 33), c("]", "}", 30), Key(label: "\\", action: .char("\\", "|", 42), width: 2)],
            [Key(label: "control", action: .modifier(.control), width: 2.25, special: true)] + arow.map(letter)
                + [c(";", ":", 41), c("'", "\"", 39), Key(label: "return", action: .code(KeyCode.returnKey), width: 2.75, special: true)],
            [Key(label: "shift", action: .modifier(.shift), width: 2.75, special: true)] + zrow.map(letter)
                + [c(",", "<", 43), c(".", ">", 47), c("/", "?", 44), Key(label: "shift", action: .modifier(.shift), width: 3.25, special: true)],
            [Key(label: "option", action: .modifier(.option), width: 1.5, special: true),
             Key(label: "command", action: .modifier(.command), width: 1.75, special: true),
             Key(label: "", action: .code(KeyCode.space), width: 5.75, special: true),
             Key(label: "command", action: .modifier(.command), width: 1.75, special: true),
             Key(label: "←", action: .code(KeyCode.left), special: true),
             Key(label: "↑", action: .code(KeyCode.up), special: true),
             Key(label: "↓", action: .code(KeyCode.down), special: true),
             Key(label: "→", action: .code(KeyCode.right), special: true),
             Key(label: "⌄", action: .hide, width: 1.25, special: true)],
        ]
    }()

    private var layout: [(Key, NSRect)] {
        if let cachedLayout { return cachedLayout }
        var out: [(Key, NSRect)] = []
        var y = pad + handle - 4
        for row in Self.rows {
            var x = pad
            for k in row {
                let w = unit * k.width
                out.append((k, NSRect(x: x + 3, y: y + 3, width: w - 6, height: rowHeight - 6)))
                x += w
            }
            y += rowHeight
        }
        cachedLayout = out
        return out
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let hw: CGFloat = 44
        NSColor(white: 1, alpha: 0.28).setFill()
        NSBezierPath(roundedRect: NSRect(x: bounds.midX - hw / 2, y: 9, width: hw, height: 5), xRadius: 2.5, yRadius: 2.5).fill()

        let accent = NSColor(cgColor: Brand.cyan)!
        let shifted = isOn(.shift)
        for (i, (k, r)) in layout.enumerated() {
            var modState: ModState = .off
            if case .modifier(let m) = k.action { modState = mods[m] ?? .off }
            let isPressed = pressed == i
            let isHovered = hovered == i
            let fill: NSColor
            if isPressed { fill = accent }
            else if modState != .off { fill = NSColor(white: 1, alpha: 0.88) }
            else if isHovered { fill = NSColor(white: 1, alpha: (k.special ? 0.07 : 0.13) + 0.16) }
            else { fill = NSColor(white: 1, alpha: k.special ? 0.07 : 0.13) }
            fill.setFill()
            let path = NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10)
            path.fill()
            if isHovered && !isPressed {
                accent.withAlphaComponent(0.95).setStroke()
                path.lineWidth = 2
                path.stroke()
            }
            if modState == .locked {
                // Lock indicator: a small bar under the label.
                NSColor(white: 0.1, alpha: 1).setFill()
                NSBezierPath(roundedRect: NSRect(x: r.midX - 7, y: r.maxY - 8, width: 14, height: 3), xRadius: 1.5, yRadius: 1.5).fill()
            }

            var label = k.label
            if case .char(let base, let up, _) = k.action { label = shifted ? up : base }
            if case .modifier(let m) = k.action {
                switch m {
                case .command: label = "⌘ command"
                case .option: label = "⌥ option"
                case .control: label = "⌃ control"
                case .shift: label = "⇧ shift"
                }
            }
            let dark = isPressed || modState != .off
            let size: CGFloat = k.special ? 12.5 : 19
            let base = NSFont.systemFont(ofSize: size, weight: k.special ? .medium : .regular)
            let font = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: dark ? NSColor(white: 0.08, alpha: 1) : NSColor(white: 1, alpha: k.special ? 0.75 : 0.95),
            ]
            let s = label as NSString
            let ts = s.size(withAttributes: attrs)
            s.draw(at: NSPoint(x: r.midX - ts.width / 2, y: r.midY - ts.height / 2 - (modState == .locked ? 2 : 0)), withAttributes: attrs)
        }
    }

    // MARK: Input

    private func keyIndex(at p: NSPoint) -> Int? {
        layout.firstIndex { $0.1.insetBy(dx: -3, dy: -3).contains(p) }
    }

    override func mouseMoved(with event: NSEvent) {
        let i = keyIndex(at: convert(event.locationInWindow, from: nil))
        if i != hovered { hovered = i; needsDisplay = true }
    }

    override func mouseExited(with event: NSEvent) { hovered = nil; needsDisplay = true }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if p.y < pad + handle - 4 { dragOrigin = event.locationInWindow; return }
        guard let i = keyIndex(at: p) else { return }
        pressed = i
        needsDisplay = true
        let key = layout[i].0
        // Fire on press, like a real keyboard: lowest latency for pinch typing.
        perform(key.action)
        if key.action == .code(KeyCode.delete) || key.action == .code(KeyCode.left) || key.action == .code(KeyCode.right) {
            let action = key.action
            repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
                self?.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.07, repeats: true) { _ in self?.perform(action) }
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let origin = dragOrigin, let w = window else { return }
        let now = event.locationInWindow
        w.setFrameOrigin(NSPoint(x: w.frame.origin.x + now.x - origin.x, y: w.frame.origin.y + now.y - origin.y))
        onMoved?()
    }

    override func mouseUp(with event: NSEvent) {
        dragOrigin = nil
        repeatTimer?.invalidate()
        repeatTimer = nil
        pressed = nil
        needsDisplay = true
    }

    private var activeFlags: CGEventFlags {
        Modifier.allCases.filter(isOn).reduce(CGEventFlags()) { $0.union($1.flag) }
    }

    private func perform(_ action: Action) {
        switch action {
        case .char(let base, let up, let code):
            monitor.noteOwnKey()
            let hasCommandish = isOn(.command) || isOn(.control) || isOn(.option)
            if hasCommandish {
                // Shortcuts need real key codes plus flags (⌘C, ⌥←, ⌃A…).
                injector.key(code, flags: activeFlags)
            } else {
                // Plain typing: layout-independent unicode.
                injector.type(isOn(.shift) ? up : base)
            }
            consumeOneShots()
        case .code(let code):
            monitor.noteOwnKey()
            injector.key(code, flags: activeFlags)
            consumeOneShots()
        case .modifier(let m):
            let now = Date()
            switch mods[m] ?? .off {
            case .off:
                mods[m] = .once
            case .once:
                // Double-tap locks.
                mods[m] = now.timeIntervalSince(lastModTap[m] ?? .distantPast) < 0.4 ? .locked : .off
            case .locked:
                mods[m] = .off
            }
            lastModTap[m] = now
        case .hide:
            onHide?()
        }
        needsDisplay = true
    }

    private func consumeOneShots() {
        for (m, s) in mods where s == .once { mods[m] = .off }
    }
}
