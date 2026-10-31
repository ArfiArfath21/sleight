import AppKit
import AVFoundation
import QuartzCore
import SleightCore

/// Live camera with the tracked skeleton and every number the engine sees.
/// The tool for tuning thresholds and for recording sessions to replay.
final class PreviewWindowController: NSWindowController, NSWindowDelegate {
    private let pipeline: Pipeline
    private let videoView: CameraSkeletonView
    private let info = NSTextField(labelWithString: "")
    private var recordButton: NSButton!
    private var recordingEnds: Date?

    init(pipeline: Pipeline) {
        self.pipeline = pipeline
        videoView = CameraSkeletonView(pipeline: pipeline)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 520),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "Sleight · Camera Preview & Tuning"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        guard let content = window?.contentView else { return }
        videoView.onTick = { [weak self] in
            guard let self else { return }
            let (hands, pose, _) = self.pipeline.shared.hands
            self.info.stringValue = self.infoText(pose: pose, hands: hands.count)
        }

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

    }

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
          mode \(hud.mode.rawValue)\(hud.cue.map { " · \($0.rawValue)" } ?? "")\(hud.warning.map { " · \($0.rawValue)" } ?? "")
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
              shape        \(p.shape(config: .default).rawValue)\(p.pinchCloses(config: .default) ? " · pinching" : "")
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
