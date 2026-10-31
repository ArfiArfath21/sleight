import AppKit
import AVFoundation
import Carbon.HIToolbox
import MaestroCore
import MaestroBrand

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let store = ConfigStore()
    let pipeline = Pipeline()
    private(set) var overlay: Overlay!
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private var statusLine = NSMenuItem()
    private var qualityLine = NSMenuItem()
    private var enableItem = NSMenuItem()
    private var statsItem = NSMenuItem()
    private var menuTimer: Timer?
    private var engaged = false
    private(set) var enabled = false

    lazy var keyboard = KeyboardPanelController(injector: pipeline.injector, monitor: pipeline.inputMonitor)
    private var settingsWindow: NSWindow?
    private var previewWindow: PreviewWindowController?
    private var guideWindow: NSWindow?

    let launchOptions: LaunchOptions

    init(options: LaunchOptions) {
        launchOptions = options
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.applicationIconImage = Brand.appIconImage(size: 512)
        overlay = Overlay(shared: pipeline.shared)
        overlay.showStats = store.showStats
        pipeline.apply(config: store.config)
        pipeline.camera.preferredDeviceID = store.preferredCameraID
        store.onChange = { [weak self] cfg in self?.pipeline.apply(config: cfg) }

        pipeline.output.onEvent = { [weak self] action in self?.handle(action) }

        if !pipeline.inputMonitor.start() {
            NSLog("Maestro: input monitor unavailable (Accessibility not granted?)")
        }

        hotKey = HotKey(keyCode: kVK_ANSI_M, modifiers: controlKey | optionKey) { [weak self] in self?.toggleEnabled() }

        setupStatusItem()

        if let seconds = launchOptions.benchmarkSeconds {
            runHeadlessBenchmark(seconds: seconds)
            return
        }
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
        if launchOptions.selfTest {
            runSelfTest()
            return
        }

        checkPermissions()
        setEnabled(true)
        if !UserDefaults.standard.bool(forKey: "seenGuide") {
            UserDefaults.standard.set(true, forKey: "seenGuide")
            showGuide()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        pipeline.stop()
    }

    // MARK: Enable / disable

    @objc func toggleEnabled() { setEnabled(!enabled) }

    func setEnabled(_ on: Bool) {
        enabled = on
        overlay.enabled = on
        if on {
            pipeline.start { [weak self] ok in
                guard let self else { return }
                if !ok {
                    self.enabled = false
                    self.overlay.toast("Camera unavailable")
                } else {
                    self.overlay.toast("Maestro on · raise an open palm")
                }
                self.refreshMenu()
            }
        } else {
            pipeline.stop()
            overlay.toast("Maestro off")
        }
        refreshMenu()
    }

    private func handle(_ action: EngineAction) {
        switch action {
        case .engaged:
            engaged = true
            statusItem.button?.image = Brand.menuBarImage(engaged: true)
        case .disengaged(let reason):
            engaged = false
            statusItem.button?.image = Brand.menuBarImage()
            if reason == .userInput { /* silent: the user is typing */ }
        case .swipe(let dir):
            switch dir {
            case .left: overlay.toast("Next Space  →")
            case .right: overlay.toast("←  Previous Space")
            case .up: overlay.toast("Mission Control")
            }
        case .toggleKeyboard:
            keyboard.toggle()
        default:
            break
        }
    }

    // MARK: Menu

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = Brand.menuBarImage()
        statusItem.button?.toolTip = "Maestro"

        let menu = NSMenu()
        menu.delegate = self
        statusLine.isEnabled = false
        qualityLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(qualityLine)
        menu.addItem(.separator())

        enableItem = NSMenuItem(title: "Hand Control", action: #selector(toggleEnabled), keyEquivalent: "m")
        enableItem.keyEquivalentModifierMask = [.control, .option]
        enableItem.target = self
        menu.addItem(enableItem)

        let cameraItem = NSMenuItem(title: "Camera", action: nil, keyEquivalent: "")
        cameraItem.submenu = NSMenu()
        cameraItem.submenu?.delegate = self
        cameraItem.tag = 42
        menu.addItem(cameraItem)

        menu.addItem(.separator())
        menu.addItem(item("On-Screen Keyboard", #selector(toggleKeyboard), "k"))
        menu.addItem(item("Camera Preview & Tuning…", #selector(showPreview), "p"))
        menu.addItem(item("Settings…", #selector(showSettings), ","))
        menu.addItem(item("Gesture Guide…", #selector(showGuide), "g"))
        statsItem = item("Show Live Stats", #selector(toggleStats), "")
        menu.addItem(statsItem)
        menu.addItem(item("Run Latency Benchmark (10 s)", #selector(runBenchmarkFromMenu), ""))
        menu.addItem(.separator())
        menu.addItem(item("Quit Maestro", #selector(quit), "q"))
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
        statsItem.state = store.showStats ? .on : .off
        let q = pipeline.shared.quality
        if !enabled {
            statusLine.title = "Off · ⌃⌥M to turn on"
            qualityLine.title = "Camera is off"
        } else {
            statusLine.title = engaged ? "Engaged · conducting" : "Watching · raise an open palm"
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

    @objc func toggleKeyboard() { keyboard.toggle() }

    @objc func showSettings() {
        if settingsWindow == nil { settingsWindow = SettingsWindow.make(store: store) }
        present(settingsWindow!)
    }

    @objc func showGuide() {
        if guideWindow == nil { guideWindow = GuideWindow.make() }
        present(guideWindow!)
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
        overlay.toast("Benchmarking for 10 s…")
        pipeline.runBenchmark(seconds: 10) { [weak self] r in
            self?.saveBenchmark(r)
            let alert = NSAlert()
            alert.messageText = "Maestro latency benchmark"
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

    /// `--bench N`: measure the real pipeline without posting any events, write
    /// the results to Application Support, quit.
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
            // Let auto exposure settle before measuring.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.pipeline.runBenchmark(seconds: seconds) { r in
                    self.saveBenchmark(r)
                    print(r.summary)
                    NSApp.terminate(nil)
                }
            }
        }
    }

    /// `--selftest`: checks that our injected events are recognised as ours by
    /// the input monitor (otherwise hand control would keep pausing itself).
    /// Moves the cursor by zero pixels, so it is invisible.
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
            self.pipeline.injector.scroll(.zero, phase: nil)
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
