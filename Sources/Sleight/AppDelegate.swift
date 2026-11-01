import AppKit
import AVFoundation
import Carbon.HIToolbox
import Combine
import SleightCore
import SleightBrand

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let store = ConfigStore()
    let pipeline = Pipeline()
    let voice = VoiceListener()
    private let menus = MenuIndex()
    private var idleTimer: Timer?
    private var subscriptions = Set<AnyCancellable>()
    /// Continuous scrolling: speed level and direction.
    private static let scrollSpeeds: [Double] = [25, 40, 60, 90, 135, 200, 300, 450]
    private var scrollLevel = 2
    private var scrollingUp = false
    private var autoScrolling = false
    private var scrollChip: Chip?
    private var sessionChip: Chip?
    private var lastHandSeen = CACurrentMediaTime()
    private var voiceItem = NSMenuItem()
    private(set) var overlay: Overlay!
    private var statusItem: NSStatusItem!
    private var hotKeys: [HotKey] = []
    private var statusLine = NSMenuItem()
    private var qualityLine = NSMenuItem()
    private var enableItem = NSMenuItem()
    private var activeItem = NSMenuItem()
    private var gesturesActive = true
    private var pointerItem = NSMenuItem()
    private var statsItem = NSMenuItem()
    private var hintsItem = NSMenuItem()
    private var menuTimer: Timer?
    private var mode: Mode = .command
    private(set) var enabled = false

    lazy var keyboard = KeyboardPanelController(injector: pipeline.injector, monitor: pipeline.inputMonitor)
    private let modeBar = ModeBar()
    private var settingsWindow: NSWindow?
    private var previewWindow: PreviewWindowController?
    private var guideWindow: NSWindow?
    private var practice: PracticeWindowController?

    let launchOptions: LaunchOptions

    init(options: LaunchOptions) {
        launchOptions = options
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.applicationIconImage = Brand.appIconImage(size: 512)
        overlay = Overlay(shared: pipeline.shared)
        // Settings and the menu both change these; the overlay follows either.
        store.$showStats.sink { [weak self] on in self?.overlay.showStats = on; self?.refreshMenuSoon() }.store(in: &subscriptions)
        store.$showHints.sink { [weak self] on in self?.overlay.showHints = on; self?.refreshMenuSoon() }.store(in: &subscriptions)
        pipeline.apply(config: store.config)
        pipeline.camera.preferredDeviceID = store.preferredCameraID
        overlay.gestures = store.config.gestures
        store.onChange = { [weak self] cfg in
            self?.pipeline.apply(config: cfg)
            self?.overlay.gestures = cfg.gestures
            self?.applyVoice(cfg)
        }
        pipeline.output.onEvent = { [weak self] action in self?.handle(action) }

        modeBar.onKeyboard = { [weak self] in self?.keyboard.toggle() }
        modeBar.onExit = { [weak self] in self?.pipeline.setMode(.command) }
        keyboard.onVisibilityChange = { [weak self] frame in self?.modeBar.place(above: frame) }

        if !pipeline.inputMonitor.start() {
            NSLog("Sleight: input monitor unavailable (Accessibility not granted?)")
        }

        hotKeys = [
            HotKey(id: 1, keyCode: kVK_ANSI_S, modifiers: controlKey | optionKey) { [weak self] in self?.toggleActive() },
            HotKey(id: 2, keyCode: kVK_ANSI_P, modifiers: controlKey | optionKey) { [weak self] in self?.togglePointer() },
            HotKey(id: 3, keyCode: kVK_ANSI_K, modifiers: controlKey | optionKey) { [weak self] in self?.toggleKeyboard() },
            HotKey(id: 4, keyCode: kVK_ANSI_V, modifiers: controlKey | optionKey) { [weak self] in self?.voice.listenNow() },
        ]

        setupStatusItem()

        if let dir = launchOptions.snapshotDir {
            Snapshots.render(to: URL(fileURLWithPath: dir, isDirectory: true), injector: pipeline.injector,
                             monitor: pipeline.inputMonitor, store: store)
            NSApp.terminate(nil)
            return
        }
        if let seconds = launchOptions.recordSeconds {
            pipeline.dryRun = true
            overlay.enabled = false
            pipeline.start { [weak self] _ in
                guard let self else { return }
                let url = self.pipeline.record(seconds: seconds)
                DispatchQueue.main.asyncAfter(deadline: .now() + seconds + 0.5) {
                    print(url.path)
                    NSApp.terminate(nil)
                }
            }
            return
        }
        if launchOptions.selfTest { runSelfTest(); return }
        if let dir = launchOptions.transcribeDir {
            VoiceListener.transcribe(folder: URL(fileURLWithPath: dir)) { NSApp.terminate(nil) }
            return
        }
        if let seconds = launchOptions.benchmarkSeconds { runHeadlessBenchmark(seconds: seconds); return }

        checkPermissions()
        setupVoice()
        // With voice on, the camera waits to be asked for ("Jarvis, camera on").
        if store.config.cameraAtLaunch || !store.config.voiceEnabled {
            setEnabled(true)
        } else {
            overlay.flash(Chip(symbol: "waveform", title: "Listening", detail: nil, accent: true), seconds: 1.6)
        }
        idleTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.checkIdleCamera() }
        if !UserDefaults.standard.bool(forKey: "seenPractice") {
            UserDefaults.standard.set(true, forKey: "seenPractice")
            showPractice()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        pipeline.stop()
        voice.stop()
    }

    // MARK: Voice

    private func setupVoice() {
        voice.config = store.config
        voice.vocabulary = { AppIndex.names() + ShortcutsIndex.shared.all }
        voice.menuTitles = { [menus] in menus.titles }
        menus.onChange = { [weak self] in self?.voice.contextChanged() }
        voice.onState = { [weak self] state in
            guard let self else { return }
            switch state {
            case .listening(let said):
                self.overlay.voiceChip = Chip(symbol: "waveform", title: said.isEmpty ? "Listening" : said, detail: nil, accent: true)
            case .unavailable(let why):
                self.overlay.voiceChip = nil
                self.overlay.flash(Chip(symbol: "mic.slash", title: "Voice unavailable", detail: why, accent: true), seconds: 3)
            case .off, .waiting:
                self.overlay.voiceChip = self.scrollChip ?? self.sessionChip
            }
            self.refreshMenu()
        }
        voice.onMessage = { [weak self] text in
            self?.overlay.flash(Chip(symbol: "waveform", title: text, detail: nil, accent: true), seconds: 1.6)
        }
        voice.onIntent = { [weak self] intent in self?.perform(intent) }
        pipeline.output.onAutoScrollInterrupted = { [weak self] in self?.stopAutoScroll(say: false) }
        voice.onSession = { [weak self] on in
            guard let self else { return }
            self.sessionChip = on
                ? Chip(symbol: "waveform", title: "Listening", detail: nil, accent: true)
                : nil
            if !on { self.overlay.flash(Chip(symbol: "checkmark", title: "Done", detail: nil, accent: true)) }
            if case .listening = self.voice.state {} else { self.overlay.voiceChip = self.scrollChip ?? self.sessionChip }
        }
        pipeline.inputMonitor.onDoubleTap = { [weak self] in self?.toggleVoice() }
        applyVoice(store.config)
    }

    private func applyVoice(_ cfg: SleightConfig) {
        guard voice.onIntent != nil else { return }   // not set up (benchmark, snapshots…)
        voice.config = cfg
        pipeline.inputMonitor.doubleTapFlag = Self.flag(cfg.voiceDoubleTap)
        if cfg.voiceEnabled, !voice.running {
            voice.start()
        } else if !cfg.voiceEnabled, voice.running {
            voice.stop()
        }
        refreshMenu()
    }

    private static func flag(_ key: DoubleTapKey) -> CGEventFlags? {
        switch key {
        case .off: return nil
        case .option: return .maskAlternate
        case .command: return .maskCommand
        case .control: return .maskControl
        case .fn: return .maskSecondaryFn
        }
    }

    /// Voice mode on (listening for a command straight away) or off (mic closed).
    @objc func toggleVoice() {
        if !store.config.voiceEnabled { voice.listenOnStart = true }
        store.config.voiceEnabled.toggle()
        if !store.config.voiceEnabled {
            overlay.flash(Chip(symbol: "mic.slash", title: "Voice off", detail: nil, accent: true), seconds: 1.4)
        }
    }

    @objc func speakNow() { voice.listenNow() }

    // MARK: Continuous scrolling

    private func startAutoScroll(up: Bool) {
        if !autoScrolling { scrollLevel = 2 }
        autoScrolling = true
        scrollingUp = up
        voice.scrolling = true
        applyAutoScroll()
    }

    private func applyAutoScroll() {
        let speed = Self.scrollSpeeds[scrollLevel]
        // Wheel axis: negative = content moves up (reveals what's below).
        pipeline.output.setAutoScroll(Vec2(0, scrollingUp ? speed : -speed))
        scrollChip = Chip(symbol: scrollingUp ? "arrow.up" : "arrow.down",
                          title: "Scrolling", detail: "\(scrollLevel + 1)×", accent: true)
        overlay.voiceChip = scrollChip
    }

    private func stopAutoScroll(say: Bool) {
        guard autoScrolling else { return }
        autoScrolling = false
        voice.scrolling = false
        pipeline.output.setAutoScroll(nil)
        scrollChip = nil
        overlay.voiceChip = nil
        if say { overlay.flash(Chip(symbol: "stop.fill", title: "Stopped scrolling", detail: nil, accent: true)) }
    }

    /// Voice can bring the camera back, so it needn't run with nobody there.
    private func checkIdleCamera() {
        let now = CACurrentMediaTime()
        guard enabled, store.config.voiceEnabled, store.config.cameraIdleMinutes > 0, practice?.window?.isVisible != true else {
            lastHandSeen = now
            return
        }
        if pipeline.shared.hud.handsVisible > 0 { lastHandSeen = now }
        if now - lastHandSeen > store.config.cameraIdleMinutes * 60 {
            setEnabled(false)
            overlay.flash(Chip(symbol: "video.slash", title: "Camera off", detail: nil, accent: true), seconds: 1.6)
        }
    }

    private func perform(_ intent: VoiceIntent) {
        NSLog("Sleight voice intent: \(intent)")
        func say(_ symbol: String, _ title: String) {
            overlay.flash(Chip(symbol: symbol, title: title, detail: nil, accent: true))
        }
        switch intent {
        case .action(let a, let times) where autoScrolling && (a == .scrollUp || a == .scrollDown):
            _ = times
            startAutoScroll(up: a == .scrollUp)
        case .action(let a, let times):
            let actions = (0..<times).flatMap { _ in ActionMapper.fire(a, speed: nil, config: store.config) }
            pipeline.output.handle(actions, frameInterval: 0)
            if ![.screenshot, .screenshotSelection, .screenshotTool].contains(a) {
                say(GestureCatalog.symbol(a), times > 1 ? "\(a.title) ×\(times)" : a.title)
            }
        case .switchTo(let name):
            if let app = AppIndex.find(name) {
                AppIndex.open(app)
                say("arrow.up.forward.app", app.name)
            } else {
                say("questionmark.app", "No app called \"\(name)\"")
            }
        case .type(let text):
            // Only into a text field: typed keys anywhere else become shortcuts.
            guard Self.textFocus() != .notText else {
                overlay.flash(Chip(symbol: "character.cursor.ibeam", title: "No text field", detail: nil, accent: true), seconds: 2)
                return
            }
            pipeline.output.queue.async { [injector = pipeline.injector] in injector.type(text) }
            let preview = text.count > 40 ? String(text.prefix(40)) + "…" : text
            say("character.cursor.ibeam", preview)
        case .search(let query):
            pipeline.output.handle([.shortcut(.spotlight)], frameInterval: 0)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [injector = pipeline.injector, output = pipeline.output] in
                output.queue.async { injector.type(query) }
            }
        case .rest:
            pipeline.setActive(false)
        case .wake:
            if gesturesActive { say("sparkle", "Already awake") } else { pipeline.setActive(true) }
        case .cameraOn:
            if enabled { say("video", "Camera is on") } else { setEnabled(true) }
            if !gesturesActive { pipeline.setActive(true) }
        case .cameraOff:
            if enabled {
                setEnabled(false)
                say("video.slash", "Camera off")
            }
        case .menuItem(let title):
            if menus.press(title) { say("filemenu.and.selection", title) } else { say("questionmark", "Couldn't press \u{201C}\(title)\u{201D}") }
        case .openURL(let site):
            if let url = URL(string: "https://" + site) {
                NSWorkspace.shared.open(url)
                say("safari", site)
            }
        case .webSearch(let query):
            var c = URLComponents(string: "https://www.google.com/search")!
            c.queryItems = [URLQueryItem(name: "q", value: query)]
            if let url = c.url { NSWorkspace.shared.open(url); say("globe", query) }
        case .runShortcut(let name):
            if let match = ShortcutsIndex.shared.find(name) {
                ShortcutsIndex.run(match)
                say("square.2.layers.3d", match)
            } else {
                say("questionmark", "No shortcut called \u{201C}\(name)\u{201D}")
            }
        case .quit(let name):
            let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
            let names = running.compactMap(\.localizedName)
            if let hit = VoiceCommands.bestApp(for: name, in: names),
               let app = running.first(where: { $0.localizedName == hit }) {
                app.terminate()
                say("power", "Quit \(hit)")
            } else {
                say("questionmark.app", "\u{201C}\(name)\u{201D} isn't open")
            }
        case .setVolume(let level):
            NSAppleScript(source: "set volume output volume \(level)")?.executeAndReturnError(nil)
            say(level == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill", "Volume \(level)")
        case .pointerMode:
            if enabled { pipeline.setMode(.pointer) } else { say("video.slash", "Camera is off") }
        case .gestureMode:
            pipeline.setMode(.command)
        case .autoScroll(let up):
            startAutoScroll(up: up)
        case .scrollFaster(let steps):
            if autoScrolling { scrollLevel = min(scrollLevel + steps, Self.scrollSpeeds.count - 1); applyAutoScroll() }
        case .scrollSlower(let steps):
            if autoScrolling { scrollLevel = max(scrollLevel - steps, 0); applyAutoScroll() }
        case .stopScrolling:
            if autoScrolling { stopAutoScroll(say: true) }
        case .cancel:
            if autoScrolling { stopAutoScroll(say: true) }
        case .startSession, .endSession:
            break   // the listener runs conversation mode; its chip says so
        }
    }

    // MARK: Enable / modes

    @objc func toggleEnabled() { setEnabled(!enabled) }

    /// Rest / wake: the camera keeps watching, gestures stop (except 👏👏).
    @objc func toggleActive() {
        guard enabled else { setEnabled(true); return }
        pipeline.setActive(!gesturesActive)
    }

    private func updateMenuBarIcon() {
        statusItem.button?.image = Brand.menuBarImage(active: enabled && gesturesActive, pointer: mode == .pointer)
    }

    func setEnabled(_ on: Bool) {
        enabled = on
        overlay.enabled = on
        if on {
            pipeline.start { [weak self] ok in
                guard let self else { return }
                if ok {
                    self.gesturesActive = true
                    self.pipeline.setActive(true)
                    self.updateMenuBarIcon()
                    self.overlay.playIntro()
                } else {
                    self.enabled = false
                    self.overlay.flash(Chip(symbol: "video.slash", title: "Camera unavailable", detail: nil, accent: true), seconds: 2)
                }
                self.refreshMenu()
            }
        } else {
            pipeline.stop()
            modeBar.hide()
            keyboard.hide()
            mode = .command
        }
        updateMenuBarIcon()
        refreshMenu()
    }

    @objc func togglePointer() {
        guard enabled else { setEnabled(true); return }
        pipeline.setMode(mode == .pointer ? .command : .pointer)
    }

    private func handle(_ action: EngineAction) {
        practice?.handle(action)
        if let chip = Chip.flash(for: action, map: store.config.gestures) { overlay.flash(chip) }
        switch action {
        case .modeChanged(let m, _):
            mode = m
            if m == .pointer {
                modeBar.show()
            } else {
                modeBar.hide()
                keyboard.hide()
            }
            updateMenuBarIcon()
            refreshMenu()
        case .activeChanged(let on):
            gesturesActive = on
            voice.resting = !on
            updateMenuBarIcon()
            refreshMenu()
        case .mouseUp(.left, _, _):
            if mode == .pointer { showKeyboardIfTextFieldFocused() }
        case .toggleKeyboard:
            keyboard.toggle()
        default:
            break
        }
    }

    /// In pointer mode, clicking into a text field brings up the keyboard.
    private func showKeyboardIfTextFieldFocused() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, self.mode == .pointer, !self.keyboard.isVisible, Self.focusedElementIsText() else { return }
            self.keyboard.show()
        }
    }

    static func focusedElementIsText() -> Bool { textFocus() == .text }

    enum TextFocus { case text, notText, unknown }

    /// Is the keyboard focus somewhere text can go? Electron and Chromium apps
    /// (Claude, Slack, VS Code…) only describe themselves to Accessibility once
    /// asked to, so ask first. When it can't be told, say unknown, not no.
    static func textFocus() -> TextFocus {
        guard let front = NSWorkspace.shared.frontmostApplication else { return .unknown }
        let app = AXUIElementCreateApplication(front.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.3)
        var el = focusedElement(of: app)
        if el == nil || isContainer(el!) {
            AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            usleep(120_000)
            el = focusedElement(of: app) ?? el
        }
        guard let el else { return .unknown }
        if isText(el) { return .text }
        // A web area or group may hold a rich editor it doesn't describe.
        return isContainer(el) ? .unknown : .notText
    }

    private static func focusedElement(of app: AXUIElement) -> AXUIElement? {
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let f = focused, CFGetTypeID(f) == AXUIElementGetTypeID() else { return nil }
        return (f as! AXUIElement)
    }

    private static func role(_ el: AXUIElement) -> String? {
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &role)
        return role as? String
    }

    private static func isContainer(_ el: AXUIElement) -> Bool {
        ["AXWebArea", "AXGroup", "AXScrollArea", "AXWindow", "AXApplication", "AXUnknown"].contains(role(el) ?? "AXUnknown")
    }

    private static func isText(_ el: AXUIElement) -> Bool {
        let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]
        if let r = role(el), textRoles.contains(r) { return true }
        // Editable web content (contenteditable, rich editors).
        var editable: CFTypeRef?
        if AXUIElementCopyAttributeValue(el, "AXEditable" as CFString, &editable) == .success, (editable as? Bool) == true {
            return true
        }
        // A text cursor you can type at.
        var settable: DarwinBoolean = false
        var range: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, kAXSelectedTextRangeAttribute as CFString, &range) == .success
            && AXUIElementIsAttributeSettable(el, kAXValueAttribute as CFString, &settable) == .success && settable.boolValue
    }

    // MARK: Menu

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = Brand.menuBarImage(active: false)
        statusItem.button?.toolTip = "Sleight"

        let menu = NSMenu()
        menu.delegate = self
        statusLine.isEnabled = false
        qualityLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(qualityLine)
        menu.addItem(.separator())

        activeItem = item("Gestures Active", #selector(toggleActive), "s")
        activeItem.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(activeItem)
        pointerItem = item("Pointer Mode", #selector(togglePointer), "p")
        pointerItem.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(pointerItem)
        let kb = item("On-Screen Keyboard", #selector(toggleKeyboard), "k")
        kb.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(kb)

        voiceItem = item("Voice Commands", #selector(toggleVoice), "")
        menu.addItem(voiceItem)
        let talk = item("Speak a Command", #selector(speakNow), "v")
        talk.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(talk)

        enableItem = item("Camera On", #selector(toggleEnabled), "")
        menu.addItem(enableItem)
        let cameraItem = NSMenuItem(title: "Camera", action: nil, keyEquivalent: "")
        cameraItem.submenu = NSMenu()
        cameraItem.submenu?.delegate = self
        menu.addItem(cameraItem)

        menu.addItem(.separator())
        menu.addItem(item("Practice Gestures…", #selector(showPractice), ""))
        menu.addItem(item("Gesture Guide…", #selector(showGuide), "g"))
        menu.addItem(item("Camera Preview & Tuning…", #selector(showPreview), ""))
        menu.addItem(item("Settings…", #selector(showSettings), ","))
        hintsItem = item("Show Gesture Hints", #selector(toggleHints), "")
        menu.addItem(hintsItem)
        statsItem = item("Show Live Stats", #selector(toggleStats), "")
        menu.addItem(statsItem)
        menu.addItem(item("Run Latency Benchmark (10 s)", #selector(runBenchmarkFromMenu), ""))
        menu.addItem(.separator())
        menu.addItem(item("Quit Sleight", #selector(quit), "q"))
        statusItem.menu = menu
        refreshMenu()
    }

    private func item(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    func menuWillOpen(_ menu: NSMenu) {
        if menu == statusItem.menu {
            refreshMenu()
            menuTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.refreshMenu() }
            RunLoop.main.add(menuTimer!, forMode: .eventTracking)
        } else {
            rebuildCameraMenu(menu)
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        if menu == statusItem.menu { menuTimer?.invalidate(); menuTimer = nil }
    }

    private func refreshMenuSoon() {
        DispatchQueue.main.async { [weak self] in if self?.statusItem != nil { self?.refreshMenu() } }
    }

    private func refreshMenu() {
        enableItem.state = enabled ? .on : .off
        voiceItem.state = store.config.voiceEnabled ? .on : .off
        activeItem.state = enabled && gesturesActive ? .on : .off
        pointerItem.state = mode == .pointer ? .on : .off
        statsItem.state = store.showStats ? .on : .off
        hintsItem.state = store.showHints ? .on : .off
        let q = pipeline.shared.quality
        if !enabled {
            statusLine.title = store.config.voiceEnabled
                ? "Camera off · say \u{201C}\(store.config.wakeWord.phrase), camera on\u{201D}"
                : "Camera off · ⌃⌥S to start"
            qualityLine.title = "Camera is off"
        } else {
            statusLine.title = !gesturesActive ? "Resting · both hands up or ⌃⌥S to wake"
                : (mode == .pointer ? "Pointer mode · ✊ to exit" : "Active · both hands up to rest")
            let light = q.luma < 40 ? "dark" : (q.luma < 70 ? "dim" : "good")
            qualityLine.title = String(format: "%.0f fps · %.0f ms pipeline (p95 %.0f) · light %@",
                                       q.fps, q.latencyMs, q.latencyP95Ms, light)
        }
    }

    private func rebuildCameraMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let current = pipeline.camera.device?.uniqueID
        for d in CameraCapture.availableDevices() {
            let i = NSMenuItem(title: d.localizedName, action: #selector(pickCamera(_:)), keyEquivalent: "")
            i.target = self
            i.representedObject = d.uniqueID
            i.state = d.uniqueID == current ? .on : .off
            menu.addItem(i)
        }
    }

    @objc private func pickCamera(_ sender: NSMenuItem) {
        store.preferredCameraID = sender.representedObject as? String
        pipeline.camera.preferredDeviceID = store.preferredCameraID
        if enabled { pipeline.camera.restart() }
    }

    @objc private func toggleStats() {
        store.showStats.toggle()
        refreshMenu()
    }

    @objc private func toggleHints() {
        store.showHints.toggle()
        refreshMenu()
    }

    @objc func toggleKeyboard() { keyboard.toggle() }

    @objc func showSettings() {
        if settingsWindow == nil { settingsWindow = SettingsWindow.make(store: store) }
        present(settingsWindow!)
    }

    @objc func showGuide() {
        // Rebuilt each time so it shows the current assignments.
        guideWindow?.close()
        let window = GuideWindow.make(map: store.config.gestures, wakeWord: store.config.wakeWord, onPractice: { [weak self] in
            self?.guideWindow?.close()
            self?.showPractice()
        })
        guideWindow = window
        present(window)
    }

    @objc func showPractice() {
        if !enabled { setEnabled(true) }
        if practice == nil { practice = PracticeWindowController(pipeline: pipeline) }
        practice?.open(map: store.config.gestures)
    }

    @objc func showPreview() {
        if previewWindow == nil { previewWindow = PreviewWindowController(pipeline: pipeline) }
        if !enabled { setEnabled(true) }
        present(previewWindow!.window!)
    }

    private func present(_ w: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        w.center()
        w.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: Benchmark / self test

    @objc private func runBenchmarkFromMenu() {
        if !enabled { setEnabled(true) }
        overlay.flash(Chip(symbol: "stopwatch", title: "Benchmarking for 10 s…", detail: nil, accent: true), seconds: 2)
        pipeline.runBenchmark(seconds: 10) { [weak self] r in
            self?.saveBenchmark(r)
            let alert = NSAlert()
            alert.messageText = "Sleight latency benchmark"
            alert.informativeText = r.summary
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    private func saveBenchmark(_ r: BenchmarkResult) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(r) {
            try? data.write(to: Pipeline.supportDirectory.appendingPathComponent("benchmark.json"))
        }
        try? r.summary.write(to: Pipeline.supportDirectory.appendingPathComponent("benchmark.txt"), atomically: true, encoding: .utf8)
    }

    /// `--bench N`: the real pipeline without posting events; results to Application Support.
    private func runHeadlessBenchmark(seconds: Double) {
        pipeline.dryRun = true
        overlay.enabled = false
        pipeline.start { [weak self] ok in
            guard let self else { return }
            guard ok else {
                try? "camera failed to start".write(to: Pipeline.supportDirectory.appendingPathComponent("benchmark.txt"),
                                                    atomically: true, encoding: .utf8)
                NSApp.terminate(nil)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.pipeline.runBenchmark(seconds: seconds) { r in
                    self.saveBenchmark(r)
                    print(r.summary)
                    NSApp.terminate(nil)
                }
            }
        }
    }

    /// `--selftest`: permissions, and that our own events are recognised as ours.
    private func runSelfTest() {
        var lines: [String] = []
        lines.append("accessibility: \(AXIsProcessTrusted())")
        lines.append("camera: \(AVCaptureDevice.authorizationStatus(for: .video) == .authorized)")
        let p = EventInjector.currentCursor()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let before = self.pipeline.inputMonitor.lastRealInput
            self.pipeline.shared.setOutputCursor(p)
            self.pipeline.injector.move(to: p, delta: .zero)
            self.pipeline.shared.noteOwnScroll()
            self.pipeline.injector.scroll(Vec2(0, 0.4))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                let after = self.pipeline.inputMonitor.lastRealInput
                lines.append("own events ignored by monitor: \(before == after)")
                let report = lines.joined(separator: "\n")
                try? report.write(to: Pipeline.supportDirectory.appendingPathComponent("selftest.txt"), atomically: true, encoding: .utf8)
                print(report)
                NSApp.terminate(nil)
            }
        }
    }

    private func checkPermissions() {
        if !AXIsProcessTrusted() {
            let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
        }
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { _ in }
        }
    }
}

struct LaunchOptions {
    var benchmarkSeconds: Double?
    var recordSeconds: Double?
    var snapshotDir: String?
    var selfTest = false
    /// `--transcribe DIR`: print what on-device speech hears in each audio file (wake-word tuning).
    var transcribeDir: String?

    init(arguments: [String]) {
        var it = arguments.dropFirst().makeIterator()
        while let a = it.next() {
            switch a {
            case "--bench": benchmarkSeconds = it.next().flatMap(Double.init) ?? 10
            case "--record": recordSeconds = it.next().flatMap(Double.init) ?? 10
            case "--selftest": selfTest = true
            case "--snapshots": snapshotDir = it.next()
            case "--transcribe": transcribeDir = it.next()
            default: break
            }
        }
    }
}
