import SwiftUI
import AppKit
import MaestroCore

enum SettingsWindow {
    static func make(store: ConfigStore) -> NSWindow {
        let host = NSHostingController(rootView: SettingsView(store: store))
        let w = NSWindow(contentViewController: host)
        w.title = "Maestro Settings"
        w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        w.setContentSize(NSSize(width: 520, height: 680))
        w.isReleasedWhenClosed = false
        return w
    }
}

struct SettingsView: View {
    @ObservedObject var store: ConfigStore

    var body: some View {
        Form {
            Section("Pointer") {
                Picker("Mapping", selection: $store.config.mappingMode) {
                    Text("Relative (like a trackpad)").tag(MappingMode.relative)
                    Text("Absolute (camera box = screen)").tag(MappingMode.absolute)
                }
                Tunable("Slow speed", value: $store.config.slowGain, range: 50...600, format: "%.0f pt/hand",
                        help: "Cursor travel per hand-length when moving slowly.")
                Tunable("Fast speed", value: $store.config.fastGain, range: 400...4000, format: "%.0f pt/hand",
                        help: "Cursor travel per hand-length when flinging.")
                Tunable("Precision strength", value: $store.config.precisionFactor, range: 0.15...1, format: "%.2f×",
                        help: "When you slow right down the pointer gets this much finer. 1 = off.")
                Tunable("Edge glide speed", value: $store.config.edgeGlideSpeed, range: 0...2000, format: "%.0f pt/s",
                        help: "Keeps the cursor moving when your hand reaches the edge of the camera view.")
            }
            Section("Smoothing (jitter vs. lag)") {
                Tunable("Steadiness", value: $store.config.filterMinCutoff, range: 0.3...6, format: "%.1f Hz",
                        help: "Lower = steadier at rest, slightly more lag when moving slowly.")
                Tunable("Responsiveness", value: $store.config.filterBeta, range: 0...0.05, format: "%.3f",
                        help: "Higher = less lag on fast moves.")
                Toggle("Glide between camera frames", isOn: $store.config.glideEnabled)
            }
            Section("Pinch & click") {
                Tunable("Pinch closes below", value: $store.config.pinchClose, range: 0.1...0.4, format: "%.2f",
                        help: "Thumb-to-finger distance in hand-lengths.")
                Tunable("Pinch opens above", value: $store.config.pinchOpen, range: 0.2...0.6, format: "%.2f",
                        help: "Must be larger than 'closes below'. The gap prevents flicker.")
                Tunable("Drag deadzone", value: $store.config.dragDeadzone, range: 0...30, format: "%.0f pt",
                        help: "While pinched, the cursor holds still until you move this far.")
                Toggle("Middle-finger pinch = right click", isOn: $store.config.rightClickEnabled)
            }
            Section("Scroll (fist)") {
                Toggle("Fist scrolling", isOn: $store.config.scrollEnabled)
                Toggle("Natural (grab the page)", isOn: $store.config.scrollNatural)
                Tunable("Scroll speed", value: $store.config.scrollGain, range: 200...4000, format: "%.0f pt/hand", help: nil)
                Tunable("Momentum", value: $store.config.momentumDecay, range: 0.05...1, format: "%.2f s", help: nil)
            }
            Section("Swipes (flick an open palm)") {
                Toggle("Swipe left/right for Spaces", isOn: $store.config.swipesEnabled)
                Toggle("Swipe up for Mission Control", isOn: $store.config.swipeUpEnabled)
                Tunable("Flick speed needed", value: $store.config.swipeMinSpeed, range: 3...15, format: "%.1f hand/s",
                        help: "Raise if normal pointing ever triggers a swipe.")
            }
            Section("Engagement") {
                Tunable("Hold open palm for", value: $store.config.armTime, range: 0.1...1.0, format: "%.2f s", help: nil)
                Tunable("Lost-tracking grace", value: $store.config.lostGrace, range: 0.05...0.6, format: "%.2f s", help: nil)
                Toggle("Back of hand disengages", isOn: $store.config.flipDisengageEnabled)
                Toggle("Hold ✌︎ to toggle keyboard", isOn: $store.config.keyboardGestureEnabled)
                Picker("Preferred hand", selection: $store.config.preferredHand) {
                    Text("Right").tag(Chirality.right)
                    Text("Left").tag(Chirality.left)
                    Text("Either").tag(Chirality.unknown)
                }
            }
            Section {
                HStack {
                    Button("Reset to defaults") { store.reset() }
                    Spacer()
                    Button("Open config file") { NSWorkspace.shared.activateFileViewerSelecting([ConfigStore.fileURL]) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, minHeight: 500)
    }
}

private struct Tunable: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String
    let help: String?

    init(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, format: String, help: String?) {
        self.title = title
        self._value = value
        self.range = range
        self.format = format
        self.help = help
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: format, value)).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range)
            if let help { Text(help).font(.caption).foregroundStyle(.secondary) }
        }
    }
}
