import AVFoundation
import CoreMedia

/// Owns the AVCaptureSession. Tuned for latency, not image quality:
/// - picks the fastest frame rate at the smallest usable resolution
/// - pins min = max frame duration so auto exposure cannot halve the frame rate
///   in dim light (the image gets darker instead, which Vision copes with far
///   better than doubled latency)
/// - drops late frames instead of queueing them
final class CameraCapture: NSObject {
    let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "maestro.camera.session")
    private(set) var device: AVCaptureDevice?
    private(set) var activeFPS: Double = 0
    private(set) var dimensions = CMVideoDimensions(width: 0, height: 0)
    private(set) var frameRateLocked = false

    var onDevicesChanged: (() -> Void)?

    /// Preferred device unique ID, persisted by the app.
    var preferredDeviceID: String?
    var lockFrameRate = true

    init(delegate: AVCaptureVideoDataOutputSampleBufferDelegate, queue: DispatchQueue) {
        super.init()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        output.setSampleBufferDelegate(delegate, queue: queue)

        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(devicesChanged), name: AVCaptureDevice.wasConnectedNotification, object: nil)
        nc.addObserver(self, selector: #selector(devicesChanged), name: AVCaptureDevice.wasDisconnectedNotification, object: nil)
    }

    static func availableDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .continuityCamera, .external],
                                         mediaType: .video, position: .unspecified).devices
    }

    /// The user's pick if available; otherwise built-in, then external (Studio
    /// Display, lid closed), then Continuity Camera. An iPhone is never grabbed
    /// unasked, but it is the best choice when picked (60 fps).
    private func chooseDevice() -> AVCaptureDevice? {
        let devices = CameraCapture.availableDevices()
        if let id = preferredDeviceID, let d = devices.first(where: { $0.uniqueID == id }) { return d }
        func rank(_ d: AVCaptureDevice) -> Int {
            switch d.deviceType {
            case .builtInWideAngleCamera: return 0
            case .continuityCamera: return 2
            default: return 1
            }
        }
        return devices.min { rank($0) < rank($1) }
    }

    /// Smallest format of at least 640 wide, with the highest frame rate.
    private func chooseFormat(for device: AVCaptureDevice) -> (AVCaptureDevice.Format, Double)? {
        var best: (AVCaptureDevice.Format, Double, Int32)?
        for f in device.formats {
            let dim = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
            guard dim.width >= 640, dim.width >= dim.height else { continue }
            let maxFPS = f.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
            let fps = min(maxFPS, 60)
            if let b = best {
                if fps > b.1 + 0.5 || (abs(fps - b.1) < 0.5 && dim.width < b.2) { best = (f, fps, dim.width) }
            } else {
                best = (f, fps, dim.width)
            }
        }
        return best.map { ($0.0, $0.1) }
    }

    func start(completion: @escaping (Bool) -> Void) {
        sessionQueue.async { [self] in
            let ok = configure()
            if ok { session.startRunning(); applyFormat() }
            let running = session.isRunning
            DispatchQueue.main.async { completion(ok && running) }
        }
    }

    func stop() {
        sessionQueue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func restart() {
        sessionQueue.async { [self] in
            if session.isRunning { session.stopRunning() }
            if configure() { session.startRunning(); applyFormat() }
        }
    }

    private func configure() -> Bool {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        for input in session.inputs { session.removeInput(input) }

        guard let device = chooseDevice(),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return false }
        session.addInput(input)
        if !session.outputs.contains(output) {
            guard session.canAddOutput(output) else { return false }
            session.addOutput(output)
        }
        self.device = device
        // A small preset keeps the ISP from producing 1080p we would throw away.
        if session.canSetSessionPreset(.vga640x480) { session.sessionPreset = .vga640x480 }
        return true
    }

    /// On macOS the session preset re-applies its own format when the session
    /// starts, so the format and frame-rate lock are applied after startRunning.
    private func applyFormat() {
        guard let device else { return }
        if let (format, fps) = chooseFormat(for: device), (try? device.lockForConfiguration()) != nil {
            device.activeFormat = format
            let duration = CMTime(value: 1, timescale: CMTimeScale(fps.rounded()))
            device.activeVideoMinFrameDuration = duration
            if lockFrameRate {
                device.activeVideoMaxFrameDuration = duration
                frameRateLocked = true
            } else {
                frameRateLocked = false
            }
            device.unlockForConfiguration()
            activeFPS = fps
            dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        }

        // Keep the buffer at native size up to 960 wide; bigger only costs time.
        if dimensions.width > 960 {
            let w = 960, h = Int(Double(dimensions.height) * 960 / Double(dimensions.width))
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                                    kCVPixelBufferWidthKey as String: w, kCVPixelBufferHeightKey as String: h]
        }
    }

    @objc private func devicesChanged() {
        // Lid closed / Studio Display unplugged / iPhone walked away: re-pick.
        if self.session.isRunning, let d = device, !CameraCapture.availableDevices().contains(d) {
            restart()
        }
        DispatchQueue.main.async { self.onDevicesChanged?() }
    }
}
