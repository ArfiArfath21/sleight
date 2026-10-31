import CoreGraphics
import AppKit
import MaestroCore

/// Posts synthetic input. Every event is tagged so `InputMonitor` can tell our
/// events apart from the user's real keyboard and trackpad.
final class EventInjector {
    static let tag: Int64 = 0x4D_4145_5354_524F // "MAESTRO"

    private let source: CGEventSource?
    private var leftDown = false
    private var rightDown = false
    private var scrollRemainder = Vec2.zero

    init() {
        source = CGEventSource(stateID: .hidSystemState)
        // By default the system ignores real input for 0.25 s after a synthetic
        // event. We never want to lock the user's trackpad out.
        source?.localEventsSuppressionInterval = 0
    }

    private func post(_ e: CGEvent?) {
        guard let e else { return }
        e.setIntegerValueField(.eventSourceUserData, value: EventInjector.tag)
        e.post(tap: .cghidEventTap)
    }

    static func currentCursor() -> Vec2 {
        let p = CGEvent(source: nil)?.location ?? .zero
        return Vec2(Double(p.x), Double(p.y))
    }

    // MARK: Mouse

    func move(to p: Vec2, delta: Vec2) {
        let type: CGEventType = leftDown ? .leftMouseDragged : (rightDown ? .rightMouseDragged : .mouseMoved)
        let button: CGMouseButton = rightDown ? .right : .left
        let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: CGPoint(x: p.x, y: p.y), mouseButton: button)
        e?.setIntegerValueField(.mouseEventDeltaX, value: Int64(delta.x.rounded()))
        e?.setIntegerValueField(.mouseEventDeltaY, value: Int64(delta.y.rounded()))
        post(e)
    }

    func button(_ b: MouseButton, down: Bool, at p: Vec2, clickCount: Int) {
        let type: CGEventType
        switch (b, down) {
        case (.left, true): type = .leftMouseDown; leftDown = true
        case (.left, false): type = .leftMouseUp; leftDown = false
        case (.right, true): type = .rightMouseDown; rightDown = true
        case (.right, false): type = .rightMouseUp; rightDown = false
        }
        let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: CGPoint(x: p.x, y: p.y),
                        mouseButton: b == .left ? .left : .right)
        e?.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
        post(e)
    }

    /// Release anything held. Called on pause/quit so a button can never stick.
    func releaseAll(at p: Vec2) {
        if leftDown { button(.left, down: false, at: p, clickCount: 1) }
        if rightDown { button(.right, down: false, at: p, clickCount: 1) }
    }

    // MARK: Scroll

    enum MomentumPhase: Int64 { case none = 0, begin = 1, `continue` = 2, end = 3 }

    /// `delta` in pixels: +y = content moves down (wheel up), +x = content moves right.
    func scroll(_ delta: Vec2, phase: ScrollPhase?, momentum: MomentumPhase = .none) {
        let total = delta + scrollRemainder
        let ix = total.x.rounded(.towardZero), iy = total.y.rounded(.towardZero)
        scrollRemainder = total - Vec2(ix, iy)
        guard let e = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                              wheel1: Int32(iy), wheel2: Int32(ix), wheel3: 0) else { return }
        e.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        e.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: delta.y)
        e.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: delta.x)
        e.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: delta.y)
        e.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: delta.x)
        if let phase {
            // NSEvent.Phase raw values: began 1, changed 4, ended 8.
            let raw: Int64 = phase == .began ? 1 : (phase == .changed ? 4 : 8)
            e.setIntegerValueField(.scrollWheelEventScrollPhase, value: raw)
        }
        e.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum.rawValue)
        post(e)
    }

    // MARK: Keyboard

    func key(_ code: CGKeyCode, flags: CGEventFlags = []) {
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
            e?.flags = flags
            post(e)
        }
    }

    /// Types arbitrary text independent of the keyboard layout.
    func type(_ text: String) {
        let units = Array(text.utf16)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down)
            units.withUnsafeBufferPointer { buf in
                e?.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
            }
            post(e)
        }
    }

    // MARK: System actions

    func switchSpace(left: Bool) { key(left ? 123 : 124, flags: .maskControl) }
    func missionControl() { key(126, flags: .maskControl) }
}

enum KeyCode {
    static let returnKey: CGKeyCode = 36
    static let tab: CGKeyCode = 48
    static let space: CGKeyCode = 49
    static let delete: CGKeyCode = 51
    static let escape: CGKeyCode = 53
    static let left: CGKeyCode = 123
    static let right: CGKeyCode = 124
    static let down: CGKeyCode = 125
    static let up: CGKeyCode = 126
}
