import AppKit
import AVFoundation
import Carbon.HIToolbox
import SleightCore
import SleightBrand

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let store = ConfigStore()
    let pipeline = Pipeline()
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
        overlay.showStats = store.showStats
        overlay.showHints = store.showHints
        pipeline.apply(config: store.config)
        pipeline.camera.preferredDeviceID = store.preferredCameraID
        overlay.gestures = store.config.gestures
        store.onChange = { [weak self] cfg in
            self?.pipeline.apply(config: cfg)
            self?.overlay.gestures = cfg.gestures
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
        if let seconds = launchOptions.benchmarkSeconds { runHeadlessBenchmark(seconds: seconds); return }

        checkPermissions()
        setEnabled(true)
        if !UserDefaults.standard.bool(forKey: "seenPractice") {
            UserDefaults.standard.set(true, forKey: "seenPractice")
            showPractice()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        pipeline.stop()
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

    static func focusedElementIsText() -> Bool {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused, CFGetTypeID(element) == AXUIElementGetTypeID() else { return false }
        let el = element as! AXUIElement
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &role)
        let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]
        if let r = role as? String, textRoles.contains(r) { return true }
        // Editable web content (contenteditable, rich editors).
        var editable: CFTypeRef?
        if AXUIElementCopyAttributeValue(el, "AXEditable" as CFString, &editable) == .success, (editable as? Bool) == true {
            return true
        }
        return false
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

    private func refreshMenu() {
        enableItem.state = enabled ? .on : .off
        activeItem.state = enabled && gesturesActive ? .on : .off
        pointerItem.state = mode == .pointer ? .on : .off
        statsItem.state = store.showStats ? .on : .off
        hintsItem.state = store.showHints ? .on : .off
        let q = pipeline.shared.quality
        if !enabled {
            statusLine.title = "Camera off · ⌃⌥S to start"
            qualityLine.title = "Camera is off"
        } else {
            statusLine.title = !gesturesActive ? "Resting · 👏👏 or ⌃⌥S to wake"
                : (mode == .pointer ? "Pointer mode · ✊ to exit" : "Active · 👏👏 to rest")
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
        overlay.showStats = store.showStats
        refreshMenu()
    }

    @objc private func toggleHints() {
        store.showHints.toggle()
        overlay.showHints = store.showHints
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
        let window = GuideWindow.make(map: store.config.gestures, onPractice: { [weak self] in
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

    init(arguments: [String]) {
        var it = arguments.dropFirst().makeIterator()
        while let a = it.next() {
            switch a {
            case "--bench": benchmarkSeconds = it.next().flatMap(Double.init) ?? 10
            case "--record": recordSeconds = it.next().flatMap(Double.init) ?? 10
            case "--selftest": selfTest = true
            case "--snapshots": snapshotDir = it.next()
            default: break
            }
        }
    }
}
