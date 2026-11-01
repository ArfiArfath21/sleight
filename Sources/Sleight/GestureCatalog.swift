import Foundation
import SleightCore

/// Every gesture Sleight recognises, explained in plain words. One source for
/// Settings, the Guide and the Practice window. What a gesture *does* comes from
/// the user's assignments, except for the reserved ones that drive Sleight itself.
struct GestureInfo: Identifiable, Equatable {
    var id: String { gesture?.rawValue ?? reserved!.rawValue }
    let gesture: GestureID?
    let reserved: ReservedGesture?
    let group: String
    let title: String
    let how: String

    init(_ g: GestureID, _ group: String, _ title: String, _ how: String) {
        gesture = g; reserved = nil; self.group = group; self.title = title; self.how = how
    }

    init(reserved r: ReservedGesture, _ group: String, _ title: String, _ how: String) {
        gesture = nil; reserved = r; self.group = group; self.title = title; self.how = how
    }

    func effect(_ map: GestureMap) -> String {
        if let g = gesture { return map[g].title }
        switch reserved! {
        case .handsUp: return "Rest / wake Sleight"
        case .pointHold: return "Pointer mode"
        case .fistHold: return "Leave pointer mode"
        }
    }
}

enum GestureCatalog {
    static let vee = "✌️  Two fingers"
    static let open = "✋  Open hand"
    static let ok = "👌  OK sign"
    static let fist = "✊  Fist"
    static let both = "🙌  Both hands"
    static let pointer = "☝️  Pointer"

    private static let veeHow = "Peace sign: index and middle finger up, the others folded, palm facing the screen. Snap it about a hand's length, quick, like flicking water off your fingers, then bring it back slowly."
    private static let openHow = "Open hand, palm facing the screen. Sweep it quickly across, like pushing a page aside."

    static let all: [GestureInfo] = [
        GestureInfo(.veeFlickUp, vee, "Flick up", veeHow),
        GestureInfo(.veeFlickDown, vee, "Flick down", "Same peace sign, snapped downward."),
        GestureInfo(.veeFlickRight, vee, "Flick right", "Same peace sign, snapped to the right."),
        GestureInfo(.veeFlickLeft, vee, "Flick left", "Same peace sign, snapped to the left."),
        GestureInfo(.openSwipeRight, open, "Swipe right", openHow),
        GestureInfo(.openSwipeLeft, open, "Swipe left", "Open hand, swept quickly to the left."),
        GestureInfo(.openSwipeUp, open, "Swipe up", "Open hand, swept quickly upward."),
        GestureInfo(.openSwipeDown, open, "Swipe down", "Open hand, swept quickly downward. Start with the hand high: dropping a hand to rest is not a swipe."),
        GestureInfo(.okTap, ok, "Tap", "Touch thumb and index fingertips while the other three fingers stay up. Start with the fingers apart, pinch, let go quickly."),
        GestureInfo(.okSlideVertical, ok, "Hold, slide up / down", "Make the OK sign and hold it still for a moment, then slide up or down. Each stretch of travel is one step. Let go to stop."),
        GestureInfo(.okSlideSideways, ok, "Hold, slide sideways", "Make the OK sign, hold it still for a moment, then slide left or right, one step per stretch of travel."),
        GestureInfo(.fistSlideSideways, fist, "Grab and slide", "Close your hand into a fist and pause for a beat, then slide it sideways: one step per stretch of travel. Open your hand to finish (for the app switcher, that picks the app)."),
        GestureInfo(reserved: .handsUp, both, "Both hands up, hold", "Raise both hands open, palms to the screen, about shoulder-width apart, as if saying \"hold on\". Keep them still for a second until the ring fills. While resting, Sleight keeps watching but only this wakes it."),
        GestureInfo(.curtains, both, "Part the curtains", "Bring both open hands together in front of you, palms to the screen, side by side and almost touching. When \"Part the curtains\" appears, sweep them apart sideways, fast."),
        GestureInfo(.frame, both, "Frame it", "Make an L with each hand: index finger up, thumb out sideways, other fingers folded. Hold the hands apart like framing a photo and keep still for half a second."),
        GestureInfo(.doubleClap, both, "Double clap (experimental)", "Clap twice, quickly, with your hands in view. Hands hide each other at the moment of a clap, so the camera misses some."),
        GestureInfo(reserved: .pointHold, pointer, "Point and hold", "Point your index finger up with the other fingers folded and hold still for half a second. Move your hand to move the cursor; pinch to click, pinch twice to double-click, pinch-hold-move to drag, thumb + middle finger to right-click."),
        GestureInfo(reserved: .fistHold, pointer, "Fist (in pointer mode)", "Close your hand into a fist and hold it for a moment."),
    ]

    /// Voice commands, for the Guide and Settings: (what to say, what happens).
    static func voice(_ w: WakeWord) -> [(String, String)] {
        let p = w.phrase
        return [
            ("\(p), camera on / camera off", "Starts or stops the camera (and gestures)"),
            ("\(p), switch to Claude", "Brings any app forward, opening it if needed"),
            ("\(p), scroll down / go back / next tab", "Any action in the gesture list, by name"),
            ("\(p), export as PDF", "Any menu command of the app in front, by its name"),
            ("\(p), next tab twice", "Add \"twice\" or \"3 times\" to repeat"),
            ("\(p), pause / next track / volume up", "Media keys"),
            ("\(p), type / say see you at six", "Types what you say into the text field you're in"),
            ("\(p), search for flights to Goa", "Spotlight search"),
            ("\(p), rest / wake up", "Rests gestures and voice; only \"wake up\" works while resting"),
            ("\(p), pointer mode", "Pointer mode, without the gesture"),
            ("⌃⌥V, then speak", "Push to talk: no wake word, works with voice off"),
        ]
    }

    static var groups: [String] {
        var seen: [String] = []
        for g in all.map(\.group) where !seen.contains(g) { seen.append(g) }
        return seen
    }

    static func info(_ g: GestureID) -> GestureInfo? { all.first { $0.gesture == g } }

    /// Which catalog entry an engine action came from (Practice window).
    static func entryID(for action: EngineAction) -> String? {
        switch action {
        case .recognized(let g): return g.rawValue
        case .activeChanged: return ReservedGesture.handsUp.rawValue
        case .modeChanged(.pointer, .gesture): return ReservedGesture.pointHold.rawValue
        case .modeChanged(.command, .gesture): return ReservedGesture.fistHold.rawValue
        default: return nil
        }
    }

    /// SF Symbol for an action, for confirmation chips.
    static func symbol(_ a: ActionID) -> String {
        switch a {
        case .none: return "circle"
        case .scrollDown: return "arrow.down"
        case .scrollUp: return "arrow.up"
        case .back: return "chevron.backward"
        case .forward: return "chevron.forward"
        case .nextTab, .previousTab, .stepTabs: return "square.on.square"
        case .newTab: return "plus.square.on.square"
        case .reopenTab: return "arrow.uturn.backward"
        case .desktopLeft: return "arrow.left.square"
        case .desktopRight: return "arrow.right.square"
        case .stepDesktops: return "rectangle.split.3x1"
        case .missionControl: return "rectangle.3.group"
        case .appWindows: return "rectangle.stack"
        case .showDesktop: return "macwindow.on.rectangle"
        case .previousApp, .stepAppSwitcher: return "square.stack.3d.up"
        case .hideApp: return "eye.slash"
        case .minimize: return "minus.square"
        case .fullScreen: return "arrow.up.left.and.arrow.down.right"
        case .playPause: return "playpause.fill"
        case .nextTrack: return "forward.fill"
        case .previousTrack: return "backward.fill"
        case .volumeUp: return "speaker.wave.3.fill"
        case .volumeDown: return "speaker.wave.1.fill"
        case .stepVolume: return "speaker.wave.2"
        case .mute: return "speaker.slash.fill"
        case .zoomIn, .stepZoom: return "plus.magnifyingglass"
        case .zoomOut: return "minus.magnifyingglass"
        case .arrowLeft: return "arrow.left"
        case .arrowRight: return "arrow.right"
        case .arrowUp: return "arrow.up"
        case .arrowDown: return "arrow.down"
        case .stepArrowsHorizontal: return "arrow.left.and.right"
        case .stepArrowsVertical: return "arrow.up.and.down"
        case .screenshot: return "camera.viewfinder"
        case .screenshotSelection: return "crop"
        case .screenshotTool: return "camera.aperture"
        case .spotlight: return "magnifyingglass"
        case .lockScreen: return "lock.fill"
        case .toggleKeyboard: return "keyboard"
        case .restWake: return "moon"
        case .stepBrightness: return "sun.max"
        case .closeTab: return "xmark.square"
        case .newWindow: return "macwindow.badge.plus"
        case .quitApp: return "power"
        case .undo: return "arrow.uturn.backward"
        case .redo: return "arrow.uturn.forward"
        case .cut: return "scissors"
        case .copy: return "doc.on.doc"
        case .paste: return "doc.on.clipboard"
        case .selectAll: return "selection.pin.in.out"
        case .save: return "square.and.arrow.down"
        case .find: return "magnifyingglass"
        case .reload: return "arrow.clockwise"
        case .scrollToTop: return "arrow.up.to.line"
        case .scrollToBottom: return "arrow.down.to.line"
        case .returnKey: return "return"
        case .escapeKey: return "escape"
        case .tabKey: return "arrow.right.to.line"
        case .spaceKey: return "space"
        case .deleteKey: return "delete.left"
        }
    }
}
