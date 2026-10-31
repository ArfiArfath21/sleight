import SwiftUI
import AppKit
import SleightBrand

enum GuideWindow {
    static func make(onPractice: (() -> Void)? = nil) -> NSWindow {
        let host = NSHostingController(rootView: GuideView(onPractice: onPractice))
        let w = NSWindow(contentViewController: host)
        w.title = "Sleight"
        w.styleMask = [.titled, .closable, .fullSizeContentView]
        w.titlebarAppearsTransparent = true
        w.isReleasedWhenClosed = false
        return w
    }
}

struct GuideView: View {
    var onPractice: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(nsImage: Brand.appIconImage(size: 128)).resizable().frame(width: 60, height: 60)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sleight").font(.system(size: 28, weight: .light))
                    Text("Gestures that land.").foregroundStyle(.secondary)
                }
                Spacer()
                if let onPractice {
                    Button("Practice with the camera…") { onPractice() }
                        .controlSize(.large)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(GestureCatalog.groups, id: \.self) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(Color(cgColor: Brand.gold))
                            ForEach(GestureCatalog.all.filter { $0.group == group }) { g in
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(g.title).font(.headline)
                                        Spacer()
                                        Text(g.effect).font(.headline).foregroundStyle(Color(cgColor: Brand.gold))
                                    }
                                    Text(g.how).font(.callout).foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
            }
            Divider()
            Text("Gestures are about the motion, not where your hand is, but your hand has to be in the camera's view: chest to face height works best. Typing or touching the trackpad pauses everything for a second.")
                .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("⌃⌥S rest / wake · ⌃⌥P pointer mode · ⌃⌥K keyboard")
                .font(.footnote.monospaced()).foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(width: 600, height: 760)
    }
}
