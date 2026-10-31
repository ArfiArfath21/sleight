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

    private let reading: [Row] = [
        Row(hand: "✌️", gesture: "Two fingers, flick up / down", action: "Scroll"),
        Row(hand: "✌️", gesture: "Two fingers, flick right / left", action: "Back · Forward"),
    ]

    private let windows: [Row] = [
        Row(hand: "✋", gesture: "Open hand, swipe right / left", action: "Switch desktop"),
        Row(hand: "✋", gesture: "Open hand, swipe up", action: "Mission Control"),
        Row(hand: "✊", gesture: "Grab, slide sideways, open hand", action: "Switch app"),
    ]

    private let media: [Row] = [
        Row(hand: "🤏", gesture: "Pinch and let go", action: "Play · Pause"),
        Row(hand: "🤏", gesture: "Pinch, slide up / down", action: "Volume"),
        Row(hand: "🤏", gesture: "Pinch, slide right / left", action: "Next · Previous"),
    ]

    private let twoHands: [Row] = [
        Row(hand: "👏", gesture: "Clap twice", action: "Rest · Wake"),
        Row(hand: "🖐", gesture: "Hands together, part the curtains", action: "Show desktop"),
        Row(hand: "📸", gesture: "Frame with both hands (L shapes)", action: "Screenshot"),
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
                    Text("Gestures that land.").foregroundStyle(.secondary)
                }
            }
            section("Reading", reading)
            section("Windows", windows)
            section("Media", media)
            section("Both hands", twoHands)
            section("Pointer mode, when you need to aim", pointer)
            Divider()
            Text("Gestures are about the motion, not where your hand is: raise a hand anywhere in view. Clap twice to let Sleight rest while it keeps watching; clap twice to wake it. Typing or touching the trackpad pauses everything for a second. Clicking into a text field in pointer mode brings up the keyboard.")
                .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("⌃⌥S rest / wake · ⌃⌥P pointer mode · ⌃⌥K keyboard")
                .font(.footnote.monospaced()).foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(width: 520)
    }

    private func section(_ title: String, _ rows: [Row]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(Color(cgColor: Brand.gold))
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
