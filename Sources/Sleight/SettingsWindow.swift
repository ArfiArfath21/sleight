import SwiftUI
import AppKit
import SleightCore

enum SettingsWindow {
    static func make(store: ConfigStore) -> NSWindow {
        let host = NSHostingController(rootView: SettingsView(store: store))
        let w = NSWindow(contentViewController: host)
        w.title = "Sleight Settings"
        w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        w.setContentSize(NSSize(width: 520, height: 700))
        w.isReleasedWhenClosed = false
        return w
    }
}

struct SettingsView: View {
    @ObservedObject var store: ConfigStore

    var body: some View {
        Form {
            Section("Everyday gestures") {
                Toggle("✌️ Flick sideways for back / forward", isOn: $store.config.backForwardEnabled)
                Toggle("✋ Swipe left/right for desktops, up for Mission Control", isOn: $store.config.swipesEnabled)
                Toggle("✋ Swipe down for app windows (Exposé)", isOn: $store.config.swipeDownEnabled)
                Toggle("✊ Grab and slide to switch apps", isOn: $store.config.grabEnabled)
                Toggle("👌 Media needs an OK sign (other fingers up)", isOn: $store.config.mediaNeedsOKSign)
                Toggle("🤏 Slide sideways to skip tracks", isOn: $store.config.trackSkipEnabled)
                Toggle("Natural scrolling", isOn: $store.config.scrollNatural)
                Toggle("Show gesture hints", isOn: $store.showHints)
            }
            Section("Two hands") {
                Toggle("🙌 Both hands up, held, to rest / wake", isOn: $store.config.handsUpEnabled)
                Toggle("👏👏 Double clap to rest / wake (experimental: the camera misses many claps)", isOn: $store.config.clapEnabled)
                Toggle("🖐🖐 Part the curtains to show the desktop", isOn: $store.config.curtainsEnabled)
                Toggle("Frame with both hands to take a screenshot", isOn: $store.config.frameEnabled)
                Tunable("Clap speed needed", value: $store.config.clapApproachSpeed, range: 2...12, format: "%.1f hand/s",
                        help: "Lower if claps are missed; raise if they fire by accident.")
            }
            Section("Sensitivity") {
                Tunable("Swipe speed needed", value: $store.config.swipeMinSpeed, range: 2...10, format: "%.1f hand/s",
                        help: "Raise if swipes fire by accident; lower if they're hard to trigger.")
                Tunable("Flick speed needed", value: $store.config.flickMinSpeed, range: 1.5...8, format: "%.1f hand/s", help: nil)
                Tunable("Scroll distance per flick", value: $store.config.scrollFlickGain, range: 150...1200, format: "%.0f", help: nil)
                Tunable("Scroll glide", value: $store.config.momentumDecay, range: 0.1...1, format: "%.2f s",
                        help: "How long a flicked page keeps moving.")
                Tunable("Hold ☝️ to point", value: $store.config.pointHoldTime, range: 0.2...1.2, format: "%.2f s", help: nil)
                Tunable("Apps per hand-length", value: $store.config.appStep, range: 0.2...1.0, format: "%.2f",
                        help: "Pinch-and-slide distance per app in the switcher.")
            }
            Section("Pointer mode") {
                Picker("Mapping", selection: $store.config.mappingMode) {
                    Text("Relative (like a trackpad)").tag(MappingMode.relative)
                    Text("Absolute (camera box = screen)").tag(MappingMode.absolute)
                }
                Tunable("Slow speed", value: $store.config.slowGain, range: 50...600, format: "%.0f pt/hand", help: nil)
                Tunable("Fast speed", value: $store.config.fastGain, range: 400...4000, format: "%.0f pt/hand", help: nil)
                Tunable("Precision strength", value: $store.config.precisionFactor, range: 0.15...1, format: "%.2f×",
                        help: "When you nearly stop, the pointer gets this much finer. 1 = off.")
                Tunable("Steadiness", value: $store.config.filterMinCutoff, range: 0.3...6, format: "%.1f Hz",
                        help: "Lower = steadier when still, a touch more lag when moving slowly.")
                Tunable("Drag deadzone", value: $store.config.dragDeadzone, range: 0...30, format: "%.0f pt", help: nil)
                Toggle("Middle-finger pinch = right click", isOn: $store.config.rightClickEnabled)
                Toggle("Back of hand exits", isOn: $store.config.flipExitEnabled)
            }
            Section("Pinch") {
                Tunable("Closes below", value: $store.config.pinchClose, range: 0.1...0.4, format: "%.2f", help: nil)
                Tunable("Opens above", value: $store.config.pinchOpen, range: 0.2...0.6, format: "%.2f",
                        help: "Thumb-to-finger distance in hand-lengths. The gap between the two prevents flicker.")
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
