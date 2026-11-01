import CoreGraphics
import AppKit
import SleightCore

/// Posts synthetic input. Every event is tagged so `InputMonitor` can tell our
/// events apart from the user's real keyboard and trackpad.
final class EventInjector {
    static let tag: Int64 = 0x53_4C45_4947_4854 // "SLEIGHT"

    private let source: CGEventSource?
    private var leftDown = false
    private var rightDown = false
    private var commandHeld = false
    /// Modifiers held by voice ("hold shift"). Every event we post carries them.
    private(set) var held: [KeyModifier] = []
    private var heldFlags: CGEventFlags { held.reduce(into: []) { $0.insert($1.flag) } }
    private var scrollRemainder = Vec2.zero

    init() {
        source = CGEventSource(stateID: .hidSystemState)
        // By default the system ignores real input for 0.25 s after a synthetic
        // event. Never lock the user's own trackpad out.
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
        let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: CGPoint(x: p.x, y: p.y),
                        mouseButton: rightDown ? .right : .left)
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
        if !held.isEmpty { e?.flags = heldFlags }   // "hold shift", then pinch = shift-click
        post(e)
    }

    /// Release anything held (buttons, ⌘, voice-held keys). Called on pause/quit so nothing sticks.
    func releaseAll(at p: Vec2) {
        if leftDown { button(.left, down: false, at: p, clickCount: 1) }
        if rightDown { button(.right, down: false, at: p, clickCount: 1) }
        if commandHeld { setCommand(false) }
        release([])
    }

    // MARK: Scroll

    /// Smooth pixel scroll, no gesture phases: every app handles these like a
    /// high-resolution mouse wheel. +y = content moves down.
    func scroll(_ delta: Vec2) {
        let total = delta + scrollRemainder
        let ix = total.x.rounded(.towardZero), iy = total.y.rounded(.towardZero)
        scrollRemainder = total - Vec2(ix, iy)
        guard ix != 0 || iy != 0,
              let e = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                              wheel1: Int32(iy), wheel2: Int32(ix), wheel3: 0) else { return }
        e.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        post(e)
    }

    // MARK: Keyboard

    func key(_ code: CGKeyCode, flags: CGEventFlags = []) {
        keyDown(code, flags: flags)
        keyUp(code, flags: flags)
    }

    func keyDown(_ code: CGKeyCode, flags: CGEventFlags = []) {
        let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)
        e?.flags = flags.union(heldFlags)
        post(e)
    }

    func keyUp(_ code: CGKeyCode, flags: CGEventFlags = []) {
        let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
        e?.flags = flags.union(heldFlags)
        post(e)
    }

    /// A named key with modifiers ("press command shift T"). false = unknown key.
    @discardableResult
    func press(_ k: KeyPress) -> Bool {
        guard let code = KeyCode.named[k.key] else { return false }
        var flags = k.modifiers.reduce(into: CGEventFlags()) { $0.insert($1.flag) }
        if KeyCode.needsFn.contains(k.key) { flags.formUnion(Self.arrowFlags) }
        if KeyCode.functionKeys.contains(code) { flags.insert(.maskSecondaryFn) }
        key(code, flags: flags)
        return true
    }

    /// Hold modifiers down until `release` ("hold shift").
    func hold(_ mods: [KeyModifier]) {
        for m in mods where !held.contains(m) {
            modifier(m.code, flag: m.flag, down: true, otherFlags: heldFlags)
            held.append(m)
        }
    }

    /// Let go of these held modifiers; empty = all.
    func release(_ mods: [KeyModifier]) {
        for m in (mods.isEmpty ? held : mods) where held.contains(m) {
            held.removeAll { $0 == m }
            modifier(m.code, flag: m.flag, down: false, otherFlags: heldFlags)
        }
    }

    /// Types text independent of the keyboard layout.
    /// Types text as key events. macOS takes at most 20 UTF-16 units per event
    /// (longer strings are cut off), so it goes in chunks that never split a character.
    func type(_ text: String) {
        var chunk: [UInt16] = []
        func flush() {
            guard !chunk.isEmpty else { return }
            for down in [true, false] {
                let e = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down)
                chunk.withUnsafeBufferPointer { buf in
                    e?.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
                }
                post(e)
            }
            chunk.removeAll()
            usleep(2_000)
        }
        for ch in text {
            let units = Array(String(ch).utf16)
            if chunk.count + units.count > 20 { flush() }
            chunk += units
        }
        flush()
    }

    /// Press or release a modifier key on its own (flagsChanged).
    func modifier(_ code: CGKeyCode, flag: CGEventFlags, down: Bool, otherFlags: CGEventFlags = []) {
        let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
        e?.type = .flagsChanged
        e?.flags = down ? otherFlags.union(flag) : otherFlags
        post(e)
    }

    private func setCommand(_ down: Bool) {
        modifier(KeyCode.command, flag: .maskCommand, down: down)
        commandHeld = down
    }

    // MARK: Commands

    /// Arrow keys carry these flags when typed on a real keyboard; some system
    /// shortcuts (Spaces) ignore arrows without them.
    private static let arrowFlags: CGEventFlags = [.maskSecondaryFn, .maskNumericPad]

    func shortcut(_ s: Shortcut) {
        let arrows = Self.arrowFlags
        switch s {
        case .back: key(KeyCode.leftBracket, flags: .maskCommand)
        case .forward: key(KeyCode.rightBracket, flags: .maskCommand)
        case .nextTab: key(KeyCode.tab, flags: .maskControl)
        case .previousTab: key(KeyCode.tab, flags: [.maskControl, .maskShift])
        case .newTab: key(KeyCode.t, flags: .maskCommand)
        case .reopenTab: key(KeyCode.t, flags: [.maskCommand, .maskShift])
        case .spaceLeft: key(KeyCode.left, flags: arrows.union(.maskControl))
        case .spaceRight: key(KeyCode.right, flags: arrows.union(.maskControl))
        case .missionControl: key(KeyCode.up, flags: arrows.union(.maskControl))
        case .appExpose: key(KeyCode.down, flags: arrows.union(.maskControl))
        case .showDesktop: key(KeyCode.f11, flags: .maskSecondaryFn)
        case .hideApp: key(KeyCode.h, flags: .maskCommand)
        case .minimize: key(KeyCode.m, flags: .maskCommand)
        case .fullScreen: key(KeyCode.f, flags: [.maskCommand, .maskControl])
        case .zoomIn: key(KeyCode.equal, flags: .maskCommand)
        case .zoomOut: key(KeyCode.minus, flags: .maskCommand)
        case .arrowLeft: key(KeyCode.left, flags: arrows)
        case .arrowRight: key(KeyCode.right, flags: arrows)
        case .arrowUp: key(KeyCode.up, flags: arrows)
        case .arrowDown: key(KeyCode.down, flags: arrows)
        case .screenshot: key(KeyCode.three, flags: [.maskCommand, .maskShift])
        case .screenshotSelection: key(KeyCode.four, flags: [.maskCommand, .maskShift])
        case .screenshotTool: key(KeyCode.five, flags: [.maskCommand, .maskShift])
        case .spotlight: key(KeyCode.space, flags: .maskCommand)
        case .lockScreen: key(KeyCode.q, flags: [.maskCommand, .maskControl])
        case .closeTab: key(KeyCode.w, flags: .maskCommand)
        case .newWindow: key(KeyCode.n, flags: .maskCommand)
        case .quitApp: key(KeyCode.q, flags: .maskCommand)
        case .undo: key(KeyCode.z, flags: .maskCommand)
        case .redo: key(KeyCode.z, flags: [.maskCommand, .maskShift])
        case .cut: key(KeyCode.x, flags: .maskCommand)
        case .copy: key(KeyCode.c, flags: .maskCommand)
        case .paste: key(KeyCode.v, flags: .maskCommand)
        case .selectAll: key(KeyCode.a, flags: .maskCommand)
        case .save: key(KeyCode.s, flags: .maskCommand)
        case .find: key(KeyCode.f, flags: .maskCommand)
        case .reload: key(KeyCode.r, flags: .maskCommand)
        case .scrollToTop: key(KeyCode.up, flags: arrows.union(.maskCommand))
        case .scrollToBottom: key(KeyCode.down, flags: arrows.union(.maskCommand))
        case .returnKey: key(KeyCode.returnKey)
        case .escapeKey: key(KeyCode.escape)
        case .tabKey: key(KeyCode.tab)
        case .spaceKey: key(KeyCode.space)
        case .deleteKey: key(KeyCode.delete)
        }
    }

    func switcher(_ step: SwitcherStep) {
        switch step {
        case .begin:
            setCommand(true)
            key(KeyCode.tab, flags: .maskCommand)
        case .next:
            key(KeyCode.tab, flags: .maskCommand)
        case .previous:
            key(KeyCode.tab, flags: [.maskCommand, .maskShift])
        case .commit:
            setCommand(false)
        case .cancel:
            key(KeyCode.escape, flags: .maskCommand)
            setCommand(false)
        }
    }

    /// Hardware media keys (play/pause, volume), exactly as the keyboard sends them.
    func media(_ k: MediaKey) {
        let code: Int
        switch k {
        case .volumeUp: code = 0       // NX_KEYTYPE_SOUND_UP
        case .volumeDown: code = 1     // NX_KEYTYPE_SOUND_DOWN
        case .playPause: code = 16     // NX_KEYTYPE_PLAY
        case .next: code = 17          // NX_KEYTYPE_NEXT
        case .previous: code = 18      // NX_KEYTYPE_PREVIOUS
        case .mute: code = 7           // NX_KEYTYPE_MUTE
        case .brightnessUp: code = 2   // NX_KEYTYPE_BRIGHTNESS_UP
        case .brightnessDown: code = 3 // NX_KEYTYPE_BRIGHTNESS_DOWN
        }
        for down in [true, false] {
            let state = down ? 0xA : 0xB
            let ev = NSEvent.otherEvent(with: .systemDefined, location: .zero,
                                        modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)),
                                        timestamp: 0, windowNumber: 0, context: nil, subtype: 8,
                                        data1: (code << 16) | (state << 8), data2: -1)
            post(ev?.cgEvent)
        }
    }
}

enum KeyCode {
    static let a: CGKeyCode = 0
    static let returnKey: CGKeyCode = 36
    static let tab: CGKeyCode = 48
    static let space: CGKeyCode = 49
    static let delete: CGKeyCode = 51
    static let escape: CGKeyCode = 53
    static let command: CGKeyCode = 55
    static let shift: CGKeyCode = 56
    static let option: CGKeyCode = 58
    static let control: CGKeyCode = 59
    static let left: CGKeyCode = 123
    static let right: CGKeyCode = 124
    static let down: CGKeyCode = 125
    static let up: CGKeyCode = 126
    static let leftBracket: CGKeyCode = 33
    static let rightBracket: CGKeyCode = 30
    static let equal: CGKeyCode = 24
    static let minus: CGKeyCode = 27
    static let forwardDelete: CGKeyCode = 117
    static let f11: CGKeyCode = 103
    static let three: CGKeyCode = 20
    static let four: CGKeyCode = 21
    static let five: CGKeyCode = 23
    static let t: CGKeyCode = 17
    static let h: CGKeyCode = 4
    static let m: CGKeyCode = 46
    static let f: CGKeyCode = 3
    static let q: CGKeyCode = 12
    static let s: CGKeyCode = 1
    static let z: CGKeyCode = 6
    static let x: CGKeyCode = 7
    static let c: CGKeyCode = 8
    static let v: CGKeyCode = 9
    static let w: CGKeyCode = 13
    static let r: CGKeyCode = 15
    static let n: CGKeyCode = 45
    static let function: CGKeyCode = 63

    /// Key names from `SleightCore.Keys` → ANSI key codes.
    static let named: [String: CGKeyCode] = {
        var m: [String: CGKeyCode] = [
            "return": 36, "escape": 53, "tab": 48, "space": 49, "delete": 51, "forwardDelete": 117,
            "up": 126, "down": 125, "left": 123, "right": 124,
            "home": 115, "end": 119, "pageUp": 116, "pageDown": 121,
            "comma": 43, "period": 47, "slash": 44, "backslash": 42, "minus": 27, "equals": 24,
            "semicolon": 41, "quote": 39, "grave": 50, "leftBracket": 33, "rightBracket": 30,
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
            "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "o": 31, "u": 32,
            "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
            "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22, "7": 26, "8": 28, "9": 25, "0": 29,
        ]
        let fkeys: [CGKeyCode] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]
        for (i, code) in fkeys.enumerated() { m["f\(i + 1)"] = code }
        return m
    }()

    /// Keys that a real keyboard sends with the fn / keypad flags.
    static let needsFn: Set<String> = ["up", "down", "left", "right", "home", "end", "pageUp", "pageDown", "forwardDelete"]
    static let functionKeys: Set<CGKeyCode> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]
}

extension KeyModifier {
    var flag: CGEventFlags {
        switch self {
        case .control: return .maskControl
        case .option: return .maskAlternate
        case .shift: return .maskShift
        case .command: return .maskCommand
        case .function: return .maskSecondaryFn
        }
    }

    var code: CGKeyCode {
        switch self {
        case .control: return KeyCode.control
        case .option: return KeyCode.option
        case .shift: return KeyCode.shift
        case .command: return KeyCode.command
        case .function: return KeyCode.function
        }
    }
}
