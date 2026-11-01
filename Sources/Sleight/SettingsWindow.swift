import SwiftUI
import AppKit
import SleightCore
import SleightBrand

/// Native preferences window: a toolbar of tabs, each a grouped form.
enum SettingsWindow {
    static func make(store: ConfigStore) -> NSWindow {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.transitionOptions = [.crossfade, .allowUserInteraction]
        for tab in SettingsTab.allCases {
            let host = NSHostingController(rootView: SettingsTabView(tab: tab, store: store))
            host.sizingOptions = .preferredContentSize
            let item = NSTabViewItem(viewController: host)
            item.label = tab.title
            item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.title)
            tabs.addTabViewItem(item)
        }
        let w = NSWindow(contentViewController: tabs)
        w.styleMask = [.titled, .closable, .miniaturizable]
        w.toolbarStyle = .preference
        w.isReleasedWhenClosed = false
        w.setFrameAutosaveName("SleightSettings")
        return w
    }
}

enum SettingsTab: String, CaseIterable {
    case general, gestures, voice, commands, pointer, tuning, about

    var title: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .gestures: return "hand.raised"
        case .voice: return "waveform"
        case .commands: return "text.bubble"
        case .pointer: return "cursorarrow.motionlines"
        case .tuning: return "slider.horizontal.3"
        case .about: return "info.circle"
        }
    }

    var height: CGFloat {
        switch self {
        case .general: return 560
        case .gestures: return 640
        case .voice: return 560
        case .commands: return 680
        case .pointer: return 560
        case .tuning: return 560
        case .about: return 380
        }
    }
}

struct SettingsTabView: View {
    let tab: SettingsTab
    @ObservedObject var store: ConfigStore

    var body: some View {
        Group {
            switch tab {
            case .general: GeneralSettings(store: store)
            case .gestures: GestureSettings(store: store)
            case .voice: VoiceSettings(store: store)
            case .commands: VoiceCommandsList(word: store.config.wakeWord)
            case .pointer: PointerSettings(store: store)
            case .tuning: TuningSettings(store: store)
            case .about: AboutSettings()
            }
        }
        .frame(width: 580, height: tab.height)
    }
}

// MARK: General

private struct GeneralSettings: View {
    @ObservedObject var store: ConfigStore

    var body: some View {
        Form {
            Section("Camera") {
                Toggle("Turn the camera on at launch", isOn: $store.config.cameraAtLaunch)
                Tunable("Turn it off after no hands for", value: $store.config.cameraIdleMinutes, range: 0...30,
                        format: "%.0f min", help: "Only while voice is on, so \u{201C}\(store.config.wakeWord.title), camera on\u{201D} brings it back. 0 = never.")
            }
            Section("On screen") {
                Toggle("Show gesture hints", isOn: $store.showHints)
                Toggle("Show live stats", isOn: $store.showStats)
            }
            Section("Keyboard shortcuts") {
                Shortcut("Rest / wake", "⌃⌥S")
                Shortcut("Pointer mode", "⌃⌥P")
                Shortcut("On-screen keyboard", "⌃⌥K")
                Shortcut("Speak one command", "⌃⌥V")
            }
            Section {
                HStack {
                    Button("Open config file") { NSWorkspace.shared.activateFileViewerSelecting([ConfigStore.fileURL]) }
                    Spacer()
                    Button("Reset everything to defaults", role: .destructive) { store.reset() }
                }
            }
        }
        .formStyle(.grouped)
    }

    private struct Shortcut: View {
        let title: String, keys: String
        init(_ title: String, _ keys: String) { self.title = title; self.keys = keys }
        var body: some View {
            LabeledContent(title) { Text(keys).font(.body.monospaced()).foregroundStyle(.secondary) }
        }
    }
}

// MARK: Gestures

private struct GestureSettings: View {
    @ObservedObject var store: ConfigStore

    var body: some View {
        Form {
            Section {
                Text("Choose what each gesture does. Gestures set to Nothing aren't even looked for, so they never get in the way. Hover a gesture's name for how to do it.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(GestureCatalog.groups, id: \.self) { group in
                Section(group) {
                    ForEach(GestureCatalog.all.filter { $0.group == group }) { info in
                        GestureAssignmentRow(info: info, store: store)
                    }
                }
            }
            Section("Options") {
                Toggle("Both hands up rests / wakes Sleight", isOn: $store.config.handsUpEnabled)
                Toggle("👌 needs the other three fingers up", isOn: $store.config.mediaNeedsOKSign)
            }
            Section {
                HStack {
                    Spacer()
                    Button("Reset gestures to defaults") { store.config.gestures = GestureMap() }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Voice

private struct VoiceSettings: View {
    @ObservedObject var store: ConfigStore

    private var word: WakeWord { store.config.wakeWord }

    var body: some View {
        Form {
            Section {
                Toggle("Voice commands", isOn: $store.config.voiceEnabled)
            }
            Section("Turning it on") {
                Picker("Double-tap to turn on / off", selection: $store.config.voiceDoubleTap) {
                    ForEach(DoubleTapKey.allCases, id: \.self) { k in Text(k.title).tag(k) }
                }
                Label("Turning voice on starts listening right away, so \u{201C}double-tap, switch to Finder\u{201D} works. After that, say \u{201C}\(word.phrase), …\u{201D}. While voice is on the microphone is open and macOS shows the orange dot; turn it off and the mic closes. (\u{201C}Hey Siri\u{201D} avoids the dot with a chip only Siri can use.)",
                      systemImage: "mic")
                    .font(.callout).foregroundStyle(.secondary)
                Picker("Wake word", selection: $store.config.wakeWord) {
                    ForEach(WakeWord.allCases, id: \.self) { w in Text(w.phrase).tag(w) }
                }
                LabeledContent("One command, voice off") { Text("⌃⌥V").font(.body.monospaced()).foregroundStyle(.secondary) }
            }
            Section("Timing") {
                Tunable("Wait for the command", value: $store.config.voiceListenWindow, range: 2...10, format: "%.0f s",
                        help: "After the wake word on its own, or after turning voice on.")
                Tunable("Pause that ends a command", value: $store.config.voiceSettle, range: 0.3...1.5, format: "%.1f s",
                        help: "Shorter is snappier; longer gives app names time to arrive.")
                Tunable("Conversation mode ends after", value: $store.config.voiceSessionMinutes, range: 0.5...10, format: "%.1f min",
                        help: "Of no commands. \u{201C}\(word.title), stay\u{201D} (or turning voice on) starts it; \u{201C}done\u{201D} ends it.")
                Tunable("Pause that ends dictation", value: $store.config.voiceDictationPause, range: 0.8...4, format: "%.1f s",
                        help: "For \u{201C}type …\u{201D}: how long a silence means you've finished.")
            }
            .disabled(!store.config.voiceEnabled)
            Section {
                Label("Recognition runs on your Mac. Nothing you say is sent anywhere.", systemImage: "lock")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Voice commands

/// Everything you can say, grouped, with a search box.
private struct VoiceCommandsList: View {
    let word: WakeWord
    @State private var query = ""

    var body: some View {
        Form {
            Section {
                VoiceHero(word: word)
                TextField("Search", text: $query, prompt: Text("Search, like \u{201C}tab\u{201D} or \u{201C}shift\u{201D}"))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
            }
            ForEach(groups) { group in
                Section {
                    ForEach(group.commands) { VoiceCommandRow(command: $0) }
                } header: {
                    Label(group.title, systemImage: group.symbol)
                        .foregroundStyle(Color.sleightAmber)
                }
            }
            if groups.isEmpty {
                Section { Text("No command matches \u{201C}\(query)\u{201D}.").foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped)
    }

    private var groups: [GestureCatalog.VoiceGroup] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return GestureCatalog.voiceGroups }
        return GestureCatalog.voiceGroups.compactMap { g in
            let hits = g.commands.filter { c in
                g.title.lowercased().contains(q) || c.does.lowercased().contains(q)
                    || c.say.contains { $0.lowercased().contains(q) }
            }
            return hits.isEmpty ? nil : GestureCatalog.VoiceGroup(title: g.title, symbol: g.symbol, commands: hits)
        }
    }
}

/// How a command is built: wake word, then the command. Shown once at the
/// top so the rows below can be just the commands.
private struct VoiceHero: View {
    let word: WakeWord

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "waveform").font(.title3).foregroundStyle(Color.sleightAmber)
                Text("\(word.phrase.capitalized),").font(.title3.weight(.semibold))
                PhraseChip(text: "next tab", prominent: true)
            }
            Text("Say the wake word, then any command below. Or press ⌃⌥V and just say the command, even with voice off.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }
}

/// One command: what to say as chips, what it does underneath.
private struct VoiceCommandRow: View {
    let command: GestureCatalog.VoiceCommand

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FlowLayout(spacing: 6) {
                ForEach(command.say, id: \.self) { PhraseChip(text: $0) }
            }
            Text(command.does).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 3)
    }
}

/// A phrase to say, set like a key cap in the brand's gold.
private struct PhraseChip: View {
    let text: String
    var prominent = false

    var body: some View {
        Text(text)
            .font(prominent ? .title3.weight(.semibold) : .callout.weight(.medium))
            .padding(.horizontal, prominent ? 10 : 8)
            .padding(.vertical, prominent ? 3 : 2)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.sleightAmber.opacity(prominent ? 0.18 : 0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.sleightAmber.opacity(0.45), lineWidth: 1)
            )
    }
}

extension Color {
    /// The brand gold, deepened in light mode so it reads on a pale background.
    static let sleightAmber = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(cgColor: Brand.gold)!
            : NSColor(srgbRed: 0.62, green: 0.40, blue: 0.02, alpha: 1)
    })
}

/// Lays chips out left to right, wrapping onto new lines.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for i in row.items {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var items: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].items.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                rows.append(Row())
            }
            var r = rows[rows.count - 1]
            r.width += (r.items.isEmpty ? 0 : spacing) + size.width
            r.height = max(r.height, size.height)
            r.items.append(i)
            rows[rows.count - 1] = r
        }
        return rows
    }
}

// MARK: Pointer

private struct PointerSettings: View {
    @ObservedObject var store: ConfigStore

    var body: some View {
        Form {
            Section("Movement") {
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
                Tunable("Hold ☝️ to point", value: $store.config.pointHoldTime, range: 0.2...1.2, format: "%.2f s", help: nil)
            }
            Section("Clicks") {
                Tunable("Drag deadzone", value: $store.config.dragDeadzone, range: 0...30, format: "%.0f pt", help: nil)
                Toggle("Middle-finger pinch = right click", isOn: $store.config.rightClickEnabled)
                Toggle("Back of hand exits", isOn: $store.config.flipExitEnabled)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Tuning

private struct TuningSettings: View {
    @ObservedObject var store: ConfigStore

    var body: some View {
        Form {
            Section("Flicks and swipes") {
                Tunable("Swipe speed needed", value: $store.config.swipeMinSpeed, range: 2...10, format: "%.1f hand/s",
                        help: "Raise if swipes fire by accident; lower if they're hard to trigger.")
                Tunable("Flick speed needed", value: $store.config.flickMinSpeed, range: 1.5...8, format: "%.1f hand/s", help: nil)
                Tunable("Scroll distance per flick", value: $store.config.scrollFlickGain, range: 150...1200, format: "%.0f", help: nil)
                Tunable("Scroll glide", value: $store.config.momentumDecay, range: 0.1...1, format: "%.2f s",
                        help: "How long a flicked page keeps moving.")
            }
            Section("Slides") {
                Tunable("Step sideways", value: $store.config.appStep, range: 0.2...1.0, format: "%.2f hand",
                        help: "How far a sideways slide travels per step (apps, tabs, desktops…).")
                Tunable("Step up / down", value: $store.config.volumeStep, range: 0.1...0.6, format: "%.2f hand", help: nil)
            }
            Section("Pinch and clap") {
                Tunable("Pinch closes below", value: $store.config.pinchClose, range: 0.1...0.4, format: "%.2f", help: nil)
                Tunable("Pinch opens above", value: $store.config.pinchOpen, range: 0.2...0.6, format: "%.2f",
                        help: "Thumb-to-finger distance in hand-lengths. The gap between the two prevents flicker.")
                Tunable("Clap speed needed", value: $store.config.clapApproachSpeed, range: 2...12, format: "%.1f hand/s",
                        help: "Only if a double clap is assigned.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: About

private struct AboutSettings: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(nsImage: Brand.appIconImage(size: 256)).resizable().frame(width: 112, height: 112)
            Text("Sleight").font(.system(size: 30, weight: .light))
            Text("Gestures that land.").foregroundStyle(.secondary)
            Text("Version \(version)").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Link("GitHub", destination: URL(string: "https://github.com/ArfiArfath21/sleight")!)
                Text("·").foregroundStyle(.secondary)
                Link("Support on Ko-fi", destination: URL(string: "https://ko-fi.com/arfiarfath21")!)
            }
            Spacer()
            Text("Camera and voice are processed on your Mac. Nothing leaves it.")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: Rows

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
