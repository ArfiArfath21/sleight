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
            ForEach(GestureCatalog.groups, id: \.self) { group in
                Section(group) {
                    ForEach(GestureCatalog.all.filter { $0.group == group }) { info in
                        GestureAssignmentRow(info: info, store: store)
                    }
                }
            }
            Section {
                Toggle("Show gesture hints", isOn: $store.showHints)
                Toggle("👌 needs the other three fingers up", isOn: $store.config.mediaNeedsOKSign)
                Toggle("Both hands up rests / wakes Sleight", isOn: $store.config.handsUpEnabled)
                HStack {
                    Spacer()
                    Button("Reset gestures to defaults") { store.config.gestures = GestureMap() }
                }
            }
            Section("Voice") {
                Toggle("Listen for \u{201C}hey Sleight\u{201D}", isOn: $store.config.voiceEnabled)
                Text("Keeps the microphone open (the orange dot stays on). Recognition runs on your Mac. ⌃⌥V speaks one command without the wake phrase, even with this off.")
                    .font(.caption).foregroundStyle(.secondary)
                Tunable("Wait for the command", value: $store.config.voiceListenWindow, range: 2...10, format: "%.0f s",
                        help: "After \u{201C}hey Sleight\u{201D} on its own.")
                Tunable("Pause that ends a command", value: $store.config.voiceSettle, range: 0.3...1.5, format: "%.1f s",
                        help: "Shorter is snappier; longer gives app names time to arrive.")
            }
            Section("Sensitivity") {
                Tunable("Swipe speed needed", value: $store.config.swipeMinSpeed, range: 2...10, format: "%.1f hand/s",
                        help: "Raise if swipes fire by accident; lower if they're hard to trigger.")
                Tunable("Flick speed needed", value: $store.config.flickMinSpeed, range: 1.5...8, format: "%.1f hand/s", help: nil)
                Tunable("Scroll distance per flick", value: $store.config.scrollFlickGain, range: 150...1200, format: "%.0f", help: nil)
                Tunable("Scroll glide", value: $store.config.momentumDecay, range: 0.1...1, format: "%.2f s",
                        help: "How long a flicked page keeps moving.")
                Tunable("Hold ☝️ to point", value: $store.config.pointHoldTime, range: 0.2...1.2, format: "%.2f s", help: nil)
                Tunable("Slide step (sideways)", value: $store.config.appStep, range: 0.2...1.0, format: "%.2f hand",
                        help: "How far a sideways slide travels per step (apps, tabs, desktops…).")
                Tunable("Slide step (up / down)", value: $store.config.volumeStep, range: 0.1...0.6, format: "%.2f hand", help: nil)
                Tunable("Clap speed needed", value: $store.config.clapApproachSpeed, range: 2...12, format: "%.1f hand/s",
                        help: "Only if a double clap is assigned.")
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

/// One gesture: what it is, and a menu of what it does. Reserved gestures
/// (which drive Sleight itself) are shown but can't be changed.
private struct GestureAssignmentRow: View {
    let info: GestureInfo
    @ObservedObject var store: ConfigStore

    var body: some View {
        if let g = info.gesture {
            Picker(selection: Binding(get: { store.config.gestures[g] },
                                      set: { store.config.gestures[g] = $0 })) {
                Text("Nothing").tag(ActionID.none)
                let choices = ActionID.choices(for: g.kind).filter { $0 != .none }
                ForEach(Self.groups(choices), id: \.self) { group in
                    Section(group) {
                        ForEach(choices.filter { $0.group == group }, id: \.self) { a in
                            Text(a.title).tag(a)
                        }
                    }
                }
            } label: {
                Text(info.title).help(info.how)
            }
        } else {
            LabeledContent {
                Text(info.effect(store.config.gestures)).foregroundStyle(.secondary)
            } label: {
                Text(info.title).help(info.how)
                Text("built in").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    static func groups(_ actions: [ActionID]) -> [String] {
        var seen: [String] = []
        for a in actions where !seen.contains(a.group) { seen.append(a.group) }
        return seen
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
