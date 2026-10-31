import AppKit
import AVFoundation
import QuartzCore
import SleightCore

/// Live mirrored camera with the tracked hand skeletons drawn on top. Used by the
/// Preview and Practice windows. `onTick` fires on every display refresh.
final class CameraSkeletonView: NSView {
    private let pipeline: Pipeline
    private let previewLayer: AVCaptureVideoPreviewLayer
    private let skeleton = CAShapeLayer()
    private let joints = CAShapeLayer()
    private let anchorLayer = CAShapeLayer()
    private var link: CADisplayLink?
    var onTick: (() -> Void)?

    init(pipeline: Pipeline) {
        self.pipeline = pipeline
        previewLayer = AVCaptureVideoPreviewLayer(session: pipeline.camera.session)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        previewLayer.videoGravity = .resizeAspect
        if let conn = previewLayer.connection, conn.isVideoMirroringSupported {
            conn.automaticallyAdjustsVideoMirroring = false
            conn.isVideoMirrored = true
        }
        layer?.addSublayer(previewLayer)
        for l in [skeleton, joints, anchorLayer] {
            l.isGeometryFlipped = true
            l.actions = ["path": NSNull(), "position": NSNull(), "bounds": NSNull()]
            layer?.addSublayer(l)
        }
        skeleton.strokeColor = NSColor(white: 1, alpha: 0.85).cgColor
        skeleton.lineWidth = 2
        skeleton.fillColor = nil
        joints.fillColor = NSColor.systemYellow.cgColor
        anchorLayer.fillColor = NSColor.systemPurple.cgColor
        anchorLayer.strokeColor = NSColor.white.cgColor
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        link?.invalidate()
        link = nil
        guard window != nil else { return }
        let l = displayLink(target: self, selector: #selector(tick))
        l.add(to: .main, forMode: .common)
        link = l
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
        previewLayer.frame = bounds
        for l in [skeleton, joints, anchorLayer] { l.frame = bounds }

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
        onTick?()
    }

    private func videoRect(aspect: Double) -> CGRect {
        let b = bounds
        guard b.width > 0, b.height > 0 else { return .zero }
        if b.width / b.height > aspect {
            let w = b.height * aspect
            return CGRect(x: (b.width - w) / 2, y: 0, width: w, height: b.height)
        } else {
            let h = b.width / aspect
            return CGRect(x: 0, y: (b.height - h) / 2, width: b.width, height: h)
        }
    }
}
