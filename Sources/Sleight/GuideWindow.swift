import SwiftUI
import AppKit
import SleightBrand
import SleightCore

enum GuideWindow {
    static func make(map: GestureMap, wakeWord: WakeWord = .jarvis, onPractice: (() -> Void)? = nil) -> NSWindow {
        let host = NSHostingController(rootView: GuideView(onPractice: onPractice, map: map, wakeWord: wakeWord))
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
    var map = GestureMap()
    var wakeWord = WakeWord.jarvis

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
                                        if g.gesture == nil { Text("built in").font(.caption).foregroundStyle(.secondary) }
                                        Spacer()
                                        Text(g.effect(map)).font(.headline)
                                            .foregroundStyle(g.effect(map) == "Nothing" ? Color.secondary : Color(cgColor: Brand.gold))
                                    }
                                    Text(g.how).font(.callout).foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("🎙  VOICE").font(.caption.weight(.semibold)).foregroundStyle(Color(cgColor: Brand.gold))
                        Text("Say \u{201C}\(wakeWord.phrase.capitalized), …\u{201D} then a command, or press ⌃⌥V and just say it.")
                            .font(.callout).foregroundStyle(.secondary)
                        ForEach(GestureCatalog.voiceGroups) { group in
                            VStack(alignment: .leading, spacing: 3) {
                                Label(group.title, systemImage: group.symbol).font(.headline)
                                ForEach(group.commands) { c in
                                    Text(c.say.map { "\u{201C}\($0)\u{201D}" }.joined(separator: "  ·  ") + "  —  " + c.does)
                                        .font(.callout).foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        Text("Turn voice on from the menu bar. Recognition runs on your Mac; nothing is sent anywhere.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            Divider()
            Text("Change what any gesture does in Settings. Gestures set to Nothing aren't even looked for, so they never get in the way. Your hand has to be in the camera's view: chest to face height works best. Typing or touching the trackpad pauses everything for a second.")
                .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("⌃⌥S rest / wake · ⌃⌥P pointer mode · ⌃⌥K keyboard · ⌃⌥V speak")
                .font(.footnote.monospaced()).foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(width: 600, height: 760)
    }
}
