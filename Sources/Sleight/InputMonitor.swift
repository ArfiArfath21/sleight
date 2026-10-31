import CoreGraphics
import Foundation
import QuartzCore
import Carbon.HIToolbox
import SleightCore

/// Notices when the user touches the real keyboard, trackpad or mouse, so hand
/// control steps aside instantly. Listen-only: it never blocks or alters events.
final class InputMonitor {
    private var tap: CFMachPort?
    private let lock = NSLock()
    private var _lastRealInput: Double?
    private var lastOwnKey = 0.0
    private let shared: SharedState

    /// Host time (CACurrentMediaTime) of the last real input.
    var lastRealInput: Double? { lock.withLock { _lastRealInput } }

    init(shared: SharedState) { self.shared = shared }

    /// The on-screen keyboard calls this right before posting a key, as a second
    /// line of defence in case the tag does not survive.
    func noteOwnKey() { lock.withLock { lastOwnKey = CACurrentMediaTime() } }

    @discardableResult
    func start() -> Bool {
        let types: [CGEventType] = [.keyDown, .mouseMoved, .leftMouseDown, .rightMouseDown,
                                    .leftMouseDragged, .scrollWheel, .otherMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << CGEventMask($1.rawValue)) }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap,
                                          options: .listenOnly, eventsOfInterest: mask,
                                          callback: { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<InputMonitor>.fromOpaque(refcon).takeUnretainedValue()
            me.handle(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }, userInfo: refcon) else { return false }
        self.tap = tap
        let src = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        if event.getIntegerValueField(.eventSourceUserData) == EventInjector.tag { return }
        let now = CACurrentMediaTime()
        switch type {
        case .keyDown:
            if lock.withLock({ now - lastOwnKey < 0.05 }) { return }
            // Our own hotkeys (⌃⌥S/P/K) should not count as "typing".
            let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
            if [kVK_ANSI_S, kVK_ANSI_P, kVK_ANSI_K].contains(code),
               event.flags.contains([.maskControl, .maskAlternate]) { return }
        case .mouseMoved, .leftMouseDragged, .leftMouseDown, .rightMouseDown:
            let p = event.location
            if shared.isOwnMouseEvent(at: Vec2(Double(p.x), Double(p.y))) { return }
        case .scrollWheel:
            if shared.isOwnScrollRecent { return }
        default:
            break
        }
        lock.withLock { _lastRealInput = now }
    }
}

/// System-wide hotkey via Carbon (needs no extra permission).
final class HotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let id: UInt32
    private let action: () -> Void

    init(id: UInt32, keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        self.id = id
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, user in
            guard let user, let event else { return OSStatus(eventNotHandledErr) }
            let hk = Unmanaged<HotKey>.fromOpaque(user).takeUnretainedValue()
            var fired = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &fired)
            // Every handler sees every hotkey: only react to our own.
            guard fired.id == hk.id else { return OSStatus(eventNotHandledErr) }
            DispatchQueue.main.async { hk.action() }
            return noErr
        }, 1, &spec, me, &handler)
        let hotID = EventHotKeyID(signature: OSType(0x534C_4754), id: id) // 'SLGT'
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotID, GetApplicationEventTarget(), 0, &ref)
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }
}
