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
        GestureInfo(.fistFlickUp, fist, "Flick up", "Close your hand into a fist and snap it upward about a hand's length, quick, then bring it back slowly."),
        GestureInfo(.fistFlickDown, fist, "Flick down", "Same fist, snapped downward. Start with the hand high: lowering a fist to rest is not a flick."),
        GestureInfo(reserved: .handsUp, both, "Both hands up, hold", "Raise both hands open, palms to the screen, about shoulder-width apart, as if saying \"hold on\". Keep them still for a second until the ring fills. While resting, Sleight keeps watching but only this wakes it."),
        GestureInfo(.curtains, both, "Part the curtains", "Bring both open hands together in front of you, palms to the screen, side by side and almost touching. When \"Part the curtains\" appears, sweep them apart sideways, fast."),
        GestureInfo(.frame, both, "Frame it", "Make an L with each hand: index finger up, thumb out sideways, other fingers folded. Hold the hands apart like framing a photo and keep still for half a second."),
        GestureInfo(.doubleClap, both, "Double clap (experimental)", "Clap twice, quickly, with your hands in view. Hands hide each other at the moment of a clap, so the camera misses some."),
        GestureInfo(reserved: .pointHold, pointer, "Point and hold", "Point your index finger up with the other fingers folded and hold still for half a second. Move your hand to move the cursor; pinch to click, pinch twice to double-click, pinch-hold-move to drag, thumb + middle finger to right-click."),
        GestureInfo(reserved: .fistHold, pointer, "Fist (in pointer mode)", "Close your hand into a fist and hold it for a moment."),
    ]

    /// Voice commands, grouped, for Settings and the Guide. Each command lists
    /// things to say (shown after the wake word) and what happens.
    struct VoiceCommand: Identifiable {
        var id: String { say.joined(separator: "|") }
        let say: [String]
        let does: String
    }

    struct VoiceGroup: Identifiable {
        var id: String { title }
        let title: String
        let symbol: String
        let commands: [VoiceCommand]
    }

    static let voiceGroups: [VoiceGroup] = [
        VoiceGroup(title: "Apps & menus", symbol: "macwindow", commands: [
            VoiceCommand(say: ["switch to Claude", "open Finder"], does: "Brings any app forward, opening it if needed."),
            VoiceCommand(say: ["export as PDF", "click show sidebar"], does: "Any menu command of the app in front, by its name."),
            VoiceCommand(say: ["quit Safari"], does: "Quits an open app."),
            VoiceCommand(say: ["run shortcut Morning"], does: "Runs one of your Apple Shortcuts."),
        ]),
        VoiceGroup(title: "Keys", symbol: "keyboard", commands: [
            VoiceCommand(say: ["press enter", "press escape", "press tab"], does: "Presses that key."),
            VoiceCommand(say: ["press page down", "press home", "press F5"], does: "Arrows, home, end, page up and down, F1–F12, delete, forward delete, any letter or digit."),
            VoiceCommand(say: ["press command shift T", "control C"], does: "Shortcuts, with any of command, shift, option, control and fn. With a modifier, \u{201C}press\u{201D} is optional."),
            VoiceCommand(say: ["hold shift", "release"], does: "Keeps a modifier down while you click or press other keys, until \u{201C}release\u{201D} or \u{201C}let go\u{201D}."),
            VoiceCommand(say: ["press down 3 times"], does: "Add \u{201C}twice\u{201D} or \u{201C}3 times\u{201D} to repeat any key or action."),
        ]),
        VoiceGroup(title: "Typing", symbol: "character.cursor.ibeam", commands: [
            VoiceCommand(say: ["type see you at six", "say on my way"], does: "Types what you say into the text field you're in, exactly as heard."),
        ]),
        VoiceGroup(title: "Scroll & browse", symbol: "scroll", commands: [
            VoiceCommand(say: ["scroll down", "go back", "next tab"], does: "Any action in the gesture list, by name."),
            VoiceCommand(say: ["keep scrolling"], does: "Scrolls slowly until you say stop. Meanwhile just \u{201C}faster\u{201D}, \u{201C}slower\u{201D}, \u{201C}up\u{201D}, \u{201C}down\u{201D} or \u{201C}stop\u{201D}, no wake word."),
            VoiceCommand(say: ["open github.com", "google best ramen"], does: "A website, or a web search."),
            VoiceCommand(say: ["search for flights to Goa"], does: "Spotlight search."),
        ]),
        VoiceGroup(title: "Media & system", symbol: "speaker.wave.2", commands: [
            VoiceCommand(say: ["pause", "next track", "volume up"], does: "Media keys."),
            VoiceCommand(say: ["volume 30"], does: "Sets the volume, 0 to 100."),
            VoiceCommand(say: ["screenshot", "lock screen"], does: "Screenshots, Spotlight, lock screen and the rest of the gesture actions."),
        ]),
        VoiceGroup(title: "Sleight", symbol: "sparkles", commands: [
            VoiceCommand(say: ["stay"], does: "Conversation mode: then just say commands, no wake word, until \u{201C}done\u{201D}."),
            VoiceCommand(say: ["camera on", "camera off"], does: "Starts or stops the camera, and with it gestures."),
            VoiceCommand(say: ["rest", "wake up"], does: "Rests gestures and voice. While resting only \u{201C}wake up\u{201D} works."),
            VoiceCommand(say: ["pointer mode"], does: "Pointer mode, without the gesture."),
            VoiceCommand(say: ["never mind"], does: "Closes the listening chip without doing anything."),
        ]),
    ]

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
        case .scrollLeft: return "arrow.left"
        case .scrollRight: return "arrow.right"
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
