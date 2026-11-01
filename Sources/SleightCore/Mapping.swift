import Foundation

/// A gesture Sleight can recognise and the user can assign an action to.
/// Recognition is Sleight's job; what each gesture does is the user's choice.
public enum GestureID: String, Codable, CaseIterable, Sendable {
    // ✌️ two fingers, flicked
    case veeFlickUp, veeFlickDown, veeFlickLeft, veeFlickRight
    // ✋ open hand, swiped
    case openSwipeLeft, openSwipeRight, openSwipeUp, openSwipeDown
    // 👌 OK sign
    case okTap, okSlideVertical, okSlideSideways
    // ✊ fist, slid sideways
    case fistSlideSideways
    // two hands
    case curtains, frame, doubleClap

    public enum Kind: Sendable { case oneShot, slider }

    /// One-shot gestures take one-shot actions; sliders take step actions.
    public var kind: Kind {
        switch self {
        case .okSlideVertical, .okSlideSideways, .fistSlideSideways: return .slider
        default: return .oneShot
        }
    }
}

/// Gestures that drive Sleight itself and can't be reassigned.
public enum ReservedGesture: String, CaseIterable, Sendable {
    case handsUp      // both hands up, held: rest / wake
    case pointHold    // ☝️ held: pointer mode
    case fistHold     // ✊ held in pointer mode: leave it
}

/// Everything a gesture can be set to do.
public enum ActionID: String, Codable, CaseIterable, Sendable {
    case none
    // Scroll (with momentum: a harder flick scrolls further)
    case scrollDown, scrollUp, scrollLeft, scrollRight
    // Browse
    case back, forward, nextTab, previousTab, newTab, reopenTab
    // Windows & desktops
    case desktopLeft, desktopRight, missionControl, appWindows, showDesktop
    case previousApp, hideApp, minimize, fullScreen
    // Media
    case playPause, nextTrack, previousTrack, volumeUp, volumeDown, mute
    // View & keys
    case zoomIn, zoomOut, arrowLeft, arrowRight, arrowUp, arrowDown
    // Capture & system
    case screenshot, screenshotSelection, screenshotTool, spotlight, lockScreen
    // Edit, keys and more (one-shot keyboard shortcuts)
    case closeTab, newWindow, quitApp, undo, redo, cut, copy, paste, selectAll, save, find, reload, scrollToTop, scrollToBottom, returnKey, escapeKey, tabKey, spaceKey, deleteKey
    // Sleight
    case toggleKeyboard, restWake
    // Step actions, for sliders: one step per stretch of hand travel.
    case stepAppSwitcher, stepVolume, stepTabs, stepZoom, stepDesktops
    case stepArrowsHorizontal, stepArrowsVertical, stepBrightness

    public var isStep: Bool { rawValue.hasPrefix("step") }

    public var title: String {
        switch self {
        case .none: return "Nothing"
        case .scrollDown: return "Scroll down"
        case .scrollUp: return "Scroll up"
        case .scrollLeft: return "Scroll left"
        case .scrollRight: return "Scroll right"
        case .back: return "Back"
        case .forward: return "Forward"
        case .nextTab: return "Next tab"
        case .previousTab: return "Previous tab"
        case .newTab: return "New tab"
        case .reopenTab: return "Reopen closed tab"
        case .desktopLeft: return "Desktop to the left"
        case .desktopRight: return "Desktop to the right"
        case .missionControl: return "Mission Control"
        case .appWindows: return "App windows"
        case .showDesktop: return "Show desktop"
        case .previousApp: return "Previous app"
        case .hideApp: return "Hide app"
        case .minimize: return "Minimize window"
        case .fullScreen: return "Full screen"
        case .playPause: return "Play / Pause"
        case .nextTrack: return "Next track"
        case .previousTrack: return "Previous track"
        case .volumeUp: return "Volume up"
        case .volumeDown: return "Volume down"
        case .mute: return "Mute"
        case .zoomIn: return "Zoom in"
        case .zoomOut: return "Zoom out"
        case .arrowLeft: return "← key"
        case .arrowRight: return "→ key"
        case .arrowUp: return "↑ key"
        case .arrowDown: return "↓ key"
        case .screenshot: return "Screenshot"
        case .screenshotSelection: return "Screenshot of a selection"
        case .screenshotTool: return "Screenshot tool"
        case .spotlight: return "Spotlight"
        case .lockScreen: return "Lock screen"
        case .toggleKeyboard: return "On-screen keyboard"
        case .closeTab: return "Close tab / window"
        case .newWindow: return "New window"
        case .quitApp: return "Quit app"
        case .undo: return "Undo"
        case .redo: return "Redo"
        case .cut: return "Cut"
        case .copy: return "Copy"
        case .paste: return "Paste"
        case .selectAll: return "Select all"
        case .save: return "Save"
        case .find: return "Find"
        case .reload: return "Reload"
        case .scrollToTop: return "Scroll to top"
        case .scrollToBottom: return "Scroll to bottom"
        case .returnKey: return "Return key"
        case .escapeKey: return "Escape key"
        case .tabKey: return "Tab key"
        case .spaceKey: return "Space bar"
        case .deleteKey: return "Delete key"
        case .restWake: return "Rest / wake Sleight"
        case .stepAppSwitcher: return "App switcher"
        case .stepVolume: return "Volume"
        case .stepTabs: return "Tabs"
        case .stepZoom: return "Zoom"
        case .stepDesktops: return "Desktops"
        case .stepArrowsHorizontal: return "← → keys"
        case .stepArrowsVertical: return "↑ ↓ keys"
        case .stepBrightness: return "Brightness"
        }
    }

    public var group: String {
        switch self {
        case .none: return ""
        case .scrollDown, .scrollUp, .scrollLeft, .scrollRight: return "Scroll"
        case .back, .forward, .nextTab, .previousTab, .newTab, .reopenTab: return "Browse"
        case .desktopLeft, .desktopRight, .missionControl, .appWindows, .showDesktop,
             .previousApp, .hideApp, .minimize, .fullScreen: return "Windows"
        case .playPause, .nextTrack, .previousTrack, .volumeUp, .volumeDown, .mute: return "Media"
        case .zoomIn, .zoomOut, .arrowLeft, .arrowRight, .arrowUp, .arrowDown: return "View & keys"
        case .screenshot, .screenshotSelection, .screenshotTool, .spotlight, .lockScreen: return "System"
        case .toggleKeyboard, .restWake: return "Sleight"
        case .closeTab: return "Browse"
        case .newWindow: return "Windows"
        case .quitApp: return "Windows"
        case .undo: return "Edit"
        case .redo: return "Edit"
        case .cut: return "Edit"
        case .copy: return "Edit"
        case .paste: return "Edit"
        case .selectAll: return "Edit"
        case .save: return "Edit"
        case .find: return "Edit"
        case .reload: return "Browse"
        case .scrollToTop: return "Scroll"
        case .scrollToBottom: return "Scroll"
        case .returnKey: return "View & keys"
        case .escapeKey: return "View & keys"
        case .tabKey: return "View & keys"
        case .spaceKey: return "View & keys"
        case .deleteKey: return "View & keys"
        default: return "Slide to step"
        }
    }

    /// Actions available for a gesture of this kind.
    public static func choices(for kind: GestureID.Kind) -> [ActionID] {
        allCases.filter { $0 == .none || $0.isStep == (kind == .slider) }
    }
}

/// The user's gesture → action assignments. Missing entries fall back to the
/// defaults, so new gestures added later get sensible behaviour.
public struct GestureMap: Codable, Equatable, Sendable {
    public var assignments: [String: String]

    public init(assignments: [String: String] = [:]) { self.assignments = assignments }

    public static let defaults: [GestureID: ActionID] = [
        .veeFlickUp: .scrollDown,        // like the trackpad: the page follows the fingers
        .veeFlickDown: .scrollUp,
        .veeFlickRight: .back,
        .veeFlickLeft: .forward,
        .openSwipeRight: .desktopLeft,
        .openSwipeLeft: .desktopRight,
        .openSwipeUp: .missionControl,
        .openSwipeDown: .none,
        .okTap: .none,
        .okSlideVertical: .none,
        .okSlideSideways: .none,
        .fistSlideSideways: .stepAppSwitcher,
        .curtains: .showDesktop,
        .frame: .screenshot,
        .doubleClap: .none,
    ]

    public subscript(_ g: GestureID) -> ActionID {
        get {
            if let raw = assignments[g.rawValue], let a = ActionID(rawValue: raw),
               a == .none || a.isStep == (g.kind == .slider) { return a }
            return Self.defaults[g] ?? .none
        }
        set { assignments[g.rawValue] = newValue.rawValue }
    }

    public func isAssigned(_ g: GestureID) -> Bool { self[g] != .none }
}

/// Turns chosen actions into OS actions.
public enum ActionMapper {
    /// A one-shot action. `speed` (hand lengths per second) scales scrolling.
    public static func fire(_ a: ActionID, speed: Double?, config: SleightConfig) -> [EngineAction] {
        func scroll(_ sign: Double, horizontal: Bool = false) -> [EngineAction] {
            let s = speed ?? 4
            let mag = clamp(s * config.scrollFlickGain, config.scrollFlickMin, config.scrollFlickMax)
            // Wheel axes: negative = content moves up / left (reveals what's below / to the right).
            return [.scrollFlick(velocity: horizontal ? Vec2(sign * mag, 0) : Vec2(0, sign * mag))]
        }
        switch a {
        case .none: return []
        case .scrollDown: return scroll(-1)
        case .scrollUp: return scroll(1)
        case .scrollLeft: return scroll(1, horizontal: true)
        case .scrollRight: return scroll(-1, horizontal: true)
        case .back: return [.shortcut(.back)]
        case .forward: return [.shortcut(.forward)]
        case .nextTab: return [.shortcut(.nextTab)]
        case .previousTab: return [.shortcut(.previousTab)]
        case .newTab: return [.shortcut(.newTab)]
        case .reopenTab: return [.shortcut(.reopenTab)]
        case .desktopLeft: return [.shortcut(.spaceLeft)]
        case .desktopRight: return [.shortcut(.spaceRight)]
        case .missionControl: return [.shortcut(.missionControl)]
        case .appWindows: return [.shortcut(.appExpose)]
        case .showDesktop: return [.shortcut(.showDesktop)]
        case .previousApp: return [.switcher(.begin), .switcher(.commit)]
        case .hideApp: return [.shortcut(.hideApp)]
        case .minimize: return [.shortcut(.minimize)]
        case .fullScreen: return [.shortcut(.fullScreen)]
        case .playPause: return [.media(.playPause)]
        case .nextTrack: return [.media(.next)]
        case .previousTrack: return [.media(.previous)]
        case .volumeUp: return [.media(.volumeUp)]
        case .volumeDown: return [.media(.volumeDown)]
        case .mute: return [.media(.mute)]
        case .zoomIn: return [.shortcut(.zoomIn)]
        case .zoomOut: return [.shortcut(.zoomOut)]
        case .arrowLeft: return [.shortcut(.arrowLeft)]
        case .arrowRight: return [.shortcut(.arrowRight)]
        case .arrowUp: return [.shortcut(.arrowUp)]
        case .arrowDown: return [.shortcut(.arrowDown)]
        case .screenshot: return [.shortcut(.screenshot)]
        case .screenshotSelection: return [.shortcut(.screenshotSelection)]
        case .screenshotTool: return [.shortcut(.screenshotTool)]
        case .spotlight: return [.shortcut(.spotlight)]
        case .lockScreen: return [.shortcut(.lockScreen)]
        case .toggleKeyboard: return [.toggleKeyboard]
        case .closeTab, .newWindow, .quitApp, .undo, .redo, .cut, .copy, .paste, .selectAll, .save, .find, .reload, .scrollToTop, .scrollToBottom, .returnKey, .escapeKey, .tabKey, .spaceKey, .deleteKey:
            return Shortcut(rawValue: a.rawValue).map { [.shortcut($0)] } ?? []
        case .restWake: return []   // handled by the engine (it owns active/resting)
        case .stepAppSwitcher, .stepVolume, .stepTabs, .stepZoom, .stepDesktops,
             .stepArrowsHorizontal, .stepArrowsVertical, .stepBrightness:
            return step(a, forward: true)
        }
    }

    /// Start of a slide. The app switcher holds ⌘ until `end`.
    public static func begin(_ a: ActionID, forward: Bool) -> [EngineAction] {
        a == .stepAppSwitcher ? [.switcher(.begin)] : step(a, forward: forward)
    }

    /// One step. Forward = right (horizontal sliders) or up (vertical sliders).
    public static func step(_ a: ActionID, forward: Bool) -> [EngineAction] {
        switch a {
        case .stepAppSwitcher: return [.switcher(forward ? .next : .previous)]
        case .stepVolume: return [.media(forward ? .volumeUp : .volumeDown)]
        case .stepTabs: return [.shortcut(forward ? .nextTab : .previousTab)]
        case .stepZoom: return [.shortcut(forward ? .zoomIn : .zoomOut)]
        case .stepDesktops: return [.shortcut(forward ? .spaceRight : .spaceLeft)]
        case .stepArrowsHorizontal: return [.shortcut(forward ? .arrowRight : .arrowLeft)]
        case .stepArrowsVertical: return [.shortcut(forward ? .arrowUp : .arrowDown)]
        case .stepBrightness: return [.media(forward ? .brightnessUp : .brightnessDown)]
        default: return []
        }
    }

    /// End of a slide: let go of anything held.
    public static func end(_ a: ActionID, cancelled: Bool) -> [EngineAction] {
        guard a == .stepAppSwitcher else { return [] }
        return [.switcher(cancelled ? .cancel : .commit)]
    }
}
