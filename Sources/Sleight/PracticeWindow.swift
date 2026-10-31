import SwiftUI
import AppKit
import SleightCore
import SleightBrand

/// Practice: live camera with your hand skeleton, every gesture explained in
/// plain words, and each one lighting up when Sleight recognises it. Nothing
/// happens on the Mac while this window is open. Hand landmarks (no video) are
/// recorded meanwhile, so thresholds can be tuned to real hands.
final class PracticeModel: ObservableObject {
    @Published var counts: [String: Int] = [:]
    @Published var lastHit: String?
    @Published var lastHitAt = Date.distantPast
    @Published var seeing = ""

    func hit(_ id: String) {
        counts[id, default: 0] += 1
        lastHit = id
        lastHitAt = Date()
    }
}

final class PracticeWindowController: NSWindowController, NSWindowDelegate {
    let model = PracticeModel()
    private let pipeline: Pipeline
    private let camera: CameraSkeletonView
    private var recording: URL?
    var onOpen: (() -> Void)?
    var onClose: (() -> Void)?

    init(pipeline: Pipeline) {
        self.pipeline = pipeline
        camera = CameraSkeletonView(pipeline: pipeline)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 720),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "Sleight · Practice"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView: PracticeView(model: model, camera: camera))
        camera.onTick = { [weak self] in self?.updateSeeing() }
    }

    required init?(coder: NSCoder) { fatalError() }

    func open() {
        model.counts = [:]
        model.lastHit = nil
        pipeline.dryRun = true
        recording = pipeline.startRecording(prefix: "practice-")
        onOpen?()
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        pipeline.dryRun = false
        pipeline.stopRecording()
        onClose?()
    }

    func handle(_ action: EngineAction, natural: Bool) {
        guard window?.isVisible == true, let id = GestureCatalog.gestureID(for: action, natural: natural) else { return }
        model.hit(id)
    }

    private var lastSeeing = ""

    private func updateSeeing() {
        let hud = pipeline.shared.hud
        let (_, pose, _) = pipeline.shared.hands
        var parts: [String] = []
        switch hud.handsVisible {
        case 0: parts.append("No hand in view")
        case 1: parts.append("1 hand")
        default: parts.append("\(hud.handsVisible) hands")
        }
        if let p = pose {
            let shape: String
            switch p.shape(config: .default) {
            case .open: shape = "open hand ✋"
            case .vee: shape = "peace sign ✌️"
            case .point: shape = p.isFrameL(config: .default) ? "L shape" : "pointing ☝️"
            case .fist: shape = "fist ✊"
            case .other: shape = p.pinchCloses(config: .default) ? "pinch 🤏" : "in between"
            }
            parts.append(shape)
        }
        if !hud.active { parts.append("resting") }
        if hud.mode == .pointer { parts.append("pointer mode") }
        if let cue = hud.cue { parts.append("ready: \(Chip.cue(cue, progress: 0, active: hud.active).title)") }
        let text = parts.joined(separator: "  ·  ")
        if text != lastSeeing {
            lastSeeing = text
            model.seeing = text
        }
    }
}

private struct CameraRepresentable: NSViewRepresentable {
    let view: CameraSkeletonView
    func makeNSView(context: Context) -> CameraSkeletonView { view }
    func updateNSView(_ nsView: CameraSkeletonView, context: Context) {}
}

struct PracticeView: View {
    @ObservedObject var model: PracticeModel
    /// nil renders a placeholder (snapshots).
    let camera: CameraSkeletonView?

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Group {
                    if let camera { CameraRepresentable(view: camera) } else { Color.black }
                }
                .aspectRatio(4.0 / 3.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                Text(model.seeing.isEmpty ? "Looking…" : model.seeing)
                    .font(.system(.body, design: .rounded).weight(.medium))
                if let id = model.lastHit, let g = GestureCatalog.all.first(where: { $0.id == id }),
                   Date().timeIntervalSince(model.lastHitAt) < 3 {
                    Label("\(g.title.trimmingCharacters(in: .whitespaces)) → \(g.effect)", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Color(cgColor: Brand.gold))
                        .font(.headline)
                }
                Spacer()
                Text("Nothing happens on your Mac while this window is open, so try anything. Yellow dots are the joints Sleight sees: if a hand has no skeleton, Sleight can't see it (move it up into view, add light).")
                    .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            .frame(width: 460)

            Divider()

            ScrollView { PracticeList(model: model).padding(20) }
        }
        .frame(minWidth: 960, minHeight: 640)
    }
}

struct PracticeList: View {
    @ObservedObject var model: PracticeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(GestureCatalog.groups, id: \.self) { group in
                VStack(alignment: .leading, spacing: 10) {
                    Text(group.uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(cgColor: Brand.gold))
                    ForEach(GestureCatalog.all.filter { $0.group == group }) { g in
                        GestureRow(info: g, count: model.counts[g.id] ?? 0,
                                   flash: model.lastHit == g.id && Date().timeIntervalSince(model.lastHitAt) < 1.5)
                    }
                }
            }
        }
    }
}

private struct GestureRow: View {
    let info: GestureInfo
    let count: Int
    let flash: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(info.title).font(.headline)
                    Text("→ \(info.effect)").foregroundStyle(.secondary)
                }
                Text(info.how).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            ZStack {
                Circle().fill(count > 0 ? Color(cgColor: Brand.gold) : Color.secondary.opacity(0.15))
                    .frame(width: 30, height: 30)
                if count > 0 {
                    Text("\(count)").font(.caption.weight(.bold)).foregroundStyle(.black)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12)
            .fill(flash ? Color(cgColor: Brand.gold).opacity(0.18) : Color.secondary.opacity(0.06)))
        .animation(.easeOut(duration: 0.25), value: flash)
    }
}
