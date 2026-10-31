import AVFoundation
import AppKit
import QuartzCore
import SleightCore

/// camera → Vision → engine → output, all on one high-priority serial queue,
/// with output on its own queue.
final class Pipeline: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let captureQueue = DispatchQueue(label: "sleight.capture", qos: .userInteractive)
    private(set) var camera: CameraCapture!
    let shared = SharedState()
    let injector = EventInjector()
    let output: OutputDriver
    let inputMonitor: InputMonitor
    private let tracker = VisionHandDetector()
    private let engine = SleightEngine()

    private(set) var running = false
    /// Benchmark mode: run everything except posting events.
    var dryRun = false { didSet { output.queue.async { [output, dryRun] in output.dryRun = dryRun } } }

    // Capture-queue state.
    private var lastPTS: Double?
    private var fpsStats = RollingStats(capacity: 90)
    private var visionStats = RollingStats(capacity: 240)
    private var latencyStats = RollingStats(capacity: 240)
    private var luma: Double = 128
    private var frameCount = 0
    private var recorder: FileHandle?
    private var recordUntil = 0.0
    private var benchmark: BenchmarkCollector?

    override init() {
        output = OutputDriver(injector: injector, shared: shared)
        inputMonitor = InputMonitor(shared: shared)
        super.init()
        camera = CameraCapture(delegate: self, queue: captureQueue)
        updateScreens()
        NotificationCenter.default.addObserver(self, selector: #selector(updateScreens),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    func apply(config: SleightConfig) {
        captureQueue.async { [engine] in engine.config = config }
        output.queue.async { [output] in output.config = config }
    }

    func start(completion: @escaping (Bool) -> Void) {
        camera.start { [weak self] ok in
            self?.running = ok
            completion(ok)
        }
    }

    func stop() {
        running = false
        camera.stop()
        let actions = captureQueue.sync { engine.shutdown() }
        output.handle(actions, frameInterval: 0)
        output.releaseAll()
        shared.setFrame(hud: HUDState(), hands: [], pose: nil, aspect: 4.0 / 3.0)
        shared.clearOutputCursor()
    }

    /// Active ↔ resting (camera keeps running).
    func setActive(_ on: Bool) {
        captureQueue.async { [self] in
            output.handle(engine.setActive(on, time: CACurrentMediaTime()), frameInterval: 0)
        }
    }

    /// Switch between command and pointer mode (menu / hotkey / mode bar).
    func setMode(_ mode: Mode) {
        let cursor = EventInjector.currentCursor()
        captureQueue.async { [self] in
            output.handle(engine.setMode(mode, systemCursor: cursor, time: CACurrentMediaTime()), frameInterval: 0)
        }
    }

    @objc private func updateScreens() {
        let screens = NSScreen.screens
        guard let primary = screens.first else { return }
        let h = primary.frame.height
        let rects = screens.map { s in
            ScreenRect(x: s.frame.minX, y: h - s.frame.maxY, width: s.frame.width, height: s.frame.height)
        }
        captureQueue.async { [engine] in engine.screens = ScreenLayout(screens: rects) }
    }

    // MARK: Recording

    static var supportDirectory: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Sleight", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Records raw hand frames as JSON lines for `seconds`; returns the file URL.
    func record(seconds: Double) -> URL {
        let dir = Pipeline.supportDirectory.appendingPathComponent("recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let url = dir.appendingPathComponent("\(f.string(from: Date())).jsonl")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try? FileHandle(forWritingTo: url)
        captureQueue.async { [self] in
            recorder = handle
            recordUntil = CACurrentMediaTime() + seconds
        }
        return url
    }

    // MARK: Benchmark

    func runBenchmark(seconds: Double, completion: @escaping (BenchmarkResult) -> Void) {
        captureQueue.async { [self] in
            benchmark = BenchmarkCollector(until: CACurrentMediaTime() + seconds, completion: completion)
        }
    }

    // MARK: Frames

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let arrival = CACurrentMediaTime()
        let ptsRaw = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        // Capture timestamps are on the host clock; fall back to arrival time if not.
        let pts = (ptsRaw.isFinite && abs(arrival - ptsRaw) < 0.5) ? ptsRaw : arrival

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let aspect = Double(width) / Double(max(height, 1))

        let hands = tracker.detect(in: pixelBuffer, aspect: aspect)
        let afterVision = CACurrentMediaTime()

        frameCount += 1
        if frameCount % 10 == 1 { luma = lerp(luma, meanLuma(pixelBuffer), frameCount == 1 ? 1 : 0.5) }

        let input = FrameInput(time: pts, hands: hands, aspect: aspect,
                               systemCursor: EventInjector.currentCursor(),
                               lastRealInput: inputMonitor.lastRealInput)
        let out = engine.process(input)

        let interval: Double
        if let last = lastPTS, pts > last { interval = pts - last; fpsStats.add(1 / interval) } else { interval = 1.0 / 30 }
        lastPTS = pts
        self.output.handle(out.actions, frameInterval: interval)

        let done = CACurrentMediaTime()
        visionStats.add((afterVision - arrival) * 1000)
        latencyStats.add((done - pts) * 1000)

        var hud = out.hud
        let fps = fpsStats.mean
        if hud.active, hud.warning == nil, hud.handsVisible > 0 || hud.mode == .pointer {
            if luma < 40 { hud.warning = .lowLight } else if fps > 0, fps < camera.activeFPS * 0.7 { hud.warning = .lowFPS }
        }
        shared.setFrame(hud: hud, hands: hands, pose: out.pose, aspect: aspect)

        if frameCount % 5 == 0 {
            var q = QualitySnapshot()
            q.fps = fps
            q.targetFPS = camera.activeFPS
            q.visionMs = visionStats.mean
            q.latencyMs = latencyStats.mean
            q.latencyP95Ms = latencyStats.percentile(0.95)
            q.luma = luma
            q.frameRateLocked = camera.frameRateLocked
            q.cameraName = camera.device?.localizedName ?? ""
            q.resolution = "\(width)×\(height)"
            shared.setQuality(q)
        }

        if let rec = recorder {
            if arrival > recordUntil {
                try? rec.close()
                recorder = nil
            } else if let line = try? JSONEncoder().encode(RecordedFrame(time: pts, aspect: aspect, hands: hands)) {
                rec.write(line)
                rec.write(Data([UInt8(ascii: "\n")]))
            }
        }

        if var b = benchmark {
            b.add(vision: (afterVision - arrival) * 1000, latency: (done - pts) * 1000,
                  queueDelay: (arrival - pts) * 1000, hands: hands.count, luma: luma)
            if arrival >= b.until {
                b.finish(fps: fps, camera: camera.device?.localizedName ?? "?", resolution: "\(width)×\(height)",
                         targetFPS: camera.activeFPS, locked: camera.frameRateLocked)
                benchmark = nil
            } else {
                benchmark = b
            }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if var b = benchmark { b.dropped += 1; benchmark = b }
    }
}

struct BenchmarkResult: Codable {
    var camera: String
    var resolution: String
    var targetFPS: Double
    var measuredFPS: Double
    var frameRateLocked: Bool
    var frames: Int
    var droppedFrames: Int
    var framesWithHands: Int
    var visionMsMean: Double
    var visionMsP95: Double
    /// Capture timestamp → engine output posted.
    var pipelineMsMean: Double
    var pipelineMsP50: Double
    var pipelineMsP95: Double
    /// Capture timestamp → frame delivered to us (camera + driver delay).
    var deliveryMsMean: Double
    var meanLuma: Double

    var summary: String {
        """
        Camera: \(camera) \(resolution) @ \(Int(targetFPS)) fps target (\(frameRateLocked ? "locked" : "auto")), measured \(String(format: "%.1f", measuredFPS)) fps
        Frames: \(frames) (\(droppedFrames) dropped, \(framesWithHands) with a hand)
        Vision: \(String(format: "%.1f", visionMsMean)) ms mean, \(String(format: "%.1f", visionMsP95)) ms p95
        Capture → event posted: \(String(format: "%.1f", pipelineMsMean)) ms mean, p50 \(String(format: "%.1f", pipelineMsP50)), p95 \(String(format: "%.1f", pipelineMsP95))
        Delivery delay: \(String(format: "%.1f", deliveryMsMean)) ms · Brightness: \(Int(meanLuma))/255
        (Add ~half a frame of exposure and one display refresh for true motion-to-photon.)
        """
    }
}

struct BenchmarkCollector {
    let until: Double
    let completion: (BenchmarkResult) -> Void
    var vision = RollingStats(capacity: 100_000)
    var latency = RollingStats(capacity: 100_000)
    var delivery = RollingStats(capacity: 100_000)
    var frames = 0
    var dropped = 0
    var withHands = 0
    var lumaSum = 0.0

    init(until: Double, completion: @escaping (BenchmarkResult) -> Void) {
        self.until = until
        self.completion = completion
    }

    mutating func add(vision v: Double, latency l: Double, queueDelay q: Double, hands: Int, luma: Double) {
        frames += 1
        vision.add(v); latency.add(l); delivery.add(q)
        if hands > 0 { withHands += 1 }
        lumaSum += luma
    }

    func finish(fps: Double, camera: String, resolution: String, targetFPS: Double, locked: Bool) {
        let r = BenchmarkResult(camera: camera, resolution: resolution, targetFPS: targetFPS, measuredFPS: fps,
                                frameRateLocked: locked, frames: frames, droppedFrames: dropped,
                                framesWithHands: withHands,
                                visionMsMean: vision.mean, visionMsP95: vision.percentile(0.95),
                                pipelineMsMean: latency.mean, pipelineMsP50: latency.percentile(0.5),
                                pipelineMsP95: latency.percentile(0.95),
                                deliveryMsMean: delivery.mean, meanLuma: frames > 0 ? lumaSum / Double(frames) : 0)
        DispatchQueue.main.async { completion(r) }
    }
}
