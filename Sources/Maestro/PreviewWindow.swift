import AppKit
import AVFoundation
import QuartzCore
import MaestroCore

/// Live camera with the tracked skeleton and every number the engine sees.
/// The tool for tuning thresholds and for recording sessions to replay.
final class PreviewWindowController: NSWindowController, NSWindowDelegate {
    private let pipeline: Pipeline
    private let previewLayer: AVCaptureVideoPreviewLayer
    private let skeleton = CAShapeLayer()
    private let joints = CAShapeLayer()
    private let anchorLayer = CAShapeLayer()
    private let videoView = NSView()
    private let info = NSTextField(labelWithString: "")
    private var link: CADisplayLink?
    private var recordButton: NSButton!
    private var recordingEnds: Date?

    init(pipeline: Pipeline) {
        self.pipeline = pipeline
        previewLayer = AVCaptureVideoPreviewLayer(session: pipeline.camera.session)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 520),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "Maestro · Camera Preview & Tuning"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        guard let content = window?.contentView else { return }
        videoView.wantsLayer = true
        videoView.layer?.backgroundColor = NSColor.black.cgColor
        previewLayer.videoGravity = .resizeAspect
        if let conn = previewLayer.connection, conn.isVideoMirroringSupported {
            conn.automaticallyAdjustsVideoMirroring = false
            conn.isVideoMirrored = true
        }
        videoView.layer?.addSublayer(previewLayer)
        for l in [skeleton, joints, anchorLayer] {
            l.isGeometryFlipped = true
            l.actions = ["path": NSNull(), "position": NSNull(), "bounds": NSNull()]
            videoView.layer?.addSublayer(l)
        }
        skeleton.strokeColor = NSColor(white: 1, alpha: 0.85).cgColor
        skeleton.lineWidth = 2
        skeleton.fillColor = nil
        joints.fillColor = NSColor.systemYellow.cgColor
        anchorLayer.fillColor = NSColor.systemPurple.cgColor
        anchorLayer.strokeColor = NSColor.white.cgColor

        info.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        info.maximumNumberOfLines = 0
        info.lineBreakMode = .byWordWrapping

        recordButton = NSButton(title: "Record 20 s", target: self, action: #selector(record))
        let folder = NSButton(title: "Show recordings", target: self, action: #selector(showRecordings))
        let buttons = NSStackView(views: [recordButton, folder])
        buttons.orientation = .horizontal

        let side = NSStackView(views: [info, buttons])
        side.orientation = .vertical
        side.alignment = .leading
        side.spacing = 14
        side.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

        let split = NSStackView(views: [videoView, side])
        split.orientation = .horizontal
        split.spacing = 0
        split.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(split)
        NSLayoutConstraint.activate([
            split.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            split.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            split.topAnchor.constraint(equalTo: content.topAnchor),
            split.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            side.widthAnchor.constraint(equalToConstant: 320),
            videoView.widthAnchor.constraint(greaterThanOrEqualToConstant: 480),
        ])

        let l = content.displayLink(target: self, selector: #selector(tick))
        l.add(to: .main, forMode: .common)
        link = l
    }

    func windowWillClose(_ notification: Notification) { link?.isPaused = true }
    func windowDidBecomeKey(_ notification: Notification) { link?.isPaused = false }

    @objc private func record() {
        let url = pipeline.record(seconds: 20)
        recordingEnds = Date().addingTimeInterval(20)
        recordButton.isEnabled = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 20.2) { [weak self] in
            self?.recordButton.isEnabled = true
            self?.recordButton.title = "Saved \(url.lastPathComponent)"
            self?.recordingEnds = nil
        }
    }

    @objc private func showRecordings() {
        let dir = Pipeline.supportDirectory.appendingPathComponent("recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    private static let bones: [(Joint, Joint)] = {
        var b: [(Joint, Joint)] = [(.wrist, .thumbCMC), (.thumbCMC, .thumbMP), (.thumbMP, .thumbIP), (.thumbIP, .thumbTip),
                                   (.indexMCP, .middleMCP), (.middleMCP, .ringMCP), (.ringMCP, .littleMCP)]
        for f in Finger.allCases {
            let base = f.mcp.rawValue
            b.append((.wrist, f.mcp))
            for k in 0..<3 { b.append((Joint(rawValue: base + k)!, Joint(rawValue: base + k + 1)!)) }
        }
        return b
    }()

    @objc private func tick() {
        guard window?.isVisible == true else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.frame = videoView.bounds
        for l in [skeleton, joints, anchorLayer] { l.frame = videoView.bounds }

        let (hands, pose, aspect) = pipeline.shared.hands
        let rect = videoRect(aspect: aspect)
        func map(_ p: Vec2) -> CGPoint {
            CGPoint(x: rect.minX + p.x / aspect * rect.width, y: rect.minY + p.y * rect.height)
        }
        let bonesPath = CGMutablePath(), jointsPath = CGMutablePath()
        for h in hands {
            for (a, b) in Self.bones {
                if let pa = h[a], let pb = h[b], pa.confidence > 0.2, pb.confidence > 0.2 {
                    bonesPath.move(to: map(pa.position)); bonesPath.addLine(to: map(pb.position))
                }
            }
            for case let p? in h.points where p.confidence > 0.2 {
                let c = map(p.position)
                jointsPath.addEllipse(in: CGRect(x: c.x - 3, y: c.y - 3, width: 6, height: 6))
            }
        }
        skeleton.path = bonesPath
        joints.path = jointsPath
        if let pose {
            let c = map(pose.anchor)
            anchorLayer.path = CGPath(ellipseIn: CGRect(x: c.x - 7, y: c.y - 7, width: 14, height: 14), transform: nil)
        } else {
            anchorLayer.path = nil
        }
        CATransaction.commit()

        info.stringValue = infoText(pose: pose, hands: hands.count)
    }

    private func videoRect(aspect: Double) -> CGRect {
        let b = videoView.bounds
        guard b.width > 0, b.height > 0 else { return .zero }
        let viewAspect = b.width / b.height
        if viewAspect > aspect {
            let w = b.height * aspect
            return CGRect(x: (b.width - w) / 2, y: 0, width: w, height: b.height)
        } else {
            let h = b.width / aspect
            return CGRect(x: 0, y: (b.height - h) / 2, width: b.width, height: h)
        }
    }

    private func infoText(pose: HandPose?, hands: Int) -> String {
        let q = pipeline.shared.quality
        let hud = pipeline.shared.hud
        var s = """
        CAMERA
          \(q.cameraName)
          \(q.resolution) · \(String(format: "%.1f", q.fps)) / \(Int(q.targetFPS)) fps \(q.frameRateLocked ? "(locked)" : "")
          brightness \(Int(q.luma))/255 \(q.luma < 40 ? "· TOO DARK" : (q.luma < 70 ? "· dim" : ""))

        LATENCY
          vision    \(String(format: "%5.1f", q.visionMs)) ms
          pipeline  \(String(format: "%5.1f", q.latencyMs)) ms  (p95 \(String(format: "%.1f", q.latencyP95Ms)))

        STATE
          \(hud.mode.rawValue)\(hud.hint.map { " · hint: \($0.rawValue)" } ?? "")
          hands seen \(hands)
        """
        if let p = pose {
            let fingers = zip(["index", "middle", "ring", "little"], p.extensionRatio).map { name, r in
                "  \(name.padding(toLength: 7, withPad: " ", startingAt: 0)) \(r.map { String(format: "%.2f", $0) } ?? "  — ")"
            }.joined(separator: "\n")
            s += """


            HAND (\(p.frame.chirality.rawValue))
              confidence   \(String(format: "%.2f", p.confidence))
              scale        \(String(format: "%.3f", p.scale))
              pinch index  \(String(format: "%.2f", p.pinchIndex))
              pinch middle \(String(format: "%.2f", p.pinchMiddle))
              orientation  \(String(format: "%+.2f", p.orientation))
              open palm \(p.isOpenPalm ? "yes" : "no") · fist \(p.isFist(config: .default) ? "yes" : "no") · peace \(p.isPeace ? "yes" : "no")
            FINGER EXTENSION (>1.6 up, <1.3 curled)
            \(fingers)
            """
        }
        if let end = recordingEnds {
            s += "\n\n● RECORDING \(Int(end.timeIntervalSinceNow.rounded(.up))) s"
        }
        return s
    }
}
