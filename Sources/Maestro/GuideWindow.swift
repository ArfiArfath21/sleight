import SwiftUI
import AppKit
import MaestroBrand

enum GuideWindow {
    static func make() -> NSWindow {
        let host = NSHostingController(rootView: GuideView())
        let w = NSWindow(contentViewController: host)
        w.title = "Maestro Gestures"
        w.styleMask = [.titled, .closable, .fullSizeContentView]
        w.titlebarAppearsTransparent = true
        w.isReleasedWhenClosed = false
        return w
    }
}

struct GuideView: View {
    private let rows: [(String, String, String)] = [
        ("hand.raised", "Engage", "Raise an open palm toward the screen and hold still for a moment. A gold ring fills, then the cursor is yours."),
        ("hand.point.up.left", "Point", "Move your hand. Slow movements get finer (the ring shrinks and turns violet); fast moves cover the screen."),
        ("hand.pinch", "Click · drag", "Pinch thumb and index. Pinch twice for a double-click. Pinch, hold and move to drag."),
        ("hand.pinch.fill", "Right click", "Pinch thumb and middle finger."),
        ("hand.raised.fingers.spread", "Swipe", "Flick an open palm left or right to switch Spaces, or up for Mission Control."),
        ("hand.wave", "Scroll", "Make a fist and move it, like grabbing the page. Let go mid-move to coast."),
        ("keyboard", "Keyboard", "Hold a peace sign ✌︎ to bring up the on-screen keyboard, and again to hide it."),
        ("hand.raised.slash", "Rest", "Drop your hand, turn its back to the camera, or just start typing. Maestro steps aside."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: Brand.appIconImage(size: 64)).resizable().frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Maestro").font(.system(size: 26, weight: .semibold, design: .rounded))
                    Text("Conduct your Mac with one hand.").foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 4)
            ForEach(rows, id: \.1) { icon, title, text in
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .medium))
                        .frame(width: 32, height: 28)
                        .foregroundStyle(Color(cgColor: Brand.violet))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.headline)
                        Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Divider()
            Text("⌃⌥M turns hand control on and off. For best results: light on your face, hand at shoulder height, 40–70 cm from the camera.")
                .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(28)
        .frame(width: 500)
    }
}
