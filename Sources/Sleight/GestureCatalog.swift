import Foundation
import SleightCore

/// Every gesture, explained in plain words. One source for the Guide and the
/// Practice window, and the mapping from engine actions back to gestures.
struct GestureInfo: Identifiable, Equatable {
    let id: String
    let group: String
    let title: String
    let effect: String
    let how: String
}

enum GestureCatalog {
    static let all: [GestureInfo] = [
        GestureInfo(id: "flickUp", group: "Reading", title: "✌️  Flick up", effect: "Scroll down the page",
                    how: "Make a peace sign (index and middle finger up, the others folded), palm facing the screen. Snap it upward about a hand's length, quick, like flicking water off your fingers. Bring it back down slowly. Flick again to keep going."),
        GestureInfo(id: "flickDown", group: "Reading", title: "✌️  Flick down", effect: "Scroll back up",
                    how: "Same peace sign, snap it downward. Bring it back up slowly."),
        GestureInfo(id: "flickSide", group: "Reading", title: "✌️  Flick sideways", effect: "Back · Forward",
                    how: "Peace sign, snap it to the right to go back, to the left to go forward."),
        GestureInfo(id: "swipeSide", group: "Windows", title: "✋  Swipe sideways", effect: "Switch desktop",
                    how: "Open hand, palm facing the screen. Sweep it quickly left or right across your body, like pushing a page aside."),
        GestureInfo(id: "swipeUp", group: "Windows", title: "✋  Swipe up", effect: "Mission Control",
                    how: "Open hand, palm facing the screen. Sweep it quickly upward."),
        GestureInfo(id: "grab", group: "Windows", title: "✊  Grab and slide", effect: "Switch app",
                    how: "Close your hand into a fist and pause for a beat. Slide the fist sideways: the app switcher opens and moves along as you slide. Open your hand to switch to the highlighted app."),
        GestureInfo(id: "tap", group: "Media", title: "👌  Tap", effect: "Play · Pause",
                    how: "OK sign: touch your thumb and index fingertips while the other three fingers stay up. Start with the fingers apart, pinch, then let go quickly."),
        GestureInfo(id: "volume", group: "Media", title: "👌  Hold, slide up / down", effect: "Volume",
                    how: "Make the OK sign and hold it still for a moment. Then slide your hand up for louder, down for quieter. Let go when done."),
        GestureInfo(id: "track", group: "Media", title: "👌  Hold, slide sideways", effect: "Next · Previous track",
                    how: "Make the OK sign and hold it still for a moment, then slide right for the next track, left for the previous."),
        GestureInfo(id: "handsUp", group: "Both hands", title: "🙌  Both hands up, hold", effect: "Rest · Wake Sleight",
                    how: "Raise both hands open, palms to the screen, about shoulder-width apart, as if saying \"hold on\". Keep them still for a second until the ring fills. Resting, Sleight keeps watching but only this gesture wakes it."),
        GestureInfo(id: "curtains", group: "Both hands", title: "🖐🖐  Part the curtains", effect: "Show desktop",
                    how: "Bring both open hands together in front of you, palms to the screen, side by side and almost touching. Wait for \"Part the curtains\" to appear (a moment), then sweep them apart sideways, fast."),
        GestureInfo(id: "frame", group: "Both hands", title: "🫲🫱  Frame it", effect: "Screenshot",
                    how: "Make an L with each hand: index finger up, thumb sticking out sideways, other fingers folded. Hold your hands apart like framing a photo and keep still for half a second."),
        GestureInfo(id: "point", group: "Pointer", title: "☝️  Point and hold", effect: "Pointer mode",
                    how: "Point your index finger up with the other fingers folded. Hold still for half a second. Then move your hand to move the cursor, pinch to click."),
        GestureInfo(id: "exitPointer", group: "Pointer", title: "✊  Fist", effect: "Leave pointer mode",
                    how: "While in pointer mode, close your hand into a fist and hold it for a moment."),
    ]

    static var groups: [String] {
        var seen: [String] = []
        for g in all.map(\.group) where !seen.contains(g) { seen.append(g) }
        return seen
    }

    /// Which gesture produced an action (for the Practice window).
    static func gestureID(for action: EngineAction, natural: Bool) -> String? {
        switch action {
        case .scrollFlick(let v): return (v.y < 0) == natural ? "flickUp" : "flickDown"
        case .shortcut(let s):
            switch s {
            case .back, .forward: return "flickSide"
            case .spaceLeft, .spaceRight: return "swipeSide"
            case .missionControl, .appExpose: return "swipeUp"
            case .showDesktop: return "curtains"
            case .screenshot: return "frame"
            }
        case .switcher(.begin): return "grab"
        case .media(let m):
            switch m {
            case .playPause: return "tap"
            case .volumeUp, .volumeDown: return "volume"
            case .next, .previous: return "track"
            }
        case .activeChanged: return "handsUp"
        case .modeChanged(.pointer, _): return "point"
        case .modeChanged(.command, .gesture): return "exitPointer"
        default: return nil
        }
    }
}
