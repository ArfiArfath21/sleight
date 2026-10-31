import AppKit
import SleightBrand

/// A small floating bar shown in pointer mode, with big pinchable buttons for
/// the keyboard and for leaving pointer mode. Never takes focus.
final class ModeBar {
    private let panel: NSPanel
    var onKeyboard: (() -> Void)?
    var onExit: (() -> Void)?

    init() {
        let size = NSSize(width: 252, height: 52)
        panel = NonActivatingPanel(contentRect: NSRect(origin: .zero, size: size),
                                   styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        let glass = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.cornerRadius = 26
        glass.layer?.masksToBounds = true
        glass.layer?.borderWidth = 1
        glass.layer?.borderColor = NSColor(white: 1, alpha: 0.12).cgColor

        let kb = BarButton(title: "Keyboard", symbol: "keyboard") { [weak self] in self?.onKeyboard?() }
        let exit = BarButton(title: "Exit", symbol: "hand.raised") { [weak self] in self?.onExit?() }
        let stack = NSStackView(views: [kb, exit])
        stack.spacing = 8
        stack.frame = glass.bounds.insetBy(dx: 7, dy: 7)
        stack.distribution = .fillEqually
        glass.addSubview(stack)
        panel.contentView = glass
    }

    func show() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main!
        let vf = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: vf.midX - panel.frame.width / 2, y: vf.minY + 18))
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.18; panel.animator().alphaValue = 1 }
    }

    func hide() {
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.15; panel.animator().alphaValue = 0 },
                                            completionHandler: { [panel] in panel.orderOut(nil) })
    }

    /// Lifts above the keyboard when it is visible.
    func place(above frame: NSRect?) {
        guard panel.isVisible else { return }
        let y = (frame?.maxY ?? (panel.screen?.visibleFrame.minY ?? 0)) + 12
        panel.setFrameOrigin(NSPoint(x: panel.frame.minX, y: frame == nil ? (panel.screen?.visibleFrame.minY ?? 0) + 18 : y))
    }
}

final class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Large button that reacts to the first click even in a non-key panel.
final class BarButton: NSView {
    private let title: String
    private let symbol: String
    private let action: () -> Void
    private var hovered = false
    private var pressed = false

    init(title: String, symbol: String, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.action = action
        super.init(frame: .zero)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func mouseDown(with event: NSEvent) { pressed = true; needsDisplay = true }
    override func mouseUp(with event: NSEvent) {
        pressed = false
        needsDisplay = true
        if bounds.contains(convert(event.locationInWindow, from: nil)) { action() }
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: 19, yRadius: 19)
        (pressed ? NSColor(cgColor: Brand.gold)!.withAlphaComponent(0.85)
                 : NSColor(white: 1, alpha: hovered ? 0.2 : 0.09)).setFill()
        path.fill()
        if hovered && !pressed {
            NSColor(cgColor: Brand.gold)!.setStroke()
            path.lineWidth = 1.5
            path.stroke()
        }
        let color: NSColor = pressed ? NSColor(white: 0.05, alpha: 1) : .white
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: color]
        let text = title as NSString
        let ts = text.size(withAttributes: attrs)
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold).applying(.init(paletteColors: [color]))
        let sym = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        let sw = sym?.size.width ?? 0
        let total = sw + 7 + ts.width
        var x = bounds.midX - total / 2
        if let sym {
            sym.draw(in: NSRect(x: x, y: bounds.midY - sym.size.height / 2, width: sym.size.width, height: sym.size.height))
            x += sw + 7
        }
        text.draw(at: NSPoint(x: x, y: bounds.midY - ts.height / 2), withAttributes: attrs)
    }
}
