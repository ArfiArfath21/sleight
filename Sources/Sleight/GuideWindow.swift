import SwiftUI
import AppKit
import SleightBrand

enum GuideWindow {
    static func make() -> NSWindow {
        let host = NSHostingController(rootView: GuideView())
        let w = NSWindow(contentViewController: host)
        w.title = "Sleight"
        w.styleMask = [.titled, .closable, .fullSizeContentView]
        w.titlebarAppearsTransparent = true
        w.isReleasedWhenClosed = false
        return w
    }
}

struct GuideView: View {
    struct Row: Identifiable {
        var id: String { action }
        var hand: String
        var gesture: String
        var action: String
    }

    private let everyday: [Row] = [
        Row(hand: "✌️", gesture: "Two fingers, flick up / down", action: "Scroll"),
        Row(hand: "✌️", gesture: "Two fingers, flick right / left", action: "Back · Forward"),
        Row(hand: "✋", gesture: "Open hand, swipe right / left", action: "Switch desktop"),
        Row(hand: "✋", gesture: "Open hand, swipe up", action: "Mission Control"),
        Row(hand: "🤏", gesture: "Pinch and let go", action: "Play · Pause"),
        Row(hand: "🤏", gesture: "Pinch, slide sideways, let go", action: "Switch app"),
        Row(hand: "🤏", gesture: "Pinch, slide up / down", action: "Volume"),
        Row(hand: "👐", gesture: "Both hands, spread / squeeze", action: "Zoom in · out"),
    ]

    private let pointer: [Row] = [
        Row(hand: "☝️", gesture: "Point and hold", action: "Pointer mode"),
        Row(hand: "🤏", gesture: "Pinch (twice = double-click, hold = drag)", action: "Click"),
        Row(hand: "🤌", gesture: "Thumb + middle finger", action: "Right click"),
        Row(hand: "✊", gesture: "Hold a fist", action: "Back to gestures"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(nsImage: Brand.appIconImage(size: 128)).resizable().frame(width: 60, height: 60)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sleight").font(.system(size: 28, weight: .semibold, design: .rounded))
                    Text("Wave. Flick. Pinch. Your Mac follows.").foregroundStyle(.secondary)
                }
            }
            section("Everyday", everyday)
            section("Pointer mode, when you need to aim", pointer)
            Divider()
            Text("Gestures are about the motion, not where your hand is: raise a hand anywhere in view. Typing or touching the trackpad pauses everything for a second. A chip at the top of the screen always shows what your hand is about to do.")
                .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("⌃⌥S on/off · ⌃⌥P pointer mode · ⌃⌥K keyboard")
                .font(.footnote.monospaced()).foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(width: 520)
    }

    private func section(_ title: String, _ rows: [Row]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(Color(cgColor: Brand.cyan))
            ForEach(rows) { r in
                HStack(spacing: 12) {
                    Text(r.hand).font(.system(size: 22)).frame(width: 32)
                    Text(r.gesture).foregroundStyle(.secondary)
                    Spacer()
                    Text(r.action).font(.headline)
                }
            }
        }
    }
}
